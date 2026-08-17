class_name TownAgentDecisionEnvelopeRuntime
extends RefCounted


static func by_id_entry_error(
	running: bool,
	resident_id: String,
	resident_name: String,
	resident_exists: bool,
	resident_alive: bool,
	world_revision: int,
) -> Dictionary:
	if not running:
		return {
			"ok": false,
			"stale": true,
			"errorCode": "WORLD_NOT_RUNNING",
			"retryable": false,
			"errors": ["世界尚未运行"],
			"residentId": resident_id,
			"residentName": "",
			"worldRevision": world_revision,
		}
	if resident_name.is_empty() or not resident_exists:
		return {
			"ok": false,
			"stale": false,
			"errorCode": "WORLD_RESIDENT_ID_UNKNOWN",
			"retryable": false,
			"errors": ["未知居民 ID：%s" % resident_id],
			"residentId": resident_id,
			"residentName": "",
			"worldRevision": world_revision,
		}
	if not resident_alive:
		return {
			"ok": false,
			"stale": true,
			"errorCode": "RESIDENT_DEAD",
			"retryable": false,
			"errors": ["该居民已经死亡，不能再提交决定"],
			"residentId": resident_id,
			"residentName": resident_name,
			"worldRevision": world_revision,
		}
	return {}


static func submission_entry_error(
	running: bool,
	submitted_resident_ref: String,
	resident_id: String,
	resident_alive: bool,
	paused: bool,
	resident: Dictionary,
	decision_id: String,
) -> Dictionary:
	if not running:
		return {"ok": false, "stale": true, "errors": ["世界尚未运行"]}
	if resident_id.is_empty():
		return {
			"ok": false,
			"stale": false,
			"errors": ["未知居民：%s" % submitted_resident_ref],
		}
	if not resident_alive:
		return {
			"ok": false,
			"stale": true,
			"errorCode": "RESIDENT_DEAD",
			"retryable": false,
			"errors": ["该居民已经死亡，不能再提交决定"],
		}
	if paused:
		if (
			bool(resident.get("decisionPending", false))
			and decision_id == String(resident.get("validDecisionId", ""))
		):
			resident["wakeDispatchQueued"] = true
		return {
			"ok": false,
			"stale": false,
			"errorCode": "WORLD_PAUSED",
			"retryable": true,
			"errors": ["世界暂停期间不接收新的居民决定"],
		}
	if (
		not bool(resident.get("decisionPending", false))
		or decision_id != String(resident.get("validDecisionId", ""))
	):
		return {
			"ok": false,
			"stale": true,
			"errors": ["决定已经失效：%s" % decision_id],
		}
	return {}


static func submission_context(
	resident: Dictionary,
	story_provenance: Dictionary,
) -> Dictionary:
	return {
		"storyProvenance": story_provenance.duplicate(true),
		"inflightEvents": (
			resident.get("inflightEvents", []) as Array
		).duplicate(true),
		"inflightResults": (
			resident.get("inflightResults", []) as Array
		).duplicate(true),
		"wakePacket": (
			resident.get("pendingWake", {}) as Dictionary
		).duplicate(true),
		"wasPrefetched": bool(resident.get("decisionPrefetch", false)),
		"mayInterruptCurrent": bool(
			resident.get("decisionMayInterruptCurrent", false)
		),
	}


static func store_prefetched_decision(
	resident: Dictionary,
	resident_id: String,
	decision_id: String,
	decision: Dictionary,
	wake_packet: Dictionary,
	inflight_events: Array,
	inflight_results: Array,
) -> Dictionary:
	resident["decisionPending"] = true
	resident["validDecisionId"] = decision_id
	resident["pendingWake"] = wake_packet
	resident["inflightEvents"] = inflight_events
	resident["inflightResults"] = inflight_results
	resident["wakeDispatchQueued"] = false
	resident["prefetchedDecision"] = decision.duplicate(true)
	resident["decisionPrefetch"] = false
	return {
		"ok": true,
		"status": "prefetched",
		"residentId": resident_id,
		"decisionId": decision_id,
	}
