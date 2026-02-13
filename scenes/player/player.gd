## Player movement controller for the goblin character.
##
## This is the core movement script. Movement must feel tight and responsive:
## - Acceleration/deceleration (not instant velocity -- gives weight)
## - Variable jump height (hold to jump higher, release for short hop)
## - Coyote time (brief window to jump after leaving a ledge)
## - Jump buffer (press jump slightly before landing, still registers)
##
## Also includes a simple inventory system (array-based, no UI yet).
##
## ALL input goes through InputManager. This script NEVER calls Input directly.
## State changes that affect the world go through GameServer.

extends CharacterBody2D

# --- Movement tuning (exported for quick iteration in the editor) ---

## Horizontal movement speed in pixels/sec.
@export var SPEED: float = 120.0

## How quickly the player reaches target speed (pixels/sec^2).
@export var ACCELERATION: float = 800.0

## How quickly the player stops when no input is held (pixels/sec^2).
@export var FRICTION: float = 900.0

## Initial jump impulse (negative = up in Godot 2D).
@export var JUMP_VELOCITY: float = -250.0

## Downward acceleration in pixels/sec^2.
@export var GRAVITY: float = 700.0

## Terminal velocity -- max downward speed.
@export var MAX_FALL_SPEED: float = 400.0

## Seconds after leaving a ledge during which a jump is still allowed.
@export var COYOTE_TIME: float = 0.1

## Seconds before landing during which a jump press is remembered and applied.
@export var JUMP_BUFFER_TIME: float = 0.1

## Gravity multiplier when the player releases jump early (makes short hops).
## Lower = more dramatic variable jump height.
@export var VARIABLE_JUMP_MULTIPLIER: float = 0.5

# --- Internal state ---

## Time since the player last stood on the floor (for coyote time).
var _coyote_timer: float = 0.0

## Time since the player last pressed jump (for jump buffer).
var _jump_buffer_timer: float = 0.0

## True while the player is in a jump that hasn't been released.
## Used to distinguish "going up because we jumped" from other upward motion.
var _is_jumping: bool = false

## Tracks whether we were on the floor last frame (for coyote time edge detection).
var _was_on_floor: bool = false

## Last known position for distance tracking.
var _last_position: Vector2 = Vector2.ZERO

## Whether we've initialized the last position yet.
var _distance_initialized: bool = false

## Cached reference to the Sprite2D for flipping.
@onready var _sprite: Sprite2D = $Sprite2D

# --- Inventory ---

## Simple inventory: each entry is {"item": String, "amount": int}.
var inventory: Array[Dictionary] = []

## Currently selected hotbar slot (0-4). Tracks which block type to place.
var selected_hotbar: int = 0

## Maps hotbar slot index to a display name for debug printing.
var _hotbar_names: Array[String] = ["Dirt", "Stone", "Iron Ore", "(empty)", "(empty)"]


func _ready() -> void:
	# Register with GameState so other systems can find the player.
	GameState.register_player(self)

	# Snap camera to player immediately (no smooth slide from origin on load)
	var camera := $Camera2D as Camera2D
	if camera:
		camera.reset_smoothing()

	# Listen for hotbar changes from InputManager.
	InputManager.hotbar_changed.connect(_on_hotbar_changed)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_update_coyote_timer(delta)
	_update_jump_buffer(delta)
	_handle_jump()
	_handle_horizontal_movement(delta)
	_apply_variable_jump_gravity(delta)

	move_and_slide()

	# Track floor state for next frame's coyote time calculation.
	_was_on_floor = is_on_floor()

	_track_movement_distance()


# --- Movement ---

## Apply gravity, capped at MAX_FALL_SPEED.
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)


## Coyote time: track how long since the player was last grounded.
## Resets when on floor. Only starts counting when the player WALKS off a ledge
## (not when they jump -- jumping immediately consumes coyote time).
func _update_coyote_timer(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer -= delta


## Jump buffer: track how long since the player last pressed jump.
## If they press jump slightly before landing, the buffer remembers it.
func _update_jump_buffer(delta: float) -> void:
	if InputManager.is_jump_just_pressed():
		_jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		_jump_buffer_timer -= delta


## Handle the actual jump.
## A jump is allowed if:
##   1. The player has jump buffered (pressed recently), AND
##   2. They are on the floor OR within coyote time.
func _handle_jump() -> void:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_is_jumping = true
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0  # Consume coyote time so you can't double-jump.

	# Detect jump release -- stop tracking the jump for variable height.
	if _is_jumping and not InputManager.is_jump_pressed():
		_is_jumping = false


## Horizontal movement with acceleration and friction.
## Feels weighty: the goblin doesn't start or stop instantly.
func _handle_horizontal_movement(delta: float) -> void:
	var direction := InputManager.get_movement_direction()

	if direction != 0.0:
		# Accelerate toward target speed.
		var target_velocity := direction * SPEED
		velocity.x = move_toward(velocity.x, target_velocity, ACCELERATION * delta)

		# Flip sprite to face movement direction.
		_sprite.flip_h = direction < 0.0
	else:
		# No input -- apply friction to slow down.
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)


## Variable jump height: if the player releases jump while still moving upward,
## increase effective gravity so the jump is cut short. This lets tap = short hop
## and hold = full jump.
func _apply_variable_jump_gravity(delta: float) -> void:
	if velocity.y < 0.0 and not InputManager.is_jump_pressed():
		# Player is moving upward but NOT holding jump -- apply extra gravity
		# to cut the jump short. We apply additional gravity on top of what
		# _apply_gravity already did, scaled by the multiplier.
		# The multiplier represents how much EXTRA gravity to add (0.5 = 50% more).
		velocity.y += GRAVITY * VARIABLE_JUMP_MULTIPLIER * delta
		# Re-cap in case this pushed us past terminal velocity.
		velocity.y = minf(velocity.y, MAX_FALL_SPEED)


## Track cumulative movement distance for BehaviorTracker.
func _track_movement_distance() -> void:
	if not _distance_initialized:
		_last_position = global_position
		_distance_initialized = true
		return
	var dist: float = global_position.distance_to(_last_position)
	if dist > 0.5:  # Ignore micro-jitter
		var current = BehaviorTracker.get_stat("movement_distance")
		if current == null:
			current = 0.0
		BehaviorTracker.set_stat("movement_distance", float(current) + dist)
	_last_position = global_position


# --- Inventory ---

## Add an item to the inventory. Stacks with existing entries of the same type.
func add_item(item_type: String, amount: int) -> void:
	for entry in inventory:
		if entry["item"] == item_type:
			entry["amount"] += amount
			_print_inventory()
			return

	# New item type -- add a new entry.
	inventory.append({"item": item_type, "amount": amount})
	_print_inventory()


## Remove an item from the inventory. Returns false if not enough.
func remove_item(item_type: String, amount: int) -> bool:
	for i in range(inventory.size()):
		if inventory[i]["item"] == item_type:
			if inventory[i]["amount"] >= amount:
				inventory[i]["amount"] -= amount
				if inventory[i]["amount"] <= 0:
					inventory.remove_at(i)
				_print_inventory()
				return true
			else:
				return false
	return false


## Check if the player has at least the specified amount of an item.
func has_item(item_type: String, amount: int = 1) -> bool:
	for entry in inventory:
		if entry["item"] == item_type and entry["amount"] >= amount:
			return true
	return false


## Get the count of a specific item type in the inventory.
func get_item_count(item_type: String) -> int:
	for entry in inventory:
		if entry["item"] == item_type:
			return entry["amount"]
	return 0


## Debug print inventory contents.
func _print_inventory() -> void:
	if inventory.is_empty():
		print("[Inventory] Empty")
		return
	var items_str := ""
	for entry in inventory:
		if items_str != "":
			items_str += ", "
		items_str += "%s x%d" % [entry["item"], entry["amount"]]
	print("[Inventory] %s" % items_str)


## Called when hotbar selection changes via InputManager.
func _on_hotbar_changed(slot: int) -> void:
	selected_hotbar = slot
	var name_str: String = _hotbar_names[slot] if slot < _hotbar_names.size() else "(unknown)"
	print("[Hotbar] Selected slot %d: %s" % [slot + 1, name_str])
