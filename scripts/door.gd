extends Area2D

@export var next_scene_path: String
var is_transitioning := false

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if is_transitioning:
		return

	if body.is_in_group("player"):
		is_transitioning = true
		await get_tree().create_timer(0.3).timeout
		get_tree().change_scene_to_file(next_scene_path)
