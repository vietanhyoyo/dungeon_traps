extends StaticBody2D
class_name CuttableRope

signal shot


func hit_by_arrow() -> void:
	shot.emit()
