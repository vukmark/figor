class_name BotState
extends RefCounted

var bot_ai: BotAI


func _init(ai: BotAI) -> void:
	bot_ai = ai


func enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> InputCommand:
	return InputCommand.new()


## "" means stay in the current state.
func get_next_state_name() -> String:
	return ""


## Shared helper: turns the character toward `direction` at a capped turn
## rate rather than snapping, so bots don't look robotic.
func _steer_yaw(cmd: InputCommand, direction: Vector3, delta: float) -> void:
	if direction.length() < 0.01:
		return
	var desired_yaw: float = atan2(-direction.x, -direction.z)
	var current_yaw: float = bot_ai.character.rotation.y
	var diff: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	var max_step: float = bot_ai.turn_rate * delta
	cmd.look_delta.x = clamp(diff, -max_step, max_step)
