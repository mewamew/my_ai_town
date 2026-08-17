class_name TownActivityRegionActionPreparer
extends RefCounted


const ROUTE_QUERY := preload(
	"res://world/data/town/TownWorldRouteQuery.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)


static func prepare(
	world_data: Dictionary,
	absolute_minute: int,
	resident: Dictionary,
	action: Dictionary,
	candidate: Dictionary,
) -> Dictionary:
	var position_value := candidate.get("memberPosition", []) as Array
	var region_id := String(candidate.get("targetRegionId", ""))
	if position_value.size() != 2 or region_id.is_empty():
		return {"ok": false, "errors": ["活动区域没有可用落点"]}
	var target_position := Vector2(
		float(position_value[0]),
		float(position_value[1]),
	)
	var route := ROUTE_QUERY.find_route_to_outdoor_position(
		world_data,
		{
			"position": resident.get("position", Vector2.ZERO),
			"spaceId": resident.get("spaceId", ""),
			"regionId": resident.get("regionId", ""),
			"currentPlace": resident.get("currentPlace", ""),
		},
		target_position,
		region_id,
		resident.get("routeConnector", []) as Array,
	) as Dictionary
	if route.is_empty():
		return {"ok": false, "errors": ["当前没有到这个活动区域落点的合法路线"]}
	var path: Array[Vector2] = []
	for segment_value: Variant in route.get("segments", []) as Array:
		if not segment_value is Dictionary:
			return {"ok": false, "errors": ["活动区域路线数据无效"]}
		var segment := segment_value as Dictionary
		if String(segment.get("kind", "")) != "route_edge":
			return {"ok": false, "errors": ["活动区域路线不能跨地图空间"]}
		for point_value: Variant in segment.get("polyline", []) as Array:
			if not point_value is Dictionary:
				return {"ok": false, "errors": ["活动区域路线坐标无效"]}
			var point := point_value as Dictionary
			var vector := Vector2(
				float(point.get("x", 0.0)),
				float(point.get("y", 0.0)),
			)
			if path.is_empty() or not path[-1].is_equal_approx(vector):
				path.append(vector)
	if path.is_empty():
		path.append(resident.get("position", Vector2.ZERO) as Vector2)
	if not path[-1].is_equal_approx(target_position):
		path.append(target_position)
	var prepared := action.duplicate(true)
	prepared["startedAbsoluteMinute"] = absolute_minute
	prepared["sourcePlace"] = String(resident.get("currentPlace", ""))
	prepared["durationMinutes"] = 0
	prepared["pathPoints"] = path
	prepared["effects"] = {}
	prepared["targetPosition"] = target_position
	prepared["dynamicPropId"] = ""
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
		return {
			"ok": false,
			"errors": ["当前没有到这个活动区域落点的安全路线"],
		}
	prepared["pathClearanceVerified"] = true
	return {"ok": true, "action": prepared}
