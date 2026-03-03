# Tile Rendering System: Autotile + Splat

## Context
Tiles currently render as colored rectangles with noise variation. Two new rendering modes replace this for tiles with art assets:

1. **Tileset** (e.g., dirt, stone) — 47-tile blob autotile, 12x4 grid of 16x16 tiles, bitmask-based neighbor matching
2. **Splat** (e.g., ores, crystals) — 32x32 single-tile sprites centered on the 16x16 cell, extending 8px in each direction to "pop out" of the wall. Multiple variant files per type, with surface vs underground categories.

Tiles without art assets keep colored rectangles as fallback.

## Rendering Modes

### Tileset Mode
- **Foreground:** `assets/items/<item_id>/tiles.png` — 12x4 grid (192x64px), standard 3x3 minimal blob autotile
- **Back wall:** `assets/items/<item_id>/back_wall.png` — same 12x4 format with transparency gaps showing parallax
- **Edge matching:** Any non-empty tile = "filled." Edges only against air/empty.
- **Rendered via:** TileMapLayer cells (source_id per tile type)

### Splat Mode
- **Asset files:** `assets/items/<item_id>/splat_1.png`, `splat_2.png`, etc. (32x32 each)
- **Surface variants:** `assets/items/<item_id>/splat_surface_1.png`, etc.
- **Surface detection:** Tile above is EMPTY → use surface variants (fall back to normal if none)
- **Variant selection:** Position hash `(world_x * 73856093 ^ world_y * 19349663) % variant_count` — deterministic, no storage cost
- **Rendered via:** Individual Sprite2D nodes (can't use TileMapLayer — 32x32 overflows 16x16 cells)
- **Z-index:** Between base tilemap (z=0) and darkness overlay (z=11), e.g., z=1

### Fallback
- **No art assets:** Existing ColorRect-style programmatic atlas (source 0)

## Configuration in `data/items.json`

Add `render_mode` to item metadata for tile items:

```json
{
  "id": "dirt",
  "metadata": { "render_mode": "tileset" }
}

{
  "id": "iron_ore",
  "metadata": {
    "render_mode": "splat",
    "splat_variants": ["splat_1.png", "splat_2.png", "splat_3.png"],
    "splat_surface_variants": ["splat_surface_1.png"]
  }
}
```

Items without `render_mode` (or with no metadata) → fallback to colored rect.
Tileset mode discovers `tiles.png` and `back_wall.png` by convention (no explicit listing).

## Files Modified

### 1. `data/items.json` — Add render_mode to tile items
- Dirt: `"render_mode": "tileset"`
- Other tiles: added as art is created
- Ores/crystals: `"render_mode": "splat"` + variant file lists (when art is ready)

### 2. `scripts/data/tile_data.gd` — Tile render config scanning
- `_scan_tile_render_config()` — iterates tile types, reads render_mode from ItemDatabase metadata via drop_item mapping
- `get_render_mode(tile_type) -> String` — returns "tileset", "splat", or "" (fallback)
- `get_tileset_path(tile_type) -> String` — `res://assets/items/<drop_item>/tiles.png`
- `get_back_wall_path(tile_type) -> String` — `res://assets/items/<drop_item>/back_wall.png`
- `get_splat_variants(tile_type) -> Array` — full paths to splat variant PNGs
- `get_splat_surface_variants(tile_type) -> Array` — full paths to surface splat variant PNGs

### 3. `scripts/world/chunk_manager.gd` — Core rendering system

**New state:**
- `_autotile_source_ids: Dictionary` — `{tile_type: source_id}` for tileset-mode types
- `_back_wall_source_ids: Dictionary` — `{tile_type: source_id}` for back wall tilesets
- `_bitmask_to_atlas: Dictionary` — 47-entry bitmask → Vector2i(col, row) lookup
- `_splat_textures: Dictionary` — `{tile_type: [Texture2D, ...]}` loaded splat variants
- `_splat_surface_textures: Dictionary` — `{tile_type: [Texture2D, ...]}` loaded surface variants
- `_chunk_splat_sprites: Dictionary` — `{chunk_coord: [Sprite2D, ...]}` for cleanup on unload

**Tileset functions (new):**
- `_build_bitmask_lookup()` — 47-entry table
- `_add_autotile_sources(tileset)` — register TileSetAtlasSource per tileset-mode tile type (12x4, with collision)
- `_add_back_wall_sources(tileset)` — same for back_wall.png (no collision)
- `_compute_bitmask(world_pos) -> int` — 8 neighbors via `world_data.has_tile()`, minimal diagonal rule
- `_compute_back_wall_bitmask(world_pos) -> int` — same via `world_data.has_back_wall()`

**Splat functions (new):**
- `_load_splat_textures()` — loads all splat variant textures at startup
- `_create_splat_sprite(world_pos, tile_type) -> Sprite2D` — creates 32x32 centered sprite, picks variant by position hash, checks surface vs underground
- `_remove_splat_sprite(world_pos, chunk_coord)` — removes splat sprite on mine

**Modified functions:**
- `_build_tileset()` — add bitmask lookup + autotile sources + back wall sources
- `_get_tile_visual(world_pos, tile_type)` — tileset: bitmask lookup. Splat: returns empty (handled separately as Sprite2D). Fallback: colored rect.
- `_create_chunk_visuals()` — after TileMapLayer population, iterate tiles again for splat types → create Sprite2D nodes. Back wall loop uses separate `_get_back_wall_visual()`.
- `_on_tile_mined()` — remove splat sprite if applicable, update neighbors
- `_on_tile_placed()` — create splat sprite if applicable, update neighbors
- `_on_back_wall_mined/placed()` — neighbor visual updates for back walls
- `_unload_chunk()` — clean up splat sprites via `_chunk_splat_sprites`

## Bitmask
```
bit 7: NW | bit 0: N  | bit 1: NE
bit 6: W  |  (center) | bit 2: E
bit 5: SW | bit 4: S  | bit 3: SE
```
N=1, NE=2, E=4, SE=8, S=16, SW=32, W=64, NW=128. Diagonals only if both adjacent cardinals present. 47 valid values. Lookup table verified against `tiles.png` during implementation.

### Verified Tile Atlas Layout

12x4 grid (48 cells, 47 used). Each cell shows the bitmask value at that atlas position `(col, row)`.

| Row | Col 0 | Col 1 | Col 2 | Col 3 | Col 4 | Col 5 | Col 6 | Col 7 | Col 8 | Col 9 | Col 10 | Col 11 |
|-----|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|--------|--------|
| 0   | 16    | 20    | 84    | 80    | 213   | 92    | 116   | 87    | 28    | 125   | 124    | 112    |
| 1   | 17    | 21    | 85    | 81    | 29    | 127   | 253   | 113   | 31    | 119   | --     | 245    |
| 2   | 1     | 5     | 69    | 65    | 23    | 223   | 247   | 209   | 95    | 255   | 221    | 241    |
| 3   | 0     | 4     | 68    | 64    | 117   | 71    | 197   | 93    | 7     | 199   | 215    | 193    |

**Block structure:**
- **Cols 0-3:** No-diagonal basic tiles (isolated, cardinals, corridors, L/T/cross shapes)
- **Cols 4-7:** Diagonal variants (partial diagonal fills)
- **Cols 8-11:** Full corners/edges with diagonals (outer corners, T-junctions, inner corners, full)

Note: Cell (10, 1) is empty -- no bitmask value maps to it (47 tiles in 48 cells).

## Performance
- Chunk gen: +8 dict lookups per tileset tile + Sprite2D creation per splat tile — negligible
- Splat sprites: ~5-20 per chunk (ores are sparse) — much fewer than the 1024 tilemap cells
- Mine/place: 9 tiles recalculated + 1 splat sprite created/removed
- Memory: ~50KB per tileset texture, ~4KB per splat texture

## Edge Cases
- **World boundary:** `has_tile()` returns true for out-of-bounds → no edges at world edge
- **Back wall with no back_wall.png:** Falls back to colored rect with modulate (existing behavior)
- **Splat at chunk boundary:** 32x32 sprite overflows by 8px into adjacent chunk area — visually fine, sprite lives in originating chunk
- **Splat tile behind tileset tile:** Won't happen — each world position has exactly one tile type
- **Water:** Treated as filled in bitmask → no edges against water

## Verification
1. Dirt renders with autotile edges against air (surface and underground tunnels)
2. Dirt back walls render with back_wall.png (parallax gaps visible)
3. Mining dirt → neighbors update their edges
4. Ores (when splat art added) render as 32x32 popping out of wall
5. Surface ores use surface variant, underground ores use normal variant
6. Stone/tiles without art → colored rectangles (unchanged)
7. Save/load → correct rendering (bitmask + variant selection computed at render time)
8. Chunk load/unload → splat sprites properly created and cleaned up
