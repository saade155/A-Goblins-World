## WorldData - Authoritative tile storage.
##
## This is the source of truth for what tiles exist in the world. It is a pure
## data layer -- no rendering, no nodes. The TileMapLayer reads from this to
## display tiles, and GameServer modifies this when mining/placing.
##
## Tiles are stored as Dictionary[Vector2i, int] where the int is a TileType enum
## value from TileData. Positions not in the dictionary are considered EMPTY.
##
## Chunk-aware: tracks which chunks have been modified by the player (dirty)
## so the save system knows what to persist vs. what can be regenerated.

class_name WorldData
extends RefCounted

## Chunk size in tiles. Each chunk is CHUNK_SIZE x CHUNK_SIZE.
const CHUNK_SIZE: int = 32

## World size presets selectable at world creation.
enum WorldSize { SMALL, MEDIUM, LARGE }

const WORLD_SIZE_PRESETS: Dictionary = {
	WorldSize.SMALL: { "width": 2400, "height": 1000, "surface_rows": 250 },
	WorldSize.MEDIUM: { "width": 3600, "height": 1200, "surface_rows": 300 },
	WorldSize.LARGE: { "width": 4800, "height": 1500, "surface_rows": 350 },
}

## World size in tiles. Set at creation, immutable after.
var world_width: int = 0
var world_height: int = 0
var surface_rows: int = 0  # rows above y=0 for sky/surface

## Tile storage: world position -> TileType value.
var tiles: Dictionary = {}

## Back wall tile storage: world position -> TileType value.
## Back walls are visible behind caves, rendered darker, and mineable.
var back_wall_tiles: Dictionary = {}

## Track which chunks have been modified by the player.
var dirty_chunks: Dictionary = {}  # Vector2i -> bool

## Entrance data for the door/transition system (structures with doors).
var entrances: Dictionary = {}  # Vector2i -> String (scene path)

## Torch positions stored as a set. Key = world tile position, value = true.
var torches: Dictionary = {}


## Configure world dimensions from a WorldSize preset.
func set_world_size(size_enum: int) -> void:
	var preset: Dictionary = WORLD_SIZE_PRESETS.get(size_enum, WORLD_SIZE_PRESETS[WorldSize.SMALL])
	world_width = preset["width"]
	world_height = preset["height"]
	surface_rows = preset["surface_rows"]


## Check if a world position is within the finite world boundaries.
## Returns true if world bounds are not set (legacy/infinite) or if the position is in-bounds.
func is_in_bounds(world_pos: Vector2i) -> bool:
	if world_width == 0:
		return true  # No bounds set (legacy/infinite)
	return (world_pos.x >= 0 and world_pos.x < world_width
		and world_pos.y >= -surface_rows and world_pos.y < world_height - surface_rows)


## Get the tile type at a world position. Returns TileData.TileType.EMPTY if not found.
## Returns DEEP_ROCK (8) for out-of-bounds positions as an unbreakable boundary.
func get_tile(world_pos: Vector2i) -> int:
	if world_width > 0 and not is_in_bounds(world_pos):
		return 8  # DEEP_ROCK — boundary tile
	return tiles.get(world_pos, 0)  # 0 = TileType.EMPTY


## Set a tile at a world position. Setting to EMPTY removes it from the dictionary.
## Marks the containing chunk as dirty (player-modified).
func set_tile(world_pos: Vector2i, tile_type: int) -> void:
	if tile_type == 0:  # TileType.EMPTY
		remove_tile(world_pos)
	else:
		tiles[world_pos] = tile_type
	var chunk_coord := world_to_chunk(world_pos)
	dirty_chunks[chunk_coord] = true


## Remove a tile at a world position (sets it to EMPTY by removing from dict).
## Marks the containing chunk as dirty.
func remove_tile(world_pos: Vector2i) -> void:
	tiles.erase(world_pos)
	var chunk_coord := world_to_chunk(world_pos)
	dirty_chunks[chunk_coord] = true


## Check if a non-empty tile exists at a world position.
## Out-of-bounds positions always count as solid (boundary).
func has_tile(world_pos: Vector2i) -> bool:
	if world_width > 0 and not is_in_bounds(world_pos):
		return true  # Boundary counts as solid
	return tiles.has(world_pos) and tiles[world_pos] != 0


# --- Back wall accessors ---

## Get the back wall tile type at a world position. Returns 0 (EMPTY) if not found.
func get_back_wall(world_pos: Vector2i) -> int:
	return back_wall_tiles.get(world_pos, 0)


## Set a back wall tile at a world position. Marks the containing chunk as dirty.
func set_back_wall(world_pos: Vector2i, tile_type: int) -> void:
	if tile_type == 0:
		remove_back_wall(world_pos)
		return
	back_wall_tiles[world_pos] = tile_type
	var chunk_coord := world_to_chunk(world_pos)
	dirty_chunks[chunk_coord] = true


## Remove a back wall tile at a world position. Marks the containing chunk as dirty.
func remove_back_wall(world_pos: Vector2i) -> void:
	back_wall_tiles.erase(world_pos)
	var chunk_coord := world_to_chunk(world_pos)
	dirty_chunks[chunk_coord] = true


## Check if a back wall tile exists at a world position.
func has_back_wall(world_pos: Vector2i) -> bool:
	return back_wall_tiles.has(world_pos)


## Get all back wall tiles belonging to a chunk as {local_pos: tile_type}.
func get_chunk_back_walls(chunk_coord: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	var origin := chunk_to_world(chunk_coord)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var wpos := origin + Vector2i(x, y)
			if back_wall_tiles.has(wpos):
				result[Vector2i(x, y)] = back_wall_tiles[wpos]
	return result


## Bulk set all back wall tiles for a chunk. EMPTY tiles erase existing entries.
## Does NOT mark the chunk as dirty (used for initial generation / loading).
func set_chunk_back_walls(chunk_coord: Vector2i, walls: Dictionary) -> void:
	var origin := chunk_to_world(chunk_coord)
	for local_pos in walls:
		var wpos: Vector2i = origin + Vector2i(local_pos)
		if walls[local_pos] == 0:  # EMPTY
			back_wall_tiles.erase(wpos)
		else:
			back_wall_tiles[wpos] = walls[local_pos]


# --- Chunk coordinate helpers ---

## Convert a world tile position to the chunk coordinate it belongs to.
## Uses floor division to handle negative coordinates correctly.
static func world_to_chunk(world_pos: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(world_pos.x) / CHUNK_SIZE),
		floori(float(world_pos.y) / CHUNK_SIZE)
	)


## Convert a chunk coordinate to the world tile position of its top-left corner.
static func chunk_to_world(chunk_coord: Vector2i) -> Vector2i:
	return chunk_coord * CHUNK_SIZE


## Get all tiles belonging to a chunk as {local_pos: tile_type}.
func get_chunk_tiles(chunk_coord: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	var origin := chunk_to_world(chunk_coord)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var wpos := origin + Vector2i(x, y)
			if tiles.has(wpos):
				result[Vector2i(x, y)] = tiles[wpos]
	return result


## Bulk set all tiles for a chunk. EMPTY tiles erase existing entries.
## Does NOT mark the chunk as dirty (used for initial generation).
func set_chunk_tiles(chunk_coord: Vector2i, chunk_tiles: Dictionary) -> void:
	var origin := chunk_to_world(chunk_coord)
	for local_pos in chunk_tiles:
		var wpos: Vector2i = origin + Vector2i(local_pos)
		if chunk_tiles[local_pos] == TileDatabase.TileType.EMPTY:
			tiles.erase(wpos)
		else:
			tiles[wpos] = chunk_tiles[local_pos]


## Check if a chunk has been modified by the player.
func is_chunk_dirty(chunk_coord: Vector2i) -> bool:
	return dirty_chunks.get(chunk_coord, false)


# --- Entrance/structure helpers ---

## Set an entrance point (door/transition) at a world position.
func set_entrance(world_pos: Vector2i, target_scene: String) -> void:
	entrances[world_pos] = target_scene


## Get the target scene for an entrance at a world position.
func get_entrance(world_pos: Vector2i) -> String:
	return entrances.get(world_pos, "")


## Check if there's an entrance at a world position.
func has_entrance(world_pos: Vector2i) -> bool:
	return entrances.has(world_pos)


## Add a torch at a world tile position. Marks the chunk as dirty.
func add_torch(world_pos: Vector2i) -> void:
	torches[world_pos] = true
	var chunk_coord := world_to_chunk(world_pos)
	dirty_chunks[chunk_coord] = true


## Remove a torch at a world tile position. Marks the chunk as dirty.
func remove_torch(world_pos: Vector2i) -> void:
	torches.erase(world_pos)
	var chunk_coord := world_to_chunk(world_pos)
	dirty_chunks[chunk_coord] = true


## Check if a torch exists at a world tile position.
func has_torch(world_pos: Vector2i) -> bool:
	return torches.has(world_pos)


## Get all torch world positions within a specific chunk.
func get_chunk_torches(chunk_coord: Vector2i) -> Array:
	var result: Array = []
	var origin := chunk_to_world(chunk_coord)
	var end_pos := origin + Vector2i(CHUNK_SIZE, CHUNK_SIZE)
	for tpos in torches:
		if tpos.x >= origin.x and tpos.x < end_pos.x and tpos.y >= origin.y and tpos.y < end_pos.y:
			result.append(tpos)
	return result
