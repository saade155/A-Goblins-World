# Sprite Sheet Specification

Reference for all sprite sheet formats used in the project.

---

## Player Character Sheet (`player_goblin_base.png`)

**Format:**

- Frame size: 32x48px
- Sheet width: 10 columns (320px)
- Left-facing art, `flip_h` for right
- Body centered in frame (no root motion)

**Row Map:**

| Row | Animation        | Frames | Notes                        |
|-----|------------------|--------|------------------------------|
| 0   | Walk             | 8      | Looping                      |
| 1   | Run              | 8      | Looping                      |
| 2   | Jump/Fall        | 10     | Frames 0-7 jump, 8-9 fall   |
| 3   | Idle (base)      | 1      | Default standing pose        |
| 4   | Idle - Ear twitch| 1      | Random idle variant          |
| 5   | Idle - Blink     | 1      | Random idle variant          |
| 6   | Idle - Fidget    | 1      | Random idle variant          |
| 7+  | Reserved         | -      | Future: attack, mine, etc.   |

---

## Template Types

Different entity types may use different sheet formats. Each template defines its own frame size, column count, and row map.

| Template | Frame Size | Columns | Used By      |
|----------|------------|---------|--------------|
| player   | 32x48      | 10      | Player goblin|

New templates should be added to this table as they are created. Each template must document its own row map in a dedicated section above.

## Tile Sheet Layout (`stone_tiles.png`, `dirt_tiles.png`, etc.)

**Sheet size:** 16x9 tiles (512x288px), 32x32 tiles per cell

### Spatial Grid (Cols 0-7, Rows 0-7)

Tiles (T), edges (E), and corners (C) are arranged in a spatial layout that mirrors how tiles connect in-game. The grid contains four quadrants showing different tile configurations in context.

**Legend:**
- **C** = Corner overlay — transparent, placed on empty diagonal neighbor cell
- **E** = Edge overlay — transparent, placed on empty cardinal neighbor cell
- **T** = Tile — the actual solid tile with baked-in edge appearance, placed on base layer
- **V** = Variant — alternate fill texture for center/top-edge tiles (noise-selected)
- **I** = Inner corner overlay — placed on empty diagonal neighbor cell; direction named from the empty cell's perspective (e.g., ITL = solid mass is at top-left of the empty cell)
- **I'** = Alternate inner corner decoration variant

```
         Col:  0  1  2  3  4  5  6  7  8     9-15
Row  0:       C  E  E  E  C  C  E  C  ITL   V ...
Row  1:       E  T  T  T  E  E  T  E  ITR   V ...
Row  2:       E  T  T  T  E  E  T  E  IBL   V ...
Row  3:       E  T  T  T  E  E  T  E  IBR   V ...
Row  4:       C  E  E  E  C  C  E  C  ITL'  V ...
Row  5:       C  E  E  E  C  C  E  C  ITR'  V ...
Row  6:       E  T  T  T  E  E  T  E  IBL'  V ...
Row  7:       C  E  E  E  C  C  E  C  IBR'  V ...
Row  8:       -  -  -  -  -  -  -  -  -     V ...
```

### Four Quadrants

| Quadrant | Cols | Rows | Shows |
|----------|------|------|-------|
| Top-left | 0-4 | 0-4 | 3-wide x 3-tall block (standard edges) |
| Top-right | 5-7 | 0-4 | 1-wide x 3-tall column (vertical shaft) |
| Bottom-left | 0-4 | 5-7 | 3-wide x 1-tall row (horizontal tunnel) |
| Bottom-right | 5-7 | 5-7 | 1-wide x 1-tall (isolated/alone tile) |

### Tile Positions (T) — Bitmask Mapping

Each T position corresponds to a 4-bit cardinal bitmask (bit 0=N, 1=E, 2=S, 3=W). 16 positions cover all neighbor combinations.

**3x3 Block (top-left quadrant):**

| Coord | Bitmask | Neighbors | Position |
|-------|---------|-----------|----------|
| (1,1) | 6 | E+S | TL corner |
| (2,1) | 14 | E+S+W | Top edge |
| (3,1) | 12 | S+W | TR corner |
| (1,2) | 7 | N+E+S | Left edge |
| (2,2) | 15 | N+E+S+W | Center |
| (3,2) | 13 | N+S+W | Right edge |
| (1,3) | 3 | N+E | BL corner |
| (2,3) | 11 | N+E+W | Bot edge |
| (3,3) | 9 | N+W | BR corner |

**Vertical Shaft (top-right quadrant):**

| Coord | Bitmask | Neighbors | Position |
|-------|---------|-----------|----------|
| (6,1) | 4 | S | Top cap |
| (6,2) | 5 | N+S | Vert bar |
| (6,3) | 1 | N | Bot cap |

**Horizontal Bar (bottom-left quadrant):**

| Coord | Bitmask | Neighbors | Position |
|-------|---------|-----------|----------|
| (1,6) | 2 | E | Left cap |
| (2,6) | 10 | E+W | Horiz bar |
| (3,6) | 8 | W | Right cap |

**Isolated (bottom-right quadrant):**

| Coord | Bitmask | Neighbors | Position |
|-------|---------|-----------|----------|
| (6,6) | 0 | None | Alone |

### Edge Overlays (E)

Placed on empty cardinal neighbor cells. Each direction has up to 4 visual variants (3 from the 3x3 block + 1 from the narrow configuration), selected by noise.

| Direction | Variant 1 | Variant 2 | Variant 3 | Variant 4 |
|-----------|-----------|-----------|-----------|-----------|
| Top | (1,0) | (2,0) | (3,0) | (6,0) |
| Bottom | (1,4) | (2,4) | (3,4) | (6,4) |
| Left | (0,1) | (0,2) | (0,3) | (5,1) |
| Right | (4,1) | (4,2) | (4,3) | (7,1) |

### Corner Overlays (C)

Placed on empty diagonal neighbor cells. 4 visual variants per corner (one from each quadrant), selected by noise.

| Corner | Variant 1 | Variant 2 | Variant 3 | Variant 4 |
|--------|-----------|-----------|-----------|-----------|
| TL | (0,0) | (5,0) | (0,5) | (5,5) |
| TR | (4,0) | (7,0) | (4,5) | (7,5) |
| BL | (0,4) | (5,4) | (0,7) | (5,7) |
| BR | (4,4) | (7,4) | (4,7) | (7,7) |

### Inner Corner Overlays (Col 8)

Placed on empty diagonal neighbor cells where both adjacent cardinal neighbors are filled. Direction named from the empty cell's perspective (e.g., ITL means solid mass is at top-left of the empty cell). Two variants per direction (base + alternate decoration), selected by noise.

| Direction | Base | Alternate |
|-----------|------|-----------|
| ITL | (8,0) | (8,4) |
| ITR | (8,1) | (8,5) |
| IBL | (8,2) | (8,6) |
| IBR | (8,3) | (8,7) |

### Variant Fills (Cols 9-15)

Up to 7 alternate fill textures per tile position, selected by noise. Blank cells are skipped (not considered valid variants). Only the 3x3 block tile positions receive variants — caps, bars, and the alone tile use their default T position only.

**Rarity tiers (contiguous, weighted by noise):**

| Cols | Tier | Count | Selection Weight |
|------|------|-------|-----------------|
| 9-11 | Common | 3 | ~60% |
| 12-13 | Uncommon | 2 | ~25% |
| 14-15 | Rare | 2 | ~15% |

| Row | Tile Position | Bitmask |
|-----|--------------|---------|
| 0 | Top Left | 6 |
| 1 | Top Center | 14 |
| 2 | Top Right | 12 |
| 3 | Left Center | 7 |
| 4 | Center | 15 |
| 5 | Right Center | 13 |
| 6 | Bottom Left | 3 |
| 7 | Bottom Center | 11 |
| 8 | Bottom Right | 9 |

### Rendering Layers

Overlay layers handle edge, corner, and inner corner pieces on empty cells only. No tile-side overrides — the T positions handle tile appearance directly on the base layer.

| Layer | Z | Content |
|-------|---|---------|
| Base | 0 | Solid tiles (T positions from bitmask) |
| Edge - Floor | 1 | Top edge overlays |
| Edge - Wall L | 2 | Left edge overlays |
| Edge - Wall R | 3 | Right edge overlays |
| Edge - Ceiling | 4 | Ceiling/bottom edge overlays |
| Player | 5 | Player sprite |
| Darkness | 7 | Light map |
