extends CanvasLayer
class_name CharacterHUD

## Khung pixel: vàng cho nhân vật đang điều khiển, đá xám cho nhân vật còn lại.
const SELECTED_FRAME: StyleBox = preload("res://nodes/ui/styles/frame_gold.tres")
const IDLE_FRAME: StyleBox = preload("res://nodes/ui/styles/frame_stone.tres")

@onready var asura_card: PanelContainer = $Portraits/AsuraCard
@onready var serelyn_card: PanelContainer = $Portraits/SerelynCard
@onready var asura_cooldown_badge: PanelContainer = $Portraits/AsuraCard/Portrait/CooldownBadge
@onready var serelyn_cooldown_badge: PanelContainer = $Portraits/SerelynCard/Portrait/CooldownBadge
@onready var asura_countdown: Label = $Portraits/AsuraCard/Portrait/CooldownBadge/Countdown
@onready var serelyn_countdown: Label = $Portraits/SerelynCard/Portrait/CooldownBadge/Countdown


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
	card.add_theme_stylebox_override("panel", SELECTED_FRAME if selected else IDLE_FRAME)
