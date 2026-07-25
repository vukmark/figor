class_name PlayerInputProvider
extends InputProvider

## Distinct from network authority: this flags which locally-running peer
## this input belongs to (relevant once Stage 2 has multiple local players
## and Stage 3 has remote players sending their own commands).
@export var is_locally_controlled := true

var _accumulated_look := Vector2.ZERO


func _ready() -> void:
	if is_locally_controlled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not is_locally_controlled:
		return
	if event is InputEventMouseMotion:
		_accumulated_look.x -= event.relative.x * Settings.mouse_sensitivity
		_accumulated_look.y -= event.relative.y * Settings.mouse_sensitivity


func get_input_command() -> InputCommand:
	var cmd := InputCommand.new()
	if not is_locally_controlled:
		return cmd

	cmd.move_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	cmd.look_delta = _accumulated_look
	_accumulated_look = Vector2.ZERO
	cmd.fire_pressed = Input.is_action_pressed("fire")
	cmd.jump_pressed = Input.is_action_just_pressed("jump")
	cmd.sprint_pressed = Input.is_action_pressed("sprint")
	cmd.switch_weapon_pressed = Input.is_action_just_pressed("switch_weapon")
	return cmd
