extends Node


func _ready() -> void:
	DatabaseManager.open_library()


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
