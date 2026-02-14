extends Control

var _settings_menu_scene: PackedScene = preload("res://scenes/menus/settings_menu.tscn")
var _new_game_menu_scene: PackedScene = preload("res://scenes/menus/new_game_menu.tscn")
var _load_game_menu_scene: PackedScene = preload("res://scenes/menus/load_game_menu.tscn")

@onready var button_container: VBoxContainer = %ButtonContainer
@onready var title_label: Label = %TitleLabel
@onready var sub_menu_container: Control = %SubMenuContainer
@onready var new_game_button: Button = %NewGameButton
@onready var load_game_button: Button = %LoadGameButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	# Disable Load Game if no save slots exist
	var slots: Array[Dictionary] = SaveManager.enumerate_slots()
	if slots.is_empty():
		load_game_button.disabled = true

	# Connect button signals
	new_game_button.pressed.connect(func(): _show_submenu(_new_game_menu_scene))
	load_game_button.pressed.connect(func(): _show_submenu(_load_game_menu_scene))
	settings_button.pressed.connect(func(): _show_submenu(_settings_menu_scene))
	quit_button.pressed.connect(func(): get_tree().quit())

	# Focus first button
	new_game_button.grab_focus()


func _show_submenu(scene: PackedScene) -> void:
	var instance: Control = scene.instantiate()
	sub_menu_container.add_child(instance)

	# Hide main menu elements
	button_container.visible = false
	title_label.visible = false

	# Connect back signal (all submenus emit this)
	if instance.has_signal("back_pressed"):
		instance.back_pressed.connect(_clear_submenu)

	# Connect start_game signal (new game and load game menus)
	if instance.has_signal("start_game"):
		instance.start_game.connect(_on_start_game)


func _clear_submenu() -> void:
	for child in sub_menu_container.get_children():
		child.queue_free()

	# Show main menu elements again
	button_container.visible = true
	title_label.visible = true

	# Re-check if load button should be enabled (user may have deleted all slots)
	var slots: Array[Dictionary] = SaveManager.enumerate_slots()
	load_game_button.disabled = slots.is_empty()

	new_game_button.grab_focus()


func _on_start_game(_slot_name: String) -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
