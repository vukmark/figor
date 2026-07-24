class_name HUD
extends Control

const KILL_FEED_MAX_ENTRIES := 5
const KILL_FEED_ENTRY_LIFETIME := 5.0

@onready var health_bar: ProgressBar = $HealthBar
@onready var head_label: Label = $HeadSizeLabel
@onready var kill_feed: VBoxContainer = $KillFeed

var _local_character: Character


func _ready() -> void:
	GameManager.character_died.connect(_on_character_died)


func _process(_delta: float) -> void:
	if _local_character == null or not is_instance_valid(_local_character):
		_local_character = _find_local_character()
		return

	health_bar.max_value = _local_character.health.max_health
	health_bar.value = _local_character.health.current_health
	head_label.text = "Head: %.0f%%" % (_local_character.head_growth.get_head_scale_ratio() * 100.0)


func _find_local_character() -> Character:
	if GameManager.characters_root == null:
		return null
	for child in GameManager.characters_root.get_children():
		if child is Character and child.input_provider is PlayerInputProvider and child.input_provider.is_locally_controlled:
			return child
	return null


func _on_character_died(victim_peer_id: int, killer_peer_id: int) -> void:
	var entry := Label.new()
	entry.text = "Player %d eliminated Player %d" % [killer_peer_id, victim_peer_id]
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
