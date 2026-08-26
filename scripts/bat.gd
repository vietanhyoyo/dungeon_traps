@tool
extends CharacterBody2D

const HIT_FLASH_COUNT := 3
const HIT_FLASH_ON_DURATION := 0.04
const HIT_FLASH_OFF_DURATION := 0.035
## Sai số vị trí coi như bat đã bay về đúng chỗ tuần tra.
const RETURN_TOLERANCE := 4.0

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

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_area: Area2D = $DetectionArea
@onready var detection_shape: CollisionShape2D = $DetectionArea/CollisionShape2D
@onready var killzone: Area2D = $Killzone


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


func _process_patrol(delta: float) -> void:
	_elapsed += delta
	position.x += direction * flight_speed * delta
	position.y = _start_position.y + sin(_elapsed * bob_speed) * bob_height

	if position.x >= _start_position.x + patrol_distance:
		position.x = _start_position.x + patrol_distance
		direction = -1
	elif position.x <= _start_position.x - patrol_distance:
		position.x = _start_position.x - patrol_distance
		direction = 1

	_face_direction(direction)


# Lao thẳng vào player theo đường chim bay, không bị giới hạn vùng tuần tra.
func _process_dive(delta: float) -> void:
	if not is_instance_valid(_target):
		_target = null
		_state = State.RETURN
		return

	var to_target := _target.global_position - global_position
	if to_target.length() > 0.1:
		global_position += to_target.normalized() * dive_speed * delta
		_face_direction(int(signf(to_target.x)))


# Mất dấu player thì bay ngược về đúng vị trí tuần tra rồi mới bay qua lại tiếp.
func _process_return(delta: float) -> void:
	var to_start := _start_position - position
	if to_start.length() <= RETURN_TOLERANCE:
		position = _start_position
		_elapsed = 0.0
		_state = State.PATROL
		return

	position += to_start.normalized() * return_speed * delta
	_face_direction(int(signf(to_start.x)))


func _face_direction(facing: int) -> void:
	if facing == 0:
		return
	# Sprite gốc quay sang trái, nên chỉ lật ảnh khi bat bay sang phải.
	animated_sprite.flip_h = facing > 0


func _on_detection_body_entered(body: Node2D) -> void:
	if is_dead or not body.is_in_group("player"):
		return

	_target = body
	_state = State.DIVE


func _on_detection_body_exited(body: Node2D) -> void:
	if body != _target:
		return

	_target = null
	if not is_dead:
		_state = State.RETURN


func _apply_detection_radius() -> void:
	if not is_node_ready():
		return
	var shape := detection_shape.shape as CircleShape2D
	if shape:
		shape.radius = detection_radius


func die() -> void:
	if is_dead:
		return

	is_dead = true
	_target = null
	_state = State.PATROL
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)
	detection_area.set_deferred("monitoring", false)

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
