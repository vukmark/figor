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

## Reverted back to the original 40.0 alongside ArenaTerrain.HALF_EXTENT's
## own revert back to 50.0 — kept at the same 80% ratio as always.
const PLAY_HALF_EXTENT := 40.0
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

## Hand-placed floating-island cluster — first pass, player-only traversal
## (bots never path here, see _islands_root's doc comment). No boundary
## ridge exists anymore (removed by request — the whole perimeter is an
## open cliff edge now, see generate_arena()'s doc comment).
##
## Clusters are spread at randomized angles/offsets around the map instead
## of exactly 4 pairs on the cardinal axes (the old ISLAND_PAIR_DIRECTIONS)
## — that read as a rigid, obviously-generated cross once you could see the
## map from above/outside. ISLAND_CLUSTER_COUNT clusters start at evenly
## spaced base angles (so every side of the map still has somewhere
## reachable to jump to, not just N/E/S/W) then each gets an angular jitter
## — random placement, not full coverage guaranteed, but never a visible
## grid either.
const ISLAND_CLUSTER_COUNT := 6
const ISLAND_CLUSTER_ANGLE_JITTER_DEG := 25.0
## Near island: ~3m past the edge, top a few meters below ground level — a
## real jump-off-the-cliff drop down onto it, not a level hop (top sits at
## ISLAND_NEAR_Y + ISLAND_NEAR_HEIGHT/2 = -3.0, comfortably below the main
## terrain's y=0). Offset is randomized per cluster (within a range) rather
## than one fixed distance, for the same "not an obvious grid" reason as the
## angle jitter above — range is centered on the original hand-tuned +X
## pair's offset (running jump ≈8m per SPRINT_SPEED/JUMP_VELOCITY, unaffected
## by map size, so this stays a fixed range rather than scaling with
## HALF_EXTENT).
const ISLAND_NEAR_OFFSET_MIN := 8.0
const ISLAND_NEAR_OFFSET_MAX := 13.0
const ISLAND_NEAR_Y := -6.0
const ISLAND_NEAR_HEIGHT := 6.0
const ISLAND_NEAR_TOP_SIZE := Vector2(14.0, 12.0)
## Wider than the top (mountain-shaped taper, base bigger than summit) —
## deliberately never the other way around. A narrower *bottom* creates an
## overhang, and a player jumping up from underneath can wedge into the
## pocket under that overhang and get stuck (real bug, see git history) —
## tapering the safe direction keeps the "chunk of rock" look without that
## trap.
const ISLAND_NEAR_BOTTOM_SIZE := Vector2(18.0, 15.0)
## Far island: further out and lower still than the near one (top at
## ISLAND_FAR_Y + ISLAND_FAR_HEIGHT/2 = -7.0, a further 4m below the near
## island's top), reachable as a forward jump-and-drop from the near
## island's far edge, not directly from the main terrain — "another
## floating island visible below" from the edge. Offset randomized the same
## way as the near island's.
const ISLAND_FAR_OFFSET_MIN := 26.0
const ISLAND_FAR_OFFSET_MAX := 38.0
const ISLAND_FAR_Y := -12.0
const ISLAND_FAR_HEIGHT := 10.0
const ISLAND_FAR_TOP_SIZE := Vector2(16.0, 14.0)
const ISLAND_FAR_BOTTOM_SIZE := Vector2(20.0, 17.0)

## Ramp back up from the near island to the main map's edge — until now
## islands were one-way (jump down, no way back except a full respawn), by
## request. Same box-ramp primitive _build_ramp() already uses for
## structure platforms; a rise of ~3 (island top at y=-3) over a run of
## ISLAND_NEAR_OFFSET_MIN..MAX (8-13) is a gentle ~15-20° slope, comfortably
## walkable at a jog with no jump needed.
const ISLAND_RETURN_RAMP_WIDTH := 3.0

## Tint reused across every island for visual consistency with each other
## (distinct from ArenaTerrain's own vertex-color gradient, but in the same
## "bare rock" family) — see _structural_material() for how the tint
## combines with a noise texture.
const ISLAND_ROCK_TINT := Color(0.4, 0.37, 0.33, 1.0)

## Thin cap on every island's top face — by request, a bare-rock island top
## ("Selection_023.png") didn't read like the main terrain at all. No longer
## a fixed constant: ArenaTerrain now rolls one of several biome palettes
## per match (see ArenaTerrain.BIOME_PALETTES), so this reads
## `_terrain.color_mid` at generation time instead, keeping the islands
## visually consistent with whatever biome that seed actually rolled rather
## than always being mossy green. See _add_island_grass_cap() for why this
## is a separate plane rather than a top-face color change on the rock mesh
## itself.
const ISLAND_GRASS_CAP_OFFSET := 0.02

## Islands are irregular N-sided prisms, not rectangular frustums — random
## side count per island (see _island_ring_points()) plus per-vertex
## angle/radius jitter (ISLAND_RADIUS_JITTER) so the top/bottom silhouettes
## read as torn rock chunks instead of a perfect box or an obvious regular
## polygon. Each bottom-ring vertex reuses its corresponding top-ring
## vertex's angle jitter (see _island_ring_jitter()) rather than an
## independent random direction, plus its own depth variation (some "legs"
## hang lower than others), since the underside is visual-only — seen from
## below/the side but never walked on.
##
## That correlation matters for more than looks: an *independent* jitter
## direction at the bottom (tried first, back when islands were simple
## 4-corner frustums) could twist a side face into a non-planar "saddle" —
## the fixed-diagonal triangulation then triangulates it inconsistently, one
## triangle's winding effectively flipping, which rendered as a see-through
## hole from outside on a single-sided material (real bug, screenshot
## "transparent_island.png" — collision, a convex hull, had no such issue,
## so the player could stand in a spot that looked like open sky). Keeping
## top/bottom angle jitter correlated per vertex means a corner's vertical
## "pillar" stays a straight line — only Y varies along it — which keeps
## side faces planar-enough that this can't recur. _build_island() also
## disables backface culling on the rock material as a second, independent
## safety net against the same failure mode.
const ISLAND_SIDE_COUNT_MIN := 6
const ISLAND_SIDE_COUNT_MAX := 9
const ISLAND_RADIUS_JITTER := 0.22
const ISLAND_BOTTOM_Y_JITTER := 1.2

## Rock-face tonal variation baked as per-vertex color, multiplied into
## _structural_material's albedo (see its use_vertex_color param) so the
## rock body reads as weathered stone instead of one flat-shaded solid —
## clean rock tint on sunlit/noise-picked high spots, mossy-dark tint toward
## the underside and in noise-picked crevices.
const ISLAND_ROCK_CLEAN_TINT := Color(1.0, 1.0, 1.0)
const ISLAND_ROCK_MOSS_TINT := Color(0.55, 0.62, 0.48)
const ISLAND_ROCK_NOISE_FREQUENCY := 0.06

## Small plant clutter scattered right at (and slightly past) the top rim,
## spilling over the edge like moss/vines overhanging a real cliff — unlike
## _scatter_island_foliage's main pass, which insets everything away from
## the edge to keep the walkable footprint clear of clutter.
const ISLAND_RIM_CLUTTER_COUNT := 3
const ISLAND_RIM_OVERHANG := 0.6

## Cheap ("procedural primitives, not modeled assets" — no sci-fi kit exists
## in this project's Kenney assets, only nature/characters/weapons) first
## pass at "the main map is a landed/derelict mothership, the islands are
## the native planet's rock": metallic, part-emissive struts jutting out and
## down from the map's open cliff edge, walkable like the ramps/platforms
## elsewhere in this file. Visible from the islands below, same vantage
## _build_terrain_body()'s double-sided-material fix was needed for — the
## underside now actually has hull structure to look up at, not just a bare
## cliff. A later, more expensive pass could replace the flat metal/emission
## tint with a real hull-plating shader (panel seams, animated glow) on this
## same geometry — a material swap on these meshes, not a geometry rewrite.
const HULL_STRUT_COUNT := 8
const HULL_STRUT_ANGLE_JITTER_DEG := 12.0
const HULL_STRUT_LENGTH := 14.0
const HULL_STRUT_SIZE := Vector2(2.2, 1.4)
const HULL_STRUT_DROP := 6.0
const HULL_METAL_TINT := Color(0.32, 0.34, 0.37, 1.0)
const HULL_EMISSION_COLOR := Color(0.25, 0.85, 0.95, 1.0)
const HULL_EMISSION_ENERGY := 1.8

## Life-support set dressing on the main map itself — "a generation ship
## sustaining life across the galaxy," not just a bare hull. Greenhouse
## domes and coolant tanks are the first pair (solar arrays/comms mast are a
## separate follow-up); both go through the same _find_valid_position/
## _placed bookkeeping every other terrain obstacle uses, so they respect
## spawn distance and don't overlap crates/structures/trees/each other.
##
## The dome itself has no collision — a hollow shell that blocks bodies but
## not bullets/sightlines correctly needs real interior/exterior geometry,
## well past this pass's scope — it's decoration a player can walk through,
## same trade-off _scatter_island_rim_clutter's plants already accept.
## Godot's built-in SphereMesh(is_hemisphere) needs no modeled asset.
const GREENHOUSE_COUNT := 3
const GREENHOUSE_RADIUS := 7.0
const GREENHOUSE_GLASS_TINT := Color(0.55, 0.85, 0.8, 0.35)
const GREENHOUSE_PLANT_COUNT := 10

## Coolant/water tanks: solid metallic cylinders (CylinderMesh/
## CylinderShape3D, also no modeled asset needed) with an emissive gauge
## band reusing _hull_material() — unlike the greenhouse dome, these are
## real obstacles (collidable, cover), same footprint role as crates/rocks.
const TANK_COUNT := 4
const TANK_RADIUS := 1.6
const TANK_HEIGHT := 4.0
const TANK_METAL_TINT := Color(0.75, 0.76, 0.78, 1.0)
const TANK_GAUGE_COLOR := Color(0.3, 0.9, 0.5, 1.0)

## Solar panel arrays: small grids of tilted dark panels on short posts —
## the ship's power source, an obvious man-made grid pattern visible from a
## distance. Every panel in one array shares a yaw (see _place_solar_array())
## so the whole cluster reads as one installation facing one direction, not
## a scatter of random panels.
const SOLAR_ARRAY_COUNT := 3
const SOLAR_PANEL_ROWS := 2
const SOLAR_PANEL_COLS := 3
const SOLAR_PANEL_SIZE := Vector3(1.8, 0.08, 1.2)
const SOLAR_PANEL_SPACING := 2.2
const SOLAR_PANEL_TILT_DEG := 35.0
const SOLAR_POST_HEIGHT := 1.4
const SOLAR_PANEL_TINT := Color(0.08, 0.1, 0.18, 1.0)
const SOLAR_PANEL_GRIDLINE_COLOR := Color(0.3, 0.55, 0.95, 1.0)

## Comms mast: a tall thin strut with a shallow dish and a blinking beacon
## at the tip — "contact with the rest of the galaxy." Dish is visual-only
## (see _place_comms_mast()'s doc comment); beacon is an emissive mesh, not
## a real Light3D — not worth a realtime light per mast at this scale.
const COMMS_MAST_COUNT := 2
const COMMS_MAST_HEIGHT := 9.0
const COMMS_MAST_RADIUS := 0.25
const COMMS_DISH_RADIUS := 1.6
const COMMS_BEACON_COLOR := Color(0.95, 0.25, 0.25, 1.0)

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

## Reverted back to the original 5-8 alongside the map-size revert (was
## bumped ~4x when the map temporarily grew 9x in area) — density should
## match the original, smaller map again.
const TREE_CLUSTER_COUNT_MIN := 5
const TREE_CLUSTER_COUNT_MAX := 8
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

## Reverted back to the original 6-10 alongside the map-size revert, same
## rationale as TREE_CLUSTER_COUNT above.
const ROCK_COUNT_MIN := 6
const ROCK_COUNT_MAX := 10
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
## Scaled down ~4x alongside the map-size revert, same rationale as
## TREE_CLUSTER_COUNT/ROCK_COUNT above (was 100-140 at the bigger map size).
const PLANT_CLUSTER_COUNT_MIN := 25
const PLANT_CLUSTER_COUNT_MAX := 35
const PLANTS_PER_CLUSTER_MIN := 4
const PLANTS_PER_CLUSTER_MAX := 9
const PLANT_CLUSTER_RADIUS := 3.0
const PLANT_SCALE_MIN := 0.8
const PLANT_SCALE_MAX := 1.3

## Forest-floor detail props (stumps/logs) — cheap like rocks (one
## StaticBody3D each, no clustering), scaled at counts comparable to rocks.
## Scaled down ~4x alongside the map-size revert, same rationale as
## TREE_CLUSTER_COUNT/ROCK_COUNT above.
const STUMP_COUNT_MIN := 5
const STUMP_COUNT_MAX := 7
const STUMP_SCALE_MIN := 0.8
const STUMP_SCALE_MAX := 1.4
const LOG_COUNT_MIN := 4
const LOG_COUNT_MAX := 6
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

## Rolled once per match (see generate_arena()) and applied to every natural
## prop count below (trees/rocks/stumps/logs/plant clusters) — by request,
## alongside terrain amplitude and biome tint, so density varies seed to
## seed too, instead of every match landing in the same narrow COUNT_MIN..MAX
## band regardless of seed.
const PROP_DENSITY_MULT_MIN := 0.6
const PROP_DENSITY_MULT_MAX := 1.6

var _terrain: ArenaTerrain
var _rng := RandomNumberGenerator.new()
var _prop_density_mult: float = 1.0

## Deliberately a sibling of NavRegion, not a child of it (unlike
## obstacles_root/terrain_root) — NavRegion's navmesh bake parses everything
## under it via geometry_source_geometry_mode=ROOT_NODE_CHILDREN, and islands
## must stay off the navmesh entirely (player-only traversal for this first
## pass; bots have no way to jump across the gap anyway). Created lazily on
## first generate_arena() call since it has no pre-authored node in the
## .tscn, then reused/cleared on every subsequent regen the same way
## obstacles_root/terrain_root already are.
var _islands_root: Node3D


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
	# Separate RNG, offset +5 (distinct from ArenaTerrain's own +1/+2 offsets
	# of this same seed_value), purely for the density roll below — kept off
	# _rng itself so this doesn't reorder _rng's existing, already-verified
	# draw sequence for prop placement.
	var density_rng := RandomNumberGenerator.new()
	density_rng.seed = seed_value + 5
	_prop_density_mult = density_rng.randf_range(PROP_DENSITY_MULT_MIN, PROP_DENSITY_MULT_MAX)
	for child in obstacles_root.get_children():
		obstacles_root.remove_child(child)
		child.free()
	for child in terrain_root.get_children():
		terrain_root.remove_child(child)
		child.free()
	if _islands_root == null:
		_islands_root = Node3D.new()
		_islands_root.name = "Islands"
		add_child(_islands_root)
	else:
		for child in _islands_root.get_children():
			_islands_root.remove_child(child)
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
	# No boundary ridge call here by request: the whole perimeter is now an
	# open cliff edge, same as the island gap that used to be the one
	# deliberate exception carved into it (see ISLAND_GAP_CENTER_DEG's old
	# doc comment) — a player can walk off any edge of the map and either
	# find a floating island below or fall to a void death
	# (Constants.VOID_KILL_Y), instead of hitting an unclimbable wall.
	# build_boundary_ridge() itself is left intact in ArenaTerrain.gd in case
	# a contained/no-fall-off mode is wanted again later.
	# Obstacles sample/flatten the heightmap as they place themselves —
	# the mesh+collision are only built afterward, from the final
	# (obstacle-flattened) heights, so platforms sit flush instead of
	# clipping into or floating above sloped ground.
	_generate_obstacles()
	_build_terrain_body()

	# Fixed world-space geometry, independent of the terrain heightmap —
	# ordering relative to the terrain build above doesn't matter, kept
	# after it purely for readability (terrain finishes, then the floating
	# extras get added on top).
	_generate_islands()
	_build_mothership_hull()
	_build_cloud_layer()

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
	# build_mesh() only emits a top surface (a heightfield has no "underside"
	# geometry), so with the default single-sided culling the map is
	# genuinely invisible from any island positioned below/outside its edge
	# — exactly the vantage point every jump-off island creates (real bug,
	# screenshot "from_bellow_island.png": props on the map stayed visible,
	# since they're separate meshes, while the ground under them vanished).
	# Double-siding the material draws the backface too; it'll render dark
	# (lit from the "wrong" side of the normal), which reads as a
	# shadowed/craggy underside rather than a hole in the world.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)


## Obstacle placement can't assume flat y=0 ground now that the arena has
## real terrain — this is the shared entry point every placer samples.
func _get_terrain_height(x: float, z: float) -> float:
	return _terrain.get_height(x, z) if _terrain else 0.0


## Hand-placed, not procedural — ISLAND_CLUSTER_COUNT near/far island pairs
## at randomized angles/offsets around the map (see _build_island_pair()),
## plus one fixed background island far outside jumping range entirely —
## pure background set-dressing, matching the distant structures visible in
## the reference image that were never meant to be reached.
func _generate_islands() -> void:
	var base_step := 360.0 / ISLAND_CLUSTER_COUNT
	for i in range(ISLAND_CLUSTER_COUNT):
		var angle_deg: float = i * base_step + _rng.randf_range(-ISLAND_CLUSTER_ANGLE_JITTER_DEG, ISLAND_CLUSTER_ANGLE_JITTER_DEG)
		var direction := Vector3(cos(deg_to_rad(angle_deg)), 0.0, sin(deg_to_rad(angle_deg)))
		_build_island_pair(direction)

	var island3 := _build_island(
		Vector3(0.0, 20.0, -260.0), Vector2(30.0, 26.0), Vector2(36.0, 31.0), 14.0
	)
	_scatter_island_foliage(island3.top_center, island3.top_points, 4)
	_scatter_island_rim_clutter(island3.top_center, island3.top_points)


## Exact distance from the map's center to its square edge along an
## arbitrary (not necessarily axis-aligned) unit `direction` — a plain
## `HALF_EXTENT * direction` multiply (fine for the old axis-aligned-only
## directions) lands *inside* the square for a diagonal direction, since the
## square's edge is further away along a diagonal than along an axis.
## Chebyshev distance: the ray exits the square as soon as either axis
## coordinate reaches HALF_EXTENT, whichever comes first.
func _island_edge_distance(direction: Vector3) -> float:
	return ArenaTerrain.HALF_EXTENT / max(absf(direction.x), absf(direction.z))


## Builds one near+far island pair jumping-distance past the map edge in
## `direction` (now an arbitrary unit vector — see ISLAND_CLUSTER_COUNT's
## doc comment). Also builds a walkable ramp from the near island's edge
## back up to the map so islands aren't a one-way trip.
func _build_island_pair(direction: Vector3) -> void:
	var edge_dist := _island_edge_distance(direction)

	var near_offset := _rng.randf_range(ISLAND_NEAR_OFFSET_MIN, ISLAND_NEAR_OFFSET_MAX)
	var near_center := direction * (edge_dist + near_offset) + Vector3(0, ISLAND_NEAR_Y, 0)
	var near := _build_island(near_center, ISLAND_NEAR_TOP_SIZE, ISLAND_NEAR_BOTTOM_SIZE, ISLAND_NEAR_HEIGHT)
	_scatter_island_foliage(near.top_center, near.top_points, 3)
	_scatter_island_rim_clutter(near.top_center, near.top_points)
	_build_island_return_ramp(direction, edge_dist, near.top_center)

	var far_offset := _rng.randf_range(ISLAND_FAR_OFFSET_MIN, ISLAND_FAR_OFFSET_MAX)
	var far_center := direction * (edge_dist + far_offset) + Vector3(0, ISLAND_FAR_Y, 0)
	var far := _build_island(far_center, ISLAND_FAR_TOP_SIZE, ISLAND_FAR_BOTTOM_SIZE, ISLAND_FAR_HEIGHT)
	_scatter_island_foliage(far.top_center, far.top_points, 3)
	_scatter_island_rim_clutter(far.top_center, far.top_points)


## Walkable ramp from the near island's map-facing edge back up to the map
## boundary itself, so a player who jumped down isn't stuck relying on a
## respawn to get back. Parented under _islands_root (not obstacles_root),
## same as every other island piece — keeps it off the navmesh, consistent
## with islands staying player-only/unreachable-by-bots.
func _build_island_return_ramp(direction: Vector3, edge_dist: float, near_top_center: Vector3) -> void:
	var top_point := direction * edge_dist
	top_point.y = _get_terrain_height(top_point.x, top_point.z)
	var bottom_point := near_top_center - direction * (ISLAND_NEAR_TOP_SIZE.length() * 0.25)
	_build_ramp(top_point, bottom_point, _islands_root, ISLAND_RETURN_RAMP_WIDTH)


## Builds one floating island as an irregular N-sided prism (a chunk of rock
## torn out of the ground, not a clean box/frustum — see ISLAND_SIDE_COUNT_MIN
## doc comment) — a StaticBody3D with a ConvexPolygonShape3D collider sharing
## the exact same vertices as the visual mesh, since the shape is convex and
## doesn't need the HeightMapShape3D/mesh-parity dance ArenaTerrain uses for
## its much more irregular surface. `center` is the island's volumetric
## center, not its top. Returns a Dictionary {top_center, top_points} rather
## than a bare Vector3 — callers (foliage/rim scatter, the return ramp) need
## both the world-space top-surface center *and* the actual jittered top
## polygon, since it's no longer a simple rectangle they can re-derive from
## a Vector2 size.
##
## `bottom_size` must never be smaller than `top_size` — a narrower bottom
## creates an overhang, and a player jumping up from underneath could wedge
## into the pocket formed by that overhang's underside, getting stuck
## looking at the ceiling with no way out (real bug report, screenshot
## showed the player's camera stuck against the slanted underside). Every
## caller below tapers the safe direction instead — bottom wider than top,
## a mountain-shaped spire with no overhang — which is also why the two
## sizes stay independent params rather than collapsing to one Vector2.
func _build_island(center: Vector3, top_size: Vector2, bottom_size: Vector2, height: float) -> Dictionary:
	var side_count := _rng.randi_range(ISLAND_SIDE_COUNT_MIN, ISLAND_SIDE_COUNT_MAX)
	var ring_jitter := _island_ring_jitter(side_count)
	var h := height * 0.5
	var top_pts := _island_ring_points(top_size.x * 0.5, top_size.y * 0.5, side_count, ring_jitter, h)
	var bottom_pts := _island_ring_points(bottom_size.x * 0.5, bottom_size.y * 0.5, side_count, ring_jitter, -h)
	for i in range(side_count):
		bottom_pts[i].y -= _rng.randf_range(0.0, ISLAND_BOTTOM_Y_JITTER)

	var points: PackedVector3Array = PackedVector3Array()
	points.append_array(top_pts)
	points.append_array(bottom_pts)

	var body := StaticBody3D.new()
	_islands_root.add_child(body)
	body.global_transform.origin = center

	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_tapered_island_mesh(top_pts, bottom_pts, center, height)
	var rock_material := _structural_material(ISLAND_ROCK_TINT, true)
	# Safety net for ISLAND_SIDE_COUNT_MIN's "saddle" failure mode: even with
	# jitter now correlated to avoid it, a double-sided material means any
	# triangle whose winding still ends up flipped renders from the inside
	# instead of vanishing into a see-through hole.
	rock_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = rock_material
	body.add_child(mesh_instance)

	_add_island_grass_cap(body, top_pts, height)

	return {"top_center": center + Vector3(0.0, h, 0.0), "top_points": top_pts}


## A thin green cap sitting just above the rock body's own top face — a
## separate mesh (not a top-face color change on the rock mesh itself) so
## the rock body can stay one single untinted material shared by every
## face/every island, same as before. Fan-triangulated from `top_pts` (the
## island's own jittered top polygon) instead of a PlaneMesh rectangle, so
## the cap matches the now-irregular rock silhouette instead of being a
## rectangle sitting on top of a non-rectangular rock. Tiny Y offset
## (ISLAND_GRASS_CAP_OFFSET) avoids z-fighting against the rock mesh's own
## coplanar top face; visual only, no collision — the rock body's existing
## convex shape already covers the top surface.
func _add_island_grass_cap(body: StaticBody3D, top_pts: Array, height: float) -> void:
	var y := height * 0.5 + ISLAND_GRASS_CAP_OFFSET
	var center := Vector3(0.0, y, 0.0)
	var count: int = top_pts.size()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count):
		var a: Vector3 = top_pts[i]
		a.y = y
		var b: Vector3 = top_pts[(i + 1) % count]
		b.y = y
		st.add_vertex(center)
		st.add_vertex(a)
		st.add_vertex(b)
	st.generate_normals()

	var cap := MeshInstance3D.new()
	cap.mesh = st.commit()
	var cap_material := _structural_material(_terrain.color_mid)
	cap_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cap.material_override = cap_material
	body.add_child(cap)


## Per-vertex angle offset + radius scale for one ring of an island's
## silhouette, shared between that island's top and bottom rings (each
## scaled to its own top_size/bottom_size radii by _island_ring_points) so a
## corner's vertical "pillar" stays a straight line in XZ — see
## ISLAND_SIDE_COUNT_MIN's doc comment for why an independent random
## direction at the bottom isn't safe (it can twist a side face into a
## non-planar saddle and flip a triangle's winding).
func _island_ring_jitter(side_count: int) -> Array:
	var jitter := []
	for i in range(side_count):
		jitter.append({
			"angle": _rng.randf_range(-0.35, 0.35) * (TAU / side_count),
			"radius_scale": 1.0 + _rng.randf_range(-ISLAND_RADIUS_JITTER, ISLAND_RADIUS_JITTER),
		})
	return jitter


## One ring (top or bottom) of an island's irregular N-sided silhouette —
## an ellipse of radii (rx, rz) with each vertex's angle/radius perturbed by
## `jitter` (shared with the other ring, see _island_ring_jitter's doc
## comment). Points are generated in decreasing-angle order to match the
## winding the original 4-corner rectangle happened to use (proven to light
## correctly in earlier screenshots) — _build_tapered_island_mesh's fan/quad
## winding assumes this order.
func _island_ring_points(rx: float, rz: float, side_count: int, jitter: Array, y: float) -> Array:
	var pts: Array = []
	for i in range(side_count):
		var base_angle := -TAU * float(i) / float(side_count)
		var angle: float = base_angle + jitter[i]["angle"]
		var radius_scale: float = jitter[i]["radius_scale"]
		pts.append(Vector3(cos(angle) * rx * radius_scale, y, sin(angle) * rz * radius_scale))
	return pts


## `center`/`height` are only needed to sample _island_rock_color() per
## vertex (world position for the noise, local Y fraction for the
## top-clean/bottom-mossy bias) — they play no part in the geometry itself,
## which is still built entirely from `top_pts`/`bottom_pts`.
func _build_tapered_island_mesh(top_pts: Array, bottom_pts: Array, center: Vector3, height: float) -> ArrayMesh:
	var count: int = top_pts.size()
	var noise := FastNoiseLite.new()
	# Seeded from the island's own center so every island gets a different
	# noise pattern, but the same island is byte-identical across peers.
	noise.seed = int(center.x * 13.0 + center.z * 7.0 + center.y * 3.0)
	noise.frequency = ISLAND_ROCK_NOISE_FREQUENCY

	var top_c: Array[Color] = []
	var bottom_c: Array[Color] = []
	for i in range(count):
		top_c.append(_island_rock_color(top_pts[i], center, height, noise))
		bottom_c.append(_island_rock_color(bottom_pts[i], center, height, noise))

	var top_center := Vector3(0.0, height * 0.5, 0.0)
	var bottom_center := Vector3(0.0, -height * 0.5, 0.0)
	var top_center_color := _island_rock_color(top_center, center, height, noise)
	var bottom_center_color := _island_rock_color(bottom_center, center, height, noise)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count):
		var j := (i + 1) % count
		# Top face: fan out from the center, same winding direction the ring
		# points are already in. Bottom face: the reverse traversal order
		# flips the winding so its normal faces down instead of up, same
		# trick the old fixed-quad version used (see git history).
		_add_tri(st, top_center, top_pts[i], top_pts[j], top_center_color, top_c[i], top_c[j])
		_add_tri(st, bottom_center, bottom_pts[j], bottom_pts[i], bottom_center_color, bottom_c[j], bottom_c[i])
		# Side quad between ring index i and i+1.
		_add_quad(st, top_pts[i], top_pts[j], bottom_pts[j], bottom_pts[i], top_c[i], top_c[j], bottom_c[j], bottom_c[i])
	st.generate_normals()
	return st.commit()


## Moss-dark patches near the underside/in noise-picked crevices, clean rock
## tint elsewhere — see ISLAND_ROCK_MOSS_TINT's doc comment. `local` is a
## point relative to the island's own center (one of _island_ring_points'
## per-ring vertices, or a top/bottom center point for the fan-triangulated
## faces); `center + local` gives noise a stable world position so two
## islands never read as the same texture repeated.
func _island_rock_color(local: Vector3, center: Vector3, height: float, noise: FastNoiseLite) -> Color:
	var world := center + local
	var noise_t: float = clamp((noise.get_noise_3d(world.x, world.y, world.z) + 1.0) * 0.5, 0.0, 1.0)
	var depth_t: float = clamp(-local.y / height + 0.5, 0.0, 1.0)
	var moss_t: float = clamp(noise_t * 0.6 + depth_t * 0.5, 0.0, 1.0)
	return ISLAND_ROCK_CLEAN_TINT.lerp(ISLAND_ROCK_MOSS_TINT, moss_t)


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color = Color.WHITE, cb: Color = Color.WHITE, cc: Color = Color.WHITE) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color = Color.WHITE, cb: Color = Color.WHITE, cc: Color = Color.WHITE, cd: Color = Color.WHITE) -> void:
	_add_tri(st, a, b, c, ca, cb, cc)
	_add_tri(st, a, c, d, ca, cc, cd)


## Picks a random point inside an island's top polygon by walking partway
## from the center toward a random vertex — always inside the polygon since
## _island_ring_points always builds a star-shaped ring around its own
## center (every point is directly visible from the center), regardless of
## how irregular the jitter made the silhouette. `margin_t` (0..1) keeps the
## far end short of the actual edge, mirroring the old rectangle version's
## fixed-distance margin.
func _random_point_in_island_top(top_points: Array, max_t: float) -> Vector3:
	var vertex: Vector3 = top_points[_rng.randi() % top_points.size()]
	return vertex * _rng.randf_range(0.0, max_t)


## Scatters a couple of trees/rocks across an island's top footprint — same
## look as _place_tree_cluster()/_place_rock() but sampling a fixed island
## top height instead of _get_terrain_height(), since islands aren't part
## of the terrain heightmap. Deliberately skips _placed/overlap bookkeeping
## (that system exists to keep terrain obstacles from overlapping each
## other across the whole arena; islands are small, isolated, hand-placed
## footprints with nothing else competing for the space).
func _scatter_island_foliage(top_center: Vector3, top_points: Array, prop_count: int) -> void:
	for i in range(prop_count):
		var local := _random_point_in_island_top(top_points, 0.75)
		var pos := top_center + Vector3(local.x, 0.0, local.z)
		var yaw := _rng.randf_range(0.0, TAU)

		var use_rock := _rng.randf() < 0.3
		var scene: PackedScene = ROCK_SCENES[_rng.randi() % ROCK_SCENES.size()] if use_rock else TREE_SCENES[_rng.randi() % TREE_SCENES.size()]

		var body := StaticBody3D.new()
		_islands_root.add_child(body)
		body.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = TREE_TRUNK_SIZE if not use_rock else ROCK_COLLISION_SIZES[0]
		collision.shape = shape
		body.add_child(collision)

		body.add_child(scene.instantiate())


## Small plant clutter right at (and slightly past) the top rim — see
## ISLAND_RIM_CLUTTER_COUNT's doc comment for why this is a separate pass
## from _scatter_island_foliage rather than just widening that one's
## placement range. Picks a random point along a random edge of the actual
## jittered top polygon (rather than the old 4-side rectangle switch) and
## pushes it outward along that point's own radial direction, so it spills
## past whichever edge it landed on regardless of the polygon's shape. No
## collision (same as _place_plant_cluster's ground plants), added straight
## to _islands_root at world position, exactly like _scatter_island_foliage's
## props.
func _scatter_island_rim_clutter(top_center: Vector3, top_points: Array) -> void:
	var count: int = top_points.size()
	for i in range(ISLAND_RIM_CLUTTER_COUNT):
		var idx := _rng.randi() % count
		var a: Vector3 = top_points[idx]
		var b: Vector3 = top_points[(idx + 1) % count]
		var edge_point: Vector3 = a.lerp(b, _rng.randf_range(0.0, 1.0))
		var radial := Vector2(edge_point.x, edge_point.z).normalized()
		var local := edge_point + Vector3(radial.x, 0.0, radial.y) * ISLAND_RIM_OVERHANG

		var scene: PackedScene = PLANT_SCENES[_rng.randi() % PLANT_SCENES.size()]
		var instance := scene.instantiate()
		_islands_root.add_child(instance)
		instance.position = top_center + Vector3(local.x, -0.3, local.z)
		instance.rotate_y(_rng.randf_range(0.0, TAU))
		instance.scale = Vector3.ONE * _rng.randf_range(0.8, 1.3)


## Real parallax depth (not just the sky dome, which renders at infinite
## distance and can't provide any) — several big flat planes at different
## heights/scales/speeds/tints, each using CLOUD_LAYER_SHADER to drift its
## own per-pixel cloud noise via the TIME uniform, so unlike the old static
## per-vertex-color version these actually move, and nearer/farther layers
## visibly shift against each other as the player moves. No collision;
## purely decorative, all sitting well below the islands.
const CLOUD_LAYER_SHADER := preload("res://assets/shaders/cloud_layer.gdshader")

## One entry per drifting layer: y (height), extent (plane half-size),
## noise_scale (bigger = smaller/more numerous puffs — kept low here for
## big, dense, reference-image-sized cloud masses), coverage, opacity,
## wind_speed (world units/sec, slow — real clouds drift, they don't race),
## tint, shadow_tint. Nearer/lower layers are whiter/faster; farther/lower
## layers are hazier/bluer/slower, for a simple atmospheric-perspective cue
## (matches ArenaTerrain/sky's own "cheap approximation over true
## volumetrics" tradeoff).
const CLOUD_LAYERS := [
	{
		"y": -15.0, "extent": 180.0, "noise_scale": 0.0055, "coverage": 0.7,
		"opacity": 0.7, "wind_speed": Vector2(1.5, 0.8),
		"tint": Color(1.0, 1.0, 0.98), "shadow_tint": Color(0.78, 0.76, 0.8),
	},
	{
		"y": -40.0, "extent": 260.0, "noise_scale": 0.004, "coverage": 0.62,
		"opacity": 0.55, "wind_speed": Vector2(1.0, 0.5),
		"tint": Color(0.92, 0.93, 0.98), "shadow_tint": Color(0.68, 0.7, 0.78),
	},
	{
		"y": -80.0, "extent": 340.0, "noise_scale": 0.0028, "coverage": 0.55,
		"opacity": 0.4, "wind_speed": Vector2(0.6, 0.3),
		"tint": Color(0.78, 0.82, 0.92), "shadow_tint": Color(0.6, 0.65, 0.78),
	},
]

func _build_cloud_layer() -> void:
	for layer in CLOUD_LAYERS:
		var extent: float = layer["extent"]
		var mat := ShaderMaterial.new()
		mat.shader = CLOUD_LAYER_SHADER
		mat.set_shader_parameter("noise_scale", layer["noise_scale"])
		mat.set_shader_parameter("coverage", layer["coverage"])
		mat.set_shader_parameter("opacity", layer["opacity"])
		mat.set_shader_parameter("wind_speed", layer["wind_speed"])
		mat.set_shader_parameter("cloud_tint", layer["tint"])
		mat.set_shader_parameter("shadow_tint", layer["shadow_tint"])
		mat.set_shader_parameter("fade_start", extent * 0.6)
		mat.set_shader_parameter("fade_end", extent)

		var plane := PlaneMesh.new()
		plane.size = Vector2(extent, extent) * 2.0
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = plane
		mesh_instance.position = Vector3(0.0, layer["y"], 0.0)
		mesh_instance.material_override = mat
		_islands_root.add_child(mesh_instance)


## Randomized each run so every match gets a different layout — the floor,
## walls, and spawn points stay fixed as the play-area boundary, but cover
## placement changes. Navmesh baking happens at runtime (see _ready), after
## these are placed, so it always reflects the layout that was just rolled.
## Rolls a count in [min_count, max_count] via _rng (same draw as before —
## _prop_density_mult is applied on top, not folded into the range itself,
## so this doesn't change _rng's draw sequence/count) then scales it by the
## match's rolled _prop_density_mult. Only used for natural/foliage props —
## see PROP_DENSITY_MULT_MIN/MAX's doc comment.
func _scaled_count(min_count: int, max_count: int) -> int:
	var base_count := _rng.randi_range(min_count, max_count)
	return maxi(0, roundi(base_count * _prop_density_mult))


func _generate_obstacles() -> void:
	# Structures placed first, before platforms — they're the most
	# position-constrained (largest footprints) and the main visual
	# anchors, so they get first pick of open ground, same rationale
	# platforms already got before structures existed.
	var structure_count := _rng.randi_range(STRUCTURE_COUNT_MIN, STRUCTURE_COUNT_MAX)
	for i in range(structure_count):
		_place_structure()

	# Tree clusters next, ahead of the life-support props below — their
	# footprint (TREE_CLUSTER_RADIUS*2.2 ≈ 24x24) is the single largest of
	# anything _generate_obstacles places, bigger even than a greenhouse
	# dome's. _clears_obstacles' exclusion zone around every already-placed
	# object scales with the *candidate's own* size, so if the smaller
	# life-support props claimed space first, each one — even a small
	# tank — would carve out a huge no-go zone once a tree cluster tried to
	# fit around it, and collectively that was enough to saturate the whole
	# map (real bug: all 8 tree clusters failed to place, every single one,
	# confirmed via temporary instrumentation — trees only reappeared once
	# this loop moved back ahead of the props).
	var tree_cluster_count := _scaled_count(TREE_CLUSTER_COUNT_MIN, TREE_CLUSTER_COUNT_MAX)
	for i in range(tree_cluster_count):
		_place_tree_cluster()

	# Life-support set dressing — same "most position-constrained gets first
	# pick of open ground" priority as structures, see GREENHOUSE_COUNT's doc
	# comment. Ordered by footprint size, largest first, for the same reason
	# tree clusters now come before all of them.
	for i in range(GREENHOUSE_COUNT):
		_place_greenhouse()

	for i in range(SOLAR_ARRAY_COUNT):
		_place_solar_array()

	for i in range(TANK_COUNT):
		_place_tank()

	for i in range(COMMS_MAST_COUNT):
		_place_comms_mast()

	var platform_count := _rng.randi_range(PLATFORM_COUNT_MIN, PLATFORM_COUNT_MAX)
	for i in range(platform_count):
		_place_platform()

	var crate_count := _rng.randi_range(CRATE_COUNT_MIN, CRATE_COUNT_MAX)
	for i in range(crate_count):
		_place_box_obstacle(CRATE_SCENE, CRATE_SIZE, CRATE_HEIGHT_OFFSET)

	var column_count := _rng.randi_range(COLUMN_COUNT_MIN, COLUMN_COUNT_MAX)
	for i in range(column_count):
		_place_box_obstacle(COLUMN_SCENE, COLUMN_SIZE, COLUMN_HEIGHT_OFFSET)

	# Remaining foliage last — the least gameplay-constrained layer (smallest
	# footprints, or for plant clusters no obstacle-overlap check at all —
	# see _place_plant_cluster), so it fills whatever open ground remains
	# instead of competing with anything above for the best clearings.
	var rock_count := _scaled_count(ROCK_COUNT_MIN, ROCK_COUNT_MAX)
	for i in range(rock_count):
		_place_rock()

	var stump_count := _scaled_count(STUMP_COUNT_MIN, STUMP_COUNT_MAX)
	for i in range(stump_count):
		_place_stump()

	var log_count := _scaled_count(LOG_COUNT_MIN, LOG_COUNT_MAX)
	for i in range(log_count):
		_place_log()

	var plant_cluster_count := _scaled_count(PLANT_CLUSTER_COUNT_MIN, PLANT_CLUSTER_COUNT_MAX)
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
## `use_vertex_color` multiplies the mesh's own per-vertex color into the
## final albedo alongside `tint`/the noise texture — off by default so
## existing callers whose meshes never set vertex colors (StandardMaterial3D
## just treats that as opaque white, a no-op) see no change; islands are the
## only caller that turns it on, since _build_tapered_island_mesh is the
## only mesh builder that bakes per-vertex color at all.
func _structural_material(tint: Color, use_vertex_color: bool = false) -> StandardMaterial3D:
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
	mat.vertex_color_use_as_albedo = use_vertex_color
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


## `parent`/`width` default to the original structure-platform-ramp behavior
## (obstacles_root, RAMP_WIDTH) — _build_island_return_ramp() is the only
## caller that overrides them, to keep its ramp off the navmesh like every
## other island piece.
func _build_ramp(top_point: Vector3, bottom_point: Vector3, parent: Node3D = null, width: float = RAMP_WIDTH) -> void:
	var diff := bottom_point - top_point
	var slope_length := diff.length()
	if slope_length < 0.01:
		return
	var mid := (top_point + bottom_point) * 0.5

	var body := StaticBody3D.new()
	(parent if parent else obstacles_root).add_child(body)
	body.global_transform = Transform3D(_basis_looking(diff), mid)

	var ramp_size := Vector3(width, RAMP_THICKNESS, slope_length)
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


## See HULL_STRUT_COUNT's doc comment for the overall "main map as
## mothership hull" idea. Struts are spread evenly around the map's
## perimeter (with a little angle jitter so they don't read as a perfectly
## regular ring) using the same _island_edge_distance() the islands use, so
## they anchor right at the map's actual edge regardless of direction.
func _build_mothership_hull() -> void:
	var base_step := 360.0 / HULL_STRUT_COUNT
	for i in range(HULL_STRUT_COUNT):
		var angle_deg: float = i * base_step + _rng.randf_range(-HULL_STRUT_ANGLE_JITTER_DEG, HULL_STRUT_ANGLE_JITTER_DEG)
		var direction := Vector3(cos(deg_to_rad(angle_deg)), 0.0, sin(deg_to_rad(angle_deg)))
		_build_hull_strut(direction)


## One strut: a metallic box jutting outward and downward from the map's
## cliff edge in `direction`, plus a thin emissive "running light" stripe
## along its top. Parented under _islands_root (off navmesh, same as every
## other piece hanging off the map's edge in open air) but does have real
## collision — unlike islands' rock, this is meant to double as a walkable
## catwalk, not just scenery.
func _build_hull_strut(direction: Vector3) -> void:
	var edge_dist := _island_edge_distance(direction)
	var base_point := direction * (edge_dist - 2.0) + Vector3(0.0, -1.0, 0.0)
	var tip_point := direction * (edge_dist + HULL_STRUT_LENGTH) + Vector3(0.0, -1.0 - HULL_STRUT_DROP, 0.0)
	var diff := tip_point - base_point
	var length := diff.length()
	if length < 0.01:
		return
	var mid := (base_point + tip_point) * 0.5

	var body := StaticBody3D.new()
	_islands_root.add_child(body)
	body.global_transform = Transform3D(_basis_looking(diff), mid)

	var strut_size := Vector3(HULL_STRUT_SIZE.x, HULL_STRUT_SIZE.y, length)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = strut_size
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = strut_size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _hull_material(HULL_METAL_TINT)
	body.add_child(mesh_instance)

	# Thin emissive stripe along the top face, like a running-light seam — a
	# second, slightly-inset box rather than a UV-mapped texture (no such
	# asset exists, and a flat emissive tint reads fine at this scale).
	var stripe_size := Vector3(HULL_STRUT_SIZE.x * 0.15, HULL_STRUT_SIZE.y * 0.15, length * 0.9)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = stripe_size
	stripe.mesh = stripe_mesh
	stripe.position = Vector3(0.0, HULL_STRUT_SIZE.y * 0.5, 0.0)
	stripe.material_override = _hull_material(HULL_EMISSION_COLOR, true)
	body.add_child(stripe)


## Metallic hull-plating material — `emissive` swaps in a bright, unlit-ish
## glow (used for the strut's running-light stripe) instead of the usual
## metallic/rough surface.
func _hull_material(tint: Color, emissive: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	if emissive:
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = HULL_EMISSION_ENERGY
	else:
		mat.metallic = 0.75
		mat.roughness = 0.35
	return mat


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


## Greenhouse dome — see GREENHOUSE_COUNT's doc comment for why the shell
## has no collision. Plants scattered inside reuse _place_plant_cluster's
## disk-sampling (area-uniform via sqrt(rand)) and its "no collision, purely
## decorative" trade-off, just at the dome's ground footprint instead of out
## in the open.
func _place_greenhouse() -> void:
	var footprint := Vector3(GREENHOUSE_RADIUS, 0, GREENHOUSE_RADIUS) * 2.2
	var center := _find_valid_position(footprint)
	if not is_finite(center.x):
		return
	var ground_y := _get_terrain_height(center.x, center.z)

	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = GREENHOUSE_RADIUS
	sphere.height = GREENHOUSE_RADIUS
	sphere.is_hemisphere = true
	dome.mesh = sphere
	dome.position = Vector3(center.x, ground_y, center.z)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = GREENHOUSE_GLASS_TINT
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	# Double-sided: with no collision a player can walk inside the dome, and
	# should still see glass looking up/out from there, not a backface-
	# culled hole (same reasoning as the island rock material's cull fix).
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material_override = glass
	obstacles_root.add_child(dome)

	for i in range(GREENHOUSE_PLANT_COUNT):
		var angle := _rng.randf_range(0.0, TAU)
		var radius := (GREENHOUSE_RADIUS - 1.0) * sqrt(_rng.randf())
		var plant_pos := center + Vector3(cos(angle), 0, sin(angle)) * radius

		var scene: PackedScene = PLANT_SCENES[_rng.randi() % PLANT_SCENES.size()]
		var scale_factor := _rng.randf_range(PLANT_SCALE_MIN, PLANT_SCALE_MAX)
		var yaw := _rng.randf_range(0.0, TAU)

		var instance := scene.instantiate()
		instance.position = Vector3(plant_pos.x, ground_y, plant_pos.z)
		instance.rotate_y(yaw)
		instance.scale = Vector3.ONE * scale_factor
		obstacles_root.add_child(instance)

	_placed.append({"position": Vector3(center.x, 0, center.z), "size": footprint})


## Coolant/water tank — see TANK_COUNT's doc comment. Reuses _hull_material()
## for both the tank body (metallic) and its gauge band (emissive), same
## helper the mothership hull struts use.
func _place_tank() -> void:
	var footprint := Vector3(TANK_RADIUS, 0, TANK_RADIUS) * 2.8
	var pos := _find_valid_position(footprint)
	if not is_finite(pos.x):
		return
	var ground_y := _get_terrain_height(pos.x, pos.z)

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	body.global_transform.origin = Vector3(pos.x, ground_y + TANK_HEIGHT * 0.5, pos.z)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = TANK_RADIUS
	shape.height = TANK_HEIGHT
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = TANK_RADIUS
	cylinder.bottom_radius = TANK_RADIUS
	cylinder.height = TANK_HEIGHT
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = _hull_material(TANK_METAL_TINT)
	body.add_child(mesh_instance)

	# Emissive gauge band — a slightly wider, very short cylinder wrapped
	# around the tank's mid-height, same "second inset mesh" trick as the
	# hull strut's running-light stripe.
	var gauge := MeshInstance3D.new()
	var gauge_mesh := CylinderMesh.new()
	gauge_mesh.top_radius = TANK_RADIUS * 1.03
	gauge_mesh.bottom_radius = TANK_RADIUS * 1.03
	gauge_mesh.height = TANK_HEIGHT * 0.12
	gauge.mesh = gauge_mesh
	gauge.material_override = _hull_material(TANK_GAUGE_COLOR, true)
	body.add_child(gauge)

	_placed.append({"position": Vector3(pos.x, 0, pos.z), "size": footprint})


## A grid of tilted solar panels sharing one yaw, so the whole cluster reads
## as one installation. Only the array's own footprint goes through
## _find_valid_position/_placed — individual panels within it are trusted
## not to collide with anything else the way a tree cluster's individual
## trees are.
func _place_solar_array() -> void:
	var array_w := (SOLAR_PANEL_COLS - 1) * SOLAR_PANEL_SPACING + SOLAR_PANEL_SIZE.x
	var array_d := (SOLAR_PANEL_ROWS - 1) * SOLAR_PANEL_SPACING + SOLAR_PANEL_SIZE.z
	var footprint := Vector3(array_w, 0, array_d) * 1.3
	var center := _find_valid_position(footprint)
	if not is_finite(center.x):
		return
	var ground_y := _get_terrain_height(center.x, center.z)
	var yaw := _rng.randf_range(0.0, TAU)
	var yaw_basis := Basis(Vector3.UP, yaw)

	for row in range(SOLAR_PANEL_ROWS):
		for col in range(SOLAR_PANEL_COLS):
			var local := Vector3(
				(col - (SOLAR_PANEL_COLS - 1) * 0.5) * SOLAR_PANEL_SPACING,
				0.0,
				(row - (SOLAR_PANEL_ROWS - 1) * 0.5) * SOLAR_PANEL_SPACING
			)
			var world := center + yaw_basis * local
			_place_solar_panel(Vector3(world.x, ground_y, world.z), yaw)

	_placed.append({"position": Vector3(center.x, 0, center.z), "size": footprint})


## One panel: a post (vertical, untilted, in the body's own local space) and
## a panel+gridline (tilted around local X, sitting atop the post) — the
## whole body itself just carries `yaw`, so every child's local transform
## stays simple regardless of which direction the array faces.
func _place_solar_panel(base_pos: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), base_pos)

	var post_offset := Vector3(0.0, SOLAR_POST_HEIGHT * 0.5, 0.0)
	var post_size := Vector3(0.2, SOLAR_POST_HEIGHT, 0.2)
	var post_collision := CollisionShape3D.new()
	var post_shape := BoxShape3D.new()
	post_shape.size = post_size
	post_collision.shape = post_shape
	post_collision.position = post_offset
	body.add_child(post_collision)

	var post_mesh := MeshInstance3D.new()
	var post_box := BoxMesh.new()
	post_box.size = post_size
	post_mesh.mesh = post_box
	post_mesh.position = post_offset
	post_mesh.material_override = _hull_material(HULL_METAL_TINT)
	body.add_child(post_mesh)

	var panel_transform := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-SOLAR_PANEL_TILT_DEG)), Vector3(0.0, SOLAR_POST_HEIGHT, 0.0))

	var panel_collision := CollisionShape3D.new()
	var panel_shape := BoxShape3D.new()
	panel_shape.size = SOLAR_PANEL_SIZE
	panel_collision.shape = panel_shape
	panel_collision.transform = panel_transform
	body.add_child(panel_collision)

	var panel_mesh := MeshInstance3D.new()
	var panel_box := BoxMesh.new()
	panel_box.size = SOLAR_PANEL_SIZE
	panel_mesh.mesh = panel_box
	panel_mesh.transform = panel_transform
	panel_mesh.material_override = _hull_material(SOLAR_PANEL_TINT)
	body.add_child(panel_mesh)

	# Thin emissive grid line down the panel's center — cheap stand-in for
	# cell seams, same "second inset mesh" trick as the tank's gauge band.
	var grid_mesh := MeshInstance3D.new()
	var grid_box := BoxMesh.new()
	grid_box.size = Vector3(SOLAR_PANEL_SIZE.x * 0.94, SOLAR_PANEL_SIZE.y * 0.4, SOLAR_PANEL_SIZE.z * 0.06)
	grid_mesh.mesh = grid_box
	grid_mesh.transform = panel_transform
	grid_mesh.material_override = _hull_material(SOLAR_PANEL_GRIDLINE_COLOR, true)
	body.add_child(grid_mesh)


## Comms mast: a tall thin strut, a shallow dish partway up, and a blinking
## beacon at the tip. The dish has no collision — it's a thin slanted disc,
## and colliding with just its surface would feel like an invisible wall
## around empty air at every other angle; the mast itself is the real
## obstacle.
func _place_comms_mast() -> void:
	var footprint := Vector3(COMMS_DISH_RADIUS, 0, COMMS_DISH_RADIUS) * 2.5
	var pos := _find_valid_position(footprint)
	if not is_finite(pos.x):
		return
	var ground_y := _get_terrain_height(pos.x, pos.z)

	var body := StaticBody3D.new()
	obstacles_root.add_child(body)
	body.global_transform.origin = Vector3(pos.x, ground_y, pos.z)

	var mast_offset := Vector3(0.0, COMMS_MAST_HEIGHT * 0.5, 0.0)
	var mast_collision := CollisionShape3D.new()
	var mast_shape := CylinderShape3D.new()
	mast_shape.radius = COMMS_MAST_RADIUS
	mast_shape.height = COMMS_MAST_HEIGHT
	mast_collision.shape = mast_shape
	mast_collision.position = mast_offset
	body.add_child(mast_collision)

	var mast_mesh := MeshInstance3D.new()
	var mast_cyl := CylinderMesh.new()
	mast_cyl.top_radius = COMMS_MAST_RADIUS
	mast_cyl.bottom_radius = COMMS_MAST_RADIUS * 1.4
	mast_cyl.height = COMMS_MAST_HEIGHT
	mast_mesh.mesh = mast_cyl
	mast_mesh.position = mast_offset
	mast_mesh.material_override = _hull_material(HULL_METAL_TINT)
	body.add_child(mast_mesh)

	var dish := MeshInstance3D.new()
	var dish_mesh := SphereMesh.new()
	dish_mesh.radius = COMMS_DISH_RADIUS
	dish_mesh.height = COMMS_DISH_RADIUS * 0.6
	dish_mesh.is_hemisphere = true
	dish.mesh = dish_mesh
	dish.scale = Vector3(1.0, 0.35, 1.0)
	dish.position = Vector3(0.0, COMMS_MAST_HEIGHT * 0.85, 0.0)
	dish.rotation = Vector3(deg_to_rad(60.0), 0.0, 0.0)
	dish.material_override = _hull_material(HULL_METAL_TINT)
	body.add_child(dish)

	# Blinking beacon at the very tip — cheap stand-in for an aircraft
	# warning light.
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.2
	beacon_mesh.height = 0.4
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(0.0, COMMS_MAST_HEIGHT, 0.0)
	beacon.material_override = _hull_material(COMMS_BEACON_COLOR, true)
	body.add_child(beacon)

	_placed.append({"position": Vector3(pos.x, 0, pos.z), "size": footprint})


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
