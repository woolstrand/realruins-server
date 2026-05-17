# RealRuins Server — Suggestions & Improvement Plan

---

## 1. Up-to-dateness, Feasibility and Effort of Updating

### Current state

The project was last meaningfully updated around 2019. Its entire dependency tree is several major versions behind:

| Component | Current in project | Latest stable | Gap |
|-----------|-------------------|---------------|-----|
| Swift | 4.1 / 4.2 | 6.x | ~4 major versions |
| Vapor | 3.x | 4.x | 1 major version (breaking) |
| Fluent | 3.x (FluentMySQL) | 4.x (FluentMySQLDriver) | 1 major version (breaking) |
| swift-nio-ssl | 1.3.2 (pinned) | 2.x | 1 major version |
| Ubuntu runtime | 16.04 (EOL 2021) | 22.04 LTS | 3 versions |
| CircleCI image | `swift:4.1` | `swift:6.1` | — |
| Bootstrap | 3.3.7 | 5.x | 2 major versions |
| jQuery | 3.3.1 | 3.7.x | minor |
| Vapor Cloud | Shut down 2020 | N/A | Dead platform |

### Feasibility

Updating is **technically feasible** but represents a moderate-to-significant effort. The codebase is small (~500 lines of Swift across all source files), which limits the blast radius. However, the Vapor 3 → 4 migration is a breaking API change that touches every controller, model, and configuration function.

### Estimated effort

| Task | Effort |
|------|--------|
| Migrate Vapor 3 → 4 (new routing, middleware, Fluent 4, async/await) | ~2–3 days |
| Replace FluentMySQL with FluentMySQLDriver 4 (new migration syntax) | ~1 day |
| Replace `dieworld/storage` S3 client (unmaintained) with `soto-project/soto` or direct HTTP | ~1 day |
| Update Dockerfile (swift:6.x builder + ubuntu:22.04 runtime) | ~2 hours |
| Update CircleCI to current Swift image | ~1 hour |
| Replace hardcoded secrets with environment variables | ~2 hours |
| Write proper database migrations | ~2 hours |
| **Total** | **~5–7 days** |

### Risks

- **`dieworld/storage`**: The S3 library used (`dieworld/storage`) is a personal fork and likely unmaintained. It may not compile with modern Swift. Replacing it is mandatory before any update.
- **Fluent 4 migration**: Model definitions, queries, and migrations are significantly different. `MySQLModel` no longer exists; models must now conform to `Model` with explicit `@ID`, `@Field` property wrappers.
- **`swift-nio-ssl` pinned version**: The pinned `1.3.2` was a workaround for a specific bug. The constraint can likely be removed with Vapor 4.
- **Regression risk**: There are no meaningful automated tests. All verification would be manual.

### Recommendation

Updating is **reasonable and worthwhile** if the service is actively used by the RimWorld mod. The main motivation is security (EOL OS, unmaintained library) and operational reliability (manual deployment, no automation) rather than feature availability. A staged approach is recommended: start with Docker/CI base images and secrets externalisation (low risk, high value), then tackle the Vapor 4 migration.

---

## 2. Weak Points, Critical Issues & Possible Improvements

### Critical

#### 🔴 SQL injection vulnerabilities

#### 🔴 SQL injection vulnerabilities
Two raw SQL queries build strings via Swift string interpolation without any sanitisation:

- `MapsController.random`: `"... LIMIT \(limit);"` — `limit` comes from a user query parameter. Although it is typed as `Int` in the struct, this pattern is fragile.
- `MapsController.distribution`: `"WHERE seed = BINARY \"\(seed)\""` — `seed` is a URL path parameter passed directly into SQL. A crafted seed value could execute arbitrary SQL.

**Fix**: Use parameterised queries (`conn.query("... WHERE seed = ?", [seed])`) or Fluent's query builder for all queries.

#### 🔴 No authentication on write endpoints
`POST /maps`, `POST /maps/vote/remove`, and `POST /maps/vote/promote` are completely open. Anyone can upload arbitrary data or flood the database with votes.

**Fix (minimum)**: Add a shared secret header check for the upload endpoint (the RimWorld mod client would include it). The vote endpoints are lower risk but still susceptible to spam.

### High

#### 🟠 Vote deduplication bypassable
Vote deduplication is done by IP address. Any user behind a dynamic IP, VPN, or proxy can vote multiple times.

**Fix**: Add a UNIQUE constraint on `(mapId, ip, voteType)` in the database as a safety net. Consider additional deduplication (e.g., a cookie or game ID).

#### 🟠 No database-level uniqueness constraints
The `(gameId, tileId)` uniqueness for `GameMap` is enforced only in application code. A race condition (two concurrent uploads) can create duplicate rows.

**Fix**: Add a unique index on `(gameId, tileId)` in a proper Fluent migration, and handle the duplicate-key error in `create`.

#### 🟠 No rate limiting
The upload endpoint and the JSON endpoints can be called without restriction, allowing resource exhaustion.

**Fix**: Add IP-based rate limiting middleware (Vapor 4 has community packages for this, e.g., `vapor-community/vapor-rate-limit`).

#### 🟠 Ubuntu 16.04 in Dockerfile (EOL)
The runtime Docker image is based on `ubuntu:16.04`, which has not received security patches since April 2021.

**Fix**: Update to `ubuntu:22.04` and adjust the installed library list (`libicu66`, `libcurl4`, etc.). Or use the official Swift Docker image as the runtime base.

### Medium

#### 🟡 `MapsService` is an empty stub
`MapsService` is registered as a Vapor service and imported in several files but contains no implementation. It appears to be scaffolding left for future use.

**Fix**: Either implement it with shared business logic currently duplicated between `MapsController` and `MapsViewController`, or remove the registration.

#### 🟡 Database migrations are disabled
The `MigrationConfig` block in `configure.swift` is commented out. Table schemas are not managed by the application, creating a risk of schema drift between environments.

**Fix**: Define proper `Migration` types for `GameMap` and `Vote` (including indexes) and enable the migration step.

#### 🟡 Synchronous AJAX in mapView.leaf
The map view template uses `$.ajax({ async: false, … })`, which freezes the browser UI thread while the map data loads. For large maps this creates a poor user experience.

**Fix**: Convert to async with a loading spinner.

#### 🟡 Duplicated map rendering logic
`maprenderer.html` (in `Sources`) and `mapView.leaf` (in `Resources/Views`) contain near-identical JavaScript. `maprenderer.html` also hardcodes `http://woolstrand.art:9000` and is not served by the app.

**Fix**: Delete `maprenderer.html`.

#### 🟡 `delete` endpoint not registered
`MapsController.delete` is implemented but never registered in `routes.swift`.

**Fix**: Either register it (with appropriate authentication) or remove the dead code.

#### 🟡 Blueprint CDN URL hardcoded in controller
`MapsController.json` and `json2` hardcode `https://realruinsv2.sfo2.digitaloceanspaces.com` to build the blueprint URL, duplicating the S3 configuration.

**Fix**: Derive the URL from the same S3 config constants used to initialise the driver.

#### 🟡 Secrets not externalised (deployment process)
`Sources/App/secureconstants.swift` contains placeholder values (`"123456"`) for the database password and S3 API keys. These are intentional dummy values that are **replaced with real credentials during manual deployment** — they do not represent leaked secrets. However, this manual substitution step is error-prone and blocks multi-environment automation.

**Fix**: Replace the hardcoded constants with environment variable reads (e.g., `Environment.get("DB_PASSWORD") ?? ""`). This is a prerequisite for the staging/production automation described in Section 3, and can be done independently of the Vapor version upgrade.

### Low

#### 🟢 No response caching
`GET /maps/topseeds` performs a `GROUP BY … ORDER BY COUNT(*)` full-table scan on every call. This could be cached (in-memory or via Redis) for a configurable TTL.

#### 🟢 No structured logging / request IDs
The custom logger writes minimal information and is not correlated with errors. Vapor's built-in logging or a structured logger would make debugging easier.

#### 🟢 Bootstrap 3 / jQuery CDN dependency
Bootstrap 3 is EOL. Templates load it from MaxCDN, which also shut down (the URL may stop working). Self-host assets or upgrade to Bootstrap 5.

---

## 3. Deployment Automation: Staging + Production Instances

### Goal

Two independent deployments:
- **Staging** — uses a throw-away MySQL instance and a separate Spaces bucket (or local MinIO). Safe for testing changes.
- **Production** — current live MySQL + `realruinsv2` bucket.

### Prerequisite: externalise configuration

All environment-specific values must be supplied via environment variables (see `docs/infrastructure.md` for the full variable list). This is required before any multi-environment setup is possible.

### Recommended architecture: Docker Compose + GitHub Actions

#### Repository changes

1. **Rename `web.Dockerfile` → `Dockerfile`** and update it to:
   - Use `swift:6.1` as builder
   - Use `ubuntu:22.04` as runtime
   - Accept environment variables at runtime (not compile time)

2. **Add `docker-compose.yml`** for local and staging use:
   ```yaml
   services:
     app:
       build: .
       ports: ["8080:80"]
       environment:
         - DB_HOST=db
         - DB_PASSWORD=${DB_PASSWORD}
         - S3_ACCESS_KEY=${S3_ACCESS_KEY}
         # ...
       depends_on: [db]
     db:
       image: mysql:8
       environment:
         MYSQL_DATABASE: realruins
         MYSQL_USER: realruins
         MYSQL_PASSWORD: ${DB_PASSWORD}
   ```

3. **Add `docker-compose.staging.yml`** override for staging (different bucket name, etc.).

#### CI/CD pipeline (GitHub Actions, replacing CircleCI)

```
.github/workflows/
  ci.yml          # runs on every PR: swift build + swift test
  deploy-staging.yml   # runs on push to main: build image, push to registry, deploy to staging host
  deploy-prod.yml      # runs on release tag: deploy same image to production host
```

**`deploy-staging.yml` steps**:
1. Build Docker image, tag as `ghcr.io/<owner>/rr-server:staging`
2. Push to GitHub Container Registry
3. SSH into staging host → `docker compose pull && docker compose up -d`

**`deploy-prod.yml` steps**:
1. On a new GitHub Release (tag `v*`): re-tag the staging image as `:<tag>` and `:latest`
2. SSH into production host → `docker compose pull && docker compose up -d`

#### Infrastructure for staging

Minimal-cost option:
- A small VPS (e.g., DigitalOcean Droplet $6/mo) running Docker
- A second Spaces bucket named `realruinsv2-staging` (or local MinIO in Docker Compose)
- A separate MySQL container (no data persistence needed for staging)

All staging secrets stored as GitHub Actions secrets (`STAGING_DB_PASSWORD`, `STAGING_S3_KEY`, etc.).

### Approximate effort

| Task | Effort |
|------|--------|
| Externalise secrets to env vars | ~2 hours |
| Update Dockerfile | ~2 hours |
| Write `docker-compose.yml` | ~2 hours |
| Write GitHub Actions CI workflow | ~2 hours |
| Write deploy workflows (staging + prod) | ~3 hours |
| Provision staging VPS + bucket | ~2 hours |
| **Total** | **~1.5–2 days** |

This work is largely **independent of the Vapor version upgrade** and can be done against the current codebase. It delivers immediate security and operational benefits regardless of whether the framework migration is pursued.
