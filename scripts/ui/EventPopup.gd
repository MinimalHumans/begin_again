extends PanelContainer

signal choice_made(choice_index: int)

const COL_BG := Color("#222222")
const COL_BORDER := Color("#7a6a50")
const COL_TITLE := Color("#f0e8d0")
const COL_DESC := Color("#e0d5c0")
const COL_HINT := Color("#8a7f70")
const COL_BTN_BG := Color("#2a2a2a")
const COL_BTN_HOVER := Color("#3a3a3a")
const COL_BTN_TEXT := Color("#e0d5c0")
const COL_BTN_TEXT_HOVER := Color("#f0e8d0")

var _title_label: Label
var _description_label: RichTextLabel
var _choices_container: VBoxContainer
var _hints_label: Label


func _ready() -> void:
	# Panel style
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	add_theme_stylebox_override("panel", style)

	# Fixed width, anchored bottom-right
	custom_minimum_size.x = 480
	size_flags_horizontal = Control.SIZE_SHRINK_END

	# Build internal layout
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", COL_TITLE)
	vbox.add_child(_title_label)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)

	_description_label = RichTextLabel.new()
	_description_label.bbcode_enabled = false
	_description_label.fit_content = true
	_description_label.scroll_active = true
	_description_label.custom_minimum_size.y = 40
	_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_label.add_theme_font_size_override("normal_font_size", 14)
	_description_label.add_theme_color_override("default_color", COL_DESC)
	vbox.add_child(_description_label)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size.y = 12
	vbox.add_child(spacer1)

	_choices_container = VBoxContainer.new()
	_choices_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_choices_container)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 8
	vbox.add_child(spacer2)

	_hints_label = Label.new()
	_hints_label.add_theme_font_size_override("font_size", 12)
	_hints_label.add_theme_color_override("font_color", COL_HINT)
	vbox.add_child(_hints_label)


func present(
	event: Dictionary,
	resolved_description: String,
	choices: Array,
	relevant_stat_names: Array
) -> void:
	_title_label.text = str(event.get("title", "Event"))
	_description_label.text = resolved_description

	# Clamp description height
	if _description_label.get_content_height() > 200:
		_description_label.custom_minimum_size.y = 200
		_description_label.scroll_active = true
	else:
		_description_label.scroll_active = false

	# Build choice buttons
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = str(choice.get("_resolved_text", choice.get("text_template", "Choose")))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		# Button style - normal
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = COL_BTN_BG
		btn_style.content_margin_left = 12.0
		btn_style.content_margin_right = 12.0
		btn_style.content_margin_top = 8.0
		btn_style.content_margin_bottom = 8.0
		btn_style.corner_radius_top_left = 3
		btn_style.corner_radius_top_right = 3
		btn_style.corner_radius_bottom_left = 3
		btn_style.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", btn_style)

		# Hover style
		var btn_hover := btn_style.duplicate()
		btn_hover.bg_color = COL_BTN_HOVER
		btn.add_theme_stylebox_override("hover", btn_hover)

		# Pressed style
		var btn_pressed := btn_style.duplicate()
		btn_pressed.bg_color = COL_BTN_HOVER
		btn.add_theme_stylebox_override("pressed", btn_pressed)

		btn.add_theme_color_override("font_color", COL_BTN_TEXT)
		btn.add_theme_color_override("font_hover_color", COL_BTN_TEXT_HOVER)
		btn.add_theme_color_override("font_pressed_color", COL_BTN_TEXT_HOVER)
		btn.add_theme_font_size_override("font_size", 14)

		btn.pressed.connect(_on_choice_selected.bind(i))
		_choices_container.add_child(btn)

	# Stat hints
	if relevant_stat_names.size() > 0:
		_hints_label.text = "Relevant: " + ", ".join(relevant_stat_names)
	else:
		_hints_label.text = ""


func _on_choice_selected(index: int) -> void:
	choice_made.emit(index)
	queue_free()
