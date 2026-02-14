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


func _ready() -> void:
	load_settings()
	apply_all()
	print("[SettingsManager] Initialized.")


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


## Save all current settings to disk.
func save_settings() -> void:
	var config := ConfigFile.new()

	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)

	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "resolution_index", resolution_index)

	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_error("[SettingsManager] Failed to save settings: %d" % err)


# --- Apply ---

## Apply all settings (audio + video).
func apply_all() -> void:
	_apply_audio()
	_apply_video()


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
