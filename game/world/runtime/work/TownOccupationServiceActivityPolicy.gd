class_name TownOccupationServiceActivityPolicy
extends RefCounted


static func apply_visitor_availability(
	option: Dictionary,
	collect_disabled_reason: String,
	onsite_staffed: bool,
) -> void:
	if (
		not bool(option.get("available", false))
		or String(option.get("role", "")) != "visitor"
	):
		return
	var activity_id := String(option.get("activityId", ""))
	if activity_id in [
		"activity_dining_eat_meal",
		"activity_dining_return_dishes",
	]:
		option["available"] = false
		option["disabledReason"] = "DINING_MEAL_ROUTINE_ONLY"
		return
	if activity_id == "activity_dining_collect_meal":
		if not collect_disabled_reason.is_empty():
			option["available"] = false
			option["disabledReason"] = collect_disabled_reason
		return
	if not onsite_staffed:
		option["available"] = false
		option["disabledReason"] = "OCCUPATION_SERVICE_UNSTAFFED"
