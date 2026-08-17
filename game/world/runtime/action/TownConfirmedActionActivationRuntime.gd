class_name TownConfirmedActionActivationRuntime
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const WORLD_PERFORMANCE_PROBE := preload(
	"res://world/runtime/TownWorldPerformanceProbe.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const CONVERSATION_FOLLOW_UP_ACTION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpActionRuntime.gd"
)
const CONVERSATION_CONFLICT_BRIDGE := preload(
	"res://world/runtime/conversation/TownConversationConflictBridge.gd"
)
const CONFIRMED_ACTION_ACTIVATION_POLICY := preload(
	"res://world/runtime/agent/TownConfirmedActionActivationPolicy.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/action/TownActionSettlementRuntime.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)
const ACTION_TIMING := preload(
	"res://world/runtime/action/TownActionTiming.gd"
)
const CONFLICT_AGENT_WORLD_BRIDGE := preload(
	"res://world/runtime/conflict/TownConflictAgentWorldBridge.gd"
)
const LEGACY_PROP_ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownLegacyPropActivityRuntime.gd"
)
const AGENT_ACTIVITY_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/activity/TownAgentActivitySubmissionRuntime.gd"
)


static func activate(
	host,
	resident_id: String,
	resident: Dictionary,
	preview: Dictionary,
	prepared_action_is_fresh := false,
) -> void:
	var probe_lap_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	if preview.is_empty():
		return
	var handling := String(preview.get("handling", ""))
	var conversation_end_reason := String(preview.get("conversationEndReason", ""))
	var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(host, resident_id)
	if handling == "continue_current":
		continue_activation(host,
			resident_id,
			resident,
			conversation_end_reason,
			active_conversation,
		)
		return
	var action := (
		preview.get("action", {}) as Dictionary
	).duplicate(true)
	var decision_can_interrupt_current := bool(
		preview.get("decisionMayInterruptCurrent", false)
	)
	match CONFIRMED_ACTION_ACTIVATION_POLICY.route_kind(action):
		"legacy_prop_activity":
			LEGACY_PROP_ACTIVITY_RUNTIME.activate(
				host,
				resident_id,
				resident,
				String(preview.get("decisionId", "")),
				action,
				conversation_end_reason,
				{},
				decision_can_interrupt_current,
			)
			return
		"agent_activity":
			AGENT_ACTIVITY_SUBMISSION_RUNTIME.activate(
				host,
				resident_id,
				resident,
				String(preview.get("decisionId", "")),
				action,
				conversation_end_reason,
				decision_can_interrupt_current,
			)
			return
		"conflict":
			activate_conflict(host,
				resident_id,
				resident,
				action,
				preview,
				conversation_end_reason,
				active_conversation,
			)
			return
	var refreshed: Dictionary = refresh_action(host,
		resident,
		action,
		preview,
		prepared_action_is_fresh,
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_prepare")
	if refreshed.get("ok") != true:
		reject_preview_activation(host,
			resident_id,
			resident,
			refreshed.get("submittedAction", {}) as Dictionary,
			String(
				(refreshed.get(
					"errors",
					["预览结束时动作条件已经失效"],
				) as Array)[0]
			),
		)
		return
	action = (refreshed.get("action", {}) as Dictionary).duplicate(true)
	# 预览确认时会重新校验玩家可提交字段。同行、代取等 World 内部状态
	# 不属于模型输入字段，必须从已确认动作带回，否则动作虽然开始移动，
	# 却会退化成普通“去”，承诺永远无法推进与结算。
	host.ACTION_PROJECTION_MODULE.copy_conversation_follow_up_state(
		preview.get("action", {}) as Dictionary,
		action,
	)
	if (
		String(action.get("type", "")) == "答话"
		and not active_conversation.is_empty()
		and String(active_conversation.get("waitingFor", "")) == resident_id
	):
		CONVERSATION_RUNTIME._activate_conversation_reply(host, host._traveler_relationship_state,
			resident_id,
			resident,
			action,
			preview,
		)
		return
	replace_regular_action(host,
		resident_id,
		resident,
		action,
		preview,
		conversation_end_reason,
		active_conversation,
		decision_can_interrupt_current,
		probe_lap_usec,
	)



static func continue_activation(
	host,
	resident_id: String,
	resident: Dictionary,
	conversation_end_reason: String,
	active_conversation: Dictionary,
) -> void:
	CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.resume_reconsideration(host, resident)
	host.ACTION_TIMING.resume_suspended_action(host, resident)
	if not conversation_end_reason.is_empty() and not active_conversation.is_empty():
		CONVERSATION_RUNTIME._end_conversation(
			host,
			host._traveler_relationship_state,
			String(active_conversation.get("conversationId", "")),
			conversation_end_reason,
			"rejected",
		)
	host._bump_world_revision()
	var continued_phase: Dictionary = ACTION_PRESENTATION._resident_action_phase_projection(
		host,
		resident,
	)
	host.resident_action_phase_changed.emit(resident_id, continued_phase.duplicate(true))
	host._emit_resident_state_changed(resident_id)



static func refresh_action(
	host,
	resident: Dictionary,
	action: Dictionary,
	preview: Dictionary,
	prepared_action_is_fresh: bool,
) -> Dictionary:
	var submitted_action: Dictionary = CONFIRMED_ACTION_ACTIVATION_POLICY.submitted_action(
		preview,
		action,
	)
	var refreshed := (
		{"ok": true, "action": action}
		if prepared_action_is_fresh
		else (
			host.PROP_ACTION_PREPARER.prepare_for_host(host, resident, submitted_action)
			if not String(action.get("dynamicPropId", "")).is_empty()
			else host.ACTION_PREPARATION_RUNTIME.prepare(host, resident, submitted_action, true)
		)
	) as Dictionary
	refreshed["submittedAction"] = submitted_action
	return refreshed



static func replace_regular_action(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	preview: Dictionary,
	conversation_end_reason: String,
	active_conversation: Dictionary,
	decision_can_interrupt_current: bool,
	probe_lap_usec: int,
) -> void:
	var old_action := resident.get("currentAction", {}) as Dictionary
	if not old_action.is_empty():
		var activity_execution := host._activity_runtime.execution_for_action(
			resident_id,
			String(old_action.get("action_id", "")),
		) as Dictionary
		if not activity_execution.is_empty():
			host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
				resident_id,
				"居民确认新的合法动作后替换当前活动",
				decision_can_interrupt_current,
			)
		else:
			var replacement_status := (
				"completed" if decision_can_interrupt_current else "replaced"
			)
			var replacement_reason := (
				ACTION_SETTLEMENT_RUNTIME.priority_settlement_reason(
					host,
					old_action,
					"居民确认新的高优先级动作",
				)
				if decision_can_interrupt_current
				else "居民确认新的合法动作后开始执行"
			)
			host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_matching_action_result(host,
				resident_id,
				old_action,
				replacement_status,
				replacement_reason,
			)
			host._append_action_result_without_schedule(
				resident_id,
				String(old_action.get("action_id", "")),
				replacement_status,
				replacement_reason,
			)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_replace_old")
	ACTION_TIMING.rebase_action_timing(host, action)
	CONFIRMED_ACTION_ACTIVATION_POLICY.activate_resident(
		resident,
		action,
		host.ACTION_PROJECTION_MODULE.default_doing(host, action),
	)
	host.telemetry.count_agent_request_metric("behaviorStarted", 1)
	host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.start_matching_action(host, resident_id, action)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_social")
	WORLD_LOG_COMMIT_RUNTIME.record_story_action_started(host,
		resident_id,
		action,
		preview.get("storyProvenance", {}) as Dictionary,
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_story")
	host._bump_world_revision()
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_revision")
	var resident_display_name: String = host.resident_display_name(resident_id)
	host._emit_resident_state_changed(resident_id)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_resident_emit")
	var presented_action: Dictionary = ACTION_PRESENTATION.public_action(host, action)
	presented_action["residentId"] = resident_id
	host.resident_action_started.emit(resident_display_name, presented_action)
	host.resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(host, resident),
	)
	WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_action_signals")
	settle_follow_up(host,
		resident_id,
		resident,
		action,
		preview,
		conversation_end_reason,
		active_conversation,
	)



static func settle_follow_up(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	preview: Dictionary,
	conversation_end_reason: String,
	active_conversation: Dictionary,
) -> void:
	var action_type := String(action.get("type", ""))
	if action_type == "搭话":
		if String(action.get("approachMode", "")).is_empty():
			CONVERSATION_RUNTIME._start_conversation(host, host._traveler_relationship_state, resident_id, action)
			host.SOCIAL_SOURCE_SUBMISSION_RUNTIME.submit_optional_request(host,
				resident_id,
				action,
				preview.get("socialRequest", {}) as Dictionary,
			)
	elif action_type == "答话":
		host.CONVERSATION_COMMITMENT_SUBMISSION_RUNTIME.submit(host,
			resident_id,
			action,
			preview.get("conversationFollowUp", {}) as Dictionary,
			active_conversation,
		)
		CONVERSATION_RUNTIME._apply_conversation_reply(host, host._traveler_relationship_state, resident_id, action)
		var conflict_intent := preview.get("conflictIntent", {}) as Dictionary
		if not conflict_intent.is_empty():
			var conflict_result := CONVERSATION_CONFLICT_BRIDGE.activate_after_reply(
				host,
				resident_id,
				resident,
				conflict_intent,
				preview.get("decisionWakeSnapshot", {}) as Dictionary,
				preview.get("storyProvenance", {}) as Dictionary,
			) as Dictionary
			if conflict_result.get("ok") != true:
				resident["doing"] = "这场火气已经散了，先缓一缓"
				ACTION_RESULT_RUNTIME.queue(
					host,
					resident_id,
					String(conflict_intent.get("action_id", "")),
					"rejected",
					"对方已经走远，冲突没有继续",
					true,
					true,
				)
	elif not conversation_end_reason.is_empty() and not active_conversation.is_empty():
		CONVERSATION_RUNTIME._end_conversation(host, host._traveler_relationship_state,
			String(active_conversation.get("conversationId", "")),
			conversation_end_reason,
			"rejected" if conversation_end_reason == "拒绝接话" else "interrupted",
		)
	_settle_post_injury_conflict(
		host,
		resident_id,
		String(action.get("type", "")),
		preview.get("postInjuryReaction", {}) as Dictionary,
	)


static func _settle_post_injury_conflict(
	host,
	resident_id: String,
	action_type: String,
	reaction: Dictionary,
) -> void:
	if host._conflict_controller == null or reaction.is_empty():
		return
	var conflict_id := String(reaction.get("conflict_id", "")).strip_edges()
	if conflict_id.is_empty():
		return
	var response_kind := "deescalate" if action_type == "搭话" else "flee"
	host._conflict_controller.respond(conflict_id, resident_id, response_kind)


static func activate_conflict(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	preview: Dictionary,
	conversation_end_reason: String,
	active_conversation: Dictionary,
) -> void:
	var old_action := resident.get("currentAction", {}) as Dictionary
	if not old_action.is_empty():
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
			resident_id,
			"居民决定立即处理眼前的冲突",
			true,
		)
	if (
		not conversation_end_reason.is_empty()
		and not active_conversation.is_empty()
	):
		CONVERSATION_RUNTIME._end_conversation(host, host._traveler_relationship_state,
			String(active_conversation.get("conversationId", "")),
			conversation_end_reason,
			"interrupted",
		)
	var result: Dictionary = (
		host._conflict_agent_world_bridge.execute_action(resident_id,
			action,) as Dictionary
		if host._conflict_agent_world_bridge != null
		else {"ok": false, "errorCode": "CONFLICT_BRIDGE_NOT_CONFIGURED"}
	)
	var action_type := String(action.get("type", ""))
	var public_line := String(action.get("line", "")).strip_edges()
	resident["doing"] = (
		public_line if not public_line.is_empty() else host.ACTION_PROJECTION_MODULE.default_doing(host, action)
	)
	WORLD_LOG_COMMIT_RUNTIME.record_story_action_started(host,
		resident_id,
		action,
		preview.get("storyProvenance", {}) as Dictionary,
	)
	ACTION_RESULT_RUNTIME.queue(
		host,
		resident_id,
		String(action.get("action_id", "")),
		"completed" if result.get("ok") == true else "rejected",
		(
			CONFLICT_AGENT_WORLD_BRIDGE.action_result_text(action_type)
			if result.get("ok") == true
			else CONFLICT_AGENT_WORLD_BRIDGE.action_error_text(String(
				result.get("errorCode", "CONFLICT_ACTION_REJECTED")
			))
		),
		true,
		true,
	)
	host._emit_resident_state_changed(resident_id)



static func reject_preview_activation(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	reason: String,
) -> void:
	host._append_action_result_without_schedule(
		resident_id,
		String(action.get("action_id", "")),
		"rejected",
		reason,
		ACTION_PRESENTATION._preview_action_presentation(host, resident, {"action": action}),
	)
	host._schedule_decision(resident_id, false)
	host._bump_world_revision()
	host.resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(host, resident),
	)
	host._emit_resident_state_changed(resident_id)
