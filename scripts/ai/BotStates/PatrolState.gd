class_name PatrolState
extends BotState

const PATROL_HALF_EXTENT := 15.0


func enter() -> void:
	_pick_new_point()


func _pick_new_point() -> void:
	var origin: Vector3 = bot_ai.character.global_transform.origin
	var point := Vector3(
		randf_range(-PATROL_HALF_EXTENT, PATROL_HALF_EXTENT),
		origin.y,
		randf_range(-PATROL_HALF_EXTENT, PATROL_HALF_EXTENT)
	)
	bot_ai.nav_agent.target_position = point


func physics_update(delta: float) -> InputCommand:
	var cmd := InputCommand.new()
	if bot_ai.nav_agent.is_navigation_finished():
		_pick_new_point()

	var next_pos: Vector3 = bot_ai.nav_agent.get_next_path_position()
	var direction: Vector3 = next_pos - bot_ai.character.global_transform.origin
	direction.y = 0.0
	_steer_yaw(cmd, direction, delta)
	if direction.length() > 0.3:
		cmd.move_vector = Vector2(0, -1)
	return cmd


func get_next_state_name() -> String:
	if bot_ai.current_target:
		return "seek"
	return ""
