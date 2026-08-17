class_name TownAgentDecisionSubmissionRuntime
extends RefCounted

const LEGACY_PROP_ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownLegacyPropActivityRuntime.gd"
)
const AGENT_ACTIVITY_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/activity/TownAgentActivitySubmissionRuntime.gd"
)


const WORLD_PERFORMANCE_PROBE := preload(
	"res://world/runtime/TownWorldPerformanceProbe.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)
const AGENT_DECISION_ENVELOPE_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionEnvelopeRuntime.gd"
)
const AGENT_DECISION_ACCEPTANCE_POLICY := preload(
	"res://world/runtime/agent/TownAgentDecisionAcceptancePolicy.gd"
)
const AGENT_DECISION_ACTION_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionActionRuntime.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const ANNOUNCEMENT_RESIDENT_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementResidentRuntime.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)


static func submit(host, resident_name: String, decision: Dictionary) -> Dictionary:
	var submitted_resident_ref := resident_name
	var resident_id: String = host._resident_key(resident_name)
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var decision_id := String(decision.get("decision_id", "")) if decision.get("decision_id") is String else ""
	var probe_lap_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	var entry_error := AGENT_DECISION_ENVELOPE_RUNTIME.submission_entry_error(
		host._running,
		submitted_resident_ref,
		resident_id,
		host._running and not resident_id.is_empty() and host._resident_is_alive(resident_id),
		host.is_paused(),
		resident,
		decision_id,
	)
	if not entry_error.is_empty():
		return entry_error
	var submission_context := AGENT_DECISION_ENVELOPE_RUNTIME.submission_context(
		resident,
		host.world_log_domain.journal.decision_story_provenance(
			resident.get("inflightEvents", []) as Array,
			resident.get("inflightResults", []) as Array,
		),
	)
	var inflight_events := submission_context.get("inflightEvents", []) as Array
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "submission_capture_wake")
	var pending_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		resident_id,
	)
	var invitation_requires_reply := CONVERSATION_RUNTIME._is_initial_invitation_for(
		host,
		resident_id,
		pending_conversation,
	)
	if invitation_requires_reply:
		var invitation_error := AGENT_DECISION_ACCEPTANCE_POLICY.invitation_reply_error(decision)
		if not invitation_error.is_empty():
			return invitation_error
	var pending_post_injury_reaction: Dictionary = host.WORLD_EVENT_DELIVERY_PROJECTION.post_injury_reaction_for_host(host,
		resident_id,
		inflight_events,
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "submission_prechecks")
	var announcement_priority_error := ANNOUNCEMENT_RESIDENT_RUNTIME.player_priority_handling_error(decision, inflight_events)
	if not announcement_priority_error.is_empty():
		return announcement_priority_error
	if not invitation_requires_reply and not pending_post_injury_reaction.is_empty():
		var post_injury_error := AGENT_DECISION_ACCEPTANCE_POLICY.post_injury_action_error(
			resident,
			decision,
			pending_post_injury_reaction,
			host.CONTENT_CATALOG.PLACE_CLINIC,
		)
		if not post_injury_error.is_empty():
			return {
				"ok": false,
				"stale": false,
				"consumed": false,
				"errorCode": "POST_INJURY_REACTION_REQUIRED",
				"retryable": true,
				"errors": [post_injury_error],
			}
	submission_context["residentId"] = resident_id
	submission_context["decisionId"] = decision_id
	submission_context["pendingConversation"] = pending_conversation
	submission_context["invitationRequiresReply"] = invitation_requires_reply
	submission_context["pendingPostInjuryReaction"] = pending_post_injury_reaction
	submission_context["probeLapUsec"] = probe_lap_usec
	return consume(host, resident, decision, submission_context)


static func consume(
	host,
	resident: Dictionary,
	decision: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var resident_id := String(context.get("residentId", ""))
	var inflight_events := context.get("inflightEvents", []) as Array
	var inflight_results := context.get("inflightResults", []) as Array
	var decision_wake := context.get("wakePacket", {}) as Dictionary
	ACTION_SUPPORT.consume_valid_request(resident)
	host._bump_world_revision(false)
	var decision_shape_error := ACTION_VALIDATION.validate_decision_shape(
		decision,
		inflight_events,
		inflight_results,
	)
	if not decision_shape_error.is_empty():
		var malformed_action: Variant = decision.get("action")
		if malformed_action is Dictionary:
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(host,
					resident_id,
					resident,
					malformed_action as Dictionary,
					decision_shape_error,
				)
			)
		host._schedule_decision(resident_id, false)
		return host._complete_agent_submission({"ok": false, "stale": false, "errors": [decision_shape_error]})
	var accepted_conversation_follow_up := AGENT_DECISION_ACCEPTANCE_POLICY.accepted_conversation_follow_up(
		decision,
		decision_wake,
		host._action_options,
	)
	host.SOCIAL_RESPONSE_ROUND_RUNTIME.settle_optional_attention(host,
		resident_id,
		(
			decision.get("social_attention", {}) as Dictionary
			if decision.get("social_attention") is Dictionary
			else {}
		),
		((decision_wake.get("snapshot", {}) as Dictionary).get("social_exposures", []) as Array),
	)
	if decision.has("social_response"):
		host.SOCIAL_RESPONSE_ROUND_RUNTIME.submit_optional_response(host,
			resident_id,
			decision.get("social_response"),
		)
	context["probeLapUsec"] = WORLD_PERFORMANCE_PROBE.record_lap(
		int(context.get("probeLapUsec", 0)),
		"submission_validate_and_social",
	)
	context["acceptedConversationFollowUp"] = accepted_conversation_follow_up
	return submit_valid(host, resident, decision, context)


static func submit_valid(
	host,
	resident: Dictionary,
	decision: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var resident_id := String(context.get("residentId", ""))
	var decision_id := String(context.get("decisionId", ""))
	var inflight_events := context.get("inflightEvents", []) as Array
	var inflight_results := context.get("inflightResults", []) as Array
	var decision_wake := context.get("wakePacket", {}) as Dictionary
	var active_conversation := context.get("pendingConversation", {}) as Dictionary
	var is_initial_invitation := bool(context.get("invitationRequiresReply", false))
	var handling := decision.get("handling") as String
	if handling == "continue_current":
		return AGENT_DECISION_ACTION_RUNTIME.continue_decision(
			host, resident_id, resident, decision, context
		)
	if handling != "replace_current" or typeof(decision.get("action")) != TYPE_DICTIONARY:
		host._schedule_decision(resident_id, false)
		return host._complete_agent_submission({"ok": false, "stale": false, "errors": ["决定必须继续当前动作或提交新动作"]})
	var action := (decision.get("action", {}) as Dictionary).duplicate(true)
	var current_action := resident.get("currentAction", {}) as Dictionary
	if bool(context.get("wasPrefetched", false)) and not current_action.is_empty():
		return host._complete_agent_submission(
			AGENT_DECISION_ENVELOPE_RUNTIME.store_prefetched_decision(
				resident,
				resident_id,
				decision_id,
				decision,
				decision_wake,
				inflight_events,
				inflight_results,
			)
		)
	var action_type := String(action.get("type", ""))
	var conflict_intent := (
		decision.get("conflict_intent", {}) as Dictionary
		if decision.get("conflict_intent") is Dictionary
		else {}
	)
	var busy_activity_reconsideration := bool(resident.get("busyActivityReconsideration", false))
	var reply_error := AGENT_DECISION_ACCEPTANCE_POLICY.waiting_conversation_reply_error(
		active_conversation,
		resident_id,
		action_type,
		is_initial_invitation,
	)
	if not reply_error.is_empty():
		return host._complete_agent_submission(
			ACTION_RESULT_RUNTIME.reject_invalid(host, resident_id, resident, action, reply_error)
		)
	if busy_activity_reconsideration:
		resident["busyActivityReconsideration"] = false
	host.ANNOUNCEMENT_RESIDENT_RUNTIME.emit_reactions(host,
		resident_id,
		decision_id,
		decision.get("reaction", {}) as Dictionary,
		(
			decision.get("announcement_reactions", []) as Array
			if decision.get("announcement_reactions", []) is Array
			else []
		),
		inflight_events,
		inflight_results,
	)
	if not conflict_intent.is_empty():
		return AGENT_DECISION_ACTION_RUNTIME.submit_conflict_intent(
			host, resident, action, conflict_intent, context
		)
	var conversation_end_reason := AGENT_DECISION_ACCEPTANCE_POLICY.conversation_end_reason(
		active_conversation,
		action_type,
		is_initial_invitation,
	)
	if action_type == "用道具":
		return host._complete_agent_submission(
			LEGACY_PROP_ACTIVITY_RUNTIME.submit(
				host,
				resident_id,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				bool(context.get("mayInterruptCurrent", false)),
			)
		)
	if action_type == "做活动":
		return host._complete_agent_submission(
			AGENT_ACTIVITY_SUBMISSION_RUNTIME.submit(
				host,
				resident_id,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				bool(context.get("mayInterruptCurrent", false)),
			)
		)
	context["actionType"] = action_type
	context["busyActivityReconsideration"] = busy_activity_reconsideration
	context["conversationEndReason"] = conversation_end_reason
	return AGENT_DECISION_ACTION_RUNTIME.submit_prepared_action(
		host, resident, decision, action, context
	)
