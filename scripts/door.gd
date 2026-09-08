extends Node2D

@export var next_scene_path: String

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var open_area: Area2D = $OpenArea
@onready var pass_area: Area2D = $PassArea

var is_transitioning := false
var is_opening := false
var is_open := false
var player_in_pass_area: Node2D


func _ready() -> void:
	open_area.body_entered.connect(_on_open_area_body_entered)
	pass_area.body_entered.connect(_on_pass_area_body_entered)
	pass_area.body_exited.connect(_on_pass_area_body_exited)
	animated_sprite.animation_finished.connect(_on_animated_sprite_animation_finished)


func _on_open_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or is_open or is_opening:
		return

	is_opening = true
	animated_sprite.play("open")


func _on_pass_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	player_in_pass_area = body

	if is_open:
		_go_to_next_scene()


func _on_pass_area_body_exited(body: Node2D) -> void:
	if body == player_in_pass_area:
		player_in_pass_area = null


func _on_animated_sprite_animation_finished() -> void:
	if animated_sprite.animation != &"open":
		return

	is_opening = false
	is_open = true

	if is_instance_valid(player_in_pass_area):
		_go_to_next_scene()


func _go_to_next_scene() -> void:
	if is_transitioning:
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
