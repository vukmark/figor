extends Node

@onready var world: Node3D = $World
@onready var characters_root: Node3D = $World/CharactersRoot
@onready var fx_root: Node3D = $World/FXRoot
@onready var arena: Arena = $World/Arena_Test01

const BOT_INPUT_PROVIDER := preload("res://scenes/character/BotInputProvider.tscn")

@export var bot_count := 5


func _ready() -> void:
	NetworkManager.host_local()
	GameManager.register_world(world, characters_root, fx_root, arena.get_spawn_points(), arena.get_platform_points())
	_start_match()


func _start_match() -> void:
	GameManager.spawn_character(null, 1)
	for i in range(bot_count):
		GameManager.spawn_character(BOT_INPUT_PROVIDER, 1)
