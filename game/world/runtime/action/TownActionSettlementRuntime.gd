class_name TownActionSettlementRuntime
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const FOLLOW_UP_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpActionRuntime.gd"
)
const ROUTINE_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityRoutineSettlementRuntime.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)


static func finish(host, resident_id: String, reason: String) -> void:
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	if FOLLOW_UP_RUNTIME.continue_after_step(
		host,
		resident_id,
		resident,
		action,
	):
		return
	var action_id := String(action.get("action_id", ""))
	var presentation: Dictionary = ACTION_PRESENTATION._preview_action_presentation(
		host,
		resident,
		{"action": action},
	)
	restore_route_connector(resident, action)
	host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_matching_action_result(host,
		resident_id,
		action,
		"completed",
		reason,
	)
	_record_completed_animal_interaction(host, resident_id, action)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = reason
	ACTION_RESULT_RUNTIME.queue(
		host,
		resident_id,
		action_id,
		"completed",
		reason,
		true,
		true,
		presentation,
	)
	host._emit_resident_state_changed(resident_id)


static func interrupt(
	host,
	resident_id: String,
	reason: String,
	settle_as_completed: bool = false,
) -> void:
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	var outcome_status := (
		"completed" if settle_as_completed else "interrupted"
	)
	var outcome_reason := (
		priority_settlement_reason(host, action, reason)
		if settle_as_completed
		else reason
	)
	var action_id := String(action.get("action_id", ""))
	var presentation: Dictionary = ACTION_PRESENTATION._preview_action_presentation(
		host,
		resident,
		{"action": action},
	)
	if String(resident.get("spaceId", "")) != "town_outdoor":
		resident["routeConnector"] = []
	var activity_execution := host._activity_runtime.execution_for_action(
		resident_id,
		action_id,
	) as Dictionary
	if not activity_execution.is_empty():
		_interrupt_activity(
			host,
			resident_id,
			resident,
			action,
			activity_execution,
			action_id,
			outcome_status,
			outcome_reason,
			reason,
			presentation,
		)
		return
	host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_matching_action_result(host,
		resident_id,
		action,
		outcome_status,
		outcome_reason,
	)
	if String(action.get("type", "")) == "去":
		host.RESIDENT_CONDITION_SETTLEMENT_RUNTIME.settle_route(host,
			resident_id,
			resident,
			action,
			"interrupted",
		)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = outcome_reason
	ACTION_RESULT_RUNTIME.queue(
		host,
		resident_id,
		action_id,
		outcome_status,
		outcome_reason,
		true,
		true,
		presentation,
	)
	host._emit_resident_state_changed(resident_id)


static func restore_route_connector(
	resident: Dictionary,
	action: Dictionary,
) -> void:
	if not action.has("returnRouteConnector"):
		return
	if String(resident.get("spaceId", "")) != "town_outdoor":
		resident["routeConnector"] = []
		return
	resident["routeConnector"] = (
		action.get("returnRouteConnector", []) as Array
	).duplicate()


static func _interrupt_activity(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	activity_execution: Dictionary,
	action_id: String,
	outcome_status: String,
	outcome_reason: String,
	reason: String,
	presentation: Dictionary,
) -> void:
	var source_action_id := ACTION_PROJECTION.activity_source_action_id(
		action,
		activity_execution,
	)
	var interrupted := host._activity_runtime.interrupt_action(
		resident_id,
		action_id,
		outcome_reason,
	) as Dictionary
	host.RESIDENT_CONDITION_SETTLEMENT_RUNTIME.settle_activity(host,
		resident_id,
		resident,
		action,
		activity_execution,
		"interrupted",
		reason,
	)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = outcome_reason
	if host.activity_routine_state.records.has(resident_id):
		ROUTINE_SETTLEMENT_RUNTIME.close_routine(
			host,
			resident_id,
			"interrupted",
			outcome_reason,
		)
	host._bump_world_revision(false)
	if not source_action_id.is_empty():
		host._append_action_result_without_schedule(
			resident_id,
			source_action_id,
			outcome_status,
			outcome_reason,
			presentation,
		)
	host._notify_world_revision()
	host.ACTIVITY_LIFECYCLE_COMMIT_RUNTIME.emit(host,
		"interrupted",
		resident_id,
		interrupted.get("execution", activity_execution) as Dictionary,
		outcome_reason,
	)
	host._emit_resident_state_changed(resident_id)


static func _record_completed_animal_interaction(
	host,
	resident_id: String,
	action: Dictionary,
) -> void:
	var request: Dictionary = host._animal_fact_runtime.pet_attention_request(
		resident_id,
		action,
		int(host._environment.get_absolute_minute()),
	)
	if request.is_empty():
		return
	var result: Dictionary = host.set_animal_public_attention(
		String(request.get("animalId", "")),
		true,
		int(request.get("expiresAt", -1)),
		request.get("sourceEventIds", []) as Array,
	)
	if bool(result.get("ok", false)):
		WORLD_LOG_COMMIT_RUNTIME.append_animal(host,
			"居民抚摸动物",
			request.get("animal", {}) as Dictionary,
			resident_id,
			host.resident_display_name(resident_id),
		)


static func priority_settlement_reason(
	host,
	action: Dictionary,
	priority_reason: String,
) -> String:
	var action_label: String = host.ACTION_PROJECTION_MODULE.default_doing(host, action).strip_edges()
	if action_label.is_empty():
		action_label = "当前动作"
	var prefix := priority_reason.strip_edges()
	if prefix.is_empty() or prefix.contains("替换"):
		prefix = "优先事项到来"
	return "%s，%s先告一段落" % [prefix, action_label]
