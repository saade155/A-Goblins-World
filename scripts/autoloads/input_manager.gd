## InputManager - Input abstraction layer.
##
## ALL input reading goes through this autoload. Player scripts NEVER call
## Input directly. This abstraction exists so that in multiplayer (Milestone 17),
## input can come from the network instead of the local keyboard/gamepad.
##
## Usage in player scripts:
##   var dir = InputManager.get_movement_direction()
##   if InputManager.is_jump_just_pressed():
##       jump()

extends Node

# --- Signals ---
# Other systems can react to input events without polling.

## Emitted the frame jump is pressed.
signal jump_pressed

## Emitted the frame jump is released.
signal jump_released

## Emitted when the hotbar selection changes.
signal hotbar_changed(slot: int)

## Emitted the frame pause is pressed.
signal pause_pressed


## Track previous jump state to detect edges for signals.
var _jump_held_last_frame: bool = false

## Currently selected hotbar slot (0-9). -1 means nothing selected.
var _selected_hotbar: int = 0


func _ready() -> void:
	print("[InputManager] Initialized -- reading from local input.")


func _process(_delta: float) -> void:
	# Emit jump signals on edges.
	var jump_held := Input.is_action_pressed("jump")

	if jump_held and not _jump_held_last_frame:
		jump_pressed.emit()
	elif not jump_held and _jump_held_last_frame:
		jump_released.emit()

	_jump_held_last_frame = jump_held

	# Emit pause signal on press.
	if Input.is_action_just_pressed("pause"):
		pause_pressed.emit()

	# Check hotbar number keys (1-9,0 map to slots 0-9).
	for i in range(10):
		var action_name := "hotbar_%d" % (i + 1)
		if Input.is_action_just_pressed(action_name):
			_selected_hotbar = i
			hotbar_changed.emit(i)


# --- Movement input ---

## Returns the horizontal movement direction as a float.
## -1.0 = full left, 0.0 = no input, 1.0 = full right.
## Supports analog input if a gamepad is connected.
func get_movement_direction() -> float:
	return Input.get_axis("move_left", "move_right")


## Returns true if the jump action is currently held down.
func is_jump_pressed() -> bool:
	return Input.is_action_pressed("jump")


## Returns true only on the frame the jump action was first pressed.
func is_jump_just_pressed() -> bool:
	return Input.is_action_just_pressed("jump")


## Returns true only on the frame the jump action was released.
func is_jump_just_released() -> bool:
	return Input.is_action_just_released("jump")


# --- Mining / placement input ---

## Returns true if the mine action (left mouse) is currently held down.
func is_mine_pressed() -> bool:
	return Input.is_action_pressed("mine")


## Returns true only on the frame the mine action was first pressed.
func is_mine_just_pressed() -> bool:
	return Input.is_action_just_pressed("mine")


## Returns true only on the frame the place action (right mouse) was first pressed.
func is_place_just_pressed() -> bool:
	return Input.is_action_just_pressed("place")


## Returns the currently selected hotbar slot index (0-9).
func get_selected_hotbar() -> int:
	return _selected_hotbar


# --- UI input ---

## Returns true only on the frame the map toggle key was pressed.
func is_map_toggle_just_pressed() -> bool:
	return Input.is_action_just_pressed("toggle_map")


## Returns true only on the frame the debug fog toggle key was pressed.
func is_debug_fog_toggle_just_pressed() -> bool:
	return Input.is_action_just_pressed("toggle_debug_fog")


## Returns true only on the frame the place torch key was pressed.
func is_place_torch_just_pressed() -> bool:
	return Input.is_action_just_pressed("place_torch")


# --- Pause input ---

## Returns true only on the frame the pause action was first pressed.
func is_pause_just_pressed() -> bool:
	return Input.is_action_just_pressed("pause")


# --- Debug input ---

## Returns true only on the frame the fly-mode toggle key was pressed.
func is_fly_toggle_just_pressed() -> bool:
	return Input.is_action_just_pressed("toggle_fly")


## Returns the vertical movement direction for fly mode.
## -1.0 = up (jump), 1.0 = down (move_down), 0.0 = no input.
func get_fly_vertical_direction() -> float:
	return Input.get_axis("jump", "move_down")
