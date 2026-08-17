class_name TownActivityRoutineActivationRuntime
extends RefCounted
const ACTIVITY_STEP_EXECUTION_RUNTIME := preload("res://world/runtime/activity/TownActivityStepExecutionRuntime.gd")


const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_PROJECTION_MODULE := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const LEGACY_PROP_ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownLegacyPropActivityRuntime.gd"
)

const ACTIVITY_ROUTINE_DURATION_MINUTES := {
	"work": 20,
	"meal": 45,
}
const ACTIVITY_ROUTINE_STEP_CAP_MINUTES := {
	"work": 20,
	"meal": 12,
}


static func activate(
	host,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	source_action: Dictionary,
	conversation_end_reason: String,
	mapping: Dictionary,
	descriptor: Dictionary,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var group := String(descriptor.get("group", ""))
	var routine_id := "routine:%s:%s" % [
		resident_id,
		String(source_action.get("action_id", "")),
	]
	var absolute_minute := int(host._environment.get_absolute_minute())
	host.activity_routine_state.records[resident_id] = {
		"routineId": routine_id,
		"sourceActionId": String(source_action.get("action_id", "")),
		"placeId": String(mapping.get("placeId", "")),
		"group": group,
		"mealPeriodRef": DINING_SERVICE.meal_period_ref_for_routine(
			host,
			group,
			absolute_minute,
		),
		"endAbsoluteMinute": absolute_minute + int(ACTIVITY_ROUTINE_DURATION_MINUTES.get(group, 30)),
		"sequence": 0,
		"lastActivityId": String(mapping.get("activityId", "")),
		"lastPhase": String(descriptor.get("phase", "")),
		"visitedActivityIds": [String(mapping.get("activityId", ""))],
		"choiceSeed": hash("%s:%d:%s" % [
			resident_id,
			absolute_minute,
			String(source_action.get("action_id", "")),
		]),
	}
	var target := {
		"activityId": String(mapping.get("activityId", "")),
		"placeId": String(mapping.get("placeId", "")),
	}
	var preferred_slot_id := String(mapping.get("preferredSlotId", "")).strip_edges()
	if not preferred_slot_id.is_empty():
		target["preferredSlotId"] = preferred_slot_id
	var step := {
		"stepId": "step-0",
		"operation": "activity.perform",
		"target": target,
		"params": {"reason": String(source_action.get("line", ""))},
	}
	var performed: Dictionary = ACTIVITY_STEP_EXECUTION_RUNTIME.perform(host,
		resident_id,
		routine_id,
		0,
		step,
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_DIRECT,
		"",
		int(ACTIVITY_ROUTINE_STEP_CAP_MINUTES.get(group, 15)),
		allow_current_activity_interrupt,
	)
	if performed.get("ok") != true:
		host.activity_routine_state.records.erase(resident_id)
		return LEGACY_PROP_ACTIVITY_RUNTIME.reject_activation(
			host,
			resident_id,
			source_action,
			performed,
			conversation_end_reason,
		)
	if not conversation_end_reason.is_empty():
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
			host,
			resident_id,
		)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(
				host,
				host._traveler_relationship_state,
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				"rejected" if conversation_end_reason == "拒绝接话" else "interrupted",
			)
	var routine_snapshot := (
		host.activity_routine_state.records.get(resident_id, {}) as Dictionary
	).duplicate(true)
	return {
		"ok": true,
		"stale": false,
		"status": "accepted",
		"action": host.ACTION_PROJECTION_MODULE.public_current_action(
			resident.get("currentAction", {}) as Dictionary
		),
		"actionPhase": ACTION_PRESENTATION._resident_action_phase_projection(host, resident),
		"activity": (performed.get("execution", {}) as Dictionary).duplicate(true),
		# Activity lifecycle callbacks run synchronously. A listener may finish or
		# interrupt the routine before activation returns, so the entry is not
		# guaranteed to still exist here.
		"routine": routine_snapshot,
	}
