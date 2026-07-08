extends Area2D

@export var trigger_width := 96.0
@export var trigger_distance := 384.0
@export var fall_speed := 520.0
@export var max_fall_distance := 768.0
@export_flags_2d_physics var floor_collision_mask := 1
@export var thorn_half_width := 8.0
@export var thorn_half_height := 8.0
@export var floor_probe_margin := 6.0

var _is_falling := false
var _start_position := Vector2.ZERO
var _player: Node2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_start_position = global_position
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(delta: float) -> void:
	if _is_game_over():
		return

	if not _is_falling:
		_try_start_falling()
		return

	_fall(delta)


func _fall(delta: float) -> void:
	var fall_distance := fall_speed * delta
	var floor_y := _get_floor_y(fall_distance + floor_probe_margin)

	if floor_y < INF:
		global_position.y = floor_y - thorn_half_height
		set_physics_process(false)
		return

	global_position += Vector2.DOWN * fall_distance

	if max_fall_distance > 0.0 and global_position.y - _start_position.y >= max_fall_distance:
		set_physics_process(false)


func _try_start_falling() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D

	if not _player:
		return

	var offset := _player.global_position - global_position
	if absf(offset.x) <= trigger_width * 0.5 and offset.y > 0.0 and offset.y <= trigger_distance:
		_is_falling = true


func _get_floor_y(distance: float) -> float:
	var closest_y := INF
	var space_state := get_world_2d().direct_space_state

	for x_offset in [-thorn_half_width, 0.0, thorn_half_width]:
		var ray_start := global_position + Vector2(x_offset, thorn_half_height)
		var ray_end := ray_start + Vector2.DOWN * distance
		var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end, floor_collision_mask)
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_position: Vector2 = hit["position"]
			closest_y = minf(closest_y, hit_position.y)

	return closest_y


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var game_state := get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("trigger_game_over"):
			game_state.trigger_game_over(body)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
