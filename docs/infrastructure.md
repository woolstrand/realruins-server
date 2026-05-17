# RealRuins Server — Infrastructure & Deployment

## Runtime Dependencies

| Dependency | Details |
|------------|---------|
| MySQL | `localhost:3306`, DB `realruins`, user `realruins` |
| DigitalOcean Spaces | Bucket `realruinsv2`, region `sfo2` |
| Log directory | `/var/log/RRServer/` (created on startup if absent) |

---

## Configuration & Secrets

Credentials are defined in `Sources/App/secureconstants.swift`:

```swift
let DatabasePassword = "123456"
let S3ApiKey         = "123456"
let S3ApiSecret      = "123456"
```

The values committed to the repository are **dummy placeholders**. They are replaced with real credentials manually at deployment time. This file is not intended to hold production secrets.

> ⚠️ The manual substitution step is error-prone and prevents automated multi-environment deployments. See `docs/suggestions.md` (Section 2 — "Secrets not externalised") for the recommended fix.

No environment variable or config-file based configuration exists. Any credential change requires editing this file and rebuilding.

---

## Logging

The custom `Logger` middleware (`Sources/App/Middleware/Logger.swift`) writes one line per request to daily rotating files:

- Location: `/var/log/RRServer/log-<YYYY-MM-DD>.log`
- Format: `[HH:mm:ss.SSS]: <METHOD> <URL>`
- Files are created with no permissions check; the process needs write access to `/var/log/RRServer`.

No structured logging, no log levels, no error-specific log entries.

---

## CORS

All origins, all methods (`GET POST PUT DELETE PATCH OPTIONS`), standard headers. This is a fully open CORS policy — intentional for a public mod API.

---

## Deployment Options

### 1. Vapor Cloud (`cloud.yml`)

```yaml
type: "vapor"
swift_version: "4.1.0"
run_parameters: "serve --port 8080 --hostname 0.0.0.0"
```

This is the original Vapor Cloud deployment manifest. **Vapor Cloud shut down in 2020** and is no longer usable.

### 2. Docker (`web.Dockerfile`)

Two-stage build:
- **Builder stage**: `swift:4.2` — compiles the release binary
- **Runtime stage**: `ubuntu:16.04` — runs the binary

> ⚠️ `ubuntu:16.04` reached end-of-life in April 2021 and no longer receives security patches.

```bash
# Build image
docker build -f web.Dockerfile -t rr-server .

# Run (example)
docker run -p 80:80 \
  -e ENVIRONMENT=production \
  rr-server
```

The container listens on port 80 and expects MySQL to be reachable at `localhost:3306` from within the container (or wherever the hardcoded hostname resolves). For Docker deployments the DB host must be changed from `localhost` to the actual container/host name — this currently requires a code change.

### 3. Direct `swift run`

```bash
swift build -c release
.build/release/Run serve --hostname 0.0.0.0 --port 8080
```

---

## CI (CircleCI)

File: `.circleci/config.yml`

| Job | Image | Steps |
|-----|-------|-------|
| `linux` | `swift:4.1` | `swift build` + `swift test` |
| `linux-release` | `swift:4.1` | `swift build -c release` |

Triggered on every commit and nightly on `master`. No deployment step. No Docker image push.

---

## Recommended Environment Variables (Future)

These values should be extracted from hardcoded constants and supplied via environment:

| Variable | Purpose |
|----------|---------|
| `DB_HOST` | MySQL hostname (default: `localhost`) |
| `DB_PORT` | MySQL port (default: `3306`) |
| `DB_USER` | MySQL username |
| `DB_PASSWORD` | MySQL password |
| `DB_NAME` | MySQL database name |
| `S3_BUCKET` | Spaces bucket name |
| `S3_HOST` | Spaces endpoint host |
| `S3_REGION` | Spaces region |
| `S3_ACCESS_KEY` | Spaces API key |
| `S3_SECRET_KEY` | Spaces API secret |

See `docs/suggestions.md` for a staging/production deployment plan.
