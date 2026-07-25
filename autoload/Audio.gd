extends Node

## Spins up a one-shot player, plays it, and frees itself when done — every
## call site would otherwise duplicate this boilerplate. Both play on the
## "Master" bus by default, so Settings.master_volume affects them
## automatically without any extra wiring here.

const MUSIC_VOLUME_DB := -10.0

## A single persistent player (Audio is an autoload, so this survives scene
## changes) rather than the one-shot-and-free pattern above — music needs to
## keep playing across a match restart instead of cutting out and
## restarting from 0 every time.
var _music_player: AudioStreamPlayer


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)


## No-ops if this exact track is already playing, so callers (e.g.
## Main.gd on both initial load and every restart_match()) can call this
## unconditionally without worrying about restarting the track mid-loop.
func play_music(stream: AudioStream, volume_db: float = MUSIC_VOLUME_DB) -> void:
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.volume_db = volume_db
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()

## Non-positional (UI clicks, menu feedback). PROCESS_MODE_ALWAYS so it still
## plays for menu interactions made while the game is paused (e.g. clicking
## "Resume" in the pause menu).
func play_sfx_2d(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.volume_db = volume_db
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Positional (weapon fire, explosions, footsteps, hit impacts).
func play_sfx_3d(stream: AudioStream, position: Vector3, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


## Picks a random variant from a list — most Kenney SFX come in several
## takes of the same sound so repeated plays don't sound identical.
func play_random_sfx_3d(streams: Array, position: Vector3, volume_db: float = 0.0) -> void:
	if streams.is_empty():
		return
	play_sfx_3d(streams[randi() % streams.size()], position, volume_db)
