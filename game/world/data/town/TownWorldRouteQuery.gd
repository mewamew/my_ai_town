extends RefCounted

const INDOOR_PATH_QUERY := preload(
	"res://world/data/town/TownIndoorPropPathQuery.gd"
)
const OUTDOOR_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const OUTDOOR_PATHFINDER := preload(
	"res://world/data/town/TownRouteNetworkBuilder.gd"
)
const OUTDOOR_SPACE_ID := "town_outdoor"
const OUTDOOR_COLLISION_PATH := "res://world/maps/town/generated/collision.json"
const OUTDOOR_ROUTE_RECOVERY_DISTANCE := 120.0
const COST_EPSILON := 0.000001
const DIRECT_ROUTE_CACHE_MAX_ENTRIES := 512

static var _outdoor_collision_records: Array[Dictionary] = []
static var _direct_route_cache: Dictionary = {}
static var _place_route_graph_cache: Dictionary = {}


static func _direct_route_cache_key(
	data: Dictionary,
	node_id: String,
	target_place: String,
) -> String:
	var movement := data.get("movementNetwork", {}) as Dictionary
	return "%s:%s:%s:%d:%d:%s:%s" % [
		str(data.get("worldId", "")),
		str(data.get("schemaVersion", "")),
		str(data.get("dataVersion", "")),
		(movement.get("nodes", []) as Array).size(),
		(movement.get("edges", []) as Array).size(),
		node_id,
		target_place,
	]


static func outdoor_polyline_is_safe(values: Array) -> bool:
	var points := _variant_points(values)
	if points.is_empty():
		return false
	var collision_records := _outdoor_collision_records_for_query()
	if collision_records.is_empty():
		return false
	for point: Vector2 in points:
		if not OUTDOOR_CLEARANCE.body_origin_is_safe(
			point,
			collision_records,
		):
			return false
	for index in range(1, points.size()):
		if not OUTDOOR_CLEARANCE.body_segment_is_safe(
			points[index - 1],
			points[index],
			collision_records,
		):
			return false
	return OUTDOOR_PATHFINDER.outdoor_polyline_is_navigable(
		PackedVector2Array(points),
	)


static func outdoor_position_has_clearance(
	position: Vector2,
	required_clearance: float,
) -> bool:
	var collision_records := _outdoor_collision_records_for_query()
	return (
		not collision_records.is_empty()
		and OUTDOOR_CLEARANCE.body_origin_has_clearance(
			position,
			collision_records,
			required_clearance,
		)
	)


static func outdoor_position_connects_to_network(
	data: Dictionary,
	position: Vector2,
) -> bool:
	if data.is_empty() or not position.is_finite():
		return false
	if not OUTDOOR_PATHFINDER.outdoor_position_is_navigable(position):
		return false
	var movement := data.get("movementNetwork", {}) as Dictionary
	var nodes := movement.get("nodes", []) as Array
	var edges := movement.get("edges", []) as Array
	if not _matching_node_id(nodes, position, OUTDOOR_SPACE_ID).is_empty():
		return true
	var runtime_edges: Array = []
	return _connect_matching_edges(
		runtime_edges,
		edges,
		"runtime_clearance_probe",
		position,
	) > 0


static func outdoor_connector_is_safe(
	position: Vector2,
	network_position: Vector2,
) -> bool:
	if not position.is_finite() or not network_position.is_finite():
		return false
	return outdoor_polyline_is_safe([position, network_position])


static func find_route(data: Dictionary, from_place_name: String, to_place_name: String) -> Dictionary:
	if data.is_empty() or from_place_name.is_empty() or to_place_name.is_empty():
		return {}
	var movement := data.get("movementNetwork", {}) as Dictionary
	var nodes := movement.get("nodes", []) as Array
	var arrivals := movement.get("arrivalNodes", []) as Array
	var nodes_by_id := {}
	for node_value in nodes:
		var node := node_value as Dictionary
		nodes_by_id[str(node.get("id", ""))] = node
	var arrivals_by_place := {}
	for arrival_value in arrivals:
		var arrival := arrival_value as Dictionary
		var place_name := str(arrival.get("placeName", ""))
		var place_arrivals := arrivals_by_place.get(place_name, []) as Array
		place_arrivals.append(arrival)
		arrivals_by_place[place_name] = place_arrivals
	var start_arrivals := arrivals_by_place.get(from_place_name, []) as Array
	var goal_arrivals := arrivals_by_place.get(to_place_name, []) as Array
	if start_arrivals.is_empty() or goal_arrivals.is_empty():
		return {}
	start_arrivals.sort_custom(_arrival_less)
	goal_arrivals.sort_custom(_arrival_less)
	if from_place_name == to_place_name:
		var node_id := str((start_arrivals[0] as Dictionary).get("nodeId", ""))
		return _zero_route(from_place_name, node_id, nodes_by_id.get(node_id, {}) as Dictionary)

	var adjacency := _build_adjacency(data, nodes_by_id)
	var distances := {}
	var signatures := {}
	var previous := {}
	var active := {}
	for arrival_value in start_arrivals:
		var arrival := arrival_value as Dictionary
		var node_id := str(arrival.get("nodeId", ""))
		if not nodes_by_id.has(node_id):
			continue
		var signature := "start:%s:%s" % [arrival.get("id", ""), node_id]
		if (
			not distances.has(node_id)
			or signature < str(signatures.get(node_id, ""))
		):
			distances[node_id] = 0.0
			signatures[node_id] = signature
			active[node_id] = true

	while not active.is_empty():
		var current_id := _best_active_node(active, distances, signatures)
		active.erase(current_id)
		var current_cost := float(distances.get(current_id, INF))
		var current_signature := str(signatures.get(current_id, ""))
		for step_value in adjacency.get(current_id, []) as Array:
			var step := step_value as Dictionary
			var neighbor_id := str(step.get("toNodeId", ""))
			var candidate_cost := current_cost + float(step.get("costGameMinutes", INF))
			var candidate_signature := "%s|%s>%s" % [
				current_signature,
				step.get("id", ""),
				neighbor_id,
			]
			var known_cost := float(distances.get(neighbor_id, INF))
			var known_signature := str(signatures.get(neighbor_id, ""))
			if (
				candidate_cost < known_cost - COST_EPSILON
				or (
					absf(candidate_cost - known_cost) <= COST_EPSILON
					and (known_signature.is_empty() or candidate_signature < known_signature)
				)
			):
				distances[neighbor_id] = candidate_cost
				signatures[neighbor_id] = candidate_signature
				previous[neighbor_id] = {"fromNodeId": current_id, "step": step}
				active[neighbor_id] = true

	var goal := _best_goal(goal_arrivals, distances, signatures)
	if goal.is_empty():
		return {}
	var goal_node_id := str(goal.get("nodeId", ""))
	var reversed_steps := []
	var node_id := goal_node_id
	while previous.has(node_id):
		var predecessor := previous[node_id] as Dictionary
		reversed_steps.append((predecessor.get("step", {}) as Dictionary).duplicate(true))
		node_id = str(predecessor.get("fromNodeId", ""))
	reversed_steps.reverse()
	var route_start_node_id := node_id
	var steps := _adaptive_outdoor_segments(
		reversed_steps,
		nodes_by_id,
		float(
			(data.get("movementRules", {}) as Dictionary).get(
				"outdoorDistancePerGameMinute",
				0.0,
			)
		),
	)
	if not reversed_steps.is_empty() and steps.is_empty():
		return {}
	var node_ids := [route_start_node_id]
	var step_ids := []
	var route_distance := 0.0
	var connection_minutes := 0
	var total_cost := 0.0
	for step_value in steps:
		var step := step_value as Dictionary
		node_ids.append(str(step.get("toNodeId", "")))
		step_ids.append(str(step.get("id", "")))
		if str(step.get("kind", "")) == "route_edge":
			route_distance += float(step.get("length", 0.0))
		else:
			connection_minutes += int(roundf(float(step.get("costGameMinutes", 0.0))))
		total_cost += float(step.get("costGameMinutes", 0.0))
	var duration_minutes := maxi(1, ceili(total_cost))
	var result := {
		"fromPlaceName": from_place_name,
		"toPlaceName": to_place_name,
		"startNodeId": str(node_ids[0]),
		"arrivalNodeId": goal_node_id,
		"nodeIds": node_ids,
		"stepIds": step_ids,
		"segments": steps,
		"routeDistance": snappedf(route_distance, 0.001),
		"connectionMinutes": connection_minutes,
		"costGameMinutes": snappedf(total_cost, 0.001),
		"durationMinutes": duration_minutes,
	}
	result["minutePositions"] = _minute_positions(result, data, nodes_by_id)
	return result


static func place_route_exists(
	data: Dictionary,
	from_place_name: String,
	to_place_name: String,
) -> bool:
	if data.is_empty() or from_place_name.is_empty() or to_place_name.is_empty():
		return false
	if from_place_name == to_place_name:
		return true
	var world_key := "%s:%s:%s" % [
		str(data.get("worldId", "")),
		str(data.get("schemaVersion", "")),
		str(data.get("dataVersion", "")),
	]
	var graph := _place_route_graph_cache.get(world_key, {}) as Dictionary
	if graph.is_empty():
		graph = _build_place_route_graph(data)
		_place_route_graph_cache[world_key] = graph
	var start_components := graph.get("places", {}).get(from_place_name, []) as Array
	var goal_components := graph.get("places", {}).get(to_place_name, []) as Array
	for component_value in start_components:
		if goal_components.has(component_value):
			return true
	return false


static func _build_place_route_graph(data: Dictionary) -> Dictionary:
	var movement := data.get("movementNetwork", {}) as Dictionary
	var adjacency := {}
	for node_value in movement.get("nodes", []) as Array:
		var node := node_value as Dictionary
		adjacency[str(node.get("id", ""))] = []
	for edge_value in movement.get("edges", []) as Array:
		var edge := edge_value as Dictionary
		_append_undirected_route_link(
			adjacency,
			str(edge.get("fromNodeId", "")),
			str(edge.get("toNodeId", "")),
		)
	for connection_value in data.get("connections", []) as Array:
		var connection := connection_value as Dictionary
		_append_undirected_route_link(
			adjacency,
			str((connection.get("from", {}) as Dictionary).get("nodeId", "")),
			str((connection.get("to", {}) as Dictionary).get("nodeId", "")),
		)
	var component_by_node := {}
	var component_index := 0
	for node_id_value in adjacency:
		var node_id := str(node_id_value)
		if component_by_node.has(node_id):
			continue
		var pending: Array[String] = [node_id]
		component_by_node[node_id] = component_index
		var cursor := 0
		while cursor < pending.size():
			var current_id := pending[cursor]
			cursor += 1
			for next_value in adjacency.get(current_id, []) as Array:
				var next_id := str(next_value)
				if component_by_node.has(next_id):
					continue
				component_by_node[next_id] = component_index
				pending.append(next_id)
		component_index += 1
	var places := {}
	for arrival_value in movement.get("arrivalNodes", []) as Array:
		var arrival := arrival_value as Dictionary
		var place_name := str(arrival.get("placeName", ""))
		var node_id := str(arrival.get("nodeId", ""))
		if place_name.is_empty() or not component_by_node.has(node_id):
			continue
		var components := places.get(place_name, []) as Array
		var component: Variant = component_by_node[node_id]
		if not components.has(component):
			components.append(component)
		places[place_name] = components
	return {"places": places}


static func _append_undirected_route_link(
	adjacency: Dictionary,
	from_node: String,
	to_node: String,
) -> void:
	if (
		from_node.is_empty()
		or to_node.is_empty()
		or not adjacency.has(from_node)
		or not adjacency.has(to_node)
	):
		return
	(adjacency[from_node] as Array).append(to_node)
	(adjacency[to_node] as Array).append(from_node)


static func _adaptive_outdoor_segments(
	steps: Array,
	nodes_by_id: Dictionary,
	outdoor_speed: float,
) -> Array:
	if outdoor_speed <= 0.0:
		return []
	var result: Array = []
	var cursor := 0
	while cursor < steps.size():
		var step := steps[cursor] as Dictionary
		if not _is_outdoor_route_step(step):
			result.append(step.duplicate(true))
			cursor += 1
			continue
		var chain_start_id := String(step.get("fromNodeId", ""))
		var chain_finish_id := String(step.get("toNodeId", ""))
		var chain_finish := cursor + 1
		while chain_finish < steps.size():
			var candidate := steps[chain_finish] as Dictionary
			if not _is_outdoor_route_step(candidate):
				break
			chain_finish_id = String(candidate.get("toNodeId", ""))
			chain_finish += 1
		if (
			not nodes_by_id.has(chain_start_id)
			or not nodes_by_id.has(chain_finish_id)
		):
			return []
		var start_position := _point(
			(nodes_by_id[chain_start_id] as Dictionary).get(
				"position",
				{},
			) as Dictionary,
		)
		var finish_position := _point(
			(nodes_by_id[chain_finish_id] as Dictionary).get(
				"position",
				{},
			) as Dictionary,
		)
		var adaptive_path := OUTDOOR_PATHFINDER.find_outdoor_path(
			start_position,
			finish_position,
		)
		if adaptive_path.is_empty():
			return []
		var length := float(adaptive_path.get("length", 0.0))
		result.append({
			"id": "adaptive_%s__%s" % [
				chain_start_id,
				chain_finish_id,
			],
			"kind": "route_edge",
			"fromNodeId": chain_start_id,
			"toNodeId": chain_finish_id,
			"fromSpaceId": OUTDOOR_SPACE_ID,
			"toSpaceId": OUTDOOR_SPACE_ID,
			"length": snappedf(length, 0.001),
			"costGameMinutes": length / outdoor_speed,
			"polyline": (
				adaptive_path.get("polyline", []) as Array
			).duplicate(true),
		})
		cursor = chain_finish
	return result


static func _is_outdoor_route_step(step: Dictionary) -> bool:
	return (
		String(step.get("kind", "")) == "route_edge"
		and String(step.get("fromSpaceId", "")) == OUTDOOR_SPACE_ID
		and String(step.get("toSpaceId", "")) == OUTDOOR_SPACE_ID
	)


static func find_route_from_state(
	data: Dictionary,
	state: Dictionary,
	to_place_name: String,
	connector_polyline: Array = [],
) -> Dictionary:
	var space_id := str(state.get("spaceId", ""))
	var region_id := str(state.get("regionId", ""))
	var place_name := str(state.get("currentPlace", ""))
	var position: Vector2 = state.get("position", Vector2.ZERO) as Vector2
	if space_id.is_empty() or region_id.is_empty() or place_name.is_empty() or to_place_name.is_empty():
		return {}
	# 性能：活动可达性预检里每个候选项都会走到这里，原先每次
	# data.duplicate(true) 整份世界数据深拷贝（加路网两轮深拷贝）是
	# 单次寻路最大的成本。下面全部只追加不修改：movement 与各数组
	# 先浅拷贝再追加，共享原始数据保持不变。
	var runtime_data := data.duplicate()
	var movement := (
		(data.get("movementNetwork", {}) as Dictionary).duplicate()
	)
	var original_nodes := movement.get("nodes", []) as Array
	var original_edges := movement.get("edges", []) as Array
	var nodes := original_nodes.duplicate()
	var edges := original_edges.duplicate()
	if connector_polyline.is_empty():
		var matching_node_id := _matching_node_id(
			original_nodes,
			position,
			space_id,
		)
		if not matching_node_id.is_empty():
			var cache_key := _direct_route_cache_key(
				data,
				matching_node_id,
				to_place_name,
			)
			if _direct_route_cache.has(cache_key):
				var cached := (
					_direct_route_cache[cache_key] as Dictionary
				).duplicate(true)
				cached["fromPlaceName"] = place_name
				return cached
			var direct_arrivals := (
				(movement.get("arrivalNodes", []) as Array).duplicate()
			)
			direct_arrivals.append({
				"id": "runtime_start_arrival",
				"nodeId": matching_node_id,
				"placeName": "__runtime_start__",
				"priority": 0,
			})
			movement["arrivalNodes"] = direct_arrivals
			runtime_data["movementNetwork"] = movement
			var direct_result := find_route(
				runtime_data,
				"__runtime_start__",
				to_place_name,
			)
			if not direct_result.is_empty():
				direct_result["fromPlaceName"] = place_name
				if _direct_route_cache.size() >= DIRECT_ROUTE_CACHE_MAX_ENTRIES:
					_direct_route_cache.clear()
				_direct_route_cache[cache_key] = direct_result.duplicate(true)
				return direct_result
	var virtual_node_id := "runtime_start"
	nodes.append({
		"id": virtual_node_id,
		"kind": "runtime_start",
		"placeName": place_name,
		"position": _point_dictionary(position),
		"regionId": region_id,
		"spaceId": space_id,
	})
	var arrivals := (movement.get("arrivalNodes", []) as Array).duplicate()
	arrivals.append({"id": "runtime_start_arrival", "nodeId": virtual_node_id, "placeName": "__runtime_start__", "priority": 0})
	var connection_count := 0
	if not connector_polyline.is_empty():
		connection_count += _connect_explicit_polyline(edges, original_nodes, virtual_node_id, position, space_id, connector_polyline)
	# A completed or interrupted prop action can leave an old same-space
	# connector in a restored save.  It is only a hint: when it no longer ends
	# at a formal movement node, rebuild the connection from authoritative
	# navigation instead of trapping the resident at the prop.
	if connection_count == 0:
		connection_count += _connect_matching_nodes(
			edges,
			original_nodes,
			virtual_node_id,
			position,
			space_id,
		)
	if space_id == OUTDOOR_SPACE_ID:
		# Outdoor movement starts at the resident's exact body origin. Connect it
		# directly to the destination's outdoor arrival, or to the outside of the
		# destination's shared player portal when the destination is indoors.
		connection_count += _connect_outdoor_goal_anchors(
			runtime_data,
			edges,
			nodes,
			virtual_node_id,
			position,
			to_place_name,
		)
	elif connection_count == 0:
		connection_count += _connect_indoor_navigation(
			runtime_data,
			edges,
			original_nodes,
			virtual_node_id,
			position,
			space_id,
		)
	if connection_count == 0:
		return {}
	movement["nodes"] = nodes
	movement["edges"] = edges
	movement["arrivalNodes"] = arrivals
	runtime_data["movementNetwork"] = movement
	var result := find_route(runtime_data, "__runtime_start__", to_place_name)
	if not result.is_empty():
		result["fromPlaceName"] = place_name
		result["runtimeStart"] = true
	return result


static func find_route_to_outdoor_position(
	data: Dictionary,
	state: Dictionary,
	target_position: Vector2,
	target_region_id: String,
	connector_polyline: Array = [],
) -> Dictionary:
	if (
		data.is_empty()
		or not target_position.is_finite()
		or target_region_id.strip_edges().is_empty()
	):
		return {}
	var target_place_name := ""
	for value: Variant in data.get("perceptionRegions", []) as Array:
		if not value is Dictionary:
			continue
		var region := value as Dictionary
		if (
			String(region.get("id", "")) == target_region_id
			and String(region.get("spaceId", "")) == OUTDOOR_SPACE_ID
			and _position_in_grid_region(
				target_position,
				region.get("shape", {}) as Dictionary,
			)
		):
			target_place_name = String(region.get("placeName", ""))
			break
	if target_place_name.is_empty():
		return {}
	# 性能：该函数在活动可达性预检中被每个候选项调用一次（单次唤醒包
	# 可达数×十几次），原先每次 data.duplicate(true) 深拷贝整个世界数据
	# 加整套路网，单次可达 30ms+。这里只读不改——节点/边/到达点用浅拷贝
	# 数组追加，world data 只做顶层浅拷贝替换 movementNetwork。
	var movement := data.get("movementNetwork", {}) as Dictionary
	var nodes := (movement.get("nodes", []) as Array).duplicate()
	var edges := (movement.get("edges", []) as Array).duplicate()
	var target_node_id := "runtime_activity_region_target"
	nodes.append({
		"id": target_node_id,
		"kind": "runtime_activity_region_target",
		"placeName": target_place_name,
		"position": _point_dictionary(target_position),
		"regionId": target_region_id,
		"spaceId": OUTDOOR_SPACE_ID,
	})
	if String(state.get("spaceId", "")) != OUTDOOR_SPACE_ID:
		if _connect_outdoor_target_to_state_portal(
			data,
			edges,
			nodes,
			target_node_id,
			target_position,
			String(state.get("spaceId", "")),
		) == 0:
			return {}
	var arrivals := (
		movement.get("arrivalNodes", []) as Array
	).duplicate()
	arrivals.append({
		"id": "runtime_activity_region_arrival",
		"nodeId": target_node_id,
		"placeName": "__runtime_activity_region_target__",
		"priority": 0,
	})
	var patched_movement := movement.duplicate()
	patched_movement["nodes"] = nodes
	patched_movement["edges"] = edges
	patched_movement["arrivalNodes"] = arrivals
	var runtime_data := data.duplicate()
	runtime_data["movementNetwork"] = patched_movement
	var route := find_route_from_state(
		runtime_data,
		state,
		"__runtime_activity_region_target__",
		connector_polyline,
	)
	if route.is_empty():
		return {}
	route["toPlaceName"] = target_place_name
	route["targetRegionId"] = target_region_id
	route["targetPosition"] = target_position
	return route


static func _position_in_grid_region(
	position: Vector2,
	shape: Dictionary,
) -> bool:
	if String(shape.get("type", "")) != "grid_cells":
		return false
	var cell_size := float(shape.get("cellSize", 0.0))
	if cell_size <= 0.0:
		return false
	var expected := Vector2i(
		floori(position.x / cell_size),
		floori(position.y / cell_size),
	)
	for value: Variant in shape.get("cells", []) as Array:
		if not value is Array or (value as Array).size() != 2:
			continue
		var pair := value as Array
		if Vector2i(int(pair[0]), int(pair[1])) == expected:
			return true
	return false


static func _matching_node_id(
	nodes: Array,
	position: Vector2,
	space_id: String,
) -> String:
	for value: Variant in nodes:
		var node := value as Dictionary
		if (
			str(node.get("spaceId", "")) == space_id
			and _point(
				node.get("position", {}) as Dictionary,
			).distance_to(position) <= 1.0
		):
			return str(node.get("id", ""))
	return ""


static func rebuild_minute_positions_for_restore(
	data: Dictionary,
	route: Dictionary,
) -> Array:
	if (
		typeof(route.get("durationMinutes")) != TYPE_INT
		or int(route.get("durationMinutes", 0)) <= 0
		or typeof(route.get("costGameMinutes")) not in [TYPE_INT, TYPE_FLOAT]
		or not route.get("segments") is Array
		or (route.get("segments") as Array).is_empty()
	):
		return []
	for segment_value: Variant in route.get("segments") as Array:
		if (
			not segment_value is Dictionary
			or not (segment_value as Dictionary).get("polyline") is Array
			or (
				(segment_value as Dictionary).get("polyline") as Array
			).size() < 2
		):
			return []
		for point_value: Variant in (
			(segment_value as Dictionary).get("polyline") as Array
		):
			if not point_value is Dictionary:
				return []
	var nodes_by_id := {}
	for node_value: Variant in (
		(data.get("movementNetwork", {}) as Dictionary).get("nodes", [])
		as Array
	):
		if node_value is Dictionary:
			var node := node_value as Dictionary
			nodes_by_id[String(node.get("id", ""))] = node
	if route.get("runtimeStart") == true:
		var samples_value: Variant = route.get("minutePositions")
		if not samples_value is Array or (samples_value as Array).is_empty():
			return []
		var first_value: Variant = (samples_value as Array)[0]
		if not first_value is Dictionary:
			return []
		var first := first_value as Dictionary
		nodes_by_id["runtime_start"] = {
			"id": "runtime_start",
			"kind": "runtime_start",
			"placeName": first.get("placeName"),
			"position": (
				(first.get("position") as Dictionary).duplicate(true)
				if first.get("position") is Dictionary
				else {}
			),
			"regionId": first.get("regionId"),
			"spaceId": first.get("spaceId"),
		}
	if (
		not nodes_by_id.has(String(route.get("startNodeId", "")))
		or not nodes_by_id.has(String(route.get("arrivalNodeId", "")))
	):
		return []
	return _minute_positions(route, data, nodes_by_id)


static func _connect_explicit_polyline(
	edges: Array,
	nodes: Array,
	virtual_node_id: String,
	position: Vector2,
	space_id: String,
	values: Array,
) -> int:
	var points := _variant_points(values)
	if points.is_empty() or points[0].distance_to(position) > 1.0:
		return 0
	if space_id == OUTDOOR_SPACE_ID:
		var collision_records := _outdoor_collision_records_for_query()
		if collision_records.is_empty():
			return 0
		for point: Vector2 in points:
			if not OUTDOOR_CLEARANCE.body_origin_is_safe(
				point,
				collision_records,
			):
				return 0
		for index in range(1, points.size()):
			if not OUTDOOR_CLEARANCE.body_segment_is_safe(
				points[index - 1],
				points[index],
				collision_records,
			):
				return 0
	var target_node_id := ""
	for value: Variant in nodes:
		var node := value as Dictionary
		if str(node.get("spaceId", "")) == space_id and _point(node.get("position", {}) as Dictionary).distance_to(points[-1]) <= 1.0:
			target_node_id = str(node.get("id", ""))
			break
	if target_node_id.is_empty():
		return 0
	_append_runtime_edge(edges, "runtime_connector", virtual_node_id, target_node_id, points)
	return 1


static func _connect_matching_nodes(
	edges: Array,
	nodes: Array,
	virtual_node_id: String,
	position: Vector2,
	space_id: String,
) -> int:
	var count := 0
	for value: Variant in nodes:
		var node := value as Dictionary
		var node_position := _point(node.get("position", {}) as Dictionary)
		if str(node.get("spaceId", "")) != space_id or node_position.distance_to(position) > 1.0:
			continue
		_append_runtime_edge(edges, "runtime_node_%s" % node.get("id", ""), virtual_node_id, str(node.get("id", "")), [position, node_position])
		count += 1
	return count


static func _connect_matching_edges(edges: Array, source_edges: Array, virtual_node_id: String, position: Vector2) -> int:
	var matches: Array[Dictionary] = []
	var best_distance := INF
	var collision_records := _outdoor_collision_records_for_query()
	if collision_records.is_empty():
		return 0
	var projected_edges: Array[Dictionary] = []
	for value: Variant in source_edges:
		var edge := value as Dictionary
		var points := _variant_points(edge.get("polyline", []) as Array)
		var projection := _polyline_projection(points, position)
		var distance := float(projection.get("distance", INF))
		if (
			projection.is_empty()
			or distance > OUTDOOR_ROUTE_RECOVERY_DISTANCE
		):
			continue
		projected_edges.append({
			"edge": edge,
			"projection": projection,
			"distance": distance,
		})
	projected_edges.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_distance := float(left.get("distance", INF))
		var right_distance := float(right.get("distance", INF))
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return String((left.get("edge", {}) as Dictionary).get("id", "")) < String(
			(right.get("edge", {}) as Dictionary).get("id", "")
		)
	)
	for projected_edge: Dictionary in projected_edges:
		var distance := float(projected_edge.get("distance", INF))
		if distance > best_distance + COST_EPSILON:
			break
		var projection := projected_edge.get("projection", {}) as Dictionary
		if not OUTDOOR_CLEARANCE.body_segment_is_safe(
			position,
			projection.get("point", position) as Vector2,
			collision_records,
		):
			continue
		if best_distance == INF:
			best_distance = distance
		matches.append(projected_edge)
	if matches.is_empty():
		return 0
	matches.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String((left.get("edge", {}) as Dictionary).get("id", "")) < String(
			(right.get("edge", {}) as Dictionary).get("id", "")
		)
	)
	var connection_count := 0
	for match: Dictionary in matches:
		var matched_edge := match.get("edge", {}) as Dictionary
		var matched_projection := match.get("projection", {}) as Dictionary
		var points := _variant_points(
			matched_edge.get("polyline", []) as Array
		)
		var segment_index := int(
			matched_projection.get("segmentIndex", 0)
		)
		var projected := matched_projection.get(
			"point",
			position,
		) as Vector2
		var to_from: Array[Vector2] = [position]
		if not projected.is_equal_approx(position):
			to_from.append(projected)
		for index in range(segment_index, -1, -1):
			if not to_from[-1].is_equal_approx(points[index]):
				to_from.append(points[index])
		var to_to: Array[Vector2] = [position]
		if not projected.is_equal_approx(position):
			to_to.append(projected)
		for index in range(segment_index + 1, points.size()):
			if not to_to[-1].is_equal_approx(points[index]):
				to_to.append(points[index])
		_append_runtime_edge(
			edges,
			"runtime_edge_%s_from" % matched_edge.get("id", ""),
			virtual_node_id,
			str(matched_edge.get("fromNodeId", "")),
			to_from,
		)
		_append_runtime_edge(
			edges,
			"runtime_edge_%s_to" % matched_edge.get("id", ""),
			virtual_node_id,
			str(matched_edge.get("toNodeId", "")),
			to_to,
		)
		connection_count += 2
	return connection_count


static func _outdoor_collision_records_for_query() -> Array[Dictionary]:
	if not _outdoor_collision_records.is_empty():
		return _outdoor_collision_records
	if not FileAccess.file_exists(OUTDOOR_COLLISION_PATH):
		return []
	var value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(OUTDOOR_COLLISION_PATH)
	)
	if not value is Array:
		return []
	_outdoor_collision_records = OUTDOOR_CLEARANCE.collision_records(
		value as Array
	)
	return _outdoor_collision_records


static func _connect_indoor_navigation(
	data: Dictionary,
	edges: Array,
	nodes: Array,
	virtual_node_id: String,
	position: Vector2,
	space_id: String,
) -> int:
	var navigation := _indoor_navigation(data, space_id)
	if navigation.is_empty():
		return 0
	var count := 0
	for value: Variant in nodes:
		var node := value as Dictionary
		if str(node.get("spaceId", "")) != space_id:
			continue
		var target_position := _point(node.get("position", {}) as Dictionary)
		var points := INDOOR_PATH_QUERY.find_path(
			navigation,
			position,
			target_position,
		)
		if points.is_empty():
			continue
		_append_runtime_edge(
			edges,
			"runtime_indoor_%s" % node.get("id", ""),
			virtual_node_id,
			str(node.get("id", "")),
			points,
		)
		count += 1
	return count


static func _connect_outdoor_goal_anchors(
	data: Dictionary,
	edges: Array,
	nodes: Array,
	virtual_node_id: String,
	position: Vector2,
	to_place_name: String,
) -> int:
	var nodes_by_id := {}
	for value: Variant in nodes:
		if value is Dictionary:
			var node := value as Dictionary
			nodes_by_id[String(node.get("id", ""))] = node
	var anchor_ids: Array[String] = []
	var movement := data.get("movementNetwork", {}) as Dictionary
	for value: Variant in movement.get("arrivalNodes", []) as Array:
		if value is not Dictionary:
			continue
		var arrival := value as Dictionary
		if String(arrival.get("placeName", "")) != to_place_name:
			continue
		var arrival_node_id := String(arrival.get("nodeId", ""))
		var arrival_node := nodes_by_id.get(arrival_node_id, {}) as Dictionary
		if String(arrival_node.get("spaceId", "")) == OUTDOOR_SPACE_ID:
			if arrival_node_id not in anchor_ids:
				anchor_ids.append(arrival_node_id)
			continue
		for connection_value: Variant in data.get("connections", []) as Array:
			if connection_value is not Dictionary:
				continue
			var connection := connection_value as Dictionary
			var from_end := connection.get("from", {}) as Dictionary
			var to_end := connection.get("to", {}) as Dictionary
			var outdoor_id := ""
			if (
				String(from_end.get("nodeId", "")) == arrival_node_id
				and String(to_end.get("spaceId", "")) == OUTDOOR_SPACE_ID
			):
				outdoor_id = String(to_end.get("nodeId", ""))
			elif (
				String(to_end.get("nodeId", "")) == arrival_node_id
				and String(from_end.get("spaceId", "")) == OUTDOOR_SPACE_ID
			):
				outdoor_id = String(from_end.get("nodeId", ""))
			if not outdoor_id.is_empty() and outdoor_id not in anchor_ids:
				anchor_ids.append(outdoor_id)
	var count := 0
	anchor_ids.sort()
	for anchor_id: String in anchor_ids:
		var node := nodes_by_id.get(anchor_id, {}) as Dictionary
		if node.is_empty():
			continue
		var target_position := _point(
			node.get("position", {}) as Dictionary,
		)
		var route := OUTDOOR_PATHFINDER.find_outdoor_path(
			position,
			target_position,
		)
		var points := _variant_points(route.get("polyline", []) as Array)
		if points.size() < 2:
			continue
		_append_runtime_edge(
			edges,
			"runtime_adaptive_goal_%s" % anchor_id,
			virtual_node_id,
			anchor_id,
			points,
		)
		count += 1
	return count


static func _connect_outdoor_target_to_state_portal(
	data: Dictionary,
	edges: Array,
	nodes: Array,
	target_node_id: String,
	target_position: Vector2,
	state_space_id: String,
) -> int:
	var nodes_by_id := {}
	for value: Variant in nodes:
		if value is Dictionary:
			var node := value as Dictionary
			nodes_by_id[String(node.get("id", ""))] = node
	var count := 0
	for value: Variant in data.get("connections", []) as Array:
		if value is not Dictionary:
			continue
		var connection := value as Dictionary
		var from_end := connection.get("from", {}) as Dictionary
		var to_end := connection.get("to", {}) as Dictionary
		var outdoor_id := ""
		if (
			String(from_end.get("spaceId", "")) == state_space_id
			and String(to_end.get("spaceId", "")) == OUTDOOR_SPACE_ID
		):
			outdoor_id = String(to_end.get("nodeId", ""))
		elif (
			String(to_end.get("spaceId", "")) == state_space_id
			and String(from_end.get("spaceId", "")) == OUTDOOR_SPACE_ID
		):
			outdoor_id = String(from_end.get("nodeId", ""))
		var outdoor_node := nodes_by_id.get(outdoor_id, {}) as Dictionary
		if outdoor_node.is_empty():
			continue
		var outdoor_position := _point(
			outdoor_node.get("position", {}) as Dictionary,
		)
		var route := OUTDOOR_PATHFINDER.find_outdoor_path(
			target_position,
			outdoor_position,
		)
		var points := _variant_points(route.get("polyline", []) as Array)
		if points.size() < 2:
			continue
		_append_runtime_edge(
			edges,
			"runtime_adaptive_target_%s" % outdoor_id,
			target_node_id,
			outdoor_id,
			points,
		)
		count += 1
	return count


static func _indoor_navigation(data: Dictionary, space_id: String) -> Dictionary:
	for value: Variant in data.get("indoorNavigation", []) as Array:
		var navigation := value as Dictionary
		if str(navigation.get("spaceId", "")) == space_id:
			return navigation
	return {}


static func _append_runtime_edge(edges: Array, edge_id: String, from_id: String, to_id: String, points: Array[Vector2]) -> void:
	var length := 0.0
	var polyline: Array[Dictionary] = []
	for index in points.size():
		polyline.append(_point_dictionary(points[index]))
		if index > 0:
			length += points[index - 1].distance_to(points[index])
	edges.append({"id": edge_id, "fromNodeId": from_id, "toNodeId": to_id, "length": snappedf(length, 0.001), "polyline": polyline})


static func _variant_points(values: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for value: Variant in values:
		if value is Vector2:
			result.append(value as Vector2)
		elif value is Dictionary:
			result.append(_point(value as Dictionary))
	return result


static func _polyline_projection(points: Array[Vector2], position: Vector2) -> Dictionary:
	var result := {}
	var best_distance := INF
	for index in range(points.size() - 1):
		var segment := points[index + 1] - points[index]
		var length_squared := segment.length_squared()
		var weight := 0.0 if length_squared <= COST_EPSILON else clampf((position - points[index]).dot(segment) / length_squared, 0.0, 1.0)
		var projected := points[index] + segment * weight
		var distance := position.distance_to(projected)
		if distance < best_distance:
			best_distance = distance
			result = {"segmentIndex": index, "point": projected, "distance": distance}
	return result


static func _build_adjacency(data: Dictionary, nodes_by_id: Dictionary) -> Dictionary:
	var adjacency := {}
	for node_id in nodes_by_id:
		adjacency[node_id] = []
	var speed := float(data.get("movementRules", {}).get("outdoorDistancePerGameMinute", 0.0))
	if speed <= 0.0:
		return adjacency
	for edge_value in (data.get("movementNetwork", {}) as Dictionary).get("edges", []) as Array:
		var edge := edge_value as Dictionary
		var from_id := str(edge.get("fromNodeId", ""))
		var to_id := str(edge.get("toNodeId", ""))
		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id):
			continue
		var from_node := nodes_by_id.get(from_id, {}) as Dictionary
		var to_node := nodes_by_id.get(to_id, {}) as Dictionary
		var forward := {
			"id": str(edge.get("id", "")),
			"kind": "route_edge",
			"fromNodeId": from_id,
			"toNodeId": to_id,
			"fromSpaceId": str(from_node.get("spaceId", "")),
			"toSpaceId": str(to_node.get("spaceId", "")),
			"length": float(edge.get("length", 0.0)),
			"costGameMinutes": float(edge.get("length", 0.0)) / speed,
			"polyline": (edge.get("polyline", []) as Array).duplicate(true),
		}
		_append_step(adjacency, forward)
		_append_step(adjacency, _reversed_step(forward))
	for connection_value in data.get("connections", []) as Array:
		var connection := connection_value as Dictionary
		var from_end := connection.get("from", {}) as Dictionary
		var to_end := connection.get("to", {}) as Dictionary
		var forward := {
			"id": str(connection.get("id", "")),
			"kind": "connection",
			"fromNodeId": str(from_end.get("nodeId", "")),
			"toNodeId": str(to_end.get("nodeId", "")),
			"fromSpaceId": str(from_end.get("spaceId", "")),
			"toSpaceId": str(to_end.get("spaceId", "")),
			"length": 0.0,
			"costGameMinutes": float(connection.get("movementMinutes", 0.0)),
			"polyline": [
				(from_end.get("position", {}) as Dictionary).duplicate(true),
				(to_end.get("position", {}) as Dictionary).duplicate(true),
			],
		}
		_append_step(adjacency, forward)
		_append_step(adjacency, _reversed_step(forward))
	for node_id in adjacency:
		(adjacency[node_id] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_key := "%s>%s" % [left.get("id", ""), left.get("toNodeId", "")]
			var right_key := "%s>%s" % [right.get("id", ""), right.get("toNodeId", "")]
			return left_key < right_key
		)
	return adjacency


static func _append_step(adjacency: Dictionary, step: Dictionary) -> void:
	var from_id := str(step.get("fromNodeId", ""))
	if adjacency.has(from_id):
		(adjacency[from_id] as Array).append(step)


static func _reversed_step(step: Dictionary) -> Dictionary:
	var polyline := (step.get("polyline", []) as Array).duplicate(true)
	polyline.reverse()
	return {
		"id": str(step.get("id", "")),
		"kind": str(step.get("kind", "")),
		"fromNodeId": str(step.get("toNodeId", "")),
		"toNodeId": str(step.get("fromNodeId", "")),
		"fromSpaceId": str(step.get("toSpaceId", "")),
		"toSpaceId": str(step.get("fromSpaceId", "")),
		"length": float(step.get("length", 0.0)),
		"costGameMinutes": float(step.get("costGameMinutes", 0.0)),
		"polyline": polyline,
	}


static func _best_active_node(active: Dictionary, distances: Dictionary, signatures: Dictionary) -> String:
	var best_id := ""
	for node_id_value in active:
		var node_id := str(node_id_value)
		if best_id.is_empty() or _state_less(node_id, best_id, distances, signatures):
			best_id = node_id
	return best_id


static func _state_less(left_id: String, right_id: String, distances: Dictionary, signatures: Dictionary) -> bool:
	var left_cost := float(distances.get(left_id, INF))
	var right_cost := float(distances.get(right_id, INF))
	if absf(left_cost - right_cost) > COST_EPSILON:
		return left_cost < right_cost
	var left_signature := str(signatures.get(left_id, ""))
	var right_signature := str(signatures.get(right_id, ""))
	if left_signature != right_signature:
		return left_signature < right_signature
	return left_id < right_id


static func _best_goal(arrivals: Array, distances: Dictionary, signatures: Dictionary) -> Dictionary:
	var result := {}
	var best_cost := INF
	var best_key := ""
	for arrival_value in arrivals:
		var arrival := arrival_value as Dictionary
		var node_id := str(arrival.get("nodeId", ""))
		if not distances.has(node_id):
			continue
		var cost := float(distances[node_id])
		var key := "%s|goal:%s:%s" % [signatures.get(node_id, ""), arrival.get("id", ""), node_id]
		if cost < best_cost - COST_EPSILON or (absf(cost - best_cost) <= COST_EPSILON and (best_key.is_empty() or key < best_key)):
			best_cost = cost
			best_key = key
			result = arrival
	return result


static func _minute_positions(route: Dictionary, data: Dictionary, nodes_by_id: Dictionary) -> Array:
	var result := []
	var duration := int(route.get("durationMinutes", 0))
	var total_cost := float(route.get("costGameMinutes", 0.0))
	var segments := route.get("segments", []) as Array
	var outdoor_lookup := _outdoor_lookup(data)
	for minute in range(duration + 1):
		if minute == duration:
			result.append(_node_position_snapshot(
				minute,
				nodes_by_id.get(str(route.get("arrivalNodeId", "")), {}) as Dictionary
			))
			continue
		var elapsed := minf(float(minute), total_cost)
		result.append(_sample_segments(minute, elapsed, segments, data, outdoor_lookup, nodes_by_id))
	for minute in range(1, result.size()):
		var interval_start := minf(float(minute - 1), total_cost)
		var interval_finish := minf(float(minute), total_cost)
		var presentation_path := _presentation_path_between(
			interval_start,
			interval_finish,
			segments,
		)
		var previous_sample := result[minute - 1] as Dictionary
		var sample := result[minute] as Dictionary
		if previous_sample.get("spaceId") != sample.get("spaceId"):
			presentation_path.clear()
		elif presentation_path.is_empty():
			presentation_path = [
				(previous_sample.get("position", {}) as Dictionary).duplicate(true),
				(sample.get("position", {}) as Dictionary).duplicate(true),
			]
		else:
			# Segment sampling uses floating travel cost and may finish a
			# fraction of a pixel beside the authoritative minute position.
			# Presentation paths are persisted and replayed, so keep their
			# interior geometry but pin both ends to the exact adjacent World
			# samples. This prevents a valid in-progress route from making the
			# entire session unsavable.
			presentation_path[0] = (
				(previous_sample.get("position", {}) as Dictionary).duplicate(
					true
				)
			)
			presentation_path[-1] = (
				(sample.get("position", {}) as Dictionary).duplicate(true)
			)
		sample["presentationPath"] = presentation_path
		result[minute] = sample
	if not result.is_empty():
		var first_sample := result[0] as Dictionary
		first_sample["presentationPath"] = [
			(first_sample.get("position", {}) as Dictionary).duplicate(true),
		]
		result[0] = first_sample
	return result


static func _presentation_path_between(
	elapsed_start: float,
	elapsed_finish: float,
	segments: Array,
) -> Array[Dictionary]:
	if elapsed_finish <= elapsed_start + COST_EPSILON:
		return []
	var result: Array[Dictionary] = []
	var cursor := 0.0
	for segment_value: Variant in segments:
		if segment_value is not Dictionary:
			return []
		var segment := segment_value as Dictionary
		var cost := float(segment.get("costGameMinutes", 0.0))
		var segment_start := cursor
		var segment_finish := cursor + cost
		cursor = segment_finish
		var overlap_start := maxf(elapsed_start, segment_start)
		var overlap_finish := minf(elapsed_finish, segment_finish)
		if overlap_finish <= overlap_start + COST_EPSILON:
			continue
		if (
			String(segment.get("kind", "")) != "route_edge"
			or String(segment.get("fromSpaceId", "")) != OUTDOOR_SPACE_ID
			or String(segment.get("toSpaceId", "")) != OUTDOOR_SPACE_ID
			or cost <= COST_EPSILON
		):
			break
		var local_start := clampf(
			(overlap_start - segment_start) / cost,
			0.0,
			1.0,
		)
		var local_finish := clampf(
			(overlap_finish - segment_start) / cost,
			0.0,
			1.0,
		)
		var segment_path := _polyline_slice(
			segment.get("polyline", []) as Array,
			local_start,
			local_finish,
		)
		if segment_path.is_empty():
			return []
		for point: Dictionary in segment_path:
			if (
				result.is_empty()
				or _point(result[-1]).distance_to(_point(point)) > 0.001
			):
				result.append(point)
	return _erase_retraced_loops(result)


static func _erase_retraced_loops(
	points: Array[Dictionary],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point: Dictionary in points:
		var repeated_index := -1
		for index in range(result.size() - 1, -1, -1):
			if _point(result[index]).distance_to(_point(point)) <= 0.001:
				repeated_index = index
				break
		if repeated_index >= 0:
			result.resize(repeated_index + 1)
			continue
		result.append(point)
	return result


static func _polyline_slice(
	values: Array,
	start_ratio: float,
	finish_ratio: float,
) -> Array[Dictionary]:
	var points := _variant_points(values)
	if points.size() < 2:
		return []
	var total_length := 0.0
	for index in range(1, points.size()):
		total_length += points[index - 1].distance_to(points[index])
	if total_length <= COST_EPSILON:
		return []
	var start_distance := total_length * clampf(start_ratio, 0.0, 1.0)
	var finish_distance := total_length * clampf(finish_ratio, 0.0, 1.0)
	if finish_distance <= start_distance + COST_EPSILON:
		return []
	var result: Array[Dictionary] = [
		_point_dictionary(_point_along_polyline(values, start_ratio)),
	]
	var cursor := 0.0
	for index in range(1, points.size()):
		cursor += points[index - 1].distance_to(points[index])
		if (
			cursor > start_distance + COST_EPSILON
			and cursor < finish_distance - COST_EPSILON
		):
			result.append(_point_dictionary(points[index]))
	var finish_point := _point_along_polyline(values, finish_ratio)
	if _point(result[-1]).distance_to(finish_point) > 0.001:
		result.append(_point_dictionary(finish_point))
	return result


static func _sample_segments(
	minute: int,
	elapsed: float,
	segments: Array,
	data: Dictionary,
	outdoor_lookup: Dictionary,
	nodes_by_id: Dictionary
) -> Dictionary:
	var cursor := 0.0
	for segment_value in segments:
		var segment := segment_value as Dictionary
		var cost := float(segment.get("costGameMinutes", 0.0))
		if elapsed <= cursor + cost + COST_EPSILON:
			var local_elapsed := maxf(0.0, elapsed - cursor)
			if str(segment.get("kind", "")) == "connection":
				if local_elapsed + COST_EPSILON < cost:
					return _node_position_snapshot(
						minute,
						nodes_by_id.get(str(segment.get("fromNodeId", "")), {}) as Dictionary
					)
				return _node_position_snapshot(
					minute,
					nodes_by_id.get(str(segment.get("toNodeId", "")), {}) as Dictionary
				)
			var ratio := 1.0 if cost <= COST_EPSILON else clampf(local_elapsed / cost, 0.0, 1.0)
			var position := _point_along_polyline(segment.get("polyline", []) as Array, ratio)
			return _route_edge_position_snapshot(
				minute,
				position,
				segment,
				data,
				outdoor_lookup,
				nodes_by_id,
			)
		cursor += cost
	return _node_position_snapshot(
		minute,
		nodes_by_id.get(str((segments[-1] as Dictionary).get("toNodeId", "")), {}) as Dictionary
	)


static func _route_edge_position_snapshot(
	minute: int,
	position: Vector2,
	segment: Dictionary,
	data: Dictionary,
	outdoor_lookup: Dictionary,
	nodes_by_id: Dictionary,
) -> Dictionary:
	var space_id := str(segment.get("fromSpaceId", ""))
	if space_id == OUTDOOR_SPACE_ID:
		var membership := _outdoor_membership(data, outdoor_lookup, position)
		if membership.is_empty():
			var from_node := nodes_by_id.get(
				str(segment.get("fromNodeId", "")),
				{},
			) as Dictionary
			var to_node := nodes_by_id.get(
				str(segment.get("toNodeId", "")),
				{},
			) as Dictionary
			membership = (
				from_node
				if position.distance_to(
					_point(from_node.get("position", {}) as Dictionary),
				) <= position.distance_to(
					_point(to_node.get("position", {}) as Dictionary),
				)
				else to_node
			)
		return {
			"minute": minute,
			"spaceId": OUTDOOR_SPACE_ID,
			"position": _point_dictionary(position),
			"regionId": str(membership.get("regionId", "")),
			"placeName": str(membership.get("placeName", "")),
		}
	var from_node := nodes_by_id.get(str(segment.get("fromNodeId", "")), {}) as Dictionary
	var to_node := nodes_by_id.get(str(segment.get("toNodeId", "")), {}) as Dictionary
	var membership_node := from_node
	if str(membership_node.get("spaceId", "")) != space_id:
		membership_node = to_node
	return {
		"minute": minute,
		"spaceId": space_id,
		"position": _point_dictionary(position),
		"regionId": str(membership_node.get("regionId", "")),
		"placeName": str(membership_node.get("placeName", "")),
	}


static func _point_along_polyline(values: Array, ratio: float) -> Vector2:
	var points := PackedVector2Array()
	for value in values:
		points.append(_point(value as Dictionary))
	if points.is_empty():
		return Vector2.ZERO
	var total_length := 0.0
	for index in range(1, points.size()):
		total_length += points[index - 1].distance_to(points[index])
	var target := total_length * ratio
	var cursor := 0.0
	for index in range(1, points.size()):
		var length := points[index - 1].distance_to(points[index])
		if target <= cursor + length or index == points.size() - 1:
			var local_ratio := 0.0 if length <= COST_EPSILON else (target - cursor) / length
			return points[index - 1].lerp(points[index], clampf(local_ratio, 0.0, 1.0))
		cursor += length
	return points[-1]


static func _outdoor_lookup(data: Dictionary) -> Dictionary:
	var result := {}
	for region_value in data.get("perceptionRegions", []) as Array:
		var region := region_value as Dictionary
		if str(region.get("spaceId", "")) != OUTDOOR_SPACE_ID:
			continue
		var membership := {
			"regionId": str(region.get("id", "")),
			"placeName": str(region.get("placeName", "")),
		}
		for cell_value in (region.get("shape", {}) as Dictionary).get("cells", []) as Array:
			var pair := cell_value as Array
			result["%d:%d" % [int(pair[0]), int(pair[1])]] = membership
	return result


static func _outdoor_membership(data: Dictionary, lookup: Dictionary, position: Vector2) -> Dictionary:
	var grid := data.get("perceptionGrid", {}) as Dictionary
	var cell_size := int(grid.get("cellSize", 0))
	var cell_x := floori(position.x / float(cell_size))
	var cell_y := floori(position.y / float(cell_size))
	var direct := lookup.get("%d:%d" % [cell_x, cell_y], {}) as Dictionary
	if not direct.is_empty():
		return direct
	for radius in range(1, 13):
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if maxi(absi(offset_x), absi(offset_y)) != radius:
					continue
				var candidate := lookup.get(
					"%d:%d" % [cell_x + offset_x, cell_y + offset_y],
					{},
				) as Dictionary
				if not candidate.is_empty():
					return candidate
	return {}


static func _node_position_snapshot(minute: int, node: Dictionary) -> Dictionary:
	return {
		"minute": minute,
		"spaceId": str(node.get("spaceId", "")),
		"position": (node.get("position", {}) as Dictionary).duplicate(true),
		"regionId": str(node.get("regionId", "")),
		"placeName": str(node.get("placeName", "")),
	}


static func _zero_route(place_name: String, node_id: String, node: Dictionary) -> Dictionary:
	var first_sample := _node_position_snapshot(0, node)
	first_sample["presentationPath"] = [
		(first_sample.get("position", {}) as Dictionary).duplicate(true),
	]
	return {
		"fromPlaceName": place_name,
		"toPlaceName": place_name,
		"startNodeId": node_id,
		"arrivalNodeId": node_id,
		"nodeIds": [node_id],
		"stepIds": [],
		"segments": [],
		"routeDistance": 0.0,
		"connectionMinutes": 0,
		"costGameMinutes": 0.0,
		"durationMinutes": 0,
		"minutePositions": [first_sample],
	}


static func _arrival_less(left: Dictionary, right: Dictionary) -> bool:
	var priority_compare := int(left.get("priority", 0)) - int(right.get("priority", 0))
	if priority_compare != 0:
		return priority_compare < 0
	return str(left.get("id", "")) < str(right.get("id", ""))


static func _point(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))


static func _point_dictionary(point: Vector2) -> Dictionary:
	return {"x": snappedf(point.x, 0.001), "y": snappedf(point.y, 0.001)}
