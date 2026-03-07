## WorldGenerator - Procedural world generation using FastNoiseLite.
##
## Supports two modes:
##   1. Finite pre-generation: generate_world() creates all tiles up front for
##      a bounded world. Used for new games with world size presets.
##   2. Legacy per-chunk generation: generate_chunk() generates on demand.
##      Used for backward compatibility with old saves.
##
## Depth zones (Y increases downward):
##   Above surface: empty (or water below sea level)
##   Surface zone (surface_h to 0): biome-driven surface/subsurface tiles
##   Shallow (0-80): mostly dirt, some stone, iron ore
##   Mid (80-200): stone, copper ore, gold ore at depth 150+
##   Deep (200-400): hard stone, gold ore, crystal at 300+
##   Very Deep (400+): deep rock, crystal

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

## Macro cell step size for biome map sampling. Biomes are sampled every
## MACRO_STEP tiles and looked up per macro cell for performance.
const MACRO_STEP: int = 8

## Base number of worms for a small (2400x800) world. Scaled by area ratio.
const WORMS_BASE_COUNT: int = 18

## Maximum recursion depth for branching worms.
const MAX_BRANCH_DEPTH: int = 3

## Worm archetypes with parameter ranges. Weight controls spawn frequency.
const WORM_TYPES: Array[Dictionary] = [
	{
		"name": "explorer",
		"length": [120, 300],
		"base_radius": [2.0, 4.0],
		"radius_amplitude": [1.0, 2.0],
		"radius_frequency": [0.08, 0.15],
		"angle_drift_max": [0.15, 0.30],
		"vertical_bias": [-0.1, 0.2],
		"branch_chance": [0.006, 0.015],
		"start_depth_min": 10,
		"start_depth_max": 800,
		"weight": 5,
	},
	{
		"name": "cavern",
		"length": [40, 100],
		"base_radius": [5.0, 9.0],
		"radius_amplitude": [2.0, 4.0],
		"radius_frequency": [0.05, 0.10],
		"angle_drift_max": [0.20, 0.50],
		"vertical_bias": [-0.05, 0.05],
		"branch_chance": [0.01, 0.03],
		"start_depth_min": 30,
		"start_depth_max": 600,
		"weight": 3,
	},
	{
		"name": "shaft",
		"length": [80, 200],
		"base_radius": [1.5, 3.0],
		"radius_amplitude": [0.5, 1.5],
		"radius_frequency": [0.10, 0.20],
		"angle_drift_max": [0.10, 0.20],
		"vertical_bias": [0.4, 0.8],
		"branch_chance": [0.003, 0.008],
		"start_depth_min": 5,
		"start_depth_max": 400,
		"weight": 2,
	},
]

## Whether world generation has completed (used for async polling).
var generation_complete: bool = false

## Progress counter for generation (tiles generated so far).
var generation_progress: int = 0

## Total tiles to generate (set at start of generate_world).
var generation_total: int = 0

## Pre-computed biome map for finite worlds.
## Maps Vector2i(macro_x, macro_y) -> biome_id (StringName).
var _biome_map: Dictionary = {}


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


## Scale noise frequencies for a specific world width. Bigger world = lower
## biome cell frequency = proportionally bigger biome regions.
func _scale_noise_for_world_size(world_width: int) -> void:
	var scale_factor: float = 2400.0 / float(world_width)
	# Scale biome cell noise frequency with world size
	biome_cell_noise.frequency = 0.003 * scale_factor
	# Scale surface biome noise similarly
	surface_biome_noise.frequency = 0.0008 * scale_factor
	# Surface terrain base scales slightly so landforms feel proportional
	surface_terrain_noise.frequency = 0.002 * scale_factor


# ===========================================================================
#  Finite world pre-generation
# ===========================================================================

## Pre-generate the entire finite world. Populates world_data.tiles directly.
## Call from a background thread; poll generation_complete from the main thread.
func generate_world(world_data: WorldData) -> void:
	generation_complete = false
	generation_progress = 0

	_scale_noise_for_world_size(world_data.world_width)

	var w: int = world_data.world_width
	var h: int = world_data.world_height
	var sr: int = world_data.surface_rows
	var underground_depth: int = h - sr  # rows below y=0

	generation_total = w * h

	# Phase 1: Build the biome macro-map for underground regions
	_biome_map = _generate_biome_map(w, underground_depth)

	# Phase 2: Generate every tile
	for wx in range(w):
		for wy in range(-sr, underground_depth):
			var tile: int = _get_tile_at_finite(wx, wy, world_data)
			if tile != 0:  # Not EMPTY
				world_data.tiles[Vector2i(wx, wy)] = tile
			generation_progress += 1

	# Phase 2.5: Carve worm tunnels through the generated terrain
	_generate_worm_caves(world_data)

	# Phase 3: Generate back wall tiles
	_generate_back_walls(world_data, w, sr, underground_depth)

	generation_complete = true


## Get the generation progress as a fraction 0.0 to 1.0.
func get_generation_progress() -> float:
	if generation_total <= 0:
		return 0.0
	return float(generation_progress) / float(generation_total)


## Determine what tile should exist at a finite world position.
## Uses the pre-computed biome map for underground biome lookup.
func _get_tile_at_finite(wx: int, wy: int, _world_data: WorldData) -> int:
	# Surface terrain system
	var surface_h: int = _get_surface_height(wx)

	# Above the surface
	if wy < surface_h:
		var s_biome: SurfaceBiomeData = _get_surface_biome_at(wx)
		if s_biome.allows_water and surface_h > SEA_LEVEL and wy >= SEA_LEVEL:
			return TileDatabase.TileType.WATER
		return TileDatabase.TileType.EMPTY

	# Surface zone: between the surface and underground (surface_h to y=0)
	if wy <= 0:
		return _get_surface_tile_at(wx, wy, surface_h)

	# Underground (wy > 0)
	var biome: BiomeData = _get_biome_for_tile(wx, wy)
	return _generate_underground_tile(wx, wy, biome)


## Generate tile for an underground position given its biome.
## Shared logic between finite and chunk-based generation.
func _generate_underground_tile(wx: int, wy: int, biome: BiomeData) -> int:
	var depth: int = wy

	# Get base noise value (-1 to 1)
	var base: float = base_noise.get_noise_2d(wx, wy)

	# Density threshold controls cave openness
	var density_threshold: float = 0.3 + (depth / 1500.0)
	density_threshold = clampf(density_threshold, 0.3, 0.6)
	density_threshold *= biome.cave_density_modifier

	if base > density_threshold:
		return TileDatabase.TileType.EMPTY

	# Cave carving layer
	var cave: float = cave_noise.get_noise_2d(wx, wy)
	var cave_threshold: float = -0.75
	if biome.cave_threshold_override >= 0.0:
		cave_threshold = biome.cave_threshold_override
	if cave < cave_threshold:
		return TileDatabase.TileType.EMPTY

	# Solid — determine tile type from biome
	var base_tile: int = _get_base_tile_for_biome(wx, wy, depth, biome)

	# Check for ores
	var ore: int = _check_for_ore_in_biome(wx, wy, depth, biome)
	if ore != TileDatabase.TileType.EMPTY:
		return ore

	return base_tile


# ===========================================================================
#  Biome map generation (macro-cell approach)
# ===========================================================================

## Build a macro-cell biome map for the underground portion of the world.
## Samples biome noise every MACRO_STEP tiles and stores the biome ID.
func _generate_biome_map(world_width: int, underground_depth: int) -> Dictionary:
	var biome_map: Dictionary = {}
	var biome_counts: Dictionary = {}

	var macro_w: int = ceili(float(world_width) / MACRO_STEP)
	var macro_h: int = ceili(float(underground_depth) / MACRO_STEP)

	for mx in range(macro_w):
		for my in range(macro_h):
			@warning_ignore("integer_division")
			var sample_x: int = mx * MACRO_STEP + MACRO_STEP / 2
			@warning_ignore("integer_division")
			var sample_y: int = my * MACRO_STEP + MACRO_STEP / 2
			var biome: BiomeData = _get_biome_at(sample_x, sample_y)
			var key := Vector2i(mx, my)
			biome_map[key] = biome.id
			biome_counts[biome.id] = biome_counts.get(biome.id, 0) + 1

	# Guarantee all required biomes are present
	_guarantee_all_biomes(biome_map, biome_counts, macro_w, macro_h)

	return biome_map


## Look up the biome for a tile position using the pre-computed macro-cell map.
## Falls back to noise-based lookup if the macro cell isn't in the map.
func _get_biome_for_tile(wx: int, wy: int) -> BiomeData:
	if _biome_map.is_empty():
		return _get_biome_at(wx, wy)
	var key := Vector2i(floori(float(wx) / MACRO_STEP), floori(float(wy) / MACRO_STEP))
	if _biome_map.has(key):
		return biome_registry.get_biome_by_id(_biome_map[key])
	return _get_biome_at(wx, wy)


## Ensure every required underground biome appears at least a minimum number of
## times in the macro-cell map. If any biome is missing or underrepresented,
## force-place it by overriding some standard_caverns cells.
func _guarantee_all_biomes(biome_map: Dictionary, counts: Dictionary,
		macro_w: int, macro_h: int) -> void:
	var required_biomes: Array[StringName] = [
		&"standard_caverns", &"sandy_hollows", &"swamp_depths", &"fungal_grove",
		&"frozen_caverns", &"volcanic_depths", &"crystal_caverns",
	]
	var min_cells: int = 10  # Minimum macro cells per biome

	for biome_id in required_biomes:
		if counts.get(biome_id, 0) >= min_cells:
			continue
		# Need to force-place this biome
		_force_place_biome(biome_map, counts, biome_id, macro_w, macro_h)


## Force-place a biome by converting a cluster of standard_caverns macro cells.
## Picks a random valid region and converts a block of cells.
func _force_place_biome(biome_map: Dictionary, counts: Dictionary,
		biome_id: StringName, macro_w: int, macro_h: int) -> void:
	# Find cells belonging to standard_caverns (the most common biome)
	var candidates: Array[Vector2i] = []
	for key in biome_map:
		if biome_map[key] == &"standard_caverns":
			candidates.append(key)

	if candidates.is_empty():
		return

	# Pick a deterministic pseudo-random starting point based on biome_id hash
	var start_idx: int = hash(biome_id) % candidates.size()
	if start_idx < 0:
		start_idx += candidates.size()

	# Look up the biome's depth constraints to pick a valid region
	var biome_data: BiomeData = biome_registry.get_biome_by_id(biome_id)
	var min_macro_y: int = maxi(0, biome_data.depth_min / MACRO_STEP)
	var max_macro_y: int = mini(macro_h - 1, biome_data.depth_max / MACRO_STEP)

	# Convert up to 20 cells starting from the chosen point
	var converted: int = 0
	var target: int = 20
	for i in range(candidates.size()):
		var idx: int = (start_idx + i) % candidates.size()
		var cell: Vector2i = candidates[idx]
		# Check depth range validity
		if cell.y < min_macro_y or cell.y > max_macro_y:
			continue
		biome_map[cell] = biome_id
		counts[&"standard_caverns"] = counts.get(&"standard_caverns", 0) - 1
		counts[biome_id] = counts.get(biome_id, 0) + 1
		converted += 1
		if converted >= target:
			break


## Generate all tiles for a chunk. Returns a Dictionary with:
##   "tiles": Dictionary[Vector2i, int] - foreground tiles (local pos -> TileType)
##   "back_walls": Dictionary[Vector2i, int] - back wall tiles (local pos -> TileType)
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

	var back_walls: Dictionary = _generate_chunk_back_walls(chunk_coord, tiles)
	return {"tiles": tiles, "back_walls": back_walls}


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


# ===========================================================================
#  Back wall generation
# ===========================================================================

## Generate back wall tiles for a finite world. Called after foreground tiles
## are generated. Rules:
##   - Every solid foreground tile gets a back wall of the same type.
##   - Empty foreground tiles (caves) get back wall extending 2 tiles into
##     the cave from solid walls (cardinal neighbor expansion, 2 passes).
##   - Above surface: no back wall.
func _generate_back_walls(world_data: WorldData, w: int, sr: int, underground_depth: int) -> void:
	# Pass 1: Copy all solid foreground tiles as back walls.
	# Also collect cave positions (empty tiles underground) for expansion.
	var cave_positions: Array[Vector2i] = []
	for wx in range(w):
		for wy in range(-sr, underground_depth):
			var pos := Vector2i(wx, wy)
			var surface_h: int = _get_surface_height(wx)
			# Above surface: no back wall
			if wy < surface_h:
				continue
			if world_data.tiles.has(pos):
				# Solid foreground -> same back wall
				world_data.back_wall_tiles[pos] = world_data.tiles[pos]
			else:
				# Empty tile underground -> candidate for cave extension
				cave_positions.append(pos)

	# Pass 2 & 3: Expand back walls into caves from solid neighbors.
	# Two passes, each expanding by 1 tile via cardinal neighbors.
	for _pass_num in range(2):
		for pos in cave_positions:
			if world_data.back_wall_tiles.has(pos):
				continue  # Already has a back wall
			# Check 4 cardinal neighbors for an existing back wall
			var has_neighbor: bool = false
			var neighbor_wall_type: int = 0
			for offset in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var npos: Vector2i = pos + offset
				if world_data.back_wall_tiles.has(npos):
					has_neighbor = true
					neighbor_wall_type = world_data.back_wall_tiles[npos]
					break
			if has_neighbor:
				# Use the neighbor's wall type (biome-appropriate)
				world_data.back_wall_tiles[pos] = neighbor_wall_type
		# After each pass, newly filled positions allow the next pass to expand further.
		# (The positions are already in cave_positions, and back_wall_tiles was updated.)


## Generate back wall tiles for a single chunk (legacy infinite world path).
## Takes the foreground chunk tiles and returns a Dictionary of back wall tiles
## in local coordinates (Vector2i -> int).
func _generate_chunk_back_walls(chunk_coord: Vector2i, chunk_tiles: Dictionary) -> Dictionary:
	var back_walls: Dictionary = {}
	var world_origin := chunk_coord * WorldData.CHUNK_SIZE

	# Pass 1: Every solid foreground tile gets a back wall of the same type.
	# Track empty positions for cave expansion.
	var empty_positions: Array[Vector2i] = []
	for x in range(WorldData.CHUNK_SIZE):
		for y in range(WorldData.CHUNK_SIZE):
			var local := Vector2i(x, y)
			var wx: int = world_origin.x + x
			var wy: int = world_origin.y + y
			var surface_h: int = _get_surface_height(wx)
			if wy < surface_h:
				continue  # Above surface: no back wall
			if chunk_tiles.has(local):
				back_walls[local] = chunk_tiles[local]
			else:
				empty_positions.append(local)

	# Pass 2 & 3: Expand into caves. For chunk boundaries, check foreground
	# tiles via the generator (read-only) since neighbor chunks may not exist.
	for _pass_num in range(2):
		for local in empty_positions:
			if back_walls.has(local):
				continue
			var has_neighbor: bool = false
			var neighbor_wall_type: int = 0
			for offset in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var n_local: Vector2i = local + offset
				if back_walls.has(n_local):
					has_neighbor = true
					neighbor_wall_type = back_walls[n_local]
					break
				# Check cross-chunk boundary: query the generator for the neighbor tile
				if n_local.x < 0 or n_local.x >= WorldData.CHUNK_SIZE or n_local.y < 0 or n_local.y >= WorldData.CHUNK_SIZE:
					var n_world := Vector2i(world_origin.x + n_local.x, world_origin.y + n_local.y)
					var n_tile: int = _get_tile_at(n_world.x, n_world.y)
					if n_tile != 0:  # TileType.EMPTY
						has_neighbor = true
						neighbor_wall_type = n_tile
						break
			if has_neighbor:
				back_walls[local] = neighbor_wall_type


	return back_walls


## Deterministic pseudo-random value from a world position.
## Returns a float in range [0, 1). Same position + same seed = same result.
func _hash_position(x: int, y: int) -> float:
	var h: int = hash(Vector2i(x, y) * seed_value)
	return absf(float(h) / float(2147483647))  # Normalize to 0-1


# ===========================================================================
#  Worm cave generation
# ===========================================================================

## Phase 2.5: Carve worm tunnels through the generated terrain.
func _generate_worm_caves(world_data) -> void:
	var w: int = world_data.world_width
	var h: int = world_data.world_height
	var sr: int = world_data.surface_rows
	var underground_depth: int = h - sr

	var worm_count: int = _get_worm_count(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5000

	for i in range(worm_count):
		var worm_type: Dictionary = _pick_worm_type(rng)
		var params: Dictionary = _randomize_worm_params(rng, worm_type)

		var start_x: int = rng.randi_range(0, w - 1)
		var min_y: int = maxi(1, worm_type["start_depth_min"])
		var max_y: int = mini(underground_depth - 1, worm_type["start_depth_max"])
		if min_y >= max_y:
			continue
		var start_y: int = rng.randi_range(min_y, max_y)

		_run_worm(world_data, rng, Vector2(start_x, start_y), params, 0)


func _get_worm_count(w: int, h: int) -> int:
	var area: float = float(w * h)
	var base_area: float = 2400.0 * 800.0
	return int(WORMS_BASE_COUNT * (area / base_area))


func _pick_worm_type(rng: RandomNumberGenerator) -> Dictionary:
	var total_weight: int = 0
	for wt in WORM_TYPES:
		total_weight += wt["weight"]
	var roll: int = rng.randi_range(0, total_weight - 1)
	var cumulative: int = 0
	for wt in WORM_TYPES:
		cumulative += wt["weight"]
		if roll < cumulative:
			return wt
	return WORM_TYPES[0]


func _randomize_worm_params(rng: RandomNumberGenerator, worm_type: Dictionary) -> Dictionary:
	return {
		"length": rng.randi_range(worm_type["length"][0], worm_type["length"][1]),
		"base_radius": rng.randf_range(worm_type["base_radius"][0], worm_type["base_radius"][1]),
		"radius_amplitude": rng.randf_range(worm_type["radius_amplitude"][0], worm_type["radius_amplitude"][1]),
		"radius_frequency": rng.randf_range(worm_type["radius_frequency"][0], worm_type["radius_frequency"][1]),
		"angle_drift_max": rng.randf_range(worm_type["angle_drift_max"][0], worm_type["angle_drift_max"][1]),
		"vertical_bias": rng.randf_range(worm_type["vertical_bias"][0], worm_type["vertical_bias"][1]),
		"branch_chance": rng.randf_range(worm_type["branch_chance"][0], worm_type["branch_chance"][1]),
	}


func _run_worm(world_data, rng: RandomNumberGenerator,
		start_pos: Vector2, params: Dictionary, branch_depth: int) -> void:
	var pos: Vector2 = start_pos
	var angle: float = rng.randf_range(0.0, TAU)
	angle = lerp_angle(angle, PI / 2.0, params["vertical_bias"])

	var w: int = world_data.world_width
	var underground_depth: int = world_data.world_height - world_data.surface_rows

	for step in range(params["length"]):
		var radius: float = params["base_radius"] + sin(step * params["radius_frequency"]) * params["radius_amplitude"]
		radius = maxf(radius, 1.0)
		_carve_circle(world_data, pos, radius)

		var drift: float = rng.randf_range(-params["angle_drift_max"], params["angle_drift_max"])
		angle += drift
		angle = lerp_angle(angle, PI / 2.0, params["vertical_bias"] * 0.05)

		pos.x += cos(angle) * 1.5
		pos.y += sin(angle) * 1.5

		if pos.x < 1 or pos.x >= w - 1:
			break
		if pos.y < 1 or pos.y >= underground_depth - 1:
			break

		if branch_depth < MAX_BRANCH_DEPTH and rng.randf() < params["branch_chance"]:
			var branch_params: Dictionary = params.duplicate()
			branch_params["length"] = rng.randi_range(
				int(params["length"] * 0.2),
				int(params["length"] * 0.5)
			)
			branch_params["base_radius"] *= rng.randf_range(0.5, 0.9)
			branch_params["branch_chance"] *= 0.5
			_run_worm(world_data, rng, pos, branch_params, branch_depth + 1)


func _carve_circle(world_data, center: Vector2, radius: float) -> void:
	var r_int: int = ceili(radius)
	var cx: int = int(center.x)
	var cy: int = int(center.y)
	var r_sq: float = radius * radius

	for dx in range(-r_int, r_int + 1):
		for dy in range(-r_int, r_int + 1):
			if dx * dx + dy * dy <= r_sq:
				var pos := Vector2i(cx + dx, cy + dy)
				if pos.y > 0 and pos.x >= 0 and pos.x < world_data.world_width:
					world_data.tiles.erase(pos)
