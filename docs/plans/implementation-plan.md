# This Goblin's World - Implementation Plan

**Engine:** Godot 4.4+ (GDScript)
**Solo dev + AI assisted**

Structured as milestones that each produce something playable. Early milestones (1-6) are detailed with Godot specifics. Mid milestones (7-10) have moderate detail. Later milestones (11-18) are broader because the right decisions depend on what we learn building the foundation.

---

## Architectural Principles (Apply From Day One)

These are not a milestone. They are constraints that apply from line one of code.

**Client-Server Mindset:**
Every game action flows through an authority. In single-player, the local game IS the server - but the code treats it that way:
- Game logic lives in "system" scripts, not in player or UI scripts
- State changes go through a `GameServer` autoload
- The player controller emits input events; it does not directly modify world state
- Rendering reads from authoritative state, never writes to it

**Chunk Architecture:**
The world is effectively infinite. From day one:
- World data is stored in chunks (dictionaries of tile data, not TileMapLayer nodes)
- Only chunks near the player get rendered via TileMapLayer
- Chunks load/unload as the player moves
- World generation happens per-chunk on demand

**Data vs. Presentation:**
World state (what tile is at position X,Y) is data in dictionaries. TileMapLayer nodes are presentation. This separation is what makes multiplayer, saving, and chunk streaming possible.

**Behavior Tracking System (Foundational):**
The game watches what the player does from the very first session. This system is not a milestone feature - it is infrastructure that goes in early and feeds everything later:
- Every meaningful player action is recorded: blocks mined (type, depth), enemies killed (type, weapon used), items crafted (type, station), damage taken (type, source), spells cast, distances traveled, resources gathered, tools used, stations built
- Tracked as cumulative counters and rolling windows (recent behavior matters for class offers, lifetime totals matter for thresholds)
- This data feeds: skill XP calculations (Milestone 5), class unlock evaluation (Milestone 10), dynamic difficulty awareness, and analytics
- The tracking system is a `BehaviorTracker` autoload that listens to signals from `GameServer` - it never modifies game state, only observes
- Storage is lightweight: dictionaries of counters, serialized with save data
- Even before skills or classes exist in-game, every action is being counted. When those systems come online, they read from a rich history of player behavior

---

## Milestone 1: Project Setup and Core Movement

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
    chunk_renderer.gd  # TileMapLayer wrapper (stub)
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

**World data layer (chunk_data.gd):**
- `Dictionary` keyed by `Vector2i` chunk coords
- Functions: `get_tile(world_pos)`, `set_tile(world_pos, type)`, `remove_tile(world_pos)`
- TileMapLayer reads from this data, never the other way around

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
- **Chunk data as plain dictionaries** - fast to serialize for saving and networking
- **Mining progress visual** - overlay sprite with crack frames
- **Signal-based behavior tracking** - GameServer emits, BehaviorTracker listens, zero coupling

### Acceptance Test
Player can mine a tunnel, blocks drop items, items get picked up, blocks can be placed. Mining respects hardness. World data and visual tilemap stay in sync. `BehaviorTracker.get_count("tile_mined")` returns correct count after mining.

---

## Milestone 3: Chunk System and World Generation

**Goal:** Procedurally generated, effectively infinite world. Chunks load/unload as the player moves. Game starts underground. BehaviorTracker records depth reached.

### What Gets Built

**Chunk manager (autoload):**
- Tracks player position, determines active chunk radius (5x5 around player)
- Loads entering chunks, unloads leaving chunks
- One TileMapLayer per active chunk, positioned at world offset
- Chunk size: 32x32 tiles (512x512 pixels)
- Background thread generation, main thread application via `call_deferred`

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

**Chunk persistence:**
- Modified chunks saved to disk (`user://worlds/<name>/chunks/<x>_<y>.dat`)
- Unmodified chunks regenerated from seed (not saved)

**Lighting (basic):**
- Depth-based ambient darkness (CanvasModulate or shader)
- Placeable torches as `PointLight2D` with limited range

**BehaviorTracker additions:**
- Track `max_depth_reached` - updated whenever player moves deeper than previous record
- Track movement distance (cumulative)
- Track ore types encountered (first discovery of each type)

### Chunk Lifecycle
```
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
- **Chunk size 32x32** - fast generation, manageable count
- **One TileMapLayer per chunk** - natural physics boundaries
- **FastNoiseLite over cellular automata** - deterministic per-coordinate, chunks generate independently
- **Background thread generation** - prevents frame drops
- **Dirty chunk tracking** - only modified chunks saved
- **Y-axis goes down** - deeper = higher Y values in Godot 2D
- **BehaviorTracker serialized with save data** - chunk persistence and behavior data save/load together

### Acceptance Test
World generates seamlessly in any direction. No pop-in, no frame drops. Modified terrain persists after leaving/returning. Depth zones are visually distinct. Spawn chamber always generates correctly. `BehaviorTracker.get_stat("max_depth_reached")` updates correctly as player descends.

---

## Milestone 4: Inventory, Crafting, and Menus (NEXT)

**Goal:** Full inventory system with station-based crafting, quality foundation, and complete menu infrastructure (title screen, pause menu, settings, save slots).

### Sub-phases

#### 4A: Item Database + Inventory Data Layer
- **Item database (autoload):** Static registry loaded from data files. Items have: id, name, icon, max_stack, type (material/tool/weapon/placeable/consumable), metadata. Tools add: tool_quality (enum: Crude/Standard/Fine/Masterwork/Legendary/Ancient), mining_power, crafting_bonus
- **Inventory system:** Fixed slots (30 + 10 hotbar), item stacking, split/swap. State lives on GameServer, UI reads from it

#### 4B: Menus + Save Slots
- **Title screen:** New Game / Load Game / Settings / Quit
- **Pause menu (Escape):** Resume / Settings / Save & Quit / Quit to Title
- **Settings menu:** Audio (master/sfx/music volume), Video (fullscreen, resolution), Controls (keybinding display, remapping deferred to later)
- **Save slot system:** Multiple worlds instead of hardcoded `user://worlds/default/`. SaveManager parameterized by world slot. World metadata: name, playtime, last played date, thumbnail (stretch)
- **Load screen:** Show existing saves with metadata, delete save option

#### 4C: Game HUD + Inventory UI
- **HUD:** Hotbar with selected slot highlight, health bar
- **Inventory grid:** Drag/drop, split/swap, right-click actions
- **Crafting panel:** Available recipes filtered by nearby station
- **Tooltip system:** Item name, quality, stats, description

#### 4D: Crafting System + Stations + Recipes
- **Hand-crafting:** Limited to survival basics — torches, crude bandages, campfires, rope, crude stone tools. Available anywhere, no station needed. Always produces Crude quality
- **Station-based crafting:** Stations are interactive world scenes — walk up, press interact, filtered recipe UI opens. Always produces Standard quality
- **Stations gate recipe categories:**
  - Workbench: basic items, furniture, building components
  - Furnace: smelting ores into bars
  - Anvil: weapons, armor, tools
- **Station progression chain:** Workbench → Furnace (needs workbench to build) → Anvil (needs smelted iron from furnace)
- **Recipe database** with station requirements. Authority validates ingredients before crafting

#### 4E: Tool Progression + Quality + BehaviorTracker
- **Tool progression:** Wood → Stone → Iron → Gold pickaxes. Each tier mines faster and mines harder blocks
- **Quality foundation:** Enum: Crude/Standard/Fine/Masterwork/Legendary/Ancient. Quality field on every item from day one. Quality affects displayed stats (multipliers per tier defined in data). Weighted roll system deferred to M9
- **Initial recipes:**
  - Hand-craft: torches, campfire, crude stone pickaxe, crude bandage
  - Workbench: wooden tools, furniture, furnace components
  - Furnace: ore → bars (copper, iron, gold)
  - Anvil: metal tools, weapons, armor
- **BehaviorTracker additions:** items_crafted (by type and station), stations_built (by type), stations_used (by type), items_consumed

### Key Technical Decisions
- Item database as data files — easy to add items without code changes
- Inventory on authority side — UI sends requests, reacts to confirmed changes
- Quality field on every item from day one — data structure ready for M9
- Hand-crafting = Crude, station-crafting = Standard — immediately communicates that stations matter
- Menus use CanvasLayer with Control nodes — independent of game world rendering
- Save slots parameterize SaveManager — minimal refactor of existing persistence

### Acceptance Tests
1. **Inventory:** Pick up items, stack, split, swap, drop. Edge cases (full inventory, max stack) handled
2. **Crafting loop:** Mine → hand-craft crude stone pickaxe → build workbench → craft furnace → smelt iron → build anvil → craft iron pickaxe. Crude pickaxe visibly worse than anvil-crafted
3. **Menus:** Title screen → New Game starts fresh world. Escape pauses. Settings persist. Save & Quit → Load Game restores state
4. **Save slots:** Create multiple worlds, load each independently, delete a save
5. **BehaviorTracker:** `get_count("items_crafted")` is accurate

---

## Milestone 5: Skill System and Behavior Tracking

**Goal:** Learn-by-doing skill system goes live. Skills level through use, soft-capped by environment difficulty. The BehaviorTracker data accumulated since Milestone 2 feeds into XP calculations. Material efficiency starts working.

### What Gets Built

**Skill system (autoload: `SkillSystem`):**
- Skills as data: `Dictionary` of skill_id -> { level: int, xp: float, xp_to_next: float }
- Initial skill list:
  - **Mining** - leveled by mining tiles
  - **Smithing** - leveled by crafting at anvil/forge
  - **Construction** - leveled by placing blocks and building
  - **Survival** - leveled by crafting consumables, healing, cooking
  - **Melee** - stub, leveled by combat (Milestone 6 activates it)
  - **Defense** - stub, leveled by taking/blocking damage (Milestone 6 activates it)
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
- This means: mining basic stone at Mining 50 gives almost nothing. Mining iron at Mining 50 gives good XP. Mining crystal at Mining 50 gives great XP.
- Ore/tile difficulty values defined in tile_data. Enemy difficulty defined in enemy_data (for Milestone 6).

**Skill effects (immediate, scaling):**
- **Mining:** speed bonus (% faster per level), chance for bonus ore drop, reduced tool durability loss
- **Smithing:** (prepares for Milestone 9) for now just tracks XP, no quality influence yet
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
- Historical data from BehaviorTracker doesn't retroactively grant XP (skills start at 0 when this milestone goes live in dev, but in the shipped game, skills exist from the start)
- BehaviorTracker continues accumulating all counters - class system (Milestone 10) will read lifetime totals

**Skill UI:**
- Simple skill panel accessible from inventory screen
- Shows: skill name, current level, XP bar to next level, list of earned perks
- No skill point allocation - this is purely informational ("here's what you've become")

**Save/load:**
- Skill data serialized with save file
- BehaviorTracker data serialized with save file

### What the Player Can Do
Mine and watch Mining skill level up. Notice mining gets faster as skill increases. See that mining easy ores gives almost no XP while harder ores give more. Craft and watch Smithing skill rise. Hit skill milestones and receive perk bonuses. Open the skill panel to see progress. Notice material costs go down as crafting skill improves.

### Key Technical Decisions
- **Skills as pure data** - no nodes, no scenes, just dictionaries. Fast to query, easy to serialize
- **Challenge-based XP** - the core design principle. Environment difficulty IS the progression gate
- **BehaviorTracker stays separate from SkillSystem** - BehaviorTracker records everything (for classes later), SkillSystem only cares about XP-relevant actions
- **No retroactive XP** - skills level from actions taken after the system exists. In shipped game this is seamless since skills exist from Milestone 1's save data
- **Material efficiency as a multiplier on recipe cost** - simple math, big impact on feel
- **Perks as data entries, not code** - easy to add new perks without touching skill system code

### Acceptance Test
Mining stone gives Mining XP. Mining dirt at Mining level 20+ gives almost no XP. Mining iron at Mining level 20 gives good XP. Mining speed visibly improves with Mining level. Material costs decrease with skill. Skill panel shows accurate data. Milestone perks trigger at correct thresholds. All data persists through save/load.

---

## Milestone 6: Combat Foundation

**Goal:** Melee combat with dodging, hitbox/hurtbox system, one test enemy. Combat skills start leveling through use via the skill system.

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
- Weapons have quality field (all Standard for now, quality variation in Milestone 9)

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
- These counters are critical: they directly feed class unlock evaluation in Milestone 10. A player who fights with swords accumulates sword kills. A player who takes tons of damage accumulates damage-taken counters. The class system reads all of this.

### What the Player Can Do
Equip sword or hammer, attack cave bats, dodge through swoops, kill for loot, die and respawn. Watch Melee and Defense skills level up through combat. Notice that fighting tougher enemies gives more combat XP. Combat feels snappy and skill-based.

### Key Technical Decisions
- **Hitbox/hurtbox with Area2D** - precise, frame-based collision
- **Animation-driven combat** - AnimationPlayer keyframes control hitbox timing
- **State machine** for player and enemies (simple script pattern, no framework)
- **Damage through GameServer** - `deal_damage(source, target, amount, type)` -> signals -> BehaviorTracker + SkillSystem both listen
- **Stamina system** introduced here - shared resource for dodge and later heavy attacks
- **Enemy difficulty_level** as data - directly plugs into skill XP formula from Milestone 5
- **Every combat action tracked** - this is non-negotiable. Class unlocks depend on rich combat history

### Acceptance Test
Player can equip weapons, attack the cave bat, dodge its swoop, kill it for loot. Death respawns correctly. Melee skill gains XP from kills scaled by enemy difficulty. Defense skill gains XP from damage taken. BehaviorTracker shows accurate combat statistics. Hit registration is frame-precise with no phantom hits.

---

## Milestone 7: Enemy AI and Encounters

**Goal:** Multiple enemy types populating the cave system with natural spawning. Depth-based difficulty scaling. Combat becomes a real part of the exploration loop.

### What Gets Built

**Spawning system:**
- Chunk-based spawn evaluation: each active chunk has a spawn budget based on depth
- Max enemies per chunk, minimum distance from player for spawning
- Spawn tables per depth zone (weighted random from enemy pool)
- Enemies despawn when their chunk unloads

**3-5 enemy types, each with unique behavior:**
- **Cave Bat** (from M6, refined): Flies, swoops, low HP, fast - shallow caves
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
- **Chunk-based spawning** - natural population control, tied to world streaming
- **Difficulty_level per depth variant** - plugs directly into skill XP soft cap
- **Loot tables as data** - JSON/Resource files, easy to tune

### Acceptance Test
Caves feel alive with enemies. Each type behaves distinctly. Depth scaling is noticeable. Loot drops reward deeper exploration. No performance issues with multiple active enemies. Kill counters in BehaviorTracker are accurate per enemy type and weapon.

---

## Milestone 8: Building and Defenses

**Goal:** Proper base building with background walls, furniture, functional defenses. Opt-in escalation system. Construction skill matters.

### What Gets Built

**Background wall layer:**
- Second TileMapLayer per chunk for background walls
- Walls define "enclosed rooms" (required for some furniture/station functionality)
- Wall types with visual variety (stone, wood, crystal)

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
- Minor threats only for now (scaled up in Milestone 11)
- Player who doesn't trigger progression events stays safe

**Outpost markers:**
- Craftable item that designates a location as fast travel point and respawn location
- Limited number active at once (upgradeable later)

### What the Player Can Do
Build a proper base with rooms, storage, and crafting stations. Set up defenses that matter. Trigger escalation events through progression and defend against them. Establish outposts as forward bases. See Construction skill improve building speed and defense quality.

### Key Technical Decisions
- **Background walls as separate TileMapLayer** - clean separation, independent rendering
- **Enclosed room detection** - flood fill algorithm checking for complete wall/door enclosure
- **Defenses as StaticBody2D scenes** with HP, not just tiles
- **Escalation events as data-driven triggers** - action thresholds defined in data files

### Acceptance Test
Player can build enclosed rooms. Furniture works inside rooms. Defenses take and deal damage. Escalation events trigger from specific actions and are survivable with basic defenses. Outposts work as respawn/fast-travel points. Construction skill visibly improves building.

---

## Milestone 9: Crafting Quality and Tool Progression

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
- Skill-based efficiency from Milestone 5 now interacts with quality attempts
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

## Milestone 10: Class System

**Goal:** Behavior-unlocked and knowledge-unlocked classes. Two class slots. Class skill pool with slotting and progression. The BehaviorTracker data accumulated since Milestone 2 finally pays off in a big way.

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

## Milestone 11: Progression and Bosses

**Goal:** Boss encounters gating major progression. Ability unlocks. World evolution. Relics as boss drops and exploration rewards. Escalation events scale up.

### What Gets Built

- **2-3 bosses:** Cave Guardian (~depth 100), Crystal Titan (~depth 300), Deep Watcher (~depth 500)
- **Boss arenas:** Hand-designed room templates embedded in world generation at specific depths
- **Boss patterns:** Multi-phase fights with telegraphed attacks, unique mechanics per boss
- **Ability system:** Wall climb, enhanced dash, double jump - unlocked through boss defeat or deep exploration
- **Relics:** Permanent perk items found as boss drops, in hidden rooms, and in ancient ruins. Each grants a specific enhancement. Some bear chicken motifs. Relics stack on top of class skills - independent progression layer.
- **World evolution:** Boss kills change the world (new enemy types appear, new ore veins generate, "the depths are angry" events)
- **Escalation scaling:** Boss kills trigger larger defense events, telegraphed well in advance
- **NPC training preview:** One or two hidden master NPCs who teach specific techniques (combat move, crafting secret) in exchange for resources or tasks. This previews the full NPC system in Milestone 13.

### What the Player Can Do
Seek out bosses, learn their patterns, defeat them. Gain new traversal abilities. Find relics that permanently enhance the character. See the world respond to their victories. Defend against escalated threats. The full character identity stack starts coming together: skills + classes + class skills + relics.

---

## Milestone 12: Surface World and Biomes

**Goal:** Player breaks through to the surface. Overworld biomes exist. The game's scope expands dramatically.

### What Gets Built

- **Surface generation:** Height map terrain, biome assignment, trees/vegetation, sky background
- **Biomes:** Forest, desert, mountains, coast - unique tiles, resources, enemies
- **Sky/weather:** Parallax background, day/night cycle, weather particles
- **The breakthrough moment:** Dramatic transition from underground to open sky - a milestone moment for the player
- **Underground biomes beneath surface biomes** - surface type influences sub-surface generation
- **Surface enemies and resources** - distinct from underground, different difficulty ratings for skill XP

---

## Milestone 13: NPCs, Trade, and Training

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

## Milestone 14: Automation

**Goal:** Optional automation systems tied to Engineering skill.

### What Gets Built

- **Conveyor belts, auto-miners, sorting systems, processing chains**
- **Simple power system:** Fuel-based, later crystal power
- **Engineering skill integration:** Higher skill = more efficient machines, access to advanced components
- **Philosophy:** Rewarding to set up, never required to progress. Frees the player from repetitive gathering.

---

## Milestone 15: Additional Realms

**Goal:** Portal system to new dimensions with unique rules.

### What Gets Built

- **Portal system:** Craftable or discoverable frames with activation requirements
- **2+ realms:** Unique generation, tilesets, enemies, resources, atmosphere
- **Realm-specific mechanics:** Different rules per realm (gravity, hazards, resources)
- **Cross-realm resources:** Some recipes require multi-realm materials
- **Realm-specific class unlocks and relics**

---

## Milestone 16: Narrative and Chicken Conspiracy

**Goal:** Environmental storytelling woven throughout the world. Endgame revelation.

### What Gets Built

- **Environmental storytelling:** Carvings, journals, murals placed during world generation
- **Chicken placement system:** Chickens in impossible places, footprints near sealed doors, suspicious motifs
- **Lore collectibles:** Documents piecing together the conspiracy
- **Endgame sequence:** The chicken truth revealed
- **Post-game:** World persists for sandbox play. Sequel hook for Dungeon Chicken.

---

## Milestone 17: Multiplayer

**Goal:** Drop-in/drop-out co-op using the architecture built from day one.

### What Gets Built

- **Networking:** `ENetMultiplayerPeer` (LAN), potentially Steam networking
- **Player replication:** `MultiplayerSpawner` + `MultiplayerSynchronizer`
- **State sync:** World changes as RPCs, chunk streaming from server to clients
- **Host-as-server model:** One player hosts, others join
- **Skill/class/behavior per player:** Each player has independent BehaviorTracker, SkillSystem, and class data

This is why we built client-server from day one. GameServer becomes the network authority. InputManager routes over network. BehaviorTracker is per-player, not global.

---

## Milestone 18: Polish and Steam

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
| Chunk border seams | Overlap by 1 tile or shader fix |
| Performance with many chunks | Strict unloading, object pooling, LOD |
| Boring world generation | Multiple noise layers, structures, POIs, constant playtesting |
| Floaty combat | Nail movement in M1 first. Frame-precise hitboxes. Playtest constantly. |
| Multiplayer retrofit pain | Client-server architecture from M1 prevents this |
| Skill XP curve feels grindy or too fast | Soft cap formula is tunable. Expose difficulty multiplier curve as data. Playtest every ore/enemy tier. |
| Class system feels random or unearned | BehaviorTracker gives exact data. Thresholds tunable. Add "you're close to unlocking..." hints if needed. |
| Quality system feels like gambling | Weight the roll heavily toward skill/station factors. RNG adds excitement, not frustration. Bad luck protection (pity counter) if needed. |
| Behavior tracking performance | Lightweight counters only. No per-frame tracking. Signal-based, batched writes. Profile early. |
| Station bootstrap loop feels stuck | Ensure each tier is achievable with previous tier's best. Tune material difficulty so the jump is challenging, not impossible. |
| Scope creep | Each milestone is playable. Cut from the end (M14-M16 most cuttable). Core identity is M1-M10. |

---

## Start Here

**Milestone 1.** Create the Godot project, set up folder structure, get a CharacterBody2D on screen with good jump physics. Wire up the GameServer stub, InputManager, and BehaviorTracker skeleton. Everything depends on movement feeling right - and on the tracking infrastructure being in place from the start, even if it does nothing visible yet.
