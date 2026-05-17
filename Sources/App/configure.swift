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
    app.databases.use(
        .mysql(
            hostname: "localhost",
            port: 3306,
            username: "realruins",
            password: DatabasePassword,
            database: "realruins",
            tlsConfiguration: nil
        ),
        as: .mysql
    )

    // MARK: - S3 / DigitalOcean Spaces
    app.s3Uploader = S3Uploader(
        accessKey: S3ApiKey,
        secretKey: S3ApiSecret,
        bucket: "realruinsv2",
        host: "sfo2.digitaloceanspaces.com",
        region: "sfo2"
    )

    // Warn loudly if any credential is still using the placeholder value.
    if [DatabasePassword, S3ApiKey, S3ApiSecret].contains("123456") {
        app.logger.warning("One or more credentials are using placeholder values. Set MYSQL_PASSWORD, S3_API_KEY and S3_API_SECRET environment variables before running in production.")
    }

    // MARK: - Routes
    try routes(app)
}
