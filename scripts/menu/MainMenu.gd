extends Control

const CLICK_SOUND: AudioStream = preload("res://assets/kenney/audio/interface/Audio/click_003.ogg")

@onready var main_buttons: VBoxContainer = $VBoxContainer
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var settings_panel: Control = $SettingsPanel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_panel.closed.connect(_on_settings_closed)
	settings_panel.visible = false
	start_button.grab_focus()


func _on_start_pressed() -> void:
	Audio.play_sfx_2d(CLICK_SOUND)
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
