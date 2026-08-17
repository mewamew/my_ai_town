extends SceneTree


const RuntimeScript := preload("res://agent/ResidentRuntime.gd")
const AgentSystemScript := preload("res://agent/AgentSystem.gd")
const SaveStoreScript := preload("res://agent/lifecycle/AgentSaveStore.gd")
const CleanerScript := preload("res://tests/support/UserTestDataCleaner.gd")
const AgentTestCaseScript := preload(
	"res://tests/agent/support/AgentTestCase.gd"
)

const AVATAR_ID := "person_7f3a91c2d8e4"
const TEST_ROOT_BASE := "user://tests/avatar-memory-runtime"
const SAVE_ROOT_BASE := "user://agent_save_tests/avatar-memory-runtime"

var _test_suffix := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
var _memory_root := "%s/%s" % [TEST_ROOT_BASE, _test_suffix]
var _save_root := "%s/%s" % [SAVE_ROOT_BASE, _test_suffix]
var _failures: Array[String] = []


class ScriptedProvider:
	extends RefCounted

	var write_message := true
	var fail_departure := false
	var departure_calls := 0
	var requests: Array[Dictionary] = []

	func _init(
		should_write := true,
		should_fail_departure := false,
	) -> void:
		write_message = should_write
		fail_departure = should_fail_departure

	func request_json(request: Dictionary, callback: Callable) -> void:
		requests.append(request.duplicate(true))
		var kind := String(request.get("request_kind", ""))
		if kind == "memory_organization":
			callback.call({
				"ok": true,
				"json": (
					request.get("old_memory", {}) as Dictionary
				).duplicate(true),
			})
			return
		if kind == "avatar_memory_organization":
			var evidence := request.get("evidence_items", []) as Array
			var first := evidence[0] as Dictionary
			if JSON.stringify(evidence).contains("找到找不到都给我留个言"):
				callback.call({
					"ok": true,
					"json": {
						"summary": "旅行者请我寻找迪迦并留言告知结果。",
						"memories": [],
						"open_loops": [{
							"content": "寻找迪迦，找到找不到都给旅行者留言。",
							"world_time": (
								first.get("world_time", {}) as Dictionary
							).duplicate(true),
							"source_type": "direct_dialogue",
							"source_person_id": AVATAR_ID,
							"source_refs": [String(
								first.get("source_ref", ""),
							)],
							"status": "active",
							"salience": 4,
							"people": [AVATAR_ID],
							"progress": "尚未留言告知结果",
						}],
						"message_updates": [],
					},
				})
				return
			callback.call({
				"ok": true,
				"json": {
					"summary": "化身亲口说自己叫迪迦。",
					"memories": [{
						"content": "化身亲口说自己叫迪迦。",
						"world_time": (
							first.get("world_time", {}) as Dictionary
						).duplicate(true),
						"source_type": "direct_dialogue",
						"source_person_id": AVATAR_ID,
						"source_refs": [String(first.get("source_ref", ""))],
						"status": "active",
						"salience": 4,
					}],
					"open_loops": [],
					"message_updates": [],
				},
			})
			return
		if kind == "departure_message":
			departure_calls += 1
			if fail_departure:
				callback.call({
					"ok": false,
					"errors": ["simulated departure message timeout"],
				})
				return
			callback.call({
				"ok": true,
				"json": {
					"write": write_message,
					"message": "迪迦，明天见。" if write_message else "",
				},
			})
			return
		callback.call({"ok": false, "errors": ["unexpected JSON request"]})

	func request_decision(request: Dictionary, callback: Callable) -> void:
		requests.append(request.duplicate(true))
		var wake := request.get("wake_packet", {}) as Dictionary
		var conversation: Variant = (
			wake.get("snapshot", {}) as Dictionary
		).get("conversation")
		if typeof(conversation) == TYPE_DICTIONARY:
			callback.call({
				"ok": true,
				"decision": {
					"decision_id": String(wake.get("decision_id", "")),
					"handling": "replace_current",
					"action": {
						"action_id": "action-%s" % String(
							wake.get("decision_id", ""),
						),
						"type": "答话",
						"conversation_id": String(
							(conversation as Dictionary).get(
								"conversation_id",
								"",
							),
						),
						"say": "我知道了。",
						"narration": "",
						"photos": [],
						"end": false,
					},
				},
			})
			return
		callback.call({
			"ok": true,
			"decision": {
				"decision_id": String(wake.get("decision_id", "")),
				"handling": "replace_current",
				"action": {
					"action_id": "action-%s" % String(
						wake.get("decision_id", ""),
					),
					"type": "待着",
					"line": "我记住了。",
				},
			},
		})


func _initialize() -> void:
	_prepare_project_shutdown()
	call_deferred("_run")


func _run() -> void:
	_test_runtime_prompt_persistence_and_legacy_migration()
	_test_runtime_departure_forces_pending_avatar_organization()
	_test_agent_system_departure_limit_and_idempotency()
	CleanerScript.remove_tree(_memory_root)
	var cleanup_store := SaveStoreScript.new()
	cleanup_store.call("configure_test_root", _save_root)
	cleanup_store.call("cleanup_test_root")
	if _failures.is_empty():
		print("AVATAR_MEMORY_RUNTIME_INTEGRATION_PASS")
	else:
		for failure in _failures:
			printerr("AVATAR_MEMORY_RUNTIME_INTEGRATION_FAIL: %s" % failure)
	_prepare_project_shutdown()
	call_deferred("_quit_after_shutdown", 0 if _failures.is_empty() else 1)


func _prepare_project_shutdown() -> void:
	AgentTestCaseScript.shutdown_project_autoloads(self)


func _quit_after_shutdown(exit_code: int) -> void:
	await process_frame
	_prepare_project_shutdown()
	await create_timer(0.6, true, false, true).timeout
	quit(exit_code)


func _test_runtime_prompt_persistence_and_legacy_migration() -> void:
	var provider := ScriptedProvider.new(true)
	var runtime := RuntimeScript.new(
		_initialization("resident-runtime", "林岚"),
		provider,
		_memory_root.path_join("runtime-source"),
		null,
		AVATAR_ID,
		"旅行者",
	)
	var decision_result := {}
	var started := runtime.call(
		"request_decision",
		_avatar_conversation_wake("runtime-avatar-talk"),
		func(result: Dictionary) -> void:
			decision_result.merge(result, true),
	) as Dictionary
	_expect_ok(started, "runtime starts decision with avatar evidence")
	_expect_ok(decision_result, "runtime completes ordinary and avatar organization")
	var avatar_debug := runtime.call(
		"get_avatar_memory_debug_snapshot",
	) as Dictionary
	_expect_equal(
		(
			avatar_debug.get("memory", {}) as Dictionary
		).get("summary"),
		"化身亲口说自己叫迪迦。",
		"avatar organization is stored separately",
	)
	var decision_request := _last_request_kind(
		provider.requests,
		"resident_decision",
	)
	var decision_messages := decision_request.get("messages", []) as Array
	_expect(
		JSON.stringify(decision_messages).contains("关于化身的个人记忆"),
		"resident decision receives a separate avatar-memory section",
	)
	var departure_result := {}
	_expect_ok(
		runtime.call(
			"request_departure_message",
			"runtime-departure",
			func(result: Dictionary) -> void:
				departure_result.merge(result, true),
		),
		"runtime starts departure message request",
	)
	_expect_ok(departure_result, "runtime accepts departure message")
	_expect_equal(departure_result.get("wrote"), true, "runtime proposes one message")
	var before_commit := runtime.call("capture_persistent_state") as Dictionary
	var before_commit_state := (
		before_commit.get("resident_state", {}) as Dictionary
	)
	var before_commit_avatar := (
		before_commit_state.get("avatar_memory_module", {}) as Dictionary
	)
	_expect_equal(
		(
			(
				before_commit_avatar.get("memory", {}) as Dictionary
			).get("sent_messages", []) as Array
		).size(),
		0,
		"runtime does not persist an unselected proposal",
	)
	_expect_ok(
		runtime.call(
			"commit_departure_message",
			"runtime-departure",
		),
		"runtime commits the selected proposal",
	)
	var capture := runtime.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "runtime captures both memory modules")
	var state := capture.get("resident_state", {}) as Dictionary
	_expect_equal(
		state.get("runtime_state_version"),
		6,
		"new resident state uses version 6",
	)
	_expect(
		state.has("avatar_memory_module"),
		"new resident state contains sibling avatar module",
	)

	var legacy := state.duplicate(true)
	legacy.erase("avatar_memory_module")
	legacy["runtime_state_version"] = 5
	var restored := RuntimeScript.new(
		_initialization("resident-runtime", "林岚"),
		ScriptedProvider.new(false),
		_memory_root.path_join("runtime-legacy-restored"),
		null,
		AVATAR_ID,
		"旅行者",
	)
	_expect_ok(
		restored.call("apply_persistent_state", legacy),
		"version 5 resident state migrates with an empty avatar module",
	)
	var migrated := restored.call("capture_persistent_state") as Dictionary
	var migrated_state := migrated.get("resident_state", {}) as Dictionary
	var migrated_avatar := (
		migrated_state.get("avatar_memory_module", {}) as Dictionary
	)
	_expect_equal(
		(
			migrated_avatar.get("memory", {}) as Dictionary
		).get("summary"),
		"",
		"legacy migration does not invent avatar memory",
	)


func _test_runtime_departure_forces_pending_avatar_organization() -> void:
	var provider := ScriptedProvider.new(true)
	var runtime := RuntimeScript.new(
		_initialization("resident-departure-organize", "闻叙"),
		provider,
		_memory_root.path_join("runtime-departure-organize"),
		null,
		AVATAR_ID,
		"旅行者",
	)
	var decision_result := {}
	_expect_ok(
		runtime.call(
			"request_decision",
			_active_departure_request_wake(),
			func(result: Dictionary) -> void:
				decision_result.merge(result, true),
		),
		"active avatar request starts a resident decision",
	)
	_expect_ok(decision_result, "active avatar request decision completes")
	_expect_equal(
		_last_request_kind(
			provider.requests,
			"avatar_memory_organization",
		).size(),
		0,
		"active conversation defers ordinary avatar organization",
	)
	var departure_result := {}
	_expect_ok(
		runtime.call(
			"request_departure_message",
			"forced-departure-organization",
			func(result: Dictionary) -> void:
				departure_result.merge(result, true),
		),
		"departure starts after forcing pending avatar organization",
	)
	_expect_ok(departure_result, "forced departure organization completes")
	_expect_equal(
		departure_result.get("wrote"),
		true,
		"resident can propose a message from the organized request",
	)
	var organization_request := _last_request_kind(
		provider.requests,
		"avatar_memory_organization",
	)
	var organization_text := JSON.stringify(organization_request)
	_expect(
		organization_text.contains("找到找不到都给我留个言"),
		"forced organization receives the avatar's explicit instruction",
	)
	_expect(
		not organization_text.contains("继续看面前的花苗"),
		"forced organization excludes resident-only scene narration",
	)
	var departure_request := _last_request_kind(
		provider.requests,
		"departure_message",
	)
	var departure_text := JSON.stringify(departure_request)
	_expect(
		departure_text.contains("找到找不到都给旅行者留言"),
		"departure judgment receives the organized open request",
	)
	_expect(
		not departure_text.contains("花苗"),
		"departure judgment cannot use resident-only flower narration",
	)


func _test_agent_system_departure_limit_and_idempotency() -> void:
	var save_store := SaveStoreScript.new()
	_expect_ok(
		save_store.call("configure_test_root", _save_root),
		"Agent save store uses isolated test root",
	)
	var system := AgentSystemScript.new(save_store)
	_expect_ok(
		system.call(
			"configure_test_runtime_storage",
			_memory_root.path_join("agent-system"),
		),
		"Agent runtime uses isolated test memory",
	)
	_expect_ok(
		system.call("configure_avatar_identity", AVATAR_ID, "旅行者"),
		"Agent system accepts stable avatar identity",
	)
	_expect_ok(
		system.call(
			"start_new_game",
			{
				"slot_id": "avatar-message-slot",
				"session_id": "avatar-message-session",
				"save_revision": 0,
			},
		),
		"Agent system starts test game",
	)
	var providers: Array[ScriptedProvider] = []
	for index in 4:
		var provider := ScriptedProvider.new(false, true)
		providers.append(provider)
		_expect_ok(
			system.call(
				"initialize_resident",
				_initialization("resident-%d" % index, "居民%d" % index),
				provider,
			),
			"Agent system initializes candidate %d" % index,
		)
	_expect_ok(system.call("finish_new_game"), "Agent system commits test game")
	for index in 4:
		var decision_result := {}
		_expect_ok(
			system.call(
				"request_decision",
				"resident-%d" % index,
				_avatar_conversation_wake("candidate-%d" % index),
				func(result: Dictionary) -> void:
					decision_result.merge(result, true),
			),
			"candidate %d receives avatar conversation" % index,
		)
		_expect_ok(
			decision_result,
			"candidate %d finishes avatar-memory decision" % index,
		)
	var departure_result := {}
	_expect_ok(
		system.call(
			"prepare_departure_messages",
			"agent-departure",
			2,
			func(result: Dictionary) -> void:
				departure_result.merge(result, true),
		),
		"Agent system starts bounded departure roll",
	)
	_expect_ok(
		departure_result,
		"model-timeout outcomes still complete the departure roll",
	)
	_expect_equal(
		(departure_result.get("candidate_ids", []) as Array).size(),
		2,
		"departure judgment is limited to two idle residents",
	)
	_expect_equal(
		(departure_result.get("messages", []) as Array).size(),
		0,
		"no-write outcomes produce no messages",
	)
	var calls_after_first := 0
	for provider in providers:
		calls_after_first += provider.departure_calls
	_expect_equal(calls_after_first, 2, "only two idle residents call the model")
	for provider in providers:
		provider.fail_departure = false
		provider.write_message = false
	var none_result := {}
	_expect_ok(
		system.call(
			"prepare_departure_messages",
			"agent-departure-none",
			2,
			func(result: Dictionary) -> void:
				none_result.merge(result, true),
		),
		"all residents can independently choose not to write",
	)
	_expect_ok(none_result, "valid no-write judgments complete")
	_expect_equal(
		(none_result.get("message_candidate_ids", []) as Array).size(),
		0,
		"zero write decisions keep zero messages",
	)
	var screened_result := {}
	_expect_ok(
		system.call(
			"prepare_departure_messages",
			"agent-departure-screened",
			2,
			func(result: Dictionary) -> void:
				screened_result.merge(result, true),
		),
		"screened residents can complete departure without model calls",
	)
	_expect_equal(
		(screened_result.get("candidate_ids", []) as Array).size(),
		2,
		"the bounded first pass leaves the other residents for a later pass",
	)
	_add_new_avatar_evidence(system, "before-one")
	providers[0].write_message = true
	var one_result := {}
	_expect_ok(
		system.call(
			"prepare_departure_messages",
			"agent-departure-one",
			2,
			func(result: Dictionary) -> void:
				one_result.merge(result, true),
		),
		"one resident can independently propose a message",
	)
	_expect_ok(one_result, "single message proposal completes")
	_expect_equal(
		(one_result.get("message_candidate_ids", []) as Array).size(),
		1,
		"one write decision becomes one candidate",
	)
	_expect_equal(
		(one_result.get("messages", []) as Array).size(),
		1,
		"one candidate is kept without random sampling",
	)
	_add_new_avatar_evidence(system, "before-two")
	providers[1].write_message = true
	var two_result := {}
	_expect_ok(
		system.call(
			"prepare_departure_messages",
			"agent-departure-two",
			2,
			func(result: Dictionary) -> void:
				two_result.merge(result, true),
		),
		"two residents can independently propose messages",
	)
	_expect_ok(two_result, "two message proposals complete")
	_expect_equal(
		(two_result.get("message_candidate_ids", []) as Array).size(),
		2,
		"two write decisions become two candidates",
	)
	_expect_equal(
		(two_result.get("messages", []) as Array).size(),
		2,
		"two candidates are both kept without random sampling",
	)
	_add_new_avatar_evidence(system, "before-written")
	for provider in providers:
		provider.write_message = true
	var written_result := {}
	_expect_ok(
		system.call(
			"prepare_departure_messages",
			"agent-departure-written",
			2,
			func(result: Dictionary) -> void:
				written_result.merge(result, true),
		),
		"all residents can independently propose a departure message",
	)
	_expect_ok(written_result, "written departure proposals complete")
	_expect_equal(
		(
			written_result.get("message_candidate_ids", []) as Array
		).size(),
		2,
		"two bounded write decisions become two message candidates",
	)
	_expect_equal(
		(written_result.get("messages", []) as Array).size(),
		2,
		"the bounded pass keeps its two prepared messages",
	)
	_expect_equal(
		(
			written_result.get("selected_message_ids", []) as Array
		).size(),
		2,
		"only the two selected proposals are committed",
	)
	var post_written_screened := {}
	_expect_ok(
		system.call(
			"prepare_departure_messages",
			"agent-departure-post-written",
			2,
			func(result: Dictionary) -> void:
				post_written_screened.merge(result, true),
		),
		"a later bounded pass can continue with the remaining residents",
	)
	_expect_equal(
		(
			post_written_screened.get("candidate_ids", []) as Array
		).size(),
		2,
		"the next bounded pass processes the remaining residents",
	)
	var repeated := {}
	_expect_ok(
		system.call(
			"prepare_departure_messages",
			"agent-departure",
			2,
			func(result: Dictionary) -> void:
				repeated.merge(result, true),
		),
		"same departure id reuses completed result",
	)
	var calls_after_repeat := 0
	for provider in providers:
		calls_after_repeat += provider.departure_calls
	_expect_equal(
		calls_after_repeat,
		14,
		"same departure id does not call residents again",
	)
	_expect_equal(repeated, departure_result, "idempotent result is stable")
	var sent_message_count := 0
	for index in 4:
		var debug_snapshot := system.call(
			"get_resident_debug_snapshot",
			"resident-%d" % index,
		) as Dictionary
		var avatar_memory := (
			debug_snapshot.get("avatar_memory", {}) as Dictionary
		)
		var stored_memory := (
			avatar_memory.get("memory", {}) as Dictionary
		)
		sent_message_count += (
			stored_memory.get("sent_messages", []) as Array
		).size()
	_expect_equal(
		sent_message_count,
		7,
		"bounded passes persist only the proposals selected in each pass",
	)
	system.call("close_game")


func _add_new_avatar_evidence(
	system: RefCounted,
	suffix: String,
) -> void:
	for index in 4:
		var decision_result := {}
		_expect_ok(
			system.call(
				"request_decision",
				"resident-%d" % index,
				_avatar_conversation_wake(
					"%s-%d" % [suffix, index],
				),
				func(result: Dictionary) -> void:
					decision_result.merge(result, true),
			),
			"candidate %d receives new avatar evidence %s" % [index, suffix],
		)
		_expect_ok(
			decision_result,
			"candidate %d stores new avatar evidence %s" % [index, suffix],
		)


func _avatar_conversation_wake(decision_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": {"day": 3, "clock": "19:20", "period": "傍晚"},
			"weather": "晴天",
			"me": {
				"doing": "站在广场",
				"current_action": null,
				"body": {"困": "不困", "饿": "不饿", "累": "不累"},
			},
			"nearby": [],
			"place": {"name": "中心广场", "props": []},
			"conversation": null,
		},
		"events": [{
			"event_id": "ended-%s" % decision_id,
			"time": {"day": 3, "clock": "19:20", "period": "傍晚"},
			"type": "对话结束",
			"conversation_id": "conversation-%s" % decision_id,
			"turns": [{
				"turn_id": 1,
				"speaker_resident_id": AVATAR_ID,
				"speaker": "旅行者",
				"say": "我叫迪迦。",
				"narration": "",
				"photos": [],
			}],
			"reason": "主动结束",
		}],
		"action_results": [],
	}


func _active_departure_request_wake() -> Dictionary:
	var wake := _avatar_conversation_wake("active-departure-request")
	var turns: Array[Dictionary] = [
		{
			"turn_id": 1,
			"speaker_resident_id": AVATAR_ID,
			"speaker": "旅行者",
			"say": "你帮我找迪迦，找到找不到都给我留个言。",
			"narration": "旅行者认真交代这件事",
			"photos": [],
		},
		{
			"turn_id": 2,
			"speaker_resident_id": "resident-departure-organize",
			"speaker": "闻叙",
			"say": "我知道了。",
			"narration": "我转头继续看面前的花苗",
			"photos": [],
		},
	]
	(wake["snapshot"] as Dictionary)["conversation"] = {
		"conversation_id": "conversation-active-departure-request",
		"with_resident_id": AVATAR_ID,
		"with": "旅行者",
		"turns": turns,
	}
	wake["events"] = [{
		"event_id": "active-departure-request-turn-2",
		"time": {"day": 3, "clock": "19:20", "period": "傍晚"},
		"type": "对方答话",
		"conversation_id": "conversation-active-departure-request",
		"turn": turns.back().duplicate(true),
	}]
	return wake


func _initialization(resident_id: String, resident_name: String) -> Dictionary:
	return {
		"me": {
			"resident_id": resident_id,
			"attributes": {
				"name": resident_name,
				"gender": "男",
				"age": 30,
				"desire": "过好自己的生活",
				"personality": "认真",
				"speech": "说话简短",
			},
			"social_state": {
				"home": "%s家" % resident_name,
				"job": "居民",
				"workplace": "中心广场",
			},
		},
		"residents": [],
		"places": [{
			"name": "中心广场",
			"type": "公共地点",
			"owner": null,
			"owner_resident_id": null,
			"summary": "镇中心",
			"features": [],
		}],
	}


func _last_request_kind(
	requests: Array[Dictionary],
	kind: String,
) -> Dictionary:
	for index in range(requests.size() - 1, -1, -1):
		if String(requests[index].get("request_kind", "")) == kind:
			return requests[index]
	return {}


func _expect_ok(result: Variant, message: String) -> void:
	if not result is Dictionary or not bool((result as Dictionary).get("ok", false)):
		_failures.append("%s: %s" % [message, result])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s: expected %s, got %s" % [message, expected, actual],
		)
