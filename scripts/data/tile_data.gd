## TileData - Registry of all tile types and their properties.
##
## This autoload provides a central lookup for tile metadata: hardness, drops,
## display color, etc. All tile-related constants and data queries go through here.
## When we add new tile types in later milestones, we only need to update this file.

extends Node

## Tile pixel size constant for reference by other systems.
const TILE_PX: int = 16

# --- Tile type enum ---
# EMPTY = no tile. Other values correspond to atlas positions in the tile atlas.
enum TileType {
	EMPTY = 0,
	DIRT = 1,
	STONE = 2,
	IRON_ORE = 3,
	HARD_STONE = 4,
	COPPER_ORE = 5,
	GOLD_ORE = 6,
	CRYSTAL = 7,
	DEEP_ROCK = 8,
	SAND = 9,
	SANDSTONE = 10,
	MUD = 11,
	MOSSY_STONE = 12,
	MYCELIUM = 13,
	VOLCANIC_ROCK = 14,
	OBSIDIAN = 15,
	ICE = 16,
	FROZEN_STONE = 17,
	RUBY_ORE = 18,
	EMERALD_ORE = 19,
	GRASS = 20,
	SNOW = 21,
	WATER = 22,
	CLAY = 23,
}

# --- Tile properties ---
# Keyed by TileType. Each entry defines how the tile behaves when mined,
# what it drops, and its placeholder color.
var tile_properties: Dictionary = {
	TileType.DIRT: {
		"name": "Dirt",
		"hardness": 1.0,
		"difficulty_level": 2,
		"drop_item": "dirt",
		"drop_count": 1,
		"color": Color(0.55, 0.35, 0.17),  # Brown
	},
	TileType.STONE: {
		"name": "Stone",
		"hardness": 2.5,
		"difficulty_level": 3,
		"drop_item": "stone",
		"drop_count": 1,
		"color": Color(0.5, 0.5, 0.5),  # Gray
	},
	TileType.IRON_ORE: {
		"name": "Iron Ore",
		"hardness": 4.0,
		"difficulty_level": 4,
		"drop_item": "iron_ore",
		"drop_count": 1,
		"color": Color(0.7, 0.5, 0.35),  # Rusty brown
	},
	TileType.HARD_STONE: {
		"name": "Hard Stone",
		"hardness": 4.0,
		"difficulty_level": 4,
		"drop_item": "hard_stone",
		"drop_count": 1,
		"color": Color(0.45, 0.48, 0.58),  # Gray-blue
	},
	TileType.COPPER_ORE: {
		"name": "Copper Ore",
		"hardness": 3.0,
		"difficulty_level": 4,
		"drop_item": "copper_ore",
		"drop_count": 1,
		"color": Color(0.7, 0.55, 0.3),  # Orange-green
	},
	TileType.GOLD_ORE: {
		"name": "Gold Ore",
		"hardness": 5.0,
		"difficulty_level": 5,
		"drop_item": "gold_ore",
		"drop_count": 1,
		"color": Color(0.85, 0.75, 0.2),  # Yellow
	},
	TileType.CRYSTAL: {
		"name": "Crystal",
		"hardness": 6.0,
		"difficulty_level": 6,
		"drop_item": "crystal",
		"drop_count": 1,
		"color": Color(0.3, 0.8, 0.75),  # Cyan/teal
	},
	TileType.DEEP_ROCK: {
		"name": "Deep Rock",
		"hardness": 8.0,
		"difficulty_level": 7,
		"drop_item": "deep_rock",
		"drop_count": 1,
		"color": Color(0.35, 0.2, 0.45),  # Dark purple
	},
	TileType.SAND: {
		"name": "Sand",
		"hardness": 0.5,
		"difficulty_level": 1,
		"drop_item": "sand",
		"drop_count": 1,
		"color": Color(0.85, 0.78, 0.55),
	},
	TileType.SANDSTONE: {
		"name": "Sandstone",
		"hardness": 1.5,
		"difficulty_level": 3,
		"drop_item": "sandstone",
		"drop_count": 1,
		"color": Color(0.78, 0.65, 0.42),
	},
	TileType.MUD: {
		"name": "Mud",
		"hardness": 0.7,
		"difficulty_level": 2,
		"drop_item": "mud",
		"drop_count": 1,
		"color": Color(0.35, 0.28, 0.18),
	},
	TileType.MOSSY_STONE: {
		"name": "Mossy Stone",
		"hardness": 2.0,
		"difficulty_level": 3,
		"drop_item": "mossy_stone",
		"drop_count": 1,
		"color": Color(0.35, 0.55, 0.30),
	},
	TileType.MYCELIUM: {
		"name": "Mycelium",
		"hardness": 1.2,
		"difficulty_level": 3,
		"drop_item": "mycelium",
		"drop_count": 1,
		"color": Color(0.60, 0.45, 0.65),
	},
	TileType.VOLCANIC_ROCK: {
		"name": "Volcanic Rock",
		"hardness": 5.0,
		"difficulty_level": 5,
		"drop_item": "volcanic_rock",
		"drop_count": 1,
		"color": Color(0.3, 0.15, 0.1),
	},
	TileType.OBSIDIAN: {
		"name": "Obsidian",
		"hardness": 10.0,
		"difficulty_level": 8,
		"drop_item": "obsidian",
		"drop_count": 1,
		"color": Color(0.1, 0.05, 0.15),
	},
	TileType.ICE: {
		"name": "Ice",
		"hardness": 1.5,
		"difficulty_level": 3,
		"drop_item": "ice",
		"drop_count": 1,
		"color": Color(0.7, 0.85, 0.95),
	},
	TileType.FROZEN_STONE: {
		"name": "Frozen Stone",
		"hardness": 3.5,
		"difficulty_level": 4,
		"drop_item": "frozen_stone",
		"drop_count": 1,
		"color": Color(0.5, 0.6, 0.75),
	},
	TileType.RUBY_ORE: {
		"name": "Ruby Ore",
		"hardness": 6.0,
		"difficulty_level": 6,
		"drop_item": "ruby_ore",
		"drop_count": 1,
		"color": Color(0.8, 0.15, 0.2),
	},
	TileType.EMERALD_ORE: {
		"name": "Emerald Ore",
		"hardness": 5.0,
		"difficulty_level": 5,
		"drop_item": "emerald_ore",
		"drop_count": 1,
		"color": Color(0.15, 0.7, 0.3),
	},
	TileType.GRASS: {
		"name": "Grass",
		"hardness": 0.8,
		"difficulty_level": 2,
		"drop_item": "grass",
		"drop_count": 1,
		"color": Color(0.3, 0.65, 0.2),
	},
	TileType.SNOW: {
		"name": "Snow",
		"hardness": 0.5,
		"difficulty_level": 1,
		"drop_item": "snow",
		"drop_count": 1,
		"color": Color(0.9, 0.93, 0.97),
	},
	TileType.WATER: {
		"name": "Water",
		"hardness": 0.0,
		"difficulty_level": 0,
		"drop_item": "",
		"drop_count": 0,
		"color": Color(0.2, 0.4, 0.8),
	},
	TileType.CLAY: {
		"name": "Clay",
		"hardness": 1.2,
		"difficulty_level": 3,
		"drop_item": "clay",
		"drop_count": 1,
		"color": Color(0.65, 0.45, 0.35),
	},
}

# Maps item string names back to TileType for placement.
var item_to_tile: Dictionary = {
	"dirt": TileType.DIRT,
	"stone": TileType.STONE,
	"iron_ore": TileType.IRON_ORE,
	"hard_stone": TileType.HARD_STONE,
	"copper_ore": TileType.COPPER_ORE,
	"gold_ore": TileType.GOLD_ORE,
	"crystal": TileType.CRYSTAL,
	"deep_rock": TileType.DEEP_ROCK,
	"sand": TileType.SAND,
	"sandstone": TileType.SANDSTONE,
	"mud": TileType.MUD,
	"mossy_stone": TileType.MOSSY_STONE,
	"mycelium": TileType.MYCELIUM,
	"volcanic_rock": TileType.VOLCANIC_ROCK,
	"obsidian": TileType.OBSIDIAN,
	"ice": TileType.ICE,
	"frozen_stone": TileType.FROZEN_STONE,
	"ruby_ore": TileType.RUBY_ORE,
	"emerald_ore": TileType.EMERALD_ORE,
	"grass": TileType.GRASS,
	"snow": TileType.SNOW,
	"clay": TileType.CLAY,
}

# --- Biome color palettes ---
# Each biome gets a dictionary of colors used for tile rendering.
# Keys: wall, wall_alt, ground, ground_alt, back_wall, ore_*, surface, subsurface
var biome_palettes: Dictionary = {
	"standard_caverns": {
		"wall": Color(0.35, 0.32, 0.3),
		"wall_alt": Color(0.4, 0.36, 0.33),
		"ground": Color(0.3, 0.22, 0.15),
		"ground_alt": Color(0.28, 0.2, 0.13),
		"back_wall": Color(0.18, 0.14, 0.12),
		"ore_iron": Color(0.7, 0.5, 0.35),
		"ore_copper": Color(0.7, 0.55, 0.3),
		"ore_gold": Color(0.85, 0.75, 0.2),
		"ore_crystal": Color(0.3, 0.8, 0.75),
		"ore_ruby": Color(0.8, 0.15, 0.15),
		"ore_emerald": Color(0.2, 0.75, 0.3),
		"surface": Color(0.35, 0.32, 0.3),
		"subsurface": Color(0.3, 0.25, 0.2),
	},
	"sandy_hollows": {
		"wall": Color(0.6, 0.5, 0.35),
		"wall_alt": Color(0.55, 0.45, 0.32),
		"ground": Color(0.65, 0.55, 0.38),
		"ground_alt": Color(0.6, 0.5, 0.35),
		"back_wall": Color(0.35, 0.28, 0.18),
		"ore_iron": Color(0.7, 0.5, 0.35),
		"ore_copper": Color(0.7, 0.55, 0.3),
		"ore_gold": Color(0.85, 0.75, 0.2),
		"ore_crystal": Color(0.3, 0.8, 0.75),
		"ore_ruby": Color(0.8, 0.15, 0.15),
		"ore_emerald": Color(0.2, 0.75, 0.3),
		"surface": Color(0.76, 0.7, 0.5),
		"subsurface": Color(0.6, 0.5, 0.35),
	},
	"swamp_depths": {
		"wall": Color(0.2, 0.25, 0.18),
		"wall_alt": Color(0.22, 0.28, 0.2),
		"ground": Color(0.25, 0.2, 0.12),
		"ground_alt": Color(0.22, 0.18, 0.1),
		"back_wall": Color(0.1, 0.15, 0.08),
		"ore_iron": Color(0.6, 0.45, 0.3),
		"ore_copper": Color(0.6, 0.5, 0.28),
		"ore_gold": Color(0.8, 0.7, 0.2),
		"ore_crystal": Color(0.3, 0.75, 0.7),
		"ore_ruby": Color(0.75, 0.15, 0.15),
		"ore_emerald": Color(0.2, 0.7, 0.28),
		"surface": Color(0.3, 0.25, 0.15),
		"subsurface": Color(0.22, 0.2, 0.12),
	},
	"fungal_grove": {
		"wall": Color(0.2, 0.3, 0.25),
		"wall_alt": Color(0.18, 0.28, 0.22),
		"ground": Color(0.15, 0.22, 0.18),
		"ground_alt": Color(0.12, 0.2, 0.15),
		"back_wall": Color(0.1, 0.15, 0.12),
		"ore_iron": Color(0.6, 0.45, 0.3),
		"ore_copper": Color(0.6, 0.5, 0.28),
		"ore_gold": Color(0.8, 0.7, 0.2),
		"ore_crystal": Color(0.3, 0.8, 0.75),
		"ore_ruby": Color(0.75, 0.15, 0.15),
		"ore_emerald": Color(0.2, 0.75, 0.3),
		"surface": Color(0.15, 0.22, 0.18),
		"subsurface": Color(0.12, 0.18, 0.14),
	},
	"frozen_caverns": {
		"wall": Color(0.55, 0.6, 0.7),
		"wall_alt": Color(0.5, 0.55, 0.65),
		"ground": Color(0.6, 0.65, 0.75),
		"ground_alt": Color(0.55, 0.6, 0.7),
		"back_wall": Color(0.3, 0.35, 0.45),
		"ore_iron": Color(0.65, 0.5, 0.4),
		"ore_copper": Color(0.65, 0.55, 0.35),
		"ore_gold": Color(0.8, 0.72, 0.25),
		"ore_crystal": Color(0.4, 0.85, 0.8),
		"ore_ruby": Color(0.75, 0.2, 0.2),
		"ore_emerald": Color(0.25, 0.7, 0.35),
		"surface": Color(0.85, 0.88, 0.95),
		"subsurface": Color(0.55, 0.6, 0.7),
	},
	"volcanic_depths": {
		"wall": Color(0.3, 0.18, 0.12),
		"wall_alt": Color(0.35, 0.2, 0.14),
		"ground": Color(0.25, 0.12, 0.08),
		"ground_alt": Color(0.22, 0.1, 0.06),
		"back_wall": Color(0.15, 0.08, 0.05),
		"ore_iron": Color(0.7, 0.45, 0.3),
		"ore_copper": Color(0.7, 0.5, 0.28),
		"ore_gold": Color(0.85, 0.7, 0.2),
		"ore_crystal": Color(0.35, 0.8, 0.7),
		"ore_ruby": Color(0.9, 0.2, 0.1),
		"ore_emerald": Color(0.25, 0.7, 0.28),
		"surface": Color(0.3, 0.18, 0.12),
		"subsurface": Color(0.25, 0.14, 0.1),
	},
	"crystal_caverns": {
		"wall": Color(0.3, 0.25, 0.4),
		"wall_alt": Color(0.35, 0.28, 0.45),
		"ground": Color(0.25, 0.2, 0.35),
		"ground_alt": Color(0.22, 0.18, 0.32),
		"back_wall": Color(0.15, 0.12, 0.25),
		"ore_iron": Color(0.65, 0.5, 0.4),
		"ore_copper": Color(0.65, 0.55, 0.35),
		"ore_gold": Color(0.82, 0.72, 0.25),
		"ore_crystal": Color(0.5, 0.9, 0.85),
		"ore_ruby": Color(0.85, 0.2, 0.15),
		"ore_emerald": Color(0.25, 0.75, 0.35),
		"surface": Color(0.3, 0.25, 0.4),
		"subsurface": Color(0.25, 0.2, 0.35),
	},
	"forest": {
		"wall": Color(0.35, 0.32, 0.3),
		"wall_alt": Color(0.4, 0.36, 0.33),
		"ground": Color(0.3, 0.22, 0.15),
		"ground_alt": Color(0.28, 0.2, 0.13),
		"back_wall": Color(0.18, 0.14, 0.12),
		"surface": Color(0.3, 0.55, 0.2),
		"subsurface": Color(0.4, 0.3, 0.18),
	},
	"desert": {
		"wall": Color(0.6, 0.5, 0.35),
		"wall_alt": Color(0.55, 0.45, 0.32),
		"ground": Color(0.65, 0.55, 0.38),
		"ground_alt": Color(0.6, 0.5, 0.35),
		"back_wall": Color(0.35, 0.28, 0.18),
		"surface": Color(0.76, 0.7, 0.5),
		"subsurface": Color(0.6, 0.5, 0.35),
	},
	"swamp": {
		"wall": Color(0.25, 0.2, 0.12),
		"wall_alt": Color(0.28, 0.22, 0.14),
		"ground": Color(0.3, 0.25, 0.15),
		"ground_alt": Color(0.28, 0.22, 0.13),
		"back_wall": Color(0.12, 0.1, 0.06),
		"surface": Color(0.3, 0.25, 0.15),
		"subsurface": Color(0.25, 0.2, 0.12),
	},
	"mountains": {
		"wall": Color(0.45, 0.43, 0.42),
		"wall_alt": Color(0.5, 0.48, 0.46),
		"ground": Color(0.4, 0.38, 0.36),
		"ground_alt": Color(0.38, 0.36, 0.34),
		"back_wall": Color(0.25, 0.23, 0.22),
		"surface": Color(0.5, 0.48, 0.45),
		"subsurface": Color(0.45, 0.43, 0.42),
	},
	"snowy_peaks": {
		"wall": Color(0.55, 0.6, 0.7),
		"wall_alt": Color(0.5, 0.55, 0.65),
		"ground": Color(0.6, 0.65, 0.75),
		"ground_alt": Color(0.55, 0.6, 0.7),
		"back_wall": Color(0.3, 0.35, 0.45),
		"surface": Color(0.85, 0.88, 0.95),
		"subsurface": Color(0.55, 0.6, 0.7),
	},
	"beach": {
		"wall": Color(0.6, 0.5, 0.35),
		"wall_alt": Color(0.55, 0.45, 0.32),
		"ground": Color(0.65, 0.55, 0.38),
		"ground_alt": Color(0.6, 0.5, 0.35),
		"back_wall": Color(0.35, 0.28, 0.18),
		"surface": Color(0.76, 0.7, 0.5),
		"subsurface": Color(0.7, 0.62, 0.42),
	},
	"ocean": {
		"wall": Color(0.6, 0.5, 0.35),
		"wall_alt": Color(0.55, 0.45, 0.32),
		"ground": Color(0.65, 0.55, 0.38),
		"ground_alt": Color(0.6, 0.5, 0.35),
		"back_wall": Color(0.35, 0.28, 0.18),
		"surface": Color(0.76, 0.7, 0.5),
		"subsurface": Color(0.7, 0.62, 0.42),
	},
}


func _ready() -> void:
	print("[TileData] Initialized with %d tile types." % tile_properties.size())


## Get all registered tile types (excludes EMPTY). Useful for iteration.
func get_tile_types() -> Array:
	return tile_properties.keys()


## Get the full properties dictionary for a tile type. Returns empty dict for EMPTY/unknown.
func get_properties(tile_type: int) -> Dictionary:
	return tile_properties.get(tile_type, {})


## Get the hardness value for a tile type. Returns 0.0 for EMPTY/unknown.
func get_hardness(tile_type: int) -> float:
	var props := get_properties(tile_type)
	return props.get("hardness", 0.0)


## Get the difficulty level for a tile type (1-10 scale). Returns 0 for EMPTY/unknown.
func get_difficulty(tile_type: int) -> int:
	var props := get_properties(tile_type)
	return props.get("difficulty_level", 0)


## Get the drop info for a tile type. Returns {"item": String, "count": int}.
func get_drop(tile_type: int) -> Dictionary:
	var props := get_properties(tile_type)
	if props.is_empty():
		return {"item": "", "count": 0}
	return {"item": props.get("drop_item", ""), "count": props.get("drop_count", 0)}


## Get the atlas coordinates for a tile type on the tile atlas texture.
## Returns Vector2i(index, 0) where index matches the tile_properties insertion order.
## Returns Vector2i(-1, -1) for EMPTY or unknown types.
func get_atlas_coords(tile_type: int) -> Vector2i:
	# Atlas coords map directly: TileType value - 1 = atlas index (since EMPTY=0 is skipped)
	# DIRT=1 -> (0,0), STONE=2 -> (1,0), IRON_ORE=3 -> (2,0), etc.
	if tile_type <= TileType.EMPTY or tile_type > TileType.CLAY:
		return Vector2i(-1, -1)
	return Vector2i(tile_type - 1, 0)


## Get the color for a tile type. Returns white for unknown types.
func get_color(tile_type: int) -> Color:
	var props := get_properties(tile_type)
	return props.get("color", Color.WHITE)


## Get the display name for a tile type. Returns "Unknown" for unknown types.
func get_tile_name(tile_type: int) -> String:
	var props := get_properties(tile_type)
	return props.get("name", "Unknown")


## Get the TileType from an item name string. Returns EMPTY if not found.
func get_tile_from_item(item_name: String) -> int:
	return item_to_tile.get(item_name, TileType.EMPTY)


# --- Render configuration cache ---

## Cached render configuration per tile type. Populated on first access.
var _render_config: Dictionary = {}
var _render_config_built: bool = false


## Build render config cache by scanning tile properties and ItemDatabase metadata.
## Called lazily on first render config access (ItemDatabase must be ready first).
func _build_render_config() -> void:
	_render_config.clear()
	for tile_type in tile_properties.keys():
		var props: Dictionary = tile_properties[tile_type]
		var drop_item: String = props.get("drop_item", "")
		if drop_item == "":
			continue
		var meta: Dictionary = ItemDatabase.get_item_metadata(drop_item)
		var mode: String = meta.get("render_mode", "")
		if mode == "":
			continue
		var config: Dictionary = {"render_mode": mode, "drop_item": drop_item}
		if mode == "splat":
			config["splat_variants"] = meta.get("splat_variants", [])
			config["splat_surface_variants"] = meta.get("splat_surface_variants", [])
		_render_config[tile_type] = config
	_render_config_built = true
	print("[TileDatabase] Render config built: %d tile types with art assets." % _render_config.size())


func _ensure_render_config() -> void:
	if not _render_config_built:
		_build_render_config()


## Get render mode for a tile type: "tileset", "splat", or "" (fallback to colored rect).
func get_render_mode(tile_type: int) -> String:
	_ensure_render_config()
	var config: Dictionary = _render_config.get(tile_type, {})
	return config.get("render_mode", "")


## Get path to tileset PNG for a tileset-mode tile type.
func get_tileset_path(tile_type: int) -> String:
	_ensure_render_config()
	var config: Dictionary = _render_config.get(tile_type, {})
	var drop_item: String = config.get("drop_item", "")
	if drop_item == "":
		return ""
	return "res://assets/items/%s/tiles.png" % drop_item


## Get path to back wall tileset PNG for a tileset-mode tile type.
func get_back_wall_path(tile_type: int) -> String:
	_ensure_render_config()
	var config: Dictionary = _render_config.get(tile_type, {})
	var drop_item: String = config.get("drop_item", "")
	if drop_item == "":
		return ""
	return "res://assets/items/%s/back_wall.png" % drop_item


## Get full paths to splat variant PNGs for a splat-mode tile type.
func get_splat_variants(tile_type: int) -> Array:
	_ensure_render_config()
	var config: Dictionary = _render_config.get(tile_type, {})
	var drop_item: String = config.get("drop_item", "")
	var filenames: Array = config.get("splat_variants", [])
	var paths: Array = []
	for f in filenames:
		paths.append("res://assets/items/%s/%s" % [drop_item, f])
	return paths


## Get full paths to surface splat variant PNGs for a splat-mode tile type.
func get_splat_surface_variants(tile_type: int) -> Array:
	_ensure_render_config()
	var config: Dictionary = _render_config.get(tile_type, {})
	var drop_item: String = config.get("drop_item", "")
	var filenames: Array = config.get("splat_surface_variants", [])
	var paths: Array = []
	for f in filenames:
		paths.append("res://assets/items/%s/%s" % [drop_item, f])
	return paths
