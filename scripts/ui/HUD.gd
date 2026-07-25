class_name HUD
extends Control

const KILL_FEED_MAX_ENTRIES := 5
const KILL_FEED_ENTRY_LIFETIME := 5.0
const HIT_MARKER_COLOR := Color(1, 0.2, 0.2)
const HIT_MARKER_FLASH_TIME := 0.15

@onready var health_bar: ProgressBar = $HealthBar
@onready var head_label: Label = $HeadSizeLabel
@onready var kill_feed: VBoxContainer = $KillFeed
@onready var crosshair: Label = $Crosshair
@onready var timer_label: Label = $MatchTimerLabel
@onready var scoreboard_panel: Control = $ScoreboardPanel
@onready var scoreboard_rows: VBoxContainer = $ScoreboardPanel/VBoxContainer/Rows
@onready var game_over_panel: Control = $GameOverPanel
@onready var game_over_label: Label = $GameOverPanel/VBoxContainer/WinnerLabel
@onready var game_over_rows: VBoxContainer = $GameOverPanel/VBoxContainer/Rows

var _local_character: Character


func _ready() -> void:
	GameManager.character_died.connect(_on_character_died)
	GameManager.match_ended.connect(_on_match_ended)
	GameManager.scores_changed.connect(_refresh_scoreboard)
	scoreboard_panel.visible = false
	game_over_panel.visible = false


func _process(_delta: float) -> void:
	if _local_character == null or not is_instance_valid(_local_character):
		_local_character = _find_local_character()
		if _local_character:
			var weapon: Node = _local_character.weapon_mount.get_child(0)
			if weapon and weapon.has_signal("hit_character"):
				weapon.hit_character.connect(_on_hit_character)
	else:
		health_bar.max_value = _local_character.health.max_health
		health_bar.value = _local_character.health.current_health
		head_label.text = "Head: %.0f%%" % (_local_character.head_growth.get_head_scale_ratio() * 100.0)

	timer_label.text = _format_time(GameManager.match_time_remaining)

	if GameManager.match_over:
		if Input.is_action_just_pressed("restart_match"):
			var main := get_tree().current_scene
			if main and main.has_method("restart_match"):
				main.restart_match()
	else:
		if game_over_panel.visible:
			game_over_panel.visible = false
		scoreboard_panel.visible = Input.is_action_pressed("toggle_scoreboard")


## Brief crosshair flash confirming a shot actually landed on someone —
## otherwise a landed hit is visually indistinguishable from a miss until
## the target dies.
func _on_hit_character() -> void:
	crosshair.add_theme_color_override("font_color", HIT_MARKER_COLOR)
	var timer := get_tree().create_timer(HIT_MARKER_FLASH_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(crosshair):
			crosshair.remove_theme_color_override("font_color")
	)


func _find_local_character() -> Character:
	if GameManager.characters_root == null:
		return null
	for child in GameManager.characters_root.get_children():
		if child is Character and child.input_provider is PlayerInputProvider and child.input_provider.is_locally_controlled:
			return child
	return null


func _on_character_died(victim_player_id: int, killer_player_id: int) -> void:
	var victim_name: String = GameManager.scores.get(victim_player_id, {}).get("name", "Unknown")
	var killer_name: String = GameManager.scores.get(killer_player_id, {}).get("name", "Unknown")

	var entry := Label.new()
	if killer_player_id == victim_player_id or not GameManager.scores.has(killer_player_id):
		entry.text = "%s died" % victim_name
	else:
		entry.text = "%s eliminated %s" % [killer_name, victim_name]
	kill_feed.add_child(entry)
	if kill_feed.get_child_count() > KILL_FEED_MAX_ENTRIES:
		kill_feed.get_child(0).queue_free()

	# Timer is a child of the entry itself, so trimming/freeing the entry
	# early also frees the timer — no dangling reference to worry about.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = KILL_FEED_ENTRY_LIFETIME
	entry.add_child(timer)
	timer.timeout.connect(entry.queue_free)
	timer.start()


func _refresh_scoreboard() -> void:
	_populate_rows(scoreboard_rows)


func _on_match_ended(winner_player_id: int, reason: String) -> void:
	var winner_name: String = GameManager.scores.get(winner_player_id, {}).get("name", "No one")
	game_over_label.text = "%s wins! (%s)\nPress R to play again" % [winner_name, reason]
	_populate_rows(game_over_rows)
	game_over_panel.visible = true
	scoreboard_panel.visible = false


func _populate_rows(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

	var entries: Array = []
	for id in GameManager.scores.keys():
		entries.append(GameManager.scores[id])
	entries.sort_custom(func(a, b): return a["kills"] > b["kills"])

	for entry in entries:
		var row := Label.new()
		row.text = "%s — Kills: %d  Deaths: %d" % [entry["name"], entry["kills"], entry["deaths"]]
		container.add_child(row)


func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
