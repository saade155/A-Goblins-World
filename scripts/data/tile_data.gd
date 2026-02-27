## TileData - Registry of all tile types and their properties.
##
## This autoload provides a central lookup for tile metadata: hardness, drops,
## display color, etc. All tile-related constants and data queries go through here.
## When we add new tile types in later milestones, we only need to update this file.

extends Node

# --- Tile type enum ---
# EMPTY = no tile. Other values correspond to atlas positions in the tile atlas.
enum TileType {
	EMPTY = 0,
	DIRT = 1,
	STONE = 2,
	IRON_ORE = 3,
	HARD_STONE = 4,
	COPPER_ORE = 5,
	GOLD_ORE = 6,
	CRYSTAL = 7,
	DEEP_ROCK = 8,
	SAND = 9,
	SANDSTONE = 10,
	MUD = 11,
	MOSSY_STONE = 12,
	MYCELIUM = 13,
	VOLCANIC_ROCK = 14,
	OBSIDIAN = 15,
	ICE = 16,
	FROZEN_STONE = 17,
	RUBY_ORE = 18,
	EMERALD_ORE = 19,
	GRASS = 20,
	SNOW = 21,
	WATER = 22,
	CLAY = 23,
}

# --- Tile properties ---
# Keyed by TileType. Each entry defines how the tile behaves when mined,
# what it drops, and its placeholder color.
var tile_properties: Dictionary = {
	TileType.DIRT: {
		"name": "Dirt",
		"hardness": 1.0,
		"difficulty_level": 2,
		"drop_item": "dirt",
		"drop_count": 1,
		"color": Color(0.55, 0.35, 0.17),  # Brown
	},
	TileType.STONE: {
		"name": "Stone",
		"hardness": 2.5,
		"difficulty_level": 3,
		"drop_item": "stone",
		"drop_count": 1,
		"color": Color(0.5, 0.5, 0.5),  # Gray
	},
	TileType.IRON_ORE: {
		"name": "Iron Ore",
		"hardness": 4.0,
		"difficulty_level": 4,
		"drop_item": "iron_ore",
		"drop_count": 1,
		"color": Color(0.7, 0.5, 0.35),  # Rusty brown
	},
	TileType.HARD_STONE: {
		"name": "Hard Stone",
		"hardness": 4.0,
		"difficulty_level": 4,
		"drop_item": "hard_stone",
		"drop_count": 1,
		"color": Color(0.45, 0.48, 0.58),  # Gray-blue
	},
	TileType.COPPER_ORE: {
		"name": "Copper Ore",
		"hardness": 3.0,
		"difficulty_level": 4,
		"drop_item": "copper_ore",
		"drop_count": 1,
		"color": Color(0.7, 0.55, 0.3),  # Orange-green
	},
	TileType.GOLD_ORE: {
		"name": "Gold Ore",
		"hardness": 5.0,
		"difficulty_level": 5,
		"drop_item": "gold_ore",
		"drop_count": 1,
		"color": Color(0.85, 0.75, 0.2),  # Yellow
	},
	TileType.CRYSTAL: {
		"name": "Crystal",
		"hardness": 6.0,
		"difficulty_level": 6,
		"drop_item": "crystal",
		"drop_count": 1,
		"color": Color(0.3, 0.8, 0.75),  # Cyan/teal
	},
	TileType.DEEP_ROCK: {
		"name": "Deep Rock",
		"hardness": 8.0,
		"difficulty_level": 7,
		"drop_item": "deep_rock",
		"drop_count": 1,
		"color": Color(0.35, 0.2, 0.45),  # Dark purple
	},
	TileType.SAND: {
		"name": "Sand",
		"hardness": 0.5,
		"difficulty_level": 1,
		"drop_item": "sand",
		"drop_count": 1,
		"color": Color(0.85, 0.78, 0.55),
	},
	TileType.SANDSTONE: {
		"name": "Sandstone",
		"hardness": 1.5,
		"difficulty_level": 3,
		"drop_item": "sandstone",
		"drop_count": 1,
		"color": Color(0.78, 0.65, 0.42),
	},
	TileType.MUD: {
		"name": "Mud",
		"hardness": 0.7,
		"difficulty_level": 2,
		"drop_item": "mud",
		"drop_count": 1,
		"color": Color(0.35, 0.28, 0.18),
	},
	TileType.MOSSY_STONE: {
		"name": "Mossy Stone",
		"hardness": 2.0,
		"difficulty_level": 3,
		"drop_item": "mossy_stone",
		"drop_count": 1,
		"color": Color(0.35, 0.55, 0.30),
	},
	TileType.MYCELIUM: {
		"name": "Mycelium",
		"hardness": 1.2,
		"difficulty_level": 3,
		"drop_item": "mycelium",
		"drop_count": 1,
		"color": Color(0.60, 0.45, 0.65),
	},
	TileType.VOLCANIC_ROCK: {
		"name": "Volcanic Rock",
		"hardness": 5.0,
		"difficulty_level": 5,
		"drop_item": "volcanic_rock",
		"drop_count": 1,
		"color": Color(0.3, 0.15, 0.1),
	},
	TileType.OBSIDIAN: {
		"name": "Obsidian",
		"hardness": 10.0,
		"difficulty_level": 8,
		"drop_item": "obsidian",
		"drop_count": 1,
		"color": Color(0.1, 0.05, 0.15),
	},
	TileType.ICE: {
		"name": "Ice",
		"hardness": 1.5,
		"difficulty_level": 3,
		"drop_item": "ice",
		"drop_count": 1,
		"color": Color(0.7, 0.85, 0.95),
	},
	TileType.FROZEN_STONE: {
		"name": "Frozen Stone",
		"hardness": 3.5,
		"difficulty_level": 4,
		"drop_item": "frozen_stone",
		"drop_count": 1,
		"color": Color(0.5, 0.6, 0.75),
	},
	TileType.RUBY_ORE: {
		"name": "Ruby Ore",
		"hardness": 6.0,
		"difficulty_level": 6,
		"drop_item": "ruby_ore",
		"drop_count": 1,
		"color": Color(0.8, 0.15, 0.2),
	},
	TileType.EMERALD_ORE: {
		"name": "Emerald Ore",
		"hardness": 5.0,
		"difficulty_level": 5,
		"drop_item": "emerald_ore",
		"drop_count": 1,
		"color": Color(0.15, 0.7, 0.3),
	},
	TileType.GRASS: {
		"name": "Grass",
		"hardness": 0.8,
		"difficulty_level": 2,
		"drop_item": "grass",
		"drop_count": 1,
		"color": Color(0.3, 0.65, 0.2),
	},
	TileType.SNOW: {
		"name": "Snow",
		"hardness": 0.5,
		"difficulty_level": 1,
		"drop_item": "snow",
		"drop_count": 1,
		"color": Color(0.9, 0.93, 0.97),
	},
	TileType.WATER: {
		"name": "Water",
		"hardness": 0.0,
		"difficulty_level": 0,
		"drop_item": "",
		"drop_count": 0,
		"color": Color(0.2, 0.4, 0.8),
	},
	TileType.CLAY: {
		"name": "Clay",
		"hardness": 1.2,
		"difficulty_level": 3,
		"drop_item": "clay",
		"drop_count": 1,
		"color": Color(0.65, 0.45, 0.35),
	},
}

# Maps item string names back to TileType for placement.
var item_to_tile: Dictionary = {
	"dirt": TileType.DIRT,
	"stone": TileType.STONE,
	"iron_ore": TileType.IRON_ORE,
	"hard_stone": TileType.HARD_STONE,
	"copper_ore": TileType.COPPER_ORE,
	"gold_ore": TileType.GOLD_ORE,
	"crystal": TileType.CRYSTAL,
	"deep_rock": TileType.DEEP_ROCK,
	"sand": TileType.SAND,
	"sandstone": TileType.SANDSTONE,
	"mud": TileType.MUD,
	"mossy_stone": TileType.MOSSY_STONE,
	"mycelium": TileType.MYCELIUM,
	"volcanic_rock": TileType.VOLCANIC_ROCK,
	"obsidian": TileType.OBSIDIAN,
	"ice": TileType.ICE,
	"frozen_stone": TileType.FROZEN_STONE,
	"ruby_ore": TileType.RUBY_ORE,
	"emerald_ore": TileType.EMERALD_ORE,
	"grass": TileType.GRASS,
	"snow": TileType.SNOW,
	"clay": TileType.CLAY,
}

# --- Autotile support ---
# Bitmask convention: bit=1 means same-type neighbor IS present.
# Bit 0 = North, Bit 1 = East, Bit 2 = South, Bit 3 = West.

# Maps 4-bit cardinal bitmask → atlas coords (0-indexed) within the autotile sheet.
const BITMASK_TO_ATLAS: Dictionary = {
	0:  Vector2i(6, 6),  # Alone
	1:  Vector2i(6, 3),  # Only N → bot cap
	2:  Vector2i(1, 6),  # Only E → left cap
	3:  Vector2i(1, 3),  # N+E → BL corner
	4:  Vector2i(6, 1),  # Only S → top cap
	5:  Vector2i(6, 2),  # N+S → vert bar
	6:  Vector2i(1, 1),  # E+S → TL corner
	7:  Vector2i(1, 2),  # N+E+S → Left edge
	8:  Vector2i(3, 6),  # Only W → right cap
	9:  Vector2i(3, 3),  # N+W → BR corner
	10: Vector2i(2, 6),  # E+W → horiz bar
	11: Vector2i(2, 3),  # N+E+W → Bot edge
	12: Vector2i(3, 1),  # S+W → TR corner
	13: Vector2i(3, 2),  # N+S+W → Right edge
	14: Vector2i(2, 1),  # E+S+W → Top edge
	15: Vector2i(2, 2),  # All → Center
}


# Tile types that have hand-drawn autotile sprite sheets.
# TileType → {path: String, block_offset: Vector2i}
var autotile_textures: Dictionary = {
	TileType.STONE: {"path": "res://assets/tilesets/stone_tiles.png", "block_offset": Vector2i(0, 0)},
	TileType.DIRT: {"path": "res://assets/tilesets/dirt_tiles.png", "block_offset": Vector2i(0, 0)},
}

# Populated at runtime by ChunkManager when building the TileSet.
# TileType → source_id (int)
var autotile_source_ids: Dictionary = {}

# --- Edge overlay system ---

## Inner corner overlays (col 8, rows 0-7). Placed on diagonal neighbor cell.
## Keys are from the TILE's perspective: which diagonal is empty.
## 2 variants per direction, noise-selected.
const INNER_CORNER_OVERLAY_ATLAS: Dictionary = {
	"SE": [Vector2i(8, 0), Vector2i(8, 4)],  # ITL in spec
	"SW": [Vector2i(8, 1), Vector2i(8, 5)],  # ITR in spec
	"NE": [Vector2i(8, 2), Vector2i(8, 6)],  # IBL in spec
	"NW": [Vector2i(8, 3), Vector2i(8, 7)],  # IBR in spec
}

## Edge direction enum.
enum EdgeDir { TOP, RIGHT, BOTTOM, LEFT }

## Edge overlay atlas coordinates indexed by [direction][context].
## Context is determined by perpendicular neighbors of the source tile.
## For TOP/BOTTOM: perpendicular = E and W neighbors.
## For LEFT/RIGHT: perpendicular = N and S neighbors.
## Context key: (perp1_filled << 2) | (perp2_filled << 1) | parallel_filled
##   TOP/BOTTOM: perp1=E, perp2=W, parallel=S/N (does source extend away from edge?)
##   LEFT/RIGHT: perp1=S, perp2=N, parallel=E/W (does source extend away from edge?)
const EDGE_CONTEXT_ATLAS: Dictionary = {
	EdgeDir.TOP: {
		# key: (has_E << 2) | (has_W << 1) | has_S → atlas coord
		0: Vector2i(6, 5),  # alone narrow
		1: Vector2i(6, 0),  # pillar narrow (extends S)
		2: Vector2i(3, 5),  # bar right cap (W only)
		3: Vector2i(3, 0),  # block right end (W+S)
		4: Vector2i(1, 5),  # bar left cap (E only)
		5: Vector2i(1, 0),  # block left end (E+S)
		6: Vector2i(2, 5),  # bar center (E+W)
		7: Vector2i(2, 0),  # block center (E+W+S)
	},
	EdgeDir.BOTTOM: {
		# key: (has_E << 2) | (has_W << 1) | has_N → atlas coord
		0: Vector2i(6, 7),  # alone narrow
		1: Vector2i(6, 4),  # pillar narrow (extends N)
		2: Vector2i(3, 7),  # bar right cap (W only)
		3: Vector2i(3, 4),  # block right end (W+N)
		4: Vector2i(1, 7),  # bar left cap (E only)
		5: Vector2i(1, 4),  # block left end (E+N)
		6: Vector2i(2, 7),  # bar center (E+W)
		7: Vector2i(2, 4),  # block center (E+W+N)
	},
	EdgeDir.LEFT: {
		# key: (has_S << 2) | (has_N << 1) | has_E → atlas coord
		0: Vector2i(5, 6),  # alone narrow
		1: Vector2i(0, 6),  # horiz pillar narrow (extends E)
		2: Vector2i(5, 3),  # vert pillar bot cap (N only)
		3: Vector2i(0, 3),  # block bot end (N+E)
		4: Vector2i(5, 1),  # vert pillar top cap (S only)
		5: Vector2i(0, 1),  # block top end (S+E)
		6: Vector2i(5, 2),  # vert pillar center (S+N)
		7: Vector2i(0, 2),  # block center (S+N+E)
	},
	EdgeDir.RIGHT: {
		# key: (has_S << 2) | (has_N << 1) | has_W → atlas coord
		0: Vector2i(7, 6),  # alone narrow
		1: Vector2i(4, 6),  # horiz pillar narrow (extends W)
		2: Vector2i(7, 3),  # vert pillar bot cap (N only)
		3: Vector2i(4, 3),  # block bot end (N+W)
		4: Vector2i(7, 1),  # vert pillar top cap (S only)
		5: Vector2i(4, 1),  # block top end (S+W)
		6: Vector2i(7, 2),  # vert pillar center (S+N)
		7: Vector2i(4, 2),  # block center (S+N+W)
	},
}

## Outer corner overlays (placed on diagonal empty neighbor cell).
## 4 variants per corner from the four quadrants of the spatial grid.
const CORNER_ATLAS: Dictionary = {
	"TL": [Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 5), Vector2i(5, 5)],
	"TR": [Vector2i(4, 0), Vector2i(7, 0), Vector2i(4, 5), Vector2i(7, 5)],
	"BL": [Vector2i(0, 4), Vector2i(5, 4), Vector2i(0, 7), Vector2i(5, 7)],
	"BR": [Vector2i(4, 4), Vector2i(7, 4), Vector2i(4, 7), Vector2i(7, 7)],
}

## Maps bitmask values to their variant row (cols 9-15).
## Only the 3x3 block positions get variants.
const VARIANT_ROWS: Dictionary = {
	6:  0,  # TL corner
	14: 1,  # Top edge
	12: 2,  # TR corner
	7:  3,  # Left edge
	15: 4,  # Center
	13: 5,  # Right edge
	3:  6,  # BL corner
	11: 7,  # Bot edge
	9:  8,  # BR corner
}

## Rarity tier boundaries for variant selection.
## Common: cols 9-11 (3 variants, ~60%)
## Uncommon: cols 12-13 (2 variants, ~25%)
## Rare: cols 14-15 (2 variants, ~15%)
const VARIANT_COLS: Array[int] = [9, 10, 11, 12, 13, 14, 15]

## Maps edge direction to cardinal offset.
const EDGE_DIR_OFFSETS: Dictionary = {
	EdgeDir.TOP: Vector2i(0, -1),
	EdgeDir.RIGHT: Vector2i(1, 0),
	EdgeDir.BOTTOM: Vector2i(0, 1),
	EdgeDir.LEFT: Vector2i(-1, 0),
}

## Maps edge direction to overlay layer name.
const EDGE_DIR_LAYER: Dictionary = {
	EdgeDir.TOP: "edge_floor",
	EdgeDir.RIGHT: "edge_wall_r",
	EdgeDir.BOTTOM: "edge_ceiling",
	EdgeDir.LEFT: "edge_wall_l",
}

# --- Variant noise ---

## Noise generator for deterministic per-tile variant selection.
var _variant_noise: FastNoiseLite = null

## Which tile types have edge overlay art (auto-detected at runtime).
var edge_capable_types: Dictionary = {}


func _ready() -> void:
	print("[TileData] Initialized with %d tile types." % tile_properties.size())


## Get all registered tile types (excludes EMPTY). Useful for iteration.
func get_tile_types() -> Array:
	return tile_properties.keys()


## Get the full properties dictionary for a tile type. Returns empty dict for EMPTY/unknown.
func get_properties(tile_type: int) -> Dictionary:
	return tile_properties.get(tile_type, {})


## Get the hardness value for a tile type. Returns 0.0 for EMPTY/unknown.
func get_hardness(tile_type: int) -> float:
	var props := get_properties(tile_type)
	return props.get("hardness", 0.0)


## Get the difficulty level for a tile type (1-10 scale). Returns 0 for EMPTY/unknown.
func get_difficulty(tile_type: int) -> int:
	var props := get_properties(tile_type)
	return props.get("difficulty_level", 0)


## Get the drop info for a tile type. Returns {"item": String, "count": int}.
func get_drop(tile_type: int) -> Dictionary:
	var props := get_properties(tile_type)
	if props.is_empty():
		return {"item": "", "count": 0}
	return {"item": props.get("drop_item", ""), "count": props.get("drop_count", 0)}


## Get the atlas coordinates for a tile type on the tile atlas texture.
## Returns Vector2i(index, 0) where index matches the tile_properties insertion order.
## Returns Vector2i(-1, -1) for EMPTY or unknown types.
func get_atlas_coords(tile_type: int) -> Vector2i:
	# Atlas coords map directly: TileType value - 1 = atlas index (since EMPTY=0 is skipped)
	# DIRT=1 -> (0,0), STONE=2 -> (1,0), IRON_ORE=3 -> (2,0), etc.
	if tile_type <= TileType.EMPTY or tile_type > TileType.CLAY:
		return Vector2i(-1, -1)
	return Vector2i(tile_type - 1, 0)


## Get the TileType from an item name string. Returns EMPTY if not found.
func get_tile_from_item(item_name: String) -> int:
	return item_to_tile.get(item_name, TileType.EMPTY)


## Check if a tile type has an autotile sprite sheet registered.
func has_autotile(tile_type: int) -> bool:
	return autotile_textures.has(tile_type)


## Get the TileSet source ID for an autotiled tile type.
## Returns -1 if not registered or not yet built.
func get_autotile_source_id(tile_type: int) -> int:
	return autotile_source_ids.get(tile_type, -1)


# --- Edge overlay system ---

## Initialize the variant noise from the world seed. Call once after world loads.
func initialize_variant_noise(world_seed: int) -> void:
	_variant_noise = FastNoiseLite.new()
	_variant_noise.noise_type = FastNoiseLite.TYPE_VALUE
	_variant_noise.seed = world_seed + 9999
	_variant_noise.frequency = 0.5


## Get a deterministic variant index for a world position.
func get_variant_index(world_pos: Vector2i, variant_count: int) -> int:
	if _variant_noise == null or variant_count <= 1:
		return 0
	var noise_val: float = _variant_noise.get_noise_2d(float(world_pos.x), float(world_pos.y))
	var normalized: float = (noise_val + 1.0) / 2.0
	return clampi(int(normalized * variant_count), 0, variant_count - 1)


## Get the edge overlay atlas coords for a direction based on source tile context.
## perp1 and perp2 are whether the perpendicular neighbors are filled.
## parallel is whether the source tile extends away from the edge (depth).
## For TOP: perp1=E, perp2=W, parallel=S
## For BOTTOM: perp1=E, perp2=W, parallel=N
## For LEFT: perp1=S, perp2=N, parallel=E
## For RIGHT: perp1=S, perp2=N, parallel=W
func get_edge_coords(direction: int, perp1_filled: bool, perp2_filled: bool, parallel_filled: bool) -> Vector2i:
	var context_key: int = (int(perp1_filled) << 2) | (int(perp2_filled) << 1) | int(parallel_filled)
	return EDGE_CONTEXT_ATLAS[direction][context_key]


## Get outer corner atlas coords for a corner position.
func get_corner_coords(corner_name: String, world_pos: Vector2i) -> Vector2i:
	var variants: Array = CORNER_ATLAS[corner_name]
	var idx: int = get_variant_index(world_pos, variants.size())
	return variants[idx]


## Get corner atlas coords based on the source tile's neighbor context.
## adj_vertical: true if source tile has a solid neighbor in the vertical direction adjacent to this corner
## adj_horizontal: true if source tile has a solid neighbor in the horizontal direction adjacent to this corner
## For TL corner: adj_vertical=has_N, adj_horizontal=has_W
## For TR corner: adj_vertical=has_N, adj_horizontal=has_E
## For BL corner: adj_vertical=has_S, adj_horizontal=has_W
## For BR corner: adj_vertical=has_S, adj_horizontal=has_E
func get_corner_coords_contextual(corner_name: String, adj_vertical: bool, adj_horizontal: bool) -> Vector2i:
	var variants: Array = CORNER_ATLAS[corner_name]
	# Index mapping:
	# 0 = block (both present), 1 = pillar (vertical only), 2 = bar (horizontal only), 3 = alone (neither)
	var idx: int = 0
	if adj_vertical and adj_horizontal:
		idx = 0  # block
	elif adj_vertical:
		idx = 1  # pillar
	elif adj_horizontal:
		idx = 2  # bar
	else:
		idx = 3  # alone
	return variants[idx]


## Get inner corner overlay atlas coords for a diagonal direction.
func get_inner_corner_overlay_coords(diagonal_name: String, world_pos: Vector2i) -> Vector2i:
	var variants: Array = INNER_CORNER_OVERLAY_ATLAS.get(diagonal_name, [])
	if variants.is_empty():
		return Vector2i(-1, -1)
	var idx: int = get_variant_index(world_pos, variants.size())
	return variants[idx]


## Get variant atlas coords for a bitmask at a world position.
## Returns Vector2i(-1, -1) if no variant row exists for the bitmask.
func get_variant_coords(bitmask: int, world_pos: Vector2i) -> Vector2i:
	if not VARIANT_ROWS.has(bitmask):
		return Vector2i(-1, -1)
	var row: int = VARIANT_ROWS[bitmask]
	if _variant_noise == null:
		return Vector2i(-1, -1)
	var noise_val: float = _variant_noise.get_noise_2d(float(world_pos.x), float(world_pos.y))
	var normalized: float = (noise_val + 1.0) / 2.0
	# Weighted selection: 0-60% common, 60-85% uncommon, 85-100% rare
	var col: int
	if normalized < 0.6:
		# Common: cols 9-11
		var sub_idx: int = int(normalized / 0.6 * 3.0)
		col = 9 + clampi(sub_idx, 0, 2)
	elif normalized < 0.85:
		# Uncommon: cols 12-13
		var sub_idx: int = int((normalized - 0.6) / 0.25 * 2.0)
		col = 12 + clampi(sub_idx, 0, 1)
	else:
		# Rare: cols 14-15
		var sub_idx: int = int((normalized - 0.85) / 0.15 * 2.0)
		col = 14 + clampi(sub_idx, 0, 1)
	return Vector2i(col, row)


## Check if a tile type has edge overlay art.
func has_edge_overlay(tile_type: int) -> bool:
	return edge_capable_types.get(tile_type, false)
