# M5: Skill System — Implementation Plan

## Context

M4.7 (save system) is done. Art spec for layered sprites is locked down. Christian is drawing while we build the next gameplay system. M5 adds learn-by-doing skills, but only **Mining** is wired end-to-end — everything else plugs in as mechanics are built.

## Design Decisions (from conversation)

- **General skills** (unlimited, passive, learn by doing): Proficiencies (Mining, Swords, etc.) + Resistances (Fire, Physical, etc.)
- **Class skills** (gated, active+passive slots): Deferred to M10. Data model accommodates them.
- **Challenge multiplier XP**: rewards playing at your skill edge (trivial=0.01x → matched=1.0x → hard=1.5x cap)
- **Perks**: data-driven level thresholds, awarded automatically on level-up
- **Skills are per-character**, not per-world — persist across worlds, travel with the player
- **Save structure**: `user://players/<id>/skills.dat` (M5 uses `default` as player ID for singleplayer)
- **Multiplayer vision**: dedicated server + P2P (host), player data is player-owned, world data is world-owned
- **Future save split** (not M5): inventory + behavior migrate to player folder; position stays in world folder keyed by player ID

## Files

### New
| File | Purpose |
|------|---------|
| `scripts/autoloads/skill_system.gd` | Core autoload — skill registry, XP, leveling, perks, queries, save/load |
| `scenes/ui/skill_panel.tscn` + `.gd` | Skill UI overlay (CanvasLayer 15) |

### Modified
| File | Change |
|------|--------|
| `project.godot` | Add SkillSystem autoload (last), add `toggle_skills` input action |
| `scripts/data/tile_data.gd` | Add `difficulty_level` (int 1-10) to each tile, add `get_difficulty()` |
| `scenes/player/mining_component.gd` | Apply mining speed bonus from SkillSystem |
| `scripts/autoloads/game_server.gd` | Bonus ore roll in `request_mine()` after successful mine |
| `scripts/world/save_manager.gd` | Add `save_skill_data()` / `load_skill_data()` methods |
| `scripts/world/chunk_manager.gd` | Wire skill save/load calls alongside behavior data at all save/load points |
| `scenes/player/player.gd` | Toggle skill panel input |

## Data Model

### SkillSystem state (per-skill)
```
skills: Dictionary  # skill_id -> {category, xp, level, status, perks_unlocked}
```
- `category`: PROFICIENCY=0, RESISTANCE=1, CLASS=2
- `status`: LOCKED=0 (not acquired), ACTIVE=1
- Proficiencies/resistances auto-acquire on first relevant action
- Class skills stay LOCKED until class system exists (M10)

### Skill definitions (const data in skill_system.gd)
Each skill: `{name, category, description, perks: Array[perk_id]}`

### Perk definitions (const data in skill_system.gd)
Each perk: `{name, description, skill_id, required_level, effect_type, effect_value}`

Mining perks:
| Level | Perk | Effect |
|-------|------|--------|
| 5 | Keen Strikes | +15% mining speed |
| 10 | Lucky Strikes | 8% bonus ore chance |
| 15 | Rock Breaker | +15% mining speed |
| 25 | Ore Sense | +12% bonus ore chance |
| 30 | Master Miner | +20% mining speed |

### Tile difficulty (added to tile_data.gd)
Int 1-10 per tile, roughly mapped from hardness:
- 1-2: Snow, Sand, Dirt, Grass, Mud
- 3: Stone, Sandstone, Clay, Ice, Mossy Stone
- 4: Copper, Iron, Hard Stone, Frozen Stone
- 5: Gold, Volcanic Rock, Emerald
- 6: Crystal, Ruby
- 7: Deep Rock
- 8: Obsidian

### XP formula
```
xp_for_level(n) = 100 * n^1.5
challenge_multiplier = smooth curve based on (tile_difficulty - skill_level_equivalent)
awarded_xp = base_xp * difficulty * challenge_multiplier
```

## Key API (SkillSystem public methods)

```gdscript
# XP & leveling
award_xp(skill_id, base_amount, difficulty) -> void
# Queries (used by gameplay systems)
get_skill_level(skill_id) -> int
get_total_perk_effect(effect_type) -> float  # sums all matching unlocked perks
has_perk(perk_id) -> bool
get_skills_by_category(category) -> Array[Dictionary]
# Save/load
get_save_data() -> Dictionary
load_save_data(data) -> void
```

## Integration Points

1. **Mining XP**: SkillSystem connects to `GameServer.tile_mined` → looks up tile difficulty → awards XP with challenge multiplier
2. **Mining speed**: `mining_component.gd` multiplies `base_mine_speed` by `(1.0 + SkillSystem.get_total_perk_effect("mining_speed"))`
3. **Bonus ore**: `game_server.gd` rolls `SkillSystem.get_total_perk_effect("bonus_ore_chance")` after successful mine
4. **Save/load**: `save_manager.gd` writes `skills.dat` to `user://players/default/`, `chunk_manager.gd` calls it at all save/load points

## Implementation Phases

### Phase 1: Data foundation
- Add `difficulty_level` to all tiles in `tile_data.gd`, add `get_difficulty()`
- Verify game still runs

### Phase 2: SkillSystem autoload
- Create `skill_system.gd` with definitions, XP formula, leveling, perks, queries
- Register in `project.godot` (after SettingsManager)
- Connect to `GameServer.tile_mined`, wire mining XP
- Test: mine tiles, verify XP prints and level-ups

### Phase 3: Save/load
- Add `_get_player_path(player_id)` → `user://players/<id>/` helper to `save_manager.gd`
- Add save/load methods writing to `user://players/default/skills.dat`
- Wire calls in `chunk_manager.gd` at all save/load points
- Test: mine, save, reload — skills persist. Start new world — same skills carry over.

### Phase 4: Mining gameplay effects
- Apply speed bonus in `mining_component.gd`
- Add bonus ore roll in `game_server.gd`
- Test: level to 5, verify faster mining. Level to 10, verify bonus drops.

### Phase 5: Skill UI
- Create skill panel (CanvasLayer 15, code-built like pause menu)
- Category tabs (Proficiencies, Resistances, [Class grayed out])
- Skill rows: name, level, XP bar, perk icons
- Toggle with keybind, pauses game when open
- Connect to skill_leveled/perk_unlocked signals

### Phase 6: Polish
- XP gain notification (small floating text)
- Level-up notification
- Write `docs/plans/skill-system.md`

## NOT building (scope boundaries)
- Class skills, active/passive slots (M10)
- Resistance gameplay effects (no combat yet)
- Non-mining proficiency wiring (no signals for them yet)
- Tool-based XP modifiers (tools don't exist yet)
- Skill respec
- Art/icons (placeholder rects)

## Gotchas
- SkillSystem autoload must load AFTER GameServer and TileDatabase — register last
- No `class_name` on autoload scripts
- Use untyped `var` when querying SkillSystem (returns Variant)
- Skill panel CanvasLayer: set `mouse_filter = IGNORE` on non-interactive containers
- `skills.dat` is new file — `load_skill_data()` returns false gracefully on missing file
- Player save path (`user://players/default/`) is separate from world path — establishes the pattern for future multiplayer/character-select without migrating anything now
