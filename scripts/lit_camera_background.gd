extends Sprite2D


func _ready() -> void:
	_update_from_camera()


func _process(_delta: float) -> void:
	_update_from_camera()


func _update_from_camera() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or texture == null:
		return

	global_position = camera.get_screen_center_position()

	var visible_world_size := get_viewport_rect().size / camera.zoom.abs()
	var texture_size := texture.get_size()
	var cover_scale := maxf(
		visible_world_size.x / texture_size.x,
		visible_world_size.y / texture_size.y
	)
	scale = Vector2.ONE * cover_scale
