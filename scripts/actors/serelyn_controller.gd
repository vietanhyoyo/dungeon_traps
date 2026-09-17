extends CharacterBody2D

const MEMBER_ID := "serelyn"
const SPEED := 180.0
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

var nearby_player: Node2D
var dialogue_open := false
var line_index := 0
var is_controlled := false
var is_dead := false
var is_hurt := false


func _ready() -> void:
	talk_area.body_entered.connect(_on_body_entered)
	talk_area.body_exited.connect(_on_body_exited)
	dialog.visible = false
	prompt.visible = false


func _physics_process(delta: float) -> void:
	if is_dead or get_tree().paused:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var direction := Input.get_axis("move_left", "move_right") if is_controlled else 0.0
	velocity.x = direction * SPEED
	if direction != 0.0:
		sprite.flip_h = direction < 0.0
	_set_running(direction != 0.0 and is_on_floor())
	move_and_slide()


func set_controlled(value: bool) -> void:
	is_controlled = value
	if value:
		add_to_group(&"player")
	else:
		remove_from_group(&"player")
		velocity.x = 0.0
		_set_running(false)


func _set_running(value: bool) -> void:
	var animation := &"run" if value else &"idle"
	if sprite.animation != animation:
		sprite.play(animation)


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
