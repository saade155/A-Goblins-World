## Test room builder -- a temporary hardcoded room for testing mining and movement.
##
## This generates a box of tiles using WorldData as the authoritative source,
## then syncs the visual TileMapLayer to match. It uses multiple tile types:
## stone for walls, dirt for interior fill, iron ore patches scattered within.
##
## Listens to GameServer signals to update visuals when tiles are mined/placed,
## and spawns dropped items on mine.
##
## This entire scene is temporary -- it will be replaced by the chunk-based
## world generation system in Milestone 3.

extends TileMapLayer

## Room dimensions in tiles.
const ROOM_WIDTH: int = 40
const ROOM_HEIGHT: int = 25

## Wall thickness in tiles.
const WALL_THICKNESS: int = 2

## Tile size in pixels (must match the TileSet).
const TILE_SIZE: int = 16

## Preloaded dropped item scene for spawning.
var _dropped_item_scene: PackedScene = preload("res://scenes/items/dropped_item.tscn")

## The authoritative world data for this room.
var _world_data: WorldData = null


func _ready() -> void:
	_build_tileset()
	_build_world_data()
	_sync_all_tiles()
	_register_with_server()
	_connect_signals()
	_setup_mining_component()


## Create a TileSet with 3 tile types from the tile atlas (dirt, stone, iron ore).
## Each tile has full-square collision on physics layer 0 (World).
func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add a physics layer for collision.
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)  # Layer 1 = World
	ts.set_physics_layer_collision_mask(0, 0)

	# Create a TileSetAtlasSource from the tile atlas image (48x16, 3 tiles in a row).
	var atlas := TileSetAtlasSource.new()
	var texture := load("res://assets/tilesets/tile_atlas.png") as Texture2D
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Create 3 tiles: (0,0)=dirt, (1,0)=stone, (2,0)=iron_ore.
	atlas.create_tile(Vector2i(0, 0))
	atlas.create_tile(Vector2i(1, 0))
	atlas.create_tile(Vector2i(2, 0))

	# Add the atlas source to the tileset BEFORE setting collision polygons.
	var _source_id := ts.add_source(atlas, 0)

	# Full-square collision polygon shared by all tiles.
	var collision_polygon := PackedVector2Array([
		Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0),
		Vector2( TILE_SIZE / 2.0, -TILE_SIZE / 2.0),
		Vector2( TILE_SIZE / 2.0,  TILE_SIZE / 2.0),
		Vector2(-TILE_SIZE / 2.0,  TILE_SIZE / 2.0),
	])

	# Set collision on each tile.
	for tile_coords in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		var tile_data := atlas.get_tile_data(tile_coords, 0)
		tile_data.add_collision_polygon(0)
		tile_data.set_collision_polygon_points(0, 0, collision_polygon)

	# Assign the tileset to this TileMapLayer.
	tile_set = ts


## Build the room layout in WorldData (the authoritative data layer).
## Layout: stone outer walls, dirt fill, stone platforms, iron ore patches.
func _build_world_data() -> void:
	_world_data = WorldData.new()

	# --- Outer walls (stone, 2 tiles thick) ---
	for x in range(ROOM_WIDTH):
		for y in range(ROOM_HEIGHT):
			var is_border := (
				x < WALL_THICKNESS
				or x >= ROOM_WIDTH - WALL_THICKNESS
				or y < WALL_THICKNESS
				or y >= ROOM_HEIGHT - WALL_THICKNESS
			)
			if is_border:
				_world_data.set_tile(Vector2i(x, y), TileDatabase.TileType.STONE)

	# --- Interior dirt fill ---
	# Fill the lower portion of the room with dirt (below y = 14),
	# leaving the upper portion as air for the player to move around.
	for x in range(WALL_THICKNESS, ROOM_WIDTH - WALL_THICKNESS):
		for y in range(14, ROOM_HEIGHT - WALL_THICKNESS):
			_world_data.set_tile(Vector2i(x, y), TileDatabase.TileType.DIRT)

	# --- Iron ore patches ---
	# Scatter some iron ore veins in the dirt area.
	var ore_positions: Array[Vector2i] = [
		# Vein 1: left side cluster
		Vector2i(5, 16), Vector2i(6, 16), Vector2i(5, 17), Vector2i(6, 17),
		# Vein 2: center
		Vector2i(18, 18), Vector2i(19, 18), Vector2i(18, 19), Vector2i(19, 19), Vector2i(20, 18),
		# Vein 3: right side
		Vector2i(32, 15), Vector2i(33, 15), Vector2i(33, 16), Vector2i(34, 16),
		# Vein 4: deep
		Vector2i(12, 20), Vector2i(13, 20), Vector2i(13, 21),
	]
	for pos in ore_positions:
		if pos.x >= WALL_THICKNESS and pos.x < ROOM_WIDTH - WALL_THICKNESS:
			if pos.y >= WALL_THICKNESS and pos.y < ROOM_HEIGHT - WALL_THICKNESS:
				_world_data.set_tile(pos, TileDatabase.TileType.IRON_ORE)

	# --- Platforms (stone) ---
	# Platform 1: low, left side -- a short hop.
	_place_platform_data(6, ROOM_HEIGHT - 5, 8, TileDatabase.TileType.STONE)
	# Platform 2: mid height, center -- needs a decent jump.
	_place_platform_data(16, ROOM_HEIGHT - 9, 8, TileDatabase.TileType.STONE)
	# Platform 3: high, right side -- full jump needed.
	_place_platform_data(28, ROOM_HEIGHT - 13, 8, TileDatabase.TileType.STONE)
	# Platform 4: small stepping stone between platforms.
	_place_platform_data(12, ROOM_HEIGHT - 7, 3, TileDatabase.TileType.STONE)
	# Platform 5: low right platform.
	_place_platform_data(30, ROOM_HEIGHT - 5, 6, TileDatabase.TileType.STONE)

	print("[TestRoom] World data built with %d tiles." % _world_data.tiles.size())


## Place a horizontal platform in world data.
func _place_platform_data(start_x: int, y: int, length: int, tile_type: int) -> void:
	for x in range(start_x, start_x + length):
		if x >= WALL_THICKNESS and x < ROOM_WIDTH - WALL_THICKNESS:
			if y >= WALL_THICKNESS and y < ROOM_HEIGHT - WALL_THICKNESS:
				_world_data.set_tile(Vector2i(x, y), tile_type)


## Sync every tile in WorldData to the TileMapLayer visual.
func _sync_all_tiles() -> void:
	# First clear any existing tiles.
	clear()

	# Set every tile from world data.
	for pos in _world_data.tiles:
		_sync_tile(pos)


## Sync a single tile position: update the TileMapLayer cell to match WorldData.
func _sync_tile(world_pos: Vector2i) -> void:
	var tile_type: int = _world_data.get_tile(world_pos)
	if tile_type == TileDatabase.TileType.EMPTY:
		erase_cell(world_pos)
	else:
		var atlas_coords: Vector2i = TileDatabase.get_atlas_coords(tile_type)
		set_cell(world_pos, 0, atlas_coords)


## Register WorldData with GameServer so it becomes the authority.
func _register_with_server() -> void:
	GameServer.initialize_world(_world_data)


## Connect to GameServer signals to react to tile changes.
func _connect_signals() -> void:
	GameServer.tile_mined.connect(_on_tile_mined)
	GameServer.tile_placed.connect(_on_tile_placed)


## Find the player's MiningComponent and give it a reference to this TileMapLayer.
func _setup_mining_component() -> void:
	# Defer so the player is ready.
	call_deferred("_deferred_setup_mining")


func _deferred_setup_mining() -> void:
	if GameState.player:
		var mining_comp := GameState.player.get_node_or_null("MiningComponent")
		if mining_comp:
			mining_comp.tile_map_layer = self
			print("[TestRoom] MiningComponent linked to TileMapLayer.")
		else:
			print("[TestRoom] WARNING: Player has no MiningComponent.")
	else:
		print("[TestRoom] WARNING: No player registered in GameState.")


## Called when a tile is mined via GameServer. Update visuals and spawn a drop.
func _on_tile_mined(position: Vector2i, tile_type: int, _tool_used: String) -> void:
	# Update the visual TileMapLayer.
	_sync_tile(position)

	# Spawn a dropped item at the tile's world position.
	var drop_info: Dictionary = TileDatabase.get_drop(tile_type)
	if drop_info["item"] != "":
		_spawn_dropped_item(drop_info["item"], drop_info["count"], position)


## Called when a tile is placed via GameServer. Update visuals.
func _on_tile_placed(position: Vector2i, _tile_type: int) -> void:
	_sync_tile(position)


## Spawn a dropped item entity at a tile position.
func _spawn_dropped_item(item_type: String, amount: int, tile_pos: Vector2i) -> void:
	var item_instance := _dropped_item_scene.instantiate() as CharacterBody2D
	# Calculate the world-space center of the tile.
	var spawn_pos := Vector2(
		tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)
	item_instance.initialize(item_type, amount, spawn_pos)
	# Add the item to the scene tree (parent it to the same parent as this TileMapLayer).
	get_parent().add_child(item_instance)
