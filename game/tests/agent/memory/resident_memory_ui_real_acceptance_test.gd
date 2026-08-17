extends SceneTree


const AgentTestCaseScript := preload(
	"res://tests/agent/support/AgentTestCase.gd"
)


const AGENT_SYSTEM := preload("res://agent/AgentSystem.gd")
const GATEWAY := preload("res://world/integration/TownWorldAgentGateway.gd")
const UI_PROJECTION_SERVICE := preload(
	"res://world/presentation/ui/TownUiPageProjectionService.gd"
)
const SCRIPTED_MODEL := preload("res://tests/agent/support/ScriptedModelProvider.gd")
const CLEANER := preload("res://tests/support/UserTestDataCleaner.gd")

const RESIDENT_ID := "resident-lin-lan"
const MEMORY_KEY := "memory-real-ui-acceptance"
var _test_root := "user://tests/resident-memory-ui-real-acceptance/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


class MemoryWorld:
	extends RefCounted

	func get_time() -> Dictionary:
		return {"day": 4, "period": "下午", "clock": "15:20"}

	func get_world_revision() -> int:
		return 12

	func get_resident_identity_snapshot() -> Dictionary:
		return {
			"status": "confirmed",
			"residents": [{
				"residentId": RESIDENT_ID,
				"residentName": "林岚",
			}],
		}

	func get_resident_state(_resident_id: String) -> Dictionary:
		return {"doing": "整理木架"}


var _failures: Array[String] = []


class DecisionCollector:
	var values: Array[Dictionary] = []

	func collect(value: Dictionary) -> void:
		values.append(value.duplicate(true))


func _initialize() -> void:
	AgentTestCaseScript.shutdown_project_autoloads(self)
	call_deferred("_run")


func _run() -> void:
	var agent: RefCounted = AGENT_SYSTEM.new()
	_expect_ok(
		agent.call("configure_test_runtime_storage", _test_root) as Dictionary,
		"real AgentSystem uses an isolated memory root",
	)
	var save_context := {
		"slot_id": "real-resident-memory-ui-%d" % Time.get_ticks_usec(),
		"session_id": "real-resident-memory-ui-%d" % Time.get_ticks_usec(),
		"save_revision": 0,
	}
	_expect_ok(
		agent.call("start_new_game", save_context) as Dictionary,
		"real AgentSystem starts an isolated session",
	)
	var initialization := _initialization()
	var model := SCRIPTED_MODEL.new()
	_expect_ok(
		agent.call("initialize_resident", initialization, model) as Dictionary,
		"real resident runtime initializes",
	)
	_expect_ok(
		agent.call("finish_new_game") as Dictionary,
		"real resident memory state becomes ready",
	)

	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_world", MemoryWorld.new())
	gateway.set("_session_active", true)
	var connected_resident_ids: Array[String] = [RESIDENT_ID]
	gateway.set("_connected_resident_ids", connected_resident_ids)
	gateway.set("_resident_name_by_id", {RESIDENT_ID: "林岚"})

	var initial_memory := gateway.call("get_resident_memory", RESIDENT_ID) as Dictionary
	_expect_ok(initial_memory, "gateway reads the real resident memory before intervention")
	var first_write := gateway.call(
		"apply_resident_memory_intervention",
		RESIDENT_ID,
		{
			"memoryKey": MEMORY_KEY,
			"operation": "write",
			"playerText": "我答应今天把木架送到市集。",
			"expectedRevision": 0,
		},
	) as Dictionary
	_expect_ok(first_write, "gateway writes a real resident memory")
	var edited := gateway.call(
		"apply_resident_memory_intervention",
		RESIDENT_ID,
		{
			"memoryKey": MEMORY_KEY,
			"operation": "edit",
			"playerText": "我记得今天要把改好的木架送到市集。",
			"expectedRevision": 1,
		},
	) as Dictionary
	_expect_ok(edited, "gateway edits the real resident memory")

	var after_memory := gateway.call("get_resident_memory", RESIDENT_ID) as Dictionary
	_expect_ok(after_memory, "gateway reads the edited memory back from Agent")
	var public_memory := after_memory.get("memory", {}) as Dictionary
	var formal_memories := public_memory.get("formal_memories", []) as Array
	var edited_subject := ""
	for entry_value: Variant in formal_memories:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		if String(entry.get("memoryKey", "")) == MEMORY_KEY:
			edited_subject = String(entry.get("subject", ""))
	_expect_equal(
		edited_subject,
		"我记得今天要把改好的木架送到市集。",
		"real Agent read-back contains the edited resident memory",
	)
	var residents := agent.get("_residents") as Dictionary
	var resident_runtime := residents.get(RESIDENT_ID) as RefCounted
	var memory_system := resident_runtime.get("_memory_system") as RefCounted
	var decision_context := memory_system.call(
		"retrieve_context",
		{
			"decision_id": "real-memory-effect-check",
			"snapshot": {
				"time": {"day": 4, "period": "下午", "clock": "15:20"},
				"place": {"name": "市集"},
				"me": {"doing": "把改好的木架送到市集"},
			},
			"events": [],
			"action_results": [],
		},
	) as Dictionary
	_expect_ok(
		decision_context,
		"next real decision reads the resident memory context",
	)
	_expect(
		String(decision_context.get("memory_prompt", "")).contains(
			"我记得今天要把改好的木架送到市集。",
		),
		"next real decision context contains the edited resident memory",
	)
	var reaction_wake := {
		"decision_id": "real-memory-reaction",
		"snapshot": {
			"time": {"day": 4, "period": "下午", "clock": "15:20"},
			"weather": "晴天",
			"me": {
				"doing": "在工作坊整理木架",
				"current_action": null,
				"body": {"困": "不困", "饿": "不饿", "累": "不累"},
			},
			"nearby": [],
			"place": {"name": "工作坊", "props": []},
			"conversation": null,
		},
		"events": [],
		"action_results": [],
	}
	var expected_reaction := {
		"decision_id": "real-memory-reaction",
		"handling": "replace_current",
		"action": {
			"action_id": "real-memory-reaction-action",
			"type": "去",
			"place": "市集",
			"line": "我得把改好的木架送到市集。",
		},
	}
	model.call("queue_decision", expected_reaction)
	var reaction_results := DecisionCollector.new()
	var decision_start := agent.call(
		"request_decision",
		RESIDENT_ID,
		reaction_wake,
		reaction_results.collect,
	) as Dictionary
	_expect_ok(decision_start, "real resident decision starts after memory edit")
	_expect_equal(
		reaction_results.values.size(),
		1,
		"real resident produces one reaction",
	)
	if reaction_results.values.size() == 1:
		var reaction := reaction_results.values[0]
		var reaction_action := (
			reaction.get("decision", {}) as Dictionary
		).get("action", {}) as Dictionary
		_expect_ok(reaction, "real resident reaction is accepted")
		_expect_equal(
			reaction_action.get("place"),
			"市集",
			"real resident reacts by going to the place named in the edited memory",
		)
	var model_requests := model.call("get_requests") as Array
	_expect(
		not model_requests.is_empty()
			and JSON.stringify(model_requests[-1]).contains(
				"我记得今天要把改好的木架送到市集。",
			),
		"reaction model receives the edited memory in its decision request",
	)
	print("NPC_MEMORY_REACTION: 林岚读取到修改后的记忆后，决定前往市集送木架。")

	var snapshot := gateway.call(
		"_public_inner_observation_snapshot",
		RESIDENT_ID,
		12,
	) as Dictionary
	_expect(not snapshot.is_empty(), "inner observation reads a real Agent snapshot")
	var ready := gateway.call(
		"_inner_observation_ready_result",
		snapshot,
		"real-inner-observation",
	) as Dictionary
	var content := ready.get("content", {}) as Dictionary
	_expect_equal(ready.get("status"), "ready", "real inner observation completes")
	_expect_equal(content.get("empty"), false, "real inner observation keeps the current reaction")
	_expect(
		String(content.get("monologueText", "")).contains(
			"我得把改好的木架送到市集。",
		),
		"real inner observation displays the resident's current thought",
	)
	_expect(
		String(content.get("reasonText", "")).contains(
			"我记得今天要把改好的木架送到市集。",
		),
		"real inner observation uses one relevant memory as its reason",
	)

	var service: RefCounted = UI_PROJECTION_SERVICE.new()
	_expect(
		gateway.has_method("request_resident_inner_observation")
			and gateway.has_method("cancel_resident_inner_observation"),
		"real gateway exposes the inner observation interface",
	)
	var service_bind := service.bind(
		null,
		gateway.get("_world"),
		{
			"worldStartMode": "formal",
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
		},
		gateway,
	) as Dictionary
	_expect_ok(service_bind, "real gateway binds to the UI projection service")
	service.set_page_context("resident_action_menu", {
		"residentId": RESIDENT_ID,
		"open": true,
	})
	var open_result := service.dispatch(
		"resident.inner_observation.open",
		{"residentId": RESIDENT_ID},
	) as Dictionary
	_expect_ok(open_result, "real inner observation page opens")
	await process_frame
	await process_frame
	var page := service.get_view_model("inner_observation") as Dictionary
	var page_data := page.get("data", {}) as Dictionary
	var page_content := page_data.get("content", {}) as Dictionary
	_expect(
		String(page_content.get("monologueText", "")).contains(
			"我得把改好的木架送到市集。",
		),
		"real inner observation page displays the resident's current thought",
	)
	_expect(
		String(page_content.get("reasonText", "")).contains(
			"我记得今天要把改好的木架送到市集。",
		),
		"real inner observation page displays one relevant reason",
	)
	service.unbind()

	if not CLEANER.remove_tree(_test_root):
		_failures.append("real resident memory acceptance root is removed")
	gateway.free()
	agent.call("delete_game", save_context)
	agent.call("close_game")
	service = null
	model = null
	agent = null
	AgentTestCaseScript.shutdown_project_autoloads(self)
	if _failures.is_empty():
		print("RESIDENT_MEMORY_UI_REAL_ACCEPTANCE_PASS")
	else:
		for failure in _failures:
			push_error("RESIDENT_MEMORY_UI_REAL_ACCEPTANCE_FAIL: %s" % failure)
	call_deferred("_quit_after_shutdown", 0 if _failures.is_empty() else 1)


func _quit_after_shutdown(exit_code: int) -> void:
	await process_frame
	AgentTestCaseScript.shutdown_project_autoloads(self)
	await create_timer(0.6, true, false, true).timeout
	quit(exit_code)


func _initialization() -> Dictionary:
	return {
		"me": {
			"resident_id": RESIDENT_ID,
			"attributes": {
				"name": "林岚",
				"gender": "男",
				"age": 32,
				"desire": "把手艺做好",
				"personality": "话少，慢热",
				"speech": "说话简短",
			},
			"social_state": {
				"home": "林岚家",
				"job": "木匠",
				"workplace": "工作坊",
			},
		},
		"residents": [],
		"places": [{
			"name": "市集",
			"type": "公共地点",
			"owner": null,
			"owner_resident_id": null,
			"summary": "居民交换物品的地方",
		}],
	}


func _expect_ok(result: Dictionary, message: String) -> void:
	if result.get("ok") != true:
		_failures.append("%s (actual=%s)" % [message, result])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s (actual=%s expected=%s)" % [message, actual, expected]
		)
