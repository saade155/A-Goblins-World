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
## Generated randomly on startup; will be saveable/loadable later.
var world_seed: int = 0

## Starting depth in tiles. Higher = deeper underground.
## Easy: 80, Normal: 170, Hard: 280
var start_depth: int = 170

## Saved player position from a loaded game. Null = new game (use start_depth).
var saved_player_position: Variant = null


func _ready() -> void:
	# Generate a random seed for this world
	randomize()
	world_seed = randi()
	print("[GameState] Initialized. World seed: %d" % world_seed)


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
