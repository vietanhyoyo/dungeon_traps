extends Node2D

## Place the trap on solid floor. This is the height of the hanging stone's center.
@export_range(72.0, 360.0, 1.0) var drop_height := 120.0
@export_range(0.15, 2.0, 0.05) var warning_duration := 0.55

const GRAVITY := 1020.0

@onready var stone: CharacterBody2D = $Stone
@onready var stone_sprite: Sprite2D = $Stone/Sprite2D
@onready var winch: Sprite2D = $Winch
@onready var rope: Line2D = $Rope
@onready var dust: CPUParticles2D = $Dust

var warning_remaining := 0.0
var speed := 0.0
var triggered := false


func _ready() -> void:
	stone.position.y = -drop_height
	winch.position.y = -drop_height - 34.0
	var post: Sprite2D = $Post
	post.position.y = winch.position.y
	post.region_rect.size.y = -post.position.y
	$Brace.position.y = winch.position.y + 4.0
	rope.points = PackedVector2Array([winch.position + Vector2(0, 3), stone.position])
	$Trigger.body_entered.connect(_on_trigger_body_entered)
	set_physics_process(false)


func _on_trigger_body_entered(body: Node2D) -> void:
	if triggered or not body.is_in_group(&"player") or GameState.is_game_over():
		return
	triggered = true
	warning_remaining = warning_duration
	$Trigger.set_deferred("monitoring", false)
	$ReleaseSound.play()
	dust.position = stone.position + Vector2.DOWN * 18.0
	dust.restart()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if GameState.is_game_over():
		set_physics_process(false)
		return

	if warning_remaining > 0.0:
		warning_remaining -= delta
		stone_sprite.position.x = roundf(sin(warning_remaining * 70.0) * 2.0)
		if warning_remaining <= 0.0:
			stone_sprite.position.x = 0.0
			rope.hide()
		return

	speed += GRAVITY * delta
	var collision := stone.move_and_collide(Vector2.DOWN * speed * delta)
	if collision:
		var body := collision.get_collider() as Node2D
		if body and body.is_in_group(&"player"):
			GameState.trigger_game_over(body)
		_shatter()
	elif stone.position.y >= 24.0:
		# A trap placed over a gap must still expire.
		_shatter()


func _shatter() -> void:
	set_physics_process(false)
	stone.hide()
	dust.position = stone.position + Vector2.DOWN * 10.0
	dust.restart()
	$ImpactSound.position = stone.position
	$ImpactSound.play()
