extends Control

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var quit_button: Button = $VBoxContainer/QuitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
