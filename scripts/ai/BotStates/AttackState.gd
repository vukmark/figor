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
	# Bots aren't perfect shots — this keeps fights from being instant even
	# with unbroken line of sight, on top of the weapon's own fire cooldown.
	cmd.fire_pressed = Constants.BOTS_CAN_FIRE and bot_ai.has_line_of_sight(target) and randf() < bot_ai.accuracy
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
