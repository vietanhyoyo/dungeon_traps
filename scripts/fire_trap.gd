extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_shape: CollisionShape2D = $CollisionShape2D
@onready var trigger_area: Area2D = $TriggerArea


func _ready() -> void:
	body_entered.connect(_on_damage_body_entered)
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	animated_sprite.visible = false


func _on_trigger_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	trigger_area.set_deferred("monitoring", false)
	animated_sprite.visible = true
	damage_shape.set_deferred("disabled", false)
	set_deferred("monitoring", true)


func _on_damage_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var game_state := get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("trigger_game_over"):
			game_state.trigger_game_over(body)
