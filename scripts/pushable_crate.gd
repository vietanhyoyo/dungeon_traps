class_name PushableCrate
extends CharacterBody2D

## Hộp đẩy được. Hộp nằm trên layer 1 (world) nên nhân vật đứng lên nóc như mặt
## đất, còn slime và đạn cũng coi nó là tường. Nhân vật tì vào mặt bên để đẩy.
##
## Scene nào có node con "FireSensor" (Area2D) thì hộp dập tắt fire trap khi được
## đẩy qua — dùng cho hộp sắt.

const DEBRIS_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
# File nguồn có khoảng nửa giây yên lặng ở đầu, bỏ qua để tiếng vỡ khớp cú chém.
const DEBRIS_SOUND_OFFSET := 0.5
const DEBRIS_FLY_DURATION := 0.45
# Mỗi mảnh vỡ văng ngang ra xa tâm hộp bấy nhiêu px.
const DEBRIS_SPREAD := 18.0
# Độ cao đỉnh cung bay của mảnh vỡ.
const DEBRIS_RISE := 14.0
# Mảnh vỡ rơi thấp hơn chỗ xuất phát bấy nhiêu px ở cuối cung bay.
const DEBRIS_DROP := 20.0
# Chỉ tính là đẩy khi tì vào mặt gần thẳng đứng. Chạm mép nóc hộp cho ra normal
# xiên, không lọc thì đứng trên góc hộp cũng đẩy được chính cái hộp đó.
const PUSH_NORMAL_MIN := 0.7
# Layer 3 là lớp quái; AttackHitbox của nhân vật chỉ mask lớp này.
const HITTABLE_LAYER := 3

## Tốc độ hộp trượt ngang lúc bị đẩy.
@export var push_speed := 120.0
## Bật lên thì nhân vật chém vỡ được hộp (hộp gỗ).
@export var breakable := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var fire_sensor := get_node_or_null("FireSensor") as Area2D

# Hướng bị đẩy trong frame vừa rồi, reset sau mỗi bước physics.
var _push_direction := 0.0
var _is_broken := false


func _ready() -> void:
	if breakable:
		# Đứng trên layer 3 thì AttackHitbox mới quét trúng hộp.
		set_collision_layer_value(HITTABLE_LAYER, true)
		add_to_group(&"breakable")

	if fire_sensor:
		fire_sensor.area_entered.connect(_on_fire_sensor_area_entered)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Hộp chỉ trượt trong bước được đẩy; người chơi buông tay là hộp đứng lại
	# ngay chứ không trôi tiếp.
	var direction := _push_direction
	_push_direction = 0.0
	velocity.x = direction * push_speed
	move_and_slide()

	# Hộp đang bị đẩy mà tì vào hộp khác thì đẩy luôn hộp đó.
	if direction != 0.0:
		push_touching(self, direction)


## Đẩy mọi hộp mà body vừa tì vào mặt bên theo hướng direction. Gọi ngay sau
## move_and_slide() của body; dùng chung cho nhân vật lẫn hộp đẩy hộp.
static func push_touching(body: CharacterBody2D, direction: float) -> void:
	for i in body.get_slide_collision_count():
		var collision := body.get_slide_collision(i)
		var crate := collision.get_collider() as PushableCrate
		if crate == null:
			continue
		# Normal chỉ từ hộp ra phía body, nên hộp nằm phía trước thì normal.x
		# ngược dấu với hướng đẩy.
		if collision.get_normal().x * direction > -PUSH_NORMAL_MIN:
			continue
		crate.push(direction)


func push(direction: float) -> void:
	# Hộp đang rơi thì không đẩy ngang được, tránh "ném" hộp bay qua hố.
	if _is_broken or not is_on_floor():
		return

	_push_direction = signf(direction)


## Nhân vật chém trúng. Hộp không breakable (hộp sắt) thì không hề hấn gì.
func break_apart() -> void:
	if _is_broken or not breakable:
		return

	_is_broken = true
	# Tắt va chạm ngay: nhân vật đang đứng trên nóc rơi xuống luôn, không phải
	# đợi mảnh vỡ bay xong. set_deferred vì hàm được gọi giữa lúc quét va chạm.
	collision_shape.set_deferred("disabled", true)
	set_physics_process(false)
	sprite.visible = false
	_play_break_sound()

	await _play_debris()
	queue_free()


func _play_break_sound() -> void:
	# Không gắn player âm thanh làm con của hộp vì hộp bị queue_free ngay khi
	# mảnh vỡ bay xong, tiếng vỡ sẽ bị ngắt giữa chừng.
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEBRIS_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	sound_player.play(DEBRIS_SOUND_OFFSET)


## Cắt ảnh hộp thành bốn góc rồi cho từng góc văng theo cung parabol ra bốn phía.
func _play_debris() -> void:
	var half_size := sprite.texture.get_size() * 0.5
	var tween := create_tween().set_parallel()

	for column in 2:
		for row in 2:
			# side = (-1|+1, -1|+1): góc này nằm phía nào so với tâm hộp.
			var side := Vector2(column * 2 - 1, row * 2 - 1)
			var piece := Sprite2D.new()
			piece.texture = sprite.texture
			piece.region_enabled = true
			piece.region_rect = Rect2(Vector2(column, row) * half_size, half_size)
			var start := side * half_size * 0.5
			piece.position = start
			add_child(piece)

			tween.tween_method(
				func(t: float) -> void:
					piece.position = start + Vector2(
						side.x * DEBRIS_SPREAD * t,
						DEBRIS_DROP * t * t - DEBRIS_RISE * 4.0 * t * (1.0 - t)
					),
				0.0, 1.0, DEBRIS_FLY_DURATION
			)
			tween.tween_property(piece, "rotation", side.x * PI * 0.5, DEBRIS_FLY_DURATION)
			tween.tween_property(piece, "modulate:a", 0.0, DEBRIS_FLY_DURATION) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	await tween.finished


func _on_fire_sensor_area_entered(area: Area2D) -> void:
	if area.has_method("extinguish"):
		area.extinguish()
