extends Control

signal back_pressed
signal start_game(slot_name: String)


func _ready() -> void:
	%BackButton.pressed.connect(func(): back_pressed.emit())
	_populate_slots()
	%BackButton.grab_focus()


func _populate_slots() -> void:
	# Clear existing slot entries
	for child in %SlotList.get_children():
		child.queue_free()

	var slots: Array[Dictionary] = SaveManager.enumerate_slots()

	if slots.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saved worlds found."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%SlotList.add_child(empty_label)
		return

	for slot in slots:
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

		# Load button
		var load_btn := Button.new()
		load_btn.text = "Load"
		var sn: String = slot["slot_name"]
		load_btn.pressed.connect(_on_load.bind(sn))
		row.add_child(load_btn)

		# Delete button
		var delete_btn := Button.new()
		delete_btn.text = "Delete"
		delete_btn.pressed.connect(_on_delete.bind(sn))
		row.add_child(delete_btn)

		%SlotList.add_child(row)


func _on_load(slot_name: String) -> void:
	GameState.reset_for_new_game()
	GameState.world_slot_name = slot_name
	GameState.is_game_active = true
	GameServer.reset_state()
	start_game.emit(slot_name)


func _on_delete(slot_name: String) -> void:
	SaveManager.delete_slot(slot_name)
	_populate_slots()


func _format_playtime(seconds: float) -> String:
	if seconds < 60.0:
		return "< 1m"
	var total_minutes: int = int(seconds) / 60
	var hours: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes
