extends Node2D
## Bẫy giọt độc: bám dưới trần, cứ một lúc lại tụ thành một giọt rồi nhỏ xuống.
## Giọt đang rơi chạm vào player là chết. Đặt gốc node sát mép dưới của trần.

const TOXIC_SMOKE_SCENE := preload("res://nodes/effects/spitter_slime_smoke.tscn")
const HIT_EFFECT_SCENE := preload("res://nodes/effects/hit_effect.tscn")
const RELEASE_OFFSET := Vector2(0.0, 15.0)
## Khoảng từ tâm tới đầu giọt, để đầu giọt chạm sàn chứ không phải tâm.
const DROP_TIP_LENGTH := 6.0
## Đèn phập phồng nhẹ khi rơi; tắt dần lúc vỡ.
const GLOW_ENERGY := 1.0
const GLOW_PULSE := 0.18
const GLOW_FADE_DURATION := 0.25

enum State { WAITING, FORMING, FALLING, SPLASHING }

## Thời gian nghỉ giữa lúc giọt trước vỡ và lúc giọt sau bắt đầu tụ.
@export_range(0.0, 10.0, 0.1, "or_greater") var drip_interval := 1.4
## Trễ trước giọt đầu tiên. Đặt khác nhau để các bẫy cạnh nhau nhỏ so le.
@export_range(0.0, 10.0, 0.1, "or_greater") var start_delay := 0.0
## Thời gian giọt tụ lại dưới trần trước khi rơi: đây là lúc báo hiệu cho người chơi.
@export_range(0.05, 5.0, 0.05, "or_greater") var form_duration := 0.7
@export var gravity := 620.0
@export var max_fall_speed := 520.0
## Rơi quá xa mà không gặp sàn thì giọt tự vỡ.
@export var max_fall_distance := 1024.0
@export_flags_2d_physics var floor_collision_mask := 1
## Chạm sàn thì toả khói độc như đạn của spitter-slime.
@export var spawn_toxic_smoke := true

@onready var source: AnimatedSprite2D = $Source
@onready var drop: Node2D = $Drop
@onready var animated_sprite: AnimatedSprite2D = $Drop/AnimatedSprite2D
@onready var glow: PointLight2D = $Drop/Glow
@onready var killzone: Area2D = $Killzone

var _state := State.WAITING
var _time_left := 0.0
var _state_time := 0.0
var _fall_speed := 0.0
var _glow_tween: Tween


func _ready() -> void:
	drop.visible = false
	glow.energy = 0.0
	killzone.monitoring = false
	source.animation_finished.connect(_on_source_animation_finished)
	_time_left = start_delay


func _physics_process(delta: float) -> void:
	match _state:
		State.WAITING:
			_time_left -= delta
			if _time_left <= 0.0:
				_start_forming()
		State.FORMING:
			_form(delta)
		State.FALLING:
			_fall(delta)


## Killzone hỏi hàm này: chỉ giọt đang rơi mới gây chết.
func should_ignore_player_damage(_player: Node2D) -> bool:
	return _state != State.FALLING


## Killzone gọi khi giọt trúng player: giọt vỡ ngay trên người, không toả khói.
func on_player_touched(player: Node2D) -> void:
	_spawn_hit_effect(player)
	await _splash(false)


func _start_forming() -> void:
	_state = State.FORMING
	_state_time = 0.0
	if _glow_tween:
		_glow_tween.kill()
	drop.position = RELEASE_OFFSET
	drop.visible = true
	animated_sprite.hide()
	# Vệt nhớt trĩu dần theo đúng tiến độ tụ giọt, nên tự đặt frame thay vì play().
	source.animation = &"swell"
	source.pause()
	source.frame = 0


func _form(delta: float) -> void:
	_state_time += delta
	var progress := clampf(_state_time / maxf(form_duration, 0.01), 0.0, 1.0)
	glow.energy = GLOW_ENERGY * progress
	var swell_frames := source.sprite_frames.get_frame_count(&"swell")
	source.frame = mini(int(progress * swell_frames), swell_frames - 1)
	if progress >= 1.0:
		_start_falling()


func _start_falling() -> void:
	_state = State.FALLING
	_state_time = 0.0
	animated_sprite.show()
	animated_sprite.play(&"fly")
	_fall_speed = 0.0
	killzone.position = drop.position
	killzone.set_deferred("monitoring", true)
	# Giọt vừa đứt: sợi nhớt co giật lên rồi trở lại nhịp phập phồng.
	source.play(&"release")


func _fall(delta: float) -> void:
	_state_time += delta
	_fall_speed = minf(_fall_speed + gravity * delta, max_fall_speed)
	glow.energy = GLOW_ENERGY + GLOW_PULSE * sin(_state_time * 18.0)

	var motion := Vector2.DOWN * _fall_speed * delta
	var from := drop.global_position
	var query := PhysicsRayQueryParameters2D.create(
		from, from + motion + Vector2.DOWN * DROP_TIP_LENGTH, floor_collision_mask
	)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_position: Vector2 = hit["position"]
		drop.global_position = hit_position
		killzone.position = drop.position
		_splash(true)
		return

	drop.global_position = from + motion
	killzone.position = drop.position
	if max_fall_distance > 0.0 and drop.position.y >= max_fall_distance:
		_splash(false)


func _on_source_animation_finished() -> void:
	if source.animation == &"release":
		source.play(&"idle")


## Giọt vỡ toé thành các giọt nhỏ rồi bẫy nghỉ một nhịp trước giọt kế tiếp.
func _splash(on_floor: bool) -> void:
	if _state == State.SPLASHING:
		return

	_state = State.SPLASHING
	killzone.set_deferred("monitoring", false)
	if on_floor and spawn_toxic_smoke:
		_spawn_toxic_smoke()

	animated_sprite.play(&"pop")
	_glow_tween = create_tween()
	_glow_tween.tween_property(glow, "energy", 0.0, GLOW_FADE_DURATION)
	await animated_sprite.animation_finished

	drop.visible = false
	_time_left = drip_interval
	_state = State.WAITING


func _spawn_toxic_smoke() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var smoke := TOXIC_SMOKE_SCENE.instantiate() as Node2D
	if smoke == null:
		return
	current_scene.add_child(smoke)
	smoke.global_position = drop.global_position


## Cùng hiệu ứng hit.png như đạn spitter-slime trúng player.
func _spawn_hit_effect(player: Node2D) -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null or not is_instance_valid(player):
		return
	var effect: Node2D = HIT_EFFECT_SCENE.instantiate()
	current_scene.add_child(effect)
	effect.global_position = player.global_position
