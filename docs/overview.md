# RealRuins Server — Project Overview

## Purpose

Backend server for the **Real Ruins** mod for the game *RimWorld*. The mod captures map blueprints (snapshots of tile content) from players' running games and uploads them to this server. Other players' games query the server to download random blueprints to place as ruins in their own worlds.

## Tech Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Swift | 5.5+ (built with Swift 6.x) |
| Web framework | Vapor | 4.x |
| ORM | Fluent + FluentMySQLDriver | 4.x |
| Database | MySQL | (external, localhost:3306) |
| Object storage | DigitalOcean Spaces (S3-compatible) | sfo2 region |
| S3 client | Custom AWS Sig V4 uploader | (in-repo, uses swift-crypto) |
| Template engine | Leaf | 4.x |
| Compression | GzipSwift | 5.x |
| XML parsing | FoundationXML | (Swift stdlib, via swift-corelibs-foundation) |

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
├── Package.swift                 # SPM manifest (swift-tools-version:5.5)
├── Dockerfile                    # Docker build (Swift 5.9 builder, Ubuntu 22.04 runtime)
└── .github/workflows/ci.yml     # GitHub Actions: build/test + Docker push to GHCR
```

## Request Flow

1. A game client (RimWorld mod) sends a `POST /maps` request with a gzipped XML blueprint in the body.
2. `MapsController.create` decompresses, parses the XML, extracts metadata, and either inserts or updates a `GameMap` row in MySQL.
3. The raw blueprint bytes are uploaded to DigitalOcean Spaces (bucket `realruinsv2`). The file is stored as `<uuid>.bp`.
4. Other clients call `GET /maps/random` or `GET /maps/seed/:seed` to retrieve metadata. They then fetch the blueprint file directly from the Spaces CDN URL.
5. The optional web UI (`/view/*`) renders Leaf templates for human browsing of stored maps.

## CI / Build

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and pull request to `master`:
1. **`test` job** — `swift build` + `swift test` inside a `swift:5.9` container.
2. **`docker` job** — builds the Docker image and pushes it to GHCR as `ghcr.io/woolstrand/realruins-server:latest` (push-to-master only, after `test` passes).

## Running Locally

```bash
swift build
swift run
```

Requires:
- MySQL running on `localhost:3306` with database `realruins`, user `realruins`
- Credentials set in `Sources/App/secureconstants.swift`
- DigitalOcean Spaces credentials also in `secureconstants.swift`
