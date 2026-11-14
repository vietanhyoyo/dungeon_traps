# CharacterBody2D chứ không phải Node2D: AttackHitbox của Asura là Area2D quét
# get_overlapping_bodies(), nên viên đạn phải là physics body nằm ở lớp 4 và ở
# trong group "enemy" thì mới chém được. Không dùng move_and_slide, đạn tự dời
# global_position như bat - chỉ mượn cái thân va chạm.
extends CharacterBody2D
class_name SlimeBullet

## Trọng lực riêng của viên đạn, nhẹ hơn trọng lực nhân vật (980) để đường bay
## vồng cao và người chơi kịp đọc quỹ đạo mà né.
const GRAVITY := 620.0
## Đạn bay chệch ra khoảng trống thì tự dọn mình sau ngần này giây.
const LIFETIME := 5.0
## Đèn xanh phập phồng nhẹ khi bay; tắt dần lúc vỡ.
const GLOW_ENERGY := 1.0
const GLOW_PULSE := 0.18
const GLOW_FADE_DURATION := 0.25
## Bit 1 = lớp va chạm của tile map, dùng để biết đạn cắm vào tường.
const TERRAIN_MASK := 1
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5
const HIT_EFFECT_SCENE := preload("res://nodes/effects/hit_effect.tscn")

# velocity là property có sẵn của CharacterBody2D, không khai báo lại.

var _is_popping := false
var _age := 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var glow: PointLight2D = $Glow
@onready var trail: CPUParticles2D = $Trail
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone


## Gọi ngay sau add_child. Viên đạn tự lo phần bay, không bám theo slime đã bắn
## nó ra - slime chết giữa chừng thì đạn vẫn tới đích.
func launch(from: Vector2, initial_velocity: Vector2) -> void:
	global_position = from
	velocity = initial_velocity
	_face_velocity()
	# Hạt vệt đuôi dùng toạ độ thế giới: xoá hạt sinh ra ở vị trí trước launch().
	trail.restart()


func _physics_process(delta: float) -> void:
	if _is_popping:
		return

	_age += delta
	if _age >= LIFETIME:
		_pop()
		return

	velocity.y += GRAVITY * delta
	_face_velocity()
	glow.energy = GLOW_ENERGY + GLOW_PULSE * sin(_age * 18.0)
	var motion := velocity * delta

	var terrain_hit := _terrain_hit(motion)
	if terrain_hit.is_empty():
		global_position += motion
		return

	# Dời về đúng chỗ chạm tường rồi mới nổ, tránh nổ khi đã lút vào trong gạch.
	global_position = terrain_hit["position"]
	_pop()


## Quét cả đoạn đường của frame này chứ không chỉ xét điểm đến: đạn đi hơn 32px
## mỗi frame nên nếu chỉ xét điểm đến nó sẽ lọt qua tường dày một ô.
func _terrain_hit(motion: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + motion
	)
	query.collision_mask = TERRAIN_MASK
	return get_world_2d().direct_space_state.intersect_ray(query)


## Giọt slime vẽ hướng sang phải: xoay theo vận tốc để đầu luôn đi trước,
## giọt nhỏ phía sau thành đuôi.
func _face_velocity() -> void:
	if velocity.length_squared() > 1.0:
		animated_sprite.rotation = velocity.angle()


## Killzone gọi hàm này khi player dính đạn. Cố tình không await bên trong:
## killzone.gd await lại giá trị trả về, mà viên đạn thì tự xoá mình sau hiệu
## ứng nổ - await xong sẽ resume trên một node đã chết.
func on_player_touched(player: Node2D) -> void:
	_spawn_hit_effect(player)
	_pop()


## Cùng hiệu ứng hit.png như lúc player chém trúng quái, đặt ở vị trí player.
## Gắn vào scene màn chơi chứ không vào đạn: đạn tự xoá sau hiệu ứng vỡ.
func _spawn_hit_effect(player: Node2D) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null or not is_instance_valid(player):
		return
	var effect: AnimatedSprite2D = HIT_EFFECT_SCENE.instantiate()
	current_scene.add_child(effect)
	effect.global_position = player.global_position


## Player chém trúng viên đạn. Cùng tên hàm với slime và bat vì
## asura_controller.hit_enemy() gọi die() cho mọi thứ trong group "enemy".
func die() -> void:
	if _is_popping:
		return

	# Chỉ kêu khi bị chém, không kêu lúc đạn cắm vào tường: đó là phản hồi cho
	# người chơi biết mình vừa phá được đạn, cắm tường thì kêu suốt sẽ ồn.
	_play_defeat_sound()
	_pop()


func _pop() -> void:
	if _is_popping:
		return

	_is_popping = true
	trail.emitting = false
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)

	# Giọt slime bẹp ra rồi văng thành các giọt nhỏ (animation không xoay theo
	# hướng bay).
	animated_sprite.rotation = 0.0
	animated_sprite.play(&"pop")
	var glow_tween := create_tween()
	glow_tween.tween_property(glow, "energy", 0.0, GLOW_FADE_DURATION)
	await animated_sprite.animation_finished

	queue_free()


func _play_defeat_sound() -> void:
	# Player âm thanh nằm ở scene để tiếng vẫn phát hết sau khi đạn bị xoá.
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEFEAT_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	sound_player.pitch_scale = 1.4
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	# Bỏ qua khoảng nửa giây yên lặng ở đầu file để tiếng khớp với cú chém.
	sound_player.play(DEFEAT_SOUND_OFFSET)
