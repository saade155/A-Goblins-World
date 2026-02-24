# Save System — Multi-Snapshot Design

## Context
Current system: one save state per world slot, overwrites on every save. No autosave, no ability to reload past points. This design adds multiple save snapshots per world with autosave support.

## Directory Structure
```
user://worlds/<world_name>/
├── world.dat                  # Immutable: seed, world config
├── behavior.dat               # Cumulative counters (world-level, not snapshotted)
├── current/                   # Live play state (chunk unload writes here)
│   ├── state.dat              # Player pos, inventory, playtime
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

**Note on behavior.dat:** Stays at world root — it's cumulative counters with no gameplay impact right now, so there's no value in snapshotting it. If a future skill system makes behavior data gameplay-relevant, we'll migrate it into snapshots then.

## Save Types

### Autosave
- **Timer-based:** Every 10 minutes during gameplay (hardcoded, not configurable in settings yet)
- **Rolling limit:** Keep last 5 autosaves, oldest gets replaced
- **Naming:** auto_1 through auto_5, with meta.dat storing trigger reason and timestamp

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
2. Copy `current/` → `saves/<name>/` **on a background thread** to avoid frame drops
3. Write `meta.dat` with timestamp, trigger reason, playtime, player position
4. For autosave: if at rolling limit, delete oldest auto save before creating new one
5. Show non-blocking "Saving..." overlay (does not pause gameplay)

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
- **Load Game menu (title screen):**
  - World list shows each world with name + last played time
  - Primary **"Load"** button resumes the most recent save (`current/` or latest snapshot) — one click to play
  - Secondary **"Restore Points"** button expands a sub-panel showing all snapshots (auto + manual) sorted by timestamp, with load and delete options
  - Common case is one click; restore points are accessible but not in the way

## Autosave Triggers (Event System)
- GameServer emits `autosave_requested(reason: String)` signal — hook is in place for future event triggers
- SaveManager listens and creates autosave with the reason as metadata
- Timer managed by a dedicated AutosaveTimer node or by GameState
- **M4.7 scope:** Timer-based autosave only. Event triggers (boss kills, artifact discoveries, biome milestones) will be wired up when those systems exist.

## Disk Budget
- ~2-4KB per dirty chunk
- ~200 dirty chunks in a well-explored world = ~600KB per save
- 5 autosaves + 20 manual saves = ~15MB per world
- Completely reasonable for modern systems

## Future Enhancements
- **Screenshot thumbnails:** Capture a viewport screenshot on save and store it alongside the snapshot (e.g., `thumbnail.png`). Display in the restore points browser for quick visual identification of save states.

## Implementation Dependencies
- Requires: M4B menus (done), working save system (done)
- Should be done before: M6 (Combat) — boss kills need autosave triggers
