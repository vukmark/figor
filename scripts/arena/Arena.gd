class_name Arena
extends Node3D

@onready var nav_region: NavigationRegion3D = $NavRegion
@onready var spawn_points_root: Node3D = $SpawnPoints


func _ready() -> void:
	if not Engine.is_editor_hint():
		nav_region.bake_navigation_mesh(false)


func get_spawn_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for child in spawn_points_root.get_children():
		if child is Node3D:
			points.append(child)
	return points
