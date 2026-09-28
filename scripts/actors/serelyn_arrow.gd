extends Node2D
class_name SerelynArrow

const SPEED := 900.0
const LIFETIME := 3.0
const HIT_MASK := 1 | 4 | 8 # Địa hình, enemy, vật phá được và dây cắt được.
const ARROW_AREA_MASK := 16 # Vùng trúng tên mở rộng của enemy, không ảnh hưởng va chạm thân.
const ARROW_TIP_OFFSET := 17.0
const HIT_EFFECT_SCENE := preload("res://nodes/effects/hit_effect.tscn")

var direction := Vector2.RIGHT
var age := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var glow: PointLight2D = $GreenGlow


func launch(origin: Vector2, launch_direction: Vector2) -> void:
	global_position = origin
	direction = launch_direction.normalized()
	rotation = direction.angle()
	sprite.flip_h = false
	# Tâm quầng sáng nằm ở đầu mũi tên, không nằm giữa texture 64x64.
	glow.position = Vector2(ARROW_TIP_OFFSET, 0.0)


func _physics_process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return

	var motion := direction * SPEED * delta
	# Quét hết quãng đường mỗi frame để tên không xuyên qua slime khi bay nhanh.
	var hit := raycast_path(get_world_2d().direct_space_state, global_position, global_position + motion)
	if not hit.is_empty():
		global_position = hit["position"]
		var target := hit["collider"] as Node
		var enemy := enemy_for_collider(target)
		if enemy != null:
			if _is_inside_camera(enemy):
				_spawn_hit_effect()
				enemy.die()
		elif target != null and target.is_in_group(&"breakable") \
				and target.has_method("break_apart"):
			_spawn_hit_effect()
			target.break_apart()
		elif target != null and target.has_method("hit_by_arrow"):
			target.hit_by_arrow()
		queue_free()
		return

	global_position += motion


static func raycast_path(space: PhysicsDirectSpaceState2D, origin: Vector2, endpoint: Vector2) -> Dictionary:
	var body_query := PhysicsRayQueryParameters2D.create(origin, endpoint)
	body_query.collision_mask = HIT_MASK
	var body_hit := space.intersect_ray(body_query)

	var area_query := PhysicsRayQueryParameters2D.create(origin, endpoint)
	area_query.collision_mask = ARROW_AREA_MASK
	area_query.collide_with_bodies = false
	area_query.collide_with_areas = true
	var area_hit := space.intersect_ray(area_query)

	if area_hit.is_empty():
		return body_hit
	if body_hit.is_empty() or origin.distance_squared_to(area_hit["position"]) \
			< origin.distance_squared_to(body_hit["position"]):
		return area_hit
	return body_hit


static func enemy_for_collider(collider: Object) -> Node2D:
	var node := collider as Node
	if node == null:
		return null
	if node.is_in_group(&"enemy") and node.has_method("die"):
		return node as Node2D
	var area := node as Area2D
	if area != null and (area.collision_layer & ARROW_AREA_MASK) != 0:
		var owner_node := area.get_parent()
		if owner_node.is_in_group(&"enemy") and owner_node.has_method("die"):
			return owner_node as Node2D
	return null


func _is_inside_camera(target: Node2D) -> bool:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return false

	var view_size := get_viewport_rect().size / camera.zoom.abs()
	var view_center := camera.get_screen_center_position()
	var view_rect := Rect2(view_center - view_size * 0.5, view_size)
	return view_rect.has_point(target.global_position)


func _spawn_hit_effect() -> void:
	# Hiệu ứng là con của scene màn chơi để không bị xoá cùng slime sau khi die().
	var effect: AnimatedSprite2D = HIT_EFFECT_SCENE.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = global_position
