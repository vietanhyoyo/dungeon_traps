@tool
extends CharacterBody2D

const SPEED = 30.0

## Vùng tuần tra, tính bằng px từ vị trí đặt slime trong editor.
## Để -1 nghĩa là không giới hạn phía đó, chỉ quay đầu khi đụng tường.
@export_range(-1.0, 1000.0, 1.0, "or_greater") var patrol_left: float = -1.0:
	set(value):
		patrol_left = value
		queue_redraw()

@export_range(-1.0, 1000.0, 1.0, "or_greater") var patrol_right: float = -1.0:
	set(value):
		patrol_right = value
		queue_redraw()

var direction = 1
var is_dead := false
var is_attacking := false

var _start_x: float = 0.0

@onready var ray_cast_right: RayCast2D = $RayCastRight
@onready var ray_cast_left: RayCast2D = $RayCastLeft
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = $Killzone

func _ready() -> void:
	_start_x = position.x

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_dead:
		return
	if is_attacking:
		velocity = Vector2.ZERO
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Chỉ đổi hướng khi đang đứng trên đất, để lúc rơi không bị xoay qua lại
	if is_on_floor():
		if patrol_right >= 0.0 and position.x >= _start_x + patrol_right:
			direction = -1
		elif patrol_left >= 0.0 and position.x <= _start_x - patrol_left:
			direction = 1
		elif ray_cast_right.is_colliding():
			direction = -1
		elif ray_cast_left.is_colliding():
			direction = 1

	# Sprite được vẽ quay sang trái, nên lật lại khi đi sang phải
	animated_sprite.flip_h = direction > 0

	velocity.x = direction * SPEED
	move_and_slide()

# Bị nhân vật chém trúng: phát animation chết rồi biến mất
func die() -> void:
	if is_dead:
		return

	is_dead = true
	velocity = Vector2.ZERO
	# Tắt va chạm để không còn giết được người chơi trong lúc đang tan biến
	collision_shape.set_deferred("disabled", true)
	killzone.set_deferred("monitoring", false)

	if animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
		await animated_sprite.animation_finished

	queue_free()


# Player chạm vào slime: quay mặt về player và phát animation attack.
func on_player_touched(player: Node2D) -> void:
	if is_dead:
		return

	var player_direction := signf(player.global_position.x - global_position.x)
	if player_direction != 0.0:
		direction = int(player_direction)
		animated_sprite.flip_h = direction > 0

	is_attacking = true
	velocity = Vector2.ZERO
	if animated_sprite.sprite_frames.has_animation("attack"):
		animated_sprite.play("attack")
		await animated_sprite.animation_finished


# Vẽ vùng tuần tra trong editor cho dễ canh
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if patrol_left < 0.0 and patrol_right < 0.0:
		return

	const COLOR := Color(1, 0.85, 0.2, 0.9)
	var y := 16.0
	var left := -patrol_left if patrol_left >= 0.0 else -24.0
	var right := patrol_right if patrol_right >= 0.0 else 24.0
	draw_line(Vector2(left, y), Vector2(right, y), COLOR, 1.0)
	if patrol_left >= 0.0:
		draw_line(Vector2(left, y - 8.0), Vector2(left, y + 4.0), COLOR, 1.0)
	if patrol_right >= 0.0:
		draw_line(Vector2(right, y - 8.0), Vector2(right, y + 4.0), COLOR, 1.0)
