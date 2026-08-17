extends RefCounted


# O 域迁移第三件:路径/几何工具族——纯静态五件+经读接口的世界几何四件。

static func vector_path_from_payload(values: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for value: Variant in values:
		if not value is Dictionary:
			return []
		var point := value as Dictionary
		var vector := Vector2(
			float(point.get("x", 0.0)),
			float(point.get("y", 0.0)),
		)
		if not vector.is_finite():
			return []
		if result.is_empty() or result[-1].distance_to(vector) > 0.001:
			result.append(vector)
	return result

static func polyline_distance(points: Array[Vector2]) -> float:
	var result := 0.0
	for index in range(1, points.size()):
		result += points[index - 1].distance_to(points[index])
	return result

static func polyline_prefix(
	points: Array[Vector2],
	target_distance: float,
) -> Array[Vector2]:
	if points.is_empty() or target_distance < 0.0:
		return []
	var result: Array[Vector2] = [points[0]]
	var remaining := target_distance
	for index in range(1, points.size()):
		var segment_length := points[index - 1].distance_to(points[index])
		if segment_length <= remaining + 0.001:
			if result[-1].distance_to(points[index]) > 0.001:
				result.append(points[index])
			remaining -= segment_length
			if remaining <= 0.001:
				break
			continue
		var ratio := remaining / segment_length
		result.append(points[index - 1].lerp(points[index], ratio))
		remaining = 0.0
		break
	return result

static func point_near_any(
	point: Vector2,
	others: Array[Vector2],
	clearance: float,
) -> bool:
	for other in others:
		if point.distance_to(other) < clearance:
			return true
	return false

static func point_along_polyline(points: Array[Vector2], ratio: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	var target := total * clampf(ratio, 0.0, 1.0)
	var cursor := 0.0
	for index in range(1, points.size()):
		var length := points[index - 1].distance_to(points[index])
		if target <= cursor + length or index == points.size() - 1:
			var local_ratio := 0.0 if length <= 0.000001 else (target - cursor) / length
			return points[index - 1].lerp(points[index], clampf(local_ratio, 0.0, 1.0))
		cursor += length
	return points[-1]


static func movement_duration_for_path(world, points: Array[Vector2]) -> int:
	var distance := 0.0
	for index in range(1, points.size()):
		distance += points[index - 1].distance_to(points[index])
	if distance <= 0.001:
		return 0
	var movement_rules := world.world_data().get("movementRules", {}) as Dictionary
	var distance_per_minute := float(
		movement_rules.get("outdoorDistancePerGameMinute", 0.0)
	)
	if distance_per_minute <= 0.0:
		return 1
	return maxi(1, ceili(distance / distance_per_minute))


static func reverse_polyline_to_ratio(
	points: Array[Vector2],
	ratio: float,
) -> Array[Vector2]:
	if points.is_empty():
		return []
	var current := point_along_polyline(points, ratio)
	var result: Array[Vector2] = [current]
	var target_distance := 0.0
	for index in range(1, points.size()):
		target_distance += points[index - 1].distance_to(points[index])
	target_distance *= clampf(ratio, 0.0, 1.0)
	var cursor := 0.0
	var segment_index := 0
	for index in range(1, points.size()):
		var length := points[index - 1].distance_to(points[index])
		if target_distance <= cursor + length:
			segment_index = index - 1
			break
		cursor += length
	for index in range(segment_index, -1, -1):
		if not result[-1].is_equal_approx(points[index]):
			result.append(points[index])
	return result

static func indoor_navigation_for_space(world, space_id: String) -> Dictionary:
	for value: Variant in world.world_data().get("indoorNavigation", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("spaceId", ""))
				== space_id
		):
			return (value as Dictionary).duplicate(true)
	return {}

static func portal_positions_for_space(world, space_id: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for value: Variant in world.world_data().get("connections", []) as Array:
		if not value is Dictionary:
			continue
		var connection := value as Dictionary
		for endpoint_key in ["from", "to"]:
			var endpoint := connection.get(endpoint_key, {}) as Dictionary
			if String(endpoint.get("spaceId", "")) != space_id:
				continue
			var position := endpoint.get("position", {}) as Dictionary
			var point := Vector2(
				float(position.get("x", 0.0)),
				float(position.get("y", 0.0)),
			)
			if point.is_finite() and not result.has(point):
				result.append(point)
	return result

static func resident_idle_occupied_positions(world,
	resident_id: String,
	space_id: String,
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for other_id in world.resident_order():
		if other_id == resident_id:
			continue
		var other := world.residents().get(other_id, {}) as Dictionary
		if (
			not world.resident_is_present(other)
			or String(other.get("spaceId", "")) != space_id
		):
			continue
		var current: Variant = other.get("position")
		if current is Vector2 and (current as Vector2).is_finite():
			result.append(current as Vector2)
		var action := other.get("currentAction", {}) as Dictionary
		var idle_target: Variant = action.get("idleTargetPosition")
		if (
			String(action.get("type", "")) == "待着"
			and idle_target is Vector2
			and (idle_target as Vector2).is_finite()
		):
			result.append(idle_target as Vector2)
	return result
