extends Node

@onready var world: Node3D = $World
@onready var characters_root: Node3D = $World/CharactersRoot
@onready var fx_root: Node3D = $World/FXRoot
@onready var arena: Arena = $World/Arena_Test01

const ARENA_SCENE: PackedScene = preload("res://scenes/arena/Arena_Test01.tscn")
const BOT_INPUT_PROVIDER := preload("res://scenes/character/BotInputProvider.tscn")
const MUSIC_TRACK: AudioStream = preload("res://assets/music/frozenjam-seamlessloop.ogg")

@export var bot_count := 5

## Arena.gd's obstacle/terrain generation is otherwise pure per-peer
## randomness (see Arena.generate_arena) — every peer must build the exact
## same layout from this one seed, or a client's local terrain/obstacles
## won't match what the server (the only peer that actually runs physics)
## is really using, which looks like characters clipping through terrain or
## walking through walls that aren't really there. The server rolls a fresh
## seed once per match/restart and hands it to clients via RPC below.
var _arena_seed := 0


func _ready() -> void:
	# Fallback for running Main.tscn directly (e.g. F6 during dev) without
	# going through MainMenu's Host/Join flow first.
	if not multiplayer.has_multiplayer_peer():
		NetworkManager.host_local()

	GameManager.register_world(world, characters_root, fx_root, arena.get_spawn_points(), arena.get_platform_points())

	if NetworkManager.is_server():
		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		GameManager.reset_match()
		_arena_seed = randi()
		arena.generate_arena(_arena_seed)
		_start_match()
	else:
		# has_multiplayer_peer() is true as soon as join_game() assigns the
		# ENetMultiplayerPeer, but the actual handshake with the server may
		# still be in flight — an RPC sent before CONNECTION_CONNECTED errors
		# ("via a multiplayer peer which is not connected"). Wait for the
		# real connected_to_server signal unless we're already past it.
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			request_arena_seed.rpc_id(1)
		else:
			multiplayer.connected_to_server.connect(func() -> void: request_arena_seed.rpc_id(1), CONNECT_ONE_SHOT)

	# Character nodes themselves need no further action here — MultiplayerSpawner
	# hands clients Character nodes as the server spawns them; each one
	# self-identifies via Character.owning_peer_id (see Character._bind_input_provider).
	Audio.play_music(MUSIC_TRACK)


func _start_match() -> void:
	GameManager.spawn_character(null, "Player", multiplayer.get_unique_id())
	for i in range(bot_count):
		GameManager.spawn_character(BOT_INPUT_PROVIDER)


## A peer connecting (including mid-match) just gets a Character spawned
## into the current world state — get_next_spawn_point()/scoring are
## already peer-count-agnostic, no special-casing of match phase needed.
func _on_player_connected(peer_id: int) -> void:
	GameManager.spawn_character(null, "Player", peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	GameManager.despawn_peer(peer_id)


@rpc("any_peer", "reliable")
func request_arena_seed() -> void:
	if not multiplayer.is_server():
		return
	_apply_arena_seed.rpc_id(multiplayer.get_remote_sender_id(), _arena_seed)


@rpc("authority", "reliable")
func _apply_arena_seed(seed_value: int) -> void:
	_arena_seed = seed_value
	arena.generate_arena(seed_value)


## Deliberately avoids NetworkManager/reload_current_scene entirely (that
## would tear down and recreate the ENetMultiplayerPeer, risking a port
## rebind failure) — instead swaps in a fresh Arena instance (a bonus:
## a new procedural layout each restart, consistent with the "different map
## every match" design) and resets existing Characters in place rather than
## despawning/respawning them.
##
## That despawn/respawn approach used to be blocked outright whenever a
## real peer was connected — freeing a batch of MultiplayerSpawner-tracked
## Characters and immediately respawning a new batch reliably corrupted
## that peer's replication state (see GameManager.restart_for_new_match()'s
## doc comment for the full investigation). Resetting in place needs no
## spawns/despawns at all, which is what actually fixes this rather than
## just working around it — restart now works correctly with real peers
## connected, and as a bonus resets *every* connected peer's character, not
## just the host + bots.
func restart_match() -> void:
	if not NetworkManager.is_server():
		# Non-authoritative peers must never locally rebuild spawner-owned
		# state — their own add_child calls wouldn't replicate anyway.
		return

	# Explosion.tscn is no longer MultiplayerSpawner-replicated (see
	# GameManager._spawn_local_explosion) — these are now plain local nodes
	# on the server, so freeing them here has no cross-peer implications at
	# all; any lingering copy on a client just finishes its own short
	# lifetime independently.
	for child in fx_root.get_children():
		fx_root.remove_child(child)
		child.queue_free()

	world.remove_child(arena)
	arena.free()
	arena = ARENA_SCENE.instantiate()
	world.add_child(arena)
	world.move_child(arena, 0)

	_arena_seed = randi()
	arena.generate_arena(_arena_seed)
	# Any already-connected client needs the new layout too, not just future
	# joiners — a client's own Arena node isn't swapped, it just regenerates
	# in place from the new seed (Arena.generate_arena clears its own old
	# geometry first, so this is safe to call again on the same node).
	_apply_arena_seed.rpc(_arena_seed)

	GameManager.register_world(world, characters_root, fx_root, arena.get_spawn_points(), arena.get_platform_points())
	GameManager.restart_for_new_match()
	# Not merely defensive: play_music() no-ops when this track is already
	# playing, so a restart keeps the music running uninterrupted instead
	# of jarringly restarting it from 0.
	Audio.play_music(MUSIC_TRACK)
