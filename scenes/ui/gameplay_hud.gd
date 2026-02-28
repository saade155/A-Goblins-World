## GameplayHUD - Root HUD overlay that composes all HUD components.
##
## Replaces DebugHotbar. Creates and positions child components:
## hotbar (bottom center), vitals (bottom left), minimap (top right),
## status effects (top left).

extends CanvasLayer


func _ready() -> void:
	layer = 5

	# Hotbar — bottom center
	var hotbar := Control.new()
	hotbar.set_script(preload("res://scenes/ui/hud/hotbar_display.gd"))
	add_child(hotbar)

	# Vitals — bottom left
	var vitals := Control.new()
	vitals.set_script(preload("res://scenes/ui/hud/vitals_display.gd"))
	add_child(vitals)

	# Minimap — top right
	var minimap := Control.new()
	minimap.set_script(preload("res://scenes/ui/hud/minimap_display.gd"))
	add_child(minimap)

	# Status effects — top left
	var effects := Control.new()
	effects.set_script(preload("res://scenes/ui/hud/status_effects_display.gd"))
	add_child(effects)

	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	for child in get_children():
		if child.has_method("reposition"):
			child.reposition()
