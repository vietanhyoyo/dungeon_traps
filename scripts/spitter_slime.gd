@tool
extends CharacterBody2D

const BULLET_SCENE := preload("res://nodes/enemies/spitter_slime_bullet.tscn")
const DEATH_SMOKE_SCENE := preload("res://nodes/effects/spitter_slime_smoke.tscn")
const HIT_FLASH_COUNT := 3
const HIT_FLASH_ON_DURATION := 0.04
const HIT_FLASH_OFF_DURATION := 0.035
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5
const ATTACK_RELEASE_FRAME := 4
const PROJECTILE_GRAVITY := 620.0
const DEATH_BURST_BULLET_COUNT := 5
const DEATH_BURST_ANGLE_MIN_DEGREES := 50.0

enum State { WAIT, PATROL, ATTACK, DEAD }

@export_group("Movement")
@export_range(0.0, 300.0, 1.0, "or_greater") var move_speed := 30.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var patrol_distance := 64.0:
	set(value):
		patrol_distance = value
		queue_redraw()
@export_range(0.1, 8.0, 0.1, "or_greater") var wait_before_move_min := 1.5
@export_range(0.1, 8.0, 0.1, "or_greater") var wait_before_move_max := 2.5
@export_range(0.1, 8.0, 0.1, "or_greater") var patrol_duration_min := 2.0
@export_range(0.1, 8.0, 0.1, "or_greater") var patrol_duration_max := 3.5

@export_group("Detection")
## Bán kính phát hiện player; vùng tròn được vẽ trong editor để dễ đặt slime.
@export_range(32.0, 800.0, 1.0, "or_greater") var detection_radius := 280.0:
	set(value):
		detection_radius = value
		_apply_detection_radius()
		queue_redraw()
@export_range(0.0, 3.0, 0.05) var first_shot_delay := 0.6

@export_group("Shooting")
@export_range(0.1, 8.0, 0.1, "or_greater") var wait_after_attack_min := 1.8
@export_range(0.1, 8.0, 0.1, "or_greater") var wait_after_attack_max := 3.0
@export_range(32.0, 500.0, 1.0, "or_greater") var bullet_apex_height := 140.0
@export_range(100.0, 700.0, 10.0, "or_greater") var launch_speed_min := 283.0
@export_range(100.0, 700.0, 10.0, "or_greater") var launch_speed_max := 396.0

var is_dead := false
var _state := State.WAIT
var _phase_timer := 0.0
var _start_x := 0.0
var _direction := 1
var _target: Node2D = null
var _has_started_attack := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_area: Area2D = $DetectionArea
@onready var detection_shape: CollisionShape2D = $DetectionArea/CollisionShape2D
@onready var muzzle: Marker2D = $Muzzle
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSound
@onready var move_sound: AudioStreamPlayer2D = $MoveSound
@onready var floor_probe: RayCast2D = $FloorProbe


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_apply_detection_radius()
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
	if animated_sprite.material:
		animated_sprite.material = animated_sprite.material.duplicate()
	animated_sprite.animation_finished.connect(_on_animation_finished)
	_start_x = global_position.x
	_phase_timer = _random_duration(wait_before_move_min, wait_before_move_max)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_dead:
		return

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity += get_gravity() * delta

	if _has_valid_target():
		_face_towards(_target.global_position.x)

	match _state:
		State.WAIT:
			velocity.x = 0.0
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				if _has_valid_target():
					_start_attack()
				else:
					_start_patrol()
		State.PATROL:
			if _has_valid_target():
				_start_attack()
			else:
				_process_patrol(delta)
		State.ATTACK:
			velocity.x = 0.0

	move_and_slide()
	if _state == State.PATROL and _phase_timer <= 0.0:
		if _has_valid_target():
			_start_attack()
		else:
			_state = State.WAIT
			_phase_timer = _random_duration(wait_before_move_min, wait_before_move_max)
			move_sound.stop()
			_play_animation(&"idle")


func _start_patrol() -> void:
	_state = State.PATROL
	_phase_timer = _random_duration(patrol_duration_min, patrol_duration_max)
	_play_animation(&"move")
	move_sound.play()


func _process_patrol(delta: float) -> void:
	_phase_timer -= delta
	if is_on_floor():
		if global_position.x >= _start_x + patrol_distance:
			_direction = -1
		elif global_position.x <= _start_x - patrol_distance:
			_direction = 1
		else:
			floor_probe.position.x = _direction * 16.0
			floor_probe.force_raycast_update()
			if not floor_probe.is_colliding():
				_direction *= -1
	if is_on_wall():
		_direction *= -1

	animated_sprite.flip_h = _direction > 0
	_play_animation(&"move")
	if not move_sound.playing:
		move_sound.play()
	velocity.x = _direction * move_speed


func _face_towards(target_x: float) -> void:
	var direction := signf(target_x - global_position.x)
	if is_zero_approx(direction):
		return

	_direction = int(direction)
	animated_sprite.flip_h = _direction > 0


func _start_attack() -> void:
	_state = State.ATTACK
	_has_started_attack = true
	velocity.x = 0.0
	move_sound.stop()
	animated_sprite.play(&"attack")

	var attack_speed := maxf(animated_sprite.sprite_frames.get_animation_speed(&"attack"), 0.01)
	await get_tree().create_timer(ATTACK_RELEASE_FRAME / attack_speed, false).timeout
	if is_dead or not is_inside_tree() or not _has_valid_target():
		return

	var launch_velocity := _get_targeted_launch_velocity(muzzle.global_position)
	var bullet := BULLET_SCENE.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.launch(muzzle.global_position, launch_velocity)
	shoot_sound.play()


func _get_targeted_launch_velocity(origin: Vector2) -> Vector2:
	var player := _target if _has_valid_target() else null
	var configured_minimum_speed := launch_speed_min if launch_speed_min > 0.0 else 283.0
	var minimum_speed := minf(configured_minimum_speed, maxf(launch_speed_max, configured_minimum_speed))
	var vertical_speed := sqrt(2.0 * PROJECTILE_GRAVITY * bullet_apex_height)
	if player == null:
		return Vector2(_direction * minimum_speed * 0.5, -vertical_speed)

	var target_offset := player.global_position - origin
	# Với mục tiêu cao hơn đỉnh quỹ đạo, nhắm vào điểm cao nhất có thể tới.
	var reachable_target_height := maxf(target_offset.y, -bullet_apex_height)
	var descent_vertical_speed := sqrt(maxf(
		vertical_speed * vertical_speed + 2.0 * PROJECTILE_GRAVITY * reachable_target_height,
		0.0
	))
	var descent_time := (
		vertical_speed
		+ descent_vertical_speed
	) / PROJECTILE_GRAVITY
	var horizontal_speed := target_offset.x / maxf(descent_time, 0.01)
	return Vector2(horizontal_speed, -vertical_speed)


func _on_animation_finished() -> void:
	if is_dead or _state != State.ATTACK or animated_sprite.animation != &"attack":
		return
	_state = State.WAIT
	_phase_timer = _random_duration(wait_after_attack_min, wait_after_attack_max)
	animated_sprite.play(&"idle")


func _play_animation(animation_name: StringName) -> void:
	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)


func _random_duration(minimum: float, maximum: float) -> float:
	return randf_range(minf(minimum, maximum), maxf(minimum, maximum))


func _has_valid_target() -> bool:
	if is_instance_valid(_target) and _target.is_in_group(&"player"):
		return true
	_target = null
	return false


func _apply_detection_radius() -> void:
	if detection_shape == null:
		return

	var shape := detection_shape.shape as CircleShape2D
	if shape:
		shape.radius = detection_radius


func _on_detection_body_entered(body: Node2D) -> void:
	if is_dead or not body.is_in_group(&"player"):
		return

	_target = body
	if _state == State.PATROL:
		_state = State.WAIT
		_phase_timer = first_shot_delay
		velocity.x = 0.0
		move_sound.stop()
		_play_animation(&"idle")
	elif _state == State.WAIT and not _has_started_attack:
		_phase_timer = minf(_phase_timer, first_shot_delay)


func _on_detection_body_exited(body: Node2D) -> void:
	if body == _target:
		_target = null


func die() -> void:
	if is_dead:
		return

	is_dead = true
	_state = State.DEAD
	velocity = Vector2.ZERO
	move_sound.stop()
	animated_sprite.pause()
	collision_shape.set_deferred("disabled", true)
	detection_area.set_deferred("monitoring", false)
	_spawn_death_bullets()
	_spawn_death_smoke()
	_play_defeat_sound()
	await _play_hit_flash()
	if not is_inside_tree():
		return

	var death_tween := create_tween().set_parallel(true)
	death_tween.tween_property(self, "scale", Vector2.ZERO, 0.18)
	death_tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.18)
	await death_tween.finished
	if is_inside_tree():
		queue_free()


func _spawn_death_bullets() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var origin := global_position + Vector2(0.0, -16.0)
	var configured_minimum_speed := launch_speed_min if launch_speed_min > 0.0 else 283.0
	var configured_maximum_speed := launch_speed_max if launch_speed_max > 0.0 else 396.0
	var speed := (
		minf(configured_minimum_speed, configured_maximum_speed)
		+ maxf(configured_minimum_speed, configured_maximum_speed)
	) * 0.5
	var horizontal_speed_limit := speed * cos(deg_to_rad(DEATH_BURST_ANGLE_MIN_DEGREES))
	var vertical_speed := sqrt(2.0 * PROJECTILE_GRAVITY * bullet_apex_height)
	for bullet_index in DEATH_BURST_BULLET_COUNT:
		var spread := float(bullet_index) / float(DEATH_BURST_BULLET_COUNT - 1)
		var horizontal_speed := lerpf(-horizontal_speed_limit, horizontal_speed_limit, spread)
		var launch_velocity := Vector2(horizontal_speed, -vertical_speed)
		var bullet := BULLET_SCENE.instantiate()
		current_scene.add_child(bullet)
		bullet.launch(origin, launch_velocity)


func _spawn_death_smoke() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var smoke := DEATH_SMOKE_SCENE.instantiate() as Node2D
	if smoke == null:
		return
	current_scene.add_child(smoke)
	smoke.global_position = global_position


func _play_defeat_sound() -> void:
	if Engine.is_editor_hint():
		return

	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEFEAT_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	sound_player.play(DEFEAT_SOUND_OFFSET)


func _play_hit_flash() -> void:
	if not animated_sprite.material is ShaderMaterial:
		return

	var flash_material := animated_sprite.material as ShaderMaterial
	for flash_index in HIT_FLASH_COUNT:
		flash_material.set_shader_parameter("flash_amount", 1.0)
		await get_tree().create_timer(HIT_FLASH_ON_DURATION, false).timeout
		flash_material.set_shader_parameter("flash_amount", 0.0)

		if flash_index < HIT_FLASH_COUNT - 1:
			await get_tree().create_timer(HIT_FLASH_OFF_DURATION, false).timeout


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	const DETECTION_COLOR := Color(1.0, 0.35, 0.35, 0.7)
	draw_arc(Vector2.ZERO, detection_radius, 0.0, TAU, 48, DETECTION_COLOR, 1.0)
	if patrol_distance <= 0.0:
		return

	const PATROL_COLOR := Color(1.0, 0.85, 0.2, 0.9)
	var left := -patrol_distance
	var right := patrol_distance
	var guide_y := 16.0
	draw_line(Vector2(left, guide_y), Vector2(right, guide_y), PATROL_COLOR, 1.0)
	draw_line(Vector2(left, guide_y - 8.0), Vector2(left, guide_y + 4.0), PATROL_COLOR, 1.0)
	draw_line(Vector2(right, guide_y - 8.0), Vector2(right, guide_y + 4.0), PATROL_COLOR, 1.0)
