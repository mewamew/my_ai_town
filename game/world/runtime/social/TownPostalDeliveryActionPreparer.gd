class_name TownPostalDeliveryActionPreparer
extends RefCounted


const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")
const INDOOR_PATH_QUERY := preload(
	"res://world/data/town/TownIndoorPropPathQuery.gd"
)
const ACTION_GEOMETRY := preload(
	"res://world/runtime/action/TownActionGeometry.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const APPROACH_STOP_DISTANCE_PX := 96.0


static func prepare(
	world_data: Dictionary,
	indoor_navigation: Dictionary,
	resident: Dictionary,
	target: Dictionary,
	prepared_action: Dictionary,
	membership_for_position: Callable,
) -> Dictionary:
	var prepared := prepared_action.duplicate(true)
	var resident_space := String(resident.get("spaceId", ""))
	var target_space := String(target.get("spaceId", ""))
	var target_region := String(target.get("regionId", ""))
	var target_place := String(target.get("currentPlace", ""))
	var target_position := target.get("position", Vector2.ZERO) as Vector2
	if (
		resident_space.is_empty()
		or target_space.is_empty()
		or target_region.is_empty()
		or target_place.is_empty()
		or not target_position.is_finite()
	):
		return {"ok": false, "errors": ["收件人当前没有可接近的位置"]}
	prepared["targetSpaceId"] = target_space
	prepared["targetRegionId"] = target_region
	prepared["targetPlace"] = target_place
	prepared["expectedTargetPosition"] = target_position
	if resident_space == target_space:
		var path: Array[Vector2] = []
		if resident_space == "town_outdoor":
			var route := ROUTE_QUERY.find_route_to_outdoor_position(
				world_data,
				{
					"position": resident.get("position", Vector2.ZERO),
					"spaceId": resident_space,
					"regionId": resident.get("regionId", ""),
					"currentPlace": resident.get("currentPlace", ""),
				},
				target_position,
				target_region,
				resident.get("routeConnector", []) as Array,
			) as Dictionary
			path = ACTION_SUPPORT.outdoor_path_from_route(route)
		else:
			path.assign(
				INDOOR_PATH_QUERY.find_path(
					indoor_navigation,
					resident.get("position", Vector2.ZERO) as Vector2,
					target_position,
				) as Array,
			)
		if path.is_empty():
			return {"ok": false, "errors": ["当前没有到收件人身边的安全路线"]}
		var full_distance := ACTION_GEOMETRY.polyline_distance(path)
		var stop_distance := minf(APPROACH_STOP_DISTANCE_PX, full_distance)
		var trimmed := ACTION_GEOMETRY.polyline_prefix(
			path,
			maxf(0.0, full_distance - stop_distance),
		)
		if not trimmed.is_empty():
			var endpoint_membership := membership_for_position.call(
				resident_space,
				trimmed[-1],
			) as Dictionary
			if String(endpoint_membership.get("regionId", "")) == target_region:
				path = trimmed
		prepared["approachMode"] = "same_space_path"
		prepared["pathPoints"] = path
		prepared["targetPosition"] = path[-1]
		prepared["durationMinutes"] = _approach_duration_minutes(
			world_data,
			path,
		)
		var return_connector := path.duplicate()
		return_connector.reverse()
		prepared["returnRouteConnector"] = return_connector
		prepared["consumeRouteConnector"] = not (
			resident.get("routeConnector", []) as Array
		).is_empty()
		if not ACTION_SUPPORT.prepared_same_space_action_route_errors(
			resident,
			prepared,
		).is_empty():
			return {"ok": false, "errors": ["当前没有到收件人身边的安全路线"]}
		return {"ok": true, "action": prepared}
	if target_place == String(resident.get("currentPlace", "")):
		return {"ok": false, "errors": ["收件人当前不在可接近的地图空间"]}
	var approach_route := ROUTE_QUERY.find_route_from_state(
		world_data,
		{
			"position": resident.get("position", Vector2.ZERO),
			"spaceId": resident_space,
			"regionId": resident.get("regionId", ""),
			"currentPlace": resident.get("currentPlace", ""),
		},
		target_place,
		resident.get("routeConnector", []) as Array,
	) as Dictionary
	if approach_route.is_empty():
		return {"ok": false, "errors": ["当前没有到收件人所在地点的固定路线"]}
	prepared["approachMode"] = "place_route"
	prepared["approachRoute"] = approach_route.duplicate(true)
	prepared["durationMinutes"] = int(
		approach_route.get("durationMinutes", 0),
	)
	prepared["consumeRouteConnector"] = not (
		resident.get("routeConnector", []) as Array
	).is_empty()
	return {"ok": true, "action": prepared}


static func _approach_duration_minutes(
	world_data: Dictionary,
	path: Array[Vector2],
) -> int:
	var distance := ACTION_GEOMETRY.polyline_distance(path)
	if distance <= 0.000001:
		return 0
	var movement_rules := world_data.get("movementRules", {}) as Dictionary
	var distance_per_minute := float(
		movement_rules.get("outdoorDistancePerGameMinute", 0.0),
	)
	if distance_per_minute <= 0.0:
		return 1
	return maxi(1, ceili(distance / distance_per_minute))
