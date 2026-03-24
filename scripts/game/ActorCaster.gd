class_name ActorCaster
extends RefCounted


static func cast(
	event: Dictionary,
	population: Array,
	game_day: int
) -> Dictionary:
	var result: Dictionary = {}

	# Parse actor_requirements
	var req_raw = event.get("actor_requirements")
	if req_raw == null or str(req_raw).strip_edges() == "":
		return result

	var requirements = JSON.parse_string(str(req_raw))
	if requirements == null or not (requirements is Dictionary):
		return result

	# Track which people have been cast already (no double-casting)
	var used_ids: Array[String] = []

	# Get event category for personality weighting
	var event_category: String = str(event.get("category", ""))

	for slot_name in requirements:
		var slot: Dictionary = requirements[slot_name] if requirements[slot_name] is Dictionary else {}

		var required_skills: Array = slot.get("required_skills", []) if slot.get("required_skills") is Array else []
		var required_personality = slot.get("required_personality")
		var excluded_flags: Array = slot.get("excluded_flags", []) if slot.get("excluded_flags") is Array else []
		var prefer_not_recent: bool = slot.get("prefer_not_recent", false) == true

		# Step 1: Filter candidates
		var candidates: Array = []
		for person in population:
			var pid: String = str(person.get("id", ""))
			if pid in used_ids:
				continue

			# Check required_skills
			if required_skills.size() > 0:
				var person_skills = JSON.parse_string(str(person.get("skills", "[]")))
				if not (person_skills is Array):
					continue
				var has_skill := false
				for sk in required_skills:
					if sk in person_skills:
						has_skill = true
						break
				if not has_skill:
					continue

			# Check required_personality
			if required_personality != null and str(required_personality) != "":
				if str(person.get("personality", "")) != str(required_personality):
					continue

			# Check excluded_flags
			if excluded_flags.size() > 0:
				var person_flags = JSON.parse_string(str(person.get("flags", "[]")))
				if not (person_flags is Array):
					person_flags = []
				var has_excluded := false
				for fl in excluded_flags:
					if fl in person_flags:
						has_excluded = true
						break
				if has_excluded:
					continue

			candidates.append(person)

		# Step 2: If no candidates, casting fails
		if candidates.size() == 0:
			return {}

		# Step 3: Score and weight candidates
		var weights: Array[float] = []
		for person in candidates:
			var weight: float = 1.0

			# Deprioritise recently mentioned
			if prefer_not_recent:
				var last_mentioned: int = int(person.get("last_mentioned", 0))
				if last_mentioned > 0 and game_day - last_mentioned < 7:
					weight *= 0.3

			# Personality event_weights (look up from library)
			if event_category != "":
				var personality_id: String = str(person.get("personality", ""))
				if personality_id != "":
					var p_row: Dictionary = GameData.get_personality(personality_id)
					if not p_row.is_empty():
						var ew = JSON.parse_string(str(p_row.get("event_weights", "{}")))
						if ew is Dictionary and ew.has(event_category):
							weight *= float(ew[event_category])

			weights.append(maxf(weight, 0.01))

		# Step 4: Weighted random selection
		var total_weight: float = 0.0
		for w in weights:
			total_weight += w

		var roll: float = randf() * total_weight
		var cumulative: float = 0.0
		var selected_idx: int = 0
		for i in range(weights.size()):
			cumulative += weights[i]
			if roll <= cumulative:
				selected_idx = i
				break

		var selected: Dictionary = candidates[selected_idx]
		result[slot_name] = selected
		used_ids.append(str(selected.get("id", "")))

	return result
