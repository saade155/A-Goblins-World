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

## Ridged noise -- adds jagged peaks to mountain/snowy_peaks biomes.
var _ridged_noise: FastNoiseLite

## Surface biome registry with all registered surface biomes.
var surface_biome_registry: SurfaceBiomeRegistry

## Sea level Y coordinate. Terrain below this gets filled with water.
const SEA_LEVEL: int = -5

## Macro cell step size for biome map sampling. Biomes are sampled every
## MACRO_STEP tiles and looked up per macro cell for performance.
const MACRO_STEP: int = 8

## Base number of worms for a small (2400x1000) world. Scaled by area ratio.
const WORMS_BASE_COUNT: int = 45

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

## Voronoi biome ownership: underground biomes assigned via seed-based Voronoi
## with domain warping. Seeds placed near surface under each biome zone so they
## naturally win shallow territory. Standard_caverns gets a distance bonus.

## Voronoi biome region map. Maps Vector2i(macro_x, macro_y) -> biome_id (StringName).
## Pre-computed from biome seeds placed under each surface biome zone.
var _biome_region_map: Dictionary = {}

## Biome seed positions used for Voronoi assignment.
var _biome_seeds: Array[Dictionary] = []

## Pre-computed surface biome layout for finite worlds.
var _surface_layout: SurfaceBiomeLayout

## Depth below surface before caves can appear.
const MIN_CAVE_DEPTH: int = 8

## Tiles over which cave density ramps from 0 to full.
const CAVE_RAMP_DEPTH: int = 30

## Global cave pocket threshold for cave_noise layer.
const CAVE_POCKET_THRESHOLD: float = -0.75


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

	# Ridged noise - jagged peaks for mountain biomes
	_ridged_noise = FastNoiseLite.new()
	_ridged_noise.seed = seed_value + 777
	_ridged_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridged_noise.frequency = 0.015


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

## Build a structured surface biome layout from a WorldDefinition.
## Returns a SurfaceBiomeLayout with per-column biome assignments and blend factors.
func _build_surface_layout(definition: WorldDefinition, world_width: int) -> SurfaceBiomeLayout:
	var layout := SurfaceBiomeLayout.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7000

	# --- Step 1: Determine zone order ---
	var zone_order: Array[StringName] = _resolve_zone_order(definition, rng)

	# --- Step 2: Size each zone ---
	var zone_widths: Array[int] = _size_zones(zone_order, world_width, rng)

	# --- Step 3: Fill per-column arrays ---
	layout.biome_ids.resize(world_width)
	layout.blend_biome_ids.resize(world_width)
	layout.blend_factors.resize(world_width)
	layout.zone_boundaries.resize(zone_order.size())
	layout.zone_biome_ids = zone_order.duplicate()

	var col: int = 0
	for zone_idx in range(zone_order.size()):
		var biome_id: StringName = zone_order[zone_idx]
		var width: int = zone_widths[zone_idx]
		layout.zone_boundaries[zone_idx] = col

		for x in range(width):
			var wx: int = col + x
			if wx >= world_width:
				break
			layout.biome_ids[wx] = biome_id
			layout.blend_biome_ids[wx] = &""
			layout.blend_factors[wx] = 0.0
		col += width

	# Fill any remaining columns with the last zone's biome
	var last_biome: StringName = zone_order[zone_order.size() - 1]
	while col < world_width:
		layout.biome_ids[col] = last_biome
		layout.blend_biome_ids[col] = &""
		layout.blend_factors[col] = 0.0
		col += 1

	# --- Step 4: Compute blend factors at zone boundaries ---
	_compute_blend_factors(layout, zone_order, world_width)

	# --- Step 5: Determine spawn X ---
	# Find the spawn zone and place spawn at its center
	for zone_idx in range(zone_order.size()):
		if zone_order[zone_idx] == definition.spawn_biome:
			var zone_start: int = layout.zone_boundaries[zone_idx]
			var zone_width: int = zone_widths[zone_idx]
			layout.spawn_x = zone_start + zone_width / 2
			break

	return layout


## Resolve the zone order from a WorldDefinition using adjacency rules.
## Returns an array of biome IDs in left-to-right order.
func _resolve_zone_order(definition: WorldDefinition, rng: RandomNumberGenerator) -> Array[StringName]:
	var order: Array[StringName] = []

	# Pin edge biomes on the left side
	for edge_biome in definition.edge_biomes:
		order.append(edge_biome)

	# Determine inner biomes (pool minus edges)
	var inner_biomes: Array[StringName] = []
	var edge_set: Dictionary = {}
	for eb in definition.edge_biomes:
		edge_set[eb] = true
	for biome_id in definition.biome_pool:
		if not edge_set.has(biome_id):
			inner_biomes.append(biome_id)

	# Remove spawn biome from inner list — it gets placed explicitly
	var spawn_idx_in_inner: int = inner_biomes.find(definition.spawn_biome)
	if spawn_idx_in_inner >= 0:
		inner_biomes.remove_at(spawn_idx_in_inner)

	var inner_count: int = inner_biomes.size() + 1  # +1 for spawn biome
	# Pick spawn position within allowed range
	var spawn_pos: int = rng.randi_range(definition.spawn_position_range.x,
		definition.spawn_position_range.y)
	spawn_pos = clampi(spawn_pos, 0, inner_count - 1)

	# Enumerate valid permutations of the remaining inner biomes
	var remaining: Array[StringName] = inner_biomes.duplicate()
	var valid_arrangements: Array = _find_valid_arrangements(
		remaining, spawn_pos, inner_count, definition)

	if valid_arrangements.is_empty():
		# Fallback: just use the biomes in pool order
		var fallback_inner: Array[StringName] = []
		for biome_id in definition.biome_pool:
			if not edge_set.has(biome_id):
				fallback_inner.append(biome_id)
		for biome_id in fallback_inner:
			order.append(biome_id)
	else:
		# Pick a valid arrangement deterministically
		var pick: int = rng.randi_range(0, valid_arrangements.size() - 1)
		var chosen: Array = valid_arrangements[pick]
		for biome_id in chosen:
			order.append(biome_id)

	# Pin edge biomes on the right side (reversed)
	var right_edges: Array[StringName] = definition.edge_biomes.duplicate()
	right_edges.reverse()
	for edge_biome in right_edges:
		order.append(edge_biome)

	# 50% chance to mirror the inner zones
	if rng.randi_range(0, 1) == 1:
		var left_edge_count: int = definition.edge_biomes.size()
		var right_edge_count: int = left_edge_count
		var inner_start: int = left_edge_count
		var inner_end: int = order.size() - right_edge_count - 1
		# Reverse just the inner portion
		var inner_section: Array[StringName] = []
		for i in range(inner_start, inner_end + 1):
			inner_section.append(order[i])
		inner_section.reverse()
		for i in range(inner_section.size()):
			order[inner_start + i] = inner_section[i]

	return order


## Find all valid arrangements of inner biomes respecting adjacency rules.
## spawn_biome is fixed at spawn_pos. Returns array of arrays.
func _find_valid_arrangements(remaining: Array[StringName], spawn_pos: int,
		inner_count: int, definition: WorldDefinition) -> Array:
	var results: Array = []
	var slots: Array[StringName] = []
	slots.resize(inner_count)
	for i in range(inner_count):
		slots[i] = &""
	slots[spawn_pos] = definition.spawn_biome

	_permute_inner(slots, remaining, 0, spawn_pos, definition, results)

	# Cap results to avoid excessive memory if somehow many valid arrangements exist
	if results.size() > 100:
		results.resize(100)

	return results


## Recursive backtracking to find valid inner biome permutations.
func _permute_inner(slots: Array[StringName], remaining: Array[StringName],
		slot_idx: int, spawn_pos: int, definition: WorldDefinition,
		results: Array) -> void:
	# Skip the spawn slot (already filled)
	if slot_idx == spawn_pos:
		_permute_inner(slots, remaining, slot_idx + 1, spawn_pos, definition, results)
		return

	# Base case: all slots filled
	if slot_idx >= slots.size():
		results.append(slots.duplicate())
		return

	# Try each remaining biome in this slot
	for i in range(remaining.size()):
		var biome_id: StringName = remaining[i]

		# Check adjacency with left neighbor
		if slot_idx > 0:
			var left: StringName = slots[slot_idx - 1]
			if not _is_adjacent_allowed(left, biome_id, definition):
				continue

		# Check adjacency with left edge biome (for first inner slot)
		if slot_idx == 0:
			if not definition.edge_biomes.is_empty():
				var left_edge: StringName = definition.edge_biomes[definition.edge_biomes.size() - 1]
				if not _is_adjacent_allowed(left_edge, biome_id, definition):
					continue

		# If this is the last inner slot, also check adjacency with right edge biome
		if slot_idx == slots.size() - 1:
			# The right neighbor will be the first right edge biome (reversed edges)
			var right_edges: Array[StringName] = definition.edge_biomes.duplicate()
			right_edges.reverse()
			if not right_edges.is_empty():
				if not _is_adjacent_allowed(biome_id, right_edges[0], definition):
					continue

		# Place and recurse
		slots[slot_idx] = biome_id
		var next_remaining: Array[StringName] = remaining.duplicate()
		next_remaining.remove_at(i)
		_permute_inner(slots, next_remaining, slot_idx + 1, spawn_pos, definition, results)

	# Also check left adjacency of spawn biome with its left neighbor when we reach it
	# (handled naturally since spawn slot is pre-filled and skipped)


## Check if two biomes are allowed to be adjacent per definition rules.
func _is_adjacent_allowed(left: StringName, right: StringName,
		definition: WorldDefinition) -> bool:
	if not definition.adjacency_rules.has(left):
		return true  # No rules = allow anything
	var allowed: Array = definition.adjacency_rules[left]
	if not allowed.has(right):
		return false
	# Also check the reverse direction
	if not definition.adjacency_rules.has(right):
		return true
	var allowed_reverse: Array = definition.adjacency_rules[right]
	return allowed_reverse.has(left)


## Size each zone within its biome's min/max width constraints.
func _size_zones(zone_order: Array[StringName], world_width: int,
		rng: RandomNumberGenerator) -> Array[int]:
	var widths: Array[int] = []
	var min_total: int = 0
	var biome_datas: Array[SurfaceBiomeData] = []

	for biome_id in zone_order:
		var biome: SurfaceBiomeData = surface_biome_registry.get_biome_by_id(biome_id)
		biome_datas.append(biome)
		var min_w: int = maxi(1, int(biome.min_width_pct * world_width))
		widths.append(min_w)
		min_total += min_w

	# Distribute remaining width proportionally up to max
	var remaining_width: int = world_width - min_total
	if remaining_width > 0:
		# Calculate how much each zone can grow
		var growth_room: Array[int] = []
		var total_growth: int = 0
		for i in range(zone_order.size()):
			var max_w: int = int(biome_datas[i].max_width_pct * world_width)
			var room: int = maxi(0, max_w - widths[i])
			growth_room.append(room)
			total_growth += room

		if total_growth > 0:
			# Distribute proportionally with noise jitter
			for i in range(zone_order.size()):
				if growth_room[i] <= 0:
					continue
				var proportion: float = float(growth_room[i]) / float(total_growth)
				var base_growth: int = int(proportion * remaining_width)
				# Add noise jitter (±20% of growth)
				var jitter: int = rng.randi_range(-base_growth / 5, base_growth / 5)
				var growth: int = clampi(base_growth + jitter, 0, growth_room[i])
				growth = mini(growth, remaining_width)
				widths[i] += growth
				remaining_width -= growth
				if remaining_width <= 0:
					break

		# Any remaining pixels go to the spawn zone or the largest zone
		if remaining_width > 0:
			# Find the largest zone and give it the remainder
			var largest_idx: int = 0
			for i in range(1, widths.size()):
				if widths[i] > widths[largest_idx]:
					largest_idx = i
			widths[largest_idx] += remaining_width

	return widths


## Compute horizontal blend factors at zone boundaries.
func _compute_blend_factors(layout: SurfaceBiomeLayout,
		zone_order: Array[StringName], world_width: int) -> void:
	for zone_idx in range(zone_order.size() - 1):
		var current_biome: StringName = zone_order[zone_idx]
		var next_biome: StringName = zone_order[zone_idx + 1]
		var boundary_x: int = layout.zone_boundaries[zone_idx + 1] if zone_idx + 1 < layout.zone_boundaries.size() else world_width

		# Get transition width from the current biome
		var biome: SurfaceBiomeData = surface_biome_registry.get_biome_by_id(current_biome)
		var tw: int = biome.transition_width

		# Set blend factors for tiles near the boundary
		# Left side of boundary (current biome blending toward next)
		for offset in range(1, tw + 1):
			var wx: int = boundary_x - offset
			if wx < 0 or wx >= world_width:
				continue
			var factor: float = float(offset) / float(tw)
			# Only set if this column belongs to the current biome
			if layout.biome_ids[wx] == current_biome:
				layout.blend_factors[wx] = 1.0 - factor
				layout.blend_biome_ids[wx] = next_biome

		# Right side of boundary (next biome blending toward current)
		var next_biome_data: SurfaceBiomeData = surface_biome_registry.get_biome_by_id(next_biome)
		var tw_right: int = next_biome_data.transition_width
		for offset in range(0, tw_right):
			var wx: int = boundary_x + offset
			if wx < 0 or wx >= world_width:
				continue
			var factor: float = float(tw_right - offset) / float(tw_right)
			if layout.biome_ids[wx] == next_biome:
				layout.blend_factors[wx] = factor
				layout.blend_biome_ids[wx] = current_biome


## Pre-generate the entire finite world. Populates world_data.tiles directly.
## Call from a background thread; poll generation_complete from the main thread.
func generate_world(world_data: WorldData, definition: WorldDefinition = null) -> void:
	generation_complete = false
	generation_progress = 0

	_scale_noise_for_world_size(world_data.world_width)

	var w: int = world_data.world_width
	var h: int = world_data.world_height
	var sr: int = world_data.surface_rows
	var underground_depth: int = h - sr  # rows below y=0

	generation_total = w * h

	# Phase 0: Build structured surface layout (if definition provided)
	if definition != null:
		_surface_layout = _build_surface_layout(definition, w)
	else:
		_surface_layout = null

	# Phase 1: Pre-compute underground biome regions (Voronoi seeds)
	_generate_biome_regions(w, h, sr)

	# Phase 2: Generate every tile
	for wx in range(w):
		for wy in range(-sr, underground_depth):
			var tile: int = _get_tile_at_finite(wx, wy, world_data)
			if tile != 0:  # Not EMPTY
				world_data.tiles[Vector2i(wx, wy)] = tile
			generation_progress += 1

	# Phase 2.25: Carve cavern rooms and tunnel network
	_generate_cavern_network(world_data)

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
## Uses depth-relative zones: sky -> surface -> subsurface -> underground.
## Underground uses blended cave thresholds between biomes at boundaries.
func _get_tile_at_finite(wx: int, wy: int, _world_data: WorldData) -> int:
	var surface_h: int = _get_surface_height(wx)

	# --- Sky zone (above surface) ---
	if wy < surface_h:
		var s_biome: SurfaceBiomeData = _get_surface_biome_at(wx)
		if s_biome.allows_water and surface_h > SEA_LEVEL and wy >= SEA_LEVEL:
			return TileDatabase.TileType.WATER
		return TileDatabase.TileType.EMPTY

	var depth_below_surface: int = wy - surface_h

	# --- Determine surface biome (with horizontal blend) ---
	var surface_biome: SurfaceBiomeData = _get_blended_surface_biome(wx, wy)

	# --- Surface layer (top 2 tiles) ---
	if depth_below_surface <= 1:
		return surface_biome.surface_tile

	# --- Subsurface layer ---
	if depth_below_surface <= 1 + surface_biome.subsurface_depth:
		return surface_biome.subsurface_tile

	# --- Transition zone: blend subsurface into underground ---
	var transition_depth: int = 12
	var subsurface_end: int = 1 + surface_biome.subsurface_depth
	if depth_below_surface <= subsurface_end + transition_depth:
		var blend_progress: float = float(depth_below_surface - subsurface_end) / float(transition_depth)
		# Probability of using underground tile increases with depth
		if _hash_position(wx, wy) > blend_progress:
			return surface_biome.subsurface_tile

	# --- Underground (depth-relative, no Y=0 boundary) ---
	return _generate_underground_tile_blended(wx, wy, depth_below_surface, surface_biome)


## Get the surface biome at a position, applying horizontal blend probability.
## At biome boundaries, probabilistically returns the neighbor biome instead.
func _get_blended_surface_biome(wx: int, wy: int) -> SurfaceBiomeData:
	if _surface_layout == null:
		return _get_surface_biome_at(wx)

	var primary: SurfaceBiomeData = surface_biome_registry.get_biome_by_id(
		_surface_layout.get_biome_id(wx))
	var blend_factor: float = _surface_layout.get_blend_factor(wx)

	if blend_factor > 0.0:
		var blend_id: StringName = _surface_layout.get_blend_biome_id(wx)
		if blend_id != &"":
			# Noise-modulated blend for organic jaggedness
			var noise_mod: float = surface_detail_noise.get_noise_2d(float(wx), float(wy)) * 0.3
			var blend_chance: float = clampf(blend_factor + noise_mod, 0.0, 1.0)
			if _hash_position(wx, wy) < blend_chance:
				return surface_biome_registry.get_biome_by_id(blend_id)

	return primary


## Generate an underground tile using blended cave thresholds.
## Replaces the old Y=0 boundary with depth-relative zones.
func _generate_underground_tile_blended(wx: int, wy: int,
		depth_below_surface: int, surface_biome: SurfaceBiomeData) -> int:
	var ug_biome: BiomeData = _get_biome_for_tile(wx, wy)

	# --- Depth ramp: no caves near surface, ramping up ---
	var cave_depth: int = depth_below_surface - (1 + surface_biome.subsurface_depth)
	var depth_factor: float = clampf(float(cave_depth - MIN_CAVE_DEPTH) / float(CAVE_RAMP_DEPTH), 0.0, 1.0)

	# --- Get universal noise values ---
	var base_val: float = base_noise.get_noise_2d(float(wx), float(wy))
	var cave_val: float = cave_noise.get_noise_2d(float(wx), float(wy))

	# --- Cave threshold from biome ---
	var effective_threshold: float = ug_biome.cave_threshold

	# Apply depth ramp
	effective_threshold *= depth_factor

	# --- Determine solid or cave ---
	var is_cave: bool = base_val > effective_threshold or cave_val < CAVE_POCKET_THRESHOLD
	if depth_factor <= 0.0:
		is_cave = false

	if is_cave:
		return TileDatabase.TileType.EMPTY

	# --- Solid: determine tile type from biome ---
	var base_tile: int = _get_base_tile_for_biome(wx, wy, wy, ug_biome)

	# --- Check for ores ---
	var ore: int = _check_for_ore_in_biome(wx, wy, wy, ug_biome)
	if ore != TileDatabase.TileType.EMPTY:
		return ore

	return base_tile


# ===========================================================================
#  Biome lookup (Voronoi region map)
# ===========================================================================

## Look up the biome for a tile position using Voronoi region map.
## Falls back to noise-based lookup if no surface layout exists.
func _get_biome_for_tile(wx: int, wy: int) -> BiomeData:
	if _surface_layout == null:
		return _get_biome_at(wx, wy)
	return _get_column_biome(wx, wy)


## Determine the underground biome at a position.
## Uses ONLY the pre-computed Voronoi region map (no forced shallow zone).
## Seeds are placed near the surface so the correct biome wins naturally.
func _get_column_biome(wx: int, wy: int) -> BiomeData:
	var surface_h: int = _get_surface_height(wx)
	var depth: int = maxi(0, wy - surface_h)

	# Look up from pre-computed Voronoi region map
	@warning_ignore("integer_division")
	var macro_key := Vector2i(wx / MACRO_STEP, depth / MACRO_STEP)
	if _biome_region_map.has(macro_key):
		return biome_registry.get_biome_by_id(_biome_region_map[macro_key])

	# Fallback
	return biome_registry.get_biome_by_id(&"standard_caverns")


## Pre-compute underground biome regions using seed-based Voronoi.
## Each surface biome zone (except ocean/beach) seeds a paired underground
## biome near the surface so it naturally wins shallow territory. Deep biomes
## (crystal, fungal, volcanic) get independent seeds. Standard_caverns gets
## a distance bonus to fill background territory. Organic biomes get tendril
## extensions for sprawling shapes.
@warning_ignore("integer_division")
func _generate_biome_regions(world_width: int, world_height: int, surface_rows: int) -> void:
	_biome_seeds.clear()
	_biome_region_map.clear()
	var underground_depth: int = world_height - surface_rows
	var macro_w: int = ceili(float(world_width) / MACRO_STEP)
	var macro_h: int = ceili(float(underground_depth) / MACRO_STEP)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 888

	# --- Phase 1: Place seeds from surface biome zones ---
	# Skip ocean and beach — they only have shallow sandy influence
	var skip_biomes: Array[StringName] = [&"ocean", &"beach"]
	var mountain_center_x: int = -1
	var swamp_center_x: int = -1

	if _surface_layout != null and _surface_layout.zone_boundaries.size() > 0:
		var zones: PackedInt32Array = _surface_layout.zone_boundaries
		var zone_ids: Array[StringName] = _surface_layout.zone_biome_ids
		for i in range(zone_ids.size()):
			var zone_start: int = zones[i]
			var zone_end: int = zones[i + 1] if i + 1 < zones.size() else world_width
			var zone_center_x: int = (zone_start + zone_end) / 2
			var biome_id: StringName = zone_ids[i]

			# Track mountain and swamp positions for deep biome placement
			if biome_id == &"mountains" or biome_id == &"snowy_peaks":
				mountain_center_x = zone_center_x
			if biome_id == &"swamp":
				swamp_center_x = zone_center_x

			# Skip ocean/beach — no deep underground seeds
			if biome_id in skip_biomes:
				continue

			var s_biome: SurfaceBiomeData = surface_biome_registry.get_biome_by_id(biome_id)
			var paired_id: StringName = s_biome.paired_underground_biome
			if paired_id == &"":
				paired_id = &"standard_caverns"

			# Place seed near surface so it naturally wins shallow area
			var seed_depth: int = int(float(underground_depth) * rng.randf_range(0.15, 0.25))
			_biome_seeds.append({
				"pos": Vector2(float(zone_center_x), float(seed_depth)),
				"id": paired_id,
				"weight": 1.0
			})

	# --- Phase 2: Place deep biome seeds ---
	# Volcanic: bottom of world, centered
	var volcanic_x: float = float(world_width) * rng.randf_range(0.35, 0.65)
	var volcanic_y: float = float(underground_depth) * 0.82
	_biome_seeds.append({"pos": Vector2(volcanic_x, volcanic_y), "id": &"volcanic_depths", "weight": 2.0})

	# Crystal: placed near/under mountains if they exist
	var crystal_x: float
	if mountain_center_x >= 0:
		crystal_x = float(mountain_center_x) + rng.randf_range(-80.0, 80.0)
	else:
		crystal_x = float(world_width) * rng.randf_range(0.25, 0.45)
	var crystal_y: float = float(underground_depth) * rng.randf_range(0.40, 0.55)
	_biome_seeds.append({"pos": Vector2(crystal_x, crystal_y), "id": &"crystal_caverns", "weight": 2.0})

	# Fungal: placed near/under swamp if it exists
	var fungal_x: float
	if swamp_center_x >= 0:
		fungal_x = float(swamp_center_x) + rng.randf_range(-60.0, 60.0)
	else:
		fungal_x = float(world_width) * rng.randf_range(0.55, 0.75)
	var fungal_y: float = float(underground_depth) * rng.randf_range(0.35, 0.50)
	_biome_seeds.append({"pos": Vector2(fungal_x, fungal_y), "id": &"fungal_grove", "weight": 2.0})

	# --- Phase 3: Voronoi assignment for all macro cells ---
	for mx in range(macro_w):
		for my in range(macro_h):
			var world_x: float = float(mx * MACRO_STEP + MACRO_STEP / 2)
			var world_y: float = float(my * MACRO_STEP + MACRO_STEP / 2)
			# Domain warp for organic boundaries
			var warp_x: float = boundary_noise.get_noise_2d(world_x * 0.8, world_y * 0.8) * 80.0
			var warp_y: float = boundary_noise.get_noise_2d(world_x * 0.8 + 5000.0, world_y * 0.8 + 5000.0) * 80.0
			var warped_x: float = world_x + warp_x
			var warped_y: float = world_y + warp_y

			# Find nearest seed (anisotropic: Y scaled for tall blobs)
			var nearest_id: StringName = &"standard_caverns"
			var nearest_dist: float = INF
			for seed_data in _biome_seeds:
				var dx: float = warped_x - seed_data.pos.x
				var dy: float = (warped_y - seed_data.pos.y) * 2.0  # Stretch Y = tall blobs
				var dist_sq: float = dx * dx + dy * dy
				# Standard caverns gets distance bonus (wins more territory)
				if seed_data.id == &"standard_caverns":
					dist_sq *= 0.65
				dist_sq *= seed_data.weight
				if dist_sq < nearest_dist:
					nearest_dist = dist_sq
					nearest_id = seed_data.id
			_biome_region_map[Vector2i(mx, my)] = nearest_id

	# --- Phase 4: Paint tendrils for organic biomes ---
	_paint_tendrils(rng, macro_w, macro_h)


## Paint tendril extensions for organic biomes (swamp, fungal, volcanic).
## Tendrils are drunk-walk paths that override Voronoi cells, creating
## finger-like extensions reaching out from the biome's main body.
func _paint_tendrils(rng: RandomNumberGenerator, macro_w: int, macro_h: int) -> void:
	for seed_data in _biome_seeds:
		var tendril_biomes: Array[StringName] = [
			&"swamp_depths", &"fungal_grove", &"volcanic_depths"
		]
		if seed_data.id not in tendril_biomes:
			continue

		@warning_ignore("integer_division")
		var seed_mx: float = seed_data.pos.x / float(MACRO_STEP)
		@warning_ignore("integer_division")
		var seed_my: float = seed_data.pos.y / float(MACRO_STEP)

		var tendril_count: int = rng.randi_range(2, 4)
		for _t in range(tendril_count):
			var pos := Vector2(seed_mx, seed_my)
			var angle: float = rng.randf_range(0.0, TAU)
			var length: int = rng.randi_range(12, 25)
			var width: float = rng.randf_range(1.0, 2.5)

			for _step in range(length):
				angle += rng.randf_range(-0.4, 0.4)
				pos.x += cos(angle) * 1.2
				pos.y += sin(angle) * 1.2

				# Paint a thick tendril (multiple cells wide)
				var r_int: int = ceili(width)
				for dx in range(-r_int, r_int + 1):
					for dy in range(-r_int, r_int + 1):
						if dx * dx + dy * dy <= int(width * width):
							var mx: int = int(pos.x) + dx
							var my: int = int(pos.y) + dy
							if mx >= 0 and mx < macro_w and my >= 0 and my < macro_h:
								_biome_region_map[Vector2i(mx, my)] = seed_data.id

				# Taper width
				width *= 0.97
				width = maxf(width, 0.5)


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
		var h: float = biome.base_height + base_val * biome.height_amplitude + detail_val * biome.detail_amplitude
		# Ridged noise adds jagged peaks to mountain biomes
		if biome.id == &"mountains" or biome.id == &"snowy_peaks":
			var ridged_val: float = _ridged_noise.get_noise_1d(float(sx))
			ridged_val = 1.0 - 2.0 * absf(ridged_val)  # Convert to ridged shape
			var ridged_amplitude: float = 25.0 if biome.id == &"mountains" else 20.0
			h -= ridged_val * ridged_amplitude  # Negative = higher terrain
		total += h
		samples += 1
	return int(total / samples)


## Public wrapper for surface height. Used by external systems.
func get_surface_height(wx: int) -> int:
	return _get_surface_height(wx)


## Get the pre-computed surface layout. Returns null if not built yet.
func get_surface_layout() -> SurfaceBiomeLayout:
	return _surface_layout


## Determine which surface biome exists at a world X position.
## Uses the precomputed layout if available, otherwise falls back to noise.
func _get_surface_biome_at(wx: int) -> SurfaceBiomeData:
	if _surface_layout != null and wx >= 0 and wx < _surface_layout.biome_ids.size():
		return surface_biome_registry.get_biome_by_id(_surface_layout.get_biome_id(wx))
	# Fallback: noise-based (legacy chunk path)
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
	if depth < 160 + warp:
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
	return float(absi(h) % 10000) / 10000.0


# ===========================================================================
#  Cavern network generation (broken spiderweb pattern)
# ===========================================================================

## Phase 2.25: Generate structured cavern rooms connected by tunnels.
## Creates a "broken spiderweb" pattern: cavern nodes connected by a
## minimum spanning tree backbone with additional pruned connections.
func _generate_cavern_network(world_data) -> void:
	var w: int = world_data.world_width
	var h: int = world_data.world_height
	var sr: int = world_data.surface_rows
	var underground_depth: int = h - sr

	# Scale cavern count by world area
	var area: float = float(w * h)
	var base_area: float = 2400.0 * 1000.0
	var base_count: int = 40
	var cavern_count: int = int(float(base_count) * (area / base_area))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9000

	# Step 1: Place cavern rooms
	var caverns: Array[Dictionary] = _place_caverns(rng, w, underground_depth, cavern_count)
	if caverns.size() < 2:
		return

	# Step 2: Build connectivity graph (nearest neighbors)
	var edges: Array[Dictionary] = _build_neighbor_graph(caverns, 5)

	# Step 3: Extract minimum spanning tree as backbone
	var mst_edges: Array[Dictionary] = _build_mst(caverns.size(), edges)

	# Step 4: Add extra connections and prune
	var final_edges: Array[Dictionary] = _prune_connections(rng, edges, mst_edges, 0.35)

	# Step 5: Carve cavern rooms
	for cavern in caverns:
		_carve_cavern_room(world_data, rng, cavern)

	# Step 6: Carve tunnels along edges
	for edge in final_edges:
		var a: Dictionary = caverns[edge.a]
		var b: Dictionary = caverns[edge.b]
		_carve_tunnel(world_data, rng, a.center, b.center)


## Place cavern room centers with minimum spacing constraint.
## Returns array of {center: Vector2i, radius: int}.
func _place_caverns(rng: RandomNumberGenerator, world_width: int,
		underground_depth: int, count: int) -> Array[Dictionary]:
	var caverns: Array[Dictionary] = []
	var min_spacing_sq: int = 50 * 50  # 50 tile minimum spacing
	var min_depth: int = 25  # No caverns too close to surface
	var max_attempts: int = count * 4

	for _attempt in range(max_attempts):
		if caverns.size() >= count:
			break

		var cx: int = rng.randi_range(20, world_width - 20)
		var cy: int = rng.randi_range(min_depth, underground_depth - 20)

		# Depth-based density: denser at mid-depth
		var depth_pct: float = float(cy) / float(underground_depth)
		# Bell curve: peaks at 40-60% depth
		var density_chance: float = 1.0 - 2.0 * absf(depth_pct - 0.5)
		density_chance = clampf(density_chance, 0.2, 1.0)
		if rng.randf() > density_chance:
			continue

		# Check minimum spacing
		var too_close: bool = false
		for existing in caverns:
			var dx: int = cx - existing.center.x
			var dy: int = cy - existing.center.y
			if dx * dx + dy * dy < min_spacing_sq:
				too_close = true
				break
		if too_close:
			continue

		# Radius varies: 8-20 tiles (diameter 16-40)
		var radius: int = rng.randi_range(8, 20)
		caverns.append({"center": Vector2i(cx, cy), "radius": radius})

	return caverns


## Build a k-nearest-neighbor graph. Returns array of {a: int, b: int, dist: float}.
func _build_neighbor_graph(caverns: Array[Dictionary], k: int) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	var edge_set: Dictionary = {}  # Dedup: "min_max" -> true

	for i in range(caverns.size()):
		# Find k nearest neighbors
		var distances: Array[Dictionary] = []
		for j in range(caverns.size()):
			if i == j:
				continue
			var dx: float = float(caverns[i].center.x - caverns[j].center.x)
			var dy: float = float(caverns[i].center.y - caverns[j].center.y)
			var dist: float = sqrt(dx * dx + dy * dy)
			distances.append({"index": j, "dist": dist})

		# Sort by distance
		distances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist < b.dist)

		# Add k nearest as edges (deduplicated)
		var added: int = 0
		for d in distances:
			if added >= k:
				break
			var edge_key: String = "%d_%d" % [mini(i, d.index), maxi(i, d.index)]
			if not edge_set.has(edge_key):
				edge_set[edge_key] = true
				edges.append({"a": i, "b": d.index, "dist": d.dist})
			added += 1

	return edges


## Build minimum spanning tree using Kruskal's algorithm with union-find.
func _build_mst(node_count: int, edges: Array[Dictionary]) -> Array[Dictionary]:
	# Sort edges by distance
	var sorted_edges: Array[Dictionary] = edges.duplicate()
	sorted_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist < b.dist)

	# Union-Find
	var parent: Array[int] = []
	var rank_arr: Array[int] = []
	for i in range(node_count):
		parent.append(i)
		rank_arr.append(0)

	var mst: Array[Dictionary] = []

	for edge in sorted_edges:
		var root_a: int = _uf_find(parent, edge.a)
		var root_b: int = _uf_find(parent, edge.b)
		if root_a != root_b:
			mst.append(edge)
			_uf_union(parent, rank_arr, root_a, root_b)
			if mst.size() == node_count - 1:
				break

	return mst


func _uf_find(parent: Array[int], x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]  # Path compression
		x = parent[x]
	return x


func _uf_union(parent: Array[int], rank_arr: Array[int], a: int, b: int) -> void:
	if rank_arr[a] < rank_arr[b]:
		parent[a] = b
	elif rank_arr[a] > rank_arr[b]:
		parent[b] = a
	else:
		parent[b] = a
		rank_arr[a] += 1


## Start with MST edges, add extra connections, then prune some extras.
func _prune_connections(rng: RandomNumberGenerator, all_edges: Array[Dictionary],
		mst_edges: Array[Dictionary], prune_ratio: float) -> Array[Dictionary]:
	# Build MST edge set for quick lookup
	var mst_set: Dictionary = {}
	for edge in mst_edges:
		var key: String = "%d_%d" % [mini(edge.a, edge.b), maxi(edge.a, edge.b)]
		mst_set[key] = true

	# Collect non-MST edges
	var extra_edges: Array[Dictionary] = []
	for edge in all_edges:
		var key: String = "%d_%d" % [mini(edge.a, edge.b), maxi(edge.a, edge.b)]
		if not mst_set.has(key):
			extra_edges.append(edge)

	# Shuffle and prune
	for i in range(extra_edges.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: Dictionary = extra_edges[i]
		extra_edges[i] = extra_edges[j]
		extra_edges[j] = temp

	var keep_count: int = int(float(extra_edges.size()) * (1.0 - prune_ratio))
	var kept_extras: Array[Dictionary] = extra_edges.slice(0, keep_count)

	# Combine MST + kept extras
	var result: Array[Dictionary] = mst_edges.duplicate()
	result.append_array(kept_extras)
	return result


## Carve a cavern room with noise-irregular edges.
func _carve_cavern_room(world_data, rng: RandomNumberGenerator, cavern: Dictionary) -> void:
	var center: Vector2i = cavern.center
	var radius: int = cavern.radius
	var r_sq: float = float(radius * radius)

	for dx in range(-radius - 2, radius + 3):
		for dy in range(-radius - 2, radius + 3):
			var dist_sq: float = float(dx * dx + dy * dy)
			# Noise-modulated boundary for irregular shape
			var wx: int = center.x + dx
			var wy: int = center.y + dy
			var noise_mod: float = base_noise.get_noise_2d(float(wx) * 2.0, float(wy) * 2.0) * float(radius) * 0.3
			if dist_sq < r_sq + noise_mod * float(radius):
				if wy > 0 and wx >= 0 and wx < world_data.world_width:
					world_data.tiles.erase(Vector2i(wx, wy))


## Carve a wobbling tunnel between two cavern centers.
## Width varies along the length for natural feel.
func _carve_tunnel(world_data, rng: RandomNumberGenerator,
		from_pos: Vector2i, to_pos: Vector2i) -> void:
	var start := Vector2(from_pos)
	var end := Vector2(to_pos)
	var dist: float = start.distance_to(end)
	var steps: int = int(dist / 1.5) + 1

	var direction: Vector2 = (end - start).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)

	for step in range(steps):
		var t: float = float(step) / float(steps)

		# Wobble perpendicular to the tunnel direction
		var wobble: float = sin(t * TAU * 3.0 + rng.randf() * 0.5) * 8.0
		var carve_pos: Vector2 = start.lerp(end, t) + perpendicular * wobble

		# Width varies: 2-5 tiles, pulsing with distance
		var width: float = 2.5 + sin(t * TAU * 2.0) * 1.5
		_carve_circle(world_data, carve_pos, width)


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
	var base_area: float = 2400.0 * 1000.0
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
