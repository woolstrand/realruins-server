# RealRuins Server — Frontend / Web UI

## Template Engine

**Leaf 4** (Vapor's server-side template engine, `vapor/leaf` 4.x / `vapor/leaf-kit` 1.x). Templates live in `Resources/Views/`.

Leaf 4 syntax notes:
- Block bodies use a **colon** (`:`) indicator, **not** curly braces `{}`.
- Control-flow tags: `#if(cond):` … `#else:` … `#endif`, `#for(x in xs):` … `#endfor`.
- Template inheritance: child templates use `#extend("base"):` … `#endextend` with `#export("block"):` … `#endexport` inside; the base template pulls blocks in with `#import("block")`.
- Context variables accessed directly with `#(varName)`.
- Built-in function tags: `count(array)`, `lowercased(str)`, `uppercased(str)`, `date(ts)`, etc.

---

## Templates

### `index.leaf`

Landing page. Standalone HTML (not using `tablebase.leaf`).

Features:
- Seed search: text input + coverage/size dropdowns → navigates to `/view/maps/seed/<seed>?mapSize=…&coverage=…`
- Distribution lookup: text input → navigates to `/view/distribution/seed/<seed>`
- Links to: Top Seeds, View Random Map, Statistics

Uses **Bootstrap 3.3.7** (loaded from MaxCDN).

---

### `tablebase.leaf`

Base layout for list pages. Renders `#(title)` for the page title and `#import("content")` for the main body. Child templates extend it with `#extend("tablebase"):` and export their content via `#export("content"):` … `#endexport`.

Uses **Bootstrap 3.3.7**.

---

### `mapslist.leaf`

Extends `tablebase.leaf`. Rendered by `GET /view/maps/seed/:seed`.

Displays a table of maps with columns: id, seed, tileId, width, height, mapSize, coverage, biome, and a "View map" link.

Pagination: Prev/Next links using `offset` and `limit` query params.

Context type: `MapsContext { mapsList, offset, limit, seed, title }`

---

### `seedslist.leaf`

Extends `tablebase.leaf`. Rendered by `GET /view/maps/topseeds`.

Displays a ranked table of seeds with map count and a link to `/view/maps/seed/<seed>` and `/view/distribution/seed/<seed>` for each.

Context type: `SeedsListContext { seedsList, offset, limit, title }`

---

### `mapView.leaf`

Standalone HTML (no `tablebase.leaf`). Rendered by `GET /view/map/:id` and `GET /view/maps/random`.

Context type: `MapViewContext { mapId, nameInBucket }`

Fetches the blueprint file directly from DigitalOcean Spaces at
`https://realruinsv2.sfo2.digitaloceanspaces.com/<nameInBucket>.bp` using the Fetch API, decompresses it with **pako 2.1.0** (loaded from cdnjs CDN), then parses the XML using the browser's built-in `DOMParser` and renders the map on a `<canvas>` element.

**Colour coding**:
| Colour | Meaning |
|--------|---------|
| `#000000` (black) | Empty cell |
| `#004400` (dark green) | Terrain only |
| `#ffffff` (white) | Cell contains a Wall |
| `#0000ff` (blue) | Cell contains a Door |
| `#440044` (dark purple) | Cell contains a Chunk |
| `#770000` (dark red) | Other objects |

Mouseover tooltip shows terrain def and object defs for the hovered cell.

Voting buttons trigger `POST /maps/vote/remove/:id` and `POST /maps/vote/promote/:id`.

Uses **Bootstrap 3.3.7** + **jQuery 3.3.1** + **pako 2.1.0**.

---

### `mapsdistr.leaf`

Extends `tablebase.leaf`. Rendered by `GET /view/distribution/seed/:seed`.

Displays a coverage × map-size distribution matrix (HTML table). Rows are coverage buckets (`0%`, `5%`, `30%`, `50%`, `100%`, `other`), columns are size buckets (`200×200` … `400×400`, `other`).

Context type: `DistributionContext { hcaptions, rows [DistributionRow { caption, data }], title }`

---

### `stats.leaf`

Standalone HTML (no `tablebase.leaf`). Rendered by `GET /view/stats`.

Shows total number of maps stored.

---

### `visitors.leaf`

Standalone HTML (no `tablebase.leaf`). Rendered by `GET /view/visitors`.

Context type: `VisitorsContext` — see `MapsViewController.swift`.

**Summary tables** — four Bootstrap panels (Today API, Today Dashboard, Last-30-Days API, Last-30-Days Dashboard). Each table now has three columns: Category, Unique IPs, and Requests.

**Chart** — a Chart.js 4 dual-Y-axis line chart showing daily unique users (left axis) and total requests (right axis) for the last 30 days. Chart data is passed from the controller as a single pipe-delimited string in a `data-chart` attribute (`chartDataAttr`, format: `YYYY-MM-DD|users|requests,...`), then parsed by client-side JavaScript — no `#unsafeHTML` required.

**Top 10 IPs by requests** — one Bootstrap panel per event-type group (Uploaders, Random Readers, Seed Readers, Dashboard Visitors) showing today's top 10 IPs sorted by `request_count`. Rows with anomalously high counts are highlighted:
- Bootstrap `warning` (yellow background) — >2× group average and ≥5 requests.
- Bootstrap `danger` (red background) — >3× group average and ≥5 requests.

**Recent uploads** — the 10 most recently created maps.

Uses **Bootstrap 3.3.7** (MaxCDN) + **Chart.js 4.4.0** (jsDelivr CDN).

---

## Debugging Artifact

`Sources/App/maprenderer.html` — a standalone HTML file (not served by the app) used during development to visualise maps against the server at `http://woolstrand.art:9000`. It is not part of the application's served content and can be removed.

---

## Frontend Notes

- All pages load Bootstrap and jQuery from public CDNs — no local assets except the `Public/` directory (which currently appears empty / unused by templates).
- The `FileMiddleware` serves static files from `Public/` but the Dockerfile has the `COPY Public` line commented out.
