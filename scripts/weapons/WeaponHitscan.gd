class_name WeaponHitscan
extends WeaponBase

## Single instant-hit ray, longest range of any weapon — the reliable
## all-purpose default. See WeaponBase for shared cooldown/reload/FX/
## headshot machinery; this only casts the one ray.


func _resolve_shot() -> void:
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
	_record_tracer(global_transform.origin, hit_point)

	if result.is_empty():
		fired.emit(to, false)
		return

	fired.emit(result.position, true)
	var collider: Object = result.collider
	if collider is Character and collider != _character:
		_apply_hit(collider, result.shape, result.position, damage)
