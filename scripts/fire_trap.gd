extends Area2D

# Bỏ qua đoạn đầu file tiếng lửa để tiếng khớp sớm hơn với lúc bẫy hiện ra
const APPEAR_SOUND_OFFSET = 0.2

## Bật lên thì bẫy cháy sẵn từ đầu màn thay vì nấp chờ người chơi đi tới.
## Dùng cho những dàn lửa đặt làm chướng ngại nhìn thấy trước, không phải bẫy bất ngờ.
@export var always_active := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var damage_shape: CollisionShape2D = $CollisionShape2D
@onready var trigger_area: Area2D = $TriggerArea
@onready var appear_sound: AudioStreamPlayer2D = $AppearSound


func _ready() -> void:
	body_entered.connect(_on_damage_body_entered)

	if always_active:
		# Không cần vùng kích hoạt nữa, và cũng không phát tiếng lửa: cả dàn bẫy
		# sẽ kêu cùng một lúc lúc vào màn.
		trigger_area.set_deferred("monitoring", false)
		_activate(false)
		return

	trigger_area.body_entered.connect(_on_trigger_body_entered)
	animated_sprite.visible = false


func _on_trigger_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	trigger_area.set_deferred("monitoring", false)
	_activate(true)


func _activate(play_appear_sound: bool) -> void:
	animated_sprite.visible = true
	if play_appear_sound:
		appear_sound.play(APPEAR_SOUND_OFFSET)
	damage_shape.set_deferred("disabled", false)
	set_deferred("monitoring", true)


func _on_damage_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var game_state := get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("trigger_game_over"):
			game_state.trigger_game_over(body)
