extends Control

signal back_pressed
signal start_game(slot_name: String)


func _ready() -> void:
	# Auto-fill world name based on existing slot count
	var slot_count: int = SaveManager.enumerate_slots().size()
	%NameInput.text = "World %d" % (slot_count + 1)

	# Connect signals
	%CreateButton.pressed.connect(_on_create_pressed)
	%BackButton.pressed.connect(func(): back_pressed.emit())
	%NameInput.text_submitted.connect(func(_text: String): _on_create_pressed())

	# Focus name input
	%NameInput.grab_focus()


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
	GameState.is_game_active = true

	# Reset GameServer session state
	GameServer.reset_state()

	start_game.emit(slot_name)
