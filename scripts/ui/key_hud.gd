extends CanvasLayer
class_name KeyHUD

## Ô chìa khoá ở góc trái trên. Chỉ hiện khi người chơi đang cầm chìa
## `key_id` của màn hiện tại.

@export var key_id := "crystal_key"

@onready var slot: PanelContainer = $Slot
@onready var key_anchor: Control = $Slot/KeyAnchor
@onready var crystal_key: CrystalKey = $Slot/KeyAnchor/CrystalKey
@onready var pickup_sound: AudioStreamPlayer = $PickupSound

var _pop_tween: Tween


func _ready() -> void:
	add_to_group(&"key_hud")
	GameState.keys_changed.connect(_on_keys_changed)
	# Hồi sinh ở save point sau khi đã nhặt chìa: hiện ngay, không cần hiệu ứng.
	slot.visible = GameState.has_key(key_id)


## Toạ độ của ô chìa khoá trong thế giới game, để hiệu ứng chìa bay ra / bay
## vào khớp đúng vị trí đang hiển thị trên màn hình dù camera đang di chuyển.
func get_slot_world_position() -> Vector2:
	var screen_position := key_anchor.get_global_transform_with_canvas() * crystal_key.position
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


## Gọi khi chìa vừa bay tới ô: hiện ô với hiệu ứng nảy.
func receive_key() -> void:
	if not GameState.has_key(key_id):
		return
	slot.visible = true
	slot.pivot_offset = slot.size * 0.5
	slot.scale = Vector2.ONE * 1.6
	pickup_sound.play()
	if _pop_tween != null:
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.tween_property(slot, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Chìa rời khỏi ô để bay vào cửa.
func release_key() -> void:
	if _pop_tween != null:
		_pop_tween.kill()
	slot.visible = false


func _on_keys_changed() -> void:
	# Chỉ tự ẩn ở đây. Việc hiện ô do receive_key() lo, để chờ chìa bay tới.
	if not GameState.has_key(key_id):
		slot.visible = false
