extends Node2D
class_name CharacterTransformEffect

signal finished

const DURATION := 0.64
const FRAME_COUNT := 8
# Khung thứ 7 (đếm từ 1) là lúc nhân vật hiện trở lại.
const REVEAL_FRAME := 6
const REVEAL_BRIGHTNESS := 1.4
const REVEAL_FADE_DURATION := 0.18
# Mỗi ô 100x200; tâm vòng teleport ở (50, 150), không phải tâm ô.
const RING_CENTER_OFFSET := Vector2(0.0, -50.0)
const RING_DIAMETER := 100.0
const BODY_COVERAGE := 1.25

@onready var sprite: Sprite2D = $Sprite2D
@onready var teleport_sound: AudioStreamPlayer2D = $TeleportSound

var _elapsed := 0.0
var _actor: CharacterBody2D
var _body_shape: CollisionShape2D
var _character_sprite: AnimatedSprite2D
var _revealed := false


func play(actor: CharacterBody2D) -> void:
	_actor = actor
	_body_shape = actor.get_node("CollisionShape2D") as CollisionShape2D
	_character_sprite = actor.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var capsule := _body_shape.shape as CapsuleShape2D
	var effect_scale := capsule.height * BODY_COVERAGE / RING_DIAMETER
	sprite.scale = Vector2.ONE * effect_scale
	sprite.position = RING_CENTER_OFFSET * effect_scale
	_elapsed = 0.0
	_revealed = false
	_character_sprite.hide()
	sprite.frame = 0
	sprite.modulate = Color.WHITE
	_follow_actor()
	# Âm thanh dài hơn animation teleport nên để nó sống độc lập đến khi phát xong.
	teleport_sound.reparent(_actor, true)
	teleport_sound.finished.connect(teleport_sound.queue_free)
	teleport_sound.play()
	set_process(true)


func _ready() -> void:
	# Giữ màu gốc của hiệu ứng, không nhận modulate làm tối của nhân vật.
	top_level = true
	set_process(false)


func _process(delta: float) -> void:
	if not is_instance_valid(_actor) or not _actor.is_visible_in_tree():
		if is_instance_valid(_character_sprite):
			_character_sprite.show()
		finished.emit()
		queue_free()
		return
	_follow_actor()
	_elapsed += delta
	var progress := clampf(_elapsed / DURATION, 0.0, 1.0)
	sprite.frame = mini(int(progress * FRAME_COUNT), FRAME_COUNT - 1)
	if sprite.frame >= REVEAL_FRAME and not _revealed:
		_reveal_actor()
	# Giữ sáng rõ lúc vòng bung ra, chỉ làm mờ ở hai khung cuối.
	sprite.modulate.a = 1.0 - clampf((progress - 0.75) / 0.25, 0.0, 1.0)

	if _elapsed >= DURATION:
		if not _revealed:
			_reveal_actor()
		finished.emit()
		queue_free()


func _reveal_actor() -> void:
	_revealed = true
	_character_sprite.modulate = Color(REVEAL_BRIGHTNESS, REVEAL_BRIGHTNESS, REVEAL_BRIGHTNESS)
	_character_sprite.show()
	_character_sprite.create_tween().tween_property(
		_character_sprite, "modulate", Color.WHITE, REVEAL_FADE_DURATION
	)


func _follow_actor() -> void:
	global_transform = _actor.global_transform
	global_position = _body_shape.global_position
