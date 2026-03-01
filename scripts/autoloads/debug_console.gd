## DebugConsole — Toggleable in-game command console for debug/testing.
##
## Press backtick (`) to open/close. Type commands and press Enter to execute.
## Set DEBUG_ENABLED to false to completely disable for release builds.
##
## Output is a scrollable log that retains command + result history (max 50 lines).
## Expose `console_open` so player/mining scripts can block gameplay input.

extends CanvasLayer

## Set to false to disable debug console entirely.
const DEBUG_ENABLED: bool = true

## Maximum number of log lines before oldest are removed.
const MAX_LOG_LINES: int = 50

## Public flag — other scripts check this to block gameplay input while console is open.
var console_open: bool = false

var _is_open: bool = false
var _panel: ColorRect
var _scroll: ScrollContainer
var _log_label: RichTextLabel
var _bar: ColorRect
var _input_field: LineEdit
var _log_lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	if not DEBUG_ENABLED:
		set_process(false)
		set_process_unhandled_input(false)
		return
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_set_visible(false)


func _unhandled_input(event: InputEvent) -> void:
	if not DEBUG_ENABLED:
		return
	# Toggle console with backtick. Using _unhandled_input so GUI controls (LineEdit)
	# receive key events first — _input would consume them before the LineEdit sees them.
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		_toggle()
		get_viewport().set_input_as_handled()
		return
	# When console is open, block mouse clicks from reaching game world.
	# Key events are NOT consumed here — the LineEdit needs them for text input,
	# and the console_open flag already blocks player movement/mining (polling-based).
	if _is_open and event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_is_open = not _is_open
	console_open = _is_open
	_set_visible(_is_open)
	if _is_open:
		_input_field.grab_focus()
		_input_field.text = ""
	else:
		_input_field.release_focus()


func _set_visible(vis: bool) -> void:
	_panel.visible = vis
	_bar.visible = vis
	_input_field.visible = vis
	_scroll.visible = vis


func _build_ui() -> void:
	# Semi-transparent background panel for the log area.
	_panel = ColorRect.new()
	_panel.color = Color(0.0, 0.0, 0.0, 0.6)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	# Scrollable log container.
	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll)

	# RichTextLabel for log output — supports many lines, auto-scrolls.
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = false
	_log_label.scroll_active = false  # ScrollContainer handles scrolling.
	_log_label.fit_content = true
	_log_label.add_theme_font_size_override("normal_font_size", 10)
	_log_label.add_theme_color_override("default_color", Color(0.8, 1.0, 0.8))
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_log_label)

	# Dark bar background for input.
	_bar = ColorRect.new()
	_bar.color = Color(0.0, 0.0, 0.0, 0.8)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bar)

	# Line edit for command input.
	_input_field = LineEdit.new()
	_input_field.placeholder_text = "Type command... (help for list)"
	_input_field.add_theme_font_size_override("font_size", 10)
	_input_field.text_submitted.connect(_on_command_submitted)
	# Prevent backtick from appearing in the input.
	_input_field.text_changed.connect(func(new_text: String):
		if new_text.ends_with("`"):
			_input_field.text = new_text.trim_suffix("`")
			_input_field.caret_column = _input_field.text.length()
	)
	add_child(_input_field)

	_reposition()
	get_viewport().size_changed.connect(_reposition)


func _reposition() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var bar_height: float = 30.0
	var log_height: float = 150.0

	# Input bar at the bottom.
	_bar.position = Vector2(0, vp_size.y - bar_height)
	_bar.size = Vector2(vp_size.x, bar_height)
	_input_field.position = Vector2(4, vp_size.y - bar_height + 2)
	_input_field.size = Vector2(vp_size.x - 8, bar_height - 4)

	# Log panel and scroll container above the bar.
	_panel.position = Vector2(0, vp_size.y - bar_height - log_height)
	_panel.size = Vector2(vp_size.x, log_height)
	_scroll.position = Vector2(4, vp_size.y - bar_height - log_height + 2)
	_scroll.size = Vector2(vp_size.x - 8, log_height - 4)

	# RichTextLabel fills scroll container width.
	_log_label.custom_minimum_size = Vector2(vp_size.x - 16, 0)


func _on_command_submitted(text: String) -> void:
	var stripped: String = text.strip_edges()
	if stripped.is_empty():
		_input_field.text = ""
		_input_field.grab_focus()
		return

	# Log the command the user typed.
	_append_log("> " + stripped)

	var parts: PackedStringArray = stripped.split(" ", false)
	var cmd: String = parts[0].to_lower()
	match cmd:
		"give":
			_cmd_give(parts)
		"give_all":
			_cmd_give_all()
		"list":
			_cmd_list()
		"clear":
			_cmd_clear()
		"help":
			_append_log("Commands: give <id> [amount] [quality], give_all, list, clear, help")
		_:
			_append_log("Unknown command: %s" % cmd)

	_input_field.text = ""
	# Re-grab focus so the user can type another command immediately.
	_input_field.grab_focus()


func _cmd_give(parts: PackedStringArray) -> void:
	if parts.size() < 2:
		_append_log("Usage: give <item_id> [amount] [quality]")
		return
	var item_id: String = parts[1]
	if not ItemDatabase.has_item(item_id):
		_append_log("Unknown item: %s" % item_id)
		return
	var amount: int = 1
	if parts.size() >= 3:
		amount = maxi(parts[2].to_int(), 1)
	var quality: int = 1  # STANDARD
	if parts.size() >= 4:
		quality = clampi(parts[3].to_int(), 0, 5)
	var remainder: int = GameServer.request_add_item(item_id, amount, quality)
	var given: int = amount - remainder
	_append_log("Gave %d x %s (quality %d)" % [given, ItemDatabase.get_item_name(item_id), quality])


func _cmd_give_all() -> void:
	var ids: Array = ItemDatabase.get_all_ids()
	var count: int = 0
	for id in ids:
		var remainder: int = GameServer.request_add_item(id, 1, 1)
		if remainder == 0:
			count += 1
	_append_log("Gave 1 of %d items" % count)


func _cmd_list() -> void:
	var ids: Array = ItemDatabase.get_all_ids()
	_append_log("Items: " + ", ".join(ids))


func _cmd_clear() -> void:
	for i in range(GameServer.MAIN_SLOTS):
		GameServer.inventory_main[i] = {"item_id": "", "amount": 0, "quality": 0}
	for i in range(GameServer.HOTBAR_SLOTS):
		GameServer.inventory_hotbar[i] = {"item_id": "", "amount": 0, "quality": 0}
	for i in range(GameServer.EQUIP_SLOTS):
		GameServer.inventory_equipment[i] = {"item_id": "", "amount": 0, "quality": 0}
	GameServer.inventory_changed.emit()
	_append_log("Inventory cleared.")


## Append a line to the scrollable log. Trims oldest lines beyond MAX_LOG_LINES.
func _append_log(msg: String) -> void:
	_log_lines.append(msg)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)
	# Auto-scroll to bottom on next frame so the label has time to resize.
	_scroll.call_deferred("set_v_scroll", 999999)
