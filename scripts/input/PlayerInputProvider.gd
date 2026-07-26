class_name PlayerInputProvider
extends InputProvider

## Distinct from network authority: this flags which locally-running peer
## this input belongs to (relevant once Stage 2 has multiple local players
## and Stage 3 has remote players sending their own commands).
@export var is_locally_controlled := true

## Set by Character._bind_input_provider from the owning Character's
## owning_peer_id. Used server-side to reject input RPCs claiming to drive
## a character the sending peer doesn't actually own.
var owning_peer_id := -1

## Set by Character._bind_input_provider — lets a genuine remote client
## apply its own camera pitch immediately/locally (see _input below)
## instead of waiting on a server round-trip that, for pitch specifically,
## would never even arrive (see Character.apply_local_look_pitch).
var character: Character

var _accumulated_look := Vector2.ZERO
var _last_remote_command := InputCommand.new()


func _ready() -> void:
	if is_locally_controlled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not is_locally_controlled:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var delta_x: float = -motion.relative.x * Settings.mouse_sensitivity
		var delta_y: float = -motion.relative.y * Settings.mouse_sensitivity
		_accumulated_look.x += delta_x
		_accumulated_look.y += delta_y
		# Only for a real remote client: the host applies this same delta
		# itself via the authoritative Character._physics_process path
		# below, so doing it here too would double it up for the host.
		if character and not multiplayer.is_server():
			character.apply_local_look_pitch(delta_y)


## Runs on every peer (unlike get_input_command, which is only ever called
## from the server's authority-gated Character._physics_process). This is
## the only path that ships a remote client's own input to the server each
## tick — on the server itself this is a no-op since the server already
## polls its own input directly via get_input_command().
func _physics_process(_delta: float) -> void:
	if not is_locally_controlled or multiplayer.is_server():
		return
	var cmd := _poll_local_input()
	submit_input_command.rpc_id(1, cmd.move_vector, cmd.look_delta,
			cmd.fire_pressed, cmd.jump_pressed, cmd.sprint_pressed, cmd.switch_weapon_pressed)


## Server-side receiver for a remote client's input. unreliable_ordered:
## movement tolerates drops, but a stale out-of-order packet must be
## discarded rather than overwrite a newer command.
@rpc("any_peer", "unreliable_ordered")
func submit_input_command(move_vector: Vector2, look_delta: Vector2, fire_pressed: bool,
		jump_pressed: bool, sprint_pressed: bool, switch_weapon_pressed: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owning_peer_id:
		return
	_last_remote_command.move_vector = move_vector
	_last_remote_command.look_delta = look_delta
	_last_remote_command.fire_pressed = fire_pressed
	_last_remote_command.jump_pressed = jump_pressed
	_last_remote_command.sprint_pressed = sprint_pressed
	_last_remote_command.switch_weapon_pressed = switch_weapon_pressed


## Only ever called on the authority (server) via Character._physics_process.
func get_input_command() -> InputCommand:
	if not is_locally_controlled:
		return _last_remote_command
	return _poll_local_input()


func _poll_local_input() -> InputCommand:
	var cmd := InputCommand.new()
	cmd.move_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	cmd.look_delta = _accumulated_look
	_accumulated_look = Vector2.ZERO
	cmd.fire_pressed = Input.is_action_pressed("fire")
	cmd.jump_pressed = Input.is_action_just_pressed("jump")
	cmd.sprint_pressed = Input.is_action_pressed("sprint")
	cmd.switch_weapon_pressed = Input.is_action_just_pressed("switch_weapon")
	return cmd
