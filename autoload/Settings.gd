extends Node

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_MOUSE_SENSITIVITY := 0.003
const DEFAULT_MASTER_VOLUME := 1.0  # linear 0..1

var mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY
var master_volume := DEFAULT_MASTER_VOLUME:
	set(value):
		master_volume = clamp(value, 0.0, 1.0)
		_apply_master_volume()


func _ready() -> void:
	load_settings()
	_apply_master_volume()


func _apply_master_volume() -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index == -1:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(max(master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus_index, master_volume <= 0.0)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY)
	master_volume = config.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("audio", "master_volume", master_volume)
	config.save(SETTINGS_PATH)
