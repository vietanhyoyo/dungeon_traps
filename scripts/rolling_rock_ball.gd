extends Node2D

const LANDING_DUST_SCENE := preload("res://nodes/effects/landing_dust.tscn")
const DUST_HALF_SIZE := 16.0

## Dấu bẫy nằm trên sàn. Khi player chạm vào, quả cầu rơi từ trên xuống,
## rồi lăn theo chiều ngang về phía player cho đến khi gặp tường.

@export var gravity := 2200.0
@export var max_fall_speed := 1600.0
@export var rolling_speed := 120.0
@export var ball_radius := 42.0
@export var fall_delay := 1.0

@onready var trigger_area: Area2D = $TriggerArea
@onready var trigger_shape: CollisionShape2D = $TriggerArea/CollisionShape2D
@onready var ball: CharacterBody2D = $Ball
@onready var ball_sprite: AnimatedSprite2D = $Ball/BallSprite
@onready var hazard: Area2D = $Ball/Hazard
@onready var landing_sound: AudioStreamPlayer2D = $Ball/LandingSound
@onready var rolling_sound: AudioStreamPlayer2D = $Ball/RollingSound

var _target_player: Node2D
var _player_side_at_trigger := -1.0
var _roll_direction := -1.0
var _has_triggered := false
var _is_falling := false
var _is_breaking := false
var _is_rolling := false


func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	hazard.body_entered.connect(_on_hazard_body_entered)
	ball_sprite.animation_finished.connect(_on_break_animation_finished)
	ball.visible = false
	hazard.monitoring = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _is_game_over():
		rolling_sound.stop()
		# Giữ nguyên frame hiện tại khi va chạm kết thúc màn; stop() sẽ reset về frame đầu.
		ball_sprite.pause()
		set_physics_process(false)
		return

	if _is_falling:
		ball.velocity.y = minf(ball.velocity.y + gravity * delta, max_fall_speed)
		ball.move_and_slide()
		if ball.collision_mask == 0 and ball.global_position.y >= _visible_drop_height():
			# Bật va chạm khi cầu đã đi qua các bục phía trên.
			ball.collision_mask = 1
			hazard.set_deferred("monitoring", true)
		if ball.is_on_floor():
			_start_breaking()
			_spawn_landing_dust()
		return

	if not _is_rolling:
		return

	var was_on_floor := ball.is_on_floor()
	var previous_x := ball.global_position.x
	ball.velocity.x = _roll_direction * rolling_speed
	ball.velocity.y = minf(ball.velocity.y + gravity * delta, max_fall_speed)
	ball.move_and_slide()
	if not was_on_floor and ball.is_on_floor():
		_spawn_landing_dust()
		_start_rolling_sound()
	elif was_on_floor and not ball.is_on_floor():
		rolling_sound.stop()

	# Xoay riêng quả cầu theo quãng đường lăn; lớp bóng đổ giữ nguyên hướng.
	var traveled_x := ball.global_position.x - previous_x
	ball_sprite.rotation += traveled_x / ball_radius

	if ball.is_on_wall() and absf(traveled_x) < 0.25:
		_is_rolling = false
		ball.velocity = Vector2.ZERO
		rolling_sound.stop()
		# Sau khi dừng, cho player va chạm với thân cầu để có thể đứng lên trên.
		ball.set_deferred("collision_layer", 1)
		hazard.set_deferred("monitoring", false)
		set_physics_process(false)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _has_triggered or not body.is_in_group(&"player"):
		return

	_has_triggered = true
	trigger_area.set_deferred("monitoring", false)
	_target_player = body

	var player_offset := body.global_position.x - global_position.x
	if absf(player_offset) > 2.0:
		_player_side_at_trigger = signf(player_offset)
	elif body is CharacterBody2D and absf(body.velocity.x) > 1.0:
		# Khi player vừa đi qua tâm dấu bẫy, vận tốc cho biết họ đã tiến vào từ phía đối diện.
		_player_side_at_trigger = -signf(body.velocity.x)

	await get_tree().create_timer(fall_delay).timeout
	if not is_inside_tree() or _is_game_over():
		return

	# Căn tâm quả cầu theo tâm trigger và bắt đầu ngay ngoài mép trên camera.
	ball.global_position = _get_offscreen_spawn_position()
	ball.velocity = Vector2.ZERO
	ball.collision_mask = 0
	ball.z_index = 7
	ball.visible = true
	ball_sprite.stop()
	ball_sprite.animation = &"break"
	ball_sprite.frame = 0
	ball_sprite.frame_progress = 0.0
	ball_sprite.rotation = 0.0
	_is_falling = true
	set_physics_process(true)


func _start_breaking() -> void:
	_is_falling = false
	_is_breaking = true
	ball.velocity = Vector2.ZERO
	hazard.set_deferred("monitoring", false)

	var target_x := ball.global_position.x + _player_side_at_trigger
	if is_instance_valid(_target_player):
		target_x = _target_player.global_position.x

	var offset_to_player := target_x - ball.global_position.x
	_roll_direction = signf(offset_to_player) if absf(offset_to_player) > 1.0 else _player_side_at_trigger
	ball_sprite.play(&"break")


func _on_break_animation_finished() -> void:
	if not _is_breaking or _is_game_over():
		return
	_is_breaking = false
	ball_sprite.stop()
	ball_sprite.frame = ball_sprite.sprite_frames.get_frame_count(&"break") - 1
	_start_rolling()


func _start_rolling() -> void:
	_is_rolling = true
	ball.velocity.x = _roll_direction * rolling_speed
	hazard.set_deferred("monitoring", true)
	_start_rolling_sound()


func _get_offscreen_spawn_position() -> Vector2:
	var viewport_size := get_viewport_rect().size
	var camera := get_viewport().get_camera_2d()
	var spawn_y := global_position.y - viewport_size.y - ball_radius - 16.0
	if camera:
		var zoom_y := maxf(absf(camera.zoom.y), 0.001)
		var half_view_height := viewport_size.y / (2.0 * zoom_y)
		spawn_y = camera.get_screen_center_position().y - half_view_height - ball_radius - 16.0

	return Vector2(trigger_shape.global_position.x, spawn_y)


func _visible_drop_height() -> float:
	return trigger_shape.global_position.y - ball_radius * 3.0


func _spawn_landing_dust() -> void:
	landing_sound.play()
	var dust: AnimatedSprite2D = LANDING_DUST_SCENE.instantiate()
	var direction := signf(_roll_direction)
	dust.flip_h = direction > 0.0
	get_tree().current_scene.add_child(dust)
	dust.global_position = Vector2(
		ball.global_position.x - direction * 10.0,
		ball.global_position.y + ball_radius - DUST_HALF_SIZE
	)


func _start_rolling_sound() -> void:
	if not rolling_sound.playing:
		rolling_sound.play()


func _on_hazard_body_entered(body: Node2D) -> void:
	if not (_is_falling or _is_rolling) or not body.is_in_group(&"player"):
		return

	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("trigger_game_over"):
		game_state.trigger_game_over(body)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state != null and game_state.has_method("is_game_over") and game_state.is_game_over()
