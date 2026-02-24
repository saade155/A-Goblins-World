## SaveManager - Handles all save/load disk I/O for world persistence.
##
## Multi-snapshot save system with autosave and manual save support.
## Saves dirty chunks, world metadata, player state, and BehaviorTracker data.
## Uses Godot's store_var/get_var for serialization which handles Dictionary
## with Vector2i keys natively.
##
## Save layout (v2 directory structure):
##   user://worlds/<name>/world.dat                    - Immutable: seed, config
##   user://worlds/<name>/behavior.dat                 - Cumulative counters
##   user://worlds/<name>/current/state.dat            - Player pos, inventory, playtime
##   user://worlds/<name>/current/chunks/<x>_<y>.dat   - Per-chunk tile data + torches
##   user://worlds/<name>/saves/<save_name>/state.dat  - Snapshot player state
##   user://worlds/<name>/saves/<save_name>/chunks/    - Snapshot chunk data
##   user://worlds/<name>/saves/<save_name>/meta.dat   - Snapshot metadata

extends RefCounted
class_name SaveManager

## File format version for future migration support.
const SAVE_VERSION: int = 4

## Directory layout version. 1 = flat (legacy), 2 = structured with current/ and saves/.
const LAYOUT_VERSION: int = 2

## Name of the current world (used in save path).
var world_name: String = "default"

## Background thread for snapshot operations. Only one save at a time.
var _save_thread: Thread = null

## Set to true by the background thread when the snapshot copy finishes.
var _save_completed: bool = false

## Result from the last completed snapshot. {save_name: String, success: bool}
var _save_result: Dictionary = {}


## Returns true if a background snapshot is currently in progress.
func is_saving() -> bool:
	return _save_thread != null and _save_thread.is_started()


## Call from the main thread (_process) to check if a background snapshot finished.
## Returns empty Dictionary if not done yet, otherwise {save_name, success} and
## cleans up the thread so a new save can start.
func check_save_complete() -> Dictionary:
	if not _save_completed:
		return {}
	if _save_thread:
		_save_thread.wait_to_finish()
		_save_thread = null
	_save_completed = false
	var result: Dictionary = _save_result
	_save_result = {}
	return result


# ===========================================================================
#  Path helpers
# ===========================================================================

## Base path for this world's save data.
func _get_world_path() -> String:
	return "user://worlds/%s/" % world_name


## Path to the current/ live play directory.
func _get_current_path() -> String:
	return "%scurrent/" % _get_world_path()


## Path to a specific chunk's save file (inside current/).
func _get_chunk_path(chunk_coord: Vector2i) -> String:
	return "%schunks/%d_%d.dat" % [_get_current_path(), chunk_coord.x, chunk_coord.y]


## Path to the world metadata file (immutable seed/config at world root).
func _get_world_meta_path() -> String:
	return "%sworld.dat" % _get_world_path()


## Path to the session state file (player pos, inventory, playtime).
func _get_state_path() -> String:
	return "%sstate.dat" % _get_current_path()


## Path to the BehaviorTracker save file (world root, not snapshotted).
func _get_behavior_path() -> String:
	return "%sbehavior.dat" % _get_world_path()


## Path to the saves/ directory containing all snapshots.
func _get_saves_dir() -> String:
	return "%ssaves/" % _get_world_path()


## Path to a specific snapshot directory.
func _get_save_path(save_name: String) -> String:
	return "%s%s/" % [_get_saves_dir(), save_name]


## Path to a snapshot's meta.dat file.
func _get_save_meta_path(save_name: String) -> String:
	return "%smeta.dat" % _get_save_path(save_name)


# ===========================================================================
#  Chunk I/O (reads/writes to current/)
# ===========================================================================

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


# ===========================================================================
#  World metadata (immutable — written once on world creation)
# ===========================================================================

## Save immutable world metadata: seed, start depth, display name.
## Only called on NEW world creation. Never overwritten after that.
func save_world_meta(world_seed: int, start_depth: int, display_name: String = "") -> void:
	var path: String = _get_world_meta_path()
	_ensure_directory(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[SaveManager] Failed to save world meta: %s" % error_string(FileAccess.get_open_error()))
		return
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"layout_version": LAYOUT_VERSION,
		"world_seed": world_seed,
		"start_depth": start_depth,
		"display_name": display_name if display_name != "" else world_name,
	}
	file.store_var(data)
	file.close()
	print("[SaveManager] World meta saved (immutable). Seed: %d" % world_seed)


## Load immutable world metadata. Returns Dictionary or null if no save exists.
## Does NOT restore inventory — use load_state() for that.
## Handles backward compat: v2/v3 format detection, triggers migration if needed.
func load_world_meta() -> Variant:
	var path: String = _get_world_meta_path()
	if not FileAccess.file_exists(path):
		return null

	# Migrate legacy flat layout to structured layout if needed.
	migrate_if_needed()

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var data: Dictionary = file.get_var()
	file.close()

	# Reject saves from older tile-size era (v1 used 16px tiles, v2+ uses 32px).
	var version: int = data.get("version", 1)
	if version < 2:
		print("[SaveManager] WARNING: Save version %d is incompatible. Generating new world." % version)
		return null

	# Backward compat: ensure display_name exists.
	if not data.has("display_name"):
		data["display_name"] = world_name

	# Strip session fields that may remain from pre-migration world.dat reads.
	# These now live in state.dat. We keep them in the returned dict only for
	# backward compat with callers that check for them.
	return data


# ===========================================================================
#  Session state (current/state.dat — player pos, inventory, playtime)
# ===========================================================================

## Save session state to current/state.dat.
func save_state(player_position: Vector2, playtime_seconds: float) -> void:
	var path: String = _get_state_path()
	_ensure_directory(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[SaveManager] Failed to save state: %s" % error_string(FileAccess.get_open_error()))
		return
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"player_position_x": player_position.x,
		"player_position_y": player_position.y,
		"inventory_main": GameServer.inventory_main,
		"inventory_hotbar": GameServer.inventory_hotbar,
		"selected_hotbar": GameServer.selected_hotbar_slot,
		"playtime_seconds": playtime_seconds,
		"last_played": Time.get_datetime_string_from_system(),
	}
	file.store_var(data)
	file.close()


## Load session state from current/state.dat. Returns Dictionary or null.
## Restores inventory to GameServer if present.
func load_state() -> Variant:
	var path: String = _get_state_path()
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var data: Dictionary = file.get_var()
	file.close()

	# Restore inventory to GameServer.
	if data.has("inventory_main"):
		GameServer.inventory_main = data["inventory_main"]
		GameServer.inventory_hotbar = data["inventory_hotbar"]
		GameServer.selected_hotbar_slot = data.get("selected_hotbar", 0)
		GameServer.inventory_changed.emit()

	return data


# ===========================================================================
#  Snapshot operations (manual saves + autosaves)
# ===========================================================================

## Create a snapshot by copying current/ to saves/<save_name>/.
## Writes meta.dat with timestamp, trigger reason, playtime.
## The state flush (save_state) happens synchronously on the main thread,
## then the directory copy runs on a background thread.
## Poll check_save_complete() from _process() to detect when it finishes.
func create_snapshot(save_name: String, reason: String, player_position: Vector2, playtime_seconds: float) -> void:
	if is_saving():
		push_warning("[SaveManager] Save already in progress, skipping")
		return

	# Flush current state synchronously (must happen on main thread before copy).
	save_state(player_position, playtime_seconds)

	# Prepare params for the background thread (no Node references).
	_save_completed = false
	_save_result = {}

	var params: Dictionary = {
		"save_name": save_name,
		"reason": reason,
		"playtime_seconds": playtime_seconds,
		"player_position_x": player_position.x,
		"player_position_y": player_position.y,
		"src_path": _get_current_path(),
		"dst_path": _get_save_path(save_name),
		"meta_path": _get_save_meta_path(save_name),
		"save_version": SAVE_VERSION,
	}

	_save_thread = Thread.new()
	_save_thread.start(_snapshot_thread_func.bind(params))
	print("[SaveManager] Snapshot started on background thread: %s (reason: %s)" % [save_name, reason])


## Background thread function that copies current/ to a snapshot directory.
## Only does file I/O — never accesses Nodes or the scene tree.
func _snapshot_thread_func(params: Dictionary) -> void:
	var success: bool = true

	# If snapshot already exists, delete it first for a clean overwrite.
	if DirAccess.dir_exists_absolute(params.dst_path):
		_delete_directory_recursive(params.dst_path)

	# Copy current/ directory tree to saves/<save_name>/.
	_copy_directory(params.src_path, params.dst_path)

	# Write meta.dat with snapshot info.
	var meta_file := FileAccess.open(params.meta_path, FileAccess.WRITE)
	if meta_file:
		var meta: Dictionary = {
			"version": params.save_version,
			"save_name": params.save_name,
			"reason": params.reason,
			"timestamp": Time.get_datetime_string_from_system(),
			"playtime_seconds": params.playtime_seconds,
			"player_position_x": params.player_position_x,
			"player_position_y": params.player_position_y,
			"is_auto": params.save_name.begins_with("auto_"),
		}
		meta_file.store_var(meta)
		meta_file.close()
	else:
		success = false

	# Signal completion via shared state (main thread polls check_save_complete).
	_save_result = {"save_name": params.save_name, "success": success}
	_save_completed = true


## Load a snapshot by copying saves/<save_name>/ to current/ (overwrites current state).
func load_snapshot(save_name: String) -> bool:
	var src_path: String = _get_save_path(save_name)
	var dst_path: String = _get_current_path()

	if not DirAccess.dir_exists_absolute(src_path):
		push_error("[SaveManager] Snapshot not found: %s" % save_name)
		return false

	# Delete current/ contents, then copy snapshot into it.
	_delete_directory_contents(dst_path)
	_copy_directory(src_path, dst_path)

	print("[SaveManager] Snapshot loaded: %s" % save_name)
	return true


## Scan saves/ directory and return metadata for all snapshots.
## Returns Array[Dictionary] sorted by timestamp descending (most recent first).
## Each entry: {save_name, timestamp, reason, playtime_seconds, is_auto}
func enumerate_snapshots() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var saves_path: String = _get_saves_dir()
	if not DirAccess.dir_exists_absolute(saves_path):
		return results

	var dir := DirAccess.open(saves_path)
	if not dir:
		return results

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry != "." and entry != "..":
			var meta_path: String = saves_path + entry + "/meta.dat"
			if FileAccess.file_exists(meta_path):
				var file := FileAccess.open(meta_path, FileAccess.READ)
				if file:
					var meta = file.get_var()
					file.close()
					if meta is Dictionary:
						results.append({
							"save_name": meta.get("save_name", entry),
							"timestamp": meta.get("timestamp", "Unknown"),
							"reason": meta.get("reason", ""),
							"playtime_seconds": meta.get("playtime_seconds", 0.0),
							"is_auto": meta.get("is_auto", entry.begins_with("auto_")),
						})
		entry = dir.get_next()
	dir.list_dir_end()

	# Sort by timestamp descending (most recent first).
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["timestamp"] > b["timestamp"]
	)
	return results


## Recursively delete a snapshot directory.
func delete_snapshot(save_name: String) -> bool:
	var snap_path: String = _get_save_path(save_name)
	if not DirAccess.dir_exists_absolute(snap_path):
		return false
	_delete_directory_recursive(snap_path)
	print("[SaveManager] Deleted snapshot: %s" % save_name)
	return true


## Count existing autosave directories (auto_*).
func get_autosave_count() -> int:
	var saves_path: String = _get_saves_dir()
	if not DirAccess.dir_exists_absolute(saves_path):
		return 0
	var count: int = 0
	var dir := DirAccess.open(saves_path)
	if not dir:
		return 0
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry.begins_with("auto_"):
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


## Delete the oldest autosave if at or above max_count, making room for a new one.
func rotate_autosaves(max_count: int) -> void:
	var snapshots: Array[Dictionary] = enumerate_snapshots()
	var auto_saves: Array[Dictionary] = []
	for snap in snapshots:
		if snap["is_auto"]:
			auto_saves.append(snap)

	# auto_saves is sorted by timestamp desc (newest first).
	# Delete oldest entries until we're below max_count.
	while auto_saves.size() >= max_count:
		var oldest: Dictionary = auto_saves.pop_back()
		delete_snapshot(oldest["save_name"])


# ===========================================================================
#  BehaviorTracker I/O (world root, not snapshotted)
# ===========================================================================

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


# ===========================================================================
#  World existence / slot enumeration
# ===========================================================================

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
						var playtime: float = data.get("playtime_seconds", 0.0)
						var last_played: String = data.get("last_played", "Unknown")
						# For v2 layout, session data lives in current/state.dat.
						# Try to read it for up-to-date playtime/last_played.
						var state_path: String = base_path + entry + "/current/state.dat"
						if FileAccess.file_exists(state_path):
							var state_file := FileAccess.open(state_path, FileAccess.READ)
							if state_file:
								var state_data = state_file.get_var()
								state_file.close()
								if state_data is Dictionary:
									playtime = state_data.get("playtime_seconds", playtime)
									last_played = state_data.get("last_played", last_played)
						results.append({
							"slot_name": entry,
							"display_name": data.get("display_name", entry),
							"playtime_seconds": playtime,
							"last_played": last_played,
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
## Handles the structured layout with current/, saves/, and subdirectories.
## Returns false if the slot directory doesn't exist.
static func delete_slot(slot_name: String) -> bool:
	var slot_path: String = "user://worlds/" + slot_name + "/"
	if not DirAccess.dir_exists_absolute(slot_path):
		return false
	_delete_directory_recursive_static(slot_path)
	print("[SaveManager] Deleted save slot: %s" % slot_name)
	return true


## Sanitize a save name for use as a directory name.
## Replaces unsafe characters, trims whitespace, limits length.
static func sanitize_save_name(raw_name: String) -> String:
	var result: String = raw_name.strip_edges()
	# Replace path separators and Windows-illegal chars
	var illegal: String = "/\\:*?\"<>|"
	for i in illegal.length():
		result = result.replace(illegal[i], "_")
	# Replace multiple underscores with single
	while result.contains("__"):
		result = result.replace("__", "_")
	# Trim to reasonable length
	if result.length() > 50:
		result = result.substr(0, 50)
	# Strip leading/trailing underscores and dots
	result = result.strip_edges().trim_prefix(".").trim_suffix(".").trim_prefix("_").trim_suffix("_")
	if result == "":
		result = "save"
	return result


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


# ===========================================================================
#  Backward compatibility migration (flat layout v1 -> structured layout v2)
# ===========================================================================

## Migrate a legacy flat-layout save to the new structured layout.
## Checks if current/ directory exists. If not, assumes legacy save and migrates:
##   - Creates current/ and current/chunks/
##   - Moves chunks/* -> current/chunks/*
##   - Reads old world.dat, splits into new world.dat (immutable) + current/state.dat (session)
##   - Creates saves/ directory
##   - Removes old chunks/ directory
func migrate_if_needed() -> void:
	var world_path: String = _get_world_path()
	var current_path: String = _get_current_path()

	# If current/ already exists, this is already a v2 layout. Nothing to do.
	if DirAccess.dir_exists_absolute(current_path):
		return

	var meta_path: String = _get_world_meta_path()
	if not FileAccess.file_exists(meta_path):
		return

	print("[SaveManager] Migrating legacy save '%s' to structured layout..." % world_name)

	# 1. Read the old world.dat (contains both immutable and session data).
	var file := FileAccess.open(meta_path, FileAccess.READ)
	if not file:
		push_error("[SaveManager] Migration failed: cannot read world.dat")
		return
	var old_data: Dictionary = file.get_var()
	file.close()

	# 2. Create directory structure.
	_ensure_directory(current_path + "chunks/")
	_ensure_directory(_get_saves_dir())

	# 3. Move legacy chunks/ -> current/chunks/.
	var old_chunks_path: String = world_path + "chunks/"
	if DirAccess.dir_exists_absolute(old_chunks_path):
		var chunks_dir := DirAccess.open(old_chunks_path)
		if chunks_dir:
			chunks_dir.list_dir_begin()
			var chunk_file: String = chunks_dir.get_next()
			while chunk_file != "":
				if not chunks_dir.current_is_dir() and chunk_file.ends_with(".dat"):
					var src: String = old_chunks_path + chunk_file
					var dst: String = current_path + "chunks/" + chunk_file
					# Copy then remove (DirAccess.rename doesn't work across directories in Godot).
					var src_file := FileAccess.open(src, FileAccess.READ)
					if src_file:
						var contents: PackedByteArray = src_file.get_buffer(src_file.get_length())
						src_file.close()
						var dst_file := FileAccess.open(dst, FileAccess.WRITE)
						if dst_file:
							dst_file.store_buffer(contents)
							dst_file.close()
						DirAccess.remove_absolute(src)
				chunk_file = chunks_dir.get_next()
			chunks_dir.list_dir_end()
		# Remove the now-empty old chunks/ directory.
		DirAccess.remove_absolute(old_chunks_path)

	# 4. Write current/state.dat with session data extracted from old world.dat.
	var state_data: Dictionary = {
		"version": SAVE_VERSION,
		"player_position_x": old_data.get("player_position_x", 0.0),
		"player_position_y": old_data.get("player_position_y", 0.0),
		"inventory_main": old_data.get("inventory_main", []),
		"inventory_hotbar": old_data.get("inventory_hotbar", []),
		"selected_hotbar": old_data.get("selected_hotbar", 0),
		"playtime_seconds": old_data.get("playtime_seconds", 0.0),
		"last_played": old_data.get("last_played", Time.get_datetime_string_from_system()),
	}
	var state_path: String = _get_state_path()
	var state_file := FileAccess.open(state_path, FileAccess.WRITE)
	if state_file:
		state_file.store_var(state_data)
		state_file.close()

	# 5. Rewrite world.dat with ONLY immutable data.
	var immutable_data: Dictionary = {
		"version": SAVE_VERSION,
		"layout_version": LAYOUT_VERSION,
		"world_seed": old_data.get("world_seed", 0),
		"start_depth": old_data.get("start_depth", 0),
		"display_name": old_data.get("display_name", world_name),
	}
	var meta_file := FileAccess.open(meta_path, FileAccess.WRITE)
	if meta_file:
		meta_file.store_var(immutable_data)
		meta_file.close()

	print("[SaveManager] Migration complete for '%s'." % world_name)


# ===========================================================================
#  Directory utilities
# ===========================================================================

## Ensure a directory exists, creating it recursively if needed.
func _ensure_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


## Copy an entire directory tree from src to dst (non-static).
func _copy_directory(src_path: String, dst_path: String) -> void:
	_ensure_directory(dst_path)
	var dir := DirAccess.open(src_path)
	if not dir:
		push_error("[SaveManager] Cannot open source dir for copy: %s" % src_path)
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var src_entry: String = src_path + entry
		var dst_entry: String = dst_path + entry
		if dir.current_is_dir():
			_copy_directory(src_entry + "/", dst_entry + "/")
		else:
			var file := FileAccess.open(src_entry, FileAccess.READ)
			if file:
				var contents: PackedByteArray = file.get_buffer(file.get_length())
				file.close()
				var out_file := FileAccess.open(dst_entry, FileAccess.WRITE)
				if out_file:
					out_file.store_buffer(contents)
					out_file.close()
		entry = dir.get_next()
	dir.list_dir_end()


## Delete all files in a directory (but not subdirectories or the dir itself).
func _delete_directory_contents(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path: String = dir_path + entry
		if dir.current_is_dir():
			_delete_directory_recursive(full_path + "/")
		else:
			DirAccess.remove_absolute(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## Recursively delete a directory and all its contents (non-static).
func _delete_directory_recursive(dir_path: String) -> void:
	_delete_directory_contents(dir_path)
	DirAccess.remove_absolute(dir_path)


## Recursively delete a directory and all its contents (static version for delete_slot).
static func _delete_directory_recursive_static(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path: String = dir_path + entry
		if dir.current_is_dir():
			_delete_directory_recursive_static(full_path + "/")
		else:
			DirAccess.remove_absolute(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)
