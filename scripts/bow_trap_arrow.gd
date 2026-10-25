extends Area2D
class_name BowTrapArrow

const MAX_WALL_SEEK_DISTANCE := 4096.0

var _bow_trap: Node
var _origin_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _wall_collision_start_distance := 0.0
var _direction := Vector2.RIGHT
var _speed := 1500.0
var _hit_distance := 10.0
var _impact_distance := 14.0
var _deflected_lifetime := 3.0
var _deflected_time_left := 0.0
var _continues_until_wall := false
var _deflected := false
var _stuck := false
var _has_hit_player := false
var _finished := false

@onready var impact_sound: AudioStreamPlayer2D = $ImpactSound
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	body_entered.connect(_on_body_entered)
	monitoring = false
	set_physics_process(false)


func launch(
		origin: Vector2,
		target: Vector2,
		flight_speed: float,
		hit_distance: float,
		impact_distance: float,
		deflected_lifetime: float,
		bow_trap: Node,
		continue_until_wall := false
	) -> void:
	global_position = origin
	_origin_position = origin
	_target_position = target
	_speed = flight_speed
	_hit_distance = hit_distance
	_impact_distance = impact_distance
	_deflected_lifetime = deflected_lifetime
	_bow_trap = bow_trap
	_continues_until_wall = continue_until_wall
	_direction = global_position.direction_to(_target_position)
	if _direction.is_zero_approx():
		_direction = Vector2.RIGHT
	_wall_collision_start_distance = maxf(
		0.0,
	(_target_position - _origin_position).dot(_direction)
	)
	global_rotation = _direction.angle() - 3.0 * PI / 4.0
	visible = true
	set_deferred("monitoring", true)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _stuck or _finished:
		return
	if _deflected:
		_move_deflected_arrow(delta)
		return

	_move_arrow(delta)


func _move_arrow(delta: float) -> void:
	var distance := global_position.distance_to(_target_position)
	var next_position: Vector2
	if _continues_until_wall:
		next_position = global_position + _direction * _speed * delta
	else:
		next_position = global_position.move_toward(
			_target_position,
			minf(_speed * delta, distance)
		)

	if _continues_until_wall:
		var start_distance := (global_position - _origin_position).dot(_direction)
		var end_distance := (next_position - _origin_position).dot(_direction)
		if end_distance >= _wall_collision_start_distance:
			var ray_start := global_position
			if start_distance < _wall_collision_start_distance:
				ray_start = _origin_position + _direction * _wall_collision_start_distance
			var hit := _raycast_wall(ray_start, next_position)
			if not hit.is_empty():
				global_position = hit["position"] - _direction * 8.0
				_stick_to_wall()
				return

	global_position = next_position
	if _continues_until_wall:
		if global_position.distance_to(_origin_position) >= MAX_WALL_SEEK_DISTANCE:
			_remove_and_rearm()
	elif distance <= maxf(_hit_distance, _speed * delta):
		_finish_flight()


func _finish_flight() -> void:
	if _finished or _deflected:
		return
	set_physics_process(false)
	global_position = _target_position
	await get_tree().physics_frame
	if _finished or _deflected or not is_inside_tree():
		return

	for body in get_overlapping_bodies():
		if body.is_in_group(&"player"):
			_hit_player(body)
			return

	_remove_and_rearm()


func _on_body_entered(body: Node2D) -> void:
	if _finished or _stuck:
		return
	if body.is_in_group(&"player"):
		if not _deflected:
			_hit_player(body)


func hit_by_attack(deflect_direction: Vector2) -> void:
	if _finished or _stuck or _has_hit_player or _deflected \
			or not visible or deflect_direction.is_zero_approx():
		return

	_deflected = true
	_direction = deflect_direction.normalized()
	_deflected_time_left = _deflected_lifetime
	global_rotation = _direction.angle() - 3.0 * PI / 4.0
	set_physics_process(true)


func _move_deflected_arrow(delta: float) -> void:
	_deflected_time_left -= delta
	if _deflected_time_left <= 0.0:
		_remove_and_rearm()
		return

	var start := global_position
	var end := start + _direction * _speed * delta
	# Quét đường đi để mũi tên không xuyên qua tường ở tốc độ cao.
	var hit := _raycast_wall(start, end)
	if not hit.is_empty():
		# Đưa đầu tên sát vào mặt tường rồi giữ nguyên projectile tại đó.
		global_position = hit["position"] - _direction * 8.0
		_stick_to_wall()
		return

	global_position = end


func _raycast_wall(start: Vector2, end: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = 1
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query)


func _stick_to_wall() -> void:
	if _finished or _stuck or (not _deflected and not _continues_until_wall):
		return

	_stuck = true
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	remove_from_group(&"slashable_projectile")
	impact_sound.pitch_scale = _random.randf_range(0.94, 1.06)
	impact_sound.play()
	_notify_trap_rearm()


func _remove_and_rearm() -> void:
	if _finished or _stuck:
		return

	_finished = true
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	_notify_trap_rearm()
	queue_free()


func _hit_player(player: Node2D) -> void:
	if _finished or _deflected or not is_instance_valid(player):
		return

	var game_state := get_node_or_null("/root/GameState")
	if game_state == null or not game_state.has_method("trigger_game_over"):
		_remove_and_rearm()
		return

	_has_hit_player = true
	_finished = true
	set_physics_process(false)
	set_deferred("monitoring", false)
	var impact_direction := global_position.direction_to(player.global_position)
	if impact_direction.length_squared() <= 0.0001:
		impact_direction = _direction
	global_position = player.global_position - impact_direction * _impact_distance
	if _bow_trap != null and is_instance_valid(_bow_trap) \
			and _bow_trap.has_method("register_player_hit"):
		_bow_trap.register_player_hit()
	game_state.trigger_game_over(player)


func _notify_trap_rearm() -> void:
	if _bow_trap != null and is_instance_valid(_bow_trap) \
			and _bow_trap.has_method("rearm_after_shot"):
		_bow_trap.rearm_after_shot()
