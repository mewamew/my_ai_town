class_name TownResidentMovementProjection
extends RefCounted


static func project(
	resident_id: String,
	resident: Dictionary,
	absolute_minute: int,
	world_revision: int,
	conversation_suspended: bool,
	outdoor_distance_per_minute: float,
) -> Dictionary:
	if conversation_suspended:
		var held_position := resident.get("position", Vector2.ZERO) as Vector2
		return {
			"residentId": resident_id,
			"spaceId": String(resident.get("spaceId", "")),
			"regionId": String(resident.get("regionId", "")),
			"currentPlace": String(resident.get("currentPlace", "")),
			"position": held_position,
			"target": {
				"spaceId": String(resident.get("spaceId", "")),
				"position": held_position,
			},
			"isMoving": false,
			"presentationPath": [],
			"routeCrossesPortal": false,
			"movementRevision": int(resident.get("movementRevision", 1)),
			"worldRevision": world_revision,
		}
	var target := movement_target(resident, absolute_minute)
	var is_moving := not target.is_empty()
	if target.is_empty():
		target = {
			"spaceId": String(resident.get("spaceId", "")),
			"position": resident.get("position", Vector2.ZERO) as Vector2,
		}
	var movement_blocked := false
	var action := resident.get("currentAction", {}) as Dictionary
	if String(action.get("type", "")) == "用道具":
		var elapsed := maxi(
			0,
			absolute_minute - int(
				action.get("startedAbsoluteMinute", absolute_minute),
			),
		)
		movement_blocked = (
			elapsed
			>= _prop_approach_duration_minutes(
				action,
				outdoor_distance_per_minute,
			)
		)
	return {
		"residentId": resident_id,
		"spaceId": String(resident.get("spaceId", "")),
		"regionId": String(resident.get("regionId", "")),
		"currentPlace": String(resident.get("currentPlace", "")),
		"position": resident.get("position", Vector2.ZERO) as Vector2,
		"target": target,
		"isMoving": is_moving and not movement_blocked,
		"presentationPath": presentation_path(resident, absolute_minute),
		"routeCrossesPortal": _route_crosses_portal(resident),
		"movementRevision": int(resident.get("movementRevision", 1)),
		"worldRevision": world_revision,
	}


static func presentation_path(
	resident: Dictionary,
	absolute_minute: int,
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var action := resident.get("currentAction", {}) as Dictionary
	var action_type := String(action.get("type", ""))
	if action_type == "待着" and action.has("idlePathPoints"):
		var elapsed := maxi(
			0,
			absolute_minute - int(
				action.get("startedAbsoluteMinute", absolute_minute),
			),
		)
		if elapsed >= int(action.get("idleMoveDurationMinutes", 0)):
			return result
		for point_value: Variant in action.get("idlePathPoints", []) as Array:
			if point_value is not Vector2:
				return []
			var point := point_value as Vector2
			if not point.is_finite():
				return []
			if result.is_empty() or result[-1].distance_to(point) > 0.001:
				result.append(point)
		return result
	if action_type == "用道具":
		for point_value: Variant in action.get("pathPoints", []) as Array:
			if point_value is not Vector2:
				return []
			var point := point_value as Vector2
			if not point.is_finite():
				return []
			if result.is_empty() or result[-1].distance_to(point) > 0.001:
				result.append(point)
		return result
	if action_type != "去":
		return result
	var route := action.get("route", {}) as Dictionary
	var positions := route.get("minutePositions", []) as Array
	if positions.is_empty():
		return result
	var elapsed := maxi(
		0,
		absolute_minute - int(
			action.get("startedAbsoluteMinute", absolute_minute),
		),
	)
	var sample_index := mini(elapsed, positions.size() - 1)
	var sample_value: Variant = positions[sample_index]
	if sample_value is not Dictionary:
		return result
	var path_value: Variant = (sample_value as Dictionary).get(
		"presentationPath",
		[],
	)
	if path_value is not Array:
		return result
	for point_value: Variant in path_value as Array:
		if point_value is not Dictionary:
			return []
		var point := point_value as Dictionary
		var x_value: Variant = point.get("x")
		var y_value: Variant = point.get("y")
		if (
			typeof(x_value) not in [TYPE_INT, TYPE_FLOAT]
			or typeof(y_value) not in [TYPE_INT, TYPE_FLOAT]
		):
			return []
		var position := Vector2(float(x_value), float(y_value))
		if not position.is_finite():
			return []
		if result.is_empty() or result[-1].distance_to(position) > 0.001:
			result.append(position)
	return result


static func _route_crosses_portal(resident: Dictionary) -> bool:
	var action := resident.get("currentAction", {}) as Dictionary
	if String(action.get("type", "")) != "去":
		return false
	var route := action.get("route", {}) as Dictionary
	for segment_value: Variant in route.get("segments", []) as Array:
		if (
			segment_value is Dictionary
			and String((segment_value as Dictionary).get("kind", ""))
				== "connection"
		):
			return true
	return false


static func movement_target(
	resident: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var action := resident.get("currentAction", {}) as Dictionary
	if (
		String(action.get("type", "")) == "待着"
		and action.get("idleTargetPosition") is Vector2
	):
		var elapsed := maxi(
			0,
			absolute_minute - int(
				action.get("startedAbsoluteMinute", absolute_minute),
			),
		)
		if elapsed < int(action.get("idleMoveDurationMinutes", 0)):
			return {
				"spaceId": String(resident.get("spaceId", "")),
				"regionId": String(resident.get("regionId", "")),
				"placeName": String(resident.get("currentPlace", "")),
				"position": action.get("idleTargetPosition") as Vector2,
			}
	if String(action.get("type", "")) == "去":
		var positions := (
			(action.get("route", {}) as Dictionary).get("minutePositions", [])
			as Array
		)
		if positions.is_empty():
			return {}
		var sample := positions[-1] as Dictionary
		var position := sample.get("position", {}) as Dictionary
		return {
			"spaceId": String(sample.get("spaceId", "")),
			"regionId": String(sample.get("regionId", "")),
			"placeName": String(sample.get("placeName", "")),
			"position": Vector2(
				float(position.get("x", 0.0)),
				float(position.get("y", 0.0)),
			),
		}
	if String(action.get("type", "")) == "用道具":
		return {
			"spaceId": String(resident.get("spaceId", "")),
			"regionId": String(resident.get("regionId", "")),
			"placeName": String(resident.get("currentPlace", "")),
			"position": action.get(
				"targetPosition",
				resident.get("position", Vector2.ZERO),
			) as Vector2,
		}
	return {}


static func _prop_approach_duration_minutes(
	action: Dictionary,
	outdoor_distance_per_minute: float,
) -> int:
	var points: Array[Vector2] = []
	points.assign(action.get("pathPoints", []) as Array)
	var distance := 0.0
	for index in range(1, points.size()):
		distance += points[index - 1].distance_to(points[index])
	if distance <= 0.000001:
		return 0
	if outdoor_distance_per_minute <= 0.0:
		return 1
	return maxi(1, ceili(distance / outdoor_distance_per_minute))
