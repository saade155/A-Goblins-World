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
}

# Maps item string names back to TileType for placement.
var item_to_tile: Dictionary = {
	"dirt": TileType.DIRT,
	"stone": TileType.STONE,
	"iron_ore": TileType.IRON_ORE,
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
## Dirt = (0,0), Stone = (1,0), Iron Ore = (2,0). Returns Vector2i(-1,-1) for EMPTY.
func get_atlas_coords(tile_type: int) -> Vector2i:
	match tile_type:
		TileType.DIRT:
			return Vector2i(0, 0)
		TileType.STONE:
			return Vector2i(1, 0)
		TileType.IRON_ORE:
			return Vector2i(2, 0)
		_:
			return Vector2i(-1, -1)


## Get the TileType from an item name string. Returns EMPTY if not found.
func get_tile_from_item(item_name: String) -> int:
	return item_to_tile.get(item_name, TileType.EMPTY)
