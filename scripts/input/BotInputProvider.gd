class_name BotInputProvider
extends InputProvider

## Wraps the AI state machine; BotAI is added as a child once bot behavior
## (task: NavigationAgent3D + bot state machine) is implemented. Until then
## this returns an idle command so a bot-flagged Character just stands still.
@onready var bot_ai: Node = get_node_or_null("BotAI")


func get_input_command() -> InputCommand:
	if bot_ai and bot_ai.has_method("get_input_command"):
		return bot_ai.get_input_command()
	return InputCommand.new()
