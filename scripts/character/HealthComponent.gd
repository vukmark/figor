class_name HealthComponent
extends Node

signal died(killer_peer_id: int)

@export var max_health := Constants.HEALTH_MAX

var current_health := max_health
var is_alive := true


## Authority-only. Guards against any double-processing: is_alive flips to
## false the instant health hits zero, before died() even fires, so a victim
## can never be counted twice regardless of overlap/ordering elsewhere.
func take_damage(amount: float, source_peer_id: int = -1) -> void:
	if not is_alive:
		return
	current_health = max(current_health - amount, 0.0)
	if current_health <= 0.0:
		is_alive = false
		died.emit(source_peer_id)


func reset() -> void:
	current_health = max_health
	is_alive = true
