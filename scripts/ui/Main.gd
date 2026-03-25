extends Control

@onready var stats_panel: PanelContainer = $Layout/StatsPanel
@onready var event_log: PanelContainer = $Layout/RightArea/EventLog
@onready var time_controls: PanelContainer = $Layout/RightArea/TimeControls
@onready var _roster_panel: PanelContainer = $RosterPanel


func _ready() -> void:
	DatabaseManager.open_library()
	DatabaseManager.open_save("user://save.db")

	# Register UI with TickManager
	TickManager.register_ui(event_log, stats_panel)

	# Register EndingSystem with scene root and event log
	EndingSystem.register(self, event_log)

	# Connect TimeControls speed signal to TickManager
	time_controls.speed_changed.connect(
		func(speed: int): TickManager.set_speed(speed)
	)

	# Connect TickManager signals
	TickManager.day_advanced.connect(_on_day_advanced)

	# Connect New Game button
	stats_panel.new_game_requested.connect(start_new_game)

	# Connect Roster panel
	stats_panel.roster_requested.connect(_on_roster_requested)
	_roster_panel.closed.connect(func(): _roster_panel.hide())

	# If no game_state exists, start a new game automatically
	var existing := DatabaseManager.query_save("SELECT id FROM game_state LIMIT 1;")
	if existing.is_empty():
		start_new_game()
	else:
		_enter_gameplay()


func start_new_game() -> void:
	# Stop any running simulation
	TickManager.set_speed(0)
	TickManager._game_over = false

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


func _on_roster_requested() -> void:
	_roster_panel.refresh()
	_roster_panel.show()
