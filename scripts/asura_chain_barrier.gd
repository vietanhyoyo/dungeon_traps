@tool
extends StaticBody2D
class_name AsuraChainBarrier
## Sợi xích căng từ trần xuống sàn, chặn đường đi của người chơi.
##
## Chỉ đòn chém của Asura mới chém đứt được (asura_controller gọi cut_by_asura).
## Tên của Serelyn chỉ va vào xích, bật tia lửa rồi rơi, xích không hề hấn gì.
##
## Đặt node ở mép trần, chỉnh `length` trong Inspector cho bằng chiều cao từ trần
## tới sàn: mắt xích, móc neo dưới và khung va chạm tự dựng lại ngay trong editor.

signal cut

const LINK_TEXTURE: Texture2D = preload("res://assets/sprites/traps/pendulum_chain_links.png")
const ANCHOR_TEXTURE: Texture2D = preload("res://assets/sprites/traps/pendulum_anchor.png")
const DUST_SCENE: PackedScene = preload("res://nodes/effects/landing_dust.tscn")
## Hai kiểu mắt xích (chính diện / nghiêng) nằm cạnh nhau trong cùng texture.
const LINK_REGIONS: Array[Rect2] = [Rect2(0, 0, 12, 18), Rect2(12, 0, 12, 18)]
const LINK_HEIGHT := 18.0
## Mắt xích sau móc vào mắt trước, nên mỗi mắt chỉ chiếm 12px chiều dài xích.
const LINK_PITCH := 12.0
const ANCHOR_HEIGHT := 14.0
## Khoen của móc neo nằm sát đáy sprite, xích bắt đầu từ đó.
const ANCHOR_RING_OFFSET := 10.0
const COLLISION_WIDTH := 12.0
const MIN_LENGTH := 48.0

const GLINT_DURATION := 0.7
const GLINT_BRIGHTNESS := 0.75
const SHAKE_DURATION := 0.45
const SHAKE_AMPLITUDE := 3.0
const DAMAGE_TINT := Color(1.5, 0.75, 0.5, 1.0)
const DEBRIS_GRAVITY := 980.0
const DEBRIS_LIFETIME := 0.9
const PILE_BOUNCE := 0.3
const PILE_FRICTION := 6.0
const SWING_FREQUENCY := 8.5
const SWING_DAMPING := 1.6

## Chiều dài xích (px) tính từ gốc node (mép trần) xuống. Đặt bằng chiều cao
## khoảng trống cần chặn, ví dụ 8 ô 32px = 256.
@export_range(MIN_LENGTH, 2048.0, 1.0, "or_greater", "suffix:px") var length := 256.0:
	set(value):
		length = maxf(value, MIN_LENGTH)
		_rebuild()
## Móc neo trên trần.
@export var top_anchor := true:
	set(value):
		top_anchor = value
		_rebuild()
## Móc neo dưới sàn. Tắt nếu muốn xích chỉ thả từ trần xuống chạm đất.
@export var bottom_anchor := true:
	set(value):
		bottom_anchor = value
		_rebuild()
## Số nhát chém của Asura cần để đứt xích. Các nhát trước chỉ làm xích rung
## và mắt xích trúng đòn đỏ lên.
@export_range(1, 5) var hits_to_cut := 1

@export_group("Animation")
## Chu kỳ (giây) của vệt sáng chạy dọc sợi xích lúc đứng yên. 0 = tắt.
@export_range(0.0, 10.0, 0.1, "suffix:s") var glint_interval := 2.8
## Độ văng (radian) của đoạn xích còn treo trên trần sau khi bị chém đứt.
@export_range(0.0, 1.5, 0.01) var swing_strength := 0.5

@onready var spark: AnimatedSprite2D = $Spark
@onready var spark_particles: CPUParticles2D = $SparkParticles
@onready var clank_sound: AudioStreamPlayer2D = $ClankSound
@onready var snap_sound: AudioStreamPlayer2D = $SnapSound
@onready var rattle_sound: AudioStreamPlayer2D = $RattleSound

var _links: Array[Sprite2D] = []
var _links_root: Node2D
var _top_anchor_sprite: Sprite2D
var _bottom_anchor_sprite: Sprite2D
var _collision: CollisionShape2D
var _chain_start := 0.0
var _chain_end := 0.0

var _hits_left := 1
var _is_cut := false
var _time := 0.0
var _glint_timer := 0.0
var _glint_t := -1.0
var _shake_t := -1.0
var _shake_index := 0
var _damaged_index := -1

# Sau khi đứt: đoạn trên treo vào _upper_pivot và đung đưa tắt dần, đoạn dưới
# cùng hai nửa mắt xích bị chém thành mảnh vụn rơi theo trọng lực.
var _upper_pivot: Node2D
var _swing_t := -1.0
var _swing_dir := 1.0
var _debris: Array[Dictionary] = []
var _pile_landed := false


func _ready() -> void:
	_hits_left = hits_to_cut
	_rebuild()
	if Engine.is_editor_hint():
		return
	add_to_group(&"asura_cuttable")
	spark.visible = false
	spark.animation_finished.connect(_on_spark_finished)
	# Lệch pha để nhiều sợi xích trong màn không loé sáng cùng lúc.
	_glint_timer = randf() * glint_interval


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	if _is_cut:
		_update_swing(delta)
		_update_debris(delta)
		return
	_update_glint(delta)
	_update_shake(delta)
	_apply_link_visuals()


# --- Dựng sợi xích ------------------------------------------------------------

func _rebuild() -> void:
	if not is_inside_tree() or _is_cut:
		return

	if _links_root == null:
		_links_root = Node2D.new()
		_links_root.name = "Links"
		add_child(_links_root, false, Node.INTERNAL_MODE_FRONT)
	if _collision == null:
		_collision = CollisionShape2D.new()
		_collision.name = "CollisionShape2D"
		_collision.shape = RectangleShape2D.new()
		add_child(_collision, false, Node.INTERNAL_MODE_FRONT)

	_top_anchor_sprite = _sync_anchor(_top_anchor_sprite, top_anchor, "TopAnchor")
	_bottom_anchor_sprite = _sync_anchor(_bottom_anchor_sprite, bottom_anchor, "BottomAnchor")

	_chain_start = ANCHOR_RING_OFFSET if top_anchor else 0.0
	_chain_end = length - ANCHOR_RING_OFFSET if bottom_anchor else length
	if _top_anchor_sprite:
		_top_anchor_sprite.position = Vector2(0.0, ANCHOR_HEIGHT * 0.5)
	if _bottom_anchor_sprite:
		_bottom_anchor_sprite.position = Vector2(0.0, length - ANCHOR_HEIGHT * 0.5)
		_bottom_anchor_sprite.flip_v = true

	var count := maxi(1, roundi((_chain_end - _chain_start) / LINK_PITCH))
	while _links.size() < count:
		var link := Sprite2D.new()
		link.texture = LINK_TEXTURE
		link.region_enabled = true
		_links_root.add_child(link)
		_links.append(link)
	while _links.size() > count:
		var extra: Sprite2D = _links.pop_back()
		extra.queue_free()

	# Dàn đều số mắt xích để mắt đầu và mắt cuối móc đúng vào hai khoen neo.
	var pitch := (_chain_end - _chain_start) / float(count)
	for i in count:
		var link := _links[i]
		link.region_rect = LINK_REGIONS[i % 2]
		link.position = Vector2(0.0, _chain_start + pitch * (i + 0.5))
		link.rotation = 0.0
		link.self_modulate = Color.WHITE

	var rect := _collision.shape as RectangleShape2D
	rect.size = Vector2(COLLISION_WIDTH, length)
	_collision.position = Vector2(0.0, length * 0.5)


func _sync_anchor(sprite: Sprite2D, wanted: bool, node_name: String) -> Sprite2D:
	if not wanted:
		if sprite:
			sprite.queue_free()
		return null
	if sprite:
		return sprite
	var anchor := Sprite2D.new()
	anchor.name = node_name
	anchor.texture = ANCHOR_TEXTURE
	# Vẽ móc neo đè lên mắt xích đầu/cuối để khoen nhìn như đang giữ xích.
	anchor.z_index = 1
	add_child(anchor, false, Node.INTERNAL_MODE_FRONT)
	return anchor


# --- Hiệu ứng lúc còn nguyên ---------------------------------------------------

func _update_glint(delta: float) -> void:
	if glint_interval <= 0.0:
		return
	if _glint_t >= 0.0:
		_glint_t += delta
		if _glint_t >= GLINT_DURATION:
			_glint_t = -1.0
		return
	_glint_timer -= delta
	if _glint_timer <= 0.0:
		_glint_timer = glint_interval
		_glint_t = 0.0


func _update_shake(delta: float) -> void:
	if _shake_t < 0.0:
		return
	_shake_t += delta
	if _shake_t >= SHAKE_DURATION:
		_shake_t = -1.0


func _apply_link_visuals() -> void:
	var count := _links.size()
	var glint_pos := -100.0
	if _glint_t >= 0.0:
		# Vệt sáng chạy từ trên xuống, ra khỏi hai đầu một chút cho mượt.
		glint_pos = lerpf(-2.0, count + 2.0, _glint_t / GLINT_DURATION)

	var shake_amount := 0.0
	if _shake_t >= 0.0:
		shake_amount = SHAKE_AMPLITUDE * (1.0 - _shake_t / SHAKE_DURATION)

	for i in count:
		var link := _links[i]
		var color := Color.WHITE
		if i == _damaged_index:
			color = DAMAGE_TINT
		var glint := clampf(1.0 - absf(i - glint_pos) / 1.5, 0.0, 1.0)
		if glint > 0.0:
			color = color.lightened(glint * GLINT_BRIGHTNESS)
		link.self_modulate = color

		var x := 0.0
		if shake_amount > 0.0:
			# Hai đầu bị neo nên đứng yên, giữa xích và chỗ trúng đòn rung mạnh nhất.
			var pinned := sin(PI * (i + 0.5) / count)
			var near_hit := exp(-pow((i - _shake_index) / 4.0, 2.0))
			x = sin(_time * 70.0 + i * 0.9) * shake_amount * pinned * (0.4 + 0.6 * near_hit)
		link.position.x = x


# --- Bị tấn công ----------------------------------------------------------------

## Asura chém trúng xích. Trả về vị trí (global) của mắt xích trúng đòn để
## Asura đặt hiệu ứng chém vào đúng chỗ.
func cut_by_asura(attacker_position: Vector2, facing: float) -> Vector2:
	var index := _link_index_at(attacker_position)
	var hit_point := _link_global_position(index)
	if _is_cut:
		return hit_point

	_hits_left -= 1
	if _hits_left > 0:
		_damaged_index = index
		_clank(index, 1.0)
		return hit_point

	_break_at(index, signf(facing) if facing != 0.0 else 1.0)
	return hit_point


## Tên (hoặc vật khác) va vào xích: chỉ toé lửa và rung, không đứt được.
func deflect_hit(hit_position: Vector2) -> void:
	if _is_cut:
		return
	_clank(_link_index_at(hit_position), 1.25)


func _clank(index: int, pitch: float) -> void:
	_shake_t = 0.0
	_shake_index = index
	_play_spark(_link_global_position(index), 1.0, 8)
	clank_sound.pitch_scale = pitch * randf_range(0.92, 1.08)
	clank_sound.play()


func _link_index_at(world_position: Vector2) -> int:
	var local_y := to_local(world_position).y
	var count := _links.size()
	var t := (local_y - _chain_start) / maxf(_chain_end - _chain_start, 1.0)
	return clampi(int(t * count), 0, count - 1)


func _link_global_position(index: int) -> Vector2:
	if index < 0 or index >= _links.size():
		return global_position
	return to_global(Vector2(0.0, _links[index].position.y))


func _play_spark(at: Vector2, size: float, particles: int) -> void:
	spark.global_position = at
	spark.scale = Vector2.ONE * size
	spark.rotation = randf() * TAU
	spark.visible = true
	spark.play(&"spark")
	spark.set_frame_and_progress(0, 0.0)
	spark_particles.global_position = at
	spark_particles.amount = particles
	spark_particles.restart()


func _on_spark_finished() -> void:
	spark.visible = false


# --- Đứt xích -------------------------------------------------------------------

func _break_at(index: int, facing: float) -> void:
	_is_cut = true
	_swing_dir = facing
	_collision.set_deferred("disabled", true)
	remove_from_group(&"asura_cuttable")

	var hit_point := _link_global_position(index)
	_play_spark(hit_point, 1.6, 18)
	snap_sound.pitch_scale = randf_range(0.95, 1.05)
	snap_sound.play()

	# Đoạn trên: treo vào pivot ở khoen neo trần để đung đưa quanh điểm đó.
	_upper_pivot = Node2D.new()
	_upper_pivot.position = Vector2(0.0, _chain_start)
	add_child(_upper_pivot, false, Node.INTERNAL_MODE_FRONT)
	for i in index:
		var link := _links[i]
		link.self_modulate = Color.WHITE
		link.reparent(_upper_pivot, false)
		link.position = Vector2(0.0, link.position.y - _chain_start)
	_swing_t = 0.0
	# Xích đang căng bị đứt sẽ giật ngược lên rồi mới duỗi ra.
	_upper_pivot.scale = Vector2(1.0, 0.82)
	var recoil := create_tween()
	recoil.tween_property(_upper_pivot, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# Mắt xích trúng đòn vỡ làm hai nửa văng ra theo hướng chém.
	var broken := _links[index]
	var broken_pos := broken.position
	broken.queue_free()
	for half in 2:
		var piece := Sprite2D.new()
		piece.texture = LINK_TEXTURE
		piece.region_enabled = true
		piece.region_rect = Rect2(0.0, half * LINK_HEIGHT * 0.5, 12.0, LINK_HEIGHT * 0.5)
		piece.position = broken_pos + Vector2(0.0, (half - 0.5) * LINK_HEIGHT * 0.5)
		add_child(piece, false, Node.INTERNAL_MODE_FRONT)
		_debris.append({
			"node": piece,
			"velocity": Vector2(facing * randf_range(90.0, 160.0), randf_range(-220.0, -140.0) + half * 80.0),
			"spin": facing * randf_range(10.0, 18.0),
			"fade": true,
			"age": 0.0,
		})

	# Đoạn dưới: các mắt xích rời nhau, rơi xuống chất thành đống dưới chân.
	var floor_y := length - 4.0
	for i in range(index + 1, _links.size()):
		var link := _links[i]
		link.self_modulate = Color.WHITE
		_debris.append({
			"node": link,
			"velocity": Vector2(randf_range(-40.0, 40.0) + facing * 25.0, randf_range(-30.0, 10.0)),
			"spin": randf_range(-8.0, 8.0),
			"fade": false,
			"age": 0.0,
			# Chồng lệch nhau vài px để đống xích có độ dày.
			"floor_y": floor_y - float((i - index) % 3) * 2.0,
			"landed": false,
		})
	_links.clear()
	cut.emit()


func _update_swing(delta: float) -> void:
	if _swing_t < 0.0 or _upper_pivot == null:
		return
	_swing_t += delta
	var envelope := exp(-SWING_DAMPING * _swing_t)
	_upper_pivot.rotation = swing_strength * _swing_dir * envelope * sin(SWING_FREQUENCY * _swing_t)
	if envelope < 0.01:
		_upper_pivot.rotation = 0.0
		_swing_t = -1.0


func _update_debris(delta: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var item: Dictionary = _debris[i]
		var node: Sprite2D = item["node"]
		var age: float = item["age"] + delta
		item["age"] = age
		var velocity: Vector2 = item["velocity"]

		if item["fade"]:
			velocity.y += DEBRIS_GRAVITY * delta
			node.position += velocity * delta
			node.rotation += float(item["spin"]) * delta
			node.modulate.a = clampf(1.0 - age / DEBRIS_LIFETIME, 0.0, 1.0)
			item["velocity"] = velocity
			if age >= DEBRIS_LIFETIME:
				node.queue_free()
				_debris.remove_at(i)
			continue

		var floor_y: float = item["floor_y"]
		if item["landed"]:
			# Nằm trên sàn: trượt chậm dần và xoay về tư thế nằm ngang.
			velocity.x = move_toward(velocity.x, 0.0, PILE_FRICTION * 60.0 * delta)
			node.position.x += velocity.x * delta
			var lie_flat := PI * 0.5 * signf(node.rotation + 0.001)
			node.rotation = lerp_angle(node.rotation, lie_flat, 10.0 * delta)
			item["velocity"] = velocity
			if is_zero_approx(velocity.x) and absf(angle_difference(node.rotation, lie_flat)) < 0.02:
				node.rotation = lie_flat
				_debris.remove_at(i)
			continue

		velocity.y += DEBRIS_GRAVITY * delta
		node.position += velocity * delta
		node.rotation += float(item["spin"]) * delta
		if node.position.y >= floor_y:
			node.position.y = floor_y
			if velocity.y > 120.0:
				velocity.y = -velocity.y * PILE_BOUNCE
				velocity.x *= 0.7
				item["spin"] = float(item["spin"]) * 0.5
				_on_link_hit_floor()
			else:
				item["landed"] = true
				velocity.y = 0.0
		item["velocity"] = velocity


func _on_link_hit_floor() -> void:
	if _pile_landed:
		return
	_pile_landed = true
	rattle_sound.pitch_scale = randf_range(0.6, 0.7)
	rattle_sound.play()
	var dust: Node2D = DUST_SCENE.instantiate()
	get_parent().add_child(dust)
	dust.global_position = to_global(Vector2(0.0, length - 16.0))
