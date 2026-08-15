extends CharacterBody2D

const SPEED = 180.0
const JUMP_VELOCITY = -320.0
const SLIDE_SPEED = 240.0
const SLIDE_DURATION = 0.4
const SLIDE_COLLISION_HEIGHT = 34.0
const AIR_SLIDE_SPRITE_OFFSET_Y = -16.0
const LANDING_DUST_MIN_SPEED = 180.0
const DEATH_JUMP_VELOCITY = -420.0
# Bỏ qua đoạn đầu file tiếng chém để tiếng khớp sớm hơn với lúc vung kiếm
const ATTACK_SOUND_OFFSET = 0.2
# Thời gian giữ animation "hust" trước khi chuyển sang animation chết
const HURT_DURATION = 0.4

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var running_sound: AudioStreamPlayer2D = $RunningSound
@onready var attack_sound: AudioStreamPlayer2D = $AttackSound
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_shape_high: CollisionShape2D = $AttackHitbox/HighShape
@onready var attack_shape_low: CollisionShape2D = $AttackHitbox/LowShape
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var dust_scene = preload("res://nodes/effects/landing_dust.tscn")

var is_attacking = false
var is_sliding = false
var is_hurt = false
var is_dead = false
var movement_locked = false
var use_attack_1 = true
var was_on_floor = false
var last_fall_speed = 0.0
var slide_direction = 1.0
var slide_time_left = 0.0
var normal_collision_height = 0.0
var normal_collision_position = Vector2.ZERO
var normal_sprite_position = Vector2.ZERO

# Vùng sát thương đang dùng cho đòn hiện tại: "attack" chém cao, "attack2" chém thấp
var attack_shape: CollisionShape2D = null
var hit_enemies: Array[Node] = []

func _ready() -> void:
	# Shape là Resource nên cần bản riêng trước khi thay đổi kích thước lúc chạy.
	body_collision.shape = body_collision.shape.duplicate()
	var capsule := body_collision.shape as CapsuleShape2D
	if capsule:
		normal_collision_height = capsule.height
	normal_collision_position = body_collision.position
	normal_sprite_position = animated_sprite.position
	clear_attack_hitbox()


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity += get_gravity() * delta
		position += velocity * delta
		running_sound.stop()
		return

	if movement_locked:
		velocity = Vector2.ZERO
		running_sound.stop()
		return

	# Khi đang lướt, giữ nguyên hướng nhìn và vận tốc cho đến hết animation.
	if is_sliding:
		slide_time_left -= delta
		velocity.x = slide_direction * SLIDE_SPEED
		# Giữ nhân vật trên cùng độ cao trong suốt cú lướt, kể cả ngoài không trung.
		velocity.y = 0.0
		move_and_slide()

		if slide_time_left <= 0.0 or is_on_wall():
			stop_slide()
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
		last_fall_speed = velocity.y

	# Có thể lướt cả trên mặt đất lẫn trên không; hướng lướt là hướng nhân vật đang nhìn.
	if Input.is_action_just_pressed("slide") and not is_attacking:
		start_slide()
		return
		
	# Attack input
	if Input.is_action_just_pressed("attack") and not is_attacking:
		# Nếu đang trên không thì luôn dùng attack2
		if not is_on_floor():
			start_attack("attack2")
		else:
			# Ở dưới đất thì xen kẽ
			if use_attack_1:
				start_attack("attack")
			else:
				start_attack("attack2")

			use_attack_1 = !use_attack_1

	# Trong lúc attack thì không override animation
	if is_attacking:
		velocity.x = 0
		running_sound.stop()
		update_attack_hitbox()
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


func start_attack(anim: String) -> void:
	is_attacking = true
	attack_sound.play(ATTACK_SOUND_OFFSET)
	animated_sprite.play(anim)

	hit_enemies.clear()
	# "attack" là nhát chém ngang tầm ngực, "attack2" là nhát chém thấp xuống chân
	attack_shape = attack_shape_low if anim == "attack2" else attack_shape_high

	# Lật vùng sát thương theo hướng nhân vật đang quay. Phải đặt trước khi bật
	# shape, vì physics server chỉ đọc transform mới ở bước kế tiếp.
	var facing := -1.0 if animated_sprite.flip_h else 1.0
	attack_shape.position.x = absf(attack_shape.position.x) * facing


func start_slide() -> void:
	var started_in_air := not is_on_floor()
	is_sliding = true
	slide_time_left = SLIDE_DURATION
	slide_direction = -1.0 if animated_sprite.flip_h else 1.0
	velocity = Vector2(slide_direction * SLIDE_SPEED, 0.0)
	running_sound.stop()
	set_slide_collision(true)
	set_air_slide_sprite_offset(started_in_air)
	animated_sprite.play("slide")
	if not started_in_air:
		spawn_landing_dust()


func stop_slide() -> void:
	is_sliding = false
	slide_time_left = 0.0
	velocity.x = 0.0
	set_slide_collision(false)
	set_air_slide_sprite_offset(false)
	animated_sprite.play("idle")


func set_slide_collision(enabled: bool) -> void:
	var capsule := body_collision.shape as CapsuleShape2D
	if not capsule:
		return

	if enabled:
		capsule.height = SLIDE_COLLISION_HEIGHT
		# Dịch tâm xuống một nửa phần chiều cao bị cắt để đáy capsule giữ nguyên.
		body_collision.position.y = normal_collision_position.y + \
			(normal_collision_height - SLIDE_COLLISION_HEIGHT) * 0.5
	else:
		capsule.height = normal_collision_height
		body_collision.position = normal_collision_position


func set_air_slide_sprite_offset(enabled: bool) -> void:
	animated_sprite.position = normal_sprite_position
	if enabled:
		# Khung slide 96px đặt phần đầu thấp hơn khung jump 64px khoảng 12px.
		animated_sprite.position.y += AIR_SLIDE_SPRITE_OFFSET_Y


func update_attack_hitbox() -> void:
	if attack_shape == null:
		return

	# Frame 0 là lúc lấy đà, chỉ gây sát thương từ frame vung kiếm trở đi
	if animated_sprite.frame < 1:
		return

	attack_shape.disabled = false

	for body in attack_hitbox.get_overlapping_bodies():
		hit_enemy(body)


func hit_enemy(body: Node) -> void:
	if body in hit_enemies:
		return
	if not body.is_in_group("enemy"):
		return

	hit_enemies.append(body)
	if body.has_method("die"):
		body.die()


func clear_attack_hitbox() -> void:
	attack_shape = null
	hit_enemies.clear()
	# set_deferred vì clear có thể được gọi từ trong callback va chạm (die)
	attack_shape_high.set_deferred("disabled", true)
	attack_shape_low.set_deferred("disabled", true)


func spawn_landing_dust() -> void:
	# Một đám bụi toả ngược hướng nhân vật đang quay và đặt lệch về phía sau
	# lưng. Sprite bụi 32x32 vẽ sát đáy ô nên tâm phải nằm cao hơn chân nhân vật
	# đúng nửa ô (16px) thì đáy mới chạm đất.
	var facing := -1 if animated_sprite.flip_h else 1
	var dust: AnimatedSprite2D = dust_scene.instantiate()
	dust.flip_h = not animated_sprite.flip_h
	get_parent().add_child(dust)
	dust.global_position = global_position + Vector2(-facing * 10, 16)


# Player trúng đòn (slime, bẫy...): khoá điều khiển và giữ animation "hust"
# một nhịp ngắn trước khi hazard xử lý tiếp (thường là game over).
func take_hit() -> void:
	if is_dead or is_hurt:
		return

	is_hurt = true
	is_attacking = false
	is_sliding = false
	set_slide_collision(false)
	set_air_slide_sprite_offset(false)
	clear_attack_hitbox()
	running_sound.stop()
	movement_locked = true
	velocity = Vector2.ZERO

	if animated_sprite.sprite_frames.has_animation("hust"):
		animated_sprite.play("hust")

	await get_tree().create_timer(HURT_DURATION).timeout


func die() -> void:
	if is_dead:
		return

	is_dead = true
	is_attacking = false
	is_sliding = false
	set_slide_collision(false)
	set_air_slide_sprite_offset(false)
	clear_attack_hitbox()
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


func lock_movement() -> void:
	movement_locked = true
	is_sliding = false
	set_slide_collision(false)
	set_air_slide_sprite_offset(false)
	velocity = Vector2.ZERO


func _on_animated_sprite_2d_animation_finished():
	if animated_sprite.animation in ["attack", "attack2"]:
		is_attacking = false
		clear_attack_hitbox()
		animated_sprite.play("idle")
