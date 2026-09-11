@tool
extends CharacterBody2D
class_name SlimeGunner

const BULLET_SCENE := preload("res://nodes/enemies/slime_bullet.tscn")
const HIT_FLASH_COUNT := 3
const HIT_FLASH_ON_DURATION := 0.04
const HIT_FLASH_OFF_DURATION := 0.035
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5

## Vị trí đầu nòng so với gốc node, tính cho lúc slime quay sang phải. Khẩu súng
## nằm ngang tầm thân slime, không phải cái ăng-ten chĩa lên trên.
const MUZZLE_OFFSET := Vector2(14, -4)
## Giới hạn co giãn animation "attack": windup quá ngắn thì ba khung hình chỉ còn
## là một cái giật, quá dài thì slime đứng đơ giữa chừng.
const ATTACK_SPEED_SCALE_RANGE := Vector2(0.5, 4.0)

## Hướng đứng lúc đặt trong editor, cũng là hướng của khung hình đầu tiên. Vào
## game thì gunner luôn quay mặt theo player nên giá trị này chỉ để xem trước.
@export var faces_left := true:
	set(value):
		faces_left = value
		_facing = -1 if value else 1
		_apply_facing()
		queue_redraw()

@export_group("Bắn")
## Bán kính phát hiện player, vẽ sẵn trong editor để dễ canh. Camera zoom 1.6
## nên nửa bề ngang màn hình là 360px - để lớn hơn thế là bắn từ ngoài khung.
@export_range(32.0, 800.0, 1.0, "or_greater") var detection_radius := 280.0:
	set(value):
		detection_radius = value
		_apply_detection_radius()
		queue_redraw()

## Khoảng cách giữa hai phát đạn.
@export_range(0.2, 8.0, 0.05, "or_greater") var fire_interval := 2.0
## Nhịp chờ trước phát đầu tiên, để người chơi kịp thấy khẩu súng trước khi ăn đạn.
@export_range(0.0, 3.0, 0.05) var first_shot_delay := 0.6
## Thời lượng cả animation "attack": slime lấy đà, nảy lên, rồi đạn mới rời nòng
## đúng lúc khung cuối chạy xong. Animation được co giãn theo giá trị này nên
## chỉnh ở đây là chỉnh luôn độ dài động tác báo hiệu.
@export_range(0.0, 1.0, 0.01) var windup := 0.6
## Góc bắn cố định; tốc độ mới là thứ được tính lại theo khoảng cách tới player.
@export_range(10.0, 80.0, 1.0) var launch_angle_degrees := 45.0
@export_range(60.0, 1200.0, 10.0, "or_greater") var min_launch_speed := 170.0
@export_range(60.0, 1200.0, 10.0, "or_greater") var max_launch_speed := 520.0

var is_dead := false

var _facing := -1
var _player: Node2D = null
var _target: Node2D = null
var _cooldown := 0.0
var _is_firing := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone
@onready var detection_area: Area2D = $DetectionArea
@onready var detection_shape: CollisionShape2D = $DetectionArea/CollisionShape2D
@onready var muzzle: Marker2D = $Muzzle
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSound


func _ready() -> void:
	_facing = -1 if faces_left else 1
	_apply_facing()
	_apply_detection_radius()

	if Engine.is_editor_hint():
		return

	# Mỗi con cần material riêng, nếu không đổi shader parameter ở một con sẽ
	# làm mọi instance cùng nhấp nháy.
	if animated_sprite.material:
		animated_sprite.material = animated_sprite.material.duplicate()

	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
	animated_sprite.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_dead:
		return

	# Gunner là bệ pháo đứng yên, chỉ cần trọng lực để nó tụt xuống chạm nền.
	velocity.x = 0.0
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity += get_gravity() * delta
	move_and_slide()

	# Quay mặt theo player kể cả khi player còn ngoài tầm bắn: gunner đứng yên
	# một chỗ, nếu chờ tới lúc phát hiện mới xoay thì người chơi bước vào khung
	# hình sẽ thấy nó đang quay lưng rồi mới giật mình lật lại.
	var player := _find_player()
	if player != null:
		_face_towards(player.global_position.x)

	if not is_instance_valid(_target):
		_target = null
		return

	if _is_firing:
		return

	_cooldown -= delta
	if _cooldown <= 0.0:
		_fire()


func _fire() -> void:
	_is_firing = true
	_cooldown = fire_interval

	animated_sprite.speed_scale = clampf(
		_attack_animation_length() / maxf(windup, 0.01),
		ATTACK_SPEED_SCALE_RANGE.x,
		ATTACK_SPEED_SCALE_RANGE.y
	)
	animated_sprite.play(&"attack")

	# Chờ hết động tác rồi mới nhả đạn. Dùng timer chứ không await tín hiệu
	# animation_finished: tín hiệu đó đang có sẵn một handler trả sprite về "idle",
	# await chung một chỗ thì thứ tự chạy phụ thuộc thứ tự kết nối.
	await get_tree().create_timer(_attack_animation_length() / animated_sprite.speed_scale, false).timeout
	if is_dead or not is_inside_tree() or not is_instance_valid(_target):
		_is_firing = false
		return

	# Ngắm vào chỗ player đang đứng lúc bóp cò rồi thôi. Đạn không đuổi theo,
	# nên chạy tiếp hoặc lùi lại đều né được - đó là cách chơi với con này.
	var launch_velocity := _solve_launch_velocity(_target.global_position)

	var bullet := BULLET_SCENE.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.launch(muzzle.global_position, launch_velocity)

	shoot_sound.play()
	_is_firing = false


## Độ dài animation "attack" ở speed_scale = 1, tính lại từ SpriteFrames thay vì
## chép cứng con số: sửa nhịp khung hình trong editor là chỗ này tự theo.
func _attack_animation_length() -> float:
	var frames := animated_sprite.sprite_frames
	var speed := frames.get_animation_speed(&"attack")
	if speed <= 0.0:
		return 0.0

	var total := 0.0
	for frame_index in frames.get_frame_count(&"attack"):
		total += frames.get_frame_duration(&"attack", frame_index)
	return total / speed


## "attack" không loop nên cứ chạy hết là quay về nhịp thở bình thường, kể cả khi
## player đã ra khỏi tầm giữa chừng và phát đạn bị huỷ.
func _on_animation_finished() -> void:
	if is_dead or animated_sprite.animation != &"attack":
		return

	animated_sprite.speed_scale = 1.0
	animated_sprite.play(&"idle")


## Giải bài toán ném xiên: giữ nguyên góc bắn, tìm tốc độ để đạn rơi trúng đích.
func _solve_launch_velocity(target: Vector2) -> Vector2:
	var to_target := target - muzzle.global_position
	var direction := signf(to_target.x)
	if is_zero_approx(direction):
		direction = float(_facing)

	var angle := deg_to_rad(launch_angle_degrees)
	var horizontal := absf(to_target.x)
	# Đổi sang hệ toạ độ toán học (y hướng lên) cho đúng công thức bên dưới.
	var height := -to_target.y

	# v² = g·x² / (2·cos²θ·(x·tanθ − y)). Mẫu số ≤ 0 nghĩa là ở góc này đạn
	# không với tới được player dù bắn mạnh cỡ nào, khi đó cứ bắn hết cỡ.
	var speed := max_launch_speed
	var reach := horizontal * tan(angle) - height
	if reach > 0.0:
		var cos_angle := cos(angle)
		speed = sqrt(
			SlimeBullet.GRAVITY * horizontal * horizontal / (2.0 * cos_angle * cos_angle * reach)
		)

	speed = clampf(speed, min_launch_speed, max_launch_speed)
	return Vector2(cos(angle) * direction, -sin(angle)) * speed


## Player là global group nên tra một lần rồi giữ lại; chỉ tìm lại khi node cũ
## đã bị xoá (chết và hồi sinh ở save point).
func _find_player() -> Node2D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player


func _face_towards(target_x: float) -> void:
	var direction := signf(target_x - global_position.x)
	if is_zero_approx(direction) or _facing == int(direction):
		return

	_facing = int(direction)
	_apply_facing()


func _apply_facing() -> void:
	# Kiểm tra null chứ không dùng is_node_ready(): setter của export chạy lúc
	# scene còn đang nạp (node chưa có), còn _ready() thì gọi hàm này khi cờ
	# ready vẫn chưa được bật - dùng is_node_ready() là bỏ sót đúng lần đầu.
	if animated_sprite == null or muzzle == null:
		return

	# Sprite gốc vẽ slime quay sang trái (súng ở bên trái thân), giống slime
	# thường và bat, nên chỉ lật ảnh khi nó quay sang phải.
	animated_sprite.flip_h = _facing > 0
	muzzle.position = Vector2(MUZZLE_OFFSET.x * _facing, MUZZLE_OFFSET.y)


func _apply_detection_radius() -> void:
	if detection_shape == null:
		return

	var shape := detection_shape.shape as CircleShape2D
	if shape:
		shape.radius = detection_radius


func _on_detection_body_entered(body: Node2D) -> void:
	if is_dead or not body.is_in_group("player"):
		return

	_target = body
	# Chỉ hoãn khi nhịp hiện tại còn ngắn hơn: player chạy ra chạy vào tầm ngắm
	# không được phép reset đồng hồ để đứng lì mà không bao giờ ăn đạn.
	_cooldown = maxf(_cooldown, first_shot_delay)


func _on_detection_body_exited(body: Node2D) -> void:
	if body == _target:
		_target = null


# Bị nhân vật chém trúng: chớp trắng vài nhịp rồi phát animation chết.
func die() -> void:
	if is_dead:
		return

	is_dead = true
	_target = null
	velocity = Vector2.ZERO
	animated_sprite.speed_scale = 1.0
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)
	detection_area.set_deferred("monitoring", false)
	_play_defeat_sound()

	await _play_hit_flash()

	# Animation chết tự lo phần tan biến, không cần tween thu nhỏ như trước.
	if animated_sprite.sprite_frames.has_animation(&"death"):
		animated_sprite.play(&"death")
		await animated_sprite.animation_finished

	queue_free()


func _play_defeat_sound() -> void:
	if Engine.is_editor_hint():
		return

	# Player âm thanh nằm ở scene để tiếng vẫn phát hết sau khi gunner bị xoá.
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEFEAT_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	# Bỏ qua khoảng nửa giây yên lặng ở đầu file để tiếng khớp với cú chém.
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

	# Vạch chỉ hướng nòng, để lúc đặt trong editor thấy ngay nó bắn về phía nào.
	const AIM_COLOR := Color(0.45, 0.8, 1.0, 0.9)
	var muzzle_position := Vector2(MUZZLE_OFFSET.x * _facing, MUZZLE_OFFSET.y)
	var angle := deg_to_rad(launch_angle_degrees)
	var aim := Vector2(cos(angle) * _facing, -sin(angle)) * 48.0
	draw_line(muzzle_position, muzzle_position + aim, AIM_COLOR, 1.0)
