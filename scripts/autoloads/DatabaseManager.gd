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
		_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE chain_id IS NOT NULL;")
		if _library_db.query_result.size() == 0 or int(_library_db.query_result[0].get("cnt", 0)) < 15:
			_seed_chain_events()
		_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 3;")
		if _library_db.query_result.size() == 0 or int(_library_db.query_result[0].get("cnt", 0)) < 15:
			_seed_tier3_events()
		_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 4;")
		if _library_db.query_result.size() == 0 or int(_library_db.query_result[0].get("cnt", 0)) < 8:
			_seed_tier4_events()

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
		chain_auto_next      TEXT DEFAULT NULL,
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
		chain_id        TEXT PRIMARY KEY,
		current_stage_id TEXT NOT NULL,
		memory          TEXT NOT NULL,
		started_day     INTEGER NOT NULL,
		last_stage_day  INTEGER NOT NULL,
		next_fire_day   INTEGER
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
	_seed_chain_events()
	_seed_tier3_events()
	_seed_tier4_events()


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
		'[{"id":"a","text_template":"Grant {actor_1} a day of rest. Everyone needs it sometimes.","immediate_effects":{"morale":2},"community_scores":{"commonwealth":2,"kindred":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Others saw the rest day and wanted the same. Productivity collapsed for a week.","effects":{"resources":-5,"stability":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"{actor_1} rested and returned to work. A few grumbles, nothing more.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"{actor_1} came back refreshed and grateful. The gesture was noticed by everyone.","effects":{"morale":4,"cohesion":2},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Insist. Everyone works. No exceptions.","immediate_effects":{"stability":2},"community_scores":{"throne":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} worked but resentment is building. You can feel it.","effects":{"morale":-6,"cohesion":-3},"flags_set":[],"flags_cleared":[],"escalates_to":"tier3_full_breakdown"},"mixed":{"text":"{actor_1} complied without further argument. The message was received.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The firmness was respected. People understand that discipline keeps them alive.","effects":{"stability":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Reassign {actor_1} to lighter duties.","immediate_effects":{},"community_scores":{"commonwealth":1,"archive":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.5},{"stat":"morale","weight":0.5}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The lighter assignment was seen as favouritism. Others are unhappy.","effects":{"cohesion":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A compromise. Nobody is thrilled but nobody is angry.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"A pragmatic solution. {actor_1} contributed where they could and recovered naturally.","effects":{"morale":2,"stability":2},"flags_set":[],"flags_cleared":[]}}}]'
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


func _insert_chain_event(id: String, title: String, category: String, chain_id: String, chain_stage: int, chain_memory_schema: String, desc_template: String, actor_req, choices_json, chain_auto_next) -> void:
	_library_db.query_with_bindings(
		"INSERT INTO events (id, tier, category, title, eligibility, description_template, actor_requirements, choices, chain_id, chain_stage, chain_memory_schema, chain_auto_next, cooldown_days, exclusion_group, max_occurrences, content_tags, seasonal_tags, weight) VALUES (?, 2, ?, ?, '{}', ?, ?, ?, ?, ?, ?, ?, 0, NULL, 1, NULL, NULL, 1.0);",
		[id, category, title, desc_template, actor_req, choices_json, chain_id, chain_stage, chain_memory_schema, chain_auto_next]
	)


func _seed_chain_events() -> void:
	_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE chain_id IS NOT NULL;")
	if _library_db.query_result.size() > 0 and int(_library_db.query_result[0].get("cnt", 0)) >= 15:
		return

	var a1 := '{"actor_1":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'

	# ========== Chain 1: The Refugees (chain_refugees) ==========

	# Stage 1
	_insert_chain_event(
		"chain_refugees_1", "Refugees at the Gate", "external",
		"chain_refugees", 1,
		'{"reads":[],"writes":["leader_name","group_size","accepted"]}',
		'A group of refugees — twelve of them — has arrived at the settlement edge. Their leader, {actor_1}, speaks for them. They look hungry, frightened, and determined.',
		a1,
		'[{"id":"a","text_template":"Let them in on a trial basis. They earn their place.","immediate_effects":{"food":-15,"morale":3},"community_scores":{"commonwealth":2,"exchange":1},"roll":{"relevant_stats":[{"stat":"resources","weight":0.8},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The trial is off to a rough start. Resources are tighter than expected.","effects":{"resources":-8,"cohesion":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_2_tense","chain_memory_write":{"accepted":true,"group_size":12,"leader_name":"{actor_1}","mood":"tense"}},"mixed":{"text":"The refugees are in. It is an adjustment.","effects":{"cohesion":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_2_settled","chain_memory_write":{"accepted":true,"group_size":12,"leader_name":"{actor_1}","mood":"neutral"}},"good":{"text":"{actor_1} proved an excellent liaison. Integration is smoother than expected.","effects":{"morale":4,"cohesion":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_2_settled","chain_memory_write":{"accepted":true,"group_size":12,"leader_name":"{actor_1}","mood":"positive"}}}},{"id":"b","text_template":"The community cannot absorb twelve more people right now.","immediate_effects":{"morale":-5},"community_scores":{"bastion":2,"throne":1,"commonwealth":-3},"roll":{"relevant_stats":[{"stat":"stability","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The community fractured over the decision. Half wanted to help.","effects":{"cohesion":-8,"morale":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_2_aftermath","chain_memory_write":{"accepted":false,"group_size":12,"leader_name":"{actor_1}","mood":"divided"}},"mixed":{"text":"A hard call. The community accepted it without enthusiasm.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}},"good":{"text":"The decision was accepted. Leadership held.","effects":{"stability":3},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}}}}]',
		null
	)

	# Stage 2a — Settled
	_insert_chain_event(
		"chain_refugees_2_settled", "The Refugees Settle In", "external",
		"chain_refugees", 2,
		'{"reads":["leader_name","group_size","mood"],"writes":["integrated"]}',
		'The refugees — {memory.group_size} of them — have been with the community for two weeks now. {memory.leader_name} has been helpful, but tensions are emerging over work assignments.',
		null,
		'[{"id":"a","text_template":"Create a shared work rota.","immediate_effects":{},"community_scores":{"commonwealth":3},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The rota created more arguments than it solved.","effects":{"cohesion":-5},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_bad","chain_memory_write":{"integrated":false}},"mixed":{"text":"The rota works, barely.","effects":{"stability":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_good","chain_memory_write":{"integrated":true}},"good":{"text":"{memory.leader_name} took ownership of the rota. Real cooperation is developing.","effects":{"cohesion":5,"morale":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_good","chain_memory_write":{"integrated":true}}}},{"id":"b","text_template":"Let {memory.leader_name} manage their own people.","immediate_effects":{},"community_scores":{"kindred":2,"exchange":1},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Two separate communities formed. Cooperation is minimal.","effects":{"cohesion":-6},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_bad","chain_memory_write":{"integrated":false}},"mixed":{"text":"Parallel tracks. Peaceful but separate.","effects":{"cohesion":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_bad","chain_memory_write":{"integrated":false}},"good":{"text":"{memory.leader_name} group proved self-sufficient and complementary.","effects":{"stability":4,"resources":6},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_good","chain_memory_write":{"integrated":true}}}}]',
		null
	)

	# Stage 2b — Tense
	_insert_chain_event(
		"chain_refugees_2_tense", "Tensions with the Refugees", "external",
		"chain_refugees", 2,
		'{"reads":["leader_name","group_size"],"writes":["integrated"]}',
		'The provisional arrangement with the refugees is fraying. {memory.leader_name} came to you privately — their people feel unwelcome.',
		null,
		'[{"id":"a","text_template":"Hold a community meeting to air grievances.","immediate_effects":{},"community_scores":{"commonwealth":3},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"morale","weight":0.5}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The meeting became an argument. Fault lines are visible.","effects":{"cohesion":-7,"morale":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_bad","chain_memory_write":{"integrated":false}},"mixed":{"text":"Voices were heard. Nothing resolved but pressure released.","effects":{"cohesion":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_bad","chain_memory_write":{"integrated":false}},"good":{"text":"Honest conversation cleared the air. {memory.leader_name} was grateful for the chance to speak.","effects":{"cohesion":4,"morale":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_good","chain_memory_write":{"integrated":true}}}},{"id":"b","text_template":"Ask the refugees to leave if they are unhappy.","immediate_effects":{},"community_scores":{"throne":2,"bastion":1,"commonwealth":-2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"Half the refugees left. The others stayed, resentful. Your own people are divided over the handling.","effects":{"cohesion":-8,"morale":-6},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}},"mixed":{"text":"The ultimatum landed badly but they stayed.","effects":{"morale":-4,"stability":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_bad","chain_memory_write":{"integrated":false}},"good":{"text":"The bluntness paradoxically cleared the air. {memory.leader_name} respected the honesty.","effects":{"stability":4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_refugees_3_end_bad","chain_memory_write":{"integrated":false}}}}]',
		null
	)

	# Stage 2c — Aftermath (turned away, bad outcome)
	_insert_chain_event(
		"chain_refugees_2_aftermath", "Aftermath of the Refusal", "external",
		"chain_refugees", 2,
		'{"reads":["leader_name"],"writes":[]}',
		'Three weeks after the community turned away {memory.leader_name} group, a messenger arrived. They found shelter — but {memory.leader_name} wants to talk.',
		null,
		'[{"id":"a","text_template":"Meet with them.","immediate_effects":{},"community_scores":{"exchange":2},"roll":{"relevant_stats":[{"stat":"reputation","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The meeting went badly. The refugees have allied with another group nearby.","effects":{"reputation":-6,"security":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}},"mixed":{"text":"An awkward exchange. No harm done, no bridge built.","effects":{"reputation":2},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}},"good":{"text":"A surprising outcome — {memory.leader_name} offered a trade arrangement.","effects":{"reputation":8,"resources":10},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}}}},{"id":"b","text_template":"Decline the meeting.","immediate_effects":{"reputation":-5},"community_scores":{"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.3}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"bad":{"text":"Word spread. The community reputation for cruelty is growing.","effects":{"reputation":-8},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}},"mixed":{"text":"The messenger left. The matter is closed.","effects":{},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}},"good":{"text":"The messenger left. The matter is closed.","effects":{},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{}}}}]',
		null
	)

	# Stage 3a — Integrated well (no-choice resolution)
	_insert_chain_event(
		"chain_refugees_3_end_good", "The Refugees — Resolution", "external",
		"chain_refugees", 3,
		'{"reads":["leader_name","group_size"],"writes":[]}',
		'The {memory.group_size} who came with {memory.leader_name} are woven into the community now. Some of them are among the most reliable people here.',
		null, null, null
	)

	# Stage 3b — Integrated poorly (no-choice resolution)
	_insert_chain_event(
		"chain_refugees_3_end_bad", "The Refugees — Resolution", "external",
		"chain_refugees", 3,
		'{"reads":["leader_name","group_size"],"writes":[]}',
		'The {memory.group_size} who came with {memory.leader_name} are still here. Nobody would call them community. They coexist. It is not the same thing.',
		null, null, null
	)

	# ========== Chain 2: The Illness (chain_illness) ==========

	# Stage 1
	_insert_chain_event(
		"chain_illness_1", "Something Going Around", "health",
		"chain_illness", 1,
		'{"reads":[],"writes":["source","sick_count","quarantine_held"]}',
		'Several people reported feeling unwell this morning. Headaches, fever, fatigue. {actor_1} was the first to show symptoms. Nobody knows the source yet.',
		a1,
		'[{"id":"a","text_template":"Quarantine the sick immediately. Isolate and contain.","immediate_effects":{"morale":-3},"community_scores":{"archive":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"health","weight":1.0},{"stat":"knowledge","weight":0.5}],"base_value":0.2,"context_bonuses":[{"condition":"stat_above:health:50","bonus":0.3}]},"outcomes":{"bad":{"text":"The quarantine was too late. Three more fell ill before containment held.","effects":{"health":-6,"morale":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_2_quarantine","chain_memory_write":{"source":"unknown contamination","sick_count":6,"quarantine_held":false}},"mixed":{"text":"The quarantine contained the worst of it. People are nervous but following protocol.","effects":{"health":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_2_quarantine","chain_memory_write":{"source":"unknown contamination","sick_count":3,"quarantine_held":true}},"good":{"text":"Swift action. The sick are isolated and the source is being traced.","effects":{"stability":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_2_quarantine","chain_memory_write":{"source":"contaminated water","sick_count":2,"quarantine_held":true}}}},{"id":"b","text_template":"Treat openly. Share resources and keep people calm.","immediate_effects":{"resources":-8,"morale":2},"community_scores":{"congregation":2,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"health","weight":0.8},{"stat":"resources","weight":0.4}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The illness spread rapidly through the open camp. Half the community is showing symptoms.","effects":{"health":-10,"morale":-5},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_2_spread","chain_memory_write":{"source":"unknown contamination","sick_count":10,"quarantine_held":false}},"mixed":{"text":"Some spread was inevitable but people appreciated the transparency.","effects":{"health":-5,"cohesion":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_2_spread","chain_memory_write":{"source":"unknown contamination","sick_count":5,"quarantine_held":false}},"good":{"text":"Open treatment and good care kept it contained. Trust in leadership grew.","effects":{"morale":4,"cohesion":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"source":"mild infection","sick_count":2,"quarantine_held":false}}}}]',
		null
	)

	# Stage 2a — Quarantine
	_insert_chain_event(
		"chain_illness_2_quarantine", "The Quarantine Holds", "health",
		"chain_illness", 2,
		'{"reads":["source","sick_count","quarantine_held"],"writes":["quarantine_held"]}',
		'Day five of the quarantine. {memory.sick_count} people are isolated. Supplies are being rationed to the sick. The healthy are restless.',
		null,
		'[{"id":"a","text_template":"Maintain the quarantine. Stay the course.","immediate_effects":{"resources":-5},"community_scores":{"archive":2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"health","weight":0.6}],"base_value":0.3,"context_bonuses":[{"condition":"stat_above:health:40","bonus":0.2}]},"outcomes":{"bad":{"text":"The quarantine broke down. Someone snuck out. Now everyone is exposed.","effects":{"health":-8,"stability":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":false}},"mixed":{"text":"The quarantine held but morale is fraying. People want normalcy.","effects":{"morale":-4,"health":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":true}},"good":{"text":"The quarantine worked. New cases stopped appearing. The illness is burning itself out.","effects":{"health":6,"stability":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":true}}}},{"id":"b","text_template":"End the quarantine early. People need to work.","immediate_effects":{"morale":3},"community_scores":{"commonwealth":1,"congregation":1},"roll":{"relevant_stats":[{"stat":"health","weight":1.0}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"bad":{"text":"The illness roared back. More people sick than before.","effects":{"health":-10,"morale":-6},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":false}},"mixed":{"text":"Some spread, but the worst had already passed.","effects":{"health":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":false}},"good":{"text":"Timing was right. The sick were already recovering. Life resumed.","effects":{"morale":4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":true}}}}]',
		null
	)

	# Stage 2b — Spread
	_insert_chain_event(
		"chain_illness_2_spread", "The Illness Spreads", "health",
		"chain_illness", 2,
		'{"reads":["source","sick_count"],"writes":["quarantine_held"]}',
		'The illness has spread. {memory.sick_count} people are now symptomatic. Productivity has collapsed. Desperate measures are being discussed.',
		null,
		'[{"id":"a","text_template":"Burn through the medical supplies. Treat aggressively.","immediate_effects":{"resources":-15},"community_scores":{"congregation":2},"roll":{"relevant_stats":[{"stat":"health","weight":1.0},{"stat":"knowledge","weight":0.5}],"base_value":0.2,"context_bonuses":[{"condition":"actor_has_skill:medicine","bonus":0.3}]},"outcomes":{"bad":{"text":"The supplies are gone and people are still sick. A dire situation.","effects":{"health":-6,"resources":-5},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":false}},"mixed":{"text":"The aggressive treatment helped some. Others are still fighting it.","effects":{"health":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":false}},"good":{"text":"The treatment worked. Recovery is rapid. The worst is over.","effects":{"health":8,"morale":4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":false}}}},{"id":"b","text_template":"Late quarantine. Lock it down now.","immediate_effects":{"morale":-5},"community_scores":{"archive":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"bad":{"text":"Too late. The quarantine is a formality. Everyone has been exposed.","effects":{"health":-8,"cohesion":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":false}},"mixed":{"text":"The late quarantine slowed things. Not ideal but better than nothing.","effects":{"health":-3,"stability":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":true}},"good":{"text":"Against the odds, the quarantine worked. The illness peaked and began to fade.","effects":{"health":4,"stability":4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_illness_3_end","chain_memory_write":{"quarantine_held":true}}}}]',
		null
	)

	# Stage 3 — Resolution (no-choice)
	_insert_chain_event(
		"chain_illness_3_end", "The Illness Passes", "health",
		"chain_illness", 3,
		'{"reads":["source","sick_count","quarantine_held"],"writes":[]}',
		'The illness has run its course. The community survived, though not without cost. The source was traced to {memory.source}. People will remember how it was handled.',
		null, null, null
	)

	# ========== Chain 3: The Deserter (chain_deserter) ==========

	# Stage 1
	_insert_chain_event(
		"chain_deserter_1", "Signs of Desertion", "interpersonal",
		"chain_deserter", 1,
		'{"reads":[],"writes":["deserter_name","reason","confronted"]}',
		'Someone found a hidden pack near the perimeter — supplies, a water bottle, a rough map. It belongs to {actor_1}. They are planning to leave.',
		a1,
		'[{"id":"a","text_template":"Confront {actor_1} directly.","immediate_effects":{},"community_scores":{"throne":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"cohesion","weight":0.5}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} denied everything, then became hostile. The confrontation turned ugly.","effects":{"cohesion":-5,"morale":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_2_confronted","chain_memory_write":{"deserter_name":"{actor_1}","reason":"felt trapped","confronted":true}},"mixed":{"text":"{actor_1} admitted it. They said they felt trapped. No resolution yet.","effects":{"cohesion":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_2_confronted","chain_memory_write":{"deserter_name":"{actor_1}","reason":"felt unvalued","confronted":true}},"good":{"text":"{actor_1} broke down. They were afraid, not disloyal. The conversation helped.","effects":{"morale":2,"cohesion":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_2_confronted","chain_memory_write":{"deserter_name":"{actor_1}","reason":"was afraid","confronted":true}}}},{"id":"b","text_template":"Watch {actor_1} quietly. Do not tip them off.","immediate_effects":{},"community_scores":{"archive":2,"exchange":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.6},{"stat":"security","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} noticed the surveillance and panicked. They tried to leave that night.","effects":{"security":-3,"morale":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_2_watched","chain_memory_write":{"deserter_name":"{actor_1}","reason":"felt watched","confronted":false}},"mixed":{"text":"The watch revealed nothing new. {actor_1} continues their routine, but the pack is still there.","effects":{},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_2_watched","chain_memory_write":{"deserter_name":"{actor_1}","reason":"unknown","confronted":false}},"good":{"text":"Watching {actor_1} revealed they had been meeting someone outside the perimeter. Intelligence gained.","effects":{"security":3,"knowledge":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_2_watched","chain_memory_write":{"deserter_name":"{actor_1}","reason":"outside contact","confronted":false}}}}]',
		null
	)

	# Stage 2a — Confronted
	_insert_chain_event(
		"chain_deserter_2_confronted", "The Confrontation", "interpersonal",
		"chain_deserter", 2,
		'{"reads":["deserter_name","reason"],"writes":[]}',
		'{memory.deserter_name} knows you know. The community is watching. They said they {memory.reason}. What happens next defines something about this place.',
		null,
		'[{"id":"a","text_template":"Give {memory.deserter_name} a reason to stay. Address their grievance.","immediate_effects":{},"community_scores":{"commonwealth":3,"kindred":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"{memory.deserter_name} listened but their mind was made up. They left the next morning.","effects":{"morale":-5,"cohesion":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":false}},"mixed":{"text":"{memory.deserter_name} agreed to stay, for now. The underlying tension remains.","effects":{"morale":-1},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":true}},"good":{"text":"{memory.deserter_name} was moved by the effort. Something shifted. They recommitted.","effects":{"morale":4,"cohesion":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":true}}}},{"id":"b","text_template":"Let them go. No one is a prisoner here.","immediate_effects":{"morale":-2},"community_scores":{"commonwealth":2,"rewilded":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"{memory.deserter_name} left and took supplies. Others are wondering if they should do the same.","effects":{"morale":-6,"stability":-4,"resources":-5},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":false}},"mixed":{"text":"{memory.deserter_name} left quietly. A loss, but a clean one.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":false}},"good":{"text":"{memory.deserter_name} left with dignity. The community respected the handling. Strangely, it strengthened resolve.","effects":{"stability":3,"cohesion":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":false}}}}]',
		null
	)

	# Stage 2b — Watched
	_insert_chain_event(
		"chain_deserter_2_watched", "Watching and Waiting", "interpersonal",
		"chain_deserter", 2,
		'{"reads":["deserter_name","reason"],"writes":[]}',
		'The watch on {memory.deserter_name} continues. They {memory.reason}. The situation cannot hold indefinitely.',
		null,
		'[{"id":"a","text_template":"Approach {memory.deserter_name} now, with what you know.","immediate_effects":{},"community_scores":{"throne":2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"morale","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The delayed confrontation felt like surveillance. {memory.deserter_name} was furious and left immediately.","effects":{"cohesion":-6,"morale":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":false}},"mixed":{"text":"{memory.deserter_name} was shaken but agreed to talk. An uneasy truce.","effects":{"cohesion":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":true}},"good":{"text":"The intelligence gathered made the conversation productive. {memory.deserter_name} felt heard.","effects":{"stability":3,"cohesion":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":true}}}},{"id":"b","text_template":"Do nothing. Let events take their course.","immediate_effects":{},"community_scores":{"rewilded":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"{memory.deserter_name} vanished in the night. Took more than their share.","effects":{"morale":-5,"resources":-6},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":false}},"mixed":{"text":"{memory.deserter_name} stayed, but the distance between them and the community grew.","effects":{"cohesion":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":true}},"good":{"text":"{memory.deserter_name} unpacked the hidden bag themselves. Whatever passed, it passed.","effects":{"morale":3,"cohesion":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_deserter_3_end","chain_memory_write":{"stayed":true}}}}]',
		null
	)

	# Stage 3 — Resolution (no-choice)
	_insert_chain_event(
		"chain_deserter_3_end", "The Deserter — Resolution", "interpersonal",
		"chain_deserter", 3,
		'{"reads":["deserter_name","stayed"],"writes":[]}',
		'The matter of {memory.deserter_name} has settled. The community moved on, as it must.',
		null, null, null
	)

	# ========== Chain 4: The Rival Group (chain_rivals) ==========

	# Stage 1
	_insert_chain_event(
		"chain_rivals_1", "Signs of Others", "external",
		"chain_rivals", 1,
		'{"reads":[],"writes":["rival_name","approach","threat_level"]}',
		'{actor_1} found tracks near the foraging grounds — fresh, deliberate. Supply caches have been disturbed. Someone else is operating in the area.',
		a1,
		'[{"id":"a","text_template":"Investigate carefully. Map their movements.","immediate_effects":{},"community_scores":{"archive":2,"exchange":1},"roll":{"relevant_stats":[{"stat":"security","weight":0.8},{"stat":"knowledge","weight":0.5}],"base_value":0.3,"context_bonuses":[{"condition":"actor_has_skill:combat","bonus":0.2}]},"outcomes":{"bad":{"text":"The investigation was spotted. Whoever is out there knows you are aware of them now.","effects":{"security":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_2","chain_memory_write":{"rival_name":"the eastern group","approach":"cautious","threat_level":"medium"}},"mixed":{"text":"A clear picture is forming. A small group, maybe eight people, operating east of here.","effects":{"knowledge":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_2","chain_memory_write":{"rival_name":"the eastern group","approach":"cautious","threat_level":"low"}},"good":{"text":"Thorough reconnaissance. You know their camp location, their numbers, their patterns.","effects":{"security":4,"knowledge":4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_2","chain_memory_write":{"rival_name":"the eastern group","approach":"cautious","threat_level":"low"}}}},{"id":"b","text_template":"Mark the territory. Make it clear this area is claimed.","immediate_effects":{},"community_scores":{"bastion":3,"throne":1},"roll":{"relevant_stats":[{"stat":"security","weight":1.0}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The territorial markers were torn down overnight. A message.","effects":{"security":-5,"morale":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_2","chain_memory_write":{"rival_name":"the hostile group","approach":"aggressive","threat_level":"high"}},"mixed":{"text":"The markers stand. No response yet. Tension hangs in the air.","effects":{"security":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_2","chain_memory_write":{"rival_name":"the nearby group","approach":"aggressive","threat_level":"medium"}},"good":{"text":"The markers worked. Activity near your territory dropped immediately.","effects":{"security":5,"stability":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_2","chain_memory_write":{"rival_name":"the nearby group","approach":"aggressive","threat_level":"low"}}}}]',
		null
	)

	# Stage 2
	_insert_chain_event(
		"chain_rivals_2", "Contact with the Rivals", "external",
		"chain_rivals", 2,
		'{"reads":["rival_name","approach","threat_level"],"writes":["approach"]}',
		'Confirmed: {memory.rival_name} is real. A small settlement, surviving much as you are. Threat level seems {memory.threat_level}. Direct contact is now possible.',
		null,
		'[{"id":"a","text_template":"Send an envoy to negotiate.","immediate_effects":{},"community_scores":{"exchange":3,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"reputation","weight":0.8},{"stat":"knowledge","weight":0.4}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The envoy was turned away. {memory.rival_name} is not interested in talk.","effects":{"reputation":-3,"morale":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_3_conflict","chain_memory_write":{"approach":"diplomatic"}},"mixed":{"text":"A cautious exchange. Neither side trusts the other but communication is open.","effects":{"reputation":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_3_peace","chain_memory_write":{"approach":"diplomatic"}},"good":{"text":"The envoy was well received. {memory.rival_name} is open to trade talks.","effects":{"reputation":5,"morale":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_3_peace","chain_memory_write":{"approach":"diplomatic"}}}},{"id":"b","text_template":"Send a warning. Stay out of our territory.","immediate_effects":{},"community_scores":{"bastion":3,"throne":1},"roll":{"relevant_stats":[{"stat":"security","weight":1.0}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The warning was met with a counter-warning. Escalation is real.","effects":{"security":-4,"morale":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_3_conflict","chain_memory_write":{"approach":"hostile"}},"mixed":{"text":"The warning was received. An uneasy standoff.","effects":{"security":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_3_conflict","chain_memory_write":{"approach":"hostile"}},"good":{"text":"The warning was respected. {memory.rival_name} pulled back from the disputed area.","effects":{"security":5,"stability":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"approach":"hostile"}}}}]',
		null
	)

	# Stage 3a — Peace
	_insert_chain_event(
		"chain_rivals_3_peace", "Negotiations with the Rivals", "external",
		"chain_rivals", 3,
		'{"reads":["rival_name"],"writes":[]}',
		'A meeting has been arranged with {memory.rival_name}. Neutral ground. Both sides armed but talking.',
		null,
		'[{"id":"a","text_template":"Propose a trade arrangement. Mutual benefit.","immediate_effects":{},"community_scores":{"exchange":3,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"reputation","weight":0.8},{"stat":"resources","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The trade terms fell apart. Cultural differences run deep. The meeting ended coldly.","effects":{"reputation":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"cold_peace"}},"mixed":{"text":"A small trade deal was struck. Not transformative but a start.","effects":{"resources":6,"reputation":4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"trade"}},"good":{"text":"A real partnership is forming. Resource sharing, shared intelligence, mutual defense.","effects":{"resources":12,"reputation":8,"security":4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"alliance"}}}},{"id":"b","text_template":"Propose territorial boundaries. Coexistence through separation.","immediate_effects":{},"community_scores":{"bastion":2,"archive":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The boundary proposal was seen as an insult. They wanted partnership, not walls.","effects":{"reputation":-5},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"cold_peace"}},"mixed":{"text":"Boundaries were agreed. Clear, if cold. Better than conflict.","effects":{"security":4,"stability":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"cold_peace"}},"good":{"text":"Clean lines drawn with mutual respect. Both groups have room to grow.","effects":{"security":6,"stability":5,"reputation":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"boundary"}}}}]',
		null
	)

	# Stage 3b — Conflict
	_insert_chain_event(
		"chain_rivals_3_conflict", "Escalation with the Rivals", "external",
		"chain_rivals", 3,
		'{"reads":["rival_name"],"writes":[]}',
		'Things with {memory.rival_name} are getting worse. A scuffle at a foraging site. Supplies taken. The community wants a response.',
		null,
		'[{"id":"a","text_template":"Retaliate in kind. Take back what was taken.","immediate_effects":{},"community_scores":{"bastion":3,"throne":2},"roll":{"relevant_stats":[{"stat":"security","weight":1.0}],"base_value":0.2,"context_bonuses":[{"condition":"stat_above:security:50","bonus":0.3}]},"outcomes":{"bad":{"text":"The retaliation spiraled. People were hurt on both sides.","effects":{"security":-6,"health":-5,"morale":-4},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"conflict"}},"mixed":{"text":"The raid succeeded but at a cost. The rivalry is entrenched.","effects":{"resources":8,"security":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"rivalry"}},"good":{"text":"A decisive response. {memory.rival_name} backed down after the show of force.","effects":{"security":5,"resources":10},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"deterred"}}}},{"id":"b","text_template":"De-escalate. Try to talk despite the provocation.","immediate_effects":{},"community_scores":{"commonwealth":2,"exchange":2},"roll":{"relevant_stats":[{"stat":"reputation","weight":0.6},{"stat":"stability","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The peace attempt was seen as weakness. {memory.rival_name} took more.","effects":{"resources":-8,"security":-4,"morale":-5},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"conflict"}},"mixed":{"text":"An uneasy ceasefire. Neither side is happy but the bleeding stopped.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"cold_peace"}},"good":{"text":"Against the odds, diplomacy worked. {memory.rival_name} apologized and offered restitution.","effects":{"reputation":6,"resources":6,"morale":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_rivals_4_end","chain_memory_write":{"outcome":"trade"}}}}]',
		null
	)

	# Stage 4 — Resolution (no-choice)
	_insert_chain_event(
		"chain_rivals_4_end", "The Rivals — Resolution", "external",
		"chain_rivals", 4,
		'{"reads":["rival_name"],"writes":[]}',
		'The situation with {memory.rival_name} has found its equilibrium. Whatever the relationship is now, it is what the community built through its choices.',
		null, null, null
	)

	# ========== Chain 5: The Teacher's Legacy (chain_teacher) ==========

	# Stage 1
	_insert_chain_event(
		"chain_teacher_1", "The Teacher Approaches", "governance",
		"chain_teacher", 1,
		'{"reads":[],"writes":["teacher_name","knowledge_type","committed"]}',
		'{actor_1} has asked to speak with you privately. They are getting older, they say, and they carry knowledge the community cannot afford to lose. They want to teach — formally, with time set aside.',
		'{"actor_1":{"required_skills":["teaching","engineering","medicine"],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}',
		'[{"id":"a","text_template":"Allocate time for formal teaching sessions.","immediate_effects":{"resources":-3},"community_scores":{"archive":3,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"stability","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The teaching sessions disrupted the work schedule badly. People resent the lost productivity.","effects":{"resources":-5,"morale":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_2","chain_memory_write":{"teacher_name":"{actor_1}","knowledge_type":"practical skills","committed":true}},"mixed":{"text":"Teaching has begun. It is slow going but {actor_1} is patient.","effects":{"knowledge":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_2","chain_memory_write":{"teacher_name":"{actor_1}","knowledge_type":"practical skills","committed":true}},"good":{"text":"{actor_1} is a natural teacher. The students are engaged. Real knowledge transfer is happening.","effects":{"knowledge":6,"morale":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_2","chain_memory_write":{"teacher_name":"{actor_1}","knowledge_type":"practical skills","committed":true}}}},{"id":"b","text_template":"Now is not the time. Survival comes first.","immediate_effects":{},"community_scores":{"bastion":1,"throne":1,"archive":-2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} was visibly hurt. Knowledge that could save lives may be lost.","effects":{"morale":-4,"knowledge":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{"teacher_name":"{actor_1}","committed":false}},"mixed":{"text":"{actor_1} accepted the decision with quiet disappointment.","effects":{"morale":-2},"flags_set":[],"flags_cleared":[],"next_stage_id":null,"chain_memory_write":{"teacher_name":"{actor_1}","committed":false}},"good":{"text":"{actor_1} understood. They began teaching informally during meals instead.","effects":{"knowledge":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_2","chain_memory_write":{"teacher_name":"{actor_1}","knowledge_type":"practical skills","committed":false}}}}]',
		null
	)

	# Stage 2
	_insert_chain_event(
		"chain_teacher_2", "The Teaching Continues", "governance",
		"chain_teacher", 2,
		'{"reads":["teacher_name","knowledge_type","committed"],"writes":["committed"]}',
		'{memory.teacher_name} teaching on {memory.knowledge_type} has been underway for weeks. The students are learning but the work schedule is suffering.',
		null,
		'[{"id":"a","text_template":"Double down. Knowledge is the long game.","immediate_effects":{"resources":-5},"community_scores":{"archive":3,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.0},{"stat":"morale","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The community resents the ongoing disruption. {memory.teacher_name} feels the hostility.","effects":{"morale":-5,"cohesion":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_3_end","chain_memory_write":{"committed":true}},"mixed":{"text":"The teaching continued. Not everyone is happy but the students are genuinely learning.","effects":{"knowledge":5},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_3_end","chain_memory_write":{"committed":true}},"good":{"text":"A breakthrough moment. One of the students solved a problem using what {memory.teacher_name} taught. The value became undeniable.","effects":{"knowledge":8,"morale":4,"cohesion":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_3_end","chain_memory_write":{"committed":true}}}},{"id":"b","text_template":"Scale it back. Less formal, less disruptive.","immediate_effects":{},"community_scores":{"commonwealth":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.6},{"stat":"knowledge","weight":0.5}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The scaled-back approach lost momentum. {memory.teacher_name} stopped trying.","effects":{"knowledge":-2,"morale":-3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_3_end","chain_memory_write":{"committed":false}},"mixed":{"text":"Informal teaching continued at a slower pace. Some knowledge transferred, some lost.","effects":{"knowledge":3},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_3_end","chain_memory_write":{"committed":false}},"good":{"text":"The lighter approach worked better. People learned at their own pace.","effects":{"knowledge":5,"morale":2},"flags_set":[],"flags_cleared":[],"next_stage_id":"chain_teacher_3_end","chain_memory_write":{"committed":true}}}}]',
		null
	)

	# Stage 3 — Resolution (no-choice)
	_insert_chain_event(
		"chain_teacher_3_end", "The Teacher's Legacy — Resolution", "governance",
		"chain_teacher", 3,
		'{"reads":["teacher_name","knowledge_type","committed"],"writes":[]}',
		'{memory.teacher_name} teaching on {memory.knowledge_type} has come to a natural end. What was learned will shape the community for years to come.',
		null, null, null
	)


func _insert_tier3_event(id: String, title: String, category: String, eligibility: String, actor_req, cooldown_days: int, weight: float, desc_template: String, choices_json: String) -> void:
	_library_db.query_with_bindings(
		"INSERT INTO events (id, tier, category, title, eligibility, description_template, actor_requirements, choices, chain_id, chain_stage, chain_memory_schema, cooldown_days, exclusion_group, max_occurrences, content_tags, seasonal_tags, weight) VALUES (?, 3, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, NULL, NULL, NULL, NULL, ?);",
		[id, category, title, eligibility, desc_template, actor_req, choices_json, cooldown_days, weight]
	)


func _seed_tier3_events() -> void:
	_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 3;")
	if _library_db.query_result.size() > 0 and int(_library_db.query_result[0].get("cnt", 0)) >= 15:
		return

	var a1 := '{"actor_1":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'
	var a1_eng := '{"actor_1":{"required_skills":["engineering"],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'
	var a1_med := '{"actor_1":{"required_skills":["medicine"],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'

	# Event 1: Raid
	_insert_tier3_event("tier3_raid", "Under Attack", "external", '{"min_game_day":30}', a1, 45, 1.0,
		'They came before dawn. A group — armed, organised, and angry.\n\nThey want supplies. {actor_1} is at the perimeter and the community is awake and frightened.\n\nYou have minutes to decide.',
		'[{"id":"a","text_template":"Fight back. Drive them off.","immediate_effects":{"security":-5},"community_scores":{"bastion":3,"throne":2},"roll":{"relevant_stats":[{"stat":"security","weight":1.2},{"stat":"morale","weight":0.5}],"base_value":0.0,"context_bonuses":[{"condition":"actor_has_skill:combat","bonus":0.4}]},"outcomes":{"catastrophic":{"text":"The defence collapsed. They took what they wanted and burned something on the way out.","effects":{"resources":-30,"health":-20,"morale":-20,"security":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"You held them off but took casualties. {actor_1} was injured.","effects":{"resources":-12,"health":-12,"morale":-10},"flags_set":["actor_1:injured"],"flags_cleared":[]},"mixed":{"text":"The attackers were driven off but not without cost. They will likely be back.","effects":{"resources":-8,"security":-5,"morale":-5},"flags_set":[],"flags_cleared":[]},"good":{"text":"A clean defence. They retreated faster than expected.","effects":{"security":8,"morale":8},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The defence was overwhelming. Word will spread — this community is not an easy target.","effects":{"security":15,"morale":12},"flags_set":["repelled_raid"],"flags_cleared":[]}}},{"id":"b","text_template":"Meet them at the perimeter. Talk first.","immediate_effects":{},"community_scores":{"commonwealth":2,"exchange":2},"roll":{"relevant_stats":[{"stat":"reputation","weight":0.8},{"stat":"stability","weight":0.6}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Negotiation was read as weakness. The attack intensified.","effects":{"resources":-25,"health":-15,"morale":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"They took more than was offered.","effects":{"resources":-18,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A deal of sorts. Costly, but they left.","effects":{"resources":-12,"reputation":5},"flags_set":[],"flags_cleared":[]},"good":{"text":"The negotiation worked. They wanted food more than a fight.","effects":{"resources":-6,"reputation":8,"morale":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"An extraordinary outcome — the negotiation ended with a tentative agreement to trade rather than raid.","effects":{"reputation":15,"resources":-5,"morale":8},"flags_set":["raid_turned_trade"],"flags_cleared":[]}}},{"id":"c","text_template":"Pay them off. Avoid bloodshed.","immediate_effects":{"resources":-20,"morale":-8},"community_scores":{"exchange":1,"rewilded":1,"bastion":-2},"roll":{"relevant_stats":[{"stat":"resources","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"They took the supplies and attacked anyway.","effects":{"health":-15,"morale":-15,"security":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"They left but told others. Expect more visitors.","effects":{"security":-8,"reputation":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"They took the supplies and left. For now.","effects":{"morale":-4},"flags_set":[],"flags_cleared":[]},"good":{"text":"They left without incident. The community is shaken but intact.","effects":{"morale":3},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"One of them lingered. Apologised quietly. Left extra.","effects":{"morale":5,"resources":5},"flags_set":[],"flags_cleared":[]}}},{"id":"d","text_template":"Everyone into hiding. Do not engage.","immediate_effects":{"morale":-5},"community_scores":{"rewilded":2,"archive":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.6},{"stat":"cohesion","weight":0.8}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"They found you anyway. Worse for the deception.","effects":{"resources":-20,"health":-10,"morale":-20,"cohesion":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"They found the stores. Not the people, but the supplies.","effects":{"resources":-22},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"They ransacked the outer area and left. Core supplies intact.","effects":{"resources":-8,"morale":-5},"flags_set":[],"flags_cleared":[]},"good":{"text":"They searched, found little, and moved on.","effects":{"morale":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Complete concealment. They did not know anyone was here.","effects":{"morale":8,"security":5},"flags_set":["raid_hidden_success"],"flags_cleared":[]}}}]'
	)

	# Event 2: Disease Outbreak
	_insert_tier3_event("tier3_disease_outbreak", "The Sickness", "health", '{"min_game_day":20}', null, 60, 1.0,
		'It spread faster than anyone expected. Six people are showing symptoms — fever, weakness, and something worse that nobody is naming yet.\n\nThe community is scared. You need to act now.',
		'[{"id":"a","text_template":"Full quarantine. Isolate the sick immediately.","immediate_effects":{},"community_scores":{"archive":3,"bastion":2},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.0},{"stat":"stability","weight":0.8}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Quarantine broke down. The illness spread to nearly everyone.","effects":{"health":-30,"morale":-20},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Quarantine held but the cost was enormous. People resent the isolation.","effects":{"health":-12,"morale":-15,"cohesion":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The outbreak was contained — six sick, none dead yet. A fragile situation.","effects":{"health":-10,"morale":-8},"flags_set":["active_quarantine"],"flags_cleared":[]},"good":{"text":"Quarantine worked. The illness burned through six people and stopped.","effects":{"health":-5,"morale":-4,"knowledge":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Textbook containment. The community learned something about managing illness.","effects":{"health":2,"knowledge":8,"morale":3},"flags_set":["disease_protocol_established"],"flags_cleared":[]}}},{"id":"b","text_template":"Treat openly. Accept the spread.","immediate_effects":{},"community_scores":{"commonwealth":2,"congregation":2},"roll":{"relevant_stats":[{"stat":"health","weight":1.0},{"stat":"morale","weight":0.6}],"base_value":0.0,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The illness spread to half the community. The death toll climbed.","effects":{"health":-28,"morale":-22,"cohesion":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Wide spread. Most survived but the community was weakened for weeks.","effects":{"health":-18,"morale":-10},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"It spread further than hoped but burned itself out.","effects":{"health":-12,"morale":-5,"cohesion":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The communal approach built solidarity even as people got sick. Most recovered well.","effects":{"health":-6,"morale":6,"cohesion":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Remarkable resilience. The community came through it together, stronger for it.","effects":{"health":-2,"morale":10,"cohesion":8,"knowledge":4},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Use all available medical supplies immediately.","immediate_effects":{"resources":-20},"community_scores":{"archive":1,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"health","weight":1.2},{"stat":"resources","weight":0.4}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The supplies were insufficient. The illness was unlike anything treatable with what was available.","effects":{"health":-20,"resources":-5,"morale":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"The supplies helped but did not stop the spread. Depleted now.","effects":{"health":-10,"morale":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Six people treated, all survived. Supplies exhausted.","effects":{"health":-3,"morale":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Fast aggressive treatment contained the outbreak quickly.","effects":{"health":3,"morale":6,"knowledge":3},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The treatment worked beyond expectations. One survivor described a recovery method.","effects":{"health":8,"morale":8,"knowledge":6},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 3: Famine
	_insert_tier3_event("tier3_famine", "The Hunger", "resource", '{"required_state_tags":["food_low"],"min_game_day":20}', null, 30, 1.0,
		'The food situation has become a crisis.\n\nAt current consumption rates there are days left, not weeks.\n\nPeople know. The mood in the community has shifted from worried to frightened.',
		'[{"id":"a","text_template":"Implement strict rationing immediately.","immediate_effects":{},"community_scores":{"bastion":2,"archive":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"morale","weight":0.6}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Rationing caused a revolt. Three people left. Stores were raided in the chaos.","effects":{"food":-20,"morale":-20,"cohesion":-15,"stability":-12},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Rationing held but barely. People are miserable and some are stealing.","effects":{"morale":-12,"cohesion":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Strict rationing bought time. Not comfortable time, but time.","effects":{"morale":-8,"stability":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The community accepted rationing. Morale dropped but order held.","effects":{"morale":-5,"stability":8,"cohesion":3},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Rationing was accepted with surprising dignity. People stepped up.","effects":{"morale":-3,"stability":10,"cohesion":6,"knowledge":4},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Send every able person to forage.","immediate_effects":{},"community_scores":{"rewilded":2,"kindred":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"security","weight":0.6}],"base_value":0.1,"context_bonuses":[{"condition":"season:summer","bonus":0.4},{"condition":"season:winter","bonus":-0.4}]},"outcomes":{"catastrophic":{"text":"The foragers found nothing. Two did not come back.","effects":{"food":-5,"morale":-18,"security":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Little found. The effort cost more than it gained.","effects":{"morale":-10,"health":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Enough found to extend the runway a week. The search continues.","effects":{"food":15,"morale":-5},"flags_set":[],"flags_cleared":[]},"good":{"text":"A cache was found. Not a permanent solution but real relief.","effects":{"food":30,"morale":6,"knowledge":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"A major discovery — abandoned stores, intact. The crisis is resolved for now.","effects":{"food":60,"morale":12,"knowledge":6},"flags_set":["cache_found"],"flags_cleared":[]}}},{"id":"c","text_template":"Appeal for help from outside.","immediate_effects":{},"community_scores":{"commonwealth":3,"exchange":2},"roll":{"relevant_stats":[{"stat":"reputation","weight":1.2}],"base_value":0.0,"context_bonuses":[{"condition":"flag:raid_turned_trade","bonus":0.5}]},"outcomes":{"catastrophic":{"text":"The appeal attracted the wrong attention.","effects":{"security":-15,"resources":-15,"morale":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"No response. The community is alone with this.","effects":{"morale":-12,"cohesion":-6},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A small amount of help arrived. Not enough but something.","effects":{"food":12,"reputation":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"A neighbouring group sent supplies in exchange for future goodwill.","effects":{"food":25,"reputation":10,"morale":8},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The appeal sparked a trade network. Food now, connection going forward.","effects":{"food":35,"reputation":15,"morale":10},"flags_set":[],"flags_cleared":[],"chain_to":"chain_rivals"}}}]'
	)

	# Event 4: Leadership Crisis
	_insert_tier3_event("tier3_leadership_crisis", "No Confidence", "governance", '{"required_state_tags":["stability_low"],"min_game_day":60}', a1, 60, 1.0,
		'It came to a head today. {actor_1} stood up in front of everyone and said what several people had been thinking: that the community needs different leadership.\n\nNot everyone agrees. But enough do that this cannot be ignored.',
		'[{"id":"a","text_template":"Defend your leadership publicly.","immediate_effects":{},"community_scores":{"throne":3,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"morale","weight":0.6},{"stat":"cohesion","weight":0.6}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The defence fell apart under questioning. The community split.","effects":{"stability":-20,"cohesion":-18,"morale":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"You held on but lost credibility. {actor_1} is still there, still watching.","effects":{"stability":-8,"morale":-8,"cohesion":-6},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A narrow victory. Leadership held but the wound is visible.","effects":{"stability":-4,"morale":-5},"flags_set":[],"flags_cleared":[]},"good":{"text":"A strong performance. {actor_1} backed down publicly.","effects":{"stability":8,"morale":5,"cohesion":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The challenge made you stronger. {actor_1} became an unlikely ally.","effects":{"stability":12,"morale":8,"cohesion":6},"flags_set":["leadership_tested"],"flags_cleared":[]}}},{"id":"b","text_template":"Propose a council. Share the burden.","immediate_effects":{},"community_scores":{"commonwealth":4,"archive":2,"throne":-2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"knowledge","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The council devolved into factionalism immediately.","effects":{"stability":-15,"cohesion":-12},"flags_set":[],"flags_cleared":[]},"bad":{"text":"The council formed but is ineffective. More voices, less clarity.","effects":{"stability":-5,"morale":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The council is functional. {actor_1} has a seat. Things are slower but less fragile.","effects":{"stability":4,"cohesion":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"A genuine improvement. Distributed leadership suits the community.","effects":{"stability":8,"cohesion":8,"morale":5},"flags_set":["council_established"],"flags_cleared":[]},"exceptional":{"text":"The council became an institution. This community has real governance now.","effects":{"stability":14,"cohesion":10,"morale":8,"knowledge":5},"flags_set":["council_established"],"flags_cleared":[]}}},{"id":"c","text_template":"Step back. Let {actor_1} lead.","immediate_effects":{},"community_scores":{"commonwealth":2,"kindred":1,"throne":-3},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"{actor_1} was not ready for it. The community unravelled without a clear centre.","effects":{"stability":-18,"morale":-15,"cohesion":-12},"flags_set":[],"flags_cleared":[]},"bad":{"text":"{actor_1} is trying. It is not going well yet.","effects":{"stability":-8,"morale":-6},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A quiet handover. {actor_1} is learning. You are still here.","effects":{"morale":3,"stability":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"{actor_1} proved more capable than the crisis suggested. A genuine succession.","effects":{"morale":8,"cohesion":6,"stability":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"A rare thing — a peaceful transfer of power that made the community stronger.","effects":{"morale":12,"cohesion":10,"stability":8},"flags_set":["succession_completed"],"flags_cleared":[]}}}]'
	)

	# Event 5: Fire
	_insert_tier3_event("tier3_fire", "Fire", "resource", '{"min_game_day":10}', a1, 90, 1.0,
		'Fire. It started in {building} and spread faster than anyone could react.\n\nPeople are out of the building, but the structure and everything in it may be lost.\n\nThere is still time to attempt a rescue of supplies — at risk.',
		'[{"id":"a","text_template":"Rush in. Save what you can.","immediate_effects":{},"community_scores":{"bastion":2,"kindred":1},"roll":{"relevant_stats":[{"stat":"health","weight":0.8},{"stat":"security","weight":0.6}],"base_value":0.0,"context_bonuses":[{"condition":"actor_has_skill:combat","bonus":0.3}]},"outcomes":{"catastrophic":{"text":"{actor_1} was badly burned. The supplies were already gone.","effects":{"health":-20,"resources":-25,"morale":-15},"flags_set":["actor_1:injured"],"flags_cleared":[]},"bad":{"text":"Some supplies saved but {actor_1} was hurt in the process.","effects":{"resources":-15,"health":-10},"flags_set":["actor_1:injured"],"flags_cleared":[]},"mixed":{"text":"A frantic rescue. Half the supplies saved, everyone got out.","effects":{"resources":-10,"morale":-5},"flags_set":[],"flags_cleared":[]},"good":{"text":"A brave effort. Most supplies recovered before the collapse.","effects":{"resources":-5,"morale":6},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Everything critical was saved. The building is gone but nothing irreplaceable was lost.","effects":{"morale":10,"cohesion":5},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Controlled burn. Contain it, accept the loss.","immediate_effects":{"resources":-15},"community_scores":{"archive":2,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"knowledge","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The fire jumped the containment. It spread to a second structure.","effects":{"resources":-20,"morale":-18},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Contained, but just barely. The loss was total for that building.","effects":{"morale":-10},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The fire burned itself out within the containment. Damage limited.","effects":{"morale":-5},"flags_set":[],"flags_cleared":[]},"good":{"text":"Clean containment. The community handled it with discipline.","effects":{"stability":6,"morale":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Textbook firebreak. The community learned something valuable about crisis response.","effects":{"stability":10,"knowledge":6,"morale":5},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Evacuate everything. People and supplies, out now.","immediate_effects":{},"community_scores":{"commonwealth":2,"kindred":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"morale","weight":0.6}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The evacuation was chaos. People were trampled, supplies scattered.","effects":{"health":-15,"resources":-18,"morale":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Everyone got out but the supplies did not.","effects":{"resources":-20,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A messy evacuation. Most people safe, some supplies saved.","effects":{"resources":-12,"morale":-4},"flags_set":[],"flags_cleared":[]},"good":{"text":"An orderly evacuation. People and critical supplies all safe.","effects":{"resources":-5,"cohesion":5,"morale":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The evacuation was seamless. Everyone helped everyone. Nothing critical lost.","effects":{"cohesion":10,"morale":8},"flags_set":[],"flags_cleared":[]}}},{"id":"d","text_template":"Stand back. Let it burn. No one goes near it.","immediate_effects":{"resources":-22},"community_scores":{"rewilded":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The fire spread anyway. Standing back cost more than it saved.","effects":{"resources":-10,"morale":-18},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Total loss. The community watches their work burn in silence.","effects":{"morale":-12},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"It burned out on its own. Nobody hurt. Everything in it is gone.","effects":{"morale":-8},"flags_set":[],"flags_cleared":[]},"good":{"text":"Nobody hurt. That was the right call. Supplies can be rebuilt.","effects":{"morale":3},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The fire burned clean and left usable foundations. Rebuilding will be easier than expected.","effects":{"morale":5,"knowledge":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 6: The Long Winter
	_insert_tier3_event("tier3_winter_crisis", "The Long Winter", "resource", '{"required_state_tags":["season_winter"],"min_game_day":20}', null, 60, 1.0,
		'Winter has settled in and it is worse than anyone predicted. The cold is relentless, supplies are dwindling, and the days are short and dark.\n\nSomething has to change or the community will not see spring.',
		'[{"id":"a","text_template":"Desperate foraging expedition into the frozen landscape.","immediate_effects":{},"community_scores":{"rewilded":3,"kindred":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"health","weight":0.6}],"base_value":-0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The foragers returned frostbitten and empty-handed. One did not return at all.","effects":{"health":-22,"morale":-18,"food":-5},"flags_set":[],"flags_cleared":[]},"bad":{"text":"A brutal outing. Little found, several people weakened by exposure.","effects":{"health":-12,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Some preserved stores found in an abandoned building. Enough for a few more days.","effects":{"food":15,"health":-5},"flags_set":[],"flags_cleared":[]},"good":{"text":"A sheltered cache discovered under snow. Real provisions.","effects":{"food":30,"morale":8},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"An extraordinary find — a sealed cellar full of preserved food. Winter suddenly looks survivable.","effects":{"food":50,"morale":15,"knowledge":4},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Strict winter rationing. Cut consumption to the bone.","immediate_effects":{"morale":-10},"community_scores":{"bastion":2,"archive":2},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"cohesion","weight":0.6}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"People broke into the reserves at night. Trust shattered along with the lock.","effects":{"food":-15,"cohesion":-18,"stability":-12},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Rationing held but the community is fraying at the edges.","effects":{"cohesion":-10,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Hard days. Hunger is constant but controlled. The community endures.","effects":{"morale":-5,"stability":5},"flags_set":[],"flags_cleared":[]},"good":{"text":"Disciplined rationing extended supplies meaningfully. People are hungry but alive.","effects":{"stability":8,"cohesion":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The shared sacrifice brought people closer. Winter became a bonding experience.","effects":{"stability":10,"cohesion":10,"morale":3},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Send a group to appeal to any nearby settlements for winter aid.","immediate_effects":{},"community_scores":{"commonwealth":3,"exchange":2},"roll":{"relevant_stats":[{"stat":"reputation","weight":1.0}],"base_value":0.0,"context_bonuses":[{"condition":"flag:raid_turned_trade","bonus":0.4}]},"outcomes":{"catastrophic":{"text":"The group was robbed on the road. They returned with less than they left with.","effects":{"resources":-15,"health":-10,"morale":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"No one would help. The journey was wasted.","effects":{"morale":-12,"health":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A small amount of help. Barely worth the trip, but something.","effects":{"food":10,"reputation":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"A neighbouring group shared winter stores. Kindness in the cold.","effects":{"food":25,"morale":8,"reputation":8},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"A winter alliance formed. Shared shelters, shared food. Both communities stronger.","effects":{"food":35,"morale":12,"reputation":12,"cohesion":5},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 7: Mass Departure
	_insert_tier3_event("tier3_mass_departure", "Exodus", "social", '{"required_state_tags":["morale_low"],"min_game_day":45}', a1, 60, 1.0,
		'It is not one or two people this time. A significant group — nearly a third of the community — has packed their things.\n\n{actor_1} is among them, and they are not asking permission. They are leaving at dawn.',
		'[{"id":"a","text_template":"Block the exit. No one leaves.","immediate_effects":{"stability":3},"community_scores":{"throne":3,"bastion":2},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"security","weight":0.6}],"base_value":0.0,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The confrontation turned violent. People were hurt on both sides. They left anyway.","effects":{"cohesion":-22,"morale":-20,"health":-10,"stability":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"They stayed but under protest. The community feels like a prison now.","effects":{"morale":-15,"cohesion":-12},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Some stayed, some left. The community is smaller but the worst was avoided.","effects":{"morale":-8,"cohesion":-6},"flags_set":[],"flags_cleared":[]},"good":{"text":"The show of authority worked. People reconsidered. Most stayed.","effects":{"stability":8,"morale":-5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The confrontation became a conversation. Grievances aired, compromises made. Nobody left.","effects":{"stability":10,"cohesion":8,"morale":5},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Let them go. Wish them well.","immediate_effects":{"morale":-8},"community_scores":{"commonwealth":2,"kindred":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"morale","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"More left than expected. The community is barely viable now.","effects":{"morale":-18,"cohesion":-15,"stability":-12},"flags_set":[],"flags_cleared":[]},"bad":{"text":"They left and took critical skills with them. The gap is felt immediately.","effects":{"morale":-10,"knowledge":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A painful parting. Those who stayed are quieter but committed.","effects":{"morale":-5,"cohesion":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"A clean separation. The remaining community is smaller but more cohesive.","effects":{"cohesion":8,"morale":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The departure was amicable. They promised to keep in contact. Two communities instead of one fractured one.","effects":{"cohesion":10,"morale":6,"reputation":5},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Ask what it would take for them to stay.","immediate_effects":{},"community_scores":{"commonwealth":3,"congregation":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.8}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The demands were impossible. The negotiation made everything worse. They left angrier than before.","effects":{"morale":-18,"cohesion":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Some demands met, but resentment runs deep. A fragile truce.","effects":{"morale":-8,"stability":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Compromises on both sides. Most stayed. The underlying issues remain.","effects":{"morale":-4,"cohesion":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"Real issues were addressed. {actor_1} agreed to stay and help fix things.","effects":{"morale":8,"cohesion":8,"stability":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The crisis became a turning point. Genuine reform. The community is stronger for having faced this.","effects":{"morale":12,"cohesion":12,"stability":8},"flags_set":["exodus_resolved"],"flags_cleared":[]}}}]'
	)

	# Event 8: The Column
	_insert_tier3_event("tier3_strangers_army", "The Column", "external", '{"min_game_day":60}', null, 60, 1.0,
		'A large organised group has been spotted moving through the area. Fifty people, maybe more. Armed. Disciplined. They have vehicles.\n\nThey have not noticed the community yet. Or if they have, they have not acted on it.',
		'[{"id":"a","text_template":"Make contact. Find out who they are.","immediate_effects":{},"community_scores":{"commonwealth":3,"exchange":2},"roll":{"relevant_stats":[{"stat":"reputation","weight":0.8},{"stat":"security","weight":0.6}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"They were hostile. Making contact revealed your position. An attack is coming.","effects":{"security":-20,"morale":-18,"resources":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"They were not interested in friendship. Your scouts were detained for a day before being released.","effects":{"security":-8,"morale":-10},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A tense encounter. They are passing through. They want nothing from you and offer nothing.","effects":{"morale":-4},"flags_set":[],"flags_cleared":[]},"good":{"text":"They are traders with a military escort. A brief but productive exchange.","effects":{"resources":12,"reputation":8,"morale":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"A well-organised trade caravan. They added your location to their route. Expect return visits.","effects":{"resources":20,"reputation":15,"morale":10},"flags_set":["trade_route_established"],"flags_cleared":[]}}},{"id":"b","text_template":"Hide. Complete concealment until they pass.","immediate_effects":{"morale":-5},"community_scores":{"rewilded":3,"archive":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"They found the settlement while searching for water. The concealment made you look suspicious.","effects":{"security":-15,"resources":-15,"morale":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"They passed nearby. Too close. The stress of hiding was extreme.","effects":{"morale":-12,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"They passed without incident. The community breathes again.","effects":{"morale":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"Complete concealment. They moved on without ever knowing you were here.","effects":{"morale":5,"security":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Not only did they pass, but your scouts learned their patrol patterns. Valuable intelligence.","effects":{"security":10,"knowledge":8,"morale":5},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Fortify. Prepare for the worst.","immediate_effects":{"resources":-10},"community_scores":{"bastion":4,"throne":1},"roll":{"relevant_stats":[{"stat":"security","weight":1.0},{"stat":"stability","weight":0.6}],"base_value":0.1,"context_bonuses":[{"condition":"actor_has_skill:combat","bonus":0.3}]},"outcomes":{"catastrophic":{"text":"The fortification drew attention. They interpreted it as hostile and attacked.","effects":{"security":-15,"health":-18,"resources":-20},"flags_set":[],"flags_cleared":[]},"bad":{"text":"A tense standoff. They moved on but the community is shaken.","effects":{"morale":-10,"resources":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"They saw the defences and decided you were not worth the trouble.","effects":{"security":5,"morale":-4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The fortifications held. They passed without testing them. The investment paid off.","effects":{"security":10,"morale":6},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Your defences impressed them. They sent an envoy offering a mutual defence pact.","effects":{"security":15,"reputation":10,"morale":8},"flags_set":["defence_pact"],"flags_cleared":[]}}}]'
	)

	# Event 9: What We Found
	_insert_tier3_event("tier3_discovery", "What We Found", "knowledge", '{"min_game_day":45}', a1_eng, 90, 1.0,
		'{actor_1} found something significant in an expedition beyond the perimeter. A working facility — partially intact equipment, technical documents, maybe even power.\n\nIt could change everything. But exploiting it will take resources the community can barely spare.',
		'[{"id":"a","text_template":"Commit everything. This is worth the risk.","immediate_effects":{"resources":-20},"community_scores":{"archive":4,"exchange":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.0},{"stat":"resources","weight":0.6}],"base_value":0.1,"context_bonuses":[{"condition":"actor_has_skill:engineering","bonus":0.4}]},"outcomes":{"catastrophic":{"text":"The facility was unstable. An accident destroyed most of what was there and injured the team.","effects":{"health":-18,"resources":-10,"morale":-15},"flags_set":["actor_1:injured"],"flags_cleared":[]},"bad":{"text":"More was needed than expected. Resources spent, little gained.","effects":{"resources":-8,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Partial success. Some equipment salvaged, some knowledge gained. The facility is depleted.","effects":{"knowledge":8,"morale":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"A real breakthrough. Working equipment and documented processes that will help for months.","effects":{"knowledge":15,"resources":10,"morale":8},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Everything worked. A generator, medical supplies, technical manuals. A watershed moment.","effects":{"knowledge":20,"resources":15,"health":10,"morale":12},"flags_set":["major_discovery"],"flags_cleared":[]}}},{"id":"b","text_template":"Secure it. Guard it. Use it gradually.","immediate_effects":{"resources":-8},"community_scores":{"bastion":2,"archive":2},"roll":{"relevant_stats":[{"stat":"security","weight":0.8},{"stat":"stability","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Others found it first. By the time your guards arrived, it was stripped.","effects":{"resources":-5,"morale":-18,"security":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Securing it stretched the community thin. The ongoing cost is significant.","effects":{"security":-8,"morale":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Secured and slowly yielding value. A long-term investment.","effects":{"knowledge":5,"security":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"A steady stream of useful materials and knowledge. Well worth the guard rotation.","effects":{"knowledge":10,"resources":8,"morale":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The facility became a permanent asset. A second location, defended and productive.","effects":{"knowledge":15,"resources":12,"security":5,"morale":10},"flags_set":["outpost_established"],"flags_cleared":[]}}},{"id":"c","text_template":"Share the location with nearby groups. Knowledge should be shared.","immediate_effects":{},"community_scores":{"commonwealth":4,"exchange":2,"archive":1},"roll":{"relevant_stats":[{"stat":"reputation","weight":1.0},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The other groups took everything and left nothing. Generosity exploited.","effects":{"resources":-15,"morale":-18,"reputation":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Shared, but others took more than their fair portion. Resentment lingers.","effects":{"morale":-8,"reputation":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"An uneasy sharing arrangement. Not ideal but functional.","effects":{"reputation":5,"knowledge":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Shared access built real trust with neighbouring groups. Knowledge flowed both ways.","effects":{"reputation":12,"knowledge":10,"morale":6},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The shared facility became a hub. A meeting place. The beginning of something larger than one community.","effects":{"reputation":18,"knowledge":12,"morale":10,"cohesion":5},"flags_set":["knowledge_hub"],"flags_cleared":[]}}}]'
	)

	# Event 10: The Cost
	_insert_tier3_event("tier3_sacrifice_demanded", "The Cost", "moral", '{"min_game_day":90}', a1, 60, 1.0,
		'The crisis is clear and the solution is clear. But the cost falls unfairly on one person.\n\n{actor_1} is the one who would bear it — the dangerous task, the personal sacrifice, the loss that cannot be undone.\n\nThe community needs this. But is it right to ask?',
		'[{"id":"a","text_template":"Ask {actor_1} to do it. Explain why it matters.","immediate_effects":{},"community_scores":{"commonwealth":2,"congregation":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"morale","weight":0.6}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"{actor_1} agreed. It went wrong. The sacrifice was made and it was not enough.","effects":{"morale":-22,"cohesion":-15,"health":-10},"flags_set":["actor_1:injured"],"flags_cleared":[]},"bad":{"text":"{actor_1} did it. The community survived. But the cost to one person was too high.","effects":{"morale":-12,"cohesion":-5},"flags_set":["actor_1:sacrificed"],"flags_cleared":[]},"mixed":{"text":"{actor_1} accepted. The crisis passed. The community is grateful but uncomfortable.","effects":{"morale":-5,"stability":5},"flags_set":[],"flags_cleared":[]},"good":{"text":"{actor_1} stepped up willingly. The community honoured the sacrifice.","effects":{"morale":6,"cohesion":8,"stability":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"{actor_1} not only accepted but found a way to minimise the cost. Courage and ingenuity together.","effects":{"morale":12,"cohesion":10,"stability":8},"flags_set":["hero_emerged"],"flags_cleared":[]}}},{"id":"b","text_template":"Find another way. No one should bear this alone.","immediate_effects":{},"community_scores":{"commonwealth":3,"kindred":2},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"stability","weight":0.6}],"base_value":0.0,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"There was no other way. The delay made everything worse.","effects":{"resources":-20,"health":-15,"morale":-18},"flags_set":[],"flags_cleared":[]},"bad":{"text":"An alternative was found but it cost more overall. The burden was spread but heavier.","effects":{"resources":-15,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A workable alternative. More expensive but fairer. The community accepts the cost.","effects":{"resources":-10,"morale":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"A creative solution that avoided the worst of it. Nobody bore an unfair burden.","effects":{"morale":8,"cohesion":6,"knowledge":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Not only was an alternative found, it was better than the original plan. Innovation born from ethics.","effects":{"morale":12,"knowledge":10,"cohesion":8},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Order it done. The community comes first.","immediate_effects":{"stability":3},"community_scores":{"throne":3,"bastion":2},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The order was carried out. {actor_1} was broken by it. Others saw and will not forget.","effects":{"morale":-20,"cohesion":-18,"stability":-10},"flags_set":["actor_1:injured"],"flags_cleared":[]},"bad":{"text":"Done. The community survived. But the way it was done will haunt people.","effects":{"morale":-12,"cohesion":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"An ugly necessity. People understand why but do not feel good about it.","effects":{"morale":-6,"stability":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Decisive leadership in a crisis. People respect the willingness to make hard calls.","effects":{"stability":10,"morale":3},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The decisiveness was exactly what was needed. Even {actor_1} understood.","effects":{"stability":12,"morale":6,"cohesion":5},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 11: The Split
	_insert_tier3_event("tier3_schism", "The Split", "social", '{"required_state_tags":["cohesion_low"],"min_game_day":60}', a1, 60, 1.0,
		'The community has fractured. Two clear factions have formed — those who follow {actor_1} and those who do not.\n\nMeals are eaten separately. Work assignments are contested. The tension is constant.',
		'[{"id":"a","text_template":"Force unity. One community, one set of rules.","immediate_effects":{"stability":3},"community_scores":{"bastion":3,"throne":2},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"security","weight":0.6}],"base_value":0.0,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Forced unity broke into open conflict. People were hurt. The split deepened.","effects":{"cohesion":-22,"morale":-20,"health":-8},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Compliance without agreement. The factions still exist but are quieter about it.","effects":{"cohesion":-8,"morale":-12},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A fragile peace imposed by authority. It holds for now.","effects":{"cohesion":-4,"stability":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The firmness worked. People needed someone to end the ambiguity.","effects":{"stability":10,"cohesion":6,"morale":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Unity restored through strength. Both factions found common ground under pressure.","effects":{"stability":14,"cohesion":12,"morale":8},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Let them separate. Two groups, shared territory.","immediate_effects":{},"community_scores":{"commonwealth":2,"kindred":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"morale","weight":0.6}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Separation became hostility. Two groups competing for the same resources.","effects":{"cohesion":-20,"resources":-15,"security":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Separate but unequal. One group got more, resentment followed.","effects":{"cohesion":-10,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"An uncomfortable arrangement. Two groups, one territory. Functional but tense.","effects":{"cohesion":-4,"stability":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The separation reduced friction. Two groups working in parallel, sharing resources fairly.","effects":{"cohesion":5,"morale":6},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"An unexpected benefit — the two groups developed complementary specialisations.","effects":{"cohesion":8,"morale":8,"knowledge":5},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Mediate. Build a structure both sides can accept.","immediate_effects":{},"community_scores":{"commonwealth":4,"archive":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"knowledge","weight":0.6}],"base_value":0.1,"context_bonuses":[{"condition":"flag:council_established","bonus":0.4}]},"outcomes":{"catastrophic":{"text":"Mediation failed. Both sides felt the process was rigged. Worse than before.","effects":{"cohesion":-18,"morale":-15,"stability":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"A framework was proposed. Neither side is satisfied. Grudging compliance at best.","effects":{"cohesion":-5,"morale":-6},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A workable agreement. Not peace, but a ceasefire with rules.","effects":{"cohesion":3,"stability":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Real mediation success. {actor_1} and the other faction found genuine compromise.","effects":{"cohesion":10,"morale":8,"stability":6},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The mediation transformed the community. A new charter, written together. Stronger for having broken apart.","effects":{"cohesion":15,"morale":12,"stability":10},"flags_set":["community_charter"],"flags_cleared":[]}}}]'
	)

	# Event 12: Patient Zero
	_insert_tier3_event("tier3_plague_vector", "Patient Zero", "health", '{"required_world_tags":["contagion"],"min_game_day":30}', a1, 90, 1.0,
		'The source of the ongoing illness has been identified. {actor_1} is carrying it — possibly immune, but spreading it to everyone they contact.\n\nThe community is watching. What happens next will define who you are.',
		'[{"id":"a","text_template":"Permanent isolation for {actor_1}. Protect the community.","immediate_effects":{},"community_scores":{"bastion":3,"archive":2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"health","weight":0.8}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Isolation became imprisonment. {actor_1} suffered. Others began to question everything.","effects":{"health":-8,"morale":-20,"cohesion":-15},"flags_set":["actor_1:isolated"],"flags_cleared":[]},"bad":{"text":"Isolation contained the spread but the moral cost was high.","effects":{"health":5,"morale":-12,"cohesion":-8},"flags_set":["actor_1:isolated"],"flags_cleared":[]},"mixed":{"text":"{actor_1} accepted isolation. The illness stopped spreading. An uneasy solution.","effects":{"health":8,"morale":-6},"flags_set":["actor_1:isolated"],"flags_cleared":[]},"good":{"text":"Managed isolation with regular contact and care. The illness stopped and dignity preserved.","effects":{"health":12,"morale":4,"cohesion":3},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Study of {actor_1} during isolation revealed a treatment. The carrier became the cure.","effects":{"health":18,"knowledge":10,"morale":8},"flags_set":["disease_protocol_established"],"flags_cleared":[]}}},{"id":"b","text_template":"Keep {actor_1} integrated. Treat the symptoms, accept the risk.","immediate_effects":{},"community_scores":{"commonwealth":3,"congregation":2},"roll":{"relevant_stats":[{"stat":"health","weight":1.0},{"stat":"morale","weight":0.6}],"base_value":0.0,"context_bonuses":[{"condition":"actor_has_skill:medicine","bonus":0.4}]},"outcomes":{"catastrophic":{"text":"The illness spread wildly. Half the community is now sick. {actor_1} is blamed.","effects":{"health":-25,"morale":-18,"cohesion":-12},"flags_set":[],"flags_cleared":[]},"bad":{"text":"More people got sick. The community managed but barely.","effects":{"health":-15,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The illness spread further but remained manageable. A risky but humane choice.","effects":{"health":-8,"cohesion":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Remarkably, keeping {actor_1} integrated maintained trust. The illness was treated successfully.","effects":{"health":5,"morale":8,"cohesion":8},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The community rallied around {actor_1}. The illness ran its course. No one was left behind.","effects":{"health":8,"morale":12,"cohesion":12},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Ask {actor_1} to leave voluntarily. For everyone.","immediate_effects":{},"community_scores":{"kindred":1,"throne":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.8}],"base_value":0.1,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"{actor_1} left. The illness did not stop. The sacrifice was meaningless.","effects":{"health":-10,"morale":-22,"cohesion":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"{actor_1} left with visible pain. The community is healthier but ashamed.","effects":{"health":5,"morale":-15,"cohesion":-10},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"{actor_1} agreed to go. The illness stopped spreading. The cost was a person.","effects":{"health":8,"morale":-8},"flags_set":[],"flags_cleared":[]},"good":{"text":"{actor_1} left with dignity. Supplies were shared. A painful but respectful parting.","effects":{"health":10,"morale":-3,"reputation":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"{actor_1} found another group nearby and was welcomed. Still in contact. Still alive.","effects":{"health":12,"morale":5,"reputation":8},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 13: Something That Works
	_insert_tier3_event("tier3_infrastructure", "Something That Works", "resource", '{"min_game_day":45}', a1_eng, 60, 1.0,
		'{actor_1} has been working on something. A well, a greenhouse, a generator — real infrastructure that could transform daily life.\n\nBut finishing it requires a massive commitment of resources and labour. The community would need to pause almost everything else.',
		'[{"id":"a","text_template":"Full commitment. Build it now.","immediate_effects":{"resources":-25},"community_scores":{"archive":3,"exchange":2},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.0},{"stat":"stability","weight":0.6}],"base_value":0.1,"context_bonuses":[{"condition":"actor_has_skill:engineering","bonus":0.4}]},"outcomes":{"catastrophic":{"text":"The project failed catastrophically. Resources wasted, morale destroyed.","effects":{"resources":-10,"morale":-22,"stability":-12},"flags_set":[],"flags_cleared":[]},"bad":{"text":"It partially works. Not the transformation hoped for. Resources heavily depleted.","effects":{"morale":-8,"resources":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"It works. Barely. Needs constant maintenance but provides real value.","effects":{"resources":8,"morale":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"A genuine success. {actor_1} built something that will serve the community for a long time.","effects":{"resources":18,"morale":10,"knowledge":6},"flags_set":["infrastructure_built"],"flags_cleared":[]},"exceptional":{"text":"Beyond expectations. It works better than planned and inspired other projects.","effects":{"resources":25,"morale":15,"knowledge":10,"stability":5},"flags_set":["infrastructure_built"],"flags_cleared":[]}}},{"id":"b","text_template":"Partial investment. Build slowly alongside other work.","immediate_effects":{"resources":-10},"community_scores":{"archive":1,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"knowledge","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The slow build stalled. Resources spent, nothing finished. Morale suffered.","effects":{"morale":-12,"resources":-5},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Progress is glacial. People are losing faith in the project.","effects":{"morale":-6},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Slow but steady progress. It will take time but the foundation is solid.","effects":{"knowledge":4,"morale":2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The balanced approach worked. Infrastructure built without disrupting other critical work.","effects":{"resources":10,"morale":6,"knowledge":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The methodical approach yielded a better design. It works and it taught skills to others.","effects":{"resources":15,"morale":8,"knowledge":8},"flags_set":["infrastructure_built"],"flags_cleared":[]}}},{"id":"c","text_template":"Postpone. The community cannot afford this right now.","immediate_effects":{},"community_scores":{"bastion":1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"{actor_1} was devastated. The project was abandoned and the materials scattered.","effects":{"morale":-15,"cohesion":-8},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Postponed. {actor_1} is disappointed. The materials sit unused.","effects":{"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A sensible delay. {actor_1} understands but is not happy about it.","effects":{"morale":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The delay allowed better planning. When the time comes, it will be done right.","effects":{"knowledge":4,"morale":2},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"During the delay, {actor_1} found a way to build it with far fewer resources.","effects":{"knowledge":8,"morale":6},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 14: The Question
	_insert_tier3_event("tier3_the_child", "The Question", "social", '{"required_state_tags":["recent_birth"],"min_game_day":180}', null, 120, 1.0,
		'A child born after the apocalypse asked a question today that stopped everyone.\n\n"What was the old world like?"\n\nThe adults looked at each other. The answer to this question will shape how the next generation understands everything.',
		'[{"id":"a","text_template":"Tell them the truth. All of it.","immediate_effects":{},"community_scores":{"archive":4,"commonwealth":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.0},{"stat":"cohesion","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The truth was too much. Fear spread. Children now have nightmares about a world they never knew.","effects":{"morale":-18,"cohesion":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Honesty without context. The children are confused and scared.","effects":{"morale":-10,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A difficult conversation. The children understand more now. Whether that is good remains to be seen.","effects":{"knowledge":5,"morale":-3},"flags_set":[],"flags_cleared":[]},"good":{"text":"Truth told with care. The children understand where they came from and why this matters.","effects":{"knowledge":10,"cohesion":6,"morale":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The truth became a foundation story. The community gained a shared narrative about who they are and why.","effects":{"knowledge":12,"cohesion":10,"morale":8},"flags_set":["founding_story"],"flags_cleared":[]}}},{"id":"b","text_template":"Tell them a simplified, hopeful version.","immediate_effects":{},"community_scores":{"congregation":3,"kindred":2},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.6}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"The simplified story was caught as a lie by older children. Trust in adults collapsed.","effects":{"cohesion":-15,"morale":-12},"flags_set":[],"flags_cleared":[]},"bad":{"text":"A comfortable story but it rings false. Questions persist.","effects":{"morale":-5,"knowledge":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The children accepted the story. For now, innocence is preserved.","effects":{"morale":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"A story of hope that inspired the children without crushing them. Well calibrated.","effects":{"morale":10,"cohesion":6},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The hopeful story became a community myth — not a lie but a purpose. We are building something better.","effects":{"morale":14,"cohesion":10,"stability":5},"flags_set":["community_myth"],"flags_cleared":[]}}},{"id":"c","text_template":"Tell them to focus on the world they have, not the one that was lost.","immediate_effects":{},"community_scores":{"rewilded":3,"bastion":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"morale","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Dismissing the question hurt. The children feel their curiosity is unwelcome.","effects":{"morale":-12,"cohesion":-8},"flags_set":[],"flags_cleared":[]},"bad":{"text":"The deflection was noticed. Adults divided on whether the children deserve answers.","effects":{"cohesion":-5,"morale":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A pragmatic answer. The children turned their attention forward. The question lingers.","effects":{"stability":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The forward focus resonated. This is their world. They will make of it what they can.","effects":{"morale":8,"stability":8},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The children embraced the present fully. They began contributing ideas for how to make things better.","effects":{"morale":12,"stability":10,"knowledge":5},"flags_set":["new_generation"],"flags_cleared":[]}}}]'
	)

	# Event 15: Full Breakdown (escalation target from tier2_work_refusal)
	_insert_tier3_event("tier3_full_breakdown", "Everything at Once", "governance", '{"required_state_tags":["stability_low","morale_low"],"min_game_day":30}', a1, 45, 1.0,
		'Everything is falling apart at the same time. Work has stopped. Arguments have turned into shouting matches. Two people have already packed their things.\n\n{actor_1} is at the centre of it, but this is bigger than one person. This is the moment where the community either holds together or comes apart.',
		'[{"id":"a","text_template":"Take control. Direct orders, clear structure, no debate.","immediate_effects":{"stability":5},"community_scores":{"throne":4,"bastion":2},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"security","weight":0.6}],"base_value":0.0,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Authority without trust. People broke. Some left. Some fought. The centre did not hold.","effects":{"stability":-25,"cohesion":-22,"morale":-20},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Order restored at the cost of trust. People comply but do not believe.","effects":{"stability":-8,"morale":-15,"cohesion":-10},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A shaky peace. The crisis passed but the underlying problems remain.","effects":{"stability":4,"morale":-8},"flags_set":[],"flags_cleared":[]},"good":{"text":"Decisive leadership in the worst moment. People needed direction and got it.","effects":{"stability":12,"morale":5,"cohesion":4},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"A defining moment. You stood in the gap and held everything together through sheer will.","effects":{"stability":18,"morale":10,"cohesion":8},"flags_set":["crisis_leader"],"flags_cleared":[]}}},{"id":"b","text_template":"Call everyone together. Let everything be said.","immediate_effects":{},"community_scores":{"commonwealth":4,"congregation":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"morale","weight":0.8}],"base_value":0.1,"context_bonuses":[{"condition":"flag:council_established","bonus":0.4}]},"outcomes":{"catastrophic":{"text":"The meeting became a forum for blame. People said things that cannot be taken back.","effects":{"cohesion":-22,"morale":-20,"stability":-15},"flags_set":[],"flags_cleared":[]},"bad":{"text":"Too much said, too little resolved. The community is more fragmented than before.","effects":{"cohesion":-10,"morale":-10},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A brutal meeting. Everything was aired. Nothing was solved but nothing is hidden anymore.","effects":{"cohesion":3,"morale":-6},"flags_set":[],"flags_cleared":[]},"good":{"text":"The meeting was painful but productive. Real issues named, real commitments made.","effects":{"cohesion":10,"morale":8,"stability":6},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"A cathartic reckoning. The community rebuilt its social contract from the ground up.","effects":{"cohesion":15,"morale":12,"stability":10},"flags_set":["community_rebuilt"],"flags_cleared":[]}}},{"id":"c","text_template":"Focus on one thing at a time. Start with food.","immediate_effects":{},"community_scores":{"bastion":2,"archive":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"knowledge","weight":0.6}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Ignoring the emotional crisis to focus on logistics was tone-deaf. People snapped.","effects":{"morale":-18,"cohesion":-15,"stability":-10},"flags_set":[],"flags_cleared":[]},"bad":{"text":"The practical approach helped with supplies but not with the underlying anger.","effects":{"morale":-8,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Food sorted. Security sorted. The emotional damage remains but survival is stabilised.","effects":{"stability":5,"morale":-4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Pragmatism won. Once people saw progress on practical problems, the emotional temperature dropped.","effects":{"stability":10,"morale":6,"resources":5},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"The practical focus became a unifying force. Working together on real problems healed what talking could not.","effects":{"stability":14,"morale":10,"cohesion":8,"resources":5},"flags_set":[],"flags_cleared":[]}}},{"id":"d","text_template":"Step back entirely. Let {actor_1} and the community sort it out.","immediate_effects":{},"community_scores":{"kindred":2,"rewilded":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"morale","weight":0.6}],"base_value":0.0,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"Without leadership, chaos. The community splintered. Some left. Nothing was resolved.","effects":{"stability":-22,"cohesion":-20,"morale":-18},"flags_set":[],"flags_cleared":[]},"bad":{"text":"The vacuum was filled poorly. {actor_1} tried but did not have the standing to lead.","effects":{"stability":-12,"morale":-10},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Things settled on their own eventually. A messy, organic recovery.","effects":{"stability":-3,"cohesion":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The community found its own way through. Grassroots resilience.","effects":{"cohesion":8,"morale":6},"flags_set":[],"flags_cleared":[]},"exceptional":{"text":"Stepping back was the right call. The community self-organised and emerged genuinely stronger.","effects":{"cohesion":12,"morale":10,"stability":5},"flags_set":["self_governing"],"flags_cleared":[]}}}]'
	)

	# Event 16: Self-Sacrifice — "Someone Has to Stay"
	_library_db.query_with_bindings(
		"INSERT INTO events (id, tier, category, title, eligibility, description_template, actor_requirements, choices, chain_id, chain_stage, chain_memory_schema, cooldown_days, exclusion_group, max_occurrences, content_tags, seasonal_tags, weight) VALUES (?, 3, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, NULL, ?, NULL, NULL, ?);",
		["tier3_self_sacrifice", "moral", "Someone Has to Stay",
		'{"min_game_day":180}',
		'There is a situation from which the community can escape — but only if someone stays behind. The task is dangerous and almost certainly fatal.\n\nNobody is asking you. But you are the leader, and you can see what needs to be done.',
		null,
		'[{"id":"a","text_template":"You' + "'" + 'll stay. Send the others ahead.","immediate_effects":{"morale":15,"cohesion":10},"community_scores":{"commonwealth":3,"kindred":3,"congregation":3},"roll":{"relevant_stats":[],"base_value":0.0},"outcomes":{"good":{"text":"You stayed. The others went ahead. They didn' + "'" + 't look back — you told them not to.","effects":{}}},"_self_sacrifice":true},{"id":"b","text_template":"Call for a volunteer. You won' + "'" + 't order anyone to die.","immediate_effects":{},"community_scores":{"commonwealth":4,"kindred":2},"roll":{"relevant_stats":[{"stat":"morale","weight":1.0},{"stat":"cohesion","weight":0.8}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"Nobody came forward. The moment passed. The community survived but something was lost.","effects":{"morale":-10,"cohesion":-8}},"mixed":{"text":"Someone stepped up. You don' + "'" + 't know their name well enough. You should have.","effects":{"morale":5,"cohesion":3}},"good":{"text":"A volunteer came forward immediately — someone you knew would. The community was saved.","effects":{"morale":12,"cohesion":8}}}},{"id":"c","text_template":"There has to be another option. Think.","immediate_effects":{},"community_scores":{"archive":3,"exchange":1},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.2},{"stat":"stability","weight":0.6}],"base_value":0.0,"context_bonuses":[]},"outcomes":{"catastrophic":{"text":"There was no other way. The delay cost everything.","effects":{"health":-20,"morale":-15,"resources":-20}},"bad":{"text":"A partial solution. Costly and incomplete.","effects":{"health":-10,"resources":-12}},"mixed":{"text":"A way out was found. Ugly and expensive, but a way.","effects":{"resources":-15}},"good":{"text":"A genuine solution emerged. The situation resolved without sacrifice.","effects":{"morale":8,"knowledge":5}},"exceptional":{"text":"The solution was elegant. The community came through it stronger.","effects":{"morale":12,"knowledge":8,"cohesion":5}}}}]',
		0, 1, 1.0]
	)


func _insert_tier4_event(id: String, title: String, category: String, eligibility: String, actor_req, weight: float, desc_template: String, choices_json: String) -> void:
	_library_db.query_with_bindings(
		"INSERT INTO events (id, tier, category, title, eligibility, description_template, actor_requirements, choices, chain_id, chain_stage, chain_memory_schema, cooldown_days, exclusion_group, max_occurrences, content_tags, seasonal_tags, weight) VALUES (?, 4, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, 0, NULL, 1, NULL, NULL, ?);",
		[id, category, title, eligibility, desc_template, actor_req, choices_json, weight]
	)


func _seed_tier4_events() -> void:
	_library_db.query("SELECT COUNT(*) AS cnt FROM events WHERE tier = 4;")
	if _library_db.query_result.size() > 0 and int(_library_db.query_result[0].get("cnt", 0)) >= 8:
		return

	var a1 := '{"actor_1":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}'

	# Event 1: Too Many Faces
	_insert_tier4_event("tier4_too_many_faces", "Too Many Faces", "governance", '{"population_min":25,"min_game_day":60}', null, 1.0,
		'The community has grown to the point where not everyone knows everyone.\nYou can see it in the way people eat — clusters now, not a single table.\nIn the small arguments that don' + "'" + 't get resolved because nobody knows who to ask.\nThis is a threshold. How you organise now will shape everything that follows.',
		'[{"id":"a","text_template":"Create a governing council. Formalise the structure.","immediate_effects":{},"community_scores":{"commonwealth":4,"archive":2},"roll":{"relevant_stats":[{"stat":"stability","weight":1.0},{"stat":"cohesion","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The council formed, but factions formed with it. The structure created the division it was meant to prevent.","effects":{"stability":-5,"cohesion":-8},"flags_set":["council_established","factional_council"],"flags_cleared":[]},"mixed":{"text":"The council is functional. Governance is slower and more visible. That is probably right.","effects":{"stability":8},"flags_set":["council_established"],"flags_cleared":[]},"good":{"text":"The council gave the community a face it could look to when things were uncertain. That turned out to matter.","effects":{"stability":12,"cohesion":6,"morale":5},"flags_set":["council_established"],"flags_cleared":[]}}},{"id":"b","text_template":"Let clusters form naturally. Recognise the ones that already exist.","immediate_effects":{},"community_scores":{"kindred":4,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"morale","weight":0.6}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The informal leaders became informal power centres. Not what you intended.","effects":{"cohesion":-6,"stability":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The clusters organised around familiar faces. Looser than a council, but it holds.","effects":{"cohesion":5,"morale":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"Organic leadership emerged. People found their place. The community scaled without losing its texture.","effects":{"cohesion":8,"morale":6,"stability":5},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"You make the decisions. One voice, one direction.","immediate_effects":{},"community_scores":{"throne":5,"bastion":2,"commonwealth":-3},"roll":{"relevant_stats":[{"stat":"stability","weight":1.2},{"stat":"morale","weight":-0.4}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The weight of it became unmanageable. The community felt the strain of a single point of failure.","effects":{"stability":-8,"morale":-8,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"You held it together. At personal cost and collective risk, but together.","effects":{"stability":6,"morale":-4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Strong central leadership suited the community at this stage. Things ran cleanly.","effects":{"stability":10,"morale":-2,"cohesion":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 2: The Child's Question
	_insert_tier4_event("tier4_childs_question", "What Was It Like?", "reflection", '{"required_state_tags":["recent_birth"],"min_game_day":120}', null, 1.0,
		'A child born after the apocalypse — old enough now to ask questions —\nhas been asking about the old world. Not with grief. With curiosity.\nWhat it looked like. What people did. What they cared about.\nThe community has gathered, quietly, to hear your answer.',
		'[{"id":"a","text_template":"Describe it fully. The abundance and the waste. The connection and the loneliness.","immediate_effects":{},"community_scores":{"archive":3,"commonwealth":3},"roll":{"relevant_stats":[{"stat":"knowledge","weight":0.8},{"stat":"cohesion","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The honesty landed harder than intended. Some people are grieving things they' + "'" + 'd stopped thinking about.","effects":{"morale":-6,"cohesion":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The community sat with it. A complicated answer to a simple question. The child seemed satisfied.","effects":{"knowledge":3,"morale":-2},"flags_set":[],"flags_cleared":[]},"good":{"text":"The full picture — beautiful and terrible — gave the community something to measure itself against. They understood what they were trying to preserve.","effects":{"knowledge":6,"morale":5,"cohesion":4},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Tell them about the things people got right. Art. Medicine. Connection.","immediate_effects":{},"community_scores":{"archive":3,"congregation":2,"rewilded":-1},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"knowledge","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The curated version felt false to people who remembered. A small fracture.","effects":{"cohesion":-4,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Hope was planted. Whether it takes root depends on what they build.","effects":{"morale":4,"knowledge":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The community found a relationship with the past that motivated rather than haunted.","effects":{"morale":8,"knowledge":5,"cohesion":5},"flags_set":["old_world_acknowledged"],"flags_cleared":[]}}},{"id":"c","text_template":"The past is past. What we build here is what they should think about.","immediate_effects":{},"community_scores":{"rewilded":4,"throne":2,"archive":-2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"morale","weight":0.4}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The forward-only answer sat poorly with people who still carried the old world in them.","effects":{"morale":-5,"cohesion":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Pragmatic. Not everyone agreed, but the community moved on.","effects":{"stability":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The community oriented itself around what it was becoming. Less haunted. More purposeful.","effects":{"stability":6,"morale":4,"cohesion":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 3: Mortality
	_insert_tier4_event("tier4_your_mortality", "Not Today, But Soon", "reflection", '{"min_game_day":365}', a1, 1.0,
		'You have not been well. Nothing dramatic — just a persistent awareness\nthat the body keeping score has noted some things. You are not dying today.\nBut the long run is shorter than it was.\n{actor_1} knows. Others may be starting to guess.\nWhat arrangements do you make?',
		'[{"id":"a","text_template":"Tell {actor_1}. Start the transfer of understanding, slowly.","immediate_effects":{},"community_scores":{"archive":3,"commonwealth":3,"kindred":2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8},{"stat":"cohesion","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"{actor_1} was not ready for the weight of it. The preparation created anxiety it was meant to prevent.","effects":{"stability":-4,"morale":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The succession is in motion. Not clean, but in motion.","effects":{"stability":5},"flags_set":["succession_planned"],"flags_cleared":[]},"good":{"text":"The quiet transfer worked. The community will not collapse when the time comes.","effects":{"stability":10,"cohesion":5,"morale":4},"flags_set":["succession_planned"],"flags_cleared":[]}}},{"id":"b","text_template":"Write it down. All of it. Let whoever comes next understand what was tried.","immediate_effects":{},"community_scores":{"archive":5,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.0}],"base_value":0.5,"context_bonuses":[]},"outcomes":{"bad":{"text":"The documentation was incomplete. The most important things resisted being written down.","effects":{"knowledge":3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A partial record. Better than nothing. Perhaps enough.","effects":{"knowledge":8},"flags_set":["legacy_documented"],"flags_cleared":[]},"good":{"text":"The record was thorough. The community will have a map of how they got here.","effects":{"knowledge":14,"stability":5},"flags_set":["legacy_documented"],"flags_cleared":[]}}},{"id":"c","text_template":"There' + "'" + 's still work to do. Worry about succession when it' + "'" + 's actually necessary.","immediate_effects":{},"community_scores":{"throne":3,"kindred":1},"roll":{"relevant_stats":[{"stat":"stability","weight":0.4},{"stat":"morale","weight":0.6}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The secret became a weight. People sensed something was wrong without knowing what.","effects":{"morale":-6,"stability":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Life continued. The question was deferred.","effects":{},"flags_set":[],"flags_cleared":[]},"good":{"text":"The community kept moving. The future can wait a little longer.","effects":{"morale":3,"stability":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 4: The Anniversary
	_insert_tier4_event("tier4_one_year", "One Year", "reflection", '{"min_game_day":365,"max_game_day":390}', null, 1.0,
		'It has been one year since the world ended.\nThe community has gathered without being asked.\nThere is no ceremony planned. Nobody knows what the right thing to do is.\nThey are looking at you.',
		'[{"id":"a","text_template":"Mark it with a ceremony. Create a ritual.","immediate_effects":{},"community_scores":{"congregation":4,"commonwealth":2,"kindred":2},"roll":{"relevant_stats":[{"stat":"morale","weight":1.0},{"stat":"cohesion","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The ceremony exposed grief people were managing by not looking at it.","effects":{"morale":-5,"cohesion":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Something was acknowledged. Not resolved, but named.","effects":{"morale":4,"cohesion":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The community found, in the ritual, something it could return to. A shared reference point.","effects":{"morale":8,"cohesion":7},"flags_set":["founding_ritual_established"],"flags_cleared":[]}}},{"id":"b","text_template":"Acknowledge it briefly. Then return to work.","immediate_effects":{},"community_scores":{"bastion":2,"archive":2,"throne":2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8}],"base_value":0.5,"context_bonuses":[]},"outcomes":{"bad":{"text":"People wanted more than acknowledgement. The brevity read as indifference.","effects":{"morale":-6,"cohesion":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Brief and functional. The community respected the practicality even if it wasn' + "'" + 't what they needed.","effects":{"stability":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The lightness of it was exactly right. People returned to work feeling anchored.","effects":{"stability":5,"morale":4},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Let people grieve. Take the day.","immediate_effects":{},"community_scores":{"kindred":4,"commonwealth":3,"rewilded":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"morale","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"Grief, unconstrained, ran deep and long. Coming back from it took time the community didn' + "'" + 't have.","effects":{"morale":-4,"cohesion":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A necessary day. The community was quieter afterward — but present.","effects":{"morale":5,"cohesion":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The day of grieving became a day of memory. People talked about who they were before. It made the after more real.","effects":{"morale":8,"cohesion":8,"stability":3},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 5: The First Generation
	_insert_tier4_event("tier4_born_after", "The First Generation", "reflection", '{"min_game_day":548}', null, 1.0,
		'There are children here who have no memory of the world before.\nThey know this settlement as simply the world — the only one there is.\nThey are watching how adults treat each other, what gets valued, what gets punished.\nThey are learning what it means to be human from what they see here.',
		'[{"id":"a","text_template":"Establish a school. Formal teaching.","immediate_effects":{},"community_scores":{"archive":5,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.0},{"stat":"stability","weight":0.6}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The school was resented as one more obligation in a life of obligations.","effects":{"morale":-4,"knowledge":4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Knowledge is being passed on. Imperfectly, but reliably.","effects":{"knowledge":10,"stability":3},"flags_set":[],"flags_cleared":[]},"good":{"text":"The school became the community' + "'" + 's investment in its own future. Something built that would outlast individuals.","effects":{"knowledge":15,"stability":6,"morale":5},"flags_set":["school_established"],"flags_cleared":[]}}},{"id":"b","text_template":"Let them learn by doing. Work alongside adults.","immediate_effects":{},"community_scores":{"kindred":4,"rewilded":3},"roll":{"relevant_stats":[{"stat":"cohesion","weight":0.8},{"stat":"morale","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"Children in adult roles showed the cracks in the adult world more clearly than anyone was comfortable with.","effects":{"morale":-3,"cohesion":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Learning by proximity. Slow, uneven, but the knowledge is lived.","effects":{"cohesion":5,"knowledge":5},"flags_set":[],"flags_cleared":[]},"good":{"text":"The apprenticeship model built bonds between generations that formal schooling might not have.","effects":{"cohesion":8,"knowledge":6,"morale":5},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 6: The Long Peace
	_insert_tier4_event("tier4_long_peace", "The Quiet Stretch", "reflection", '{"min_game_day":180,"required_state_tags":["security_good","morale_good"]}', a1, 1.0,
		'For the first time since the beginning, nothing is wrong.\nNot urgently wrong, not quietly wrong — just not wrong.\n{actor_1} said it out loud this morning, half-disbelieving: things are alright.\nThe community has a moment to choose what it does with stability.',
		'[{"id":"a","text_template":"Invest in knowledge and documentation.","immediate_effects":{"resources":-10},"community_scores":{"archive":4,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"knowledge","weight":1.0}],"base_value":0.5,"context_bonuses":[]},"outcomes":{"bad":{"text":"The investment was mismanaged. The peace was spent on projects that didn' + "'" + 't pan out.","effects":{"knowledge":4,"resources":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Solid progress. The community knows more than it did.","effects":{"knowledge":10},"flags_set":[],"flags_cleared":[]},"good":{"text":"The quiet period was used to build real understanding. A foundation for harder times ahead.","effects":{"knowledge":16,"stability":5},"flags_set":["knowledge_investment_made"],"flags_cleared":[]}}},{"id":"b","text_template":"Rest. Let people recover.","immediate_effects":{},"community_scores":{"kindred":4,"rewilded":3,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"morale","weight":1.0},{"stat":"health","weight":0.6}],"base_value":0.5,"context_bonuses":[]},"outcomes":{"bad":{"text":"Rest became restlessness. People with nothing urgent to solve started solving each other.","effects":{"cohesion":-5,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"People recovered. Quietly and without drama. A gift.","effects":{"morale":8,"health":6},"flags_set":[],"flags_cleared":[]},"good":{"text":"The rest built reserves — not of food, but of people. Communities can' + "'" + 't run on empty for long.","effects":{"morale":12,"health":8,"cohesion":5},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Expand. Build outward.","immediate_effects":{"resources":-15},"community_scores":{"exchange":4,"bastion":2},"roll":{"relevant_stats":[{"stat":"resources","weight":0.8},{"stat":"security","weight":0.6}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Expansion drew attention. The quiet period ended on someone else' + "'" + 's schedule.","effects":{"security":-10,"resources":-8,"morale":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Growth achieved at cost. The community is larger and less settled.","effects":{"resources":10,"reputation":5},"flags_set":[],"flags_cleared":[]},"good":{"text":"The expansion paid off. More space, more capacity, more room for what comes next.","effects":{"resources":18,"stability":6,"reputation":8},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 7: The Offer
	_insert_tier4_event("tier4_the_offer", "The Offer", "governance", '{"min_game_day":270,"stat_above":{"reputation":65}}', null, 1.0,
		'A message arrived from a larger, more established settlement.\nThey have heard of this community. They are proposing a merger —\nnot a takeover, they say, but an integration.\nResources, safety, numbers. In exchange for autonomy.',
		'[{"id":"a","text_template":"Decline outright.","immediate_effects":{},"community_scores":{"throne":3,"kindred":3,"rewilded":2},"roll":{"relevant_stats":[{"stat":"morale","weight":0.8},{"stat":"cohesion","weight":0.6}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The refusal was read as hostility. Relations with the outside cooled.","effects":{"reputation":-8,"morale":3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The independence was preserved. The road ahead is the community' + "'" + 's own to walk.","effects":{"morale":5,"cohesion":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The refusal was respected. Word spread of a community that knew its own mind.","effects":{"morale":6,"cohesion":5,"reputation":5},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Accept and integrate.","immediate_effects":{},"community_scores":{"exchange":4,"commonwealth":3,"throne":-3},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"stability","weight":0.8}],"base_value":0.2,"context_bonuses":[]},"outcomes":{"bad":{"text":"The integration did not go as described. Autonomy was the first casualty.","effects":{"stability":-12,"cohesion":-10,"morale":-8},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"The merger happened. Something was gained. Something was lost. Hard to say which mattered more.","effects":{"resources":20,"stability":4,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"good":{"text":"The integration was genuine. The community grew without losing its character.","effects":{"resources":25,"stability":8,"cohesion":4,"morale":6},"flags_set":[],"flags_cleared":[]}}},{"id":"c","text_template":"Negotiate terms. Partial alliance, not merger.","immediate_effects":{},"community_scores":{"exchange":3,"archive":2,"commonwealth":2},"roll":{"relevant_stats":[{"stat":"reputation","weight":1.0},{"stat":"knowledge","weight":0.6}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The negotiation broke down. The offer was withdrawn.","effects":{"reputation":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A limited arrangement was reached. Not what was hoped for on either side, but workable.","effects":{"resources":10,"reputation":8},"flags_set":[],"flags_cleared":[]},"good":{"text":"The negotiated terms were better than the original offer. An equal relationship established.","effects":{"resources":15,"reputation":12,"stability":6,"knowledge":5},"flags_set":[],"flags_cleared":[]}}}]'
	)

	# Event 8: The Meaning Question
	_insert_tier4_event("tier4_meaning_question", "What Is This For?", "reflection", '{"min_game_day":180,"community_score_above":{"commonwealth":30}}', a1, 1.0,
		'The immediate crisis has passed — for now.\n{actor_1} asked a question in an unguarded moment that the whole community heard:\nwhat are we actually trying to build here?\nNot how to survive. What to survive for.\nThe question is sitting in the air.',
		'[{"id":"a","text_template":"Survival is enough. Purpose comes later.","immediate_effects":{},"community_scores":{"throne":2,"bastion":2},"roll":{"relevant_stats":[{"stat":"stability","weight":0.8}],"base_value":0.4,"context_bonuses":[]},"outcomes":{"bad":{"text":"The deferral landed as indifference. People needed more than a plan to live.","effects":{"morale":-7,"cohesion":-5},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"Pragmatism accepted. Not inspiring, but not wrong.","effects":{"stability":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"The community respected the honesty. Purpose is a luxury — they weren' + "'" + 't there yet, and everyone knew it.","effects":{"stability":6,"morale":3},"flags_set":[],"flags_cleared":[]}}},{"id":"b","text_template":"Name a shared purpose. Something worth building toward.","immediate_effects":{},"community_scores":{"congregation":4,"archive":3,"commonwealth":3},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"morale","weight":0.8}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"The named purpose divided as much as it united. Not everyone shared it.","effects":{"cohesion":-5,"morale":-3},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A purpose was named. Some believed it fully. Others carried it lightly. Both were enough.","effects":{"morale":6,"cohesion":4},"flags_set":["shared_purpose_named"],"flags_cleared":[]},"good":{"text":"The answer was right. Not for everyone, but for enough. The community oriented around something beyond survival.","effects":{"morale":10,"cohesion":8,"stability":5},"flags_set":["shared_purpose_named"],"flags_cleared":[]}}},{"id":"c","text_template":"Let the community answer for itself.","immediate_effects":{},"community_scores":{"commonwealth":5,"rewilded":2},"roll":{"relevant_stats":[{"stat":"cohesion","weight":1.0},{"stat":"stability","weight":0.6}],"base_value":0.3,"context_bonuses":[]},"outcomes":{"bad":{"text":"Too many answers. The discussion became a debate that had no bottom.","effects":{"cohesion":-7,"stability":-4},"flags_set":[],"flags_cleared":[]},"mixed":{"text":"A multiplicity of answers emerged. The community held them all, imperfectly.","effects":{"cohesion":3,"morale":4},"flags_set":[],"flags_cleared":[]},"good":{"text":"Collective meaning emerged organically. Nobody owned it. Everybody held it.","effects":{"cohesion":10,"morale":8,"stability":6},"flags_set":["shared_purpose_named"],"flags_cleared":[]}}}]'
	)
