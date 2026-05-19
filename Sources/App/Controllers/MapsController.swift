//
//  MapsController.swift
//  App
//
//  Created by IC on 16/01/2019.
//

import Foundation
import FoundationXML
import Vapor
import Fluent
import FluentMySQLDriver
import SQLKit


/// Request structures
struct GameId: Content {
    let gameId: String?
}

struct Limit: Content {
    let limit: Int?
    let offset: Int?
}

struct MapFilter: Content {
    let mapSize: Int?
    let coverage: Int?
}


/// Response structures
// For map JSON request
struct GameCell: Content {
    var x: Int?
    var y: Int?
    var terrain: GameObject?
    var objects: [GameObject] = []
}

// For map JSON request
struct GameObject: Content {
    let def: String
    let stuffDef: String?
    let artDesc: String?
}

// For seed:count request
struct Seed: Content {
    let seed: String
    let num: Int
}

// Vote statistics
struct VoteStats: Content {
    let removeVotes: Int
    let promoteVotes: Int
}

struct Distribution: Content {
    let sizes: [Int]
    let coverages: [Int]
    let data: [[Int]]
}

/// Internal struct for raw SQL decoding of distribution query
private struct DistributionRawRow: Decodable {
    let coverage: Int
    let mapSize: Int
    let coverageCount: Int
}

/// Controls basic CRUD operations on `Map`s.
final class MapsController {

    /// Returns a paginated list of all `GameMap`s.
    func index(_ req: Request) async throws -> [GameMap] {
        let limitObj = try? req.query.decode(Limit.self)
        let limit = limitObj?.limit ?? 50
        let offset = limitObj?.offset ?? 0

        return try await GameMap.query(on: req.db)
            .range(offset..<(offset + limit))
            .all()
    }

    func random(_ req: Request) async throws -> [GameMap] {
        let limitObj = try? req.query.decode(Limit.self)
        let limit = limitObj?.limit ?? 50

        // Returns <limit> records starting from a random ID to avoid full-table scan.
        let result = try await req.sqlDb
            .raw("""
                SELECT GameMap.* FROM GameMap
                JOIN (SELECT (RAND() * (SELECT MAX(id) FROM GameMap)) AS id) AS r2
                WHERE GameMap.id >= r2.id
                ORDER BY GameMap.id ASC
                LIMIT \(bind: limit)
                """)
            .all(decodingFluent: GameMap.self)

        if let ip = req.remoteAddress?.ipAddress {
            await AnalyticsService.record(ip: ip, type: .randomRead, on: req.db)
        }
        return result
    }

    func withSeed(_ req: Request) async throws -> [GameMap] {
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

        let result = try await query
            .sort(DatabaseQuery.Sort.sort(.custom("RAND()"), .ascending))
            .range(offset..<(offset + limit))
            .all()

        if let ip = req.remoteAddress?.ipAddress {
            await AnalyticsService.record(ip: ip, type: .seedRead, on: req.db)
        }
        return result
    }

    func distribution(_ req: Request) async throws -> Distribution {
        let coverages = [0, 5, 30, 50, 100, -1]
        let sizes = [0, 200, 225, 250, 275, 300, 325, 350, 400, -1]

        guard let seed = req.parameters.get("seed") else {
            throw RealRuinsError.invalidParameters("No seed provided")
        }

        let rows = try await req.sqlDb
            .raw("""
                SELECT coverage, mapSize, COUNT(coverage) AS coverageCount
                FROM GameMap
                WHERE seed = BINARY \(bind: seed)
                GROUP BY coverage, mapSize
                """)
            .all(decoding: DistributionRawRow.self)

        var data = Array(repeating: Array(repeating: 0, count: sizes.count), count: coverages.count)

        for row in rows {
            let coverageIndex = coverages.firstIndex(of: Int(row.coverage)) ?? (coverages.count - 1)
            let sizeIndex = sizes.firstIndex(of: Int(row.mapSize)) ?? (sizes.count - 1)
            data[coverageIndex][sizeIndex] += Int(row.coverageCount)
        }

        return Distribution(sizes: sizes, coverages: coverages, data: data)
    }

    func topSeeds(_ req: Request) async throws -> [Seed] {
        let limitObj = try? req.query.decode(Limit.self)
        var limit = limitObj?.limit ?? 50
        let offset = limitObj?.offset ?? 0
        if limit > 1000 { limit = 1000 }

        return try await req.sqlDb
            .raw("""
                SELECT seed, COUNT(*) AS num FROM GameMap
                GROUP BY seed
                ORDER BY num DESC
                LIMIT \(bind: limit) OFFSET \(bind: offset)
                """)
            .all(decoding: Seed.self)
    }

    /// Saves a decoded `GameMap` to the database and uploads blueprint to S3.
    func create(_ req: Request) async throws -> GameMap {
        // Collect the body explicitly in the async handler context rather than
        // at the route-dispatch level on the NIO event loop.  The 50 MB cap is
        // well above the largest expected blueprint file.
        let bodyBuffer = try await req.body.collect(upTo: 50 * 1024 * 1024)

        guard bodyBuffer.readableBytes > 0 else {
            throw RealRuinsError.noData()
        }

        // gameId is sent as a String query param to avoid integer overflow issues.
        let gameIdStr = try? req.query.decode(GameId.self)
        let rawData = Data(buffer: bodyBuffer)
        let gameMap = try GameMap(blueprintData: rawData, externalGameId: UInt64(gameIdStr?.gameId ?? ""))

        let dbResult = try await GameMap.query(on: req.db)
            .filter(\.$gameId == gameMap.gameId)
            .filter(\.$tileId == gameMap.tileId)
            .first()

        let savedMap: GameMap
        if let storedMap = dbResult {
            // Update existing map
            storedMap.updatedAt = Date()
            storedMap.height = gameMap.height
            storedMap.width = gameMap.width
            try await req.s3Uploader.upload(client: req.client, data: bodyBuffer, fileName: storedMap.nameInBucket, logger: req.logger)
            try await storedMap.update(on: req.db)
            savedMap = storedMap

        } else {
            // Create new map
            let filename = UUID().uuidString
            try await req.s3Uploader.upload(client: req.client, data: bodyBuffer, fileName: filename, logger: req.logger)
            gameMap.nameInBucket = filename
            try await gameMap.save(on: req.db)
            savedMap = gameMap
        }

        if let ip = req.remoteAddress?.ipAddress {
            await AnalyticsService.record(ip: ip, type: .upload, on: req.db)
        }
        return savedMap
    }

    func voteForRemoval(_ req: Request) async throws -> HTTPStatus {
        return try await vote(req, voteType: 500)
    }

    func voteForPromotion(_ req: Request) async throws -> HTTPStatus {
        return try await vote(req, voteType: 100)
    }

    func vote(_ req: Request, voteType: Int) async throws -> HTTPStatus {
        guard let ip = req.remoteAddress?.ipAddress,
              let mapId = req.parameters.get("id", as: Int.self) else {
            return .badRequest
        }

        if try await Vote.query(on: req.db)
            .filter(\.$mapId == mapId)
            .filter(\.$ip == ip)
            .filter(\.$voteType == voteType)
            .first() != nil {
            return .alreadyReported
        }

        let newVote = Vote(mapId: mapId, ip: ip, voteType: voteType)
        try await newVote.save(on: req.db)
        return .ok
    }
}

/// Returning map data in JSON format
extension MapsController {

    func json(_ req: Request) async throws -> [[GameCell]] {
        guard let mapId = req.parameters.get("id", as: Int.self) else {
            throw RealRuinsError.invalidParameters("No ID provided")
        }

        guard let gameMap = try await GameMap.find(mapId, on: req.db) else {
            throw RealRuinsError.invalidParameters("Map not found")
        }

        let fullName = "https://realruinsv2.sfo2.digitaloceanspaces.com/\(gameMap.nameInBucket).bp"
        let response = try await req.client.get(URI(string: fullName))

        guard let bodyBuffer = response.body else {
            throw RealRuinsError.noData()
        }
        let blueprintData = Data(buffer: bodyBuffer)

        guard let unzipped = try? blueprintData.gunzipped() else {
            throw RealRuinsError.malformedBlueprintGZIP()
        }

        guard let blueprint = try? XMLDocument(data: unzipped, options: []),
              let root = blueprint.rootElement() else {
            throw RealRuinsError.malformedBlueprintXML("Can't init XML")
        }

        guard let blueprintWidth = Int(root.attribute(forName: "width")?.stringValue ?? ""),
              let blueprintHeight = Int(root.attribute(forName: "height")?.stringValue ?? "") else {
            throw RealRuinsError.malformedBlueprintXML("No height or width provided")
        }

        var cells: [[GameCell]] = Array(repeating: Array(repeating: GameCell(), count: blueprintWidth), count: blueprintHeight)

        for node in root.elements(forName: "cell") {
            if let nodeX = Int(node.attribute(forName: "x")?.stringValue ?? ""),
               let nodeZ = Int(node.attribute(forName: "z")?.stringValue ?? "") {
                var gameCell = cells[nodeZ][nodeX]
                if let terrainDef = node.elements(forName: "terrain").first?.attribute(forName: "def")?.stringValue {
                    gameCell.terrain = GameObject(def: terrainDef, stuffDef: nil, artDesc: nil)
                }
                for item in node.elements(forName: "item") {
                    if let itemDef = item.attribute(forName: "def")?.stringValue {
                        let stuffDef = item.attribute(forName: "stuffDef")?.stringValue
                        gameCell.objects.append(GameObject(def: itemDef, stuffDef: stuffDef, artDesc: ""))
                    }
                }
                cells[nodeZ][nodeX] = gameCell
            }
        }
        return cells
    }

    func json2(_ req: Request) async throws -> [GameCell] {
        guard let mapId = req.parameters.get("id", as: Int.self) else {
            throw RealRuinsError.invalidParameters("No ID provided")
        }

        guard let gameMap = try await GameMap.find(mapId, on: req.db) else {
            throw RealRuinsError.invalidParameters("Map not found")
        }

        let fullName = "https://realruinsv2.sfo2.digitaloceanspaces.com/\(gameMap.nameInBucket).bp"
        let response = try await req.client.get(URI(string: fullName))

        guard let bodyBuffer = response.body else {
            throw RealRuinsError.noData()
        }
        let blueprintData = Data(buffer: bodyBuffer)

        guard let unzipped = try? blueprintData.gunzipped() else {
            throw RealRuinsError.malformedBlueprintGZIP()
        }

        guard let blueprint = try? XMLDocument(data: unzipped, options: []),
              let root = blueprint.rootElement() else {
            throw RealRuinsError.malformedBlueprintXML("Can't init XML")
        }

        var cells: [GameCell] = []

        for node in root.elements(forName: "cell") {
            if let nodeX = Int(node.attribute(forName: "x")?.stringValue ?? ""),
               let nodeZ = Int(node.attribute(forName: "z")?.stringValue ?? "") {
                var gameCell = GameCell()
                gameCell.x = nodeX
                gameCell.y = nodeZ

                if let terrainDef = node.elements(forName: "terrain").first?.attribute(forName: "def")?.stringValue {
                    gameCell.terrain = GameObject(def: terrainDef, stuffDef: nil, artDesc: nil)
                }
                for item in node.elements(forName: "item") {
                    if let itemDef = item.attribute(forName: "def")?.stringValue {
                        let stuffDef = item.attribute(forName: "stuffDef")?.stringValue
                        gameCell.objects.append(GameObject(def: itemDef, stuffDef: stuffDef, artDesc: ""))
                    }
                }
                cells.append(gameCell)
            }
        }
        return cells
    }
}

// MARK: - SQL helper
extension Request {
    var sqlDb: SQLDatabase {
        guard let sql = db as? SQLDatabase else {
            fatalError("Database does not support SQLKit")
        }
        return sql
    }
}
