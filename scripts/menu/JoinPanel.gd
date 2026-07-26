extends Control

## Emitted when the Back button is pressed — mirrors SettingsPanel.closed.
signal closed()
## Emitted when Connect is pressed with a non-empty address.
signal connect_requested(address: String, port: int)

const CLICK_SOUND: AudioStream = preload("res://assets/kenney/audio/interface/Audio/click_003.ogg")

@onready var address_edit: LineEdit = $VBoxContainer/AddressEdit
@onready var port_edit: LineEdit = $VBoxContainer/PortEdit
@onready var connect_button: Button = $VBoxContainer/ButtonRow/ConnectButton
@onready var back_button: Button = $VBoxContainer/ButtonRow/BackButton


func _ready() -> void:
	address_edit.text = "127.0.0.1"
	port_edit.text = str(NetworkManager.DEFAULT_PORT)
	connect_button.pressed.connect(_on_connect_pressed)
	back_button.pressed.connect(func() -> void:
		Audio.play_sfx_2d(CLICK_SOUND)
		closed.emit()
	)


func _on_connect_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address == "":
		return
	var port := int(port_edit.text.strip_edges())
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT
	Audio.play_sfx_2d(CLICK_SOUND)
	connect_requested.emit(address, port)
