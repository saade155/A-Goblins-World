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
## Chunk data generation (expensive noise calculations) runs on a background thread.
## Visual creation (TileMapLayer population) runs on the main thread, up to 2 per frame.
## Look-ahead loading biases generation toward the player's movement direction.

extends Node2D
class_name ChunkManager

## Chunk size in tiles (must match WorldData.CHUNK_SIZE).
const CHUNK_SIZE: int = 32

## Tile size in pixels.
const TILE_SIZE: int = 16

## How many chunks to load in each direction from the player's chunk.
## Total loaded area = (2 * LOAD_RADIUS + 1)^2 chunks.
const LOAD_RADIUS: int = 5

## Maximum pending chunks to create visuals for per frame (main thread).
const VISUALS_PER_FRAME: int = 8

## Extra radius beyond LOAD_RADIUS before chunks are unloaded.
## Prevents rapid load/unload cycles when the player sits on a boundary.
const UNLOAD_BUFFER: int = 3

## Pixel size of a full chunk (CHUNK_SIZE * TILE_SIZE).
const PIXEL_CHUNK_SIZE: int = CHUNK_SIZE * TILE_SIZE  # 512

## Maximum light level (sunlight).
const MAX_LIGHT: int = 40
## Sunlight level (unobstructed sky).
const SUN_LIGHT: int = 40
## Torch light emission level.
const TORCH_LIGHT: int = 28
## Light reduction when passing through an air tile.
const AIR_REDUCTION: int = 2
## Light reduction when passing through a solid tile (sun + torches).
const SOLID_REDUCTION: int = 8
## Light reduction through solid tiles for player lantern (walls block harder).
const PLAYER_SOLID_REDUCTION: int = 14

## Z-index for the back wall tile layer (behind foreground).
const BACK_WALL_Z_INDEX: int = -10
## Z-index for the base tile layer.
const BASE_Z_INDEX: int = 0
## Z-index for the player character.
const PLAYER_Z_INDEX: int = 9
## Z-index for darkness overlay sprites (above terrain).
const DARKNESS_Z_INDEX: int = 11

## Z-index for torch sprites (above darkness overlay).
const TORCH_SPRITE_Z_INDEX: int = -1

## Autosave interval in seconds (10 minutes).
const AUTOSAVE_INTERVAL: float = 600.0

## Maximum number of rolling autosave snapshots to keep.
const MAX_AUTOSAVES: int = 5

## The authoritative world data.
var world_data: WorldData

## Procedural terrain generator.
var world_generator: WorldGenerator

## Structure placement system.
var structure_placer: StructurePlacer

## Active (loaded) chunks: chunk_coord (Vector2i) -> Dictionary of layer nodes.
## Each value is {"base": TileMapLayer}.
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

## Static light map (sun + torches). Key = world tile Vector2i, value = light level 0-20.
var static_light_map: Dictionary = {}
## Player dynamic light map. Key = world tile Vector2i, value = light level 0-20.
var player_light_map: Dictionary = {}
## Current player lantern light level (placeholder, will come from equipment later).
var _player_light_level: int = 28
## Last tile where player light was computed, to avoid redundant recalculation.
var _last_player_light_tile: Vector2i = Vector2i(999999, 999999)

## Saving overlay UI (small bottom-right indicator).
var _saving_overlay: CanvasLayer

## Full-tile collision polygon for tileset tiles.
var collision_polygon: PackedVector2Array

## Timer for periodic autosaves.
var _autosave_timer: Timer

## Whether this is the first frame (force-load all chunks synchronously).
var _first_load: bool = true

## Look-ahead chunk used for generation queue sorting (biased toward player velocity).
var _look_ahead_chunk: Vector2i = Vector2i(999999, 999999)

## Tracks player tile for fog-of-war darkness updates.
var _last_fog_player_tile: Vector2i = Vector2i(999999, 999999)

## Whether the current world gen is a save load (for loading overlay text).
var _is_loading_save: bool = false

## Whether world data was loaded from cache (skip dirty chunk overlay).
var _loaded_from_cache: bool = false

## Background thread for chunk data generation (noise calculations).
var _generation_thread: Thread = null

## Chunks whose data is ready and need visuals created on the main thread.
var _pending_visual_chunks: Array[Vector2i] = []

## Whether the background thread is currently generating chunk data.
var _thread_generating: bool = false

## The chunk coordinate currently being generated by the background thread.
var _thread_chunk: Vector2i

## Whether a finite world is being pre-generated on a background thread.
var _world_generating: bool = false

## Background thread for finite world pre-generation.
var _world_gen_thread: Thread = null

## Reference to loading overlay for progress updates during world generation.
var _loading_overlay = null

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
	var _is_existing_save: bool = false
	var meta = save_manager.load_world_meta()
	if meta != null:
		_is_existing_save = true
		GameState.world_seed = meta["world_seed"]
		GameState.start_depth = meta["start_depth"]
		GameState.world_display_name = meta.get("display_name", save_manager.world_name)
		GameState.world_size = meta.get("world_size", -1)

		# Load session state (position, inventory, playtime) from current/state.dat
		var state = save_manager.load_state()
		if state:
			var pos_x: float = state.get("player_position_x", 0.0)
			var pos_y: float = state.get("player_position_y", 0.0)
			if pos_x != 0.0 or pos_y != 0.0:
				GameState.saved_player_position = Vector2(pos_x, pos_y)
			GameState.playtime_seconds = state.get("playtime_seconds", 0.0)

		print("[ChunkManager] Loaded world save. Seed: %d, world_size: %d" % [GameState.world_seed, GameState.world_size])
	else:
		# New world — write immutable metadata once
		save_manager.save_world_meta(GameState.world_seed, GameState.start_depth, GameState.world_display_name, GameState.world_size)

	# Initialize systems
	world_data = WorldData.new()
	world_generator = WorldGenerator.new(GameState.world_seed)
	structure_placer = StructurePlacer.new()

	# Configure finite world bounds if applicable
	var ws: int = GameState.world_size
	if ws >= 0:
		world_data.set_world_size(ws)
		print("[ChunkManager] Finite world configured: %dx%d tiles (size preset %d)" % [world_data.world_width, world_data.world_height, ws])

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
	GameServer.back_wall_mined.connect(_on_back_wall_mined)
	GameServer.back_wall_placed.connect(_on_back_wall_placed)

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
	save_manager.load_skill_data(SkillSystem)

	# Load fog of war data (explored tiles) if save exists
	var fog_data: Dictionary = save_manager.load_fog_data()
	if not fog_data.is_empty():
		ExplorationTracker.explored_tiles = fog_data
		print("[ChunkManager] Fog data loaded: %d explored tiles" % fog_data.size())

	# Intercept window close to save before quitting
	get_tree().set_auto_accept_quit(false)

	# Start autosave timer (10-minute rolling snapshots)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.one_shot = false
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)
	_autosave_timer.start()

	# Saving overlay (non-blocking bottom-right indicator)
	_saving_overlay = preload("res://scenes/ui/saving_overlay.tscn").instantiate()
	add_child(_saving_overlay)

	# For finite worlds, try loading the world cache first (skips regeneration).
	# If no cache exists (new world or first load), generate from seed and cache.
	if ws >= 0:
		if not _is_existing_save and world_data.world_width > 0:
			@warning_ignore("integer_division")
			var center_x: int = world_data.world_width / 2
			GameState.saved_player_position = Vector2(center_x * TILE_SIZE, GameState.start_depth * TILE_SIZE)

		# Try loading cached world data (skips regeneration)
		var cache = save_manager.load_world_cache()
		if cache != null:
			world_data.tiles = cache["tiles"]
			world_data.back_wall_tiles = cache["back_wall_tiles"]
			world_data.torches = cache["torches"]
			_loaded_from_cache = true
			# Signal that world data is ready — skip to chunk loading
			_first_load = true
			# Show loading overlay
			_loading_overlay = get_tree().current_scene.get_node_or_null("LoadingOverlay")
			if _loading_overlay:
				_loading_overlay.set_progress_text("Loading chunks...")
			print("[ChunkManager] World loaded from cache, skipping generation.")
			_recompute_static_light()
		else:
			_start_world_generation(_is_existing_save)


func _start_world_generation(is_loading_save: bool = false) -> void:
	## Kick off background thread to pre-generate all tiles for a finite world.
	## The loading overlay shows progress; _process() polls for completion.
	_world_generating = true
	_is_loading_save = is_loading_save

	# Find the loading overlay in the scene tree and update its text
	_loading_overlay = get_tree().current_scene.get_node_or_null("LoadingOverlay")
	if _loading_overlay:
		var label: String = "Loading world... 0%" if is_loading_save else "Generating world... 0%"
		_loading_overlay.set_progress_text(label)

	_world_gen_thread = Thread.new()
	_world_gen_thread.start(world_generator.generate_world.bind(world_data))
	print("[ChunkManager] Finite world generation started on background thread.")


func _process(_delta: float) -> void:
	# Poll for finite world generation completion
	if _world_generating:
		# Hold player in place during generation (no collision exists yet)
		if GameState.player:
			GameState.player.velocity = Vector2.ZERO
			if GameState.saved_player_position != null:
				GameState.player.global_position = GameState.saved_player_position
		if world_generator.generation_complete:
			_world_generating = false
			if _world_gen_thread:
				_world_gen_thread.wait_to_finish()
				_world_gen_thread = null
			# Cache the generated world for fast future loads
			save_manager.save_world_cache(world_data)
			print("[ChunkManager] Finite world generation complete.")
			print("[ChunkManager] World data tiles: %d" % world_data.tiles.size())
			_recompute_static_light()
			# Reset player to intended spawn (they may have drifted during generation)
			if GameState.player and GameState.saved_player_position != null:
				GameState.player.global_position = GameState.saved_player_position
				GameState.player.velocity = Vector2.ZERO
			# Update loading overlay text — the normal initial_load_complete signal
			# will hide it after chunk visuals are created.
			if _loading_overlay and _loading_overlay.has_method("set_progress_text"):
				_loading_overlay.set_progress_text("Loading chunks...")
			# Reset first_load so the next frame with a player triggers synchronous
			# chunk loading behind the loading screen.
			_first_load = true
		else:
			# Update loading overlay with progress percentage
			if _loading_overlay and _loading_overlay.has_method("set_progress_text"):
				var pct: int = int(world_generator.get_generation_progress() * 100.0)
				var label: String = "Loading world... %d%%" % pct if _is_loading_save else "Generating world... %d%%" % pct
				_loading_overlay.set_progress_text(label)
		return  # Don't do normal chunk processing while generating

	if not GameState.player:
		return

	var player_pos: Vector2 = GameState.player.global_position
	var player_chunk := Vector2i(
		floori(player_pos.x / PIXEL_CHUNK_SIZE),
		floori(player_pos.y / PIXEL_CHUNK_SIZE)
	)

	# Look-ahead: bias chunk loading toward player movement direction
	var player_velocity: Vector2 = Vector2.ZERO
	if GameState.player is CharacterBody2D:
		player_velocity = GameState.player.velocity
	var look_ahead_pos: Vector2 = player_pos + player_velocity * 1.5  # 1.5 seconds ahead
	_look_ahead_chunk = Vector2i(
		floori(look_ahead_pos.x / PIXEL_CHUNK_SIZE),
		floori(look_ahead_pos.y / PIXEL_CHUNK_SIZE)
	)

	if player_chunk != current_player_chunk:
		current_player_chunk = player_chunk
		_update_loaded_chunks()

	# Process generation queue
	if _first_load:
		# Force-load all chunks synchronously on first frame (no pop-in on game load).
		# This runs behind the loading screen so stutter doesn't matter.
		# Re-pin player position — physics may have drifted them during the
		# frame gap between world gen completing and chunks being created.
		if GameState.player and GameState.saved_player_position != null:
			GameState.player.global_position = GameState.saved_player_position
			GameState.player.velocity = Vector2.ZERO
		# Phase 1: Generate all chunk data first (so neighbors exist)
		for chunk_coord in chunks_to_generate:
			if _is_chunk_needed(chunk_coord):
				_generate_chunk_data(chunk_coord)
		# Phase 2: Create visuals
		while chunks_to_generate.size() > 0:
			var chunk_coord: Vector2i = chunks_to_generate.pop_front()
			if _is_chunk_needed(chunk_coord):
				_create_chunk_visuals(chunk_coord)
		_first_load = false
		initial_load_complete.emit()
	else:
		# Finite worlds: data already exists in world_data.tiles, so skip threading
		# and generate chunk data synchronously (near-instant). This avoids the
		# expensive OS Thread creation overhead that bottlenecks chunk loading.
		if world_data.world_width > 0:
			while not chunks_to_generate.is_empty():
				var next_chunk: Vector2i = chunks_to_generate.pop_front()
				if _is_chunk_needed(next_chunk) and not generated_chunks.has(next_chunk):
					_generate_chunk_data(next_chunk)
					_pending_visual_chunks.append(next_chunk)
		else:
			# Infinite/legacy worlds: threaded generation (noise is expensive).
			# Step 1: Check if background thread finished generating data
			if _thread_generating and _generation_thread != null and not _generation_thread.is_alive():
				_generation_thread.wait_to_finish()
				_thread_generating = false
				_pending_visual_chunks.append(_thread_chunk)

			# Step 2: Start next thread if idle and queue has work
			if not _thread_generating and not chunks_to_generate.is_empty():
				var next_chunk: Vector2i = chunks_to_generate.pop_front()
				if _is_chunk_needed(next_chunk) and not generated_chunks.has(next_chunk):
					_thread_chunk = next_chunk
					_generation_thread = Thread.new()
					_thread_generating = true
					_generation_thread.start(_threaded_generate_chunk.bind(_thread_chunk))

		# Create visuals for ready chunks (main thread only)
		var visuals_this_frame: int = 0
		while not _pending_visual_chunks.is_empty() and visuals_this_frame < VISUALS_PER_FRAME:
			var cc: Vector2i = _pending_visual_chunks.pop_front()
			if _is_chunk_needed(cc):
				_create_chunk_visuals(cc)
			visuals_this_frame += 1

	# Track max depth for BehaviorTracker
	_update_depth_tracking()

	# Fog of war: update darkness when player moves to a new tile
	var player_tile := Vector2i(
		floori(player_pos.x / float(TILE_SIZE)),
		floori(player_pos.y / float(TILE_SIZE))
	)
	if player_tile != _last_fog_player_tile:
		_last_fog_player_tile = player_tile
		# Recompute player dynamic light when tile changes
		_update_player_light(player_tile)
		_update_fog_darkness()

	# Poll for background save completion
	var save_result: Dictionary = save_manager.check_save_complete()
	if not save_result.is_empty():
		print("[ChunkManager] Snapshot complete: %s (success: %s)" % [save_result.save_name, str(save_result.success)])
		_saving_overlay.hide_saving()


# --- Chunk loading / unloading ---

## Determine which chunks should be loaded/unloaded based on player position.
func _update_loaded_chunks() -> void:
	var needed_chunks: Dictionary = {}  # Used as a set

	# Determine which chunks should be loaded (skip fully out-of-bounds chunks)
	for x in range(current_player_chunk.x - LOAD_RADIUS, current_player_chunk.x + LOAD_RADIUS + 1):
		for y in range(current_player_chunk.y - LOAD_RADIUS, current_player_chunk.y + LOAD_RADIUS + 1):
			var cc := Vector2i(x, y)
			if _is_chunk_in_world(cc):
				needed_chunks[cc] = true

	# Unload chunks outside LOAD_RADIUS + UNLOAD_BUFFER (hysteresis to avoid rapid load/unload cycles)
	var unload_radius: int = LOAD_RADIUS + UNLOAD_BUFFER
	var to_unload: Array[Vector2i] = []
	for chunk_coord in active_chunks:
		var diff: Vector2i = (chunk_coord - current_player_chunk).abs()
		if diff.x > unload_radius or diff.y > unload_radius:
			to_unload.append(chunk_coord)

	for chunk_coord in to_unload:
		_unload_chunk(chunk_coord)

	# Queue chunks that need loading
	for chunk_coord in needed_chunks:
		if not active_chunks.has(chunk_coord):
			if not chunks_to_generate.has(chunk_coord):
				chunks_to_generate.append(chunk_coord)

	# Sort by distance to look-ahead chunk (biased toward player velocity)
	var sort_target: Vector2i = _look_ahead_chunk
	chunks_to_generate.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(sort_target) < b.distance_squared_to(sort_target)
	)


## Thread entry point for background chunk data generation.
## Only performs data operations (noise, save loading) — no scene tree access.
func _threaded_generate_chunk(chunk_coord: Vector2i) -> void:
	_generate_chunk_data(chunk_coord)


## Check if a chunk is within the load radius of the current player chunk.
func _is_chunk_needed(chunk_coord: Vector2i) -> bool:
	var diff: Vector2i = (chunk_coord - current_player_chunk).abs()
	return diff.x <= LOAD_RADIUS and diff.y <= LOAD_RADIUS


## Check if any tile in a 32x32 chunk falls within finite world bounds.
## Returns true for infinite/legacy worlds (no bounds set).
func _is_chunk_in_world(chunk_coord: Vector2i) -> bool:
	if world_data.world_width == 0:
		return true  # No bounds set (legacy/infinite)
	# Check if any corner of the chunk overlaps the world rectangle,
	# expanded by 1 chunk on each side to create DEEP_ROCK boundary walls.
	var origin: Vector2i = WorldData.chunk_to_world(chunk_coord)
	var chunk_min_x: int = origin.x
	var chunk_max_x: int = origin.x + CHUNK_SIZE - 1
	var chunk_min_y: int = origin.y
	var chunk_max_y: int = origin.y + CHUNK_SIZE - 1
	var world_min_x: int = -CHUNK_SIZE
	var world_max_x: int = world_data.world_width + CHUNK_SIZE - 1
	var world_min_y: int = -world_data.surface_rows - CHUNK_SIZE
	var world_max_y: int = world_data.world_height - world_data.surface_rows + CHUNK_SIZE - 1
	# AABB overlap test
	if chunk_max_x < world_min_x or chunk_min_x > world_max_x:
		return false
	if chunk_max_y < world_min_y or chunk_min_y > world_max_y:
		return false
	return true


## Generate chunk data (load from save or generate from seed) without creating visuals.
## Safe to call multiple times; skips if data already exists.
## For finite worlds, tiles are pre-generated in world_data.tiles so we only need
## to check for saved player modifications and apply structure overrides.
func _generate_chunk_data(chunk_coord: Vector2i) -> void:
	if generated_chunks.has(chunk_coord):
		return

	# Skip chunks entirely outside the world bounds
	if not _is_chunk_in_world(chunk_coord):
		generated_chunks[chunk_coord] = true
		return

	# When loaded from cache, world_data already has correct tiles (including
	# player modifications). Skip dirty chunk loading and structure application.
	if _loaded_from_cache:
		pass  # Tiles, back walls, and torches already correct in world_data
	else:
		# Check for saved chunk first (player-modified chunks saved to disk)
		var saved_data = save_manager.load_chunk(chunk_coord)
		if saved_data != null:
			world_data.set_chunk_tiles(chunk_coord, saved_data["tiles"])
			# Restore back walls from save
			if saved_data.has("back_walls"):
				world_data.set_chunk_back_walls(chunk_coord, saved_data["back_walls"])
			# Restore torches
			for tpos in saved_data["torches"]:
				world_data.torches[tpos] = true
			world_data.dirty_chunks[chunk_coord] = true
		elif world_data.world_width > 0:
			# Finite world: tiles were pre-generated by generate_world().
			# Back walls are already in world_data.back_wall_tiles from generate_world().
			# Just apply structure overrides (spawn chamber, etc.)
			_apply_structure_tiles_to_chunk(chunk_coord)
		else:
			# Legacy infinite world: generate fresh from seed
			var chunk_data: Dictionary = world_generator.generate_chunk(chunk_coord)
			world_data.set_chunk_tiles(chunk_coord, chunk_data["tiles"])
			world_data.set_chunk_back_walls(chunk_coord, chunk_data["back_walls"])
			_apply_structure_tiles_to_chunk(chunk_coord)
	generated_chunks[chunk_coord] = true


## Create the visual TileMapLayer for a chunk whose data already exists.
## Spawns torches and creates the darkness overlay.
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

	# Create back wall TileMapLayer for this chunk
	var back_wall_tilemap := TileMapLayer.new()
	back_wall_tilemap.name = "BackWall_%d_%d" % [chunk_coord.x, chunk_coord.y]
	back_wall_tilemap.tile_set = shared_tileset
	back_wall_tilemap.position = Vector2(chunk_coord.x * PIXEL_CHUNK_SIZE, chunk_coord.y * PIXEL_CHUNK_SIZE)
	back_wall_tilemap.collision_enabled = false  # Back walls don't block movement
	back_wall_tilemap.z_index = BACK_WALL_Z_INDEX
	back_wall_tilemap.modulate = Color(0.55, 0.55, 0.55)  # Darker to distinguish from foreground

	# Populate back wall tilemap from world data
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var wpos: Vector2i = origin + Vector2i(x, y)
			var wall_type: int = world_data.get_back_wall(wpos)
			if wall_type != 0:
				var visual: Dictionary = _get_tile_visual(wpos, wall_type)
				back_wall_tilemap.set_cell(Vector2i(x, y), visual["source_id"], visual["atlas_coords"])

	add_child(back_wall_tilemap)

	active_chunks[chunk_coord] = {"base": tilemap, "back_wall": back_wall_tilemap}

	chunk_loaded.emit(chunk_coord)

	# Spawn torches for this chunk
	var torch_positions: Array = world_data.get_chunk_torches(chunk_coord)
	for tpos in torch_positions:
		_spawn_torch(tpos)

	# Create per-tile darkness overlay for this chunk
	_create_darkness_overlay(chunk_coord)


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


## Get the back wall TileMapLayer for a chunk.
func _get_back_wall_tilemap(chunk_coord: Vector2i) -> TileMapLayer:
	var chunk_data: Dictionary = active_chunks.get(chunk_coord, {})
	return chunk_data.get("back_wall", null)


# --- Structure placement ---

## Place the spawn chamber structure tiles. These will be applied on top of
## generated terrain when chunks around the origin are first created.
func _place_spawn_chamber() -> void:
	var spawn_data: Dictionary = StructurePlacer.create_spawn_chamber()
	var spawn_y: int = GameState.start_depth - 5  # Chamber wraps around player
	var spawn_x: int = -8  # Default for legacy infinite worlds
	if world_data.world_width > 0:
		@warning_ignore("integer_division")
		spawn_x = world_data.world_width / 2 - 8  # Center in finite world
	var spawn_pos := Vector2i(spawn_x, spawn_y)
	var tiles: Dictionary = spawn_data["tiles"]

	for local_pos in tiles:
		var wpos: Vector2i = spawn_pos + local_pos
		structure_tiles[wpos] = tiles[local_pos]

	print("[ChunkManager] Spawn chamber registered at tile (%d, %d) (start_depth=%d)" % [
		spawn_pos.x, spawn_pos.y, GameState.start_depth])


## Apply structure tile overrides to a chunk after terrain generation.
## Overwrites generated foreground tiles with structure data, including EMPTY to carve.
## Back walls are preserved — carved rooms should show the rock behind them.
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

	# Update neighbor visuals (refresh their cell visual)
	_update_neighbor_visuals(world_pos)

	# Update fog darkness (fast — only chunks around player)
	_update_fog_darkness()
	# Localized light recompute (fast — only ~2000 tiles around mined tile)
	_recompute_light_local(world_pos)
	_update_player_light(_last_fog_player_tile)


## Called when a tile is placed via GameServer. Update the visual tilemap.
func _on_tile_placed(world_pos: Vector2i, tile_type: int) -> void:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	var base_tilemap: TileMapLayer = _get_base_tilemap(chunk_coord)
	if base_tilemap:
		var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
		var visual: Dictionary = _get_tile_visual(world_pos, tile_type)
		base_tilemap.set_cell(local_pos, visual["source_id"], visual["atlas_coords"])

	# Update neighbor visuals
	_update_neighbor_visuals(world_pos)

	_recompute_light_local(world_pos)
	_update_player_light(_last_fog_player_tile)


## Called when a back wall is mined via GameServer. Update visuals and spawn a drop.
func _on_back_wall_mined(world_pos: Vector2i, tile_type: int) -> void:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	var back_wall_tilemap: TileMapLayer = _get_back_wall_tilemap(chunk_coord)
	if back_wall_tilemap:
		var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
		back_wall_tilemap.erase_cell(local_pos)

	# Spawn dropped item for the mined back wall
	_spawn_dropped_item(world_pos, tile_type)

	_update_fog_darkness()
	_recompute_light_local(world_pos)
	_update_player_light(_last_fog_player_tile)


## Called when a back wall is placed via GameServer. Update visuals.
func _on_back_wall_placed(world_pos: Vector2i, tile_type: int) -> void:
	var chunk_coord: Vector2i = WorldData.world_to_chunk(world_pos)
	var back_wall_tilemap: TileMapLayer = _get_back_wall_tilemap(chunk_coord)
	if back_wall_tilemap:
		var local_pos: Vector2i = world_pos - WorldData.chunk_to_world(chunk_coord)
		var visual: Dictionary = _get_tile_visual(world_pos, tile_type)
		back_wall_tilemap.set_cell(local_pos, visual["source_id"], visual["atlas_coords"])

	_update_player_light(_last_fog_player_tile)


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

	# Source ID 0: Programmatic colored tiles
	_add_programmatic_atlas(ts)

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


## Simple pixel-position hash for tile texture variation.
func _hash_pixel(x: int, y: int) -> float:
	var h: int = hash(Vector2i(x, y))
	return absf(float(h % 1000) / 1000.0)


# --- Tile visuals ---

## Get the visual source_id and atlas_coords for a tile at a world position.
## Always uses the programmatic colored atlas (source 0).
func _get_tile_visual(_world_pos: Vector2i, tile_type: int) -> Dictionary:
	return {
		"source_id": 0,
		"atlas_coords": TileDatabase.get_atlas_coords(tile_type),
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


# --- Per-tile lighting ---

## Flood sunlight downward through all air columns. Any air tile with clear sky
## above gets SUN_LIGHT (20). Stops at the first solid tile per column.
func _compute_sunlight() -> void:
	var sr: int = world_data.surface_rows
	var w: int = world_data.world_width
	var h: int = world_data.world_height
	for wx in range(w):
		# Scan downward from above the surface through air
		for wy in range(-sr, h - sr):
			var pos := Vector2i(wx, wy)
			if world_data.has_tile(pos):
				break  # Hit solid ground, stop this column
			static_light_map[pos] = SUN_LIGHT


## BFS propagation of static light (sunlight + torches) into walls and through air.
## Air tiles reduce light by AIR_REDUCTION (1), solid tiles by SOLID_REDUCTION (5).
func _propagate_static_light() -> void:
	# Initialize BFS queue with all existing light sources
	var queue: Array[Vector2i] = []

	# Add all sunlit tiles (already in static_light_map from _compute_sunlight)
	for pos in static_light_map:
		queue.append(pos)

	# Add torch sources
	for torch_pos in world_data.torches:
		var current: int = static_light_map.get(torch_pos, 0)
		if TORCH_LIGHT > current:
			static_light_map[torch_pos] = TORCH_LIGHT
			queue.append(torch_pos)

	# BFS propagation
	var neighbors := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var idx: int = 0
	while idx < queue.size():
		var pos: Vector2i = queue[idx]
		idx += 1
		var current_level: int = static_light_map.get(pos, 0)
		if current_level <= 1:
			continue  # Can't propagate further
		for offset in neighbors:
			var neighbor: Vector2i = pos + offset
			var is_solid: bool = world_data.has_tile(neighbor)
			var reduction: int = SOLID_REDUCTION if is_solid else AIR_REDUCTION
			var new_level: int = current_level - reduction
			if new_level > 0 and new_level > static_light_map.get(neighbor, 0):
				static_light_map[neighbor] = new_level
				queue.append(neighbor)


## Recompute player dynamic light via BFS from the player's tile position.
## Uses the same propagation rules as static light (air -1, solid -5).
func _update_player_light(tile_pos: Vector2i) -> void:
	player_light_map.clear()
	if _player_light_level <= 0:
		return
	player_light_map[tile_pos] = _player_light_level
	var queue: Array[Vector2i] = [tile_pos]
	var neighbors := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var idx: int = 0
	while idx < queue.size():
		var pos: Vector2i = queue[idx]
		idx += 1
		var current_level: int = player_light_map.get(pos, 0)
		if current_level <= 1:
			continue
		for offset in neighbors:
			var neighbor: Vector2i = pos + offset
			var is_solid: bool = world_data.has_tile(neighbor)
			var reduction: int = PLAYER_SOLID_REDUCTION if is_solid else AIR_REDUCTION
			var new_level: int = current_level - reduction
			if new_level > 0 and new_level > player_light_map.get(neighbor, 0):
				player_light_map[neighbor] = new_level
				queue.append(neighbor)
	_last_player_light_tile = tile_pos


## Recompute light in a localized area around a tile change.
## Much faster than _recompute_static_light() — processes ~2000 tiles instead of 60,000+.
## Used for gameplay events (mining, placing, torches). Full recompute reserved for init.
func _recompute_light_local(center: Vector2i) -> void:
	var RADIUS := 22  # MAX_LIGHT / AIR_REDUCTION + 2 margin
	var min_x := center.x - RADIUS
	var max_x := center.x + RADIUS
	var min_y := center.y - RADIUS
	var max_y := center.y + RADIUS

	# Step 1: Clear light in local area
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			static_light_map.erase(Vector2i(x, y))

	# Step 2: Reseed sunlight in local columns (scan from sky down)
	var sr: int = world_data.surface_rows
	var wh: int = world_data.world_height
	for wx in range(min_x, max_x + 1):
		for wy in range(-sr, wh - sr):
			var pos := Vector2i(wx, wy)
			if world_data.has_tile(pos):
				break  # Hit solid — sunlight blocked in this column
			if pos.y >= min_y and pos.y <= max_y:
				static_light_map[pos] = SUN_LIGHT

	# Step 3: Build BFS queue from seeds
	var queue: Array[Vector2i] = []

	# Seed from sunlit tiles we just placed in the local area
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var pos := Vector2i(x, y)
			if static_light_map.has(pos):
				queue.append(pos)

	# Seed from torches that could contribute light to the local area
	for torch_pos in world_data.torches:
		if torch_pos.x >= min_x and torch_pos.x <= max_x \
				and torch_pos.y >= min_y and torch_pos.y <= max_y:
			var current: int = static_light_map.get(torch_pos, 0)
			if TORCH_LIGHT > current:
				static_light_map[torch_pos] = TORCH_LIGHT
				queue.append(torch_pos)

	# Seed from boundary ring (light flowing in from outside the cleared area)
	for x in range(min_x - 1, max_x + 2):
		for border_y in [min_y - 1, max_y + 1]:
			var pos := Vector2i(x, border_y)
			if static_light_map.get(pos, 0) > 0:
				queue.append(pos)
	for y in range(min_y, max_y + 1):
		for border_x in [min_x - 1, max_x + 1]:
			var pos := Vector2i(border_x, y)
			if static_light_map.get(pos, 0) > 0:
				queue.append(pos)

	# Step 4: BFS propagation (same algorithm as _propagate_static_light)
	var neighbors := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var idx: int = 0
	while idx < queue.size():
		var pos: Vector2i = queue[idx]
		idx += 1
		var current_level: int = static_light_map.get(pos, 0)
		if current_level <= 1:
			continue
		for offset in neighbors:
			var neighbor: Vector2i = pos + offset
			var is_solid: bool = world_data.has_tile(neighbor)
			var reduction: int = SOLID_REDUCTION if is_solid else AIR_REDUCTION
			var new_level: int = current_level - reduction
			if new_level > 0 and new_level > static_light_map.get(neighbor, 0):
				static_light_map[neighbor] = new_level
				queue.append(neighbor)

	# Step 5: Update darkness textures for affected chunks only
	var min_chunk := WorldData.world_to_chunk(Vector2i(min_x, min_y))
	var max_chunk := WorldData.world_to_chunk(Vector2i(max_x, max_y))
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var cc := Vector2i(cx, cy)
			if chunk_darkness_sprites.has(cc):
				_update_chunk_lighting(cc)


## Full recomputation of static light map (sunlight + torches).
func _recompute_static_light() -> void:
	static_light_map.clear()
	_compute_sunlight()
	_propagate_static_light()


## Get the combined light level at a world position (0-20).
## Used by gameplay systems (mob spawning, etc.).
func get_light_level(world_pos: Vector2i) -> int:
	return maxi(static_light_map.get(world_pos, 0), player_light_map.get(world_pos, 0))


## Create a darkness overlay Sprite2D for a chunk. The image is 34x34 (32 + 1px
## border on each side) so LINEAR filtering has correct neighbor data at chunk
## edges, eliminating visible seams between adjacent chunks.
func _create_darkness_overlay(chunk_coord: Vector2i) -> void:
	var img := Image.create(CHUNK_SIZE + 2, CHUNK_SIZE + 2, false, Image.FORMAT_RGBA8)
	_update_darkness_image(chunk_coord, img)

	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.z_index = DARKNESS_Z_INDEX
	sprite.region_enabled = true
	sprite.region_rect = Rect2(1, 1, CHUNK_SIZE, CHUNK_SIZE)
	sprite.scale = Vector2(TILE_SIZE, TILE_SIZE)
	sprite.position = Vector2(
		chunk_coord.x * PIXEL_CHUNK_SIZE,
		chunk_coord.y * PIXEL_CHUNK_SIZE
	)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	chunk_darkness_sprites[chunk_coord] = sprite


## Fill a 34x34 image with darkness alpha values from precomputed BFS light maps.
## The image has a 1-pixel border around the 32x32 chunk data so that LINEAR
## texture filtering can interpolate correctly at chunk boundaries.
## Reads combined light level from static_light_map (sun + torches) and
## player_light_map (dynamic lantern). Fog of war is still applied: unexplored
## tiles are fully black regardless of light level.
func _update_darkness_image(chunk_coord: Vector2i, img: Image) -> void:
	var origin: Vector2i = WorldData.chunk_to_world(chunk_coord)
	var img_size: int = CHUNK_SIZE + 2
	for ix in range(img_size):
		for iy in range(img_size):
			var wx: int = origin.x + ix - 1
			var wy: int = origin.y + iy - 1
			var wt := Vector2i(wx, wy)
			# Fog of war: unexplored tiles are fully black
			if not ExplorationTracker.is_tile_explored(wt):
				img.set_pixel(ix, iy, Color(0.0, 0.0, 0.0, 1.0))
				continue
			# Read combined light level from precomputed maps
			var level: int = maxi(
				static_light_map.get(wt, 0),
				player_light_map.get(wt, 0)
			)
			var darkness: float = 1.0 - clampf(float(level) / float(MAX_LIGHT), 0.0, 1.0)
			img.set_pixel(ix, iy, Color(0.0, 0.0, 0.0, darkness))


## Update the darkness overlay for an already-loaded chunk.
func _update_chunk_lighting(chunk_coord: Vector2i) -> void:
	if not chunk_darkness_sprites.has(chunk_coord):
		return
	var sprite: Sprite2D = chunk_darkness_sprites[chunk_coord]
	var tex: ImageTexture = sprite.texture as ImageTexture
	var img: Image = tex.get_image()
	_update_darkness_image(chunk_coord, img)
	tex.update(img)


## Update darkness overlays for chunks near the player to reflect newly explored tiles.
## Called when the player moves. Uses a wider radius on the surface for daylight.
func _update_fog_darkness() -> void:
	if not GameState.player:
		return
	var radius: int = ExplorationTracker.REVEAL_RADIUS + 2
	# Use wider radius on surface so daylight-explored chunks update their darkness
	if _last_fog_player_tile.y <= 5:
		radius = ExplorationTracker.SURFACE_REVEAL_RADIUS + 2
	var player_tile := _last_fog_player_tile
	var min_chunk := WorldData.world_to_chunk(Vector2i(player_tile.x - radius, player_tile.y - radius))
	var max_chunk := WorldData.world_to_chunk(Vector2i(player_tile.x + radius, player_tile.y + radius))
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var cc := Vector2i(cx, cy)
			if chunk_darkness_sprites.has(cc):
				_update_chunk_lighting(cc)


## Recalculate lighting for all loaded chunks affected by a light change.
## Uses MAX_LIGHT as the search radius since BFS light can propagate that far
## through air (1 reduction per tile).
func _recalculate_lighting_around(world_pos: Vector2i) -> void:
	var min_chunk := WorldData.world_to_chunk(Vector2i(world_pos.x - MAX_LIGHT, world_pos.y - MAX_LIGHT))
	var max_chunk := WorldData.world_to_chunk(Vector2i(world_pos.x + MAX_LIGHT, world_pos.y + MAX_LIGHT))
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var cc := Vector2i(cx, cy)
			if active_chunks.has(cc):
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

## Flush all dirty chunks to current/ on disk. Does not save state or behavior.
func _save_dirty_chunks() -> void:
	for chunk_coord in active_chunks:
		if world_data.is_chunk_dirty(chunk_coord):
			save_manager.save_chunk(chunk_coord, world_data)
			world_data.dirty_chunks[chunk_coord] = false


## Save all world data and session state. Called before game exit.
func save_all() -> void:
	_save_dirty_chunks()

	# Update world cache with current state (includes player modifications)
	if world_data.world_width > 0:
		save_manager.save_world_cache(world_data)

	# Save session state (player position, inventory, playtime)
	var player_pos = null
	if GameState.player:
		player_pos = GameState.player.global_position
	elif GameState.saved_player_position != null:
		player_pos = GameState.saved_player_position

	# Only save state if we have a valid position — don't overwrite a good save with zero
	if player_pos == null:
		print("[ChunkManager] save_all: No valid player position — skipping state save.")
	else:
		save_manager.save_state(player_pos, GameState.get_total_playtime())

	# Save behavior tracker data
	save_manager.save_behavior_data(BehaviorTracker)
	save_manager.save_skill_data(SkillSystem)

	# Save fog of war data (explored tiles)
	save_manager.save_fog_data(ExplorationTracker.explored_tiles)

	print("[ChunkManager] All data saved.")


## Called when the autosave timer fires. Creates a rolling autosave snapshot.
func _on_autosave_timeout() -> void:
	if save_manager.is_saving():
		return  # Skip this tick, will try again next interval

	# Flush dirty chunks synchronously (they're small, writes to current/)
	_save_dirty_chunks()
	save_manager.save_behavior_data(BehaviorTracker)
	save_manager.save_skill_data(SkillSystem)
	save_manager.save_fog_data(ExplorationTracker.explored_tiles)

	# Rotate old autosaves to stay under the limit
	save_manager.rotate_autosaves(MAX_AUTOSAVES)

	# Timestamp-based autosave name (naturally sortable, no collision)
	var save_name: String = "auto_%s" % Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")

	# Get player position
	var player_pos: Vector2 = GameState.player.global_position if GameState.player else Vector2.ZERO

	# Launch threaded snapshot
	save_manager.create_snapshot(save_name, "autosave", player_pos, GameState.get_total_playtime())
	_saving_overlay.show_saving()
	print("[ChunkManager] Autosave started: %s" % save_name)


## Create a manual save snapshot with the given name.
func create_save(save_name: String, reason: String = "manual") -> void:
	if save_manager.is_saving():
		push_warning("[ChunkManager] Save already in progress")
		return
	_save_dirty_chunks()
	save_manager.save_behavior_data(BehaviorTracker)
	save_manager.save_skill_data(SkillSystem)
	var player_pos: Vector2 = GameState.player.global_position if GameState.player else Vector2.ZERO
	save_manager.create_snapshot(save_name, reason, player_pos, GameState.get_total_playtime())
	_saving_overlay.show_saving()


## Programmatic hook for event-triggered saves (future use by combat/exploration systems).
func request_autosave(reason: String) -> void:
	if save_manager.is_saving():
		return
	_save_dirty_chunks()
	save_manager.save_behavior_data(BehaviorTracker)
	save_manager.save_skill_data(SkillSystem)
	save_manager.rotate_autosaves(MAX_AUTOSAVES)
	var save_name: String = "auto_%s" % Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var player_pos: Vector2 = GameState.player.global_position if GameState.player else Vector2.ZERO
	save_manager.create_snapshot(save_name, reason, player_pos, GameState.get_total_playtime())
	_saving_overlay.show_saving()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Wait for world generation thread if running
		if _world_gen_thread != null and _world_generating:
			_world_gen_thread.wait_to_finish()
			_world_generating = false
			_world_gen_thread = null
		# Wait for chunk generation thread if running
		if _generation_thread != null and _thread_generating:
			_generation_thread.wait_to_finish()
			_thread_generating = false
		# If a background snapshot is running, wait for it to finish first.
		if save_manager.is_saving():
			var result: Dictionary = save_manager.check_save_complete()
			while result.is_empty():
				OS.delay_msec(10)
				result = save_manager.check_save_complete()
		save_all()
		get_tree().quit()
	elif what == NOTIFICATION_EXIT_TREE:
		# Clean up world generation thread
		if _world_gen_thread != null and _world_generating:
			_world_gen_thread.wait_to_finish()
			_world_generating = false
			_world_gen_thread = null
		# Clean up chunk generation thread when removed from scene tree
		if _generation_thread != null and _thread_generating:
			_generation_thread.wait_to_finish()
			_thread_generating = false


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
	_recompute_light_local(world_pos)
	_update_player_light(_last_fog_player_tile)


## Called when GameServer confirms a torch was removed.
func _on_torch_removed(world_pos: Vector2i) -> void:
	_remove_torch(world_pos)
	_recompute_light_local(world_pos)
	_update_player_light(_last_fog_player_tile)


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
