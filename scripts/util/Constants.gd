class_name Constants
extends RefCounted

const GROUP_CHARACTERS := "characters"

## Test-only toggle: when false, bots never fire (they still patrol/seek/flee
## normally) so you can verify your own shots actually land and kill,
## without bots shooting back or killing each other. Set back to true
## afterward for normal gameplay.
const BOTS_CAN_FIRE := false

const MOVE_SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8

## Movement speed multiplier at full head growth (1.0 = no penalty at
## min head size, scales down to this at max head size) — bigger head is a
## real tradeoff: a much deadlier death explosion, but a slower, easier
## target while you're carrying it around.
const HEAD_MIN_SPEED_MULTIPLIER := 0.5

## Mouse sensitivity is user-configurable — see the Settings autoload.
const CAMERA_PITCH_MIN := -80.0
const CAMERA_PITCH_MAX := 80.0

const HEAD_MIN_SCALE := 1.0
const HEAD_MAX_SCALE := 6.0
const HEAD_TIME_TO_MAX := 25.0

const HEALTH_MAX := 100.0
const WEAPON_DAMAGE := 14.0
const WEAPON_RANGE := 100.0
const WEAPON_COOLDOWN := 0.35
## A full magazine (8 rounds) roughly matches one kill from full HP if every
## shot lands — miss even one and you're reloading mid-fight.
const WEAPON_MAGAZINE_SIZE := 8
const WEAPON_RELOAD_TIME := 1.8
## The head hitbox grows over a match (see HeadGrowth), so a bigger head is
## both a bigger risk (bigger death explosion) and a bigger target — this
## reward makes aiming for it worthwhile even before it's grown much.
const HEADSHOT_DAMAGE_MULTIPLIER := 2.0

## Close-range burst alternative to the hitscan blaster: short range and
## wide pellet spread mean most pellets miss beyond a few meters, but every
## pellet that lands up close adds up fast (6 * 5.0 = 30 max per shot,
## before headshots, vs. the blaster's single 14).
const SHOTGUN_PELLET_COUNT := 6
const SHOTGUN_PELLET_DAMAGE := 5.0
const SHOTGUN_SPREAD_DEGREES := 8.0
const SHOTGUN_RANGE := 18.0
const SHOTGUN_COOLDOWN := 0.9
const SHOTGUN_MAGAZINE_SIZE := 2
const SHOTGUN_RELOAD_TIME := 2.2

## At ratio=1.0 (fully grown head) max radius is 36 units — a dangerous
## room/cluster-sized blast that punishes anyone nearby, but no longer the
## old 150-unit version that reliably wiped the entire 240x240 arena
## regardless of where the kill happened. Obstacles now also block line of
## sight (see ExplosionArea._detonate), so real cover matters at any size.
const EXPLOSION_BASE_RADIUS := 3.0
const EXPLOSION_MAX_RADIUS_MULT := 12.0
const EXPLOSION_BASE_DAMAGE := 40.0
const EXPLOSION_MAX_DAMAGE_MULT := 40.0
const EXPLOSION_BASE_FORCE := 6.0
const EXPLOSION_MAX_FORCE_MULT := 10.0

const KNOCKBACK_FRICTION := 6.0

const RESPAWN_DELAY := 3.0

## Falling below this world Y counts as a void death (fell off a floating
## island with nothing underneath) — comfortably below the lowest island so
## a player is unmistakably in the void, not just briefly under terrain.
const VOID_KILL_Y := -60.0

## Match ends when either is reached first, like a classic FFA deathmatch.
const MATCH_KILL_LIMIT := 15
const MATCH_TIME_LIMIT := 300.0  # 30s for now, easy to bump back up later
