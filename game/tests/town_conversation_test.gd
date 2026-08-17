extends "res://tests/support/TownWorldTestCase.gd"
const ANNOUNCEMENT_RESIDENT_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementResidentRuntime.gd"
)
## 对话与公告 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - town_ui_adapter_conversation_spectator_test.gd
## - town_conversation_photo_contract_test.gd
## - town_world_conversation_test.gd
## - town_ui_adapter_player_conversation_identity_test.gd
## - town_announcement_distribution_integration_test.gd
## - town_relationship_evidence_progress_test.gd
## - town_announcement_long_history_test.gd
## - town_announcement_pending_arrival_test.gd

class WorldHarness extends RefCounted:
	signal world_revision_changed(revision: int)
	signal conversation_changed(conversation_id: String, state: Dictionary)
	signal resident_action_started(resident_name: String, action: Dictionary)
	signal world_restored(summary: Dictionary)

	var revision := 41
	var duplicate_active_conversation := false
	var avatar := {
		"name": "旅行者",
		"conversationId": "",
		"conversation": null,
		"nearby": [],
	}
	var conversations := {
		"conversation-residents": {
			"conversationId": "conversation-residents",
			"participants": ["resident-lin", "resident-tang"],
			"initiator": "resident-lin",
			"turns": [
				{
					"turn_id": 1,
					"speaker_resident_id": "resident-lin",
					"speaker": "林岚",
					"say": "你今天怎么突然问起这个？",
					"narration": "林岚把杯子轻轻放回桌面。",
					"action": {"type": "gesture", "label": "放下杯子"},
					"expression_id": "calm",
					"photos": [],
				},
				{
					"turn_id": 2,
					"speaker_resident_id": "resident-tang",
					"speaker": "唐小满",
					"say": "因为大家都听见了。",
					"narration": "唐小满往前挪了半步。",
					"photos": [],
				},
			],
			"waitingFor": "resident-lin",
			"status": "active",
			"startedAt": {"day": 1, "clock": "10:00"},
			"updatedAt": {"day": 1, "clock": "10:05"},
			"endReason": null,
		},
	}
	var resident_states := {
		"林岚": {
			"name": "林岚",
			"spaceId": "indoor_cafe",
			"currentPlace": "咖啡馆",
			"currentAction": {"action_id": "talk-1", "type": "搭话"},
			"body": {"累": "正常"},
		},
		"唐小满": {
			"name": "唐小满",
			"spaceId": "indoor_cafe",
			"currentPlace": "咖啡馆",
			"currentAction": {"action_id": "talk-2", "type": "答话"},
			"body": {"累": "正常"},
		},
		"顾川": {
			"name": "顾川",
			"spaceId": "indoor_cafe",
			"currentPlace": "咖啡馆",
			"currentAction": {"action_id": "walk-3", "type": "去"},
			"body": {"累": "正常"},
		},
		"陆青": {
			"name": "陆青",
			"spaceId": "indoor_cafe",
			"currentPlace": "咖啡馆",
			"currentAction": {},
			"body": {"累": "很累"},
		},
		"许安": {
			"name": "许安",
			"spaceId": "indoor_cafe",
			"currentPlace": "咖啡馆",
			"currentAction": {"action_id": "organize-5", "type": "整理"},
			"body": {"累": "正常"},
		},
	}

	func get_world_revision() -> int:
		return revision

	func get_player_avatar_state() -> Dictionary:
		return avatar.duplicate(true)

	func get_active_conversations() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for value: Variant in conversations.values():
			var conversation := value as Dictionary
			if str(conversation.get("status", "")) == "active":
				result.append(conversation.duplicate(true))
				if duplicate_active_conversation:
					result.append(conversation.duplicate(true))
		return result

	func get_conversation(conversation_id: String) -> Dictionary:
		return (conversations.get(conversation_id, {}) as Dictionary).duplicate(true)

	func get_resident_state(resident_name: String) -> Dictionary:
		return (resident_states.get(resident_name, {}) as Dictionary).duplicate(true)

	func get_all_resident_states() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for value: Variant in resident_states.values():
			result.append((value as Dictionary).duplicate(true))
		return result

	func emit_action_started(
		resident_name: String,
		action_id: String,
		action_type: String,
	) -> void:
		var state := resident_states.get(resident_name, {}) as Dictionary
		var action := {
			"action_id": action_id,
			"type": action_type,
			"line": "公开动作",
			"startedAt": {"day": 1, "clock": "10:05"},
		}
		state["currentAction"] = action.duplicate(true)
		resident_states[resident_name] = state
		revision += 1
		resident_action_started.emit(resident_name, action.duplicate(true))
		world_revision_changed.emit(revision)

	func get_lifecycle_state() -> Dictionary:
		return {"state": "running", "started": true, "paused": false, "pauseReasons": []}

	func get_time() -> Dictionary:
		return {"day": 1, "clock": "10:05", "period": "morning"}

	func get_weather() -> String:
		return "sunny"

	func get_announcements() -> Array:
		return []
class RuntimeHarness extends Node:
	var player_mutation_count := 0
	var hidden_resident_names: Dictionary = {}
	var resident_anchors := {
		"林岚": {"x": 300.0, "y": 420.0},
		"唐小满": {"x": 500.0, "y": 420.0},
		"顾川": {"x": 760.0, "y": 420.0},
		"陆青": {"x": 920.0, "y": 420.0},
		"许安": {"x": 1080.0, "y": 420.0},
	}

	func get_resident_identity_snapshot() -> Dictionary:
		return {
			"status": "confirmed",
			"residents": [
				{"residentId": "resident-lin", "residentName": "林岚"},
				{"residentId": "resident-tang", "residentName": "唐小满"},
				{"residentId": "resident-gu", "residentName": "顾川"},
				{"residentId": "resident-lu", "residentName": "陆青"},
				{"residentId": "resident-xu", "residentName": "许安"},
			],
		}

	func get_resident_screen_anchor(resident_name: String) -> Dictionary:
		return (
			resident_anchors.get(resident_name, {}) as Dictionary
		).duplicate(true)

	func get_resident_head_screen_anchor(
		resident_name: String,
	) -> Dictionary:
		var anchor := get_resident_screen_anchor(resident_name)
		if anchor.is_empty():
			return {
				"valid": false,
				"visible": false,
				"kind": "head",
				"coordinateSpace": "viewport_logical",
				"x": 0.0,
				"y": 0.0,
				"spaceId": "",
			}
		return {
			"valid": true,
			"visible": not hidden_resident_names.has(resident_name),
			"kind": "head",
			"coordinateSpace": "viewport_logical",
			"x": float(anchor.get("x", 0.0)),
			"y": float(anchor.get("y", 0.0)),
			"spaceId": "indoor_cafe",
		}

	func get_resident_screen_projection(resident_name: String) -> Dictionary:
		var anchor := get_resident_screen_anchor(resident_name)
		return {
			"available": not anchor.is_empty(),
			"offscreen": false,
			"screenAnchor": anchor,
		}

	func get_runtime_state() -> Dictionary:
		return {
			"playerAvatarEnabled": false,
			"avatarMode": "observer",
			"viewMode": "town",
			"visibleResidents": ["林岚", "唐小满", "顾川", "陆青", "许安"],
			"residents": [
				{
					"name": "林岚",
					"spaceId": "indoor_cafe",
					"currentAction": {"action_id": "walk-owned", "type": "去"},
					"body": {"累": "正常"},
				},
				{
					"name": "唐小满",
					"spaceId": "indoor_cafe",
					"currentAction": {"action_id": "talk-2", "type": "答话"},
					"body": {"累": "正常"},
				},
				{
					"name": "顾川",
					"spaceId": "indoor_cafe",
					"currentAction": {"action_id": "walk-3", "type": "去"},
					"body": {"累": "正常"},
				},
				{
					"name": "陆青",
					"spaceId": "indoor_cafe",
					"currentAction": {},
					"body": {"累": "很累"},
				},
				{
					"name": "许安",
					"spaceId": "indoor_cafe",
					"currentAction": {"action_id": "organize-5", "type": "整理"},
					"body": {"累": "正常"},
				},
			],
		}

	func player_start_conversation(_resident_name: String, _say: String, _narration: String) -> Dictionary:
		player_mutation_count += 1
		return {"ok": true}

	func player_reply_conversation(
		_conversation_id: String,
		_say: String,
		_narration: String,
		_end: bool,
	) -> Dictionary:
		player_mutation_count += 1
		return {"ok": true}

	func player_end_conversation(_conversation_id: String, _narration: String) -> Dictionary:
		player_mutation_count += 1
		return {"ok": true}

	func player_reject_conversation(_conversation_id: String, _narration: String) -> Dictionary:
		player_mutation_count += 1
		return {"ok": true}
class GatewayHarness extends Node:
	var connected: Array[String] = ["林岚", "唐小满", "顾川", "陆青", "许安"]

	func get_connected_resident_names() -> Array[String]:
		return connected.duplicate()

	func get_errors() -> Array:
		return []
class MissingGatewayHarness extends Node:
	func get_errors() -> Array:
		return []
class WorldHarnessConversationPhotoContract extends RefCounted:
	signal world_revision_changed(revision: int)
	signal conversation_changed(conversation_id: String, state: Dictionary)

	var revision := 17
	var avatar := {
		"name": "旅行者",
		"conversationId": "conversation-photo",
		"conversation": null,
		"nearby": [],
	}
	var conversation := {
		"conversationId": "conversation-photo",
		"participants": ["旅行者", "林岚"],
		"turns": [
			{
				"turn_id": 1,
				"speaker_resident_id": "resident-lin",
				"speaker": "林岚",
				"say": "给我看看吧。",
				"narration": "林岚看向旅行者。",
				"photos": [],
			},
		],
		"waitingFor": "旅行者",
		"status": "active",
	}

	func get_world_revision() -> int:
		return revision

	func get_player_avatar_state() -> Dictionary:
		return avatar.duplicate(true)

	func get_conversation(conversation_id: String) -> Dictionary:
		if conversation_id != String(conversation.get("conversationId", "")):
			return {}
		return conversation.duplicate(true)

	func get_active_conversations() -> Array[Dictionary]:
		return []

	func get_lifecycle_state() -> Dictionary:
		return {
			"state": "running",
			"started": true,
			"paused": false,
			"pauseReasons": [],
		}

	func get_time() -> Dictionary:
		return {"day": 1, "clock": "10:05", "period": "morning"}

	func get_weather() -> String:
		return "sunny"

	func get_announcements() -> Array:
		return []

	func get_all_resident_states() -> Array[Dictionary]:
		return [{
			"name": "林岚",
			"spaceId": "town",
			"currentPlace": "中心广场",
			"currentAction": {"action_id": "talk-1", "type": "答话"},
			"body": {"累": "正常"},
		}]

	func get_resident_state(resident_name: String) -> Dictionary:
		if resident_name != "林岚":
			return {}
		return get_all_resident_states()[0].duplicate(true)
class RuntimeHarnessConversationPhotoContract extends Node:
	var reply_ok := true
	var text_reply_count := 0
	var photo_reply_count := 0
	var last_photos: Array = []

	func get_resident_identity_snapshot() -> Dictionary:
		return {
			"status": "confirmed",
			"residents": [{
				"residentId": "resident-lin",
				"residentName": "林岚",
			}],
		}

	func get_runtime_state() -> Dictionary:
		return {
			"playerAvatarEnabled": true,
			"avatarMode": "avatar",
			"viewMode": "town",
			"visibleResidents": ["林岚"],
			"residents": [],
		}

	func player_reply_conversation(
		_conversation_id: String,
		_say: String,
		_narration: String,
		_end: bool,
	) -> Dictionary:
		text_reply_count += 1
		return {"ok": reply_ok, "errorCode": "" if reply_ok else "REPLY_REJECTED"}

	func player_reply_conversation_with_photos(
		_conversation_id: String,
		_say: String,
		_narration: String,
		photos: Array,
		_end: bool,
	) -> Dictionary:
		photo_reply_count += 1
		last_photos = photos.duplicate(true)
		return {"ok": reply_ok, "errorCode": "" if reply_ok else "REPLY_REJECTED"}
class GatewayHarnessConversationPhotoContract extends Node:
	var store: RefCounted = PHOTO_STORE.new()
	var prepare_ok := true

	func get_connected_resident_names() -> Array[String]:
		return ["林岚"]

	func get_errors() -> Array:
		return []

	func can_attach_photo_for_resident(resident_id: String) -> bool:
		return resident_id == "resident-lin"

	func stage_conversation_photo(
		resident_id: String,
		path: String,
	) -> Dictionary:
		return store.call("stage_file", path, resident_id) as Dictionary

	func has_staged_conversation_photo(
		resident_id: String,
		ref: String,
		mime_type: String,
	) -> bool:
		return bool(store.call(
			"has_staged_photo",
			ref,
			mime_type,
			resident_id,
		))

	func prepare_conversation_photo_commit(
		resident_id: String,
		ref: String,
		mime_type: String,
	) -> bool:
		return (
			prepare_ok
			and bool(store.call(
				"prepare_photo_commit",
				ref,
				mime_type,
				resident_id,
			))
		)

	func commit_conversation_photo(
		resident_id: String,
		ref: String,
		mime_type: String,
	) -> bool:
		return bool(store.call(
			"commit_photo",
			ref,
			mime_type,
			resident_id,
		))

	func discard_staged_conversation_photo(
		resident_id: String,
		ref: String,
	) -> bool:
		return bool(store.call(
			"discard_staged_photo",
			ref,
			resident_id,
		))

	func resolve_conversation_photo_preview(
		ref: String,
		mime_type: String,
	) -> Dictionary:
		return store.call(
			"resolve_photo_preview",
			ref,
			mime_type,
		) as Dictionary

	func snapshot() -> Dictionary:
		return store.call("audit_snapshot") as Dictionary
class WorldHarnessUiAdapterPlayerConversationIdentity extends RefCounted:
	signal world_revision_changed(revision: int)
	signal conversation_changed(conversation_id: String, state: Dictionary)

	var revision := 60
	var avatar := {
		"residentId": "player-avatar",
		"name": "旅行者",
		"conversationId": "",
		"conversation": null,
		"nearby": ["林岚", "唐小满", "闻叙"],
		"position": Vector2.ZERO,
		"currentPlace": "中央广场",
		"spaceId": "town_outdoor",
		"regionId": "central_square",
	}
	var conversations: Dictionary = {}

	func get_world_revision() -> int:
		return revision

	func get_player_avatar_state() -> Dictionary:
		return avatar.duplicate(true)

	func get_conversation(conversation_id: String) -> Dictionary:
		return (
			conversations.get(conversation_id, {}) as Dictionary
		).duplicate(true)

	func get_active_conversations() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for value: Variant in conversations.values():
			if (
				value is Dictionary
				and str((value as Dictionary).get("status", "")) == "active"
			):
				result.append((value as Dictionary).duplicate(true))
		return result

	func get_resident_state(_resident_name: String) -> Dictionary:
		return {"position": Vector2.ZERO}
class RuntimeHarnessUiAdapterPlayerConversationIdentity extends Node:
	var started_names: Array[String] = []
	var world: WorldHarnessUiAdapterPlayerConversationIdentity

	func get_resident_identity_snapshot() -> Dictionary:
		return {
			"status": "confirmed",
			"residents": RESIDENTS.duplicate(true),
		}

	func get_runtime_state() -> Dictionary:
		return {
			"playerAvatarEnabled": true,
			"avatarMode": "avatar_active",
		}

	func get_resident_screen_anchor(_resident_name: String) -> Dictionary:
		return {"x": 640.0, "y": 360.0}

	func get_resident_head_screen_anchor(
		_resident_name: String,
	) -> Dictionary:
		return {
			"valid": true,
			"visible": true,
			"kind": "head",
			"coordinateSpace": "viewport_logical",
			"x": 640.0,
			"y": 360.0,
			"spaceId": "town_outdoor",
		}

	func player_start_conversation(
		resident_name: String,
		_say: String,
		_narration: String,
	) -> Dictionary:
		started_names.append(resident_name)
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"worldRevision": 60,
		}

	func player_end_conversation(
		conversation_id: String,
		_narration: String,
	) -> Dictionary:
		if world == null or not world.conversations.has(conversation_id):
			return {
				"ok": false,
				"errorCode": "CONVERSATION_COMMAND_REJECTED",
				"retryable": false,
				"worldRevision": world.revision if world != null else 0,
			}
		var conversation := (
			world.conversations[conversation_id] as Dictionary
		)
		var turns := conversation.get("turns", []) as Array
		turns.append({
			"turn_id": turns.size() + 1,
			"speaker_resident_id": "player-avatar",
			"speaker": "旅行者",
			"say": "",
			"narration": "旅行者结束交谈。",
			"photos": [],
		})
		conversation["status"] = "ended"
		conversation["waitingFor"] = null
		conversation["endReason"] = "主动结束"
		conversation["endedAt"] = {"day": 1, "hour": 9, "minute": 10}
		world.avatar["conversationId"] = ""
		world.avatar["conversation"] = null
		world.revision += 1
		world.conversation_changed.emit(
			conversation_id,
			conversation.duplicate(true),
		)
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"worldRevision": world.revision,
		}
class GatewayHarnessUiAdapterPlayerConversationIdentity extends Node:
	func get_connected_resident_names() -> Array[String]:
		return ["林岚", "唐小满", "闻叙"]

	func get_errors() -> Array:
		return []

	func can_attach_photo_for_resident(_resident_id: String) -> bool:
		return false

const ADAPTER := preload("res://world/presentation/ui/TownUiAdapter.gd")
const UNIFIED_CONVERSATION_SCENE := preload(
	"res://ui/conversation_unified/UnifiedConversationScreen.tscn"
)
const GATEWAY := preload("res://world/integration/TownWorldAgentGateway.gd")
const AGENT_PROVIDER_SERVICE := preload(
	"res://world/integration/TownAgentProviderService.gd"
)
const PHOTO_STORE := preload(
	"res://world/integration/TownConversationPhotoStore.gd"
)
const SCREEN := preload(
	"res://ui/conversation_unified/UnifiedConversationScreen.tscn"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const RESIDENTS := [
	{"residentId": "resident-lin", "residentName": "林岚"},
	{"residentId": "resident-tang", "residentName": "唐小满"},
	{"residentId": "resident-wen", "residentName": "闻叙"},
]
const CONTRACT := preload("res://agent/AgentContract.gd")
const MANAGER_ID := "resident_zhao_tang_01"
const POSTAL_ID := "resident_lin_lan_01"
const SPEAKER_ID := "resident_a_he_01"
const LISTENER_ID := "resident_tang_xiaoman_01"
const BYSTANDER_ID := "resident_he_yu_01"
const NOTICE_RECIPIENT_ID := "resident_gu_chuan_01"
const NOTICE_TEXT := "诊所今天傍晚提前关门。"
const PROGRESS := preload(
	"res://world/runtime/relationship/TownRelationshipEvidenceProgress.gd"
)
const MEMORY_SYSTEM := preload(
	"res://agent/memory/ResidentMemorySystem.gd"
)
const TestData := preload(
	"res://tests/support/AgentMemoryTestData.gd"
)
const UserTestDataCleanerScript := preload(
	"res://tests/support/UserTestDataCleaner.gd"
)
const FORMAL_OPENING := preload(
	"res://tests/support/TownWorldFormalOpeningTestHelper.gd"
)

var _announcement_event_count := 0
var _test_root := "user://tests/town-relationship-evidence-progress/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	# These scenarios yield while waiting for UI frames. Keep the suite strictly
	# sequential so a later fixture cannot mutate or free an earlier screen.
	await _scenario_ui_adapter_conversation_spectator()
	await _scenario_conversation_photo_contract()
	_scenario_conversation()
	await _scenario_ui_adapter_player_conversation_identity()
	_scenario_announcement_distribution_integration()
	_scenario_player_announcement_priority()
	_scenario_relationship_evidence_progress()
	_scenario_announcement_long_history()
	_scenario_announcement_pending_arrival()
	_finish_suite("TOWN_CONVERSATION_PASS")


func _scenario_ui_adapter_conversation_spectator() -> void:
	var world := WorldHarness.new()
	var runtime := RuntimeHarness.new()
	var gateway := GatewayHarness.new()
	var adapter := ADAPTER.new()
	root.add_child(runtime)
	root.add_child(gateway)
	root.add_child(adapter)
	adapter.call("bind_runtime", runtime, world, gateway, {
		"source": "runtime",
		"capabilityMode": "development",
		"formalReady": false,
	})
	adapter.call(
		"_on_hud_resident_reaction_created",
		"林岚",
		{
			"reactionId": "announcement-reaction-1",
			"decisionId": "decision-announcement-1",
			"sourceActionId": "",
			"sourceEventId": "event-announcement-1",
			"announcementId": "announcement-1",
			"residentId": "resident-lin",
			"text": "这场电影我想去看看。",
			"reactionKind": "announcement",
			"worldRevision": 41,
		},
	)
	var announcement_reactions := (
		adapter.get("_hud_public_thoughts") as Dictionary
	)
	_expect_equal(
		announcement_reactions.size(),
		1,
		"announcement reaction reaches the resident head-bubble queue",
	)
	if not announcement_reactions.is_empty():
		var announcement_reaction := (
			announcement_reactions.values()[0] as Dictionary
		)
		_expect_equal(
			announcement_reaction.get("actionId"),
			"event-announcement-1",
			"head-bubble identity can use an announcement event source",
		)
		_expect_equal(
			announcement_reaction.get("publicThought"),
			"这场电影我想去看看。",
			"head bubble preserves the resident-authored announcement thought",
		)
		_expect_equal(
			announcement_reaction.get("thoughtKind"),
			"announcement_reaction",
			"announcement response uses its own HUD semantic",
		)
		var reaction_item := adapter.call(
			"_hud_public_thought_item",
			"announcement-reaction-1",
			"event-announcement-1",
			"resident-lin",
			"林岚",
			"这场电影我想去看看。",
			41,
			0,
			10000,
			"town_outdoor",
			"announcement_reaction",
			{"announcementId": "announcement-1"},
		) as Dictionary
		var reaction_action := reaction_item.get("action", {}) as Dictionary
		_expect_equal(
			reaction_action.get("intent"),
			"town_hud.open_town_log",
			"公告回应气泡打开右侧事件链，而不是公告编辑页",
		)
		_expect_equal(
			(reaction_action.get("payload", {}) as Dictionary).get("threadId"),
			"announcement:announcement-1",
			"公告回应直接定位到对应事件链",
		)

	var initial := adapter.call("get_view_model", "conversation") as Dictionary
	_expect_complete_view_model(initial)
	var initial_data := initial.get("data", {}) as Dictionary
	var spectator := initial_data.get("spectator", {}) as Dictionary
	_expect_equal(initial.get("status"), "ready", "public spectator contract is ready")
	_expect_equal(initial_data.get("displayMode"), "spectator", "idle player state uses spectator projection")
	_expect_equal(initial_data.get("formalReady"), true, "formal public spectator interface is explicit")
	_expect_equal(initial_data.get("identityStatus"), "confirmed", "identity snapshot is authoritative")
	_expect_equal(spectator.get("panelOpen"), false, "entry bubbles do not auto-open the panel")
	_expect_equal((spectator.get("activeConversations", []) as Array).size(), 1, "resident conversation is projected")
	var summary := (spectator.get("activeConversations", []) as Array)[0] as Dictionary
	_expect_equal(summary.get("participantIds"), ["resident-lin", "resident-tang"], "stable IDs are projected")
	_expect_equal(summary.get("participantNames"), ["林岚", "唐小满"], "display names are projected")
	_expect_equal(summary.get("canSpectate"), true, "connected resident pair is spectatable")
	_expect_equal(
		(summary.get("entryBubble", {}) as Dictionary).get("screenAnchor"),
		{"x": 400.0, "y": 420.0},
		"entry anchor is the presentation midpoint",
	)
	runtime.hidden_resident_names["唐小满"] = true
	world.revision += 1
	world.world_revision_changed.emit(world.revision)
	var hidden_conversation := (
		(adapter.call("get_view_model", "conversation") as Dictionary)
		.get("data", {}) as Dictionary
	)
	var hidden_summary := (
		(
			(hidden_conversation.get("spectator", {}) as Dictionary)
			.get("activeConversations", []) as Array
		)[0] as Dictionary
	)
	_expect_equal(
		(hidden_summary.get("entryBubble", {}) as Dictionary).get(
			"visible",
		),
		false,
		"conversation entry hides when either participant leaves the viewport",
	)
	runtime.hidden_resident_names.clear()
	world.revision += 1
	world.world_revision_changed.emit(world.revision)
	var hud := adapter.call("get_view_model", "town_hud") as Dictionary
	var far_activity := (
		(hud.get("data", {}) as Dictionary).get("farResidentActivity", {})
		as Dictionary
	)
	_expect_equal(
		far_activity.get("revision"),
		world.revision,
		"far projection uses the World revision",
	)
	_expect_equal(far_activity.get("visibleBudget"), 3, "far projection has the frozen budget")
	var far_items := far_activity.get("items", []) as Array
	_expect_equal(
		far_items.size(),
		3,
		"binding combines the active conversation with current resident semantics",
	)
	_expect_equal(
		far_activity.get("aggregateCount"),
		0,
		"only newly confirmed resident actions enter the transient aggregate",
	)
	var conversation_item := far_items[0] as Dictionary
	_expect_equal(
		conversation_item.get("kind"),
		"spectator_conversation",
		"resident conversation has first priority",
	)
	_expect_equal(
		conversation_item.get("bubbleText"),
		"你今天怎么突然问起这个？",
		"far conversation starts with the confirmed speech text",
	)
	_expect_equal(
		conversation_item.get("participantIds"),
		["resident-lin", "resident-tang"],
		"far conversation preserves stable participant IDs",
	)
	_expect(
		not conversation_item.has("screenAnchor"),
		"far conversation no longer embeds an anchor copy; the layer reads live anchors",
	)
	_expect_equal(
		(conversation_item.get("action", {}) as Dictionary).get("intent"),
		"conversation.spectator.select",
		"far conversation reuses the existing spectator select intent",
	)
	_expect_equal(
		((conversation_item.get("action", {}) as Dictionary).get("payload", {}) as Dictionary)
		.get("conversationId"),
		"conversation-residents",
		"far conversation action carries only the conversation ID",
	)
	_expect_equal(
		conversation_item.get("anchorPolicy"),
		"live_resident_head",
		"conversation reads its participants' live head positions",
	)
	_expect_equal(
		conversation_item.get("motionPolicy"),
		"follow_resident",
		"conversation bubble follows its participants while active",
	)
	_expect_equal(
		conversation_item.get("expiresAtMsec"),
		0,
		"active conversation persists until the World ends it",
	)
	_expect(
		not conversation_item.has("animationHint"),
		"conversation snapshot does not request bounce or breathing animation",
	)
	var conversation_started_at := int(
		conversation_item.get("startedAtMsec", 0)
	)
	world.emit_action_started("顾川", "walk-new", "去")
	world.emit_action_started("陆青", "tired-new", "整理")
	world.emit_action_started("许安", "ordinary-new", "整理")
	far_activity = (
		((adapter.call("get_view_model", "town_hud") as Dictionary)
		.get("data", {}) as Dictionary).get("farResidentActivity", {}) as Dictionary
	)
	far_items = far_activity.get("items", []) as Array
	_expect_equal(
		far_items.size(),
		3,
		"conversation keeps priority while two resident activities fill the far budget",
	)
	_expect_equal(
		far_activity.get("aggregateCount"),
		0,
		"ordinary action events do not create hidden transient aggregation",
	)
	conversation_item = far_items[0] as Dictionary
	world.duplicate_active_conversation = true
	runtime.resident_anchors["林岚"] = {"x": 30.0, "y": 40.0}
	runtime.resident_anchors["唐小满"] = {"x": 70.0, "y": 40.0}
	world.conversation_changed.emit(
		"conversation-residents",
		(world.conversations["conversation-residents"] as Dictionary).duplicate(true),
	)
	far_activity = (
		((adapter.call("get_view_model", "town_hud") as Dictionary)
		.get("data", {}) as Dictionary).get("farResidentActivity", {}) as Dictionary
	)
	_expect_equal(
		(far_activity.get("items", []) as Array).size(),
		3,
		"duplicate conversation facts do not duplicate a far overlay",
	)
	_expect_equal(
		far_activity.get("aggregateCount"),
		0,
		"duplicate conversation facts do not invent transient aggregation",
	)
	conversation_item = (far_activity.get("items", []) as Array)[0] as Dictionary
	_expect(
		not conversation_item.has("screenAnchor"),
		"duplicate conversation facts still embed no anchor copy",
	)
	_expect_equal(
		conversation_item.get("startedAtMsec"),
		conversation_started_at,
		"duplicate conversation facts cannot restart the snapshot",
	)
	world.duplicate_active_conversation = false
	var confirmed_far := far_activity.duplicate(true)
	(world.conversations["conversation-residents"] as Dictionary)["status"] = "ended"
	world.world_revision_changed.emit(world.revision - 1)
	_expect_equal(
		((adapter.call("get_view_model", "town_hud") as Dictionary)
		.get("data", {}) as Dictionary).get("farResidentActivity", {}),
		confirmed_far,
		"late World revision cannot replace confirmed far activity",
	)
	(world.conversations["conversation-residents"] as Dictionary)["status"] = "active"
	var selected := spectator.get("selectedConversation", {}) as Dictionary
	_expect_equal(selected.get("placeId"), "indoor_cafe", "World space is the stable place ID")
	_expect_equal(selected.get("placeLabel"), "咖啡馆", "World place label is projected")
	_expect_equal(((selected.get("observer", {}) as Dictionary).get("canSpeak")), false, "spectator cannot speak")
	var messages := initial_data.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "confirmed World turns are projected")
	var first_message := messages[0] as Dictionary
	var second_message := messages[1] as Dictionary
	_expect_equal(first_message.get("speakerId"), "resident-lin", "World speaker ID is preserved")
	_expect_equal(first_message.get("expressionId"), "calm", "public expression ID is passed through")
	_expect_equal(first_message.get("action"), {"type": "gesture", "label": "放下杯子"}, "public action is passed through")
	_expect_equal(second_message.get("expressionId"), "", "missing expression is not invented")
	for action_key in ["start", "reply", "end", "reject"]:
		var action := (initial.get("actions", {}) as Dictionary).get(action_key, {}) as Dictionary
		_expect_equal(action.get("enabled"), false, "%s is read-only" % action_key)
		_expect_equal(action.get("disabledReason"), "SPECTATOR_READ_ONLY", "%s has stable read-only reason" % action_key)

	var select_result := adapter.call("dispatch", "conversation.spectator.select", {
		"conversationId": "conversation-residents",
	}) as Dictionary
	_expect(bool(select_result.get("ok", false)), "declared spectator select intent succeeds")
	var opened := adapter.call("get_view_model", "conversation") as Dictionary
	var opened_data := opened.get("data", {}) as Dictionary
	_expect_equal(
		((opened_data.get("spectator", {}) as Dictionary).get("panelOpen")),
		true,
		"select intent opens the read-only panel",
	)
	var confirmed_data := opened_data.duplicate(true)
	var forbidden := adapter.call("dispatch", "conversation.reply", {"say": "不应发送"}) as Dictionary
	_expect_equal(forbidden.get("errorCode"), "SPECTATOR_READ_ONLY", "speech is rejected while spectating")
	_expect_equal(runtime.player_mutation_count, 0, "spectator never calls player conversation mutation methods")
	var rejected := adapter.call("get_view_model", "conversation") as Dictionary
	_expect_equal(
		rejected.get("data"),
		confirmed_data,
		"read-only rejection preserves the last confirmed spectator data",
	)
	_expect_equal((rejected.get("operation", {}) as Dictionary).get("status"), "rejected", "read-only operation is rejected")
	var changed_conversation := world.conversations["conversation-residents"] as Dictionary
	var changed_turns := changed_conversation.get("turns", []) as Array
	(changed_turns[0] as Dictionary)["say"] = "这条迟到刷新不应覆盖拒绝前的数据。"
	world.revision += 1
	world.world_revision_changed.emit(world.revision)
	_expect_equal(
		(adapter.call("get_view_model", "conversation") as Dictionary).get("data"),
		confirmed_data,
		"rejected operation keeps confirmed data across a later World refresh",
	)

	var before_unknown := (rejected.get("data", {}) as Dictionary).duplicate(true)
	var unknown := adapter.call("dispatch", "conversation.spectator.select", {
		"conversationId": "conversation-missing",
	}) as Dictionary
	_expect_equal(unknown.get("errorCode"), "SPECTATOR_SELECTION_REJECTED", "unknown selection has stable error")
	_expect_equal(
		(adapter.call("get_view_model", "conversation") as Dictionary).get("data"),
		before_unknown,
		"selection rejection preserves confirmed data",
	)
	var reopen := adapter.call("dispatch", "conversation.spectator.select", {
		"conversationId": "conversation-residents",
	}) as Dictionary
	_expect(bool(reopen.get("ok", false)), "a later confirmed select clears rejected state")

	gateway.connected = ["林岚", "顾川", "陆青", "许安"]
	world.revision += 1
	world.world_revision_changed.emit(world.revision)
	var disconnected := adapter.call("get_view_model", "conversation") as Dictionary
	var disconnected_summary := (
		(((disconnected.get("data", {}) as Dictionary).get("spectator", {}) as Dictionary)
		.get("activeConversations", []) as Array)[0] as Dictionary
	)
	_expect_equal(disconnected_summary.get("canSpectate"), false, "Gateway connection state disables spectator entry")
	_expect_equal(disconnected_summary.get("disabledReason"), "SPECTATOR_PARTICIPANT_NOT_CONNECTED", "disconnect reason is stable")
	_expect_equal(
		(disconnected_summary.get("entryBubble", {}) as Dictionary).get("visible"),
		false,
		"disconnected pair has no actionable entry bubble",
	)
	far_activity = (
		((adapter.call("get_view_model", "town_hud") as Dictionary)
		.get("data", {}) as Dictionary).get("farResidentActivity", {}) as Dictionary
	)
	conversation_item = (far_activity.get("items", []) as Array)[0] as Dictionary
	_expect_equal(
		(conversation_item.get("action", {}) as Dictionary).get("enabled"),
		false,
		"far spectator action follows the public Gateway connection state",
	)
	_expect_equal(
		(conversation_item.get("action", {}) as Dictionary).get("disabledReason"),
		"SPECTATOR_PARTICIPANT_NOT_CONNECTED",
		"far spectator action preserves the stable disabled reason",
	)

	gateway.connected = ["林岚", "唐小满", "顾川", "陆青", "许安"]
	var ended := world.conversations["conversation-residents"] as Dictionary
	ended["status"] = "ended"
	ended["waitingFor"] = null
	ended["endReason"] = "一方离开"
	world.revision += 1
	world.conversation_changed.emit("conversation-residents", ended.duplicate(true))
	var ended_vm := adapter.call("get_view_model", "conversation") as Dictionary
	var ended_spectator := (ended_vm.get("data", {}) as Dictionary).get("spectator", {}) as Dictionary
	_expect_equal((ended_spectator.get("activeConversations", []) as Array).size(), 0, "ended conversation leaves active list")
	_expect_equal(
		(ended_spectator.get("selectedConversation", {}) as Dictionary).get("status"),
		"ended",
		"selected confirmed history remains visible after World end",
	)
	_expect_equal(
		(ended_spectator.get("selectedConversation", {}) as Dictionary).get("endReason"),
		"一方离开",
		"public end reason is preserved",
	)
	far_activity = (
		((adapter.call("get_view_model", "town_hud") as Dictionary)
		.get("data", {}) as Dictionary).get("farResidentActivity", {}) as Dictionary
	)
	var ended_far_items := far_activity.get("items", []) as Array
	var ended_far_kinds: Array[String] = []
	for ended_item_value: Variant in ended_far_items:
		var ended_item := ended_item_value as Dictionary
		ended_far_kinds.append(String(ended_item.get("kind", "")))
	_expect(
		ended_far_kinds.has("spectator_conversation"),
		"ended conversation keeps the current speech bubble until playback finishes",
	)
	var ended_bubble: Dictionary = {}
	for ended_item_value: Variant in ended_far_items:
		var ended_item := ended_item_value as Dictionary
		if String(ended_item.get("kind", "")) == "spectator_conversation":
			ended_bubble = ended_item
			break
	_expect(
		String(ended_bubble.get("bubbleText", "")) != "旁观对话",
		"far conversation uses the confirmed speech text instead of the spectator label",
	)
	_expect_equal(
		far_activity.get("aggregateCount"),
		0,
		"conversation end keeps ordinary action events out of aggregation",
	)
	world.world_restored.emit({"worldRevision": world.revision})
	far_activity = (
		((adapter.call("get_view_model", "town_hud") as Dictionary)
		.get("data", {}) as Dictionary).get("farResidentActivity", {}) as Dictionary
	)
	_expect_equal(
		(far_activity.get("items", []) as Array).size(),
		3,
		"World restore clears snapshots but keeps current resident semantics",
	)
	world.emit_action_started("许安", "ordinary-new", "整理")
	far_activity = (
		((adapter.call("get_view_model", "town_hud") as Dictionary)
		.get("data", {}) as Dictionary).get("farResidentActivity", {}) as Dictionary
	)
	_expect_equal(
		(far_activity.get("items", []) as Array).size(),
		3,
		"a fresh confirmed action remains behind the current semantic budget",
	)

	var page := UNIFIED_CONVERSATION_SCENE.instantiate()
	page.call("bind_town_ui_adapter", adapter)
	root.add_child(page)
	await process_frame
	await process_frame
	var gate := page.call("runtime_gate_snapshot") as Dictionary
	_expect_equal(
		gate.get("pageId"),
		"unified_conversation",
		"正式旁观链必须消费统一聊天页",
	)
	_expect_equal(
		gate.get("mode"),
		"spectator",
		"统一聊天页必须进入只读旁观模式",
	)
	_expect_equal(
		gate.get("contractAvailable"),
		true,
		"统一聊天页必须消费正式 Adapter 旁观投影",
	)
	_expect_equal(
		gate.get("composerVisible"),
		false,
		"旁观模式不得显示输入、照片或发送区",
	)
	_expect_equal(
		gate.get("runtimeMockUsed"),
		false,
		"统一聊天页不得消费运行时 mock",
	)
	page.call("unbind_town_ui_adapter")
	page.free()

	world.conversations["conversation-player"] = {
		"conversationId": "conversation-player",
		"participants": ["旅行者", "林岚"],
		"turns": [{
			"turn_id": 1,
			"speaker_resident_id": "player-avatar",
			"speaker": "旅行者",
			"say": "你好。",
			"narration": "旅行者开口搭话。",
			"photos": [],
		}],
		"waitingFor": "",
		"status": "active",
	}
	world.avatar["conversationId"] = "conversation-player"
	world.revision += 1
	world.world_revision_changed.emit(world.revision)
	var player_vm := adapter.call("get_view_model", "conversation") as Dictionary
	_expect_equal(
		(player_vm.get("data", {}) as Dictionary).get("displayMode"),
		"player",
		"player conversation keeps the existing conversation contract",
	)
	_expect_equal(
		((player_vm.get("actions", {}) as Dictionary).get("reply", {}) as Dictionary).get("enabled"),
		true,
		"player reply remains enabled outside spectator mode",
	)
	var player_reply := adapter.call("dispatch", "conversation.reply", {"say": "继续。"}) as Dictionary
	_expect(bool(player_reply.get("ok", false)), "player reply still reaches the existing Runtime command")
	_expect_equal(runtime.player_mutation_count, 1, "only the explicit player-mode reply mutates conversation")

	adapter.call("unbind_runtime")
	adapter.free()
	runtime.free()
	gateway.free()
	await process_frame

	world.avatar["conversationId"] = ""
	world.conversations.erase("conversation-player")
	var missing_runtime := RuntimeHarness.new()
	var missing_gateway := MissingGatewayHarness.new()
	var missing_adapter := ADAPTER.new()
	root.add_child(missing_runtime)
	root.add_child(missing_gateway)
	root.add_child(missing_adapter)
	missing_adapter.call("bind_runtime", missing_runtime, world, missing_gateway, {})
	var missing := missing_adapter.call("get_view_model", "conversation") as Dictionary
	_expect_equal(missing.get("status"), "disabled", "missing Gateway contract disables spectator")
	_expect_equal(
		((missing.get("error") as Dictionary).get("code")),
		"SPECTATOR_INTERFACE_MISSING",
		"missing public dependency uses stable error",
	)
	_expect_equal((missing.get("data", {}) as Dictionary).get("formalReady"), false, "missing interface never claims formal readiness")
	missing_adapter.call("unbind_runtime")
	missing_adapter.free()
	missing_runtime.free()
	missing_gateway.free()
	await process_frame
	return
func _expect_complete_view_model(view_model: Dictionary) -> void:
	for key in ["scope", "status", "revision", "data", "actions", "operation", "error"]:
		_expect(view_model.has(key), "conversation ViewModel contains %s" % key)



func _scenario_conversation_photo_contract() -> void:
	var photo_path := _create_test_photo()
	if photo_path.is_empty():
		return
	_test_store_contract(photo_path)
	_test_gateway_capability_contract()
	await _test_formal_adapter_and_screen(photo_path)
	if FileAccess.file_exists(photo_path):
		DirAccess.remove_absolute(photo_path)
	return
func _test_store_contract(photo_path: String) -> void:
	var store: RefCounted = PHOTO_STORE.new()
	var first := store.call("stage_file", photo_path, "resident-lin") as Dictionary
	var second := store.call("stage_file", photo_path, "resident-lin") as Dictionary
	_expect(bool(first.get("ok", false)), "有效 PNG 没有通过安全读取")
	_expect_equal(
		first.get("ref"),
		second.get("ref"),
		"同一图片没有生成稳定 SHA-256 ref",
	)
	_expect(
		String(first.get("ref", "")).begins_with("chat-photo-sha256-"),
		"照片 ref 没有使用稳定安全命名",
	)
	_expect_equal(first.get("mimeType"), "image/png", "PNG MIME 判定错误")
	_expect(first.get("previewImage") is Image, "安全读取没有返回内存预览")
	var resolved := store.call(
		"resolve_photo",
		String(first.get("ref", "")),
		"image/png",
	) as Dictionary
	_expect(
		bool(resolved.get("ok", false))
		and resolved.get("bytes") is PackedByteArray
		and not (resolved.get("bytes") as PackedByteArray).is_empty(),
		"Agent resolver 无法按 ref 取得照片内容",
	)
	var preview := store.call(
		"resolve_photo_preview",
		String(first.get("ref", "")),
		"image/png",
	) as Dictionary
	_expect(
		bool(preview.get("ok", false))
		and preview.get("previewImage") is Image
		and not (preview.get("previewImage") as Image).is_empty(),
		"聊天记录无法按照片引用取得安全预览",
	)
	store.call("discard_staged_photo", first.get("ref"), "resident-lin")
	store.call("discard_staged_photo", second.get("ref"), "resident-lin")
	_expect_equal(
		(store.call("audit_snapshot") as Dictionary).get("entryCount"),
		0,
		"取消选择没有释放未提交照片",
	)
	var prepared_store: RefCounted = PHOTO_STORE.new()
	var prepared := prepared_store.call(
		"stage_file",
		photo_path,
		"resident-lin",
	) as Dictionary
	_expect(
		bool(prepared_store.call(
			"prepare_photo_commit",
			prepared.get("ref"),
			prepared.get("mimeType"),
			"resident-lin",
		)),
		"照片提交预检错误拒绝了有效暂存内容",
	)
	var prepared_snapshot := (
		prepared_store.call("audit_snapshot") as Dictionary
	)
	_expect_equal(
		prepared_snapshot.get("committedCount"),
		0,
		"照片提交预检提前消费了暂存引用",
	)
	_expect_equal(
		prepared_snapshot.get("stagedCount"),
		1,
		"照片提交预检没有保留待发送内容",
	)
	_expect(
		bool(prepared_store.call(
			"commit_photo",
			prepared.get("ref"),
			prepared.get("mimeType"),
			"resident-lin",
		)),
		"预检后的照片无法完成提交",
	)
	var invalid_path := "%s.invalid" % photo_path
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string("not an image")
	invalid_file.close()
	var invalid := store.call(
		"stage_file",
		invalid_path,
		"resident-lin",
	) as Dictionary
	_expect_equal(
		invalid.get("errorCode"),
		"PHOTO_FORMAT_UNSUPPORTED",
		"伪扩展/无效图片没有被格式校验拒绝",
	)
	DirAccess.remove_absolute(invalid_path)



func _test_gateway_capability_contract() -> void:
	var provider: RefCounted = AGENT_PROVIDER_SERVICE.new()
	var provider_configured := provider.call("configure", {
		"capabilityMode": "formal",
		"source": "runtime",
		"allowFake": false,
		"providerConfigs": {},
	}) as Dictionary
	_expect(
		bool(provider_configured.get("ok", false)),
		"正式 Agent Provider 目录配置失败",
	)
	var gateway := GATEWAY.new()
	var base_config := {
		"sessionId": "photo-capability-contract",
		"slotId": "photo-capability-slot",
		"saveRevision": 0,
		"residentIdentities": [{
			"residentId": "resident-lin",
			"residentName": "林岚",
		}],
		"residentBindings": [{
			"residentId": "resident-lin",
			"llmBinding": {
				"mode": "model",
				"providerId": "deepseek",
				"modelId": "deepseek-v4-flash",
			},
		}],
	}
	var configured := gateway.call(
		"configure_session",
		base_config,
		provider,
		null,
	) as Dictionary
	_expect(bool(configured.get("ok", false)), "Gateway 能力合同配置失败")
	_expect(
		not bool(gateway.call(
			"can_attach_photo_for_resident",
			"resident-lin",
		)),
		"文本模型被错误开放照片入口",
	)
	var vision_config := base_config.duplicate(true)
	var bindings := vision_config.get("residentBindings", []) as Array
	var llm := (bindings[0] as Dictionary).get("llmBinding", {}) as Dictionary
	llm["capabilities"] = ["vision"]
	var spoofed_configured := gateway.call(
		"configure_session",
		vision_config,
		provider,
		null,
	) as Dictionary
	_expect(
		bool(spoofed_configured.get("ok", false))
		and not bool(gateway.call(
			"can_attach_photo_for_resident",
			"resident-lin",
		)),
		"绑定自报 vision 绕过了 Agent 模型目录能力门禁",
	)
	llm.erase("capabilities")
	llm["providerId"] = "kimi"
	llm["modelId"] = "kimi-k2.6"
	var vision_configured := gateway.call(
		"configure_session",
		vision_config,
		provider,
		null,
	) as Dictionary
	_expect(
		bool(vision_configured.get("ok", false))
			and bool(gateway.call(
				"can_attach_photo_for_resident",
				"resident-lin",
			)),
			"Agent 模型目录声明图片理解后照片能力仍未开放",
		)
	gateway.free()



func _test_formal_adapter_and_screen(photo_path: String) -> void:
	var world := WorldHarnessConversationPhotoContract.new()
	var runtime := RuntimeHarnessConversationPhotoContract.new()
	var gateway := GatewayHarnessConversationPhotoContract.new()
	var adapter := ADAPTER.new()
	root.add_child(runtime)
	root.add_child(gateway)
	root.add_child(adapter)
	adapter.call("bind_runtime", runtime, world, gateway, {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
	})
	var view_model := adapter.call("get_view_model", "conversation") as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	_expect_equal(data.get("displayMode"), "player", "正式 Adapter 未投影玩家聊天")
	_expect_equal(data.get("canAttachPhoto"), true, "正式 Adapter 未投影视觉能力")

	var screen := SCREEN.instantiate() as Control
	screen.call("bind_town_ui_adapter", adapter)
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.call("_on_photo_selected", photo_path)
	var selected := screen.call("runtime_gate_snapshot") as Dictionary
	_expect(bool(selected.get("photoSelected", false)), "原生选择结果没有进入预览态")
	_expect(bool(selected.get("photoPreviewVisible", false)), "照片预览没有显示")
	_expect(
		not JSON.stringify(view_model).contains(photo_path),
		"绝对路径泄漏到 conversation ViewModel",
	)
	screen.call("_open_photo_dialog")
	var canceled := screen.call("runtime_gate_snapshot") as Dictionary
	_expect(not bool(canceled.get("photoSelected", true)), "预览取消没有清除页面状态")
	_expect_equal(
		gateway.snapshot().get("stagedCount"),
		0,
		"预览取消没有释放暂存内容",
	)

	screen.call("_on_photo_selected", photo_path)
	gateway.prepare_ok = false
	screen.call("_submit_reply")
	var preflight_failed := (
		screen.call("runtime_gate_snapshot") as Dictionary
	)
	_expect(
		bool(preflight_failed.get("photoSelected", false)),
		"照片提交预检失败后没有保留待发送内容",
	)
	_expect_equal(
		runtime.photo_reply_count,
		0,
		"照片尚不能可靠保存时就提前写入了 World",
	)
	gateway.prepare_ok = true
	runtime.reply_ok = false
	screen.call("_submit_reply")
	var failed := screen.call("runtime_gate_snapshot") as Dictionary
	_expect(bool(failed.get("photoSelected", false)), "发送失败后照片预览被清空")
	_expect_equal(runtime.photo_reply_count, 1, "照片发送没有进入正式 runtime bridge")
	_expect_equal(runtime.last_photos.size(), 1, "照片发送没有传递照片列表")
	if runtime.last_photos.size() == 1:
		_expect_equal(
			(runtime.last_photos[0] as Dictionary).keys(),
			["ref", "mime_type"],
			"World/Agent 照片合同包含了额外字段",
		)
	_expect_equal(
		gateway.snapshot().get("stagedCount"),
		1,
		"失败发送没有保留可重试照片",
	)
	var stale_vm := (
		adapter.call("get_view_model", "conversation") as Dictionary
	).duplicate(true)
	stale_vm["revision"] = int(stale_vm.get("revision", 0)) - 1
	(stale_vm.get("data", {}) as Dictionary)["canAttachPhoto"] = false
	_expect(
		not bool(screen.call("apply_view_model", stale_vm)),
		"页面接受了迟到 revision",
	)
	_expect(
		bool(
			(screen.call("runtime_gate_snapshot") as Dictionary).get(
				"photoSelected",
				false,
			)
		),
		"迟到 revision 覆盖了可重试照片状态",
	)

	runtime.reply_ok = true
	screen.call("_submit_reply")
	var retried := screen.call("runtime_gate_snapshot") as Dictionary
	_expect(not bool(retried.get("photoSelected", true)), "成功重试后页面临时状态未清理")
	_expect_equal(runtime.photo_reply_count, 2, "照片失败重试没有再次走正式桥")
	_expect_equal(
		gateway.snapshot().get("committedCount"),
		1,
		"成功发送没有把照片保留给 Agent resolver",
	)
	_expect_equal(
		gateway.snapshot().get("stagedCount"),
		0,
		"成功发送后仍残留页面暂存引用",
	)
	(world.conversation.get("turns", []) as Array).append({
		"turn_id": 2,
		"speaker_resident_id": "player-avatar",
		"speaker": "旅行者",
		"say": "给你看一张照片。",
		"narration": "旅行者展示了一张照片。",
		"photos": runtime.last_photos.duplicate(true),
	})
	world.conversation["waitingFor"] = "林岚"
	world.revision += 1
	adapter.call("_refresh_scope", "conversation", true)
	await process_frame
	await process_frame
	var history_snapshot := screen.call("runtime_gate_snapshot") as Dictionary
	_expect_equal(
		history_snapshot.get("historyPhotoPreviewCount"),
		1,
		"照片发送成功后聊天记录没有显示照片预览",
	)

	screen.call("_on_photo_selected", photo_path)
	_expect_equal(gateway.snapshot().get("stagedCount"), 1, "关闭前没有暂存照片")
	screen.call("unbind_town_ui_adapter")
	_expect_equal(
		gateway.snapshot().get("stagedCount"),
		0,
		"关闭页面没有释放未发送照片",
	)
	screen.free()
	await process_frame

	world.avatar["conversationId"] = ""
	adapter.call("_refresh_scope", "conversation", true)
	var spectator_vm := adapter.call("get_view_model", "conversation") as Dictionary
	var spectator_data := spectator_vm.get("data", {}) as Dictionary
	_expect_equal(
		spectator_data.get("canAttachPhoto"),
		false,
		"旁观投影暴露了照片入口",
	)
	adapter.call("unbind_runtime")
	adapter.free()
	runtime.free()
	gateway.free()



func _create_test_photo() -> String:
	var image := Image.create(12, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.25, 0.5, 0.75, 1.0))
	var path := ProjectSettings.globalize_path(
		"user://town-conversation-photo-contract.png"
	)
	var error := image.save_png(path)
	if error != OK:
		_failures.append("无法创建照片合同输入：%s" % error_string(error))
		return ""
	return path



func _scenario_conversation() -> void:
	_test_accept_multi_turn_overhear_and_end()
	_test_resident_conversation_turn_budget_ends_loop()
	_test_resident_conversation_idle_timeout_releases_both_residents()
	_test_resident_pair_cooldown_and_repeat_rejection_breaker()
	_test_refusal_keeps_existing_action()
	_test_required_reply_rejects_non_reply_action()
	_test_invalid_photo_reference_is_rejected()
	_test_leaving_range_ends_conversation()
	return
func _test_accept_multi_turn_overhear_and_end() -> void:
	var world := _new_world(true)
	var bystander_events: Array[Dictionary] = []
	var conversation_states: Array[Dictionary] = []
	world.connect("world_event_created", func(resident_name: String, event: Dictionary) -> void:
		if resident_name == "阿禾" and String(event.get("type", "")) == "旁听":
			bystander_events.append(event.duplicate(true))
	)
	world.connect("conversation_changed", func(_conversation_id: String, state: Dictionary) -> void:
		conversation_states.append(state.duplicate(true))
	)

	var lin_wake := _take_wake_conversation(world, "林岚")
	_expect_equal(world.call("submit_agent_decision", "林岚", _talk_conversation(lin_wake, "唐小满", "早上好。", "林岚朝她点了点头")).get("status"), "accepted", "nearby resident can start a conversation")
	_expire_confirmed_preview(world)
	var active := world.call("get_active_conversations") as Array[Dictionary]
	_expect_equal(active.size(), 1, "accepted talk creates one active world conversation")
	var conversation_id := String(active[0].get("conversationId", "")) if not active.is_empty() else ""
	_expect(not conversation_id.is_empty(), "world assigns a stable conversation id")
	_expect_equal((active[0].get("turns", []) as Array).size(), 1, "talk creates the first confirmed turn")
	_expect_equal(active[0].get("waitingFor"), "resident_tang_xiaoman_01", "talk waits for the target residentId")
	var lin_activity := (
		world.call("get_resident_state", "林岚") as Dictionary
	).get("activityCue", {}) as Dictionary
	_expect_equal(
		lin_activity.get("actorFacing"),
		"right",
		"the speaking resident visibly faces the conversation partner",
	)
	_expect_equal(
		lin_activity.get("socialRole"),
		"speaking",
		"the conversation cue identifies the current visible speaker",
	)
	_expect_equal(bystander_events.size(), 1, "a nearby third resident overhears the first confirmed turn")
	if bystander_events.size() == 1:
		var overheard := bystander_events[0]
		_expect_equal(
			overheard.get("speaker_resident_ids"),
			["resident_lin_lan_01", "resident_tang_xiaoman_01"],
			"overhear event identifies both participants with stable residentIds",
		)
		_expect_equal(overheard.get("speakers"), ["林岚", "唐小满"], "overhear event keeps player-readable participant names")
		_expect_equal((overheard.get("turn", {}) as Dictionary).get("speaker_resident_id"), "resident_lin_lan_01", "overhear turn identifies the actual speaker")

	var player_notice := world.call(
		"publish_announcement",
		"请大家稍后到中央广场集合。",
	) as Dictionary
	_expect_equal(
		player_notice.get("ok"),
		true,
		"player announcement can be published during a resident conversation",
	)
	var player_announcements := world.call("get_announcements") as Array
	var player_announcement := player_announcements[0] as Dictionary if not player_announcements.is_empty() else {}
	_expect_equal(
		player_announcement.get("publisher_role"),
		"旅行者",
		"player announcement exposes the traveler publisher role",
	)
	_expect_equal(
		player_announcement.get("publisher_type"),
		"traveler",
		"player announcement exposes the traveler publisher type",
	)
	var lin_during_conversation := (
		(world.get("resident_registry") as TownResidentRegistry).records as Dictionary
	).get(POSTAL_ID, {}) as Dictionary
	_expect_equal(
		lin_during_conversation.get("decisionPending"),
		false,
		"player announcement does not interrupt an active resident conversation",
	)
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		1,
		"active resident conversation remains intact after a player announcement",
	)

	var tang_invitation := _take_wake_conversation(world, "唐小满")
	_expect(_has_event_conversation(tang_invitation, "搭话"), "target receives an urgent talk event")
	_expect(_has_required_invitation_event_conversation(tang_invitation), "talk event marks the target reply as required")
	_expect_equal((tang_invitation.get("snapshot", {}) as Dictionary).get("conversation", {}).get("conversation_id"), conversation_id, "target snapshot contains the same conversation")
	_expect_equal(world.call("submit_agent_decision", "唐小满", _reply(tang_invitation, conversation_id, "早呀。", "唐小满笑着回应", false)).get("status"), "accepted", "target can accept with a reply")
	_expire_confirmed_preview(world)
	var tang_activity := (
		world.call("get_resident_state", "唐小满") as Dictionary
	).get("activityCue", {}) as Dictionary
	_expect_equal(
		tang_activity.get("actorFacing"),
		"left",
		"the replying resident turns toward the conversation partner",
	)
	_expect_equal(
		tang_activity.get("socialRole"),
		"speaking",
		"the reply becomes the current visible speaker activity",
	)

	var lin_reply_wake := _take_wake_conversation(world, "林岚")
	_expect(_has_event_conversation(lin_reply_wake, "对方答话"), "initiator receives the accepted reply")
	_expect(_has_result(lin_reply_wake, "completed"), "reply completes the initiator talk action")
	_expect_equal(world.call("submit_agent_decision", "林岚", _reply(lin_reply_wake, conversation_id, "花开得不错。", "林岚看向花圃", false)).get("status"), "accepted", "initiator can continue with a second reply")
	_expire_confirmed_preview(world)

	var tang_reply_wake := _take_wake_conversation(world, "唐小满")
	_expect(_has_event_conversation(tang_reply_wake, "对方答话"), "the other participant receives the next turn")
	_expect(_has_result(tang_reply_wake, "completed"), "next turn completes the previous reply action")
	_expect_equal(world.call("submit_agent_decision", "唐小满", _reply(tang_reply_wake, conversation_id, "我再去浇点水。", "唐小满挥挥手准备离开", true)).get("status"), "accepted", "participant can end after delivering a final turn")
	_expire_confirmed_preview(world)

	_expect_equal((world.call("get_active_conversations") as Array).size(), 0, "active conversation list clears after an explicit end")
	var ended := world.call("get_conversation", conversation_id) as Dictionary
	_expect_equal(ended.get("status"), "ended", "ended conversation remains queryable for presentation feedback")
	_expect_equal(ended.get("endReason"), "主动结束", "world records the explicit end reason")
	_expect_equal((ended.get("turns", []) as Array).size(), 4, "world keeps all confirmed turns in order")
	_expect_equal(bystander_events.size(), 4, "nearby bystander hears every confirmed turn exactly once")
	var social_progress := world.call(
		"get_resident_public_relationship_progress",
		"resident_lin_lan_01",
	) as Dictionary
	var social_items := social_progress.get("items", []) as Array
	_expect_equal(
		social_progress.get("ok"),
		true,
		"confirmed conversation exposes public relationship progress",
	)
	_expect_equal(
		social_items.size(),
		1,
		"one confirmed resident relationship produces one progress record",
	)
	if social_items.size() == 1:
		var social_item := social_items[0] as Dictionary
		_expect_equal(
			social_item.get("residentId"),
			"resident_tang_xiaoman_01",
			"relationship progress identifies the other resident",
		)
		_expect_equal(
			(social_item.get("depth", {}) as Dictionary).get("level"),
			2,
			"one four-turn exchange yields evidence-based depth two of five",
		)
	_expect_equal((world.call("get_resident_state", "林岚") as Dictionary).get("conversation"), null, "initiator no longer has an active conversation")
	_expect_equal((world.call("get_resident_state", "唐小满") as Dictionary).get("conversation"), null, "other participant no longer has an active conversation")
	_expect_equal(conversation_states[-1].get("status"), "ended", "presentation receives the final ended conversation state")
	var lin_end_wake := _take_wake_conversation(world, "林岚")
	var tang_end_wake := _take_wake_conversation(world, "唐小满")
	_expect(_has_event_conversation(lin_end_wake, "对话结束", "主动结束"), "initiator receives the full conversation end event")
	_expect(_has_event_conversation(tang_end_wake, "对话结束", "主动结束"), "ending participant receives the full conversation end event")
	_expect(_has_result(lin_end_wake, "completed"), "initiator's pending reply completes when the other side ends")
	_expect(_has_result(tang_end_wake, "completed"), "final reply action completes when it ends the conversation")



func _test_resident_conversation_turn_budget_ends_loop() -> void:
	var world := _new_world(false)
	var first_wake := _take_wake_conversation(world, "林岚")
	_expect_equal(
		world.call(
			"submit_agent_decision",
			"林岚",
			_talk_conversation(first_wake, "唐小满", "今天忙吗？", "林岚停下来问她"),
		).get("status"),
		"accepted",
		"resident-only conversation starts for turn-budget coverage",
	)
	_expire_confirmed_preview(world)
	var active := world.call("get_active_conversations") as Array[Dictionary]
	var conversation_id := (
		String(active[0].get("conversationId", ""))
		if not active.is_empty()
		else ""
	)
	var next_resident := "唐小满"
	for turn_number in range(2, 9):
		var wake := _take_wake_conversation(world, next_resident)
		var reply := _reply(
			wake,
			conversation_id,
			"这是第%d轮。" % turn_number,
			"%s继续回应" % next_resident,
			false,
		)
		_expect_equal(
			world.call(
				"submit_agent_decision",
				next_resident,
				reply,
			).get("status"),
			"accepted",
			"resident reply %d is accepted" % turn_number,
		)
		_expire_confirmed_preview(world)
		next_resident = "林岚" if next_resident == "唐小满" else "唐小满"
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		0,
		"resident-only conversation cannot exceed eight confirmed turns",
	)
	var ended := world.call("get_conversation", conversation_id) as Dictionary
	_expect_equal(ended.get("status"), "ended", "turn budget ends the conversation")
	_expect_equal(ended.get("endReason"), "无法继续", "turn budget uses the existing unable-to-continue reason")
	_expect_equal((ended.get("turns", []) as Array).size(), 8, "the final confirmed turn is retained before automatic end")
	var lin_end := _take_wake_conversation(world, "林岚")
	var tang_end := _take_wake_conversation(world, "唐小满")
	_expect(_has_event_conversation(lin_end, "对话结束", "无法继续"), "initiator receives the automatic end event")
	_expect(_has_event_conversation(tang_end, "对话结束", "无法继续"), "other resident receives the automatic end event")



func _test_resident_conversation_idle_timeout_releases_both_residents() -> void:
	var world := _new_world(false)
	var first_wake := _take_wake_conversation(world, "林岚")
	_expect_equal(
		world.call(
			"submit_agent_decision",
			"林岚",
			_talk_conversation(
				first_wake,
				"唐小满",
				"聊一会儿吗？",
				"林岚停下来问她",
			),
		).get("status"),
		"accepted",
		"resident-only conversation starts for idle-timeout coverage",
	)
	_expire_confirmed_preview(world)
	var active := world.call("get_active_conversations") as Array[Dictionary]
	var conversation_id := (
		String(active[0].get("conversationId", ""))
		if not active.is_empty()
		else ""
	)
	CONVERSATION_RUNTIME._advance_autonomous_conversation_timeouts(
		world,
		world.get("_traveler_relationship_state") as TownTravelerRelationshipState,
		40.0,
	)
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		1,
		"resident conversation remains active before its idle deadline",
	)
	CONVERSATION_RUNTIME._advance_autonomous_conversation_timeouts(
		world,
		world.get("_traveler_relationship_state") as TownTravelerRelationshipState,
		5.0,
	)
	_expect_equal(
		(world.call("get_active_conversations") as Array).size(),
		0,
		"resident conversation closes when no reply returns by the deadline",
	)
	var ended := world.call("get_conversation", conversation_id) as Dictionary
	_expect_equal(
		ended.get("endReason"),
		"无法继续",
		"idle timeout uses the existing player-facing unable-to-continue result",
	)
	for resident_name in ["林岚", "唐小满"]:
		var resident := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		_expect_equal(
			resident.get("conversation"),
			null,
			"%s is released from the stalled conversation" % resident_name,
		)
		var wake := _take_wake_conversation(world, resident_name)
		_expect(
			_has_event_conversation(wake, "对话结束", "无法继续"),
			"%s receives the idle-timeout end fact" % resident_name,
		)



func _test_resident_pair_cooldown_and_repeat_rejection_breaker() -> void:
	var world := _new_world(false)
	var lin_wake := _take_wake_conversation(world, "林岚")
	world.call(
		"submit_agent_decision",
		"林岚",
		_talk_conversation(lin_wake, "唐小满", "聊两句吗？", "林岚停下来"),
	)
	_expire_confirmed_preview(world)
	var active := world.call("get_active_conversations") as Array[Dictionary]
	var conversation_id := (
		String(active[0].get("conversationId", ""))
		if not active.is_empty()
		else ""
	)
	var tang_wake := _take_wake_conversation(world, "唐小满")
	world.call(
		"submit_agent_decision",
		"唐小满",
		_reply(
			tang_wake,
			conversation_id,
			"先到这里吧。",
			"唐小满结束交谈",
			true,
		),
	)
	_expire_confirmed_preview(world)
	var first_retry_wake := _take_wake_conversation(world, "林岚")
	var first_retry := world.call(
		"submit_agent_decision",
		"林岚",
		_talk_conversation(
			first_retry_wake,
			"唐小满",
			"再聊一句？",
			"林岚再次开口",
		),
	) as Dictionary
	_expect_equal(
		first_retry.get("ok"),
		false,
		"same resident pair cannot restart during the cooldown",
	)
	var second_retry_wake := _take_wake_conversation(world, "林岚")
	var second_retry := world.call(
		"submit_agent_decision",
		"林岚",
		_talk_conversation(
			second_retry_wake,
			"唐小满",
			"换句话再聊？",
			"林岚仍然尝试搭话",
		),
	) as Dictionary
	_expect_equal(
		second_retry.get("ok"),
		false,
		"rephrasing the same rejected intent remains rejected",
	)
	var unexpected_retry := world.call(
		"take_pending_decision_requests",
		["林岚"],
	) as Array[Dictionary]
	_expect_equal(
		unexpected_retry.size(),
		0,
		"second identical rejection does not create an immediate decision loop",
	)



func _test_refusal_keeps_existing_action() -> void:
	var world := _new_world(false)
	var tang_initial := _take_wake_conversation(world, "唐小满")
	_expect_equal(
		world.call(
			"submit_agent_decision",
			"唐小满",
			_garden_activity(tang_initial),
		).get("status"),
		"accepted",
		"target starts an existing garden activity",
	)
	_expire_confirmed_preview(world)
	var tang_action_before: Variant = (world.call("get_resident_state", "唐小满") as Dictionary).get("currentAction")
	var lin_initial := _take_wake_conversation(world, "林岚")
	_expect_equal(world.call("submit_agent_decision", "林岚", _talk_conversation(lin_initial, "唐小满", "能聊聊吗？", "林岚停在她身边")).get("status"), "accepted", "initiator starts a refusal test conversation")
	_expire_confirmed_preview(world)
	var tang_invitation := _take_wake_conversation(world, "唐小满")
	var refusal_attempt := world.call("submit_agent_decision", "唐小满", {
		"decision_id": String(tang_invitation.get("decision_id", "")),
		"handling": "continue_current",
	}) as Dictionary
	_expect_equal(refusal_attempt.get("ok"), false, "World rejects silently continuing during an invitation")
	_expect_equal(refusal_attempt.get("errorCode"), "CONVERSATION_REPLY_REQUIRED", "silent invitation refusal has a precise retryable error")
	var conversation_id := String((tang_invitation.get("snapshot", {}) as Dictionary).get("conversation", {}).get("conversation_id", ""))
	var refusal := _reply(tang_invitation, conversation_id, "抱歉，我现在正忙，改天再聊。", "我停下来说明现在不方便交谈，然后告别。", true)
	var refusal_result := world.call("submit_agent_decision", "唐小满", refusal) as Dictionary
	_expect_equal(refusal_result.get("status"), "accepted", "World accepts an explicit refusal as a reply")
	_expire_confirmed_preview(world)
	_expect_equal((world.call("get_resident_state", "唐小满") as Dictionary).get("currentAction"), tang_action_before, "refusal does not stop the target's existing legal action")
	_expect_equal((world.call("get_active_conversations") as Array).size(), 0, "refused invitation is no longer active")
	var lin_rejected := _take_wake_conversation(world, "林岚")
	_expect(_has_result(lin_rejected, "completed"), "initiator receives the completed opening action after the refusal reply")
	_expect(_has_event_conversation(lin_rejected, "对话结束", "主动结束"), "initiator receives the refusal end event")
	_expect(_has_end_turn_text_conversation(lin_rejected, "抱歉，我现在正忙，改天再聊。"), "initiator receives the explicit refusal reason in the final turn")



func _test_leaving_range_ends_conversation() -> void:
	var world := _new_world(false)
	var tang_initial := _take_wake_conversation(world, "唐小满")
	_expect_equal(world.call("submit_agent_decision", "唐小满", _go_conversation(tang_initial, "中心广场")).get("status"), "accepted", "target starts moving before the invitation")
	# Unobserved actions activate immediately. The invitation must hold the target
	# before the movement can carry them out of speaking range.
	var lin_initial := _take_wake_conversation(world, "林岚")
	var moving_talk_result := world.call(
		"submit_agent_decision",
		"林岚",
		_talk_conversation(lin_initial, "唐小满", "等等。", "林岚朝她喊了一声"),
	) as Dictionary
	_expect_equal(
		moving_talk_result.get("status"),
		"accepted",
		"moving nearby target can receive a talk invitation (%s)" % moving_talk_result,
	)
	_expire_confirmed_preview(world)
	var held_target := ((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get("resident_tang_xiaoman_01", {}) as Dictionary
	_expect_equal((held_target.get("currentAction", {}) as Dictionary).get("type"), "去", "target keeps the original movement internally while answering is pending")
	_expect(int(held_target.get("actionSuspendedAbsoluteMinute", -1)) >= 0, "target movement is paused while the invitation is pending")
	for _minute in 120:
		if (world.call("get_active_conversations") as Array).is_empty():
			break
		world.call("advance", 1.0)
	_expect_equal((world.call("get_active_conversations") as Array).size(), 0, "conversation eventually ends while the target remains held")
	_expect_equal((world.call("get_resident_state", "唐小满") as Dictionary).get("currentAction", {}).get("type"), "去", "target movement continues after the invitation ends")
	var lin_interrupted := _take_wake_conversation(world, "林岚")
	_expect(_has_result(lin_interrupted, "interrupted"), "opening talk is interrupted when the held invitation times out")
	_expect(_has_event_conversation(lin_interrupted, "对话结束", "无法继续"), "stalled conversation receives an automatic end event")



func _test_required_reply_rejects_non_reply_action() -> void:
	var world := _new_world(false)
	var lin_initial := _take_wake_conversation(world, "林岚")
	world.call("submit_agent_decision", "林岚", _talk_conversation(lin_initial, "唐小满", "在忙吗？", "林岚看向唐小满"))
	_expire_confirmed_preview(world)
	var tang_invitation := _take_wake_conversation(world, "唐小满")
	var conversation_id := String((tang_invitation.get("snapshot", {}) as Dictionary).get("conversation", {}).get("conversation_id", ""))
	world.call("submit_agent_decision", "唐小满", _reply(tang_invitation, conversation_id, "不忙。", "唐小满转过身来", false))
	_expire_confirmed_preview(world)
	var lin_reply_wake := _take_wake_conversation(world, "林岚")
	var invalid := world.call("submit_agent_decision", "林岚", _wait_conversation(lin_reply_wake)) as Dictionary
	_expect_equal(invalid.get("ok"), false, "world independently rejects a non-reply while a reply is required")
	_expect_equal((world.call("get_active_conversations") as Array).size(), 1, "invalid non-reply does not rewrite active conversation state")
	_expect_equal((world.call("get_conversation", conversation_id) as Dictionary).get("waitingFor"), "resident_lin_lan_01", "conversation still waits for the same participant residentId")



func _test_invalid_photo_reference_is_rejected() -> void:
	var world := _new_world(false)
	var lin_initial := _take_wake_conversation(world, "林岚")
	var invalid_talk := _talk_conversation(lin_initial, "唐小满", "看看这个。", "林岚递出一张照片")
	invalid_talk["action"]["photos"] = [{"ref": "not-in-current-wake", "mime_type": "image/jpeg"}]
	var result := world.call("submit_agent_decision", "林岚", invalid_talk) as Dictionary
	_expect_equal(result.get("ok"), false, "world rejects a photo reference that is not available in the current conversation")
	_expect_equal((world.call("get_active_conversations") as Array).size(), 0, "invalid photo does not create a conversation")

	var mismatch_world := _new_world(false)
	var mismatch_wake := _take_wake_conversation(mismatch_world, "林岚")
	var mismatched_target := _talk_conversation(mismatch_wake, "唐小满", "你好。", "林岚打了声招呼")
	mismatched_target["action"]["target"] = "唐小满"
	var mismatch_result := mismatch_world.call("submit_agent_decision", "林岚", mismatched_target) as Dictionary
	_expect_equal(mismatch_result.get("ok"), false, "legacy display-name target fields are rejected")
	_expect_equal((mismatch_world.call("get_active_conversations") as Array).size(), 0, "unknown target fields do not create a conversation")



func _new_world(include_bystander: bool) -> RefCounted:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening := (OPENING.load_config(OPENING_PATH, data) as Dictionary).get("config", {}).duplicate(true) as Dictionary
	_set_resident_outdoor_state_conversation(opening, "林岚", Vector2(3340, 2772))
	_set_resident_outdoor_state_conversation(opening, "唐小满", Vector2(3396, 2772))
	if include_bystander:
		_set_resident_outdoor_state_conversation(opening, "阿禾", Vector2(3440, 2772))
	var validation := OPENING.validate(opening, data) as Array[String]
	_expect_equal(validation, [], "conversation test opening remains legal")
	var world: RefCounted = WORLD.new()
	_expect_equal(world.call("start", data, opening).get("ok"), true, "conversation test world starts")
	return world



func _expire_confirmed_preview(world: RefCounted) -> void:
	for _step in 5:
		world.call("advance", 0.5)



func _set_resident_outdoor_state_conversation(opening: Dictionary, resident_name: String, position: Vector2) -> void:
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		if String(resident.get("attributes", {}).get("name", "")) != resident_name:
			continue
		resident["worldState"] = {
			"place": "社区花园",
			"spaceId": "town_outdoor",
			"regionId": "outdoor_garden_01",
			"position": [position.x, position.y],
			"doing": "在社区花园里",
			"body": {"困": "不困", "饿": "不饿", "累": "不累"},
		}
		return



func _take_wake_conversation(world: RefCounted, resident_name: String) -> Dictionary:
	var requests := world.call("take_pending_decision_requests", [resident_name]) as Array[Dictionary]
	if requests.is_empty():
		_failures.append("missing wake request for %s" % resident_name)
		return {}
	return (requests[0].get("wakePacket", {}) as Dictionary).duplicate(true)



func _talk_conversation(wake: Dictionary, target: String, say: String, narration: String) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-talk" % decision_id,
			"type": "搭话",
			"target_resident_id": _nearby_resident_id_conversation(wake, target),
			"say": say,
			"narration": narration,
			"photos": [],
		},
	}



func _nearby_resident_id_conversation(wake: Dictionary, target: String) -> String:
	var nearby := (wake.get("snapshot", {}) as Dictionary).get("nearby", []) as Array
	for value: Variant in nearby:
		var person := value as Dictionary
		if String(person.get("name", "")) == target:
			return String(person.get("resident_id", ""))
	return ""



func _reply(wake: Dictionary, conversation_id: String, say: String, narration: String, end: bool) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-reply" % decision_id,
			"type": "答话",
			"conversation_id": conversation_id,
			"say": say,
			"narration": narration,
			"photos": [],
			"end": end,
		},
	}



func _wait_conversation(wake: Dictionary) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {"decision_id": decision_id, "handling": "replace_current", "action": {"action_id": "%s-wait" % decision_id, "type": "待着", "line": "继续待着"}}



func _garden_activity(wake: Dictionary) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-activity" % decision_id,
			"type": "做活动",
			"activity_id": "activity_garden_bench_rest",
			"line": "在花园长椅边休息",
		},
	}



func _go_conversation(wake: Dictionary, place: String) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {"decision_id": decision_id, "handling": "replace_current", "action": {"action_id": "%s-go" % decision_id, "type": "去", "place": place, "line": "去%s" % place}}



func _has_event_conversation(wake: Dictionary, event_type: String, reason := "") -> bool:
	for value: Variant in wake.get("events", []) as Array:
		var event := value as Dictionary
		if String(event.get("type", "")) == event_type and (reason.is_empty() or String(event.get("reason", "")) == reason):
			return true
	return false


func _has_required_invitation_event_conversation(wake: Dictionary) -> bool:
	for value: Variant in wake.get("events", []) as Array:
		var event := value as Dictionary
		if String(event.get("type", "")) == "搭话" and bool(event.get("response_required", false)):
			return true
	return false



func _has_result(wake: Dictionary, status: String) -> bool:
	for value: Variant in wake.get("action_results", []) as Array:
		if String((value as Dictionary).get("status", "")) == status:
			return true
	return false


func _has_end_turn_text_conversation(wake: Dictionary, text: String) -> bool:
	for value: Variant in wake.get("events", []) as Array:
		var event := value as Dictionary
		if String(event.get("type", "")) != "对话结束":
			continue
		for turn_value: Variant in event.get("turns", []) as Array:
			var turn := turn_value as Dictionary
			if String(turn.get("say", "")) == text:
				return true
	return false



func _scenario_ui_adapter_player_conversation_identity() -> void:
	var world := WorldHarnessUiAdapterPlayerConversationIdentity.new()
	var runtime := RuntimeHarnessUiAdapterPlayerConversationIdentity.new()
	runtime.world = world
	var gateway := GatewayHarnessUiAdapterPlayerConversationIdentity.new()
	var adapter := ADAPTER.new()
	get_root().add_child(runtime)
	get_root().add_child(gateway)
	get_root().add_child(adapter)
	adapter.call("bind_runtime", runtime, world, gateway, {
		"source": "runtime",
		"capabilityMode": "formal",
		"formalReady": true,
	})

	for resident: Dictionary in RESIDENTS:
		var resident_id := str(resident.get("residentId", ""))
		var resident_name := str(resident.get("residentName", ""))
		var start_result := adapter.call(
			"dispatch",
			"conversation.start",
			{"residentId": resident_id},
		) as Dictionary
		_expect(
			bool(start_result.get("ok", false)),
			"%s 的 conversation.start 没有到达 Runtime" % resident_name,
		)
		_expect_equal(
			runtime.started_names.back(),
			resident_name,
			"%s 的稳定 residentId 没有解析为正确显示名" % resident_name,
		)

	for resident: Dictionary in RESIDENTS:
		var resident_id := str(resident.get("residentId", ""))
		var resident_name := str(resident.get("residentName", ""))
		var conversation_id := "conversation-%s" % resident_id
		world.conversations.clear()
		world.conversations[conversation_id] = {
			"conversationId": conversation_id,
			"participants": ["player-avatar", resident_id],
			"initiator": "player-avatar",
			"turns": [{
				"turn_id": 1,
				"speaker_resident_id": "player-avatar",
				"speaker": "旅行者",
				"say": "你好。",
				"narration": "旅行者开口搭话。",
				"photos": [],
			}],
			"waitingFor": resident_id,
			"status": "active",
		}
		world.avatar["conversationId"] = conversation_id
		world.revision += 1
		adapter.call("_refresh_scope", "conversation", true)
		var view_model := adapter.call(
			"get_view_model",
			"conversation",
		) as Dictionary
		var data := view_model.get("data", {}) as Dictionary
		var actions := view_model.get("actions", {}) as Dictionary
		var reply := actions.get("reply", {}) as Dictionary
		_expect_equal(
			data.get("residentId"),
			resident_id,
			"%s 会话把对方 residentId 投影错了" % resident_name,
		)
		_expect_equal(
			data.get("residentName"),
			resident_name,
			"%s 会话把 player-avatar 当成了对方名字" % resident_name,
		)
		_expect_equal(
			data.get("waitingFor"),
			[resident_name],
			"%s 的稳定 waitingFor 没有投影为居民显示名" % resident_name,
		)
		_expect_equal(
			view_model.get("status"),
			"loading",
			"%s 等待 Agent 回复时没有进入 loading" % resident_name,
		)
		_expect_equal(
			reply.get("enabled"),
			false,
			"%s 等待回复时仍错误开放玩家回复" % resident_name,
		)
		_expect_equal(
			reply.get("disabledReason"),
			"WAITING_FOR_RESIDENT",
			"%s 等待回复时缺少稳定禁用原因" % resident_name,
		)

	adapter.set("_conversation_network_error", {
		"code": "AGENT_DECISION_REQUEST_FAILED",
		"message": "这次请求不能再次提交。",
		"retryable": false,
	})
	adapter.call("_refresh_scope", "conversation", true)
	var non_retryable_vm := adapter.call(
		"get_view_model",
		"conversation",
	) as Dictionary
	_expect_equal(
		(
			(
				non_retryable_vm.get("actions", {}) as Dictionary
			).get("retry", {}) as Dictionary
		).get("enabled"),
		false,
		"不可重试的聊天错误仍开放了重试操作",
	)
	adapter.set("_conversation_network_error", {})
	var cleared_conversation_vm := (
		adapter.call("get_view_model", "conversation") as Dictionary
	)
	cleared_conversation_vm["status"] = "loading"
	cleared_conversation_vm["error"] = null
	(adapter.get("_view_models") as Dictionary)["conversation"] = (
		cleared_conversation_vm
	)
	adapter.call("_refresh_scope", "conversation", true)

	var screen := SCREEN.instantiate() as UnifiedConversationScreen
	screen.call("bind_town_ui_adapter", adapter)
	get_root().add_child(screen)
	await process_frame
	await process_frame
	var snapshot := screen.call("runtime_gate_snapshot") as Dictionary
	_expect_equal(snapshot.get("title"), "闻叙", "聊天页标题没有显示实际 Agent 名字")
	_expect_equal(snapshot.get("subtitle"), "聊天中", "聊天页没有保持玩家聊天模式")
	_expect_equal(snapshot.get("thinkingVisible"), true, "稳定 residentId 等待态没有显示思考中")
	var balanced_bubble_width := float(screen.call(
		"_bubble_width",
		"这是一段刚刚超过聊天气泡最大宽度并且过去会在最后单独留下一个字的测试文字",
		"",
	))
	_expect(
		balanced_bubble_width < 520.0,
		"聊天气泡略超最大宽度时没有改用均衡行宽",
	)
	_expect(
		balanced_bubble_width >= 272.0,
		"均衡后的聊天气泡没有满足最小可读宽度",
	)

	var ended_conversation_id := "conversation-resident-wen"
	var ended_conversation := (
		world.conversations[ended_conversation_id] as Dictionary
	)
	var ended_turns := ended_conversation.get("turns", []) as Array
	ended_turns.append({
		"turn_id": 2,
		"speaker_resident_id": "resident-wen",
		"speaker": "闻叙",
		"say": "我先去忙了，回头再聊。",
		"narration": "闻叙向旅行者挥了挥手。",
		"photos": [],
	})
	ended_conversation["status"] = "ended"
	ended_conversation["waitingFor"] = null
	ended_conversation["endReason"] = "主动结束"
	ended_conversation["endedAt"] = {"day": 1, "hour": 9, "minute": 5}
	world.avatar["conversationId"] = ""
	world.avatar["conversation"] = null
	world.revision += 1
	world.conversation_changed.emit(
		ended_conversation_id,
		ended_conversation.duplicate(true),
	)
	await process_frame
	var ended_view_model := adapter.call(
		"get_view_model",
		"conversation",
	) as Dictionary
	var ended_data := ended_view_model.get("data", {}) as Dictionary
	var ended_actions := ended_view_model.get("actions", {}) as Dictionary
	_expect_equal(
		ended_data.get("conversationEnded"),
		true,
		"居民结束时 Adapter 没有保留 ended 会话",
	)
	_expect_equal(
		(ended_data.get("messages", []) as Array).size(),
		2,
		"居民结束时最终答话没有保留",
	)
	_expect_equal(
		ended_data.get("endedByName"),
		"闻叙",
		"居民结束时没有投影结束者",
	)
	_expect_equal(
		ended_data.get("endNotice"),
		"闻叙结束了对话",
		"居民结束提示不明确",
	)
	_expect_equal(
		(
			ended_actions.get("dismissEnded", {}) as Dictionary
		).get("enabled"),
		true,
		"ended 会话没有提供呈现完成确认动作",
	)
	_expect_equal(
		(
			(
				adapter.call(
					"get_view_model",
					"avatar",
				) as Dictionary
			).get("data", {}) as Dictionary
		).get("conversationId"),
		ended_conversation_id,
		"结束呈现期间化身 HUD 没有继续保持互斥",
	)
	var streaming_end_snapshot := screen.call(
		"runtime_gate_snapshot"
	) as Dictionary
	_expect_equal(
		streaming_end_snapshot.get("conversationEnded"),
		true,
		"聊天页没有保持居民结束态",
	)
	_expect_equal(
		streaming_end_snapshot.get("streamActive"),
		true,
		"居民最后一句没有先逐字呈现",
	)
	_expect_equal(
		streaming_end_snapshot.get("endNoticeVisible"),
		false,
		"最后一句尚未呈现完成时提前显示结束提示",
	)
	screen.call("_process", 10.0)
	var revealed_end_snapshot := screen.call(
		"runtime_gate_snapshot"
	) as Dictionary
	_expect_equal(
		revealed_end_snapshot.get("streamActive"),
		false,
		"居民最后一句没有完成呈现",
	)
	_expect_equal(
		revealed_end_snapshot.get("endNoticeVisible"),
		true,
		"居民最后一句完成后没有显示结束者",
	)
	screen.call("_process", 1.0)
	var persistent_end_view_model := adapter.call(
		"get_view_model",
		"conversation",
	) as Dictionary
	_expect_equal(
		(
			persistent_end_view_model.get("data", {}) as Dictionary
		).get("conversationId"),
		ended_conversation_id,
		"结束提示在自动关闭延迟内仍保留",
	)
	screen.call("_process", 0.3)
	var dismissed_view_model := adapter.call(
		"get_view_model",
		"conversation",
	) as Dictionary
	_expect_equal(
		(
			dismissed_view_model.get("data", {}) as Dictionary
		).get("conversationId"),
		"",
		"结束提示自动关闭后没有退出聊天数据",
	)
	_expect_equal(
		(
			(
				adapter.call(
					"get_view_model",
					"avatar",
				) as Dictionary
			).get("data", {}) as Dictionary
		).get("conversationId"),
		"",
		"结束呈现退出后化身 HUD 没有解除互斥",
	)

	var self_end_id := "conversation-self-end"
	world.conversations[self_end_id] = {
		"conversationId": self_end_id,
		"participants": ["player-avatar", "resident-lin"],
		"initiator": "player-avatar",
		"turns": [{
			"turn_id": 1,
			"speaker_resident_id": "player-avatar",
			"speaker": "旅行者",
			"say": "下次再聊。",
			"narration": "旅行者准备离开。",
			"photos": [],
		}],
		"waitingFor": "resident-lin",
		"status": "active",
	}
	world.avatar["conversationId"] = self_end_id
	world.revision += 1
	world.conversation_changed.emit(
		self_end_id,
		(world.conversations[self_end_id] as Dictionary).duplicate(true),
	)
	var self_end_result := adapter.call(
		"dispatch",
		"conversation.end",
		{"narration": "旅行者结束交谈"},
	) as Dictionary
	_expect_equal(
		self_end_result.get("ok"),
		true,
		"玩家主动结束没有到达 Runtime",
	)
	var self_ended_view_model := adapter.call(
		"get_view_model",
		"conversation",
	) as Dictionary
	_expect_equal(
		bool(
			(
				self_ended_view_model.get("data", {}) as Dictionary
			).get("conversationEnded", false)
		),
		false,
		"玩家主动关闭错误进入居民结束停留流程",
	)

	var interrupted_id := "conversation-resident-left"
	var interrupted := {
		"conversationId": interrupted_id,
		"participants": ["player-avatar", "resident-lin"],
		"initiator": "player-avatar",
		"turns": [{
			"turn_id": 1,
			"speaker_resident_id": "player-avatar",
			"speaker": "旅行者",
			"say": "你还在吗？",
			"narration": "旅行者回头看了看。",
			"photos": [],
		}],
		"waitingFor": null,
		"status": "ended",
		"endReason": "一方离开",
		"endedAt": {"day": 1, "hour": 9, "minute": 15},
	}
	world.conversations[interrupted_id] = interrupted
	world.avatar["conversationId"] = ""
	world.revision += 1
	world.conversation_changed.emit(
		interrupted_id,
		interrupted.duplicate(true),
	)
	var interrupted_view_model := adapter.call(
		"get_view_model",
		"conversation",
	) as Dictionary
	var interrupted_data := (
		interrupted_view_model.get("data", {}) as Dictionary
	)
	_expect_equal(
		interrupted_data.get("conversationEnded"),
		true,
		"非玩家主动关闭的中断会话没有保留",
	)
	_expect_equal(
		interrupted_data.get("endedByName"),
		"林岚",
		"中断会话没有显示对方居民",
	)
	_expect_equal(
		interrupted_data.get("endNotice"),
		"距离太远，对话结束了",
		"未知离开者的中断会话错误归责给了居民",
	)
	adapter.call("dispatch", "conversation.dismiss_ended", {})

	screen.call("unbind_town_ui_adapter")
	screen.free()
	adapter.call("unbind_runtime")
	adapter.free()
	runtime.free()
	gateway.free()
	await process_frame


func _scenario_announcement_distribution_integration() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "公告传播开局可加载")
	if opening_result.get("ok") != true:
		return
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	_prepare_residents(opening)
	var world: RefCounted = WORLD.new()
	world.connect("world_event_created", _on_world_event_created)
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "公告传播 World 可启动")
	if started.get("ok") != true:
		return
	_test_board_and_bell(world)
	_test_read_and_relay_do_not_duplicate(world)
	_test_resident_notice_is_global(world)
	_test_resident_notice_survives_restore(world, data, opening)
	_test_timed_announcement_due(world)
	world.call("stop")
	return


func _scenario_player_announcement_priority() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "公告优先级开局可加载")
	if opening_result.get("ok") != true:
		return
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	var world: RefCounted = WORLD.new()
	_expect_equal(
		world.call("start", data, opening).get("ok"),
		true,
		"公告优先级 World 可启动",
	)
	for request: Dictionary in world.call(
		"take_pending_decision_requests",
	) as Array[Dictionary]:
		var wake := request.get("wakePacket", {}) as Dictionary
		world.call(
			"submit_agent_decision",
			String(request.get("residentName", "")),
			_wait_announcement_long_history(wake),
		)
	var residents := (world.get("resident_registry") as TownResidentRegistry).records as Dictionary
	var target := residents.get(SPEAKER_ID, {}) as Dictionary
	_expect(
		not (target.get("currentAction", {}) as Dictionary).is_empty(),
		"目标居民先有一项持续中的普通行动",
	)
	var resident_notice := world.call(
		"publish_resident_announcement",
		MANAGER_ID,
		"镇公所今天整理旧档案。",
	) as Dictionary
	_expect_equal(resident_notice.get("ok"), true, "居民公告可以正常发布")
	_expect_equal(
		target.get("decisionPending"),
		false,
		"居民公告不会打断持续中的普通行动",
	)
	var player_notice := world.call(
		"publish_announcement",
		"请所有人现在到中央广场集合。",
	) as Dictionary
	_expect_equal(player_notice.get("ok"), true, "玩家公告可以正常发布")
	_expect_equal(
		target.get("decisionPending"),
		true,
		"玩家公告立即唤醒正在行动的居民",
	)
	_expect_equal(
		target.get("decisionMayInterruptCurrent"),
		true,
		"玩家公告允许居民替换当前普通行动",
	)
	var requests := world.call(
		"take_pending_decision_requests_by_ids",
		[SPEAKER_ID],
	) as Array
	_expect_equal(requests.size(), 1, "玩家公告立即形成一轮居民决定")
	if requests.size() == 1:
		var wake := (
			(requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
		)
		var player_event_found := false
		var reactions: Array[Dictionary] = []
		for event_value: Variant in wake.get("events", []) as Array:
			var event := event_value as Dictionary
			if String(event.get("type", "")) not in ["公告发布", "公告到点"]:
				continue
			player_event_found = (
				player_event_found
				or String(event.get("announcement_priority", "")) == "player"
			)
			reactions.append({
				"source_event_id": String(event.get("event_id", "")),
				"text": "我会明确处理这条公告。",
			})
		_expect(player_event_found, "玩家公告以最高优先级进入唤醒包")
		var continue_result := world.call(
			"submit_agent_decision",
			SPEAKER_ID,
			{
				"decision_id": String(wake.get("decision_id", "")),
				"handling": "continue_current",
				"announcement_reactions": reactions,
			},
		) as Dictionary
		_expect_equal(
			continue_result.get("errorCode"),
			"PLAYER_ANNOUNCEMENT_ACTION_REQUIRED",
			"World 本身拒绝只表态后继续普通工作",
		)
		_expect_equal(
			continue_result.get("consumed"),
			false,
			"被拒绝的继续工作不会消耗本轮决定",
		)
		var replacement_id := "%s-player-priority" % String(
			wake.get("decision_id", ""),
		)
		var replacement := world.call(
			"submit_agent_decision",
			SPEAKER_ID,
			{
				"decision_id": String(wake.get("decision_id", "")),
				"handling": "replace_current",
				"announcement_reactions": reactions,
				"action": {
					"action_id": replacement_id,
					"type": "待着",
					"line": "停下手头工作，重新安排眼前行动。",
				},
			},
		) as Dictionary
		_expect_equal(replacement.get("ok"), true, "居民可提交新行动处理玩家公告")
		_expect_equal(
			String((target.get("currentAction", {}) as Dictionary).get("action_id", "")),
			replacement_id,
			"玩家公告最终替换了持续中的普通行动",
		)
	var timed := world.call(
		"publish_announcement",
		"两小时后请到中央广场集合。",
	) as Dictionary
	var due_minute := int(
		(timed.get("announcement", {}) as Dictionary).get(
			"scheduled_absolute_minute",
			-1,
		),
	)
	_expect(due_minute >= 0, "玩家时间公告识别出到点时刻")
	ANNOUNCEMENT_RESIDENT_RUNTIME.advance_schedules(
		world, world.get("_community_bulletin"), due_minute,
	)
	_expect_equal(
		target.get("decisionPending"),
		true,
		"玩家公告到点会再次立即唤醒居民",
	)
	_expect_equal(
		target.get("decisionMayInterruptCurrent"),
		true,
		"玩家公告到点仍可替换普通行动",
	)
	var due_requests := world.call(
		"take_pending_decision_requests_by_ids",
		[SPEAKER_ID],
	) as Array
	var player_due_found := false
	if due_requests.size() == 1:
		for value: Variant in (
			(due_requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
		).get("events", []) as Array:
			var event := value as Dictionary
			if (
				String(event.get("type", "")) == "公告到点"
				and String(event.get("announcement_priority", "")) == "player"
			):
				player_due_found = true
	_expect(player_due_found, "玩家公告到点保留最高优先级标记")
	world.call("stop")
func _prepare_residents(opening: Dictionary) -> void:
	var positions := {
		POSTAL_ID: [4631, 2790],
		NOTICE_RECIPIENT_ID: [4663, 2790],
		SPEAKER_ID: [4700, 2790],
		LISTENER_ID: [4732, 2790],
		BYSTANDER_ID: [4764, 2790],
	}
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		var resident_id := String(resident.get("residentId", ""))
		var social := resident.get("socialState", {}) as Dictionary
		if resident_id == MANAGER_ID:
			social["job"] = "小镇管理者"
			social["workplace"] = "镇公所"
		elif resident_id == POSTAL_ID:
			social["job"] = "邮差"
			social["workplace"] = "小镇道路"
		if not positions.has(resident_id):
			continue
		var state := resident.get("worldState", {}) as Dictionary
		state["place"] = "小镇道路"
		state["spaceId"] = "town_outdoor"
		state["regionId"] = "outdoor_road_01"
		state["position"] = (positions[resident_id] as Array).duplicate()



func _test_board_and_bell(world: RefCounted) -> void:
	var board := world.call(
		"publish_announcement",
		"今晚广场有露天电影。",
	) as Dictionary
	_expect_equal(board.get("ok"), true, "普通公告进入公告栏")
	for resident_id: String in world.call("get_resident_ids") as Array[String]:
		_expect(
			_knows(
				world,
				resident_id,
				"announcement-1",
				"announcement_broadcast",
			),
			"普通公告立即让每名居民知情",
		)
	var bell := world.call(
		"broadcast_announcement",
		"钟响三声，暴雨将至，请尽快进屋。",
	) as Dictionary
	_expect_equal(bell.get("ok"), true, "敲钟公告可以发布")
	_expect(
		not String(bell.get("broadcastEventId", "")).is_empty(),
		"敲钟形成稳定的全镇事件",
	)
	_expect_equal(_announcement_event_count, 30, "两条公告各向十五名居民交付一次")
	for resident_id: String in world.call("get_resident_ids") as Array[String]:
		var knowledge := world.call(
			"announcement_knowledge_for",
			resident_id,
		) as Array
		_expect_equal(knowledge.size(), 2, "两条公告让每名居民知情")
		if not knowledge.is_empty():
			_expect_equal(
				(knowledge[1] as Dictionary).get("acquired_via"),
				"announcement_broadcast",
				"敲钟公告同样使用全局通知知情来源",
			)
	var requests := world.call(
		"take_pending_decision_requests_by_ids",
		[SPEAKER_ID],
	) as Array
	_expect(not requests.is_empty(), "知情居民能取得下一次自然决定")
	if not requests.is_empty():
		var wake := (
			(requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
		)
		_expect(
			(CONTRACT.validate_wake_packet(wake) as Array).is_empty(),
			"已知公告符合正式 Agent 唤醒合同",
		)
		_expect_equal(
			((wake.get("snapshot", {}) as Dictionary).get(
				"known_announcements",
				[],
			) as Array).size(),
			2,
			"居民的自然决定能读到两条已知公告",
		)



func _test_read_and_relay_do_not_duplicate(world: RefCounted) -> void:
	_expect_equal(
		world.call(
			"read_announcement",
			SPEAKER_ID,
			"announcement-1",
		).get("newKnowledge"),
		false,
		"阅读已广播公告不会重复知情",
	)
	_expect_equal(
		world.call(
			"relay_announcement",
			SPEAKER_ID,
			LISTENER_ID,
			"announcement-1",
		).get("newKnowledge"),
		false,
		"转告已广播公告不会重复知情",
	)



func _test_resident_notice_is_global(world: RefCounted) -> void:
	var source := world.call(
		"sync_resident_request",
		{
			"request_id": "formal-notice-source",
			"source_revision": 1,
			"requester_id": NOTICE_RECIPIENT_ID,
			"submitted": true,
			"active": true,
			"subject_ids": [NOTICE_RECIPIENT_ID],
			"place_id": "诊所",
			"capability_id": "bulletin.publish",
			"target_refs": {"text": NOTICE_TEXT},
			"success_result_id": "formal-notice-published",
			"expires_at": 3000,
			"capacity": 1,
			"source_event_ids": ["event-formal-notice"],
		},
	) as Dictionary
	_expect_equal(source.get("ok"), true, "正式通知有真实事项来源")
	var matter_id := String(
		(source.get("matter", {}) as Dictionary).get("matter_id", ""),
	)
	var published := world.call(
		"publish_resident_announcement",
		MANAGER_ID,
		NOTICE_TEXT,
		matter_id,
		"postal_notice",
	) as Dictionary
	_expect_equal(published.get("ok"), true, "管理者发布指定对象的正式通知")
	var announcement_id := String(
		(published.get("announcement", {}) as Dictionary).get(
			"announcement_id",
			"",
		),
	)
	for resident_id: String in world.call("get_resident_ids") as Array[String]:
		_expect(
			_knows(
				world,
				resident_id,
				announcement_id,
				(
					"publisher"
					if resident_id == MANAGER_ID
					else "announcement_broadcast"
				),
			),
			"居民发布的公告同样立即通知 %s" % resident_id,
		)
		_expect(
			_has_agent_matter(world, resident_id, matter_id),
			"关联事项立即进入 %s 的已知事项" % resident_id,
		)
	var manager_state := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(MANAGER_ID, {}) as Dictionary
	)
	var manager_announcement_events: Array = []
	manager_announcement_events.append_array(
		manager_state.get("eventQueue", []) as Array,
	)
	manager_announcement_events.append_array(
		manager_state.get("inflightEvents", []) as Array,
	)
	var publisher_received_own_event := false
	for event_value: Variant in manager_announcement_events:
		if (
			event_value is Dictionary
			and String((event_value as Dictionary).get("announcement_id", ""))
			== announcement_id
		):
			publisher_received_own_event = true
	_expect(
		not publisher_received_own_event,
		"居民发布者知道自己的公告，但不会收到一条自我回应事件",
	)
	_expect_equal(
		(world.call(
			"get_private_messages_for_resident",
			NOTICE_RECIPIENT_ID,
		) as Array).size(),
		0,
		"全局公告不再生成重复邮差通知",
	)
	var announcement_count_before := (
		world.call("get_announcements") as Array
	).size()
	var knowledge_count_before := (
		world.call(
			"announcement_knowledge_for",
			NOTICE_RECIPIENT_ID,
		) as Array
	).size()
	var rejected := world.call(
		"publish_resident_announcement",
		MANAGER_ID,
		"这条公告不应成立。",
		"matter-does-not-exist",
	) as Dictionary
	_expect_equal(rejected.get("ok"), false, "无效事项公告被整体拒绝")
	_expect_equal(
		(world.call("get_announcements") as Array).size(),
		announcement_count_before,
		"无效提交不会留下公告历史",
	)
	_expect_equal(
		(world.call(
			"announcement_knowledge_for",
			NOTICE_RECIPIENT_ID,
		) as Array).size(),
		knowledge_count_before,
		"无效提交不会留下部分居民知情",
	)



func _test_resident_notice_survives_restore(
	world: RefCounted,
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(save_result.get("ok"), true, "居民公告可以进入世界存档")
	if save_result.get("ok") != true:
		return
	var parsed: Variant = JSON.parse_string(JSON.stringify(
		save_result.get("snapshot", {}) as Dictionary,
	))
	var restored := world.call(
		"restore_from_snapshot",
		data,
		opening,
		parsed as Dictionary,
	) as Dictionary
	_expect_equal(
		restored.get("ok"),
		true,
		"居民发布的全局公告可从 JSON 存档恢复：%s"
		% str(restored.get("errors", [])),
	)
	_expect(
		_knows(world, MANAGER_ID, "announcement-3", "publisher"),
		"恢复后仍保留居民发布者的知情来源",
	)
	_expect(
		_knows(
			world,
			NOTICE_RECIPIENT_ID,
			"announcement-3",
			"announcement_broadcast",
		),
		"恢复后仍保留其他居民的全局知情来源",
	)


func _test_timed_announcement_due(world: RefCounted) -> void:
	var timed: Dictionary = {}
	for value: Variant in world.call("get_announcements") as Array:
		var announcement := value as Dictionary
		if String(announcement.get("announcement_id", "")) == "announcement-1":
			timed = announcement
			break
	var due_minute := int(timed.get("scheduled_absolute_minute", -1))
	_expect(
		due_minute > _absolute_minute(world.call("get_time")),
		"今晚公告识别出未来约定时间",
	)
	_expect_equal(
		String(timed.get("scheduled_time_label", "")),
		"第1天 20:00",
		"今晚使用稳定的世界时间标签",
	)
	var guard := 0
	while _absolute_minute(world.call("get_time")) < due_minute and guard < 12:
		world.call("cycle_time_period_for_test")
		guard += 1
	_expect(
		_absolute_minute(world.call("get_time")) >= due_minute,
		"测试时钟能够推进到公告约定时间",
	)
	var due_event_id := ""
	for value: Variant in world.call("get_public_event_log") as Array:
		var record := value as Dictionary
		var payload := record.get("payload", {}) as Dictionary
		if (
			String(payload.get("type", "")) == "公告到点"
			and String(payload.get("announcement_id", "")) == "announcement-1"
		):
			due_event_id = String(record.get("eventId", ""))
			break
	_expect(not due_event_id.is_empty(), "约定时间到达后形成一次公告到点事件")
	ANNOUNCEMENT_RESIDENT_RUNTIME.emit_reactions(
		world,
		BYSTANDER_ID,
		"timed-announcement-response",
		{},
		[{
			"source_event_id": due_event_id,
			"text": "时间到了，我现在过去看看。",
		}],
		[{
			"event_id": due_event_id,
			"type": "公告到点",
			"announcement_id": "announcement-1",
			"text": "今晚广场有露天电影。",
		}],
		[],
	)
	var detail := world.call(
		"get_world_log_thread_detail",
		"announcement:announcement-1",
		{},
	) as Dictionary
	_expect_equal(detail.get("ok"), true, "时间公告可从右侧事件链读取")
	_expect(
		String((detail.get("thread", {}) as Dictionary).get("title", "")).contains(
			"今晚广场有露天电影",
		),
		"居民回应追加后仍保留公告作为事件链标题",
	)
	_expect(
		String((detail.get("thread", {}) as Dictionary).get("title", "")).begins_with(
			"公告发布",
		),
		"到点提醒和居民回应不会改掉公告事件链的根标题",
	)
	var record_types: Array[String] = []
	for value: Variant in detail.get("records", []) as Array:
		record_types.append(String(
			((value as Dictionary).get("payload", {}) as Dictionary).get("type", ""),
		))
	_expect(
		record_types.has("公告发布")
		and record_types.has("公告到点")
		and record_types.has("居民公开反应"),
		"公告发布、到点提醒与居民回应保留在同一条右侧事件链",
	)
	var past_time := world.call(
		"publish_announcement",
		"今天上午十点在广场集合。",
	) as Dictionary
	_expect_equal(past_time.get("ok"), true, "未识别时间不影响公告本身发布")
	_expect_equal(
		past_time.get("scheduleWarning"),
		true,
		"过去的模糊时刻会明确告诉界面需要提醒玩家",
	)
	_expect_equal(
		past_time.get("scheduleRecognized"),
		false,
		"时间解析失败不会伪装成已设置到点提醒",
	)



func _knows(
	world: RefCounted,
	resident_id: String,
	announcement_id: String,
	via: String,
) -> bool:
	for value: Variant in world.call(
		"announcement_knowledge_for",
		resident_id,
	) as Array:
		var knowledge := value as Dictionary
		if (
			String(knowledge.get("announcement_id", "")) == announcement_id
			and String(knowledge.get("acquired_via", "")) == via
		):
			return true
	return false



func _has_agent_matter(
	world: RefCounted,
	resident_id: String,
	matter_id: String,
) -> bool:
	for value: Variant in world.call(
		"get_agent_social_matters",
		resident_id,
	) as Array:
		if String((value as Dictionary).get("matter_id", "")) == matter_id:
			return true
	return false



func _on_world_event_created(_resident_name: String, event: Dictionary) -> void:
	if String(event.get("type", "")) == "公告发布":
		_announcement_event_count += 1



func _scenario_relationship_evidence_progress() -> void:
	var names := {
		"resident_a": "甲",
		"resident_b": "乙",
		"resident_c": "丙",
		"resident_d": "丁",
	}
	var conversations := [
		{
			"conversationId": "conversation-1",
			"status": "ended",
			"participants": ["resident_a", "resident_b"],
			"turns": [
				{"status": "confirmed"},
				{"status": "confirmed"},
				{"status": "confirmed"},
				{"status": "confirmed"},
			],
			"endedAt": {"day": 2, "time": "10:00"},
		},
		{
			"conversationId": "conversation-active",
			"status": "active",
			"participants": ["resident_a", "resident_c"],
			"turns": [{"status": "confirmed"}],
		},
		{
			"conversationId": "conversation-runtime-name-shaped",
			"status": "ended",
			"participants": ["甲", "丙"],
			"turns": [
				{"status": "confirmed"},
				{"status": "completed"},
			],
			"endedAt": {"day": 2, "time": "11:30"},
		},
	]
	var matters := [
		{
			"matter_id": "matter-help",
			"creator_id": "resident_c",
			"subject_ids": [],
			"participants": {
				"resident_a": {
					"resident_id": "resident_a",
					"status": "completed",
				},
			},
		},
		{
			"matter_id": "matter-shared",
			"creator_id": "",
			"subject_ids": [],
			"participants": {
				"resident_a": {
					"resident_id": "resident_a",
					"status": "completed",
				},
				"resident_d": {
					"resident_id": "resident_d",
					"status": "completed",
				},
			},
		},
		{
			"matter_id": "matter-unfinished",
			"creator_id": "resident_b",
			"subject_ids": [],
			"participants": {
				"resident_a": {
					"resident_id": "resident_a",
					"status": "interrupted",
				},
			},
		},
	]
	var items := PROGRESS.build(
		"resident_a",
		names,
		conversations,
		matters,
	)
	_expect(items.size() == 3, "只应出现有确认共同证据的三位居民")
	var by_id := {}
	for item: Dictionary in items:
		by_id[String(item.get("residentId", ""))] = item
	var b := by_id.get("resident_b", {}) as Dictionary
	_expect(
		int(b.get("conversationCount", 0)) == 1
		and int(b.get("confirmedTurnCount", 0)) == 4
		and int(b.get("sharedMatterCount", 0)) == 0,
		"结束对话与确认轮次必须形成关系证据",
	)
	_expect(
		int((b.get("depth", {}) as Dictionary).get("level", 0)) == 2,
		"一段结束对话加四次确认轮次应显示两格进度",
	)
	var c := by_id.get("resident_c", {}) as Dictionary
	_expect(
		int(c.get("sharedMatterCount", 0)) == 1
		and int(c.get("conversationCount", 0)) == 1
		and int(c.get("confirmedTurnCount", 0)) == 2,
		"完成居民请求与真实 World 姓名形态对话都必须形成关系证据",
	)
	var d := by_id.get("resident_d", {}) as Dictionary
	_expect(
		int(d.get("sharedMatterCount", 0)) == 1,
		"共同完成同一社会事项必须形成一次共同经历",
	)
	_expect(
		not JSON.stringify(items).contains("_evidenceIds"),
		"公开进度不得泄漏内部证据去重键",
	)
	_expect(
		PROGRESS.build("unknown", names, conversations, matters).is_empty(),
		"未知居民必须失败关闭",
	)
	_test_public_memory_influence()
	return
func _test_public_memory_influence() -> void:
	var memory_system: RefCounted = MEMORY_SYSTEM.new(
		TestData.initialization(),
		_test_root,
	)
	var seeded := memory_system.call(
		"seed_debug_memory",
		TestData.organized_memory(),
	) as Dictionary
	_expect(
		seeded.get("ok") == true,
		"真实居民记忆必须能写入隔离测试存储",
	)
	var read_result := memory_system.call(
		"get_read_only_memory",
	) as Dictionary
	_expect(
		read_result.get("ok") == true,
		"居民公开记忆必须能读取",
	)
	var memory := read_result.get("memory", {}) as Dictionary
	var influence := (
		memory.get("important_memory_influence", {}) as Dictionary
	)
	_expect(
		influence.get("available") == true
		and int(influence.get("level", -1)) == 4
		and int(influence.get("segmentCount", 0)) == 5
		and String(influence.get("label", "")) == "明显影响",
		"重要记忆必须按真实跨字段影响生成 4/5 公开进度",
	)
	_expect(
		not String(memory.get("important_memories", "")).contains(
			"resident-tang-xiao-man",
		),
		"公开记忆进度不得泄漏内部居民 ID",
	)



func _scenario_announcement_long_history() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	var world: RefCounted = WORLD.new()
	_expect_equal(world.call("start", data, opening).get("ok"), true, "world starts")
	for request: Dictionary in world.call(
		"take_pending_decision_requests",
	) as Array[Dictionary]:
		var wake := request.get("wakePacket", {}) as Dictionary
		_expect_equal(
			world.call(
				"submit_agent_decision",
				String(request.get("residentName", "")),
				_wait_announcement_long_history(wake),
			).get("status"),
			"accepted",
			"resident begins waiting",
		)
	for index in 65:
		_expect_equal(
			world.call(
				"publish_announcement",
				"公告 %d" % (index + 1),
			).get("ok"),
			true,
			"announcement %d publishes" % (index + 1),
		)
	for index in 205:
		var weather := "小雨" if index % 2 == 0 else "晴天"
		_expect_equal(
			world.call("set_weather", weather).get("changed"),
			true,
			"weather event %d is recorded" % (index + 1),
		)
	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(save_result.get("ok"), true, "long history saves")
	var parsed: Variant = JSON.parse_string(
		JSON.stringify(save_result.get("snapshot", {})),
	)
	_expect(parsed is Dictionary, "long history survives JSON round trip")
	if not parsed is Dictionary:
		return
	var state := (parsed as Dictionary).get("state", {}) as Dictionary
	var bulletin := state.get("communityBulletin", {}) as Dictionary
	_expect_equal(
		(bulletin.get("announcements", []) as Array).size(),
		65,
		"canonical bulletin keeps all published announcements",
	)
	_expect(
		not _public_log_has_announcement(state, "announcement-1"),
		"bounded public log may discard the first announcement",
	)
	_expect(
		_pending_has_announcement(state, "announcement-1"),
		"resident pending delivery still references the first announcement",
	)
	var restore := world.call(
		"restore_from_snapshot",
		data,
		opening,
		parsed as Dictionary,
	) as Dictionary
	_expect_equal(
		restore.get("ok"),
		true,
		"long history restores (%s)" % str(restore.get("errors", [])),
	)
	var requests := world.call(
		"take_pending_decision_requests",
	) as Array[Dictionary]
	_expect_equal(requests.size(), 15, "all residents resume after restore")
	for request: Dictionary in requests:
		_expect(
			_wake_has_announcement(
				request.get("wakePacket", {}) as Dictionary,
				"announcement-1",
			),
			"restored resident receives the first announcement",
		)
	world.call("stop")
	world = null
	return
func _public_log_has_announcement(
	state: Dictionary,
	announcement_id: String,
) -> bool:
	for record_value: Variant in state.get("eventLog", []) as Array:
		var payload := (record_value as Dictionary).get(
			"payload",
			{},
		) as Dictionary
		if String(payload.get("announcement_id", "")) == announcement_id:
			return true
	return false



func _pending_has_announcement(
	state: Dictionary,
	announcement_id: String,
) -> bool:
	for resident_value: Variant in state.get("residents", []) as Array:
		for event_value: Variant in (
			(resident_value as Dictionary).get("pendingEvents", []) as Array
		):
			if String(
				(event_value as Dictionary).get("announcement_id", ""),
			) == announcement_id:
				return true
	return false



func _wake_has_announcement(
	wake: Dictionary,
	announcement_id: String,
) -> bool:
	for event_value: Variant in wake.get("events", []) as Array:
		if String(
			(event_value as Dictionary).get("announcement_id", ""),
		) == announcement_id:
			return true
	return false



func _wait_announcement_long_history(wake: Dictionary) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-wait" % decision_id,
			"type": "待着",
			"line": "在这里待着",
		},
	}



func _scenario_announcement_pending_arrival() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var loaded := OPENING.load_config(OPENING_PATH, data) as Dictionary
	var opening := FORMAL_OPENING.with_authoritative_new_game_spawns(
		data,
		loaded.get("config", {}) as Dictionary,
	)
	var world: RefCounted = WORLD.new()
	_expect_equal(
		world.call(
			"start_formal",
			data,
			opening,
			_resident_identities(opening),
		).get("ok"),
		true,
		"待抵达居民正式世界可启动",
	)
	_expect_equal(
		(world.call("take_pending_decision_requests") as Array).size(),
		0,
		"居民抵达前没有决定请求",
	)
	_expect_equal(
		world.call(
			"publish_announcement",
			"中午前到镇公所登记。",
		).get("ok"),
		true,
		"待抵达期间可以发布全局公告",
	)
	var resident_ids := world.call("get_resident_ids") as Array[String]
	for resident_id: String in resident_ids:
		_expect_equal(
			(world.call(
				"announcement_knowledge_for",
				resident_id,
			) as Array).size(),
			1,
			"待抵达居民已经保留公告知情",
		)
	_expect_equal(
		(world.call("take_pending_decision_requests") as Array).size(),
		0,
		"公告不会提前唤醒尚未抵达的居民",
	)
	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(save_result.get("ok"), true, "待交付公告可以保存")
	var state := (
		(save_result.get("snapshot", {}) as Dictionary).get("state", {})
		as Dictionary
	)
	var saved_with_announcement := 0
	for value: Variant in state.get("residents", []) as Array:
		for event_value: Variant in (value as Dictionary).get(
			"pendingEvents",
			[],
		) as Array:
			if String((event_value as Dictionary).get("type", "")) == "公告发布":
				saved_with_announcement += 1
	_expect_equal(saved_with_announcement, 15, "十五份待交付公告都进入存档")

	var first_arrival_minute := 1 << 30
	for value: Variant in world.call("get_all_resident_states") as Array:
		first_arrival_minute = mini(
			first_arrival_minute,
			int(((value as Dictionary).get(
				"arrivalState",
				{},
			) as Dictionary).get("scheduledAbsoluteMinute", first_arrival_minute)),
		)
	while _absolute_minute(world.call("get_time")) < first_arrival_minute:
		world.call("advance", 1.0)
	var requests := world.call("take_pending_decision_requests") as Array
	_expect_equal(requests.size(), 1, "首名居民抵达后才收到决定请求")
	if requests.size() == 1:
		var wake := (requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
		_expect(_wake_has_event(wake, "公告发布"), "首名居民抵达后取得公告正文")
	world.call("stop")
	return
func _resident_identities(opening: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		result.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(resident.get("attributes", {}) as Dictionary).get("name", ""),
			),
		})
	return result



func _absolute_minute(time: Dictionary) -> int:
	var parts := String(time.get("clock", "00:00")).split(":")
	return (int(time.get("day", 1)) - 1) * 1440 + int(parts[0]) * 60 + int(parts[1])



func _wake_has_event(wake: Dictionary, event_type: String) -> bool:
	for event_value: Variant in wake.get("events", []) as Array:
		if String((event_value as Dictionary).get("type", "")) == event_type:
			return true
	return false
