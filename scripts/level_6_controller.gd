extends Node2D

const AsuraController = preload("res://scripts/actors/asura_controller.gd")
const SerelynController = preload("res://scripts/actors/serelyn_controller.gd")
const TransformEffect = preload("res://nodes/effects/character_transform_effect.tscn")

const ASURA_TRANSFORM_COLOR := Color(1.0, 0.55, 0.18, 1.0)
const SERELYN_TRANSFORM_COLOR := Color(0.3, 1.0, 0.72, 1.0)

@onready var asura: AsuraController = $Asura
@onready var serelyn: SerelynController = $Serelyn
@onready var camera: Camera2D = $Asura/Camera2D
@onready var light: PointLight2D = $Asura/PointLight2D
@onready var character_hud: CharacterHUD = $CharacterHUD

var controlling_serelyn := false
var _is_transforming := false


func _ready() -> void:
	serelyn.conversation_finished.connect(_on_serelyn_conversation_finished)
	if serelyn.conversation_completed:
		_on_serelyn_conversation_finished()
	else:
		character_hud.set_state(false, false)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("switch_character") \
			or (event is InputEventKey and event.echo):
		return
	if get_tree().paused or GameState.is_game_over() \
			or not serelyn.conversation_completed \
			or serelyn.dialogue_open or asura.is_dead or serelyn.is_dead \
			or asura.movement_locked or serelyn.is_hurt or _is_transforming:
		return

	_switch_character()
	get_viewport().set_input_as_handled()


func _on_serelyn_conversation_finished() -> void:
	# Nhân vật đứng trò chuyện trở thành dạng nhân vật có thể chọn bằng Z.
	_set_actor_active(serelyn, false)
	character_hud.set_state(false, true)


func _switch_character() -> void:
	_is_transforming = true
	var source: CharacterBody2D = serelyn if controlling_serelyn else asura
	var target: CharacterBody2D = asura if controlling_serelyn else serelyn
	var source_velocity := source.velocity
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
	camera.reparent(target, true)
	light.reparent(target, true)
	_set_actor_active(source, false)
	source.velocity = Vector2.ZERO

	controlling_serelyn = not controlling_serelyn
	if controlling_serelyn:
		serelyn.sprite.flip_h = facing_left
		serelyn.set_controlled(true)
	else:
		asura.animated_sprite.flip_h = facing_left
		asura.set_controlled(true)
	camera.reset_smoothing()
	character_hud.set_state(controlling_serelyn, true)

	var effect: CharacterTransformEffect = TransformEffect.instantiate()
	target.add_child(effect)
	effect.position = Vector2(0.0, _body_center_offset(target))
	effect.play(SERELYN_TRANSFORM_COLOR if controlling_serelyn else ASURA_TRANSFORM_COLOR)
	await effect.finished
	_is_transforming = false


func _set_actor_active(actor: CharacterBody2D, active: bool) -> void:
	actor.visible = active
	actor.collision_layer = 2 if active else 0
	actor.collision_mask = 1 if active else 0
	actor.set_physics_process(active)


func _body_center_offset(actor: CharacterBody2D) -> float:
	var shape := actor.get_node("CollisionShape2D") as CollisionShape2D
	return shape.position.y


func _feet_offset(actor: CharacterBody2D) -> float:
	var shape := actor.get_node("CollisionShape2D") as CollisionShape2D
	var capsule := shape.shape as CapsuleShape2D
	return shape.position.y + capsule.height * 0.5
