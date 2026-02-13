## WorldGenerator - Procedural chunk generation using FastNoiseLite.
##
## Generates chunk data deterministically from a world seed. Uses multiple
## noise layers for terrain density, cave carving, and ore placement.
## Each chunk is generated independently -- the same seed + chunk coord
## always produces the same result.
##
## Depth zones (Y increases downward):
##   Above surface: empty (or water below sea level)
##   Surface zone (surface_h to 0): biome-driven surface/subsurface tiles
##   Shallow (0-80): mostly dirt, some stone, iron ore
##   Mid (80-200): stone, copper ore, gold ore at depth 150+
##   Deep (200-400): hard stone, gold ore, crystal at 300+
##   The Deep (400+): deep rock, crystal

extends RefCounted
class_name WorldGenerator

## The seed used for all noise generation.
var seed_value: int

## Base noise -- determines solid vs air (terrain density).
var base_noise: FastNoiseLite

## Cave noise -- carves out larger cave pockets.
var cave_noise: FastNoiseLite

## Ore noise layers -- each ore has its own noise for placement.
## Indexed: 0=iron, 1=copper, 2=gold, 3=crystal, 4=ruby, 5=emerald

## Layer boundary noise -- warps depth boundaries so biome edges are irregular.
var boundary_noise: FastNoiseLite

## Cellular noise for biome region shapes (Voronoi cells).
var biome_cell_noise: FastNoiseLite

## Simplex noise for domain-warping biome cell boundaries.
var biome_warp_noise: FastNoiseLite

## Temperature noise - creates hot/cold zones to prevent incompatible biome adjacency.
var biome_temp_noise: FastNoiseLite

## Ore noise layers indexed for biome ore rules.
var ore_noises: Array[FastNoiseLite] = []

## Biome registry with all registered biomes.
var biome_registry: BiomeRegistry

## Surface terrain base shape -- large-scale hills and mountains.
var surface_terrain_noise: FastNoiseLite

## Surface terrain detail -- small bumps, roughness.
var surface_detail_noise: FastNoiseLite

## Surface biome assignment noise -- determines which surface biome at each X.
var surface_biome_noise: FastNoiseLite

## Surface biome registry with all registered surface biomes.
var surface_biome_registry: SurfaceBiomeRegistry

## Sea level Y coordinate. Terrain below this gets filled with water.
const SEA_LEVEL: int = -5


func _init(world_seed: int) -> void:
	seed_value = world_seed
	_setup_noise()
	biome_registry = BiomeRegistry.new()
	surface_biome_registry = SurfaceBiomeRegistry.new()


func _setup_noise() -> void:
	# Base noise - determines solid vs air
	base_noise = FastNoiseLite.new()
	base_noise.seed = seed_value
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base_noise.frequency = 0.04
	base_noise.fractal_octaves = 4

	# Cave noise - carves out larger caves
	cave_noise = FastNoiseLite.new()
	cave_noise.seed = seed_value + 1
	cave_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	cave_noise.frequency = 0.07
	cave_noise.fractal_octaves = 2

	# Ore noises - each ore has its own noise layer (indexed array for biome rules)
	ore_noises.append(_create_ore_noise(seed_value + 10, 0.1))   # 0: iron
	ore_noises.append(_create_ore_noise(seed_value + 11, 0.09))  # 1: copper
	ore_noises.append(_create_ore_noise(seed_value + 12, 0.08))  # 2: gold
	ore_noises.append(_create_ore_noise(seed_value + 13, 0.07))  # 3: crystal
	ore_noises.append(_create_ore_noise(seed_value + 14, 0.06))  # 4: ruby
	ore_noises.append(_create_ore_noise(seed_value + 15, 0.055)) # 5: emerald

	# Boundary noise - warps biome depth boundaries into irregular edges
	boundary_noise = FastNoiseLite.new()
	boundary_noise.seed = seed_value + 100
	boundary_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	boundary_noise.frequency = 0.02  # Low freq = wide, sweeping boundary warps
	boundary_noise.fractal_octaves = 3

	# Biome cell noise - Voronoi cells define biome regions
	biome_cell_noise = FastNoiseLite.new()
	biome_cell_noise.seed = seed_value + 200
	biome_cell_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	biome_cell_noise.frequency = 0.01
	biome_cell_noise.fractal_octaves = 1
	biome_cell_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	biome_cell_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE

	# Biome warp noise - deforms cell boundaries into organic shapes
	biome_warp_noise = FastNoiseLite.new()
	biome_warp_noise.seed = seed_value + 201
	biome_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	biome_warp_noise.frequency = 0.015
	biome_warp_noise.fractal_octaves = 2

	# Temperature noise - smooth zones preventing incompatible biome adjacency
	biome_temp_noise = FastNoiseLite.new()
	biome_temp_noise.seed = seed_value + 202
	biome_temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	biome_temp_noise.frequency = 0.008
	biome_temp_noise.fractal_octaves = 2

	# Surface terrain base - low frequency, large-scale landforms
	surface_terrain_noise = FastNoiseLite.new()
	surface_terrain_noise.seed = seed_value + 300
	surface_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	surface_terrain_noise.frequency = 0.002
	surface_terrain_noise.fractal_octaves = 3

	# Surface terrain detail - high frequency, small-scale roughness
	surface_detail_noise = FastNoiseLite.new()
	surface_detail_noise.seed = seed_value + 301
	surface_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	surface_detail_noise.frequency = 0.05
	surface_detail_noise.fractal_octaves = 2

	# Surface biome noise - determines which surface biome at each X
	surface_biome_noise = FastNoiseLite.new()
	surface_biome_noise.seed = seed_value + 302
	surface_biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	surface_biome_noise.frequency = 0.0008
	surface_biome_noise.fractal_octaves = 2


func _create_ore_noise(ore_seed: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = ore_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 2
	return n


## Generate all tiles for a chunk. Returns Dictionary[Vector2i, int] of
## local positions (0,0 to CHUNK_SIZE-1) to TileType values.
## Only non-EMPTY tiles are included.
func generate_chunk(chunk_coord: Vector2i) -> Dictionary:
	var tiles: Dictionary = {}
	var world_origin := chunk_coord * WorldData.CHUNK_SIZE

	for x in range(WorldData.CHUNK_SIZE):
		for y in range(WorldData.CHUNK_SIZE):
			var wx: int = world_origin.x + x
			var wy: int = world_origin.y + y
			var tile := _get_tile_at(wx, wy)
			if tile != TileDatabase.TileType.EMPTY:
				tiles[Vector2i(x, y)] = tile

	return tiles


## Public wrapper for _get_tile_at. Used by the map system to query
## tile types in chunks that haven't been generated yet (read-only, does
## not modify world_data).
func get_tile_at(wx: int, wy: int) -> int:
	return _get_tile_at(wx, wy)


## Determine what tile should exist at a given world position.
## This is the core generation logic combining all noise layers.
func _get_tile_at(wx: int, wy: int) -> int:
	# Y goes DOWN in Godot 2D. Positive Y = deeper underground.
	# The game starts at Y~0. Above Y=0 is eventually surface (not generated yet).
	# Below Y=0 is underground.

	# Surface terrain system
	var surface_h: int = _get_surface_height(wx)

	# Above the surface
	if wy < surface_h:
		# Check for water: terrain below sea level gets water above it
		var s_biome: SurfaceBiomeData = _get_surface_biome_at(wx)
		if s_biome.allows_water and surface_h > SEA_LEVEL and wy >= SEA_LEVEL:
			return TileDatabase.TileType.WATER
		return TileDatabase.TileType.EMPTY

	# Surface zone: between the surface and underground (surface_h to y=0)
	if wy <= 0:
		return _get_surface_tile_at(wx, wy, surface_h)

	# Underground (wy > 0)
	var depth: int = wy  # depth increases with y
	var biome: BiomeData = _get_biome_at(wx, wy)

	# Get base noise value (-1 to 1)
	var base: float = base_noise.get_noise_2d(wx, wy)

	# Density: positive noise = cave, negative noise = solid
	# Threshold controls how much is open. Higher = fewer caves.
	# At depth 0: ~20% open. Deeper = even more solid.
	var density_threshold: float = 0.3 + (depth / 1500.0)
	density_threshold = clampf(density_threshold, 0.3, 0.6)
	density_threshold *= biome.cave_density_modifier

	# Only strong positive noise values create caves
	if base > density_threshold:
		return TileDatabase.TileType.EMPTY

	# Cave carving layer - creates occasional larger cave pockets
	var cave: float = cave_noise.get_noise_2d(wx, wy)
	var cave_threshold: float = -0.75
	if biome.cave_threshold_override >= 0.0:
		cave_threshold = biome.cave_threshold_override
	if cave < cave_threshold:
		return TileDatabase.TileType.EMPTY

	# It's solid - determine what type based on depth and biome
	var base_tile: int = _get_base_tile_for_biome(wx, wy, depth, biome)

	# Check for ores using biome rules (override base tile)
	var ore: int = _check_for_ore_in_biome(wx, wy, depth, biome)
	if ore != TileDatabase.TileType.EMPTY:
		return ore

	return base_tile


## Determine which biome exists at a world position using cellular noise + depth + temperature.
func _get_biome_at(wx: int, wy: int) -> BiomeData:
	var warp_x: float = biome_warp_noise.get_noise_2d(wx, wy) * 40.0
	var warp_y: float = biome_warp_noise.get_noise_2d(wx + 31337, wy + 31337) * 40.0
	var cell_value: float = biome_cell_noise.get_noise_2d(wx + warp_x, wy + warp_y)
	# Warp the effective depth so biome depth boundaries are irregular, not straight lines
	var depth_warp: float = boundary_noise.get_noise_2d(wx + 7777, wy + 7777) * 25.0
	var warped_depth: int = wy + int(depth_warp)
	# Temperature determines hot/cold zone (prevents lava next to ice)
	var temperature: float = biome_temp_noise.get_noise_2d(wx, wy)
	return biome_registry.get_biome(cell_value, warped_depth, temperature)


## Get the surface height (Y of topmost solid tile) at a world X position.
## Averages over a window to smooth transitions between biomes with different heights.
func _get_surface_height(wx: int) -> int:
	var total: float = 0.0
	var samples: int = 0
	# Sample every 4 tiles across a ±16 tile window for smooth transitions
	for offset in range(-16, 17, 4):
		var sx: int = wx + offset
		var biome: SurfaceBiomeData = _get_surface_biome_at(sx)
		var base_val: float = surface_terrain_noise.get_noise_2d(float(sx), 0.0)
		var detail_val: float = surface_detail_noise.get_noise_2d(float(sx), 0.0)
		total += biome.base_height + base_val * biome.height_amplitude + detail_val * biome.detail_amplitude
		samples += 1
	return int(total / samples)


## Public wrapper for surface height. Used by external systems.
func get_surface_height(wx: int) -> int:
	return _get_surface_height(wx)


## Determine which surface biome exists at a world X position.
func _get_surface_biome_at(wx: int) -> SurfaceBiomeData:
	var biome_val: float = surface_biome_noise.get_noise_2d(float(wx), 0.0)
	var norm_val: float = (biome_val + 1.0) / 2.0
	var temperature: float = biome_temp_noise.get_noise_2d(float(wx), 0.0)
	return surface_biome_registry.get_surface_biome(norm_val, temperature)


## Get tile type for positions in the surface zone (between surface height and y=0).
func _get_surface_tile_at(wx: int, wy: int, surface_h: int) -> int:
	var biome: SurfaceBiomeData = _get_surface_biome_at(wx)
	var depth_below_surface: int = wy - surface_h

	# Top surface layer: 2 tiles of surface material
	if depth_below_surface <= 1:
		return biome.surface_tile

	# Subsurface layer
	if depth_below_surface <= 1 + biome.subsurface_depth:
		return biome.subsurface_tile

	# Deep subsurface: transition stone, solid (no caves near surface)
	return TileDatabase.TileType.STONE


## Get the base tile for a position within a specific biome.
func _get_base_tile_for_biome(wx: int, wy: int, depth: int, biome: BiomeData) -> int:
	if biome.use_depth_palette:
		return _get_base_tile_for_depth(wx, wy, depth)
	# Mix primary and secondary tiles using boundary noise for variety
	var variety: float = boundary_noise.get_noise_2d(wx, wy)
	var normalized: float = (variety + 1.0) / 2.0
	if normalized < biome.secondary_ratio:
		return biome.secondary_tile
	return biome.primary_tile


## Check for ores using biome-specific rules.
func _check_for_ore_in_biome(wx: int, wy: int, depth: int, biome: BiomeData) -> int:
	for rule in biome.ore_rules:
		if depth < rule["min_depth"]:
			continue
		var noise_idx: int = rule["noise_index"]
		if noise_idx < 0 or noise_idx >= ore_noises.size():
			continue
		var val: float = ore_noises[noise_idx].get_noise_2d(wx, wy)
		if val > rule["threshold"]:
			return rule["tile_type"]
	# If biome doesn't suppress base ores, check them too
	if not biome.exclusive_ores:
		return _check_for_ore(wx, wy, depth)
	return TileDatabase.TileType.EMPTY


## Get the base tile type for a given depth. Boundary noise warps the
## depth thresholds so biome edges are jagged and irregular, not straight lines.
func _get_base_tile_for_depth(wx: int, wy: int, depth: int) -> int:
	# Noise-based boundary warp: shifts the effective depth ±30 tiles per boundary
	# This makes biome edges snake up and down naturally
	var warp: float = boundary_noise.get_noise_2d(wx, wy) * 30.0

	# Each boundary center + warp. You're in one biome or the other, no blending.
	if depth < 60 + warp:
		return TileDatabase.TileType.DIRT
	elif depth < 160 + warp:
		return TileDatabase.TileType.STONE
	elif depth < 350 + warp:
		return TileDatabase.TileType.HARD_STONE
	else:
		return TileDatabase.TileType.DEEP_ROCK


## Check if an ore should spawn at this position based on depth and noise.
## Used as fallback for biomes with exclusive_ores = false.
func _check_for_ore(wx: int, wy: int, depth: int) -> int:
	# Iron: appears below depth 20, common
	if depth >= 20:
		var iron_val: float = ore_noises[0].get_noise_2d(wx, wy)
		if iron_val > 0.6:
			return TileDatabase.TileType.IRON_ORE

	# Copper: appears below depth 40
	if depth >= 40:
		var copper_val: float = ore_noises[1].get_noise_2d(wx, wy)
		if copper_val > 0.65:
			return TileDatabase.TileType.COPPER_ORE

	# Gold: appears below depth 150, rare
	if depth >= 150:
		var gold_val: float = ore_noises[2].get_noise_2d(wx, wy)
		if gold_val > 0.75:
			return TileDatabase.TileType.GOLD_ORE

	# Crystal: appears below depth 300, very rare
	if depth >= 300:
		var crystal_val: float = ore_noises[3].get_noise_2d(wx, wy)
		if crystal_val > 0.8:
			return TileDatabase.TileType.CRYSTAL

	return TileDatabase.TileType.EMPTY


## Deterministic pseudo-random value from a world position.
## Returns a float in range [0, 1). Same position + same seed = same result.
func _hash_position(x: int, y: int) -> float:
	var h: int = hash(Vector2i(x, y) * seed_value)
	return absf(float(h) / float(2147483647))  # Normalize to 0-1
