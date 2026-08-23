extends Area2D

signal activated(spawn_position: Vector2)

## Điểm đặt tâm nhân vật khi hồi sinh, tính từ chân cờ.
@export var spawn_offset := Vector2(0.0, -31.0)

@onready var flag_sprite: Sprite2D = $FlagSprite
@onready var activation_light: PointLight2D = $ActivationLight

var is_activated := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if GameState.is_checkpoint_active(_get_spawn_position()):
		_set_activated_visual(false)


func _on_body_entered(body: Node2D) -> void:
	if is_activated or GameState.is_game_over() or not body.is_in_group(&"player"):
		return

	var spawn_position := _get_spawn_position()
	GameState.activate_checkpoint(spawn_position)
	_set_activated_visual(true)
	activated.emit(spawn_position)


func _get_spawn_position() -> Vector2:
	return global_position + spawn_offset


func _set_activated_visual(animate: bool) -> void:
	is_activated = true
	activation_light.enabled = true
	flag_sprite.modulate = Color(1.0, 0.9, 0.65, 1.0)

	if not animate:
		return

	flag_sprite.scale = Vector2(1.0, 1.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(flag_sprite, "scale", Vector2(1.18, 1.18), 0.12)
	tween.tween_property(flag_sprite, "scale", Vector2.ONE, 0.18)
