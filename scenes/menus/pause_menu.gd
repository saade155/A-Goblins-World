extends CanvasLayer

var _settings_scene: PackedScene = preload("res://scenes/menus/settings_menu.tscn")
var _active_submenu: Control = null
var _is_open: bool = false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_visible(false)
	%ResumeButton.pressed.connect(_resume)
	%SettingsButton.pressed.connect(_open_settings)
	%SaveQuitButton.pressed.connect(_save_and_quit)
	%QuitDesktopButton.pressed.connect(_quit_to_desktop)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _is_open:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()


func _pause() -> void:
	_is_open = true
	_set_visible(true)
	get_tree().paused = true
	%ResumeButton.grab_focus()


func _resume() -> void:
	_clear_submenu()
	_is_open = false
	_set_visible(false)
	get_tree().paused = false


func _set_visible(vis: bool) -> void:
	# CanvasLayer doesn't have a visible property directly
	# Instead show/hide child nodes
	for child in get_children():
		if child is CanvasItem:
			child.visible = vis


func _open_settings() -> void:
	_clear_submenu()
	_active_submenu = _settings_scene.instantiate()
	_active_submenu.back_pressed.connect(_on_settings_back)
	%SubMenuContainer.add_child(_active_submenu)
	# Hide main panel (the CenterContainer with buttons)
	$CenterContainer.visible = false


func _on_settings_back() -> void:
	_clear_submenu()
	$CenterContainer.visible = true
	%SettingsButton.grab_focus()


func _clear_submenu() -> void:
	if _active_submenu:
		_active_submenu.queue_free()
		_active_submenu = null


func _save_and_quit() -> void:
	# Find ChunkManager and save
	var chunk_manager = get_tree().current_scene.get_node_or_null("ChunkManager")
	if chunk_manager and chunk_manager.has_method("save_all"):
		chunk_manager.save_all()
	_go_to_title()


func _quit_to_desktop() -> void:
	var chunk_manager = get_tree().current_scene.get_node_or_null("ChunkManager")
	if chunk_manager and chunk_manager.has_method("save_all"):
		chunk_manager.save_all()
	get_tree().quit()


func _go_to_title() -> void:
	get_tree().paused = false
	GameState.is_game_active = false
	GameServer.reset_state()
	get_tree().change_scene_to_file("res://scenes/menus/title_screen.tscn")
