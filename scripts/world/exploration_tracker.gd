## ExplorationTracker - Tracks which tiles the player has actually seen.
##
## Reveals tiles in a circular radius around the player. The fog of war
## opens up as the player moves through the world. Explored tiles persist
## across sessions via SaveManager.
##
## Dev toggle: debug_fog_disabled bypasses fog to show the entire world on the map.

extends Node

## Emitted when debug fog is toggled via console or hotkey.
signal debug_fog_toggled

## Explored tiles stored as a set (Dictionary[Vector2i, bool]).
## Permanent — once explored, always explored. Used for fog of war.
var explored_tiles: Dictionary = {}

## Tiles currently visible via the flood-fill from the player's position.
## Rebuilt every time the player moves. Used for player proximity lighting.
var visible_tiles: Dictionary = {}

## Reveal radius in tiles — how far light floods through open space.
const REVEAL_RADIUS: int = 12

## Squared radius for fast distance checks (avoids sqrt).
const REVEAL_RADIUS_SQ: int = REVEAL_RADIUS * REVEAL_RADIUS

## Surface reveal radius — much larger since daylight lets you see to the horizon.
## Covers full screen at 1x zoom (960px / 16px = 60 tiles wide, half = 30 + margin).
const SURFACE_REVEAL_RADIUS: int = 40
const SURFACE_REVEAL_RADIUS_SQ: int = SURFACE_REVEAL_RADIUS * SURFACE_REVEAL_RADIUS

## How many tiles deep into solid walls are revealed from open space.
const WALL_REVEAL_DEPTH: int = 2

## Tile size in pixels.
const TILE_SIZE: int = 16

## When true, all tiles are treated as explored (dev tool).
var debug_fog_disabled: bool = false

## Track last player tile to avoid redundant work when standing still.
var _last_player_tile: Vector2i = Vector2i(999999, 999999)

## Set to true when the world changes (mining) to force a recheck next frame.
var _needs_recheck: bool = false


func _ready() -> void:
	# Recheck LOS when tiles are mined (opens up new sightlines)
	GameServer.tile_mined.connect(func(_p, _t, _tool): _force_recheck())
	GameServer.back_wall_mined.connect(func(_p, _t): _force_recheck())


## Force a full LOS recheck on the next frame (called when world changes).
func _force_recheck() -> void:
	_needs_recheck = true


func _process(_delta: float) -> void:
	if not GameState.player:
		return

	# Get the player's tile position
	var camera_pos: Vector2 = GameState.player.global_position
	var center_tile := Vector2i(
		floori(camera_pos.x / TILE_SIZE),
		floori(camera_pos.y / TILE_SIZE)
	)

	# Only update if player moved to a new tile or world changed
	if center_tile == _last_player_tile and not _needs_recheck:
		return
	_last_player_tile = center_tile
	_needs_recheck = false

	# Flood-fill reveal: BFS through open space, then reveal nearby walls
	_update_exploration(center_tile)


## Flood-fill exploration from the player's position.
## Phase 1: BFS through empty tiles within REVEAL_RADIUS.
## Phase 2: Reveal solid walls within WALL_REVEAL_DEPTH of any revealed empty tile.
func _update_exploration(center_tile: Vector2i) -> void:
	var world_data = GameState.world_data
	if world_data == null:
		return

	# Reset current visibility for this frame
	visible_tiles.clear()

	# Phase 1: BFS flood through empty tiles within reveal radius
	var queue: Array[Vector2i] = [center_tile]
	var qi: int = 0  # Queue index (avoids O(n) pop_front)
	var visited: Dictionary = {}
	var empty_revealed: Array[Vector2i] = []
	var reached_surface: bool = false

	while qi < queue.size():
		var tile: Vector2i = queue[qi]
		qi += 1

		if visited.has(tile):
			continue
		visited[tile] = true

		# Distance check (standard radius for BFS — surface gets expanded separately)
		var dx: int = tile.x - center_tile.x
		var dy: int = tile.y - center_tile.y
		if dx * dx + dy * dy > REVEAL_RADIUS_SQ:
			continue

		explored_tiles[tile] = true
		visible_tiles[tile] = true

		if tile.y <= 0:
			reached_surface = true

		# Flood through empty tiles (or always from start tile in case player is inside solid)
		if tile == center_tile or not world_data.has_tile(tile):
			empty_revealed.append(tile)
			for nx in range(tile.x - 1, tile.x + 2):
				for ny in range(tile.y - 1, tile.y + 2):
					if nx == tile.x and ny == tile.y:
						continue
					var neighbor := Vector2i(nx, ny)
					if not visited.has(neighbor):
						queue.append(neighbor)

	# Phase 1.5: Surface daylight expansion
	# If BFS reached the surface, mark a wide horizontal band as explored.
	# Surface tiles get full daylight in the darkness overlay, so no BFS needed —
	# just mark them explored so the darkness overlay shows them as lit.
	if reached_surface or center_tile.y <= 5:
		var sr: int = SURFACE_REVEAL_RADIUS
		var min_y: int = maxi(center_tile.y - 20, -100)
		var max_y: int = mini(center_tile.y + 5, 0)
		for sx in range(center_tile.x - sr, center_tile.x + sr + 1):
			for sy in range(min_y, max_y + 1):
				explored_tiles[Vector2i(sx, sy)] = true

	# Phase 2: Reveal walls within WALL_REVEAL_DEPTH tiles of any revealed empty tile
	for empty_tile in empty_revealed:
		for wx in range(empty_tile.x - WALL_REVEAL_DEPTH, empty_tile.x + WALL_REVEAL_DEPTH + 1):
			for wy in range(empty_tile.y - WALL_REVEAL_DEPTH, empty_tile.y + WALL_REVEAL_DEPTH + 1):
				var wt := Vector2i(wx, wy)
				if world_data.has_tile(wt):
					explored_tiles[wt] = true
					visible_tiles[wt] = true


## Check if a specific tile has been explored.
func is_tile_explored(tile_pos: Vector2i) -> bool:
	if debug_fog_disabled:
		return true
	return explored_tiles.has(tile_pos)


## Toggle the debug fog override.
func toggle_debug_fog() -> void:
	debug_fog_disabled = not debug_fog_disabled
	if debug_fog_disabled:
		print("[ExplorationTracker] Debug fog: OFF (all visible)")
	else:
		print("[ExplorationTracker] Debug fog: ON")
	debug_fog_toggled.emit()
