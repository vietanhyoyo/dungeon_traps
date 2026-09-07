extends Node2D

## Xử lý riêng của level 4: một đàn dơi phục sẵn nhưng chỉ hiện ra khi người chơi
## mở rương kho báu. Level scene vẫn chỉ đặt vị trí, còn kịch bản của màn nằm ở
## đây - rương và bat đều không biết gì về nhau.

## Tên các bat bị giấu trong BatList. Bat còn lại bay sẵn từ đầu màn.
const AMBUSH_BAT_NAMES: Array[StringName] = [&"Bat2", &"Bat3", &"Bat4", &"Bat5", &"Bat6"]
## Khoảng cách giữa hai con liên tiếp để cả đàn hiện so le chứ không bật cùng lúc.
const AMBUSH_STAGGER := 0.12

@onready var chest: TreasureChest = $ChestList/TreasureChest
@onready var bat_list: Node = $BatList

var _ambush_bats: Array[Bat] = []


func _ready() -> void:
	_collect_ambush_bats()

	# Rương mở từ trước (chết rồi hồi sinh ở save point): đàn dơi phải có sẵn,
	# không được giấu lại rồi bắt người chơi mở rương lần nữa mới hiện.
	if chest.is_open:
		return

	for bat in _ambush_bats:
		bat.set_dormant(true)

	chest.opened.connect(_on_chest_opened)


func _collect_ambush_bats() -> void:
	for bat_name in AMBUSH_BAT_NAMES:
		var bat := bat_list.get_node_or_null(NodePath(bat_name)) as Bat
		if bat == null:
			push_warning("Level 4: không tìm thấy BatList/%s" % bat_name)
			continue
		_ambush_bats.append(bat)


func _on_chest_opened() -> void:
	for index in _ambush_bats.size():
		_ambush_bats[index].appear(index * AMBUSH_STAGGER)
