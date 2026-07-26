extends Control

const CLICK_SOUND: AudioStream = preload("res://assets/kenney/audio/interface/Audio/click_003.ogg")

@onready var main_buttons: VBoxContainer = $VBoxContainer
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var settings_panel: Control = $SettingsPanel
@onready var join_panel: Control = $JoinPanel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_panel.closed.connect(_on_settings_closed)
	join_panel.closed.connect(_on_join_closed)
	join_panel.connect_requested.connect(_on_join_connect_requested)
	settings_panel.visible = false
	join_panel.visible = false
	host_button.grab_focus()


func _on_host_pressed() -> void:
	Audio.play_sfx_2d(CLICK_SOUND)
	NetworkManager.host_game()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_join_pressed() -> void:
	Audio.play_sfx_2d(CLICK_SOUND)
	main_buttons.visible = false
	join_panel.visible = true


func _on_join_closed() -> void:
	main_buttons.visible = true
	join_panel.visible = false


func _on_join_connect_requested(address: String, port: int) -> void:
	NetworkManager.join_game(address, port)
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_settings_pressed() -> void:
	Audio.play_sfx_2d(CLICK_SOUND)
	main_buttons.visible = false
	settings_panel.visible = true


func _on_settings_closed() -> void:
	main_buttons.visible = true
	settings_panel.visible = false


func _on_quit_pressed() -> void:
	Audio.play_sfx_2d(CLICK_SOUND)
	get_tree().quit()
