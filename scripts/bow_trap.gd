extends Node2D

const ARROW_SCENE: PackedScene = preload("res://nodes/traps/bow_trap_arrow.tscn")

@export var arrow_speed := 1500.0
@export var fire_delay := 0.12
# Thời gian nạp lại sau khi mũi tên bay hết hoặc cắm vào địa hình.
@export var rearm_delay := 0.6
@export var hit_distance := 10.0
@export var impact_distance := 14.0
@export var deflected_arrow_lifetime := 3.0

@onready var trap_sprite: Sprite2D = $TrapSprite
@onready var trigger_area: Area2D = $TriggerArea
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var target_point: Marker2D = $TargetPoint
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSound

var _has_fired := false
var _has_hit := false
var _rearm_started := false


func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_body_entered)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _has_fired or not body.is_in_group(&"player"):
		return

	_has_fired = true
	trigger_area.set_deferred("monitoring", false)

	# Nhấn nhẹ frame 1 xuống để người chơi thấy ô bẫy vừa được kích hoạt.
	var press_tween := create_tween()
	press_tween.set_parallel(true)
	press_tween.tween_property(trap_sprite, "position:y", 3.0, 0.08)
	press_tween.tween_property(trap_sprite, "scale:y", 0.72, 0.08)

	await get_tree().create_timer(fire_delay).timeout
	if _is_game_over() or not is_inside_tree():
		return

	# Mỗi lần bắn tạo một projectile riêng để các bẫy và các mũi tên đang cắm
	# trên tường không dùng chung hoặc ghi đè trạng thái của nhau.
	var arrow := ARROW_SCENE.instantiate() as BowTrapArrow
	get_tree().current_scene.add_child(arrow)
	arrow.launch(
		spawn_point.global_position,
		target_point.global_position,
		arrow_speed,
		hit_distance,
		impact_distance,
		deflected_arrow_lifetime,
		self
	)
	shoot_sound.play()


func rearm_after_shot() -> void:
	_rearm()


func register_player_hit() -> void:
	_has_hit = true


func _rearm() -> void:
	if _rearm_started or _has_hit:
		return
	_rearm_started = true
	await get_tree().create_timer(rearm_delay).timeout
	if _has_hit or _is_game_over() or not is_inside_tree():
		return

	var release_tween := create_tween()
	release_tween.set_parallel(true)
	release_tween.tween_property(trap_sprite, "position:y", 0.0, 0.12)
	release_tween.tween_property(trap_sprite, "scale:y", 1.0, 0.12)

	_has_fired = false
	_rearm_started = false
	trigger_area.set_deferred("monitoring", true)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
