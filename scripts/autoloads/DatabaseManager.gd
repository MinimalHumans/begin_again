extends Node

var _library_db: SQLite = null
var _save_db: SQLite = null


func open_library() -> bool:
	_library_db = SQLite.new()
	_library_db.path = "res://database/library.db"
	if not _library_db.open_db():
		push_error("DatabaseManager: Failed to open library.db")
		return false

	# Check if the database has already been set up
	var check := _library_db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='stats';")
	if not check or _library_db.query_result.size() == 0:
		_create_library_schema()
		_seed_library_data()
	else:
		# Ensure events table exists and is seeded (added in Phase 2b)
		_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 1;")
		if _library_db.query_result.size() == 0 or int(_library_db.query_result[0].get("cnt", 0)) < 50:
			_seed_tier1_events()

	return true


func open_save(path: String) -> bool:
	_save_db = SQLite.new()
	_save_db.path = path
	if not _save_db.open_db():
		push_error("DatabaseManager: Failed to open save.db at " + path)
		return false

	# Check if save schema exists
	var check := _save_db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='game_state';")
	if not check or _save_db.query_result.size() == 0:
		_create_save_schema()

	return true


func reset_save(path: String) -> void:
	if _save_db:
		_save_db.close_db()
		_save_db = null
	# Delete the existing file
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	# Re-open and recreate schema
	open_save(path)


func close_all() -> void:
	if _library_db:
		_library_db.close_db()
		_library_db = null
	if _save_db:
		_save_db.close_db()
		_save_db = null


func query_library(sql: String, params: Array = []) -> Array:
	if not _library_db:
		push_error("DatabaseManager: library.db is not open")
		return []
	if params.size() > 0:
		_library_db.query_with_bindings(sql, params)
	else:
		_library_db.query(sql)
	return _library_db.query_result.duplicate()


func query_save(sql: String, params: Array = []) -> Array:
	if not _save_db:
		push_error("DatabaseManager: save.db is not open")
		return []
	if params.size() > 0:
		_save_db.query_with_bindings(sql, params)
	else:
		_save_db.query(sql)
	return _save_db.query_result.duplicate()


func execute_save(sql: String, params: Array = []) -> void:
	if not _save_db:
		push_error("DatabaseManager: save.db is not open")
		return
	if params.size() > 0:
		_save_db.query_with_bindings(sql, params)
	else:
		_save_db.query(sql)


func execute_library(sql: String, params: Array = []) -> void:
	if not _library_db:
		push_error("DatabaseManager: library.db is not open")
		return
	if params.size() > 0:
		_library_db.query_with_bindings(sql, params)
	else:
		_library_db.query(sql)


# ---------- Library Schema ----------

func _create_library_schema() -> void:
	_library_db.query("CREATE TABLE IF NOT EXISTS stats (
		id            TEXT PRIMARY KEY,
		display_name  TEXT NOT NULL,
		description   TEXT NOT NULL,
		min_value     REAL DEFAULT 0,
		max_value     REAL DEFAULT 100,
		default_value REAL DEFAULT 50,
		warning_low   REAL DEFAULT 20,
		critical_low  REAL DEFAULT 10,
		warning_high  REAL,
		critical_high REAL,
		display_order INTEGER NOT NULL,
		format_type   TEXT DEFAULT 'bar'
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS community_types (
		id             TEXT PRIMARY KEY,
		display_name   TEXT NOT NULL,
		description    TEXT NOT NULL,
		reveal_text    TEXT NOT NULL,
		roll_modifiers TEXT NOT NULL,
		thresholds     TEXT NOT NULL
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS apocalypses (
		id                    TEXT PRIMARY KEY,
		category              TEXT NOT NULL,
		variant               TEXT NOT NULL,
		name                  TEXT NOT NULL,
		opening_text          TEXT NOT NULL,
		environment_tags      TEXT NOT NULL,
		scarce_resources      TEXT NOT NULL,
		abundant_resources    TEXT NOT NULL,
		stat_modifiers        TEXT NOT NULL,
		world_danger_type     TEXT NOT NULL,
		daily_health_pressure REAL DEFAULT 0.0,
		population_cap_mod    REAL DEFAULT 1.0,
		event_tags            TEXT NOT NULL,
		weight                REAL DEFAULT 1.0
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS origins (
		id                  TEXT PRIMARY KEY,
		name                TEXT NOT NULL,
		opening_text        TEXT NOT NULL,
		population_min      INTEGER NOT NULL,
		population_max      INTEGER NOT NULL,
		stat_modifiers      TEXT NOT NULL,
		skill_weights       TEXT NOT NULL,
		personality_weights TEXT NOT NULL,
		weight              REAL DEFAULT 1.0
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS locations (
		id               TEXT PRIMARY KEY,
		category         TEXT NOT NULL,
		variant          TEXT NOT NULL,
		name_template    TEXT NOT NULL,
		opening_text     TEXT NOT NULL,
		stat_modifiers   TEXT NOT NULL,
		event_tags       TEXT NOT NULL,
		resource_profile TEXT NOT NULL,
		terrain_tags     TEXT NOT NULL,
		structures       TEXT NOT NULL,
		weight           REAL DEFAULT 1.0
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS name_pool (
		id        INTEGER PRIMARY KEY AUTOINCREMENT,
		name      TEXT NOT NULL,
		gender    TEXT,
		ethnicity TEXT
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS skills (
		id           TEXT PRIMARY KEY,
		display_name TEXT NOT NULL,
		description  TEXT NOT NULL,
		stat_links   TEXT NOT NULL
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS personalities (
		id                TEXT PRIMARY KEY,
		display_name      TEXT NOT NULL,
		description       TEXT NOT NULL,
		stat_links        TEXT NOT NULL,
		event_weights     TEXT NOT NULL,
		behavior_profile  TEXT NOT NULL,
		ambient_templates TEXT NOT NULL
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS roles (
		id              TEXT PRIMARY KEY,
		display_name    TEXT NOT NULL,
		description     TEXT NOT NULL,
		required_skills TEXT NOT NULL,
		stat_bonuses    TEXT NOT NULL,
		max_slots       INTEGER DEFAULT 1
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS simulation_config (
		key         TEXT PRIMARY KEY,
		value       REAL NOT NULL,
		description TEXT NOT NULL
	);")

	_library_db.query("CREATE TABLE IF NOT EXISTS events (
		id                   TEXT PRIMARY KEY,
		tier                 INTEGER NOT NULL,
		category             TEXT NOT NULL,
		title                TEXT NOT NULL,
		eligibility          TEXT NOT NULL,
		description_template TEXT NOT NULL,
		actor_requirements   TEXT,
		choices              TEXT,
		chain_id             TEXT,
		chain_stage          INTEGER,
		chain_memory_schema  TEXT,
		cooldown_days        INTEGER DEFAULT 0,
		exclusion_group      TEXT,
		max_occurrences      INTEGER,
		content_tags         TEXT,
		seasonal_tags        TEXT,
		weight               REAL DEFAULT 1.0
	);")


# ---------- Save Schema ----------

func _create_save_schema() -> void:
	_save_db.query("CREATE TABLE IF NOT EXISTS game_state (
		id                     INTEGER PRIMARY KEY DEFAULT 1,
		game_day               INTEGER NOT NULL DEFAULT 30,
		starting_day_of_year   INTEGER NOT NULL,
		apocalypse_id          TEXT NOT NULL,
		origin_id              TEXT NOT NULL,
		location_id            TEXT NOT NULL,
		season                 TEXT NOT NULL,
		food_production        REAL DEFAULT 0.0,
		difficulty_time_factor REAL DEFAULT 0.0,
		opening_text           TEXT NOT NULL,
		game_over              INTEGER DEFAULT 0,
		game_over_reason       TEXT,
		game_over_text         TEXT,
		daily_health_pressure  REAL DEFAULT 0.0
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS world_tags (
		tag     TEXT PRIMARY KEY,
		source  TEXT NOT NULL
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS current_stats (
		stat_id TEXT PRIMARY KEY,
		value   REAL NOT NULL,
		trend   TEXT DEFAULT 'stable'
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS stat_history (
		id       INTEGER PRIMARY KEY AUTOINCREMENT,
		stat_id  TEXT NOT NULL,
		game_day INTEGER NOT NULL,
		value    REAL NOT NULL
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS population (
		id              TEXT PRIMARY KEY,
		name            TEXT NOT NULL,
		age             INTEGER NOT NULL,
		gender          TEXT,
		alive           INTEGER DEFAULT 1,
		joined_day      INTEGER NOT NULL,
		died_day        INTEGER,
		death_cause     TEXT,
		skills          TEXT NOT NULL,
		personality     TEXT NOT NULL,
		flags           TEXT DEFAULT '[]',
		assigned_role   TEXT,
		last_mentioned  INTEGER DEFAULT 0,
		mention_context TEXT
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS community_scores (
		type_id TEXT PRIMARY KEY,
		score   REAL DEFAULT 0.0,
		rank    INTEGER
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS event_log (
		id             INTEGER PRIMARY KEY AUTOINCREMENT,
		game_day       INTEGER NOT NULL,
		tier           INTEGER NOT NULL,
		event_id       TEXT,
		category       TEXT NOT NULL,
		display_text   TEXT NOT NULL,
		choice_made    TEXT,
		outcome_tier   TEXT,
		outcome_score  REAL,
		stat_changes   TEXT,
		is_highlighted INTEGER DEFAULT 0,
		is_major       INTEGER DEFAULT 0
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS pending_deferred (
		id                INTEGER PRIMARY KEY AUTOINCREMENT,
		source_event_id   TEXT NOT NULL,
		source_choice_id  TEXT NOT NULL,
		source_log_id     INTEGER NOT NULL,
		actor_ids         TEXT NOT NULL,
		earliest_fire_day INTEGER NOT NULL,
		latest_fire_day   INTEGER NOT NULL,
		check_config      TEXT NOT NULL,
		outcomes          TEXT NOT NULL,
		log_hints         TEXT,
		fired             INTEGER DEFAULT 0,
		fired_day         INTEGER,
		fired_outcome     TEXT
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS active_chains (
		chain_id       TEXT PRIMARY KEY,
		current_stage  INTEGER NOT NULL,
		memory         TEXT NOT NULL,
		started_day    INTEGER NOT NULL,
		last_stage_day INTEGER NOT NULL,
		next_fire_day  INTEGER
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS flags (
		flag_name TEXT PRIMARY KEY,
		set_day   INTEGER NOT NULL,
		source    TEXT
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS cooldowns (
		event_id        TEXT,
		exclusion_group TEXT,
		expires_day     INTEGER NOT NULL
	);")

	_save_db.query("CREATE TABLE IF NOT EXISTS event_occurrence_counts (
		event_id TEXT PRIMARY KEY,
		count    INTEGER DEFAULT 0
	);")


# ---------- Seed Data ----------

func _seed_library_data() -> void:
	_seed_stats()
	_seed_simulation_config()
	_seed_apocalypses()
	_seed_origins()
	_seed_locations()
	_seed_name_pool()
	_seed_skills()
	_seed_personalities()
	_seed_roles()
	_seed_community_types()
	_seed_tier1_events()


func _seed_stats() -> void:
	var rows := [
		["population", "Population", "Total number of living community members", 0, 9999, 0, 10, 5, null, null, 1, "number"],
		["food", "Food Supply", "Weeks of food reserves at current consumption rate", 0, 9999, 0, 3, 1, null, null, 2, "weeks"],
		["morale", "Morale", "Whether people want to be here", 0, 100, 50, 20, 10, null, null, 3, "bar"],
		["health", "Health", "Medical supplies, disease risk, general wellness", 0, 100, 50, 20, 10, null, null, 4, "bar"],
		["security", "Security", "External threat protection", 0, 100, 50, 20, 10, null, null, 5, "bar"],
		["knowledge", "Knowledge", "Technical and practical understanding", 0, 100, 50, 15, 5, null, null, 6, "bar"],
		["cohesion", "Cohesion", "Whether people are together and cooperating", 0, 100, 50, 20, 10, null, null, 7, "bar"],
		["resources", "Resources", "Materials, tools, fuel, building supplies", 0, 100, 50, 20, 10, null, null, 8, "bar"],
		["stability", "Stability", "How well governance functions", 0, 100, 50, 20, 10, null, null, 9, "bar"],
		["reputation", "Reputation", "How outsiders perceive the settlement", 0, 100, 50, null, null, null, null, 10, "bar"],
	]
	for r in rows:
		_library_db.query_with_bindings(
			"INSERT INTO stats (id, display_name, description, min_value, max_value, default_value, warning_low, critical_low, warning_high, critical_high, display_order, format_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			r
		)


func _seed_simulation_config() -> void:
	var rows := [
		["FOOD_DRAIN_PER_PERSON", 0.14, "Daily food consumed per person"],
		["RESOURCE_DRAIN_PER_PERSON", 0.02, "Daily resources consumed per person"],
		["HEALTH_DECAY_RATE", 0.05, "Daily health loss without medical care"],
		["SECURITY_DECAY_RATE", 0.03, "Daily security loss without guards"],
		["MORALE_DRIFT_RATE", 0.02, "Speed of morale convergence to baseline"],
		["COHESION_DRIFT_RATE", 0.02, "Speed of cohesion convergence to baseline"],
		["REPUTATION_DRIFT_RATE", 0.005, "Speed of reputation convergence toward 50"],
		["TEACHING_RATE", 0.02, "Daily knowledge gain with a qualified teacher"],
		["COHESION_POP_THRESHOLD", 25.0, "Population above which cohesion baseline is penalized"],
		["COHESION_POP_PENALTY", 0.5, "Cohesion baseline penalty per person over threshold"],
		["SEASON_SPRING", 0.8, "Food production multiplier in spring"],
		["SEASON_SUMMER", 1.2, "Food production multiplier in summer"],
		["SEASON_FALL", 1.0, "Food production multiplier in fall"],
		["SEASON_WINTER", 0.3, "Food production multiplier in winter"],
		["BASE_BIRTH_RATE", 0.001, "Daily birth probability per eligible pair"],
		["BASE_MORTALITY_RATE", 0.0002, "Daily death probability per person"],
		["DEPARTURE_MORALE_THRESHOLD", 20.0, "Morale below which departures can occur"],
		["DEPARTURE_RATE", 0.005, "Daily departure probability when below threshold"],
	]
	for r in rows:
		_library_db.query_with_bindings(
			"INSERT INTO simulation_config (key, value, description) VALUES (?, ?, ?);",
			r
		)


func _seed_apocalypses() -> void:
	_library_db.query_with_bindings(
		"INSERT INTO apocalypses (id, category, variant, name, opening_text, environment_tags, scarce_resources, abundant_resources, stat_modifiers, world_danger_type, daily_health_pressure, population_cap_mod, event_tags, weight) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[
			"nuclear_exchange", "Nuclear", "Full Exchange", "The Last War",
			"the missiles flew. Within hours, every major city was ash. The fires burned for weeks. The sky is still grey.",
			'["radiation","infrastructure_damaged","low_survivors"]',
			'["medicine","food","clean_water"]',
			'["salvage","metal"]',
			'{"health":-20,"food":-2,"security":-10,"knowledge":-5}',
			"radiation", 0.02, 1.0,
			'["radiation","nuclear","infrastructure_damaged"]',
			1.0
		]
	)


func _seed_origins() -> void:
	_library_db.query_with_bindings(
		"INSERT INTO origins (id, name, opening_text, population_min, population_max, stat_modifiers, skill_weights, personality_weights, weight) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[
			"founder", "Founder",
			"You gathered these people. They follow you because you are the reason they are alive.",
			5, 15,
			'{"stability":10,"morale":5,"cohesion":5}',
			'{}', '{}', 1.0
		]
	)


func _seed_locations() -> void:
	_library_db.query_with_bindings(
		"INSERT INTO locations (id, category, variant, name_template, opening_text, stat_modifiers, event_tags, resource_profile, terrain_tags, structures, weight) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[
			"suburban_residential", "Suburban", "Residential",
			"a suburban neighborhood",
			"You have settled in a quiet residential area. Houses with overgrown gardens surround you. The streets are empty but the pantries are not — yet.",
			'{"health":0,"security":5,"resources":5}',
			'["suburban","residential"]',
			'{"food_weeks":5,"salvage":"moderate","medical":"low"}',
			'["suburban","flat","sheltered"]',
			'["the cul-de-sac","the old school","the community garden","the hardware store","the church","the park"]',
			1.0
		]
	)


func _seed_name_pool() -> void:
	var names := [
		["Ana", "f"], ["Beth", "f"], ["Clara", "f"], ["Dena", "f"], ["Eva", "f"],
		["Farah", "f"], ["Grace", "f"], ["Hana", "f"], ["Iris", "f"], ["Jana", "f"],
		["Aaron", "m"], ["Ben", "m"], ["Cole", "m"], ["Dani", "m"], ["Eli", "m"],
		["Finn", "m"], ["Grant", "m"], ["Hugo", "m"], ["Ivan", "m"], ["Jack", "m"],
	]
	for n in names:
		_library_db.query_with_bindings(
			"INSERT INTO name_pool (name, gender, ethnicity) VALUES (?, ?, NULL);",
			[n[0], n[1]]
		)


func _seed_skills() -> void:
	var rows := [
		["medicine", "Medicine", "Medical knowledge and treatment skills", '{"health":0.5,"knowledge":0.2}'],
		["farming", "Farming", "Agricultural and food production skills", '{"food":0.4,"knowledge":0.1}'],
		["combat", "Combat", "Fighting and defensive skills", '{"security":0.5}'],
		["engineering", "Engineering", "Construction and technical repair skills", '{"resources":0.3,"knowledge":0.3}'],
		["teaching", "Teaching", "Ability to pass on knowledge to others", '{"knowledge":0.5}'],
	]
	for r in rows:
		_library_db.query_with_bindings(
			"INSERT INTO skills (id, display_name, description, stat_links) VALUES (?, ?, ?, ?);",
			r
		)


func _seed_personalities() -> void:
	_library_db.query_with_bindings(
		"INSERT INTO personalities (id, display_name, description, stat_links, event_weights, behavior_profile, ambient_templates) VALUES (?, ?, ?, ?, ?, ?, ?);",
		[
			"caregiver", "Caregiver",
			"Puts others first. Natural healer and mediator. Will sacrifice their own needs for the group.",
			'{"morale":0.2,"health":0.1}',
			'{"dispute":-0.5,"illness":1.5,"breakdown":0.8}',
			'{"instigator_weight":0.1,"helper_weight":2.0,"departure_threshold":15,"description_modifiers":["quietly","gently","carefully","with steady hands"]}',
			'["{actor_1} quietly checked on the injured this morning.","{actor_1} was seen sharing their ration with the children.","{actor_1} spent the evening tending to {actor_2}.","{actor_1} organized a small meal for those who could not cook for themselves.","Someone left a bundle of herbs by the door. Probably {actor_1}."]'
		]
	)


func _seed_roles() -> void:
	var rows := [
		["medic", "Medic", "Provides medical care, offsets daily health decay", '["medicine"]', '{"health":0.08}', 1],
		["farmer", "Farmer", "Produces food, increases daily food production", '["farming"]', '{"food_production":0.5}', 2],
		["guard", "Guard", "Maintains security, offsets daily security decay", '["combat"]', '{"security":0.06}', 2],
		["teacher", "Teacher", "Teaches skills, increases daily knowledge gain", '["teaching"]', '{"knowledge":0.02}', 1],
		["scavenger", "Scavenger", "Gathers supplies, offsets daily resource drain", '[]', '{"resources":0.04}', 2],
		["builder", "Builder", "Enables construction events", '["engineering"]', '{"resources":0.02}', 1],
	]
	for r in rows:
		_library_db.query_with_bindings(
			"INSERT INTO roles (id, display_name, description, required_skills, stat_bonuses, max_slots) VALUES (?, ?, ?, ?, ?, ?);",
			r
		)


func _seed_community_types() -> void:
	var thresholds := '{"minor":30,"major":60,"dominant":80}'
	var rows := [
		["commonwealth", "The Commonwealth", "A community governed by collective decision.", '{"cohesion":0.1,"crisis_response":-0.1}',
			"Democracy survived the end of the world here. Every voice was heard, every burden shared. It was imperfect and slow and beautiful."],
		["bastion", "The Bastion", "A community built on defense and order.", '{"security":0.1,"morale":-0.05}',
			"Safety was the only god worth worshipping now. You built walls, gave orders, kept them alive. Whether they were free was a question nobody asked out loud."],
		["exchange", "The Exchange", "A community driven by trade and value.", '{"resources":0.1,"cohesion":-0.05}',
			"Everything had a price — even here, even now. The ledgers were balanced, the trade routes open, the community prosperous. What it cost in trust was a line item nobody added up."],
		["congregation", "The Congregation", "A community united by shared belief.", '{"morale":0.1,"knowledge":-0.05}',
			"They needed something to believe in, and you gave it to them. The faith was real, the comfort genuine, the unity absolute. The questions it silenced are harder to account for."],
		["kindred", "The Kindred", "A community bound by kinship and loyalty.", '{"cohesion":0.1}',
			"Blood and bond. They were yours and you were theirs and that was enough. The world outside barely existed. It would be a problem for someone else's descendants."],
		["archive", "The Archive", "A community dedicated to preserving knowledge.", '{"knowledge":0.1,"security":-0.05}',
			"The library did not burn this time. You saved what could be saved — the how and the why and the what-comes-next. The people were the vessel. The knowledge was the cargo."],
		["rewilded", "The Rewilded", "A community that returned to the land.", '{"food":0.1,"health":-0.05}',
			"You let the old world go, all of it. No machines, no hierarchy, no debt to a civilization that had already failed you. It was hard. It was honest. It was enough."],
		["throne", "The Throne", "A community ruled by a single will.", '{"stability":0.1,"cohesion":-0.1}',
			"You decided, and it was done. No committees, no votes, no delay while people argued about what was obvious. The community was an extension of your will. The question of what comes after you was one you kept meaning to answer."],
	]
	for r in rows:
		_library_db.query_with_bindings(
			"INSERT INTO community_types (id, display_name, description, roll_modifiers, reveal_text, thresholds) VALUES (?, ?, ?, ?, ?, ?);",
			[r[0], r[1], r[2], r[3], r[4], thresholds]
		)


func _seed_tier1_events() -> void:
	# Skip if events already seeded
	_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 1;")
	if _library_db.query_result.size() > 0 and int(_library_db.query_result[0].get("cnt", 0)) >= 50:
		return

	var actor_1_only := '{"actor_1":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'
	var actor_1_and_2 := '{"actor_1":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true},"actor_2":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'

	# --- Group A: Universal Daily Life (20 events) ---
	var group_a := [
		["amb_work_morning", "{actor_1} worked through the morning without complaint.", "{}", actor_1_only, 3, 1.0, null],
		["amb_talking", "{actor_1} was seen talking with {actor_2} near {building}.", "{}", actor_1_and_2, 2, 1.0, null],
		["amb_laughter", "Laughter from {building} tonight. It was good to hear.", "{}", null, 5, 0.8, null],
		["amb_afternoon", "{actor_1} spent the afternoon in {building}, keeping busy.", "{}", actor_1_only, 2, 1.0, null],
		["amb_repair_anon", "Someone repaired a section of the outer perimeter. Nobody claimed credit.", "{}", null, 7, 0.7, null],
		["amb_disagreement_resolved", "{actor_1} and {actor_2} settled a small disagreement before it became anything more.", "{}", actor_1_and_2, 4, 0.9, null],
		["amb_quiet_day", "A quiet day. {actor_1} worked. Others rested. The world outside stayed away.", "{}", actor_1_only, 4, 0.8, null],
		["amb_early_riser", "{actor_1} was up before dawn again.", "{}", actor_1_only, 3, 1.0, null],
		["amb_gathered", "The community gathered briefly near {building}. No agenda. Just people.", "{}", null, 6, 0.7, null],
		["amb_teaching", "{actor_1} was explaining something to a small group near {building}.", "{}", actor_1_only, 5, 0.8, null],
		["amb_stores_check", "{actor_1} checked the stores and said nothing. Their expression said enough.", "{}", actor_1_only, 4, 1.0, null],
		["amb_quiet_incident", "The day passed without incident. For once.", "{}", null, 6, 0.6, null],
		["amb_fix_unnoticed", "{actor_1} fixed something nobody else had noticed was broken.", "{}", actor_1_only, 5, 0.9, null],
		["amb_brief_argument", "There was a brief argument near {building}. It passed.", "{}", null, 3, 1.0, null],
		["amb_watching", "{actor_1} was seen watching the treeline for a long time.", "{}", actor_1_only, 4, 0.9, null],
		["amb_late_night", "Two people sat together in {building} long after dark. Nobody asked why.", "{}", null, 7, 0.7, null],
		["amb_rotation", "{actor_1} organized a small work rotation for the afternoon.", "{}", actor_1_only, 5, 0.8, null],
		["amb_cooking", "Smoke from {building} in the evening — someone was cooking something that actually smelled good.", "{}", null, 5, 0.9, null],
		["amb_bad_sleep", "Nobody slept well. It showed in the morning.", "{}", null, 4, 0.8, null],
		["amb_herbs", "Someone left a small bundle of herbs near the door. Nobody claimed them.", "{}", null, 7, 0.6, null],
	]

	for e in group_a:
		_insert_tier1_event(e[0], e[1], "ambient", e[2], e[3], e[4], e[5], e[6])

	# --- Group B: Stat-Gated Mood Reflectors (10 events) ---
	var group_b := [
		["amb_morale_brittle", "Morale is brittle. People are going through the motions.", '{"required_state_tags":["morale_low"]}', null, 5, 1.0],
		["amb_breakdown", "{actor_1} broke down near {building}. Others gave them space.", '{"required_state_tags":["morale_critical"]}', actor_1_only, 7, 1.0],
		["amb_mood_lifted", "The mood has lifted slightly. Nothing specific — just a feeling.", '{"required_state_tags":["morale_good"]}', null, 6, 0.8],
		["amb_coughing", "Several people are coughing. It may be nothing.", '{"required_state_tags":["health_low"]}', null, 5, 1.0],
		["amb_injured_struggling", "The injured are being tended to. It is not going well.", '{"required_state_tags":["health_critical"]}', null, 4, 1.0],
		["amb_food_anxiety", "{actor_1} checked the stores again. The numbers haven't changed.", '{"required_state_tags":["food_low"]}', actor_1_only, 4, 1.0],
		["amb_rationing_tension", "Rationing has changed how people relate to each other. Not for the better.", '{"required_state_tags":["food_low"]}', null, 6, 0.9],
		["amb_looking_over_shoulder", "People are looking over their shoulders more than usual.", '{"required_state_tags":["security_low"]}', null, 5, 1.0],
		["amb_steady_feeling", "There's a steadiness to people lately. Things feel more organized.", '{"required_state_tags":["stability_good"]}', null, 7, 0.7],
		["amb_fractured", "The community feels fractured. Groups eat apart. Work alone.", '{"required_state_tags":["cohesion_low"]}', null, 5, 1.0],
	]

	for e in group_b:
		_insert_tier1_event(e[0], e[1], "ambient", e[2], e[3], e[4], e[5], null)

	# --- Group C: Seasonal (8 events) ---
	var group_c := [
		["amb_winter_cold", "The first real cold of the season. Everyone felt it.", '{"required_state_tags":["season_winter"]}', null, 14, 1.0, '["winter"]'],
		["amb_winter_snow", "Snow overnight. The world is quieter and harder.", '{"required_state_tags":["season_winter"]}', null, 7, 1.0, '["winter"]'],
		["amb_winter_morning", "{actor_1} was the first one up on a grey winter morning.", '{"required_state_tags":["season_winter"]}', actor_1_only, 5, 0.9, '["winter"]'],
		["amb_spring_days", "The days are getting longer. It lifts the mood in ways that are hard to explain.", '{"required_state_tags":["season_spring"]}', null, 10, 0.9, '["spring"]'],
		["amb_spring_rain", "Rain again. But the ground needs it.", '{"required_state_tags":["season_spring"]}', null, 5, 1.0, '["spring"]'],
		["amb_summer_heat", "Summer heat is wearing on everyone. Work slows in the afternoon.", '{"required_state_tags":["season_summer"]}', null, 7, 1.0, '["summer"]'],
		["amb_fall_harvest", "The harvest is underway. Everyone is working.", '{"required_state_tags":["season_fall"]}', null, 10, 1.0, '["fall"]'],
		["amb_fall_smell", "There's that autumn smell in the air. Another season passing.", '{"required_state_tags":["season_fall"]}', null, 10, 0.8, '["fall"]'],
	]

	for e in group_c:
		_insert_tier1_event(e[0], e[1], "ambient", e[2], e[3], e[4], e[5], e[6])

	# --- Group D: Role & Skill Specific (7 events) ---
	var actor_medicine := '{"actor_1":{"required_skills":["medicine"],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'
	var actor_farming := '{"actor_1":{"required_skills":["farming"],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'
	var actor_combat := '{"actor_1":{"required_skills":["combat"],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'
	var actor_teaching := '{"actor_1":{"required_skills":["teaching"],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'
	var actor_scavenger_role := '{"actor_1":{"required_skills":[],"required_personality":null,"required_role":"scavenger","excluded_flags":[],"prefer_not_recent":true}}'

	_insert_tier1_event("amb_medic_working", "{actor_1} {actor_1_modifier} spent the morning tending to the sick.", "ambient", '{"required_state_tags":["has_skill_medicine"]}', actor_medicine, 4, 1.0, null)
	_insert_tier1_event("amb_farmer_early", "{actor_1} was out in the field before anyone else was awake.", "ambient", '{"required_state_tags":["has_skill_farming"]}', actor_farming, 4, 1.0, null)
	_insert_tier1_event("amb_guard_perimeter", "{actor_1} walked the perimeter at dusk, checking every section.", "ambient", '{"required_state_tags":["has_skill_combat"]}', actor_combat, 4, 1.0, null)
	_insert_tier1_event("amb_teacher_group", "{actor_1} was explaining something to a small group near {building}. They looked like they were actually learning.", "ambient", '{"required_state_tags":["has_skill_teaching"]}', actor_teaching, 5, 1.0, null)
	_insert_tier1_event("amb_no_medic", "The medic role sits empty. People are treating their own injuries as best they can.", "ambient", '{"required_state_tags":["role_vacant_medic"]}', null, 7, 1.0, null)
	_insert_tier1_event("amb_no_scavenger", "Nobody has scouted the surrounding area in days. Supplies are what they are.", "ambient", '{"required_state_tags":["role_vacant_scavenger"]}', null, 7, 0.9, null)
	_insert_tier1_event("amb_scavenger_return", "{actor_1} came back from the surrounding area with something useful.", "ambient", "{}", actor_scavenger_role, 3, 1.0, null)

	# --- Group E: Lifecycle Follow-Ups (5 events) ---
	_insert_tier1_event("amb_grief_visible", "{actor_1} has been quiet since the recent loss. The grief sits on them visibly.", "ambient", '{"required_state_tags":["recent_death"]}', actor_1_only, 5, 1.0, null)
	_insert_tier1_event("amb_baby_heard", "The new baby's crying can be heard from {building}. Some people smile at it.", "ambient", '{"required_state_tags":["recent_birth"]}', null, 4, 0.9, null)
	_insert_tier1_event("amb_empty_bunk", "The empty space where someone slept is still there. Nobody has moved anything.", "ambient", '{"required_state_tags":["recent_death"]}', null, 7, 0.8, null)
	_insert_tier1_event("amb_newcomer_observed", "There's a new face among them. The others are still deciding what to think.", "ambient", '{"required_state_tags":["newcomers_present"]}', null, 6, 0.9, null)
	_insert_tier1_event("amb_processing_loss", "People are still processing the loss. Work continues because it must.", "ambient", '{"required_state_tags":["recent_death"]}', actor_1_only, 6, 1.0, null)


func _insert_tier1_event(id: String, desc_template: String, category: String, eligibility, actor_req, cooldown_days: int, weight: float, seasonal_tags) -> void:
	_library_db.query_with_bindings(
		"INSERT INTO events (id, tier, category, title, eligibility, description_template, actor_requirements, choices, chain_id, chain_stage, chain_memory_schema, cooldown_days, exclusion_group, max_occurrences, content_tags, seasonal_tags, weight) VALUES (?, 1, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, ?, NULL, NULL, NULL, ?, ?);",
		[id, category, id, eligibility if eligibility != null else "{}", desc_template, actor_req, cooldown_days, seasonal_tags, weight]
	)
