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
- **Stage 2 — skipped by decision.** Local split-screen/hotseat multiplayer
  is rare on PC in practice, so we're jumping straight to real networked
  multiplayer instead of building this.
- **Stage 3 (up next)** — real networked multiplayer (host/join UI, client
  prediction).

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
- **Background music**: Kenney's audio packs turned out to have no real
  ambient/loop music, only short (5-10s) chiptune "jingle" stingers meant
  for things like level-complete fanfares — a poor, repetitive fit for a
  continuous match loop. Sourced "Frozen Jam (Seamless Loop)" by Elle
  Trudgett (edited by qubodup) from OpenGameArt.org instead — a genuine
  103-second seamless cyber/space-themed loop, CC-BY 3.0 (attribution
  required, unlike the rest of the project's CC0 Kenney assets — credited
  in `assets/music/License.txt`). `Audio.gd` gained a persistent
  `AudioStreamPlayer` (autoloads survive scene changes, so this isn't
  recreated per scene) plus `play_music()`/`stop_music()`; `play_music()`
  no-ops if the requested track is already playing, so `Main.gd` can call
  it unconditionally on both initial load and every `restart_match()`
  without the track jarringly restarting from 0 on every restart. Stops on
  the two return-to-main-menu paths in `HUD.gd` (pause menu and the
  game-over screen) so it doesn't keep playing into the menu. Verified
  directly: music is playing at match start with the correct track and
  volume (-10 dB), and a full match run stays clean.

- **Floating health bar above characters**: new `scenes/character/HealthBar3D.tscn`
  (`scripts/character/HealthBar3D.gd`) — two billboarded, unshaded
  `MeshInstance3D` quads (dark background + green fill), `no_depth_test`
  so it stays readable through nearby geometry. Lives under each
  `Character`'s `VisualRoot` — piggybacks on two behaviors that already
  existed for free: `VisualRoot.visible = not is_local_view` already hides
  it for your own first-person view, and `RespawnComponent` hiding the
  whole `Character` node on death already hides it there too, so no new
  visibility logic was needed. `Character._process()` (new — runs on every
  peer, not just the authority, since it just reflects the already-networked
  `HealthComponent.current_health`/`max_health`) calls
  `HealthBar3D.set_ratio()` every frame; the fill quad shrinks from its
  right/far edge inward by scaling `Fill.scale.x` and repositioning it to
  keep the *left* edge pinned to the background's left edge (so it reads as
  "draining," not shrinking from the center). Verified directly: damaging a
  bot to 50% health dropped `Fill.scale.x` to exactly `0.5` and repositioned
  it to the expected `-0.15` (half the 0.6-unit bar width times the drained
  fraction).
  **Follow-up (by request)**: initially placed at a fixed height (y=2.6,
  just clear of even max head growth) — moved to dynamically track the
  head instead, since a static height either sat inside a fully-grown head
  or floated oddly far above a fresh one. `Character._process()` now reads
  `head_hitbox.position.y`/`head_hitbox.shape.radius` (already updated
  every physics frame by `HeadGrowth` to track the head's true, growing
  extent — reused rather than duplicated) and repositions the bar to
  `head_top + HEALTH_BAR_HEAD_CLEARANCE` (0.35) every frame. Verified
  directly: over several seconds of simulated growth, `head_scale` rose
  from ~1.01 to ~1.38 and the bar's height tracked the head's rising
  position + growing radius exactly (e.g. `head_hitbox_y=2.45,
  radius=0.39` → `bar_y=3.19`, matching `2.45 + 0.39 + 0.35`).

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

- **Stage 3 — basic networked multiplayer (no client prediction)**:
  real ENet host/join now works, not just the local-host-only wiring from
  Stage 1. `NetworkManager.host_game()`/`join_game()` (already-functional
  code, just never exercised with a second real peer) are now wired to new
  `MainMenu` Host/Join buttons — Join opens a small `JoinPanel`
  (IP + port, mirrors `SettingsPanel`'s show/hide pattern) — and are called
  *before* `change_scene_to_file` so `Main._ready()` can just branch on
  `NetworkManager.is_server()`.
  Movement stays server-authoritative (`Character` keeps
  `multiplayer_authority = 1`, the host, matching the pre-existing
  `_physics_process` authority gate) — the actual gap closed here is that
  **zero `@rpc` methods existed anywhere** before this, so a remote
  client's input had no way to reach the server. New
  `Character.owning_peer_id` (synced via `spawn=true`, same pattern as
  `head_scale`/`current_health`) lets every peer determine which spawned
  Character is "theirs" (camera activation, input routing). A remote
  client's `PlayerInputProvider` now polls local input and ships it via
  `submit_input_command.rpc_id(1, ...)` (`@rpc("any_peer",
  "unreliable_ordered")`) every physics tick; the server-side receiver
  validates `get_remote_sender_id() == owning_peer_id` (rejects spoofed
  input for a character the sender doesn't own) and stores it for
  `get_input_command()` to return instead of polling local `Input.*`.
  `GameManager.spawn_character()` takes a real `peer_id` now, tracks a
  `peer_id -> Character` map, and `despawn_peer()` cleans up on
  disconnect; `Main.gd` wires `NetworkManager.player_connected/disconnected`
  to spawn/despawn real peers, so late-join mid-match works automatically.
  `restart_match()` is now a no-op for non-server peers (a client
  triggering it would have locally rebuilt spawner-owned state it doesn't
  own — a real latent bug once a second real peer exists, not just a
  theoretical one).
  **Real gap found and fixed along the way, not in the original plan**:
  `GameManager.scores` is a plain per-instance autoload dict and
  `character_died`/`match_ended` are only ever emitted from server-only
  code paths (`spawn_explosion()`/`_end_match()` both early-return on
  clients) — without syncing, a client's HUD would show a permanently
  blank scoreboard/kill-feed and would never show the "Killed by X"/"You
  died" overlay or the game-over screen at all. Fixed with three small
  `@rpc("authority", "reliable")` broadcasts
  (`_sync_scores`/`_sync_character_died`/`_sync_match_ended`) fired
  alongside the existing local signal emits.
  Verified via a headless two-process ENet smoke test (host + a real
  joining peer, no GUI/display available in this environment): peer
  connect → correct `owning_peer_id` assignment → correct per-peer
  `is_locally_controlled`/camera-current resolution on *both* sides →
  scores dict fully replicated to the client, including the joining
  player's own entry. **Not yet verified**: actual movement feel/input
  latency, aiming/firing across a real network, or the visual HUD overlays
  — those need a real two-window playtest (two Godot instances on
  localhost, or two machines on a LAN) since headless mode has no
  display/input.
  Known limitations (by design, this pass): no client-side
  prediction/reconciliation (remote movement will feel laggy, proportional
  to RTT — planned as a separate future pass); no lag compensation for
  hitscan; `jump_pressed`/`switch_weapon_pressed` can be silently dropped
  on packet loss (sent over `unreliable_ordered`, movement/fire self-heal
  on the next packet, these two don't); no reconnect/rejoin state
  carry-over; disconnected players' scoreboard entries linger;
  listen-server only, no dedicated-server mode; `GameManager.match_time_remaining`
  is not synced, so a client's HUD timer will show a static, non-ticking
  value (cosmetic — the server's own timer is what actually ends the
  match).

- **Stage 3 real-usage bug hunt (post-implementation)**: the user's first
  real two-instance playtest (not headless) surfaced two symptoms — client
  falling/clipping through terrain, and mouse not controlling the client's
  look. Root-caused via a headless two-process repro harness (not kept in
  the repo):
  - **Confirmed and fixed**: `Arena.gd` generated its terrain/obstacle
    layout from Godot's global, unseeded RNG (`randi()`/`randf_range()`/
    `randi_range()`, plus `randomize()`) in its own `_ready()` — since
    `Arena` is a plain static child of `Main.tscn` (not spawned via
    `MultiplayerSpawner`), **every peer independently generated a
    completely different random arena**. Character positions were
    correctly synced from the server, but rendered against each client's
    own, different terrain/walls — this is what "gassing through terrain"
    actually was. Fixed by converting `Arena.gd` to a local seeded
    `RandomNumberGenerator` (`_rng`), extracting generation into a public
    `generate_arena(seed_value)` (replaces the old automatic `_ready()`
    generation), and having the server roll one seed per match/restart and
    hand it to clients via new `Main.gd` RPCs (`request_arena_seed`,
    pulled by the client once its own `connected_to_server` signal fires —
    not pushed by the server, which would race the client's own scene-load
    timing; `_apply_arena_seed`, sent back by the server). Verified via the
    repro harness: host and client end up with byte-identical
    `arena_seed`, obstacle count, and platform-point coordinates.
  - **Confirmed and fixed, a second real bug found via the same repro**:
    restarting the match while a real peer was connected reproducibly
    triggered `ERROR: Node not found: .../MultiplayerSynchronizer` on the
    client (matching the user's actual host.log) and, in one repro run, an
    **engine-level crash (SIGSEGV)**. Root cause: `restart_match()`
    despawned every `Character` via immediate `.free()` — deleting a
    `MultiplayerSpawner`-tracked node's replication bookkeeping
    synchronously, before the despawn notification finished flushing to
    the connected client — fixed by switching to `queue_free()`. Also
    fixed: new post-restart characters immediately reused the exact same
    Godot auto-uniquified node names (`Character`, `Character2`, ...) the
    just-despawned ones had, which alone was enough to leave the client
    with a **stale/incorrect character roster** even after the
    `queue_free()` fix — fixed by giving every spawned `Character` a
    permanently unique name (`GameManager._spawn_sequence`, never reset by
    `reset_match()`, unlike the per-match `_next_player_id`/`_bot_number`
    counters).
  - **Not fully resolved — real limitation, not covered up**: even after
    both fixes above, restarting mid-session with a real peer connected
    still leaves that peer's `MultiplayerSpawner` replication unable to
    receive the *newly spawned* post-restart characters (repro showed the
    client stuck with a stale roster, though no longer crashing). Root
    cause not fully isolated — plausibly an engine-level limitation in how
    `MultiplayerSpawner` handles a mass despawn+respawn burst against an
    already-connected peer, though not confirmed. Rather than keep
    patching blindly, `Main.restart_match()` now hard-blocks (with a
    `push_warning`) whenever `multiplayer.get_peers()` is non-empty, so a
    restart can no longer silently corrupt a live multiplayer session —
    restarting is only available again once everyone else has
    disconnected. **This needs real investigation** (ideally with actual
    Godot editor debugging/logging, not just headless repro) before
    restart-while-connected can be safely re-enabled.
  - Terrain fix confirmed by user retest ("terrain is good now"). Follow-up
    retest surfaced two more real, isolated bugs (not the restart-corruption
    guessed above — that theory didn't pan out; these are separate,
    unrelated root causes):
    - **Camera pitch never worked for a client, only yaw did**: yaw is
      applied via `rotate_y()` directly on the `CharacterBody3D`, which
      rides along with the already-synced `.:transform` — but pitch is
      `camera.rotation.x` on a *child* node (`CameraRig/Camera3D`) that was
      never part of `SceneReplicationConfig`, and was only ever being set
      inside `Character._physics_process()`, which — like everything else
      gated on `is_multiplayer_authority()` — never runs at all on a real
      client (authority is always the host). Fixed by having a genuine
      remote client apply its own pitch delta immediately/locally
      (`Character.apply_local_look_pitch()`, called from
      `PlayerInputProvider._input()` only when `not multiplayer.is_server()`,
      to avoid double-applying the same delta on the host, which still
      updates pitch via the pre-existing authoritative path). This is
      intentionally *not* networked — nobody but the owning peer ever
      needs to see their own camera's pitch, so an immediate local update
      is both simpler and more responsive than round-tripping it.
    - **Client couldn't fire — because nobody but the server ever saw/heard
      any shot, from anyone**: `try_fire()`/`_resolve_shot()` (both weapon
      types) call `Audio.play_sfx_3d`/`_spawn_muzzle_flash`/`_spawn_tracer`
      directly — all of which just `add_child` onto *the calling peer's own*
      `get_tree().current_scene`, with zero networking involved. Since
      firing is server-authoritative (`try_fire()` is only ever invoked from
      `Character._physics_process()`, itself authority-gated), 100% of fire
      sound, muzzle flash, tracers, and hit sound only ever appeared on the
      **server's** screen — a client firing (or watching anyone else fire)
      got no feedback at all, even though the shot was actually resolving
      correctly server-side (damage already replicated fine via
      `HealthComponent`, just invisibly/silently). Fixed by having
      `WeaponBase.try_fire()` collect what it just did (tracer endpoints,
      hit positions) and broadcast a single `_replay_fire_feedback` RPC
      (`@rpc("authority", "unreliable")`) so every other peer replays the
      same muzzle flash/tracer(s)/fire sound/hit sound/hit-marker locally.
      Ammo/reload sync (originally deferred here) is now done too — see
      the dedicated entry below.
    Both fixes verified via the headless repro harness (RPC/replication
    plumbing only — no real display/mouse/audio available headless, so the
    *actual feel* of pitch and fire feedback still needs a real two-window
    retest). Mouse pitch confirmed fixed by user retest.
  - **Ammo/reload sync to the owning client**: `WeaponBase._process()`'s
    cooldown/reload countdown ran unconditionally on every peer's own copy
    of a weapon — since `try_fire()` (and thus real ammo/reload state) is
    only ever invoked server-side, every other peer's copy was ticking its
    own separate, meaningless numbers, and a client's own ammo/reload HUD
    could show stale or outright wrong values even though firing itself
    already worked correctly (see fire-feedback fix above). Fixed by
    gating `_process()`'s countdown logic to `is_multiplayer_authority()`
    (weapons inherit their owning `Character`'s authority, so this only
    ever runs server-side now) and adding a targeted (not broadcast —
    ammo is private per-player info) `_apply_ammo_state`
    `@rpc("authority", "reliable")`, sent to the owning peer from all three
    places `current_ammo`/`is_reloading` actually change (firing, starting
    a reload, reload completing). Real bug caught during verification: the
    host firing *its own* weapon tried to `rpc_id()` targeting its own peer
    id, which Godot rejects ("RPC on yourself is not allowed by selected
    mode") — fixed by skipping the sync entirely when the owning peer is
    the caller itself (the host's own local copy is already authoritative,
    nothing to sync). Verified directly via the headless harness: emptied
    a client's magazine from the host, and the client's own weapon showed
    `ammo=0/8, is_reloading=true` within 0.3s and recovered to
    `8/8, is_reloading=false` once the auto-reload completed, matching the
    server's state exactly at both points, with bots (no real owning peer)
    correctly never triggering a sync attempt at all.
  - **Client froze on death with no "killed by" message, plus match timer
    never counted down for a client** — three real bugs from one user
    report, root-caused via the headless repro harness:
    - **Match timer never synced**: `GameManager.match_time_remaining` is a
      plain per-instance autoload var, only ever decremented inside the
      server-only branch of `GameManager._process()` — a client's own copy
      simply never moved from its starting value. Fixed with a
      once-a-second `@rpc("authority", "unreliable") _sync_match_time`
      broadcast (once/sec loses no visible precision since `HUD._format_time`
      only ever displays whole seconds anyway). Verified directly: a
      client's `match_time_remaining` tracked the server's within about a
      second at two separate checkpoints 3 seconds apart.
    - **Real root cause of the freeze + missing kill message (first attempt
      was wrong)**: initially attributed this to the same NodePath-reuse
      bug already fixed for `Character` nodes (see the restart-corruption
      entry above) and gave every `Explosion` a unique name too. That
      didn't fix it — the user's very next `client.log` showed the exact
      same `on_despawn_receive ... recv_nodes doesn't have net_id` errors
      again. The *actual* root cause: `Explosion.tscn`'s entire lifetime is
      only **0.2 seconds** (`LifetimeTimer.wait_time`), which is simply too
      short to reliably survive a real `MultiplayerSpawner` spawn+despawn
      round-trip over any actual network latency — the despawn notification
      can easily arrive at a client before it's even finished registering
      the spawn, regardless of naming. This never showed up in this
      session's own localhost headless testing (near-zero latency never
      exposes the race) but is a real risk over any real connection,
      especially since chain-explosion kills (an intentional mechanic — a
      kill's explosion can itself kill nearby characters, cascading)
      routinely spawn several in quick succession. The resulting cache
      corruption was severe enough to explain both symptoms: the client's
      whole view appearing frozen, and the `_sync_character_died` broadcast
      (added earlier this session) silently failing to arrive, so no
      "Killed by X" message ever showed.
      Properly fixed by not networking the `Explosion` node via
      `MultiplayerSpawner` at all: `GameManager.spawn_explosion()` now
      instantiates a purely local copy on the server
      (`_spawn_local_explosion()`, plain `add_child`, no spawner involved)
      and separately broadcasts a `_replay_explosion`
      `@rpc("authority", "unreliable")` carrying just the data (position,
      head-scale ratio, killer/victim ids) so every other peer builds its
      own independent, also purely local copy. Since `HealthComponent.take_damage()`
      has no authority check of its own, `ExplosionArea._detonate()`'s
      actual damage-dealing loop is now gated to `multiplayer.is_server()`
      — every peer plays the same visual/audio, but only the server's copy
      ever affects real gameplay. Removed the now-dead `MultiplayerSpawner`
      under `Main.tscn`'s `FXRoot` (Explosion was its only spawnable scene).
      Verified with a more realistic retest than the first attempt: let
      real bot combat run for several seconds (3 natural deaths) *while*
      also firing a synthetic burst of 10 more explosions back-to-back — a
      connected client received all 13 `character_died` broadcasts with
      **zero** replication errors, versus the user's real, reproducible
      errors before this fix.
    - **A fourth, genuinely separate bug remained after the above**: user
      retest showed the console errors were gone, but the client still
      never saw the "Killed by X"/"You died" overlay or respawn countdown.
      Root cause: `Character.player_id` was never in `Character.tscn`'s
      `SceneReplicationConfig` at all (only `owning_peer_id` was) — so on
      every client, every character's `player_id` was permanently stuck at
      its unset default (`-1`). `HUD._on_character_died()` decides whether
      to show the death overlay via `victim_player_id ==
      _local_character.player_id`, which could therefore never match on a
      client, even though `character_died` itself was now arriving
      correctly (the kill feed, which doesn't depend on `player_id`,
      already worked). Fixed by adding `player_id` to the replication
      config (`spawn=true`, on-change, same pattern as `owning_peer_id`).
      Verified directly: a client's `HUD._local_character.player_id`
      correctly resolved to the real value (was always `-1` before), and
      killing that character from the host produced
      `death_overlay.visible=true` with the text "Killed by Player /
      Respawning in 1..." on the client — the exact behavior that was
      missing.
- **`restart_match()` properly fixed, not just worked around**: previously
  hard-blocked whenever a real peer was connected, because
  despawning every `Character` and respawning a fresh batch through
  `MultiplayerSpawner` reliably corrupted that peer's replication state —
  tried unique node names, `queue_free()` instead of `free()`, and extra
  idle frames between the despawn/respawn bursts; none of it fully worked
  (see the earlier restart-corruption entries above). Revisited after the
  Explosion investigation established a clearer general lesson: bursty
  spawn/despawn through `MultiplayerSpawner` is inherently fragile, so the
  right fix is avoiding it, not tuning around it. Applied the same idea
  here — `GameManager.restart_for_new_match()` now resets every currently-
  connected `Character` *in place* (reposition/health/head-growth reset
  via the existing `RespawnComponent._do_respawn()` path, wrapped in a
  new `RespawnComponent.force_reset()` that cancels any in-progress death
  countdown first) instead of freeing and respawning anything — no new
  spawns or despawns happen at all, so this whole class of bug is
  eliminated by construction rather than mitigated. As a genuine side
  benefit (not just a workaround-removal), restart now correctly resets
  *every* connected peer's character, not just the host + bots, fixing a
  second documented limitation for free. `Main.restart_match()`'s
  peer-connected guard is removed entirely. `GameManager.reset_match()`
  (the original full reset, including `_next_player_id`/`_bot_number`) is
  now used only for the very first match of a session — reusing it for
  restarts would have collided with the player_ids already held by the
  characters being kept alive.
  Verified directly and thoroughly: restarted with a real connected client
  and confirmed identical `Character` instance IDs before/after (proving
  reuse, not respawn) on both host and client, scores correctly rebuilt to
  0/0 for all 7 players (including the client's own), and the client's own
  character correctly repositioned into the newly-generated arena — all
  with **zero** replication errors. Followed up by killing every character
  post-restart: kills/deaths tallied correctly and stayed perfectly in
  sync between host and client, and a natural (non-scripted) death
  broadcast during the test also arrived cleanly — confirming ordinary
  post-restart gameplay isn't just theoretically fine but actually works.

## Backlog / possible next steps

Nothing here is committed to — just candidates to pick from next session.

- [x] Noise-based terrain (rolling hills) — done, see "Done so far" above.
- [x] Stage 2: local multiplayer — skipped by decision (split-screen is rare
	  on PC), see Stages section above.
- [x] Stage 3: real networked multiplayer, basic pass (host/join UI, real
	  ENet peers, server-authoritative movement via input RPCs) — done, see
	  "Done so far" above. Client-side prediction is explicitly deferred as
	  a separate future pass (see limitations above); needs a real
	  two-window playtest to verify feel/latency (only headless-verified
	  so far).
- [x] Headshot damage multiplier — done, see "Done so far" above.
- [x] More weapon variety — done, see "Done so far" above.
- [ ] Visual stairs — tried and reverted, see "Done so far" above (the
	  ramp still looks like a plain inclined box for now).
- [ ] More elaborate platform layouts (multiple tiers, connected platforms)
- [x] Background music — done, see "Done so far" above.
- [ ] In-game key-rebinding UI (input map already supports it)
- [ ] Tier 3 polish: minimap/radar, directional damage indicator, player
	  skins, accessibility options, additional game modes
- [x] Fix `restart_match()` breaking `MultiplayerSpawner` replication for
	  an already-connected client — done (properly fixed, not worked
	  around: resets characters in place instead of despawning/respawning
	  them), see the Stage 3 bug-hunt entry above.
- [x] Sync ammo/reload state to the owning client — done, see the Stage 3
	  bug-hunt entry above.
