class_name TownPropActionPreparer
extends RefCounted


const PROP_QUERY := preload(
	"res://world/data/town/TownWorldPropQuery.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)


static func prepare_for_host(
	host,
	resident: Dictionary,
	action: Dictionary,
) -> Dictionary:
	return prepare(
		query_data(host),
		int(host._environment.get_absolute_minute()),
		resident,
		action,
	)


static func query_data(host) -> Dictionary:
	return host._dynamic_prop_runtime.query_data(host.world_definition.world_data)


static func is_layout_override_action(
	host,
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	return host._dynamic_prop_runtime.is_layout_override_action(
		host.world_definition.world_data,
		resident,
		action,
	)


static func prepare(
	prop_query_data: Dictionary,
	absolute_minute: int,
	resident: Dictionary,
	action: Dictionary,
) -> Dictionary:
	var path: Array[Vector2] = [resident.get("position", Vector2.ZERO) as Vector2]
	for point_value: Variant in resident.get("routeConnector", []) as Array:
		var connector_point := point_value as Vector2
		if not path[-1].is_equal_approx(connector_point):
			path.append(connector_point)
	var plan := PROP_QUERY.interaction_plan(
		prop_query_data,
		String(resident.get("currentPlace", "")),
		String(action.get("prop", "")),
		String(action.get("verb", "")),
		path[-1],
	) as Dictionary
	if plan.is_empty():
		return {"ok": false, "errors": ["当前地点没有这个可用道具或动作词"]}
	if String(plan.get("spaceId", "")) != String(resident.get("spaceId", "")):
		return {"ok": false, "errors": ["道具与居民不在同一个地图空间"]}
	for point_value: Variant in plan.get("approachPolyline", []) as Array:
		var point := point_value as Vector2
		if not path[-1].is_equal_approx(point):
			path.append(point)
	var prepared := action.duplicate(true)
	prepared["startedAbsoluteMinute"] = absolute_minute
	prepared["sourcePlace"] = String(resident.get("currentPlace", ""))
	prepared["durationMinutes"] = int(plan.get("durationMinutes", 0))
	prepared["pathPoints"] = path
	prepared["effects"] = (plan.get("effects", {}) as Dictionary).duplicate(true)
	prepared["targetPosition"] = plan.get(
		"position",
		resident.get("position", Vector2.ZERO),
	) as Vector2
	prepared["dynamicPropId"] = String(plan.get("propId", ""))
	var return_connector := (plan.get("approachPolyline", []) as Array).duplicate()
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
			"errors": ["当前没有到这个道具的安全路线"],
		}
	prepared["pathClearanceVerified"] = true
	return {"ok": true, "action": prepared}
