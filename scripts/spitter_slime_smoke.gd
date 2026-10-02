extends Node2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var killzone: Area2D = $Killzone


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite.play(&"expand")


func _on_animation_finished() -> void:
	if animated_sprite.animation == &"expand":
		animated_sprite.play(&"dissipate")
	elif animated_sprite.animation == &"dissipate":
		killzone.set_deferred("monitoring", false)
		queue_free()
