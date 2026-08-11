extends Area2D

@onready var pickup_sound: AudioStreamPlayer2D = $PickupSound
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var collected := false

func _on_body_entered(body: Node2D) -> void:
	if collected or not body.is_in_group("player"):
		return

	collected = true
	monitoring = false
	collision_shape.set_deferred("disabled", true)
	get_tree().call_group(&"star_hud", &"add_star")
	$AnimatedSprite2D.hide()
	pickup_sound.play()

	await pickup_sound.finished
	queue_free()
