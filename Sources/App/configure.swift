import Fluent
import FluentMySQLDriver
import Vapor
import Leaf

// MARK: - Analytics lifecycle handler

private struct AnalyticsLifecycleHandler: LifecycleHandler {
    func didBoot(_ app: Application) throws {
        Task {
            do {
                try await AnalyticsService.ensureTables(on: app.db)
                try await AnalyticsService.cleanup(on: app.db)
            } catch {
                app.logger.error("Analytics initialization failed: \(error)")
            }
        }
    }
}

/// Called before your application initializes.
public func configure(_ app: Application) throws {

    // MARK: - Leaf templating
    app.views.use(.leaf)
    app.leaf.cache.isEnabled = app.environment.isRelease

    // MARK: - Middleware (order = outermost first)
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfig))
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    let fileLogger = FileLogger()
    fileLogger.initialize()
    app.middleware.use(fileLogger)

    // MARK: - MySQL database
    // No migrations are run so existing data is preserved.
    let dbHost     = Environment.get("DATABASE_HOST")     ?? "localhost"
    let dbPortStr  = Environment.get("DATABASE_PORT")
    let dbPort: Int
    if let portStr = dbPortStr, let parsed = Int(portStr) {
        dbPort = parsed
    } else {
        if dbPortStr != nil {
            app.logger.warning("DATABASE_PORT value '\(dbPortStr!)' is not a valid integer; using default port 3306.")
        }
        dbPort = 3306
    }
    guard let dbName     = Environment.get("DATABASE_NAME"),
          let dbUser     = Environment.get("DATABASE_USERNAME"),
          let dbPassword = Environment.get("DATABASE_PASSWORD") else {
              fatalError("Database configuration environment variables missing (DATABASE_NAME, DATABASE_USERNAME, DATABASE_PASSWORD)")
    }

    app.databases.use(
        .mysql(
            hostname: dbHost,
            port: dbPort,
            username: dbUser,
            password: dbPassword,
            database: dbName,
            tlsConfiguration: nil
        ),
        as: .mysql
    )

    // MARK: - S3 / DigitalOcean Spaces
    guard let s3AccessKey = Environment.get("S3_API_KEY"),
          let s3SecretKey = Environment.get("S3_API_SECRET"),
          let s3Bucket    = Environment.get("S3_BUCKET"),
          let s3Region    = Environment.get("S3_REGION") else {
                fatalError("S3 configuration environment variables missing (S3_API_KEY, S3_API_SECRET, S3_BUCKET, S3_REGION)")
    }

    app.s3Uploader = S3Uploader(
        accessKey: s3AccessKey,
        secretKey: s3SecretKey,
        bucket: s3Bucket,
        host: "\(s3Region).digitaloceanspaces.com",
        region: s3Region
    )

    // MARK: - HTTP client (timeouts for outgoing requests such as S3 uploads)
    // Without these limits an unreachable S3 endpoint causes the upload handler
    // to hang indefinitely, producing a 502 from the reverse proxy with no
    // Vapor-side logs at all.
    app.http.client.configuration.timeout = .init(connect: .seconds(10), read: .seconds(60))

    // MARK: - Analytics (auto-create tables, run cleanup)
    app.lifecycle.use(AnalyticsLifecycleHandler())

    // MARK: - Routes
    app.routes.defaultMaxBodySize = "50mb"
    try routes(app)
}
