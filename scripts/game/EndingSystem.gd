class_name EndingSystem
extends RefCounted

# --- Module-level state (not static — accessed via singleton pattern) ---
# Because GDScript static methods can't access instance vars, we use a
# script-level dictionary as pseudo-static state.

static var _scene_root: Node = null
static var _ui_event_log: Node = null
static var _epilogue_entries: Array = []
static var _epilogue_index: int = 0
static var _epilogue_timer: Timer = null
static var _end_reason: String = ""
static var _end_stats: Dictionary = {}
static var _end_game_state: Dictionary = {}
static var _is_coda: bool = false


static func register(scene_root: Node, event_log: Node) -> void:
	_scene_root = scene_root
	_ui_event_log = event_log


static func abort() -> void:
	if _epilogue_timer != null and is_instance_valid(_epilogue_timer):
		_epilogue_timer.stop()
		_epilogue_timer.queue_free()
		_epilogue_timer = null
	_epilogue_entries = []
	_epilogue_index = 0
	_end_reason = ""
	_is_coda = false


# ---------- Epilogue Entry Point ----------

static func begin_epilogue(
	reason: String,
	final_stats: Dictionary,
	game_state: Dictionary
) -> void:
	_end_reason = reason
	_end_stats = final_stats.duplicate()
	_end_game_state = game_state.duplicate()
	_is_coda = false
	_epilogue_index = 0
	_epilogue_entries = _get_epilogue_entries(reason, game_state)

	_start_epilogue_timer(2.0)


static func begin_self_sacrifice_coda(
	final_stats: Dictionary,
	game_state: Dictionary
) -> void:
	_end_reason = "self_sacrifice"
	_end_stats = final_stats.duplicate()
	_end_game_state = game_state.duplicate()
	_is_coda = true
	_epilogue_index = 0
	_epilogue_entries = _get_coda_entries()

	_start_epilogue_timer(3.0)


# ---------- Timer Management ----------

static func _start_epilogue_timer(interval: float) -> void:
	if _scene_root == null:
		push_error("EndingSystem: _scene_root is null — call register() first")
		return

	_epilogue_timer = Timer.new()
	_epilogue_timer.wait_time = interval
	_epilogue_timer.one_shot = false
	_scene_root.add_child(_epilogue_timer)
	_epilogue_timer.timeout.connect(_on_epilogue_tick)
	_epilogue_timer.start()


static func _on_epilogue_tick() -> void:
	if _epilogue_index >= _epilogue_entries.size():
		# All entries delivered — stop timer, wait 3 seconds, show ending screen
		_epilogue_timer.stop()
		_epilogue_timer.queue_free()
		_epilogue_timer = null

		var delay_timer := Timer.new()
		delay_timer.wait_time = 3.0
		delay_timer.one_shot = true
		_scene_root.add_child(delay_timer)
		delay_timer.timeout.connect(func():
			delay_timer.queue_free()
			show_ending_screen()
		)
		delay_timer.start()
		return

	var text: String = _epilogue_entries[_epilogue_index]
	var game_day: int = int(_end_game_state.get("game_day", 0)) + _epilogue_index
	_epilogue_index += 1

	# Write to DB
	DatabaseManager.execute_save(
		"INSERT INTO event_log (game_day, tier, category, display_text, is_highlighted, is_major) VALUES (?, 1, 'epilogue', ?, 0, 0);",
		[game_day, text]
	)

	# Append to UI
	var entry := {
		"game_day": game_day,
		"tier": 1,
		"category": "epilogue",
		"display_text": text,
		"is_highlighted": 0,
		"is_major": 0
	}
	if _ui_event_log:
		_ui_event_log.append_entry(entry)


# ---------- Epilogue Entry Definitions ----------

static func _get_epilogue_entries(reason: String, game_state: Dictionary) -> Array:
	match reason:
		"population_collapse":
			return _entries_population_collapse(game_state)
		"starvation":
			return _entries_starvation()
		"cohesion_failure":
			return _entries_cohesion_failure()
		"overthrow":
			return _entries_overthrow()
		"extinction":
			return _entries_extinction()
	return ["The end came."]


static func _entries_population_collapse(game_state: Dictionary) -> Array:
	var building := _random_structure(game_state)
	return [
		"Five people remain. The settlement feels enormous now.",
		"Nobody talks much. There isn't much to say.",
		"The fires are smaller. Less wood needed.",
		"Someone packed their things and left without a word. Four now.",
		"The last ones sit together in %s. Not speaking. Just present." % building,
		"Morning. The settlement is quiet in a way that has no word for it."
	]


static func _entries_starvation() -> Array:
	return [
		"The last of the food was divided this morning.",
		"People are working on empty stomachs. Slower. Quieter.",
		"The first person collapsed today. Others helped them inside.",
		"Rationing beyond rationing. Some are giving their share to others.",
		"Three people left to find something. They haven't come back.",
		"The calculation everyone was avoiding has arrived. There is nothing left.",
		"The community ends not with a fight but with an absence. Hunger is patient."
	]


static func _entries_cohesion_failure() -> Array:
	return [
		"The fault lines became walls overnight.",
		"Two groups eat separately now. The common area is empty.",
		"An argument this morning. The kind that doesn't resolve.",
		"Half the community packed up and left together. They didn't say where.",
		"The ones who stayed are strangers to each other.",
		"By evening, even they were gone. The settlement stands empty."
	]


static func _entries_overthrow() -> Array:
	var dominant := CommunityIdentity.get_dominant_type()
	var type_id: String = dominant.get("type_id", "") if not dominant.is_empty() else ""

	var final_entry: String
	match type_id:
		"commonwealth":
			final_entry = "You step down. It is the right thing and you know it."
		"throne":
			final_entry = "You resist. Briefly. Then the weight of it is clear."
		"bastion":
			final_entry = "The chain of command is invoked. You are part of it, until you aren't."
		_:
			final_entry = "There is nothing left to say. You go."

	return [
		"The meeting was called without warning.",
		"It was quick. The decision had already been made before anyone spoke.",
		"You are asked to leave your post. The words are formal. The intent is not.",
		"A successor is named. The community watches to see what you do.",
		final_entry
	]


static func _entries_extinction() -> Array:
	return [
		"Something happened that cannot be taken back.",
		"It moved through the settlement faster than response was possible.",
		"The last entry in the log is written by no one in particular.",
		"The settlement is quiet. It will be quiet for a long time."
	]


# ---------- Self-Sacrifice Coda ----------

static func _get_coda_entries() -> Array:
	# Get a random living community member name for entry 6
	var member_name := "Someone"
	var pop_rows := DatabaseManager.query_save(
		"SELECT name FROM population WHERE alive = 1 ORDER BY RANDOM() LIMIT 1;"
	)
	if pop_rows.size() > 0:
		member_name = str(pop_rows[0].get("name", "Someone"))

	return [
		"The community moved on. They had to.",
		"The first night without you, someone kept the fire going longer than necessary.",
		"Work continued the next morning. That is what you would have wanted.",
		"A small marker was placed where you made the decision. Nobody organised it.",
		"The community is smaller now, but it holds together.",
		"%s has taken on the role of organiser. Quietly, without ceremony." % member_name,
		"Weeks pass. The community that you built is still here.",
		"They are not the same as before. Nothing is. But they endure.",
		"The settlement carries your work in its structure, its habits, its shape.",
		"Whatever comes next, this was real. It mattered."
	]


# ---------- Ending Screen ----------

static func show_ending_screen() -> void:
	if _scene_root == null:
		push_error("EndingSystem: scene root not registered")
		return
	var dominant := CommunityIdentity.get_dominant_type()
	var secondary := CommunityIdentity.get_secondary_type()
	var dominant_type_row: Dictionary = {}
	if not dominant.is_empty():
		dominant_type_row = GameData.get_community_type(dominant.type_id)
	var secondary_type_row: Dictionary = {}
	if not secondary.is_empty() and secondary.score > 20:
		secondary_type_row = GameData.get_community_type(secondary.type_id)

	var final_stats: Dictionary = {}
	for row in DatabaseManager.query_save("SELECT stat_id, value FROM current_stats"):
		final_stats[str(row.stat_id)] = float(row.value)

	var gs_rows := DatabaseManager.query_save("SELECT * FROM game_state LIMIT 1")
	var game_state: Dictionary = gs_rows[0] if gs_rows.size() > 0 else _end_game_state

	var narrative := _build_narrative(_end_reason, final_stats, game_state, dominant_type_row)

	var peak_pop: float = final_stats.get("population", 0)
	var peak_pop_row := DatabaseManager.query_save(
		"SELECT MAX(value) as peak FROM stat_history WHERE stat_id = 'population'"
	)
	if not peak_pop_row.is_empty():
		peak_pop = float(peak_pop_row[0].get("peak", peak_pop))

	var decision_count: int = 0
	var decision_count_row := DatabaseManager.query_save(
		"SELECT COUNT(*) as n FROM event_log WHERE tier >= 2 AND choice_made IS NOT NULL"
	)
	if not decision_count_row.is_empty():
		decision_count = int(decision_count_row[0].get("n", 0))

	var stats_summary := {
		"game_day": int(game_state.get("game_day", 0)),
		"population": int(final_stats.get("population", 0)),
		"peak_population": int(peak_pop),
		"decisions": decision_count,
		"community_name": str(dominant_type_row.get("display_name", "Unknown"))
	}

	var screen = preload("res://scenes/ui/EndingScreen.tscn").instantiate()
	_scene_root.add_child(screen)
	screen.present(_end_reason, final_stats, game_state, narrative,
		dominant_type_row, secondary_type_row, stats_summary)
	screen.new_game_requested.connect(func(): _scene_root.call_deferred("start_new_game"))


# ---------- Narrative Builder ----------

static func _build_narrative(
	reason: String,
	final_stats: Dictionary,
	game_state: Dictionary,
	dominant_type_row: Dictionary
) -> String:
	var game_day: int = int(game_state.get("game_day", 0))
	var peak_pop: float = 0
	var peak_row := DatabaseManager.query_save(
		"SELECT MAX(value) as peak FROM stat_history WHERE stat_id = 'population'"
	)
	if not peak_row.is_empty():
		peak_pop = float(peak_row[0].get("peak", final_stats.get("population", 0)))
	var peak_pop_int: int = int(peak_pop) if peak_pop > 0 else int(final_stats.get("population", 0))

	var community_type_line := ""
	var reveal_text: String = str(dominant_type_row.get("reveal_text", ""))
	if reveal_text != "":
		# Take first sentence
		var dot_pos := reveal_text.find(".")
		if dot_pos >= 0:
			community_type_line = reveal_text.substr(0, dot_pos + 1)
		else:
			community_type_line = reveal_text

	match reason:
		"starvation":
			var food_line := _get_food_situation_line(game_state)
			return "The community of %d survived for %d days before hunger ended it. %s The decisions that led here were made one at a time, each one reasonable, the sum of them fatal. %s" % [peak_pop_int, game_day, food_line, community_type_line]

		"cohesion_failure":
			var cohesion_line := _get_cohesion_line(final_stats)
			return "For %d days, %d people tried to hold together what the world had broken apart. %s In the end, what undid them was not the outside world but the distance between people standing three feet apart. %s" % [game_day, peak_pop_int, cohesion_line, community_type_line]

		"population_collapse":
			var pop_line := _get_pop_decline_line()
			return "They endured %d days. At the peak there were %d of them. %s The last ones did not go dramatically. They simply did not continue. %s" % [game_day, peak_pop_int, pop_line, community_type_line]

		"overthrow":
			var leadership_line := _get_leadership_line(dominant_type_row)
			return "For %d days you led %d people through the aftermath of everything. %s The community decided it needed something different. Whether they were right is not for you to say. %s" % [game_day, peak_pop_int, leadership_line, community_type_line]

		"extinction":
			return "In %d days, %d people built something. Then something ended it. %s The settlement stands empty now." % [game_day, peak_pop_int, community_type_line]

		"self_sacrifice":
			var sacrifice_lines: Array[String] = ["The community you built carried that forward.", "They remembered.", "It was enough."]
			var sacrifice_line: String = sacrifice_lines[randi() % 3]
			return "You led %d people for %d days. At the end, when the choice came, you made it without hesitation. %s What you built outlasted you. That was the point." % [peak_pop_int, game_day, sacrifice_line]

	return "The story ended on day %d." % game_day


static func _get_food_situation_line(game_state: Dictionary) -> String:
	var food_prod: float = float(game_state.get("food_production", 0.0))
	if food_prod < 0.5:
		return "Farming was never established."
	elif food_prod < 2.0:
		return "Production couldn't keep up with the mouths."
	else:
		return "A late winter depleted reserves that never recovered."


static func _get_cohesion_line(final_stats: Dictionary) -> String:
	var pop: float = float(final_stats.get("population", 0))
	if pop > 20:
		return "The community grew too large for its bonds to hold."
	else:
		return "Decisions were made that divided more than they united."


static func _get_pop_decline_line() -> String:
	# Check event log for death causes
	var death_count := DatabaseManager.query_save(
		"SELECT COUNT(*) as n FROM event_log WHERE category = 'death'"
	)
	var departure_count := DatabaseManager.query_save(
		"SELECT COUNT(*) as n FROM event_log WHERE category = 'departure'"
	)
	var deaths: int = int(death_count[0].get("n", 0)) if not death_count.is_empty() else 0
	var departures: int = int(departure_count[0].get("n", 0)) if not departure_count.is_empty() else 0

	if deaths > departures * 2:
		return "Disease took many."
	elif departures > deaths:
		return "Departures were steady."
	else:
		return "The numbers never recovered from an early crisis."


static func _get_leadership_line(dominant_type_row: Dictionary) -> String:
	var type_id: String = str(dominant_type_row.get("id", ""))
	match type_id:
		"throne":
			return "You made every decision alone."
		"commonwealth":
			return "Every voice was heard, in the end too many of them."
		"bastion":
			return "Order was maintained until it wasn't."
		"congregation":
			return "Faith held the community together, until it didn't."
		"kindred":
			return "The bonds of family frayed under pressure."
		"exchange":
			return "Every deal was fair. Fairness wasn't enough."
		"archive":
			return "Knowledge was preserved. The people were not."
		"rewilded":
			return "The land gave what it could. It was not enough."
	return "Leadership is a weight that eventually finds its limit."


# ---------- Utility ----------

static func _random_structure(game_state: Dictionary) -> String:
	var location_id: String = str(game_state.get("location_id", ""))
	if location_id == "":
		return "the main building"
	var rows := DatabaseManager.query_library(
		"SELECT structures FROM locations WHERE id = ?;", [location_id]
	)
	if rows.size() > 0:
		var parsed = JSON.parse_string(str(rows[0].get("structures", "[]")))
		if parsed is Array and parsed.size() > 0:
			return str(parsed[randi() % parsed.size()])
	return "the main building"
