tool
extends HBoxContainer


onready var _label: Label = $Label
onready var _h_slider: HSlider = $HSlider
onready var _value_label: Label = $Value


export(String) var label_text = "Label" setget set_label_text
export(float) var min_value = 0 setget set_min_value
export(float) var max_value = 100 setget set_max_value
export(float) var step = 1 setget set_step
export(float) var current_value = 50 setget set_current_value


func _ready() -> void:
	_h_slider.connect("value_changed", self, "update_label")
	update_settings()


func update_settings():
	if not is_instance_valid(_label): return

	_label.text = label_text

	_h_slider.min_value = min_value
	_h_slider.max_value = max_value
	_h_slider.step = step
	_h_slider.value = current_value

	update_label()


func get_value() -> float:
	return _h_slider.value


func update_label(_value: float = 0):
	_value_label.text = str(_h_slider.value)


func set_label_text(value: String):
	label_text = value
	update_settings()


func set_min_value(value: float):
	min_value = value
	update_settings()


func set_max_value(value: float):
	max_value = value
	update_settings()


func set_step(value: float):
	step = value
	update_settings()


func set_current_value(value: float):
	current_value = value
	update_settings()
