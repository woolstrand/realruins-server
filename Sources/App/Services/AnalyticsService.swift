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

// MARK: - Shared result type

struct VisitorsStats {
    let uploaders: Int
    let randomReaders: Int
    let seedReaders: Int
    let apiTotal: Int
    let dashboard: Int

    static let zero = VisitorsStats(uploaders: 0, randomReaders: 0, seedReaders: 0, apiTotal: 0, dashboard: 0)
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

    /// Creates the analytics tables if they do not already exist.
    static func ensureTables(on db: Database) async throws {
        guard let sql = db as? SQLDatabase else { return }

        try await sql.raw("""
            CREATE TABLE IF NOT EXISTS analytics_events (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                ip          VARCHAR(45)  NOT NULL,
                event_type  VARCHAR(32)  NOT NULL,
                event_date  DATE         NOT NULL,
                created_at  DATETIME     NOT NULL,
                UNIQUE KEY  uk_ip_type_date (ip, event_type, event_date),
                INDEX       idx_event_date  (event_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """).run()

        try await sql.raw("""
            CREATE TABLE IF NOT EXISTS analytics_daily_summary (
                id           INT AUTO_INCREMENT PRIMARY KEY,
                summary_date DATE        NOT NULL,
                category     VARCHAR(32) NOT NULL,
                unique_count INT         NOT NULL DEFAULT 0,
                UNIQUE KEY   uk_date_cat   (summary_date, category),
                INDEX        idx_summary_date (summary_date)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """).run()
    }

    // MARK: Event recording

    /// Records a single analytics event. Failures are swallowed so they never
    /// affect the main request handlers.
    static func record(ip: String, type eventType: EventType, on db: Database) async {
        guard let sql = db as? SQLDatabase else { return }
        do {
            try await sql.raw("""
                INSERT IGNORE INTO analytics_events (ip, event_type, event_date, created_at)
                VALUES (\(bind: ip), \(bind: eventType.rawValue), CURDATE(), NOW())
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

        // Upsert daily unique-user counts for all expired dates.
        try await sql.raw("""
            INSERT INTO analytics_daily_summary (summary_date, category, unique_count)
            SELECT event_date, event_type, COUNT(DISTINCT ip)
            FROM analytics_events
            WHERE event_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            GROUP BY event_date, event_type
            ON DUPLICATE KEY UPDATE unique_count = VALUES(unique_count)
            """).run()

        // Remove the now-archived raw events.
        try await sql.raw("""
            DELETE FROM analytics_events
            WHERE event_date < DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            """).run()
    }

    // MARK: Stats queries

    private struct EventTypeCount: Decodable {
        let eventType: String
        let uniqueCount: Int
    }

    private struct SingleCount: Decodable {
        let uniqueCount: Int
    }

    /// Returns unique-user counts for today.
    static func dailyStats(on db: Database) async throws -> VisitorsStats {
        guard let sql = db as? SQLDatabase else { return .zero }

        let byType = try await sql.raw("""
            SELECT event_type AS eventType, COUNT(DISTINCT ip) AS uniqueCount
            FROM analytics_events
            WHERE event_date = CURDATE()
            GROUP BY event_type
            """).all(decoding: EventTypeCount.self)

        let totalRows = try await sql.raw("""
            SELECT COUNT(DISTINCT ip) AS uniqueCount
            FROM analytics_events
            WHERE event_date = CURDATE()
              AND event_type IN ('upload', 'random_read', 'seed_read')
            """).all(decoding: SingleCount.self)

        return VisitorsStats(
            uploaders:     byType.first(where: { $0.eventType == "upload" })?.uniqueCount ?? 0,
            randomReaders: byType.first(where: { $0.eventType == "random_read" })?.uniqueCount ?? 0,
            seedReaders:   byType.first(where: { $0.eventType == "seed_read" })?.uniqueCount ?? 0,
            apiTotal:      totalRows.first?.uniqueCount ?? 0,
            dashboard:     byType.first(where: { $0.eventType == "dashboard" })?.uniqueCount ?? 0
        )
    }

    /// Returns unique-user counts for the last 30 days.
    static func monthlyStats(on db: Database) async throws -> VisitorsStats {
        guard let sql = db as? SQLDatabase else { return .zero }

        let byType = try await sql.raw("""
            SELECT event_type AS eventType, COUNT(DISTINCT ip) AS uniqueCount
            FROM analytics_events
            WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
            GROUP BY event_type
            """).all(decoding: EventTypeCount.self)

        let totalRows = try await sql.raw("""
            SELECT COUNT(DISTINCT ip) AS uniqueCount
            FROM analytics_events
            WHERE event_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
              AND event_type IN ('upload', 'random_read', 'seed_read')
            """).all(decoding: SingleCount.self)

        return VisitorsStats(
            uploaders:     byType.first(where: { $0.eventType == "upload" })?.uniqueCount ?? 0,
            randomReaders: byType.first(where: { $0.eventType == "random_read" })?.uniqueCount ?? 0,
            seedReaders:   byType.first(where: { $0.eventType == "seed_read" })?.uniqueCount ?? 0,
            apiTotal:      totalRows.first?.uniqueCount ?? 0,
            dashboard:     byType.first(where: { $0.eventType == "dashboard" })?.uniqueCount ?? 0
        )
    }
}
