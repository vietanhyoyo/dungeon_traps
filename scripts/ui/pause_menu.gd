extends CanvasLayer

const LEVEL_SELECT_SCENE := "res://nodes/ui/level_select.tscn"

@onready var menu_button: Button = $MenuButton
@onready var overlay: Control = $Overlay
@onready var resume_button: Button = $Overlay/Center/Panel/VBox/ResumeButton
@onready var restart_button: Button = $Overlay/Center/Panel/VBox/RestartButton
@onready var select_button: Button = $Overlay/Center/Panel/VBox/SelectButton
@onready var spin_jump_attack_skill: HBoxContainer = $Overlay/Center/Panel/VBox/SkillList/SpinJumpAttack
@onready var wall_jump_skill: HBoxContainer = $Overlay/Center/Panel/VBox/SkillList/WallJump

var is_paused := false


func _ready() -> void:
	# Menu phải chạy cả khi SceneTree bị pause, nếu không sẽ không bấm được gì.
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false

	# Nút hamburger mở bảng thông tin nhân vật (cũng là menu tạm dừng).
	menu_button.pressed.connect(_pause)
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
	# Kỹ năng mở khoá từ rương chỉ hiện trong bảng sau khi thực sự nhận được.
	spin_jump_attack_skill.visible = GameState.has_skill(Skills.SPIN_JUMP_ATTACK)
	wall_jump_skill.visible = GameState.has_skill(Skills.WALL_DOUBLE_JUMP)
	overlay.visible = true
	menu_button.visible = false
	get_tree().paused = true
	resume_button.grab_focus()


func _resume() -> void:
	is_paused = false
	overlay.visible = false
	menu_button.visible = true
	get_tree().paused = false


func _restart_level() -> void:
	var scene_path := get_tree().current_scene.scene_file_path

	# Chơi lại màn là chơi lại từ đầu: bỏ sao đã ăn và save point cũ.
	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("clear_level_progress"):
		game_state.clear_level_progress(scene_path)

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
