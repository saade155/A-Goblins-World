## Tests for registry data consistency.
##
## Validates that SurfaceBiomeRegistry and BiomeRegistry data is internally
## consistent: paired biomes exist, widths fit, thresholds are in range, etc.

extends GutTest

var _surface_registry: SurfaceBiomeRegistry
var _biome_registry: BiomeRegistry


func before_each() -> void:
	_surface_registry = SurfaceBiomeRegistry.new()
	_biome_registry = BiomeRegistry.new()


# --- Surface biome pairing ---

func test_all_surface_biomes_have_paired_ug() -> void:
	for biome: SurfaceBiomeData in _surface_registry.biomes:
		assert_true(biome.paired_underground_biome != &"",
			"Surface biome '%s' must have a non-empty paired_underground_biome" % biome.id)


func test_paired_ug_biomes_exist() -> void:
	for biome: SurfaceBiomeData in _surface_registry.biomes:
		var ug_id: StringName = biome.paired_underground_biome
		if ug_id == &"":
			continue
		var found: BiomeData = _biome_registry.get_biome_by_id(ug_id)
		# get_biome_by_id returns default_biome when not found, so check actual id
		assert_eq(found.id, ug_id,
			"Paired underground biome '%s' (from surface '%s') must exist in BiomeRegistry" % [
				ug_id, biome.id
			])


# --- Width percentages ---

func test_width_percentages_fit() -> void:
	var total_min: float = 0.0
	for biome: SurfaceBiomeData in _surface_registry.biomes:
		total_min += biome.min_width_pct
		gut.p("  %s: min=%.2f, max=%.2f" % [biome.id, biome.min_width_pct, biome.max_width_pct])
	gut.p("Total min_width_pct sum: %.3f" % total_min)
	assert_true(total_min <= 1.0,
		"Sum of all min_width_pct (%.3f) must be <= 1.0" % total_min)


# --- Cave thresholds ---

func test_cave_thresholds_in_range() -> void:
	for biome: BiomeData in _biome_registry.biomes:
		assert_true(biome.cave_threshold >= 0.1,
			"Biome '%s' cave_threshold (%.2f) must be >= 0.1" % [biome.id, biome.cave_threshold])
		assert_true(biome.cave_threshold <= 1.0,
			"Biome '%s' cave_threshold (%.2f) must be <= 1.0" % [biome.id, biome.cave_threshold])


# --- Positive depth/width values ---

func test_continuity_depths_positive() -> void:
	for biome: SurfaceBiomeData in _surface_registry.biomes:
		assert_gt(biome.continuity_depth, 0,
			"Surface biome '%s' continuity_depth must be > 0" % biome.id)


func test_subsurface_depth_positive() -> void:
	for biome: SurfaceBiomeData in _surface_registry.biomes:
		assert_gt(biome.subsurface_depth, 0,
			"Surface biome '%s' subsurface_depth must be > 0" % biome.id)


func test_transition_widths_positive() -> void:
	for biome: SurfaceBiomeData in _surface_registry.biomes:
		assert_gt(biome.transition_width, 0,
			"Surface biome '%s' transition_width must be > 0" % biome.id)


# --- Distinct tiles for non-standard underground biomes ---

func test_all_ug_biomes_have_distinct_tiles() -> void:
	var standard: BiomeData = _biome_registry.get_biome_by_id(&"standard_caverns")
	assert_not_null(standard, "standard_caverns must exist in BiomeRegistry")

	for biome: BiomeData in _biome_registry.biomes:
		if biome.id == &"standard_caverns":
			continue
		var has_distinct_tile: bool = (
			biome.primary_tile != standard.primary_tile
			or biome.secondary_tile != standard.secondary_tile
		)
		assert_true(has_distinct_tile,
			"Underground biome '%s' should have at least one tile different from standard_caverns (primary=%d, secondary=%d vs standard primary=%d, secondary=%d)" % [
				biome.id,
				biome.primary_tile, biome.secondary_tile,
				standard.primary_tile, standard.secondary_tile
			])
