class_name ArenaTerrain
extends RefCounted

## Rolling-hill terrain for the arena — a single static mesh+collision built
## once per match (the arena is bounded, not infinite/chunked, so this is
## nothing like a voxel engine's problem). `HeightMapShape3D` samples at a
## fixed 1 unit/vertex with no configurable cell size, so CELL_SIZE must
## stay 1.0 — the mesh is built from the exact same height array so visuals
## and collision can never disagree.
## 3x the original 50.0, by request ("map bigger, at least 3x") — grid
## resolution scales with this (see width/depth below), so this also means
## a 9x larger heightmap/mesh/navmesh bake (area scales with the square of
## a linear dimension) — timed directly after this change, see the doc
## comment on generate_arena() in Arena.gd for the actual measured cost.
const HALF_EXTENT := 150.0
const CELL_SIZE := 1.0

## Rolling hills restored by request, now that flat-ground-only building
## structures are disabled again (see Arena.STRUCTURE_COUNT_MIN/MAX) and
## the arena is going for a natural/nature-kit look instead — flat ground
## was only ever needed to give those structures a flat footprint.
## History: briefly set to 0.0 (flat) while the structure system was
## active; before that, first non-zero attempt used amplitude 2.5 with only
## a soft box-blur as the slope safety net — technically real elevation,
## but visually almost imperceptible (worst-case ~11°) at first-person eye
## height. Bumping amplitude to fix that pushed worst-case *single-cell*
## slope as high as ~40° on some seeds (a soft blur only reduces slopes on
## average, it doesn't bound the worst case) — too close to
## CharacterBody3D's ~45° floor_max_angle for comfort. Fixed properly with
## clamp_slopes() below, an explicit iterative relaxation that
## mathematically guarantees no adjacent grid cells ever exceed
## MAX_SLOPE_DEGREES regardless of amplitude, which is what actually lets
## amplitude go this high safely.
const NOISE_FREQUENCY := 0.025
const NOISE_AMPLITUDE := 12.0
const FRACTAL_OCTAVES := 3
const FRACTAL_GAIN := 0.4

## Smoothstep-falloff-to-flat near the map edge — originally so terrain met
## the (now-removed, see build_boundary_ridge() below) perimeter walls'
## flat base with no gap; kept as-is since it still serves a purpose: a
## clean, predictable (non-noisy) base for the boundary ridge to rise from,
## rather than a bumpy one.
const BORDER_FLATTEN_MARGIN := 4.0

## Cosmetic only (removes single-cell jaggies) — clamp_slopes() below is
## what actually guarantees climbability, not this.
const SLOPE_SMOOTH_PASSES := 1

## Comfortably under CharacterBody3D's ~45° default floor_max_angle, with
## real margin for knockback/jump timing/etc. to not tip something over the
## edge into "stuck."
const MAX_SLOPE_DEGREES := 28.0
const MAX_SLOPE_CLAMP_ITERATIONS := 25

## Replaces the old invisible perimeter walls: a deliberately steep, narrow
## ring of terrain right at the map edge that a player physically cannot
## climb, instead of an artificial collision box. Rising RIDGE_HEIGHT over
## just RIDGE_MARGIN horizontal units gives a slope of atan(20/4) ≈ 79° on
## average and steeper still at the steepest single cell (smoothstep's
## derivative peaks at its midpoint, giving a worst-case single-cell slope
## around 82° by the same napkin math already used to justify
## MAX_SLOPE_DEGREES's own worst-case bound) — both are far past
## CharacterBody3D's ~45° floor_max_angle, so move_and_slide() simply won't
## climb it. Must run *after* clamp_slopes(), never before or again
## afterward, or clamp_slopes()'s own guarantee (no adjacent cells differ by
## more than a climbable amount, *anywhere*) would immediately flatten this
## back down to something climbable.
const RIDGE_MARGIN := 4.0
const RIDGE_HEIGHT := 20.0

## Height-based vertex coloring, baked directly into the mesh rather than a
## texture. A texture-based approach (e.g. triplanar) was considered first,
## but standard triplanar's top-facing projection (the dominant one on this
## mostly-flat/rolling terrain, since normals point mostly straight up)
## samples using world X/Z, not height — a vertical gradient texture
## wouldn't actually read as height-based color on the terrain's primary
## visible surface. Vertex colors sidestep that entirely and need no UVs.
## Arena.gd just sets `StandardMaterial3D.vertex_color_use_as_albedo = true`.
const COLOR_LOW := Color(0.16, 0.14, 0.09)   # dark loam, low ground
const COLOR_MID := Color(0.32, 0.42, 0.18)   # mossy green, mid elevation
const COLOR_HIGH := Color(0.55, 0.53, 0.48)  # pale rock, peaks

## Fine-grained color speckling on top of the height gradient above — by
## request, the ground looked "a bit poor" (flat/plasticky) even with the
## height gradient in place. A *second*, much higher-frequency noise
## channel (sampled per-vertex, purely a function of world position, never
## touching the actual heights array) breaks up flat color bands into
## something that reads more like a real grass/dirt texture, without any
## new synced state — every peer computes byte-identical vertex colors from
## the same seed, exactly like the height noise already does, just a
## different noise instance/seed offset so the two don't visually correlate.
const DETAIL_NOISE_FREQUENCY := 0.15
const DETAIL_COLOR_JITTER := 0.12

var width: int
var depth: int
var heights: PackedFloat32Array
var _detail_noise: FastNoiseLite


func generate(rng_seed: int, spawn_positions: Array) -> void:
	width = int(HALF_EXTENT * 2.0 / CELL_SIZE) + 1
	depth = width
	heights = PackedFloat32Array()
	heights.resize(width * depth)

	# Different seed offset than the height noise below so the two don't
	# visually correlate (a speckle pattern that tracked hills 1:1 would
	# look like banding, not texture).
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = rng_seed + 1
	_detail_noise.noise_type = FastNoiseLite.NoiseType.TYPE_PERLIN
	_detail_noise.frequency = DETAIL_NOISE_FREQUENCY

	var noise := FastNoiseLite.new()
	noise.seed = rng_seed
	noise.noise_type = FastNoiseLite.NoiseType.TYPE_PERLIN
	noise.frequency = NOISE_FREQUENCY
	noise.fractal_octaves = FRACTAL_OCTAVES
	noise.fractal_gain = FRACTAL_GAIN

	for j in range(depth):
		for i in range(width):
			var x := _grid_to_world_x(i)
			var z := _grid_to_world_z(j)
			heights[_idx(i, j)] = noise.get_noise_2d(x, z) * NOISE_AMPLITUDE

	_flatten_border()
	# Spawn markers are static y=1 Node3Ds baked into the arena scene (not
	# dynamically placed via get_height()), so the ground under them must be
	# flattened to exactly 0 — not to "whatever height happened to already
	# be there", which is what a bare flatten_patch() targets (correct for
	# platforms, which do sample their own placement height, but wrong here).
	for sp in spawn_positions:
		flatten_patch(Vector2(sp.x, sp.z), 5.0, 0.0)

	for i in range(SLOPE_SMOOTH_PASSES):
		_smooth_pass()


## Called by Arena.gd right after generate() and before any obstacle is
## placed — obstacles read get_height() to position themselves, and the
## mesh/collision are built from these same final heights, so this has to
## run before anything else samples the heightmap, not after, or an
## obstacle could read a height that then shifts underneath it.
func clamp_slopes() -> void:
	var max_delta: float = tan(deg_to_rad(MAX_SLOPE_DEGREES)) * CELL_SIZE
	for iteration in range(MAX_SLOPE_CLAMP_ITERATIONS):
		var changed := false
		for j in range(depth):
			for i in range(width):
				var idx := _idx(i, j)
				if i + 1 < width:
					changed = _relax_pair(idx, _idx(i + 1, j), max_delta) or changed
				if j + 1 < depth:
					changed = _relax_pair(idx, _idx(i, j + 1), max_delta) or changed
		if not changed:
			break


func _relax_pair(idx_a: int, idx_b: int, max_delta: float) -> bool:
	var diff: float = heights[idx_b] - heights[idx_a]
	if absf(diff) <= max_delta:
		return false
	var excess: float = (absf(diff) - max_delta) * 0.5 * signf(diff)
	heights[idx_a] += excess
	heights[idx_b] -= excess
	return true


## Call after clamp_slopes(), and never call clamp_slopes() again
## afterward — see RIDGE_MARGIN/RIDGE_HEIGHT's doc comment for why order
## matters here. Adds height on top of whatever's already there (rather
## than setting it outright) so the ridge still visually follows the
## existing rolling terrain/vertex-color shape instead of becoming a
## harsh flat plateau — RIDGE_HEIGHT dominates the interior's own
## NOISE_AMPLITUDE regardless, so the result reads clearly as a boundary
## cliff either way.
func build_boundary_ridge() -> void:
	for j in range(depth):
		for i in range(width):
			var x := _grid_to_world_x(i)
			var z := _grid_to_world_z(j)
			var dist_to_edge: float = min(HALF_EXTENT - abs(x), HALF_EXTENT - abs(z))
			if dist_to_edge < RIDGE_MARGIN:
				var t: float = clamp(dist_to_edge / RIDGE_MARGIN, 0.0, 1.0)
				heights[_idx(i, j)] += RIDGE_HEIGHT * (1.0 - smoothstep(0.0, 1.0, t))


func _idx(i: int, j: int) -> int:
	return j * width + i


func _grid_to_world_x(i: int) -> float:
	return -HALF_EXTENT + i * CELL_SIZE


func _grid_to_world_z(j: int) -> float:
	return -HALF_EXTENT + j * CELL_SIZE


func _world_to_grid(x: float, z: float) -> Vector2:
	return Vector2((x + HALF_EXTENT) / CELL_SIZE, (z + HALF_EXTENT) / CELL_SIZE)


func _flatten_border() -> void:
	for j in range(depth):
		for i in range(width):
			var x := _grid_to_world_x(i)
			var z := _grid_to_world_z(j)
			var dist_to_edge: float = min(HALF_EXTENT - abs(x), HALF_EXTENT - abs(z))
			if dist_to_edge < BORDER_FLATTEN_MARGIN:
				var t: float = clamp(dist_to_edge / BORDER_FLATTEN_MARGIN, 0.0, 1.0)
				heights[_idx(i, j)] *= smoothstep(0.0, 1.0, t)


## Flattens an area of the already-generated heightmap, blended smoothly at
## the edges. If `target_height` is left at its default (NAN), the area
## flattens to whatever height already sits at `center` — correct for
## platforms, called again from Arena.gd for their footprints, since a
## platform samples that same point for its own placement height and this
## just keeps the ground around it consistent with that. Spawn points need
## an explicit target of 0.0 instead, since their markers are static y=1
## Node3Ds, not dynamically placed via get_height().
func flatten_patch(center: Vector2, radius: float, target_height: float = NAN) -> void:
	var center_grid := _world_to_grid(center.x, center.y)
	var ci := int(round(center_grid.x))
	var cj := int(round(center_grid.y))
	if ci < 0 or ci >= width or cj < 0 or cj >= depth:
		return
	var reference_height: float = target_height if not is_nan(target_height) else heights[_idx(ci, cj)]
	var grid_radius := int(ceil(radius / CELL_SIZE)) + 1
	for dj in range(-grid_radius, grid_radius + 1):
		for di in range(-grid_radius, grid_radius + 1):
			var i := ci + di
			var j := cj + dj
			if i < 0 or i >= width or j < 0 or j >= depth:
				continue
			var world_dist: float = Vector2(di, dj).length() * CELL_SIZE
			if world_dist > radius:
				continue
			var t: float = clamp(world_dist / radius, 0.0, 1.0)
			heights[_idx(i, j)] = lerp(reference_height, heights[_idx(i, j)], smoothstep(0.0, 1.0, t))


func _smooth_pass() -> void:
	var new_heights := heights.duplicate()
	for j in range(depth):
		for i in range(width):
			var sum := 0.0
			var count := 0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ni := i + di
					var nj := j + dj
					if ni < 0 or ni >= width or nj < 0 or nj >= depth:
						continue
					sum += heights[_idx(ni, nj)]
					count += 1
			new_heights[_idx(i, j)] = sum / count
	heights = new_heights


## Bilinear-sampled world height at an arbitrary (x, z) — used by Arena.gd's
## obstacle placement, which otherwise assumes flat y=0 ground.
func get_height(x: float, z: float) -> float:
	var g := _world_to_grid(x, z)
	var gi: float = clamp(g.x, 0.0, width - 1.0)
	var gj: float = clamp(g.y, 0.0, depth - 1.0)
	var i0 := int(floor(gi))
	var j0 := int(floor(gj))
	var i1: int = min(i0 + 1, width - 1)
	var j1: int = min(j0 + 1, depth - 1)
	var fx: float = gi - i0
	var fz: float = gj - j0
	var h00: float = heights[_idx(i0, j0)]
	var h10: float = heights[_idx(i1, j0)]
	var h01: float = heights[_idx(i0, j1)]
	var h11: float = heights[_idx(i1, j1)]
	var h0: float = lerp(h00, h10, fx)
	var h1: float = lerp(h01, h11, fx)
	return lerp(h0, h1, fz)


## Height fraction mapped through a 2-segment gradient (low->mid->high),
## then speckled with a small amount of position-based noise (see
## DETAIL_NOISE_FREQUENCY/DETAIL_COLOR_JITTER's doc comment) so flat-ish
## areas don't read as a single flat color band.
func _height_color(h: float, x: float, z: float) -> Color:
	var base: Color
	# NOISE_AMPLITUDE == 0 (flat ground) would divide by zero below — every
	# height is exactly 0 in that case anyway, so just use the mid color.
	if NOISE_AMPLITUDE <= 0.001:
		base = COLOR_MID
	else:
		var t: float = clamp((h + NOISE_AMPLITUDE) / (2.0 * NOISE_AMPLITUDE), 0.0, 1.0)
		base = COLOR_LOW.lerp(COLOR_MID, t / 0.5) if t < 0.5 else COLOR_MID.lerp(COLOR_HIGH, (t - 0.5) / 0.5)

	var jitter: float = _detail_noise.get_noise_2d(x, z) * DETAIL_COLOR_JITTER
	return Color(
		clamp(base.r + jitter, 0.0, 1.0),
		clamp(base.g + jitter, 0.0, 1.0),
		clamp(base.b + jitter, 0.0, 1.0),
	)


## Built from the exact same height array as build_collision_shape() — the
## single source of truth, so visuals and collision can never mismatch.
func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(depth - 1):
		for i in range(width - 1):
			var x0 := _grid_to_world_x(i)
			var z0 := _grid_to_world_z(j)
			var x1 := _grid_to_world_x(i + 1)
			var z1 := _grid_to_world_z(j + 1)
			var h00: float = heights[_idx(i, j)]
			var h10: float = heights[_idx(i + 1, j)]
			var h01: float = heights[_idx(i, j + 1)]
			var h11: float = heights[_idx(i + 1, j + 1)]
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x1, h10, z0)
			var p01 := Vector3(x0, h01, z1)
			var p11 := Vector3(x1, h11, z1)
			var c00 := _height_color(h00, x0, z0)
			var c10 := _height_color(h10, x1, z0)
			var c01 := _height_color(h01, x0, z1)
			var c11 := _height_color(h11, x1, z1)
			st.set_color(c00)
			st.add_vertex(p00)
			st.set_color(c10)
			st.add_vertex(p10)
			st.set_color(c01)
			st.add_vertex(p01)
			st.set_color(c10)
			st.add_vertex(p10)
			st.set_color(c11)
			st.add_vertex(p11)
			st.set_color(c01)
			st.add_vertex(p01)
	st.generate_normals()
	return st.commit()


func build_collision_shape() -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = heights
	return shape
