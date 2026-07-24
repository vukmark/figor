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

const EXPLOSION_BASE_RADIUS := 3.0
const EXPLOSION_MAX_RADIUS_MULT := 3.0
const EXPLOSION_BASE_DAMAGE := 40.0
const EXPLOSION_MAX_DAMAGE_MULT := 2.5
const EXPLOSION_BASE_FORCE := 6.0
const EXPLOSION_MAX_FORCE_MULT := 3.0

const KNOCKBACK_FRICTION := 6.0

const RESPAWN_DELAY := 3.0
