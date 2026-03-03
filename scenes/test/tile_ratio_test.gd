extends Node2D

## Tile Ratio Test — visual comparison of different tile sizes relative to player.
## Run this scene standalone (F6) to see the comparison.
## Left/Right arrows cycle tile sizes. Escape quits.
## No autoloads required.

# Viewport dimensions (match project default).
const VP_W := 960
const VP_H := 540

# Player rectangle in pixels (consistent across all views).
const PLAYER_W := 32
const PLAYER_H := 48

# Configurations: [label, tile_size]
const CONFIGS: Array = [
	["32 px  (current)", 32],
	["16 px", 16],
	["12 px", 12],
	["10 px", 10],
]

# Colours
const COL_BG := Color(0.12, 0.12, 0.15)
const COL_GRID := Color(0.25, 0.25, 0.30, 0.35)
const COL_GROUND := Color(0.45, 0.28, 0.12)
const COL_WALL := Color(0.40, 0.40, 0.42)
const COL_ORE := Color(0.85, 0.55, 0.15)
const COL_PLAYER := Color(0.2, 0.75, 0.3)
const COL_LABEL := Color(0.9, 0.9, 0.9)
const COL_SUBLABEL := Color(0.65, 0.65, 0.7)
const COL_CAVE_BG := Color(0.18, 0.14, 0.12)
const COL_HINT := Color(0.5, 0.5, 0.55)

var current_index: int = 0


func _ready() -> void:
	get_window().title = "Tile Ratio Test"


func _draw() -> void:
	# Full background
	draw_rect(Rect2(0, 0, VP_W, VP_H), COL_BG)

	var font: Font = ThemeDB.fallback_font
	var font_large := 20
	var font_medium := 15
	var font_small := 13

	var label: String = CONFIGS[current_index][0]
	var tile_sz: int = CONFIGS[current_index][1]

	# --- Header ---
	var ratio_val: float = float(PLAYER_H) / tile_sz
	var header_text := "Tile Size: %s" % label
	var ratio_text := "Player is %.1f tiles tall  |  %d x %d px player  |  %d px tiles" % [ratio_val, PLAYER_W, PLAYER_H, tile_sz]

	draw_string(font, Vector2(20, 24), header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_large, COL_LABEL)
	draw_string(font, Vector2(20, 44), ratio_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_medium, COL_SUBLABEL)

	# Page indicator (e.g. "1 / 4")
	var page_text := "%d / %d" % [current_index + 1, CONFIGS.size()]
	draw_string(font, Vector2(VP_W - 80, 24), page_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_large, COL_SUBLABEL)

	# --- Terrain area ---
	var area_top := 56.0
	var area_bottom := VP_H - 30.0
	var area_left := 20.0
	var area_right := VP_W - 20.0
	var area_w := area_right - area_left
	var area_h := area_bottom - area_top

	# How many tiles fit
	var cols: int = int(area_w / tile_sz)
	var rows: int = int(area_h / tile_sz)
	cols = mini(cols, 80)
	rows = mini(rows, 60)

	# Center the tile grid within the area
	var grid_w: float = cols * tile_sz
	var grid_h: float = rows * tile_sz
	var ox: float = area_left + (area_w - grid_w) * 0.5
	var oy: float = area_top + (area_h - grid_h) * 0.5

	# --- Grid lines ---
	for c in range(cols + 1):
		var gx: float = ox + c * tile_sz
		draw_line(Vector2(gx, oy), Vector2(gx, oy + grid_h), COL_GRID, 1.0)
	for r in range(rows + 1):
		var gy: float = oy + r * tile_sz
		draw_line(Vector2(ox, gy), Vector2(ox + grid_w, gy), COL_GRID, 1.0)

	# --- Build terrain ---
	var player_tiles_h: int = ceili(float(PLAYER_H) / tile_sz)

	# Ground level: place it so roughly 60% of rows are above ground.
	var ground_row: int = int(rows * 0.6)

	# -- Flat ground (full width, 3 tiles deep) --
	for c in range(cols):
		for r in range(ground_row, mini(ground_row + 3, rows)):
			_draw_tile(ox, oy, c, r, tile_sz, COL_GROUND)

	# Fill everything below ground+3 as ground too
	for c in range(cols):
		for r in range(mini(ground_row + 3, rows), rows):
			_draw_tile(ox, oy, c, r, tile_sz, COL_GROUND)

	# -- 1-tile thick wall (left area) --
	var wall1_col := 3
	var wall_top := maxi(ground_row - player_tiles_h - 5, 0)
	for r in range(wall_top, ground_row):
		_draw_tile(ox, oy, wall1_col, r, tile_sz, COL_WALL)

	# -- Doorway wall (center-left) --
	# A wall with a player-height gap at the bottom so the player can walk through.
	var door_col: int = int(cols * 0.3)
	var door_gap_top: int = ground_row - player_tiles_h
	# Wall above the doorway
	for r in range(maxi(ground_row - player_tiles_h - 6, 0), maxi(door_gap_top, 0)):
		_draw_tile(ox, oy, door_col, r, tile_sz, COL_WALL)

	# -- 2-tile thick wall with ore (center-right) --
	var wall2_col: int = int(cols * 0.55)
	var wall2_top := maxi(ground_row - player_tiles_h - 6, 0)
	for r in range(wall2_top, ground_row):
		_draw_tile(ox, oy, wall2_col, r, tile_sz, COL_WALL)
		if wall2_col + 1 < cols:
			_draw_tile(ox, oy, wall2_col + 1, r, tile_sz, COL_WALL)

	# Ore tiles embedded in the 2-tile wall
	var ore_row1: int = ground_row - int(player_tiles_h * 0.5)
	if ore_row1 >= wall2_top:
		_draw_tile(ox, oy, wall2_col, ore_row1, tile_sz, COL_ORE)
	var ore_row2: int = ground_row - int(player_tiles_h * 1.2)
	if ore_row2 >= wall2_top and wall2_col + 1 < cols:
		_draw_tile(ox, oy, wall2_col + 1, ore_row2, tile_sz, COL_ORE)

	# -- Small cave pocket (underground, right side) --
	var cave_left: int = int(cols * 0.72)
	var cave_top: int = ground_row + 1
	var cave_w: int = mini(5, cols - cave_left)
	var cave_h: int = mini(3, rows - cave_top)

	# Hollow out the cave interior
	for c in range(cave_left, mini(cave_left + cave_w, cols)):
		for r in range(cave_top, mini(cave_top + cave_h, rows)):
			_draw_tile(ox, oy, c, r, tile_sz, COL_CAVE_BG)

	# Cave entrance on the left side
	if cave_top < rows and cave_left > 0:
		_draw_tile(ox, oy, cave_left - 1, cave_top, tile_sz, COL_CAVE_BG)
		if cave_top + 1 < mini(cave_top + cave_h, rows):
			_draw_tile(ox, oy, cave_left - 1, cave_top + 1, tile_sz, COL_CAVE_BG)

	# -- Player rectangle (standing on ground between doorway and thick wall) --
	var player_col: int = int((door_col + wall2_col) * 0.5)
	var player_x: float = ox + player_col * tile_sz + (tile_sz - PLAYER_W) * 0.5
	var player_y: float = oy + ground_row * tile_sz - PLAYER_H
	draw_rect(Rect2(player_x, player_y, PLAYER_W, PLAYER_H), COL_PLAYER)

	# Feet marker
	var feet_x := player_x + PLAYER_W * 0.5
	var feet_y := player_y + PLAYER_H
	draw_line(Vector2(feet_x - 5, feet_y), Vector2(feet_x + 5, feet_y), Color.WHITE, 1.0)

	# -- Second player silhouette near the cave for scale --
	var p2_col: int = maxi(cave_left - 2, 0)
	var p2_x: float = ox + p2_col * tile_sz + (tile_sz - PLAYER_W) * 0.5
	var p2_y: float = oy + ground_row * tile_sz - PLAYER_H
	if p2_x > ox and p2_x + PLAYER_W < ox + grid_w:
		draw_rect(Rect2(p2_x, p2_y, PLAYER_W, PLAYER_H), COL_PLAYER.lerp(Color.TRANSPARENT, 0.4))

	# --- Footer hint ---
	var hint_text := "< >  to change tile size          Escape to quit"
	draw_string(font, Vector2(VP_W * 0.5 - 180, VP_H - 8), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_small, COL_HINT)


func _draw_tile(ox: float, oy: float, col: int, row: int, tile_sz: int, color: Color) -> void:
	draw_rect(Rect2(ox + col * tile_sz, oy + row * tile_sz, tile_sz, tile_sz), color)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_RIGHT:
				current_index = (current_index + 1) % CONFIGS.size()
				queue_redraw()
			KEY_LEFT:
				current_index = (current_index - 1 + CONFIGS.size()) % CONFIGS.size()
				queue_redraw()
