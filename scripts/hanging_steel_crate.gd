@tool
extends Node2D
class_name HangingSteelCrate

## Từ điểm neo ở gốc scene đến mép trên của hộp.
@export_range(24.0, 512.0, 1.0, "or_greater") var rope_length := 96.0:
	set(value):
		rope_length = maxf(value, 24.0)
		if is_node_ready() and not _is_cut:
			_update_layout()

@onready var rope: CuttableRope = $Rope
@onready var rope_visual: Line2D = $Rope/Line2D
@onready var rope_collision: CollisionShape2D = $Rope/CollisionShape2D
@onready var crate: PushableCrate = $SteelCrate

var _is_cut := false
var _shape_is_unique := false


func _ready() -> void:
	_update_layout()
	if not Engine.is_editor_hint():
		rope.shot.connect(cut_rope)


func _update_layout() -> void:
	rope_visual.points = PackedVector2Array([Vector2.ZERO, Vector2(0.0, rope_length)])
	rope_collision.position = Vector2(0.0, rope_length * 0.5)
	# Shape thuộc riêng instance này để chỉnh chiều dài không làm đổi scene khác.
	if not _shape_is_unique:
		rope_collision.shape = rope_collision.shape.duplicate() as RectangleShape2D
		_shape_is_unique = true
	(rope_collision.shape as RectangleShape2D).size = Vector2(4.0, rope_length)
	if not _is_cut:
		crate.position = Vector2(0.0, rope_length + 16.0)


func cut_rope() -> void:
	if _is_cut or Engine.is_editor_hint():
		return

	_is_cut = true
	rope.queue_free()
	crate.suspended = false
