extends CharacterBody2D

const TOXIC_SMOKE_SCENE := preload("res://nodes/effects/spitter_slime_smoke.tscn")
const GRAVITY := 620.0
const LIFETIME := 4.0
const TERRAIN_MASK := 1
const POP_DURATION := 0.16
const TRAIL_SPACING := 9.0
const TRAIL_RADII := [4.0, 3.0, 2.0]
const TRAIL_COLORS := [
	Color(0.25, 1.0, 0.35, 0.78),
	Color(0.25, 1.0, 0.35, 0.52),
	Color(0.25, 1.0, 0.35, 0.3),
]
const MAX_TRAIL_HISTORY := 24
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5
const SOUND_MAX_DISTANCE := 600.0
const SOUND_ATTENUATION := 1.4

var is_dead := false
var _age := 0.0
var _slash_protection_time_left := 0.0
var _trail_positions: Array[Vector2] = []

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone
@onready var glow: PointLight2D = $Glow


func launch(from: Vector2, initial_velocity: Vector2) -> void:
	global_position = from
	velocity = initial_velocity
	_trail_positions.clear()
	_trail_positions.append(from)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_age += delta
	_slash_protection_time_left = maxf(_slash_protection_time_left - delta, 0.0)
	if _age >= LIFETIME:
		_pop()
		return

	velocity.y += GRAVITY * delta
	var motion := velocity * delta
	var terrain_hit := _terrain_hit(motion)
	if terrain_hit.is_empty():
		global_position += motion
		_record_trail_position()
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


func _record_trail_position() -> void:
	_trail_positions.push_front(global_position)
	if _trail_positions.size() > MAX_TRAIL_HISTORY:
		_trail_positions.pop_back()
	queue_redraw()


func _draw() -> void:
	if is_dead or _trail_positions.is_empty():
		return

	var trail_index := 0
	var distance_traveled := 0.0
	var required_distance := TRAIL_SPACING
	var newer_position := global_position
	for older_position in _trail_positions:
		var segment_length := newer_position.distance_to(older_position)
		if segment_length > 0.001:
			while trail_index < TRAIL_RADII.size() and distance_traveled + segment_length >= required_distance:
				var segment_offset := required_distance - distance_traveled
				var trail_position := newer_position.lerp(older_position, segment_offset / segment_length)
				draw_circle(
					trail_position - global_position,
					TRAIL_RADII[trail_index],
					TRAIL_COLORS[trail_index]
				)
				trail_index += 1
				required_distance += TRAIL_SPACING
			distance_traveled += segment_length
		newer_position = older_position
		if trail_index >= TRAIL_RADII.size():
			break


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
	if is_dead or _slash_protection_time_left > 0.0:
		return
	_play_defeat_sound()
	_pop(true)


## Cho viên đạn cuối bay qua cú chém vừa hạ spitter-slime; sau thời gian này,
## Asura có thể chém phá nó như mọi viên đạn khác.
func protect_from_slash_for(duration: float) -> void:
	_slash_protection_time_left = maxf(_slash_protection_time_left, duration)


func _pop(emit_toxic_smoke := false) -> void:
	if is_dead:
		return

	is_dead = true
	_trail_positions.clear()
	queue_redraw()
	if emit_toxic_smoke:
		_spawn_toxic_smoke()
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
	sound_player.max_distance = SOUND_MAX_DISTANCE
	sound_player.attenuation = SOUND_ATTENUATION
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	sound_player.play(DEFEAT_SOUND_OFFSET)
