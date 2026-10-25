extends Node2D

const ARROW_SCENE: PackedScene = preload("res://nodes/traps/bow_trap_arrow.tscn")

@export_range(1, 32, 1) var arrow_count := 11
@export_range(0.0, 1.0, 0.01) var arrow_interval := 0.1
@export var arrow_speed := 1500.0
@export var hit_distance := 10.0
@export var impact_distance := 14.0
@export var deflected_arrow_lifetime := 3.0
@export var rearm_delay := 0.8

@onready var trigger_area: Area2D = $TriggerArea
@onready var trigger_collision: CollisionShape2D = $TriggerArea/CollisionShape2D
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var target_point: Marker2D = $TargetPoint

var _random := RandomNumberGenerator.new()
var _has_fired := false
var _has_hit := false
var _pending_arrows := 0
var _rearm_started := false


func _ready() -> void:
	_random.randomize()
	trigger_area.body_entered.connect(_on_trigger_body_entered)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _has_fired or not body.is_in_group(&"player"):
		return

	_has_fired = true
	trigger_area.set_deferred("monitoring", false)
	_pending_arrows = arrow_count
	var spread_width := _get_trigger_width()
	var spread_center_offset := trigger_collision.global_position.x - target_point.global_position.x
	var spread_offsets: Array[float] = []
	for index in range(arrow_count):
		var segment_start := spread_center_offset - spread_width * 0.5 \
			+ spread_width * float(index) / float(arrow_count)
		var segment_end := spread_center_offset - spread_width * 0.5 \
			+ spread_width * float(index + 1) / float(arrow_count)
		spread_offsets.append(_random.randf_range(segment_start, segment_end))
	spread_offsets.shuffle()

	for index in range(arrow_count):
		if _is_game_over() or not is_inside_tree():
			return

		var spread_offset: float = spread_offsets[index]
		var arrow := ARROW_SCENE.instantiate() as BowTrapArrow
		get_tree().current_scene.add_child(arrow)
		var offset := Vector2(spread_offset, 0.0)
		arrow.launch(
			spawn_point.global_position + offset,
			target_point.global_position + offset,
			arrow_speed,
			hit_distance,
			impact_distance,
			deflected_arrow_lifetime,
			self,
			true
		)

		if index < arrow_count - 1 and arrow_interval > 0.0:
			await get_tree().create_timer(arrow_interval).timeout


func _get_trigger_width() -> float:
	var rectangle := trigger_collision.shape as RectangleShape2D
	if rectangle == null:
		return 160.0
	return rectangle.size.x * absf(trigger_collision.global_scale.x)


func register_player_hit() -> void:
	_has_hit = true


func rearm_after_shot() -> void:
	if not _has_fired or _has_hit:
		return

	_pending_arrows = maxi(0, _pending_arrows - 1)
	if _pending_arrows == 0:
		_rearm()


func _rearm() -> void:
	if _rearm_started or _has_hit:
		return
	_rearm_started = true
	await get_tree().create_timer(rearm_delay).timeout
	if _has_hit or _is_game_over() or not is_inside_tree():
		return

	_has_fired = false
	_rearm_started = false
	trigger_area.set_deferred("monitoring", true)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
