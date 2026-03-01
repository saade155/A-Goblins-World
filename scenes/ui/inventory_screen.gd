## InventoryScreen - Full inventory UI with equipment, main grid, hotbar, tooltips, and cursor display.
##
## Extends CanvasLayer. Toggled via "toggle_inventory" input action.
## All click operations delegate to GameServer authority methods.
## Layout: equipment column (left), main inventory 6x5 grid (right), hotbar (bottom center).

extends CanvasLayer

# --- Layout constants ---
const SLOT_SIZE: int = 36
const ICON_SIZE: int = 32
const ICON_OFFSET: int = 2
const SLOT_GAP: int = 2
const MAIN_COLS: int = 6
const MAIN_ROWS: int = 5
const HOTBAR_SLOTS: int = 10
const EQUIP_SLOTS: int = 6
const EQUIP_GAP: int = 12  # gap between equipment column and main grid

const EQUIP_SLOT_NAMES: Array = ["Head", "Chest", "Belt", "Arms", "Legs", "Back"]

# --- Colors ---
const QUALITY_COLORS: Dictionary = {
	0: Color(0.7, 0.7, 0.7),    # CRUDE - gray
	1: Color(1.0, 1.0, 1.0),    # STANDARD - white
	2: Color(0.3, 0.9, 0.3),    # FINE - green
	3: Color(0.3, 0.5, 1.0),    # MASTERWORK - blue
	4: Color(0.7, 0.3, 0.9),    # LEGENDARY - purple
	5: Color(1.0, 0.7, 0.2),    # ANCIENT - gold
}

const BG_EMPTY := Color(0.1, 0.1, 0.1, 0.6)
const BG_EQUIP := Color(0.15, 0.12, 0.1, 0.6)
const BORDER_NORMAL := Color(0.3, 0.3, 0.3, 0.8)
const BORDER_EQUIP := Color(0.5, 0.4, 0.3, 0.8)
const BORDER_HOTBAR_SELECTED := Color(0.9, 0.75, 0.2, 1.0)
const TORCH_COLOR := Color(0.9, 0.6, 0.2)
const UNKNOWN_COLOR := Color(0.4, 0.4, 0.4)

# --- Slot tracking ---
# Each entry: {"area": String, "index": int, "panel": Panel, "icon": ColorRect, "texture": TextureRect, "count": Label, "style": StyleBoxFlat}
var _slots: Array[Dictionary] = []

# --- Equipment labels ---
var _equip_labels: Array[Label] = []

# --- UI elements ---
var _overlay: ColorRect
var _tooltip_panel: PanelContainer
var _tooltip_name: Label
var _tooltip_type: Label
var _tooltip_stats: Label
var _tooltip_desc: Label
var _cursor_icon: ColorRect
var _cursor_texture: TextureRect
var _cursor_count: Label

# --- State ---
var _placeholder_texture: Texture2D = preload("res://assets/items/placeholder_icon.png")
var _is_open: bool = false
var _hovered_slot: int = -1

# --- Drag state ---
var _drag_active: bool = false
var _drag_origin_slot: int = -1
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_pending: bool = false  # Mouse is held but hasn't crossed threshold yet
const DRAG_THRESHOLD: float = 4.0


func _ready() -> void:
	layer = 15

	# Dark overlay — blocks clicks to game world when inventory is open
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.5)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Build equipment slots (6)
	for i in range(EQUIP_SLOTS):
		var label := Label.new()
		label.text = EQUIP_SLOT_NAMES[i]
		label.add_theme_font_size_override("font_size", 7)
		label.add_theme_color_override("font_color", Color(0.6, 0.5, 0.4))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_equip_labels.append(label)
		_build_slot("equipment", i, BG_EQUIP, BORDER_EQUIP)

	# Build main inventory slots (6x5 = 30)
	for row in range(MAIN_ROWS):
		for col in range(MAIN_COLS):
			_build_slot("main", row * MAIN_COLS + col, BG_EMPTY, BORDER_NORMAL)

	# Build hotbar slots (10)
	for i in range(HOTBAR_SLOTS):
		_build_slot("hotbar", i, BG_EMPTY, BORDER_NORMAL)

	_build_tooltip()
	_build_cursor_display()

	# Connect signals
	GameServer.inventory_changed.connect(_refresh_all_slots)
	GameServer.equipment_changed.connect(func(_s: int): _refresh_all_slots())
	GameServer.cursor_item_changed.connect(_update_cursor_display)
	GameServer.hotbar_selection_changed.connect(func(_s: int): _refresh_all_slots())
	get_viewport().size_changed.connect(reposition)

	_set_visible(false)
	reposition()


# ============================================================================
# Slot Construction
# ============================================================================

func _build_slot(area: String, index: int, bg_color: Color, border_color: Color) -> Dictionary:
	var panel := Panel.new()
	panel.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	# Item color icon (fallback when no texture exists)
	var icon := ColorRect.new()
	icon.position = Vector2(ICON_OFFSET, ICON_OFFSET)
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.color = Color.TRANSPARENT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	# Item texture icon (shown when icon.png exists for the item)
	var tex_rect := TextureRect.new()
	tex_rect.position = Vector2(ICON_OFFSET, ICON_OFFSET)
	tex_rect.size = Vector2(ICON_SIZE, ICON_SIZE)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.visible = false
	panel.add_child(tex_rect)

	# Stack count label (bottom right corner)
	var count_label := Label.new()
	count_label.position = Vector2(0, 0)
	count_label.size = Vector2(SLOT_SIZE - 4, SLOT_SIZE - 2)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.add_theme_font_size_override("font_size", 8)
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(count_label)

	# Invisible click button covering the slot
	var btn := Button.new()
	btn.position = Vector2.ZERO
	btn.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	btn.flat = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_NONE
	var slot_idx: int = _slots.size()
	btn.gui_input.connect(_on_slot_gui_input.bind(slot_idx))
	btn.mouse_entered.connect(_on_slot_hover.bind(slot_idx))
	btn.mouse_exited.connect(_on_slot_unhover)
	panel.add_child(btn)

	var slot_data := {"area": area, "index": index, "panel": panel, "icon": icon, "texture": tex_rect, "count": count_label, "style": style}
	_slots.append(slot_data)
	return slot_data


# ============================================================================
# Tooltip
# ============================================================================

func _build_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = Color(0.4, 0.4, 0.4, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(6)
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.visible = false
	add_child(_tooltip_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_tooltip_panel.add_child(vbox)

	_tooltip_name = Label.new()
	_tooltip_name.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_tooltip_name)

	_tooltip_type = Label.new()
	_tooltip_type.add_theme_font_size_override("font_size", 9)
	_tooltip_type.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_tooltip_type)

	_tooltip_stats = Label.new()
	_tooltip_stats.add_theme_font_size_override("font_size", 9)
	_tooltip_stats.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	vbox.add_child(_tooltip_stats)

	_tooltip_desc = Label.new()
	_tooltip_desc.add_theme_font_size_override("font_size", 9)
	_tooltip_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tooltip_desc.custom_minimum_size.x = 150
	vbox.add_child(_tooltip_desc)


# ============================================================================
# Cursor Display
# ============================================================================

func _build_cursor_display() -> void:
	_cursor_icon = ColorRect.new()
	_cursor_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_icon.visible = false
	add_child(_cursor_icon)

	_cursor_texture = TextureRect.new()
	_cursor_texture.size = Vector2(ICON_SIZE, ICON_SIZE)
	_cursor_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_texture.visible = false
	add_child(_cursor_texture)

	_cursor_count = Label.new()
	_cursor_count.size = Vector2(ICON_SIZE, ICON_SIZE)
	_cursor_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cursor_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_cursor_count.add_theme_font_size_override("font_size", 8)
	_cursor_count.add_theme_color_override("font_color", Color.WHITE)
	_cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_count.visible = false
	add_child(_cursor_count)


func _update_cursor_display() -> void:
	if GameServer.cursor_item["item_id"] == "":
		_cursor_icon.visible = false
		_cursor_texture.visible = false
		_cursor_texture.texture = null
		_cursor_count.visible = false
	else:
		var item_id: String = GameServer.cursor_item["item_id"]
		var icon_path: String = ItemDatabase.get_icon_path(item_id)
		if ResourceLoader.exists(icon_path):
			_cursor_texture.texture = load(icon_path)
		else:
			_cursor_texture.texture = _placeholder_texture
		_cursor_texture.visible = true
		_cursor_icon.visible = false  # Never need ColorRect anymore
		if GameServer.cursor_item["amount"] > 1:
			_cursor_count.text = str(GameServer.cursor_item["amount"])
			_cursor_count.visible = true
		else:
			_cursor_count.visible = false


# ============================================================================
# Positioning
# ============================================================================

func reposition() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size

	# Overlay covers full viewport
	_overlay.size = vp_size

	# Calculate total layout dimensions
	var equip_col_width: int = SLOT_SIZE
	var equip_col_height: int = EQUIP_SLOTS * SLOT_SIZE + (EQUIP_SLOTS - 1) * SLOT_GAP
	var main_grid_width: int = MAIN_COLS * SLOT_SIZE + (MAIN_COLS - 1) * SLOT_GAP
	var main_grid_height: int = MAIN_ROWS * SLOT_SIZE + (MAIN_ROWS - 1) * SLOT_GAP
	var hotbar_width: int = HOTBAR_SLOTS * SLOT_SIZE + (HOTBAR_SLOTS - 1) * SLOT_GAP

	# Total width: equipment column + gap + main grid
	var total_width: int = equip_col_width + EQUIP_GAP + main_grid_width
	# Total height: taller of equipment column vs main grid, plus gap, plus hotbar
	var upper_height: int = maxi(equip_col_height, main_grid_height)
	var hotbar_gap: int = 8
	var label_height: int = 10  # space for equipment slot labels above slots

	# Center the whole layout
	var layout_x: float = (vp_size.x - total_width) / 2.0
	var layout_y: float = (vp_size.y - (upper_height + hotbar_gap + SLOT_SIZE)) / 2.0

	# Equipment column (left side, vertically centered within upper area)
	var equip_x: float = layout_x
	var equip_start_y: float = layout_y + (upper_height - equip_col_height) / 2.0

	# Slot indices: first 6 slots in _slots are equipment
	for i in range(EQUIP_SLOTS):
		var slot_y: float = equip_start_y + i * (SLOT_SIZE + SLOT_GAP)
		_slots[i]["panel"].position = Vector2(equip_x, slot_y)
		# Label above the slot
		_equip_labels[i].position = Vector2(equip_x, slot_y - label_height)
		_equip_labels[i].size = Vector2(SLOT_SIZE, label_height)

	# Main grid (right of equipment column)
	var main_x: float = layout_x + equip_col_width + EQUIP_GAP
	var main_start_y: float = layout_y + (upper_height - main_grid_height) / 2.0

	# Slot indices: 6..35 are main inventory (6 equipment + 30 main)
	for row in range(MAIN_ROWS):
		for col in range(MAIN_COLS):
			var slot_idx: int = EQUIP_SLOTS + row * MAIN_COLS + col
			var sx: float = main_x + col * (SLOT_SIZE + SLOT_GAP)
			var sy: float = main_start_y + row * (SLOT_SIZE + SLOT_GAP)
			_slots[slot_idx]["panel"].position = Vector2(sx, sy)

	# Hotbar (centered below the grid)
	var hotbar_x: float = (vp_size.x - hotbar_width) / 2.0
	var hotbar_y: float = layout_y + upper_height + hotbar_gap

	# Slot indices: 36..45 are hotbar (6 equipment + 30 main + 10 hotbar)
	var hotbar_start: int = EQUIP_SLOTS + MAIN_COLS * MAIN_ROWS
	for i in range(HOTBAR_SLOTS):
		var slot_idx: int = hotbar_start + i
		var sx: float = hotbar_x + i * (SLOT_SIZE + SLOT_GAP)
		_slots[slot_idx]["panel"].position = Vector2(sx, hotbar_y)


# ============================================================================
# Toggle / Open / Close
# ============================================================================

func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	# Don't toggle inventory while the debug console is open (user is typing).
	if DebugConsole.console_open:
		return
	if event.is_action_pressed("toggle_inventory"):
		_toggle()
		get_viewport().set_input_as_handled()
	# Close on Escape if open
	if _is_open and event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()
	# Drag release detection (left mouse up anywhere)
	if _is_open and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag_active or _drag_pending:
			_on_drag_release()


func _toggle() -> void:
	if _is_open:
		_close()
	else:
		_open()


func _open() -> void:
	_is_open = true
	GameServer.set_inventory_open(true)
	_set_visible(true)
	_refresh_all_slots()


func _close() -> void:
	_is_open = false
	_drag_active = false
	_drag_pending = false
	_drag_origin_slot = -1
	GameServer.set_inventory_open(false)
	_set_visible(false)
	_tooltip_panel.visible = false


# ============================================================================
# Click & Drag Handling
# ============================================================================

func _on_slot_gui_input(event: InputEvent, slot_idx: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		_on_slot_right_click(slot_idx)
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		var s: Dictionary = _slots[slot_idx]
		var area: String = s["area"]
		var index: int = s["index"]

		# Shift+click: quick move (unchanged)
		if Input.is_key_pressed(KEY_SHIFT):
			GameServer.request_quick_move(area, index)
			return

		# Cursor already has an item: place or swap immediately on press
		if GameServer.cursor_item["item_id"] != "":
			GameServer.request_place_to_slot(area, index)
			return

		# Cursor empty, slot has item: start drag pending
		var slot: Dictionary = GameServer.get_slot(area, index)
		if slot["item_id"] != "":
			_drag_pending = true
			_drag_origin_slot = slot_idx
			_drag_start_pos = get_viewport().get_mouse_position()


func _on_drag_release() -> void:
	if _drag_active:
		# Dragging an item — try to place it
		if _hovered_slot >= 0:
			var s: Dictionary = _slots[_hovered_slot]
			GameServer.request_place_to_slot(s["area"], s["index"])
		elif _drag_origin_slot >= 0:
			# Released outside any slot — return to origin
			var s: Dictionary = _slots[_drag_origin_slot]
			GameServer.request_place_to_slot(s["area"], s["index"])
	elif _drag_pending and _drag_origin_slot >= 0:
		# Quick tap without dragging — pick up (standard click behavior)
		var s: Dictionary = _slots[_drag_origin_slot]
		GameServer.request_pickup_from_slot(s["area"], s["index"])
	_drag_active = false
	_drag_pending = false
	_drag_origin_slot = -1


func _on_slot_right_click(slot_idx: int) -> void:
	var s: Dictionary = _slots[slot_idx]
	var area: String = s["area"]
	var index: int = s["index"]

	if GameServer.cursor_item["item_id"] == "":
		# Pick up half
		var slot: Dictionary = GameServer.get_slot(area, index)
		if slot["item_id"] == "":
			return
		var half: int = maxi(slot["amount"] / 2, 1)
		GameServer.request_pickup_from_slot(area, index, half)
	else:
		# Place one
		GameServer.request_place_to_slot(area, index, 1)


# ============================================================================
# Slot Refresh
# ============================================================================

func _refresh_all_slots() -> void:
	for i in range(_slots.size()):
		_refresh_slot(i)


func _refresh_slot(slot_idx: int) -> void:
	var s: Dictionary = _slots[slot_idx]
	var slot: Dictionary = GameServer.get_slot(s["area"], s["index"])
	if slot["item_id"] == "":
		s["texture"].visible = false
		s["texture"].texture = null
		s["icon"].visible = false
		s["count"].text = ""
	else:
		var icon_path: String = ItemDatabase.get_icon_path(slot["item_id"])
		if ResourceLoader.exists(icon_path):
			s["texture"].texture = load(icon_path)
		else:
			s["texture"].texture = _placeholder_texture
		s["texture"].visible = true
		s["icon"].visible = false  # Never need ColorRect anymore
		s["count"].text = str(slot["amount"]) if slot["amount"] > 1 else ""
	# Hotbar selection highlight
	if s["area"] == "hotbar" and s["index"] == GameServer.selected_hotbar_slot:
		s["style"].border_color = BORDER_HOTBAR_SELECTED
	elif s["area"] == "equipment":
		s["style"].border_color = BORDER_EQUIP
	else:
		s["style"].border_color = BORDER_NORMAL


# ============================================================================
# Item Colors
# ============================================================================

func _get_item_color(item_id: String) -> Color:
	# Tile-based items get their biome color
	var tile_type: int = ItemDatabase.get_tile_type(item_id)
	if tile_type > 0:
		var props: Dictionary = TileDatabase.get_properties(tile_type)
		return props.get("color", UNKNOWN_COLOR)
	# Special items
	if item_id == "torch":
		return TORCH_COLOR
	# Equipment — distinct color per slot
	if ItemDatabase.is_equippable(item_id):
		var equip_slot: int = ItemDatabase.get_equip_slot(item_id)
		match equip_slot:
			0: return Color(0.6, 0.5, 0.35)   # HEAD - bronze
			1: return Color(0.5, 0.5, 0.55)   # CHEST - steel
			2: return Color(0.55, 0.4, 0.25)  # BELT - leather
			3: return Color(0.45, 0.45, 0.5)  # ARMS - iron
			4: return Color(0.4, 0.4, 0.45)   # LEGS - iron
			5: return Color(0.5, 0.35, 0.2)   # BACK - leather/cloth
		return Color(0.6, 0.55, 0.5)  # fallback equipment color
	# Unknown item — bright magenta to indicate missing icon
	return Color(1.0, 0.0, 1.0)


# ============================================================================
# Tooltip Hover
# ============================================================================

func _on_slot_hover(slot_idx: int) -> void:
	_hovered_slot = slot_idx
	var s: Dictionary = _slots[slot_idx]
	var slot: Dictionary = GameServer.get_slot(s["area"], s["index"])
	if slot["item_id"] != "":
		_show_tooltip(slot["item_id"], slot["quality"])
	else:
		_tooltip_panel.visible = false


func _on_slot_unhover() -> void:
	_hovered_slot = -1
	_tooltip_panel.visible = false


func _show_tooltip(item_id: String, quality: int) -> void:
	var item_def: Dictionary = ItemDatabase.get_item(item_id)
	if item_def.is_empty():
		_tooltip_panel.visible = false
		return

	_tooltip_name.text = item_def["name"]
	_tooltip_name.add_theme_color_override("font_color", QUALITY_COLORS.get(quality, Color.WHITE))

	var type_names := ["Material", "Placeable", "Tool", "Weapon", "Consumable", "Equipment"]
	var type_idx: int = item_def.get("type", 0)
	_tooltip_type.text = type_names[type_idx] if type_idx < type_names.size() else "Unknown"

	var meta: Dictionary = item_def.get("metadata", {})
	var stats: Dictionary = meta.get("stats", {})
	if stats.is_empty():
		_tooltip_stats.visible = false
	else:
		_tooltip_stats.visible = true
		var parts: PackedStringArray = PackedStringArray()
		for key in stats:
			parts.append("+%.0f %s" % [stats[key], key])
		_tooltip_stats.text = ", ".join(parts)

	var desc: String = meta.get("description", "")
	_tooltip_desc.visible = desc != ""
	_tooltip_desc.text = desc

	_tooltip_panel.visible = true


func _update_tooltip_position() -> void:
	if not _tooltip_panel.visible:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tp_size: Vector2 = _tooltip_panel.size
	var pos: Vector2 = mouse_pos + Vector2(16, 16)
	# Keep within viewport
	if pos.x + tp_size.x > vp_size.x:
		pos.x = mouse_pos.x - tp_size.x - 8
	if pos.y + tp_size.y > vp_size.y:
		pos.y = mouse_pos.y - tp_size.y - 8
	_tooltip_panel.position = pos


# ============================================================================
# Process — cursor tracking and tooltip position
# ============================================================================

func _process(_delta: float) -> void:
	if not _is_open:
		return
	# Check drag threshold
	if _drag_pending and not _drag_active:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		if mouse_pos.distance_to(_drag_start_pos) > DRAG_THRESHOLD:
			# Threshold crossed — pick up item and start drag
			var s: Dictionary = _slots[_drag_origin_slot]
			GameServer.request_pickup_from_slot(s["area"], s["index"])
			_drag_pending = false
			_drag_active = true
	# Update cursor position
	if _cursor_icon.visible or _cursor_texture.visible:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var cursor_offset: Vector2 = mouse_pos + Vector2(8, 8)
		_cursor_icon.position = cursor_offset
		_cursor_texture.position = cursor_offset
		_cursor_count.position = cursor_offset
	# Update tooltip position
	_update_tooltip_position()


# ============================================================================
# Visibility
# ============================================================================

func _set_visible(vis: bool) -> void:
	for child in get_children():
		if child is CanvasItem:
			child.visible = vis
	if vis:
		_update_cursor_display()
	else:
		_tooltip_panel.visible = false
		_cursor_icon.visible = false
		_cursor_texture.visible = false
		_cursor_count.visible = false
