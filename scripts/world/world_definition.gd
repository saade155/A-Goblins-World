## WorldDefinition - Defines how a map type generates its surface biome layout.
##
## Pure data container. Each map type (overworld, volcanic realm, etc.) has its own definition.
## Used by WorldGenerator to build a structured SurfaceBiomeLayout.

extends RefCounted
class_name WorldDefinition

## Unique identifier for this map type.
var id: StringName

## Which biome the player spawns in.
var spawn_biome: StringName

## All surface biomes available in this map.
var biome_pool: Array[StringName]

## Biomes pinned to world edges, in order from edge inward.
## e.g., [&"ocean", &"beach"] means Ocean at the very edge, Beach next to it.
var edge_biomes: Array[StringName]

## Adjacency rules: { biome_id: Array of allowed neighbor biome_ids }
var adjacency_rules: Dictionary

## Min/max index (inclusive) within inner biome slots where spawn biome can be placed.
## e.g., Vector2i(1, 3) means positions 1, 2, or 3 of the inner slots.
var spawn_position_range: Vector2i

## Factory: create the default overworld definition.
static func create_overworld() -> WorldDefinition:
	var def := WorldDefinition.new()
	def.id = &"overworld"
	def.spawn_biome = &"forest"
	def.biome_pool = [
		&"ocean", &"beach", &"forest", &"desert", &"swamp", &"mountains", &"snowy_peaks"
	]
	def.edge_biomes = [&"ocean", &"beach"]
	def.spawn_position_range = Vector2i(1, 3)

	# Adjacency rules — which biomes can be neighbors
	def.adjacency_rules = {
		&"ocean": [&"beach"],
		&"beach": [&"ocean", &"desert", &"swamp", &"mountains", &"snowy_peaks"],
		&"forest": [&"desert", &"swamp", &"mountains"],
		&"desert": [&"beach", &"forest", &"swamp", &"mountains"],
		&"swamp": [&"beach", &"forest", &"desert", &"mountains"],
		&"mountains": [&"beach", &"forest", &"desert", &"swamp", &"snowy_peaks"],
		&"snowy_peaks": [&"beach", &"mountains"],
	}

	return def
