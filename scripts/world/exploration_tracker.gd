## ExplorationTracker - Tracks which tiles the player has actually seen.
##
## Reveals tiles based on the camera viewport - only what's visible on screen
## gets marked as explored. The fog of war opens up naturally as the player
## moves through the world.
##
## Dev toggle: debug_fog_disabled bypasses fog to show the entire world on the map.

extends Node

## Explored tiles stored as a set (Dictionary[Vector2i, bool]).
## Only tiles the player has seen on screen are added.
var explored_tiles: Dictionary = {}

## Viewport size in tiles (calculated on ready).
var viewport_tiles_x: int = 0
var viewport_tiles_y: int = 0

## Small buffer around viewport edges so fog doesn't flicker at screen borders.
const EDGE_BUFFER: int = 2

## Tile size in pixels.
const TILE_SIZE: int = 16

## When true, all tiles are treated as explored (dev tool).
var debug_fog_disabled: bool = false

## Track last player tile to avoid redundant work when standing still.
var _last_player_tile: Vector2i = Vector2i(999999, 999999)


func _ready() -> void:
	# Calculate viewport size in tiles from project settings
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	viewport_tiles_x = ceili(viewport_size.x / TILE_SIZE) + EDGE_BUFFER * 2
	viewport_tiles_y = ceili(viewport_size.y / TILE_SIZE) + EDGE_BUFFER * 2


func _process(_delta: float) -> void:
	if not GameState.player:
		return

	# Get the player's camera position (center of viewport)
	var camera_pos: Vector2 = GameState.player.global_position
	var center_tile := Vector2i(
		floori(camera_pos.x / TILE_SIZE),
		floori(camera_pos.y / TILE_SIZE)
	)

	# Only update if player moved to a new tile
	if center_tile == _last_player_tile:
		return
	_last_player_tile = center_tile

	# Mark all tiles visible on screen as explored
	var half_x: int = viewport_tiles_x / 2
	var half_y: int = viewport_tiles_y / 2

	for x in range(center_tile.x - half_x, center_tile.x + half_x + 1):
		for y in range(center_tile.y - half_y, center_tile.y + half_y + 1):
			explored_tiles[Vector2i(x, y)] = true


## Check if a specific tile has been explored (seen on screen).
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
