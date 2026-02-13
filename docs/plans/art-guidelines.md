# Art Asset Guidelines — This Goblin's World

## Core Specs

| Setting | Value |
|---------|-------|
| **Palette** | ENDESGA-64 (Lospec) — can swap later, engine has no palette dependency |
| **Tool** | Aseprite (recommended) |
| **Viewport** | 640×360, integer scale (3× → 1080p, 4× → 1440p) |
| **Resolution target** | 1440p primary, graceful downgrade to 1080p. Sharper pixels at higher res, same visible area. |
| **Style** | Modern retro — intentionally pixel art, not hardware-limited. Think Celeste/Dead Cells polish, not SNES constraints. |
| **Filtering** | Nearest-neighbor (no anti-aliasing, no sub-pixel) |
| **Format** | PNG export, no compression |

## Size Standards

| Asset Type | Size | Notes |
|-----------|------|-------|
| Tiles (foreground + back walls) | 32×32 | All terrain, ores, decorations |
| Item icons | 32×32 | Inventory/hotbar icons, dropped items |
| Goblin (player) | 32×48 | 1 tile wide, 1.5 tiles tall |
| Small props | 32×32 or 32×64 | Torches, plants, small furniture |
| Crafting stations | 64×64 or 96×64 | Workbench, furnace, anvil |
| UI elements | Multiples of 8px | Buttons, panels, frames (design later in M4-C) |

## Color Palette

**ENDESGA-64** by ENDESGA — download from Lospec and load into Aseprite.

In Aseprite: `Sprite → Color Mode → Indexed`, then load the palette via `Palette → Load Palette`. This locks you to only those 64 colors.

If the palette feels too limiting later, we can switch. The engine has no palette dependency — it's purely an art-side constraint for visual consistency.

## World Layer Model

The game uses a multi-layer depth system for visual richness:

```
[Closest to camera]
  Layer 1: Player, entities, dropped items, particles
  Layer 2: Foreground tiles (mineable terrain — the main gameplay layer)
  Layer 3: Stations/machines (player-placed — workbench, furnace, etc.)
  Layer 4: Back wall tiles (mineable, fill tunnel walls — darker recessed variants)
  Layer 5: Natural background features (underground trees, large mining nodes — visible through wall gaps)
  Layer 6+: Distant parallax backgrounds (biome-specific scenes, flexible layer count per biome)
[Furthest from camera]
```

### Layer Details

**Layer 2 — Foreground Tiles:**
- The main terrain grid the player mines and places
- Full auto-tile bitmask system with material-specific edge variants
- Exposed edges show depth: top edges = lit floor face, bottom edges = shadowed ceiling face
- Same-type tile boundaries have organic, irregular edges (not straight lines) — dirt is crumbly, obsidian is jagged, ice is smooth with cracks
- Cross-type transitions blend with noise, no hard seams

**Layer 3 — Stations/Machines:**
- Player-placed objects that sit in the playable space
- Behind the player, in front of back walls
- Examples: workbench, furnace, anvil

**Layer 4 — Back Walls:**
- Mineable, 1:1 mapping with foreground tile types (every block type has a back wall variant)
- Visually: same material but darker (~30-40% darker), reduced contrast, slight shadow/depth
- Where back walls are missing (natural cavities, player-cleared), deeper layers show through

**Layer 5 — Natural Background Features:**
- Behind back walls, visible only in natural cavities/large caves
- Biome-specific interactive objects: underground trees (occasionally give fruit), large mining nodes (setup machines on), crystal formations
- Needs object/interaction system designed before art creation

**Layer 6+ — Distant Parallax Backgrounds:**
- Biome-specific atmospheric scenes visible through wall gaps
- Flexible layer count per biome (some need 1-2, others 3+)
- Examples: distant caverns, underground forests, active lava falls/volcanoes, frozen chasms
- Scrolls with parallax relative to camera for depth effect

## Tile System

### Auto-Tile Variants

Each tile type will use a bitmask auto-tile system in Godot. Each type needs multiple variants based on which edges are exposed to open space.

**Phase approach:**
- **Start (blob-style minimal):** ~15 variants per type — covers tops, bottoms, sides, basic corners. Handles 90% of visual cases.
- **Polish (full 3×3 bitmask):** 47 variants per type — every edge combination, seamless in all configurations.

Each tile type's edge character reflects its material:
- Dirt: organic, crumbly, loose particles, uneven surfaces
- Stone: chipped, slightly irregular, small cracks
- Obsidian: sharp angular breaks, clean geometric edges
- Ice: smooth curves, occasional crack lines
- Sandstone: weathered, rounded, grainy edges
- etc.

**WAIT: Do not draw auto-tile variant sheets yet.** The exact bitmask template layout needs to be defined in Godot first. Drawing variants into the wrong grid = redo work.

### What to Draw NOW for Tiles

Draw the **base interior texture** for each tile type — one 32×32 tile showing the core look of the material. This becomes the "full interior" variant (no exposed edges) in the final auto-tile sheet. It also establishes the visual identity and isn't wasted work.

### Current Tile Types (24)

Row 0: EMPTY*, DIRT, STONE, IRON_ORE, GOLD_ORE, DIAMOND_ORE, COPPER_ORE, COAL_ORE
Row 1: CRYSTAL, OBSIDIAN, SANDSTONE, CLAY_STONE, ICE, MOSSY_STONE, GRANITE, MARBLE
Row 2: MUSHROOM_BLOCK, LAVA_ROCK, GRASS_DIRT, SAND, SNOW, SWAMP_MUD, RED_SAND, CLAY

*EMPTY (index 0) is never rendered.

### Tile Art Tips

- Each tile should read clearly at 32×32 — distinct texture and color for each type
- Add subtle internal variation (noise, cracks, speckles) so tiled surfaces don't look flat
- Ores: base stone texture + colored ore veins/crystals embedded in it
- Think about how each material would naturally break/erode — this informs edge treatment later
- Keep edge pixels relatively neutral for now — the auto-tile variants will handle edge-specific detail

### Back Wall Tiles

1:1 with foreground types. Same material, darker and recessed.

**Art approach:** Take each foreground base texture, darken ~30-40%, reduce contrast, optionally add subtle shadow depth. Can batch-process once base textures are done.

**WAIT: Full back wall variant sheets depend on the auto-tile template, same as foreground.**

### File Structure (Final — Per Tile Type)

Once auto-tile templates are defined:
```
assets/tilesets/
├── dirt/
│   ├── dirt.aseprite            ← auto-tile variants in bitmask layout
│   ├── dirt.png                 ← exported variant sheet
│   ├── dirt_wall.aseprite       ← back wall variants
│   └── dirt_wall.png
├── stone/
│   ├── stone.aseprite
│   ├── stone.png
│   ├── stone_wall.aseprite
│   └── stone_wall.png
├── ... (per tile type)
```

For now (base textures only):
```
assets/tilesets/
├── base_textures/
│   ├── dirt.png                 ← single 32×32 base texture
│   ├── stone.png
│   ├── iron_ore.png
│   ├── ... (all 24 types)
```

## The Goblin (Player Character)

**Concept:** Classic/cute hybrid. A determined small goblin — "brave child lost in the woods." Pointy ears, expressive eyes, scrappy clothing. Should read clearly at 32×48.

**Canvas:** 32×48 pixels per frame. Don't fill the entire canvas — leave a few pixels of padding on each side so animations have room to extend (like a pickaxe swing).

**Facing:** Draw the goblin facing RIGHT. The engine flips horizontally for left-facing movement. Only draw one direction.

### Animation List (Priority Order)

Each animation is a separate Aseprite file. Frames go left to right on the timeline. Export as horizontal strip PNG.

| # | Animation | Frames | Loop? | Description |
|---|-----------|--------|-------|-------------|
| 1 | **Idle** | 4–6 | Yes | Standing still. Subtle breathing (chest rises 1px), occasional blink. Plays most of the time. |
| 2 | **Run** | 6–8 | Yes | Full run cycle. Arms and legs pumping. Head can bob 1px. Energetic but small. |
| 3 | **Mine (swing)** | 6–8 | No | Pickaxe swing: wind-up (2f) → swing (2f) → impact (2f). CORE action — make it punchy. |
| 4 | **Jump** | 2 | No | Rising pose: legs tucked, arms slightly up. Held frame while ascending. |
| 5 | **Fall** | 2 | No | Falling pose: legs dangling, arms out. Different from jump. Held while descending. |
| 6 | **Land** | 2–3 | No | Squash on landing: body compresses 1-2px, springs back. Quick, adds juice. |
| 7 | **Hurt** | 3 | No | Knockback/flinch. Eyes shut. Plays briefly on damage. |

**Total first pass: ~30 frames.**

### How Sprite Sheets Work

In Aseprite, export each animation as a horizontal strip:
`File → Export Sprite Sheet → Layout: Horizontal Strip (Rows: 1)`

Example: `run.png` with 8 frames at 32×48 = a 256×48 PNG.

```
[frame1][frame2][frame3][frame4][frame5][frame6][frame7][frame8]
  32×48   32×48   32×48   32×48   32×48   32×48   32×48   32×48
```

**Save `.aseprite` source files** — they preserve layers/timeline. Only exported `.png` sheets are used by the engine.

### Player File Structure

```
assets/sprites/player/
├── idle.aseprite / idle.png            ← 4-6 frames × 32×48
├── run.aseprite / run.png              ← 6-8 frames × 32×48
├── mine.aseprite / mine.png            ← 6-8 frames × 32×48
├── jump.aseprite / jump.png            ← 2 frames × 32×48
├── fall.aseprite / fall.png            ← 2 frames × 32×48
├── land.aseprite / land.png            ← 2-3 frames × 32×48
├── hurt.aseprite / hurt.png            ← 3 frames × 32×48
```

## Item Icons

**Size: 32×32, transparent background.**

Used in: inventory grid, hotbar, dropped items in world. Should be recognizable at a glance.

Individual PNG per item. Name matches ItemDatabase ID.

### Priority Items (Build Now)

```
assets/items/
├── dirt.png
├── stone.png
├── iron_ore.png
├── gold_ore.png
├── copper_ore.png
├── coal_ore.png
├── diamond_ore.png
├── torch.png
├── wood_pickaxe.png
├── stone_pickaxe.png
├── iron_pickaxe.png
├── bandage.png
├── rope.png
├── campfire.png
├── iron_bar.png
```

## Crafting Stations

**Sizes:**
- Workbench: 64×64 (2×2 tiles)
- Furnace: 64×64 (2×2 tiles)
- Anvil: 64×32 (2×1 tiles) or 64×64

These are Layer 3 objects (behind player, in front of back walls). Should look like functional objects. Animated variants (furnace fire) can come later.

```
assets/stations/
├── workbench.aseprite / workbench.png
├── furnace.aseprite / furnace.png
├── anvil.aseprite / anvil.png
```

## Parallax Backgrounds

**WAIT: Do not build yet.** Need engine system designed first (exact dimensions, scroll rates, layer count per biome).

**Vision for later:**
- Per-biome atmospheric scenes: distant caverns, underground forests, active lava falls, frozen chasms, crystal grottos
- Flexible layer count per biome (1-3+ layers)
- Scrolls with parallax for depth
- 8 underground biomes + 7 surface biomes = up to 15 unique background sets

## Natural Background Features

**WAIT: Do not build yet.** Need object/interaction system designed.

**Vision for later:**
- Biome-specific objects behind back walls: underground trees, large crystal formations, lava pools, mining nodes
- Some interactive (trees give fruit, nodes for machines)
- Visible only through natural cavities where back walls are missing

## UI Elements

**WAIT: Design during M4 Phase C (Game HUD + Inventory UI).**

General direction when we get there:
- 9-slice panels for resizable frames
- Consistent border width (2-3px)
- Dark, earthy aesthetic matching the game tone

## Aseprite Workflow Summary

1. **New file** → set canvas size (32×48 for goblin, 32×32 for tiles/items)
2. **Load palette** → Palette → Load Palette → select ENDESGA-64
3. **Set indexed mode** → Sprite → Color Mode → Indexed (locks to palette)
4. **Draw/animate** → timeline at bottom, one frame per column
5. **Onion skin** → toggle onion icon to see previous/next frames while drawing
6. **Export** → File → Export Sprite Sheet → Horizontal Strip, PNG

## What to Build NOW vs LATER

### BUILD NOW (no engine dependency)

| Priority | Asset | Details |
|----------|-------|---------|
| 1 | **Base tile textures** | One 32×32 per tile type (24 total). Core material look. Becomes the interior variant later. |
| 2 | **Goblin idle + run** | First two animations. Unblocks player visual overhaul. |
| 3 | **Goblin mine/swing** | Core gameplay animation. |
| 4 | **Item icons** (top 15) | Unblocks inventory UI work. |
| 5 | **Crafting stations** | Workbench, furnace, anvil. |
| 6 | **Remaining goblin animations** | Jump, fall, land, hurt. |

### WAIT (engine dependency)

| Asset | Blocked by |
|-------|-----------|
| Auto-tile variant sheets (foreground) | Bitmask template layout definition |
| Auto-tile variant sheets (back walls) | Same — bitmask template |
| Edge depth faces (floor/ceiling) | Part of auto-tile system |
| Organic edge treatments | Part of auto-tile system |
| Parallax backgrounds | Parallax system design (dimensions, scroll rates) |
| Natural background objects | Object/interaction system design |
| UI elements | HUD layout design (M4-C) |

---

*This document is the single source of truth for art asset creation. Updated as engine systems are designed and new templates become available.*
