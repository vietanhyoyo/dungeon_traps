extends Node2D
class_name CharacterTransformEffect

signal finished

const DURATION := 0.55
const FRAME_COUNT := 8

@onready var sprite: Sprite2D = $Sprite2D

var _elapsed := 0.0
var _effect_color := Color.WHITE


func play(effect_color: Color) -> void:
	_effect_color = effect_color
	_elapsed = 0.0
	sprite.frame = 0
	sprite.modulate = Color.WHITE.lerp(_effect_color, 0.3)
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	var progress := clampf(_elapsed / DURATION, 0.0, 1.0)
	sprite.frame = mini(int(progress * FRAME_COUNT), FRAME_COUNT - 1)
	sprite.modulate.a = 1.0 - progress

	if _elapsed >= DURATION:
		finished.emit()
		queue_free()
