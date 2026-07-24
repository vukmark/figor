class_name WeaponHitscan
extends Node3D

signal fired(hit_position: Vector3, did_hit: bool)

@export var damage := Constants.WEAPON_DAMAGE
@export var weapon_range := Constants.WEAPON_RANGE
@export var cooldown := Constants.WEAPON_COOLDOWN

var _cooldown_remaining := 0.0
var _character: Character


func _ready() -> void:
	_character = _find_character(self)


func _process(delta: float) -> void:
	_cooldown_remaining = max(_cooldown_remaining - delta, 0.0)


## Server-side only in practice (Stage 1 authority owns every Character, so
## this always runs on the server) — resolves the shot and applies damage
## directly rather than trusting any client-side aim.
func try_fire() -> void:
	if _cooldown_remaining > 0.0 or _character == null:
		return
	_cooldown_remaining = cooldown

	var cam := _character.camera
	var from := cam.global_transform.origin
	var to := from - cam.global_transform.basis.z * weapon_range

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_character.get_rid()]
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		fired.emit(to, false)
		return

	fired.emit(result.position, true)
	var collider: Object = result.collider
	if collider is Character and collider != _character:
		collider.health.take_damage(damage, _character.get_multiplayer_authority())


func _find_character(node: Node) -> Character:
	var current := node
	while current:
		if current is Character:
			return current
		current = current.get_parent()
	return null
