//
//  WebMapsController.swift
//  App
//
//  Created by IC on 20/01/2019.
//

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

final class MapsViewController {

    func index(_ req: Request) async throws -> View {
        return try await req.view.render("index")
    }

    func viewMap(_ req: Request) async throws -> View {
        guard let mapId = req.parameters.get("id", as: Int.self) else {
            throw RealRuinsError.invalidParameters("No ID provided")
        }
        return try await req.view.render("mapView", ["mapId": mapId])
    }

    func viewRandomMap(_ req: Request) async throws -> View {
        let gameMap = try await GameMap.query(on: req.db)
            .sort(DatabaseQuery.Sort.sort(.custom("RAND()"), .ascending))
            .first()
        return try await req.view.render("mapView", ["mapId": gameMap?.id ?? 0])
    }

    func viewStats(_ req: Request) async throws -> View {
        let count = try await GameMap.query(on: req.db).count()
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

        return try await req.view.render(
            "mapsdistr",
            DistributionContext(hcaptions: columnCaptions, rows: dataRows, title: "Distribution")
        )
    }
}
