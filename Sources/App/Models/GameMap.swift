//
//  GameMap.swift
//  App
//
//  Created by IC on 16/01/2019.
//

import Foundation
import Fluent
import Vapor
import Gzip

/// A single entry of a GameMap blueprint
final class GameMap: Model, Content {
    static let schema = "GameMap"

    /// The unique identifier
    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    /// Game seed
    @Field(key: "seed")
    var seed: String

    /// Tile number on the global planet map
    @Field(key: "tileId")
    var tileId: Int

    /// Game unique identifier
    @Field(key: "gameId")
    var gameId: UInt64

    @Field(key: "coverage")
    var coverage: Int

    @Field(key: "width")
    var width: Int

    @Field(key: "height")
    var height: Int

    @Field(key: "originX")
    var originX: Int

    @Field(key: "originZ")
    var originZ: Int

    @Field(key: "mapSize")
    var mapSize: Int

    @Field(key: "updatedAt")
    var updatedAt: Date

    /// File name as it is stored in bucket
    @Field(key: "nameInBucket")
    var nameInBucket: String

    @Field(key: "biome")
    var biome: String

    @Field(key: "version")
    var version: String

    /// Required by Fluent
    init() {}

    /// Creates a new game map blueprint by parsing gzipped XML data
    init(blueprintData: Data, externalGameId: UInt64?) throws {

        guard let unzipped = try? blueprintData.gunzipped() else {
            throw RealRuinsError.malformedBlueprintGZIP()
        }

        guard let blueprint = try? XMLDocument.init(data: unzipped, options: []) else {
            throw RealRuinsError.malformedBlueprintXML("Can't init XML")
        }

        guard let root = blueprint.rootElement() else {
            throw RealRuinsError.malformedBlueprintXML("No root element found")
        }

        guard let blueprintWidth = Int(root.attribute(forName: "width")?.stringValue ?? ""),
            let blueprintHeight = Int(root.attribute(forName: "height")?.stringValue ?? "") else {
                throw RealRuinsError.malformedBlueprintXML("No height or width provided")
        }

        width = blueprintWidth
        height = blueprintHeight
        biome = root.attribute(forName: "biomeDef")?.stringValue ?? ""

        originX = Int(root.attribute(forName: "x")?.stringValue ?? "0") ?? 0
        originZ = Int(root.attribute(forName: "z")?.stringValue ?? "0") ?? 0
        mapSize = Int(root.attribute(forName: "mapSize")?.stringValue ?? "0") ?? 0

        version = root.attribute(forName: "version")?.stringValue ?? "1.0"

        guard let world = root.elements(forName: "world").first else {
            throw RealRuinsError.malformedBlueprintXML("No world tag found")
        }

        guard let blueprintSeed = world.attribute(forName: "seed")?.stringValue,
            let blueprintTileId = Int(world.attribute(forName: "tile")?.stringValue ?? "") else {
            throw RealRuinsError.malformedBlueprintXML("No seed or tile tags found")
        }

        guard let blueprintGameId = UInt64(world.attribute(forName: "gameId")?.stringValue ?? "") ?? externalGameId else {
            throw RealRuinsError.malformedBlueprintXML("GameId is not provided either in XML or in request")
        }

        seed = blueprintSeed
        tileId = blueprintTileId
        gameId = blueprintGameId
        coverage = Int((Float(world.attribute(forName: "percentage")?.stringValue ?? "0") ?? 0) * 100)

        updatedAt = Date()
        nameInBucket = UUID().uuidString
    }
}
