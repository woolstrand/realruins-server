//
//  secureconstants.swift
//  App
//
//  Created by IC on 17/01/2019.
//

import Foundation

let DatabasePassword = ProcessInfo.processInfo.environment["MYSQL_PASSWORD"] ?? "123456"
let S3ApiKey         = ProcessInfo.processInfo.environment["S3_API_KEY"] ?? "123456"
let S3ApiSecret      = ProcessInfo.processInfo.environment["S3_API_SECRET"] ?? "123456"
