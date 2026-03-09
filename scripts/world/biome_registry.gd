## BiomeRegistry - Central registry of all biomes.
##
## Owns BiomeData instances and provides lookup by cellular noise value + depth.
## Biomes are sorted by priority; first matching biome wins.
## Used by WorldGenerator to determine which biome exists at any world position.

extends RefCounted
class_name BiomeRegistry

## All registered biomes, sorted by priority (descending).
var biomes: Array[BiomeData] = []

## Default biome returned when no other biome matches.
var default_biome: BiomeData


func _init() -> void:
	_register_all_biomes()
	biomes.sort_custom(func(a: BiomeData, b: BiomeData) -> bool: return a.priority > b.priority)


## Find the biome at a given cell value, depth, and temperature.
func get_biome(cell_value: float, depth: int, temperature: float) -> BiomeData:
	var norm_cell: float = (cell_value + 1.0) / 2.0
	for biome in biomes:
		if depth < biome.depth_min or depth > biome.depth_max:
			continue
		if norm_cell < biome.cell_min or norm_cell >= biome.cell_max:
			continue
		if temperature < biome.temp_min or temperature > biome.temp_max:
			continue
		return biome
	return default_biome


## Look up a biome by its string ID. Returns default_biome if not found.
func get_biome_by_id(biome_id: StringName) -> BiomeData:
	for biome in biomes:
		if biome.id == biome_id:
			return biome
	return default_biome


func _register_all_biomes() -> void:
	# --- 1. Standard Caverns (default - reproduces existing generation) ---
	default_biome = _create_biome(&"standard_caverns", "Standard Caverns",
		0, 600, 0.0, 0.45, 0,
		TileDatabase.TileType.STONE, TileDatabase.TileType.DIRT, 0.0)
	default_biome.use_depth_palette = true
	default_biome.ore_rules = [
		{"tile_type": TileDatabase.TileType.IRON_ORE, "noise_index": 0, "threshold": 0.6, "min_depth": 20},
		{"tile_type": TileDatabase.TileType.COPPER_ORE, "noise_index": 1, "threshold": 0.65, "min_depth": 40},
		{"tile_type": TileDatabase.TileType.GOLD_ORE, "noise_index": 2, "threshold": 0.75, "min_depth": 150},
		{"tile_type": TileDatabase.TileType.CRYSTAL, "noise_index": 3, "threshold": 0.8, "min_depth": 300},
	]
	biomes.append(default_biome)

	# --- 2. Sandy Hollows ---
	var sandy := _create_biome(&"sandy_hollows", "Sandy Hollows",
		0, 120, 0.45, 0.58, 0,
		TileDatabase.TileType.SAND, TileDatabase.TileType.SANDSTONE, 0.35)
	sandy.cave_density_modifier = 0.85
	sandy.cave_threshold = 0.40
	sandy.ore_rules = [
		{"tile_type": TileDatabase.TileType.IRON_ORE, "noise_index": 0, "threshold": 0.55, "min_depth": 10},
		{"tile_type": TileDatabase.TileType.COPPER_ORE, "noise_index": 1, "threshold": 0.65, "min_depth": 30},
	]
	biomes.append(sandy)

	# --- 3. Swamp Depths ---
	var swamp := _create_biome(&"swamp_depths", "Swamp Depths",
		20, 160, 0.58, 0.68, 0,
		TileDatabase.TileType.MUD, TileDatabase.TileType.MOSSY_STONE, 0.4)
	swamp.cave_density_modifier = 0.75
	swamp.cave_threshold = 0.30
	swamp.ore_rules = [
		{"tile_type": TileDatabase.TileType.IRON_ORE, "noise_index": 0, "threshold": 0.55, "min_depth": 20},
		{"tile_type": TileDatabase.TileType.COPPER_ORE, "noise_index": 1, "threshold": 0.6, "min_depth": 30},
	]
	biomes.append(swamp)

	# --- 4. Fungal Grove ---
	var fungal := _create_biome(&"fungal_grove", "Fungal Grove",
		60, 250, 0.68, 0.78, 0,
		TileDatabase.TileType.MYCELIUM, TileDatabase.TileType.MOSSY_STONE, 0.3)
	fungal.cave_density_modifier = 0.7
	fungal.cave_threshold = 0.28
	fungal.ore_rules = [
		{"tile_type": TileDatabase.TileType.EMERALD_ORE, "noise_index": 5, "threshold": 0.7, "min_depth": 80},
		{"tile_type": TileDatabase.TileType.COPPER_ORE, "noise_index": 1, "threshold": 0.6, "min_depth": 60},
		{"tile_type": TileDatabase.TileType.CRYSTAL, "noise_index": 3, "threshold": 0.7, "min_depth": 150},
	]
	biomes.append(fungal)

	# --- 5. Frozen Caverns ---
	var frozen := _create_biome(&"frozen_caverns", "Frozen Caverns",
		80, 300, 0.78, 0.87, 0,
		TileDatabase.TileType.ICE, TileDatabase.TileType.FROZEN_STONE, 0.35)
	frozen.cave_density_modifier = 1.15
	frozen.cave_threshold = 0.42
	frozen.temp_max = -0.2
	frozen.ore_rules = [
		{"tile_type": TileDatabase.TileType.IRON_ORE, "noise_index": 0, "threshold": 0.55, "min_depth": 80},
		{"tile_type": TileDatabase.TileType.GOLD_ORE, "noise_index": 2, "threshold": 0.7, "min_depth": 120},
		{"tile_type": TileDatabase.TileType.CRYSTAL, "noise_index": 3, "threshold": 0.75, "min_depth": 200},
	]
	biomes.append(frozen)

	# --- 6. Volcanic Depths ---
	# Extended depth and cell range to fill space left by removed Abyss biome.
	var volcanic := _create_biome(&"volcanic_depths", "Volcanic Depths",
		200, 999, 0.45, 0.75, 1,
		TileDatabase.TileType.VOLCANIC_ROCK, TileDatabase.TileType.OBSIDIAN, 0.2)
	volcanic.cave_density_modifier = 1.3
	volcanic.cave_threshold = 0.60
	volcanic.ore_rules = [
		{"tile_type": TileDatabase.TileType.RUBY_ORE, "noise_index": 4, "threshold": 0.7, "min_depth": 220},
		{"tile_type": TileDatabase.TileType.GOLD_ORE, "noise_index": 2, "threshold": 0.65, "min_depth": 200},
		{"tile_type": TileDatabase.TileType.CRYSTAL, "noise_index": 3, "threshold": 0.75, "min_depth": 300},
	]
	volcanic.exclusive_ores = true
	volcanic.temp_min = 0.2
	biomes.append(volcanic)

	# --- 7. Crystal Caverns ---
	# Extended depth and cell range to fill space left by removed Abyss biome.
	var crystal := _create_biome(&"crystal_caverns", "Crystal Caverns",
		250, 999, 0.75, 0.95, 0,
		TileDatabase.TileType.HARD_STONE, TileDatabase.TileType.CRYSTAL, 0.4)
	crystal.cave_density_modifier = 1.1
	crystal.cave_threshold = 0.50
	crystal.ore_rules = [
		{"tile_type": TileDatabase.TileType.CRYSTAL, "noise_index": 3, "threshold": 0.6, "min_depth": 250},
		{"tile_type": TileDatabase.TileType.GOLD_ORE, "noise_index": 2, "threshold": 0.7, "min_depth": 250},
	]
	crystal.exclusive_ores = true
	biomes.append(crystal)


func _create_biome(id: StringName, biome_name: String,
		d_min: int, d_max: int, c_min: float, c_max: float,
		prio: int, primary: int, secondary: int,
		sec_ratio: float) -> BiomeData:
	var b := BiomeData.new()
	b.id = id
	b.name = biome_name
	b.depth_min = d_min
	b.depth_max = d_max
	b.cell_min = c_min
	b.cell_max = c_max
	b.priority = prio
	b.primary_tile = primary
	b.secondary_tile = secondary
	b.secondary_ratio = sec_ratio
	return b
