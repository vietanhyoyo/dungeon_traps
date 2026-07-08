extends Node2D

@export var player_path: NodePath = ^"Asura"
@export var fire_list_path: NodePath = ^"FireList"
@export var thorn_list_path: NodePath = ^"ThornList"

@export var hidden_fire_names: Array[String] = ["Fire8", "Fire9", "Fire10"]
@export var fire_trigger_distance := 220.0
@export var fire_reveal_interval := 0.25

@export var thorn_trigger_width := 96.0
@export var thorn_trigger_distance := 384.0
@export var thorn_fall_speed := 520.0
@export var thorn_max_fall_distance := 768.0
@export_flags_2d_physics var thorn_floor_collision_mask := 1
@export var thorn_half_width := 8.0
@export var thorn_half_height := 8.0
@export var thorn_floor_probe_margin := 6.0

var _player: Node2D
var _hidden_fires: Array[Area2D] = []
var _fire_sequence_triggered := false
var _thorn_states: Array[Dictionary] = []


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_setup_hidden_fires()
	_setup_falling_thorns()


func _physics_process(delta: float) -> void:
	if _is_game_over():
		return

	_update_fire_reveal()
	_update_falling_thorns(delta)


func _setup_hidden_fires() -> void:
	var fire_list := get_node_or_null(fire_list_path)
	if not fire_list:
		return

	for fire_name in hidden_fire_names:
		var fire := fire_list.get_node_or_null(NodePath(fire_name)) as Area2D
		if fire:
			_hidden_fires.append(fire)
			_set_fire_active(fire, false)


func _setup_falling_thorns() -> void:
	var thorn_list := get_node_or_null(thorn_list_path)
	if not thorn_list:
		return

	for child in thorn_list.get_children():
		var thorn := child as Area2D
		if thorn:
			_thorn_states.append({
				"thorn": thorn,
				"start_position": thorn.global_position,
				"falling": false,
				"settled": false,
			})


func _update_fire_reveal() -> void:
	if _fire_sequence_triggered or _hidden_fires.is_empty():
		return

	var player := _get_player()
	if not player:
		return

	if player.global_position.distance_to(_get_fire_trigger_position()) <= fire_trigger_distance:
		_fire_sequence_triggered = true
		_reveal_fires()


func _reveal_fires() -> void:
	for fire in _hidden_fires:
		_set_fire_active(fire, true)
		await get_tree().create_timer(fire_reveal_interval).timeout


func _get_fire_trigger_position() -> Vector2:
	var total := Vector2.ZERO
	for fire in _hidden_fires:
		total += fire.global_position
	return total / float(_hidden_fires.size())


func _set_fire_active(fire: Area2D, active: bool) -> void:
	fire.visible = active
	fire.monitoring = active
	fire.monitorable = active

	for child in fire.find_children("*", "CollisionShape2D", true, false):
		var collision_shape := child as CollisionShape2D
		if collision_shape:
			collision_shape.disabled = not active


func _update_falling_thorns(delta: float) -> void:
	if _thorn_states.is_empty():
		return

	var player := _get_player()
	if not player:
		return

	for state in _thorn_states:
		if state["settled"]:
			continue

		var thorn := state["thorn"] as Area2D
		if not is_instance_valid(thorn):
			state["settled"] = true
			continue

		if not state["falling"]:
			state["falling"] = _should_thorn_start_falling(thorn, player)

		if state["falling"]:
			_fall_thorn(state, delta)


func _should_thorn_start_falling(thorn: Area2D, player: Node2D) -> bool:
	var offset := player.global_position - thorn.global_position
	return absf(offset.x) <= thorn_trigger_width * 0.5 and offset.y > 0.0 and offset.y <= thorn_trigger_distance


func _fall_thorn(state: Dictionary, delta: float) -> void:
	var thorn := state["thorn"] as Area2D
	var fall_distance := thorn_fall_speed * delta
	var floor_y := _get_floor_y(thorn, fall_distance + thorn_floor_probe_margin)

	if floor_y < INF:
		thorn.global_position.y = floor_y - thorn_half_height
		state["settled"] = true
		return

	thorn.global_position += Vector2.DOWN * fall_distance

	var start_position := state["start_position"] as Vector2
	if thorn_max_fall_distance > 0.0 and thorn.global_position.y - start_position.y >= thorn_max_fall_distance:
		state["settled"] = true


func _get_floor_y(thorn: Area2D, distance: float) -> float:
	var closest_y := INF
	var space_state := get_world_2d().direct_space_state

	for x_offset in [-thorn_half_width, 0.0, thorn_half_width]:
		var ray_start := thorn.global_position + Vector2(x_offset, thorn_half_height)
		var ray_end := ray_start + Vector2.DOWN * distance
		var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end, thorn_floor_collision_mask)
		query.collide_with_areas = false
		query.collide_with_bodies = true

		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_position: Vector2 = hit["position"]
			closest_y = minf(closest_y, hit_position.y)

	return closest_y


func _get_player() -> Node2D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
