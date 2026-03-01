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

	# --- Equipment (M7 test items) ---
	_register("iron_helmet", "Iron Helmet", ItemType.EQUIPMENT, 1, -1, false, {
		"equip_slot": 0,
		"equip_mode": "overlay",
		"equip_layers": ["head"],
		"stats": {"defense": 2.0},
		"description": "A sturdy iron helmet.",
	})
	_register("iron_chestplate", "Iron Chestplate", ItemType.EQUIPMENT, 1, -1, false, {
		"equip_slot": 1,
		"stats": {"defense": 4.0},
		"description": "Basic iron chest armor.",
	})
	_register("leather_belt", "Leather Belt", ItemType.EQUIPMENT, 1, -1, false, {
		"equip_slot": 2,
		"stats": {"carry_bonus": 5.0},
		"description": "A simple leather belt.",
	})
	_register("iron_gauntlets", "Iron Gauntlets", ItemType.EQUIPMENT, 1, -1, false, {
		"equip_slot": 3,
		"stats": {"mining_power": 1.0},
		"description": "Reinforced iron gauntlets.",
	})
	_register("iron_greaves", "Iron Greaves", ItemType.EQUIPMENT, 1, -1, false, {
		"equip_slot": 4,
		"stats": {"defense": 3.0},
		"description": "Protective leg armor.",
	})
	# Slot 5 (BACK) — capes, backpacks, quivers, etc. No test item yet.

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


## Get the metadata dictionary for an item. Returns empty dict for unknown items.
func get_item_metadata(item_id: String) -> Dictionary:
	var item: Dictionary = _items.get(item_id, {})
	return item.get("metadata", {})


## Get the equip slot index for an item. Returns -1 if not equippable.
func get_equip_slot(item_id: String) -> int:
	return get_item_metadata(item_id).get("equip_slot", -1)


## Get the convention-based icon path for an item: res://assets/items/<item_id>/icon.png
func get_icon_path(item_id: String) -> String:
	return "res://assets/items/%s/icon.png" % item_id


## Check if an item can be equipped.
func is_equippable(item_id: String) -> bool:
	return get_equip_slot(item_id) >= 0


## Default body layers affected by each equipment slot.
const _SLOT_DEFAULT_LAYERS: Dictionary = {
	0: ["head"],                     # HEAD
	1: ["chest"],                    # CHEST
	2: ["belt"],                     # BELT
	3: ["back_arm", "front_arm"],    # ARMS
	4: ["back_leg", "front_leg"],    # LEGS
	5: [],                           # BACK (capes, backpacks — custom layers per item)
}


## Get the equip mode for an item ("overlay" or "replace"). Defaults to "overlay".
func get_equip_mode(item_id: String) -> String:
	return get_item_metadata(item_id).get("equip_mode", "overlay")


## Get the body layers this equipment affects. Falls back to slot defaults.
func get_equip_layers(item_id: String) -> Array:
	var meta := get_item_metadata(item_id)
	var layers = meta.get("equip_layers", [])
	if layers.size() > 0:
		return layers
	var slot: int = meta.get("equip_slot", -1)
	return _SLOT_DEFAULT_LAYERS.get(slot, [])
