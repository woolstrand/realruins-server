# Copilot Instructions for RealRuins Server

This is a Swift/Vapor 3 backend server for the **Real Ruins** RimWorld mod. It stores player-uploaded map blueprints in MySQL and DigitalOcean Spaces, and serves them to other players' games.

## Documentation index

Before starting any task, read the relevant documents from the `docs/` directory:

| File | When to read |
|------|-------------|
| [`docs/overview.md`](../docs/overview.md) | Always — project purpose, tech stack, repository structure, request flow, and how to build/run |
| [`docs/api.md`](../docs/api.md) | When working on routes, endpoints, request/response handling, or the game client integration |
| [`docs/data-models.md`](../docs/data-models.md) | When working on database models, Fluent queries, the blueprint XML format, or S3 storage |
| [`docs/infrastructure.md`](../docs/infrastructure.md) | When working on deployment, configuration, secrets, logging, CI, or Docker |
| [`docs/frontend.md`](../docs/frontend.md) | When working on Leaf templates, the web UI, or the canvas map renderer |
| [`docs/suggestions.md`](../docs/suggestions.md) | When planning improvements, addressing tech-debt, or setting up staging/production environments |

## Documentation maintenance

**Keep the `docs/` files up to date as you make changes.**

- If you add, remove, or rename a route → update `docs/api.md`.
- If you change a model, table schema, or the blueprint XML parsing → update `docs/data-models.md`.
- If you change deployment config, environment variables, Dockerfile, or CI → update `docs/infrastructure.md`.
- If you add or modify a Leaf template → update `docs/frontend.md`.
- If you change the overall architecture, dependencies, or build process → update `docs/overview.md`.

You do **not** need to track every minor change. The goal is to prevent the docs from containing **false or outdated information**. Update only the sections that would mislead a future agent if left unchanged.
