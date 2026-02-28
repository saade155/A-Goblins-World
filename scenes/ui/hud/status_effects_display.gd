## StatusEffectsDisplay - Framework for buff/debuff/ailment icons.
##
## Currently idle — no status effects system exists yet.
## Public API ready for a future effects system to feed into.

extends Control

const ICON_SIZE: int = 24
const ICON_GAP: int = 2
const MAX_ICONS: int = 8
const START_X: int = 8
const START_Y: int = 8

var _active_effects: Array[Dictionary] = []
var _effect_nodes: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _active_effects.is_empty():
		return

	# Tick down durations
	var expired: Array[String] = []
	for effect in _active_effects:
		effect["remaining"] -= delta
		if effect["remaining"] <= 0.0:
			expired.append(effect["id"])
		else:
			_update_effect_timer(effect)

	for id in expired:
		remove_effect(id)


## Add or refresh a status effect.
func add_effect(id: String, duration: float, icon_color: Color) -> void:
	# Refresh if already exists
	for effect in _active_effects:
		if effect["id"] == id:
			effect["duration"] = duration
			effect["remaining"] = duration
			return

	if _active_effects.size() >= MAX_ICONS:
		return

	var effect := {
		"id": id,
		"duration": duration,
		"remaining": duration,
		"color": icon_color,
	}
	_active_effects.append(effect)
	_create_effect_node(effect)
	_reposition_effects()


## Remove a status effect immediately.
func remove_effect(id: String) -> void:
	for i in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[i]["id"] == id:
			_active_effects.remove_at(i)
			break

	if _effect_nodes.has(id):
		_effect_nodes[id].queue_free()
		_effect_nodes.erase(id)

	_reposition_effects()


func _create_effect_node(effect: Dictionary) -> void:
	var panel := Panel.new()
	panel.size = Vector2(ICON_SIZE, ICON_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	style.border_color = effect["color"]
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel", style)

	var icon := ColorRect.new()
	icon.position = Vector2(3, 3)
	icon.size = Vector2(ICON_SIZE - 6, ICON_SIZE - 6)
	icon.color = effect["color"]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	var timer_label := Label.new()
	timer_label.position = Vector2(0, ICON_SIZE - 10)
	timer_label.size = Vector2(ICON_SIZE, 10)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 7)
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.name = "TimerLabel"
	panel.add_child(timer_label)

	add_child(panel)
	_effect_nodes[effect["id"]] = panel


func _reposition_effects() -> void:
	var idx: int = 0
	for effect in _active_effects:
		if _effect_nodes.has(effect["id"]):
			var node: Panel = _effect_nodes[effect["id"]]
			node.position = Vector2(START_X + idx * (ICON_SIZE + ICON_GAP), START_Y)
			idx += 1


func _update_effect_timer(effect: Dictionary) -> void:
	if _effect_nodes.has(effect["id"]):
		var node: Panel = _effect_nodes[effect["id"]]
		var label: Label = node.get_node("TimerLabel")
		var secs: int = ceili(effect["remaining"])
		label.text = "%ds" % secs
