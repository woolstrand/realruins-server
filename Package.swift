// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "rr-server",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),

        // 🔵 Fluent ORM
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.0.0"),

        // 🍃 Leaf templating engine
        .package(url: "https://github.com/vapor/leaf.git", from: "4.0.0"),

        // 🗄 GZip implementation for swift
        .package(url: "https://github.com/1024jp/GzipSwift.git", from: "5.0.0"),

        // 🔐 Swift Crypto (for AWS Sig V4 signing)
        .package(url: "https://github.com/apple/swift-crypto.git", "2.0.0"..<"4.0.0"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Gzip", package: "GzipSwift"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .target(name: "Run", dependencies: [.target(name: "App")]),
        .testTarget(name: "AppTests", dependencies: [
            .target(name: "App"),
            .product(name: "XCTVapor", package: "vapor"),
        ])
    ]
)

