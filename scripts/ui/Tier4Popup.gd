extends CanvasLayer

signal choice_made(choice_index: int)

const COL_BG := Color("#181818")
const COL_BORDER := Color("#7a6a50")
const COL_EYEBROW := Color("#7a6a50")
const COL_TITLE := Color("#f0e8d0")
const COL_DAY := Color("#8a7f70")
const COL_DESC := Color("#e0d5c0")
const COL_HINT := Color("#8a7f70")
const COL_BTN_BG := Color("#2a2a2a")
const COL_BTN_HOVER := Color("#252525")
const COL_BTN_TEXT := Color("#e0d5c0")
const COL_BTN_TEXT_HOVER := Color("#f0e8d0")
const COL_DIMMER := Color(0, 0, 0, 0.88)

var _title_label: Label
var _day_label: Label
var _description_label: RichTextLabel
var _choices_container: VBoxContainer
var _hints_label: Label


func _ready() -> void:
	layer = 15

	# Dimmer — full screen dark overlay
	var dimmer := ColorRect.new()
	dimmer.color = COL_DIMMER
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	# Content panel — centered, constrained
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(720, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COL_BG
	panel_style.border_color = COL_BORDER
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 0.0
	panel_style.content_margin_right = 0.0
	panel_style.content_margin_top = 0.0
	panel_style.content_margin_bottom = 0.0
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	# Padded content area (no accent bar — Tier 4 is not a warning)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# Eyebrow label
	var eyebrow := Label.new()
	eyebrow.text = "A DEFINING MOMENT"
	eyebrow.add_theme_font_size_override("font_size", 10)
	eyebrow.add_theme_color_override("font_color", COL_EYEBROW)
	eyebrow.uppercase = true
	vbox.add_child(eyebrow)

	var eyebrow_spacer := Control.new()
	eyebrow_spacer.custom_minimum_size.y = 16
	vbox.add_child(eyebrow_spacer)

	# Title
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", COL_TITLE)
	vbox.add_child(_title_label)

	var title_spacer := Control.new()
	title_spacer.custom_minimum_size.y = 6
	vbox.add_child(title_spacer)

	# Day label
	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 12)
	_day_label.add_theme_color_override("font_color", COL_DAY)
	vbox.add_child(_day_label)

	var day_spacer := Control.new()
	day_spacer.custom_minimum_size.y = 20
	vbox.add_child(day_spacer)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	var sep_spacer := Control.new()
	sep_spacer.custom_minimum_size.y = 16
	vbox.add_child(sep_spacer)

	# Description in a scroll container
	var desc_scroll := ScrollContainer.new()
	desc_scroll.custom_minimum_size.y = 120
	desc_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(desc_scroll)

	_description_label = RichTextLabel.new()
	_description_label.bbcode_enabled = false
	_description_label.fit_content = true
	_description_label.scroll_active = false
	_description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_label.add_theme_font_size_override("normal_font_size", 16)
	_description_label.add_theme_color_override("default_color", COL_DESC)
	_description_label.add_theme_constant_override("line_separation", 4)
	desc_scroll.add_child(_description_label)

	# Spacer before choices
	var spacer1 := Control.new()
	spacer1.custom_minimum_size.y = 24
	vbox.add_child(spacer1)

	# Choices container
	_choices_container = VBoxContainer.new()
	_choices_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_choices_container)

	# Spacer after choices
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 12
	vbox.add_child(spacer2)

	# Stat hints
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
	_title_label.text = str(event.get("title", "A Defining Moment"))

	# Get current game day for the day label
	var gs_rows := DatabaseManager.query_save("SELECT game_day FROM game_state WHERE id = 1;")
	if gs_rows.size() > 0:
		_day_label.text = "Day %d" % int(gs_rows[0].get("game_day", 0))
	else:
		_day_label.text = ""

	_description_label.text = resolved_description

	# Build choice buttons — clean, no left border bar
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = str(choice.get("_resolved_text", choice.get("text_template", "Choose")))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 60

		# Normal style — no left border bar
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = COL_BTN_BG
		btn_style.content_margin_left = 16.0
		btn_style.content_margin_right = 16.0
		btn_style.content_margin_top = 12.0
		btn_style.content_margin_bottom = 12.0
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
		btn.add_theme_font_size_override("font_size", 15)

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
