extends Node

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 32

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

var peer: ENetMultiplayerPeer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Stage 1: host with no remote clients expected. Exercises the same
## ENetMultiplayerPeer + authority code path Stage 3 will use for real hosting,
## so nothing here needs to change when remote clients start joining.
func host_local() -> void:
	host_game(DEFAULT_PORT)


func host_game(port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("NetworkManager: failed to create server: %s" % err)
		return
	multiplayer.multiplayer_peer = peer


func join_game(address: String, port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("NetworkManager: failed to create client: %s" % err)
		return
	multiplayer.multiplayer_peer = peer


func is_server() -> bool:
	return multiplayer.is_server()


func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)
