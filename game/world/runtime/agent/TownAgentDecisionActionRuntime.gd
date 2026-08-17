class_name TownAgentDecisionActionRuntime
extends RefCounted


const ACTION_PREVIEW_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreviewRuntime.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)


const AGENT_DECISION_ACCEPTANCE_POLICY := preload(
	"res://world/runtime/agent/TownAgentDecisionAcceptancePolicy.gd"
)
const RESIDENT_EVENT_QUEUE_RUNTIME := preload(
	"res://world/runtime/event/TownResidentEventQueueRuntime.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)

const CONTINUITY_WAIT_MAX_MINUTES := 5


static func continue_decision(
	host,
	resident_id: String,
	resident: Dictionary,
	decision: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var current_action := resident.get("currentAction", {}) as Dictionary
	if current_action.is_empty():
		host._schedule_decision(resident_id, false)
		return host._complete_agent_submission({"ok": false, "stale": false, "errors": ["没有可以继续的当前动作"]})
	var active_conversation := context.get("pendingConversation", {}) as Dictionary
	if not active_conversation.is_empty() and String(active_conversation.get("waitingFor", "")) == resident_id:
		host._schedule_decision(resident_id, false)
		return host._complete_agent_submission({
			"ok": false,
			"stale": false,
			"errorCode": "CONVERSATION_REPLY_REQUIRED",
			"retryable": true,
			"errors": ["搭话必须提交答话；拒绝也要说明理由并结束对话"],
		})
	host.ANNOUNCEMENT_RESIDENT_RUNTIME.emit_reactions(host,
		resident_id,
		String(context.get("decisionId", "")),
		decision.get("reaction", {}) as Dictionary,
		(
			decision.get("announcement_reactions", []) as Array
			if decision.get("announcement_reactions", []) is Array
			else []
		),
		context.get("inflightEvents", []) as Array,
		context.get("inflightResults", []) as Array,
	)
	return host._complete_agent_submission(
		ACTION_PREVIEW_RUNTIME.confirm(host,
			resident_id,
			resident,
			String(context.get("decisionId", "")),
			"continue_current",
			current_action,
		)
	)


static func submit_conflict_intent(
	host,
	resident: Dictionary,
	action: Dictionary,
	conflict_intent: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var resident_id := String(context.get("residentId", ""))
	var decision_wake := context.get("wakePacket", {}) as Dictionary
	var reply_preparation: Dictionary = host.ACTION_PREPARATION_RUNTIME.prepare(host,
		resident,
		action,
		false,
		decision_wake.get("snapshot", {}) as Dictionary,
	)
	if reply_preparation.get("ok") != true:
		return host._complete_agent_submission(
			ACTION_RESULT_RUNTIME.reject_invalid(host,
				resident_id,
				resident,
				action,
				String((reply_preparation.get("errors", ["对话已经无法继续"]) as Array)[0]),
			)
		)
	var prepared_reply := reply_preparation.get("action", {}) as Dictionary
	(resident.get("usedActionIds", {}) as Dictionary)[String(action.get("action_id", "")).strip_edges()] = true
	(resident.get("usedActionIds", {}) as Dictionary)[String(conflict_intent.get("action_id", "")).strip_edges()] = true
	return host._complete_agent_submission(
		ACTION_PREVIEW_RUNTIME.confirm(host,
			resident_id,
			resident,
			String(context.get("decisionId", "")),
			"replace_current",
			prepared_reply,
			"",
			context.get("storyProvenance", {}) as Dictionary,
			{},
			context.get("acceptedConversationFollowUp", {}) as Dictionary,
			context.get("pendingPostInjuryReaction", {}) as Dictionary,
			bool(context.get("mayInterruptCurrent", false)),
			conflict_intent,
			decision_wake.get("snapshot", {}) as Dictionary,
		)
	)


static func submit_prepared_action(
	host,
	resident: Dictionary,
	decision: Dictionary,
	action: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var resident_id := String(context.get("residentId", ""))
	var action_type := String(context.get("actionType", ""))
	var decision_wake := context.get("wakePacket", {}) as Dictionary
	var pending_post_injury_reaction := context.get(
		"pendingPostInjuryReaction", {}
	) as Dictionary
	var preparation: Dictionary = host.ACTION_PREPARATION_RUNTIME.prepare(host,
		resident,
		action,
		false,
		decision_wake.get("snapshot", {}) as Dictionary,
		not pending_post_injury_reaction.is_empty()
			and action_type == "去"
			and String(action.get("place", "")) == CONTENT_CATALOG.PLACE_CLINIC,
	)
	context["probeLapUsec"] = host.WORLD_PERFORMANCE_PROBE.record_lap(
		int(context.get("probeLapUsec", 0)),
		"submission_prepare_action",
	)
	if preparation.get("ok") != true:
		var preparation_errors := preparation.get("errors", []) as Array
		var preparation_error := String(
			preparation_errors[0] if not preparation_errors.is_empty() else ""
		)
		if not pending_post_injury_reaction.is_empty():
			# A route or target can change between the urgent wake and submission.
			# Keep the injury event authoritative so a transient clinic/range
			# failure cannot release the resident back into ordinary activity.
			resident["inflightEvents"] = context.get("inflightEvents", []) as Array
			resident["inflightResults"] = context.get("inflightResults", []) as Array
			RESIDENT_EVENT_QUEUE_RUNTIME.restore_inflight_facts(resident)
			host._schedule_decision(resident_id, false)
			return host._complete_agent_submission({
				"ok": true,
				"stale": true,
				"ignored": true,
				"reason": preparation_error if not preparation_error.is_empty() else "受击后的首轮动作条件已变化，已重新观察",
			})
		if (
			action_type == "搭话"
			and preparation_error in [
				"搭话对象已经不在感知范围内",
				"搭话对象正在参与其他对话",
			]
		):
			resident["inflightEvents"] = context.get("inflightEvents", []) as Array
			resident["inflightResults"] = context.get("inflightResults", []) as Array
			RESIDENT_EVENT_QUEUE_RUNTIME.restore_inflight_facts(resident)
			host._schedule_decision(resident_id, false)
			return host._complete_agent_submission({
				"ok": true,
				"stale": true,
				"ignored": true,
				"reason": "%s，已重新观察" % preparation_error,
			})
		var rejection: Dictionary = ACTION_RESULT_RUNTIME.reject_invalid(host,
			resident_id,
			resident,
			action,
			String((preparation.get("errors", ["动作不合法"]) as Array)[0]),
		)
		DINING_SERVICE.decorate_go_rejection(rejection, preparation)
		var conversation_end_reason := String(context.get("conversationEndReason", ""))
		if conversation_end_reason == "拒绝接话":
			var active_conversation := context.get("pendingConversation", {}) as Dictionary
			CONVERSATION_RUNTIME._end_conversation(
				host,
				host._traveler_relationship_state,
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				"rejected",
			)
		return host._complete_agent_submission(rejection)
	var prepared_action := AGENT_DECISION_ACCEPTANCE_POLICY.apply_wait_reconsideration(
		preparation.get("action", {}) as Dictionary,
		resident.get("currentAction", {}) as Dictionary,
		bool(context.get("busyActivityReconsideration", false)),
		int(host._environment.get_absolute_minute()),
		CONTINUITY_WAIT_MAX_MINUTES,
	)
	(resident.get("usedActionIds", {}) as Dictionary)[String(action.get("action_id", "")).strip_edges()] = true
	return host._complete_agent_submission(
		ACTION_PREVIEW_RUNTIME.confirm(host,
			resident_id,
			resident,
			String(context.get("decisionId", "")),
			"replace_current",
			prepared_action,
			String(context.get("conversationEndReason", "")),
			context.get("storyProvenance", {}) as Dictionary,
			(
				decision.get("social_request", {}) as Dictionary
				if decision.get("social_request") is Dictionary
				else {}
			),
			context.get("acceptedConversationFollowUp", {}) as Dictionary,
			pending_post_injury_reaction,
			bool(context.get("mayInterruptCurrent", false)),
		)
	)
