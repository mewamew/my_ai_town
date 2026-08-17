class_name TownActionValidityPolicy
extends RefCounted


const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const PROP_QUERY := preload(
	"res://world/data/town/TownWorldPropQuery.gd"
)


static func is_valid(
	host,
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	match String(action.get("type", "")):
		"去":
			return _go_is_valid(host, action)
		"用道具":
			return _prop_is_valid(host, resident, action)
		"调整营业":
			var control: Dictionary = host.PLACE_SERVICE_COMMAND_RUNTIME.service_control(host, resident)
			return (
				not control.is_empty()
				and String(control.get("place_id", ""))
					== String(action.get("place_id", ""))
				and bool(control.get("open", false))
					!= bool(action.get("open", false))
			)
		"托人传话":
			var recipient_id := String(
				action.get("recipient_resident_id", ""),
			)
			return (
				host.resident_registry.records.has(recipient_id)
				and recipient_id != String(resident.get("residentId", ""))
			)
		"待着", "搭话", "答话":
			return true
	return false


static func _go_is_valid(host, action: Dictionary) -> bool:
	var route := action.get("route", {}) as Dictionary
	var positions := route.get("minutePositions", []) as Array
	if (
		positions.is_empty()
		or host.get_place_detail(String(action.get("place", ""))).is_empty()
	):
		return false
	var now := int(host._environment.get_absolute_minute())
	var elapsed := maxi(
		0,
		now - int(action.get("startedAbsoluteMinute", now)),
	)
	var sample_value: Variant = positions[mini(elapsed, positions.size() - 1)]
	if sample_value is not Dictionary:
		return false
	var sample := sample_value as Dictionary
	var position_value: Variant = sample.get("position")
	if position_value is not Dictionary:
		return false
	var point := position_value as Dictionary
	var membership := PERCEPTION_RUNTIME._membership(
		host,
		String(sample.get("spaceId", "")),
		Vector2(
			float(point.get("x", 0.0)),
			float(point.get("y", 0.0)),
		),
	)
	return (
		not membership.is_empty()
		and String(membership.get("regionId", ""))
			== String(sample.get("regionId", ""))
		and String(membership.get("placeName", ""))
			== String(sample.get("placeName", ""))
	)


static func _prop_is_valid(
	host,
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	var execution := host._activity_runtime.execution_for_action(
		String(resident.get("residentId", "")),
		String(action.get("action_id", "")),
	) as Dictionary
	if (
		not execution.is_empty()
		and String(execution.get("targetType", "")) == "region"
	):
		var target_position := action.get(
			"targetPosition",
			Vector2(INF, INF),
		) as Vector2
		var membership := PERCEPTION_RUNTIME._membership(
			host,
			"town_outdoor",
			target_position,
		)
		return (
			target_position.is_finite()
			and not (action.get("pathPoints", []) as Array).is_empty()
			and String(membership.get("placeName", ""))
				== String(execution.get("placeId", ""))
		)
	if (
		not execution.is_empty()
		and String(resident.get("currentPlace", ""))
			!= String(execution.get("placeId", ""))
	):
		return false
	return not PROP_QUERY.interaction_plan(
		host.PROP_ACTION_PREPARER.query_data(host),
		String(
			action.get("sourcePlace", resident.get("currentPlace", "")),
		),
		String(action.get("prop", "")),
		String(action.get("verb", "")),
		resident.get("position", Vector2.ZERO) as Vector2,
	).is_empty()
