class_name NewGameGenerator


static func generate() -> Dictionary:
	# Step 1 — Roll apocalypse
	var apocalypse_rows := DatabaseManager.query_library("SELECT * FROM apocalypses;")
	var apocalypse := _weighted_random(apocalypse_rows)

	# Step 2 — Roll origin
	var origin_rows := DatabaseManager.query_library("SELECT * FROM origins;")
	var origin := _weighted_random(origin_rows)

	# Step 3 — Roll location
	var location_rows := DatabaseManager.query_library("SELECT * FROM locations;")
	var location := _weighted_random(location_rows)

	# Step 4 — Roll starting population count
	var pop_count: int = randi_range(int(origin["population_min"]), int(origin["population_max"]))

	# Step 5 — Generate population members
	var name_pool := DatabaseManager.query_library("SELECT * FROM name_pool;")
	var all_skills := DatabaseManager.query_library("SELECT * FROM skills;")
	var used_names := {}
	var generated_people: Array = []

	for i in range(pop_count):
		var person := _generate_person(i + 1, name_pool, all_skills, used_names)
		generated_people.append(person)
		DatabaseManager.execute_save(
			"INSERT INTO population (id, name, age, gender, alive, joined_day, skills, personality, flags, assigned_role, last_mentioned, mention_context) VALUES (?, ?, ?, ?, 1, 30, ?, ?, ?, NULL, 0, '');",
			[person["id"], person["name"], person["age"], person["gender"], person["skills"], person["personality"], person["flags"]]
		)

	# Step 6 — Calculate starting stats
	var stat_defs := GameData.get_all_stats()
	var apoc_mods: Dictionary = JSON.parse_string(str(apocalypse["stat_modifiers"]))
	if apoc_mods == null:
		apoc_mods = {}
	var origin_mods: Dictionary = JSON.parse_string(str(origin["stat_modifiers"]))
	if origin_mods == null:
		origin_mods = {}
	var location_mods: Dictionary = JSON.parse_string(str(location["stat_modifiers"]))
	if location_mods == null:
		location_mods = {}

	# Pre-calculate skill bonuses per stat
	var skill_bonus_map := _calculate_skill_bonuses(generated_people, all_skills)

	for stat_def in stat_defs:
		var stat_id: String = stat_def["id"]

		if stat_id == "population":
			DatabaseManager.execute_save(
				"INSERT INTO current_stats (stat_id, value) VALUES (?, ?);",
				[stat_id, pop_count]
			)
			continue

		if stat_id == "food":
			# Food calculated separately
			var resource_profile: Dictionary = JSON.parse_string(str(location["resource_profile"]))
			if resource_profile == null:
				resource_profile = {}
			var food_weeks_location: float = float(resource_profile.get("food_weeks", 4))
			var food_weeks_apocalypse: float = float(apoc_mods.get("food", 0))
			var total_food_weeks: float = food_weeks_location + food_weeks_apocalypse
			var food_drain_per_person: float = GameData.get_config("FOOD_DRAIN_PER_PERSON")
			var food_value: float = total_food_weeks * pop_count * food_drain_per_person * 7.0
			food_value = clampf(food_value, float(stat_def["min_value"]), float(stat_def["max_value"]))
			DatabaseManager.execute_save(
				"INSERT INTO current_stats (stat_id, value) VALUES (?, ?);",
				[stat_id, food_value]
			)
			continue

		var base_val: float = float(stat_def["default_value"])
		var apoc_mod: float = float(apoc_mods.get(stat_id, 0))
		var origin_mod: float = float(origin_mods.get(stat_id, 0))
		var location_mod: float = float(location_mods.get(stat_id, 0))
		var skill_bon: float = minf(float(skill_bonus_map.get(stat_id, 0)), 20.0)

		var starting_val: float = clampf(
			base_val + apoc_mod + origin_mod + location_mod + skill_bon,
			float(stat_def["min_value"]),
			float(stat_def["max_value"])
		)
		DatabaseManager.execute_save(
			"INSERT INTO current_stats (stat_id, value) VALUES (?, ?);",
			[stat_id, starting_val]
		)

	# Step 7 — Write world tags
	var env_tags: Array = JSON.parse_string(str(apocalypse["environment_tags"]))
	if env_tags == null:
		env_tags = []
	var loc_tags: Array = JSON.parse_string(str(location["event_tags"]))
	if loc_tags == null:
		loc_tags = []

	var written_tags := {}
	for tag in env_tags:
		if not written_tags.has(tag):
			DatabaseManager.execute_save(
				"INSERT INTO world_tags (tag, source) VALUES (?, 'apocalypse');", [tag]
			)
			written_tags[tag] = true
	for tag in loc_tags:
		if not written_tags.has(tag):
			DatabaseManager.execute_save(
				"INSERT INTO world_tags (tag, source) VALUES (?, 'location');", [tag]
			)
			written_tags[tag] = true

	# Step 8 — Write community_scores
	var community_types := DatabaseManager.query_library("SELECT id FROM community_types;")
	for ct in community_types:
		DatabaseManager.execute_save(
			"INSERT INTO community_scores (type_id, score) VALUES (?, 0.0);", [ct["id"]]
		)

	# Step 9 — Write game_state
	var starting_day_of_year: int = randi_range(1, 365)
	var season := _calculate_season(starting_day_of_year, 30)
	var daily_health_pressure: float = float(apocalypse.get("daily_health_pressure", 0.0))

	# Step 10 — Assemble opening text
	var food_stat_rows := DatabaseManager.query_save("SELECT value FROM current_stats WHERE stat_id = 'food';")
	var food_val: float = 0.0
	if food_stat_rows.size() > 0:
		food_val = float(food_stat_rows[0]["value"])
	var food_drain: float = GameData.get_config("FOOD_DRAIN_PER_PERSON")
	var food_weeks: float = 0.0
	if pop_count > 0 and food_drain > 0:
		food_weeks = food_val / (pop_count * food_drain * 7.0)

	var food_situation := ""
	if food_weeks >= 6.0:
		food_situation = "Supplies are adequate for now"
	elif food_weeks >= 3.0:
		food_situation = "Food will become a concern within weeks"
	else:
		food_situation = "You are already dangerously low on food"

	# Find lowest starting stat (excluding food and population)
	var immediate_concern := "The community is fragile but intact"
	var lowest_val: float = 999.0
	var lowest_name := ""
	var check_stats := DatabaseManager.query_save("SELECT stat_id, value FROM current_stats;")
	for row in check_stats:
		var sid: String = str(row["stat_id"])
		if sid == "food" or sid == "population":
			continue
		var val: float = float(row["value"])
		if val < lowest_val:
			lowest_val = val
			lowest_name = sid

	if lowest_val < 30.0:
		immediate_concern = "Your " + lowest_name + " is critically low"
	elif lowest_val < 45.0:
		immediate_concern = "Your " + lowest_name + " needs attention"

	var context := {
		"apocalypse_opening": str(apocalypse["opening_text"]),
		"origin_opening": str(origin["opening_text"]),
		"location_opening": str(location["opening_text"]),
		"population_count": str(pop_count),
		"food_situation": food_situation,
		"immediate_concern": immediate_concern,
	}

	var opening_text := TemplateResolver.resolve(
		"It has been 30 days since {apocalypse_opening}\n\n" +
		"{origin_opening}\n\n" +
		"{location_opening}\n\n" +
		"You have {population_count} people. {food_situation}. {immediate_concern}.\n\n" +
		"What kind of leader will you be?",
		context
	)

	DatabaseManager.execute_save(
		"INSERT INTO game_state (id, game_day, starting_day_of_year, apocalypse_id, origin_id, location_id, season, food_production, difficulty_time_factor, opening_text, game_over, daily_health_pressure) VALUES (1, 30, ?, ?, ?, ?, ?, 0.0, 0.0, ?, 0, ?);",
		[starting_day_of_year, apocalypse["id"], origin["id"], location["id"], season, opening_text, daily_health_pressure]
	)

	return { "opening_text": opening_text }


# ---------- Helpers ----------

static func _weighted_random(rows: Array) -> Dictionary:
	var total_weight := 0.0
	for row in rows:
		total_weight += float(row.get("weight", 1.0))

	var roll: float = randf() * total_weight
	var cumulative := 0.0
	for row in rows:
		cumulative += float(row.get("weight", 1.0))
		if roll <= cumulative:
			return row

	return rows[rows.size() - 1]


static func _generate_person(index: int, name_pool: Array, all_skills: Array, used_names: Dictionary) -> Dictionary:
	# Name
	var available_names: Array = []
	for entry in name_pool:
		if not used_names.has(entry["name"]):
			available_names.append(entry)

	var chosen_name_entry: Dictionary
	if available_names.size() > 0:
		chosen_name_entry = available_names[randi() % available_names.size()]
	else:
		# Fallback if pool exhausted
		chosen_name_entry = name_pool[randi() % name_pool.size()]

	var person_name: String = str(chosen_name_entry["name"])
	used_names[person_name] = true

	# Gender
	var gender: String
	if chosen_name_entry.has("gender") and chosen_name_entry["gender"] != null:
		gender = str(chosen_name_entry["gender"])
	else:
		gender = "f" if randf() < 0.5 else "m"

	# Age (weighted bands)
	var age := _roll_age()

	# Skills (1-3 per person)
	var skill_count_roll: float = randf()
	var skill_count: int
	if skill_count_roll < 0.50:
		skill_count = 1
	elif skill_count_roll < 0.85:
		skill_count = 2
	else:
		skill_count = 3
	skill_count = mini(skill_count, all_skills.size())

	var skill_pool := all_skills.duplicate()
	var chosen_skills: Array = []
	for _j in range(skill_count):
		if skill_pool.size() == 0:
			break
		var pick_idx: int = randi() % skill_pool.size()
		chosen_skills.append(str(skill_pool[pick_idx]["id"]))
		skill_pool.remove_at(pick_idx)

	var skills_json := JSON.stringify(chosen_skills)

	# Personality (Phase 1: always caregiver)
	var personality := "caregiver"

	# Flags (10% chance of injured)
	var flags: Array = []
	if randf() < 0.10:
		flags.append("injured")
	var flags_json := JSON.stringify(flags)

	# ID
	var person_id := "p_%04d" % index

	return {
		"id": person_id,
		"name": person_name,
		"age": age,
		"gender": gender,
		"skills": skills_json,
		"personality": personality,
		"flags": flags_json,
	}


static func _roll_age() -> int:
	# Bands: 18-35 (50), 36-55 (30), 56-70 (10), 5-17 (8), 0-4 (2)
	var total := 100.0
	var roll: float = randf() * total
	if roll < 50.0:
		return randi_range(18, 35)
	elif roll < 80.0:
		return randi_range(36, 55)
	elif roll < 90.0:
		return randi_range(56, 70)
	elif roll < 98.0:
		return randi_range(5, 17)
	else:
		return randi_range(0, 4)


static func _calculate_skill_bonuses(people: Array, all_skills: Array) -> Dictionary:
	# Build skill -> stat_links lookup
	var skill_links := {}
	for skill in all_skills:
		var links: Dictionary = JSON.parse_string(str(skill["stat_links"]))
		if links == null:
			links = {}
		skill_links[str(skill["id"])] = links

	var bonus_map := {}
	for person in people:
		var person_skills: Array = JSON.parse_string(str(person["skills"]))
		if person_skills == null:
			continue
		for skill_id in person_skills:
			if not skill_links.has(skill_id):
				continue
			var links: Dictionary = skill_links[skill_id]
			for stat_id in links:
				if float(links[stat_id]) > 0:
					if not bonus_map.has(stat_id):
						bonus_map[stat_id] = 0.0
					bonus_map[stat_id] += 2.0

	return bonus_map


static func _calculate_season(starting_day_of_year: int, game_day: int) -> String:
	var day_of_year: int = (starting_day_of_year + game_day) % 365
	if day_of_year >= 335 or day_of_year < 60:
		return "winter"
	elif day_of_year < 152:
		return "spring"
	elif day_of_year < 244:
		return "summer"
	elif day_of_year < 335:
		return "fall"
	return "winter"
