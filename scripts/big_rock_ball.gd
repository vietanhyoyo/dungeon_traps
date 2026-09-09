extends Node2D

## Bẫy cầu đá: dấu khắc trên nền chính là bàn đạp, player giẫm lên thì quả cầu
## đá rơi xuống, vỡ tan rồi nằm lại luôn trên nền.
## Đặt node ngay tâm dấu khắc, rồi kéo hai Marker2D để chỉnh đường rơi.

@export var gravity := 2500.0
@export var max_fall_speed := 1800.0
## Bật nếu muốn quả cầu đã nằm vẫn giết player khi chạm phải. Cẩn thận: quả cầu
## rộng 64px mà player chỉ nhảy cao được 52px, nên ở hành lang hẹp nó sẽ thành
## bức tường chết không đi qua được.
@export var deadly_after_landing := false

@onready var marker: Sprite2D = $Marker
@onready var trigger_area: Area2D = $TriggerArea
# Kéo hai Marker2D này trong editor để chỉnh đường rơi của quả cầu.
# SpawnPoint là nơi quả cầu hiện ra (đặt sát trần), LandPoint là nơi nó đáp
# xuống và nằm lại. LandPoint có sẵn một ảnh mờ hình quả cầu để canh cho dễ;
# ảnh đó tự ẩn lúc chạy game.
@onready var spawn_point: Marker2D = $SpawnPoint
@onready var land_point: Marker2D = $LandPoint
@onready var land_preview: Sprite2D = $LandPoint/Preview
@onready var ball: Node2D = $Ball
@onready var animated_sprite: AnimatedSprite2D = $Ball/AnimatedSprite2D
@onready var hazard: Area2D = $Ball/Hazard
@onready var fall_sound: AudioStreamPlayer2D = $FallSound
@onready var impact_sound: AudioStreamPlayer2D = $ImpactSound

var _fall_speed := 0.0
var _has_triggered := false


func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	hazard.body_entered.connect(_on_hazard_body_entered)
	land_preview.visible = false
	ball.visible = false
	hazard.monitoring = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _is_game_over():
		return

	_fall_speed = minf(_fall_speed + gravity * delta, max_fall_speed)

	var target := land_point.position
	var distance := ball.position.distance_to(target)
	ball.position = ball.position.move_toward(target, minf(_fall_speed * delta, distance))
	if ball.position.is_equal_approx(target):
		_land()


func _on_trigger_body_entered(body: Node2D) -> void:
	if _has_triggered or not body.is_in_group(&"player"):
		return

	_has_triggered = true
	trigger_area.set_deferred("monitoring", false)

	# Nhấn nhẹ dấu khắc xuống để người chơi kịp nhận ra mình vừa đạp phải bẫy.
	var press_tween := create_tween()
	press_tween.tween_property(marker, "scale", Vector2(1.12, 0.82), 0.08)
	press_tween.tween_property(marker, "scale", Vector2.ONE, 0.12)

	ball.position = spawn_point.position
	ball.visible = true
	animated_sprite.play(&"fall")
	hazard.set_deferred("monitoring", true)
	fall_sound.play()
	set_physics_process(true)


func _on_hazard_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		var game_state := get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("trigger_game_over"):
			game_state.trigger_game_over(body)


func _land() -> void:
	set_physics_process(false)
	_fall_speed = 0.0
	impact_sound.play()
	animated_sprite.play(&"impact")
	_settle()


# Đập xong thì quả cầu nằm lại luôn trên nền, không biến mất. Animation "impact"
# không lặp nên nó dừng ở khung cuối (quả cầu đã tan bụi) và giữ nguyên khung đó.
func _settle() -> void:
	await animated_sprite.animation_finished
	if not is_instance_valid(self):
		return

	if not deadly_after_landing:
		hazard.set_deferred("monitoring", false)


func _is_game_over() -> bool:
	var game_state := get_node_or_null("/root/GameState")
	return game_state and game_state.has_method("is_game_over") and game_state.is_game_over()
