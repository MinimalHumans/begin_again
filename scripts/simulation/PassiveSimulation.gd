class_name PassiveSimulation


static func run_tick(
	stats: Dictionary,
	game_state: Dictionary,
	role_bonuses: Dictionary,
	config: Dictionary,
	role_food_production: float,
	popup_active: bool = false
) -> Dictionary:
	var delta := {}
	var population: float = maxf(float(stats.get("population", 1)), 1.0)
	var season: String = str(game_state.get("season", "spring"))

	# --- Food ---
	var season_key := "SEASON_" + season.to_upper()
	var season_mod: float = float(config.get(season_key, 1.0))
	var base_food_prod: float = float(game_state.get("food_production", 0.0))
	var effective_food_production: float = (base_food_prod + role_food_production) * season_mod
	var food_drain: float = population * float(config.get("FOOD_DRAIN_PER_PERSON", 0.14))
	delta["food"] = effective_food_production - food_drain

	# --- Resources ---
	var resource_drain: float = population * float(config.get("RESOURCE_DRAIN_PER_PERSON", 0.02))
	var resource_bonus: float = float(role_bonuses.get("resources", 0.0))
	delta["resources"] = resource_bonus - resource_drain

	# If resources are at or near zero, food production suffers (tools failing)
	var resource_val: float = float(stats.get("resources", 0.0))
	if resource_val <= 5.0:
		delta["food"] = delta.get("food", 0.0) - (population * float(config.get("FOOD_DRAIN_PER_PERSON", 0.14)) * 0.3)

	# --- Health ---
	var medic_bonus: float = float(role_bonuses.get("health", 0.0))
	var daily_health_pressure: float = float(game_state.get("daily_health_pressure", 0.0))
	var health_decay: float = float(config.get("HEALTH_DECAY_RATE", 0.05))
	delta["health"] = medic_bonus - health_decay - daily_health_pressure

	# --- Security ---
	var guard_bonus: float = float(role_bonuses.get("security", 0.0))
	var security_decay: float = float(config.get("SECURITY_DECAY_RATE", 0.03))
	delta["security"] = guard_bonus - security_decay

	# --- Morale ---
	var food_val: float = float(stats.get("food", 0.0))
	var food_weeks: float = food_val / maxf(population * float(config.get("FOOD_DRAIN_PER_PERSON", 0.14)) * 7.0, 0.001)
	var food_adequacy: float = clampf(food_weeks / 10.0 * 100.0, 0.0, 100.0)
	var morale_baseline: float = (float(stats.get("health", 50.0)) + food_adequacy + float(stats.get("security", 50.0)) + float(stats.get("cohesion", 50.0))) / 4.0
	var morale_current: float = float(stats.get("morale", 50.0))
	var morale_drift: float = float(config.get("MORALE_DRIFT_RATE", 0.02))
	delta["morale"] = (morale_baseline - morale_current) * morale_drift

	# --- Cohesion ---
	var pop_over: float = maxf(population - float(config.get("COHESION_POP_THRESHOLD", 25.0)), 0.0)
	var cohesion_baseline: float = (float(stats.get("morale", 50.0)) + float(stats.get("stability", 50.0))) / 2.0 - (pop_over * float(config.get("COHESION_POP_PENALTY", 0.5)))
	cohesion_baseline = clampf(cohesion_baseline, 0.0, 100.0)
	var cohesion_current: float = float(stats.get("cohesion", 50.0))
	var cohesion_drift: float = float(config.get("COHESION_DRIFT_RATE", 0.02))
	delta["cohesion"] = (cohesion_baseline - cohesion_current) * cohesion_drift

	# --- Reputation ---
	var rep_current: float = float(stats.get("reputation", 50.0))
	var rep_drift: float = float(config.get("REPUTATION_DRIFT_RATE", 0.005))
	delta["reputation"] = (50.0 - rep_current) * rep_drift

	# --- Knowledge ---
	var teacher_bonus: float = float(role_bonuses.get("knowledge", 0.0))
	delta["knowledge"] = teacher_bonus

	# --- Overthrow pressure ---
	if popup_active and stats.get("stability", 100) < 10:
		delta["stability"] = delta.get("stability", 0) - 2.0

	return delta
