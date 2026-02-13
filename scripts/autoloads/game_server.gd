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

# --- World data ---

## Reference to the authoritative world data. Set by the world scene via initialize_world().
var world_data: WorldData = null

## Maximum distance (in pixels) a player can be from a tile to interact with it.
const INTERACTION_RANGE: float = 48.0  # 3 tiles * 16 pixels

## Tile size in pixels — must match the TileSet and WorldData coordinate system.
const TILE_SIZE: int = 16


func _ready() -> void:
	print("[GameServer] Initialized -- acting as local authority.")


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

	# Validate: player is close enough.
	var tile_center := Vector2(world_pos.x * TILE_SIZE + TILE_SIZE / 2.0, world_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
	var player_pos := (player as Node2D).global_position
	var distance := player_pos.distance_to(tile_center)
	if distance > INTERACTION_RANGE:
		return false

	# Remove any torch at this position (can't have torch and tile at same spot)
	if world_data.has_torch(world_pos):
		world_data.remove_torch(world_pos)
		torch_removed.emit(world_pos)

	# Valid place -- set tile in world data.
	world_data.set_tile(world_pos, tile_type)

	# Emit signal so the world scene can update visuals.
	tile_placed.emit(world_pos, tile_type)

	print("[GameServer] Tile placed at %s (type %d)" % [str(world_pos), tile_type])
	return true


## Request to collect an item and add it to the player's inventory.
func request_collect_item(player: Node, item_type: String, amount: int) -> void:
	# Add to player's inventory if the player has the add_item method.
	if player.has_method("add_item"):
		player.add_item(item_type, amount)

	# Emit signal for BehaviorTracker and other listeners.
	item_collected.emit(item_type, amount)

	print("[GameServer] Item collected: %s x%d by %s" % [item_type, amount, player.name])


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
## Returns true if placement was successful.
func request_place_torch(player: Node, world_pos: Vector2i) -> bool:
	if world_data == null:
		return false
	# Cannot place torch on a solid tile
	if world_data.has_tile(world_pos):
		return false
	# Cannot place torch where one already exists
	if world_data.has_torch(world_pos):
		return false
	# Validate: player is close enough
	var tile_center := Vector2(world_pos.x * TILE_SIZE + TILE_SIZE / 2.0, world_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
	var player_pos := (player as Node2D).global_position
	if player_pos.distance_to(tile_center) > INTERACTION_RANGE:
		return false
	world_data.add_torch(world_pos)
	torch_placed.emit(world_pos)
	return true


## Request to remove a torch at a world tile position.
## Returns true if removal was successful.
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
	torch_removed.emit(world_pos)
	return true
