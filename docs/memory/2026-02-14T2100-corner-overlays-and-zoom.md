# Session: M4.6 Corner Overlay Fixes + Pixel-Perfect Zoom

**Date:** 2026-02-14
**Commit:** `45296fe` — M4.6: Corner overlay system and pixel-perfect zoom
**Status:** M4.6 complete and working. Next: M4.7 (Enhanced Save System)

## What We Did

### 1. Fixed Edge/Corner Layer Conflicts
- **Problem:** 1x1 gaps with 3+ solid neighbors had missing edges — inner corners overwrote straight edges on shared TileMapLayers (last-write-wins on `set_cell()`).
- **Fix:** Added 4 dedicated corner TileMapLayers (corner_se Z=5, corner_sw Z=6, corner_ne Z=7, corner_nw Z=8). Shifted Player to Z=9, Darkness to Z=11. Inner corners now use their own layers, no conflicts with edge layers.

### 2. L-shape Corner Fill (New Overlay Type)
- **Problem:** Diagonal solid configurations (two adjacent cardinal solids, diagonal between them empty) had no corner fill, leaving visible gaps when edges are tapered.
- **Fix:** Empty cell detects the L-shape, gets the lower-priority (higher Y) tile's corner art, and **pushes** the overlay onto the higher-priority (lower Y) solid cell. Uses CORNER_ATLAS with context-based selection.
- **Key design:** The overlay goes on a SOLID cell, not the empty cell. This is unique among the overlay types.

### 3. Context-Based Corner Selection
- **Problem:** `get_corner_coords()` used noise-based random selection from 4 CORNER_ATLAS entries. These entries are NOT variants — they're the 4 spatial quadrant contexts (block/pillar/bar/alone) in columns 0-7.
- **Fix:** Added `get_corner_coords_contextual(corner_name, adj_vertical, adj_horizontal)` in tile_data.gd. Checks source tile's full cardinal neighborhood (N/S for vertical, E/W for horizontal) to determine overall shape. Index: 0=block, 1=pillar, 2=bar, 3=alone.
- **Applied to:** Both outer corners and L-shape corners.

### 4. Pixel-Perfect Discrete Zoom
- **Replaced** analog smooth zoom (lerp-based, 0.1 step) with 3 discrete integer levels: 1.0x, 2.0x, 3.0x.
- **Learned:** Non-integer zoom (e.g., 1.5x) causes sub-pixel artifacts in Godot — sprite bleeding, pixel dithering becoming circles, blurring. Only integer Camera2D zoom values are safe with pixel art.

## Corner Overlay System Summary (3 Types)

| Type | Condition | Placed On | Art Source | Layer |
|------|-----------|-----------|------------|-------|
| Inner corner | Both cardinals + diagonal SOLID | Empty cell | Diagonal tile (INNER_CORNER_OVERLAY_ATLAS) | corner_* |
| Outer corner | Both cardinals EMPTY + diagonal SOLID | Empty cell | Diagonal tile (CORNER_ATLAS contextual) | edge_* |
| L-shape corner | Both cardinals SOLID + diagonal EMPTY | Solid cell (pushed) | Lower-priority cardinal (CORNER_ATLAS contextual) | edge_* |

## Decisions Made
- Edge cache system discussed but deferred — noise is deterministic from seed, so variations recalculate identically on load. No need to persist edge data.
- M4.7 (Enhanced Save System) is next — plan already in `docs/plans/save-system.md`.

## Files Changed
- `scripts/world/chunk_manager.gd` — corner layers, L-shape logic, context-based corners, debug panel updates
- `scripts/data/tile_data.gd` — `get_corner_coords_contextual()` function
- `scenes/player/player.gd` — discrete zoom levels
- `scenes/player/player.tscn` — z_index updated to 9
- `assets/tilesets/stone_tiles.png` — Christian's art updates
