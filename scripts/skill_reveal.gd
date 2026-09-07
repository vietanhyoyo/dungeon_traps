extends Node2D
class_name SkillReveal

## Icon kỹ năng bay lên khỏi rương vừa mở rồi tự giải phóng. Rương await hàm
## play() để biết lúc nào trình diễn xong mà hiện bảng mô tả.

const RISE_HEIGHT = 46.0
const RISE_DURATION = 0.7
const HOLD_DURATION = 0.3
const START_SCALE = Vector2(0.25, 0.25)
const END_SCALE = Vector2(1.5, 1.5)
const GLOW_ENERGY = 1.6

@onready var icon: Sprite2D = $Icon
@onready var glow: PointLight2D = $Icon/Glow


func play(skill_id: String) -> void:
	icon.texture = Skills.make_icon(skill_id)
	if icon.texture == null:
		queue_free()
		return

	icon.scale = START_SCALE
	icon.modulate.a = 0.0
	glow.energy = 0.0

	# Icon vừa nhô lên vừa nở to ra, ánh sáng bám theo icon nên sáng dần cùng lúc.
	var tween := create_tween().set_parallel()
	tween.tween_property(icon, "position:y", -RISE_HEIGHT, RISE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "scale", END_SCALE, RISE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "modulate:a", 1.0, RISE_DURATION * 0.4)
	tween.tween_property(glow, "energy", GLOW_ENERGY, RISE_DURATION * 0.6)

	await tween.finished
	# Giữ icon đứng yên một nhịp cho người chơi kịp nhìn trước khi popup che lên.
	await get_tree().create_timer(HOLD_DURATION).timeout
	queue_free()
