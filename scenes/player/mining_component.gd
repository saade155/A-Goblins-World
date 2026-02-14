## MiningComponent - Handles tile mining and placement interaction.
##
## This is a child of the Player scene. Each frame it determines which tile the
## mouse is hovering over, shows a highlight, tracks mining progress, and sends
## requests to GameServer when mining completes or placement is triggered.
##
## Authority flow: MiningComponent -> GameServer.request_mine() -> GameServer
## modifies WorldData -> GameServer emits signal -> ChunkManager updates TileMapLayer.
## This component NEVER directly modifies WorldData or the TileMapLayer.
##
## No direct TileMapLayer reference needed. Tile coordinates are calculated from
## mouse world position, and tile existence is checked via GameState.world_data.

extends Node2D

## Maximum interaction distance in pixels (~3 tiles).
@export var mine_range: float = 96.0

## Base mining speed multiplier. Tools will increase this later.
@export var base_mine_speed: float = 2.0

## The tile coordinate currently targeted by the mouse. (-1, -1) = none.
var current_target: Vector2i = Vector2i(-1, -1)

## Accumulated mining progress toward breaking the current target.
var mine_progress: float = 0.0

## The hardness of the currently targeted tile (how much progress needed to break it).
var target_hardness: float = 0.0

## Cached reference to the tile highlight sprite.
@onready var _highlight: Sprite2D = $TileHighlight

## Cached reference to the progress indicator sprite.
@onready var _progress_indicator: Sprite2D = $ProgressIndicator

## Tile size in pixels.
const TILE_SIZE: int = 32


func _ready() -> void:
	# Start with visuals hidden.
	_highlight.visible = false
	_progress_indicator.visible = false


func _process(delta: float) -> void:
	# Need world data to check tiles. Wait until it's available.
	if not GameServer.world_data:
		return

	# Get mouse position in world space.
	var mouse_world_pos := get_global_mouse_position()

	# Convert to tile coordinates using floor division.
	var tile_coord := Vector2i(
		floori(mouse_world_pos.x / float(TILE_SIZE)),
		floori(mouse_world_pos.y / float(TILE_SIZE))
	)

	# Calculate the center of this tile in world space.
	var tile_world_center := Vector2(
		tile_coord.x * TILE_SIZE + TILE_SIZE / 2.0,
		tile_coord.y * TILE_SIZE + TILE_SIZE / 2.0
	)

	# Check if the tile is within mining range of the player.
	var player_pos: Vector2 = (get_parent() as Node2D).global_position
	var distance: float = player_pos.distance_to(tile_world_center)
	var in_range: bool = distance <= mine_range

	# Update highlight position and visibility.
	if in_range:
		_highlight.global_position = tile_world_center
		_highlight.visible = true
		# Tint based on whether there's a tile there.
		if GameServer.world_data.has_tile(tile_coord):
			_highlight.self_modulate = Color(1.0, 1.0, 0.3, 0.3)  # Yellow for minable
		else:
			_highlight.self_modulate = Color(0.3, 1.0, 0.3, 0.2)  # Green for placeable
	else:
		_highlight.visible = false

	# --- Mining logic ---
	if in_range and InputManager.is_mine_pressed():
		# Check if we have a valid target tile to mine.
		if GameServer.world_data.has_tile(tile_coord):
			if tile_coord != current_target:
				# Target changed -- reset progress.
				current_target = tile_coord
				mine_progress = 0.0
				var tile_type: int = GameServer.world_data.get_tile(tile_coord)
				target_hardness = TileDatabase.get_hardness(tile_type)

			# Accumulate mining progress.
			mine_progress += delta * base_mine_speed

			# Show progress indicator.
			_progress_indicator.global_position = tile_world_center
			_progress_indicator.visible = true
			var progress_ratio := mine_progress / target_hardness if target_hardness > 0.0 else 1.0
			progress_ratio = clampf(progress_ratio, 0.0, 1.0)
			_progress_indicator.self_modulate = Color(1.0, 1.0, 1.0, progress_ratio * 0.7)

			# Check if mining is complete.
			if mine_progress >= target_hardness:
				var success := GameServer.request_mine(get_parent(), current_target, base_mine_speed)
				if success:
					_reset_mining()
		else:
			# No tile to mine at this position.
			# Check for torch removal before resetting.
			if GameServer.world_data.has_torch(tile_coord):
				GameServer.request_remove_torch(get_parent(), tile_coord)
			_reset_mining()
	else:
		# Mine button not held or out of range -- reset.
		if current_target != Vector2i(-1, -1):
			_reset_mining()

	# --- Placement logic ---
	if in_range and InputManager.is_place_just_pressed():
		if GameServer.world_data and not GameServer.world_data.has_tile(tile_coord):
			var slot: Dictionary = GameServer.get_selected_hotbar_item()
			if slot["item_id"] != "":
				if slot["item_id"] == "torch":
					GameServer.request_place_torch(get_parent(), tile_coord)
				elif ItemDatabase.is_placeable(slot["item_id"]):
					GameServer.request_place_with_inventory(get_parent(), tile_coord, slot["item_id"])

	# --- Torch placement (T key) ---
	if in_range and InputManager.is_place_torch_just_pressed():
		if GameServer.world_data and not GameServer.world_data.has_tile(tile_coord):
			GameServer.request_place_torch(get_parent(), tile_coord)


## Reset all mining state and hide the progress indicator.
func _reset_mining() -> void:
	current_target = Vector2i(-1, -1)
	mine_progress = 0.0
	target_hardness = 0.0
	_progress_indicator.visible = false
