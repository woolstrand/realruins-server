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

Fetches `/maps/json2/:id` via Ajax (jQuery, sync) and renders the map on a `<canvas>` element.

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

Uses **Bootstrap 3.3.7** + **jQuery 3.3.1**.

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

## Debugging Artifact

`Sources/App/maprenderer.html` — a standalone HTML file (not served by the app) used during development to visualise maps against the server at `http://woolstrand.art:9000`. It is not part of the application's served content and can be removed.

---

## Frontend Notes

- All pages load Bootstrap and jQuery from public CDNs — no local assets except the `Public/` directory (which currently appears empty / unused by templates).
- The `FileMiddleware` serves static files from `Public/` but the Dockerfile has the `COPY Public` line commented out.
- Synchronous Ajax (`async: false`) in `mapView.leaf` blocks the browser UI during map load — acceptable for a debug tool but poor UX for production.
