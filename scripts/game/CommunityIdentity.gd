class_name CommunityIdentity
extends RefCounted


static func get_dominant_type() -> Dictionary:
	var rows := DatabaseManager.query_save(
		"SELECT type_id, score FROM community_scores ORDER BY score DESC LIMIT 1;"
	)
	if rows.size() == 0:
		return {}
	var row: Dictionary = rows[0]
	if float(row.get("score", 0)) == 0.0:
		return {}
	return {"type_id": str(row["type_id"]), "score": float(row["score"])}


static func get_secondary_type() -> Dictionary:
	var rows := DatabaseManager.query_save(
		"SELECT type_id, score FROM community_scores ORDER BY score DESC LIMIT 1 OFFSET 1;"
	)
	if rows.size() == 0:
		return {}
	return {"type_id": str(rows[0]["type_id"]), "score": float(rows[0]["score"])}


static func get_dominant_threshold() -> String:
	var dominant := get_dominant_type()
	if dominant.is_empty():
		return "none"
	var type_row := GameData.get_community_type(dominant.type_id)
	if type_row.is_empty():
		return "none"
	var thresholds = JSON.parse_string(str(type_row.get("thresholds", "{}")))
	if not (thresholds is Dictionary):
		thresholds = {}
	var score: float = dominant.score
	if score >= float(thresholds.get("dominant", 80)):
		return "dominant"
	elif score >= float(thresholds.get("major", 60)):
		return "major"
	elif score >= float(thresholds.get("minor", 30)):
		return "minor"
	return "none"


static func get_active_roll_modifiers() -> Dictionary:
	var threshold := get_dominant_threshold()
	if threshold != "major" and threshold != "dominant":
		return {}
	var dominant := get_dominant_type()
	if dominant.is_empty():
		return {}
	var type_row := GameData.get_community_type(dominant.type_id)
	if type_row.is_empty():
		return {}
	var modifiers = JSON.parse_string(str(type_row.get("roll_modifiers", "{}")))
	if not (modifiers is Dictionary):
		return {}
	return modifiers


static func update_ranks() -> void:
	var rows := DatabaseManager.query_save(
		"SELECT type_id, score FROM community_scores ORDER BY score DESC;"
	)
	for i in rows.size():
		DatabaseManager.execute_save(
			"UPDATE community_scores SET rank = ? WHERE type_id = ?;",
			[i + 1, rows[i].type_id]
		)


static func apply_flavour(text: String, _game_day: int) -> String:
	var threshold := get_dominant_threshold()
	if threshold == "none":
		return text
	var dominant := get_dominant_type()
	if dominant.is_empty():
		return text
	if randf() > 0.2:
		return text
	var suffixes := _get_flavour_suffixes(dominant.type_id, threshold)
	if suffixes.is_empty():
		return text
	return text + " " + suffixes[randi() % suffixes.size()]


static func _get_flavour_suffixes(type_id: String, _threshold: String) -> Array[String]:
	match type_id:
		"commonwealth":
			return ["The vote was unanimous.", "Everyone had a say.", "It was decided together."]
		"bastion":
			return ["Nobody questioned the order.", "The watch was doubled.", "Discipline held."]
		"exchange":
			return ["A fair trade, all things considered.", "The ledger balanced.", "Everyone knew the terms."]
		"congregation":
			return ["A quiet prayer followed.", "The group gave thanks.", "Faith carried them through."]
		"kindred":
			return ["Family looks after family.", "No one asked — they just helped.", "Blood and bond."]
		"archive":
			return ["Someone wrote it down.", "The knowledge was preserved.", "It was documented carefully."]
		"rewilded":
			return ["The land provided.", "Nothing was wasted.", "It felt right, living this way."]
		"throne":
			return ["Nobody second-guessed the decision.", "Leadership was clear.", "The order was given and followed."]
	return []
