extends Node

@onready var world: Node3D = $World
@onready var characters_root: Node3D = $World/CharactersRoot
@onready var fx_root: Node3D = $World/FXRoot
@onready var arena: Arena = $World/Arena_Test01

const ARENA_SCENE: PackedScene = preload("res://scenes/arena/Arena_Test01.tscn")
const BOT_INPUT_PROVIDER := preload("res://scenes/character/BotInputProvider.tscn")
const MUSIC_TRACK: AudioStream = preload("res://assets/music/frozenjam-seamlessloop.ogg")

@export var bot_count := 5


func _ready() -> void:
	NetworkManager.host_local()
	GameManager.reset_match()
	GameManager.register_world(world, characters_root, fx_root, arena.get_spawn_points(), arena.get_platform_points())
	_start_match()
	Audio.play_music(MUSIC_TRACK)


func _start_match() -> void:
	GameManager.spawn_character(null, "Player")
	for i in range(bot_count):
		GameManager.spawn_character(BOT_INPUT_PROVIDER)


## Deliberately avoids NetworkManager/reload_current_scene entirely (that
## would tear down and recreate the ENetMultiplayerPeer, risking a port
## rebind failure) — instead just clears characters and swaps in a fresh
## Arena instance, which as a bonus gives a new procedural layout each
## restart, consistent with the "different map every match" design.
func restart_match() -> void:
	for child in characters_root.get_children():
		characters_root.remove_child(child)
		child.free()
	for child in fx_root.get_children():
		fx_root.remove_child(child)
		child.free()

	world.remove_child(arena)
	arena.free()
	arena = ARENA_SCENE.instantiate()
	world.add_child(arena)
	world.move_child(arena, 0)

	GameManager.reset_match()
	GameManager.register_world(world, characters_root, fx_root, arena.get_spawn_points(), arena.get_platform_points())
	_start_match()
	# Not merely defensive: play_music() no-ops when this track is already
	# playing, so a restart keeps the music running uninterrupted instead
	# of jarringly restarting it from 0.
	Audio.play_music(MUSIC_TRACK)
