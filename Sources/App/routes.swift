import Vapor

/// Register your application's routes here.
public func routes(_ app: Application) throws {
    // Basic "It works" example
    app.get { req async in
        return "It works!"
    }

    // Basic "Hello, world!" example
    app.get("hello") { req async in
        return "Hello, world!"
    }

    /// API part
    let gameMapController = MapsController()
    let gameMapViewController = MapsViewController()

    app.get("maps", use: gameMapController.index)
    app.get("maps", "random", use: gameMapController.random)
    app.get("maps", "seed", ":seed", use: gameMapController.withSeed)
    app.get("maps", "topseeds", use: gameMapController.topSeeds)
    app.on(.POST, "maps", body: .stream, use: gameMapController.create)

    app.post("maps", "vote", "remove", ":id", use: gameMapController.voteForRemoval)
    app.post("maps", "vote", "promote", ":id", use: gameMapController.voteForPromotion)

    /// Web part
    app.get("view", use: gameMapViewController.index)
    app.get("view", "stats", use: gameMapViewController.viewStats)
    app.get("view", "map", ":id", use: gameMapViewController.viewMap)
    app.get("view", "maps", "random", use: gameMapViewController.viewRandomMap)
    app.get("view", "maps", "topseeds", use: gameMapViewController.topSeeds)

    app.get("view", "maps", "seed", ":seed", use: gameMapViewController.withSeed)
    app.get("view", "distribution", "seed", ":seed", use: gameMapViewController.mapsDistribution)
    app.get("view", "visitors", use: gameMapViewController.viewVisitors)
}
