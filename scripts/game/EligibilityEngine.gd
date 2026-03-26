class_name EligibilityEngine
extends RefCounted


static func is_eligible(
	event: Dictionary,
	world_tags: Array,
	state_tags: Array,
	stats: Dictionary,
	flags: Array,
	population: Array,
	game_day: int,
	cooldowns: Array,
	occurrence_counts: Dictionary,
	cast_actors: Dictionary = {}
) -> bool:
	# Parse eligibility JSON
	var elig_raw = event.get("eligibility")
	if elig_raw == null or str(elig_raw).strip_edges() == "":
		# No eligibility constraints — always eligible (still check cooldowns/occurrences)
		return _check_cooldowns_and_occurrences(event, game_day, cooldowns, occurrence_counts)

	var elig = JSON.parse_string(str(elig_raw))
	if elig == null or not (elig is Dictionary):
		return _check_cooldowns_and_occurrences(event, game_day, cooldowns, occurrence_counts)

	# --- required_world_tags ---
	if elig.has("required_world_tags") and elig["required_world_tags"] is Array:
		for tag in elig["required_world_tags"]:
			if str(tag) not in world_tags:
				return false

	# --- excluded_world_tags ---
	if elig.has("excluded_world_tags") and elig["excluded_world_tags"] is Array:
		for tag in elig["excluded_world_tags"]:
			if str(tag) in world_tags:
				return false

	# --- required_state_tags ---
	if elig.has("required_state_tags") and elig["required_state_tags"] is Array:
		for tag in elig["required_state_tags"]:
			if str(tag) not in state_tags:
				return false

	# --- excluded_state_tags ---
	if elig.has("excluded_state_tags") and elig["excluded_state_tags"] is Array:
		for tag in elig["excluded_state_tags"]:
			if str(tag) in state_tags:
				return false

	# --- stat_above ---
	if elig.has("stat_above") and elig["stat_above"] is Dictionary:
		for stat_id in elig["stat_above"]:
			var threshold: float = float(elig["stat_above"][stat_id])
			var current: float = float(stats.get(stat_id, 0.0))
			if current <= threshold:
				return false

	# --- stat_below ---
	if elig.has("stat_below") and elig["stat_below"] is Dictionary:
		for stat_id in elig["stat_below"]:
			var threshold: float = float(elig["stat_below"][stat_id])
			var current: float
			if stat_id == "food_weeks":
				var food_val: float = float(stats.get("food", 0))
				var pop_val: float = float(stats.get("population", 1))
				current = food_val / maxf(pop_val, 1.0) / 0.14 / 7.0
			else:
				current = float(stats.get(stat_id, 0.0))
			if current >= threshold:
				return false

	# --- population_min ---
	if elig.has("population_min") and elig["population_min"] != null:
		if population.size() < int(elig["population_min"]):
			return false

	# --- population_max ---
	if elig.has("population_max") and elig["population_max"] != null:
		if population.size() > int(elig["population_max"]):
			return false

	# --- min_game_day ---
	if elig.has("min_game_day") and elig["min_game_day"] != null:
		if game_day < int(elig["min_game_day"]):
			return false

	# --- max_game_day ---
	if elig.has("max_game_day") and elig["max_game_day"] != null:
		if game_day > int(elig["max_game_day"]):
			return false

	# --- required_flags ---
	if elig.has("required_flags") and elig["required_flags"] is Array:
		for flag_name in elig["required_flags"]:
			if str(flag_name) not in flags:
				return false

	# --- excluded_flags ---
	if elig.has("excluded_flags") and elig["excluded_flags"] is Array:
		for flag_name in elig["excluded_flags"]:
			if str(flag_name) in flags:
				return false

	# --- requires_actor ---
	if elig.has("requires_actor") and elig["requires_actor"] == true:
		if population.size() == 0:
			return false

	# --- required_actor_relationship ---
	if elig.has("required_actor_relationship") and elig["required_actor_relationship"] is Dictionary:
		var rel_reqs: Dictionary = elig["required_actor_relationship"]
		if not cast_actors.is_empty():
			for rel_key in rel_reqs:
				# Parse keys like "actor_1_close_to_actor_2" or "actor_1_grudge_against_actor_2"
				var actor_a_id: String = ""
				var actor_b_id: String = ""
				var rel_type: String = ""
				var rel_parts: PackedStringArray
				if "_close_to_" in rel_key:
					rel_parts = rel_key.split("_close_to_")
					var a_person = cast_actors.get(rel_parts[0], {})
					var b_person = cast_actors.get(rel_parts[1], {})
					if a_person is Dictionary and b_person is Dictionary:
						actor_a_id = str(a_person.get("id", ""))
						actor_b_id = str(b_person.get("id", ""))
					rel_type = "close_to"
				elif "_grudge_against_" in rel_key:
					rel_parts = rel_key.split("_grudge_against_")
					var a_person = cast_actors.get(rel_parts[0], {})
					var b_person = cast_actors.get(rel_parts[1], {})
					if a_person is Dictionary and b_person is Dictionary:
						actor_a_id = str(a_person.get("id", ""))
						actor_b_id = str(b_person.get("id", ""))
					rel_type = "grudge_against"
				if actor_a_id != "" and actor_b_id != "":
					var required: bool = bool(rel_reqs[rel_key])
					var has_rel: bool = false
					if rel_type == "close_to":
						has_rel = RelationalSystem.has_bond(actor_a_id, actor_b_id)
					elif rel_type == "grudge_against":
						has_rel = RelationalSystem.has_grudge(actor_a_id, actor_b_id)
					if has_rel != required:
						return false

	# --- community_score_above ---
	var community_score_above = elig.get("community_score_above", null)
	if community_score_above != null and community_score_above is Dictionary:
		for type_id in community_score_above:
			var threshold: float = float(community_score_above[type_id])
			var rows := DatabaseManager.query_save(
				"SELECT score FROM community_scores WHERE type_id = ?", [type_id]
			)
			if rows.is_empty() or float(rows[0].get("score", 0)) <= threshold:
				return false

	# --- Cooldown and occurrence checks ---
	return _check_cooldowns_and_occurrences(event, game_day, cooldowns, occurrence_counts)


static func _check_cooldowns_and_occurrences(
	event: Dictionary,
	game_day: int,
	cooldowns: Array,
	occurrence_counts: Dictionary
) -> bool:
	# --- Cooldown check ---
	var cooldown_days = event.get("cooldown_days", 0)
	if cooldown_days != null and int(cooldown_days) > 0:
		var event_id: String = str(event.get("id", ""))
		for cd in cooldowns:
			if str(cd.get("event_id", "")) == event_id and int(cd.get("expires_day", 0)) > game_day:
				return false

	# --- Exclusion group cooldown check ---
	var excl_group = event.get("exclusion_group")
	if excl_group != null and str(excl_group) != "":
		for cd in cooldowns:
			if str(cd.get("exclusion_group", "")) == str(excl_group) and int(cd.get("expires_day", 0)) > game_day:
				return false

	# --- Max occurrences check ---
	var max_occ = event.get("max_occurrences")
	if max_occ != null:
		var event_id: String = str(event.get("id", ""))
		var count: int = occurrence_counts.get(event_id, 0)
		if count >= int(max_occ):
			return false

	return true
