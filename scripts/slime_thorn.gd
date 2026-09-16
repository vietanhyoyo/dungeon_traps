@tool
extends CharacterBody2D
class_name SlimeThorn

## Slime gai treo ngược trên trần. Không đi lại, không rơi - nó chỉ đợi người chơi
## lọt vào tầm rồi phình người và phóng một vòng gai đều khắp xung quanh.
##
## CharacterBody2D chứ không phải StaticBody2D, dù con này đứng yên tuyệt đối và
## chẳng bao giờ gọi move_and_slide. Lý do là AttackHitbox của Asura dò mục tiêu
## bằng Area2D.get_overlapping_bodies(), mà cái đó KHÔNG báo về StaticBody2D đứng
## im: đo tại chỗ với một SlimeGunner đặt trùng toạ độ thì hitbox thấy gunner
## (CharacterBody2D) còn con này thì không, dù truy vấn physics trực tiếp bằng
## đúng shape đó vẫn trúng cả hai. Đổi sang StaticBody2D là con quái thành bất tử.
##
## Thân nó KHÔNG có Killzone: đụng vào người nó thì không sao, chỉ vòng gai bắn
## ra mới giết được người chơi (Killzone nằm trong slime_thorn_spike). Mối đe doạ
## nằm ở loạt gai chứ không phải ở chỗ đứng, nên nhảy lên chém không còn là đánh
## đổi mạng sống và chỗ treo cũng không bị ràng buộc phải chừa đủ độ cao.

const SPIKE_SCENE := preload("res://nodes/enemies/slime_thorn_spike.tscn")
const HIT_FLASH_COUNT := 3
const HIT_FLASH_ON_DURATION := 0.04
const HIT_FLASH_OFF_DURATION := 0.035
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5

## Tâm thân gai so với gốc node. Mỗi khung 64x64 vẽ phần dính trần ở ngay mép trên,
## nên khi đặt gốc node cách mép dưới của trần đúng một ô (32px) thì phần dính trần
## chạm trần và cái thân đầy gai rơi vào quanh gốc node.
const BODY_CENTER := Vector2(0.0, 2.0)
## Gai xuất phát ở bán kính này quanh tâm thân, đủ xa để lúc mới sinh nó không
## nằm đè lên sprite con slime.
const SPAWN_RADIUS := 15.0
## Khung mà bộ gai bật ngược trở ra - đúng khoảnh khắc đó mới sinh vòng gai, để
## gai rời thân khớp với lúc sprite bung ra. Bốn khung trước là lúc con slime rụt
## gai vào người lấy đà, và đó chính là lời báo trước cho người chơi.
const ATTACK_RELEASE_FRAME := 4
## Giới hạn co giãn animation "attack": windup quá ngắn thì cả động tác rụt gai
## chỉ còn là một cái giật, quá dài thì slime đứng đơ giữa chừng.
const ATTACK_SPEED_SCALE_RANGE := Vector2(0.5, 4.0)
## Đung đưa nhàn rỗi, chỉ để con quái không đứng chết cứng trên trần.
const SWAY_ANGLE := 0.055
const SWAY_DURATION := 1.9

@export_group("Phóng gai")
## Số gai trong một vòng, chia đều 360 độ.
@export_range(3, 16, 1) var thorn_count := 8:
	set(value):
		thorn_count = value
		queue_redraw()

## Bán kính phát hiện player, vẽ sẵn trong editor để dễ canh. Hẹp hơn của gunner
## vì slime gai treo sát đầu người chơi, tầm rộng bằng gunner là vừa bước vào
## hành lang đã ăn gai.
@export_range(32.0, 800.0, 1.0, "or_greater") var detection_radius := 220.0:
	set(value):
		detection_radius = value
		_apply_detection_radius()
		queue_redraw()

## Khoảng cách giữa hai loạt gai.
@export_range(0.2, 8.0, 0.05, "or_greater") var fire_interval := 2.4
## Nhịp chờ trước loạt đầu tiên, để người chơi kịp nhìn thấy con quái trên trần
## trước khi ăn nguyên một vòng gai.
@export_range(0.0, 3.0, 0.05) var first_shot_delay := 0.8
## Thời lượng cả động tác "attack": slime rụt gai vào, nén lại, rồi bung ra đúng
## lúc vòng gai rời thân. Animation được co giãn theo giá trị này nên chỉnh ở đây
## là chỉnh luôn độ dài lời báo trước.
@export_range(0.05, 2.0, 0.01) var windup := 0.55
@export_range(40.0, 600.0, 5.0, "or_greater") var thorn_speed := 190.0

## Mặc định tắt: vòng gai luôn nằm đúng một góc cố định nên người chơi nhìn vài
## lần là thuộc lòng đường gai bay và biết đứng vào khe nào để né. Bật lên thì
## một mũi luôn chĩa thẳng vào player - né bằng phản xạ chứ không bằng trí nhớ.
@export var aim_at_player := false
## Góc của mũi gai đầu tiên khi không ngắm player (0 = sang phải). Mặc định 22.5
## độ - lệch nửa bước so với vòng tám mũi, nên không mũi nào bắn thẳng lên trần,
## thẳng xuống sàn hay đi ngang: khe trống nằm đúng ngay dưới chân con slime và
## ở hai bên ngang tầm người, hai chỗ dễ nhớ nhất.
@export_range(0.0, 360.0, 0.5) var ring_offset_degrees := 22.5

var is_dead := false

var _player: Node2D = null
var _target: Node2D = null
var _cooldown := 0.0
var _is_firing := false
## Hướng vòng gai, chốt lúc bắt đầu động tác và giữ tới khung bung gai.
var _pending_ring_angle := 0.0
## Tween đung đưa nhàn rỗi. Giữ lại để lúc chết còn dừng được: animation chết vẽ
## cảnh cái thân rụng khỏi trần, mà pivot thì xoay quanh đúng chỗ dính trần đó -
## để nó đung đưa tiếp thì giọt nước đang rơi lại lắc lư theo một cái cuống
## không còn nữa.
var _sway_tween: Tween = null

@onready var pivot: Node2D = $Pivot
@onready var animated_sprite: AnimatedSprite2D = $Pivot/AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_area: Area2D = $DetectionArea
@onready var detection_shape: CollisionShape2D = $DetectionArea/CollisionShape2D
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSound


func _ready() -> void:
	_apply_detection_radius()

	if Engine.is_editor_hint():
		return

	# Mỗi con cần material riêng, nếu không đổi shader parameter ở một con sẽ
	# làm mọi instance cùng nhấp nháy.
	if animated_sprite.material:
		animated_sprite.material = animated_sprite.material.duplicate()

	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
	animated_sprite.frame_changed.connect(_on_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	_start_sway()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_dead:
		return

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

	# Chốt hướng vòng gai ngay lúc bắt đầu rụt gai chứ không phải lúc gai rời thân:
	# động tác rụt gai là lời báo trước, người chơi thấy nó rụt mà chạy khỏi đường
	# ngắm thì phải né được - ngắm lại lúc bung gai là biến lời báo đó thành vô nghĩa.
	_pending_ring_angle = _ring_base_angle()

	animated_sprite.speed_scale = clampf(
		_attack_animation_length() / maxf(windup, 0.01),
		ATTACK_SPEED_SCALE_RANGE.x,
		ATTACK_SPEED_SCALE_RANGE.y
	)
	animated_sprite.play(&"attack")


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


## Gai chỉ rời thân đúng khung sprite bung gai ra, nên hình và đòn đánh luôn khớp
## nhau dù windup có kéo dài hay rút ngắn animation tới đâu.
func _on_frame_changed() -> void:
	if is_dead or animated_sprite.animation != &"attack":
		return
	if animated_sprite.frame != ATTACK_RELEASE_FRAME:
		return

	# Bắn kể cả khi player vừa ra khỏi tầm: đã rụt gai là đã cam kết, huỷ giữa
	# chừng làm con quái trông như bị hụt hơi.
	_spawn_ring(_pending_ring_angle)
	shoot_sound.play()


## "attack" không loop nên cứ chạy hết là quay về nhịp thở bình thường.
func _on_animation_finished() -> void:
	if is_dead or animated_sprite.animation != &"attack":
		return

	animated_sprite.speed_scale = 1.0
	animated_sprite.play(&"idle")
	_is_firing = false


func _ring_base_angle() -> float:
	if aim_at_player and is_instance_valid(_target):
		return (_target.global_position - to_global(BODY_CENTER)).angle()
	return deg_to_rad(ring_offset_degrees)


func _spawn_ring(base_angle: float) -> void:
	var origin := to_global(BODY_CENTER)
	var step := TAU / float(thorn_count)
	for index in thorn_count:
		var direction := Vector2.RIGHT.rotated(base_angle + step * index)
		var spike := SPIKE_SCENE.instantiate()
		# Gắn vào scene chứ không vào con slime: slime bị chém giữa loạt thì cả
		# vòng gai vẫn bay hết đường thay vì biến mất theo.
		get_tree().current_scene.add_child(spike)
		spike.launch(origin + direction * SPAWN_RADIUS, direction * thorn_speed)


## Đung đưa qua lại quanh chỗ dính trần. Chỉ là hiệu ứng nhìn - hitbox nằm ở gốc
## node nên không nhúc nhích theo, biên độ có 0.055 rad thì lệch chưa tới 2px.
func _start_sway() -> void:
	_sway_tween = create_tween().set_loops()
	_sway_tween.tween_property(pivot, "rotation", SWAY_ANGLE, SWAY_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween.tween_property(pivot, "rotation", -SWAY_ANGLE, SWAY_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
	# không được phép reset đồng hồ để đứng lì mà không bao giờ ăn gai.
	_cooldown = maxf(_cooldown, first_shot_delay)


func _on_detection_body_exited(body: Node2D) -> void:
	if body == _target:
		_target = null


# Bị nhân vật chém trúng: chớp trắng vài nhịp rồi chạy animation chết - cái thân
# rụng khỏi trần, chảy thành giọt rồi tan.
func die() -> void:
	if is_dead:
		return

	is_dead = true
	_target = null
	collision_shape.set_deferred("disabled", true)
	detection_area.set_deferred("monitoring", false)
	_play_defeat_sound()

	# Bị chém giữa lúc đang rụt gai: đứng hình ngay tại đó. Không dừng thì trong
	# lúc chớp trắng animation vẫn chạy nốt tới khung bung gai, và
	# _on_frame_changed kịp nhả ra một vòng gai từ cái xác.
	animated_sprite.speed_scale = 1.0
	animated_sprite.pause()
	# Thân sắp rụng khỏi trần nên không còn gì để đung đưa quanh cái cuống nữa.
	if _sway_tween and _sway_tween.is_valid():
		_sway_tween.kill()

	await _play_hit_flash()

	animated_sprite.play(&"death")
	await animated_sprite.animation_finished

	queue_free()


func _play_defeat_sound() -> void:
	if Engine.is_editor_hint():
		return

	# Player âm thanh nằm ở scene để tiếng vẫn phát hết sau khi slime bị xoá.
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
	draw_arc(BODY_CENTER, detection_radius, 0.0, TAU, 48, DETECTION_COLOR, 1.0)

	# Vẽ sẵn vòng gai để lúc đặt trong editor thấy ngay nó phủ tới đâu. Khi bật
	# aim_at_player thì hướng thật sẽ xoay theo player, đây chỉ là góc mặc định.
	const THORN_COLOR := Color(0.45, 0.8, 1.0, 0.9)
	var base_angle := deg_to_rad(ring_offset_degrees)
	var step := TAU / float(thorn_count)
	for index in thorn_count:
		var direction := Vector2.RIGHT.rotated(base_angle + step * index)
		draw_line(
			BODY_CENTER + direction * SPAWN_RADIUS,
			BODY_CENTER + direction * 44.0,
			THORN_COLOR,
			1.0
		)
