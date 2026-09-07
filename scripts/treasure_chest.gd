extends Area2D
class_name TreasureChest

## Rương kho báu: player chạm vào là mở ra. Trạng thái đã mở được giữ ở
## GameState nên chết rồi hồi sinh ở save point rương vẫn đang mở.
##
## Đặt skill_id (một khoá trong Skills.CATALOG) để rương thưởng kỹ năng khi mở.

## Phát đúng lúc người chơi mở rương. Level controller nối vào đây để chạy xử lý
## riêng của màn, rương không cần biết màn làm gì với tín hiệu đó.
signal opened

const SKILL_POPUP_SCENE := preload("res://nodes/ui/skill_popup.tscn")
const SKILL_REVEAL_SCENE := preload("res://nodes/effects/skill_reveal.tscn")
## Icon kỹ năng bắt đầu bay lên từ ngang nắp rương.
const SKILL_REVEAL_OFFSET := Vector2(0, -30)

## Kỹ năng rương này trao cho nhân vật. Để trống thì rương chỉ mở ra, không thưởng gì.
@export var skill_id: String = ""

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var open_sound: AudioStreamPlayer2D = $OpenSound

var is_open := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)

	if GameState.is_chest_opened(_chest_id()):
		_show_already_opened()
		return

	animated_sprite.play(&"closed")


func _on_body_entered(body: Node2D) -> void:
	if is_open or not body.is_in_group(&"player"):
		return

	_lock()
	GameState.mark_chest_opened(_chest_id())
	animated_sprite.play(&"open")
	open_sound.play()
	opened.emit()

	if skill_id.is_empty():
		return

	# Ghi nhận kỹ năng ngay chứ không đợi hết phần trình diễn: rương đã bị đánh
	# dấu là đã mở, nếu người chơi chết giữa chừng thì kỹ năng không được mất.
	GameState.unlock_skill(skill_id)

	# Chờ rương bật nắp xong rồi mới trình diễn, nếu không animation mở rương sẽ
	# bị đóng băng giữa chừng sau lưng popup.
	await animated_sprite.animation_finished
	await _play_skill_reveal()
	_show_skill_popup()


## Icon kỹ năng bay lên khỏi rương trước khi bảng mô tả hiện ra.
func _play_skill_reveal() -> void:
	var reveal: SkillReveal = SKILL_REVEAL_SCENE.instantiate()
	add_child(reveal)
	reveal.position = SKILL_REVEAL_OFFSET
	await reveal.play(skill_id)


func _show_skill_popup() -> void:
	# Chết đúng lúc mở rương: bỏ popup đi. Popup sẽ pause đè lên đếm ngược game
	# over và không còn ai gỡ pause ra sau khi màn được load lại.
	if GameState.is_game_over():
		return

	var scene_root := get_tree().current_scene
	if not scene_root:
		return

	var popup: SkillPopup = SKILL_POPUP_SCENE.instantiate()
	scene_root.add_child(popup)
	popup.show_skill(skill_id)


## Rương đã mở từ lần chơi trước: bỏ qua animation, hiện thẳng khung cuối.
func _show_already_opened() -> void:
	_lock()
	animated_sprite.animation = &"open"
	animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count(&"open") - 1


func _lock() -> void:
	is_open = true
	monitoring = false
	collision_shape.set_deferred("disabled", true)


## Đường dẫn node trong màn, ổn định qua mỗi lần load lại scene.
func _chest_id() -> String:
	var scene_root := get_tree().current_scene
	if scene_root:
		return str(scene_root.get_path_to(self))

	return str(get_path())
