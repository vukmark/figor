class_name SeekState
extends BotState


func physics_update(delta: float) -> InputCommand:
	var cmd := InputCommand.new()
	var target: Character = bot_ai.current_target
	if target == null:
		return cmd

	bot_ai.nav_agent.target_position = target.global_transform.origin
	var next_pos: Vector3 = bot_ai.nav_agent.get_next_path_position()
	var direction: Vector3 = next_pos - bot_ai.character.global_transform.origin
	direction.y = 0.0
	_steer_yaw(cmd, direction, delta)
	cmd.move_vector = Vector2(0, -1)
	return cmd


func get_next_state_name() -> String:
	var target: Character = bot_ai.current_target
	if target == null or not target.health.is_alive:
		return "patrol"
	var dist: float = bot_ai.character.global_transform.origin.distance_to(target.global_transform.origin)
	if dist <= bot_ai.attack_range and bot_ai.has_line_of_sight(target):
		return "attack"
	return ""
