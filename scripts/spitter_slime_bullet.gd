extends CharacterBody2D

const TOXIC_SMOKE_SCENE := preload("res://nodes/effects/spitter_slime_smoke.tscn")
const GRAVITY := 620.0
const LIFETIME := 4.0
const TERRAIN_MASK := 1
## Đèn phập phồng nhẹ khi bay; tắt dần lúc vỡ.
const GLOW_ENERGY := 1.0
const GLOW_PULSE := 0.18
const GLOW_FADE_DURATION := 0.25
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5
const HIT_EFFECT_SCENE := preload("res://nodes/effects/hit_effect.tscn")
const SOUND_MAX_DISTANCE := 600.0
const SOUND_ATTENUATION := 1.4

var is_dead := false
var _age := 0.0
var _slash_protection_time_left := 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone
@onready var glow: PointLight2D = $Glow
@onready var trail: CPUParticles2D = $Trail


func launch(from: Vector2, initial_velocity: Vector2) -> void:
	global_position = from
	velocity = initial_velocity
	_face_velocity()
	# Hạt vệt đuôi dùng toạ độ thế giới: xoá hạt sinh ra ở vị trí trước launch().
	trail.restart()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_age += delta
	_slash_protection_time_left = maxf(_slash_protection_time_left - delta, 0.0)
	if _age >= LIFETIME:
		_pop()
		return

	velocity.y += GRAVITY * delta
	_face_velocity()
	glow.energy = GLOW_ENERGY + GLOW_PULSE * sin(_age * 18.0)
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


## Giọt độc vẽ hướng sang phải: xoay theo vận tốc để đầu luôn đi trước.
func _face_velocity() -> void:
	if velocity.length_squared() > 1.0:
		animated_sprite.rotation = velocity.angle()


func _spawn_toxic_smoke() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var smoke := TOXIC_SMOKE_SCENE.instantiate() as Node2D
	if smoke == null:
		return
	current_scene.add_child(smoke)
	smoke.global_position = global_position


func on_player_touched(player: Node2D) -> void:
	_spawn_hit_effect(player)
	_pop()


## Cùng hiệu ứng hit.png như lúc player chém trúng quái, đặt ở vị trí player.
## Gắn vào scene màn chơi chứ không vào đạn: đạn tự xoá sau hiệu ứng vỡ.
func _spawn_hit_effect(player: Node2D) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null or not is_instance_valid(player):
		return
	var effect: AnimatedSprite2D = HIT_EFFECT_SCENE.instantiate()
	current_scene.add_child(effect)
	effect.global_position = player.global_position


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
	trail.emitting = false
	if emit_toxic_smoke:
		_spawn_toxic_smoke()
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)

	# Giọt độc vỡ toé ra thành các giọt nhỏ (animation không xoay theo hướng bay).
	animated_sprite.rotation = 0.0
	animated_sprite.play(&"pop")
	var glow_tween := create_tween()
	glow_tween.tween_property(glow, "energy", 0.0, GLOW_FADE_DURATION)
	await animated_sprite.animation_finished
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
