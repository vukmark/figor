class_name HeadGrowth
extends Node

@export var min_scale := Constants.HEAD_MIN_SCALE
@export var max_scale := Constants.HEAD_MAX_SCALE
@export var time_to_max := Constants.HEAD_TIME_TO_MAX
@export var growth_curve: Curve

var elapsed_alive_time := 0.0
var head_scale := min_scale

@export var head_hitbox_base_radius := 0.28

var _character: CharacterBody3D
var _health: HealthComponent
var _head_node: Node3D
var _head_base_scale := Vector3.ONE
var _head_local_center := Vector3.ZERO
var _head_hitbox: CollisionShape3D


func _ready() -> void:
	_character = get_parent()
	_health = _character.get_node("HealthComponent")
	if growth_curve == null:
		growth_curve = Curve.new()
		growth_curve.add_point(Vector2(0, 0))
		growth_curve.add_point(Vector2(1, 1))
	head_scale = min_scale


## `node`'s own imported/authored local scale is preserved as the baseline —
## head_scale is a multiplier on top of it, never an absolute value, so we
## never fight the model's original proportions.
##
## `node`'s origin sits at the *base* of the head mesh (like the chin/neck),
## not its center — the Kenney model's pivot, not something we control. So
## the hitbox can't just sit at `node`'s origin: as the head scales up, its
## visual center moves further and further above that pivot. We compute the
## mesh's local bounding-box center once here, then track its actual current
## world position (through node's live, growing global_transform) every
## frame in _physics_process.
func set_head_node(node: Node3D) -> void:
	_head_node = node
	_head_base_scale = node.scale
	_head_local_center = node.get_aabb().get_center() if node.has_method("get_aabb") else Vector3.ZERO


## A dedicated hitbox is needed because the body's main CollisionShape3D
## (a fixed capsule) never resizes — without this, a grown head sticks out
## far past the actual collision volume and shots aimed at it simply miss,
## even though shots at the torso (still inside the capsule) land fine.
func set_head_hitbox(shape: CollisionShape3D) -> void:
	_head_hitbox = shape


func _physics_process(delta: float) -> void:
	if _character.is_multiplayer_authority() and _health.is_alive:
		elapsed_alive_time += delta
		var t: float = clamp(elapsed_alive_time / time_to_max, 0.0, 1.0)
		head_scale = lerp(min_scale, max_scale, growth_curve.sample(t))

	if _head_node:
		_head_node.scale = _head_base_scale * head_scale
	if _head_hitbox and _head_node:
		var world_center: Vector3 = _head_node.global_transform * _head_local_center
		_head_hitbox.position = _character.to_local(world_center)
		_head_hitbox.shape.radius = head_hitbox_base_radius * head_scale


## Normalized 0..1, independent of the tuned min/max, for explosion sizing.
func get_head_scale_ratio() -> float:
	if max_scale <= min_scale:
		return 0.0
	return (head_scale - min_scale) / (max_scale - min_scale)


func reset() -> void:
	elapsed_alive_time = 0.0
	head_scale = min_scale
