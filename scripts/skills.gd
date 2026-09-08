class_name Skills
extends RefCounted

## Danh mục kỹ năng mở khoá được trong game. Mỗi kỹ năng chỉ khai báo tên, mô tả
## và ô icon ở đúng một chỗ này; popup nhận thưởng và bảng nhân vật đều đọc lại
## từ đây nên không có chỗ nào phải chép tay lại nội dung.

const WALL_DOUBLE_JUMP := "wall_double_jump"
const SPIN_JUMP_ATTACK := "spin_jump_attack"

## skills.png là một dải icon 32x32 xếp ngang, icon_index tính từ 0.
const ICON_SHEET := preload("res://assets/sprites/skills/skills.png")
const ICON_SIZE := 32

const CATALOG := {
	WALL_DOUBLE_JUMP: {
		"name": "Wall Double Jump",
		"description": "Press the Up arrow twice while touching a wall to jump one more time.",
		"key": "UP x2",
		"icon_index": 2,
	},
	SPIN_JUMP_ATTACK: {
		"name": "Spin Jump Attack",
		"description": "Attack in mid-air to somersault with a much wider slash.",
		"key": "C in air",
		"icon_index": 3,
	},
}


static func get_info(skill_id: String) -> Dictionary:
	return CATALOG.get(skill_id, {})


static func make_icon(skill_id: String) -> AtlasTexture:
	var info := get_info(skill_id)
	if info.is_empty():
		return null

	var icon := AtlasTexture.new()
	icon.atlas = ICON_SHEET
	icon.region = Rect2(int(info["icon_index"]) * ICON_SIZE, 0, ICON_SIZE, ICON_SIZE)
	return icon
