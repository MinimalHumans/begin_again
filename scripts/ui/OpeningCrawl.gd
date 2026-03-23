extends CanvasLayer

signal dismissed


func show_text(text: String) -> void:
	$ContentContainer/TextBox/CrawlLabel.text = text


func _ready() -> void:
	$ContentContainer/TextBox/DismissButton.pressed.connect(_on_dismiss_button_pressed)

	# Style the dismiss button
	var btn: Button = $ContentContainer/TextBox/DismissButton
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color("#e0d5c0"))
	btn.add_theme_color_override("font_hover_color", Color("#e0d5c0"))
	btn.add_theme_color_override("font_pressed_color", Color("#e0d5c0"))

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color("#2a2a2a")
	normal_style.content_margin_left = 20.0
	normal_style.content_margin_right = 20.0
	normal_style.content_margin_top = 10.0
	normal_style.content_margin_bottom = 10.0
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color("#3a3a3a")
	hover_style.content_margin_left = 20.0
	hover_style.content_margin_right = 20.0
	hover_style.content_margin_top = 10.0
	hover_style.content_margin_bottom = 10.0
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)


func _on_dismiss_button_pressed() -> void:
	dismissed.emit()
