@tool
extends CharacterBody2D

const HIT_FLASH_COUNT := 3
const HIT_FLASH_ON_DURATION := 0.04
const HIT_FLASH_OFF_DURATION := 0.035

## Khoảng cách bat bay sang mỗi bên tính từ vị trí đặt trong editor.
@export_range(0.0, 1000.0, 1.0, "or_greater") var patrol_distance := 160.0:
	set(value):
		patrol_distance = value
		queue_redraw()

@export_range(0.0, 300.0, 1.0, "or_greater") var flight_speed := 45.0
@export_range(0.0, 50.0, 1.0, "or_greater") var bob_height := 6.0
@export_range(0.0, 10.0, 0.1, "or_greater") var bob_speed := 2.5

var direction := 1
var is_dead := false
var _elapsed := 0.0
var _start_position := Vector2.ZERO

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone


func _ready() -> void:
	_start_position = position
	# Mỗi bat dùng một material riêng để hiệu ứng trúng đòn không ảnh hưởng
	# đến các instance khác nếu scene này được tái sử dụng ở level sau.
	if animated_sprite.material:
		animated_sprite.material = animated_sprite.material.duplicate()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_dead:
		return

	_elapsed += delta
	position.x += direction * flight_speed * delta
	position.y = _start_position.y + sin(_elapsed * bob_speed) * bob_height

	if position.x >= _start_position.x + patrol_distance:
		position.x = _start_position.x + patrol_distance
		direction = -1
	elif position.x <= _start_position.x - patrol_distance:
		position.x = _start_position.x - patrol_distance
		direction = 1

	# Sprite gốc quay sang trái, nên chỉ lật ảnh khi bat bay sang phải.
	animated_sprite.flip_h = direction > 0


func die() -> void:
	if is_dead:
		return

	is_dead = true
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)

	await _play_hit_flash()

	var death_tween := create_tween().set_parallel(true)
	death_tween.tween_property(self, "scale", Vector2.ZERO, 0.18)
	death_tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.18)
	await death_tween.finished
	queue_free()


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
	if not Engine.is_editor_hint() or patrol_distance <= 0.0:
		return

	const PATROL_COLOR := Color(0.72, 0.36, 1.0, 0.9)
	var left := -patrol_distance
	var right := patrol_distance
	draw_line(Vector2(left, 28.0), Vector2(right, 28.0), PATROL_COLOR, 1.0)
	draw_line(Vector2(left, 20.0), Vector2(left, 32.0), PATROL_COLOR, 1.0)
	draw_line(Vector2(right, 20.0), Vector2(right, 32.0), PATROL_COLOR, 1.0)
