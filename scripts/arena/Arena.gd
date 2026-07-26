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
@onready var terrain_root: Node3D = $NavRegion/Terrain

## Each entry: {position: Vector3, size: Vector3} — footprint (x/z) used for
## overlap checks against later placements.
var _placed: Array[Dictionary] = []

## Top-surface center of each generated platform, exposed so bot patrol
## behavior can occasionally target them directly — with only a couple of
## platforms in a huge arena, fully random patrol points would land on one
## so rarely that the feature would barely ever get used in a normal match.
var _platform_points: Array[Vector3] = []

var _terrain: ArenaTerrain
var _rng := RandomNumberGenerator.new()


## Every peer must produce byte-for-byte the same arena from the same
## seed_value — the server generates a fresh seed once per match/restart and
## sends it to every client (see Main.gd's request_arena_seed/_apply_arena_seed
## RPCs), instead of each peer independently randomizing its own layout.
## Without this, a client's local terrain/obstacles wouldn't match the
## server's authoritative collision, since only the server ever actually
## runs physics — the mismatch shows up as characters appearing to clip
## through terrain or walk through walls that aren't really there.
## Safe to call more than once on the same instance (defensively clears any
## previously generated geometry first) since a client reuses one Arena
## node across a match restart rather than getting a fresh instance like
## the server does.
func generate_arena(seed_value: int) -> void:
	_rng.seed = seed_value
	for child in obstacles_root.get_children():
		obstacles_root.remove_child(child)
		child.free()
	for child in terrain_root.get_children():
		terrain_root.remove_child(child)
		child.free()
	_placed.clear()
	_platform_points.clear()

	_terrain = ArenaTerrain.new()
	var spawn_positions: Array = []
	for sp in get_spawn_points():
		spawn_positions.append(sp.global_transform.origin)
	_terrain.generate(seed_value, spawn_positions)

	# Clamp raw noise slope BEFORE obstacles sample/flatten the heightmap —
	# obstacles read get_height() to place themselves, and the mesh+
	# collision are built from these same final heights, so placement and
	# the built terrain must agree. Clamping afterward instead (as a
	# platform's own flatten_patch call runs mid-placement) would let the
	# heightmap shift again after an obstacle already read its Y from it,
	# leaving that obstacle floating/sunken relative to the real terrain.
	_terrain.clamp_slopes()
	# Obstacles sample/flatten the heightmap as they place themselves —
	# the mesh+collision are only built afterward, from the final
	# (obstacle-flattened) heights, so platforms sit flush instead of
	# clipping into or floating above sloped ground.
	_generate_obstacles()
	_build_terrain_body()

	nav_region.bake_navigation_mesh(false)


func _build_terrain_body() -> void:
	var body := StaticBody3D.new()
	terrain_root.add_child(body)

	var collision := CollisionShape3D.new()
	collision.shape = _terrain.build_collision_shape()
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _terrain.build_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.37, 0.4, 1)
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)


## Obstacle placement can't assume flat y=0 ground now that the arena has
## real terrain — this is the shared entry point every placer samples.
func _get_terrain_height(x: float, z: float) -> float:
	return _terrain.get_height(x, z) if _terrain else 0.0


## Randomized each run so every match gets a different layout — the floor,
## walls, and spawn points stay fixed as the play-area boundary, but cover
## placement changes. Navmesh baking happens at runtime (see _ready), after
## these are placed, so it always reflects the layout that was just rolled.
func _generate_obstacles() -> void:
	# Platforms placed first so they get first pick of open ground — walls
	# and crates fill in around whatever space is left.
	var platform_count := _rng.randi_range(PLATFORM_COUNT_MIN, PLATFORM_COUNT_MAX)
	for i in range(platform_count):
		_place_platform()

	var wall_count := _rng.randi_range(10, 16)
	for i in range(wall_count):
		_place_wall_segment()

	var crate_count := _rng.randi_range(8, 14)
	for i in range(crate_count):
		_place_box_obstacle(CRATE_SCENE, CRATE_SIZE, CRATE_HEIGHT_OFFSET)

	var column_count := _rng.randi_range(4, 7)
	for i in range(column_count):
		_place_box_obstacle(COLUMN_SCENE, COLUMN_SIZE, COLUMN_HEIGHT_OFFSET)


## A raised platform with a ramp up one side — real verticality, not just
## flat-ground cover. The ramp is a single inclined box (not discrete steps):
## CharacterBody3D's move_and_slide handles a smooth slope reliably, whereas
## individual stair-step colliders risk snagging player/bot movement.
func _place_platform() -> void:
	var plat_w := _rng.randf_range(PLATFORM_SIZE_MIN, PLATFORM_SIZE_MAX)
	var plat_d := _rng.randf_range(PLATFORM_SIZE_MIN, PLATFORM_SIZE_MAX)

	# Reserve a generously padded square covering the platform plus the ramp
	# in any of the 4 directions it might end up facing — simpler and safer
	# than modeling the true L-shaped footprint for overlap purposes.
	var clearance: float = max(plat_w, plat_d) + RAMP_RUN * 2.0 + OVERLAP_MARGIN * 2.0
	var pos := _find_valid_position(Vector3(clearance, 0, clearance))
	if not is_finite(pos.x):
		return

	# Flatten the ground under the whole platform+ramp footprint to this
	# point's own height BEFORE reading it for placement — a flat-topped
	## platform box would otherwise clip into or float above sloped terrain.
	_terrain.flatten_patch(Vector2(pos.x, pos.z), clearance * 0.5)
	var ground_y := _get_terrain_height(pos.x, pos.z)

	var platform_body := StaticBody3D.new()
	obstacles_root.add_child(platform_body)
	platform_body.global_transform.origin = Vector3(pos.x, ground_y + PLATFORM_HEIGHT * 0.5, pos.z)

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

	var side: Vector3 = SIDE_DIRECTIONS[_rng.randi() % SIDE_DIRECTIONS.size()]
	var half_dim := plat_d * 0.5 if side.z != 0.0 else plat_w * 0.5
	var top_point := Vector3(pos.x, ground_y + PLATFORM_HEIGHT, pos.z) + side * half_dim
	# The bottom end samples terrain height independently at its own (x,z) —
	# it may land on different local ground than the platform itself — then
	# is buried slightly below that (not flush) so the ramp surface
	# transitions smoothly with no seam/lip for a CharacterBody3D to catch on.
	var bottom_xz := pos + side * (half_dim + RAMP_RUN)
	var bottom_point := Vector3(bottom_xz.x, _get_terrain_height(bottom_xz.x, bottom_xz.z) - 0.4, bottom_xz.z)
	_build_ramp(top_point, bottom_point)

	_placed.append({"position": Vector3(pos.x, 0, pos.z), "size": Vector3(clearance, 0, clearance)})
	_platform_points.append(Vector3(pos.x, ground_y + PLATFORM_HEIGHT, pos.z))


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
	var length := _rng.randf_range(WALL_LENGTH_MIN, WALL_LENGTH_MAX)
	var rotated_90 := _rng.randi() % 2 == 0
	var footprint := Vector3(WALL_THICKNESS, 0, length) if not rotated_90 else Vector3(length, 0, WALL_THICKNESS)

	var pos := _find_valid_position(footprint)
	if not is_finite(pos.x):
		return

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	body.global_transform.origin = Vector3(pos.x, _get_terrain_height(pos.x, pos.z) + WALL_HEIGHT * 0.5, pos.z)
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
	body.global_transform.origin = Vector3(pos.x, _get_terrain_height(pos.x, pos.z) + height_offset, pos.z)

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
			_rng.randf_range(-PLAY_HALF_EXTENT, PLAY_HALF_EXTENT), 0,
			_rng.randf_range(-PLAY_HALF_EXTENT, PLAY_HALF_EXTENT)
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
