## SurfaceBiomeData - Defines a single surface biome's terrain shape and tiles.
##
## Pure data container. No logic. Created by SurfaceBiomeRegistry,
## used by WorldGenerator to determine surface terrain height and tile types.

extends RefCounted
class_name SurfaceBiomeData

## Unique identifier.
var id: StringName

## Display name.
var name: String

## Biome noise range (0.0 to 1.0) -- partitions the noise space.
var noise_min: float
var noise_max: float

## Temperature constraints -- prevents desert next to snow.
var temp_min: float = -1.0
var temp_max: float = 1.0

## Priority for overlap resolution. Higher priority biome wins.
var priority: int = 0

## Base height (Y coordinate). More negative = higher above ground.
## This is the center of the terrain profile for this biome.
var base_height: float = -8.0

## Height amplitude -- how much the base terrain noise affects height.
## Mountains: 25, plains: 5, desert: 3.
var height_amplitude: float = 5.0

## Detail amplitude -- small-scale tile-to-tile roughness.
var detail_amplitude: float = 2.0

## Top surface tile (the very top 2 tiles).
var surface_tile: int

## Sub-surface tile (beneath surface, transition to underground).
var subsurface_tile: int

## Depth of the sub-surface layer in tiles before transitioning to stone.
var subsurface_depth: int = 5

## Whether this biome can have water (lakes/ponds) when below sea level.
var allows_water: bool = true

## Tree/vegetation density (0.0 to 1.0). Future use.
var vegetation_density: float = 0.0
