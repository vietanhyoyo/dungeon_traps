extends CharacterBody2D

signal conversation_finished

const MEMBER_ID := "serelyn"
const SPEED := 180.0
const TRANSFORM_MOMENTUM_DECELERATION := 900.0
const JUMP_VELOCITY := -320.0
const SLIDE_SPEED := 240.0
const SLIDE_DURATION := 0.4
const SLIDE_COLLISION_HEIGHT := 34.0
const WALL_JUMP_VELOCITY := JUMP_VELOCITY
const DEATH_JUMP_VELOCITY := -420.0
const HURT_DURATION := 0.4
const WALL_DUST_REACH := 17.0
const WALL_DUST_HEIGHT := 4.0
const LANDING_DUST_MIN_SPEED := 180.0
const DUST_HALF_SIZE := 16.0
const ARROW_SCENE := preload("res://nodes/characters/serelyn_arrow.tscn")
# Tâm texture mũi tên đặt sao cho thân tên nối tiếp đúng dây cung ở frame cuối
# của animation attack: đầu tên nằm ở khoảng x=59, y=58 trong ô sprite 96x96.
const ARROW_SPAWN_OFFSET := Vector2(30.0, 13.0)
# Ở các animation attack_high, dây cung và tay kéo cung nằm cao hơn khoảng 15 px
# so với đòn thường, nên mũi tên cũng cần xuất hiện ở vị trí cao hơn để không lệch khỏi cung.
const HIGH_ARROW_SPAWN_OFFSET := Vector2(30.0, -2.0)
# attack_low kéo cung thấp hơn đòn thường, nên điểm sinh tên cũng hạ xuống theo.
const LOW_ARROW_SPAWN_OFFSET := Vector2(30.0, 19.0)
const HIGH2_ARROW_ANGLE_THRESHOLD := deg_to_rad(15.0)
const MAX_UPWARD_ARROW_ANGLE := deg_to_rad(60.0)
const MAX_DOWNWARD_ARROW_ANGLE := deg_to_rad(15.0)
const TALK_LINES := [
	["Asura", "Hello, Serelyn!"],
	["Asura", "Would you like to join my team?"],
	["Serelyn", "Yes! I would be happy to join your team."],
]

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var running_sound: AudioStreamPlayer2D = $RunningSound
@onready var bow_shot_sound: AudioStreamPlayer2D = $BowShotSound
@onready var ground_slide_sound: AudioStreamPlayer2D = $GroundSlideSound
@onready var air_slide_sound: AudioStreamPlayer2D = $AirSlideSound
@onready var talk_area: Area2D = $TalkArea
@onready var prompt: Label = $Prompt
@export_node_path("CanvasLayer") var dialogue_layer_path: NodePath
@onready var dialogue_layer: CanvasLayer = _get_dialogue_layer()
@onready var dialog: Control = dialogue_layer.get_node_or_null("Dialog") as Control \
	if dialogue_layer != null else null
@onready var speaker_label: Label = dialog.get_node_or_null("Panel/Margin/Lines/Speaker") as Label \
	if dialog != null else null
@onready var line_label: Label = dialog.get_node_or_null("Panel/Margin/Lines/Line") as Label \
	if dialog != null else null
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var dust_scene = preload("res://nodes/effects/landing_dust.tscn")

var nearby_player: Node2D
var dialogue_open := false
var conversation_completed := false
var line_index := 0
var is_controlled := false
var _preserving_transform_momentum := false
var is_dead := false
var is_hurt := false
var is_sliding := false
var air_slide_used := false
var is_attacking := false
var _attack_target: Node2D
var _attack_aim_local := Vector2.ZERO
var attack_animation: StringName = &"attack"
var slide_direction := 1.0
var slide_time_left := 0.0
var wall_jump_used := false
var was_on_wall := false
var normal_collision_height := 0.0
var normal_collision_position := Vector2.ZERO
var was_on_floor := false
var last_fall_speed := 0.0


func _ready() -> void:
	if _has_dialogue_ui():
		add_to_group(&"dialogue_actors")
	sprite.animation_finished.connect(_on_animation_finished)
	talk_area.body_entered.connect(_on_body_entered)
	talk_area.body_exited.connect(_on_body_exited)
	if dialogue_layer != null:
		dialogue_layer.visible = false
	if dialog != null:
		dialog.visible = false
	if not _has_dialogue_ui():
		talk_area.set_deferred("monitoring", false)
	prompt.visible = false
	body_collision.shape = body_collision.shape.duplicate()
	var capsule := body_collision.shape as CapsuleShape2D
	if capsule:
		normal_collision_height = capsule.height
		normal_collision_position = body_collision.position
	if GameState.has_party_member(MEMBER_ID):
		conversation_completed = true
		_hide_as_npc()


func _physics_process(delta: float) -> void:
	if is_dead:
		running_sound.stop()
		velocity += get_gravity() * delta
		position += velocity * delta
		return
	if get_tree().paused:
		running_sound.stop()
		ground_slide_sound.stop()
		air_slide_sound.stop()
		return
	if is_hurt:
		running_sound.stop()
		return

	# Giống Asura: mỗi lần chạm đất hoặc bám sang một mặt tường mới sẽ hồi lại
	# một cú nhảy tường. Kỹ năng dùng chung được lưu trong GameState.
	if is_on_floor():
		wall_jump_used = false
		air_slide_used = false
	var touching_wall := is_on_wall() and not is_on_floor()
	if touching_wall and not was_on_wall:
		wall_jump_used = false
	was_on_wall = touching_wall

	if is_sliding:
		_preserving_transform_momentum = false
		var cancel_slide := Input.is_action_just_pressed("move_left") or \
			Input.is_action_just_pressed("move_right")
		if cancel_slide:
			stop_slide()
		else:
			running_sound.stop()
			slide_time_left -= delta
			velocity = Vector2(slide_direction * SLIDE_SPEED, 0.0)
			move_and_slide()
			if slide_time_left <= 0.0 or is_on_wall():
				stop_slide()
			return

	if not is_on_floor():
		velocity += get_gravity() * delta
		last_fall_speed = velocity.y

	var direction := Input.get_axis("move_left", "move_right") if is_controlled else 0.0
	if is_controlled and not is_attacking and Input.is_action_just_pressed("attack"):
		is_attacking = true
		var facing := -1.0 if sprite.flip_h else 1.0
		var attack_origin := global_position + Vector2(ARROW_SPAWN_OFFSET.x * facing, ARROW_SPAWN_OFFSET.y)
		var target_info := _find_arrow_target(attack_origin, facing, is_on_floor())
		_attack_target = target_info.get("target") as Node2D
		_attack_aim_local = target_info.get("local_point", Vector2.ZERO)
		if is_on_floor():
			var target := _attack_target
			if target == null:
				attack_animation = &"attack"
			elif target.to_global(_attack_aim_local).y < attack_origin.y:
				var target_angle := _get_arrow_target_angle(attack_origin, target.to_global(_attack_aim_local))
				attack_animation = &"attack_high2" \
					if absf(target_angle) > HIGH2_ARROW_ANGLE_THRESHOLD else &"attack_high"
			elif target.to_global(_attack_aim_local).y > attack_origin.y:
				attack_animation = &"attack_low"
			else:
				attack_animation = &"attack"
		else:
			attack_animation = &"jump_attack"
		sprite.play(attack_animation)

	if is_attacking:
		_preserving_transform_momentum = false
		running_sound.stop()
		if attack_animation == &"jump_attack":
			if direction != 0.0:
				velocity.x = direction * SPEED
				sprite.flip_h = direction < 0.0
			else:
				velocity.x = 0.0
		else:
			velocity.x = 0.0
		move_and_slide()
		if not was_on_floor and is_on_floor() and last_fall_speed > LANDING_DUST_MIN_SPEED:
			spawn_landing_dust()
			last_fall_speed = 0.0
		was_on_floor = is_on_floor()
		return

	var can_slide := is_on_floor() or not air_slide_used
	if is_controlled and not is_attacking \
			and Input.is_action_just_pressed("slide") and can_slide:
		start_slide()
		return

	if is_controlled and Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
		elif _can_wall_jump():
			_start_wall_jump()

	if direction != 0.0:
		velocity.x = direction * SPEED
		_preserving_transform_momentum = false
	elif _preserving_transform_momentum:
		velocity.x = move_toward(velocity.x, 0.0, TRANSFORM_MOMENTUM_DECELERATION * delta)
		if is_zero_approx(velocity.x):
			_preserving_transform_momentum = false
	else:
		velocity.x = 0.0
	if direction != 0.0:
		sprite.flip_h = direction < 0.0
	move_and_slide()
	# Giống Asura: chỉ đẩy thùng khi đang đứng trên sàn và tì vào mặt bên.
	# Đang nhảy, lướt hoặc tấn công thì không đẩy.
	if is_on_floor() and direction != 0.0:
		PushableCrate.push_touching(self, direction)
	if not was_on_floor and is_on_floor() and last_fall_speed > LANDING_DUST_MIN_SPEED:
		spawn_landing_dust()
		last_fall_speed = 0.0
	was_on_floor = is_on_floor()
	var animation_direction := direction
	if animation_direction == 0.0 and _preserving_transform_momentum:
		animation_direction = signf(velocity.x)
	_update_animation(animation_direction)
	_sync_running_sound(animation_direction)


func set_controlled(value: bool, preserve_momentum := false) -> void:
	is_controlled = value
	if value:
		_preserving_transform_momentum = preserve_momentum
		add_to_group(&"player")
	else:
		_preserving_transform_momentum = false
		remove_from_group(&"player")
		running_sound.stop()
		is_attacking = false
		_attack_target = null
		_attack_aim_local = Vector2.ZERO
		wall_jump_used = false
		was_on_wall = false
		attack_animation = &"attack"
		if is_sliding:
			stop_slide()
		velocity.x = 0.0
		_set_running(false)


func _get_dialogue_layer() -> CanvasLayer:
	if dialogue_layer_path.is_empty():
		return null
	return get_node_or_null(dialogue_layer_path) as CanvasLayer


func _has_dialogue_ui() -> bool:
	return dialogue_layer != null and dialog != null \
		and speaker_label != null and line_label != null


func _on_animation_finished() -> void:
	if not is_attacking or sprite.animation != attack_animation:
		return
	is_attacking = false
	if is_controlled and not is_dead and not is_hurt:
		var facing := -1.0 if sprite.flip_h else 1.0
		var spawn_offset := _get_arrow_spawn_offset()
		var origin := global_position + Vector2(spawn_offset.x * facing, spawn_offset.y)
		var arrow: SerelynArrow = ARROW_SCENE.instantiate()
		get_tree().current_scene.add_child(arrow)
		arrow.launch(origin, _get_arrow_direction(origin, facing))
		bow_shot_sound.play()
	_attack_target = null
	_attack_aim_local = Vector2.ZERO
	_update_animation(0.0)


func _get_arrow_spawn_offset() -> Vector2:
	if attack_animation == &"attack_high" or attack_animation == &"attack_high2":
		return HIGH_ARROW_SPAWN_OFFSET
	if attack_animation == &"attack_low":
		return LOW_ARROW_SPAWN_OFFSET
	return ARROW_SPAWN_OFFSET


func _can_wall_jump() -> bool:
	return not wall_jump_used and is_on_wall() and not is_on_floor() \
		and GameState.has_skill(Skills.WALL_DOUBLE_JUMP)


func _start_wall_jump() -> void:
	wall_jump_used = true
	velocity.y = WALL_JUMP_VELOCITY

	# Quay mặt ra khỏi tường rồi phát cùng hiệu ứng bụi như Asura.
	var wall_normal := get_wall_normal()
	if not is_zero_approx(wall_normal.x):
		sprite.flip_h = wall_normal.x < 0.0
		_spawn_wall_dust(wall_normal)
	sprite.play(&"jump_up")


func _spawn_wall_dust(wall_normal: Vector2) -> void:
	var wall_side := -signf(wall_normal.x)
	var dust: AnimatedSprite2D = dust_scene.instantiate()
	dust.flip_h = wall_side > 0.0
	get_parent().add_child(dust)
	dust.global_position = global_position + Vector2(
		wall_side * (WALL_DUST_REACH - DUST_HALF_SIZE),
		WALL_DUST_HEIGHT - DUST_HALF_SIZE
	)


func _get_arrow_direction(origin: Vector2, facing: float) -> Vector2:
	var target := _attack_target
	if not is_instance_valid(target) or not target.is_inside_tree() \
			or not _is_inside_camera(target):
		return Vector2(facing, 0.0)
	var body := target as CollisionObject2D
	if body == null or (body.collision_layer & 4) == 0:
		return Vector2(facing, 0.0)
	var aim_point := target.to_global(_attack_aim_local)
	if (aim_point.x - origin.x) * facing <= 0.0:
		return Vector2(facing, 0.0)

	# Chỉ thay đổi độ cao của đường bay; chiều ngang vẫn giữ đúng hướng nhìn.
	var angle := clampf(
		_get_arrow_target_angle(origin, aim_point),
		-MAX_UPWARD_ARROW_ANGLE,
		MAX_DOWNWARD_ARROW_ANGLE
	)
	return Vector2(facing * cos(angle), sin(angle)).normalized()


func _get_arrow_target_angle(origin: Vector2, aim_point: Vector2) -> float:
	var offset := aim_point - origin
	return atan2(offset.y, absf(offset.x))


func _find_arrow_target(origin: Vector2, facing: float, use_animation_origin := false) -> Dictionary:
	var nearest: Node2D
	var nearest_point := Vector2.ZERO
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := candidate as Node2D
		if enemy == null or not enemy.has_method("die") \
				or not _is_inside_camera(enemy):
			continue
		var visible_point := _find_shootable_point(enemy, origin, facing, use_animation_origin)
		if visible_point.is_empty():
			continue
		var distance := origin.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_point = visible_point["point"]
			nearest_distance = distance
	if nearest == null:
		return {}
	return {"target": nearest, "local_point": nearest.to_local(nearest_point)}


func _find_shootable_point(enemy: Node2D, origin: Vector2, facing: float, use_animation_origin: bool) -> Dictionary:
	for aim_point in _get_target_points(enemy):
		var shot_origin := _get_targeting_origin(aim_point, facing) if use_animation_origin else origin
		var offset := aim_point - shot_origin
		if offset.x * facing <= 0.0:
			continue
		var angle := _get_arrow_target_angle(shot_origin, aim_point)
		if angle < -MAX_UPWARD_ARROW_ANGLE or angle > MAX_DOWNWARD_ARROW_ANGLE:
			continue
		if offset.length() > SerelynArrow.SPEED * SerelynArrow.LIFETIME:
			continue
		var hit := SerelynArrow.raycast_path(
			get_world_2d().direct_space_state, shot_origin, aim_point
		)
		if SerelynArrow.enemy_for_collider(hit.get("collider")) == enemy:
			return {"point": aim_point}
	return {}


func _get_target_points(enemy: Node2D) -> Array[Vector2]:
	var points: Array[Vector2] = [enemy.global_position]
	for path in ["CollisionShape2D", "ArrowHitArea/CollisionShape2D"]:
		var shape_node := enemy.get_node_or_null(path) as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var rect := shape_node.shape.get_rect()
		for fraction in [
			Vector2(0.5, 0.5), Vector2(0.5, 0.2),
			Vector2(0.25, 0.3), Vector2(0.75, 0.3),
			Vector2(0.25, 0.5), Vector2(0.75, 0.5),
			Vector2(0.5, 0.8),
		]:
			points.append(shape_node.to_global(rect.position + rect.size * fraction))
	return points


func _get_targeting_origin(aim_point: Vector2, facing: float) -> Vector2:
	var offset := ARROW_SPAWN_OFFSET
	var default_origin_y := global_position.y + ARROW_SPAWN_OFFSET.y
	if aim_point.y < default_origin_y:
		offset = HIGH_ARROW_SPAWN_OFFSET
	elif aim_point.y > default_origin_y:
		offset = LOW_ARROW_SPAWN_OFFSET
	return global_position + Vector2(offset.x * facing, offset.y)


func _is_inside_camera(target: Node2D) -> bool:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return false
	var view_size := get_viewport_rect().size / camera.zoom.abs()
	var view_center := camera.get_screen_center_position()
	var view_rect := Rect2(view_center - view_size * 0.5, view_size)
	for point in _get_target_points(target):
		if view_rect.has_point(point):
			return true
	return false


func _set_running(value: bool) -> void:
	var animation := &"run" if value else &"idle"
	if sprite.animation != animation:
		sprite.play(animation)


func _update_animation(direction: float) -> void:
	var animation: StringName
	if not is_on_floor():
		animation = &"jump_up" if velocity.y < 0.0 else &"jump_down"
	else:
		animation = &"run" if direction != 0.0 else &"idle"

	if sprite.animation != animation:
		sprite.play(animation)


func _sync_running_sound(direction: float) -> void:
	if not is_controlled or is_dead or is_hurt or is_sliding or is_attacking \
			or not is_on_floor() or direction == 0.0:
		running_sound.stop()
	elif not running_sound.playing:
		running_sound.play()


func start_slide() -> void:
	if not is_controlled:
		return

	_preserving_transform_momentum = false
	var started_in_air := not is_on_floor()
	if started_in_air:
		air_slide_used = true
	is_sliding = true
	running_sound.stop()
	if started_in_air:
		air_slide_sound.play()
	else:
		ground_slide_sound.play()
	slide_time_left = SLIDE_DURATION
	slide_direction = -1.0 if sprite.flip_h else 1.0
	velocity = Vector2(slide_direction * SLIDE_SPEED, 0.0)
	set_slide_collision(true)
	sprite.play(&"slide-air" if started_in_air else &"slide")
	if not started_in_air:
		spawn_landing_dust()


func stop_slide() -> void:
	is_sliding = false
	ground_slide_sound.stop()
	air_slide_sound.stop()
	slide_time_left = 0.0
	velocity.x = 0.0
	set_slide_collision(false)
	if not is_dead:
		sprite.play("idle")


func set_slide_collision(enabled: bool) -> void:
	var capsule := body_collision.shape as CapsuleShape2D
	if not capsule:
		return

	if enabled:
		capsule.height = SLIDE_COLLISION_HEIGHT
		body_collision.position.y = normal_collision_position.y + \
			(normal_collision_height - SLIDE_COLLISION_HEIGHT) * 0.5
	else:
		capsule.height = normal_collision_height
		body_collision.position = normal_collision_position


func spawn_landing_dust() -> void:
	var facing := -1 if sprite.flip_h else 1
	var dust: AnimatedSprite2D = dust_scene.instantiate()
	dust.flip_h = not sprite.flip_h
	get_parent().add_child(dust)
	# Đặt đáy ô bụi trùng với đáy capsule của Serelyn. Collision của Serelyn
	# thấp hơn Asura 16px nên dùng vị trí collision thay vì offset cố định của Asura.
	var ground_y := normal_collision_position.y + normal_collision_height * 0.5
	dust.global_position = global_position + Vector2(
		-facing * 10,
		ground_y - DUST_HALF_SIZE
	)


func take_hit() -> void:
	if is_hurt or is_dead:
		return

	is_attacking = false
	is_sliding = false
	running_sound.stop()
	ground_slide_sound.stop()
	air_slide_sound.stop()
	set_slide_collision(false)
	is_hurt = true
	set_controlled(false)
	velocity = Vector2.ZERO

	if sprite.sprite_frames.has_animation(&"hust"):
		sprite.play(&"hust")

	await get_tree().create_timer(HURT_DURATION).timeout


func die() -> void:
	if is_dead:
		return
	is_dead = true
	set_controlled(false)
	velocity = Vector2(0.0, DEATH_JUMP_VELOCITY)
	collision_layer = 0
	collision_mask = 0
	body_collision.set_deferred("disabled", true)
	if sprite.sprite_frames.has_animation(&"death"):
		sprite.play(&"death")
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.reparent(get_tree().current_scene, true)
		camera.position_smoothing_enabled = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("ui_cancel"):
		if dialogue_open:
			_hide_dialogue()
			get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("interact"):
		return
	if GameState.is_game_over() or conversation_completed:
		return
	if dialogue_open:
		_next_line()
	elif not get_tree().paused and _has_player_in_talk_area():
		_start_dialogue()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	if conversation_completed or not body.is_in_group(&"player"):
		return
	nearby_player = body
	prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body != nearby_player:
		return
	nearby_player = null
	prompt.visible = false


func _has_player_in_talk_area() -> bool:
	if is_instance_valid(nearby_player) and nearby_player.is_in_group(&"player"):
		return true
	for body in talk_area.get_overlapping_bodies():
		if body is CharacterBody2D and body.is_in_group(&"player"):
			nearby_player = body
			return true
	return false


func _start_dialogue() -> void:
	if not _has_dialogue_ui():
		return
	dialogue_open = true
	dialogue_layer.visible = true
	dialog.visible = true
	prompt.visible = false
	_show_line()
	get_tree().paused = true


func _hide_dialogue() -> void:
	dialogue_open = false
	if dialog != null:
		dialog.visible = false
	if dialogue_layer != null:
		dialogue_layer.visible = false
	get_tree().paused = false
	prompt.visible = _has_player_in_talk_area()


func _next_line() -> void:
	line_index += 1
	if line_index >= TALK_LINES.size():
		dialogue_open = false
		conversation_completed = true
		if dialog != null:
			dialog.visible = false
		if dialogue_layer != null:
			dialogue_layer.visible = false
		prompt.visible = false
		nearby_player = null
		_hide_as_npc()
		get_tree().paused = false
		GameState.recruit_party_member(MEMBER_ID)
		conversation_finished.emit()
		return
	_show_line()


func _hide_as_npc() -> void:
	visible = false
	prompt.visible = false
	collision_layer = 0
	collision_mask = 0
	talk_area.set_deferred("monitoring", false)


func _show_line() -> void:
	if speaker_label == null or line_label == null:
		return
	speaker_label.text = TALK_LINES[line_index][0]
	line_label.text = TALK_LINES[line_index][1]
