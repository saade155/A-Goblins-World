## SaveManager - Handles all save/load disk I/O for world persistence.
##
## Saves dirty chunks (player-modified), world metadata (seed, player position),
## and BehaviorTracker data. Uses Godot's store_var/get_var for serialization
## which handles Dictionary with Vector2i keys natively.
##
## Save layout:
##   user://worlds/<name>/world.dat        - seed, player position, start_depth
##   user://worlds/<name>/behavior.dat     - BehaviorTracker counters + stats
##   user://worlds/<name>/chunks/<x>_<y>.dat - per-chunk tile data + torches

extends RefCounted
class_name SaveManager

## File format version for future migration support.
const SAVE_VERSION: int = 1

## Name of the current world (used in save path).
var world_name: String = "default"


## Base path for this world's save data.
func _get_world_path() -> String:
	return "user://worlds/%s/" % world_name


## Path to a specific chunk's save file.
func _get_chunk_path(chunk_coord: Vector2i) -> String:
	return "%schunks/%d_%d.dat" % [_get_world_path(), chunk_coord.x, chunk_coord.y]


## Path to the world metadata file.
func _get_world_meta_path() -> String:
	return "%sworld.dat" % _get_world_path()


## Path to the BehaviorTracker save file.
func _get_behavior_path() -> String:
	return "%sbehavior.dat" % _get_world_path()


## Save a single dirty chunk to disk. Stores tile data and torch positions.
func save_chunk(chunk_coord: Vector2i, world_data: WorldData) -> void:
	var path: String = _get_chunk_path(chunk_coord)
	_ensure_directory(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[SaveManager] Failed to save chunk %s: %s" % [str(chunk_coord), error_string(FileAccess.get_open_error())])
		return
	var chunk_tiles: Dictionary = world_data.get_chunk_tiles(chunk_coord)
	var chunk_torches: Array = world_data.get_chunk_torches(chunk_coord)
	file.store_var(SAVE_VERSION)
	file.store_var(chunk_tiles)
	file.store_var(chunk_torches)
	file.close()


## Load a chunk from disk. Returns {"tiles": Dictionary, "torches": Array} or null.
func load_chunk(chunk_coord: Vector2i) -> Variant:
	var path: String = _get_chunk_path(chunk_coord)
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var version: int = file.get_var()
	var chunk_tiles: Dictionary = file.get_var()
	var chunk_torches: Array = []
	if not file.eof_reached():
		chunk_torches = file.get_var()
	file.close()
	return {"tiles": chunk_tiles, "torches": chunk_torches}


## Check if a saved chunk file exists on disk.
func has_saved_chunk(chunk_coord: Vector2i) -> bool:
	return FileAccess.file_exists(_get_chunk_path(chunk_coord))


## Save world metadata: seed, player position, start depth.
func save_world_meta(world_seed: int, player_position: Vector2, start_depth: int) -> void:
	var path: String = _get_world_meta_path()
	_ensure_directory(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[SaveManager] Failed to save world meta: %s" % error_string(FileAccess.get_open_error()))
		return
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"world_seed": world_seed,
		"player_position_x": player_position.x,
		"player_position_y": player_position.y,
		"start_depth": start_depth,
	}
	file.store_var(data)
	file.close()
	print("[SaveManager] World meta saved. Seed: %d" % world_seed)


## Load world metadata. Returns Dictionary or null if no save exists.
func load_world_meta() -> Variant:
	var path: String = _get_world_meta_path()
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var data: Dictionary = file.get_var()
	file.close()
	return data


## Save BehaviorTracker data (counters, stats).
func save_behavior_data(tracker: Node) -> void:
	var path: String = _get_behavior_path()
	_ensure_directory(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[SaveManager] Failed to save behavior data: %s" % error_string(FileAccess.get_open_error()))
		return
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"lifetime_counters": tracker.lifetime_counters,
		"filtered_counters": tracker.filtered_counters,
		"stats": tracker.stats,
	}
	file.store_var(data)
	file.close()


## Load BehaviorTracker data into the tracker. Returns true if loaded.
func load_behavior_data(tracker: Node) -> bool:
	var path: String = _get_behavior_path()
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var data: Dictionary = file.get_var()
	file.close()
	tracker.lifetime_counters = data.get("lifetime_counters", {})
	tracker.filtered_counters = data.get("filtered_counters", {})
	tracker.stats = data.get("stats", {})
	print("[SaveManager] BehaviorTracker data loaded.")
	return true


## Check if a world save exists.
func has_save() -> bool:
	return FileAccess.file_exists(_get_world_meta_path())


## Ensure a directory exists, creating it recursively if needed.
func _ensure_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
