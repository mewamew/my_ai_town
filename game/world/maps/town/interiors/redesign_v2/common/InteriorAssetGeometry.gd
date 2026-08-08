class_name InteriorAssetGeometry
extends RefCounted


const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const CELL_SIZE_PX := 32
const HALF_CELL_SIZE_PX := 16
const GEOMETRY_EPSILON := 0.01
const MAX_ASSET_POLYGON_POINTS := 64
const MAX_BAKED_OCCUPIED_CELL_SCAN := 4096
const MAX_SUPPORTED_GEOMETRY_COORDINATE_PX := 1_000_000.0
const DIRECTIONS: Array[String] = ["down", "right", "up", "left"]
const DIRECTION_VISUAL_POLICIES: Array[String] = [
	"rotationally_symmetric_reuse",
	"strict_four_direction",
]
const DIRECTION_VISUAL_POLICY_REVISION := "furniture_direction_visual_policy_v1"
const DIRECTIONAL_GROUND_CONTACT_ROOMS: Array[String] = [
	"home_template_a",
	"home_template_b",
	"workshop",
]
const PUBLIC_ASSET_FIELDS: Array[String] = [
	"asset_id",
	"canonical_direction",
	"direction_visual_policy",
	"direction_visual_policy_revision",
	"ground_contact",
	"interaction_anchor",
	"label",
	"occlusion_polygon",
	"occupied_cells",
	"physical_size_px",
	"pixel_cluster_size",
	"projection_revision",
	"provenance",
	"room_id",
	"schema_version",
	"source_revision",
	"visual_anchor",
	"visual_effect_anchor",
	"visual_sprite",
]
const REQUIRED_PUBLIC_ASSET_FIELDS: Array[String] = [
	"asset_id",
	"canonical_direction",
	"direction_visual_policy",
	"ground_contact",
	"interaction_anchor",
	"label",
	"occlusion_polygon",
	"occupied_cells",
	"physical_size_px",
	"pixel_cluster_size",
	"projection_revision",
	"provenance",
	"room_id",
	"schema_version",
	"source_revision",
	"visual_anchor",
	"visual_sprite",
]
static var _visible_ground_overlap_cache: Dictionary = {}
static var _source_image_cache: Dictionary = {}


static func rotate_point(point: Vector2, direction: String) -> Vector2:
	match direction:
		"down":
			return point
		"right":
			return Vector2(point.y, -point.x)
		"up":
			return Vector2(-point.x, -point.y)
		"left":
			return Vector2(-point.y, point.x)
	return point


static func rotate_vector2i(point: Vector2i, direction: String) -> Vector2i:
	match direction:
		"down":
			return point
		"right":
			return Vector2i(point.y, -point.x)
		"up":
			return Vector2i(-point.x, -point.y)
		"left":
			return Vector2i(-point.y, point.x)
	return point


static func rotate_polygon(points: PackedVector2Array, direction: String) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(rotate_point(point, direction))
	return result


static func rotated_ground_contact_polygons(
	definition: Dictionary,
	direction: String
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not DIRECTIONS.has(direction):
		return result
	var ground_contact := definition.get("ground_contact", {}) as Dictionary
	if ground_contact.has("polygons_by_direction_px"):
		var directional_value: Variant = ground_contact.get(
			"polygons_by_direction_px"
		)
		if not directional_value is Dictionary:
			return result
		var directional := directional_value as Dictionary
		if not directional.has(direction):
			return result
		var polygons_value: Variant = directional.get(direction)
		if not polygons_value is Array:
			return result
		for polygon_value in polygons_value as Array:
			if not polygon_value is Array:
				return []
			result.append(_value_to_polygon(polygon_value))
		return result
	for polygon_value in ground_contact.get("polygons_px", []) as Array:
		result.append(rotate_polygon(_value_to_polygon(polygon_value), direction))
	return result


static func rotated_occlusion_polygon(
	definition: Dictionary,
	direction: String
) -> PackedVector2Array:
	if not DIRECTIONS.has(direction):
		return PackedVector2Array()
	var occlusion := definition.get("occlusion_polygon", {}) as Dictionary
	if occlusion.has("points_by_direction_px"):
		var directional_value: Variant = occlusion.get("points_by_direction_px")
		if not directional_value is Dictionary:
			return PackedVector2Array()
		var points_by_direction := directional_value as Dictionary
		if points_by_direction.has(direction):
			return _value_to_polygon(points_by_direction.get(direction))
		return PackedVector2Array()
	return rotate_polygon(_value_to_polygon(occlusion.get("points_px", [])), direction)


static func ground_contact_collision_shapes(
	definition: Dictionary,
	direction: String
) -> Array[ConvexPolygonShape2D]:
	var result: Array[ConvexPolygonShape2D] = []
	for polygon in rotated_ground_contact_polygons(definition, direction):
		for convex_polygon in Geometry2D.decompose_polygon_in_convex(polygon):
			if convex_polygon.size() < 3:
				continue
			var shape := ConvexPolygonShape2D.new()
			shape.points = convex_polygon
			result.append(shape)
	return result


static func baked_canonical_occupied_cells(definition: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var polygons := rotated_ground_contact_polygons(definition, "down")
	if polygons.is_empty():
		return result
	var occupied := definition.get("occupied_cells", {}) as Dictionary
	var origin2 := _pair_to_vector2i(occupied.get("origin2", []))
	var scan_rect := _occupied_cell_scan_rect(polygons, origin2)
	if not _occupied_cell_scan_is_supported(scan_rect):
		return result
	var origin_px := Vector2(origin2) * HALF_CELL_SIZE_PX
	for cell_y in range(scan_rect.position.y, scan_rect.end.y):
		for cell_x in range(scan_rect.position.x, scan_rect.end.x):
			var cell := Vector2i(cell_x, cell_y)
			var rect_position := origin_px + Vector2(cell) * CELL_SIZE_PX
			var cell_polygon := PackedVector2Array([
				rect_position,
				rect_position + Vector2(CELL_SIZE_PX, 0.0),
				rect_position + Vector2(CELL_SIZE_PX, CELL_SIZE_PX),
				rect_position + Vector2(0.0, CELL_SIZE_PX),
			])
			if _polygons_overlap_positive_area(polygons, cell_polygon):
				result.append(cell)
	return result


static func occupied_cells_match_ground_contact(definition: Dictionary) -> bool:
	var expected := {}
	for cell in baked_canonical_occupied_cells(definition):
		expected["%d,%d" % [cell.x, cell.y]] = true
	var actual := {}
	var occupied := definition.get("occupied_cells", {}) as Dictionary
	for value in occupied.get("cells", []) as Array:
		var cell := _pair_to_vector2i(value)
		actual["%d,%d" % [cell.x, cell.y]] = true
	return expected == actual


static func is_foot_inside_occlusion(
	definition: Dictionary,
	direction: String,
	local_foot_point: Vector2
) -> bool:
	var polygon := rotated_occlusion_polygon(definition, direction)
	return (
		polygon.size() >= 3
		and Geometry2D.is_point_in_polygon(local_foot_point, polygon)
	)


static func rotate_facing(facing: String, direction: String) -> String:
	var vector_by_name := {
		"down": Vector2i.DOWN,
		"right": Vector2i.RIGHT,
		"up": Vector2i.UP,
		"left": Vector2i.LEFT,
	}
	var name_by_vector := {
		Vector2i.DOWN: "down",
		Vector2i.RIGHT: "right",
		Vector2i.UP: "up",
		Vector2i.LEFT: "left",
	}
	if not vector_by_name.has(facing):
		return facing
	return String(name_by_vector.get(
		rotate_vector2i(vector_by_name[facing] as Vector2i, direction),
		facing
	))


static func occupied_cell_rects(definition: Dictionary, direction: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var occupied := definition.get("occupied_cells", {}) as Dictionary
	var origin2 := _pair_to_vector2i(occupied.get("origin2", []))
	for value in occupied.get("cells", []) as Array:
		var cell := _pair_to_vector2i(value)
		var top_left2 := origin2 + cell * 2
		var corners2 := [
			top_left2,
			top_left2 + Vector2i(2, 0),
			top_left2 + Vector2i(2, 2),
			top_left2 + Vector2i(0, 2),
		]
		var rotated := PackedVector2Array()
		for corner2 in corners2:
			rotated.append(Vector2(rotate_vector2i(corner2, direction)) * HALF_CELL_SIZE_PX)
		var bounds := _polygon_bounds(rotated)
		result.append(Rect2(bounds.position, Vector2(CELL_SIZE_PX, CELL_SIZE_PX)))
	return result


static func occupied_bounds(definition: Dictionary, direction: String) -> Rect2:
	var rects := occupied_cell_rects(definition, direction)
	if rects.is_empty():
		return Rect2()
	var result := rects[0]
	for index in range(1, rects.size()):
		result = result.merge(rects[index])
	return result


static func rotated_interaction_anchors(definition: Dictionary, direction: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in definition.get("interaction_anchor", []) as Array:
		var source := (value as Dictionary).duplicate(true)
		source["position_px"] = _vector_to_pair(rotate_point(
			_pair_to_vector2(source.get("position_px", [])),
			direction
		))
		source["actor_facing"] = rotate_facing(
			String(source.get("actor_facing", "")),
			direction
		)
		result.append(source)
	return result


static func validate_definition(
	definition: Dictionary,
	expected_room_id: String = "",
	expected_asset_id: String = "",
) -> PackedStringArray:
	var errors := PackedStringArray()
	for key_value: Variant in definition.keys():
		if (
			typeof(key_value) != TYPE_STRING
			or not PUBLIC_ASSET_FIELDS.has(key_value)
		):
			errors.append("asset definition contains an unknown field")
	for required_field in REQUIRED_PUBLIC_ASSET_FIELDS:
		if not definition.has(required_field):
			errors.append("asset definition is missing %s" % required_field)
	for text_field in ["asset_id", "label", "room_id", "source_revision"]:
		var text_value: Variant = definition.get(text_field)
		if (
			typeof(text_value) != TYPE_STRING
			or (text_value as String).strip_edges().is_empty()
		):
			errors.append("%s must be a non-empty string" % text_field)
	if (
		not expected_asset_id.is_empty()
		and definition.get("asset_id") != expected_asset_id
	):
		errors.append("asset_id must match the manifest asset_id")
	if (
		not expected_room_id.is_empty()
		and definition.get("room_id") != expected_room_id
	):
		errors.append("room_id must match the current room")
	if not _is_exact_integer(definition.get("schema_version"), 2):
		errors.append("schema_version must be 2")
	if (
		typeof(definition.get("projection_revision")) != TYPE_STRING
		or definition.get("projection_revision") != "interior_projection_v1"
	):
		errors.append("projection_revision must be interior_projection_v1")
	if not _is_exact_integer(definition.get("pixel_cluster_size"), 3):
		errors.append("pixel_cluster_size must be 3")
	if (
		typeof(definition.get("canonical_direction")) != TYPE_STRING
		or definition.get("canonical_direction") != "down"
	):
		errors.append("canonical_direction must be down")
	var policy_value: Variant = definition.get("direction_visual_policy")
	if (
		typeof(policy_value) != TYPE_STRING
		or not DIRECTION_VISUAL_POLICIES.has(policy_value)
	):
		errors.append("direction_visual_policy must use the closed policy set")
	if definition.has("direction_visual_policy_revision"):
		var policy_revision: Variant = definition.get("direction_visual_policy_revision")
		if (
			typeof(policy_revision) != TYPE_STRING
			or policy_revision != DIRECTION_VISUAL_POLICY_REVISION
		):
			errors.append(
				"direction_visual_policy_revision must be %s"
				% DIRECTION_VISUAL_POLICY_REVISION
			)
	errors.append_array(_validate_physical_size(definition.get("physical_size_px")))
	if not definition.get("provenance") is Dictionary:
		errors.append("provenance must be an object")
	errors.append_array(_validate_direction_pair_map(
		definition.get("visual_anchor"),
		"visual_anchor",
	))
	errors.append_array(_validate_direction_resource_map(
		definition.get("visual_sprite"),
		"visual_sprite",
	))
	errors.append_array(_validate_ground_contact(definition.get("ground_contact")))
	var ground_contact_value: Variant = definition.get("ground_contact")
	if (
		DIRECTIONAL_GROUND_CONTACT_ROOMS.has(expected_room_id)
		and (
			not ground_contact_value is Dictionary
			or not (ground_contact_value as Dictionary).has(
				"polygons_by_direction_px"
			)
		)
	):
		errors.append(
			"ground_contact.polygons_by_direction_px is required"
		)
	errors.append_array(_validate_directional_ground_contact_sprite_overlap(
		definition.get("visual_sprite"),
		definition.get("visual_anchor"),
		definition.get("ground_contact"),
	))
	errors.append_array(_validate_occlusion(definition.get("occlusion_polygon")))
	errors.append_array(_validate_directional_occlusion_sprite_overlap(
		definition.get("visual_sprite"),
		definition.get("visual_anchor"),
		definition.get("occlusion_polygon"),
	))
	errors.append_array(_validate_occupied_cells(definition.get("occupied_cells")))
	errors.append_array(_validate_interaction_anchors(
		definition.get("interaction_anchor")
	))
	errors.append_array(_validate_visual_effect_anchors(
		definition.get("visual_effect_anchor", [])
	))
	if errors.is_empty():
		if not _ground_contact_bake_is_supported(definition):
			errors.append("ground_contact exceeds the supported occupied-cell scan")
		elif not occupied_cells_match_ground_contact(definition):
			errors.append("occupied_cells must exactly bake ground_contact")
		var down_bounds := occupied_bounds(definition, "down")
		var right_bounds := occupied_bounds(definition, "right")
		var up_bounds := occupied_bounds(definition, "up")
		var left_bounds := occupied_bounds(definition, "left")
		if not is_equal_approx(down_bounds.size.x, right_bounds.size.y):
			errors.append("right occupied height must equal down occupied width")
		if not is_equal_approx(down_bounds.size.y, right_bounds.size.x):
			errors.append("right occupied width must equal down occupied height")
		if down_bounds.size != up_bounds.size:
			errors.append("up occupied bounds must equal down occupied bounds")
		if right_bounds.size != left_bounds.size:
			errors.append("left occupied bounds must equal right occupied bounds")
	return errors


static func _validate_physical_size(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("physical_size_px must be an object")
		return errors
	var physical_size := value as Dictionary
	var keys := physical_size.keys()
	keys.sort()
	if keys != ["depth", "height", "width"]:
		errors.append("physical_size_px fields must match the closed schema")
	for field in ["width", "depth", "height"]:
		var dimension: Variant = physical_size.get(field)
		if (
			not _is_integer_number(dimension)
			or float(dimension) <= 0.0
			or float(dimension) > MAX_SUPPORTED_GEOMETRY_COORDINATE_PX
		):
			errors.append(
				"physical_size_px.%s must be a supported positive integer"
				% field
			)
	return errors


static func _validate_direction_pair_map(
	value: Variant,
	label: String,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("%s must be an object" % label)
		return errors
	var direction_map := value as Dictionary
	for key_value: Variant in direction_map.keys():
		if typeof(key_value) != TYPE_STRING or not DIRECTIONS.has(key_value):
			errors.append("%s contains an unknown direction" % label)
	for direction in DIRECTIONS:
		if not direction_map.has(direction):
			errors.append("%s is missing %s" % [label, direction])
			continue
		errors.append_array(_validate_number_pair(
			direction_map.get(direction),
			"%s.%s" % [label, direction],
			false,
		))
	return errors


static func _validate_direction_resource_map(
	value: Variant,
	label: String,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("%s must be an object" % label)
		return errors
	var direction_map := value as Dictionary
	for key_value: Variant in direction_map.keys():
		if typeof(key_value) != TYPE_STRING or not DIRECTIONS.has(key_value):
			errors.append("%s contains an unknown direction" % label)
	for direction in DIRECTIONS:
		if not direction_map.has(direction):
			errors.append("%s is missing %s" % [label, direction])
			continue
		var resource_value: Variant = direction_map.get(direction)
		if (
			typeof(resource_value) != TYPE_STRING
			or (resource_value as String).is_empty()
			or not (resource_value as String).begins_with("res://")
		):
			errors.append("%s.%s must be a res:// resource path" % [label, direction])
		elif not _resource_exists(resource_value):
			errors.append("%s.%s resource does not exist" % [label, direction])
	return errors


static func _validate_ground_contact(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("ground_contact must be an object")
		return errors
	var ground_contact := value as Dictionary
	var keys := ground_contact.keys()
	keys.sort()
	if (
		keys != ["polygons_px"]
		and keys != ["polygons_by_direction_px", "polygons_px"]
	):
		errors.append("ground_contact fields must match the closed schema")
	var polygons_value: Variant = ground_contact.get("polygons_px")
	if not polygons_value is Array:
		errors.append("ground_contact.polygons_px must be an array")
		return errors
	var polygons := polygons_value as Array
	if polygons.size() != 1:
		errors.append("ground_contact.polygons_px must contain exactly one polygon")
	for index in range(polygons.size()):
		errors.append_array(_validate_polygon(
			polygons[index],
			"ground_contact.polygons_px[%d]" % index,
		))
	if not ground_contact.has("polygons_by_direction_px"):
		return errors
	var directional_value: Variant = ground_contact.get(
		"polygons_by_direction_px"
	)
	if not directional_value is Dictionary:
		errors.append(
			"ground_contact.polygons_by_direction_px must be an object"
		)
		return errors
	var directional := directional_value as Dictionary
	for key_value: Variant in directional.keys():
		if typeof(key_value) != TYPE_STRING or not DIRECTIONS.has(key_value):
			errors.append(
				"ground_contact direction map contains an unknown direction"
			)
	for direction in DIRECTIONS:
		if not directional.has(direction):
			errors.append(
				"ground_contact direction map is missing %s" % direction
			)
			continue
		var directional_polygons_value: Variant = directional.get(direction)
		if not directional_polygons_value is Array:
			errors.append(
				"ground_contact.polygons_by_direction_px.%s must be an array"
				% direction
			)
			continue
		var directional_polygons := directional_polygons_value as Array
		if directional_polygons.size() != 1:
			errors.append(
				"ground_contact.polygons_by_direction_px.%s must contain exactly one polygon"
				% direction
			)
		for index in range(directional_polygons.size()):
			errors.append_array(_validate_polygon(
				directional_polygons[index],
				"ground_contact.polygons_by_direction_px.%s[%d]"
				% [direction, index],
			))
	if directional.has("down") and directional.get("down") != polygons:
		errors.append(
			"ground_contact down direction must match polygons_px"
		)
	return errors


static func _validate_directional_ground_contact_sprite_overlap(
	sprite_value: Variant,
	anchor_value: Variant,
	ground_contact_value: Variant,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if (
		not sprite_value is Dictionary
		or not anchor_value is Dictionary
		or not ground_contact_value is Dictionary
	):
		return errors
	var directional_value: Variant = (
		(ground_contact_value as Dictionary).get(
			"polygons_by_direction_px"
		)
	)
	if not directional_value is Dictionary:
		return errors
	var sprites := sprite_value as Dictionary
	var anchors := anchor_value as Dictionary
	var directional := directional_value as Dictionary
	for direction in DIRECTIONS:
		if (
			not sprites.has(direction)
			or not anchors.has(direction)
			or not directional.has(direction)
		):
			continue
		var sprite_path: Variant = sprites.get(direction)
		var anchor_errors := _validate_number_pair(
			anchors.get(direction),
			"visual_anchor.%s" % direction,
			false,
		)
		var polygons_value: Variant = directional.get(direction)
		if (
			typeof(sprite_path) != TYPE_STRING
			or not _resource_exists(sprite_path)
			or not anchor_errors.is_empty()
			or not polygons_value is Array
		):
			continue
		var anchor := _pair_to_vector2(anchors.get(direction))
		for index in range((polygons_value as Array).size()):
			var polygon_value: Variant = (polygons_value as Array)[index]
			if not polygon_value is Array:
				continue
			var polygon_errors := _validate_polygon(
				polygon_value,
				"ground_contact.polygons_by_direction_px.%s[%d]"
				% [direction, index],
			)
			if not polygon_errors.is_empty():
				continue
			var polygon := _value_to_polygon(polygon_value)
			if not _ground_polygon_overlaps_visible_sprite(
				sprite_path,
				anchor,
				polygon,
			):
				errors.append(
					(
						"ground_contact.polygons_by_direction_px.%s[%d] "
						+ "must overlap visible sprite pixels"
					)
					% [direction, index]
				)
	return errors


static func _ground_polygon_overlaps_visible_sprite(
	sprite_path: String,
	anchor: Vector2,
	polygon: PackedVector2Array,
) -> bool:
	var serialized_points := []
	for point in polygon:
		serialized_points.append([point.x, point.y])
	var cache_key := JSON.stringify([
		sprite_path,
		anchor.x,
		anchor.y,
		serialized_points,
	])
	if _visible_ground_overlap_cache.has(cache_key):
		return bool(_visible_ground_overlap_cache.get(cache_key))
	var image := _load_png_source_image(sprite_path)
	if image == null:
		_visible_ground_overlap_cache[cache_key] = false
		return false
	var used_rect := image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		_visible_ground_overlap_cache[cache_key] = false
		return false
	var polygon_bounds := _polygon_bounds(polygon)
	var scan_start := Vector2i(
		floori(polygon_bounds.position.x + anchor.x),
		floori(polygon_bounds.position.y + anchor.y),
	)
	var scan_end := Vector2i(
		ceili(polygon_bounds.end.x + anchor.x),
		ceili(polygon_bounds.end.y + anchor.y),
	)
	var scan_rect := Rect2i(scan_start, scan_end - scan_start).intersection(
		used_rect
	)
	for y in range(scan_rect.position.y, scan_rect.end.y):
		for x in range(scan_rect.position.x, scan_rect.end.x):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var local_pixel_center := (
				Vector2(float(x) + 0.5, float(y) + 0.5)
				- anchor
			)
			if Geometry2D.is_point_in_polygon(local_pixel_center, polygon):
				_visible_ground_overlap_cache[cache_key] = true
				return true
	_visible_ground_overlap_cache[cache_key] = false
	return false


static func _validate_occlusion(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("occlusion_polygon must be an object")
		return errors
	var occlusion := value as Dictionary
	var keys := occlusion.keys()
	keys.sort()
	if keys != ["points_by_direction_px", "points_px"]:
		errors.append("occlusion_polygon fields must match the closed schema")
	errors.append_array(_validate_polygon(
		occlusion.get("points_px"),
		"occlusion_polygon.points_px",
	))
	var directional_value: Variant = occlusion.get("points_by_direction_px")
	if not directional_value is Dictionary:
		errors.append("occlusion_polygon.points_by_direction_px must be an object")
		return errors
	var directional := directional_value as Dictionary
	for key_value: Variant in directional.keys():
		if typeof(key_value) != TYPE_STRING or not DIRECTIONS.has(key_value):
			errors.append("occlusion direction map contains an unknown direction")
	for direction in DIRECTIONS:
		if not directional.has(direction):
			errors.append("occlusion direction map is missing %s" % direction)
			continue
		errors.append_array(_validate_polygon(
			directional.get(direction),
			"occlusion_polygon.points_by_direction_px.%s" % direction,
		))
	return errors


static func _validate_directional_occlusion_sprite_overlap(
	sprite_value: Variant,
	anchor_value: Variant,
	occlusion_value: Variant,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if (
		not sprite_value is Dictionary
		or not anchor_value is Dictionary
		or not occlusion_value is Dictionary
	):
		return errors
	var directional_value: Variant = (
		(occlusion_value as Dictionary).get("points_by_direction_px")
	)
	if not directional_value is Dictionary:
		return errors
	var sprites := sprite_value as Dictionary
	var anchors := anchor_value as Dictionary
	var directional := directional_value as Dictionary
	for direction in DIRECTIONS:
		if (
			not sprites.has(direction)
			or not anchors.has(direction)
			or not directional.has(direction)
		):
			continue
		var sprite_path: Variant = sprites.get(direction)
		var anchor_errors := _validate_number_pair(
			anchors.get(direction),
			"visual_anchor.%s" % direction,
			false,
		)
		var polygon_errors := _validate_polygon(
			directional.get(direction),
			"occlusion_polygon.points_by_direction_px.%s" % direction,
		)
		if (
			typeof(sprite_path) != TYPE_STRING
			or not _resource_exists(sprite_path)
			or not anchor_errors.is_empty()
			or not polygon_errors.is_empty()
		):
			continue
		var image := _load_png_source_image(sprite_path)
		if image == null:
			errors.append("visual_sprite.%s source image cannot be loaded" % direction)
			continue
		var used_rect := image.get_used_rect()
		if used_rect.size.x <= 0 or used_rect.size.y <= 0:
			errors.append("visual_sprite.%s image has no visible pixels" % direction)
			continue
		var polygon := _value_to_polygon(directional.get(direction))
		var anchor := _pair_to_vector2(anchors.get(direction))
		var overlaps_visible_pixel := false
		for y in range(used_rect.position.y, used_rect.end.y):
			for x in range(used_rect.position.x, used_rect.end.x):
				if image.get_pixel(x, y).a <= 0.0:
					continue
				var local_pixel_center := (
					Vector2(float(x) + 0.5, float(y) + 0.5)
					- anchor
				)
				if Geometry2D.is_point_in_polygon(local_pixel_center, polygon):
					overlaps_visible_pixel = true
					break
			if overlaps_visible_pixel:
				break
		if not overlaps_visible_pixel:
			errors.append(
				"occlusion_polygon.points_by_direction_px.%s must overlap visible sprite pixels"
				% direction
			)
	return errors


static func _load_png_source_image(path: String) -> Image:
	if _source_image_cache.has(path):
		return _source_image_cache.get(path) as Image
	var file := FileAccess.open(path, FileAccess.READ)
	var image: Image = null
	if file != null:
		image = Image.new()
		if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
			image = null
	elif ResourceLoader.exists(path, "Texture2D"):
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture != null:
			image = texture.get_image()
	if image == null:
		_source_image_cache[path] = null
		return null
	if image.is_empty():
		_source_image_cache[path] = null
		return null
	_source_image_cache[path] = image
	return image


static func _resource_exists(path: Variant) -> bool:
	if typeof(path) != TYPE_STRING:
		return false
	var resource_path := String(path)
	return (
		ResourceLoader.exists(resource_path)
		or FileAccess.file_exists(resource_path)
	)


static func _validate_occupied_cells(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("occupied_cells must be an object")
		return errors
	var occupied := value as Dictionary
	var keys := occupied.keys()
	keys.sort()
	if keys != ["cells", "origin2"]:
		errors.append("occupied_cells fields must match the closed schema")
	errors.append_array(_validate_number_pair(
		occupied.get("origin2"),
		"occupied_cells.origin2",
		true,
	))
	var cells_value: Variant = occupied.get("cells")
	if not cells_value is Array:
		errors.append("occupied_cells.cells must be an array")
		return errors
	if cells_value.is_empty():
		errors.append("occupied_cells.cells must not be empty")
	var seen := {}
	for index in range(cells_value.size()):
		var cell_errors := _validate_number_pair(
			cells_value[index],
			"occupied_cells.cells[%d]" % index,
			true,
		)
		errors.append_array(cell_errors)
		if cell_errors.is_empty():
			var cell := cells_value[index] as Array
			var key := "%d,%d" % [cell[0], cell[1]]
			if seen.has(key):
				errors.append("occupied_cells.cells contains duplicate %s" % key)
			seen[key] = true
	return errors


static func _validate_interaction_anchors(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Array:
		errors.append("interaction_anchor must be an array")
		return errors
	var seen := {}
	for index in range(value.size()):
		var anchor_value: Variant = value[index]
		if not anchor_value is Dictionary:
			errors.append("interaction_anchor[%d] must be an object" % index)
			continue
		var anchor := anchor_value as Dictionary
		var keys := anchor.keys()
		keys.sort()
		if keys != ["actor_facing", "capacity", "id", "kind", "position_px"]:
			errors.append("interaction_anchor[%d] fields must match the closed schema" % index)
		var id_value: Variant = anchor.get("id")
		if (
			typeof(id_value) != TYPE_STRING
			or (id_value as String).strip_edges().is_empty()
		):
			errors.append("interaction_anchor[%d].id must be a non-empty string" % index)
		elif seen.has(id_value):
			errors.append("interaction_anchor id must be unique")
		else:
			seen[id_value] = true
		var kind_value: Variant = anchor.get("kind")
		if (
			typeof(kind_value) != TYPE_STRING
			or (kind_value as String).strip_edges().is_empty()
		):
			errors.append("interaction_anchor[%d].kind must be a non-empty string" % index)
		var facing_value: Variant = anchor.get("actor_facing")
		if typeof(facing_value) != TYPE_STRING or not DIRECTIONS.has(facing_value):
			errors.append("interaction_anchor[%d].actor_facing is invalid" % index)
		var capacity_value: Variant = anchor.get("capacity")
		if not _is_integer_number(capacity_value) or float(capacity_value) <= 0.0:
			errors.append("interaction_anchor[%d].capacity must be a positive integer" % index)
		errors.append_array(_validate_number_pair(
			anchor.get("position_px"),
			"interaction_anchor[%d].position_px" % index,
			false,
		))
	return errors


static func _validate_visual_effect_anchors(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Array:
		errors.append("visual_effect_anchor must be an array")
		return errors
	var seen := {}
	for index in range(value.size()):
		var effect_value: Variant = value[index]
		if not effect_value is Dictionary:
			errors.append("visual_effect_anchor[%d] must be an object" % index)
			continue
		var effect := effect_value as Dictionary
		var keys := effect.keys()
		keys.sort()
		if keys != [
			"color",
			"energy",
			"id",
			"kind",
			"position_px",
			"radius_px",
			"rotate_with_direction",
		]:
			errors.append("visual_effect_anchor[%d] fields must match the closed schema" % index)
		var id_value: Variant = effect.get("id")
		if (
			typeof(id_value) != TYPE_STRING
			or (id_value as String).strip_edges().is_empty()
		):
			errors.append("visual_effect_anchor[%d].id must be a non-empty string" % index)
		elif seen.has(id_value):
			errors.append("visual_effect_anchor id must be unique")
		else:
			seen[id_value] = true
		if effect.get("kind") != "warm_light":
			errors.append("visual_effect_anchor[%d].kind must be warm_light" % index)
		errors.append_array(_validate_number_pair(
			effect.get("position_px"),
			"visual_effect_anchor[%d].position_px" % index,
			false,
		))
		if typeof(effect.get("rotate_with_direction")) != TYPE_BOOL:
			errors.append("visual_effect_anchor[%d].rotate_with_direction must be bool" % index)
		for number_field in ["radius_px", "energy"]:
			var number_value: Variant = effect.get(number_field)
			if not _is_number(number_value) or float(number_value) <= 0.0:
				errors.append(
					"visual_effect_anchor[%d].%s must be finite and positive"
					% [index, number_field]
				)
		if not _is_hex_color(effect.get("color")):
			errors.append("visual_effect_anchor[%d].color must be #RRGGBB" % index)
	return errors


static func _validate_polygon(value: Variant, label: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Array:
		errors.append("%s must be an array" % label)
		return errors
	var values := value as Array
	if values.size() < 3:
		errors.append("%s must contain at least three points" % label)
		return errors
	if values.size() > MAX_ASSET_POLYGON_POINTS:
		errors.append("%s exceeds the supported point limit" % label)
		return errors
	var polygon := PackedVector2Array()
	for index in range(values.size()):
		var point_errors := _validate_number_pair(
			values[index],
			"%s[%d]" % [label, index],
			false,
		)
		errors.append_array(point_errors)
		if point_errors.is_empty():
			polygon.append(_pair_to_vector2(values[index]))
	if errors.is_empty() and (
		_polygon_area(polygon) <= GEOMETRY_EPSILON
		or Geometry2D.triangulate_polygon(polygon).is_empty()
		or _polygon_has_self_intersection(polygon)
	):
		errors.append("%s must be a finite, simple polygon with positive area" % label)
	return errors


static func _validate_number_pair(
	value: Variant,
	label: String,
	require_integers: bool,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Array or value.size() != 2:
		errors.append("%s must contain exactly two numbers" % label)
		return errors
	for coordinate: Variant in value as Array:
		if (
			(require_integers and not _is_integer_number(coordinate))
			or (
				not require_integers
				and not _is_supported_geometry_coordinate(coordinate)
			)
			or (
				require_integers
				and absf(float(coordinate)) > MAX_SUPPORTED_GEOMETRY_COORDINATE_PX
			)
		):
			errors.append(
				"%s coordinates must be %s"
				% [label, "integers" if require_integers else "finite numbers"]
			)
			break
	return errors


static func _is_number(value: Variant) -> bool:
	return WORLD_SCALARS.is_number(value)


static func _is_integer_number(value: Variant) -> bool:
	return _is_number(value) and float(value) == floorf(float(value))


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	return _is_integer_number(value) and float(value) == float(expected)


static func _is_supported_geometry_coordinate(value: Variant) -> bool:
	return (
		_is_number(value)
		and absf(float(value)) <= MAX_SUPPORTED_GEOMETRY_COORDINATE_PX
	)


static func _is_hex_color(value: Variant) -> bool:
	if (
		typeof(value) != TYPE_STRING
		or (value as String).length() != 7
		or not (value as String).begins_with("#")
	):
		return false
	for index in range(1, (value as String).length()):
		if not "0123456789abcdefABCDEF".contains((value as String)[index]):
			return false
	return true


static func _polygons_overlap_positive_area(
	polygons: Array[PackedVector2Array],
	cell_polygon: PackedVector2Array
) -> bool:
	for polygon in polygons:
		for intersection in Geometry2D.intersect_polygons(polygon, cell_polygon):
			if _polygon_area(intersection) > 0.01:
				return true
	return false


static func _ground_contact_bake_is_supported(definition: Dictionary) -> bool:
	var occupied := definition.get("occupied_cells", {}) as Dictionary
	var origin2 := _pair_to_vector2i(occupied.get("origin2", []))
	var ground_contact := definition.get("ground_contact", {}) as Dictionary
	var base_polygons: Array[PackedVector2Array] = []
	for polygon_value in ground_contact.get("polygons_px", []) as Array:
		base_polygons.append(_value_to_polygon(polygon_value))
	if (
		base_polygons.is_empty()
		or not _occupied_cell_scan_is_supported(
			_occupied_cell_scan_rect(base_polygons, origin2)
		)
	):
		return false
	for direction in DIRECTIONS:
		var polygons := rotated_ground_contact_polygons(
			definition,
			direction,
		)
		if (
			polygons.is_empty()
			or not _occupied_cell_scan_is_supported(
				_occupied_cell_scan_rect(polygons, origin2)
			)
		):
			return false
	return true


static func _occupied_cell_scan_rect(
	polygons: Array[PackedVector2Array],
	origin2: Vector2i,
) -> Rect2i:
	if polygons.is_empty():
		return Rect2i()
	var combined_bounds := _polygon_bounds(polygons[0])
	for index in range(1, polygons.size()):
		combined_bounds = combined_bounds.merge(_polygon_bounds(polygons[index]))
	var origin_px := Vector2(origin2) * HALF_CELL_SIZE_PX
	var first_cell := Vector2i(
		floori((combined_bounds.position.x - origin_px.x) / CELL_SIZE_PX),
		floori((combined_bounds.position.y - origin_px.y) / CELL_SIZE_PX),
	)
	var last_cell := Vector2i(
		ceili((combined_bounds.end.x - origin_px.x) / CELL_SIZE_PX) - 1,
		ceili((combined_bounds.end.y - origin_px.y) / CELL_SIZE_PX) - 1,
	)
	return Rect2i(first_cell, last_cell - first_cell + Vector2i.ONE)


static func _occupied_cell_scan_is_supported(scan_rect: Rect2i) -> bool:
	var width := scan_rect.size.x
	var height := scan_rect.size.y
	return (
		width > 0
		and height > 0
		and width <= MAX_BAKED_OCCUPIED_CELL_SCAN
		and height <= MAX_BAKED_OCCUPIED_CELL_SCAN
		and width <= MAX_BAKED_OCCUPIED_CELL_SCAN / height
	)


static func _polygon_area(points: PackedVector2Array) -> float:
	return WORLD_SCALARS.polygon_area(points)


static func _polygon_has_self_intersection(points: PackedVector2Array) -> bool:
	var edge_count := points.size()
	for first_index in range(edge_count):
		var first_start := points[first_index]
		var first_end := points[(first_index + 1) % edge_count]
		if first_start == first_end:
			return true
		for second_index in range(first_index + 1, edge_count):
			if (
				(first_index + 1) % edge_count == second_index
				or (second_index + 1) % edge_count == first_index
			):
				continue
			if _closed_segments_intersect(
				first_start,
				first_end,
				points[second_index],
				points[(second_index + 1) % edge_count],
			):
				return true
	return false


static func _closed_segments_intersect(
	first_start: Vector2,
	first_end: Vector2,
	second_start: Vector2,
	second_end: Vector2,
) -> bool:
	var first_side_a := _orientation(first_start, first_end, second_start)
	var first_side_b := _orientation(first_start, first_end, second_end)
	var second_side_a := _orientation(second_start, second_end, first_start)
	var second_side_b := _orientation(second_start, second_end, first_end)
	if (
		((first_side_a > 0.0 and first_side_b < 0.0)
		or (first_side_a < 0.0 and first_side_b > 0.0))
		and ((second_side_a > 0.0 and second_side_b < 0.0)
		or (second_side_a < 0.0 and second_side_b > 0.0))
	):
		return true
	if first_side_a == 0.0 and _point_on_closed_segment(
		second_start,
		first_start,
		first_end,
	):
		return true
	if first_side_b == 0.0 and _point_on_closed_segment(
		second_end,
		first_start,
		first_end,
	):
		return true
	if second_side_a == 0.0 and _point_on_closed_segment(
		first_start,
		second_start,
		second_end,
	):
		return true
	if second_side_b == 0.0 and _point_on_closed_segment(
		first_end,
		second_start,
		second_end,
	):
		return true
	return false


static func _orientation(start: Vector2, end: Vector2, point: Vector2) -> float:
	var value := (end - start).cross(point - start)
	if absf(value) <= GEOMETRY_EPSILON:
		return 0.0
	return value


static func _point_on_closed_segment(
	point: Vector2,
	start: Vector2,
	end: Vector2,
) -> bool:
	return (
		point.x >= minf(start.x, end.x) - GEOMETRY_EPSILON
		and point.x <= maxf(start.x, end.x) + GEOMETRY_EPSILON
		and point.y >= minf(start.y, end.y) - GEOMETRY_EPSILON
		and point.y <= maxf(start.y, end.y) + GEOMETRY_EPSILON
	)


static func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


static func _pair_to_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _pair_to_vector2i(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


static func _value_to_polygon(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if value is not Array:
		return result
	for point_value in value as Array:
		if point_value is Array and point_value.size() == 2:
			result.append(_pair_to_vector2(point_value))
	return result


static func _vector_to_pair(value: Vector2) -> Array:
	return [value.x, value.y]
