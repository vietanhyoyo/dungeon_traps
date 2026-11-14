extends Node2D

## Con lắc quả cầu gai, ghép từ nhiều mảnh: giá treo đứng yên, xích gồm từng
## mắt xích riêng, và quả cầu ở cuối. Gốc node là mặt trần: đặt node sát trần
## thì giá treo bám đúng trần, Pivot là khoen xoay ngay bên dưới.
##
## Mỗi mắt xích đi theo cùng một đường sin nhưng trễ hơn mắt phía trên một chút,
## nên xích uốn cong khi đổi chiều và quả cầu như bị kéo theo sau, thay vì cả
## cây đu như một thanh cứng. Quả cầu còn để lại vài bóng mờ khi lao nhanh qua
## điểm thấp nhất.

## Góc lệch tối đa so với phương thẳng đứng, tính cho mỗi bên.
@export_range(0.0, 89.0, 1.0) var swing_angle_degrees := 55.0
## Thời gian cho một chu kỳ đầy đủ: giữa -> phải -> giữa -> trái -> giữa.
@export_range(0.1, 20.0, 0.1, "or_greater") var swing_period := 4.4
## Dịch pha theo tỉ lệ chu kỳ (0..1), để nhiều con lắc cạnh nhau đu so le.
@export_range(0.0, 1.0, 0.01) var phase_offset := 0.0
## Độ trễ (giây) giữa hai mắt xích liền nhau. 0 = cả cây cứng đơ như trước;
## lớn hơn thì xích càng uốn mềm.
@export_range(0.0, 0.05, 0.001) var chain_lag := 0.018

## Khoảng cách giữa tâm hai mắt xích liền nhau (mắt dài 18px, chồng lên nhau 6px).
const LINK_PITCH := 12.0
## Từ đầu mút mắt xích cuối tới tâm quả cầu.
const BALL_OFFSET := 24.0
## Bóng mờ của quả cầu: cách nhau bao lâu và đậm nhất bao nhiêu.
const GHOST_SPACING := 0.035
const GHOST_MAX_ALPHA := 0.32

@onready var pivot: Node2D = $Pivot
@onready var ball: Area2D = $Pivot/Ball
@onready var ball_sprite: Sprite2D = $Pivot/BallSprite
@onready var chain: Node2D = $Pivot/Chain
@onready var trail: Node2D = $Pivot/Trail

var _elapsed := 0.0
var _links: Array[Sprite2D] = []
var _ghosts: Array[Sprite2D] = []


func _ready() -> void:
	for child in chain.get_children():
		if child is Sprite2D:
			_links.append(child as Sprite2D)
	for child in trail.get_children():
		if child is Sprite2D:
			_ghosts.append(child as Sprite2D)
	ball.body_entered.connect(_on_ball_body_entered)
	_apply_swing(0.0)


# Cập nhật theo khung hình chứ không theo nhịp vật lý: trên màn 120Hz+ chuyển
# động vẫn mượt, không bị giật theo bước 60Hz. Area2D vẫn được kiểm tra va chạm
# ở bước vật lý kế tiếp với vị trí mới nhất.
func _process(delta: float) -> void:
	# Game over thì đóng băng con lắc lại, để khung hình chết không bị quả cầu
	# vẫn đu qua đu lại phía sau.
	if _is_game_over():
		return

	_elapsed += delta
	_apply_swing(_elapsed)


## Góc của một đoạn xích ở thời điểm time (rad, 0 = thẳng đứng).
func _angle_at(time: float) -> float:
	var phase := TAU * (time / maxf(swing_period, 0.01) + phase_offset)
	return deg_to_rad(swing_angle_degrees) * sin(phase)


## Dựng cả cây con lắc ở thời điểm time. Trả về vị trí và góc của quả cầu;
## khi update_links bật thì đặt luôn từng mắt xích.
func _solve_chain(time: float, update_links: bool) -> Transform2D:
	var joint := Vector2.ZERO
	for i in _links.size():
		var angle := _angle_at(time - chain_lag * i)
		var direction := Vector2.DOWN.rotated(angle)
		if update_links:
			var link := _links[i]
			link.position = joint + direction * (LINK_PITCH * 0.5)
			link.rotation = angle
		joint += direction * LINK_PITCH

	var ball_angle := _angle_at(time - chain_lag * _links.size())
	var ball_position := joint + Vector2.DOWN.rotated(ball_angle) * BALL_OFFSET
	return Transform2D(ball_angle, ball_position)


func _apply_swing(time: float) -> void:
	var ball_transform := _solve_chain(time, true)
	ball_sprite.position = ball_transform.origin
	ball_sprite.rotation = ball_transform.get_rotation()
	ball.position = ball_transform.origin

	# Bóng mờ chỉ hiện khi quả cầu đang lao nhanh (gần điểm thấp nhất), tắt hẳn
	# ở hai đầu biên lúc nó gần như đứng yên.
	var phase := TAU * (time / maxf(swing_period, 0.01) + phase_offset)
	var speed_factor := pow(absf(cos(phase)), 2.0)
	for i in _ghosts.size():
		var ghost := _ghosts[i]
		var ghost_transform := _solve_chain(time - GHOST_SPACING * (i + 1), false)
		ghost.position = ghost_transform.origin
		ghost.rotation = ghost_transform.get_rotation()
		var fade := 1.0 - float(i) / float(_ghosts.size())
		ghost.modulate.a = GHOST_MAX_ALPHA * fade * speed_factor


func _on_ball_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return

	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("trigger_game_over"):
		game_state.trigger_game_over(body)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
