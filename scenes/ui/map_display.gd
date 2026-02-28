## MapDisplay - Fullscreen map overlay showing a zoomed-out snapshot of the world.
##
## Each tile = 1 pixel. Renders once when opened (snapshot), not continuously.
## Explored areas are visible; unexplored areas are fog of war.
## F3 toggles fog off (dev tool) to see the full world including ungenerated areas.
## Mouse wheel zooms in/out. Click-and-drag pans the view. Tab toggles the map.
## Map re-centers on the player each time it is opened.

extends CanvasLayer

## Whether the map overlay is currently visible.
var is_open: bool = false

## The raw image buffer for the map.
var map_image: Image

## Texture wrapping the map image.
var map_texture: ImageTexture

## Sprite node that displays the map texture on screen.
var map_sprite: Sprite2D

## Semi-transparent background panel behind the map.
var bg: ColorRect

# --- Map settings ---

## Map image dimensions in pixels (1 pixel = 1 tile at zoom 1).
const MAP_SIZE: int = 512

## Half of MAP_SIZE.
const MAP_TILE_RADIUS: int = 256

# --- Zoom settings ---

## Available zoom levels. Each value = tiles per pixel.
var zoom_levels: Array[int] = [1, 2, 4, 8]
var current_zoom_index: int = 0
var zoom_level: int = 1

# --- Colors ---

## Lookup table: TileType -> Color. Built from TileDatabase on _ready().
var tile_colors: Dictionary = {}

## Color for empty/cave tiles.
var empty_color: Color = Color(0.05, 0.05, 0.08)

## Color for unexplored (fog of war) areas - distinct dark purple-gray.
var fog_color: Color = Color(0.12, 0.08, 0.18)

## Color for the player marker.
var player_color: Color = Color(1.0, 0.2, 0.2)

# --- Panning state ---

## Tile-space offset from the player position. Reset to zero when map is opened.
var map_offset: Vector2i = Vector2i.ZERO

## Whether the user is currently dragging the map.
var is_dragging: bool = false

## Pixel offset accumulated during drag (applied to sprite, not re-rendered).
var drag_pixel_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = 10
	visible = false

	# Build color lookup from TileDatabase
	for tile_type in TileDatabase.get_tile_types():
		tile_colors[tile_type] = TileDatabase.get_properties(tile_type)["color"]

	# Create the map image and texture
	map_image = Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	map_texture = ImageTexture.create_from_image(map_image)

	# Dark background panel
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Map sprite centered on viewport
	map_sprite = Sprite2D.new()
	map_sprite.texture = map_texture
	map_sprite.position = Vector2(320, 180)  # Center of 640x360 viewport
	map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(map_sprite)


func _process(_delta: float) -> void:
	# Toggle map
	if InputManager.is_map_toggle_just_pressed():
		is_open = not is_open
		visible = is_open
		if is_open:
			map_offset = Vector2i.ZERO
			drag_pixel_offset = Vector2.ZERO
			map_sprite.position = Vector2(320, 180)
			_render_map()
		else:
			is_dragging = false
			drag_pixel_offset = Vector2.ZERO
			map_sprite.position = Vector2(320, 180)

	# Toggle fog (re-render if map is open)
	if InputManager.is_debug_fog_toggle_just_pressed():
		ExplorationTracker.toggle_debug_fog()
		if is_open:
			_render_map()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return

	# Zoom (mouse wheel)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out()
			get_viewport().set_input_as_handled()

	# Drag panning (left click)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_pixel_offset = Vector2.ZERO
		else:
			# Drag ended - convert pixel offset to tile offset and re-render once
			is_dragging = false
			map_offset -= Vector2i(
				int(drag_pixel_offset.x) * zoom_level,
				int(drag_pixel_offset.y) * zoom_level
			)
			drag_pixel_offset = Vector2.ZERO
			map_sprite.position = Vector2(320, 180)
			_render_map()
		get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and is_dragging:
		# Move the sprite directly - no re-render during drag
		drag_pixel_offset += event.relative
		map_sprite.position = Vector2(320, 180) + drag_pixel_offset
		get_viewport().set_input_as_handled()


func _zoom_in() -> void:
	if current_zoom_index > 0:
		current_zoom_index -= 1
		zoom_level = zoom_levels[current_zoom_index]
		_render_map()


func _zoom_out() -> void:
	if current_zoom_index < zoom_levels.size() - 1:
		current_zoom_index += 1
		zoom_level = zoom_levels[current_zoom_index]
		_render_map()


## Render a snapshot of the map centered on the player (plus any pan offset).
## Called once on open, zoom change, fog toggle, or drag pan. No continuous rendering.
func _render_map() -> void:
	if not GameState.player:
		return

	var player_pos: Vector2 = GameState.player.global_position
	var player_tile := Vector2i(
		floori(player_pos.x / 16.0),
		floori(player_pos.y / 16.0)
	)

	var center_tile: Vector2i = player_tile + map_offset
	var half_range: int = MAP_TILE_RADIUS * zoom_level
	var map_origin_tile: Vector2i = center_tile - Vector2i(half_range, half_range)

	# Clear to fog color
	map_image.fill(fog_color)

	var fog_disabled: bool = ExplorationTracker.debug_fog_disabled
	var generator: WorldGenerator = GameState.world_generator

	for px in range(MAP_SIZE):
		for py in range(MAP_SIZE):
			var world_tile: Vector2i = map_origin_tile + Vector2i(px * zoom_level, py * zoom_level)

			# Fog of war: skip unexplored tiles (unless fog is disabled)
			if not fog_disabled and not ExplorationTracker.is_tile_explored(world_tile):
				continue

			# Try world data first (has actual generated/modified tiles)
			var tile_type: int = GameState.world_data.get_tile(world_tile)

			if tile_type != TileDatabase.TileType.EMPTY:
				map_image.set_pixel(px, py, tile_colors.get(tile_type, Color.MAGENTA))
			elif GameState.world_data.has_tile(world_tile):
				# Tile exists in world data as empty (was mined or is a generated cave)
				map_image.set_pixel(px, py, empty_color)
			elif fog_disabled and generator:
				# Tile not in world data at all - query generator directly
				var gen_tile: int = generator.get_tile_at(world_tile.x, world_tile.y)
				if gen_tile != TileDatabase.TileType.EMPTY:
					map_image.set_pixel(px, py, tile_colors.get(gen_tile, Color.MAGENTA))
				else:
					map_image.set_pixel(px, py, empty_color)
			else:
				map_image.set_pixel(px, py, empty_color)

	# Player marker (3x3 red dot). Position shifts when the view is panned.
	var player_px: int = MAP_TILE_RADIUS - map_offset.x / zoom_level
	var player_py: int = MAP_TILE_RADIUS - map_offset.y / zoom_level
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var sx: int = player_px + dx
			var sy: int = player_py + dy
			if sx >= 0 and sx < MAP_SIZE and sy >= 0 and sy < MAP_SIZE:
				map_image.set_pixel(sx, sy, player_color)

	map_texture.update(map_image)
