extends Area2D

## Rương kho báu: player chạm vào là mở ra. Trạng thái đã mở được giữ ở
## GameState nên chết rồi hồi sinh ở save point rương vẫn đang mở.

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
