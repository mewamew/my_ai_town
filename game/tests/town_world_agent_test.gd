extends "res://tests/support/TownWorldTestCase.gd"
## Agent 接入与契约 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - town_world_agent_gateway_continuity_test.gd
## - agent_environment_fact_contract_test.gd
## - town_world_agent_long_run_test.gd
## - town_world_agent_activity_action_test.gd
## - agent_activity_reaction_contract_test.gd
## - town_world_pause_agent_submission_test.gd

class DelayedFailingAgent:
	extends RefCounted

	var callbacks: Dictionary = {}
	var requested_resident_ids: Array[String] = []

	func request_decision(
		resident_id: String,
		wake: Dictionary,
		completion: Callable,
	) -> Dictionary:
		requested_resident_ids.append(resident_id)
		callbacks[String(wake.get("decision_id", ""))] = completion
		return {"ok": true}

	func fail(decision_id: String) -> void:
		var callback := callbacks.get(decision_id, Callable()) as Callable
		callbacks.erase(decision_id)
		if callback.is_valid():
			callback.call({"ok": false, "errors": ["invalid model decision"]})
class ImmediatelyRejectingAgent:
	extends RefCounted

	func request_decision(
		_resident_id: String,
		_wake: Dictionary,
		_completion: Callable,
	) -> Dictionary:
		return {
			"ok": false,
			"retryable": false,
			"errors": ["wake rejected"],
			}
class ImmediateDecisionAgent:
	extends RefCounted

	var discarded_decisions: Array[Dictionary] = []

	func request_decision(
		_resident_id: String,
		wake: Dictionary,
		completion: Callable,
	) -> Dictionary:
		var decision_id := String(wake.get("decision_id", ""))
		completion.call({
			"ok": true,
			"decision": {
				"decision_id": decision_id,
				"handling": "replace_current",
				"action": {
					"action_id": "%s-action" % decision_id,
					"type": "待着",
					"line": "等世界恢复。",
				},
			},
			"socialResponseErrors": ["测试诊断"],
		})
		return {"ok": true}

	func discard_unconfirmed_decision(
		_resident_id: String,
		decision: Dictionary,
	) -> Dictionary:
		discarded_decisions.append(decision.duplicate(true))
		return {"ok": true, "changed": true}
class ProviderServiceStub:
	extends RefCounted

	func create_provider_for_resident(_binding: Dictionary) -> Dictionary:
		return {"ok": true, "provider": null}

	func get_latest_diagnostic(_resident_id: String) -> Dictionary:
		# 合同拒绝发生在 Provider 已成功返回之后；此时生产 Provider 的
		# 最新诊断没有传输错误类型，Gateway 会归一为 agent_runtime。
		return {}
class DiscardAgent:
	extends RefCounted

	var close_calls := 0
	var delete_calls := 0
	var delete_ok := true

	func close_game() -> Dictionary:
		close_calls += 1
		return {"ok": true}

	func delete_game(_context: Dictionary) -> Dictionary:
		delete_calls += 1
		return (
			{"ok": true}
			if delete_ok
			else {"ok": false, "errors": ["delete rejected"]}
		)
class DiscardPhotoStore:
	extends RefCounted

	var discard_ok := true
	var discarded := false
	var restore_flags: Array[bool] = []

	func configure_session(_slot_id: String, _session_id: String) -> Dictionary:
		return {"ok": true, "errorCode": ""}

	func discard_unpublished_session(restore_blocker := false) -> Dictionary:
		restore_flags.append(restore_blocker)
		if not discard_ok:
			return {
				"ok": false,
				"errorCode": "PHOTO_STORAGE_SLOT_BUSY",
				"retryable": true,
			}
		var changed := not discarded
		discarded = true
		return {
			"ok": true,
			"errorCode": "",
			"changed": changed,
		}

	func clear() -> void:
		pass
class PendingWorld:
	extends RefCounted

	var pending: Array[Dictionary] = []
	var all_requests: Dictionary = {}
	var submissions: Array[Dictionary] = []
	var redispatched: Array[String] = []

	func add_request(request: Dictionary) -> void:
		var copy := request.duplicate(true)
		var decision_id := String(
			(copy.get("wakePacket", {}) as Dictionary).get("decision_id", "")
		)
		all_requests[decision_id] = copy
		pending.append(copy)

	func take_pending_decision_requests_by_ids(
		resident_ids: Array,
	) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		var kept: Array[Dictionary] = []
		for request in pending:
			if resident_ids.has(String(request.get("residentId", ""))):
				result.append(request.duplicate(true))
			else:
				kept.append(request)
		pending = kept
		return result

	func redispatch_decision_request_by_id(
		_resident_id: String,
		decision_id: String,
	) -> bool:
		redispatched.append(decision_id)
		for request in pending:
			if (
				String(
					(request.get("wakePacket", {}) as Dictionary).get(
						"decision_id",
						"",
					)
				)
				== decision_id
			):
				return true
		if all_requests.has(decision_id):
			pending.append((all_requests[decision_id] as Dictionary).duplicate(true))
			return true
		return false

	func submit_agent_decision_by_id(
		resident_id: String,
		decision: Dictionary,
	) -> Dictionary:
		submissions.append({
			"residentId": resident_id,
			"decision": decision.duplicate(true),
		})
		return {
			"ok": true,
			"stale": false,
			"errorCode": "",
			"worldRevision": submissions.size(),
		}
class PausedSubmissionWorld:
	extends RefCounted

	var terminal_calls := 0
	var redispatched: Array[String] = []

	func submit_agent_decision_by_id(
		_resident_id: String,
		_decision: Dictionary,
	) -> Dictionary:
		return {
			"ok": false,
			"stale": false,
			"errorCode": "WORLD_PAUSED",
			"retryable": true,
		}

	func mark_social_candidate_terminal(
		_matter_id: String,
		_resident_id: String,
		_reason: String,
		_expected_round_id: String = "",
	) -> Dictionary:
		terminal_calls += 1
		return {"ok": true}

	func redispatch_decision_request_by_id(
		_resident_id: String,
		decision_id: String,
	) -> bool:
		redispatched.append(decision_id)
		return true
class ConsumedRejectionWorld:
	extends RefCounted

	var submissions := 0

	func submit_agent_decision_by_id(
		_resident_id: String,
		_decision: Dictionary,
	) -> Dictionary:
		submissions += 1
		return {
			"ok": false,
			"stale": false,
			"errorCode": "TALK_TARGET_NOT_NEARBY",
			"retryable": false,
			"decisionConsumed": true,
		}
class InnerObservationWorld:
	extends RefCounted

	func get_world_revision() -> int:
		return 12

	func get_resident_state(_resident_id: String) -> Dictionary:
		return {"doing": "观察花圃"}
class InnerObservationAgent:
	extends RefCounted

	var current_thought := "想看看花圃今天有没有新芽。"

	func get_resident_memory(_resident_id: String) -> Dictionary:
		return {
			"ok": true,
			"memory": {
				"current_inner_thought": current_thought,
				"current_focus": current_thought,
				"next_plan": current_thought,
				"current_judgment": current_thought,
				"memory_certainties": [current_thought],
				"memory_doubts": [],
				"memory_contradictions": [],
				"public_basis": ["想看看花圃今天有没有新芽。"],
			},
		}

class DeathStoryWorld:
	extends RefCounted

	func get_resident_state(_resident_id: String) -> Dictionary:
		return {
			"currentPlace": "咖啡馆",
			"doing": "擦拭一只旧杯子",
			"lifecycle": {"isDead": false},
		}

	func get_time() -> Dictionary:
		return {"day": 4, "period": "night", "time24h": "22:10"}

	func get_weather() -> String:
		return "雷暴"


class DeathStoryAgent:
	extends RefCounted

	var latest_request: Dictionary = {}

	func request_json_for_resident(
		_resident_id: String,
		model_request: Dictionary,
		on_complete: Callable,
	) -> Dictionary:
		latest_request = model_request.duplicate(true)
		on_complete.call({
			"ok": true,
			"json": {
				"story": "雷声落下时，杯中映出的影子先一步熄灭，他随后在无人经过的门后消失。",
			},
		})
		return {"ok": true}


class DeathStoryResultCollector:
	extends RefCounted

	var result: Dictionary = {}

	func collect(value: Dictionary) -> void:
		result = value.duplicate(true)
class MemoryInterventionWorld:
	extends RefCounted

	func get_time() -> Dictionary:
		return {"day": 3, "period": "afternoon", "time24h": "15:20"}
class MemoryInterventionAgent:
	extends RefCounted

	var latest_request: Dictionary = {}

	func apply_resident_memory_intervention(
		_resident_id: String,
		request: Dictionary,
	) -> Dictionary:
		latest_request = request.duplicate(true)
		return {"ok": true, "revision": 8}
class LongRunWaitModelProvider:
	extends "res://agent/model/FakeModelProvider.gd"

	func _build_default_decision(model_request: Dictionary) -> Dictionary:
		var result := super._build_default_decision(model_request)
		var action := result.get("action", {}) as Dictionary
		if String(action.get("type", "")) == "答话":
			return result
		var wake := model_request.get("wake_packet", {}) as Dictionary
		result["action"] = {
			"action_id": _next_default_action_id(
				String(wake.get("decision_id", "fake-decision")),
				wake,
			),
			"type": "待着",
			"line": "先看看周围的情况",
		}
		return result
class FakeProviderService:
	extends RefCounted

	var providers: Dictionary = {}
	var fail_first_resident_id := ""

	func create_provider_for_resident(binding: Dictionary) -> Dictionary:
		var resident_id := String(binding.get("residentId", ""))
		var provider: RefCounted = (
			FailFirstModelProvider.new()
			if resident_id == fail_first_resident_id
			else LongRunWaitModelProvider.new()
		)
		providers[resident_id] = provider
		return {"ok": true, "provider": provider}

	func get_latest_diagnostic(_resident_id: String) -> Dictionary:
		return {}
class FailFirstModelProvider:
	extends RefCounted

	var _delegate: RefCounted = LongRunWaitModelProvider.new()
	var _requests: Array[Dictionary] = []
	var _failed_attempts := 0

	func request_decision(request: Dictionary, callback: Callable) -> void:
		_requests.append(request.duplicate(true))
		if (
			_failed_attempts < 2
			and String(request.get("request_kind", "")) == "resident_decision"
		):
			_failed_attempts += 1
			var wake_packet := request.get("wake_packet", {}) as Dictionary
			callback.call({
				"ok": true,
				"decision": {
					"decision_id": String(wake_packet.get("decision_id", "")),
					"handling": "replace_current",
					"action": {
						"type": "待着",
						"line": "故意缺少动作编号",
					},
				},
			})
			return
		_delegate.call("request_decision", request, callback)

	func get_requests() -> Array[Dictionary]:
		return _requests.duplicate(true)

const GATEWAY := preload(
	"res://world/integration/TownWorldAgentGateway.gd"
)
const CONTRACT := preload("res://agent/AgentContract.gd")
const COMPILER := preload("res://agent/prompt/AgentPromptCompiler.gd")
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const ANNOUNCEMENT_TIME_PARSER := preload(
	"res://world/runtime/social/TownAnnouncementTimeParser.gd"
)
const AGENT_SYSTEM := preload("res://agent/AgentSystem.gd")
const FAKE_MODEL := preload("res://agent/model/FakeModelProvider.gd")
const GATEWAY_AGENT_LONG_RUN := preload("res://world/integration/TownWorldAgentGateway.gd")
const WORLD_RUNTIME := preload("res://world/runtime/TownWorldRuntime.gd")
const RESIDENT_STATE_PROJECTION := preload(
	"res://world/runtime/presentation/TownResidentStateProjection.gd"
)
const FORMAL_OPENING := preload(
	"res://tests/support/TownWorldFormalOpeningTestHelper.gd",
)
const UserTestDataCleanerScript := preload(
	"res://tests/support/UserTestDataCleaner.gd",
)
const CYCLES := 12
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const RESIDENT_NAME := "叶澄"
const ACTIVITY_ID := "activity_fisher_organize_gear"
const SCENARIOS := preload("res://agent/debug/AgentDebugScenarios.gd")
const WORLD_DATA_PATH := "res://world/data/town/town_world.json"
const RESIDENT_ID := "resident_lin_lan_01"

var _test_root := "user://tests/town-world-agent-long-run/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_scenario_agent_gateway_continuity()
	_scenario_agent_environment_fact_contract()
	_scenario_agent_long_run()
	_scenario_agent_activity_action()
	_scenario_agent_activity_reaction_contract()
	_scenario_announcement_time_parser()
	_scenario_pause_agent_submission()
	_finish_suite("TOWN_WORLD_AGENT_PASS")



func _finalize() -> void:
	_finalize_agent_long_run()

func _scenario_agent_gateway_continuity() -> void:
	_test_null_conversation_snapshot_is_not_an_avatar_turn()
	_test_duplicate_display_names_route_by_id()
	_test_death_story_uses_resident_agent_json()
	_test_inner_observation_accepts_newer_read_only_world_revision()
	_test_memory_intervention_uses_world_time_and_agent_contract()
	_test_replacement_request_retires_old_gateway_slot()
	_test_full_queue_only_dispatches_request_that_frees_slot()
	_test_unconsumed_submission_rolls_back_without_social_side_effect()
	_test_consumed_world_rejection_is_not_a_gateway_failure()
	_test_unconsumed_fallback_keeps_social_candidate_open()
	_test_failed_first_pair_cannot_starve_the_town()
	_test_local_model_queue_preserves_town_and_avatar_lane()
	_test_conversation_turn_preempts_ordinary_life_requests()
	_test_conversation_lane_stays_available_during_ordinary_work()
	_test_immediate_agent_rejection_cannot_loop_forever()
	_test_failed_decision_uses_available_world_prop()
	_test_failed_decision_uses_available_world_activity()
	_test_continuity_action_is_replaced_by_available_world_prop()
	_test_failed_required_reply_ends_conversation_after_one_retry()
	_test_unpublished_new_game_discard_lifecycle()


func _test_death_story_uses_resident_agent_json() -> void:
	var gateway: Node = GATEWAY.new()
	var agent := DeathStoryAgent.new()
	var world := DeathStoryWorld.new()
	var collector := DeathStoryResultCollector.new()
	gateway.set("_agent_system", agent)
	gateway.set("_world", world)
	gateway.set("_session_active", true)
	var connected_resident_ids: Array[String] = ["resident-a"]
	gateway.set("_connected_resident_ids", connected_resident_ids)
	gateway.set("_resident_name_by_id", {"resident-a": "居民甲"})
	var accepted := gateway.call(
		"request_resident_death_story",
		"resident-a",
		"death-story-test-1",
		Callable(collector, "collect"),
	) as Dictionary
	_expect_ok(accepted, "死亡故事请求应交给对应居民 Agent")
	_expect_ok(collector.result, "居民 Agent 应返回完整死亡故事")
	_expect_equal(
		String(collector.result.get("generatedBy", "")),
		"resident_agent",
		"死亡故事应标记为居民 Agent 生成",
	)
	_expect(
		not String(collector.result.get("story", "")).contains("..."),
		"死亡故事不能带未完成省略号",
	)
	_expect_equal(
		String(gateway.call(
			"_normalize_death_story_result",
			{
				"ok": true,
				"json": {"story": "花子走了，我在..."},
			},
		)),
		"",
		"网关应拒绝带省略号的残缺死亡故事",
	)
	var messages := agent.latest_request.get("messages", []) as Array
	var user_message := String((messages[1] as Dictionary).get("content", ""))
	_expect(user_message.contains("咖啡馆"), "死亡故事请求应包含现场地点")
	_expect(user_message.contains("雷暴"), "死亡故事请求应包含当前天气")
	gateway.free()

func _test_null_conversation_snapshot_is_not_an_avatar_turn() -> void:
	var gateway: Node = GATEWAY.new()
	gateway.set("_avatar_person_id", "player_avatar")
	var wake := _wake("decision-null-conversation")
	wake["events"] = [{
		"event_id": "conversation-event-with-cleared-snapshot",
		"type": "对方答话",
	}]
	_expect_equal(
		gateway.call("_wake_is_avatar_conversation_turn", wake),
		false,
		"a cleared conversation snapshot cannot crash or claim the avatar lane",
	)
	gateway.free()



func _test_replacement_request_retires_old_gateway_slot() -> void:
	var agent := DelayedFailingAgent.new()
	var world := PendingWorld.new()
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	var connected_resident_ids: Array[String] = ["resident-a"]
	gateway.set("_connected_resident_ids", connected_resident_ids)
	gateway.set("_session_active", true)
	world.add_request({
		"residentId": "resident-a",
		"residentName": "居民甲",
		"wakePacket": {"decision_id": "decision-old"},
	})
	_expect_equal(gateway.call("pump"), 1, "old request occupies one gateway slot")
	world.add_request({
		"residentId": "resident-a",
		"residentName": "居民甲",
		"wakePacket": {"decision_id": "decision-current"},
	})
	_expect_equal(
		gateway.call("pump", 0),
		0,
		"a deferred replacement does not retire the request still reaching Agent",
	)
	_expect(
		(gateway.get("_inflight") as Dictionary).has("decision-old"),
		"old slot remains owned until the replacement actually dispatches",
	)
	_expect_equal(
		gateway.call("pump"),
		1,
		"replacement request dispatches when one real model slot remains",
	)
	var inflight := gateway.get("_inflight") as Dictionary
	_expect_equal(
		inflight.size(),
		2,
		"old and replacement requests both count until the old model call ends",
	)
	_expect(
		inflight.has("decision-current"),
		"replacement request owns its real model slot",
	)
	_expect(
		bool(
			(inflight.get("decision-old", {}) as Dictionary).get(
				"superseded",
				false,
			)
		),
		"old request is marked stale without hiding its real resource usage",
	)
	agent.fail("decision-old")
	_expect_equal(
		gateway.call("get_debug_inflight_count"),
		1,
		"old completion releases only its own real slot",
	)
	gateway.free()



func _test_full_queue_only_dispatches_request_that_frees_slot() -> void:
	var agent := DelayedFailingAgent.new()
	var world := PendingWorld.new()
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	var connected_resident_ids: Array[String] = [
		"resident-new",
		"resident-a",
	]
	gateway.set("_connected_resident_ids", connected_resident_ids)
	gateway.set("_session_active", true)
	var inflight := {}
	for index in 6:
		var resident_id := (
			"resident-a"
			if index == 0
			else "resident-busy-%d" % index
		)
		var decision_id := "decision-busy-%d" % index
		inflight[decision_id] = {
			"residentId": resident_id,
			"residentName": resident_id,
			"wakePacket": {
				"decision_id": decision_id,
				"events": [{"type": "搭话"}],
			},
		}
	gateway.set("_inflight", inflight)
	world.add_request({
		"residentId": "resident-new",
		"residentName": "新居民",
		"wakePacket": {
			"decision_id": "decision-new",
			"events": [{"type": "搭话"}],
		},
	})
	world.add_request({
		"residentId": "resident-a",
		"residentName": "居民甲",
		"wakePacket": {
			"decision_id": "decision-current",
			"events": [{"type": "搭话"}],
		},
	})
	_expect_equal(
		gateway.call("pump"),
		0,
		"a full queue waits because replacing bookkeeping cannot cancel a real call",
	)
	inflight = gateway.get("_inflight") as Dictionary
	_expect_equal(inflight.size(), 6, "the real model request cap remains exact")
	_expect(
		not inflight.has("decision-current"),
		"replacement waits until the old call actually finishes",
	)
	_expect(
		not inflight.has("decision-new"),
		"a new resident cannot borrow replacement capacity from another request",
	)
	_expect(
		world.redispatched.has("decision-new"),
		"the new request remains pending for a real free slot",
	)
	_expect(
		world.redispatched.has("decision-current"),
		"the replacement also remains pending for a real free slot",
	)
	gateway.free()



func _test_unconsumed_submission_rolls_back_without_social_side_effect() -> void:
	var agent := ImmediateDecisionAgent.new()
	var world := PausedSubmissionWorld.new()
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_session_active", true)
	var connected_resident_ids: Array[String] = ["resident-a"]
	gateway.set("_connected_resident_ids", connected_resident_ids)
	gateway.call("_request_agent_decision", {
		"residentId": "resident-a",
		"residentName": "居民甲",
		"wakePacket": {
			"decision_id": "decision-paused",
			"snapshot": {
				"social_matters": [{
					"matter_id": "matter-a",
					"response_round_id": "matter-a-r1",
					"options": [{"option_id": "accept"}],
				}],
			},
		},
	})
	_expect_equal(
		agent.discarded_decisions.size(),
		1,
		"World-paused submission rolls back the Agent pending intention",
	)
	_expect_equal(
		world.terminal_calls,
		0,
		"unconsumed decision cannot terminate a social candidate",
	)
	_expect_equal(
		gateway.call("get_debug_inflight_count"),
		0,
		"paused submission still releases its gateway slot",
	)
	gateway.free()



func _test_consumed_world_rejection_is_not_a_gateway_failure() -> void:
	var agent := ImmediateDecisionAgent.new()
	var world := ConsumedRejectionWorld.new()
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_session_active", true)
	var connected_resident_ids: Array[String] = ["resident-a"]
	gateway.set("_connected_resident_ids", connected_resident_ids)
	gateway.call("_request_agent_decision", {
		"residentId": "resident-a",
		"residentName": "居民甲",
		"wakePacket": {
			"decision_id": "decision-target-moved",
			"snapshot": {},
		},
	})
	_expect_equal(
		world.submissions,
		1,
		"a decision whose nearby target moved is still consumed by World",
	)
	_expect_equal(
		(gateway.call("get_errors") as Array).size(),
		0,
		"a consumed stale-fact rejection is not reported as a Gateway failure",
	)
	_expect_equal(
		agent.discarded_decisions.size(),
		0,
		"a consumed rejection keeps its Agent intention until the queued World result is ingested",
	)
	gateway.free()



func _test_unconsumed_fallback_keeps_social_candidate_open() -> void:
	var world := PausedSubmissionWorld.new()
	var gateway: Node = GATEWAY.new()
	gateway.set("_world", world)
	gateway.set("_session_active", true)
	gateway.call(
		"_submit_continuity_fallback",
		"resident-a",
		"居民甲",
		"decision-fallback-paused",
		{
			"decision_id": "decision-fallback-paused",
			"snapshot": {
				"me": {"current_action": null},
				"social_matters": [{
					"matter_id": "matter-fallback",
					"response_round_id": "matter-fallback-r1",
					"options": [{"option_id": "accept"}],
				}],
			},
			"events": [],
		},
		"AGENT_RESPONSE_TIMEOUT",
	)
	_expect_equal(
		world.terminal_calls,
		0,
		"a fallback rejected by World cannot terminate a social candidate",
	)
	_expect_equal(
		world.redispatched,
		["decision-fallback-paused"],
		"an unconsumed fallback is returned to the World request queue",
	)
	var recent_errors := gateway.call("get_errors") as Array
	_expect(
		not recent_errors.is_empty()
		and String(
			(recent_errors.back() as Dictionary).get("errorCode", ""),
		) == "AGENT_CONTINUITY_FALLBACK_DEFERRED",
		"an unconsumed fallback is reported as deferred rather than applied",
	)
	gateway.free()



func _test_inner_observation_accepts_newer_read_only_world_revision() -> void:
	var gateway: Node = GATEWAY.new()
	gateway.set("_world", InnerObservationWorld.new())
	var agent := InnerObservationAgent.new()
	gateway.set("_agent_system", agent)
	gateway.set("_session_active", true)
	gateway.set("_resident_name_by_id", {"resident-a": "林岚"})
	var snapshot := gateway.call(
		"_public_inner_observation_snapshot",
		"resident-a",
		11,
	) as Dictionary
	_expect(
		not snapshot.is_empty(),
		"a newer read-only World revision does not intermittently block the inner page",
	)
	_expect_equal(
		snapshot.get("confirmedWorldRevision"),
		12,
		"inner observation reports the revision it actually read",
	)
	_expect_equal(
		snapshot.get("currentThought"),
		"想看看花圃今天有没有新芽。",
		"inner observation keeps the resident's strict current thought",
	)
	var ready := gateway.call(
		"_inner_observation_ready_result",
		snapshot,
		"inner-dedup-test",
	) as Dictionary
	var content := ready.get("content", {}) as Dictionary
	_expect_equal(
		content.get("monologueText"),
		"想看看花圃今天有没有新芽。",
		"inner observation presents natural prose without report labels",
	)
	_expect_equal(
		content.get("reasonText"),
		"",
		"duplicated public basis is omitted instead of echoing the monologue",
	)
	var natural_ready := gateway.call(
		"_inner_observation_ready_result",
		{
			"residentId": "resident-a",
			"currentThought": "集市那边出了点事，我还是有些放心不下。",
			"nextPlan": "等把手上的活做完，我想过去看看。",
			"reasonBasis": ["旅行者刚刚说集市出了问题。"],
		},
		"inner-natural-test",
	) as Dictionary
	var natural_content := natural_ready.get("content", {}) as Dictionary
	_expect_equal(
		natural_content.get("monologueText"),
		"集市那边出了点事，我还是有些放心不下。\n\n等把手上的活做完，我想过去看看。",
		"current thought and next plan read as one natural monologue",
	)
	_expect_equal(
		natural_content.get("reasonText"),
		"旅行者刚刚说集市出了问题。",
		"only one distinct current reason is shown",
	)
	_expect_equal(natural_content.get("playerStatusText"), "", "ready content does not show a system completion message")
	var unrelated_ready := gateway.call(
		"_inner_observation_ready_result",
		{
			"residentId": "resident-a",
			"currentThought": "想看看花圃今天有没有新芽。",
			"nextPlan": "",
			"reasonBasis": ["昨天集市的木架已经修好了。"],
		},
		"inner-unrelated-reason-test",
	) as Dictionary
	_expect_equal(
		(unrelated_ready.get("content", {}) as Dictionary).get("reasonText"),
		"",
		"an unrelated recent memory is not presented as the thought's reason",
	)
	_expect_equal(
		gateway.call(
			"_inner_observation_complete_excerpt",
			"第一句话。第二句话。第三句话。",
			10,
		),
		"第一句话。第二句话。",
		"long inner text is shortened only at a complete sentence boundary",
	)
	var focus_720 := "想".repeat(720)
	var focus_721 := "想".repeat(721)
	var focus_1000 := "想".repeat(1000)
	_expect_equal(
		gateway.call("_inner_observation_player_text", focus_720, 1000),
		focus_720,
		"a current thought at the old hard limit remains visible",
	)
	_expect_equal(
		gateway.call("_inner_observation_player_text", focus_721, 1000),
		focus_721,
		"a current thought just above the old limit is not silently dropped",
	)
	_expect_equal(
		gateway.call("_inner_observation_player_text", focus_1000, 1000),
		focus_1000,
		"the full projected current-thought limit remains visible",
	)
	for focus_limit: int in [720, 721, 1000]:
		var expected_focus := "想".repeat(focus_limit)
		agent.current_thought = expected_focus
		var production_snapshot := gateway.call(
			"_public_inner_observation_snapshot",
			"resident-a",
			11,
		) as Dictionary
		_expect_equal(
			production_snapshot.get("currentThought"),
			expected_focus,
			"the production inner-observation path preserves %d characters" % focus_limit,
		)
	agent.current_thought = "想看看花圃今天有没有新芽。"
	var bounded_single_sentence := gateway.call(
		"_inner_observation_complete_excerpt",
		"想".repeat(300),
		220,
	) as String
	_expect_equal(
		bounded_single_sentence.length(),
		220,
		"a long single sentence is bounded for the fixed observation panel",
	)
	_expect(
		bounded_single_sentence.ends_with("…"),
		"a bounded single sentence tells the player that it continues",
	)
	var empty_ready := gateway.call(
		"_inner_observation_ready_result",
		{
			"residentId": "resident-a",
			"currentThought": "",
			"nextPlan": "",
			"reasonBasis": ["花圃里曾经有一件重要的事。"],
		},
		"inner-empty-test",
	) as Dictionary
	var empty_content := empty_ready.get("content", {}) as Dictionary
	_expect_equal(empty_content.get("empty"), true, "inner observation preserves a real empty state")
	_expect_equal(empty_content.get("monologueText"), "", "old memories never impersonate a current thought")
	_expect_equal(empty_content.get("reasonText"), "", "an empty thought does not show an unrelated historical reason")
	gateway.free()



func _test_memory_intervention_uses_world_time_and_agent_contract() -> void:
	var gateway: Node = GATEWAY.new()
	var world := MemoryInterventionWorld.new()
	var agent := MemoryInterventionAgent.new()
	gateway.set("_session_active", true)
	gateway.set("_world", world)
	gateway.set("_agent_system", agent)
	var resident_ids: Array[String] = ["resident-a"]
	gateway.set("_connected_resident_ids", resident_ids)
	var result := gateway.call(
		"apply_resident_memory_intervention",
		"resident-a",
		{
			"memoryKey": "memory-1",
			"operation": "edit",
			"playerText": "我记得那天并没有下雨。",
			"expectedRevision": 7,
		},
	) as Dictionary
	_expect(bool(result.get("ok", false)), "gateway accepts a valid memory edit")
	_expect_equal(result.get("revision"), 8, "gateway returns the new memory revision")
	_expect_equal(
		agent.latest_request.get("world_time"),
		{"day": 3, "period": "afternoon", "time24h": "15:20"},
		"gateway uses authoritative World time for the intervention",
	)
	_expect_equal(
		agent.latest_request.get("operation"),
		"edit",
		"gateway preserves the player-facing operation",
	)
	gateway.free()



func _test_duplicate_display_names_route_by_id() -> void:
	var gateway: Node = GATEWAY.new()
	var normalized := gateway.call("_normalize_identities", [
		{"residentId": "resident-a", "residentName": "小林"},
		{"residentId": "resident-b", "residentName": "小林"},
	]) as Dictionary
	_expect_equal(
		normalized.get("ok"),
		true,
		"Gateway preserves Aya's stable-ID authority when display names repeat",
	)
	gateway.free()



func _test_immediate_agent_rejection_cannot_loop_forever() -> void:
	var world := PendingWorld.new()
	world.add_request(_request("resident-a", "decision-rejected"))
	var resident_ids: Array[String] = ["resident-a"]
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", ImmediatelyRejectingAgent.new())
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", resident_ids)
	gateway.set("_session_active", true)
	_expect_equal(gateway.call("pump"), 1, "immediate rejection consumes one request")
	_expect_equal(
		world.submissions.size(),
		1,
		"non-retryable Agent admission failure receives a continuity decision",
	)
	_expect_equal(
		world.pending.size(),
		0,
		"non-retryable admission failure is not redispatched forever",
	)
	gateway.free()



func _test_failed_decision_uses_available_world_prop() -> void:
	var world := PendingWorld.new()
	var request := _request("resident-a", "decision-prop")
	var wake := request.get("wakePacket", {}) as Dictionary
	wake["snapshot"]["place"] = {
		"name": "工作坊",
		"props": [{
			"name": "空闲木料架",
			"verbs": ["整理木料"],
		}],
	}
	world.add_request(request)
	var resident_ids: Array[String] = ["resident-a"]
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", ImmediatelyRejectingAgent.new())
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", resident_ids)
	gateway.set("_session_active", true)

	_expect_equal(gateway.call("pump"), 1, "failed work decision reaches continuity")
	_expect_equal(world.submissions.size(), 1, "continuity submits one safe action")
	if world.submissions.size() == 1:
		var decision := (
			(world.submissions[0] as Dictionary).get("decision", {}) as Dictionary
		)
		var action := decision.get("action", {}) as Dictionary
		_expect_equal(action.get("type"), "用道具", "continuity uses a World-visible alternative")
		_expect_equal(action.get("prop"), "空闲木料架", "continuity keeps the available prop")
		_expect_equal(action.get("verb"), "整理木料", "continuity keeps the available verb")
	gateway.free()



func _test_failed_decision_uses_available_world_activity() -> void:
	var world := PendingWorld.new()
	var request := _request("resident-a", "decision-activity")
	var wake := request.get("wakePacket", {}) as Dictionary
	wake["snapshot"]["place"] = {
		"name": "社区花园",
		"props": [],
		"activities": [{
			"activity_id": "activity_garden_bench_rest",
			"label": "在花园长椅歇一会儿",
		}],
	}
	world.add_request(request)
	var resident_ids: Array[String] = ["resident-a"]
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", ImmediatelyRejectingAgent.new())
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", resident_ids)
	gateway.set("_session_active", true)

	_expect_equal(gateway.call("pump"), 1, "failed decision reaches continuity activity")
	var decision := (
		(world.submissions[0] as Dictionary).get("decision", {}) as Dictionary
	)
	var action := decision.get("action", {}) as Dictionary
	_expect_equal(action.get("type"), "做活动", "continuity uses a formal activity")
	_expect_equal(
		action.get("activity_id"),
		"activity_garden_bench_rest",
		"continuity keeps the available activity id",
	)
	gateway.free()



func _test_continuity_action_is_replaced_by_available_world_prop() -> void:
	var world := PendingWorld.new()
	var request := _request("resident-a", "decision-recover")
	var wake := request.get("wakePacket", {}) as Dictionary
	wake["snapshot"]["me"]["current_action"] = {
		"action_id": "previous-decision-continuity",
		"type": "待着",
	}
	wake["snapshot"]["place"] = {
		"name": "工作坊",
		"props": [{
			"name": "空闲成品架",
			"verbs": ["查看成品"],
		}],
	}
	world.add_request(request)
	var resident_ids: Array[String] = ["resident-a"]
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", ImmediatelyRejectingAgent.new())
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", resident_ids)
	gateway.set("_session_active", true)

	_expect_equal(gateway.call("pump"), 1, "repeated continuity reaches recovery")
	var decision := (
		(world.submissions[0] as Dictionary).get("decision", {}) as Dictionary
	)
	_expect_equal(
		decision.get("handling"),
		"replace_current",
		"old continuity wait is not prolonged when a real alternative exists",
	)
	_expect_equal(
		(decision.get("action", {}) as Dictionary).get("prop"),
		"空闲成品架",
		"recovery leaves the continuity wait for an available activity",
	)
	gateway.free()



func _test_failed_first_pair_cannot_starve_the_town() -> void:
	var agent := DelayedFailingAgent.new()
	var world := PendingWorld.new()
	var resident_ids: Array[String] = [
		"resident-a",
		"resident-b",
		"resident-c",
		"resident-d",
		"resident-e",
		"resident-f",
		"resident-g",
		"resident-h",
	]
	for resident_id in resident_ids:
		world.add_request(_request(resident_id, "decision-%s" % resident_id))
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", resident_ids)
	gateway.set("_session_active", true)

	_expect_equal(
		gateway.call("pump"),
		5,
		"ordinary life leaves one bounded model slot available for conversation",
	)
	_expect_equal(
		agent.requested_resident_ids,
		[
			"resident-a",
			"resident-b",
			"resident-c",
			"resident-d",
			"resident-e",
		],
		"first pump begins from the current round-robin cursor",
	)
	for resident_id in resident_ids.slice(0, 5):
		agent.fail("decision-%s" % resident_id)
	_expect_equal(
		world.submissions.size(),
		0,
		"contract-invalid model outputs receive one fresh request first",
	)
	_expect_equal(
		gateway.call("pump"),
		5,
		"the next bounded batch mixes correction attempts with waiting residents",
	)
	var correction_batch := agent.requested_resident_ids.slice(5)
	_expect(
		correction_batch.has("resident-f")
		and correction_batch.has("resident-g")
		and correction_batch.has("resident-h"),
		"a bad first group cannot starve residents that were already waiting",
	)
	for resident_id in correction_batch:
		agent.fail("decision-%s" % resident_id)
	_expect(
		world.submissions.size() > 0,
		"residents whose correction was exhausted receive safe continuity",
	)
	gateway.free()



func _test_local_model_queue_preserves_town_and_avatar_lane() -> void:
	var agent := DelayedFailingAgent.new()
	var world := PendingWorld.new()
	var resident_ids: Array[String] = [
		"resident-a",
		"resident-b",
		"resident-c",
		"resident-d",
		"resident-avatar",
	]
	var bindings := {}
	for resident_id in resident_ids:
		bindings[resident_id] = {
			"residentId": resident_id,
			"llmBinding": {
				"mode": "model",
				"providerId": "ollama",
				"modelId": "qwen3.5:9b",
			},
		}
	for resident_id in resident_ids.slice(0, 4):
		world.add_request(_request(resident_id, "decision-%s" % resident_id))
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", resident_ids)
	gateway.set("_bindings_by_id", bindings)
	gateway.set("_session_active", true)

	_expect_equal(
		gateway.call("pump"),
		2,
		"local inference dispatches only two ordinary residents at once",
	)
	_expect_equal(
		agent.requested_resident_ids,
		["resident-a", "resident-b"],
		"local queue keeps deterministic round-robin order",
	)
	_expect(
		world.redispatched.has("decision-resident-c")
		and world.redispatched.has("decision-resident-d"),
		"queued local residents remain pending instead of receiving continuity fallback",
	)
	var avatar_request := _request(
		"resident-avatar",
		"decision-local-avatar-reply",
	)
	var avatar_wake := avatar_request.get("wakePacket", {}) as Dictionary
	avatar_wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-local-avatar",
		"with_resident_id": "person_7f3a91c2d8e4",
		"with": "旅行者",
		"turns": [],
	}
	avatar_wake["events"] = [{
		"event_id": "conversation-local-avatar-turn",
		"time": {"day": 1, "clock": "08:11", "period": "上午"},
		"type": "对方答话",
		"conversation_id": "conversation-local-avatar",
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "person_7f3a91c2d8e4",
			"speaker": "旅行者",
			"say": "我们聊聊。",
			"narration": "",
			"photos": [],
		},
	}]
	world.add_request(avatar_request)
	_expect_equal(
		gateway.call("pump"),
		1,
		"local inference keeps a third reserved lane for the player's conversation",
	)
	_expect_equal(
		agent.requested_resident_ids.back(),
		"resident-avatar",
		"the reserved local lane prioritizes the avatar reply",
	)
	_expect_equal(
		gateway.call("get_debug_inflight_count"),
		3,
		"local provider never exceeds its two background plus one conversation limit",
	)
	gateway.free()


func _test_conversation_lane_stays_available_during_ordinary_work() -> void:
	var agent := DelayedFailingAgent.new()
	var world := PendingWorld.new()
	var resident_ids: Array[String] = [
		"resident-a",
		"resident-b",
		"resident-c",
		"resident-d",
		"resident-e",
		"resident-f",
	]
	for resident_id in resident_ids.slice(0, 5):
		world.add_request(_request(resident_id, "decision-%s" % resident_id))
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", resident_ids)
	gateway.set("_session_active", true)

	_expect_equal(
		gateway.call("pump"),
		5,
		"five ordinary requests can run without consuming the conversation lane",
	)
	var urgent := _request("resident-f", "decision-avatar-reply")
	var wake := urgent.get("wakePacket", {}) as Dictionary
	wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-avatar",
		"with_resident_id": "person_7f3a91c2d8e4",
		"with": "旅行者",
		"turns": [],
	}
	wake["events"] = [{
		"event_id": "conversation-avatar-turn",
		"time": {"day": 1, "clock": "08:11", "period": "上午"},
		"type": "对方答话",
		"conversation_id": "conversation-avatar",
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "person_7f3a91c2d8e4",
			"speaker": "旅行者",
			"say": "带我去食堂。",
			"narration": "",
			"photos": [],
		},
	}]
	world.add_request(urgent)
	_expect_equal(
		gateway.call("pump"),
		1,
		"avatar reply starts while all ordinary lanes remain occupied",
	)
	_expect_equal(
		agent.requested_resident_ids.back(),
		"resident-f",
		"reserved lane dispatches the waiting avatar conversation",
	)
	gateway.free()



func _test_conversation_turn_preempts_ordinary_life_requests() -> void:
	var agent := DelayedFailingAgent.new()
	var world := PendingWorld.new()
	var resident_ids: Array[String] = [
		"resident-a",
		"resident-b",
		"resident-c",
		"resident-d",
		"resident-e",
		"resident-f",
		"resident-g",
	]
	for resident_id in resident_ids:
		world.add_request(_request(resident_id, "decision-%s" % resident_id))
	var urgent := (
		(world.pending.back() as Dictionary).get("wakePacket", {}) as Dictionary
	)
	urgent["snapshot"]["conversation"] = {
		"conversation_id": "conversation-priority",
		"with_resident_id": "player_avatar",
		"with": "旅行者",
		"turns": [],
	}
	urgent["events"] = [{
		"event_id": "conversation-priority-turn",
		"time": {"day": 1, "clock": "08:10", "period": "上午"},
		"type": "搭话",
		"conversation_id": "conversation-priority",
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "player_avatar",
			"speaker": "旅行者",
			"say": "早上好。",
			"narration": "",
			"photos": [],
		},
	}]
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", resident_ids)
	gateway.set("_avatar_person_id", "player_avatar")
	gateway.set("_session_active", true)

	_expect_equal(gateway.call("pump"), 6, "town-scale request group is bounded")
	_expect_equal(
		agent.requested_resident_ids[0],
		"resident-g",
		"a player conversation turn preempts ordinary autonomous decisions",
	)
	gateway.free()



func _test_failed_required_reply_ends_conversation_after_one_retry() -> void:
	var agent := DelayedFailingAgent.new()
	var world := PendingWorld.new()
	var wake := _wake("decision-reply")
	wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-1",
		"with_resident_id": "resident-b",
		"with": "居民乙",
		"turns": [],
	}
	wake["events"] = [{
		"event_id": "reply-1",
		"time": {"day": 1, "clock": "08:10", "period": "上午"},
		"type": "对方答话",
		"conversation_id": "conversation-1",
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "resident-b",
			"speaker": "居民乙",
			"say": "你觉得呢？",
			"narration": "",
			"photos": [],
		},
	}]
	world.add_request({
		"residentId": "resident-a",
		"residentName": "居民甲",
		"wakePacket": wake,
	})
	var gateway: Node = GATEWAY.new()
	var connected_resident_ids: Array[String] = ["resident-a"]
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", connected_resident_ids)
	gateway.set("_session_active", true)

	_expect_equal(world.pending.size(), 1, "required reply fixture queues one request")
	_expect_equal(
		(gateway.get("_connected_resident_ids") as Array).size(),
		1,
		"required reply fixture connects its resident",
	)
	_expect_equal(gateway.call("pump"), 1, "required reply reaches Agent")
	agent.fail("decision-reply")
	_expect_equal(
		world.submissions.size(),
		0,
		"a failed socially visible reply receives one fresh model attempt",
	)
	_expect_equal(
		gateway.call("pump"),
		1,
		"the required reply is retried before continuity",
	)
	agent.fail("decision-reply")
	_expect_equal(world.submissions.size(), 1, "failed reply receives one fallback")
	if world.submissions.size() == 1:
		var decision := (
			(world.submissions[0] as Dictionary).get("decision", {}) as Dictionary
		)
		var action := decision.get("action", {}) as Dictionary
		_expect_equal(action.get("type"), "答话", "fallback respects reply turn ownership")
		_expect_equal(
			action.get("end"),
			true,
			"provider failure ends the conversation instead of waking both residents again",
		)
		_expect(
			not String(action.get("say", "")).strip_edges().is_empty(),
			"fallback reply remains visible instead of submitting an empty answer",
		)
		_expect(
			String(action.get("say", "")).contains("没听清"),
			"fallback tells the player what the resident experienced",
		)
		_expect(
			String(action.get("narration", "")).contains("离开"),
			"fallback gives the conversation a natural visible ending",
		)
		_expect_equal(
			action.get("conversation_id"),
			"conversation-1",
			"fallback keeps the World-owned conversation id",
		)
	gateway.free()



func _test_unpublished_new_game_discard_lifecycle() -> void:
	var configured_gateway := _configured_gateway("configured")
	var configured_agent := DiscardAgent.new()
	configured_gateway.set("_agent_system", configured_agent)
	var configured_discard := (
		configured_gateway.call("discard_unpublished_new_game") as Dictionary
	)
	_expect_equal(
		configured_discard,
		{"ok": true, "errorCode": "", "retryable": false, "changed": false},
		"configure-before-bind compensation is an idempotent in-memory discard",
	)
	_expect_equal(
		configured_agent.delete_calls,
		0,
		"configure-before-bind compensation never deletes a nonexistent Agent slot",
	)
	_expect_equal(
		configured_gateway.get("_save_context"),
		{},
		"configure-before-bind compensation clears its unpublished context",
	)
	var configured_repeat := (
		configured_gateway.call("discard_unpublished_new_game") as Dictionary
	)
	_expect_equal(
		configured_repeat.get("changed"),
		false,
		"repeated configure-before-bind compensation stays idempotent",
	)
	_expect_equal(
		configured_agent.delete_calls,
		0,
		"repeated configure-before-bind compensation still performs no delete",
	)
	var configured_photos := (
		configured_gateway.get("_photo_store") as DiscardPhotoStore
	)
	_expect_equal(
		configured_photos.restore_flags,
		[false, false],
		"ordinary new-game failure requests photo slot cleanup",
	)
	configured_gateway.free()

	var active_gateway := _configured_gateway("active")
	var active_agent := DiscardAgent.new()
	active_gateway.set("_agent_system", active_agent)
	active_gateway.set("_session_active", true)
	var active_discard := (
		active_gateway.call("discard_unpublished_new_game") as Dictionary
	)
	_expect_equal(active_discard.get("ok"), true, "active Agent slot discard succeeds")
	_expect_equal(active_discard.get("changed"), true, "active Agent slot discard reports deletion")
	_expect_equal(active_agent.delete_calls, 1, "active Agent slot is deleted exactly once")
	var active_repeat := (
		active_gateway.call("discard_unpublished_new_game") as Dictionary
	)
	_expect_equal(active_repeat.get("changed"), false, "repeated active discard is idempotent")
	_expect_equal(active_agent.delete_calls, 1, "repeated active discard does not delete twice")
	active_gateway.free()

	var failing_gateway := _configured_gateway("failing")
	var failing_agent := DiscardAgent.new()
	failing_agent.delete_ok = false
	failing_gateway.set("_agent_system", failing_agent)
	failing_gateway.set("_session_active", true)
	var failed_discard := (
		failing_gateway.call("discard_unpublished_new_game") as Dictionary
	)
	_expect_equal(
		failed_discard.get("errorCode"),
		"AGENT_NEW_GAME_DISCARD_FAILED",
		"Agent slot delete failure remains an explicit compensation error",
	)
	_expect_equal(
		failing_gateway.get("_save_context"),
		{
			"slot_id": "slot-failing",
			"session_id": "session-failing",
			"save_revision": 0,
		},
		"delete failure preserves the context for diagnosis",
	)
	failing_gateway.free()

	var blocked_photos := DiscardPhotoStore.new()
	blocked_photos.discard_ok = false
	var blocked_gateway := _configured_gateway("photo-blocked", blocked_photos)
	var untouched_agent := DiscardAgent.new()
	blocked_gateway.set("_agent_system", untouched_agent)
	blocked_gateway.set("_session_active", true)
	var blocked_discard := blocked_gateway.call(
		"discard_unpublished_new_game",
		true,
	) as Dictionary
	_expect_equal(
		blocked_discard.get("errorCode"),
		"PHOTO_STORAGE_SLOT_BUSY",
		"photo compensation failure is returned without erasing its cause",
	)
	_expect_equal(
		blocked_photos.restore_flags,
		[true],
		"archive rollback forwards blocker restoration intent to PhotoStore",
	)
	_expect_equal(
		untouched_agent.close_calls,
		0,
		"photo compensation failure does not close Agent state",
	)
	_expect_equal(
		untouched_agent.delete_calls,
		0,
		"photo compensation failure does not delete Agent state",
	)
	_expect_equal(
		blocked_gateway.get("_session_active"),
		true,
		"photo compensation failure leaves the active session retryable",
	)
	_expect_equal(
		blocked_gateway.get("_save_context"),
		{
			"slot_id": "slot-photo-blocked",
			"session_id": "session-photo-blocked",
			"save_revision": 0,
		},
		"photo compensation failure preserves the exact save context",
	)
	blocked_gateway.free()



func _configured_gateway(
	suffix: String,
	photo_store: RefCounted = null,
) -> Node:
	var gateway: Node = GATEWAY.new()
	if photo_store == null:
		photo_store = DiscardPhotoStore.new()
	gateway.set("_photo_store", photo_store)
	var configured := gateway.call(
		"configure_session",
		{
			"sessionId": "session-%s" % suffix,
			"slotId": "slot-%s" % suffix,
			"saveRevision": 0,
			"residentIdentities": [{
				"residentId": "resident-a",
				"residentName": "居民甲",
			}],
			"residentBindings": [{
				"residentId": "resident-a",
				"residentName": "居民甲",
				"llmBinding": {
					"mode": "model",
					"providerId": "fake",
					"modelId": "fake",
				},
			}],
		},
		ProviderServiceStub.new(),
	) as Dictionary
	_expect_equal(configured.get("ok"), true, "%s gateway configures" % suffix)
	return gateway



func _request(resident_id: String, decision_id: String) -> Dictionary:
	return {
		"residentId": resident_id,
		"residentName": resident_id,
		"wakePacket": _wake(decision_id),
	}



func _wake(decision_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": {"day": 1, "clock": "08:10", "period": "上午"},
			"weather": "晴天",
			"me": {
				"doing": "站在广场上",
				"current_action": null,
				"body": {"困": "不困", "饿": "不饿", "累": "不累"},
			},
			"nearby": [],
			"place": {"name": "广场", "props": []},
			"conversation": null,
		},
		"events": [],
		"action_results": [],
	}



func _scenario_agent_environment_fact_contract() -> void:
	var initialization := _initialization()
	var plaza_wake := _wake_agent_environment_fact_contract("environment-plaza", "中心广场", [])
	_expect_equal(
		CONTRACT.validate_initialization(initialization),
		[],
		"初始化地点允许携带明确可见物",
	)
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				_decision({
					"action_id": "wait-on-fictional-bench",
					"type": "待着",
					"line": "就在广场长椅上坐一会儿。",
				}),
				initialization,
				plaza_wake,
				{},
			),
			"本轮动作不能使用的场景物件：长椅",
		),
		"广场待着不能凭空生成长椅",
	)
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				_decision({
					"action_id": "wait-at-fictional-fountain",
					"type": "待着",
					"line": "我去喷泉边站一会儿。",
				}),
				initialization,
				plaza_wake,
				{},
			),
			"本轮动作不能使用的场景物件：喷泉",
		),
		"广场待着也不能生成地点表从未登记的常见设施",
	)
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				_decision({
					"action_id": "wait-at-fictional-table",
					"type": "待着",
					"line": "我先到广场餐桌旁等一会儿。",
				}),
				initialization,
				plaza_wake,
				{},
			),
			"本轮动作不能使用的场景物件：桌",
		),
		"广场待着不能凭空生成其他地点才有的桌子",
	)
	var market_wake := _wake_agent_environment_fact_contract("environment-plaza", "市集", [])
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				_decision({
					"action_id": "wait-at-fictional-food-window",
					"type": "待着",
					"line": "我去供餐窗口旁看看。",
				}),
				initialization,
				market_wake,
				{},
			),
			"本轮动作不能使用的场景物件：窗口",
		),
		"市集不能继续使用已经从正式语义删除的供餐窗口",
	)
	var clinic_wake := _wake_agent_environment_fact_contract("environment-plaza", "诊所", [])
	(
		(
			clinic_wake.get("snapshot", {}) as Dictionary
		).get("place", {}) as Dictionary
	)["visible_props"] = ["诊所药柜"]
	_expect_equal(
		CONTRACT.validate_decision(
			_decision({
				"action_id": "wait-by-visible-medicine-cabinet",
				"type": "待着",
				"line": "我先在药柜旁等一会儿。",
			}),
			initialization,
			clinic_wake,
			{},
		),
		[],
		"看得见但当前不可操作的药柜仍然可以出现在环境描述里",
	)
	var talk_wake := plaza_wake.duplicate(true)
	talk_wake["decision_id"] = "environment-talk"
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				_decision({
					"action_id": "talk-on-fictional-bench",
					"type": "搭话",
					"target_resident_id": "resident-neighbor",
					"say": "这么晚了还没回去？",
					"narration": "我坐在广场长椅上朝他招手。",
					"photos": [],
				}),
				initialization,
				talk_wake,
				{},
			),
			"action.narration",
		),
		"对话旁白不能延续不存在的长椅",
	)
	_expect_equal(
		CONTRACT.validate_decision(
			_decision({
				"action_id": "wait-at-plaza",
				"type": "待着",
				"line": "我先在公告栏旁驻足，看看今晚还有没有人经过。",
			}),
			initialization,
			plaza_wake,
			{},
		),
		[],
		"不使用场景物件的广场停留仍然合法",
	)
	_expect_equal(
		CONTRACT.validate_decision(
			_decision({
				"action_id": "go-to-garden-bench",
				"type": "去",
				"place": "社区花园",
				"line": "去花园长椅坐一会儿。",
			}),
			initialization,
			plaza_wake,
			{},
		),
		[],
		"目标地点明确存在的长椅可以写入前往意图",
	)
	var garden_wake := _wake_agent_environment_fact_contract(
		"environment-garden",
		"社区花园",
		[{"name": "社区花园长椅", "verbs": ["歇着"]}],
	)
	_expect_equal(
		CONTRACT.validate_decision(
			_decision({
				"action_id": "use-real-bench",
				"type": "用道具",
				"prop": "社区花园长椅",
				"verb": "歇着",
				"line": "我在长椅上坐一会儿。",
			}),
			initialization,
			garden_wake,
			{},
		),
		[],
		"实际提供的长椅仍然可以使用",
	)
	var library_wake := _wake_agent_environment_fact_contract(
		"environment-garden",
		"图书馆",
		[{"name": "图书馆写作桌", "verbs": ["写作", "整理字帖"]}],
	)
	_expect_equal(
		CONTRACT.validate_decision(
			_decision({
				"action_id": "use-real-writing-desk",
				"type": "用道具",
				"prop": "图书馆写作桌",
				"verb": "写作",
				"line": "我在写作桌前继续写一会儿。",
			}),
			initialization,
			library_wake,
			{},
		),
		[],
		"当前地点真实提供的桌子仍然可以使用",
	)
	var library_cleanup_wake := _wake_agent_environment_fact_contract(
		"environment-garden",
		"图书馆",
		[{"name": "图书馆西北座椅", "verbs": ["整理桌椅"]}],
	)
	_expect_equal(
		CONTRACT.validate_decision(
			_decision({
				"action_id": "tidy-real-table-from-verb",
				"type": "用道具",
				"prop": "图书馆西北座椅",
				"verb": "整理桌椅",
				"line": "我把桌面和座椅收拾整齐。",
			}),
			initialization,
			library_cleanup_wake,
			{},
		),
		[],
		"已确认的道具动作名称可以授权对应物件描述",
	)
	var plaza_activity_wake := plaza_wake.duplicate(true)
	(
		(
			plaza_activity_wake.get("snapshot", {}) as Dictionary
		).get("place", {}) as Dictionary
	)["activities"] = [{
		"activity_id": "activity_tidy_real_table",
		"label": "整理桌椅",
	}]
	_expect_equal(
		CONTRACT.validate_decision(
			_decision({
				"action_id": "tidy-real-table-activity",
				"type": "做活动",
				"activity_id": "activity_tidy_real_table",
				"line": "我把桌面和座椅收拾整齐。",
			}),
			initialization,
			plaza_activity_wake,
			{},
		),
		[],
		"已确认的活动名称可以授权对应物件描述",
	)
	var fictional_dining_table_decision := _decision({
		"action_id": "wait-at-fictional-library-table",
		"type": "待着",
		"line": "我先在餐桌旁站一会儿。",
	})
	fictional_dining_table_decision["decision_id"] = "environment-garden"
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				fictional_dining_table_decision,
				initialization,
				library_wake,
				{},
			),
			"本轮动作不能使用的场景物件：餐桌",
		),
		"存在写作桌也不能把它描述成另一种桌子",
	)
	var compiler: RefCounted = COMPILER.new(initialization)
	var request := compiler.call("compile", plaza_wake, "") as Dictionary
	var messages := request.get("messages", []) as Array
	var system_text := String((messages[0] as Dictionary).get("content", ""))
	_expect(
		system_text.contains("只能引用其中已经确认的场景对象"),
		"正式提示明确使用封闭环境事实",
	)
	_expect(
		system_text.contains("明确可见：公告栏、花坛、路灯"),
		"正式提示把广场真实可见物交给居民",
	)
	return
func _initialization() -> Dictionary:
	return {
		"me": {
			"resident_id": "resident-test",
			"attributes": {
				"name": "测试居民",
				"gender": "男",
				"age": 30,
				"desire": "过好今天",
				"personality": "谨慎",
				"speech": "说话简短",
			},
			"social_state": {
				"home": "测试居民家",
				"job": "记录员",
				"workplace": "中心广场",
			},
		},
		"residents": [{
			"resident_id": "resident-neighbor",
			"name": "邻居",
			"gender": "女",
			"age": 28,
			"job": "园丁",
			"home": "邻居家",
			"workplace": "社区花园",
		}],
		"places": [
			{
				"name": "中心广场",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "有公告栏、花坛和路灯。",
				"features": ["公告栏", "花坛", "路灯"],
			},
			{
				"name": "社区花园",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "有花圃、花树和长椅。",
				"features": ["花圃", "花树", "长椅", "路灯"],
			},
			{
				"name": "市集",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "有露天摊位、货架和木桶。",
				"features": ["露天摊位", "货架", "木桶"],
			},
			{
				"name": "图书馆",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "收藏和借阅书籍的公共建筑。",
				"features": [],
			},
			{
				"name": "诊所",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "给居民看病和取药。",
				"features": [],
			},
		],
	}



func _wake_agent_environment_fact_contract(
	decision_id: String,
	place_name: String,
	props: Array,
) -> Dictionary:
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": {"day": 1, "clock": "21:00", "period": "夜里"},
			"weather": "晴天",
			"me": {
				"doing": "刚刚停下来",
				"current_action": null,
				"body": {"困": "有点困", "饿": "不饿", "累": "有点累"},
			},
			"nearby": [{
				"resident_id": "resident-neighbor",
				"name": "邻居",
				"doing": "正准备回家",
			}],
			"place": {"name": place_name, "props": props},
			"conversation": null,
		},
		"events": [],
		"action_results": [],
	}



func _decision(action: Dictionary) -> Dictionary:
	return {
		"decision_id": (
			"environment-talk"
			if String(action.get("type", "")) == "搭话"
			else (
				"environment-garden"
				if String(action.get("type", "")) == "用道具"
				else "environment-plaza"
			)
		),
		"handling": "replace_current",
		"action": action,
	}



func _errors_contain(errors: Array, fragment: String) -> bool:
	for value: Variant in errors:
		if String(value).contains(fragment):
			return true
	return false



func _scenario_agent_long_run() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_ok(opening_result, "formal opening fixture loads")
	if not bool(opening_result.get("ok", false)):
		_cleanup_agent_long_run(null, null)
		return
	var opening := FORMAL_OPENING.with_authoritative_outdoor_spawns(
		data,
		opening_result.get("config", {}) as Dictionary,
	)
	var identities := _resident_identities(opening)
	var world: RefCounted = WORLD_RUNTIME.new()
	_expect_ok(
		world.call("start_formal", data, opening, identities),
		"formal World starts for long-run Agent continuity",
	)
	world.call("cycle_time_period_for_test")
	world.call("cycle_time_period_for_test")
	var agent_system: RefCounted = AGENT_SYSTEM.new()
	_expect_ok(
		agent_system.call("configure_test_runtime_storage", _test_root),
		"long-run Agent memory uses isolated test storage",
	)
	var providers := FakeProviderService.new()
	providers.fail_first_resident_id = String(
		(identities[0] as Dictionary).get("residentId", ""),
	)
	var gateway: Node = GATEWAY_AGENT_LONG_RUN.new()
	gateway.set("_agent_system", agent_system)
	var session := gateway.call(
		"configure_session",
		_session_config(identities),
		providers,
		null,
	) as Dictionary
	_expect_ok(session, "Gateway configures the complete formal resident set")
	if bool(session.get("ok", false)):
		_expect_ok(
			gateway.call("bind_world", world),
			"Gateway binds real AgentSystem to the real formal World",
		)
	for cycle in range(CYCLES):
		var pumped := _pump_complete_round(gateway)
		_expect(
			pumped >= identities.size()
			and pumped <= identities.size() * 2,
			(
				"cycle %d serves every resident and keeps activity-contention"
				+ " reconsideration bounded (got %d)"
			) % [cycle, pumped],
		)
		for _preview_step in 5:
			world.call("advance", 0.5)
		if cycle == 0:
			_assert_hud_projection_differential(world, "cycle0 动作在途")
		var time_advance := world.call("cycle_time_period_for_test") as Dictionary
		_expect_ok(
			time_advance,
			"cycle %d advances enough World time to complete wait actions" % cycle,
		)
		for identity: Dictionary in identities:
			var resident_id := String(identity.get("residentId", ""))
			var state := world.call("get_resident_state", resident_id) as Dictionary
			_expect(
				state.get("currentAction") == null,
				"cycle %d clears %s's completed action (got %s)" % [
					cycle,
					resident_id,
					JSON.stringify(state.get("currentAction")),
				],
			)

	for identity: Dictionary in identities:
		var resident_id := String(identity.get("residentId", ""))
		var provider := providers.providers.get(resident_id) as RefCounted
		_expect(provider != null, "provider exists for %s" % resident_id)
		if provider == null:
			continue
		var decision_requests := 0
		for request_value: Variant in provider.call("get_requests") as Array:
			var request := request_value as Dictionary
			if request.get("request_kind") == "resident_decision":
				decision_requests += 1
		_expect(
			decision_requests >= CYCLES
			and decision_requests <= CYCLES * 2,
			(
				"%s keeps deciding after every completed action without"
				+ " an unbounded reconsideration loop (got %d)"
			) % [resident_id, decision_requests],
		)
	var retry_provider := providers.providers.get(
		providers.fail_first_resident_id,
	) as RefCounted
	var retry_decision_requests: Array[Dictionary] = []
	if retry_provider != null:
		for request_value: Variant in retry_provider.call(
			"get_requests",
		) as Array:
			if (
				request_value is Dictionary
				and String((request_value as Dictionary).get(
					"request_kind",
					"",
				)) == "resident_decision"
			):
				retry_decision_requests.append(
					(request_value as Dictionary).duplicate(true),
				)
	_expect(
		retry_decision_requests.size() >= 2,
		"the injected failure receives one bounded correction request",
	)
	if retry_decision_requests.size() >= 2:
		var retry_messages := (
			retry_decision_requests[1].get("messages", []) as Array
		)
		var retry_user_text := (
			String(
				(retry_messages[1] as Dictionary).get(
					"content",
					"",
				),
			)
			if retry_messages.size() == 2
			else ""
		)
		_expect(
			retry_messages.size() == 2
			and retry_user_text.contains(
				"action.action_id",
			),
			(
				"the correction attempt receives the exact previous"
				+ " contract error: %s"
			) % retry_user_text,
		)
	var gateway_errors := gateway.call("get_errors") as Array
	var fallback_count := 0
	var missing_intent_errors := 0
	for error_value: Variant in gateway_errors:
		var error := error_value as Dictionary
		if (
			String(error.get("residentId", ""))
			!= providers.fail_first_resident_id
		):
			_failures.append(
				"unrelated resident received a Gateway failure: %s"
				% JSON.stringify(error)
			)
		if (
			String(error.get("errorCode", ""))
			== "AGENT_CONTINUITY_FALLBACK_APPLIED"
		):
			fallback_count += 1
		if JSON.stringify(error).contains("缺少匹配的居民原意图"):
			missing_intent_errors += 1
	_expect_equal(
		fallback_count,
		1,
		"one injected failure episode that exhausts retry produces exactly one continuity fallback",
	)
	_expect_equal(
		missing_intent_errors,
		0,
		"continuity completion never starts a missing-intent fallback loop",
	)
	var next_round := world.call(
		"take_pending_decision_requests_by_ids",
		_connected_ids(identities),
	) as Array
	_expect_equal(
		next_round.size(),
		identities.size(),
		"all residents request another decision after the final completed action",
	)
	_assert_hud_projection_differential(world, "长跑收尾")
	_cleanup_agent_long_run(gateway, world)


# A2 差分验收(docs/帧预算与节拍解耦方案.md):town_hud 轻量投影必须恒等于
# 对完整投影输出做 HUD_KEYS 键裁剪;对照用完整投影只在本测试路径生成。

func _assert_hud_projection_differential(world: RefCounted, label: String) -> void:
	var full_states := world.call("get_all_resident_states") as Array
	var hud_states := world.call("get_town_hud_resident_states") as Array
	_expect_equal(
		hud_states.size(),
		full_states.size(),
		"%s: HUD 轻量投影覆盖全部居民" % label,
	)
	if hud_states.size() != full_states.size():
		return
	for index in range(full_states.size()):
		var full := full_states[index] as Dictionary
		var hud := hud_states[index] as Dictionary
		var pruned := {}
		for key: String in full:
			if RESIDENT_STATE_PROJECTION.HUD_KEYS.has(key):
				pruned[key] = full[key]
		_expect(
			hud == pruned,
			"%s: 轻量投影恒等于完整投影键裁剪 (%s)"
			% [label, String(full.get("residentId", ""))],
		)
		for key: String in hud:
			_expect(
				RESIDENT_STATE_PROJECTION.HUD_KEYS.has(key),
				"%s: 轻量投影出现 HUD_KEYS 之外的键 %s" % [label, key],
			)
		_expect(
			not hud.has("isMoving") and not full.has("isMoving"),
			"%s: isMoving 不得凭空出现" % label,
		)
	# C2 差分验收(docs/居民状态通知链减负方案.md):发射轻载荷必须恒等于
	# 对完整投影输出做 EMIT_KEYS 键裁剪;对照用完整投影只在本测试路径生成。
	var residents := world.get("_residents") as Dictionary
	for index in range(full_states.size()):
		var full := full_states[index] as Dictionary
		var resident_id := String(full.get("residentId", ""))
		var emit_state := RESIDENT_STATE_PROJECTION.project_emit(
			world,
			residents[resident_id] as Dictionary,
		) as Dictionary
		var pruned := {}
		for key: String in full:
			if RESIDENT_STATE_PROJECTION.EMIT_KEYS.has(key):
				pruned[key] = full[key]
		_expect(
			emit_state == pruned,
			"%s: 发射载荷恒等于完整投影键裁剪 (%s)" % [label, resident_id],
		)
		for key: String in emit_state:
			_expect(
				RESIDENT_STATE_PROJECTION.EMIT_KEYS.has(key),
				"%s: 发射载荷出现 EMIT_KEYS 之外的键 %s" % [label, key],
			)



func _pump_complete_round(gateway: Node) -> int:
	var total := 0
	for _attempt in range(64):
		var count := int(gateway.call("pump"))
		if count <= 0:
			break
		total += count
	return total



func _resident_identities(opening: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		result.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(resident.get("attributes", {}) as Dictionary).get("name", "")
			),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	return result



func _session_config(identities: Array[Dictionary]) -> Dictionary:
	var bindings: Array[Dictionary] = []
	for identity: Dictionary in identities:
		bindings.append({
			"residentId": String(identity.get("residentId", "")),
			"llmBinding": {
				"mode": "model",
				"providerId": "fake",
				"modelId": "fake",
			},
		})
	return {
		"sessionId": "long-run-%d" % Time.get_ticks_usec(),
		"slotId": "test-town-world-agent-long-run-%d" % OS.get_process_id(),
		"saveRevision": 0,
		"restorePending": false,
		"residentIdentities": identities.duplicate(true),
		"residentBindings": bindings,
		"capabilityMode": "formal",
		"formalReady": true,
	}



func _connected_ids(identities: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for identity: Dictionary in identities:
		ids.append(String(identity.get("residentId", "")))
	return ids



func _expect_ok(result: Dictionary, message: String) -> void:
	if result.get("ok") != true:
		_failures.append("%s: %s" % [message, result])



func _cleanup_agent_long_run(gateway: Node, world: RefCounted) -> void:
	if gateway != null:
		gateway.call("discard_unpublished_new_game")
		gateway.free()
	if world != null:
		world.call("stop")
	if not UserTestDataCleanerScript.remove_tree(_test_root):
		_failures.append("failed to clean isolated long-run Agent root")

func _finalize_agent_long_run() -> void:
	UserTestDataCleanerScript.remove_tree(_test_root)


func _scenario_agent_activity_action() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		data,
	) as Dictionary
	_expect_equal(
		opening_result.get("ok"),
		true,
		"无资产活动测试开局可加载",
	)
	if opening_result.get("ok") != true:
		return
	var abstract_slot := _activity_slot(
		data,
		"slot_fisher_organize_gear_01",
	)
	_expect_equal(
		abstract_slot.get("targetType"),
		"region",
		"无资产活动正式归类为真实语义区域而非道具",
	)
	_expect(
		not (
			abstract_slot.get("target", {}) as Dictionary
		).has("propName"),
		"无资产活动目标不再声明不存在的正式道具",
	)
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(
			world.call(
				"start",
				data,
				opening_result.get("config", {}) as Dictionary,
			) as Dictionary
		).get("ok"),
		true,
		"无资产活动测试 World 可启动",
	)
	var wake := _take_wake_agent_activity_action(world, RESIDENT_NAME)
	_expect(
		(CONTRACT.validate_wake_packet(wake) as Array).is_empty(),
		"包含可做活动的正式唤醒包符合 Agent 合同",
	)
	var place := (
		(wake.get("snapshot", {}) as Dictionary).get(
			"place",
			{},
		) as Dictionary
	)
	_expect(
		not JSON.stringify(place.get("props", [])).contains(
			"渔港渔具整理点"
		),
		"抽象站位不会冒充 Agent 可见道具",
	)
	_expect(
		_has_activity(place.get("activities", []) as Array, ACTIVITY_ID),
		"居民能看到当前地点正式可做的站位活动",
	)
	var action_id := "agent-activity-fisher-01"
	var decision := {
		"decision_id": String(wake.get("decision_id", "")),
		"handling": "replace_current",
		"action": {
			"action_id": action_id,
			"type": "做活动",
			"activity_id": ACTIVITY_ID,
			"line": "先整理一下今天的渔具",
		},
	}
	_expect(
		(
			CONTRACT.validate_decision(
				decision,
				world.call(
					"get_agent_initialization",
					"resident_ye_cheng_01",
				) as Dictionary,
				wake,
				{},
			) as Array
		).is_empty(),
		"Agent 能按当前活动编号提交做活动决定",
	)
	var accepted := world.call(
		"submit_agent_decision",
		RESIDENT_NAME,
		decision,
	) as Dictionary
	_expect_equal(
		accepted.get("status"),
		"accepted",
		"无资产活动决定被 World 接受",
	)
	var preview_presentation := ACTION_PRESENTATION._preview_action_presentation(
		world,
		{
			"currentPlace": "渔港",
			"spaceId": "town_outdoor",
		},
		{"action": decision.get("action", {}) as Dictionary},
	) as Dictionary
	_expect_equal(
		preview_presentation.get("baseIconKey"),
		"organize_fishing_gear",
		"新决定在动作激活前已经公开后续任务图标",
	)
	_expect_equal(
		preview_presentation.get("label"),
		"整理渔具",
		"新决定使用正式活动文字而不是自由描述",
	)
	_expect_equal(
		preview_presentation.get("publicThought"),
		"先整理一下今天的渔具",
		"新决定公开居民本人为什么要做这件事",
	)
	var state := world.call(
		"get_resident_state",
		RESIDENT_NAME,
	) as Dictionary
	var current := state.get("currentAction", {}) as Dictionary
	_expect(
		not current.is_empty(),
		"居民开始向合法活动站位移动并计时",
	)
	var action_presentation := (
		state.get("actionPresentation", {}) as Dictionary
	)
	_expect_equal(
		action_presentation.get("baseIconKey"),
		"organize_fishing_gear",
		"World 公开居民正在整理渔具的专属图标",
	)
	_expect_equal(
		action_presentation.get("sourceActivityId"),
		ACTIVITY_ID,
		"动作表现语义保留正式活动编号",
	)
	_expect_equal(
		action_presentation.get("publicThought"),
		"先整理一下今天的渔具",
		"动作开始后仍持续保留公开想法",
	)
	_expect(
		String(action_presentation.get("phase", "")) in [
			"approaching",
			"performing",
		],
		"动作表现语义公开当前前往或执行阶段",
	)
	_expect_equal(
		(
			accepted.get("action", {}) as Dictionary
		).get("type"),
		"做活动",
		"公开当前动作保留 Agent 选择的做活动类型",
	)
	var active_save := world.call("create_save_snapshot") as Dictionary
	_expect_equal(
		active_save.get("ok"),
		true,
		"Agent 发起的站位活动在执行中可以存档",
	)
	var restored: RefCounted = WORLD.new()
	var restored_result := restored.call(
		"restore_from_snapshot",
		data,
		opening_result.get("config", {}) as Dictionary,
		active_save.get("snapshot", {}) as Dictionary,
	) as Dictionary
	_expect_equal(
		restored_result.get("ok"),
		true,
		"Agent 活动来源合同能够通过正式读档校验",
	)
	if restored_result.get("ok") == true:
		world.call("stop")
		world = restored
		state = world.call(
			"get_resident_state",
			RESIDENT_NAME,
		) as Dictionary
		_expect(
			state.get("currentAction") is Dictionary,
			"读档后同一站位活动继续执行",
		)
	var completed_activity_events: Array[Dictionary] = []
	world.connect(
		"resident_activity_completed",
		func(_resident_id: String, event: Dictionary) -> void:
			completed_activity_events.append(event.duplicate(true)),
	)
	var progress_messages := {}
	for _minute in 180:
		world.call("advance", 1.0)
		state = world.call(
			"get_resident_state",
			RESIDENT_NAME,
		) as Dictionary
		var doing := String(state.get("doing", ""))
		if doing.contains("渔具"):
			progress_messages[doing] = true
		if state.get("currentAction") == null:
			break
	_expect(
		progress_messages.size() >= 2,
		"无动画工作会用同一真实活动的轮换短状态表现过程",
	)
	_expect(
		not JSON.stringify(progress_messages.keys()).contains(
			"渔港渔具整理点"
		),
		"工作短状态不会把内部站位冒充成可见道具",
	)
	_expect_equal(
		state.get("currentAction"),
		null,
		"站位活动完成计时后释放居民",
	)
	var completed_wake := _take_wake_agent_activity_action(world, RESIDENT_NAME)
	var results := completed_wake.get("action_results", []) as Array
	_expect(
		_has_action_result(results, action_id, "completed"),
		"活动完成结果使用 Agent 原始 action_id 返回",
	)
	var completed_result := _action_result(results, action_id)
	_expect_equal(
		completed_result.get("baseIconKey"),
		"organize_fishing_gear",
		"活动结果队列在动作清空后仍保留原任务图标",
	)
	_expect_equal(
		completed_result.get("phase"),
		"completed",
		"活动结果队列公开完成角标阶段",
	)
	_expect(not completed_activity_events.is_empty(), "活动完成发布表现事件")
	if not completed_activity_events.is_empty():
		var completed_event := completed_activity_events[-1]
		_expect_equal(
			completed_event.get("baseIconKey"),
			"organize_fishing_gear",
			"活动完成事件保留原任务图标",
		)
		_expect_equal(
			completed_event.get("phase"),
			"completed",
			"活动完成事件公开完成阶段",
		)
	world.call("stop")
	return
func _has_activity(activities: Array, activity_id: String) -> bool:
	for value: Variant in activities:
		if (
			value is Dictionary
			and String(
				(value as Dictionary).get("activity_id", "")
			) == activity_id
		):
			return true
	return false



func _activity_slot(data: Dictionary, slot_id: String) -> Dictionary:
	for value: Variant in data.get("activitySlots", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("slotId", "")) == slot_id
		):
			return (value as Dictionary).duplicate(true)
	return {}



func _has_action_result(
	results: Array,
	action_id: String,
	status: String,
) -> bool:
	for value: Variant in results:
		if not value is Dictionary:
			continue
		var result := value as Dictionary
		if (
			String(result.get("action_id", "")) == action_id
			and String(result.get("status", "")) == status
		):
			return true
	return false



func _action_result(results: Array, action_id: String) -> Dictionary:
	for value: Variant in results:
		if (
			value is Dictionary
			and String((value as Dictionary).get("action_id", ""))
			== action_id
		):
			return (value as Dictionary).duplicate(true)
	return {}



func _take_wake_agent_activity_action(world: RefCounted, resident_name: String) -> Dictionary:
	var requests := world.call(
		"take_pending_decision_requests",
		[resident_name],
	) as Array
	return (
		{}
		if requests.is_empty()
		else (
			(requests[0] as Dictionary).get(
				"wakePacket",
				{},
			) as Dictionary
		)
	)



func _scenario_agent_activity_reaction_contract() -> void:
	var scenarios: RefCounted = SCENARIOS.new()
	var initialization := scenarios.call("initialization") as Dictionary
	var wake := scenarios.call(
		"wake_packet",
		"reaction-1",
		1,
		"12:20",
	) as Dictionary
	wake["snapshot"]["time"]["period"] = "中午"
	wake["action_results"] = [{
		"action_id": "meal-1",
		"status": "completed",
		"reason": "吃完并把餐具收拾好了",
		"time": {"day": 1, "clock": "12:18", "period": "中午"},
	}]
	var decision := _decision_agent_activity_reaction_contract(
		"reaction-1",
		"next-1",
		"meal-1",
		"这顿吃得挺舒坦。",
	)
	var errors := CONTRACT.validate_decision(
		decision,
		initialization,
		wake,
		{},
	)
	_expect_equal(errors, [], "latest completed result accepts one short reaction")
	_expect_equal(
		CONTRACT.canonicalize_decision(decision).get("reaction"),
		decision.get("reaction"),
		"canonical decision preserves only the reaction contract fields",
	)
	var failed_wake := wake.duplicate(true)
	failed_wake["decision_id"] = "reaction-failed"
	failed_wake["action_results"][0]["status"] = "failed"
	var failed_errors := CONTRACT.validate_decision(
		_decision_agent_activity_reaction_contract(
			"reaction-failed",
			"next-failed",
			"meal-1",
			"这次没能办成。",
		),
		initialization,
		failed_wake,
		{},
	)
	_expect_equal(failed_errors, [], "failed result accepts a bound reaction")

	var announcement_wake := wake.duplicate(true)
	announcement_wake["decision_id"] = "reaction-announcement"
	announcement_wake["events"] = [{
		"event_id": "event-announcement-1",
		"time": {"day": 1, "clock": "12:20", "period": "中午"},
		"type": "公告发布",
		"announcement_id": "announcement-1",
		"text": "下午三点在中心广场集合。",
	}]
	var announcement_decision := {
		"decision_id": "reaction-announcement",
		"handling": "replace_current",
		"reaction": {
			"source_action_id": "meal-1",
			"text": "这顿吃得挺舒坦。",
		},
		"announcement_reactions": [{
			"source_event_id": "event-announcement-1",
			"text": "三点我应该能赶过去。",
		}],
		"action": {
			"action_id": "reaction-announcement-next",
			"type": "待着",
			"line": "先把手头的事理清楚。",
		},
	}
	_expect_equal(
		CONTRACT.validate_decision(
			announcement_decision,
			initialization,
			announcement_wake,
			{},
		),
		[],
		"announcement and action-result reactions can coexist",
	)
	_expect_equal(
		ACTION_VALIDATION.validate_decision_shape(
			announcement_decision,
			announcement_wake.get("events", []) as Array,
			announcement_wake.get("action_results", []) as Array,
		),
		"",
		"World accepts separate announcement and result reactions",
	)
	_expect_equal(
		CONTRACT.canonicalize_decision(
			announcement_decision,
		).get("announcement_reactions"),
		announcement_decision.get("announcement_reactions"),
		"canonical decision preserves the announcement event source",
	)
	var announcement_wrong_source := announcement_decision.duplicate(true)
	announcement_wrong_source["announcement_reactions"][0]["source_event_id"] = "event-older"
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				announcement_wrong_source,
				initialization,
				announcement_wake,
				{},
			),
			"不属于本轮公告",
		),
		"announcement reaction must bind an announcement from this wake",
	)
	var multi_wake := announcement_wake.duplicate(true)
	multi_wake["decision_id"] = "reaction-announcement-multi"
	multi_wake["events"].append({
		"event_id": "event-announcement-2-due",
		"time": {"day": 1, "clock": "15:00", "period": "下午"},
		"type": "公告到点",
		"announcement_id": "announcement-2",
		"publisher_resident_id": "resident-tang-xiao-man",
		"text": "下午三点在中心广场集合。",
		"scheduled_time_label": "第1天 15:00",
	})
	var multi_decision := announcement_decision.duplicate(true)
	multi_decision["decision_id"] = "reaction-announcement-multi"
	multi_decision["action"]["action_id"] = "reaction-announcement-multi-next"
	multi_decision["announcement_reactions"].append({
		"source_event_id": "event-announcement-2-due",
		"text": "时间到了，我现在再决定。",
	})
	_expect_equal(
		CONTRACT.validate_decision(
			multi_decision,
			initialization,
			multi_wake,
			{},
		),
		[],
		"one decision preserves separate reactions for every announcement event",
	)
	var due_wake := announcement_wake.duplicate(true)
	due_wake["decision_id"] = "reaction-announcement-due-continue"
	due_wake["action_results"] = []
	due_wake["snapshot"]["me"]["current_action"] = {
		"action_id": "work-in-progress",
		"type": "做活动",
		"activity_id": "activity-work",
		"line": "继续把手头的活做完。",
	}
	due_wake["events"] = [{
		"event_id": "event-announcement-due-continue",
		"time": {"day": 1, "clock": "15:00", "period": "下午"},
		"type": "公告到点",
		"announcement_id": "announcement-due-continue",
		"publisher_resident_id": "resident-tang-xiao-man",
		"text": "下午三点在中心广场集合。",
		"scheduled_time_label": "第1天 15:00",
	}]
	var due_continue_decision := {
		"decision_id": "reaction-announcement-due-continue",
		"handling": "continue_current",
		"announcement_reactions": [{
			"source_event_id": "event-announcement-due-continue",
			"text": "时间到了，但我先把手头的活做完。",
		}],
	}
	_expect_equal(
		CONTRACT.validate_decision(
			due_continue_decision,
			initialization,
			due_wake,
			{},
		),
		[],
		"announcement due reaction can keep a reasonable current action",
	)
	_expect_equal(
		ACTION_VALIDATION.validate_decision_shape(
			due_continue_decision,
			due_wake.get("events", []) as Array,
			due_wake.get("action_results", []) as Array,
		),
		"",
		"World accepts a due reaction without replacing the current action",
	)
	var player_priority_wake := due_wake.duplicate(true)
	player_priority_wake["decision_id"] = "reaction-player-announcement-priority"
	player_priority_wake["events"][0]["announcement_priority"] = "player"
	var player_priority_continue := due_continue_decision.duplicate(true)
	player_priority_continue["decision_id"] = (
		"reaction-player-announcement-priority"
	)
	player_priority_continue["announcement_reactions"][0]["source_event_id"] = (
		"event-announcement-due-continue"
	)
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				player_priority_continue,
				initialization,
				player_priority_wake,
				{},
			),
			"玩家公告必须停止普通工作",
		),
		"player announcement priority rejects continue_current",
	)
	var priority_compiler: RefCounted = COMPILER.new(initialization)
	var player_priority_request := priority_compiler.call(
		"compile",
		player_priority_wake,
		"",
	) as Dictionary
	_expect_equal(
		(
			player_priority_request.get("derived_constraints", {}) as Dictionary
		).get("handling"),
		["replace_current"],
		"player announcement prompt only exposes replacement actions",
	)

	var no_result_wake := wake.duplicate(true)
	no_result_wake["decision_id"] = "reaction-none"
	no_result_wake["action_results"] = []
	var no_result_errors := CONTRACT.validate_decision(
		_decision_agent_activity_reaction_contract(
			"reaction-none",
			"next-none",
			"meal-1",
			"还不错。",
		),
		initialization,
		no_result_wake,
		{},
	)
	_expect(
		_errors_contain(no_result_errors, "没有可回应的动作结果"),
		"reaction cannot appear without a matching result in this wake",
	)

	var replaced_wake := wake.duplicate(true)
	replaced_wake["decision_id"] = "reaction-replaced"
	replaced_wake["action_results"][0]["status"] = "replaced"
	var replaced_errors := CONTRACT.validate_decision(
		_decision_agent_activity_reaction_contract(
			"reaction-replaced",
			"next-replaced",
			"meal-1",
			"换件事做。",
		),
		initialization,
		replaced_wake,
		{},
	)
	_expect(
		_errors_contain(replaced_errors, "没有可回应的动作结果"),
		"replaced action does not create a completion reaction",
	)

	var wrong_source := decision.duplicate(true)
	wrong_source["reaction"]["source_action_id"] = "older-action"
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				wrong_source,
				initialization,
				wake,
				{},
			),
			"最新的可回应动作结果",
		),
		"reaction must bind the latest eligible result",
	)

	var long_reaction := decision.duplicate(true)
	long_reaction["reaction"]["text"] = (
		"这句话故意写得特别特别特别特别特别特别特别特别特别特别特别特别特别特别特别长"
	)
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				long_reaction,
				initialization,
				wake,
				{},
			),
			"最多 32 个字符",
		),
		"reaction text has a small fixed output budget",
	)

	var reply_wake := wake.duplicate(true)
	reply_wake["decision_id"] = "reaction-reply"
	reply_wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-1",
		"with_resident_id": "resident-tang-xiao-man",
		"with": "唐小满",
		"turns": [],
	}
	reply_wake["events"] = [{
		"event_id": "reply-1",
		"time": {"day": 1, "clock": "12:20", "period": "中午"},
		"type": "对方答话",
		"conversation_id": "conversation-1",
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "吃完了吗？",
			"narration": "",
			"photos": [],
		},
	}]
	var reply_decision := {
		"decision_id": "reaction-reply",
		"handling": "replace_current",
		"reaction": {
			"source_action_id": "meal-1",
			"text": "吃得挺饱。",
		},
		"action": {
			"action_id": "reply-action",
			"type": "答话",
			"conversation_id": "conversation-1",
			"say": "刚吃完。",
			"narration": "",
			"photos": [],
			"end": false,
		},
	}
	_expect(
		_errors_contain(
			CONTRACT.validate_decision(
				reply_decision,
				initialization,
				reply_wake,
				{},
			),
			"不允许 reaction",
		),
		"required conversation reply suppresses the optional reaction",
	)
	var reply_announcement_wake := reply_wake.duplicate(true)
	reply_announcement_wake["decision_id"] = "reaction-reply-announcement"
	reply_announcement_wake["events"].append({
		"event_id": "event-announcement-during-reply",
		"time": {"day": 1, "clock": "12:20", "period": "中午"},
		"type": "公告发布",
		"announcement_id": "announcement-during-reply",
		"text": "下午三点在中心广场集合。",
	})
	var reply_announcement_decision := reply_decision.duplicate(true)
	reply_announcement_decision["decision_id"] = (
		"reaction-reply-announcement"
	)
	reply_announcement_decision.erase("reaction")
	reply_announcement_decision["announcement_reactions"] = [{
		"source_event_id": "event-announcement-during-reply",
		"text": "三点的安排我先记住。",
	}]
	reply_announcement_decision["action"]["action_id"] = (
		"reply-announcement-action"
	)
	_expect_equal(
		CONTRACT.validate_decision(
			reply_announcement_decision,
			initialization,
			reply_announcement_wake,
			{},
		),
		[],
		"required reply can carry a non-blocking announcement reaction",
	)

	var compiler: RefCounted = COMPILER.new(initialization)
	var request := compiler.call("compile", wake, "") as Dictionary
	var constraints := request.get("derived_constraints", {}) as Dictionary
	_expect_equal(
		(constraints.get("reaction", {}) as Dictionary).get(
			"source_action_id"
		),
		"meal-1",
		"dynamic constraints expose only the latest reaction source",
	)
	_expect_equal(
		(constraints.get("reaction", {}) as Dictionary).get("required"),
		true,
		"result reaction is marked as required for the model",
	)
	_expect(
		String(
			((request.get("messages", []) as Array)[1] as Dictionary).get(
				"content",
				"",
			)
		).contains("必填结果反应"),
		"compiled prompt tells the model the result reaction is required",
	)
	var announcement_request := compiler.call(
		"compile",
		announcement_wake,
		"",
	) as Dictionary
	var announcement_constraints := (
		announcement_request.get("derived_constraints", {}) as Dictionary
	)
	_expect_equal(
		(announcement_constraints.get("announcement_reactions", {}) as Dictionary).get(
			"source_event_ids",
		),
		["event-announcement-1"],
		"dynamic constraints expose every announcement event",
	)
	_expect(
		String(
			(
				(announcement_request.get("messages", []) as Array)[1]
				as Dictionary
			).get("content", ""),
		).contains("必填公告反应"),
		"compiled prompt makes the announcement reaction visible and required",
	)
	var reply_request := compiler.call("compile", reply_wake, "") as Dictionary
	_expect(
		not (
			reply_request.get("derived_constraints", {}) as Dictionary
		).has("reaction"),
		"reply-only constraints omit reaction entirely",
	)
	var reply_announcement_request := compiler.call(
		"compile",
		reply_announcement_wake,
		"",
	) as Dictionary
	_expect_equal(
		(
			(
				reply_announcement_request.get(
					"derived_constraints",
					{},
				) as Dictionary
			).get("announcement_reactions", {}) as Dictionary
		).get("source_event_ids"),
		["event-announcement-during-reply"],
		"reply constraints keep the non-blocking announcement reaction",
	)
	return


func _scenario_announcement_time_parser() -> void:
	var now := 12 * 60 + 20
	var afternoon := ANNOUNCEMENT_TIME_PARSER.parse(
		"下午三点在中心广场集合。",
		now,
	) as Dictionary
	_expect_equal(
		afternoon.get("scheduled_absolute_minute"),
		15 * 60,
		"Chinese afternoon time resolves on the current world day",
	)
	_expect_equal(
		afternoon.get("scheduled_time_label"),
		"第1天 15:00",
		"time announcement exposes a player-readable world-time label",
	)
	var tomorrow := ANNOUNCEMENT_TIME_PARSER.parse(
		"明天上午九点半去镇公所。",
		now,
	) as Dictionary
	_expect_equal(
		tomorrow.get("scheduled_absolute_minute"),
		1440 + 9 * 60 + 30,
		"tomorrow and half-hour wording resolve deterministically",
	)
	var tomorrow_late_morning := ANNOUNCEMENT_TIME_PARSER.parse(
		"明天上午十一点集合。",
		now,
	) as Dictionary
	_expect_equal(
		tomorrow_late_morning.get("scheduled_absolute_minute"),
		1440 + 11 * 60,
		"Chinese eleven o'clock is not reduced to one o'clock",
	)
	var relative := ANNOUNCEMENT_TIME_PARSER.parse(
		"两小时后在桥边见。",
		now,
	) as Dictionary
	_expect_equal(
		relative.get("scheduled_absolute_minute"),
		now + 120,
		"relative-hour announcement resolves from current world time",
	)
	_expect(
		ANNOUNCEMENT_TIME_PARSER.parse("上午十点集合。", now).is_empty(),
		"past ambiguous times are not silently moved to tomorrow",
	)
	_expect(
		ANNOUNCEMENT_TIME_PARSER.has_time_expression("上午十点集合。"),
		"an invalid past time is still detected so the UI can warn the player",
	)
	_expect(
		not ANNOUNCEMENT_TIME_PARSER.has_time_expression("广场有新公告。"),
		"ordinary announcement text does not produce a false schedule warning",
	)
	_expect(
		ANNOUNCEMENT_TIME_PARSER.parse("周五下午三点集合。", now).is_empty(),
		"unsupported real-calendar weekdays are not misread as today",
	)
	_expect(
		ANNOUNCEMENT_TIME_PARSER.parse("明天下午25点集合。", now).is_empty(),
		"invalid numeric hours are not accepted through a suffix match",
	)


func _decision_agent_activity_reaction_contract(
	decision_id: String,
	action_id: String,
	source_action_id: String,
	text: String,
) -> Dictionary:
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"reaction": {
			"source_action_id": source_action_id,
			"text": text,
		},
		"action": {
			"action_id": action_id,
			"type": "待着",
			"line": "先歇一会儿。",
		},
	}



func _scenario_pause_agent_submission() -> void:
	var world_data := _read_json(WORLD_DATA_PATH)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		world_data,
	) as Dictionary
	var opening := opening_result.get("config", {}) as Dictionary
	var identities: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var attributes := resident.get("attributes", {}) as Dictionary
		identities.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(attributes.get("name", "")),
		})
	var world: RefCounted = WORLD.new()
	var started := world.call(
		"start",
		world_data,
		opening,
		identities,
	) as Dictionary
	_expect_equal(started.get("ok"), true, "World starts")
	var requests := world.call(
		"take_pending_decision_requests_by_ids",
		[RESIDENT_ID],
	) as Array[Dictionary]
	_expect_equal(requests.size(), 1, "resident has an initial decision request")
	if requests.is_empty():
		return
	var wake := requests[0].get("wakePacket", {}) as Dictionary
	var decision := _go_decision(
		String(wake.get("decision_id", "")),
	)
	var paused := world.call("pause", "manual") as Dictionary
	_expect_equal(paused.get("ok"), true, "World pauses")
	var paused_revision := int(world.call("get_world_revision"))
	var rejected := world.call(
		"submit_agent_decision_by_id",
		RESIDENT_ID,
		decision,
	) as Dictionary
	_expect_equal(rejected.get("ok"), false, "paused World rejects an in-flight result")
	_expect_equal(
		rejected.get("errorCode"),
		"WORLD_PAUSED",
		"paused rejection is explicit and retryable",
	)
	_expect_equal(rejected.get("retryable"), true, "paused result can be retried")
	_expect_equal(
		world.call("get_world_revision"),
		paused_revision,
		"paused submission does not mutate World state",
	)
	_expect_equal(
		(world.call("get_resident_state", RESIDENT_ID) as Dictionary).get(
			"currentAction",
		),
		null,
		"paused submission cannot start a visible resident action",
	)
	var resumed := world.call("resume", "manual") as Dictionary
	_expect_equal(resumed.get("ok"), true, "World resumes")
	var retried_requests := world.call(
		"take_pending_decision_requests_by_ids",
		[RESIDENT_ID],
	) as Array[Dictionary]
	_expect_equal(
		retried_requests.size(),
		1,
		"the rejected request is queued again after resume",
	)
	if not retried_requests.is_empty():
		var retried_wake := (
			retried_requests[0].get("wakePacket", {}) as Dictionary
		)
		var accepted := world.call(
			"submit_agent_decision_by_id",
			RESIDENT_ID,
			_go_decision(String(retried_wake.get("decision_id", ""))),
		) as Dictionary
		_expect_equal(
			accepted.get("status"),
			"accepted",
			"resident decision is accepted normally after resume",
		)
	world.call("stop")
	return
func _go_decision(decision_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-pause-regression" % decision_id,
			"type": "去",
			"place": "社区花园",
			"line": "去社区花园",
		},
	}



func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	return parsed as Dictionary if parsed is Dictionary else {}
