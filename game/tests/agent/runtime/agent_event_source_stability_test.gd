extends SceneTree


const AGENT_SYSTEM := preload("res://agent/AgentSystem.gd")
const AgentTestCaseScript := preload(
	"res://tests/agent/support/AgentTestCase.gd"
)

var _failures: Array[String] = []


class MutableMemoryResident:
	var claim_root := "claim-root-a"
	var wakes: Array[Dictionary] = []

	func request_decision(
		wake: Dictionary,
		_completion: Callable,
		_feedback := "",
	) -> Dictionary:
		wakes.append(wake.duplicate(true))
		return {"ok": true}

	func find_expressed_memory_claim(_spoken_text: String) -> Dictionary:
		return {
			"ok": true,
			"matched": true,
			"claim_root_id": claim_root,
		}


func _initialize() -> void:
	AgentTestCaseScript.shutdown_project_autoloads(self)
	var system: RefCounted = AGENT_SYSTEM.new()
	var resident := MutableMemoryResident.new()
	system.set("_residents", {"resident-a": resident})
	var wake := {
		"decision_id": "decision-source-stability",
		"events": [{
			"event_id": "world-event-stable-1",
			"turn": {
				"speaker_resident_id": "resident-a",
				"say": "这件事已经确认过了。",
			},
		}],
	}
	_expect(
		system.call(
			"request_decision",
			"resident-a",
			wake,
			Callable(),
		).get("ok") == true,
		"首轮唤醒接受",
	)
	resident.claim_root = "claim-root-b"
	_expect(
		system.call(
			"request_decision",
			"resident-a",
			wake,
			Callable(),
		).get("ok") == true,
		"同一决定可重试",
	)
	_expect_equal(resident.wakes.size(), 2, "同一决定产生两次模型请求")
	if resident.wakes.size() == 2:
		var first_turn := (
			(resident.wakes[0].get("events", []) as Array)[0] as Dictionary
		).get("turn", {}) as Dictionary
		var second_turn := (
			(resident.wakes[1].get("events", []) as Array)[0] as Dictionary
		).get("turn", {}) as Dictionary
		_expect_equal(
			first_turn.get("memory_claim_root_id"),
			"claim-root-a",
			"首次事件使用当时的记忆来源",
		)
		_expect_equal(
			second_turn.get("memory_claim_root_id"),
			"claim-root-a",
			"重试不改写同一世界事件的记忆来源",
		)
	_finish()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s：实际=%s，期望=%s" % [message, actual, expected])


func _finish() -> void:
	var exit_code := 0 if _failures.is_empty() else 1
	if _failures.is_empty():
		print("AGENT_EVENT_SOURCE_STABILITY_PASS")
	else:
		print("AGENT_EVENT_SOURCE_STABILITY_FAIL")
	AgentTestCaseScript.shutdown_project_autoloads(self)
	await create_timer(0.6, true, false, true).timeout
	quit(exit_code)
