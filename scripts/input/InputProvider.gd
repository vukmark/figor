class_name InputProvider
extends Node

## Base class for anything that can drive a Character: real player input or bot AI.
## Character.gd only ever talks to this interface, so players and bots are interchangeable.
func get_input_command() -> InputCommand:
	return InputCommand.new()
