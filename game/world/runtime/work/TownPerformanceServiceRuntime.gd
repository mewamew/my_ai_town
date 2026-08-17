class_name TownPerformanceServiceRuntime
extends RefCounted


const RESIDENT_EVENT_QUEUE_RUNTIME := preload(
	"res://world/runtime/event/TownResidentEventQueueRuntime.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const SOCIAL_MATTER_COMMAND_RUNTIME := preload(
	"res://world/runtime/social/TownSocialMatterCommandRuntime.gd"
)


static func retire_stale_requests(host, absolute_minute: int) -> void:
	var current_day := absolute_minute / 1440
	for request_value: Variant in (
		host._work.services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) != "performance"
			or String(request.get("state", "")) not in ["pending", "waiting"]
		):
			continue
		var context := request.get("context", {}) as Dictionary
		var request_day := int(context.get(
			"dayIndex",
			int(request.get("createdAtMinute", 0)) / 1440,
		))
		if request_day >= current_day:
			continue
		host._work.services.cancel_request(
			String(request.get("requestId", "")),
			"演出日期已经过去",
		)
		var task_id := String(request.get("taskId", ""))
		if not task_id.is_empty():
			host._work.tasks.cancel_task(task_id, "演出日期已经过去")
		host.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_for_source(host,
			"performance-event:%d" % request_day,
			"演出日期已经过去",
		)
		close_invitation_sources(host, request_day, "演出日期已经过去")


static func begin_listener_wait(
	host,
	resident_id: String,
	day_index: int,
) -> void:
	if day_index < 0:
		return
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	if (
		resident.is_empty()
		or String(resident.get("currentPlace", "")) != CONTENT_CATALOG.PLACE_PLAZA
		or not (resident.get("currentAction", {}) as Dictionary).is_empty()
	):
		return
	if bool(resident.get("decisionPending", false)):
		RESIDENT_EVENT_QUEUE_RUNTIME.restore_inflight_facts(resident)
		resident["decisionPending"] = false
		resident["validDecisionId"] = ""
		resident["pendingWake"] = {}
		resident["wakeDispatchQueued"] = false
	var now := int(host._environment.get_absolute_minute())
	var action_id := "performance-listen:%d:%s" % [day_index, resident_id]
	resident["currentAction"] = {
		"type": "待着",
		"action_id": action_id,
		"line": "在中心广场等待并聆听演奏",
		"startedAbsoluteMinute": now,
		"completeAbsoluteMinute": now + 120,
		"performanceDayIndex": day_index,
		"performanceEventId": "performance-event:%d" % day_index,
	}
	(resident.get("usedActionIds", {}) as Dictionary)[action_id] = true
	resident["doing"] = "正在中心广场等待并聆听演奏"
	host._bump_world_revision(false)
	host._emit_resident_state_changed(resident_id)


static func finish_listener_waits(
	host,
	day_index: int,
	audience_ids: Array[String],
) -> void:
	for resident_id: String in audience_ids:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			String(action.get("type", "")) == "待着"
			and int(action.get("performanceDayIndex", -1)) == day_index
		):
			host.ACTION_SETTLEMENT_RUNTIME.finish(host, resident_id, "已经听完这场演奏")


static func close_invitation_sources(
	host,
	day_index: int,
	reason: String,
) -> void:
	if day_index < 0:
		return
	var source_prefix := "performance-invitation:%d:" % day_index
	var executing_statuses: Array[String] = ["executing"]
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		for assignment: Dictionary in host.SOCIAL_GOAL_MATCHING_RUNTIME.active_assignments(host,
			resident_id,
			executing_statuses,
		):
			var matter := host._social_matters.get_matter(
				String(assignment.get("matter_id", "")),
			) as Dictionary
			var source_ref := matter.get("source_state_ref", {}) as Dictionary
			if (
				String(source_ref.get("source_kind", "")) == "resident_request"
				and String(source_ref.get("source_id", "")).begins_with(source_prefix)
				and host.SOCIAL_GOAL_MATCHING_RUNTIME.goal_matches_action(host,
					assignment.get("action_goal", {}) as Dictionary,
					action,
					resident_id,
				)
			):
				host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, reason)
				break
	var source_ids: Array[String] = []
	for value: Variant in host._social_matters.list_matters(false) as Array:
		var matter := value as Dictionary
		var source_ref := matter.get("source_state_ref", {}) as Dictionary
		var source_id := String(source_ref.get("source_id", ""))
		if (
			String(source_ref.get("source_kind", "")) == "resident_request"
			and source_id.begins_with(source_prefix)
			and not source_ids.has(source_id)
		):
			source_ids.append(source_id)
	for source_id: String in source_ids:
		SOCIAL_MATTER_COMMAND_RUNTIME.close_resident_request_source(
			host,
			source_id,
			"performance-invitation-ended",
		)
