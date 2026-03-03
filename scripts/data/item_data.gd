extends Node

## ItemDatabase — Central registry for all item definitions.
##
## Registered as an autoload. Provides item properties, types, stacking limits,
## and quality tiers. Item definitions loaded from res://data/items.json on startup.

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

## String-to-enum mapping for JSON type field.
const _ITEM_TYPE_MAP: Dictionary = {
	"MATERIAL": ItemType.MATERIAL,
	"PLACEABLE": ItemType.PLACEABLE,
	"TOOL": ItemType.TOOL,
	"WEAPON": ItemType.WEAPON,
	"CONSUMABLE": ItemType.CONSUMABLE,
	"EQUIPMENT": ItemType.EQUIPMENT,
}


func _ready() -> void:
	_load_items_from_json("res://data/items.json")
	print("[ItemDatabase] Initialized with %d items." % _items.size())


## Load all item definitions from a JSON file.
func _load_items_from_json(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[ItemDatabase] Failed to open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return

	var text: String = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("[ItemDatabase] Failed to parse JSON from %s" % path)
		return

	var item_list: Array = parsed.get("items", [])
	for entry in item_list:
		_load_item_entry(entry)


## Parse and register a single item entry from JSON.
func _load_item_entry(entry: Dictionary) -> void:
	var id: String = entry.get("id", "")
	if id == "":
		push_warning("[ItemDatabase] Skipping item with missing 'id'")
		return

	var type_str: String = entry.get("type", "")
	if not _ITEM_TYPE_MAP.has(type_str):
		push_warning("[ItemDatabase] Item '%s' has invalid type '%s', skipping" % [id, type_str])
		return
	var type_int: int = _ITEM_TYPE_MAP[type_str]

	# Resolve tile_type string to TileDatabase enum int.
	var tile_type: int = -1
	var tile_type_val = entry.get("tile_type")
	if tile_type_val is String and tile_type_val != "":
		tile_type = _resolve_tile_type(tile_type_val)
		if tile_type == -1:
			push_warning("[ItemDatabase] Item '%s' has invalid tile_type '%s'" % [id, tile_type_val])

	_items[id] = {
		"id": id,
		"name": entry.get("name", id),
		"type": type_int,
		"max_stack": int(entry.get("max_stack", 1)),
		"icon_path": "",
		"tile_type": tile_type,
		"placeable": entry.get("placeable", false),
		"metadata": entry.get("metadata", {}),
	}


## Resolve a tile type name string to its TileDatabase enum int.
func _resolve_tile_type(type_name: String) -> int:
	if TileDatabase.TileType.has(type_name):
		return TileDatabase.TileType[type_name]
	return -1


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
	return int(get_item_metadata(item_id).get("equip_slot", -1))


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
	var slot: int = int(meta.get("equip_slot", -1))
	return _SLOT_DEFAULT_LAYERS.get(slot, [])
