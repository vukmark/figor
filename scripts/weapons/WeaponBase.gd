class_name WeaponBase
extends Node3D

## Shared machinery for every weapon type — cooldown/reload timers, ammo
## bookkeeping, muzzle flash + tracer FX, and headshot resolution are
## identical regardless of how a weapon actually resolves a trigger pull.
## Concrete weapons (WeaponHitscan, WeaponShotgun) only differ in how many
## rays they cast per shot and how damage is split across them, so that's
## the only thing `_resolve_shot()` needs to implement.

signal fired(hit_position: Vector3, did_hit: bool)
## Fired specifically when a shot lands on another Character — distinct from
## `fired` so listeners (e.g. a hit-marker on the HUD) don't need to inspect
## the hit collider themselves.
signal hit_character()
## Ammo state, for a HUD counter to listen to.
signal ammo_changed(current: int, max_ammo: int)
signal reload_started(reload_time: float)

@export var display_name := "Weapon"
@export var damage := Constants.WEAPON_DAMAGE
@export var weapon_range := Constants.WEAPON_RANGE
@export var cooldown := Constants.WEAPON_COOLDOWN
@export var magazine_size := Constants.WEAPON_MAGAZINE_SIZE
@export var reload_time := Constants.WEAPON_RELOAD_TIME

## Defaults match the original (and still only) blaster sounds — a weapon
## scene only needs to override these if it wants to sound distinct.
@export var fire_sound: AudioStream = preload("res://assets/kenney/audio/scifi/Audio/laserLarge_000.ogg")
@export var reload_sound: AudioStream = preload("res://assets/kenney/audio/scifi/Audio/doorClose_000.ogg")
@export var hit_sounds: Array[AudioStream] = [
	preload("res://assets/kenney/audio/impact/Audio/impactMetal_medium_000.ogg"),
	preload("res://assets/kenney/audio/impact/Audio/impactMetal_medium_001.ogg"),
	preload("res://assets/kenney/audio/impact/Audio/impactMetal_medium_002.ogg"),
]

const TRACER_LIFETIME := 0.08
const MUZZLE_FLASH_LIFETIME := 0.05

var current_ammo: int
var is_reloading := false

var _cooldown_remaining := 0.0
var _reload_time_remaining := 0.0
var _character: Character

## Collected during _resolve_shot() (both weapon types call _record_tracer/
## _record_hit instead of the raw local-only helpers) and flushed to every
## other peer in a single broadcast right after — see try_fire().
var _pending_tracer_from: PackedVector3Array = []
var _pending_tracer_to: PackedVector3Array = []
var _pending_hit_positions: PackedVector3Array = []


func _ready() -> void:
	_character = _find_character(self)
	current_ammo = magazine_size


func _process(delta: float) -> void:
	_cooldown_remaining = max(_cooldown_remaining - delta, 0.0)

	if is_reloading:
		_reload_time_remaining -= delta
		if _reload_time_remaining <= 0.0:
			is_reloading = false
			current_ammo = magazine_size
			ammo_changed.emit(current_ammo, magazine_size)


## Server-side only in practice (Stage 1 authority owns every Character, so
## this always runs on the server) — resolves the shot and applies damage
## directly rather than trusting any client-side aim. No manual reload input:
## the magazine auto-reloads the instant it empties, which works identically
## for the player and bots without any bot-side special-casing.
func try_fire() -> void:
	if _cooldown_remaining > 0.0 or _character == null or GameManager.match_over or is_reloading:
		return
	if current_ammo <= 0:
		_start_reload()
		return

	_cooldown_remaining = cooldown
	current_ammo -= 1
	ammo_changed.emit(current_ammo, magazine_size)

	Audio.play_sfx_3d(fire_sound, global_transform.origin)
	_pending_tracer_from.clear()
	_pending_tracer_to.clear()
	_pending_hit_positions.clear()
	_resolve_shot()

	# _resolve_shot() (and the sound/muzzle-flash calls around it) only ever
	# run on whichever peer calls try_fire() — always the server, since
	# firing is server-authoritative. Without this broadcast, nobody would
	# ever see or hear a shot except the server: every muzzle flash/tracer/
	# fire sound/hit sound just spawned above only exists on the server's
	# own local scene tree. This is what made firing look completely dead
	# from a client's perspective, even though the shot was actually
	# landing (damage already replicates fine via HealthComponent).
	_replay_fire_feedback.rpc(_pending_tracer_from, _pending_tracer_to, _pending_hit_positions)


## Casts whatever ray(s) this weapon type fires and applies damage/FX for
## each. Subclasses must call `_apply_hit()` for every ray that lands on a
## Character and `_spawn_tracer()`/`fired.emit()` for every ray regardless of
## whether it hit anything, so hit-scan feedback stays consistent across
## weapon types.
func _resolve_shot() -> void:
	pass


## Shared by every weapon type's raycast handling: applies damage (with the
## headshot multiplier if the ray landed on the head hitbox), fires the
## shared hit signal/sound, and returns whether it was a headshot in case a
## caller wants to react further (e.g. per-pellet feedback).
func _apply_hit(collider: Character, shape_index: int, hit_position: Vector3, per_hit_damage: float) -> void:
	var is_headshot := _is_headshot(collider, shape_index)
	var dealt_damage: float = per_hit_damage * Constants.HEADSHOT_DAMAGE_MULTIPLIER if is_headshot else per_hit_damage
	collider.health.take_damage(dealt_damage, _character.player_id)
	hit_character.emit()
	Audio.play_random_sfx_3d(hit_sounds, hit_position)
	_pending_hit_positions.append(hit_position)


## Weapon subclasses call this instead of _spawn_tracer() directly during
## _resolve_shot(), so every tracer also gets queued into the fire-feedback
## broadcast (see try_fire()) alongside the immediate local spawn.
func _record_tracer(from: Vector3, to: Vector3) -> void:
	_spawn_tracer(from, to)
	_pending_tracer_from.append(from)
	_pending_tracer_to.append(to)


## Replays a shot's visible/audible feedback on every peer that didn't
## actually run _resolve_shot() themselves (see try_fire()'s broadcast).
@rpc("authority", "unreliable")
func _replay_fire_feedback(tracer_from: PackedVector3Array, tracer_to: PackedVector3Array, hit_positions: PackedVector3Array) -> void:
	Audio.play_sfx_3d(fire_sound, global_transform.origin)
	_spawn_muzzle_flash()
	for i in range(tracer_from.size()):
		_spawn_tracer(tracer_from[i], tracer_to[i])
	for pos in hit_positions:
		Audio.play_random_sfx_3d(hit_sounds, pos)
	var did_hit := not hit_positions.is_empty()
	fired.emit(tracer_to[-1] if tracer_to.size() > 0 else global_transform.origin, did_hit)
	if did_hit:
		hit_character.emit()


## `result.shape` from intersect_ray is a shape index local to the collider's
## own compound shape, not a node — resolve it back to the owning
## CollisionShape3D and compare against the character's dedicated head
## hitbox to tell a headshot from a body hit.
func _is_headshot(character: Character, shape_index: int) -> bool:
	var owner_id := character.shape_find_owner(shape_index)
	return character.shape_owner_get_owner(owner_id) == character.head_hitbox


func _start_reload() -> void:
	is_reloading = true
	_reload_time_remaining = reload_time
	reload_started.emit(reload_time)
	Audio.play_sfx_3d(reload_sound, global_transform.origin)


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
