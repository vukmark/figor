class_name WeaponShotgun
extends WeaponBase

## Multiple independent rays per trigger pull, spread across a cone — high
## burst damage up close (all pellets can land), falls off hard at range
## (both from spread scattering pellets wide and from `weapon_range` itself
## being much shorter than the hitscan's). Trades WeaponHitscan's reliable
## single-target-at-range damage for a close-quarters risk/reward pick.

@export var pellet_count := Constants.SHOTGUN_PELLET_COUNT
@export var pellet_damage := Constants.SHOTGUN_PELLET_DAMAGE
@export var spread_degrees := Constants.SHOTGUN_SPREAD_DEGREES


func _resolve_shot() -> void:
	var cam := _character.camera
	var from := cam.global_transform.origin
	var forward := -cam.global_transform.basis.z
	var space_state := get_world_3d().direct_space_state
	var any_hit := false

	for i in range(pellet_count):
		var dir := _spread_direction(forward)
		var to := from + dir * weapon_range
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [_character.get_rid()]
		var result := space_state.intersect_ray(query)

		var hit_point := to
		if not result.is_empty():
			hit_point = result.position
		_spawn_tracer(global_transform.origin, hit_point)

		if not result.is_empty():
			any_hit = true
			var collider: Object = result.collider
			if collider is Character and collider != _character:
				_apply_hit(collider, result.shape, result.position, pellet_damage)

	_spawn_muzzle_flash()
	fired.emit(from + forward * weapon_range, any_hit)


## Random direction within a cone around `forward` — `tan()` of a uniformly
## random angle (rather than a uniformly random offset vector) keeps pellets
## from clustering toward the cone's center, giving an even spread disc.
func _spread_direction(forward: Vector3) -> Vector3:
	var max_rad := deg_to_rad(spread_degrees)
	var yaw := randf_range(-max_rad, max_rad)
	var pitch := randf_range(-max_rad, max_rad)
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	return (forward + right * tan(yaw) + up * tan(pitch)).normalized()
