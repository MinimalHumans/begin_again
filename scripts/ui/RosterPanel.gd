extends PanelContainer

signal closed

const COL_BG := Color("#222222")
const COL_BORDER := Color("#7a6a50")
const COL_TEXT_PRIMARY := Color("#e0d5c0")
const COL_TEXT_DIM := Color("#8a7f70")

@onready var _member_list: VBoxContainer = $VBoxContainer/ScrollContainer/MemberList
@onready var _close_button: Button = $VBoxContainer/HeaderRow/CloseButton
@onready var _warning_label: Label = $VBoxContainer/WarningLabel

var _all_roles: Array = []


func _ready() -> void:
	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_BORDER
	style.border_width_left = 1
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	add_theme_stylebox_override("panel", style)

	_close_button.pressed.connect(_on_close_button_pressed)


func refresh() -> void:
	# Clear existing rows
	for child in _member_list.get_children():
		child.queue_free()

	_warning_label.text = ""

	# Query data
	_all_roles = DatabaseManager.query_library("SELECT * FROM roles;")
	var members := DatabaseManager.query_save(
		"SELECT id, name, age, skills, assigned_role FROM population WHERE alive = 1 ORDER BY name;"
	)

	for member in members:
		var row := _create_member_row(member)
		_member_list.add_child(row)


func _create_member_row(member: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36

	# Name + age
	var name_label := Label.new()
	name_label.text = str(member["name"]) + ", " + str(member["age"])
	name_label.custom_minimum_size.x = 130
	name_label.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.clip_text = true
	row.add_child(name_label)

	# Skills
	var person_skills: Array = JSON.parse_string(str(member["skills"]))
	if person_skills == null:
		person_skills = []
	var skills_label := Label.new()
	skills_label.text = " · ".join(person_skills) if person_skills.size() > 0 else "—"
	skills_label.custom_minimum_size.x = 130
	skills_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	skills_label.add_theme_font_size_override("font_size", 11)
	skills_label.clip_text = true
	row.add_child(skills_label)

	# Role dropdown
	var option_btn := OptionButton.new()
	option_btn.custom_minimum_size.x = 140
	option_btn.add_theme_font_size_override("font_size", 12)

	# First item: no role
	option_btn.add_item("— No Role —", 0)
	option_btn.set_item_metadata(0, "")

	var current_role = member.get("assigned_role")
	if current_role == null:
		current_role = ""
	var selected_idx := 0

	for i in range(_all_roles.size()):
		var role: Dictionary = _all_roles[i]
		var role_id: String = str(role["id"])
		var display_name: String = str(role["display_name"])

		# Check if person is qualified
		var required_skills: Array = JSON.parse_string(str(role["required_skills"]))
		if required_skills == null:
			required_skills = []
		var is_qualified := required_skills.size() == 0
		if not is_qualified:
			for req_skill in required_skills:
				if req_skill in person_skills:
					is_qualified = true
					break

		if not is_qualified:
			display_name += " *"

		var item_idx: int = i + 1
		option_btn.add_item(display_name, item_idx)
		option_btn.set_item_metadata(item_idx, role_id)

		if role_id == current_role:
			selected_idx = item_idx

	option_btn.selected = selected_idx

	var person_id: String = str(member["id"])
	option_btn.item_selected.connect(func(idx: int):
		var role_id: String = option_btn.get_item_metadata(idx)
		_assign_role(person_id, role_id)
	)

	row.add_child(option_btn)
	return row


func _assign_role(person_id: String, role_id: String) -> void:
	# Check max_slots warning
	if role_id != "":
		for role in _all_roles:
			if str(role["id"]) == role_id:
				var max_slots: int = int(role["max_slots"])
				var current_count_rows := DatabaseManager.query_save(
					"SELECT COUNT(*) as n FROM population WHERE assigned_role = ? AND alive = 1 AND id != ?;",
					[role_id, person_id]
				)
				var current_count: int = int(current_count_rows[0]["n"])
				if current_count >= max_slots:
					_warning_label.text = str(role["display_name"]) + " slots full (" + str(current_count) + "/" + str(max_slots) + ") — assigning anyway, only the first fills the role"
				else:
					_warning_label.text = ""
				break

	# Update assignment
	if role_id == "":
		DatabaseManager.execute_save(
			"UPDATE population SET assigned_role = NULL WHERE id = ?;",
			[person_id]
		)
	else:
		DatabaseManager.execute_save(
			"UPDATE population SET assigned_role = ? WHERE id = ?;",
			[role_id, person_id]
		)

	# Recalculate food_production if farmer was involved
	_update_food_production()

	# Refresh display
	refresh()


func _update_food_production() -> void:
	var farmer_count_rows := DatabaseManager.query_save(
		"SELECT COUNT(*) as n FROM population WHERE assigned_role = 'farmer' AND alive = 1;"
	)
	var farmer_count: int = int(farmer_count_rows[0]["n"])
	var farmer_role_rows := DatabaseManager.query_library(
		"SELECT stat_bonuses FROM roles WHERE id = 'farmer';"
	)
	var total_food_production := 0.0
	if farmer_role_rows.size() > 0:
		var farmer_bonuses: Dictionary = JSON.parse_string(str(farmer_role_rows[0]["stat_bonuses"]))
		if farmer_bonuses != null:
			var farmer_bonus: float = float(farmer_bonuses.get("food_production", 0.5))
			total_food_production = farmer_count * farmer_bonus
	DatabaseManager.execute_save(
		"UPDATE game_state SET food_production = ? WHERE id = 1;",
		[total_food_production]
	)


func _on_close_button_pressed() -> void:
	closed.emit()
	hide()
