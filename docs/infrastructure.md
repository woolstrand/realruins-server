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
`DATABASE_PASSWORD` instead of the old `MYSQL_PASSWORD`. The following variables need
explicit secrets (or at minimum non-default values) for production use:
`DATABASE_HOST`, `DATABASE_NAME`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`,
`S3_API_KEY`, `S3_API_SECRET`, `S3_BUCKET`, and `S3_REGION`.
`DATABASE_PORT` can typically remain at the default `3306`.

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

## Branching Strategy

| Branch | Purpose |
|--------|---------|
| `develop` | Integration branch. All feature/fix PRs target here. |
| `master` | Stable production branch. Only receives merges from `develop`. |

**Setting the default branch to `develop`** (one-time, done in GitHub):  
`Settings → General → Default branch → change to develop`.

---

## CI/CD (GitHub Actions)

Three workflow files replace the original `ci.yml`:

| File | Trigger | Jobs |
|------|---------|------|
| `.github/workflows/pr.yml` | PR opened/updated against `develop` (or `master`) | `Build & Test` — read-only, no secrets required |
| `.github/workflows/staging.yml` | Push to `develop` (PR merged) | `Build & Test`, then `Docker Build & Push` → staging image |
| `.github/workflows/prod.yml` | Push to `master` | `Docker Build & Push` → prod image (retags staging image if available, otherwise rebuilds from source using BuildKit cache) |

### PR workflow & fork approvals

For same-repo branch PRs the workflow runs automatically with no approval needed.  
For **fork** PRs, GitHub requires manual approval by default. To allow them to run without
confirmation go to:  
`Settings → Actions → General → Fork pull request workflows from outside collaborators`  
→ select **"Run workflows from fork pull requests"**.

> **Security note:** enabling automatic fork-PR runs means a malicious contributor
> could submit a PR that modifies the workflow files and access runner secrets or
> consume compute. Keep manual approval for untrusted outside contributors unless
> you trust all potential fork authors.

### GHCR image references

| Environment | Image | Notes |
|-------------|-------|-------|
| **Staging** | `ghcr.io/woolstrand/realruins-server:staging` | Updated on every merge to `develop` |
| **Staging (pinned)** | `ghcr.io/woolstrand/realruins-server:staging-<sha>` | Immutable per-commit tag |
| **Production** | `ghcr.io/woolstrand/realruins-server:latest` | Updated on every merge to `master` |
| **Production (pinned)** | `ghcr.io/woolstrand/realruins-server:<sha>` | Immutable per-commit tag |

Use the pinned tags in production `docker-compose.yml` files for reproducible deployments.
Use the floating tags (`staging` / `latest`) for convenience during development.

Example `docker-compose.yml` snippet:

```yaml
services:
  app:
    # Staging
    image: ghcr.io/woolstrand/realruins-server:staging
    # Production
    # image: ghcr.io/woolstrand/realruins-server:latest
    ports:
      - "8080:8080"
    environment:
      DATABASE_HOST: db
      DATABASE_PORT: 3306
      DATABASE_NAME: realruins
      DATABASE_USERNAME: realruins
      DATABASE_PASSWORD: ${DATABASE_PASSWORD}
      S3_API_KEY: ${S3_API_KEY}
      S3_API_SECRET: ${S3_API_SECRET}
      S3_BUCKET: realruinsv2
      S3_REGION: sfo2
```

---

See `docs/suggestions.md` for further deployment recommendations.
