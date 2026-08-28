# 重制室内的运行时几何读取器。
# 地板格是导航与边界的唯一来源；门槛朝外的五格必须保持为真实开口。
extends RefCounted

const GRID_SIZE := 32.0
const PROJECTION_REVISION := "interior_projection_v1"
const MAX_GEOMETRY_FILE_BYTES := 8 * 1024 * 1024
const MAX_FLOOR_CELLS := 65_536
const MAX_FLOOR_POLYGONS := 4_096
const MAX_FLOOR_POLYGON_POINTS := 65_536
const MAX_POLYGON_POINTS := 4_096
const MAX_FUNCTIONAL_ANCHORS := 4_096
const MAX_NAVIGATION_GRID_CELLS := 262_144
const MAX_FLOOR_POLYGON_RASTER_CELLS := MAX_NAVIGATION_GRID_CELLS * 4
const MAX_POLYGON_INTERSECTION_CHECKS := 1_000_000
const MAX_DOORWAYS := 64
const MAX_DOORWAY_CELLS := 64
const MAX_CANONICAL_TEXT_LENGTH := 256
const MAX_INTEGRAL_COMPONENT := 1_000_000.0
const MAX_POINT_COMPONENT := MAX_INTEGRAL_COMPONENT * GRID_SIZE
const MAX_INCREMENTAL_WORK_ITEMS := 16
const GEOMETRY_KEYS := {
	"schema_version": true,
	"source_revision": true,
	"projection_revision": true,
	"room_id": true,
	"cell_size_px": true,
	"background_sprite": true,
	"canvas_size_px": true,
	"world_origin_px": true,
	"floor_polygon": true,
	"floor_cells": true,
	"doorway": true,
	"functional_anchor": true,
}
const DOORWAY_KEYS := {
	"id": true,
	"threshold_cells": true,
	"entry_anchor_px": true,
	"clear_width_cells": true,
}
const FUNCTIONAL_ANCHOR_KEYS := {
	"id": true,
	"position_px": true,
	"required_access": true,
}
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.UP,
]


static func load_geometry(path_value: Variant) -> Dictionary:
	if not _is_canonical_text(path_value):
		return {}
	var path := path_value as String
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Interior room geometry cannot be opened: %s" % path)
		return {}
	if file.get_length() > MAX_GEOMETRY_FILE_BYTES:
		push_error("Interior room geometry is too large: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var validation_errors := validate_geometry(parsed)
	if not validation_errors.is_empty():
		push_error(
			"Interior room geometry is invalid (%s): %s"
			% [path, "; ".join(validation_errors)]
		)
		return {}
	return (parsed as Dictionary).duplicate(true)


static func validate_geometry(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("document must be an object")
		return errors
	var geometry := value as Dictionary
	_validate_exact_keys(geometry, GEOMETRY_KEYS, "document", errors)

	if not _is_integer_number(geometry.get("schema_version")):
		errors.append("schema_version must be an integer")
	elif int(geometry["schema_version"]) != 2:
		errors.append("schema_version must equal 2")

	if not _is_integer_number(geometry.get("cell_size_px")):
		errors.append("cell_size_px must be an integer")
	elif int(geometry["cell_size_px"]) != int(GRID_SIZE):
		errors.append("cell_size_px must equal 32")

	if not _is_canonical_text(geometry.get("room_id")):
		errors.append("room_id must be canonical non-empty text")
	if not _is_canonical_text(geometry.get("source_revision")):
		errors.append("source_revision must be canonical non-empty text")
	if (
		typeof(geometry.get("projection_revision")) != TYPE_STRING
		or geometry.get("projection_revision") != PROJECTION_REVISION
	):
		errors.append("projection_revision must equal %s" % PROJECTION_REVISION)
	if not _is_canonical_relative_path(geometry.get("background_sprite")):
		errors.append("background_sprite must be a canonical relative path")
	if not _is_positive_integral_point(geometry.get("canvas_size_px")):
		errors.append("canvas_size_px must contain two positive integers")
	if not _is_integral_point(geometry.get("world_origin_px")):
		errors.append("world_origin_px must contain two integers")

	var floor_cells_value: Variant = geometry.get("floor_cells")
	if not floor_cells_value is Array:
		errors.append("floor_cells must be an array")
		return errors
	var floor_values := floor_cells_value as Array
	if floor_values.is_empty():
		errors.append("floor_cells must not be empty")
		return errors
	if floor_values.size() > MAX_FLOOR_CELLS:
		errors.append("floor_cells exceeds the supported limit")
		return errors

	var floor_cells: Array[Vector2i] = []
	var floor_lookup := {}
	for index in range(floor_values.size()):
		var cell_value: Variant = floor_values[index]
		if not _is_integral_point(cell_value):
			errors.append("floor_cells[%d] must contain exactly two integers" % index)
			continue
		var cell := _integral_cell(cell_value)
		if floor_lookup.has(cell):
			errors.append("floor_cells[%d] duplicates %s" % [index, str(cell)])
			continue
		floor_lookup[cell] = true
		floor_cells.append(cell)

	if floor_cells.size() == floor_values.size() and not _cells_are_connected(floor_cells):
		errors.append("floor_cells must form one cardinally connected region")
	if (
		floor_cells.size() == floor_values.size()
		and _cell_bounding_area(floor_cells) > MAX_NAVIGATION_GRID_CELLS
	):
		errors.append("floor_cells bounding grid exceeds the supported limit")
	if (
		floor_cells.size() == floor_values.size()
		and _is_positive_integral_point(geometry.get("canvas_size_px"))
		and _is_integral_point(geometry.get("world_origin_px"))
	):
		var canvas_size := _point(geometry["canvas_size_px"])
		var world_origin := _point(geometry["world_origin_px"])
		for cell in floor_cells:
			if not _cell_fits_shell(cell, canvas_size, world_origin):
				errors.append("floor cell %s is outside canvas bounds" % str(cell))
				break
	_validate_floor_polygons(
		geometry.get("floor_polygon"),
		geometry.get("canvas_size_px"),
		geometry.get("world_origin_px"),
		floor_cells,
		floor_lookup,
		(
			floor_cells.size() == floor_values.size()
			and _cell_bounding_area(floor_cells) <= MAX_NAVIGATION_GRID_CELLS
		),
		errors,
	)

	var doorway_value: Variant = geometry.get("doorway")
	if not doorway_value is Array:
		errors.append("doorway must be an array")
		return errors
	var doorway_list := doorway_value as Array
	if doorway_list.is_empty():
		errors.append("doorway must not be empty")
		return errors
	if doorway_list.size() > MAX_DOORWAYS:
		errors.append("doorway exceeds the supported limit")
		return errors

	var doorway_ids := {}
	var occupied_thresholds := {}
	for doorway_index in range(doorway_list.size()):
		var raw_doorway: Variant = doorway_list[doorway_index]
		if typeof(raw_doorway) != TYPE_DICTIONARY:
			errors.append("doorway[%d] must be an object" % doorway_index)
			continue
		var doorway := raw_doorway as Dictionary
		_validate_exact_keys(
			doorway,
			DOORWAY_KEYS,
			"doorway[%d]" % doorway_index,
			errors,
		)
		var doorway_id: Variant = doorway.get("id")
		if not _is_canonical_text(doorway_id):
			errors.append("doorway[%d].id must be canonical non-empty text" % doorway_index)
		elif doorway_ids.has(doorway_id):
			errors.append("doorway[%d].id duplicates %s" % [doorway_index, doorway_id])
		else:
			doorway_ids[doorway_id] = true

		var threshold_value: Variant = doorway.get("threshold_cells")
		if not threshold_value is Array:
			errors.append("doorway[%d].threshold_cells must be an array" % doorway_index)
			continue
		var threshold_values := threshold_value as Array
		if threshold_values.is_empty():
			errors.append("doorway[%d].threshold_cells must not be empty" % doorway_index)
			continue
		if threshold_values.size() > MAX_DOORWAY_CELLS:
			errors.append(
				"doorway[%d].threshold_cells exceeds the supported limit"
				% doorway_index
			)
			continue

		var threshold_cells: Array[Vector2i] = []
		var local_thresholds := {}
		for threshold_index in range(threshold_values.size()):
			var raw_cell: Variant = threshold_values[threshold_index]
			if not _is_integral_point(raw_cell):
				errors.append(
					"doorway[%d].threshold_cells[%d] must contain exactly two integers"
					% [doorway_index, threshold_index]
				)
				continue
			var threshold_cell := _integral_cell(raw_cell)
			if local_thresholds.has(threshold_cell):
				errors.append(
					"doorway[%d].threshold_cells[%d] duplicates %s"
					% [doorway_index, threshold_index, str(threshold_cell)]
				)
				continue
			if occupied_thresholds.has(threshold_cell):
				errors.append(
					"doorway[%d].threshold_cells overlaps another doorway at %s"
					% [doorway_index, str(threshold_cell)]
				)
			local_thresholds[threshold_cell] = true
			occupied_thresholds[threshold_cell] = true
			threshold_cells.append(threshold_cell)
			if not floor_lookup.has(threshold_cell):
				errors.append(
					"doorway[%d].threshold_cells[%d] is not walkable"
					% [doorway_index, threshold_index]
				)

		if threshold_cells.size() == threshold_values.size():
			if not _cells_form_straight_cardinal_run(threshold_cells):
				errors.append(
					"doorway[%d].threshold_cells must form one straight cardinal run"
					% doorway_index
				)
			var clear_width: Variant = doorway.get("clear_width_cells")
			if not _is_integer_number(clear_width) or int(clear_width) <= 0:
				errors.append(
					"doorway[%d].clear_width_cells must be a positive integer"
					% doorway_index
				)
			elif int(clear_width) != threshold_cells.size():
				errors.append(
					"doorway[%d].clear_width_cells must match threshold_cells"
					% doorway_index
				)

		var entry_anchor: Variant = doorway.get("entry_anchor_px")
		if not _is_finite_point(entry_anchor):
			errors.append(
				"doorway[%d].entry_anchor_px must contain exactly two finite numbers"
				% doorway_index
			)
		elif not floor_lookup.has(_local_position_to_cell_unchecked(_point(entry_anchor))):
			errors.append("doorway[%d].entry_anchor_px is not walkable" % doorway_index)

	_validate_functional_anchors(
		geometry.get("functional_anchor"),
		floor_lookup,
		errors,
	)
	return errors


static func get_walkable_cells(value: Variant) -> Array[Vector2i]:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return []
	return _get_walkable_cells_unchecked(geometry)


static func _get_walkable_cells_unchecked(geometry: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var lookup := {}
	var serialized_cells := _array_or_empty(geometry.get("floor_cells"))
	if serialized_cells.size() > MAX_FLOOR_CELLS:
		return cells
	for serialized_cell in serialized_cells:
		if not _is_integral_point(serialized_cell):
			continue
		var cell := _integral_cell(serialized_cell)
		if not lookup.has(cell):
			lookup[cell] = true
			cells.append(cell)
	_sort_cells(cells)
	return cells


static func get_walkable_lookup(value: Variant) -> Dictionary:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return {}
	return _get_walkable_lookup_unchecked(geometry)


static func _get_walkable_lookup_unchecked(geometry: Dictionary) -> Dictionary:
	var lookup := {}
	for cell in _get_walkable_cells_unchecked(geometry):
		lookup[cell] = true
	return lookup


static func is_cell_walkable(value: Variant, cell_value: Variant) -> bool:
	var geometry := _validated_geometry(value)
	if geometry.is_empty() or typeof(cell_value) != TYPE_VECTOR2I:
		return false
	return _get_walkable_lookup_unchecked(geometry).has(cell_value)


static func is_point_walkable(value: Variant, point_value: Variant) -> bool:
	var geometry := _validated_geometry(value)
	if geometry.is_empty() or not _is_finite_vector2(point_value):
		return false
	return _get_walkable_lookup_unchecked(geometry).has(
		_local_position_to_cell_unchecked(point_value as Vector2)
	)


static func cell_to_local_center(cell_value: Variant) -> Vector2:
	if typeof(cell_value) != TYPE_VECTOR2I:
		return Vector2.ZERO
	return _cell_to_local_center_unchecked(cell_value as Vector2i)


static func _cell_to_local_center_unchecked(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_SIZE


static func local_position_to_cell(position_value: Variant) -> Vector2i:
	if not _is_finite_vector2(position_value):
		return Vector2i.ZERO
	return _local_position_to_cell_unchecked(position_value as Vector2)


static func _local_position_to_cell_unchecked(local_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(local_position.x / GRID_SIZE),
		floori(local_position.y / GRID_SIZE)
	)


static func shell_position(value: Variant) -> Vector2:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return Vector2.ZERO
	return _shell_position_unchecked(geometry)


# 仅接收 load_geometry 已验证的结果，供分帧构建避免重复扫描整份 floor_cells。
static func room_setup_from_loaded_geometry(geometry: Dictionary) -> Dictionary:
	return {
		"shell_position": _shell_position_unchecked(geometry),
		"entry_point": _get_primary_entry_point_unchecked(geometry),
		"exit_point": _get_primary_exit_point_unchecked(geometry),
	}


static func _shell_position_unchecked(geometry: Dictionary) -> Vector2:
	var canvas := _point(geometry.get("canvas_size_px", [0, 0]))
	var world_origin := _point(geometry.get("world_origin_px", [0, 0]))
	return canvas * 0.5 - world_origin


static func get_shell_local_bounds(value: Variant) -> Rect2:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return Rect2()
	return _get_shell_local_bounds_unchecked(geometry)


static func _get_shell_local_bounds_unchecked(geometry: Dictionary) -> Rect2:
	var canvas := _point(geometry.get("canvas_size_px", [0, 0]))
	return Rect2(_shell_position_unchecked(geometry) - canvas * 0.5, canvas)


static func get_floor_local_bounds(value: Variant) -> Rect2:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return Rect2()
	return _get_floor_local_bounds_unchecked(geometry)


static func _get_floor_local_bounds_unchecked(geometry: Dictionary) -> Rect2:
	var cells := _get_walkable_cells_unchecked(geometry)
	if cells.is_empty():
		return Rect2()
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	return Rect2(
		Vector2(min_cell) * GRID_SIZE,
		Vector2(max_cell - min_cell + Vector2i.ONE) * GRID_SIZE
	)


static func get_primary_exit_point(value: Variant) -> Vector2:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return Vector2.ZERO
	return _get_primary_exit_point_unchecked(geometry)


static func _get_primary_exit_point_unchecked(geometry: Dictionary) -> Vector2:
	var doorway_list := _array_or_empty(geometry.get("doorway"))
	if doorway_list.is_empty() or typeof(doorway_list[0]) != TYPE_DICTIONARY:
		return Vector2.ZERO
	var doorway := doorway_list[0] as Dictionary
	var threshold_cells := _doorway_threshold_cells(doorway)
	if threshold_cells.is_empty():
		return _point(doorway.get("entry_anchor_px", [0, 0]))
	var center := Vector2.ZERO
	for cell in threshold_cells:
		center += _cell_to_local_center_unchecked(cell)
	return center / float(threshold_cells.size())


static func get_primary_entry_point(value: Variant) -> Vector2:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return Vector2.ZERO
	return _get_primary_entry_point_unchecked(geometry)


static func _get_primary_entry_point_unchecked(geometry: Dictionary) -> Vector2:
	var doorway_list := _array_or_empty(geometry.get("doorway"))
	if doorway_list.is_empty() or typeof(doorway_list[0]) != TYPE_DICTIONARY:
		return Vector2.ZERO
	var doorway := doorway_list[0] as Dictionary
	var threshold_cells := _doorway_threshold_cells(doorway)
	if threshold_cells.is_empty():
		return _get_primary_exit_point_unchecked(geometry)
	var walkable_lookup := _get_walkable_lookup_unchecked(geometry)
	var exit_point := _get_primary_exit_point_unchecked(geometry)
	var authored_entry := _point(doorway.get("entry_anchor_px", [0, 0]))
	if (
		walkable_lookup.has(_local_position_to_cell_unchecked(authored_entry))
		and (
			_local_position_to_cell_unchecked(authored_entry)
			!= _local_position_to_cell_unchecked(exit_point)
		)
	):
		return authored_entry
	var inward := _doorway_inward_offset(geometry, threshold_cells)
	var middle_cell := threshold_cells[threshold_cells.size() / 2]
	for distance in [1, 2, 3, 4]:
		var candidate := middle_cell + inward * int(distance)
		if walkable_lookup.has(candidate):
			return _cell_to_local_center_unchecked(candidate)
	if walkable_lookup.has(middle_cell):
		return _cell_to_local_center_unchecked(middle_cell)
	return exit_point


static func get_boundary_blocker_cells(value: Variant) -> Array[Vector2i]:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return []
	return _get_boundary_blocker_cells_unchecked(geometry)


static func _get_boundary_blocker_cells_unchecked(
	geometry: Dictionary
) -> Array[Vector2i]:
	var walkable_lookup := _get_walkable_lookup_unchecked(geometry)
	var doorway_openings := _doorway_outside_openings(geometry, walkable_lookup)
	var blocker_lookup := {}
	for floor_cell_value in walkable_lookup.keys():
		var floor_cell := floor_cell_value as Vector2i
		for offset in CARDINAL_OFFSETS:
			var candidate := floor_cell + offset
			if (
				not walkable_lookup.has(candidate)
				and not doorway_openings.has(candidate)
			):
				blocker_lookup[candidate] = true
	var blockers: Array[Vector2i] = []
	for cell_value in blocker_lookup.keys():
		blockers.append(cell_value as Vector2i)
	_sort_cells(blockers)
	return blockers


static func get_boundary_collision_rects(value: Variant) -> Array[Rect2]:
	var geometry := _validated_geometry(value)
	if geometry.is_empty():
		return []
	return _get_boundary_collision_rects_unchecked(geometry)


static func boundary_collision_rects_from_loaded_geometry(
	geometry: Dictionary,
) -> Array[Rect2]:
	return _get_boundary_collision_rects_unchecked(geometry)


# 分帧构建只接收 load_geometry 已校验的结果。每个 work item 最多处理一个
# 地板格、门槛格、相邻方向或包围盒格，避免单次调用暗藏全量扫描。
static func begin_boundary_collision_scan(geometry: Dictionary) -> Dictionary:
	return {
		"phase": "floor",
		"floor_values": geometry.get("floor_cells", []) as Array,
		"floor_cursor": 0,
		"floor_lookup": {},
		"floor_cells": [],
		"min_cell": Vector2i.ZERO,
		"max_cell": Vector2i.ZERO,
		"doorways": geometry.get("doorway", []) as Array,
		"doorway_cursor": 0,
		"threshold_values": [],
		"threshold_cells": [],
		"threshold_cursor": 0,
		"threshold_center": Vector2.ZERO,
		"outward": Vector2i.ZERO,
		"doorway_openings": {},
		"boundary_cursor": 0,
		"boundary_direction": 0,
		"blockers": {},
		"scan_cell": Vector2i.ZERO,
		"scan_min": Vector2i.ZERO,
		"scan_max": Vector2i.ZERO,
		"run_start_x": 0,
		"run_active": false,
		"rects": [],
		"complete": false,
	}


static func continue_boundary_collision_scan(
	state: Dictionary,
	max_work_items: int,
) -> Dictionary:
	var work_limit := clampi(max_work_items, 1, MAX_INCREMENTAL_WORK_ITEMS)
	var processed := 0
	while processed < work_limit and not bool(state.get("complete", false)):
		match String(state.get("phase", "")):
			"floor":
				var floor_values := state.get("floor_values", []) as Array
				var cursor := int(state.get("floor_cursor", 0))
				if cursor >= floor_values.size():
					state["phase"] = "doorway_start"
					continue
				var cell := _integral_cell(floor_values[cursor])
				var floor_lookup := state.get("floor_lookup", {}) as Dictionary
				var floor_cells := state.get("floor_cells", []) as Array
				floor_lookup[cell] = true
				floor_cells.append(cell)
				if cursor == 0:
					state["min_cell"] = cell
					state["max_cell"] = cell
				else:
					var minimum := state.get("min_cell") as Vector2i
					var maximum := state.get("max_cell") as Vector2i
					minimum.x = mini(minimum.x, cell.x)
					minimum.y = mini(minimum.y, cell.y)
					maximum.x = maxi(maximum.x, cell.x)
					maximum.y = maxi(maximum.y, cell.y)
					state["min_cell"] = minimum
					state["max_cell"] = maximum
				state["floor_cursor"] = cursor + 1
				processed += 1
			"doorway_start":
				var doorways := state.get("doorways", []) as Array
				var doorway_cursor := int(state.get("doorway_cursor", 0))
				if doorway_cursor >= doorways.size():
					state["phase"] = "boundary"
					continue
				var doorway := doorways[doorway_cursor] as Dictionary
				state["threshold_values"] = doorway.get("threshold_cells", []) as Array
				state["threshold_cells"] = []
				state["threshold_cursor"] = 0
				state["threshold_center"] = Vector2.ZERO
				state["phase"] = "doorway_center"
			"doorway_center":
				var threshold_values := state.get("threshold_values", []) as Array
				var thresholds := state.get("threshold_cells", []) as Array
				var threshold_cursor := int(state.get("threshold_cursor", 0))
				if threshold_cursor >= threshold_values.size():
					var floor_minimum := state.get("min_cell") as Vector2i
					var floor_maximum := state.get("max_cell") as Vector2i
					var floor_center := (
						Vector2(floor_minimum + floor_maximum + Vector2i.ONE)
						* GRID_SIZE * 0.5
					)
					var threshold_center := (
						state.get("threshold_center") as Vector2
					) / float(thresholds.size())
					var toward_center := floor_center - threshold_center
					var inward := (
						(Vector2i.RIGHT if toward_center.x >= 0.0 else Vector2i.LEFT)
						if absf(toward_center.x) > absf(toward_center.y)
						else (Vector2i.DOWN if toward_center.y >= 0.0 else Vector2i.UP)
					)
					state["outward"] = -inward
					state["threshold_cursor"] = 0
					state["phase"] = "doorway_openings"
					continue
				var threshold_cell := _integral_cell(threshold_values[threshold_cursor])
				thresholds.append(threshold_cell)
				state["threshold_center"] = (
					state.get("threshold_center") as Vector2
				) + _cell_to_local_center_unchecked(threshold_cell)
				state["threshold_cursor"] = threshold_cursor + 1
				processed += 1
			"doorway_openings":
				var thresholds := state.get("threshold_cells", []) as Array
				var threshold_cursor := int(state.get("threshold_cursor", 0))
				if threshold_cursor >= thresholds.size():
					state["doorway_cursor"] = int(state.get("doorway_cursor", 0)) + 1
					state["phase"] = "doorway_start"
					continue
				var outside := (
					thresholds[threshold_cursor] as Vector2i
				) + (state.get("outward") as Vector2i)
				var floor_lookup := state.get("floor_lookup", {}) as Dictionary
				if not floor_lookup.has(outside):
					(state.get("doorway_openings", {}) as Dictionary)[outside] = true
				state["threshold_cursor"] = threshold_cursor + 1
				processed += 1
			"boundary":
				var floor_cells := state.get("floor_cells", []) as Array
				var floor_cursor := int(state.get("boundary_cursor", 0))
				if floor_cursor >= floor_cells.size():
					var scan_minimum := (state.get("min_cell") as Vector2i) - Vector2i.ONE
					var scan_maximum := (state.get("max_cell") as Vector2i) + Vector2i.ONE
					state["scan_min"] = scan_minimum
					state["scan_max"] = scan_maximum
					state["scan_cell"] = scan_minimum
					state["phase"] = "rects"
					continue
				var direction_cursor := int(state.get("boundary_direction", 0))
				var candidate := (
					floor_cells[floor_cursor] as Vector2i
				) + CARDINAL_OFFSETS[direction_cursor]
				var floor_lookup := state.get("floor_lookup", {}) as Dictionary
				var openings := state.get("doorway_openings", {}) as Dictionary
				if not floor_lookup.has(candidate) and not openings.has(candidate):
					(state.get("blockers", {}) as Dictionary)[candidate] = true
				direction_cursor += 1
				if direction_cursor >= CARDINAL_OFFSETS.size():
					direction_cursor = 0
					state["boundary_cursor"] = floor_cursor + 1
				state["boundary_direction"] = direction_cursor
				processed += 1
			"rects":
				var scan_cell := state.get("scan_cell") as Vector2i
				var scan_maximum := state.get("scan_max") as Vector2i
				var is_blocker := (state.get("blockers", {}) as Dictionary).has(scan_cell)
				if is_blocker and not bool(state.get("run_active", false)):
					state["run_active"] = true
					state["run_start_x"] = scan_cell.x
				var row_ended := scan_cell.x >= scan_maximum.x
				if bool(state.get("run_active", false)) and (not is_blocker or row_ended):
					var run_end_x := scan_cell.x + 1 if is_blocker else scan_cell.x
					var run_start_x := int(state.get("run_start_x", scan_cell.x))
					(state.get("rects", []) as Array).append(Rect2(
						Vector2(run_start_x, scan_cell.y) * GRID_SIZE,
						Vector2(run_end_x - run_start_x, 1) * GRID_SIZE,
					))
					state["run_active"] = false
				if row_ended:
					if scan_cell.y >= scan_maximum.y:
						state["complete"] = true
					else:
						state["scan_cell"] = Vector2i(
							(state.get("scan_min") as Vector2i).x,
							scan_cell.y + 1,
						)
				else:
					state["scan_cell"] = scan_cell + Vector2i.RIGHT
				processed += 1
			_:
				state["complete"] = true
	return {
		"complete": bool(state.get("complete", false)),
		"processed": processed,
		"rects": state.get("rects", []) as Array,
	}


static func _get_boundary_collision_rects_unchecked(
	geometry: Dictionary
) -> Array[Rect2]:
	var remaining := {}
	var sorted_cells := _get_boundary_blocker_cells_unchecked(geometry)
	for cell in sorted_cells:
		remaining[cell] = true
	var collision_rects: Array[Rect2] = []
	for start in sorted_cells:
		if not remaining.has(start):
			continue
		var width := 1
		while remaining.has(start + Vector2i(width, 0)):
			width += 1
		var height := 1
		while _row_run_exists(remaining, start + Vector2i(0, height), width):
			height += 1
		for y in range(height):
			for x in range(width):
				remaining.erase(start + Vector2i(x, y))
		collision_rects.append(Rect2(
			Vector2(start) * GRID_SIZE,
			Vector2(width, height) * GRID_SIZE
		))
	return collision_rects


static func build_navigation_grid_data(
	value: Variant,
	entry_value: Variant,
	exit_value: Variant
) -> Dictionary:
	var geometry := _validated_geometry(value)
	if (
		geometry.is_empty()
		or not _is_finite_vector2(entry_value)
		or not _is_finite_vector2(exit_value)
	):
		return {}
	var entry_point := entry_value as Vector2
	var exit_point := exit_value as Vector2
	return _build_navigation_grid_data_unchecked(
		geometry,
		entry_point,
		exit_point,
	)


static func navigation_grid_from_loaded_geometry(
	geometry: Dictionary,
	entry_point: Vector2,
	exit_point: Vector2,
) -> Dictionary:
	return _build_navigation_grid_data_unchecked(
		geometry,
		entry_point,
		exit_point,
	)


static func begin_navigation_grid_scan(
	geometry: Dictionary,
	entry_point: Vector2,
	exit_point: Vector2,
) -> Dictionary:
	return {
		"phase": "floor",
		"floor_values": geometry.get("floor_cells", []) as Array,
		"floor_cursor": 0,
		"walkable_lookup": {},
		"serialized_walkable": [],
		"min_cell": Vector2i.ZERO,
		"max_cell": Vector2i.ZERO,
		"entry_point": entry_point,
		"exit_point": exit_point,
		"profile_id": String(geometry.get("room_id", "")),
		"source_revision": String(geometry.get("source_revision", "")),
		"scan_cell": Vector2i.ZERO,
		"wall_cells": [],
		"result": {},
		"complete": false,
		"failed": false,
	}


static func continue_navigation_grid_scan(
	state: Dictionary,
	max_work_items: int,
) -> Dictionary:
	var work_limit := clampi(max_work_items, 1, MAX_INCREMENTAL_WORK_ITEMS)
	var processed := 0
	while processed < work_limit and not bool(state.get("complete", false)):
		match String(state.get("phase", "")):
			"floor":
				var floor_values := state.get("floor_values", []) as Array
				var cursor := int(state.get("floor_cursor", 0))
				if cursor >= floor_values.size():
					var minimum := state.get("min_cell") as Vector2i
					var maximum := state.get("max_cell") as Vector2i
					var grid_size := maximum - minimum + Vector2i.ONE
					var entry_cell := _local_position_to_cell_unchecked(
						state.get("entry_point") as Vector2,
					)
					var exit_cell := _local_position_to_cell_unchecked(
						state.get("exit_point") as Vector2,
					)
					var lookup := state.get("walkable_lookup", {}) as Dictionary
					if (
						floor_values.is_empty()
						or grid_size.x * grid_size.y > MAX_NAVIGATION_GRID_CELLS
						or not lookup.has(entry_cell)
						or not lookup.has(exit_cell)
					):
						state["failed"] = true
						state["complete"] = true
						continue
					state["entry_cell"] = entry_cell
					state["exit_cell"] = exit_cell
					state["scan_cell"] = minimum
					state["phase"] = "walls"
					continue
				var cell := _integral_cell(floor_values[cursor])
				(state.get("walkable_lookup", {}) as Dictionary)[cell] = true
				(state.get("serialized_walkable", []) as Array).append([cell.x, cell.y])
				if cursor == 0:
					state["min_cell"] = cell
					state["max_cell"] = cell
				else:
					var minimum := state.get("min_cell") as Vector2i
					var maximum := state.get("max_cell") as Vector2i
					minimum.x = mini(minimum.x, cell.x)
					minimum.y = mini(minimum.y, cell.y)
					maximum.x = maxi(maximum.x, cell.x)
					maximum.y = maxi(maximum.y, cell.y)
					state["min_cell"] = minimum
					state["max_cell"] = maximum
				state["floor_cursor"] = cursor + 1
				processed += 1
			"walls":
				var cell := state.get("scan_cell") as Vector2i
				var maximum := state.get("max_cell") as Vector2i
				if not (state.get("walkable_lookup", {}) as Dictionary).has(cell):
					(state.get("wall_cells", []) as Array).append([cell.x, cell.y])
				if cell.x >= maximum.x:
					if cell.y >= maximum.y:
						var minimum := state.get("min_cell") as Vector2i
						var entry_cell := state.get("entry_cell") as Vector2i
						var exit_cell := state.get("exit_cell") as Vector2i
						state["result"] = {
							"revision": 2,
							"profile_id": String(state.get("profile_id", "")),
							"source_revision": String(state.get("source_revision", "")),
							"cell_size": int(GRID_SIZE),
							"origin_cell": [minimum.x, minimum.y],
							"size": [maximum.x - minimum.x + 1, maximum.y - minimum.y + 1],
							"entry_cell": [entry_cell.x, entry_cell.y],
							"exit_cell": [exit_cell.x, exit_cell.y],
							"walkable_cells": state.get("serialized_walkable", []) as Array,
							"wall_cells": state.get("wall_cells", []) as Array,
							"neighbor_mode": "cardinal_4",
						}
						state["complete"] = true
					else:
						state["scan_cell"] = Vector2i(
							(state.get("min_cell") as Vector2i).x,
							cell.y + 1,
						)
				else:
					state["scan_cell"] = cell + Vector2i.RIGHT
				processed += 1
			_:
				state["failed"] = true
				state["complete"] = true
	return {
		"complete": bool(state.get("complete", false)),
		"failed": bool(state.get("failed", false)),
		"processed": processed,
		"data": state.get("result", {}) as Dictionary,
	}


static func _build_navigation_grid_data_unchecked(
	geometry: Dictionary,
	entry_point: Vector2,
	exit_point: Vector2,
) -> Dictionary:
	var walkable_cells := _get_walkable_cells_unchecked(geometry)
	if walkable_cells.is_empty():
		return {}
	var min_cell := walkable_cells[0]
	var max_cell := walkable_cells[0]
	var walkable_lookup := {}
	var serialized_walkable: Array = []
	for cell in walkable_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
		walkable_lookup[cell] = true
		serialized_walkable.append([cell.x, cell.y])
	var grid_width := max_cell.x - min_cell.x + 1
	var grid_height := max_cell.y - min_cell.y + 1
	if grid_width * grid_height > MAX_NAVIGATION_GRID_CELLS:
		return {}
	var entry_cell := _local_position_to_cell_unchecked(entry_point)
	var exit_cell := _local_position_to_cell_unchecked(exit_point)
	if not walkable_lookup.has(entry_cell) or not walkable_lookup.has(exit_cell):
		return {}
	var wall_cells: Array = []
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)
			if not walkable_lookup.has(cell):
				wall_cells.append([cell.x, cell.y])
	return {
		"revision": 2,
		"profile_id": geometry["room_id"],
		"source_revision": geometry["source_revision"],
		"cell_size": int(GRID_SIZE),
		"origin_cell": [min_cell.x, min_cell.y],
		"size": [max_cell.x - min_cell.x + 1, max_cell.y - min_cell.y + 1],
		"entry_cell": [entry_cell.x, entry_cell.y],
		"exit_cell": [exit_cell.x, exit_cell.y],
		"walkable_cells": serialized_walkable,
		"wall_cells": wall_cells,
		"neighbor_mode": "cardinal_4",
	}


static func _doorway_outside_openings(
	geometry: Dictionary,
	walkable_lookup: Dictionary
) -> Dictionary:
	var openings := {}
	var doorway_values := _array_or_empty(geometry.get("doorway"))
	if doorway_values.size() > MAX_DOORWAYS:
		return openings
	for doorway_value in doorway_values:
		if typeof(doorway_value) != TYPE_DICTIONARY:
			continue
		var threshold_cells := _doorway_threshold_cells(doorway_value as Dictionary)
		if threshold_cells.is_empty():
			continue
		var outward := -_doorway_inward_offset(geometry, threshold_cells)
		for threshold_cell in threshold_cells:
			var outside_cell := threshold_cell + outward
			if not walkable_lookup.has(outside_cell):
				openings[outside_cell] = true
	return openings


static func _doorway_inward_offset(
	geometry: Dictionary,
	threshold_cells: Array[Vector2i]
) -> Vector2i:
	var floor_center := _get_floor_local_bounds_unchecked(geometry).get_center()
	var threshold_center := Vector2.ZERO
	for cell in threshold_cells:
		threshold_center += _cell_to_local_center_unchecked(cell)
	threshold_center /= float(threshold_cells.size())
	var toward_center := floor_center - threshold_center
	if absf(toward_center.x) > absf(toward_center.y):
		return Vector2i.RIGHT if toward_center.x >= 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if toward_center.y >= 0.0 else Vector2i.UP


static func _array_or_empty(value: Variant) -> Array:
	return value as Array if value is Array else []


static func _point(value: Variant) -> Vector2:
	if _is_finite_point(value):
		var values := value as Array
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO


static func _integral_cell(value: Variant) -> Vector2i:
	var values := value as Array
	return Vector2i(int(values[0]), int(values[1]))


static func _doorway_threshold_cells(doorway: Dictionary) -> Array[Vector2i]:
	var threshold_cells: Array[Vector2i] = []
	var threshold_values := _array_or_empty(doorway.get("threshold_cells"))
	if threshold_values.size() > MAX_DOORWAY_CELLS:
		return threshold_cells
	for value in threshold_values:
		if _is_integral_point(value):
			threshold_cells.append(_integral_cell(value))
	return threshold_cells


static func _validated_geometry(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	if not validate_geometry(value).is_empty():
		return {}
	return value as Dictionary


static func _validate_exact_keys(
	record: Dictionary,
	allowed_keys: Dictionary,
	context: String,
	errors: PackedStringArray,
) -> void:
	for key_value in record.keys():
		if typeof(key_value) != TYPE_STRING or not allowed_keys.has(key_value):
			errors.append("%s contains unknown field %s" % [context, str(key_value)])
	for key_value in allowed_keys.keys():
		if not record.has(key_value):
			errors.append("%s is missing field %s" % [context, str(key_value)])


static func _validate_floor_polygons(
	value: Variant,
	canvas_size_value: Variant,
	world_origin_value: Variant,
	floor_cells: Array[Vector2i],
	floor_lookup: Dictionary,
	can_compare_floor: bool,
	errors: PackedStringArray,
) -> void:
	if not value is Array:
		errors.append("floor_polygon must be an array")
		return
	var polygons := value as Array
	if polygons.is_empty():
		errors.append("floor_polygon must not be empty")
		return
	if polygons.size() > MAX_FLOOR_POLYGONS:
		errors.append("floor_polygon exceeds the supported polygon limit")
		return
	var total_points := 0
	var intersection_work := 0
	var valid_polygons: Array[PackedVector2Array] = []
	var polygons_are_valid := true
	var shell_is_valid := (
		_is_positive_integral_point(canvas_size_value)
		and _is_integral_point(world_origin_value)
	)
	var canvas_size := _point(canvas_size_value)
	var world_origin := _point(world_origin_value)
	for polygon_index in range(polygons.size()):
		var polygon_value: Variant = polygons[polygon_index]
		if not polygon_value is Array:
			errors.append("floor_polygon[%d] must be an array" % polygon_index)
			polygons_are_valid = false
			continue
		var points := polygon_value as Array
		if points.size() < 3:
			errors.append("floor_polygon[%d] requires at least three points" % polygon_index)
			polygons_are_valid = false
			continue
		if points.size() > MAX_POLYGON_POINTS:
			errors.append("floor_polygon[%d] exceeds the point limit" % polygon_index)
			polygons_are_valid = false
			continue
		total_points += points.size()
		if total_points > MAX_FLOOR_POLYGON_POINTS:
			errors.append("floor_polygon exceeds the total point limit")
			return
		intersection_work += _nonadjacent_edge_pair_count(points.size())
		if intersection_work > MAX_POLYGON_INTERSECTION_CHECKS:
			errors.append("floor_polygon intersection checks exceed the supported limit")
			return
		var polygon := PackedVector2Array()
		var polygon_is_valid := true
		for point_index in range(points.size()):
			if not _is_integral_point(points[point_index]):
				errors.append(
					"floor_polygon[%d][%d] must contain exactly two integers"
					% [polygon_index, point_index]
				)
				polygon_is_valid = false
				continue
			var point := _point(points[point_index])
			polygon.append(point)
			if shell_is_valid and not _point_fits_shell(
				point,
				canvas_size,
				world_origin,
			):
				errors.append(
					"floor_polygon[%d][%d] is outside canvas bounds"
					% [polygon_index, point_index]
				)
				polygon_is_valid = false
		if not polygon_is_valid:
			polygons_are_valid = false
			continue
		if (
			absf(_polygon_signed_double_area(polygon)) < 1.0
			or Geometry2D.triangulate_polygon(polygon).is_empty()
			or _polygon_has_self_intersection(polygon)
		):
			errors.append("floor_polygon[%d] must have valid positive area" % polygon_index)
			polygons_are_valid = false
			continue
		valid_polygons.append(polygon)
	if (
		not polygons_are_valid
		or not can_compare_floor
		or floor_cells.is_empty()
		or valid_polygons.size() != polygons.size()
	):
		return

	var covered_cells := {}
	var raster_work := 0
	for polygon_index in range(valid_polygons.size()):
		var polygon := valid_polygons[polygon_index]
		var bounds := _polygon_bounds(polygon)
		var first_cell := Vector2i(
			floori(bounds.position.x / GRID_SIZE),
			floori(bounds.position.y / GRID_SIZE),
		)
		var last_cell := Vector2i(
			ceili(bounds.end.x / GRID_SIZE) - 1,
			ceili(bounds.end.y / GRID_SIZE) - 1,
		)
		var raster_width := last_cell.x - first_cell.x + 1
		var raster_height := last_cell.y - first_cell.y + 1
		if raster_width <= 0 or raster_height <= 0:
			errors.append("floor_polygon[%d] has empty raster bounds" % polygon_index)
			return
		raster_work += raster_width * raster_height
		if raster_work > MAX_FLOOR_POLYGON_RASTER_CELLS:
			errors.append("floor_polygon rasterization exceeds the supported limit")
			return
		for y in range(first_cell.y, last_cell.y + 1):
			for x in range(first_cell.x, last_cell.x + 1):
				var cell := Vector2i(x, y)
				if Geometry2D.is_point_in_polygon(
					_cell_to_local_center_unchecked(cell),
					polygon,
				):
					covered_cells[cell] = true
	if covered_cells.size() != floor_lookup.size():
		errors.append("floor_polygon must cover exactly floor_cells")
		return
	for cell in floor_cells:
		if not covered_cells.has(cell):
			errors.append("floor_polygon must cover exactly floor_cells")
			return


static func _point_fits_shell(
	point: Vector2,
	canvas_size: Vector2,
	world_origin: Vector2,
) -> bool:
	var shell_minimum := -world_origin
	var shell_maximum := shell_minimum + canvas_size
	return (
		point.x >= shell_minimum.x
		and point.y >= shell_minimum.y
		and point.x <= shell_maximum.x
		and point.y <= shell_maximum.y
	)


static func _polygon_signed_double_area(points: PackedVector2Array) -> float:
	var result := 0.0
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		result += current.x * next.y - next.x * current.y
	return result


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


static func _nonadjacent_edge_pair_count(point_count: int) -> int:
	if point_count < 4:
		return 0
	return point_count * (point_count - 3) / 2


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
	return second_side_b == 0.0 and _point_on_closed_segment(
		first_end,
		second_start,
		second_end,
	)


static func _orientation(start: Vector2, end: Vector2, point: Vector2) -> float:
	return (end - start).cross(point - start)


static func _point_on_closed_segment(point: Vector2, start: Vector2, end: Vector2) -> bool:
	return (
		point.x >= minf(start.x, end.x)
		and point.x <= maxf(start.x, end.x)
		and point.y >= minf(start.y, end.y)
		and point.y <= maxf(start.y, end.y)
	)


static func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


static func _validate_functional_anchors(
	value: Variant,
	floor_lookup: Dictionary,
	errors: PackedStringArray,
) -> void:
	if not value is Array:
		errors.append("functional_anchor must be an array")
		return
	var anchors := value as Array
	if anchors.is_empty():
		errors.append("functional_anchor must not be empty")
		return
	if anchors.size() > MAX_FUNCTIONAL_ANCHORS:
		errors.append("functional_anchor exceeds the supported limit")
		return
	var anchor_ids := {}
	for anchor_index in range(anchors.size()):
		var anchor_value: Variant = anchors[anchor_index]
		if typeof(anchor_value) != TYPE_DICTIONARY:
			errors.append("functional_anchor[%d] must be an object" % anchor_index)
			continue
		var anchor := anchor_value as Dictionary
		_validate_exact_keys(
			anchor,
			FUNCTIONAL_ANCHOR_KEYS,
			"functional_anchor[%d]" % anchor_index,
			errors,
		)
		var anchor_id: Variant = anchor.get("id")
		if not _is_canonical_text(anchor_id):
			errors.append(
				"functional_anchor[%d].id must be canonical non-empty text"
				% anchor_index
			)
		elif anchor_ids.has(anchor_id):
			errors.append(
				"functional_anchor[%d].id duplicates %s"
				% [anchor_index, anchor_id]
			)
		else:
			anchor_ids[anchor_id] = true
		var position_value: Variant = anchor.get("position_px")
		if not _is_finite_point(position_value):
			errors.append(
				"functional_anchor[%d].position_px must contain exactly two finite numbers"
				% anchor_index
			)
		elif not floor_lookup.has(
			_local_position_to_cell_unchecked(_point(position_value))
		):
			errors.append(
				"functional_anchor[%d].position_px is not walkable"
				% anchor_index
			)
		if typeof(anchor.get("required_access")) != TYPE_BOOL:
			errors.append(
				"functional_anchor[%d].required_access must be a boolean"
				% anchor_index
			)


static func _cell_fits_shell(
	cell: Vector2i,
	canvas_size: Vector2,
	world_origin: Vector2,
) -> bool:
	var shell_minimum := -world_origin
	var shell_maximum := shell_minimum + canvas_size
	var cell_minimum := Vector2(cell) * GRID_SIZE
	var cell_maximum := cell_minimum + Vector2(GRID_SIZE, GRID_SIZE)
	return (
		cell_minimum.x >= shell_minimum.x
		and cell_minimum.y >= shell_minimum.y
		and cell_maximum.x <= shell_maximum.x
		and cell_maximum.y <= shell_maximum.y
	)


static func _is_canonical_text(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text := value as String
	if (
		text.is_empty()
		or text.length() > MAX_CANONICAL_TEXT_LENGTH
		or text != text.strip_edges()
	):
		return false
	for index in range(text.length()):
		var codepoint := text.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true


static func _is_canonical_relative_path(value: Variant) -> bool:
	if not _is_canonical_text(value):
		return false
	var path := value as String
	if (
		path.begins_with("/")
		or path.ends_with("/")
		or path.contains("\\")
		or path.contains(":")
		or path.contains("//")
	):
		return false
	for segment in path.split("/", false):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return (
		not is_nan(number)
		and not is_inf(number)
		and absf(number) <= 2_147_483_647.0
		and number == floor(number)
	)


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)


static func _is_finite_vector2(value: Variant) -> bool:
	if typeof(value) != TYPE_VECTOR2:
		return false
	var point := value as Vector2
	return (
		not is_nan(point.x)
		and not is_inf(point.x)
		and not is_nan(point.y)
		and not is_inf(point.y)
		and absf(point.x) <= MAX_POINT_COMPONENT
		and absf(point.y) <= MAX_POINT_COMPONENT
	)


static func _is_finite_point(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	var values := value as Array
	return (
		_is_finite_number(values[0])
		and _is_finite_number(values[1])
		and absf(float(values[0])) <= MAX_POINT_COMPONENT
		and absf(float(values[1])) <= MAX_POINT_COMPONENT
	)


static func _is_integral_point(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	var values := value as Array
	return (
		_is_integer_number(values[0])
		and _is_integer_number(values[1])
		and absf(float(values[0])) <= MAX_INTEGRAL_COMPONENT
		and absf(float(values[1])) <= MAX_INTEGRAL_COMPONENT
	)


static func _is_positive_integral_point(value: Variant) -> bool:
	if not _is_integral_point(value):
		return false
	var values := value as Array
	return int(values[0]) > 0 and int(values[1]) > 0


static func _cells_are_connected(cells: Array[Vector2i]) -> bool:
	if cells.is_empty():
		return false
	var unvisited := {}
	for cell in cells:
		unvisited[cell] = true
	var pending: Array[Vector2i] = [cells[0]]
	unvisited.erase(cells[0])
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		for offset in CARDINAL_OFFSETS:
			var neighbor: Vector2i = current + offset
			if unvisited.erase(neighbor):
				pending.append(neighbor)
	return unvisited.is_empty()


static func _cell_bounding_area(cells: Array[Vector2i]) -> int:
	if cells.is_empty():
		return 0
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	return (max_cell.x - min_cell.x + 1) * (max_cell.y - min_cell.y + 1)


static func _cells_form_straight_cardinal_run(cells: Array[Vector2i]) -> bool:
	if cells.is_empty():
		return false
	var sorted_cells := cells.duplicate()
	_sort_cells(sorted_cells)
	var same_x := true
	var same_y := true
	for cell in sorted_cells:
		same_x = same_x and cell.x == sorted_cells[0].x
		same_y = same_y and cell.y == sorted_cells[0].y
	if not same_x and not same_y:
		return false
	for index in range(1, sorted_cells.size()):
		if same_x and sorted_cells[index].y != sorted_cells[index - 1].y + 1:
			return false
		if same_y and sorted_cells[index].x != sorted_cells[index - 1].x + 1:
			return false
	return true


static func _row_run_exists(lookup: Dictionary, start: Vector2i, width: int) -> bool:
	for x in range(width):
		if not lookup.has(start + Vector2i(x, 0)):
			return false
	return true


static func _sort_cells(cells: Array[Vector2i]) -> void:
	cells.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
