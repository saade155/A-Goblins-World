## BiomeData - Defines a single biome's tile palette, cave density, and ore rules.
##
## Pure data container. No logic. Created and registered by BiomeRegistry,
## used by WorldGenerator to determine tile types within a biome region.

extends RefCounted
class_name BiomeData

## Unique identifier for this biome.
var id: StringName

## Display name.
var name: String

## Depth range where this biome can appear (Y tiles, deeper = higher).
var depth_min: int
var depth_max: int

## Cell value range (0.0 to 1.0) that maps to this biome at valid depths.
## Multiple biomes partition the cell value space at different depth ranges.
var cell_min: float
var cell_max: float

## Priority for overlap resolution. Higher priority biome wins.
var priority: int = 0

## Primary fill tile (most common solid tile in this biome).
var primary_tile: int

## Secondary fill tile (mixed with primary for variety).
var secondary_tile: int

## Ratio of secondary to primary (0.0 = all primary, 1.0 = all secondary).
var secondary_ratio: float = 0.3

## If true, use the legacy depth-based tile palette instead of primary/secondary.
## Only used by Standard Caverns to reproduce existing generation.
var use_depth_palette: bool = false

## Cave density modifier. Multiplied against base density threshold.
## < 1.0 = more caves (more open), > 1.0 = fewer caves (more solid).
var cave_density_modifier: float = 1.0

## Cave noise threshold override. -1.0 means use the default (-0.75).
var cave_threshold_override: float = -1.0

## Biome-specific cave threshold for the new blended cave system.
## Lower = more caves (more open), Higher = fewer caves (denser).
## 0.3 = very open (swamp), 0.6 = dense (volcanic), 0.45 = baseline.
var cave_threshold: float = 0.45

## Ore rules for this biome. Each entry:
## { "tile_type": int, "noise_index": int, "threshold": float, "min_depth": int }
var ore_rules: Array[Dictionary] = []

## If true, ONLY biome ore rules apply (base ores are suppressed).
## If false, biome ores are checked first, then base ores as fallback.
var exclusive_ores: bool = false

## Ambient light modifier (multiplied against depth-based lighting).
var light_modifier: float = 1.0

## Temperature range this biome requires (-1.0 to 1.0). Used to prevent
## incompatible biomes (e.g. lava and ice) from appearing adjacent.
## Default range covers all temperatures (no restriction).
var temp_min: float = -1.0
var temp_max: float = 1.0
