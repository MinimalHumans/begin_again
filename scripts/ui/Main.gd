extends Control

@onready var stats_panel: PanelContainer = $Layout/StatsPanel
@onready var event_log: PanelContainer = $Layout/RightArea/EventLog
@onready var time_controls: PanelContainer = $Layout/RightArea/TimeControls


func _ready() -> void:
	DatabaseManager.open_library()
	DatabaseManager.open_save("user://save.db")

	_seed_test_data()

	# Build stats panel from library definitions
	var stat_defs := GameData.get_all_stats()
	stats_panel.build(stat_defs)
	stats_panel.refresh()

	event_log.load_from_db()

	# Register UI with TickManager
	TickManager.register_ui(event_log, stats_panel)

	# Connect TimeControls speed signal to TickManager
	time_controls.speed_changed.connect(
		func(speed: int): TickManager.set_speed(speed)
	)

	# Connect TickManager signals
	TickManager.day_advanced.connect(_on_day_advanced)


func _on_day_advanced(_new_day: int, _new_season: String) -> void:
	pass


func _seed_test_data() -> void:
	# Only seed if game_state is empty
	var gs := DatabaseManager.query_save("SELECT id FROM game_state;")
	if gs.size() > 0:
		return

	# game_state
	DatabaseManager.execute_save(
		"INSERT INTO game_state (id, game_day, starting_day_of_year, apocalypse_id, origin_id, location_id, season, food_production, difficulty_time_factor, opening_text, game_over) VALUES (1, 30, 90, 'nuclear_exchange', 'founder', 'suburban_residential', 'spring', 0.0, 0.0, ?, 0);",
		["It has been 30 days since the missiles flew. You gathered these people. You settled in a quiet residential area. You have 8 people. Food is running low. What kind of leader will you be?"]
	)

	# current_stats
	var stats := [
		["population", 8], ["food", 19.6], ["morale", 45], ["health", 31],
		["security", 40], ["knowledge", 28], ["cohesion", 52], ["resources", 38],
		["stability", 55], ["reputation", 50],
	]
	for s in stats:
		DatabaseManager.execute_save(
			"INSERT INTO current_stats (stat_id, value) VALUES (?, ?);", s
		)

	# population
	var people := [
		["p_001", "Ana", 34, "f", 1, 30, '["medicine"]', "caregiver", "medic"],
		["p_002", "Ben", 28, "m", 1, 30, '["farming"]', "caregiver", "farmer"],
		["p_003", "Clara", 22, "f", 1, 30, '["combat"]', "caregiver", "guard"],
		["p_004", "Dani", 45, "m", 1, 30, '["engineering"]', "caregiver", null],
		["p_005", "Eva", 31, "f", 1, 30, '["teaching"]', "caregiver", null],
		["p_006", "Finn", 51, "m", 1, 30, '["farming","combat"]', "caregiver", "farmer"],
		["p_007", "Grace", 27, "f", 1, 30, '[]', "caregiver", null],
		["p_008", "Hugo", 38, "m", 1, 30, '[]', "caregiver", null],
	]
	for p in people:
		DatabaseManager.execute_save(
			"INSERT INTO population (id, name, age, gender, alive, joined_day, skills, personality, assigned_role) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
			p
		)

	# event_log
	var events := [
		[1, 1, "ambient", "Ana quietly checked on the injured this morning.", 0, 0],
		[12, 1, "ambient", "Ben was seen sharing his ration with the children.", 0, 0],
		[20, 2, "interpersonal", "Clara and Hugo argued over watch duties. You intervened and kept the peace — for now.", 0, 0],
		[28, 1, "ambient", "Someone left a bundle of herbs by the door. Probably Ana.", 0, 0],
		[30, 3, "resource", "Food supplies are lower than expected. A hard conversation about rationing is coming.", 1, 1],
	]
	for e in events:
		DatabaseManager.execute_save(
			"INSERT INTO event_log (game_day, tier, category, display_text, is_highlighted, is_major) VALUES (?, ?, ?, ?, ?, ?);",
			e
		)
