extends Node2D

## Con lắc quả cầu gai: cả cây con lắc (vòng neo, xích, quả cầu) là một sprite
## duy nhất, xoay quanh gốc node. Gốc node chính là điểm neo, nên đặt node ngay
## sát mặt trần là con lắc treo đúng chỗ, không phải căn lại sprite con.

## Góc lệch tối đa so với phương thẳng đứng, tính cho mỗi bên.
@export_range(0.0, 89.0, 1.0) var swing_angle_degrees := 55.0
## Thời gian cho một chu kỳ đầy đủ: giữa -> phải -> giữa -> trái -> giữa.
@export_range(0.1, 20.0, 0.1, "or_greater") var swing_period := 4.4
## Dịch pha theo tỉ lệ chu kỳ (0..1), để nhiều con lắc cạnh nhau đu so le.
@export_range(0.0, 1.0, 0.01) var phase_offset := 0.0

@onready var pivot: Node2D = $Pivot
@onready var ball: Area2D = $Pivot/Ball

var _elapsed := 0.0


func _ready() -> void:
	ball.body_entered.connect(_on_ball_body_entered)
	_apply_swing(0.0)


func _physics_process(delta: float) -> void:
	# Game over thì đóng băng con lắc lại, để khung hình chết không bị quả cầu
	# vẫn đu qua đu lại phía sau.
	if _is_game_over():
		return

	_elapsed += delta
	_apply_swing(_elapsed)


func _apply_swing(time: float) -> void:
	var phase := TAU * (time / maxf(swing_period, 0.01) + phase_offset)
	pivot.rotation = deg_to_rad(swing_angle_degrees) * sin(phase)


func _on_ball_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return

	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("trigger_game_over"):
		game_state.trigger_game_over(body)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
