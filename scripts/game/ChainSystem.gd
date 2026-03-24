class_name ChainSystem
extends RefCounted


static func start_chain(
	chain_id: String,
	first_stage_id: String,
	game_day: int,
	initial_memory: Dictionary = {}
) -> void:
	var next_fire: int = game_day + randi_range(3, 10)
	DatabaseManager.execute_save(
		"INSERT OR REPLACE INTO active_chains (chain_id, current_stage_id, memory, started_day, last_stage_day, next_fire_day) VALUES (?, ?, ?, ?, ?, ?);",
		[chain_id, first_stage_id, JSON.stringify(initial_memory), game_day, game_day, next_fire]
	)


static func advance_chain(
	chain_id: String,
	next_stage_id: String,
	memory_writes: Dictionary,
	game_day: int
) -> void:
	if next_stage_id == null or next_stage_id == "" or str(next_stage_id) == "null":
		end_chain(chain_id)
		return

	var current_memory := get_memory(chain_id)
	for key in memory_writes:
		current_memory[key] = memory_writes[key]

	var next_fire: int = game_day + randi_range(5, 20)
	DatabaseManager.execute_save(
		"UPDATE active_chains SET current_stage_id = ?, memory = ?, last_stage_day = ?, next_fire_day = ? WHERE chain_id = ?;",
		[next_stage_id, JSON.stringify(current_memory), game_day, next_fire, chain_id]
	)


static func end_chain(chain_id: String) -> void:
	DatabaseManager.execute_save(
		"DELETE FROM active_chains WHERE chain_id = ?;",
		[chain_id]
	)


static func get_memory(chain_id: String) -> Dictionary:
	var rows := DatabaseManager.query_save(
		"SELECT memory FROM active_chains WHERE chain_id = ?;",
		[chain_id]
	)
	if rows.size() == 0:
		return {}
	var parsed = JSON.parse_string(str(rows[0].get("memory", "{}")))
	if parsed is Dictionary:
		return parsed
	return {}


static func get_due_chains(game_day: int) -> Array:
	return DatabaseManager.query_save(
		"SELECT * FROM active_chains WHERE next_fire_day <= ?;",
		[game_day]
	)
