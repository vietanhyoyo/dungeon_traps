extends CharacterBody2D

const TOXIC_SMOKE_SCENE := preload("res://nodes/effects/spitter_slime_smoke.tscn")
const GRAVITY := 620.0
const LIFETIME := 4.0
const TERRAIN_MASK := 1
const POP_DURATION := 0.16
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5

var is_dead := false
var _age := 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone
@onready var glow: PointLight2D = $Glow


func launch(from: Vector2, initial_velocity: Vector2) -> void:
	global_position = from
	velocity = initial_velocity


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_age += delta
	if _age >= LIFETIME:
		_pop()
		return

	velocity.y += GRAVITY * delta
	var motion := velocity * delta
	var terrain_hit := _terrain_hit(motion)
	if terrain_hit.is_empty():
		global_position += motion
		return

	var terrain_normal: Vector2 = terrain_hit["normal"]
	var landed_on_ground: bool = velocity.y >= 0.0 and terrain_normal.y < -0.5
	global_position = terrain_hit["position"]
	if landed_on_ground:
		_spawn_toxic_smoke()
	_pop()


func _terrain_hit(motion: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + motion)
	query.collision_mask = TERRAIN_MASK
	return get_world_2d().direct_space_state.intersect_ray(query)


func _spawn_toxic_smoke() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var smoke := TOXIC_SMOKE_SCENE.instantiate() as Node2D
	if smoke == null:
		return
	current_scene.add_child(smoke)
	smoke.global_position = global_position


func on_player_touched(_player: Node2D) -> void:
	_pop()


func die() -> void:
	if is_dead:
		return
	_play_defeat_sound()
	_pop()


func _pop() -> void:
	if is_dead:
		return

	is_dead = true
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)

	var pop_tween := create_tween().set_parallel(true)
	pop_tween.tween_property(animated_sprite, "scale", Vector2(1.8, 1.8), POP_DURATION)
	pop_tween.tween_property(animated_sprite, "modulate:a", 0.0, POP_DURATION)
	pop_tween.tween_property(glow, "energy", 0.0, POP_DURATION)
	await pop_tween.finished
	queue_free()


func _play_defeat_sound() -> void:
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEFEAT_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	sound_player.pitch_scale = 1.4
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	sound_player.play(DEFEAT_SOUND_OFFSET)
