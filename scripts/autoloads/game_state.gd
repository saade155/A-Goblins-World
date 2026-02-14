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
var start_depth: int = 170

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


func _ready() -> void:
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
		player_node.global_position = Vector2(0, start_depth * 32)
		print("[GameState] Player registered at start_depth=%d (y=%d)" % [start_depth, start_depth * 32])


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
	start_depth = 170
	print("[GameState] State reset for new game.")


## Returns the total playtime in seconds for the current world.
func get_total_playtime() -> float:
	return playtime_seconds
