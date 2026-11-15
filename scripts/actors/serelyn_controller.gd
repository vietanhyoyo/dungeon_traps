extends CharacterBody2D

signal conversation_finished

const MEMBER_ID := "serelyn"
const TELEPORT_EFFECT := preload("res://nodes/effects/character_transform_effect.tscn")
const SPEED := 180.0
const TRANSFORM_MOMENTUM_DECELERATION := 900.0
const JUMP_VELOCITY := -320.0
const WALL_SLIDE_SPEED := 80.0
const WALL_SLIDE_SPRITE_OFFSET := Vector2(0.0, 16.0)
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
## Địa hình chặn tên giữa thân Serelyn và điểm tạo tên (xem _clamp_shot_origin).
const SHOT_BLOCKING_MASK := 1
## Điểm bắn bị kéo về cách mặt tường bấy nhiêu px, để tên chạm tường ở frame đầu.
const SHOT_WALL_MARGIN := 1.0
# Ở các animation attack_high, dây cung và tay kéo cung nằm cao hơn khoảng 15 px
# so với đòn thường, nên mũi tên cũng cần xuất hiện ở vị trí cao hơn để không lệch khỏi cung.
const HIGH_ARROW_SPAWN_OFFSET := Vector2(30.0, -2.0)
# attack_low kéo cung thấp hơn đòn thường, nên điểm sinh tên cũng hạ xuống theo.
const LOW_ARROW_SPAWN_OFFSET := Vector2(30.0, 19.0)
## Kỹ năng Charged Arrow: giữ C đủ lâu thì bắn mũi tên xanh sát thương lớn.
const CHARGED_ARROW_SCENE := preload("res://nodes/characters/serelyn_charged_arrow.tscn")
## Giữ C bấy nhiêu giây thì tên được gồng đầy. Nhả sớm hơn là bắn tên thường.
const CHARGE_TIME := 0.4
## Ánh sáng ở mũi tên lúc gồng, tăng dần tới mức này khi đầy.
const CHARGE_GLOW_MAX_ENERGY := 1.6
## Khung "đã kéo căng dây" trong các animation ngắm (attack, attack_high,
## attack_high2, attack_low). Giữ C thì dừng ở khung này, nhả C thì chạy tiếp.
const AIM_HOLD_FRAME := 1
## Vị trí mũi tên ở AIM_HOLD_FRAME, tính từ tâm khung 96x96 khi nhìn sang phải.
## Vòng sáng gồng tên đặt đúng ở đây nên bám theo từng tư thế ngắm.
const AIM_TIP_OFFSETS := {
	&"attack": Vector2(38.0, 10.0),
	&"attack_high": Vector2(37.0, -3.0),
	&"attack_high2": Vector2(23.0, -15.0),
	&"attack_low": Vector2(36.0, 21.0),
}
## Trong lúc gồng, cứ bấy nhiêu giây lại ngắm lại mục tiêu để đổi tư thế cho khớp.
const CHARGE_AIM_REFRESH := 0.15
## Góc mũi tên vẽ trong khung kéo dây của từng animation ngắm (radian, âm là
## chếch lên), đo từ Serelyn-attack.png. Dùng để chọn tư thế khớp góc bay thật.
## Thứ tự cũng là thứ tự ưu tiên khi hai tư thế khớp như nhau.
const AIM_POSE_ANGLES := {
	&"attack": 0.0,
	&"attack_high": deg_to_rad(-18.0),
	&"attack_low": deg_to_rad(21.0),
	&"attack_high2": deg_to_rad(-42.0),
}
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
@onready var wall_slide_sound: AudioStreamPlayer2D = $WallSlideSound
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
@onready var wall_slide_detector: Area2D = $WallSlideDetector
@onready var dust_scene = preload("res://nodes/effects/landing_dust.tscn")
@onready var charge_glow: PointLight2D = $ChargeGlow
## Tiếng kéo dây cung + năng lượng dâng lên lúc bắt đầu giữ C.
@onready var charge_draw_sound: AudioStreamPlayer2D = $ChargeDrawSound
## Tiếng chuông pha lê khi gồng đầy.
@onready var charge_ready_sound: AudioStreamPlayer2D = $ChargeReadySound
@onready var charge_orb: AnimatedSprite2D = $ChargeOrb

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
var is_charging := false
var charge_time := 0.0
var charge_ready := false
var _charge_aim_timer := 0.0
## Phát bắn đang chạy là tên gồng (nhả C sau khi đã gồng đầy).
var _shot_is_charged := false
var slide_direction := 1.0
var slide_time_left := 0.0
var wall_jump_used := false
var was_on_wall := false
var normal_collision_height := 0.0
var normal_collision_position := Vector2.ZERO
var normal_sprite_position := Vector2.ZERO
var was_on_floor := false
var last_fall_speed := 0.0


func _ready() -> void:
	var wall_slide_stream := wall_slide_sound.stream as AudioStreamWAV
	if wall_slide_stream:
		wall_slide_stream.loop_begin = 0
		wall_slide_stream.loop_end = roundi(
			wall_slide_stream.mix_rate * wall_slide_stream.get_length()
		)
		wall_slide_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	if _has_dialogue_ui():
		add_to_group(&"dialogue_actors")
	sprite.animation_finished.connect(_on_animation_finished)
	charge_glow.visible = false
	charge_orb.visible = false
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	talk_area.body_entered.connect(_on_body_entered)
	talk_area.body_exited.connect(_on_body_exited)
	if dialogue_layer != null:
		dialogue_layer.visible = false
	if dialog != null:
		dialog.visible = false
	if not _has_dialogue_ui():
		talk_area.set_deferred("monitoring", false)
	prompt.visible = false
	normal_sprite_position = sprite.position
	body_collision.shape = body_collision.shape.duplicate()
	var capsule := body_collision.shape as CapsuleShape2D
	if capsule:
		normal_collision_height = capsule.height
		normal_collision_position = body_collision.position
	if GameState.has_party_member(MEMBER_ID):
		conversation_completed = true
		_hide_as_npc()
	_play_spawn_effect()


func _play_spawn_effect() -> void:
	if not is_visible_in_tree():
		return
	var effect: CharacterTransformEffect = TELEPORT_EFFECT.instantiate()
	add_child(effect)
	effect.play(self)


func _physics_process(delta: float) -> void:
	if is_dead:
		running_sound.stop()
		wall_slide_sound.stop()
		velocity += get_gravity() * delta
		position += velocity * delta
		return
	if get_tree().paused:
		running_sound.stop()
		ground_slide_sound.stop()
		air_slide_sound.stop()
		wall_slide_sound.stop()
		return
	if is_hurt:
		running_sound.stop()
		wall_slide_sound.stop()
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
		wall_slide_sound.stop()
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
	if is_controlled and not is_attacking and not is_charging \
			and Input.is_action_just_pressed("attack"):
		# Có kỹ năng Charged Arrow và đang đứng trên sàn: bấm C vẫn vào tư thế
		# ngắm như thường nhưng dừng ở lúc kéo căng dây cho tới khi nhả C.
		if is_on_floor() and GameState.has_skill(Skills.CHARGED_ARROW):
			_start_charge()
		else:
			_start_attack()

	if is_charging:
		_process_charge(delta, direction)
		return

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
		wall_slide_sound.stop()
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
	var wall_sliding := _is_wall_sliding(direction)
	if wall_sliding:
		velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)
	move_and_slide()
	wall_sliding = _is_wall_sliding(direction)
	if wall_sliding:
		velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)
	# Đang nhảy lên mà chạm tường thì vẫn là jump_up, chỉ trượt tường khi đã rơi xuống.
	wall_sliding = wall_sliding and velocity.y >= 0.0
	_sync_wall_slide_sound(wall_sliding)
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
	_update_animation(animation_direction, wall_sliding)
	_sync_running_sound(animation_direction)


func _start_attack() -> void:
	is_attacking = true
	_shot_is_charged = false
	_choose_attack_pose()
	sprite.position = normal_sprite_position
	sprite.play(attack_animation)


## Tìm mục tiêu và chọn animation ngắm (ngang, chếch lên, dốc lên, chếch xuống).
func _choose_attack_pose() -> void:
	var facing := -1.0 if sprite.flip_h else 1.0
	var attack_origin := _clamp_shot_origin(
		global_position + Vector2(ARROW_SPAWN_OFFSET.x * facing, ARROW_SPAWN_OFFSET.y)
	)
	var target_info := _find_arrow_target(attack_origin, facing, is_on_floor())
	_attack_target = target_info.get("target") as Node2D
	_attack_aim_local = target_info.get("local_point", Vector2.ZERO)
	if not is_on_floor():
		attack_animation = &"jump_attack"
		return
	attack_animation = &"attack"
	var target := _attack_target
	if target == null:
		return

	# 1) Bắn thẳng ngang mà trúng được thì luôn chọn tư thế ngang, và ngắm đúng
	#    điểm trúng trên đường ngang để mũi tên bay thẳng.
	var horizontal_hit := _horizontal_hit_point(target, attack_origin, facing)
	if not horizontal_hit.is_empty():
		_attack_aim_local = target.to_local(horizontal_hit["point"])
		return

	# 2) Không thì thử từng tư thế, mỗi tư thế bắn từ đúng điểm sinh tên của nó,
	#    và chọn tư thế có góc cung vẽ trong animation gần góc bay thật nhất.
	var best_cost := INF
	for pose: StringName in AIM_POSE_ANGLES:
		var origin := _clamp_shot_origin(global_position + Vector2(
			_get_arrow_spawn_offset(pose).x * facing, _get_arrow_spawn_offset(pose).y
		))
		for point in _get_target_points(target):
			if not _can_shoot_point(target, origin, point, facing):
				continue
			var cost := absf(_get_arrow_target_angle(origin, point) - AIM_POSE_ANGLES[pose])
			if cost < best_cost:
				best_cost = cost
				attack_animation = pose
				_attack_aim_local = target.to_local(point)


## Điểm trúng target nếu bắn thẳng ngang từ origin, rỗng nếu trượt/bị chặn.
func _horizontal_hit_point(target: Node2D, origin: Vector2, facing: float) -> Dictionary:
	var reach := SerelynArrow.SPEED * SerelynArrow.LIFETIME
	var hit := SerelynArrow.raycast_path(
		get_world_2d().direct_space_state, origin, origin + Vector2(facing * reach, 0.0)
	)
	if hit.is_empty() or SerelynArrow.shootable_target_for_collider(hit.get("collider")) != target:
		return {}
	return {"point": hit["position"]}


## Tên bay từ origin tới point có trúng target không (đúng hướng, trong giới hạn
## góc và tầm bay, không bị tường chặn).
func _can_shoot_point(target: Node2D, origin: Vector2, point: Vector2, facing: float) -> bool:
	var offset := point - origin
	if offset.x * facing <= 0.0:
		return false
	var angle := _get_arrow_target_angle(origin, point)
	if angle < -MAX_UPWARD_ARROW_ANGLE or angle > MAX_DOWNWARD_ARROW_ANGLE:
		return false
	if offset.length() > SerelynArrow.SPEED * SerelynArrow.LIFETIME:
		return false
	var hit := SerelynArrow.raycast_path(get_world_2d().direct_space_state, origin, point)
	return SerelynArrow.shootable_target_for_collider(hit.get("collider")) == target


## Bắt đầu gồng: vào đúng animation ngắm như bắn thường, sprite sẽ dừng ở
## AIM_HOLD_FRAME (xem _on_sprite_frame_changed) và vòng sáng xanh hiện ở mũi tên.
func _start_charge() -> void:
	is_charging = true
	charge_time = 0.0
	charge_ready = false
	_charge_aim_timer = CHARGE_AIM_REFRESH
	running_sound.stop()
	wall_slide_sound.stop()
	_preserving_transform_momentum = false
	_choose_attack_pose()
	sprite.position = normal_sprite_position
	sprite.play(attack_animation)
	charge_orb.speed_scale = 1.0
	charge_orb.play(&"grow")
	charge_draw_sound.play()
	charge_orb.visible = true
	charge_glow.visible = true
	_update_charge_effect()


func _on_sprite_frame_changed() -> void:
	if is_charging and AIM_TIP_OFFSETS.has(sprite.animation) \
			and sprite.frame >= AIM_HOLD_FRAME:
		sprite.pause()
		sprite.frame = AIM_HOLD_FRAME


## Đứng yên giữ dây cung. Vẫn quay trái/phải được, và tư thế ngắm tự đổi theo
## vị trí mục tiêu (lên/xuống) trong lúc gồng.
func _process_charge(delta: float, direction: float) -> void:
	velocity.x = 0.0
	var turned := direction != 0.0 and (direction < 0.0) != sprite.flip_h
	if direction != 0.0:
		sprite.flip_h = direction < 0.0
	move_and_slide()
	was_on_floor = is_on_floor()

	_charge_aim_timer -= delta
	if turned or _charge_aim_timer <= 0.0:
		_charge_aim_timer = CHARGE_AIM_REFRESH
		_refresh_charge_pose()

	charge_time += delta
	if not charge_ready and charge_time >= CHARGE_TIME:
		charge_ready = true
		charge_orb.play(&"full")
		charge_ready_sound.play()
	_update_charge_effect()

	if Input.is_action_pressed("attack"):
		return

	# Nhả C: chạy nốt animation ngắm hiện tại (buông dây), mũi tên bay ra ở
	# _on_animation_finished giống bắn thường, chỉ khác loại tên.
	_shot_is_charged = charge_ready
	_cancel_charge()
	is_attacking = true
	sprite.play(attack_animation)


func _refresh_charge_pose() -> void:
	var previous := attack_animation
	_choose_attack_pose()
	if attack_animation == previous:
		return
	# Đã kéo căng dây rồi thì đổi thẳng sang khung giữ dây của tư thế mới.
	var drawn := sprite.frame >= AIM_HOLD_FRAME or not sprite.is_playing()
	sprite.play(attack_animation)
	if drawn:
		sprite.pause()
		sprite.frame = AIM_HOLD_FRAME


func _cancel_charge() -> void:
	is_charging = false
	charge_time = 0.0
	charge_ready = false
	charge_glow.energy = 0.0
	charge_glow.visible = false
	charge_orb.stop()
	charge_orb.visible = false
	# Nhả C sớm hoặc bị ngắt giữa chừng thì tắt luôn tiếng kéo dây.
	charge_draw_sound.stop()


func _update_charge_effect() -> void:
	var facing := -1.0 if sprite.flip_h else 1.0
	var tip: Vector2 = AIM_TIP_OFFSETS.get(attack_animation, AIM_TIP_OFFSETS[&"attack"])
	var tip_position := sprite.position + Vector2(tip.x * facing, tip.y)
	charge_orb.position = tip_position
	charge_glow.position = tip_position
	var progress := clampf(charge_time / CHARGE_TIME, 0.0, 1.0)
	var pulse := 0.25 * sin(charge_time * 28.0) if charge_ready else 0.0
	charge_glow.energy = CHARGE_GLOW_MAX_ENERGY * progress + pulse


func set_controlled(value: bool, preserve_momentum := false) -> void:
	is_controlled = value
	if value:
		_preserving_transform_momentum = preserve_momentum
		add_to_group(&"player")
	else:
		_preserving_transform_momentum = false
		remove_from_group(&"player")
		running_sound.stop()
		wall_slide_sound.stop()
		is_attacking = false
		_cancel_charge()
		_attack_target = null
		_attack_aim_local = Vector2.ZERO
		wall_jump_used = false
		was_on_wall = false
		attack_animation = &"attack"
		if is_sliding:
			stop_slide()
		velocity.x = 0.0
		sprite.position = normal_sprite_position
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
		var origin := _clamp_shot_origin(
			global_position + Vector2(spawn_offset.x * facing, spawn_offset.y)
		)
		var arrow_scene := CHARGED_ARROW_SCENE if _shot_is_charged else ARROW_SCENE
		var arrow: SerelynArrow = arrow_scene.instantiate()
		get_tree().current_scene.add_child(arrow)
		arrow.launch(origin, _get_arrow_direction(origin, facing))
		bow_shot_sound.pitch_scale = 0.75 if _shot_is_charged else 1.0
		bow_shot_sound.play()
	_shot_is_charged = false
	_attack_target = null
	_attack_aim_local = Vector2.ZERO
	_update_animation(0.0)


func _get_arrow_spawn_offset(pose: StringName = attack_animation) -> Vector2:
	if pose == &"attack_high" or pose == &"attack_high2":
		return HIGH_ARROW_SPAWN_OFFSET
	if pose == &"attack_low":
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
	sprite.position = normal_sprite_position
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
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group(&"enemy"))
	candidates.append_array(get_tree().get_nodes_in_group(&"breakable"))
	for candidate in candidates:
		var target := candidate as Node2D
		if target == null or not _is_arrow_target(target) \
				or not _is_inside_camera(target):
			continue
		var visible_point := _find_shootable_point(target, origin, facing, use_animation_origin)
		if visible_point.is_empty():
			continue
		var distance := origin.distance_squared_to(target.global_position)
		if distance < nearest_distance:
			nearest = target
			nearest_point = visible_point["point"]
			nearest_distance = distance
	if nearest == null:
		return {}
	return {"target": nearest, "local_point": nearest.to_local(nearest_point)}


func _is_arrow_target(target: Node) -> bool:
	return (target.is_in_group(&"enemy") and target.has_method("die")) \
		or (target.is_in_group(&"breakable") and target.has_method("break_apart"))


func _find_shootable_point(target: Node2D, origin: Vector2, facing: float, use_animation_origin: bool) -> Dictionary:
	# Đứng trên sàn thì Serelyn có nhiều tư thế, mỗi tư thế bắn từ một điểm khác
	# nhau: chỉ cần một tư thế bắn trúng là target hợp lệ.
	var origins: Array[Vector2] = [origin]
	if use_animation_origin:
		origins.clear()
		for offset in [ARROW_SPAWN_OFFSET, HIGH_ARROW_SPAWN_OFFSET, LOW_ARROW_SPAWN_OFFSET]:
			origins.append(_clamp_shot_origin(global_position + Vector2(offset.x * facing, offset.y)))
	for aim_point in _get_target_points(target):
		for shot_origin in origins:
			if _can_shoot_point(target, shot_origin, aim_point, facing):
				return {"point": aim_point}
	return {}


func _get_target_points(target: Node2D) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var aim_point := target.get_node_or_null("AimPoint") as Node2D
	if aim_point != null:
		points.append(aim_point.global_position)
	points.append(target.global_position)
	for path in ["CollisionShape2D", "ArrowHitArea/CollisionShape2D"]:
		var shape_node := target.get_node_or_null(path) as CollisionShape2D
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


## Điểm tạo tên nằm trước thân Serelyn ARROW_SPAWN_OFFSET.x px. Áp sát tường thì
## điểm đó đã ở bên kia tường, nên tên (và tia ngắm) xuyên qua được. Kéo điểm
## bắn lùi về sát mặt tường: tên cắm vào tường ngay, không ngắm xuyên tường.
func _clamp_shot_origin(origin: Vector2) -> Vector2:
	var from := Vector2(global_position.x, origin.y)
	if from.is_equal_approx(origin):
		return origin
	var query := PhysicsRayQueryParameters2D.create(from, origin)
	query.collision_mask = SHOT_BLOCKING_MASK
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return origin
	var hit_position: Vector2 = hit["position"]
	return hit_position + (from - origin).normalized() * SHOT_WALL_MARGIN


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
	sprite.position = normal_sprite_position
	if sprite.animation != animation:
		sprite.play(animation)


func _is_wall_sliding(direction: float) -> bool:
	return not is_on_floor() and is_on_wall() \
		and direction * get_wall_normal().x < -0.5 \
		and wall_slide_detector.has_overlapping_bodies()


func _sync_wall_slide_sound(wall_sliding: bool) -> void:
	if wall_sliding:
		if not wall_slide_sound.playing:
			wall_slide_sound.play()
	else:
		wall_slide_sound.stop()


func _update_animation(direction: float, wall_sliding := false) -> void:
	var animation: StringName
	if wall_sliding and not is_on_floor():
		animation = &"wall_slide"
		sprite.position = normal_sprite_position + WALL_SLIDE_SPRITE_OFFSET
	elif not is_on_floor():
		animation = &"jump_up" if velocity.y < 0.0 else &"jump_down"
		sprite.position = normal_sprite_position
	else:
		animation = &"run" if direction != 0.0 else &"idle"
		sprite.position = normal_sprite_position

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

	wall_slide_sound.stop()
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
	sprite.position = normal_sprite_position
	sprite.play(&"slide-air" if started_in_air else &"slide")
	if not started_in_air:
		spawn_landing_dust()


func stop_slide() -> void:
	is_sliding = false
	wall_slide_sound.stop()
	ground_slide_sound.stop()
	air_slide_sound.stop()
	slide_time_left = 0.0
	velocity.x = 0.0
	set_slide_collision(false)
	sprite.position = normal_sprite_position
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
	wall_slide_sound.stop()
	ground_slide_sound.stop()
	air_slide_sound.stop()
	set_slide_collision(false)
	is_hurt = true
	set_controlled(false)
	velocity = Vector2.ZERO
	sprite.position = normal_sprite_position

	if sprite.sprite_frames.has_animation(&"hust"):
		sprite.play(&"hust")

	await get_tree().create_timer(HURT_DURATION).timeout


func die() -> void:
	if is_dead:
		return
	is_dead = true
	set_controlled(false)
	wall_slide_sound.stop()
	velocity = Vector2(0.0, DEATH_JUMP_VELOCITY)
	sprite.position = normal_sprite_position
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
