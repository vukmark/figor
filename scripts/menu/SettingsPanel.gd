extends Control

## Emitted when the Back button is pressed — the parent context (MainMenu or
## the in-match pause menu) decides what to show instead.
signal closed()

const SENSITIVITY_MIN := 0.001
const SENSITIVITY_MAX := 0.01

@onready var sensitivity_slider: HSlider = $VBoxContainer/SensitivityRow/SensitivitySlider
@onready var sensitivity_value_label: Label = $VBoxContainer/SensitivityRow/ValueLabel
@onready var volume_slider: HSlider = $VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $VBoxContainer/VolumeRow/ValueLabel
@onready var back_button: Button = $VBoxContainer/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	sensitivity_slider.min_value = SENSITIVITY_MIN
	sensitivity_slider.max_value = SENSITIVITY_MAX
	sensitivity_slider.step = 0.0005
	sensitivity_slider.value = Settings.mouse_sensitivity

	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.value = Settings.master_volume

	_update_labels()

	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	volume_slider.value_changed.connect(_on_volume_changed)
	back_button.pressed.connect(func() -> void: closed.emit())


func _on_sensitivity_changed(value: float) -> void:
	Settings.mouse_sensitivity = value
	Settings.save_settings()
	_update_labels()


func _on_volume_changed(value: float) -> void:
	Settings.master_volume = value
	Settings.save_settings()
	_update_labels()


func _update_labels() -> void:
	sensitivity_value_label.text = "%.4f" % Settings.mouse_sensitivity
	volume_value_label.text = "%d%%" % round(Settings.master_volume * 100.0)
