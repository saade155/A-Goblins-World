extends CanvasLayer

## Loading overlay shown during initial chunk generation.
## Hides itself when ChunkManager signals that initial load is complete.

func _ready() -> void:
	layer = 50

	# Display the world name if available
	var world_name = GameState.world_display_name
	if world_name != "":
		%LoadingLabel.text = "Loading %s..." % world_name

	# Find ChunkManager and connect to its signal
	var chunk_manager = get_tree().current_scene.get_node_or_null("ChunkManager")
	if chunk_manager:
		chunk_manager.initial_load_complete.connect(_on_load_complete)
	else:
		# No ChunkManager found, hide immediately
		_hide()


## Update the loading label text. Called by ChunkManager during world generation
## to show progress percentage.
func set_progress_text(text: String) -> void:
	%LoadingLabel.text = text


func _on_load_complete() -> void:
	_hide()


func _hide() -> void:
	# Simple fade: just hide immediately for now
	# Can add a tween fade later for polish
	for child in get_children():
		if child is CanvasItem:
			child.visible = false
	queue_free()
