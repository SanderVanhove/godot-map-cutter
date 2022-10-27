tool
extends EditorPlugin


const EditPanel = preload("./MapCutter.tscn")

var _panel: Control = null
var _nav_poly_instance: NavigationPolygonInstance = null


func handles(object):
	if object.is_class("NavigationPolygonInstance"):
		return true
	return false


func edit(object):
	_nav_poly_instance = object


func make_visible(visible: bool):
	if visible and not is_instance_valid(_panel):
		_panel = EditPanel.instance()
		add_control_to_bottom_panel(_panel, "Map Cutter")
		_panel.setup(_nav_poly_instance)
	elif is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()


func _exit_tree():
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
