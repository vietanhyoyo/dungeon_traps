extends CharacterBody2D

## Gentle bat: dơi hiền treo ngược trên trần và ngủ say, không bay, không đuổi,
## không gây sát thương. Gốc node là điểm chân bám trần: đặt node sát mép dưới
## của ô trần là dơi treo đúng chỗ. Player vẫn chém chết được như bat thường.

const HIT_FLASH_COUNT := 3
const HIT_FLASH_ON_DURATION := 0.04
const HIT_FLASH_OFF_DURATION := 0.035
const DEFEAT_SOUND := preload("res://assets/sounds/freesound_community-poof-80161.mp3")
const DEFEAT_SOUND_OFFSET := 0.5
## Chữ z tắt dần khi dơi bị chém, thay vì biến mất cái bụp.
const ZZZ_FADE_DURATION := 0.15

var is_dead := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var zzz: AnimatedSprite2D = $Zzz


func _ready() -> void:
	# Material riêng cho từng con để hiệu ứng trúng đòn không lây sang con khác.
	if animated_sprite.material:
		animated_sprite.material = animated_sprite.material.duplicate()
	# Lệch nhịp chữ z giữa các con treo cạnh nhau để không thở đều như một.
	zzz.frame = randi() % zzz.sprite_frames.get_frame_count(&"default")


## Player chém trúng. asura_controller.hit_enemy() gọi die() cho mọi thứ trong
## group "enemy" không có take_damage().
func die() -> void:
	if is_dead:
		return

	is_dead = true
	collision_shape.set_deferred("disabled", true)
	var zzz_tween := create_tween()
	zzz_tween.tween_property(zzz, "modulate:a", 0.0, ZZZ_FADE_DURATION)
	# Animation chết dùng chung với bat thường (tư thế bay, mắt chữ X rồi tan khói).
	animated_sprite.play(&"death")
	_play_defeat_sound()
	await _play_hit_flash()
	if not is_inside_tree():
		return

	await animated_sprite.animation_finished
	if is_inside_tree():
		queue_free()


func _play_defeat_sound() -> void:
	# Player âm thanh nằm ở scene để vẫn phát hết tiếng sau khi dơi bị xoá.
	var sound_player := AudioStreamPlayer2D.new()
	sound_player.stream = DEFEAT_SOUND
	sound_player.bus = &"SFX"
	sound_player.global_position = global_position
	get_tree().current_scene.add_child(sound_player)
	sound_player.finished.connect(sound_player.queue_free)
	sound_player.play(DEFEAT_SOUND_OFFSET)


func _play_hit_flash() -> void:
	if not animated_sprite.material is ShaderMaterial:
		return

	var flash_material := animated_sprite.material as ShaderMaterial
	for flash_index in HIT_FLASH_COUNT:
		flash_material.set_shader_parameter("flash_amount", 1.0)
		await get_tree().create_timer(HIT_FLASH_ON_DURATION, false).timeout
		flash_material.set_shader_parameter("flash_amount", 0.0)

		if flash_index < HIT_FLASH_COUNT - 1:
			await get_tree().create_timer(HIT_FLASH_OFF_DURATION, false).timeout
