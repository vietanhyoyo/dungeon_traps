extends CanvasLayer

@export_range(1, 99, 1) var total_stars := 3

@onready var counter_label: Label = $Panel/Margin/HBox/Counter

var collected_stars := 0

func _ready() -> void:
	_update_counter()


func add_star() -> void:
	collected_stars = mini(collected_stars + 1, total_stars)
	_update_counter()


func _update_counter() -> void:
	counter_label.text = "%d / %d" % [collected_stars, total_stars]
