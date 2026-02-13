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

## Tile size in pixels (must match the TileSet and GameServer.TILE_SIZE).
const TILE_SIZE: int = 16

## How many chunks to load in each direction from the player's chunk.
## Total loaded area = (2 * LOAD_RADIUS + 1)^2 chunks.
const LOAD_RADIUS: int = 3

## Pixel size of a full chunk (CHUNK_SIZE * TILE_SIZE).
const PIXEL_CHUNK_SIZE: int = CHUNK_SIZE * TILE_SIZE  # 512

## Torch light radius in tiles.
const TORCH_RADIUS: int = 8

## Maximum light level a torch emits at its center.
const TORCH_LIGHT_LEVEL: float = 1.0

## Falloff exponent for torch light attenuation.
const TORCH_FALLOFF_POWER: float = 1.4

## Minimum ambient light level deep underground.
const AMBIENT_FLOOR: float = 0.03

## Z-index for darkness overlay sprites (above terrain).
const DARKNESS_Z_INDEX: int = 5

## Z-index for torch sprites (above darkness overlay).
const TORCH_SPRITE_Z_INDEX: int = 6

## The authoritative world data.
var world_data: WorldData

## Procedural terrain generator.
var world_generator: WorldGenerator

## Structure placement system.
var structure_placer: StructurePlacer

## Active (loaded) chunks: chunk_coord (Vector2i) -> TileMapLayer node.
var active_chunks: Dictionary = {}

## The shared TileSet used by all chunk TileMapLayers.
var shared_tileset: TileSet

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

## Whether this is the first frame (force-load all chunks synchronously).
var _first_load: bool = true

## Emitted when a chunk is loaded into the scene.
signal chunk_loaded(chunk_coord: Vector2i)

## Emitted when a chunk is unloaded from the scene.
signal chunk_unloaded(chunk_coord: Vector2i)


func _ready() -> void:
	save_manager = SaveManager.new()

	# Try to load existing world save
	var meta = save_manager.load_world_meta()
	if meta != null:
		GameState.world_seed = meta["world_seed"]
		GameState.start_depth = meta["start_depth"]
		GameState.saved_player_position = Vector2(meta["player_position_x"], meta["player_position_y"])
		print("[ChunkManager] Loaded world save. Seed: %d" % GameState.world_seed)

	# Initialize systems
	world_data = WorldData.new()
	world_generator = WorldGenerator.new(GameState.world_seed)
	structure_placer = StructurePlacer.new()

	# Build the shared tileset (programmatic atlas with all tile types)
	shared_tileset = _build_tileset()

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
		# Force-load all chunks synchronously on first frame (no pop-in on game load)
		while chunks_to_generate.size() > 0:
			var chunk_coord: Vector2i = chunks_to_generate.pop_front()
			if _is_chunk_needed(chunk_coord):
				_load_chunk(chunk_coord)
		_first_load = false
	else:
		# Normal: generate up to 2 chunks per frame
		_process_generation_queue()

	# Track max depth for BehaviorTracker
	_update_depth_tracking()


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


## Generate (if needed) and load a chunk into the scene tree.
func _load_chunk(chunk_coord: Vector2i) -> void:
	if active_chunks.has(chunk_coord):
		return

	var origin: Vector2i = WorldData.chunk_to_world(chunk_coord)

	# Generate chunk data if not already generated
	if not generated_chunks.has(chunk_coord):
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
				var atlas_coords: Vector2i = TileDatabase.get_atlas_coords(tile_type)
				tilemap.set_cell(Vector2i(x, y), 0, atlas_coords)

	add_child(tilemap)
	active_chunks[chunk_coord] = tilemap
	chunk_loaded.emit(chunk_coord)

	# Spawn torches for this chunk
	var torch_positions: Array = world_data.get_chunk_torches(chunk_coord)
	for tpos in torch_positions:
		_spawn_torch(tpos)

	# Create per-tile darkness overlay for this chunk
	_create_darkness_overlay(chunk_coord)


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

	var tilemap: TileMapLayer = active_chunks[chunk_coord]
	tilemap.queue_free()
	active_chunks.erase(chunk_coord)
	chunk_unloaded.emit(chunk_coord)


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
	if active_chunks.has(chunk_coord):
		var tilemap: TileMapLayer = active_chunks[chunk_coord]
		var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
		tilemap.erase_cell(local_pos)

	# Spawn dropped item
	_spawn_dropped_item(world_pos, tile_type)


## Called when a tile is placed via GameServer. Update the visual tilemap.
func _on_tile_placed(world_pos: Vector2i, tile_type: int) -> void:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	if active_chunks.has(chunk_coord):
		var tilemap: TileMapLayer = active_chunks[chunk_coord]
		var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
		var atlas_coords: Vector2i = TileDatabase.get_atlas_coords(tile_type)
		tilemap.set_cell(local_pos, 0, atlas_coords)


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
## Each tile gets full-square collision on physics layer 0 (World).
func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)  # Layer 1 = World
	ts.set_physics_layer_collision_mask(0, 0)

	# Determine how many tile types we have (skip EMPTY)
	var tile_types: Array = TileDatabase.tile_properties.keys()
	var atlas_width: int = tile_types.size()

	# Create the atlas image programmatically
	var img := Image.create(atlas_width * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)

	for i in range(tile_types.size()):
		var tile_type: int = tile_types[i]
		var color: Color = TileDatabase.get_properties(tile_type)["color"]
		var x_offset: int = i * TILE_SIZE
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				# Add subtle variation for visual interest
				var variation: float = (_hash_pixel(x_offset + x, y) - 0.5) * 0.1
				var c := Color(
					clampf(color.r + variation, 0.0, 1.0),
					clampf(color.g + variation, 0.0, 1.0),
					clampf(color.b + variation, 0.0, 1.0),
					1.0
				)
				img.set_pixel(x_offset + x, y, c)

	var tex := ImageTexture.create_from_image(img)

	# Create atlas source
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add to tileset FIRST (learned from M2 bug - must add source before creating tiles)
	ts.add_source(atlas, 0)

	# Create tiles and collision for each type
	var half: float = TILE_SIZE / 2.0
	var collision_polygon := PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])

	for i in range(tile_types.size()):
		var coords := Vector2i(i, 0)
		atlas.create_tile(coords)
		var tile_data: TileData = atlas.get_tile_data(coords, 0)
		# Water tiles have no collision so the player can pass through
		if tile_types[i] != TileDatabase.TileType.WATER:
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, collision_polygon)

	return ts


## Simple pixel-position hash for tile texture variation.
func _hash_pixel(x: int, y: int) -> float:
	var h: int = hash(Vector2i(x, y))
	return absf(float(h % 1000) / 1000.0)


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
	save_manager.save_world_meta(GameState.world_seed, player_pos, GameState.start_depth)

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

## Get the TileMapLayer for the chunk containing a world tile position.
## Returns null if the chunk is not currently loaded.
func get_tilemap_at(world_pos: Vector2i) -> TileMapLayer:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	return active_chunks.get(chunk_coord, null)


## Convert a pixel position to a tile coordinate.
func world_to_tile(pixel_pos: Vector2) -> Vector2i:
	return Vector2i(floori(pixel_pos.x / TILE_SIZE), floori(pixel_pos.y / TILE_SIZE))


## Convert a tile coordinate to the pixel position of its center.
func tile_to_world_center(tile_pos: Vector2i) -> Vector2:
	return Vector2(tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0, tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
