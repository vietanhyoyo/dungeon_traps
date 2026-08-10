extends CharacterBody2D

const SPEED = 180.0
const JUMP_VELOCITY = -320.0
const LANDING_DUST_MIN_SPEED = 180.0
const DEATH_JUMP_VELOCITY = -420.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var running_sound: AudioStreamPlayer2D = $RunningSound
@onready var attack_sound: AudioStreamPlayer2D = $AttackSound
@onready var dust_scene = preload("res://nodes/effects/landing_dust.tscn")

var is_attacking = false
var is_dead = false
var use_attack_1 = true
var was_on_floor = false
var last_fall_speed = 0.0

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity += get_gravity() * delta
		position += velocity * delta
		running_sound.stop()
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
		last_fall_speed = velocity.y
		
	# Attack input
	if Input.is_action_just_pressed("attack") and not is_attacking:
		is_attacking = true
		attack_sound.play()

		# Nếu đang trên không thì luôn dùng attack2
		if not is_on_floor():
			animated_sprite.play("attack2")
		else:
			# Ở dưới đất thì xen kẽ
			if use_attack_1:
				animated_sprite.play("attack")
			else:
				animated_sprite.play("attack2")
			
			use_attack_1 = !use_attack_1
		
	# Trong lúc attack thì không override animation
	if is_attacking:
		velocity.x = 0
		running_sound.stop()
		move_and_slide()
		
		# Kiểm tra vừa chạm đất trong lúc attack
		if not was_on_floor and is_on_floor() and last_fall_speed > LANDING_DUST_MIN_SPEED:
			spawn_landing_dust()
			last_fall_speed = 0.0
			
		was_on_floor = is_on_floor()
		return

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction: -1, 0, 1
	var direction := Input.get_axis("move_left", "move_right")
	
	# Flip the Sprite
	if direction > 0:
		animated_sprite.flip_h = false
	elif direction < 0:
		animated_sprite.flip_h = true
		
	# Apply movement
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

	# Vừa chạm đất sau khi rơi
	if not was_on_floor and is_on_floor() and last_fall_speed > LANDING_DUST_MIN_SPEED:
		spawn_landing_dust()
		last_fall_speed = 0.0

	was_on_floor = is_on_floor()

	# Play animations
	if is_on_floor():
		if direction == 0:
			animated_sprite.play("idle")
			running_sound.stop()
		else:
			animated_sprite.play("run")
			if not running_sound.playing:
				running_sound.play()
	else:
		if velocity.y < 0:
			animated_sprite.play("jump_up")
		else:
			animated_sprite.play("jump_down")
		running_sound.stop()


func spawn_landing_dust() -> void:
	for offset_x in [-6, 6]:
		var dust = dust_scene.instantiate()
		get_parent().add_child(dust)
		dust.global_position = global_position + Vector2(offset_x, 32)


func die() -> void:
	if is_dead:
		return

	is_dead = true
	is_attacking = false
	running_sound.stop()
	velocity = Vector2(0.0, DEATH_JUMP_VELOCITY)
	collision_layer = 0
	collision_mask = 0

	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	if animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
	else:
		animated_sprite.play("jump_up")


func _on_animated_sprite_2d_animation_finished():
	if animated_sprite.animation in ["attack", "attack2"]:
		is_attacking = false
		animated_sprite.play("idle")
