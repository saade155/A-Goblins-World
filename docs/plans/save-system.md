# Save System — Multi-Snapshot Design

## Context
Current system: one save state per world slot, overwrites on every save. No autosave, no ability to reload past points. This design adds multiple save snapshots per world with autosave support.

## Directory Structure
```
user://worlds/<world_name>/
├── world.dat                  # Immutable: seed, world config
├── current/                   # Live play state (chunk unload writes here)
│   ├── state.dat              # Player pos, inventory, behavior, playtime
│   └── chunks/
├── saves/
│   ├── auto_1/                # Rolling autosaves (oldest replaced)
│   │   ├── state.dat
│   │   ├── chunks/
│   │   └── meta.dat           # Timestamp, trigger reason, playtime
│   ├── auto_2/
│   ├── "Beat First Boss"/     # Manual saves with player-chosen names
│   │   └── ...
│   └── "Cool Base Spot"/
│       └── ...
```

## Save Types

### Autosave
- **Timer-based:** Every N minutes during gameplay (interval TBD based on save duration benchmarking)
- **Event-triggered:** Boss kills, artifact discoveries, new biome entered, other significant events
- **Rolling limit:** Keep last N autosaves (suggest 5), oldest gets replaced
- **Naming:** auto_1 through auto_N, with meta.dat storing trigger reason and timestamp

### Manual Save
- Player-initiated from pause menu
- Player names the save (with auto-suggested name based on location/event)
- Never expires — player deletes manually when they want
- No hard limit (reasonable soft limit TBD, maybe 50)

## Operations

### During Play
- Chunks write to `current/` as they do now (on chunk unload, window close)
- This is the live working state, same as current behavior

### On Save (Manual or Auto)
1. Flush all dirty chunks to `current/`
2. Copy `current/` → `saves/<name>/`
3. Write `meta.dat` with timestamp, trigger reason, playtime, player position
4. For autosave: if at rolling limit, delete oldest auto save before creating new one
5. Show "Saving..." overlay for minimum 2 seconds

### On Load (from save browser)
1. Show loading screen
2. Copy `saves/<name>/` → `current/`
3. Reload the game scene (same as current load flow)
4. ChunkManager reads from `current/` as usual

### Backward Compatibility
- Existing v4 saves (flat structure) need migration on first load
- Migration: move existing files into `current/` subfolder, create `saves/` directory
- One-time, non-destructive

## UI Changes
- **Pause menu:** Add "Save Game" button (opens save name dialog)
- **Pause menu:** Add "Load Save" button (opens save browser for current world)
- **Load Game menu (title screen):** Two-level: select world → select save point within world (or load latest)
- **Save browser:** Shows all saves (auto + manual) sorted by timestamp, with delete option

## Autosave Triggers (Event System)
- GameServer emits `autosave_requested(reason: String)` signal on significant events
- SaveManager listens and creates autosave with the reason as metadata
- Timer managed by a dedicated AutosaveTimer node or by GameState
- Events that trigger autosave:
  - Boss defeated
  - Artifact/relic found
  - New biome discovered for first time
  - Player reaches new depth milestone
  - (More added as features are implemented)

## Disk Budget
- ~2-4KB per dirty chunk
- ~200 dirty chunks in a well-explored world = ~600KB per save
- 5 autosaves + 20 manual saves = ~15MB per world
- Completely reasonable for modern systems

## Implementation Dependencies
- Requires: M4B menus (done), working save system (done)
- Should be done before: M6 (Combat) — boss kills need autosave triggers
