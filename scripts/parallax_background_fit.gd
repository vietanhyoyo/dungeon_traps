extends Sprite2D

@onready var base_scale := scale.x


func _ready() -> void:
	_fit_background()


func _process(_delta: float) -> void:
	_fit_background()


func _fit_background() -> void:
	if texture == null:
		return

	var layer := get_parent() as Parallax2D
	var viewport_rect := get_viewport().get_visible_rect()
	var viewport_to_layer := layer.get_global_transform_with_canvas().affine_inverse()
	var viewport_top := viewport_to_layer * viewport_rect.position
	var viewport_bottom := viewport_to_layer * Vector2(viewport_rect.position.x, viewport_rect.end.y)
	var view_height := viewport_bottom.y - viewport_top.y
	var cover_scale := maxf(base_scale, view_height / float(texture.get_height()))
	scale = Vector2.ONE * cover_scale
	var repeat_size := Vector2(texture.get_size()) * cover_scale
	if not layer.repeat_size.is_equal_approx(repeat_size):
		layer.repeat_size = repeat_size
