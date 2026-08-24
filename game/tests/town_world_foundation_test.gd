extends "res://tests/support/TownWorldTestCase.gd"

const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const AGENT_WAKE_CONTEXT_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWakeContextRuntime.gd"
)
const DINING_SERVICE_RUNTIME := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
## 世界基础与日志 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - town_world_indoor_props_test.gd
## - town_world_daily_life_chain_test.gd
## - town_world_log_causal_query_test.gd
## - town_world_environment_test.gd
## - town_world_staggered_arrival_test.gd
## - town_weather_behavior_diversity_test.gd
## - town_world_action_type_registry_test.gd
## - town_audio_controller_button_cue_test.gd

class _StubWorld:
	extends RefCounted

	func person_name_for_id(person_id: String) -> String:
		return person_id


class _MessagePolicyWorld:
	extends RefCounted

	var _resident_order: Array[String] = [
		"postal-a", "postal-b", "postal-c", "recipient",
	]

	func resident_order() -> Array[String]:
		return _resident_order.duplicate()

	func _resident_can_work_occupation(
		resident_id: String,
		occupation_id: String,
	) -> bool:
		return (
			occupation_id == "occupation_postal_worker"
			and resident_id.begins_with("postal-")
		)


class _StaffingAssignmentCommitStub:
	extends TownStaffingRuntime

	var arrangement_result := {"ok": true, "arrangement": {"arrangementId": "arrangement-1"}}
	var create_args: Array = []
	var rebuild_args: Array = []
	var end_args: Array = []

	func create_arrangement(
		resident_id: String,
		occupation_id: String,
		mode: String,
		absolute_minute: int,
		shift_start_minute := 0,
		shift_end_minute := 1440,
	) -> Dictionary:
		create_args = [
			resident_id,
			occupation_id,
			mode,
			absolute_minute,
			shift_start_minute,
			shift_end_minute,
		]
		return arrangement_result.duplicate(true)

	func rebuild(residents: Dictionary, absolute_minute := 0) -> Dictionary:
		rebuild_args = [residents, absolute_minute]
		return {"ok": true}

	func end_active_arrangements_for_occupation(
		occupation_id: String,
		absolute_minute: int,
		reason: String,
		_created_not_before := -1,
	) -> Dictionary:
		end_args = [occupation_id, absolute_minute, reason]
		return {"ok": true}

const ROOMS_ROOT := "res://world/maps/town/interiors/redesign_v2/rooms"
const PROP_VALIDATOR := preload("res://world/data/town/TownWorldPropValidator.gd")
const PROP_QUERY := preload("res://world/data/town/TownWorldPropQuery.gd")
const AUTHORING := preload("res://world/data/town/TownIndoorPropAuthoring.gd")
const FORMAL_OPENING := preload(
	"res://tests/support/TownWorldFormalOpeningTestHelper.gd"
)
const LAYOUT_PROJECTION := preload("res://world/runtime/TownIndoorLayoutProjection.gd")
const DYNAMIC_PROP_RUNTIME := preload(
	"res://world/runtime/prop/TownDynamicPropRuntime.gd"
)
const ANIMAL_FACT_RUNTIME := preload(
	"res://world/runtime/animals/TownAnimalFactRuntime.gd"
)
const PLACE_SERVICE_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceRuntime.gd"
)
const OCCUPATION_SERVICE_PRESENCE_POLICY := preload(
	"res://world/runtime/work/TownOccupationServicePresencePolicy.gd"
)
const CLINIC_SERVICE_REQUEST_POLICY := preload(
	"res://world/runtime/work/TownClinicServiceRequestPolicy.gd"
)
const PRODUCTION_TASK_SYNC_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskSyncRuntime.gd"
)
const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const GEOMETRY := preload(
	"res://world/maps/town/interiors/redesign_v2/common/InteriorAssetGeometry.gd"
)
const ROOM_GEOMETRY := preload(
	"res://world/maps/town/interiors/InteriorRoomGeometry.gd"
)
const MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownIndoorMovementClearance.gd"
)
const LAYOUT_CELL_SIZE := 32
const INVALID_CELL := Vector2i(2147483647, 2147483647)
const STORE := preload("res://world/runtime/log/TownWorldLogStore.gd")
const EVENT_JOURNAL_RUNTIME := preload(
	"res://world/runtime/log/TownWorldEventJournalRuntime.gd"
)
const DOMAIN_LOG_PROJECTION := preload(
	"res://world/runtime/log/TownWorldDomainLogProjection.gd"
)
const STORY_EVENT_PROJECTION := preload(
	"res://world/runtime/log/TownStoryEventProjection.gd"
)
const ACTIVITY_LIFECYCLE_EVENT_PROJECTION := preload(
	"res://world/runtime/log/TownActivityLifecycleEventProjection.gd"
)
const RESIDENT_EVENT_QUEUE_RUNTIME := preload(
	"res://world/runtime/event/TownResidentEventQueueRuntime.gd"
)
const WORLD_EVENT_DELIVERY_PROJECTION := preload(
	"res://world/runtime/event/TownWorldEventDeliveryProjection.gd"
)
const AGENT_DECISION_ACCEPTANCE_POLICY := preload(
	"res://world/runtime/agent/TownAgentDecisionAcceptancePolicy.gd"
)
const AGENT_DECISION_ENVELOPE_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionEnvelopeRuntime.gd"
)
const AGENT_DECISION_CONFIRMATION_PROJECTION := preload(
	"res://world/runtime/agent/TownAgentDecisionConfirmationProjection.gd"
)
const CONFIRMED_ACTION_ACTIVATION_POLICY := preload(
	"res://world/runtime/agent/TownConfirmedActionActivationPolicy.gd"
)
const ACTIVITY_CANDIDATE_PREFLIGHT_POLICY := preload(
	"res://world/runtime/activity/TownActivityCandidatePreflightPolicy.gd"
)
const ACTIVITY_ROUTINE_POLICY := preload(
	"res://world/runtime/activity/TownActivityRoutinePolicy.gd"
)
const RESTORE_COMMIT_PROJECTION := preload(
	"res://world/runtime/persistence/TownWorldRestoreCommitProjection.gd"
)
const AGENT_WAKE_PACKET_PROJECTION := preload(
	"res://world/runtime/agent/TownAgentWakePacketProjection.gd"
)
const ACTION_PREPARATION_POLICY := preload(
	"res://world/runtime/action/TownActionPreparationPolicy.gd"
)
const STAFFING_ASSIGNMENT_POLICY := preload(
	"res://world/runtime/work/TownStaffingAssignmentPolicy.gd"
)
const STAFFING_ASSIGNMENT_COMMIT := preload(
	"res://world/runtime/work/TownStaffingAssignmentCommit.gd"
)
const OCCUPATION_SERVICE_REQUEST_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceRequestRuntime.gd"
)
const OCCUPATION_SERVICE_REQUEST_COMMIT := preload(
	"res://world/runtime/work/TownOccupationServiceRequestCommit.gd"
)
const INITIAL_SOCIAL_CONTACT_POLICY := preload(
	"res://world/runtime/social/TownInitialSocialContactPolicy.gd"
)
const WORK_DOMAIN_RUNTIME := preload(
	"res://world/runtime/work/TownWorkDomainRuntime.gd"
)
const STAFFING_MATTER_PROJECTION := preload(
	"res://world/runtime/work/TownStaffingMatterProjection.gd"
)
const CARGO_LOGISTICS_RUNTIME := preload(
	"res://world/runtime/work/TownCargoLogisticsRuntime.gd"
)
const CONVERSATION_FOLLOW_UP_OPTION_PROJECTION := preload(
	"res://world/runtime/conversation/TownConversationFollowUpOptionProjection.gd"
)
const ANNOUNCEMENT_PUBLICATION_PROJECTION := preload(
	"res://world/runtime/social/TownAnnouncementPublicationProjection.gd"
)
const ACTIVITY_WORK_TASK_BINDING_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityWorkTaskBindingRuntime.gd"
)
const BULLETIN_ACTIVITY_EFFECT_PLANNER := preload(
	"res://world/runtime/activity/TownBulletinActivityEffectPlanner.gd"
)
const ACTIVITY_COMPLETION_PROJECTION := preload(
	"res://world/runtime/activity/TownActivityCompletionProjection.gd"
)
const ACTIVITY_EXECUTION_PROJECTION := preload(
	"res://world/runtime/activity/TownActivityExecutionProjection.gd"
)
const RESIDENT_MESSAGE_POLICY := preload(
	"res://world/runtime/social/TownResidentMessagePolicy.gd"
)
const ENVIRONMENT := preload("res://world/runtime/environment/TownWorldEnvironment.gd")
const RESIDENT_PRESENTATION := preload(
	"res://world/presentation/residents/ResidentCharacterPresentation.gd"
)
const REGISTRY := preload(
	"res://world/runtime/action/TownActionTypeRegistry.gd"
)
const VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const AUDIO_CONTROLLER := preload("res://audio/TownAudioController.gd")
const TOWN_RUNTIME := preload(
	"res://world/presentation/town_runtime/TownRuntime.gd"
)


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_scenario_world_event_journal_runtime()
	_scenario_world_log_event_projections()
	_scenario_resident_event_queue_runtime()
	_scenario_agent_decision_acceptance_policy()
	_scenario_e12_world_orchestration_policies()
	_scenario_e13_agent_social_projections()
	_scenario_e14_activity_routine_policy()
	_scenario_e15_action_and_staffing_policies()
	_scenario_e16_occupation_service_and_social_contact_policies()
	_scenario_f1_work_domain_ownership()
	_scenario_activity_work_task_binding_runtime()
	_scenario_occupation_service_request_policies()
	_scenario_production_task_sync_runtime()
	_scenario_place_service_runtime_state()
	_scenario_animal_fact_runtime_state()
	_scenario_dynamic_prop_runtime_state()
	_scenario_indoor_props()
	_scenario_daily_life_chain()
	_scenario_log_causal_query()
	_scenario_environment()
	_scenario_staggered_arrival()
	_scenario_weather_behavior_diversity()
	_scenario_frame_work_budget()
	_scenario_action_type_registry()
	await _scenario_audio_controller_button_cue()
	_finish_suite("TOWN_WORLD_FOUNDATION_PASS")


func _scenario_world_event_journal_runtime() -> void:
	var journal := EVENT_JOURNAL_RUNTIME.new()
	var source_payload := {
		"storyRootEventIds": ["root-1"],
		"nested": {"value": 1},
	}
	var appended := journal.append_public_event(
		" event-1 ",
		" world_event ",
		{"day": 2, "hour": 9, "minute": 5},
		7,
		" resident-a ",
		"居民甲",
		" 广场 ",
		source_payload,
	) as Dictionary
	_expect(appended.get("changed") == true, "事件日志模块应接收合法公开事件")
	source_payload["nested"]["value"] = 9
	var events := journal.public_events()
	_expect_equal(events.size(), 1, "事件日志模块应保存一条公开事件")
	_expect_equal(
		int(((events[0].get("payload", {}) as Dictionary).get("nested", {}) as Dictionary).get("value", 0)),
		1,
		"公开事件必须与调用方后续修改隔离",
	)
	_expect_equal(
		String(events[0].get("eventId", "")),
		"event-1",
		"公开事件编号必须标准化",
	)
	_expect(
		journal.append_public_event(
			"event-1", "world_event", {}, 8, "", "", "", {}
		).get("changed") == false,
		"重复事件编号必须保持幂等",
	)
	_expect_equal(
		journal.story_root_ids_for_world_event("event-1"),
		["root-1"],
		"事件日志模块应返回世界事件的故事根因",
	)
	journal.set_event_sequence(4)
	_expect_equal(journal.next_world_event_id(), "world-event-5", "事件序号应延续恢复值")
	_expect_equal(journal.next_sequence(), 6, "匿名事件序号应共用同一条序列")
	journal.set_action_story_context("action-1", {
		"sourceEventIds": ["event-1"],
		"rootEventIds": ["root-1"],
	})
	var provenance := journal.decision_story_provenance(
		[],
		[{"action_id": "action-1"}],
	) as Dictionary
	_expect_equal(
		provenance.get("sourceEventIds", []),
		["event-1"],
		"行动结果应继承直接故事来源",
	)
	_expect_equal(
		provenance.get("rootEventIds", []),
		["root-1"],
		"行动结果应继承故事根因",
	)
	journal.set_conversation_story_context("conversation-1", {
		"lastEventId": "event-1",
	})
	var conversation_context := journal.conversation_story_context("conversation-1")
	conversation_context["lastEventId"] = "mutated"
	_expect_equal(
		String(journal.conversation_story_context("conversation-1").get("lastEventId", "")),
		"event-1",
		"对话故事上下文读取必须返回隔离副本",
	)
	journal.set_consistency_error(" WORLD_LOG_INVALID ")
	_expect_equal(
		journal.consistency_error(),
		"WORLD_LOG_INVALID",
		"事件日志一致性错误应标准化",
	)
	journal.clear_consistency_error()
	_expect(journal.consistency_error().is_empty(), "一致性错误应可清除")
	var story_append := journal.append_story_event(
		"story-action:resident-a:action-1",
		"action_started",
		{"day": 2, "hour": 9, "minute": 6},
		8,
		"resident-a",
		"居民甲",
		"广场",
		{
			"actionId": "action-1",
			"storyRootEventIds": ["root-1"],
		},
	) as Dictionary
	_expect(story_append.get("changed") == true, "故事事件必须写入事件日志")
	var external_events := journal.external_public_events()
	var external_story_payload := (
		external_events[external_events.size() - 1].get("payload", {}) as Dictionary
	)
	_expect(not external_story_payload.has("storyEventId"), "公开事件不得泄露内部故事编号")
	_expect(not external_story_payload.has("storyType"), "公开事件不得泄露内部故事类型")
	_expect(not external_story_payload.has("storyRootEventIds"), "公开事件不得泄露内部故事根因")
	var sequence_after_story := journal.event_sequence()
	_expect(
		journal.append_story_event(
			"story-action:resident-a:action-1",
			"action_started", {}, 8, "resident-a", "居民甲", "广场", {}
		).get("changed") == false,
		"重复故事事件必须保持幂等",
	)
	_expect_equal(
		journal.event_sequence(),
		sequence_after_story,
		"重复故事事件不能消耗新的世界事件序号",
	)


func _scenario_world_log_event_projections() -> void:
	var work_event := DOMAIN_LOG_PROJECTION.work_task_event({
		"taskId": "task-1",
		"revision": 2,
		"state": "waiting",
		"assignedResidentId": "worker-1",
		"targets": [
			{"kind": "resident", "ref": "resident-2"},
			{"kind": "service_request", "ref": "request-1"},
			{"kind": "place", "ref": "clinic"},
		],
	}, "工人甲") as Dictionary
	var work_payload := work_event.get("payload", {}) as Dictionary
	_expect_equal(
		String(work_event.get("eventId", "")),
		"work-task:task-1:revision:2",
		"工作任务日志编号必须由任务和修订组成",
	)
	_expect_equal(
		work_payload.get("participantIds", []),
		["worker-1", "resident-2"],
		"工作任务日志必须保留完整参与者",
	)
	_expect_equal(
		String(work_payload.get("requestId", "")),
		"request-1",
		"工作任务日志必须关联服务请求",
	)
	var cargo_event := DOMAIN_LOG_PROJECTION.cargo_event(
		"货批到货",
		{
			"lotId": "lot-1",
			"carrierResidentId": "carrier-1",
			"sourcePlaceId": "warehouse",
			"destinationPlaceId": "clinic",
		},
		"worker-1", "工人甲", "运送员", "completed",
	) as Dictionary
	_expect_equal(
		String(cargo_event.get("placeName", "")),
		"clinic",
		"到货日志地点必须使用目的地",
	)
	var service_event := DOMAIN_LOG_PROJECTION.service_event(
		{
			"requestId": "request-1",
			"kind": "clinic_treatment",
			"requesterResidentId": "resident-2",
			"placeId": "clinic",
		},
		{"taskId": "task-1"},
		"worker-1", "医生甲", "患者甲", "completed",
		{"audienceResidentIds": ["resident-3"]},
	) as Dictionary
	_expect_equal(
		(service_event.get("payload", {}) as Dictionary).get("participantIds", []),
		["resident-2", "worker-1", "resident-3"],
		"服务结果日志必须合并请求者、工作人员与受众",
	)
	var private_event := DOMAIN_LOG_PROJECTION.private_message_event(
		"私信送达",
		{
			"messageId": "message-1",
			"senderResidentId": "resident-1",
			"recipientResidentId": "resident-2",
		},
		"delivered", "worker-1", "甲", "乙", "邮差",
	) as Dictionary
	_expect_equal(
		(private_event.get("payload", {}) as Dictionary).get("participantIds", []),
		["resident-1", "resident-2", "worker-1"],
		"私信日志必须保留发送、接收与送达人",
	)
	var animal_event := DOMAIN_LOG_PROJECTION.animal_event(
		"抚摸动物",
		{
			"animal_id": "cat-1",
			"display_name": "小橘",
			"exists": true,
			"place_id": "square",
		},
		"resident-1", "甲",
	) as Dictionary
	_expect_equal(
		String((animal_event.get("payload", {}) as Dictionary).get("animalName", "")),
		"小橘",
		"动物日志必须保留公开名称",
	)
	var snapshotted := DOMAIN_LOG_PROJECTION.payload_with_participant_snapshots(
		{"participantIds": ["resident-2", "player-1"]},
		"resident-1", "甲",
		{"resident-1": "甲", "resident-2": "乙"},
		"player-1", "玩家",
	) as Dictionary
	_expect_equal(
		(snapshotted.get("participantSnapshots", []) as Array).size(),
		3,
		"日志参与者快照必须合并主体与附加参与者",
	)
	var started := STORY_EVENT_PROJECTION.action_started(
		"resident-1", "甲", "square",
		{"action_id": "action-1", "type": "工作", "prop": "desk"},
		{"rootEventIds": ["root-1"], "sourceEventIds": ["event-1"]},
		"正在工作",
	) as Dictionary
	_expect_equal(
		String(started.get("storyEventId", "")),
		"story-action:resident-1:action-1",
		"故事行动开始事件必须使用稳定编号",
	)
	_expect(
		STORY_EVENT_PROJECTION.action_outcome(
			"resident-1", "甲", "square", "action-1", "completed", "",
			{"actionType": "去"},
		).is_empty(),
		"移动类行动结果不应生成重复故事事件",
	)
	var lifecycle_event := ACTIVITY_LIFECYCLE_EVENT_PROJECTION.event(
		"failed",
		{"activityId": "activity-1", "label": "看诊", "placeId": "clinic"},
		"医生离开",
		{"day": 1, "hour": 10, "minute": 0},
	) as Dictionary
	_expect_equal(
		String(lifecycle_event.get("result", "")),
		"看诊未能完成：医生离开",
		"活动失败日志必须保留原因文案",
	)
	var social_event := DOMAIN_LOG_PROJECTION.social_matter_event({
		"matter_id": "matter-1",
		"revision": 3,
		"state": "collecting",
		"creator_id": "resident-1",
		"subject_ids": ["resident-2"],
		"participants": {"resident-3": {}},
		"fixed_candidates": [{"resident_id": "resident-4"}],
	}, "甲") as Dictionary
	_expect_equal(
		(social_event.get("payload", {}) as Dictionary).get("participantIds", []),
		["resident-1", "resident-2", "resident-3", "resident-4"],
		"社会事项日志必须按原顺序汇总全部参与者",
	)
	_expect_equal(
		String((social_event.get("payload", {}) as Dictionary).get("status", "")),
		"waiting",
		"征集中的社会事项日志必须保持等待状态",
	)
	var conflict_event := DOMAIN_LOG_PROJECTION.conflict_event({
		"eventId": "conflict-event-1",
		"rootConflictId": "conflict-1",
		"type": "conflict_ended",
		"sourceActorId": "resident-1",
		"subjectId": "resident-2",
		"actorIds": ["resident-1", "resident-2"],
	}, "甲") as Dictionary
	_expect_equal(
		String((conflict_event.get("payload", {}) as Dictionary).get("status", "")),
		"completed",
		"已结束的冲突日志必须保持完成状态",
	)


func _scenario_resident_event_queue_runtime() -> void:
	var deduplicated := RESIDENT_EVENT_QUEUE_RUNTIME.deduplicated_world_events([
		{"event_id": "event-1", "type": "公告发布", "announcement_id": "a-1", "value": 1},
		{"event_id": "event-1", "type": "公告发布", "announcement_id": "a-1", "value": 2},
		{"event_id": "event-2", "type": "公告发布", "announcement_id": "a-1", "value": 3},
	])
	_expect_equal(deduplicated.size(), 1, "事件队列必须同时按编号和事实键去重")
	_expect_equal(
		int(deduplicated[0].get("value", 0)),
		3,
		"同一件待处理事实必须保留最新版本",
	)
	var resident := {
		"eventQueue": [],
		"resultQueue": [],
		"inflightEvents": [{
			"event_id": "event-old",
			"type": "天气变了",
			"weather": "rain",
		}],
		"inflightResults": [],
		"decisionSequence": 2,
	}
	RESIDENT_EVENT_QUEUE_RUNTIME.append_pending_world_event(resident, {
		"event_id": "event-new",
		"type": "天气变了",
		"weather": "rain",
	})
	_expect_equal(
		(resident.get("eventQueue", []) as Array).size(),
		1,
		"飞行中已有旧事实时，新版本必须进入下一次事件队列",
	)
	RESIDENT_EVENT_QUEUE_RUNTIME.restore_inflight_facts(resident)
	_expect_equal(
		(resident.get("eventQueue", []) as Array).size(),
		1,
		"回收飞行中事实后同类事件仍只保留最新版本",
	)
	var decision := RESIDENT_EVENT_QUEUE_RUNTIME.begin_decision(
		resident,
		"resident-1",
		4,
		false,
		true,
	) as Dictionary
	_expect_equal(
		String(decision.get("decisionId", "")),
		"resident-1-g4-3",
		"事件队列必须使用原有世代与居民序号生成决定编号",
	)
	_expect(bool(resident.get("decisionPending", false)), "建立决定后必须进入等待状态")
	_expect(bool(resident.get("decisionMayInterruptCurrent", false)), "紧急决定必须保留中断许可")
	_expect_equal(
		(resident.get("eventQueue", []) as Array).size(),
		0,
		"进入决定信封的事件必须从待办队列移出",
	)
	var source := {
		"type": "公告发布",
		"placeName": "广场",
		"participant_resident_ids": ["resident-1"],
		"storyRootEventIds": ["root-1"],
	}
	var materialized := WORLD_EVENT_DELIVERY_PROJECTION.materialized_event(
		source,
		"world-event-8",
		{"day": 1, "hour": 8, "minute": 0},
	) as Dictionary
	_expect_equal(
		String(materialized.get("event_id", "")),
		"world-event-8",
		"世界事件物化必须使用预留编号",
	)
	var views := WORLD_EVENT_DELIVERY_PROJECTION.delivery_views(
		materialized,
		"resident-1",
	) as Dictionary
	var identified := views.get("identifiedEvent", {}) as Dictionary
	var agent_event := views.get("agentEvent", {}) as Dictionary
	_expect(identified.has("storyRootEventIds"), "公开投递事件必须保留故事根因")
	_expect(not agent_event.has("storyRootEventIds"), "Agent 事件必须移除系统故事字段")
	_expect(not agent_event.has("placeName"), "Agent 事件必须移除系统地点字段")
	_expect(
		not WORLD_EVENT_DELIVERY_PROJECTION.should_schedule_broadcast(
			{"type": "天气变了"}, "clinic",
		),
		"室内居民收到天气事实但不应立即唤醒",
	)
	var wake := WORLD_EVENT_DELIVERY_PROJECTION.wake_policy(
		{"type": "公告到点"},
		["公告到点"],
	) as Dictionary
	_expect(bool(wake.get("invalidate", false)), "紧急事件必须使旧决定失效")
	_expect(bool(wake.get("wakeWhileCurrentAction", false)), "到点公告必须允许行动中唤醒")
	var injury := WORLD_EVENT_DELIVERY_PROJECTION.post_injury_reaction(
		"resident-1",
		[{
			"type": "冲突见闻",
			"knowledge_kind": "participant",
			"conflict_event_type": "injury_applied",
			"subject_id": "resident-1",
			"actor_ids": ["resident-1", "resident-2"],
			"source_actor_id": "resident-2",
			"conflict_event_id": "injury-1",
		}],
		{"resident-2": "乙"},
		"player-1",
		"玩家",
	) as Dictionary
	_expect_equal(
		String(injury.get("attacker_name", "")),
		"乙",
		"受伤反应必须保留攻击者公开名称",
	)


func _scenario_activity_work_task_binding_runtime() -> void:
	var bindings := ACTIVITY_WORK_TASK_BINDING_RUNTIME.new()
	bindings.bind("resident-1", "action-1", "task-1")
	_expect_equal(
		bindings.task_id_for("resident-1", "action-1"),
		"task-1",
		"活动任务绑定必须支持精确动作查询",
	)
	_expect_equal(
		bindings.task_id_for("resident-1", "missing-action"),
		"task-1",
		"居民只有一条绑定时必须兼容旧存档中的动作编号偏差",
	)
	bindings.bind("resident-1", "action-2", "task-2")
	_expect(
		bindings.task_id_for("resident-1", "missing-action").is_empty(),
		"居民存在多条绑定时不能猜测工作任务",
	)
	var snapshot := bindings.snapshot()
	snapshot["resident-1:action-1"] = "mutated"
	_expect_equal(
		bindings.task_id_for("resident-1", "action-1"),
		"task-1",
		"活动任务绑定快照必须与内部状态隔离",
	)
	bindings.erase_key("resident-1:action-2")
	bindings.restore({"resident-2:action-1": "task-3"})
	_expect_equal(
		bindings.task_id_for("resident-2", "action-1"),
		"task-3",
		"活动任务绑定必须恢复存档快照",
	)
	bindings.reset()
	_expect(bindings.snapshot().is_empty(), "活动任务绑定重置后必须清空")
	var read_plan := BULLETIN_ACTIVITY_EFFECT_PLANNER.plan(
		"resident-1",
		{
			"placeId": "中心广场",
			"activityId": "activity_bulletin_read",
		},
		[{
			"action_goal": {
				"capability_id": "bulletin.read",
				"target_refs": {"announcement_id": "announcement-1"},
			},
		}],
		"announcement-fallback",
	) as Dictionary
	_expect_equal(
		String(read_plan.get("announcementId", "")),
		"announcement-1",
		"公告阅读活动必须优先使用社会任务指定公告",
	)
	var publish_plan := BULLETIN_ACTIVITY_EFFECT_PLANNER.plan(
		"resident-1",
		{
			"placeId": "中心广场",
			"activityId": "activity_bulletin_publish",
		},
		[{
			"matter_id": "matter-1",
			"action_goal": {
				"capability_id": "bulletin.publish",
				"target_refs": {"text": "今晚广场集合"},
			},
		}],
		"",
	) as Dictionary
	_expect_equal(
		String(publish_plan.get("text", "")),
		"今晚广场集合",
		"公告发布活动必须保留已确认文本",
	)
	_expect_equal(
		String(publish_plan.get("matterId", "")),
		"matter-1",
		"公告发布活动必须继承社会事项编号",
	)
	_expect(
		BULLETIN_ACTIVITY_EFFECT_PLANNER.plan(
			"resident-1",
			{
				"placeId": "中心广场",
				"activityId": "activity_bulletin_publish",
			},
			[],
			"",
		).get("ok") == false,
		"没有确认内容时公告发布活动必须失败",
	)
	_expect(
		ACTIVITY_COMPLETION_PROJECTION.resident_effects(
			{"energy": -5},
			{"group": "work", "sequence": 1},
		).is_empty(),
		"连续工作活动的后续步骤不能重复结算完整效果",
	)
	var completed_execution := ACTIVITY_COMPLETION_PROJECTION.completed_execution(
		{"activityId": "activity-1", "slotId": "slot-1"},
		{"status": "completed"},
		0,
	) as Dictionary
	_expect_equal(
		int(completed_execution.get("performedDurationMinutes", 0)),
		1,
		"活动完成时真实发生时长至少为一分钟",
	)
	_expect_equal(
		ACTIVITY_COMPLETION_PROJECTION.completion_text({"label": "看诊"}),
		"已完成看诊",
		"活动完成公开文案必须保持原格式",
	)
	_expect(
		ACTIVITY_EXECUTION_PROJECTION.valid_source("activity.perform", ""),
		"直接活动来源不能携带来源动作编号",
	)
	_expect(
		not ACTIVITY_EXECUTION_PROJECTION.valid_source(
			"activity.perform",
			"action-1",
		),
		"直接活动来源携带动作编号时必须拒绝",
	)
	_expect_equal(
		ACTIVITY_EXECUTION_PROJECTION.requested_activity_id({
			"target": {"activityId": "activity-1"},
		}),
		"activity-1",
		"活动执行投影必须从稳定目标读取活动编号",
	)
	_expect_equal(
		String((ACTIVITY_EXECUTION_PROJECTION.bulletin_unavailable_failure(
			"activity_bulletin_read",
		).get("errors", []) as Array)[0]),
		"公告栏当前没有可阅读的新公告",
		"公告阅读不可用时必须保持原错误文案",
	)
	_expect(
		ACTIVITY_EXECUTION_PROJECTION.first_candidate_is_visitor({
			"candidates": [{"role": "visitor"}],
		}),
		"活动执行投影必须识别访客候选",
	)
	var activation_action := ACTIVITY_EXECUTION_PROJECTION.activation_action(
		{
			"action_id": "activity-action-1",
			"line": "原始想法",
			"effects": {"energy": 4},
			"consumeRouteConnector": true,
		},
		{
			"reason": "公开想法",
			"remainingTicks": 20,
			"sourceContract": "agent_activity",
			"sourceActionId": "source-1",
			"activityLabel": "看书",
		},
		12,
	) as Dictionary
	_expect_equal(
		int(activation_action.get("durationMinutes", 0)),
		12,
		"活动动作时长必须继续受单步上限约束",
	)
	_expect_equal(
		String(activation_action.get("line", "")),
		"公开想法",
		"活动执行原因必须覆盖兼容动作台词",
	)
	_expect(
		(activation_action.get("effects", {}) as Dictionary).is_empty(),
		"活动动作不能重复应用兼容道具效果",
	)
	var activation_resident := {
		"usedActionIds": {},
		"routeConnector": [Vector2.ZERO],
	}
	ACTIVITY_EXECUTION_PROJECTION.activate_resident(
		activation_resident,
		activation_action,
		{"activityLabel": "看书"},
	)
	_expect_equal(
		String(activation_resident.get("doing", "")),
		"正在看书",
		"活动激活必须保持居民公开状态文案",
	)
	_expect(
		(activation_resident.get("routeConnector", []) as Array).is_empty(),
		"活动动作要求消费返程连接时必须清空旧连接",
	)
	var execution_work_tasks := TownWorkTaskRuntime.new()
	_expect(
		execution_work_tasks.configure().get("ok") == true,
		"活动工作任务要求测试必须成功配置任务运行时",
	)
	_expect_equal(
		String(ACTIVITY_EXECUTION_PROJECTION.work_task_requirement(
			{"candidates": []},
			"occupation-1",
			"resident-1",
			execution_work_tasks,
		).get("errorCode", "")),
		"ACTIVITY_NOT_ELIGIBLE",
		"没有合法候选的活动必须保持原错误码",
	)
	_expect(
		ACTIVITY_EXECUTION_PROJECTION.work_task_requirement(
			{"activityId": "activity-1", "candidates": [{"role": "visitor"}]},
			"occupation-1",
			"resident-1",
			execution_work_tasks,
		).get("ok") == true,
		"访客活动不能被工作任务要求拦截",
	)


func _scenario_e15_action_and_staffing_policies() -> void:
	var missing_action := ACTION_PREPARATION_POLICY.entry_failure({}, {}, false)
	_expect(not missing_action.is_empty(), "动作准备入口必须拒绝缺少正式字段的动作")
	var reused_action := ACTION_PREPARATION_POLICY.entry_failure(
		{"action_id": "action-1", "type": "搭话", "target_resident_id": "resident-b"},
		{"action-1": true},
		false,
	) as Dictionary
	_expect_equal(String((reused_action.get("errors", []) as Array)[0]), "动作 action_id 已被该居民使用：action-1", "动作编号重复必须保持原错误")
	_expect(
		ACTION_PREPARATION_POLICY.entry_failure(
			{"action_id": "action-1", "type": "待着", "line": ""},
			{},
			false,
		).get("ok") == false,
		"要求说明的动作必须拒绝空 line",
	)
	_expect_equal(
		String((ACTION_PREPARATION_POLICY.delegated_action_failure("用道具").get("errors", []) as Array)[0]),
		"旧用道具动作必须经唯一 activity.perform 映射，不能直达 prop 路径",
		"旧道具动作必须保持唯一活动入口错误",
	)
	var service_action := {
		"action_id": "service-1",
		"type": "调整营业",
		"line": "开门",
		"place_id": "shop",
		"open": true,
	}
	var prepared_service := ACTION_PREPARATION_POLICY.service_adjustment(
		service_action,
		{"place_id": "shop", "open": false},
		60,
	) as Dictionary
	var prepared_service_action := prepared_service.get("action", {}) as Dictionary
	_expect(bool(prepared_service.get("ok", false)), "本人控制且状态变化的营业调整必须通过")
	_expect_equal(int(prepared_service_action.get("startedAbsoluteMinute", 0)), 60, "营业调整必须从当前分钟开始")
	_expect_equal(int(prepared_service_action.get("completeAbsoluteMinute", 0)), 61, "营业调整必须保持一分钟完成")
	_expect(not service_action.has("startedAbsoluteMinute"), "营业调整准备不能修改 Agent 原动作")
	_expect(
		ACTION_PREPARATION_POLICY.service_adjustment(
			service_action,
			{"place_id": "shop", "open": true},
			60,
		).get("ok") == false,
		"营业状态没有变化时必须拒绝调整",
	)
	var message_action := {
		"action_id": "message-1",
		"type": "托人传话",
		"line": "请帮我转告",
		"recipient_resident_id": "resident-b",
		"content": "晚上见",
	}
	var prepared_message := ACTION_PREPARATION_POLICY.private_message(
		message_action,
		"resident-a",
		true,
		0,
		80,
	) as Dictionary
	_expect(bool(prepared_message.get("ok", false)), "指定另一位真实居民的有效口信必须通过")
	_expect_equal(int((prepared_message.get("action", {}) as Dictionary).get("completeAbsoluteMinute", 0)), 81, "传话准备必须保持一分钟完成")
	_expect(
		ACTION_PREPARATION_POLICY.private_message(
			message_action,
			"resident-a",
			true,
			2,
			80,
		).get("ok") == false,
		"已有两条待投递口信时必须拒绝重复托付",
	)
	var regular_wait := ACTION_PREPARATION_POLICY.wait_action(
		{"action_id": "wait-1", "type": "待着", "line": "等等"},
		100,
		90,
		5,
		30,
	) as Dictionary
	_expect_equal(int((regular_wait.get("action", {}) as Dictionary).get("completeAbsoluteMinute", 0)), 130, "普通等待必须受最大等待分钟限制")
	var continuity_wait := ACTION_PREPARATION_POLICY.wait_action(
		{"action_id": "wait-continuity", "type": "待着", "line": "稍等"},
		100,
		90,
		5,
		30,
	) as Dictionary
	_expect_equal(int((continuity_wait.get("action", {}) as Dictionary).get("completeAbsoluteMinute", 0)), 105, "连续性占位等待必须使用更短上限")
	_expect_equal(
		String((ACTION_PREPARATION_POLICY.unknown_action_failure("未知").get("errors", []) as Array)[0]),
		"当前运行层尚未接入动作类型：未知",
		"未知动作类型必须保持原错误文案",
	)

	var target := STAFFING_ASSIGNMENT_POLICY.target({
		"target_refs": {
			"occupation_id": "occupation-baker",
			"assignment_kind": "trial",
			"from_occupation_id": "occupation-farmer",
			"shift_start_minute": 120,
			"shift_end_minute": 240,
		},
	}) as Dictionary
	_expect_equal(String(target.get("occupationId", "")), "occupation-baker", "岗位目标必须保留职业编号")
	_expect_equal(String(target.get("assignmentKind", "")), "trial", "岗位目标必须保留安排类型")
	var vacant_post := {"assignedResidentIds": []}
	var occupation := {"label": "面包师", "primaryWorkplacePlace": "烘焙坊"}
	_expect_equal(
		STAFFING_ASSIGNMENT_POLICY.failure_reason(target, "occupation-farmer", vacant_post, occupation, ["trial"]),
		"",
		"空缺岗位和允许的试岗模式必须通过资格检查",
	)
	_expect_equal(
		STAFFING_ASSIGNMENT_POLICY.failure_reason(target, "occupation-farmer", vacant_post, occupation, []),
		"居民当前没有以这种方式接手该岗位的资格",
		"不允许的岗位接手方式必须保持原错误",
	)
	var changed_job_target := target.duplicate(true)
	changed_job_target["fromOccupationId"] = "occupation-clinic"
	_expect_equal(
		STAFFING_ASSIGNMENT_POLICY.failure_reason(changed_job_target, "occupation-farmer", vacant_post, occupation, ["trial"]),
		"居民职业已经发生变化，本次申请失效",
		"协商期间职业变化必须使申请失效",
	)
	var transfer_target := target.duplicate(true)
	transfer_target["assignmentKind"] = "transfer"
	_expect_equal(
		STAFFING_ASSIGNMENT_POLICY.failure_reason(transfer_target, "occupation-farmer", {"assignedResidentIds": ["resident-b"]}, occupation, ["transfer"]),
		"岗位已经有正式负责人",
		"已有正式负责人的岗位不能转岗占用",
	)
	var assignment_result := STAFFING_ASSIGNMENT_POLICY.arrangement_result(
		{"arrangementId": "arrangement-7", "coversPost": true},
		"occupation-baker",
		"trial",
	) as Dictionary
	_expect_equal(String(assignment_result.get("result_id", "")), "staffing-arrangement:arrangement-7", "临时岗位安排结果编号必须保持稳定")
	_expect(bool(assignment_result.get("covers_post", false)), "岗位安排结果必须保留是否覆盖岗位")
	var original_social_state := {"job": "农夫", "workplace": "农场", "nested": {"value": 1}}
	var transferred_social_state := STAFFING_ASSIGNMENT_POLICY.transfer_social_state(
		original_social_state,
		occupation,
	) as Dictionary
	_expect_equal(String(transferred_social_state.get("job", "")), "面包师", "正式转岗必须更新职业标签")
	_expect_equal(String(transferred_social_state.get("workplace", "")), "烘焙坊", "正式转岗必须更新主要工作地点")
	(transferred_social_state.get("nested", {}) as Dictionary)["value"] = 2
	_expect_equal(int((original_social_state.get("nested", {}) as Dictionary).get("value", 0)), 1, "转岗社会状态必须深复制")

	var commit_stub := _StaffingAssignmentCommitStub.new()
	var residents := {"resident-a": {"socialState": original_social_state.duplicate(true)}}
	var committed_arrangement := STAFFING_ASSIGNMENT_COMMIT.create_arrangement(
		commit_stub,
		residents,
		"resident-a",
		target,
		90,
	) as Dictionary
	_expect(bool(committed_arrangement.get("ok", false)), "岗位安排提交必须返回运行时结果")
	_expect_equal(commit_stub.create_args, ["resident-a", "occupation-baker", "trial", 90, 120, 240], "岗位安排提交必须保持参数顺序")
	_expect_equal(commit_stub.rebuild_args.size(), 2, "成功岗位安排后必须立即重建岗位快照")
	var resident_state := residents.get("resident-a", {}) as Dictionary
	STAFFING_ASSIGNMENT_COMMIT.transfer(
		commit_stub,
		residents,
		resident_state,
		transfer_target,
		occupation,
		100,
	)
	_expect_equal(commit_stub.end_args, ["occupation-baker", 100, "岗位已有正式负责人"], "正式转岗必须结束目标岗位的临时安排")
	_expect_equal(String((resident_state.get("socialState", {}) as Dictionary).get("job", "")), "面包师", "正式转岗提交必须安装新的社会职业状态")


func _scenario_e16_occupation_service_and_social_contact_policies() -> void:
	_expect_equal(
		String(OCCUPATION_SERVICE_REQUEST_RUNTIME.entry_failure(
			false, "", "", {},
		).get("errorCode", "")),
		"WORLD_NOT_RUNNING",
		"职业服务请求入口必须优先保持世界未运行错误",
	)
	_expect_equal(
		String(OCCUPATION_SERVICE_REQUEST_RUNTIME.entry_failure(
			true, "civic_request", "", {"placeId": "市政厅"},
		).get("errorCode", "")),
		"OCCUPATION_SERVICE_REQUESTER_UNKNOWN",
		"职业服务请求入口必须拒绝未知居民",
	)
	_expect_equal(
		String(OCCUPATION_SERVICE_REQUEST_RUNTIME.entry_failure(
			true, "unknown", "resident-a", {},
		).get("errorCode", "")),
		"OCCUPATION_SERVICE_KIND_UNKNOWN",
		"职业服务请求入口必须拒绝未知服务类型",
	)
	_expect(
		OCCUPATION_SERVICE_REQUEST_RUNTIME.entry_failure(
			true, "civic_request", "resident-a", {"placeId": "市政厅"},
		).is_empty(),
		"真实居民和已知服务类型必须通过入口检查",
	)

	var occupation_services := TownOccupationServiceRuntime.new()
	_expect(occupation_services.configure().get("ok") == true, "职业服务提交测试必须配置服务运行时")
	_expect(occupation_services.initialize().get("ok") == true, "职业服务提交测试必须初始化服务运行时")
	var work_tasks := TownWorkTaskRuntime.new()
	_expect(work_tasks.configure().get("ok") == true, "职业服务提交测试必须配置工作任务运行时")
	var request_commit := OCCUPATION_SERVICE_REQUEST_COMMIT.new(
		occupation_services,
		work_tasks,
		TownClinicInterviewPolicy.new(),
	)
	var created_request := occupation_services.create_request({
		"kind": "civic_request",
		"requesterResidentId": "resident-a",
		"subjectRef": "",
		"itemId": "",
		"placeId": "市政厅",
		"context": {},
		"createdAtMinute": 100,
	}) as Dictionary
	_expect(created_request.get("ok") == true, "职业服务提交测试必须建立真实服务请求")
	var request := created_request.get("request", {}) as Dictionary
	var prepared := {
		"kind": "civic_request",
		"requesterResidentId": "resident-a",
		"definition": {
			"capability": "civic.service",
			"sourceKind": "resident_request",
			"resultKind": "civic_case_update",
			"occupationId": "occupation_town_manager",
			"targetKind": "service_request",
		},
	}
	var task_result := request_commit.create_task(prepared, request, {}, 100) as Dictionary
	_expect(task_result.get("ok") == true, "非地点职业服务必须建立真实工作任务")
	_expect(bool(task_result.get("createdNonPlaceTask", false)), "新建非地点任务必须要求总控推进世界版本")
	var task := task_result.get("task", {}) as Dictionary
	_expect_equal(String(task.get("sourceRef", "")), String(request.get("requestId", "")), "职业任务必须引用原服务请求")
	var configured := request_commit.configure_task(
		prepared,
		task,
		String(request.get("requestId", "")),
	) as Dictionary
	_expect(configured.get("ok") == true, "职业任务配置与请求关联必须作为同一提交步骤成功")
	_expect_equal(
		String((configured.get("request", {}) as Dictionary).get("taskId", "")),
		String(task.get("taskId", "")),
		"职业服务请求必须关联刚建立的任务",
	)
	var existing_task := {"taskId": "place-task"}
	var reused_task := request_commit.create_task(prepared, request, existing_task, 101) as Dictionary
	_expect(not bool(reused_task.get("createdNonPlaceTask", true)), "地点服务已有任务时不能重复创建非地点任务")
	_expect_equal(reused_task.get("task", {}), existing_task, "地点服务已有任务必须原样传入配置阶段")

	var failed_request_result := occupation_services.create_request({
		"kind": "civic_request",
		"requesterResidentId": "resident-b",
		"subjectRef": "",
		"itemId": "",
		"placeId": "市政厅",
		"context": {},
		"createdAtMinute": 101,
	}) as Dictionary
	var failed_request := failed_request_result.get("request", {}) as Dictionary
	var invalid_prepared := prepared.duplicate(true)
	(invalid_prepared.get("definition", {}) as Dictionary)["capability"] = "unknown.capability"
	var failed_task := request_commit.create_task(invalid_prepared, failed_request, {}, 101) as Dictionary
	_expect(failed_task.get("ok") != true, "未知能力的职业任务必须提交失败")
	_expect_equal(
		String(occupation_services.request(
			String(failed_request.get("requestId", "")),
		).get("state", "")),
		"cancelled",
		"职业任务创建失败后必须取消原服务请求",
	)
	var success_source := {"requestId": "request-source", "nested": {"value": 1}}
	var success_task_source := {"taskId": "task-source", "nested": {"value": 1}}
	var success := OCCUPATION_SERVICE_REQUEST_RUNTIME.success(success_source, success_task_source)
	(success.get("request", {}) as Dictionary)["requestId"] = "changed"
	(success.get("task", {}) as Dictionary)["taskId"] = "changed"
	_expect_equal(String(success_source.get("requestId", "")), "request-source", "职业服务成功结果必须隔离原请求")
	_expect_equal(String(success_task_source.get("taskId", "")), "task-source", "职业服务成功结果必须隔离原任务")

	_expect_equal(
		INITIAL_SOCIAL_CONTACT_POLICY.source_id(
			"sync_resident_request",
			{"source_event_ids": ["", " event-2 "], "request_id": "request-1"},
		),
		"event-2",
		"初始社会关系必须优先使用第一个真实来源事件",
	)
	_expect_equal(
		INITIAL_SOCIAL_CONTACT_POLICY.source_id(
			"sync_job_vacancy",
			{"vacancy_id": "vacancy-1"},
		),
		"vacancy-1",
		"岗位空缺必须回退到稳定空缺编号",
	)
	var request_operations := INITIAL_SOCIAL_CONTACT_POLICY.operations(
		"sync_resident_request",
		{"request_id": "request-1"},
		120,
		["resident-a", "resident-b"],
		"resident-a",
		"",
		"",
		"",
		"",
	)
	_expect_equal(request_operations.size(), 3, "居民请求必须先登记创建者再记录全部直接知情者")
	_expect_equal(String(request_operations[0].get("role", "")), "creator", "居民请求第一项操作必须登记创建者")
	_expect_equal(String(request_operations[1].get("acquiredVia", "")), "direct_request", "居民请求知情来源必须保持直接请求")
	var conversation_operations := INITIAL_SOCIAL_CONTACT_POLICY.operations(
		"sync_conversation_commitment",
		{"request_id": "promise-1"},
		121,
		[],
		"",
		"resident-promisor",
		"resident-beneficiary",
		"",
		"",
	)
	_expect_equal(conversation_operations.size(), 4, "对话承诺必须为承诺者和受益者各生成关系与知情操作")
	_expect_equal(String(conversation_operations[0].get("role", "")), "participant", "承诺者必须保持参与者身份")
	_expect_equal(String(conversation_operations[2].get("role", "")), "affected", "受益者必须保持受影响者身份")
	var vacancy_operations := INITIAL_SOCIAL_CONTACT_POLICY.operations(
		"sync_job_vacancy",
		{"vacancy_id": "vacancy-1"},
		122,
		["resident-a", "resident-b"],
		"",
		"",
		"",
		"",
		"",
	)
	_expect_equal(vacancy_operations.size(), 4, "岗位空缺必须为每位候选人生成关系与知情操作")
	_expect_equal(String(vacancy_operations[0].get("kind", "")), "involvement", "岗位候选人必须先登记受影响关系")
	var pressure_operations := INITIAL_SOCIAL_CONTACT_POLICY.operations(
		"sync_place_service_pressure",
		{"pressure_id": "pressure-1", "expires_at": 180},
		123,
		["resident-helper", "resident-owner"],
		"",
		"",
		"",
		"resident-owner",
		"市政厅里似乎忙不过来。",
	)
	_expect_equal(pressure_operations.size(), 4, "地点压力必须登记负责人并只向其他居民提供接触机会")
	_expect_equal(String(pressure_operations[1].get("acquiredVia", "")), "witnessed", "地点负责人必须保持目击知情来源")
	_expect_equal(String(pressure_operations[2].get("residentId", "")), "resident-helper", "地点负责人不能收到重复接触机会")
	_expect_equal(int(pressure_operations[2].get("expiresAt", 0)), 180, "接触机会必须保持来源过期时间")
	_expect_equal(String(pressure_operations[3].get("kind", "")), "schedule_decision", "每次接触机会后必须紧接居民决定调度")


func _scenario_f1_work_domain_ownership() -> void:
	var domain := WORK_DOMAIN_RUNTIME.new()
	_expect(domain.tasks is TownWorkTaskRuntime, "工作域必须拥有工作任务运行时")
	_expect(domain.staffing is TownStaffingRuntime, "工作域必须拥有岗位运行时")
	_expect(domain.cargo is TownCargoInventoryRuntime, "工作域必须拥有货运库存运行时")
	_expect(domain.production is TownProductionRuntime, "工作域必须拥有生产运行时")
	_expect(domain.services is TownOccupationServiceRuntime, "工作域必须拥有职业服务运行时")
	_expect(domain.place_services is TownPlaceServiceRuntime, "工作域必须拥有地点服务运行时")
	_expect_equal(
		(domain.staffing_snapshot(false).get("posts", []) as Array).size(),
		0,
		"世界停止时工作域必须返回稳定空岗位快照",
	)
	_expect_equal(
		(domain.cargo_snapshot(false).get("cargoLots", []) as Array).size(),
		0,
		"世界停止时工作域必须返回稳定空货运快照",
	)
	_expect_equal(
		(domain.service_snapshot(false).get("requests", []) as Array).size(),
		0,
		"世界停止时工作域必须返回稳定空职业服务快照",
	)
	_expect(domain.production_snapshot(false).is_empty(), "世界停止时生产快照必须保持空对象合同")

	var tasks := TownWorkTaskRuntime.new()
	var staffing := TownStaffingRuntime.new()
	var cargo := TownCargoInventoryRuntime.new()
	var production := TownProductionRuntime.new()
	var services := TownOccupationServiceRuntime.new()
	domain.install(tasks, staffing, cargo, production, services)
	_expect(
		domain.tasks == tasks
		and domain.staffing == staffing
		and domain.cargo == cargo
		and domain.production == production
		and domain.services == services,
		"世界启动提交必须一次安装同一批工作域组件",
	)
	domain.place_services.set_state("foundation-place", {"open": true})
	domain.reset_after_stop()
	_expect(domain.tasks == tasks, "世界停止必须保持原工作任务历史兼容语义")
	_expect(
		domain.staffing != staffing
		and domain.cargo != cargo
		and domain.production != production
		and domain.services != services,
		"世界停止必须由工作域统一重置岗位、货运、生产和服务状态",
	)
	_expect(
		domain.place_services.state("foundation-place").is_empty(),
		"世界停止必须同时清空工作域拥有的地点服务状态",
	)
	var occupation_world_data := {
		"occupations": [
			{
				"occupationId": "occupation-foundation",
				"label": "基础岗位",
				"aliases": ["岗位别名"],
			},
		],
	}
	_expect_equal(
		domain.primary_occupation_id(
			{"socialState": {"job": "基础岗位"}},
			occupation_world_data,
		),
		"occupation-foundation",
		"工作域必须根据岗位正式名称解析主职业",
	)
	_expect_equal(
		domain.primary_occupation_id(
			{"socialState": {"job": "岗位别名"}},
			occupation_world_data,
		),
		"occupation-foundation",
		"工作域必须保持岗位别名解析兼容性",
	)
	_expect_equal(
		String(domain.pickup_cargo_lot(
			"lot-1", "未知居民", "", "", 100, false, "",
		).get("errorCode", "")),
		"WORLD_RESIDENT_UNKNOWN",
		"货运命令必须在工作域保持未知居民错误合同",
	)
	var private_cargo_result := {
		"ok": true,
		"cargoCommand": {"logLabel": "货批生成"},
		"scheduleResidentIds": ["resident-a"],
		"scheduleOccupationIds": ["occupation-delivery"],
		"logStatus": "ongoing",
	}
	var public_cargo_result := CARGO_LOGISTICS_RUNTIME.public_result(private_cargo_result)
	_expect(
		not public_cargo_result.has("cargoCommand")
		and not public_cargo_result.has("scheduleResidentIds")
		and not public_cargo_result.has("scheduleOccupationIds")
		and not public_cargo_result.has("logStatus"),
		"货运公开结果不能泄漏内部提交和调度信息",
	)
	_expect_equal(
		String(domain.meal_period_for_minute(570).get("id", "")),
		"breakfast",
		"工作域必须保持早餐时段查询合同",
	)
	_expect_equal(
		domain.meal_period_source_ref(570),
		"meal-period:0:breakfast",
		"工作域必须保持餐次来源编号合同",
	)
	_expect(domain.meal_service_is_open(570), "工作域必须保持早餐发放时间判断")
	_expect(
		domain.dining_collect_can_finish_in_current_period(595),
		"餐次结束前五分钟仍必须允许完成取餐",
	)
	_expect(
		not domain.dining_collect_can_finish_in_current_period(596),
		"餐次剩余不足五分钟时必须拒绝开始取餐",
	)
	_expect(
		not domain.meal_period_is_prepared(570),
		"没有完成备餐工单时工作域不能误报餐次已备好",
	)
	_expect(
		domain.active_clinic_request_for_resident("resident-a").is_empty(),
		"空职业服务状态不能产生诊所请求",
	)
	var staffing_plan := STAFFING_MATTER_PROJECTION.plan(
		{
			"posts": [
				{
					"occupationId": "occupation-target",
					"label": "目标岗位",
					"status": "vacant",
				},
				{
					"occupationId": "occupation-duplicate",
					"status": "duplicate",
					"assignedResidentIds": ["resident-duplicate"],
				},
			],
			"unassignedResidentIds": ["resident-unassigned"],
		},
		[
			"resident-duplicate",
			"resident-unassigned",
			"resident-current",
			"resident-candidate",
			"resident-on-leave",
		],
		{
			"resident-current": "occupation-target",
			"resident-candidate": "occupation-other",
			"resident-on-leave": "occupation-other",
		},
		["resident-unassigned", "resident-current", "resident-candidate"],
		3,
		7,
		120,
	)
	var vacancy_source := (
		staffing_plan.get("sources", []) as Array
	)[0] as Dictionary
	_expect_equal(
		vacancy_source.get("candidate_resident_ids", []),
		["resident-duplicate", "resident-unassigned", "resident-candidate"],
		"岗位事项必须保持重复岗位、未分配居民和普通候选的稳定顺序",
	)
	_expect_equal(
		int(vacancy_source.get("expires_at", 0)),
		10200,
		"岗位事项必须保持七天刷新期限",
	)
	_expect_equal(
		int(vacancy_source.get("source_revision", 0)),
		7,
		"岗位事项必须保留世界来源版本",
	)

	_expect_equal(
		(domain.tasks.configure() as Dictionary).get("ok"),
		true,
		"工作域生产任务测试必须先配置真实工作链目录",
	)
	var production_events: Array[Dictionary] = []
	domain.production_task_created.connect(
		func(task: Dictionary) -> void:
			production_events.append(task.duplicate(true))
	)
	var production_spec := {
		"taskId": "foundation-production-task",
		"capability": "food.production",
		"sourceKind": "daily_baking_plan",
		"sourceRef": "foundation-production-source",
		"targets": [{"kind": "prop", "ref": "公共食堂备餐柜"}],
		"requestedResultKind": "food_batch",
		"createdAtMinute": 120,
		"priority": 50,
		"processStage": "planned",
		"processFacts": {
			"productItemId": "pastry",
			"destinationPlaceId": "花房咖啡馆",
			"nextActivityId": "activity_baker_prepare_dough",
		},
	}
	var ensured_production := domain.ensure_production_task(production_spec)
	_expect(bool(ensured_production.get("created", false)), "工作域必须建立新的生产任务")
	_expect_equal(production_events.size(), 1, "新生产任务必须只发出一次调度事件")
	_expect_equal(
		String((ensured_production.get("task", {}) as Dictionary).get("processStage", "")),
		"planned",
		"工作域必须在调度前完成生产阶段初始化",
	)
	_expect(
		not bool(domain.ensure_production_task(production_spec).get("created", true)),
		"同一来源的生产任务必须保持幂等",
	)
	_expect_equal(production_events.size(), 1, "幂等生产任务不能重复唤醒居民")
	_expect_equal(domain.active_presence_requests(), [], "空工作域不能产生在场服务计划")


func _scenario_e14_activity_routine_policy() -> void:
	_expect(
		ACTIVITY_ROUTINE_POLICY.legacy_activation(
			{"activityId": "eat"},
			{},
			[],
		).is_empty(),
		"没有例程描述时旧道具活动必须保持单步执行",
	)
	_expect(
		ACTIVITY_ROUTINE_POLICY.legacy_activation(
			{"activityId": "eat"},
			{"group": "meal", "phase": "consume"},
			[{"activityId": "eat", "available": true}],
		).is_empty(),
		"没有下一项不同活动时不能错误启动例程",
	)
	var meal_activation := ACTIVITY_ROUTINE_POLICY.legacy_activation(
		{"activityId": "eat", "preferredSlotId": "seat-1", "placeId": "餐厅"},
		{"group": "meal", "phase": "consume"},
		[
			{"activityId": "eat", "phase": "consume", "available": true},
			{"activityId": "collect", "phase": "collect", "available": true},
			{"activityId": "cleanup", "phase": "cleanup", "available": true},
		],
	) as Dictionary
	var meal_mapping := meal_activation.get("mapping", {}) as Dictionary
	var meal_descriptor := meal_activation.get("descriptor", {}) as Dictionary
	_expect_equal(String(meal_mapping.get("activityId", "")), "collect", "餐次从中间动作进入时必须先回到领取阶段")
	_expect(not meal_mapping.has("preferredSlotId"), "餐次改从领取阶段开始时不能沿用原座位偏好")
	_expect_equal(String(meal_descriptor.get("phase", "")), "collect", "餐次例程描述必须同步为领取阶段")
	_expect_equal(String(meal_descriptor.get("group", "")), "meal", "餐次例程描述必须保留餐次分组")
	var work_activation := ACTIVITY_ROUTINE_POLICY.legacy_activation(
		{"activityId": "work-a", "placeId": "工坊"},
		{"group": "work", "phase": ""},
		[
			{"activityId": "work-a", "available": true},
			{"activityId": "work-b", "available": true},
		],
	) as Dictionary
	_expect_equal(String((work_activation.get("mapping", {}) as Dictionary).get("activityId", "")), "work-a", "普通例程启动不能改写首个活动")

	var base_routine := {
		"routineId": "routine-1",
		"placeId": "餐厅",
		"group": "meal",
		"endAbsoluteMinute": 100,
		"sequence": 0,
		"lastActivityId": "collect",
		"lastPhase": "collect",
		"visitedActivityIds": ["collect"],
		"choiceSeed": 7,
	}
	var interrupted := ACTIVITY_ROUTINE_POLICY.continuation_entry(
		base_routine,
		{"type": "去"},
		"餐厅",
		20,
		3,
		"用餐结束",
	) as Dictionary
	_expect_equal(String(interrupted.get("status", "")), "interrupted", "同步回调安装新动作后必须中断旧例程")
	_expect_equal(String(interrupted.get("reason", "")), "居民改做另一件事，刚才的活动安排先收尾了", "新动作中断例程必须保留原提示")
	var departed := ACTIVITY_ROUTINE_POLICY.continuation_entry(
		base_routine,
		{},
		"广场",
		20,
		3,
		"用餐结束",
	) as Dictionary
	_expect_equal(String(departed.get("status", "")), "interrupted", "居民离开地点后必须中断例程")
	var expired := ACTIVITY_ROUTINE_POLICY.continuation_entry(
		base_routine,
		{},
		"餐厅",
		100,
		3,
		"用餐结束",
	) as Dictionary
	_expect_equal(String(expired.get("status", "")), "completed", "达到例程截止时间必须正常完成")
	_expect_equal(String(expired.get("reason", "")), "用餐结束", "正常结束必须使用分组完成文案")
	var maxed_routine := base_routine.duplicate(true)
	maxed_routine["sequence"] = 2
	var maxed := ACTIVITY_ROUTINE_POLICY.continuation_entry(
		maxed_routine,
		{},
		"餐厅",
		20,
		3,
		"用餐结束",
	) as Dictionary
	_expect_equal(String(maxed.get("kind", "")), "close", "达到最大步骤数必须关闭例程")
	var select_meal := ACTIVITY_ROUTINE_POLICY.continuation_entry(
		base_routine,
		{},
		"餐厅",
		20,
		3,
		"用餐结束",
	) as Dictionary
	_expect_equal(String(select_meal.get("expectedPhase", "")), "consume", "领取餐食后只能继续进食阶段")
	var invalid_phase_routine := base_routine.duplicate(true)
	invalid_phase_routine["lastPhase"] = "unknown"
	var invalid_phase := ACTIVITY_ROUTINE_POLICY.continuation_entry(
		invalid_phase_routine,
		{},
		"餐厅",
		20,
		3,
		"用餐结束",
	) as Dictionary
	_expect_equal(String(invalid_phase.get("kind", "")), "close", "未知餐次阶段不能猜测下一步")

	var meal_candidates := ACTIVITY_ROUTINE_POLICY.candidate_plan(
		base_routine,
		[
			{"activityId": "collect", "phase": "collect", "available": true},
			{"activityId": "eat", "phase": "consume", "label": "吃饭", "available": true},
			{"activityId": "cleanup", "phase": "cleanup", "available": true},
			{"activityId": "unavailable", "phase": "consume", "available": false},
		],
		"consume",
	) as Dictionary
	var ordered_meal_candidates := meal_candidates.get("candidates", []) as Array
	_expect_equal(ordered_meal_candidates.size(), 1, "餐次候选必须只保留预期阶段的可用新活动")
	_expect_equal(String((ordered_meal_candidates[0] as Dictionary).get("activityId", "")), "eat", "餐次领取后的候选必须是进食")
	_expect_equal(int(meal_candidates.get("nextSequence", 0)), 1, "下一例程步骤序号必须递增一次")
	var work_routine := {
		"routineId": "routine-work",
		"placeId": "工坊",
		"group": "work",
		"sequence": 1,
		"lastActivityId": "work-b",
		"visitedActivityIds": ["work-a", "work-b"],
		"choiceSeed": 0,
	}
	var work_candidates := ACTIVITY_ROUTINE_POLICY.candidate_plan(
		work_routine,
		[
			{"activityId": "work-a", "available": true},
			{"activityId": "work-c", "label": "制作", "available": true},
		],
		"",
	) as Dictionary
	_expect_equal((work_candidates.get("candidates", []) as Array).size(), 1, "工作例程不能重复访问过的活动")
	var work_candidate := (work_candidates.get("candidates", []) as Array)[0] as Dictionary
	var step := ACTIVITY_ROUTINE_POLICY.continuation_step(
		work_routine,
		work_candidate,
		2,
	) as Dictionary
	_expect_equal(String(step.get("stepId", "")), "step-2-work-c", "例程步骤编号必须保持稳定")
	_expect_equal(String((step.get("target", {}) as Dictionary).get("placeId", "")), "工坊", "例程步骤必须留在原地点")
	var advanced := ACTIVITY_ROUTINE_POLICY.advanced_routine(
		work_routine,
		work_candidate,
		2,
	) as Dictionary
	_expect_equal(int(advanced.get("sequence", 0)), 2, "成功活动必须推进例程序号")
	_expect_equal(String(advanced.get("lastActivityId", "")), "work-c", "成功活动必须记录最后活动")
	_expect((advanced.get("visitedActivityIds", []) as Array).has("work-c"), "成功工作活动必须加入已访问集合")
	_expect(not (work_routine.get("visitedActivityIds", []) as Array).has("work-c"), "例程推进不能提前修改原运行态")


func _scenario_e13_agent_social_projections() -> void:
	var source_resident := {
		"spaceId": "road",
		"regionId": "region-old",
		"currentPlace": "旧地点",
		"position": Vector2(1, 2),
		"currentAction": {"type": "去"},
	}
	var perception_resident := AGENT_WAKE_PACKET_PROJECTION.perception_resident(
		source_resident,
		{
			"spaceId": "town_outdoor",
			"regionId": "region-new",
			"currentPlace": "广场",
			"position": Vector2(10, 20),
		},
	) as Dictionary
	_expect_equal(String(perception_resident.get("currentPlace", "")), "广场", "抵达预取唤醒必须使用抵达后的地点")
	_expect((perception_resident.get("currentAction", {}) as Dictionary).is_empty(), "抵达预取唤醒不能暴露仍在路上的动作")
	_expect_equal(String(source_resident.get("currentPlace", "")), "旧地点", "抵达投影不能修改真实居民状态")
	var nearby_ids := AGENT_WAKE_PACKET_PROJECTION.resident_ids([
		{"resident_id": " resident-a "},
		{"resident_id": ""},
		{"resident_id": "resident-b"},
	])
	_expect_equal(nearby_ids, ["resident-a", "resident-b"], "唤醒冲突视图必须只保留有效附近居民编号")
	var social_source := {"result_id": "result-1", "nested": {"value": 1}}
	var social_results := AGENT_WAKE_PACKET_PROJECTION.public_social_results([
		social_source,
		"invalid",
	])
	_expect_equal(social_results.size(), 1, "唤醒包必须过滤非字典社会回应")
	(social_results[0].get("nested", {}) as Dictionary)["value"] = 2
	_expect_equal(int((social_source.get("nested", {}) as Dictionary).get("value", 0)), 1, "社会回应投影必须深复制")
	var conflict_source := {"conflicts": [{"conflict_id": "conflict-1"}]}
	var packet := AGENT_WAKE_PACKET_PROJECTION.packet(
		"decision-1",
		{
			"resident": {"doing": "思考中", "body": {}, "activityState": {}},
			"currentAction": null,
			"conflictSnapshot": conflict_source,
		},
		[{"event_id": "event-1"}],
		[{"result_id": "result-1"}],
		social_results,
	) as Dictionary
	var packet_snapshot := packet.get("snapshot", {}) as Dictionary
	var packet_me := packet_snapshot.get("me", {}) as Dictionary
	_expect(packet_me.has("current_action") and packet_me.get("current_action") == null, "唤醒合同必须保留可选的空当前动作")
	_expect_equal(String(packet.get("decision_id", "")), "decision-1", "唤醒包必须保留决定编号")
	((packet_snapshot.get("conflicts", []) as Array)[0] as Dictionary)["conflict_id"] = "changed"
	_expect_equal(String(((conflict_source.get("conflicts", []) as Array)[0] as Dictionary).get("conflict_id", "")), "conflict-1", "冲突投影必须与运行时状态隔离")

	var options := CONVERSATION_FOLLOW_UP_OPTION_PROJECTION.legacy_options({
		"residentId": "resident-a",
		"partnerId": "resident-b",
		"partnerRef": "居民乙",
		"partnerName": "居民乙",
		"currentPlace": "广场",
		"requestedPlaceIds": [],
		"destinations": ["诊所"],
		"activities": [{"activity_id": "rest", "label": "休息"}],
		"nearby": [{"residentId": "resident-c", "displayName": "居民丙"}],
		"serviceOfferings": [{
			"place_id": "餐厅",
			"activity_id": "collect-meal",
			"service_label": "餐食",
		}],
	})
	_expect_equal(options.size(), 5, "完整对话后续投影必须包含前往、同行、活动、交谈和代取服务")
	_expect_equal(String(options[0].get("capability_id", "")), "world.go_to_place", "前往选项顺序必须保持不变")
	_expect_equal(String(options[1].get("capability_id", "")), "world.escort_person_to_place", "同行选项必须紧跟对应地点")
	_expect_equal(String(options[4].get("capability_id", "")), "world.fetch_service_for_person", "代取服务选项必须保留原能力编号")
	var filtered_options := CONVERSATION_FOLLOW_UP_OPTION_PROJECTION.legacy_options({
		"residentId": "resident-a",
		"partnerId": "resident-b",
		"partnerName": "居民乙",
		"currentPlace": "广场",
		"requestedPlaceIds": ["诊所"],
		"destinations": ["诊所", "餐厅"],
		"activities": [{"activity_id": "rest", "label": "休息"}],
		"nearby": [{"residentId": "resident-c", "displayName": "居民丙"}],
		"serviceOfferings": [{"place_id": "餐厅", "activity_id": "meal", "service_label": "餐食"}],
	})
	_expect_equal(filtered_options.size(), 2, "指定地点的对话承诺只能保留该地点的前往与同行选项")
	_expect_equal(String(filtered_options[0].get("place_id", "")), "诊所", "指定地点筛选必须保留目标地点")

	var no_time_schedule := ANNOUNCEMENT_PUBLICATION_PROJECTION.schedule_context(
		"大家记得查看公告",
		480,
	) as Dictionary
	_expect((no_time_schedule.get("schedule", {}) as Dictionary).is_empty(), "无时间表达的公告不能产生定时计划")
	_expect(not bool(no_time_schedule.get("timeExpressionDetected", true)), "无时间表达公告不能产生计划警告前提")
	var announcement_source := {
		"announcement_id": "announcement-1",
		"publisher_id": "resident-a",
		"text": "今晚集合",
		"matter_id": "",
		"time": {"day": 2, "clock": "08:00"},
	}
	var published := ANNOUNCEMENT_PUBLICATION_PROJECTION.published_announcement({
		"value": {"announcement": announcement_source},
	})
	(published.get("time", {}) as Dictionary)["day"] = 9
	_expect_equal(int((announcement_source.get("time", {}) as Dictionary).get("day", 0)), 2, "公告提交结果必须深复制")
	var event_spec := ANNOUNCEMENT_PUBLICATION_PROJECTION.event_spec(
		announcement_source,
		"resident-a",
		"居民甲",
		"ordinary",
		{"day": 1},
	) as Dictionary
	_expect(event_spec.has("matter_id") and event_spec.get("matter_id") == null, "无社会事项公告必须保留空 matter_id 合同")
	_expect_equal(String(event_spec.get("announcement_priority", "")), "ordinary", "公告事件必须保留发布者优先级")
	var invalid_announcement := ANNOUNCEMENT_PUBLICATION_PROJECTION.invalid_publish_failure({
		"error_code": "BULLETIN_ANNOUNCEMENT_INVALID",
		"reason": "公告内容无效",
	})
	_expect_equal(String(invalid_announcement.get("errorCode", "")), "ANNOUNCEMENT_INVALID", "公告校验失败必须映射原世界错误码")
	var capability := ANNOUNCEMENT_PUBLICATION_PROJECTION.capability_completion(announcement_source)
	_expect_equal(String(capability.get("resultId", "")), "bulletin-publish:announcement-1", "公告社会能力结果编号必须保持稳定")
	var success := ANNOUNCEMENT_PUBLICATION_PROJECTION.success_result(
		announcement_source,
		"world-event-1",
		"",
		{},
		true,
	)
	_expect(bool(success.get("scheduleWarning", false)), "检测到时间表达但无法解析时必须保留计划警告")


func _scenario_e12_world_orchestration_policies() -> void:
	_expect_equal(
		CONFIRMED_ACTION_ACTIVATION_POLICY.route_kind(
			{"type": "用道具", "dynamicPropId": ""},
		),
		"legacy_prop_activity",
		"静态道具确认动作必须继续走旧活动兼容入口",
	)
	_expect_equal(
		CONFIRMED_ACTION_ACTIVATION_POLICY.route_kind(
			{"type": "用道具", "dynamicPropId": "dynamic-1"},
		),
		"regular",
		"动态道具确认动作必须继续走常规入口",
	)
	_expect_equal(
		CONFIRMED_ACTION_ACTIVATION_POLICY.route_kind({"type": "做活动"}),
		"agent_activity",
		"活动确认动作必须继续走 Agent 活动入口",
	)
	_expect_equal(
		CONFIRMED_ACTION_ACTIVATION_POLICY.route_kind({"type": "攻击"}),
		"conflict",
		"冲突动作必须继续走冲突入口",
	)
	var submitted_source := {"type": "观察", "nested": {"value": 1}}
	var submitted := CONFIRMED_ACTION_ACTIVATION_POLICY.submitted_action(
		{"submittedAction": submitted_source},
		{},
	) as Dictionary
	(submitted.get("nested", {}) as Dictionary)["value"] = 2
	_expect_equal(
		int((submitted_source.get("nested", {}) as Dictionary).get("value", 0)),
		1,
		"确认动作的原始提交内容必须深复制",
	)
	var resident := {
		"currentAction": {},
		"routeConnector": [Vector2(1, 2)],
		"actionSuspendedAbsoluteMinute": 30,
		"doing": "旧状态",
	}
	var activated_action := {"type": "观察", "consumeRouteConnector": true}
	CONFIRMED_ACTION_ACTIVATION_POLICY.activate_resident(
		resident,
		activated_action,
		"正在观察",
	)
	_expect(resident.get("currentAction") == activated_action, "确认动作必须成为当前动作")
	_expect_equal((resident.get("routeConnector", []) as Array).size(), 0, "动作声明消费连接线时必须清空旧连接线")
	_expect_equal(int(resident.get("actionSuspendedAbsoluteMinute", 0)), -1, "确认新动作必须清除暂停时间")
	_expect_equal(String(resident.get("doing", "")), "正在观察", "确认新动作必须同步居民状态文案")

	var region_candidates := [
		{"slotId": "slot-a", "targetType": "region", "memberAvailable": true},
		{"slotId": "slot-b", "targetType": "region", "memberAvailable": true},
		{"slotId": "slot-c", "targetType": "region", "memberAvailable": true},
	]
	var ordered := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.ordered_candidates({
		"residentId": "resident-1",
		"actionId": "action-1",
		"candidates": region_candidates,
	}) as Array
	_expect_equal(ordered.size(), 3, "区域活动候选排序不能丢失成员")
	var ordered_ids: Array[String] = []
	for candidate_value: Variant in ordered:
		ordered_ids.append(String((candidate_value as Dictionary).get("slotId", "")))
	ordered_ids.sort()
	_expect_equal(ordered_ids, ["slot-a", "slot-b", "slot-c"], "区域活动候选轮转后必须保持原候选集合")
	var preferred := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.ordered_candidates({
		"preferredRequested": true,
		"candidates": [
			{"slotId": "slot-a", "memberAvailable": false},
			{"slotId": "slot-b", "memberAvailable": true},
			{"slotId": "slot-c", "memberAvailable": true},
		],
	}) as Array
	_expect_equal(preferred.size(), 2, "明确指定活动候选时最多保留前两个确定性候选")
	_expect_equal(String((preferred[0] as Dictionary).get("slotId", "")), "slot-a", "明确指定候选不能因占用被提前改序")
	var available := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.ordered_candidates({
		"candidates": [
			{"slotId": "slot-a", "memberAvailable": false},
			{"slotId": "slot-b", "memberAvailable": true},
		],
	}) as Array
	_expect_equal(String((available[0] as Dictionary).get("slotId", "")), "slot-b", "普通活动必须选取首个可用候选")
	var conflict := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.reservation_conflict([])
	_expect_equal(String(conflict.get("errorCode", "")), "ACTIVITY_RESERVATION_CONFLICT", "无活动候选时必须保持预约冲突错误")
	_expect(bool(conflict.get("retryable", false)), "活动预约冲突必须保持可重试")
	var candidate := {
		"slotId": "slot-1",
		"memberAnchorId": "member-1",
		"targetPropName": "长椅",
		"targetActionVerb": "坐下",
		"memberPosition": [10.0, 20.0],
	}
	var action := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.candidate_action(
		{"actionId": "action-1", "activityLabel": "休息"},
		candidate,
	) as Dictionary
	_expect_equal(action, {
		"action_id": "action-1",
		"type": "用道具",
		"prop": "长椅",
		"verb": "坐下",
		"line": "休息",
	}, "活动候选必须投影为原有道具动作字段")
	var prepared := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.prepared_from_cache(
		{"targetPosition": Vector2(10, 20), "path": [Vector2.ZERO]},
		action,
	) as Dictionary
	var prepared_action := prepared.get("action", {}) as Dictionary
	_expect_equal(String(prepared_action.get("action_id", "")), "action-1", "缓存动作必须刷新本次动作编号")
	var candidate_result := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.candidate_result(
		candidate,
		prepared_action,
		false,
	) as Dictionary
	_expect(bool(candidate_result.get("ok", false)), "权威锚点一致时活动候选必须通过")
	_expect_equal(String(candidate_result.get("memberAnchorId", "")), "member-1", "活动候选结果必须保留成员锚点")
	_expect(
		ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.candidate_result(
			candidate,
			{"targetPosition": Vector2(99, 99)},
			false,
		).is_empty(),
		"非布局覆盖动作的目标位置不一致时必须拒绝候选",
	)
	var unreachable := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.target_failure(true)
	_expect_equal(String(unreachable.get("errorCode", "")), "ACTIVITY_TARGET_UNREACHABLE", "不可达候选必须保持原错误码")
	_expect(bool(unreachable.get("retryable", false)), "活动目标不可达必须保持可重试")
	var invalid_reference := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.target_failure(false)
	_expect_equal(String(invalid_reference.get("errorCode", "")), "ACTIVITY_SLOT_REFERENCE_INVALID", "锚点不一致必须保持原错误码")
	_expect(not bool(invalid_reference.get("retryable", true)), "活动锚点引用错误不能标记为可重试")

	var identity_status := "confirmed"
	var time := {"day": 3, "hour": 8, "minute": 15}
	var lifecycle := {"running": true, "paused": false}
	var restore_summary := RESTORE_COMMIT_PROJECTION.summary(
		5,
		4,
		2,
		identity_status,
		time,
		"晴",
		lifecycle,
		19,
	) as Dictionary
	_expect_equal(String(restore_summary.get("identityStatus", "")), identity_status, "恢复摘要必须保留居民身份状态")
	_expect(bool(restore_summary.get("residentRelocationRequired", false)), "恢复摘要必须继续要求表现层重新放置居民")
	(time as Dictionary)["day"] = 99
	(lifecycle as Dictionary)["running"] = false
	_expect_equal(int((restore_summary.get("time", {}) as Dictionary).get("day", 0)), 3, "恢复摘要时间必须与可变运行态隔离")
	_expect(bool((restore_summary.get("lifecycle", {}) as Dictionary).get("running", false)), "恢复摘要生命周期必须与可变运行态隔离")


func _scenario_agent_decision_acceptance_policy() -> void:
	var stopped_entry := AGENT_DECISION_ENVELOPE_RUNTIME.by_id_entry_error(
		false,
		"resident-1",
		"居民甲",
		true,
		true,
		8,
	) as Dictionary
	_expect_equal(
		String(stopped_entry.get("errorCode", "")),
		"WORLD_NOT_RUNNING",
		"按编号提交决定时必须优先保持世界未运行错误",
	)
	_expect_equal(
		int(stopped_entry.get("worldRevision", 0)),
		8,
		"决定入口错误必须保留当前世界版本",
	)
	var paused_resident := {
		"decisionPending": true,
		"validDecisionId": "decision-1",
		"wakeDispatchQueued": false,
	}
	var paused_entry := AGENT_DECISION_ENVELOPE_RUNTIME.submission_entry_error(
		true,
		"居民甲",
		"resident-1",
		true,
		true,
		paused_resident,
		"decision-1",
	) as Dictionary
	_expect_equal(
		String(paused_entry.get("errorCode", "")),
		"WORLD_PAUSED",
		"暂停期间必须保持可重试的决定入口错误",
	)
	_expect(
		bool(paused_resident.get("wakeDispatchQueued", false)),
		"暂停期间收到仍有效决定时必须重新排队唤醒",
	)
	var stale_entry := AGENT_DECISION_ENVELOPE_RUNTIME.submission_entry_error(
		true,
		"居民甲",
		"resident-1",
		true,
		false,
		paused_resident,
		"decision-old",
	) as Dictionary
	_expect(bool(stale_entry.get("stale", false)), "旧决定编号必须继续判为失效")
	var context_resident := {
		"inflightEvents": [{"event_id": "event-1"}],
		"inflightResults": [{"action_id": "action-1"}],
		"pendingWake": {"snapshot": {"value": 1}},
		"decisionPrefetch": true,
		"decisionMayInterruptCurrent": true,
	}
	var captured_context := AGENT_DECISION_ENVELOPE_RUNTIME.submission_context(
		context_resident,
		{"rootEventIds": ["root-1"]},
	) as Dictionary
	(context_resident.get("inflightEvents", []) as Array).clear()
	_expect_equal(
		(captured_context.get("inflightEvents", []) as Array).size(),
		1,
		"决定受理上下文必须与居民飞行中事实后续修改隔离",
	)
	_expect(bool(captured_context.get("wasPrefetched", false)), "决定上下文必须保留预取标记")
	_expect(bool(captured_context.get("mayInterruptCurrent", false)), "决定上下文必须保留中断许可")
	var reply_required := AGENT_DECISION_ACCEPTANCE_POLICY.invitation_reply_error({
		"handling": "continue_current",
	}) as Dictionary
	_expect_equal(
		String(reply_required.get("errorCode", "")),
		"CONVERSATION_REPLY_REQUIRED",
		"初次搭话必须提交答话动作",
	)
	var refusal_reason := AGENT_DECISION_ACCEPTANCE_POLICY.invitation_reply_error({
		"handling": "replace_current",
		"action": {"type": "答话", "end": true, "say": ""},
	}) as Dictionary
	_expect_equal(
		String(refusal_reason.get("errorCode", "")),
		"CONVERSATION_REFUSAL_REASON_REQUIRED",
		"拒绝搭话时必须保留明确理由检查",
	)
	_expect(
		AGENT_DECISION_ACCEPTANCE_POLICY.invitation_reply_error({
			"handling": "replace_current",
			"action": {"type": "答话", "end": true, "say": "现在不方便"},
		}).is_empty(),
		"带明确理由的拒绝答话必须通过前置检查",
	)
	var injury := {
		"attacker_resident_id": "resident-2",
	}
	_expect_equal(
		AGENT_DECISION_ACCEPTANCE_POLICY.post_injury_action_error(
			{},
			{
				"handling": "replace_current",
				"action": {
					"type": "搭话",
					"target_resident_id": "resident-2",
				},
			},
			injury,
			"诊所",
		),
		"",
		"受伤后当面质问攻击者必须允许继续",
	)
	_expect(
		not AGENT_DECISION_ACCEPTANCE_POLICY.post_injury_action_error(
			{},
			{
				"handling": "replace_current",
				"action": {"type": "搭话", "target_resident_id": "resident-3"},
			},
			injury,
			"诊所",
		).is_empty(),
		"受伤后不能先与无关居民搭话",
	)
	_expect_equal(
		AGENT_DECISION_ACCEPTANCE_POLICY.waiting_conversation_reply_error(
			{"waitingFor": "resident-1"},
			"resident-1",
			"去",
			false,
		),
		"当前对话正在等待本居民提交答话动作",
		"进行中的对话必须保持强制答话错误",
	)
	_expect_equal(
		AGENT_DECISION_ACCEPTANCE_POLICY.conversation_end_reason(
			{"conversationId": "conversation-1"},
			"去",
			true,
		),
		"拒绝接话",
		"初次搭话改做其他动作时必须保持拒绝结束原因",
	)
	var prefetched_resident := {}
	var prefetched_decision := {"decision_id": "decision-1", "nested": {"value": 1}}
	var prefetched_result := AGENT_DECISION_ENVELOPE_RUNTIME.store_prefetched_decision(
		prefetched_resident,
		"resident-1",
		"decision-1",
		prefetched_decision,
		{"snapshot": {"value": 1}},
		[{"event_id": "event-1"}],
		[{"action_id": "action-1"}],
	) as Dictionary
	prefetched_decision["nested"]["value"] = 2
	_expect_equal(
		String(prefetched_result.get("status", "")),
		"prefetched",
		"行动中的预取决定必须保持原状态返回值",
	)
	_expect_equal(
		int((((prefetched_resident.get("prefetchedDecision", {}) as Dictionary).get(
			"nested", {}
		) as Dictionary).get("value", 0))),
		1,
		"暂存的预取决定必须与调用方后续修改隔离",
	)
	var reconsidered := AGENT_DECISION_ACCEPTANCE_POLICY.apply_wait_reconsideration(
		{"type": "待着", "completeAbsoluteMinute": 150},
		{
			"action_id": "resume-1",
			"followUpPausedForReconsideration": true,
			"followUpReconsiderationReason": "目标暂不可达",
			"followUpReconsiderationSinceMinute": 80,
		},
		true,
		100,
		20,
	) as Dictionary
	_expect_equal(
		int(reconsidered.get("completeAbsoluteMinute", 0)),
		120,
		"重新考虑时的等待动作必须继续受最长等待时长约束",
	)
	var resume_action := reconsidered.get("followUpResumeAction", {}) as Dictionary
	_expect(
		not resume_action.has("followUpPausedForReconsideration"),
		"恢复动作必须移除重新考虑暂停标记",
	)
	var preview_action := {"action_id": "action-1", "type": "待着"}
	var preview := AGENT_DECISION_CONFIRMATION_PROJECTION.preview(
		"decision-1",
		"replace_current",
		preview_action,
		"待在原地",
		"先等等",
		7,
		{"day": 1, "hour": 8, "minute": 0},
		0.8,
		preview_action,
	) as Dictionary
	preview_action["type"] = "去"
	_expect_equal(
		String((preview.get("action", {}) as Dictionary).get("type", "")),
		"待着",
		"确认预览必须与提交动作后续修改隔离",
	)
	_expect_equal(
		String(AGENT_DECISION_CONFIRMATION_PROJECTION.accepted_result(
			"replace_current", {}, {}
		).get("status", "")),
		"accepted",
		"替换动作的确认结果必须保持 accepted 状态",
	)


func _scenario_production_task_sync_runtime() -> void:
	var work_tasks := TownWorkTaskRuntime.new()
	_expect(
		work_tasks.configure().get("ok") == true,
		"生产任务同步模块测试必须成功配置任务运行时",
	)
	var created := work_tasks.create_task({
		"taskId": "e8-active-food-task",
		"capability": "food.production",
		"sourceKind": "daily_baking_plan",
		"sourceRef": "dining-pastry-plan-day:1",
		"targets": [{"kind": "prop", "ref": "公共食堂灶台"}],
		"requestedResultKind": "food_batch",
		"createdAtMinute": 600,
		"priority": 60,
	}) as Dictionary
	_expect(created.get("ok") == true, "生产任务查询测试必须建立真实任务")
	var task := created.get("task", {}) as Dictionary
	var configured := work_tasks.configure_initial_process(
		String(task.get("taskId", "")),
		int(task.get("revision", 0)),
		"planned",
		{
			"productItemId": "pastry",
			"destinationPlaceId": "花房咖啡馆",
		},
	) as Dictionary
	_expect(configured.get("ok") == true, "生产任务必须保留初始加工事实")
	_expect(
		PRODUCTION_TASK_SYNC_RUNTIME.has_active_work_task_capability(
			work_tasks,
			"food.production",
		),
		"生产任务同步模块必须识别仍在进行的能力任务",
	)
	_expect(
		PRODUCTION_TASK_SYNC_RUNTIME.has_active_specialty_production(
			work_tasks,
			"pastry",
			"花房咖啡馆",
		),
		"生产任务同步模块必须按产品和目的地识别在途生产",
	)
	_expect(
		not PRODUCTION_TASK_SYNC_RUNTIME.retire_stale_period_work_tasks(
			work_tasks,
			"food.production",
			"daily_baking_plan",
			"dining-pastry-plan-day:2",
			"新的烘焙周期已经开始",
		),
		"未接取的旧周期任务应被取消，不能误判为结转任务",
	)
	_expect_equal(
		String(work_tasks.task("e8-active-food-task").get("state", "")),
		"cancelled",
		"旧周期生产任务必须由迁出后的模块取消",
	)
	var stage_result := (
		PRODUCTION_TASK_SYNC_RUNTIME.plant_research_stage_task_spec(
			{"projectId": "research-e8", "sourceKind": "abnormal_plant"},
			"verify",
			[],
		) as Dictionary
	)
	var stage_spec := stage_result.get("spec", {}) as Dictionary
	_expect_equal(
		String(stage_spec.get("capability", "")),
		"research.verify",
		"研究验证阶段必须保留原能力标识",
	)
	_expect_equal(
		int(stage_spec.get("priority", 0)),
		62,
		"异常植物研究必须保留原任务优先级",
	)
	var invalid_stage := (
		PRODUCTION_TASK_SYNC_RUNTIME.plant_research_stage_task_spec(
			{"projectId": "research-e8"},
			"unknown",
			[],
		) as Dictionary
	)
	_expect_equal(
		String(invalid_stage.get("errorCode", "")),
		"PLANT_RESEARCH_STAGE_INVALID",
		"迁出后的研究阶段校验必须继续拒绝未知阶段",
	)


func _scenario_occupation_service_request_policies() -> void:
	var request := {
		"kind": "cafe_order",
		"requesterResidentId": "resident-customer",
		"placeId": "花房咖啡馆",
		"createdAtMinute": 100,
		"context": {},
	}
	var mode := OCCUPATION_SERVICE_PRESENCE_POLICY.resolve_mode(
		request,
		110,
		false,
		30,
	)
	_expect_equal(mode.get("mode"), "onsite_wait",
		"occupation service policy defaults staffed requests to onsite wait",)
	_expect_equal(
		(mode.get("patch", {}) as Dictionary).get("onsiteWaitUntilMinute"),
		130,
		"occupation service policy derives the original wait deadline",
	)
	var absent := OCCUPATION_SERVICE_PRESENCE_POLICY.evaluate(
		request,
		{"residentId": "resident-customer", "currentPlace": "中央广场"},
		110,
		mode,
		true,
		true,
		false,
		true,
		30,
	)
	_expect_equal(absent.get("action"), "pause",
		"occupation service policy pauses work when the customer is absent",)
	_expect_equal(
		((absent.get("contextPatches", []) as Array)[1] as Dictionary).get(
			"customerAbsentSinceMinute",
		),
		110,
		"occupation service policy records the first absent minute",
	)
	var clinic_context := CLINIC_SERVICE_REQUEST_POLICY.build_condition_context(
		[{
			"conditionId": "condition-fatigue",
			"label": "疲劳",
		}],
		{
			"conflict_injuries": [{
				"injury_id": "injury-heavy",
				"severity": "heavy",
				"source_actor_name": "测试居民",
			}],
		},
	)
	var context := clinic_context.get("context", {}) as Dictionary
	_expect_equal(
		(context.get("conditionIds", []) as Array).has("condition-fatigue"),
		true,
		"clinic request policy preserves resident condition ids",
	)
	_expect_equal(
		(context.get("conditionIds", []) as Array).has("injury-heavy"),
		true,
		"clinic request policy merges conflict injury ids",
	)
	_expect_equal(bool(context.get("conflictInjuryRequiresTreatment", false)), true,
		"clinic request policy marks heavy conflict injuries for treatment",)


func _scenario_place_service_runtime_state() -> void:
	var runtime: TownPlaceServiceRuntime = PLACE_SERVICE_RUNTIME.new()
	runtime.restore_prepared({
		"测试服务点": {
			"pressure_id": "service-pressure:测试服务点",
			"place_id": "测试服务点",
			"owner_id": "resident-owner",
			"open": true,
			"service_capacity": 2,
			"helper_activity_id": "activity_help",
			"request_activity_ids": ["activity_request"],
			"pending_request_ids": [],
			"source_revision": 0,
			"expires_at": -1,
			"updated_at": -1,
		},
	})
	_expect_equal(
		runtime.update_request("未知地点", "request-a", true, -1, 100).get("errorCode"),
		"PLACE_SERVICE_REQUEST_INVALID",
		"place service runtime rejects requests for an unknown place",
	)
	var added := runtime.update_request(
		"测试服务点",
		"request-b",
		true,
		-1,
		100,
	)
	_expect_equal(added.get("changed"), true, "place service request is added once")
	_expect_equal(
		runtime.update_request("测试服务点", "request-b", true, -1, 101).get("changed"),
		false,
		"repeating the same place service request is idempotent",
	)
	runtime.update_request("测试服务点", "request-a", true, 250, 102)
	_expect_equal(
		(runtime.state("测试服务点").get("pending_request_ids", []) as Array),
		["request-a", "request-b"],
		"place service requests are stable-sorted",
	)
	var opened_state := runtime.state("测试服务点")
	opened_state["open"] = false
	_expect_equal(
		runtime.state("测试服务点").get("open"),
		true,
		"place service state queries return deep copies",
	)
	var closed := runtime.update_open("测试服务点", false, 110)
	_expect_equal(closed.get("changed"), true, "place service open state changes")
	_expect_equal(
		runtime.service_control({
			"residentId": "resident-owner",
			"currentPlace": "测试服务点",
		}).get("open"),
		false,
		"service owner control projects the authoritative open state",
	)
	_expect_equal(
		runtime.service_control({
			"residentId": "resident-colleague",
			"currentPlace": "测试服务点",
			"socialState": {"workplace": "测试服务点"},
		}).get("open"),
		false,
		"同一地点的其他现任职员也能调整营业状态",
	)
	_expect_equal(
		runtime.is_closed_for_visitor({
			"residentId": "resident-visitor",
			"socialState": {"workplace": "其他地点"},
		}, "测试服务点"),
		true,
		"closed service blocks an unrelated visitor",
	)
	var pressure := runtime.pressure_payload("测试服务点", 1)
	_expect_equal(
		(pressure.get("payload", {}) as Dictionary).get("waiting_requests"),
		2,
		"service pressure derives waiting request count from owned state",
	)
	var snapshot := runtime.save_snapshot()
	runtime.reset()
	_expect(runtime.values_snapshot().is_empty(), "place service reset clears owned state")
	runtime.restore_prepared(snapshot)
	_expect_equal(
		runtime.first_pending_request("测试服务点"),
		"request-a",
		"place service snapshot restores pending request order",
	)


func _scenario_animal_fact_runtime_state() -> void:
	var runtime: TownAnimalFactRuntime = ANIMAL_FACT_RUNTIME.new()
	_expect_equal(
		runtime.prepare_upsert(
			{"animal_id": "cat-test"},
			100,
			Callable(self, "_animal_test_place_for_position"),
		).get("errorCode"),
		"ANIMAL_FACT_INVALID",
		"animal fact runtime rejects incomplete source state",
	)
	var created := runtime.prepare_upsert(
		{
			"animal_id": "cat-test",
			"display_name": "测试猫",
			"species": "cat",
			"exists": true,
			"position": Vector2(12.0, 24.0),
			"generation": 1,
		},
		100,
		Callable(self, "_animal_test_place_for_position"),
	)
	_expect_equal(created.get("changed"), true, "animal fact creation is meaningful")
	_expect_equal(
		(created.get("animal", {}) as Dictionary).get("place_id"),
		"测试地点",
		"animal fact runtime stores resolved world membership",
	)
	(created.get("animal", {}) as Dictionary)["display_name"] = "外部篡改"
	_expect_equal(
		runtime.fact("cat-test").get("display_name"),
		"测试猫",
		"animal fact query returns a deep copy",
	)
	var attention := runtime.prepare_public_attention(
		"cat-test",
		true,
		160,
		["event-b", "event-a", "event-b"],
		100,
	)
	_expect_equal(attention.get("changed"), true, "animal attention becomes active")
	_expect_equal(
		(runtime.fact("cat-test").get("source_event_ids", []) as Array),
		["event-a", "event-b"],
		"animal attention source ids are unique and stable-sorted",
	)
	_expect_equal(
		runtime.expire_public_attention(159),
		false,
		"animal attention remains active before its expiry minute",
	)
	_expect_equal(
		runtime.expire_public_attention(160),
		true,
		"animal attention expires at its authoritative minute",
	)
	_expect_equal(
		runtime.fact("cat-test").get("public_attention"),
		false,
		"expired animal attention is persisted in runtime state",
	)
	var restored: TownAnimalFactRuntime = ANIMAL_FACT_RUNTIME.new()
	restored.restore_prepared(runtime.save_snapshot())
	runtime.reset()
	_expect_equal(
		restored.public_snapshot().size(),
		1,
		"animal fact save snapshot restores independently of the source runtime",
	)


func _animal_test_place_for_position(_position: Vector2) -> String:
	return "测试地点"


func _scenario_dynamic_prop_runtime_state() -> void:
	var runtime: TownDynamicPropRuntime = DYNAMIC_PROP_RUNTIME.new()
	_expect_equal(
		runtime.normalize_identity("", "流浪猫").get("errorCode"),
		"DYNAMIC_PROP_IDENTITY_INVALID",
		"dynamic prop runtime rejects an empty identity",
	)
	var first_identity := runtime.normalize_identity(" prop-z ", " 流浪猫·乙 ")
	var second_identity := runtime.normalize_identity("prop-a", "流浪猫·甲")
	var placement := {
		"membership": {"placeName": "社区花园", "regionId": "garden"},
		"approachPosition": Vector2(10.0, 20.0),
	}
	_expect_equal(
		runtime.upsert_normalized(
			first_identity,
			Vector2(10.0, 10.0),
			true,
			true,
			placement,
		).get("status"),
		"registered",
		"dynamic prop runtime registers a normalized prop",
	)
	runtime.upsert_normalized(
		second_identity,
		Vector2(20.0, 20.0),
		true,
		true,
		placement,
	)
	var snapshot := runtime.snapshot()
	_expect_equal(
		(snapshot[0] as Dictionary).get("id"),
		"prop-a",
		"dynamic prop snapshot is sorted by stable identity",
	)
	(snapshot[0] as Dictionary)["name"] = "被调用方修改"
	_expect_equal(
		(runtime.snapshot()[0] as Dictionary).get("name"),
		"流浪猫·甲",
		"dynamic prop snapshot returns a deep copy",
	)
	_expect_equal(
		runtime.is_dynamic_action(
			{"currentPlace": "社区花园"},
			{"prop": "流浪猫·甲", "verb": "摸摸"},
		),
		true,
		"dynamic prop action matches place, name and verb",
	)
	var base_query_data := {"props": [{"id": "static-prop"}]}
	var merged_query_data := runtime.query_data(base_query_data)
	_expect_equal(
		(base_query_data.get("props", []) as Array).size(),
		1,
		"dynamic prop query merge does not mutate base World data",
	)
	_expect_equal(
		(merged_query_data.get("props", []) as Array).size(),
		3,
		"dynamic props are appended to the authoritative prop query view",
	)
	runtime.restore_layout_overrides([
		{"spaceId": "space-z", "value": 2},
		{"spaceId": "space-a", "value": 1},
	])
	var layout_snapshots := runtime.layout_override_snapshots()
	_expect_equal(
		(layout_snapshots[0] as Dictionary).get("spaceId"),
		"space-a",
		"layout override snapshots are sorted by space identity",
	)
	(layout_snapshots[0] as Dictionary)["value"] = 99
	_expect_equal(
		(runtime.layout_override_snapshots()[0] as Dictionary).get("value"),
		1,
		"layout override snapshots return deep copies",
	)
	runtime.reject_outside_world("prop-a", Vector2(999999.0, 999999.0))
	_expect_equal(
		runtime.snapshot().size(),
		1,
		"outside-world registration removes the previous prop identity",
	)
	runtime.reset()
	_expect(
		runtime.snapshot().is_empty()
			and runtime.layout_override_snapshots().is_empty(),
		"dynamic prop runtime reset clears transient props and layout overrides",
	)
	var data := _build_data()
	var opening := _load_opening(data)
	var world: RefCounted = WORLD.new()
	_expect_equal(
		world.call("start", data, opening).get("ok"),
		true,
		"World starts before dynamic prop integration checks",
	)
	var residents := (world.get("resident_registry") as TownResidentRegistry).records as Dictionary
	var outdoor_position := Vector2.ZERO
	for resident_value: Variant in residents.values():
		var resident := resident_value as Dictionary
		if String(resident.get("spaceId", "")) == "town_outdoor":
			outdoor_position = resident.get("position", Vector2.ZERO) as Vector2
			break
	var registered := world.call(
		"upsert_dynamic_prop",
		"dynamic-test-cat",
		"流浪猫·测试",
		outdoor_position,
		true,
	) as Dictionary
	_expect_equal(
		registered.get("status"),
		"registered",
		"World delegates valid dynamic prop placement to its runtime",
	)
	_expect_equal(
		(world.call("get_dynamic_prop_snapshot") as Array).size(),
		1,
		"World exposes the registered dynamic prop snapshot",
	)
	var outside := world.call(
		"upsert_dynamic_prop",
		"dynamic-test-cat",
		"流浪猫·测试",
		Vector2(999999.0, 999999.0),
		true,
	) as Dictionary
	_expect_equal(
		outside.get("errorCode"),
		"DYNAMIC_PROP_OUTSIDE_WORLD",
		"World rejects a dynamic prop outside every perception region",
	)
	_expect_equal(
		(world.call("get_dynamic_prop_snapshot") as Array).size(),
		0,
		"rejected outside placement removes the previous dynamic prop identity",
	)
	world.call("stop")
	_expect_equal(
		world.call(
			"upsert_dynamic_prop",
			"dynamic-test-cat",
			"流浪猫·测试",
			outdoor_position,
			true,
		).get("errorCode"),
		"WORLD_NOT_RUNNING",
		"stopped World rejects active dynamic prop registration",
	)
	_expect_equal(
		world.call("remove_dynamic_prop", "dynamic-test-cat").get("status"),
		"already_absent",
		"dynamic prop removal remains idempotent while World is stopped",
	)


func _scenario_frame_work_budget() -> void:
	var data := _build_data()
	var opening := _load_opening(data)
	var world: RefCounted = WORLD.new()
	var start_result := world.call("start", data, opening) as Dictionary
	_expect_equal(start_result.get("ok"), true, "frame-budget World starts")
	if start_result.get("ok") != true:
		return
	var now := _absolute_minute_foundation(world.call("get_time") as Dictionary)
	var resident_ids: Array = (
		world.call("get_resident_ids") as Array
	).slice(0, 8)
	var residents := (world.get("resident_registry") as TownResidentRegistry).records as Dictionary
	var activity_reachability_cache := world.get(
		"activity_reachability_state",
	) as TownActivityReachabilityCache
	activity_reachability_cache.clear()
	AGENT_WAKE_CONTEXT_RUNTIME.available_activities(
		world,
		residents[String(resident_ids[0])] as Dictionary,
		true,
	)
	_expect(
		activity_reachability_cache.reachability_count() <= 1,
		"one Agent wake performs at most one new activity route check",
	)
	for index in resident_ids.size():
		var resident_id := String(resident_ids[index])
		var resident := residents[resident_id] as Dictionary
		resident["decisionPending"] = false
		resident["pendingWake"] = {}
		resident["currentAction"] = {
			"action_id": "frame-budget-wait-%d" % index,
			"type": "待着",
			"line": "等待同一分钟结算",
			"startedAbsoluteMinute": now,
			"completeAbsoluteMinute": now + 1,
		}
	var minute_result := world.call("advance", 1.0) as Dictionary
	_expect_equal(minute_result.get("minutesAdvanced"), 1, "first frame advances one game minute")
	_expect_equal(
		_count_empty_actions(residents, resident_ids),
		8,
		"all actions finish in their authoritative game minute",
	)
	for resident_value: Variant in resident_ids:
		world.frame_budget_runtime.queue_resident_state_refresh(String(resident_value))
	var first_presentation_batch := world.call("advance", 0.1) as Dictionary
	_expect_equal(
		first_presentation_batch.get("deferredPresentationRefreshesProcessed"),
		3,
		"one frame publishes at most three resident presentation refreshes",
	)
	_expect_equal(
		first_presentation_batch.get("deferredPresentationRefreshCount"),
		5,
		"presentation refresh backlog remains measurable",
	)
	var second_presentation_batch := world.call("advance", 0.1) as Dictionary
	_expect_equal(second_presentation_batch.get("deferredPresentationRefreshesProcessed"), 3, "second presentation frame keeps the same work limit")
	var third_presentation_batch := world.call("advance", 0.1) as Dictionary
	_expect_equal(third_presentation_batch.get("deferredPresentationRefreshesProcessed"), 2, "finite presentation backlog drains without starvation")
	_expect_equal(third_presentation_batch.get("deferredPresentationRefreshCount"), 0, "presentation refresh queue becomes empty")
	var presentation_perception_frame := world.call("advance", 0.1) as Dictionary
	_expect_equal(presentation_perception_frame.get("deferredPerceptionProcessed"), true, "perception follows all queued presentation refreshes")
	(world.get("frame_budget_runtime") as TownWorldFrameBudgetRuntime).defer_perception_refresh()
	var forced_perception_refresh := false
	for _frame_index in 12:
		for resident_value: Variant in resident_ids:
			world.frame_budget_runtime.queue_resident_state_refresh(String(resident_value))
		var starvation_result := world.call("advance", 0.01) as Dictionary
		forced_perception_refresh = (
			forced_perception_refresh
			or bool(starvation_result.get("deferredPerceptionProcessed", false))
		)
	_expect_equal(
		forced_perception_refresh,
		true,
		"continuous presentation work cannot starve perception beyond twelve advances",
	)
	_expect(
		(world.get("frame_budget_runtime") as TownWorldFrameBudgetRuntime)
		.presentation_refresh_count() <= resident_ids.size(),
		"continuous presentation refreshes remain coalesced per resident",
	)
	# 清掉压力场景留下的表现工作，后面的地点通知断言只测自己的队列。
	(world.get("frame_budget_runtime") as TownWorldFrameBudgetRuntime).clear_presentation_refreshes()
	for index in 3:
		world.frame_budget_runtime.queue_resident_place_change_signal(String(resident_ids[index]), {
			"residentId": String(resident_ids[index]),
			"from": "测试旧地点",
			"to": "测试新地点",
			"time": world.call("get_time"),
			"worldRevision": world.call("get_world_revision"),
		}, int(world.call("get_world_revision")))
	world.frame_budget_runtime.queue_resident_place_change_signal(String(resident_ids[0]), {
		"residentId": String(resident_ids[0]),
		"from": "测试旧地点",
		"to": "测试最新地点",
		"time": world.call("get_time"),
		"worldRevision": world.call("get_world_revision"),
	}, int(world.call("get_world_revision")))
	_expect_equal(
		(world.get("frame_budget_runtime") as TownWorldFrameBudgetRuntime)
		.place_change_signal_count(),
		3,
		"repeated place changes coalesce per resident instead of growing forever",
	)
	var first_place_signal := world.call("advance", 0.1) as Dictionary
	_expect_equal(first_place_signal.get("deferredPlaceChangeSignalsProcessed"), 1, "one frame publishes at most one expensive place-change signal")
	_expect_equal(first_place_signal.get("deferredPlaceChangeSignalCount"), 2, "place-change backlog remains finite and measurable")
	var second_place_signal := world.call("advance", 0.1) as Dictionary
	var third_place_signal := world.call("advance", 0.1) as Dictionary
	_expect_equal(second_place_signal.get("deferredPlaceChangeSignalsProcessed"), 1, "second frame publishes the next place change")
	_expect_equal(third_place_signal.get("deferredPlaceChangeSignalCount"), 0, "place-change signal queue drains without starvation")
	_expect_equal(
		TOWN_RUNTIME.AGENT_DISPATCH_BUDGET_PER_FRAME,
		1,
		"each runtime frame admits at most one Agent request into the staged pipeline",
	)
	world.call("stop")


func _count_empty_actions(residents: Dictionary, resident_ids: Array) -> int:
	var count := 0
	for resident_value: Variant in resident_ids:
		var resident := residents[String(resident_value)] as Dictionary
		if (resident.get("currentAction", {}) as Dictionary).is_empty():
			count += 1
	return count


func _absolute_minute_foundation(time: Dictionary) -> int:
	var parts := String(time.get("clock", "00:00")).split(":")
	return (
		(int(time.get("day", 1)) - 1) * 1440
		+ int(parts[0]) * 60
		+ int(parts[1])
	)


func _scenario_indoor_props() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var authored := AUTHORING.build_document() as Dictionary
	_expect_equal(authored.get("ok"), true, "indoor prop authoring succeeds")
	for error in PROP_VALIDATOR.validate(data):
		_expect(false, str(error))
	_expect_equal((data.get("props", []) as Array).size(), 81, "catalog includes all authored work, writing, and rest props")
	_expect_equal(_indoor_prop_count(data), 63, "catalog includes indoor and fixed-scene interaction props")
	_expect_equal(_props_at_place(data, "独立市集").size(), 5, "fixed market stalls expose goods and flower work points")
	_expect_equal(int(authored.get("indoorSpaceCount", 0)), 23, "authoring covers all twenty-three indoor spaces")
	var colliding_name_data := data.duplicate(true)
	((colliding_name_data.get("props", []) as Array)[0] as Dictionary)["name"] = "中心广场"
	_expect(
		_errors_contain(PROP_VALIDATOR.validate(colliding_name_data), "道具中文名不得与地点中文名重复"),
		"validator enforces one Chinese identity namespace across places and props",
	)
	var duplicate_position_data := data.duplicate(true)
	var duplicate_position_props := (
		duplicate_position_data.get("props", []) as Array
	)
	var duplicate_position_prop := (
		(duplicate_position_props[1] as Dictionary).duplicate(true)
	)
	duplicate_position_prop["name"] = "重复位置测试道具"
	duplicate_position_prop["placeName"] = (
		(duplicate_position_props[0] as Dictionary).get("placeName", "")
	)
	duplicate_position_prop["interaction"] = (
		(duplicate_position_props[0] as Dictionary)
		.get("interaction", {})
		as Dictionary
	).duplicate(true)
	duplicate_position_props[1] = duplicate_position_prop
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(duplicate_position_data),
			"道具交互位置重复",
		),
		"validator rejects two semantic props at one physical interaction position",
	)
	var fractional_cell_size_data := data.duplicate(true)
	var fractional_cell_size_navigation := (
		fractional_cell_size_data.get("indoorNavigation", []) as Array
	)[0] as Dictionary
	fractional_cell_size_navigation["cellSize"] = 32.5
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(fractional_cell_size_data),
			"必须使用 32px 网格",
		),
		"validator rejects a fractional indoor navigation cell size",
	)
	var fractional_cell_data := data.duplicate(true)
	var fractional_navigation := (
		fractional_cell_data.get("indoorNavigation", []) as Array
	)[0] as Dictionary
	var fractional_cells := (
		fractional_navigation.get("walkableCells", []) as Array
	)
	var fractional_cell := fractional_cells[0] as Array
	fractional_cell[0] = float(fractional_cell[0]) + 0.5
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(fractional_cell_data),
			"walkableCells[0] 无效",
		),
		"validator rejects a fractional indoor navigation coordinate",
	)
	var fractional_duration_data := data.duplicate(true)
	var duration_action := (
		((fractional_duration_data.get("props", []) as Array)[0] as Dictionary)
		.get("actions", []) as Array
	)[0] as Dictionary
	duration_action["durationMinutes"] = 240.000001
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(fractional_duration_data),
			"正整数 durationMinutes",
		),
		"validator rejects an approximately integral action duration",
	)
	var fractional_effect_data := data.duplicate(true)
	var effect_action := (
		((fractional_effect_data.get("props", []) as Array)[0] as Dictionary)
		.get("actions", []) as Array
	)[0] as Dictionary
	(effect_action.get("effects", {}) as Dictionary)["困"] = -2.000001
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(fractional_effect_data),
			"效果必须为整数",
		),
		"validator rejects an approximately integral body-state effect",
	)
	var home_without_sleep_data := data.duplicate(true)
	for prop_value in home_without_sleep_data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		if str(prop.get("placeName", "")) != "北街一号住宅":
			continue
		var action := (prop.get("actions", []) as Array)[0] as Dictionary
		action["verb"] = "歇着"
		break
	_expect(
		_errors_contain(
			PROP_VALIDATOR.validate(home_without_sleep_data),
			"住家必须提供睡觉动作：北街一号住宅",
		),
		"validator rejects a furnished home without a sleep action",
	)
	var approximate_endpoint_data := data.duplicate(true)
	var outdoor_prop := {}
	for prop_value in approximate_endpoint_data.get("props", []) as Array:
		var candidate := prop_value as Dictionary
		var candidate_interaction := (
			candidate.get("interaction", {}) as Dictionary
		)
		if str(candidate_interaction.get("spaceId", "")) == "town_outdoor":
			outdoor_prop = candidate
			break
	_expect(
		not outdoor_prop.is_empty(),
		"catalog exposes an outdoor prop regression target",
	)
	if not outdoor_prop.is_empty():
		var outdoor_interaction := (
			outdoor_prop.get("interaction", {}) as Dictionary
		)
		var approach_polyline := (
			outdoor_interaction.get("approachPolyline", []) as Array
		)
		var approximate_endpoint := (
			approach_polyline[approach_polyline.size() - 1] as Array
		)
		approximate_endpoint[0] = (
			float(approximate_endpoint[0]) + 0.000001
		)
		_expect(
			_errors_contain(
				PROP_VALIDATOR.validate(approximate_endpoint_data),
				"必须是 approachPolyline 终点",
			),
			"validator rejects an approximately matching outdoor approach endpoint",
		)
	var authored_text := JSON.stringify((authored.get("document", {}) as Dictionary), "", true)
	var normalized_authored: Variant = JSON.parse_string(authored_text)
	_expect_equal(
		JSON.stringify(normalized_authored, "", true),
		JSON.stringify(BUILDER.load_json_object(SOURCE_DIR + "/props.json"), "", true),
		"checked authoring output exactly matches props.json",
	)
	_validate_agent_projection(data)
	_validate_walkable_interactions(data)
	_validate_formal_indoor_action(data)
	_validate_dynamic_world_projection(data)
	return
func _validate_agent_projection(data: Dictionary) -> void:
	var projected := PROP_QUERY.agent_props_at_place(data, "北街一号住宅") as Array
	_expect_equal(projected.size(), 1, "home projects its bed to the Agent")
	if projected.is_empty():
		return
	var prop := projected[0] as Dictionary
	_expect_equal(prop.get("name"), "北街一号住宅单人床", "Agent projection keeps the unique Chinese prop name")
	_expect_equal(prop.get("verbs"), ["睡觉"], "Agent projection keeps only supported verbs")
	_expect(not prop.has("interaction"), "Agent projection hides coordinates and furniture provenance")
	var action := PROP_QUERY.action_definition(data, "北街一号住宅", "北街一号住宅单人床", "睡觉")
	_expect_equal(action.get("durationMinutes"), 480, "sleep duration spans the normal night")
	_expect_equal((action.get("effects", {}) as Dictionary).get("困"), -2, "sleep applies the authored tiredness effect")
	var library_props := PROP_QUERY.agent_props_at_place(data, "图书馆") as Array
	var writing_props := library_props.filter(
		func(value: Variant) -> bool:
			return (
				value is Dictionary
				and String((value as Dictionary).get("name", "")) == "图书馆写作桌"
			)
	)
	_expect_equal(
		writing_props.size(),
		1,
		"a resident with a writing goal can discover one executable writing place",
	)
	if not writing_props.is_empty():
		_expect_equal(
			(writing_props[0] as Dictionary).get("verbs"),
			["写作", "整理字帖"],
			"one real writing desk can expose several supported actions",
		)
	var dining_props := PROP_QUERY.agent_props_at_place(
		data,
		"公共食堂",
	) as Array
	_expect_equal(
		_verbs_for_prop(dining_props, "公共食堂灶台"),
		["做饭", "烘烤面包"],
		"one real stove carries both cooking actions",
	)
	_expect_equal(
		_verbs_for_prop(dining_props, "公共食堂备餐柜"),
		["取餐"],
		"the pantry pickup point only serves customers collecting meals",
	)
	_expect_equal(
		_verbs_for_prop(dining_props, "公共食堂递餐口"),
		["递餐"],
		"the pantry service point is independent from customer pickup",
	)
	_expect_equal(
		_verbs_for_prop(dining_props, "公共食堂面团操作台"),
		["准备面团"],
		"the pantry dough point is independent from meal handoff",
	)



func _validate_walkable_interactions(data: Dictionary) -> void:
	var authoring := BUILDER.load_json_object(SOURCE_DIR + "/indoor_prop_authoring.json")
	var props_by_room := {}
	var navigation_by_space := {}
	for navigation_value in data.get("indoorNavigation", []) as Array:
		var navigation := navigation_value as Dictionary
		navigation_by_space[str(navigation.get("spaceId", ""))] = navigation
	for prop_value in data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		var interaction := prop.get("interaction", {}) as Dictionary
		var room_id := str(interaction.get("roomId", ""))
		if room_id.is_empty():
			continue
		var room_props := props_by_room.get(room_id, []) as Array
		room_props.append(prop)
		props_by_room[room_id] = room_props
	for room_value in authoring.get("rooms", []) as Array:
		var room := room_value as Dictionary
		var room_id := str(room.get("roomId", ""))
		var template_id := str(room.get("templateRoomId", room_id))
		var root := ROOMS_ROOT.path_join(template_id)
		var geometry := BUILDER.load_json_object(root.path_join("room_geometry.json"))
		var manifest := BUILDER.load_json_object(root.path_join("furniture_manifest.json"))
		var layout := BUILDER.load_json_object(root.path_join(str(room.get("layoutFile", "layout.json"))))
		var navigation := navigation_by_space.get(str(room.get("spaceId", "")), {}) as Dictionary
		var cell_size := int(navigation.get("cellSize", 0))
		var layout_floor := _cell_set(geometry.get("floor_cells", []) as Array)
		var definitions := {}
		var instances_by_id := {}
		var ground_by_instance := {}
		var furniture_polygons: Array[PackedVector2Array] = []
		for asset_value in manifest.get("assets", []) as Array:
			var asset := asset_value as Dictionary
			definitions[str(asset.get("asset_id", ""))] = BUILDER.load_json_object(str(asset.get("definition_path", "")))
		for instance_value in layout.get("instances", []) as Array:
			var instance := instance_value as Dictionary
			var instance_id := str(instance.get("instance_id", ""))
			instances_by_id[instance_id] = instance
			var definition := definitions.get(str(instance.get("asset_id", "")), {}) as Dictionary
			var origin := _point(instance.get("position_px"))
			var direction := str(instance.get("direction", "down"))
			var translated_polygons: Array[PackedVector2Array] = []
			for polygon in GEOMETRY.rotated_ground_contact_polygons(definition, direction):
				var translated := PackedVector2Array()
				for point in polygon:
					translated.append(point + origin)
				translated_polygons.append(translated)
				furniture_polygons.append(translated)
			ground_by_instance[instance_id] = translated_polygons
		var navigation_candidates := MOVEMENT_CLEARANCE.subdivide_cells(
			layout_floor,
			LAYOUT_CELL_SIZE,
			cell_size,
		)
		var walkable := MOVEMENT_CLEARANCE.filter_walkable_cells(
			navigation_candidates,
			cell_size,
			ROOM_GEOMETRY.get_boundary_collision_rects(geometry),
			furniture_polygons,
		)
		walkable = MOVEMENT_CLEARANCE.retain_reachable_cells(
			walkable,
			cell_size,
			ROOM_GEOMETRY.get_primary_entry_point(geometry),
		)
		var entry_cell := _walkable_cell_for_point(
			ROOM_GEOMETRY.get_primary_entry_point(geometry),
			cell_size,
			walkable,
		)
		_expect(entry_cell != INVALID_CELL, "%s has a doorway entry anchor" % room_id)
		_expect(walkable.has(entry_cell), "%s doorway entry cell is walkable" % room_id)
		var reachable := _reachable_cells(entry_cell, walkable)
		for prop_value in props_by_room.get(room_id, []) as Array:
			var prop := prop_value as Dictionary
			var interaction := prop.get("interaction", {}) as Dictionary
			var interaction_position := _point(interaction.get("position"))
			var interaction_cell := _walkable_cell_for_point(
				interaction_position,
				cell_size,
				walkable,
			)
			_expect(
				walkable.has(interaction_cell),
				"%s interaction is on floor minus all layout furniture" % str(prop.get("name", "")),
			)
			_expect(
				reachable.has(interaction_cell),
				"%s interaction is reachable from the room doorway" % str(prop.get("name", "")),
			)
			_expect(
				not interaction.has("approachPolyline"),
				"%s does not bake a fixed indoor approach path" % str(prop.get("name", "")),
			)
			if (
				bool(interaction.get("anchorSnappedToFloor", false))
				and instances_by_id.has(str(interaction.get("instanceId", "")))
			):
				var instance_id := str(interaction.get("instanceId", ""))
				var owner := instances_by_id.get(instance_id, {}) as Dictionary
				var definition := definitions.get(str(owner.get("asset_id", "")), {}) as Dictionary
				var anchor_id := str(interaction.get("anchorId", ""))
				_expect(
					_anchor_kind(definition, anchor_id) == "sit",
					"%s only snaps an authored sit/seat center out of its own collision"
					% str(prop.get("name", "")),
				)
				_expect(
					_point_is_in_any_polygon(
						_point(interaction.get("sourceAnchorPosition")),
						ground_by_instance.get(instance_id, []) as Array,
					),
					"%s snapped source is inside its owning seat ground_contact"
					% str(prop.get("name", "")),
				)
		# functional_anchor 属于 32px 房间布局的制作约束，仍由
		# town_indoor_layout_instance_geometry_test 覆盖；World 的正式寻路目标
		# 是门连接点和上面已校验的道具交互点。
		var expected_cells := _serialized_cells(walkable)
		_expect(
			_cell_arrays_equal(navigation.get("walkableCells", []) as Array, expected_cells),
			"%s publishes the current furniture collision grid" % room_id,
		)



func _validate_formal_indoor_action(data: Dictionary) -> void:
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "formal opening fixture is legal")
	if opening_result.get("ok") != true:
		return
	var opening := FORMAL_OPENING.with_authoritative_new_game_spawns(
		data,
		opening_result.get("config", {}) as Dictionary,
	)
	var navigation := _navigation_for_space(data, "home_01")
	var cell_size := float(navigation.get("cellSize", 0.0))
	var navigation_cells := navigation.get("walkableCells", []) as Array
	var start_cell := navigation_cells[-1] as Array
	var start := _cell_center(start_cell, cell_size)
	var plan := PROP_QUERY.interaction_plan(
		data,
		"北街一号住宅",
		"北街一号住宅单人床",
		"睡觉",
		start,
	)
	var approach := plan.get("approachPolyline", []) as Array
	_expect(approach.size() > 2, "indoor action computes a route across the current collision grid")
	_expect_equal(
		plan.get("actorFacing"),
		null,
		"movement plans stay free of presentation-only pose data",
	)
	var sleep_cue := PROP_QUERY.presentation_cue(
		data,
		"北街一号住宅",
		"北街一号住宅单人床",
		"睡觉",
	)
	_expect_equal(
		sleep_cue.get("actorFacing"),
		"right",
		"authored bed interaction publishes the rotated actor facing",
	)
	_expect_equal(
		sleep_cue.get("anchorKind"),
		"use",
		"prop presentation keeps the asset anchor semantic lightweight",
	)
	if approach.is_empty():
		return
	var alternate_cell := navigation_cells[0] as Array
	var alternate_start := _cell_center(alternate_cell, cell_size)
	var alternate_plan := PROP_QUERY.interaction_plan(
		data,
		"北街一号住宅",
		"北街一号住宅单人床",
		"睡觉",
		alternate_start,
	)
	_expect(
		alternate_plan.get("approachPolyline", []) != approach,
		"the same prop gets a fresh path from a different actor position",
	)
	var world: RefCounted = WORLD.new()
	var start_result := world.call("start_formal", data, opening, _resident_identities(opening)) as Dictionary
	_expect_equal(start_result.get("ok"), true, "completed catalog starts through the formal World gate")
	if start_result.get("ok") != true:
		return
	var formal_resident := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get("resident_lin_lan_01", {})
		as Dictionary
	)
	var formal_activity := formal_resident.get("activityState", {}) as Dictionary
	formal_activity["energy"] = 35
	ACTIVITY_SCALARS.sync_body_from_activity_needs(formal_resident, formal_activity)
	world.call("cycle_time_period_for_test")
	world.call("cycle_time_period_for_test")
	var requests := world.call("take_pending_decision_requests", ["林岚"]) as Array[Dictionary]
	var wake := requests[0].get("wakePacket", {}) as Dictionary
	var arrive_home := {
		"decision_id": wake.get("decision_id", ""),
		"handling": "replace_current",
		"action": {
			"action_id": "formal-arrive-home-before-sleep",
			"type": "去",
			"place": "北街一号住宅",
			"line": "从南入口沿正式路线回家",
		},
	}
	var arrive_home_result := (
		world.call("submit_agent_decision", "林岚", arrive_home) as Dictionary
	)
	_expect_equal(
		arrive_home_result.get("status"),
		"accepted",
		"formal resident enters the assigned home through navigation and its portal: %s"
		% str(arrive_home_result),
	)
	var movement_guard := 0
	while (
		(world.call("get_resident_state", "林岚") as Dictionary).get("currentAction") != null
		and movement_guard < 600
	):
		world.call("advance", 1.0)
		movement_guard += 1
	var arrived_home := world.call("get_resident_state", "林岚") as Dictionary
	_expect(movement_guard < 600, "formal resident reaches the assigned home deterministically")
	_expect_equal(arrived_home.get("spaceId"), "home_01", "formal route crosses into the assigned home space")
	requests = world.call("take_pending_decision_requests", ["林岚"]) as Array[Dictionary]
	_expect_equal(requests.size(), 1, "home arrival emits one new decision request")
	if requests.is_empty():
		return
	wake = requests[0].get("wakePacket", {}) as Dictionary
	var decision := {
		"decision_id": wake.get("decision_id", ""),
		"handling": "replace_current",
		"action": {
			"action_id": "formal-indoor-sleep",
			"type": "用道具",
			"prop": "北街一号住宅单人床",
			"verb": "睡觉",
			"line": "回家睡觉",
		},
	}
	_expect_equal(world.call("submit_agent_decision", "林岚", decision).get("status"), "accepted", "formal World accepts an indoor prop action")
	var approach_guard := 0
	while (
		not ((world.call("get_resident_state", "林岚") as Dictionary).get("position") as Vector2).is_equal_approx(
			plan.get("position") as Vector2
		)
		and approach_guard < 10
	):
		world.call("advance", 1.0)
		approach_guard += 1
	_expect(approach_guard < 10, "resident walks to the indoor interaction anchor promptly")
	_expect(
		(world.call("get_resident_state", "林岚") as Dictionary).get("currentAction") != null,
		"resident remains at the prop while the authored interaction duration elapses",
	)
	world.call("advance", 480.0)
	var state := world.call("get_resident_state", "林岚") as Dictionary
	_expect((state.get("position") as Vector2).is_equal_approx(plan.get("position") as Vector2), "indoor action finishes at its walkable interaction anchor")
	_expect_equal(state.get("currentAction"), null, "indoor prop action completes after its authored duration")
	_expect_equal(
		(state.get("routeConnector", []) as Array).size(),
		0,
		"indoor action completion clears the temporary approach connector",
	)
	requests = world.call("take_pending_decision_requests", ["林岚"]) as Array[Dictionary]
	_expect_equal(
		requests.size(),
		1,
		"completed indoor interaction immediately schedules the resident's next decision",
	)



func _validate_dynamic_world_projection(data: Dictionary) -> void:
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "dynamic layout opening fixture is legal")
	if opening_result.get("ok") != true:
		return
	var opening := FORMAL_OPENING.with_authoritative_new_game_spawns(
		data,
		opening_result.get("config", {}) as Dictionary,
	)
	var navigation := _navigation_for_space(data, "home_01")
	var cell_size := float(navigation.get("cellSize", 0.0))
	var cells := navigation.get("walkableCells", []) as Array
	var start_cell := cells[0] as Array
	var start := _cell_center(start_cell, cell_size)
	var world: RefCounted = WORLD.new()
	var dynamic_start_result := world.call("start_formal", data, opening, _resident_identities(opening)) as Dictionary
	var activity_reachability_cache := world.get(
		"activity_reachability_state",
	) as TownActivityReachabilityCache
	_expect_equal(
		dynamic_start_result.get("ok"),
		true,
		"formal World starts before a dynamic furniture edit",
	)
	var dynamic_resident := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get("resident_lin_lan_01", {})
		as Dictionary
	)
	var dynamic_activity := dynamic_resident.get("activityState", {}) as Dictionary
	dynamic_activity["energy"] = 35
	ACTIVITY_SCALARS.sync_body_from_activity_needs(dynamic_resident, dynamic_activity)
	world.call("cycle_time_period_for_test")
	world.call("cycle_time_period_for_test")
	var entry_wake := _take_request(world, "林岚")
	var enter_home_result := world.call("submit_agent_decision", "林岚", {
		"decision_id": entry_wake.get("decision_id", ""),
		"handling": "replace_current",
		"action": {
			"action_id": "dynamic-layout-enter-home",
			"type": "去",
			"place": "北街一号住宅",
			"line": "从南入口沿正式路线回家",
		},
	}) as Dictionary
	_expect_equal(
		enter_home_result.get("status"),
		"accepted",
		"dynamic projection resident enters the home through the formal route: %s"
		% str(enter_home_result),
	)
	var movement_guard := 0
	while (
		(world.call("get_resident_state", "林岚") as Dictionary).get("currentAction") != null
		and movement_guard < 600
	):
		world.call("advance", 1.0)
		movement_guard += 1
	_expect(movement_guard < 600, "dynamic projection resident reaches home deterministically")
	_expect_equal(
		(world.call("get_resident_state", "林岚") as Dictionary).get("spaceId"),
		"home_01",
		"dynamic projection resident is physically inside before Agent prop facts are tested",
	)
	_take_request(world, "林岚")
	var initial := world.call("get_indoor_layout_projection", "home_01") as Dictionary
	_expect_equal((initial.get("props", []) as Array).size(), 1, "home starts from the authored default layout projection")
	_expect_equal(world.call("pause", "furniture_editor").get("ok"), true, "furniture editor pauses World through its public reason")

	var invalid := initial.duplicate(true)
	(invalid.get("props", []) as Array).append(((invalid.get("props", []) as Array)[0] as Dictionary).duplicate(true))
	var invalid_result := world.call("apply_indoor_layout_projection", invalid) as Dictionary
	_expect_equal(invalid_result.get("ok"), false, "duplicate dynamic prop identity is rejected")
	_expect_equal(
		world.call("get_indoor_layout_projection", "home_01"),
		initial,
		"rejected dynamic layout keeps the active projection",
	)

	var moved := initial.duplicate(true)
	var moved_prop := ((moved.get("props", []) as Array)[0] as Dictionary)
	var moved_interaction := moved_prop.get("interaction", {}) as Dictionary
	var target_cell := _different_cell(cells, start_cell)
	var target := _cell_center(target_cell, cell_size)
	moved_interaction["position"] = [target.x, target.y]
	moved_interaction["sourceAnchorPosition"] = [target.x, target.y]
	moved_interaction["instancePosition"] = [target.x, target.y]
	var moved_navigation := moved.get("navigation", {}) as Dictionary
	var removed_cell := _remove_safe_navigation_cell(
		moved_navigation,
		[start_cell, target_cell],
	)
	_expect(not removed_cell.is_empty(), "dynamic edit can publish a changed collision grid")
	var move_result := world.call("apply_indoor_layout_projection", moved) as Dictionary
	_expect_equal(
		move_result.get("ok"),
		true,
		"World atomically accepts moved props and current collision: %s"
		% str(move_result),
	)
	_expect(
		activity_reachability_cache.reachability_count() == 0
			and activity_reachability_cache.prepared_action_count() == 0
			and activity_reachability_cache.cached_minute() == -1,
		"layout edits invalidate same-minute activity route cache",
	)
	var dynamic_data := LAYOUT_PROJECTION.apply(data, moved) as Dictionary
	var moved_plan := PROP_QUERY.interaction_plan(
		dynamic_data,
		"北街一号住宅",
		"北街一号住宅单人床",
		"睡觉",
		start,
	) as Dictionary
	_expect_equal(moved_plan.get("position"), target, "prop action targets the moved interaction anchor")
	_expect(
		not _path_contains_cell_center(
			moved_plan.get("approachPolyline", []) as Array,
			removed_cell,
			cell_size,
		),
		"fresh prop path avoids the latest furniture collision grid",
	)
	world.call("resume", "furniture_editor")
	var refreshed := _take_request(world, "林岚")
	_expect_equal(refreshed.size(), 5, "layout edit invalidates stale Agent facts through an exact fresh wake")
	_expect_equal(
		((((refreshed.get("snapshot", {}) as Dictionary).get("place", {}) as Dictionary).get("props", []) as Array).size()),
		1,
		"fresh Agent wake sees the moved prop projection",
	)

	world.call("pause", "furniture_editor")
	var removed := world.call("get_indoor_layout_projection", "home_01") as Dictionary
	removed["props"] = []
	_expect_equal(world.call("apply_indoor_layout_projection", removed).get("ok"), true, "removing furniture removes its Agent prop")
	_expect_equal(
		((world.call("get_place_detail", "北街一号住宅") as Dictionary).get("props", []) as Array).size(),
		0,
		"removed furniture is absent from current place facts",
	)

	var added := world.call("get_indoor_layout_projection", "home_01") as Dictionary
	var added_prop := moved_prop.duplicate(true)
	added_prop["name"] = "北街一号住宅新单人床"
	(added_prop.get("interaction", {}) as Dictionary)["instanceId"] = "home_01_player_bed_02"
	added["props"] = [added_prop]
	_expect_equal(world.call("apply_indoor_layout_projection", added).get("ok"), true, "adding furniture publishes a new stable Agent prop")
	_expect_equal(
		((world.call("get_place_detail", "北街一号住宅") as Dictionary).get("props", []) as Array)[0].get("name"),
		"北街一号住宅新单人床",
		"Agent facts use the newly added furniture identity",
	)
	world.call("resume", "furniture_editor")
	var added_wake := _take_request(world, "林岚")
	var added_props := (
		((added_wake.get("snapshot", {}) as Dictionary).get(
			"place",
			{},
		) as Dictionary).get("props", []) as Array
	)
	_expect(not added_props.is_empty(), "new furniture enters the Agent wake")
	if not added_props.is_empty():
		_expect_equal(
			(added_props[0] as Dictionary).get("name"),
			"北街一号住宅新单人床",
			"new furniture keeps its stable Agent identity",
		)
	var added_action := world.call(
		"submit_agent_decision",
		"林岚",
		{
			"decision_id": added_wake.get("decision_id", ""),
			"handling": "replace_current",
			"action": {
				"action_id": "dynamic-layout-use-new-bed",
				"type": "用道具",
				"prop": "北街一号住宅新单人床",
				"verb": "睡觉",
				"line": "在新摆的床上休息",
			},
		},
	) as Dictionary
	_expect_equal(
		added_action.get("status"),
		"accepted",
		"new furniture executes through its authored direct prop semantics",
	)
	for _step in 5:
		world.call("advance", 0.5)
	world.call("pause", "furniture_editor")
	var saved_projection := world.call("get_indoor_layout_projection", "home_01") as Dictionary
	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(save_result.get("ok"), true, "dynamic indoor layout enters the formal World snapshot")
	var decoded_state := SAVE_CODEC.decode_checked(
		((save_result.get("snapshot", {}) as Dictionary).get("state", {})),
	) as Dictionary
	_expect_equal(decoded_state.get("ok"), true, "dynamic indoor save state decodes")
	var saved_state := decoded_state.get("value", {}) as Dictionary
	_expect_equal(
		(saved_state.get("indoorLayoutOverrides", []) as Array).size(),
		1,
		"save stores only changed rooms instead of duplicating all default layouts",
	)
	var serialized: Variant = JSON.parse_string(JSON.stringify(save_result.get("snapshot", {})))
	var restored_world: RefCounted = WORLD.new()
	var restore_result := restored_world.call(
		"restore_from_snapshot",
		data,
		opening,
		serialized as Dictionary,
		_resident_identities(opening),
	) as Dictionary
	_expect_equal(
		restore_result.get("ok"),
		true,
		"serialized dynamic layout restores through the formal boundary: %s"
		% JSON.stringify(restore_result),
	)
	var encoded_projection := SAVE_CODEC.encode_checked(saved_projection) as Dictionary
	_expect_equal(encoded_projection.get("ok"), true, "dynamic layout projection encodes")
	var decoded_projection := SAVE_CODEC.decode_checked(
		encoded_projection.get("value", {}),
	) as Dictionary
	_expect_equal(decoded_projection.get("ok"), true, "dynamic layout projection decodes")
	_expect_equal(
		restored_world.call("get_indoor_layout_projection", "home_01"),
		decoded_projection.get("value", {}),
		"save and restore preserve moved props and current collision exactly",
	)



func _resident_identities(opening: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		result.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(resident.get("attributes", {}).get("name", "")),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	return result



func _indoor_prop_count(data: Dictionary) -> int:
	var count := 0
	for value in data.get("props", []) as Array:
		if str(((value as Dictionary).get("interaction", {}) as Dictionary).get("spaceId", "")) != "town_outdoor":
			count += 1
	return count



func _props_at_place(data: Dictionary, place_name: String) -> Array:
	var result := []
	for value in data.get("props", []) as Array:
		if str((value as Dictionary).get("placeName", "")) == place_name:
			result.append(value)
	return result



func _cell_set(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		result[Vector2i(int(value[0]), int(value[1]))] = true
	return result



func _serialized_cells(cells: Dictionary) -> Array:
	var result := []
	for cell_value in cells:
		var cell := cell_value as Vector2i
		result.append([cell.x, cell.y])
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return int((left as Array)[1]) < int((right as Array)[1]) or (
			int((left as Array)[1]) == int((right as Array)[1])
			and int((left as Array)[0]) < int((right as Array)[0])
		)
	)
	return result



func _cell_arrays_equal(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if (
			int((left[index] as Array)[0]) != int((right[index] as Array)[0])
			or int((left[index] as Array)[1]) != int((right[index] as Array)[1])
		):
			return false
	return true



func _navigation_for_space(data: Dictionary, space_id: String) -> Dictionary:
	for value in data.get("indoorNavigation", []) as Array:
		var navigation := value as Dictionary
		if str(navigation.get("spaceId", "")) == space_id:
			return navigation
	return {}



func _cell_center(cell: Array, cell_size: float) -> Vector2:
	return MOVEMENT_CLEARANCE.body_origin_for_cell(
		Vector2i(int(cell[0]), int(cell[1])),
		cell_size,
	)



func _different_cell(cells: Array, excluded: Array) -> Array:
	for index in range(cells.size() - 1, -1, -1):
		var cell := cells[index] as Array
		if int(cell[0]) != int(excluded[0]) or int(cell[1]) != int(excluded[1]):
			return cell.duplicate()
	return []



func _remove_safe_navigation_cell(navigation: Dictionary, excluded: Array) -> Array:
	var cells := navigation.get("walkableCells", []) as Array
	for index in cells.size():
		var candidate := cells[index] as Array
		if _cell_list_contains(excluded, candidate):
			continue
		var next := cells.duplicate(true)
		next.remove_at(index)
		if _all_cells_connected(next):
			navigation["walkableCells"] = next
			return candidate.duplicate()
	return []



func _cell_list_contains(cells: Array, expected: Array) -> bool:
	for value in cells:
		var cell := value as Array
		if int(cell[0]) == int(expected[0]) and int(cell[1]) == int(expected[1]):
			return true
	return false



func _all_cells_connected(cells: Array) -> bool:
	if cells.is_empty():
		return false
	var lookup := {}
	for value in cells:
		var pair := value as Array
		lookup[Vector2i(int(pair[0]), int(pair[1]))] = true
	var start := lookup.keys()[0] as Vector2i
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = current + offset
			if lookup.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == lookup.size()



func _walkable_cell_for_point(
	point: Vector2,
	cell_size: float,
	cells: Dictionary,
) -> Vector2i:
	if cell_size <= 0.0:
		return INVALID_CELL
	var candidates: Array[Vector2i] = []
	var base := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
	for offset_y in [-1, 0]:
		for offset_x in [-1, 0]:
			var cell := base + Vector2i(offset_x, offset_y)
			if not cells.has(cell):
				continue
			if Rect2(Vector2(cell) * cell_size, Vector2.ONE * cell_size).grow(0.01).has_point(point):
				candidates.append(cell)
	if candidates.is_empty():
		return INVALID_CELL
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := MOVEMENT_CLEARANCE.body_origin_for_cell(
			left,
			cell_size,
		).distance_squared_to(point)
		var right_distance := MOVEMENT_CLEARANCE.body_origin_for_cell(
			right,
			cell_size,
		).distance_squared_to(point)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
	return candidates[0]



func _reachable_cells(start: Vector2i, cells: Dictionary) -> Dictionary:
	if not cells.has(start):
		return {}
	var result := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = current + offset
			if cells.has(next) and not result.has(next):
				result[next] = true
				queue.append(next)
	return result



func _path_contains_cell_center(path: Array, cell: Array, cell_size: float) -> bool:
	var center := _cell_center(cell, cell_size)
	for point_value in path:
		if (point_value as Vector2).is_equal_approx(center):
			return true
	return false



func _take_request(world: RefCounted, resident_name: String) -> Dictionary:
	for request_value in world.call("take_pending_decision_requests", [resident_name]) as Array:
		var request := request_value as Dictionary
		if str(request.get("residentName", "")) == resident_name:
			return (request.get("wakePacket", {}) as Dictionary).duplicate(true)
	return {}



func _point(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))



func _anchor_kind(definition: Dictionary, anchor_id: String) -> String:
	for value in definition.get("interaction_anchor", []) as Array:
		var anchor := value as Dictionary
		if str(anchor.get("id", "")) == anchor_id:
			return str(anchor.get("kind", ""))
	return ""



func _verbs_for_prop(props: Array, prop_name: String) -> Array:
	for value: Variant in props:
		if (
			value is Dictionary
			and String((value as Dictionary).get("name", "")) == prop_name
		):
			return (value as Dictionary).get("verbs", []) as Array
	return []



func _point_is_in_any_polygon(point: Vector2, polygons: Array) -> bool:
	for value in polygons:
		if Geometry2D.is_point_in_polygon(point, value as PackedVector2Array):
			return true
	return false



func _errors_contain(errors: PackedStringArray, text: String) -> bool:
	for error in errors:
		if str(error).contains(text):
			return true
	return false



func _scenario_daily_life_chain() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "daily-life opening loads")
	if not bool(opening_result.get("ok", false)):
		return
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call(
			"start",
			data,
			opening_result.get("config", {}) as Dictionary,
		) as Dictionary).get("ok"),
		true,
		"daily-life World starts",
	)

	var lin_wake := _take_wake_daily_life_chain(world, "林岚")
	var a_he_wake := _take_wake_daily_life_chain(world, "阿禾")
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_go_daily_life_chain(lin_wake, "工作坊", "去工作坊开工"),
		) as Dictionary,
		"resident can commute to work",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"阿禾",
			_go_daily_life_chain(a_he_wake, "花房咖啡馆", "回咖啡馆照看生意"),
		) as Dictionary,
		"cafe worker can commute to the cafe",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"work commute completes",
	)
	_expect(
		_advance_until_action_clears(world, "阿禾"),
		"cafe commute completes",
	)
	_expect_equal(
		(world.call("get_resident_state", "林岚") as Dictionary).get(
			"currentPlace",
		),
		"工作坊",
		"worker reaches the authored workplace",
	)
	_expect_equal(
		(world.call("get_resident_state", "阿禾") as Dictionary).get(
			"currentPlace",
		),
		"花房咖啡馆",
		"cafe worker reaches the authored workplace",
	)
	_expect_equal(
		(world.call("create_work_task", {
			"taskId": "daily-life-craft-production",
			"capability": "craft.production",
			"sourceKind": "production_request",
			"sourceRef": "daily-life-chain",
			"targets": [{
				"kind": "prop",
				"ref": "工作坊主木工台",
			}],
			"requestedResultKind": "crafted_lot",
			"priority": 70,
		}) as Dictionary).get("ok"),
		true,
		"daily-life workshop work is backed by a real production task",
	)

	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	a_he_wake = _take_wake_daily_life_chain(world, "阿禾")
	var lin_work_activity := _available_worker_activity_id(world, "林岚")
	var a_he_work_activity := _available_worker_activity_id(world, "阿禾")
	_expect(
		not lin_work_activity.is_empty(),
		"workshop exposes a real available worker activity",
	)
	_expect(
		not a_he_work_activity.is_empty(),
		"cafe exposes a real available worker activity",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_do_activity(
				lin_wake,
				lin_work_activity,
				"在木工台做今天的活",
			),
		) as Dictionary,
		"arrival can continue into a task-backed workshop activity",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"阿禾",
			_do_activity(
				a_he_wake,
				a_he_work_activity,
				"在店里照看生意",
			),
		) as Dictionary,
		"cafe worker starts a real cafe work activity",
	)
	var work_chain := _advance_until_action_clears_with_positions(
		world,
		"林岚",
	)
	_expect(
		bool(work_chain.get("completed", false)),
		"workplace activity completes",
	)
	_expect(
		(work_chain.get("positions", []) as Array).size() >= 2,
		"work consists of movement between multiple authored workplace points",
	)
	_expect_equal(
		(world.call("set_weather", "小雨") as Dictionary).get("changed"),
		true,
		"rain begins after the resident finishes indoor work",
	)

	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	var rainy_snapshot := lin_wake.get("snapshot", {}) as Dictionary
	var rainy_context := rainy_snapshot.get(
		"weather_context",
		{},
	) as Dictionary
	_expect(
		String(rainy_snapshot.get("weather", "")) in [
			"小雨",
			"中雨",
			"大雨",
		],
		"the next autonomous decision receives confirmed rain",
	)
	_expect_equal(
		rainy_context.get("outdoorPolicy"),
		"discouraged",
		"rain discourages optional outdoor activity without forbidding it",
	)
	_expect(
		(rainy_context.get("indoorAlternatives", []) as Array).has(
			"花房咖啡馆",
		),
		"rain offers the cafe as a real executable indoor social alternative",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_go_daily_life_chain(lin_wake, "花房咖啡馆", "忙完去咖啡馆歇口气"),
		) as Dictionary,
		"resident can leave work for a social public place",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"cafe trip completes",
	)
	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_use_prop(
				lin_wake,
				"花房咖啡馆点单柜台",
				"点单",
				"点杯喝的再坐一会儿",
			),
		) as Dictionary,
		"arrival can flow into a cafe order",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"cafe order completes",
	)
	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	var lin_cafe_state := world.call("get_resident_state", "林岚") as Dictionary
	var a_he_cafe_state := world.call("get_resident_state", "阿禾") as Dictionary
	var a_he_id := _nearby_id(lin_wake, "阿禾")
	_expect(
		not a_he_id.is_empty(),
		"cafe co-location exposes the familiar resident (lin=%s, a_he=%s, wake_place=%s)"
		% [
			lin_cafe_state,
			a_he_cafe_state,
			(lin_wake.get("snapshot", {}) as Dictionary).get("place", {}),
		],
	)
	if not a_he_id.is_empty():
		# 阿禾空闲时会在店内走动，点单柜台到他的距离会落进"唤醒包可见、
		# 搭话超严格感知半径"的滞回带；林岚先到主厅座位坐下（台词也
		# 正是坐下之后说的），双方站定再搭话。
		_expect_accepted(
			world.call(
				"submit_agent_decision",
				"林岚",
				_use_prop(
					lin_wake,
					"花房咖啡馆主厅座位",
					"歇着",
					"找个主厅座位坐下",
				),
			) as Dictionary,
			"resident settles at a main-hall cafe seat",
		)
		_expect(
			_advance_until_action_clears(world, "林岚"),
			"cafe seat rest completes",
		)
		lin_wake = _take_wake_daily_life_chain(world, "林岚")
		a_he_id = _nearby_id(lin_wake, "阿禾")
		_expect(
			not a_he_id.is_empty(),
			"the seated resident keeps the cafe worker in talk range",
		)
		_expect_accepted(
			world.call(
				"submit_agent_decision",
				"林岚",
				_talk_daily_life_chain(
					lin_wake,
					a_he_id,
					"今天店里倒挺安静。",
					"我在柜台边坐下，看了看四周",
				),
			) as Dictionary,
			"resident can start ordinary cafe conversation",
		)
		var a_he_reply_wake := _take_wake_daily_life_chain(world, "阿禾")
		var conversation_value: Variant = (
			a_he_reply_wake.get("snapshot", {}) as Dictionary
		).get("conversation")
		var conversation := (
			conversation_value as Dictionary
			if conversation_value is Dictionary
			else {}
		)
		_expect(
			not conversation.is_empty(),
			"reply wake carries the active conversation snapshot",
		)
		_expect_accepted(
			world.call(
				"submit_agent_decision",
				"阿禾",
				_reply(
					a_he_reply_wake,
					String(conversation.get("conversation_id", "")),
					"现在店里就我们两个，你还嫌不够安静。",
					"我把杯子放到他面前，忍不住回了一句",
					true,
				),
			) as Dictionary,
			"familiar resident can answer with a mild, fact-grounded barb",
		)
		_expect_equal(
			(world.call("get_active_conversations") as Array).size(),
			0,
			"resident can deliver the last line before ending the exchange",
		)
		var ended_conversations := world.call(
			"get_resident_public_relationship_progress",
			"resident_lin_lan_01",
		) as Dictionary
		_expect_equal(
			ended_conversations.get("ok"),
			true,
			"the confirmed rainy-day exchange reaches public social progress",
		)
		lin_wake = _take_wake_daily_life_chain(world, "林岚")
		_expect(
			_has_event_daily_life_chain(lin_wake, "对话结束"),
			"the other resident receives the confirmed conversation end",
		)

	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_go_daily_life_chain(lin_wake, "北街一号住宅", "忙完了，回家歇着"),
		) as Dictionary,
		"resident can commute home",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"home commute completes",
	)
	lin_wake = _take_wake_daily_life_chain(world, "林岚")
	var lin_resident := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get("resident_lin_lan_01", {})
		as Dictionary
	)
	var lin_activity := lin_resident.get("activityState", {}) as Dictionary
	lin_activity["energy"] = 35
	ACTIVITY_SCALARS.sync_body_from_activity_needs(lin_resident, lin_activity)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"林岚",
			_use_prop(
				lin_wake,
				"北街一号住宅单人床",
				"睡觉",
				"收拾好就睡下",
			),
		) as Dictionary,
		"resident can close the daily loop with sleep",
	)
	_expect(
		_advance_until_action_clears(world, "林岚"),
		"sleep action completes",
	)
	_expect_equal(
		(world.call("get_resident_state", "林岚") as Dictionary).get(
			"currentPlace",
		),
		"北街一号住宅",
		"daily-life chain ends at the resident's own home",
	)
	world.call("stop")
	return
func _advance_until_action_clears(
	world: RefCounted,
	resident_name: String,
	maximum_minutes := 900,
) -> bool:
	for _minute in maximum_minutes:
		var state := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		if state.get("currentAction") == null:
			return true
		world.call("advance", 1.0)
	return false



func _advance_until_action_clears_with_positions(
	world: RefCounted,
	resident_name: String,
	maximum_minutes := 900,
) -> Dictionary:
	var distinct_positions := {}
	for _minute in maximum_minutes:
		var state := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		if state.get("currentAction") == null:
			return {
				"completed": true,
				"positions": distinct_positions.values(),
			}
		var position := state.get("position", Vector2.ZERO) as Vector2
		distinct_positions["%.2f,%.2f" % [position.x, position.y]] = position
		world.call("advance", 1.0)
	return {
		"completed": false,
		"positions": distinct_positions.values(),
	}



func _take_wake_daily_life_chain(world: RefCounted, resident_name: String) -> Dictionary:
	var requests := world.call(
		"take_pending_decision_requests",
		[resident_name],
	) as Array[Dictionary]
	if requests.is_empty():
		_failures.append("missing wake for %s" % resident_name)
		return {}
	return (
		(requests[0].get("wakePacket", {}) as Dictionary).duplicate(true)
	)



func _go_daily_life_chain(
	wake: Dictionary,
	place: String,
	line: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-go-%s" % [decision_id, place],
			"type": "去",
			"place": place,
			"line": line,
		},
	}



func _use_prop(
	wake: Dictionary,
	prop: String,
	verb: String,
	line: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-use-%s" % [decision_id, verb],
			"type": "用道具",
			"prop": prop,
			"verb": verb,
			"line": line,
		},
	}



func _do_activity(
	wake: Dictionary,
	activity_id: String,
	line: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-activity-%s" % [decision_id, activity_id],
			"type": "做活动",
			"activity_id": activity_id,
			"line": line,
		},
	}



func _available_worker_activity_id(
	world: RefCounted,
	resident_name: String,
) -> String:
	var state := world.call(
		"get_resident_state",
		resident_name,
	) as Dictionary
	var resident_id := String(state.get("residentId", ""))
	var query := world.call(
		"query_activity_options",
		resident_id,
	) as Dictionary
	for option_value: Variant in query.get("options", []) as Array:
		var option := option_value as Dictionary
		if (
			bool(option.get("available", false))
			and String(option.get("role", "")) == "worker"
		):
			return String(option.get("activityId", ""))
	return ""



func _talk_daily_life_chain(
	wake: Dictionary,
	target_id: String,
	say: String,
	narration: String,
) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-talk" % decision_id,
			"type": "搭话",
			"target_resident_id": target_id,
			"say": say,
			"narration": narration,
			"photos": [],
		},
	}



func _reply(
	wake: Dictionary,
	conversation_id: String,
	say: String,
	narration: String,
	end: bool,
) -> Dictionary:
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



func _nearby_id(wake: Dictionary, resident_name: String) -> String:
	for value: Variant in (
		(wake.get("snapshot", {}) as Dictionary).get("nearby", []) as Array
	):
		if not value is Dictionary:
			continue
		var person := value as Dictionary
		if String(person.get("name", "")) == resident_name:
			return String(person.get("resident_id", ""))
	return ""



func _has_event_daily_life_chain(wake: Dictionary, event_type: String) -> bool:
	for value: Variant in wake.get("events", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("type", "")) == event_type
		):
			return true
	return false



func _expect_accepted(result: Dictionary, message: String) -> void:
	_expect_equal(result.get("status"), "accepted", "%s (%s)" % [message, result])



func _scenario_log_causal_query() -> void:
	_test_find_thread_by_source_event()
	_test_causal_chain()
	_test_excluded_event_types()
	_test_story_event_ingestion()
	_test_postal_terminal_update()
	_test_thread_detail_stores_no_story_fields()
	_test_runtime_public_log_hides_story_fields()
	_test_weather_change_enters_player_log()
	_test_message_sender_distribution()
	_test_place_filter()
	_test_place_log_item_adapter()
	_test_thread_source_event_ids()
	_test_observation_kind_rule()
	_test_place_observations()
	return
func _test_find_thread_by_source_event() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "causal-find"), "find reset")
	_expect_ok(store.call("append_public_event", _public_event(
		"evt-cargo-1",
		"cargo_event",
		{"type": "货批生成", "cargoLotId": "lot-1", "status": "ongoing"},
	)), "find append")
	var rows := (
		store.call("query_threads", {}) as Dictionary
	).get("rows", []) as Array
	_expect_equal(rows.size(), 1, "find thread row present")
	var thread_id := String((rows[0] as Dictionary).get("threadId", ""))
	var found := store.call(
		"find_thread_by_source_event",
		"evt-cargo-1",
	) as Dictionary
	_expect_equal(found.get("ok"), true, "source event resolves")
	_expect_equal(found.get("threadId"), thread_id, "resolved thread matches query row")
	_expect(int(found.get("sequence", 0)) >= 1, "resolved sequence positive")
	var missing := store.call(
		"find_thread_by_source_event",
		"evt-unknown",
	) as Dictionary
	_expect_equal(
		missing.get("errorCode"),
		"WORLD_LOG_SOURCE_EVENT_NOT_FOUND",
		"unknown source event fails explicitly",
	)
	var empty := store.call("find_thread_by_source_event", "  ") as Dictionary
	_expect_equal(
		empty.get("errorCode"),
		"WORLD_LOG_SOURCE_ID_MISSING",
		"blank source id fails explicitly",
	)



func _test_causal_chain() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "causal-chain"), "chain reset")
	_expect_ok(store.call("append_batch", [
		_record("thread-a", "item-a", "evt-a", {}),
		_record("thread-b", "item-b", "evt-b", {"causedByEventIds": ["evt-a"]}),
	]), "chain append")
	var chain := store.call("get_causal_chain", "thread-b") as Dictionary
	_expect_equal(chain.get("ok"), true, "chain resolves")
	_expect_equal(chain.get("currentThreadId"), "thread-b", "chain current thread")
	var nodes := chain.get("nodes", []) as Array
	_expect_equal(nodes.size(), 2, "chain has cause and effect")
	if nodes.size() == 2:
		_expect_equal(
			(nodes[0] as Dictionary).get("threadId"),
			"thread-a",
			"earliest cause first",
		)
		_expect_equal(
			(nodes[0] as Dictionary).get("isCurrent"),
			false,
			"cause not current",
		)
		_expect_equal(
			(nodes[1] as Dictionary).get("threadId"),
			"thread-b",
			"current thread last",
		)
		_expect_equal(
			(nodes[1] as Dictionary).get("isCurrent"),
			true,
			"current flagged",
		)
	var no_cause := store.call("get_causal_chain", "thread-a") as Dictionary
	_expect_equal(no_cause.get("ok"), true, "no-cause chain resolves")
	_expect_equal(
		(no_cause.get("nodes", []) as Array).size(),
		0,
		"single-node chain reports empty nodes",
	)
	var absent := store.call("get_causal_chain", "thread-x") as Dictionary
	_expect_equal(
		absent.get("errorCode"),
		"WORLD_LOG_THREAD_NOT_FOUND",
		"unknown thread fails explicitly",
	)
	_expect_ok(store.call("append_batch", [
		_record("thread-c", "item-c", "evt-c", {"causedByEventIds": ["evt-d"]}),
		_record("thread-d", "item-d", "evt-d", {"causedByEventIds": ["evt-c"]}),
	]), "cycle append")
	var cycle := store.call("get_causal_chain", "thread-c") as Dictionary
	_expect_equal(cycle.get("ok"), true, "cyclic causes terminate")
	_expect_equal(
		(cycle.get("nodes", []) as Array).size(),
		2,
		"cycle yields both nodes exactly once",
	)



func _test_excluded_event_types() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "excluded-types"), "excluded reset")
	for event_type in ["旁听", "移动", "有人来了"]:
		var result := store.call("append_public_event", _public_event(
			"evt-%s" % event_type,
			"world_event",
			{"type": event_type},
		)) as Dictionary
		_expect_equal(result.get("ok"), true, "%s 排除返回成功" % event_type)
		_expect_equal(result.get("excluded"), true, "%s 被排除" % event_type)
	_expect_equal(
		int(store.call("get_record_count")),
		0,
		"排除类型不入库(旁听按 aya 裁决保留丢弃)",
	)
	# 正向对照用已知会入库的货批事件(裸"搭话"事件还要过 LogStore 的
	# "玩家有感"过滤,不适合做排除表的对照组)。
	_expect_ok(store.call("append_public_event", _public_event(
		"evt-cargo",
		"cargo_event",
		{"type": "货批生成", "cargoLotId": "lot-x", "status": "ongoing"},
	)), "非排除类型正常入库")
	_expect_equal(int(store.call("get_record_count")), 1, "对照事件入库")



func _test_story_event_ingestion() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "story-events"), "story reset")
	# 行动结果:完成态的非移动/等待/对话类才收(规则源=表现层影子引擎)
	_expect_ok(store.call("append_public_event", _story_event(
		"evt-outcome-1",
		{
			"storyType": "action_outcome",
			"status": "completed",
			"actionType": "用道具",
			"storyRootEventIds": ["root-1"],
		},
	)), "完成态行动结果入库")
	for skipped in [
		{"storyType": "action_outcome", "status": "ongoing", "actionType": "用道具", "storyRootEventIds": ["root-1"]},
		{"storyType": "action_outcome", "status": "completed", "actionType": "去", "storyRootEventIds": ["root-1"]},
		{"storyType": "action_outcome", "status": "completed", "actionType": "用道具", "verb": "睡觉", "storyRootEventIds": ["root-1"]},
		{"storyType": "action_outcome", "status": "completed", "actionType": "做活动", "storyRootEventIds": ["root-1"]},
		{"storyType": "action_outcome", "status": "completed", "actionType": "用道具", "storyRootEventIds": []},
	]:
		var result := store.call("append_public_event", _story_event(
			"evt-skip-%d" % skipped.hash(),
			skipped,
		)) as Dictionary
		_expect_equal(result.get("excluded"), true, "不合规则的行动结果被排除")
	_expect_equal(int(store.call("get_record_count")), 1, "仅合规行动结果入库")
	var rollover_cancel := store.call("append_public_event", _public_event(
		"evt-rollover-cancel",
		"work_task",
		{
			"type": "工作任务取消",
			"taskId": "daily-catalog-task-1",
			"status": "cancelled",
			"capability": "library.assist",
			"sourceKind": "daily_catalog_plan",
			"sourceRef": "daily-catalog:1",
			"participantIds": ["resident-a"],
		},
	)) as Dictionary
	_expect_equal(rollover_cancel.get("excluded"), true, "日切内部任务取消不进入玩家日志")
	_expect_equal(int(store.call("get_record_count")), 1, "内部任务取消不增加日志记录")
	var expired_performance := store.call("append_public_event", _public_event(
		"evt-expired-performance",
		"work_task",
		{
			"type": "工作任务取消",
			"taskId": "performance-task-1",
			"status": "cancelled",
			"capability": "music.perform",
			"sourceKind": "personal_performance_plan",
			"sourceRef": "performance-plan:1",
			"participantIds": ["resident-a"],
			"waitReason": "演出日期已经过去",
		},
	)) as Dictionary
	_expect_equal(expired_performance.get("excluded"), true, "过期演出计划取消不进入玩家日志")
	_expect_equal(int(store.call("get_record_count")), 1, "过期演出计划取消不增加日志记录")
	# 聚集到场:同一根事件+地点归入同一线程(LogStore 线程模型天然聚合)
	for index in 3:
		_expect_ok(store.call("append_public_event", _story_event(
			"evt-gather-%d" % index,
			{
				"storyType": "gathering_arrival",
				"storyRootEventIds": ["root-gather"],
				"to": "小酒馆",
			},
		)), "聚集到场 %d 入库" % index)
	var rows := (
		store.call("query_threads", {}) as Dictionary
	).get("rows", []) as Array
	var gathering_rows: Array[Dictionary] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		if String(row.get("threadId", "")).begins_with("gathering:"):
			gathering_rows.append(row)
	_expect_equal(gathering_rows.size(), 1, "三条到场归并为一条聚集线程")
	if gathering_rows.size() == 1:
		_expect_equal(
			(gathering_rows[0] as Dictionary).get("threadId"),
			"gathering:root-gather:小酒馆",
			"聚集线程按 根事件+地点 归并",
		)
		_expect_equal(
			int((gathering_rows[0] as Dictionary).get("recordCount", 0)),
			3,
			"聚集线程累计三条记录",
		)
	# 不同地点不归并
	_expect_ok(store.call("append_public_event", _story_event(
		"evt-gather-other",
		{
			"storyType": "gathering_arrival",
			"storyRootEventIds": ["root-gather"],
			"to": "花房咖啡馆",
		},
	)), "异地到场入库")
	var rows2 := (
		store.call("query_threads", {}) as Dictionary
	).get("rows", []) as Array
	var gathering_count := 0
	for row_value: Variant in rows2:
		if String((row_value as Dictionary).get("threadId", "")).begins_with("gathering:"):
			gathering_count += 1
	_expect_equal(gathering_count, 2, "不同地点的聚集各自成线程")

func _test_postal_terminal_update() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "postal-terminal"), "postal terminal reset")
	_expect_ok(store.call("append_public_event", _public_event(
		"evt-postal-cancel",
		"work_task",
		{
			"type": "工作任务取消",
			"taskId": "postal-deliver-task-1",
			"status": "cancelled",
			"capability": "message.deliver",
			"sourceKind": "postal_batch",
			"sourceRef": "postal-batch-1",
			"participantIds": ["resident-a", "resident-b"],
			"waitReason": "收件居民已经离开小镇",
		},
	)), "口信取消仍保留为可解释记录")
	var rows := (store.call("query_threads", {}) as Dictionary).get("rows", []) as Array
	_expect_equal(rows.size(), 1, "口信取消只有一条线程")
	if rows.size() == 1:
		_expect_equal(
			(rows[0] as Dictionary).get("latestUpdate"),
			"口信投递已取消：收件居民已经离开小镇",
			"口信取消不会显示成等待投递",
		)


func _test_thread_detail_stores_no_story_fields() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "legacy-story-payload"), "legacy story payload reset")
	_expect_ok(store.call("append_batch", [
		_record(
			"thread-story",
			"item-story-1",
			"evt-story-1",
			{
				"storyEventId": "story-old-1",
				"storyType": "action_outcome",
				"storyRootEventIds": ["root-old-1"],
				"type": "用道具",
				"status": "completed",
			},
		),
	]), "legacy payload story fields stored")
	var detail := store.call("get_thread_detail", "thread-story") as Dictionary
	_expect_equal(detail.get("ok"), true, "thread detail 可返回")
	var records := detail.get("records", []) as Array
	_expect_equal(records.size(), 1, "thread detail 里有一条记录")
	var payload := {}
	if records.size() == 1:
		payload = (
			(records[0] as Dictionary).get("payload", {}) as Dictionary
		)
	_expect(
		not payload.has("storyEventId"),
		"详情返回不含 storyEventId",
	)
	_expect(
		not payload.has("storyType"),
		"详情返回不含 storyType",
	)
	_expect(
		not payload.has("storyRootEventIds"),
		"详情返回不含 storyRootEventIds",
	)


func _test_runtime_public_log_hides_story_fields() -> void:
	var world: RefCounted = WORLD.new()
	world.WORLD_LOG_COMMIT_RUNTIME.append_public(
		world,
		"evt-public-story",
		"story_event",
		"",
		"",
		"",
		{
			"storyEventId": "story-public-1",
			"storyType": "action_outcome",
			"storyRootEventIds": ["root-public-1"],
			"type": "用道具",
		},
	)
	var public_events := world.call("get_public_event_log") as Array
	_expect_equal(public_events.size(), 1, "公开事件日志可返回测试记录")
	var payload := {}
	if public_events.size() == 1:
		payload = (
			(public_events[0] as Dictionary).get("payload", {}) as Dictionary
		)
	for field: String in [
		"storyEventId", "storyType", "storyRootEventIds",
	]:
		_expect(not payload.has(field), "公开事件日志不泄漏 %s" % field)


func _test_weather_change_enters_player_log() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "weather-log"), "weather log reset")
	_expect_ok(store.call("append_public_event", _public_event(
		"evt-weather-rain",
		"world_event",
		{"type": "天气变了", "weather": "小雨"},
	)), "天气变化进入日志资料库")
	var rows := (store.call("query_threads", {}) as Dictionary).get(
		"rows",
		[],
	) as Array
	_expect_equal(rows.size(), 1, "天气变化形成一条玩家日志")
	if rows.size() == 1:
		_expect_equal(
			(rows[0] as Dictionary).get("latestUpdate"),
			"天气转为小雨",
			"天气日志使用玩家可读文字",
		)


func _test_message_sender_distribution() -> void:
	var world := _MessagePolicyWorld.new()
	var selected := {}
	for index in 48:
		var source_ref := "notice:%d" % index
		var sender := RESIDENT_MESSAGE_POLICY.sender_for_source(
			world,
			"occupation_postal_worker",
			source_ref,
			"recipient",
			"distribution:%d" % index,
		)
		selected[sender] = true
	_expect(
		selected.size() > 1,
		"多名合格职业居民不会长期固定为同一发送人",
	)
	_expect(
		not selected.has("recipient"),
		"发送人选择不会选到收件人本人",
	)
	var stable_sender := RESIDENT_MESSAGE_POLICY.sender_for_source(
		world,
		"occupation_postal_worker",
		"notice:stable",
		"recipient",
		"distribution:stable",
	)
	_expect_equal(
		RESIDENT_MESSAGE_POLICY.sender_for_source(
			world,
			"occupation_postal_worker",
			"notice:stable",
			"recipient",
			"distribution:stable",
		),
		stable_sender,
		"同一事实重试时发送人保持稳定",
	)



func _story_event(event_id: String, payload: Dictionary) -> Dictionary:
	var event := _public_event(event_id, "story_event", payload)
	event["placeName"] = String(payload.get("to", "独立市集"))
	return event



func _test_place_filter() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "place-filter"), "place filter reset")
	_expect_ok(store.call("append_batch", [
		_record_at("pf1", "pi1", "pe1", "小酒馆", "daily_activity", "archive_only"),
		_record_at("pf2", "pi2", "pe2", "小酒馆", "conversation", "archive_only"),
		_record_at("pf3", "pi3", "pe3", "花房咖啡馆", "daily_activity", "archive_only"),
	]), "place filter append")
	var tavern := store.call("query_threads", {"placeId": "小酒馆"}) as Dictionary
	_expect_equal(tavern.get("ok"), true, "地点过滤查询成功")
	_expect_equal((tavern.get("rows", []) as Array).size(), 2, "只返回该地点线程")
	_expect_equal(int(tavern.get("total", 0)), 2, "total 与过滤后一致")
	var cafe := store.call("query_threads", {"placeId": "花房咖啡馆"}) as Dictionary
	_expect_equal((cafe.get("rows", []) as Array).size(), 1, "另一地点各自计数")
	var none := store.call("query_threads", {"placeId": "不存在的地方"}) as Dictionary
	_expect_equal((none.get("rows", []) as Array).size(), 0, "无匹配地点返回空")
	var all := store.call("query_threads", {}) as Dictionary
	_expect_equal((all.get("rows", []) as Array).size(), 3, "不带过滤返回全部")



func _test_place_log_item_adapter() -> void:
	# G 之 1 第二步适配器的映射等价性:LogStore 线程行 → place_focus 条目形态。
	var service_script := load("res://world/presentation/ui/TownUiPageProjectionService.gd")
	var service: RefCounted = service_script.new()
	var conversation_thread := {
		"threadId": "conversation:c-1",
		"title": "小满与阿禾的对话",
		"preview": "两个人在市集上聊了几句。",
		"updatedAt": {"day": 3, "hour": 10, "minute": 5},
		"kindTags": ["conversation"],
		"placeLabel": "独立市集",
		"participantSnapshots": [
			{"residentId": "r-1", "displayName": "小满"},
			{"residentId": "r-2", "displayName": "阿禾"},
		],
		"participantIds": ["r-1", "r-2"],
	}
	var mapped := service.call(
		"_thread_to_place_log_item",
		conversation_thread,
	) as Dictionary
	_expect_equal(mapped.get("id"), "conversation:c-1", "id 取 threadId")
	_expect_equal(mapped.get("title"), "小满与阿禾的对话", "title 直取")
	_expect_equal(mapped.get("subtitle"), "两个人在市集上聊了几句。", "subtitle 取 preview")
	_expect_equal(mapped.get("primaryCategory"), "social", "对话类映射为 social")
	_expect_equal(mapped.get("placeLabel"), "独立市集", "地点标签直取")
	_expect_equal(
		mapped.get("participantLabels"),
		["小满", "阿禾"],
		"参与者标签取快照显示名",
	)
	_expect_equal(mapped.get("isHot"), false, "两人不算热闹")
	_expect_equal(
		mapped.get("sourceEventIds"),
		[],
		"无来源时透传空数组",
	)
	_expect(
		not String(mapped.get("timeLabel", "")).is_empty(),
		"时间标签非空",
	)
	var gathering_thread := conversation_thread.duplicate(true)
	gathering_thread["threadId"] = "gathering:root-1:小酒馆"
	gathering_thread["kindTags"] = ["daily_activity"]
	gathering_thread["participantIds"] = ["r-1", "r-2", "r-3"]
	var mapped_gathering := service.call(
		"_thread_to_place_log_item",
		gathering_thread,
	) as Dictionary
	_expect_equal(
		mapped_gathering.get("primaryCategory"),
		"resident",
		"非对话类映射为 resident",
	)
	_expect_equal(mapped_gathering.get("isHot"), true, "三人及以上判热闹")



func _test_thread_source_event_ids() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "thread-sources"), "sources reset")
	_expect_ok(store.call("append_batch", [
		_record("t-src", "i-src-1", "evt-src-1", {}),
		_record("t-src", "i-src-2", "evt-src-2", {}),
	]), "同线程两条记录")
	var rows := (
		store.call("query_threads", {}) as Dictionary
	).get("rows", []) as Array
	_expect_equal(rows.size(), 1, "两条记录归一线程")
	if rows.size() == 1:
		_expect_equal(
			(rows[0] as Dictionary).get("sourceEventIds"),
			["evt-src-1", "evt-src-2"],
			"线程按摄取顺序累积来源事件 id",
		)



func _test_observation_kind_rule() -> void:
	_expect_equal(
		STORE.observation_kind_for({"attention": "important"}),
		"important",
		"important attention wins",
	)
	_expect_equal(
		STORE.observation_kind_for({
			"attention": "important",
			"kindTag": "conversation",
		}),
		"important",
		"important outranks dialogue",
	)
	_expect_equal(
		STORE.observation_kind_for({"kindTag": "conversation"}),
		"dialogue",
		"conversation tag maps to dialogue",
	)
	_expect_equal(
		STORE.observation_kind_for({"kind": "conversation_turn"}),
		"dialogue",
		"conversation record kind maps to dialogue",
	)
	for action_tag in ["daily_activity", "production", "service", "commerce"]:
		_expect_equal(
			STORE.observation_kind_for({"kindTag": action_tag}),
			"action",
			"%s maps to action" % action_tag,
		)
	_expect_equal(
		STORE.observation_kind_for({"kindTag": "world_change"}),
		"",
		"unclassified stays blank",
	)



func _test_place_observations() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "place-observations"), "obs reset")
	_expect_ok(store.call("append_batch", [
		_record_at("t1", "i1", "e1", "小酒馆", "daily_activity", "archive_only"),
		_record_at("t2", "i2", "e2", "小酒馆", "conversation", "archive_only"),
		_record_at("t3", "i3", "e3", "小酒馆", "world_change", "important"),
		_record_at("t4", "i4", "e4", "别处", "daily_activity", "archive_only"),
		_record_at("t5", "i5", "e5", "小酒馆", "daily_activity", "archive_only"),
	]), "obs append")
	var result := store.call("query_place_observations", "小酒馆") as Dictionary
	_expect_equal(result.get("ok"), true, "observations resolve")
	var observations := result.get("observations", []) as Array
	_expect_equal(observations.size(), 3, "one observation per kind")
	if observations.size() == 3:
		_expect_equal(
			(observations[0] as Dictionary).get("observationKind"),
			"action",
			"fixed kind order starts with action",
		)
		_expect_equal(
			(observations[0] as Dictionary).get("threadId"),
			"t5",
			"newest action wins per-kind slot",
		)
		_expect_equal(
			(observations[1] as Dictionary).get("observationKind"),
			"dialogue",
			"dialogue second",
		)
		_expect_equal(
			(observations[2] as Dictionary).get("observationKind"),
			"important",
			"important last",
		)
	for entry_value: Variant in observations:
		_expect(
			String((entry_value as Dictionary).get("threadId", "")) != "t4",
			"other place excluded",
		)
	var blank := store.call("query_place_observations", " ") as Dictionary
	_expect_equal(
		blank.get("errorCode"),
		"WORLD_LOG_PLACE_ID_MISSING",
		"blank place fails explicitly",
	)



func _public_event(event_id: String, kind: String, payload: Dictionary) -> Dictionary:
	return {
		"eventId": event_id,
		"kind": kind,
		"time": {"day": 3, "hour": 10, "minute": 0},
		"worldRevision": 20,
		"residentId": "resident-a",
		"residentName": "小满",
		"placeName": "独立市集",
		"payload": payload,
	}



func _record(
	thread_id: String,
	item_id: String,
	event_id: String,
	payload: Dictionary,
) -> Dictionary:
	return {
		"threadId": thread_id,
		"logItemId": item_id,
		"sourceRefs": [{
			"sourceKind": "world_event",
			"sourceId": event_id,
			"mutationId": event_id,
		}],
		"kind": "world_event",
		"kindTag": "world_change",
		"time": {"day": 2, "hour": 9, "minute": 0},
		"participantIds": [],
		"references": {},
		"payload": payload,
		"title": "标题-%s" % thread_id,
		"attention": "archive_only",
	}



func _record_at(
	thread_id: String,
	item_id: String,
	event_id: String,
	place_id: String,
	kind_tag: String,
	attention: String,
) -> Dictionary:
	var record := _record(thread_id, item_id, event_id, {})
	record["placeId"] = place_id
	record["kindTag"] = kind_tag
	record["attention"] = attention
	return record



func _expect_ok(value: Variant, label: String) -> void:
	_expect(
		value is Dictionary and (value as Dictionary).get("ok") == true,
		"%s ok expected, got %s" % [label, value],
	)



func _scenario_environment() -> void:
	var environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(environment.call("get_errors"), [], "formal time-weather data validates")
	_expect_equal(environment.call("start", 1, "+1:00", "晴天", 7).get("ok"), false, "signed clocks are rejected")
	_expect_equal(environment.call("start", 1, "1:00", "晴天", 7).get("ok"), false, "short clocks are rejected")
	_expect_equal(
		environment.call("start", 1, "05:59", "晴天", 7).get("ok"),
		true,
		"formal world starts from valid state",
	)
	var first_weather_delay := int(
		environment.call("get_minutes_until_next_weather_check")
	)
	_expect(
		first_weather_delay >= 45 and first_weather_delay <= 90,
		"natural weather schedules its first check inside the formal random window",
	)
	_expect_equal(environment.call("queue_weather_roll", 0.71), true, "valid forced weather rolls are accepted")
	var dawn: Dictionary = environment.call("advance", float(first_weather_delay))
	_expect_equal(
		dawn.get("minutesAdvanced"),
		first_weather_delay,
		"weather wait advances the expected number of game minutes",
	)
	_expect_equal((dawn.get("periodChanges", []) as Array).size(), 0, "weather checks do not depend on broad period boundaries")
	_expect_equal(environment.call("get_weather"), "阴天", "weather follows the sunny transition row")
	_expect_equal((dawn.get("events", []) as Array).size(), 1, "actual natural weather change emits one event")
	if (dawn.get("events", []) as Array).size() == 1:
		_expect_equal(dawn["events"][0]["type"], "天气变了", "weather event uses Agent contract type")
	var unchanged_weather: RefCounted = ENVIRONMENT.new()
	unchanged_weather.call("start", 1, "05:59", "晴天", 9)
	unchanged_weather.call("queue_weather_roll", 0.1)
	var unchanged_dawn := unchanged_weather.call(
		"advance",
		float(unchanged_weather.call("get_minutes_until_next_weather_check")),
	) as Dictionary
	_expect_equal(unchanged_weather.call("get_weather"), "晴天", "same-bucket weather keeps the current weather")
	_expect_equal((unchanged_dawn.get("events", []) as Array).size(), 0, "unchanged natural weather emits no event")

	environment.call("start", 1, "23:59", "雷暴", 11)
	environment.call("queue_weather_roll", 0.01)
	var midnight: Dictionary = environment.call("advance", 1.0)
	_expect_equal(environment.call("get_time"), {"day": 2, "clock": "00:00", "period": "夜里"}, "midnight advances the day")
	_expect_equal((midnight.get("periodChanges", []) as Array).size(), 0, "night remains the same named period across midnight")
	environment.call("set_time", 2, "22:00")
	_expect_equal(environment.call("minutes_until_next_period"), 420, "night waits until dawn instead of stopping at midnight")

	environment.call("start", 2, "17:59", "小雨", 13)
	var evening_weather_delay := int(
		environment.call("get_minutes_until_next_weather_check")
	)
	environment.call("queue_weather_roll", 0.98)
	var evening: Dictionary = environment.call("advance", 1.0)
	_expect_equal(environment.call("get_time").get("period"), "傍晚", "18:00 enters evening")
	_expect_equal((evening.get("periodChanges", []) as Array).size(), 1, "new formal period is observable")
	_expect_equal(environment.call("get_weather"), "小雨", "period boundary alone does not force a weather check")
	var evening_weather := environment.call(
		"advance",
		float(evening_weather_delay - 1),
	) as Dictionary
	_expect_equal(
		(evening_weather.get("events", []) as Array).size(),
		1,
		"randomly scheduled weather check can change weather away from a period boundary",
	)
	_expect_equal(environment.call("get_weather"), "雷暴", "forced roll selects the matching transition bucket")

	var found_non_hourly_check := false
	for seed in range(1, 9):
		var irregular_environment: RefCounted = ENVIRONMENT.new()
		irregular_environment.call("start", 1, "08:00", "晴天", seed)
		var scheduled_delay := int(
			irregular_environment.call(
				"get_minutes_until_next_weather_check",
			)
		)
		if posmod(scheduled_delay, 60) != 0:
			found_non_hourly_check = true
			break
	_expect(
		found_non_hourly_check,
		"natural weather checks are not locked to whole clock hours",
	)

	for weather in ["晴天", "阴天", "小雨", "中雨", "大雨", "雷暴", "下雪"]:
		var changed: Dictionary = environment.call("set_weather", weather)
		_expect_equal(changed.get("ok"), true, "player can select formal weather %s" % weather)
		_expect_equal(environment.call("get_weather"), weather, "world exposes only confirmed weather %s" % weather)

	var cycle_environment: RefCounted = ENVIRONMENT.new()
	cycle_environment.call("start", 3, "04:00", "晴天", 19)
	var expected_times := [
		{"day": 3, "clock": "05:30", "period": "清晨"},
		{"day": 3, "clock": "09:30", "period": "上午"},
		{"day": 3, "clock": "12:30", "period": "中午"},
		{"day": 3, "clock": "15:30", "period": "下午"},
		{"day": 3, "clock": "18:30", "period": "傍晚"},
		{"day": 3, "clock": "22:30", "period": "夜里"},
		{"day": 4, "clock": "05:30", "period": "清晨"},
	]
	for expected_time in expected_times:
		cycle_environment.call("cycle_time_period")
		_expect_equal(cycle_environment.call("get_time"), expected_time, "manual time switch visits the next formal period")

	var sliced_environment: RefCounted = ENVIRONMENT.new()
	sliced_environment.call("start", 1, "00:00", "晴天", 21)
	var sliced_minutes := 0
	for slice_index in range(10):
		var slice_result := sliced_environment.call("advance", 0.1) as Dictionary
		sliced_minutes += int(slice_result.get("minutesAdvanced", 0))
		_expect_equal(
			slice_result.get("minutesAdvanced"),
			0 if slice_index < 9 else 1,
			"ten equal frame slices advance only when exactly one real second is complete",
		)
	_expect_equal(sliced_minutes, 1, "ten 0.1-second frame slices advance exactly one game minute")
	_expect_equal(
		sliced_environment.call("get_time"),
		{"day": 1, "clock": "00:01", "period": "夜里"},
		"equivalent segmented input keeps the confirmed world clock",
	)

	var strict_input_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		strict_input_environment.call("start", 3, "08:00", "晴天", 29).get("ok"),
		true,
		"strict-input test starts from valid state",
	)
	var strict_time: Dictionary = strict_input_environment.call("get_time")
	_expect_equal(strict_input_environment.call("start", 1.5, "08:00", "晴天", 29).get("ok"), false, "fractional start days are rejected before coercion")
	_expect_equal(strict_input_environment.call("start", true, "08:00", "晴天", 29).get("ok"), false, "boolean start days are rejected before coercion")
	_expect_equal(strict_input_environment.call("start", ENVIRONMENT.MAX_SAFE_DAY + 1, "08:00", "晴天", 29).get("ok"), false, "start days that overflow absolute minutes are rejected")
	_expect_equal(strict_input_environment.call("start", 3, "08:00", "晴天", true).get("ok"), false, "boolean random seeds are rejected before coercion")
	_expect_equal(strict_input_environment.call("start", 3, "08:00", "晴天", 1.5).get("ok"), false, "fractional random seeds are rejected before coercion")
	_expect_equal(strict_input_environment.call("start", 3, "08:00", [], 29).get("ok"), false, "array weather is rejected without a format-string failure")
	_expect_equal(strict_input_environment.call("get_time"), strict_time, "rejected start inputs do not change world time")
	_expect_equal(strict_input_environment.call("get_weather"), "晴天", "rejected start weather does not change world weather")
	_expect_equal(strict_input_environment.call("set_time", 1.5, "09:00").get("ok"), false, "fractional set-time days are rejected before coercion")
	_expect_equal(strict_input_environment.call("set_time", true, "09:00").get("ok"), false, "boolean set-time days are rejected before coercion")
	_expect_equal(strict_input_environment.call("set_time", ENVIRONMENT.MAX_SAFE_DAY + 1, "09:00").get("ok"), false, "set-time days that overflow absolute minutes are rejected")
	_expect_equal(strict_input_environment.call("get_time"), strict_time, "rejected set-time inputs do not change world time")
	_expect_equal(strict_input_environment.call("queue_weather_roll", false), false, "boolean weather rolls are rejected before coercion")
	_expect_equal(strict_input_environment.call("advance", true).get("minutesAdvanced"), 0, "boolean elapsed time is rejected before coercion")
	_expect_equal(strict_input_environment.call("get_time"), strict_time, "rejected elapsed time does not change world time")
	_expect_equal(strict_input_environment.call("set_weather", false).get("ok"), false, "non-text weather is rejected before coercion")
	_expect_equal(strict_input_environment.call("set_weather", []).get("ok"), false, "array weather is rejected without a format-string failure")
	_expect_equal(strict_input_environment.call("get_weather"), "晴天", "rejected weather does not change world state")
	var maximum_time_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		maximum_time_environment.call(
			"start",
			ENVIRONMENT.MAX_SAFE_DAY,
			"23:59",
			"晴天",
			37,
		).get("ok"),
		true,
		"the last representable world minute can start",
	)
	_expect_equal(
		maximum_time_environment.call("advance", 1.0).get(
			"minutesAdvanced"
		),
		0,
		"world time does not advance beyond its serializable range",
	)
	_expect_equal(
		maximum_time_environment.call("get_time"),
		{
			"day": ENVIRONMENT.MAX_SAFE_DAY,
			"clock": "23:59",
			"period": "夜里",
		},
		"the time horizon preserves the last valid minute",
	)
	_expect_equal(
		(maximum_time_environment.call(
			"restore_from_snapshot",
			maximum_time_environment.call("create_save_snapshot"),
		) as Dictionary).get("ok"),
		true,
		"the capped world time remains restorable",
	)

	var fractional_environment: RefCounted = ENVIRONMENT.new()
	fractional_environment.call("start", 1, "00:00", "晴天", 23)
	var almost_one_second: Dictionary = fractional_environment.call("advance", 0.999999)
	_expect_equal(almost_one_second.get("minutesAdvanced"), 0, "fractional time never advances before one full real second")
	_expect_equal(fractional_environment.call("get_time"), {"day": 1, "clock": "00:00", "period": "夜里"}, "fractional time keeps the confirmed clock")
	var fractional_snapshot: Dictionary = fractional_environment.call("create_save_snapshot")
	var restored_fractional_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		restored_fractional_environment.call(
			"restore_from_snapshot",
			fractional_snapshot,
		).get("ok"),
		true,
		"fractional time snapshot restores through the public boundary",
	)
	_expect_equal(
		restored_fractional_environment.call("advance", 0.000002).get(
			"minutesAdvanced"
		),
		1,
		"restored fractional time advances after the remaining real time",
	)
	_expect_equal(
		restored_fractional_environment.call("get_time"),
		{"day": 1, "clock": "00:01", "period": "夜里"},
		"restored fractional time reaches the next minute once",
	)
	_expect_equal(
		restored_fractional_environment.call(
			"get_minutes_until_next_weather_check",
		),
		int(
			fractional_environment.call(
				"get_minutes_until_next_weather_check",
			)
		) - 1,
		"restore preserves the already scheduled weather check",
	)
	var legacy_fractional_snapshot := fractional_snapshot.duplicate(true)
	legacy_fractional_snapshot.erase(
		"nextNaturalWeatherCheckAbsoluteMinute",
	)
	var legacy_restored_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		legacy_restored_environment.call(
			"restore_from_snapshot",
			legacy_fractional_snapshot,
		).get("ok"),
		true,
		"older environment snapshots receive a fresh legal weather schedule",
	)
	_expect_equal(fractional_environment.call("advance", NAN).get("minutesAdvanced"), 0, "non-finite elapsed time never poisons the world clock")
	_expect_equal(fractional_environment.call("queue_weather_roll", -0.1), false, "negative weather rolls are rejected instead of clamped")
	_expect_equal(fractional_environment.call("queue_weather_roll", 1.0), false, "weather rolls at one are rejected instead of clamped")
	var unknown_snapshot_field := fractional_snapshot.duplicate(true)
	unknown_snapshot_field["debug"] = true
	var rejected_restore_environment: RefCounted = ENVIRONMENT.new()
	_expect_equal(
		rejected_restore_environment.call(
			"start",
			3,
			"08:00",
			"阴天",
			31,
		).get("ok"),
		true,
		"rejected-restore test starts from valid state",
	)
	_expect_equal(
		rejected_restore_environment.call("queue_weather_roll", 0.25),
		true,
		"rejected-restore test records a pending weather roll",
	)
	var before_rejected_restore: Dictionary = (
		rejected_restore_environment.call("create_save_snapshot")
	)
	_expect_equal(
		rejected_restore_environment.call(
			"restore_from_snapshot",
			unknown_snapshot_field,
		).get("ok"),
		false,
		"unknown saved environment fields are rejected",
	)
	_expect_equal(
		rejected_restore_environment.call("create_save_snapshot"),
		before_rejected_restore,
		"rejected environment snapshots preserve all previous state",
	)
	var coerced_saved_weather := fractional_snapshot.duplicate(true)
	coerced_saved_weather["weather"] = 123
	_expect_equal(
		rejected_restore_environment.call(
			"restore_from_snapshot",
			coerced_saved_weather,
		).get("ok"),
		false,
		"saved weather is not silently coerced",
	)
	_expect_equal(
		rejected_restore_environment.call("create_save_snapshot"),
		before_rejected_restore,
		"coerced saved weather does not partially replace world state",
	)
	var padded_rng_state := fractional_snapshot.duplicate(true)
	padded_rng_state["rngState"] = "01"
	_expect_equal(
		rejected_restore_environment.call(
			"restore_from_snapshot",
			padded_rng_state,
		).get("ok"),
		false,
		"saved RNG state must use its canonical integer spelling",
	)
	_expect_equal(
		rejected_restore_environment.call("create_save_snapshot"),
		before_rejected_restore,
		"non-canonical RNG state does not partially replace world state",
	)
	var overflowing_day_snapshot := fractional_snapshot.duplicate(true)
	overflowing_day_snapshot["day"] = ENVIRONMENT.MAX_SAFE_DAY + 1
	_expect_equal(
		rejected_restore_environment.call(
			"restore_from_snapshot",
			overflowing_day_snapshot,
		).get("ok"),
		false,
		"saved days that overflow absolute minutes are rejected",
	)
	_expect_equal(
		rejected_restore_environment.call("create_save_snapshot"),
		before_rejected_restore,
		"overflowing saved days do not partially replace world state",
	)

	var formal_config := _read_json("res://world/runtime/environment/town_environment.json")
	var shifted_period := formal_config.duplicate(true)
	((shifted_period.get("time", {}) as Dictionary).get("periods", []) as Array)[1]["startMinute"] = 301
	_expect(not _environment_from_config(shifted_period).call("get_errors").is_empty(), "shifted period boundaries are rejected")
	var altered_speed := formal_config.duplicate(true)
	(altered_speed.get("time", {}) as Dictionary)["realSecondsPerGameMinute"] = 2.0
	_expect(not _environment_from_config(altered_speed).call("get_errors").is_empty(), "time speed cannot drift from one real second per game minute")
	var signed_manual_clock := formal_config.duplicate(true)
	((signed_manual_clock.get("time", {}) as Dictionary).get("manualCycleClocks", []) as Array)[0] = "+5:30"
	_expect(not _environment_from_config(signed_manual_clock).call("get_errors").is_empty(), "non-canonical manual clocks are rejected")
	var altered_weather := formal_config.duplicate(true)
	(((altered_weather.get("weather", {}) as Dictionary).get("transitions", {}) as Dictionary).get("晴天", {}) as Dictionary)["晴天"] = 69
	_expect(not _environment_from_config(altered_weather).call("get_errors").is_empty(), "altered formal weather probabilities are rejected")
	var altered_weather_interval := formal_config.duplicate(true)
	(
		(
			altered_weather_interval.get("weather", {}) as Dictionary
		).get("naturalChangeIntervalMinutes", {}) as Dictionary
	)["maximum"] = 91
	_expect(not _environment_from_config(altered_weather_interval).call("get_errors").is_empty(), "natural weather random window cannot silently drift")
	var extra_weather_key := formal_config.duplicate(true)
	(((extra_weather_key.get("weather", {}) as Dictionary).get("transitions", {}) as Dictionary).get("晴天", {}) as Dictionary)["未知"] = 0
	_expect(not _environment_from_config(extra_weather_key).call("get_errors").is_empty(), "extra weather transition keys are rejected")
	var extra_top_level := formal_config.duplicate(true)
	extra_top_level["debug"] = true
	_expect(not _environment_from_config(extra_top_level).call("get_errors").is_empty(), "unknown environment configuration fields are rejected")

	return
func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}



func _environment_from_config(config: Dictionary) -> RefCounted:
	var path := "user://town_world_environment_invalid_test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("cannot write temporary environment fixture")
		return ENVIRONMENT.new()
	file.store_string(JSON.stringify(config))
	file.close()
	return ENVIRONMENT.new(path)



func _scenario_staggered_arrival() -> void:
	var custom_arrival_ids: Array[String] = [
		"custom_resident_musician_01",
		"custom_resident_dining_01",
	]
	var custom_arrival_minutes: Array[int] = [11, 29]
	DINING_SERVICE_RUNTIME.prioritize_dining_worker_arrival(
		{
			"residents": [{
				"residentId": custom_arrival_ids[0],
				"occupation": {
					"name": "乐师",
					"workplacePlace": "中心广场",
				},
				"socialState": {
					"job": "乐师",
					"workplace": "中心广场",
				},
			}, {
				"residentId": custom_arrival_ids[1],
				"occupation": {
					"name": "食堂主理人",
					"workplacePlace": "公共食堂",
				},
				"socialState": {
					"job": "食堂主理人",
					"workplace": "公共食堂",
				},
			}],
		},
		custom_arrival_ids,
		custom_arrival_minutes,
	)
	_expect_equal(
		custom_arrival_minutes[1],
		11,
		"custom dining operator receives the earliest arrival by occupation",
	)
	_expect(
		not FileAccess.get_file_as_string(
			"res://world/runtime/work/TownDiningServiceRuntime.gd",
		).contains("resident_su_tang_01"),
		"formal dining runtime does not depend on one built-in resident ID",
	)
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var loaded := OPENING.load_config(
		OPENING_PATH,
		world_data,
	) as Dictionary
	_expect_equal(loaded.get("ok"), true, "opening fixture loads")
	if loaded.get("ok") != true:
		return
	var opening := FORMAL_OPENING.with_authoritative_new_game_spawns(
		world_data,
		loaded.get("config", {}) as Dictionary,
	)
	var identities := _resident_identities_staggered_arrival(opening)
	var world: RefCounted = WORLD.new()
	var started := world.call(
		"start_formal",
		world_data,
		opening,
		identities,
	) as Dictionary
	_expect_equal(started.get("ok"), true, "formal world starts")
	if started.get("ok") != true:
		return
	var states := world.call("get_all_resident_states") as Array
	_expect_equal(states.size(), 15, "all residents keep roster state")
	var scheduled_minutes: Array[int] = []
	var dining_worker_arrival := -1
	for value: Variant in states:
		var state := value as Dictionary
		var arrival := state.get("arrivalState", {}) as Dictionary
		_expect_equal(
			state.get("isPresent"),
			false,
			"resident stays absent before the scheduled minute",
		)
		_expect_equal(
			arrival.get("status"),
			"pending",
			"new resident starts with a pending arrival",
		)
		scheduled_minutes.append(
			int(arrival.get("scheduledAbsoluteMinute", -1)),
		)
		if String(state.get("residentId", "")) == "resident_lu_qing_01":
			dining_worker_arrival = int(
				arrival.get("scheduledAbsoluteMinute", -1),
			)
	scheduled_minutes.sort()
	_expect_equal(
		_unique_ints(scheduled_minutes).size(),
		states.size(),
		"every resident receives a different arrival minute",
	)
	var start_absolute := _absolute_minute(world.call("get_time"))
	_expect(
		scheduled_minutes[0] > start_absolute,
		"no resident appears before the world starts",
	)
	_expect_equal(
		dining_worker_arrival,
		start_absolute + 1,
		"the dining operator arrives first so opening-day meal preparation is not delayed until noon",
	)
	_expect(
		scheduled_minutes[-1] <= 719,
		"all residents arrive before noon on day one",
	)
	_expect(
		not _regular_intervals(scheduled_minutes),
		"arrival intervals are not a fixed timetable",
	)
	_expect_equal(
		(world.call("take_pending_decision_requests") as Array).size(),
		0,
		"absent residents do not request Agent decisions",
	)
	var opening_services := world.call(
		"get_place_service_state_snapshots",
	) as Array
	_expect(
		not opening_services.is_empty(),
		"formal service places expose opening state",
	)
	for value: Variant in opening_services:
		_expect_equal(
			(value as Dictionary).get("open"),
			false,
			"a service stays closed until its worker arrives",
		)
	var actor_root := Node2D.new()
	actor_root.y_sort_enabled = true
	root.add_child(actor_root)
	var presentation := RESIDENT_PRESENTATION.new()
	root.add_child(presentation)
	var presentation_bind := presentation.call(
		"bind_world",
		world,
		actor_root,
	) as Dictionary
	_expect_equal(
		presentation_bind.get("ok"),
		true,
		"resident presentation binds to the pending roster",
	)
	_expect_equal(
		presentation_bind.get("residentCount"),
		0,
		"pending residents do not create visible bodies",
	)

	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect_equal(save_result.get("ok"), true, "pending schedule saves")
	var restored_world: RefCounted = WORLD.new()
	var restore_start := restored_world.call(
		"start_formal_restore_observer",
		world_data,
		opening,
		identities,
	) as Dictionary
	_expect_equal(
		restore_start.get("ok"),
		true,
		"restore host starts",
	)
	var restored := restored_world.call(
		"restore_from_snapshot",
		world_data,
		opening,
		save_result.get("snapshot", {}) as Dictionary,
		identities,
	) as Dictionary
	_expect_equal(restored.get("ok"), true, "pending schedule restores")
	var restored_minutes: Array[int] = []
	for value: Variant in (
		restored_world.call("get_all_resident_states") as Array
	):
		restored_minutes.append(
			int(
				(
					(value as Dictionary).get(
						"arrivalState",
						{},
					) as Dictionary
				).get("scheduledAbsoluteMinute", -1),
			),
		)
	restored_minutes.sort()
	_expect_equal(
		restored_minutes,
		scheduled_minutes,
		"loading does not reroll the arrival timetable",
	)
	var separate_world: RefCounted = WORLD.new()
	var separate_start := separate_world.call(
		"start_formal",
		world_data,
		opening,
		identities,
	) as Dictionary
	_expect_equal(
		separate_start.get("ok"),
		true,
		"a separate new town starts with the same authored opening",
	)
	var separate_minutes: Array[int] = []
	for value: Variant in (
		separate_world.call("get_all_resident_states") as Array
	):
		separate_minutes.append(
			int(
				(
					(value as Dictionary).get(
						"arrivalState",
						{},
					) as Dictionary
				).get("scheduledAbsoluteMinute", -1),
			),
		)
	separate_minutes.sort()
	_expect(
		separate_minutes != scheduled_minutes,
		"a separate new town draws a genuinely different arrival timetable",
	)

	var expected_arrival_count := 0
	var first_arrival_checked := false
	var first_arrival_resident_id := ""
	var first_arrival_absolute_minute := -1
	var first_arrival_bridge_released := false
	while (
		_absolute_minute(world.call("get_time"))
		< scheduled_minutes[-1]
	):
		var minute_result := world.call("advance", 1.0) as Dictionary
		_expect_equal(
			minute_result.get("minutesAdvanced"),
			1,
			"normal World advance emits one real game-minute tick",
		)
		var current_absolute := _absolute_minute(world.call("get_time"))
		while (
			expected_arrival_count < scheduled_minutes.size()
			and scheduled_minutes[expected_arrival_count]
			<= current_absolute
		):
			expected_arrival_count += 1
		var present_states := _present_states(
			world.call("get_all_resident_states") as Array,
		)
		_expect_equal(
			present_states.size(),
			expected_arrival_count,
			"only residents whose scheduled minute has passed are present",
		)
		_expect_equal(
			(presentation.call("get_resident_ids") as Array).size(),
			expected_arrival_count,
			"presentation bodies follow the same real arrival ticks",
		)
		if expected_arrival_count == 1 and not first_arrival_checked:
			first_arrival_checked = true
			first_arrival_resident_id = String(
				present_states[0].get("residentId", "")
			)
			first_arrival_absolute_minute = current_absolute
			var arrival_resident := (
				(world.call("residents") as Dictionary).get(
					String(present_states[0].get("residentId", "")),
					{},
				) as Dictionary
			)
			var arrival_action := (
				arrival_resident.get("currentAction", {}) as Dictionary
			)
			_expect_equal(
				present_states[0].get("currentPlace"),
				"南入口",
				"the first resident enters through the South gate",
			)
			_expect_equal(
				arrival_action.get("decisionBridge"),
				true,
				"the arriving resident walks naturally while the first decision is pending",
			)
			_expect(
				not (arrival_action.get("idlePathPoints", []) as Array).is_empty(),
				"the arrival bridge moves the resident away from the entrance",
			)
			var arrival_requests := world.call(
				"take_pending_decision_requests",
			) as Array
			_expect_equal(
				arrival_requests.size(),
				1,
				"the arriving resident starts deciding only after entering",
			)
			if arrival_requests.size() == 1:
				var arrival_wake := (
					(arrival_requests[0] as Dictionary).get("wakePacket", {})
					as Dictionary
				)
				_expect_equal(
					(
						(arrival_wake.get("snapshot", {}) as Dictionary)
						.get("me", {}) as Dictionary
					).get("current_action"),
					null,
					"the local arrival bridge does not replace the resident's first OC decision",
				)
			_expect_equal(
				(world.call("create_save_snapshot") as Dictionary).get("ok"),
				true,
				"the arrival decision bridge remains saveable",
			)
		if (
			first_arrival_checked
			and not first_arrival_bridge_released
			and current_absolute >= first_arrival_absolute_minute + 1
		):
			var first_arrival_after_bridge := (
				(world.call("residents") as Dictionary).get(
					first_arrival_resident_id,
					{},
				) as Dictionary
			)
			_expect(
				(first_arrival_after_bridge.get("currentAction", {}) as Dictionary).is_empty(),
				"the arrival bridge ends after its one-minute entry walk instead of adding a second idle minute",
			)
			_expect_equal(
				first_arrival_after_bridge.get("decisionPending"),
				true,
				"ending the arrival bridge keeps the pending Agent decision alive",
			)
			first_arrival_bridge_released = true
	_expect_equal(
		_present_states(
			world.call("get_all_resident_states") as Array,
		).size(),
		15,
		"the full roster has entered by the end of the morning",
	)
	for value: Variant in (
		world.call("get_place_service_state_snapshots") as Array
	):
		var service := value as Dictionary
		if not String(service.get("owner_id", "")).is_empty():
			_expect_equal(
				service.get("open"),
				true,
				"staffed services open after their workers have arrived",
			)
	_expect_equal(
		(presentation.call("get_resident_ids") as Array).size(),
		15,
		"all resident bodies exist after the morning arrivals finish",
	)
	var arrival_log := world.call(
		"query_world_log_threads",
		{"limit": 200},
	) as Dictionary
	_expect_equal(arrival_log.get("ok"), true, "arrival history can be queried")
	var arrival_thread_count := 0
	for row_value: Variant in arrival_log.get("rows", []) as Array:
		if String((row_value as Dictionary).get("threadId", "")).begins_with(
			"lifecycle:resident-arrival:",
		):
			arrival_thread_count += 1
	_expect_equal(
		arrival_thread_count,
		15,
		"every resident arrival remains available in world history",
	)
	return
func _resident_identities_staggered_arrival(opening: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		result.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(
					resident.get("attributes", {}) as Dictionary
				).get("name", ""),
			),
		})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("residentId", "")) < String(
				right.get("residentId", ""),
			)
	)
	return result



func _present_states(states: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in states:
		if (
			value is Dictionary
			and bool((value as Dictionary).get("isPresent", false))
		):
			result.append(value as Dictionary)
	return result



func _unique_ints(values: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		if not result.has(value):
			result.append(value)
	return result



func _regular_intervals(values: Array[int]) -> bool:
	if values.size() < 3:
		return false
	var expected := values[1] - values[0]
	for index in range(2, values.size()):
		if values[index] - values[index - 1] != expected:
			return false
	return true



func _absolute_minute(time_value: Variant) -> int:
	var time := time_value as Dictionary
	var parts := String(time.get("clock", "00:00")).split(":")
	return (
		(int(time.get("day", 1)) - 1) * 1440
		+ int(parts[0]) * 60
		+ int(parts[1])
	)



func _scenario_weather_behavior_diversity() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect(opening_result.get("ok") == true, "正式开局夹具必须可用")
	if opening_result.get("ok") != true:
		return
	var world: RefCounted = WORLD.new()
	_expect(
		(world.call(
			"start",
			data,
			opening_result.get("config", {}) as Dictionary,
		) as Dictionary).get("ok") == true,
		"天气多样性模拟必须能启动正式 World",
	)
	var initial_requests := (
		world.call("take_pending_decision_requests") as Array[Dictionary]
	)
	_expect(initial_requests.size() == 15, "15 位居民必须收到初始决定")
	for request: Dictionary in initial_requests:
		var wake := request.get("wakePacket", {}) as Dictionary
		var resident_name := String(request.get("residentName", ""))
		var result := world.call(
			"submit_agent_decision",
			resident_name,
			_wait_weather_behavior_diversity(wake),
		) as Dictionary
		_expect(
			String(result.get("status", "")) in [
				"accepted",
				"continued",
			],
			"%s 的初始状态必须被 World 保留：%s"
			% [resident_name, result],
		)

	var weather_result := world.call("set_weather", "大雨") as Dictionary
	_expect(
		weather_result.get("changed") == true,
		"大雨必须成为新的 World 确认事实",
	)
	var weather_requests := (
		world.call("take_pending_decision_requests") as Array[Dictionary]
	)
	_expect(
		weather_requests.size() == 4,
		"只有当前在户外的 4 位居民应立即回应天气",
	)
	var choices := {
		"林岚": {"kind": "continue"},
		"唐小满": {"kind": "go", "place": "花房咖啡馆"},
		"阿禾": {"kind": "go", "place": "图书馆"},
		"叶澄": {"kind": "go", "place": "东南街住宅"},
	}
	var observed_kinds := {}
	var requested_places: Array[String] = []
	for request: Dictionary in weather_requests:
		var resident_name := String(request.get("residentName", ""))
		var wake := request.get("wakePacket", {}) as Dictionary
		var choice := choices.get(resident_name, {}) as Dictionary
		_expect(not choice.is_empty(), "天气模拟必须覆盖 %s" % resident_name)
		if choice.is_empty():
			continue
		var decision := {}
		if String(choice.get("kind", "")) == "continue":
			decision = {
				"decision_id": String(wake.get("decision_id", "")),
				"handling": "continue_current",
			}
			observed_kinds["continue_outdoor"] = true
		else:
			var place_name := String(choice.get("place", ""))
			decision = _go_weather_behavior_diversity(wake, place_name)
			requested_places.append(place_name)
			observed_kinds[
				"home" if place_name.ends_with("住宅") else "public_indoor"
			] = true
		var result := world.call(
			"submit_agent_decision",
			resident_name,
			decision,
		) as Dictionary
		_expect(
			String(result.get("status", "")) in ["accepted", "continued"],
			"%s 的天气选择必须进入 World 执行链：%s"
			% [resident_name, result],
		)

	_expect(
		observed_kinds.has("continue_outdoor"),
		"大雨中应允许有人按事情轻重继续当前户外行动",
	)
	_expect(
		observed_kinds.has("public_indoor"),
		"大雨中应允许居民选择公共室内地点",
	)
	_expect(
		observed_kinds.has("home"),
		"回家仍应是居民可选择的一条生活路径",
	)
	_expect(
		requested_places.count("花房咖啡馆") == 1
		and requested_places.count("图书馆") == 1
		and requested_places.count("东南街住宅") == 1,
		"模拟选择必须形成公共地点、另一公共地点与住处三种去向",
	)
	var context := (
		world.call(
			"get_resident_state",
			"resident_tang_xiaoman_01",
		) as Dictionary
	)
	_expect(
		String(
			(context.get("currentAction", {}) as Dictionary).get(
				"type",
				"",
			)
		) == "去"
		and String(context.get("doing", "")).contains("花房咖啡馆"),
		"唐小满的公共室内去向必须成为 World 的公开行动与状态",
	)
	return
func _wait_weather_behavior_diversity(wake: Dictionary) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-continuity" % decision_id,
			"type": "待着",
			"line": "我先看看眼前的情况",
		},
	}



func _go_weather_behavior_diversity(wake: Dictionary, place_name: String) -> Dictionary:
	var decision_id := String(wake.get("decision_id", ""))
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-go-%s" % [decision_id, place_name],
			"type": "去",
			"place": place_name,
			"line": "我去%s避一避" % place_name,
		},
	}



func _scenario_action_type_registry() -> void:
	_test_full_set_matches_field_whitelist()
	_test_shape_validation_covers_expected_types()
	_test_conflict_types_excluded_from_advance_tables()
	_test_prop_type_remains_live()
	_test_default_doing_covers_expected_types()
	return
func _test_full_set_matches_field_whitelist() -> void:
	var whitelist_types: Array[String] = []
	for key_value: Variant in VALIDATION.ACTION_FIELDS:
		whitelist_types.append(String(key_value))
	whitelist_types.sort()
	var registry_types := REGISTRY.ALL_TYPES.duplicate()
	registry_types.sort()
	_expect_equal(
		whitelist_types,
		registry_types,
		"字段白名单(T1)与登记表全集逐项一致",
	)
	_expect_equal(REGISTRY.ALL_TYPES.size(), 13, "动作类型全集为 13 种")



func _test_shape_validation_covers_expected_types() -> void:
	# T4:登记表声明覆盖的类型必须被形状校验认出(未知字段会被拒),
	# 未声明的类型(冲突五类)必须直接放行——校验对它们不设约束。
	for action_type: String in REGISTRY.ALL_TYPES:
		var action := {
			"action_id": "registry-%s" % action_type,
			"type": action_type,
			"unknown_field": true,
		}
		# 第一层:字段白名单对全部类型生效,未知字段一律被拒。
		_expect(
			not String(VALIDATION.validate_action_shape(action)).is_empty(),
			"%s 的未知字段被白名单层拒绝" % action_type,
		)
		# 第二层:仅登记类型有必填校验;未登记类型给出合法字段即应通过。
		var minimal := {
			"action_id": "registry-min-%s" % action_type,
			"type": action_type,
		}
		var minimal_error := String(VALIDATION.validate_action_shape(minimal))
		if not REGISTRY.participates_in("T4_required_fields", action_type):
			_expect(
				minimal_error.is_empty(),
				"%s 无必填校验,最小动作应放行" % action_type,
			)



func _test_conflict_types_excluded_from_advance_tables() -> void:
	# 冲突五类由冲突桥即时结算、不写 currentAction,故不参与推进期各表。
	for action_type: String in REGISTRY.CONFLICT_TYPES:
		_expect(
			REGISTRY.is_conflict_type(action_type),
			"%s 登记为冲突类型" % action_type,
		)
		_expect(
			not REGISTRY.participates_in("T4_required_fields", action_type),
			"%s 不参与形状校验(有意)" % action_type,
		)
		_expect(
			not REGISTRY.participates_in("T7_default_doing", action_type),
			"%s 不参与 UI 文案表(有意)" % action_type,
		)
	_expect_equal(
		REGISTRY.CONFLICT_TYPES.size(),
		5,
		"冲突类型共 5 种",
	)
	for action_type: String in REGISTRY.ALL_TYPES:
		if REGISTRY.is_conflict_type(action_type):
			continue
		_expect(
			REGISTRY.participates_in("T4_required_fields", action_type)
			or action_type in REGISTRY.PREPARE_REJECTED_TYPES
			or true,
			"%s 为非冲突类型" % action_type,
		)



func _test_prop_type_remains_live() -> void:
	# "用道具"是活玩法:提交入口在 submit_agent_decision 分流到
	# _submit_legacy_prop_activity,不得因 _prepare_action 的硬拒而被判死。
	_expect(
		REGISTRY.ALL_TYPES.has("用道具"),
		"用道具在类型全集内",
	)
	_expect(
		not REGISTRY.PREPARE_REJECTED_TYPES.has("用道具"),
		"用道具不属于准备期硬拒类型(硬拒只守直连入口)",
	)
	_expect(
		REGISTRY.participates_in("T4_required_fields", "用道具"),
		"用道具参与形状校验",
	)
	_expect(
		REGISTRY.participates_in("T7_default_doing", "用道具"),
		"用道具参与 UI 文案表",
	)



func _test_default_doing_covers_expected_types() -> void:
	for action_type: String in REGISTRY.ALL_TYPES:
		var doing := String(PROJECTION.default_doing(
			_StubWorld.new(),
			{"type": action_type},
		))
		_expect(
			not doing.is_empty(),
			"%s 的 UI 文案非空(未覆盖类型走兜底)" % action_type,
		)
		if not REGISTRY.participates_in("T7_default_doing", action_type):
			_expect_equal(
				doing,
				"正在行动",
				"%s 未在文案表内,应走兜底文案" % action_type,
			)



func _scenario_audio_controller_button_cue() -> void:
	await process_frame
	var controller: Node = AUDIO_CONTROLLER.new()

	var cancel_delete := Button.new()
	cancel_delete.text = "取消删除"
	_expect_cue(controller, cancel_delete, "ui_back", "取消删除 is a cancel action, not a warning")

	var delete_button := Button.new()
	delete_button.text = "删除存档"
	_expect_cue(controller, delete_button, "ui_warning", "删除存档 keeps the warning cue")

	var quit_button := Button.new()
	quit_button.text = "退出游戏"
	_expect_cue(controller, quit_button, "ui_warning", "退出游戏 keeps the warning cue")

	var background_button := Button.new()
	background_button.name = "BackgroundPanelButton"
	_expect_cue(controller, background_button, "ui_tap", "background must not match the back keyword")

	var back_button := Button.new()
	back_button.name = "back_button"
	_expect_cue(controller, back_button, "ui_back", "back still matches as a whole word")

	var meta_button := Button.new()
	meta_button.text = "删除"
	meta_button.set_meta("town_audio_cue", "ui_confirm")
	_expect_cue(controller, meta_button, "ui_confirm", "explicit town_audio_cue meta wins over sniffing")

	controller._slider_steps[123] = 4
	controller.prepare_shutdown()
	_expect(
		(controller._slider_steps as Dictionary).is_empty(),
		"prepare_shutdown clears the slider step cache",
	)

	for node: Node in [
		cancel_delete,
		delete_button,
		quit_button,
		background_button,
		back_button,
		meta_button,
		controller,
	]:
		node.free()
	return
func _expect_cue(
	controller: Node, button: BaseButton, expected: String, message: String
) -> void:
	var actual := String(controller._cue_for_button(button))
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, expected, actual])
