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

# Phase 2c: Tier 2 popup state
var _popup_active: bool = false

# Phase 3b: Chain stage queue — process one per tick
var _pending_chain_stages: Array = []


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

	# --- Step 5b: Process deferred outcomes (hints + resolutions) ---
	var deferred_entries := DeferredOutcomeSystem.tick(
		game_day, stats, gs_for_sim, _current_flags, _current_world_tags
	)
	for entry in deferred_entries:
		_pending_log_entries.append(entry)
		if entry.get("is_highlighted", 0) == 1 and _ui_stats_panel:
			_ui_stats_panel.refresh()

	# --- Step 5c: Process chain stages ---
	if not _popup_active:
		_tick_chains(stats, pop_rows, gs_for_sim)

	# --- Step 5d: Fire Tier 1 ambient events ---
	# Re-fetch living population after lifecycle changes
	var pop_after := DatabaseManager.query_save(
		"SELECT id, name, age, gender, alive, skills, personality, flags, assigned_role, joined_day, last_mentioned, mention_context FROM population WHERE alive = 1;"
	)
	_fire_ambient_events(stats, pop_after, gs_for_sim)

	# --- Step 5e: Attempt Tier 2 decision event ---
	if not _popup_active:
		var tier2_base_prob: float = 0.03
		if randf() < tier2_base_prob:
			_attempt_fire_tier2(stats, pop_after, gs_for_sim)

	# --- Step 5f: Generate stat warnings ---
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
		"chain":
			return "who was involved in an ongoing situation"
		_:
			return "who was recently mentioned"


# ---------- Tier 2 Decision Event Firing ----------

func _attempt_fire_tier2(stats: Dictionary, population: Array, game_state: Dictionary) -> void:
	var game_day: int = int(game_state.get("game_day", _current_game_day))

	# Filter to Tier 2 events (exclude chain stages — those are fired by _tick_chains)
	var all_events := GameData.get_all_events()
	var eligible_pool: Array = []
	for ev in all_events:
		if int(ev.get("tier", 0)) != 2:
			continue
		var ev_chain_id = ev.get("chain_id", null)
		if ev_chain_id != null and str(ev_chain_id) != "" and str(ev_chain_id) != "null":
			continue
		if EligibilityEngine.is_eligible(
			ev, _current_world_tags, _current_state_tags, stats,
			_current_flags, population, game_day,
			_current_cooldowns, _current_occurrence_counts
		):
			eligible_pool.append(ev)

	if eligible_pool.size() == 0:
		return

	# Try up to 4 events to find one that casts successfully
	var selected_event: Dictionary = {}
	var cast_actors: Dictionary = {}
	var attempts := 0
	while attempts < 4 and eligible_pool.size() > 0:
		var candidate: Dictionary = _weighted_select_event(eligible_pool)
		if candidate.is_empty():
			break

		var req_raw = candidate.get("actor_requirements")
		if req_raw == null or str(req_raw).strip_edges() == "" or str(req_raw).strip_edges() == "null":
			selected_event = candidate
			cast_actors = {}
			break
		else:
			var result := ActorCaster.cast(candidate, population, game_day)
			if not result.is_empty():
				selected_event = candidate
				cast_actors = result
				break
			else:
				eligible_pool.erase(candidate)
				attempts += 1

	if selected_event.is_empty():
		return

	# Fetch location structures
	var location_id: String = str(game_state.get("location_id", ""))
	var structures: Array = _get_location_structures(location_id)

	# Resolve description template
	var desc_template: String = str(selected_event.get("description_template", ""))
	var resolved_desc := TemplateResolver.resolve_event(
		desc_template, cast_actors, stats, game_state, structures, {}
	)

	# Parse choices
	var choices_raw = selected_event.get("choices")
	var parsed_choices: Array = []
	if choices_raw != null:
		var parsed = JSON.parse_string(str(choices_raw))
		if parsed is Array:
			parsed_choices = parsed

	if parsed_choices.size() == 0:
		return

	# Resolve choice text templates and collect relevant stat names
	var all_stat_ids: Dictionary = {}
	for i in range(parsed_choices.size()):
		var choice: Dictionary = parsed_choices[i]
		var text_tmpl: String = str(choice.get("text_template", "Choose"))
		choice["_resolved_text"] = TemplateResolver.resolve_event(
			text_tmpl, cast_actors, stats, game_state, structures, {}
		)
		# Collect relevant stat ids
		var roll_cfg = choice.get("roll", {})
		if roll_cfg is Dictionary:
			var rs = roll_cfg.get("relevant_stats", [])
			if rs is Array:
				for entry in rs:
					if entry is Dictionary:
						all_stat_ids[str(entry.get("stat", ""))] = true

	var relevant_names: Array = []
	for stat_id in all_stat_ids:
		var sdef: Dictionary = GameData.get_stat(stat_id)
		if not sdef.is_empty():
			relevant_names.append(str(sdef.get("display_name", stat_id)))

	# Pause the game
	set_speed(0)
	_popup_active = true

	# Instantiate popup
	var popup: PanelContainer = preload("res://scenes/ui/EventPopup.tscn").instantiate()
	get_tree().root.add_child(popup)
	popup.present(selected_event, resolved_desc, parsed_choices, relevant_names)
	popup.choice_made.connect(
		_on_tier2_choice_made.bind(
			selected_event, cast_actors, parsed_choices,
			game_state.duplicate(), stats.duplicate(), structures
		)
	)


func _on_tier2_choice_made(
	choice_index: int,
	event: Dictionary,
	cast_actors: Dictionary,
	parsed_choices: Array,
	game_state_snapshot: Dictionary,
	stats_snapshot: Dictionary,
	structures: Array
) -> void:
	if choice_index < 0 or choice_index >= parsed_choices.size():
		_popup_active = false
		return

	var choice: Dictionary = parsed_choices[choice_index]
	var game_day: int = int(game_state_snapshot.get("game_day", _current_game_day))

	# Re-load current stats from DB (they may have drifted if a tick somehow ran)
	var stat_rows := DatabaseManager.query_save("SELECT stat_id, value FROM current_stats;")
	var stats: Dictionary = {}
	for row in stat_rows:
		stats[row["stat_id"]] = float(row["value"])

	# Ensure stat defs are loaded
	if _stat_defs.is_empty():
		var all_stats := GameData.get_all_stats()
		for s in all_stats:
			_stat_defs[s["id"]] = s

	var stability_factor: float = 0.5 + (float(stats.get("stability", 50.0)) / 100.0) * 0.5
	var all_deltas: Dictionary = {}

	# --- 1. Apply immediate effects ---
	var imm_effects = choice.get("immediate_effects", {})
	if imm_effects is Dictionary:
		for stat_id in imm_effects:
			var delta: float = float(imm_effects[stat_id])
			if delta > 0:
				delta *= stability_factor
			var new_val: float = float(stats.get(stat_id, 0.0)) + delta
			if _stat_defs.has(stat_id):
				var sdef: Dictionary = _stat_defs[stat_id]
				new_val = clampf(new_val, float(sdef["min_value"]), float(sdef["max_value"]))
			stats[stat_id] = new_val
			DatabaseManager.execute_save(
				"UPDATE current_stats SET value = ? WHERE stat_id = ?;",
				[new_val, stat_id]
			)
			all_deltas[stat_id] = all_deltas.get(stat_id, 0.0) + float(imm_effects[stat_id])

	# --- 2. Apply community scores ---
	var comm_scores = choice.get("community_scores", {})
	if comm_scores is Dictionary:
		for type_id in comm_scores:
			var pts: float = float(comm_scores[type_id])
			DatabaseManager.execute_save(
				"UPDATE community_scores SET score = score + ? WHERE type_id = ?;",
				[pts, type_id]
			)

	# --- 3. Execute the roll ---
	var roll_result := RollEngine.roll(
		choice, stats, cast_actors, game_state_snapshot,
		_current_flags, _current_world_tags
	)
	var outcome_tier: String = roll_result["outcome_tier"]
	var outcome_score: float = roll_result["outcome_score"]

	# --- 4. Get outcome ---
	var outcomes = choice.get("outcomes", {})
	if not (outcomes is Dictionary):
		outcomes = {}
	var outcome: Dictionary = outcomes.get(outcome_tier, {})
	if not (outcome is Dictionary):
		outcome = {}

	# --- 5. Apply outcome effects ---
	var outcome_effects = outcome.get("effects", {})
	if outcome_effects is Dictionary:
		for stat_id in outcome_effects:
			var delta: float = float(outcome_effects[stat_id])
			if delta > 0:
				delta *= stability_factor
			var new_val: float = float(stats.get(stat_id, 0.0)) + delta
			if _stat_defs.has(stat_id):
				var sdef: Dictionary = _stat_defs[stat_id]
				new_val = clampf(new_val, float(sdef["min_value"]), float(sdef["max_value"]))
			stats[stat_id] = new_val
			DatabaseManager.execute_save(
				"UPDATE current_stats SET value = ? WHERE stat_id = ?;",
				[new_val, stat_id]
			)
			all_deltas[stat_id] = all_deltas.get(stat_id, 0.0) + float(outcome_effects[stat_id])

	# --- 6. Set/clear flags ---
	var flags_set = outcome.get("flags_set", [])
	if flags_set is Array:
		for flag_name in flags_set:
			var fn: String = str(flag_name)
			if fn.begins_with("actor_1:") and cast_actors.has("actor_1"):
				FlagSystem.set_actor_flag(str(cast_actors["actor_1"].get("id", "")), fn.substr(8))
			elif fn.begins_with("actor_2:") and cast_actors.has("actor_2"):
				FlagSystem.set_actor_flag(str(cast_actors["actor_2"].get("id", "")), fn.substr(8))
			else:
				FlagSystem.set_flag(fn, game_day)

	var flags_cleared = outcome.get("flags_cleared", [])
	if flags_cleared is Array:
		for flag_name in flags_cleared:
			var fn: String = str(flag_name)
			if fn.begins_with("actor_1:") and cast_actors.has("actor_1"):
				FlagSystem.clear_actor_flag(str(cast_actors["actor_1"].get("id", "")), fn.substr(8))
			elif fn.begins_with("actor_2:") and cast_actors.has("actor_2"):
				FlagSystem.clear_actor_flag(str(cast_actors["actor_2"].get("id", "")), fn.substr(8))
			else:
				FlagSystem.clear_flag(fn)

	# --- 7. Resolve outcome text ---
	var outcome_text: String = str(outcome.get("text", "The outcome was unclear."))
	var outcome_labels := {
		"catastrophic": "Everything went wrong.",
		"bad": "It didn't go well.",
		"mixed": "Results were mixed.",
		"good": "It went reasonably well.",
		"exceptional": "Better than expected."
	}
	var chain_mem := {"_outcome_label": outcome_labels.get(outcome_tier, "")}
	var resolved_outcome := TemplateResolver.resolve_event(
		outcome_text, cast_actors, stats, game_state_snapshot, structures, chain_mem
	)

	var choice_text: String = str(choice.get("_resolved_text", choice.get("text_template", "")))
	var display_text: String = "You chose: " + choice_text + "\n\n" + resolved_outcome

	# Stat change summary
	var changes_parts: Array = []
	for stat_id in all_deltas:
		var d: float = all_deltas[stat_id]
		if absf(d) < 0.01:
			continue
		var sdef: Dictionary = _stat_defs.get(stat_id, {})
		var stat_name: String = str(sdef.get("display_name", stat_id))
		if d > 0:
			changes_parts.append(stat_name + " +" + str(int(d)))
		else:
			changes_parts.append(stat_name + " " + str(int(d)))
	if changes_parts.size() > 0:
		display_text += "\n[" + ", ".join(changes_parts) + "]"

	# --- 8. Write to event_log ---
	var event_id: String = str(event.get("id", ""))
	var category: String = str(event.get("category", "decision"))
	var choice_id: String = str(choice.get("id", ""))
	DatabaseManager.execute_save(
		"INSERT INTO event_log (game_day, tier, event_id, category, display_text, choice_made, outcome_tier, outcome_score, stat_changes, is_highlighted, is_major) VALUES (?, 2, ?, ?, ?, ?, ?, ?, ?, 1, 0);",
		[game_day, event_id, category, display_text, choice_id, outcome_tier, outcome_score, JSON.stringify(all_deltas)]
	)

	# Get the ROWID of the just-inserted log entry
	var rowid_rows := DatabaseManager.query_save("SELECT last_insert_rowid() AS id;")
	var written_log_id: int = 0
	if rowid_rows.size() > 0:
		written_log_id = int(rowid_rows[0].get("id", 0))

	var entry := {
		"game_day": game_day,
		"tier": 2,
		"category": category,
		"display_text": display_text,
		"is_highlighted": 1,
		"is_major": 0
	}

	# --- 8b. Schedule deferred outcome if present ---
	if choice.has("deferred") and choice.get("deferred") != null:
		var deferred_block = choice.get("deferred")
		if deferred_block is Dictionary:
			var actor_id_list: Array = []
			for actor_key in cast_actors:
				var person: Dictionary = cast_actors[actor_key]
				actor_id_list.append(str(person.get("id", "")))
			DeferredOutcomeSystem.schedule(
				event_id, choice_id, written_log_id,
				actor_id_list, deferred_block, game_day
			)

	# --- 8c. Chain triggers ---
	var chain_to = outcome.get("chain_to", null)
	if chain_to != null and str(chain_to) != "" and str(chain_to) != "null":
		var chain_initial_mem = outcome.get("chain_memory_write", {})
		if not (chain_initial_mem is Dictionary):
			chain_initial_mem = {}
		# Resolve actor names in memory values
		for mem_key in chain_initial_mem:
			var mem_val: String = str(chain_initial_mem[mem_key])
			for actor_key in cast_actors:
				mem_val = mem_val.replace("{" + actor_key + "}", str(cast_actors[actor_key].get("name", "")))
			chain_initial_mem[mem_key] = mem_val
		ChainSystem.start_chain(str(chain_to), str(chain_to) + "_1", game_day, chain_initial_mem)

	var next_stage_id = outcome.get("next_stage_id", null)
	var event_chain_id = event.get("chain_id", null)
	if next_stage_id != null and str(next_stage_id) != "" and str(next_stage_id) != "null":
		var memory_writes = outcome.get("chain_memory_write", {})
		if not (memory_writes is Dictionary):
			memory_writes = {}
		for mem_key in memory_writes:
			var mem_val: String = str(memory_writes[mem_key])
			for actor_key in cast_actors:
				mem_val = mem_val.replace("{" + actor_key + "}", str(cast_actors[actor_key].get("name", "")))
			memory_writes[mem_key] = mem_val
		if event_chain_id != null and str(event_chain_id) != "" and str(event_chain_id) != "null":
			ChainSystem.advance_chain(str(event_chain_id), str(next_stage_id), memory_writes, game_day)
	elif event_chain_id != null and str(event_chain_id) != "" and str(event_chain_id) != "null":
		ChainSystem.end_chain(str(event_chain_id))

	# --- 9. Record cooldown ---
	var cd_days = event.get("cooldown_days", 0)
	if cd_days != null and int(cd_days) > 0:
		DatabaseManager.execute_save(
			"INSERT INTO cooldowns (event_id, exclusion_group, expires_day) VALUES (?, NULL, ?);",
			[event_id, game_day + int(cd_days)]
		)
	var excl = event.get("exclusion_group")
	if excl != null and str(excl) != "":
		DatabaseManager.execute_save(
			"INSERT INTO cooldowns (event_id, exclusion_group, expires_day) VALUES (NULL, ?, ?);",
			[str(excl), game_day + int(event.get("cooldown_days", 7))]
		)

	# --- 10. Increment occurrence count ---
	var prev_count: int = _current_occurrence_counts.get(event_id, 0)
	DatabaseManager.execute_save(
		"INSERT OR REPLACE INTO event_occurrence_counts (event_id, count) VALUES (?, ?);",
		[event_id, prev_count + 1]
	)

	# --- 11. Update actor last_mentioned ---
	var loc_structures: Array = structures
	for actor_key in cast_actors:
		var person: Dictionary = cast_actors[actor_key]
		var pid: String = str(person.get("id", ""))
		var mention_ctx := _get_mention_context(category, loc_structures, game_day)
		DatabaseManager.execute_save(
			"UPDATE population SET last_mentioned = ?, mention_context = ? WHERE id = ?;",
			[game_day, mention_ctx, pid]
		)

	# --- 12. Notify UI ---
	log_entry_added.emit(entry)
	if _ui_event_log:
		_ui_event_log.append_entry(entry)
	if _ui_stats_panel:
		_ui_stats_panel.refresh()

	# --- 13. Done — leave paused ---
	_popup_active = false


# ---------- Chain System Integration ----------

func _tick_chains(stats: Dictionary, population: Array, game_state: Dictionary) -> void:
	var game_day: int = int(game_state.get("game_day", _current_game_day))

	# Refill queue if empty
	if _pending_chain_stages.size() == 0:
		_pending_chain_stages = ChainSystem.get_due_chains(game_day)

	# Process at most one chain stage per tick
	if _pending_chain_stages.size() > 0 and not _popup_active:
		var chain_record: Dictionary = _pending_chain_stages.pop_front()
		_fire_chain_stage(chain_record, stats, population, game_state)


func _fire_chain_stage(chain_record: Dictionary, stats: Dictionary, population: Array, game_state: Dictionary) -> void:
	var game_day: int = int(game_state.get("game_day", _current_game_day))
	var stage_id: String = str(chain_record.get("current_stage_id", ""))
	var chain_id: String = str(chain_record.get("chain_id", ""))

	# Fetch stage event from library
	var stage_rows := DatabaseManager.query_library(
		"SELECT * FROM events WHERE id = ?;", [stage_id]
	)
	if stage_rows.size() == 0:
		ChainSystem.end_chain(chain_id)
		return

	var stage_event: Dictionary = stage_rows[0]

	# Check eligibility
	if not EligibilityEngine.is_eligible(
		stage_event, _current_world_tags, _current_state_tags, stats,
		_current_flags, population, game_day,
		_current_cooldowns, _current_occurrence_counts
	):
		# Defer — try again in 3 days
		DatabaseManager.execute_save(
			"UPDATE active_chains SET next_fire_day = ? WHERE chain_id = ?;",
			[game_day + 3, chain_id]
		)
		return

	# Cast actors
	var cast_actors: Dictionary = {}
	var req_raw = stage_event.get("actor_requirements")
	if req_raw != null and str(req_raw).strip_edges() != "" and str(req_raw).strip_edges() != "null":
		cast_actors = ActorCaster.cast(stage_event, population, game_day)
		if cast_actors.is_empty():
			# Can't cast — defer
			DatabaseManager.execute_save(
				"UPDATE active_chains SET next_fire_day = ? WHERE chain_id = ?;",
				[game_day + 3, chain_id]
			)
			return

	# Get chain memory
	var chain_memory := ChainSystem.get_memory(chain_id)

	# Fetch location structures
	var location_id: String = str(game_state.get("location_id", ""))
	var structures: Array = _get_location_structures(location_id)

	# Resolve description template
	var desc_template: String = str(stage_event.get("description_template", ""))
	var resolved_desc := TemplateResolver.resolve_event(
		desc_template, cast_actors, stats, game_state, structures, chain_memory
	)

	# Parse choices
	var choices_raw = stage_event.get("choices")
	var parsed_choices: Array = []
	if choices_raw != null and str(choices_raw).strip_edges() != "" and str(choices_raw).strip_edges() != "null":
		var parsed = JSON.parse_string(str(choices_raw))
		if parsed is Array:
			parsed_choices = parsed

	# No-choice stage: auto-resolve immediately
	if parsed_choices.size() == 0:
		DatabaseManager.execute_save(
			"INSERT INTO event_log (game_day, tier, event_id, category, display_text, is_highlighted, is_major) VALUES (?, 1, ?, 'chain', ?, 0, 0);",
			[game_day, str(stage_event.get("id", "")), resolved_desc]
		)
		var entry := {
			"game_day": game_day,
			"tier": 1,
			"category": "chain",
			"display_text": resolved_desc,
			"is_highlighted": 0,
			"is_major": 0
		}
		_pending_log_entries.append(entry)

		# Check chain_auto_next for the next stage
		var auto_next = stage_event.get("chain_auto_next", null)
		if auto_next != null and str(auto_next) != "" and str(auto_next) != "null":
			ChainSystem.advance_chain(chain_id, str(auto_next), {}, game_day)
		else:
			ChainSystem.end_chain(chain_id)
		return

	# Resolve choice text templates and collect relevant stat names
	var all_stat_ids: Dictionary = {}
	for i in range(parsed_choices.size()):
		var choice: Dictionary = parsed_choices[i]
		var text_tmpl: String = str(choice.get("text_template", "Choose"))
		choice["_resolved_text"] = TemplateResolver.resolve_event(
			text_tmpl, cast_actors, stats, game_state, structures, chain_memory
		)
		var roll_cfg = choice.get("roll", {})
		if roll_cfg is Dictionary:
			var rs = roll_cfg.get("relevant_stats", [])
			if rs is Array:
				for rs_entry in rs:
					if rs_entry is Dictionary:
						all_stat_ids[str(rs_entry.get("stat", ""))] = true

	var relevant_names: Array = []
	for stat_id in all_stat_ids:
		var sdef: Dictionary = GameData.get_stat(stat_id)
		if not sdef.is_empty():
			relevant_names.append(str(sdef.get("display_name", stat_id)))

	# Pause the game and show popup
	set_speed(0)
	_popup_active = true

	var popup: PanelContainer = preload("res://scenes/ui/EventPopup.tscn").instantiate()
	get_tree().root.add_child(popup)
	popup.present(stage_event, resolved_desc, parsed_choices, relevant_names)
	popup.choice_made.connect(
		_on_chain_stage_choice_made.bind(
			stage_event, cast_actors, parsed_choices,
			chain_record, game_state.duplicate(), stats.duplicate(), structures
		)
	)


func _on_chain_stage_choice_made(
	choice_index: int,
	stage_event: Dictionary,
	cast_actors: Dictionary,
	parsed_choices: Array,
	chain_record: Dictionary,
	game_state_snapshot: Dictionary,
	stats_snapshot: Dictionary,
	structures: Array
) -> void:
	if choice_index < 0 or choice_index >= parsed_choices.size():
		_popup_active = false
		return

	var choice: Dictionary = parsed_choices[choice_index]
	var game_day: int = int(game_state_snapshot.get("game_day", _current_game_day))
	var chain_id: String = str(chain_record.get("chain_id", ""))

	# Re-load current stats from DB
	var stat_rows := DatabaseManager.query_save("SELECT stat_id, value FROM current_stats;")
	var stats: Dictionary = {}
	for row in stat_rows:
		stats[row["stat_id"]] = float(row["value"])

	if _stat_defs.is_empty():
		var all_stats := GameData.get_all_stats()
		for s in all_stats:
			_stat_defs[s["id"]] = s

	var stability_factor: float = 0.5 + (float(stats.get("stability", 50.0)) / 100.0) * 0.5
	var all_deltas: Dictionary = {}

	# --- 1. Apply immediate effects ---
	var imm_effects = choice.get("immediate_effects", {})
	if imm_effects is Dictionary:
		for stat_id in imm_effects:
			var delta: float = float(imm_effects[stat_id])
			if delta > 0:
				delta *= stability_factor
			var new_val: float = float(stats.get(stat_id, 0.0)) + delta
			if _stat_defs.has(stat_id):
				var sdef: Dictionary = _stat_defs[stat_id]
				new_val = clampf(new_val, float(sdef["min_value"]), float(sdef["max_value"]))
			stats[stat_id] = new_val
			DatabaseManager.execute_save(
				"UPDATE current_stats SET value = ? WHERE stat_id = ?;",
				[new_val, stat_id]
			)
			all_deltas[stat_id] = all_deltas.get(stat_id, 0.0) + float(imm_effects[stat_id])

	# --- 2. Apply community scores ---
	var comm_scores = choice.get("community_scores", {})
	if comm_scores is Dictionary:
		for type_id in comm_scores:
			var pts: float = float(comm_scores[type_id])
			DatabaseManager.execute_save(
				"UPDATE community_scores SET score = score + ? WHERE type_id = ?;",
				[pts, type_id]
			)

	# --- 3. Execute the roll ---
	var chain_memory := ChainSystem.get_memory(chain_id)
	var roll_result := RollEngine.roll(
		choice, stats, cast_actors, game_state_snapshot,
		_current_flags, _current_world_tags
	)
	var outcome_tier: String = roll_result["outcome_tier"]
	var outcome_score: float = roll_result["outcome_score"]

	# --- 4. Get outcome ---
	var outcomes = choice.get("outcomes", {})
	if not (outcomes is Dictionary):
		outcomes = {}
	var outcome: Dictionary = outcomes.get(outcome_tier, {})
	if not (outcome is Dictionary):
		outcome = {}

	# --- 5. Apply outcome effects ---
	var outcome_effects = outcome.get("effects", {})
	if outcome_effects is Dictionary:
		for stat_id in outcome_effects:
			var delta: float = float(outcome_effects[stat_id])
			if delta > 0:
				delta *= stability_factor
			var new_val: float = float(stats.get(stat_id, 0.0)) + delta
			if _stat_defs.has(stat_id):
				var sdef: Dictionary = _stat_defs[stat_id]
				new_val = clampf(new_val, float(sdef["min_value"]), float(sdef["max_value"]))
			stats[stat_id] = new_val
			DatabaseManager.execute_save(
				"UPDATE current_stats SET value = ? WHERE stat_id = ?;",
				[new_val, stat_id]
			)
			all_deltas[stat_id] = all_deltas.get(stat_id, 0.0) + float(outcome_effects[stat_id])

	# --- 6. Set/clear flags ---
	var flags_set = outcome.get("flags_set", [])
	if flags_set is Array:
		for flag_name in flags_set:
			var fn: String = str(flag_name)
			if fn.begins_with("actor_1:") and cast_actors.has("actor_1"):
				FlagSystem.set_actor_flag(str(cast_actors["actor_1"].get("id", "")), fn.substr(8))
			elif fn.begins_with("actor_2:") and cast_actors.has("actor_2"):
				FlagSystem.set_actor_flag(str(cast_actors["actor_2"].get("id", "")), fn.substr(8))
			else:
				FlagSystem.set_flag(fn, game_day)

	var flags_cleared = outcome.get("flags_cleared", [])
	if flags_cleared is Array:
		for flag_name in flags_cleared:
			var fn: String = str(flag_name)
			if fn.begins_with("actor_1:") and cast_actors.has("actor_1"):
				FlagSystem.clear_actor_flag(str(cast_actors["actor_1"].get("id", "")), fn.substr(8))
			elif fn.begins_with("actor_2:") and cast_actors.has("actor_2"):
				FlagSystem.clear_actor_flag(str(cast_actors["actor_2"].get("id", "")), fn.substr(8))
			else:
				FlagSystem.clear_flag(fn)

	# --- 7. Resolve outcome text ---
	var outcome_text: String = str(outcome.get("text", "The outcome was unclear."))
	var outcome_labels := {
		"catastrophic": "Everything went wrong.",
		"bad": "It didn't go well.",
		"mixed": "Results were mixed.",
		"good": "It went reasonably well.",
		"exceptional": "Better than expected."
	}
	chain_memory["_outcome_label"] = outcome_labels.get(outcome_tier, "")
	var resolved_outcome := TemplateResolver.resolve_event(
		outcome_text, cast_actors, stats, game_state_snapshot, structures, chain_memory
	)

	var choice_text: String = str(choice.get("_resolved_text", choice.get("text_template", "")))
	var display_text: String = "You chose: " + choice_text + "\n\n" + resolved_outcome

	# Stat change summary
	var changes_parts: Array = []
	for stat_id in all_deltas:
		var d: float = all_deltas[stat_id]
		if absf(d) < 0.01:
			continue
		var sdef: Dictionary = _stat_defs.get(stat_id, {})
		var stat_name: String = str(sdef.get("display_name", stat_id))
		if d > 0:
			changes_parts.append(stat_name + " +" + str(int(d)))
		else:
			changes_parts.append(stat_name + " " + str(int(d)))
	if changes_parts.size() > 0:
		display_text += "\n[" + ", ".join(changes_parts) + "]"

	# --- 8. Write to event_log ---
	var event_id: String = str(stage_event.get("id", ""))
	var choice_id: String = str(choice.get("id", ""))
	DatabaseManager.execute_save(
		"INSERT INTO event_log (game_day, tier, event_id, category, display_text, choice_made, outcome_tier, outcome_score, stat_changes, is_highlighted, is_major) VALUES (?, 2, ?, 'chain', ?, ?, ?, ?, ?, 1, 0);",
		[game_day, event_id, display_text, choice_id, outcome_tier, outcome_score, JSON.stringify(all_deltas)]
	)

	var entry := {
		"game_day": game_day,
		"tier": 2,
		"category": "chain",
		"display_text": display_text,
		"is_highlighted": 1,
		"is_major": 0
	}

	# --- 9. Advance or end chain ---
	var next_stage_id = outcome.get("next_stage_id", null)
	var memory_writes = outcome.get("chain_memory_write", {})
	if not (memory_writes is Dictionary):
		memory_writes = {}
	# Resolve actor names in memory values
	for mem_key in memory_writes:
		var mem_val: String = str(memory_writes[mem_key])
		for actor_key in cast_actors:
			mem_val = mem_val.replace("{" + actor_key + "}", str(cast_actors[actor_key].get("name", "")))
		memory_writes[mem_key] = mem_val

	if next_stage_id != null and str(next_stage_id) != "" and str(next_stage_id) != "null":
		ChainSystem.advance_chain(chain_id, str(next_stage_id), memory_writes, game_day)
	else:
		# Merge any final memory writes before ending
		if memory_writes.size() > 0:
			var cur_mem := ChainSystem.get_memory(chain_id)
			for mk in memory_writes:
				cur_mem[mk] = memory_writes[mk]
		ChainSystem.end_chain(chain_id)

	# --- 10. Update actor last_mentioned ---
	for actor_key in cast_actors:
		var person: Dictionary = cast_actors[actor_key]
		var pid: String = str(person.get("id", ""))
		var mention_ctx := _get_mention_context("chain", structures, game_day)
		DatabaseManager.execute_save(
			"UPDATE population SET last_mentioned = ?, mention_context = ? WHERE id = ?;",
			[game_day, mention_ctx, pid]
		)

	# --- 11. Notify UI ---
	log_entry_added.emit(entry)
	if _ui_event_log:
		_ui_event_log.append_entry(entry)
	if _ui_stats_panel:
		_ui_stats_panel.refresh()

	_popup_active = false


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
