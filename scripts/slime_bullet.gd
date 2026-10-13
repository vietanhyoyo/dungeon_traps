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
const POP_DURATION := 0.14
const POP_SCALE := Vector2(1.9, 1.9)
const TRAIL_SPACING := 9.0
const TRAIL_RADII := [4.0, 3.0, 2.0]
const TRAIL_COLORS := [
	Color(0.25, 0.75, 1.0, 0.78),
	Color(0.2, 0.62, 0.95, 0.52),
	Color(0.15, 0.48, 0.85, 0.3),
]
const MAX_TRAIL_HISTORY := 24
## Bit 1 = lớp va chạm của tile map, dùng để biết đạn cắm vào tường.
const TERRAIN_MASK := 1
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5

# velocity là property có sẵn của CharacterBody2D, không khai báo lại.

var _is_popping := false
var _age := 0.0
var _trail_positions: Array[Vector2] = []

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone


## Gọi ngay sau add_child. Viên đạn tự lo phần bay, không bám theo slime đã bắn
## nó ra - slime chết giữa chừng thì đạn vẫn tới đích.
func launch(from: Vector2, initial_velocity: Vector2) -> void:
	global_position = from
	velocity = initial_velocity
	_trail_positions.clear()
	_trail_positions.append(from)


func _physics_process(delta: float) -> void:
	if _is_popping:
		return

	_age += delta
	if _age >= LIFETIME:
		_pop()
		return

	velocity.y += GRAVITY * delta
	var motion := velocity * delta

	var terrain_hit := _terrain_hit(motion)
	if terrain_hit.is_empty():
		global_position += motion
		_record_trail_position()
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


func _record_trail_position() -> void:
	_trail_positions.push_front(global_position)
	if _trail_positions.size() > MAX_TRAIL_HISTORY:
		_trail_positions.pop_back()
	queue_redraw()


func _draw() -> void:
	if _is_popping or _trail_positions.is_empty():
		return

	var trail_index := 0
	var distance_traveled := 0.0
	var required_distance := TRAIL_SPACING
	var newer_position := global_position
	for older_position in _trail_positions:
		var segment_length := newer_position.distance_to(older_position)
		if segment_length > 0.001:
			while trail_index < TRAIL_RADII.size() and distance_traveled + segment_length >= required_distance:
				var segment_offset := required_distance - distance_traveled
				var trail_position := newer_position.lerp(older_position, segment_offset / segment_length)
				draw_circle(
					trail_position - global_position,
					TRAIL_RADII[trail_index],
					TRAIL_COLORS[trail_index]
				)
				trail_index += 1
				required_distance += TRAIL_SPACING
			distance_traveled += segment_length
		newer_position = older_position
		if trail_index >= TRAIL_RADII.size():
			break


## Killzone gọi hàm này khi player dính đạn. Cố tình không await bên trong:
## killzone.gd await lại giá trị trả về, mà viên đạn thì tự xoá mình sau hiệu
## ứng nổ - await xong sẽ resume trên một node đã chết.
func on_player_touched(_player: Node2D) -> void:
	_pop()


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
	_trail_positions.clear()
	queue_redraw()
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)

	var pop_tween := create_tween().set_parallel(true)
	pop_tween.tween_property(sprite, "scale", POP_SCALE, POP_DURATION)
	pop_tween.tween_property(sprite, "modulate:a", 0.0, POP_DURATION)
	await pop_tween.finished

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
