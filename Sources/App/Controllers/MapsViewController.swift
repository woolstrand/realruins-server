import Foundation
import Vapor
import Fluent
import FluentMySQLDriver
import SQLKit

struct MapsContext: Encodable {
    let mapsList: [GameMap]
    let offset: Int
    let limit: Int
    let seed: String
    let title: String
}

struct SeedsListContext: Encodable {
    let seedsList: [Seed]
    let offset: Int
    let limit: Int
    let title: String
}

struct DistributionRow: Encodable {
    let caption: String
    let data: [Int]
}

struct DistributionContext: Encodable {
    let hcaptions: [String]
    let rows: [DistributionRow]
    let title: String
}

struct MapViewContext: Encodable {
    let mapId: Int
    let nameInBucket: String
}

// MARK: - Visitors page context types

struct RecentUpload: Encodable {
    let id: Int
    let seed: String
    let mapSize: Int
    let version: String
    let width: Int
    let height: Int
    let updatedAt: String
}

struct VisitorsContext: Encodable {
    let todayStr: String
    // Summary stats (unique IPs + request counts per category)
    let last24h: VisitorsStats
    let monthly: VisitorsStats
    // Recent uploads
    let recentUploads: [RecentUpload]
    // Chart data — pipe-delimited strings embedded in data attributes ("date|users|requests,...")
    let apiChartDataAttr: String
    let webChartDataAttr: String
    // Top IPs per event-type group (today)
    let topIPGroups: [TopIPGroup]
}

final class MapsViewController {

    func index(_ req: Request) async throws -> View {
        if let ip = req.realIPAddress {
            await AnalyticsService.record(ip: ip, type: .dashboard, on: req.db)
        }
        return try await req.view.render("index")
    }

    func viewMap(_ req: Request) async throws -> View {
        guard let mapId = req.parameters.get("id", as: Int.self) else {
            throw RealRuinsError.invalidParameters("No ID provided")
        }
        guard let gameMap = try await GameMap.find(mapId, on: req.db) else {
            throw RealRuinsError.invalidParameters("Map not found")
        }
        if let ip = req.realIPAddress {
            await AnalyticsService.record(ip: ip, type: .dashboard, on: req.db)
        }
        return try await req.view.render("mapView", MapViewContext(mapId: mapId, nameInBucket: gameMap.nameInBucket))
    }

    func viewRandomMap(_ req: Request) async throws -> View {
        guard let gameMap = try await GameMap.query(on: req.db)
            .sort(DatabaseQuery.Sort.sort(.custom("RAND()"), .ascending))
            .first() else {
            throw RealRuinsError.invalidParameters("No maps available")
        }
        if let ip = req.realIPAddress {
            await AnalyticsService.record(ip: ip, type: .dashboard, on: req.db)
        }
        return try await req.view.render("mapView", MapViewContext(
            mapId: gameMap.id ?? 0,
            nameInBucket: gameMap.nameInBucket
        ))
    }

    func viewStats(_ req: Request) async throws -> View {
        let count = try await GameMap.query(on: req.db).count()
        if let ip = req.realIPAddress {
            await AnalyticsService.record(ip: ip, type: .dashboard, on: req.db)
        }
        return try await req.view.render("stats", ["total": "\(count)"])
    }

    func withSeed(_ req: Request) async throws -> View {
        guard let seed = req.parameters.get("seed") else {
            throw RealRuinsError.invalidParameters("No seed provided")
        }
        let seedDecoded = seed.removingPercentEncoding ?? seed

        let limitObj = try? req.query.decode(Limit.self)
        let limit = limitObj?.limit ?? 50
        let offset = limitObj?.offset ?? 0

        let filter = try? req.query.decode(MapFilter.self)

        var query = GameMap.query(on: req.db)
            .filter(\.$seed == seedDecoded)

        if let mapSize = filter?.mapSize, mapSize != -1 {
            query = query.filter(\.$mapSize == mapSize)
        }

        if let coverage = filter?.coverage, coverage != -1 {
            query = query.filter(\.$coverage == coverage)
        }

        let maps = try await query
            .sort(\.$id, .ascending)
            .range(offset..<(offset + limit))
            .all()

        if let ip = req.realIPAddress {
            await AnalyticsService.record(ip: ip, type: .dashboard, on: req.db)
        }

        return try await req.view.render(
            "mapslist",
            MapsContext(
                mapsList: maps,
                offset: offset,
                limit: limit,
                seed: seed,
                title: "Maps list for seed '\(seed)' from \(offset) to \(offset + maps.count)"
            )
        )
    }

    func topSeeds(_ req: Request) async throws -> View {
        let seeds = try await MapsController().topSeeds(req)

        let limitObj = try? req.query.decode(Limit.self)
        let offset = limitObj?.offset ?? 0
        let limit = limitObj?.limit ?? 50

        if let ip = req.realIPAddress {
            await AnalyticsService.record(ip: ip, type: .dashboard, on: req.db)
        }

        return try await req.view.render(
            "seedslist",
            SeedsListContext(
                seedsList: seeds,
                offset: offset,
                limit: limit,
                title: "Top seeds list from \(offset) to \(offset + seeds.count)"
            )
        )
    }

    func mapsDistribution(_ req: Request) async throws -> View {
        let distr = try await MapsController().distribution(req)

        var dataRows: [DistributionRow] = []
        for (index, row) in distr.data.enumerated() {
            let coverage = distr.coverages[index]
            let rowCaption: String
            if coverage == 0 {
                rowCaption = "not specified"
            } else if coverage == -1 {
                rowCaption = "other"
            } else {
                rowCaption = "\(coverage)%"
            }
            dataRows.append(DistributionRow(caption: rowCaption, data: row))
        }

        var columnCaptions: [String] = []
        for size in distr.sizes {
            if size == -1 {
                columnCaptions.append("other")
            } else if size == 0 {
                columnCaptions.append("not specified")
            } else {
                columnCaptions.append("\(size)x\(size)")
            }
        }

        if let ip = req.realIPAddress {
            await AnalyticsService.record(ip: ip, type: .dashboard, on: req.db)
        }

        return try await req.view.render(
            "mapsdistr",
            DistributionContext(hcaptions: columnCaptions, rows: dataRows, title: "Distribution")
        )
    }

    // MARK: - Visitors analytics page

    func viewVisitors(_ req: Request) async throws -> View {
        let last24h = (try? await AnalyticsService.last24HoursStats(on: req.db)) ?? .zero
        let monthly = (try? await AnalyticsService.monthlyStats(on: req.db))     ?? .zero
        let apiBreakdown = (try? await AnalyticsService.dailyBreakdown(.api, on: req.db)) ?? []
        let webBreakdown = (try? await AnalyticsService.dailyBreakdown(.web, on: req.db)) ?? []
        let topIPGroups = (try? await AnalyticsService.topIPsToday(on: req.db)) ?? []

        // Fetch 10 most recent uploads
        let maps = try await GameMap.query(on: req.db)
            .sort(\.$id, .descending)
            .range(0..<10)
            .all()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let todayFormatter = DateFormatter()
        todayFormatter.dateFormat = "yyyy-MM-dd"
        todayFormatter.timeZone = TimeZone(identifier: "UTC")

        let recentUploads = maps.map { map in
            RecentUpload(
                id:        map.id ?? 0,
                seed:      map.seed,
                mapSize:   map.mapSize,
                version:   map.version,
                width:     map.width,
                height:    map.height,
                updatedAt: dateFormatter.string(from: map.updatedAt)
            )
        }

        // Build chart data as a single pipe-delimited string embedded in a data attribute.
        // Format: "YYYY-MM-DD|users|requests,YYYY-MM-DD|users|requests,..."
        // All characters used (digits, hyphens, pipes, commas) are HTML-safe so no
        // raw/unsafe output is needed in the Leaf template.
        func chartAttr(_ rows: [DailyBreakdownRow]) -> String {
            rows.map { "\($0.dateStr)|\($0.uniqueCount)|\($0.requestCount)" }.joined(separator: ",")
        }

        let context = VisitorsContext(
            todayStr:         todayFormatter.string(from: Date()),
            last24h:          last24h,
            monthly:          monthly,
            recentUploads:    recentUploads,
            apiChartDataAttr: chartAttr(apiBreakdown),
            webChartDataAttr: chartAttr(webBreakdown),
            topIPGroups:      topIPGroups
        )

        return try await req.view.render("visitors", context)
    }
}
