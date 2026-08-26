extends CanvasLayer

const LEVEL_SELECT_SCENE := "res://nodes/ui/level_select.tscn"

@onready var exit_button: Button = $ExitButton
@onready var overlay: Control = $Overlay
@onready var resume_button: Button = $Overlay/Panel/VBox/ResumeButton
@onready var restart_button: Button = $Overlay/Panel/VBox/RestartButton
@onready var select_button: Button = $Overlay/Panel/VBox/SelectButton

var is_paused := false


func _ready() -> void:
	# Menu phải chạy cả khi SceneTree bị pause, nếu không sẽ không bấm được gì.
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false

	exit_button.pressed.connect(_go_to_level_select)
	resume_button.pressed.connect(_resume)
	restart_button.pressed.connect(_restart_level)
	select_button.pressed.connect(_go_to_level_select)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	get_viewport().set_input_as_handled()
	if is_paused:
		_resume()
	else:
		_pause()


func _pause() -> void:
	# Lúc game over đang đếm ngược restart thì không cho pause, tránh kẹt đếm ngược.
	if _is_game_over():
		return

	is_paused = true
	overlay.visible = true
	exit_button.visible = false
	get_tree().paused = true
	resume_button.grab_focus()


func _resume() -> void:
	is_paused = false
	overlay.visible = false
	exit_button.visible = true
	get_tree().paused = false


func _restart_level() -> void:
	var scene_path := get_tree().current_scene.scene_file_path
	_leave_to_scene(scene_path)


func _go_to_level_select() -> void:
	_leave_to_scene(LEVEL_SELECT_SCENE)


func _leave_to_scene(scene_path: String) -> void:
	_resume()

	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("reset_to_playing"):
		game_state.reset_to_playing()

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not load scene %s: %s" % [scene_path, error])


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
