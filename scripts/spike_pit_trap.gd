extends Node2D

const PIT_DEPTH := 128.0
const PIT_WIDTH := 64.0
# Cho phép player chạm mép tường một chút vẫn tính là bị kẹp.
const CRUSH_TOLERANCE := 2.0

@export var tile_map_path: NodePath = ^"../TileMap32"
## Thời gian hai tường gai trượt từ trong vách ra khép kín miệng hố. Tường bắt
## đầu khép ngay khi bẫy kích hoạt, cùng lúc với sàn giả sụp xuống.
@export_range(0.1, 10.0, 0.1, "or_greater") var spike_close_duration := 2.0

@onready var ground_collision: CollisionShape2D = $FakeGround/CollisionShape2D
@onready var trigger_area: Area2D = $FakeGround/TriggerArea
@onready var ground_sprite: Sprite2D = $FakeGround/GroundSprite
@onready var left_wall: Area2D = $LeftWall
@onready var right_wall: Area2D = $RightWall
@onready var left_wall_solid_collision: CollisionShape2D = $LeftWall/SolidWall/CollisionShape2D
@onready var right_wall_solid_collision: CollisionShape2D = $RightWall/SolidWall/CollisionShape2D
@onready var activation_sound: AudioStreamPlayer2D = $ActivationSound
@onready var grind_sound: AudioStreamPlayer2D = $GrindSound
@onready var slam_sound: AudioStreamPlayer2D = $SlamSound
@onready var left_wall_sprite: Sprite2D = $LeftWall/Sprite2D
@onready var right_wall_sprite: Sprite2D = $RightWall/Sprite2D

const LANDING_DUST_SCENE := preload("res://nodes/effects/landing_dust.tscn")
# Màu gạch của sàn giả (lấy từ trap-map-1.png) cho mảnh vỡ trông cùng chất liệu.
const DEBRIS_COLOR := Color(0.2, 0.22, 0.55)
const DUST_COLOR := Color(0.62, 0.58, 0.52)
## Biên độ rung (px) của sprite tường gai khi đang nghiến vào nhau. Chỉ là hiệu
## ứng hình ảnh trên Sprite2D, không đụng tới vị trí Area2D nên hitbox giữ nguyên.
@export var wall_rumble_amount := 1.0

var _walls_rumbling := false
var _camera_shake_tween: Tween
var _camera_base_offset := Vector2.ZERO
var _falling_dust: CPUParticles2D

var _triggered := false
var _game_over_started := false
var _spike_walls_closing := false
var _crush_check_in_progress := false
var _trapped_player: CharacterBody2D


func _ready() -> void:
	left_wall.body_entered.connect(_on_spike_wall_body_entered)
	right_wall.body_entered.connect(_on_spike_wall_body_entered)


# Rung sprite tường gai mỗi frame vẽ (không phải physics) để chuyển động mượt;
# làm tròn về pixel nguyên cho hợp pixel art.
func _process(_delta: float) -> void:
	if not _walls_rumbling:
		return
	var amount := wall_rumble_amount
	left_wall_sprite.offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount) * 0.5).round()
	right_wall_sprite.offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount) * 0.5).round()


func _physics_process(_delta: float) -> void:
	if _triggered:
		if not is_instance_valid(_trapped_player):
			return
		if _spike_walls_closing and _is_player_crushed(_trapped_player):
			call_deferred("_crush_player", _trapped_player)
		return
	for body in trigger_area.get_overlapping_bodies():
		if not (body is CharacterBody2D) or not body.is_in_group(&"player"):
			continue
		var player := body as CharacterBody2D
		if _is_standing_on_fake_floor(player):
			_activate_for_player(player)
			return


func _is_standing_on_fake_floor(player: CharacterBody2D) -> bool:
	if not player.is_on_floor():
		return false
	var player_position := _get_player_body_center(player)
	return absf(player_position.x) <= PIT_WIDTH * 0.5 - 20.0 and player_position.y < 0.0


func _activate_for_player(player: CharacterBody2D) -> void:
	_triggered = true
	activation_sound.play()
	_trapped_player = player
	left_wall.show()
	right_wall.show()
	trigger_area.set_deferred("monitoring", false)
	ground_collision.set_deferred("disabled", true)
	call_deferred("_clear_floor_tiles")

	# Tường gai khép ngay lập tức, không đợi player rơi chạm đáy: player chỉ còn
	# khoảng thời gian tường trượt tới miệng hố để thoát ra.
	_drop_fake_ground()
	_close_spike_walls()


func _clear_floor_tiles() -> void:
	var tile_map := get_node_or_null(tile_map_path) as TileMap
	if tile_map == null:
		return
	var tile_size := tile_map.tile_set.tile_size
	var top_left := global_position + Vector2(-PIT_WIDTH * 0.5 + 1.0, 1.0)
	var first_cell := tile_map.local_to_map(tile_map.to_local(top_left))
	var columns := ceili(PIT_WIDTH / float(tile_size.x))
	var rows := ceili(PIT_DEPTH / float(tile_size.y))
	for layer in range(tile_map.get_layers_count()):
		for column in range(columns):
			# Xóa thêm hàng ngay trên miệng hố để bỏ phần viền trang trí của map.
			for row in range(-1, rows):
				tile_map.erase_cell(layer, first_cell + Vector2i(column, row))


func _drop_fake_ground() -> void:
	# Sàn vỡ: chớp sáng một nhịp, văng mảnh gạch + bụi ở hai mép, rung camera nhẹ
	# để player cảm nhận được "cú sụp" ngay khi bước lên.
	_spawn_floor_debris()
	_spawn_dust_puff(Vector2(-PIT_WIDTH * 0.5 + 4.0, -14.0), false)
	_spawn_dust_puff(Vector2(PIT_WIDTH * 0.5 - 4.0, -14.0), true)
	_shake_camera(2.5, 0.2)
	ground_sprite.self_modulate = Color(1.8, 1.8, 1.8)

	var flash := create_tween()
	flash.tween_property(ground_sprite, "self_modulate", Color.WHITE, 0.12)

	# Thời gian rơi giữ nguyên 0.4s như cũ; thêm nghiêng và mờ dần cho đỡ cứng.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(ground_sprite, "position:y", 64.0 + PIT_DEPTH, 0.4)
	tween.tween_property(ground_sprite, "rotation", randf_range(0.08, 0.16) * (1.0 if randf() < 0.5 else -1.0), 0.4)
	tween.tween_property(ground_sprite, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	if not is_inside_tree():
		return
	ground_sprite.hide()


func _close_spike_walls() -> void:
	if not is_inside_tree():
		return
	left_wall.set_deferred("monitoring", true)
	right_wall.set_deferred("monitoring", true)
	# Tắt va chạm cứng của tường gai khi khép lại: nếu không, StaticBody sẽ đẩy
	# player ra ngoài (thường là đẩy lên đứng trên nóc tường) và player không chết.
	left_wall_solid_collision.set_deferred("disabled", true)
	right_wall_solid_collision.set_deferred("disabled", true)
	_spike_walls_closing = true
	_start_closing_effects()
	# Tween vị trí Area2D giữ nguyên như cũ (SINE in-out, cùng thời lượng): hitbox
	# và logic kẹp không đổi. Mọi hiệu ứng thêm vào chỉ tác động lên Sprite2D,
	# camera, hạt bụi và âm thanh.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(left_wall, "position:x", -12.0, spike_close_duration)
	tween.tween_property(right_wall, "position:x", 12.0, spike_close_duration)
	await tween.finished
	if not is_inside_tree():
		return
	_play_slam_effects()
	if _is_player_crushed(_trapped_player):
		await _crush_player(_trapped_player)
	# Chờ lượt kiểm tra kẹp đang chạy (vd. player đang bất tử tạm thời) kết thúc.
	while _crush_check_in_progress and is_inside_tree():
		await get_tree().physics_frame
	if not is_inside_tree() or _game_over_started:
		return
	# Tường đã khép xong mà player không bị kẹp: ngừng gây sát thương và bật lại
	# va chạm cứng để player có thể đứng lên trên tường gai.
	_spike_walls_closing = false
	left_wall.set_deferred("monitoring", false)
	right_wall.set_deferred("monitoring", false)
	left_wall_solid_collision.set_deferred("disabled", false)
	right_wall_solid_collision.set_deferred("disabled", false)


func _on_spike_wall_body_entered(body: Node2D) -> void:
	if not _triggered or _game_over_started or not (body is CharacterBody2D):
		return
	var player := body as CharacterBody2D
	if not body.is_in_group(&"player"):
		return
	if _can_crush_player(player):
		await _crush_player(player)


func _get_player_body_center(player: CharacterBody2D) -> Vector2:
	var collision_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var center_global := player.global_position
	if collision_shape != null and not collision_shape.disabled:
		center_global = collision_shape.global_position
	return to_local(center_global)


func _are_both_walls_touching_player(body: Node2D) -> bool:
	return is_instance_valid(body) \
		and left_wall.overlaps_body(body) \
		and right_wall.overlaps_body(body)


func _get_shape_half_width(collision_shape: CollisionShape2D) -> float:
	if collision_shape == null or collision_shape.shape == null:
		return 0.0
	return collision_shape.shape.get_rect().size.x * 0.5 * absf(collision_shape.global_scale.x)


# Kiểm tra bằng hình học thay vì chỉ dựa vào Area overlap (dễ trượt khi player
# bị physics đẩy ra khỏi tường): player còn nằm trong lòng hố và khe hở giữa hai
# tường gai đã hẹp hơn thân player.
func _is_player_crushed(body: Node2D) -> bool:
	if not is_instance_valid(body) or not (body is CharacterBody2D):
		return false
	if _are_both_walls_touching_player(body):
		return true
	var player := body as CharacterBody2D
	var player_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var player_half_width := _get_shape_half_width(player_shape)
	var center := _get_player_body_center(player)
	if absf(center.x) > PIT_WIDTH * 0.5:
		return false
	if center.y < 0.0 or center.y > PIT_DEPTH + 16.0:
		return false
	var wall_half_width := _get_shape_half_width($LeftWall/CollisionShape2D as CollisionShape2D)
	var left_inner := left_wall.position.x + wall_half_width
	var right_inner := right_wall.position.x - wall_half_width
	return right_inner - left_inner <= player_half_width * 2.0 + CRUSH_TOLERANCE


func _can_crush_player(body: Node2D) -> bool:
	return _spike_walls_closing \
		and not _game_over_started \
		and is_instance_valid(body) \
		and body == _trapped_player \
		and body is CharacterBody2D \
		and body.is_in_group(&"player") \
		and _is_player_crushed(body)


func _crush_player(body: Node2D) -> void:
	if _crush_check_in_progress or not _can_crush_player(body):
		return
	_crush_check_in_progress = true
	while is_instance_valid(body) and body.has_method("is_invulnerable") and body.is_invulnerable():
		if not is_inside_tree() or not _can_crush_player(body):
			_crush_check_in_progress = false
			return
		await get_tree().physics_frame
		if not is_inside_tree():
			_crush_check_in_progress = false
			return
	if not _can_crush_player(body):
		_crush_check_in_progress = false
		return
	_game_over_started = true
	_crush_check_in_progress = false
	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("trigger_game_over"):
		await game_state.trigger_game_over(body)


# ---------------------------------------------------------------------------
# Hiệu ứng hình ảnh / âm thanh. Không hàm nào dưới đây đụng tới collision,
# monitoring hay vị trí Area2D, nên thời điểm gây sát thương không đổi.
# ---------------------------------------------------------------------------

func _start_closing_effects() -> void:
	_walls_rumbling = true
	grind_sound.play()
	# Gai lóe đỏ hai nhịp lúc bắt đầu trồi ra, báo cho player biết phải thoát ngay.
	for sprite in [left_wall_sprite, right_wall_sprite]:
		var pulse := create_tween()
		pulse.set_loops(2)
		pulse.tween_property(sprite, "self_modulate", Color(1.7, 0.55, 0.5), 0.12)
		pulse.tween_property(sprite, "self_modulate", Color.WHITE, 0.22)
	# Đất cát lả tả rơi từ miệng hố trong lúc tường nghiến vào.
	_falling_dust = _make_particles(22, 1.0, DUST_COLOR)
	_falling_dust.position = Vector2(0, 2)
	_falling_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_falling_dust.emission_rect_extents = Vector2(PIT_WIDTH * 0.5 - 2.0, 2.0)
	_falling_dust.direction = Vector2(0, 1)
	_falling_dust.spread = 12.0
	_falling_dust.initial_velocity_min = 5.0
	_falling_dust.initial_velocity_max = 20.0
	_falling_dust.gravity = Vector2(0, 260)
	_falling_dust.scale_amount_min = 1.0
	_falling_dust.scale_amount_max = 2.0
	_falling_dust.emitting = true


func _play_slam_effects() -> void:
	_walls_rumbling = false
	left_wall_sprite.offset = Vector2.ZERO
	right_wall_sprite.offset = Vector2.ZERO
	_stop_grind_sound()
	slam_sound.play()
	_shake_camera(5.0, 0.3)

	if is_instance_valid(_falling_dust):
		var dust := _falling_dust
		_falling_dust = null
		dust.emitting = false
		get_tree().create_timer(dust.lifetime + 0.1).timeout.connect(dust.queue_free)

	# Cú đập: sprite lố vào trong vài px rồi nảy về (TRANS_BACK), kèm chớp trắng.
	# Chỉ dịch offset của Sprite2D nên hitbox vẫn đứng yên ở vị trí đã khép.
	for data in [[left_wall_sprite, 4.0], [right_wall_sprite, -4.0]]:
		var sprite: Sprite2D = data[0]
		var overshoot: float = data[1]
		sprite.self_modulate = Color(2.0, 2.0, 2.0)
		var bounce := create_tween()
		bounce.tween_property(sprite, "offset:x", overshoot, 0.05) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		bounce.tween_property(sprite, "offset:x", 0.0, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		bounce.parallel().tween_property(sprite, "self_modulate", Color.WHITE, 0.2)

	_spawn_dust_puff(Vector2(-12.0, -14.0), false)
	_spawn_dust_puff(Vector2(12.0, -14.0), true)
	var burst := _make_particles(20, 0.6, DUST_COLOR)
	burst.position = Vector2(0, PIT_DEPTH * 0.5)
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = Vector2(2.0, PIT_DEPTH * 0.45)
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 100.0
	burst.damping_min = 60.0
	burst.damping_max = 120.0
	burst.gravity = Vector2(0, 200)
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 3.0
	burst.finished.connect(burst.queue_free)
	burst.emitting = true


func _stop_grind_sound() -> void:
	if not grind_sound.playing:
		return
	var base_volume := grind_sound.volume_db
	var fade := create_tween()
	fade.tween_property(grind_sound, "volume_db", -40.0, 0.15)
	fade.tween_callback(grind_sound.stop)
	fade.tween_property(grind_sound, "volume_db", base_volume, 0.0)


func _spawn_floor_debris() -> void:
	# Mảnh gạch bật lên rồi rơi xuống lòng hố.
	var debris := _make_particles(16, 0.9, DEBRIS_COLOR)
	debris.position = Vector2(0, 4)
	debris.one_shot = true
	debris.explosiveness = 0.85
	debris.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	debris.emission_rect_extents = Vector2(PIT_WIDTH * 0.5 - 4.0, 3.0)
	debris.direction = Vector2(0, -1)
	debris.spread = 60.0
	debris.initial_velocity_min = 30.0
	debris.initial_velocity_max = 90.0
	debris.gravity = Vector2(0, 700)
	debris.angular_velocity_min = -360.0
	debris.angular_velocity_max = 360.0
	debris.scale_amount_min = 2.0
	debris.scale_amount_max = 4.0
	debris.finished.connect(debris.queue_free)
	debris.emitting = true


func _make_particles(amount: int, lifetime: float, color: Color) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = false
	particles.light_mask = 0
	particles.z_index = 1
	# Mờ dần về cuối đời hạt thay vì biến mất đột ngột.
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	particles.color_ramp = ramp
	add_child(particles)
	return particles


func _spawn_dust_puff(local_position: Vector2, flip: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var dust: AnimatedSprite2D = LANDING_DUST_SCENE.instantiate()
	dust.flip_h = flip
	scene.add_child(dust)
	dust.global_position = to_global(local_position)


func _shake_camera(strength: float, duration: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	# Nếu cú rung trước chưa xong thì trả offset về gốc rồi rung lại từ đầu, tránh
	# lấy nhầm offset đang lệch làm gốc mới.
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
