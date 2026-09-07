extends StaticBody2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var trigger_area: Area2D = $TriggerArea

var _is_breaking := false


func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_area_body_entered)
	animated_sprite.play(&"default")


func _on_trigger_area_body_entered(body: Node2D) -> void:
	if _is_breaking or not body.is_in_group(&"player"):
		return

	# Chỉ vỡ khi player đi/đáp xuống từ phía trên, không kích hoạt lúc nhảy xuyên
	# qua cạnh dưới của bục.
	if body.global_position.y >= global_position.y:
		return

	_is_breaking = true
	trigger_area.set_deferred("monitoring", false)
	animated_sprite.play(&"broken")
	await animated_sprite.animation_finished

	if not is_instance_valid(self):
		return

	collision_shape.set_deferred("disabled", true)
	queue_free()
