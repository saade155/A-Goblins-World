## KeybindsTab - Keybind remapping UI built in code.
##
## Each remappable action is a row: Label + Button showing current key.
## Click button -> "Press a key..." -> captures next key press -> assigns.
## Conflicts are resolved by swapping the two bindings.

extends VBoxContainer

## The button currently in listening mode, or null.
var _listening_button: Button = null

## The action name the listening button corresponds to.
var _listening_action: String = ""

## Map of action_name -> Button for updating display after swaps.
var _action_buttons: Dictionary = {}


func _ready() -> void:
	name = "Keybinds"
	_build_ui()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var current_group: String = ""

	for entry in SettingsManager.REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		var display_name: String = entry["display"]
		var group: String = entry["group"]

		# Group header
		if group != current_group:
			current_group = group
			if vbox.get_child_count() > 0:
				var spacer := Control.new()
				spacer.custom_minimum_size.y = 8
				vbox.add_child(spacer)
			var header := Label.new()
			header.text = group
			header.add_theme_font_size_override("font_size", 18)
			vbox.add_child(header)
			var sep := HSeparator.new()
			vbox.add_child(sep)

		# Row: label + button
		var row := HBoxContainer.new()
		vbox.add_child(row)

		var label := Label.new()
		label.text = display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var btn := Button.new()
		btn.custom_minimum_size.x = 150
		btn.text = _keycode_to_display(SettingsManager.get_current_keycode(action))
		btn.pressed.connect(_on_keybind_button_pressed.bind(action, btn))
		row.add_child(btn)

		_action_buttons[action] = btn

	# Bottom spacer + reset button
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size.y = 16
	vbox.add_child(bottom_spacer)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset_btn.pressed.connect(_on_reset_defaults)
	vbox.add_child(reset_btn)


func _on_keybind_button_pressed(action: String, btn: Button) -> void:
	# Cancel any existing listening
	if _listening_button and _listening_button != btn:
		_cancel_listening()

	_listening_button = btn
	_listening_action = action
	btn.text = "Press a key..."


func _unhandled_key_input(event: InputEvent) -> void:
	if not _listening_button:
		return
	if not event is InputEventKey:
		return
	if not event.pressed:
		return

	# Escape cancels
	if event.physical_keycode == KEY_ESCAPE:
		_cancel_listening()
		get_viewport().set_input_as_handled()
		return

	var new_keycode: int = event.physical_keycode

	# Conflict detection — swap if key is already used by another action
	var conflicting_action: String = SettingsManager.find_action_for_keycode(new_keycode)
	if conflicting_action != "" and conflicting_action != _listening_action:
		var old_keycode: int = SettingsManager.get_current_keycode(_listening_action)
		SettingsManager.set_keybind(conflicting_action, old_keycode)
		if _action_buttons.has(conflicting_action):
			_action_buttons[conflicting_action].text = _keycode_to_display(old_keycode)

	# Apply the new keybind
	SettingsManager.set_keybind(_listening_action, new_keycode)
	_listening_button.text = _keycode_to_display(new_keycode)

	_listening_button = null
	_listening_action = ""
	get_viewport().set_input_as_handled()


func _cancel_listening() -> void:
	if _listening_button:
		var current: int = SettingsManager.get_current_keycode(_listening_action)
		_listening_button.text = _keycode_to_display(current)
		_listening_button = null
		_listening_action = ""


func _on_reset_defaults() -> void:
	SettingsManager.reset_all_keybinds()
	for entry in SettingsManager.REMAPPABLE_ACTIONS:
		var action: String = entry["action"]
		if _action_buttons.has(action):
			_action_buttons[action].text = _keycode_to_display(SettingsManager.get_current_keycode(action))


func _keycode_to_display(keycode: int) -> String:
	if keycode == 0:
		return "[None]"
	var key_string: String = OS.get_keycode_string(keycode)
	if key_string == "":
		key_string = OS.get_keycode_string(
			DisplayServer.keyboard_get_keycode_from_physical(keycode as Key)
		)
	if key_string == "":
		return "Key %d" % keycode
	return key_string
