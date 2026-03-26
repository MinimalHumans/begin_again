extends Control

var _data_points: Array = []   # Array of {game_day, value}
var _stat_def: Dictionary = {}


func plot(history: Array, stat_def: Dictionary) -> void:
	_data_points = history
	_stat_def = stat_def
	queue_redraw()


func _draw() -> void:
	if _data_points.is_empty():
		draw_string(
			ThemeDB.fallback_font, Vector2(8, 20),
			"No history yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color("#8a7f70")
		)
		return

	var w := size.x
	var h := size.y
	var pad_left := 8.0
	var pad_right := 8.0
	var pad_top := 8.0
	var pad_bottom := 8.0
	var chart_w := w - pad_left - pad_right
	var chart_h := h - pad_top - pad_bottom

	# Determine value range
	var min_val: float = float(_stat_def.get("min_value", 0.0))
	var max_val: float = float(_stat_def.get("max_value", 100.0))

	# For food, convert raw values to weeks for display
	var display_points: Array = _data_points.duplicate()
	if str(_stat_def.get("id", "")) == "food":
		display_points = display_points.map(func(p):
			return {"game_day": p.game_day, "value": float(p.value) / 7.0}
		)
		max_val = 20.0  # Cap food chart at 20 weeks for readability
		min_val = 0.0

	# Draw background
	draw_rect(Rect2(pad_left, pad_top, chart_w, chart_h), Color("#1a1a1a"))

	# Draw warning threshold line if applicable
	var warn_low = _stat_def.get("warning_low", null)
	if warn_low != null and float(warn_low) > 0:
		var warn_y: float = pad_top + chart_h - (float(warn_low) - min_val) / (max_val - min_val) * chart_h
		warn_y = clampf(warn_y, pad_top, pad_top + chart_h)
		_draw_dashed_line(
			Vector2(pad_left, warn_y), Vector2(pad_left + chart_w, warn_y),
			Color("#c8882a", 0.5), 1.0, 4.0
		)

	# Draw data line
	var first_day: int = int(display_points[0].game_day)
	var last_day: int = int(display_points[-1].game_day)
	var day_range: int = maxi(last_day - first_day, 1)

	var prev_pt: Vector2 = Vector2.ZERO
	for i in display_points.size():
		var p: Dictionary = display_points[i]
		var x: float = pad_left + (float(int(p.game_day) - first_day) / float(day_range)) * chart_w
		var y: float = pad_top + chart_h - clampf(
			(float(p.value) - min_val) / (max_val - min_val), 0.0, 1.0
		) * chart_h
		var pt := Vector2(x, y)
		if i > 0:
			# Colour line segment based on value at this point
			var colour := _value_colour(float(p.value), _stat_def)
			draw_line(prev_pt, pt, colour, 1.5)
		prev_pt = pt

	# Draw current value dot
	if not display_points.is_empty():
		draw_circle(prev_pt, 3.0, Color("#f0e8d0"))


func _value_colour(value: float, stat_def: Dictionary) -> Color:
	var crit = stat_def.get("critical_low", null)
	var warn = stat_def.get("warning_low", null)
	if crit != null and value <= float(crit):
		return Color("#b03030")
	elif warn != null and value <= float(warn):
		return Color("#c8882a")
	return Color("#5a9a5a")


func _draw_dashed_line(from: Vector2, to: Vector2, colour: Color, width: float, dash_length: float) -> void:
	var total := from.distance_to(to)
	var dir := (to - from).normalized()
	var travelled := 0.0
	var drawing := true
	while travelled < total:
		var segment_end := minf(travelled + dash_length, total)
		if drawing:
			draw_line(from + dir * travelled, from + dir * segment_end, colour, width)
		travelled = segment_end + dash_length * 0.5
		drawing = !drawing
