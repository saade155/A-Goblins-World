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
@export var SPEED: float = 150.0

## Horizontal sprint speed in pixels/sec.
@export var RUN_SPEED: float = 240.0

## How quickly the player reaches target speed (pixels/sec^2).
@export var ACCELERATION: float = 1200.0

## How quickly the player stops when no input is held (pixels/sec^2).
@export var FRICTION: float = 1400.0

## Acceleration while sprinting (pixels/sec^2).
@export var RUN_ACCELERATION: float = 1600.0

## Friction while sprinting — more slippery (pixels/sec^2).
@export var RUN_FRICTION: float = 800.0

## Initial jump impulse (negative = up in Godot 2D).
@export var JUMP_VELOCITY: float = -350.0

## Downward acceleration in pixels/sec^2.
@export var GRAVITY: float = 1000.0

## Terminal velocity -- max downward speed.
@export var MAX_FALL_SPEED: float = 600.0

## Seconds after leaving a ledge during which a jump is still allowed.
@export var COYOTE_TIME: float = 0.1

## Seconds before landing during which a jump press is remembered and applied.
@export var JUMP_BUFFER_TIME: float = 0.1

## How much upward velocity to keep when jump is released early (0.0-1.0).
## Lower = shorter hops. 0.4 means a tap keeps 40% of upward speed.
@export var JUMP_CUT_MULTIPLIER: float = 0.4

## Maximum horizontal pixels to nudge when clipping a corner during jump/fall.
@export var CORNER_CORRECTION: float = 6.0

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
## Manual camera smoothing factor (higher = snappier, lower = smoother).
const CAMERA_SMOOTH_SPEED: float = 15.0

const ZOOM_LEVELS: Array[float] = [1.0, 2.0, 3.0]

## Current index into ZOOM_LEVELS (default = 1 → 2.0x zoom).
var _zoom_index: int = 1

# --- UI Panels ---

## Skill panel scene — self-contained CanvasLayer, handles its own input toggling.
var _skill_panel_scene: PackedScene = preload("res://scenes/ui/skill_panel.tscn")

# --- Animation ---

## Number of columns in the sprite sheet.
const SHEET_COLS: int = 8

## Animation definitions: row on sheet, frame count, FPS, whether it loops.
const ANIMATIONS := {
	"idle":       { "row": 0, "frames": 4, "fps": 8.0, "loop": true },
	"idle_2":     { "row": 1, "frames": 4, "fps": 8.0, "loop": true },
	"idle_3":     { "row": 2, "frames": 4, "fps": 8.0, "loop": true },
	"idle_4":     { "row": 3, "frames": 4, "fps": 8.0, "loop": true },
	"walk":       { "row": 4, "frames": 6, "fps": 10.0, "loop": true },
	"run":        { "row": 5, "frames": 6, "fps": 16.0, "loop": true },
	"jump":       { "row": 6, "frames": 4, "fps": 10.0, "loop": false },
	"fall":       { "row": 7, "frames": 4, "fps": 8.0, "loop": true },
	"land":       { "row": 8, "frames": 4, "fps": 20.0, "loop": false },
	"walk_back":  { "row": 12, "frames": 6, "fps": 10.0, "loop": true },
	"climb_back": { "row": 13, "frames": 6, "fps": 10.0, "loop": true },
	"walk_front": { "row": 14, "frames": 6, "fps": 10.0, "loop": true },
}

## Idle variant pool — randomly selected after idle timer expires.
const IDLE_VARIANTS: Array[String] = ["idle_2", "idle_3", "idle_4"]

## Seconds of standing still before a random idle variant plays.
const IDLE_VARIANT_MIN_DELAY: float = 3.0
const IDLE_VARIANT_MAX_DELAY: float = 6.0

## Duration to hold an idle variant frame before returning to base idle.
const IDLE_VARIANT_HOLD_TIME: float = 0.5

## Current animation name (key into ANIMATIONS).
var _current_anim_name: String = "idle"

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

## Whether we're currently in the landing animation.
var _landing: bool = false

## Timer for how long to hold the idle variant.
var _idle_variant_hold_timer: float = 0.0

## All body layer sprites, updated in lockstep.
@onready var _sprites: Array[Sprite2D] = [
	$SpriteStack/BackArm,
	$SpriteStack/BackLeg,
	$SpriteStack/FrontLeg,
	$SpriteStack/Belt,
	$SpriteStack/Chest,
	$SpriteStack/Head,
	$SpriteStack/FrontArm,
]

# --- Equipment visuals ---

## Maps body layer name to index in _sprites array.
const LAYER_NAME_TO_INDEX: Dictionary = {
	"back_arm": 0, "back_leg": 1, "front_leg": 2,
	"belt": 3, "chest": 4, "head": 5, "front_arm": 6,
}

## Active overlay sprites per equipment slot: {slot_int: [Sprite2D, ...]}.
var _equipment_overlays: Dictionary = {}

## Saved base textures for replace-mode equipment: {sprite_index: Texture2D}.
var _base_textures: Dictionary = {}

## Tracks which sprite indices are replaced by which slot: {sprite_index: slot_int}.
var _replaced_by_slot: Dictionary = {}

## Cached reference to the Camera2D for zoom control.
@onready var _camera: Camera2D = $Camera2D

func _ready() -> void:
	# Tighten floor detection: default 45° lets Godot treat wall collisions as "floor".
	# 20° is plenty for a rectangular tile game where floors are perfectly flat.
	floor_max_angle = deg_to_rad(20.0)

	# Register with GameState so other systems can find the player.
	GameState.register_player(self)
	add_to_group("player")

	# Snap camera to player immediately (no smooth slide from origin on load)
	var camera := $Camera2D as Camera2D
	if camera:
		camera.reset_smoothing()
		camera.global_position = global_position

	# Apply the default zoom level immediately.
	_camera.zoom = Vector2(ZOOM_LEVELS[_zoom_index], ZOOM_LEVELS[_zoom_index])

	# Listen for hotbar changes from InputManager.
	InputManager.hotbar_changed.connect(_on_hotbar_changed)

	# Initialize idle variant timer with a random delay.
	_reset_idle_timer()

	# Add the skill panel UI (self-contained CanvasLayer with its own input handling).
	var skill_panel = _skill_panel_scene.instantiate()
	add_child(skill_panel)

	# Inventory screen
	var inventory_screen := CanvasLayer.new()
	inventory_screen.set_script(preload("res://scenes/ui/inventory_screen.gd"))
	add_child(inventory_screen)

	# Equipment visuals — connect signal and apply any already-equipped items (load from save).
	GameServer.equipment_changed.connect(_on_equipment_changed)
	_apply_all_equipment()


func _physics_process(delta: float) -> void:
	if not DebugConsole.console_open:
		_check_fly_toggle()

	if debug_fly:
		_handle_fly_movement()
	elif GameServer.inventory_open or DebugConsole.console_open:
		# Inventory/console open: still apply gravity and decelerate, but skip player input.
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	else:
		_apply_gravity(delta)
		_update_coyote_timer(delta)
		_update_jump_buffer(delta)
		_handle_jump()
		_handle_horizontal_movement(delta)
		_apply_variable_jump_gravity(delta)

	move_and_slide()
	_apply_corner_correction()

	# Snap sprite visuals to nearest whole pixel to prevent sub-pixel shimmering.
	# Physics stays at full precision — only the visual offset compensates.
	var frac := Vector2(
		global_position.x - roundf(global_position.x),
		global_position.y - roundf(global_position.y)
	)
	$SpriteStack.position = -frac

	# Manual camera smoothing with pixel snap.
	# Built-in smoothing causes sub-pixel positions that blur everything.
	var cam_target := global_position
	var cam_current := _camera.global_position
	var cam_smoothed := cam_current.lerp(cam_target, 1.0 - exp(-CAMERA_SMOOTH_SPEED * delta))
	_camera.global_position = Vector2(roundf(cam_smoothed.x), roundf(cam_smoothed.y))

	# Track floor state for next frame's coyote time calculation.
	_was_on_floor = is_on_floor()

	_track_movement_distance()

	_update_animation_state()
	_advance_animation(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		_zoom_index = mini(_zoom_index + 1, ZOOM_LEVELS.size() - 1)
		_camera.zoom = Vector2(ZOOM_LEVELS[_zoom_index], ZOOM_LEVELS[_zoom_index])
	elif event.is_action_pressed("zoom_out"):
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
		var flip := h_dir < 0.0
		for sprite in _sprites:
			sprite.flip_h = flip
		for overlays in _equipment_overlays.values():
			for overlay in overlays:
				overlay.flip_h = flip


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



## Horizontal movement with acceleration and friction.
## Feels weighty: the goblin doesn't start or stop instantly.
func _handle_horizontal_movement(delta: float) -> void:
	var direction := InputManager.get_movement_direction()
	var sprinting: bool = InputManager.is_sprint_pressed()

	if direction != 0.0:
		# Use sprint or walk values based on input.
		var target_speed := RUN_SPEED if sprinting else SPEED
		var accel := RUN_ACCELERATION if sprinting else ACCELERATION
		var target_velocity := direction * target_speed
		velocity.x = move_toward(velocity.x, target_velocity, accel * delta)

		# Flip sprite to face movement direction.
		var flip := direction < 0.0
		for sprite in _sprites:
			sprite.flip_h = flip
		for overlays in _equipment_overlays.values():
			for overlay in overlays:
				overlay.flip_h = flip
	else:
		# No input -- apply friction to slow down. Sprint friction is more slippery.
		var fric := RUN_FRICTION if sprinting else FRICTION
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)


## Variable jump height: when the player releases jump while still rising,
## immediately cut upward velocity. This makes tap = short hop, hold = full jump.
## The cut happens once on the frame jump is released, not gradually.
func _apply_variable_jump_gravity(_delta: float) -> void:
	if _is_jumping and not InputManager.is_jump_pressed():
		_is_jumping = false
		if velocity.y < 0.0:
			velocity.y *= JUMP_CUT_MULTIPLIER


## Corner correction: when jumping into a ceiling corner or falling onto a ledge corner,
## nudge the player horizontally to clear or land cleanly. Makes platforming feel forgiving.
func _apply_corner_correction() -> void:
	if get_slide_collision_count() == 0:
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()

		# Ceiling corner correction (jumping upward, hit ceiling)
		if velocity.y < 0.0 and normal.y > 0.5 and absf(normal.x) < 0.3:
			# Hit ceiling — try nudging left or right to slip past
			for nudge_dir in [1.0, -1.0]:
				for nudge_px in [2.0, 4.0, 6.0]:
					if nudge_px > CORNER_CORRECTION:
						break
					var test_motion := Vector2(nudge_dir * nudge_px, velocity.y * get_physics_process_delta_time())
					var test_result := move_and_collide(test_motion, true)
					if test_result == null:
						# Clear path — apply the nudge
						global_position.x += nudge_dir * nudge_px
						velocity.y = velocity.y  # Preserve upward momentum
						return



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
		var moving := velocity.length() > 10.0
		if moving:
			if InputManager.is_sprint_pressed():
				_play_anim("run")
			else:
				_play_anim("walk")
		else:
			_play_anim("idle")
		return

	if not is_on_floor():
		_landing = false
		if velocity.y < 0.0:
			_play_anim("jump")
		else:
			_play_anim("fall")
		return

	# Just landed — trigger land animation if not moving.
	var h_speed := absf(velocity.x)
	if not _was_on_floor and is_on_floor():
		if h_speed <= 10.0:
			_landing = true
			_play_anim("land")
			return
		# If moving when landing, skip land anim — go straight to walk/run.

	# Currently in landing animation — let it finish unless movement cancels it.
	if _landing:
		if h_speed > 10.0:
			_landing = false
			# Movement cancels land — fall through to normal walk/run logic.
		else:
			# Check if land animation finished (non-looping, on last frame).
			var anim: Dictionary = ANIMATIONS["land"]
			if _anim_frame >= anim["frames"] - 1:
				_landing = false
				# Fall through to idle logic.
			else:
				return  # Still playing land animation.

	if h_speed > 10.0:
		if InputManager.is_sprint_pressed():
			_play_anim("run")
		else:
			_play_anim("walk")
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
			_play_anim("idle")
		return

	# Base idle — count down to next variant.
	if _current_anim_name != "idle":
		_play_anim("idle")
		_reset_idle_timer()
		return

	_idle_timer += get_physics_process_delta_time()
	if _idle_timer >= _idle_next_variant_time:
		# Trigger a random idle variant.
		var variant: String = IDLE_VARIANTS[randi() % IDLE_VARIANTS.size()]
		_play_anim(variant)
		_idle_variant_active = true
		_idle_variant_hold_timer = IDLE_VARIANT_HOLD_TIME
		_idle_timer = 0.0


## Reset the idle variant timer with a random delay.
func _reset_idle_timer() -> void:
	_idle_timer = 0.0
	_idle_next_variant_time = randf_range(IDLE_VARIANT_MIN_DELAY, IDLE_VARIANT_MAX_DELAY)


## Switch to a new animation (resets frame if animation changed).
func _play_anim(anim_name: String) -> void:
	if _current_anim_name == anim_name:
		return
	_current_anim_name = anim_name
	_anim_frame = 0
	_anim_timer = 0.0
	if anim_name != "land":
		_landing = false
	if anim_name != "idle" and not _idle_variant_active:
		_idle_timer = 0.0


## Advance the animation frame timer and update the sprite.
func _advance_animation(delta: float) -> void:
	var anim: Dictionary = ANIMATIONS[_current_anim_name]
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

	var sheet_frame: int = anim["row"] * SHEET_COLS + _anim_frame
	for sprite in _sprites:
		sprite.frame = sheet_frame
	for overlays in _equipment_overlays.values():
		for overlay in overlays:
			overlay.frame = sheet_frame


# --- Equipment visuals ---


## Apply visuals for all currently equipped items (used on load).
func _apply_all_equipment() -> void:
	for slot in range(GameServer.EQUIP_SLOTS):
		var equip: Dictionary = GameServer.get_equipment_slot(slot)
		if equip.get("item_id", "") != "":
			_on_equipment_changed(slot)


## Called when equipment changes — update the player's sprite visuals.
func _on_equipment_changed(slot: int) -> void:
	_clear_equipment_visuals(slot)

	var equip: Dictionary = GameServer.get_equipment_slot(slot)
	var item_id: String = equip.get("item_id", "")
	if item_id == "":
		return

	var mode: String = ItemDatabase.get_equip_mode(item_id)
	var layers: Array = ItemDatabase.get_equip_layers(item_id)
	print("[Player] Equipment changed slot %d: item=%s mode=%s layers=%s" % [slot, item_id, mode, str(layers)])

	for layer_name in layers:
		if not LAYER_NAME_TO_INDEX.has(layer_name):
			print("[Player]   Layer '%s' not in LAYER_NAME_TO_INDEX, skipping" % layer_name)
			continue
		var sprite_idx: int = LAYER_NAME_TO_INDEX[layer_name]
		var tex_path: String = "res://assets/items/%s/%s.png" % [item_id, layer_name]
		if not ResourceLoader.exists(tex_path):
			push_warning("[Player] Equipment texture not found: %s" % tex_path)
			continue
		var tex: Texture2D = load(tex_path)
		print("[Player]   Layer '%s' idx=%d tex=%s loaded=%s" % [layer_name, sprite_idx, tex_path, tex != null])

		if mode == "replace":
			# Save the base texture so we can restore it on unequip.
			if not _base_textures.has(sprite_idx):
				_base_textures[sprite_idx] = _sprites[sprite_idx].texture
			_sprites[sprite_idx].texture = tex
			_replaced_by_slot[sprite_idx] = slot
		else:
			# Overlay: create a new Sprite2D on top of the body layer.
			var body_sprite: Sprite2D = _sprites[sprite_idx]
			var overlay := Sprite2D.new()
			overlay.texture = tex
			overlay.hframes = body_sprite.hframes
			overlay.vframes = body_sprite.vframes
			overlay.offset = body_sprite.offset
			overlay.z_index = body_sprite.z_index + 1
			overlay.frame = body_sprite.frame
			overlay.flip_h = body_sprite.flip_h
			$SpriteStack.add_child(overlay)
			if not _equipment_overlays.has(slot):
				_equipment_overlays[slot] = []
			_equipment_overlays[slot].append(overlay)


## Remove visuals for a given equipment slot.
func _clear_equipment_visuals(slot: int) -> void:
	# Remove overlay sprites.
	if _equipment_overlays.has(slot):
		for overlay in _equipment_overlays[slot]:
			overlay.queue_free()
		_equipment_overlays.erase(slot)

	# Restore replaced textures.
	var to_erase: Array[int] = []
	for sprite_idx in _replaced_by_slot:
		if _replaced_by_slot[sprite_idx] == slot:
			if _base_textures.has(sprite_idx):
				_sprites[sprite_idx].texture = _base_textures[sprite_idx]
				_base_textures.erase(sprite_idx)
			to_erase.append(sprite_idx)
	for idx in to_erase:
		_replaced_by_slot.erase(idx)
