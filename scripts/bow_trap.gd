extends Node2D

@export var arrow_speed := 1500.0
@export var fire_delay := 0.12
# Camera của game là 1152x648; offset này đưa mũi tên gần rìa trên-bên phải
# khi player đứng trên ô bẫy, tạo khoảng bay đủ dài để nhìn rõ animation.
@export var arrow_spawn_offset := Vector2(480.0, -260.0)
@export var hit_distance := 10.0
@export var impact_distance := 14.0

@onready var trap_sprite: Sprite2D = $TrapSprite
@onready var trigger_area: Area2D = $TriggerArea
@onready var arrow: Area2D = $Arrow
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSound

var _target: Node2D
var _has_fired := false
var _has_hit := false


func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	arrow.body_entered.connect(_on_arrow_body_entered)
	arrow.visible = false
	arrow.monitoring = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target) or _is_game_over():
		set_physics_process(false)
		return

	var target_position := _target.global_position
	var direction := arrow.global_position.direction_to(target_position)
	var distance := arrow.global_position.distance_to(target_position)

	# Đầu mũi tên trong frame 2 hướng chéo xuống-trái (135 độ).
	# Xoay theo vector bay để đầu mũi tên luôn chĩa về phía player.
	arrow.global_rotation = direction.angle() - 3.0 * PI / 4.0
	arrow.global_position = arrow.global_position.move_toward(
		target_position,
		minf(arrow_speed * delta, distance)
	)

	if distance <= maxf(hit_distance, arrow_speed * delta):
		_hit_player(_target)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _has_fired or not body.is_in_group(&"player"):
		return

	_has_fired = true
	_target = body
	trigger_area.set_deferred("monitoring", false)

	# Nhấn nhẹ frame 1 xuống để người chơi thấy ô bẫy vừa được kích hoạt.
	var press_tween := create_tween()
	press_tween.set_parallel(true)
	press_tween.tween_property(trap_sprite, "position:y", 3.0, 0.08)
	press_tween.tween_property(trap_sprite, "scale:y", 0.72, 0.08)

	await get_tree().create_timer(fire_delay).timeout
	if not is_instance_valid(_target) or _is_game_over():
		return

	arrow.global_position = global_position + arrow_spawn_offset
	arrow.visible = true
	arrow.set_deferred("monitoring", true)
	shoot_sound.play()
	set_physics_process(true)


func _on_arrow_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_hit_player(body)


func _hit_player(player: Node2D) -> void:
	if _has_hit or not is_instance_valid(player):
		return

	_has_hit = true
	set_physics_process(false)
	arrow.set_deferred("monitoring", false)
	# Giữ đầu mũi tên ngay trước mặt player thay vì đặt chồng vào tâm nhân vật.
	var impact_direction := arrow.global_position.direction_to(player.global_position)
	if impact_direction.length_squared() <= 0.0001:
		# Ở tốc độ cao, mũi tên có thể đi hết quãng đường trong một frame.
		impact_direction = Vector2.from_angle(arrow.global_rotation + 3.0 * PI / 4.0)
	arrow.global_position = player.global_position - impact_direction * impact_distance

	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("trigger_game_over"):
		game_state.trigger_game_over(player)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
