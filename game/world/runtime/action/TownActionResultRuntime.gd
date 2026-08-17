class_name TownActionResultRuntime
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const RESIDENT_ARRIVAL_RUNTIME := preload(
	"res://world/runtime/TownResidentArrivalRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const AGENT_WAKE_STATE_RUNTIME := preload(
	"res://world/runtime/TownAgentWakeStateRuntime.gd"
)


static func reject_invalid(
	host,
	resident_name: String,
	resident: Dictionary,
	action: Dictionary,
	reason: String,
) -> Dictionary:
	var fingerprint := ACTION_VALIDATION.invalid_action_fingerprint(action, reason)
	var previous_fingerprint := String(
		resident.get("lastRejectedActionFingerprint", ""),
	)
	var repeat_count := (
		int(resident.get("consecutiveRejectedActionCount", 0)) + 1
		if fingerprint == previous_fingerprint
		else 1
	)
	resident["lastRejectedActionFingerprint"] = fingerprint
	resident["consecutiveRejectedActionCount"] = repeat_count
	var rejected_action_id := (
		String(action.get("action_id", "")).strip_edges()
		if action.get("action_id") is String
		else ""
	)
	var used_action_ids := resident.get("usedActionIds", {}) as Dictionary
	if rejected_action_id.is_empty() or used_action_ids.has(rejected_action_id):
		host._schedule_decision(resident_name, false)
	else:
		used_action_ids[rejected_action_id] = true
		queue(
			host,
			resident_name,
			rejected_action_id,
			"rejected",
			reason,
			true,
			not (repeat_count >= 2 and String(action.get("type", "")) == "搭话"),
			ACTION_PRESENTATION._preview_action_presentation(
				host,
				resident,
				{"action": action},
			),
		)
	return {"ok": false, "stale": false, "errors": [reason]}


static func append_without_schedule(
	host,
	resident_id: String,
	action_id: String,
	status: String,
	reason: String,
	presentation: Dictionary = {},
) -> void:
	if RESIDENT_ARRIVAL_RUNTIME.is_entry_continuity_action_id(resident_id, action_id): return
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var result := {
		"residentId": resident_id,
		"action_id": action_id,
		"status": status,
		"reason": reason,
		"time": host.get_time(),
	}
	ACTION_SUPPORT.apply_action_result_presentation(result, status, presentation)
	ACTION_VALIDATION.append_or_replace_action_result(
		resident.get("resultQueue", []) as Array,
		result,
	)
	if bool(resident.get("decisionPending", false)):
		AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	WORLD_LOG_COMMIT_RUNTIME.append_public(
		host,
		host.world_log_domain.journal.next_world_event_id(),
		"action_result",
		resident_id,
		host.resident_display_name(resident_id),
		String(resident.get("currentPlace", "")),
		result,
	)
	WORLD_LOG_COMMIT_RUNTIME.record_story_action_outcome(host,
		resident_id,
		action_id,
		status,
		reason,
	)
	host.action_result_created.emit(host.resident_display_name(resident_id), result.duplicate(true))


static func queue(
	host,
	resident_name: String,
	action_id: String,
	status: String,
	reason: String,
	invalidate_request := true,
	schedule_request := true,
	presentation: Dictionary = {},
) -> void:
	if RESIDENT_ARRIVAL_RUNTIME.is_entry_continuity_action_id(resident_name, action_id): return
	var resident := host.resident_registry.records[resident_name] as Dictionary
	var result_presentation := presentation.duplicate(true)
	if result_presentation.is_empty():
		var current_action := resident.get("currentAction", {}) as Dictionary
		if String(
			current_action.get(
				"sourceActionId",
				current_action.get("action_id", ""),
			)
		).strip_edges() == action_id.strip_edges():
			var activity_cue: Variant = ACTION_PRESENTATION._resident_activity_cue(host, resident)
			var current_presentation: Variant = ACTION_PRESENTATION._resident_action_presentation(host,
				resident,
				activity_cue,
			)
			if current_presentation is Dictionary:
				result_presentation = (
					current_presentation as Dictionary
				).duplicate(true)
	var result := {
		"residentId": resident_name,
		"action_id": action_id,
		"status": status,
		"reason": reason,
		"time": host.get_time(),
	}
	ACTION_SUPPORT.apply_action_result_presentation(
		result,
		status,
		result_presentation,
	)
	ACTION_VALIDATION.append_or_replace_action_result(
		resident.get("resultQueue", []) as Array,
		result,
	)
	if bool(resident.get("decisionPending", false)):
		AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	WORLD_LOG_COMMIT_RUNTIME.append_public(
		host,
		host.world_log_domain.journal.next_world_event_id(),
		"action_result",
		resident_name,
		host.resident_display_name(resident_name),
		String(resident.get("currentPlace", "")),
		result,
	)
	WORLD_LOG_COMMIT_RUNTIME.record_story_action_outcome(host,
		resident_name,
		action_id,
		status,
		reason,
	)
	host.action_result_created.emit(host.resident_display_name(resident_name), result.duplicate(true))
	if schedule_request:
		host._schedule_decision(resident_name, invalidate_request)
