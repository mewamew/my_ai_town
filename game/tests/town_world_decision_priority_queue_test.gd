extends SceneTree


const SOURCE_DIR := "res://world/data/town/source"
const OPENING_PATH := "res://tests/fixtures/town_world_opening.json"
const BUILDER := preload("res://world/data/town/TownWorldDataBuilder.gd")
const OPENING := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const WORLD := preload("res://world/runtime/TownWorldRuntime.gd")
const AGENT_TEST_CASE := preload("res://tests/agent/support/AgentTestCase.gd")
const RESIDENT_ID := "resident_su_he_01"

var _failures: Array[String] = []


func _initialize() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "queue test opening loads")
	if opening_result.get("ok") != true:
		_finish()
		return
	var world: RefCounted = WORLD.new()
	_expect_equal(
		world.start(data, opening_result.get("config", {}) as Dictionary).get("ok"),
		true,
		"queue test world starts",
	)
	var initial_requests := world.take_pending_decision_requests_by_ids([RESIDENT_ID]) as Array
	_expect_equal(initial_requests.size(), 1, "resident receives initial decision")
	if initial_requests.is_empty():
		_finish()
		return
	var initial_wake := (initial_requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
	_expect_equal(
		world.submit_agent_decision_by_id(RESIDENT_ID, {
			"decision_id": String(initial_wake.get("decision_id", "")),
			"handling": "replace_current",
			"action": {
				"action_id": "queue-current-wait",
				"type": "待着",
				"line": "先休息一下",
			},
		}).get("status"),
		"accepted",
		"resident starts the action that protects the queue",
	)

	var low_task := world.create_work_task({
		"taskId": "queue-low-priority-task",
		"capability": "library.return",
		"sourceKind": "returned_book",
		"sourceRef": "queue_low_return",
		"targets": [{"kind": "prop", "ref": "图书馆归还书台"}],
		"requestedResultKind": "loan_record",
		"priority": 70,
	}) as Dictionary
	_expect_equal(low_task.get("ok"), true, "low priority task is created")
	_expect_equal(
		world.take_pending_decision_requests_by_ids([RESIDENT_ID]).size(),
		0,
		"low priority task waits for the current action",
	)

	var high_task := world.create_work_task({
		"taskId": "queue-high-priority-task",
		"capability": "library.return",
		"sourceKind": "returned_book",
		"sourceRef": "queue_high_return",
		"targets": [{"kind": "prop", "ref": "图书馆归还书台"}],
		"requestedResultKind": "loan_record",
		"priority": 86,
	}) as Dictionary
	_expect_equal(high_task.get("ok"), true, "high priority task is created")
	var high_requests := world.take_pending_decision_requests_by_ids([RESIDENT_ID]) as Array
	_expect_equal(high_requests.size(), 1, "high priority task can interrupt the current action")
	if not high_requests.is_empty():
		var high_wake := (high_requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
		var tasks := ((high_wake.get("snapshot", {}) as Dictionary).get("work_tasks", []) as Array)
		_expect(
			_has_task(tasks, "queue-low-priority-task")
			and _has_task(tasks, "queue-high-priority-task"),
			"both low and high priority tasks remain pending",
		)
		if not tasks.is_empty():
			_expect_equal(
				(tasks[0] as Dictionary).get("priority"),
				86,
				"highest priority task is presented first",
			)
		var replacement := world.submit_agent_decision_by_id(RESIDENT_ID, {
			"decision_id": String(high_wake.get("decision_id", "")),
			"handling": "replace_current",
			"action": {
				"action_id": "queue-high-priority-action",
				"type": "待着",
				"line": "先处理紧急事项",
			},
		}) as Dictionary
		_expect_equal(replacement.get("status"), "accepted", "priority action is accepted")
		var resident := ((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(RESIDENT_ID, {}) as Dictionary
		var results := resident.get("resultQueue", []) as Array
		_expect(
			_results_include_completed_settlement(results, "queue-current-wait"),
			"preempted action is settled instead of marked failed",
		)

	world.stop()
	_finish()


func _results_include_completed_settlement(results: Array, action_id: String) -> bool:
	for value: Variant in results:
		if not value is Dictionary:
			continue
		var result := value as Dictionary
		if (
			String(result.get("action_id", "")) == action_id
			and String(result.get("status", "")) == "completed"
			and String(result.get("reason", "")).contains("告一段落")
		):
			return true
	return false


func _has_task(tasks: Array, task_id: String) -> bool:
	for value: Variant in tasks:
		if value is Dictionary and String((value as Dictionary).get("task_id", "")) == task_id:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, expected, actual])


func _finish() -> void:
	AGENT_TEST_CASE.shutdown_project_autoloads(self)
	if _failures.is_empty():
		print("TOWN_WORLD_DECISION_PRIORITY_QUEUE_PASS")
		call_deferred("_quit_after_shutdown", 0)
		return
	for failure in _failures:
		printerr("TOWN_WORLD_DECISION_PRIORITY_QUEUE_FAIL: %s" % failure)
	call_deferred("_quit_after_shutdown", 1)


func _quit_after_shutdown(exit_code: int) -> void:
	await process_frame
	AGENT_TEST_CASE.shutdown_project_autoloads(self)
	await create_timer(0.6, true, false, true).timeout
	quit(exit_code)
