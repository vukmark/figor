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

	for body in area.get_overlapping_bodies():
		if body is Character and body.health.is_alive:
			var offset: Vector3 = body.global_transform.origin - global_transform.origin
			var dist: float = offset.length()
			var falloff: float = clamp(1.0 - dist / radius, 0.0, 1.0)
			if falloff <= 0.0:
				continue
			body.health.take_damage(damage * falloff, killer_player_id)
			if body.health.is_alive:
				var direction: Vector3 = offset.normalized() if dist > 0.001 else Vector3.UP
				body.apply_external_impulse(direction * force * falloff)

	lifetime_timer.start()


func _on_lifetime_timeout() -> void:
	queue_free()
