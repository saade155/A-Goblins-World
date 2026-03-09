## SurfaceBiomeRegistry - Registry of surface biomes.
##
## Owns SurfaceBiomeData instances and provides lookup by noise value + temperature.
## Surface biomes determine terrain height profile and surface tile types.

extends RefCounted
class_name SurfaceBiomeRegistry

## All registered surface biomes, sorted by priority (descending).
var biomes: Array[SurfaceBiomeData] = []

## Default surface biome returned when no other matches.
var default_biome: SurfaceBiomeData


func _init() -> void:
	_register_all_biomes()
	biomes.sort_custom(func(a: SurfaceBiomeData, b: SurfaceBiomeData) -> bool: return a.priority > b.priority)


## Find the surface biome at a given noise value and temperature.
func get_surface_biome(noise_val: float, temperature: float) -> SurfaceBiomeData:
	for biome in biomes:
		if noise_val < biome.noise_min or noise_val >= biome.noise_max:
			continue
		if temperature < biome.temp_min or temperature > biome.temp_max:
			continue
		return biome
	return default_biome


## Look up a surface biome by its string ID. Returns default_biome if not found.
func get_biome_by_id(biome_id: StringName) -> SurfaceBiomeData:
	for biome in biomes:
		if biome.id == biome_id:
			return biome
	return default_biome


func _register_all_biomes() -> void:
	# --- 1. Forest / Plains (default - green, gentle hills) ---
	default_biome = _create_biome(&"forest", "Forest",
		0.0, 0.30, -0.5, 0.5, 0,
		-8.0, 5.0, 2.0,
		TileDatabase.TileType.GRASS, TileDatabase.TileType.DIRT, 5)
	default_biome.vegetation_density = 0.6
	biomes.append(default_biome)
	default_biome.paired_underground_biome = &"standard_caverns"
	default_biome.continuity_depth = 80
	default_biome.min_width_pct = 0.18
	default_biome.max_width_pct = 0.30

	# --- 2. Desert (flat, sandy, warm only) ---
	var desert := _create_biome(&"desert", "Desert",
		0.30, 0.45, 0.15, 1.0, 0,
		-5.0, 3.0, 1.0,
		TileDatabase.TileType.SAND, TileDatabase.TileType.SANDSTONE, 8)
	desert.allows_water = false
	biomes.append(desert)
	desert.paired_underground_biome = &"sandy_hollows"
	desert.continuity_depth = 60
	desert.min_width_pct = 0.14
	desert.max_width_pct = 0.22

	# --- 3. Swamp (low, wet, temperate) ---
	var swamp := _create_biome(&"swamp", "Swamp",
		0.45, 0.55, -0.3, 0.4, 0,
		-3.0, 2.0, 1.0,
		TileDatabase.TileType.MUD, TileDatabase.TileType.CLAY, 4)
	swamp.vegetation_density = 0.4
	biomes.append(swamp)
	swamp.paired_underground_biome = &"swamp_depths"
	swamp.continuity_depth = 60
	swamp.min_width_pct = 0.12
	swamp.max_width_pct = 0.20

	# --- 4. Mountains (very high, steep, any temp) ---
	var mountains := _create_biome(&"mountains", "Mountains",
		0.55, 0.70, -0.5, 0.5, 0,
		-60.0, 50.0, 8.0,
		TileDatabase.TileType.STONE, TileDatabase.TileType.STONE, 5)
	mountains.vegetation_density = 0.1
	biomes.append(mountains)
	mountains.paired_underground_biome = &"standard_caverns"
	mountains.continuity_depth = 120
	mountains.min_width_pct = 0.14
	mountains.max_width_pct = 0.22

	# --- 5. Snowy Peaks (very high, cold only) ---
	var snow := _create_biome(&"snowy_peaks", "Snowy Peaks",
		0.70, 0.82, -1.0, -0.15, 0,
		-55.0, 45.0, 7.0,
		TileDatabase.TileType.SNOW, TileDatabase.TileType.FROZEN_STONE, 4)
	snow.vegetation_density = 0.0
	biomes.append(snow)
	snow.paired_underground_biome = &"frozen_caverns"
	snow.continuity_depth = 80
	snow.min_width_pct = 0.10
	snow.max_width_pct = 0.18

	# --- 6. Beach / Coast (gradual slope toward ocean, shallow water) ---
	var beach := _create_biome(&"beach", "Beach",
		0.82, 0.92, -0.5, 0.5, 0,
		-4.0, 2.0, 1.0,
		TileDatabase.TileType.SAND, TileDatabase.TileType.SAND, 15)
	beach.allows_water = false
	biomes.append(beach)
	beach.paired_underground_biome = &"sandy_hollows"
	beach.continuity_depth = 30
	beach.min_width_pct = 0.03
	beach.max_width_pct = 0.06
	beach.transition_width = 6

	# --- 7. Ocean (deep submerged floor with heavy water coverage) ---
	var ocean := _create_biome(&"ocean", "Ocean",
		0.92, 1.0, -0.5, 0.5, 0,
		30.0, 5.0, 2.0,
		TileDatabase.TileType.SAND, TileDatabase.TileType.SAND, 80)
	biomes.append(ocean)
	ocean.paired_underground_biome = &"sandy_hollows"
	ocean.continuity_depth = 30
	ocean.min_width_pct = 0.05
	ocean.max_width_pct = 0.10
	ocean.transition_width = 8


func _create_biome(id: StringName, biome_name: String,
		n_min: float, n_max: float, t_min: float, t_max: float,
		prio: int, base_h: float, h_amp: float, d_amp: float,
		surface: int, subsurface: int, sub_depth: int) -> SurfaceBiomeData:
	var b := SurfaceBiomeData.new()
	b.id = id
	b.name = biome_name
	b.noise_min = n_min
	b.noise_max = n_max
	b.temp_min = t_min
	b.temp_max = t_max
	b.priority = prio
	b.base_height = base_h
	b.height_amplitude = h_amp
	b.detail_amplitude = d_amp
	b.surface_tile = surface
	b.subsurface_tile = subsurface
	b.subsurface_depth = sub_depth
	return b
