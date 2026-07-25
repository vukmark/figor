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
- Basic HUD: health, head-size %, kill feed, hit-marker flash, muzzle
  flash + tracer VFX on fire.
- Server-authoritative multiplayer wiring in place (single local host only
  right now, no real remote peers).

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

- No audio at all (no sound assets were ever added).
- No main menu — `Main.tscn` auto-hosts and auto-spawns on load.
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
- [ ] Win/lose condition or match structure — right now it runs forever
      with no round timer, kill-limit, or end state. `GameManager.gd`
      tracks nothing beyond spawn bookkeeping. Biggest single gap.
- [ ] Scoreboard/persistent score — `HUD.gd`'s kill feed is transient
      (fades after 5s), no running per-player kill/death tally.
- [ ] Ammo/reload system — `WeaponHitscan.gd` only has a fire cooldown,
      infinite ammo forever.
- [ ] Spawn safety — `GameManager.get_next_spawn_point()` round-robins
      blindly, no check for nearby enemies before dropping you in.
- [ ] Death/spectator feedback — `RespawnComponent.begin_respawn_countdown()`
      just hides the character; no "You died"/"Killed by X" message, no
      death animation, no spectator camera during the 3s respawn delay.

**Tier 2 — expected baseline polish** (see "Known limitations" above):
sound, main menu, pause menu, settings/options UI, restart-match flow.

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
