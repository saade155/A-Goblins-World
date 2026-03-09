# Underground Biome Rework

## Problem Summary

The current underground biome system uses a macro-cell grid (8x8 tiles) with noise-based biome assignment. "Forced pairing" overwrites some cells under surface biomes, but the result is:

1. **No vertical continuity** — Surface biomes cut off sharply; paired underground biomes appear as disconnected patches elsewhere
2. **Rectangular biome shapes** — Macro-cell grid creates blocky, unnatural regions
3. **Scattered deep biomes** — Volcanic depths and crystal caverns are noise-sprinkled rather than consolidated regions
4. **Bottom layer too uniform** — One biome dominates the entire bottom of the world
5. **Surface biome zones too small** — Biomes feel like thin strips, not regions
6. **Mountains lack underground presence** — Dirt layer under mountains instead of deep stone
7. **Mountains too smooth** — Gradual height profile, needs jagged peaks and dips
8. **Not enough sky space** — No room reserved for future sky biomes (cloud layers, sky islands, beanstalk destinations)

---

## Design: Noise-Wobbled Column Ownership

Replace the macro-cell grid with a **column ownership** model where each surface biome owns the underground directly beneath it, with organic noise-wobbled boundaries.

### Core Algorithm

For any underground position `(x, y)`:

1. Compute depth below surface: `depth = y - surface_height(x)`
2. Compute a wobbled X position: `effective_x = x + biome_wobble_noise(x, y) * wobble_amount(depth)`
3. Look up which surface biome zone `effective_x` falls in
4. Return that surface biome's `paired_underground_biome`
5. If `depth > continuity_depth`, check for deep biome pocket overrides

The **wobble amount increases with depth**, so biome boundaries near the surface closely follow the surface zones but twist and spread as you go deeper. This creates organic, flowing shapes without expensive algorithms.

### Wobble Parameters

```
WOBBLE_NOISE_SCALE = 0.02       # Low frequency for smooth curves
WOBBLE_BASE = 4.0               # Slight wobble near surface (tiles)
WOBBLE_PER_DEPTH = 0.15         # Additional wobble per tile of depth
WOBBLE_MAX = 60.0               # Cap to prevent extreme shifts
```

At depth 0: wobble = 4 tiles (nearly vertical boundary)
At depth 100: wobble = 19 tiles (moderate spread)
At depth 300: wobble = 49 tiles (significant spread)
At depth 400+: wobble = 60 tiles (capped)

---

## Underground Biome Tiers

### Tier 1: Paired Biomes (surface to continuity_depth)

Each surface biome's paired underground biome extends directly below it:

| Surface Biome | Paired Underground | Continuity Depth |
|---|---|---|
| Forest | Standard Caverns | 80 |
| Desert | Sandy Hollows | 60 |
| Swamp | Swamp Depths | 60 |
| Mountains | Standard Caverns | 120 (deep stone) |
| Snowy Peaks | Frozen Caverns | 80 |
| Beach | Sandy Hollows | 30 |
| Ocean | Sandy Hollows | 30 |

Mountains get the deepest continuity — solid stone extending far underground.

### Tier 2: Transition Biomes (mid-depth, 40-70% of world depth)

Below continuity depth, independent biomes appear as **consolidated pockets**:

- **Fungal Growth** — Large organic regions, preferentially spawns below/adjacent to swamp_depths
- **Crystal Caverns** — Concentrated veins/pockets, preferentially near frozen_caverns and deep standard_caverns

These are placed as **large noise-defined regions**, not scattered cells. Use a separate low-frequency noise layer with a high threshold to create a few big pockets rather than many small ones.

### Tier 3: Deep Biome (bottom 20-25% of world)

- **Volcanic Depths** — A consolidated band/region at the bottom of the world. Not scattered noise — a solid presence with irregular upper boundary (noise-wobbled ceiling). Covers most of the bottom but with standard_caverns or crystal_caverns intrusions breaking up uniformity.

### Depth Palette Override

Within any underground biome, the base tile still uses depth-relative selection:
- Shallow: biome primary tile
- Mid: biome secondary tile mixed in
- Deep: harder variants (HARD_STONE, DEEP_ROCK for standard_caverns)

This creates visual variety within each biome region.

---

## Underground Adjacency Rules

Which underground biomes can share a boundary:

| Biome | Can Border |
|---|---|
| Standard Caverns | All biomes (default/universal) |
| Sandy Hollows | Standard Caverns, Swamp Depths, Volcanic Depths, Fungal Growth |
| Swamp Depths | Standard Caverns, Sandy Hollows, Fungal Growth |
| Frozen Caverns | Standard Caverns, Crystal Caverns |
| Crystal Caverns | Standard Caverns, Frozen Caverns, Volcanic Depths, Fungal Growth |
| Fungal Growth | Standard Caverns, Sandy Hollows, Swamp Depths, Crystal Caverns, Volcanic Depths |
| Volcanic Depths | Standard Caverns, Sandy Hollows, Crystal Caverns, Fungal Growth |

**Cannot border (temperature/logic clash):**
- Frozen Caverns ↔ Volcanic Depths
- Frozen Caverns ↔ Sandy Hollows
- Frozen Caverns ↔ Swamp Depths
- Sandy Hollows ↔ Crystal Caverns

When two incompatible biomes would meet, **Standard Caverns acts as a buffer zone** between them (thin strip of default stone separating incompatible biomes).

---

## Deep Biome Pocket Placement

Instead of noise-scattered cells, deep biomes are placed as **seeded regions**:

### Fungal Growth Placement
1. Find all swamp surface zones
2. For each, seed a fungal growth pocket starting at `continuity_depth` below the swamp
3. The pocket grows downward and spreads horizontally using noise-defined boundaries
4. Size: 80-150 tiles wide, 60-120 tiles tall
5. Can also spawn independently in deep standard_caverns (smaller pockets)

### Crystal Caverns Placement
1. Seed pockets at mid-depth (40-60% of world depth)
2. Prefer locations under frozen_caverns or deep standard_caverns
3. Size: 60-120 tiles wide, 40-80 tiles tall
4. 2-4 pockets per world (Small), scaling with world size

### Volcanic Depths Placement
1. Solid band across the bottom 15-20% of world depth
2. Upper boundary is noise-wobbled (not a flat line) — creates peaks and valleys in the volcanic ceiling
3. Standard Caverns or Crystal Caverns intrusions punch into the volcanic band for variety
4. Width: spans most of the world width, but not 100% — gaps at edges under ocean

---

## Mountain Height Profile

### Problem
Current mountains use smooth FastNoiseLite, producing gentle rolling hills.

### Solution: Layered Noise for Mountains
Mountains and Snowy Peaks get a special height calculation:

```
base_noise          # Low frequency, overall shape (existing)
+ ridged_noise      # |1 - 2*abs(noise)| creates sharp peaks
+ detail_noise * 3  # High frequency for jagged small-scale variation
```

**Ridged noise** creates V-shaped valleys and sharp ridges — exactly the jagged mountain profile wanted. Applied only when the surface biome is mountains or snowy_peaks.

### Updated Mountain Parameters
```
Mountains:
  base_height: -60       # Taller overall (was -50)
  height_amplitude: 50   # More variation (was 40)
  detail_amplitude: 8    # More jagged (was 5)
  ridged_amplitude: 25   # NEW — sharp peaks

Snowy Peaks:
  base_height: -55       # Taller (was -45)
  height_amplitude: 45   # More variation (was 35)
  detail_amplitude: 7    # More jagged (was 4)
  ridged_amplitude: 20   # NEW — sharp peaks
```

### Mountains Underground
- Mountains' `subsurface_tile` is already STONE
- `continuity_depth = 120` ensures deep stone columns
- No dirt layer — solid stone from surface to deep underground

---

## World Vertical Proportions

### Current (Small World)
```
Height: 800 tiles
Surface at: ~row 100 (from top)
Sky space: ~100 tiles (1600px)
Underground: ~700 tiles
```

### Proposed (Small World)
```
Height: 1000 tiles
Surface at: ~row 250 (from top)
Sky space: ~250 tiles (4000px)
Underground: ~750 tiles
```

This gives:
- **Sky (250 tiles):** Room for cloud layers, sky islands, beanstalk destinations, hidden content. Large enough that finding things requires deliberate searching.
- **Surface (thin band):** Biome surfaces, as now.
- **Underground (750 tiles):** Slightly more than current. Plenty of depth for tiered biomes.

### World Size Updates
| Size | Current | Proposed |
|---|---|---|
| Small | 2400 × 800 | 2400 × 1000 |
| Medium | 3600 × 1000 | 3600 × 1200 |
| Large | 4800 × 1200 | 4800 × 1500 |

`surface_rows` renamed to `surface_offset` (distance from top to surface baseline): 250 / 300 / 350.

---

## Surface Biome Width

### Current Width Percentages
```
Forest:      15-25%
Desert:      10-18%
Swamp:        8-15%
Mountains:   10-18%
Snowy Peaks:  8-15%
Beach:        3-6%
Ocean:        4-8%
```

### Proposed Width Percentages
Make core biomes larger, keep transition biomes (beach, ocean) small:

```
Forest:      18-30%
Desert:      14-22%
Swamp:       12-20%
Mountains:   14-22%
Snowy Peaks: 10-18%
Beach:        3-6%    (unchanged)
Ocean:        5-10%
```

This means fewer total biome zones per world but each feels like a real region. A Small world (2400 tiles) would have roughly 4-5 major biomes (plus edge ocean/beach) instead of 6-7 tiny ones.

---

## Transition Blending

All biome boundaries (horizontal and vertical) use gradient blending:

### Horizontal (between adjacent surface biome columns)
- `transition_width` per biome (default 12 tiles)
- Tiles in the blend zone probabilistically come from either neighbor
- Use `_hash_position()` for deterministic randomness

### Vertical (subsurface → paired underground)
- Existing 12-tile transition zone
- Smooth probability ramp from 100% subsurface to 100% underground tiles

### Deep biome boundaries
- Where paired biome meets a deep biome pocket, 8-12 tile blend
- Where two deep biomes meet, 6-8 tile blend
- Incompatible biomes get a thin Standard Caverns buffer (4-6 tiles) instead of direct blending

---

## Cave System: Broken Spiderweb

Replace the current cave generation (pure noise threshold + worm caves) with a structured cavern network overlaid with organic worm tunnels.

### Cavern Rooms (Nodes)

Scatter large open chambers throughout the underground:

- **Size range:** 15-40 tile diameter (irregular shapes, not perfect circles)
- **Shape:** Use noise-masked circles/ellipses for natural, non-uniform edges
- **Density:** Scales with world size. ~30-50 caverns for Small world
- **Placement rules:**
  - Minimum spacing between cavern centers (40-60 tiles)
  - Denser in mid-depth, sparser near surface and at volcanic depths
  - Biome-influenced: swamp_depths and fungal_growth get more/larger caverns; frozen_caverns get fewer, tighter ones
  - No caverns within 20 tiles of surface (preserve terrain integrity)

### Tunnel Network (Edges)

Connect caverns into a web-like network:

1. **Build connectivity graph** — For each cavern, find the 3-5 nearest neighbors
2. **Ensure reachability** — Use minimum spanning tree as backbone so no cavern is fully isolated
3. **Add extra connections** — Layer additional edges from the neighbor graph on top of MST
4. **Break the web** — Remove 30-40% of the extra connections (not MST edges). Creates dead ends and forces alternate routing
5. **Carve tunnels** — Along remaining edges, carve wobbling passages between cavern rooms

### Tunnel Variety

- **Width varies along length:** 2-3 tiles (tight crawlspace) to 5-8 tiles (wide corridor)
- **Width pulsing:** Sine-based or noise-based variation as the tunnel progresses
- **Wobble:** Tunnels don't follow straight lines — drunk-walk deviation from the ideal path
- **Vertical shafts:** Some connections go steeply up/down between depth layers, giving vertical exploration

### Worm Caves (Chaos Layer)

Keep the existing drunk-walk worm system as an **additional organic layer**:

- Worms carve independently of the structured network
- Occasionally intersect caverns or tunnels, creating surprise shortcuts
- Provide unpredictable exploration between the structured web
- Current count (WORMS_BASE_COUNT = 45) may need tuning after the cavern network is in place

### Biome Interaction

- Cavern room tiles match the underground biome they're placed in (e.g., cavern in sandy_hollows has sand walls)
- Tunnels through biome boundaries show the transition between biome tiles
- Larger caverns in organic biomes (swamp_depths, fungal_growth), tighter in frozen/crystal
- Volcanic depths: fewer but more dramatic chambers (lava lakes in future)

### Generation Order

1. Place cavern rooms (after biome map is built, so rooms know their biome)
2. Build connectivity graph + MST
3. Add and prune extra connections
4. Carve tunnels between connected rooms
5. Run worm caves on top
6. Apply cave noise threshold for small natural pockets (existing system, reduced influence)

---

## Implementation Order

1. **World size + sky space** — Update WORLD_SIZE_PRESETS, surface_offset. Adjust spawn, sea level, and all Y-relative code.
2. **Surface biome widths** — Update min/max width percentages in registry.
3. **Mountain height profile** — Add ridged noise layer, update parameters.
4. **Column ownership biome map** — Replace `_generate_biome_map()` with noise-wobbled column lookup. Remove macro-cell grid.
5. **Cave system** — Cavern room placement, tunnel network (MST + pruned extras), worm caves on top.
6. **Deep biome pocket placement** — Fungal, Crystal, Volcanic as consolidated regions.
7. **Transition blending** — Ensure smooth boundaries everywhere.
8. **Update tests** — Adapt existing 43 tests to new system, add new tests for wobble boundaries and deep pocket placement.
9. **Visual verification** — Generate worlds, check map display for expected biome shapes.

---

## Save Compatibility

This changes world generation fundamentally. Existing saves will load fine (they store tile data directly), but generating a new world will produce very different results. No save version bump needed since we're only changing generation, not the save format.
