class_name TownResidentEventQueueRuntime
extends RefCounted


const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)


static func deduplicated_world_events(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen_event_ids := {}
	var coalesced_indexes := {}
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var event := value as Dictionary
		var event_id := String(event.get("event_id", "")).strip_edges()
		if not event_id.is_empty() and seen_event_ids.has(event_id):
			continue
		if not event_id.is_empty():
			seen_event_ids[event_id] = true
		var coalescing_key := world_event_coalescing_key(event)
		if (
			not coalescing_key.is_empty()
			and coalesced_indexes.has(coalescing_key)
		):
			result[int(coalesced_indexes[coalescing_key])] = event.duplicate(true)
			continue
		if not coalescing_key.is_empty():
			coalesced_indexes[coalescing_key] = result.size()
		result.append(event.duplicate(true))
	return result


static func world_event_coalescing_key(event: Dictionary) -> String:
	var event_type := String(event.get("type", ""))
	match event_type:
		"天气变了":
			return "天气变了|%s" % String(event.get("weather", ""))
		"公告发布":
			return "公告发布|%s" % String(event.get("announcement_id", ""))
		"公告到点":
			return "公告到点|%s" % String(event.get("announcement_id", ""))
		"钟声公告":
			return "钟声公告|%s" % String(event.get("announcement_id", ""))
		"公告阅读":
			return "公告阅读|%s" % String(event.get("announcement_id", ""))
		"公告转告":
			return "公告转告|%s|%s" % [
				String(event.get("announcement_id", "")),
				String(event.get("speaker_resident_id", "")),
			]
		"正式通知送达":
			return "正式通知送达|%s" % String(event.get("message_id", ""))
		"营业状态变化":
			return "营业状态变化|%s|%s" % [
				String(event.get("place_id", "")),
				"1" if bool(event.get("open", false)) else "0",
			]
		"承诺条件变化":
			return "承诺条件变化|%s" % String(
				event.get("commitment_action_id", "")
			)
		"冲突见闻":
			return "冲突见闻|%s" % String(
				event.get("conflict_event_id", event.get("conflict_id", ""))
			)
		"身体状况变化":
			return "身体状况变化|%s|%s|%s" % [
				String(event.get("eventId", "")),
				String(event.get("conditionId", "")),
				String(event.get("state", "")),
			]
		_:
			return ""


static func append_pending_world_event(
	resident: Dictionary,
	event: Dictionary,
) -> void:
	var event_id := String(event.get("event_id", "")).strip_edges()
	var coalescing_key := world_event_coalescing_key(event)
	var queue := resident.get("eventQueue", []) as Array
	for value: Variant in resident.get("inflightEvents", []) as Array:
		if not value is Dictionary:
			continue
		var existing := value as Dictionary
		if (
			not event_id.is_empty()
			and String(existing.get("event_id", "")).strip_edges() == event_id
		):
			return
		if (
			not coalescing_key.is_empty()
			and world_event_coalescing_key(existing) == coalescing_key
		):
			break
	for index in queue.size():
		var existing_value: Variant = queue[index]
		if not existing_value is Dictionary:
			continue
		var existing := existing_value as Dictionary
		if (
			(not event_id.is_empty()
			and String(existing.get("event_id", "")).strip_edges() == event_id)
			or (
				not coalescing_key.is_empty()
				and world_event_coalescing_key(existing) == coalescing_key
			)
		):
			queue[index] = event.duplicate(true)
			return
	queue.append(event.duplicate(true))


static func restore_inflight_facts(resident: Dictionary) -> void:
	var events := (resident.get("inflightEvents", []) as Array).duplicate(true)
	events.append_array(resident.get("eventQueue", []) as Array)
	resident["eventQueue"] = deduplicated_world_events(events)
	var results := (resident.get("inflightResults", []) as Array).duplicate(true)
	results.append_array(resident.get("resultQueue", []) as Array)
	resident["resultQueue"] = ACTION_VALIDATION.deduplicated_action_results(results)
	resident["inflightEvents"] = []
	resident["inflightResults"] = []


static func begin_decision(
	resident: Dictionary,
	resident_id: String,
	runtime_generation: int,
	prefetch: bool,
	allow_current_activity_interrupt: bool,
) -> Dictionary:
	resident["decisionSequence"] = int(resident.get("decisionSequence", 0)) + 1
	var decision_id := "%s-g%d-%d" % [
		resident_id,
		runtime_generation,
		int(resident["decisionSequence"]),
	]
	var events := deduplicated_world_events(
		(resident.get("eventQueue", []) as Array).duplicate(true),
	)
	var results := ACTION_VALIDATION.deduplicated_action_results(
		(resident.get("resultQueue", []) as Array).duplicate(true),
	)
	(resident.get("eventQueue", []) as Array).clear()
	(resident.get("resultQueue", []) as Array).clear()
	resident["inflightEvents"] = events.duplicate(true)
	resident["inflightResults"] = results.duplicate(true)
	resident["validDecisionId"] = decision_id
	resident["decisionPending"] = true
	resident["decisionPrefetch"] = prefetch
	resident["decisionMayInterruptCurrent"] = (
		allow_current_activity_interrupt and not prefetch
	)
	resident["prefetchedDecision"] = {}
	resident["pendingWake"] = {
		"decision_id": decision_id,
		"events": ACTION_SUPPORT.agent_fact_payloads(events),
		"action_results": ACTION_SUPPORT.agent_fact_payloads(results),
	}
	return {
		"decisionId": decision_id,
		"events": events,
		"results": results,
	}
