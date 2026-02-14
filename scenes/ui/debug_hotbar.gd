## DebugHotbar — Temporary debug HUD showing hotbar contents.
## Replace with proper UI in M4C.

extends CanvasLayer

var _slot_labels: Array[Label] = []


func _ready() -> void:
	layer = 10

	# Simple positioning — viewport is 960x540
	var slot_width: int = 90
	var slot_height: int = 32
	var spacing: int = 2
	var total_width: int = slot_width * 10 + spacing * 9
	var start_x: int = (960 - total_width) / 2
	var y: int = 540 - slot_height - 4

	for i in range(10):
		var panel := Panel.new()
		panel.position = Vector2(start_x + i * (slot_width + spacing), y)
		panel.size = Vector2(slot_width, slot_height)
		add_child(panel)

		var label := Label.new()
		label.position = Vector2(2, 2)
		label.size = Vector2(slot_width - 4, slot_height - 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = str((i + 1) % 10) + ": ---"
		label.add_theme_font_size_override("font_size", 9)
		panel.add_child(label)
		_slot_labels.append(label)

	GameServer.inventory_changed.connect(_update_display)
	GameServer.hotbar_selection_changed.connect(_on_selection_changed)
	_update_display()


func _update_display() -> void:
	for i in range(10):
		var slot: Dictionary = GameServer.get_hotbar_slot(i)
		var key_label: String = str((i + 1) % 10)
		if slot["item_id"] == "":
			_slot_labels[i].text = key_label + ": ---"
		else:
			var display_name: String = ItemDatabase.get_item_name(slot["item_id"])
			_slot_labels[i].text = key_label + ": " + display_name + "\nx" + str(slot["amount"])

		if i == GameServer.selected_hotbar_slot:
			_slot_labels[i].add_theme_color_override("font_color", Color.YELLOW)
		else:
			_slot_labels[i].add_theme_color_override("font_color", Color.WHITE)


func _on_selection_changed(_slot: int) -> void:
	_update_display()
