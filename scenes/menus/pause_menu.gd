extends CanvasLayer

var _settings_scene: PackedScene = preload("res://scenes/menus/settings_menu.tscn")
var _active_submenu: Control = null
var _is_open: bool = false

## Save dialog nodes (built in code, shown/hidden inline).
var _save_dialog: PanelContainer = null
var _save_name_input: LineEdit = null
var _save_status_label: Label = null

## Load dialog nodes (built in code, shown/hidden inline).
var _snapshot_list: VBoxContainer = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_visible(false)
	%ResumeButton.pressed.connect(_resume)
	%SaveGameButton.pressed.connect(_show_save_dialog)
	%LoadSaveButton.pressed.connect(_on_load_save_pressed)
	%SettingsButton.pressed.connect(_open_settings)
	%SaveQuitButton.pressed.connect(_save_and_quit)
	%QuitDesktopButton.pressed.connect(_quit_to_desktop)

	_build_save_dialog()
	_build_load_dialog()


func _input(event: InputEvent) -> void:
	# Don't toggle pause while any overlay is open — they handle Escape themselves.
	if ChatWindow.chat_focused:
		return
	if GameServer.inventory_open or GameServer.skill_panel_open or GameServer.map_open:
		return
	if event.is_action_pressed("pause"):
		if _is_open:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()


func _pause() -> void:
	_is_open = true
	_set_visible(true)
	# Ensure save/load dialogs are hidden — _set_visible shows all children
	var save_center = get_node_or_null("SaveDialogCenter")
	if save_center:
		save_center.visible = false
	var load_center = get_node_or_null("LoadDialogCenter")
	if load_center:
		load_center.visible = false
	$CenterContainer.visible = true
	get_tree().paused = true
	%ResumeButton.grab_focus()


func _resume() -> void:
	_hide_save_dialog()
	_hide_load_dialog()
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
	GameState.reset_for_new_game()
	GameServer.reset_state()
	get_tree().change_scene_to_file("res://scenes/menus/title_screen.tscn")


# --- Save dialog ---

## Build the inline save dialog panel in code. Hidden by default.
func _build_save_dialog() -> void:
	# CenterContainer to center the dialog on screen (same pattern as main menu)
	var center := CenterContainer.new()
	center.name = "SaveDialogCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	add_child(center)

	_save_dialog = PanelContainer.new()
	_save_dialog.name = "SaveDialogPanel"
	center.add_child(_save_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_save_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Save Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Name row
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Save Name:"
	name_row.add_child(name_label)

	_save_name_input = LineEdit.new()
	_save_name_input.custom_minimum_size = Vector2(200, 0)
	_save_name_input.text_submitted.connect(func(_text: String): _on_save_confirm())
	name_row.add_child(_save_name_input)

	# Status label (shows "Saving..." feedback)
	_save_status_label = Label.new()
	_save_status_label.text = ""
	_save_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_status_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	vbox.add_child(_save_status_label)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Button row
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save_confirm)
	button_row.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_hide_save_dialog)
	button_row.add_child(cancel_btn)


## Generate a default save name like "Save 1", "Save 2", etc.
func _generate_save_name() -> String:
	var chunk_manager = get_tree().current_scene.get_node_or_null("ChunkManager")
	if not chunk_manager or not chunk_manager.save_manager:
		return "Save 1"
	var snapshots: Array = chunk_manager.save_manager.enumerate_snapshots()
	# Count manual (non-auto) saves
	var manual_count: int = 0
	for snap in snapshots:
		if not snap.get("is_auto", false):
			manual_count += 1
	return "Save %d" % (manual_count + 1)


## Show the save dialog, hiding the main button panel.
func _show_save_dialog() -> void:
	_save_status_label.text = ""
	_save_name_input.text = _generate_save_name()
	$CenterContainer.visible = false
	# The save dialog center container is a direct child of the CanvasLayer
	var center: CenterContainer = get_node("SaveDialogCenter")
	center.visible = true
	_save_name_input.grab_focus()
	_save_name_input.select_all()


## Hide the save dialog and return to main buttons.
func _hide_save_dialog() -> void:
	var center = get_node_or_null("SaveDialogCenter")
	if center:
		center.visible = false
	$CenterContainer.visible = true
	%SaveGameButton.grab_focus()


## Confirm the save action.
func _on_save_confirm() -> void:
	var save_name: String = SaveManager.sanitize_save_name(_save_name_input.text)
	if save_name == "":
		save_name = _generate_save_name()

	var chunk_manager = get_tree().current_scene.get_node_or_null("ChunkManager")
	if not chunk_manager or not chunk_manager.has_method("create_save"):
		_save_status_label.text = "Error: no ChunkManager"
		return

	if chunk_manager.save_manager.is_saving():
		_save_status_label.text = "Save in progress..."
		return

	# Trigger the save
	chunk_manager.create_save(save_name)
	_save_status_label.text = "Saved!"

	# Brief delay then return to main buttons
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(_hide_save_dialog)


# --- Load Save ---

func _on_load_save_pressed() -> void:
	_show_load_dialog()


## Build the inline load dialog panel in code. Hidden by default.
func _build_load_dialog() -> void:
	var center := CenterContainer.new()
	center.name = "LoadDialogCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "LoadDialogPanel"
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Restore Points"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrollable snapshot list (vertical only, no horizontal scrollbar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_snapshot_list = VBoxContainer.new()
	_snapshot_list.name = "SnapshotList"
	_snapshot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_snapshot_list)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Back button
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_hide_load_dialog)
	vbox.add_child(back_btn)


## Show the load dialog, hiding the main button panel.
func _show_load_dialog() -> void:
	$CenterContainer.visible = false
	_populate_snapshots()
	var center: CenterContainer = get_node("LoadDialogCenter")
	center.visible = true


## Hide the load dialog and return to main buttons.
func _hide_load_dialog() -> void:
	var center = get_node_or_null("LoadDialogCenter")
	if center:
		center.visible = false
	$CenterContainer.visible = true
	%LoadSaveButton.grab_focus()


## Clear and rebuild the snapshot list with the current world's snapshots.
func _populate_snapshots() -> void:
	for child in _snapshot_list.get_children():
		child.queue_free()

	var sm := SaveManager.new()
	sm.world_name = GameState.world_slot_name
	var snapshots: Array = sm.enumerate_snapshots()

	if snapshots.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No restore points yet."
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_snapshot_list.add_child(empty_label)
		return

	for snap in snapshots:
		var snap_row := HBoxContainer.new()

		# Save name
		var snap_name_label := Label.new()
		snap_name_label.text = snap["save_name"]
		snap_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		snap_row.add_child(snap_name_label)

		# Reason (auto/manual)
		var reason_label := Label.new()
		reason_label.text = snap["reason"] if snap["reason"] != "" else ("auto" if snap["is_auto"] else "manual")
		reason_label.custom_minimum_size.x = 60
		snap_row.add_child(reason_label)

		# Playtime
		var snap_time_label := Label.new()
		snap_time_label.text = _format_playtime(snap["playtime_seconds"])
		snap_time_label.custom_minimum_size.x = 80
		snap_row.add_child(snap_time_label)

		# Timestamp
		var snap_date_label := Label.new()
		snap_date_label.text = snap["timestamp"]
		snap_date_label.custom_minimum_size.x = 160
		snap_row.add_child(snap_date_label)

		# Load snapshot button
		var snap_load_btn := Button.new()
		snap_load_btn.text = "Load"
		var save_name: String = snap["save_name"]
		snap_load_btn.pressed.connect(_on_load_snapshot.bind(save_name))
		snap_row.add_child(snap_load_btn)

		_snapshot_list.add_child(snap_row)


## Load a snapshot and reload the current scene to pick up restored state.
func _on_load_snapshot(save_name: String) -> void:
	var sm := SaveManager.new()
	sm.world_name = GameState.world_slot_name
	sm.load_snapshot(save_name)
	get_tree().paused = false
	GameState.saved_player_position = null
	GameServer.reset_state()
	get_tree().reload_current_scene()


## Format playtime seconds into a human-readable string.
func _format_playtime(seconds: float) -> String:
	if seconds < 60.0:
		return "< 1m"
	var total_minutes: int = int(seconds) / 60
	var hours: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes
