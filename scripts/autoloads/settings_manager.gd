## SettingsManager - Persists and applies user settings.
##
## Reads/writes settings to user://settings.cfg using ConfigFile.
## Call save_settings() after changing any property, then apply_all() to
## make the changes take effect immediately.

extends Node

# --- Constants ---

## Available resolution options (descending).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(960, 540),
]

const SETTINGS_PATH := "user://settings.cfg"

# --- Audio settings ---

## Master volume (0.0 - 1.0).
var master_volume: float = 1.0

## Sound effects volume (0.0 - 1.0).
var sfx_volume: float = 1.0

## Music volume (0.0 - 1.0).
var music_volume: float = 1.0

# --- Video settings ---

## Whether the game runs in fullscreen mode.
var fullscreen: bool = false

## Index into RESOLUTIONS for the current window size.
var resolution_index: int = 0

# --- Keybind settings ---

## Actions that are remappable. Display name and group for UI organization.
const REMAPPABLE_ACTIONS: Array[Dictionary] = [
	{"action": "move_left", "display": "Move Left", "group": "Movement"},
	{"action": "move_right", "display": "Move Right", "group": "Movement"},
	{"action": "move_down", "display": "Crouch / Down", "group": "Movement"},
	{"action": "jump", "display": "Jump", "group": "Actions"},
	{"action": "place_torch", "display": "Place Torch", "group": "Actions"},
	{"action": "hotbar_1", "display": "Hotbar 1", "group": "Hotbar"},
	{"action": "hotbar_2", "display": "Hotbar 2", "group": "Hotbar"},
	{"action": "hotbar_3", "display": "Hotbar 3", "group": "Hotbar"},
	{"action": "hotbar_4", "display": "Hotbar 4", "group": "Hotbar"},
	{"action": "hotbar_5", "display": "Hotbar 5", "group": "Hotbar"},
	{"action": "hotbar_6", "display": "Hotbar 6", "group": "Hotbar"},
	{"action": "hotbar_7", "display": "Hotbar 7", "group": "Hotbar"},
	{"action": "hotbar_8", "display": "Hotbar 8", "group": "Hotbar"},
	{"action": "hotbar_9", "display": "Hotbar 9", "group": "Hotbar"},
	{"action": "hotbar_10", "display": "Hotbar 10", "group": "Hotbar"},
	{"action": "toggle_map", "display": "Map", "group": "UI"},
	{"action": "toggle_skills", "display": "Skills", "group": "UI"},
	{"action": "pause", "display": "Pause", "group": "UI"},
]

## Keybind overrides — only stores actions that differ from project.godot defaults.
## Key = action name, Value = physical keycode.
var keybind_overrides: Dictionary = {}

## Snapshot of project.godot default events, captured once before any overrides.
var _default_events: Dictionary = {}


func _ready() -> void:
	_capture_default_events()
	load_settings()
	apply_all()
	print("[SettingsManager] Initialized.")


## Capture the project.godot input events before any overrides are applied.
func _capture_default_events() -> void:
	for entry in REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action).duplicate()


# --- Persistence ---

## Load settings from disk. Uses defaults if the file doesn't exist.
func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err != OK:
		print("[SettingsManager] No settings file found, using defaults.")
		return

	master_volume = config.get_value("audio", "master_volume", 1.0)
	sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
	music_volume = config.get_value("audio", "music_volume", 1.0)

	fullscreen = config.get_value("video", "fullscreen", false)
	resolution_index = config.get_value("video", "resolution_index", 0)

	# Clamp to valid range.
	resolution_index = clampi(resolution_index, 0, RESOLUTIONS.size() - 1)

	# Load keybind overrides
	keybind_overrides.clear()
	if config.has_section("keybinds"):
		for action_name in config.get_section_keys("keybinds"):
			var keycode: int = config.get_value("keybinds", action_name, 0)
			if keycode != 0:
				keybind_overrides[action_name] = keycode


## Save all current settings to disk.
func save_settings() -> void:
	var config := ConfigFile.new()

	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)

	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "resolution_index", resolution_index)

	# Save keybind overrides
	for action_name in keybind_overrides:
		config.set_value("keybinds", action_name, keybind_overrides[action_name])

	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_error("[SettingsManager] Failed to save settings: %d" % err)


# --- Apply ---

## Apply all settings (audio + video).
func apply_all() -> void:
	_apply_audio()
	_apply_video()
	_apply_keybinds()


## Apply audio settings to the AudioServer buses.
func _apply_audio() -> void:
	var master_bus := AudioServer.get_bus_index("Master")

	if master_volume <= 0.0:
		AudioServer.set_bus_mute(master_bus, true)
	else:
		AudioServer.set_bus_mute(master_bus, false)
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(master_volume))

	# SFX and Music buses are applied only if they exist.
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus != -1:
		if sfx_volume <= 0.0:
			AudioServer.set_bus_mute(sfx_bus, true)
		else:
			AudioServer.set_bus_mute(sfx_bus, false)
			AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(sfx_volume))

	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus != -1:
		if music_volume <= 0.0:
			AudioServer.set_bus_mute(music_bus, true)
		else:
			AudioServer.set_bus_mute(music_bus, false)
			AudioServer.set_bus_volume_db(music_bus, linear_to_db(music_volume))


## Apply video settings via DisplayServer.
func _apply_video() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var res := RESOLUTIONS[resolution_index]
		DisplayServer.window_set_size(res)
		# Center the window on the primary screen.
		var screen_size := DisplayServer.screen_get_size()
		var win_pos := (screen_size - res) / 2
		DisplayServer.window_set_position(win_pos)


# --- Keybind application ---

## Apply all keybind overrides to the runtime InputMap.
func _apply_keybinds() -> void:
	for entry in REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		if not InputMap.has_action(action):
			continue
		if keybind_overrides.has(action):
			_apply_single_keybind(action, keybind_overrides[action])
		else:
			_restore_default_keybind(action)


## Replace the first InputEventKey for an action with a new physical keycode.
func _apply_single_keybind(action: String, keycode: int) -> void:
	var events := InputMap.action_get_events(action)
	# Remove the first keyboard event
	for event in events:
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
			break
	# Add the new key
	var new_event := InputEventKey.new()
	new_event.physical_keycode = keycode as Key
	new_event.device = -1
	InputMap.action_add_event(action, new_event)


## Restore an action to its project.godot defaults.
func _restore_default_keybind(action: String) -> void:
	if not _default_events.has(action):
		return
	InputMap.action_erase_events(action)
	for event in _default_events[action]:
		InputMap.action_add_event(action, event)


# --- Keybind public API ---

## Set a keybind override. Called by the keybinds UI.
func set_keybind(action: String, keycode: int) -> void:
	if keycode == 0 or keycode == get_default_keycode(action):
		keybind_overrides.erase(action)
	else:
		keybind_overrides[action] = keycode
	_apply_keybinds()
	save_settings()


## Get the currently active physical keycode for an action.
func get_current_keycode(action: String) -> int:
	if keybind_overrides.has(action):
		return keybind_overrides[action]
	return get_default_keycode(action)


## Get the project.godot default keycode for an action.
func get_default_keycode(action: String) -> int:
	if _default_events.has(action):
		for event in _default_events[action]:
			if event is InputEventKey:
				return event.physical_keycode
	return 0


## Check if a keycode is already bound to another action. Returns action name or "".
func find_action_for_keycode(keycode: int) -> String:
	for entry in REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		if get_current_keycode(action) == keycode:
			return action
	return ""


## Reset all keybinds to project.godot defaults.
func reset_all_keybinds() -> void:
	keybind_overrides.clear()
	_apply_keybinds()
	save_settings()
