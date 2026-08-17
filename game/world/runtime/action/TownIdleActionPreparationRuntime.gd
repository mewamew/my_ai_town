class_name TownIdleActionPreparationRuntime
extends RefCounted


const CHARACTER_MOVEMENT_QUERY := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const ACTION_GEOMETRY := preload(
	"res://world/runtime/action/TownActionGeometry.gd"
)


static func attach_parking_route(
	host,
	resident: Dictionary,
	prepared: Dictionary,
) -> bool:
	var space_id := String(resident.get("spaceId", ""))
	if space_id.is_empty():
		return true
	var portals: Array[Vector2] = ACTION_GEOMETRY.portal_positions_for_space(
		host,
		space_id,
	)
	var current_position := resident.get("position", Vector2.ZERO) as Vector2
	var near_portal := false
	for portal in portals:
		if current_position.distance_to(portal) <= host.IDLE_PORTAL_TRIGGER_DISTANCE_PX:
			near_portal = true
			break
	var occupied: Array[Vector2] = ACTION_GEOMETRY.resident_idle_occupied_positions(
		host,
		String(resident.get("residentId", "")),
		space_id,
	)
	var crowded := ACTION_GEOMETRY.point_near_any(
		current_position,
		occupied,
		host.IDLE_RESIDENT_CLEARANCE_PX,
	)
	if not near_portal and not crowded:
		return true
	var candidates: Array[Dictionary] = []
	if space_id == "town_outdoor":
		candidates = outdoor_parking_candidates(
			host,
			current_position,
			portals,
			occupied,
		)
	else:
		candidates = CHARACTER_MOVEMENT_QUERY.indoor_idle_parking_candidates(
			ACTION_GEOMETRY.indoor_navigation_for_space(host, space_id),
			current_position,
			portals,
			occupied,
		) as Array[Dictionary]
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
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
	)
	var selected: Dictionary = candidates[0]
	var path_points: Array[Vector2] = []
	path_points.assign(selected.get("path", []) as Array)
	var move_duration: int = ACTION_GEOMETRY.movement_duration_for_path(
		host,
		path_points,
	)
	prepared["idlePathPoints"] = path_points
	prepared["idleTargetPosition"] = selected.get(
		"position",
		current_position,
	) as Vector2
	prepared["idleMoveDurationMinutes"] = move_duration
	prepared["completeAbsoluteMinute"] = maxi(
		int(prepared.get("completeAbsoluteMinute", 0)),
		int(prepared.get("startedAbsoluteMinute", 0)) + move_duration + 1,
	)
	return true



static func prepare_departure_action(
	host,
	resident: Dictionary,
	prepared_wait: Dictionary,
) -> Dictionary:
	var current_place := String(resident.get("currentPlace", ""))
	var target_places: Array[String] = []
	for value: Variant in host.world_definition.world_data.get("places", []) as Array:
		var place := value as Dictionary
		var target_place := String(place.get("name", ""))
		if (
			target_place.is_empty()
			or target_place == current_place
			or String(place.get("type", "")) != "公共地点"
		):
			continue
		target_places.append(target_place)
	if target_places.is_empty():
		return {}
	target_places.sort()
	var rotation := posmod(
		hash(
			"%s:%s" % [
				String(resident.get("residentId", "")),
				current_place,
			]
		),
		target_places.size(),
	)
	var candidate_count: int = mini(
		target_places.size(),
		host.IDLE_DEPARTURE_PLACE_CANDIDATE_LIMIT,
	)
	for offset in candidate_count:
		var target_place := target_places[
			(rotation + offset) % target_places.size()
		]
		var go_action := {
			"action_id": String(
				prepared_wait.get("action_id", "")
			),
			"type": "去",
			"place": target_place,
			"line": (
				"%s；这里暂时没有空位，先去%s"
				% [
					String(prepared_wait.get("line", "")),
					target_place,
				]
			),
		}
		var preparation: Dictionary = host.ACTION_PREPARATION_RUNTIME.prepare_go_action(host, resident, go_action)
		if preparation.get("ok") == true:
			return preparation
	return {}



static func outdoor_parking_candidates(
	host,
	current_position: Vector2,
	portals: Array[Vector2],
	occupied: Array[Vector2],
) -> Array[Dictionary]:
	return CHARACTER_MOVEMENT_QUERY.outdoor_idle_parking_candidates(
		host.world_definition.world_data.get("movementNetwork", {}) as Dictionary,
		current_position,
		portals,
		occupied,
	) as Array[Dictionary]
