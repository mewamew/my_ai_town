extends RefCounted


# 决策提交/动作结果/工单关联等支撑纯函数族(O 域迁移第九件)。

const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")
const INDOOR_PATH_QUERY := preload("res://world/data/town/TownIndoorPropPathQuery.gd")
const RESTORE_LAYOUT := preload("res://world/runtime/persistence/TownWorldRestoreLayout.gd")
const OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS := [
	"clinic",
	"library_loan",
	"library_return",
	"library_assist",
	"dining_order",
	"cafe_order",
	"grocer_sale",
	"flower_sale",
]

static func agent_activity_step(
	action: Dictionary,
	place_id: String,
) -> Dictionary:
	return {
		"stepId": String(action.get("action_id", "")).strip_edges(),
		"operation": "activity.perform",
		"target": {
			"activityId": String(
				action.get("activity_id", "")
			).strip_edges(),
			"placeId": place_id,
		},
		"params": {
			"reason": String(action.get("line", "")),
		},
	}

static func consume_valid_request(resident: Dictionary) -> void:
	resident["decisionPending"] = false
	resident["validDecisionId"] = ""
	resident["pendingWake"] = {}
	resident["wakeDispatchQueued"] = false
	(resident.get("inflightEvents", []) as Array).clear()
	(resident.get("inflightResults", []) as Array).clear()

static func connection_anchor(endpoint: Dictionary) -> Dictionary:
	var point := endpoint.get("position", {}) as Dictionary
	return {
		"spaceId": String(endpoint.get("spaceId", "")),
		"regionId": String(endpoint.get("regionId", "")),
		"placeName": String(endpoint.get("placeName", "")),
		"position": Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))),
	}

static func apply_action_result_presentation(
	result: Dictionary,
	status: String,
	presentation: Dictionary,
) -> void:
	var base_icon_key := String(
		presentation.get("baseIconKey", "")
	).strip_edges()
	if base_icon_key.is_empty():
		return
	var result_phase := (
		"completed"
		if status == "completed"
		else (
			"interrupted"
			if status in ["interrupted", "replaced"]
			else "failed"
		)
	)
	result["baseIconKey"] = base_icon_key
	result["label"] = String(presentation.get("label", ""))
	result["sourceActivityId"] = String(
		presentation.get("sourceActivityId", "")
	)
	result["phase"] = result_phase

static func focus_agent_place_snapshot_on_service_task(
	resident: Dictionary,
	place_snapshot: Dictionary,
	service_task: Dictionary,
) -> void:
	var task_id := String(service_task.get("task_id", ""))
	var service_place := String(service_task.get("place_id", ""))
	var focused_activities: Array[Dictionary] = []
	for activity_value: Variant in place_snapshot.get("activities", []) as Array:
		if not activity_value is Dictionary:
			continue
		var activity := activity_value as Dictionary
		if (activity.get("work_task_ids", []) as Array).has(task_id):
			focused_activities.append(activity.duplicate(true))
	place_snapshot["activities"] = focused_activities
	place_snapshot["destinations"] = (
		[service_place]
		if (
			not service_place.is_empty()
			and String(resident.get("currentPlace", "")) != service_place
		)
		else []
	)
	place_snapshot["props"] = []
	place_snapshot["service_control"] = {}
	place_snapshot["message_recipients"] = []

static func inflight_allows_conversation_reply(
	events: Array,
	conversation_id: String,
) -> bool:
	var allows_reply := false
	for value: Variant in events:
		if value is not Dictionary:
			continue
		var event := value as Dictionary
		if String(event.get("conversation_id", "")) != conversation_id:
			continue
		var event_type := String(event.get("type", ""))
		if event_type in ["搭话", "对方答话"]:
			allows_reply = true
		elif event_type == "对话结束":
			allows_reply = false
	return allows_reply

static func agent_fact_payloads(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var payload := (value as Dictionary).duplicate(true)
		payload.erase("residentId")
		result.append(payload)
	return result

static func apply_work_task_log_associations(
	payload: Dictionary,
	task: Dictionary,
) -> void:
	for target_value: Variant in task.get("targets", []) as Array:
		if not target_value is Dictionary:
			continue
		var target := target_value as Dictionary
		var target_ref := String(target.get("ref", "")).strip_edges()
		match String(target.get("kind", "")):
			"service_request":
				payload["requestId"] = target_ref
			"cargo_lot":
				payload["cargoLotId"] = target_ref
			"public_matter":
				payload["matterId"] = target_ref
	var source_kind := String(task.get("sourceKind", ""))
	var source_ref := String(task.get("sourceRef", "")).strip_edges()
	if source_kind in ["resident_message", "formal_notice"]:
		payload["messageId"] = source_ref
	elif source_kind in [
		"cargo_available", "incoming_cargo", "flower_cargo", "inventory_request",
	]:
		payload["cargoLotId"] = source_ref
	elif source_kind in ["public_matter", "staffing_matter"]:
		payload["matterId"] = source_ref
	var result_facts := (
		(task.get("result", {}) as Dictionary).get("facts", {}) as Dictionary
	)
	for key: String in ["requestId", "cargoLotId", "messageId", "matterId"]:
		if payload.has(key):
			continue
		var fact_value := String(result_facts.get(key, "")).strip_edges()
		if not fact_value.is_empty():
			payload[key] = fact_value

static func apply_authoritative_resident_position(
	resident: Dictionary,
	position: Vector2,
	space_id: String,
	region_id: String,
	place_name: String,
) -> bool:
	var changed := (
		(resident.get("position", Vector2.ZERO) as Vector2).distance_to(position) > 0.001
		or String(resident.get("spaceId", "")) != space_id
		or String(resident.get("regionId", "")) != region_id
		or String(resident.get("currentPlace", "")) != place_name
	)
	resident["position"] = position
	resident["spaceId"] = space_id
	resident["regionId"] = region_id
	resident["currentPlace"] = place_name
	if changed:
		resident["movementRevision"] = int(resident.get("movementRevision", 1)) + 1
	return changed

static func validate_player_turn(action: Dictionary, is_reply: bool) -> String:
	if typeof(action.get("say")) != TYPE_STRING or typeof(action.get("narration")) != TYPE_STRING:
		return "玩家对话的文字和动作描述必须是文本"
	if String(action.get("say", "")).strip_edges().is_empty() and String(action.get("narration", "")).strip_edges().is_empty():
		return "玩家对话的文字和动作描述至少一项不能为空"
	if typeof(action.get("photos", [])) != TYPE_ARRAY:
		return "玩家对话的照片引用必须是数组"
	for photo_value: Variant in action.get("photos", []) as Array:
		if typeof(photo_value) != TYPE_DICTIONARY:
			return "玩家照片引用必须是对象"
		var photo := photo_value as Dictionary
		for key_value: Variant in photo:
			if not key_value is String or not ["ref", "mime_type"].has(key_value):
				return "玩家照片引用包含未知字段：%s" % str(key_value)
		if (
			not photo.get("ref") is String
			or String(photo.get("ref")).strip_edges().is_empty()
			or not photo.get("mime_type") is String
			or String(photo.get("mime_type")).strip_edges().is_empty()
		):
			return "玩家照片引用缺少 ref 或 mime_type"
	if is_reply and typeof(action.get("end")) != TYPE_BOOL:
		return "玩家答话的 end 必须是布尔值"
	if is_reply and bool(action.get("end", false)) and String(action.get("narration", "")).strip_edges().is_empty():
		return "玩家结束对话时需要可观察的动作描述"
	return ""

static func outdoor_path_from_route(route: Dictionary) -> Array[Vector2]:
	var path: Array[Vector2] = []
	if route.is_empty():
		return path
	for segment_value: Variant in route.get("segments", []) as Array:
		if not segment_value is Dictionary:
			return []
		var segment := segment_value as Dictionary
		if String(segment.get("kind", "")) != "route_edge":
			return []
		for point_value: Variant in segment.get("polyline", []) as Array:
			if not point_value is Dictionary:
				return []
			var point := point_value as Dictionary
			var vector := Vector2(
				float(point.get("x", 0.0)),
				float(point.get("y", 0.0)),
			)
			if not vector.is_finite():
				return []
			if path.is_empty() or not path[-1].is_equal_approx(vector):
				path.append(vector)
	return path

static func absolute_minute(time: Dictionary) -> int:
	var parts := String(time.get("clock", "00:00")).split(":")
	return (int(time.get("day", 1)) - 1) * 1440 + int(parts[0]) * 60 + int(parts[1])


static func conversation_requested_place_ids(world,
	conversation: Dictionary,
	responding_resident_id: String,
) -> Array[String]:
	var known_places: Array = world.get_place_names()
	known_places.sort_custom(
		func(left: String, right: String) -> bool:
			return left.length() > right.length()
	)
	var turns := conversation.get("turns", []) as Array
	for reverse_index in turns.size():
		var turn_value: Variant = turns[turns.size() - reverse_index - 1]
		if turn_value is not Dictionary:
			continue
		var turn := turn_value as Dictionary
		if String(turn.get("speaker_resident_id", "")) == responding_resident_id:
			continue
		var say := String(turn.get("say", "")).strip_edges()
		if say.is_empty():
			continue
		var result: Array[String] = []
		for place_id: String in known_places:
			if not place_id.is_empty() and say.contains(place_id):
				result.append(place_id)
		return result
	return []


static func prepared_same_space_action_route_errors(
	resident: Dictionary,
	prepared_action: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if String(resident.get("spaceId", "")) != "town_outdoor":
		return errors
	var path_value: Variant = prepared_action.get("pathPoints")
	if (
		not path_value is Array
		or not ROUTE_QUERY.outdoor_polyline_is_safe(path_value as Array)
	):
		errors.append("活动路线穿过室外正式碰撞")
	return errors

static func occupation_service_request_requires_presence(
	request: Dictionary,
) -> bool:
	return String(request.get("kind", "")) in (
		OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS
	)

static func direct_prop_action_available(world,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	var place_name := String(resident.get("currentPlace", ""))
	var prop_name := String(action.get("prop", "")).strip_edges()
	var verb := String(action.get("verb", "")).strip_edges()
	for other_resident_id in world.resident_order():
		if other_resident_id == resident_id:
			continue
		var other := world.residents()[other_resident_id] as Dictionary
		var other_action := other.get("currentAction", {}) as Dictionary
		if (
			String(other_action.get("type", "")) == "用道具"
			and String(
				other_action.get(
					"sourcePlace",
					other.get("currentPlace", ""),
				)
			) == place_name
			and String(other_action.get("prop", "")) == prop_name
			and String(other_action.get("verb", "")) == verb
		):
			return false
	return true

static func region_activity_position_occupied(world,
	resident_id: String,
	position_value: Array,
) -> bool:
	if position_value.size() != 2:
		return true
	var position := Vector2(
		float(position_value[0]),
		float(position_value[1]),
	)
	for other_id: String in world.resident_order():
		if other_id == resident_id:
			continue
		var other := world.residents().get(other_id, {}) as Dictionary
		if String(other.get("spaceId", "")) != "town_outdoor":
			continue
		var other_position := (
			other.get("position", Vector2.ZERO) as Vector2
		)
		if other_position.distance_to(position) < 36.0:
			return true
		var other_action := other.get("currentAction", {}) as Dictionary
		if (
			String(other_action.get("type", "")) == "用道具"
			and (
				other_action.get(
					"targetPosition",
					Vector2(INF, INF),
				) as Vector2
			).distance_to(position) < 36.0
		):
			return true
	return false

static func validate_layout_occupants(world,
	space_id: String,
	projection: Dictionary,
	errors: PackedStringArray,
) -> void:
	var navigation := projection.get("navigation", {}) as Dictionary
	for resident_name in world.resident_order():
		var resident := world.residents()[resident_name] as Dictionary
		if String(resident.get("spaceId", "")) != space_id:
			continue
		if not (resident.get("currentAction", {}) as Dictionary).is_empty():
			errors.append("居民 %s 正在该室内执行动作，不能改动布局" % resident_name)
		if not INDOOR_PATH_QUERY.is_position_walkable(
			navigation,
			resident.get("position", Vector2.ZERO) as Vector2,
		):
			errors.append("新布局会把居民 %s 压在碰撞内" % resident_name)
	if (
		String(world.player_avatar().get("spaceId", "")) == space_id
		and not INDOOR_PATH_QUERY.is_position_walkable(
			navigation,
			world.player_avatar().get("position", Vector2.ZERO) as Vector2,
		)
	):
		errors.append("新布局会把玩家压在碰撞内")

static func direct_connection_endpoint(world, current_place: String, target_place: String) -> Dictionary:
	for value: Variant in world.world_data().get("connections", []) as Array:
		var connection := value as Dictionary
		var from_end := connection.get("from", {}) as Dictionary
		var to_end := connection.get("to", {}) as Dictionary
		var direction := String(connection.get("direction", ""))
		if String(from_end.get("placeName", "")) == current_place and String(to_end.get("placeName", "")) == target_place:
			return to_end.duplicate(true)
		if direction == "双向" and String(to_end.get("placeName", "")) == current_place and String(from_end.get("placeName", "")) == target_place:
			return from_end.duplicate(true)
	return {}

static func outdoor_connection_place_for(world, place_name: String) -> String:
	for value: Variant in world.world_data().get("connections", []) as Array:
		var connection := value as Dictionary
		var from_end := connection.get("from", {}) as Dictionary
		var to_end := connection.get("to", {}) as Dictionary
		if (
			String(from_end.get("placeName", "")) == place_name
			and String(to_end.get("spaceId", "")) == "town_outdoor"
		):
			return String(to_end.get("placeName", ""))
		if (
			String(to_end.get("placeName", "")) == place_name
			and String(from_end.get("spaceId", "")) == "town_outdoor"
		):
			return String(from_end.get("placeName", ""))
	return (
		place_name
		if String(world.player_avatar().get("spaceId", "")) == "town_outdoor"
		else ""
	)

static func prop_approach_duration_minutes(world, action: Dictionary) -> int:
	var points: Array[Vector2] = []
	points.assign(action.get("pathPoints", []) as Array)
	var distance := 0.0
	for index in range(1, points.size()):
		distance += points[index - 1].distance_to(points[index])
	if distance <= 0.000001:
		return 0
	var movement_rules := world.world_data().get("movementRules", {}) as Dictionary
	var distance_per_minute := float(
		movement_rules.get("outdoorDistancePerGameMinute", 0.0)
	)
	if distance_per_minute <= 0.0:
		return 1
	return maxi(1, ceili(distance / distance_per_minute))

static func public_work_task_targets(world, targets: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in targets:
		var target := (value as Dictionary).duplicate(true)
		if String(target.get("kind", "")) in [
			"region",
			"audience_area",
		]:
			var region_id := String(target.get("ref", ""))
			for region_value: Variant in world.world_data().get(
				"perceptionRegions",
				[],
			) as Array:
				var region := region_value as Dictionary
				if String(region.get("id", "")) != region_id:
					continue
				target["ref"] = String(region.get("placeName", region_id))
				break
		result.append(target)
	return result

static func resident_is_heading_to_service_request(world,
	resident_id: String,
	request: Dictionary,
) -> bool:
	var resident := world.residents().get(resident_id, {}) as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	return (
		not resident.is_empty()
		and String(action.get("type", "")) == "去"
		and String(action.get("place", ""))
		== String(request.get("placeId", ""))
	)

static func resident_is_on_leave(world,
	resident: Dictionary,
	absolute_minute := -1,
) -> bool:
	var attendance := resident.get("attendanceState", {}) as Dictionary
	if String(attendance.get("status", "available")) != "on_leave":
		return false
	var resolved_minute := absolute_minute
	if resolved_minute < 0 and world.environment() != null:
		resolved_minute = int(world.environment().get_absolute_minute())
	return int(attendance.get("untilMinute", -1)) > resolved_minute

static func world_data_has_activity_at_place(
	world_data: Dictionary,
	activity_id: String,
	place_id: String,
) -> bool:
	return RESTORE_LAYOUT.world_data_has_activity_at_place(
		world_data,
		activity_id,
		place_id,
	)
