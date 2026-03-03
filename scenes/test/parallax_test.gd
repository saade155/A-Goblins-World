## Parallax Depth Test — standalone scene proving depth layering feel.
## Run with F6. No autoloads required.
##
## Controls:
##   A/D or Arrows — Move
##   Space — Jump
##   Left Click — Mine back wall tile
##   1/2/3 — Switch biome (Cave / Fungal / Volcanic)
##   Escape — Quit

extends Node2D

# --- Constants ---

const TILE_SIZE := 16
const GRID_W := 180
const GRID_H := 60
const WORLD_W := GRID_W * TILE_SIZE  # 2880
const WORLD_H := GRID_H * TILE_SIZE  # 960

const SPEED := 240.0
const JUMP_VELOCITY := -500.0
const GRAVITY := 1400.0
const MAX_FALL_SPEED := 800.0

const PLAYER_W := 28
const PLAYER_H := 44

# --- Biome palettes ---

var PALETTES := {
	"cave": {
		"far_top": Color(0.05, 0.05, 0.15),
		"far_bottom": Color(0.02, 0.02, 0.08),
		"far_accent": Color(0.1, 0.1, 0.2, 0.3),
		"mid_shape": Color(0.08, 0.08, 0.12),
		"mid_accent": Color(0.15, 0.12, 0.1, 0.4),
		"near_shape": Color(0.12, 0.1, 0.14),
		"near_accent": Color(0.15, 0.12, 0.1, 0.3),
		"back_wall": Color(0.18, 0.14, 0.12),
		"cave_wall": Color(0.35, 0.32, 0.3),
		"cave_ground": Color(0.3, 0.22, 0.15),
		"foreground": Color(0.04, 0.03, 0.03, 0.85),
	},
	"fungal": {
		"far_top": Color(0.02, 0.08, 0.12),
		"far_bottom": Color(0.04, 0.02, 0.1),
		"far_accent": Color(0.0, 0.6, 0.5, 0.2),
		"mid_shape": Color(0.05, 0.12, 0.1),
		"mid_accent": Color(0.1, 0.8, 0.6, 0.35),
		"near_shape": Color(0.08, 0.06, 0.15),
		"near_accent": Color(0.4, 0.1, 0.6, 0.3),
		"back_wall": Color(0.1, 0.15, 0.12),
		"cave_wall": Color(0.2, 0.3, 0.25),
		"cave_ground": Color(0.15, 0.22, 0.18),
		"foreground": Color(0.02, 0.05, 0.04, 0.85),
	},
	"volcanic": {
		"far_top": Color(0.12, 0.03, 0.02),
		"far_bottom": Color(0.06, 0.01, 0.01),
		"far_accent": Color(0.9, 0.4, 0.1, 0.25),
		"mid_shape": Color(0.15, 0.05, 0.02),
		"mid_accent": Color(1.0, 0.5, 0.1, 0.4),
		"near_shape": Color(0.12, 0.06, 0.03),
		"near_accent": Color(0.9, 0.3, 0.05, 0.3),
		"back_wall": Color(0.15, 0.08, 0.05),
		"cave_wall": Color(0.3, 0.18, 0.12),
		"cave_ground": Color(0.25, 0.12, 0.08),
		"foreground": Color(0.06, 0.02, 0.01, 0.85),
	}
}

var BIOME_NAMES := ["cave", "fungal", "volcanic"]

# --- State ---

var current_biome: String = "cave"
var cave_grid: Dictionary = {}   # Vector2i -> true (solid)
var back_wall_grid: Dictionary = {}  # Vector2i -> true (solid)

# Draw node references (assigned in _ready).
var _far_bg_draw: Node2D
var _mid_bg_draw: Node2D
var _near_bg_draw: Node2D
var _fg_draw: Node2D
var _back_wall_node: Node2D
var _cave_node: Node2D
var _player_sprite: Node2D
var _player: CharacterBody2D
var _biome_label: Label
var _draw_script: GDScript

# --- Palette helper ---

func _pal(key: String) -> Color:
	return PALETTES[current_biome][key]


# --- Lifecycle ---

func _ready() -> void:
	get_window().title = "Parallax Depth Test"

	_build_cave_grid()
	_build_back_wall_grid()
	_setup_draw_nodes()
	_create_collision_bodies()

	# Cache node refs.
	_player = $Player
	_biome_label = $UIOverlay/BiomeLabel

	# Reset camera smoothing to avoid slide from origin.
	var camera := _player.get_node("Camera2D") as Camera2D
	if camera:
		camera.reset_smoothing()


func _physics_process(delta: float) -> void:
	if not _player:
		return

	# Gravity.
	if not _player.is_on_floor():
		_player.velocity.y = minf(_player.velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	# Jump.
	if Input.is_action_just_pressed("jump") and _player.is_on_floor():
		_player.velocity.y = JUMP_VELOCITY

	# Horizontal movement.
	var dir := Input.get_axis("move_left", "move_right")
	_player.velocity.x = dir * SPEED

	_player.move_and_slide()

	# Flip player sprite.
	if dir != 0.0 and _player_sprite:
		_player_sprite.scale.x = -1.0 if dir < 0.0 else 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		# Check for mouse click (back wall mining).
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_mine_back_wall()
		return

	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_1:
			_switch_biome("cave")
		KEY_2:
			_switch_biome("fungal")
		KEY_3:
			_switch_biome("volcanic")


# --- Biome switching ---

func _switch_biome(biome_name: String) -> void:
	if current_biome == biome_name:
		return
	current_biome = biome_name
	if _biome_label:
		_biome_label.text = "Biome: %s" % biome_name.capitalize()
	# Redraw everything.
	for node in [_far_bg_draw, _mid_bg_draw, _near_bg_draw, _fg_draw, _back_wall_node, _cave_node]:
		if node:
			node.queue_redraw()


# --- Back wall mining ---

func _mine_back_wall() -> void:
	var mouse_pos := get_global_mouse_position()
	var gx := int(floor(mouse_pos.x / TILE_SIZE))
	var gy := int(floor(mouse_pos.y / TILE_SIZE))
	var cell := Vector2i(gx, gy)

	# Only mine back wall cells that exist AND are not covered by a cave tile.
	if back_wall_grid.has(cell) and not cave_grid.has(cell):
		back_wall_grid.erase(cell)
		if _back_wall_node:
			_back_wall_node.queue_redraw()


# --- Grid generation ---

func _build_cave_grid() -> void:
	cave_grid.clear()

	# Floor: rows 45-59, all columns.
	for x in range(GRID_W):
		for y in range(45, GRID_H):
			cave_grid[Vector2i(x, y)] = true

	# Ceiling: rows 0-4, all columns.
	for x in range(GRID_W):
		for y in range(0, 5):
			cave_grid[Vector2i(x, y)] = true

	# Left wall: columns 0-2.
	for x in range(0, 3):
		for y in range(GRID_H):
			cave_grid[Vector2i(x, y)] = true

	# Right wall: columns 177-179.
	for x in range(177, 180):
		for y in range(GRID_H):
			cave_grid[Vector2i(x, y)] = true


func _build_back_wall_grid() -> void:
	back_wall_grid.clear()

	# Sparse back wall: ~30-40% coverage using layered seeded noise.
	# Uses multiple "cluster center" passes to create organic patches rather than
	# uniform random, so tiles clump together naturally.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	# The open interior is rows 5-44, columns 3-176 (between walls/ceiling/floor).
	var min_x := 3
	var max_x := 177
	var min_y := 5
	var max_y := 45

	# Pass 1: Scatter cluster centers. Each center spawns a patch of back wall.
	var cluster_centers: Array[Vector2i] = []
	var num_clusters := 60
	for _i in range(num_clusters):
		var cx := rng.randi_range(min_x, max_x - 1)
		var cy := rng.randi_range(min_y, max_y - 1)
		cluster_centers.append(Vector2i(cx, cy))

	# Pass 2: For each cluster, fill a random-radius blob around its center.
	for center in cluster_centers:
		var radius := rng.randf_range(2.0, 6.0)
		var ri := int(ceil(radius))
		for dx in range(-ri, ri + 1):
			for dy in range(-ri, ri + 1):
				var gx := center.x + dx
				var gy := center.y + dy
				if gx < min_x or gx >= max_x or gy < min_y or gy >= max_y:
					continue
				# Elliptical distance with slight vertical stretch for natural look.
				var dist := sqrt(float(dx * dx) + float(dy * dy) * 0.8)
				if dist <= radius:
					# Add some per-cell randomness to break up edges.
					if dist <= radius * 0.6 or rng.randf() < 0.5:
						back_wall_grid[Vector2i(gx, gy)] = true

	# Pass 3: Sprinkle additional isolated tiles for texture (~5% extra).
	for x in range(min_x, max_x):
		for y in range(min_y, max_y):
			if not back_wall_grid.has(Vector2i(x, y)):
				if rng.randf() < 0.04:
					back_wall_grid[Vector2i(x, y)] = true

	# Always fill back wall behind solid cave tiles (walls/floor/ceiling)
	# so the back wall is continuous where it's hidden anyway.
	for cell in cave_grid:
		back_wall_grid[cell] = true


# --- Draw node setup ---

func _setup_draw_nodes() -> void:
	# Create a dynamic script that delegates _draw() to a Callable.
	_draw_script = GDScript.new()
	_draw_script.source_code = "extends Node2D\nvar draw_func: Callable\nfunc _draw():\n\tif draw_func.is_valid():\n\t\tdraw_func.call(self)\n"
	_draw_script.reload()

	# Parallax draw nodes.
	_far_bg_draw = $ParallaxBackground/FarBG/FarBGDraw
	_far_bg_draw.set_script(_draw_script)
	_far_bg_draw.draw_func = _draw_far_bg

	_mid_bg_draw = $ParallaxBackground/MidBG/MidBGDraw
	_mid_bg_draw.set_script(_draw_script)
	_mid_bg_draw.draw_func = _draw_mid_bg

	_near_bg_draw = $ParallaxBackground/NearBG/NearBGDraw
	_near_bg_draw.set_script(_draw_script)
	_near_bg_draw.draw_func = _draw_near_bg

	_fg_draw = $ParallaxBackground/Foreground/ForegroundDraw
	_fg_draw.set_script(_draw_script)
	_fg_draw.draw_func = _draw_foreground

	# Non-parallax draw nodes.
	_back_wall_node = $BackWallLayer
	_back_wall_node.set_script(_draw_script)
	_back_wall_node.draw_func = _draw_back_wall

	_cave_node = $CaveLayer
	_cave_node.set_script(_draw_script)
	_cave_node.draw_func = _draw_cave

	# Player sprite.
	_player_sprite = $Player/PlayerSprite
	_player_sprite.set_script(_draw_script)
	_player_sprite.draw_func = _draw_player


# --- Collision body creation ---

func _create_collision_bodies() -> void:
	# Floor: full width, rows 45-59 => y=720..960, height=240, center y=840.
	_add_static_body(Vector2(WORLD_W * 0.5, (45 * TILE_SIZE + WORLD_H) * 0.5),
		Vector2(WORLD_W, (GRID_H - 45) * TILE_SIZE))

	# Ceiling: rows 0-4 => y=0..80, height=80, center y=40.
	_add_static_body(Vector2(WORLD_W * 0.5, 5 * TILE_SIZE * 0.5),
		Vector2(WORLD_W, 5 * TILE_SIZE))

	# Left wall: columns 0-2 => x=0..48, full height.
	_add_static_body(Vector2(3 * TILE_SIZE * 0.5, WORLD_H * 0.5),
		Vector2(3 * TILE_SIZE, WORLD_H))

	# Right wall: columns 177-179 => x=2832..2880.
	_add_static_body(Vector2(177 * TILE_SIZE + 3 * TILE_SIZE * 0.5, WORLD_H * 0.5),
		Vector2(3 * TILE_SIZE, WORLD_H))


func _add_static_body(center: Vector2, extents: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = extents
	shape.shape = rect
	body.add_child(shape)
	$CaveLayer.add_child(body)


# --- Draw functions ---

func _draw_far_bg(node: Node2D) -> void:
	var pal_top := _pal("far_top")
	var pal_bottom := _pal("far_bottom")
	var pal_accent := _pal("far_accent")

	# Large gradient rect centered around the cave midpoint.
	# Draw area: 4000x3000, offset so it covers the camera range.
	var draw_x := -500.0
	var draw_y := -1000.0
	var draw_w := 4000.0
	var draw_h := 3000.0

	# Vertical gradient: split into horizontal bands.
	var bands := 30
	var band_h := draw_h / bands
	for i in range(bands):
		var t := float(i) / (bands - 1)
		var col := pal_top.lerp(pal_bottom, t)
		node.draw_rect(Rect2(draw_x, draw_y + i * band_h, draw_w, band_h + 1), col)

	# Glow circles.
	node.draw_circle(Vector2(600.0, 200.0), 180.0, pal_accent)
	node.draw_circle(Vector2(1800.0, 350.0), 140.0, pal_accent)
	node.draw_circle(Vector2(2400.0, 100.0), 200.0, pal_accent)


func _draw_mid_bg(node: Node2D) -> void:
	var shape_col := _pal("mid_shape")
	var accent_col := _pal("mid_accent")

	# Draw area ~5000x3000, centered.
	var ox := -800.0
	var oy := -800.0

	match current_biome:
		"cave":
			# Mountain-like silhouettes.
			node.draw_polygon(PackedVector2Array([
				Vector2(ox + 300, oy + 1200), Vector2(ox + 500, oy + 600),
				Vector2(ox + 700, oy + 1200)
			]), PackedColorArray([shape_col, shape_col, shape_col]))

			node.draw_polygon(PackedVector2Array([
				Vector2(ox + 1200, oy + 1200), Vector2(ox + 1500, oy + 500),
				Vector2(ox + 1800, oy + 1200)
			]), PackedColorArray([shape_col, shape_col, shape_col]))

			# Pyramid shape.
			node.draw_polygon(PackedVector2Array([
				Vector2(ox + 2500, oy + 1200), Vector2(ox + 2700, oy + 400),
				Vector2(ox + 2900, oy + 1200)
			]), PackedColorArray([shape_col, shape_col, shape_col]))

			# Faint glow.
			node.draw_circle(Vector2(ox + 1500, oy + 800), 120.0, accent_col)

		"fungal":
			# Mushroom silhouettes — cap (circle) + stalk (rect).
			# Mushroom 1.
			node.draw_circle(Vector2(ox + 600, oy + 700), 100.0, shape_col)
			node.draw_rect(Rect2(ox + 575, oy + 700, 50, 300), shape_col)

			# Mushroom 2 (larger).
			node.draw_circle(Vector2(ox + 1800, oy + 600), 150.0, shape_col)
			node.draw_rect(Rect2(ox + 1765, oy + 600, 70, 400), shape_col)

			# Mushroom 3.
			node.draw_circle(Vector2(ox + 3000, oy + 750), 90.0, shape_col)
			node.draw_rect(Rect2(ox + 2975, oy + 750, 50, 250), shape_col)

			# Bioluminescent glow circles.
			node.draw_circle(Vector2(ox + 600, oy + 650), 160.0, accent_col)
			node.draw_circle(Vector2(ox + 1800, oy + 550), 200.0, accent_col)
			node.draw_circle(Vector2(ox + 3000, oy + 700), 130.0, accent_col)

		"volcanic":
			# Dark mountain ridges.
			node.draw_polygon(PackedVector2Array([
				Vector2(ox + 100, oy + 1200), Vector2(ox + 400, oy + 300),
				Vector2(ox + 600, oy + 700), Vector2(ox + 900, oy + 200),
				Vector2(ox + 1200, oy + 1200)
			]), PackedColorArray([shape_col, shape_col, shape_col, shape_col, shape_col]))

			node.draw_polygon(PackedVector2Array([
				Vector2(ox + 1800, oy + 1200), Vector2(ox + 2200, oy + 350),
				Vector2(ox + 2400, oy + 600), Vector2(ox + 2700, oy + 250),
				Vector2(ox + 3000, oy + 1200)
			]), PackedColorArray([shape_col, shape_col, shape_col, shape_col, shape_col]))

			# Lava glow circles.
			node.draw_circle(Vector2(ox + 900, oy + 500), 150.0, accent_col)
			node.draw_circle(Vector2(ox + 2400, oy + 600), 180.0, accent_col)


func _draw_near_bg(node: Node2D) -> void:
	var shape_col := _pal("near_shape")
	var accent_col := _pal("near_accent")

	var ox := -600.0
	var oy := -600.0

	# Rock column silhouettes (tall thin polygons).
	node.draw_polygon(PackedVector2Array([
		Vector2(ox + 200, oy + 1400), Vector2(ox + 220, oy + 300),
		Vector2(ox + 260, oy + 280), Vector2(ox + 280, oy + 1400)
	]), PackedColorArray([shape_col, shape_col, shape_col, shape_col]))

	node.draw_polygon(PackedVector2Array([
		Vector2(ox + 1100, oy + 1400), Vector2(ox + 1125, oy + 200),
		Vector2(ox + 1175, oy + 180), Vector2(ox + 1200, oy + 1400)
	]), PackedColorArray([shape_col, shape_col, shape_col, shape_col]))

	node.draw_polygon(PackedVector2Array([
		Vector2(ox + 2300, oy + 1400), Vector2(ox + 2330, oy + 350),
		Vector2(ox + 2380, oy + 330), Vector2(ox + 2410, oy + 1400)
	]), PackedColorArray([shape_col, shape_col, shape_col, shape_col]))

	# Crystal-like angular shapes.
	node.draw_polygon(PackedVector2Array([
		Vector2(ox + 700, oy + 900), Vector2(ox + 730, oy + 600),
		Vector2(ox + 780, oy + 550), Vector2(ox + 820, oy + 620),
		Vector2(ox + 800, oy + 900)
	]), PackedColorArray([accent_col, accent_col, accent_col, accent_col, accent_col]))

	node.draw_polygon(PackedVector2Array([
		Vector2(ox + 1700, oy + 1000), Vector2(ox + 1740, oy + 700),
		Vector2(ox + 1800, oy + 650), Vector2(ox + 1850, oy + 720),
		Vector2(ox + 1830, oy + 1000)
	]), PackedColorArray([accent_col, accent_col, accent_col, accent_col, accent_col]))

	# Doorway / arch shape suggesting ruins.
	var arch_x := ox + 3000.0
	var arch_y := oy + 500.0
	node.draw_rect(Rect2(arch_x, arch_y, 40, 500), shape_col)
	node.draw_rect(Rect2(arch_x + 160, arch_y, 40, 500), shape_col)
	node.draw_rect(Rect2(arch_x, arch_y, 200, 40), shape_col)


func _draw_foreground(node: Node2D) -> void:
	var fg_col := _pal("foreground")

	var ox := -200.0
	var oy := -400.0

	# Stalactite triangles hanging from top.
	var stalactites := [
		Vector2(ox + 200, oy + 0), Vector2(ox + 215, oy + 180), Vector2(ox + 230, oy + 0),
	]
	node.draw_polygon(PackedVector2Array(stalactites), PackedColorArray([fg_col, fg_col, fg_col]))

	stalactites = [
		Vector2(ox + 800, oy + 0), Vector2(ox + 820, oy + 250), Vector2(ox + 840, oy + 0),
	]
	node.draw_polygon(PackedVector2Array(stalactites), PackedColorArray([fg_col, fg_col, fg_col]))

	stalactites = [
		Vector2(ox + 1400, oy + 0), Vector2(ox + 1418, oy + 200), Vector2(ox + 1436, oy + 0),
	]
	node.draw_polygon(PackedVector2Array(stalactites), PackedColorArray([fg_col, fg_col, fg_col]))

	stalactites = [
		Vector2(ox + 2100, oy + 0), Vector2(ox + 2112, oy + 160), Vector2(ox + 2124, oy + 0),
	]
	node.draw_polygon(PackedVector2Array(stalactites), PackedColorArray([fg_col, fg_col, fg_col]))

	stalactites = [
		Vector2(ox + 2700, oy + 0), Vector2(ox + 2722, oy + 220), Vector2(ox + 2744, oy + 0),
	]
	node.draw_polygon(PackedVector2Array(stalactites), PackedColorArray([fg_col, fg_col, fg_col]))

	# Thin vine-like lines from top.
	var vine_col := Color(fg_col.r, fg_col.g, fg_col.b, fg_col.a * 0.7)
	node.draw_line(Vector2(ox + 500, oy + 0), Vector2(ox + 510, oy + 300), vine_col, 2.0)
	node.draw_line(Vector2(ox + 1700, oy + 0), Vector2(ox + 1690, oy + 250), vine_col, 2.0)
	node.draw_line(Vector2(ox + 2400, oy + 0), Vector2(ox + 2410, oy + 280), vine_col, 2.0)


func _draw_back_wall(node: Node2D) -> void:
	var wall_col := _pal("back_wall")
	for cell in back_wall_grid:
		# Skip cells that are also in the cave grid (they're drawn by cave layer).
		if cave_grid.has(cell):
			continue
		node.draw_rect(Rect2(cell.x * TILE_SIZE, cell.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), wall_col)


func _draw_cave(node: Node2D) -> void:
	var wall_col := _pal("cave_wall")
	var ground_col := _pal("cave_ground")
	for cell in cave_grid:
		var col := ground_col if cell.y >= 45 else wall_col
		node.draw_rect(Rect2(cell.x * TILE_SIZE, cell.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), col)


func _draw_player(node: Node2D) -> void:
	# Green rectangle centered at the node's origin (player center).
	var half_w := PLAYER_W * 0.5
	var half_h := PLAYER_H * 0.5
	node.draw_rect(Rect2(-half_w, -half_h, PLAYER_W, PLAYER_H), Color(0.2, 0.75, 0.3))
	# Eyes.
	node.draw_rect(Rect2(-6, -12, 4, 4), Color.WHITE)
	node.draw_rect(Rect2(2, -12, 4, 4), Color.WHITE)
	node.draw_rect(Rect2(-5, -11, 2, 2), Color.BLACK)
	node.draw_rect(Rect2(3, -11, 2, 2), Color.BLACK)
