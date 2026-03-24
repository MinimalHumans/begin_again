extends Node

var _skill_ids_cache: Array[String] = []
var _events_cache: Array = []
var _personality_cache: Dictionary = {}


func _ready() -> void:
	DatabaseManager.open_library()


func get_all_skill_ids() -> Array[String]:
	if _skill_ids_cache.size() > 0:
		return _skill_ids_cache
	var rows := DatabaseManager.query_library("SELECT id FROM skills;")
	for row in rows:
		_skill_ids_cache.append(str(row["id"]))
	return _skill_ids_cache


func get_all_events() -> Array:
	if _events_cache.size() > 0:
		return _events_cache
	_events_cache = DatabaseManager.query_library("SELECT * FROM events;")
	return _events_cache


func get_personality(id: String) -> Dictionary:
	if _personality_cache.has(id):
		return _personality_cache[id]
	var rows := DatabaseManager.query_library(
		"SELECT * FROM personalities WHERE id = ?;", [id]
	)
	if rows.size() > 0:
		_personality_cache[id] = rows[0]
		return rows[0]
	return {}


func get_config(key: String) -> float:
	var results := DatabaseManager.query_library(
		"SELECT value FROM simulation_config WHERE key = ?;", [key]
	)
	if results.size() > 0:
		return results[0]["value"]
	return 0.0


func get_all_stats() -> Array:
	return DatabaseManager.query_library(
		"SELECT * FROM stats ORDER BY display_order;"
	)


func get_stat(id: String) -> Dictionary:
	var results := DatabaseManager.query_library(
		"SELECT * FROM stats WHERE id = ?;", [id]
	)
	if results.size() > 0:
		return results[0]
	return {}


func get_all_roles() -> Array:
	return DatabaseManager.query_library("SELECT * FROM roles;")
