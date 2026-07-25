# Figor — Project Plan & Status

Living document. Update this as we go — it tracks what's done, what's in
progress, and what's next.

Note: `/home/marko/.claude/plans/logical-bubbling-flute.md` is Claude Code's
plan-mode scratch file — it gets *overwritten* every time a new `/plan`
session runs, so it only ever holds the most recently drafted plan (currently:
noise-based terrain, see backlog below), not a history. Anything worth
keeping long-term belongs here instead.

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
  verticality — see notes below on why ramps not discrete stairs).
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
- Ramps use smooth inclined-box collision, not literal Kenney stair meshes
  with discrete steps (discrete step colliders risk snagging
  player/bot movement — this was a deliberate tradeoff, see notes above).
- Only 1 weapon type (hitscan).
- No headshot damage multiplier — the head hitbox exists for aim
  accuracy/visual correctness, not bonus damage (could be added easily
  since `WeaponHitscan.gd` already knows which shape it hit).
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

- [ ] **Noise-based terrain (rolling hills)** — fully designed, not yet
	  built. Full plan at `/home/marko/.claude/plans/logical-bubbling-flute.md`
	  (until overwritten by a future `/plan` — worth copying into this file
	  or a dedicated doc before that happens if it's not built soon).
	  Short version: `FastNoiseLite` + `HeightMapShape3D`, single static
	  mesh built once per match (not chunked — arena is bounded, ~100x100),
	  flatten patches under spawn points/walls/platforms so existing
	  obstacle logic keeps working, biggest open risk is whether Godot's
	  navmesh baker parses `HeightMapShape3D` correctly (plan includes a
	  spike step to validate that first, with a mesh-instance-parsing
	  fallback if not).
- [ ] Stage 2: local multiplayer (split-screen/hotseat)
- [ ] Stage 3: real networked multiplayer (host/join UI, client prediction)
- [ ] Sound (weapon fire, explosion, footsteps, ambient)
- [ ] Main menu / start screen
- [ ] More weapon variety
- [ ] Headshot damage multiplier
- [ ] Visual stairs (decorative Kenney stair mesh over the existing ramp
	  collision) instead of a plain primitive ramp
- [ ] More elaborate platform layouts (multiple tiers, connected platforms)
