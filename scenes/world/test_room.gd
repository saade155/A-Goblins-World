## Test room builder — a temporary hardcoded room for testing movement.
##
## This generates a box of tiles (floor, walls, ceiling) with a few interior
## platforms at different heights. It uses a TileMapLayer with a programmatic
## TileSet containing one solid collision tile.
##
## This entire scene is temporary — it will be replaced by the chunk-based
## world generation system in Milestone 3.

extends TileMapLayer

## Room dimensions in tiles.
const ROOM_WIDTH: int = 40
const ROOM_HEIGHT: int = 25

## Wall thickness in tiles.
const WALL_THICKNESS: int = 2

## Tile size in pixels (must match the TileSet).
const TILE_SIZE: int = 16


func _ready() -> void:
	_build_tileset()
	_build_room()


## Create a simple TileSet with one solid-colored tile that has collision.
func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add a physics layer for collision.
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)  # Layer 1 = World
	ts.set_physics_layer_collision_mask(0, 0)

	# Create a TileSetAtlasSource from our stone tile image.
	var atlas := TileSetAtlasSource.new()
	var texture := load("res://assets/tilesets/stone_tile.png") as Texture2D
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Create one tile at atlas coords (0, 0).
	atlas.create_tile(Vector2i(0, 0))

	# Add the atlas source to the tileset BEFORE setting collision polygons.
	# The atlas must belong to a TileSet with physics layers configured so that
	# TileData.add_collision_polygon() can reference the correct layer index.
	var _source_id := ts.add_source(atlas, 0)

	# Now that the atlas is part of the tileset, set up the collision polygon.
	var tile_data := atlas.get_tile_data(Vector2i(0, 0), 0)
	var collision_polygon := PackedVector2Array([
		Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0),
		Vector2( TILE_SIZE / 2.0, -TILE_SIZE / 2.0),
		Vector2( TILE_SIZE / 2.0,  TILE_SIZE / 2.0),
		Vector2(-TILE_SIZE / 2.0,  TILE_SIZE / 2.0),
	])
	tile_data.add_collision_polygon(0)
	tile_data.set_collision_polygon_points(0, 0, collision_polygon)

	# Assign the tileset to this TileMapLayer.
	tile_set = ts


## Build the room geometry: walls, floor, ceiling, and interior platforms.
func _build_room() -> void:
	# Fill border walls.
	for x in range(ROOM_WIDTH):
		for y in range(ROOM_HEIGHT):
			var is_border := (
				x < WALL_THICKNESS
				or x >= ROOM_WIDTH - WALL_THICKNESS
				or y < WALL_THICKNESS
				or y >= ROOM_HEIGHT - WALL_THICKNESS
			)
			if is_border:
				set_cell(Vector2i(x, y), 0, Vector2i(0, 0))

	# Interior platforms for testing jumps at various heights.
	# Platform 1: low, left side — a short hop.
	_place_platform(6, ROOM_HEIGHT - 5, 8)

	# Platform 2: mid height, center — needs a decent jump.
	_place_platform(16, ROOM_HEIGHT - 9, 8)

	# Platform 3: high, right side — full jump needed.
	_place_platform(28, ROOM_HEIGHT - 13, 8)

	# Platform 4: small stepping stone between platforms.
	_place_platform(12, ROOM_HEIGHT - 7, 3)

	# Platform 5: low right platform.
	_place_platform(30, ROOM_HEIGHT - 5, 6)


## Place a horizontal platform of tiles.
func _place_platform(start_x: int, y: int, length: int) -> void:
	for x in range(start_x, start_x + length):
		if x >= WALL_THICKNESS and x < ROOM_WIDTH - WALL_THICKNESS:
			set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
