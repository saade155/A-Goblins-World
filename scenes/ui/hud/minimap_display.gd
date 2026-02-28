## MinimapDisplay - Small terrain overview in the top-right corner.
##
## Renders a 128x96 image at 4 tiles per pixel, centered on the player.
## Updates every 0.5 seconds and on tile changes.

extends Control

const MAP_W: int = 128
const MAP_H: int = 96
const TILES_PER_PX: int = 4
const HALF_W: int = 64
const HALF_H: int = 48
const MARGIN: int = 8
const BORDER: int = 1

var _pos_x: int = 0
var _pos_y: int = MARGIN

var _map_image: Image
var _map_texture: ImageTexture
var _map_sprite: Sprite2D
var _border_rect: ColorRect
var _dirty: bool = true
var _timer: float = 0.0

# Color lookup (built from TileDatabase)
var _tile_colors: Dictionary = {}
var _empty_color := Color(0.05, 0.05, 0.08)
var _fog_color := Color(0.12, 0.08, 0.18)
var _player_color := Color(1.0, 0.2, 0.2)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Build tile color lookup
	for tile_type in TileDatabase.get_tile_types():
		_tile_colors[tile_type] = TileDatabase.get_properties(tile_type)["color"]

	# Border frame
	_border_rect = ColorRect.new()
	_border_rect.size = Vector2(MAP_W + BORDER * 2, MAP_H + BORDER * 2)
	_border_rect.color = Color(0.2, 0.2, 0.2, 0.8)
	_border_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_border_rect)

	# Map image + texture
	_map_image = Image.create(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	_map_texture = ImageTexture.create_from_image(_map_image)

	_map_sprite = Sprite2D.new()
	_map_sprite.texture = _map_texture
	_map_sprite.centered = false
	_map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_map_sprite)

	# Listen for tile changes to mark dirty
	GameServer.tile_mined.connect(_on_world_changed)
	GameServer.tile_placed.connect(_on_world_changed)
	GameServer.torch_placed.connect(_on_torch_changed)
	GameServer.torch_removed.connect(_on_torch_changed)

	reposition()


func reposition() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	_pos_x = int(vp_size.x) - MAP_W - MARGIN - BORDER * 2
	_pos_y = MARGIN
	_border_rect.position = Vector2(_pos_x - BORDER, _pos_y - BORDER)
	_map_sprite.position = Vector2(_pos_x, _pos_y)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		_render()
	elif _dirty:
		_dirty = false
		_render()


func _on_world_changed(_pos, _type = null, _tool = null) -> void:
	_dirty = true


func _on_torch_changed(_pos) -> void:
	_dirty = true


func _render() -> void:
	if not GameState.player:
		return

	var player_pos: Vector2 = GameState.player.global_position
	var player_tile := Vector2i(
		floori(player_pos.x / 16.0),
		floori(player_pos.y / 16.0)
	)

	var origin := player_tile - Vector2i(HALF_W * TILES_PER_PX, HALF_H * TILES_PER_PX)

	_map_image.fill(_fog_color)

	var fog_disabled: bool = ExplorationTracker.debug_fog_disabled

	for px in range(MAP_W):
		for py in range(MAP_H):
			var world_tile := origin + Vector2i(px * TILES_PER_PX, py * TILES_PER_PX)

			if not fog_disabled and not ExplorationTracker.is_tile_explored(world_tile):
				continue

			var tile_type: int = GameState.world_data.get_tile(world_tile)
			if tile_type != TileDatabase.TileType.EMPTY:
				_map_image.set_pixel(px, py, _tile_colors.get(tile_type, Color.MAGENTA))
			elif GameState.world_data.has_tile(world_tile):
				_map_image.set_pixel(px, py, _empty_color)
			else:
				_map_image.set_pixel(px, py, _empty_color)

	# Player marker — 3x3 dot at center
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var sx: int = HALF_W + dx
			var sy: int = HALF_H + dy
			if sx >= 0 and sx < MAP_W and sy >= 0 and sy < MAP_H:
				_map_image.set_pixel(sx, sy, _player_color)

	_map_texture.update(_map_image)
