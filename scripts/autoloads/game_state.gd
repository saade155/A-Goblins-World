## GameState - Shared state container.
##
## Holds references to key game objects so any system can access them without
## hardcoded node paths. This is a read-friendly registry -- state CHANGES still
## go through GameServer.

extends Node

## Reference to the active player node. Set by the player on _ready().
var player: CharacterBody2D = null

## Reference to the world data (chunk system). Set by ChunkManager on _ready().
var world_data = null

## Reference to the world generator. Set by ChunkManager on _ready().
## Used by the map system to query tiles in ungenerated chunks (dev mode).
var world_generator: WorldGenerator = null

## Current world seed. Used for deterministic generation.
## Set by new game menu or loaded from a save file.
var world_seed: int = 0

## Starting depth in tiles. Higher = deeper underground.
## Easy: 80, Normal: 170, Hard: 280
var start_depth: int = 50

## Saved player position from a loaded game. Null = new game (use start_depth).
var saved_player_position: Variant = null

## Whether a game session is currently active (in-world, not in menus).
var is_game_active: bool = false

## The slot folder name for the current world save (e.g. "slot_1").
var world_slot_name: String = ""

## The user-facing display name for the current world (e.g. "My World").
var world_display_name: String = ""

## Total playtime for the current world in seconds.
var playtime_seconds: float = 0.0

## World size preset. -1 = legacy/infinite, 0+ = WorldData.WorldSize enum.
var world_size: int = -1


func _ready() -> void:
	# Cap physics catch-up to prevent snap-to-floor during frame stutters.
	# Default is 8 — too aggressive for a single-player game.
	Engine.max_physics_steps_per_frame = 4
	print("[GameState] Initialized.")


func _process(delta: float) -> void:
	if is_game_active and not get_tree().paused:
		playtime_seconds += delta


## Register the player node. Called by the player scene on _ready().
## Repositions the player to the configured start_depth.
func register_player(player_node: CharacterBody2D) -> void:
	player = player_node
	if saved_player_position != null:
		player_node.global_position = saved_player_position
		print("[GameState] Player restored to saved position: %s" % str(saved_player_position))
	else:
		var center_x: float = _get_world_center_x()
		player_node.global_position = Vector2(center_x, start_depth * 16)
		print("[GameState] Player registered at center (%.0f, %d)" % [center_x, start_depth * 16])

	# Safety check: nudge up if spawning inside solid tiles
	_ensure_safe_spawn(player_node)


## If the player would spawn inside solid tiles, nudge upward to the nearest
## 2-tile-tall open area. Falls back to spawn position if no air found.
func _ensure_safe_spawn(player_node: CharacterBody2D) -> void:
	if not world_data:
		return

	var tile_size: int = 16
	var pos: Vector2 = player_node.global_position
	# Convert pixel position to tile coordinates (player origin is at feet-ish area)
	var tile_x: int = floori(pos.x / tile_size)
	var tile_y: int = floori(pos.y / tile_size)

	# Check if the two tiles at player position (feet + head) are clear
	var feet_pos := Vector2i(tile_x, tile_y)
	var head_pos := Vector2i(tile_x, tile_y - 1)

	if not world_data.has_tile(feet_pos) and not world_data.has_tile(head_pos):
		return  # Position is safe

	# Scan upward for a 2-tile-tall gap (max 64 tiles to avoid infinite loop)
	print("[GameState] Player spawn blocked by tiles at %s, scanning upward..." % str(feet_pos))
	for offset in range(1, 64):
		var check_feet := Vector2i(tile_x, tile_y - offset)
		var check_head := Vector2i(tile_x, tile_y - offset - 1)
		if not world_data.has_tile(check_feet) and not world_data.has_tile(check_head):
			player_node.global_position = Vector2(pos.x, check_feet.y * tile_size)
			print("[GameState] Player nudged to safe position: %s" % str(player_node.global_position))
			return

	# Fallback: spawn at world center at start_depth
	var center_x: float = _get_world_center_x()
	player_node.global_position = Vector2(center_x, start_depth * tile_size)
	print("[GameState] Could not find safe position, falling back to world center.")


## Get the horizontal center of the world in pixels. Falls back to 0 if world_data is unavailable.
func _get_world_center_x() -> float:
	if world_data and world_data.world_width > 0:
		return (world_data.world_width / 2.0) * 16.0
	return 0.0


## Unregister the player (e.g., on scene change or cleanup).
func unregister_player() -> void:
	player = null
	print("[GameState] Player unregistered.")


## Reset all state to defaults. Called when returning to main menu or starting fresh.
func reset_for_new_game() -> void:
	player = null
	world_data = null
	world_generator = null
	saved_player_position = null
	playtime_seconds = 0.0
	is_game_active = false
	world_slot_name = ""
	world_display_name = ""
	world_seed = 0
	start_depth = 50
	world_size = 0  # Default to SMALL for new games
	print("[GameState] State reset for new game.")


## Returns the total playtime in seconds for the current world.
func get_total_playtime() -> float:
	return playtime_seconds
