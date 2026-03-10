## VitalsDisplay - HP, MP, and Stamina bars in the top left.

extends Control

const BAR_WIDTH: int = 140
const BAR_X: int = 12
const BAR_BOTTOM_OFFSET: int = 62
const BAR_GAP: int = 4

var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _hp_label: Label
var _mp_bg: ColorRect
var _mp_fill: ColorRect
var _mp_label: Label
var _stam_bg: ColorRect
var _stam_fill: ColorRect
var _stam_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# HP bar — 14px tall
	var result := _create_bar(0, 0, BAR_WIDTH, 14,
		Color(0.75, 0.15, 0.15), Color(0.25, 0.05, 0.05))
	_hp_bg = result[0]
	_hp_fill = result[1]
	_hp_label = _create_bar_label(0, 0, BAR_WIDTH, 14, "HP")

	# MP bar — 12px tall
	result = _create_bar(0, 0, BAR_WIDTH, 12,
		Color(0.15, 0.25, 0.75), Color(0.05, 0.05, 0.25))
	_mp_bg = result[0]
	_mp_fill = result[1]
	_mp_label = _create_bar_label(0, 0, BAR_WIDTH, 12, "MP")

	# Stamina bar — 12px tall
	result = _create_bar(0, 0, BAR_WIDTH, 12,
		Color(0.2, 0.7, 0.2), Color(0.05, 0.2, 0.05))
	_stam_bg = result[0]
	_stam_fill = result[1]
	_stam_label = _create_bar_label(0, 0, BAR_WIDTH, 12, "ST")

	# Connect signals
	GameServer.player_health_changed.connect(_on_health_changed)
	GameServer.player_mana_changed.connect(_on_mana_changed)
	GameServer.player_stamina_changed.connect(_on_stamina_changed)

	# Initial display
	_update_bar(_hp_fill, _hp_label, GameServer.player_health, GameServer.player_max_health, BAR_WIDTH, "HP")
	_update_bar(_mp_fill, _mp_label, GameServer.player_mana, GameServer.player_max_mana, BAR_WIDTH, "MP")
	_update_bar(_stam_fill, _stam_label, GameServer.player_stamina, GameServer.player_max_stamina, BAR_WIDTH, "ST")

	# Position bars based on current viewport size
	reposition()


func reposition() -> void:
	var bar_start_y: int = 12

	# HP bar — 14px tall
	var hp_pos := Vector2(BAR_X, bar_start_y)
	_hp_bg.position = hp_pos
	_hp_fill.position = hp_pos
	_hp_label.position = Vector2(BAR_X + 4, bar_start_y)
	_hp_label.size = Vector2(BAR_WIDTH - 8, 14)

	# MP bar — 12px tall
	var mp_y: int = bar_start_y + 14 + BAR_GAP
	var mp_pos := Vector2(BAR_X, mp_y)
	_mp_bg.position = mp_pos
	_mp_fill.position = mp_pos
	_mp_label.position = Vector2(BAR_X + 4, mp_y)
	_mp_label.size = Vector2(BAR_WIDTH - 8, 12)

	# Stamina bar — 12px tall
	var stam_y: int = mp_y + 12 + BAR_GAP
	var stam_pos := Vector2(BAR_X, stam_y)
	_stam_bg.position = stam_pos
	_stam_fill.position = stam_pos
	_stam_label.position = Vector2(BAR_X + 4, stam_y)
	_stam_label.size = Vector2(BAR_WIDTH - 8, 12)


func _create_bar(x: int, y: int, w: int, h: int, fill_color: Color, bg_color: Color) -> Array:
	# Background
	var bg := ColorRect.new()
	bg.position = Vector2(x, y)
	bg.size = Vector2(w, h)
	bg.color = bg_color
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Fill
	var fill := ColorRect.new()
	fill.position = Vector2(x, y)
	fill.size = Vector2(w, h)
	fill.color = fill_color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)

	return [bg, fill]


func _create_bar_label(x: int, y: int, w: int, h: int, prefix: String) -> Label:
	var label := Label.new()
	label.position = Vector2(x + 4, y)
	label.size = Vector2(w - 8, h)
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = prefix
	add_child(label)
	return label


func _update_bar(fill: ColorRect, label: Label, current: float, max_val: float, width: int, prefix: String) -> void:
	var ratio: float = current / maxf(max_val, 1.0)
	var target_w: float = ratio * width
	# Tween for smooth transitions
	var tween := create_tween()
	tween.tween_property(fill, "size:x", target_w, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	label.text = "%s %d/%d" % [prefix, roundi(current), roundi(max_val)]


func _on_health_changed(current: float, max_val: float) -> void:
	_update_bar(_hp_fill, _hp_label, current, max_val, BAR_WIDTH, "HP")


func _on_mana_changed(current: float, max_val: float) -> void:
	_update_bar(_mp_fill, _mp_label, current, max_val, BAR_WIDTH, "MP")


func _on_stamina_changed(current: float, max_val: float) -> void:
	_update_bar(_stam_fill, _stam_label, current, max_val, BAR_WIDTH, "ST")
