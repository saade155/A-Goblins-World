## ChatWindow — In-game chat with command support.
##
## Three states: HIDDEN (invisible), PASSIVE (history fading), FOCUSED (typing).
## Press T to open chat, / to open with command prefix.
## Commands use / prefix: /give, /give_all, /list, /clear, /reveal, /help.
## Public API: ChatWindow.add_message(text, type) for external systems.
## Exposes `chat_focused` so other scripts can block gameplay input.

extends CanvasLayer

## Set to false to disable chat entirely in release.
const DEBUG_ENABLED: bool = true

const MAX_LOG_LINES: int = 50
const PASSIVE_DISPLAY_TIME: float = 5.0
const FADE_DURATION: float = 2.0
const PANEL_WIDTH: float = 320.0
const LOG_HEIGHT: float = 150.0
const BAR_HEIGHT: float = 26.0

const MSG_COLORS: Dictionary = {
	"system": "00cc44",
	"echo": "888888",
	"chat": "ffffff",
}

enum { HIDDEN, PASSIVE, FOCUSED }

## Public guard — other scripts check this to block gameplay input.
var chat_focused: bool = false

var _state: int = HIDDEN
var _log_entries: Array[Dictionary] = []
var _fade_tween: Tween = null
var _passive_timer: float = 0.0

var _root: Control
var _panel: Panel
var _scroll: ScrollContainer
var _log_label: RichTextLabel
var _bar: Panel
var _input_field: LineEdit


func _ready() -> void:
	if not DEBUG_ENABLED:
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_set_state(HIDDEN)


func _input(event: InputEvent) -> void:
	if not DEBUG_ENABLED:
		return
	# Escape to unfocus while in FOCUSED state (uses _input for priority)
	if _state == FOCUSED and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_set_state(PASSIVE)
			get_viewport().set_input_as_handled()
			return
	# Block mouse clicks from reaching game world while focused
	if _state == FOCUSED and event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not DEBUG_ENABLED:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# Don't open chat when other overlays are active or game is paused
	if _state != FOCUSED:
		if get_tree().paused:
			return
		if GameServer.inventory_open or GameServer.skill_panel_open or GameServer.map_open:
			return
		if event.keycode == KEY_T:
			_enter_focused("")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SLASH:
			_enter_focused("/")
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	if _state == PASSIVE and _fade_tween == null:
		_passive_timer += delta
		if _passive_timer >= PASSIVE_DISPLAY_TIME:
			_start_fade()


func _set_state(new_state: int) -> void:
	_state = new_state
	match new_state:
		HIDDEN:
			chat_focused = false
			_root.modulate.a = 0.0
			_bar.visible = false
			_input_field.visible = false
			_input_field.release_focus()
		PASSIVE:
			chat_focused = false
			_kill_fade()
			_root.modulate.a = 1.0
			_bar.visible = false
			_input_field.visible = false
			_input_field.release_focus()
			_passive_timer = 0.0
		FOCUSED:
			chat_focused = true
			_kill_fade()
			_root.modulate.a = 1.0
			_bar.visible = true
			_input_field.visible = true
	_reposition()


func _enter_focused(prefill: String) -> void:
	_set_state(FOCUSED)
	_input_field.grab_focus()
	# Defer text set to avoid the triggering keypress leaking into LineEdit
	_input_field.call_deferred("set_text", prefill)
	_input_field.call_deferred("set_caret_column", prefill.length())


func _kill_fade() -> void:
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null


func _start_fade() -> void:
	# Only start fade from PASSIVE, and only once
	if _state != PASSIVE:
		return
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 0.0, FADE_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_fade_tween.finished.connect(_on_fade_complete)


func _on_fade_complete() -> void:
	_fade_tween = null
	if _state == PASSIVE:
		_set_state(HIDDEN)


## Public API — add a message to the chat log.
## type: "system" (green), "echo" (gray), "chat" (white)
func add_message(text: String, type: String = "system") -> void:
	_log_entries.append({"text": text, "type": type})
	while _log_entries.size() > MAX_LOG_LINES:
		_log_entries.remove_at(0)
	_refresh_log()

	if _state == HIDDEN:
		_set_state(PASSIVE)
	elif _state == PASSIVE:
		_passive_timer = 0.0
		_kill_fade()
		_root.modulate.a = 1.0


func _refresh_log() -> void:
	_log_label.clear()
	var bbcode: String = ""
	for entry in _log_entries:
		var color: String = MSG_COLORS.get(entry["type"], "ffffff")
		bbcode += "[color=#%s]%s[/color]\n" % [color, entry["text"]]
	_log_label.append_text(bbcode)
	_scroll.call_deferred("set_v_scroll", 999999)


func _on_text_submitted(text: String) -> void:
	var stripped: String = text.strip_edges()
	_input_field.text = ""

	if stripped.is_empty():
		_set_state(PASSIVE)
		return

	if stripped.begins_with("/"):
		var cmd_text: String = stripped.substr(1).strip_edges()
		if cmd_text.is_empty():
			_set_state(PASSIVE)
			return
		add_message("> /" + cmd_text, "echo")
		_execute_command(cmd_text)
	else:
		# Chat message — local echo for now
		add_message(stripped, "chat")

	_set_state(PASSIVE)


func _execute_command(raw: String) -> void:
	var parts: PackedStringArray = raw.split(" ", false)
	if parts.is_empty():
		return
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
		"reveal":
			ExplorationTracker.toggle_debug_fog()
		"help":
			add_message("Commands: /give <id> [amount] [quality], /give_all, /list, /clear, /reveal, /help")
		_:
			add_message("Unknown command: %s" % cmd)


func _cmd_give(parts: PackedStringArray) -> void:
	if parts.size() < 2:
		add_message("Usage: /give <item_id> [amount] [quality]")
		return
	var item_id: String = parts[1]
	if not ItemDatabase.has_item(item_id):
		add_message("Unknown item: %s" % item_id)
		return
	var amount: int = 1
	if parts.size() >= 3:
		amount = maxi(parts[2].to_int(), 1)
	var quality: int = 1
	if parts.size() >= 4:
		quality = clampi(parts[3].to_int(), 0, 5)
	var remainder: int = GameServer.request_add_item(item_id, amount, quality)
	var given: int = amount - remainder
	add_message("Gave %d x %s (quality %d)" % [given, ItemDatabase.get_item_name(item_id), quality])


func _cmd_give_all() -> void:
	var ids: Array = ItemDatabase.get_all_ids()
	var count: int = 0
	for id in ids:
		var remainder: int = GameServer.request_add_item(id, 1, 1)
		if remainder == 0:
			count += 1
	add_message("Gave 1 of %d items" % count)


func _cmd_list() -> void:
	var ids: Array = ItemDatabase.get_all_ids()
	add_message("Items: " + ", ".join(ids))


func _cmd_clear() -> void:
	for i in range(GameServer.MAIN_SLOTS):
		GameServer.inventory_main[i] = {"item_id": "", "amount": 0, "quality": 0}
	for i in range(GameServer.HOTBAR_SLOTS):
		GameServer.inventory_hotbar[i] = {"item_id": "", "amount": 0, "quality": 0}
	for i in range(GameServer.EQUIP_SLOTS):
		GameServer.inventory_equipment[i] = {"item_id": "", "amount": 0, "quality": 0}
	GameServer.inventory_changed.emit()
	add_message("Inventory cleared.")


func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_panel = Panel.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	panel_style.border_color = Color(0.5, 0.5, 0.5, 0.6)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scroll)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = false
	_log_label.fit_content = true
	_log_label.add_theme_font_size_override("normal_font_size", 10)
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_log_label)

	_bar = Panel.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	bar_style.border_color = Color(0.5, 0.5, 0.5, 0.6)
	bar_style.border_width_left = 1
	bar_style.border_width_right = 1
	bar_style.border_width_top = 1
	bar_style.border_width_bottom = 1
	_bar.add_theme_stylebox_override("panel", bar_style)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_bar)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "Type to chat, / for commands..."
	_input_field.add_theme_font_size_override("font_size", 10)
	_input_field.text_submitted.connect(_on_text_submitted)
	_input_field.focus_mode = Control.FOCUS_ALL
	_root.add_child(_input_field)

	_reposition()
	get_viewport().size_changed.connect(_reposition)


func _reposition() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var margin: float = 8.0
	var hotbar_start_x: float = (vp_size.x - 378.0) / 2.0
	var panel_width: float = hotbar_start_x - 12.0  # 8px left margin + 4px right gap
	var bottom_y: float = vp_size.y - margin

	if _state == FOCUSED:
		_bar.position = Vector2(margin, bottom_y - BAR_HEIGHT)
		_bar.size = Vector2(panel_width, BAR_HEIGHT)
		_input_field.position = Vector2(margin + 4, bottom_y - BAR_HEIGHT + 2)
		_input_field.size = Vector2(panel_width - 8, BAR_HEIGHT - 4)
		bottom_y -= BAR_HEIGHT

	_panel.position = Vector2(margin, bottom_y - LOG_HEIGHT)
	_panel.size = Vector2(panel_width, LOG_HEIGHT)
	_scroll.position = Vector2(margin + 4, bottom_y - LOG_HEIGHT + 2)
	_scroll.size = Vector2(panel_width - 8, LOG_HEIGHT - 4)
	_log_label.custom_minimum_size = Vector2(panel_width - 16, 0)
