class_name Character
extends CharacterBody3D

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var weapon_mount: Node3D = $WeaponMount
@onready var health: HealthComponent = $HealthComponent
@onready var head_growth: HeadGrowth = $HeadGrowth
@onready var respawn: RespawnComponent = $RespawnComponent
@onready var input_slot: Node = $InputProviderSlot
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var input_provider: InputProvider
var knockback_velocity := Vector3.ZERO

var _gravity_velocity := 0.0


func _ready() -> void:
	add_to_group(Constants.GROUP_CHARACTERS)
	health.died.connect(_on_died)

	if input_slot.get_child_count() > 0:
		_bind_input_provider(input_slot.get_child(0))

	var head_node := _find_node_named(visual_root, "head")
	head_growth.set_head_node(head_node)

	_update_camera_active()


func set_input_provider(provider: InputProvider) -> void:
	for child in input_slot.get_children():
		child.queue_free()
	input_slot.add_child(provider)
	_bind_input_provider(provider)


func _bind_input_provider(provider: Node) -> void:
	input_provider = provider
	_update_camera_active()


func _update_camera_active() -> void:
	camera.current = input_provider is PlayerInputProvider and input_provider.is_locally_controlled


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var cmd: InputCommand = input_provider.get_input_command() if input_provider else InputCommand.new()

	rotate_y(cmd.look_delta.x)
	spring_arm.rotation.x = clamp(
		spring_arm.rotation.x + cmd.look_delta.y,
		deg_to_rad(Constants.CAMERA_PITCH_MIN),
		deg_to_rad(Constants.CAMERA_PITCH_MAX)
	)

	if is_on_floor():
		_gravity_velocity = 0.0
		if cmd.jump_pressed:
			_gravity_velocity = Constants.JUMP_VELOCITY
	else:
		_gravity_velocity -= Constants.GRAVITY * delta

	var move_dir := (transform.basis * Vector3(cmd.move_vector.x, 0.0, cmd.move_vector.y)).normalized()
	var speed: float = Constants.SPRINT_SPEED if cmd.sprint_pressed else Constants.MOVE_SPEED

	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, Constants.KNOCKBACK_FRICTION * delta)

	velocity.x = move_dir.x * speed + knockback_velocity.x
	velocity.z = move_dir.z * speed + knockback_velocity.z
	velocity.y = _gravity_velocity + knockback_velocity.y

	move_and_slide()

	if cmd.fire_pressed and weapon_mount.get_child_count() > 0:
		var weapon: Node = weapon_mount.get_child(0)
		if weapon.has_method("try_fire"):
			weapon.try_fire()


## Called by ExplosionArea (and eventually anything else) to shove this
## character around; decays each physics frame via knockback_velocity.
func apply_external_impulse(impulse: Vector3) -> void:
	knockback_velocity += impulse


func _on_died(killer_peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var ratio := head_growth.get_head_scale_ratio()
	GameManager.spawn_explosion(global_transform.origin, ratio, killer_peer_id, get_multiplayer_authority())
	respawn.begin_respawn_countdown()


func _find_node_named(root: Node, node_name: String) -> Node3D:
	if root.name.to_lower() == node_name.to_lower() and root is Node3D:
		return root
	for child in root.get_children():
		var found := _find_node_named(child, node_name)
		if found:
			return found
	return null
