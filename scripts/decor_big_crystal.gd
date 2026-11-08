extends "res://scripts/decor_crystal.gd"

const SLIDE_OFF_SPEED := 300.0
const SLIDE_OFF_FEET_TOLERANCE := 24.0

@onready var slip_sensor: Area2D = $SlipSensor


func _physics_process(delta: float) -> void:
	if _is_broken:
		return

	var crystal_top_y := collision_shape.global_position.y \
		+ collision_shape.shape.get_rect().position.y
	for body in slip_sensor.get_overlapping_bodies():
		var player := body as CharacterBody2D
		if player == null or player.velocity.y < 0.0:
			continue

		var player_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if player_shape == null or player_shape.shape == null:
			continue

		var feet_y := player_shape.global_position.y + player_shape.shape.get_rect().end.y
		if feet_y > crystal_top_y + SLIDE_OFF_FEET_TOLERANCE:
			continue

		var direction := signf(player.global_position.x - global_position.x)
		if is_zero_approx(direction):
			var player_sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			direction = -1.0 if player_sprite != null and player_sprite.flip_h else 1.0
		player.global_position.x += direction * SLIDE_OFF_SPEED * delta


func break_apart() -> void:
	slip_sensor.set_deferred("monitoring", false)
	super.break_apart()
