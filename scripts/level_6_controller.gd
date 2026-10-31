extends Node2D

const AsuraController = preload("res://scripts/actors/asura_controller.gd")
const SerelynController = preload("res://scripts/actors/serelyn_controller.gd")
const SERELYN_SCENE: PackedScene = preload("res://nodes/characters/serelyn.tscn")
const TransformEffect = preload("res://nodes/effects/character_transform_effect.tscn")
const CHARACTER_HUD_SCENE: PackedScene = preload("res://nodes/ui/character_hud.tscn")
const CAMERA_OFFSET := Vector2(-1.0, 5.0)
const CAMERA_SWITCH_DURATION := 0.35
const CHARACTER_SWITCH_COOLDOWN := 5.0

var _level_root: Node2D
var asura: AsuraController
var serelyn: SerelynController
var camera: Camera2D
var light: PointLight2D
var character_hud: CharacterHUD

var controlling_serelyn := false
var _is_transforming := false
var _switch_cooldown_remaining := 0.0


func _ready() -> void:
	# Controller có thể gắn trực tiếp ở root (Level 6-8) hoặc làm node con
	# (Level 1-5, trong đó Level 4 còn có controller riêng cho rương).
	_level_root = self if get_node_or_null("Asura") != null else get_parent() as Node2D
	asura = _level_root.get_node("Asura") as AsuraController
	serelyn = _level_root.get_node_or_null("Serelyn") as SerelynController
	camera = _level_root.get_node("Asura/Camera2D") as Camera2D
	light = _level_root.get_node("Asura/PointLight2D") as PointLight2D
	character_hud = _level_root.get_node_or_null("CharacterHUD") as CharacterHUD
	_setup_party_member.call_deferred()


func _setup_party_member() -> void:
	# Những màn chưa có HUD sẵn chỉ hiện HUD sau khi Serelyn đã được lưu.
	if character_hud == null and GameState.has_party_member("serelyn"):
		character_hud = CHARACTER_HUD_SCENE.instantiate() as CharacterHUD
		character_hud.name = "CharacterHUD"
		_level_root.add_child(character_hud)

	# Level 7/8 và các màn chơi trước Level 6 không có NPC Serelyn đặt sẵn.
	# Chỉ tạo cô ấy thành dạng có thể chơi sau khi đã gia nhập đội.
	if serelyn == null and GameState.has_party_member("serelyn"):
		serelyn = SERELYN_SCENE.instantiate() as SerelynController
		serelyn.name = "Serelyn"
		serelyn.position = asura.position
		_level_root.add_child(serelyn)

	if serelyn == null:
		if character_hud != null:
			character_hud.set_state(false, false)
		GameState.consume_respawn_as_serelyn()
		return

	serelyn.conversation_finished.connect(_on_serelyn_conversation_finished)
	if serelyn.conversation_completed:
		_on_serelyn_conversation_finished()
	elif character_hud != null:
		character_hud.set_state(false, false)

	_restore_respawn_character()


func _restore_respawn_character() -> void:
	if not GameState.consume_respawn_as_serelyn() or serelyn == null \
			or not serelyn.conversation_completed:
		return

	serelyn.global_position = asura.global_position + Vector2(
		0.0, _feet_offset(asura) - _feet_offset(serelyn)
	)
	asura.set_controlled(false)
	_set_actor_active(asura, false)
	_set_actor_active(serelyn, true)
	serelyn.set_controlled(true)
	camera.reparent(serelyn, true)
	light.reparent(serelyn, true)
	controlling_serelyn = true
	if character_hud != null:
		character_hud.set_state(true, true)
	var effect: CharacterTransformEffect = TransformEffect.instantiate()
	serelyn.add_child(effect)
	effect.play(serelyn)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("switch_character") \
			or (event is InputEventKey and event.echo):
		return
	if serelyn == null or get_tree().paused or GameState.is_game_over() \
			or not serelyn.conversation_completed \
			or serelyn.dialogue_open or asura.is_dead or serelyn.is_dead \
			or asura.movement_locked or serelyn.is_hurt or _is_transforming \
			or _switch_cooldown_remaining > 0.0:
		return

	_switch_character()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _switch_cooldown_remaining <= 0.0:
		return
	_switch_cooldown_remaining = maxf(_switch_cooldown_remaining - delta, 0.0)
	if character_hud != null:
		character_hud.set_switch_cooldown(controlling_serelyn, _switch_cooldown_remaining)


func _on_serelyn_conversation_finished() -> void:
	# Nhân vật đứng trò chuyện trở thành dạng nhân vật có thể chọn bằng A.
	_set_actor_active(serelyn, false)
	if character_hud != null:
		character_hud.set_state(false, true)


func _switch_character() -> void:
	_is_transforming = true
	_switch_cooldown_remaining = CHARACTER_SWITCH_COOLDOWN
	var source: CharacterBody2D = serelyn if controlling_serelyn else asura
	var target: CharacterBody2D = asura if controlling_serelyn else serelyn
	var source_velocity := source.velocity
	var camera_screen_center := camera.get_screen_center_position()
	var facing_left := serelyn.sprite.flip_h if controlling_serelyn else asura.animated_sprite.flip_h

	# Hủy slide trước khi tính vị trí chân, vì slide thay đổi chiều cao capsule.
	if controlling_serelyn:
		serelyn.set_controlled(false)
	else:
		asura.set_controlled(false)

	# Hai nhân vật có tâm collision lệch nhau 16 px. Căn theo bàn chân để khi
	# đổi hình vẫn đứng đúng trên mặt đất ở vị trí player vừa đứng.
	target.global_position = source.global_position + Vector2(
		0.0, _feet_offset(source) - _feet_offset(target)
	)
	target.velocity = source_velocity
	_set_actor_active(target, true)
	# Đóng băng nhân vật đích trong lúc hiệu ứng chạy để không bị trượt hoặc
	# nhận lệnh di chuyển trước khi quá trình biến hình kết thúc.
	target.set_physics_process(false)
	camera.reparent(target, true)
	# Bắt đầu từ tâm màn hình đang hiển thị để đổi parent không làm camera giật.
	camera.position_smoothing_enabled = false
	camera.global_position = camera_screen_center
	var camera_tween := camera.create_tween()
	camera_tween.set_trans(Tween.TRANS_SINE)
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(
		camera,
		"global_position",
		target.global_position + CAMERA_OFFSET,
		CAMERA_SWITCH_DURATION
	)
	light.reparent(target, true)
	_set_actor_active(source, false)
	source.velocity = Vector2.ZERO

	controlling_serelyn = not controlling_serelyn
	if controlling_serelyn:
		serelyn.sprite.flip_h = facing_left
		serelyn.set_controlled(true, true)
	else:
		asura.animated_sprite.flip_h = facing_left
		asura.set_controlled(true, true)
	if character_hud != null:
		character_hud.set_state(controlling_serelyn, true)
		character_hud.set_switch_cooldown(controlling_serelyn, _switch_cooldown_remaining)

	var effect: CharacterTransformEffect = TransformEffect.instantiate()
	target.add_child(effect)
	effect.play(target)
	await camera_tween.finished
	camera.position_smoothing_enabled = true
	await effect.finished
	if is_instance_valid(target) and target.is_visible_in_tree():
		target.set_physics_process(true)
	_is_transforming = false


func _set_actor_active(actor: CharacterBody2D, active: bool) -> void:
	actor.visible = active
	actor.collision_layer = 2 if active else 0
	actor.collision_mask = 1 if active else 0
	actor.set_physics_process(active)


func _feet_offset(actor: CharacterBody2D) -> float:
	var shape := actor.get_node("CollisionShape2D") as CollisionShape2D
	var capsule := shape.shape as CapsuleShape2D
	return shape.position.y + capsule.height * 0.5
