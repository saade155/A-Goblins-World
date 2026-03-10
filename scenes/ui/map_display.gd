## MapDisplay - Fullscreen map overlay showing the world.
##
## Renders the full world to a cached image (1 tile = 1 pixel).
## Zoom and pan manipulate the sprite transform — no re-rendering needed.
## Re-renders only when opened and tiles have changed (dirty flag).

extends CanvasLayer

var is_open: bool = false
var _map_dirty: bool = true

# Cached world image
var _map_image: Image
var _map_texture: ImageTexture

# UI nodes
var _bg: ColorRect
var _map_sprite: Sprite2D
var _player_marker: ColorRect

# World dimensions (cached on render)
var _world_width: int = 0
var _world_height: int = 0
var _surface_rows: int = 0

# Viewport
var _viewport_center: Vector2 = Vector2(480, 270)

# Zoom
var _zoom_levels: Array[float] = [1.0, 0.5, 0.25, 0.125]
var _zoom_index: int = 1
var _zoom_scale: float = 0.5

# Panning
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _sprite_start: Vector2 = Vector2.ZERO

# Colors
var _tile_colors: Dictionary = {}
var _empty_color: Color = Color(0.05, 0.05, 0.08)
var _fog_color: Color = Color(0.12, 0.08, 0.18)
var _player_color: Color = Color(1.0, 0.2, 0.2)

const MARKER_SIZE: int = 5


func _ready() -> void:
	layer = 10
	visible = false

	# Build color lookup from TileDatabase
	for tile_type in TileDatabase.get_tile_types():
		_tile_colors[tile_type] = TileDatabase.get_properties(tile_type)["color"]

	# Dark background panel
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.85)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Map sprite (centered by default)
	_map_sprite = Sprite2D.new()
	_map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_map_sprite)

	# Player marker (fixed screen size)
	_player_marker = ColorRect.new()
	_player_marker.color = _player_color
	_player_marker.size = Vector2(MARKER_SIZE, MARKER_SIZE)
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player_marker)

	# Mark dirty when tiles change
	GameServer.tile_mined.connect(_on_world_changed)
	GameServer.tile_placed.connect(_on_world_changed)
	ExplorationTracker.debug_fog_toggled.connect(_on_fog_toggled)


func _on_world_changed(_a = null, _b = null, _c = null) -> void:
	_map_dirty = true


func _on_fog_toggled() -> void:
	_map_dirty = true
	if is_open:
		_render_full_image()
		_center_on_player()


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		_close_map()
		get_viewport().set_input_as_handled()


func _close_map() -> void:
	is_open = false
	visible = false
	_is_dragging = false
	GameServer.map_open = false


func _process(_delta: float) -> void:
	# Toggle map
	if not ChatWindow.chat_focused and InputManager.is_map_toggle_just_pressed():
		is_open = not is_open
		visible = is_open
		GameServer.map_open = is_open
		if is_open:
			_open_map()
		else:
			_is_dragging = false

	# Toggle fog (hotkey — signal handler _on_fog_toggled covers re-render)
	if not ChatWindow.chat_focused and InputManager.is_debug_fog_toggle_just_pressed():
		ExplorationTracker.toggle_debug_fog()

	# Update player marker position while open
	if is_open:
		_update_player_marker()


func _open_map() -> void:
	_viewport_center = get_viewport().get_visible_rect().size / 2.0
	if _map_dirty or _map_texture == null:
		_render_full_image()
	_center_on_player()


func _center_on_player() -> void:
	if not GameState.player:
		return
	var player_img := _world_to_image(GameState.player.global_position)
	var img_center := Vector2(_world_width, _world_height) / 2.0
	_map_sprite.position = _viewport_center - (player_img - img_center) * _zoom_scale
	_map_sprite.scale = Vector2(_zoom_scale, _zoom_scale)


func _world_to_image(world_pos: Vector2) -> Vector2:
	return Vector2(world_pos.x / 16.0, world_pos.y / 16.0 + _surface_rows)


func _update_player_marker() -> void:
	if not GameState.player:
		_player_marker.visible = false
		return
	_player_marker.visible = true
	var player_img := _world_to_image(GameState.player.global_position)
	var img_center := Vector2(_world_width, _world_height) / 2.0
	var screen_pos: Vector2 = _map_sprite.position + (player_img - img_center) * _zoom_scale
	_player_marker.position = screen_pos - Vector2(MARKER_SIZE, MARKER_SIZE) / 2.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return

	# Zoom (mouse wheel)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(1)
			get_viewport().set_input_as_handled()

	# Drag pan (left click)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			_drag_start = event.position
			_sprite_start = _map_sprite.position
		else:
			_is_dragging = false
		get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and _is_dragging:
		_map_sprite.position = _sprite_start + (event.position - _drag_start)
		get_viewport().set_input_as_handled()


func _change_zoom(direction: int) -> void:
	var old_index := _zoom_index
	_zoom_index = clampi(_zoom_index + direction, 0, _zoom_levels.size() - 1)
	if _zoom_index == old_index:
		return

	var old_scale := _zoom_scale
	_zoom_scale = _zoom_levels[_zoom_index]

	# Zoom toward screen center: adjust sprite position so center stays fixed
	_map_sprite.position = _viewport_center + (_map_sprite.position - _viewport_center) * (_zoom_scale / old_scale)
	_map_sprite.scale = Vector2(_zoom_scale, _zoom_scale)


## Render the entire world to a cached image. Called once on open when dirty.
## Fog enabled: fill fog, paint explored tiles only.
## Fog disabled: fill empty, paint all solid tiles.
func _render_full_image() -> void:
	var world_data = GameState.world_data
	if not world_data:
		return

	_world_width = world_data.world_width
	_world_height = world_data.world_height
	_surface_rows = world_data.surface_rows

	var w: int = _world_width
	var h: int = _world_height
	var sr: int = _surface_rows

	var buf := PackedByteArray()
	var buf_size: int = w * h * 4
	buf.resize(buf_size)

	var fog_disabled: bool = ExplorationTracker.debug_fog_disabled
	var tile_type_empty: int = TileDatabase.TileType.EMPTY

	if fog_disabled:
		# Fill with empty color, then paint solid tiles
		var er: int = _empty_color.r8
		var eg: int = _empty_color.g8
		var eb: int = _empty_color.b8
		var ea: int = _empty_color.a8
		for i in range(0, buf_size, 4):
			buf[i] = er
			buf[i + 1] = eg
			buf[i + 2] = eb
			buf[i + 3] = ea

		for pos in world_data.tiles:
			var tile_type: int = world_data.tiles[pos]
			if tile_type == tile_type_empty:
				continue
			var ix: int = pos.x
			var iy: int = pos.y + sr
			if ix < 0 or ix >= w or iy < 0 or iy >= h:
				continue
			var color: Color = _tile_colors.get(tile_type, Color.MAGENTA)
			var idx: int = (iy * w + ix) * 4
			buf[idx] = color.r8
			buf[idx + 1] = color.g8
			buf[idx + 2] = color.b8
			buf[idx + 3] = color.a8
	else:
		# Fill with fog, then paint explored tiles
		var fr: int = _fog_color.r8
		var fg_c: int = _fog_color.g8
		var fb: int = _fog_color.b8
		var fa: int = _fog_color.a8
		for i in range(0, buf_size, 4):
			buf[i] = fr
			buf[i + 1] = fg_c
			buf[i + 2] = fb
			buf[i + 3] = fa

		var er: int = _empty_color.r8
		var eg: int = _empty_color.g8
		var eb: int = _empty_color.b8
		var ea: int = _empty_color.a8

		for pos in ExplorationTracker.explored_tiles:
			var ix: int = pos.x
			var iy: int = pos.y + sr
			if ix < 0 or ix >= w or iy < 0 or iy >= h:
				continue
			var tile_type: int = world_data.get_tile(pos)
			var idx: int = (iy * w + ix) * 4
			if tile_type != tile_type_empty:
				var color: Color = _tile_colors.get(tile_type, Color.MAGENTA)
				buf[idx] = color.r8
				buf[idx + 1] = color.g8
				buf[idx + 2] = color.b8
				buf[idx + 3] = color.a8
			else:
				buf[idx] = er
				buf[idx + 1] = eg
				buf[idx + 2] = eb
				buf[idx + 3] = ea

	_map_image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, buf)
	_map_texture = ImageTexture.create_from_image(_map_image)
	_map_sprite.texture = _map_texture
	_map_dirty = false
