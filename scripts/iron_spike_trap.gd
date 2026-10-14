extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_shape: CollisionShape2D = $CollisionShape2D
@onready var trigger_area: Area2D = $TriggerArea
@onready var appear_sound: AudioStreamPlayer2D = $AppearSound

var _activated := false


func _ready() -> void:
	body_entered.connect(_on_damage_body_entered)
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	animated_sprite.animation_finished.connect(_on_appear_animation_finished)
	animated_sprite.visible = false
	damage_shape.disabled = true
	monitoring = false


func _on_trigger_body_entered(body: Node2D) -> void:
	if _activated or not body.is_in_group("player"):
		return

	_activated = true
	trigger_area.set_deferred("monitoring", false)
	appear_sound.play()
	animated_sprite.visible = true
	animated_sprite.play("appear")


func _on_appear_animation_finished() -> void:
	if not _activated or animated_sprite.animation != "appear":
		return

	# Only expose the spike's hitbox once the full spike is visible.
	damage_shape.set_deferred("disabled", false)
	set_deferred("monitoring", true)
	await _enable_damage_after_physics_update()


func _enable_damage_after_physics_update() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(self):
		return

	# The player may still be standing on the trigger when the spike finishes rising.
	for body in get_overlapping_bodies():
		_on_damage_body_entered(body)


func _on_damage_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("trigger_game_over"):
		game_state.trigger_game_over(body)
