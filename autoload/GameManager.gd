extends Node

signal character_died(victim_peer_id: int, killer_peer_id: int)

const character_scene: PackedScene = preload("res://scenes/character/Character.tscn")
const explosion_scene: PackedScene = preload("res://scenes/fx/Explosion.tscn")

var world_root: Node3D
var characters_root: Node3D
var fx_root: Node3D
var spawn_points: Array[Node3D] = []

var _spawn_index := 0


func register_world(world: Node3D, characters_container: Node3D, fx_container: Node3D, points: Array[Node3D]) -> void:
	world_root = world
	characters_root = characters_container
	fx_root = fx_container
	spawn_points = points
	_spawn_index = 0


func get_next_spawn_point() -> Node3D:
	if spawn_points.is_empty():
		return null
	var point := spawn_points[_spawn_index % spawn_points.size()]
	_spawn_index += 1
	return point


## Server-authoritative: only ever called on the host/server.
func spawn_character(input_provider_scene: PackedScene, peer_id: int = 1) -> Node:
	if character_scene == null or characters_root == null:
		push_warning("GameManager: character_scene or characters_root not set")
		return null
	var character := character_scene.instantiate()
	character.set_multiplayer_authority(1)

	# Swap the input provider BEFORE the character enters the tree, so its
	# _ready() never sees the scene's default PlayerInputProvider. Otherwise
	# a bot would briefly report itself as the locally-controlled player
	# during its own _ready() (stealing the "current" Camera3D from whichever
	# camera actually held it, since only one Camera3D can be current per
	# viewport) before being corrected a moment later.
	if input_provider_scene:
		var slot: Node = character.get_node("InputProviderSlot")
		for child in slot.get_children():
			slot.remove_child(child)
			child.free()
		slot.add_child(input_provider_scene.instantiate())

	characters_root.add_child(character, true)
	var spawn_point := get_next_spawn_point()
	if spawn_point:
		character.global_transform = spawn_point.global_transform
	return character


## Server-only: decides an explosion happened and spawns the one-shot effect.
func spawn_explosion(pos: Vector3, head_scale_ratio: float, killer_peer_id: int, victim_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if explosion_scene == null or fx_root == null:
		push_warning("GameManager: explosion_scene or fx_root not set")
		return
	var explosion := explosion_scene.instantiate()
	fx_root.add_child(explosion, true)
	explosion.global_position = pos
	if explosion.has_method("configure"):
		explosion.configure(head_scale_ratio, killer_peer_id, victim_peer_id)
	character_died.emit(victim_peer_id, killer_peer_id)
