extends Control

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
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_settings_pressed() -> void:
	main_buttons.visible = false
	settings_panel.visible = true


func _on_settings_closed() -> void:
	settings_panel.visible = false
	main_buttons.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()
