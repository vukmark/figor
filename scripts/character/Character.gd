class_name Character
extends CharacterBody3D

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var weapon_mount: Node3D = $WeaponMount
@onready var health: HealthComponent = $HealthComponent
@onready var head_growth: HeadGrowth = $HeadGrowth
@onready var respawn: RespawnComponent = $RespawnComponent
@onready var input_slot: Node = $InputProviderSlot
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var head_hitbox: CollisionShape3D = $HeadHitbox
@onready var health_bar: HealthBar3D = $VisualRoot/HealthBar3D

## Fired whenever the active weapon slot changes, so listeners (HUD ammo
## display) can re-target which weapon's signals they're reading from
## instead of re-polling every frame.
signal weapon_switched(weapon: Node)

var input_provider: InputProvider
var knockback_velocity := Vector3.ZERO
var _active_weapon_index := 0

## Identity for scoring/display — distinct from multiplayer authority
## (network ownership), which is always 1 for every character in Stage 1
## and can't tell characters apart. Assigned by GameManager at spawn.
var player_id: int = -1
var display_name: String = ""

## The real ENet peer id of whoever this character belongs to (0 for bots,
## -1 until the server assigns it). Synced via spawn=true so it's already
## correct by _ready() on every peer, including late joiners. Each peer
## compares this to multiplayer.get_unique_id() to know whether a given
## spawned Character is "theirs" (camera, input routing).
var owning_peer_id: int = -1

const FOOTSTEP_DISTANCE_INTERVAL := 2.2
const FOOTSTEP_SOUNDS: Array[AudioStream] = [
	preload("res://assets/kenney/audio/impact/Audio/footstep_concrete_000.ogg"),
	preload("res://assets/kenney/audio/impact/Audio/footstep_concrete_001.ogg"),
	preload("res://assets/kenney/audio/impact/Audio/footstep_concrete_002.ogg"),
	preload("res://assets/kenney/audio/impact/Audio/footstep_concrete_003.ogg"),
	preload("res://assets/kenney/audio/impact/Audio/footstep_concrete_004.ogg"),
]

var _gravity_velocity := 0.0
var _footstep_distance_accum := 0.0


func _ready() -> void:
	add_to_group(Constants.GROUP_CHARACTERS)
	health.died.connect(_on_died)

	if input_slot.get_child_count() > 0:
		_bind_input_provider(input_slot.get_child(0))

	var head_node := _find_node_named(visual_root, "head")
	head_growth.set_head_node(head_node)

	# The shape resource is shared across every Character.tscn instance by
	# default (sub-resources aren't auto-duplicated per instance) — since
	# each character's hitbox radius grows independently with its own head,
	# it must be a private copy, not a reference every character would fight
	# over. Position is tracked continuously by HeadGrowth as the head grows.
	head_hitbox.shape = head_hitbox.shape.duplicate()
	head_growth.set_head_hitbox(head_hitbox)

	_update_camera_active()
	_update_weapon_visibility()


## Only the active weapon slot is visible/usable at a time — every weapon a
## character owns lives permanently under WeaponMount (no pickup/inventory
## system), so switching is just moving which index counts as "active."
func _update_weapon_visibility() -> void:
	for i in range(weapon_mount.get_child_count()):
		weapon_mount.get_child(i).visible = i == _active_weapon_index


func get_active_weapon() -> Node:
	if weapon_mount.get_child_count() == 0:
		return null
	return weapon_mount.get_child(_active_weapon_index)


func set_input_provider(provider: InputProvider) -> void:
	for child in input_slot.get_children():
		child.queue_free()
	input_slot.add_child(provider)
	_bind_input_provider(provider)


func _bind_input_provider(provider: Node) -> void:
	input_provider = provider
	if provider is PlayerInputProvider:
		provider.owning_peer_id = owning_peer_id
		provider.is_locally_controlled = owning_peer_id == multiplayer.get_unique_id()
		provider.character = self
	_update_camera_active()


## Camera pitch (unlike yaw, which rotates the CharacterBody3D itself and
## rides along with the already-synced `.:transform`) lives on a child node
## never included in replication — normally applied by the authority in
## _physics_process below, which never runs at all on a real client (only
## the authority/host ever passes is_multiplayer_authority()). Without this,
## a remote client's own camera pitch would never move. Called directly by
## PlayerInputProvider for a genuine remote client only (see the
## multiplayer.is_server() guard there) — the host applies the identical
## clamp itself, just via the authoritative path below, so calling this too
## for the host would double-apply the same delta.
func apply_local_look_pitch(delta_pitch: float) -> void:
	camera.rotation.x = clamp(
		camera.rotation.x + delta_pitch,
		deg_to_rad(Constants.CAMERA_PITCH_MIN),
		deg_to_rad(Constants.CAMERA_PITCH_MAX)
	)


func _update_camera_active() -> void:
	var is_local_view: bool = input_provider is PlayerInputProvider and input_provider.is_locally_controlled
	camera.current = is_local_view
	# First-person: hide our own body so it doesn't clip into the view. Only
	# affects this peer's local rendering — other characters (bots, and
	# eventually remote players) keep rendering their own VisualRoot normally.
	visual_root.visible = not is_local_view


## Clearance above the head hitbox's own (growing) surface, not a fixed
## world height — a static offset would either sit inside a fully-grown
## head (3x scale) or float oddly far above a fresh, un-grown one.
const HEALTH_BAR_HEAD_CLEARANCE := 0.35

## Purely a rendering concern, so — unlike movement/firing below — this runs
## on every peer unconditionally, not just the authority: HealthComponent's
## current_health is already replicated to everyone, this just reflects it.
## Living under VisualRoot means it's already hidden for our own first-person
## view (via the visible toggle above) and hidden entirely on death (via
## RespawnComponent hiding the whole Character node) with no extra code.
func _process(_delta: float) -> void:
	if health.max_health > 0.0:
		health_bar.set_ratio(health.current_health / health.max_health)
	# head_hitbox.position/shape.radius are already updated every physics
	# frame by HeadGrowth to track the head's true, growing extent — reusing
	# that here keeps the bar riding just above the head at every growth
	# stage instead of sitting at one fixed height for the whole match.
	var head_top: float = head_hitbox.position.y + head_hitbox.shape.radius
	health_bar.position.y = head_top + HEALTH_BAR_HEAD_CLEARANCE


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var cmd: InputCommand = input_provider.get_input_command() if input_provider else InputCommand.new()

	rotate_y(cmd.look_delta.x)
	camera.rotation.x = clamp(
		camera.rotation.x + cmd.look_delta.y,
		deg_to_rad(Constants.CAMERA_PITCH_MIN),
		deg_to_rad(Constants.CAMERA_PITCH_MAX)
	)

	# Dead: frozen in place (no movement/gravity/firing) until respawn, but
	# can still look around from the death spot — a minimal spectator view.
	# Without this, a dead character (invisible, non-colliding) could still
	# walk around and shoot people for the whole respawn countdown.
	if not health.is_alive:
		return

	if is_on_floor():
		_gravity_velocity = 0.0
		if cmd.jump_pressed:
			_gravity_velocity = Constants.JUMP_VELOCITY
	else:
		_gravity_velocity -= Constants.GRAVITY * delta

	var move_dir := (transform.basis * Vector3(cmd.move_vector.x, 0.0, cmd.move_vector.y)).normalized()
	var speed: float = Constants.SPRINT_SPEED if cmd.sprint_pressed else Constants.MOVE_SPEED
	# Bigger head = slower target — the tradeoff for a deadlier death explosion.
	var speed_mult: float = lerp(1.0, Constants.HEAD_MIN_SPEED_MULTIPLIER, head_growth.get_head_scale_ratio())
	speed *= speed_mult

	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, Constants.KNOCKBACK_FRICTION * delta)

	velocity.x = move_dir.x * speed + knockback_velocity.x
	velocity.z = move_dir.z * speed + knockback_velocity.z
	velocity.y = _gravity_velocity + knockback_velocity.y

	move_and_slide()
	_update_footsteps(delta)

	if cmd.switch_weapon_pressed and weapon_mount.get_child_count() > 1:
		_active_weapon_index = (_active_weapon_index + 1) % weapon_mount.get_child_count()
		_update_weapon_visibility()
		weapon_switched.emit(get_active_weapon())

	if cmd.fire_pressed:
		var weapon: Node = get_active_weapon()
		if weapon and weapon.has_method("try_fire"):
			weapon.try_fire()


## Called by ExplosionArea (and eventually anything else) to shove this
## character around; decays each physics frame via knockback_velocity.
func apply_external_impulse(impulse: Vector3) -> void:
	knockback_velocity += impulse


## Distance-based rather than time-based, so cadence naturally matches
## actual movement speed (walk vs sprint vs slowed-by-big-head) instead of
## firing on a fixed timer regardless of how far the character really moved.
func _update_footsteps(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or horizontal_speed < 0.5:
		_footstep_distance_accum = 0.0
		return
	_footstep_distance_accum += horizontal_speed * delta
	if _footstep_distance_accum >= FOOTSTEP_DISTANCE_INTERVAL:
		_footstep_distance_accum = 0.0
		Audio.play_random_sfx_3d(FOOTSTEP_SOUNDS, global_transform.origin)


func _on_died(killer_player_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var ratio := head_growth.get_head_scale_ratio()
	GameManager.spawn_explosion(global_transform.origin, ratio, killer_player_id, player_id)
	respawn.begin_respawn_countdown()


func _find_node_named(root: Node, node_name: String) -> Node3D:
	if root.name.to_lower() == node_name.to_lower() and root is Node3D:
		return root
	for child in root.get_children():
		var found := _find_node_named(child, node_name)
		if found:
			return found
	return null
