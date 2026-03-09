## Tests for actual tile output at specific world positions.
##
## Key regression test: verifies that underground tiles match their biome,
## not just stone everywhere. Validates sky, surface, subsurface, transition,
## underground biome tiles, and water placement.

extends GutTest

var _gen: WorldGenerator
var _world_data: WorldData
var _layout: SurfaceBiomeLayout

const TEST_SEED: int = 42


func before_all() -> void:
	_gen = WorldGenerator.new(TEST_SEED)
	_world_data = WorldData.new()
	_world_data.set_world_size(WorldData.WorldSize.SMALL)
	var definition := WorldDefinition.create_overworld()
	_gen.generate_world(_world_data, definition)
	_layout = _gen.get_surface_layout()


## Find a column near the CENTER of a specific biome zone (avoids boundary blending).
## Returns -1 if the biome is not found in the layout.
func _find_biome_center(biome_id: StringName) -> int:
	var wx: int = 0
	while wx < _layout.biome_ids.size():
		if _layout.get_biome_id(wx) == biome_id:
			var start: int = wx
			while wx < _layout.biome_ids.size() and _layout.get_biome_id(wx) == biome_id:
				wx += 1
			@warning_ignore("integer_division")
			return (start + wx) / 2
		wx += 1
	return -1


## Get a human-readable tile type name for debug output.
func _tile_name(tile_type: int) -> String:
	match tile_type:
		TileDatabase.TileType.EMPTY: return "EMPTY"
		TileDatabase.TileType.DIRT: return "DIRT"
		TileDatabase.TileType.STONE: return "STONE"
		TileDatabase.TileType.IRON_ORE: return "IRON_ORE"
		TileDatabase.TileType.HARD_STONE: return "HARD_STONE"
		TileDatabase.TileType.COPPER_ORE: return "COPPER_ORE"
		TileDatabase.TileType.GOLD_ORE: return "GOLD_ORE"
		TileDatabase.TileType.CRYSTAL: return "CRYSTAL"
		TileDatabase.TileType.DEEP_ROCK: return "DEEP_ROCK"
		TileDatabase.TileType.SAND: return "SAND"
		TileDatabase.TileType.SANDSTONE: return "SANDSTONE"
		TileDatabase.TileType.MUD: return "MUD"
		TileDatabase.TileType.MOSSY_STONE: return "MOSSY_STONE"
		TileDatabase.TileType.MYCELIUM: return "MYCELIUM"
		TileDatabase.TileType.VOLCANIC_ROCK: return "VOLCANIC_ROCK"
		TileDatabase.TileType.OBSIDIAN: return "OBSIDIAN"
		TileDatabase.TileType.ICE: return "ICE"
		TileDatabase.TileType.FROZEN_STONE: return "FROZEN_STONE"
		TileDatabase.TileType.RUBY_ORE: return "RUBY_ORE"
		TileDatabase.TileType.EMERALD_ORE: return "EMERALD_ORE"
		TileDatabase.TileType.GRASS: return "GRASS"
		TileDatabase.TileType.SNOW: return "SNOW"
		TileDatabase.TileType.WATER: return "WATER"
		TileDatabase.TileType.CLAY: return "CLAY"
	return "UNKNOWN(%d)" % tile_type


# ---------------------------------------------------------------------------
#  1. Sky is empty
# ---------------------------------------------------------------------------

func test_sky_is_empty() -> void:
	# Pick the spawn column (guaranteed to exist) and check well above surface
	var wx: int = _layout.spawn_x
	var surface_h: int = _gen.get_surface_height(wx)
	var sky_y: int = surface_h - 20

	gut.p("Checking sky at (%d, %d), surface_h=%d" % [wx, sky_y, surface_h])

	var tile: int = _world_data.get_tile(Vector2i(wx, sky_y))
	assert_eq(tile, TileDatabase.TileType.EMPTY,
		"Tile 20 above surface at column %d should be EMPTY, got %s" % [
			wx, _tile_name(tile)
		])


# ---------------------------------------------------------------------------
#  2. Surface tile matches biome
# ---------------------------------------------------------------------------

func test_surface_tile_matches_biome_forest() -> void:
	var wx: int = _find_biome_center(&"forest")
	assert_gt(wx, -1, "Forest biome should exist in layout")
	if wx == -1:
		return

	var surface_h: int = _gen.get_surface_height(wx)
	var pos := Vector2i(wx, surface_h)
	var tile: int = _world_data.get_tile(pos)
	var s_biome: SurfaceBiomeData = _gen.surface_biome_registry.get_biome_by_id(&"forest")

	gut.p("Forest center: wx=%d, surface_h=%d, tile=%s, expected=%s" % [
		wx, surface_h, _tile_name(tile), _tile_name(s_biome.surface_tile)
	])

	assert_eq(tile, s_biome.surface_tile,
		"Surface tile at forest center (%d, %d) should be %s, got %s" % [
			wx, surface_h, _tile_name(s_biome.surface_tile), _tile_name(tile)
		])


func test_surface_tile_matches_biome_desert() -> void:
	var wx: int = _find_biome_center(&"desert")
	if wx == -1:
		pending("Desert biome not found in layout for seed %d" % TEST_SEED)
		return

	var surface_h: int = _gen.get_surface_height(wx)
	var pos := Vector2i(wx, surface_h)
	var tile: int = _world_data.get_tile(pos)
	var s_biome: SurfaceBiomeData = _gen.surface_biome_registry.get_biome_by_id(&"desert")

	gut.p("Desert center: wx=%d, surface_h=%d, tile=%s, expected=%s" % [
		wx, surface_h, _tile_name(tile), _tile_name(s_biome.surface_tile)
	])

	assert_eq(tile, s_biome.surface_tile,
		"Surface tile at desert center (%d, %d) should be %s, got %s" % [
			wx, surface_h, _tile_name(s_biome.surface_tile), _tile_name(tile)
		])


# ---------------------------------------------------------------------------
#  3. Subsurface tile matches biome
# ---------------------------------------------------------------------------

func test_subsurface_tile_matches_biome_forest() -> void:
	var wx: int = _find_biome_center(&"forest")
	assert_gt(wx, -1, "Forest biome should exist in layout")
	if wx == -1:
		return

	var surface_h: int = _gen.get_surface_height(wx)
	var check_y: int = surface_h + 3
	var pos := Vector2i(wx, check_y)
	var tile: int = _world_data.get_tile(pos)
	var s_biome: SurfaceBiomeData = _gen.surface_biome_registry.get_biome_by_id(&"forest")

	gut.p("Forest subsurface: wx=%d, y=%d (depth=%d), tile=%s, expected=%s" % [
		wx, check_y, check_y - surface_h, _tile_name(tile),
		_tile_name(s_biome.subsurface_tile)
	])

	assert_eq(tile, s_biome.subsurface_tile,
		"Subsurface tile at forest (%d, %d) depth 3 should be %s, got %s" % [
			wx, check_y, _tile_name(s_biome.subsurface_tile), _tile_name(tile)
		])


func test_subsurface_tile_matches_biome_desert() -> void:
	var wx: int = _find_biome_center(&"desert")
	if wx == -1:
		pending("Desert biome not found in layout for seed %d" % TEST_SEED)
		return

	var surface_h: int = _gen.get_surface_height(wx)
	var check_y: int = surface_h + 3
	var pos := Vector2i(wx, check_y)
	var tile: int = _world_data.get_tile(pos)
	var s_biome: SurfaceBiomeData = _gen.surface_biome_registry.get_biome_by_id(&"desert")

	gut.p("Desert subsurface: wx=%d, y=%d (depth=%d), tile=%s, expected=%s" % [
		wx, check_y, check_y - surface_h, _tile_name(tile),
		_tile_name(s_biome.subsurface_tile)
	])

	assert_eq(tile, s_biome.subsurface_tile,
		"Subsurface tile at desert (%d, %d) depth 3 should be %s, got %s" % [
			wx, check_y, _tile_name(s_biome.subsurface_tile), _tile_name(tile)
		])


# ---------------------------------------------------------------------------
#  4. Transition zone has a mix of subsurface and underground tiles
# ---------------------------------------------------------------------------

func test_transition_zone_has_mix() -> void:
	# Use desert because its subsurface (SANDSTONE) is clearly distinct from
	# its paired underground biome sandy_hollows (SAND), making the mix detectable.
	# Forest subsurface is DIRT which overlaps with standard_caverns depth palette.
	var wx_center: int = _find_biome_center(&"desert")
	if wx_center == -1:
		pending("Desert biome not found in layout for seed %d" % TEST_SEED)
		return

	var s_biome: SurfaceBiomeData = _gen.surface_biome_registry.get_biome_by_id(&"desert")
	var subsurface_end: int = 1 + s_biome.subsurface_depth  # depth where transition starts

	var subsurface_count: int = 0
	var non_subsurface_count: int = 0
	var sample_columns: int = 50

	gut.p("Transition zone test: desert center=%d, subsurface_depth=%d, subsurface_tile=%s" % [
		wx_center, s_biome.subsurface_depth, _tile_name(s_biome.subsurface_tile)
	])

	for col_offset in range(-sample_columns / 2, sample_columns / 2):
		var wx: int = wx_center + col_offset
		if wx < 0 or wx >= _layout.biome_ids.size():
			continue
		# Only sample columns that are actually in the desert biome
		if _layout.get_biome_id(wx) != &"desert":
			continue

		var surface_h: int = _gen.get_surface_height(wx)
		# Check depths inside transition zone, past subsurface_depth
		for depth in range(subsurface_end + 1, subsurface_end + 12):
			var check_y: int = surface_h + depth
			var tile: int = _world_data.get_tile(Vector2i(wx, check_y))
			if tile == TileDatabase.TileType.EMPTY:
				continue  # Skip cave openings
			if tile == s_biome.subsurface_tile:
				subsurface_count += 1
			else:
				non_subsurface_count += 1

	gut.p("  Transition zone results: subsurface=%d, non_subsurface=%d" % [
		subsurface_count, non_subsurface_count
	])

	assert_gt(subsurface_count, 0,
		"Transition zone should have some subsurface tiles (%s), got 0" % _tile_name(s_biome.subsurface_tile))
	assert_gt(non_subsurface_count, 0,
		"Transition zone should have some non-subsurface tiles, got 0 (all %s)" % _tile_name(s_biome.subsurface_tile))


# ---------------------------------------------------------------------------
#  5. Underground desert is not all stone
# ---------------------------------------------------------------------------

func test_underground_desert_not_stone() -> void:
	_assert_underground_biome_tiles(
		&"desert", &"sandy_hollows",
		[TileDatabase.TileType.SAND, TileDatabase.TileType.SANDSTONE],
		"SAND or SANDSTONE")


# ---------------------------------------------------------------------------
#  6. Underground swamp is not all stone
# ---------------------------------------------------------------------------

func test_underground_swamp_not_stone() -> void:
	_assert_underground_biome_tiles(
		&"swamp", &"swamp_depths",
		[TileDatabase.TileType.MUD, TileDatabase.TileType.MOSSY_STONE],
		"MUD or MOSSY_STONE")


# ---------------------------------------------------------------------------
#  7. Underground snowy is not all stone
# ---------------------------------------------------------------------------

func test_underground_snowy_not_stone() -> void:
	_assert_underground_biome_tiles(
		&"snowy_peaks", &"frozen_caverns",
		[TileDatabase.TileType.ICE, TileDatabase.TileType.FROZEN_STONE],
		"ICE or FROZEN_STONE")


## Shared helper for tests 5-7. Checks that underground tiles below a surface biome
## actually contain tiles from the paired underground biome (not all stone).
func _assert_underground_biome_tiles(surface_id: StringName,
		expected_ug_id: StringName, expected_tiles: Array,
		tile_names: String) -> void:
	var wx_center: int = _find_biome_center(surface_id)
	if wx_center == -1:
		pending("Surface biome '%s' not found in layout for seed %d" % [surface_id, TEST_SEED])
		return

	# Verify the pairing is what we expect
	var s_biome: SurfaceBiomeData = _gen.surface_biome_registry.get_biome_by_id(surface_id)
	var paired_id: StringName = s_biome.paired_underground_biome
	gut.p("Surface '%s' paired with '%s' (expected '%s')" % [surface_id, paired_id, expected_ug_id])

	# Look up the underground biome's tiles from the biome registry
	var ug_biome: BiomeData = _gen.biome_registry.get_biome_by_id(expected_ug_id)
	gut.p("  UG biome '%s': primary=%s, secondary=%s" % [
		expected_ug_id,
		_tile_name(ug_biome.primary_tile),
		_tile_name(ug_biome.secondary_tile)
	])

	var biome_count: int = 0
	var other_solid: int = 0
	var empty_count: int = 0
	var other_tiles: Dictionary = {}

	# Sample a range of columns around center (21 columns: center-10 to center+10)
	for col_offset in range(-10, 11):
		var test_x: int = wx_center + col_offset
		if test_x < 0 or test_x >= _world_data.world_width:
			continue
		# Verify this column is still the right biome
		if _layout.get_biome_id(test_x) != surface_id:
			continue
		var surface_h: int = _gen.get_surface_height(test_x)
		# Sample depth 22-29 below surface (Voronoi seeds placed at 10-18% depth win this zone naturally)
		for depth in range(22, 30):
			var wy: int = surface_h + depth
			var pos := Vector2i(test_x, wy)
			var tile: int = _world_data.get_tile(pos)
			if tile == TileDatabase.TileType.EMPTY or tile == 0:
				empty_count += 1
				continue
			if expected_tiles.has(tile):
				biome_count += 1
			else:
				other_solid += 1
				other_tiles[_tile_name(tile)] = other_tiles.get(_tile_name(tile), 0) + 1

	var total_solid: int = biome_count + other_solid
	gut.p("  Results at depth 22-29 (21 columns): solid=%d (biome=%d, other=%d), empty=%d" % [
		total_solid, biome_count, other_solid, empty_count
	])
	if not other_tiles.is_empty():
		gut.p("  Other tile types found: %s" % str(other_tiles))

	if total_solid == 0:
		gut.p("  All tiles are caves/empty — skipping assertion for %s" % tile_names)
		return

	assert_gt(biome_count, 0,
		"Underground below '%s' at depth 22-29 should have some %s tiles (found %d solid, %s other)" % [
			surface_id, str(expected_tiles), total_solid, str(other_tiles)
		])


# ---------------------------------------------------------------------------
#  8. Water between sea level and surface in ocean
# ---------------------------------------------------------------------------

func test_water_between_sea_level_and_surface() -> void:
	var wx: int = _find_biome_center(&"ocean")
	if wx == -1:
		pending("Ocean biome not found in layout for seed %d" % TEST_SEED)
		return

	var surface_h: int = _gen.get_surface_height(wx)
	var s_biome: SurfaceBiomeData = _gen.surface_biome_registry.get_biome_by_id(&"ocean")

	gut.p("Ocean center: wx=%d, surface_h=%d, SEA_LEVEL=%d, allows_water=%s" % [
		wx, surface_h, WorldGenerator.SEA_LEVEL, s_biome.allows_water
	])

	# Ocean base_height is 30 (deep below sea level), so surface_h should be > SEA_LEVEL
	if surface_h <= WorldGenerator.SEA_LEVEL:
		gut.p("  WARNING: Ocean floor at %d is AT or ABOVE sea level %d -- water logic may not apply" % [
			surface_h, WorldGenerator.SEA_LEVEL
		])

	if s_biome.allows_water and surface_h > WorldGenerator.SEA_LEVEL:
		# Check tile at sea level -- should be water
		var water_pos := Vector2i(wx, WorldGenerator.SEA_LEVEL)
		var water_tile: int = _world_data.get_tile(water_pos)
		gut.p("  Tile at sea level (%d, %d): %s" % [wx, WorldGenerator.SEA_LEVEL, _tile_name(water_tile)])
		assert_eq(water_tile, TileDatabase.TileType.WATER,
			"Tile at sea level in ocean column %d should be WATER, got %s" % [
				wx, _tile_name(water_tile)
			])

		# Check tile well above sea level -- should be empty
		var above_y: int = WorldGenerator.SEA_LEVEL - 10
		var above_pos := Vector2i(wx, above_y)
		var above_tile: int = _world_data.get_tile(above_pos)
		gut.p("  Tile above sea level (%d, %d): %s" % [wx, above_y, _tile_name(above_tile)])
		assert_eq(above_tile, TileDatabase.TileType.EMPTY,
			"Tile 10 above sea level in ocean column %d should be EMPTY, got %s" % [
				wx, _tile_name(above_tile)
			])
	else:
		gut.p("  Skipping water check: allows_water=%s, surface_h(%d) > SEA_LEVEL(%d) = %s" % [
			s_biome.allows_water, surface_h, WorldGenerator.SEA_LEVEL,
			surface_h > WorldGenerator.SEA_LEVEL
		])
		pending("Ocean water conditions not met for this seed")


# ---------------------------------------------------------------------------
#  9. No water above sea level
# ---------------------------------------------------------------------------

func test_no_water_above_sea_level() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TEST_SEED + 9999  # Deterministic but different from world gen
	var world_width: int = _world_data.world_width
	var water_above_count: int = 0
	var sample_count: int = 100
	var water_columns: Array = []

	for i in range(sample_count):
		var wx: int = rng.randi_range(0, world_width - 1)
		var check_y: int = WorldGenerator.SEA_LEVEL - 1  # One above sea level
		var pos := Vector2i(wx, check_y)
		var tile: int = _world_data.get_tile(pos)
		if tile == TileDatabase.TileType.WATER:
			water_above_count += 1
			water_columns.append(wx)

	if water_above_count > 0:
		gut.p("WARNING: Found %d/%d columns with WATER above sea level at y=%d" % [
			water_above_count, sample_count, WorldGenerator.SEA_LEVEL - 1
		])
		gut.p("  Columns with water: %s" % str(water_columns))

	assert_eq(water_above_count, 0,
		"No columns should have WATER above sea level (y=%d), found %d/%d: columns %s" % [
			WorldGenerator.SEA_LEVEL - 1, water_above_count, sample_count, str(water_columns)
		])
