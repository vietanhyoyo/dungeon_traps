class_name SaveGame
extends RefCounted

## Bộ nhớ ngoài của game: chỉ đọc và ghi file, không giữ luật chơi nào.
## `GameState` là chỗ duy nhất gọi tới đây, phần còn lại của game không cần biết
## có file save tồn tại.
##
## `user://` trỏ vào thư mục dữ liệu riêng của người chơi (khác nhau theo hệ điều
## hành), nên file nằm ngoài thư mục project: không bị git theo dõi và không mất
## mỗi lần export. Bản export HTML thì Godot ánh xạ `user://` vào IndexedDB của
## trình duyệt, cùng một đoạn code chạy được cả hai nơi.
##
## Mọi lỗi đọc/ghi đều chỉ cảnh báo rồi đi tiếp: mất file save là mất tiến độ,
## không đáng để dựng cả game lên.

const SAVE_PATH := "user://save_game.json"
const UNLOCKED_SKILLS_KEY := "unlocked_skills"
## Tăng lên khi đổi cấu trúc file, để bản game sau còn biết đường đọc file cũ.
const FORMAT_VERSION := 1
const VERSION_KEY := "version"


## Danh sách skill_id đã kiếm được. Lần chơi đầu tiên chưa có file, hoặc file
## hỏng, thì trả về mảng rỗng — người chơi bắt đầu lại từ chưa có kỹ năng nào.
static func load_skills() -> Array:
	var data := _read_file()
	if data.is_empty():
		return []

	var stored: Variant = data.get(UNLOCKED_SKILLS_KEY, [])
	if not stored is Array:
		push_warning("Save file has a malformed skill list, ignoring it")
		return []

	var skills := []
	for skill_id: Variant in stored:
		# Bỏ qua kỹ năng đã bị xoá khỏi Skills.CATALOG giữa hai phiên bản game,
		# nếu không màn chơi sẽ hỏi has_skill() về một id không còn tồn tại.
		if skill_id is String and not Skills.get_info(skill_id).is_empty():
			skills.append(skill_id)

	return skills


static func save_skills(skill_ids: Array) -> void:
	var data := {
		VERSION_KEY: FORMAT_VERSION,
		UNLOCKED_SKILLS_KEY: skill_ids,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("Could not write %s: %s" % [SAVE_PATH, FileAccess.get_open_error()])
		return

	# "\t" cho file xuống dòng đẹp, để mở ra đọc/sửa tay lúc test cho nhanh.
	file.store_string(JSON.stringify(data, "\t"))


## Đọc file save thành Dictionary. Trả về {} cho mọi trường hợp không đọc được,
## chỗ gọi không phải phân biệt "chưa có file" với "file hỏng".
static func _read_file() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		# Lần chơi đầu tiên, không có gì bất thường để cảnh báo.
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_warning("Could not read %s: %s" % [SAVE_PATH, FileAccess.get_open_error()])
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Save file is not valid JSON, starting from scratch")
		return {}

	return parsed
