@tool
extends CharacterBody2D

const SPEED = 30.0
const HIT_FLASH_COUNT := 3
const HIT_FLASH_ON_DURATION := 0.04
const HIT_FLASH_OFF_DURATION := 0.035
const DAMAGE_ATTACK_DELAY := 1.0
const MAX_DAMAGE_ATTACK_DELAY := 2.0
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5

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

## Tắt di chuyển ngang cho các slime chỉ đứng canh tại chỗ.
@export var movement_enabled := true
## Quay mặt về phía player khi slime đứng yên.
@export var face_player_while_stationary := false
## Bật đòn lưỡi cho devi-slime. Các slime thường vẫn dùng Killzone như trước.
@export var attack_on_detection := false
@export_range(0.1, 10.0, 0.1) var attack_cooldown := 1.25
@export_range(0.0, 3.0, 0.05) var first_attack_delay := 0.4
@export_range(1, 100, 1) var max_health := 1

const TONGUE_HIT_START_FRAME := 10
const TONGUE_HIT_END_FRAME := 10

var direction = 1
var is_dead := false
var is_attacking := false
var _player: Node2D = null
var _attack_target: Node2D = null
var _attack_cooldown_left := 0.0
var _attack_has_hit := false
var _post_attack_damage_delay := 0.0
var _damage_attack_delay_accumulated := 0.0
var _hit_flash_generation := 0
var current_health := 1

var _start_x: float = 0.0

@onready var ray_cast_right: RayCast2D = $RayCastRight
@onready var ray_cast_left: RayCast2D = $RayCastLeft
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var killzone: Area2D = get_node_or_null("Killzone") as Area2D
@onready var detection_area: Area2D = get_node_or_null("DetectionArea") as Area2D
@onready var tongue_hit_area: Area2D = get_node_or_null("TongueHitArea") as Area2D
@onready var tongue_hit_shape: CollisionShape2D = get_node_or_null(
	"TongueHitArea/CollisionShape2D"
) as CollisionShape2D
@onready var attack_sprite: AnimatedSprite2D = get_node_or_null("AttackSprite") as AnimatedSprite2D
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar") as ProgressBar

func _ready() -> void:
	_start_x = position.x
	current_health = max_health
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
		health_bar.hide()
	# Mỗi sprite cần material riêng để một con không làm các instance khác nhấp nháy.
	if animated_sprite.material:
		animated_sprite.material = animated_sprite.material.duplicate()
	if attack_sprite and attack_sprite.material:
		attack_sprite.material = attack_sprite.material.duplicate()

	if attack_on_detection and not Engine.is_editor_hint():
		_attack_cooldown_left = 0.0
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)
		attack_sprite.frame_changed.connect(_on_attack_frame_changed)
		attack_sprite.animation_finished.connect(_on_attack_animation_finished)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_dead:
		return
	if attack_on_detection:
		_physics_process_detected_attack(delta)
		return
	if not movement_enabled:
		velocity.x = 0.0
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity += get_gravity() * delta
		move_and_slide()
		if face_player_while_stationary:
			var player := _find_player()
			if player != null:
				_face_towards(player.global_position.x)
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

# Bị nhân vật chém trúng: chớp trắng vài nhịp rồi phát animation chết.
func take_damage(amount: int = 1) -> void:
	if is_dead or amount <= 0:
		return

	current_health = maxi(current_health - amount, 0)
	if health_bar:
		health_bar.value = current_health
		health_bar.show()
	if current_health == 0:
		die()
		return

	_play_hit_flash()
	if attack_on_detection:
		_delay_attack_after_damage()


func die() -> void:
	if is_dead:
		return

	is_dead = true
	velocity = Vector2.ZERO
	if health_bar:
		health_bar.hide()
	# Tắt va chạm để không còn giết được người chơi trong lúc đang tan biến
	collision_shape.set_deferred("disabled", true)
	if killzone:
		killzone.set_deferred("monitoring", false)
	if detection_area:
		detection_area.set_deferred("monitoring", false)
	if tongue_hit_area:
		tongue_hit_area.set_deferred("monitoring", false)
	if attack_sprite:
		attack_sprite.stop()
		attack_sprite.visible = false
		animated_sprite.visible = true
	_play_defeat_sound()

	await _play_hit_flash()

	if animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
		await animated_sprite.animation_finished

	queue_free()


func _play_defeat_sound() -> void:
	if Engine.is_editor_hint():
		return

	# Không gắn player âm thanh làm con của slime vì slime sẽ bị queue_free
	# sau animation chết, làm tiếng "poof" bị ngắt giữa chừng.
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEFEAT_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	# File nguồn có khoảng nửa giây yên lặng ở đầu; bỏ qua phần này để tiếng
	# vang đúng nhịp với cú chém.
	sound_player.play(DEFEAT_SOUND_OFFSET)


# Nhấp tắt/mở dứt khoát thay vì fade mượt để hợp với nhịp pixel-art 2D.
func _play_hit_flash() -> void:
	var flash_sprite: AnimatedSprite2D = animated_sprite
	if attack_sprite and attack_sprite.visible:
		flash_sprite = attack_sprite
	if not flash_sprite.material is ShaderMaterial:
		return

	var flash_material := flash_sprite.material as ShaderMaterial
	_hit_flash_generation += 1
	var flash_generation := _hit_flash_generation
	for flash_index in HIT_FLASH_COUNT:
		if flash_generation != _hit_flash_generation:
			return
		flash_material.set_shader_parameter("flash_amount", 1.0)
		await get_tree().create_timer(HIT_FLASH_ON_DURATION, false).timeout
		if flash_generation != _hit_flash_generation:
			return
		flash_material.set_shader_parameter("flash_amount", 0.0)

		if flash_index < HIT_FLASH_COUNT - 1:
			await get_tree().create_timer(HIT_FLASH_OFF_DURATION, false).timeout


# Player chạm vào slime: quay mặt về player và phát animation attack.
func on_player_touched(player: Node2D) -> void:
	if is_dead:
		return

	_face_towards(player.global_position.x)

	is_attacking = true
	velocity = Vector2.ZERO
	if animated_sprite.sprite_frames.has_animation("attack"):
		animated_sprite.play("attack")
		await animated_sprite.animation_finished


func _physics_process_detected_attack(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	move_and_slide()

	var target := _get_attack_target()
	if not is_attacking and is_instance_valid(target):
		_face_towards(target.global_position.x)
		_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
		if _attack_cooldown_left <= 0.0:
			_begin_detected_attack(target)

	if is_attacking and not _attack_has_hit \
			and attack_sprite.frame >= TONGUE_HIT_START_FRAME \
			and attack_sprite.frame <= TONGUE_HIT_END_FRAME:
		_check_tongue_hit()


func _get_attack_target() -> Node2D:
	if is_instance_valid(_attack_target) and _attack_target.is_in_group(&"player"):
		return _attack_target
	_attack_target = null
	if detection_area:
		for body in detection_area.get_overlapping_bodies():
			if body.is_in_group(&"player"):
				_attack_target = body
				return _attack_target
	return null


func _begin_detected_attack(target: Node2D) -> void:
	if not is_instance_valid(target):
		return

	_damage_attack_delay_accumulated = 0.0
	_post_attack_damage_delay = 0.0
	_face_towards(target.global_position.x)
	is_attacking = true
	_attack_has_hit = false
	animated_sprite.visible = false
	attack_sprite.visible = true
	attack_sprite.flip_h = animated_sprite.flip_h
	# Phần hình nhìn thấy trong ô 200x200 đã cùng cỡ với idle 96x96,
	# nên dùng cùng scale và điểm neo thay vì thu cả animation xuống 0.48.
	attack_sprite.position = animated_sprite.position
	attack_sprite.scale = animated_sprite.scale
	tongue_hit_area.position = Vector2(float(direction) * 50.0, -7.0)
	attack_sprite.stop()
	attack_sprite.frame = 0
	attack_sprite.play(&"attack")


func _delay_attack_after_damage() -> void:
	# Chỉ cộng tối đa 2 giây cho chu kỳ này. Khi chạm trần, các hit sau không
	# đặt lại timer; cooldown hiện tại tiếp tục đếm tới đòn kế tiếp.
	var remaining_delay := MAX_DAMAGE_ATTACK_DELAY - _damage_attack_delay_accumulated
	if remaining_delay <= 0.0:
		return
	var delay_to_add := minf(DAMAGE_ATTACK_DELAY, remaining_delay)
	_damage_attack_delay_accumulated += delay_to_add

	if is_attacking:
		_post_attack_damage_delay += delay_to_add
		return

	_attack_cooldown_left += delay_to_add


func _on_detection_body_entered(body: Node2D) -> void:
	if is_dead or not body.is_in_group(&"player"):
		return
	if not is_instance_valid(_attack_target):
		_attack_target = body
		if not is_attacking and _attack_cooldown_left <= 0.0:
			_attack_cooldown_left = first_attack_delay


func _on_detection_body_exited(body: Node2D) -> void:
	if body == _attack_target:
		_attack_target = null


func _on_attack_frame_changed() -> void:
	if not is_attacking or attack_sprite.animation != &"attack":
		return
	var tongue_is_extended := attack_sprite.frame >= TONGUE_HIT_START_FRAME \
		and attack_sprite.frame <= TONGUE_HIT_END_FRAME
	tongue_hit_shape.set_deferred("disabled", not tongue_is_extended)


func _check_tongue_hit() -> void:
	for body in tongue_hit_area.get_overlapping_bodies():
		if not body.is_in_group(&"player"):
			continue
		_attack_has_hit = true
		var game_state := get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("trigger_game_over"):
			game_state.trigger_game_over(body)
		return


func _on_attack_animation_finished() -> void:
	if not is_attacking or attack_sprite.animation != &"attack":
		return
	tongue_hit_shape.set_deferred("disabled", true)
	attack_sprite.visible = false
	animated_sprite.visible = true
	if animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.play(&"idle")
	is_attacking = false
	_attack_cooldown_left = attack_cooldown + _post_attack_damage_delay
	_post_attack_damage_delay = 0.0


func _find_player() -> Node2D:
	if not is_instance_valid(_player) or not _player.is_in_group(&"player"):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player


func _face_towards(target_x: float) -> void:
	var target_direction := signf(target_x - global_position.x)
	if target_direction == 0.0:
		return
	direction = int(target_direction)
	# Sprite mặc định quay sang trái, nên lật ngang khi mục tiêu ở bên phải.
	animated_sprite.flip_h = direction > 0


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
