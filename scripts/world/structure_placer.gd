## StructurePlacer - System for placing hand-designed structures into the world.
##
## Structures are predefined tile layouts (rooms, passages, etc.) that get
## stamped into the world, overwriting generated terrain. Used for the spawn
## chamber, boss rooms, and other designed content.
##
## Structure data format:
##   "tiles": Dictionary[Vector2i, int] - local offsets to tile types
##   "entrances": Array[Dictionary] - {position: Vector2i, target_scene: String}
##   "size": Vector2i - bounding box

extends RefCounted
class_name StructurePlacer

## Registered structure templates. name -> structure data dictionary.
var templates: Dictionary = {}


## Register a named structure template for later placement.
func register_template(name: String, data: Dictionary) -> void:
	templates[name] = data


## Place a registered structure into world data at the given position.
## Stamps structure tiles on top of whatever exists, including EMPTY tiles
## to carve out interiors.
func place_structure(world_data: WorldData, world_pos: Vector2i, structure_name: String) -> void:
	var template: Dictionary = templates.get(structure_name, {})
	if template.is_empty():
		push_warning("[StructurePlacer] Template '%s' not found." % structure_name)
		return

	_stamp_structure(world_data, world_pos, template)


## Place a structure directly from data (no registration needed).
## Used for built-in structures like the spawn chamber.
func place_structure_direct(world_data: WorldData, world_pos: Vector2i, structure_data: Dictionary) -> void:
	_stamp_structure(world_data, world_pos, structure_data)


## Internal: stamp a structure's tiles into world data.
func _stamp_structure(world_data: WorldData, world_pos: Vector2i, structure_data: Dictionary) -> void:
	var structure_tiles: Dictionary = structure_data.get("tiles", {})
	for local_pos in structure_tiles:
		var wpos: Vector2i = world_pos + local_pos
		var tile_type: int = structure_tiles[local_pos]
		if tile_type == TileDatabase.TileType.EMPTY:
			# Carve out the terrain - erase the tile
			world_data.tiles.erase(wpos)
		else:
			world_data.tiles[wpos] = tile_type

	# Store entrance data for the door/transition system
	var entrances: Array = structure_data.get("entrances", [])
	for entrance in entrances:
		var epos: Vector2i = world_pos + entrance["position"]
		world_data.set_entrance(epos, entrance.get("target_scene", ""))


## Built-in structure: Spawn Chamber.
## A small cave room where the goblin wakes up.
## Roughly 16 wide x 10 tall, with:
##   - Solid walls/ceiling
##   - Flat floor
##   - An opening on the right side (leads into the world)
##   - A small alcove on the left with dirt for atmosphere
static func create_spawn_chamber() -> Dictionary:
	var tiles: Dictionary = {}
	var width: int = 24
	var height: int = 14

	# Fill everything solid first (stone)
	for x in range(width):
		for y in range(height):
			tiles[Vector2i(x, y)] = TileDatabase.TileType.STONE

	# Carve interior (leave 2-tile walls on sides and top, 2-tile floor)
	for x in range(2, width - 2):
		for y in range(2, height - 2):
			tiles[Vector2i(x, y)] = TileDatabase.TileType.EMPTY

	# Opening on right side (exit into the world) - carve through right wall
	for y in range(4, height - 2):
		tiles[Vector2i(width - 2, y)] = TileDatabase.TileType.EMPTY
		tiles[Vector2i(width - 1, y)] = TileDatabase.TileType.EMPTY

	# Small alcove on left for atmosphere
	tiles[Vector2i(2, height - 3)] = TileDatabase.TileType.DIRT
	tiles[Vector2i(2, height - 4)] = TileDatabase.TileType.DIRT

	return {
		"tiles": tiles,
		"entrances": [],  # No door entrances in spawn chamber
		"size": Vector2i(width, height),
	}
