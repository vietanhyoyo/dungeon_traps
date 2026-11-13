extends Area2D

signal activated(spawn_position: Vector2)

## Sprite sheet: khung 0 là cờ chưa kích hoạt (màu trầm, ngọc tắt), khung 1..3
## là cờ phấp phới dịu dần lúc vừa kích hoạt, khung 4 là cờ đã kích hoạt đứng yên.
const IDLE_FRAME := 0
const ACTIVATE_FRAMES: Array[int] = [1, 2, 3, 4]
const ACTIVE_FRAME := 4
const ACTIVATE_FRAME_TIME := 0.09
## Độ sáng đèn khi đã kích hoạt, và mức loé lên lúc vừa chạm vào.
const GLOW_ENERGY := 0.75
const GLOW_BURST_ENERGY := 1.8

## Điểm đặt tâm nhân vật khi hồi sinh, tính từ chân cờ.
@export var spawn_offset := Vector2(0.0, -31.0)

@onready var flag_sprite: Sprite2D = $FlagSprite
@onready var glow: PointLight2D = $Glow
@onready var sparks: CPUParticles2D = $Sparks

var is_activated := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	flag_sprite.frame = IDLE_FRAME
	if GameState.is_checkpoint_active(_get_spawn_position()):
		_set_activated_visual(false)


func _on_body_entered(body: Node2D) -> void:
	if is_activated or GameState.is_game_over() or not body.is_in_group(&"player"):
		return

	var spawn_position := _get_spawn_position()
	GameState.activate_checkpoint(spawn_position)
	_set_activated_visual(true)
	activated.emit(spawn_position)


func _get_spawn_position() -> Vector2:
	return global_position + spawn_offset


func _set_activated_visual(animate: bool) -> void:
	is_activated = true
	glow.enabled = true

	if not animate:
		# Hồi sinh ở save point đã kích hoạt: cờ đứng yên, đèn sáng sẵn.
		flag_sprite.frame = ACTIVE_FRAME
		glow.energy = GLOW_ENERGY
		return

	# Cờ phấp phới một lần rồi đứng yên.
	var frame_tween := create_tween()
	for frame_index in ACTIVATE_FRAMES:
		frame_tween.tween_callback(flag_sprite.set_frame.bind(frame_index))
		frame_tween.tween_interval(ACTIVATE_FRAME_TIME)

	# Đèn loé sáng rồi dịu về mức thường, kèm tia lửa bắn ra từ viên ngọc.
	glow.energy = GLOW_BURST_ENERGY
	var glow_tween := create_tween()
	glow_tween.tween_property(glow, "energy", GLOW_ENERGY, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	sparks.restart()

	flag_sprite.scale = Vector2(1.0, 1.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(flag_sprite, "scale", Vector2(1.18, 1.18), 0.12)
	tween.tween_property(flag_sprite, "scale", Vector2.ONE, 0.18)
