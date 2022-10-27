tool
extends Control

var SAVE_LOCATION: String = "res://addons/map_cutter/map_cutter_state.json"

onready var _agent_radius: HBoxContainer = $HSplitter/VBoxRight/AgentRadius
onready var _simplification: HBoxContainer = $HSplitter/VBoxRight/Simplification
onready var _circle_segments: HBoxContainer = $HSplitter/VBoxRight/CircleSegments
onready var _margin: HBoxContainer = $HSplitter/VBoxRight/Margin


var _nav_poly_instance: NavigationPolygonInstance


func _ready():
	load_state()


func setup(nav_poly_instance: NavigationPolygonInstance):
	_nav_poly_instance = nav_poly_instance


func save_state():
	var save_file: File = File.new()
	save_file.open(SAVE_LOCATION, File.WRITE)

	var data: Dictionary = {
		agent_radius=_agent_radius.get_value(),
		simplification=_simplification.get_value(),
		circle_segments=_circle_segments.get_value(),
		margin=_margin.get_value(),
	}

	save_file.store_line(to_json(data))
	save_file.close()


func load_state():
	var save_file: File = File.new()

	if not save_file.file_exists(SAVE_LOCATION):
		return

	save_file.open(SAVE_LOCATION, File.READ)

	var data_string: String = save_file.get_as_text()
	if data_string.empty(): return

	var data: Dictionary = parse_json(data_string)
	_agent_radius.set_current_value(data.agent_radius)
	_simplification.set_current_value(data.simplification)
	_circle_segments.set_current_value(data.circle_segments)
	_margin.set_current_value(data.margin)

	save_file.close()


func generate(is_slow_mode: bool):
	save_state()

	var radius: float = _agent_radius.get_value()
	var margin: float = _margin.get_value() + radius * 2

	var bounds: Dictionary = {
		minimum = {x = INF, y = INF},
		maximum = {x = -INF, y = -INF}
	}

	var collisions: Array = get_all_collision_shapes()
	var polygons: Array = []

	for collision in collisions:
		var collision_poly: PoolVector2Array = generate_poly_from_collision_shape(collision)
		var transformed_poly: PoolVector2Array = collision.global_transform.xform(collision_poly)
		polygons.append_array(Geometry.offset_polygon_2d(transformed_poly, radius, Geometry.JOIN_MITER))

		for point in transformed_poly:
			bounds.minimum.x = min(bounds.minimum.x, point.x)
			bounds.minimum.y = min(bounds.minimum.y, point.y)
			bounds.maximum.x = max(bounds.maximum.x, point.x)
			bounds.maximum.y = max(bounds.maximum.y, point.y)

	var maring_vec: Vector2 = Vector2(margin, margin)
	var space = PoolVector2Array([
		Vector2(bounds.minimum.x, bounds.minimum.y) - maring_vec / 2,
		Vector2(bounds.maximum.x + margin / 2, bounds.minimum.y - margin / 2),
		Vector2(bounds.maximum.x, bounds.maximum.y) + maring_vec / 2,
		Vector2(bounds.minimum.x - margin / 2, bounds.maximum.y + margin / 2),
	])

	var merged_polygons: Array = merge_overlaping_polygons(polygons, space, is_slow_mode)
	construct_navmesh(merged_polygons, space)


func construct_navmesh(polygons: Array, space: PoolVector2Array):
	_nav_poly_instance.global_position = Vector2.ZERO

	_nav_poly_instance.navpoly = NavigationPolygon.new()
	_nav_poly_instance.navpoly.clear_outlines()
	_nav_poly_instance.navpoly.clear_polygons()
	_nav_poly_instance.navpoly.add_outline(space)

	for polygon in polygons:
		var simplifyed_poligon: PoolVector2Array = simplify_poligon(polygon)
		_nav_poly_instance.navpoly.add_outline(simplifyed_poligon)

	_nav_poly_instance.navpoly.make_polygons_from_outlines()


func simplify_poligon(polygon: PoolVector2Array) -> PoolVector2Array:
	var simplification_threshold: float = _simplification.get_value()

	var point_index: int = 0
	while point_index < len(polygon) - 1:
		var point_a: Vector2 = polygon[point_index]

		while point_index + 1 < len(polygon) and point_a.distance_to(polygon[point_index + 1]) < simplification_threshold:
			polygon.remove(point_index + 1)

		point_index += 1

	if polygon[0].distance_to(polygon[-1]) < simplification_threshold:
		polygon.remove(0)

	# Remove exact duplicate points
	point_index = 0
	while point_index < len(polygon) - 1:
		var point_index2: int = point_index + 1
		while point_index2 < len(polygon):
			if polygon[point_index] == polygon[point_index2]:
				polygon.remove(point_index2)
				point_index2 -= 1
			point_index2 += 1
		point_index += 1

	return polygon


func merge_overlaping_polygons(polygons: Array, space: PoolVector2Array, is_slow_mode: bool) -> Array:
	var polygon_datas: Array = []
	for polygon in polygons:
		polygon_datas.append({
			polygon=polygon,
			holes=[]
		})

	var polygon_a_index: int = 0
	while polygon_a_index < len(polygon_datas):
		var polygon_a: PoolVector2Array = polygon_datas[polygon_a_index].polygon
		var merged_polygons: Array = []

		for polygon_b_index in len(polygon_datas):
			if polygon_a_index == polygon_b_index: continue

			var polygon_b: PoolVector2Array = polygon_datas[polygon_b_index].polygon

			var merged_polygon: Array = Geometry.merge_polygons_2d(polygon_a, polygon_b)

			if not did_merge(merged_polygon): continue

			var is_in_hole: bool = false
			for hole_index in len(polygon_datas[polygon_a_index].holes):
				var hole = polygon_datas[polygon_a_index].holes[hole_index]
				var hole_merge = Geometry.merge_polygons_2d(hole, polygon_b)
				if did_merge(hole_merge):
					if is_same_poly(hole_merge[0], hole): # the poly is completely in the hole
						is_in_hole = true
					else: # the poly is pushing the boundry of the hole
						var clipped: Array = Geometry.clip_polygons_2d(hole, polygon_b)
						if len(clipped) != 0:
							polygon_datas[polygon_a_index].holes[hole_index] = clipped[0]
						else:
							polygon_datas[polygon_a_index].holes.remove(hole_index)
						merged_polygons.append(polygon_b_index)

						if is_same_poly(merged_polygon[0], polygon_a): # the poly is NOT pushing the boundry of poly a too
							is_in_hole = true
					break
			if is_in_hole: continue

			var a_got_merged: bool = false
			for hole_index in len(polygon_datas[polygon_b_index].holes):
				var hole = polygon_datas[polygon_b_index].holes[hole_index]
				var hole_merge = Geometry.merge_polygons_2d(hole, polygon_a)
				if did_merge(hole_merge):
					if is_same_poly(hole_merge[0], hole):
						is_in_hole = true
					else:
						a_got_merged = true

						var clipped: Array = Geometry.clip_polygons_2d(hole, polygon_a)
						if len(clipped) != 0:
							polygon_datas[polygon_b_index].holes[hole_index] = clipped[0]
						else:
							polygon_datas[polygon_b_index].holes.remove(hole_index)
						merged_polygons.append(polygon_a_index)

						polygon_datas[polygon_b_index].holes.append_array(polygon_datas[polygon_a_index].holes)

						if not is_same_poly(merged_polygon[0], polygon_b):
							polygon_datas[polygon_b_index].polygon = Geometry.merge_polygons_2d(polygon_b, polygon_a)[0]
					break
			if a_got_merged: break
			if is_in_hole: continue

			polygon_a = merged_polygon[0]
			merged_polygons.append(polygon_b_index)
			if len(merged_polygon) > 1:
				merged_polygon.remove(0)
				polygon_datas[polygon_a_index].holes.append_array(merged_polygon)
			polygon_datas[polygon_a_index].holes.append_array(polygon_datas[polygon_b_index].holes)

		polygon_datas[polygon_a_index].polygon = polygon_a

		merged_polygons.invert()
		for polygon_index in merged_polygons:
			polygon_datas.remove(polygon_index)
			if polygon_index < polygon_a_index:
				polygon_a_index -= 1

		# Re-merge poygon later on if it was able to merge this round
		if merged_polygons.empty() or polygon_a_index in merged_polygons:
			polygon_a_index += 1

		if is_slow_mode:
			yield(get_tree().create_timer(.5), "timeout")
			var resulting_polygons: Array = []
			for polygon_data in polygon_datas:
				resulting_polygons.append(polygon_data.polygon)
				resulting_polygons.append_array(polygon_data.holes)
			construct_navmesh(resulting_polygons, space)

	var resulting_polygons: Array = []
	for polygon_data in polygon_datas:
		resulting_polygons.append(polygon_data.polygon)
		resulting_polygons.append_array(polygon_data.holes)

	return resulting_polygons


func did_merge(merge_result: Array) -> bool:
	var clockwise: int = 0
	for polygon in merge_result:
		clockwise += int(Geometry.is_polygon_clockwise(polygon))

	if len(merge_result) > 1 and clockwise != len(merge_result) - 1:
		return false

	return true


func is_same_poly(poly1: PoolVector2Array, poly2: PoolVector2Array):
	if len(poly1) != len(poly2): return false

	for point in poly1:
		if poly2.find(point) == -1: return false

	return true


func generate_poly_from_collision_shape(collision_shape: Node2D) -> PoolVector2Array:
	if collision_shape.is_class("CollisionPolygon2D"):
		return collision_shape.polygon

	var shape: Shape2D = collision_shape.shape
	match shape.get_class():
		"CapsuleShape2D":
			return generate_capsule_poly_from_shape(shape)
		"CircleShape2D":
			return generate_circle_poly_from_shape(shape)
		"ConcavePolygonShape2D":
			return shape.segments
		"ConvexPolygonShape2D":
			return shape.points
		"RectangleShape2D":
			return generate_rect_poly_from_shape(shape)
		_:
			printerr("Shape not supported: ", shape.get_class())

	return PoolVector2Array()


func generate_rect_poly_from_shape(rect_shape: RectangleShape2D) -> PoolVector2Array:
	return generate_rect_poly(rect_shape.extents)


func generate_rect_poly(boundaries: Vector2) -> PoolVector2Array:
	return PoolVector2Array([
		-boundaries,
		Vector2(boundaries.x, -boundaries.y),
		boundaries,
		Vector2(-boundaries.x, boundaries.y),
	])


func generate_circle_poly_from_shape(circle_shape: CircleShape2D) -> PoolVector2Array:
	return generate_circle_poly(circle_shape.radius)


func generate_circle_poly(radius: float) -> PoolVector2Array:
	var num_sides: int = _circle_segments.get_value()
	var angle_delta: float = (PI * 2) / num_sides
	var vector: Vector2 = Vector2(radius, 0)
	var polygon: PoolVector2Array = PoolVector2Array()

	for _i in num_sides:
		polygon.append(vector)
		vector = vector.rotated(angle_delta)

	return polygon


func generate_capsule_poly_from_shape(capsule_shape: CapsuleShape2D) -> PoolVector2Array:
	var radius: float = capsule_shape.radius
	var boundaries: Vector2 = Vector2(radius, capsule_shape.height / 2)

	var rect_poly: PoolVector2Array = generate_rect_poly(boundaries)
	var circle_poly1: PoolVector2Array = generate_circle_poly(radius)
	circle_poly1 = Transform2D(0, Vector2(0, boundaries.y)).xform(circle_poly1)
	var circle_poly2: PoolVector2Array = generate_circle_poly(radius)
	circle_poly2 = Transform2D(0, Vector2(0, -boundaries.y)).xform(circle_poly2)

	return Geometry.merge_polygons_2d(Geometry.merge_polygons_2d(rect_poly, circle_poly1)[0], circle_poly2)[0]


func get_all_collision_shapes() -> Array:
	var scene_tree: Node2D = get_tree().get_edited_scene_root() if Engine.editor_hint else get_tree().root.get_child(0)

	var static_body_list: Array = []
	get_all_nodes_recursive("StaticBody2D", scene_tree, static_body_list)

	var collision_list: Array = []
	for static_body in static_body_list:
		for child in static_body.get_children():
			if child.is_class("CollisionShape2D") and not child.disabled:
				collision_list.append(child)
			if child.is_class("CollisionPolygon2D") and not child.disabled:
				collision_list.append(child)

	return collision_list


func get_all_nodes_recursive(type: String, tree: Node, array: Array):
	for child in tree.get_children():
		if child.is_class(type):
			array.append(child)
			continue

		get_all_nodes_recursive(type, child, array)


func _on_GenerateButton_pressed() -> void:
	generate(Input.is_key_pressed(KEY_CONTROL))
