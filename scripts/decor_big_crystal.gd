extends "res://scripts/decor_crystal.gd"

const SLIDE_OFF_SPEED := 300.0
const SLIDE_OFF_FEET_TOLERANCE := 24.0
const CRYSTAL_KEY_SCENE: PackedScene = preload("res://nodes/items/crystal_key.tscn")
## Tâm sprite pha lê so với gốc node (gốc nằm ở chân).
const KEY_SPAWN_OFFSET := Vector2(0.0, -24.0)

## Để trống thì là pha lê trang trí. Đặt id thì phá vỡ sẽ rơi ra chìa khoá đó.
@export var key_id := ""

@onready var slip_sensor: Area2D = $SlipSensor


func _ready() -> void:
	# Hồi sinh ở save point sau khi đã lấy chìa: pha lê này đã vỡ từ trước.
	if not key_id.is_empty() and GameState.is_key_collected(key_id):
		queue_free()


func _physics_process(delta: float) -> void:
	if _is_broken:
		return

	var crystal_top_y := collision_shape.global_position.y \
		+ collision_shape.shape.get_rect().position.y
	for body in slip_sensor.get_overlapping_bodies():
		var player := body as CharacterBody2D
		if player == null or player.velocity.y < 0.0:
			continue

		var player_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if player_shape == null or player_shape.shape == null:
			continue

		var feet_y := player_shape.global_position.y + player_shape.shape.get_rect().end.y
		if feet_y > crystal_top_y + SLIDE_OFF_FEET_TOLERANCE:
			continue

		var direction := signf(player.global_position.x - global_position.x)
		if is_zero_approx(direction):
			var player_sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			direction = -1.0 if player_sprite != null and player_sprite.flip_h else 1.0
		player.global_position.x += direction * SLIDE_OFF_SPEED * delta


func break_apart() -> void:
	if _is_broken:
		return
	slip_sensor.set_deferred("monitoring", false)
	if not key_id.is_empty() and not GameState.is_key_collected(key_id):
		_drop_key()
	super.break_apart()


func _drop_key() -> void:
	# Ghi nhận ngay lúc vỡ, để chết giữa lúc chìa đang bay vẫn giữ được chìa.
	GameState.collect_key(key_id)

	var key := CRYSTAL_KEY_SCENE.instantiate() as CrystalKey
	# Chìa sống ở scene hiện tại: pha lê sẽ queue_free() khi animation vỡ xong.
	get_tree().current_scene.add_child(key)
	key.global_position = global_position + KEY_SPAWN_OFFSET
	key.collect_into_hud()
