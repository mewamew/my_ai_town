class_name TownAgentDecisionTraceEvidence
extends RefCounted


const ACCEPTED := "accepted"
const CONTINUED_CURRENT := "continuedCurrent"
const INTERNAL_RETRY := "internalRetry"
const FALLBACK_RECOVERED := "fallbackRecovered"
const PROVIDER_FAILED := "providerFailed"
const STALE_DISCARDED := "staleDiscarded"
const WORLD_REJECTED := "worldRejected"
const INVALID_SUCCESS := "invalidSuccess"


static func classify(trace: Dictionary) -> Dictionary:
	var result := trace.get("agentResult", {}) as Dictionary
	var submission := trace.get("worldSubmission", {}) as Dictionary
	var decision := result.get("decision", {}) as Dictionary
	var action := decision.get("action", {}) as Dictionary
	var kind := ""
	if (
		bool(trace.get("stale", false))
		or bool(trace.get("superseded", false))
		or bool(submission.get("stale", false))
	):
		kind = STALE_DISCARDED
	elif not bool(result.get("ok", false)):
		if bool(trace.get("recovered", false)):
			kind = FALLBACK_RECOVERED
		elif bool(trace.get("ignored", false)):
			kind = INTERNAL_RETRY
		else:
			kind = PROVIDER_FAILED
	elif not submission.is_empty() and not bool(submission.get("ok", false)):
		kind = WORLD_REJECTED
	elif not action.is_empty() and not String(action.get("type", "")).strip_edges().is_empty():
		kind = ACCEPTED
	elif String(decision.get("handling", "")) == "continue_current":
		kind = CONTINUED_CURRENT
	else:
		kind = INVALID_SUCCESS
	return {
		"kind": kind,
		"decision": decision.duplicate(true),
		"action": action.duplicate(true),
		"submission": submission.duplicate(true),
	}
