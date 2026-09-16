# Cùng lý do với SlimeBullet: AttackHitbox của Asura quét get_overlapping_bodies()
# nên cái gai phải là physics body ở lớp 4 và nằm trong group "enemy" thì mới chém
# được. Khác ở chỗ gai bay thẳng, không có trọng lực - tám cái phóng ra cùng lúc
# phải giữ nguyên hình vòng tròn thì người chơi mới đọc được khe hở để né.
#
# Vùng ăn chém (CollisionShape2D, bán kính 10) rộng gấp đôi vùng giết người chơi
# (Killzone, bán kính 5). Hai vùng bằng nhau thì lưỡi kiếm và mũi gai chạm nhau
# đúng cùng một khoảnh khắc, chém trúng hay chết chỉ còn là chuyện may rủi của
# thứ tự xử lý va chạm. Chênh 5px ở tốc độ mặc định 190 là khoảng hai bước
# physics - đủ để cú chém luôn ăn trước.
extends CharacterBody2D
class_name SlimeThornSpike

## Gai bay chệch ra khoảng trống thì tự dọn mình sau ngần này giây. Ngắn hơn đạn
## của gunner nhiều: đạn gunner có trọng lực nên kiểu gì cũng rơi chạm đất, còn
## gai bay thẳng mãi - ở tốc độ mặc định 190 thì 2.5 giây là 475px, hơn nửa bề
## ngang màn hình (360px ở zoom 1.6) một chút. Để dài hơn là gai bay ngang qua cả
## hang rồi đâm vào người chơi từ ngoài khung hình.
const LIFETIME := 2.5
const POP_DURATION := 0.12
const POP_SCALE := Vector2(1.7, 1.7)
## Bit 1 = lớp va chạm của tile map, dùng để biết gai cắm vào tường.
const TERRAIN_MASK := 1
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5

# velocity là property có sẵn của CharacterBody2D, không khai báo lại.

## Đặt ngay lúc gai bắt đầu vỡ. Killzone đọc cờ này để không giết người chơi
## bằng một cái gai vừa bị chém nát trong cùng frame.
var is_dead := false
var _age := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone


## Gọi ngay sau add_child. Gai tự lo phần bay, không bám theo con slime đã phóng
## nó ra - slime chết giữa chừng thì cả vòng gai vẫn bay hết đường.
func launch(from: Vector2, initial_velocity: Vector2) -> void:
	global_position = from
	velocity = initial_velocity
	# Sprite vẽ mũi gai chĩa sang phải, nên xoay cả node theo hướng bay là đủ.
	# Hitbox là hình tròn nên xoay theo cũng không đổi hình dạng va chạm.
	rotation = initial_velocity.angle()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_age += delta
	if _age >= LIFETIME:
		_pop()
		return

	var motion := velocity * delta
	var terrain_hit := _terrain_hit(motion)
	if terrain_hit.is_empty():
		global_position += motion
		return

	# Dời về đúng chỗ chạm tường rồi mới vỡ, tránh vỡ khi đã lút vào trong gạch.
	global_position = terrain_hit["position"]
	_pop()


## Quét cả đoạn đường của frame này chứ không chỉ xét điểm đến: cùng lý do với
## SlimeBullet, gai đi nhanh nên xét mỗi điểm đến là nó lọt qua tường dày một ô.
func _terrain_hit(motion: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + motion
	)
	query.collision_mask = TERRAIN_MASK
	return get_world_2d().direct_space_state.intersect_ray(query)


## Killzone gọi hàm này khi player dính gai. Cố tình không await bên trong:
## killzone.gd await lại giá trị trả về, mà cái gai thì tự xoá mình sau hiệu ứng
## vỡ - await xong sẽ resume trên một node đã chết.
func on_player_touched(_player: Node2D) -> void:
	_pop()


## Player chém trúng cái gai. Cùng tên hàm với slime và bat vì
## asura_controller.hit_enemy() gọi die() cho mọi thứ trong group "enemy".
func die() -> void:
	if is_dead:
		return

	# Chỉ kêu khi bị chém, không kêu lúc gai cắm vào tường: cả vòng tám cái mà
	# cái nào chạm tường cũng kêu thì mỗi loạt bắn là một tràng tiếng nổ.
	_play_defeat_sound()
	_pop()


func _pop() -> void:
	if is_dead:
		return

	is_dead = true
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)

	var pop_tween := create_tween().set_parallel(true)
	pop_tween.tween_property(sprite, "scale", POP_SCALE, POP_DURATION)
	pop_tween.tween_property(sprite, "modulate:a", 0.0, POP_DURATION)
	await pop_tween.finished

	queue_free()


func _play_defeat_sound() -> void:
	# Player âm thanh nằm ở scene để tiếng vẫn phát hết sau khi gai bị xoá.
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEFEAT_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	sound_player.pitch_scale = 1.5
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	# Bỏ qua khoảng nửa giây yên lặng ở đầu file để tiếng khớp với cú chém.
	sound_player.play(DEFEAT_SOUND_OFFSET)
