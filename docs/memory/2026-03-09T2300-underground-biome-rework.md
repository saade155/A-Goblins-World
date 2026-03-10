# Session: Underground Biome Rework Implementation

**Date:** 2026-03-09
**Commit:** `4858b40` on main
**Status:** Core rework implemented. Deep biome balance pass needed (volcanic/swamp/fungal containment).

## What We Did

### 1. Voronoi Seed-Based Underground Biome Regions
- **Problem:** Macro-cell noise grid produced scattered, fragmented underground biome patches instead of large cohesive regions.
- **Fix:** Replaced with Voronoi seed-based placement. Each surface biome zone seeds its paired underground biome directly below. Deep biomes (volcanic/crystal/fungal) seeded with 2.0x weight penalty so they don't dominate.
- **Standard caverns** wins as dominant background biome via 0.65x distance multiplier in the Voronoi calculation.

### 2. Domain-Warped Voronoi Boundaries
- Anisotropic Y scaling for organic blob shapes instead of geometric cell edges.
- Domain warping applied to Voronoi boundaries for natural-looking transitions.

### 3. Drunk-Walk Tendrils for Organic Biomes
- Swamp depths, fungal grove, and volcanic depths get drunk-walk tendrils extending from their Voronoi cores.
- Creates organic, non-geometric biome boundaries for these specific biome types.

### 4. Broken Spiderweb Cave Network
- MST-connected cavern rooms form the backbone cave structure.
- Pruned extra tunnels added on top for variety.
- Worm caves layered on top of the spiderweb network.

### 5. World Size & Terrain Changes
- **World sizes increased:** Small 2400x1000, Medium 3600x1200, Large 4800x1500 (more sky space).
- **Surface biome zones widened:** Fewer but larger biomes per world.
- **Ridged noise** for jagged mountain height profiles.
- **Depth palette simplified:** STONE -> HARD_STONE -> DEEP_ROCK (removed DIRT tier; subsurface handles soil per-biome).
- **Mountains:** subsurface_depth=5 with stone all the way down via depth palette.
- **Beach/desert:** set to allows_water=false.

### 6. World Collision Borders
- 4 StaticBody2D walls at world edges to prevent player from leaving the world bounds.

### 7. Infrastructure
- SaveManager stray 'm' character fix.
- GUT 9.6.0 testing framework added with 44 tests across 5 files.

## Key Decisions
- **Voronoi over noise** for biome placement -- gives large cohesive regions instead of scattered fragments.
- **Standard caverns as dominant background** biome, not just one of many (0.65x distance multiplier).
- **No DIRT in depth palette** -- each biome's subsurface layer handles its own soil type.
- **subsurface_depth should stay small** (5-8) to avoid suppressing cave generation.

## Known Issues for Future
- Volcanic depths (abyss) layer too tall at bottom of world.
- Swamp/fungal biomes extend all the way to world bottom -- needs containment.
- General deep biome balance pass needed.
- Desert test risky (all caves at seed 42 sample location).

## Plan Doc
- `docs/plans/underground-biome-rework.md` -- full design and implementation details.
