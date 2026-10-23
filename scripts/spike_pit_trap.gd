extends Node2D

const PIT_DEPTH := 128.0
const PIT_WIDTH := 64.0
const PIT_LANDING_TIMEOUT_FRAMES := 180
const PIT_SETTLE_DELAY := 0.6
const SPIKE_CLOSE_DURATION := 2.0

@export var tile_map_path: NodePath = ^"../TileMap32"

@onready var ground_collision: CollisionShape2D = $FakeGround/CollisionShape2D
@onready var trigger_area: Area2D = $FakeGround/TriggerArea
@onready var ground_sprite: Sprite2D = $FakeGround/GroundSprite
@onready var pit_bottom: StaticBody2D = $PitBottom
@onready var pit_bottom_collision: CollisionShape2D = $PitBottom/CollisionShape2D
@onready var left_wall: Area2D = $LeftWall
@onready var right_wall: Area2D = $RightWall
@onready var left_wall_solid_collision: CollisionShape2D = $LeftWall/SolidWall/CollisionShape2D
@onready var right_wall_solid_collision: CollisionShape2D = $RightWall/SolidWall/CollisionShape2D
@onready var activation_sound: AudioStreamPlayer2D = $ActivationSound

var _triggered := false
var _game_over_started := false
var _player_has_reached_pit_bottom := false
var _trapped_player: CharacterBody2D


func _ready() -> void:
	left_wall.body_entered.connect(_on_spike_wall_body_entered)
	right_wall.body_entered.connect(_on_spike_wall_body_entered)


func _physics_process(_delta: float) -> void:
	if _triggered:
		if not is_instance_valid(_trapped_player):
			return
		if _is_standing_on_pit_bottom(_trapped_player):
			_player_has_reached_pit_bottom = true
		if _player_has_reached_pit_bottom and _are_both_walls_touching_player(_trapped_player):
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
	left_wall_solid_collision.set_deferred("disabled", false)
	right_wall_solid_collision.set_deferred("disabled", false)
	trigger_area.set_deferred("monitoring", false)
	ground_collision.set_deferred("disabled", true)
	call_deferred("_clear_floor_tiles")

	await _drop_fake_ground()
	if not is_instance_valid(self) or not is_inside_tree():
		return

	var landed_on_bottom := await _wait_for_player_to_land()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if landed_on_bottom:
		var scene_tree := get_tree()
		if scene_tree == null:
			return
		await scene_tree.create_timer(PIT_SETTLE_DELAY).timeout
		if not is_instance_valid(self) or not is_inside_tree():
			return
	await _close_spike_walls()


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
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(ground_sprite, "position:y", 64.0 + PIT_DEPTH, 0.4)
	await tween.finished
	if not is_inside_tree():
		return
	ground_sprite.hide()


func _wait_for_player_to_land() -> bool:
	var player := _trapped_player
	if not is_instance_valid(player) or not is_inside_tree():
		return false
	for _frame in range(PIT_LANDING_TIMEOUT_FRAMES):
		if not is_instance_valid(player) or not is_inside_tree():
			return false
		if player.is_on_floor():
			if _is_standing_on_pit_bottom(player):
				_player_has_reached_pit_bottom = true
				return true
			return false
		await get_tree().physics_frame
		if not is_inside_tree():
			return false
	return false


func _close_spike_walls() -> void:
	if not is_inside_tree():
		return
	left_wall.set_deferred("monitoring", true)
	right_wall.set_deferred("monitoring", true)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(left_wall, "position:x", -12.0, SPIKE_CLOSE_DURATION)
	tween.tween_property(right_wall, "position:x", 12.0, SPIKE_CLOSE_DURATION)
	await tween.finished
	if not is_inside_tree():
		return
	if _player_has_reached_pit_bottom and _are_both_walls_touching_player(_trapped_player):
		await _crush_player(_trapped_player)


func _on_spike_wall_body_entered(body: Node2D) -> void:
	if not _triggered or _game_over_started or not (body is CharacterBody2D):
		return
	var player := body as CharacterBody2D
	if not body.is_in_group(&"player"):
		return
	if _is_standing_on_pit_bottom(player):
		_player_has_reached_pit_bottom = true
	if body.has_method("is_invulnerable"):
		while is_instance_valid(body) and body.is_invulnerable():
			if not is_inside_tree():
				return
			if not _player_has_reached_pit_bottom or not _are_both_walls_touching_player(body):
				return
			await get_tree().physics_frame
			if not is_inside_tree():
				return
	if _player_has_reached_pit_bottom and _are_both_walls_touching_player(body):
		await _crush_player(body)


func _get_player_body_center(player: CharacterBody2D) -> Vector2:
	var collision_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var center_global := player.global_position
	if collision_shape != null and not collision_shape.disabled:
		center_global = collision_shape.global_position
	return to_local(center_global)


func _is_standing_on_pit_bottom(player: CharacterBody2D) -> bool:
	if not is_instance_valid(player) or not player.is_in_group(&"player") or not player.is_on_floor():
		return false
	for index in range(player.get_slide_collision_count()):
		var collision := player.get_slide_collision(index)
		if collision.get_collider() != pit_bottom or collision.get_normal().y >= -0.5:
			continue
		if collision.get_collider_shape() == pit_bottom_collision:
			return true
	return false


func _are_both_walls_touching_player(body: Node2D) -> bool:
	return is_instance_valid(body) \
		and left_wall.overlaps_body(body) \
		and right_wall.overlaps_body(body)


func _crush_player(body: Node2D) -> void:
	if _game_over_started or not (body is CharacterBody2D):
		return
	if not body.is_in_group(&"player") \
		or not _player_has_reached_pit_bottom \
		or not _are_both_walls_touching_player(body):
		return
	_game_over_started = true
	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("trigger_game_over"):
		await game_state.trigger_game_over(body)
