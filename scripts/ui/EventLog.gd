extends PanelContainer

const COL_BG_PANEL := Color("#222222")
const COL_BORDER := Color("#333333")
const COL_TEXT_PRIMARY := Color("#e0d5c0")
const COL_TEXT_DIM := Color("#8a7f70")
const COL_TEXT_HIGHLIGHT := Color("#f0e8d0")

var _scroll_container: ScrollContainer
var _log_entries: VBoxContainer
var _was_at_bottom := true


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG_PANEL
	style.border_color = COL_BORDER
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)

	_scroll_container = $VBoxContainer/ScrollContainer
	_log_entries = $VBoxContainer/ScrollContainer/LogEntries

	# Style header
	var header: Label = $VBoxContainer/HeaderLabel
	header.text = "Community Log"
	header.add_theme_color_override("font_color", COL_TEXT_DIM)
	header.add_theme_font_size_override("font_size", 14)


func load_from_db() -> void:
	clear()
	var entries := DatabaseManager.query_save(
		"SELECT game_day, tier, display_text FROM event_log ORDER BY id DESC LIMIT 200;"
	)
	# Reverse so oldest is at top
	entries.reverse()
	if entries.is_empty():
		append_entry({
			"game_day": 30,
			"tier": 1,
			"display_text": "The world ended a month ago. You are still here."
		})
	else:
		for entry in entries:
			_add_entry_label(entry)
	_scroll_to_bottom_deferred()


func append_entry(entry: Dictionary) -> void:
	_check_scroll_position()
	_add_entry_label(entry)
	if _was_at_bottom:
		_scroll_to_bottom_deferred()


func clear() -> void:
	for child in _log_entries.get_children():
		child.queue_free()


func _add_entry_label(entry: Dictionary) -> void:
	var tier: int = entry.get("tier", 1)
	var day: int = entry.get("game_day", 0)
	var text: String = entry.get("display_text", "")

	var label := Label.new()
	label.text = "[Day %d] %s" % [day, text]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Left padding and bottom margin via a margin container
	label.add_theme_constant_override("margin_left", 8)

	match tier:
		1:
			label.add_theme_color_override("font_color", COL_TEXT_DIM)
			label.add_theme_font_size_override("font_size", 13)
		2:
			label.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
			label.add_theme_font_size_override("font_size", 14)
		_:
			label.add_theme_color_override("font_color", COL_TEXT_HIGHLIGHT)
			label.add_theme_font_size_override("font_size", 14)

	_log_entries.add_child(label)


func _check_scroll_position() -> void:
	var vbar := _scroll_container.get_v_scroll_bar()
	_was_at_bottom = vbar.value >= vbar.max_value - _scroll_container.size.y - 20


func _scroll_to_bottom_deferred() -> void:
	# Wait two frames so layout is updated
	await get_tree().process_frame
	await get_tree().process_frame
	var vbar := _scroll_container.get_v_scroll_bar()
	vbar.value = vbar.max_value
