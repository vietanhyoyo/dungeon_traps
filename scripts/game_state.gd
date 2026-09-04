extends Node
class_name GameStateManager

signal game_over_started(player: Node2D)
signal restart_countdown_changed(seconds_left: int)
signal checkpoint_activated(scene_path: String, spawn_position: Vector2)

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
var _checkpoint_scene_path := ""
var _checkpoint_position := Vector2.ZERO
## scene_path -> { star_id: true }. Giữ ngoài scene để sao đã ăn không mất
## khi chết và hồi sinh ở save point.
var _collected_stars := {}
## scene_path -> { chest_id: true }, giữ rương đã mở khi hồi sinh.
var _opened_chests := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_game_over_sound_player = AudioStreamPlayer.new()
	_game_over_sound_player.stream = GAME_OVER_SOUND
	_game_over_sound_player.bus = &"SFX"
	_game_over_sound_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_game_over_sound_player)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_counting_down:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			_restart_now()


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


func activate_checkpoint(spawn_position: Vector2) -> void:
	_checkpoint_scene_path = _get_current_scene_path()
	_checkpoint_position = spawn_position
	checkpoint_activated.emit(_checkpoint_scene_path, _checkpoint_position)


func is_checkpoint_active(spawn_position: Vector2) -> bool:
	return _checkpoint_scene_path == _get_current_scene_path() and \
		_checkpoint_position.is_equal_approx(spawn_position)


func collect_star(star_id: String) -> void:
	var scene_path := _get_current_scene_path()
	if not _collected_stars.has(scene_path):
		_collected_stars[scene_path] = {}
	_collected_stars[scene_path][star_id] = true


func is_star_collected(star_id: String) -> bool:
	return _stars_of_current_scene().has(star_id)


func get_collected_star_count() -> int:
	return _stars_of_current_scene().size()


func mark_chest_opened(chest_id: String) -> void:
	var scene_path := _get_current_scene_path()
	if not _opened_chests.has(scene_path):
		_opened_chests[scene_path] = {}
	_opened_chests[scene_path][chest_id] = true


func is_chest_opened(chest_id: String) -> bool:
	var opened: Dictionary = _opened_chests.get(_get_current_scene_path(), {})
	return opened.has(chest_id)


## Xoá tiến độ (sao + rương + save point) của một màn để chơi lại từ đầu. Bỏ trống
## scene_path thì xoá tiến độ của tất cả các màn.
func clear_level_progress(scene_path := "") -> void:
	if scene_path.is_empty():
		_collected_stars.clear()
		_opened_chests.clear()
		_checkpoint_scene_path = ""
		_checkpoint_position = Vector2.ZERO
		return

	_collected_stars.erase(scene_path)
	_opened_chests.erase(scene_path)
	if _checkpoint_scene_path == scene_path:
		_checkpoint_scene_path = ""
		_checkpoint_position = Vector2.ZERO


func _stars_of_current_scene() -> Dictionary:
	return _collected_stars.get(_get_current_scene_path(), {})


func reset_to_playing() -> void:
	state = State.PLAYING
	_is_counting_down = false
	_restart_scene_path = DEFAULT_RESTART_SCENE_PATH
	_hide_countdown()


func _run_restart_countdown() -> void:
	_show_countdown(RESTART_DELAY_SECONDS)

	for seconds_left in range(RESTART_DELAY_SECONDS, 0, -1):
		# Kiểm tra nếu đã restart sớm (nhấn Space/Enter)
		if not _is_counting_down:
			return
		_update_countdown(seconds_left)
		restart_countdown_changed.emit(seconds_left)
		await get_tree().create_timer(1.0).timeout

	# Có thể đã restart sớm trong lúc chờ timer cuối
	if not _is_counting_down:
		return

	_restart_now()


func _restart_now() -> void:
	if not _is_counting_down:
		return

	var scene_path := _restart_scene_path
	var should_restore_checkpoint := _checkpoint_scene_path == scene_path
	var checkpoint_position := _checkpoint_position
	reset_to_playing()

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not reload scene %s: %s" % [scene_path, error])
	elif should_restore_checkpoint:
		_restore_checkpoint_after_scene_change(checkpoint_position)


func _restore_checkpoint_after_scene_change(spawn_position: Vector2) -> void:
	# change_scene_to_file thay scene ở cuối frame; chờ player mới vào SceneTree
	# rồi mới gán vị trí. Thử vài frame để ổn định cả khi scene tải chậm.
	for attempt in 3:
		await get_tree().process_frame
		var player: CharacterBody2D
		for candidate in get_tree().get_nodes_in_group(&"player"):
			if candidate is CharacterBody2D:
				player = candidate
				break
		if player:
			player.global_position = spawn_position
			player.velocity = Vector2.ZERO
			return

	push_warning("Checkpoint could not find a player after scene reload")


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
