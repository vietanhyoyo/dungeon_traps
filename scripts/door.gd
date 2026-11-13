extends Node2D

const CRYSTAL_KEY_SCENE: PackedScene = preload("res://nodes/items/crystal_key.tscn")
const PROMPT_FONT := preload("res://assets/fonts/PixelOperator8-Bold.ttf")
const INSERT_SOUND := preload("res://assets/sounds/tap.wav")
const UNLOCK_SOUND := preload("res://assets/sounds/move_boulder.ogg")
const KEY_FLY_DURATION := 0.9
const KEY_SETTLE_DELAY := 0.45
const PROMPT_OFFSET := Vector2(0.0, -28.0)
## Người chơi cách tâm cửa (theo trục x) không quá bấy nhiêu px là "ở giữa cửa".
const DOOR_CENTER_TOLERANCE := 6.0

@export var next_scene_path: String
## Để trống thì cửa tự mở khi người chơi lại gần. Đặt id thì phải đang cầm chìa
## đó, đứng gần cửa và nhấn phím tấn công (C) để tra chìa vào ổ. Cửa mở xong
## không tự chuyển màn: người chơi phải đi / lướt vào giữa cửa mới qua màn.
@export var required_key_id := ""
## Vị trí ổ khoá so với gốc cửa (tâm sprite).
@export var key_slot_offset := Vector2.ZERO

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var open_area: Area2D = $OpenArea
@onready var pass_area: Area2D = $PassArea

var is_transitioning := false
var is_opening := false
var is_open := false
var player_in_pass_area: Node2D
var player_in_open_area: Node2D

var _is_inserting_key := false
var _prompt: Label
var _prompt_time := 0.0


func _ready() -> void:
	open_area.body_entered.connect(_on_open_area_body_entered)
	open_area.body_exited.connect(_on_open_area_body_exited)
	pass_area.body_entered.connect(_on_pass_area_body_entered)
	pass_area.body_exited.connect(_on_pass_area_body_exited)
	animated_sprite.animation_finished.connect(_on_animated_sprite_animation_finished)

	if _needs_key():
		# Hồi sinh ở save point sau khi đã tra chìa: cửa vẫn mở sẵn.
		if GameState.is_key_used(required_key_id):
			_show_fully_open()
		else:
			_create_prompt()
	set_process(_needs_key())


func _process(delta: float) -> void:
	_update_prompt(delta)
	# Cửa đã mở: người chơi phải tự bước đi và tới giữa cửa mới chuyển màn.
	# Đứng yên sẵn ở giữa lúc cửa mở xong thì chưa tính, phải đi hoặc lướt.
	var player := player_in_pass_area as CharacterBody2D
	if is_open and not _is_inserting_key and is_instance_valid(player) \
			and player.is_in_group("player") and not get_tree().paused \
			and absf(player.velocity.x) > 1.0 \
			and absf(player.global_position.x - global_position.x) <= DOOR_CENTER_TOLERANCE:
		_go_to_next_scene()


func _update_prompt(delta: float) -> void:
	if _prompt == null:
		return
	_prompt_time += delta
	var show_prompt := is_instance_valid(player_in_open_area) and not _is_inserting_key \
		and not is_open and not is_opening and GameState.has_key(required_key_id)
	_prompt.visible = show_prompt
	if show_prompt:
		_prompt.position = PROMPT_OFFSET - _prompt.size * 0.5 \
			+ Vector2(0.0, sin(_prompt_time * 5.0) * 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if not _needs_key() or not event.is_action_pressed("attack") \
			or (event is InputEventKey and event.echo):
		return
	if is_open or is_opening or _is_inserting_key or get_tree().paused \
			or GameState.is_game_over() or not is_instance_valid(player_in_open_area) \
			or not GameState.has_key(required_key_id):
		return

	# Nuốt phím C để nhân vật không vung kiếm / bắn tên cùng lúc.
	get_viewport().set_input_as_handled()
	_insert_key(player_in_open_area)


func _needs_key() -> bool:
	return not required_key_id.is_empty()


func _on_open_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or is_open or is_opening:
		return

	if _needs_key():
		player_in_open_area = body
		return

	is_opening = true
	animated_sprite.play("open")


func _on_open_area_body_exited(body: Node2D) -> void:
	# Trong lúc tra chìa nhân vật bị tắt điều khiển; giữ nguyên tham chiếu.
	if body == player_in_open_area and not _is_inserting_key:
		player_in_open_area = null


func _on_pass_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	player_in_pass_area = body

	# Cửa cần chìa chỉ chuyển màn khi người chơi đi vào giữa cửa (xem _process).
	if is_open and not _needs_key():
		_go_to_next_scene()


func _on_pass_area_body_exited(body: Node2D) -> void:
	if body == player_in_pass_area:
		player_in_pass_area = null


func _on_animated_sprite_animation_finished() -> void:
	if animated_sprite.animation != &"open":
		return

	is_opening = false
	is_open = true

	# Cửa cần chìa: chờ người chơi tự bước vào (xem _process).
	if not _needs_key() and is_instance_valid(player_in_pass_area):
		_go_to_next_scene()


func _insert_key(player: Node2D) -> void:
	_is_inserting_key = true
	add_to_group(&"cutscene_lock")
	_set_player_locked(player, true)

	var hud := get_tree().get_first_node_in_group(&"key_hud") as KeyHUD
	var key := CRYSTAL_KEY_SCENE.instantiate() as CrystalKey
	# Chìa đã nhặt thì không còn hào quang.
	key.glowing = false
	# Con của cửa và thêm sau sprite nên được vẽ đè lên mặt cửa.
	add_child(key)
	if hud != null:
		key.global_position = hud.get_slot_world_position()
		key.scale = Vector2.ONE * key.world_scale_for_hud()
		hud.release_key()
	else:
		key.global_position = player.global_position + Vector2(0.0, -24.0)

	var slot_position := to_global(key_slot_offset)
	await key.fly_to(func() -> Vector2: return slot_position, KEY_FLY_DURATION, 1.0, -56.0)
	key.global_position = slot_position
	key.rotation = 0.0
	# Chìa đã nằm trong ổ: đánh dấu đã dùng trước khi mở để hồi sinh vẫn mở sẵn.
	GameState.use_key(required_key_id)
	_play_sound(INSERT_SOUND)
	_flash_door()

	await get_tree().create_timer(KEY_SETTLE_DELAY).timeout
	_play_sound(UNLOCK_SOUND)
	is_opening = true
	animated_sprite.play("open")
	var fade := key.create_tween().set_parallel(true)
	fade.tween_property(key, "modulate:a", 0.0, 0.5)
	fade.tween_property(key, "scale", Vector2.ONE * 1.6, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.chain().tween_callback(key.queue_free)

	await animated_sprite.animation_finished
	_set_player_locked(player, false)
	remove_from_group(&"cutscene_lock")
	_is_inserting_key = false


func _flash_door() -> void:
	var tween := animated_sprite.create_tween()
	animated_sprite.modulate = Color(1.8, 2.1, 2.6)
	tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_player_locked(player: Node2D, locked: bool) -> void:
	if not is_instance_valid(player) or not player.has_method("set_controlled"):
		return
	player.call("set_controlled", not locked)
	if locked:
		var sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite != null and sprite.sprite_frames.has_animation(&"idle"):
			sprite.play(&"idle")


func _show_fully_open() -> void:
	animated_sprite.play(&"open")
	animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count(&"open") - 1
	animated_sprite.pause()
	is_open = true


func _create_prompt() -> void:
	_prompt = Label.new()
	_prompt.text = "C"
	_prompt.visible = false
	_prompt.z_index = 20
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_override(&"font", PROMPT_FONT)
	_prompt.add_theme_font_size_override(&"font_size", 8)
	_prompt.add_theme_color_override(&"font_color", Color(0.75, 0.9, 1.0))
	_prompt.add_theme_color_override(&"font_outline_color", Color(0.05, 0.08, 0.18))
	_prompt.add_theme_constant_override(&"outline_size", 4)
	add_child(_prompt)


func _play_sound(stream: AudioStream) -> void:
	var player := AudioStreamPlayer2D.new()
	# move_boulder.ogg được import với loop=true cho quả cầu đá lăn. Cửa chỉ
	# cần phát một lần, nên tắt lặp trên một bản sao để không ảnh hưởng chỗ khác.
	if stream is AudioStreamOggVorbis:
		var once := stream.duplicate() as AudioStreamOggVorbis
		once.loop = false
		stream = once
	player.stream = stream
	player.bus = &"SFX"
	add_child(player)
	player.global_position = to_global(key_slot_offset)
	player.finished.connect(player.queue_free)
	player.play()


func _go_to_next_scene() -> void:
	if is_transitioning or _is_inserting_key:
		return

	is_transitioning = true

	# Qua được cửa là hoàn thành màn. Báo trước khi đổi scene, vì GameState cần
	# biết màn nào vừa xong mà _get_current_scene_path() chỉ đúng ở thời điểm này.
	GameState.complete_level()

	# Cửa cuối chưa trỏ đi đâu thì dừng ở đây, nhưng màn vẫn được tính là xong.
	if next_scene_path.is_empty():
		return

	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file(next_scene_path)
