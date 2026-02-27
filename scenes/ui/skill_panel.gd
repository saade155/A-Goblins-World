extends CanvasLayer

signal panel_closed

var _is_open: bool = false
var _current_category: int = 0  # SkillSystem.SkillCategory.PROFICIENCY
var _skill_list_container: VBoxContainer = null
var _category_buttons: Array[Button] = []
var _button_group: ButtonGroup = null


func _ready() -> void:
	_build_ui()
	_set_visible(false)

	# Connect to SkillSystem signals for live updates
	SkillSystem.skill_leveled.connect(_on_skill_leveled)
	SkillSystem.perk_unlocked.connect(_on_perk_unlocked)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_skills"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	if _is_open:
		_close()
	else:
		_open()


func _open() -> void:
	_is_open = true
	_set_visible(true)
	_populate_skills(_current_category)
	get_tree().paused = true


func _close() -> void:
	_is_open = false
	_set_visible(false)
	get_tree().paused = false
	panel_closed.emit()


func _set_visible(vis: bool) -> void:
	for child in get_children():
		if child is CanvasItem:
			child.visible = vis


# --- UI Construction ---

func _build_ui() -> void:
	# Overlay (semi-transparent background)
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	# Center container
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Main panel
	var panel := PanelContainer.new()
	panel.name = "MainPanel"
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15)
	panel_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	# Margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	# Root VBox
	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	# --- Header row ---
	var header := HBoxContainer.new()
	root_vbox.add_child(header)

	var title_label := Label.new()
	title_label.text = "Skills"
	title_label.add_theme_font_size_override("font_size", 20)
	header.add_child(title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_hint := Label.new()
	close_hint.text = "[K] Close"
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	header.add_child(close_hint)

	# Separator
	var sep := HSeparator.new()
	root_vbox.add_child(sep)

	# --- Main content (tabs + skill list) ---
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(content_hbox)

	# Category tabs (left column)
	var category_vbox := VBoxContainer.new()
	category_vbox.custom_minimum_size.x = 120
	category_vbox.add_theme_constant_override("separation", 4)
	content_hbox.add_child(category_vbox)

	_button_group = ButtonGroup.new()

	var btn_proficiencies := Button.new()
	btn_proficiencies.text = "Proficiencies"
	btn_proficiencies.toggle_mode = true
	btn_proficiencies.button_pressed = true
	btn_proficiencies.button_group = _button_group
	btn_proficiencies.pressed.connect(_on_category_pressed.bind(0))
	category_vbox.add_child(btn_proficiencies)
	_category_buttons.append(btn_proficiencies)

	var btn_resistances := Button.new()
	btn_resistances.text = "Resistances"
	btn_resistances.toggle_mode = true
	btn_resistances.button_group = _button_group
	btn_resistances.pressed.connect(_on_category_pressed.bind(1))
	category_vbox.add_child(btn_resistances)
	_category_buttons.append(btn_resistances)

	var btn_class := Button.new()
	btn_class.text = "Class"
	btn_class.toggle_mode = true
	btn_class.button_group = _button_group
	btn_class.disabled = true
	btn_class.modulate = Color(0.5, 0.5, 0.5)
	category_vbox.add_child(btn_class)
	_category_buttons.append(btn_class)

	# Vertical separator
	var vsep := VSeparator.new()
	content_hbox.add_child(vsep)

	# Skill list area (right column)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_hbox.add_child(scroll)

	_skill_list_container = VBoxContainer.new()
	_skill_list_container.name = "SkillListContainer"
	_skill_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_skill_list_container)


# --- Skill List Population ---

func _on_category_pressed(category: int) -> void:
	_current_category = category
	_populate_skills(category)


func _populate_skills(category: int) -> void:
	# Clear existing children
	for child in _skill_list_container.get_children():
		child.queue_free()

	# Get all skill definitions for this category (show all, not just acquired)
	var skill_ids: Array = []
	for skill_id in SkillSystem.SKILL_DEFS:
		var def: Dictionary = SkillSystem.SKILL_DEFS[skill_id]
		if def["category"] == category:
			skill_ids.append(skill_id)

	if skill_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No skills in this category."
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_skill_list_container.add_child(empty_label)
		return

	for skill_id in skill_ids:
		_build_skill_row(skill_id)


func _build_skill_row(skill_id: String) -> void:
	var def: Dictionary = SkillSystem.SKILL_DEFS[skill_id]
	var is_acquired: bool = SkillSystem.skills.has(skill_id)
	var level: int = SkillSystem.get_skill_level(skill_id)
	var xp: float = SkillSystem.get_skill_xp(skill_id)
	var xp_needed: float = SkillSystem.get_xp_for_next_level(skill_id)
	var xp_ratio: float = SkillSystem.get_xp_progress_ratio(skill_id)
	var perks_unlocked: Array = []
	if is_acquired:
		perks_unlocked = SkillSystem.skills[skill_id].get("perks_unlocked", [])

	# Outer container for this skill entry
	var skill_vbox := VBoxContainer.new()
	skill_vbox.add_theme_constant_override("separation", 2)
	_skill_list_container.add_child(skill_vbox)

	# Main row: name + XP bar
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	skill_vbox.add_child(row)

	# Left side: name + level
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = def["name"]
	if perks_unlocked.size() > 0:
		name_label.add_theme_font_size_override("font_size", 16)
	info_vbox.add_child(name_label)

	var level_label := Label.new()
	if is_acquired:
		level_label.text = "Level %d" % level
	else:
		level_label.text = "Not yet acquired"
	level_label.add_theme_font_size_override("font_size", 12)
	level_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_vbox.add_child(level_label)

	# Right side: XP bar area
	var xp_vbox := VBoxContainer.new()
	row.add_child(xp_vbox)

	var xp_label := Label.new()
	if is_acquired:
		if level >= 50:
			xp_label.text = "MAX LEVEL"
		else:
			xp_label.text = "XP: %d / %d" % [int(xp), int(xp_needed)]
	else:
		xp_label.text = ""
	xp_label.add_theme_font_size_override("font_size", 12)
	xp_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	xp_vbox.add_child(xp_label)

	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(150, 16)
	progress.max_value = 100.0
	progress.value = xp_ratio * 100.0 if is_acquired else 0.0
	progress.show_percentage = false
	# Style the progress bar green
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.7, 0.3)
	fill_style.set_corner_radius_all(2)
	progress.add_theme_stylebox_override("fill", fill_style)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2)
	bg_style.set_corner_radius_all(2)
	progress.add_theme_stylebox_override("background", bg_style)
	xp_vbox.add_child(progress)

	# Show unlocked perks below the row
	if perks_unlocked.size() > 0:
		for perk_id in perks_unlocked:
			if SkillSystem.PERK_DEFS.has(perk_id):
				var perk_def: Dictionary = SkillSystem.PERK_DEFS[perk_id]
				var perk_label := Label.new()
				perk_label.text = "    %s - %s" % [perk_def["name"], perk_def["description"]]
				perk_label.add_theme_font_size_override("font_size", 12)
				perk_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.4))
				skill_vbox.add_child(perk_label)

	# Separator between skills
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	_skill_list_container.add_child(sep)


# --- Signal Handlers ---

func _on_skill_leveled(_skill_id: String, _new_level: int) -> void:
	if _is_open:
		_populate_skills(_current_category)


func _on_perk_unlocked(_skill_id: String, _perk_id: String, _skill_level: int) -> void:
	if _is_open:
		_populate_skills(_current_category)
