class_name HealthBar3D
extends Node3D

## Full width of the background bar — the fill quad shrinks from this same
## width, keeping its left edge pinned to the background's left edge so it
## reads as "draining" rather than shrinking from the center.
const WIDTH := 0.6

@onready var _fill: MeshInstance3D = $Fill


func set_ratio(ratio: float) -> void:
	ratio = clamp(ratio, 0.0, 1.0)
	_fill.scale.x = ratio
	_fill.position.x = -(WIDTH * 0.5) * (1.0 - ratio)
