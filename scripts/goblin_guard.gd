extends CharacterBody2D

signal defeated

enum State { PATROL, WINDUP, STRIKE, RECOVER }

@export var patrol_left := 42.0
@export var patrol_right := 42.0
@export var speed := 47.0
@export var max_health := 5
@export var windup_time := 0.30
@export var recovery_time := 0.50

var is_dead := false
var current_health: int
var _state := State.PATROL
var _origin_x: float
var _direction := -1
var _time_left := 0.0
var _walk_cycle := 0.0
var _flash_left := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var footing: RayCast2D = $Footing
@onready var detection: Area2D = $Detection
@onready var strike_area: Area2D = $Killzone
@onready var strike_shape: CollisionShape2D = $Killzone/CollisionShape2D


func _ready() -> void:
	_origin_x = position.x
	current_health = max_health
	_face(_direction)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta

	velocity.x = 0.0
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			sprite.self_modulate = Color.WHITE

	if _state == State.PATROL:
		_patrol(delta)
	else:
		_time_left -= delta
		if _time_left <= 0.0:
			_advance_attack()

	move_and_slide()


func _patrol(delta: float) -> void:
	if not is_on_floor():
		return
	for body in detection.get_overlapping_bodies():
		if body.is_in_group(&"player"):
			_face(1 if body.global_position.x > global_position.x else -1)
			_state = State.WINDUP
			_time_left = windup_time
			sprite.frame = 4
			return
	if patrol_left + patrol_right <= 0.0:
		sprite.frame = 0
		return

	var at_limit := (position.x >= _origin_x + patrol_right and _direction > 0) \
			or (position.x <= _origin_x - patrol_left and _direction < 0)
	if at_limit or is_on_wall() or not footing.is_colliding():
		_face(-_direction)
		footing.force_raycast_update()
	if footing.is_colliding():
		velocity.x = _direction * speed
		_walk_cycle = fmod(_walk_cycle + delta * speed / 5.0, 4.0)
		sprite.frame = int(_walk_cycle)


func _face(direction: int) -> void:
	_direction = direction
	sprite.flip_h = _direction < 0
	footing.position.x = absf(footing.position.x) * _direction
	strike_area.position.x = absf(strike_area.position.x) * _direction


func _advance_attack() -> void:
	match _state:
		State.WINDUP:
			_state = State.STRIKE
			_time_left = 0.16
			sprite.frame = 5
			strike_shape.set_deferred("disabled", false)
		State.STRIKE:
			_state = State.RECOVER
			_time_left = recovery_time
			sprite.frame = 0
			strike_shape.set_deferred("disabled", true)
		State.RECOVER:
			_state = State.PATROL


func take_damage(amount: int = 1) -> void:
	if is_dead or amount <= 0:
		return
	current_health = maxi(current_health - amount, 0)
	if current_health == 0:
		die()
	else:
		sprite.self_modulate = Color(1.9, 1.4, 0.9)
		_flash_left = 0.12


func die() -> void:
	if is_dead:
		return
	is_dead = true
	defeated.emit()
	$CollisionShape2D.set_deferred("disabled", true)
	strike_shape.set_deferred("disabled", true)
	sprite.self_modulate = Color(1.9, 1.6, 1.0)
	var fade := create_tween()
	fade.tween_property(sprite, "modulate:a", 0.0, 0.18)
	fade.tween_callback(queue_free)
