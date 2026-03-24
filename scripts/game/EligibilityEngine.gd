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
	occurrence_counts: Dictionary
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
