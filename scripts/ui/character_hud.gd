extends CanvasLayer
class_name CharacterHUD

const SELECTED_BORDER := Color(0.93, 0.82, 0.1, 1.0)
const IDLE_BORDER := Color(0.34, 0.32, 0.37, 1.0)

@onready var asura_card: PanelContainer = $Portraits/AsuraCard
@onready var serelyn_card: PanelContainer = $Portraits/SerelynCard
@onready var asura_cooldown_badge: PanelContainer = $Portraits/AsuraCard/Portrait/CooldownBadge
@onready var serelyn_cooldown_badge: PanelContainer = $Portraits/SerelynCard/Portrait/CooldownBadge
@onready var asura_countdown: Label = $Portraits/AsuraCard/Portrait/CooldownBadge/Countdown
@onready var serelyn_countdown: Label = $Portraits/SerelynCard/Portrait/CooldownBadge/Countdown


func _ready() -> void:
	# Mỗi ô cần StyleBox riêng để đổi màu viền độc lập.
	for card in [asura_card, serelyn_card]:
		var frame := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		card.add_theme_stylebox_override("panel", frame)


func set_state(controlling_serelyn: bool, can_switch: bool) -> void:
	_set_card(asura_card, not controlling_serelyn, true)
	_set_card(serelyn_card, controlling_serelyn, can_switch)


func set_switch_cooldown(controlling_serelyn: bool, seconds_remaining: float) -> void:
	var is_active := seconds_remaining > 0.0
	asura_cooldown_badge.visible = is_active and controlling_serelyn
	serelyn_cooldown_badge.visible = is_active and not controlling_serelyn
	if not is_active:
		return
	var countdown := str(ceili(seconds_remaining))
	asura_countdown.text = countdown
	serelyn_countdown.text = countdown


func _set_card(card: PanelContainer, selected: bool, available: bool) -> void:
	card.modulate.a = 1.0 if selected else (0.6 if available else 0.25)
	var frame := card.get_theme_stylebox("panel") as StyleBoxFlat
	frame.border_color = SELECTED_BORDER if selected else IDLE_BORDER
