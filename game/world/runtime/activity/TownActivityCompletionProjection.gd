class_name TownActivityCompletionProjection
extends RefCounted


static func resident_effects(
	applied_effects: Dictionary,
	active_routine: Dictionary,
) -> Dictionary:
	if (
		String(active_routine.get("group", "")) == "work"
		and int(active_routine.get("sequence", 0)) > 0
	):
		return {}
	return applied_effects


static func completed_execution(
	activity_execution: Dictionary,
	committed_execution: Dictionary,
	duration_minutes: int,
) -> Dictionary:
	var execution := activity_execution.duplicate(true)
	for key: Variant in committed_execution:
		execution[key] = committed_execution.get(key)
	execution["performedDurationMinutes"] = maxi(1, duration_minutes)
	return execution


static func completion_text(execution: Dictionary) -> String:
	return "已完成%s" % String(execution.get("label", "活动"))
