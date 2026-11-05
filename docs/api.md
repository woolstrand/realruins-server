# RealRuins Server — API Reference

## Base URL

`http://<host>:<port>` (no authentication required on any endpoint)

---

## Maps API

### List maps

```
GET /maps?limit=<n>&offset=<n>
```

Returns a paginated JSON array of `GameMap` objects sorted by insertion order.

| Query param | Type | Default | Notes |
|-------------|------|---------|-------|
| `limit` | Int | 50 | Max records to return |
| `offset` | Int | 0 | Pagination offset |

**Response**: `[GameMap]`

---

### Random maps

```
GET /maps/random?limit=<n>
```

Returns up to `limit` consecutive `GameMap` records starting from a random ID. Implemented with a raw SQL `RAND()` jump to avoid a full-table scan.

| Query param | Type | Default |
|-------------|------|---------|
| `limit` | Int | 50 |

**Response**: `[GameMap]`

---

### Maps by seed

```
GET /maps/seed/:seed?limit=<n>&offset=<n>&mapSize=<n>&coverage=<n>
```

Returns maps matching the given world seed, in random order.

| Path param | Type | Notes |
|------------|------|-------|
| `seed` | String | URL-encoded world seed string |

| Query param | Type | Default | Notes |
|-------------|------|---------|-------|
| `limit` | Int | 50 | |
| `offset` | Int | 0 | |
| `mapSize` | Int | — | Filter by map size; `-1` = any |
| `coverage` | Int | — | Filter by coverage percentage; `-1` = any |

**Response**: `[GameMap]`

---

### Top seeds

```
GET /maps/topseeds?limit=<n>&offset=<n>
```

Returns seeds ranked by the number of maps uploaded for each seed.

| Query param | Type | Default | Notes |
|-------------|------|---------|-------|
| `limit` | Int | 50 | Capped at 1000 |
| `offset` | Int | 0 | |

**Response**: `[{ "seed": String, "num": Int }]`

---

### Upload map blueprint

```
POST /maps?gameId=<id>
Content-Type: application/octet-stream
Body: <gzipped XML blueprint>
```

Decompresses the body, parses XML metadata, and either creates a new `GameMap` row or updates an existing one (matched on `gameId` + `tileId`). The raw blueprint file is stored in DigitalOcean Spaces as `<uuid>.bp`.

| Query param | Type | Notes |
|-------------|------|-------|
| `gameId` | String (UInt64) | Fallback game ID if not present in the XML |
| `debug_stage` | Int (0–4) | **Staging only.** Returns HTTP 400 immediately at the named checkpoint to isolate hang points. 0=pre-body-collect, 1=post-body-collect, 2=post-parse, 3=post-DB, 4=post-S3. |

**Response**: `GameMap` (created or updated)

---

### Get map as 2D JSON grid

> **Removed.** This endpoint has been deleted. The map view page now fetches the blueprint directly from DigitalOcean Spaces and performs decompression and XML parsing in the browser.

---

### Get map as flat JSON array

> **Removed.** This endpoint has been deleted. The map view page now fetches the blueprint directly from DigitalOcean Spaces and performs decompression and XML parsing in the browser.

---

### Vote for removal

```
POST /maps/vote/remove/:id
```

Records one removal vote for the map from the requester's IP. Duplicate votes (same IP + map + type) return `208 Already Reported`.

**Response**: `200 OK` or `208 Already Reported` or `400 Bad Request`

---

### Vote for promotion (faction base)

```
POST /maps/vote/promote/:id
```

Same mechanics as vote for removal, but records a promotion vote (voteType=100).

**Response**: `200 OK` or `208 Already Reported` or `400 Bad Request`

---

## Web UI Routes

All web routes render Leaf templates and return HTML.

| Route | Template | Description |
|-------|----------|-------------|
| `GET /view` | `index.leaf` | Landing page with seed search form |
| `GET /view/stats` | `stats.leaf` | Total map count |
| `GET /view/map/:id` | `mapView.leaf` | Canvas map renderer for a specific map |
| `GET /view/maps/random` | `mapView.leaf` | Renders a random map |
| `GET /view/maps/topseeds` | `seedslist.leaf` | Top seeds table |
| `GET /view/maps/seed/:seed` | `mapslist.leaf` | Paginated map list for a seed |
| `GET /view/distribution/seed/:seed` | `mapsdistr.leaf` | Coverage × size distribution matrix |
| `GET /view/visitors` | `visitors.leaf` | Analytics dashboard (unique API/dashboard users + recent uploads) |

---

## Patreon Progress Dashboard

| Route | Response | Description |
|-------|----------|-------------|
| `GET /generateProgressDashboard` | JSON `{"status":"generated"}`, `{"status":"throttled"}`, or `{"status":"error"}` | Fetches the creator's monthly Patreon pledge total and regenerates the public image. A successful generation blocks further attempts for 60 seconds, including concurrent requests. Failures return HTTP 500 with `error` and can be retried. |
| `GET /progressDashboard.png` | PNG (or 404 before first successful generation) | Publicly accessible cached image, served from `Public/`. Reading it never calls Patreon. |

Amounts are rounded to whole US dollars for display; goal and status selection uses the unrounded pledge total. The current status is the highest status with a threshold **strictly below** the total. Reached targets include thresholds equal to the total.
The 1200×416 image is a wide, heading-free Patreon embed. The bar and white goal
markers share a monetary axis: before the first goal it starts at $0; between
goals it spans from 10% of the goal interval below the reached goal to 10%
above the next goal. The fill always starts at the left edge of this axis.
After the last goal the axis runs from $0 to the current total, so the bar is
full and the last goal's marker is positioned relative to that total.
The solid fill interpolates from red at 10% of the first goal to yellow at 70%
and green at 100%; below 10% it stays red, and from the first goal onward it
stays green.
The image shows the status and an approximation/refresh disclaimer, not a target list.
The total is the sum of active members' `will_pay_amount_cents` (monthly cents) from the authenticated
API, excluding members whose `last_charge_status` is set and not `Paid` or `Pending` (pessimistic), multiplied
by 0.85 to approximate fees and losses. The creator access token needs
`campaigns` and `campaigns.members` access; when the account owns one campaign,
`PATREON_CAMPAIGN_ID` is not required.

---

## Response Types

### GameMap

```json
{
  "id": 42,
  "seed": "SomeSeedString",
  "tileId": 1234,
  "gameId": 9876543210,
  "coverage": 50,
  "width": 250,
  "height": 250,
  "originX": 10,
  "originZ": 5,
  "mapSize": 250,
  "updatedAt": "2023-01-15T10:30:00Z",
  "nameInBucket": "550e8400-e29b-41d4-a716-446655440000",
  "biome": "TemperateForest",
  "version": "1.3"
}
```

Blueprint file URL: `https://realruinsv2.sfo2.digitaloceanspaces.com/<nameInBucket>.bp`

### Seed

```json
{ "seed": "SomeSeedString", "num": 147 }
```

---

## Error Responses

Errors are returned as Vapor's standard error JSON:

```json
{
  "error": true,
  "reason": "<human readable message>"
}
```

Internal error identifiers (defined in `errors.swift`): `No map data`, `Can't decompress`, `Malformed map XML`, `InvalidParameters`, `DatabaseUnaccessible`.
