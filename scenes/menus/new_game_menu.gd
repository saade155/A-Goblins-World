extends Control

signal back_pressed
signal start_game(slot_name: String)

## Selected world size preset (WorldData.WorldSize enum). Default: SMALL (0).
var selected_size: int = 0

## References to the size buttons for highlight management.
var _size_buttons: Array[Button] = []


func _ready() -> void:
	# Auto-fill world name based on existing slot count
	var slot_count: int = SaveManager.enumerate_slots().size()
	%NameInput.text = "World %d" % (slot_count + 1)

	# Connect signals
	%CreateButton.pressed.connect(_on_create_pressed)
	%BackButton.pressed.connect(func(): back_pressed.emit())
	%NameInput.text_submitted.connect(func(_text: String): _on_create_pressed())

	# Connect world size buttons
	_size_buttons = [%SmallButton, %MediumButton, %LargeButton]
	%SmallButton.pressed.connect(_on_size_small)
	%MediumButton.pressed.connect(_on_size_medium)
	%LargeButton.pressed.connect(_on_size_large)

	# Set default selection visual
	_update_size_highlight()

	# Focus name input
	%NameInput.grab_focus()


func _on_size_small() -> void:
	selected_size = 0  # WorldSize.SMALL
	_update_size_highlight()


func _on_size_medium() -> void:
	selected_size = 1  # WorldSize.MEDIUM
	_update_size_highlight()


func _on_size_large() -> void:
	selected_size = 2  # WorldSize.LARGE
	_update_size_highlight()


## Update button visuals to show which size is selected.
## Uses disabled state as a visual indicator (pressed look).
func _update_size_highlight() -> void:
	for i in range(_size_buttons.size()):
		_size_buttons[i].disabled = (i == selected_size)


func _on_create_pressed() -> void:
	var display_name: String = %NameInput.text.strip_edges()
	if display_name == "":
		display_name = "Unnamed World"

	var slot_name: String = SaveManager.generate_slot_name(display_name)

	# Set up GameState for a new world
	GameState.reset_for_new_game()
	GameState.world_seed = randi()
	GameState.world_slot_name = slot_name
	GameState.world_display_name = display_name
	GameState.world_size = selected_size
	GameState.is_game_active = true

	# Reset GameServer session state
	GameServer.reset_state()

	start_game.emit(slot_name)
