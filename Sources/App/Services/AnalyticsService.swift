import Foundation
import Vapor
import Fluent
import SQLKit

// MARK: - Cleanup state tracker

/// Tracks the last time cleanup was run so it is only attempted once per day.
actor AnalyticsCleanupTracker {
    static let shared = AnalyticsCleanupTracker()
    private var lastCleanup: Date = .distantPast

    /// Returns `true` (and marks the new timestamp) if cleanup should be run now.
    func shouldCleanup() -> Bool {
        let threshold = Date().addingTimeInterval(-86400)
        guard lastCleanup < threshold else { return false }
        lastCleanup = Date()
        return true
    }
}

// MARK: - Shared result types

struct VisitorsStats {
    let uploaders: Int
    let randomReaders: Int
    let seedReaders: Int
    let apiTotal: Int
    let dashboard: Int
    let uploaderRequests: Int
    let randomReaderRequests: Int
    let seedReaderRequests: Int
    let apiTotalRequests: Int
    let dashboardRequests: Int

    static let zero = VisitorsStats(
        uploaders: 0, randomReaders: 0, seedReaders: 0, apiTotal: 0, dashboard: 0,
        uploaderRequests: 0, randomReaderRequests: 0, seedReaderRequests: 0,
        apiTotalRequests: 0, dashboardRequests: 0
    )
}

struct DailyBreakdownRow: Encodable {
    let dateStr: String
    let uniqueCount: Int
    let requestCount: Int
}

struct TopIPEntry: Encodable {
    let ip: String
    let requestCount: Int
    let rowClass: String  // "" | "warning" (yellow) | "danger" (red)
}

struct TopIPGroup: Encodable {
    let categoryLabel: String
    let entries: [TopIPEntry]
}

// MARK: - Analytics service

struct AnalyticsService {

    enum EventType: String {
        case upload      = "upload"
        case randomRead  = "random_read"
        case seedRead    = "seed_read"
        case dashboard   = "dashboard"
    }

    // MARK: Table creation

    /// Creates the analytics tables if they do not already exist, and applies
    /// any pending schema migrations (e.g. adding new columns to existing tables).
    static func ensureTables(on db: Database) async throws {
        guard let sql = db as? SQLDatabase else { return }

        try await sql.raw("""
            CREATE TABLE IF NOT EXISTS analytics_events (
                id            INT AUTO_INCREMENT PRIMARY KEY,
                ip            VARCHAR(45)  NOT NULL,
                event_type    VARCHAR(32)  NOT NULL,
                event_date    DATE         NOT NULL,
                created_at    DATETIME     NOT NULL,
                request_count INT          NOT NULL DEFAULT 1,
                UNIQUE KEY    uk_ip_type_date (ip, event_type, event_date),
                INDEX         idx_event_date  (event_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """).run()

        // Migration: add request_count to pre-existing analytics_events rows (default 1).
        // MySQL error 1060 ("Duplicate column name") means the column already exists — safe to ignore.
        do {
            try await sql.raw("""
                ALTER TABLE analytics_events
                ADD COLUMN request_count INT NOT NULL DEFAULT 1
                """).run()
        } catch {
            let desc = "\(error)"
            guard desc.contains("1060") || desc.lowercased().contains("duplicate column") else {
                throw error
            }
        }

        try await sql.raw("""
            CREATE TABLE IF NOT EXISTS analytics_daily_summary (
                id            INT AUTO_INCREMENT PRIMARY KEY,
                summary_date  DATE        NOT NULL,
                category      VARCHAR(32) NOT NULL,
                unique_count  INT         NOT NULL DEFAULT 0,
                request_count INT         NOT NULL DEFAULT 0,
                UNIQUE KEY    uk_date_cat   (summary_date, category),
                INDEX         idx_summary_date (summary_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """).run()

        // Migration: add request_count to pre-existing analytics_daily_summary rows.
        do {
            try await sql.raw("""
                ALTER TABLE analytics_daily_summary
                ADD COLUMN request_count INT NOT NULL DEFAULT 0
                """).run()
        } catch {
            let desc = "\(error)"
            guard desc.contains("1060") || desc.lowercased().contains("duplicate column") else {
                throw error
            }
        }
    }

    // MARK: Event recording

    /// Records a single analytics event. Each call increments the request counter
    /// for the (ip, event_type, event_date) tuple. Failures are swallowed so they
    /// never affect the main request handlers.
    static func record(ip: String, type eventType: EventType, on db: Database) async {
        guard let sql = db as? SQLDatabase else { return }
        do {
            try await sql.raw("""
                INSERT INTO analytics_events (ip, event_type, event_date, created_at, request_count)
                VALUES (\(bind: ip), \(bind: eventType.rawValue), CURDATE(), NOW(), 1)
                ON DUPLICATE KEY UPDATE request_count = request_count + 1
                """).run()
            if await AnalyticsCleanupTracker.shared.shouldCleanup() {
                try await cleanup(on: db)
            }
        } catch {
            // Non-fatal — analytics must not break main functionality.
        }
    }

    // MARK: Cleanup (archive events older than 30 days)

    /// Aggregates events older than 30 days into `analytics_daily_summary` and
    /// then deletes them from `analytics_events`.
    static func cleanup(on db: Database) async throws {
        guard let sql = db as? SQLDatabase else { return }

        // Archive daily unique-user counts and total request counts for all expired dates.
        // ON DUPLICATE KEY UPDATE overwrites in case cleanup runs more than once for a date.
        try await sql.raw("""
            INSERT INTO analytics_daily_summary (summary_date, category, unique_count, request_count)
            SELECT event_date, event_type, COUNT(DISTINCT ip), SUM(request_count)
            FROM analytics_events
            WHERE event_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            GROUP BY event_date, event_type
            ON DUPLICATE KEY UPDATE
                unique_count  = VALUES(unique_count),
                request_count = VALUES(request_count)
            """).run()

        // Remove the now-archived raw events.
        try await sql.raw("""
            DELETE FROM analytics_events
            WHERE event_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            """).run()
    }

    private struct EventTypeCount: Decodable {
        let eventType: String
        let uniqueCount: Int
        let requestCount: Int
    }

    private struct SingleCount: Decodable {
        let uniqueCount: Int
        let requestCount: Int
    }

    /// Returns unique-user counts and request totals for today.
    static func dailyStats(on db: Database) async throws -> VisitorsStats {
        guard let sql = db as? SQLDatabase else { return .zero }

        let byType = try await sql.raw("""
            SELECT event_type AS eventType,
                   COUNT(DISTINCT ip) AS uniqueCount,
                   COALESCE(SUM(request_count), 0) AS requestCount
            FROM analytics_events
            WHERE event_date = CURDATE()
            GROUP BY event_type
            """).all(decoding: EventTypeCount.self)

        let totalRows = try await sql.raw("""
            SELECT COUNT(DISTINCT ip) AS uniqueCount,
                   COALESCE(SUM(request_count), 0) AS requestCount
            FROM analytics_events
            WHERE event_date = CURDATE()
              AND event_type IN ('upload', 'random_read', 'seed_read')
            """).all(decoding: SingleCount.self)

        return VisitorsStats(
            uploaders:            byType.first(where: { $0.eventType == "upload" })?.uniqueCount ?? 0,
            randomReaders:        byType.first(where: { $0.eventType == "random_read" })?.uniqueCount ?? 0,
            seedReaders:          byType.first(where: { $0.eventType == "seed_read" })?.uniqueCount ?? 0,
            apiTotal:             totalRows.first?.uniqueCount ?? 0,
            dashboard:            byType.first(where: { $0.eventType == "dashboard" })?.uniqueCount ?? 0,
            uploaderRequests:     byType.first(where: { $0.eventType == "upload" })?.requestCount ?? 0,
            randomReaderRequests: byType.first(where: { $0.eventType == "random_read" })?.requestCount ?? 0,
            seedReaderRequests:   byType.first(where: { $0.eventType == "seed_read" })?.requestCount ?? 0,
            apiTotalRequests:     totalRows.first?.requestCount ?? 0,
            dashboardRequests:    byType.first(where: { $0.eventType == "dashboard" })?.requestCount ?? 0
        )
    }

    /// Returns unique-user counts and request totals for the last 30 days.
    static func monthlyStats(on db: Database) async throws -> VisitorsStats {
        guard let sql = db as? SQLDatabase else { return .zero }

        let byType = try await sql.raw("""
            SELECT event_type AS eventType,
                   COUNT(DISTINCT ip) AS uniqueCount,
                   COALESCE(SUM(request_count), 0) AS requestCount
            FROM analytics_events
            WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            GROUP BY event_type
            """).all(decoding: EventTypeCount.self)

        let totalRows = try await sql.raw("""
            SELECT COUNT(DISTINCT ip) AS uniqueCount,
                   COALESCE(SUM(request_count), 0) AS requestCount
            FROM analytics_events
            WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
              AND event_type IN ('upload', 'random_read', 'seed_read')
            """).all(decoding: SingleCount.self)

        return VisitorsStats(
            uploaders:            byType.first(where: { $0.eventType == "upload" })?.uniqueCount ?? 0,
            randomReaders:        byType.first(where: { $0.eventType == "random_read" })?.uniqueCount ?? 0,
            seedReaders:          byType.first(where: { $0.eventType == "seed_read" })?.uniqueCount ?? 0,
            apiTotal:             totalRows.first?.uniqueCount ?? 0,
            dashboard:            byType.first(where: { $0.eventType == "dashboard" })?.uniqueCount ?? 0,
            uploaderRequests:     byType.first(where: { $0.eventType == "upload" })?.requestCount ?? 0,
            randomReaderRequests: byType.first(where: { $0.eventType == "random_read" })?.requestCount ?? 0,
            seedReaderRequests:   byType.first(where: { $0.eventType == "seed_read" })?.requestCount ?? 0,
            apiTotalRequests:     totalRows.first?.requestCount ?? 0,
            dashboardRequests:    byType.first(where: { $0.eventType == "dashboard" })?.requestCount ?? 0
        )
    }

    // MARK: - Daily breakdown (for chart)

    private struct DailyBreakdownRaw: Decodable {
        let eventDate: String
        let uniqueCount: Int
        let requestCount: Int
    }

    /// Returns per-day unique-IP counts and total request counts for the last 30 days.
    static func dailyBreakdown(on db: Database) async throws -> [DailyBreakdownRow] {
        guard let sql = db as? SQLDatabase else { return [] }

        let rows = try await sql.raw("""
            SELECT DATE_FORMAT(event_date, '%Y-%m-%d') AS eventDate,
                   COUNT(DISTINCT ip) AS uniqueCount,
                   COALESCE(SUM(request_count), 0) AS requestCount
            FROM analytics_events
            WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            GROUP BY event_date
            ORDER BY event_date ASC
            """).all(decoding: DailyBreakdownRaw.self)

        return rows.map { DailyBreakdownRow(dateStr: $0.eventDate, uniqueCount: $0.uniqueCount, requestCount: $0.requestCount) }
    }

    // MARK: - Top IPs per event-type group (today)

    private struct TopIPRaw: Decodable {
        let eventType: String
        let ip: String
        let requestCount: Int
    }

    /// Returns the top 10 IPs by request count for each event-type group for today.
    /// IPs with anomalously high request counts are flagged with a Bootstrap CSS class:
    /// "danger" (>3× group average, ≥5 requests) or "warning" (>2× group average, ≥5 requests).
    static func topIPsToday(on db: Database) async throws -> [TopIPGroup] {
        guard let sql = db as? SQLDatabase else { return [] }

        let rows = try await sql.raw("""
            SELECT event_type AS eventType, ip, request_count AS requestCount
            FROM analytics_events
            WHERE event_date = CURDATE()
            ORDER BY event_type, request_count DESC
            """).all(decoding: TopIPRaw.self)

        // Group by event_type
        var grouped: [String: [TopIPRaw]] = [:]
        for row in rows {
            grouped[row.eventType, default: []].append(row)
        }

        let categories: [(key: String, label: String)] = [
            ("upload",      "Uploaders"),
            ("random_read", "Random Readers"),
            ("seed_read",   "Seed Readers"),
            ("dashboard",   "Dashboard Visitors"),
        ]

        var result: [TopIPGroup] = []
        for (key, label) in categories {
            let entries = grouped[key] ?? []
            guard !entries.isEmpty else { continue }

            let total = entries.reduce(0) { $0 + $1.requestCount }
            let avg = Double(total) / Double(entries.count)

            let ipEntries = entries.prefix(10).map { row -> TopIPEntry in
                let rc = row.requestCount
                let rowClass: String
                if rc >= 5 && Double(rc) > avg * 3.0 {
                    rowClass = "danger"
                } else if rc >= 5 && Double(rc) > avg * 2.0 {
                    rowClass = "warning"
                } else {
                    rowClass = ""
                }
                return TopIPEntry(ip: row.ip, requestCount: rc, rowClass: rowClass)
            }

            result.append(TopIPGroup(categoryLabel: label, entries: Array(ipEntries)))
        }

        return result
    }
}
