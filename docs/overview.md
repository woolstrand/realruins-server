# RealRuins Server — Project Overview

## Purpose

Backend server for the **Real Ruins** mod for the game *RimWorld*. The mod captures map blueprints (snapshots of tile content) from players' running games and uploads them to this server. Other players' games query the server to download random blueprints to place as ruins in their own worlds.

## Tech Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Swift | 4.1 / 4.2 |
| Web framework | Vapor | 3.x |
| ORM | Fluent-MySQL | 3.x |
| Database | MySQL | (external, localhost:3306) |
| Object storage | DigitalOcean Spaces (S3-compatible) | sfo2 region |
| S3 client | dieworld/storage | 1.0.0-beta |
| Template engine | Leaf | 3.x |
| Compression | GzipSwift | 4.x |
| TLS | swift-nio-ssl | 1.3.2 (pinned) |

## Repository Structure

```
rr-server/
├── Sources/
│   ├── App/
│   │   ├── configure.swift       # App bootstrap: DB, S3, middleware, routes
│   │   ├── routes.swift          # Route declarations
│   │   ├── app.swift             # Application factory
│   │   ├── boot.swift            # Post-init hook (empty)
│   │   ├── errors.swift          # RealRuinsError type
│   │   ├── secureconstants.swift # ⚠️ Secrets (DB password, S3 keys)
│   │   ├── maprenderer.html      # Old standalone debug HTML tool
│   │   ├── Controllers/
│   │   │   ├── MapsController.swift      # JSON API endpoints
│   │   │   └── MapsViewController.swift  # Server-rendered web UI
│   │   ├── Middleware/
│   │   │   └── Logger.swift      # File-based request logger
│   │   ├── Models/
│   │   │   ├── GameMap.swift     # Blueprint metadata model
│   │   │   └── Vote.swift        # Map vote model
│   │   └── Services/
│   │       └── MapsService.swift # Registered but currently empty stub
│   └── Run/
│       └── main.swift            # Process entry point
├── Resources/Views/              # Leaf HTML templates
│   ├── index.leaf
│   ├── mapView.leaf
│   ├── mapslist.leaf
│   ├── seedslist.leaf
│   ├── mapsdistr.leaf
│   ├── stats.leaf
│   └── tablebase.leaf
├── Tests/AppTests/               # Minimal test stub (no real tests)
├── Package.swift                 # SPM manifest (swift-tools-version:4.0)
├── .circleci/config.yml          # CI: compile + swift test on Swift 4.1 image
├── cloud.yml                     # Vapor Cloud deployment config
└── web.Dockerfile                # Docker build (Swift 4.2 builder, Ubuntu 16.04 runtime)
```

## Request Flow

1. A game client (RimWorld mod) sends a `POST /maps` request with a gzipped XML blueprint in the body.
2. `MapsController.create` decompresses, parses the XML, extracts metadata, and either inserts or updates a `GameMap` row in MySQL.
3. The raw blueprint bytes are uploaded to DigitalOcean Spaces (bucket `realruinsv2`). The file is stored as `<uuid>.bp`.
4. Other clients call `GET /maps/random` or `GET /maps/seed/:seed` to retrieve metadata. They then fetch the blueprint file directly from the Spaces CDN URL.
5. The optional web UI (`/view/*`) renders Leaf templates for human browsing of stored maps.

## CI / Build

- CircleCI (`.circleci/config.yml`) runs `swift build` and `swift test` on every commit using a Swift 4.1 Docker image.
- A nightly build also runs against `master`.
- No deployment step in CI — deployment is manual or via Vapor Cloud (`cloud.yml`).

## Running Locally

```bash
swift build
swift run
```

Requires:
- MySQL running on `localhost:3306` with database `realruins`, user `realruins`
- Credentials set in `Sources/App/secureconstants.swift`
- DigitalOcean Spaces credentials also in `secureconstants.swift`
