# Art Asset Guidelines — This Goblin's World

## Core Specs

| Setting | Value |
|---------|-------|
| **Palette** | Duel by Arilyn (256 colors, Lospec) — can swap later, engine has no palette dependency |
| **Tool** | Aseprite (recommended) |
| **Viewport** | 960×540, `canvas_items` stretch, `expand` aspect |
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

**Duel** by Arilyn — 256 colors, download from Lospec and load into Aseprite.

In Aseprite: `Sprite → Color Mode → Indexed`, then load the palette via `Palette → Load Palette`. This locks you to only those 256 colors.

If the palette needs changing later, we can swap freely. The engine has no palette dependency — it's purely an art-side constraint for visual consistency.

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

**Facing:** Draw the goblin facing LEFT. The engine flips horizontally for right-facing movement. Only draw one direction.

### Layered Sprite System

The goblin is composed of **7 body layers**, each exported as its own sprite sheet. All layers share the same animation layout and are frame-synced at runtime.

| Layer | Z-Order | Equipment Slot | Notes |
|-------|---------|---------------|-------|
| Back arm | 0 | Arms (paired with front arm) | Behind body |
| Back leg | 1 | Legs (paired with front leg) | Behind body |
| Chest | 2 | Chest | Core torso |
| Belt | 3 | Belt | Over chest |
| Head | 4 | Head | Helmets, hoods |
| Front leg | 5 | Legs (paired with back leg) | In front of body |
| Front arm | 6 | Arms (paired with front arm) | In front of body |

**Equipment slots (6):** Head, Chest, Belt, Arms, Legs, Weapon

- Equipping an item swaps the texture on its layer(s)
- Arms equipment swaps both back arm + front arm sheets
- Legs equipment swaps both back leg + front leg sheets
- Multi-slot items (e.g., robes) can replace Chest + Belt + Legs simultaneously
- Unequipping restores the base goblin layer sheet

**Weapons** are a separate sprite (not part of the sheet system). Positioned by code relative to the goblin. Details TBD — start with simple items and see how they look.

### Sprite Sheet Format (Locked)

- One PNG per body layer, per character/equipment piece
- All animations and orientations baked into a single sheet
- Fixed **8 columns** (longest animation padded with blank frames)
- Fixed **16 rows** (reserved layout below — rows never move, columns never change)
- New animations fill reserved slots; if all 16 used, overflow goes to a second "extended animations" sheet
- Frame size: 32x48 pixels per cell (may change if 2x art pipeline is adopted — see foundation-redesign.md)
- Sheet dimensions: **256x768** (8 columns x 16 rows x 32x48 per cell)

### Row Assignments (Locked)

| Row | Tag | Frames | Orientation | Purpose |
|-----|-----|--------|-------------|---------|
| 0 | `idle` | 4 | side | Default idle |
| 1 | `idle_2` | 4 | side | Variant idle |
| 2 | `idle_3` | 4 | side | Variant idle |
| 3 | `idle_4` | 4 | side | Variant idle |
| 4 | `walk` | 6 | side | Standard walk |
| 5 | `run` | 6 | side | Sprint |
| 6 | `jump` | 4 | side | Launch + airborne |
| 7 | `fall` | 4 | side | Descent |
| 8 | `land` | 4 | side | Landing impact + recover |
| 9 | *reserved* | -- | side | Future side-facing |
| 10 | *reserved* | -- | side | Future side-facing |
| 11 | *reserved* | -- | side | Future side-facing |
| 12 | `walk_back` | 6 | back | Walking into passage/doorway |
| 13 | `climb_back` | 6 | back | Climbing into background |
| 14 | `walk_front` | 6 | front | Walking toward camera |
| 15 | *reserved* | -- | front/back | Future orientation variant |

### Row Assignment Rules

- Side-facing animations use `flip_h` for left/right — no mirrored art needed
- Back and front orientations are separate art, separate rows
- Shorter animations pad remaining columns with blank (transparent) frames
- Frame counts are defined in code (not auto-detected from blank frames)
- Equipment sheets use the EXACT same row/column layout — drop-in texture replacement per layer
- Row assignments are permanent. Adding new animations fills reserved rows. Nothing shifts.
- If 16 rows are exhausted, create a second sheet (extended animations) with its own row table

### Animation Data Dictionary (Code Reference)

The engine reads animations from this dictionary. Row numbers match the sprite sheet layout above.

```gdscript
const ANIMATIONS = {
    "idle":       { "row": 0, "frames": 4 },
    "idle_2":     { "row": 1, "frames": 4 },
    "idle_3":     { "row": 2, "frames": 4 },
    "idle_4":     { "row": 3, "frames": 4 },
    "walk":       { "row": 4, "frames": 6 },
    "run":        { "row": 5, "frames": 6 },
    "jump":       { "row": 6, "frames": 4 },
    "fall":       { "row": 7, "frames": 4 },
    "land":       { "row": 8, "frames": 4 },
    "walk_back":  { "row": 12, "frames": 6 },
    "climb_back": { "row": 13, "frames": 6 },
    "walk_front": { "row": 14, "frames": 6 },
}
```

### Aseprite Workflow

1. Animate the full goblin in one `.aseprite` file with all 7 body layers
2. Create animation tags matching the row order in the locked row assignments above
3. Export per-layer: target one layer, all tags, fixed 8 columns — PNG wraps into rows
4. Pad shorter animations to 8 frames with blank (transparent) cells
5. Result: one 256x768 PNG per layer with all animations baked in
6. Equipment pieces follow the same process — animate in a layered file, export the relevant layer(s)

### Player File Structure

**Base goblin (7 sheets, 256x768 each — 8 columns x 16 rows x 32x48 per cell):**
```
assets/characters/goblin/
  base/
    back_arm.png      # Z0 - all animations, all orientations
    back_leg.png      # Z1
    chest.png         # Z2
    belt.png          # Z3
    head.png          # Z4
    front_leg.png     # Z5
    front_arm.png     # Z6
```

**Equipment (per item, only layers it affects — same 8x16 layout):**
```
assets/characters/goblin/
  equipment/
    iron_helmet/
      head.png        # Same 8x16 layout, replaces base head layer
    leather_vest/
      chest.png       # Same layout, replaces base chest layer
    iron_greaves/
      front_leg.png   # Replaces both leg layers
      back_leg.png
    goblin_robe/
      chest.png       # Replaces chest + belt + legs
      belt.png
      front_leg.png
      back_leg.png
    leather_gloves/
      front_arm.png   # Replaces both arm layers
      back_arm.png
```

**Weapons (separate sprites, not sheet-based):**
```
assets/sprites/weapons/
├── wood_pickaxe.png             ← small sprite, positioned by code
├── iron_sword.png
├── ...
```

**Source files (not used by engine):**
```
art/Sprites/
├── animations/
│   ├── goblin_base_animations.aseprite    ← master layered file
│   ├── goblin_geared_animations.aseprite  ← equipment variants
│   └── ...
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

1. **New file** → set canvas size (32x48 for goblin, 32x32 for tiles/items)
2. **Load palette** → Palette → Load Palette → select Duel (by Arilyn)
3. **Set indexed mode** → Sprite → Color Mode → Indexed (locks to palette)
4. **Draw/animate** → timeline at bottom, one frame per column
5. **Onion skin** → toggle onion icon to see previous/next frames while drawing
6. **Tag animations** → create tags matching the locked row assignments (idle, idle_2, walk, run, etc.)
7. **Pad frames** → ensure every tag has exactly 8 frames (pad shorter ones with blank transparent frames)
8. **Export per-layer** → File → Export Sprite Sheet → fixed 8 columns, all tags, one layer visible → PNG

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
