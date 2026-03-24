class_name FlagSystem
extends RefCounted

# In-memory cache for per-actor flags to avoid repeated DB round trips
static var _actor_flags_cache: Dictionary = {}


static func invalidate_cache() -> void:
	_actor_flags_cache.clear()


# ---------- Global Flags ----------

static func set_flag(flag_name: String, game_day: int, source: String = "") -> void:
	DatabaseManager.execute_save(
		"INSERT OR REPLACE INTO flags (flag_name, set_day, source) VALUES (?, ?, ?);",
		[flag_name, game_day, source]
	)


static func clear_flag(flag_name: String) -> void:
	DatabaseManager.execute_save(
		"DELETE FROM flags WHERE flag_name = ?;",
		[flag_name]
	)


static func has_flag(flag_name: String) -> bool:
	var rows := DatabaseManager.query_save(
		"SELECT 1 FROM flags WHERE flag_name = ? LIMIT 1;",
		[flag_name]
	)
	return rows.size() > 0


static func get_all_flags() -> Array[String]:
	var rows := DatabaseManager.query_save("SELECT flag_name FROM flags;")
	var result: Array[String] = []
	for row in rows:
		result.append(str(row["flag_name"]))
	return result


# ---------- Per-Actor Flags ----------

static func set_actor_flag(person_id: String, flag_name: String) -> void:
	var flags := get_actor_flags(person_id)
	if flag_name not in flags:
		flags.append(flag_name)
		var json_str := JSON.stringify(flags)
		DatabaseManager.execute_save(
			"UPDATE population SET flags = ? WHERE id = ?;",
			[json_str, person_id]
		)
		_actor_flags_cache[person_id] = flags


static func clear_actor_flag(person_id: String, flag_name: String) -> void:
	var flags := get_actor_flags(person_id)
	var idx := flags.find(flag_name)
	if idx >= 0:
		flags.remove_at(idx)
		var json_str := JSON.stringify(flags)
		DatabaseManager.execute_save(
			"UPDATE population SET flags = ? WHERE id = ?;",
			[json_str, person_id]
		)
		_actor_flags_cache[person_id] = flags


static func actor_has_flag(person_id: String, flag_name: String) -> bool:
	var flags := get_actor_flags(person_id)
	return flag_name in flags


static func get_actor_flags(person_id: String) -> Array[String]:
	if _actor_flags_cache.has(person_id):
		return _actor_flags_cache[person_id]

	var rows := DatabaseManager.query_save(
		"SELECT flags FROM population WHERE id = ? LIMIT 1;",
		[person_id]
	)
	var result: Array[String] = []
	if rows.size() > 0:
		var parsed = JSON.parse_string(str(rows[0].get("flags", "[]")))
		if parsed is Array:
			for f in parsed:
				result.append(str(f))

	_actor_flags_cache[person_id] = result
	return result
