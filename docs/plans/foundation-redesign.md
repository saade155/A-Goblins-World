# Foundation Redesign -- World, Tiles, Art Pipeline

## Overview

Major overhaul of the game's visual and world systems. Replaces the current 32px tile / infinite generation approach with a new foundation built around smaller tiles, finite structured worlds, depth layering, and a new art pipeline (approach TBD -- 3D-to-sprite rendering is being explored).

## Decisions Locked

### Tile Size: 16px
- Down from 32px. Player is roughly 3 tiles tall.
- Gives terrain organic, sculpted feel -- caves curve, walls are thin, slopes are smooth.
- Mining interaction needs rework -- area/radius mining instead of single-tile clicking.

### Viewport / Resolution
- Moving up in resolution (exact TBD, but larger than current 960x540).
- Goal: more visual detail, modern feel while retaining retro game structure.

### World Structure: Finite, Structured Random
- Worlds are finite and bounded -- not infinite generation.
- Fully procedural but with structural rules -- "structured randomness."
- Each biome generates as one large contiguous region, not scattered patches. One jungle, one crystal cave, one volcanic zone -- massive and explorable.
- Every world guarantees all biomes and progression-critical structures. No bad seeds.
- Characters can travel between worlds (other players' worlds, other saves) -- Terraria model.

### World Transitions / Doorways
Three types of map transitions:
1. **Dungeons** -- Discovered structures with entrances in the main world. Self-contained procedural sub-maps tied to their biome (jungle temple, ice fortress, volcanic forge, etc.).
2. **Portals** -- Rarer, more dramatic. Transport to entirely separate realm worlds with their own generation rules and biome sets (The Abyss, Mushroom Realm, Sky Realm, etc.).
3. **Parallax depth transitions** -- Move "into" the background. The world has depth layers visible through parallax. Background caves and chambers are visible but unreachable until you find the transition point. Gives the 2D world real dimensionality without going 3D. Inspired by Hollow Knight's background teasing.

### Depth Layering
- The world is not a single flat 2D plane. Multiple depth layers exist per area.
- Background layers are rendered with parallax and are visually present but not interactive until you transition in.
- Transition points connect depth layers -- a doorway in a cave wall, a gap you squeeze through, a ledge you drop behind.
- This makes the world feel 3D while remaining 2D gameplay.

### Fog of War
- World-owned, globally shared state.
- Once any player reveals a tile/area, it's revealed for everyone permanently.
- Unrevealed areas render as dark/fog -- you don't know what's there until you explore.
- Separate from dynamic lighting/darkness system.

### Player/World Data Split
- **Player-owned data**: Skills, inventory, equipment, abilities, classes, experience, behavior stats. Travels with the character across worlds.
- **World-owned data**: Terrain, tile states, structures, NPC states, player positions (keyed by player ID), fog of war reveal state.
- Save paths: `user://players/<id>/` for player data, `user://worlds/<slot>/` for world data.

### Biomes -- Main World

**Surface (7):**
| Biome | Purpose |
|-------|---------|
| Forest | Home base. Safe, abundant resources. Building, returning. |
| Desert | Heat hazard. Sand-based resources. Gateway to volcanic underground. |
| Swamp | Poison/debuff zone. Rare alchemical ingredients. |
| Mountains | Verticality challenge. Exposed cliff ores. High-altitude caves. |
| Snowy Peaks | Cold hazard. Frozen Caverns access. Ice resources. |
| Beach | Transition zone. Ocean access. (Purpose TBD -- fishing, coastal content) |
| Ocean | Water traversal. Underwater content potential. (Purpose TBD) |

**Underground (7):**
| Biome | Depth Tier | Purpose |
|-------|-----------|---------|
| Standard Caverns | Shallow | Learning zone. Basic ores, predictable layout. |
| Sandy Hollows | Shallow | Desert's underground. Early resources. |
| Swamp Depths | Shallow-Mid | Tight, claustrophobic. Biological/alchemical materials. |
| Fungal Grove | Mid | Alien flora. Emerald. Portal potential (Mushroom Realm). |
| Frozen Caverns | Mid | Cold hazard. Extra caves. Mid-tier ores. |
| Volcanic Depths | Deep | Fire hazard. Endgame ores (Ruby). Dangerous. |
| Crystal Caverns | Deep | Rare crystal resources. Visually spectacular. Late-game. |

**Removed from main world:**
- The Abyss -- becomes a separate portal realm with its own identity and generation rules.

### Sister Realms (separate world maps)
- The Abyss -- alien, terrifying, its own rules. Accessed via portal.
- Mushroom Realm -- potential portal from Fungal Grove.
- Others TBD (Sky/Celestial, Shadow, etc.).

### Tile Rendering (Direction)
- Splat tiles for ores and minables -- noise-mask blending of ore texture onto base rock.
- Standard autotile format for terrain shapes (replacing current custom 16-column edge/corner system).
- Exact autotile format TBD.

## Art Pipeline (Direction Being Explored -- Not Locked)

The art production pipeline has not been decided yet. The direction below is one approach being explored.

### Explored Approach: 3D to Sprite
- **Potential workflow:** Models built in Blender (or similar), rendered to sprite sheets via orthographic camera + shaders.
- Under this approach, equipment would be mesh/material swaps on the model, re-rendered. Animations would be done in 3D with frames exported automatically.
- If adopted, sprites would not be constrained by pixel-perfect integer scaling, which affects viewport/resolution decisions.
- Motivation for exploring this: removes hand-drawn sprite art bottleneck -- Christian is stronger in 3D than 2D sprite work.

### Art Style (Decided Regardless of Pipeline)
- Retro-feeling but modern. Dark atmospheric with vibrant biome contrast.
- Not pixel-art-retro but stylized-retro (think later Mega Man, Hollow Knight mood, Craft the World).

## What Survives From Current Codebase
- World generation algorithms (conceptually -- noise-based biome placement, but rewritten for finite/structured approach)
- Save system architecture (paths, threading, snapshots -- but world data format changes)
- Skill system (M5 -- carries forward unchanged)
- Game server authority pattern
- Inventory system
- Menu system (needs rescaling)
- Settings system

## What Gets Rebuilt
- Tile atlas mapping and edge/overlay system (tile_data.gd)
- Chunk system (finite world changes loading strategy)
- World generator (structured region placement instead of pure noise)
- Player sprite system (new art pipeline replaces hand-drawn sheets -- exact approach TBD)
- Darkness / lighting system
- Camera zoom levels
- All tile art assets
- All player/character art assets

## Open Questions
- Exact viewport resolution
- Autotile format selection (47-tile blob, Godot 3x3 minimal, other?)
- World dimensions in tiles (how big is "large but bounded"?)
- Biome placement algorithm specifics (Voronoi regions? recursive subdivision?)
- Parallax depth layer implementation details
- Beach and Ocean biome purpose -- need real gameplay identity or merge/cut
- Dungeon generation approach (templates + procedural fill? fully procedural? hand-designed rooms?)
- Art pipeline decision -- 3D-to-sprite is being explored but alternatives may emerge. If 3D: Blender workflow, shader approach for sprite export
- Splat tile implementation (runtime blending vs pre-baked variants)

---

*Document created during foundation redesign discussion. Updated as decisions are made.*
