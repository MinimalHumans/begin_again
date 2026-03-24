class_name StateTagSystem
extends RefCounted


static func compute(
	stats: Dictionary,
	population: Array,
	game_state: Dictionary,
	known_skill_ids: Array[String],
	recent_log_days: Array = []
) -> Array[String]:
	var tags: Array[String] = []

	# --- Stat threshold tags ---
	var bar_stats := ["morale", "health", "security", "knowledge", "cohesion", "resources", "stability", "reputation"]
	for stat_id in bar_stats:
		if not stats.has(stat_id):
			continue
		var val: float = float(stats[stat_id])
		if val <= 10.0:
			tags.append(stat_id + "_critical")
		elif val <= 25.0:
			tags.append(stat_id + "_low")
		elif val <= 50.0:
			tags.append(stat_id + "_moderate")
		elif val <= 75.0:
			tags.append(stat_id + "_good")
		else:
			tags.append(stat_id + "_high")

	# --- Food threshold tags ---
	var food_val: float = float(stats.get("food", 0))
	var pop_val: float = float(stats.get("population", 1))
	var food_weeks: float = food_val / maxf(pop_val, 1.0) / 0.14 / 7.0
	if food_weeks < 1.0:
		tags.append("food_critical")
	elif food_weeks < 3.0:
		tags.append("food_low")
	elif food_weeks < 6.0:
		tags.append("food_moderate")
	else:
		tags.append("food_adequate")

	# --- Population band tags ---
	var living_count: int = population.size()
	if living_count == 1:
		tags.append("solo")
	elif living_count <= 5:
		tags.append("tiny_group")
	elif living_count <= 15:
		tags.append("small_group")
	elif living_count <= 30:
		tags.append("medium_group")
	elif living_count <= 60:
		tags.append("large_group")
	else:
		tags.append("settlement")

	# --- Skill presence tags ---
	var all_person_skills: Array = []
	for person in population:
		var person_skills = JSON.parse_string(str(person.get("skills", "[]")))
		if person_skills is Array:
			for sk in person_skills:
				if sk not in all_person_skills:
					all_person_skills.append(sk)
	for skill_id in known_skill_ids:
		if skill_id in all_person_skills:
			tags.append("has_skill_" + skill_id)

	# --- Role vacancy tags ---
	var core_roles := ["medic", "farmer", "guard", "teacher", "scavenger", "builder"]
	for role_id in core_roles:
		var filled := false
		for person in population:
			if str(person.get("assigned_role", "")) == role_id:
				filled = true
				break
		if not filled:
			tags.append("role_vacant_" + role_id)

	# --- Season tag ---
	var season: String = str(game_state.get("season", "spring"))
	tags.append("season_" + season)

	# --- Recent event tags ---
	if recent_log_days.size() > 0:
		for entry in recent_log_days:
			var cat: String = str(entry.get("category", ""))
			if cat == "death":
				if "recent_death" not in tags:
					tags.append("recent_death")
			elif cat == "birth":
				if "recent_birth" not in tags:
					tags.append("recent_birth")

	# --- Newcomers present ---
	var game_day: int = int(game_state.get("game_day", 0))
	for person in population:
		var joined: int = int(person.get("joined_day", 0))
		if joined > game_day - 14:
			tags.append("newcomers_present")
			break

	return tags
