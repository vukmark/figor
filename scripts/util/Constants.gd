class_name Constants
extends RefCounted

const GROUP_CHARACTERS := "characters"

## Test-only toggle: when false, bots never fire (they still patrol/seek/flee
## normally) so you can verify your own shots actually land and kill,
## without bots shooting back or killing each other. Set back to true
## afterward for normal gameplay.
const BOTS_CAN_FIRE := true

const MOVE_SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8

## Movement speed multiplier at full head growth (1.0 = no penalty at
## min head size, scales down to this at max head size) — bigger head is a
## real tradeoff: a much deadlier death explosion, but a slower, easier
## target while you're carrying it around.
const HEAD_MIN_SPEED_MULTIPLIER := 0.5

const CAMERA_MOUSE_SENSITIVITY := 0.003
const CAMERA_PITCH_MIN := -80.0
const CAMERA_PITCH_MAX := 80.0

const HEAD_MIN_SCALE := 1.0
const HEAD_MAX_SCALE := 3.0
const HEAD_TIME_TO_MAX := 25.0

const HEALTH_MAX := 100.0
const WEAPON_DAMAGE := 14.0
const WEAPON_RANGE := 100.0
const WEAPON_COOLDOWN := 0.35
## A full magazine (8 rounds) roughly matches one kill from full HP if every
## shot lands — miss even one and you're reloading mid-fight.
const WEAPON_MAGAZINE_SIZE := 8
const WEAPON_RELOAD_TIME := 1.8

## At ratio=1.0 (fully grown head) the radius/damage below are tuned to
## realistically wipe out most/all of the 100x100 arena — anyone within
## ~65 units of the blast is guaranteed lethal damage even after falloff,
## and the max radius (75) covers the large majority of the map from most
## death locations.
const EXPLOSION_BASE_RADIUS := 3.0
const EXPLOSION_MAX_RADIUS_MULT := 25.0
const EXPLOSION_BASE_DAMAGE := 40.0
const EXPLOSION_MAX_DAMAGE_MULT := 20.0
const EXPLOSION_BASE_FORCE := 6.0
const EXPLOSION_MAX_FORCE_MULT := 10.0

const KNOCKBACK_FRICTION := 6.0

const RESPAWN_DELAY := 3.0

## Match ends when either is reached first, like a classic FFA deathmatch.
const MATCH_KILL_LIMIT := 15
const MATCH_TIME_LIMIT := 30.0  # 30s for now, easy to bump back up later
