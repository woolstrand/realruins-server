//
//  GameMap.swift
//  App
//
//  Created by IC on 16/01/2019.
//

import Foundation
import FoundationXML
import Fluent
import Vapor
import Gzip

// MARK: - SAX delegate

/// Minimal SAX delegate that captures only the root-element attributes and the
/// first `<world>` child's attributes.  Unlike the DOM approach this never
/// builds a tree in memory, so peak memory per request is proportional to the
/// decompressed payload size rather than the parsed object graph.
private final class BlueprintAttributeExtractor: NSObject, XMLParserDelegate {
    private(set) var rootAttributes: [String: String] = [:]
    private(set) var worldAttributes: [String: String]? = nil
    private var seenRoot = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if !seenRoot {
            // First element encountered is the document root.
            rootAttributes = attributeDict
            seenRoot = true
        } else if worldAttributes == nil, elementName == "world" {
            worldAttributes = attributeDict
            // Do NOT call abortParsing() here: we must let the parser reach the
            // end of the document so that parse() can return true for a complete
            // file and false for a truncated one.  Without this check a
            // corrupted blueprint whose header is intact would pass validation
            // and be stored in the database.
        }
    }
}

// MARK: - Model

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

    /// Creates a new game map blueprint by parsing gzipped XML data.
    ///
    /// Accepts a `ByteBuffer` directly to avoid an extra `Data` copy in the
    /// call site.  Internally uses a SAX (`XMLParser`) delegate that fires
    /// element callbacks without building a DOM tree, so peak memory per
    /// request is proportional to the *decompressed* payload size rather than
    /// the size of a full in-memory XML object graph.
    ///
    /// The entire document is parsed to completion so that `parse()` can signal
    /// truncation or corruption via its return value.  Blueprints with corrupt
    /// or truncated XML are rejected with a `.badRequest` error and never reach
    /// the database — even when the header attributes were readable.
    init(blueprintData: ByteBuffer, externalGameId: UInt64?) throws {
        // Convert ByteBuffer → Data once, for gunzip only.
        let compressedData = Data(buffer: blueprintData)

        let unzipped: Data
        do {
            unzipped = try compressedData.gunzipped()
        } catch {
            throw RealRuinsError.malformedBlueprintGZIP()
        }

        // SAX parse — fires element callbacks without building a DOM tree.
        // parse() returns true iff the document is complete and well-formed.
        // A return of false means the XML is corrupt or truncated; in that case
        // the blueprint is rejected regardless of whether the header was readable.
        let extractor = BlueprintAttributeExtractor()
        let xmlParser = XMLParser(data: unzipped)
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.delegate = extractor
        let parseOK = xmlParser.parse()

        guard parseOK else {
            let detail = xmlParser.parserError.map { " (\($0.localizedDescription))" } ?? ""
            throw RealRuinsError.malformedBlueprintXML("Corrupted or truncated blueprint XML\(detail)")
        }

        guard let blueprintWidth = Int(extractor.rootAttributes["width"] ?? ""),
              let blueprintHeight = Int(extractor.rootAttributes["height"] ?? "") else {
            throw RealRuinsError.malformedBlueprintXML("No height or width provided")
        }

        width = blueprintWidth
        height = blueprintHeight
        biome = extractor.rootAttributes["biomeDef"] ?? ""

        originX = Int(extractor.rootAttributes["x"] ?? "0") ?? 0
        originZ = Int(extractor.rootAttributes["z"] ?? "0") ?? 0
        mapSize = Int(extractor.rootAttributes["mapSize"] ?? "0") ?? 0
        version = extractor.rootAttributes["version"] ?? "1.0"

        guard let worldAttrs = extractor.worldAttributes else {
            throw RealRuinsError.malformedBlueprintXML("No world tag found")
        }

        guard let blueprintSeed = worldAttrs["seed"],
              let blueprintTileId = Int(worldAttrs["tile"] ?? "") else {
            throw RealRuinsError.malformedBlueprintXML("No seed or tile tags found")
        }

        guard let blueprintGameId = UInt64(worldAttrs["gameId"] ?? "") ?? externalGameId else {
            throw RealRuinsError.malformedBlueprintXML("GameId is not provided either in XML or in request")
        }

        seed = blueprintSeed
        tileId = blueprintTileId
        gameId = blueprintGameId
        coverage = Int((Float(worldAttrs["percentage"] ?? "0") ?? 0) * 100)

        updatedAt = Date()
        nameInBucket = UUID().uuidString
    }
}
