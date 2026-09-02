class_name TownWorldCharacterMovementQuery
extends RefCounted


const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")
const OUTDOOR_SPACE_ID := "town_outdoor"
const SOUTH_ENTRY_PLACE := "南入口"
const SOUTH_ENTRY_NODE_ID := "arrival_south_entrance"
const MAX_PUBLIC_COLLECTION_ITEMS := 262_144
const MAX_CANVAS_COMPONENT := 1_000_000
const MAX_CANONICAL_TEXT_LENGTH := 256
const MAX_RESIDENT_ID_LENGTH := 128
const CONTRACT_REVISION := "town_character_movement_v1"
const OUTDOOR_COLLISION_PATH := "res://world/maps/town/generated/collision.json"
const OUTDOOR_NAVIGATION_PATH := "res://world/maps/town/generated/navigation.json"
const OUTDOOR_OCCLUSION_PATH := "res://world/maps/town/generated/occlusion.json"
const INDOOR_AUTHORING_PATH := "res://world/data/town/source/indoor_prop_authoring.json"
const INTERIOR_ROOT := "res://world/maps/town/interiors/redesign_v2/rooms"
const ROOM_GEOMETRY := preload("res://world/maps/town/interiors/InteriorRoomGeometry.gd")
const ASSET_GEOMETRY := preload(
	"res://world/maps/town/interiors/redesign_v2/common/InteriorAssetGeometry.gd"
)
const OUTDOOR_MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const OUTDOOR_PATHFINDER := preload(
	"res://world/data/town/TownRouteNetworkBuilder.gd"
)
const INDOOR_MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownIndoorMovementClearance.gd"
)
const INDOOR_PATH_QUERY := preload(
	"res://world/data/town/TownIndoorPropPathQuery.gd"
)
const SAFE_POINT_RADIAL_STEP := 4.0
const SAFE_POINT_RADIAL_LIMIT := 256.0
const SAFE_POINT_DIRECTION_COUNT := 64
const IDLE_PARKING_MIN_DISTANCE_PX := 96.0
const IDLE_PARKING_MAX_DISTANCE_PX := 224.0
const IDLE_PORTAL_CLEARANCE_PX := 96.0
const IDLE_RESIDENT_CLEARANCE_PX := 56.0
const IDLE_PARKING_PATH_CANDIDATE_LIMIT := 16
const OUTDOOR_IDLE_PARKING_MAX_EDGE_DEPTH := 3
const OUTDOOR_IDLE_PARKING_MAX_DISTANCE_PX := 1536.0
const OUTDOOR_IDLE_PARKING_SAMPLE_STEP_PX := 64.0
const OUTDOOR_IDLE_PARKING_EDGE_SNAP_PX := 8.0
const SAVED_ROUTE_KEYS := [
	"fromPlaceName",
	"toPlaceName",
	"startNodeId",
	"arrivalNodeId",
	"nodeIds",
	"stepIds",
	"segments",
	"routeDistance",
	"connectionMinutes",
	"costGameMinutes",
	"durationMinutes",
	"minutePositions",
]
const OPTIONAL_SAVED_ROUTE_KEYS := ["runtimeStart"]
const SAVED_ROUTE_SEGMENT_KEYS := [
	"id",
	"kind",
	"fromNodeId",
	"toNodeId",
	"fromSpaceId",
	"toSpaceId",
	"length",
	"costGameMinutes",
	"polyline",
]
const SAVED_MINUTE_POSITION_KEYS := [
	"minute",
	"spaceId",
	"position",
	"regionId",
	"placeName",
	"presentationPath",
]


static func indoor_idle_parking_candidates(
	navigation: Dictionary,
	current_position: Vector2,
	portals: Array[Vector2],
	occupied: Array[Vector2],
) -> Array[Dictionary]:
	var cell_size := float(navigation.get("cellSize", 0.0))
	if navigation.is_empty() or cell_size <= 0.0:
		return []
	var candidates: Array[Dictionary] = []
	for cell_value: Variant in navigation.get("walkableCells", []) as Array:
		if not cell_value is Array or (cell_value as Array).size() != 2:
			continue
		var pair := cell_value as Array
		var candidate := (
			Vector2(float(pair[0]), float(pair[1])) + Vector2(0.5, 0.5)
		) * cell_size
		var distance := current_position.distance_to(candidate)
		if (
			distance < IDLE_PARKING_MIN_DISTANCE_PX
			or distance > IDLE_PARKING_MAX_DISTANCE_PX
			or _point_near_any(candidate, portals, IDLE_PORTAL_CLEARANCE_PX)
			or _point_near_any(candidate, occupied, IDLE_RESIDENT_CLEARANCE_PX)
		):
			continue
		candidates.append({
			"position": candidate,
			"score": absf(distance - 144.0),
		})
	candidates.sort_custom(_idle_parking_candidate_less)
	for index in mini(candidates.size(), IDLE_PARKING_PATH_CANDIDATE_LIMIT):
		var selected := candidates[index]
		var path := INDOOR_PATH_QUERY.find_path(
			navigation,
			current_position,
			selected.get("position", Vector2.ZERO) as Vector2,
		)
		if path.is_empty():
			continue
		selected["path"] = path
		return [selected]
	return []


static func outdoor_idle_parking_candidates(
	movement: Dictionary,
	current_position: Vector2,
	portals: Array[Vector2],
	occupied: Array[Vector2],
) -> Array[Dictionary]:
	var nodes_by_id: Dictionary = {}
	var matching_node_ids: Array[String] = []
	for value: Variant in movement.get("nodes", []) as Array:
		var node := value as Dictionary
		if String(node.get("spaceId", "")) != OUTDOOR_SPACE_ID:
			continue
		var node_id := String(node.get("id", ""))
		var point := _point(node.get("position", {}))
		if node_id.is_empty() or not point.is_finite():
			continue
		nodes_by_id[node_id] = node
		if point.distance_to(current_position) <= 1.0:
			matching_node_ids.append(node_id)
	var adjacency: Dictionary = {}
	var nearest_edge: Dictionary = {}
	for value: Variant in movement.get("edges", []) as Array:
		var edge := value as Dictionary
		var from_id := String(edge.get("fromNodeId", ""))
		var to_id := String(edge.get("toNodeId", ""))
		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id):
			continue
		var points := _idle_vector_path(edge.get("polyline", []) as Array)
		if points.size() < 2:
			continue
		var from_steps := adjacency.get(from_id, []) as Array
		from_steps.append({"nodeId": to_id, "path": points})
		adjacency[from_id] = from_steps
		var reverse_points := points.duplicate()
		reverse_points.reverse()
		var to_steps := adjacency.get(to_id, []) as Array
		to_steps.append({"nodeId": from_id, "path": reverse_points})
		adjacency[to_id] = to_steps
		if matching_node_ids.is_empty():
			var projection := _idle_closest_polyline_projection(
				points,
				current_position,
			)
			if (
				not projection.is_empty()
				and float(projection.get("distanceSquared", INF))
					< float(nearest_edge.get("distanceSquared", INF))
			):
				nearest_edge = {
					"fromNodeId": from_id,
					"toNodeId": to_id,
					"path": points,
					"segmentIndex": int(projection.get("segmentIndex", -1)),
					"projection": projection.get("position", Vector2.ZERO),
					"distanceSquared": float(
						projection.get("distanceSquared", INF),
					),
				}
	var queue: Array[Dictionary] = []
	for node_id: String in matching_node_ids:
		queue.append({
			"nodeId": node_id,
			"nodePath": [node_id],
			"path": [current_position],
			"depth": 0,
		})
	if matching_node_ids.is_empty():
		if (
			nearest_edge.is_empty()
			or float(nearest_edge.get("distanceSquared", INF))
				> OUTDOOR_IDLE_PARKING_EDGE_SNAP_PX \
					* OUTDOOR_IDLE_PARKING_EDGE_SNAP_PX
		):
			return []
		var edge_points: Array[Vector2] = []
		edge_points.assign(nearest_edge.get("path", []) as Array)
		var segment_index := int(nearest_edge.get("segmentIndex", -1))
		var projection := nearest_edge.get("projection", Vector2.ZERO) as Vector2
		var from_id := String(nearest_edge.get("fromNodeId", ""))
		var to_id := String(nearest_edge.get("toNodeId", ""))
		queue.append({
			"nodeId": from_id,
			"nodePath": [to_id, from_id],
			"path": _idle_path_to_polyline_endpoint(
				edge_points,
				current_position,
				segment_index,
				projection,
				false,
			),
			"depth": 1,
		})
		queue.append({
			"nodeId": to_id,
			"nodePath": [from_id, to_id],
			"path": _idle_path_to_polyline_endpoint(
				edge_points,
				current_position,
				segment_index,
				projection,
				true,
			),
			"depth": 1,
		})
	var result: Array[Dictionary] = []
	var seen_positions: Dictionary = {}
	while not queue.is_empty():
		var state := queue.pop_front() as Dictionary
		var depth := int(state.get("depth", 0))
		var state_path: Array[Vector2] = []
		state_path.assign(state.get("path", []) as Array)
		_append_outdoor_idle_path_candidates(
			result,
			seen_positions,
			state_path,
			portals,
			occupied,
		)
		if depth >= OUTDOOR_IDLE_PARKING_MAX_EDGE_DEPTH:
			continue
		var node_id := String(state.get("nodeId", ""))
		var node_path := state.get("nodePath", []) as Array
		for step_value: Variant in adjacency.get(node_id, []) as Array:
			var step := step_value as Dictionary
			var next_node_id := String(step.get("nodeId", ""))
			if node_path.has(next_node_id):
				continue
			var combined: Array[Vector2] = []
			combined.assign(state.get("path", []) as Array)
			for point_value: Variant in step.get("path", []) as Array:
				var point := point_value as Vector2
				if combined.is_empty() or not combined[-1].is_equal_approx(point):
					combined.append(point)
			var path_length := _idle_polyline_distance(combined)
			if (
				depth + 1 < OUTDOOR_IDLE_PARKING_MAX_EDGE_DEPTH
				and path_length < OUTDOOR_IDLE_PARKING_MAX_DISTANCE_PX
			):
				var next_node_path := node_path.duplicate()
				next_node_path.append(next_node_id)
				queue.append({
					"nodeId": next_node_id,
					"nodePath": next_node_path,
					"path": combined,
					"depth": depth + 1,
				})
	return result


static func _idle_closest_polyline_projection(
	points: Array[Vector2],
	position: Vector2,
) -> Dictionary:
	var result: Dictionary = {}
	var nearest_distance_squared := INF
	for index in range(points.size() - 1):
		var start := points[index]
		var finish := points[index + 1]
		var delta := finish - start
		var length_squared := delta.length_squared()
		if length_squared <= 0.0001:
			continue
		var ratio := clampf((position - start).dot(delta) / length_squared, 0.0, 1.0)
		var projected := start + delta * ratio
		var distance_squared := position.distance_squared_to(projected)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			result = {
				"segmentIndex": index,
				"position": projected,
				"distanceSquared": distance_squared,
			}
	return result


static func _idle_path_to_polyline_endpoint(
	points: Array[Vector2],
	position: Vector2,
	segment_index: int,
	projection: Vector2,
	toward_end: bool,
) -> Array[Vector2]:
	var result: Array[Vector2] = [position]
	if not result[-1].is_equal_approx(projection):
		result.append(projection)
	if toward_end:
		for index in range(segment_index + 1, points.size()):
			if not result[-1].is_equal_approx(points[index]):
				result.append(points[index])
	else:
		for index in range(segment_index, -1, -1):
			if not result[-1].is_equal_approx(points[index]):
				result.append(points[index])
	return result


static func _append_outdoor_idle_path_candidates(
	result: Array[Dictionary],
	seen_positions: Dictionary,
	path: Array[Vector2],
	portals: Array[Vector2],
	occupied: Array[Vector2],
) -> void:
	var path_length := _idle_polyline_distance(path)
	var sample_distance := IDLE_PARKING_MIN_DISTANCE_PX
	while (
		sample_distance <= path_length
		and sample_distance <= OUTDOOR_IDLE_PARKING_MAX_DISTANCE_PX
	):
		var clipped := _idle_polyline_prefix(path, sample_distance)
		if clipped.is_empty():
			break
		var candidate := clipped[-1]
		var position_key := "%d:%d" % [
			roundi(candidate.x),
			roundi(candidate.y),
		]
		if (
			not seen_positions.has(position_key)
			and not _point_near_any(candidate, portals, IDLE_PORTAL_CLEARANCE_PX)
			and not _point_near_any(candidate, occupied, IDLE_RESIDENT_CLEARANCE_PX)
		):
			seen_positions[position_key] = true
			result.append({
				"position": candidate,
				"path": clipped,
				"score": absf(sample_distance - 144.0),
			})
		sample_distance += OUTDOOR_IDLE_PARKING_SAMPLE_STEP_PX


static func _idle_vector_path(values: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for value: Variant in values:
		var point := _point(value)
		if point.is_finite():
			result.append(point)
	return result


static func _idle_polyline_distance(points: Array[Vector2]) -> float:
	var result := 0.0
	for index in range(1, points.size()):
		result += points[index - 1].distance_to(points[index])
	return result


static func _idle_polyline_prefix(
	points: Array[Vector2],
	target_distance: float,
) -> Array[Vector2]:
	if points.is_empty():
		return []
	var result: Array[Vector2] = [points[0]]
	var remaining := maxf(0.0, target_distance)
	for index in range(1, points.size()):
		var from_point := points[index - 1]
		var to_point := points[index]
		var segment_length := from_point.distance_to(to_point)
		if segment_length <= 0.000001:
			continue
		if remaining <= segment_length:
			result.append(from_point.lerp(to_point, remaining / segment_length))
			return result
		result.append(to_point)
		remaining -= segment_length
	return result


static func _idle_parking_candidate_less(left: Dictionary, right: Dictionary) -> bool:
	var left_score := float(left.get("score", INF))
	var right_score := float(right.get("score", INF))
	if not is_equal_approx(left_score, right_score):
		return left_score < right_score
	var left_position := left.get("position", Vector2.ZERO) as Vector2
	var right_position := right.get("position", Vector2.ZERO) as Vector2
	return (
		left_position.y < right_position.y
		or (
			is_equal_approx(left_position.y, right_position.y)
			and left_position.x < right_position.x
		)
	)


static func _point_near_any(
	point: Vector2,
	others: Array[Vector2],
	clearance: float,
) -> bool:
	for other: Vector2 in others:
		if point.distance_to(other) < clearance:
			return true
	return false


static func formal_south_entry(world_data_value: Variant) -> Dictionary:
	var world_data := _dictionary_or_empty(world_data_value)
	if world_data.is_empty():
		return {}
	var movement := _dictionary_or_empty(world_data.get("movementNetwork"))
	var node := {}
	for value: Variant in _bounded_array(movement.get("nodes")):
		var candidate := _dictionary_or_empty(value)
		if _canonical_text(candidate.get("id")) == SOUTH_ENTRY_NODE_ID:
			if not node.is_empty():
				return {}
			node = candidate
	if node.is_empty():
		return {}
	var place := {}
	for value: Variant in _bounded_array(world_data.get("places")):
		var candidate := _dictionary_or_empty(value)
		if _canonical_text(candidate.get("name")) == SOUTH_ENTRY_PLACE:
			if not place.is_empty():
				return {}
			place = candidate
	if place.is_empty():
		return {}
	var position := _point(node.get("position"))
	var space_id := _canonical_text(node.get("spaceId"))
	var region_id := _canonical_text(node.get("regionId"))
	var membership := _membership_at(world_data, space_id, position)
	if (
		not _finite(position)
		or space_id != OUTDOOR_SPACE_ID
		or region_id.is_empty()
		or _canonical_text(node.get("kind")) != "place_arrival"
		or _canonical_text(node.get("placeName")) != SOUTH_ENTRY_PLACE
		or _canonical_text(place.get("spaceId")) != space_id
		or _canonical_text(membership.get("regionId")) != region_id
		or _canonical_text(membership.get("placeName")) != SOUTH_ENTRY_PLACE
	):
		return {}
	return {
		"placeName": SOUTH_ENTRY_PLACE,
		"nodeId": SOUTH_ENTRY_NODE_ID,
		"spaceId": space_id,
		"regionId": region_id,
		"position": position,
	}


static func validate_formal_new_game_spawns(
	world_data_value: Variant,
	opening_config_value: Variant,
) -> PackedStringArray:
	var errors := PackedStringArray()
	var world_data := _dictionary_or_empty(world_data_value)
	var opening_config := _dictionary_or_empty(opening_config_value)
	if world_data.is_empty():
		errors.append("正式世界数据必须为非空对象")
		return errors
	if opening_config.is_empty():
		errors.append("开局配置必须为非空对象")
		return errors
	var south_entry := formal_south_entry(world_data)
	if south_entry.is_empty():
		errors.append("正式世界缺少唯一且有效的南入口出生锚点")
		return errors
	var expected_position := (
		south_entry.get("position", Vector2.INF) as Vector2
	)
	var residents_value: Variant = opening_config.get("residents")
	if not residents_value is Array:
		errors.append("开局配置 residents 必须为数组")
		return errors
	var residents := _bounded_array(residents_value)
	if residents.is_empty():
		errors.append("开局配置 residents 必须包含居民")
		return errors
	var resident_ids := {}
	for index in range(residents.size()):
		var resident := _dictionary_or_empty(residents[index])
		var resident_id := _canonical_text(resident.get("residentId"))
		if resident.is_empty() or not _resident_id_is_valid(resident_id):
			errors.append(
				"开局配置 residents[%d].residentId 必须是 1–128 个 ASCII 小写字母、数字、下划线或连字符"
				% index
			)
			continue
		if resident_ids.has(resident_id):
			errors.append("开局配置 residentId 重复：%s" % resident_id)
			continue
		resident_ids[resident_id] = true
		var state := _dictionary_or_empty(resident.get("worldState"))
		if state.is_empty():
			errors.append("居民 %s 缺少 worldState" % resident_id)
			continue
		var state_errors := validate_position_state(world_data, state)
		for error in state_errors:
			errors.append("居民 %s 的出生位置无效：%s" % [resident_id, error])
		if (
			_canonical_text(state.get("place"))
			!= _canonical_text(south_entry.get("placeName"))
			or _canonical_text(state.get("spaceId"))
			!= _canonical_text(south_entry.get("spaceId"))
			or _canonical_text(state.get("regionId"))
			!= _canonical_text(south_entry.get("regionId"))
			or _movement_point(state.get("position")) != expected_position
		):
			errors.append(
				"正式新游戏居民 %s 必须使用南入口权威出生点"
				% resident_id
			)
	return errors


static func validate_position_state(
	world_data_value: Variant,
	state_value: Variant,
) -> PackedStringArray:
	var errors := PackedStringArray()
	var world_data := _dictionary_or_empty(world_data_value)
	var state := _dictionary_or_empty(state_value)
	if world_data.is_empty():
		errors.append("正式世界数据必须为非空对象")
		return errors
	if state.is_empty():
		errors.append("人物位置状态必须为非空对象")
		return errors
	var space_id := _canonical_text(state.get("spaceId"))
	var region_id := _canonical_text(state.get("regionId"))
	var place := _canonical_text(state.get("place")) if state.has("place") else ""
	var current_place := (
		_canonical_text(state.get("currentPlace"))
		if state.has("currentPlace")
		else ""
	)
	if (
		state.has("place")
		and state.has("currentPlace")
		and (place.is_empty() or current_place.is_empty() or place != current_place)
	):
		errors.append("place 与 currentPlace 必须使用同一规范地点")
		return errors
	var place_name := _canonical_text(
		state.get("place")
		if state.has("place")
		else state.get("currentPlace")
	)
	var position_value: Variant = state.get("position")
	var position := (
		position_value as Vector2
		if position_value is Vector2
		else (
			_pair(position_value)
			if position_value is Array
			else Vector2(INF, INF)
		)
	)
	if space_id.is_empty() or region_id.is_empty() or place_name.is_empty():
		errors.append("spaceId、regionId 和 place 均为必填")
		return errors
	if not _finite(position):
		errors.append("position 必须是有限坐标")
		return errors
	var membership := _membership_at(world_data, space_id, position)
	if membership.is_empty():
		errors.append("position 不属于任何正式感知区域")
	elif (
		_canonical_text(membership.get("regionId")) != region_id
		or _canonical_text(membership.get("placeName")) != place_name
	):
		errors.append("position 与 regionId/place 语义不一致")
	if space_id == OUTDOOR_SPACE_ID:
		var collision_value: Variant = _read_json(OUTDOOR_COLLISION_PATH)
		var collision_records: Array[Dictionary] = []
		if collision_value is Array:
			collision_records = OUTDOOR_MOVEMENT_CLEARANCE.collision_records(
				collision_value as Array,
			)
		if not _point_in_outdoor_movement(
			world_data,
			position,
			collision_records,
		):
			errors.append("室外 position 不满足玩家碰撞净空")
	else:
		var navigation := _navigation_for_space(world_data, space_id)
		if navigation.is_empty() or not _point_in_grid_navigation(position, navigation):
			errors.append("室内 position 不在正式 walkable_cells 内")
	return errors


static func validate_saved_route(
	world_data: Dictionary,
	resident_id: String,
	saved: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	var action_value: Variant = saved.get("currentAction")
	var action := action_value as Dictionary if action_value is Dictionary else {}
	if not action.is_empty():
		var action_type := String(action.get("type", ""))
		if action_type == "去":
			var route_value: Variant = action.get("route")
			if route_value is Dictionary:
				var route := route_value as Dictionary
				_validate_route_shape(
					resident_id,
					route,
					errors,
				)
				_validate_route_segments(
					world_data,
					resident_id,
					route,
					errors,
				)
				_validate_route_topology(
					resident_id,
					route,
					errors,
				)
				_validate_minute_positions(
					world_data,
					resident_id,
					saved,
					action,
					route,
					errors,
				)
				_validate_runtime_route_replay(
					world_data,
					resident_id,
					action,
					route,
					errors,
				)
				if (
					typeof(action.get("durationMinutes")) == TYPE_INT
					and action.get("durationMinutes")
					!= route.get("durationMinutes")
				):
					errors.append(
						"居民 %s 的动作时长与恢复路线时长不一致"
						% resident_id
					)
			else:
				errors.append("居民 %s 的恢复路线必须是对象" % resident_id)
		elif action_type == "用道具":
			var path_points_value: Variant = action.get("pathPoints")
			if path_points_value is Array:
				_validate_same_space_points(
					world_data,
					resident_id,
					String(saved.get("spaceId", "")),
					path_points_value as Array,
					"道具路径",
					errors,
				)
			else:
				errors.append("居民 %s 的道具路径必须是数组" % resident_id)
			var return_connector_value: Variant = action.get(
				"returnRouteConnector"
			)
			if return_connector_value is Array:
				_validate_same_space_points(
					world_data,
					resident_id,
					String(saved.get("spaceId", "")),
					return_connector_value as Array,
					"道具返程连接",
					errors,
				)
			else:
				errors.append("居民 %s 的道具返程连接必须是数组" % resident_id)
	var connector_value: Variant = saved.get("routeConnector")
	if connector_value is Array:
		_validate_same_space_points(
			world_data,
			resident_id,
			String(saved.get("spaceId", "")),
			connector_value as Array,
			"返程连接",
			errors,
		)
	else:
		errors.append("居民 %s 的返程连接必须是数组" % resident_id)
	return errors


static func space_contract(world_data: Dictionary, space_id: String) -> Dictionary:
	var normalized := space_id.strip_edges()
	if normalized.is_empty():
		return {}
	var known := false
	for value: Variant in world_data.get("mapSpaces", []) as Array:
		if String((value as Dictionary).get("id", "")) == normalized:
			known = true
			break
	if not known:
		return {}
	var navigation: Dictionary = (
		_read_json(OUTDOOR_NAVIGATION_PATH)
		if normalized == OUTDOOR_SPACE_ID
		else _navigation_for_space(world_data, normalized)
	) as Dictionary
	var cell_size := int(navigation.get(
		"cellSize",
		navigation.get("cell_size", navigation.get("cellSizePx", 32)),
	))
	if cell_size <= 0:
		cell_size = 32
	var result := {
		"contractRevision": CONTRACT_REVISION,
		"spaceId": normalized,
		"navigation": navigation.duplicate(true),
		"portals": _portals_for_space(world_data, normalized),
		"presentationPolicy": {
			"positionAuthority": "world",
			"collisionBlockedReport": "diagnostic_only",
			"presentationWriteBackAllowed": false,
			"presentationRouteAllowed": false,
			"sameSpaceCatchUpMaxDistancePx": maxi(cell_size * 2, 64),
			"relocateWhen": ["space_changed", "distance_exceeded", "world_restored"],
		},
	}
	if normalized == OUTDOOR_SPACE_ID:
		result["collision"] = {
			"sourcePath": OUTDOOR_COLLISION_PATH,
			"shapes": _read_json(OUTDOOR_COLLISION_PATH),
		}
		result["occlusion"] = {
			"sourcePath": OUTDOOR_OCCLUSION_PATH,
			"entries": _read_json(OUTDOOR_OCCLUSION_PATH),
		}
		return result
	return _append_interior_contract(result, normalized)


static func nearest_safe_position(
	world_data_value: Variant,
	space_id_value: Variant,
	preferred_position_value: Variant,
) -> Dictionary:
	var world_data := _dictionary_or_empty(world_data_value)
	var space_id := _canonical_text(space_id_value)
	var preferred_position := _movement_point(preferred_position_value)
	if (
		world_data.is_empty()
		or space_id.is_empty()
		or not _finite(preferred_position)
	):
		return {}
	var resolved := (
		_nearest_safe_outdoor_position(
			world_data,
			preferred_position,
		)
		if space_id == OUTDOOR_SPACE_ID
		else _nearest_safe_indoor_position(
			world_data,
			space_id,
			preferred_position,
		)
	)
	if resolved.is_empty():
		return {}
	var position := resolved.get("position", Vector2.INF) as Vector2
	resolved["spaceId"] = space_id
	resolved["preferredPosition"] = preferred_position
	resolved["adjusted"] = not position.is_equal_approx(preferred_position)
	resolved["distance"] = position.distance_to(preferred_position)
	return resolved


static func _nearest_safe_outdoor_position(
	world_data: Dictionary,
	preferred_position: Vector2,
) -> Dictionary:
	var navigation := _read_json(OUTDOOR_NAVIGATION_PATH) as Dictionary
	var polygons := _cached_outdoor_navigation_polygons()
	var collision_records := _cached_outdoor_collision_records()
	if polygons.is_empty() or collision_records.is_empty():
		return {}
	var direct := _safe_outdoor_position_record(
		world_data,
		preferred_position,
		polygons,
		collision_records,
	)
	if not direct.is_empty():
		return direct
	var best := {}
	for ring_index in range(
		1,
		floori(SAFE_POINT_RADIAL_LIMIT / SAFE_POINT_RADIAL_STEP) + 1,
	):
		var radius := float(ring_index) * SAFE_POINT_RADIAL_STEP
		for direction_index in SAFE_POINT_DIRECTION_COUNT:
			var angle := TAU * float(direction_index) / float(
				SAFE_POINT_DIRECTION_COUNT,
			)
			var candidate := preferred_position + Vector2(
				cos(angle),
				sin(angle),
			) * radius
			var record := _safe_outdoor_position_record(
				world_data,
				candidate,
				polygons,
				collision_records,
			)
			if not record.is_empty():
				return record
	var cell_size := maxf(float(navigation.get("cellSize", 24)), 1.0)
	for polygon: PackedVector2Array in polygons:
		var bounds := _polygon_bounds(polygon)
		var first_cell := Vector2i(
			floori(bounds.position.x / cell_size),
			floori(bounds.position.y / cell_size),
		)
		var last_cell := Vector2i(
			ceili(bounds.end.x / cell_size),
			ceili(bounds.end.y / cell_size),
		)
		for cell_y in range(first_cell.y, last_cell.y + 1):
			for cell_x in range(first_cell.x, last_cell.x + 1):
				var candidate := (
					Vector2(cell_x, cell_y) + Vector2(0.5, 0.5)
				) * cell_size
				var record := _safe_outdoor_position_record(
					world_data,
					candidate,
					polygons,
					collision_records,
				)
				best = _nearer_position_record(
					preferred_position,
					best,
					record,
				)
	return best


static func _nearest_safe_indoor_position(
	world_data: Dictionary,
	space_id: String,
	preferred_position: Vector2,
) -> Dictionary:
	var navigation := _navigation_for_space(world_data, space_id)
	if navigation.is_empty():
		return {}
	var direct := _safe_indoor_position_record(
		world_data,
		space_id,
		preferred_position,
		navigation,
	)
	if not direct.is_empty():
		return direct
	var cell_size := float(
		navigation.get("cellSize", navigation.get("cell_size", 0)),
	)
	if cell_size <= 0.0:
		return {}
	var best := {}
	for value: Variant in _bounded_array(
		navigation.get(
			"walkableCells",
			navigation.get("walkable_cells"),
		),
	):
		if not _is_integral_pair(value):
			continue
		var pair := value as Array
		var cell := Vector2i(int(pair[0]), int(pair[1]))
		var candidate := INDOOR_MOVEMENT_CLEARANCE.body_origin_for_cell(
			cell,
			cell_size,
		)
		var record := _safe_indoor_position_record(
			world_data,
			space_id,
			candidate,
			navigation,
		)
		best = _nearer_position_record(
			preferred_position,
			best,
			record,
		)
	return best


static func _safe_outdoor_position_record(
	world_data: Dictionary,
	position: Vector2,
	polygons: Array[PackedVector2Array],
	collision_records: Array[Dictionary],
) -> Dictionary:
	if not _point_in_polygons(position, polygons):
		return {}
	if not OUTDOOR_MOVEMENT_CLEARANCE.body_origin_is_safe(
		position,
		collision_records,
	):
		return {}
	return _safe_position_membership_record(
		world_data,
		OUTDOOR_SPACE_ID,
		position,
	)


static func _safe_indoor_position_record(
	world_data: Dictionary,
	space_id: String,
	position: Vector2,
	navigation: Dictionary,
) -> Dictionary:
	if not _point_in_grid_navigation(position, navigation):
		return {}
	return _safe_position_membership_record(
		world_data,
		space_id,
		position,
	)


static func _safe_position_membership_record(
	world_data: Dictionary,
	space_id: String,
	position: Vector2,
) -> Dictionary:
	var membership := _membership_at(
		world_data,
		space_id,
		position,
	)
	if membership.is_empty():
		return {}
	return {
		"position": position,
		"regionId": String(membership.get("regionId", "")),
		"placeName": String(membership.get("placeName", "")),
	}


static func _nearer_position_record(
	origin: Vector2,
	current: Dictionary,
	candidate: Dictionary,
) -> Dictionary:
	if candidate.is_empty():
		return current
	if current.is_empty():
		return candidate
	var current_position := current.get("position", Vector2.INF) as Vector2
	var candidate_position := candidate.get("position", Vector2.INF) as Vector2
	var current_distance := current_position.distance_squared_to(origin)
	var candidate_distance := candidate_position.distance_squared_to(origin)
	if candidate_distance < current_distance - 0.001:
		return candidate
	if (
		is_equal_approx(candidate_distance, current_distance)
		and (
			candidate_position.y < current_position.y
			or (
				is_equal_approx(candidate_position.y, current_position.y)
				and candidate_position.x < current_position.x
			)
		)
	):
		return candidate
	return current


static func _outdoor_navigation_polygons(
	navigation: Dictionary,
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for value: Variant in navigation.get("regions", []) as Array:
		if not value is Dictionary:
			continue
		var region := value as Dictionary
		if not bool(region.get("enabled", true)):
			continue
		var shape := region.get("shape", {}) as Dictionary
		if String(shape.get("type", "polygon")) != "polygon":
			continue
		var polygon := PackedVector2Array()
		for point_value: Variant in shape.get("points", []) as Array:
			var point := _point(point_value)
			if not _finite(point):
				polygon.clear()
				break
			polygon.append(point)
		if polygon.size() >= 3:
			result.append(polygon)
	return result


static func _point_in_polygons(
	position: Vector2,
	polygons: Array[PackedVector2Array],
) -> bool:
	for polygon: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(position, polygon):
			return true
	return false


static func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for index in range(1, polygon.size()):
		bounds = bounds.expand(polygon[index])
	return bounds


static func _append_interior_contract(result: Dictionary, space_id: String) -> Dictionary:
	var room_record := _room_record(space_id)
	if room_record.is_empty():
		return result
	var room_id := String(room_record.get("roomId", ""))
	var template_room_id := String(room_record.get("templateRoomId", room_id))
	var room_root := "%s/%s" % [INTERIOR_ROOT, template_room_id]
	var geometry_path := "%s/room_geometry.json" % room_root
	var occlusion_path := "%s/wall_occlusion.json" % room_root
	var manifest_path := "%s/furniture_manifest.json" % room_root
	var layout_file := String(room_record.get("layoutFile", "layout.json"))
	var layout_path := "%s/%s" % [room_root, layout_file]
	var geometry := ROOM_GEOMETRY.load_geometry(geometry_path) as Dictionary
	var wall_occlusion := _read_json(occlusion_path) as Dictionary
	var collision_rects: Array = []
	for rect: Rect2 in ROOM_GEOMETRY.get_boundary_collision_rects(geometry):
		collision_rects.append(rect)
	result["collision"] = {
		"sourcePath": geometry_path,
		"boundaryRects": collision_rects,
	}
	result["occlusion"] = {
		"sourcePath": occlusion_path,
		"wallSegments": (wall_occlusion.get("segments", []) as Array).duplicate(true),
	}
	result["furniture"] = _furniture_contract(layout_path, manifest_path)
	result["interiorDoor"] = {
		"entryPosition": ROOM_GEOMETRY.get_primary_entry_point(geometry),
		"exitPosition": ROOM_GEOMETRY.get_primary_exit_point(geometry),
	}
	return result


static func _furniture_contract(layout_path: String, manifest_path: String) -> Dictionary:
	var layout := _read_json(layout_path) as Dictionary
	var manifest := _read_json(manifest_path) as Dictionary
	var definition_paths := {}
	for value: Variant in manifest.get("assets", []) as Array:
		var item := value as Dictionary
		definition_paths[String(item.get("asset_id", ""))] = String(item.get("definition_path", ""))
	var instances: Array[Dictionary] = []
	for value: Variant in layout.get("instances", []) as Array:
		var instance := value as Dictionary
		var asset_id := String(instance.get("asset_id", ""))
		var direction := String(instance.get("direction", "down"))
		var position := _movement_point(instance.get("position_px", []))
		var definition_path := String(definition_paths.get(asset_id, ""))
		var definition := _read_json(definition_path) as Dictionary
		var occupied_cells: Array = []
		for cell_value: Variant in (
			(definition.get("occupied_cells", {}) as Dictionary).get("cells", []) as Array
		):
			occupied_cells.append((cell_value as Array).duplicate())
		var occupied_rects: Array = []
		for rect: Rect2 in ASSET_GEOMETRY.occupied_cell_rects(definition, direction):
			occupied_rects.append(Rect2(rect.position + position, rect.size))
		var ground_polygons: Array = []
		for polygon: PackedVector2Array in ASSET_GEOMETRY.rotated_ground_contact_polygons(
			definition,
			direction,
		):
			var translated := PackedVector2Array()
			for point in polygon:
				translated.append(point + position)
			ground_polygons.append(translated)
		var occlusion_polygon := ASSET_GEOMETRY.rotated_occlusion_polygon(
			definition,
			direction,
		) as PackedVector2Array
		for index in occlusion_polygon.size():
			occlusion_polygon[index] += position
		instances.append({
			"instanceId": String(instance.get("instance_id", "")),
			"assetId": asset_id,
			"position": position,
			"direction": direction,
			"occupiedCells": occupied_cells,
			"occupiedCellRects": occupied_rects,
			"groundContactPolygons": ground_polygons,
			"occlusionPolygon": occlusion_polygon,
			"depth": {"sortMode": "foot_y", "baselineY": position.y},
			"sourceRevision": String(definition.get("source_revision", "")),
		})
	return {
		"layoutPath": layout_path,
		"manifestPath": manifest_path,
		"layoutRevision": int(layout.get("layout_revision", 0)),
		"instances": instances,
	}


static func _portals_for_space(world_data: Dictionary, space_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in world_data.get("connections", []) as Array:
		var connection := value as Dictionary
		var from := connection.get("from", {}) as Dictionary
		var to := connection.get("to", {}) as Dictionary
		if String(from.get("spaceId", "")) != space_id and String(to.get("spaceId", "")) != space_id:
			continue
		var local_endpoint := from if String(from.get("spaceId", "")) == space_id else to
		var remote_endpoint := to if String(from.get("spaceId", "")) == space_id else from
		result.append({
			"connectionId": String(connection.get("id", "")),
			"from": _endpoint_projection(from),
			"to": _endpoint_projection(to),
			"localEndpoint": _endpoint_projection(local_endpoint),
			"remoteEndpoint": _endpoint_projection(remote_endpoint),
			"fallbackPosition": _point(local_endpoint.get("position", {}) as Dictionary),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("connectionId", "")) < String(b.get("connectionId", ""))
	)
	return result


static func _validate_runtime_route_replay(
	world_data: Dictionary,
	resident_id: String,
	action: Dictionary,
	route: Dictionary,
	errors: PackedStringArray,
) -> void:
	if route.get("runtimeStart") != true:
		return
	var samples_value: Variant = route.get("minutePositions")
	var segments_value: Variant = route.get("segments")
	if (
		not samples_value is Array
		or (samples_value as Array).is_empty()
		or not (samples_value as Array)[0] is Dictionary
		or not segments_value is Array
		or (segments_value as Array).is_empty()
		or not (segments_value as Array)[0] is Dictionary
	):
		return
	var first_sample := (samples_value as Array)[0] as Dictionary
	var point := _movement_point(first_sample.get("position"))
	if not _finite(point):
		return
	var connector: Array = []
	var first_segment := (segments_value as Array)[0] as Dictionary
	# consumeRouteConnector means the stale resident-side hint is cleared after
	# accepting the action. It does not prove that the route producer actually
	# used that hint: an invalid hint legitimately falls back to authoritative
	# outdoor/indoor navigation. Replaying a fallback segment as an explicit
	# connector changes its edge identity and falsely rejects a valid save.
	if (
		action.get("consumeRouteConnector") == true
		and String(first_segment.get("id", "")) == "runtime_connector"
	):
		var first_polyline_value: Variant = first_segment.get("polyline")
		if not first_polyline_value is Array:
			return
		connector = (first_polyline_value as Array).duplicate(true)
	var rebuilt := ROUTE_QUERY.find_route_from_state(
		world_data,
		{
			"position": point,
			"spaceId": first_sample.get("spaceId"),
			"regionId": first_sample.get("regionId"),
			"currentPlace": route.get("fromPlaceName"),
		},
		String(route.get("toPlaceName", "")),
		connector,
	) as Dictionary
	# SaveCodec preserves numeric meaning, but JSON round-tripping may decode an
	# integral float (3066.0) as an int (3066).  A runtime route is still the
	# same producer result in that case; raw Variant equality would reject an
	# otherwise valid current action and make the whole session unsavable.
	if (
		rebuilt.is_empty()
		or not _runtime_route_values_match(
			_canonical_route_presentation(rebuilt),
			_canonical_route_presentation(route),
		)
	):
		# 移动中保存的路线,恢复时寻路重建可能与存档存在微小差异
		# (polyline 节点数/途经点不同但起点终点一致)。这种差异不应
		# 阻断恢复——恢复后角色会按存档路线继续,或重新规划路线。
		# 只有重建完全失败、或起点/终点不一致时才视为损坏。
		if not _runtime_route_endpoints_match(rebuilt, route):
			errors.append(
				"居民 %s 的运行时恢复路线无法由正式路线生产器重建"
				% resident_id
			)


## 移动中保存的路线,恢复时只要求起点/终点一致(允许中间路径微小差异)。
static func _runtime_route_endpoints_match(rebuilt: Dictionary, saved: Dictionary) -> bool:
	if rebuilt.is_empty() or saved.is_empty():
		return false
	var rebuilt_from := String(rebuilt.get("fromPlaceName", ""))
	var saved_from := String(saved.get("fromPlaceName", ""))
	var rebuilt_to := String(rebuilt.get("toPlaceName", ""))
	var saved_to := String(saved.get("toPlaceName", ""))
	var rebuilt_start := String(rebuilt.get("startNodeId", ""))
	var saved_start := String(saved.get("startNodeId", ""))
	var rebuilt_arrival := String(rebuilt.get("arrivalNodeId", ""))
	var saved_arrival := String(saved.get("arrivalNodeId", ""))
	return (
		not rebuilt_from.is_empty()
		and rebuilt_from == saved_from
		and not rebuilt_to.is_empty()
		and rebuilt_to == saved_to
		and rebuilt_start == saved_start
		and rebuilt_arrival == saved_arrival
	)


static func _runtime_route_values_match(
	left: Variant,
	right: Variant,
) -> bool:
	if (
		typeof(left) in [TYPE_INT, TYPE_FLOAT]
		and typeof(right) in [TYPE_INT, TYPE_FLOAT]
	):
		return _numbers_match(left, float(right))
	if left is Vector2 and right is Vector2:
		return (left as Vector2).is_equal_approx(right as Vector2)
	if left is Dictionary and right is Dictionary:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		if left_dictionary.size() != right_dictionary.size():
			return false
		for key: Variant in left_dictionary:
			if (
				not right_dictionary.has(key)
				or not _runtime_route_values_match(
					left_dictionary[key],
					right_dictionary[key],
				)
			):
				return false
		return true
	if left is Array and right is Array:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			return false
		for index in left_array.size():
			if not _runtime_route_values_match(
				left_array[index],
				right_array[index],
			):
				return false
		return true
	return typeof(left) == typeof(right) and left == right


static func _validate_route_shape(
	resident_id: String,
	route: Dictionary,
	errors: PackedStringArray,
) -> void:
	var label := "居民 %s 的恢复路线" % resident_id
	_validate_required_and_optional_keys(
		route,
		SAVED_ROUTE_KEYS,
		OPTIONAL_SAVED_ROUTE_KEYS,
		label,
		errors,
	)
	for key in ["fromPlaceName", "toPlaceName", "startNodeId", "arrivalNodeId"]:
		if _canonical_text(route.get(key)).is_empty():
			errors.append("%s.%s 必须是规范非空文本" % [label, key])
	for key in ["nodeIds", "stepIds", "segments", "minutePositions"]:
		if not route.get(key) is Array:
			errors.append("%s.%s 必须是数组" % [label, key])
	for key in ["routeDistance", "costGameMinutes"]:
		if not _is_finite_number(route.get(key)) or float(route.get(key)) < 0.0:
			errors.append("%s.%s 必须是非负有限数字" % [label, key])
	for key in ["connectionMinutes", "durationMinutes"]:
		if (
			typeof(route.get(key)) != TYPE_INT
			or int(route.get(key, -1)) < 0
		):
			errors.append("%s.%s 必须是非负整数" % [label, key])
	if (
		typeof(route.get("durationMinutes")) == TYPE_INT
		and int(route.get("durationMinutes")) <= 0
	):
		errors.append("%s.durationMinutes 必须为正整数" % label)
	for key in ["nodeIds", "stepIds"]:
		var values_value: Variant = route.get(key)
		if not values_value is Array:
			continue
		for index in (values_value as Array).size():
			if _canonical_text((values_value as Array)[index]).is_empty():
				errors.append(
					"%s.%s[%d] 必须是规范非空文本" % [label, key, index]
				)
	if route.has("runtimeStart"):
		if typeof(route.get("runtimeStart")) != TYPE_BOOL:
			errors.append("%s.runtimeStart 必须是布尔值" % label)
		elif route.get("runtimeStart") != true:
			errors.append("%s.runtimeStart 只能标记真实运行时起点" % label)
		if route.get("startNodeId") != "runtime_start":
			errors.append("%s 的运行时起点编号无效" % label)
	elif route.get("startNodeId") == "runtime_start":
		errors.append("%s 缺少 runtimeStart 标记" % label)


static func _validate_route_segments(
	world_data: Dictionary,
	resident_id: String,
	route: Dictionary,
	errors: PackedStringArray,
) -> void:
	var connections := {}
	for value: Variant in _bounded_array(world_data.get("connections")):
		if not value is Dictionary:
			continue
		var connection := value as Dictionary
		connections[String(connection.get("id", ""))] = connection
	var nodes := {}
	for value: Variant in _bounded_array(
		(world_data.get("movementNetwork", {}) as Dictionary).get("nodes")
	):
		if value is Dictionary:
			var node := value as Dictionary
			nodes[String(node.get("id", ""))] = node
	var edges := {}
	for value: Variant in _bounded_array(
		(world_data.get("movementNetwork", {}) as Dictionary).get("edges")
	):
		if value is Dictionary:
			var edge := value as Dictionary
			edges[String(edge.get("id", ""))] = edge
	var speed := float(
		(world_data.get("movementRules", {}) as Dictionary).get(
			"outdoorDistancePerGameMinute",
			0.0,
		)
	)
	var segments_value: Variant = route.get("segments")
	if not segments_value is Array:
		return
	var segments := segments_value as Array
	for index in segments.size():
		var segment_value: Variant = segments[index]
		if not segment_value is Dictionary:
			errors.append(
				"居民 %s 的恢复路线 segments[%d] 必须是对象"
				% [resident_id, index]
			)
			continue
		var segment := segment_value as Dictionary
		var label := "居民 %s 的恢复路线 segments[%d]" % [resident_id, index]
		_validate_exact_keys(segment, SAVED_ROUTE_SEGMENT_KEYS, label, errors)
		for key in [
			"id",
			"kind",
			"fromNodeId",
			"toNodeId",
			"fromSpaceId",
			"toSpaceId",
		]:
			if _canonical_text(segment.get(key)).is_empty():
				errors.append("%s.%s 必须是规范非空文本" % [label, key])
		for key in ["length", "costGameMinutes"]:
			if (
				not _is_finite_number(segment.get(key))
				or float(segment.get(key)) < 0.0
			):
				errors.append("%s.%s 必须是非负有限数字" % [label, key])
		var polyline_value: Variant = segment.get("polyline")
		if not polyline_value is Array:
			errors.append("%s.polyline 必须是数组" % label)
			continue
		var polyline := polyline_value as Array
		if polyline.size() < 2:
			errors.append("%s.polyline 至少需要两个坐标" % label)
			continue
		var kind := _canonical_text(segment.get("kind"))
		var from_space := _canonical_text(segment.get("fromSpaceId"))
		var to_space := _canonical_text(segment.get("toSpaceId"))
		if kind == "connection":
			var connection_id := _canonical_text(segment.get("id"))
			if not connections.has(connection_id):
				errors.append(
					"居民 %s 的恢复路线包含未知 portal connection：%s"
					% [resident_id, connection_id]
				)
				continue
			var connection := connections[connection_id] as Dictionary
			var formal_from := connection.get("from", {}) as Dictionary
			var formal_to := connection.get("to", {}) as Dictionary
			var forward := (
				from_space == String(formal_from.get("spaceId", ""))
				and to_space == String(formal_to.get("spaceId", ""))
				and String(segment.get("fromNodeId", ""))
				== String(formal_from.get("nodeId", ""))
				and String(segment.get("toNodeId", ""))
				== String(formal_to.get("nodeId", ""))
			)
			var reverse := (
				from_space == String(formal_to.get("spaceId", ""))
				and to_space == String(formal_from.get("spaceId", ""))
				and String(segment.get("fromNodeId", ""))
				== String(formal_to.get("nodeId", ""))
				and String(segment.get("toNodeId", ""))
				== String(formal_from.get("nodeId", ""))
			)
			if not forward and not reverse:
				errors.append(
					"居民 %s 的 portal connection 空间端点已漂移" % resident_id
				)
				continue
			var expected_from := formal_from if forward else formal_to
			var expected_to := formal_to if forward else formal_from
			var expected_start := _point(expected_from.get("position"))
			var expected_end := _point(expected_to.get("position"))
			if (
				polyline.size() != 2
				or not _finite(_movement_point(polyline[0]))
				or not _finite(_movement_point(polyline[1]))
				or _movement_point(polyline[0]).distance_to(expected_start) > 0.01
				or _movement_point(polyline[1]).distance_to(expected_end) > 0.01
			):
				errors.append(
					"居民 %s 的 portal connection 坐标端点已漂移" % resident_id
				)
			if (
				not _numbers_match(segment.get("length"), 0.0)
				or not _numbers_match(
					segment.get("costGameMinutes"),
					connection.get("movementMinutes"),
				)
			):
				errors.append(
					"居民 %s 的 portal connection 路线代价已漂移"
					% resident_id
				)
		elif kind == "route_edge":
			if from_space != to_space:
				errors.append("居民 %s 的普通路线边不得跨地图空间" % resident_id)
			_validate_same_space_points(
				world_data,
				resident_id,
				from_space,
				polyline,
				"移动路线",
				errors,
			)
			var segment_id := _canonical_text(segment.get("id"))
			var is_adaptive_segment := (
				segment_id.begins_with("adaptive_")
				and from_space == "town_outdoor"
				and to_space == "town_outdoor"
			)
			var is_runtime_segment: bool = (
				route.get("runtimeStart") == true
				and index == 0
				and segment.get("fromNodeId") == "runtime_start"
				and segment_id.begins_with("runtime_")
			)
			if is_adaptive_segment:
				var from_node := nodes.get(
					segment.get("fromNodeId"),
					{},
				) as Dictionary
				var to_node := nodes.get(
					segment.get("toNodeId"),
					{},
				) as Dictionary
				var runtime_start: bool = (
					route.get("runtimeStart") == true
					and index == 0
					and segment.get("fromNodeId") == "runtime_start"
				)
				if (
					(not runtime_start and from_node.is_empty())
					or to_node.is_empty()
					or (
						not runtime_start
						and _movement_point(polyline[0]).distance_to(
							_movement_point(from_node.get("position"))
						) > 0.01
					)
					or _movement_point(polyline[-1]).distance_to(
						_movement_point(to_node.get("position"))
					) > 0.01
				):
					errors.append(
						"居民 %s 的自适应路线端点与世界节点不一致"
						% resident_id
					)
				var adaptive_length := _polyline_length(polyline)
				if (
					not _numbers_match(
						segment.get("length"),
						adaptive_length,
					)
					or speed <= 0.0
					or not _numbers_match(
						segment.get("costGameMinutes"),
						adaptive_length / speed,
					)
				):
					errors.append(
						"居民 %s 的自适应路线长度或代价不一致"
						% resident_id
					)
			elif is_runtime_segment:
				var target_node_value: Variant = nodes.get(
					segment.get("toNodeId")
				)
				if not target_node_value is Dictionary:
					errors.append(
						"居民 %s 的运行时路线连接了未知节点"
						% resident_id
					)
				else:
					var target_node := target_node_value as Dictionary
					if (
						segment.get("toSpaceId")
						!= target_node.get("spaceId")
						or _movement_point(polyline[-1]).distance_to(
							_movement_point(target_node.get("position"))
						) > 0.01
					):
						errors.append(
							"居民 %s 的运行时路线终点与正式节点不一致"
							% resident_id
						)
				var runtime_length := _polyline_length(polyline)
				if (
					not _numbers_match(
						segment.get("length"),
						runtime_length,
					)
					or speed <= 0.0
					or not _numbers_match(
						segment.get("costGameMinutes"),
						runtime_length / speed,
					)
				):
					errors.append(
						"居民 %s 的运行时路线长度或代价不一致"
						% resident_id
					)
			elif not edges.has(segment_id):
				errors.append(
					"居民 %s 的恢复路线包含未知正式路线边：%s"
					% [resident_id, segment_id]
				)
			else:
				var edge := edges[segment_id] as Dictionary
				var edge_from := String(edge.get("fromNodeId", ""))
				var edge_to := String(edge.get("toNodeId", ""))
				var forward: bool = (
					segment.get("fromNodeId") == edge_from
					and segment.get("toNodeId") == edge_to
				)
				var reverse: bool = (
					segment.get("fromNodeId") == edge_to
					and segment.get("toNodeId") == edge_from
				)
				var expected_polyline := (
					(edge.get("polyline", []) as Array).duplicate(true)
				)
				if reverse:
					expected_polyline.reverse()
				var from_node := nodes.get(
					segment.get("fromNodeId"),
					{},
				) as Dictionary
				var to_node := nodes.get(
					segment.get("toNodeId"),
					{},
				) as Dictionary
				var edge_length := float(edge.get("length", 0.0))
				if (
					not forward and not reverse
					or from_node.is_empty()
					or to_node.is_empty()
					or from_space != from_node.get("spaceId")
					or to_space != to_node.get("spaceId")
					or not _polylines_match(polyline, expected_polyline)
					or not _numbers_match(
						segment.get("length"),
						edge_length,
					)
					or speed <= 0.0
					or not _numbers_match(
						segment.get("costGameMinutes"),
						edge_length / speed,
					)
				):
					errors.append(
						"居民 %s 的正式路线边内容与世界数据不一致：%s"
						% [resident_id, segment_id]
					)
		else:
			errors.append(
				"居民 %s 的恢复路线包含未知段类型：%s" % [resident_id, kind]
			)


static func _validate_route_topology(
	resident_id: String,
	route: Dictionary,
	errors: PackedStringArray,
) -> void:
	var node_ids_value: Variant = route.get("nodeIds")
	var step_ids_value: Variant = route.get("stepIds")
	var segments_value: Variant = route.get("segments")
	if (
		not node_ids_value is Array
		or not step_ids_value is Array
		or not segments_value is Array
	):
		return
	var node_ids := node_ids_value as Array
	var step_ids := step_ids_value as Array
	var segments := segments_value as Array
	if (
		node_ids.size() != segments.size() + 1
		or step_ids.size() != segments.size()
		or segments.is_empty()
	):
		errors.append("居民 %s 的恢复路线节点、步骤与分段数量不一致" % resident_id)
		return
	if (
		route.get("startNodeId") != node_ids[0]
		or route.get("arrivalNodeId") != node_ids[-1]
	):
		errors.append("居民 %s 的恢复路线首尾节点与节点序列不一致" % resident_id)
	var route_distance := 0.0
	var connection_minutes := 0
	var total_cost := 0.0
	var previous_end := Vector2(INF, INF)
	for index in segments.size():
		var segment_value: Variant = segments[index]
		if not segment_value is Dictionary:
			continue
		var segment := segment_value as Dictionary
		if (
			segment.get("id") != step_ids[index]
			or segment.get("fromNodeId") != node_ids[index]
			or segment.get("toNodeId") != node_ids[index + 1]
		):
			errors.append(
				"居民 %s 的恢复路线分段 %d 与节点/步骤序列不一致"
				% [resident_id, index]
			)
		var polyline_value: Variant = segment.get("polyline")
		if not polyline_value is Array or (polyline_value as Array).size() < 2:
			continue
		var polyline := polyline_value as Array
		var segment_start := _movement_point(polyline[0])
		var segment_end := _movement_point(polyline[-1])
		if (
			index > 0
			and (
				not _finite(previous_end)
				or not _finite(segment_start)
				or previous_end.distance_to(segment_start) > 0.01
			)
		):
			errors.append("居民 %s 的恢复路线分段坐标不连续" % resident_id)
		previous_end = segment_end
		var segment_cost := float(segment.get("costGameMinutes", 0.0))
		total_cost += segment_cost
		if segment.get("kind") == "route_edge":
			route_distance += float(segment.get("length", 0.0))
		elif segment.get("kind") == "connection":
			connection_minutes += int(roundf(segment_cost))
	if (
		not _numbers_match(route.get("routeDistance"), route_distance)
		or not _numbers_match(route.get("costGameMinutes"), total_cost)
		or route.get("connectionMinutes") != connection_minutes
		or (
			typeof(route.get("durationMinutes")) == TYPE_INT
			and route.get("durationMinutes")
			!= maxi(1, ceili(total_cost))
		)
	):
		errors.append("居民 %s 的恢复路线汇总数值与分段不一致" % resident_id)


static func _validate_minute_positions(
	world_data: Dictionary,
	resident_id: String,
	saved: Dictionary,
	action: Dictionary,
	route: Dictionary,
	errors: PackedStringArray,
) -> void:
	var samples_value: Variant = route.get("minutePositions")
	if not samples_value is Array:
		return
	var samples := samples_value as Array
	var duration_value: Variant = route.get("durationMinutes")
	if (
		typeof(duration_value) == TYPE_INT
		and int(duration_value) > 0
		and samples.size() != int(duration_value) + 1
	):
		errors.append(
			"居民 %s 的恢复路线逐分钟位置数量与时长不一致" % resident_id
		)
	for index in samples.size():
		var sample_value: Variant = samples[index]
		if not sample_value is Dictionary:
			errors.append(
				"居民 %s 的恢复路线 minutePositions[%d] 必须是对象"
				% [resident_id, index]
			)
			continue
		var sample := sample_value as Dictionary
		var label := (
			"居民 %s 的恢复路线 minutePositions[%d]"
			% [resident_id, index]
		)
		_validate_exact_keys(sample, SAVED_MINUTE_POSITION_KEYS, label, errors)
		if typeof(sample.get("minute")) != TYPE_INT or int(sample.get("minute", -1)) != index:
			errors.append("%s.minute 必须从 0 连续递增" % label)
		for key in ["spaceId", "regionId", "placeName"]:
			if _canonical_text(sample.get(key)).is_empty():
				errors.append("%s.%s 必须是规范非空文本" % [label, key])
		var point := _movement_point(sample.get("position"))
		if not _finite(point):
			errors.append("%s.position 必须是有限坐标" % label)
			continue
		var presentation_path_value: Variant = sample.get("presentationPath")
		if not presentation_path_value is Array:
			errors.append("%s.presentationPath 必须是数组" % label)
		else:
			var presentation_path := presentation_path_value as Array
			for path_point_value: Variant in presentation_path:
				if not _finite(_movement_point(path_point_value)):
					errors.append(
						"%s.presentationPath 必须只包含有限坐标" % label
					)
					break
			if (
				index == 0
				and (
					presentation_path.size() != 1
					or _movement_point(presentation_path[0]).distance_to(point)
						> 0.01
				)
			):
				errors.append(
					"%s.presentationPath 起始采样必须等于权威位置" % label
				)
			elif index > 0:
				var previous := samples[index - 1] as Dictionary
				var previous_point := _movement_point(
					previous.get("position")
				)
				var same_space: bool = (
					previous.get("spaceId") == sample.get("spaceId")
				)
				if same_space and (
					presentation_path.size() < 2
					or _movement_point(presentation_path[0]).distance_to(
						previous_point
					) > 0.01
					or _movement_point(presentation_path[-1]).distance_to(
						point
					) > 0.01
				):
					errors.append(
						"%s.presentationPath 未连接相邻权威采样" % label
					)
				if not same_space and not presentation_path.is_empty():
					errors.append(
						"%s.presentationPath 跨空间时必须为空" % label
					)
			if (
				not presentation_path.is_empty()
				and String(sample.get("spaceId", "")) == OUTDOOR_SPACE_ID
			):
				_validate_same_space_points(
					world_data,
					resident_id,
					OUTDOOR_SPACE_ID,
					presentation_path,
					"逐帧表现路线",
					errors,
				)
		var sample_errors := validate_position_state(
			world_data,
			{
				"position": point,
				"spaceId": sample.get("spaceId", ""),
				"regionId": sample.get("regionId", ""),
				"place": sample.get("placeName", ""),
			},
		)
		for sample_error in sample_errors:
			errors.append(
				"居民 %s 的恢复路线采样无效：%s" % [resident_id, sample_error]
			)
	var rebuilt_samples := (
		ROUTE_QUERY.rebuild_minute_positions_for_restore(
			world_data,
			route,
		) as Array
	)
	if not _route_samples_match(samples, rebuilt_samples):
		errors.append(
			"居民 %s 的恢复路线逐分钟位置无法由正式路线重建"
			% resident_id
		)
	if samples.is_empty():
		return
	var first_value: Variant = samples[0]
	var segments_value: Variant = route.get("segments")
	if (
		first_value is Dictionary
		and segments_value is Array
		and not (segments_value as Array).is_empty()
		and (segments_value as Array)[0] is Dictionary
	):
		var first_segment := (segments_value as Array)[0] as Dictionary
		var first_polyline_value: Variant = first_segment.get("polyline")
		if (
			not first_polyline_value is Array
			or (first_polyline_value as Array).is_empty()
			or _movement_point(
				(first_value as Dictionary).get("position"),
			).distance_to(
				_movement_point((first_polyline_value as Array)[0]),
			) > 0.01
			or (first_value as Dictionary).get("placeName")
			!= route.get("fromPlaceName")
		):
			errors.append("居民 %s 的恢复路线起点与首段不一致" % resident_id)
	if not _saved_position_matches_route_sample(saved, samples):
		errors.append("居民 %s 的权威位置不在恢复路线逐分钟轨迹上" % resident_id)
	var last_value: Variant = samples[-1]
	var last_segment_value: Variant = (
		(segments_value as Array)[-1]
		if segments_value is Array
		and not (segments_value as Array).is_empty()
		else null
	)
	if (
		last_value is Dictionary
		and action.get("place") is String
		and (
			(last_value as Dictionary).get("placeName") != action.get("place")
			or route.get("toPlaceName") != action.get("place")
			or not last_segment_value is Dictionary
			or not (last_segment_value as Dictionary).get("polyline") is Array
			or (
				(last_segment_value as Dictionary).get("polyline", [])
				as Array
			).is_empty()
			or _movement_point(
				(last_value as Dictionary).get("position"),
			).distance_to(
				_movement_point(
					(
						(last_segment_value as Dictionary).get(
							"polyline",
							[],
						) as Array
					)[-1]
				),
			) > 0.01
		)
	):
		errors.append("居民 %s 的恢复路线终点与动作目标不一致" % resident_id)


static func _route_samples_match(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		var left_value: Variant = left[index]
		var right_value: Variant = right[index]
		if not left_value is Dictionary or not right_value is Dictionary:
			return false
		var left_sample := left_value as Dictionary
		var right_sample := right_value as Dictionary
		if (
			left_sample.get("minute") != right_sample.get("minute")
			or left_sample.get("spaceId") != right_sample.get("spaceId")
			or left_sample.get("regionId") != right_sample.get("regionId")
			or left_sample.get("placeName") != right_sample.get("placeName")
			or _movement_point(left_sample.get("position")).distance_to(
				_movement_point(right_sample.get("position"))
			) > 0.01
			or not _polylines_match(
				left_sample.get("presentationPath", []) as Array,
				right_sample.get("presentationPath", []) as Array,
			)
		):
			return false
	return true


static func _saved_position_matches_route_sample(
	saved: Dictionary,
	samples: Array,
) -> bool:
	var saved_position := _movement_point(saved.get("position"))
	if not _finite(saved_position):
		return false
	for sample_value: Variant in samples:
		if not sample_value is Dictionary:
			continue
		var sample := sample_value as Dictionary
		if (
			_movement_point(sample.get("position")).distance_to(saved_position)
			<= 0.01
			and sample.get("spaceId") == saved.get("spaceId")
			and sample.get("regionId") == saved.get("regionId")
			and sample.get("placeName") == saved.get("currentPlace")
		):
			return true
	return false


static func _validate_same_space_points(
	world_data: Dictionary,
	resident_id: String,
	space_id: String,
	points: Array,
	label: String,
	errors: PackedStringArray,
) -> void:
	if points.is_empty():
		return
	var outdoor_collision_records: Array[Dictionary] = []
	if space_id == OUTDOOR_SPACE_ID:
		var collision_value: Variant = _read_json(
			OUTDOOR_COLLISION_PATH
		)
		if collision_value is Array:
			outdoor_collision_records = (
				OUTDOOR_MOVEMENT_CLEARANCE.collision_records(
					collision_value as Array,
				) as Array[Dictionary]
			)
	for point_value: Variant in points:
		var point := _movement_point(point_value)
		var legal := (
			_point_in_outdoor_movement(
				world_data,
				point,
				outdoor_collision_records,
			)
			if space_id == OUTDOOR_SPACE_ID
			else _point_in_grid_navigation(
				point,
				_navigation_for_space(world_data, space_id),
			)
		)
		if not _finite(point) or not legal:
			errors.append(
				"居民 %s 的%s包含不在 %s 正式导航内的坐标"
				% [resident_id, label, space_id]
			)
			return
	if space_id != OUTDOOR_SPACE_ID:
		return
	for index in range(1, points.size()):
		var previous := _movement_point(points[index - 1])
		var current := _movement_point(points[index])
		if not OUTDOOR_MOVEMENT_CLEARANCE.body_segment_is_safe(
			previous,
			current,
			outdoor_collision_records,
		):
			var clearance := (
				OUTDOOR_MOVEMENT_CLEARANCE.minimum_body_segment_clearance(
					previous,
					current,
					outdoor_collision_records,
				)
			)
			errors.append(
				(
					"居民 %s 的%s第 %d 段穿过室外正式碰撞"
					+ "（collisionId=%s，clearancePx=%s）"
				)
				% [
					resident_id,
					label,
					index - 1,
					clearance.get("collisionId", ""),
					clearance.get("clearancePx", ""),
				]
			)
			return
	var outdoor_points := PackedVector2Array()
	for point_value: Variant in points:
		outdoor_points.append(_movement_point(point_value))
	if not OUTDOOR_PATHFINDER.outdoor_polyline_is_navigable(outdoor_points):
		errors.append("居民 %s 的%s穿过正式水域或离开室外连通区域" % [resident_id, label])


static func _point_in_outdoor_movement(
	_world_data: Dictionary,
	position: Vector2,
	collision_records: Array[Dictionary],
) -> bool:
	if not _finite(position):
		return false
	if not OUTDOOR_MOVEMENT_CLEARANCE.BODY_ORIGIN_BOUNDS.has_point(position):
		return false
	return (
		not collision_records.is_empty()
		and OUTDOOR_MOVEMENT_CLEARANCE.body_origin_is_safe(
			position,
			collision_records,
		)
		and OUTDOOR_PATHFINDER.outdoor_position_is_navigable(position)
	)


static func _movement_point(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Dictionary:
		return _point(value)
	return _pair(value)


static func _polyline_length(values: Array) -> float:
	var total := 0.0
	for index in range(1, values.size()):
		var previous := _movement_point(values[index - 1])
		var current := _movement_point(values[index])
		if not _finite(previous) or not _finite(current):
			return INF
		total += previous.distance_to(current)
	return snappedf(total, 0.001)


static func _polylines_match(left: Array, right: Array) -> bool:
	var canonical_left := _erase_retraced_polyline(left)
	var canonical_right := _erase_retraced_polyline(right)
	if canonical_left.size() != canonical_right.size():
		return false
	for index in canonical_left.size():
		var left_point := _movement_point(canonical_left[index])
		var right_point := _movement_point(canonical_right[index])
		if (
			not _finite(left_point)
			or not _finite(right_point)
			or left_point.distance_to(right_point) > 0.01
		):
			return false
	return true


static func _canonical_route_presentation(route: Dictionary) -> Dictionary:
	var canonical := route.duplicate(true)
	var samples_value: Variant = canonical.get("minutePositions")
	if not samples_value is Array:
		return canonical
	var samples := samples_value as Array
	for index in samples.size():
		if not samples[index] is Dictionary:
			continue
		var sample := samples[index] as Dictionary
		var path_value: Variant = sample.get("presentationPath")
		if path_value is Array:
			sample["presentationPath"] = _erase_retraced_polyline(
				path_value as Array,
			)
			samples[index] = sample
	canonical["minutePositions"] = samples
	return canonical


static func _erase_retraced_polyline(points: Array) -> Array:
	var result: Array = []
	for point_value: Variant in points:
		var point := _movement_point(point_value)
		if not _finite(point):
			return points.duplicate(true)
		var repeated_index := -1
		for index in range(result.size() - 1, -1, -1):
			if _movement_point(result[index]).distance_to(point) <= 0.001:
				repeated_index = index
				break
		if repeated_index >= 0:
			result.resize(repeated_index + 1)
			continue
		result.append(point_value)
	return result


static func _navigation_for_space(world_data: Dictionary, space_id: String) -> Dictionary:
	var result := {}
	for value: Variant in _bounded_array(world_data.get("indoorNavigation")):
		var navigation := _dictionary_or_empty(value)
		if _canonical_text(navigation.get("spaceId")) == space_id:
			if not result.is_empty():
				return {}
			result = navigation
	return result


static func _point_in_grid_navigation(position: Vector2, navigation: Dictionary) -> bool:
	if not _finite(position):
		return false
	if (
		_aliases_conflict(navigation, "cellSize", "cell_size")
		or _aliases_conflict(navigation, "walkableCells", "walkable_cells")
	):
		return false
	var cell_size_value: Variant = navigation.get("cellSize", navigation.get("cell_size"))
	if not _is_positive_integer(cell_size_value):
		return false
	var cell_size := int(cell_size_value)
	var cell := Vector2i(floori(position.x / float(cell_size)), floori(position.y / float(cell_size)))
	for value: Variant in _bounded_array(
		navigation.get("walkableCells", navigation.get("walkable_cells"))
	):
		if _is_integral_pair(value):
			var pair := value as Array
			if Vector2i(int(pair[0]), int(pair[1])) == cell:
				return true
	return false


static func _membership_at(world_data: Dictionary, space_id: String, position: Vector2) -> Dictionary:
	var result := {}
	for value: Variant in _bounded_array(world_data.get("perceptionRegions")):
		var region := _dictionary_or_empty(value)
		if _canonical_text(region.get("spaceId")) != space_id:
			continue
		if _position_in_shape(position, _dictionary_or_empty(region.get("shape"))):
			var region_id := _canonical_text(region.get("id"))
			var place_name := _canonical_text(region.get("placeName"))
			if region_id.is_empty() or place_name.is_empty():
				return {}
			if not result.is_empty():
				return {}
			result = {
				"regionId": region_id,
				"placeName": place_name,
			}
	return result


static func _shape_is_valid(shape: Dictionary) -> bool:
	var shape_type := _canonical_text(shape.get("type"))
	if shape_type == "grid_cells":
		if not _is_positive_integer(shape.get("cellSize")):
			return false
		var cells_value: Variant = shape.get("cells")
		if not cells_value is Array:
			return false
		var cells := cells_value as Array
		if cells.is_empty() or cells.size() > MAX_PUBLIC_COLLECTION_ITEMS:
			return false
		for value: Variant in cells:
			if not _is_integral_pair(value):
				return false
		return true
	if shape_type == "rect":
		for key in ["x", "y", "width", "height"]:
			if not _is_finite_number(shape.get(key)):
				return false
		return (
			float(shape.get("width")) > 0.0
			and float(shape.get("height")) > 0.0
		)
	return false


static func _position_in_shape(position: Vector2, shape: Dictionary) -> bool:
	if not _finite(position):
		return false
	var shape_type := _canonical_text(shape.get("type"))
	if shape_type == "grid_cells":
		var cell_size_value: Variant = shape.get("cellSize")
		if not _is_positive_integer(cell_size_value):
			return false
		var cell_size := int(cell_size_value)
		var expected := Vector2i(floori(position.x / float(cell_size)), floori(position.y / float(cell_size)))
		for value: Variant in _bounded_array(shape.get("cells")):
			if _is_integral_pair(value):
				var pair := value as Array
				if Vector2i(int(pair[0]), int(pair[1])) == expected:
					return true
		return false
	if shape_type == "rect":
		for key in ["x", "y", "width", "height"]:
			if not _is_finite_number(shape.get(key)):
				return false
		if float(shape.get("width")) <= 0.0 or float(shape.get("height")) <= 0.0:
			return false
		return Rect2(
			float(shape.get("x")),
			float(shape.get("y")),
			float(shape.get("width")),
			float(shape.get("height")),
		).has_point(position)
	return false


static func _room_record(space_id: String) -> Dictionary:
	var authoring := _read_json(INDOOR_AUTHORING_PATH) as Dictionary
	for value: Variant in authoring.get("rooms", []) as Array:
		var room := value as Dictionary
		if String(room.get("spaceId", "")) == space_id:
			return room
	return {}


static func _endpoint_projection(endpoint: Dictionary) -> Dictionary:
	return {
		"spaceId": String(endpoint.get("spaceId", "")),
		"regionId": String(endpoint.get("regionId", "")),
		"placeName": String(endpoint.get("placeName", "")),
		"position": _point(endpoint.get("position", {}) as Dictionary),
	}


# 地图语义数据是只读静态内容，按路径缓存解析结果（同 TownWorldRouteQuery 的
# 静态缓存写法），避免抵达候选搜索等热路径反复读盘解析。调用方不得修改返回值。
static var _json_cache: Dictionary = {}
static var _outdoor_navigation_polygons_cache: Array[PackedVector2Array] = []
static var _outdoor_navigation_polygons_cached := false
static var _outdoor_collision_records_cache: Array[Dictionary] = []
static var _outdoor_collision_records_cached := false


static func _cached_outdoor_navigation_polygons() -> Array[PackedVector2Array]:
	if not _outdoor_navigation_polygons_cached:
		_outdoor_navigation_polygons_cache = _outdoor_navigation_polygons(
			_read_json(OUTDOOR_NAVIGATION_PATH) as Dictionary,
		)
		_outdoor_navigation_polygons_cached = true
	return _outdoor_navigation_polygons_cache


static func _cached_outdoor_collision_records() -> Array[Dictionary]:
	if not _outdoor_collision_records_cached:
		var collision_value: Variant = _read_json(OUTDOOR_COLLISION_PATH)
		if collision_value is Array:
			_outdoor_collision_records_cache = (
				OUTDOOR_MOVEMENT_CLEARANCE.collision_records(
					collision_value as Array,
				) as Array[Dictionary]
			)
		_outdoor_collision_records_cached = true
	return _outdoor_collision_records_cache


static func _read_json(path: String) -> Variant:
	if path.is_empty():
		return {}
	if _json_cache.has(path):
		return _json_cache[path]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result: Variant = parsed if parsed != null else {}
	_json_cache[path] = result
	return result


static func _validate_exact_keys(
	value: Dictionary,
	expected: Array,
	label: String,
	errors: PackedStringArray,
) -> void:
	for key_value: Variant in value:
		if not key_value is String or not expected.has(key_value):
			errors.append("%s 包含未知字段：%s" % [label, str(key_value)])
	for key_value: Variant in expected:
		if not value.has(key_value):
			errors.append("%s 缺少字段：%s" % [label, str(key_value)])


static func _validate_required_and_optional_keys(
	value: Dictionary,
	required: Array,
	optional: Array,
	label: String,
	errors: PackedStringArray,
) -> void:
	var allowed := required.duplicate()
	allowed.append_array(optional)
	for key_value: Variant in value:
		if not key_value is String or not allowed.has(key_value):
			errors.append("%s 包含未知字段：%s" % [label, str(key_value)])
	for key_value: Variant in required:
		if not value.has(key_value):
			errors.append("%s 缺少字段：%s" % [label, str(key_value)])


static func _numbers_match(left: Variant, right: float) -> bool:
	return (
		_is_finite_number(left)
		and is_finite(right)
		and absf(float(left) - right) <= 0.01
	)


static func _point(value: Variant) -> Vector2:
	if not value is Dictionary:
		return Vector2(INF, INF)
	var point := value as Dictionary
	if not _is_finite_number(point.get("x")) or not _is_finite_number(point.get("y")):
		return Vector2(INF, INF)
	return Vector2(float(point.get("x")), float(point.get("y")))


static func _pair(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2(INF, INF)
	var pair := value as Array
	if not _is_finite_number(pair[0]) or not _is_finite_number(pair[1]):
		return Vector2(INF, INF)
	return Vector2(float(pair[0]), float(pair[1]))


static func _finite(value: Vector2) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and absf(value.x) <= MAX_CANVAS_COMPONENT
		and absf(value.y) <= MAX_CANVAS_COMPONENT
	)


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


static func _bounded_array(value: Variant) -> Array:
	if not value is Array:
		return []
	var values := value as Array
	return values if values.size() <= MAX_PUBLIC_COLLECTION_ITEMS else []


static func _canonical_text(value: Variant) -> String:
	if not value is String:
		return ""
	var text := value as String
	if (
		text.is_empty()
		or text.length() > MAX_CANONICAL_TEXT_LENGTH
		or text != text.strip_edges()
	):
		return ""
	for index in range(text.length()):
		var codepoint := text.unicode_at(index)
		if (
			codepoint < 32
			or (codepoint >= 127 and codepoint <= 159)
			or codepoint == 0x2028
			or codepoint == 0x2029
		):
			return ""
	return text


static func _resident_id_is_valid(resident_id: String) -> bool:
	if resident_id.is_empty() or resident_id.length() > MAX_RESIDENT_ID_LENGTH:
		return false
	for index in range(resident_id.length()):
		var codepoint := resident_id.unicode_at(index)
		var is_ascii_lowercase := codepoint >= 97 and codepoint <= 122
		var is_ascii_digit := codepoint >= 48 and codepoint <= 57
		if (
			not is_ascii_lowercase
			and not is_ascii_digit
			and codepoint != 95
			and codepoint != 45
		):
			return false
	return true


static func _aliases_conflict(
	record: Dictionary,
	primary_key: String,
	secondary_key: String,
) -> bool:
	return (
		record.has(primary_key)
		and record.has(secondary_key)
		and record.get(primary_key) != record.get(secondary_key)
	)


static func _is_finite_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and absf(float(value)) <= MAX_CANVAS_COMPONENT
	)


static func _is_integer_number(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) == floor(float(value))


static func _is_integral_pair(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	var pair := value as Array
	return _is_integer_number(pair[0]) and _is_integer_number(pair[1])


static func _is_positive_integer(value: Variant) -> bool:
	return (
		_is_integer_number(value)
		and float(value) > 0.0
		and float(value) <= MAX_CANVAS_COMPONENT
	)
