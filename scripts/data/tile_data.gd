## TileData - Registry of all tile types and their properties.
##
## This autoload provides a central lookup for tile metadata: hardness, drops,
## display color, etc. All tile-related constants and data queries go through here.
## When we add new tile types in later milestones, we only need to update this file.

extends Node

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
		"drop_item": "dirt",
		"drop_count": 1,
		"color": Color(0.55, 0.35, 0.17),  # Brown
	},
	TileType.STONE: {
		"name": "Stone",
		"hardness": 2.5,
		"drop_item": "stone",
		"drop_count": 1,
		"color": Color(0.5, 0.5, 0.5),  # Gray
	},
	TileType.IRON_ORE: {
		"name": "Iron Ore",
		"hardness": 4.0,
		"drop_item": "iron_ore",
		"drop_count": 1,
		"color": Color(0.7, 0.5, 0.35),  # Rusty brown
	},
	TileType.HARD_STONE: {
		"name": "Hard Stone",
		"hardness": 4.0,
		"drop_item": "hard_stone",
		"drop_count": 1,
		"color": Color(0.45, 0.48, 0.58),  # Gray-blue
	},
	TileType.COPPER_ORE: {
		"name": "Copper Ore",
		"hardness": 3.0,
		"drop_item": "copper_ore",
		"drop_count": 1,
		"color": Color(0.7, 0.55, 0.3),  # Orange-green
	},
	TileType.GOLD_ORE: {
		"name": "Gold Ore",
		"hardness": 5.0,
		"drop_item": "gold_ore",
		"drop_count": 1,
		"color": Color(0.85, 0.75, 0.2),  # Yellow
	},
	TileType.CRYSTAL: {
		"name": "Crystal",
		"hardness": 6.0,
		"drop_item": "crystal",
		"drop_count": 1,
		"color": Color(0.3, 0.8, 0.75),  # Cyan/teal
	},
	TileType.DEEP_ROCK: {
		"name": "Deep Rock",
		"hardness": 8.0,
		"drop_item": "deep_rock",
		"drop_count": 1,
		"color": Color(0.35, 0.2, 0.45),  # Dark purple
	},
	TileType.SAND: {
		"name": "Sand",
		"hardness": 0.5,
		"drop_item": "sand",
		"drop_count": 1,
		"color": Color(0.85, 0.78, 0.55),
	},
	TileType.SANDSTONE: {
		"name": "Sandstone",
		"hardness": 1.5,
		"drop_item": "sandstone",
		"drop_count": 1,
		"color": Color(0.78, 0.65, 0.42),
	},
	TileType.MUD: {
		"name": "Mud",
		"hardness": 0.7,
		"drop_item": "mud",
		"drop_count": 1,
		"color": Color(0.35, 0.28, 0.18),
	},
	TileType.MOSSY_STONE: {
		"name": "Mossy Stone",
		"hardness": 2.0,
		"drop_item": "mossy_stone",
		"drop_count": 1,
		"color": Color(0.35, 0.55, 0.30),
	},
	TileType.MYCELIUM: {
		"name": "Mycelium",
		"hardness": 1.2,
		"drop_item": "mycelium",
		"drop_count": 1,
		"color": Color(0.60, 0.45, 0.65),
	},
	TileType.VOLCANIC_ROCK: {
		"name": "Volcanic Rock",
		"hardness": 5.0,
		"drop_item": "volcanic_rock",
		"drop_count": 1,
		"color": Color(0.3, 0.15, 0.1),
	},
	TileType.OBSIDIAN: {
		"name": "Obsidian",
		"hardness": 10.0,
		"drop_item": "obsidian",
		"drop_count": 1,
		"color": Color(0.1, 0.05, 0.15),
	},
	TileType.ICE: {
		"name": "Ice",
		"hardness": 1.5,
		"drop_item": "ice",
		"drop_count": 1,
		"color": Color(0.7, 0.85, 0.95),
	},
	TileType.FROZEN_STONE: {
		"name": "Frozen Stone",
		"hardness": 3.5,
		"drop_item": "frozen_stone",
		"drop_count": 1,
		"color": Color(0.5, 0.6, 0.75),
	},
	TileType.RUBY_ORE: {
		"name": "Ruby Ore",
		"hardness": 6.0,
		"drop_item": "ruby_ore",
		"drop_count": 1,
		"color": Color(0.8, 0.15, 0.2),
	},
	TileType.EMERALD_ORE: {
		"name": "Emerald Ore",
		"hardness": 5.0,
		"drop_item": "emerald_ore",
		"drop_count": 1,
		"color": Color(0.15, 0.7, 0.3),
	},
	TileType.GRASS: {
		"name": "Grass",
		"hardness": 0.8,
		"drop_item": "grass",
		"drop_count": 1,
		"color": Color(0.3, 0.65, 0.2),
	},
	TileType.SNOW: {
		"name": "Snow",
		"hardness": 0.5,
		"drop_item": "snow",
		"drop_count": 1,
		"color": Color(0.9, 0.93, 0.97),
	},
	TileType.WATER: {
		"name": "Water",
		"hardness": 0.0,
		"drop_item": "",
		"drop_count": 0,
		"color": Color(0.2, 0.4, 0.8),
	},
	TileType.CLAY: {
		"name": "Clay",
		"hardness": 1.2,
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


func _ready() -> void:
	print("[TileData] Initialized with %d tile types." % tile_properties.size())


## Get the full properties dictionary for a tile type. Returns empty dict for EMPTY/unknown.
func get_properties(tile_type: int) -> Dictionary:
	return tile_properties.get(tile_type, {})


## Get the hardness value for a tile type. Returns 0.0 for EMPTY/unknown.
func get_hardness(tile_type: int) -> float:
	var props := get_properties(tile_type)
	return props.get("hardness", 0.0)


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


## Get the TileType from an item name string. Returns EMPTY if not found.
func get_tile_from_item(item_name: String) -> int:
	return item_to_tile.get(item_name, TileType.EMPTY)
