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


func _register_all_biomes() -> void:
	# --- 1. Forest / Plains (default - green, gentle hills) ---
	default_biome = _create_biome(&"forest", "Forest",
		0.0, 0.30, -0.5, 0.5, 0,
		-8.0, 5.0, 2.0,
		TileDatabase.TileType.GRASS, TileDatabase.TileType.DIRT, 5)
	default_biome.vegetation_density = 0.6
	biomes.append(default_biome)

	# --- 2. Desert (flat, sandy, warm only) ---
	var desert := _create_biome(&"desert", "Desert",
		0.30, 0.45, 0.15, 1.0, 0,
		-5.0, 3.0, 1.0,
		TileDatabase.TileType.SAND, TileDatabase.TileType.SANDSTONE, 8)
	biomes.append(desert)

	# --- 3. Swamp (low, wet, temperate) ---
	var swamp := _create_biome(&"swamp", "Swamp",
		0.45, 0.55, -0.3, 0.4, 0,
		-3.0, 2.0, 1.0,
		TileDatabase.TileType.MUD, TileDatabase.TileType.CLAY, 4)
	swamp.vegetation_density = 0.4
	biomes.append(swamp)

	# --- 4. Mountains (high, dramatic, any temp) ---
	var mountains := _create_biome(&"mountains", "Mountains",
		0.55, 0.70, -0.5, 0.5, 0,
		-30.0, 25.0, 3.0,
		TileDatabase.TileType.STONE, TileDatabase.TileType.STONE, 3)
	mountains.vegetation_density = 0.1
	biomes.append(mountains)

	# --- 5. Snowy Peaks (very high, cold only) ---
	var snow := _create_biome(&"snowy_peaks", "Snowy Peaks",
		0.70, 0.82, -1.0, -0.15, 0,
		-25.0, 20.0, 2.0,
		TileDatabase.TileType.SNOW, TileDatabase.TileType.FROZEN_STONE, 4)
	snow.vegetation_density = 0.0
	biomes.append(snow)

	# --- 6. Beach / Coast (low, near water) ---
	var beach := _create_biome(&"beach", "Beach",
		0.82, 0.92, -0.5, 0.5, 0,
		-2.0, 2.0, 1.0,
		TileDatabase.TileType.SAND, TileDatabase.TileType.SAND, 6)
	biomes.append(beach)

	# --- 7. Ocean (below sea level, always submerged) ---
	var ocean := _create_biome(&"ocean", "Ocean",
		0.92, 1.0, -0.5, 0.5, 0,
		0.0, 1.0, 0.5,
		TileDatabase.TileType.SAND, TileDatabase.TileType.SAND, 4)
	biomes.append(ocean)


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
