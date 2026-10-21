extends StaticBody2D

const BREAK_SOUND := preload("res://assets/sounds/crystal_break.wav")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var glow: PointLight2D = $Glow
@onready var glow_animation: AnimationPlayer = $AnimationPlayer

var _is_broken := false


func break_apart() -> void:
	if _is_broken:
		return

	_is_broken = true
	remove_from_group(&"breakable")
	collision_shape.set_deferred("disabled", true)
	set_deferred("collision_layer", 0)
	glow_animation.stop()
	_play_break_sound()
	sprite.play(&"broken")

	var fade_tween := create_tween().set_parallel(true)
	fade_tween.tween_property(glow, "energy", 0.0, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_tween.tween_property(glow, "texture_scale", 0.35, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await sprite.animation_finished
	queue_free()


func _play_break_sound() -> void:
	# Âm thanh sống ở scene hiện tại để animation vỡ xong không cắt đuôi tiếng.
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = BREAK_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	sound_player.play()
