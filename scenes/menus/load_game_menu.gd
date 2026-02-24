extends Control

signal back_pressed
signal start_game(slot_name: String)

## Maps slot_name -> VBoxContainer (the restore points panel for that world).
var _restore_panels: Dictionary = {}


func _ready() -> void:
	%BackButton.pressed.connect(func(): back_pressed.emit())
	_populate_slots()
	%BackButton.grab_focus()


func _populate_slots() -> void:
	# Clear existing slot entries and panel tracking.
	for child in %SlotList.get_children():
		child.queue_free()
	_restore_panels.clear()

	var slots: Array[Dictionary] = SaveManager.enumerate_slots()

	if slots.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saved worlds found."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%SlotList.add_child(empty_label)
		return

	for slot in slots:
		var sn: String = slot["slot_name"]

		# --- World row (HBoxContainer) ---
		var row := HBoxContainer.new()

		# Display name
		var name_label := Label.new()
		name_label.text = slot["display_name"]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		# Playtime
		var time_label := Label.new()
		time_label.text = _format_playtime(slot["playtime_seconds"])
		time_label.custom_minimum_size.x = 80
		row.add_child(time_label)

		# Last played
		var date_label := Label.new()
		date_label.text = slot["last_played"]
		date_label.custom_minimum_size.x = 160
		row.add_child(date_label)

		# Load button (loads most recent state from current/)
		var load_btn := Button.new()
		load_btn.text = "Load"
		load_btn.pressed.connect(_on_load.bind(sn))
		row.add_child(load_btn)

		# Restore Points toggle button
		var restore_btn := Button.new()
		restore_btn.text = "Restore Points"
		restore_btn.pressed.connect(_on_toggle_restore_points.bind(sn))
		row.add_child(restore_btn)

		# Delete button
		var delete_btn := Button.new()
		delete_btn.text = "Delete"
		delete_btn.pressed.connect(_on_delete.bind(sn))
		row.add_child(delete_btn)

		%SlotList.add_child(row)

		# --- Restore points sub-panel (hidden by default) ---
		var panel := _create_restore_panel(sn)
		panel.visible = false
		%SlotList.add_child(panel)
		_restore_panels[sn] = panel


## Toggle visibility of the restore points panel for a world slot.
func _on_toggle_restore_points(slot_name: String) -> void:
	var panel: VBoxContainer = _restore_panels.get(slot_name)
	if not panel:
		return
	if panel.visible:
		panel.visible = false
	else:
		# Refresh snapshot list each time we open.
		_refresh_restore_panel(slot_name)
		panel.visible = true


## Create the restore points sub-panel container for a slot.
## Returns a VBoxContainer that will be populated on demand.
func _create_restore_panel(slot_name: String) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Indent the panel to visually nest it under the world row.
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 30)

	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.name = "SnapshotList"
	margin.add_child(inner)
	panel.add_child(margin)

	# Add a thin separator at the bottom.
	var sep := HSeparator.new()
	panel.add_child(sep)

	return panel


## Refresh the snapshot list inside a restore panel.
func _refresh_restore_panel(slot_name: String) -> void:
	var panel: VBoxContainer = _restore_panels.get(slot_name)
	if not panel:
		return

	# Find the SnapshotList inside the MarginContainer.
	var margin: MarginContainer = panel.get_child(0) as MarginContainer
	var snapshot_list: VBoxContainer = margin.get_child(0) as VBoxContainer

	# Clear previous entries.
	for child in snapshot_list.get_children():
		child.queue_free()

	# Query snapshots from SaveManager.
	var sm := SaveManager.new()
	sm.world_name = slot_name
	var snapshots: Array[Dictionary] = sm.enumerate_snapshots()

	if snapshots.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No restore points yet."
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		snapshot_list.add_child(empty_label)
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
		snap_load_btn.pressed.connect(_on_load_snapshot.bind(slot_name, save_name))
		snap_row.add_child(snap_load_btn)

		# Delete snapshot button
		var snap_delete_btn := Button.new()
		snap_delete_btn.text = "Delete"
		snap_delete_btn.pressed.connect(_on_delete_snapshot.bind(slot_name, save_name))
		snap_row.add_child(snap_delete_btn)

		snapshot_list.add_child(snap_row)


func _on_load(slot_name: String) -> void:
	GameState.reset_for_new_game()
	GameState.world_slot_name = slot_name
	GameState.is_game_active = true
	GameServer.reset_state()
	start_game.emit(slot_name)


func _on_load_snapshot(slot_name: String, save_name: String) -> void:
	var sm := SaveManager.new()
	sm.world_name = slot_name
	sm.load_snapshot(save_name)
	GameState.reset_for_new_game()
	GameState.world_slot_name = slot_name
	GameState.is_game_active = true
	GameServer.reset_state()
	start_game.emit(slot_name)


func _on_delete(slot_name: String) -> void:
	SaveManager.delete_slot(slot_name)
	_populate_slots()


func _on_delete_snapshot(slot_name: String, save_name: String) -> void:
	var sm := SaveManager.new()
	sm.world_name = slot_name
	sm.delete_snapshot(save_name)
	_refresh_restore_panel(slot_name)


func _format_playtime(seconds: float) -> String:
	if seconds < 60.0:
		return "< 1m"
	var total_minutes: int = int(seconds) / 60
	var hours: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes
