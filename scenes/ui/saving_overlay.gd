extends CanvasLayer

## Non-blocking "Saving..." indicator shown during snapshot creation.
## Appears as a small panel in the bottom-right corner and dismisses
## after the save completes (with a minimum 2-second display time).

var _min_time_elapsed: bool = false
var _save_complete: bool = false

@onready var _panel: PanelContainer = $PanelContainer
@onready var _min_timer: Timer = $MinTimer


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_min_timer.wait_time = 2.0
	_min_timer.one_shot = true
	_min_timer.timeout.connect(_on_min_timer_timeout)


func show_saving() -> void:
	_min_time_elapsed = false
	_save_complete = false
	visible = true
	_min_timer.start()


func hide_saving() -> void:
	_save_complete = true
	if _min_time_elapsed:
		visible = false


func _on_min_timer_timeout() -> void:
	_min_time_elapsed = true
	if _save_complete:
		visible = false
