class_name Arena
extends Node3D

const CRATE_SCENE: PackedScene = preload("res://assets/kenney/environment/Models/crate.glb")
const COLUMN_SCENE: PackedScene = preload("res://assets/kenney/environment/Models/column.glb")
const WALL_SCENE: PackedScene = preload("res://assets/kenney/environment/Models/wall.glb")
const WALL_CORNER_SCENE: PackedScene = preload("res://assets/kenney/environment/Models/wall-corner.glb")
const WALL_DOORWAY_SCENE: PackedScene = preload("res://assets/kenney/environment/Models/wall-doorway.glb")
const FLOOR_SCENE: PackedScene = preload("res://assets/kenney/environment/Models/floor-square.glb")

## Curated subset of Kenney's Nature Kit (329 models total, dropped in whole
## at assets/kenney/nature/Models/ per this project's existing per-pack
## convention — only a handful are actually preloaded/used, same as the
## environment kit's 145 files vs. 6 used above) — for outdoor atmosphere
## instead of gray industrial boxes.
const TREE_SCENES: Array[PackedScene] = [
	preload("res://assets/kenney/nature/Models/tree_default.glb"),
	preload("res://assets/kenney/nature/Models/tree_detailed.glb"),
	preload("res://assets/kenney/nature/Models/tree_oak.glb"),
	preload("res://assets/kenney/nature/Models/tree_pineRoundC.glb"),
	preload("res://assets/kenney/nature/Models/tree_pineTallA.glb"),
	preload("res://assets/kenney/nature/Models/tree_fat.glb"),
]
const ROCK_SCENES: Array[PackedScene] = [
	preload("res://assets/kenney/nature/Models/rock_largeA.glb"),
	preload("res://assets/kenney/nature/Models/rock_largeD.glb"),
	preload("res://assets/kenney/nature/Models/rock_smallA.glb"),
	preload("res://assets/kenney/nature/Models/rock_smallD.glb"),
	preload("res://assets/kenney/nature/Models/rock_tallB.glb"),
]
const PLANT_SCENES: Array[PackedScene] = [
	preload("res://assets/kenney/nature/Models/grass.glb"),
	preload("res://assets/kenney/nature/Models/grass_large.glb"),
	preload("res://assets/kenney/nature/Models/flower_purpleA.glb"),
	preload("res://assets/kenney/nature/Models/flower_redA.glb"),
	preload("res://assets/kenney/nature/Models/flower_yellowA.glb"),
	preload("res://assets/kenney/nature/Models/mushroom_red.glb"),
]
## Added for more forest-floor variety beyond "just trees" (real feedback:
## map still read as "only trees" even at good tree density). Standalone
## props like crates/rocks, not modular connecting pieces like the wall
## kit — low risk of the "doesn't connect" problem that hit room corners.
## Skipped the pack's `cliff_*` rock-formation models for the same reason
## walls had trouble: they're modular pieces meant to connect to each
## other, not standalone props, so placing them individually would risk
## the same "looks disconnected" problem.
const STUMP_SCENES: Array[PackedScene] = [
	preload("res://assets/kenney/nature/Models/stump_round.glb"),
	preload("res://assets/kenney/nature/Models/stump_old.glb"),
	preload("res://assets/kenney/nature/Models/stump_square.glb"),
]
const LOG_SCENES: Array[PackedScene] = [
	preload("res://assets/kenney/nature/Models/log.glb"),
	preload("res://assets/kenney/nature/Models/log_large.glb"),
	preload("res://assets/kenney/nature/Models/log_stack.glb"),
]

## 3x the original 40.0, by request — kept proportional to
## ArenaTerrain.HALF_EXTENT (150.0) the same way it always was (80% of it,
## same ratio as the original 40/50), so obstacle/prop/spawn placement fills
## proportionally more of the map instead of staying clustered in a small
## area of a much bigger terrain.
const PLAY_HALF_EXTENT := 120.0
const MIN_DIST_FROM_SPAWN := 6.0
const OVERLAP_MARGIN := 1.5
const MAX_PLACEMENT_ATTEMPTS := 60

## Real mesh sizes, confirmed by parsing crate.glb/column.glb's own glTF
## accessor bounds directly — these previously didn't match the actual
## models at all (collider up to 15x too big for column.glb), a
## pre-existing bug unrelated to anything else in this pass, fixed while
## touching this file.
const CRATE_SIZE := Vector3(0.5, 0.5, 0.5)
const CRATE_HEIGHT_OFFSET := 0.25
const COLUMN_SIZE := Vector3(0.2, 1.0, 0.2)
const COLUMN_HEIGHT_OFFSET := 0.5

## Disabled by request (count 0, code kept intact — same "disable via
## constant" pattern used elsewhere in this file): industrial crate/column
## props clash with the nature/hill look now that the map is going for
## outdoor terrain, not gray blocks. Was randi_range(8,14)/randi_range(4,7)
## inline in _generate_obstacles(), pulled out to named constants here so
## disabling them follows the same pattern as everything else.
const CRATE_COUNT_MIN := 0
const CRATE_COUNT_MAX := 0
const COLUMN_COUNT_MIN := 0
const COLUMN_COUNT_MAX := 0

## Disabled by request (count 0, code kept intact — same "disable via
## constant" pattern as STRUCTURE_COUNT_MIN/MAX and NOISE_AMPLITUDE):
## flat-color industrial-looking platforms/ramps clash with the nature/hill
## look now that the map is going for outdoor terrain, not gray blocks.
const PLATFORM_COUNT_MIN := 0
const PLATFORM_COUNT_MAX := 0
const PLATFORM_HEIGHT := 3.0
const PLATFORM_SIZE_MIN := 7.0
const PLATFORM_SIZE_MAX := 10.0
const RAMP_RUN := 6.0
const RAMP_WIDTH := 3.5
const RAMP_THICKNESS := 0.4
const SIDE_DIRECTIONS := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]

## Small walled compounds assembled from the Kenney modular wall kit, snapped
## to its native 1-unit grid — an intentional structure (real corners/
## doorway) instead of the scattered flat-color boxes everything else here
## still uses. Kit pieces are modeled at 1m/cell (confirmed by parsing the
## glb files' own mesh bounds directly) with a base-center pivot; native
## wall height (1m) is too short for a 1.8m-tall Character, so the whole
## structure is scaled up as one unit rather than hand-scaling every piece.
##
## Disabled by request (count 0, code kept intact rather than deleted —
## same pattern as NOISE_AMPLITUDE going to 0.0 for flat ground): the corner
## pieces never looked properly connected (an unresolved rendering-facing
## guess, `CORNER_YAW_DEGREES` below, that was never confirmed against an
## actual screenshot before this), and the arena is going for a natural/
## nature-kit look instead of boxy rooms now. Bump these back up (and
## un-flatten the terrain, see ArenaTerrain.NOISE_AMPLITUDE) to bring
## structures back.
const STRUCTURE_SCALE := 2.5
const STRUCTURE_COUNT_MIN := 0
const STRUCTURE_COUNT_MAX := 0
const STRUCTURE_INTERIOR_MIN := 3
const STRUCTURE_INTERIOR_MAX := 6
const STRUCTURE_WALL_COLLISION_SIZE := Vector3(0.2, 1.0, 1.0)
const STRUCTURE_CORNER_COLLISION_SIZE := Vector3(1.0, 1.0, 1.0)

## Real mesh sizes for the curated Nature Kit selection above, confirmed by
## parsing each glb's own glTF accessor bounds directly (same verified
## method as CRATE_SIZE/COLUMN_SIZE, not guessed) — every file measured has
## min.y == 0 (base pivot, same convention as the environment kit), so no
## height offset is needed for any of these; they place directly at
## _get_terrain_height(x, z).
##
## Trees: measured bounds are the *whole* mesh (trunk+canopy combined,
## ranging ~0.39-0.85 wide across the 6 chosen variants) — a full-canopy
## collision box would block movement/sightlines the visual canopy overhang
## doesn't really need to block. One shared, deliberately narrower
## trunk-only approximation is used instead (undersizing is safer than
## oversizing, same principle already applied to CRATE_SIZE/COLUMN_SIZE),
## tall enough to still block/cover a standing 1.8m-tall Character.
const TREE_TRUNK_SIZE := Vector3(0.3, 1.5, 0.3)

## Rocks vary far more in size than trees (0.36 up to 1.07 — roughly 3x, well
## past the ~40% threshold where one shared size stops being reasonable), so
## each gets its own measured collision size instead, indexed the same as
## ROCK_SCENES.
const ROCK_COLLISION_SIZES: Array[Vector3] = [
	Vector3(0.79, 0.26, 1.02),  # rock_largeA
	Vector3(1.07, 0.57, 1.03),  # rock_largeD
	Vector3(0.36, 0.19, 0.36),  # rock_smallA
	Vector3(0.43, 0.23, 0.37),  # rock_smallD
	Vector3(0.77, 0.88, 0.77),  # rock_tallB
]

## Measured the same verified way as rocks. Stump sizes vary little
## (~0.32-0.36, well under the ~40% threshold), but per-scene sizes are used
## anyway since they're already measured and it costs nothing extra.
const STUMP_COLLISION_SIZES: Array[Vector3] = [
	Vector3(0.321, 0.206, 0.371),  # stump_round
	Vector3(0.357, 0.266, 0.371),  # stump_old
	Vector3(0.36, 0.3, 0.3),       # stump_square
]
## log.glb/log_stack.glb are already modeled lying down (low height, long
## on one horizontal axis) — no reorientation needed, just the same random
## yaw every other prop here gets.
const LOG_COLLISION_SIZES: Array[Vector3] = [
	Vector3(0.234, 0.173, 0.71),  # log
	Vector3(1.0, 0.417, 0.549),   # log_large
	Vector3(0.425, 0.346, 0.71),  # log_stack
]

## ~4x the original 5-8, since the map area itself grew 9x (3x linear) but
## prop counts didn't scale with it at all — confirmed by a real screenshot
## report ("still looks empty") after the map-size change. Not a full 9x:
## trees are the most expensive prop (each gets its own StaticBody3D +
## collider), and generate_arena() already measured at ~3.5s for the bigger
## map before this — kept trees-per-cluster unchanged and scaled cluster
## *count* instead, so total tree count grows roughly in proportion without
## also multiplying per-cluster cost.
const TREE_CLUSTER_COUNT_MIN := 20
const TREE_CLUSTER_COUNT_MAX := 30
## Widened again alongside the second scale bump below — canopies up to
## ~0.85*8=6.8 units wide would crowd badly at the previous 7.0 radius.
const TREE_CLUSTER_RADIUS := 11.0
const TREES_PER_CLUSTER_MIN := 3
const TREES_PER_CLUSTER_MAX := 6
## Native mesh heights for the chosen tree variants are only ~1.15-1.7 units
## (measured directly from the glb files) — barely taller than a 1.8-unit
## Character, reading as shrubs rather than trees. First bump (0.85-1.25 →
## 2.5-4.0, i.e. trees ~2.9-6.8 units tall) still read as too small in a
## real playtest — pushed further so trees are unambiguously several times
## taller than a player, closer to real tree-to-human proportions
## (typically 3x-7x+), not just "somewhat taller."
const TREE_SCALE_MIN := 5.0
const TREE_SCALE_MAX := 8.0

## ~4x the original 6-10, same density-vs-bigger-map rationale as
## TREE_CLUSTER_COUNT above — rocks are cheap (one StaticBody3D each, no
## clustering), so scaling these directly is low-risk.
const ROCK_COUNT_MIN := 24
const ROCK_COUNT_MAX := 36
const ROCK_SCALE_MIN := 0.8
const ROCK_SCALE_MAX := 1.3

## Bumped again (~2.5x) by request — "ground is a bit poor, add grass" —
## plant clusters are the cheapest prop (visual-only, no collision, no
## _placed bookkeeping), so this is the safest one to scale up generously.
## Not pushed into the many-hundreds/thousands range in one jump: at that
## density individual MeshInstance3D nodes per blade stop being the right
## approach and MultiMeshInstance3D (batched instancing) becomes worth the
## extra complexity — flagged as the next step if this still isn't enough,
## not implemented preemptively without being able to actually measure
## runtime frame rate in this headless-only environment.
const PLANT_CLUSTER_COUNT_MIN := 100
const PLANT_CLUSTER_COUNT_MAX := 140
const PLANTS_PER_CLUSTER_MIN := 4
const PLANTS_PER_CLUSTER_MAX := 9
const PLANT_CLUSTER_RADIUS := 3.0
const PLANT_SCALE_MIN := 0.8
const PLANT_SCALE_MAX := 1.3

## Forest-floor detail props (stumps/logs) — cheap like rocks (one
## StaticBody3D each, no clustering), scaled at counts comparable to rocks.
const STUMP_COUNT_MIN := 18
const STUMP_COUNT_MAX := 28
const STUMP_SCALE_MIN := 0.8
const STUMP_SCALE_MAX := 1.4
const LOG_COUNT_MIN := 14
const LOG_COUNT_MAX := 22
## Native log lengths are only ~0.7-1.0 units — reading as small twigs at
## 0.8-1.4x scale, per real feedback. Bumped to give a real fallen-log
## presence (proportionally smaller than the tree scale-up, since a log
## doesn't need to look like a giant redwood — just a substantial section
## of one).
const LOG_SCALE_MIN := 3.0
const LOG_SCALE_MAX := 5.0

## First-guess yaw per corner (degrees), keyed by (is_max_i, is_max_j) —
## wall-corner.glb's facing direction can't be determined from mesh bounds
## alone (bounds are symmetric regardless of which way the model actually
## faces), so this needs a one-time visual check in the editor and is very
## likely to need adjusting (shifting all four values by the same 90°
## offset, or reversing the sequence, are the two most likely fixes).
const CORNER_YAW_DEGREES := {
	Vector2i(0, 0): 0.0,
	Vector2i(1, 0): 90.0,
	Vector2i(1, 1): 180.0,
	Vector2i(0, 1): 270.0,
}

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
	# Must run right after clamp_slopes(), before anything else samples or
	# further modifies the heightmap — see build_boundary_ridge()'s own doc
	# comment for why this ordering is load-bearing (clamp_slopes() must
	# never run again afterward, or it would flatten the ridge back down to
	# something climbable). Replaces the old invisible perimeter walls: this
	# is now the only thing containing players within the map.
	_terrain.build_boundary_ridge()
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
	# Color comes from per-vertex data baked into the mesh by
	# ArenaTerrain.build_mesh() (see its doc comment for why a texture-based
	# approach like triplanar wasn't actually correct here) — this just
	# tells the material to use it instead of a flat albedo_color.
	mat.vertex_color_use_as_albedo = true
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
	# Structures placed first, before platforms — they're the most
	# position-constrained (largest footprints) and the main visual
	# anchors, so they get first pick of open ground, same rationale
	# platforms already got before structures existed.
	var structure_count := _rng.randi_range(STRUCTURE_COUNT_MIN, STRUCTURE_COUNT_MAX)
	for i in range(structure_count):
		_place_structure()

	var platform_count := _rng.randi_range(PLATFORM_COUNT_MIN, PLATFORM_COUNT_MAX)
	for i in range(platform_count):
		_place_platform()

	var crate_count := _rng.randi_range(CRATE_COUNT_MIN, CRATE_COUNT_MAX)
	for i in range(crate_count):
		_place_box_obstacle(CRATE_SCENE, CRATE_SIZE, CRATE_HEIGHT_OFFSET)

	var column_count := _rng.randi_range(COLUMN_COUNT_MIN, COLUMN_COUNT_MAX)
	for i in range(column_count):
		_place_box_obstacle(COLUMN_SCENE, COLUMN_SIZE, COLUMN_HEIGHT_OFFSET)

	# Foliage last — the least gameplay-constrained layer, so it fills
	# whatever open ground remains instead of competing with structures/
	# platforms/crates/columns for the best clearings.
	var tree_cluster_count := _rng.randi_range(TREE_CLUSTER_COUNT_MIN, TREE_CLUSTER_COUNT_MAX)
	for i in range(tree_cluster_count):
		_place_tree_cluster()

	var rock_count := _rng.randi_range(ROCK_COUNT_MIN, ROCK_COUNT_MAX)
	for i in range(rock_count):
		_place_rock()

	var stump_count := _rng.randi_range(STUMP_COUNT_MIN, STUMP_COUNT_MAX)
	for i in range(stump_count):
		_place_stump()

	var log_count := _rng.randi_range(LOG_COUNT_MIN, LOG_COUNT_MAX)
	for i in range(log_count):
		_place_log()

	var plant_cluster_count := _rng.randi_range(PLANT_CLUSTER_COUNT_MIN, PLANT_CLUSTER_COUNT_MAX)
	for i in range(plant_cluster_count):
		_place_plant_cluster()


## A small walled compound: a rectangular ring of wall.glb/wall-corner.glb
## snapped to the kit's native 1-unit grid, with exactly one doorway cell
## (wall-doorway.glb, deliberately given no collider so bots can path
## through it — bake_navigation_mesh()'s PARSED_GEOMETRY_STATIC_COLLIDERS
## mode already only sees what actually has a StaticBody3D/CollisionShape3D,
## same as every other obstacle here) and floor-square.glb tiling the
## interior. One StaticBody3D holds every wall/corner CollisionShape3D as a
## compound collider, mirroring how the terrain's own single StaticBody3D
## already holds one collision shape + one mesh — same pattern, more shapes.
func _place_structure() -> void:
	var interior_w := _rng.randi_range(STRUCTURE_INTERIOR_MIN, STRUCTURE_INTERIOR_MAX)
	var interior_d := _rng.randi_range(STRUCTURE_INTERIOR_MIN, STRUCTURE_INTERIOR_MAX)
	var width_cells := interior_w + 2
	var depth_cells := interior_d + 2

	var rotation_steps := _rng.randi_range(0, 3)
	var rotated := rotation_steps % 2 == 1
	var world_w := width_cells * STRUCTURE_SCALE
	var world_d := depth_cells * STRUCTURE_SCALE
	var footprint := Vector3(world_d, 0, world_w) if rotated else Vector3(world_w, 0, world_d)

	var pos := _find_valid_position(footprint)
	if not is_finite(pos.x):
		return

	_terrain.flatten_patch(Vector2(pos.x, pos.z), max(world_w, world_d) * 0.5 * 1.2)
	var ground_y := _get_terrain_height(pos.x, pos.z)

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	var basis := Basis(Vector3.UP, rotation_steps * (PI / 2.0)).scaled(Vector3.ONE * STRUCTURE_SCALE)
	body.global_transform = Transform3D(basis, Vector3(pos.x, ground_y, pos.z))

	# Collect straight-perimeter (non-corner) cells first so a doorway cell
	# can be picked from among them via _rng, same determinism requirement
	# as every other random choice in this file.
	var straight_cells: Array[Vector2i] = []
	for j in range(depth_cells):
		for i in range(width_cells):
			var is_perimeter: bool = i == 0 or i == width_cells - 1 or j == 0 or j == depth_cells - 1
			var is_corner: bool = (i == 0 or i == width_cells - 1) and (j == 0 or j == depth_cells - 1)
			if is_perimeter and not is_corner:
				straight_cells.append(Vector2i(i, j))
	var door_cell := straight_cells[_rng.randi() % straight_cells.size()] if not straight_cells.is_empty() else Vector2i(-1, -1)

	for j in range(depth_cells):
		for i in range(width_cells):
			var is_corner: bool = (i == 0 or i == width_cells - 1) and (j == 0 or j == depth_cells - 1)
			var is_perimeter: bool = i == 0 or i == width_cells - 1 or j == 0 or j == depth_cells - 1
			var local_x: float = (i + 0.5) - width_cells * 0.5
			var local_z: float = (j + 0.5) - depth_cells * 0.5
			var local_pos := Vector3(local_x, 0.0, local_z)

			if is_corner:
				var corner_key := Vector2i(1 if i == width_cells - 1 else 0, 1 if j == depth_cells - 1 else 0)
				var yaw: float = deg_to_rad(CORNER_YAW_DEGREES[corner_key])
				_add_structure_piece(body, WALL_CORNER_SCENE, local_pos, yaw, STRUCTURE_CORNER_COLLISION_SIZE)
			elif is_perimeter:
				# Rows (j==0/last) need the wall's native length axis (Z)
				# rotated onto X; columns (i==0/last) already match natively.
				var is_row: bool = j == 0 or j == depth_cells - 1
				var yaw: float = deg_to_rad(90.0) if is_row else 0.0
				if Vector2i(i, j) == door_cell:
					_add_structure_piece(body, WALL_DOORWAY_SCENE, local_pos, yaw, Vector3.ZERO)
				else:
					_add_structure_piece(body, WALL_SCENE, local_pos, yaw, STRUCTURE_WALL_COLLISION_SIZE)
			else:
				var floor_instance := FLOOR_SCENE.instantiate()
				floor_instance.position = local_pos + Vector3(0, 0.02, 0)
				body.add_child(floor_instance)

	_placed.append({"position": Vector3(pos.x, 0, pos.z), "size": footprint})


## Adds one wall/corner/doorway piece's visual (always) and collision
## (skipped when collision_size is Vector3.ZERO — the doorway cell, so bots
## can path through the gap) as children of `body`, both at the same local
## cell position/yaw so they never visually drift apart from their collider.
func _add_structure_piece(body: StaticBody3D, scene: PackedScene, local_pos: Vector3, yaw: float, collision_size: Vector3) -> void:
	var mesh_instance := scene.instantiate()
	mesh_instance.position = local_pos
	mesh_instance.rotate_y(yaw)
	body.add_child(mesh_instance)

	if collision_size == Vector3.ZERO:
		return
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = collision_size
	collision.shape = shape
	collision.position = local_pos
	collision.rotate_y(yaw)
	body.add_child(collision)


## Shared material for platforms/ramps/loose wall segments, replacing their
## previous perfectly flat StandardMaterial3D.albedo_color — pulls them into
## the same "actually has texture variation" family as the terrain (vertex
## colors) and the new structures/crates/columns (real Kenney textures).
## NoiseTexture2D + triplanar is safe here (unlike the terrain height case,
## see ArenaTerrain.build_mesh()'s doc comment) since it's just a repeating
## mottled speckle pattern with no directional/world-position meaning to get
## wrong — it looks fine from any box face. Fixed noise seed since this is a
## texture pattern, not gameplay RNG (must not touch the seeded _rng).
func _structural_material(tint: Color) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = 1
	noise.frequency = 0.6
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 64
	noise_tex.height = 64
	noise_tex.seamless = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = noise_tex
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.35
	return mat


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
	mesh_instance.material_override = _structural_material(Color(0.45, 0.42, 0.4, 1))
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
	mesh_instance.material_override = _structural_material(Color(0.5, 0.48, 0.45, 1))
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


## A loose copse of trees rather than one standalone tree — real clearings
## have clumps with open ground between them, not evenly-spaced singles.
## Only the cluster center is checked against the rest of the arena via
## _find_valid_position; trees *within* one cluster are allowed (expected)
## to stand close together, so intra-cluster overlap isn't checked — but
## each tree still gets its own _placed entry so later placements (rocks,
## other clusters) correctly avoid the space it actually occupies.
func _place_tree_cluster() -> void:
	var footprint := Vector3(TREE_CLUSTER_RADIUS, 0, TREE_CLUSTER_RADIUS) * 2.2
	var center := _find_valid_position(footprint)
	if not is_finite(center.x):
		return

	var tree_count := _rng.randi_range(TREES_PER_CLUSTER_MIN, TREES_PER_CLUSTER_MAX)
	for i in range(tree_count):
		# Uniform point in a disk via sqrt(rand) — area-uniform density, not
		# radius-uniform (which would over-cluster trees near the center).
		var angle := _rng.randf_range(0.0, TAU)
		var radius := TREE_CLUSTER_RADIUS * sqrt(_rng.randf())
		var tree_pos := center + Vector3(cos(angle), 0, sin(angle)) * radius

		var scene: PackedScene = TREE_SCENES[_rng.randi() % TREE_SCENES.size()]
		var scale_factor := _rng.randf_range(TREE_SCALE_MIN, TREE_SCALE_MAX)
		var yaw := _rng.randf_range(0.0, TAU)
		var ground_y := _get_terrain_height(tree_pos.x, tree_pos.z)

		var body := StaticBody3D.new()
		obstacles_root.add_child(body)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor)
		body.global_transform = Transform3D(basis, Vector3(tree_pos.x, ground_y, tree_pos.z))

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = TREE_TRUNK_SIZE
		collision.shape = shape
		body.add_child(collision)

		body.add_child(scene.instantiate())

		_placed.append({
			"position": Vector3(tree_pos.x, 0, tree_pos.z),
			"size": TREE_TRUNK_SIZE * scale_factor,
		})


## Single standalone rock — structurally like _place_box_obstacle but with
## per-instance scale/rotation variety and a per-scene collision size (see
## ROCK_COLLISION_SIZES's doc comment for why rocks can't share one size the
## way crates/columns/tree trunks do). Kept as its own function rather than
## generalizing _place_box_obstacle: that function is still used as-is for
## crates/columns, and adding new _rng draws inside it would reorder the
## shared random stream those already rely on for determinism.
func _place_rock() -> void:
	var index := _rng.randi() % ROCK_SCENES.size()
	var scale_factor := _rng.randf_range(ROCK_SCALE_MIN, ROCK_SCALE_MAX)
	var base_size: Vector3 = ROCK_COLLISION_SIZES[index]
	var box_size := base_size * scale_factor

	var pos := _find_valid_position(box_size)
	if not is_finite(pos.x):
		return

	var yaw := _rng.randf_range(0.0, TAU)
	var ground_y := _get_terrain_height(pos.x, pos.z)

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor)
	body.global_transform = Transform3D(basis, Vector3(pos.x, ground_y, pos.z))

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = base_size
	collision.shape = shape
	body.add_child(collision)

	body.add_child(ROCK_SCENES[index].instantiate())

	_placed.append({"position": Vector3(pos.x, 0, pos.z), "size": box_size})


## Forest-floor detail, structurally identical to _place_rock() — see that
## function's doc comment for why this is its own function rather than a
## generalized shared helper.
func _place_stump() -> void:
	var index := _rng.randi() % STUMP_SCENES.size()
	var scale_factor := _rng.randf_range(STUMP_SCALE_MIN, STUMP_SCALE_MAX)
	var base_size: Vector3 = STUMP_COLLISION_SIZES[index]
	var box_size := base_size * scale_factor

	var pos := _find_valid_position(box_size)
	if not is_finite(pos.x):
		return

	var yaw := _rng.randf_range(0.0, TAU)
	var ground_y := _get_terrain_height(pos.x, pos.z)

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor)
	body.global_transform = Transform3D(basis, Vector3(pos.x, ground_y, pos.z))

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = base_size
	collision.shape = shape
	body.add_child(collision)

	body.add_child(STUMP_SCENES[index].instantiate())

	_placed.append({"position": Vector3(pos.x, 0, pos.z), "size": box_size})


## Forest-floor detail, structurally identical to _place_rock() — see that
## function's doc comment for why this is its own function. log.glb/
## log_stack.glb are already modeled lying down (see LOG_COLLISION_SIZES's
## doc comment), so the same random yaw every other prop gets is enough —
## no special "lay it down" reorientation needed.
func _place_log() -> void:
	var index := _rng.randi() % LOG_SCENES.size()
	var scale_factor := _rng.randf_range(LOG_SCALE_MIN, LOG_SCALE_MAX)
	var base_size: Vector3 = LOG_COLLISION_SIZES[index]
	var box_size := base_size * scale_factor

	var pos := _find_valid_position(box_size)
	if not is_finite(pos.x):
		return

	var yaw := _rng.randf_range(0.0, TAU)
	var ground_y := _get_terrain_height(pos.x, pos.z)

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor)
	body.global_transform = Transform3D(basis, Vector3(pos.x, ground_y, pos.z))

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = base_size
	collision.shape = shape
	body.add_child(collision)

	body.add_child(LOG_SCENES[index].instantiate())

	_placed.append({"position": Vector3(pos.x, 0, pos.z), "size": box_size})


## Visual-only ground clutter (grass/flowers/mushrooms) — deliberately skips
## _find_valid_position/_clears_obstacles/_placed entirely. Clutter is
## expected to overlap into tree/rock footprints (grass growing up around a
## rock, not avoiding it) and is cheap/non-blocking, so there's nothing to
## protect other placements from and nothing for other placements to avoid
## in return. Still draws every value from the seeded _rng — determinism
## matters even without collision, since non-deterministic decoration could
## block a sightline differently for different players, a real fairness bug
## not just a cosmetic one. Does do one cheap _clears_spawns-only check so a
## spawn point doesn't visually end up buried in a flower patch; if that
## fails the cluster is just skipped (no retry) since dropping one patch of
## decoration is harmless, unlike a real obstacle placement.
func _place_plant_cluster() -> void:
	var center := Vector3(
		_rng.randf_range(-PLAY_HALF_EXTENT, PLAY_HALF_EXTENT), 0,
		_rng.randf_range(-PLAY_HALF_EXTENT, PLAY_HALF_EXTENT)
	)
	if not _clears_spawns(center, Vector3(PLANT_CLUSTER_RADIUS, 0, PLANT_CLUSTER_RADIUS) * 2.0):
		return

	var plant_count := _rng.randi_range(PLANTS_PER_CLUSTER_MIN, PLANTS_PER_CLUSTER_MAX)
	for i in range(plant_count):
		var angle := _rng.randf_range(0.0, TAU)
		var radius := PLANT_CLUSTER_RADIUS * sqrt(_rng.randf())
		var plant_pos := center + Vector3(cos(angle), 0, sin(angle)) * radius

		var scene: PackedScene = PLANT_SCENES[_rng.randi() % PLANT_SCENES.size()]
		var scale_factor := _rng.randf_range(PLANT_SCALE_MIN, PLANT_SCALE_MAX)
		var yaw := _rng.randf_range(0.0, TAU)
		var ground_y := _get_terrain_height(plant_pos.x, plant_pos.z)

		var instance := scene.instantiate()
		instance.position = Vector3(plant_pos.x, ground_y, plant_pos.z)
		instance.rotate_y(yaw)
		instance.scale = Vector3.ONE * scale_factor
		obstacles_root.add_child(instance)


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
