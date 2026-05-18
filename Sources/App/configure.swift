import Fluent
import FluentMySQLDriver
import Vapor
import Leaf

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
    let dbHost     = ProcessInfo.processInfo.environment["DATABASE_HOST"]     ?? "localhost"
    let dbPort     = Int(ProcessInfo.processInfo.environment["DATABASE_PORT"] ?? "3306") ?? 3306
    let dbName     = ProcessInfo.processInfo.environment["DATABASE_NAME"]     ?? "realruins"
    let dbUser     = ProcessInfo.processInfo.environment["DATABASE_USERNAME"] ?? "realruins"
    let dbPassword = ProcessInfo.processInfo.environment["DATABASE_PASSWORD"] ?? "123456"

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
    let s3AccessKey = ProcessInfo.processInfo.environment["S3_API_KEY"]    ?? "123456"
    let s3SecretKey = ProcessInfo.processInfo.environment["S3_API_SECRET"] ?? "123456"
    let s3Bucket    = ProcessInfo.processInfo.environment["S3_BUCKET"]     ?? "realruinsv2"
    let s3Region    = ProcessInfo.processInfo.environment["S3_REGION"]     ?? "sfo2"

    app.s3Uploader = S3Uploader(
        accessKey: s3AccessKey,
        secretKey: s3SecretKey,
        bucket: s3Bucket,
        host: "\(s3Region).digitaloceanspaces.com",
        region: s3Region
    )

    // Warn loudly if any credential is still using the placeholder value.
    if [dbPassword, s3AccessKey, s3SecretKey].contains("123456") {
        app.logger.warning("One or more credentials are using placeholder values. Set DATABASE_PASSWORD, S3_API_KEY and S3_API_SECRET environment variables before running in production.")
    }

    // MARK: - Routes
    try routes(app)
}
