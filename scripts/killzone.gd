extends Area2D


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	# Nhân vật có khung bất tử ngắn ngay đầu đòn đánh. Không bỏ luôn cú va chạm
	# này: chờ hết khung rồi kiểm tra lại, nếu người chơi vẫn còn nằm trong vùng
	# nguy hiểm thì mới ăn đòn. Nhờ vậy khung bất tử chỉ cứu cú chém lướt qua,
	# chứ không biến việc đứng lì trong bẫy thành an toàn.
	if body.has_method("is_invulnerable") and body.is_invulnerable():
		await _wait_for_invulnerability_end(body)
		if not is_instance_valid(self) or not is_instance_valid(body):
			return
		if not monitoring or not overlaps_body(body):
			return

	_hit_player(body)


## Chờ tới bước physics đầu tiên mà player không còn bất tử.
func _wait_for_invulnerability_end(body: Node2D) -> void:
	while is_instance_valid(body) and body.is_invulnerable():
		await get_tree().physics_frame


func _hit_player(body: Node2D) -> void:
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
