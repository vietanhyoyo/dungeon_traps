extends Node2D

const ATTACK_HIT_START_FRAME := 2
const ATTACK_REPEAT_DELAY := 0.2

@export var devi_slime_path: NodePath

@onready var tentacle_sprite: AnimatedSprite2D = $TentacleSprite
@onready var attack_shape: CollisionShape2D = $Killzone/AttackShape
@onready var attack_range: Area2D = $AttackRange
@onready var attack_sound: AudioStreamPlayer2D = $AttackSound

var _is_attacking := false
var _target: Node2D
var _attack_repeat_timer: Timer


func _ready() -> void:
	attack_range.body_entered.connect(_on_attack_range_body_entered)
	attack_range.body_exited.connect(_on_attack_range_body_exited)
	tentacle_sprite.animation_finished.connect(_on_tentacle_animation_finished)
	tentacle_sprite.frame_changed.connect(_on_tentacle_frame_changed)

	_attack_repeat_timer = Timer.new()
	_attack_repeat_timer.one_shot = true
	_attack_repeat_timer.timeout.connect(_try_attack_target)
	add_child(_attack_repeat_timer)

	var devi_slime := get_node_or_null(devi_slime_path)
	if devi_slime == null or not devi_slime.has_signal("defeated"):
		return

	devi_slime.connect(
		"defeated",
		Callable(self, "_on_devi_slime_defeated"),
		CONNECT_ONE_SHOT
	)
	if devi_slime.get("is_dead"):
		_on_devi_slime_defeated()


func _on_devi_slime_defeated() -> void:
	queue_free()


func _on_attack_range_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_target = body
	_try_attack_target()


func _on_attack_range_body_exited(body: Node2D) -> void:
	if body == _target:
		_target = null
		_attack_repeat_timer.stop()


func _try_attack_target() -> void:
	if _is_attacking or not is_instance_valid(_target):
		return
	if not _target.is_in_group(&"player") or not attack_range.overlaps_body(_target):
		_target = null
		return
	_is_attacking = true
	attack_shape.set_deferred("disabled", true)
	tentacle_sprite.flip_h = _target.global_position.x < global_position.x
	tentacle_sprite.position.y = -48.0
	attack_sound.play()
	tentacle_sprite.play(&"attack")


## Xúc tua là đòn đánh theo nhịp ngắn: bỏ qua hit nếu player đang tung chiêu
## hoặc đang trong khung bất tử do đòn đánh cấp.
func should_ignore_player_damage(body: Node2D) -> bool:
	if _player_is_attacking(body):
		return true
	return body.has_method("is_invulnerable") and body.is_invulnerable()


func _player_is_attacking(body: Node2D) -> bool:
	for property in body.get_property_list():
		if property.get("name") == "is_attacking":
			return bool(body.get("is_attacking"))
	return false


func _on_tentacle_frame_changed() -> void:
	if not _is_attacking or tentacle_sprite.animation != &"attack":
		return
	attack_shape.set_deferred(
		"disabled",
		tentacle_sprite.frame < ATTACK_HIT_START_FRAME
	)


func _on_tentacle_animation_finished() -> void:
	if not _is_attacking or tentacle_sprite.animation != &"attack":
		return

	attack_shape.set_deferred("disabled", true)
	tentacle_sprite.flip_h = false
	tentacle_sprite.position.y = -16.0
	tentacle_sprite.play(&"idle")
	_is_attacking = false
	if is_instance_valid(_target) and attack_range.overlaps_body(_target):
		_attack_repeat_timer.start(ATTACK_REPEAT_DELAY)
