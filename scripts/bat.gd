@tool
extends CharacterBody2D
class_name Bat

const HIT_FLASH_COUNT := 3
const HIT_FLASH_ON_DURATION := 0.04
const HIT_FLASH_OFF_DURATION := 0.035
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5
## Sai số vị trí coi như bat đã bay về đúng chỗ tuần tra.
const RETURN_TOLERANCE := 4.0
## Thời gian bat hiện ra khi được đánh thức khỏi trạng thái ngủ đông.
const APPEAR_DURATION := 0.35
const APPEAR_START_SCALE := Vector2(0.3, 0.3)
## Khi bay về mà bị tường chặn, quãng đường rút ngắn được dưới mức này trong
## RETURN_STUCK_TIME giây thì coi như kẹt và lấy chỗ hiện tại làm điểm tuần tra mới.
const RETURN_STUCK_PROGRESS := 2.0
const RETURN_STUCK_TIME := 1.0

## Nhịp rít khi đang đuổi theo player. Mỗi tiếng lệch nhau một chút để cả đàn
## không kêu đều như máy - dơi thật kêu thành từng chuỗi không đều nhau.
const SCREECH_INTERVAL_MIN := 0.34
const SCREECH_INTERVAL_MAX := 0.62
const SCREECH_PITCH_MIN := 0.88
const SCREECH_PITCH_MAX := 1.18

enum State { PATROL, DIVE, RETURN }

## Khoảng cách bat bay sang mỗi bên tính từ vị trí đặt trong editor.
@export_range(0.0, 1000.0, 1.0, "or_greater") var patrol_distance := 160.0:
	set(value):
		patrol_distance = value
		queue_redraw()

@export_range(0.0, 300.0, 1.0, "or_greater") var flight_speed := 45.0
@export_range(0.0, 50.0, 1.0, "or_greater") var bob_height := 6.0
@export_range(0.0, 10.0, 0.1, "or_greater") var bob_speed := 2.5

@export_group("Tấn công")
## Bán kính vùng phát hiện player, vẽ sẵn trong editor để dễ canh.
@export_range(16.0, 600.0, 1.0, "or_greater") var detection_radius := 120.0:
	set(value):
		detection_radius = value
		_apply_detection_radius()
		queue_redraw()

## Tốc độ lao vào player, nên nhanh hơn hẳn tốc độ bay tuần tra.
@export_range(0.0, 600.0, 1.0, "or_greater") var dive_speed := 140.0
## Tốc độ bay ngược về vị trí tuần tra sau khi mất dấu player.
@export_range(0.0, 600.0, 1.0, "or_greater") var return_speed := 90.0

var direction := 1
var is_dead := false
var _state := State.PATROL
var _target: Node2D = null
var _elapsed := 0.0
var _start_position := Vector2.ZERO
## Đếm ngược tới tiếng rít kế tiếp, chỉ chạy khi đang lao theo player.
var _screech_countdown := 0.0
var _return_stuck_time := 0.0
var _return_best_distance := INF

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_area: Area2D = $DetectionArea
@onready var detection_shape: CollisionShape2D = $DetectionArea/CollisionShape2D
@onready var killzone: Area2D = $Killzone
@onready var dive_sound: AudioStreamPlayer2D = $DiveSound


func _ready() -> void:
	_start_position = position
	_apply_detection_radius()

	if Engine.is_editor_hint():
		return

	# Mỗi bat dùng một material riêng để hiệu ứng trúng đòn không ảnh hưởng
	# đến các instance khác nếu scene này được tái sử dụng ở level sau.
	if animated_sprite.material:
		animated_sprite.material = animated_sprite.material.duplicate()

	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_dead:
		return

	match _state:
		State.DIVE:
			_process_dive(delta)
		State.RETURN:
			_process_return(delta)
		_:
			_process_patrol(delta)


# Mọi kiểu di chuyển đều đi qua move_and_collide/move_and_slide (va chạm với
# tường ở layer 1 theo collision_mask) nên bat không còn bay xuyên tường.
func _process_patrol(delta: float) -> void:
	_elapsed += delta
	var desired := Vector2(
		position.x + direction * flight_speed * delta,
		_start_position.y + sin(_elapsed * bob_speed) * bob_height
	)

	if desired.x >= _start_position.x + patrol_distance:
		desired.x = _start_position.x + patrol_distance
		direction = -1
	elif desired.x <= _start_position.x - patrol_distance:
		desired.x = _start_position.x - patrol_distance
		direction = 1

	var collision := move_and_collide(desired - position)
	# Đụng tường bên hông thì quay đầu bay ngược lại, giống chạm mép vùng tuần tra.
	if collision and absf(collision.get_normal().x) > 0.5:
		direction = 1 if collision.get_normal().x > 0.0 else -1

	_face_direction(direction)


# Lao thẳng vào player theo đường chim bay, không bị giới hạn vùng tuần tra.
func _process_dive(delta: float) -> void:
	if not is_instance_valid(_target):
		_target = null
		_enter_return()
		return

	_screech_countdown -= delta
	if _screech_countdown <= 0.0:
		_play_screech()

	var to_target := _target.global_position - global_position
	if to_target.length() > 0.1:
		# move_and_slide trượt dọc theo tường thay vì xuyên qua.
		velocity = to_target.normalized() * dive_speed
		move_and_slide()
		_face_direction(int(signf(to_target.x)))


# Mất dấu player thì bay ngược về đúng vị trí tuần tra rồi mới bay qua lại tiếp.
func _process_return(delta: float) -> void:
	var to_start := _start_position - position
	var distance := to_start.length()
	if distance <= RETURN_TOLERANCE:
		move_and_collide(to_start)
		_enter_patrol()
		return

	# Có tường chắn giữa đường về thì bat có thể kẹt mãi. Theo dõi tiến độ, kẹt
	# lâu quá thì tuần tra luôn tại chỗ thay vì cứ cắm đầu vào tường.
	if distance < _return_best_distance - RETURN_STUCK_PROGRESS:
		_return_best_distance = distance
		_return_stuck_time = 0.0
	else:
		_return_stuck_time += delta
		if _return_stuck_time >= RETURN_STUCK_TIME:
			_start_position = position
			_enter_patrol()
			return

	velocity = to_start.normalized() * return_speed
	move_and_slide()
	_face_direction(int(signf(to_start.x)))


func _enter_patrol() -> void:
	velocity = Vector2.ZERO
	_elapsed = 0.0
	_state = State.PATROL


func _enter_return() -> void:
	_return_best_distance = INF
	_return_stuck_time = 0.0
	_state = State.RETURN


func _face_direction(facing: int) -> void:
	if facing == 0:
		return
	# Sprite gốc quay sang trái, nên chỉ lật ảnh khi bat bay sang phải.
	animated_sprite.flip_h = facing > 0


func _on_detection_body_entered(body: Node2D) -> void:
	if is_dead or not body.is_in_group("player"):
		return

	var was_diving := _state == State.DIVE
	_target = body
	_state = State.DIVE
	# Rít ngay khi vừa phát hiện player, sau đó _process_dive lo nhịp lặp. Nếu bat
	# vốn đã đang đuổi thì kệ nhịp cũ chạy tiếp, đừng cắt ngang tiếng đang kêu.
	if not was_diving:
		_play_screech()


func _on_detection_body_exited(body: Node2D) -> void:
	if body != _target:
		return

	_target = null
	if not is_dead:
		_enter_return()


func _apply_detection_radius() -> void:
	if not is_node_ready():
		return
	var shape := detection_shape.shape as CircleShape2D
	if shape:
		shape.radius = detection_radius


## Ngủ đông: bat biến mất và ngừng hẳn mọi hoạt động (không bay, không phát hiện
## player, không gây sát thương, không ăn đòn) cho tới khi được appear(). Dùng cho
## màn muốn giấu sẵn một đàn dơi rồi mới thả ra - xem scripts/level_4_controller.gd.
func set_dormant(dormant: bool) -> void:
	if is_dead:
		return

	visible = not dormant
	set_physics_process(not dormant)
	collision_shape.set_deferred("disabled", dormant)
	killzone.set_deferred("monitoring", not dormant)
	detection_area.set_deferred("monitoring", not dormant)


## Đánh thức bat đang ngủ đông, hiện dần từ nhỏ ra cho đỡ đột ngột. delay để cả
## đàn hiện so le nhau thay vì bật lên cùng một lúc.
func appear(delay := 0.0) -> void:
	if is_dead:
		return

	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if is_dead or not is_inside_tree():
			return

	set_dormant(false)
	modulate.a = 0.0
	scale = APPEAR_START_SCALE

	var appear_tween := create_tween().set_parallel(true)
	appear_tween.tween_property(self, "modulate:a", 1.0, APPEAR_DURATION)
	appear_tween.tween_property(self, "scale", Vector2.ONE, APPEAR_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func die() -> void:
	if is_dead:
		return

	is_dead = true
	_target = null
	_state = State.PATROL
	dive_sound.stop()
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)
	detection_area.set_deferred("monitoring", false)
	animated_sprite.play(&"death")
	_play_defeat_sound()
	await _play_hit_flash()
	if not is_inside_tree():
		return

	await animated_sprite.animation_finished
	if is_inside_tree():
		queue_free()


func _play_screech() -> void:
	dive_sound.pitch_scale = randf_range(SCREECH_PITCH_MIN, SCREECH_PITCH_MAX)
	dive_sound.play()
	_screech_countdown = randf_range(SCREECH_INTERVAL_MIN, SCREECH_INTERVAL_MAX)


func _play_defeat_sound() -> void:
	if Engine.is_editor_hint():
		return

	# Player âm thanh nằm ở scene để vẫn phát hết tiếng sau khi bat bị xoá.
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEFEAT_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	# Bỏ qua khoảng nửa giây yên lặng ở đầu file để tiếng khớp với cú hạ gục.
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

	const PATROL_COLOR := Color(0.72, 0.36, 1.0, 0.9)
	var left := -patrol_distance
	var right := patrol_distance
	draw_line(Vector2(left, 28.0), Vector2(right, 28.0), PATROL_COLOR, 1.0)
	draw_line(Vector2(left, 20.0), Vector2(left, 32.0), PATROL_COLOR, 1.0)
	draw_line(Vector2(right, 20.0), Vector2(right, 32.0), PATROL_COLOR, 1.0)
