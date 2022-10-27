extends Node2D


onready var map_cutter: Control = $MapCutter
onready var navigation_polygon_instance: NavigationPolygonInstance = $NavigationPolygonInstance


func _ready() -> void:
	map_cutter.setup(navigation_polygon_instance)
	map_cutter.generate()
