extends Node2D
class_name CharacterTransformEffect

signal finished

const DURATION := 0.55
const INNER_RADIUS := 18.0
const OUTER_RADIUS := 48.0

var _elapsed := 0.0
var _effect_color := Color.WHITE


func play(effect_color: Color) -> void:
	_effect_color = effect_color
	_elapsed = 0.0
	set_process(true)
	queue_redraw()


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= DURATION:
		finished.emit()
		queue_free()


func _draw() -> void:
	var progress := clampf(_elapsed / DURATION, 0.0, 1.0)
	var fade := 1.0 - progress
	var ring_color := _effect_color
	ring_color.a = fade
	var ring_radius := lerpf(INNER_RADIUS, OUTER_RADIUS, progress)
	var ring_width := lerpf(4.0, 1.0, progress)

	# Hai vòng xoay ngược chiều tạo cảm giác nhân vật đang được triệu hồi.
	draw_arc(Vector2.ZERO, ring_radius, progress * TAU, progress * TAU + PI * 1.55,
		32, ring_color, ring_width, true)
	var highlight_color := _effect_color.lightened(0.35)
	highlight_color.a = fade
	draw_arc(Vector2.ZERO, ring_radius * 0.72, -progress * TAU,
		-progress * TAU + PI * 1.25, 24, highlight_color, ring_width * 0.75, true)

	# Tia sáng nhỏ nở ra từ tâm ở đầu hiệu ứng.
	var flash := maxf(0.0, 1.0 - progress * 3.0)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, 8.0 + progress * 10.0, Color(1.0, 1.0, 1.0, flash * 0.8))
