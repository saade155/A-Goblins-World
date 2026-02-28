extends Control

signal back_pressed

func _ready() -> void:
	# Add keybinds tab programmatically
	var keybinds_tab := VBoxContainer.new()
	keybinds_tab.set_script(preload("res://scenes/menus/keybinds_tab.gd"))
	$PanelContainer/MarginContainer/VBoxContainer/TabContainer.add_child(keybinds_tab)

	# Load current values from SettingsManager
	%MasterSlider.value = SettingsManager.master_volume * 100.0
	%SFXSlider.value = SettingsManager.sfx_volume * 100.0
	%MusicSlider.value = SettingsManager.music_volume * 100.0
	%FullscreenToggle.button_pressed = SettingsManager.fullscreen
	_populate_resolutions()

	# Connect signals
	%MasterSlider.value_changed.connect(_on_master_changed)
	%SFXSlider.value_changed.connect(_on_sfx_changed)
	%MusicSlider.value_changed.connect(_on_music_changed)
	%FullscreenToggle.toggled.connect(_on_fullscreen_toggled)
	%ResolutionOption.item_selected.connect(_on_resolution_selected)
	%BackButton.pressed.connect(func(): back_pressed.emit())

	# Focus first interactive element
	%MasterSlider.grab_focus()

func _populate_resolutions() -> void:
	%ResolutionOption.clear()
	for res in SettingsManager.RESOLUTIONS:
		%ResolutionOption.add_item("%dx%d" % [res.x, res.y])
	%ResolutionOption.selected = SettingsManager.resolution_index

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

func _on_fullscreen_toggled(pressed: bool) -> void:
	SettingsManager.fullscreen = pressed
	SettingsManager._apply_video()
	SettingsManager.save_settings()

func _on_resolution_selected(index: int) -> void:
	SettingsManager.resolution_index = index
	SettingsManager._apply_video()
	SettingsManager.save_settings()
