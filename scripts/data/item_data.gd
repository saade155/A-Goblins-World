extends Node

## ItemDatabase — Central registry for all item definitions.
##
## Registered as an autoload. Provides item properties, types, stacking limits,
## and quality tiers. Auto-registers tile-derived items from TileDatabase on startup.
## Non-tile items (tools, weapons, consumables) registered explicitly.

## Item type categories.
enum ItemType {
	MATERIAL,
	PLACEABLE,
	TOOL,
	WEAPON,
	CONSUMABLE,
	EQUIPMENT,
}

## Quality tiers — field exists on every item from day one.
## M4A only produces STANDARD; higher tiers come in M9.
enum Quality {
	CRUDE,
	STANDARD,
	FINE,
	MASTERWORK,
	LEGENDARY,
	ANCIENT,
}

## Internal item registry: item_id (String) -> properties (Dictionary).
var _items: Dictionary = {}


func _ready() -> void:
	_register_all_items()
	print("[ItemDatabase] Initialized with %d items." % _items.size())


## Register a single item into the database.
func _register(id: String, display_name: String, type: int, max_stack: int, tile_type: int = -1, placeable: bool = false, metadata: Dictionary = {}) -> void:
	_items[id] = {
		"id": id,
		"name": display_name,
		"type": type,
		"max_stack": max_stack,
		"icon_path": "",
		"tile_type": tile_type,
		"placeable": placeable,
		"metadata": metadata,
	}


## Items that can be placed back into the world as tiles.
## Ores, deep rock, volcanic rock, obsidian are NOT placeable.
const _NON_PLACEABLE_ITEMS: Array[String] = [
	"iron_ore", "copper_ore", "gold_ore", "crystal",
	"ruby_ore", "emerald_ore", "deep_rock", "volcanic_rock", "obsidian",
]


## Register all items. Called once from _ready().
func _register_all_items() -> void:
	# Auto-register all tile drop items from TileDatabase.
	# TileDatabase is an autoload that initializes before us (registered earlier in project.godot).
	for tile_type_id in TileDatabase.get_tile_types():
		var props: Dictionary = TileDatabase.get_properties(tile_type_id)
		var drop_item: String = props.get("drop_item", "")
		if drop_item != "":
			var can_place: bool = drop_item not in _NON_PLACEABLE_ITEMS
			_register(drop_item, props.get("name", drop_item), ItemType.MATERIAL, 999, tile_type_id, can_place)

	# Torch — placeable but not a tile type in TileDatabase (handled specially by ChunkManager)
	_register("torch", "Torch", ItemType.PLACEABLE, 999, -1, true)

	# Future items will be registered here:
	# Tools (M4E)
	# _register("wood_pickaxe", "Wood Pickaxe", ItemType.TOOL, 1, -1, {"tool_power": 1.0, "mining_speed_bonus": 0.0})
	# _register("stone_pickaxe", "Stone Pickaxe", ItemType.TOOL, 1, -1, {"tool_power": 2.0, "mining_speed_bonus": 0.25})
	# etc.


## Get the full properties dictionary for an item. Returns empty dict for unknown items.
func get_item(item_id: String) -> Dictionary:
	return _items.get(item_id, {})


## Get the display name for an item.
func get_item_name(item_id: String) -> String:
	var item: Dictionary = _items.get(item_id, {})
	return item.get("name", item_id)


## Get the max stack size for an item. Defaults to 1 for unknown items.
func get_max_stack(item_id: String) -> int:
	var item: Dictionary = _items.get(item_id, {})
	return item.get("max_stack", 1)


## Get the ItemType enum value. Returns -1 for unknown items.
func get_type(item_id: String) -> int:
	var item: Dictionary = _items.get(item_id, {})
	return item.get("type", -1)


## Get the TileType int for placeable items. Returns -1 if not placeable.
func get_tile_type(item_id: String) -> int:
	var item: Dictionary = _items.get(item_id, {})
	return item.get("tile_type", -1)


## Check if an item can be placed in the world.
func is_placeable(item_id: String) -> bool:
	var item: Dictionary = _items.get(item_id, {})
	return item.get("placeable", false)


## Check if an item exists in the registry.
func has_item(item_id: String) -> bool:
	return _items.has(item_id)


## Get all registered item IDs.
func get_all_ids() -> Array:
	return _items.keys()
