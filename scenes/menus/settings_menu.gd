extends Control

signal back_pressed

func _ready() -> void:
	# Add keybinds tab programmatically
	var keybinds_tab := VBoxContainer.new()
	keybinds_tab.set_script(preload("res://scenes/menus/keybinds_tab.gd"))
	$PanelContainer/MarginContainer/VBoxContainer/TabContainer.add_child(keybinds_tab)

	# Populate window mode dropdown
	_populate_window_modes()

	# Load current values from SettingsManager
	%MasterSlider.value = SettingsManager.master_volume * 100.0
	%SFXSlider.value = SettingsManager.sfx_volume * 100.0
	%MusicSlider.value = SettingsManager.music_volume * 100.0
	%WindowModeOption.selected = SettingsManager.window_mode
	_populate_resolutions()
	_update_resolution_visibility()

	# Connect signals
	%MasterSlider.value_changed.connect(_on_master_changed)
	%SFXSlider.value_changed.connect(_on_sfx_changed)
	%MusicSlider.value_changed.connect(_on_music_changed)
	%WindowModeOption.item_selected.connect(_on_window_mode_selected)
	%ResolutionOption.item_selected.connect(_on_resolution_selected)
	%BackButton.pressed.connect(func(): back_pressed.emit())

	# Focus first interactive element
	%MasterSlider.grab_focus()


func _populate_window_modes() -> void:
	%WindowModeOption.clear()
	for mode_name in SettingsManager.WINDOW_MODE_NAMES:
		%WindowModeOption.add_item(mode_name)


func _populate_resolutions() -> void:
	%ResolutionOption.clear()
	var selected_idx: int = 0
	for i in range(SettingsManager.available_resolutions.size()):
		var res: Vector2i = SettingsManager.available_resolutions[i]
		%ResolutionOption.add_item("%dx%d" % [res.x, res.y])
		if res == SettingsManager.windowed_resolution:
			selected_idx = i
	%ResolutionOption.selected = selected_idx


## Resolution picker is only relevant in Windowed mode.
func _update_resolution_visibility() -> void:
	var show_res: bool = SettingsManager.window_mode == SettingsManager.WindowMode.WINDOWED
	%ResolutionOption.get_parent().visible = show_res


func _on_master_changed(value: float) -> void:
	SettingsManager.master_volume = value / 100.0
	SettingsManager._apply_audio()
	SettingsManager.save_settings()


func _on_sfx_changed(value: float) -> void:
	SettingsManager.sfx_volume = value / 100.0
	SettingsManager._apply_audio()
	SettingsManager.save_settings()


func _on_music_changed(value: float) -> void:
	SettingsManager.music_volume = value / 100.0
	SettingsManager._apply_audio()
	SettingsManager.save_settings()


func _on_window_mode_selected(index: int) -> void:
	SettingsManager.window_mode = index
	SettingsManager._apply_video()
	SettingsManager.save_settings()
	_update_resolution_visibility()


func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < SettingsManager.available_resolutions.size():
		SettingsManager.windowed_resolution = SettingsManager.available_resolutions[index]
		SettingsManager._apply_video()
		SettingsManager.save_settings()
