# This Goblin's World - Implementation Plan

**Engine:** Godot 4.5.1 (GDScript)
**Solo dev + AI assisted**

Structured as milestones that each produce something playable. M1-M7 plus Phase 1/1.5 are complete. Early milestones (M8-M12) are detailed with Godot specifics. Mid milestones (M13-M16) have moderate detail. Later milestones (M17-M24) are broader because the right decisions depend on what we learn building the foundation.

---

## Architectural Principles (Apply From Day One)

These are not a milestone. They are constraints that apply from line one of code.

**Client-Server Mindset:**
Every game action flows through an authority. In single-player, the local game IS the server - but the code treats it that way:
- Game logic lives in "system" scripts, not in player or UI scripts
- State changes go through a `GameServer` autoload
- The player controller emits input events; it does not directly modify world state
- Rendering reads from authoritative state, never writes to it

**World Rendering Architecture:**
The world is finite and bounded, with selectable size presets (Small 2400x800, Medium 3600x1000, Large 4800x1200). Tile data is stored in WorldData (dictionaries of tile data). Two global TileMapLayers (foreground + back wall) render all tiles — no per-chunk nodes. All tiles are loaded at once during a loading screen with progress bar. World generation happens once at world creation via a background thread, then all visuals are populated in a single pass. Darkness overlays remain spatially managed around the player.

*(Updated: Previously used per-chunk TileMapLayers with dynamic load/unload based on player proximity. Refactored to 2 global TileMapLayers with full upfront tile population.)*

**Data vs. Presentation:**
World state (what tile is at position X,Y) is data in dictionaries (WorldData). Two global TileMapLayer nodes are presentation. This separation is what makes multiplayer, saving, and efficient rendering possible.

**Behavior Tracking System (Foundational):**
The game watches what the player does from the very first session. This system is not a milestone feature - it is infrastructure that goes in early and feeds everything later:
- Every meaningful player action is recorded: blocks mined (type, depth), enemies killed (type, weapon used), items crafted (type, station), damage taken (type, source), spells cast, distances traveled, resources gathered, tools used, stations built
- Tracked as cumulative counters and rolling windows (recent behavior matters for class offers, lifetime totals matter for thresholds)
- This data feeds: skill XP calculations (M5), class unlock evaluation (M16), dynamic difficulty awareness, and analytics
- The tracking system is a `BehaviorTracker` autoload that listens to signals from `GameServer` - it never modifies game state, only observes
- Storage is lightweight: dictionaries of counters, serialized with save data
- Even before skills or classes exist in-game, every action is being counted. When those systems come online, they read from a rich history of player behavior

---

## Milestone 1: Project Setup and Core Movement
**Status:** COMPLETE

**Goal:** A goblin moving and jumping in a small hardcoded room. Establish the project structure, input system, and movement feel.

### What Gets Built

**Project structure:**
```
project.godot
assets/
  sprites/
  tilesets/
scenes/
  main.tscn
  player/
    player.tscn        # CharacterBody2D
    player.gd          # Movement controller
  world/
    world.tscn
    chunk_renderer.gd  # (Updated: Originally a per-chunk TileMapLayer wrapper stub. Now obsolete — replaced by global TileMapLayers managed by chunk_manager.gd acting as a world renderer.)
scripts/
  autoloads/
    game_server.gd     # Authority for game state (stub)
    game_state.gd      # Shared state container
    input_manager.gd   # Input abstraction
    behavior_tracker.gd # Player action observer (stub - signals wired, counters empty)
  data/
    tile_data.gd       # Tile type definitions
resources/
  tilesets/
    main_tileset.tres
```

**Player scene (player.tscn):**
- `CharacterBody2D` (root)
  - `Sprite2D` (placeholder sprite)
  - `CollisionShape2D` (capsule, ~16x24 pixels)
  - `AnimationPlayer`
  - `Camera2D` (follows player, smoothing enabled)

**Movement controller (player.gd):**
- Horizontal movement with acceleration/deceleration (not instant - gives weight)
- Gravity and jump with variable jump height (hold to jump higher)
- Coyote time (brief window to jump after leaving a ledge)
- Jump buffer (press jump slightly before landing, still registers)
- Input goes through `InputManager` autoload, not raw `Input` calls

**BehaviorTracker autoload (stub):**
- Signal connections to `GameServer` wired but mostly empty
- `record_action(action_type: StringName, metadata: Dictionary)` method exists
- Storage structure defined: `Dictionary` of `StringName -> int` for counters
- Does nothing visible yet - just the skeleton

**Test room:**
- Small box of tiles using TileMapLayer with collision
- Hardcoded, not generated - just walls and floor

### What the Player Can Do
Run left/right, jump, and bounce around a small room. Movement should feel tight and responsive.

### Key Technical Decisions
- **CharacterBody2D** over RigidBody2D - full control over movement via `move_and_slide()`
- **InputManager autoload** wraps all input so later, input can come from network
- **16x16 tile size** - goblin sprite roughly 32x48 pixels, collision tighter
- **GameServer autoload** exists as a stub from day one
- **BehaviorTracker autoload** exists as a stub from day one - signals defined, counters skeleton in place
- **Camera2D** with position smoothing ~5-8

### Acceptance Test
Goblin moves fluidly with visible acceleration. Jumping feels snappy. Variable jump height works. Coyote time and jump buffer make platforming feel generous. No jitter on tile edges. BehaviorTracker autoload loads without errors.

---

## Milestone 2: Tilemap and Basic Mining
**Status:** COMPLETE

**Goal:** The player can destroy and place tiles. World is still small/hardcoded, but the tile interaction pipeline is real. BehaviorTracker starts recording mining actions.

### What Gets Built

**TileSet setup:**
- Physics layer (collision)
- Custom data layers: `tile_type` (int), `hardness` (float), `drop_item` (StringName)
- 3 tile types minimum: dirt, stone, ore (placeholder art)
- Terrain connections for auto-tiling

**Mining system:**
- Mouse aiming to target tiles, with visual highlight on targeted tile
- Mining is a held action with progress timer based on tile hardness
- Tile removal goes through authority: input -> GameServer.request_mine(position) -> validate -> update world data -> update renderer
- Dropped item entity spawns at tile position
- **GameServer emits `tile_mined(position, tile_type, tool_used)` signal** - BehaviorTracker listens and records

**Block placement:**
- Select tile type from basic hotbar (number keys)
- Same authority flow as mining
- GameServer emits `tile_placed(position, tile_type)` signal

**Dropped items:**
- `CharacterBody2D` with `Area2D` for pickup
- Bounce on spawn, auto-collect on player contact
- Items stored in inventory array (no UI yet, just data)
- GameServer emits `item_collected(item_type, amount)` signal

**World data layer (world_data.gd):**
- `Dictionary` keyed by `Vector2i` tile positions, stored in WorldData
- Functions: `get_tile(world_pos)`, `set_tile(world_pos, type)`, `remove_tile(world_pos)`
- Global TileMapLayers read from this data, never the other way around

*(Updated: Originally `chunk_data.gd` keyed by chunk coords. Now `world_data.gd` with global tile storage. TileMapLayer rendering uses 2 global layers instead of per-chunk nodes.)*

**BehaviorTracker (first real tracking):**
- Listens to `tile_mined`, `tile_placed`, `item_collected` signals
- Records: tiles mined by type, total blocks placed, items collected by type
- Data accessible via `BehaviorTracker.get_count(action_type)` and `BehaviorTracker.get_count_filtered(action_type, metadata_key, metadata_value)`

### What the Player Can Do
Dig through dirt and stone. Pick up dropped resources. Place blocks. Carve tunnels. Behind the scenes, every mining action is being tracked.

### Key Technical Decisions
- **Mouse aiming for mining target** - highlight the targeted tile
- **Authority flow for all tile changes** - even in single-player
- **TileSet custom data layers** for tile properties (Godot native feature)
- **World data as plain dictionaries** - fast to serialize for saving and networking *(Updated: originally "Chunk data")*
- **Mining progress visual** - overlay sprite with crack frames
- **Signal-based behavior tracking** - GameServer emits, BehaviorTracker listens, zero coupling

### Acceptance Test
Player can mine a tunnel, blocks drop items, items get picked up, blocks can be placed. Mining respects hardness. World data and visual tilemap stay in sync. `BehaviorTracker.get_count("tile_mined")` returns correct count after mining.

---

## Milestone 3: World Generation and Rendering
**Status:** COMPLETE

**Goal:** Procedurally generated world. All tiles rendered via global TileMapLayers. Game starts underground. BehaviorTracker records depth reached.

*(Updated: Originally designed as a dynamic chunk loading/unloading system with per-chunk TileMapLayers. Refactored to use 2 global TileMapLayers (foreground + back wall) with all tiles loaded at once during a loading screen. chunk_manager.gd now acts as a world renderer rather than a chunk lifecycle manager.)*

### What Gets Built

**World renderer (chunk_manager.gd):**
- Manages 2 global TileMapLayers (foreground + back wall) for all tile rendering
- All tiles populated at once during loading screen with progress bar
- World generation runs on a background thread, then visuals are applied in a single pass on the main thread
- Darkness overlays remain spatially managed around the player position
- Chunk size 32x32 tiles is still used as an organizational unit for darkness overlays and world generation, but there are no per-chunk TileMapLayer nodes

*(Historical: Originally tracked player position and managed a 5x5 active chunk radius. Each chunk was a separate TileMapLayer node that was created/freed as the player moved. Background thread generation used `call_deferred` to apply chunk data. This dynamic loading was replaced by upfront full-world population.)*

**World generator:**
- `FastNoiseLite` for base terrain noise
- Pipeline per chunk:
  1. Base density (simplex noise: solid vs air)
  2. Cave carving (second noise layer, cellular type for organic shapes)
  3. Ore placement (depth-based probability per ore type)
  4. Smoothing pass (clean up isolated tiles)
- Deterministic from world seed

**Depth zones:**
| Depth (tiles) | Zone | Characteristics |
|---|---|---|
| 0-80 | Shallow Caves | Open space, dirt/stone, basic ores, bioluminescent |
| 80-200 | Mid Caves | Tighter tunnels, harder stone, iron/copper, darker |
| 200-400 | Deep Caves | Dense rock, gold/crystal ores |
| 400+ | The Deep | Stub - solid exotic rock for now |

**Spawn chamber:**
- Chunk at origin uses a special template: small cave room, floor, dead miner's pickaxe, basic supplies
- Procedural with constraints: guaranteed floor, ceiling, item spawns

**World persistence:**
- Full world tile data saved to `world_cache.dat` and loaded directly on save load
- No per-chunk save files — entire world state persisted at once via SaveManager

*(Historical: Originally, modified chunks were saved individually to `user://worlds/<name>/chunks/<x>_<y>.dat` and unmodified chunks were regenerated from seed. Replaced by whole-world persistence via world_cache.dat.)*

**Lighting (basic):**
- Depth-based ambient darkness (CanvasModulate or shader)
- Placeable torches as `PointLight2D` with limited range

**BehaviorTracker additions:**
- Track `max_depth_reached` - updated whenever player moves deeper than previous record
- Track movement distance (cumulative)
- Track ore types encountered (first discovery of each type)

### World Loading Lifecycle
```
New world:
  -> World generation runs on background thread (all tiles at once)
  -> Loading screen displays progress bar
  -> All tiles populated into 2 global TileMapLayers (foreground + back wall)
  -> Full light computation runs
  -> World is ready

Loading saved world:
  -> world_cache.dat loaded directly into WorldData
  -> All tiles populated into 2 global TileMapLayers
  -> Light maps restored
  -> World is ready
```

*(Historical: The original chunk lifecycle diagram below is obsolete but preserved for reference:)*
```
[OBSOLETE] Original per-chunk lifecycle:
Player moves near unloaded chunk
  -> Saved file exists? Load from disk : Generate from seed (background thread)
  -> Create TileMapLayer, apply tile data (main thread)
  -> Chunk is active

Player moves away from chunk
  -> Dirty (modified)? Save to disk
  -> Remove TileMapLayer from scene tree
  -> Free from memory
```

### What the Player Can Do
Start in spawn cave. Mine outward into procedural cave systems. Go deeper to find different materials. Place torches. World feels vast. Performance stays solid.

### Key Technical Decisions
- **Chunk size 32x32** - used as an organizational unit for world generation and darkness overlays
- **2 global TileMapLayers** - one for foreground tiles, one for back walls. No per-chunk nodes. *(Updated: originally one TileMapLayer per chunk for natural physics boundaries)*
- **FastNoiseLite over cellular automata** - deterministic per-coordinate, tiles generate independently
- **Background thread for world generation** - world gen runs on a thread, then all visuals populated at once during loading screen
- **Full world persistence via world_cache.dat** - entire world saved/loaded at once *(Updated: originally used dirty chunk tracking where only modified chunks were saved)*
- **Y-axis goes down** - deeper = higher Y values in Godot 2D
- **BehaviorTracker serialized with save data** - world persistence and behavior data save/load together

### Acceptance Test
World generates seamlessly in any direction. No pop-in, no frame drops. Modified terrain persists after leaving/returning. Depth zones are visually distinct. Spawn chamber always generates correctly. `BehaviorTracker.get_stat("max_depth_reached")` updates correctly as player descends.

---

## Milestone 4: Inventory, Menus, Animation, Tiles, and Save System
**Status:** COMPLETE (all sub-phases)

**Goal:** Item database, inventory data layer, full menu infrastructure, player animation, tile edge system, and enhanced saves. Originally scoped as a single milestone, broken into sub-phases during development.

### Sub-phases

#### 4A: Item Database + Inventory Data Layer — COMPLETE
- **Item database (autoload):** Static registry loaded from data files. Items have: id, name, icon, max_stack, type (material/tool/weapon/placeable/consumable), metadata. Tools add: tool_quality (enum: Crude/Standard/Fine/Masterwork/Legendary/Ancient), mining_power, crafting_bonus
- **Inventory system:** Fixed slots (30 + 10 hotbar), item stacking, split/swap. State lives on GameServer, UI reads from it

#### 4B: Menus + Save Slots — COMPLETE
- **Title screen:** New Game / Load Game / Settings / Quit
- **Pause menu (Escape):** Resume / Settings / Save & Quit / Quit to Title
- **Settings menu:** Audio (master/sfx/music volume), Video (fullscreen, resolution), Controls (keybinding display, remapping)
- **Save slot system:** Multiple worlds instead of hardcoded `user://worlds/default/`. SaveManager parameterized by world slot. World metadata: name, playtime, last played date

#### 4.5: Player Animation & Sprite Integration — COMPLETE
- Replaced placeholder sprite with authored goblin sprite sheet
- Wired all core gameplay animations via AnimationPlayer (idle, walk, run, jump, fall)
- Direct frame control animation system
- Sprite sheet conventions: 32x48px frames, flip_h for direction

#### 4.6: Tile Edge & Overlay System — COMPLETE (then STRIPPED in Phase 1)
- Edge and ore overlay rendering as additional TileMapLayers per chunk
- Base + overlay approach replacing bitmask system
- **Note:** This entire system was stripped during the Phase 1 world generation rebuild. The 16px tile migration and colored-rectangle rendering approach replaced it. The infrastructure work here informed the layer architecture but the art pipeline was abandoned in favor of biome color palettes.

#### 4.7: Enhanced Save System — COMPLETE
- Refactored save structure to support multiple snapshots per world
- Autosave (timer-based + event-triggered)
- Save browser UI for loading past save points
- "Saving..." overlay with minimum display time
- SaveManager as RefCounted (not Node) — uses polling pattern instead of call_deferred
- Directory structure: `user://worlds/<slot_name>/` with `world.dat`, `behavior.dat`, `current/`, `saves/`
- Save version 5, rejects < v5

### Key Technical Decisions
- Item database as data files — easy to add items without code changes
- Inventory on authority side — UI sends requests, reacts to confirmed changes
- Quality field on every item from day one — data structure ready for crafting quality system
- Menus use CanvasLayer with Control nodes — independent of game world rendering
- Save slots parameterize SaveManager — minimal refactor of existing persistence

### Acceptance Tests
1. **Inventory:** Pick up items, stack, split, swap, drop. Edge cases (full inventory, max stack) handled
2. **Menus:** Title screen -> New Game starts fresh world. Escape pauses. Settings persist. Save & Quit -> Load Game restores state
3. **Save slots:** Create multiple worlds, load each independently, delete a save
4. **Animation:** Player sprite animates correctly for all movement states
5. **Saves:** Multiple snapshots per world, autosave works, save browser loads correct state

---

## Milestone 5: Skill System and Behavior Tracking
**Status:** COMPLETE (commit `96b31b7`)

**Goal:** Learn-by-doing skill system goes live. Skills level through use, soft-capped by environment difficulty. The BehaviorTracker data accumulated since M2 feeds into XP calculations.

### What Gets Built

**Skill system (autoload: `SkillSystem`):**
- Skills as data: `Dictionary` of skill_id -> { level: int, xp: float, xp_to_next: float }
- Initial skill list:
  - **Mining** - leveled by mining tiles
  - **Smithing** - leveled by crafting at anvil/forge
  - **Construction** - leveled by placing blocks and building
  - **Survival** - leveled by crafting consumables, healing, cooking
  - **Melee** - stub, leveled by combat (M12 activates it)
  - **Defense** - stub, leveled by taking/blocking damage (M12 activates it)
- Each skill has a level curve (exponential XP requirements)

**XP from appropriate challenge (the soft cap):**
- Every XP source has a `difficulty_level` (ore hardness tier, enemy combat rating, recipe complexity)
- XP formula: `base_xp * challenge_multiplier(skill_level, difficulty_level)`
- Challenge multiplier curve:
  - difficulty far below skill: ~0.01x (essentially zero - you've outgrown it)
  - difficulty slightly below skill: ~0.3x (diminishing returns)
  - difficulty matching skill: 1.0x (sweet spot)
  - difficulty above skill: 1.5x (pushing your limits, rewarded)
  - difficulty far above skill: 1.5x cap (can't cheese it by attempting impossible tasks)
- Ore/tile difficulty values defined in tile_data. Enemy difficulty defined in enemy_data (for M12).

**Skill effects (immediate, scaling):**
- **Mining:** speed bonus (% faster per level), chance for bonus ore drop, reduced tool durability loss
- **Smithing:** tracks XP, no quality influence yet (prepares for M15)
- **Construction:** faster block placement, sturdier structures (HP bonus)
- **Survival:** more effective consumables, better healing
- Skills provide gradual passive improvement - nothing is gated behind "need level X"

**Material efficiency (tied to crafting skills):**
- Recipe cost modified by skill level:
  - Skill far below recipe difficulty: costs 140% materials (waste)
  - Skill at recipe level: costs 100% (standard)
  - Skill well above recipe level: costs ~70% (efficient), occasional scrap return
- Displayed in crafting UI: "Iron Pickaxe: 5 iron bars (your skill: 4 needed)" with color coding

**Milestone perks (bonus rewards at skill thresholds):**
- Defined as data: skill_id + level_threshold -> perk_id
- Example: Mining 25 -> "Ore Sense" (nearby ores glow faintly), Mining 50 -> "Double Strike" (chance to mine 2 tiles at once)
- Perks are awarded automatically when threshold is reached
- Perks are nice-to-have bonuses, never required for progression
- Small notification: "Your mining skill has reached 25. You've developed Ore Sense."

**BehaviorTracker integration:**
- `BehaviorTracker` now feeds `SkillSystem` via signals
- When `tile_mined` fires, `SkillSystem` calculates Mining XP based on tile difficulty vs current Mining level
- When `item_crafted` fires at a station, `SkillSystem` calculates Smithing/relevant skill XP
- BehaviorTracker continues accumulating all counters - class system (M16) will read lifetime totals

**Skill UI:**
- Simple skill panel accessible from inventory screen
- Shows: skill name, current level, XP bar to next level, list of earned perks
- No skill point allocation - this is purely informational ("here's what you've become")

**Save/load:**
- Skill data serialized per character (player-owned, travels between worlds)
- BehaviorTracker data serialized with save file

### What the Player Can Do
Mine and watch Mining skill level up. Notice mining gets faster as skill increases. See that mining easy ores gives almost no XP while harder ores give more. Craft and watch Smithing skill rise. Hit skill milestones and receive perk bonuses. Open the skill panel to see progress. Notice material costs go down as crafting skill improves.

### Key Technical Decisions
- **Skills as pure data** - no nodes, no scenes, just dictionaries. Fast to query, easy to serialize
- **Challenge-based XP** - the core design principle. Environment difficulty IS the progression gate
- **BehaviorTracker stays separate from SkillSystem** - BehaviorTracker records everything (for classes later), SkillSystem only cares about XP-relevant actions
- **No retroactive XP** - skills level from actions taken after the system exists
- **Material efficiency as a multiplier on recipe cost** - simple math, big impact on feel
- **Perks as data entries, not code** - easy to add new perks without touching skill system code

### Acceptance Test
Mining stone gives Mining XP. Mining dirt at Mining level 20+ gives almost no XP. Mining iron at Mining level 20 gives good XP. Mining speed visibly improves with Mining level. Material costs decrease with skill. Skill panel shows accurate data. Milestone perks trigger at correct thresholds. All data persists through save/load.

---

## Phase 1: World Generation Rebuild
**Status:** COMPLETE (commit `da7fe02`)

**Goal:** Rebuild the world system from the ground up — 16px tiles, finite bounded worlds, back walls, fog of war, and a new spawn chamber. This was a major architecture change that replaced the old infinite chunk streaming with finite worlds that fit entirely in memory.

### What Gets Built

- **16px tiles** (rebuilt from 32px): All tile rendering and collision updated. 32x32 tile chunks remain as an organizational unit for darkness overlays, but tiles are rendered via 2 global TileMapLayers rather than per-chunk nodes
- **Finite bounded worlds** with selectable size presets:
  - Small: 2400x800 tiles
  - Medium: 3600x1000 tiles
  - Large: 4800x1200 tiles
  - World size chosen at new game creation
- **Back wall system:** Separate tile layer (Z=-10) with darker modulate. Back walls are mineable independently of front tiles
- **BFS fog of war:** Flood-fill exploration through empty space. Surface daylight expansion reveals tiles near the surface. Fog persists via SaveManager. World-owned (any player reveals for all)
- **Spawn chamber:** 24x14 tiles at world center. Guaranteed safe starting area
- **Colored rectangle rendering:** Biome color palettes drive tile appearance instead of sprite-based tiles. The M4.6 edge/overlay system was stripped entirely
- **Full upfront tile loading:** All tiles loaded at once during a loading screen with progress bar. 2 global TileMapLayers (foreground + back wall) — no per-chunk nodes or dynamic loading

### Key Technical Decisions
- **Finite over infinite** — bounded worlds enable full-world operations (fog of war, lighting) without streaming complexity
- **All data in memory** — eliminates per-chunk save/load during gameplay; world_cache.dat handles full-world persistence. 2 global TileMapLayers render all tiles upfront
- **16px tiles** — doubles visual detail density at same viewport size, better for the art style
- **Fog of war as world-owned** — globally shared exploration state, not per-player
- **Strip edge/overlay system** — colored rectangles are fast and sufficient until proper tile art is ready

### Acceptance Test
World generates correctly at all three size presets. Back walls render behind front tiles. Fog of war reveals correctly via BFS flood-fill. Spawn chamber generates reliably. Performance is solid with all tile data in memory.

---

## Phase 1.5: BFS Light System
**Status:** COMPLETE (commit `8851c2d`)

**Goal:** Discrete lighting system using BFS flood-fill. Sunlight, torches, and player-driven recomputation. World cache for full tile persistence.

### What Gets Built

- **Discrete light levels 0-40:** MAX_LIGHT=40, SUN_LIGHT=40, TORCH_LIGHT=28, AIR_REDUCTION=2, SOLID_REDUCTION=8, PLAYER_SOLID_REDUCTION=14
- **Sunlight propagation:** Propagates downward through air WITHOUT reduction (stays 40). Horizontal and through-wall propagation reduces normally
- **Two light maps:**
  - `static_light_map` — sun + torches, computed once at init
  - `player_light_map` — recomputed on tile change (mining, placing, torches)
- **Localized recompute:** `_recompute_light_local(center)` — 45x45 area (~2000 tiles), seeds from sun/torches/boundary. Used for all gameplay light changes
- **Full recompute:** `_recompute_static_light()` — entire world, init only
- **World cache:** Full tile data saved to `world_cache.dat`, loaded directly on save load (no regeneration needed)
- **Darkness overlay:** 34x34 images with `region_rect(1,1,32,32)` for seamless chunk boundaries. NOT position offset — region_rect approach is correct
- **Physics cap:** `Engine.max_physics_steps_per_frame = 4` prevents snap-to-floor during light recompute

### Key Technical Decisions
- **BFS over shader-based lighting** — discrete levels are simple, predictable, and cheap to compute locally
- **Two separate light maps** — static map avoids full recompute on every player action
- **Localized recompute** — ~2000 tiles is fast enough for real-time gameplay; full recompute only at world load
- **34x34 images with region_rect** — solves chunk boundary seam artifacts without position hacks

### Acceptance Test
Sunlight illuminates surface correctly. Torches cast light with falloff. Mining into a dark area triggers localized light recompute instantly. No visible seams at chunk boundaries. World cache loads correctly, skipping regeneration.

---

## Milestone 6: HUD & Display System
**Status:** COMPLETE (commit `0920aa5`)

**Goal:** Gameplay HUD with hotbar, vitals, minimap, and status effects. Display settings supporting multiple window modes and resolutions. GameServer player stat signals.

### What Gets Built

- **HUD components** (all under `gameplay_hud.gd` CanvasLayer):
  - `hotbar_display.gd` — 10 slots, centered bottom, `focus_mode = FOCUS_NONE` (Tab freed for inventory)
  - `vitals_display.gd` — health/mana/stamina bars, bottom-left anchored
  - `minimap_display.gd` — top-right anchored
  - `status_effects_display.gd` — top-left anchored
- **Dynamic viewport positioning:** All HUD components have `reposition()` methods, triggered by viewport `size_changed` signal
- **Display settings:**
  - Stretch mode: `canvas_items` (crisp text at native resolution, pixel art stays retro)
  - Stretch aspect: `expand` (ultrawide monitors see more world, no black bars)
  - Window modes: Windowed / Borderless Windowed / Fullscreen (default: Borderless)
  - Mode transitions: Always reset to WINDOWED first, then apply target mode (Windows quirk)
  - Resolution picker: Only visible in Windowed mode, built dynamically from monitor size
- **GameServer player stat signals:** `health_changed`, `mana_changed`, `stamina_changed` with stat setters and clamping
- **InputManager:** Hotbar scroll via mouse wheel in `_unhandled_input`

### Key Technical Decisions
- **canvas_items + expand** — best combo for pixel art game that needs crisp UI text and ultrawide support
- **Borderless fullscreen as default** — seamless alt-tabbing on Windows
- **Reset to WINDOWED before mode change** — Windows quirk requires this for reliable transitions
- **FOCUS_NONE on hotbar slots** — prevents Godot's `ui_focus_next` (Tab) from cycling through hotbar

### Acceptance Test
HUD displays correctly at all supported resolutions and window modes. Hotbar selection works via number keys and mouse wheel. Vitals bars update in real-time from GameServer signals. Window mode changes work reliably including borderless fullscreen. Resolution picker only appears in windowed mode.

---

## Milestone 7: Inventory UI & Equipment System

**Goal:** Visual inventory grid with full interaction and an equipment system that affects player stats. Builds on M4A's inventory data layer to add the UI and equipment mechanics.

### What Gets Built

- **Inventory grid UI:** 30-slot main inventory + 10-slot hotbar, opened with Tab
  - Drag/drop items between slots
  - Split stacks (right-click drag or shift-click)
  - Swap items between slots
  - Right-click context menu (equip, drop, use)
  - Stack merging on drop
- **Equipment slots:** 6 slots — head, chest, legs, feet, weapon, offhand/shield
  - Equipment panel alongside inventory grid
  - Drag from inventory to equip, drag off to unequip
  - Slot type validation (can't put helmet in chest slot)
- **Tooltip system:** Hover over any item to see:
  - Item name (color-coded by quality)
  - Item type and quality tier
  - Stat bonuses (damage, defense, mining power, etc.)
  - Description text
- **Equipment stat effects:**
  - Equipped items modify player stats via GameServer
  - Stats recalculated on equip/unequip
  - Defense from armor, damage from weapons, tool bonuses from held items
- **Persistence:** Equipment state saved/loaded alongside inventory data

### Key Technical Decisions
- **UI sends requests to GameServer** — inventory operations are validated server-side before visual update
- **Equipment stats as additive modifiers** — base stats + sum of equipment bonuses, easy to recalculate
- **Tooltip as a single reusable Control node** — positioned at mouse, content rebuilt on hover change
- **Tab toggles inventory** — consistent with M6's FOCUS_NONE approach, no focus conflicts

### Acceptance Test
Player can open inventory, drag items between slots, split and merge stacks. Equipment slots accept only valid item types. Equipping armor visibly changes defense stat. Tooltips display correct information for all item types. All inventory and equipment state persists through save/load.

---

## Milestone 8: Containers

**Goal:** Storage chests that players can craft, place in the world, and use to store items. Container contents persist with world save data.

### What Gets Built

- **Storage chest:** Craftable from wood/stone, placeable as a world object
  - Interaction: walk up and press interact key to open
  - Container has its own inventory grid (size varies by chest tier)
- **Container UI:** Opens alongside player inventory
  - Shift-click to quick-transfer items between inventories
  - Drag/drop between container and player inventory
  - Close on walk-away or press interact/escape
- **Item transfer validation:** GameServer validates all transfers (no duplication exploits)
- **Container persistence:**
  - Container contents stored in world save data (world-owned, not player-owned)
  - Containers tied to world position — persist in WorldData alongside tile data
  - Container metadata in world_data alongside tile data
- **Multiple container types (stretch):** Small chest, large chest, locked chest

### Key Technical Decisions
- **Containers as world-owned data** — stored alongside tile data in world_cache.dat, not in player save
- **Same inventory slot system as player** — reuse M7's grid UI with different backing data
- **Interaction range check** — GameServer validates player proximity before allowing container access
- **Container ID system** — each container gets a unique ID tied to its world position

### Acceptance Test
Player can craft a chest, place it, open it, transfer items in and out. Container contents persist after closing. Contents survive save/load cycle. Multiple chests work independently. Walking away closes the UI. No item duplication possible.

---

## Milestone 9: Water System

**Goal:** Liquid simulation that adds environmental variety and traversal challenges. Water flows, fills cavities, and affects player movement.

### What Gets Built

- **Liquid simulation:**
  - Water as a separate data layer (like back walls) with fill levels per tile
  - Flow mechanics: water spreads horizontally and falls with gravity
  - Source blocks that generate water (underground springs, surface lakes)
  - Cellular automaton update — processed in regions on a tick timer, not per frame
- **Water rendering:**
  - Semi-transparent blue overlay on tiles containing water
  - Fill level affects visual height within a tile
  - Surface animation (subtle wave effect)
  - Water tint gets darker at depth
- **Player interaction:**
  - Swimming movement (reduced speed, different controls)
  - Breath meter — limited underwater time before taking damage
  - Water slows falling (no fall damage into deep water)
  - Mining underwater is slower
- **World generation integration:**
  - Underground water pockets generated during world creation
  - Surface water bodies (lakes, rivers) in appropriate biomes
  - Water can flood player-mined tunnels if they breach a water pocket

### Key Technical Decisions
- **Fill levels per tile (0-8)** — allows partial fills and realistic flow, not just binary wet/dry
- **Tick-based simulation** — water updates on a timer (e.g., 10 ticks/sec), not every physics frame
- **Separate data layer** — water data stored alongside tile data in world_cache.dat
- **Seamless flow** — water simulation operates on the global WorldData, no boundary concerns *(Updated: originally needed cross-chunk boundary checks when using per-chunk TileMapLayers)*

### Acceptance Test
Water flows downward and spreads horizontally realistically. Breaking into a water pocket floods the tunnel. Player can swim with reduced speed. Breath meter depletes underwater. Water persists through save/load. No performance issues with large water bodies.

---

## Milestone 10: Map Transitions & Doorways

**Goal:** Allow the player to move between separate map instances — enabling dungeons, portal realms, and instanced areas that exist outside the main world.

### What Gets Built

- **Transition system:**
  - Door/portal objects placeable in the world
  - Interaction triggers map transition (fade to black, load target, fade in)
  - Bidirectional — player can return to previous map
- **Map instances:**
  - Each map is a separate world_data with its own tile data, lighting, fog
  - Maps loaded/unloaded independently (only one active at a time for now)
  - Map definitions: size, generation rules, entry/exit points
- **Portal/door types:**
  - Doors: connect two points within the same world or between worlds
  - Portals: crafted or discovered, link to special realms (foundation for The Abyss and other realms)
  - Dungeon entrances: generated in the world, lead to hand-designed or procedural sub-maps
- **Player state preservation:**
  - Inventory, equipment, skills, health/mana/stamina carry across transitions
  - Player position saved per-map (return to where you left)
  - Characters travel between worlds (Terraria model)
- **Save integration:**
  - Each map instance saved independently under the world's save directory
  - Transition metadata (which map links to which) stored in world save

### Key Technical Decisions
- **One active map at a time** — simplifies memory and rendering; multiplayer can revisit this later
- **Maps as independent world_data instances** — reuses all existing tile/light/rendering infrastructure
- **Transition as scene swap** — current world scene freed, new one instantiated, player transferred
- **Map registry** — central registry of map IDs, types, and entry points stored in world save

### Acceptance Test
Player can enter a door/portal and arrive in a separate map instance. Returning brings them back to the correct position. Player stats and inventory persist across transitions. Both maps save independently. Dungeon entrances generate in the world and lead to functional sub-maps.

---

## Milestone 11: Items & Base Crafting

**Goal:** Expanded item roster and a crafting system with hand-crafting and station-based crafting. The foundation for all future crafting content.

### What Gets Built

- **Expanded item roster:**
  - Full set of ores, bars, and materials for current biomes
  - Consumables: bandages, food items, potions (basic)
  - Placeable items: furniture, lighting, decoration
  - Tools: pickaxes, axes, hammers per material tier
- **Hand-crafting system:**
  - Available anywhere, no station needed
  - Limited to survival basics: torches, crude bandages, campfires, rope, crude stone tools
  - Always produces Crude quality
  - Recipe list accessible from inventory UI
- **Station-based crafting:**
  - Stations are interactive world objects — walk up, press interact, filtered recipe UI opens
  - Always produces Standard quality (quality variation deferred to M15)
  - Station types: Workbench (basic items, furniture), Furnace (smelting ores to bars), Anvil (weapons, armor, tools)
  - Station progression chain: Workbench -> Furnace (needs workbench) -> Anvil (needs smelted iron)
- **Recipe database:**
  - Data-driven recipe definitions (ingredients, station requirement, output, difficulty)
  - Authority validates ingredients before crafting
  - Recipe discovery: all recipes visible but locked ones show requirements
- **Crafting UI:**
  - Recipe list filtered by available station and known recipes
  - Material requirements shown with have/need counts
  - Craft button with progress bar for multi-step recipes
- **BehaviorTracker additions:** items_crafted (by type and station), stations_built, stations_used

### Key Technical Decisions
- **Recipes as data files** — easy to add content without code changes
- **Hand-craft = Crude, station = Standard** — immediately communicates that stations matter
- **Station progression chain** — natural tutorial flow, each station unlocks the next
- **Recipe database autoload** — centralized, queryable, feeds both UI and validation

### Acceptance Test
Player can hand-craft torches and basic tools anywhere. Building a workbench unlocks new recipes. Furnace smelts ore into bars. Anvil crafts metal tools and weapons. Recipe UI shows correct material requirements. Crafted items appear in inventory. All crafting data persists through save/load.

---

## Milestone 12: Combat Foundation

**Goal:** Melee combat with dodging, hitbox/hurtbox system, one test enemy. Combat skills start leveling through use via the skill system from M5.

### What Gets Built

**Health/damage system:**
- HP on both player and enemies, managed by GameServer
- Damage types: physical, fire, poison (extensible enum)
- Invincibility frames after taking damage (configurable duration)
- GameServer emits `damage_dealt(source, target, amount, type, weapon)` and `entity_killed(source, target, weapon)` signals

**Melee weapons:**
- Attack arc/hitbox activated during attack animation frames
- Weapon stats: damage, speed, knockback, reach
- Two weapons minimum: sword (fast, narrow arc) and hammer (slow, wide arc, bonus to armored)
- Weapons have quality field (all Standard for now, quality variation in M15)

**Dodge roll:**
- Quick dash with i-frames, cooldown-based
- Direction based on input, short distance
- Stamina cost (introduce stamina bar alongside health)

**Hitbox/hurtbox pattern:**
- Separate `Area2D` nodes on both player and enemies
- Hitboxes activate only during attack animation frames via `AnimationPlayer`
- Hurtboxes are always active
- Layer/mask setup: player hitbox -> enemy hurtbox, enemy hitbox -> player hurtbox

**Knockback:**
- Velocity impulse on hit, direction based on relative positions
- Both player and enemies affected
- Knockback resistance as a stat (for tanky enemies later)

**One test enemy (Cave Bat):**
- Simple state machine: Idle -> Patrol -> Chase -> Attack -> Hurt -> Die
- Flies, swoops at player when in aggro range
- Has difficulty_level for XP calculation
- Drops basic loot on death

**Death/respawn:**
- Player death returns to last outpost or spawn point
- Drop some resources on death (recoverable)
- Short invincibility on respawn

**Combat skills go live:**
- **Melee** skill: leveled by dealing melee damage. XP scales with enemy difficulty vs skill level. Effects: damage bonus, attack speed bonus, slight reach increase
- **Defense** skill: leveled by taking damage and blocking. Effects: damage reduction, i-frame duration increase
- All combat feeds into BehaviorTracker: enemies killed by type, damage dealt by weapon type, damage taken by source, dodges performed, deaths

**BehaviorTracker additions:**
- `damage_dealt` (by weapon type, by damage type)
- `damage_taken` (by source type, by damage type)
- `enemies_killed` (by enemy type, by weapon used)
- `dodges_performed`
- `deaths`
- `healing_used` (by item type)
- These counters are critical: they directly feed class unlock evaluation in M16. A player who fights with swords accumulates sword kills. A player who takes tons of damage accumulates damage-taken counters. The class system reads all of this.

### What the Player Can Do
Equip sword or hammer, attack cave bats, dodge through swoops, kill for loot, die and respawn. Watch Melee and Defense skills level up through combat. Notice that fighting tougher enemies gives more combat XP. Combat feels snappy and skill-based.

### Key Technical Decisions
- **Hitbox/hurtbox with Area2D** - precise, frame-based collision
- **Animation-driven combat** - AnimationPlayer keyframes control hitbox timing
- **State machine** for player and enemies (simple script pattern, no framework)
- **Damage through GameServer** - `deal_damage(source, target, amount, type)` -> signals -> BehaviorTracker + SkillSystem both listen
- **Stamina system** introduced here - shared resource for dodge and later heavy attacks
- **Enemy difficulty_level** as data - directly plugs into skill XP formula from M5
- **Every combat action tracked** - this is non-negotiable. Class unlocks depend on rich combat history

### Acceptance Test
Player can equip weapons, attack the cave bat, dodge its swoop, kill it for loot. Death respawns correctly. Melee skill gains XP from kills scaled by enemy difficulty. Defense skill gains XP from damage taken. BehaviorTracker shows accurate combat statistics. Hit registration is frame-precise with no phantom hits.

---

## Milestone 13: Enemy AI and Encounters

**Goal:** Multiple enemy types populating the cave system with natural spawning. Depth-based difficulty scaling. Combat becomes a real part of the exploration loop.

### What Gets Built

**Spawning system:**
- Region-based spawn evaluation: spawn budget based on depth zone around the player
- Max enemies per region, minimum distance from player for spawning
- Spawn tables per depth zone (weighted random from enemy pool)
- Enemies despawn when far enough from the player

*(Updated: Originally described as chunk-based spawning where enemies despawned on chunk unload. Since chunks are no longer dynamically loaded/unloaded, spawning uses proximity-based regions instead.)*

**3-5 enemy types, each with unique behavior:**
- **Cave Bat** (from M12, refined): Flies, swoops, low HP, fast - shallow caves
- **Slime:** Hops toward player, splits into smaller slimes on death - shallow/mid caves
- **Skeleton Miner:** Walks patrol routes, swings pickaxe, can block - mid caves
- **Cave Spider:** Climbs walls and ceilings, shoots webs (slow effect), ambush predator - mid/deep caves
- **Deep Worm:** Burrows through tiles (destructive), emerges to attack, high HP - deep caves

**Improved AI patterns:**
- Patrol routes (wander within area)
- Aggro ranges (detection radius, line-of-sight via raycasts)
- De-aggro (return to patrol after losing player)
- Telegraphed attacks (wind-up animations the player can read)
- Each enemy has a `difficulty_level` that scales with depth variant

**Loot tables:**
- Weighted drops per enemy type
- Depth-scaled loot quality (deeper variants drop rarer materials)

**Depth scaling:**
- Same enemy type has depth variants: Cave Bat (shallow) vs Shadow Bat (deep) with scaled stats
- Deeper enemies = more HP, more damage, better drops, higher difficulty_level (more XP)

**BehaviorTracker notes:**
- All enemy types tracked separately in kill counters
- Weapon used for each kill tracked (feeds into class detection: "uses swords a lot" vs "uses hammers a lot")
- Damage taken by enemy type tracked (feeds into "takes lots of damage" for tank classes)

### What the Player Can Do
Encounter diverse enemies while exploring. Learn attack patterns. Fight through dangerous areas for valuable loot. Notice deeper enemies are tougher but more rewarding (both loot and skill XP). Develop combat preferences that the game is quietly recording.

### Key Technical Decisions
- **State machine per enemy type** - shared base class with overrides
- **Region-based spawning** - natural population control, tied to player proximity *(Updated: originally chunk-based, tied to world streaming)*
- **Difficulty_level per depth variant** - plugs directly into skill XP soft cap
- **Loot tables as data** - JSON/Resource files, easy to tune

### Acceptance Test
Caves feel alive with enemies. Each type behaves distinctly. Depth scaling is noticeable. Loot drops reward deeper exploration. No performance issues with multiple active enemies. Kill counters in BehaviorTracker are accurate per enemy type and weapon.

---

## Milestone 14: Building and Defenses

**Goal:** Proper base building with furniture, functional defenses. Opt-in escalation system. Construction skill matters.

> **Note:** The back wall system was built in Phase 1. This milestone adds wall tile content variety, room enclosure detection, and wall-dependent gameplay.

### What Gets Built

**Background wall variety:**
- Wall types with visual variety (stone, wood, crystal)
- Walls define "enclosed rooms" (required for some furniture/station functionality)

**Furniture and stations as scenes:**
- Expanded station list: workbench, furnace, anvil, storage chest, door, bed (respawn point)
- Each station has interaction logic and state
- Lighting: torches, lanterns with varying range and color

**Building mode UI:**
- Ghost preview of placement, grid snap, placement validation
- Material cost shown before placement
- Quick-build for walls (click-drag)

**Basic defenses:**
- Wooden walls, reinforced doors, spike traps, arrow traps
- Defenses have HP and can be damaged/destroyed by enemies
- Construction skill improves defense HP and build speed

**Opt-in escalation system (foundation):**
- Events triggered by player progression actions (mining rare ores, killing sub-bosses)
- Telegraphed: "The ground trembles..." -> 60-second warning -> enemy wave
- Waves target nearest player structure with defenses
- Minor threats only for now (scaled up in M17)
- Player who doesn't trigger progression events stays safe

**Outpost markers:**
- Craftable item that designates a location as fast travel point and respawn location
- Limited number active at once (upgradeable later)

### What the Player Can Do
Build a proper base with rooms, storage, and crafting stations. Set up defenses that matter. Trigger escalation events through progression and defend against them. Establish outposts as forward bases. See Construction skill improve building speed and defense quality.

### Key Technical Decisions
- **Enclosed room detection** - flood fill algorithm checking for complete wall/door enclosure
- **Defenses as StaticBody2D scenes** with HP, not just tiles
- **Escalation events as data-driven triggers** - action thresholds defined in data files

### Acceptance Test
Player can build enclosed rooms. Furniture works inside rooms. Defenses take and deal damage. Escalation events trigger from specific actions and are survivable with basic defenses. Outposts work as respawn/fast-travel points. Construction skill visibly improves building.

---

## Milestone 15: Crafting Quality and Tool Progression

**Goal:** Full quality tier system goes live. Station quality, tool quality, material difficulty, and skill level all influence crafting outcomes. The full ore tier chain. This is where the crafting endgame takes shape.

### What Gets Built

**Quality roll system:**
- When crafting, a weighted random roll determines quality tier (Crude -> Standard -> Fine -> Masterwork -> Legendary -> Ancient)
- Roll influenced by three factors:
  - **Skill level (base chance):** Higher relevant crafting skill shifts probability curve toward better tiers
  - **Station + tool quality:** A crude stone anvil suppresses quality ceiling. A Fine steel anvil with good tools pushes the curve up. Station quality is now a real stat, not binary.
  - **Material difficulty:** Iron is forgiving (wide quality range achievable). Mithril is punishing (same smith gets lower quality). Material difficulty shifts what tiers are realistically reachable.
- Formula: generate a score from `skill_weight * skill_factor + station_weight * station_factor + tool_weight * tool_factor - material_difficulty`, map score to quality tier with random spread

**Station quality:**
- Stations themselves now have quality (Crude through Ancient)
- Building a better anvil requires better materials and higher Construction/Smithing skill
- Station quality directly affects the crafting quality ceiling at that station
- Creates a crafting bootstrap: better station -> better tools -> better station -> better tools

**Tool quality matters:**
- Tools used at stations (smith's hammer, tongs, etc.) have quality
- Tool quality contributes to the crafting roll
- Mining tools: quality affects mining speed and durability in addition to tier

**Full ore tier chain:**
- Copper -> Iron -> Gold -> Crystal -> Mithril -> Deep Metal -> Void Stone
- Each ore has a material_difficulty rating
- Each tier unlocks new recipes and has depth requirements
- Matching armor and weapon tiers

**Material efficiency (enhanced):**
- Skill-based efficiency from M5 now interacts with quality attempts
- Attempting higher quality uses same materials but failing wastes more
- High skill = less waste on failed quality attempts

**Quality display:**
- Item names show quality prefix: "Fine Iron Sword", "Crude Stone Pickaxe"
- Color coding in inventory (grey/white/green/blue/purple/gold)
- Tooltip shows quality effects on stats

### What the Player Can Do
Craft items and see quality results vary. Invest in crafting skills and better stations to push quality higher. Make meaningful decisions: "craft with iron I'm skilled with, or try mithril and risk Crude quality?" Build a workshop with high-quality stations. See the crafting endgame: max skill + top station + best tools + good luck = Ancient quality items.

### Key Technical Decisions
- **Quality as weighted random with influencing factors** - never purely deterministic, always a chance element
- **Station quality as a progression axis** - gives base building deep mechanical purpose
- **Material difficulty as a counterweight** - prevents instant mastery of new ore tiers
- **Bootstrap loop is intentional** - better gear requires better stations requires better gear, but each step is achievable

### Acceptance Test
Crafting produces variable quality results. Higher skill level visibly shifts quality distribution. Better stations produce better results. Harder materials produce lower quality at same skill. The full ore chain is mineable and craftable. Quality differences are meaningful in stats.

---

## Milestone 16: Class System

**Goal:** Behavior-unlocked and knowledge-unlocked classes. Two class slots. Class skill pool with slotting and progression. The BehaviorTracker data accumulated since M2 finally pays off in a big way.

### What Gets Built

**Class evaluation system:**
- Runs periodically (every N minutes or on significant events) checking BehaviorTracker data against class unlock thresholds
- Class definitions as data files: each class has unlock conditions (behavior thresholds, knowledge flags, quest flags)
- When conditions met, class is **offered** via in-game event - never forced

**Behavior-unlocked classes (examples):**
- **Swordsman:** kill X enemies with swords -> offered
- **Miner/Deep Delver:** mine X ore at depth Y+ while rarely fighting -> offered
- **Warrior:** kill X enemies + take Y total damage -> offered
- **Berserker:** nearly die Z times while in combat -> offered
- Thresholds read directly from BehaviorTracker lifetime counters

**Knowledge-unlocked classes:**
- Triggered by finding lore items, completing NPC quests, or discovering secrets
- Example: find ancient tome -> reveals "Crystal Warden" requirements -> meet behavior requirements -> offered
- Knowledge flags stored in BehaviorTracker

**Two class slots:**
- Main class + secondary class
- Each slot independent, can hold any class
- Classes complement or diversify based on player choice

**Class skill pool:**
- Each class has a skill pool with more skills than can be equipped at once (~2-3 active + 2-3 passive **slots**, but the pool contains more skills to choose from)
- Skills are **permanently unlocked** into the pool when class-specific conditions are met (class level, play patterns within the class)
- Player chooses which unlocked skills to **slot** into their limited active and passive slots
- Skills can be swapped freely, but slotting a new skill resets its progress to zero - it must be leveled through use. The old skill retains its progress in the pool and can be slotted back later at full strength.
- Active skills: usable abilities (bound to keys)
- Passive skills: always-on stat bonuses or effects
- Skills influenced by HOW you played: Berserker who uses hammers unlocks different skills than Berserker who uses fists
- The skill pool is a collection - more unlocks means more strategic flexibility

**Class swapping:**
- When a new class is offered, player can accept it into an empty slot or replace an existing class
- Replacing resets that slot: all class progress and class skills from old class are lost
- This makes the choice meaningful and encourages commitment

**Class UI:**
- Class panel showing: current classes, class level, earned class skills, active offers
- Offer screen: dramatic presentation of the class being offered, with description and skill preview
- Clear warning on class swap about what will be lost

### What the Player Can Do
Play naturally and receive class offers based on their actual behavior. Accept or decline classes. Fill two class slots. Unlock class skills into the pool and choose which to slot into limited active/passive slots. Experiment with different skill loadouts, investing time to level favorites. See their goblin develop a unique identity. Optionally swap classes at a real cost.

### Key Technical Decisions
- **Class definitions as data files** - easy to add new classes without code changes
- **BehaviorTracker as the source of truth** - class system reads, never writes to BehaviorTracker
- **Periodic evaluation, not per-action** - checking every action would be wasteful; batch check on intervals
- **Class skill pool with slotting** - unlocks are permanent, tension comes from leveling investment, encourages experimentation and replayability
- **Skill unlocks influenced by sub-behavior** - not just "you're a Berserker" but "you're a hammer Berserker"

### Acceptance Test
Player who mines heavily gets offered a mining class. Player who fights with swords gets offered Swordsman. Class offers feel earned, not random. Class skills unlock permanently into the pool. Slotting and swapping skills works correctly - newly slotted skills start at zero progress, previously leveled skills retain their progress in the pool. Swapping a class clears all progress from the old class. Two classes can be held simultaneously.

---

## Milestone 17: Progression and Bosses

**Goal:** Boss encounters gating major progression. Ability unlocks. World evolution. Relics as boss drops and exploration rewards. Escalation events scale up.

### What Gets Built

- **2-3 bosses:** Cave Guardian (~depth 100), Crystal Titan (~depth 300), Deep Watcher (~depth 500)
- **Boss arenas:** Hand-designed room templates embedded in world generation at specific depths
- **Boss patterns:** Multi-phase fights with telegraphed attacks, unique mechanics per boss
- **Ability system:** Wall climb, enhanced dash, double jump - unlocked through boss defeat or deep exploration
- **Relics:** Permanent perk items found as boss drops, in hidden rooms, and in ancient ruins. Each grants a specific enhancement. Some bear chicken motifs. Relics stack on top of class skills - independent progression layer.
- **World evolution:** Boss kills change the world (new enemy types appear, new ore veins generate, "the depths are angry" events)
- **Escalation scaling:** Boss kills trigger larger defense events, telegraphed well in advance
- **NPC training preview:** One or two hidden master NPCs who teach specific techniques (combat move, crafting secret) in exchange for resources or tasks. This previews the full NPC system in M19.

### What the Player Can Do
Seek out bosses, learn their patterns, defeat them. Gain new traversal abilities. Find relics that permanently enhance the character. See the world respond to their victories. Defend against escalated threats. The full character identity stack starts coming together: skills + classes + class skills + relics.

---

## Milestone 18: Surface World and Biomes

**Goal:** Player breaks through to the surface. Overworld biomes exist. The game's scope expands dramatically.

### What Gets Built

- **Surface generation:** Height map terrain, biome assignment, trees/vegetation, sky background
- **Biomes:** Forest, desert, mountains, coast - unique tiles, resources, enemies
- **Sky/weather:** Parallax background, day/night cycle, weather particles
- **The breakthrough moment:** Dramatic transition from underground to open sky - a milestone moment for the player
- **Underground biomes beneath surface biomes** - surface type influences sub-surface generation
- **Surface enemies and resources** - distinct from underground, different difficulty ratings for skill XP

---

## Milestone 19: NPCs, Trade, and Training

**Goal:** Discoverable NPCs and civilizations. Trade system. NPC training as a perk source. Knowledge-unlocked classes from NPC interactions.

### What Gets Built

- **NPC system:** CharacterBody2D scenes with dialogue, trade, and training capabilities
- **Discoverable settlements:** Found through exploration - mushroom village underground, goblin survivors, ancient civilization in the deep
- **Dialogue system:** Branching text with conditions based on player progress and BehaviorTracker data
- **Trade system:** Buy/sell interface. NPCs sell unique items, blueprints, lore, cosmetics. Currency: gold coins + barter for rare goods
- **NPC training:** Masters hidden in the world teach permanent techniques. Training costs resources, time, or completing a task. These are perks independent of the class system - they stack on top.
- **Knowledge unlocks from NPCs:** NPCs reveal class requirements, hidden locations, lore that flags knowledge-unlocked classes
- **Chicken conspiracy integration:** NPCs mention strange chickens, some sell suspicious eggs, settlements have chicken motifs

### What the Player Can Do
Discover that they're not alone. Trade excess resources for unique items. Seek out masters for training. Learn about hidden classes from NPC knowledge. The world feels populated and alive.

---

## Milestone 20: Automation

**Goal:** Optional automation systems tied to Engineering skill.

### What Gets Built

- **Conveyor belts, auto-miners, sorting systems, processing chains**
- **Simple power system:** Fuel-based, later crystal power
- **Engineering skill integration:** Higher skill = more efficient machines, access to advanced components
- **Philosophy:** Rewarding to set up, never required to progress. Frees the player from repetitive gathering.

---

## Milestone 21: Additional Realms

**Goal:** Portal system to new dimensions with unique rules.

### What Gets Built

- **Portal system:** Craftable or discoverable frames with activation requirements
- **2+ realms:** Unique generation, tilesets, enemies, resources, atmosphere
- **Realm-specific mechanics:** Different rules per realm (gravity, hazards, resources)
- **Cross-realm resources:** Some recipes require multi-realm materials
- **Realm-specific class unlocks and relics**

---

## Milestone 22: Narrative and Chicken Conspiracy

**Goal:** Environmental storytelling woven throughout the world. Endgame revelation.

### What Gets Built

- **Environmental storytelling:** Carvings, journals, murals placed during world generation
- **Chicken placement system:** Chickens in impossible places, footprints near sealed doors, suspicious motifs
- **Lore collectibles:** Documents piecing together the conspiracy
- **Endgame sequence:** The chicken truth revealed
- **Post-game:** World persists for sandbox play. Sequel hook for Dungeon Chicken.

---

## Milestone 23: Multiplayer

**Goal:** Drop-in/drop-out co-op using the architecture built from day one.

### What Gets Built

- **Networking:** `ENetMultiplayerPeer` (LAN), potentially Steam networking
- **Player replication:** `MultiplayerSpawner` + `MultiplayerSynchronizer`
- **State sync:** World changes as RPCs, world data sync from server to clients *(Updated: originally "chunk streaming" when using dynamic chunk loading)*
- **Host-as-server model:** One player hosts, others join
- **Skill/class/behavior per player:** Each player has independent BehaviorTracker, SkillSystem, and class data

This is why we built client-server from day one. GameServer becomes the network authority. InputManager routes over network. BehaviorTracker is per-player, not global.

---

## Milestone 24: Polish and Steam

**Goal:** Ship-ready game.

### What Gets Built

- **Sound/Music:** SFX, ambience per biome, music per zone/boss
- **Particles:** Mining debris, combat hits, environmental effects
- **Steam integration:** GodotSteam plugin, achievements, cloud saves
- **Performance:** Target 60fps on mid-range hardware
- **Accessibility:** Remappable controls, UI scaling, colorblind options
- **Localization:** All strings through `tr()`
- **Balancing pass:** Skill XP curves, quality roll weights, class thresholds, material difficulty ratings - all tuned through extensive playtesting

---

## Risk Areas

| Risk | Mitigation |
|------|------------|
| Darkness overlay seams | 34x34 darkness images with region_rect for seamless boundaries *(Updated: originally "Chunk border seams" when using per-chunk TileMapLayers)* |
| Performance with large worlds | Finite world with all data in memory, 2 global TileMapLayers, full upfront loading with progress bar *(Updated: originally "Performance with many chunks")* |
| Boring world generation | Multiple noise layers, structures, POIs, constant playtesting |
| Floaty combat | Nail movement in M1 first. Frame-precise hitboxes. Playtest constantly. |
| Multiplayer retrofit pain | Client-server architecture from M1 prevents this |
| Skill XP curve feels grindy or too fast | Soft cap formula is tunable. Expose difficulty multiplier curve as data. Playtest every ore/enemy tier. |
| Class system feels random or unearned | BehaviorTracker gives exact data. Thresholds tunable. Add "you're close to unlocking..." hints if needed. |
| Quality system feels like gambling | Weight the roll heavily toward skill/station factors. RNG adds excitement, not frustration. Bad luck protection (pity counter) if needed. |
| Behavior tracking performance | Lightweight counters only. No per-frame tracking. Signal-based, batched writes. Profile early. |
| Station bootstrap loop feels stuck | Ensure each tier is achievable with previous tier's best. Tune material difficulty so the jump is challenging, not impossible. |
| Scope creep | Each milestone is playable. Cut from the end (M20-M22 most cuttable). Core identity is M1-M16. |

---

## Start Here

**Milestones 1-7 plus Phase 1/1.5 are complete.** Next up is M8 (Containers), building on the inventory and equipment systems from M7.
