extends SceneTree


const ModuleScript := preload(
	"res://agent/avatar_memory/ResidentAvatarMemoryModule.gd"
)
const StoreScript := preload(
	"res://agent/avatar_memory/ResidentAvatarMemoryStore.gd"
)
const EvidenceScript := preload(
	"res://agent/avatar_memory/ResidentAvatarEvidenceQueue.gd"
)
const CleanerScript := preload("res://tests/support/UserTestDataCleaner.gd")
const AgentTestCaseScript := preload(
	"res://tests/agent/support/AgentTestCase.gd"
)

const AVATAR_ID := "person_7f3a91c2d8e4"
const TEST_ROOT_BASE := "user://tests/avatar-memory-module"

var _test_root := "%s/%d_%d" % [
	TEST_ROOT_BASE,
	OS.get_process_id(),
	Time.get_ticks_usec(),
]
var _failures: Array[String] = []


func _initialize() -> void:
	AgentTestCaseScript.shutdown_project_autoloads(self)
	_test_store_and_evidence_boundaries()
	_test_organization_retrieval_message_and_restore()
	_test_active_avatar_conversation_defers_organization()
	_test_departure_forces_organization_and_filters_resident_narration()
	_test_resident_identity_isolation_and_social_propagation()
	CleanerScript.remove_tree(_test_root)
	AgentTestCaseScript.shutdown_project_autoloads(self)
	if _failures.is_empty():
		print("RESIDENT_AVATAR_MEMORY_MODULE_PASS")
		quit(0)
		return
	for failure in _failures:
		printerr("RESIDENT_AVATAR_MEMORY_MODULE_FAIL: %s" % failure)
	quit(1)


func _test_store_and_evidence_boundaries() -> void:
	var root := _test_root.path_join("store")
	var store := StoreScript.new(
		root.path_join("avatar_memory.json"),
		"resident-lin-lan",
		AVATAR_ID,
	)
	var empty := store.call("empty_memory") as Dictionary
	_expect_ok(store.call("replace", empty), "empty avatar memory persists")
	var legacy_empty := empty.duplicate(true)
	legacy_empty["state_version"] = StoreScript.LEGACY_STATE_VERSION
	legacy_empty.erase("departure_screening")
	var migrated_legacy := store.call("validate", legacy_empty) as Dictionary
	_expect_ok(migrated_legacy, "legacy avatar memory migrates")
	_expect_equal(
		(
			migrated_legacy.get("memory", {}) as Dictionary
		).get("state_version"),
		StoreScript.STATE_VERSION,
		"legacy avatar memory normalizes to the current version",
	)
	var wrong_identity := empty.duplicate(true)
	wrong_identity["resident_id"] = "resident-other"
	_expect_false(
		(store.call("validate", wrong_identity) as Dictionary).get("ok"),
		"store rejects cross-resident state",
	)
	var overflow := empty.duplicate(true)
	overflow["summary"] = "记".repeat(StoreScript.SUMMARY_LIMIT + 1)
	_expect_false(
		(store.call("validate", overflow) as Dictionary).get("ok"),
		"store rejects summary overflow",
	)

	var evidence := EvidenceScript.new(
		root.path_join("avatar_evidence.json"),
		"resident-lin-lan",
		AVATAR_ID,
		"旅行者",
	)
	_expect_ok(evidence.call("initialize_empty"), "evidence queue initializes")
	var direct := evidence.call("append_wake", _avatar_conversation_wake()) as Dictionary
	_expect_ok(direct, "direct avatar conversation enters evidence")
	_expect_equal(
		(direct.get("added_items", []) as Array).size(),
		2,
		"both sides of direct conversation are retained",
	)
	_expect_equal(
		direct.get("direct_avatar_conversation_ended"),
		true,
		"direct conversation end is reported",
	)
	var duplicate := evidence.call("append_wake", _avatar_conversation_wake()) as Dictionary
	_expect_equal(duplicate.get("added"), false, "same conversation turns deduplicate")
	var overlap_evidence := EvidenceScript.new(
		root.path_join("avatar_evidence_overlap.json"),
		"resident-lin-lan",
		AVATAR_ID,
		"旅行者",
	)
	_expect_ok(
		overlap_evidence.call("initialize_empty"),
		"overlap evidence queue initializes",
	)
	var overlap := overlap_evidence.call(
		"append_wake",
		_avatar_conversation_overlap_wake(),
	) as Dictionary
	_expect_ok(
		overlap,
		"same turn in snapshot and event deduplicates despite observation time",
	)
	_expect_equal(
		(overlap.get("added_items", []) as Array).size(),
		2,
		"overlapping snapshot and event retain each conversation turn once",
	)
	var social := evidence.call("append_wake", _resident_social_wake()) as Dictionary
	_expect_ok(social, "resident social turn is a candidate evidence")
	_expect_equal(
		(
			(social.get("added_items", []) as Array)[0] as Dictionary
		).get("source_type"),
		"hearsay",
		"resident social evidence keeps hearsay source",
	)
	var unrelated := evidence.call(
		"append_wake",
		_ordinary_social_wake(0),
	) as Dictionary
	_expect_ok(unrelated, "unrelated resident conversation is safely ignored")
	_expect_equal(
		(unrelated.get("added_items", []) as Array).size(),
		0,
		"unrelated resident daily life does not enter avatar memory",
	)
	for index in 20:
		evidence.call("append_wake", _identity_hearsay_wake(index))
	var bounded_queue := evidence.call("capture_state") as Dictionary
	var bounded_state := (
		bounded_queue.get("queue_state", {}) as Dictionary
	)
	_expect_equal(
		(bounded_state.get("items", []) as Array).size(),
		EvidenceScript.MAX_ITEMS,
		"evidence queue remains bounded",
	)
	_expect_equal(
		(bounded_state.get("known_source_hashes", {}) as Dictionary).size(),
		EvidenceScript.MAX_ITEMS,
		"evidence dedupe index is trimmed with the bounded queue",
	)


func _test_organization_retrieval_message_and_restore() -> void:
	var source_root := _test_root.path_join("module-source")
	var module := ModuleScript.new(
		_initialization(),
		source_root,
		AVATAR_ID,
		"旅行者",
	)
	var preparation := module.call(
		"prepare_context",
		_avatar_conversation_wake(),
	) as Dictionary
	_expect_ok(preparation, "module accepts direct avatar conversation")
	_expect(
		preparation.has("organization_request"),
		"direct avatar conversation end requests organization",
	)
	var candidate := {
		"summary": "旅行者说过自己叫迪迦，还说了一件很古怪的事。",
		"memories": [
			{
				"content": "旅行者亲口说自己叫迪迦。",
				"world_time": {"day": 2, "clock": "18:20", "period": "傍晚"},
				"source_type": "direct_dialogue",
				"source_person_id": AVATAR_ID,
				"source_refs": ["conversation:avatar-talk:turn:1"],
				"status": "active",
				"salience": 4,
			},
			{
				"content": "旅行者说明天想吃屎。",
				"world_time": {"day": 2, "clock": "18:20", "period": "傍晚"},
				"source_type": "direct_dialogue",
				"source_person_id": AVATAR_ID,
				"source_refs": ["conversation:avatar-talk:turn:1"],
				"status": "active",
				"salience": 1,
			},
		],
		"open_loops": [{
			"content": "还想确认旅行者为什么自称迪迦。",
			"world_time": {"day": 2, "clock": "18:20", "period": "傍晚"},
			"source_type": "direct_dialogue",
			"source_person_id": AVATAR_ID,
			"source_refs": ["conversation:avatar-talk:turn:1"],
			"status": "active",
			"salience": 3,
			"people": [AVATAR_ID],
			"progress": "尚未确认",
		}],
		"message_updates": [],
	}
	var accepted := module.call(
		"accept_organization",
		preparation.get("organization_token"),
		candidate,
	) as Dictionary
	_expect_ok(accepted, "organized avatar memory commits")
	var context := module.call(
		"retrieve_context",
		_avatar_nearby_wake(),
	) as Dictionary
	_expect_ok(context, "avatar memory retrieves")
	_expect(
		String(context.get("avatar_prompt", "")).contains("迪迦"),
		"avatar interaction retrieves the specific self-introduction",
	)
	_expect(
		String(context.get("avatar_prompt", "")).contains("明天想吃屎"),
		"specific low-salience odd utterance remains retrievable",
	)
	var compression_preparation: Dictionary = {}
	for index in 16:
		compression_preparation = module.call(
			"prepare_context",
			_identity_hearsay_wake(index),
		) as Dictionary
	_expect(
		compression_preparation.has("organization_request"),
		"a full recent-evidence window requests memory compression",
	)
	var before_compression := (
		module.call("get_debug_snapshot") as Dictionary
	).get("memory", {}) as Dictionary
	var invalid_compression := module.call(
		"accept_organization",
		compression_preparation.get("organization_token"),
		{
			"summary": "最近听了许多普通闲聊。",
			"memories": (
				before_compression.get("memories", []) as Array
			).duplicate(true),
			"open_loops": [],
			"message_updates": [],
		},
	) as Dictionary
	_expect_false(
		invalid_compression.get("ok"),
		"compression cannot discard an old unresolved avatar matter",
	)
	_expect_ok(
		module.call(
			"accept_organization",
			compression_preparation.get("organization_token"),
			{
				"summary": "旅行者说过自己叫迪迦，最近也听了许多普通闲聊。",
				"memories": (
					before_compression.get("memories", []) as Array
				).duplicate(true),
				"open_loops": (
					before_compression.get("open_loops", []) as Array
				).duplicate(true),
				"message_updates": [],
			},
		),
		"compression succeeds after retaining the unresolved avatar matter",
	)
	var departure := module.call(
		"build_departure_message_request",
		"departure-test-1",
	) as Dictionary
	_expect_ok(departure, "departure message request builds")
	_expect_equal(departure.get("eligible"), true, "resident is an eligible writer")
	var written := module.call(
		"review_departure_message",
		departure.get("token"),
		{
			"write": true,
			"message": "迪迦，明天也来把名字说清楚吧。",
		},
	) as Dictionary
	_expect_ok(written, "valid departure message becomes a proposal")
	_expect_equal(written.get("wrote"), true, "message result records a write")
	var before_commit := (
		module.call("get_debug_snapshot") as Dictionary
	).get("memory", {}) as Dictionary
	_expect_equal(
		(before_commit.get("sent_messages", []) as Array).size(),
		0,
		"unselected proposal is not recorded as a sent message",
	)
	var committed := module.call(
		"commit_departure_message",
		written.get("proposal"),
	) as Dictionary
	_expect_ok(committed, "selected departure message persists")
	var screened_departure := module.call(
		"build_departure_message_request",
		"departure-test-screened",
	) as Dictionary
	_expect_ok(screened_departure, "screened departure context remains valid")
	_expect_equal(
		screened_departure.get("eligible"),
		false,
		"sent context is not considered again without new avatar memory",
	)
	var public_message := committed.get("message", {}) as Dictionary
	_expect_equal(
		public_message.keys().size(),
		4,
		"public projection contains only display fields",
	)
	_expect_false(
		public_message.has("source_refs"),
		"public projection does not expose memory sources",
	)
	var ordinary := module.call(
		"retrieve_context",
		_base_wake("ordinary-life"),
	) as Dictionary
	var ordinary_prompt := String(ordinary.get("avatar_prompt", ""))
	_expect_equal(
		ordinary.get("mode"),
		"ordinary_life",
		"ordinary wake uses ordinary-life retrieval",
	)
	_expect(
		ordinary_prompt.contains("还想确认旅行者为什么自称迪迦"),
		"active avatar open loop reaches ordinary life",
	)
	_expect_false(
		ordinary_prompt.contains("旅行者亲口说自己叫迪迦"),
		"ordinary life does not inject unrelated avatar memories",
	)
	_expect_false(
		ordinary_prompt.contains("迪迦，明天也来把名字说清楚吧"),
		"ordinary life does not inject sent resident messages",
	)
	var memory_before_resolution := (
		module.call("get_debug_snapshot") as Dictionary
	).get("memory", {}) as Dictionary
	var resolution_preparation := module.call(
		"prepare_context",
		_resolution_conversation_wake(),
	) as Dictionary
	_expect(
		resolution_preparation.has("organization_request"),
		"resolved direct conversation requests organization",
	)
	var resolved_memories := (
		memory_before_resolution.get("memories", []) as Array
	).duplicate(true)
	var resolved_loops := (
		memory_before_resolution.get("open_loops", []) as Array
	).duplicate(true)
	if not resolved_loops.is_empty():
		(resolved_loops[0] as Dictionary)["status"] = "resolved"
		(resolved_loops[0] as Dictionary)["progress"] = "旅行者已经亲口确认"
	var resolution_candidate := {
		"summary": "旅行者确认迪迦就是自己的名字。",
		"memories": resolved_memories,
		"open_loops": resolved_loops,
		"message_updates": [],
	}
	_expect_ok(
		module.call(
			"accept_organization",
			resolution_preparation.get("organization_token"),
			resolution_candidate,
		),
		"world result can explicitly resolve an avatar open loop",
	)
	var refreshed_departure := module.call(
		"build_departure_message_request",
		"departure-test-refreshed",
	) as Dictionary
	_expect_ok(refreshed_departure, "new avatar evidence refreshes departure eligibility")
	_expect_equal(
		refreshed_departure.get("eligible"),
		true,
		"new avatar evidence restores departure eligibility",
	)
	var ordinary_after_resolution := module.call(
		"retrieve_context",
		_base_wake("ordinary-after-resolution"),
	) as Dictionary
	_expect_false(
		String(
			ordinary_after_resolution.get("avatar_prompt", ""),
		).contains("还想确认旅行者为什么自称迪迦"),
		"resolved avatar open loop stops entering ordinary life",
	)
	var capture := module.call("capture_persistent_state") as Dictionary
	_expect_ok(capture, "avatar module captures persistent state")
	var restored := ModuleScript.new(
		_initialization(),
		_test_root.path_join("module-restored"),
		AVATAR_ID,
		"旅行者",
	)
	_expect_ok(
		restored.call(
			"apply_persistent_state",
			capture.get("avatar_memory_state"),
		),
		"avatar module restores into an empty runtime",
	)
	var restored_debug := restored.call("get_debug_snapshot") as Dictionary
	var restored_memory := restored_debug.get("memory", {}) as Dictionary
	_expect_equal(
		(restored_memory.get("sent_messages", []) as Array).size(),
		1,
		"restored module keeps exact sent message",
	)


func _test_active_avatar_conversation_defers_organization() -> void:
	var module := ModuleScript.new(
		_initialization(),
		_test_root.path_join("active-conversation"),
		AVATAR_ID,
		"旅行者",
	)
	var preparation: Dictionary = {}
	for turn_count in [1, 3, 5]:
		preparation = module.call(
			"prepare_context",
			_active_avatar_conversation_wake(turn_count),
		) as Dictionary
		_expect_ok(
			preparation,
			"active avatar conversation evidence remains readable",
		)
		_expect_false(
			preparation.has("organization_request"),
			"active avatar reply is not delayed by memory organization",
		)
	var context := module.call(
		"retrieve_context",
		_active_avatar_conversation_wake(5),
	) as Dictionary
	_expect(
		String(context.get("avatar_prompt", "")).contains("带我去食堂"),
		"unorganized active turns remain available to the immediate reply",
	)


func _test_departure_forces_organization_and_filters_resident_narration() -> void:
	var module := ModuleScript.new(
		_initialization_for("resident-wen-xu", "闻叙"),
		_test_root.path_join("departure-organization"),
		AVATAR_ID,
		"旅行者",
	)
	var preparation := module.call(
		"prepare_context",
		_departure_request_active_wake(),
	) as Dictionary
	_expect_ok(preparation, "active departure request enters avatar evidence")
	_expect_false(
		preparation.has("organization_request"),
		"active conversation still defers ordinary organization",
	)
	var departure_organization := module.call(
		"prepare_departure_organization",
	) as Dictionary
	_expect_ok(
		departure_organization,
		"departure forces pending avatar evidence organization",
	)
	_expect_equal(
		departure_organization.get("triggered"),
		true,
		"pending avatar evidence is organized before departure judgment",
	)
	var request_text := JSON.stringify(
		departure_organization.get("request", {}),
	)
	_expect(
		request_text.contains("找到找不到都给我留个言"),
		"forced organization sees the avatar's explicit message request",
	)
	_expect_false(
		request_text.contains("继续看面前的花苗"),
		"resident-only scene narration is excluded from avatar memory",
	)
	_expect_ok(
		module.call(
			"accept_organization",
			departure_organization.get("token"),
			{
				"summary": "旅行者请闻叙寻找迪迦，并在离开后告知结果。",
				"memories": [],
				"open_loops": [{
					"content": "替旅行者寻找迪迦，找到找不到都要给他留言。",
					"world_time": {
						"day": 2,
						"clock": "18:20",
						"period": "傍晚",
					},
					"source_type": "direct_dialogue",
					"source_person_id": AVATAR_ID,
					"source_refs": [
						"conversation:departure-request:turn:1",
					],
					"status": "active",
					"salience": 4,
					"people": [AVATAR_ID],
					"progress": "尚未告知寻找结果",
				}],
				"message_updates": [],
			},
		),
		"forced departure organization commits the explicit open loop",
	)
	var departure := module.call(
		"build_departure_message_request",
		"departure-request-test",
	) as Dictionary
	_expect_ok(departure, "organized request builds a departure judgment")
	var departure_text := JSON.stringify(departure.get("request", {}))
	_expect(
		departure_text.contains("找到找不到都要给他留言"),
		"departure judgment receives the organized explicit request",
	)
	_expect_false(
		departure_text.contains("花苗"),
		"departure judgment cannot use resident-only flower narration",
	)


func _test_resident_identity_isolation_and_social_propagation() -> void:
	var lin := ModuleScript.new(
		_initialization_for("resident-lin-lan", "林岚"),
		_test_root.path_join("identity-slot-a"),
		AVATAR_ID,
		"旅行者",
	)
	var tang := ModuleScript.new(
		_initialization_for("resident-tang-xiao-man", "唐小满"),
		_test_root.path_join("identity-slot-a"),
		AVATAR_ID,
		"旅行者",
	)
	_expect_ok(
		_organize_identity_claim(
			lin,
			"lin-avatar-claim",
			"resident-lin-lan",
			"林岚",
			"迪迦",
		),
		"first resident remembers the avatar name heard directly",
	)
	_expect_ok(
		_organize_identity_claim(
			tang,
			"tang-avatar-claim",
			"resident-tang-xiao-man",
			"唐小满",
			"咸蛋",
		),
		"second resident remembers a different avatar name heard directly",
	)
	var lin_context := lin.call(
		"retrieve_context",
		_avatar_nearby_wake(),
	) as Dictionary
	var tang_context := tang.call(
		"retrieve_context",
		_avatar_nearby_wake(),
	) as Dictionary
	_expect(
		String(lin_context.get("avatar_prompt", "")).contains("迪迦"),
		"first resident keeps their own direct claim",
	)
	_expect_false(
		String(lin_context.get("avatar_prompt", "")).contains("咸蛋"),
		"different resident memories do not auto-share",
	)
	_expect(
		String(tang_context.get("avatar_prompt", "")).contains("咸蛋"),
		"second resident keeps their own direct claim",
	)
	_expect_false(
		String(tang_context.get("avatar_prompt", "")).contains("迪迦"),
		"second resident has not learned the other claim before social talk",
	)

	var social_preparation: Dictionary = {}
	for index in 4:
		social_preparation = tang.call(
			"prepare_context",
			_identity_hearsay_wake(index),
		) as Dictionary
	_expect(
		social_preparation.has("organization_request"),
		"real resident social turns trigger hearsay organization",
	)
	var tang_memory := (
		tang.call("get_debug_snapshot") as Dictionary
	).get("memory", {}) as Dictionary
	var propagated_memories := (
		tang_memory.get("memories", []) as Array
	).duplicate(true)
	propagated_memories.append({
		"content": "林岚说旅行者曾自称迪迦，与亲口说的咸蛋不一致。",
		"world_time": {"day": 2, "clock": "18:34", "period": "傍晚"},
		"source_type": "hearsay",
		"source_person_id": "resident-lin-lan",
		"source_refs": ["conversation:identity-hearsay-3:turn:1"],
		"status": "disputed",
		"salience": 4,
	})
	_expect_ok(
		tang.call(
			"accept_organization",
			social_preparation.get("organization_token"),
			{
				"summary": "旅行者亲口自称咸蛋，林岚却说他曾自称迪迦。",
				"memories": propagated_memories,
				"open_loops": [],
				"message_updates": [],
			},
		),
		"hearsay from a real resident conversation enters that resident memory",
	)
	var propagated_context := tang.call(
		"retrieve_context",
		_avatar_nearby_wake(),
	) as Dictionary
	_expect(
		String(propagated_context.get("avatar_prompt", "")).contains("咸蛋")
		and String(propagated_context.get("avatar_prompt", "")).contains("迪迦"),
		"resident can notice contradictory avatar names after propagation",
	)

	var fresh_other_slot := ModuleScript.new(
		_initialization_for("resident-lin-lan", "林岚"),
		_test_root.path_join("identity-slot-b"),
		AVATAR_ID,
		"旅行者",
	)
	var fresh_context := fresh_other_slot.call(
		"retrieve_context",
		_avatar_nearby_wake(),
	) as Dictionary
	_expect_equal(
		fresh_context.get("avatar_prompt"),
		"",
		"same resident in another slot starts with isolated avatar memory",
	)
	var lin_capture := lin.call("capture_persistent_state") as Dictionary
	var wrong_resident := ModuleScript.new(
		_initialization_for("resident-tang-xiao-man", "唐小满"),
		_test_root.path_join("identity-cross-resident"),
		AVATAR_ID,
		"旅行者",
	)
	_expect_false(
		(
			wrong_resident.call(
				"apply_persistent_state",
				lin_capture.get("avatar_memory_state"),
			) as Dictionary
		).get("ok"),
		"captured avatar memory cannot be restored into another resident",
	)


func _organize_identity_claim(
	module: RefCounted,
	conversation_id: String,
	resident_id: String,
	resident_name: String,
	claim: String,
) -> Dictionary:
	var preparation := module.call(
		"prepare_context",
		_avatar_identity_wake(
			conversation_id,
			resident_id,
			resident_name,
			claim,
		),
	) as Dictionary
	if not preparation.has("organization_request"):
		return {"ok": false, "errors": ["direct claim did not request organization"]}
	return module.call(
		"accept_organization",
		preparation.get("organization_token"),
		{
			"summary": "旅行者亲口说自己叫%s。" % claim,
			"memories": [{
				"content": "旅行者亲口说自己叫%s。" % claim,
				"world_time": {"day": 2, "clock": "18:20", "period": "傍晚"},
				"source_type": "direct_dialogue",
				"source_person_id": AVATAR_ID,
				"source_refs": [
					"conversation:%s:turn:1" % conversation_id,
				],
				"status": "active",
				"salience": 4,
			}],
			"open_loops": [],
			"message_updates": [],
		},
	) as Dictionary


func _avatar_conversation_wake() -> Dictionary:
	var wake := _base_wake("avatar-conversation")
	wake["events"] = [{
		"event_id": "avatar-conversation-ended",
		"time": {"day": 2, "clock": "18:20", "period": "傍晚"},
		"type": "对话结束",
		"conversation_id": "avatar-talk",
		"turns": [
			{
				"turn_id": 1,
				"speaker_resident_id": AVATAR_ID,
				"speaker": "旅行者",
				"say": "我叫迪迦，我明天想吃屎。",
				"narration": "",
				"photos": [],
			},
			{
				"turn_id": 2,
				"speaker_resident_id": "resident-lin-lan",
				"speaker": "林岚",
				"say": "这名字不像真的。",
				"narration": "",
				"photos": [],
			},
		],
		"reason": "主动结束",
	}]
	return wake


func _avatar_conversation_overlap_wake() -> Dictionary:
	var wake := _avatar_conversation_wake()
	var event := (wake["events"] as Array)[0] as Dictionary
	event["time"] = {"day": 2, "clock": "18:21", "period": "傍晚"}
	(wake["snapshot"] as Dictionary)["conversation"] = {
		"conversation_id": event["conversation_id"],
		"with_resident_id": AVATAR_ID,
		"turns": (event["turns"] as Array).duplicate(true),
	}
	return wake


func _active_avatar_conversation_wake(turn_count: int) -> Dictionary:
	var wake := _base_wake("avatar-active-%d" % turn_count)
	var turns: Array[Dictionary] = []
	for index in turn_count:
		var avatar_turn := index % 2 == 0
		turns.append({
			"turn_id": index + 1,
			"speaker_resident_id": (
				AVATAR_ID if avatar_turn else "resident-lin-lan"
			),
			"speaker": "旅行者" if avatar_turn else "林岚",
			"say": (
				"带我去食堂，第%d次。" % (index + 1)
				if avatar_turn
				else "我听见了。"
			),
			"narration": "",
			"photos": [],
		})
	(wake["snapshot"] as Dictionary)["conversation"] = {
		"conversation_id": "avatar-active",
		"with_resident_id": AVATAR_ID,
		"with": "旅行者",
		"turns": turns,
	}
	wake["events"] = [{
		"event_id": "avatar-active-event-%d" % turn_count,
		"time": {"day": 2, "clock": "18:20", "period": "傍晚"},
		"type": "对方答话",
		"conversation_id": "avatar-active",
		"turn": turns.back().duplicate(true),
	}]
	return wake


func _departure_request_active_wake() -> Dictionary:
	var wake := _base_wake("departure-request-active")
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
			"speaker_resident_id": "resident-wen-xu",
			"speaker": "闻叙",
			"say": "我会找找看。",
			"narration": "我转头继续看面前的花苗",
			"photos": [],
		},
	]
	(wake["snapshot"] as Dictionary)["conversation"] = {
		"conversation_id": "departure-request",
		"with_resident_id": AVATAR_ID,
		"with": "旅行者",
		"turns": turns,
	}
	wake["events"] = [{
		"event_id": "departure-request-turn-2",
		"time": {"day": 2, "clock": "18:20", "period": "傍晚"},
		"type": "对方答话",
		"conversation_id": "departure-request",
		"turn": turns.back().duplicate(true),
	}]
	return wake


func _resident_social_wake() -> Dictionary:
	var wake := _base_wake("resident-social")
	wake["events"] = [{
		"event_id": "resident-social-turn",
		"time": {"day": 2, "clock": "18:30", "period": "傍晚"},
		"type": "旁听",
		"conversation_id": "resident-talk",
		"speaker_resident_ids": ["resident-tang-xiao-man"],
		"speakers": ["唐小满"],
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "旅行者跟我说他叫咸蛋。",
			"narration": "",
			"photos": [],
		},
	}]
	return wake


func _resolution_conversation_wake() -> Dictionary:
	var wake := _base_wake("avatar-resolution")
	wake["events"] = [{
		"event_id": "avatar-resolution-ended",
		"time": {"day": 3, "clock": "09:10", "period": "上午"},
		"type": "对话结束",
		"conversation_id": "avatar-resolution",
		"turns": [
			{
				"turn_id": 1,
				"speaker_resident_id": AVATAR_ID,
				"speaker": "旅行者",
				"say": "不用再确认了，迪迦就是我的名字。",
				"narration": "",
				"photos": [],
			},
			{
				"turn_id": 2,
				"speaker_resident_id": "resident-lin-lan",
				"speaker": "林岚",
				"say": "好，我记住了。",
				"narration": "",
				"photos": [],
			},
		],
		"reason": "主动结束",
	}]
	return wake


func _avatar_identity_wake(
	conversation_id: String,
	resident_id: String,
	resident_name: String,
	claim: String,
) -> Dictionary:
	var wake := _base_wake("%s-ended" % conversation_id)
	wake["events"] = [{
		"event_id": "%s-ended" % conversation_id,
		"time": {"day": 2, "clock": "18:20", "period": "傍晚"},
		"type": "对话结束",
		"conversation_id": conversation_id,
		"turns": [
			{
				"turn_id": 1,
				"speaker_resident_id": AVATAR_ID,
				"speaker": "旅行者",
				"say": "我叫%s。" % claim,
				"narration": "",
				"photos": [],
			},
			{
				"turn_id": 2,
				"speaker_resident_id": resident_id,
				"speaker": resident_name,
				"say": "我记住了。",
				"narration": "",
				"photos": [],
			},
		],
		"reason": "主动结束",
	}]
	return wake


func _identity_hearsay_wake(index: int) -> Dictionary:
	var wake := _base_wake("identity-hearsay-%d" % index)
	wake["events"] = [{
		"event_id": "identity-hearsay-%d" % index,
		"time": {
			"day": 2,
			"clock": "18:%02d" % (31 + index),
			"period": "傍晚",
		},
		"type": "旁听",
		"conversation_id": "identity-hearsay-%d" % index,
		"speaker_resident_ids": ["resident-lin-lan"],
		"speakers": ["林岚"],
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "resident-lin-lan",
			"speaker": "林岚",
			"say": "旅行者曾跟我说，他叫迪迦。第%d次说起。" % (index + 1),
			"narration": "",
			"photos": [],
		},
	}]
	return wake


func _ordinary_social_wake(index: int) -> Dictionary:
	var wake := _base_wake("ordinary-social-%d" % index)
	wake["events"] = [{
		"event_id": "ordinary-social-%d" % index,
		"time": {
			"day": 2,
			"clock": "19:%02d" % index,
			"period": "晚上",
		},
		"type": "旁听",
		"conversation_id": "ordinary-social-%d" % index,
		"speaker_resident_ids": ["resident-tang-xiao-man"],
		"speakers": ["唐小满"],
		"turn": {
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "今天市集上的第%d筐青菜卖完了。" % (index + 1),
			"narration": "",
			"photos": [],
		},
	}]
	return wake


func _avatar_nearby_wake() -> Dictionary:
	var wake := _base_wake("avatar-nearby")
	(wake["snapshot"] as Dictionary)["nearby"] = [{
		"resident_id": AVATAR_ID,
		"name": "旅行者",
		"doing": "站在路边",
	}]
	return wake


func _base_wake(decision_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": {"day": 2, "clock": "18:20", "period": "傍晚"},
			"weather": "晴天",
			"me": {
				"doing": "站在中心广场",
				"current_action": null,
				"body": {"困": "不困", "饿": "不饿", "累": "不累"},
			},
			"nearby": [],
			"place": {"name": "中心广场", "props": []},
			"conversation": null,
		},
		"events": [],
		"action_results": [],
	}


func _initialization() -> Dictionary:
	return _initialization_for("resident-lin-lan", "林岚")


func _initialization_for(resident_id: String, resident_name: String) -> Dictionary:
	var other_id := (
		"resident-tang-xiao-man"
		if resident_id == "resident-lin-lan"
		else "resident-lin-lan"
	)
	var other_name := "唐小满" if other_id == "resident-tang-xiao-man" else "林岚"
	return {
		"me": {
			"resident_id": resident_id,
			"attributes": {
				"name": resident_name,
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
		"residents": [{
			"resident_id": other_id,
			"name": other_name,
			"gender": "女",
			"age": 29,
			"job": "摊主",
			"home": "唐小满家",
			"workplace": "市集",
		}],
		"places": [{
			"name": "中心广场",
			"type": "公共地点",
			"owner": null,
			"owner_resident_id": null,
			"summary": "小镇广场",
			"features": [],
		}],
	}


func _expect_ok(result: Variant, message: String) -> void:
	if not result is Dictionary or not bool((result as Dictionary).get("ok", false)):
		_failures.append("%s: %s" % [message, result])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_false(value: Variant, message: String) -> void:
	if bool(value):
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s: expected %s, got %s" % [message, expected, actual],
		)
