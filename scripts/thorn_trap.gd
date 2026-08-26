extends Node2D

@export var fall_speed := 520.0
@export var max_fall_distance := 768.0
@export_flags_2d_physics var floor_collision_mask := 1
@export var thorn_half_width := 8.0
@export var thorn_half_height := 8.0
@export var floor_probe_margin := 6.0
## Thời gian thorn nằm lại sau khi rơi xuống trước khi biến mất. Để 0 là không tự biến mất.
@export_range(0.0, 10.0, 0.1, "or_greater") var despawn_delay := 0.2
## Thời gian mờ dần lúc biến mất, để không bị mất đột ngột giữa màn.
@export_range(0.0, 2.0, 0.05, "or_greater") var despawn_fade_duration := 0.2

@onready var hazard: Area2D = $Hazard
@onready var trigger_area: Area2D = $TriggerArea

var _start_position: Vector2
var _is_falling := false
var _is_despawning := false


func _ready() -> void:
	_start_position = global_position
	hazard.body_entered.connect(_on_hazard_body_entered)
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _is_game_over():
		return

	var fall_distance := fall_speed * delta
	var floor_y := _get_floor_y(fall_distance + floor_probe_margin)

	if floor_y < INF:
		global_position.y = floor_y - thorn_half_height
		_stop_falling()
		return

	global_position += Vector2.DOWN * fall_distance
	if max_fall_distance > 0.0 and global_position.y - _start_position.y >= max_fall_distance:
		_stop_falling()


func _on_trigger_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or _is_falling:
		return

	_is_falling = true
	trigger_area.set_deferred("monitoring", false)
	set_physics_process(true)


func _on_hazard_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var game_state := get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("trigger_game_over"):
			game_state.trigger_game_over(body)


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


func _stop_falling() -> void:
	_is_falling = false
	set_physics_process(false)
	_start_despawn()


# Rơi xong thì nằm lại đúng despawn_delay giây rồi mờ dần và biến mất.
func _start_despawn() -> void:
	if _is_despawning or despawn_delay <= 0.0:
		return

	_is_despawning = true
	await get_tree().create_timer(despawn_delay, false).timeout
	if not is_instance_valid(self):
		return

	# Tắt sát thương ngay khi bắt đầu mờ, tránh chết oan vì cái gai gần như vô hình.
	hazard.set_deferred("monitoring", false)

	if despawn_fade_duration > 0.0:
		var fade_tween := create_tween()
		fade_tween.tween_property(hazard, "modulate:a", 0.0, despawn_fade_duration)
		await fade_tween.finished

	queue_free()


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
