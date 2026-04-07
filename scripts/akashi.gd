extends CharacterBody2D

const SPEED = 180.0
const JUMP_VELOCITY = -320.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var is_attacking = false
var use_attack_1 = true

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
		
	# Attack input
	if Input.is_action_just_pressed("attack") and not is_attacking:
		is_attacking = true
		
		if use_attack_1:
			animated_sprite.play("attack")
		else:
			animated_sprite.play("attack2")
			
		use_attack_1 = !use_attack_1
		
	# Trong lúc attack thì không override animation
	if is_attacking:
		velocity.x = 0
		move_and_slide()
		return

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction: -1, 0, 1.
	var direction := Input.get_axis("move_left", "move_right")
	
	# Flip the Sprite
	if direction > 0:
		animated_sprite.flip_h = false
	elif direction < 0:
		animated_sprite.flip_h = true
		
	# Play animations
	if is_on_floor():
		if direction == 0:
			animated_sprite.play("idle")
		else: 
			animated_sprite.play("run") 
	else: 
		animated_sprite.play("jump")
	
	# Apply movement
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()
	
func _on_animated_sprite_2d_animation_finished():
	if animated_sprite.animation == "attack" or animated_sprite.animation == "attack2":
		is_attacking = false
		animated_sprite.play("idle")
