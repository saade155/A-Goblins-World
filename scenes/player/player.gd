## Player movement controller for the goblin character.
##
## This is the core movement script. Movement must feel tight and responsive:
## - Acceleration/deceleration (not instant velocity -- gives weight)
## - Variable jump height (hold to jump higher, release for short hop)
## - Coyote time (brief window to jump after leaving a ledge)
## - Jump buffer (press jump slightly before landing, still registers)
##
## ALL input goes through InputManager. This script NEVER calls Input directly.
## State changes that affect the world go through GameServer.

extends CharacterBody2D

# --- Movement tuning (exported for quick iteration in the editor) ---

## Horizontal movement speed in pixels/sec.
@export var SPEED: float = 240.0

## How quickly the player reaches target speed (pixels/sec^2).
@export var ACCELERATION: float = 1600.0

## How quickly the player stops when no input is held (pixels/sec^2).
@export var FRICTION: float = 1800.0

## Initial jump impulse (negative = up in Godot 2D).
@export var JUMP_VELOCITY: float = -500.0

## Downward acceleration in pixels/sec^2.
@export var GRAVITY: float = 1400.0

## Terminal velocity -- max downward speed.
@export var MAX_FALL_SPEED: float = 800.0

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

# --- Debug fly mode ---

## When true, gravity is disabled and the player can move freely in all directions.
var debug_fly: bool = false

## Movement speed in fly mode (pixels/sec).
var _fly_speed: float = 400.0

## Saved collision layer before entering fly mode (restored on exit).
var _saved_collision_layer: int = 0

## Saved collision mask before entering fly mode (restored on exit).
var _saved_collision_mask: int = 0

## Last known position for distance tracking.
var _last_position: Vector2 = Vector2.ZERO

## Whether we've initialized the last position yet.
var _distance_initialized: bool = false

# --- Camera zoom ---

## Discrete pixel-perfect zoom levels.
## 0.5x = 1 screen px per game px (wide), 1.0x = 2:1 (default),
## 1.5x = 3:1 (medium close), 2.0x = 4:1 (detail).
const ZOOM_LEVELS: Array[float] = [1.0, 2.0, 3.0]

## Current index into ZOOM_LEVELS (default = 0 → 1.0x zoom).
var _zoom_index: int = 0

# --- Animation ---

## Number of columns in the sprite sheet.
const SHEET_COLS: int = 10

## Animation definitions: row on sheet, frame count, FPS, whether it loops.
## Row map matches docs/sprite-sheet-spec.md.
const ANIM_WALK := { "row": 0, "frames": 8, "fps": 14.0, "loop": true }
const ANIM_RUN := { "row": 1, "frames": 8, "fps": 16.0, "loop": true }
const ANIM_JUMP := { "row": 2, "frames": 8, "fps": 12.0, "loop": false }
const ANIM_FALL := { "row": 2, "frames": 2, "fps": 6.0, "loop": true, "col_offset": 8 }
const ANIM_IDLE := { "row": 3, "frames": 1, "fps": 1.0, "loop": false }
const ANIM_IDLE_EAR := { "row": 4, "frames": 1, "fps": 1.0, "loop": false }
const ANIM_IDLE_BLINK := { "row": 5, "frames": 1, "fps": 1.0, "loop": false }
const ANIM_IDLE_FIDGET := { "row": 6, "frames": 1, "fps": 1.0, "loop": false }

## Idle variant pool — randomly selected after idle timer expires.
const IDLE_VARIANTS := [ANIM_IDLE_EAR, ANIM_IDLE_BLINK, ANIM_IDLE_FIDGET]

## Seconds of standing still before a random idle variant plays.
const IDLE_VARIANT_MIN_DELAY: float = 3.0
const IDLE_VARIANT_MAX_DELAY: float = 6.0

## Duration to hold an idle variant frame before returning to base idle.
const IDLE_VARIANT_HOLD_TIME: float = 0.5

## Current animation dictionary.
var _current_anim: Dictionary = ANIM_IDLE

## Current frame index within the animation.
var _anim_frame: int = 0

## Accumulator for frame timing.
var _anim_timer: float = 0.0

## Timer for idle variant triggering.
var _idle_timer: float = 0.0

## Time until next idle variant.
var _idle_next_variant_time: float = 4.0

## Whether we're currently showing an idle variant.
var _idle_variant_active: bool = false

## Timer for how long to hold the idle variant.
var _idle_variant_hold_timer: float = 0.0

## Cached reference to the Sprite2D for flipping.
@onready var _sprite: Sprite2D = $Sprite2D

## Cached reference to the Camera2D for zoom control.
@onready var _camera: Camera2D = $Camera2D

func _ready() -> void:
	# Register with GameState so other systems can find the player.
	GameState.register_player(self)

	# Snap camera to player immediately (no smooth slide from origin on load)
	var camera := $Camera2D as Camera2D
	if camera:
		camera.reset_smoothing()

	# Apply the default zoom level immediately.
	_camera.zoom = Vector2(ZOOM_LEVELS[_zoom_index], ZOOM_LEVELS[_zoom_index])

	# Listen for hotbar changes from InputManager.
	InputManager.hotbar_changed.connect(_on_hotbar_changed)

	# Initialize idle variant timer with a random delay.
	_reset_idle_timer()


func _physics_process(delta: float) -> void:
	_check_fly_toggle()

	if debug_fly:
		_handle_fly_movement()
	else:
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

	_update_animation_state()
	_advance_animation(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_index = mini(_zoom_index + 1, ZOOM_LEVELS.size() - 1)
			_camera.zoom = Vector2(ZOOM_LEVELS[_zoom_index], ZOOM_LEVELS[_zoom_index])
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_index = maxi(_zoom_index - 1, 0)
			_camera.zoom = Vector2(ZOOM_LEVELS[_zoom_index], ZOOM_LEVELS[_zoom_index])


# --- Debug fly mode ---

## Check if the fly-mode toggle was just pressed this frame and toggle state.
func _check_fly_toggle() -> void:
	if not InputManager.is_fly_toggle_just_pressed():
		return

	debug_fly = not debug_fly

	if debug_fly:
		# Save current collision settings and disable collisions.
		_saved_collision_layer = collision_layer
		_saved_collision_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
		velocity = Vector2.ZERO
		print("[Debug] Fly mode: ON")
	else:
		# Restore collision settings.
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask
		velocity = Vector2.ZERO
		print("[Debug] Fly mode: OFF")


## Handle free movement in all four directions when fly mode is active.
func _handle_fly_movement() -> void:
	var h_dir := InputManager.get_movement_direction()
	var v_dir := InputManager.get_fly_vertical_direction()
	var direction := Vector2(h_dir, v_dir)

	# Normalize so diagonal movement isn't faster.
	if direction.length() > 1.0:
		direction = direction.normalized()

	velocity = direction * _fly_speed

	# Flip sprite even in fly mode for visual consistency.
	if h_dir != 0.0:
		_sprite.flip_h = h_dir < 0.0


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


## Called when hotbar selection changes via InputManager.
## Delegates to GameServer which owns the hotbar state.
func _on_hotbar_changed(slot: int) -> void:
	GameServer.request_select_hotbar(slot)


# --- Animation ---

## Determine which animation should play based on current movement state.
func _update_animation_state() -> void:
	if debug_fly:
		# In fly mode, just use walk anim if moving, idle if not.
		var moving := velocity.length() > 10.0
		if moving:
			_play_anim(ANIM_WALK)
		else:
			_play_anim(ANIM_IDLE)
		return

	if not is_on_floor():
		if velocity.y < 0.0:
			_play_anim(ANIM_JUMP)
		else:
			_play_anim(ANIM_FALL)
		return

	var h_speed := absf(velocity.x)
	if h_speed > 10.0:
		# TODO: Use ANIM_RUN when sprint input is added.
		_play_anim(ANIM_WALK)
	else:
		_handle_idle_state()


## Handle idle state with random variant timer.
func _handle_idle_state() -> void:
	if _idle_variant_active:
		# Currently showing a variant — check if hold time is done.
		_idle_variant_hold_timer -= get_physics_process_delta_time()
		if _idle_variant_hold_timer <= 0.0:
			_idle_variant_active = false
			_reset_idle_timer()
			_play_anim(ANIM_IDLE)
		return

	# Base idle — count down to next variant.
	if _current_anim != ANIM_IDLE:
		_play_anim(ANIM_IDLE)
		_reset_idle_timer()
		return

	_idle_timer += get_physics_process_delta_time()
	if _idle_timer >= _idle_next_variant_time:
		# Trigger a random idle variant.
		var variant: Dictionary = IDLE_VARIANTS[randi() % IDLE_VARIANTS.size()]
		_play_anim(variant)
		_idle_variant_active = true
		_idle_variant_hold_timer = IDLE_VARIANT_HOLD_TIME
		_idle_timer = 0.0


## Reset the idle variant timer with a random delay.
func _reset_idle_timer() -> void:
	_idle_timer = 0.0
	_idle_next_variant_time = randf_range(IDLE_VARIANT_MIN_DELAY, IDLE_VARIANT_MAX_DELAY)


## Switch to a new animation (resets frame if animation changed).
func _play_anim(anim: Dictionary) -> void:
	if _current_anim == anim:
		return
	_current_anim = anim
	_anim_frame = 0
	_anim_timer = 0.0
	# Reset idle state when switching away from idle.
	if anim != ANIM_IDLE and not _idle_variant_active:
		_idle_timer = 0.0


## Advance the animation frame timer and update the sprite.
func _advance_animation(delta: float) -> void:
	var anim := _current_anim
	var frame_count: int = anim["frames"]

	if frame_count > 1:
		_anim_timer += delta
		var frame_duration: float = 1.0 / float(anim["fps"])
		while _anim_timer >= frame_duration:
			_anim_timer -= frame_duration
			_anim_frame += 1
			if _anim_frame >= frame_count:
				if anim.get("loop", false):
					_anim_frame = 0
				else:
					_anim_frame = frame_count - 1  # Hold last frame.

	# Calculate the sprite sheet frame index.
	var col_offset: int = anim.get("col_offset", 0)
	var sheet_frame: int = anim["row"] * SHEET_COLS + col_offset + _anim_frame
	_sprite.frame = sheet_frame
