## Tests for the column ownership biome system and Voronoi biome regions.
##
## Validates that surface biomes correctly determine underground biome
## assignments via column ownership, and that deep biomes
## (volcanic, crystal, fungal) are present in the Voronoi region map.

extends GutTest

var _gen: WorldGenerator
var _world_data: WorldData

const TEST_SEED: int = 42


func before_all() -> void:
	_gen = WorldGenerator.new(TEST_SEED)
	_world_data = WorldData.new()
	_world_data.set_world_size(WorldData.WorldSize.SMALL)
	var definition := WorldDefinition.create_overworld()
	_gen.generate_world(_world_data, definition)


# --- Helpers ---

## Find the center column of the first occurrence of a surface biome.
## Returns -1 if the biome is not found in the layout.
func _find_biome_center(biome_id: StringName) -> int:
	if _gen._surface_layout == null:
		return -1
	var i: int = 0
	while i < _gen._surface_layout.biome_ids.size():
		if _gen._surface_layout.biome_ids[i] == biome_id:
			var start: int = i
			while i < _gen._surface_layout.biome_ids.size() and _gen._surface_layout.biome_ids[i] == biome_id:
				i += 1
			@warning_ignore("integer_division")
			return (start + i) / 2
		i += 1
	return -1


# --- Column ownership: surface-to-underground pairing ---

func test_column_biome_desert() -> void:
	var cx: int = _find_biome_center(&"desert")
	if cx < 0:
		pending("No desert in this seed")
		return
	var surface_h: int = _gen._get_surface_height(cx)
	var biome: BiomeData = _gen._get_biome_for_tile(cx, surface_h + 30)
	gut.p("  desert: cx=%d, surface_h=%d, biome=%s" % [cx, surface_h, biome.id])
	assert_eq(biome.id, &"sandy_hollows",
		"Underground biome below desert should be sandy_hollows")


func test_column_biome_swamp() -> void:
	var cx: int = _find_biome_center(&"swamp")
	if cx < 0:
		pending("No swamp in this seed")
		return
	var surface_h: int = _gen._get_surface_height(cx)
	var biome: BiomeData = _gen._get_biome_for_tile(cx, surface_h + 30)
	gut.p("  swamp: cx=%d, surface_h=%d, biome=%s" % [cx, surface_h, biome.id])
	assert_eq(biome.id, &"swamp_depths",
		"Underground biome below swamp should be swamp_depths")


func test_column_biome_snowy_peaks() -> void:
	var cx: int = _find_biome_center(&"snowy_peaks")
	if cx < 0:
		pending("No snowy_peaks in this seed")
		return
	var surface_h: int = _gen._get_surface_height(cx)
	var biome: BiomeData = _gen._get_biome_for_tile(cx, surface_h + 30)
	gut.p("  snowy_peaks: cx=%d, surface_h=%d, biome=%s" % [cx, surface_h, biome.id])
	assert_eq(biome.id, &"frozen_caverns",
		"Underground biome below snowy_peaks should be frozen_caverns")


func test_column_biome_forest() -> void:
	var cx: int = _find_biome_center(&"forest")
	if cx < 0:
		pending("No forest in this seed")
		return
	var surface_h: int = _gen._get_surface_height(cx)
	var biome: BiomeData = _gen._get_biome_for_tile(cx, surface_h + 30)
	gut.p("  forest: cx=%d, surface_h=%d, biome=%s" % [cx, surface_h, biome.id])
	assert_eq(biome.id, &"standard_caverns",
		"Underground biome below forest should be standard_caverns")


func test_column_biome_mountains() -> void:
	var cx: int = _find_biome_center(&"mountains")
	if cx < 0:
		pending("No mountains in this seed")
		return
	var surface_h: int = _gen._get_surface_height(cx)
	var biome: BiomeData = _gen._get_biome_for_tile(cx, surface_h + 30)
	gut.p("  mountains: cx=%d, surface_h=%d, biome=%s" % [cx, surface_h, biome.id])
	assert_eq(biome.id, &"standard_caverns",
		"Underground biome below mountains should be standard_caverns")


# --- Voronoi biome regions ---

func test_biome_region_volcanic() -> void:
	var has_volcanic: bool = false
	for key in _gen._biome_region_map:
		if _gen._biome_region_map[key] == &"volcanic_depths":
			has_volcanic = true
			break
	assert_true(has_volcanic, "Biome region map should contain volcanic_depths")


func test_biome_region_crystal() -> void:
	var has_crystal: bool = false
	for key in _gen._biome_region_map:
		if _gen._biome_region_map[key] == &"crystal_caverns":
			has_crystal = true
			break
	assert_true(has_crystal, "Biome region map should contain crystal_caverns")


func test_biome_region_fungal() -> void:
	var has_fungal: bool = false
	for key in _gen._biome_region_map:
		if _gen._biome_region_map[key] == &"fungal_grove":
			has_fungal = true
			break
	assert_true(has_fungal, "Biome region map should contain fungal_grove")


# --- Debug output ---

func test_biome_region_counts_debug() -> void:
	var counts: Dictionary = {}
	for key in _gen._biome_region_map:
		var biome_id: StringName = _gen._biome_region_map[key]
		counts[biome_id] = counts.get(biome_id, 0) + 1

	gut.p("=== Biome Region Map Counts (seed=%d) ===" % TEST_SEED)
	var sorted_ids: Array = counts.keys()
	sorted_ids.sort()
	for biome_id in sorted_ids:
		gut.p("  %s: %d cells" % [biome_id, counts[biome_id]])
	gut.p("  Total: %d cells" % _gen._biome_region_map.size())

	# This test always passes -- it's for manual inspection
	assert_true(true, "Debug output printed above")
