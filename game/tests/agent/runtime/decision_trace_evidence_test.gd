extends "res://tests/agent/support/AgentTestCase.gd"


const TRACE_EVIDENCE := preload(
	"res://tests/support/TownAgentDecisionTraceEvidence.gd"
)


func _initialize() -> void:
	_expect_kind(
		{"agentResult": {"ok": true, "decision": {"action": {"type": "去"}}}, "worldSubmission": {"ok": true}},
		TRACE_EVIDENCE.ACCEPTED,
	)
	_expect_kind(
		{"agentResult": {"ok": true, "decision": {"handling": "continue_current"}}, "worldSubmission": {"ok": true}},
		TRACE_EVIDENCE.CONTINUED_CURRENT,
	)
	_expect_kind(
		{"ignored": true, "agentResult": {"ok": false}},
		TRACE_EVIDENCE.INTERNAL_RETRY,
	)
	_expect_kind(
		{"ignored": true, "recovered": true, "agentResult": {"ok": false}},
		TRACE_EVIDENCE.FALLBACK_RECOVERED,
	)
	_expect_kind(
		{"agentResult": {"ok": false}},
		TRACE_EVIDENCE.PROVIDER_FAILED,
	)
	_expect_kind(
		{"stale": true, "agentResult": {"ok": true}},
		TRACE_EVIDENCE.STALE_DISCARDED,
	)
	_expect_kind(
		{"agentResult": {"ok": true}, "worldSubmission": {"ok": false, "stale": true}},
		TRACE_EVIDENCE.STALE_DISCARDED,
	)
	_expect_kind(
		{"agentResult": {"ok": true, "decision": {"action": {"type": "去"}}}, "worldSubmission": {"ok": false}},
		TRACE_EVIDENCE.WORLD_REJECTED,
	)
	_expect_kind(
		{"agentResult": {"ok": true, "decision": {}}, "worldSubmission": {"ok": true}},
		TRACE_EVIDENCE.INVALID_SUCCESS,
	)
	_finish_suite("AGENT_DECISION_TRACE_EVIDENCE_PASS")


func _expect_kind(trace: Dictionary, expected: String) -> void:
	var evidence := TRACE_EVIDENCE.classify(trace) as Dictionary
	_expect_equal(
		String(evidence.get("kind", "")),
		expected,
		"决策调试记录分类为 %s" % expected,
	)
