extends CharacterBody2D

const MEMBER_ID := "serelyn"
const SPEED := 180.0
const JUMP_VELOCITY := -320.0
const SLIDE_SPEED := 240.0
const SLIDE_DURATION := 0.4
const SLIDE_COLLISION_HEIGHT := 34.0
const LANDING_DUST_MIN_SPEED := 180.0
const DUST_HALF_SIZE := 16.0
const TALK_LINES := [
	["Asura", "Xin chào, Serelyn!"],
	["Asura", "Cậu có muốn gia nhập đội của mình không?"],
	["Serelyn", "Được chứ! Tớ gia nhập đội của cậu."],
]

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var talk_area: Area2D = $TalkArea
@onready var prompt: Label = $Prompt
@onready var dialog: Control = $DialogueLayer/Dialog
@onready var speaker_label: Label = $DialogueLayer/Dialog/Panel/Margin/Lines/Speaker
@onready var line_label: Label = $DialogueLayer/Dialog/Panel/Margin/Lines/Line
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var dust_scene = preload("res://nodes/effects/landing_dust.tscn")

var nearby_player: Node2D
var dialogue_open := false
var line_index := 0
var is_controlled := false
var is_dead := false
var is_hurt := false
var is_sliding := false
var slide_direction := 1.0
var slide_time_left := 0.0
var normal_collision_height := 0.0
var normal_collision_position := Vector2.ZERO
var was_on_floor := false
var last_fall_speed := 0.0


func _ready() -> void:
	talk_area.body_entered.connect(_on_body_entered)
	talk_area.body_exited.connect(_on_body_exited)
	dialog.visible = false
	prompt.visible = false
	body_collision.shape = body_collision.shape.duplicate()
	var capsule := body_collision.shape as CapsuleShape2D
	if capsule:
		normal_collision_height = capsule.height
		normal_collision_position = body_collision.position


func _physics_process(delta: float) -> void:
	if is_dead or get_tree().paused:
		return

	if is_sliding:
		var cancel_slide := Input.is_action_just_pressed("move_left") or \
			Input.is_action_just_pressed("move_right")
		if cancel_slide:
			stop_slide()
		else:
			slide_time_left -= delta
			velocity = Vector2(slide_direction * SLIDE_SPEED, 0.0)
			move_and_slide()
			if slide_time_left <= 0.0 or is_on_wall():
				stop_slide()
			return

	if not is_on_floor():
		velocity += get_gravity() * delta
		last_fall_speed = velocity.y

	var direction := Input.get_axis("move_left", "move_right") if is_controlled else 0.0
	if is_controlled and Input.is_action_just_pressed("slide") and is_on_floor():
		start_slide()
		return

	if is_controlled and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	velocity.x = direction * SPEED
	if direction != 0.0:
		sprite.flip_h = direction < 0.0
	move_and_slide()
	if not was_on_floor and is_on_floor() and last_fall_speed > LANDING_DUST_MIN_SPEED:
		spawn_landing_dust()
		last_fall_speed = 0.0
	was_on_floor = is_on_floor()
	_update_animation(direction)


func set_controlled(value: bool) -> void:
	is_controlled = value
	if value:
		add_to_group(&"player")
	else:
		remove_from_group(&"player")
		if is_sliding:
			stop_slide()
		velocity.x = 0.0
		_set_running(false)


func _set_running(value: bool) -> void:
	var animation := &"run" if value else &"idle"
	if sprite.animation != animation:
		sprite.play(animation)


func _update_animation(direction: float) -> void:
	var animation: StringName
	if not is_on_floor():
		animation = &"jump_up" if velocity.y < 0.0 else &"jump_down"
	else:
		animation = &"run" if direction != 0.0 else &"idle"

	if sprite.animation != animation:
		sprite.play(animation)


func start_slide() -> void:
	if not is_controlled:
		return

	is_sliding = true
	slide_time_left = SLIDE_DURATION
	slide_direction = -1.0 if sprite.flip_h else 1.0
	velocity = Vector2(slide_direction * SLIDE_SPEED, 0.0)
	set_slide_collision(true)
	sprite.play("slide")
	if is_on_floor():
		spawn_landing_dust()


func stop_slide() -> void:
	is_sliding = false
	slide_time_left = 0.0
	velocity.x = 0.0
	set_slide_collision(false)
	if not is_dead:
		sprite.play("idle")


func set_slide_collision(enabled: bool) -> void:
	var capsule := body_collision.shape as CapsuleShape2D
	if not capsule:
		return

	if enabled:
		capsule.height = SLIDE_COLLISION_HEIGHT
		body_collision.position.y = normal_collision_position.y + \
			(normal_collision_height - SLIDE_COLLISION_HEIGHT) * 0.5
	else:
		capsule.height = normal_collision_height
		body_collision.position = normal_collision_position


func spawn_landing_dust() -> void:
	var facing := -1 if sprite.flip_h else 1
	var dust: AnimatedSprite2D = dust_scene.instantiate()
	dust.flip_h = not sprite.flip_h
	get_parent().add_child(dust)
	# Đặt đáy ô bụi trùng với đáy capsule của Serelyn. Collision của Serelyn
	# thấp hơn Asura 16px nên dùng vị trí collision thay vì offset cố định của Asura.
	var ground_y := normal_collision_position.y + normal_collision_height * 0.5
	dust.global_position = global_position + Vector2(
		-facing * 10,
		ground_y - DUST_HALF_SIZE
	)


func take_hit() -> void:
	if is_hurt or is_dead:
		return
	is_hurt = true
	set_controlled(false)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	set_controlled(false)
	collision_layer = 0
	collision_mask = 0
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.reparent(get_tree().current_scene, true)
		camera.position_smoothing_enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or (event is InputEventKey and event.echo):
		return
	if GameState.is_game_over():
		return
	if dialogue_open:
		_next_line()
	elif is_instance_valid(nearby_player) and not get_tree().paused \
			and not GameState.has_party_member(MEMBER_ID):
		_start_dialogue()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	nearby_player = body
	prompt.visible = not GameState.has_party_member(MEMBER_ID)


func _on_body_exited(body: Node2D) -> void:
	if body != nearby_player:
		return
	nearby_player = null
	prompt.visible = false


func _start_dialogue() -> void:
	dialogue_open = true
	line_index = 0
	dialog.visible = true
	prompt.visible = false
	_show_line()
	get_tree().paused = true


func _next_line() -> void:
	line_index += 1
	if line_index >= TALK_LINES.size():
		dialogue_open = false
		dialog.visible = false
		get_tree().paused = false
		GameState.recruit_party_member(MEMBER_ID)
		return
	_show_line()


func _show_line() -> void:
	speaker_label.text = TALK_LINES[line_index][0]
	line_label.text = TALK_LINES[line_index][1]
