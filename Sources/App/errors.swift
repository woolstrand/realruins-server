//
//  errors.swift
//  App
//
//  Created by IC on 17/01/2019.
//

import Foundation
import Vapor

struct RealRuinsError: AbortError {

    var status: HTTPResponseStatus
    var reason: String

    static func noData() -> RealRuinsError {
        RealRuinsError(status: .badRequest, reason: "Add map request did not contain map data attached in body")
    }

    static func malformedBlueprintGZIP() -> RealRuinsError {
        RealRuinsError(status: .badRequest, reason: "Map body can not be decompressed")
    }

    static func malformedBlueprintXML(_ additional: String) -> RealRuinsError {
        RealRuinsError(status: .badRequest, reason: additional)
    }

    static func invalidParameters(_ additional: String) -> RealRuinsError {
        RealRuinsError(status: .badRequest, reason: additional)
    }

    static func databaseNotAccessible() -> RealRuinsError {
        RealRuinsError(status: .internalServerError, reason: "Can't connect to the database")
    }
}
