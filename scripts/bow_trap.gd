extends Node2D

@export var arrow_speed := 1500.0
@export var fire_delay := 0.12
# Thời gian nạp lại sau một phát bắn hụt, trước khi bẫy nhận kích hoạt tiếp.
@export var rearm_delay := 0.6
@export var hit_distance := 10.0
@export var impact_distance := 14.0

@onready var trap_sprite: Sprite2D = $TrapSprite
@onready var trigger_area: Area2D = $TriggerArea
@onready var arrow: Area2D = $Arrow
# Kéo hai Marker2D này trong editor để chỉnh nơi mũi tên xuất phát và nơi nó bay tới.
# SpawnPoint nằm ngoài rìa camera (1152x648) để có quãng bay đủ dài;
# TargetPoint mặc định đặt ngay chỗ thân player khi đứng trên ô bẫy.
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var target_point: Marker2D = $TargetPoint
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSound

var _target_position := Vector2.ZERO
var _has_fired := false
var _has_hit := false


func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	arrow.body_entered.connect(_on_arrow_body_entered)
	arrow.visible = false
	arrow.monitoring = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _is_game_over():
		set_physics_process(false)
		return

	# Mũi tên bay tới điểm đã khoá lúc bắn, không bám theo player nữa.
	var distance := arrow.global_position.distance_to(_target_position)
	arrow.global_position = arrow.global_position.move_toward(
		_target_position,
		minf(arrow_speed * delta, distance)
	)

	if distance <= maxf(hit_distance, arrow_speed * delta):
		_finish_flight()


func _on_trigger_body_entered(body: Node2D) -> void:
	if _has_fired or not body.is_in_group(&"player"):
		return

	_has_fired = true
	# Khoá điểm ngắm ngay lúc player chạm bẫy; mũi tên không đuổi theo nữa.
	_target_position = target_point.global_position
	trigger_area.set_deferred("monitoring", false)

	# Nhấn nhẹ frame 1 xuống để người chơi thấy ô bẫy vừa được kích hoạt.
	var press_tween := create_tween()
	press_tween.set_parallel(true)
	press_tween.tween_property(trap_sprite, "position:y", 3.0, 0.08)
	press_tween.tween_property(trap_sprite, "scale:y", 0.72, 0.08)

	await get_tree().create_timer(fire_delay).timeout
	if _is_game_over():
		return

	arrow.global_position = spawn_point.global_position
	# Hướng bay cố định ngay lúc bắn. Đầu mũi tên trong frame 2 chĩa chéo
	# xuống-trái (135 độ) nên phải bù lại góc đó.
	arrow.global_rotation = (
		arrow.global_position.direction_to(_target_position).angle() - 3.0 * PI / 4.0
	)
	arrow.visible = true
	arrow.set_deferred("monitoring", true)
	shoot_sound.play()
	set_physics_process(true)


func _finish_flight() -> void:
	set_physics_process(false)
	arrow.global_position = _target_position

	# Chờ một frame vật lý để Area2D kịp báo va chạm ở vị trí cuối,
	# nếu player đã né đi thì mũi tên chỉ đơn giản cắm xuống rồi biến mất.
	await get_tree().physics_frame
	if _has_hit or not is_instance_valid(arrow):
		return

	for body in arrow.get_overlapping_bodies():
		if body.is_in_group(&"player"):
			_hit_player(body)
			return

	arrow.set_deferred("monitoring", false)
	arrow.visible = false
	_rearm()


func _rearm() -> void:
	# Bắn hụt thì bẫy nạp lại: player quay lại giẫm lên sẽ bị bắn tiếp.
	await get_tree().create_timer(rearm_delay).timeout
	if _has_hit or _is_game_over() or not is_inside_tree():
		return

	var release_tween := create_tween()
	release_tween.set_parallel(true)
	release_tween.tween_property(trap_sprite, "position:y", 0.0, 0.12)
	release_tween.tween_property(trap_sprite, "scale:y", 1.0, 0.12)

	_has_fired = false
	trigger_area.set_deferred("monitoring", true)


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
