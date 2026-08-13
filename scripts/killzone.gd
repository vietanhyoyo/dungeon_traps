extends Area2D


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_hit"):
			body.take_hit()
		elif body.has_method("lock_movement"):
			body.lock_movement()

		var hazard_owner := get_parent()
		if hazard_owner.has_method("on_player_touched"):
			await hazard_owner.on_player_touched(body)

		var game_state := get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("trigger_game_over"):
			game_state.trigger_game_over(body)
