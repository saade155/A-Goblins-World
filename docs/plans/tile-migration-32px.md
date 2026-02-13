# Tile Migration: 16px to 32px

## Summary

Migrated tile size from 16px to 32px to match the art style targets in `art-guidelines.md`. At 640x360 viewport, 16px tiles were too small to read and left no room for detail. 32px tiles give us a 20x11.25 visible tile grid — tight but workable for a mining game.

All tile coordinates remain unchanged. The migration is purely a pixel-space scaling: every place that converted between tile coords and pixel coords needed `TILE_SIZE` updated, and physics constants that depended on pixel distances were doubled.

## Files Modified

| File | What Changed |
|------|-------------|
| `scripts/autoloads/game_server.gd` | `TILE_SIZE = 32`, `INTERACTION_RANGE = 96.0` (was 48) |
| `scripts/world/chunk_manager.gd` | `TILE_SIZE = 32`, `PIXEL_CHUNK_SIZE = 1024` (was 512), torch radius / lighting constants reviewed |
| `scripts/world/save_manager.gd` | `SAVE_VERSION = 2`, reject v1 saves |
| `scenes/player/player.gd` | Movement speed, jump velocity, gravity — doubled spatial values |
| `scenes/player/mining_component.gd` | Cursor snapping, interaction math uses `GameServer.TILE_SIZE` |
| `project.godot` / TileSet resource | TileSet cell size 32x32 |
| Art assets | Re-exported or upscaled to 32x32 per tile |

## TILE_SIZE Centralization

`GameServer.TILE_SIZE` is the single source of truth. Other scripts that previously had their own `const TILE_SIZE` now reference `GameServer.TILE_SIZE` or duplicate it with a comment pointing to GameServer as authority. ChunkManager keeps a local copy for performance (used in tight loops) but the comment makes the dependency explicit.

## Physics Scaling Rationale

**Rule: double spatial values, keep time values.**

- **Speed, jump velocity, gravity, ranges** — these are pixels/sec or pixels. They double because the world is twice as large in pixel space. A 3-tile interaction range is still 3 tiles, but 3 * 32 = 96px instead of 3 * 16 = 48px.
- **Animation durations, cooldowns, timers** — unchanged. A 0.3s mining swing is still 0.3s.
- **Noise frequencies, tile coordinates, chunk sizes** — unchanged. World gen operates in tile space, not pixel space.

## Save Compatibility

- `SAVE_VERSION` bumped from 1 to 2.
- `load_chunk()` and `load_world_meta()` check the version field. If version != 2, the save is rejected (returns null), and the chunk/world is regenerated from scratch.
- No migration path from v1 — the game is pre-release, and v1 saves used 16px spatial data for player position. Simpler to regenerate than to migrate every saved coordinate.
- `save_behavior_data` / `load_behavior_data` are version-tolerant (counters don't depend on tile size), but the version field is still bumped for consistency.

## World Generation: Zero Changes

World gen (`world_generator.gd`) operates entirely in tile coordinates. Noise sampling, biome assignment, surface height — all tile-space. The only pixel conversion happens downstream in ChunkManager when painting tiles to the TileMapLayer. This meant world gen needed exactly zero changes for the migration.

## Playtest Tuning Notes

These values were set for 16px and may need adjustment after playtesting at 32px:

- **Torch radius** (`TORCH_RADIUS = 8` tiles) — 8 tiles at 32px covers 256px radius. May feel too generous or too tight depending on cave scale. Test and adjust.
- **Torch falloff** (`TORCH_FALLOFF_POWER = 1.4`) — visual feel changes when tiles are larger. May want steeper or softer falloff.
- **Ambient floor** (`AMBIENT_FLOOR = 0.03`) — darkness overlay at 32px tiles means larger dark patches. Could feel oppressive or fine. Test.
- **Cave density / noise thresholds** — caves are the same in tile-count, but visually larger on screen. If caves feel too open, tighten the noise threshold. If too cramped, loosen.
- **LOAD_RADIUS** (`= 3`) — at 32px, each chunk is 1024px wide. 7 chunks across = 7168px vs 4480px needed (viewport 1920 at worst). Still fine, but monitor for pop-in at chunk edges.
- **Camera smoothing** — player moves faster in pixel-space. Camera smooth speed may need to increase to avoid feeling sluggish.
