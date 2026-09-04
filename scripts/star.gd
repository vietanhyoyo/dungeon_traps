extends Area2D

@onready var pickup_sound: AudioStreamPlayer2D = $PickupSound
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var collected := false


func _ready() -> void:
	# Sao đã ăn ở lần chơi trước thì không hiện lại khi hồi sinh ở save point.
	if GameState.is_star_collected(_star_id()):
		collected = true
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if collected or not body.is_in_group("player"):
		return

	collected = true
	monitoring = false
	collision_shape.set_deferred("disabled", true)
	GameState.collect_star(_star_id())
	get_tree().call_group(&"star_hud", &"add_star")
	animated_sprite.hide()
	pickup_sound.play()

	await pickup_sound.finished
	queue_free()


## Đường dẫn node trong màn, ổn định qua mỗi lần load lại scene.
func _star_id() -> String:
	var scene_root := get_tree().current_scene
	if scene_root:
		return str(scene_root.get_path_to(self))

	return str(get_path())
