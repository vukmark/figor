class_name RespawnComponent
extends Node

@export var respawn_delay := Constants.RESPAWN_DELAY

var _character: CharacterBody3D
var _health: HealthComponent
var _head_growth: HeadGrowth
var _timer: Timer


func _ready() -> void:
	_character = get_parent()
	_health = _character.get_node("HealthComponent")
	_head_growth = _character.get_node("HeadGrowth")
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = respawn_delay
	add_child(_timer)
	_timer.timeout.connect(_do_respawn)


## Authority-only: called by Character after death has been fully processed
## (explosion spawned, rpc_died broadcast).
func begin_respawn_countdown() -> void:
	_character.visible = false
	_character.set_collision_layer_value(2, false)
	_character.set_collision_mask_value(1, false)
	_timer.start()


func _do_respawn() -> void:
	var spawn_point: Node3D = GameManager.get_next_spawn_point()
	if spawn_point:
		_character.global_transform = spawn_point.global_transform
	_health.reset()
	_head_growth.reset()
	_character.visible = true
	_character.set_collision_layer_value(2, true)
	_character.set_collision_mask_value(1, true)
