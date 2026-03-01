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

## Emitted when a back wall tile is successfully mined.
signal back_wall_mined(position: Vector2i, tile_type: int)

## Emitted when a back wall tile is successfully placed.
signal back_wall_placed(position: Vector2i, tile_type: int)

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

## Emitted when an equipment slot changes.
signal equipment_changed(slot: int)

## Emitted when the inventory open/closed state changes.
signal inventory_open_changed(is_open: bool)

## Emitted when the cursor-held item changes.
signal cursor_item_changed()

## Emitted when player health changes.
signal player_health_changed(current: float, max_val: float)

## Emitted when player mana changes.
signal player_mana_changed(current: float, max_val: float)

## Emitted when player stamina changes.
signal player_stamina_changed(current: float, max_val: float)

## Emitted to request an event-triggered autosave (e.g., after boss kill, biome entry).
## ChunkManager listens and creates a rolling autosave snapshot.
signal autosave_requested(reason: String)

# --- World data ---

## Reference to the authoritative world data. Set by the world scene via initialize_world().
var world_data: WorldData = null

## Main inventory storage (30 slots).
var inventory_main: Array[Dictionary] = []

## Hotbar inventory storage (10 slots).
var inventory_hotbar: Array[Dictionary] = []

## Equipment inventory storage (6 slots).
var inventory_equipment: Array[Dictionary] = []

## Whether the inventory UI is currently open.
var inventory_open: bool = false

## Whether the skill panel is currently open.
var skill_panel_open: bool = false

## Whether the map overlay is currently open.
var map_open: bool = false

## Item currently held on the cursor (drag-and-drop).
var cursor_item: Dictionary = {"item_id": "", "amount": 0, "quality": 0}

## Currently selected hotbar index (0-9).
var selected_hotbar_slot: int = 0

# --- Player stats ---

## Player health.
var player_max_health: float = 100.0
var player_health: float = 100.0

## Player mana.
var player_max_mana: float = 50.0
var player_mana: float = 50.0

## Player stamina.
var player_max_stamina: float = 100.0
var player_stamina: float = 100.0

## Maximum distance (in pixels) a player can be from a tile to interact with it.
const INTERACTION_RANGE: float = 96.0  # 6 tiles * 16 pixels

## Tile size in pixels — must match the TileSet and WorldData coordinate system.
const TILE_SIZE: int = 16

## Inventory slot counts.
const MAIN_SLOTS: int = 30
const HOTBAR_SLOTS: int = 10

## Equipment slot counts and indices.
const EQUIP_SLOTS: int = 6
const EQUIP_HEAD: int = 0
const EQUIP_CHEST: int = 1
const EQUIP_BELT: int = 2
const EQUIP_ARMS: int = 3
const EQUIP_LEGS: int = 4
const EQUIP_BACK: int = 5


func _ready() -> void:
	print("[GameServer] Initialized -- acting as local authority.")
	_initialize_inventory()


## Reset all session-specific state. Called when returning to main menu or starting a new game.
func reset_state() -> void:
	world_data = null
	selected_hotbar_slot = 0
	player_max_health = 100.0
	player_health = 100.0
	player_max_mana = 50.0
	player_mana = 50.0
	player_max_stamina = 100.0
	player_stamina = 100.0
	cursor_item = _empty_slot()
	inventory_open = false
	skill_panel_open = false
	map_open = false
	_initialize_inventory()
	print("[GameServer] State reset.")


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

	# Skill system: bonus ore chance
	var bonus_chance: float = SkillSystem.get_total_perk_effect("bonus_ore_chance")
	if bonus_chance > 0.0 and randf() < bonus_chance:
		var bonus_drop: Dictionary = TileDatabase.get_drop(tile_type)
		if bonus_drop["item"] != "":
			request_add_item(bonus_drop["item"], 1)

	print("[GameServer] Tile mined at %s (type %d, power %.1f)" % [str(world_pos), tile_type, tool_power])
	return true


## Request to mine a back wall tile at the given world tile position.
## Can only mine back walls when the foreground tile is empty.
## Returns true if the mine was successful, false if validation failed.
func request_mine_back_wall(player: Node, world_pos: Vector2i) -> bool:
	if world_data == null:
		return false

	# Validate: back wall exists at this position.
	if not world_data.has_back_wall(world_pos):
		return false

	# Validate: foreground must be empty (can't mine back wall through solid tile).
	if world_data.has_tile(world_pos):
		return false

	# Validate: player is close enough.
	var tile_center := Vector2(world_pos.x * TILE_SIZE + TILE_SIZE / 2.0, world_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
	var player_pos := (player as Node2D).global_position
	if player_pos.distance_to(tile_center) > INTERACTION_RANGE:
		return false

	# Valid mine -- get the type before removing.
	var wall_type: int = world_data.get_back_wall(world_pos)
	world_data.remove_back_wall(world_pos)

	# Emit signal so the world scene can update visuals and spawn drops.
	back_wall_mined.emit(world_pos, wall_type)

	print("[GameServer] Back wall mined at %s (type %d)" % [str(world_pos), wall_type])
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

	# Place as back wall first if none exists, otherwise place as foreground.
	if not world_data.has_back_wall(world_pos):
		world_data.set_back_wall(world_pos, tile_type)
		back_wall_placed.emit(world_pos, tile_type)
		print("[GameServer] Back wall placed at %s (type %d)" % [str(world_pos), tile_type])
	else:
		world_data.set_tile(world_pos, tile_type)
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


## Initialize all inventory arrays with empty slots. Called from _ready().
func _initialize_inventory() -> void:
	inventory_main.clear()
	inventory_hotbar.clear()
	for i in range(MAIN_SLOTS):
		inventory_main.append(_empty_slot())
	for i in range(HOTBAR_SLOTS):
		inventory_hotbar.append(_empty_slot())
	selected_hotbar_slot = 0
	_initialize_equipment()


## Initialize equipment array with empty slots.
func _initialize_equipment() -> void:
	inventory_equipment.clear()
	for i in range(EQUIP_SLOTS):
		inventory_equipment.append(_empty_slot())


## Return the inventory array for a given area name.
func _get_inv_array(area: String) -> Array[Dictionary]:
	if area == "hotbar":
		return inventory_hotbar
	elif area == "equipment":
		return inventory_equipment
	else:
		return inventory_main


## Return the max slot count for a given area name.
func _get_inv_max(area: String) -> int:
	if area == "hotbar":
		return HOTBAR_SLOTS
	elif area == "equipment":
		return EQUIP_SLOTS
	else:
		return MAIN_SLOTS


# --- Inventory: Query Methods ---

## Get a slot dictionary by area ("main", "hotbar", or "equipment") and index.
func get_slot(area: String, index: int) -> Dictionary:
	if area == "hotbar" and index >= 0 and index < HOTBAR_SLOTS:
		return inventory_hotbar[index]
	elif area == "main" and index >= 0 and index < MAIN_SLOTS:
		return inventory_main[index]
	elif area == "equipment" and index >= 0 and index < EQUIP_SLOTS:
		return inventory_equipment[index]
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


## Shorthand: get an equipment slot.
func get_equipment_slot(index: int) -> Dictionary:
	if index >= 0 and index < EQUIP_SLOTS:
		return inventory_equipment[index]
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


## Set whether the inventory UI is open. Returns cursor item when closing.
func set_inventory_open(open: bool) -> void:
	inventory_open = open
	if not open:
		_return_cursor_item()
	inventory_open_changed.emit(open)


## Pick up items from a slot into the cursor.
## area: "main", "hotbar", or "equipment". amount=-1 means full stack.
## If cursor is empty: pick up. If cursor has same item+quality: merge into cursor.
## Returns false if nothing can be picked up.
func request_pickup_from_slot(area: String, index: int, amount: int = -1) -> bool:
	var arr: Array[Dictionary] = _get_inv_array(area)
	var arr_max: int = _get_inv_max(area)
	if index < 0 or index >= arr_max:
		return false

	var slot: Dictionary = arr[index]
	if slot["item_id"] == "":
		return false

	var pickup_amount: int = slot["amount"] if amount == -1 else mini(amount, slot["amount"])
	if pickup_amount <= 0:
		return false

	# Cursor is empty: pick up directly
	if cursor_item["item_id"] == "":
		cursor_item["item_id"] = slot["item_id"]
		cursor_item["quality"] = slot["quality"]
		cursor_item["amount"] = pickup_amount
		slot["amount"] -= pickup_amount
		if slot["amount"] <= 0:
			arr[index] = _empty_slot()
		if area == "equipment":
			equipment_changed.emit(index)
		cursor_item_changed.emit()
		inventory_changed.emit()
		return true

	# Cursor has same item+quality: merge into cursor
	if cursor_item["item_id"] == slot["item_id"] and cursor_item["quality"] == slot["quality"]:
		var cursor_max: int = ItemDatabase.get_max_stack(cursor_item["item_id"])
		var cursor_space: int = cursor_max - cursor_item["amount"]
		if cursor_space <= 0:
			return false
		var to_move: int = mini(pickup_amount, cursor_space)
		cursor_item["amount"] += to_move
		slot["amount"] -= to_move
		if slot["amount"] <= 0:
			arr[index] = _empty_slot()
		if area == "equipment":
			equipment_changed.emit(index)
		cursor_item_changed.emit()
		inventory_changed.emit()
		return true

	return false


## Place items from cursor into a slot.
## area: "main", "hotbar", or "equipment". amount=-1 means full stack.
## Empty slot: place. Same item: merge. Different item: swap (full stack only).
## For equipment: validates equip_slot via ItemDatabase.get_equip_slot().
## Returns false if placement is invalid.
func request_place_to_slot(area: String, index: int, amount: int = -1) -> bool:
	var arr: Array[Dictionary] = _get_inv_array(area)
	var arr_max: int = _get_inv_max(area)
	if index < 0 or index >= arr_max:
		return false

	if cursor_item["item_id"] == "":
		return false

	var place_amount: int = cursor_item["amount"] if amount == -1 else mini(amount, cursor_item["amount"])
	if place_amount <= 0:
		return false

	# Equipment slot validation
	if area == "equipment":
		var equip_slot: int = ItemDatabase.get_equip_slot(cursor_item["item_id"])
		if equip_slot != index:
			return false
		# Equipment slots always have amount=1
		place_amount = 1

	var slot: Dictionary = arr[index]

	# Empty slot: place items
	if slot["item_id"] == "":
		arr[index] = {"item_id": cursor_item["item_id"], "amount": place_amount, "quality": cursor_item["quality"]}
		cursor_item["amount"] -= place_amount
		if cursor_item["amount"] <= 0:
			cursor_item = _empty_slot()
		if area == "equipment":
			equipment_changed.emit(index)
		cursor_item_changed.emit()
		inventory_changed.emit()
		return true

	# Same item+quality: merge
	if slot["item_id"] == cursor_item["item_id"] and slot["quality"] == cursor_item["quality"]:
		if area == "equipment":
			return false  # Equipment slots can't stack
		var max_stack: int = ItemDatabase.get_max_stack(slot["item_id"])
		var space: int = max_stack - slot["amount"]
		if space <= 0:
			return false
		var to_move: int = mini(place_amount, space)
		slot["amount"] += to_move
		cursor_item["amount"] -= to_move
		if cursor_item["amount"] <= 0:
			cursor_item = _empty_slot()
		cursor_item_changed.emit()
		inventory_changed.emit()
		return true

	# Different item: swap (only for full stack placement)
	if amount != -1:
		return false  # Partial placement can't swap

	var old_slot: Dictionary = slot.duplicate()
	arr[index] = {"item_id": cursor_item["item_id"], "amount": place_amount, "quality": cursor_item["quality"]}
	cursor_item = old_slot
	if area == "equipment":
		equipment_changed.emit(index)
	cursor_item_changed.emit()
	inventory_changed.emit()
	return true


## Quick-move an item (shift+click behavior).
## If equippable and equipment slot empty: equip it.
## Otherwise: move between main <-> hotbar (stack first, then empty slots).
func request_quick_move(area: String, index: int) -> bool:
	var arr: Array[Dictionary] = _get_inv_array(area)
	var arr_max: int = _get_inv_max(area)
	if index < 0 or index >= arr_max:
		return false

	var slot: Dictionary = arr[index]
	if slot["item_id"] == "":
		return false

	# Try equipping if item is equippable and slot is empty
	if area != "equipment":
		var equip_slot: int = ItemDatabase.get_equip_slot(slot["item_id"])
		if equip_slot >= 0 and equip_slot < EQUIP_SLOTS:
			if inventory_equipment[equip_slot]["item_id"] == "":
				inventory_equipment[equip_slot] = {"item_id": slot["item_id"], "amount": 1, "quality": slot["quality"]}
				slot["amount"] -= 1
				if slot["amount"] <= 0:
					arr[index] = _empty_slot()
				equipment_changed.emit(equip_slot)
				inventory_changed.emit()
				return true

	# Move from equipment to inventory
	if area == "equipment":
		var eq_item_id: String = slot["item_id"]
		var eq_quality: int = slot["quality"]
		var eq_stack_max: int = ItemDatabase.get_max_stack(eq_item_id)
		var moved: bool = false
		# Try stacking into hotbar first, then main
		for target_slot in inventory_hotbar:
			if target_slot["item_id"] == eq_item_id and target_slot["quality"] == eq_quality:
				if target_slot["amount"] < eq_stack_max:
					target_slot["amount"] += 1
					arr[index] = _empty_slot()
					moved = true
					break
		if not moved:
			for target_slot in inventory_main:
				if target_slot["item_id"] == eq_item_id and target_slot["quality"] == eq_quality:
					if target_slot["amount"] < eq_stack_max:
						target_slot["amount"] += 1
						arr[index] = _empty_slot()
						moved = true
						break
		if not moved:
			for target_slot in inventory_hotbar:
				if target_slot["item_id"] == "":
					target_slot["item_id"] = eq_item_id
					target_slot["amount"] = 1
					target_slot["quality"] = eq_quality
					arr[index] = _empty_slot()
					moved = true
					break
		if not moved:
			for target_slot in inventory_main:
				if target_slot["item_id"] == "":
					target_slot["item_id"] = eq_item_id
					target_slot["amount"] = 1
					target_slot["quality"] = eq_quality
					arr[index] = _empty_slot()
					moved = true
					break
		if moved:
			equipment_changed.emit(index)
			inventory_changed.emit()
		return moved

	# Move between main <-> hotbar
	var target_arr: Array[Dictionary]
	var target_max: int
	if area == "main":
		target_arr = inventory_hotbar
		target_max = HOTBAR_SLOTS
	else:
		target_arr = inventory_main
		target_max = MAIN_SLOTS

	var item_id: String = slot["item_id"]
	var quality: int = slot["quality"]
	var remaining: int = slot["amount"]
	var max_stack: int = ItemDatabase.get_max_stack(item_id)

	# Pass 1: Stack into matching slots in target
	for i in range(target_max):
		if remaining <= 0:
			break
		var target_slot: Dictionary = target_arr[i]
		if target_slot["item_id"] == item_id and target_slot["quality"] == quality:
			var space: int = max_stack - target_slot["amount"]
			if space > 0:
				var to_move: int = mini(remaining, space)
				target_slot["amount"] += to_move
				remaining -= to_move

	# Pass 2: Place into empty slots in target
	for i in range(target_max):
		if remaining <= 0:
			break
		var target_slot: Dictionary = target_arr[i]
		if target_slot["item_id"] == "":
			var to_move: int = mini(remaining, max_stack)
			target_arr[i] = {"item_id": item_id, "amount": to_move, "quality": quality}
			remaining -= to_move

	if remaining < slot["amount"]:
		if remaining <= 0:
			arr[index] = _empty_slot()
		else:
			slot["amount"] = remaining
		inventory_changed.emit()
		return true

	return false


## Sum a stat bonus from all equipped items' metadata.
func get_equipment_stat_bonus(stat_name: String) -> float:
	var total: float = 0.0
	for slot in inventory_equipment:
		if slot["item_id"] == "":
			continue
		var item_data: Dictionary = ItemDatabase.get_item(slot["item_id"])
		if item_data.is_empty():
			continue
		var metadata = item_data.get("metadata", {})
		if metadata is Dictionary:
			var stats = metadata.get("stats", {})
			if stats is Dictionary and stats.has(stat_name):
				total += float(stats[stat_name])
	return total


## Force cursor item back into inventory. Called when closing inventory.
func _return_cursor_item() -> void:
	if cursor_item["item_id"] == "":
		return
	var remainder: int = request_add_item(cursor_item["item_id"], cursor_item["amount"], cursor_item["quality"])
	if remainder <= 0:
		cursor_item = _empty_slot()
	else:
		cursor_item["amount"] = remainder
	cursor_item_changed.emit()


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


# --- Player stat setters ---

## Set player health, clamped to [0, max]. Emits signal.
func set_player_health(value: float) -> void:
	player_health = clampf(value, 0.0, player_max_health)
	player_health_changed.emit(player_health, player_max_health)


## Set player max health. Re-clamps current health. Emits signal.
func set_player_max_health(value: float) -> void:
	player_max_health = maxf(value, 1.0)
	player_health = clampf(player_health, 0.0, player_max_health)
	player_health_changed.emit(player_health, player_max_health)


## Set player mana, clamped to [0, max]. Emits signal.
func set_player_mana(value: float) -> void:
	player_mana = clampf(value, 0.0, player_max_mana)
	player_mana_changed.emit(player_mana, player_max_mana)


## Set player max mana. Re-clamps current mana. Emits signal.
func set_player_max_mana(value: float) -> void:
	player_max_mana = maxf(value, 0.0)
	player_mana = clampf(player_mana, 0.0, player_max_mana)
	player_mana_changed.emit(player_mana, player_max_mana)


## Set player stamina, clamped to [0, max]. Emits signal.
func set_player_stamina(value: float) -> void:
	player_stamina = clampf(value, 0.0, player_max_stamina)
	player_stamina_changed.emit(player_stamina, player_max_stamina)


## Set player max stamina. Re-clamps current stamina. Emits signal.
func set_player_max_stamina(value: float) -> void:
	player_max_stamina = maxf(value, 0.0)
	player_stamina = clampf(player_stamina, 0.0, player_max_stamina)
	player_stamina_changed.emit(player_stamina, player_max_stamina)
