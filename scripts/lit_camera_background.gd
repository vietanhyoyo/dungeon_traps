extends Sprite2D

## Smallest scale the image is drawn at. 1.0 keeps pixel art crisp; the image is
## still enlarged when it would not cover the visible area.
@export var min_scale := 1.0


func _ready() -> void:
	_update_from_camera()


func _process(_delta: float) -> void:
	_update_from_camera()


func _update_from_camera() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or texture == null:
		return

	var view_size := get_viewport_rect().size / camera.zoom.abs()
	var view_center := camera.get_screen_center_position()
	var texture_size := texture.get_size()
	var cover_scale := maxf(
		view_size.x / texture_size.x,
		view_size.y / texture_size.y
	)
	scale = Vector2.ONE * maxf(cover_scale, min_scale)

	# Parallax across the camera limits: at the left/top limit the image's
	# left/top edge lines up with the screen, at the right/bottom limit its
	# right/bottom edge does, so a long image scrolls across the whole map.
	var image_size := texture_size * scale
	var limit_min := Vector2(camera.limit_left, camera.limit_top)
	var limit_max := Vector2(camera.limit_right, camera.limit_bottom)
	var progress := Vector2(
		_axis_progress(view_center.x, limit_min.x, limit_max.x, view_size.x),
		_axis_progress(view_center.y, limit_min.y, limit_max.y, view_size.y)
	)
	global_position = view_center + (Vector2(0.5, 0.5) - progress) * (image_size - view_size)


func _axis_progress(center: float, limit_min: float, limit_max: float, view_length: float) -> float:
	var travel := limit_max - limit_min - view_length
	# No usable limits (default +-10000000) or a map smaller than the view.
	if travel <= 0.0 or travel > 1000000.0:
		return 0.5
	return clampf((center - limit_min - view_length * 0.5) / travel, 0.0, 1.0)
