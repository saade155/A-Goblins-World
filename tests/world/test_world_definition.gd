## Tests for WorldDefinition data class.
##
## Validates overworld configuration: biome pool, edge biomes, spawn settings,
## adjacency rule integrity, and spawn position range constraints.

extends GutTest

var _def: WorldDefinition


func before_each() -> void:
	_def = WorldDefinition.create_overworld()


# --- Basic property tests ---

func test_overworld_id() -> void:
	assert_eq(_def.id, &"overworld", "Overworld definition should have id 'overworld'")


func test_overworld_spawn_biome() -> void:
	assert_eq(_def.spawn_biome, &"forest", "Overworld spawn biome should be 'forest'")


func test_overworld_has_all_biomes() -> void:
	var expected: Array[StringName] = [
		&"forest", &"desert", &"swamp", &"mountains", &"snowy_peaks", &"beach", &"ocean"
	]
	for biome_id in expected:
		assert_has(_def.biome_pool, biome_id,
			"biome_pool should contain '%s'" % biome_id)
	assert_eq(_def.biome_pool.size(), expected.size(),
		"biome_pool should have exactly %d biomes" % expected.size())


func test_overworld_edge_biomes() -> void:
	assert_eq(_def.edge_biomes.size(), 2, "Should have exactly 2 edge biomes")
	assert_eq(_def.edge_biomes[0], &"ocean", "First edge biome should be 'ocean'")
	assert_eq(_def.edge_biomes[1], &"beach", "Second edge biome should be 'beach'")


# --- Adjacency rule integrity ---

func test_adjacency_rules_bidirectional() -> void:
	for biome_id: StringName in _def.adjacency_rules:
		var neighbors: Array = _def.adjacency_rules[biome_id]
		for neighbor_id: StringName in neighbors:
			assert_true(
				_def.adjacency_rules.has(neighbor_id),
				"Neighbor '%s' (referenced by '%s') must have its own adjacency entry" % [neighbor_id, biome_id]
			)
			if _def.adjacency_rules.has(neighbor_id):
				var reverse_neighbors: Array = _def.adjacency_rules[neighbor_id]
				assert_has(reverse_neighbors, biome_id,
					"'%s' lists '%s' as neighbor, so '%s' must also list '%s'" % [
						biome_id, neighbor_id, neighbor_id, biome_id
					])


func test_adjacency_rules_reference_valid_biomes() -> void:
	var all_valid_ids: Array[StringName] = []
	all_valid_ids.append_array(_def.biome_pool)

	# Every key in adjacency_rules must be a valid biome
	for biome_id: StringName in _def.adjacency_rules:
		assert_has(all_valid_ids, biome_id,
			"Adjacency key '%s' must exist in biome_pool" % biome_id)

	# Every neighbor referenced in adjacency_rules must be a valid biome
	for biome_id: StringName in _def.adjacency_rules:
		var neighbors: Array = _def.adjacency_rules[biome_id]
		for neighbor_id: StringName in neighbors:
			assert_has(all_valid_ids, neighbor_id,
				"Neighbor '%s' (of '%s') must exist in biome_pool" % [neighbor_id, biome_id])


# --- Spawn position range ---

func test_spawn_position_range_valid() -> void:
	var inner_slot_count: int = _def.biome_pool.size() - _def.edge_biomes.size()
	gut.p("Inner slot count: %d, spawn range: %s" % [inner_slot_count, _def.spawn_position_range])

	assert_true(_def.spawn_position_range.x >= 0,
		"Spawn range min (x=%d) must be >= 0" % _def.spawn_position_range.x)
	assert_true(_def.spawn_position_range.y >= _def.spawn_position_range.x,
		"Spawn range max (y=%d) must be >= min (x=%d)" % [
			_def.spawn_position_range.y, _def.spawn_position_range.x
		])
	assert_true(_def.spawn_position_range.y < inner_slot_count,
		"Spawn range max (y=%d) must be < inner slot count (%d)" % [
			_def.spawn_position_range.y, inner_slot_count
		])
