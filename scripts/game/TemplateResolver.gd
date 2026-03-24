class_name TemplateResolver


static func resolve(template: String, context: Dictionary) -> String:
	var result := template
	for key in context:
		result = result.replace("{" + str(key) + "}", str(context[key]))
	return result


static func resolve_event(
	template: String,
	actors: Dictionary,
	stats: Dictionary,
	game_state: Dictionary,
	location_structures: Array,
	chain_memory: Dictionary
) -> String:
	var result := template

	# --- Pass 1: Actor variables ---
	for actor_key in actors:
		var person: Dictionary = actors[actor_key]
		# {actor_N} → name
		result = result.replace("{" + actor_key + "}", str(person.get("name", "")))

		# {actor_N_modifier} → random description_modifier from personality
		var modifier := ""
		var personality_id: String = str(person.get("personality", ""))
		if personality_id != "":
			var p_row: Dictionary = GameData.get_personality(personality_id)
			if not p_row.is_empty():
				var bp = JSON.parse_string(str(p_row.get("behavior_profile", "{}")))
				if bp is Dictionary:
					var mods = bp.get("description_modifiers", [])
					if mods is Array and mods.size() > 0:
						modifier = str(mods[randi() % mods.size()])
		result = result.replace("{" + actor_key + "_modifier}", modifier)

		# {actor_N_mention} → mention_context
		var mention: String = str(person.get("mention_context", ""))
		if mention == "<null>" or mention == "null":
			mention = ""
		result = result.replace("{" + actor_key + "_mention}", mention)

	# --- Pass 2: Stat band variables ---
	var bar_stats := ["morale", "health", "security", "knowledge", "cohesion", "resources", "stability", "reputation"]
	for stat_id in bar_stats:
		var token: String = "{stat." + stat_id + "}"
		if result.contains(token):
			var val: float = float(stats.get(stat_id, 50.0))
			result = result.replace(token, _stat_band(val))

	# {stat.food} → food weeks band
	if result.contains("{stat.food}"):
		var food_val: float = float(stats.get("food", 0))
		var pop_val: float = float(stats.get("population", 1))
		var food_weeks: float = food_val / maxf(pop_val, 1.0) / 0.14 / 7.0
		var band: String
		if food_weeks < 1.0:
			band = "critical"
		elif food_weeks < 3.0:
			band = "low"
		elif food_weeks < 6.0:
			band = "moderate"
		else:
			band = "adequate"
		result = result.replace("{stat.food}", band)

	# --- Pass 3: Location, game state, chain_memory ---
	# {building}
	if result.contains("{building}"):
		var building := "the common area"
		if location_structures.size() > 0:
			building = str(location_structures[randi() % location_structures.size()])
		result = result.replace("{building}", building)

	# {season}
	if result.contains("{season}"):
		var season: String = str(game_state.get("season", "spring"))
		result = result.replace("{season}", season.capitalize())

	# {population_count}
	if result.contains("{population_count}"):
		result = result.replace("{population_count}", str(int(stats.get("population", 0))))

	# {game_day}
	if result.contains("{game_day}"):
		result = result.replace("{game_day}", str(game_state.get("game_day", 0)))

	# {outcome_label}
	if result.contains("{outcome_label}"):
		var label: String = str(chain_memory.get("_outcome_label", ""))
		result = result.replace("{outcome_label}", label)

	# Chain memory tokens
	for key in chain_memory:
		if str(key).begins_with("_"):
			continue
		result = result.replace("{" + str(key) + "}", str(chain_memory[key]))

	# --- Pass 4: Base resolve for any remaining simple tokens ---
	result = resolve(result, {})

	# --- Strip any unresolved {variable} tokens ---
	var regex := RegEx.new()
	regex.compile("\\{[a-zA-Z0-9_.]+\\}")
	result = regex.sub(result, "", true)

	return result


static func _stat_band(val: float) -> String:
	if val <= 20.0:
		return "critical"
	elif val <= 40.0:
		return "low"
	elif val <= 60.0:
		return "moderate"
	elif val <= 80.0:
		return "good"
	else:
		return "high"
