class_name BotAI
extends Node

@export var vision_range := 20.0
@export var attack_range := 15.0
@export var flee_health_threshold := 25.0
@export var turn_rate := 6.0  # radians/sec
@export var detection_interval := 0.2
@export var accuracy := 0.55  # chance per eligible frame that a bot actually fires

var character: Character
var nav_agent: NavigationAgent3D
var current_target: Character

var _state_machine: BotStateMachine
var _detection_accum := 0.0


func _ready() -> void:
	character = _find_character(self)
	# Fetch the node directly rather than through Character's @onready var:
	# BotAI can now be attached to the Character subtree before that subtree
	# ever enters the tree (see GameManager.spawn_character), which means
	# child _ready() calls (this one) run before the parent Character's own
	# _ready() — so its @onready vars aren't populated yet at this point.
	nav_agent = character.get_node("NavigationAgent3D")
	_state_machine = BotStateMachine.new(self)
	_state_machine.change_state("patrol")


func get_input_command() -> InputCommand:
	var delta := get_physics_process_delta_time()

	_detection_accum += delta
	if _detection_accum >= detection_interval:
		_detection_accum = 0.0
		_refresh_target()

	var next_name := _state_machine.current_state.get_next_state_name()
	if next_name != "":
		_state_machine.change_state(next_name)

	return _state_machine.current_state.physics_update(delta)


func _refresh_target() -> void:
	if current_target and not current_target.health.is_alive:
		current_target = null

	# Hysteresis: keep an already-acquired, still-alive target a bit past
	# vision_range/line-of-sight edge cases so bots don't flicker between
	# states every detection tick while circling each other.
	if current_target:
		var dist: float = character.global_transform.origin.distance_to(current_target.global_transform.origin)
		if dist <= vision_range * 1.3:
			return
		current_target = null

	current_target = _find_nearest_enemy()


func _find_nearest_enemy() -> Character:
	var best: Character = null
	var best_dist := INF
	for node in character.get_tree().get_nodes_in_group(Constants.GROUP_CHARACTERS):
		if node == character or not node.health.is_alive:
			continue
		var dist: float = character.global_transform.origin.distance_to(node.global_transform.origin)
		if dist <= vision_range and dist < best_dist and has_line_of_sight(node):
			best = node
			best_dist = dist
	return best


func has_line_of_sight(target: Character) -> bool:
	var space_state := character.get_world_3d().direct_space_state
	var from: Vector3 = character.global_transform.origin + Vector3.UP * 0.9
	var to: Vector3 = target.global_transform.origin + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [character.get_rid()]
	var result := space_state.intersect_ray(query)
	return result.is_empty() or result.collider == target


func _find_character(node: Node) -> Character:
	var current := node
	while current:
		if current is Character:
			return current
		current = current.get_parent()
	return null
