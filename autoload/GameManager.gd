extends Node

## Emitted whenever a character dies, after scores have been updated —
## HUD kill feed listens to this.
signal character_died(victim_player_id: int, killer_player_id: int)
## Emitted once, when the match ends (kill limit or time limit reached).
signal match_ended(winner_player_id: int, reason: String)
## Emitted whenever a score changes, so a scoreboard UI can refresh.
signal scores_changed()

const character_scene: PackedScene = preload("res://scenes/character/Character.tscn")
const explosion_scene: PackedScene = preload("res://scenes/fx/Explosion.tscn")

var world_root: Node3D
var characters_root: Node3D
var fx_root: Node3D
var spawn_points: Array[Node3D] = []
var platform_points: Array[Vector3] = []

## player_id -> {"name": String, "kills": int, "deaths": int}
var scores: Dictionary = {}
var match_time_remaining := Constants.MATCH_TIME_LIMIT
var match_over := false

var _spawn_index := 0
var _next_player_id := 1
var _bot_number := 0

## Never reset (unlike _next_player_id/_bot_number, which intentionally
## restart each match for scoring/display purposes) — guarantees every
## spawned Character gets a node name it never had before, for the whole
## process lifetime. Godot's default auto-uniquified sibling names
## ("Character", "Character2", ...) reset back to the same sequence every
## time characters_root is emptied, so a restart would immediately reuse
## the exact names the just-despawned characters had — reproduced as a
## real NodePath identity collision in the multiplayer replication cache
## on a connected client (manifests as "Node not found: .../
## MultiplayerSynchronizer" errors, and in one repro an engine crash).
var _spawn_sequence := 0

## Real ENet peer_id -> Character, server-only (bots never enter this map,
## they pass peer_id 0). Used to despawn a departed player's character on
## disconnect.
var _peer_characters: Dictionary = {}


func register_world(world: Node3D, characters_container: Node3D, fx_container: Node3D, points: Array[Node3D], platforms: Array[Vector3] = []) -> void:
	world_root = world
	characters_root = characters_container
	fx_root = fx_container
	spawn_points = points
	platform_points = platforms
	_spawn_index = 0


## Called once per new match (including restarts) — GameManager is an
## autoload and its state would otherwise persist stale scores/timers across
## a fresh match.
func reset_match() -> void:
	scores.clear()
	match_time_remaining = Constants.MATCH_TIME_LIMIT
	match_over = false
	_spawn_index = 0
	_next_player_id = 1
	_bot_number = 0
	_peer_characters.clear()


func _process(delta: float) -> void:
	# multiplayer.is_server() throws if no peer is assigned at all (e.g. while
	# sitting at the main menu after NetworkManager.close_peer()) — has_multiplayer_peer()
	# guards that instead of erroring every single frame.
	if match_over or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	match_time_remaining = max(match_time_remaining - delta, 0.0)
	if match_time_remaining <= 0.0:
		_end_match(_leading_player_id(), "time limit reached")


## Picks the spawn point farthest from the nearest living enemy, rather than
## blindly round-robining — otherwise a respawn can drop you right next to
## (or facing) someone already there. `excluding_player_id` lets a
## respawning character skip itself in the danger check (it's usually
## already dead/not-yet-alive at this point anyway, but this is defensive).
func get_next_spawn_point(excluding_player_id: int = -1) -> Node3D:
	if spawn_points.is_empty():
		return null

	var threat_positions: Array[Vector3] = []
	if characters_root:
		for c in characters_root.get_children():
			if c is Character and c.health.is_alive and c.player_id != excluding_player_id:
				threat_positions.append(c.global_transform.origin)

	if threat_positions.is_empty():
		# Nobody alive to be unsafe from yet (e.g. very first spawns of a
		# match) — round-robin keeps the initial spread even.
		var point := spawn_points[_spawn_index % spawn_points.size()]
		_spawn_index += 1
		return point

	var safest_point: Node3D = spawn_points[0]
	var safest_min_dist := -1.0
	for sp in spawn_points:
		var sp_pos: Vector3 = sp.global_transform.origin
		var nearest_threat_dist := INF
		for pos in threat_positions:
			nearest_threat_dist = min(nearest_threat_dist, sp_pos.distance_to(pos))
		if nearest_threat_dist > safest_min_dist:
			safest_min_dist = nearest_threat_dist
			safest_point = sp
	return safest_point


## Server-authoritative: only ever called on the host/server. `display_name`
## is auto-generated ("Player" / "Bot N") when left blank. `peer_id` is the
## real ENet peer this character belongs to (0 for bots — never a valid
## ENet peer id, so it's a safe "no owner" sentinel distinct from the -1
## already used elsewhere for "no killer").
func spawn_character(input_provider_scene: PackedScene, display_name: String = "", peer_id: int = 0) -> Node:
	if character_scene == null or characters_root == null:
		push_warning("GameManager: character_scene or characters_root not set")
		return null
	var character := character_scene.instantiate()
	_spawn_sequence += 1
	character.name = "Character_%d" % _spawn_sequence
	character.set_multiplayer_authority(1)
	character.owning_peer_id = peer_id

	# Swap the input provider BEFORE the character enters the tree, so its
	# _ready() never sees the scene's default PlayerInputProvider. Otherwise
	# a bot would briefly report itself as the locally-controlled player
	# during its own _ready() (stealing the "current" Camera3D from whichever
	# camera actually held it, since only one Camera3D can be current per
	# viewport) before being corrected a moment later.
	if input_provider_scene:
		var slot: Node = character.get_node("InputProviderSlot")
		for child in slot.get_children():
			slot.remove_child(child)
			child.free()
		slot.add_child(input_provider_scene.instantiate())

	if display_name == "":
		if input_provider_scene == null:
			display_name = "Player"
		else:
			_bot_number += 1
			display_name = "Bot %d" % _bot_number

	character.player_id = _next_player_id
	character.display_name = display_name
	scores[character.player_id] = {"name": display_name, "kills": 0, "deaths": 0}
	_next_player_id += 1
	_broadcast_scores()

	characters_root.add_child(character, true)
	if peer_id > 0:
		_peer_characters[peer_id] = character
	var spawn_point := get_next_spawn_point()
	if spawn_point:
		character.global_transform = spawn_point.global_transform
	return character


## Server-only. Called on NetworkManager.player_disconnected. Frees that
## peer's Character; MultiplayerSpawner replicates the despawn to every
## other peer once the node exits the tree on the authority.
func despawn_peer(peer_id: int) -> void:
	if not _peer_characters.has(peer_id):
		return
	var character: Node = _peer_characters[peer_id]
	_peer_characters.erase(peer_id)
	if is_instance_valid(character):
		character.queue_free()


## Server-only: decides an explosion happened, spawns the one-shot effect,
## and records the kill/death.
func spawn_explosion(pos: Vector3, head_scale_ratio: float, killer_player_id: int, victim_player_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if explosion_scene == null or fx_root == null:
		push_warning("GameManager: explosion_scene or fx_root not set")
		return
	var explosion := explosion_scene.instantiate()
	fx_root.add_child(explosion, true)
	explosion.global_position = pos
	if explosion.has_method("configure"):
		explosion.configure(head_scale_ratio, killer_player_id, victim_player_id)

	_record_kill(killer_player_id, victim_player_id)
	character_died.emit(victim_player_id, killer_player_id)
	_sync_character_died.rpc(victim_player_id, killer_player_id)


func _record_kill(killer_player_id: int, victim_player_id: int) -> void:
	if scores.has(victim_player_id):
		scores[victim_player_id]["deaths"] += 1
	# Not a self-kill/suicide, and the killer must be a real registered
	# player — explosions can in principle report an unset (-1) killer id.
	if killer_player_id != victim_player_id and scores.has(killer_player_id):
		scores[killer_player_id]["kills"] += 1
		if scores[killer_player_id]["kills"] >= Constants.MATCH_KILL_LIMIT:
			_end_match(killer_player_id, "kill limit reached")
	_broadcast_scores()


func _leading_player_id() -> int:
	var best_id := -1
	var best_kills := -1
	for id in scores.keys():
		if scores[id]["kills"] > best_kills:
			best_kills = scores[id]["kills"]
			best_id = id
	return best_id


func _end_match(winner_player_id: int, reason: String) -> void:
	if match_over:
		return
	match_over = true
	match_ended.emit(winner_player_id, reason)
	_sync_match_ended.rpc(winner_player_id, reason)


## `scores` is a plain per-instance autoload dict — HUD.gd reads
## GameManager.scores directly (scoreboard/kill-feed/game-over text), so
## without this a client's own HUD would show nothing. Only the server
## calls this (every scores mutation happens server-side already); clients
## receive it and update their own local copy.
func _broadcast_scores() -> void:
	scores_changed.emit()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_scores.rpc(scores)


@rpc("authority", "reliable")
func _sync_scores(new_scores: Dictionary) -> void:
	scores = new_scores
	scores_changed.emit()


## character_died/match_ended are only ever emitted from server-only code
## paths (spawn_explosion/_end_match both early-return on clients) — without
## rebroadcasting them, a client's HUD would never show the "Killed by X" /
## "You died" overlay, kill feed, or game-over screen at all.
@rpc("authority", "reliable")
func _sync_character_died(victim_player_id: int, killer_player_id: int) -> void:
	character_died.emit(victim_player_id, killer_player_id)


@rpc("authority", "reliable")
func _sync_match_ended(winner_player_id: int, reason: String) -> void:
	match_over = true
	match_ended.emit(winner_player_id, reason)
