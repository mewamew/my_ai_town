extends SceneTree


const GATEWAY := preload(
	"res://world/integration/TownWorldAgentGateway.gd"
)
const PROVIDER_SERVICE := preload(
	"res://world/integration/TownAgentProviderService.gd"
)

var _failures: Array[String] = []
var _death_results: Array[Dictionary] = []


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


class CancellableDelayedAgent:
	extends DelayedFailingAgent

	var cancelled_requests: Array[Dictionary] = []

	func cancel_resident_model_request(
		resident_id: String,
		request_id: String,
	) -> Dictionary:
		cancelled_requests.append({
			"residentId": resident_id,
			"requestId": request_id,
		})
		return {"ok": true, "supported": true}


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

	func validate_resident_bindings(_bindings: Variant) -> Dictionary:
		return {"ok": true, "errorCode": "", "retryable": false}

	func create_provider_for_resident(_binding: Dictionary) -> Dictionary:
		return {"ok": true, "provider": null}

	func get_latest_diagnostic(_resident_id: String) -> Dictionary:
		return {}


class RebindProvider:
	extends RefCounted

	func request_decision(_request: Dictionary, _on_complete: Callable) -> void:
		pass


class RebindProviderService:
	extends ProviderServiceStub

	func create_provider_for_resident(_binding: Dictionary) -> Dictionary:
		return {"ok": true, "provider": RebindProvider.new()}


class RebindAgentSystem:
	extends RefCounted

	var providers_by_resident_id: Dictionary = {}

	func replace_resident_model_provider(
		resident_id: String,
		model_provider: Object,
	) -> Dictionary:
		if model_provider == null or not model_provider.has_method("request_decision"):
			return {"ok": false, "errors": ["model provider missing"]}
		providers_by_resident_id[resident_id] = model_provider
		return {"ok": true}


class ProviderBillingFailureStub:
	extends RefCounted

	func get_latest_diagnostic(_resident_id: String) -> Dictionary:
		return {
			"error_type": "billing",
			"provider_error_code": "insufficient_balance",
			"retryable": false,
		}


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


class EnvelopePendingWorld:
	extends PendingWorld

	func take_pending_decision_envelopes_by_ids(
		resident_ids: Array,
	) -> Array[Dictionary]:
		var requests := take_pending_decision_requests_by_ids(resident_ids)
		for request in requests:
			var wake := request.get("wakePacket", {}) as Dictionary
			# Model the production light envelope: event identity is retained,
			# while the full snapshot is refreshed only after capacity selection.
			wake.erase("snapshot")
		return requests


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


class DeathStoryWorld:
	extends RefCounted

	func get_resident_state(_resident_id: String) -> Dictionary:
		return {
			"lifecycle": {"isDead": false},
			"currentPlace": "广场",
			"doing": "散步",
		}

	func get_time() -> Dictionary:
		return {"day": 1, "clock": "08:10"}

	func get_weather() -> String:
		return "晴天"


class DeathStoryAgent:
	extends RefCounted

	var cancelled_requests: Array[Dictionary] = []

	func request_json_for_resident(
		_resident_id: String,
		_request: Dictionary,
		_callback: Callable,
	) -> Dictionary:
		return {"ok": true, "started": true}

	func cancel_resident_model_request(
		resident_id: String,
		request_id: String,
	) -> Dictionary:
		cancelled_requests.append({
			"residentId": resident_id,
			"requestId": request_id,
		})
		return {"ok": true, "supported": true}


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


class FailingMemoryAgent:
	extends RefCounted

	func get_resident_memory(_resident_id: String) -> Dictionary:
		return {
			"ok": false,
			"retryable": true,
			"errors": ["memory store unavailable"],
		}


func _initialize() -> void:
	_test_null_conversation_snapshot_is_not_an_avatar_turn()
	_test_light_conversation_envelope_uses_event_identity()
	_test_rapid_avatar_reopen_preempts_same_resident_stale_call()
	_test_duplicate_display_names_route_by_id()
	_test_runtime_resident_bindings_can_be_replaced_atomically()
	_test_inner_observation_accepts_newer_read_only_world_revision()
	_test_death_story_timeout_releases_pending_state()
	_test_memory_read_failures_are_structured()
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
	_test_recovered_admission_rejection_is_not_final()
	_test_provider_failure_stays_final_when_continuity_keeps_life_moving()
	_test_thinking_only_provider_failures_are_retried()
	_test_provider_diagnostic_keeps_safe_code_only()
	_test_failed_decision_uses_available_world_prop()
	_test_failed_decision_uses_available_world_activity()
	_test_continuity_action_is_replaced_by_available_world_prop()
	_test_failed_required_reply_ends_conversation_after_one_retry()
	_test_unpublished_new_game_discard_lifecycle()
	call_deferred("_finish")


func _finish() -> void:
	var exit_code := 0 if _failures.is_empty() else 1
	if _failures.is_empty():
		print("TOWN_WORLD_AGENT_GATEWAY_CONTINUITY_PASS")
	else:
		for failure in _failures:
			push_error(failure)
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	for _index in 5:
		await process_frame
	await create_timer(0.3, true, false, true).timeout
	quit(exit_code)


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


func _test_light_conversation_envelope_uses_event_identity() -> void:
	var gateway: Node = GATEWAY.new()
	gateway.set("_avatar_person_id", "player_avatar")
	var wake := _wake("decision-light-conversation")
	wake.erase("snapshot")
	wake["events"] = [{
		"event_id": "conversation-light-turn",
		"type": "搭话",
		"conversation_id": "conversation-new",
		"participant_resident_ids": ["resident-a", "player_avatar"],
		"turn": {
			"speaker_resident_id": "player_avatar",
		},
	}]
	_expect_equal(
		gateway.call("_wake_is_avatar_conversation_turn", wake),
		true,
		"a light conversation envelope keeps the avatar lane from the event identity",
	)
	gateway.free()


func _test_rapid_avatar_reopen_preempts_same_resident_stale_call() -> void:
	var agent := CancellableDelayedAgent.new()
	var world := EnvelopePendingWorld.new()
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_avatar_person_id", "player_avatar")
	var connected_resident_ids: Array[String] = [
		"resident-a",
		"resident-busy-1",
		"resident-busy-2",
		"resident-busy-3",
		"resident-busy-4",
		"resident-busy-5",
	]
	gateway.set(
		"_connected_resident_ids",
		connected_resident_ids,
	)
	gateway.set("_session_active", true)
	var inflight := {}
	for index in 6:
		var resident_id := "resident-a" if index == 0 else "resident-busy-%d" % index
		var decision_id := "decision-old-%d" % index
		var old_wake := _wake(decision_id)
		if index == 0:
			old_wake["events"] = [{
				"type": "对方答话",
				"conversation_id": "conversation-old",
				"participant_resident_ids": ["resident-a", "player_avatar"],
			}]
		inflight[decision_id] = {
			"residentId": resident_id,
			"residentName": resident_id,
			"wakePacket": old_wake,
		}
	gateway.set("_inflight", inflight)
	var new_wake := _wake("decision-reopen")
	new_wake.erase("snapshot")
	new_wake["events"] = [{
		"event_id": "conversation-reopen-turn",
		"type": "搭话",
		"conversation_id": "conversation-reopen",
		"participant_resident_ids": ["resident-a", "player_avatar"],
		"turn": {"speaker_resident_id": "player_avatar"},
	}]
	world.add_request({
		"residentId": "resident-a",
		"residentName": "居民甲",
		"wakePacket": new_wake,
	})
	_expect_equal(
		world.has_method("take_pending_decision_envelopes_by_ids"),
		true,
		"the rapid reopen fixture exposes the production envelope API",
	)
	_expect_equal(world.pending.size(), 1, "the rapid reopen starts with one pending request")
	_expect_equal(
		gateway.call("_wake_is_avatar_conversation_turn", new_wake),
		true,
		"the reopen event identifies the player before the pump",
	)
	_expect_equal(
		gateway.call("pump"),
		1,
		"an immediate reopen dispatches even when the stale call filled the gateway",
	)
	inflight = gateway.get("_inflight") as Dictionary
	_expect(
		inflight.has("decision-reopen"),
		"the new conversation owns a request instead of remaining in World overflow",
	)
	_expect(
		bool(
			(inflight.get("decision-old-0", {}) as Dictionary).get(
				"superseded",
				false,
			)
		),
		"the prior conversation request is marked stale before capacity selection",
	)
	_expect(
		world.redispatched.is_empty(),
		"the immediate reopen is not redispatched back into the waiting queue",
	)
	_expect_equal(
		agent.cancelled_requests,
		[{
			"residentId": "resident-a",
			"requestId": "decision-old-0",
		}],
		"the superseded player conversation asks Agent to cancel the real request",
	)
	gateway.free()


func _test_memory_read_failures_are_structured() -> void:
	var gateway: Node = GATEWAY.new()
	var inactive := gateway.call("get_resident_memory", "resident-a") as Dictionary
	_expect_equal(
		inactive.get("errorCode", ""),
		"AGENT_GATEWAY_SESSION_INACTIVE",
		"inactive memory reads expose a stable gateway error",
	)
	gateway.set("_agent_system", FailingMemoryAgent.new())
	gateway.set("_session_active", true)
	var failed := gateway.call("get_resident_memory", "resident-a") as Dictionary
	_expect_equal(
		failed.get("errorCode", ""),
		"RESIDENT_MEMORY_READ_FAILED",
		"Agent memory failures are normalized for the UI page",
	)
	_expect_equal(
		failed.get("retryable", false),
		true,
		"transient Agent memory failures preserve retryability",
	)
	gateway.free()


func _test_death_story_timeout_releases_pending_state() -> void:
	var gateway: Node = GATEWAY.new()
	var agent := DeathStoryAgent.new()
	var world := DeathStoryWorld.new()
	gateway.set("_agent_system", agent)
	gateway.set("_world", world)
	gateway.set("_session_active", true)
	var connected_resident_ids: Array[String] = ["resident-a"]
	gateway.set("_connected_resident_ids", connected_resident_ids)
	gateway.set("_resident_name_by_id", {"resident-a": "居民甲"})
	_death_results.clear()
	var accepted := gateway.call(
		"request_resident_death_story",
		"resident-a",
		"death-timeout",
		Callable(self, "_capture_death_result"),
	) as Dictionary
	_expect_equal(
		accepted.get("ok"),
		true,
		"死亡故事请求能进入等待态 %s" % accepted,
	)
	var pending := gateway.get("_death_story_inflight") as Dictionary
	var request := (pending.get("death-timeout", {}) as Dictionary).duplicate(true)
	request["startedAtMsec"] = Time.get_ticks_msec() - 46_000
	pending["death-timeout"] = request
	gateway.set("_death_story_inflight", pending)
	gateway.call(
		"_advance_death_story_requests",
		Time.get_ticks_msec(),
	)
	_expect(
		(gateway.get("_death_story_inflight") as Dictionary).is_empty(),
		"死亡故事超时后不会永久保留 loading 状态",
	)
	_expect_equal(
		_death_results.size(),
		1,
		"死亡故事超时向上层发送一次恢复结果",
	)
	if _death_results.size() == 1:
		_expect_equal(
			_death_results[0].get("errorCode"),
			"DEATH_STORY_TIMEOUT",
			"死亡故事超时使用稳定错误码",
		)
	_expect_equal(
		agent.cancelled_requests,
		[{
			"residentId": "resident-a",
			"requestId": "death-timeout",
		}],
		"死亡故事超时会请求取消真实模型调用",
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


func _test_runtime_resident_bindings_can_be_replaced_atomically() -> void:
	var gateway: Node = GATEWAY.new()
	gateway.set("_session_active", true)
	gateway.set("_provider_service", RebindProviderService.new())
	gateway.set("_agent_system", RebindAgentSystem.new())
	gateway.set("_resident_identities", [
		{"residentId": "resident-a", "residentName": "小林"},
		{"residentId": "resident-b", "residentName": "小苏"},
	] as Array[Dictionary])
	var bindings := [
		{
			"residentId": "resident-a",
			"llmBinding": {
				"mode": "model",
				"providerId": "ollama",
				"modelId": "qwen3:8b",
			},
		},
		{
			"residentId": "resident-b",
			"llmBinding": {
				"mode": "model",
				"providerId": "deepseek",
				"modelId": "deepseek-chat",
			},
		},
	]
	var updated := gateway.call(
		"update_resident_bindings",
		bindings,
	) as Dictionary
	_expect(bool(updated.get("ok", false)), "运行中的居民模型绑定可整体更新")
	_expect_equal(
		((gateway.get("_bindings_by_id") as Dictionary).get(
			"resident-a",
			{},
		) as Dictionary).get("llmBinding"),
		bindings[0].get("llmBinding"),
		"Gateway 立即使用更新后的居民模型",
	)
	_expect_equal(
		(
			gateway.get("_agent_system") as RebindAgentSystem
		).providers_by_resident_id.size(),
		2,
		"绑定更新同步替换真实 Agent 层的居民模型提供方",
	)
	var before_invalid := (
		gateway.get("_bindings_by_id") as Dictionary
	).duplicate(true)
	var rejected := gateway.call(
		"update_resident_bindings",
		[bindings[0]],
	) as Dictionary
	_expect(
		not bool(rejected.get("ok", false)),
		"缺少居民的绑定更新会被拒绝",
	)
	_expect_equal(
		gateway.get("_bindings_by_id"),
		before_invalid,
		"失败的绑定更新不会留下半套状态",
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


func _test_recovered_admission_rejection_is_not_final() -> void:
	var world := PendingWorld.new()
	world.add_request(_request("resident-a", "decision-admission-recovered"))
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", ImmediatelyRejectingAgent.new())
	gateway.set("_provider_service", ProviderServiceStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", ["resident-a"] as Array[String])
	gateway.set("_session_active", true)
	_expect_equal(gateway.call("pump"), 1, "recovered admission rejection is processed")
	var errors := gateway.call("get_errors") as Array
	var rejection: Dictionary = {}
	for error_value: Variant in errors:
		var error := error_value as Dictionary
		if String(error.get("errorCode", "")) == "AGENT_DECISION_REQUEST_REJECTED":
			rejection = error
			break
	_expect(not rejection.is_empty(), "admission rejection remains in internal diagnostics")
	_expect_equal(rejection.get("final"), false, "successful continuity makes admission rejection non-final")
	_expect_equal(
		(rejection.get("diagnostic", {}) as Dictionary).get("recoveredByFallback"),
		true,
		"admission rejection records its actual recovery",
	)
	gateway.free()


func _test_provider_failure_stays_final_when_continuity_keeps_life_moving() -> void:
	var world := PendingWorld.new()
	var request := _request("resident-a", "decision-provider-billing")
	var gateway: Node = GATEWAY.new()
	var agent := DelayedFailingAgent.new()
	gateway.set("_agent_system", agent)
	gateway.set("_provider_service", ProviderBillingFailureStub.new())
	gateway.set("_world", world)
	gateway.set("_connected_resident_ids", ["resident-a"] as Array[String])
	gateway.set("_session_active", true)
	gateway.call("_request_agent_decision", request)
	agent.fail("decision-provider-billing")
	_expect_equal(world.submissions.size(), 1, "provider failure may use continuity to keep the resident moving")
	var failures: Array[Dictionary] = []
	for error_value: Variant in gateway.call("get_errors") as Array:
		var error := error_value as Dictionary
		if String(error.get("errorCode", "")) == "AGENT_DECISION_REQUEST_FAILED":
			failures.append(error)
	_expect_equal(failures.size(), 1, "non-retryable provider failure is not retried as a contract error")
	if not failures.is_empty():
		var failure := failures[0]
		_expect_equal(failure.get("final"), true, "provider failure remains a real final failure")
		_expect_equal(
			(failure.get("diagnostic", {}) as Dictionary).get("recoveredByFallback"),
			false,
			"continuity does not claim to recover the provider",
		)
	gateway.free()


func _test_thinking_only_provider_failures_are_retried() -> void:
	var gateway: Node = GATEWAY.new()
	var ordinary_life_wake := {"events": []}
	for error_type: String in [
		"reasoning_only_response",
		"thinking_only_content",
	]:
		_expect(
			gateway.call(
				"_decision_result_should_retry",
				1,
				{"error_type": error_type, "retryable": false},
				ordinary_life_wake,
			),
			"%s retries an ordinary resident decision instead of falling back immediately"
			% error_type,
		)
	gateway.free()


func _test_provider_diagnostic_keeps_safe_code_only() -> void:
	var service: RefCounted = PROVIDER_SERVICE.new()
	var diagnostic := service.call("_public_diagnostic", {
		"provider": "deepseek",
		"model": "deepseek-chat",
		"error_type": "billing",
		"provider_error_code": "insufficient_balance",
		"provider_error_message": "secret account detail",
		"raw_response": {"api_key": "must-not-leak"},
		"request": {
			"prompt": "private OC",
			"url": "https://model.example/v1/chat/completions?api_key=secret",
		},
		"content_present": true,
		"reasoning_present": true,
		"content_length": 32,
		"request_url": "https://model.example/v1/chat/completions",
		"retryable": false,
	}) as Dictionary
	_expect_equal(
		diagnostic.get("provider_error_code"),
		"insufficient_balance",
		"safe provider error code reaches internal diagnostics",
	)
	_expect(not diagnostic.has("provider_error_message"), "provider message is not exposed")
	_expect(not diagnostic.has("raw_response"), "raw provider response is not exposed")
	_expect(not diagnostic.has("request"), "private prompt is not exposed")
	_expect_equal(
		diagnostic.get("request_url"),
		"https://model.example/v1/chat/completions?<已隐藏参数>",
		"request URL is exposed without query credentials",
	)


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s (actual=%s expected=%s)" % [message, actual, expected]
		)


func _capture_death_result(result: Dictionary) -> void:
	_death_results.append(result.duplicate(true))
