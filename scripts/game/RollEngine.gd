class_name RollEngine
extends RefCounted


static func roll(
	choice: Dictionary,
	stats: Dictionary,
	actors: Dictionary,
	game_state: Dictionary,
	flags: Array,
	world_tags: Array,
	community_modifiers: Dictionary = {}
) -> Dictionary:
	var roll_config: Dictionary = choice.get("roll", {})
	if not (roll_config is Dictionary):
		roll_config = {}

	# --- base_value ---
	var base_value: float = float(roll_config.get("base_value", 0.0))

	# --- stat_bonus ---
	var stat_bonus: float = 0.0
	var relevant_stats = roll_config.get("relevant_stats", [])
	if relevant_stats is Array:
		for entry in relevant_stats:
			if not (entry is Dictionary):
				continue
			var stat_id: String = str(entry.get("stat", ""))
			var weight: float = float(entry.get("weight", 0.0))
			var stat_val: float = float(stats.get(stat_id, 50.0))
			var contribution: float = (stat_val - 50.0) * weight * 0.02
			contribution += float(community_modifiers.get(stat_id, 0.0)) * weight
			stat_bonus += contribution

	# --- context_bonus ---
	var context_bonus: float = 0.0
	var context_bonuses = roll_config.get("context_bonuses", [])
	if context_bonuses is Array:
		for cb in context_bonuses:
			if not (cb is Dictionary):
				continue
			var condition: String = str(cb.get("condition", ""))
			var bonus: float = float(cb.get("bonus", 0.0))
			if _evaluate_condition(condition, actors, stats, flags, world_tags, game_state):
				context_bonus += bonus

	# --- roll_value (3d6 bell curve) ---
	var d1: int = randi_range(1, 6)
	var d2: int = randi_range(1, 6)
	var d3: int = randi_range(1, 6)
	var raw: float = float(d1 + d2 + d3)
	var time_factor: float = float(game_state.get("difficulty_time_factor", 0.0))
	var divisor: float = 7.5 - time_factor
	if divisor < 1.0:
		divisor = 1.0
	var roll_value: float = (raw - 10.5) / divisor

	# --- outcome_score ---
	var outcome_score: float = base_value + stat_bonus + context_bonus + roll_value

	# --- tier mapping ---
	var tier: String
	if outcome_score < -1.0:
		tier = "catastrophic"
	elif outcome_score < -0.3:
		tier = "bad"
	elif outcome_score <= 0.3:
		tier = "mixed"
	elif outcome_score <= 1.0:
		tier = "good"
	else:
		tier = "exceptional"

	# --- fallback if tier not in outcomes ---
	var outcomes = choice.get("outcomes", {})
	if outcomes is Dictionary and not outcomes.has(tier):
		tier = _find_nearest_tier(tier, outcomes)

	return {"outcome_tier": tier, "outcome_score": outcome_score}


static func _evaluate_condition(
	condition: String,
	actors: Dictionary,
	stats: Dictionary,
	flags: Array,
	world_tags: Array,
	game_state: Dictionary
) -> bool:
	if condition.is_empty():
		return false

	var parts: PackedStringArray = condition.split(":")

	match parts[0]:
		"actor_has_skill":
			if parts.size() < 2:
				return false
			var skill_id: String = parts[1]
			var actor = actors.get("actor_1", {})
			if actor is Dictionary:
				var skills = JSON.parse_string(str(actor.get("skills", "[]")))
				if skills is Array:
					return skill_id in skills
			return false

		"actor_personality":
			if parts.size() < 2:
				return false
			var actor = actors.get("actor_1", {})
			if actor is Dictionary:
				return str(actor.get("personality", "")) == parts[1]
			return false

		"flag":
			if parts.size() < 2:
				return false
			return parts[1] in flags

		"season":
			if parts.size() < 2:
				return false
			return str(game_state.get("season", "")).to_lower() == parts[1].to_lower()

		"stat_above":
			if parts.size() < 3:
				return false
			var val: float = float(stats.get(parts[1], 0.0))
			return val > float(parts[2])

		"stat_below":
			if parts.size() < 3:
				return false
			var val: float = float(stats.get(parts[1], 0.0))
			return val < float(parts[2])

		"world_tag":
			if parts.size() < 2:
				return false
			return parts[1] in world_tags

		"actor_relationship":
			if parts.size() < 3:
				return false
			var relationship_type: String = parts[1]
			var other_role: String = parts[2]
			var actor_a = actors.get("actor_1", {})
			var actor_b = actors.get(other_role, {})
			if actor_a is Dictionary and actor_b is Dictionary:
				var id_a: String = str(actor_a.get("id", ""))
				var id_b: String = str(actor_b.get("id", ""))
				if id_a != "" and id_b != "":
					if relationship_type == "close_to":
						return RelationalSystem.has_bond(id_a, id_b)
					elif relationship_type == "grudge_against":
						return RelationalSystem.has_grudge(id_a, id_b)
			return false

	return false


static func _find_nearest_tier(target: String, outcomes: Dictionary) -> String:
	var tier_order: Array[String] = ["catastrophic", "bad", "mixed", "good", "exceptional"]
	var target_idx: int = tier_order.find(target)
	if target_idx < 0:
		target_idx = 2  # default to mixed

	# Search outward from target toward center (mixed)
	for dist in range(1, 5):
		# Try toward center first
		var toward_center: int
		if target_idx <= 2:
			toward_center = target_idx + dist
		else:
			toward_center = target_idx - dist
		if toward_center >= 0 and toward_center < tier_order.size():
			if outcomes.has(tier_order[toward_center]):
				return tier_order[toward_center]
		# Try away from center
		var away: int
		if target_idx <= 2:
			away = target_idx - dist
		else:
			away = target_idx + dist
		if away >= 0 and away < tier_order.size():
			if outcomes.has(tier_order[away]):
				return tier_order[away]

	# Last resort: return any available tier
	for t in tier_order:
		if outcomes.has(t):
			return t
	return "mixed"
