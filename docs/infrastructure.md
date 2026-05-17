# RealRuins Server — Infrastructure & Deployment

## Runtime Dependencies

| Dependency | Details |
|------------|---------|
| MySQL | `localhost:3306`, DB `realruins`, user `realruins` |
| DigitalOcean Spaces | Bucket `realruinsv2`, region `sfo2` |
| Log directory | `/var/log/RRServer/` (created on startup if absent) |

---

## Configuration & Secrets

Credentials are read from environment variables at startup, with placeholder fallbacks
when the variables are not set:

| Environment variable | Purpose | Default (placeholder) |
|----------------------|---------|----------------------|
| `MYSQL_PASSWORD`     | MySQL password | `123456` |
| `S3_API_KEY`         | DigitalOcean Spaces access key | `123456` |
| `S3_API_SECRET`      | DigitalOcean Spaces secret key | `123456` |

The values are read in `Sources/App/secureconstants.swift` using `ProcessInfo.processInfo.environment`.

For Docker deployments, pass secrets at **runtime** — not at build time — so they are never
baked into the image:

```bash
docker run -p 80:80 \
  -e MYSQL_PASSWORD=<real-password> \
  -e S3_API_KEY=<real-key> \
  -e S3_API_SECRET=<real-secret> \
  ghcr.io/woolstrand/realruins-server:latest
```

The GitHub Actions secrets `MYSQL_PASSWORD`, `S3_API_KEY`, and `S3_API_SECRET` stored in the
`staging` and `production` environments map directly to these variable names.

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

### 1. Docker (`Dockerfile`)

Two-stage build:
- **Builder stage**: `swift:5.9-focal` — compiles the release binary
- **Runtime stage**: `ubuntu:22.04` — runs the binary

```bash
# Build image
docker build -t rr-server .

# Run (example)
docker run -p 80:80 \
  -e ENVIRONMENT=production \
  rr-server
```

The container listens on port 80 and expects MySQL to be reachable at `localhost:3306` from within the container (or wherever the hardcoded hostname resolves). For Docker deployments the DB host must be changed from `localhost` to the actual container/host name — this currently requires a code change.

### 2. Direct `swift run`

```bash
swift build -c release
.build/release/Run serve --hostname 0.0.0.0 --port 8080
```

---

## CI/CD (GitHub Actions)

File: `.github/workflows/ci.yml`

| Job | Trigger | Steps |
|-----|---------|-------|
| `test` | every push / PR to `master` | `swift build` + `swift test` (inside `swift:5.9` container) |
| `docker` | push to `master` only (after `test` passes) | Build Docker image and push to GHCR as `ghcr.io/<owner>/realruins-server:latest` |

The Docker image is published to the GitHub Container Registry (GHCR). Pull it with:

```bash
docker pull ghcr.io/woolstrand/realruins-server:latest
```

---

## Other Hardcoded Values

The following values are still hardcoded. They could be extracted similarly to the credentials above:

| Variable | Purpose |
|----------|---------|
| `DB_HOST` | MySQL hostname (default: `localhost`) |
| `DB_PORT` | MySQL port (default: `3306`) |
| `DB_USER` | MySQL username |
| `DB_NAME` | MySQL database name |
| `S3_BUCKET` | Spaces bucket name |
| `S3_HOST` | Spaces endpoint host |
| `S3_REGION` | Spaces region |

See `docs/suggestions.md` for a staging/production deployment plan.
