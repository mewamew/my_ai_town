class_name TownGoActionPrefetchRuntime
extends RefCounted


const RESIDENT_MOVEMENT_PROJECTION := preload(
	"res://world/runtime/presentation/TownResidentMovementProjection.gd"
)


static func can_prefetch(action: Dictionary) -> bool:
	if (
		String(action.get("type", "")) != "去"
		or not String(action.get("conversationFollowUpMode", "")).is_empty()
		or not String(action.get("serviceRequestId", "")).is_empty()
	):
		return false
	var route_value: Variant = action.get("route", {})
	if not route_value is Dictionary:
		return false
	var positions_value: Variant = (route_value as Dictionary).get(
		"minutePositions",
		[],
	)
	return positions_value is Array and not (positions_value as Array).is_empty()


static func arrival_projection(host, resident: Dictionary) -> Dictionary:
	var action := resident.get("currentAction", {}) as Dictionary
	if not can_prefetch(action):
		return {}
	var arrival := RESIDENT_MOVEMENT_PROJECTION.movement_target(
		resident,
		int(host._environment.get_absolute_minute()),
	)
	if arrival.is_empty():
		return {}
	var position_value: Variant = arrival.get("position")
	if not position_value is Vector2 or not (position_value as Vector2).is_finite():
		return {}
	var current_place := String(arrival.get("placeName", "")).strip_edges()
	if current_place.is_empty():
		current_place = String(action.get("place", "")).strip_edges()
	var space_id := String(arrival.get("spaceId", "")).strip_edges()
	var region_id := String(arrival.get("regionId", "")).strip_edges()
	if current_place.is_empty() or space_id.is_empty():
		return {}
	return {
		"spaceId": space_id,
		"regionId": region_id,
		"currentPlace": current_place,
		"position": position_value as Vector2,
	}
