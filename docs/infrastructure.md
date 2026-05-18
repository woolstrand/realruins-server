# RealRuins Server — Infrastructure & Deployment

## Runtime Dependencies

| Dependency | Details |
|------------|---------|
| MySQL | Configurable via env vars (see below) |
| DigitalOcean Spaces | Bucket and region configurable via env vars (see below) |
| Log directory | `/var/log/RRServer/` (created on startup if absent) |

---

## Configuration & Secrets

All settings are read from environment variables at startup in `Sources/App/configure.swift`,
with placeholder fallbacks when variables are not set:

| Environment variable | Purpose | Default (placeholder) |
|----------------------|---------|----------------------|
| `DATABASE_HOST`      | MySQL hostname | `localhost` |
| `DATABASE_PORT`      | MySQL port | `3306` |
| `DATABASE_NAME`      | MySQL database name | `realruins` |
| `DATABASE_USERNAME`  | MySQL username | `realruins` |
| `DATABASE_PASSWORD`  | MySQL password | `123456` |
| `S3_API_KEY`         | DigitalOcean Spaces access key | `123456` |
| `S3_API_SECRET`      | DigitalOcean Spaces secret key | `123456` |
| `S3_BUCKET`          | Spaces bucket name | `realruinsv2` |
| `S3_REGION`          | Spaces region (also used to build the endpoint host) | `sfo2` |

For Docker deployments, pass secrets at **runtime** — not at build time — so they are never
baked into the image:

```bash
docker run -p 80:80 \
  -e DATABASE_HOST=<db-host> \
  -e DATABASE_PORT=3306 \
  -e DATABASE_NAME=realruins \
  -e DATABASE_USERNAME=realruins \
  -e DATABASE_PASSWORD=<real-password> \
  -e S3_API_KEY=<real-key> \
  -e S3_API_SECRET=<real-secret> \
  -e S3_BUCKET=realruinsv2 \
  -e S3_REGION=sfo2 \
  ghcr.io/woolstrand/realruins-server:latest
```

Update the GitHub Actions secrets in the `staging` and `production` environments to use
`DATABASE_PASSWORD` instead of the old `MYSQL_PASSWORD`, and add the new variables listed above.

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
  -e DATABASE_HOST=<db-host> \
  rr-server
```

The container listens on port 80. Set `DATABASE_HOST` to the MySQL host reachable from inside the container (e.g. a Docker network alias or external hostname).

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

See `docs/suggestions.md` for a staging/production deployment plan.
