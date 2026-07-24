class_name AttackState
extends BotState


func physics_update(delta: float) -> InputCommand:
	var cmd := InputCommand.new()
	var target: Character = bot_ai.current_target
	if target == null:
		return cmd

	var direction: Vector3 = target.global_transform.origin - bot_ai.character.global_transform.origin
	direction.y = 0.0
	_steer_yaw(cmd, direction, delta)
	cmd.fire_pressed = bot_ai.has_line_of_sight(target)
	return cmd


func get_next_state_name() -> String:
	var target: Character = bot_ai.current_target
	if target == null or not target.health.is_alive:
		return "patrol"
	if bot_ai.character.health.current_health <= bot_ai.flee_health_threshold:
		return "flee"
	if not bot_ai.has_line_of_sight(target):
		return "seek"
	var dist: float = bot_ai.character.global_transform.origin.distance_to(target.global_transform.origin)
	if dist > bot_ai.attack_range:
		return "seek"
	return ""
