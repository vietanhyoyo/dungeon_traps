extends Node
class_name GameStateManager

signal game_over_started(player: Node2D)
signal restart_countdown_changed(seconds_left: int)

enum State {
	PLAYING,
	GAME_OVER,
}

const DEFAULT_RESTART_SCENE_PATH := "res://nodes/scenes/level_1.tscn"
const COUNTDOWN_FONT := preload("res://assets/fonts/PixelOperator8-Bold.ttf")
const GAME_OVER_SOUND := preload("res://assets/sounds/game_over.mp3")
const RESTART_DELAY_SECONDS := 5

var state: State = State.PLAYING

var _is_counting_down := false
var _restart_scene_path := DEFAULT_RESTART_SCENE_PATH
var _countdown_layer: CanvasLayer
var _countdown_label: Label
var _game_over_sound_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_game_over_sound_player = AudioStreamPlayer.new()
	_game_over_sound_player.stream = GAME_OVER_SOUND
	_game_over_sound_player.bus = &"SFX"
	_game_over_sound_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_game_over_sound_player)


func trigger_game_over(player: Node2D) -> void:
	if state == State.GAME_OVER:
		return

	state = State.GAME_OVER
	_restart_scene_path = _get_current_scene_path()
	game_over_started.emit(player)
	_game_over_sound_player.play()

	if not _is_counting_down:
		_is_counting_down = true
		_run_restart_countdown()

	# Cho player kịp phát animation chịu đòn rồi mới chuyển sang animation chết
	if player and player.has_method("take_hit"):
		await player.take_hit()

	if player and player.has_method("die"):
		player.die()


func is_game_over() -> bool:
	return state == State.GAME_OVER


func reset_to_playing() -> void:
	state = State.PLAYING
	_is_counting_down = false
	_restart_scene_path = DEFAULT_RESTART_SCENE_PATH
	_hide_countdown()


func _run_restart_countdown() -> void:
	_show_countdown(RESTART_DELAY_SECONDS)

	for seconds_left in range(RESTART_DELAY_SECONDS, 0, -1):
		_update_countdown(seconds_left)
		restart_countdown_changed.emit(seconds_left)
		await get_tree().create_timer(1.0).timeout

	var error := get_tree().change_scene_to_file(_restart_scene_path)
	if error != OK:
		push_error("Could not reload scene %s: %s" % [_restart_scene_path, error])

	reset_to_playing()


func _get_current_scene_path() -> String:
	var current_scene := get_tree().current_scene
	if current_scene and not current_scene.scene_file_path.is_empty():
		return current_scene.scene_file_path

	return DEFAULT_RESTART_SCENE_PATH


func _show_countdown(seconds_left: int) -> void:
	if _countdown_layer:
		_update_countdown(seconds_left)
		return

	_countdown_layer = CanvasLayer.new()
	_countdown_layer.layer = 100
	_countdown_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_countdown_layer)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_layer.add_child(shade)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_override("font", COUNTDOWN_FONT)
	_countdown_label.add_theme_font_size_override("font_size", 22)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_countdown_label.anchor_left = 0.5
	_countdown_label.anchor_top = 0.5
	_countdown_label.anchor_right = 0.5
	_countdown_label.anchor_bottom = 0.5
	_countdown_label.offset_left = -180.0
	_countdown_label.offset_top = -60.0
	_countdown_label.offset_right = 180.0
	_countdown_label.offset_bottom = 60.0
	_countdown_layer.add_child(_countdown_label)

	_update_countdown(seconds_left)


func _update_countdown(seconds_left: int) -> void:
	if not _countdown_label:
		return

	_countdown_label.text = "GAME OVER\nRestarting in %s" % seconds_left


func _hide_countdown() -> void:
	if not _countdown_layer:
		return

	_countdown_layer.queue_free()
	_countdown_layer = null
	_countdown_label = null
