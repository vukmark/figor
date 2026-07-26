class_name ExplosionArea
extends Node3D

@onready var area: Area3D = $Area3D
@onready var collision_shape: CollisionShape3D = $Area3D/CollisionShape3D
@onready var vfx: Node3D = $VFX
@onready var lifetime_timer: Timer = $LifetimeTimer

const EXPLOSION_SOUNDS: Array[AudioStream] = [
	preload("res://assets/kenney/audio/scifi/Audio/explosionCrunch_000.ogg"),
	preload("res://assets/kenney/audio/scifi/Audio/explosionCrunch_001.ogg"),
	preload("res://assets/kenney/audio/scifi/Audio/explosionCrunch_002.ogg"),
]

var _detonated := false


## Called once by GameManager right after instancing, before this node has
## necessarily entered the tree's physics step.
func configure(head_scale_ratio: float, killer_player_id: int, victim_player_id: int) -> void:
	var radius: float = Constants.EXPLOSION_BASE_RADIUS * lerp(1.0, Constants.EXPLOSION_MAX_RADIUS_MULT, head_scale_ratio)
	var damage: float = Constants.EXPLOSION_BASE_DAMAGE * lerp(1.0, Constants.EXPLOSION_MAX_DAMAGE_MULT, head_scale_ratio)
	var force: float = Constants.EXPLOSION_BASE_FORCE * lerp(1.0, Constants.EXPLOSION_MAX_FORCE_MULT, head_scale_ratio)

	collision_shape.shape.radius = radius
	vfx.scale = Vector3.ONE * radius

	set_meta("radius", radius)
	set_meta("damage", damage)
	set_meta("force", force)
	set_meta("killer_player_id", killer_player_id)
	set_meta("victim_player_id", victim_player_id)
	set_meta("head_scale_ratio", head_scale_ratio)


func _ready() -> void:
	await get_tree().physics_frame
	_detonate()


## Exactly one detonation pass — a single overlap sweep, not a repeating
## signal-driven trigger — so there is no risk of double-processing a victim
## from this explosion instance. Chain reactions (a victim's own death
## spawning its own Explosion) are handled naturally by that victim's own
## HealthComponent/Character, not by this node recursing.
##
## Runs identically on every peer now (see GameManager.spawn_explosion —
## this node is no longer MultiplayerSpawner-replicated at all, each peer
## gets its own independently-spawned local instance), but the actual
## damage-dealing is gated to the server: HealthComponent.take_damage() has
## no authority check of its own, so every peer's local copy would
## otherwise apply damage to its own (about-to-be-overwritten-by-sync)
## copy of nearby characters' health — harmless in the end since the
## server's real value wins on the next sync, but a needless correctness
## risk (e.g. a client incorrectly seeing die() fire locally) for zero
## benefit, since only the server's result actually matters.
func _detonate() -> void:
	if _detonated:
		return
	_detonated = true

	var radius: float = get_meta("radius", Constants.EXPLOSION_BASE_RADIUS)
	var damage: float = get_meta("damage", Constants.EXPLOSION_BASE_DAMAGE)
	var force: float = get_meta("force", Constants.EXPLOSION_BASE_FORCE)
	var killer_player_id: int = get_meta("killer_player_id", -1)
	var head_scale_ratio: float = get_meta("head_scale_ratio", 0.0)

	# Bigger head = bigger explosion = louder bang, not just a wider radius.
	Audio.play_random_sfx_3d(EXPLOSION_SOUNDS, global_transform.origin, lerp(0.0, 8.0, head_scale_ratio))

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var space_state := get_world_3d().direct_space_state
		# Explosion spawns at the victim's own origin (feet level, same
		# convention as Character.gd), which sits right at/in the terrain's
		# collision surface — raycasting from there would immediately clip
		# the ground at t≈0 and read as "blocked" for every target. Raise
		# the ray's start point off the ground the same way the target is
		# raised to torso height, so it only hits real cover in between.
		var blast_origin: Vector3 = global_transform.origin + Vector3.UP * 0.9
		for body in area.get_overlapping_bodies():
			if body is Character and body.health.is_alive:
				var target: Vector3 = body.global_transform.origin + Vector3.UP * 0.9
				var offset: Vector3 = target - global_transform.origin
				var dist: float = offset.length()
				var falloff: float = clamp(1.0 - dist / radius, 0.0, 1.0)
				if falloff <= 0.0:
					continue
				# Terrain/obstacles sit on collision layer 1 (characters are
				# layer 2, excluded here by mask), so a hit means real cover
				# is blocking line-of-sight to this victim's torso.
				var query := PhysicsRayQueryParameters3D.create(blast_origin, target, 1)
				if space_state.intersect_ray(query):
					continue
				body.health.take_damage(damage * falloff, killer_player_id)
				if body.health.is_alive:
					var direction: Vector3 = offset.normalized() if dist > 0.001 else Vector3.UP
					body.apply_external_impulse(direction * force * falloff)

	lifetime_timer.start()


func _on_lifetime_timeout() -> void:
	queue_free()
