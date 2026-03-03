extends Area2D

@export var next_scene: PackedScene
var is_transitioning := false

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if is_transitioning:
		print("❌ Already transitioning")
		return

	if body.is_in_group("player"):
		print("✅ Player detected")
		is_transitioning = true
		await get_tree().create_timer(0.3).timeout

		if next_scene == null:
			push_error("❌ next_scene is NULL")
			return

		get_tree().change_scene_to_packed(next_scene)
