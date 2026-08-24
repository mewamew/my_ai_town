extends "res://tests/agent/support/AgentTestCase.gd"


class CountingReadStore:
	extends RefCounted

	var delegate: RefCounted
	var read_count := 0

	func _init(value: RefCounted) -> void:
		delegate = value

	func read() -> Dictionary:
		read_count += 1
		return delegate.call("read") as Dictionary

	func validate(value: Variant) -> Dictionary:
		return delegate.call("validate", value) as Dictionary

	func replace(value: Variant) -> Dictionary:
		return delegate.call("replace", value) as Dictionary


const MEMORY_SYSTEM_PATH := "res://agent/memory/ResidentMemorySystem.gd"
const MEMORY_STORE_PATH := "res://agent/memory/ResidentMemoryStore.gd"
const MEMORY_ORGANIZER_PATH := "res://agent/memory/MemoryOrganizer.gd"
const EVIDENCE_QUEUE_PATH := "res://agent/memory/ResidentEvidenceQueue.gd"
const UserTestDataCleanerScript := preload("res://tests/support/UserTestDataCleaner.gd")
const TestData := preload("res://tests/support/AgentMemoryTestData.gd")

const TEST_ROOT_BASE := "user://tests/agent-memory-layer"

var _test_root := "%s/%d_%d" % [
	TEST_ROOT_BASE,
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	_test_memory_state_round_trip_preserves_queue_and_pending_action()
	_test_version_five_state_migrates_to_formal_memory_archives()
	_test_unconfirmed_decision_can_be_discarded()
	_test_continuity_result_does_not_require_a_fabricated_agent_intent()
	_test_memory_state_rejects_cross_index_corruption()
	_test_decision_context_selects_relevant_fields()
	_test_formal_memory_recall_stays_bounded_at_archive_capacity()
	_test_active_intervention_forces_unrelated_recall()
	_test_public_current_focus_falls_back_to_formal_or_important_memory()
	_test_formal_memory_recall_respects_total_memory_budget()
	_test_retrieve_context_reuses_formal_memory_snapshot()
	_test_missing_memory_with_evidence_fails_explicitly()
	_test_loaded_evidence_corruption_fails_explicitly()
	_test_atomic_backups_recover_before_pair_validation()
	_test_player_query_is_read_only()
	_test_intervention_archive_round_trip()
	_test_automatic_hearsay_aging_round_trip()
	_finish_suite("AGENT_MEMORY_SYSTEM_PASS", [_test_root])


func _test_retrieve_context_reuses_formal_memory_snapshot() -> void:
	var system := _new_memory_system("single-read-retrieve")
	_expect_ok(
		system.call(
			"prepare_context",
			TestData.wake_packet("single-read-initialize"),
		),
		"single-read fixture initializes",
	)
	var archive_store := CountingReadStore.new(
		system.get("_memory_entry_store") as RefCounted,
	)
	var intervention_store := CountingReadStore.new(
		system.get("_memory_intervention_store") as RefCounted,
	)
	system.set("_memory_entry_store", archive_store)
	system.set("_memory_intervention_store", intervention_store)
	_expect_ok(
		system.call(
			"retrieve_context",
			TestData.wake_packet("single-read-retrieve"),
		),
		"single-read retrieval succeeds",
	)
	_expect_equal(
		archive_store.read_count,
		1,
		"one retrieval reads the formal archive exactly once",
	)
	_expect_equal(
		intervention_store.read_count,
		1,
		"one retrieval reads the intervention log exactly once",
	)


func _test_version_five_state_migrates_to_formal_memory_archives() -> void:
	var source := _new_memory_system("legacy-five-source")
	var capture := source.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "current empty memory state captures")
	var legacy := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	legacy["memory_state_version"] = 5
	legacy.erase("formal_memory_archive")
	legacy.erase("memory_interventions")
	var restored := _new_memory_system("legacy-five-restored")
	_expect_ok(
		restored.call("apply_persistent_state", legacy),
		"version five memory state migrates without inventing formal memories",
	)
	var migrated := restored.call("capture_persistent_state") as Dictionary
	var state := migrated.get("memory_state", {}) as Dictionary
	_expect_equal(state.get("memory_state_version"), 6, "legacy state upgrades to version six")
	_expect_equal(
		((state.get("formal_memory_archive", {}) as Dictionary).get("entries", []) as Array).size(),
		0,
		"migration starts with an empty formal archive",
	)
	_expect_equal(
		((state.get("memory_interventions", {}) as Dictionary).get("interventions", []) as Array).size(),
		0,
		"migration starts with an empty intervention log",
	)


func _test_unconfirmed_decision_can_be_discarded() -> void:
	var system := _new_memory_system("discard-unconfirmed")
	var decision := {
		"decision_id": "discard-decision",
		"handling": "replace_current",
		"action": {
			"action_id": "discard-action",
			"type": "待着",
			"line": "等世界确认。",
		},
	}
	_expect_ok(
		system.call(
			"accept_decision",
			decision,
			TestData.wake_packet("discard-decision"),
		),
		"unconfirmed decision first enters the pending index",
	)
	_expect_equal(
		(system.call("get_debug_snapshot") as Dictionary).get(
			"pending_action_count",
		),
		1,
		"unconfirmed decision is visible before World submission",
	)
	var live_memory := (system.call("get_debug_snapshot") as Dictionary).get(
		"memory",
		{},
	) as Dictionary
	_expect_equal(
		live_memory.get("current_thoughts"),
		"等世界确认。",
		"accepted decision immediately becomes the resident current thought",
	)
	var discarded := system.call(
		"discard_unconfirmed_decision",
		decision,
	) as Dictionary
	_expect_ok(discarded, "World-rejected decision can be discarded")
	_expect_equal(discarded.get("changed"), true, "discard reports a real rollback")
	var snapshot := system.call("get_debug_snapshot") as Dictionary
	_expect_equal(
		snapshot.get("pending_action_count"),
		0,
		"discard removes the phantom pending action",
	)
	_expect_equal(
		(snapshot.get("memory", {}) as Dictionary).get("current_thoughts"),
		"",
		"discard restores the previous current focus",
	)
	var captured := system.call("capture_persistent_state") as Dictionary
	_expect_equal(
		(
			(captured.get("memory_state", {}) as Dictionary).get(
				"known_action_ids",
				[],
			) as Array
		).has("discard-action"),
		false,
		"discarded unconfirmed action does not enter the save index",
	)


func _test_continuity_result_does_not_require_a_fabricated_agent_intent() -> void:
	var system := _new_memory_system("continuity-result")
	var wake := TestData.wake_packet("after-continuity")
	wake["action_results"] = [{
		"action_id": "resident-lin-lan-g1-2-continuity-activity",
		"status": "completed",
		"reason": "技术兜底已经结束",
		"time": {"day": 1, "clock": "08:20", "period": "上午"},
	}]
	_expect_ok(
		system.call("prepare_context", wake),
		"Gateway continuity result does not pretend to be an Agent intent",
	)
	var snapshot := system.call("get_debug_snapshot") as Dictionary
	_expect_equal(
		snapshot.get("evidence_item_count"),
		0,
		"technical continuity result stays out of resident memory evidence",
	)
	var service_wait := TestData.wake_packet("after-service-wait")
	service_wait["action_results"] = [{
		"action_id": "service-wait:occupation-service-000002",
		"status": "completed",
		"reason": "服务等待已经结束",
		"time": {"day": 1, "clock": "08:22", "period": "上午"},
	}]
	_expect_ok(
		system.call("prepare_context", service_wait),
		"World-owned service wait does not require a fabricated Agent intent",
	)
	snapshot = system.call("get_debug_snapshot") as Dictionary
	_expect_equal(
		snapshot.get("evidence_item_count"),
		0,
		"World-owned service wait stays out of resident memory evidence",
	)
	var conversation_continuity := TestData.wake_packet(
		"after-conversation-continuity",
	)
	conversation_continuity["action_results"] = [
		{
			"action_id": "commitment:goal-000001",
			"status": "completed",
			"reason": "刚才答应的事已经做完",
			"time": {"day": 1, "clock": "08:23", "period": "上午"},
		},
		{
			"action_id": "escort-follower:goal-000001",
			"status": "completed",
			"reason": "已经跟着带路人抵达",
			"time": {"day": 1, "clock": "08:24", "period": "上午"},
		},
	]
	_expect_ok(
		system.call("prepare_context", conversation_continuity),
		"World-owned promise continuations do not require fabricated Agent intents",
	)
	snapshot = system.call("get_debug_snapshot") as Dictionary
	_expect_equal(
		snapshot.get("evidence_item_count"),
		0,
		"promise continuation mechanics stay out of resident memory evidence",
	)
	var ordinary_unmatched := TestData.wake_packet("ordinary-unmatched")
	ordinary_unmatched["action_results"] = [{
		"action_id": "resident-authored-continuity-action",
		"status": "completed",
		"reason": "没有对应居民意图",
		"time": {"day": 1, "clock": "08:25", "period": "上午"},
	}]
	_expect_equal(
		(
			system.call(
				"prepare_context",
				ordinary_unmatched,
			) as Dictionary
		).get("ok"),
		false,
		"an ordinary unmatched result still fails the intent invariant",
	)



func _test_memory_state_round_trip_preserves_queue_and_pending_action() -> void:
	var source := _new_memory_system("round-trip-source")
	_expect_ok(source.call("prepare_context", _event_wake(6)), "source records evidence")
	_expect_ok(
		source.call(
			"accept_decision",
			{
				"decision_id": "pending-decision",
				"handling": "replace_current",
				"action": {
					"action_id": "pending-action",
					"type": "待着",
					"line": "等一会儿。",
				},
			},
			TestData.wake_packet("pending-decision"),
		),
		"source records pending action",
	)
	var capture := source.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "memory state captures")
	var invalid_target := _new_memory_system("round-trip-invalid")
	var invalid_time := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	invalid_time["pending_actions"][0]["submitted_at"]["day"] = 0
	_expect_equal(
		(invalid_target.call("apply_persistent_state", invalid_time) as Dictionary).get("ok"),
		false,
		"restore rejects a non-positive saved day",
	)
	var invalid_reply := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	invalid_reply["pending_actions"][0]["action"] = {
		"action_id": "pending-action",
		"type": "答话",
		"conversation_id": "conversation-1",
		"say": "再见。",
		"narration": "",
		"photos": [],
		"end": true,
	}
	_expect_equal(
		(invalid_target.call("apply_persistent_state", invalid_reply) as Dictionary).get("ok"),
		false,
		"restore rejects an ending reply without an ending narration",
	)
	var invalid_line := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	invalid_line["pending_actions"][0]["action"]["line"] = "   "
	_expect_equal(
		(invalid_target.call("apply_persistent_state", invalid_line) as Dictionary).get("ok"),
		false,
		"restore rejects an all-whitespace action field",
	)
	var invalid_photo := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	invalid_photo["pending_actions"][0]["action"] = {
		"action_id": "pending-action",
		"type": "搭话",
		"target_resident_id": "resident-tang-xiao-man",
		"say": "看看。",
		"narration": "",
		"photos": [{"ref": " ", "mime_type": "image/png"}],
	}
	_expect_equal(
		(invalid_target.call("apply_persistent_state", invalid_photo) as Dictionary).get("ok"),
		false,
		"restore rejects an all-whitespace photo reference",
	)
	var invalid_clock := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	invalid_clock["pending_actions"][0]["submitted_at"]["clock"] = "25:00"
	_expect_equal(
		(invalid_target.call("apply_persistent_state", invalid_clock) as Dictionary).get("ok"),
		false,
		"restore rejects an invalid saved clock",
	)
	var mismatched_period := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	mismatched_period["pending_actions"][0]["submitted_at"]["period"] = "下午"
	_expect_equal(
		(invalid_target.call("apply_persistent_state", mismatched_period) as Dictionary).get("ok"),
		false,
		"restore rejects a saved period that does not match its clock",
	)
	var restored := _new_memory_system("round-trip-restored")
	restored.call("get_debug_snapshot")
	_expect_ok(
		restored.call("apply_persistent_state", capture.get("memory_state")),
		"memory state restores after an empty debug read",
	)
	var snapshot := restored.call("get_debug_snapshot") as Dictionary
	_expect_equal(snapshot.get("evidence_item_count"), 1, "restored queue keeps its item")
	_expect_equal(snapshot.get("pending_action_count"), 1, "restored state keeps pending action")

func _test_memory_state_rejects_cross_index_corruption() -> void:
	var source := _new_memory_system("cross-index-source")
	_expect_ok(
		source.call(
			"accept_decision",
			{
				"decision_id": "cross-index-decision",
				"handling": "replace_current",
				"action": {
					"action_id": "cross-index-action",
					"type": "待着",
					"line": "等世界确认。",
				},
			},
			TestData.wake_packet("cross-index-decision"),
		),
		"cross-index fixture records a pending action",
	)
	var result_wake := TestData.wake_packet("cross-index-result")
	result_wake["action_results"] = [{
		"action_id": "cross-index-action",
		"status": "completed",
		"reason": "林岚确实等了一会儿。",
		"time": {"day": 1, "clock": "08:20", "period": "上午"},
	}]
	_expect_ok(
		source.call("prepare_context", result_wake),
		"cross-index fixture records the confirmed action result",
	)
	var capture := source.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "cross-index fixture captures")
	var corrupted := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	corrupted["known_action_ids"] = []
	var restored := _new_memory_system("cross-index-restored")
	var result := restored.call("apply_persistent_state", corrupted) as Dictionary
	_expect_equal(result.get("ok"), false, "restore rejects an evidence result absent from the action index")
	_expect(
		_errors_contain(result.get("errors", []), "动作结果不在已使用动作编号"),
		"cross-index corruption reports its invariant",
	)

func _test_decision_context_selects_relevant_fields() -> void:
	var root := _test_root.path_join("relevant-context")
	var store: RefCounted = (load(MEMORY_STORE_PATH) as Script).new(
		root.path_join("resident-lin-lan/resident_memory.json"),
	)
	var memory := {
		"important_memories": "唐小满（resident-tang-xiao-man）曾认真提醒我别忘了木架。",
		"relationships": "唐小满（resident-tang-xiao-man）：我重视她直率的提醒。",
		"current_thoughts": "今天得集中精神。",
		"long_term_goals": "把木工手艺磨炼好。",
		"short_term_goals": "完成手头仍未交付的木架。",
	}
	_expect_ok(store.call("replace", memory), "relevant-context fixture is stored")
	var queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(
		root.path_join("resident-lin-lan/world_evidence.json"),
	)
	_expect_ok(queue.call("initialize_empty"), "relevant-context evidence fixture is stored")
	var system: RefCounted = (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		root,
	)
	var unrelated := system.call(
		"prepare_context",
		TestData.wake_packet("unrelated-context"),
	) as Dictionary
	_expect_ok(unrelated, "unrelated context prepares")
	var unrelated_prompt := String(unrelated.get("memory_prompt", ""))
	_expect(not unrelated_prompt.contains("唐小满"), "unrelated wake omits person-specific fields")
	_expect(unrelated_prompt.contains("今天得集中精神"), "current thoughts retain short continuity")
	_expect(unrelated_prompt.contains("完成手头仍未交付的木架"), "unfinished goals remain available")

	var related_wake := TestData.wake_packet("related-context")
	related_wake["snapshot"]["nearby"] = [{
		"resident_id": "resident-tang-xiao-man",
		"name": "唐小满",
		"doing": "站在摊位旁",
	}]
	var related := system.call("prepare_context", related_wake) as Dictionary
	_expect_ok(related, "related context prepares")
	var related_prompt := String(related.get("memory_prompt", ""))
	_expect(related_prompt.contains("曾认真提醒"), "related wake includes important memory")
	_expect(related_prompt.contains("我重视她直率的提醒"), "related wake includes relationship")
	_expect_equal(
		(system.call("get_debug_snapshot") as Dictionary).get("context_item_count"),
		5,
		"debug snapshot reports the selected field count",
	)
	var result_wake := TestData.wake_packet("result-context")
	result_wake["action_results"] = [{
		"action_id": "unapplied-result",
		"status": "rejected",
		"reason": "木架还没有修好，交付没有发生。",
		"time": {"day": 1, "clock": "08:25", "period": "上午"},
	}]
	var result_context := system.call("retrieve_context", result_wake) as Dictionary
	_expect_ok(result_context, "action-result context retrieves without ingesting a second time")
	_expect(
		String(result_context.get("memory_prompt", "")).contains("曾认真提醒"),
		"action-result topic can retrieve the related important-memory field",
	)
	var generic_memory := memory.duplicate(true)
	generic_memory["important_memories"] = "今天工作很辛苦，我想明天去河岸钓鱼。"
	generic_memory["relationships"] = ""
	_expect_ok(store.call("replace", generic_memory), "generic-anchor fixture replaces memory")
	var unrelated_wake := TestData.wake_packet("unrelated-generic-context")
	unrelated_wake["snapshot"]["me"]["doing"] = "我打算继续修炉灶"
	var unrelated_context := system.call("retrieve_context", unrelated_wake) as Dictionary
	_expect_ok(unrelated_context, "generic-overlap context retrieves")
	_expect(
		not String(unrelated_context.get("memory_prompt", "")).contains("河岸钓鱼"),
		"generic first-person phrasing alone does not retrieve an unrelated important memory",
	)
	var workplace_wake := TestData.wake_packet("unrelated-workplace-context")
	workplace_wake["snapshot"]["me"]["doing"] = "我在工作坊修炉灶"
	var workplace_context := system.call("retrieve_context", workplace_wake) as Dictionary
	_expect_ok(workplace_context, "known-place context retrieves")
	_expect(
		not String(workplace_context.get("memory_prompt", "")).contains("河岸钓鱼"),
		"a known place does not degrade into a generic two-character topic",
	)
	var short_topic_memory := memory.duplicate(true)
	short_topic_memory["important_memories"] = "我答应给唐小满带一瓶可乐。"
	short_topic_memory["relationships"] = ""
	_expect_ok(store.call("replace", short_topic_memory), "short-topic fixture replaces memory")
	var short_topic_wake := TestData.wake_packet("short-topic-context")
	short_topic_wake["snapshot"]["me"]["doing"] = "可乐呢？"
	var short_topic_context := system.call("retrieve_context", short_topic_wake) as Dictionary
	_expect_ok(short_topic_context, "short-topic context retrieves")
	_expect(
		String(short_topic_context.get("memory_prompt", "")).contains("一瓶可乐"),
		"a meaningful two-character topic is preserved during preprocessing",
	)


func _test_formal_memory_recall_stays_bounded_at_archive_capacity() -> void:
	var source := _new_memory_system("formal-recall-source")
	var capture := source.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "formal recall fixture captures an empty current state")
	var state := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	state["memory"] = TestData.empty_memory()
	state["observed_identity_ids"] = ["avatar-player-7"]
	var entries: Array[Dictionary] = []
	entries.append(_formal_memory_entry(
		"old-player-photo",
		"旅行者给我看过雨后的花摊照片。",
		["avatar-player-7"],
		["雨后花摊"],
		1,
	))
	for index in range(255):
		entries.append(_formal_memory_entry(
			"ordinary-ledger-%03d" % index,
			"仓库账本编号 %03d 已经整理完毕。" % index,
			[],
			["仓库账本"],
			2 + index / 32,
		))
	var archive := (state["formal_memory_archive"] as Dictionary).duplicate(true)
	archive["revision"] = 1
	archive["entries"] = entries
	state["formal_memory_archive"] = archive
	var intervention_log := (
		state["memory_interventions"] as Dictionary
	).duplicate(true)
	intervention_log["revision"] = 1
	state["memory_interventions"] = intervention_log
	var restored := _new_memory_system("formal-recall-restored")
	_expect_ok(
		restored.call("apply_persistent_state", state),
		"a full formal memory archive restores without expanding the working summary",
	)
	var later := TestData.wake_packet("formal-recall-later", 12)
	later["snapshot"]["nearby"] = [{
		"resident_id": "avatar-player-7",
		"name": "旅行者",
		"doing": "站在广场旁",
	}]
	var context := restored.call("retrieve_context", later) as Dictionary
	_expect_ok(context, "formal recall succeeds at archive capacity")
	var prompt := String(context.get("memory_prompt", ""))
	_expect(
		prompt.contains("雨后的花摊照片"),
		"an old person-related memory is recalled after 255 unrelated memories",
	)
	_expect(
		not prompt.contains("仓库账本编号"),
		"unrelated archive entries do not enter the decision context",
	)
	_expect(
		prompt.length() <= 2500,
		"formal recall keeps the decision memory text inside its fixed budget",
	)
	_expect_ok(
		restored.call("apply_memory_intervention", {
			"resident_id": "resident-lin-lan",
			"memory_id": "memory-old-player-photo",
			"operation": "delete",
			"player_text": "",
			"world_time": {
				"day": 12,
				"clock": "12:10",
				"period": "中午",
			},
			"expected_revision": 1,
		}),
		"player suppression applies to a recalled formal memory",
	)
	var suppressed_context := restored.call("retrieve_context", later) as Dictionary
	_expect_ok(suppressed_context, "context still retrieves after player suppression")
	_expect(
		not String(suppressed_context.get("memory_prompt", "")).contains(
			"雨后的花摊照片",
		),
		"a player-suppressed memory does not re-enter the decision context",
	)


func _test_active_intervention_forces_unrelated_recall() -> void:
	var source := _new_memory_system("priority-recall-source")
	var capture := source.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "priority recall fixture captures an empty current state")
	var state := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	state["memory"] = TestData.empty_memory()
	var archive := (state["formal_memory_archive"] as Dictionary).duplicate(true)
	archive["revision"] = 1
	archive["entries"] = [_formal_memory_entry(
		"active-intervention-priority",
		"旧的花摊记忆。",
		[],
		["花摊"],
		1,
	)]
	state["formal_memory_archive"] = archive
	var intervention_log := (
		state["memory_interventions"] as Dictionary
	).duplicate(true)
	intervention_log["revision"] = 1
	intervention_log["interventions"] = []
	state["memory_interventions"] = intervention_log
	var restored := _new_memory_system("priority-recall-restored")
	_expect_ok(
		restored.call("apply_persistent_state", state),
		"priority recall fixture restores",
	)
	var before := restored.call(
		"retrieve_context",
		TestData.wake_packet("priority-recall-before"),
	) as Dictionary
	_expect_ok(before, "unrelated context retrieves before intervention")
	_expect(
		not String(before.get("memory_prompt", "")).contains("旧的花摊记忆"),
		"an unrelated formal memory is not recalled before intervention",
	)
	_expect_ok(
		restored.call("apply_memory_intervention", {
			"resident_id": "resident-lin-lan",
			"memory_id": "memory-active-intervention-priority",
			"operation": "edit",
			"player_text": "我现在认定旧的花摊记忆另有原因。",
			"world_time": {
				"day": 1,
				"clock": "09:10",
				"period": "上午",
			},
			"expected_revision": 1,
		}),
		"active memory intervention applies without waking an Agent",
	)
	var after := restored.call(
		"retrieve_context",
		TestData.wake_packet("priority-recall-after"),
	) as Dictionary
	_expect_ok(after, "unrelated context retrieves after intervention")
	_expect(
		String(after.get("memory_prompt", "")).contains(
			"我现在认定旧的花摊记忆另有原因。",
		),
		"an active memory intervention forces its memory into the next context",
	)


func _test_public_current_focus_falls_back_to_formal_or_important_memory() -> void:
	var formal_source := _new_memory_system("current-focus-formal-source")
	var formal_capture := formal_source.call("capture_persistent_state") as Dictionary
	_expect_ok(formal_capture, "current focus formal fixture captures")
	var formal_state := (
		formal_capture.get("memory_state", {}) as Dictionary
	).duplicate(true)
	formal_state["memory"] = TestData.empty_memory()
	var formal_archive := (
		formal_state["formal_memory_archive"] as Dictionary
	).duplicate(true)
	var formal_entry := _formal_memory_entry(
		"current-focus-formal",
		"花圃里有一件需要留意的事。",
		[],
		["花圃"],
		1,
	)
	formal_entry["state"] = "influencing"
	formal_archive["revision"] = 1
	formal_archive["entries"] = [formal_entry]
	formal_state["formal_memory_archive"] = formal_archive
	var formal_intervention_log := (
		formal_state["memory_interventions"] as Dictionary
	).duplicate(true)
	formal_intervention_log["revision"] = 1
	formal_state["memory_interventions"] = formal_intervention_log
	var formal_restored := _new_memory_system("current-focus-formal-restored")
	_expect_ok(
		formal_restored.call("apply_persistent_state", formal_state),
		"current focus formal fixture restores",
	)
	var formal_public := formal_restored.call("get_read_only_memory") as Dictionary
	_expect_ok(formal_public, "formal memory can provide current focus")
	_expect_equal(
		(formal_public.get("memory", {}) as Dictionary).get("current_focus"),
		"花圃里有一件需要留意的事。",
		"current focus falls back to the latest public formal memory",
	)
	_expect_equal(
		(formal_public.get("memory", {}) as Dictionary).get("current_inner_thought"),
		"",
		"inner observation never treats a formal memory as a current thought",
	)

	var important_source := _new_memory_system("current-focus-important-source")
	var important_capture := important_source.call("capture_persistent_state") as Dictionary
	_expect_ok(important_capture, "current focus important fixture captures")
	var important_state := (
		important_capture.get("memory_state", {}) as Dictionary
	).duplicate(true)
	important_state["memory"] = TestData.empty_memory()
	important_state["memory"]["important_memories"] = "我仍然记得那盏旧灯。"
	var important_restored := _new_memory_system("current-focus-important-restored")
	_expect_ok(
		important_restored.call("apply_persistent_state", important_state),
		"current focus important fixture restores",
	)
	var important_public := important_restored.call("get_read_only_memory") as Dictionary
	_expect_ok(important_public, "important memory can provide current focus")
	_expect_equal(
		(important_public.get("memory", {}) as Dictionary).get("current_focus"),
		"我仍然记得那盏旧灯。",
		"current focus falls back to the important memory summary",
	)
	_expect_equal(
		(important_public.get("memory", {}) as Dictionary).get("current_inner_thought"),
		"",
		"inner observation never treats important memories as a current thought",
	)


func _test_formal_memory_recall_respects_total_memory_budget() -> void:
	var source := _new_memory_system("formal-recall-budget-source")
	var capture := source.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "formal recall budget fixture captures")
	var state := (capture.get("memory_state", {}) as Dictionary).duplicate(true)
	state["memory"] = {
		"important_memories": "",
		"relationships": (
			"旅行者（avatar-player-7）：" + "信任".repeat(700)
		),
		"current_thoughts": "想法".repeat(340),
		"long_term_goals": "目标".repeat(340),
		"short_term_goals": "计划".repeat(580),
	}
	state["observed_identity_ids"] = ["avatar-player-7"]
	var restored := _new_memory_system("formal-recall-budget-restored")
	_expect_ok(
		restored.call("apply_persistent_state", state),
		"a near-capacity working summary restores",
	)
	var entries: Array[Dictionary] = []
	for index in range(6):
		var entry := _formal_memory_entry(
			"budget-%02d" % index,
			"旅行者的预算记忆%02d：%s" % [index, "花".repeat(420)],
			["avatar-player-7"],
			["预算记忆"],
			1 + index,
		)
		entry["interpretation"] = "这件事仍然影响我：%s" % "雨".repeat(420)
		entries.append(entry)
	var later := TestData.wake_packet("formal-recall-budget-later", 12)
	later["snapshot"]["nearby"] = [{
		"resident_id": "avatar-player-7",
		"name": "旅行者",
		"doing": "站在广场旁",
	}]
	var selected := restored.call(
		"_select_decision_memory",
		later,
		entries,
		{},
	) as Dictionary
	_expect(
		_memory_character_count(selected) <= 6000,
		"formal recall does not exceed the five-field decision memory budget",
	)
	_expect(
		String(selected.get("important_memories", "")).length() <= 2400,
		"formal recall also keeps the important-memory field budget",
	)
	_expect(
		String(selected.get("important_memories", "")).count("预算记忆") < 6,
		"the total budget drops lower-ranked memories instead of expanding context",
	)

func _test_missing_memory_with_evidence_fails_explicitly() -> void:
	var root := _test_root.path_join("missing-memory")
	var system: RefCounted = (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		root,
	)
	_expect_ok(system.call("prepare_context", _event_wake(70)), "fixture creates memory and evidence")
	var memory_path := root.path_join("resident-lin-lan/resident_memory.json")
	var removal := DirAccess.remove_absolute(ProjectSettings.globalize_path(memory_path))
	_expect_equal(removal, OK, "fixture removes only the resident memory file")
	var result := system.call(
		"prepare_context",
		TestData.wake_packet("after-memory-loss"),
	) as Dictionary
	_expect_equal(result.get("ok"), false, "evidence without memory fails explicitly")
	_expect(
		_errors_contain(result.get("errors", []), "文件不完整"),
		"missing-memory error identifies the inconsistent resident state",
	)
	var both_system := _new_memory_system("missing-both")
	_expect_ok(
		both_system.call("prepare_context", _event_wake(71)),
		"second fixture creates both resident files",
	)
	var both_snapshot := both_system.call("get_debug_snapshot") as Dictionary
	for path: String in [
		String(both_snapshot.get("source", "")),
		String(both_snapshot.get("evidence_source", "")),
	]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var both_result := both_system.call(
		"prepare_context",
		TestData.wake_packet("after-both-files-lost"),
	) as Dictionary
	_expect_equal(both_result.get("ok"), false, "initialized resident does not recreate two lost files")
	_expect(
		_errors_contain(both_result.get("errors", []), "文件缺失"),
		"double-loss error remains explicit",
	)
	var restarted: RefCounted = (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		_test_root.path_join("missing-both"),
	)
	var restarted_snapshot := restarted.call("get_debug_snapshot") as Dictionary
	_expect(
		_errors_contain(restarted_snapshot.get("read_errors", []), "文件缺失"),
		"restart-style double loss is visible in the debug snapshot before a formal read",
	)
	var restarted_result := restarted.call(
		"prepare_context",
		TestData.wake_packet("after-restart-with-both-files-lost"),
	) as Dictionary
	_expect_equal(
		restarted_result.get("ok"),
		false,
		"recreated memory system does not treat an existing empty resident directory as a new game",
	)
	_expect(
		_errors_contain(restarted_result.get("errors", []), "文件缺失"),
		"restart-style double loss remains explicit",
	)

func _test_atomic_backups_recover_before_pair_validation() -> void:
	var root := _test_root.path_join("backup-recovery")
	var source: RefCounted = (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		root,
	)
	_expect_ok(source.call("prepare_context", _event_wake(72)), "backup fixture initializes")
	var snapshot := source.call("get_debug_snapshot") as Dictionary
	for path_key: String in ["source", "evidence_source"]:
		var path := String(snapshot.get(path_key, ""))
		var rename_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path("%s.bak" % path),
		)
		_expect_equal(rename_error, OK, "fixture moves %s to its atomic backup" % path_key)
	var recovered: RefCounted = (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		root,
	)
	var result := recovered.call(
		"prepare_context",
		TestData.wake_packet("after-backup-recovery"),
	) as Dictionary
	_expect_ok(result, "both atomic backups recover before pair validation")
	_expect(
		FileAccess.file_exists(String(snapshot.get("source", "")))
			and FileAccess.file_exists(String(snapshot.get("evidence_source", ""))),
		"backup recovery restores both main files",
	)

func _test_loaded_evidence_corruption_fails_explicitly() -> void:
	var system := _new_memory_system("loaded-evidence-corruption")
	_expect_ok(
		system.call("prepare_context", _event_wake(73)),
		"evidence corruption fixture initializes and loads the queue",
	)
	var snapshot := system.call("get_debug_snapshot") as Dictionary
	var evidence_path := String(snapshot.get("evidence_source", ""))
	var file := FileAccess.open(evidence_path, FileAccess.WRITE)
	if file == null:
		_failures.append("evidence corruption fixture opens its queue file")
		return
	file.store_string("{broken-evidence")
	file = null
	var result := system.call(
		"prepare_context",
		TestData.wake_packet("after-loaded-evidence-corruption"),
	) as Dictionary
	_expect_equal(result.get("ok"), false, "loaded queue does not hide later file corruption")
	_expect(
		_errors_contain(result.get("errors", []), "居民证据文件损坏"),
		"loaded queue reports the corrupted evidence file",
	)

func _test_player_query_is_read_only() -> void:
	var system := _new_memory_system("read-only")
	var preparation: Dictionary = {}
	for index in range(4):
		var wake := _event_wake(80 + index)
		if index == 0:
			wake["events"] = [{
				"event_id": "overheard-identity-event",
				"time": {"day": 1, "clock": "08:10", "period": "上午"},
				"type": "旁听",
				"conversation_id": "overheard-identity-conversation",
				"speaker_resident_ids": ["avatar-player-7", "person-avatar-8"],
				"speakers": ["玩家", "阿澈"],
				"turn": {
					"turn_id": 1,
					"speaker_resident_id": "avatar-player-7",
					"speaker": "玩家",
					"say": "阿澈也听见了。",
					"narration": "",
					"photos": [],
				},
			}]
		preparation = system.call("prepare_context", wake)
	var organized := TestData.organized_memory()
	organized["important_memories"] = (
		"唐小满(resident-tang-xiao-man)问木架；"
		+ "玩家（avatar-player-7）提醒我，avatar-player-7确实听见了；"
		+ "阿澈person-avatar-8也在场。"
	)
	organized["relationships"] = (
		"玩家(avatar-player-7)：我记得这次提醒。"
	)
	_expect_ok(
		system.call(
			"accept_organization",
			preparation.get("organization_token"),
			organized,
		),
		"read-only fixture stores organized memory",
	)
	var before := system.call("capture_persistent_state") as Dictionary
	var query := system.call("get_read_only_memory") as Dictionary
	var after := system.call("capture_persistent_state") as Dictionary
	_expect_ok(query, "player memory query succeeds")
	var public_memory := query.get("memory", {}) as Dictionary
	_expect(
		(public_memory.get("formal_memories", []) as Array).size() >= 1,
		"player output exposes formal memories after organization",
	)
	var first_public_memory := (
		(public_memory.get("formal_memories", []) as Array)[0] as Dictionary
	)
	_expect(
		not first_public_memory.has("sourceResidentId"),
		"player output does not expose internal source resident IDs",
	)
	var public_people := first_public_memory.get("people", []) as Array
	_expect(
		not public_people.has("resident-tang-xiao-man"),
		"player output does not expose internal related resident IDs",
	)
	_expect_equal(
		system.call("_public_person_label", "resident-tang-xiao-man"),
		"唐小满",
		"player output resolves known related resident IDs to names",
	)
	_expect_equal(
		system.call("_public_person_label", "resident-not-in-initialization"),
		"",
		"player output drops unknown internal resident IDs instead of exposing them",
	)
	_expect_equal(
		system.call(
			"_public_person_label",
			"custom_resident_not_in_initialization",
		),
		"",
		"player output drops stale custom resident IDs instead of exposing them",
	)
	_expect_equal(public_memory.get("interventions"), [], "new memory has no interventions")
	var public_important := String(public_memory.get("important_memories", ""))
	_expect(not public_important.is_empty(), "formal memories project a public working summary")
	_expect(
		not public_important.contains("resident-")
			and not public_important.contains("avatar-")
			and not public_important.contains("person-avatar-"),
		"player output removes private identity IDs from the projected working summary",
	)
	_expect_equal(
		public_memory.get("relationships"),
		"玩家：我记得这次提醒。",
		"relationship summary remains player-visible",
	)
	_expect_equal(public_memory.get("current_focus"), "今晚要把木架收尾。", "current focus remains visible")
	_expect_equal(public_memory.get("current_inner_thought"), "今晚要把木架收尾。", "strict inner thought remains visible")
	_expect(public_memory.has("next_plan"), "inner observation next plan is projected")
	_expect(public_memory.has("current_judgment"), "inner observation judgment is projected")
	_expect(public_memory.has("memory_certainties"), "inner observation certainties are projected")
	_expect(public_memory.has("memory_doubts"), "inner observation doubts are projected")
	_expect(public_memory.has("memory_contradictions"), "inner observation contradictions are projected")
	_expect_equal(before.get("memory_state"), after.get("memory_state"), "query has no side effects")
	var expressed_claim := system.call(
		"find_expressed_memory_claim",
		"阿澈也听见了。",
	) as Dictionary
	_expect_ok(expressed_claim, "spoken memory claim can be matched read-only")
	_expect_equal(expressed_claim.get("matched"), true, "spoken claim keeps a propagation root")
	var restored := _new_memory_system("read-only-restored")
	_expect_ok(
		restored.call("apply_persistent_state", before.get("memory_state")),
		"observed identities restore with resident memory",
	)
	_expect_equal(
		(restored.call("get_read_only_memory") as Dictionary).get("memory"),
		query.get("memory"),
		"restored player output keeps non-initialization IDs private",
	)


func _test_intervention_archive_round_trip() -> void:
	var source := _new_memory_system("intervention-round-trip-source")
	var preparation := source.call(
		"prepare_context",
		TestData.conversation_end_wake(),
	) as Dictionary
	_expect_ok(preparation, "intervention round-trip conversation evidence prepares")
	_expect(
		preparation.has("organization_request"),
		"intervention round-trip reaches an organization boundary",
	)
	_expect_ok(
		source.call(
			"accept_organization",
			preparation.get("organization_token"),
			TestData.organized_memory(),
		),
		"intervention round-trip creates formal memories",
	)
	var before_intervention := source.call("get_read_only_memory") as Dictionary
	_expect_ok(before_intervention, "intervention round-trip reads its formal archive")
	var public_before := before_intervention.get("memory", {}) as Dictionary
	var entries := public_before.get("formal_memories", []) as Array
	_expect(not entries.is_empty(), "intervention round-trip has a target memory")
	if entries.is_empty():
		return
	var target := entries[0] as Dictionary
	_expect_ok(
		source.call("apply_memory_intervention", {
			"resident_id": "resident-lin-lan",
			"memory_id": target.get("memoryKey"),
			"operation": "edit",
			"player_text": "我现在相信这件事另有原因。",
			"world_time": {"day": 4, "clock": "09:10", "period": "上午"},
			"expected_revision": public_before.get("formal_memory_revision"),
		}),
		"intervention round-trip changes the subjective memory",
	)
	var capture := source.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "intervened archive captures")
	var restored := _new_memory_system("intervention-round-trip-restored")
	_expect_ok(
		restored.call("apply_persistent_state", capture.get("memory_state")),
		"intervened archive restores",
	)
	var restored_query := restored.call("get_read_only_memory") as Dictionary
	_expect_ok(restored_query, "restored intervened archive is readable")
	var public_interventions := (
		(restored_query.get("memory", {}) as Dictionary).get("interventions", [])
		as Array
	)
	_expect_equal(public_interventions.size(), 1, "restored public memory exposes one intervention record")
	if public_interventions.size() == 1:
		var public_intervention := public_interventions[0] as Dictionary
		_expect(
			String(public_intervention.get("originalSubject", "")).strip_edges() != "",
			"public intervention history keeps the visible original subject",
		)
		_expect_equal(public_intervention.get("operation"), "edit", "public intervention exposes the player operation")
		_expect_equal(
			public_intervention.get("activeSubject"),
			"我现在相信这件事另有原因。",
			"public intervention history keeps the visible edited memory",
		)
	_expect_equal(
		restored_query.get("memory"),
		(source.call("get_read_only_memory") as Dictionary).get("memory"),
		"formal memories and intervention records survive the same save restore",
	)


func _test_automatic_hearsay_aging_round_trip() -> void:
	var source := _new_memory_system("automatic-aging-source")
	var preparation := source.call(
		"prepare_context",
		TestData.conversation_end_wake(),
	) as Dictionary
	_expect_ok(preparation, "automatic-aging conversation evidence prepares")
	_expect_ok(
		source.call(
			"accept_organization",
			preparation.get("organization_token"),
			TestData.organized_memory(),
		),
		"automatic-aging fixture creates formal memories",
	)
	var before := source.call("get_read_only_memory") as Dictionary
	var before_hearsay := _public_memory_for_source(
		(before.get("memory", {}) as Dictionary).get("formal_memories", []),
		"hearsay",
	)
	_expect_equal(before_hearsay.get("confidence"), 58, "new hearsay starts at its normal confidence")
	var archive_store := CountingReadStore.new(
		source.get("_memory_entry_store") as RefCounted,
	)
	var intervention_store := CountingReadStore.new(
		source.get("_memory_intervention_store") as RefCounted,
	)
	source.set("_memory_entry_store", archive_store)
	source.set("_memory_intervention_store", intervention_store)
	var aging_wake := TestData.event_wake(
		"automatic-aging-day-eight",
		"automatic-aging-person-anchor",
		8,
	)
	var aging_context := source.call("prepare_context", aging_wake) as Dictionary
	_expect_ok(
		aging_context,
		"later game day triggers automatic memory organization",
	)
	_expect_equal(
		archive_store.read_count,
		1,
		"automatic aging reuses the formal archive snapshot from the same preparation",
	)
	_expect_equal(
		intervention_store.read_count,
		1,
		"automatic aging reuses the intervention snapshot from the same preparation",
	)
	_expect(
		String(aging_context.get("memory_prompt", "")).contains("木架明天能好吗"),
		"the same preparation renders context from the post-aging archive snapshot",
	)
	var after := source.call("get_read_only_memory") as Dictionary
	var public_after := after.get("memory", {}) as Dictionary
	var after_hearsay := _public_memory_for_source(
		public_after.get("formal_memories", []),
		"hearsay",
	)
	_expect_equal(after_hearsay.get("confidence"), 50, "unconfirmed hearsay softens after seven game days")
	_expect_equal(public_after.get("interventions"), [], "internal aging is not shown as the player's intervention")
	var capture := source.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "automatically aged memory captures")
	var state := capture.get("memory_state", {}) as Dictionary
	var internal_audits := (
		(state.get("memory_interventions", {}) as Dictionary).get("interventions", []) as Array
	)
	_expect_equal(internal_audits.size(), 1, "save keeps the internal aging audit")
	var restored := _new_memory_system("automatic-aging-restored")
	_expect_ok(
		restored.call("apply_persistent_state", state),
		"automatically aged memory restores",
	)
	_expect_equal(
		(restored.call("get_read_only_memory") as Dictionary).get("memory"),
		public_after,
		"automatic aging survives save restore without leaking its audit",
	)


func _public_memory_for_source(value: Variant, source_kind: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {}
	for entry_value: Variant in value as Array:
		var entry := entry_value as Dictionary
		if String(entry.get("sourceKind", "")) == source_kind:
			return entry
	return {}

func _new_memory_system(suffix: String) -> RefCounted:
	return (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		_test_root.path_join(suffix),
	)

func _event_wake(index: int, day: int = 1) -> Dictionary:
	return TestData.event_wake(
		"wake-%d" % index,
		"event-%d" % index,
		day,
		"有人走了",
		"08:%02d" % (index % 60),
	)


func _formal_memory_entry(
	suffix: String,
	subject: String,
	people: Array,
	topics: Array,
	day: int,
) -> Dictionary:
	var memory_id := "memory-%s" % suffix
	return {
		"memory_id": memory_id,
		"resident_id": "resident-lin-lan",
		"subject": subject,
		"interpretation": subject,
		"people": people.duplicate(),
		"places": [],
		"topics": topics.duplicate(),
		"world_time": {
			"day": day,
			"clock": "12:00",
			"period": "中午",
		},
		"source_kind": "firsthand",
		"source_resident_id": "",
		"claim_root_id": "event:%s" % suffix,
		"confidence": 72,
		"state": "past",
		"active_version_id": "%s-v1" % memory_id,
		"evidence_refs": ["event:%s" % suffix],
		"created_revision": 1,
		"updated_revision": 1,
	}


func _memory_character_count(memory: Dictionary) -> int:
	var total := 0
	for field_name: String in [
		"important_memories",
		"relationships",
		"current_thoughts",
		"long_term_goals",
		"short_term_goals",
	]:
		total += String(memory.get(field_name, "")).length()
	return total

func _message_text(content: Variant) -> String:
	if typeof(content) == TYPE_STRING:
		return String(content)
	if typeof(content) != TYPE_ARRAY:
		return ""
	for part_value: Variant in content as Array:
		if typeof(part_value) != TYPE_DICTIONARY:
			continue
		var part := part_value as Dictionary
		if part.get("type") == "text":
			return String(part.get("text", ""))
	return ""


func _finalize() -> void:
	UserTestDataCleanerScript.remove_tree(_test_root)
