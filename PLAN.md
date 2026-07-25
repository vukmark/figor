# Figor — Project Plan & Status

Living document. Update this as we go — it tracks what's done, what's in
progress, and what's next.

Note: `/home/marko/.claude/plans/logical-bubbling-flute.md` is Claude Code's
plan-mode scratch file — it gets *overwritten* every time a new `/plan`
session runs, so it only ever holds whatever was drafted most recently, not
a history. Anything worth keeping long-term belongs here instead.

## Concept

Third-person(-turned-first-person) shooter. Core twist: your head grows the
longer you survive; the bigger it is when you die, the bigger the explosion
you leave behind (damage + knockback, scaled by head size), which can chain
into other players. Die → respawn with a normal head, timer resets.

## Stages

- **Stage 1 (current)** — bots-only gameplay, single local host, no real
  network peers yet.
- **Stage 2 (not started)** — local multiplayer (same machine, split-screen
  or hotseat).
- **Stage 3 (not started)** — real networked multiplayer.

Architecture is already built multiplayer-ready (server-authoritative
movement, `MultiplayerSynchronizer`/`MultiplayerSpawner`, RPC-shaped hooks)
so Stage 2/3 should mostly be additive — see the original plan doc for the
reasoning.

## Done so far

**Core loop**
- Player movement, first-person camera (see note below — started 3rd
  person, switched to FPS by request), hitscan weapon, head-growth-over-time
  mechanic, death → scaled explosion → respawn chain.
- Dedicated growing head hitbox tracking the head's true visual center (not
  just its base pivot) — needed because the visible head scales up over
  time but the body's main collision capsule doesn't.
- 4-state bot AI (Patrol/Seek/Attack/Flee) via `NavigationAgent3D`, with
  imprecise aim (`accuracy` chance) so fights aren't instant.
- Procedurally generated arena each match: randomized wall segments,
  crates, columns, plus 2 elevated platforms with ramps up (real
  verticality — see notes below on why ramps not discrete stairs), and
  noise-based rolling-hill terrain (see "Done so far" entry below).
- HUD: health, head-size %, kill feed (now with real player names), hit-marker
  flash, muzzle flash + tracer VFX on fire, match countdown timer,
  toggleable scoreboard (Tab), game-over screen with final scores and
  restart prompt (R).
- Server-authoritative multiplayer wiring in place (single local host only
  right now, no real remote peers).
- **Match structure & scoring**: classic FFA deathmatch — first to
  `Constants.MATCH_KILL_LIMIT` (15) kills or `Constants.MATCH_TIME_LIMIT`
  (5 min) wins, whichever comes first. `GameManager.gd` tracks per-player
  `scores` (kills/deaths) keyed by a new `Character.player_id` (assigned at
  spawn — distinct from multiplayer authority, which stays 1 for everyone
  in Stage 1 and can't tell characters apart). `GameManager.match_over`
  freezes further damage (checked in `HealthComponent.take_damage` and
  `WeaponHitscan.try_fire`) once the match ends. Restarting
  (`Main.restart_match()`) clears characters, swaps in a fresh procedurally
  generated `Arena` instance, and resets `GameManager` state — deliberately
  avoids touching `NetworkManager`/`reload_current_scene()` to sidestep any
  ENet port-rebind risk.
- Chain-explosion kills already correctly attribute to the original
  killer, however many hops deep (verified directly: shoot A, A's death
  explosion kills B, both kills credit the original shooter) — the
  `killer_player_id` is baked into each `Explosion.configure()` call and
  carries through the whole cascade. Confirmed intentional: the original
  killer is *not* immune to their own chain, so standing too close to a
  kill you just landed can still kill you too (kept as-is by request —
  real risk/reward, not a bug).
- `Constants.MATCH_TIME_LIMIT` currently set to **30s** (was 5 min) for
  fast iteration/testing — bump back up before any real playtest.
- **Spawn safety**: `GameManager.get_next_spawn_point()` now picks whichever
  spawn point is farthest from the nearest living enemy, instead of blindly
  round-robining — no more respawning right next to (or facing) someone
  already there. Falls back to round-robin when nobody's alive yet (initial
  match spawns). `RespawnComponent` passes its own `player_id` so a
  respawning character doesn't count itself as a threat.
- **Ammo/reload**: `WeaponHitscan.gd` now has a magazine (`Constants.WEAPON_MAGAZINE_SIZE`
  = 8, tuned so a full mag roughly equals one kill from full HP if every
  shot lands) and auto-reload (`Constants.WEAPON_RELOAD_TIME` = 1.8s) — no
  manual reload key; the magazine starts reloading automatically on the
  next fire attempt after it empties, which works identically for the
  player and bots with zero bot-side special-casing. Firing is blocked
  while `is_reloading` is true. HUD shows an ammo counter (`current/max`)
  that switches to "Reloading..." during reload.
- **Death/spectator feedback**: fixed a real bug found along the way —
  `Character._physics_process` never checked `health.is_alive`, so a dead
  (invisible, non-colliding) character could still walk around and fire
  their weapon for the entire respawn countdown. Now movement/gravity/firing
  freeze on death, but look-around still works (a minimal spectator view
  from the death spot). HUD shows a "Killed by X" / "You died" overlay with
  a live countdown, shown for exactly `Constants.RESPAWN_DELAY` and hidden
  in sync with the actual respawn.
- **Main menu**: `scenes/menu/MainMenu.tscn` is now `run/main_scene`
  (title, Start Match, Quit). Start transitions to `Main.tscn` via
  `change_scene_to_file`. Game-over screen now offers both **R** (restart
  in place, fresh procedural arena) and **M** (return to `MainMenu`).
  `NetworkManager.host_game()`/`join_game()` now call a new `close_peer()`
  first (releases the old `ENetMultiplayerPeer` and its port) — without
  this, returning to the menu and starting a second match risked a port
  rebind failure. Verified directly: menu → match → menu → second match,
  twice through, no errors. Also fixed a bug this surfaced: `GameManager._process()`
  and `NetworkManager.is_server()` called `multiplayer.is_server()`
  unconditionally, which throws when no peer is assigned at all (e.g. idle
  at the main menu after `close_peer()`) — both now check
  `multiplayer.has_multiplayer_peer()` first.
- **Pause menu & settings**: new `Settings` autoload
  (`autoload/Settings.gd`) holds `mouse_sensitivity` and `master_volume`,
  persisted to `user://settings.cfg` via `ConfigFile`. `mouse_sensitivity`
  moved out of `Constants.gd` (was a fixed const, now user-configurable);
  `master_volume` drives the "Master" `AudioServer` bus directly (works
  correctly even before any actual sound effects exist — see Tier 2 sound,
  still pending). A single reusable `scenes/menu/SettingsPanel.tscn` (two
  sliders + Back) is used both from `MainMenu` and the new in-match pause
  menu, so there's one settings implementation, not two. Pause (**Esc**)
  toggles `get_tree().paused` — `HUD.gd` sets its own `process_mode` to
  `PROCESS_MODE_ALWAYS` so the pause menu keeps responding while paused;
  every other gameplay node (`Character`, bots, `Timer`s) stays on the
  default `PROCESS_MODE_INHERIT`, so pausing freezes movement/AI/countdowns
  automatically with no per-node changes needed. Verified directly:
  pausing freezes a bot's position and the match timer exactly, resume
  unfreezes both, and settings changes apply live and persist across a
  reload.
- **Sound**: downloaded 3 Kenney SFX packs to `assets/kenney/audio/`
  (`interface` — UI clicks, `scifi` — weapon fire/explosions/mechanical
  sounds, `impact` — footsteps/hit impacts, ~300 files, CC0). New
  `Audio` autoload (`autoload/Audio.gd`) provides `play_sfx_2d`/`play_sfx_3d`/
  `play_random_sfx_3d` — each spawns a one-shot `AudioStreamPlayer(3D)`,
  plays it, and frees itself when finished, so no call site has to manage
  player lifetime by hand. 2D (UI) players use `PROCESS_MODE_ALWAYS` so
  menu clicks are audible even while the game is paused. Wired in: weapon
  fire/hit/reload (`WeaponHitscan.gd`), explosion (`ExplosionArea.gd`, with
  volume scaling by head-size ratio — bigger head, louder bang), footsteps
  (`Character.gd`, distance-based cadence so it naturally matches actual
  movement speed rather than firing on a fixed timer), and UI click
  feedback on every button across `MainMenu`, `SettingsPanel`, and the
  pause menu. All audio routes through the "Master" bus by default, so
  `Settings.master_volume` (see pause/settings entry above) already
  controls it correctly.
- Real gotcha hit while wiring sound, worth remembering for any future
  asset downloads: the Kenney "sci-fi-sounds" zip extracted its `Audio/`
  folder as **read-only** (`dr-xr-xr-x`) — Godot could see the files fine
  but silently failed to write their `.import` sidecar files into that
  directory, so `preload()` on them threw "unrecognized file extension"
  parse errors despite the files being completely valid. Fixed with
  `chmod u+w` on the affected directory, but a stale Godot filesystem cache
  kept skipping re-import even after that — needed a full `rm -rf .godot`
  (safe, it's pure cache) to force a truly fresh scan. If a freshly
  downloaded/extracted asset pack ever throws this exact error, check
  directory permissions first.
- **Noise-based terrain**: new `scripts/arena/ArenaTerrain.gd` (a plain
  `RefCounted`, not a node) builds one rolling-hill heightmap per match via
  `FastNoiseLite` (101×101 grid, `HeightMapShape3D` requires exactly 1
  unit/vertex spacing, no chunking needed since the arena is bounded).
  Border and spawn-point areas are smoothstep-flattened (spawn points
  specifically flatten to *exactly* 0, not "whatever height was already
  there" — see bug note below), plus a 2-pass box blur as an explicit
  slope-bounding backstop. `Arena.gd`'s generation order changed: terrain
  heights generate first, then obstacles place themselves by sampling
  `_get_terrain_height(x, z)` instead of assuming flat y=0 (platforms also
  call `ArenaTerrain.flatten_patch()` on their own footprint so they sit
  flush instead of clipping into or floating above slopes), and only then
  is the actual mesh+`HeightMapShape3D` collision built and the navmesh
  baked — so everything downstream sees the final, fully-flattened heights.
  The old static flat floor in `Arena_Test01.tscn` was removed entirely
  (kept alongside the terrain, it would have let characters walk through
  hills at y=0 instead of over them). Two things validated before/during
  the build, both worth knowing if this code is touched again:
  (1) Godot's navmesh baker *does* correctly parse `HeightMapShape3D`
  terrain via the same `PARSED_GEOMETRY_STATIC_COLLIDERS` mode already used
  for every other obstacle — confirmed with an isolated spike test before
  writing the full pipeline, no fallback needed.
  (2) The visual mesh and physics collision are built from the exact same
  height array and are perfectly aligned — verified directly by comparing
  `get_height()` against real raycast hits (error ~5×10⁻⁶, floating-point
  noise only).
  Real bug caught along the way: `flatten_patch()`'s default behavior
  (flatten to whatever height already happens to be at the center point)
  is correct for platforms but was wrong for spawn points, whose markers
  are static y=1 `Node3D`s, not dynamically placed — fixed by adding an
  explicit `target_height` parameter, with spawn flattening now passing
  `0.0`. Verified end-to-end: 16/16 crates and columns sit exactly on the
  terrain surface at their correct offsets, a platform stayed fully
  reachable (17-point path climbing to the right height), and terrain
  genuinely differs between separate runs/restarts.
- **Terrain flatness follow-up fix**: user playtest report was "terrain
  still is flat." Root cause was tuning, not a data bug — the original
  `NOISE_AMPLITUDE = 2.5` produced a real but tiny ~11° worst-case slope,
  imperceptible at first-person eye height. Raising amplitude alone isn't
  safe: the original 2-pass box blur only bounds *average* slope, not
  worst case, and pushing amplitude up (tried 6.0, 10.0, 7.5) surfaced
  seeds with single-cell slopes of 37-40°+, too close to
  `CharacterBody3D`'s ~45° `floor_max_angle` for comfort. Fixed properly by
  adding `ArenaTerrain.clamp_slopes()` — an explicit iterative
  pairwise-relaxation pass (up to 25 iterations) that mathematically
  guarantees no two adjacent grid cells differ by more than
  `tan(MAX_SLOPE_DEGREES) * CELL_SIZE`, decoupling "visually noticeable"
  amplitude from "guaranteed climbable" slope. Final tuning:
  `NOISE_AMPLITUDE = 12.0`, `MAX_SLOPE_DEGREES = 28.0` (comfortable margin
  under the 45° limit for knockback/jump timing). Verified across 5 seeds:
  height span now 10-16 units per match (vs. the original sub-1-unit
  variation), worst-case slope converges to 28-29.5° on every seed.
  Second real bug caught while re-verifying at the new amplitude:
  `Arena.gd` called `clamp_slopes()` *after* `_generate_obstacles()`, but
  obstacles read `_get_terrain_height()` to place themselves *before* that
  call — so the heightmap could still shift under an already-placed
  obstacle, leaving it floating/sunken by a small amount (caught directly:
  one crate off by ~0.12 units). Fixed by moving `clamp_slopes()` to run
  immediately after `generate()`, before any obstacle samples the
  heightmap — re-verified with 19/19 obstacles landing exactly on the
  final terrain and platform pathfinding still working (12-point path to
  the platform top). Full `Main.tscn` run confirmed clean otherwise (one
  pre-existing, harmless "navmesh edge merge" warning from the baker, not
  a functional error).
- **Headshot damage multiplier**: `WeaponHitscan.try_fire()` resolves
  `result.shape` (a shape index local to the hit CharacterBody3D's compound
  shape, not a node) back to the owning `CollisionShape3D` via
  `shape_find_owner()`/`shape_owner_get_owner()`, then compares it against
  the target's `head_hitbox` — a 2x multiplier
  (`Constants.HEADSHOT_DAMAGE_MULTIPLIER`) applies only on a match. Verified
  directly by firing at a target's head-hitbox world position vs. its torso
  in a headless test: 28 damage (2x14) on the head, 14 on the body, exactly
  as expected.
- **More weapon variety**: extracted shared cooldown/reload/ammo/muzzle-
  flash/tracer/headshot machinery out of `WeaponHitscan.gd` into a new
  `scripts/weapons/WeaponBase.gd`, leaving each concrete weapon to only
  implement `_resolve_shot()` — worth doing once there were two real
  weapons sharing ~150 lines of near-identical logic. Added
  `scripts/weapons/WeaponShotgun.gd`/`scenes/weapons/WeaponShotgun.tscn`: 6
  independent pellet rays per trigger pull spread across an 8° cone (via
  `tan()` of a random angle, not a random offset vector, so pellets land
  in an even disc rather than clustering toward center), 5 damage each (30
  max per shot before headshots), 18-unit range (vs. the blaster's 100),
  0.9s cooldown, 2-round magazine, 2.2s reload — a close-range burst
  alternative to the blaster's reliable long-range single shot. Both
  weapons now live permanently as children of `WeaponMount` (no pickup/
  inventory system); `Character.gd` tracks `_active_weapon_index`, toggles
  visibility between them, and switches on a new `switch_weapon` input
  action (Q) via a new `weapon_switched` signal that `HUD.gd` listens to,
  re-targeting its ammo/hit-marker signal connections and updating the
  ammo label's weapon-name prefix immediately on switch (connects to every
  weapon's signals up front since only the active one ever actually fires,
  so no dynamic connect/disconnect juggling needed). Bots never switch
  (their input command never sets `switch_weapon_pressed`), so they stay
  on the blaster by design — not considered unfair since bot AI is
  intentionally simple. Verified directly in a headless test: switching
  toggles the correct weapon's visibility/active state, a point-blank
  shotgun blast on a target's torso dealt 25 damage (5 of 6 pellets
  landed, consistent with the spread cone), ammo dropped by exactly 1 per
  trigger pull despite firing 6 rays, and the magazine correctly
  auto-reloaded after the 2nd shot emptied it.
- **Visual stairs — tried and reverted**: attempted swapping the ramp's
  flat box mesh for an instanced Kenney `stairs.glb` model (purely visual,
  oriented upright rather than tilted to the incline). Along the way, found
  and fixed a real Godot gotcha — `Basis.scaled(v)` scales along **world**
  X/Y/Z axes, not a rotated basis's own local axes, so it silently sheared
  the mesh on any non-axis-aligned ramp; fixed by building the
  already-scaled basis columns directly instead. Numerically verified
  correct after that fix (exact `RAMP_WIDTH` on the width axis, correct
  rise/run on the others). Reverted anyway after actual playtesting: the
  stair mesh has no collision of its own (the real collision is still the
  separate invisible inclined box), so visually it looked like walking
  straight through solid-looking stairs, and a single non-uniformly
  scaled model didn't read as real stairs regardless. Back to the plain
  box mesh visual for now — see "Known limitations" below.

**Bugs found & fixed along the way** (worth knowing about if something
regresses):
- Kenney body model was facing the camera instead of the movement-forward
  direction — fixed by rotating the model 180°.
- `SpringArm3D` (from the original 3rd-person camera) was self-colliding
  with the player's own capsule because they shared a collision layer —
  fixed by putting characters on their own layer (2) separate from world
  geometry (1). Camera was later replaced entirely with a direct
  first-person `Camera3D` per user request, which sidesteps this class of
  bug going forward.
- Bots briefly stole the "current" `Camera3D` from the player during their
  own spawn `_ready()` (every `Character.tscn` ships a default
  `PlayerInputProvider` until swapped) — fixed by swapping the input
  provider *before* the character enters the tree.
- Head hitbox was anchored at the head mesh's base pivot (chin/neck), not
  its visual center — as the head grew, the pivot and the visual center
  diverged (up to ~1.2 units apart at max growth), so headshots increasingly
  missed. Fixed by tracking the mesh's actual AABB center each frame.
- Ramp's low end sat exactly flush with the floor, creating a geometric
  seam characters could catch on — fixed by burying that end slightly below
  floor level.
- Weapon fire had zero feedback (no sound/flash/hit marker existed at all),
  which made "am I even hitting anything" impossible to tell — added
  tracer/muzzle flash/hit marker.

**Balance/tuning notes** (current values live in `scripts/util/Constants.gd`):
- Weapon: 14 dmg / 0.35s cooldown (~8 hits to kill from full HP).
- Head growth: 25s to reach max size (1.0x → 3.0x), so it's visible within
  a normal life.
- Explosion at max head growth: radius up to 75, damage up to 800 — kills
  most/all of the map from a typical death location, not literally
  guaranteed from every possible corner-to-corner distance.
- Movement speed scales down to 50% at max head growth (bigger head =
  slower, easier target — the tradeoff for the bigger explosion).
- `Constants.BOTS_CAN_FIRE` — a test-only toggle added while debugging
  aiming issues (set to `false` disarms all bots so you can test your own
  aim in isolation). **Currently `true`** (normal gameplay). If bots ever
  seem suspiciously passive, check this flag first.

## Known limitations / things not done

- No in-game key-rebinding UI (the input map itself supports it already).
- No background music, only SFX (weapon/explosion/footsteps/UI).
- Ramps are still a plain smooth inclined box, both visually and for
  collision (discrete step colliders risk snagging player/bot movement) —
  a decorative stair-mesh attempt was tried and reverted, see "Done so
  far" above.
- Bot patrol has a 30% chance to target a platform directly (otherwise
  platforms would almost never see traffic in a large arena) — this is a
  bit of a hack; a nicer long-term fix would be genuine points-of-interest
  weighting.

## Gap audit — what's missing from "a complete game"

Full audit done via `/plan`; recommended priority order below (not a
commitment, just a suggested order).

**Tier 1 — core game gaps (highest impact):**
- [x] Win/lose condition or match structure — done, see "Done so far" above.
- [x] Scoreboard/persistent score — done, see "Done so far" above.
- [x] Ammo/reload system — done, see "Done so far" above.
- [x] Spawn safety — done, see "Done so far" above.
- [x] Death/spectator feedback — done, see "Done so far" above. All of
	  Tier 1 is now complete.

**Tier 2 — expected baseline polish:**
- [x] Main menu — done, see "Done so far" above.
- [x] Pause menu — done, see "Done so far" above.
- [x] Settings/options UI (sensitivity, volume) — done, see "Done so far"
	  above. Key rebinding UI not included (the input map itself already
	  supports rebinding, just no in-game UI for it) — left for later if
	  wanted.
- [x] Sound (weapon fire, explosion, footsteps, UI) — done, see "Done so
	  far" above. Ambient/background music not included — see "Known
	  limitations" above. **All of Tier 2 is now complete.**

**Tier 3 — lower priority, genre-typical:** minimap/radar, directional
damage indicator, player customization/skins, accessibility options,
additional game modes (currently implicit free-for-all).

## Backlog / possible next steps

Nothing here is committed to — just candidates to pick from next session.

- [x] Noise-based terrain (rolling hills) — done, see "Done so far" above.
- [ ] Stage 2: local multiplayer (split-screen/hotseat)
- [ ] Stage 3: real networked multiplayer (host/join UI, client prediction)
- [x] Headshot damage multiplier — done, see "Done so far" above.
- [x] More weapon variety — done, see "Done so far" above.
- [ ] Visual stairs — tried and reverted, see "Done so far" above (the
	  ramp still looks like a plain inclined box for now).
- [ ] More elaborate platform layouts (multiple tiers, connected platforms)
- [ ] Background music (SFX already done, see "Known limitations" above)
- [ ] In-game key-rebinding UI (input map already supports it)
- [ ] Tier 3 polish: minimap/radar, directional damage indicator, player
	  skins, accessibility options, additional game modes
