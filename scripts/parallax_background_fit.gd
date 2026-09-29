extends Sprite2D


func _ready() -> void:
	_fit_to_camera()


func _process(_delta: float) -> void:
	_fit_to_camera()


func _fit_to_camera() -> void:
	if texture == null:
		return

	var layer := get_parent() as CanvasItem
	var viewport_rect := get_viewport().get_visible_rect()
	var viewport_to_layer := layer.get_global_transform_with_canvas().affine_inverse()
	var top := viewport_to_layer * viewport_rect.position
	var bottom := viewport_to_layer * Vector2(viewport_rect.position.x, viewport_rect.end.y)
	position.y = top.y
	scale.y = (bottom.y - top.y) / float(texture.get_height())
