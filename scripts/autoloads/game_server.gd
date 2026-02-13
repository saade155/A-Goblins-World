## GameServer - The authority for all game state changes.
##
## Every game action flows through this autoload. In single-player, the local
## game IS the server — but the code treats it that way. This means:
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
# Other systems (BehaviorTracker, UI, etc.) listen to these — they never call
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


func _ready() -> void:
	print("[GameServer] Initialized — acting as local authority.")


## Request to mine a tile at the given world position.
## In single-player this validates immediately and applies.
## In multiplayer this would be an RPC to the host.
func request_mine(player: Node, world_pos: Vector2i) -> void:
	print("[GameServer] request_mine from %s at %s — stub, no world data yet." % [player.name, str(world_pos)])


## Request to place a tile at the given world position.
func request_place(player: Node, world_pos: Vector2i, tile_type: int) -> void:
	print("[GameServer] request_place from %s at %s, type %d — stub." % [player.name, str(world_pos), tile_type])


## Apply damage from source to target. This is the ONLY way damage happens.
func deal_damage(source: Node, target: Node, amount: float, damage_type: String = "physical", weapon: String = "") -> void:
	print("[GameServer] deal_damage: %s -> %s for %.1f %s damage (weapon: %s) — stub." % [
		source.name if source else "null",
		target.name if target else "null",
		amount,
		damage_type,
		weapon
	])
