class_name TownLegacyPropActivityRuntime
extends RefCounted

const ACTIVITY_ROUTINE_ACTIVATION_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityRoutineActivationRuntime.gd"
)
const ACTIVITY_STEP_EXECUTION_RUNTIME := preload("res://world/runtime/activity/TownActivityStepExecutionRuntime.gd")


const ACTION_PREVIEW_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreviewRuntime.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)


const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const ACTIVITY_ROUTINE_POLICY := preload(
	"res://world/runtime/activity/TownActivityRoutinePolicy.gd"
)
const ACTION_PROJECTION_MODULE := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
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
	var shape_error := ACTION_VALIDATION.validate_action_shape(action)
	if shape_error.is_empty() and (
		resident.get("usedActionIds", {}) as Dictionary
	).has(String(action.get("action_id", "")).strip_edges()):
		shape_error = "动作 action_id 已被该居民使用：%s" % String(
			action.get("action_id", "")
		).strip_edges()
	if not shape_error.is_empty():
		return ACTION_RESULT_RUNTIME.reject_invalid(host,
			resident_id,
			resident,
			action,
			shape_error,
		)
	if host._dynamic_prop_runtime.is_dynamic_action(resident, action):
		return submit_direct(host,
			resident_id,
			resident,
			decision_id,
			action,
			conversation_end_reason,
			allow_current_activity_interrupt,
		)
	var mapping := host._activity_runtime.legacy_activity_mapping(
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		String(action.get("prop", "")),
		String(action.get("verb", "")),
	) as Dictionary
	if mapping.get("ok") != true:
		if host.PROP_ACTION_PREPARER.is_layout_override_action(host, resident, action):
			return submit_direct(host,
				resident_id,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				allow_current_activity_interrupt,
			)
		var rejection: Dictionary = ACTION_RESULT_RUNTIME.reject_invalid(host,
			resident_id,
			resident,
			action,
			String(
				(mapping.get(
					"errors",
					["旧用道具动作不能唯一映射到可执行活动"],
				) as Array)[0]
			),
		)
		rejection["errorCode"] = String(
			mapping.get("errorCode", "ACTIVITY_NO_EXECUTABLE_SLOT")
		)
		rejection["retryable"] = bool(mapping.get("retryable", false))
		if conversation_end_reason == "拒绝接话":
			var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(host,
				resident_id
			)
			if not active_conversation.is_empty():
				CONVERSATION_RUNTIME._end_conversation(host, host._traveler_relationship_state,
					String(active_conversation.get("conversationId", "")),
					conversation_end_reason,
					"rejected",
				)
		return rejection
	if resident_id == host.actor_presentation_state.observed_action_preview_resident_id:
		var observed_preflight: Dictionary = preflight_observed(host,
			resident_id,
			resident,
			decision_id,
			action,
			mapping,
		)
		if observed_preflight.get("ok") != true:
			return reject_activation(host,
				resident_id,
				action,
				observed_preflight,
				conversation_end_reason,
			)
	(resident.get("usedActionIds", {}) as Dictionary)[
		String(action.get("action_id", "")).strip_edges()
	] = true
	ACTION_VALIDATION.clear_rejected_action_streak(resident)
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
	return activate(host,
		resident_id,
		resident,
		decision_id,
		action,
		conversation_end_reason,
		mapping,
		allow_current_activity_interrupt,
	)



static func preflight_observed(
	host,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	mapping: Dictionary,
) -> Dictionary:
	var target := {
		"activityId": String(mapping.get("activityId", "")),
		"placeId": String(mapping.get("placeId", "")),
	}
	var preferred_slot_id := String(
		mapping.get("preferredSlotId", "")
	).strip_edges()
	if not preferred_slot_id.is_empty():
		target["preferredSlotId"] = preferred_slot_id
	var step := {
		"stepId": String(action.get("action_id", "")).strip_edges(),
		"operation": "activity.perform",
		"target": target,
		"params": {
			"reason": String(action.get("line", "")),
		},
	}
	var validated := host._activity_runtime.validate_step(
		resident_id,
		"legacy-prop-use:%s" % decision_id,
		0,
		step,
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		host.get_weather(),
	) as Dictionary
	if validated.get("ok") != true:
		return validated
	return host.ACTIVITY_CANDIDATE_PREFLIGHT_RUNTIME.preflight(host, resident, validated)



static func submit_direct(
	host,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	if String(action.get("line", "")).strip_edges().is_empty():
		return ACTION_RESULT_RUNTIME.reject_invalid(host,
			resident_id,
			resident,
			action,
			"用道具动作必须包含非空 line",
		)
	if not host.ACTION_SUPPORT.direct_prop_action_available(host, resident_id, resident, action):
		resident["busyActivityReconsideration"] = true
		resident["doing"] = "这个位置正有人用，正在另找能做的事"
		return ACTION_RESULT_RUNTIME.reject_invalid(host,
			resident_id,
			resident,
			action,
			"这个道具位置当前正被其他居民使用",
		)
	var preparation: Dictionary = host.PROP_ACTION_PREPARER.prepare_for_host(host, resident, action)
	if preparation.get("ok") != true:
		return ACTION_RESULT_RUNTIME.reject_invalid(host,
			resident_id,
			resident,
			action,
			String(
				(preparation.get(
					"errors",
					["当前世界道具不可交互"],
				) as Array)[0]
			),
		)
	(resident.get("usedActionIds", {}) as Dictionary)[
		String(action.get("action_id", "")).strip_edges()
	] = true
	return ACTION_PREVIEW_RUNTIME.confirm(host,
		resident_id,
		resident,
		decision_id,
		"replace_current",
		preparation.get("action", {}) as Dictionary,
		conversation_end_reason,
		{},
		{},
		{},
		{},
		allow_current_activity_interrupt,
	)



static func activate(
	host,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	prevalidated_mapping: Dictionary = {},
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var mapping := prevalidated_mapping.duplicate(true)
	if mapping.is_empty():
		mapping = host._activity_runtime.legacy_activity_mapping(
			resident.get("socialState", {}) as Dictionary,
			String(resident.get("currentPlace", "")),
			String(action.get("prop", "")),
			String(action.get("verb", "")),
		) as Dictionary
	if mapping.get("ok") != true:
		return reject_activation(host,
			resident_id,
			action,
			mapping,
			conversation_end_reason,
		)
	var routine_descriptor := host._activity_runtime.routine_descriptor(
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		String(mapping.get("activityId", "")),
	) as Dictionary
	if not routine_descriptor.is_empty():
		var routine_candidates := host._activity_runtime.routine_candidates(
			resident.get("socialState", {}) as Dictionary,
			String(resident.get("currentPlace", "")),
			String(routine_descriptor.get("group", "")),
		) as Array[Dictionary]
		var routine_activation := ACTIVITY_ROUTINE_POLICY.legacy_activation(
			mapping,
			routine_descriptor,
			routine_candidates,
		)
		if not routine_activation.is_empty():
			return ACTIVITY_ROUTINE_ACTIVATION_RUNTIME.activate(
				host,
				resident_id,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				routine_activation.get("mapping", {}) as Dictionary,
				routine_activation.get("descriptor", {}) as Dictionary,
				allow_current_activity_interrupt,
			)
	var target := {
		"activityId": String(mapping.get("activityId", "")),
		"placeId": String(mapping.get("placeId", "")),
	}
	var preferred_slot_id := String(
		mapping.get("preferredSlotId", "")
	).strip_edges()
	if not preferred_slot_id.is_empty():
		target["preferredSlotId"] = preferred_slot_id
	var step := {
		"stepId": String(action.get("action_id", "")).strip_edges(),
		"operation": "activity.perform",
		"target": target,
		"params": {
			"reason": String(action.get("line", "")),
		},
	}
	var performed: Dictionary = ACTIVITY_STEP_EXECUTION_RUNTIME.perform(host,
		resident_id,
		"legacy-prop-use:%s" % decision_id,
		0,
		step,
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_LEGACY_PROP,
		String(action.get("action_id", "")).strip_edges(),
		-1,
		allow_current_activity_interrupt,
	)
	if performed.get("ok") != true:
		return reject_activation(host,
			resident_id,
			action,
			performed,
			conversation_end_reason,
		)
	if not conversation_end_reason.is_empty():
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(host, resident_id)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(host, host._traveler_relationship_state,
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				(
					"rejected"
					if conversation_end_reason == "拒绝接话"
					else "interrupted"
				),
			)
	return {
		"ok": true,
		"stale": false,
		"status": "accepted",
		"action": host.ACTION_PROJECTION_MODULE.public_current_action(
			resident.get("currentAction", {}) as Dictionary
		),
		"actionPhase": ACTION_PRESENTATION._resident_action_phase_projection(host, resident),
		"activity": (
			performed.get("execution", {}) as Dictionary
		).duplicate(true),
	}



static func reject_activation(
	host,
	resident_id: String,
	action: Dictionary,
	failure_source: Dictionary,
	conversation_end_reason: String,
) -> Dictionary:
	var errors := failure_source.get(
		"errors",
		["旧用道具动作的 activity.perform 激活失败"],
	) as Array
	var reason := (
		String(errors[0])
		if not errors.is_empty()
		else "旧用道具动作的 activity.perform 激活失败"
	)
	var resident := host.resident_registry.records[resident_id] as Dictionary
	if (
		String(failure_source.get("errorCode", ""))
		== "ACTIVITY_RESERVATION_CONFLICT"
		and (resident.get("currentAction", {}) as Dictionary).is_empty()
	):
		resident["busyActivityReconsideration"] = true
		resident["doing"] = "这个位置正有人用，正在另找能做的事"
		host._emit_resident_state_changed(resident_id)
	ACTION_RESULT_RUNTIME.queue(
		host,
		resident_id,
		String(action.get("action_id", "")).strip_edges(),
		"rejected",
		reason,
		true,
		true,
		ACTION_PRESENTATION._preview_action_presentation(host, resident, {"action": action}),
	)
	if conversation_end_reason == "拒绝接话":
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(host, resident_id)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(host, host._traveler_relationship_state,
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				"rejected",
			)
	return {
		"ok": false,
		"stale": false,
		"errorCode": String(
			failure_source.get("errorCode", "ACTIVITY_STATE_CHANGED")
		),
		"retryable": bool(failure_source.get("retryable", false)),
		"errors": [reason],
	}
