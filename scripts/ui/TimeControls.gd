extends PanelContainer

signal speed_changed(speed: int)

const COL_BG_PANEL := Color("#222222")
const COL_BG_RAISED := Color("#2a2a2a")
const COL_BORDER := Color("#333333")
const COL_TEXT_PRIMARY := Color("#e0d5c0")
const COL_TEXT_DIM := Color("#8a7f70")

var _current_speed: int = 0
var _buttons: Array[Button] = []
var _speed_label: Label


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG_PANEL
	style.border_color = COL_BORDER
	style.border_width_top = 1
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)

	var pause_btn: Button = $HBoxContainer/PauseButton
	var normal_btn: Button = $HBoxContainer/NormalButton
	var fast_btn: Button = $HBoxContainer/FastButton
	_speed_label = $HBoxContainer/SpeedLabel

	_buttons = [pause_btn, normal_btn, fast_btn]

	pause_btn.text = "⏸ Pause"
	normal_btn.text = "▶ Normal"
	fast_btn.text = "⏩ Fast"

	pause_btn.pressed.connect(_on_pause)
	normal_btn.pressed.connect(_on_normal)
	fast_btn.pressed.connect(_on_fast)

	for btn in _buttons:
		btn.flat = true
		btn.add_theme_font_size_override("font_size", 14)

	_speed_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	_speed_label.add_theme_font_size_override("font_size", 13)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	set_speed(0)


func get_speed() -> int:
	return _current_speed


func set_speed(speed: int) -> void:
	_current_speed = clampi(speed, 0, 2)
	_update_button_visuals()
	var labels := ["Paused", "Normal", "Fast"]
	_speed_label.text = labels[_current_speed]


func _on_pause() -> void:
	set_speed(0)
	speed_changed.emit(0)


func _on_normal() -> void:
	set_speed(1)
	speed_changed.emit(1)


func _on_fast() -> void:
	set_speed(2)
	speed_changed.emit(2)


func _update_button_visuals() -> void:
	for i in range(_buttons.size()):
		var btn := _buttons[i]
		if i == _current_speed:
			var active_style := StyleBoxFlat.new()
			active_style.bg_color = COL_BG_RAISED
			active_style.content_margin_left = 10.0
			active_style.content_margin_right = 10.0
			active_style.content_margin_top = 4.0
			active_style.content_margin_bottom = 4.0
			btn.add_theme_stylebox_override("normal", active_style)
			btn.add_theme_stylebox_override("hover", active_style)
			btn.add_theme_stylebox_override("pressed", active_style)
			btn.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
			btn.add_theme_color_override("font_hover_color", COL_TEXT_PRIMARY)
			btn.add_theme_color_override("font_pressed_color", COL_TEXT_PRIMARY)
		else:
			var inactive_style := StyleBoxFlat.new()
			inactive_style.bg_color = COL_BG_PANEL
			inactive_style.content_margin_left = 10.0
			inactive_style.content_margin_right = 10.0
			inactive_style.content_margin_top = 4.0
			inactive_style.content_margin_bottom = 4.0
			btn.add_theme_stylebox_override("normal", inactive_style)
			btn.add_theme_stylebox_override("hover", inactive_style)
			btn.add_theme_stylebox_override("pressed", inactive_style)
			btn.add_theme_color_override("font_color", COL_TEXT_DIM)
			btn.add_theme_color_override("font_hover_color", COL_TEXT_DIM)
			btn.add_theme_color_override("font_pressed_color", COL_TEXT_DIM)
