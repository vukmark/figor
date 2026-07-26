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
## rebind failure) — instead just clears characters and swaps in a fresh
## Arena instance, which as a bonus gives a new procedural layout each
## restart, consistent with the "different map every match" design.
func restart_match() -> void:
	if not NetworkManager.is_server():
		# Non-authoritative peers must never locally rebuild spawner-owned
		# state — their own add_child calls wouldn't replicate anyway.
		return

	if not multiplayer.get_peers().is_empty():
		# Confirmed by direct testing: despawning every Character and
		# respawning a fresh batch while a real remote peer is connected
		# leaves that peer's MultiplayerSpawner replication in a broken
		# state — post-restart spawns silently fail to reach it (visible as
		# repeated "Node not found: .../MultiplayerSynchronizer" errors),
		# even after fixing the immediate-free()-during-despawn race below.
		# Root cause not fully isolated yet (possibly an engine-level
		# limitation in how MultiplayerSpawner handles a mass despawn+
		# respawn burst) — until that's resolved, block restart entirely
		# while anyone else is connected rather than risk corrupting a live
		# session for them.
		push_warning("Main: restart_match() blocked — a real peer is connected. See PLAN.md limitations.")
		return

	# queue_free(), not free(): an immediate free() deletes the node's
	# MultiplayerSynchronizer/spawner bookkeeping synchronously, before the
	# replication system finishes flushing the despawn notification to any
	# connected client — that race is what produced the "Node not found:
	# .../MultiplayerSynchronizer" errors seen when restarting with a real
	# second peer connected. queue_free() keeps the object alive (just
	# detached from the tree) until the end of the frame, giving that
	# in-flight network bookkeeping a valid object to finish resolving.
	for child in characters_root.get_children():
		characters_root.remove_child(child)
		child.queue_free()
	for child in fx_root.get_children():
		fx_root.remove_child(child)
		child.queue_free()

	# _start_match() below immediately reuses the exact same auto-assigned
	# node names ("Character", "Character2", ...) the just-removed
	# characters had — spawning new nodes at those NodePaths before the old
	# ones' queued deletion and despawn replication have actually flushed
	# caused a NodePath cache collision on connected clients (reproduced: a
	# hard engine crash during restart with a real second peer connected).
	# A couple of idle frames lets that settle before anything new spawns.
	await get_tree().process_frame
	await get_tree().process_frame

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

	GameManager.reset_match()
	GameManager.register_world(world, characters_root, fx_root, arena.get_spawn_points(), arena.get_platform_points())
	_start_match()
	# Not merely defensive: play_music() no-ops when this track is already
	# playing, so a restart keeps the music running uninterrupted instead
	# of jarringly restarting it from 0.
	Audio.play_music(MUSIC_TRACK)
