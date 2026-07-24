class_name Arena
extends Node3D

const CRATE_SCENE: PackedScene = preload("res://assets/kenney/environment/Models/crate.glb")
const COLUMN_SCENE: PackedScene = preload("res://assets/kenney/environment/Models/column.glb")

const PLAY_HALF_EXTENT := 40.0
const MIN_DIST_FROM_SPAWN := 6.0
const OVERLAP_MARGIN := 1.5
const MAX_PLACEMENT_ATTEMPTS := 60

const CRATE_SIZE := Vector3(1, 1, 1)
const CRATE_HEIGHT_OFFSET := 0.5
const COLUMN_SIZE := Vector3(1, 3, 1)
const COLUMN_HEIGHT_OFFSET := 1.5

const WALL_THICKNESS := 0.6
const WALL_HEIGHT := 3.5
const WALL_LENGTH_MIN := 6.0
const WALL_LENGTH_MAX := 14.0

const PLATFORM_COUNT_MIN := 2
const PLATFORM_COUNT_MAX := 3
const PLATFORM_HEIGHT := 3.0
const PLATFORM_SIZE_MIN := 7.0
const PLATFORM_SIZE_MAX := 10.0
const RAMP_RUN := 6.0
const RAMP_WIDTH := 3.5
const RAMP_THICKNESS := 0.4
const SIDE_DIRECTIONS := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]

@onready var nav_region: NavigationRegion3D = $NavRegion
@onready var spawn_points_root: Node3D = $SpawnPoints
@onready var obstacles_root: Node3D = $NavRegion/Obstacles

## Each entry: {position: Vector3, size: Vector3} — footprint (x/z) used for
## overlap checks against later placements.
var _placed: Array[Dictionary] = []

## Top-surface center of each generated platform, exposed so bot patrol
## behavior can occasionally target them directly — with only a couple of
## platforms in a huge arena, fully random patrol points would land on one
## so rarely that the feature would barely ever get used in a normal match.
var _platform_points: Array[Vector3] = []


func _ready() -> void:
	if not Engine.is_editor_hint():
		randomize()
		_generate_obstacles()
		nav_region.bake_navigation_mesh(false)


## Randomized each run so every match gets a different layout — the floor,
## walls, and spawn points stay fixed as the play-area boundary, but cover
## placement changes. Navmesh baking happens at runtime (see _ready), after
## these are placed, so it always reflects the layout that was just rolled.
func _generate_obstacles() -> void:
	# Platforms placed first so they get first pick of open ground — walls
	# and crates fill in around whatever space is left.
	var platform_count := randi_range(PLATFORM_COUNT_MIN, PLATFORM_COUNT_MAX)
	for i in range(platform_count):
		_place_platform()

	var wall_count := randi_range(10, 16)
	for i in range(wall_count):
		_place_wall_segment()

	var crate_count := randi_range(8, 14)
	for i in range(crate_count):
		_place_box_obstacle(CRATE_SCENE, CRATE_SIZE, CRATE_HEIGHT_OFFSET)

	var column_count := randi_range(4, 7)
	for i in range(column_count):
		_place_box_obstacle(COLUMN_SCENE, COLUMN_SIZE, COLUMN_HEIGHT_OFFSET)


## A raised platform with a ramp up one side — real verticality, not just
## flat-ground cover. The ramp is a single inclined box (not discrete steps):
## CharacterBody3D's move_and_slide handles a smooth slope reliably, whereas
## individual stair-step colliders risk snagging player/bot movement.
func _place_platform() -> void:
	var plat_w := randf_range(PLATFORM_SIZE_MIN, PLATFORM_SIZE_MAX)
	var plat_d := randf_range(PLATFORM_SIZE_MIN, PLATFORM_SIZE_MAX)

	# Reserve a generously padded square covering the platform plus the ramp
	# in any of the 4 directions it might end up facing — simpler and safer
	# than modeling the true L-shaped footprint for overlap purposes.
	var clearance: float = max(plat_w, plat_d) + RAMP_RUN * 2.0 + OVERLAP_MARGIN * 2.0
	var pos := _find_valid_position(Vector3(clearance, 0, clearance))
	if not is_finite(pos.x):
		return

	var platform_body := StaticBody3D.new()
	obstacles_root.add_child(platform_body)
	platform_body.global_transform.origin = Vector3(pos.x, PLATFORM_HEIGHT * 0.5, pos.z)

	var platform_size := Vector3(plat_w, PLATFORM_HEIGHT, plat_d)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = platform_size
	collision.shape = shape
	platform_body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = platform_size
	mesh_instance.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.42, 0.4, 1)
	mesh_instance.material_override = mat
	platform_body.add_child(mesh_instance)

	var side: Vector3 = SIDE_DIRECTIONS[randi() % SIDE_DIRECTIONS.size()]
	var half_dim := plat_d * 0.5 if side.z != 0.0 else plat_w * 0.5
	var top_point := pos + side * half_dim + Vector3(0, PLATFORM_HEIGHT, 0)
	# The bottom end is buried slightly below floor level (not flush at
	# exactly y=0) so the ramp surface transitions smoothly into the floor
	# with no seam/lip for a CharacterBody3D to catch on.
	var bottom_point := pos + side * (half_dim + RAMP_RUN) + Vector3(0, -0.4, 0)
	_build_ramp(top_point, bottom_point)

	_placed.append({"position": Vector3(pos.x, 0, pos.z), "size": Vector3(clearance, 0, clearance)})
	_platform_points.append(Vector3(pos.x, PLATFORM_HEIGHT, pos.z))


func _build_ramp(top_point: Vector3, bottom_point: Vector3) -> void:
	var diff := bottom_point - top_point
	var slope_length := diff.length()
	if slope_length < 0.01:
		return
	var mid := (top_point + bottom_point) * 0.5

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	body.global_transform = Transform3D(_basis_looking(diff), mid)

	var ramp_size := Vector3(RAMP_WIDTH, RAMP_THICKNESS, slope_length)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = ramp_size
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = ramp_size
	mesh_instance.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.45, 1)
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)


## Builds a basis whose local Z points along `direction`, with local X kept
## horizontal (perpendicular to both `direction` and world up) so the ramp's
## width stays level instead of twisting — local Y then ends up roughly
## perpendicular to the slope, which is what we want for box "thickness".
func _basis_looking(direction: Vector3) -> Basis:
	var z_axis := direction.normalized()
	var x_axis := z_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


## Long, axis-aligned blocking walls — actual cover that breaks sightlines
## across the arena, unlike a knee-high crate. Built from primitive geometry
## (not a Kenney tile) since these need arbitrary lengths without visibly
## stretching a small modular texture.
func _place_wall_segment() -> void:
	var length := randf_range(WALL_LENGTH_MIN, WALL_LENGTH_MAX)
	var rotated_90 := randi() % 2 == 0
	var footprint := Vector3(WALL_THICKNESS, 0, length) if not rotated_90 else Vector3(length, 0, WALL_THICKNESS)

	var pos := _find_valid_position(footprint)
	if not is_finite(pos.x):
		return

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	body.global_transform.origin = Vector3(pos.x, WALL_HEIGHT * 0.5, pos.z)
	if rotated_90:
		body.rotate_y(deg_to_rad(90.0))

	var box_size := Vector3(WALL_THICKNESS, WALL_HEIGHT, length)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	mesh_instance.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.45, 1)
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	_placed.append({"position": body.global_transform.origin, "size": footprint})


func _place_box_obstacle(model_scene: PackedScene, box_size: Vector3, height_offset: float) -> void:
	var pos := _find_valid_position(box_size)
	if not is_finite(pos.x):
		return

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	body.global_transform.origin = Vector3(pos.x, height_offset, pos.z)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	body.add_child(collision)

	body.add_child(model_scene.instantiate())

	_placed.append({"position": body.global_transform.origin, "size": box_size})


func _find_valid_position(footprint: Vector3) -> Vector3:
	for attempt in range(MAX_PLACEMENT_ATTEMPTS):
		var candidate := Vector3(
			randf_range(-PLAY_HALF_EXTENT, PLAY_HALF_EXTENT), 0,
			randf_range(-PLAY_HALF_EXTENT, PLAY_HALF_EXTENT)
		)
		if _clears_spawns(candidate, footprint) and _clears_obstacles(candidate, footprint):
			return candidate
	return Vector3.INF


func _clears_spawns(pos: Vector3, footprint: Vector3) -> bool:
	var half_x := footprint.x * 0.5 + MIN_DIST_FROM_SPAWN
	var half_z := footprint.z * 0.5 + MIN_DIST_FROM_SPAWN
	for sp in get_spawn_points():
		var sp_pos: Vector3 = sp.global_transform.origin
		if abs(sp_pos.x - pos.x) < half_x and abs(sp_pos.z - pos.z) < half_z:
			return false
	return true


func _clears_obstacles(pos: Vector3, footprint: Vector3) -> bool:
	for entry in _placed:
		var other_pos: Vector3 = entry["position"]
		var other_size: Vector3 = entry["size"]
		var overlap_x: float = footprint.x * 0.5 + other_size.x * 0.5 + OVERLAP_MARGIN
		var overlap_z: float = footprint.z * 0.5 + other_size.z * 0.5 + OVERLAP_MARGIN
		if abs(other_pos.x - pos.x) < overlap_x and abs(other_pos.z - pos.z) < overlap_z:
			return false
	return true


func get_platform_points() -> Array[Vector3]:
	return _platform_points


func get_spawn_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for child in spawn_points_root.get_children():
		if child is Node3D:
			points.append(child)
	return points
