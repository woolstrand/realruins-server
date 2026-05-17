//
//  Vote.swift
//  App
//
//  Created by IC on 22/01/2019.
//

import Foundation
import Fluent
import Vapor

/// A vote record for a GameMap blueprint
final class Vote: Model, Content {
    static let schema = "Vote"

    /// The unique identifier
    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "mapId")
    var mapId: Int

    @Field(key: "ip")
    var ip: String

    @Field(key: "voteType")
    var voteType: Int

    /// Required by Fluent
    init() {}

    init(mapId: Int, ip: String, voteType: Int) {
        self.mapId = mapId
        self.ip = ip
        self.voteType = voteType
    }
}
