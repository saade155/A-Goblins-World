## Tests for SurfaceBiomeLayout built by WorldGenerator._build_surface_layout().
##
## Validates layout coverage, biome placement, blend factors, zone ordering,
## adjacency rules, and seed variation.

extends GutTest

var _gen: WorldGenerator
var _definition: WorldDefinition
var _layout: SurfaceBiomeLayout

const WORLD_WIDTH: int = 2400
const TEST_SEED: int = 12345


func before_each() -> void:
	_gen = WorldGenerator.new(TEST_SEED)
	_definition = WorldDefinition.create_overworld()
	_layout = _gen._build_surface_layout(_definition, WORLD_WIDTH)


# --- Coverage ---

func test_layout_covers_full_width() -> void:
	assert_eq(_layout.biome_ids.size(), WORLD_WIDTH,
		"biome_ids should have exactly %d entries (one per column)" % WORLD_WIDTH)
	assert_eq(_layout.blend_biome_ids.size(), WORLD_WIDTH,
		"blend_biome_ids should have exactly %d entries" % WORLD_WIDTH)
	assert_eq(int(_layout.blend_factors.size()), WORLD_WIDTH,
		"blend_factors should have exactly %d entries" % WORLD_WIDTH)


# --- Biome pool completeness ---

func test_all_pool_biomes_present() -> void:
	var found: Dictionary = {}
	for wx in range(WORLD_WIDTH):
		found[_layout.biome_ids[wx]] = true

	for biome_id in _definition.biome_pool:
		assert_true(found.has(biome_id),
			"Biome '%s' from pool should appear in the layout" % biome_id)


# --- Edge biomes ---

func test_edges_are_ocean() -> void:
	# The zone order starts with edge_biomes [ocean, beach] on the left
	# and ends with [beach, ocean] on the right. Verify the first columns
	# are ocean and the last columns are ocean.
	assert_eq(_layout.biome_ids[0], &"ocean",
		"Column 0 should be 'ocean'")
	assert_eq(_layout.biome_ids[WORLD_WIDTH - 1], &"ocean",
		"Last column should be 'ocean'")

	# Verify a range of edge columns are ocean (not just column 0)
	var left_ocean_count: int = 0
	for wx in range(mini(200, WORLD_WIDTH)):
		if _layout.biome_ids[wx] == &"ocean":
			left_ocean_count += 1
		else:
			break
	assert_gt(left_ocean_count, 10,
		"Left edge should have a substantial ocean zone (got %d columns)" % left_ocean_count)

	var right_ocean_count: int = 0
	for wx in range(WORLD_WIDTH - 1, maxi(WORLD_WIDTH - 200, 0), -1):
		if _layout.biome_ids[wx] == &"ocean":
			right_ocean_count += 1
		else:
			break
	assert_gt(right_ocean_count, 10,
		"Right edge should have a substantial ocean zone (got %d columns)" % right_ocean_count)


# --- Spawn placement ---

func test_spawn_in_forest() -> void:
	assert_eq(_layout.get_biome_id(_layout.spawn_x), &"forest",
		"Spawn X (%d) should be in the 'forest' biome" % _layout.spawn_x)


# --- Blend factors at zone centers ---

func test_blend_factors_zero_in_centers() -> void:
	# The midpoint of each zone should have blend_factor == 0.0
	for zone_idx in range(_layout.zone_boundaries.size()):
		var zone_start: int = _layout.zone_boundaries[zone_idx]
		var zone_end: int
		if zone_idx + 1 < _layout.zone_boundaries.size():
			zone_end = _layout.zone_boundaries[zone_idx + 1]
		else:
			zone_end = WORLD_WIDTH
		@warning_ignore("integer_division")
		var mid: int = (zone_start + zone_end) / 2
		var factor: float = _layout.get_blend_factor(mid)
		assert_eq(factor, 0.0,
			"Zone %d ('%s') center at column %d should have blend_factor 0.0, got %.3f" % [
				zone_idx, _layout.zone_biome_ids[zone_idx], mid, factor
			])


# --- Blend factors at boundaries ---

func test_blend_factors_nonzero_at_boundaries() -> void:
	# At zone boundaries (excluding the very first and very last), nearby
	# columns should have nonzero blend factors.
	var boundaries_with_blend: int = 0
	for zone_idx in range(1, _layout.zone_boundaries.size() - 1):
		var boundary_x: int = _layout.zone_boundaries[zone_idx]
		# Check a column just inside the previous zone
		var check_x: int = boundary_x - 2
		if check_x >= 0 and check_x < WORLD_WIDTH:
			var factor: float = _layout.get_blend_factor(check_x)
			if factor > 0.0:
				boundaries_with_blend += 1

	# We expect most interior boundaries to have blend factors
	var interior_boundary_count: int = _layout.zone_boundaries.size() - 2
	if interior_boundary_count > 0:
		assert_gt(boundaries_with_blend, 0,
			"At least some interior zone boundaries should have nonzero blend factors")


# --- Zone boundary ordering ---

func test_zone_boundaries_ordered() -> void:
	for i in range(_layout.zone_boundaries.size() - 1):
		assert_lt(_layout.zone_boundaries[i], _layout.zone_boundaries[i + 1],
			"zone_boundaries[%d] (%d) should be < zone_boundaries[%d] (%d)" % [
				i, _layout.zone_boundaries[i],
				i + 1, _layout.zone_boundaries[i + 1]
			])


# --- Seed variation ---

func test_different_seeds_different_layouts() -> void:
	# Generate layouts with 10 different seeds and verify at least 3 unique
	# zone orderings emerge (proving the seed actually changes the layout).
	var unique_orderings: Dictionary = {}
	for s in range(1, 11):
		var gen := WorldGenerator.new(s)
		var layout := gen._build_surface_layout(_definition, WORLD_WIDTH)
		# Create a key from the zone ordering
		var key: String = ""
		for biome_id in layout.zone_biome_ids:
			key += str(biome_id) + ","
		unique_orderings[key] = true

	gut.p("Unique zone orderings from 10 seeds: %d" % unique_orderings.size())
	assert_gt(unique_orderings.size(), 2,
		"10 different seeds should produce at least 3 unique zone orderings (got %d)" % unique_orderings.size())


# --- Adjacency rules ---

func test_adjacency_respected() -> void:
	# Each consecutive pair of zones in zone_biome_ids should satisfy
	# the adjacency rules from the definition.
	for i in range(_layout.zone_biome_ids.size() - 1):
		var left: StringName = _layout.zone_biome_ids[i]
		var right: StringName = _layout.zone_biome_ids[i + 1]

		var left_ok: bool = true
		var right_ok: bool = true

		if _definition.adjacency_rules.has(left):
			var allowed: Array = _definition.adjacency_rules[left]
			left_ok = allowed.has(right)

		if _definition.adjacency_rules.has(right):
			var allowed: Array = _definition.adjacency_rules[right]
			right_ok = allowed.has(left)

		assert_true(left_ok and right_ok,
			"Zone pair [%d]='%s' -> [%d]='%s' must satisfy adjacency rules" % [
				i, left, i + 1, right
			])
