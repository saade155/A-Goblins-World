## ChunkManager - Core orchestrator for chunk-based procedural world.
##
## Manages loading/unloading of terrain chunks around the player. Each chunk
## is a TileMapLayer with its own collision. The manager:
##   1. Tracks which chunk the player is in
##   2. Loads/generates chunks within LOAD_RADIUS
##   3. Unloads chunks outside that radius
##   4. Handles tile visual updates when GameServer emits mine/place signals
##   5. Spawns dropped items
##   6. Applies depth-based ambient lighting
##
## Generation is synchronous but limited to 2 chunks per frame to avoid hitches.

extends Node2D
class_name ChunkManager

## Chunk size in tiles (must match WorldData.CHUNK_SIZE).
const CHUNK_SIZE: int = 32

## Tile size in pixels.
const TILE_SIZE: int = 32

## How many chunks to load in each direction from the player's chunk.
## Total loaded area = (2 * LOAD_RADIUS + 1)^2 chunks.
const LOAD_RADIUS: int = 3

## Pixel size of a full chunk (CHUNK_SIZE * TILE_SIZE).
const PIXEL_CHUNK_SIZE: int = CHUNK_SIZE * TILE_SIZE  # 1024

## Torch light radius in tiles.
const TORCH_RADIUS: int = 8

## Maximum light level a torch emits at its center.
const TORCH_LIGHT_LEVEL: float = 1.0

## Falloff exponent for torch light attenuation.
const TORCH_FALLOFF_POWER: float = 1.4

## Minimum ambient light level deep underground.
const AMBIENT_FLOOR: float = 0.03

## Z-index for the base tile layer.
const BASE_Z_INDEX: int = 0
## Z-index for floor (top) edge overlays.
const EDGE_FLOOR_Z_INDEX: int = 1
## Z-index for left wall edge overlays.
const EDGE_WALL_L_Z_INDEX: int = 2
## Z-index for right wall edge overlays.
const EDGE_WALL_R_Z_INDEX: int = 3
## Z-index for ceiling (bottom) edge overlays.
const EDGE_CEILING_Z_INDEX: int = 4
## Z-index for SE inner corner overlay (separate from edges to avoid conflicts).
const CORNER_SE_Z_INDEX: int = 5
## Z-index for SW inner corner overlay.
const CORNER_SW_Z_INDEX: int = 6
## Z-index for NE inner corner overlay.
const CORNER_NE_Z_INDEX: int = 7
## Z-index for NW inner corner overlay.
const CORNER_NW_Z_INDEX: int = 8
## Z-index for the player character.
const PLAYER_Z_INDEX: int = 9
## Z-index for darkness overlay sprites (above terrain).
const DARKNESS_Z_INDEX: int = 11

## Z-index for torch sprites (above darkness overlay).
const TORCH_SPRITE_Z_INDEX: int = -1

## The authoritative world data.
var world_data: WorldData

## Procedural terrain generator.
var world_generator: WorldGenerator

## Structure placement system.
var structure_placer: StructurePlacer

## Active (loaded) chunks: chunk_coord (Vector2i) -> Dictionary of layer nodes.
## Each value is {"base": TileMapLayer, ...} (edge layers added later).
var active_chunks: Dictionary = {}

## The shared TileSet used by all chunk TileMapLayers.
var shared_tileset: TileSet

## Edge overlay atlas source IDs per tile type (no collision). TileType -> source_id.
var edge_source_ids: Dictionary = {}

## Player's current chunk coordinate. Initialized to an impossible value
## so the first _process always triggers a load.
var current_player_chunk: Vector2i = Vector2i(999999, 999999)

## Queue of chunks waiting to be generated and loaded.
var chunks_to_generate: Array[Vector2i] = []

## Structure tiles that override generated terrain.
## World position (Vector2i) -> tile type (int). Includes EMPTY for carved areas.
var structure_tiles: Dictionary = {}

## Set of chunks that have been generated (to avoid re-generating).
var generated_chunks: Dictionary = {}  # Vector2i -> bool

## Preloaded dropped item scene.
var _dropped_item_scene: PackedScene

## Darkness overlay sprites per chunk. Key = chunk_coord, value = Sprite2D.
var chunk_darkness_sprites: Dictionary = {}

## Save manager for chunk and world persistence.
var save_manager: SaveManager

## Preloaded torch scene.
var _torch_scene: PackedScene

## Active torch visual nodes. Key = world tile position, value = Node2D instance.
var active_torches: Dictionary = {}

## Full-tile collision polygon for tileset tiles.
var collision_polygon: PackedVector2Array

## Whether this is the first frame (force-load all chunks synchronously).
var _first_load: bool = true

## Skip edge overlay population during first-load (handled in bulk after all chunks are created).
var _skip_edge_overlays: bool = false

## Emitted when a chunk is loaded into the scene.
signal chunk_loaded(chunk_coord: Vector2i)

## Emitted when a chunk is unloaded from the scene.
signal chunk_unloaded(chunk_coord: Vector2i)

## Emitted once after the first synchronous load completes (all initial chunks ready).
signal initial_load_complete


func _ready() -> void:
	save_manager = SaveManager.new()

	# Use the slot name from GameState (set by title screen menus), fall back to "default"
	if GameState.world_slot_name != "":
		save_manager.world_name = GameState.world_slot_name
	else:
		save_manager.world_name = "default"

	# Try to load existing world save
	var meta = save_manager.load_world_meta()
	if meta != null:
		GameState.world_seed = meta["world_seed"]
		GameState.start_depth = meta["start_depth"]
		GameState.saved_player_position = Vector2(meta["player_position_x"], meta["player_position_y"])
		GameState.world_display_name = meta.get("display_name", save_manager.world_name)
		GameState.playtime_seconds = meta.get("playtime_seconds", 0.0)
		print("[ChunkManager] Loaded world save. Seed: %d" % GameState.world_seed)

	# Initialize systems
	world_data = WorldData.new()
	world_generator = WorldGenerator.new(GameState.world_seed)
	structure_placer = StructurePlacer.new()

	# Build the shared tileset (programmatic atlas with all tile types)
	shared_tileset = _build_tileset()

	# Detect which tile types have edge overlay art (scans textures)
	_detect_edge_capable_types()

	# Initialize variant noise for deterministic tile variation
	TileDatabase.initialize_variant_noise(GameState.world_seed)

	# Register world data and generator with GameServer and GameState
	GameServer.initialize_world(world_data)
	GameState.world_data = world_data
	GameState.world_generator = world_generator

	# Place the spawn chamber as structure tiles
	_place_spawn_chamber()

	# Connect to GameServer signals for visual updates
	GameServer.tile_mined.connect(_on_tile_mined)
	GameServer.tile_placed.connect(_on_tile_placed)

	# Preload dropped item scene
	_dropped_item_scene = preload("res://scenes/items/dropped_item.tscn")

	print("[ChunkManager] Ready. World seed: %d" % GameState.world_seed)

	# Load torch scene
	_torch_scene = preload("res://scenes/world/torch.tscn")

	# Connect torch signals
	GameServer.torch_placed.connect(_on_torch_placed)
	GameServer.torch_removed.connect(_on_torch_removed)

	# Load BehaviorTracker data if save exists
	save_manager.load_behavior_data(BehaviorTracker)

	# Intercept window close to save before quitting
	get_tree().set_auto_accept_quit(false)


func _process(_delta: float) -> void:
	if not GameState.player:
		return

	var player_pos: Vector2 = GameState.player.global_position
	var player_chunk := Vector2i(
		floori(player_pos.x / PIXEL_CHUNK_SIZE),
		floori(player_pos.y / PIXEL_CHUNK_SIZE)
	)

	if player_chunk != current_player_chunk:
		current_player_chunk = player_chunk
		_update_loaded_chunks()

	# Process generation queue
	if _first_load:
		_skip_edge_overlays = true
		# Force-load all chunks synchronously on first frame (no pop-in on game load)
		# Phase 1: Generate all chunk data first (so neighbors exist for bitmasks)
		for chunk_coord in chunks_to_generate:
			if _is_chunk_needed(chunk_coord):
				_generate_chunk_data(chunk_coord)
		# Phase 2: Create base visuals (bitmasks can now see all neighbor data)
		while chunks_to_generate.size() > 0:
			var chunk_coord: Vector2i = chunks_to_generate.pop_front()
			if _is_chunk_needed(chunk_coord):
				_create_chunk_visuals(chunk_coord)
		# Phase 3: Populate edge overlays (all chunks now have base data)
		_skip_edge_overlays = false
		for chunk_coord in active_chunks:
			_populate_chunk_edge_overlays(chunk_coord)
		for chunk_coord in active_chunks:
			_update_neighbor_edge_overlays(chunk_coord)
		_first_load = false
		initial_load_complete.emit()
	else:
		# Normal: generate up to 2 chunks per frame
		_process_generation_queue()

	# Track max depth for BehaviorTracker
	_update_depth_tracking()

	# Debug hover panel update
	_debug_process(_delta)


# --- Chunk loading / unloading ---

## Determine which chunks should be loaded/unloaded based on player position.
func _update_loaded_chunks() -> void:
	var needed_chunks: Dictionary = {}  # Used as a set

	# Determine which chunks should be loaded
	for x in range(current_player_chunk.x - LOAD_RADIUS, current_player_chunk.x + LOAD_RADIUS + 1):
		for y in range(current_player_chunk.y - LOAD_RADIUS, current_player_chunk.y + LOAD_RADIUS + 1):
			needed_chunks[Vector2i(x, y)] = true

	# Unload chunks no longer needed
	var to_unload: Array[Vector2i] = []
	for chunk_coord in active_chunks:
		if not needed_chunks.has(chunk_coord):
			to_unload.append(chunk_coord)

	for chunk_coord in to_unload:
		_unload_chunk(chunk_coord)

	# Queue chunks that need loading
	for chunk_coord in needed_chunks:
		if not active_chunks.has(chunk_coord):
			if not chunks_to_generate.has(chunk_coord):
				chunks_to_generate.append(chunk_coord)

	# Sort by distance to player (closest first)
	chunks_to_generate.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(current_player_chunk) < b.distance_squared_to(current_player_chunk)
	)


## Process the generation queue. Generates up to 2 chunks per frame.
func _process_generation_queue() -> void:
	var count: int = 0
	while chunks_to_generate.size() > 0 and count < 2:
		var chunk_coord: Vector2i = chunks_to_generate.pop_front()
		# Check it's still needed (player may have moved)
		if _is_chunk_needed(chunk_coord):
			_load_chunk(chunk_coord)
			count += 1


## Check if a chunk is within the load radius of the current player chunk.
func _is_chunk_needed(chunk_coord: Vector2i) -> bool:
	var diff: Vector2i = (chunk_coord - current_player_chunk).abs()
	return diff.x <= LOAD_RADIUS and diff.y <= LOAD_RADIUS


## Generate chunk data (load from save or generate from seed) without creating visuals.
## Safe to call multiple times; skips if data already exists.
func _generate_chunk_data(chunk_coord: Vector2i) -> void:
	if generated_chunks.has(chunk_coord):
		return

	# Check for saved chunk first (player-modified chunks saved to disk)
	var saved_data = save_manager.load_chunk(chunk_coord)
	if saved_data != null:
		world_data.set_chunk_tiles(chunk_coord, saved_data["tiles"])
		# Restore torches
		for tpos in saved_data["torches"]:
			world_data.torches[tpos] = true
		world_data.dirty_chunks[chunk_coord] = true
	else:
		# Generate fresh from seed
		var chunk_tiles: Dictionary = world_generator.generate_chunk(chunk_coord)
		world_data.set_chunk_tiles(chunk_coord, chunk_tiles)
		_apply_structure_tiles_to_chunk(chunk_coord)
	generated_chunks[chunk_coord] = true


## Create the visual TileMapLayer for a chunk whose data already exists.
## Builds bitmask visuals, spawns torches, and creates the darkness overlay.
func _create_chunk_visuals(chunk_coord: Vector2i) -> void:
	if active_chunks.has(chunk_coord):
		return

	var origin: Vector2i = WorldData.chunk_to_world(chunk_coord)

	# Create TileMapLayer for this chunk
	var tilemap := TileMapLayer.new()
	tilemap.name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	tilemap.tile_set = shared_tileset
	tilemap.position = Vector2(chunk_coord.x * PIXEL_CHUNK_SIZE, chunk_coord.y * PIXEL_CHUNK_SIZE)
	tilemap.collision_enabled = true

	# Populate the tilemap from world data
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var wpos: Vector2i = origin + Vector2i(x, y)
			var tile_type: int = world_data.get_tile(wpos)
			if tile_type != TileDatabase.TileType.EMPTY:
				var visual: Dictionary = _get_tile_visual(wpos, tile_type)
				tilemap.set_cell(Vector2i(x, y), visual["source_id"], visual["atlas_coords"])

	add_child(tilemap)
	active_chunks[chunk_coord] = {"base": tilemap}

	# Create edge overlay TileMapLayers (no collision)
	var edge_layer_names: Array = ["edge_floor", "edge_wall_l", "edge_wall_r", "edge_ceiling"]
	var edge_z_values: Array = [EDGE_FLOOR_Z_INDEX, EDGE_WALL_L_Z_INDEX, EDGE_WALL_R_Z_INDEX, EDGE_CEILING_Z_INDEX]

	for i in range(edge_layer_names.size()):
		var edge_layer := TileMapLayer.new()
		edge_layer.name = "Chunk_%d_%d_%s" % [chunk_coord.x, chunk_coord.y, edge_layer_names[i]]
		edge_layer.tile_set = shared_tileset
		edge_layer.position = Vector2(chunk_coord.x * PIXEL_CHUNK_SIZE, chunk_coord.y * PIXEL_CHUNK_SIZE)
		edge_layer.collision_enabled = false
		edge_layer.z_index = edge_z_values[i]
		add_child(edge_layer)
		active_chunks[chunk_coord][edge_layer_names[i]] = edge_layer

	# Create inner corner overlay TileMapLayers (no collision, dedicated to avoid edge conflicts)
	var corner_layer_names: Array = ["corner_se", "corner_sw", "corner_ne", "corner_nw"]
	var corner_z_values: Array = [CORNER_SE_Z_INDEX, CORNER_SW_Z_INDEX, CORNER_NE_Z_INDEX, CORNER_NW_Z_INDEX]

	for i in range(corner_layer_names.size()):
		var corner_layer := TileMapLayer.new()
		corner_layer.name = "Chunk_%d_%d_%s" % [chunk_coord.x, chunk_coord.y, corner_layer_names[i]]
		corner_layer.tile_set = shared_tileset
		corner_layer.position = Vector2(chunk_coord.x * PIXEL_CHUNK_SIZE, chunk_coord.y * PIXEL_CHUNK_SIZE)
		corner_layer.collision_enabled = false
		corner_layer.z_index = corner_z_values[i]
		add_child(corner_layer)
		active_chunks[chunk_coord][corner_layer_names[i]] = corner_layer

	chunk_loaded.emit(chunk_coord)

	# Spawn torches for this chunk
	var torch_positions: Array = world_data.get_chunk_torches(chunk_coord)
	for tpos in torch_positions:
		_spawn_torch(tpos)

	# Create per-tile darkness overlay for this chunk
	_create_darkness_overlay(chunk_coord)

	# Populate edge overlays (skipped during first-load; handled in bulk there)
	if not _skip_edge_overlays:
		_populate_chunk_edge_overlays(chunk_coord)
		_update_neighbor_edge_overlays(chunk_coord)


## Generate (if needed) and load a chunk into the scene tree.
## Convenience wrapper that calls both phases sequentially.
func _load_chunk(chunk_coord: Vector2i) -> void:
	_generate_chunk_data(chunk_coord)
	_create_chunk_visuals(chunk_coord)


## Unload a chunk from the scene tree. World data is preserved.
func _unload_chunk(chunk_coord: Vector2i) -> void:
	if not active_chunks.has(chunk_coord):
		return

	# Save dirty chunks before unloading
	if world_data.is_chunk_dirty(chunk_coord):
		save_manager.save_chunk(chunk_coord, world_data)

	# Remove darkness overlay for this chunk
	if chunk_darkness_sprites.has(chunk_coord):
		chunk_darkness_sprites[chunk_coord].queue_free()
		chunk_darkness_sprites.erase(chunk_coord)

	# Remove torch visuals for this chunk
	var torch_positions: Array = world_data.get_chunk_torches(chunk_coord)
	for tpos in torch_positions:
		if active_torches.has(tpos):
			active_torches[tpos].queue_free()
			active_torches.erase(tpos)

	var chunk_layers: Dictionary = active_chunks[chunk_coord]
	for layer_key in chunk_layers:
		chunk_layers[layer_key].queue_free()
	active_chunks.erase(chunk_coord)
	chunk_unloaded.emit(chunk_coord)


## Get the base TileMapLayer for a chunk.
func _get_base_tilemap(chunk_coord: Vector2i) -> TileMapLayer:
	var chunk_data: Dictionary = active_chunks.get(chunk_coord, {})
	return chunk_data.get("base", null)


# --- Structure placement ---

## Place the spawn chamber structure tiles. These will be applied on top of
## generated terrain when chunks around the origin are first created.
func _place_spawn_chamber() -> void:
	var spawn_data: Dictionary = StructurePlacer.create_spawn_chamber()
	var spawn_y: int = GameState.start_depth - 5  # Chamber wraps around player
	var spawn_pos := Vector2i(-8, spawn_y)
	var tiles: Dictionary = spawn_data["tiles"]

	for local_pos in tiles:
		var wpos: Vector2i = spawn_pos + local_pos
		structure_tiles[wpos] = tiles[local_pos]

	print("[ChunkManager] Spawn chamber registered at tile (%d, %d) (start_depth=%d)" % [
		spawn_pos.x, spawn_pos.y, GameState.start_depth])


## Apply structure tile overrides to a chunk after terrain generation.
## Overwrites generated tiles with structure data, including EMPTY to carve.
func _apply_structure_tiles_to_chunk(chunk_coord: Vector2i) -> void:
	var origin: Vector2i = WorldData.chunk_to_world(chunk_coord)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var wpos: Vector2i = origin + Vector2i(x, y)
			if structure_tiles.has(wpos):
				var tile_type: int = structure_tiles[wpos]
				if tile_type == TileDatabase.TileType.EMPTY:
					world_data.tiles.erase(wpos)
				else:
					world_data.tiles[wpos] = tile_type


# --- Tile update handlers (GameServer signals) ---

## Called when a tile is mined via GameServer. Update visuals and spawn a drop.
func _on_tile_mined(world_pos: Vector2i, tile_type: int, _tool_used: String) -> void:
	# Update the visual tilemap
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	var base_tilemap: TileMapLayer = _get_base_tilemap(chunk_coord)
	if base_tilemap:
		var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
		base_tilemap.erase_cell(local_pos)

	# Spawn dropped item
	_spawn_dropped_item(world_pos, tile_type)

	# Update neighbor visuals (they may now have exposed edges)
	_update_neighbor_visuals(world_pos)

	# Update edge overlays for this tile and neighbors
	_update_edge_overlays_around(world_pos)


## Called when a tile is placed via GameServer. Update the visual tilemap.
func _on_tile_placed(world_pos: Vector2i, tile_type: int) -> void:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	var base_tilemap: TileMapLayer = _get_base_tilemap(chunk_coord)
	if base_tilemap:
		var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
		var visual: Dictionary = _get_tile_visual(world_pos, tile_type)
		base_tilemap.set_cell(local_pos, visual["source_id"], visual["atlas_coords"])

	# Update neighbor visuals (they may need to lose exposed edges)
	_update_neighbor_visuals(world_pos)

	# Update edge overlays for this tile and neighbors
	_update_edge_overlays_around(world_pos)


## Spawn a dropped item at the world position of a mined tile.
func _spawn_dropped_item(world_pos: Vector2i, tile_type: int) -> void:
	var drop: Dictionary = TileDatabase.get_drop(tile_type)
	if drop["item"] == "":
		return
	var item: CharacterBody2D = _dropped_item_scene.instantiate()
	var spawn_pos := Vector2(
		world_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		world_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)
	item.initialize(drop["item"], drop["count"], spawn_pos)
	add_child(item)


# --- Tileset building ---

## Build the shared TileSet programmatically. Creates a texture atlas with
## one tile per type, colored according to TileDatabase properties.
## Then adds separate atlas sources for tile types with hand-drawn sprite sheets.
func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)  # Layer 1 = World
	ts.set_physics_layer_collision_mask(0, 0)

	# Build collision polygon
	var half: float = TILE_SIZE / 2.0
	collision_polygon = PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])

	# Source ID 0: Programmatic colored tiles (fallback for types without art)
	_add_programmatic_atlas(ts)

	# Source IDs 1+: Autotile sheets for registered types
	var next_source_id: int = 1
	for tile_type in TileDatabase.autotile_textures:
		_add_autotile_source(ts, tile_type, next_source_id)
		next_source_id += 1

	# Edge overlay sources (same textures, NO collision)
	for tile_type in TileDatabase.autotile_textures:
		_add_edge_overlay_source(ts, tile_type, next_source_id)
		next_source_id += 1

	return ts


## Add the programmatic colored-tile atlas as source 0.
func _add_programmatic_atlas(ts: TileSet) -> void:
	var tile_types: Array = TileDatabase.get_tile_types()
	var atlas_width: int = tile_types.size()

	var img := Image.create(atlas_width * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)

	for i in range(tile_types.size()):
		var tile_type: int = tile_types[i]
		var color: Color = TileDatabase.get_properties(tile_type)["color"]
		var x_offset: int = i * TILE_SIZE
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				var variation: float = (_hash_pixel(x_offset + x, y) - 0.5) * 0.1
				var c := Color(
					clampf(color.r + variation, 0.0, 1.0),
					clampf(color.g + variation, 0.0, 1.0),
					clampf(color.b + variation, 0.0, 1.0),
					1.0
				)
				img.set_pixel(x_offset + x, y, c)

	var tex := ImageTexture.create_from_image(img)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_source(atlas, 0)

	for i in range(tile_types.size()):
		var coords := Vector2i(i, 0)
		atlas.create_tile(coords)
		var tile_data: TileData = atlas.get_tile_data(coords, 0)
		if tile_types[i] != TileDatabase.TileType.WATER:
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, collision_polygon)


## Add an autotile sprite sheet as a separate atlas source.
func _add_autotile_source(ts: TileSet, tile_type: int, source_id: int) -> void:
	var autotile_info: Dictionary = TileDatabase.autotile_textures[tile_type]
	var texture: Texture2D = load(autotile_info["path"])
	var block_offset: Vector2i = autotile_info["block_offset"]

	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_source(atlas, source_id)

	# Store source ID back in TileDatabase for runtime lookup
	TileDatabase.autotile_source_ids[tile_type] = source_id

	# Create tiles for all base autotile positions (rows 0-8, cols 0-15).
	# Covers bitmask positions, variant positions, and any other base-layer cells.
	var created_coords: Dictionary = {}
	var tex_size: Vector2 = texture.get_size()

	for row in range(9):
		for col in range(16):
			var coords := Vector2i(col, row) + block_offset
			var px: int = coords.x * TILE_SIZE
			var py: int = coords.y * TILE_SIZE
			if px + TILE_SIZE <= int(tex_size.x) and py + TILE_SIZE <= int(tex_size.y):
				if not created_coords.has(coords):
					atlas.create_tile(coords)
					var td: TileData = atlas.get_tile_data(coords, 0)
					if tile_type != TileDatabase.TileType.WATER:
						td.add_collision_polygon(0)
						td.set_collision_polygon_points(0, 0, collision_polygon)
					created_coords[coords] = true

	print("[ChunkManager] Autotile source %d registered for %s (%d tiles)" % [
		source_id, TileDatabase.get_properties(tile_type).get("name", "Unknown"), created_coords.size()])


## Add edge overlay tiles as a separate atlas source (NO collision).
func _add_edge_overlay_source(ts: TileSet, tile_type: int, source_id: int) -> void:
	var autotile_info: Dictionary = TileDatabase.autotile_textures[tile_type]
	var texture: Texture2D = load(autotile_info["path"])
	var block_offset: Vector2i = autotile_info["block_offset"]

	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_source(atlas, source_id)

	edge_source_ids[tile_type] = source_id

	# Create tiles for edge overlay atlas (rows 0-8, cols 0-15). NO collision.
	var created: Dictionary = {}
	var tex_size: Vector2 = texture.get_size()

	for row in range(9):
		for col in range(16):
			var coords := Vector2i(col, row) + block_offset
			var px: int = coords.x * TILE_SIZE
			var py: int = coords.y * TILE_SIZE
			if px + TILE_SIZE <= int(tex_size.x) and py + TILE_SIZE <= int(tex_size.y):
				if not created.has(coords):
					atlas.create_tile(coords)
					created[coords] = true

	print("[ChunkManager] Edge overlay source %d: %d tiles for %s" % [
		source_id, created.size(),
		TileDatabase.get_properties(tile_type).get("name", "Unknown")])


## Scan edge overlay positions to auto-detect which tile types have edge overlay art.
## Checks the center variant (context key 3 = both perpendiculars filled) for each
## direction in EDGE_CONTEXT_ATLAS for non-transparent pixels.
func _detect_edge_capable_types() -> void:
	for tile_type in TileDatabase.autotile_textures:
		var info: Dictionary = TileDatabase.autotile_textures[tile_type]
		var texture: Texture2D = load(info["path"])
		var img: Image = texture.get_image()
		var block_offset: Vector2i = info["block_offset"]
		var has_edges: bool = false

		# Check center variant (context key 3) of each edge direction for non-transparent pixels
		for dir in TileDatabase.EDGE_CONTEXT_ATLAS:
			if has_edges:
				break
			var context_map: Dictionary = TileDatabase.EDGE_CONTEXT_ATLAS[dir]
			if not context_map.has(3):
				continue
			var coords: Vector2i = context_map[3] + block_offset
			var px: int = coords.x * TILE_SIZE
			var py: int = coords.y * TILE_SIZE
			if px + TILE_SIZE > img.get_width() or py + TILE_SIZE > img.get_height():
				continue
			for x in range(TILE_SIZE):
				if has_edges:
					break
				for y in range(TILE_SIZE):
					if img.get_pixel(px + x, py + y).a > 0.01:
						has_edges = true
						break

		TileDatabase.edge_capable_types[tile_type] = has_edges
		var type_name: String = TileDatabase.get_properties(tile_type).get("name", "Unknown")
		if has_edges:
			print("[ChunkManager] %s: edge capable (edge overlays detected)" % type_name)
		else:
			print("[ChunkManager] %s: using legacy autotile (no edge overlays)" % type_name)


## Simple pixel-position hash for tile texture variation.
func _hash_pixel(x: int, y: int) -> float:
	var h: int = hash(Vector2i(x, y))
	return absf(float(h % 1000) / 1000.0)


# --- Autotile bitmask ---

## Cardinal neighbor offsets: N, E, S, W (matching bit positions 0-3).
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),   # Bit 0: North
	Vector2i(1, 0),    # Bit 1: East
	Vector2i(0, 1),    # Bit 2: South
	Vector2i(-1, 0),   # Bit 3: West
]

## Diagonal neighbor offsets: NW, NE, SW, SE.
const DIAGONAL_OFFSETS: Dictionary = {
	"NW": Vector2i(-1, -1),
	"NE": Vector2i(1, -1),
	"SW": Vector2i(-1, 1),
	"SE": Vector2i(1, 1),
}

## Calculate 4-bit cardinal bitmask for a tile. Bit=1 means any non-empty neighbor present.
func _calc_bitmask(world_pos: Vector2i) -> int:
	var bitmask: int = 0
	for i in range(CARDINAL_OFFSETS.size()):
		var neighbor_pos: Vector2i = world_pos + CARDINAL_OFFSETS[i]
		if world_data.get_tile(neighbor_pos) != TileDatabase.TileType.EMPTY:
			bitmask |= (1 << i)
	return bitmask


## Get the visual source_id and atlas_coords for a tile at a world position.
## Uses autotile bitmask for registered types, falls back to programmatic atlas.
func _get_tile_visual(world_pos: Vector2i, tile_type: int) -> Dictionary:
	if not TileDatabase.has_autotile(tile_type):
		return {
			"source_id": 0,
			"atlas_coords": TileDatabase.get_atlas_coords(tile_type),
		}

	var source_id: int = TileDatabase.get_autotile_source_id(tile_type)
	var block_offset: Vector2i = TileDatabase.autotile_textures[tile_type]["block_offset"]
	var bitmask: int = _calc_bitmask(world_pos)
	var atlas_coords: Vector2i = TileDatabase.BITMASK_TO_ATLAS[bitmask] + block_offset

	return {
		"source_id": source_id,
		"atlas_coords": atlas_coords,
	}


## Update visuals for all 8 neighbors of a changed tile.
## Handles cross-chunk boundaries.
func _update_neighbor_visuals(center_pos: Vector2i) -> void:
	var all_offsets: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1),
	]
	for offset in all_offsets:
		var neighbor_pos: Vector2i = center_pos + offset
		var neighbor_type: int = world_data.get_tile(neighbor_pos)
		if neighbor_type != TileDatabase.TileType.EMPTY:
			_update_single_tile_visual(neighbor_pos, neighbor_type)


## Recalculate and update the visual for a single tile.
func _update_single_tile_visual(world_pos: Vector2i, tile_type: int) -> void:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	var tilemap: TileMapLayer = _get_base_tilemap(chunk_coord)
	if tilemap == null:
		return

	var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
	var visual: Dictionary = _get_tile_visual(world_pos, tile_type)
	tilemap.set_cell(local_pos, visual["source_id"], visual["atlas_coords"])


# --- Edge overlay rendering ---

## Place an overlay tile on a specific world position's overlay layer.
## Handles cross-chunk placement (overlay may be on a different chunk's layer).
func _place_overlay_on_cell(world_pos: Vector2i, source_id: int, atlas_coords: Vector2i, layer_name: String) -> void:
	var target_chunk: Vector2i = WorldData.world_to_chunk(world_pos)
	if not active_chunks.has(target_chunk):
		return
	var chunk_layers: Dictionary = active_chunks[target_chunk]
	var layer: TileMapLayer = chunk_layers.get(layer_name, null)
	if layer == null:
		return
	var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(target_chunk)
	layer.set_cell(local_pos, source_id, atlas_coords)


## Clear all edge overlay cells at a world position across all 4 overlay layers.
func _clear_overlays_at(world_pos: Vector2i) -> void:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	if not active_chunks.has(chunk_coord):
		return
	var chunk_layers: Dictionary = active_chunks[chunk_coord]
	var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
	for layer_name in ["edge_floor", "edge_wall_l", "edge_wall_r", "edge_ceiling", "corner_se", "corner_sw", "corner_ne", "corner_nw"]:
		var layer: TileMapLayer = chunk_layers.get(layer_name, null)
		if layer:
			layer.erase_cell(local_pos)


func _update_edge_overlays_around(center_pos: Vector2i) -> void:
	# Use 5x5 area (radius 2) to ensure overlays from tiles 2 cells away
	# that extend into the affected zone are properly recalculated.
	var all_positions: Array = []
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			all_positions.append(center_pos + Vector2i(dx, dy))

	# Clear overlays on all affected positions
	for pos in all_positions:
		_clear_overlays_at(pos)

	# Recalculate overlays for empty cells only
	for pos in all_positions:
		if world_data.get_tile(pos) == TileDatabase.TileType.EMPTY:
			_calculate_cell_overlays(pos)


## Calculate and place edge overlays for a single EMPTY cell.
## Checks all 4 cardinal neighbors for solid tiles and pulls their edge art.
## Each direction can use a different tile type's atlas (multi-material support).
func _calculate_cell_overlays(empty_pos: Vector2i) -> void:
	# Cardinal directions: check each neighbor for solid tiles
	# If solid, place that tile's edge overlay on this empty cell
	var cardinal_checks: Array = [
		# [direction_of_neighbor, edge_direction, layer, perp_offset1, perp_offset2]
		# If N neighbor is solid -> its BOTTOM edge goes on this cell
		[Vector2i(0, -1), TileDatabase.EdgeDir.BOTTOM, "edge_ceiling",
		 Vector2i(1, 0), Vector2i(-1, 0)],  # perp E, W of the source tile
		# If S neighbor is solid -> its TOP edge goes on this cell
		[Vector2i(0, 1), TileDatabase.EdgeDir.TOP, "edge_floor",
		 Vector2i(1, 0), Vector2i(-1, 0)],  # perp E, W
		# If E neighbor is solid -> its LEFT edge goes on this cell
		[Vector2i(1, 0), TileDatabase.EdgeDir.LEFT, "edge_wall_l",
		 Vector2i(0, 1), Vector2i(0, -1)],  # perp S, N
		# If W neighbor is solid -> its RIGHT edge goes on this cell
		[Vector2i(-1, 0), TileDatabase.EdgeDir.RIGHT, "edge_wall_r",
		 Vector2i(0, 1), Vector2i(0, -1)],  # perp S, N
	]

	for check in cardinal_checks:
		var neighbor_offset: Vector2i = check[0]
		var edge_dir: int = check[1]
		var layer_name: String = check[2]
		var perp1_offset: Vector2i = check[3]
		var perp2_offset: Vector2i = check[4]

		var neighbor_pos: Vector2i = empty_pos + neighbor_offset
		var tile_type: int = world_data.get_tile(neighbor_pos)
		if tile_type == TileDatabase.TileType.EMPTY:
			continue
		if not TileDatabase.has_edge_overlay(tile_type):
			continue

		var edge_sid: int = edge_source_ids.get(tile_type, -1)
		if edge_sid < 0:
			continue
		var block_offset: Vector2i = TileDatabase.autotile_textures[tile_type]["block_offset"]

		# Determine context from the source tile's perpendicular and parallel neighbors
		var perp1_filled: bool = world_data.get_tile(neighbor_pos + perp1_offset) != TileDatabase.TileType.EMPTY
		var perp2_filled: bool = world_data.get_tile(neighbor_pos + perp2_offset) != TileDatabase.TileType.EMPTY
		var parallel_filled: bool = world_data.get_tile(neighbor_pos + neighbor_offset) != TileDatabase.TileType.EMPTY

		var edge_coords: Vector2i = TileDatabase.get_edge_coords(edge_dir, perp1_filled, perp2_filled, parallel_filled)
		_place_overlay_on_cell(empty_pos, edge_sid, edge_coords + block_offset, layer_name)

	# Diagonal checks for inner corner decorations
	# An inner corner exists when this empty cell has two adjacent cardinal neighbors
	# that are BOTH solid, AND the diagonal tile between them is also solid.
	# Each corner uses a layer based on its visual quadrant. The opposite cardinal
	# being empty guarantees that layer is free; if it's solid, the edge overwrites
	# the inner corner (acceptable — inner corners are decorative).
	var diag_checks: Array = [
		# [diag_offset, adj1_offset, adj2_offset, corner_name, layer]
		# TL of cell: solid at NW, N+W solid. Dedicated corner layer avoids edge conflict.
		[Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), "SE", "corner_se"],
		# TR of cell: solid at NE, N+E solid. Dedicated corner layer avoids edge conflict.
		[Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 0), "SW", "corner_sw"],
		# BL of cell: solid at SW, S+W solid. Dedicated corner layer avoids edge conflict.
		[Vector2i(-1, 1), Vector2i(0, 1), Vector2i(-1, 0), "NE", "corner_ne"],
		# BR of cell: solid at SE, S+E solid. Dedicated corner layer avoids edge conflict.
		[Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, 0), "NW", "corner_nw"],
	]

	for check in diag_checks:
		var diag_offset: Vector2i = check[0]
		var adj1_offset: Vector2i = check[1]
		var adj2_offset: Vector2i = check[2]
		var corner_name: String = check[3]
		var layer_name: String = check[4]

		var diag_pos: Vector2i = empty_pos + diag_offset
		var diag_type: int = world_data.get_tile(diag_pos)
		if diag_type == TileDatabase.TileType.EMPTY:
			continue
		if not TileDatabase.has_edge_overlay(diag_type):
			continue

		var adj1_type: int = world_data.get_tile(empty_pos + adj1_offset)
		var adj2_type: int = world_data.get_tile(empty_pos + adj2_offset)

		# Inner corner: both adjacent cardinals are solid
		if adj1_type != TileDatabase.TileType.EMPTY and adj2_type != TileDatabase.TileType.EMPTY:
			var edge_sid: int = edge_source_ids.get(diag_type, -1)
			if edge_sid < 0:
				continue
			var block_offset: Vector2i = TileDatabase.autotile_textures[diag_type]["block_offset"]
			var corner_coords: Vector2i = TileDatabase.get_inner_corner_overlay_coords(corner_name, empty_pos) + block_offset
			_place_overlay_on_cell(empty_pos, edge_sid, corner_coords, layer_name)

	# L-shape corners: two adjacent cardinals solid, diagonal between them empty.
	# The empty cell detects the L-shape, then pushes the overlay onto the
	# neighboring SOLID cell (the one with lower Y = higher on screen = target).
	# The source tile (higher Y) provides the corner art.
	# Context is determined by the source tile's full cardinal neighborhood
	# (has any vertical neighbor? has any horizontal neighbor?).
	var lshape_checks: Array = [
		# [card1_offset, card2_offset, diag_offset, target_is_card1, corner_name, layer_name]
		# Case A: N+E solid, NE empty -> target=N, source=E, corner TL
		[Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, -1), true, "TL", "edge_floor"],
		# Case B: N+W solid, NW empty -> target=N, source=W, corner TR
		[Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, -1), true, "TR", "edge_wall_r"],
		# Case C: S+E solid, SE empty -> target=E, source=S, corner TR
		[Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), false, "TR", "edge_wall_r"],
		# Case D: S+W solid, SW empty -> target=W, source=S, corner TL
		[Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, 1), false, "TL", "edge_floor"],
	]

	for check in lshape_checks:
		var card1_offset: Vector2i = check[0]
		var card2_offset: Vector2i = check[1]
		var diag_offset: Vector2i = check[2]
		var target_is_card1: bool = check[3]
		var corner_name: String = check[4]
		var layer_name: String = check[5]

		var card1_pos: Vector2i = empty_pos + card1_offset
		var card2_pos: Vector2i = empty_pos + card2_offset
		var diag_pos: Vector2i = empty_pos + diag_offset

		var card1_type: int = world_data.get_tile(card1_pos)
		var card2_type: int = world_data.get_tile(card2_pos)
		var diag_type: int = world_data.get_tile(diag_pos)

		# L-shape: both cardinals solid, diagonal empty
		if card1_type == TileDatabase.TileType.EMPTY or card2_type == TileDatabase.TileType.EMPTY:
			continue
		if diag_type != TileDatabase.TileType.EMPTY:
			continue

		# Target gets the overlay, source provides the art
		var target_pos: Vector2i = card1_pos if target_is_card1 else card2_pos
		var source_pos: Vector2i = card2_pos if target_is_card1 else card1_pos
		var source_type: int = card2_type if target_is_card1 else card1_type

		if not TileDatabase.has_edge_overlay(source_type):
			continue
		var edge_sid: int = edge_source_ids.get(source_type, -1)
		if edge_sid < 0:
			continue
		var block_offset: Vector2i = TileDatabase.autotile_textures[source_type]["block_offset"]

		# Source tile's overall shape context: check all 4 cardinal neighbors
		var src_n: bool = world_data.get_tile(source_pos + Vector2i(0, -1)) != TileDatabase.TileType.EMPTY
		var src_s: bool = world_data.get_tile(source_pos + Vector2i(0, 1)) != TileDatabase.TileType.EMPTY
		var src_e: bool = world_data.get_tile(source_pos + Vector2i(1, 0)) != TileDatabase.TileType.EMPTY
		var src_w: bool = world_data.get_tile(source_pos + Vector2i(-1, 0)) != TileDatabase.TileType.EMPTY
		var has_vertical: bool = src_n or src_s
		var has_horizontal: bool = src_e or src_w
		var corner_coords: Vector2i = TileDatabase.get_corner_coords_contextual(corner_name, has_vertical, has_horizontal) + block_offset
		_place_overlay_on_cell(target_pos, edge_sid, corner_coords, layer_name)

	# Outer corner checks
	# An outer corner exists when this empty cell has two adjacent cardinal neighbors
	# that are BOTH empty, but the diagonal tile is solid.
	# Each corner uses a guaranteed-free layer (the empty cardinal = no edge on that layer).
	# All 4 corners land on different layers, so no overwrites even with 4 diagonal neighbors.
	var outer_checks: Array = [
		# [diag_to_solid_tile, adj1_must_be_empty, adj2_must_be_empty, corner_name, layer]
		# TL corner: solid at SE, E+S empty → edge_floor free (S empty = no floor edge)
		[Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1), "TL", "edge_floor"],
		# TR corner: solid at SW, W+S empty → edge_wall_r free (W empty = no wall_r edge)
		[Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, 1), "TR", "edge_wall_r"],
		# BL corner: solid at NE, E+N empty → edge_wall_l free (E empty = no wall_l edge)
		[Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, -1), "BL", "edge_wall_l"],
		# BR corner: solid at NW, W+N empty → edge_ceiling free (N empty = no ceiling edge)
		[Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(0, -1), "BR", "edge_ceiling"],
	]

	for check in outer_checks:
		var diag_offset: Vector2i = check[0]
		var adj1_offset: Vector2i = check[1]
		var adj2_offset: Vector2i = check[2]
		var corner_name: String = check[3]
		var layer_name: String = check[4]

		var diag_pos: Vector2i = empty_pos + diag_offset
		var diag_type: int = world_data.get_tile(diag_pos)
		if diag_type == TileDatabase.TileType.EMPTY:
			continue
		if not TileDatabase.has_edge_overlay(diag_type):
			continue

		var adj1_type: int = world_data.get_tile(empty_pos + adj1_offset)
		var adj2_type: int = world_data.get_tile(empty_pos + adj2_offset)

		# Outer corner: both adjacent cardinals are also empty
		if adj1_type == TileDatabase.TileType.EMPTY and adj2_type == TileDatabase.TileType.EMPTY:
			var edge_sid: int = edge_source_ids.get(diag_type, -1)
			if edge_sid < 0:
				continue
			var block_offset: Vector2i = TileDatabase.autotile_textures[diag_type]["block_offset"]
			# Source tile's overall shape context: check all 4 cardinal neighbors
			var src_n: bool = world_data.get_tile(diag_pos + Vector2i(0, -1)) != TileDatabase.TileType.EMPTY
			var src_s: bool = world_data.get_tile(diag_pos + Vector2i(0, 1)) != TileDatabase.TileType.EMPTY
			var src_e: bool = world_data.get_tile(diag_pos + Vector2i(1, 0)) != TileDatabase.TileType.EMPTY
			var src_w: bool = world_data.get_tile(diag_pos + Vector2i(-1, 0)) != TileDatabase.TileType.EMPTY
			var has_vertical: bool = src_n or src_s
			var has_horizontal: bool = src_e or src_w
			var corner_coords: Vector2i = TileDatabase.get_corner_coords_contextual(corner_name, has_vertical, has_horizontal) + block_offset
			_place_overlay_on_cell(empty_pos, edge_sid, corner_coords, layer_name)


## Populate all edge overlays for an entire chunk.
func _populate_chunk_edge_overlays(chunk_coord: Vector2i) -> void:
	var origin: Vector2i = WorldData.chunk_to_world(chunk_coord)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var wpos: Vector2i = origin + Vector2i(x, y)
			if world_data.get_tile(wpos) == TileDatabase.TileType.EMPTY:
				_calculate_cell_overlays(wpos)


## Update edge overlays from neighboring chunks that may extend into this chunk.
func _update_neighbor_edge_overlays(chunk_coord: Vector2i) -> void:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor_chunk := Vector2i(chunk_coord.x + dx, chunk_coord.y + dy)
			if not active_chunks.has(neighbor_chunk):
				continue
			var border_positions: Array = _get_border_positions(neighbor_chunk, chunk_coord)
			for wpos in border_positions:
				if world_data.get_tile(wpos) == TileDatabase.TileType.EMPTY:
					_calculate_cell_overlays(wpos)


## Get tile positions along the edge of source_chunk that face target_chunk.
func _get_border_positions(source_chunk: Vector2i, target_chunk: Vector2i) -> Array:
	var result: Array = []
	var origin: Vector2i = WorldData.chunk_to_world(source_chunk)
	var diff: Vector2i = target_chunk - source_chunk

	if diff.x == 1:
		for y in range(CHUNK_SIZE):
			result.append(origin + Vector2i(CHUNK_SIZE - 1, y))
	elif diff.x == -1:
		for y in range(CHUNK_SIZE):
			result.append(origin + Vector2i(0, y))

	if diff.y == 1:
		for x in range(CHUNK_SIZE):
			result.append(origin + Vector2i(x, CHUNK_SIZE - 1))
	elif diff.y == -1:
		for x in range(CHUNK_SIZE):
			result.append(origin + Vector2i(x, 0))

	if diff.x != 0 and diff.y != 0:
		var cx: int = CHUNK_SIZE - 1 if diff.x == 1 else 0
		var cy: int = CHUNK_SIZE - 1 if diff.y == 1 else 0
		result.append(origin + Vector2i(cx, cy))

	return result


# --- Per-tile lighting ---

## Get ambient light level for a given world tile Y coordinate.
## Same depth breakpoints as the old CanvasModulate system but per-tile.
func _get_ambient_for_depth(wy: int) -> float:
	if wy < 0:
		return 1.0
	elif wy < 80:
		return lerpf(1.0, 0.7, float(wy) / 80.0)
	elif wy < 200:
		return lerpf(0.7, 0.4, float(wy - 80) / 120.0)
	elif wy < 400:
		return lerpf(0.4, 0.15, float(wy - 200) / 200.0)
	else:
		return lerpf(0.15, AMBIENT_FLOOR, clampf(float(wy - 400) / 400.0, 0.0, 1.0))


## Euclidean distance between two tile positions.
func _tile_distance(x1: int, y1: int, x2: int, y2: int) -> float:
	var dx: float = float(x1 - x2)
	var dy: float = float(y1 - y2)
	return sqrt(dx * dx + dy * dy)


## Calculate the final light level for a tile, combining ambient and torch light.
func _calculate_tile_light(wx: int, wy: int, nearby_torches: Array) -> float:
	var ambient: float = _get_ambient_for_depth(wy)
	var best_torch: float = 0.0
	for torch_pos in nearby_torches:
		var dist: float = _tile_distance(wx, wy, torch_pos.x, torch_pos.y)
		if dist < TORCH_RADIUS:
			var t: float = dist / float(TORCH_RADIUS)
			var contribution: float = TORCH_LIGHT_LEVEL * (1.0 - pow(t, TORCH_FALLOFF_POWER))
			if contribution > best_torch:
				best_torch = contribution
	return maxf(ambient, best_torch)


## Gather torch positions from a chunk and its 8 neighbors that could bleed
## light into this chunk (within TORCH_RADIUS of the chunk boundary).
func _gather_torches_for_chunk(chunk_coord: Vector2i) -> Array:
	var result: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var neighbor := Vector2i(chunk_coord.x + dx, chunk_coord.y + dy)
			var torch_list: Array = world_data.get_chunk_torches(neighbor)
			if dx == 0 and dy == 0:
				# Same chunk: include all torches
				result.append_array(torch_list)
			else:
				# Neighbor chunk: only include torches close enough to bleed in
				var origin: Vector2i = WorldData.chunk_to_world(chunk_coord)
				for tpos in torch_list:
					# Check if torch is within TORCH_RADIUS of any edge of our chunk
					var closest_x: int = clampi(tpos.x, origin.x, origin.x + CHUNK_SIZE - 1)
					var closest_y: int = clampi(tpos.y, origin.y, origin.y + CHUNK_SIZE - 1)
					if _tile_distance(tpos.x, tpos.y, closest_x, closest_y) < TORCH_RADIUS:
						result.append(tpos)
	return result


## Find which loaded chunks could be affected by a torch at the given position.
func _get_affected_chunks(torch_pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# Check all positions within TORCH_RADIUS to find unique chunks
	var min_chunk := WorldData.world_to_chunk(Vector2i(torch_pos.x - TORCH_RADIUS, torch_pos.y - TORCH_RADIUS))
	var max_chunk := WorldData.world_to_chunk(Vector2i(torch_pos.x + TORCH_RADIUS, torch_pos.y + TORCH_RADIUS))
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var cc := Vector2i(cx, cy)
			if active_chunks.has(cc):
				result.append(cc)
	return result


## Create a darkness overlay Sprite2D for a chunk. Each pixel in the 32x32
## image represents one tile; the sprite is scaled up to TILE_SIZE.
func _create_darkness_overlay(chunk_coord: Vector2i) -> void:
	var img := Image.create(CHUNK_SIZE, CHUNK_SIZE, false, Image.FORMAT_RGBA8)
	_update_darkness_image(chunk_coord, img)

	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.z_index = DARKNESS_Z_INDEX
	sprite.scale = Vector2(TILE_SIZE, TILE_SIZE)
	sprite.position = Vector2(
		chunk_coord.x * PIXEL_CHUNK_SIZE,
		chunk_coord.y * PIXEL_CHUNK_SIZE
	)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	chunk_darkness_sprites[chunk_coord] = sprite


## Fill a 32x32 image with darkness alpha values based on per-tile lighting.
func _update_darkness_image(chunk_coord: Vector2i, img: Image) -> void:
	var origin: Vector2i = WorldData.chunk_to_world(chunk_coord)
	var nearby_torches: Array = _gather_torches_for_chunk(chunk_coord)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var wx: int = origin.x + x
			var wy: int = origin.y + y
			var light: float = _calculate_tile_light(wx, wy, nearby_torches)
			var darkness: float = 1.0 - clampf(light, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, darkness))


## Update the darkness overlay for an already-loaded chunk.
func _update_chunk_lighting(chunk_coord: Vector2i) -> void:
	if not chunk_darkness_sprites.has(chunk_coord):
		return
	var sprite: Sprite2D = chunk_darkness_sprites[chunk_coord]
	var tex: ImageTexture = sprite.texture as ImageTexture
	var img: Image = tex.get_image()
	_update_darkness_image(chunk_coord, img)
	tex.update(img)


## Recalculate lighting for all loaded chunks affected by a torch change.
func _recalculate_lighting_around(world_pos: Vector2i) -> void:
	var affected: Array[Vector2i] = _get_affected_chunks(world_pos)
	for cc in affected:
		_update_chunk_lighting(cc)


# --- Depth tracking ---

## Update max depth stat in BehaviorTracker.
func _update_depth_tracking() -> void:
	if not GameState.player:
		return
	var depth: float = GameState.player.global_position.y / float(TILE_SIZE)
	if depth > 0.0:
		BehaviorTracker.update_stat_max("max_depth_reached", depth)


# --- Save / Exit ---

## Save all dirty loaded chunks, world metadata, and behavior data.
## Called before game exit.
func save_all() -> void:
	for chunk_coord in active_chunks:
		if world_data.is_chunk_dirty(chunk_coord):
			save_manager.save_chunk(chunk_coord, world_data)

	# Save world metadata
	var player_pos := Vector2.ZERO
	if GameState.player:
		player_pos = GameState.player.global_position
	save_manager.save_world_meta(GameState.world_seed, player_pos, GameState.start_depth, GameState.world_display_name, GameState.get_total_playtime())

	# Save behavior tracker data
	save_manager.save_behavior_data(BehaviorTracker)

	print("[ChunkManager] All data saved.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_all()
		get_tree().quit()


# --- Torch management ---

## Spawn a torch visual node at a world tile position.
func _spawn_torch(world_pos: Vector2i) -> void:
	if active_torches.has(world_pos):
		return
	var torch: Node2D = _torch_scene.instantiate()
	torch.global_position = Vector2(
		world_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		world_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)
	torch.z_index = TORCH_SPRITE_Z_INDEX
	add_child(torch)
	active_torches[world_pos] = torch


## Remove a torch visual node.
func _remove_torch(world_pos: Vector2i) -> void:
	if active_torches.has(world_pos):
		active_torches[world_pos].queue_free()
		active_torches.erase(world_pos)


## Called when GameServer confirms a torch was placed.
func _on_torch_placed(world_pos: Vector2i) -> void:
	_spawn_torch(world_pos)
	_recalculate_lighting_around(world_pos)


## Called when GameServer confirms a torch was removed.
func _on_torch_removed(world_pos: Vector2i) -> void:
	_remove_torch(world_pos)
	_recalculate_lighting_around(world_pos)


# --- Utility ---

## Get the base TileMapLayer for the chunk containing a world tile position.
## Returns null if the chunk is not currently loaded.
func get_tilemap_at(world_pos: Vector2i) -> TileMapLayer:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	return _get_base_tilemap(chunk_coord)


## Convert a pixel position to a tile coordinate.
func world_to_tile(pixel_pos: Vector2) -> Vector2i:
	return Vector2i(floori(pixel_pos.x / TILE_SIZE), floori(pixel_pos.y / TILE_SIZE))


## Convert a tile coordinate to the pixel position of its center.
func tile_to_world_center(tile_pos: Vector2i) -> Vector2:
	return Vector2(tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0, tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0)


# --- Debug edge overlay labels ---

var _debug_edge_labels: bool = false
var _debug_canvas: CanvasLayer = null
var _debug_panel: PanelContainer = null
var _debug_label: Label = null
var _debug_highlight: Line2D = null
var _debug_last_cell: Vector2i = Vector2i(999999, 999999)


## Handle F9 input to toggle debug edge labels.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == 4194340:  # F9
			_toggle_debug_edge_labels()


## Toggle the debug edge label overlay on/off.
func _toggle_debug_edge_labels() -> void:
	_debug_edge_labels = !_debug_edge_labels
	if _debug_edge_labels:
		# Info panel (screen space via CanvasLayer, always crisp)
		_debug_canvas = CanvasLayer.new()
		_debug_canvas.layer = 100
		add_child(_debug_canvas)

		_debug_panel = PanelContainer.new()
		_debug_panel.position = Vector2(10, 10)
		_debug_canvas.add_child(_debug_panel)

		_debug_label = Label.new()
		_debug_label.text = "Hover over a cell (F9 to close)"
		_debug_label.add_theme_font_size_override("font_size", 14)
		_debug_label.add_theme_color_override("font_color", Color.WHITE)
		_debug_panel.add_child(_debug_label)

		# Cell highlight (world space)
		_debug_highlight = Line2D.new()
		_debug_highlight.width = 2.0
		_debug_highlight.default_color = Color(1, 1, 0, 0.8)
		_debug_highlight.closed = true
		_debug_highlight.points = PackedVector2Array([
			Vector2(0, 0), Vector2(TILE_SIZE, 0),
			Vector2(TILE_SIZE, TILE_SIZE), Vector2(0, TILE_SIZE),
		])
		_debug_highlight.z_index = 20
		add_child(_debug_highlight)

		_debug_last_cell = Vector2i(999999, 999999)
		print("[Debug] Edge overlay hover ON (F9 to toggle)")
	else:
		if _debug_canvas:
			_debug_canvas.queue_free()
			_debug_canvas = null
			_debug_panel = null
			_debug_label = null
		if _debug_highlight:
			_debug_highlight.queue_free()
			_debug_highlight = null
		print("[Debug] Edge overlay hover OFF")


## Update hover debug panel each frame (only recalculates when mouse moves to a new cell).
func _debug_process(_delta: float) -> void:
	if not _debug_edge_labels or not _debug_label:
		return

	var viewport: Viewport = get_viewport()
	var canvas_xform: Transform2D = viewport.get_canvas_transform()
	var mouse_world: Vector2 = canvas_xform.affine_inverse() * viewport.get_mouse_position()
	var cell := Vector2i(int(floor(mouse_world.x / TILE_SIZE)), int(floor(mouse_world.y / TILE_SIZE)))

	if cell == _debug_last_cell:
		return
	_debug_last_cell = cell

	# Update highlight position
	_debug_highlight.position = Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)

	# Build info for this cell
	_debug_label.text = _get_debug_cell_info(cell)


## Build a multi-line debug string describing a single cell's tile, overlays, and actual placed tiles.
## For solid tiles: shows bitmask and atlas coords.
## For empty cells: shows what _calculate_cell_overlays would produce (pulled from neighbors).
func _get_debug_cell_info(target: Vector2i) -> String:
	var lines: Array = []
	var tile_type: int = world_data.get_tile(target)

	lines.append("Cell: (%d, %d)" % [target.x, target.y])

	if tile_type != TileDatabase.TileType.EMPTY:
		var props: Dictionary = TileDatabase.get_properties(tile_type)
		lines.append("Tile: %s" % props.get("name", "Unknown"))
		if TileDatabase.has_autotile(tile_type):
			var bitmask: int = _calc_bitmask(target)
			var block_offset: Vector2i = TileDatabase.autotile_textures[tile_type]["block_offset"]
			var atlas_coords: Vector2i = TileDatabase.BITMASK_TO_ATLAS[bitmask] + block_offset
			lines.append("Bitmask: %d  Atlas: (%d,%d)" % [bitmask, atlas_coords.x, atlas_coords.y])
		lines.append("")
		lines.append("(Solid tile - no overlays here)")
	else:
		lines.append("EMPTY")
		lines.append("")

		# Scan from this empty cell's perspective (mirrors _calculate_cell_overlays logic)
		var overlay_lines: Array = _debug_scan_empty_cell(target)
		if overlay_lines.size() > 0:
			lines.append("Overlays on this cell:")
			for entry in overlay_lines:
				lines.append("  " + entry)
		else:
			lines.append("No overlays")

	# Also show what's ACTUALLY placed on overlay layers
	var chunk_coord: Vector2i = WorldData.world_to_chunk(target)
	if active_chunks.has(chunk_coord):
		var chunk_layers: Dictionary = active_chunks[chunk_coord]
		var local_pos: Vector2i = target - WorldData.chunk_to_world(chunk_coord)
		var actual_lines: Array = []
		for layer_name in ["edge_floor", "edge_wall_l", "edge_wall_r", "edge_ceiling", "corner_se", "corner_sw", "corner_ne", "corner_nw"]:
			var layer: TileMapLayer = chunk_layers.get(layer_name, null)
			if layer and layer.get_cell_source_id(local_pos) != -1:
				var atlas: Vector2i = layer.get_cell_atlas_coords(local_pos)
				actual_lines.append("  %s: (%d,%d)" % [layer_name, atlas.x, atlas.y])
		if actual_lines.size() > 0:
			lines.append("")
			lines.append("Actual placed tiles:")
			for line in actual_lines:
				lines.append(line)

	return "\n".join(lines)


## Scan an empty cell for debug overlay info. Mirrors _calculate_cell_overlays() logic
## but returns label strings instead of placing tiles.
func _debug_scan_empty_cell(empty_pos: Vector2i) -> Array:
	var results: Array = []
	var dir_labels: Dictionary = {
		TileDatabase.EdgeDir.TOP: "Top",
		TileDatabase.EdgeDir.RIGHT: "Right",
		TileDatabase.EdgeDir.BOTTOM: "Bottom",
		TileDatabase.EdgeDir.LEFT: "Left",
	}

	# Cardinal edges: check each neighbor for solid tiles
	var cardinal_checks: Array = [
		[Vector2i(0, -1), TileDatabase.EdgeDir.BOTTOM, "edge_ceiling",
		 Vector2i(1, 0), Vector2i(-1, 0)],
		[Vector2i(0, 1), TileDatabase.EdgeDir.TOP, "edge_floor",
		 Vector2i(1, 0), Vector2i(-1, 0)],
		[Vector2i(1, 0), TileDatabase.EdgeDir.LEFT, "edge_wall_l",
		 Vector2i(0, 1), Vector2i(0, -1)],
		[Vector2i(-1, 0), TileDatabase.EdgeDir.RIGHT, "edge_wall_r",
		 Vector2i(0, 1), Vector2i(0, -1)],
	]

	for check in cardinal_checks:
		var neighbor_offset: Vector2i = check[0]
		var edge_dir: int = check[1]
		var layer_name: String = check[2]
		var perp1_offset: Vector2i = check[3]
		var perp2_offset: Vector2i = check[4]

		var neighbor_pos: Vector2i = empty_pos + neighbor_offset
		var n_type: int = world_data.get_tile(neighbor_pos)
		if n_type == TileDatabase.TileType.EMPTY:
			continue
		if not TileDatabase.has_edge_overlay(n_type):
			continue

		var perp1_filled: bool = world_data.get_tile(neighbor_pos + perp1_offset) != TileDatabase.TileType.EMPTY
		var perp2_filled: bool = world_data.get_tile(neighbor_pos + perp2_offset) != TileDatabase.TileType.EMPTY
		var parallel_filled: bool = world_data.get_tile(neighbor_pos + neighbor_offset) != TileDatabase.TileType.EMPTY
		var edge_coords: Vector2i = TileDatabase.get_edge_coords(edge_dir, perp1_filled, perp2_filled, parallel_filled)
		var n_name: String = TileDatabase.get_properties(n_type).get("name", "?")
		results.append("%s Edge from %s -> (%d,%d) [%s]" % [dir_labels[edge_dir], n_name, edge_coords.x, edge_coords.y, layer_name])

	# Inner corners
	var diag_checks: Array = [
		[Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), "SE", "corner_se"],
		[Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 0), "SW", "corner_sw"],
		[Vector2i(-1, 1), Vector2i(0, 1), Vector2i(-1, 0), "NE", "corner_ne"],
		[Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, 0), "NW", "corner_nw"],
	]

	for check in diag_checks:
		var diag_offset: Vector2i = check[0]
		var adj1_offset: Vector2i = check[1]
		var adj2_offset: Vector2i = check[2]
		var corner_name: String = check[3]
		var layer_name: String = check[4]

		var diag_pos: Vector2i = empty_pos + diag_offset
		var diag_type: int = world_data.get_tile(diag_pos)
		if diag_type == TileDatabase.TileType.EMPTY:
			continue
		if not TileDatabase.has_edge_overlay(diag_type):
			continue

		var adj1_type: int = world_data.get_tile(empty_pos + adj1_offset)
		var adj2_type: int = world_data.get_tile(empty_pos + adj2_offset)

		if adj1_type != TileDatabase.TileType.EMPTY and adj2_type != TileDatabase.TileType.EMPTY:
			var inner_coords: Vector2i = TileDatabase.get_inner_corner_overlay_coords(corner_name, empty_pos)
			var d_name: String = TileDatabase.get_properties(diag_type).get("name", "?")
			results.append("Inner %s from %s -> (%d,%d) [%s]" % [corner_name, d_name, inner_coords.x, inner_coords.y, layer_name])

	# L-shape corners (pushed to solid neighbor cells)
	var lshape_checks_dbg: Array = [
		# [card1_offset, card2_offset, diag_offset, target_is_card1, corner_name, layer_name]
		[Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, -1), true, "TL", "edge_floor"],
		[Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, -1), true, "TR", "edge_wall_r"],
		[Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), false, "TR", "edge_wall_r"],
		[Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, 1), false, "TL", "edge_floor"],
	]

	for check in lshape_checks_dbg:
		var card1_offset: Vector2i = check[0]
		var card2_offset: Vector2i = check[1]
		var diag_offset: Vector2i = check[2]
		var target_is_card1: bool = check[3]
		var corner_name: String = check[4]
		var layer_name: String = check[5]

		var card1_pos: Vector2i = empty_pos + card1_offset
		var card2_pos: Vector2i = empty_pos + card2_offset

		var card1_type: int = world_data.get_tile(card1_pos)
		var card2_type: int = world_data.get_tile(card2_pos)
		var diag_type: int = world_data.get_tile(empty_pos + diag_offset)

		if card1_type == TileDatabase.TileType.EMPTY or card2_type == TileDatabase.TileType.EMPTY:
			continue
		if diag_type != TileDatabase.TileType.EMPTY:
			continue

		var target_pos: Vector2i = card1_pos if target_is_card1 else card2_pos
		var source_pos: Vector2i = card2_pos if target_is_card1 else card1_pos
		var source_type: int = card2_type if target_is_card1 else card1_type

		if not TileDatabase.has_edge_overlay(source_type):
			continue
		# Source tile's overall shape context (same logic as _calculate_cell_overlays)
		var src_n: bool = world_data.get_tile(source_pos + Vector2i(0, -1)) != TileDatabase.TileType.EMPTY
		var src_s: bool = world_data.get_tile(source_pos + Vector2i(0, 1)) != TileDatabase.TileType.EMPTY
		var src_e: bool = world_data.get_tile(source_pos + Vector2i(1, 0)) != TileDatabase.TileType.EMPTY
		var src_w: bool = world_data.get_tile(source_pos + Vector2i(-1, 0)) != TileDatabase.TileType.EMPTY
		var has_vertical: bool = src_n or src_s
		var has_horizontal: bool = src_e or src_w
		var corner_coords: Vector2i = TileDatabase.get_corner_coords_contextual(corner_name, has_vertical, has_horizontal)
		var s_name: String = TileDatabase.get_properties(source_type).get("name", "?")
		results.append("L-shape %s: %s -> pushes to (%d,%d) [%s]" % [corner_name, s_name, target_pos.x, target_pos.y, layer_name])

	# Outer corners
	var outer_checks: Array = [
		[Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1), "TL", "edge_floor"],
		[Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, 1), "TR", "edge_wall_r"],
		[Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, -1), "BL", "edge_wall_l"],
		[Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(0, -1), "BR", "edge_ceiling"],
	]

	for check in outer_checks:
		var diag_offset: Vector2i = check[0]
		var adj1_offset: Vector2i = check[1]
		var adj2_offset: Vector2i = check[2]
		var corner_name: String = check[3]
		var layer_name: String = check[4]

		var diag_pos: Vector2i = empty_pos + diag_offset
		var diag_type: int = world_data.get_tile(diag_pos)
		if diag_type == TileDatabase.TileType.EMPTY:
			continue
		if not TileDatabase.has_edge_overlay(diag_type):
			continue

		var adj1_type: int = world_data.get_tile(empty_pos + adj1_offset)
		var adj2_type: int = world_data.get_tile(empty_pos + adj2_offset)

		if adj1_type == TileDatabase.TileType.EMPTY and adj2_type == TileDatabase.TileType.EMPTY:
			# Source tile's overall shape context (same logic as _calculate_cell_overlays)
			var src_n: bool = world_data.get_tile(diag_pos + Vector2i(0, -1)) != TileDatabase.TileType.EMPTY
			var src_s: bool = world_data.get_tile(diag_pos + Vector2i(0, 1)) != TileDatabase.TileType.EMPTY
			var src_e: bool = world_data.get_tile(diag_pos + Vector2i(1, 0)) != TileDatabase.TileType.EMPTY
			var src_w: bool = world_data.get_tile(diag_pos + Vector2i(-1, 0)) != TileDatabase.TileType.EMPTY
			var has_vertical: bool = src_n or src_s
			var has_horizontal: bool = src_e or src_w
			var corner_coords: Vector2i = TileDatabase.get_corner_coords_contextual(corner_name, has_vertical, has_horizontal)
			var d_name: String = TileDatabase.get_properties(diag_type).get("name", "?")
			results.append("Corner %s from %s -> (%d,%d) [%s]" % [corner_name, d_name, corner_coords.x, corner_coords.y, layer_name])

	return results
