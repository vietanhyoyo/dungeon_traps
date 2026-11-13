extends Node2D
class_name CrystalKey

## Chìa khoá pha lê. Lúc vừa rơi ra từ pha lê thì có hào quang (quầng sáng
## nhấp nháy, tia sáng xoay quanh, hạt sáng bay lên). Nhặt rồi thì tắt hào
## quang: chìa trên HUD và lúc tra vào cửa chỉ là chìa thường.

const PULSE_SPEED := 3.2
const RAY_SPIN_SPEED := 0.9
const WHOOSH_SOUND := preload("res://assets/sounds/mixkit-short-wind-swoosh-1461.wav")
## Vẽ đè lên tilemap, cửa và nhân vật trong lúc bay.
const FLYING_Z_INDEX := 50
const HUD_FLY_DURATION := 0.75
## Bằng scale của chìa trong KeyHUD để lúc chạm ô không bị giật kích thước.
const HUD_KEY_SCALE := 1.25

## Tắt khi đặt trong CanvasLayer (HUD): PointLight2D chỉ có ý nghĩa ngoài thế giới.
@export var world_light := true
## Mức sáng gốc của hào quang; burst() đẩy tạm lên rồi trả về mức này.
@export var glow_strength := 1.0
## Tắt thì không có hào quang và chìa đứng yên (chìa đã nhặt).
@export var glowing := true

@onready var halo: Sprite2D = $Halo
@onready var rays: Sprite2D = $Rays
@onready var sparkles: CPUParticles2D = $Sparkles
@onready var key_sprite: Sprite2D = $Key
@onready var light: PointLight2D = $Light

var _time := 0.0
var _burst := 0.0
## 0..1, nhân vào độ sáng của hào quang; tween về 0 để tắt dần.
var _glow_level := 1.0
var _glow_tween: Tween


func _ready() -> void:
	light.enabled = world_light
	_glow_level = 1.0 if glowing else 0.0
	sparkles.emitting = glowing
	_apply_glow_visibility()


func _process(delta: float) -> void:
	_time += delta
	_burst = maxf(_burst - delta * 1.6, 0.0)
	var pulse := 0.5 + 0.5 * sin(_time * PULSE_SPEED)
	var strength := (glow_strength + _burst) * _glow_level
	_apply_glow_visibility()

	halo.scale = Vector2.ONE * (0.85 + 0.25 * pulse + 0.6 * _burst)
	halo.modulate.a = clampf((0.55 + 0.35 * pulse) * strength, 0.0, 1.0)
	rays.rotation += RAY_SPIN_SPEED * delta
	rays.scale = Vector2.ONE * (0.9 + 0.15 * pulse + 0.8 * _burst)
	rays.modulate.a = clampf((0.35 + 0.3 * pulse) * strength, 0.0, 1.0)
	key_sprite.position.y = (-1.0 + sin(_time * 2.2)) * _glow_level
	light.energy = (0.55 + 0.35 * pulse) * strength
	light.texture_scale = 0.9 + 0.2 * pulse + 0.8 * _burst


## Loé sáng mạnh trong chốc lát (lúc nhặt được hoặc lúc khớp vào ổ khoá).
func burst(amount := 1.5) -> void:
	if not glowing:
		return
	_burst = maxf(_burst, amount)
	sparkles.restart()


## Bật / tắt hào quang, tắt dần trong `fade_time` giây.
func set_glowing(enabled: bool, fade_time := 0.0) -> void:
	glowing = enabled
	sparkles.emitting = enabled
	if _glow_tween != null:
		_glow_tween.kill()
	var target := 1.0 if enabled else 0.0
	if fade_time <= 0.0:
		_glow_level = target
		_apply_glow_visibility()
		return
	_glow_tween = create_tween()
	_glow_tween.tween_property(self, "_glow_level", target, fade_time)


func _apply_glow_visibility() -> void:
	var visible_glow := _glow_level > 0.01
	halo.visible = visible_glow
	rays.visible = visible_glow
	light.visible = visible_glow and world_light


## Chìa trồi lên khỏi chỗ pha lê vừa vỡ, nảy nhẹ và loé sáng.
func play_reveal(rise := 28.0) -> void:
	z_index = FLYING_Z_INDEX
	scale = Vector2.ONE * 0.3
	burst(2.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise, 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * 1.4, 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished


## Bay theo đường cong tới `get_target.call()` (toạ độ thế giới). Đích được tính
## lại mỗi khung hình nên vẫn trúng khi đích di chuyển trên màn hình (ô HUD
## trong lúc camera chạy). `arc_height` âm là vòng lên trên.
func fly_to(get_target: Callable, duration: float, end_scale: float, arc_height := -40.0) -> void:
	z_index = FLYING_Z_INDEX
	set_trail(glowing)
	_play_whoosh()
	var start := global_position
	var start_scale := scale.x
	var tween := create_tween()
	tween.tween_method(
		func(t: float) -> void:
			var target: Vector2 = get_target.call()
			var control := (start + target) * 0.5 + Vector2(0.0, arc_height)
			var eased := ease(t, -1.8)
			# Đường cong Bezier bậc hai: start -> control -> target.
			global_position = start.lerp(control, eased).lerp(control.lerp(target, eased), eased)
			scale = Vector2.ONE * lerpf(start_scale, end_scale, eased)
			rotation = sin(t * PI) * 0.35,
		0.0, 1.0, duration
	)
	await tween.finished
	set_trail(false)


## Trồi lên rồi bay vào ô chìa khoá trên HUD, sau đó tự xoá. Chạy trên chính
## node chìa để không phụ thuộc vào pha lê đã bị xoá.
func collect_into_hud() -> void:
	await play_reveal()
	await get_tree().create_timer(0.25).timeout
	var hud := get_tree().get_first_node_in_group(&"key_hud") as KeyHUD
	if hud != null:
		# Đã nhặt: hào quang tắt dần trên đường bay về HUD.
		set_glowing(false, HUD_FLY_DURATION)
		await fly_to(hud.get_slot_world_position, HUD_FLY_DURATION, world_scale_for_hud())
		hud.receive_key()
	queue_free()


## Scale trong thế giới để chìa trông bằng chìa trên HUD (camera đang zoom).
func world_scale_for_hud() -> float:
	return HUD_KEY_SCALE / maxf(get_viewport().get_canvas_transform().get_scale().x, 0.01)


func _play_whoosh() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = WHOOSH_SOUND
	player.bus = &"SFX"
	player.volume_db = -4.0
	# Gắn vào scene hiện tại để chìa bị xoá giữa chừng không cắt ngang tiếng.
	get_tree().current_scene.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Bật / tắt việc thả hạt sáng. Khi đang bay, hạt nằm lại phía sau tạo thành
## vệt sáng nên phải dùng toạ độ thế giới thay vì toạ độ cục bộ.
func set_trail(enabled: bool) -> void:
	sparkles.local_coords = not enabled
	sparkles.amount = 24 if enabled else 12
