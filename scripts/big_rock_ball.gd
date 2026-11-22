extends Node2D

## Bẫy cầu đá: dấu khắc trên nền chính là bàn đạp, player giẫm lên thì quả cầu
## đá rơi xuống, vỡ tan rồi nằm lại luôn trên nền.
## Đặt node ngay tâm dấu khắc, rồi kéo hai Marker2D để chỉnh đường rơi.

@export var gravity := 2500.0
@export var max_fall_speed := 1800.0
## Bật nếu muốn quả cầu đã nằm vẫn giết player khi chạm phải. Cẩn thận: quả cầu
## rộng 64px mà player chỉ nhảy cao được 52px, nên ở hành lang hẹp nó sẽ thành
## bức tường chết không đi qua được.
@export var deadly_after_landing := false

# Bán kính hình quả cầu (sprite rộng 64px).
const BALL_RADIUS := 32.0
# Màu sáng hơn thực tế vì cả bẫy bị modulate tối 0.72; nhân vào sẽ ra xám bụi.
const DUST_COLOR := Color(1.0, 0.96, 0.9, 0.9)
const PEBBLE_COLOR := Color(0.3, 0.32, 0.62)

@onready var trigger_area: Area2D = $TriggerArea
# Kéo hai Marker2D này trong editor để chỉnh đường rơi của quả cầu.
# SpawnPoint là nơi quả cầu hiện ra (đặt sát trần), LandPoint là nơi nó đáp
# xuống và nằm lại. LandPoint có sẵn một ảnh mờ hình quả cầu để canh cho dễ;
# ảnh đó tự ẩn lúc chạy game.
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var land_point: Marker2D = $LandPoint
@onready var land_preview: Sprite2D = $LandPoint/Preview
@onready var ball: Node2D = $Ball
@onready var animated_sprite: AnimatedSprite2D = $Ball/AnimatedSprite2D
@onready var hazard: Area2D = $Ball/Hazard
@onready var fall_sound: AudioStreamPlayer2D = $FallSound
@onready var impact_sound: AudioStreamPlayer2D = $ImpactSound

var _fall_speed := 0.0
var _has_triggered := false
var _has_landed := false
var _fall_trail: CPUParticles2D
var _camera_shake_tween: Tween
var _camera_base_offset := Vector2.ZERO


func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	hazard.body_entered.connect(_on_hazard_body_entered)
	land_preview.visible = false
	ball.visible = false
	hazard.monitoring = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _is_game_over():
		return

	_fall_speed = minf(_fall_speed + gravity * delta, max_fall_speed)

	var target := land_point.position
	var distance := ball.position.distance_to(target)
	ball.position = ball.position.move_toward(target, minf(_fall_speed * delta, distance))
	_update_fall_trail()
	if ball.position.is_equal_approx(target):
		_land()


func _on_trigger_body_entered(body: Node2D) -> void:
	if _has_triggered or not body.is_in_group(&"player"):
		return

	_has_triggered = true
	trigger_area.set_deferred("monitoring", false)

	ball.position = spawn_point.position
	ball.visible = true
	animated_sprite.play(&"fall")
	hazard.set_deferred("monitoring", true)
	fall_sound.play()
	_play_ceiling_crack()
	_start_fall_trail()
	set_physics_process(true)


func _on_hazard_body_entered(body: Node2D) -> void:
	# Đã đáp đất thì hết sát thương ngay, không chờ animation vỡ chạy xong.
	# monitoring chỉ tắt được bằng set_deferred nên vẫn còn một frame Area2D
	# tiếp tục bắn signal; cờ này chặn nốt frame đó.
	if _has_landed and not deadly_after_landing:
		return

	if body.is_in_group(&"player"):
		var game_state := get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("trigger_game_over"):
			game_state.trigger_game_over(body)


# Đập xong thì quả cầu nằm lại luôn trên nền, không biến mất. Animation "impact"
# không lặp nên nó dừng ở khung cuối (quả cầu đã tan bụi) và giữ nguyên khung đó.
func _land() -> void:
	set_physics_process(false)
	_fall_speed = 0.0
	_has_landed = true
	impact_sound.play()
	animated_sprite.play(&"impact")
	_stop_fall_trail()
	_play_impact_dust()

	if not deadly_after_landing:
		hazard.set_deferred("monitoring", false)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()


# ---------------------------------------------------------------------------
# Hiệu ứng bụi rơi. Chỉ là hạt và rung camera, không đổi đường rơi, tốc độ rơi,
# animation hay thời điểm Hazard bật/tắt.
# ---------------------------------------------------------------------------

# Trần nứt khi bẫy kích hoạt: một mảng bụi + sỏi bung ra ngay chỗ quả cầu xuất hiện.
func _play_ceiling_crack() -> void:
	_shake_camera(2.0, 0.25)
	var ceiling := spawn_point.position + Vector2(0, -BALL_RADIUS)
	var puff := _make_dust(8, 0.7)
	puff.position = ceiling
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	puff.emission_rect_extents = Vector2(BALL_RADIUS * 0.8, 2.0)
	puff.direction = Vector2(0, 1)
	puff.spread = 70.0
	puff.initial_velocity_min = 20.0
	puff.initial_velocity_max = 70.0
	puff.damping_min = 40.0
	puff.damping_max = 80.0
	puff.gravity = Vector2(0, 40)
	puff.finished.connect(puff.queue_free)
	puff.emitting = true
	_burst_pebbles(ceiling, 10, Vector2(0, 1), 40.0, 60.0)
	# Bụi mịn tiếp tục lả tả rơi từ chỗ trần vừa nứt.
	_spawn_dust_shower(spawn_point.position.x, BALL_RADIUS, 0.4, 6.0)


# Vệt bụi bám theo quả cầu khi rơi. Hạt dùng toạ độ thế giới nên đọng lại
# phía sau thành vệt khi emitter đi theo quả cầu.
func _start_fall_trail() -> void:
	# Quả cầu rơi rất nhanh (~0.45s) nên cần mật độ hạt cao mới thành vệt rõ.
	_fall_trail = _make_dust(40, 0.5)
	_fall_trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_fall_trail.emission_rect_extents = Vector2(BALL_RADIUS * 0.7, 6.0)
	_fall_trail.direction = Vector2(0, -1)
	_fall_trail.spread = 40.0
	_fall_trail.initial_velocity_min = 10.0
	_fall_trail.initial_velocity_max = 35.0
	_fall_trail.damping_min = 30.0
	_fall_trail.damping_max = 60.0
	_fall_trail.scale_amount_min = 1.2
	_fall_trail.scale_amount_max = 2.0
	_update_fall_trail()
	_fall_trail.emitting = true


func _update_fall_trail() -> void:
	if is_instance_valid(_fall_trail):
		_fall_trail.position = ball.position + Vector2(0, -BALL_RADIUS * 0.5)


func _stop_fall_trail() -> void:
	if is_instance_valid(_fall_trail):
		_stop_particles_later(_fall_trail, 0.0)
	_fall_trail = null


# Cú đập: đám bụi cuộn sát nền tràn ra hai bên, đá vụn văng lên, camera rung
# mạnh, rồi bụi trên trần bị chấn động tiếp tục rơi lả tả xuống một lúc.
func _play_impact_dust() -> void:
	_shake_camera(6.0, 0.35)
	var floor_point := Vector2(ball.position.x, _floor_y() - 4.0)
	for side in [-1.0, 1.0]:
		var cloud := _make_dust(9, 0.7)
		cloud.position = floor_point + Vector2(side * BALL_RADIUS * 0.6, 0)
		cloud.one_shot = true
		cloud.explosiveness = 1.0
		cloud.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		cloud.emission_rect_extents = Vector2(6.0, 3.0)
		cloud.direction = Vector2(side, -0.35)
		cloud.spread = 20.0
		cloud.initial_velocity_min = 60.0
		cloud.initial_velocity_max = 150.0
		cloud.damping_min = 120.0
		cloud.damping_max = 200.0
		cloud.gravity = Vector2(0, -15)
		cloud.scale_amount_min = 1.2
		cloud.scale_amount_max = 2.2
		cloud.finished.connect(cloud.queue_free)
		cloud.emitting = true
	_burst_pebbles(floor_point, 14, Vector2(0, -1), 70.0, 130.0)
	_spawn_dust_shower(ball.position.x, BALL_RADIUS * 2.0, 0.6, 10.0)


# Bụi mịn rơi chậm từ trần (cao độ SpawnPoint) xuống. Tuổi thọ hạt tính theo
# khoảng cách tới mặt nền để bụi tan đúng lúc chạm sàn, không vẽ xuyên qua đất.
# `rate` là số hạt sinh ra mỗi giây (CPUParticles2D tính amount = rate × lifetime).
func _spawn_dust_shower(x: float, half_width: float, duration: float, rate: float) -> void:
	var top := spawn_point.position.y - BALL_RADIUS
	var drop := maxf(_floor_y() - top, 32.0)
	# Rơi đủ nhanh để bụi trôi hết trong ~2s, không lơ lửng quá lâu.
	var speed := 140.0
	# Hạt nhanh nhất đi đúng `drop` trong một đời hạt, nên không hạt nào lố qua nền.
	var lifetime := drop / speed
	var shower := _make_dust(maxi(4, ceili(rate * lifetime)), lifetime)
	shower.position = Vector2(x, top)
	shower.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	shower.emission_rect_extents = Vector2(half_width, 2.0)
	shower.direction = Vector2(0, 1)
	shower.spread = 12.0
	shower.initial_velocity_min = speed * 0.75
	shower.initial_velocity_max = speed
	shower.scale_amount_min = 0.6
	shower.scale_amount_max = 1.1
	shower.emitting = true
	_stop_particles_later(shower, duration)


func _burst_pebbles(at: Vector2, amount: int, direction: Vector2, spread: float, speed: float) -> void:
	var pebbles := CPUParticles2D.new()
	pebbles.amount = amount
	pebbles.lifetime = 0.7
	pebbles.one_shot = true
	pebbles.explosiveness = 1.0
	pebbles.position = at
	pebbles.direction = direction
	pebbles.spread = spread
	pebbles.initial_velocity_min = speed * 0.4
	pebbles.initial_velocity_max = speed
	pebbles.gravity = Vector2(0, 900)
	pebbles.angular_velocity_min = -540.0
	pebbles.angular_velocity_max = 540.0
	pebbles.scale_amount_min = 2.0
	pebbles.scale_amount_max = 4.0
	pebbles.color_ramp = _fade_ramp(PEBBLE_COLOR)
	pebbles.light_mask = 0
	pebbles.z_index = 1
	add_child(pebbles)
	pebbles.finished.connect(pebbles.queue_free)
	pebbles.emitting = true


func _make_dust(amount: int, lifetime: float) -> CPUParticles2D:
	var dust := CPUParticles2D.new()
	dust.amount = amount
	dust.lifetime = lifetime
	dust.emitting = false
	dust.texture = _get_dust_texture()
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 1.6
	dust.angle_min = 0.0
	dust.angle_max = 360.0
	# Bụi phình ra theo thời gian như đám khói tan dần.
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.2))
	dust.scale_amount_curve = grow
	dust.color_ramp = _fade_ramp(DUST_COLOR)
	dust.light_mask = 0
	dust.z_index = 1
	add_child(dust)
	return dust


# Hiện nhanh, giữ đậm một lúc, rồi mờ dần về cuối đời hạt.
func _fade_ramp(color: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(color, 0.0), color, color, Color(color, 0.0)])
	return ramp


# Texture hạt bụi tròn tạo bằng code (không cần thêm file ảnh). Gradient dạng
# bậc thang (INTERPOLATE_CONSTANT) cho mép cứng từng vòng, hợp phong cách pixel art.
static var _dust_texture: GradientTexture2D

func _get_dust_texture() -> GradientTexture2D:
	if _dust_texture != null:
		return _dust_texture
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 0.8])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	_dust_texture = GradientTexture2D.new()
	_dust_texture.gradient = gradient
	_dust_texture.width = 10
	_dust_texture.height = 10
	_dust_texture.fill = GradientTexture2D.FILL_RADIAL
	_dust_texture.fill_from = Vector2(0.5, 0.5)
	_dust_texture.fill_to = Vector2(1.0, 0.5)
	return _dust_texture


func _floor_y() -> float:
	return land_point.position.y + BALL_RADIUS


func _stop_particles_later(particles: CPUParticles2D, emit_time: float) -> void:
	if emit_time > 0.0:
		await get_tree().create_timer(emit_time).timeout
	if not is_instance_valid(particles):
		return
	particles.emitting = false
	await get_tree().create_timer(particles.lifetime + 0.1).timeout
	if is_instance_valid(particles):
		particles.queue_free()


func _shake_camera(strength: float, duration: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	# Cú rung trước chưa xong thì trả offset về gốc trước, tránh lấy offset đang
	# lệch làm gốc mới.
	if _camera_shake_tween != null and _camera_shake_tween.is_valid():
		_camera_shake_tween.kill()
		camera.offset = _camera_base_offset
	_camera_base_offset = camera.offset
	var base_offset := _camera_base_offset
	# t giảm từ 1 về 0: rung mạnh lúc đầu rồi tắt dần, kết thúc đúng offset gốc.
	var apply_shake := func(t: float) -> void:
		if is_instance_valid(camera):
			var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			camera.offset = base_offset + jitter * strength * t
	_camera_shake_tween = create_tween()
	_camera_shake_tween.tween_method(apply_shake, 1.0, 0.0, duration)
