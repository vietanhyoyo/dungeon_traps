extends CanvasLayer
class_name CharacterHUD

const SELECTED_BORDER := Color(0.93, 0.82, 0.1, 1.0)
const IDLE_BORDER := Color(0.34, 0.32, 0.37, 1.0)

@onready var asura_card: PanelContainer = $Portraits/AsuraCard
@onready var serelyn_card: PanelContainer = $Portraits/SerelynCard


func _ready() -> void:
	# Mỗi ô cần StyleBox riêng để đổi màu viền độc lập.
	for card in [asura_card, serelyn_card]:
		var frame := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		card.add_theme_stylebox_override("panel", frame)


func set_state(controlling_serelyn: bool, can_switch: bool) -> void:
	_set_card(asura_card, not controlling_serelyn, true)
	_set_card(serelyn_card, controlling_serelyn, can_switch)


func _set_card(card: PanelContainer, selected: bool, available: bool) -> void:
	card.modulate.a = 1.0 if selected else (0.6 if available else 0.25)
	var frame := card.get_theme_stylebox("panel") as StyleBoxFlat
	frame.border_color = SELECTED_BORDER if selected else IDLE_BORDER
