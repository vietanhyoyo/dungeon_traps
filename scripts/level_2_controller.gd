extends Node2D

@export var player_path: NodePath = ^"Asura"
@export var fire_list_path: NodePath = ^"FireList"

@export var hidden_fire_names: Array[String] = ["Fire8", "Fire9", "Fire10"]
@export var fire_trigger_distance := 220.0
@export var fire_reveal_interval := 0.25

var _player: Node2D
var _hidden_fires: Array[Area2D] = []
var _fire_sequence_triggered := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_setup_hidden_fires()


func _physics_process(_delta: float) -> void:
	if _is_game_over():
		return

	_update_fire_reveal()


func _setup_hidden_fires() -> void:
	var fire_list := get_node_or_null(fire_list_path)
	if not fire_list:
		return

	for fire_name in hidden_fire_names:
		var fire := fire_list.get_node_or_null(NodePath(fire_name)) as Area2D
		if fire:
			_hidden_fires.append(fire)
			_set_fire_active(fire, false)


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


func _get_player() -> Node2D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
