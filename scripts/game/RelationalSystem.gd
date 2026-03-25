class_name RelationalSystem
extends RefCounted


static func form_bond(person_a_id: String, person_b_id: String) -> void:
	FlagSystem.set_actor_flag(person_a_id, "close_to:" + person_b_id)
	FlagSystem.set_actor_flag(person_b_id, "close_to:" + person_a_id)


static func form_grudge(holder_id: String, target_id: String) -> void:
	FlagSystem.set_actor_flag(holder_id, "grudge_against:" + target_id)


static func clear_bond(person_a_id: String, person_b_id: String) -> void:
	FlagSystem.clear_actor_flag(person_a_id, "close_to:" + person_b_id)
	FlagSystem.clear_actor_flag(person_b_id, "close_to:" + person_a_id)


static func get_bonds(person_id: String) -> Array[String]:
	var flags := FlagSystem.get_actor_flags(person_id)
	var bonds: Array[String] = []
	for f in flags:
		if f.begins_with("close_to:"):
			bonds.append(f.substr(9))
	return bonds


static func get_grudges(person_id: String) -> Array[String]:
	var flags := FlagSystem.get_actor_flags(person_id)
	var grudges: Array[String] = []
	for f in flags:
		if f.begins_with("grudge_against:"):
			grudges.append(f.substr(15))
	return grudges


static func has_bond(person_a_id: String, person_b_id: String) -> bool:
	return FlagSystem.actor_has_flag(person_a_id, "close_to:" + person_b_id)


static func has_grudge(holder_id: String, target_id: String) -> bool:
	return FlagSystem.actor_has_flag(holder_id, "grudge_against:" + target_id)
