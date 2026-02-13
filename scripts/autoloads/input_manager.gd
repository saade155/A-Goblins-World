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


## Track previous jump state to detect edges for signals.
var _jump_held_last_frame: bool = false


func _ready() -> void:
	print("[InputManager] Initialized — reading from local input.")


func _process(_delta: float) -> void:
	# Emit jump signals on edges.
	var jump_held := Input.is_action_pressed("jump")

	if jump_held and not _jump_held_last_frame:
		jump_pressed.emit()
	elif not jump_held and _jump_held_last_frame:
		jump_released.emit()

	_jump_held_last_frame = jump_held


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
