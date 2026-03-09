## SurfaceBiomeLayout - Precomputed per-column surface biome assignment.
##
## Built once during world generation Phase 0 from a WorldDefinition.
## Provides O(1) lookups for biome ID and blend factor at any X column.

extends RefCounted
class_name SurfaceBiomeLayout

## Primary biome ID for each X column.
var biome_ids: Array[StringName] = []

## Neighbor biome ID for blending at each X column (empty StringName if no blend).
var blend_biome_ids: Array[StringName] = []

## Blend factor for each X column (0.0 = pure primary, approaching 1.0 = mostly neighbor).
var blend_factors: PackedFloat32Array = PackedFloat32Array()

## X column where the player should spawn (center of spawn zone).
var spawn_x: int = 0

## X positions where each zone starts (for debug/map display).
var zone_boundaries: PackedInt32Array = PackedInt32Array()

## Zone biome IDs in order (matches zone_boundaries).
var zone_biome_ids: Array[StringName] = []


## Get the primary biome ID at a given X column.
func get_biome_id(wx: int) -> StringName:
	var idx: int = clampi(wx, 0, biome_ids.size() - 1)
	return biome_ids[idx]


## Get the blend neighbor biome ID at a given X column.
func get_blend_biome_id(wx: int) -> StringName:
	var idx: int = clampi(wx, 0, blend_biome_ids.size() - 1)
	return blend_biome_ids[idx]


## Get the blend factor at a given X column (0.0 = no blend).
func get_blend_factor(wx: int) -> float:
	var idx: int = clampi(wx, 0, blend_factors.size() - 1)
	return blend_factors[idx]
