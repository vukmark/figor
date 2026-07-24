class_name InputCommand
extends RefCounted

var move_vector := Vector2.ZERO   # x = strafe, y = forward(-)/back(+)
var look_delta := Vector2.ZERO    # x = yaw delta, y = pitch delta (radians)
var fire_pressed := false
var jump_pressed := false
var sprint_pressed := false
