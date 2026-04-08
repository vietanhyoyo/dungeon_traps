extends GPUParticles2D

func _ready() -> void:
	restart()
	emitting = true
	await get_tree().create_timer(0.5).timeout
	queue_free()
