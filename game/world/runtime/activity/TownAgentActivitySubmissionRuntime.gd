class_name TownAgentActivitySubmissionRuntime
extends RefCounted
const ACTIVITY_STEP_EXECUTION_RUNTIME := preload("res://world/runtime/activity/TownActivityStepExecutionRuntime.gd")


const ACTION_PREVIEW_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreviewRuntime.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)


const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const ACTION_PROJECTION_MODULE := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const LEGACY_PROP_ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownLegacyPropActivityRuntime.gd"
)


static func submit(
	host,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var activity_id := String(action.get("activity_id", "")).strip_edges()
	if activity_id.is_empty() or String(action.get("line", "")).strip_edges().is_empty():
		return ACTION_RESULT_RUNTIME.reject_invalid(host,
			resident_id,
			resident,
			action,
			"做活动必须包含当前可做的 activity_id 和非空 line",
		)
	var available := false
	for option_value: Variant in host.AGENT_WAKE_CONTEXT_RUNTIME.available_activities(host,
		resident,
		true,
		activity_id,
		1,
	):
		if String((option_value as Dictionary).get("activity_id", "")) == activity_id:
			available = true
			break
	if not available:
		resident["busyActivityReconsideration"] = true
		host._schedule_decision(resident_id, false)
		return host._command_failure(
			"ACTIVITY_STATE_CHANGED",
			["这项活动当前不可用，请根据最新活动列表重新决定"],
			{"stale": true},
			true,
		)
	if resident_id == host.actor_presentation_state.observed_action_preview_resident_id:
		var preflight := preflight(
			host,
			resident_id,
			resident,
			decision_id,
			action,
		)
		if preflight.get("ok") != true:
			return LEGACY_PROP_ACTIVITY_RUNTIME.reject_activation(
				host,
				resident_id,
				action,
				preflight,
				conversation_end_reason,
			)
	(resident.get("usedActionIds", {}) as Dictionary)[
		String(action.get("action_id", "")).strip_edges()
	] = true
	host.ACTION_VALIDATION.clear_rejected_action_streak(resident)
	if resident_id == host.actor_presentation_state.observed_action_preview_resident_id:
		return ACTION_PREVIEW_RUNTIME.confirm(host,
			resident_id,
			resident,
			decision_id,
			"replace_current",
			action,
			conversation_end_reason,
			{},
			{},
			{},
			{},
			allow_current_activity_interrupt,
		)
	return activate(
		host,
		resident_id,
		resident,
		decision_id,
		action,
		conversation_end_reason,
		allow_current_activity_interrupt,
	)


static func preflight(
	host,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
) -> Dictionary:
	var step := agent_activity_step(
		action,
		String(resident.get("currentPlace", "")),
	)
	var validated := host._activity_runtime.validate_step(
		resident_id,
		"agent-activity:%s" % decision_id,
		0,
		step,
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		host.get_weather(),
	) as Dictionary
	if validated.get("ok") != true:
		return validated
	return host.ACTIVITY_CANDIDATE_PREFLIGHT_RUNTIME.preflight(host, resident, validated)


static func activate(
	host,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var meal_result := DINING_SERVICE.activate_agent_meal_routine(
		host,
		resident_id,
		resident,
		decision_id,
		action,
		conversation_end_reason,
		allow_current_activity_interrupt,
	) as Dictionary
	if not meal_result.is_empty():
		return meal_result
	var performed: Dictionary = ACTIVITY_STEP_EXECUTION_RUNTIME.perform(host,
		resident_id,
		"agent-activity:%s" % decision_id,
		0,
		agent_activity_step(action, String(resident.get("currentPlace", ""))),
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_AGENT_ACTIVITY,
		String(action.get("action_id", "")).strip_edges(),
		-1,
		allow_current_activity_interrupt,
	)
	if performed.get("ok") != true:
		return LEGACY_PROP_ACTIVITY_RUNTIME.reject_activation(
			host,
			resident_id,
			action,
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
	return {
		"ok": true,
		"stale": false,
		"status": "accepted",
		"action": host.ACTION_PROJECTION_MODULE.public_current_action(
			resident.get("currentAction", {}) as Dictionary
		),
		"actionPhase": ACTION_PRESENTATION._resident_action_phase_projection(host, resident),
		"activity": (performed.get("execution", {}) as Dictionary).duplicate(true),
	}


static func agent_activity_step(action: Dictionary, place_id: String) -> Dictionary:
	return ACTION_SUPPORT.agent_activity_step(action, place_id)
