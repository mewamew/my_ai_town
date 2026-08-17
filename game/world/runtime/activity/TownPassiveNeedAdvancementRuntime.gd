class_name TownPassiveNeedAdvancementRuntime
extends RefCounted


const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)


static func advance(host, absolute_minute: int) -> void:
	if posmod(absolute_minute, host.PASSIVE_NEED_TICK_MINUTES) != 0:
		return
	var lap_usec := Time.get_ticks_usec() if host.telemetry.advance_profile_enabled else 0
	for resident_id in host.resident_registry.order:
		var resident := host.resident_registry.records[resident_id] as Dictionary
		if not host.resident_is_present(resident) or resident_is_sleeping(host, resident):
			continue
		var current_action := resident.get("currentAction", {}) as Dictionary
		var activity_execution := host._activity_runtime.execution_for_action(
			resident_id,
			String(current_action.get("action_id", "")),
		) as Dictionary
		if not activity_execution.is_empty():
			continue
		var nearby := resident.get("nearby", []) as Array
		var effects := {
			"energy": -2,
			"satiety": -3,
			"socialNeed": -1 if not nearby.is_empty() else 2,
			"solitudeNeed": 2 if not nearby.is_empty() else -1,
		}
		var previous: Dictionary = (
			resident.get("activityState", host.ACTIVITY_SCALARS.empty_activity_state()) as Dictionary
		).duplicate(true)
		var next: Dictionary = host.ACTIVITY_SCALARS.next_activity_state(
			resident,
			effects,
			host.ACTIVITY_STATE_KEYS,
		)
		if next == previous:
			continue
		resident["activityState"] = next
		host.ACTIVITY_SCALARS.sync_body_from_activity_needs(resident, next)
		if ACTIVITY_SCALARS.hunger_crossed_decision_threshold(previous, next):
			host._schedule_decision(resident_id, false)
		lap_usec = host.telemetry.lap(
			host.telemetry.advance_profile_scratch,
			"passiveNeedsComputeUsec",
			lap_usec,
		)
	host.telemetry.lap(
		host.telemetry.advance_profile_scratch,
		"passiveNeedsComputeUsec",
		lap_usec,
	)


static func resident_is_sleeping(host, resident: Dictionary) -> bool:
	var action := resident.get("currentAction", {}) as Dictionary
	if String(action.get("type", "")) == "用道具" and String(action.get("verb", "")) == "睡觉":
		return true
	var execution := host._activity_runtime.execution_for_action(
		String(resident.get("residentId", "")),
		String(action.get("action_id", "")),
	) as Dictionary
	return String(execution.get("activityId", "")) == "activity_home_sleep"
