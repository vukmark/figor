class_name FleeState
extends BotState

const FLEE_DISTANCE := 12.0
const ARENA_HALF_EXTENT := 18.0


func enter() -> void:
	_pick_flee_point()


func _pick_flee_point() -> void:
	var origin: Vector3 = bot_ai.character.global_transform.origin
	var target: Character = bot_ai.current_target
	var away: Vector3
	if target:
		away = origin - target.global_transform.origin
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	else:
		away = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()

	var flee_point: Vector3 = origin + away * FLEE_DISTANCE
	flee_point.x = clamp(flee_point.x, -ARENA_HALF_EXTENT, ARENA_HALF_EXTENT)
	flee_point.z = clamp(flee_point.z, -ARENA_HALF_EXTENT, ARENA_HALF_EXTENT)
	bot_ai.nav_agent.target_position = flee_point


func physics_update(delta: float) -> InputCommand:
	var cmd := InputCommand.new()
	if bot_ai.nav_agent.is_navigation_finished():
		_pick_flee_point()

	var next_pos: Vector3 = bot_ai.nav_agent.get_next_path_position()
	var direction: Vector3 = next_pos - bot_ai.character.global_transform.origin
	direction.y = 0.0
	_steer_yaw(cmd, direction, delta)
	cmd.move_vector = Vector2(0, -1)
	return cmd


func get_next_state_name() -> String:
	if bot_ai.character.health.current_health > bot_ai.flee_health_threshold * 1.5:
		return "patrol"
	return ""
