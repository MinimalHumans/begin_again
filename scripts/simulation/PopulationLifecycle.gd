class_name PopulationLifecycle


static func run_tick(
	population: Array,
	stats: Dictionary,
	game_state: Dictionary,
	config: Dictionary
) -> Dictionary:
	var births: Array = []
	var deaths: Array = []
	var departures: Array = []

	# --- Natural Deaths (cap 2 per tick) ---
	var health_val: float = float(stats.get("health", 50.0))
	var health_factor: float = (100.0 - health_val) / 50.0
	var base_mortality: float = float(config.get("BASE_MORTALITY_RATE", 0.0002))

	for person in population:
		if deaths.size() >= 2:
			break
		var age: int = int(person.get("age", 25))
		var age_factor := 1.0
		if age < 5:
			age_factor = 1.5
		elif age > 65:
			age_factor = 2.0

		var flag_factor := 1.0
		var flags_str: String = str(person.get("flags", "[]"))
		var has_injured := flags_str.contains("injured")
		var has_sick := flags_str.contains("sick")
		if has_sick:
			flag_factor = 3.0
		elif has_injured:
			flag_factor = 2.0

		var death_chance := base_mortality * health_factor * age_factor * flag_factor
		if randf() < death_chance:
			deaths.append({
				"id": person["id"],
				"name": person["name"],
				"cause": "natural"
			})

	# Collect IDs of dead people so they don't also depart
	var dead_ids := {}
	for d in deaths:
		dead_ids[d["id"]] = true

	# --- Departures (cap 1 per tick) ---
	var morale_val: float = float(stats.get("morale", 50.0))
	var departure_threshold: float = float(config.get("DEPARTURE_MORALE_THRESHOLD", 20.0))
	var departure_rate: float = float(config.get("DEPARTURE_RATE", 0.005))

	if morale_val < departure_threshold:
		for person in population:
			if departures.size() >= 1:
				break
			if dead_ids.has(person["id"]):
				continue
			# Use caregiver's departure_threshold of 15 as default personal threshold
			var personal_threshold := 15.0
			if morale_val < personal_threshold:
				var departure_chance := departure_rate * (personal_threshold - morale_val) / personal_threshold
				if randf() < departure_chance:
					departures.append({
						"id": person["id"],
						"name": person["name"]
					})

	# --- Births (cap 1 per tick) ---
	var women_eligible := 0
	var men_eligible := 0
	for person in population:
		if dead_ids.has(person["id"]):
			continue
		var dominated := false
		for dep in departures:
			if dep["id"] == person["id"]:
				dominated = true
				break
		if dominated:
			continue
		var age: int = int(person.get("age", 25))
		var gender: String = str(person.get("gender", ""))
		if gender == "f" and age >= 18 and age <= 45:
			women_eligible += 1
		elif gender == "m" and age >= 18 and age <= 45:
			men_eligible += 1

	var eligible_pairs := mini(women_eligible, men_eligible)
	var base_birth_rate: float = float(config.get("BASE_BIRTH_RATE", 0.001))
	var birth_chance := base_birth_rate * (health_val / 50.0) * (morale_val / 50.0)

	for i in range(eligible_pairs):
		if births.size() >= 1:
			break
		if randf() < birth_chance:
			var child_gender := "f" if randf() < 0.5 else "m"
			births.append({
				"age": 0,
				"gender": child_gender,
				"skills": "[]",
				"personality": "caregiver"
			})

	return {
		"births": births,
		"deaths": deaths,
		"departures": departures
	}
