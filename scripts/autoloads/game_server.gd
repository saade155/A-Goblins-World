## GameServer - The authority for all game state changes.
##
## Every game action flows through this autoload. In single-player, the local
## game IS the server -- but the code treats it that way. This means:
## - Game logic lives here, not in player or UI scripts.
## - State changes go through GameServer methods.
## - The player controller emits input events; it does NOT directly modify world state.
## - Rendering reads from authoritative state, never writes to it.
##
## In a future multiplayer setup (Milestone 17), this becomes the network authority.
## InputManager routes input over the network, and GameServer validates and applies.

extends Node

# --- Signals ---
# These signals are emitted AFTER the server validates and applies a state change.
# Other systems (BehaviorTracker, UI, etc.) listen to these -- they never call
# GameServer methods themselves to read state.

## Emitted when a tile is successfully mined.
signal tile_mined(position: Vector2i, tile_type: int, tool_used: String)

## Emitted when a tile is successfully placed.
signal tile_placed(position: Vector2i, tile_type: int)

## Emitted when an item is collected by a player.
signal item_collected(item_type: String, amount: int)

## Emitted when damage is dealt from one entity to another.
signal damage_dealt(source: Node, target: Node, amount: float, damage_type: String, weapon: String)

## Emitted when an entity is killed.
signal entity_killed(source: Node, target: Node, weapon: String)

## Emitted when a torch is placed.
signal torch_placed(position: Vector2i)

## Emitted when a torch is removed.
signal torch_removed(position: Vector2i)

## Emitted when any inventory slot changes.
signal inventory_changed()

## Emitted when the selected hotbar slot changes.
signal hotbar_selection_changed(slot: int)

## Emitted when items could not be picked up (inventory full).
signal inventory_full(item_id: String, amount: int)

# --- World data ---

## Reference to the authoritative world data. Set by the world scene via initialize_world().
var world_data: WorldData = null

## Main inventory storage (30 slots).
var inventory_main: Array[Dictionary] = []

## Hotbar inventory storage (10 slots).
var inventory_hotbar: Array[Dictionary] = []

## Currently selected hotbar index (0-9).
var selected_hotbar_slot: int = 0

## Maximum distance (in pixels) a player can be from a tile to interact with it.
const INTERACTION_RANGE: float = 96.0  # 3 tiles * 32 pixels

## Tile size in pixels — must match the TileSet and WorldData coordinate system.
const TILE_SIZE: int = 32

## Inventory slot counts.
const MAIN_SLOTS: int = 30
const HOTBAR_SLOTS: int = 10


func _ready() -> void:
	print("[GameServer] Initialized -- acting as local authority.")
	_initialize_inventory()


## Called by the world scene to register the authoritative world data.
func initialize_world(data: WorldData) -> void:
	world_data = data
	print("[GameServer] World data registered with %d tiles." % data.tiles.size())


## Request to mine a tile at the given world tile position.
## Returns true if the mine was successful, false if validation failed.
func request_mine(player: Node, world_pos: Vector2i, tool_power: float) -> bool:
	if world_data == null:
		print("[GameServer] request_mine failed: no world data.")
		return false

	# Validate: tile exists and is not EMPTY.
	var tile_type: int = world_data.get_tile(world_pos)
	if tile_type == TileDatabase.TileType.EMPTY:
		return false

	# Validate: player is close enough.
	var tile_center := Vector2(world_pos.x * TILE_SIZE + TILE_SIZE / 2.0, world_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
	var player_pos := (player as Node2D).global_position
	var distance := player_pos.distance_to(tile_center)
	if distance > INTERACTION_RANGE:
		return false

	# Valid mine -- remove tile from world data.
	world_data.remove_tile(world_pos)

	# Emit signal so the world scene can update visuals and spawn drops.
	tile_mined.emit(world_pos, tile_type, "hand")  # tool_used is "hand" for now

	print("[GameServer] Tile mined at %s (type %d, power %.1f)" % [str(world_pos), tile_type, tool_power])
	return true


## Request to place a tile at the given world tile position.
## Returns true if placement was successful, false if validation failed.
func request_place(player: Node, world_pos: Vector2i, tile_type: int) -> bool:
	if world_data == null:
		print("[GameServer] request_place failed: no world data.")
		return false

	# Validate: position must be empty.
	if world_data.has_tile(world_pos):
		return false

	# Validate: tile type must be valid (not EMPTY).
	if tile_type == TileDatabase.TileType.EMPTY:
		return false

	# Validate: cell is not occupied by any entity.
	if is_cell_occupied(world_pos):
		return false

	# Validate: player is close enough.
	var tile_center := Vector2(world_pos.x * TILE_SIZE + TILE_SIZE / 2.0, world_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
	var player_pos := (player as Node2D).global_position
	var distance := player_pos.distance_to(tile_center)
	if distance > INTERACTION_RANGE:
		return false

	# Valid place -- set tile in world data.
	world_data.set_tile(world_pos, tile_type)

	# Emit signal so the world scene can update visuals.
	tile_placed.emit(world_pos, tile_type)

	print("[GameServer] Tile placed at %s (type %d)" % [str(world_pos), tile_type])
	return true


## Request to collect an item and add it to the player's inventory.
## Returns the number of items that could NOT be added (0 = all collected).
func request_collect_item(player: Node, item_type: String, amount: int) -> int:
	var remainder: int = request_add_item(item_type, amount)
	if remainder < amount:
		item_collected.emit(item_type, amount - remainder)
	if remainder > 0:
		inventory_full.emit(item_type, remainder)
	return remainder


## Apply damage from source to target. This is the ONLY way damage happens.
func deal_damage(source: Node, target: Node, amount: float, damage_type: String = "physical", weapon: String = "") -> void:
	print("[GameServer] deal_damage: %s -> %s for %.1f %s damage (weapon: %s) -- stub." % [
		source.name if source else "null",
		target.name if target else "null",
		amount,
		damage_type,
		weapon
	])


## Request to place a torch at a world tile position.
## Returns true if placement was successful. Requires a torch in inventory.
func request_place_torch(player: Node, world_pos: Vector2i) -> bool:
	if world_data == null:
		return false
	# Cannot place torch on a solid tile
	if world_data.has_tile(world_pos):
		return false
	# Cannot place torch where one already exists
	if world_data.has_torch(world_pos):
		return false
	# Validate: player has a torch in inventory
	if not has_item("torch", 1):
		return false
	# Validate: player is close enough
	var tile_center := Vector2(world_pos.x * TILE_SIZE + TILE_SIZE / 2.0, world_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
	var player_pos := (player as Node2D).global_position
	if player_pos.distance_to(tile_center) > INTERACTION_RANGE:
		return false
	world_data.add_torch(world_pos)
	request_remove_item("torch", 1)
	torch_placed.emit(world_pos)
	return true


## Request to remove a torch at a world tile position.
## Returns true if removal was successful. Returns the torch to inventory.
func request_remove_torch(player: Node, world_pos: Vector2i) -> bool:
	if world_data == null:
		return false
	if not world_data.has_torch(world_pos):
		return false
	var tile_center := Vector2(world_pos.x * TILE_SIZE + TILE_SIZE / 2.0, world_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
	var player_pos := (player as Node2D).global_position
	if player_pos.distance_to(tile_center) > INTERACTION_RANGE:
		return false
	world_data.remove_torch(world_pos)
	request_add_item("torch", 1)
	torch_removed.emit(world_pos)
	return true


# ============================================================================
# Inventory System
# ============================================================================

## Create an empty inventory slot dictionary.
func _empty_slot() -> Dictionary:
	return {"item_id": "", "amount": 0, "quality": 0}


## Initialize both inventory arrays with empty slots. Called from _ready().
func _initialize_inventory() -> void:
	inventory_main.clear()
	inventory_hotbar.clear()
	for i in range(MAIN_SLOTS):
		inventory_main.append(_empty_slot())
	for i in range(HOTBAR_SLOTS):
		inventory_hotbar.append(_empty_slot())
	selected_hotbar_slot = 0


# --- Inventory: Query Methods ---

## Get a slot dictionary by area ("main" or "hotbar") and index.
func get_slot(area: String, index: int) -> Dictionary:
	if area == "hotbar" and index >= 0 and index < HOTBAR_SLOTS:
		return inventory_hotbar[index]
	elif area == "main" and index >= 0 and index < MAIN_SLOTS:
		return inventory_main[index]
	return _empty_slot()


## Shorthand: get a hotbar slot.
func get_hotbar_slot(index: int) -> Dictionary:
	if index >= 0 and index < HOTBAR_SLOTS:
		return inventory_hotbar[index]
	return _empty_slot()


## Shorthand: get a main inventory slot.
func get_main_slot(index: int) -> Dictionary:
	if index >= 0 and index < MAIN_SLOTS:
		return inventory_main[index]
	return _empty_slot()


## Get the currently selected hotbar slot contents.
func get_selected_hotbar_item() -> Dictionary:
	return inventory_hotbar[selected_hotbar_slot]


## Count total amount of an item across all slots.
func get_item_count(item_id: String) -> int:
	var count: int = 0
	for slot in inventory_hotbar:
		if slot["item_id"] == item_id:
			count += slot["amount"]
	for slot in inventory_main:
		if slot["item_id"] == item_id:
			count += slot["amount"]
	return count


## Check if player has at least `amount` of an item.
func has_item(item_id: String, amount: int = 1) -> bool:
	return get_item_count(item_id) >= amount


## Check if all inventory slots are occupied (no empty slots).
## Check if a world cell is occupied by any entity (torch, player, or future entities).
## Used by placement validation to prevent placing blocks on occupied cells.
func is_cell_occupied(world_pos: Vector2i) -> bool:
	# Check torches
	if world_data and world_data.has_torch(world_pos):
		return true

	# Check player position (1.5 tiles tall — feet tile and head tile)
	if GameState.player:
		var player_pos: Vector2 = GameState.player.global_position
		var player_tile := Vector2i(floori(player_pos.x / TILE_SIZE), floori(player_pos.y / TILE_SIZE))
		if world_pos == player_tile or world_pos == player_tile - Vector2i(0, 1):
			return true

	# Future: check stations, NPCs, etc.
	return false


func is_inventory_full() -> bool:
	for slot in inventory_hotbar:
		if slot["item_id"] == "":
			return false
	for slot in inventory_main:
		if slot["item_id"] == "":
			return false
	return true


# --- Inventory: Mutation Methods ---

## Add items to inventory. Returns the number of items that could NOT be added.
## Stacks into existing matching slots first, then empty slots. Hotbar first, then main.
func request_add_item(item_id: String, amount: int, quality: int = 0) -> int:
	if amount <= 0 or item_id == "":
		return amount
	var max_stack: int = ItemDatabase.get_max_stack(item_id)
	var remaining: int = amount

	# Pass 1: Stack into existing matching slots (hotbar first)
	for slot in inventory_hotbar:
		if remaining <= 0:
			break
		if slot["item_id"] == item_id and slot["quality"] == quality and slot["amount"] < max_stack:
			var space: int = max_stack - slot["amount"]
			var to_add: int = mini(remaining, space)
			slot["amount"] += to_add
			remaining -= to_add

	for slot in inventory_main:
		if remaining <= 0:
			break
		if slot["item_id"] == item_id and slot["quality"] == quality and slot["amount"] < max_stack:
			var space: int = max_stack - slot["amount"]
			var to_add: int = mini(remaining, space)
			slot["amount"] += to_add
			remaining -= to_add

	# Pass 2: Place into empty slots (hotbar first)
	for slot in inventory_hotbar:
		if remaining <= 0:
			break
		if slot["item_id"] == "":
			var to_add: int = mini(remaining, max_stack)
			slot["item_id"] = item_id
			slot["amount"] = to_add
			slot["quality"] = quality
			remaining -= to_add

	for slot in inventory_main:
		if remaining <= 0:
			break
		if slot["item_id"] == "":
			var to_add: int = mini(remaining, max_stack)
			slot["item_id"] = item_id
			slot["amount"] = to_add
			slot["quality"] = quality
			remaining -= to_add

	if remaining < amount:
		inventory_changed.emit()
	return remaining


## Remove items from inventory. Returns true if all items were removed.
## All-or-nothing: if insufficient items, nothing is removed.
## quality = -1 means any quality.
func request_remove_item(item_id: String, amount: int, quality: int = -1) -> bool:
	if amount <= 0:
		return true

	# First: check if we have enough
	var available: int = 0
	for slot in inventory_main:
		if slot["item_id"] == item_id and (quality == -1 or slot["quality"] == quality):
			available += slot["amount"]
	for slot in inventory_hotbar:
		if slot["item_id"] == item_id and (quality == -1 or slot["quality"] == quality):
			available += slot["amount"]

	if available < amount:
		return false

	# Remove from main first, then hotbar
	var remaining: int = amount
	for slot in inventory_main:
		if remaining <= 0:
			break
		if slot["item_id"] == item_id and (quality == -1 or slot["quality"] == quality):
			var to_remove: int = mini(remaining, slot["amount"])
			slot["amount"] -= to_remove
			remaining -= to_remove
			if slot["amount"] <= 0:
				slot["item_id"] = ""
				slot["amount"] = 0
				slot["quality"] = 0

	for slot in inventory_hotbar:
		if remaining <= 0:
			break
		if slot["item_id"] == item_id and (quality == -1 or slot["quality"] == quality):
			var to_remove: int = mini(remaining, slot["amount"])
			slot["amount"] -= to_remove
			remaining -= to_remove
			if slot["amount"] <= 0:
				slot["item_id"] = ""
				slot["amount"] = 0
				slot["quality"] = 0

	inventory_changed.emit()
	return true


## Swap two inventory slots. If same item_id and quality, stack-merge instead.
func request_swap_slots(from_area: String, from_index: int, to_area: String, to_index: int) -> bool:
	var from_arr: Array[Dictionary] = inventory_hotbar if from_area == "hotbar" else inventory_main
	var to_arr: Array[Dictionary] = inventory_hotbar if to_area == "hotbar" else inventory_main
	var from_max: int = HOTBAR_SLOTS if from_area == "hotbar" else MAIN_SLOTS
	var to_max: int = HOTBAR_SLOTS if to_area == "hotbar" else MAIN_SLOTS

	if from_index < 0 or from_index >= from_max or to_index < 0 or to_index >= to_max:
		return false

	var from_slot: Dictionary = from_arr[from_index]
	var to_slot: Dictionary = to_arr[to_index]

	# Stack merge if same item and quality
	if from_slot["item_id"] != "" and from_slot["item_id"] == to_slot["item_id"] and from_slot["quality"] == to_slot["quality"]:
		var max_stack: int = ItemDatabase.get_max_stack(from_slot["item_id"])
		var space: int = max_stack - to_slot["amount"]
		if space > 0:
			var to_move: int = mini(from_slot["amount"], space)
			to_slot["amount"] += to_move
			from_slot["amount"] -= to_move
			if from_slot["amount"] <= 0:
				from_arr[from_index] = _empty_slot()
			inventory_changed.emit()
			return true

	# Plain swap
	var temp: Dictionary = from_slot.duplicate()
	from_arr[from_index] = to_slot.duplicate()
	to_arr[to_index] = temp
	inventory_changed.emit()
	return true


## Split a stack: move split_amount from source to target slot.
## Target must be empty or contain the same item+quality.
func request_split_stack(area: String, slot_index: int, split_amount: int, target_area: String, target_index: int) -> bool:
	var src_arr: Array[Dictionary] = inventory_hotbar if area == "hotbar" else inventory_main
	var dst_arr: Array[Dictionary] = inventory_hotbar if target_area == "hotbar" else inventory_main
	var src_max: int = HOTBAR_SLOTS if area == "hotbar" else MAIN_SLOTS
	var dst_max: int = HOTBAR_SLOTS if target_area == "hotbar" else MAIN_SLOTS

	if slot_index < 0 or slot_index >= src_max or target_index < 0 or target_index >= dst_max:
		return false

	var src: Dictionary = src_arr[slot_index]
	var dst: Dictionary = dst_arr[target_index]

	if src["item_id"] == "" or split_amount <= 0 or split_amount > src["amount"]:
		return false

	if dst["item_id"] != "" and (dst["item_id"] != src["item_id"] or dst["quality"] != src["quality"]):
		return false

	var max_stack: int = ItemDatabase.get_max_stack(src["item_id"])
	var dst_amount: int = dst["amount"] if dst["item_id"] != "" else 0
	var space: int = max_stack - dst_amount
	var to_move: int = mini(split_amount, space)

	if to_move <= 0:
		return false

	# Save item info before modifying source
	var moved_item_id: String = src["item_id"]
	var moved_quality: int = src["quality"]

	src["amount"] -= to_move
	if src["amount"] <= 0:
		src_arr[slot_index] = _empty_slot()

	if dst["item_id"] == "":
		dst_arr[target_index] = {"item_id": moved_item_id, "amount": to_move, "quality": moved_quality}
	else:
		dst["amount"] += to_move

	inventory_changed.emit()
	return true


## Select a hotbar slot.
func request_select_hotbar(slot: int) -> void:
	selected_hotbar_slot = clampi(slot, 0, HOTBAR_SLOTS - 1)
	hotbar_selection_changed.emit(selected_hotbar_slot)


## Place a tile from inventory. Wraps request_place() with inventory deduction.
func request_place_with_inventory(player: Node, world_pos: Vector2i, item_id: String) -> bool:
	var tile_type: int = ItemDatabase.get_tile_type(item_id)
	if tile_type <= 0:
		return false
	if not has_item(item_id, 1):
		return false
	# Use existing request_place for world validation
	var placed: bool = request_place(player, world_pos, tile_type)
	if placed:
		request_remove_item(item_id, 1)
	return placed
