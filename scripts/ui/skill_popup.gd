extends CanvasLayer
class_name SkillPopup

## Bảng thông báo "nhận kỹ năng mới". Rương tự instantiate scene này khi mở nên
## level không phải đặt sẵn node UI nào; nội dung lấy từ Skills.CATALOG.

const APPEAR_DURATION = 0.3
const APPEAR_START_SCALE = Vector2(0.85, 0.85)

@onready var overlay: Control = $Overlay
@onready var shade: ColorRect = $Overlay/Shade
@onready var panel: PanelContainer = $Overlay/Center/Panel
@onready var icon: TextureRect = $Overlay/Center/Panel/VBox/Header/IconFrame/Icon
@onready var name_label: Label = $Overlay/Center/Panel/VBox/Header/Text/Name
@onready var key_label: Label = $Overlay/Center/Panel/VBox/Header/Text/Key
@onready var desc_label: Label = $Overlay/Center/Panel/VBox/Desc
@onready var continue_button: Button = $Overlay/Center/Panel/VBox/ContinueButton

var is_open := false


func _ready() -> void:
	# Popup phải chạy được khi SceneTree bị pause, nếu không sẽ không đóng lại được.
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false
	continue_button.pressed.connect(close)


## Hiện bảng thưởng và dừng game để người chơi kịp đọc mô tả kỹ năng.
func show_skill(skill_id: String) -> void:
	var info := Skills.get_info(skill_id)
	if info.is_empty():
		push_warning("Unknown skill id: %s" % skill_id)
		queue_free()
		return

	icon.texture = Skills.make_icon(skill_id)
	name_label.text = info["name"]
	key_label.text = info["key"]
	desc_label.text = info["description"]

	is_open = true
	overlay.visible = true
	get_tree().paused = true
	continue_button.grab_focus()
	_play_appear()


## Bảng nở ra từ giữa màn hình cho khớp với icon vừa bay lên khỏi rương.
func _play_appear() -> void:
	shade.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = APPEAR_START_SCALE

	# CenterContainer chỉ tính xong kích thước bảng sau một frame; phải có kích
	# thước thật thì mới đặt được tâm phóng to vào giữa bảng.
	await get_tree().process_frame
	if not is_open:
		return
	panel.pivot_offset = panel.size * 0.5

	# Tween gắn vào node này, mà node chạy cả khi tree pause nên vẫn chạy được.
	var tween := create_tween().set_parallel()
	tween.tween_property(shade, "modulate:a", 1.0, APPEAR_DURATION)
	tween.tween_property(panel, "modulate:a", 1.0, APPEAR_DURATION)
	tween.tween_property(panel, "scale", Vector2.ONE, APPEAR_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not is_open:
		return

	is_open = false
	get_tree().paused = false
	queue_free()


func _input(event: InputEvent) -> void:
	if not is_open:
		return

	# Chỉ nhận Space/Enter/ESC. Không nhận phím "jump" vì người chơi rất dễ đang
	# giữ mũi tên lên lúc chạm rương và popup sẽ tắt ngay khi vừa hiện.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
