extends Node2D

const AsuraController = preload("res://scripts/actors/asura_controller.gd")
const SerelynController = preload("res://scripts/actors/serelyn_controller.gd")

@onready var asura: AsuraController = $Asura
@onready var serelyn: SerelynController = $Serelyn
@onready var camera: Camera2D = $Asura/Camera2D
@onready var light: PointLight2D = $Asura/PointLight2D
@onready var light_offset: Vector2 = light.position

var controlling_serelyn := false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("switch_character") \
			or (event is InputEventKey and event.echo):
		return
	if get_tree().paused or GameState.is_game_over() \
			or not GameState.has_party_member("serelyn") \
			or serelyn.dialogue_open or asura.is_dead or serelyn.is_dead \
			or asura.movement_locked or serelyn.is_hurt:
		return

	controlling_serelyn = not controlling_serelyn
	if controlling_serelyn:
		asura.set_controlled(false)
		serelyn.set_controlled(true)
		camera.reparent(serelyn, false)
		light.reparent(serelyn, false)
	else:
		serelyn.set_controlled(false)
		asura.set_controlled(true)
		camera.reparent(asura, false)
		light.reparent(asura, false)

	camera.position = Vector2(-1, 5)
	camera.reset_smoothing()
	light.position = light_offset
	get_viewport().set_input_as_handled()
