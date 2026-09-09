extends Control

## Danh sách màn chơi hiển thị ở màn hình chọn màn. Thêm level mới chỉ cần
## thêm một dòng ở đây, cả nút thoát trong game cũng dùng chung màn hình này.
const LEVELS := [
	{"title": "Level 1", "path": "res://nodes/scenes/level_1.tscn"},
	{"title": "Level 2", "path": "res://nodes/scenes/level_2.tscn"},
	{"title": "Level 3", "path": "res://nodes/scenes/level_3.tscn"},
	{"title": "Level 4", "path": "res://nodes/scenes/level_4.tscn"},
	{"title": "Level 5", "path": "res://nodes/scenes/level_5.tscn"},
]
const BUTTON_FONT := preload("res://assets/fonts/PixelOperator8-Bold.ttf")

@onready var level_list: VBoxContainer = $Panel/VBox/LevelList
@onready var quit_button: Button = $Panel/VBox/QuitButton


func _ready() -> void:
	# Vào đây có thể là do bấm thoát lúc game đang pause, nên phải bỏ pause.
	get_tree().paused = false

	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("reset_to_playing"):
		game_state.reset_to_playing()

	_build_level_buttons()
	quit_button.pressed.connect(_on_quit_pressed)


func _build_level_buttons() -> void:
	for index in LEVELS.size():
		var level: Dictionary = LEVELS[index]
		var button := Button.new()
		button.text = level["title"]
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_font_override("font", BUTTON_FONT)
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_on_level_pressed.bind(level["path"]))
		level_list.add_child(button)

		if index == 0:
			button.grab_focus()


func _on_level_pressed(scene_path: String) -> void:
	# Chọn màn từ menu là chơi lại từ đầu: bỏ sao đã ăn và save point cũ.
	var game_state := get_node_or_null("/root/GameState")
	if game_state and game_state.has_method("clear_level_progress"):
		game_state.clear_level_progress(scene_path)

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not load level %s: %s" % [scene_path, error])


func _on_quit_pressed() -> void:
	get_tree().quit()
