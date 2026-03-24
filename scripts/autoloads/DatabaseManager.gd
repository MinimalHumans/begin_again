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
		# Ensure events are seeded (added in Phase 2b/2c)
		_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 1;")
		if _library_db.query_result.size() == 0 or int(_library_db.query_result[0].get("cnt", 0)) < 50:
			_seed_tier1_events()
		_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 2;")
		if _library_db.query_result.size() == 0 or int(_library_db.query_result[0].get("cnt", 0)) < 20:
			_seed_tier2_events()

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
	_seed_tier2_events()


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


func _seed_tier2_events() -> void:
	_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 2;")
	if _library_db.query_result.size() > 0 and int(_library_db.query_result[0].get("cnt", 0)) >= 20:
		return

	var a12 := '{"actor_1":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true},"actor_2":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'
	var a1 := '{"actor_1":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'

	# Event 1: Rationing Dispute
	_insert_tier2_event("tier2_rationing_dispute", "Rationing Dispute", "interpersonal", "{}", a12, 14, 1.0, null, null,
		'{actor_1} and {actor_2} got into a heated argument over rations. {actor_1} says the portions are not fair. {actor_2} says everyone gets the same. Both have supporters.',
		'[{"id":"a","text_template":"Hear both sides and make a ruling.","immediate_effects":{},"community_scores":{"commonwealth":2,"throne":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"stability","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"Your ruling satisfied nobody. Both parties left angrier. Morale took a hit.","effects":{"morale":-6,"cohesion":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The argument cooled but did not resolve. People are watching to see if it flares again.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"You threaded the needle. Both parties accepted the ruling. The group respected the process.","effects":{"morale":4,"cohesion":2},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Side with {actor_1}. Make it clear.","immediate_effects":{"stability":-3},"community_scores":{"throne":2,"kindred":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"bad":{"text":"The supporters of {actor_2} are furious. A schism is forming.","effects":{"cohesion":-8,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"{actor_2} backed down but has not forgotten. Watch that one.","effects":{"cohesion":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"Your decisiveness settled the matter. {actor_2} grumbled but fell in line.","effects":{"stability":3,"morale":2},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Give everyone slightly more for the next few days. Defuse it with food.","immediate_effects":{"food":-8,"morale":4},"community_scores":{"commonwealth":1,"exchange":-1},"roll":{"relevant_stats":[{"stat":"food","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"People noticed the food drop. Now they are worried about supplies on top of everything else.","effects":{"morale":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The argument stopped. Nobody is happy but nobody is shouting.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"The tension broke. A few extra calories was all it took.","effects":{"morale":3,"cohesion":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 2: Injured Stranger
	_insert_tier2_event("tier2_injured_stranger", "Injured Stranger", "external", "{}", null, 20, 1.0, null, null,
		'A stranger appeared at the edge of the settlement — alone, injured, and unable to travel. They say they have been alone since the beginning. They are asking to stay.',
		'[{"id":"a","text_template":"Bring them in. Treat their injuries.","immediate_effects":{"morale":3},"community_scores":{"commonwealth":2,"congregation":1,"kindred":-1},"roll":{"relevant_stats":[{"stat":"health","weight":0.8},{"stat":"resources","weight":0.4}],"base_value":0.2,"context_bonuses":[{"condition":"stat_above:health:40","bonus":0.2}]},"outcomes":{"bad":{"text":"The injuries the stranger had were worse than they looked. They did not survive the week. The effort cost resources and lifted nobody is spirits.","effects":{"health":-4,"resources":-5,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"They survived and recovered slowly. Another mouth to feed, another pair of hands eventually.","effects":{"resources":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"They recovered well. Grateful and capable — a real addition to the community.","effects":{"morale":4},"flags_set":["newcomer_joined"],"flags_cleared":[]}},"deferred":{"delay_min_days":14,"delay_max_days":30,"log_hints":[{"day_offset":7,"text":"{actor_1} is still recovering. Hard to tell which way it is going."},{"day_offset":14,"text":"The community is watching {actor_1} progress closely."}],"check":{"relevant_stats":[{"stat":"health","weight":1.2}],"base_value":0.1,"context_bonuses":[{"condition":"stat_above:health:50","bonus":0.3}]},"outcomes":{"bad":{"text":"{actor_1} never fully recovered. They left quietly one morning before anyone was up.","effects":{"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"{actor_1} recovered enough to contribute in small ways. Not what anyone hoped, but something.","effects":{"morale":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"{actor_1} made a full recovery and has become a reliable member of the community.","effects":{"morale":5,"cohesion":3},"flags_set":[],"flags_cleared":[]}}}},{"id":"b","text_template":"Give them what they need to travel. Wish them well.","immediate_effects":{"resources":-5},"community_scores":{"exchange":1,"bastion":1},"roll":{"relevant_stats":[{"stat":"resources","weight":0.5}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"You watched them go. Later you heard they did not make it far.","effects":{"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"They took the supplies and left. You will never know what became of them.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"They were grateful. As they left they mentioned a cache of medical supplies two days east.","effects":{"resources":8,"knowledge":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"The needs of the community come first. Turn them away.","immediate_effects":{"morale":-4},"community_scores":{"bastion":2,"throne":1,"commonwealth":-2},"roll":{"relevant_stats":[{"stat":"morale","weight":0.5},{"stat":"cohesion","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Some community members saw what happened. The mood is darker.","effects":{"morale":-5,"cohesion":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Nobody argued out loud. But some people are quieter now.","effects":{"cohesion":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The decision was accepted. Hard choices are part of survival. The community understands that.","effects":{"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 3: Medical Emergency
	_insert_tier2_event("tier2_medical_emergency", "Medical Emergency", "health", "{}", a1, 10, 1.0, null, null,
		'{actor_1} collapsed this morning. Fever, unable to stand. Without proper treatment, they could deteriorate fast.',
		'[{"id":"a","text_template":"Use whatever medical supplies remain.","immediate_effects":{"resources":-8},"community_scores":{"commonwealth":1,"congregation":1},"roll":{"relevant_stats":[{"stat":"health","weight":1.0}],"base_value":0.3,"context_bonuses":[{"condition":"stat_above:health:50","bonus":0.3}]},"outcomes":{"bad":{"text":"The supplies helped but were not enough. {actor_1} is bedridden and deteriorating.","effects":{"health":-6},"flags_set":["actor_1:sick"],"flags_cleared":[]},"mixed":{"text":"{actor_1} stabilised. They will need rest but should recover.","effects":{"health":-2},"flags_set":["actor_1:injured"],"flags_cleared":[]},"good":{"text":"{actor_1} responded well to treatment. Back on their feet within days.","effects":{"health":3,"morale":4},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Isolate {actor_1} and watch. Do not waste supplies yet.","immediate_effects":{},"community_scores":{"archive":1,"bastion":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"health","weight":0.5}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} worsened during the wait. The illness spread to two others.","effects":{"health":-10,"morale":-5},"flags_set":["actor_1:sick"],"flags_cleared":[]},"mixed":{"text":"{actor_1} neither improved nor worsened. The illness seems contained.","effects":{"health":-3},"flags_set":["actor_1:injured"],"flags_cleared":[]},"good":{"text":"The illness broke on its own. {actor_1} recovered without supplies. The community breathed again.","effects":{"morale":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Ask for someone to sit with {actor_1} around the clock.","immediate_effects":{"morale":2},"community_scores":{"commonwealth":2,"kindred":2},"roll":{"relevant_stats":[{"stat":"morale","weight":0.6},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"Nobody had the capacity. {actor_1} was left largely alone and felt it.","effects":{"morale":-5,"cohesion":-4},"flags_set":["actor_1:sick"],"flags_cleared":[]},"mixed":{"text":"Someone stayed. It helped the spirits of {actor_1} if not their condition.","effects":{"morale":2},"flags_set":["actor_1:injured"],"flags_cleared":[]},"good":{"text":"Several people took shifts. {actor_1} felt the care of the community and recovered stronger for it.","effects":{"health":4,"morale":5,"cohesion":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 4: Scavenging Run
	_insert_tier2_event("tier2_scavenging_opportunity", "Scavenging Run", "resource", "{}", a1, 12, 1.0, null, null,
		'{actor_1} has spotted what looks like an untouched supply cache near {building}. It could be significant. It could also be a trap, or already picked clean.',
		'[{"id":"a","text_template":"Send {actor_1} with one other. Careful and quiet.","immediate_effects":{},"community_scores":{"archive":1,"exchange":1},"roll":{"relevant_stats":[{"stat":"security","weight":0.8},{"stat":"knowledge","weight":0.4}],"base_value":0.2,"context_bonuses":[{"condition":"actor_has_skill:combat","bonus":0.3}]},"outcomes":{"bad":{"text":"The team walked into an ambush. They came back empty-handed and shaken.","effects":{"security":-6,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The cache was mostly picked over. They brought back something, not much.","effects":{"resources":8},"flags_set":[],"flags_cleared":[]},"good":{"text":"A solid haul. Enough to ease the immediate pressure.","effects":{"resources":18,"morale":3},"flags_set":[],"flags_cleared":[]}},"deferred":{"delay_min_days":5,"delay_max_days":14,"log_hints":[{"day_offset":3,"text":"{actor_1} is still cataloguing what was brought back."}],"check":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"resources","weight":0.5}],"base_value":0.3,"context_bonuses":[{"condition":"actor_has_skill:engineering","bonus":0.3}]},"outcomes":{"bad":{"text":"Most of what was recovered turned out to be unusable. The real haul was much smaller.","effects":{"resources":-6,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The supplies were what they were — useful, nothing remarkable.","effects":{"resources":5},"flags_set":[],"flags_cleared":[]},"good":{"text":"Hidden among the haul was something unexpected. Technical manuals. Intact tools. Real value.","effects":{"resources":10,"knowledge":5},"flags_set":[],"flags_cleared":[]}}}},{"id":"b","text_template":"Take a larger group. Overwhelm any opposition.","immediate_effects":{"security":-4},"community_scores":{"bastion":2,"throne":1},"roll":{"relevant_stats":[{"stat":"security","weight":1.0}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The group was seen leaving. Someone followed them back.","effects":{"security":-8,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"No opposition but the noise attracted attention. Worth it, probably.","effects":{"resources":15},"flags_set":[],"flags_cleared":[]},"good":{"text":"Clean sweep. A real score.","effects":{"resources":25,"morale":4},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Leave it. The risk is not worth it right now.","immediate_effects":{},"community_scores":{"rewilded":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.5}],"base_value":0.5,"context_bonuses":[]},"outcomes":{"bad":{"text":"Someone else hit the cache. You watched them carry it away.","effects":{"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A cautious choice. The opportunity passed.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"Turned out the cache was booby-trapped. You heard the explosion from a distance.","effects":{"morale":3,"security":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 5: New Arrival
	_insert_tier2_event("tier2_new_arrival", "New Arrival", "external", '{"stat_above":{"reputation":45}}', null, 21, 1.0, null, null,
		'A small group — three people — found you. They have been surviving alone for weeks and they are asking to join. They look capable but you do not know them.',
		'[{"id":"a","text_template":"Open the doors. More hands, more strength.","immediate_effects":{"morale":3},"community_scores":{"commonwealth":3,"congregation":1},"roll":{"relevant_stats":[{"stat":"resources","weight":0.6},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"One of them had a hidden illness. Health dropped before anyone noticed.","effects":{"health":-8,"resources":-6},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"They settled in. Three new mouths, three new pairs of hands. The balance is unclear.","effects":{"resources":-4},"flags_set":[],"flags_cleared":[]},"good":{"text":"A good addition. Skills the community was missing, and they pulled their weight from day one.","effects":{"morale":4,"cohesion":2,"knowledge":3},"flags_set":[],"flags_cleared":[]}},"deferred":{"delay_min_days":21,"delay_max_days":45,"log_hints":[{"day_offset":10,"text":"The newcomers are settling in. Hard to say yet whether that is a good thing."},{"day_offset":25,"text":"People have formed opinions about the newcomers. Not all of them good."}],"check":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"morale","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"One of the newcomers has been causing friction — quietly, persistently. Cohesion has suffered.","effects":{"cohesion":-7,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The newcomers integrated without incident. They are part of the community now, for better or worse.","effects":{"cohesion":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The newcomers brought skills and energy the community did not know it needed. A genuine strengthening.","effects":{"cohesion":5,"morale":4,"knowledge":4},"flags_set":[],"flags_cleared":[]}}}},{"id":"b","text_template":"Ask questions. Verify their story. Decide based on that.","immediate_effects":{},"community_scores":{"archive":2,"exchange":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.6},{"stat":"stability","weight":0.6}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The interview revealed inconsistencies. They left angry. Word may get around.","effects":{"reputation":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Nothing alarming turned up. You accepted two of the three.","effects":{"morale":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"Thorough vetting paid off. You took in exactly who you needed.","effects":{"morale":3,"stability":3,"knowledge":4},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"You cannot absorb more people right now.","immediate_effects":{"morale":-3},"community_scores":{"bastion":2,"exchange":1,"commonwealth":-2},"roll":{"relevant_stats":[{"stat":"morale","weight":0.5},{"stat":"stability","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Some of your people disagreed loudly with the decision.","effects":{"cohesion":-5,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A hard call. Most accepted it.","effects":{"morale":-1},"flags_set":[],"flags_cleared":[]},"good":{"text":"Turned out to be the right read — you later heard the group had serious problems elsewhere.","effects":{"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 6: Work Refusal
	_insert_tier2_event("tier2_work_refusal", "Work Refusal", "interpersonal", "{}", a1, 14, 1.0, null, null,
		'{actor_1} is refusing their assigned duties, citing exhaustion. Others are watching to see what happens.',
		'[{"id":"a","text_template":"Grant {actor_1} a day of rest. Everyone needs it sometimes.","immediate_effects":{"morale":2},"community_scores":{"commonwealth":2,"kindred":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Others saw the rest day and wanted the same. Productivity collapsed for a week.","effects":{"resources":-5,"stability":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"{actor_1} rested and returned to work. A few grumbles, nothing more.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"{actor_1} came back refreshed and grateful. The gesture was noticed by everyone.","effects":{"morale":4,"cohesion":2},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Insist. Everyone works. No exceptions.","immediate_effects":{"stability":2},"community_scores":{"throne":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} worked but resentment is building. You can feel it.","effects":{"morale":-6,"cohesion":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"{actor_1} complied without further argument. The message was received.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The firmness was respected. People understand that discipline keeps them alive.","effects":{"stability":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Reassign {actor_1} to lighter duties.","immediate_effects":{},"community_scores":{"commonwealth":1,"archive":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.5},{"stat":"morale","weight":0.5}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The lighter assignment was seen as favouritism. Others are unhappy.","effects":{"cohesion":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A compromise. Nobody is thrilled but nobody is angry.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"A pragmatic solution. {actor_1} contributed where they could and recovered naturally.","effects":{"morale":2,"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 7: Rule Proposal
	_insert_tier2_event("tier2_rule_proposal", "Rule Proposal", "governance", "{}", a1, 18, 1.0, null, null,
		'{actor_1} proposes a formal rule about resource sharing: everyone contributes equally and receives equally. It is a direct challenge to any informal hierarchies.',
		'[{"id":"a","text_template":"Accept the proposal. Formalise equal sharing.","immediate_effects":{},"community_scores":{"commonwealth":3,"archive":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"stability","weight":0.5}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The rule created more arguments than it resolved. Who decides what is equal?","effects":{"cohesion":-5,"stability":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The rule was adopted. Early days. People are testing its limits.","effects":{"stability":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"A sense of fairness settled over the community. People felt heard.","effects":{"morale":4,"cohesion":4,"stability":2},"flags_set":[],"flags_cleared":[]}},"deferred":{"delay_min_days":28,"delay_max_days":56,"log_hints":[{"day_offset":14,"text":"The new rule is being followed. Mostly."},{"day_offset":35,"text":"There has been some grumbling about the new rule. Nothing serious yet."}],"check":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[{"condition":"stat_above:stability:60","bonus":0.3}]},"outcomes":{"bad":{"text":"The rule has created more resentment than order. It is being quietly ignored by half the community.","effects":{"stability":-6,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The rule became background. Not transformative, but not harmful. Part of the fabric now.","effects":{"stability":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The rule has become a reference point. People cite it when resolving disputes. Governance feels more real.","effects":{"stability":7,"cohesion":4},"flags_set":[],"flags_cleared":[]}}}},{"id":"b","text_template":"Reject it. The current system works.","immediate_effects":{},"community_scores":{"throne":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} and their supporters feel dismissed. A faction is forming.","effects":{"cohesion":-6,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The proposal died quietly. Some resentment lingers.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"People accepted the decision. Stability is its own kind of fairness.","effects":{"stability":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Table it. Discuss it properly when things are calmer.","immediate_effects":{},"community_scores":{"archive":1,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.6},{"stat":"morale","weight":0.4}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The delay was seen as a soft rejection. Trust in the process dropped.","effects":{"morale":-3,"stability":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"People accepted the delay. The conversation will come back eventually.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"A wise deferral. When the discussion happened later, cooler heads prevailed.","effects":{"stability":3,"cohesion":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 8: Theft Accusation
	_insert_tier2_event("tier2_theft_accusation", "Theft Accusation", "interpersonal", "{}", a12, 14, 1.0, null, null,
		'{actor_1} accuses {actor_2} of stealing from the stores. {actor_2} denies it. There is no proof either way but the accusation is out there now.',
		'[{"id":"a","text_template":"Investigate. Check the stores and question both sides.","immediate_effects":{},"community_scores":{"commonwealth":2,"archive":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.6},{"stat":"stability","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The investigation found nothing conclusive but stirred up more suspicion.","effects":{"cohesion":-5,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Inconclusive. The accusation hangs in the air. Both parties are unhappy.","effects":{"cohesion":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The investigation cleared {actor_2} and restored confidence in the stores.","effects":{"cohesion":3,"stability":3},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Side with {actor_1}. Restrict access for {actor_2} to supplies.","immediate_effects":{"stability":2},"community_scores":{"bastion":2,"throne":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_2} was innocent. The punishment was unjust and everyone knows it.","effects":{"morale":-6,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The restriction was accepted grudgingly. Nobody is sure it was right.","effects":{"morale":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"Swift action. Whether right or wrong, the message was clear: theft will not be tolerated.","effects":{"security":3,"stability":2},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Dismiss the accusation. Without proof, there is nothing to act on.","immediate_effects":{},"community_scores":{"commonwealth":1,"rewilded":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"More things went missing. {actor_1} was right and everyone knows you did nothing.","effects":{"resources":-8,"stability":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The matter faded. Neither party is satisfied.","effects":{"cohesion":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The tension dissipated. Sometimes the best response is no response.","effects":{"morale":2,"cohesion":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 9: Outside Contact
	_insert_tier2_event("tier2_outside_contact", "Outside Contact", "external", "{}", null, 25, 1.0, null, null,
		'A distant signal — someone is trying to communicate. It could be another settlement, or it could be bait. The signal is coming from the east.',
		'[{"id":"a","text_template":"Send a small team to investigate the signal.","immediate_effects":{},"community_scores":{"exchange":2,"archive":1},"roll":{"relevant_stats":[{"stat":"security","weight":0.7},{"stat":"knowledge","weight":0.5}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The team found nothing but wasted two days and came back uneasy.","effects":{"security":-4,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Another group of survivors, cautious but not hostile. No trade yet but contact was made.","effects":{"reputation":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"A friendly settlement. They are willing to trade. This changes the calculus.","effects":{"reputation":6,"morale":4,"resources":8},"flags_set":["outside_contact_made"],"flags_cleared":[]}},"deferred":{"delay_min_days":30,"delay_max_days":60,"log_hints":[{"day_offset":15,"text":"The contact from outside has been on people minds. Expectations are building."},{"day_offset":40,"text":"Still no follow-up from the outside contact. People are starting to wonder."}],"check":{"relevant_stats":[{"stat":"reputation","weight":0.8},{"stat":"resources","weight":0.5}],"base_value":0.1,"context_bonuses":[{"condition":"stat_above:reputation:55","bonus":0.4}]},"outcomes":{"bad":{"text":"The contact turned out to be hostile reconnaissance. A raid followed. The community was not prepared.","effects":{"security":-10,"resources":-8,"morale":-6},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Nothing came of the contact. A false start. The world outside remains as silent as ever.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The contact proved genuine. A trade connection. Small for now, but real.","effects":{"reputation":8,"resources":10,"morale":5},"flags_set":[],"flags_cleared":[]}}}},{"id":"b","text_template":"Respond to the signal but do not reveal your location.","immediate_effects":{},"community_scores":{"bastion":2,"exchange":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The signal went dead. You are not sure what that means.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A cautious exchange of information. Neither side trusts the other yet.","effects":{"knowledge":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"They shared useful intelligence about the surrounding area without compromising your position.","effects":{"knowledge":5,"security":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Ignore it. Signals mean attention and attention means danger.","immediate_effects":{},"community_scores":{"bastion":2,"rewilded":1},"roll":{"relevant_stats":[{"stat":"security","weight":0.5}],"base_value":0.5,"context_bonuses":[]},"outcomes":{"bad":{"text":"The signal kept coming. Others wanted to respond. Your caution looks like fear.","effects":{"morale":-4,"stability":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The signal faded. The world outside remains unknown.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"Later reports suggest the signal was a lure. Your caution may have saved lives.","effects":{"security":3,"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 10: Religious Gathering
	_insert_tier2_event("tier2_religious_gathering", "Religious Gathering", "social", "{}", a1, 18, 1.0, null, null,
		'{actor_1} has started holding informal prayer meetings in the evenings. A growing number of people attend. Some find comfort. Others are uneasy.',
		'[{"id":"a","text_template":"Encourage it. People need something to believe in.","immediate_effects":{"morale":3},"community_scores":{"congregation":3,"kindred":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The gatherings became exclusive. Those who do not attend feel judged.","effects":{"cohesion":-5,"morale":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The meetings continue. A source of comfort for some, irrelevant to others.","effects":{"morale":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The gatherings brought people together. A sense of shared purpose emerged.","effects":{"morale":5,"cohesion":4},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Allow it but keep it separate from community decisions.","immediate_effects":{},"community_scores":{"commonwealth":2,"archive":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.7},{"stat":"knowledge","weight":0.4}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The boundary was hard to maintain. Faith and governance are tangling.","effects":{"stability":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A reasonable compromise. The meetings continue in their own space.","effects":{"morale":1},"flags_set":[],"flags_cleared":[]},"good":{"text":"Clear separation worked well. People found comfort without it becoming political.","effects":{"morale":3,"stability":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Discourage it. Unity means one identity, not factions.","immediate_effects":{"morale":-3},"community_scores":{"throne":2,"bastion":1,"congregation":-2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The crackdown backfired. Meetings moved underground and resentment grew.","effects":{"cohesion":-6,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The meetings stopped. Some people are quieter now.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"People accepted the decision. The community focused on practical matters instead.","effects":{"stability":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 11: Knowledge Request
	_insert_tier2_event("tier2_skill_request", "Knowledge Request", "knowledge", "{}", a1, 16, 1.0, null, null,
		'{actor_1} wants time off regular duties to document their expertise — writing down techniques, procedures, knowledge that only they carry. They say it is important for the future of the community.',
		'[{"id":"a","text_template":"Grant the time. Knowledge preservation matters.","immediate_effects":{},"community_scores":{"archive":3,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"stability","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The documentation was incomplete and the time cost was noticed. Others want the same deal.","effects":{"stability":-3,"resources":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Some useful notes were produced. Whether anyone reads them remains to be seen.","effects":{"knowledge":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"Valuable knowledge captured. the expertise of {actor_1} is now accessible to everyone.","effects":{"knowledge":6,"morale":3},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Deny it. Everyone works their share, no exceptions.","immediate_effects":{},"community_scores":{"throne":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} is resentful. Their motivation has dropped noticeably.","effects":{"morale":-4,"knowledge":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"{actor_1} accepted the decision. The knowledge stays in their head for now.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"The refusal was understood. Practical work takes priority and everyone agrees.","effects":{"stability":2},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Compromise — {actor_1} can document in the evenings after duties.","immediate_effects":{},"community_scores":{"archive":1,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.5},{"stat":"knowledge","weight":0.5}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The extra work exhausted {actor_1}. Both duties and documentation suffered.","effects":{"health":-3,"morale":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Slow progress, but progress. {actor_1} is tired but committed.","effects":{"knowledge":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"It worked. The documentation is solid and {actor_1} inspired others to do the same.","effects":{"knowledge":5,"morale":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 12: Child in Danger
	_insert_tier2_event("tier2_child_danger", "Child in Danger", "health", '{"population_min":5}', null, 20, 1.0, null, null,
		'A child wandered outside the perimeter. They were found quickly but the incident has shaken people. How do we make sure this does not happen again?',
		'[{"id":"a","text_template":"Assign a dedicated watcher for the children.","immediate_effects":{},"community_scores":{"kindred":3,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"morale","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Nobody could be spared. The rotation fell apart within days.","effects":{"morale":-4,"stability":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A watcher was assigned. It works but pulls someone from other duties.","effects":{"security":2,"morale":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The arrangement worked well. Children are safer and parents are calmer.","effects":{"morale":5,"cohesion":3,"security":2},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Strengthen the perimeter. Make it harder to wander out.","immediate_effects":{"resources":-6},"community_scores":{"bastion":2,"throne":1},"roll":{"relevant_stats":[{"stat":"resources","weight":0.8},{"stat":"security","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The reinforcement used materials needed elsewhere. And the children found another gap.","effects":{"resources":-4,"morale":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The perimeter is more secure. The children are safer, if less free.","effects":{"security":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"A practical improvement. The perimeter is stronger and the community feels more secure.","effects":{"security":5,"morale":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Talk to the parents. This is their responsibility.","immediate_effects":{},"community_scores":{"throne":1,"rewilded":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.6},{"stat":"stability","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The parents felt blamed. The community feels less united.","effects":{"cohesion":-5,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The message was received. Awkward, but the children are watched more closely.","effects":{"morale":-1},"flags_set":[],"flags_cleared":[]},"good":{"text":"The conversation went well. Parents organised their own watch system.","effects":{"cohesion":3,"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 13: Physical Altercation
	_insert_tier2_event("tier2_fight", "Physical Altercation", "interpersonal", "{}", a12, 12, 1.0, null, null,
		'{actor_1} and {actor_2} came to blows near {building}. It took three people to pull them apart. Both are bruised. The community is shaken.',
		'[{"id":"a","text_template":"Separate them. Enforce a cooling-off period.","immediate_effects":{},"community_scores":{"commonwealth":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"cohesion","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The separation bred resentment. Both sides are recruiting allies.","effects":{"cohesion":-6,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"They are apart. The anger has not gone but the violence has stopped.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The cooling period worked. Both came back calmer and the incident faded.","effects":{"stability":3,"cohesion":2},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Public accountability. Both answer for the violence.","immediate_effects":{"stability":2},"community_scores":{"bastion":2,"throne":2},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The public shaming went too far. Both are humiliated and the community feels uneasy.","effects":{"morale":-6,"cohesion":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The message was received. Violence has consequences. People are wary.","effects":{"morale":-2,"security":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"Clear, fair consequences. The community respects the boundary.","effects":{"stability":4,"security":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Let them sort it out themselves. Intervening makes it worse.","immediate_effects":{},"community_scores":{"rewilded":2,"kindred":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"It happened again. This time someone got hurt badly.","effects":{"health":-5,"cohesion":-6,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The situation resolved itself, messily. People are on edge.","effects":{"cohesion":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"They worked it out. Sometimes people need to handle things directly.","effects":{"cohesion":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 14: Supplies Spoiled
	_insert_tier2_event("tier2_supplies_spoiled", "Supplies Spoiled", "resource", "{}", null, 16, 1.0, null, null,
		'A portion of the food stores have spoiled. Moisture got in, or the containers failed. Either way, the loss is real and people are upset.',
		'[{"id":"a","text_template":"Reorganise all storage. Prevent this from happening again.","immediate_effects":{"food":-10},"community_scores":{"archive":2,"exchange":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.7},{"stat":"resources","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The reorganisation revealed more spoilage. The actual loss is worse than thought.","effects":{"food":-6,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Storage is improved. The loss stings but it should not happen again.","effects":{"knowledge":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The overhaul was thorough. Better storage, better tracking. A crisis turned into an improvement.","effects":{"knowledge":4,"stability":3},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Ration immediately. Tighten food distribution.","immediate_effects":{"food":-10,"morale":-3},"community_scores":{"bastion":2,"throne":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The rationing hit morale hard. People are hungry and angry.","effects":{"morale":-5,"cohesion":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Tight belts all around. Nobody is happy but nobody is starving.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"Disciplined rationing stretched what remained. People respected the necessity.","effects":{"stability":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Send a scavenging party to replace the loss.","immediate_effects":{"food":-10,"security":-3},"community_scores":{"exchange":1,"rewilded":1},"roll":{"relevant_stats":[{"stat":"security","weight":0.6},{"stat":"resources","weight":0.5}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The party came back with almost nothing. A wasted risk.","effects":{"morale":-4,"security":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Partial replacement. Better than nothing.","effects":{"food":6},"flags_set":[],"flags_cleared":[]},"good":{"text":"A successful run. The loss is covered and then some.","effects":{"food":14,"morale":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 15: Severe Weather
	_insert_tier2_event("tier2_weather_warning", "Severe Weather", "environmental", "{}", null, 20, 1.0, null, null,
		'The sky has changed. Wind is picking up. Signs point to severe weather incoming within the day. There is time to prepare but not much.',
		'[{"id":"a","text_template":"All hands on reinforcement. Secure everything.","immediate_effects":{},"community_scores":{"bastion":2,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"resources","weight":0.8},{"stat":"security","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The storm was worse than expected. Significant damage despite preparations.","effects":{"resources":-10,"health":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Damage was limited. The preparations helped but the storm still took its toll.","effects":{"resources":-4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The preparations held. Minimal damage. People were impressed by the response.","effects":{"morale":4,"stability":3},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Shelter in place. Protect the people, not the structures.","immediate_effects":{},"community_scores":{"kindred":2,"congregation":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Everyone survived but the damage to structures and supplies was severe.","effects":{"resources":-12,"security":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Safe but shaken. The settlement took a beating.","effects":{"resources":-6},"flags_set":[],"flags_cleared":[]},"good":{"text":"The community huddled together and came through strong. The structures can be rebuilt.","effects":{"morale":4,"cohesion":4},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Split focus — some reinforce, others prepare medical and food stores.","immediate_effects":{},"community_scores":{"archive":1,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.6},{"stat":"knowledge","weight":0.5}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The split focus meant nothing was done well. Damage across the board.","effects":{"resources":-8,"health":-4,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A balanced approach. Some damage, some protection. Could have been worse.","effects":{"resources":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The balanced preparation paid off. Minimal losses on all fronts.","effects":{"stability":4,"morale":3,"knowledge":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 16: Morale Crisis
	_insert_tier2_event("tier2_morale_speech", "Morale Crisis", "social", '{"stat_below":{"morale":35}}', null, 20, 1.0, null, null,
		'The community mood has hit a low point. Arguments are more frequent. Work is slower. Something needs to change before this turns into something worse.',
		'[{"id":"a","text_template":"Call everyone together. Speak honestly about where things stand.","immediate_effects":{},"community_scores":{"commonwealth":3,"congregation":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"stability","weight":0.5}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The honesty backfired. People heard the problems and not the hope.","effects":{"morale":-5,"cohesion":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"People listened. Whether it helped is unclear. At least they know the truth.","effects":{"morale":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The speech hit the right note. People felt seen and recommitted.","effects":{"morale":8,"cohesion":4},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Organise a communal meal. Something to look forward to.","immediate_effects":{"food":-6},"community_scores":{"kindred":2,"congregation":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.6},{"stat":"food","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The meal was sparse and the forced cheer felt hollow.","effects":{"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"People ate together. It was not a celebration but it was not nothing.","effects":{"morale":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The meal brought genuine warmth. Laughter, stories, connection. A turning point.","effects":{"morale":7,"cohesion":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Crack down. Discipline will get people moving again.","immediate_effects":{"stability":3},"community_scores":{"throne":3,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"bad":{"text":"The crackdown made everything worse. People are afraid now, not just sad.","effects":{"morale":-8,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"People are moving but the fear is palpable. This is not sustainable.","effects":{"morale":-2,"stability":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The firm hand worked. Structure and discipline gave people something to hold onto.","effects":{"stability":4,"morale":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 17: Trade Offer
	_insert_tier2_event("tier2_trade_offer", "Trade Offer", "external", "{}", null, 22, 1.0, null, null,
		'A small group arrives at the perimeter. They are not asking to stay — they want to trade. They have medicine and want food.',
		'[{"id":"a","text_template":"Trade. Medicine is worth the food cost.","immediate_effects":{"food":-12},"community_scores":{"exchange":3,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"resources","weight":0.5},{"stat":"reputation","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The medicine was diluted. Barely useful. You overpaid.","effects":{"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A fair trade. Nothing spectacular. The medicine will help.","effects":{"health":5},"flags_set":[],"flags_cleared":[]},"good":{"text":"Excellent medicine and a promise to return. A trade route might be forming.","effects":{"health":8,"reputation":4},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Negotiate hard. Get more for less.","immediate_effects":{},"community_scores":{"exchange":2,"throne":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.6},{"stat":"stability","weight":0.5}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"Your negotiators pushed too hard. The traders left insulted.","effects":{"reputation":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A grudging deal. Less food given, less medicine received.","effects":{"food":-6,"health":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"Sharp negotiation. A great deal. The traders respect your position.","effects":{"food":-6,"health":7,"reputation":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Decline. You cannot afford to give up food.","immediate_effects":{},"community_scores":{"bastion":1,"rewilded":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.5}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"People who needed medicine watched the traders leave. The resentment is real.","effects":{"morale":-5,"health":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The traders moved on. The food stays but the medicine does not come.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"A cautious choice that preserved resources. The sick managed with what you had.","effects":{"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 18: Abandoned Homestead
	_insert_tier2_event("tier2_abandoned_cache", "Abandoned Homestead", "resource", "{}", a1, 15, 1.0, null, null,
		'{actor_1} found signs of a long-abandoned home while exploring. There might be useful supplies inside, but the structure does not look stable.',
		'[{"id":"a","text_template":"Send {actor_1} in carefully. Take what you can.","immediate_effects":{},"community_scores":{"rewilded":1,"exchange":1},"roll":{"relevant_stats":[{"stat":"security","weight":0.6},{"stat":"resources","weight":0.5}],"base_value":0.2,"context_bonuses":[{"condition":"actor_has_skill:combat","bonus":0.2}]},"outcomes":{"bad":{"text":"Part of the structure collapsed. {actor_1} barely got out. Nothing salvaged.","effects":{"health":-4,"morale":-3},"flags_set":["actor_1:injured"],"flags_cleared":[]},"mixed":{"text":"Some useful items recovered. Not worth the risk, probably, but done now.","effects":{"resources":6},"flags_set":[],"flags_cleared":[]},"good":{"text":"A careful search yielded excellent supplies. Tools, materials, even some preserved food.","effects":{"resources":12,"food":6,"morale":3},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Strip the outside only. Do not enter the structure.","immediate_effects":{},"community_scores":{"archive":1,"bastion":1},"roll":{"relevant_stats":[{"stat":"resources","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"Nothing useful on the exterior. A wasted trip.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A few odds and ends. Better than nothing.","effects":{"resources":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Good materials from the exterior. Enough to justify the effort without the risk.","effects":{"resources":8},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Mark it and leave it. Not worth someone getting hurt.","immediate_effects":{},"community_scores":{"kindred":1,"rewilded":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.5}],"base_value":0.5,"context_bonuses":[]},"outcomes":{"bad":{"text":"Others heard about the homestead and went anyway. Now you look indecisive.","effects":{"stability":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A cautious choice. The homestead remains for another day.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"The right call. Someone reported the structure collapsed completely the next day.","effects":{"morale":3,"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 19: Leadership Question
	_insert_tier2_event("tier2_leadership_question", "Leadership Question", "governance", "{}", a1, 25, 1.0, null, null,
		'{actor_1} publicly asked who makes the final decisions around here. It was not hostile — but it was not casual either. People are waiting for an answer.',
		'[{"id":"a","text_template":"Decisions are made together. By everyone.","immediate_effects":{},"community_scores":{"commonwealth":4},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"stability","weight":0.4}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The idealism rang hollow. Decisions have been unilateral and everyone knows it.","effects":{"cohesion":-5,"stability":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A nice sentiment. Whether it is true will be tested soon.","effects":{"morale":1},"flags_set":[],"flags_cleared":[]},"good":{"text":"The commitment to shared governance was genuine. People felt empowered.","effects":{"morale":4,"cohesion":4,"stability":2},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"I do. Someone has to, and I am accountable.","immediate_effects":{},"community_scores":{"throne":4},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The directness alarmed people. This is not what they signed up for.","effects":{"cohesion":-6,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Some respected the honesty. Others are uneasy. Power has been named.","effects":{"stability":2,"cohesion":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"Clear authority, clearly claimed. In uncertain times, people wanted exactly this.","effects":{"stability":5,"morale":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Deflect. Now is not the time for this conversation.","immediate_effects":{},"community_scores":{"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.5},{"stat":"morale","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The deflection was seen as cowardice. {actor_1} pressed harder.","effects":{"stability":-4,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The question was shelved. It will come back.","effects":{"stability":-1},"flags_set":[],"flags_cleared":[]},"good":{"text":"Timing matters. People accepted the deferral and the moment passed.","effects":{"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 20: Burial Rites
	_insert_tier2_event("tier2_burial_rites", "Burial Rites", "social", '{"required_state_tags":["recent_death"]}', null, 20, 1.0, null, null,
		'A community member has died and people disagree on how to honour them. Some want a religious ceremony. Others want something simpler. A few say there is not time for any of it.',
		'[{"id":"a","text_template":"Hold a formal ceremony. Give them a proper farewell.","immediate_effects":{},"community_scores":{"congregation":3,"kindred":2},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The ceremony sparked an argument about beliefs. The farewell was marred by conflict.","effects":{"cohesion":-5,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A solemn ceremony. Not everyone participated but those who did found comfort.","effects":{"morale":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"A moving ceremony. People cried, spoke, and came together in grief.","effects":{"morale":5,"cohesion":4},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Keep it simple. A moment of silence and move on.","immediate_effects":{},"community_scores":{"bastion":1,"rewilded":2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.6},{"stat":"morale","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Too brief. People felt the death was not acknowledged. The grief had nowhere to go.","effects":{"morale":-4,"cohesion":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Brief and functional. Some people needed more.","effects":{"morale":-1},"flags_set":[],"flags_cleared":[]},"good":{"text":"Simple and dignified. People respected the restraint.","effects":{"stability":3,"morale":2},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Let individuals grieve in their own way. No organised event.","immediate_effects":{},"community_scores":{"rewilded":2,"kindred":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.6},{"stat":"morale","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Without structure, the grief fragmented people further.","effects":{"cohesion":-5,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"People grieved privately. The community moved on, unevenly.","effects":{"morale":-1},"flags_set":[],"flags_cleared":[]},"good":{"text":"People found their own way to honour the lost. Small gestures, quiet and genuine.","effects":{"morale":3,"cohesion":2},"flags_set":[],"flags_cleared":[]}}}]'
	)


func _insert_tier2_event(id: String, title: String, category: String, eligibility: String, actor_req, cooldown_days: int, weight: float, exclusion_group, max_occurrences, desc_template: String, choices_json: String) -> void:
	_library_db.query_with_bindings(
		"INSERT INTO events (id, tier, category, title, eligibility, description_template, actor_requirements, choices, chain_id, chain_stage, chain_memory_schema, cooldown_days, exclusion_group, max_occurrences, content_tags, seasonal_tags, weight) VALUES (?, 2, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, ?, ?, NULL, NULL, ?);",
		[id, category, title, eligibility, desc_template, actor_req, choices_json, cooldown_days, exclusion_group, max_occurrences, weight]
	)
