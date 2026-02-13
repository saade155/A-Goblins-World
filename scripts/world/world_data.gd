## WorldData - Authoritative tile storage.
##
## This is the source of truth for what tiles exist in the world. It is a pure
## data layer — no rendering, no nodes. The TileMapLayer reads from this to
## display tiles, and GameServer modifies this when mining/placing.
##
## Tiles are stored as Dictionary[Vector2i, int] where the int is a TileType enum
## value from TileData. Positions not in the dictionary are considered EMPTY.

class_name WorldData
extends RefCounted

## Tile storage: world position -> TileType value.
var tiles: Dictionary = {}


## Get the tile type at a world position. Returns TileData.TileType.EMPTY if not found.
func get_tile(world_pos: Vector2i) -> int:
	return tiles.get(world_pos, 0)  # 0 = TileType.EMPTY


## Set a tile at a world position. Setting to EMPTY removes it from the dictionary.
func set_tile(world_pos: Vector2i, tile_type: int) -> void:
	if tile_type == 0:  # TileType.EMPTY
		remove_tile(world_pos)
	else:
		tiles[world_pos] = tile_type


## Remove a tile at a world position (sets it to EMPTY by removing from dict).
func remove_tile(world_pos: Vector2i) -> void:
	tiles.erase(world_pos)


## Check if a non-empty tile exists at a world position.
func has_tile(world_pos: Vector2i) -> bool:
	return tiles.has(world_pos) and tiles[world_pos] != 0
