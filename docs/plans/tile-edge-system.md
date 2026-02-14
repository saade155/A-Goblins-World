# Tile Edge & Ore Overlay System — Design

## Problem
The current autotile system uses a 4-bit cardinal bitmask + separate diagonal inner corner checks (20 tile variants). This doesn't scale to all combinations — tiles with edges + inner corners, opposite corner pairs, and other combos show incorrect visuals. A full 47-tile blob autotile would cover everything but requires significant art per tile type per biome.

## Current State (Working)
- 16 cardinal bitmask variants + 4 inner corners = 20 tiles per type
- Covers ~80% of cases correctly (all cardinal edges, single inner corners)
- Breaks on: multiple inner corners, edge + inner corner combos, opposite corner pairs
- Stone and dirt tiles have art; all others use procedural colored squares

## Rendering Layers (per chunk)

The system uses 3 overlay TileMapLayers on top of the existing base layer, plus torches and darkness:

```
Torches          (Z=-1)  — torch sprites
Base layer       (Z=0)   — interior tile fills, collision
Edge overlay     (Z=1)   — tile edges/corners (renders behind player)
Player           (Z=2)   — player z_index set to 2
Ore overlay      (Z=3)   — ore protrusions extending into neighbor tiles (renders in front of player)
Darkness         (Z=5)   — darkness/lighting overlay
```

The edge overlay renders behind the player for natural depth. The ore overlay renders in front of the player so ore protrusions feel like they're jutting out of the cave walls toward the viewer.

## Edge Overlay System (Option A — Chosen)

**Concept:** Tiles render as interior-only textures (center variant). Edges, corners, and depth effects are rendered as transparent overlays on the edge overlay layer (Z=1).

**How it works:**
- Base layer (Z=0): every tile renders its center/interior texture (the tileable material)
- Edge overlay layer (Z=1): overlays edge sprites on exposed faces
- Each edge piece is a small transparent sprite showing the material edge treatment
- Bitmask logic determines which edge pieces to place (same 8-neighbor check)

**Art per tile type:**
- 1 interior texture (tileable 32x32)
- 4 cardinal edge strips (top, right, bottom, left — could be 32x32 with transparency)
- 4 outer corner pieces
- 4 inner corner pieces
- = 13 edge pieces + 1 base = 14 total (similar to current but decoupled)

**Advantages:**
- Edges decouple from base texture — can swap edge style per biome without redrawing base material
- Natural home for depth effects (floor lit faces, ceiling shadows, wall shading from art guidelines)
- Building/structure edges use the same system with different edge art
- Easy to add lighting/shadow hints to edges
- Base tiles become trivially tileable (just the material texture, no edge variants)

**Concerns:**
- Additional TileMapLayer per chunk for edge rendering
- Need to define edge sprite format and overlay positioning
- Transparency blending at pixel art scale needs care

**Aligns with art guidelines:**
- Layer model already defines depth faces (top edges = lit floor, bottom edges = shadowed ceiling)
- "Same-type tile boundaries have organic, irregular edges" — overlay approach lets these be separate art pieces
- Back wall tiles (darker recessed variants) could use same overlay system

## Ore Overlay System

**Concept:** Ore tiles (iron, gold, crystal, etc.) have protrusion sprites that extend beyond the 32x32 tile boundary into neighboring tiles. These render on the ore overlay layer (Z=3), in front of the player, creating visual depth — crystals and metal chunks poking out of cave walls toward the viewer.

**How it works:**
- Ore tiles that form veins tile together properly; only vein edges get protrusion sprites
- Same neighbor-detection logic as edge tiles but applied to ore types: check if neighbor is the same ore type
- If neighbor is NOT the same ore type (i.e., this is a vein edge), place a protrusion sprite extending 4-8px into that neighbor
- Protrusions overlay neighboring stone/dirt — they don't replace the neighbor tile

**Art per ore type:**
- 4 cardinal protrusion strips (top, right, bottom, left)
- 4 outer corner protrusion pieces (TL, TR, BL, BR)
- 4 inner corner protrusion pieces (TL, TR, BL, BR)
- = 12 protrusion pieces (or a simpler 4-cardinal subset to start)
- Each piece is 32x32 with transparency, positioned on the neighboring tile's cell
- Protrusions extend 4-8px from the ore boundary into the neighbor

**Visual effect:**
- Iron ore: small metallic chunks poking into adjacent stone
- Crystal ore: crystalline shards jutting into neighboring tiles
- Gold ore: nugget clusters breaking the tile boundary
- Renders in front of the player — creates a sense of the ore deposits having real physical presence

**Vein-aware rendering:**
- Two adjacent iron tiles: no protrusion between them (they're the same vein)
- Iron tile next to stone tile: iron protrusion extends into the stone tile
- This prevents veins from looking spiky internally while maintaining dramatic edges

## Option B: Quarter-Tile System (Rejected)

**Concept:** Split each 32x32 tile into four 16x16 quadrants. Each quadrant independently selects from ~4 variants based on its 3 nearest neighbors (2 cardinals + 1 diagonal).

**Why rejected:**
- 4x the tile cells per chunk (64x64 instead of 32x32)
- Doesn't naturally handle depth/lighting effects (would still need overlay for that)
- The 3-layer overlay system handles edges, depth, and ore protrusions — quarter-tiles add redundant complexity

Remains viable as a fallback if the overlay approach proves too complex or has performance issues.

## Recommendation

**Use the 3-layer system** because:
1. The depth/floor/ceiling visual system from the art guidelines requires an overlay approach anyway
2. Edge treatment is a natural part of that overlay — not a separate system
3. Ore protrusions add significant visual richness with minimal additional complexity (same neighbor-detection logic)
4. Base tiles simplify to just the tileable interior texture (less art, more reuse)
5. Z-ordering gives clear visual layering: edges behind player, ore in front of player

## Next Steps (When Ready)
1. Design the edge sprite format (size, positioning, transparency approach)
2. Design ore protrusion sprite format (extension distance, transparency)
3. Prototype with stone tiles: center texture + 4 cardinal edge overlays
4. Prototype with one ore type: protrusion sprites on vein edges
5. Evaluate visual quality and performance with all 3 layers active
6. Extend to depth effects (floor/ceiling/wall shading)
