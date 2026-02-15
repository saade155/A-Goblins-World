# Tile Edge & Overlay System — Design (Revised)

## Problem
The current 20-variant bitmask autotile doesn't scale to all edge/corner combinations. A compositional overlay approach eliminates combinatorial explosion.

## Core Concept: Compositional Overlays

Instead of baking edges into tile variants, edges are independent transparent overlays stacked on separate TileMapLayers. Inner corners form naturally where overlays overlap — no dedicated inner corner art needed (though materials can add them optionally).

Each tile position has two tile layers:
- **Foreground tile** — solid, collidable, mineable
- **Background tile** — back wall, same material but darker/recessed, visible when foreground is mined

Three visual outcomes per cell:
1. **Foreground + background** — cut/irregular foreground edges reveal darker back wall (depth)
2. **Background only** (foreground mined) — back wall visible, player can walk through
3. **Neither** (both mined) — backdrop/sky/void shows through

## Tile Variation

Each tile type has multiple interior fill variants (e.g., plain dirt, dirt with roots, dirt with pebbles). All variants are tileable with each other. Variant selection uses noise-based mapping for deterministic results that survive save/load without storing per-tile variant data.

## Edge Overlay System

**Per cardinal direction (top, bottom, left, right), two art pieces:**
1. **Edge overlay** — placed on the empty neighbor cell (extends into open space)
2. **Tile-side override** — placed on the tile's own cell (modifies the tile edge)

Both are 32x32 transparent PNGs.

**4 overlay layers per chunk, rendered in priority order:**

| Layer | Z | Content | Draw Order |
|-------|---|---------|------------|
| Edge - Floor (top edges) | 1 | Floor edges drawn first | 1st |
| Edge - Wall L (left edges) | 2 | Left wall edges | 2nd |
| Edge - Wall R (right edges) | 3 | Right wall edges | 3rd |
| Edge - Ceiling (bottom edges) | 4 | Ceiling edges drawn last (on top) | 4th |

This priority ordering (floor → walls → ceiling) gives natural depth — ceiling edges occlude wall edges, wall edges occlude floor edges.

**Inner corners:** Not needed for most materials — they form naturally from overlapping cardinal edge overlays. Materials that need explicit inner corners can add them as optional art pieces.

**Outer corners:** Placed on the empty neighbor cell (diagonal), rendered on the appropriate overlay layer.

## Full Rendering Stack

| Layer | Z | Content |
|-------|---|---------|
| Background tiles | -2 | Back wall (darker material variant) |
| Torches | -1 | Torch sprites |
| Base tiles | 0 | Interior fill (with noise-selected variants), collision |
| Edge - Floor | 1 | Top edge overlays + overrides |
| Edge - Wall L | 2 | Left edge overlays + overrides |
| Edge - Wall R | 3 | Right edge overlays + overrides |
| Edge - Ceiling | 4 | Bottom edge overlays + overrides |
| Player | 5 | Player z_index |
| Ore overlay | 6 | Ore protrusions (in front of player) |
| Darkness | 7 | Lighting overlay |

## Ore Overlay System

Unchanged from original design:
- Ore tiles have protrusion sprites extending 4-8px beyond tile boundary into neighbors
- Renders at Z=6 (in front of player) for physical depth
- Vein-aware: only vein edges get protrusions (same ore neighbors = no protrusion)
- Art per ore type: 4 cardinal protrusions minimum, corners optional

## Art Per Tile Type (Starting with Stone)

| Piece | Count | Description |
|-------|-------|-------------|
| Interior fill variants | 4+ | Tileable 32x32, noise-selected |
| Edge overlays | 4 | Top, right, bottom, left (on neighbor cell) |
| Tile-side overrides | 4 | Top, right, bottom, left (on own cell) |
| Outer corners | 4 | Optional, on diagonal neighbor cell |
| Inner corners | 0-4 | Optional per material, not needed for stone |
| **Total** | **12-16** | Scales per material needs |

## Ceiling Shadow (Deferred)

Global ceiling shadow (gradient overlay on empty cells below solid tiles) is deferred until the lighting system is more developed. Keeping it as a separate overlay (not baked into background variants) preserves flexibility for light interaction.

## Next Steps
1. Finalize stone tile art (interior variants + 8 edge pieces)
2. Implement 4-layer edge overlay system in chunk_manager
3. Add background tile layer
4. Implement noise-based variant selection
5. Test with stone, then extend to dirt and other materials
6. Add ore protrusion system
