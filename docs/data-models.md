# RealRuins Server — Data Models

## Database: MySQL

Database name: `realruins`  
ORM: Fluent-MySQL 3 (`MySQLModel`)  
No formal migration config is active (the `MigrationConfig` block in `configure.swift` is commented out — tables must be created manually).

---

## GameMap

**Table name**: `GameMap` (Fluent default: class name)

| Column | Swift type | MySQL type | Notes |
|--------|-----------|------------|-------|
| `id` | `Int?` | INT AUTO_INCREMENT | Primary key |
| `seed` | `String` | VARCHAR | World seed string from RimWorld |
| `tileId` | `Int` | INT | Tile index on the planet map |
| `gameId` | `UInt64` | BIGINT UNSIGNED | Unique per save file |
| `coverage` | `Int` | INT | Ruin coverage % × 100 (e.g., 50 = 50%) |
| `width` | `Int` | INT | Blueprint width in cells |
| `height` | `Int` | INT | Blueprint height in cells |
| `originX` | `Int` | INT | X coordinate of the tile's origin |
| `originZ` | `Int` | INT | Z coordinate of the tile's origin |
| `mapSize` | `Int` | INT | RimWorld map dimension (e.g., 250 for 250×250) |
| `updatedAt` | `Date` | DATETIME | Last update timestamp |
| `nameInBucket` | `String` | VARCHAR | UUID filename in DigitalOcean Spaces (no extension) |
| `biome` | `String` | VARCHAR | RimWorld biome def name (e.g., `TemperateForest`) |
| `version` | `String` | VARCHAR | Blueprint format version from the XML |

**Uniqueness constraint**: `(gameId, tileId)` — enforced in application logic (the `create` endpoint queries for an existing record before inserting). There is no database-level unique index defined via migrations.

**Blueprint file URL pattern**: `https://realruinsv2.sfo2.digitaloceanspaces.com/<nameInBucket>.bp`

---

## Vote

**Table name**: `Vote`

| Column | Swift type | MySQL type | Notes |
|--------|-----------|------------|-------|
| `id` | `Int?` | INT AUTO_INCREMENT | Primary key |
| `mapId` | `Int` | INT | References `GameMap.id` (no FK constraint) |
| `ip` | `String` | VARCHAR | Voter's IP address |
| `voteType` | `Int` | INT | `100` = promote, `500` = remove |

Deduplication: application code checks for an existing `(mapId, ip, voteType)` triple before inserting. No database-level unique index.

---

## Analytics

Both analytics tables are created automatically at server startup via `CREATE TABLE IF NOT EXISTS`. No manual setup is needed.

### analytics_events

**Purpose**: Stores one row per unique `(ip, event_type, event_date)` tuple, covering the last 30 days. Raw events older than 30 days are archived to `analytics_daily_summary` and deleted.

| Column | MySQL type | Notes |
|--------|-----------|-------|
| `id` | INT AUTO_INCREMENT | Primary key |
| `ip` | VARCHAR(45) | Client IP address |
| `event_type` | VARCHAR(32) | `upload`, `random_read`, `seed_read`, `dashboard` |
| `event_date` | DATE | Day of the event (UTC) |
| `created_at` | DATETIME | Exact time of first occurrence |

**Unique constraint**: `(ip, event_type, event_date)` — `INSERT IGNORE` is used so each IP is counted only once per event type per day.

**Tracked events**:
- `upload` — `POST /maps` (blueprint uploaded)
- `random_read` — `GET /maps/random`
- `seed_read` — `GET /maps/seed/:seed`
- `dashboard` — any `GET /view/*` page

### analytics_daily_summary

**Purpose**: Cumulative daily unique-user counts for dates older than 30 days. Populated automatically by the cleanup process.

| Column | MySQL type | Notes |
|--------|-----------|-------|
| `id` | INT AUTO_INCREMENT | Primary key |
| `summary_date` | DATE | The calendar day |
| `category` | VARCHAR(32) | Same values as `analytics_events.event_type` |
| `unique_count` | INT | Number of distinct IPs on that day |

**Unique constraint**: `(summary_date, category)` — upserted via `ON DUPLICATE KEY UPDATE`.

---

## Blueprint File Format

Files stored in Spaces are **gzip-compressed XML**. After decompression the structure is:

```xml
<blueprint width="250" height="250" biomeDef="TemperateForest"
           x="10" z="5" mapSize="250" version="1.3">
  <world seed="SomeSeed" tile="1234" gameId="9876543210" percentage="0.5" />
  <cell x="0" z="0">
    <terrain def="Gravel" />
    <item def="Wall" stuffDef="Steel" />
    <item def="Door" />
  </cell>
  <!-- ... more cells ... -->
</blueprint>
```

**Key attributes on `<blueprint>`**:
- `width`, `height` — dimensions in cells
- `biomeDef` — biome identifier
- `x`, `z` — tile origin coordinates
- `mapSize` — RimWorld map edge length
- `version` — format version (defaults to `"1.0"` if absent)

**`<world>` child element**:
- `seed` — world seed string
- `tile` — tile index
- `gameId` — unique save-file identifier
- `percentage` — coverage as a float (0.0–1.0); stored in DB multiplied by 100

**`<cell>` child elements**:
- `x`, `z` — cell coordinates within the blueprint
- `<terrain def="…" />` — terrain type (optional)
- `<item def="…" stuffDef="…" />` — placed objects (0 or more per cell)

---

## Object Storage

Provider: DigitalOcean Spaces  
Bucket: `realruinsv2`  
Region: `sfo2`  
Host: `sfo2.digitaloceanspaces.com`  
Public CDN URL: `https://realruinsv2.sfo2.digitaloceanspaces.com/<nameInBucket>.bp`

Files are uploaded via the `dieworld/storage` S3 driver. The S3 keys are read from `Sources/App/secureconstants.swift` at compile time.
