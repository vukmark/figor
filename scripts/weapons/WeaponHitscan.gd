class_name WeaponHitscan
extends Node3D

signal fired(hit_position: Vector3, did_hit: bool)
## Fired specifically when a shot lands on another Character — distinct from
## `fired` so listeners (e.g. a hit-marker on the HUD) don't need to inspect
## the hit collider themselves.
signal hit_character()

const TRACER_LIFETIME := 0.08
const MUZZLE_FLASH_LIFETIME := 0.05

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
	if _cooldown_remaining > 0.0 or _character == null or GameManager.match_over:
		return
	_cooldown_remaining = cooldown

	var cam := _character.camera
	var from := cam.global_transform.origin
	var to := from - cam.global_transform.basis.z * weapon_range

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_character.get_rid()]
	var result := space_state.intersect_ray(query)

	var hit_point := to
	if not result.is_empty():
		hit_point = result.position

	_spawn_muzzle_flash()
	_spawn_tracer(global_transform.origin, hit_point)

	if result.is_empty():
		fired.emit(to, false)
		return

	fired.emit(result.position, true)
	var collider: Object = result.collider
	if collider is Character and collider != _character:
		collider.health.take_damage(damage, _character.player_id)
		hit_character.emit()


func _spawn_muzzle_flash() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.85, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.8, 0.2)
	mat.emission_energy_multiplier = 6.0
	flash.material_override = mat
	root.add_child(flash)
	flash.global_transform.origin = global_transform.origin

	var timer := get_tree().create_timer(MUZZLE_FLASH_LIFETIME)
	timer.timeout.connect(flash.queue_free)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var dist := from.distance_to(to)
	if dist < 0.01:
		return

	var tracer := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, dist)
	tracer.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.9, 0.4, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.85, 0.3)
	mat.emission_energy_multiplier = 4.0
	tracer.material_override = mat
	root.add_child(tracer)

	var midpoint := from.lerp(to, 0.5)
	tracer.global_transform = Transform3D(_basis_looking(to - from), midpoint)

	var timer := get_tree().create_timer(TRACER_LIFETIME)
	timer.timeout.connect(tracer.queue_free)


## BoxMesh's long axis (`size.z`) needs to point along `direction` — this
## builds that basis directly rather than via look_at (which aligns -Z to a
## target point, not a mesh's local Z to an arbitrary direction vector).
func _basis_looking(direction: Vector3) -> Basis:
	var z_axis := direction.normalized()
	var up := Vector3.UP if abs(z_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := up.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _find_character(node: Node) -> Character:
	var current := node
	while current:
		if current is Character:
			return current
		current = current.get_parent()
	return null
