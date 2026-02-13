## DroppedItem - A collectible item entity that spawns when tiles are mined.
##
## Spawns with a small bounce, falls via gravity, and is picked up when the
## player enters the PickupArea. Pickup goes through GameServer.request_collect_item().

extends CharacterBody2D

## The type of item (e.g., "dirt", "stone", "iron_ore").
var item_type: String = ""

## How many of this item the pickup gives.
var amount: int = 1

## Spawn position, stored before the node enters the tree.
var _spawn_pos: Vector2 = Vector2.ZERO

## Initial velocity set during initialization, applied once in _ready.
var _initial_velocity: Vector2 = Vector2.ZERO

## Gravity applied to the dropped item.
const GRAVITY: float = 400.0

## Maximum fall speed.
const MAX_FALL_SPEED: float = 300.0

## Cached reference to the sprite for setting color.
@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	# Apply spawn position and velocity now that we're in the tree.
	global_position = _spawn_pos
	velocity = _initial_velocity

	# Set the sprite color based on item type using TileData colors.
	var tile_type: int = TileDatabase.get_tile_from_item(item_type)
	var props: Dictionary = TileDatabase.get_properties(tile_type)
	if not props.is_empty():
		_sprite.self_modulate = props.get("color", Color.WHITE)


func _physics_process(delta: float) -> void:
	# Apply gravity.
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	else:
		# Stop horizontal sliding on the floor with friction.
		velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)

	move_and_slide()


## Initialize the dropped item with type, count, and spawn position.
## Must be called BEFORE adding the node to the scene tree.
## Applies a small random bounce velocity for visual flair.
func initialize(type: String, count: int, spawn_pos: Vector2) -> void:
	item_type = type
	amount = count
	_spawn_pos = spawn_pos

	# Small random upward bounce with slight horizontal spread.
	_initial_velocity = Vector2(
		randf_range(-30.0, 30.0),  # Horizontal randomness
		randf_range(-120.0, -60.0)  # Upward bounce
	)


## Called when a body enters the PickupArea. If it's the player, collect the item.
func _on_pickup_area_body_entered(body: Node2D) -> void:
	if body == GameState.player:
		GameServer.request_collect_item(body, item_type, amount)
		queue_free()
