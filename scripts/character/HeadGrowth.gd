class_name HeadGrowth
extends Node

@export var min_scale := Constants.HEAD_MIN_SCALE
@export var max_scale := Constants.HEAD_MAX_SCALE
@export var time_to_max := Constants.HEAD_TIME_TO_MAX
@export var growth_curve: Curve

var elapsed_alive_time := 0.0
var head_scale := min_scale

var _character: CharacterBody3D
var _health: HealthComponent
var _head_node: Node3D


func _ready() -> void:
	_character = get_parent()
	_health = _character.get_node("HealthComponent")
	if growth_curve == null:
		growth_curve = Curve.new()
		growth_curve.add_point(Vector2(0, 0))
		growth_curve.add_point(Vector2(1, 1))
	head_scale = min_scale


func set_head_node(node: Node3D) -> void:
	_head_node = node


func _physics_process(delta: float) -> void:
	if _character.is_multiplayer_authority() and _health.is_alive:
		elapsed_alive_time += delta
		var t: float = clamp(elapsed_alive_time / time_to_max, 0.0, 1.0)
		head_scale = lerp(min_scale, max_scale, growth_curve.sample(t))

	if _head_node:
		_head_node.scale = Vector3.ONE * head_scale


## Normalized 0..1, independent of the tuned min/max, for explosion sizing.
func get_head_scale_ratio() -> float:
	if max_scale <= min_scale:
		return 0.0
	return (head_scale - min_scale) / (max_scale - min_scale)


func reset() -> void:
	elapsed_alive_time = 0.0
	head_scale = min_scale
