extends Node

signal day_advanced(new_day: int, new_season: String)
signal log_entry_added(entry: Dictionary)
signal game_over_triggered(reason: String)

var current_speed: int = 0
var _tick_accumulator: float = 0.0
var _ui_stats_panel: Node = null
var _ui_event_log: Node = null

# Tick entries generated during current tick, flushed at end
var _pending_log_entries: Array = []

# Cache stat definitions from library for clamping
var _stat_defs: Dictionary = {}  # stat_id -> { min_value, max_value }

# Phase 2a: State for event engine
var _current_state_tags: Array[String] = []
var _current_world_tags: Array[String] = []
var _current_flags: Array[String] = []
var _current_cooldowns: Array = []
var _current_occurrence_counts: Dictionary = {}
var _current_game_day: int = 0


func _ready() -> void:
	set_process(true)


func set_speed(speed: int) -> void:
	current_speed = clampi(speed, 0, 2)
	_tick_accumulator = 0.0


func register_ui(event_log: Node, stats_panel: Node) -> void:
	_ui_event_log = event_log
	_ui_stats_panel = stats_panel


func _process(delta: float) -> void:
	if current_speed == 0:
		return

	var interval: float
	match current_speed:
		1:
			interval = 2.0   # 0.5 days/sec → 1 day every 2 seconds
		2:
			interval = 0.333 # 3 days/sec → 1 day every ~0.333 seconds
		_:
			return

	_tick_accumulator += delta
	if _tick_accumulator >= interval:
		_tick_accumulator -= interval
		_run_tick()


func _run_tick() -> void:
	_pending_log_entries.clear()

	# --- Step 1: Load current state ---
	var gs_rows := DatabaseManager.query_save("SELECT * FROM game_state WHERE id = 1;")
	if gs_rows.size() == 0:
		return
	var game_state: Dictionary = gs_rows[0]
	var game_day: int = game_state["game_day"]

	var stat_rows := DatabaseManager.query_save("SELECT stat_id, value FROM current_stats;")
	var stats: Dictionary = {}
	for row in stat_rows:
		stats[row["stat_id"]] = float(row["value"])

	var pop_rows := DatabaseManager.query_save(
		"SELECT id, name, age, gender, alive, skills, personality, flags, assigned_role, joined_day, last_mentioned FROM population WHERE alive = 1;"
	)

	var roles := GameData.get_all_roles()

	# Load all config values
	var config_keys := [
		"FOOD_DRAIN_PER_PERSON", "RESOURCE_DRAIN_PER_PERSON",
		"HEALTH_DECAY_RATE", "SECURITY_DECAY_RATE",
		"MORALE_DRIFT_RATE", "COHESION_DRIFT_RATE", "REPUTATION_DRIFT_RATE",
		"TEACHING_RATE", "COHESION_POP_THRESHOLD", "COHESION_POP_PENALTY",
		"SEASON_SPRING", "SEASON_SUMMER", "SEASON_FALL", "SEASON_WINTER",
		"BASE_BIRTH_RATE", "BASE_MORTALITY_RATE",
		"DEPARTURE_MORALE_THRESHOLD", "DEPARTURE_RATE"
	]
	var config: Dictionary = {}
	for key in config_keys:
		config[key] = GameData.get_config(key)

	# Cache stat definitions for clamping (lazy load once)
	if _stat_defs.is_empty():
		var all_stats := GameData.get_all_stats()
		for s in all_stats:
			_stat_defs[s["id"]] = s

	var gs_for_sim := game_state.duplicate()
	gs_for_sim["daily_health_pressure"] = float(game_state.get("daily_health_pressure", 0.0))

	# --- Step 1b: Load event engine state ---
	_current_game_day = game_day
	FlagSystem.invalidate_cache()
	_current_world_tags = _load_world_tags()
	_current_flags = _load_flags()
	_current_cooldowns = _load_cooldowns()
	_current_occurrence_counts = _load_occurrence_counts()

	# --- Step 2: Calculate role bonuses ---
	var role_bonuses: Dictionary = {}
	var role_food_production: float = 0.0
	_calculate_role_bonuses(roles, pop_rows, role_bonuses, role_food_production)
	# GDScript can't return multiple values cleanly, so recalculate food_production inline
	role_food_production = _calculate_role_food_production(roles, pop_rows)

	# --- Step 3: Run PassiveSimulation ---
	var deltas := PassiveSimulation.run_tick(stats, gs_for_sim, role_bonuses, config, role_food_production)

	# --- Step 4: Apply stat deltas ---
	var stability_factor: float = 0.5 + (float(stats.get("stability", 50.0)) / 100.0) * 0.5
	for stat_id in deltas:
		var delta_val: float = deltas[stat_id]
		if delta_val > 0:
			delta_val *= stability_factor
		var new_val: float = float(stats.get(stat_id, 0.0)) + delta_val
		# Clamp to stat min/max
		if _stat_defs.has(stat_id):
			var sdef: Dictionary = _stat_defs[stat_id]
			new_val = clampf(new_val, float(sdef["min_value"]), float(sdef["max_value"]))
		stats[stat_id] = new_val
		DatabaseManager.execute_save(
			"UPDATE current_stats SET value = ? WHERE stat_id = ?;",
			[new_val, stat_id]
		)

	# --- Step 4b: Compute state tags ---
	var recent_log := _load_recent_log_days(game_day)
	var known_skills := GameData.get_all_skill_ids()
	_current_state_tags = StateTagSystem.compute(stats, pop_rows, gs_for_sim, known_skills, recent_log)

	# --- Step 5: Run PopulationLifecycle ---
	var lifecycle := PopulationLifecycle.run_tick(pop_rows, stats, gs_for_sim, config)

	# Process deaths
	for death in lifecycle["deaths"]:
		DatabaseManager.execute_save(
			"UPDATE population SET alive = 0, died_day = ?, death_cause = ? WHERE id = ?;",
			[game_day, death["cause"], death["id"]]
		)
		# Check if they had a role
		_handle_role_vacancy(death["id"], death["name"], game_day, pop_rows)
		var new_count := _get_living_count()
		_write_log_entry(game_day, 1, "death",
			"%s died on day %d. The community now numbers %d." % [death["name"], game_day, new_count])

	# Process departures
	for departure in lifecycle["departures"]:
		DatabaseManager.execute_save(
			"UPDATE population SET alive = 0, died_day = ?, death_cause = 'departed' WHERE id = ?;",
			[game_day, departure["id"]]
		)
		_handle_role_vacancy(departure["id"], departure["name"], game_day, pop_rows)
		var new_count := _get_living_count()
		_write_log_entry(game_day, 1, "departure",
			"%s slipped away during the night. The community now numbers %d." % [departure["name"], new_count])

	# Process births
	for birth in lifecycle["births"]:
		var birth_name := _pick_available_name(birth["gender"])
		var new_id := "p_%03d" % _get_next_person_id()
		DatabaseManager.execute_save(
			"INSERT INTO population (id, name, age, gender, alive, joined_day, skills, personality) VALUES (?, ?, ?, ?, 1, ?, ?, ?);",
			[new_id, birth_name, birth["age"], birth["gender"], game_day, birth["skills"], birth["personality"]]
		)
		var new_count := _get_living_count()
		_write_log_entry(game_day, 1, "birth",
			"A child was born on day %d. The community now numbers %d." % [game_day, new_count])

	# Update population stat
	var living_count := _get_living_count()
	stats["population"] = living_count
	DatabaseManager.execute_save(
		"UPDATE current_stats SET value = ? WHERE stat_id = 'population';",
		[living_count]
	)

	# --- Step 5b: Fire Tier 1 ambient events ---
	# Re-fetch living population after lifecycle changes
	var pop_after := DatabaseManager.query_save(
		"SELECT id, name, age, gender, alive, skills, personality, flags, assigned_role, joined_day, last_mentioned, mention_context FROM population WHERE alive = 1;"
	)
	_fire_ambient_events(stats, pop_after, gs_for_sim)

	# --- Step 5c: Generate stat warnings ---
	_maybe_generate_stat_warning(game_day, stats)

	# --- Step 6: Update season ---
	var day_of_year: int = (game_state["starting_day_of_year"] + game_day) % 365
	var new_season := _get_season(day_of_year)
	if new_season != game_state["season"]:
		DatabaseManager.execute_save(
			"UPDATE game_state SET season = ? WHERE id = 1;",
			[new_season]
		)

	# --- Step 7: Snapshot stat history (every 7 days) ---
	if game_day % 7 == 0:
		for stat_id in stats:
			DatabaseManager.execute_save(
				"INSERT INTO stat_history (stat_id, game_day, value) VALUES (?, ?, ?);",
				[stat_id, game_day, stats[stat_id]]
			)

	# --- Step 8: Update stat trends (every 14 days) ---
	if game_day % 14 == 0:
		for stat_id in stats:
			var hist := DatabaseManager.query_save(
				"SELECT value FROM stat_history WHERE stat_id = ? AND game_day = ?;",
				[stat_id, game_day - 14]
			)
			if hist.size() > 0:
				var old_val: float = float(hist[0]["value"])
				var diff: float = stats[stat_id] - old_val
				var trend := "stable"
				if diff >= 3.0:
					trend = "rising"
				elif diff <= -3.0:
					trend = "falling"
				DatabaseManager.execute_save(
					"UPDATE current_stats SET trend = ? WHERE stat_id = ?;",
					[trend, stat_id]
				)

	# --- Step 9: Increment difficulty_time_factor ---
	var dtf: float = float(game_state.get("difficulty_time_factor", 0.0))
	dtf += 0.025 / 30.0
	DatabaseManager.execute_save(
		"UPDATE game_state SET difficulty_time_factor = ? WHERE id = 1;",
		[dtf]
	)

	# --- Step 10: Check loss conditions ---
	if float(stats.get("population", 0)) < 3:
		_trigger_game_over("Population collapse")
		return
	if float(stats.get("food", 0)) <= 0:
		_trigger_game_over("Starvation")
		return
	if float(stats.get("cohesion", 0)) <= 0:
		_trigger_game_over("Cohesion failure")
		return

	# --- Step 11: Advance game_day ---
	game_day += 1
	DatabaseManager.execute_save(
		"UPDATE game_state SET game_day = ? WHERE id = 1;",
		[game_day]
	)

	# --- Step 12: Notify UI ---
	day_advanced.emit(game_day, new_season)
	if _ui_stats_panel:
		_ui_stats_panel.refresh()
	for entry in _pending_log_entries:
		log_entry_added.emit(entry)
		if _ui_event_log:
			_ui_event_log.append_entry(entry)


# ---------- Tier 1 Ambient Event Firing ----------

# Cache for location structures (location_id -> Array)
var _location_structures_cache: Dictionary = {}

func _fire_ambient_events(stats: Dictionary, population: Array, game_state: Dictionary) -> void:
	if population.size() == 0:
		return

	var game_day: int = int(game_state.get("game_day", _current_game_day))

	# Roll event count: 0 (15%), 1 (45%), 2 (30%), 3 (10%)
	var r := randf()
	var event_count: int
	if r < 0.15:
		event_count = 0
	elif r < 0.60:
		event_count = 1
	elif r < 0.90:
		event_count = 2
	else:
		event_count = 3

	if event_count == 0:
		return

	# Build eligible pool of Tier 1 events
	var all_events := GameData.get_all_events()
	var eligible_pool: Array = []
	for ev in all_events:
		if int(ev.get("tier", 0)) != 1:
			continue
		if EligibilityEngine.is_eligible(
			ev, _current_world_tags, _current_state_tags, stats,
			_current_flags, population, game_day,
			_current_cooldowns, _current_occurrence_counts
		):
			eligible_pool.append(ev)

	if eligible_pool.size() == 0:
		return

	# Fetch location structures (cached)
	var location_id: String = str(game_state.get("location_id", ""))
	var structures: Array = _get_location_structures(location_id)

	# Fire events
	var fired := 0
	while fired < event_count and eligible_pool.size() > 0:
		# Weighted random selection from pool
		var selected_event: Dictionary = _weighted_select_event(eligible_pool)
		if selected_event.is_empty():
			break

		# Cast actors
		var cast_actors: Dictionary = {}
		var req_raw = selected_event.get("actor_requirements")
		if req_raw != null and str(req_raw).strip_edges() != "":
			var cast_ok := false
			var attempts := 0
			while not cast_ok and attempts < 3:
				cast_actors = ActorCaster.cast(selected_event, population, game_day)
				if cast_actors.is_empty():
					attempts += 1
				else:
					cast_ok = true
			if not cast_ok:
				# Remove failed event from pool and try next
				eligible_pool.erase(selected_event)
				continue

		# Resolve template
		var template_text: String = str(selected_event.get("description_template", ""))
		var resolved := TemplateResolver.resolve_event(
			template_text, cast_actors, stats, game_state, structures, {}
		)

		# Write log entry
		var category: String = str(selected_event.get("category", "ambient"))
		var event_id: String = str(selected_event.get("id", ""))
		DatabaseManager.execute_save(
			"INSERT INTO event_log (game_day, tier, event_id, category, display_text, is_highlighted, is_major) VALUES (?, 1, ?, ?, ?, 0, 0);",
			[game_day, event_id, category, resolved]
		)
		var entry := {
			"game_day": game_day,
			"tier": 1,
			"category": category,
			"display_text": resolved,
			"event_id": event_id,
			"is_highlighted": 0,
			"is_major": 0
		}
		_pending_log_entries.append(entry)

		# Update actor last_mentioned and mention_context
		for actor_key in cast_actors:
			var person: Dictionary = cast_actors[actor_key]
			var pid: String = str(person.get("id", ""))
			var mention_ctx := _get_mention_context(category, structures, game_day)
			DatabaseManager.execute_save(
				"UPDATE population SET last_mentioned = ?, mention_context = ? WHERE id = ?;",
				[game_day, mention_ctx, pid]
			)

		# Record cooldown
		var cd_days = selected_event.get("cooldown_days", 0)
		if cd_days != null and int(cd_days) > 0:
			DatabaseManager.execute_save(
				"INSERT INTO cooldowns (event_id, exclusion_group, expires_day) VALUES (?, NULL, ?);",
				[event_id, game_day + int(cd_days)]
			)
		var excl = selected_event.get("exclusion_group")
		if excl != null and str(excl) != "":
			DatabaseManager.execute_save(
				"INSERT INTO cooldowns (event_id, exclusion_group, expires_day) VALUES (NULL, ?, ?);",
				[str(excl), game_day + int(selected_event.get("cooldown_days", 7))]
			)

		# Increment occurrence count
		var prev_count: int = _current_occurrence_counts.get(event_id, 0)
		DatabaseManager.execute_save(
			"INSERT OR REPLACE INTO event_occurrence_counts (event_id, count) VALUES (?, ?);",
			[event_id, prev_count + 1]
		)
		_current_occurrence_counts[event_id] = prev_count + 1

		# Add to cooldowns cache so same event doesn't fire again this tick
		_current_cooldowns.append({
			"event_id": event_id,
			"exclusion_group": selected_event.get("exclusion_group"),
			"expires_day": game_day + maxi(int(cd_days if cd_days != null else 0), 1)
		})

		# Remove from pool
		eligible_pool.erase(selected_event)
		fired += 1


func _weighted_select_event(pool: Array) -> Dictionary:
	if pool.size() == 0:
		return {}
	var total_weight: float = 0.0
	for ev in pool:
		total_weight += float(ev.get("weight", 1.0))
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for ev in pool:
		cumulative += float(ev.get("weight", 1.0))
		if roll <= cumulative:
			return ev
	return pool[pool.size() - 1]


func _get_location_structures(location_id: String) -> Array:
	if _location_structures_cache.has(location_id):
		return _location_structures_cache[location_id]
	var rows := DatabaseManager.query_library(
		"SELECT structures FROM locations WHERE id = ?;", [location_id]
	)
	var structures: Array = []
	if rows.size() > 0:
		var parsed = JSON.parse_string(str(rows[0].get("structures", "[]")))
		if parsed is Array:
			structures = parsed
	_location_structures_cache[location_id] = structures
	return structures


func _get_mention_context(category: String, structures: Array, game_day: int) -> String:
	match category:
		"ambient":
			var building := "the common area"
			if structures.size() > 0:
				building = str(structures[randi() % structures.size()])
			return "who was seen near " + building
		"death":
			return "who died on day " + str(game_day)
		"birth":
			return "who was born on day " + str(game_day)
		"departure":
			return "who left the community"
		"interpersonal":
			return "who was involved in a recent dispute"
		"resource":
			return "who helped manage supplies"
		_:
			return "who was recently mentioned"


func _maybe_generate_stat_warning(game_day: int, stats: Dictionary) -> void:
	# ~10% chance per day of a stat-based warning when something is low
	if randf() > 0.10:
		return

	var warnings: Array = []

	var food_val: float = float(stats.get("food", 0))
	var pop_val: float = float(stats.get("population", 1))
	var food_drain: float = GameData.get_config("FOOD_DRAIN_PER_PERSON")
	var food_weeks: float = 0.0
	if pop_val > 0 and food_drain > 0:
		food_weeks = food_val / (pop_val * food_drain * 7.0)
	if food_weeks < 2.0:
		warnings.append("The food stores are getting dangerously thin. People are starting to notice.")
	elif food_weeks < 4.0:
		warnings.append("Food is running lower than anyone would like to admit.")

	var health: float = float(stats.get("health", 50))
	if health < 25:
		warnings.append("Sickness is spreading. Without proper medicine, it will only get worse.")
	elif health < 40:
		warnings.append("Several people are complaining of aches and fevers.")

	var security: float = float(stats.get("security", 50))
	if security < 25:
		warnings.append("The perimeter is barely watched. Anything could walk in.")
	elif security < 40:
		warnings.append("Strange noises at night. The guards are stretched too thin.")

	var morale: float = float(stats.get("morale", 50))
	if morale < 25:
		warnings.append("The mood in camp is bleak. Arguments break out over nothing.")
	elif morale < 40:
		warnings.append("People are quieter than usual. The weight of it all is showing.")

	var cohesion: float = float(stats.get("cohesion", 50))
	if cohesion < 25:
		warnings.append("Factions are forming. People eat in separate groups now.")
	elif cohesion < 40:
		warnings.append("Small disagreements linger longer than they should.")

	var resources: float = float(stats.get("resources", 50))
	if resources < 25:
		warnings.append("Tools are breaking faster than they can be repaired. Supplies are critical.")
	elif resources < 40:
		warnings.append("The supply shed is looking emptier every day.")

	if warnings.size() > 0:
		var warning_text: String = warnings[randi() % warnings.size()]
		_write_log_entry(game_day, 2, "warning", warning_text)


# ---------- Helper Methods ----------

func _calculate_role_bonuses(roles: Array, population: Array, out_bonuses: Dictionary, _out_food: float) -> void:
	for role in roles:
		var role_id: String = role["id"]
		var required_skills: Array = JSON.parse_string(role["required_skills"])
		var stat_bonuses: Dictionary = JSON.parse_string(role["stat_bonuses"])
		var max_slots: int = role["max_slots"]

		# Find assigned and qualified members
		var qualified_count := 0
		for person in population:
			if qualified_count >= max_slots:
				break
			if person.get("assigned_role", "") != role_id:
				continue
			# Check skill qualification
			var person_skills: Array = JSON.parse_string(person["skills"])
			var is_qualified := required_skills.size() == 0
			if not is_qualified:
				for req_skill in required_skills:
					if req_skill in person_skills:
						is_qualified = true
						break
			if is_qualified:
				qualified_count += 1

		# Apply bonuses for each qualified slot
		for _i in range(qualified_count):
			for stat_id in stat_bonuses:
				if stat_id == "food_production":
					continue  # Handled separately
				if not out_bonuses.has(stat_id):
					out_bonuses[stat_id] = 0.0
				out_bonuses[stat_id] += float(stat_bonuses[stat_id])


func _calculate_role_food_production(roles: Array, population: Array) -> float:
	var total := 0.0
	for role in roles:
		var role_id: String = role["id"]
		var required_skills: Array = JSON.parse_string(role["required_skills"])
		var stat_bonuses: Dictionary = JSON.parse_string(role["stat_bonuses"])
		var max_slots: int = role["max_slots"]

		if not stat_bonuses.has("food_production"):
			continue

		var qualified_count := 0
		for person in population:
			if qualified_count >= max_slots:
				break
			if person.get("assigned_role", "") != role_id:
				continue
			var person_skills: Array = JSON.parse_string(person["skills"])
			var is_qualified := required_skills.size() == 0
			if not is_qualified:
				for req_skill in required_skills:
					if req_skill in person_skills:
						is_qualified = true
						break
			if is_qualified:
				qualified_count += 1

		total += qualified_count * float(stat_bonuses["food_production"])
	return total


func _handle_role_vacancy(person_id: String, person_name: String, game_day: int, population: Array) -> void:
	for person in population:
		if person["id"] == person_id:
			var role_id = person.get("assigned_role")
			if role_id != null and role_id != "":
				DatabaseManager.execute_save(
					"UPDATE population SET assigned_role = NULL WHERE id = ?;",
					[person_id]
				)
				# Look up role display name
				var role_rows := DatabaseManager.query_library(
					"SELECT display_name FROM roles WHERE id = ?;",
					[role_id]
				)
				var role_display: String = role_id
				if role_rows.size() > 0:
					role_display = role_rows[0]["display_name"]
				_write_log_entry(game_day, 1, "role_vacancy",
					"With %s gone, the %s role is now unfilled." % [person_name, role_display])
			break


func _write_log_entry(game_day: int, tier: int, category: String, display_text: String) -> void:
	DatabaseManager.execute_save(
		"INSERT INTO event_log (game_day, tier, category, display_text, is_highlighted, is_major) VALUES (?, ?, ?, ?, 0, 0);",
		[game_day, tier, category, display_text]
	)
	var entry := {
		"game_day": game_day,
		"tier": tier,
		"category": category,
		"display_text": display_text,
		"is_highlighted": 0,
		"is_major": 0
	}
	_pending_log_entries.append(entry)


func _get_living_count() -> int:
	var rows := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population WHERE alive = 1;")
	if rows.size() > 0:
		return int(rows[0]["cnt"])
	return 0


func _get_next_person_id() -> int:
	var rows := DatabaseManager.query_save("SELECT COUNT(*) AS cnt FROM population;")
	if rows.size() > 0:
		return int(rows[0]["cnt"]) + 1
	return 1


func _pick_available_name(gender: String) -> String:
	# Get names already in use by living members
	var used_rows := DatabaseManager.query_save("SELECT name FROM population WHERE alive = 1;")
	var used_names := {}
	for row in used_rows:
		used_names[row["name"]] = true

	# Get available names from pool matching gender
	var pool := DatabaseManager.query_library(
		"SELECT name FROM name_pool WHERE gender = ?;", [gender]
	)
	for row in pool:
		if not used_names.has(row["name"]):
			return row["name"]

	# Fallback: any unused name
	var all_pool := DatabaseManager.query_library("SELECT name FROM name_pool;")
	for row in all_pool:
		if not used_names.has(row["name"]):
			return row["name"]

	# Last resort
	return "Child"


func _get_season(day_of_year: int) -> String:
	if day_of_year >= 335 or day_of_year < 60:
		return "winter"
	elif day_of_year < 152:
		return "spring"
	elif day_of_year < 244:
		return "summer"
	elif day_of_year < 335:
		return "fall"
	return "winter"


func _trigger_game_over(reason: String) -> void:
	push_warning("GAME OVER: " + reason)
	current_speed = 0
	game_over_triggered.emit(reason)


# ---------- Phase 2a: Event Engine Support ----------

func _load_world_tags() -> Array[String]:
	var rows := DatabaseManager.query_save("SELECT tag FROM world_tags")
	var result: Array[String] = []
	for r in rows:
		result.append(str(r["tag"]))
	return result


func _load_flags() -> Array[String]:
	return FlagSystem.get_all_flags()


func _load_cooldowns() -> Array:
	return DatabaseManager.query_save("SELECT * FROM cooldowns WHERE expires_day > ?", [_current_game_day])


func _load_occurrence_counts() -> Dictionary:
	var rows := DatabaseManager.query_save("SELECT event_id, count FROM event_occurrence_counts")
	var result := {}
	for row in rows:
		result[row["event_id"]] = row["count"]
	return result


func _load_recent_log_days(game_day: int) -> Array:
	return DatabaseManager.query_save(
		"SELECT * FROM event_log WHERE game_day >= ?;",
		[game_day - 7]
	)
