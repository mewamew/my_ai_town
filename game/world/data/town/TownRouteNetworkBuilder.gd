extends RefCounted


const AUTHORING_FILES := preload(
	"res://world/data/town/TownAuthoringFiles.gd"
)
const OUTDOOR_SPACE_ID := "town_outdoor"
const OUTDOOR_COLLISION_PATH := "res://world/maps/town/generated/collision.json"
const OUTDOOR_PERCEPTION_PATH := (
	"res://world/data/town/source/perception_regions.json"
)
const OUTDOOR_NAVIGATION_CACHE_PATH := (
	"res://world/data/town/source/outdoor_navigation_grid.json"
)
const MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const MOVEMENT_SURFACE := preload(
	"res://world/data/town/TownOutdoorSurfaceMask.gd"
)
const PORTAL_CATALOG := preload(
	"res://world/data/town/TownPortalCatalog.gd"
)
const WORLD_DATA_VALIDATOR := preload(
	"res://world/data/town/TownWorldDataValidator.gd"
)
const ROUTE_GRID_DIVISIONS := 2
const PORTAL_APPROACH_SEARCH_RADIUS := 64
const CELL_PATH_CACHE_MAX_ENTRIES := 1024

var _cell_size := 0
var _grid_width := 0
var _grid_height := 0
var _legal_cells := {}
var _region_by_cell := {}
var _place_by_cell := {}
var _collision_records: Array[Dictionary] = []
var _surface_mask := PackedByteArray()
var _route_cell_by_node_id: Dictionary = {}
var _component_by_cell_key: Dictionary = {}
var _cells_by_component: Dictionary = {}
var _grid: AStar2D
var _errors: Array[String] = []
var _simplified_cell_path_cache: Dictionary = {}

static var _runtime_pathfinder: RefCounted


static func load_json_object(path: String) -> Dictionary:
	return AUTHORING_FILES.load_json_object(path)


static func load_json_array(path: String) -> Array:
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed as Array


static func serialize_document(document: Dictionary) -> String:
	return AUTHORING_FILES.serialize_document(document)


static func write_document(path: String, document: Dictionary) -> bool:
	return AUTHORING_FILES.write_document(path, document)


static func find_outdoor_path(
	from_position: Vector2,
	to_position: Vector2,
) -> Dictionary:
	if not from_position.is_finite() or not to_position.is_finite():
		return {}
	var pathfinder := _runtime_outdoor_pathfinder()
	if pathfinder == null:
		return {}
	return pathfinder._route_between_positions(
		from_position,
		to_position,
	)


static func outdoor_position_is_navigable(position: Vector2) -> bool:
	var pathfinder := _runtime_outdoor_pathfinder()
	return (
		pathfinder != null
		and pathfinder._nearest_route_cell(position, "").x >= 0
	)


static func outdoor_polyline_is_navigable(points: PackedVector2Array) -> bool:
	if points.is_empty():
		return false
	var pathfinder := _runtime_outdoor_pathfinder()
	if pathfinder == null:
		return false
	for point: Vector2 in points:
		if pathfinder._nearest_route_cell(point, "").x < 0:
			return false
	for index: int in range(1, points.size()):
		if not pathfinder._movement_segment_is_safe(
			points[index - 1],
			points[index],
		):
			return false
	return true


static func reset_runtime_pathfinder() -> void:
	_runtime_pathfinder = null


static func prewarm_runtime_pathfinder() -> bool:
	# 显式触发一次全图寻路网格构建（当前基线约 1.4 秒，主线程同步）。
	# 生产流程目前没有预热点：这笔冷启动开销落在首个触发
	# validate_position_state 的调用方（如首次进入居民选择页）。
	# v49 门禁用本接口把冷构建耗时与页面本身耗时拆开计量；
	# 真正消除卡顿需先剖析 _prepare_grid_from_cache 等各段耗时后
	# 另行选择预生成、分帧或验证过线程安全的后台方案。
	return _runtime_outdoor_pathfinder() != null


static func _runtime_outdoor_pathfinder() -> RefCounted:
	if _runtime_pathfinder != null:
		return _runtime_pathfinder
	var navigation_cache := load_json_object(
		OUTDOOR_NAVIGATION_CACHE_PATH,
	)
	var collision_values := load_json_array(OUTDOOR_COLLISION_PATH)
	if navigation_cache.is_empty() or collision_values.is_empty():
		return null
	var candidate := new()
	candidate._collision_records = MOVEMENT_CLEARANCE.collision_records(
		collision_values,
	)
	candidate._surface_mask = MOVEMENT_SURFACE.data()
	if (
		candidate._collision_records.is_empty()
		or candidate._surface_mask.is_empty()
		or not candidate._prepare_grid_from_cache(navigation_cache)
	):
		return null
	_runtime_pathfinder = candidate
	return _runtime_pathfinder


static func assemble_validation_data(
	settings: Dictionary,
	spaces_document: Dictionary,
	places_document: Dictionary,
	perception_document: Dictionary,
	documents: Dictionary,
) -> Dictionary:
	var movement_document := documents.get("movement", {}) as Dictionary
	var connections_document := documents.get("connections", {}) as Dictionary
	var indoor_regions_document := documents.get("indoorRegions", {}) as Dictionary
	var regions := (perception_document.get("regions", []) as Array).duplicate(true)
	regions.append_array(
		(indoor_regions_document.get("regions", []) as Array).duplicate(true)
	)
	return {
		"movementRules": (settings.get("movementRules", {}) as Dictionary).duplicate(true),
		"mapSpaces": (spaces_document.get("spaces", []) as Array).duplicate(true),
		"places": (places_document.get("places", []) as Array).duplicate(true),
		"perceptionGrid": (perception_document.get("grid", {}) as Dictionary).duplicate(true),
		"perceptionRegions": regions,
		"connections": (connections_document.get("connections", []) as Array).duplicate(true),
		"movementNetwork": movement_document.duplicate(true),
	}


func build_documents(
	perception: Dictionary,
	spaces: Dictionary,
	authoring: Dictionary,
) -> Dictionary:
	_reset()
	if perception.is_empty() or spaces.is_empty() or authoring.is_empty():
		_fail("无法读取感知区域、空间台账或路网制作源数据")
		return _failed_result()
	var collision_values := load_json_array(OUTDOOR_COLLISION_PATH)
	_collision_records = MOVEMENT_CLEARANCE.collision_records(collision_values)
	if _collision_records.is_empty():
		_fail("无法读取正式室外碰撞，不能生成居民移动路线")
		return _failed_result()
	_surface_mask = MOVEMENT_SURFACE.data()
	if _surface_mask.is_empty():
		_fail("无法读取正式水域遮罩，不能生成居民移动路线")
		return _failed_result()
	if not _prepare_grid(perception):
		return _failed_result()
	var indoor_bounds_by_space := _indoor_bounds_by_space(spaces)

	var nodes_by_id := {}
	var junction_ids := PackedStringArray()
	var terminal_ids := PackedStringArray()
	var arrival_nodes := []
	var connections := []
	var indoor_regions := []

	for value in authoring.get("junctions", []) as Array:
		var source := value as Dictionary
		var node_id := str(source.get("id", ""))
		var desired := _pair_point(source.get("position", []) as Array)
		var desired_cell := _point_cell(desired)
		var desired_is_safe := (
			_legal_cells.has(_cell_key(desired_cell))
			and _movement_origin_is_safe(desired)
		)
		var cell := (
			desired_cell
			if desired_is_safe
			else _nearest_legal_cell(desired_cell)
		)
		if node_id.is_empty() or not _legal_cells.has(_cell_key(cell)):
			_fail("无法放置路口节点：%s" % node_id)
			return _failed_result()
		var position := desired if desired_is_safe else _cell_center(cell)
		var node := {
			"id": node_id,
			"kind": "junction",
			"spaceId": OUTDOOR_SPACE_ID,
			"position": _point_dictionary(position),
			"regionId": str(_region_by_cell.get(_cell_key(cell), "")),
			"placeName": str(_place_by_cell.get(_cell_key(cell), "")),
		}
		if not _insert_node(nodes_by_id, node):
			return _failed_result()
		junction_ids.append(node_id)

	for value in authoring.get("outdoorArrivals", []) as Array:
		var source := value as Dictionary
		var node_id := str(source.get("id", ""))
		var desired_position := _pair_point(source.get("position", []) as Array)
		var expected_place_name := str(source.get("placeName", ""))
		var desired_cell := _point_cell(desired_position)
		var desired_is_safe := (
			_legal_cells.has(_cell_key(desired_cell))
			and String(_place_by_cell.get(_cell_key(desired_cell), ""))
				== expected_place_name
			and _movement_origin_is_safe(desired_position)
		)
		var cell := (
			desired_cell
			if desired_is_safe
			else _nearest_legal_cell(
				desired_cell,
				expected_place_name,
			)
		)
		if not _legal_cells.has(_cell_key(cell)):
			_fail(
				"室外地点到达点找不到碰撞安全位置：%s at %s"
				% [node_id, desired_position]
			)
			return _failed_result()
		var position := (
			desired_position
			if desired_is_safe
			else _cell_center(cell)
		)
		var actual_place_name := str(_place_by_cell.get(_cell_key(cell), ""))
		if actual_place_name != expected_place_name:
			_fail(
				"室外地点到达点 %s 应属于 %s，实际属于 %s"
				% [node_id, expected_place_name, actual_place_name]
			)
			return _failed_result()
		var node := {
			"id": node_id,
			"kind": "place_arrival",
			"spaceId": OUTDOOR_SPACE_ID,
			"position": _point_dictionary(position),
			"regionId": str(_region_by_cell.get(_cell_key(cell), "")),
			"placeName": expected_place_name,
		}
		if not _insert_node(nodes_by_id, node):
			return _failed_result()
		terminal_ids.append(node_id)
		arrival_nodes.append({
			"id": "place_arrival_%s" % node_id.trim_prefix("arrival_"),
			"placeName": expected_place_name,
			"nodeId": node_id,
			"priority": 0,
		})

	for value in authoring.get("portals", []) as Array:
		var portal := value as Dictionary
		var portal_id := str(portal.get("id", ""))
		if portal.has("outsidePosition"):
			_fail("室内入口不得重复保存门外位置：%s" % portal_id)
			return _failed_result()
		var outside_node_id := "%s_outside" % portal_id
		var inside_node_id := "%s_inside" % portal_id
		var shared_portal := PORTAL_CATALOG.definition(portal_id)
		if shared_portal.is_empty():
			_fail("室内入口缺少玩家与居民共享门点：%s" % portal_id)
			return _failed_result()
		var outside_position := _portal_approach_position(shared_portal)
		var return_position := shared_portal.get(
			"return",
			Vector2.INF,
		) as Vector2
		var outside_cell := _point_cell(return_position)
		if (
			not outside_position.is_finite()
			or not _legal_cells.has(_cell_key(outside_cell))
			or not _movement_origin_is_safe(outside_position)
		):
			_fail(
				"门外节点不满足居民脚部碰撞净空：%s at %s"
				% [portal_id, outside_position]
			)
			return _failed_result()
		var outside_place_name := str(_place_by_cell.get(_cell_key(outside_cell), ""))
		var outside_region_id := str(_region_by_cell.get(_cell_key(outside_cell), ""))
		var inside_place_name := str(portal.get("insidePlaceName", ""))
		var inside_space_id := str(portal.get("insideSpaceId", ""))
		var inside_position := _pair_point(portal.get("insidePosition", []) as Array)
		var inside_region_id := "region_%s_entry" % portal_id
		if not indoor_bounds_by_space.has(inside_space_id):
			_fail("门内节点引用了没有合法边界的室内空间：%s" % inside_space_id)
			return _failed_result()
		var inside_bounds := indoor_bounds_by_space[inside_space_id] as Rect2
		if not inside_bounds.has_point(inside_position):
			_fail("门内节点不在室内空间边界：%s at %s" % [portal_id, inside_position])
			return _failed_result()

		var outside_node := {
			"id": outside_node_id,
			"kind": "portal_outside",
			"spaceId": OUTDOOR_SPACE_ID,
			"position": _point_dictionary(outside_position),
			"regionId": outside_region_id,
			"placeName": outside_place_name,
		}
		var inside_node := {
			"id": inside_node_id,
			"kind": "portal_inside",
			"spaceId": inside_space_id,
			"position": _point_dictionary(inside_position),
			"regionId": inside_region_id,
			"placeName": inside_place_name,
		}
		if not _insert_node(nodes_by_id, outside_node) or not _insert_node(nodes_by_id, inside_node):
			return _failed_result()
		terminal_ids.append(outside_node_id)
		arrival_nodes.append({
			"id": "place_arrival_%s" % portal_id.trim_prefix("portal_"),
			"placeName": inside_place_name,
			"nodeId": inside_node_id,
			"priority": 0,
		})
		indoor_regions.append({
			"id": inside_region_id,
			"placeName": inside_place_name,
			"spaceId": inside_space_id,
			"shape": {
				"type": "rect",
				"x": inside_bounds.position.x,
				"y": inside_bounds.position.y,
				"width": inside_bounds.size.x,
				"height": inside_bounds.size.y,
			},
		})
		connections.append({
			"id": "connection_%s" % portal_id.trim_prefix("portal_"),
			"direction": "双向",
			"movementMinutes": 1,
			"from": {
				"placeName": outside_place_name,
				"spaceId": OUTDOOR_SPACE_ID,
				"regionId": outside_region_id,
				"nodeId": outside_node_id,
				"position": _point_dictionary(outside_position),
			},
			"to": {
				"placeName": inside_place_name,
				"spaceId": inside_space_id,
				"regionId": inside_region_id,
				"nodeId": inside_node_id,
				"position": _point_dictionary(inside_position),
			},
		})

	junction_ids.sort()
	terminal_ids.sort()
	var edges_by_id := {}
	for value in authoring.get("backboneLinks", []) as Array:
		var pair := value as Array
		if pair.size() != 2:
			_fail("backboneLinks 必须为两个节点 id")
			return _failed_result()
		if not _add_edge(edges_by_id, nodes_by_id, str(pair[0]), str(pair[1])):
			return _failed_result()

	var terminal_links_per_node := int(authoring.get("terminalLinksPerNode", 0))
	if terminal_links_per_node <= 0:
		_fail("terminalLinksPerNode 必须大于 0")
		return _failed_result()
	for terminal_id in terminal_ids:
		var terminal_position := _dictionary_point(
			(nodes_by_id[terminal_id] as Dictionary).get(
				"position",
				{},
			) as Dictionary
		)
		var candidate_junction_ids := Array(junction_ids)
		candidate_junction_ids.sort_custom(
			func(left_value: Variant, right_value: Variant) -> bool:
				var left_id := String(left_value)
				var right_id := String(right_value)
				var left_position := _dictionary_point(
					(nodes_by_id[left_id] as Dictionary).get(
						"position",
						{},
					) as Dictionary
				)
				var right_position := _dictionary_point(
					(nodes_by_id[right_id] as Dictionary).get(
						"position",
						{},
					) as Dictionary
				)
				var difference := (
					terminal_position.distance_squared_to(left_position)
					- terminal_position.distance_squared_to(right_position)
				)
				if absf(difference) > 0.001:
					return difference < 0.0
				return left_id < right_id
		)
		var added_links := 0
		for junction_id_value: Variant in candidate_junction_ids:
			var junction_id := String(junction_id_value)
			var route := _route_between(
				nodes_by_id[terminal_id],
				nodes_by_id[junction_id],
			)
			if route.is_empty() or float(route.get("length", 0.0)) <= 0.01:
				continue
			if not _add_edge(
				edges_by_id,
				nodes_by_id,
				terminal_id,
				junction_id,
				route,
			):
				return _failed_result()
			added_links += 1
			if added_links >= terminal_links_per_node:
				break
		if added_links < terminal_links_per_node:
			_fail(
				"终端节点 %s 找不到足够的碰撞安全路口连接：需要 %d，实际 %d，路由格 %s"
				% [
					terminal_id,
					terminal_links_per_node,
					added_links,
					_route_cell_for_node(nodes_by_id[terminal_id]),
				]
			)
			return _failed_result()

	var nodes := nodes_by_id.values()
	nodes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	var edges := edges_by_id.values()
	edges.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	arrival_nodes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	connections.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	indoor_regions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)

	var movement_document := {
		"schemaVersion": 1,
		"worldId": "town",
		"nodes": nodes,
		"edges": edges,
		"arrivalNodes": arrival_nodes,
	}
	var connections_document := {
		"schemaVersion": 1,
		"worldId": "town",
		"connections": connections,
	}
	var indoor_regions_document := {
		"schemaVersion": 1,
		"worldId": "town",
		"regions": indoor_regions,
	}
	var result := {
		"ok": true,
		"errors": [],
		"documents": {
			"movement": movement_document,
			"connections": connections_document,
			"indoorRegions": indoor_regions_document,
			"outdoorNavigation": _outdoor_navigation_document(),
		},
	}
	_release_working_state()
	return result


func _reset() -> void:
	_release_working_state()
	_errors.clear()


func _release_working_state() -> void:
	_cell_size = 0
	_grid_width = 0
	_grid_height = 0
	_legal_cells = {}
	_region_by_cell = {}
	_place_by_cell = {}
	_collision_records.clear()
	_surface_mask = PackedByteArray()
	_route_cell_by_node_id.clear()
	_component_by_cell_key.clear()
	_cells_by_component.clear()
	_grid = null


func _failed_result() -> Dictionary:
	if _errors.is_empty():
		_errors.append("地点网络生成失败")
	var result := {"ok": false, "errors": _errors.duplicate(), "documents": {}}
	_release_working_state()
	return result


func _indoor_bounds_by_space(spaces_document: Dictionary) -> Dictionary:
	var result := {}
	for value in spaces_document.get("spaces", []) as Array:
		var space := value as Dictionary
		if str(space.get("type", "")) != "室内":
			continue
		var space_id := str(space.get("id", ""))
		var bounds := space.get("bounds", {}) as Dictionary
		var rect := Rect2(
			float(bounds.get("x", 0.0)),
			float(bounds.get("y", 0.0)),
			float(bounds.get("width", 0.0)),
			float(bounds.get("height", 0.0)),
		)
		if space_id.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		result[space_id] = rect
	return result


func _portal_approach_position(portal: Dictionary) -> Vector2:
	var door := portal.get("door", Vector2.INF) as Vector2
	var return_position := portal.get("return", Vector2.INF) as Vector2
	var trigger := PORTAL_CATALOG.exterior_trigger_rect(portal)
	if (
		not door.is_finite()
		or not return_position.is_finite()
		or not trigger.has_area()
	):
		return Vector2.INF
	var approach_direction := (return_position - door).normalized()
	if approach_direction == Vector2.ZERO:
		approach_direction = Vector2.DOWN
	var perpendicular_direction := Vector2(
		-approach_direction.y,
		approach_direction.x,
	)
	# Prefer the center line from the door toward its authored outdoor return.
	# Only fan sideways when the map collision genuinely blocks that line.
	for perpendicular_distance in range(PORTAL_APPROACH_SEARCH_RADIUS + 1):
		var signs := [0] if perpendicular_distance == 0 else [-1, 1]
		for sign_value: Variant in signs:
			var sign := int(sign_value)
			for forward_distance in range(PORTAL_APPROACH_SEARCH_RADIUS + 1):
				var candidate := (
					door
					+ approach_direction * float(forward_distance)
					+ perpendicular_direction
						* float(perpendicular_distance * sign)
				).round()
				if _portal_approach_candidate_is_valid(candidate, trigger):
					return candidate
	return Vector2.INF


func _portal_approach_candidate_is_valid(
	candidate: Vector2,
	trigger: Rect2,
) -> bool:
	return (
		MOVEMENT_CLEARANCE.BODY_ORIGIN_BOUNDS.has_point(candidate)
		and MOVEMENT_CLEARANCE.body_origin_overlaps_rect(
			candidate,
			trigger,
		)
		and _movement_origin_is_safe(candidate)
	)


func _prepare_grid(perception: Dictionary) -> bool:
	var grid_data := perception.get("grid", {}) as Dictionary
	var source_cell_size := int(grid_data.get("cellSize", 0))
	var source_grid_width := int(grid_data.get("width", 0))
	var source_grid_height := int(grid_data.get("height", 0))
	if (
		source_cell_size <= 0
		or source_grid_width <= 0
		or source_grid_height <= 0
		or source_cell_size % ROUTE_GRID_DIVISIONS != 0
	):
		_fail("感知网格尺寸无效")
		return false
	_cell_size = floori(
		float(source_cell_size) / float(ROUTE_GRID_DIVISIONS)
	)
	_grid_width = source_grid_width * ROUTE_GRID_DIVISIONS
	_grid_height = source_grid_height * ROUTE_GRID_DIVISIONS
	for region_value in perception.get("regions", []) as Array:
		var region := region_value as Dictionary
		if str(region.get("spaceId", "")) != OUTDOOR_SPACE_ID:
			continue
		var region_id := str(region.get("id", ""))
		var place_name := str(region.get("placeName", ""))
		for cell_value in (region.get("shape", {}) as Dictionary).get("cells", []) as Array:
			var pair := cell_value as Array
			var source_cell := Vector2i(int(pair[0]), int(pair[1]))
			for sub_y in ROUTE_GRID_DIVISIONS:
				for sub_x in ROUTE_GRID_DIVISIONS:
					var cell := (
						source_cell * ROUTE_GRID_DIVISIONS
						+ Vector2i(sub_x, sub_y)
					)
					var key := _cell_key(cell)
					_region_by_cell[key] = region_id
					_place_by_cell[key] = place_name
	for cell_y in _grid_height:
		for cell_x in _grid_width:
			var cell := Vector2i(cell_x, cell_y)
			if not MOVEMENT_CLEARANCE.BODY_ORIGIN_BOUNDS.has_point(
				_cell_center(cell),
			):
				continue
			_legal_cells[_cell_key(cell)] = cell
	if _legal_cells.is_empty():
		_fail("室外感知数据没有合法位置格")
		return false
	var unsafe_keys := PackedStringArray()
	for key_value: Variant in _legal_cells.keys():
		var key := String(key_value)
		var cell := _legal_cells[key] as Vector2i
		if not _movement_origin_is_safe(_cell_center(cell)):
			unsafe_keys.append(key)
	for key: String in unsafe_keys:
		_legal_cells.erase(key)
		_region_by_cell.erase(key)
		_place_by_cell.erase(key)
	if _legal_cells.is_empty():
		_fail("正式室外碰撞阻断了全部居民可行走格")
		return false
	_grid = AStar2D.new()
	for cell_value: Variant in _legal_cells.values():
		var cell := cell_value as Vector2i
		_grid.add_point(
			_cell_id(cell),
			Vector2(float(cell.x), float(cell.y)),
		)
	for cell_value: Variant in _legal_cells.values():
		var cell := cell_value as Vector2i
		for offset: Vector2i in [
			Vector2i.RIGHT,
			Vector2i.DOWN,
			Vector2i(1, 1),
			Vector2i(-1, 1),
		]:
			var neighbor := cell + offset
			if not _legal_cells.has(_cell_key(neighbor)):
				continue
			if (
				offset.x != 0
				and offset.y != 0
				and (
					not _legal_cells.has(
						_cell_key(cell + Vector2i(offset.x, 0))
					)
					or not _legal_cells.has(
						_cell_key(cell + Vector2i(0, offset.y))
					)
				)
			):
				continue
			# Both endpoints are safe, but a narrow water or collision strip may
			# still cross the short segment between them.
			if not _movement_segment_is_safe(
				_cell_center(cell),
				_cell_center(neighbor),
			):
				continue
			_grid.connect_points(
				_cell_id(cell),
				_cell_id(neighbor),
				true,
			)
	_index_connected_components()
	_retain_main_component()
	return true


func _prepare_grid_from_cache(document: Dictionary) -> bool:
	_cell_size = 0
	_grid_width = 0
	_grid_height = 0
	_legal_cells = {}
	_region_by_cell = {}
	_place_by_cell = {}
	_route_cell_by_node_id.clear()
	_component_by_cell_key.clear()
	_cells_by_component.clear()
	_grid = null
	if not WORLD_DATA_VALIDATOR.validate_outdoor_navigation_grid(
		document,
	).is_empty():
		return false
	_cell_size = int(document.get("cellSize", 0))
	_grid_width = int(document.get("width", 0))
	_grid_height = int(document.get("height", 0))
	if _cell_size <= 0 or _grid_width <= 0 or _grid_height <= 0:
		return false
	var connection_mask_by_key := {}
	for value: Variant in document.get("cells", []) as Array:
		if value is not Array or (value as Array).size() != 3:
			return false
		var pair := value as Array
		var cell := Vector2i(int(pair[0]), int(pair[1]))
		if (
			cell.x < 0
			or cell.y < 0
			or cell.x >= _grid_width
			or cell.y >= _grid_height
		):
			return false
		var key := _cell_key(cell)
		_legal_cells[key] = cell
		connection_mask_by_key[key] = int(pair[2])
	if _legal_cells.is_empty():
		return false
	_grid = AStar2D.new()
	for cell_value: Variant in _legal_cells.values():
		var cell := cell_value as Vector2i
		_grid.add_point(
			_cell_id(cell),
			Vector2(float(cell.x), float(cell.y)),
		)
	for cell_value: Variant in _legal_cells.values():
		var cell := cell_value as Vector2i
		var connection_mask := int(
			connection_mask_by_key.get(_cell_key(cell), 0)
		)
		var directions: Array[Dictionary] = [
			{"bit": 1, "offset": Vector2i.RIGHT},
			{"bit": 2, "offset": Vector2i.DOWN},
			{"bit": 4, "offset": Vector2i(1, 1)},
			{"bit": 8, "offset": Vector2i(-1, 1)},
		]
		for direction: Dictionary in directions:
			if connection_mask & int(direction["bit"]) == 0:
				continue
			var offset := direction["offset"] as Vector2i
			var neighbor := cell + offset
			if not _legal_cells.has(_cell_key(neighbor)):
				return false
			_grid.connect_points(
				_cell_id(cell),
				_cell_id(neighbor),
				true,
			)
	_index_connected_components()
	return _cells_by_component.size() == 1


func _outdoor_navigation_document() -> Dictionary:
	var cells: Array = []
	for cell_value: Variant in _legal_cells.values():
		var cell := cell_value as Vector2i
		var connection_mask := 0
		for direction: Dictionary in [
			{"bit": 1, "offset": Vector2i.RIGHT},
			{"bit": 2, "offset": Vector2i.DOWN},
			{"bit": 4, "offset": Vector2i(1, 1)},
			{"bit": 8, "offset": Vector2i(-1, 1)},
		]:
			var neighbor := cell + (direction["offset"] as Vector2i)
			if (
				_legal_cells.has(_cell_key(neighbor))
				and _grid.get_point_connections(
					_cell_id(cell),
				).has(_cell_id(neighbor))
			):
				connection_mask |= int(direction["bit"])
		cells.append([cell.x, cell.y, connection_mask])
	cells.sort_custom(
		func(left: Array, right: Array) -> bool:
			return (
				int(left[1]) < int(right[1])
				or (
					int(left[1]) == int(right[1])
					and int(left[0]) < int(right[0])
				)
			)
	)
	return {
		"schemaVersion": 1,
		"worldId": "town",
		"cellSize": _cell_size,
		"width": _grid_width,
		"height": _grid_height,
		"cells": cells,
	}


func _index_connected_components() -> void:
	_component_by_cell_key.clear()
	_cells_by_component.clear()
	var component_id := 0
	var neighbor_offsets: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
	]
	for cell_value: Variant in _legal_cells.values():
		var start := cell_value as Vector2i
		var start_key := _cell_key(start)
		if _component_by_cell_key.has(start_key):
			continue
		component_id += 1
		var queue: Array[Vector2i] = [start]
		var cursor := 0
		_component_by_cell_key[start_key] = component_id
		while cursor < queue.size():
			var cell := queue[cursor]
			cursor += 1
			for neighbor_id: int in _grid.get_point_connections(
				_cell_id(cell),
			):
				var neighbor := _id_cell(neighbor_id)
				var neighbor_key := _cell_key(neighbor)
				if (
					not _legal_cells.has(neighbor_key)
					or _component_by_cell_key.has(neighbor_key)
				):
					continue
				_component_by_cell_key[neighbor_key] = component_id
				queue.append(neighbor)
		_cells_by_component[component_id] = queue.duplicate()


func _retain_main_component() -> void:
	if _cells_by_component.size() <= 1:
		return
	var main_component_id := -1
	var main_component_size := -1
	for component_id_value: Variant in _cells_by_component.keys():
		var component_id := int(component_id_value)
		var component_size := (
			_cells_by_component[component_id] as Array
		).size()
		if component_size > main_component_size:
			main_component_id = component_id
			main_component_size = component_size
	var discarded_keys := PackedStringArray()
	for key_value: Variant in _legal_cells.keys():
		var key := String(key_value)
		if int(_component_by_cell_key.get(key, -1)) != main_component_id:
			discarded_keys.append(key)
	for key: String in discarded_keys:
		var cell := _legal_cells[key] as Vector2i
		_grid.remove_point(_cell_id(cell))
		_legal_cells.erase(key)
		_region_by_cell.erase(key)
		_place_by_cell.erase(key)
	_component_by_cell_key.clear()
	_cells_by_component.clear()
	_index_connected_components()


func _insert_node(nodes_by_id: Dictionary, node: Dictionary) -> bool:
	var node_id := str(node.get("id", ""))
	if node_id.is_empty() or nodes_by_id.has(node_id):
		_fail("路网节点 id 为空或重复：%s" % node_id)
		return false
	nodes_by_id[node_id] = node
	return true


func _add_edge(
	edges_by_id: Dictionary,
	nodes_by_id: Dictionary,
	left_id: String,
	right_id: String,
	prepared_route: Dictionary = {}
) -> bool:
	if not nodes_by_id.has(left_id) or not nodes_by_id.has(right_id) or left_id == right_id:
		_fail("固定路线引用无效节点：%s -> %s" % [left_id, right_id])
		return false
	var from_id := left_id if left_id < right_id else right_id
	var to_id := right_id if left_id < right_id else left_id
	var edge_id := "edge_%s__%s" % [from_id, to_id]
	if edges_by_id.has(edge_id):
		return true
	var route := prepared_route
	if route.is_empty():
		route = _route_between(nodes_by_id[from_id], nodes_by_id[to_id])
	elif left_id != from_id:
		var reversed := (route.get("polyline", []) as Array).duplicate(true)
		reversed.reverse()
		route = route.duplicate(true)
		route["polyline"] = reversed
	if route.is_empty() or float(route.get("length", 0.0)) <= 0.01:
		_fail("固定路线无法生成：%s -> %s" % [from_id, to_id])
		return false
	edges_by_id[edge_id] = {
		"id": edge_id,
		"fromNodeId": from_id,
		"toNodeId": to_id,
		"direction": "双向",
		"length": snappedf(float(route.get("length", 0.0)), 0.001),
		"polyline": route.get("polyline", []) as Array,
	}
	return true


func _route_between(left_node: Dictionary, right_node: Dictionary) -> Dictionary:
	var left_position := _dictionary_point(left_node.get("position", {}) as Dictionary)
	var right_position := _dictionary_point(right_node.get("position", {}) as Dictionary)
	var left_cell := _route_cell_for_node(left_node)
	var right_cell := _route_cell_for_node(right_node)
	if (
		not _legal_cells.has(_cell_key(left_cell))
		or not _legal_cells.has(_cell_key(right_cell))
	):
		return {}
	var id_path := _grid.get_id_path(
		_cell_id(left_cell),
		_cell_id(right_cell),
	)
	if id_path.is_empty():
		var connected_left := _nearest_connected_route_cell(
			left_position,
			"",
			right_cell,
		)
		if _legal_cells.has(_cell_key(connected_left)):
			left_cell = connected_left
			_route_cell_by_node_id[String(left_node.get("id", ""))] = left_cell
			id_path = _grid.get_id_path(
				_cell_id(left_cell),
				_cell_id(right_cell),
			)
	if id_path.is_empty():
		var connected_right := _nearest_connected_route_cell(
			right_position,
			"",
			left_cell,
		)
		if _legal_cells.has(_cell_key(connected_right)):
			right_cell = connected_right
			_route_cell_by_node_id[String(right_node.get("id", ""))] = right_cell
			id_path = _grid.get_id_path(
				_cell_id(left_cell),
				_cell_id(right_cell),
			)
	if id_path.is_empty():
		return {}
	var cell_path: Array[Vector2i] = []
	for point_id: int in id_path:
		cell_path.append(_id_cell(point_id))
	var simplified_cells := _simplify_cell_path(cell_path)
	var points := PackedVector2Array([left_position])
	for cell in simplified_cells:
		var center := _cell_center(cell)
		if points[-1].distance_to(center) > 0.01:
			points.append(center)
	if points[-1].distance_to(right_position) > 0.01:
		points.append(right_position)
	for index in range(1, points.size()):
		if not _movement_segment_is_safe(points[index - 1], points[index]):
			return {}
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	var serialized := []
	for point in points:
		serialized.append(_point_dictionary(point))
	return {"length": length, "polyline": serialized}


func _route_between_positions(
	left_position: Vector2,
	right_position: Vector2,
) -> Dictionary:
	var left_cell := _nearest_route_cell(left_position, "")
	var right_cell := _nearest_route_cell(right_position, "")
	if (
		not _legal_cells.has(_cell_key(left_cell))
		or not _legal_cells.has(_cell_key(right_cell))
	):
		return {}
	if left_position.distance_to(right_position) <= 0.01:
		return {
			"length": 0.0,
			"polyline": [_point_dictionary(left_position)],
		}
	var path_cache_key := "%s>%s" % [
		_cell_key(left_cell),
		_cell_key(right_cell),
	]
	var simplified_cells: Array[Vector2i] = []
	if _simplified_cell_path_cache.has(path_cache_key):
		simplified_cells.assign(
			_simplified_cell_path_cache[path_cache_key] as Array,
		)
	else:
		var id_path := _grid.get_id_path(
			_cell_id(left_cell),
			_cell_id(right_cell),
		)
		if id_path.is_empty():
			return {}
		var cell_path: Array[Vector2i] = []
		for point_id: int in id_path:
			cell_path.append(_id_cell(point_id))
		simplified_cells = _simplify_cell_path(cell_path)
		if (
			_simplified_cell_path_cache.size()
			>= CELL_PATH_CACHE_MAX_ENTRIES
		):
			_simplified_cell_path_cache.clear()
		_simplified_cell_path_cache[path_cache_key] = (
			simplified_cells.duplicate()
		)
		var reversed_cells := simplified_cells.duplicate()
		reversed_cells.reverse()
		_simplified_cell_path_cache[
			"%s>%s" % [_cell_key(right_cell), _cell_key(left_cell)]
		] = reversed_cells
	var points := PackedVector2Array([left_position])
	for cell: Vector2i in simplified_cells:
		var center := _cell_center(cell)
		if points[-1].distance_to(center) > 0.01:
			points.append(center)
	if points[-1].distance_to(right_position) > 0.01:
		points.append(right_position)
	for index in range(1, points.size()):
		if not _movement_segment_is_safe(points[index - 1], points[index]):
			return {}
	var length := 0.0
	var serialized: Array[Dictionary] = []
	for index in points.size():
		serialized.append(_point_dictionary(points[index]))
		if index > 0:
			length += points[index - 1].distance_to(points[index])
	return {
		"length": length,
		"polyline": serialized,
	}


func _simplify_cell_path(cell_path: Array[Vector2i]) -> Array[Vector2i]:
	if cell_path.size() <= 2:
		return cell_path.duplicate()
	var result: Array[Vector2i] = [cell_path[0]]
	var previous_direction := cell_path[1] - cell_path[0]
	for index in range(1, cell_path.size() - 1):
		var next_direction := cell_path[index + 1] - cell_path[index]
		if next_direction != previous_direction:
			result.append(cell_path[index])
		previous_direction = next_direction
	result.append(cell_path[-1])
	return result


func _nearest_legal_cell(
	desired: Vector2i,
	required_place_name: String = "",
) -> Vector2i:
	if (
		_legal_cells.has(_cell_key(desired))
		and (
			required_place_name.is_empty()
			or String(_place_by_cell.get(_cell_key(desired), ""))
				== required_place_name
		)
	):
		return desired
	var best_cell := Vector2i(-1, -1)
	var best_distance := 9223372036854775807
	var best_key := ""
	for cell_value in _legal_cells.values():
		var cell := cell_value as Vector2i
		if (
			not required_place_name.is_empty()
			and String(_place_by_cell.get(_cell_key(cell), ""))
				!= required_place_name
		):
			continue
		var distance := desired.distance_squared_to(cell)
		var key := _cell_key(cell)
		if (
			distance < best_distance
			or (
				distance == best_distance
				and (best_key.is_empty() or key < best_key)
			)
		):
			best_cell = cell
			best_distance = distance
			best_key = key
	return best_cell


func _route_cell_for_node(node: Dictionary) -> Vector2i:
	var node_id := String(node.get("id", ""))
	if _route_cell_by_node_id.has(node_id):
		return _route_cell_by_node_id[node_id] as Vector2i
	var cell := _nearest_route_cell(
		_dictionary_point(node.get("position", {}) as Dictionary),
		"",
	)
	_route_cell_by_node_id[node_id] = cell
	return cell


func _nearest_route_cell(
	position: Vector2,
	required_place_name: String,
) -> Vector2i:
	if not _movement_origin_is_safe(position):
		return Vector2i(-1, -1)
	var desired := _point_cell(position)
	var desired_key := _cell_key(desired)
	if (
		_legal_cells.has(desired_key)
		and (
			required_place_name.is_empty()
			or String(_place_by_cell.get(desired_key, ""))
			== required_place_name
		)
		and _movement_segment_is_safe(position, _cell_center(desired))
	):
		return desired
	var best_cell := Vector2i(-1, -1)
	var best_distance := INF
	var best_grid_distance := 9223372036854775807
	var best_key := ""
	var maximum_ring := maxi(_grid_width, _grid_height)
	for ring in range(maximum_ring + 1):
		for offset_y in range(-ring, ring + 1):
			for offset_x in range(-ring, ring + 1):
				if (
					ring > 0
					and maxi(absi(offset_x), absi(offset_y)) != ring
				):
					continue
				var cell := desired + Vector2i(offset_x, offset_y)
				var key := _cell_key(cell)
				if (
					not _legal_cells.has(key)
					or (
						not required_place_name.is_empty()
						and String(_place_by_cell.get(key, ""))
							!= required_place_name
					)
				):
					continue
				var center := _cell_center(cell)
				var distance := position.distance_squared_to(center)
				var grid_distance := desired.distance_squared_to(cell)
				var is_better := (
					distance < best_distance - 0.001
					or (
						absf(distance - best_distance) <= 0.001
						and (
							grid_distance < best_grid_distance
							or (
								grid_distance == best_grid_distance
								and (
									best_key.is_empty()
									or key < best_key
								)
							)
						)
					)
				)
				if (
					not is_better
					or not _movement_segment_is_safe(position, center)
				):
					continue
				best_cell = cell
				best_distance = distance
				best_grid_distance = grid_distance
				best_key = key
		# A cell in the next ring cannot be closer than this distance from a
		# point inside the desired cell, so the current best is globally nearest.
		var next_ring_lower_bound := (
			(float(ring) + 0.5) * float(_cell_size)
		)
		if (
			best_cell.x >= 0
			and best_distance
				<= next_ring_lower_bound * next_ring_lower_bound + 0.001
		):
			return best_cell
	return best_cell


func _nearest_connected_route_cell(
	position: Vector2,
	required_place_name: String,
	target_cell: Vector2i,
) -> Vector2i:
	if (
		not _legal_cells.has(_cell_key(target_cell))
		or not _movement_origin_is_safe(position)
	):
		return Vector2i(-1, -1)
	var desired := _point_cell(position)
	var target_component := int(
		_component_by_cell_key.get(_cell_key(target_cell), -1)
	)
	if target_component < 0:
		return Vector2i(-1, -1)
	var component_cells := (
		_cells_by_component.get(target_component, []) as Array
	)
	var best_cell := Vector2i(-1, -1)
	var best_distance := INF
	var best_grid_distance := 9223372036854775807
	var best_key := ""
	for cell_value: Variant in component_cells:
		var cell := cell_value as Vector2i
		var key := _cell_key(cell)
		if (
			not required_place_name.is_empty()
			and String(_place_by_cell.get(key, ""))
				!= required_place_name
		):
			continue
		var center := _cell_center(cell)
		var distance := position.distance_squared_to(center)
		var grid_distance := desired.distance_squared_to(cell)
		var is_better := (
			distance < best_distance - 0.001
			or (
				absf(distance - best_distance) <= 0.001
				and (
					grid_distance < best_grid_distance
					or (
						grid_distance == best_grid_distance
						and (best_key.is_empty() or key < best_key)
					)
				)
			)
		)
		if (
			not is_better
			or not _movement_segment_is_safe(position, center)
		):
			continue
		best_cell = cell
		best_distance = distance
		best_grid_distance = grid_distance
		best_key = key
	return best_cell


func _movement_origin_is_safe(position: Vector2) -> bool:
	return (
		not _surface_mask.is_empty()
		and MOVEMENT_CLEARANCE.body_origin_is_safe(
			position,
			_collision_records,
		)
		and MOVEMENT_SURFACE.body_origin_is_dry(position, _surface_mask)
	)


func _movement_segment_is_safe(from_position: Vector2, to_position: Vector2) -> bool:
	return (
		not _surface_mask.is_empty()
		and MOVEMENT_CLEARANCE.body_segment_is_safe(
			from_position,
			to_position,
			_collision_records,
		)
		and MOVEMENT_SURFACE.body_segment_is_dry(
			from_position,
			to_position,
			_surface_mask,
		)
	)


func _pair_point(pair: Array) -> Vector2:
	if pair.size() < 2:
		return Vector2.INF
	return Vector2(float(pair[0]), float(pair[1]))


func _dictionary_point(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))


func _point_dictionary(point: Vector2) -> Dictionary:
	return {"x": snappedf(point.x, 0.001), "y": snappedf(point.y, 0.001)}


func _point_cell(point: Vector2) -> Vector2i:
	return Vector2i(
		floori(point.x / float(_cell_size)),
		floori(point.y / float(_cell_size))
	)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x * _cell_size) + float(_cell_size) * 0.5,
		float(cell.y * _cell_size) + float(_cell_size) * 0.5
	)


func _cell_id(cell: Vector2i) -> int:
	return cell.y * _grid_width + cell.x


func _id_cell(point_id: int) -> Vector2i:
	return Vector2i(
		point_id % _grid_width,
		floori(float(point_id) / float(_grid_width)),
	)


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


func _fail(message: String) -> void:
	_errors.append(message)
