## GameState - Shared state container.
##
## Holds references to key game objects so any system can access them without
## hardcoded node paths. This is a read-friendly registry — state CHANGES still
## go through GameServer.

extends Node

## Reference to the active player node. Set by the player on _ready().
var player: CharacterBody2D = null

## Reference to the world data (chunk system). Null until Milestone 3.
var world_data = null

## Current world seed. Used for deterministic generation.
var world_seed: int = 0


func _ready() -> void:
	print("[GameState] Initialized.")


## Register the player node. Called by the player scene on _ready().
func register_player(player_node: CharacterBody2D) -> void:
	player = player_node
	print("[GameState] Player registered: %s" % player_node.name)


## Unregister the player (e.g., on scene change or cleanup).
func unregister_player() -> void:
	player = null
	print("[GameState] Player unregistered.")
