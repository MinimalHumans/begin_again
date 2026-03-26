extends PanelContainer

const COL_BG := Color("#222222")
const COL_BORDER := Color("#7a6a50")
const COL_TITLE := Color("#f0e8d0")
const COL_DIM := Color("#8a7f70")
const COL_DESC := Color("#e0d5c0")

var _stat_name_label: Label
var _stat_value_label: Label
var _trend_label: Label
var _chart_container: Control
var _derived_label: RichTextLabel


func _ready() -> void:
	# Style the panel
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

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Header row
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)

	_stat_name_label = Label.new()
	_stat_name_label.add_theme_font_size_override("font_size", 16)
	_stat_name_label.add_theme_color_override("font_color", COL_TITLE)
	_stat_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_stat_name_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", COL_DIM)
	close_btn.add_theme_color_override("font_hover_color", COL_TITLE)
	close_btn.pressed.connect(func(): hide())
	header.add_child(close_btn)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Value label
	_stat_value_label = Label.new()
	_stat_value_label.add_theme_font_size_override("font_size", 13)
	_stat_value_label.add_theme_color_override("font_color", COL_DIM)
	vbox.add_child(_stat_value_label)

	# Trend label
	_trend_label = Label.new()
	_trend_label.add_theme_font_size_override("font_size", 12)
	_trend_label.add_theme_color_override("font_color", COL_DIM)
	vbox.add_child(_trend_label)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size.y = 8
	vbox.add_child(spacer1)

	# Chart container
	_chart_container = Control.new()
	_chart_container.custom_minimum_size.y = 180
	_chart_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_chart_container)

	# Separator before derived values
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Derived values
	_derived_label = RichTextLabel.new()
	_derived_label.bbcode_enabled = false
	_derived_label.fit_content = true
	_derived_label.scroll_active = false
	_derived_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_derived_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_derived_label.add_theme_font_size_override("normal_font_size", 13)
	_derived_label.add_theme_color_override("default_color", COL_DESC)
	vbox.add_child(_derived_label)


func load_stat(stat_id: String) -> void:
	var stat_def: Dictionary = GameData.get_stat(stat_id)
	if stat_def.is_empty():
		return

	var current_row := DatabaseManager.query_save(
		"SELECT value, trend FROM current_stats WHERE stat_id = ?", [stat_id]
	)
	var history := DatabaseManager.query_save(
		"SELECT game_day, value FROM stat_history WHERE stat_id = ? ORDER BY game_day ASC",
		[stat_id]
	)
	var gs_rows := DatabaseManager.query_save("SELECT * FROM game_state LIMIT 1")
	var game_state: Dictionary = {}
	if gs_rows.size() > 0:
		game_state = gs_rows[0]

	_stat_name_label.text = str(stat_def.get("display_name", stat_id))

	if not current_row.is_empty():
		_stat_value_label.text = "Current: " + _format_stat_value(stat_id, float(current_row[0].get("value", 0)), game_state)
		_trend_label.text = "Trend: " + str(current_row[0].get("trend", "stable")).capitalize()
	else:
		_stat_value_label.text = "Current: —"
		_trend_label.text = "Trend: —"

	# Build chart
	for child in _chart_container.get_children():
		child.queue_free()
	var chart: Control = preload("res://scenes/ui/StatChart.tscn").instantiate()
	_chart_container.add_child(chart)
	chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	chart.plot(history, stat_def)

	# Build derived values
	_derived_label.text = _build_derived_text(stat_id, game_state)


func _format_stat_value(stat_id: String, value: float, game_state: Dictionary) -> String:
	match stat_id:
		"population":
			return str(int(value))
		"food":
			var pop_rows := DatabaseManager.query_save(
				"SELECT value FROM current_stats WHERE stat_id = 'population'"
			)
			var pop: float = 1.0
			if pop_rows.size() > 0:
				pop = float(pop_rows[0].get("value", 1))
			var food_drain: float = GameData.get_config("FOOD_DRAIN_PER_PERSON")
			var weeks: float = value / maxf(pop, 1.0) / maxf(food_drain, 0.01) / 7.0
			return "%.1f weeks" % weeks
		_:
			return "%d / 100" % int(value)


func _build_derived_text(stat_id: String, game_state: Dictionary) -> String:
	var lines: Array = []

	match stat_id:
		"population":
			var living := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 1")
			var dead := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 0 AND death_cause != 'departed'")
			var departed := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 0 AND death_cause = 'departed'")
			lines.append("Living: %d" % _count(living))
			lines.append("Dead: %d" % _count(dead))
			lines.append("Departed: %d" % _count(departed))

		"food":
			var pop_rows := DatabaseManager.query_save("SELECT value FROM current_stats WHERE stat_id = 'population'")
			var pop: float = maxf(_val(pop_rows), 1.0)
			var food_drain: float = GameData.get_config("FOOD_DRAIN_PER_PERSON")
			var food_rows := DatabaseManager.query_save("SELECT value FROM current_stats WHERE stat_id = 'food'")
			var food_val: float = _val(food_rows)
			var weeks: float = food_val / maxf(pop, 1.0) / maxf(food_drain, 0.01) / 7.0
			var daily_drain: float = pop * food_drain
			var daily_prod: float = float(game_state.get("food_production", 0))
			lines.append("Weeks remaining: %.1f" % weeks)
			lines.append("Daily drain: %.1f" % daily_drain)
			lines.append("Daily production: %.1f" % daily_prod)
			lines.append("Net daily change: %.1f" % (daily_prod - daily_drain))

		"health":
			var injured := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 1 AND flags LIKE '%injured%'")
			var sick := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 1 AND flags LIKE '%sick%'")
			var medics := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 1 AND assigned_role = 'medic'")
			var decay: float = GameData.get_config("HEALTH_DECAY_RATE")
			lines.append("Injured: %d" % _count(injured))
			lines.append("Sick: %d" % _count(sick))
			lines.append("Medics active: %d" % _count(medics))
			lines.append("Daily decay rate: %.2f" % decay)

		"security":
			var guards := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 1 AND assigned_role = 'guard'")
			var guard_role := DatabaseManager.query_library("SELECT max_slots FROM roles WHERE id = 'guard'")
			var max_slots: int = 0
			if guard_role.size() > 0:
				max_slots = int(guard_role[0].get("max_slots", 0))
			var decay: float = GameData.get_config("SECURITY_DECAY_RATE")
			lines.append("Guards: %d / %d" % [_count(guards), max_slots])
			lines.append("Daily decay rate: %.2f" % decay)

		"knowledge":
			var teachers := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 1 AND assigned_role = 'teacher'")
			var teach_rate: float = GameData.get_config("TEACHING_RATE")
			lines.append("Teachers active: %d" % _count(teachers))
			lines.append("Teaching rate: %.2f/day" % teach_rate)
			# Count skilled members
			var skills := GameData.get_all_skill_ids()
			for skill_id in skills:
				var skilled := DatabaseManager.query_save(
					"SELECT COUNT(*) AS cnt FROM population WHERE alive = 1 AND skills LIKE '%%%s%%'" % skill_id
				)
				lines.append("  %s: %d members" % [skill_id.capitalize(), _count(skilled)])

		"morale":
			# Baseline from related stats
			var stat_ids := ["health", "food", "security", "cohesion"]
			var total: float = 0.0
			for sid in stat_ids:
				var r := DatabaseManager.query_save("SELECT value FROM current_stats WHERE stat_id = ?", [sid])
				if sid == "food":
					# Convert to effective 0-100 scale based on weeks
					var pop_rows := DatabaseManager.query_save("SELECT value FROM current_stats WHERE stat_id = 'population'")
					var pop := maxf(_val(pop_rows), 1.0)
					var fd := GameData.get_config("FOOD_DRAIN_PER_PERSON")
					var wks := _val(r) / pop / maxf(fd, 0.01) / 7.0
					total += clampf(wks / 6.0 * 100.0, 0.0, 100.0)
				else:
					total += _val(r)
			var baseline: float = total / 4.0
			var drift: float = GameData.get_config("MORALE_DRIFT_RATE")
			lines.append("Morale baseline: %.0f" % baseline)
			lines.append("Drift rate: %.2f/day" % drift)

		"cohesion":
			var pop_rows := DatabaseManager.query_save("SELECT value FROM current_stats WHERE stat_id = 'population'")
			var pop: float = _val(pop_rows)
			var threshold: float = GameData.get_config("COHESION_POP_THRESHOLD")
			var drift: float = GameData.get_config("COHESION_DRIFT_RATE")
			lines.append("Population: %d (threshold: %d)" % [int(pop), int(threshold)])
			lines.append("Drift rate: %.2f/day" % drift)

		"stability":
			var has_council := FlagSystem.has_flag("council_established")
			var has_succession := FlagSystem.has_flag("succession_planned")
			lines.append("Council established: %s" % ("Yes" if has_council else "No"))
			lines.append("Succession planned: %s" % ("Yes" if has_succession else "No"))

		"reputation":
			var drift: float = GameData.get_config("REPUTATION_DRIFT_RATE")
			var rep_rows := DatabaseManager.query_save("SELECT value FROM current_stats WHERE stat_id = 'reputation'")
			var rep: float = _val(rep_rows)
			var direction := "toward 50"
			if rep > 50:
				direction = "drifting down"
			elif rep < 50:
				direction = "drifting up"
			else:
				direction = "at equilibrium"
			lines.append("Daily drift: %.2f" % drift)
			lines.append("Direction: %s" % direction)

		"resources":
			var drain: float = GameData.get_config("RESOURCE_DRAIN_PER_PERSON")
			var pop_rows := DatabaseManager.query_save("SELECT value FROM current_stats WHERE stat_id = 'population'")
			var pop: float = _val(pop_rows)
			var scavengers := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 1 AND assigned_role = 'scavenger'")
			lines.append("Daily drain: %.1f" % (drain * pop))
			lines.append("Scavengers active: %d" % _count(scavengers))

	return "\n".join(lines)


func _count(rows: Array) -> int:
	if rows.is_empty():
		return 0
	return int(rows[0].get("cnt", 0))


func _val(rows: Array) -> float:
	if rows.is_empty():
		return 0.0
	return float(rows[0].get("value", 0.0))
