extends PanelContainer

# Colour palette
const COL_BG_PANEL := Color("#222222")
const COL_BORDER := Color("#333333")
const COL_TEXT_PRIMARY := Color("#e0d5c0")
const COL_TEXT_DIM := Color("#8a7f70")
const COL_GREEN_OK := Color("#5a9a5a")
const COL_AMBER_WARN := Color("#c8882a")
const COL_RED_CRIT := Color("#b03030")
const COL_BAR_BG := Color("#333333")

signal new_game_requested
signal roster_requested

var _stat_rows: Dictionary = {}  # stat_id -> { bar_fill, value_label, stat_def }
var _day_season_label: Label


func _ready() -> void:
	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG_PANEL
	style.border_color = COL_BORDER
	style.border_width_right = 0
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 12.0
	add_theme_stylebox_override("panel", style)

	# Style the New Game button
	var btn: Button = $VBoxContainer/NewGameButton
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", COL_TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", COL_TEXT_PRIMARY)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color("#2a2a2a")
	btn_normal.content_margin_left = 8.0
	btn_normal.content_margin_right = 8.0
	btn_normal.content_margin_top = 6.0
	btn_normal.content_margin_bottom = 6.0
	btn.add_theme_stylebox_override("normal", btn_normal)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color("#3a3a3a")
	btn_hover.content_margin_left = 8.0
	btn_hover.content_margin_right = 8.0
	btn_hover.content_margin_top = 6.0
	btn_hover.content_margin_bottom = 6.0
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_stylebox_override("pressed", btn_hover)

	btn.pressed.connect(func(): new_game_requested.emit())

	# Style the Roster button
	var roster_btn: Button = $VBoxContainer/RosterButton
	roster_btn.flat = true
	roster_btn.add_theme_font_size_override("font_size", 13)
	roster_btn.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	roster_btn.add_theme_color_override("font_hover_color", COL_TEXT_PRIMARY)
	roster_btn.add_theme_color_override("font_pressed_color", COL_TEXT_PRIMARY)

	var roster_normal := StyleBoxFlat.new()
	roster_normal.bg_color = Color("#2a2a2a")
	roster_normal.content_margin_left = 8.0
	roster_normal.content_margin_right = 8.0
	roster_normal.content_margin_top = 6.0
	roster_normal.content_margin_bottom = 6.0
	roster_btn.add_theme_stylebox_override("normal", roster_normal)

	var roster_hover := StyleBoxFlat.new()
	roster_hover.bg_color = Color("#3a3a3a")
	roster_hover.content_margin_left = 8.0
	roster_hover.content_margin_right = 8.0
	roster_hover.content_margin_top = 6.0
	roster_hover.content_margin_bottom = 6.0
	roster_btn.add_theme_stylebox_override("hover", roster_hover)
	roster_btn.add_theme_stylebox_override("pressed", roster_hover)

	roster_btn.pressed.connect(func(): roster_requested.emit())


func build(stat_definitions: Array) -> void:
	var vbox := $VBoxContainer
	_day_season_label = $VBoxContainer/DaySeasonLabel
	var stats_list := $VBoxContainer/StatsList

	# Clear any existing rows
	for child in stats_list.get_children():
		child.queue_free()
	_stat_rows.clear()

	for stat in stat_definitions:
		var row := _create_stat_row(stat)
		stats_list.add_child(row)


func refresh() -> void:
	# Update day/season
	var gs := DatabaseManager.query_save("SELECT game_day, season FROM game_state WHERE id = 1;")
	if gs.size() > 0:
		var day_text := "Day %d" % gs[0]["game_day"]
		var season_text: String = gs[0]["season"]
		season_text = season_text.capitalize()
		_day_season_label.text = day_text + "\n" + season_text

	# Update stat values
	var current := DatabaseManager.query_save("SELECT stat_id, value FROM current_stats;")
	var values := {}
	for row in current:
		values[row["stat_id"]] = row["value"]

	# Get population for food-weeks calc
	var pop_val: float = values.get("population", 1)
	var food_drain: float = GameData.get_config("FOOD_DRAIN_PER_PERSON")

	for stat_id in _stat_rows:
		var info: Dictionary = _stat_rows[stat_id]
		var stat_def: Dictionary = info["stat_def"]
		var val: float = values.get(stat_id, 0.0)
		var fmt: String = stat_def["format_type"]
		var colour := _get_threshold_colour(stat_def, val, pop_val, food_drain)

		if fmt == "bar":
			var min_v: float = stat_def["min_value"]
			var max_v: float = stat_def["max_value"]
			var pct := clampf((val - min_v) / (max_v - min_v), 0.0, 1.0)
			var bar_fill: ColorRect = info["bar_fill"]
			var bar_track: ColorRect = info["bar_track"]
			bar_fill.custom_minimum_size.x = bar_track.size.x * pct
			bar_fill.color = colour
			# Deferred resize since track may not have sized yet
			var track_ref := bar_track
			var fill_ref := bar_fill
			var pct_val := pct
			var col_val := colour
			track_ref.resized.connect(func():
				fill_ref.custom_minimum_size.x = track_ref.size.x * pct_val
				fill_ref.color = col_val
			)
			var vl: Label = info["value_label"]
			vl.text = str(int(val))
		elif fmt == "number":
			var vl: Label = info["value_label"]
			vl.text = str(int(val))
			vl.add_theme_color_override("font_color", colour)
		elif fmt == "weeks":
			var weeks := 0.0
			if pop_val > 0 and food_drain > 0:
				weeks = val / (pop_val * food_drain * 7.0)
			var vl: Label = info["value_label"]
			vl.text = "%.1f wks" % weeks
			vl.add_theme_color_override("font_color", colour)


func _get_threshold_colour(stat_def: Dictionary, value: float, population: float, food_drain: float) -> Color:
	var fmt: String = stat_def["format_type"]
	var crit_low = stat_def.get("critical_low")
	var warn_low = stat_def.get("warning_low")

	# Reputation has no thresholds
	if crit_low == null and warn_low == null:
		return COL_GREEN_OK

	var check_val := value
	# For weeks format, compare in weeks
	if fmt == "weeks" and population > 0 and food_drain > 0:
		check_val = value / (population * food_drain * 7.0)

	if crit_low != null and check_val <= float(crit_low):
		return COL_RED_CRIT
	if warn_low != null and check_val <= float(warn_low):
		return COL_AMBER_WARN
	return COL_GREEN_OK


func _create_stat_row(stat_def: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = stat_def["display_name"]
	name_label.custom_minimum_size.x = 110
	name_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	name_label.add_theme_font_size_override("font_size", 13)
	row.add_child(name_label)

	var fmt: String = stat_def["format_type"]
	var stat_id: String = stat_def["id"]

	if fmt == "bar":
		# Bar track
		var track := ColorRect.new()
		track.color = COL_BAR_BG
		track.custom_minimum_size.y = 12
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(track)

		# Bar fill (child of track)
		var fill := ColorRect.new()
		fill.color = COL_GREEN_OK
		fill.custom_minimum_size.y = 12
		fill.custom_minimum_size.x = 0
		fill.position = Vector2.ZERO
		track.add_child(fill)

		# Value label
		var val_label := Label.new()
		val_label.text = "0"
		val_label.custom_minimum_size.x = 40
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_label.add_theme_color_override("font_color", COL_TEXT_DIM)
		val_label.add_theme_font_size_override("font_size", 11)
		row.add_child(val_label)

		_stat_rows[stat_id] = { "bar_track": track, "bar_fill": fill, "value_label": val_label, "stat_def": stat_def }

	elif fmt == "number":
		var val_label := Label.new()
		val_label.text = "0"
		val_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_label.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
		val_label.add_theme_font_size_override("font_size", 16)
		row.add_child(val_label)

		_stat_rows[stat_id] = { "value_label": val_label, "stat_def": stat_def }

	elif fmt == "weeks":
		var val_label := Label.new()
		val_label.text = "0.0 wks"
		val_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_label.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
		val_label.add_theme_font_size_override("font_size", 14)
		row.add_child(val_label)

		_stat_rows[stat_id] = { "value_label": val_label, "stat_def": stat_def }

	return row
