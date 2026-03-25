class_name DeferredOutcomeSystem
extends RefCounted


static func schedule(
	event_id: String,
	choice_id: String,
	source_log_id: int,
	actor_ids: Array,
	deferred_block: Dictionary,
	game_day: int
) -> void:
	var earliest: int = game_day + int(deferred_block.get("delay_min_days", 7))
	var latest: int = game_day + int(deferred_block.get("delay_max_days", 30))

	var raw_hints = deferred_block.get("log_hints", [])
	var hints: Array = []
	if raw_hints is Array:
		for hint in raw_hints:
			if hint is Dictionary:
				hints.append({
					"fire_day": game_day + int(hint.get("day_offset", 0)),
					"text": str(hint.get("text", "")),
					"fired": false
				})

	var check_config: Dictionary = deferred_block.get("check", {})
	var outcomes: Dictionary = deferred_block.get("outcomes", {})

	DatabaseManager.execute_save(
		"INSERT INTO pending_deferred (source_event_id, source_choice_id, source_log_id, actor_ids, earliest_fire_day, latest_fire_day, check_config, outcomes, log_hints, fired) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0);",
		[event_id, choice_id, source_log_id, JSON.stringify(actor_ids), earliest, latest, JSON.stringify(check_config), JSON.stringify(outcomes), JSON.stringify(hints)]
	)


static func tick(
	game_day: int,
	stats: Dictionary,
	game_state: Dictionary,
	flags: Array,
	world_tags: Array
) -> Array:
	var log_entries: Array = []

	var records := DatabaseManager.query_save("SELECT * FROM pending_deferred WHERE fired = 0;")

	for record in records:
		# --- Step A: Fire pending hints ---
		var hints_json = record.get("log_hints", "[]")
		var hints = JSON.parse_string(str(hints_json))
		if not (hints is Array):
			hints = []

		var hints_changed: bool = false
		for i in range(hints.size()):
			var hint: Dictionary = hints[i]
			if hint.get("fired", false):
				continue
			if int(hint.get("fire_day", 999999)) <= game_day:
				# Re-fetch actors
				var actors := _fetch_actors(record)
				var resolved_text := TemplateResolver.resolve_event(
					str(hint.get("text", "")), actors, stats, game_state, [], {}
				)
				DatabaseManager.execute_save(
					"INSERT INTO event_log (game_day, tier, event_id, category, display_text, is_highlighted, is_major) VALUES (?, 1, ?, 'ambient', ?, 0, 0);",
					[game_day, str(record.get("source_event_id", "")), resolved_text]
				)
				var entry := {
					"game_day": game_day,
					"tier": 1,
					"category": "ambient",
					"display_text": resolved_text,
					"is_highlighted": 0,
					"is_major": 0
				}
				log_entries.append(entry)
				hints[i]["fired"] = true
				hints_changed = true

		if hints_changed:
			DatabaseManager.execute_save(
				"UPDATE pending_deferred SET log_hints = ? WHERE id = ?;",
				[JSON.stringify(hints), record["id"]]
			)

	# --- Step B: Resolve matured outcomes ---
	for record in records:
		var earliest: int = int(record.get("earliest_fire_day", 999999))
		if game_day < earliest:
			continue

		var latest: int = int(record.get("latest_fire_day", earliest))
		var window: int = latest - earliest
		var prob: float = 1.0 / maxf(float(window), 1.0)
		if game_day >= latest:
			prob = 1.0

		if randf() < prob:
			var entry := _resolve(record, game_day, stats, game_state, flags, world_tags)
			if not entry.is_empty():
				log_entries.append(entry)

	return log_entries


static func _resolve(
	record: Dictionary,
	game_day: int,
	stats: Dictionary,
	game_state: Dictionary,
	flags: Array,
	world_tags: Array
) -> Dictionary:
	var actors := _fetch_actors(record)

	var check_config = JSON.parse_string(str(record.get("check_config", "{}")))
	if not (check_config is Dictionary):
		check_config = {}

	var outcomes_json = JSON.parse_string(str(record.get("outcomes", "{}")))
	if not (outcomes_json is Dictionary):
		outcomes_json = {}

	# Build roll input for RollEngine
	var roll_input := {
		"roll": check_config,
		"outcomes": outcomes_json
	}

	var community_modifiers := CommunityIdentity.get_active_roll_modifiers()
	var roll_result := RollEngine.roll(roll_input, stats, actors, game_state, flags, world_tags, community_modifiers)
	var outcome_tier: String = roll_result["outcome_tier"]

	var outcome: Dictionary = outcomes_json.get(outcome_tier, {})
	if not (outcome is Dictionary):
		outcome = {}

	# Apply effects
	var effects = outcome.get("effects", {})
	if effects is Dictionary:
		var stat_defs := _load_stat_defs()
		var stability_factor: float = 0.5 + (float(stats.get("stability", 50.0)) / 100.0) * 0.5
		for stat_id in effects:
			var delta: float = float(effects[stat_id])
			if delta > 0:
				delta *= stability_factor
			var new_val: float = float(stats.get(stat_id, 0.0)) + delta
			if stat_defs.has(stat_id):
				var sdef: Dictionary = stat_defs[stat_id]
				new_val = clampf(new_val, float(sdef.get("min_value", 0)), float(sdef.get("max_value", 100)))
			stats[stat_id] = new_val
			DatabaseManager.execute_save(
				"UPDATE current_stats SET value = ? WHERE stat_id = ?;",
				[new_val, stat_id]
			)

	# Apply flags
	var flags_set = outcome.get("flags_set", [])
	if flags_set is Array:
		for flag_name in flags_set:
			FlagSystem.set_flag(str(flag_name), game_day)

	var flags_cleared = outcome.get("flags_cleared", [])
	if flags_cleared is Array:
		for flag_name in flags_cleared:
			FlagSystem.clear_flag(str(flag_name))

	# Resolve outcome text
	var outcome_text: String = str(outcome.get("text", "The deferred outcome was unclear."))
	var resolved_text := TemplateResolver.resolve_event(
		outcome_text, actors, stats, game_state, [], {}
	)
	var display_text: String = "[Deferred] " + resolved_text

	# Write to event_log
	DatabaseManager.execute_save(
		"INSERT INTO event_log (game_day, tier, event_id, category, display_text, is_highlighted, is_major) VALUES (?, 2, ?, 'deferred_resolution', ?, 1, 0);",
		[game_day, str(record.get("source_event_id", "")), display_text]
	)

	# Mark as fired
	DatabaseManager.execute_save(
		"UPDATE pending_deferred SET fired = 1, fired_day = ?, fired_outcome = ? WHERE id = ?;",
		[game_day, outcome_tier, record["id"]]
	)

	return {
		"game_day": game_day,
		"tier": 2,
		"category": "deferred_resolution",
		"display_text": display_text,
		"is_highlighted": 1,
		"is_major": 0
	}


static func _fetch_actors(record: Dictionary) -> Dictionary:
	var actor_ids_json = JSON.parse_string(str(record.get("actor_ids", "[]")))
	if not (actor_ids_json is Array):
		return {}

	var actors: Dictionary = {}
	for i in range(actor_ids_json.size()):
		var pid: String = str(actor_ids_json[i])
		var rows := DatabaseManager.query_save(
			"SELECT id, name, age, gender, alive, skills, personality, flags, assigned_role, joined_day, last_mentioned, mention_context FROM population WHERE id = ?;",
			[pid]
		)
		if rows.size() > 0:
			var key := "actor_" + str(i + 1)
			actors[key] = rows[0]

	return actors


static func _load_stat_defs() -> Dictionary:
	var all_stats := GameData.get_all_stats()
	var defs: Dictionary = {}
	for s in all_stats:
		defs[s["id"]] = s
	return defs
