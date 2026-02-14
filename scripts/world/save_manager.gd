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
const SAVE_VERSION: int = 4

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


## Save world metadata: seed, player position, start depth, and slot info.
func save_world_meta(world_seed: int, player_position: Vector2, start_depth: int, display_name: String = "", playtime_seconds: float = 0.0) -> void:
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
		"inventory_main": GameServer.inventory_main,
		"inventory_hotbar": GameServer.inventory_hotbar,
		"selected_hotbar": GameServer.selected_hotbar_slot,
		"display_name": display_name,
		"playtime_seconds": playtime_seconds,
		"last_played": Time.get_datetime_string_from_system(),
	}
	file.store_var(data)
	file.close()
	print("[SaveManager] World meta saved. Seed: %d" % world_seed)


## Load world metadata. Returns Dictionary or null if no save exists.
## v3 saves missing new fields get defaults: display_name=world_name,
## playtime_seconds=0.0, last_played="Unknown".
func load_world_meta() -> Variant:
	var path: String = _get_world_meta_path()
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var data: Dictionary = file.get_var()
	file.close()
	# Reject saves from older tile-size era (v1 used 16px tiles, v2+ uses 32px)
	var version: int = data.get("version", 1)
	if version < 2:
		print("[SaveManager] WARNING: Save version %d is incompatible. Generating new world." % version)
		return null
	# Restore inventory if present (v3+). Old v2 saves just skip this.
	if data.has("inventory_main"):
		GameServer.inventory_main = data["inventory_main"]
		GameServer.inventory_hotbar = data["inventory_hotbar"]
		GameServer.selected_hotbar_slot = data.get("selected_hotbar", 0)
		GameServer.inventory_changed.emit()
	# Backward compat: v3 saves lack slot metadata fields
	if not data.has("display_name"):
		data["display_name"] = world_name
	if not data.has("playtime_seconds"):
		data["playtime_seconds"] = 0.0
	if not data.has("last_played"):
		data["last_played"] = "Unknown"
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


## Scan user://worlds/ for all save slots and return metadata for each.
## Returns Array[Dictionary] with keys: slot_name, display_name, playtime_seconds, last_played.
## Sorted by last_played descending (most recent first).
static func enumerate_slots() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var base_path: String = "user://worlds/"
	if not DirAccess.dir_exists_absolute(base_path):
		return results
	var dir := DirAccess.open(base_path)
	if not dir:
		return results
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry != "." and entry != "..":
			var meta_path: String = base_path + entry + "/world.dat"
			if FileAccess.file_exists(meta_path):
				var file := FileAccess.open(meta_path, FileAccess.READ)
				if file:
					var data = file.get_var()
					file.close()
					if data is Dictionary:
						results.append({
							"slot_name": entry,
							"display_name": data.get("display_name", entry),
							"playtime_seconds": data.get("playtime_seconds", 0.0),
							"last_played": data.get("last_played", "Unknown"),
						})
		entry = dir.get_next()
	dir.list_dir_end()
	# Sort by last_played descending (most recent first).
	# "Unknown" sorts before valid timestamps, pushing old v3 saves to the end.
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["last_played"] > b["last_played"]
	)
	return results


## Recursively delete a save slot directory and all its contents.
## Returns false if the slot directory doesn't exist.
static func delete_slot(slot_name: String) -> bool:
	var slot_path: String = "user://worlds/" + slot_name + "/"
	if not DirAccess.dir_exists_absolute(slot_path):
		return false
	# Delete chunks subdirectory first
	var chunks_path: String = slot_path + "chunks/"
	if DirAccess.dir_exists_absolute(chunks_path):
		var chunks_dir := DirAccess.open(chunks_path)
		if chunks_dir:
			chunks_dir.list_dir_begin()
			var file_name: String = chunks_dir.get_next()
			while file_name != "":
				if not chunks_dir.current_is_dir():
					chunks_dir.remove(file_name)
				file_name = chunks_dir.get_next()
			chunks_dir.list_dir_end()
		DirAccess.remove_absolute(chunks_path)
	# Delete top-level files in the slot directory
	var slot_dir := DirAccess.open(slot_path)
	if slot_dir:
		slot_dir.list_dir_begin()
		var file_name: String = slot_dir.get_next()
		while file_name != "":
			if not slot_dir.current_is_dir():
				slot_dir.remove(file_name)
			file_name = slot_dir.get_next()
		slot_dir.list_dir_end()
	# Remove the slot directory itself
	DirAccess.remove_absolute(slot_path)
	print("[SaveManager] Deleted save slot: %s" % slot_name)
	return true


## Generate a unique, filesystem-safe slot name from a display name.
## Sanitizes to lowercase alphanumeric + underscores, appends counter if needed.
static func generate_slot_name(display_name: String) -> String:
	var sanitized: String = display_name.to_lower().replace(" ", "_")
	var result: String = ""
	for i in sanitized.length():
		var c: String = sanitized[i]
		if c == "_" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
	if result == "":
		result = "world"
	var base: String = result
	var counter: int = 1
	while DirAccess.dir_exists_absolute("user://worlds/" + result + "/"):
		counter += 1
		result = "%s_%d" % [base, counter]
	return result


## Ensure a directory exists, creating it recursively if needed.
func _ensure_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
