class_name TownAgentDecisionSchedulingRuntime
extends RefCounted


const ACTION_PREVIEW_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreviewRuntime.gd"
)


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const RESIDENT_EVENT_QUEUE_RUNTIME := preload(
	"res://world/runtime/event/TownResidentEventQueueRuntime.gd"
)
const AGENT_WAKE_STATE_RUNTIME := preload(
	"res://world/runtime/TownAgentWakeStateRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const CUSTOMER_SERVICE_WAIT_RUNTIME := preload(
	"res://world/runtime/work/TownCustomerServiceWaitRuntime.gd"
)


static func schedule(
	host,
	resident_name: String,
	invalidate: bool,
	prefetch := false,
	allow_current_activity_interrupt := false,
	force_fresh := false,
	wake_while_current_action := false,
) -> void:
	var resident := host.resident_registry.records[resident_name] as Dictionary
	if not host.resident_is_present(resident):
		return
	if (
		not force_fresh
		and host.CLINIC_SERVICE_COORDINATION_RUNTIME.resident_is_completing_bound_work(host, resident_name, resident)
	):
		# 普通观察先留在队列里，不能每分钟重新决策并重启正在进行的诊疗。
		return
	if (
		not force_fresh
		and CUSTOMER_SERVICE_WAIT_RUNTIME.resident_is_waiting_for_active_onsite_service(
			host, resident_name,
		)
		and CONVERSATION_RUNTIME._active_conversation_for_person(host, resident_name).is_empty()
	):
		if bool(resident.get("decisionPending", false)):
			host._agent_wake_preparation_runtime.clear_resident(String(resident.get("residentId", resident_name)), String(resident.get("validDecisionId", "")))
			RESIDENT_EVENT_QUEUE_RUNTIME.restore_inflight_facts(resident)
			resident["decisionPending"] = false
			resident["validDecisionId"] = ""
			resident["pendingWake"] = {}
			resident["wakeDispatchQueued"] = false
		return
	var preview := resident.get("confirmedActionPreview", {}) as Dictionary
	if not preview.is_empty():
		if not allow_current_activity_interrupt:
			return
		cancel_confirmed_action_preview_for_new_decision(
			host,
			resident_name,
			resident,
			preview,
		)
		if host.CLINIC_SERVICE_COORDINATION_RUNTIME.resident_is_completing_bound_work(host,
			resident_name,
			resident,
		):
			return
	var current_action := resident.get("currentAction", {}) as Dictionary
	if DINING_SERVICE.keep_meal_routine_running(host, resident_name, current_action): return
	if (
		not current_action.is_empty()
		and not prefetch
		and not allow_current_activity_interrupt
		and not force_fresh
		and not wake_while_current_action
	):
		# 普通生活节奏和普通事件只留在队列里，当前活动完成后再统一唤醒。
		return
	var prefetched_decision := resident.get("prefetchedDecision", {}) as Dictionary
	if (
		bool(resident.get("decisionPending", false))
		and current_action.is_empty()
		and not prefetched_decision.is_empty()
	):
		apply_prefetched_decision(host, resident_name)
		return
	if (
		invalidate
		and bool(resident.get("decisionPending", false))
		and current_action.is_empty()
		and bool(resident.get("decisionPrefetch", false))
	):
		# Keep the travelling response; a later urgent invalidation may discard it.
		return
	if invalidate and bool(resident.get("decisionPending", false)):
		host.telemetry.count_agent_request_metric("decisionInvalidated", 1)
		host._agent_wake_preparation_runtime.clear_resident(String(resident.get("residentId", resident_name)), String(resident.get("validDecisionId", "")))
		RESIDENT_EVENT_QUEUE_RUNTIME.restore_inflight_facts(resident)
		resident["decisionPending"] = false
		resident["validDecisionId"] = ""
		resident["pendingWake"] = {}
		resident["wakeDispatchQueued"] = false
		resident["decisionPrefetch"] = false
		resident["decisionMayInterruptCurrent"] = false
		resident["prefetchedDecision"] = {}
	if bool(resident.get("decisionPending", false)):
		return
	host.telemetry.count_agent_request_metric("decisionCreated", 1)
	if (resident.get("currentAction", {}) as Dictionary).is_empty():
		host.telemetry.count_agent_request_metric("decisionPendingWithoutAction", 1)
	if (
		int(resident.get("actionSuspendedAbsoluteMinute", -1)) >= 0
		and CONVERSATION_RUNTIME._active_conversation_for_person(host, resident_name).is_empty()
	):
		host.ACTION_TIMING.resume_suspended_action(host, resident)
	RESIDENT_EVENT_QUEUE_RUNTIME.begin_decision(
		resident,
		resident_name,
		host._runtime_generation,
		prefetch,
		allow_current_activity_interrupt,
	)
	AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	resident["wakeDispatchQueued"] = true
	# A background reconsideration must not republish the unchanged visible
	# action phase. The presentation subscriber responds by pulling and applying
	# the resident's full state, so proximity events could synchronously repeat
	# that work for every moving resident in one world-minute frame. Residents
	# without a current action still publish the transition into thinking.
	if current_action.is_empty():
		host.resident_action_phase_changed.emit(
			resident_name,
			ACTION_PRESENTATION._resident_action_phase_projection(host, resident),
		)



static func apply_prefetched_decision(host, resident_id: String) -> void:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var decision := resident.get("prefetchedDecision", {}) as Dictionary
	if resident.is_empty() or decision.is_empty():
		return
	resident["prefetchedDecision"] = {}
	resident["decisionPrefetch"] = false
	# Preserve the decision envelope until the normal submission path consumes it.
	host.submit_agent_decision_by_id(resident_id, decision)



static func cancel_confirmed_action_preview_for_new_decision(
	host,
	resident_id: String,
	resident: Dictionary,
	preview: Dictionary,
) -> void:
	resident["confirmedActionPreview"] = {}
	ACTION_PREVIEW_RUNTIME.activate(host, resident_id, resident, preview)



static func invalidate_all_pending_decisions(host) -> void:
	for resident_name in host.resident_registry.order:
		var resident := host.resident_registry.records[resident_name] as Dictionary
		if not bool(resident.get("decisionPending", false)):
			continue
		host.telemetry.count_agent_request_metric("decisionInvalidated", 1)
		host._agent_wake_preparation_runtime.clear_resident(String(resident.get("residentId", resident_name)), String(resident.get("validDecisionId", "")))
		RESIDENT_EVENT_QUEUE_RUNTIME.restore_inflight_facts(resident)
		resident["decisionPending"] = false
		resident["validDecisionId"] = ""
		resident["pendingWake"] = {}
		resident["wakeDispatchQueued"] = false
		resident["decisionPrefetch"] = false
		resident["decisionMayInterruptCurrent"] = false
		resident["prefetchedDecision"] = {}


static func schedule_life_rhythm(
	host,
	absolute_minute: int,
	anchors: Array,
) -> void:
	var minute_of_day := posmod(absolute_minute, 1440)
	for resident_index in host.resident_registry.order.size():
		var stagger_minutes: int = (
			(resident_index % 8) * 2
			+ floori(resident_index / 8.0)
		)
		for anchor_value: Variant in anchors:
			var anchor := anchor_value as Dictionary
			if minute_of_day == int(anchor.get("minute", -1)) + stagger_minutes:
				host._schedule_decision(
				host.resident_registry.order[resident_index],
				false,
			)
				break
