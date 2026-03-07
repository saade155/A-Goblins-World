## ChunkManager - Core orchestrator for tile-based procedural world.
##
## Manages the visual representation and lighting of a finite tile world.
## All tile visuals are loaded at once during the loading screen using
## two global TileMapLayers (foreground and back wall). Godot handles
## viewport culling internally. The manager:
##   1. Populates all tile visuals during loading (with progress bar)
##   2. Handles tile visual updates when GameServer emits mine/place signals
##   3. Manages darkness overlays spatially around the player
##   4. Spawns dropped items and torches
##   5. Applies depth-based ambient lighting

extends Node2D
class_name ChunkManager

## Slope direction enum for tile shape modifiers.
enum SlopeDir { FLOOR_RIGHT, FLOOR_LEFT, CEIL_RIGHT, CEIL_LEFT, NONE = -1 }

## Chunk size in tiles (must match WorldData.CHUNK_SIZE).
const CHUNK_SIZE: int = 32

## Tile size in pixels.
const TILE_SIZE: int = 16

## Pixel size of a full chunk (CHUNK_SIZE * TILE_SIZE).
const PIXEL_CHUNK_SIZE: int = CHUNK_SIZE * TILE_SIZE  # 512

## Radius of darkness overlay chunks to maintain around the player.
const DARKNESS_RADIUS: int = 6

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

## The shared TileSet used by all chunk TileMapLayers.
var shared_tileset: TileSet

## Structure tiles that override generated terrain.
## World position (Vector2i) -> tile type (int). Includes EMPTY for carved areas.
var structure_tiles: Dictionary = {}

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

## Tracks player tile for fog-of-war darkness updates.
var _last_fog_player_tile: Vector2i = Vector2i(999999, 999999)

## Whether the current world gen is a save load (for loading overlay text).
var _is_loading_save: bool = false

## Whether world data was loaded from cache (skip dirty chunk overlay).
var _loaded_from_cache: bool = false

## Whether a finite world is being pre-generated on a background thread.
var _world_generating: bool = false

## Background thread for finite world pre-generation.
var _world_gen_thread: Thread = null

## Reference to loading overlay for progress updates during world generation.
var _loading_overlay = null

## Autotile source IDs: tile_type (int) -> source_id (int) in shared_tileset.
var _autotile_source_ids: Dictionary = {}

## Back wall autotile source IDs: tile_type (int) -> source_id (int).
var _back_wall_source_ids: Dictionary = {}

## Bitmask -> atlas coords lookup for 47-tile blob autotile.
var _bitmask_to_atlas: Dictionary = {}

## Next available source ID for autotile atlas sources.
var _next_source_id: int = 1

## Slope atlas source IDs: tile_type (int) -> source_id (int) in shared_tileset.
var _slope_source_ids: Dictionary = {}

## Atlas coordinates for each slope direction (indexed by SlopeDir enum).
var _slope_atlas_coords: Array[Vector2i] = [
	Vector2i(0, 0),  # FLOOR_RIGHT ◢
	Vector2i(1, 0),  # FLOOR_LEFT ◣
	Vector2i(0, 1),  # CEIL_RIGHT ◥
	Vector2i(1, 1),  # CEIL_LEFT ◤
]

## Global TileMapLayer for foreground tiles (world coordinates, collision enabled).
var _base_tilemap: TileMapLayer

## Global TileMapLayer for back wall tiles (world coordinates, no collision).
var _back_wall_tilemap: TileMapLayer

## Whether tile visuals need to be populated (set after world data is ready).
var _needs_population: bool = false

## Whether visual population is currently in progress (prevents _process re-entry).
var _populating: bool = false

## Current chunk coordinate for spatial darkness overlay management.
var _current_darkness_chunk: Vector2i = Vector2i(999999, 999999)

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

	# Create global TileMapLayers for foreground and back wall
	_create_global_tilemaps()

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
			# Show loading overlay
			_loading_overlay = get_tree().current_scene.get_node_or_null("LoadingOverlay")
			if _loading_overlay:
				_loading_overlay.set_progress_text("Loading tiles...")
			print("[ChunkManager] World loaded from cache, skipping generation.")
			_recompute_static_light()
			_needs_population = true
		else:
			_start_world_generation(_is_existing_save)


## Create the two global TileMapLayers for foreground and back wall tiles.
func _create_global_tilemaps() -> void:
	_base_tilemap = TileMapLayer.new()
	_base_tilemap.name = "BaseTilemap"
	_base_tilemap.tile_set = shared_tileset
	_base_tilemap.collision_enabled = true
	_base_tilemap.z_index = BASE_Z_INDEX
	add_child(_base_tilemap)

	_back_wall_tilemap = TileMapLayer.new()
	_back_wall_tilemap.name = "BackWallTilemap"
	_back_wall_tilemap.tile_set = shared_tileset
	_back_wall_tilemap.collision_enabled = false
	_back_wall_tilemap.z_index = BACK_WALL_Z_INDEX
	_back_wall_tilemap.modulate = Color(0.55, 0.55, 0.55)
	add_child(_back_wall_tilemap)


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
			# Apply structure overrides (spawn chamber)
			_apply_all_structure_tiles()
			# For existing saves without cache, load saved chunk modifications
			if _is_loading_save:
				_apply_saved_chunk_modifications()
			# Cache the generated world for fast future loads
			save_manager.save_world_cache(world_data)
			print("[ChunkManager] Finite world generation complete.")
			print("[ChunkManager] World data tiles: %d" % world_data.tiles.size())
			_recompute_static_light()
			# Reset player to intended spawn (they may have drifted during generation)
			if GameState.player and GameState.saved_player_position != null:
				GameState.player.global_position = GameState.saved_player_position
				GameState.player.velocity = Vector2.ZERO
			# Update loading overlay
			if _loading_overlay and _loading_overlay.has_method("set_progress_text"):
				_loading_overlay.set_progress_text("Loading tiles...")
			_needs_population = true
		else:
			# Update loading overlay with progress percentage
			if _loading_overlay and _loading_overlay.has_method("set_progress_text"):
				var pct: int = int(world_generator.get_generation_progress() * 100.0)
				var label: String = "Loading world... %d%%" % pct if _is_loading_save else "Generating world... %d%%" % pct
				_loading_overlay.set_progress_text(label)
		return  # Don't do normal processing while generating

	# Visual population in progress — hold player in place and wait
	if _populating:
		if GameState.player and GameState.saved_player_position != null:
			GameState.player.global_position = GameState.saved_player_position
			GameState.player.velocity = Vector2.ZERO
		return

	# One-time visual population after world data is ready
	if _needs_population:
		_needs_population = false
		_populate_all_visuals()
		return

	if not GameState.player:
		return

	# Spatial darkness overlay management
	_update_darkness_chunks()

	# Track max depth for BehaviorTracker
	_update_depth_tracking()

	# Fog of war: update darkness when player moves to a new tile
	var player_pos: Vector2 = GameState.player.global_position
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


## Populate all tile visuals into the global TileMapLayers.
## Async — yields every 10,000 tiles for progress bar updates.
func _populate_all_visuals() -> void:
	_populating = true
	var total: int = world_data.tiles.size() + world_data.back_wall_tiles.size()
	var count: int = 0

	# Populate foreground tiles
	for wpos in world_data.tiles:
		var tile_type: int = world_data.tiles[wpos]
		if tile_type != TileDatabase.TileType.EMPTY:
			var visual: Dictionary = _get_tile_visual(wpos, tile_type)
			_base_tilemap.set_cell(wpos, visual["source_id"], visual["atlas_coords"])
		count += 1
		if count % 10000 == 0:
			if _loading_overlay and _loading_overlay.has_method("set_progress_text"):
				var pct: int = count * 100 / maxi(total, 1)
				_loading_overlay.set_progress_text("Loading tiles... %d%%" % pct)
			# Pin player position before yielding
			if GameState.player and GameState.saved_player_position != null:
				GameState.player.global_position = GameState.saved_player_position
				GameState.player.velocity = Vector2.ZERO
			await get_tree().process_frame

	# Populate back wall tiles
	for wpos in world_data.back_wall_tiles:
		var wall_type: int = world_data.back_wall_tiles[wpos]
		if wall_type != 0:
			var visual: Dictionary = _get_back_wall_visual(wpos, wall_type)
			_back_wall_tilemap.set_cell(wpos, visual["source_id"], visual["atlas_coords"])
		count += 1
		if count % 10000 == 0:
			if _loading_overlay and _loading_overlay.has_method("set_progress_text"):
				var pct: int = count * 100 / maxi(total, 1)
				_loading_overlay.set_progress_text("Loading tiles... %d%%" % pct)
			if GameState.player and GameState.saved_player_position != null:
				GameState.player.global_position = GameState.saved_player_position
				GameState.player.velocity = Vector2.ZERO
			await get_tree().process_frame

	# Spawn all torches
	for torch_pos in world_data.torches:
		_spawn_torch(torch_pos)

	# Create initial darkness overlays around player
	_update_darkness_chunks()

	print("[ChunkManager] All visuals populated: %d foreground, %d back wall tiles." % [world_data.tiles.size(), world_data.back_wall_tiles.size()])
	_populating = false
	initial_load_complete.emit()


## Apply structure tile overrides directly to world_data.
## Called after world generation for new worlds.
func _apply_all_structure_tiles() -> void:
	for wpos in structure_tiles:
		var tile_type: int = structure_tiles[wpos]
		if tile_type == TileDatabase.TileType.EMPTY:
			world_data.tiles.erase(wpos)
		else:
			world_data.tiles[wpos] = tile_type


## Load saved chunk modifications for existing saves without a world cache.
## Scans current/chunks/ directory for saved chunk files and applies player
## modifications to world_data.
func _apply_saved_chunk_modifications() -> void:
	var chunks_dir: String = "user://worlds/%s/current/chunks/" % save_manager.world_name
	if not DirAccess.dir_exists_absolute(chunks_dir):
		return
	var dir := DirAccess.open(chunks_dir)
	if not dir:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".dat"):
			var parts: PackedStringArray = entry.get_basename().split("_")
			if parts.size() == 2:
				var cc := Vector2i(parts[0].to_int(), parts[1].to_int())
				var saved_data = save_manager.load_chunk(cc)
				if saved_data != null:
					world_data.set_chunk_tiles(cc, saved_data["tiles"])
					if saved_data.has("back_walls"):
						world_data.set_chunk_back_walls(cc, saved_data["back_walls"])
					for tpos in saved_data["torches"]:
						world_data.torches[tpos] = true
					world_data.dirty_chunks[cc] = true
		entry = dir.get_next()
	dir.list_dir_end()
	print("[ChunkManager] Applied saved chunk modifications.")


## Manage darkness overlays spatially around the player.
## Creates overlays within DARKNESS_RADIUS, removes far ones.
func _update_darkness_chunks() -> void:
	if not GameState.player:
		return
	var player_pos: Vector2 = GameState.player.global_position
	var player_chunk := Vector2i(
		floori(player_pos.x / PIXEL_CHUNK_SIZE),
		floori(player_pos.y / PIXEL_CHUNK_SIZE)
	)
	if player_chunk == _current_darkness_chunk:
		return
	_current_darkness_chunk = player_chunk

	var needed: Dictionary = {}
	for x in range(player_chunk.x - DARKNESS_RADIUS, player_chunk.x + DARKNESS_RADIUS + 1):
		for y in range(player_chunk.y - DARKNESS_RADIUS, player_chunk.y + DARKNESS_RADIUS + 1):
			needed[Vector2i(x, y)] = true

	# Remove far overlays
	var to_remove: Array[Vector2i] = []
	for cc in chunk_darkness_sprites:
		if not needed.has(cc):
			to_remove.append(cc)
	for cc in to_remove:
		chunk_darkness_sprites[cc].queue_free()
		chunk_darkness_sprites.erase(cc)

	# Create missing overlays
	for cc in needed:
		if not chunk_darkness_sprites.has(cc):
			_create_darkness_overlay(cc)


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



# --- Tile update handlers (GameServer signals) ---

## Called when a tile is mined via GameServer. Update visuals and spawn a drop.
func _on_tile_mined(world_pos: Vector2i, tile_type: int, _tool_used: String) -> void:
	# Update the visual tilemap
	_base_tilemap.erase_cell(world_pos)

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
	var visual: Dictionary = _get_tile_visual(world_pos, tile_type)
	_base_tilemap.set_cell(world_pos, visual["source_id"], visual["atlas_coords"])

	# Update neighbor visuals
	_update_neighbor_visuals(world_pos)

	_recompute_light_local(world_pos)
	_update_player_light(_last_fog_player_tile)


## Called when a back wall is mined via GameServer. Update visuals and spawn a drop.
func _on_back_wall_mined(world_pos: Vector2i, tile_type: int) -> void:
	_back_wall_tilemap.erase_cell(world_pos)

	# Update neighbor back wall visuals (autotile bitmask changes)
	_update_back_wall_neighbor_visuals(world_pos)

	# Spawn dropped item for the mined back wall
	_spawn_dropped_item(world_pos, tile_type)

	_update_fog_darkness()
	_recompute_light_local(world_pos)
	_update_player_light(_last_fog_player_tile)


## Called when a back wall is placed via GameServer. Update visuals.
func _on_back_wall_placed(world_pos: Vector2i, tile_type: int) -> void:
	var visual: Dictionary = _get_back_wall_visual(world_pos, tile_type)
	_back_wall_tilemap.set_cell(world_pos, visual["source_id"], visual["atlas_coords"])

	# Update neighbor back wall visuals
	_update_back_wall_neighbor_visuals(world_pos)

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

	# Build bitmask lookup table for 47-tile blob autotile
	_build_bitmask_lookup()

	# Add autotile atlas sources for tile types with tileset art
	_add_autotile_sources(ts)

	# Add slope atlas sources for tile types (art or colored fallback)
	_add_slope_sources(ts)

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


## Build the bitmask -> atlas coords lookup table for 47-tile blob autotile.
## The atlas is a 12x4 grid (48 cells, 47 used + 1 empty).
## Bitmask bits: N=1, NE=2, E=4, SE=8, S=16, SW=32, W=64, NW=128.
func _build_bitmask_lookup() -> void:
	_bitmask_to_atlas = {
		# Block 1: No-diagonal basic tiles (cols 0-3)
		# Col 0: Vertical pipe variants
		16: Vector2i(0, 0),      # S
		17: Vector2i(0, 1),      # N+S
		1: Vector2i(0, 2),       # N
		0: Vector2i(0, 3),       # Isolated
		# Col 1: Right-facing L variants
		20: Vector2i(1, 0),      # E+S
		21: Vector2i(1, 1),      # N+E+S
		5: Vector2i(1, 2),       # N+E
		4: Vector2i(1, 3),       # E
		# Col 2: T/cross variants
		84: Vector2i(2, 0),      # E+S+W
		85: Vector2i(2, 1),      # N+E+S+W
		69: Vector2i(2, 2),      # N+E+W
		68: Vector2i(2, 3),      # E+W
		# Col 3: Left-facing L variants
		80: Vector2i(3, 0),      # S+W
		81: Vector2i(3, 1),      # N+S+W
		65: Vector2i(3, 2),      # N+W
		64: Vector2i(3, 3),      # W
		# Block 2: Diagonal variants (cols 4-7)
		213: Vector2i(4, 0),     # N+E+S+W+NW
		29: Vector2i(4, 1),      # N+E+SE+S
		23: Vector2i(4, 2),      # N+NE+E+S
		117: Vector2i(4, 3),     # N+E+S+SW+W
		92: Vector2i(5, 0),      # E+SE+S+W
		127: Vector2i(5, 1),     # All except NW
		223: Vector2i(5, 2),     # All except SW
		71: Vector2i(5, 3),      # N+NE+E+W
		116: Vector2i(6, 0),     # E+S+SW+W
		253: Vector2i(6, 1),     # All except NE
		247: Vector2i(6, 2),     # All except SE
		197: Vector2i(6, 3),     # N+E+W+NW
		87: Vector2i(7, 0),      # N+NE+E+S+W
		113: Vector2i(7, 1),     # N+S+SW+W
		209: Vector2i(7, 2),     # N+S+W+NW
		93: Vector2i(7, 3),      # N+E+SE+S+W
		# Block 3: Full corners/edges with diagonals (cols 8-11)
		28: Vector2i(8, 0),      # E+SE+S
		31: Vector2i(8, 1),      # N+NE+E+SE+S
		95: Vector2i(8, 2),      # N+NE+E+SE+S+W
		7: Vector2i(8, 3),       # N+NE+E
		125: Vector2i(9, 0),     # N+E+SE+S+SW+W
		119: Vector2i(9, 1),     # N+NE+E+S+SW+W
		255: Vector2i(9, 2),     # All filled
		199: Vector2i(9, 3),     # N+NE+E+W+NW
		124: Vector2i(10, 0),    # E+SE+S+SW+W
		# (10, 1) is empty — no bitmask maps here
		221: Vector2i(10, 2),    # N+E+SE+S+W+NW
		215: Vector2i(10, 3),    # N+NE+E+S+W+NW
		112: Vector2i(11, 0),    # S+SW+W
		245: Vector2i(11, 1),    # N+E+S+SW+W+NW
		241: Vector2i(11, 2),    # N+S+SW+W+NW
		193: Vector2i(11, 3),    # N+W+NW
	}


## Add TileSetAtlasSource entries for each tileset-mode tile type.
## Each type with a tiles.png gets its own atlas source in the shared tileset.
func _add_autotile_sources(ts: TileSet) -> void:
	var tile_types: Array = TileDatabase.get_tile_types()
	for tile_type in tile_types:
		var render_mode: String = TileDatabase.get_render_mode(tile_type)
		if render_mode != "tileset":
			continue

		var tileset_path: String = TileDatabase.get_tileset_path(tile_type)
		if tileset_path == "" or not ResourceLoader.exists(tileset_path):
			continue

		var tex: Texture2D = load(tileset_path)
		if tex == null:
			push_warning("[ChunkManager] Failed to load tileset texture: %s" % tileset_path)
			continue

		var atlas := TileSetAtlasSource.new()
		atlas.texture = tex
		atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

		# Must add source to tileset BEFORE adding collision — tile data needs
		# the physics layer from the tileset to accept collision polygons.
		var source_id: int = ts.add_source(atlas, _next_source_id)

		# Create tiles for all 48 cells in the 12x4 grid
		for row in range(4):
			for col in range(12):
				var coords := Vector2i(col, row)
				atlas.create_tile(coords)
				var tile_data: TileData = atlas.get_tile_data(coords, 0)
				tile_data.add_collision_polygon(0)
				tile_data.set_collision_polygon_points(0, 0, collision_polygon)
		_autotile_source_ids[tile_type] = source_id
		_next_source_id = source_id + 1

		# Also try loading back_wall.png for this tile type
		var back_wall_path: String = TileDatabase.get_back_wall_path(tile_type)
		if back_wall_path != "" and ResourceLoader.exists(back_wall_path):
			var bw_tex: Texture2D = load(back_wall_path)
			if bw_tex != null:
				var bw_atlas := TileSetAtlasSource.new()
				bw_atlas.texture = bw_tex
				bw_atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
				for row in range(4):
					for col in range(12):
						var coords := Vector2i(col, row)
						bw_atlas.create_tile(coords)
						# No collision for back wall tiles
				var bw_source_id: int = ts.add_source(bw_atlas, _next_source_id)
				_back_wall_source_ids[tile_type] = bw_source_id
				_next_source_id = bw_source_id + 1

		print("[ChunkManager] Autotile source added for tile type %d: source_id=%d" % [tile_type, source_id])

	print("[ChunkManager] Autotile setup complete: %d foreground, %d back wall sources." % [_autotile_source_ids.size(), _back_wall_source_ids.size()])


## Add slope atlas sources for each solid tile type.
## Uses slopes.png art if available, otherwise generates colored triangle fallback.
func _add_slope_sources(ts: TileSet) -> void:
	# Build the 4 triangle collision polygons (clockwise winding)
	var half: float = TILE_SIZE / 2.0
	var slope_polygons: Array[PackedVector2Array] = [
		# FLOOR_RIGHT ◢
		PackedVector2Array([Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]),
		# FLOOR_LEFT ◣
		PackedVector2Array([Vector2(-half, -half), Vector2(half, half), Vector2(-half, half)]),
		# CEIL_RIGHT ◥
		PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half)]),
		# CEIL_LEFT ◤
		PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half)]),
	]

	var tile_types: Array = TileDatabase.get_tile_types()
	for tile_type in tile_types:
		# Skip non-solid types
		if tile_type == TileDatabase.TileType.EMPTY or tile_type == TileDatabase.TileType.WATER:
			continue

		# Try loading slope art
		var slope_path: String = TileDatabase.get_slope_path(tile_type)
		var tex: Texture2D = null
		if slope_path != "" and ResourceLoader.exists(slope_path):
			tex = load(slope_path)

		# Generate colored triangle fallback if no art
		if tex == null:
			var color: Color = TileDatabase.get_properties(tile_type)["color"]
			var img: Image = _create_slope_fallback_image(color)
			tex = ImageTexture.create_from_image(img)

		var atlas := TileSetAtlasSource.new()
		atlas.texture = tex
		atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

		# Must add source BEFORE adding collision polygons
		var source_id: int = ts.add_source(atlas, _next_source_id)

		# Create 4 slope tiles with triangle collision
		for dir in range(4):
			var coords: Vector2i = _slope_atlas_coords[dir]
			atlas.create_tile(coords)
			var tile_data: TileData = atlas.get_tile_data(coords, 0)
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, slope_polygons[dir])

		_slope_source_ids[tile_type] = source_id
		_next_source_id = source_id + 1

	print("[ChunkManager] Slope sources added: %d tile types." % _slope_source_ids.size())


## Generate a 32x32 fallback image with 4 colored triangles for slope rendering.
func _create_slope_fallback_image(color: Color) -> Image:
	var img := Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	var ts: int = TILE_SIZE  # 16

	for dir in range(4):
		var ox: int = (dir % 2) * ts  # Column offset (0 or 16)
		var oy: int = (dir / 2) * ts  # Row offset (0 or 16)
		for lx in range(ts):
			for ly in range(ts):
				var fill: bool = false
				match dir:
					SlopeDir.FLOOR_RIGHT:
						fill = (lx + ly >= ts - 1)
					SlopeDir.FLOOR_LEFT:
						fill = (ly >= lx)
					SlopeDir.CEIL_RIGHT:
						fill = (ly <= lx)
					SlopeDir.CEIL_LEFT:
						fill = (lx + ly <= ts - 1)
				if fill:
					var variation: float = (_hash_pixel(ox + lx, oy + ly) - 0.5) * 0.1
					var c := Color(
						clampf(color.r + variation, 0.0, 1.0),
						clampf(color.g + variation, 0.0, 1.0),
						clampf(color.b + variation, 0.0, 1.0),
						1.0
					)
					img.set_pixel(ox + lx, oy + ly, c)
				# Unfilled pixels stay transparent (default alpha=0)

	return img


## Evaluate whether a solid tile should render as a slope.
## Returns the SlopeDir or NONE. Floor slopes are checked before ceiling.
func _evaluate_slope(world_pos: Vector2i) -> int:
	# Floor slopes: N must be empty, S must be solid (continuous ground surface)
	if not world_data.has_tile(world_pos + Vector2i(0, -1)) and world_data.has_tile(world_pos + Vector2i(0, 1)):
		# ◢ Floor-right: NE solid, NE's N empty, NW NOT solid (else it's a valley)
		var ne := world_pos + Vector2i(1, -1)
		if world_data.has_tile(ne) and not world_data.has_tile(ne + Vector2i(0, -1)) and not world_data.has_tile(world_pos + Vector2i(-1, -1)) and not world_data.has_tile(world_pos + Vector2i(-1, 0)) and world_data.has_tile(world_pos + Vector2i(1, 0)):
			return SlopeDir.FLOOR_RIGHT
		# ◣ Floor-left: NW solid, NW's N empty, NE NOT solid (else it's a valley)
		var nw := world_pos + Vector2i(-1, -1)
		if world_data.has_tile(nw) and not world_data.has_tile(nw + Vector2i(0, -1)) and not world_data.has_tile(world_pos + Vector2i(1, -1)) and not world_data.has_tile(world_pos + Vector2i(1, 0)) and world_data.has_tile(world_pos + Vector2i(-1, 0)):
			return SlopeDir.FLOOR_LEFT
		# Ledge slopes: tile at the top edge of a step
		# ◢ Floor-right ledge: drop to the left — W empty, SW solid (lower ground), E solid (upper level continues)
		if not world_data.has_tile(world_pos + Vector2i(-1, 0)) and world_data.has_tile(world_pos + Vector2i(-1, 1)) and world_data.has_tile(world_pos + Vector2i(1, 0)):
			return SlopeDir.FLOOR_RIGHT
		# ◣ Floor-left ledge: drop to the right — E empty, SE solid (lower ground), W solid (upper level continues)
		if not world_data.has_tile(world_pos + Vector2i(1, 0)) and world_data.has_tile(world_pos + Vector2i(1, 1)) and world_data.has_tile(world_pos + Vector2i(-1, 0)):
			return SlopeDir.FLOOR_LEFT

	# Ceiling slopes: S must be empty, N must be solid (continuous ceiling surface)
	if not world_data.has_tile(world_pos + Vector2i(0, 1)) and world_data.has_tile(world_pos + Vector2i(0, -1)):
		# ◥ Ceil-right: SE solid, SE's S empty, SW NOT solid (else it's a notch)
		var se := world_pos + Vector2i(1, 1)
		if world_data.has_tile(se) and not world_data.has_tile(se + Vector2i(0, 1)) and not world_data.has_tile(world_pos + Vector2i(-1, 1)) and not world_data.has_tile(world_pos + Vector2i(-1, 0)) and world_data.has_tile(world_pos + Vector2i(1, 0)):
			return SlopeDir.CEIL_RIGHT
		# ◤ Ceil-left: SW solid, SW's S empty, SE NOT solid (else it's a notch)
		var sw := world_pos + Vector2i(-1, 1)
		if world_data.has_tile(sw) and not world_data.has_tile(sw + Vector2i(0, 1)) and not world_data.has_tile(world_pos + Vector2i(1, 1)) and not world_data.has_tile(world_pos + Vector2i(1, 0)) and world_data.has_tile(world_pos + Vector2i(-1, 0)):
			return SlopeDir.CEIL_LEFT
		# Ceiling ledge slopes: tile at the bottom edge of an overhang
		# ◥ Ceil-right ledge: indent to the left — W empty, NW solid, E solid
		if not world_data.has_tile(world_pos + Vector2i(-1, 0)) and world_data.has_tile(world_pos + Vector2i(-1, -1)) and world_data.has_tile(world_pos + Vector2i(1, 0)):
			return SlopeDir.CEIL_RIGHT
		# ◤ Ceil-left ledge: indent to the right — E empty, NE solid, W solid
		if not world_data.has_tile(world_pos + Vector2i(1, 0)) and world_data.has_tile(world_pos + Vector2i(1, -1)) and world_data.has_tile(world_pos + Vector2i(-1, 0)):
			return SlopeDir.CEIL_LEFT

	return SlopeDir.NONE


## Compute the 8-neighbor bitmask for a tile at world_pos.
## Checks world_data.has_tile() for each of 8 neighbors.
## Diagonal bits only set if both adjacent cardinals are also filled.
## Returns a value that maps to _bitmask_to_atlas.
func _compute_bitmask(world_pos: Vector2i) -> int:
	var n: bool = world_data.has_tile(world_pos + Vector2i(0, -1))
	var e: bool = world_data.has_tile(world_pos + Vector2i(1, 0))
	var s: bool = world_data.has_tile(world_pos + Vector2i(0, 1))
	var w: bool = world_data.has_tile(world_pos + Vector2i(-1, 0))

	var bitmask: int = 0
	if n: bitmask |= 1
	if e: bitmask |= 4
	if s: bitmask |= 16
	if w: bitmask |= 64

	# Diagonals only count if both adjacent cardinals are filled
	if n and e and world_data.has_tile(world_pos + Vector2i(1, -1)):
		bitmask |= 2  # NE
	if e and s and world_data.has_tile(world_pos + Vector2i(1, 1)):
		bitmask |= 8  # SE
	if s and w and world_data.has_tile(world_pos + Vector2i(-1, 1)):
		bitmask |= 32  # SW
	if w and n and world_data.has_tile(world_pos + Vector2i(-1, -1)):
		bitmask |= 128  # NW

	return bitmask


## Compute the 8-neighbor bitmask for a back wall tile.
## Same logic as _compute_bitmask but checks world_data.has_back_wall().
func _compute_back_wall_bitmask(world_pos: Vector2i) -> int:
	var n: bool = world_data.has_back_wall(world_pos + Vector2i(0, -1))
	var e: bool = world_data.has_back_wall(world_pos + Vector2i(1, 0))
	var s: bool = world_data.has_back_wall(world_pos + Vector2i(0, 1))
	var w: bool = world_data.has_back_wall(world_pos + Vector2i(-1, 0))

	var bitmask: int = 0
	if n: bitmask |= 1
	if e: bitmask |= 4
	if s: bitmask |= 16
	if w: bitmask |= 64

	if n and e and world_data.has_back_wall(world_pos + Vector2i(1, -1)):
		bitmask |= 2
	if e and s and world_data.has_back_wall(world_pos + Vector2i(1, 1)):
		bitmask |= 8
	if s and w and world_data.has_back_wall(world_pos + Vector2i(-1, 1)):
		bitmask |= 32
	if w and n and world_data.has_back_wall(world_pos + Vector2i(-1, -1)):
		bitmask |= 128

	return bitmask


# --- Tile visuals ---

## Get the visual source_id and atlas_coords for a foreground tile.
## Checks for slope condition first, then autotile bitmask, then colored rect fallback.
func _get_tile_visual(world_pos: Vector2i, tile_type: int) -> Dictionary:
	# Check if this tile should render as a slope
	var slope_dir: int = _evaluate_slope(world_pos)
	if slope_dir != SlopeDir.NONE and _slope_source_ids.has(tile_type):
		return {
			"source_id": _slope_source_ids[tile_type],
			"atlas_coords": _slope_atlas_coords[slope_dir],
		}
	# Check if this tile type has an autotile source
	if _autotile_source_ids.has(tile_type):
		var bitmask: int = _compute_bitmask(world_pos)
		var atlas_coords: Vector2i = _bitmask_to_atlas.get(bitmask, Vector2i(0, 0))
		return {
			"source_id": _autotile_source_ids[tile_type],
			"atlas_coords": atlas_coords,
		}
	# Fallback: colored rectangle from programmatic atlas
	return {
		"source_id": 0,
		"atlas_coords": TileDatabase.get_atlas_coords(tile_type),
	}


## Get the visual source_id and atlas_coords for a back wall tile.
## Uses back wall autotile if available, otherwise falls back to colored rect.
func _get_back_wall_visual(world_pos: Vector2i, tile_type: int) -> Dictionary:
	if _back_wall_source_ids.has(tile_type):
		var bitmask: int = _compute_back_wall_bitmask(world_pos)
		var atlas_coords: Vector2i = _bitmask_to_atlas.get(bitmask, Vector2i(0, 0))
		return {
			"source_id": _back_wall_source_ids[tile_type],
			"atlas_coords": atlas_coords,
		}
	# Fallback: use colored rect
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
		# Extended for slope dependency (NE/NW/SE/SW's N/S checks, 2 tiles away)
		Vector2i(-1, -2), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(1, 2),
	]
	for offset in all_offsets:
		var neighbor_pos: Vector2i = center_pos + offset
		var neighbor_type: int = world_data.get_tile(neighbor_pos)
		if neighbor_type != TileDatabase.TileType.EMPTY:
			_update_single_tile_visual(neighbor_pos, neighbor_type)


## Recalculate and update the visual for a single tile.
func _update_single_tile_visual(world_pos: Vector2i, tile_type: int) -> void:
	var visual: Dictionary = _get_tile_visual(world_pos, tile_type)
	_base_tilemap.set_cell(world_pos, visual["source_id"], visual["atlas_coords"])


## Update visuals for all 8 back wall neighbors of a changed position.
func _update_back_wall_neighbor_visuals(center_pos: Vector2i) -> void:
	var all_offsets: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1),
	]
	for offset in all_offsets:
		var neighbor_pos: Vector2i = center_pos + offset
		var neighbor_type: int = world_data.get_back_wall(neighbor_pos)
		if neighbor_type != 0:
			_update_single_back_wall_visual(neighbor_pos, neighbor_type)


## Recalculate and update the visual for a single back wall tile.
func _update_single_back_wall_visual(world_pos: Vector2i, tile_type: int) -> void:
	var visual: Dictionary = _get_back_wall_visual(world_pos, tile_type)
	_back_wall_tilemap.set_cell(world_pos, visual["source_id"], visual["atlas_coords"])


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
	for chunk_coord in world_data.dirty_chunks.keys():
		if world_data.dirty_chunks[chunk_coord]:
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


## Convert a pixel position to a tile coordinate.
func world_to_tile(pixel_pos: Vector2) -> Vector2i:
	return Vector2i(floori(pixel_pos.x / TILE_SIZE), floori(pixel_pos.y / TILE_SIZE))


## Convert a tile coordinate to the pixel position of its center.
func tile_to_world_center(tile_pos: Vector2i) -> Vector2:
	return Vector2(tile_pos.x * TILE_SIZE + TILE_SIZE / 2.0, tile_pos.y * TILE_SIZE + TILE_SIZE / 2.0)
