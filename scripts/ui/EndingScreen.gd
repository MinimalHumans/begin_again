extends CanvasLayer

signal new_game_requested

const COL_TEXT_DIM := Color("#8a7f70")
const COL_TEXT_PRIMARY := Color("#e0d5c0")
const COL_TEXT_HIGHLIGHT := Color("#f0e8d0")
const COL_BTN_BG := Color("#2a2a2a")

@onready var _end_type_label: Label = $ContentContainer/ScrollContainer/ContentBox/EndTypeLabel
@onready var _headline_label: Label = $ContentContainer/ScrollContainer/ContentBox/HeadlineLabel
@onready var _days_label: Label = $ContentContainer/ScrollContainer/ContentBox/DaysLabel
@onready var _narrative_label: RichTextLabel = $ContentContainer/ScrollContainer/ContentBox/NarrativeLabel
@onready var _stats_box: HBoxContainer = $ContentContainer/ScrollContainer/ContentBox/StatsBox
@onready var _community_reveal_box: VBoxContainer = $ContentContainer/ScrollContainer/ContentBox/CommunityRevealBox
@onready var _new_game_button: Button = $ContentContainer/ScrollContainer/ContentBox/NewGameButton

var _headlines := {
	"population_collapse": "Population Collapse",
	"starvation": "Starvation",
	"cohesion_failure": "Cohesion Failure",
	"overthrow": "Overthrow",
	"extinction": "Extinction",
	"self_sacrifice": "Your Legacy"
}

var _end_type_texts := {
	"population_collapse": "THE COMMUNITY FELL",
	"starvation": "THE COMMUNITY FELL",
	"cohesion_failure": "THE COMMUNITY FELL",
	"overthrow": "THE COMMUNITY FELL",
	"extinction": "THE COMMUNITY FELL",
	"self_sacrifice": "THE COMMUNITY ENDURES"
}


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_button_pressed)


func present(
	reason: String,
	_final_stats: Dictionary,
	game_state: Dictionary,
	narrative: String,
	dominant_type: Dictionary,
	secondary_type: Dictionary,
	stats_summary: Dictionary
) -> void:
	# --- End Type Label ---
	_end_type_label.text = _end_type_texts.get(reason, "THE COMMUNITY FELL")
	_end_type_label.add_theme_font_size_override("font_size", 13)
	_end_type_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	_end_type_label.uppercase = true

	# --- Headline ---
	_headline_label.text = _headlines.get(reason, "The End")
	_headline_label.add_theme_font_size_override("font_size", 28)
	_headline_label.add_theme_color_override("font_color", COL_TEXT_HIGHLIGHT)

	# --- Days Label ---
	var season: String = str(game_state.get("season", "")).capitalize()
	_days_label.text = "Day %d — %s" % [stats_summary.get("game_day", 0), season]
	_days_label.add_theme_font_size_override("font_size", 14)
	_days_label.add_theme_color_override("font_color", COL_TEXT_DIM)

	# --- Narrative ---
	_narrative_label.text = narrative
	_narrative_label.add_theme_font_size_override("normal_font_size", 15)
	_narrative_label.add_theme_color_override("default_color", COL_TEXT_PRIMARY)

	# --- Stats Summary ---
	_build_stats_box(stats_summary)

	# --- Community Reveal ---
	_build_community_reveal(dominant_type, secondary_type)

	# --- Button Style ---
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = COL_BTN_BG
	btn_style.content_margin_left = 20.0
	btn_style.content_margin_right = 20.0
	btn_style.content_margin_top = 8.0
	btn_style.content_margin_bottom = 8.0
	_new_game_button.add_theme_stylebox_override("normal", btn_style)
	_new_game_button.add_theme_stylebox_override("hover", btn_style)
	_new_game_button.add_theme_stylebox_override("pressed", btn_style)
	_new_game_button.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	_new_game_button.add_theme_font_size_override("font_size", 16)
	_new_game_button.flat = true


func _build_stats_box(summary: Dictionary) -> void:
	# Clear existing children
	for child in _stats_box.get_children():
		child.queue_free()

	var items := [
		["Days Survived", str(summary.get("game_day", 0))],
		["Final Population", str(summary.get("population", 0))],
		["Peak Population", str(summary.get("peak_population", 0))],
		["Decisions Made", str(summary.get("decisions", 0))],
		["Community", str(summary.get("community_name", "Unknown"))]
	]

	for i in items.size():
		if i > 0:
			# Add vertical divider
			var sep := VSeparator.new()
			sep.add_theme_constant_override("separation", 16)
			_stats_box.add_child(sep)

		var label := Label.new()
		label.text = "%s: %s" % [items[i][0], items[i][1]]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", COL_TEXT_DIM)
		_stats_box.add_child(label)


func _build_community_reveal(dominant_type: Dictionary, secondary_type: Dictionary) -> void:
	# Clear existing children
	for child in _community_reveal_box.get_children():
		child.queue_free()

	var display_name: String = str(dominant_type.get("display_name", ""))
	var reveal_text: String = str(dominant_type.get("reveal_text", ""))
	var secondary_name: String = str(secondary_type.get("display_name", ""))

	if display_name == "":
		# No dominant type
		var no_identity := Label.new()
		no_identity.text = "The community never found its identity."
		no_identity.add_theme_font_size_override("font_size", 14)
		no_identity.add_theme_color_override("font_color", COL_TEXT_DIM)
		no_identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_community_reveal_box.add_child(no_identity)
		return

	# Type name
	var type_label := Label.new()
	type_label.text = display_name.to_upper()
	type_label.add_theme_font_size_override("font_size", 18)
	type_label.add_theme_color_override("font_color", COL_TEXT_HIGHLIGHT)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_community_reveal_box.add_child(type_label)

	# Secondary type hint
	if secondary_name != "":
		var secondary_label := Label.new()
		secondary_label.text = "with traces of %s" % secondary_name
		secondary_label.add_theme_font_size_override("font_size", 13)
		secondary_label.add_theme_color_override("font_color", COL_TEXT_DIM)
		secondary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_community_reveal_box.add_child(secondary_label)

	# Reveal text
	if reveal_text != "":
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		_community_reveal_box.add_child(spacer)

		var reveal_label := RichTextLabel.new()
		reveal_label.bbcode_enabled = true
		reveal_label.fit_content = true
		reveal_label.text = "[i]%s[/i]" % reveal_text
		reveal_label.add_theme_font_size_override("normal_font_size", 14)
		reveal_label.add_theme_color_override("default_color", COL_TEXT_PRIMARY)
		_community_reveal_box.add_child(reveal_label)


func _on_new_game_button_pressed() -> void:
	new_game_requested.emit()
	queue_free()
