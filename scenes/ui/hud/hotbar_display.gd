## HotbarDisplay - Visual hotbar with 10 clickable slots.
##
## Shows item icon textures when available, falling back to colored rectangles.
## Scroll wheel cycles slots. Click selects. Number keys handled by InputManager.

extends Control

# --- Layout constants ---
const SLOT_SIZE: int = 36
const ICON_SIZE: int = 32
const ICON_OFFSET: int = 2
const SLOT_GAP: int = 2
const SLOT_COUNT: int = 10
const TOTAL_WIDTH: int = SLOT_SIZE * SLOT_COUNT + SLOT_GAP * (SLOT_COUNT - 1)  # 378
const BOTTOM_OFFSET: int = SLOT_SIZE + 6  # 42px from bottom edge

# --- Colors ---
const BORDER_NORMAL := Color(0.3, 0.3, 0.3, 0.8)
const BORDER_SELECTED := Color(0.9, 0.75, 0.2, 1.0)
const BG_EMPTY := Color(0.1, 0.1, 0.1, 0.6)
const TORCH_COLOR := Color(0.9, 0.6, 0.2)
const UNKNOWN_COLOR := Color(0.4, 0.4, 0.4)

# --- Slot references ---
var _placeholder_texture: Texture2D = preload("res://assets/items/placeholder_icon.png")
var _slot_panels: Array[Panel] = []
var _slot_icons: Array[ColorRect] = []
var _slot_textures: Array[TextureRect] = []
var _slot_counts: Array[Label] = []
var _slot_styles: Array[StyleBoxFlat] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_slots()
	GameServer.inventory_changed.connect(_update_all)
	GameServer.hotbar_selection_changed.connect(_on_selection_changed)
	_update_all()
	reposition()


func _build_slots() -> void:
	for i in range(SLOT_COUNT):
		# Panel with StyleBoxFlat for border
		var panel := Panel.new()
		panel.position = Vector2.ZERO  # Set by reposition()
		panel.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var style := StyleBoxFlat.new()
		style.bg_color = BG_EMPTY
		style.border_color = BORDER_NORMAL
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		_slot_panels.append(panel)
		_slot_styles.append(style)

		# Item color icon (fallback when no texture exists)
		var icon := ColorRect.new()
		icon.position = Vector2(ICON_OFFSET, ICON_OFFSET)
		icon.size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.color = Color.TRANSPARENT
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
		_slot_icons.append(icon)

		# Item texture icon (shown when icon.png exists for the item)
		var tex_rect := TextureRect.new()
		tex_rect.position = Vector2(ICON_OFFSET, ICON_OFFSET)
		tex_rect.size = Vector2(ICON_SIZE, ICON_SIZE)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex_rect.visible = false
		panel.add_child(tex_rect)
		_slot_textures.append(tex_rect)

		# Stack count label (bottom right corner)
		var count_label := Label.new()
		count_label.position = Vector2(0, 0)
		count_label.size = Vector2(SLOT_SIZE - 4, SLOT_SIZE - 2)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.add_theme_font_size_override("font_size", 8)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.text = ""
		panel.add_child(count_label)
		_slot_counts.append(count_label)

		# Keybind number label (top center)
		var key_label := Label.new()
		key_label.position = Vector2(0, -1)
		key_label.size = Vector2(SLOT_SIZE, 12)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 7)
		key_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.6))
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_label.text = str((i + 1) % 10)
		panel.add_child(key_label)

		# Invisible click button covering the slot
		var btn := Button.new()
		btn.position = Vector2.ZERO
		btn.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		btn.flat = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_slot_clicked.bind(i))
		panel.add_child(btn)


func reposition() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var start_x: float = (viewport_size.x - TOTAL_WIDTH) / 2.0
	var start_y: float = viewport_size.y - BOTTOM_OFFSET
	for i in range(SLOT_COUNT):
		_slot_panels[i].position = Vector2(start_x + i * (SLOT_SIZE + SLOT_GAP), start_y)


func _update_all() -> void:
	for i in range(SLOT_COUNT):
		var slot: Dictionary = GameServer.get_hotbar_slot(i)
		if slot["item_id"] == "":
			_slot_textures[i].visible = false
			_slot_textures[i].texture = null
			_slot_icons[i].visible = false
			_slot_counts[i].text = ""
		else:
			var icon_path: String = ItemDatabase.get_icon_path(slot["item_id"])
			if ResourceLoader.exists(icon_path):
				_slot_textures[i].texture = load(icon_path)
			else:
				_slot_textures[i].texture = _placeholder_texture
			_slot_textures[i].visible = true
			_slot_icons[i].visible = false  # Never need ColorRect anymore
			if slot["amount"] > 1:
				_slot_counts[i].text = str(slot["amount"])
			else:
				_slot_counts[i].text = ""

		# Update selection highlight
		if i == GameServer.selected_hotbar_slot:
			_slot_styles[i].border_color = BORDER_SELECTED
		else:
			_slot_styles[i].border_color = BORDER_NORMAL


func _on_selection_changed(_slot: int) -> void:
	_update_all()


func _on_slot_clicked(slot: int) -> void:
	GameServer.request_select_hotbar(slot)


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
			5: return Color(0.7, 0.7, 0.75)   # WEAPON - bright steel
		return Color(0.6, 0.55, 0.5)  # fallback equipment color
	# Unknown item — bright magenta to indicate missing icon
	return Color(1.0, 0.0, 1.0)
