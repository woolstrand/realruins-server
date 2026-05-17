//
//  Logger.swift
//  App
//
//  Created by IC on 30/08/2019.
//

import Foundation
import Vapor

// Renamed to FileLogger to avoid conflict with Vapor's Logger (swift-log) type.
final class FileLogger: Middleware {

    var logFolderPath: String = "/var/log/RRServer"
    var filenameFormatter: DateFormatter = DateFormatter()
    var logLineFormatter: DateFormatter = DateFormatter()

    func initialize() {
        if !FileManager.default.fileExists(atPath: logFolderPath) {
            try? FileManager.default.createDirectory(atPath: logFolderPath, withIntermediateDirectories: true, attributes: nil)
        }

        filenameFormatter.dateFormat = "yyyy-MM-dd"
        logLineFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    // Vapor 4: respond does not throw
    func respond(to request: Request, chainingTo next: any Responder) -> EventLoopFuture<Response> {
        let logLine = "\(request.method) \(request.url.string)"
        writeLog(line: logLine)
        return next.respond(to: request)
    }

    func writeLog(line: String) {
        let date = Date()
        let dateString = filenameFormatter.string(from: date)
        let fileURL = URL(fileURLWithPath: logFolderPath).appendingPathComponent("log-" + dateString + ".log")

        let logDate = logLineFormatter.string(from: date)
        let logLine = "[\(logDate)]: \(line)\r\n"
        let logData = logLine.data(using: .utf8)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }

        if let fileHandle = try? FileHandle(forWritingTo: fileURL), let logData = logData {
            fileHandle.seekToEndOfFile()
            fileHandle.write(logData)
            fileHandle.closeFile()
        }
    }
}
