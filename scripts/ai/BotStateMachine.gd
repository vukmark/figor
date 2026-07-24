class_name BotStateMachine
extends RefCounted

var current_state: BotState
var current_state_name := ""

var _states: Dictionary


func _init(bot_ai: BotAI) -> void:
	_states = {
		"patrol": PatrolState.new(bot_ai),
		"seek": SeekState.new(bot_ai),
		"attack": AttackState.new(bot_ai),
		"flee": FleeState.new(bot_ai),
	}


func change_state(state_name: String) -> void:
	if state_name == current_state_name or not _states.has(state_name):
		return
	if current_state:
		current_state.exit()
	current_state = _states[state_name]
	current_state_name = state_name
	current_state.enter()
