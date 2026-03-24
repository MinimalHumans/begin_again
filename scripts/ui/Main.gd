extends Control

@onready var stats_panel: PanelContainer = $Layout/StatsPanel
@onready var event_log: PanelContainer = $Layout/RightArea/EventLog
@onready var time_controls: PanelContainer = $Layout/RightArea/TimeControls


func _ready() -> void:
	DatabaseManager.open_library()
	DatabaseManager.open_save("user://save.db")

	# Register UI with TickManager
	TickManager.register_ui(event_log, stats_panel)

	# Connect TimeControls speed signal to TickManager
	time_controls.speed_changed.connect(
		func(speed: int): TickManager.set_speed(speed)
	)

	# Connect TickManager signals
	TickManager.day_advanced.connect(_on_day_advanced)

	# Connect New Game button
	stats_panel.new_game_requested.connect(start_new_game)

	# If no game_state exists, start a new game automatically
	var existing := DatabaseManager.query_save("SELECT id FROM game_state LIMIT 1;")
	if existing.is_empty():
		start_new_game()
	else:
		_enter_gameplay()

	# --- Phase 2a verification tests ---
	_run_phase2a_tests()


func start_new_game() -> void:
	# Stop any running simulation
	TickManager.set_speed(0)

	# Wipe save.db and recreate schema
	DatabaseManager.reset_save("user://save.db")

	# Generate starting conditions
	var result := NewGameGenerator.generate()

	# Show opening crawl
	_show_opening_crawl(result["opening_text"])


func _show_opening_crawl(text: String) -> void:
	var crawl := preload("res://scenes/ui/OpeningCrawl.tscn").instantiate()
	add_child(crawl)
	crawl.show_text(text)
	crawl.dismissed.connect(_on_crawl_dismissed.bind(crawl))


func _on_crawl_dismissed(crawl: Node) -> void:
	crawl.queue_free()
	_enter_gameplay()


func _enter_gameplay() -> void:
	var stat_defs := GameData.get_all_stats()
	stats_panel.build(stat_defs)
	stats_panel.refresh()
	event_log.load_from_db()
	# Time starts paused — player must press Normal or Fast


func _on_day_advanced(_new_day: int, _new_season: String) -> void:
	pass


func _run_phase2a_tests() -> void:
	print("=== Phase 2a Verification Tests ===")

	# Test 1: EligibilityEngine
	var test_event := {"eligibility": "{\"min_game_day\": 10}", "cooldown_days": 0, "exclusion_group": null, "max_occurrences": null, "id": "test"}
	var eligible := EligibilityEngine.is_eligible(test_event, [], ["season_spring"], {}, [], [], 30, [], {})
	print("Eligibility test (expect true): ", eligible)

	var test_event2 := {"eligibility": "{\"min_game_day\": 50}", "cooldown_days": 0, "exclusion_group": null, "max_occurrences": null, "id": "test2"}
	var eligible2 := EligibilityEngine.is_eligible(test_event2, [], ["season_spring"], {}, [], [], 30, [], {})
	print("Eligibility test min_game_day=50 day=30 (expect false): ", eligible2)

	# Test 2: FlagSystem
	FlagSystem.set_flag("test_flag", 30)
	var has_it := FlagSystem.has_flag("test_flag")
	print("FlagSystem test (expect true): ", has_it)
	FlagSystem.clear_flag("test_flag")
	var has_it2 := FlagSystem.has_flag("test_flag")
	print("FlagSystem clear test (expect false): ", has_it2)

	# Test 3: ActorCaster with no requirements
	var pop := DatabaseManager.query_save("SELECT * FROM population WHERE alive = 1;")
	if pop.size() > 0:
		var cast_event := {"actor_requirements": "{\"actor_1\": {}}", "category": "test"}
		var cast_result := ActorCaster.cast(cast_event, pop, 30)
		print("ActorCaster test (expect non-empty): ", not cast_result.is_empty(), " - cast ", cast_result.size(), " actor(s)")
	else:
		print("ActorCaster test skipped: no population")

	# Test 4: StateTagSystem
	var stats := {}
	var stat_rows := DatabaseManager.query_save("SELECT stat_id, value FROM current_stats;")
	for row in stat_rows:
		stats[row["stat_id"]] = float(row["value"])
	var gs_rows := DatabaseManager.query_save("SELECT * FROM game_state WHERE id = 1;")
	if gs_rows.size() > 0:
		var known_skills := GameData.get_all_skill_ids()
		var tags := StateTagSystem.compute(stats, pop, gs_rows[0], known_skills)
		print("StateTagSystem tags: ", tags)

	print("=== Phase 2a Tests Complete ===")
