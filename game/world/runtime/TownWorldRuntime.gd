class_name TownWorldRuntime
extends TownWorldContract

signal resident_state_changed(resident_name: String, state: Dictionary)
signal resident_action_started(resident_name: String, action: Dictionary)
signal resident_reaction_created(resident_name: String, reaction: Dictionary)
signal resident_action_phase_changed(resident_id: String, phase: Dictionary)
signal resident_activity_started(resident_id: String, event: Dictionary)
signal resident_activity_completed(resident_id: String, event: Dictionary)
signal resident_activity_interrupted(resident_id: String, event: Dictionary)
signal resident_activity_failed(resident_id: String, event: Dictionary)
signal resident_place_changed(resident_name: String, change: Dictionary)
signal resident_perception_changed(resident_name: String, change: Dictionary)
signal player_avatar_state_changed(state: Dictionary)
signal player_avatar_place_changed(change: Dictionary)
signal player_avatar_perception_changed(change: Dictionary)
signal player_command_result_created(result: Dictionary)
signal world_event_created(resident_name: String, event: Dictionary)
signal action_result_created(resident_name: String, result: Dictionary)
signal story_event_created(event: Dictionary)
signal environment_changed(time: Dictionary, weather: String)
signal announcement_published(announcement: Dictionary)
signal social_matter_changed(summary: Dictionary)
signal conversation_changed(conversation_id: String, state: Dictionary)
signal lifecycle_state_changed(state: Dictionary)
signal world_restored(summary: Dictionary)
signal world_revision_changed(revision: int)
signal world_log_changed(change: Dictionary)
signal simulation_speed_changed(speed: int, world_revision: int)
signal conflict_projection_changed(projection: Dictionary)
signal conflict_event_created(event: Dictionary)
signal conflict_follow_up_required(follow_up: Dictionary)

const OPENING_CONFIG := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const WORLD_ENVIRONMENT := preload("res://world/runtime/environment/TownWorldEnvironment.gd")
const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")
const CHARACTER_MOVEMENT_QUERY := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const MOVEMENT_CLEARANCE_RUNTIME := preload(
	"res://world/runtime/TownMovementClearanceRuntime.gd"
)
const RESIDENT_ARRIVAL_RUNTIME := preload("res://world/runtime/TownResidentArrivalRuntime.gd")
const AGENT_WAKE_STATE_RUNTIME := preload(
	"res://world/runtime/TownAgentWakeStateRuntime.gd"
)
const AGENT_WAKE_PREPARATION_RUNTIME := preload("res://world/runtime/TownAgentWakePreparationRuntime.gd")
const WORLD_PERFORMANCE_PROBE := preload(
	"res://world/runtime/TownWorldPerformanceProbe.gd"
)
const ACTIVITY_OPTION_QUERY := preload(
	"res://world/runtime/activity/TownActivityOptionQuery.gd"
)
const ACTIVITY_REACHABILITY_CACHE := preload("res://world/runtime/activity/TownActivityReachabilityCache.gd")
const FRAME_BUDGET_RUNTIME := preload(
	"res://world/runtime/presentation/TownWorldFrameBudgetRuntime.gd"
)
const WORK_ACTOR_SELECTION_POLICY := preload(
	"res://world/runtime/work/TownWorkActorSelectionPolicy.gd"
)
const PROP_QUERY := preload("res://world/data/town/TownWorldPropQuery.gd")
const INDOOR_PATH_QUERY := preload("res://world/data/town/TownIndoorPropPathQuery.gd")
const INDOOR_LAYOUT_PROJECTION := preload(
	"res://world/runtime/TownIndoorLayoutProjection.gd"
)
const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const RESTORE_STATE := preload("res://world/runtime/persistence/TownWorldRestoreState.gd")
const RESTORE_LAYOUT := preload("res://world/runtime/persistence/TownWorldRestoreLayout.gd")
const RESTORE_PEOPLE := preload("res://world/runtime/persistence/TownWorldRestorePeople.gd")
const RESTORE_WORK := preload("res://world/runtime/persistence/TownWorldRestoreWork.gd")
const TRAVELER_RELATIONSHIP_BRIDGE := preload("res://world/runtime/relationship/TownTravelerRelationshipWorldBridge.gd")
const ANNOUNCEMENT_PUBLISHER_PROJECTION := preload("res://world/presentation/announcement/TownAnnouncementPublisherProjection.gd")
const WORK_SETTLEMENT := preload(
	"res://world/runtime/work/TownWorkSettlement.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const CONVERSATION_CONFLICT_BRIDGE := preload(
	"res://world/runtime/conversation/TownConversationConflictBridge.gd"
)
const WORLD_LOG_STORE := preload(
	"res://world/runtime/log/TownWorldLogStore.gd"
)
const STARTUP_VALIDATOR := preload("res://world/runtime/TownWorldStartupValidator.gd")
const ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownWorldActivityRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const WORK_TASK_RUNTIME := preload(
	"res://world/runtime/work/TownWorkTaskRuntime.gd"
)
const STAFFING_RUNTIME := preload(
	"res://world/runtime/work/TownStaffingRuntime.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const ACTION_GEOMETRY := preload(
	"res://world/runtime/action/TownActionGeometry.gd"
)
const ACTION_PROJECTION_MODULE := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const RUNTIME_LOG_TEXT := preload("res://world/runtime/log/TownRuntimeLogText.gd")
const ACTION_SUPPORT := preload("res://world/runtime/action/TownActionSupport.gd")
const OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS := ACTION_SUPPORT.OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS
const ACTIVITY_SCALARS := preload("res://world/runtime/activity/TownActivityScalars.gd")
const SOCIAL_JUDGMENTS := preload("res://world/runtime/social/TownSocialJudgments.gd")
const BULLETIN_PUBLISH_ACTIVITY_ID := SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID
const BULLETIN_READ_ACTIVITY_ID := SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID
const COMMUNITY_BULLETIN_PLACE_ID := SOCIAL_JUDGMENTS.COMMUNITY_BULLETIN_PLACE_ID
const SYSTEM_BULLETIN_PUBLISHER_ID := "world"
const CONFLICT_JUDGMENTS := preload("res://world/runtime/conflict/TownConflictJudgments.gd")
const ACTION_TIMING := preload(
	"res://world/runtime/action/TownActionTiming.gd"
)
const CARGO_INVENTORY_RUNTIME := preload(
	"res://world/runtime/work/TownCargoInventoryRuntime.gd"
)
const PRODUCTION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionRuntime.gd"
)
const OCCUPATION_SERVICE_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceRuntime.gd"
)
const SOCIAL_MATTER_RUNTIME := preload(
	"res://world/runtime/social/TownSocialMatterRuntime.gd"
)
const COMMUNITY_BULLETIN_RUNTIME := preload(
	"res://world/runtime/social/TownCommunityBulletinRuntime.gd"
)
const ANNOUNCEMENT_TIME_PARSER := preload(
	"res://world/runtime/social/TownAnnouncementTimeParser.gd"
)
const ANNOUNCEMENT_RESIDENT_RUNTIME := preload("res://world/runtime/social/TownAnnouncementResidentRuntime.gd")
const SOCIAL_MATTER_SOURCE_ADAPTER := preload(
	"res://world/runtime/social/TownSocialMatterSourceAdapter.gd"
)
const SOCIAL_AGENT_ADAPTER := preload(
	"res://world/runtime/social/TownSocialAgentAdapter.gd"
)
const RESIDENT_MESSAGE_POLICY := preload(
	"res://world/runtime/social/TownResidentMessagePolicy.gd"
)
const RESIDENT_MESSAGE_CONTENT := preload(
	"res://world/runtime/social/TownResidentMessageContent.gd"
)
const SOCIAL_MATTER_PUBLIC_PROJECTION := preload(
	"res://world/runtime/social/TownSocialMatterPublicProjection.gd"
)
const RELATIONSHIP_EVIDENCE_PROGRESS := preload(
	"res://world/runtime/relationship/TownRelationshipEvidenceProgress.gd"
)
const RESIDENT_CONDITION_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentConditionRuntime.gd"
)
const RESIDENT_SLEEP_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentSleepRuntime.gd"
)
const CLINIC_INTERVIEW_POLICY := preload(
	"res://world/runtime/condition/TownClinicInterviewPolicy.gd"
)
const CONFLICT_CONTROLLER := preload(
	"res://world/runtime/conflict/TownConflictWorldController.gd"
)
const CONFLICT_AGENT_WORLD_BRIDGE := preload(
	"res://world/runtime/conflict/TownConflictAgentWorldBridge.gd"
)
const CONFLICT_KNOWLEDGE_PROJECTOR := preload(
	"res://world/runtime/conflict/TownConflictKnowledgeProjector.gd"
)
const RESIDENT_LIFECYCLE_RUNTIME := preload(
	"res://world/runtime/lifecycle/TownResidentLifecycleRuntime.gd"
)
const RESIDENT_LIFECYCLE_PROJECTION := preload(
	"res://world/presentation/lifecycle/TownResidentLifecycleProjection.gd"
)
const RESIDENT_STATE_PROJECTION := preload(
	"res://world/runtime/presentation/TownResidentStateProjection.gd"
)
const ACTION_OPTION_DIRECTORY := preload(
	"res://world/runtime/action/TownActionOptionDirectory.gd"
)
const ACTION_OPTION_SOURCE_ADAPTER := preload(
	"res://world/runtime/action/TownActionOptionSourceAdapter.gd"
)
const ACTIVITY_ROUTINE_DURATION_MINUTES := {
	# A work activity is one decision stage. When it finishes the resident
	# receives the result and decides again instead of World silently choosing
	# another workplace activity on the resident's behalf.
	"work": 20,
	"meal": 45,
}
const ACTIVITY_ROUTINE_STEP_CAP_MINUTES := {
	"work": 20,
	"meal": 12,
}
const ACTIVITY_ROUTINE_MAX_STEPS := {
	"work": 1,
	"meal": 3,
}
const DINING_SERVICE := preload("res://world/runtime/work/TownDiningServiceRuntime.gd")
const BODY_LEVELS := {
	"困": ["不困", "有点困", "很困"],
	"饿": ["不饿", "有点饿", "很饿"],
	"累": ["不累", "有点累", "很累"],
}
const ACTIVITY_STATE_KEYS := [
	"energy",
	"satiety",
	"stress",
	"socialNeed",
	"solitudeNeed",
]
const URGENT_EVENT_TYPES := [
	"搭话",
	"对方答话",
	"对话结束",
	"冲突见闻",
	"身体状况变化",
	"居民死亡",
	"天气变了",
]
const MAX_AUTONOMOUS_CONVERSATION_TURNS := 8
const CONVERSATION_SNAPSHOT_TURN_LIMIT := 16
const AUTONOMOUS_CONVERSATION_IDLE_TIMEOUT_SECONDS := 45.0
const RESIDENT_CONVERSATION_PAIR_COOLDOWN_MINUTES := 30
const MAX_ENDED_CONVERSATION_HISTORY := 64
const MAX_ANNOUNCEMENT_HISTORY := 64
const MAX_AGENT_KNOWN_ANNOUNCEMENTS := 12
const MAX_DELIVERED_PRIVATE_MESSAGES := 64
const MAX_SELF_CARRIED_CARGO_QUANTITY := 2
const PERCEPTION_EXIT_HYSTERESIS_PX := 48.0
const POSTAL_TALK_APPROACH_STOP_DISTANCE_PX := 96.0
const PAUSE_REASONS := [
	"main_menu",
	"resident_editor",
	"furniture_editor",
	"manual",
	"background",
]
# Compatibility fallback for malformed legacy openings. New games receive this
# opaque person ID from TownNewGameOpeningCompiler and persist it in their save.
const DEFAULT_PLAYER_AVATAR_ID := "person_7f3a91c2d8e4"
const ALLOWED_SIMULATION_SPEEDS := [1, 2, 3]
const CONFIRMED_ACTION_PREVIEW_SECONDS := 2.5
const PUBLIC_THOUGHT_MAX_LENGTH := 48
const WAIT_ACTION_MAX_MINUTES := 60
const CONTINUITY_WAIT_MAX_MINUTES := 5
const ACTION_DECISION_PREFETCH_MINUTES := 5
const IDLE_PORTAL_TRIGGER_DISTANCE_PX := 80.0
const IDLE_PORTAL_CLEARANCE_PX := 96.0
const IDLE_RESIDENT_CLEARANCE_PX := 56.0
const IDLE_PARKING_MIN_DISTANCE_PX := 96.0
const IDLE_PARKING_MAX_DISTANCE_PX := 224.0
const IDLE_DEPARTURE_PLACE_CANDIDATE_LIMIT := 2
const OUTDOOR_IDLE_PARKING_MAX_DISTANCE_PX := 640.0
const OUTDOOR_IDLE_PARKING_SAMPLE_STEP_PX := 64.0
const PASSIVE_NEED_TICK_MINUTES := 60
const SLEEP_ACTIVITY_ID := "activity_home_sleep"
const MAX_SOCIAL_RESPONSE_CANDIDATES := 4
const MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT := 1
const SERVICE_FETCH_DURATION_MINUTES := 10
const ESCORT_RETURN_AFTER_MINUTES := 3
const CONVERSATION_FOLLOW_UP_TIMEOUT_MINUTES := 180
const PRIORITY_INTERRUPT_THRESHOLD := 85
const STAFFING_MATTER_REFRESH_INTERVAL_MINUTES := 1440
const NEW_GAME_ARRIVAL_END_MINUTE_OF_DAY := 719
const MAX_LIFE_DESTINATION_OPTIONS := 8
const MAX_LIFE_ACTIVITIES_PER_DESTINATION := 3
const MAX_AGENT_ACTIVITY_ROUTE_CHECKS_PER_WAKE := 1
const NATURAL_LIFE_ACTIVITY_IDS := [
	"activity_cafe_eat_pastry",
	"activity_cafe_order",
	"activity_cafe_rest",
	"activity_dining_eat_meal",
	"activity_dining_collect_meal",
	"activity_dining_return_dishes",
	SLEEP_ACTIVITY_ID,
	"activity_market_buy_general_goods",
	"activity_market_buy_fish",
	"activity_market_buy_flowers",
]
const LIFE_RHYTHM_ANCHORS := [
	{"minute": 420, "id": "morning_start"},
	{"minute": 570, "id": "morning_work"},
	{"minute": 750, "id": "midday_free"},
	{"minute": 870, "id": "afternoon_work"},
	{"minute": 1140, "id": "evening_free"},
	{"minute": 1380, "id": "night_rest"},
]

var _world_data: Dictionary = {}
var _place_by_name_cache: Dictionary = {}
# (place, prop, verb) 的表现提示在道具集合不变时是稳定的；
# 动态道具或世界数据变化时整体失效。
var _presentation_cue_cache: Dictionary = {}
var _base_world_data: Dictionary = {}
var _indoor_layout_overrides: Dictionary = {}
var _dynamic_props: Dictionary = {}
var _animal_facts: Dictionary = {}
var _place_service_states: Dictionary = {}
var _opening: Dictionary = {}
var _owners: Dictionary = {}
var _residents: Dictionary = {}
var _resident_order: Array[String] = []
var _resident_id_by_name: Dictionary = {}
var _resident_name_by_id: Dictionary = {}
var _resident_identity_status := "unavailable"
var _player_avatar: Dictionary = {}
var _player_avatar_present := true
var _traveler_relations: Dictionary = {}
var _announcements: Array[Dictionary] = []
var _conversations: Dictionary = {}
var _autonomous_conversation_idle_seconds: Dictionary = {}
var _autonomous_timeout_tick_seconds := 0.0
var _public_event_log: Array[Dictionary] = []
var _world_log_store: RefCounted = WORLD_LOG_STORE.new()
var _world_log_consistency_error := ""
var _world_log_capture_enabled := false
var _action_story_context: Dictionary = {}
var _conversation_story_context: Dictionary = {}
var _environment: WORLD_ENVIRONMENT
var _activity_runtime: ACTIVITY_RUNTIME = ACTIVITY_RUNTIME.new()
var _activity_routines: Dictionary = {}
var _work_tasks: WORK_TASK_RUNTIME = WORK_TASK_RUNTIME.new()
var _staffing: STAFFING_RUNTIME = STAFFING_RUNTIME.new()
var _cargo_inventory: CARGO_INVENTORY_RUNTIME = CARGO_INVENTORY_RUNTIME.new()
var _production: PRODUCTION_RUNTIME = PRODUCTION_RUNTIME.new()
var _occupation_services: OCCUPATION_SERVICE_RUNTIME = OCCUPATION_SERVICE_RUNTIME.new()
var _private_messages: Dictionary = {}
var _private_message_sequence := 0
var _private_message_archive_summary := {
	"archivedDeliveredCount": 0,
	"archivedOrdinaryCount": 0,
	"archivedFormalNoticeCount": 0,
}
var _activity_work_task_bindings: Dictionary = {}
var _social_matters: SOCIAL_MATTER_RUNTIME = SOCIAL_MATTER_RUNTIME.new()
var _community_bulletin: COMMUNITY_BULLETIN_RUNTIME = COMMUNITY_BULLETIN_RUNTIME.new()
var _social_sources: SOCIAL_MATTER_SOURCE_ADAPTER = SOCIAL_MATTER_SOURCE_ADAPTER.new()
var _social_agent_adapter: SOCIAL_AGENT_ADAPTER = SOCIAL_AGENT_ADAPTER.new()
var _resident_conditions: TownResidentConditionRuntime = RESIDENT_CONDITION_RUNTIME.new()
var _resident_sleep: TownResidentSleepRuntime = RESIDENT_SLEEP_RUNTIME.new()
var _clinic_interviews: TownClinicInterviewPolicy = CLINIC_INTERVIEW_POLICY.new()
var _conflict_controller: TownConflictWorldController
var _conflict_agent_world_bridge: TownConflictAgentWorldBridge = (
	CONFLICT_AGENT_WORLD_BRIDGE.new()
)
# 同一次冲突命令可能连续产出“攻击、命中、受伤”等多条事件。
# 先合并受影响居民，再在最终投影到达时每人只调度一次决定。
var _pending_conflict_knowledge_wakes: Dictionary = {}
var _resident_lifecycle: TownResidentLifecycleRuntime = RESIDENT_LIFECYCLE_RUNTIME.new()
var _action_options: TownActionOptionDirectory = ACTION_OPTION_DIRECTORY.new()
var _action_option_sources: TownActionOptionSourceAdapter = ACTION_OPTION_SOURCE_ADAPTER.new()
var _running := false
var _pause_reasons: Array[String] = []
var _runtime_generation := 0
var _world_revision := 0
var _simulation_speed := 1
var _event_sequence := 0
var _announcement_sequence := 0
var _conversation_sequence := 0
var _tick_weather_override := ""
var _save_candidate_sequence := 0
var _restore_candidate_sequence := 0
var _save_candidates: Dictionary = {}
var _restore_candidates: Dictionary = {}
var _observed_action_preview_resident_id := ""
# 跨调用的活动可达性缓存：键为 (居民, 分钟, 原点格, 目标)，
# 每分钟整表失效。攻击唤醒包会对多名居民重复做相同目标的
# 寻路可达性检查，缓存把这部分 A* 开销压掉。
var _activity_reachability_cache: Dictionary = {}
var _activity_prepared_action_cache: Dictionary = {}
var _activity_reachability_cache_minute := -1
var perception_spatial := PERCEPTION_RUNTIME.SpatialState.new()
var _processing_tick_absolute_minute := -1
var _deferred_resident_state_refreshes: Array[String] = []
var _deferred_resident_state_refresh_keys: Dictionary = {}
var _deferred_resident_place_change_signals: Array[Dictionary] = []
var _perception_refresh_deferred := false
var _perception_deferred_advance_count := 0
var _public_social_matter_activity_cache: Dictionary = {}
var _public_social_matter_activity_cache_revision := -1
var _staffing_matter_sync_signature: Array = []
var _staffing_matter_last_sync_minute := -1
var _staffing_matter_full_sync_count := 0
var _advance_profile_enabled := false
var _last_advance_profile: Dictionary = {}
# A3:advance 期间指向本次 advance_profile,子步骤分项计时经它累计。
var _advance_profile_scratch: Dictionary = {}
# C4 排查计时(A1 探针门控):take 链内部分段,懒加载不进正式启动路径。
var _frame_probe: GDScript = null
var _frame_probe_checked := false
var _agent_request_metrics: Dictionary = {}
var _agent_wake_preparation_runtime := AGENT_WAKE_PREPARATION_RUNTIME.new()
func _reset_agent_request_metrics() -> void:
	_agent_request_metrics = {"decisionCreated": 0, "behaviorStarted": 0, "wakeRefresh": 0, "decisionInvalidated": 0, "prefetch": 0, "pendingQueuePeak": 0, "decisionPendingWithoutAction": 0}
func _count_agent_request_metric(key: String, amount := 1) -> void:
	_agent_request_metrics[key] = int(_agent_request_metrics.get(key, 0)) + amount
func get_agent_request_metrics() -> Dictionary:
	return _agent_request_metrics.duplicate(true)
func _mark_pending_wake_dirty(resident_id: String) -> void:
	if not _residents.has(resident_id): return
	var resident := _residents[resident_id] as Dictionary
	if bool(resident.get("decisionPending", false)): resident["pendingWakeDirty"] = true

func start(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		false,
		resident_identities,
		true,
		false,
	)

func start_observer(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		false,
		resident_identities,
		false,
		false,
	)

func start_formal(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		true,
		resident_identities,
		true,
		true,
	)

func start_formal_observer(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		true,
		resident_identities,
		false,
		true,
	)

func start_formal_restore_observer(
	world_data: Dictionary,
	opening_config: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	return _start_with_validation(
		world_data,
		opening_config,
		true,
		resident_identities,
		false,
		false,
	)

func validate_startup(
	world_data: Dictionary,
	opening_config: Dictionary,
	require_world_ready := true,
	resident_identities: Variant = [],
) -> Dictionary:
	var result := STARTUP_VALIDATOR.validate(
		world_data,
		opening_config,
		require_world_ready,
	) as Dictionary
	if result.get("ok") == true:
		var identities := OPENING_CONFIG.prepare_resident_identities(
			opening_config,
			resident_identities,
			require_world_ready,
		) as Dictionary
		if identities.get("ok") != true:
			result["ok"] = false
			result["errorCode"] = String(identities.get("errorCode", "WORLD_RESIDENT_IDENTITIES_INVALID"))
			result["retryable"] = false
			result["errors"] = (identities.get("errors", []) as Array).duplicate()
			result["issues"] = [{
				"code": String(result["errorCode"]),
				"scope": "opening.residentIdentities",
				"subject": "residentIdentities",
				"message": String((result["errors"] as Array)[0]),
			}]
			result["identityStatus"] = "invalid"
		else:
			result["identityStatus"] = String(identities.get("status", "unavailable"))
			result["residentIdentityCount"] = (identities.get("residents", []) as Array).size()
	result["worldRevision"] = _world_revision
	return result

func validate_new_game_resident_spawns(
	world_data: Dictionary,
	opening_config: Dictionary,
) -> Dictionary:
	var errors := CHARACTER_MOVEMENT_QUERY.validate_formal_new_game_spawns(
		world_data,
		opening_config,
	) as PackedStringArray
	if errors.is_empty():
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"spawnPolicy": "staggered_south_entry",
			"worldRevision": _world_revision,
		}
	return {
		"ok": false,
		"errorCode": "WORLD_RESIDENT_SPAWN_INVALID",
		"retryable": false,
		"errors": Array(errors),
		"issues": [{
			"code": "WORLD_RESIDENT_SPAWN_INVALID",
			"scope": "opening.residents.worldState",
			"subject": "residentSpawn",
			"message": String(errors[0]),
		}],
		"worldRevision": _world_revision,
	}

func _begin_world_run() -> void:
	_running = true
	_world_log_capture_enabled = true
	_connect_work_task_log_source()
	_sync_staffing_matters()

func _announce_world_lifecycle(speed_was_reset: bool) -> Dictionary:
	var lifecycle := get_lifecycle_state()
	_notify_world_revision()
	if speed_was_reset:
		simulation_speed_changed.emit(_simulation_speed, _world_revision)
	lifecycle_state_changed.emit(lifecycle.duplicate(true))
	return lifecycle

## 装机清单交叉校验(批次D之3):运行时组合层维护的子系统安装清单,
## 启动/恢复两条路径装机完成后断言全部就位,兜"新增子系统漏改一处=
## 存档后子系统失联"。缺失时 push_error 会被测试的引擎错误检测抓红。
func _assert_subsystems_installed(context: String) -> void:
	var checklist := {
		"environment": _environment,
		"workTasks": _work_tasks,
		"occupationServices": _occupation_services,
		"socialMatters": _social_matters,
		"communityBulletin": _community_bulletin,
		"residentConditions": _resident_conditions,
		"residentSleep": _resident_sleep,
		"clinicInterviews": _clinic_interviews,
		"conflictController": _conflict_controller,
		"conflictAgentWorldBridge": _conflict_agent_world_bridge,
		"residentLifecycle": _resident_lifecycle,
		"actionOptions": _action_options,
		"activityRuntime": _activity_runtime,
		"cargoInventory": _cargo_inventory,
		"staffing": _staffing,
		"worldLogStore": _world_log_store,
	}
	for key: String in checklist:
		if checklist[key] == null:
			push_error("装机清单校验失败(%s):子系统 %s 未安装" % [context, key])

func _start_with_validation(
	world_data: Dictionary,
	opening_config: Dictionary,
	require_world_ready: bool,
	resident_identities: Variant,
	initial_player_avatar_present: bool,
	validate_new_game_spawns: bool,
) -> Dictionary:
	var validation := validate_startup(
		world_data,
		opening_config,
		require_world_ready,
		resident_identities,
	)
	if validation.get("ok") != true:
		return validation
	var prepared_activity_runtime: TownWorldActivityRuntime = ACTIVITY_RUNTIME.new()
	var activity_configuration := prepared_activity_runtime.configure(
		world_data,
	) as Dictionary
	if activity_configuration.get("ok") != true:
		return _decorate_command_result(activity_configuration)
	var prepared_work_tasks := WORK_TASK_RUNTIME.new()
	var work_task_configuration := prepared_work_tasks.configure(
	) as Dictionary
	if work_task_configuration.get("ok") != true:
		return _decorate_command_result(work_task_configuration)
	var prepared_staffing := STAFFING_RUNTIME.new()
	var staffing_configuration := prepared_staffing.configure(
		world_data,
	) as Dictionary
	if staffing_configuration.get("ok") != true:
		return _decorate_command_result(staffing_configuration)
	var prepared_cargo_inventory := CARGO_INVENTORY_RUNTIME.new()
	var cargo_configuration := prepared_cargo_inventory.configure(
		world_data,
	) as Dictionary
	if cargo_configuration.get("ok") != true:
		return _decorate_command_result(cargo_configuration)
	var opening_stock := prepared_cargo_inventory.initialize_opening_stock(
	) as Dictionary
	if opening_stock.get("ok") != true:
		return _decorate_command_result(opening_stock)
	var prepared_production := PRODUCTION_RUNTIME.new()
	var production_configuration := prepared_production.configure(
		world_data,
	) as Dictionary
	if production_configuration.get("ok") != true:
		return _decorate_command_result(production_configuration)
	var prepared_occupation_services := OCCUPATION_SERVICE_RUNTIME.new()
	var occupation_service_configuration := (
		prepared_occupation_services.configure() as Dictionary
	)
	if occupation_service_configuration.get("ok") != true:
		return _decorate_command_result(
			occupation_service_configuration,
		)
	var occupation_service_initialization := (
		prepared_occupation_services.initialize() as Dictionary
	)
	if occupation_service_initialization.get("ok") != true:
		return _decorate_command_result(
			occupation_service_initialization,
		)
	if require_world_ready and validate_new_game_spawns:
		var spawn_validation := validate_new_game_resident_spawns(
			world_data,
			opening_config,
		) as Dictionary
		if spawn_validation.get("ok") != true:
			return spawn_validation
	var prepared_identities := OPENING_CONFIG.prepare_resident_identities(
		opening_config,
		resident_identities,
		require_world_ready,
	) as Dictionary
	var prepared_environment := WORLD_ENVIRONMENT.new()
	var initial := opening_config.get("environment", {}) as Dictionary
	var environment_result: Dictionary = prepared_environment.start(
		int(initial.get("day", 1)),
		String(initial.get("clock", "00:00")),
		String(initial.get("weather", "晴天")),
		int(initial.get("randomSeed", 1)),
	)
	if environment_result.get("ok") != true:
		return _decorate_command_result(environment_result, "ENVIRONMENT_CONFIG_INVALID")
	var prepared_arrival_schedule: Dictionary = {}
	if require_world_ready and validate_new_game_spawns:
		var arrival_preparation := _prepare_new_game_arrival_schedule(
			opening_config,
			int(prepared_environment.get_absolute_minute()),
		) as Dictionary
		if arrival_preparation.get("ok") != true:
			return _decorate_command_result(arrival_preparation)
		prepared_arrival_schedule = (
			arrival_preparation.get("schedule", {}) as Dictionary
		)
	var production_initialization := prepared_production.initialize(
		int(prepared_environment.get_absolute_minute()),
	) as Dictionary
	if production_initialization.get("ok") != true:
		return _decorate_command_result(production_initialization)
	var prepared_resident_conditions: TownResidentConditionRuntime = RESIDENT_CONDITION_RUNTIME.new()
	var condition_configuration := prepared_resident_conditions.configure() as Dictionary
	if condition_configuration.get("ok") != true:
		return _decorate_command_result(condition_configuration)
	var prepared_resident_sleep: TownResidentSleepRuntime = RESIDENT_SLEEP_RUNTIME.new()
	var prepared_conflict_controller: TownConflictWorldController = CONFLICT_CONTROLLER.new()
	var prepared_resident_lifecycle: TownResidentLifecycleRuntime = RESIDENT_LIFECYCLE_RUNTIME.new()
	var conflict_configuration := prepared_conflict_controller.configure(self,) as Dictionary
	if conflict_configuration.get("ok") != true:
		return _decorate_command_result(conflict_configuration)
	_running = false
	_activity_runtime.close()
	_activity_runtime = prepared_activity_runtime
	_disconnect_work_task_log_source()
	_work_tasks = prepared_work_tasks
	_staffing = prepared_staffing
	_cargo_inventory = prepared_cargo_inventory
	_production = prepared_production
	_occupation_services = prepared_occupation_services
	_resident_conditions = prepared_resident_conditions
	_resident_sleep = prepared_resident_sleep
	_clinic_interviews = CLINIC_INTERVIEW_POLICY.new()
	_pause_reasons.clear()
	_reset_deferred_frame_work()
	var speed_was_reset := _simulation_speed != 1
	_simulation_speed = 1
	_runtime_generation += 1
	_world_data = world_data.duplicate(true)
	_base_world_data = world_data.duplicate(true)
	_place_by_name_cache.clear()
	_presentation_cue_cache.clear()
	PERCEPTION_RUNTIME._rebuild_membership_grid_lookup(self)
	_indoor_layout_overrides.clear()
	_dynamic_props.clear()
	_animal_facts.clear()
	_activity_runtime.reset_runtime_state()
	_activity_routines.clear()
	_activity_work_task_bindings.clear()
	_private_messages.clear()
	_private_message_sequence = 0
	_private_message_archive_summary = RESTORE_WORK.empty_private_message_archive_summary()
	_opening = opening_config.duplicate(true)
	_owners = (opening_config.get("ownerAssignments", {}) as Dictionary).duplicate(true)
	_residents.clear()
	_resident_order.clear()
	_announcements.clear()
	_reset_social_runtimes()
	_conversations.clear()
	_autonomous_conversation_idle_seconds.clear()
	_public_event_log.clear()
	_world_log_store = WORLD_LOG_STORE.new()
	_world_log_store.reset()
	_world_log_consistency_error = ""
	_world_log_capture_enabled = false
	_action_story_context.clear()
	_conversation_story_context.clear()
	_observed_action_preview_resident_id = ""
	perception_spatial.reset()
	_public_social_matter_activity_cache.clear()
	_public_social_matter_activity_cache_revision = -1
	_pending_conflict_knowledge_wakes.clear()
	_staffing_matter_sync_signature.clear()
	_staffing_matter_last_sync_minute = -1
	_staffing_matter_full_sync_count = 0
	MOVEMENT_CLEARANCE_RUNTIME.clear_cache()
	RESIDENT_ARRIVAL_RUNTIME.clear_cache()
	_reset_agent_request_metrics()
	_agent_wake_preparation_runtime.clear()
	_tick_weather_override = ""
	_event_sequence = 0
	_announcement_sequence = 0
	_conversation_sequence = 0
	_apply_resident_identities(prepared_identities)
	for value: Variant in opening_config.get("residents", []) as Array:
		var record := value as Dictionary
		var attributes := record.get("attributes", {}) as Dictionary
		var world_state := record.get("worldState", {}) as Dictionary
		var name := String(attributes.get("name", ""))
		var resident_id := String(record.get("residentId", "")).strip_edges()
		if resident_id.is_empty():
			resident_id = String(_resident_id_by_name.get(name, ""))
		_resident_order.append(resident_id)
		var resident_runtime := _resident_runtime(
			record,
			world_state,
			resident_id,
		)
		if prepared_arrival_schedule.has(resident_id):
			resident_runtime["arrivalState"] = {
				"status": "pending",
				"scheduledAbsoluteMinute": int(
					prepared_arrival_schedule.get(resident_id, -1),
				),
				"arrivedAbsoluteMinute": -1,
			}
			resident_runtime["doing"] = "尚未抵达小镇"
		var lifecycle_initialization := prepared_resident_lifecycle.initialize_resident(resident_id,
			name,
			_resident_home_anchor(world_data, resident_runtime),) as Dictionary
		if lifecycle_initialization.get("ok") != true:
			return _decorate_command_result(lifecycle_initialization)
		_residents[resident_id] = resident_runtime
		var condition_initialization := _resident_conditions.initialize_resident(resident_id,
			RESTORE_PEOPLE.resident_condition_seed(resident_id),) as Dictionary
		if condition_initialization.get("ok") != true:
			return _decorate_command_result(condition_initialization)
		var sleep_initialization := _resident_sleep.initialize_resident(resident_id,) as Dictionary
		if sleep_initialization.get("ok") != true:
			return _decorate_command_result(sleep_initialization)
	_resident_order.sort()
	_resident_lifecycle = prepared_resident_lifecycle
	var staffing_rebuild := _staffing.rebuild(
		_residents,
		int(prepared_environment.get_absolute_minute()),
	) as Dictionary
	if staffing_rebuild.get("ok") != true:
		return _decorate_command_result(staffing_rebuild)
	_initialize_place_service_states()
	_player_avatar = _avatar_runtime(opening_config.get("playerAvatar", {}) as Dictionary)
	_player_avatar_present = initial_player_avatar_present
	_traveler_relations = TRAVELER_RELATIONSHIP_BRIDGE.empty_snapshot()
	_environment = prepared_environment
	_conflict_controller = prepared_conflict_controller
	# 待抵达居民的入口落点和回家可达性属于加载期静态准备，不能等到
	# 某个游戏分钟到来时在正式帧里同步跑完整寻路。
	RESIDENT_ARRIVAL_RUNTIME.prewarm_pending_entry_states(
		self,
		IDLE_RESIDENT_CLEARANCE_PX,
	)
	var conflict_bridge_configuration := _conflict_agent_world_bridge.configure(_conflict_controller,
		_person_name_for_id,) as Dictionary
	if conflict_bridge_configuration.get("ok") != true:
		return _decorate_command_result(conflict_bridge_configuration)
	_connect_conflict_controller_signals()
	PERCEPTION_RUNTIME._refresh_perception(self, false)
	_bump_world_revision(false)
	_begin_world_run()
	_sync_production_tasks(
		int(_environment.get_absolute_minute()),
	)
	for resident_id in _resident_order:
		_schedule_decision(resident_id, false)
	_assert_subsystems_installed("start")
	var lifecycle := _announce_world_lifecycle(speed_was_reset)
	return _decorate_command_result({
		"ok": true,
		"validationMode": "formal" if require_world_ready else "development",
		"residentCount": _resident_order.size(),
		"identityStatus": _resident_identity_status,
		"simulationSpeed": _simulation_speed,
		"time": get_time(),
		"weather": get_weather(),
		"lifecycle": lifecycle,
	})

func is_running() -> bool:
	return _running
func _prepare_new_game_arrival_schedule(
	opening_config: Dictionary,
	start_absolute_minute: int,
) -> Dictionary:
	var resident_ids: Array[String] = []
	for value: Variant in opening_config.get("residents", []) as Array:
		if not value is Dictionary:
			continue
		var resident_id := String(
			(value as Dictionary).get("residentId", ""),
		).strip_edges()
		if not resident_id.is_empty():
			resident_ids.append(resident_id)
	resident_ids.sort()
	var day_start := start_absolute_minute - posmod(
		start_absolute_minute,
		1440,
	)
	var last_arrival_minute := (
		day_start + NEW_GAME_ARRIVAL_END_MINUTE_OF_DAY
	)
	var candidate_minutes: Array[int] = []
	for absolute_minute in range(
		start_absolute_minute + 1,
		last_arrival_minute + 1,
	):
		candidate_minutes.append(absolute_minute)
	if candidate_minutes.size() < resident_ids.size():
		return _command_failure(
			"WORLD_RESIDENT_ARRIVAL_WINDOW_INVALID",
			["首日上午剩余时间不足以让所有居民逐个抵达"],
		)
	var random := RandomNumberGenerator.new()
	random.seed = (
		int(Time.get_unix_time_from_system() * 1_000_000.0)
		^ Time.get_ticks_usec()
		^ int(
			(
				opening_config.get("environment", {}) as Dictionary
			).get("randomSeed", 0),
		)
	)
	for index in range(candidate_minutes.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var held := candidate_minutes[index]
		candidate_minutes[index] = candidate_minutes[swap_index]
		candidate_minutes[swap_index] = held
	DINING_SERVICE.prioritize_dining_worker_arrival(opening_config, resident_ids, candidate_minutes)
	var schedule := {}
	for index in resident_ids.size():
		schedule[resident_ids[index]] = candidate_minutes[index]
	return {
		"ok": true,
		"errorCode": "",
		"schedule": schedule,
	}

func is_paused() -> bool:
	return _running and not _pause_reasons.is_empty()

func get_world_revision() -> int:
	return _world_revision

func get_simulation_speed() -> int:
	return _simulation_speed

func set_observed_action_preview_resident(
	resident_ref: String,
	enabled: bool,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var requested_id := _resident_key(resident_ref)
	if enabled and requested_id.is_empty():
		return _command_failure(
			"RESIDENT_NOT_FOUND",
			["找不到要观察的居民"],
		)
	var next_id := requested_id if enabled else ""
	if next_id == _observed_action_preview_resident_id:
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"residentId": next_id,
		})
	_release_observed_action_preview()
	_observed_action_preview_resident_id = next_id
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"residentId": next_id,
	})

func set_simulation_speed(speed: int) -> Dictionary:
	if not _running:
		return _command_failure(
			"WORLD_NOT_RUNNING",
			["世界尚未运行"],
			{"simulationSpeed": _simulation_speed},
		)
	if not ALLOWED_SIMULATION_SPEEDS.has(speed):
		return _command_failure(
			"INVALID_SIMULATION_SPEED",
			["世界倍率只允许 1、2 或 3"],
			{
				"simulationSpeed": _simulation_speed,
				"allowedSimulationSpeeds": ALLOWED_SIMULATION_SPEEDS.duplicate(),
			},
		)
	if speed == _simulation_speed:
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"simulationSpeed": _simulation_speed,
		})
	_simulation_speed = speed
	simulation_speed_changed.emit(_simulation_speed, _world_revision)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"simulationSpeed": _simulation_speed,
	})

func get_lifecycle_state() -> Dictionary:
	var reasons := _pause_reasons.duplicate()
	reasons.sort()
	return {
		"state": "stopped" if not _running else ("paused" if not reasons.is_empty() else "running"),
		"started": _running,
		"paused": _running and not reasons.is_empty(),
		"pauseReasons": reasons,
	}

func get_indoor_layout_projection(space_id: String) -> Dictionary:
	return INDOOR_LAYOUT_PROJECTION.snapshot_for_space(
		_world_data,
		space_id.strip_edges(),
	) as Dictionary

func get_space_character_movement_contract(space_id: String) -> Dictionary:
	return CHARACTER_MOVEMENT_QUERY.space_contract(_world_data, space_id) as Dictionary

func apply_indoor_layout_projection(projection: Dictionary) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if not _pause_reasons.has("furniture_editor"):
		return _command_failure(
			"FURNITURE_EDITOR_NOT_PAUSED",
			["更新室内道具布局前必须以 furniture_editor 原因暂停世界"],
		)
	var errors := INDOOR_LAYOUT_PROJECTION.validate(
		_world_data,
		projection,
	) as PackedStringArray
	var space_id := String(projection.get("spaceId", ""))
	if errors.is_empty():
		_validate_layout_occupants(space_id, projection, errors)
	if not errors.is_empty():
		return _command_failure(
			"INDOOR_LAYOUT_PROJECTION_INVALID",
			Array(errors),
			{"projection": get_indoor_layout_projection(space_id)},
		)
	var previous := get_indoor_layout_projection(space_id)
	var next_data := INDOOR_LAYOUT_PROJECTION.apply(
		_world_data,
		projection,
	) as Dictionary
	var next_projection := INDOOR_LAYOUT_PROJECTION.snapshot_for_space(
		next_data,
		space_id,
	) as Dictionary
	if next_projection == previous:
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"projection": previous,
		})
	_world_data = next_data
	_place_by_name_cache.clear()
	_presentation_cue_cache.clear()
	ACTIVITY_REACHABILITY_CACHE.clear(self)
	var baseline := INDOOR_LAYOUT_PROJECTION.snapshot_for_space(
		_base_world_data,
		space_id,
	) as Dictionary
	if next_projection == baseline:
		_indoor_layout_overrides.erase(space_id)
	else:
		_indoor_layout_overrides[space_id] = next_projection.duplicate(true)
	_bump_world_revision()
	for resident_name in _resident_order:
		var resident := _residents[resident_name] as Dictionary
		if String(resident.get("spaceId", "")) == space_id:
			_schedule_decision(resident_name, true, false, true)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"projection": next_projection,
	})

func pause(reason: String) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"], {"state": get_lifecycle_state()})
	var normalized := reason.strip_edges()
	if not PAUSE_REASONS.has(normalized):
		return _command_failure("INVALID_PAUSE_REASON", ["未知暂停原因：%s" % normalized], {"state": get_lifecycle_state()})
	if _pause_reasons.has(normalized):
		return _decorate_command_result({"ok": true, "changed": false, "state": get_lifecycle_state()})
	_pause_reasons.append(normalized)
	_bump_world_revision()
	var lifecycle := get_lifecycle_state()
	lifecycle_state_changed.emit(lifecycle.duplicate(true))
	return _decorate_command_result({"ok": true, "changed": true, "state": lifecycle})

func resume(reason: String) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"], {"state": get_lifecycle_state()})
	var normalized := reason.strip_edges()
	if not PAUSE_REASONS.has(normalized):
		return _command_failure("INVALID_PAUSE_REASON", ["未知暂停原因：%s" % normalized], {"state": get_lifecycle_state()})
	if not _pause_reasons.has(normalized):
		return _decorate_command_result({"ok": true, "changed": false, "state": get_lifecycle_state()})
	_pause_reasons.erase(normalized)
	_bump_world_revision()
	var lifecycle := get_lifecycle_state()
	lifecycle_state_changed.emit(lifecycle.duplicate(true))
	return _decorate_command_result({"ok": true, "changed": true, "state": lifecycle})

func stop() -> Dictionary:
	if not _running:
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"state": get_lifecycle_state(),
			"simulationSpeed": _simulation_speed,
		})
	_invalidate_all_pending_decisions()
	_world_log_capture_enabled = false
	_pause_reasons.clear()
	_reset_deferred_frame_work()
	_agent_wake_preparation_runtime.clear()
	_observed_action_preview_resident_id = ""
	_tick_weather_override = ""
	_dynamic_props.clear()
	_animal_facts.clear()
	_place_service_states.clear()
	_activity_runtime.reset_runtime_state()
	_activity_routines.clear()
	_activity_work_task_bindings.clear()
	_private_messages.clear()
	_private_message_sequence = 0
	_private_message_archive_summary = RESTORE_WORK.empty_private_message_archive_summary()
	_staffing = STAFFING_RUNTIME.new()
	_cargo_inventory = CARGO_INVENTORY_RUNTIME.new()
	_production = PRODUCTION_RUNTIME.new()
	_occupation_services = OCCUPATION_SERVICE_RUNTIME.new()
	_resident_conditions = RESIDENT_CONDITION_RUNTIME.new()
	_resident_sleep = RESIDENT_SLEEP_RUNTIME.new()
	_clinic_interviews = CLINIC_INTERVIEW_POLICY.new()
	_disconnect_conflict_controller_signals()
	_conflict_controller = null
	_pending_conflict_knowledge_wakes.clear()
	var speed_was_reset := _simulation_speed != 1
	_simulation_speed = 1
	_running = false
	_bump_world_revision()
	if speed_was_reset:
		simulation_speed_changed.emit(_simulation_speed, _world_revision)
	var lifecycle := get_lifecycle_state()
	lifecycle_state_changed.emit(lifecycle.duplicate(true))
	conflict_projection_changed.emit(_empty_conflict_projection())
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"state": lifecycle,
		"simulationSpeed": _simulation_speed,
	})

func create_save_snapshot() -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	# A UI preview is an observation-only transient.  Resolve it before
	# snapshotting so restore never replays a partially viewed bubble and the
	# already-confirmed action cannot be lost.
	_release_observed_action_preview()
	_reconcile_activity_routines_before_save()
	_sync_activity_save_state()
	var resident_snapshots: Array[Dictionary] = []
	for resident_name in _resident_order:
		resident_snapshots.append(_resident_save_snapshot(resident_name))
	var conversation_snapshots: Array[Dictionary] = []
	var conversation_ids: Array[String] = []
	for conversation_id_value: Variant in _conversations:
		conversation_ids.append(String(conversation_id_value))
	conversation_ids.sort()
	for conversation_id in conversation_ids:
		conversation_snapshots.append((_conversations[conversation_id] as Dictionary).duplicate(true))
	var state := {
		"environment": _environment.create_save_snapshot() as Dictionary,
		"owners": _owners.duplicate(true),
		"residents": resident_snapshots,
		"playerAvatar": _player_avatar.duplicate(true),
		"announcements": _announcements.duplicate(true),
		"conversations": conversation_snapshots,
		"eventLog": _public_event_log.duplicate(true),
		"activityRuntime": (
			_activity_runtime.create_save_snapshot() as Dictionary
		).duplicate(true),
		"activityRoutines": _activity_routine_save_snapshot(),
		"workTasks": _work_tasks.create_save_snapshot(
		) as Dictionary,
		"staffingState": (
			_staffing.persistent_snapshot() as Dictionary
		),
		"cargoInventory": _cargo_inventory.snapshot() as Dictionary,
		"productionState": _production.snapshot() as Dictionary,
		"occupationServices": (
			_occupation_services.snapshot() as Dictionary
		),
		"privateMessages": _private_message_save_snapshot(),
		"activityWorkTaskBindings": (
			_activity_work_task_bindings.duplicate(true)
		),
		"socialMatters": _social_matters.create_save_snapshot(
		) as Dictionary,
		"communityBulletin": _community_bulletin.create_save_snapshot(
		) as Dictionary,
		"animalFacts": _animal_facts.duplicate(true),
		"placeServiceStates": _place_service_states.duplicate(true),
		"residentConditions": _resident_conditions.create_save_snapshot() as Dictionary,
		"residentSleep": _resident_sleep.create_save_snapshot() as Dictionary,
		"conflictState": (
			_conflict_controller.export_state() as Dictionary
			if _conflict_controller != null
			else {}
		),
		"residentLifecycle": _resident_lifecycle.create_save_snapshot() as Dictionary,
		"travelerRelations": _traveler_relations.duplicate(true),
		"indoorLayoutOverrides": _indoor_layout_override_snapshots(),
		"sequences": {
			"event": _event_sequence,
			"announcement": _announcement_sequence,
			"conversation": _conversation_sequence,
			"worldRevision": _world_revision,
		},
	}
	# 域 key 单一来源是 SaveCodec.STATE_KEYS/OPTIONAL_STATE_KEYS:上面的字典
	# 必须与清单完全一致,新增域先改 SaveCodec 再补值,漂移在存档时立刻失败。
	if not SAVE_CODEC.has_exact_string_keys(
		state,
		SAVE_CODEC.STATE_KEYS + SAVE_CODEC.OPTIONAL_STATE_KEYS,
	):
		return _command_failure(
			"SAVE_SERIALIZATION_FAILED",
			["世界快照键集合与 SaveCodec 域清单不一致"],
		)
	var encoded_state := SAVE_CODEC.encode_checked(state) as Dictionary
	if encoded_state.get("ok") != true:
		return _command_failure(
			"SAVE_SERIALIZATION_FAILED",
			(encoded_state.get("errors", ["世界状态包含不能序列化的数据"]) as Array).duplicate(),
		)
	var snapshot := {
		"schema": SAVE_CODEC.SCHEMA,
		"schemaVersion": SAVE_CODEC.SCHEMA_VERSION,
		"worldId": String(_world_data.get("worldId", "")),
		"worldDataSchemaVersion": int(_world_data.get("schemaVersion", 0)),
		"worldDataVersion": int(_world_data.get("dataVersion", 0)),
		"savedAt": get_time(),
		"state": encoded_state.get("value", {}),
	}
	# 可序列化性由 SAVE_CODEC 编码阶段保证，不再整包 stringify+parse 验证一遍。
	return _decorate_command_result({"ok": true, "snapshot": snapshot})

func _indoor_layout_override_snapshots() -> Array:
	var result := []
	var space_ids: Array = _indoor_layout_overrides.keys()
	space_ids.sort()
	for space_id_value: Variant in space_ids:
		result.append(
			(_indoor_layout_overrides[space_id_value] as Dictionary).duplicate(true)
		)
	return result

func prepare_save_candidate() -> Dictionary:
	if not _world_log_consistency_error.is_empty():
		return _command_failure(
			"WORLD_LOG_CONSISTENCY_ERROR",
			[_world_log_consistency_error],
		)
	var snapshot_result := create_save_snapshot()
	if snapshot_result.get("ok") != true:
		return snapshot_result
	var snapshot := (
		snapshot_result.get("snapshot", {}) as Dictionary
	).duplicate(true)
	var world_log_snapshot := _world_log_store.create_save_snapshot(
		_world_revision,
	) as Dictionary
	if world_log_snapshot.is_empty():
		return _command_failure(
			"WORLD_LOG_SNAPSHOT_INVALID",
			["世界日志无法生成保存快照"],
		)
	var restore_compatibility := _prepare_snapshot_state_for_restore(
		_world_data,
		_opening,
		snapshot,
	)
	if restore_compatibility.get("ok") != true:
		return _command_failure(
			"WORLD_SAVE_RESTORE_VALIDATION_FAILED",
			restore_compatibility.get(
				"errors",
				["当前 World 状态无法生成可恢复存档"],
			) as Array,
		)
	var identity_snapshot: Variant = get_resident_identity_snapshot()
	var resident_ids_result := _save_resident_ids_from_identity_snapshot(
		identity_snapshot,
	) as Dictionary
	if resident_ids_result.get("ok") != true:
		return _command_failure(
			"WORLD_SAVE_IDENTITY_INVALID",
			resident_ids_result.get(
				"errors",
				["当前居民身份无法生成 World 保存候选"],
			) as Array,
		)
	_save_candidate_sequence += 1
	var token := "world-save-g%d-c%d" % [_runtime_generation, _save_candidate_sequence]
	var candidate := {
		"token": token,
		"state": "prepared",
		"sourceGeneration": _runtime_generation,
		"worldRevision": _world_revision,
		"snapshot": snapshot,
		"worldLogSnapshot": world_log_snapshot,
		"snapshotRef": "",
		"worldLogSnapshotRef": "",
		"identitySnapshot": (identity_snapshot as Dictionary).duplicate(true),
		"residentIds": (
			resident_ids_result.get("residentIds", []) as Array
		).duplicate(),
	}
	_save_candidates[token] = candidate
	return _decorate_command_result({
		"ok": true,
		"candidate": _save_candidate_projection(candidate),
		"snapshot": snapshot.duplicate(true),
		"worldLogSnapshot": world_log_snapshot.duplicate(true),
	})

func _prepare_snapshot_state_for_restore(
	world_data: Dictionary,
	opening_config: Dictionary,
	snapshot: Dictionary,
) -> Dictionary:
	var errors: Array[String] = []
	errors.append_array(
		SAVE_CODEC.validate_envelope(
			snapshot,
			world_data,
			opening_config,
		),
	)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var decoded := SAVE_CODEC.decode_checked(
		snapshot.get("state", {}),
	) as Dictionary
	if decoded.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				decoded.get(
					"errors",
					["世界存档反序列化失败"],
				) as Array
			).duplicate(true),
		}
	return RESTORE_STATE.prepare_full(
		self,
		world_data,
		opening_config,
		decoded.get("value", {}) as Dictionary,
	)

func validate_save_candidate(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _save_candidates.has(normalized):
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_NOT_FOUND",
			["World 保存候选不存在：%s" % normalized],
		)
	var candidate := _save_candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if not ["prepared", "committed"].has(state):
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_STATE_INVALID",
			["World 保存候选当前状态不能校验：%s" % state],
			{"candidate": _save_candidate_projection(candidate)},
		)
	if state == "prepared" and (
		not _running
		or int(candidate.get("sourceGeneration", -1)) != _runtime_generation
		or int(candidate.get("worldRevision", -1)) != _world_revision
	):
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_STALE",
			["World 保存候选来自已经变化的运行世代或 revision"],
			{"candidate": _save_candidate_projection(candidate)},
			true,
		)
	var snapshot := candidate.get("snapshot", {}) as Dictionary
	var world_log_snapshot := (
		candidate.get("worldLogSnapshot", {}) as Dictionary
	)
	# 快照由编码阶段保证 JSON 合法，这里只做存在性检查，
	# 不再对约 3MB 的候选整包 stringify+parse。
	if snapshot.is_empty():
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_INVALID",
			["World 保存候选不再是合法 JSON 快照"],
			{"candidate": _save_candidate_projection(candidate)},
		)
	if world_log_snapshot.is_empty():
		return _command_failure(
			"WORLD_LOG_SNAPSHOT_INVALID",
			["世界日志保存候选不再是合法 JSON 快照"],
			{"candidate": _save_candidate_projection(candidate)},
		)
	return _decorate_command_result({
		"ok": true,
		"candidate": _save_candidate_projection(candidate),
		"snapshot": snapshot.duplicate(true),
	})

func commit_save_candidate(
	token: String,
	snapshot_ref: String,
	world_log_snapshot_ref := "",
) -> Dictionary:
	var normalized_token := token.strip_edges()
	var normalized_ref := snapshot_ref.strip_edges()
	var normalized_log_ref := String(world_log_snapshot_ref).strip_edges()
	if normalized_ref.is_empty():
		return _command_failure(
			"WORLD_SAVE_SNAPSHOT_REF_INVALID",
			["World snapshotRef 不能为空"],
		)
	if not _save_candidates.has(normalized_token):
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_NOT_FOUND",
			["World 保存候选不存在：%s" % normalized_token],
		)
	var candidate := _save_candidates[normalized_token] as Dictionary
	var state := String(candidate.get("state", ""))
	if state == "committed":
		if String(candidate.get("snapshotRef", "")) != normalized_ref:
			return _command_failure(
				"WORLD_SAVE_CANDIDATE_STATE_INVALID",
				["已提交的 World 保存候选不能更换 snapshotRef"],
				{"candidate": _save_candidate_projection(candidate)},
			)
		if (
			String(candidate.get("worldLogSnapshotRef", ""))
			!= normalized_log_ref
		):
			return _command_failure(
				"WORLD_SAVE_CANDIDATE_STATE_INVALID",
				["已提交的 World 保存候选不能更换世界日志 snapshotRef"],
				{"candidate": _save_candidate_projection(candidate)},
			)
		return _decorate_command_result({
			"ok": true,
			"candidate": _save_candidate_projection(candidate),
			"worldComponent": _save_candidate_world_component(candidate),
			"worldLogComponent": _save_candidate_world_log_component(candidate),
		})
	if state != "prepared":
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_STATE_INVALID",
			["World 保存候选只能从 prepared 提交"],
			{"candidate": _save_candidate_projection(candidate)},
		)
	var validation := validate_save_candidate(normalized_token)
	if validation.get("ok") != true:
		return validation
	candidate["state"] = "committed"
	candidate["snapshotRef"] = normalized_ref
	candidate["worldLogSnapshotRef"] = normalized_log_ref
	_save_candidates[normalized_token] = candidate
	return _decorate_command_result({
		"ok": true,
		"candidate": _save_candidate_projection(candidate),
		"worldComponent": _save_candidate_world_component(candidate),
		"worldLogComponent": _save_candidate_world_log_component(candidate),
	})

func abort_save_candidate(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _save_candidates.has(normalized):
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_NOT_FOUND",
			["World 保存候选不存在：%s" % normalized],
		)
	var candidate := _save_candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if state == "aborted":
		return _decorate_command_result({
			"ok": true,
			"candidate": _save_candidate_projection(candidate),
			"cleanupSnapshotRef": String(candidate.get("snapshotRef", "")),
		})
	if not ["prepared", "committed"].has(state):
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_STATE_INVALID",
			["World 保存候选当前状态不能中止：%s" % state],
			{"candidate": _save_candidate_projection(candidate)},
		)
	candidate["state"] = "aborted"
	_save_candidates[normalized] = candidate
	return _decorate_command_result({
		"ok": true,
		"candidate": _save_candidate_projection(candidate),
		"cleanupSnapshotRef": String(candidate.get("snapshotRef", "")),
	})

func cleanup_save_candidate(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _save_candidates.has(normalized):
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_NOT_FOUND",
			["World 保存候选不存在：%s" % normalized],
		)
	var candidate := _save_candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if not ["committed", "aborted"].has(state):
		return _command_failure(
			"WORLD_SAVE_CANDIDATE_STATE_INVALID",
			["World 保存候选必须先提交或中止才能清理"],
			{"candidate": _save_candidate_projection(candidate)},
		)
	var projection := _save_candidate_projection(candidate)
	_save_candidates.erase(normalized)
	return _decorate_command_result({
		"ok": true,
		"candidate": projection,
		"cleanupSnapshotRef": String(candidate.get("snapshotRef", "")),
	})

func prepare_restore_candidate(
	world_data: Dictionary,
	opening_config: Dictionary,
	snapshot: Dictionary,
	resident_identities: Variant = [],
	require_world_ready := true,
	world_log_snapshot: Dictionary = {},
) -> Dictionary:
	var prepared_identities := OPENING_CONFIG.prepare_resident_identities(
		opening_config,
		resident_identities,
		require_world_ready,
	) as Dictionary
	if _running and _resident_identity_status == "confirmed":
		var requested_identity_snapshot := {
			"status": String(prepared_identities.get("status", "")),
			"residents": (prepared_identities.get("residents", []) as Array).duplicate(true),
		}
		if prepared_identities.get("ok") != true or requested_identity_snapshot != get_resident_identity_snapshot():
			return _command_failure(
				"WORLD_RESTORE_IDENTITY_DRIFT",
				["恢复身份集合与当前 World 权威身份集合不一致"],
			)
	var startup_validation := validate_startup(
		world_data,
		opening_config,
		require_world_ready,
		resident_identities,
	)
	if startup_validation.get("ok") != true:
		return startup_validation
	var restore_compatibility := _prepare_snapshot_state_for_restore(
		world_data,
		opening_config,
		snapshot,
	)
	if restore_compatibility.get("ok") != true:
		return _command_failure(
			"SAVE_SNAPSHOT_INVALID",
			restore_compatibility.get(
				"errors",
				["世界存档无法恢复"],
			) as Array,
		)
	var prepared := (
		restore_compatibility.get("preparedState", {}) as Dictionary
	)
	var prepared_world_log: RefCounted = WORLD_LOG_STORE.new()
	var world_log_restore := prepared_world_log.restore_save_snapshot(
		world_log_snapshot.duplicate(true),
		prepared,
	) as Dictionary
	if world_log_restore.get("ok") != true:
		return _command_failure(
			"WORLD_LOG_SNAPSHOT_INVALID",
			["世界日志存档无法恢复"],
		)
	_restore_candidate_sequence += 1
	var token := "world-restore-g%d-c%d" % [_runtime_generation, _restore_candidate_sequence]
	var candidate := {
		"token": token,
		"state": "prepared",
		"baseGeneration": _runtime_generation,
		"baseWorldRevision": _world_revision,
		"requireWorldReady": require_world_ready,
		"worldData": world_data.duplicate(true),
		"openingConfig": opening_config.duplicate(true),
		"preparedIdentities": prepared_identities,
		"preparedState": prepared,
		"preparedWorldLog": prepared_world_log,
		"snapshotSchemaVersion": int(snapshot.get("schemaVersion", 0)),
		"savedWorldRevision": int(
			(prepared.get("sequences", {}) as Dictionary).get(
				"worldRevision",
				0,
			),
		),
	}
	_restore_candidates[token] = candidate
	return _decorate_command_result({
		"ok": true,
		"candidate": _restore_candidate_projection(candidate),
	})

func validate_restore_candidate(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _restore_candidates.has(normalized):
		return _command_failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _restore_candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if state != "prepared":
		return _command_failure(
			"WORLD_RESTORE_CANDIDATE_STATE_INVALID",
			["World 恢复候选当前状态不能校验：%s" % state],
			{"candidate": _restore_candidate_projection(candidate)},
		)
	if (
		int(candidate.get("baseGeneration", -1)) != _runtime_generation
		or int(candidate.get("baseWorldRevision", -1)) != _world_revision
	):
		return _command_failure(
			"WORLD_RESTORE_CANDIDATE_STALE",
			["World 在恢复准备后已经发生变化，必须重新 prepare"],
			{"candidate": _restore_candidate_projection(candidate)},
			true,
		)
	return _decorate_command_result({
		"ok": true,
		"candidate": _restore_candidate_projection(candidate),
	})

func commit_restore_candidate(token: String) -> Dictionary:
	return _commit_restore_candidate(token, true)

func commit_restore_candidate_for_observer(token: String) -> Dictionary:
	return _commit_restore_candidate(token, false)

func _commit_restore_candidate(
	token: String,
	player_avatar_present: bool,
) -> Dictionary:
	var normalized := token.strip_edges()
	if not _restore_candidates.has(normalized):
		return _command_failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _restore_candidates[normalized] as Dictionary
	if String(candidate.get("state", "")) == "committed":
		return _decorate_command_result({
			"ok": true,
			"candidate": _restore_candidate_projection(candidate),
			"summary": (
				candidate.get("commitSummary", {}) as Dictionary
			).duplicate(true),
			"commitReceipt": (
				candidate.get("commitReceipt", {}) as Dictionary
			).duplicate(true),
		})
	var validation := validate_restore_candidate(normalized)
	if validation.get("ok") != true:
		return validation
	var summary := _apply_prepared_restore_candidate(
		candidate,
		player_avatar_present,
	)
	var receipt := {
		"token": normalized,
		"runtimeGeneration": _runtime_generation,
		"worldRevision": _world_revision,
		"identitySnapshot": get_resident_identity_snapshot(),
	}
	candidate["state"] = "committed"
	candidate["commitGeneration"] = _runtime_generation
	candidate["commitWorldRevision"] = _world_revision
	candidate["commitSummary"] = summary.duplicate(true)
	candidate["commitReceipt"] = receipt.duplicate(true)
	_release_restore_candidate_payload(candidate)
	_restore_candidates[normalized] = candidate
	return _decorate_command_result({
		"ok": true,
		"candidate": _restore_candidate_projection(candidate),
		"summary": summary,
		"commitReceipt": receipt,
	})

func abort_restore_candidate(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _restore_candidates.has(normalized):
		return _command_failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _restore_candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if state == "aborted":
		return _decorate_command_result({
			"ok": true,
			"candidate": _restore_candidate_projection(candidate),
		})
	if state != "prepared":
		return _command_failure(
			"WORLD_RESTORE_CANDIDATE_STATE_INVALID",
			["World 恢复候选只能在 prepared 状态中止"],
			{"candidate": _restore_candidate_projection(candidate)},
		)
	candidate["state"] = "aborted"
	_release_restore_candidate_payload(candidate)
	_restore_candidates[normalized] = candidate
	return _decorate_command_result({
		"ok": true,
		"candidate": _restore_candidate_projection(candidate),
	})

# 提交/中止后候选只剩投影需要的轻量字段；释放约 3MB 的重载荷，用后即清。
func _release_restore_candidate_payload(candidate: Dictionary) -> void:
	candidate.erase("worldData")
	candidate.erase("openingConfig")
	candidate.erase("preparedState")
	candidate.erase("preparedWorldLog")

func cleanup_restore_candidate(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _restore_candidates.has(normalized):
		return _command_failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _restore_candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if not ["committed", "aborted"].has(state):
		return _command_failure(
			"WORLD_RESTORE_CANDIDATE_STATE_INVALID",
			["World 恢复候选必须先提交或中止才能清理"],
			{"candidate": _restore_candidate_projection(candidate)},
		)
	var projection := _restore_candidate_projection(candidate)
	_restore_candidates.erase(normalized)
	return _decorate_command_result({"ok": true, "candidate": projection})

func restore_from_snapshot(
	world_data: Dictionary,
	opening_config: Dictionary,
	snapshot: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	var preparation := prepare_restore_candidate(
		world_data,
		opening_config,
		snapshot,
		resident_identities,
		false,
	)
	if preparation.get("ok") != true:
		return preparation
	var token := String((preparation.get("candidate", {}) as Dictionary).get("token", ""))
	var result := commit_restore_candidate(token)
	if result.get("ok") == true:
		cleanup_restore_candidate(token)
	else:
		abort_restore_candidate(token)
	return result

func _advance_resident_arrivals(absolute_minute: int) -> void:
	RESIDENT_ARRIVAL_RUNTIME.advance(
		self, absolute_minute,
		IDLE_RESIDENT_CLEARANCE_PX,
	)

# advance 分项计时:启用时把上一步耗时累入 profile 并返回新起点;关闭时零分配。
func _advance_profile_lap(profile: Dictionary, key: String, lap_started_usec: int) -> int:
	if not _advance_profile_enabled:
		return 0
	var now_usec := Time.get_ticks_usec()
	profile[key] = int(profile.get(key, 0)) + int(now_usec - lap_started_usec)
	return now_usec

func _advance_profile_count(key: String, amount: int) -> void:
	if _advance_profile_enabled:
		_advance_profile_scratch[key] = (
			int(_advance_profile_scratch.get(key, 0)) + amount
		)
func _reset_deferred_frame_work() -> void:
	FRAME_BUDGET_RUNTIME.reset(self)
	ACTIVITY_REACHABILITY_CACHE.clear(self)


func _finish_advance_profile(advance_started_usec: int) -> void:
	if not _advance_profile_enabled:
		return
	_advance_profile_scratch["totalUsec"] = (
		Time.get_ticks_usec() - advance_started_usec
	)
	_last_advance_profile = _advance_profile_scratch


func _defer_perception_refresh() -> void:
	FRAME_BUDGET_RUNTIME.defer_perception_refresh(self)


func _queue_resident_state_refresh(resident_id: String) -> void:
	FRAME_BUDGET_RUNTIME.queue_resident_state_refresh(self, resident_id)


func _queue_resident_place_change_signal(
	resident_id: String,
	place_change: Dictionary,
) -> void:
	FRAME_BUDGET_RUNTIME.queue_resident_place_change_signal(self, resident_id, place_change)


func advance(real_seconds: float) -> Dictionary:
	var advance_started_usec := (
		Time.get_ticks_usec() if _advance_profile_enabled else 0
	)
	var advance_profile: Dictionary = {}
	_advance_profile_scratch = advance_profile
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if is_paused():
		return _decorate_command_result({
			"ok": true,
			"paused": true,
			"simulationSpeed": _simulation_speed,
			"pauseReasons": get_lifecycle_state().get("pauseReasons", []),
			"minutesAdvanced": 0,
			"events": [],
		})
	var deferred_work := FRAME_BUDGET_RUNTIME.process_deferred_work(
		self,
		advance_profile,
	)
	var processed_presentation_refreshes := int(deferred_work.get("presentationProcessed", 0))
	var processed_place_change_signals := int(deferred_work.get("placeProcessed", 0))
	var processed_deferred_perception := bool(deferred_work.get("perceptionProcessed", false))
	CONVERSATION_RUNTIME._advance_autonomous_conversation_timeouts(
		self,
		real_seconds,
	)
	var environment_update := _environment.advance(
		real_seconds * float(_simulation_speed),
	) as Dictionary
	if int(environment_update.get("minutesAdvanced", 0)) > 0:
		_bump_world_revision(false)
	for time_value: Variant in environment_update.get("minuteTicks", []) as Array:
		var minute_tick := time_value as Dictionary
		# 环境时钟在 advance 开头一次性推进到终态;逐分钟结算期间,
		# "现在几点"必须取当前 tick 的分钟,否则一次多分钟推进会把
		# 结算中产生的时限(如服务等待窗口)错定到未来。
		_processing_tick_absolute_minute = _absolute_minute(minute_tick)
		_tick_weather_override = String(
			minute_tick.get("weather", ""),
		)
		if bool(minute_tick.get("weatherChanged", false)):
			_interrupt_unsafe_weather_activities()
		var absolute_minute := _absolute_minute(minute_tick)
		var lap_usec := Time.get_ticks_usec() if _advance_profile_enabled else 0
		_advance_resident_arrivals(absolute_minute)
		lap_usec = _advance_profile_lap(advance_profile, "residentArrivalsUsec", lap_usec)
		_advance_actions(absolute_minute)
		lap_usec = _advance_profile_lap(advance_profile, "actionsUsec", lap_usec)
		_advance_resident_conditions(absolute_minute)
		lap_usec = _advance_profile_lap(advance_profile, "residentConditionsUsec", lap_usec)
		_advance_conflict_runtime()
		lap_usec = _advance_profile_lap(advance_profile, "conflictUsec", lap_usec)
		_expire_time_sensitive_private_messages(absolute_minute)
		lap_usec = _advance_profile_lap(advance_profile, "privateMessageExpiryUsec", lap_usec)
		DINING_SERVICE.settle_period_close(self, absolute_minute)
		_sync_occupation_service_presence(absolute_minute)
		lap_usec = _advance_profile_lap(advance_profile, "occupationPresenceUsec", lap_usec)
		_advance_social_matters(absolute_minute)
		lap_usec = _advance_profile_lap(advance_profile, "socialMattersUsec", lap_usec)
		_advance_announcement_schedules(absolute_minute)
		_advance_passive_activity_needs(absolute_minute)
		lap_usec = _advance_profile_lap(advance_profile, "passiveNeedsUsec", lap_usec)
		if posmod(absolute_minute, 30) == 0:
			_staffing.rebuild_if_dependencies_changed(
				_residents,
				absolute_minute,
			)
			lap_usec = _advance_profile_lap(advance_profile, "staffingRebuildUsec", lap_usec)
			_refresh_place_service_staffing()
			lap_usec = _advance_profile_lap(advance_profile, "placeServiceUsec", lap_usec)
			_sync_staffing_matters()
			lap_usec = _advance_profile_lap(advance_profile, "staffingMattersUsec", lap_usec)
			_sync_production_tasks(absolute_minute)
			lap_usec = _advance_profile_lap(advance_profile, "productionTasksUsec", lap_usec)
		FRAME_BUDGET_RUNTIME.refresh_or_defer_perception(self)
		lap_usec = _advance_profile_lap(advance_profile, "perceptionUsec", lap_usec)
		_schedule_life_rhythm_decisions(absolute_minute)
		lap_usec = _advance_profile_lap(advance_profile, "lifeRhythmUsec", lap_usec)
	_processing_tick_absolute_minute = -1
	_tick_weather_override = ""
	for event_value: Variant in environment_update.get("events", []) as Array:
		var environment_event := event_value as Dictionary
		_broadcast_event(environment_event)
	if int(environment_update.get("minutesAdvanced", 0)) > 0:
		_notify_world_revision()
		environment_changed.emit(get_time(), get_weather())
	_advance_confirmed_action_previews(real_seconds)
	_finish_advance_profile(advance_started_usec)
	# advance 是逐帧热路径：返回值就地构造，不走 _decorate_command_result 的整体深拷贝；
	# events 多数帧为空，只在非空时拷贝。
	var advanced_events := environment_update.get("events", []) as Array
	return {
		"ok": true,
		"observationPreviewActive": _has_observed_action_preview(),
		"simulationSpeed": _simulation_speed,
		"minutesAdvanced": int(environment_update.get("minutesAdvanced", 0)),
		"events": advanced_events.duplicate(true) if not advanced_events.is_empty() else [],
		"deferredPresentationRefreshesProcessed": processed_presentation_refreshes,
		"deferredPresentationRefreshCount": _deferred_resident_state_refreshes.size(),
		"deferredPlaceChangeSignalsProcessed": processed_place_change_signals,
		"deferredPlaceChangeSignalCount": _deferred_resident_place_change_signals.size(),
		"deferredPerceptionProcessed": processed_deferred_perception,
		"errorCode": "",
		"retryable": false,
		"worldRevision": _world_revision,
	}

func set_advance_profile_enabled(enabled: bool) -> void:
	_advance_profile_enabled = enabled
	if not enabled:
		_last_advance_profile.clear()

func get_last_advance_profile() -> Dictionary:
	return _last_advance_profile.duplicate(true)

func set_weather(weather: String) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var result := _environment.set_weather(weather) as Dictionary
	if result.get("changed") == true:
		_bump_world_revision(false)
		_pause_active_conversation_follow_ups_for_reconsideration(
			"天气已经变为%s，需要重新决定是否继续刚才的约定" % String(result.get("weather", weather)),
		)
		_broadcast_event(result.get("event", {}) as Dictionary)
		_interrupt_unsafe_weather_activities()
		_notify_world_revision()
		environment_changed.emit(get_time(), get_weather())
	return _decorate_command_result(result, "INVALID_WEATHER")

func cycle_time_period_for_test() -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var previous_absolute := int(_environment.get_absolute_minute())
	var result := _environment.cycle_time_period() as Dictionary
	if result.get("ok") == true:
		_bump_world_revision(false)
	var current_absolute := int(_environment.get_absolute_minute())
	for absolute_minute in range(previous_absolute + 1, current_absolute + 1):
		_advance_resident_arrivals(absolute_minute)
		_advance_actions(absolute_minute)
		_advance_resident_conditions(absolute_minute)
		_advance_social_matters(absolute_minute)
		_advance_announcement_schedules(absolute_minute)
		_advance_passive_activity_needs(absolute_minute)
		PERCEPTION_RUNTIME._refresh_perception(self, true)
		_schedule_life_rhythm_decisions(absolute_minute)
	if result.get("ok") == true:
		_notify_world_revision()
	environment_changed.emit(get_time(), get_weather())
	return _decorate_command_result(result, "INVALID_TIME")

func queue_weather_roll(value: float) -> void:
	if _environment != null:
		_environment.queue_weather_roll(value)

func _resident_save_snapshot(resident_id: String) -> Dictionary:
	var resident := _residents[resident_id] as Dictionary
	var pending_events := _deduplicated_world_events(
		(resident.get("inflightEvents", []) as Array).duplicate(true)
	)
	pending_events.append_array(
		(resident.get("eventQueue", []) as Array).duplicate(true)
	)
	pending_events = _deduplicated_world_events(pending_events)
	var pending_results := (resident.get("inflightResults", []) as Array).duplicate(true)
	pending_results.append_array((resident.get("resultQueue", []) as Array).duplicate(true))
	pending_results = _deduplicated_action_results(pending_results)
	var used_action_ids: Array = (resident.get("usedActionIds", {}) as Dictionary).keys()
	used_action_ids.sort()
	return {
		"residentId": resident_id,
		"name": String((resident.get("attributes", {}) as Dictionary).get("name", "")),
		"movementRevision": int(resident.get("movementRevision", 1)),
		"profileAttributes": _saved_profile_attributes(
			resident.get("attributes", {}) as Dictionary,
		),
		"socialState": (resident.get("socialState", {}) as Dictionary).duplicate(true),
		"arrivalState": (
			resident.get(
				"arrivalState",
				{
					"status": "arrived",
					"scheduledAbsoluteMinute": -1,
					"arrivedAbsoluteMinute": -1,
				},
			) as Dictionary
		).duplicate(true),
		"position": resident.get("position", Vector2.ZERO),
		"spaceId": String(resident.get("spaceId", "")),
		"regionId": String(resident.get("regionId", "")),
		"currentPlace": String(resident.get("currentPlace", "")),
		"doing": String(resident.get("doing", "")),
		"body": (resident.get("body", {}) as Dictionary).duplicate(true),
		"activityState": (
			resident.get("activityState", _empty_activity_state()) as Dictionary
		).duplicate(true),
		"attendanceState": (
			resident.get(
				"attendanceState",
				{"status": "available", "untilMinute": -1},
			) as Dictionary
		).duplicate(true),
		"currentAction": (resident.get("currentAction", {}) as Dictionary).duplicate(true),
		"confirmedActionPreview": _saved_confirmed_action_preview(resident),
		"actionSuspendedAbsoluteMinute": int(
			resident.get("actionSuspendedAbsoluteMinute", -1),
		),
		"routeConnector": (resident.get("routeConnector", []) as Array).duplicate(true),
		"conversationId": String(resident.get("conversationId", "")),
		"conversation": _duplicate_optional_dictionary(resident.get("conversation")),
		"pendingEvents": pending_events,
		"pendingActionResults": pending_results,
		"usedActionIds": used_action_ids,
	}

func _sync_activity_save_state() -> void:
	var absolute_minute := int(_environment.get_absolute_minute())
	for resident_id in _resident_order:
		var resident := _residents[resident_id] as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		var execution := _activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if execution.is_empty():
			continue
		var effective_minute := (
			int(resident.get("actionSuspendedAbsoluteMinute", -1))
			if int(resident.get("actionSuspendedAbsoluteMinute", -1)) >= 0
			else absolute_minute
		)
		var elapsed := maxi(
			0,
			effective_minute - int(
				action.get("startedAbsoluteMinute", effective_minute)
			),
		)
		_activity_runtime.sync_remaining_ticks(
			resident_id,
			maxi(
				0,
				_prop_approach_duration_minutes(action)
				+ int(action.get("durationMinutes", 0))
				- elapsed,
			),
		)

func _reconcile_activity_routines_before_save() -> void:
	_activity_runtime.reconcile_activity_routines_before_save(
		_activity_routines,
		_residents,
		Callable(self, "_append_action_result_without_schedule"),
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_DIRECT,
	)
func _activity_routine_save_snapshot() -> Dictionary:
	var routines: Array[Dictionary] = []
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in _activity_routines:
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	for resident_id in resident_ids:
		var routine := (
			_activity_routines[resident_id] as Dictionary
		).duplicate(true)
		routine["residentId"] = resident_id
		routines.append(routine)
	return {
		"schemaVersion": 1,
		"routines": routines,
	}

func _private_message_save_snapshot() -> Dictionary:
	_compact_delivered_private_messages()
	var messages: Array[Dictionary] = []
	var message_ids: Array[String] = []
	for message_id_value: Variant in _private_messages:
		message_ids.append(String(message_id_value))
	message_ids.sort()
	for message_id: String in message_ids:
		messages.append(
			(
				_private_messages.get(message_id, {}) as Dictionary
			).duplicate(true),
		)
	return {
		"schemaVersion": 4,
		"sequence": _private_message_sequence,
		"messages": messages,
		"archiveSummary": _private_message_archive_summary.duplicate(true),
	}

func _public_private_message(message: Dictionary) -> Dictionary:
	var sender_id := String(message.get("senderResidentId", ""))
	var recipient_id := String(
		message.get("recipientResidentId", ""),
	)
	return {
		"message_id": String(message.get("messageId", "")),
		"sender_resident_id": sender_id,
		"sender_name": _resident_display_name(sender_id),
		"recipient_resident_id": recipient_id,
		"recipient_name": _resident_display_name(recipient_id),
		"content": String(message.get("content", "")),
		"message_kind": String(message.get("messageKind", "private")),
		"announcement_id": String(message.get("announcementId", "")),
		"expires_at_minute": int(message.get("expiresAtMinute", -1)),
		"source_ref": String(message.get("sourceRef", "")),
		"state": String(message.get("state", "")),
		"created_at_minute": int(
			message.get("createdAtMinute", 0),
		),
		"delivered_at_minute": int(
			message.get("deliveredAtMinute", -1),
		),
		"delivered_by_resident_id": String(
			message.get("deliveredByResidentId", ""),
		),
	}

func _save_candidate_projection(candidate: Dictionary) -> Dictionary:
	var snapshot := candidate.get("snapshot", {}) as Dictionary
	return {
		"token": String(candidate.get("token", "")),
		"state": String(candidate.get("state", "")),
		"sourceGeneration": int(candidate.get("sourceGeneration", -1)),
		"worldRevision": int(candidate.get("worldRevision", 0)),
		"schema": String(snapshot.get("schema", "")),
		"schemaVersion": int(snapshot.get("schemaVersion", 0)),
		"worldId": String(snapshot.get("worldId", "")),
		"worldDataSchemaVersion": int(snapshot.get("worldDataSchemaVersion", 0)),
		"worldDataVersion": int(snapshot.get("worldDataVersion", 0)),
		"identitySnapshot": (
			candidate.get("identitySnapshot", {}) as Dictionary
		).duplicate(true),
		"residentIds": (
			candidate.get("residentIds", []) as Array
		).duplicate(),
		"snapshotRef": String(candidate.get("snapshotRef", "")),
		"worldLogSnapshotRef": String(
			candidate.get("worldLogSnapshotRef", ""),
		),
	}


func _save_resident_ids_from_identity_snapshot(
	identity_snapshot: Variant,
) -> Dictionary:
	var errors: Array[String] = []
	if not identity_snapshot is Dictionary:
		return {
			"ok": false,
			"errors": ["identitySnapshot 必须是对象"],
		}
	var identity := identity_snapshot as Dictionary
	if not SAVE_CODEC.has_exact_string_keys(
		identity,
		["status", "residents"],
	):
		errors.append("identitySnapshot 字段必须严格为 status、residents")
	var status_value: Variant = identity.get("status")
	if (
		not status_value is String
		or status_value != _resident_identity_status
	):
		errors.append("identitySnapshot.status 必须保持当前居民身份状态")
	var residents_value: Variant = identity.get("residents")
	if not residents_value is Array:
		errors.append("identitySnapshot.residents 必须是数组")
		return {"ok": false, "errors": errors}
	var resident_ids: Array[String] = []
	var resident_names := {}
	for index in (residents_value as Array).size():
		var resident_value: Variant = (residents_value as Array)[index]
		if not resident_value is Dictionary:
			errors.append("identitySnapshot.residents[%d] 必须是对象" % index)
			continue
		var resident := resident_value as Dictionary
		if not SAVE_CODEC.has_exact_string_keys(
			resident,
			["residentId", "residentName"],
		):
			errors.append(
				"identitySnapshot.residents[%d] 字段必须严格为 residentId、residentName"
				% index,
			)
			continue
		var resident_id_value: Variant = resident.get("residentId")
		var resident_name_value: Variant = resident.get("residentName")
		if (
			not resident_id_value is String
			or (resident_id_value as String).is_empty()
			or resident_id_value != (resident_id_value as String).strip_edges()
			or not _save_resident_id_is_safe(resident_id_value as String)
		):
			errors.append(
				"identitySnapshot.residents[%d].residentId 无效" % index,
			)
			continue
		var resident_id := resident_id_value as String
		if (
			not resident_name_value is String
			or (resident_name_value as String).is_empty()
			or resident_name_value != (resident_name_value as String).strip_edges()
		):
			errors.append(
				"identitySnapshot.residents[%d].residentName 无效" % index,
			)
			continue
		if resident_names.has(resident_id):
			errors.append("identitySnapshot residentId 重复：%s" % resident_id)
			continue
		resident_ids.append(resident_id)
		resident_names[resident_id] = resident_name_value as String
	resident_ids.sort()
	var authoritative_ids := _resident_order.duplicate()
	authoritative_ids.sort()
	if resident_ids != authoritative_ids:
		errors.append("identitySnapshot 居民集合与当前 World 权威居民集合不一致")
	else:
		for resident_id in authoritative_ids:
			if (
				String(resident_names.get(resident_id, ""))
				!= String(_resident_name_by_id.get(resident_id, ""))
			):
				errors.append(
					"identitySnapshot 居民显示名称与当前 World 权威身份不一致：%s"
					% resident_id,
				)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {
		"ok": true,
		"errors": [],
		"residentIds": resident_ids,
	}


func _save_resident_id_is_safe(resident_id: String) -> bool:
	if resident_id.is_empty() or resident_id.length() > 128:
		return false
	for character in resident_id:
		var code := character.unicode_at(0)
		var is_ascii_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_ascii_letter and not is_digit and character not in ["_", "-"]:
			return false
	return true


func _saved_confirmed_action_preview(resident: Dictionary) -> Dictionary:
	# Keep the save key for schema compatibility, but observation previews are
	# deliberately never persisted or replayed.
	return {}


func _save_candidate_world_component(candidate: Dictionary) -> Dictionary:
	var snapshot := candidate.get("snapshot", {}) as Dictionary
	return {
		"worldRevision": int(candidate.get("worldRevision", 0)),
		"snapshotRef": String(candidate.get("snapshotRef", "")),
		"schema": String(snapshot.get("schema", "")),
		"schemaVersion": int(snapshot.get("schemaVersion", 0)),
		"worldDataVersion": int(snapshot.get("worldDataVersion", 0)),
		"day": int((snapshot.get("savedAt", {}) as Dictionary).get("day", 0)),
	}


func _save_candidate_world_log_component(candidate: Dictionary) -> Dictionary:
	var snapshot := candidate.get("worldLogSnapshot", {}) as Dictionary
	return {
		"snapshotRef": String(candidate.get("worldLogSnapshotRef", "")),
		"schema": String(snapshot.get("schema", "")),
		"schemaVersion": int(snapshot.get("schemaVersion", 0)),
		"timelineId": String(snapshot.get("timelineId", "")),
		"maxSequence": int(snapshot.get("maxSequence", 0)),
		"worldRevision": int(snapshot.get("worldRevision", 0)),
	}


func _restore_candidate_projection(candidate: Dictionary) -> Dictionary:
	var result := {
		"token": String(candidate.get("token", "")),
		"state": String(candidate.get("state", "")),
		"baseGeneration": int(candidate.get("baseGeneration", -1)),
		"baseWorldRevision": int(candidate.get("baseWorldRevision", 0)),
		"requireWorldReady": bool(candidate.get("requireWorldReady", true)),
		"snapshotSchemaVersion": int(candidate.get("snapshotSchemaVersion", 0)),
		"savedWorldRevision": int(candidate.get("savedWorldRevision", 0)),
		"identitySnapshot": {
			"status": String(
				(candidate.get("preparedIdentities", {}) as Dictionary).get("status", ""),
			),
			"residents": (
				(candidate.get("preparedIdentities", {}) as Dictionary).get("residents", []) as Array
			).duplicate(true),
		},
	}
	if candidate.has("commitGeneration"):
		result["commitGeneration"] = int(candidate.get("commitGeneration", -1))
		result["commitWorldRevision"] = int(candidate.get("commitWorldRevision", 0))
	return result


func _apply_prepared_restore_candidate(
	candidate: Dictionary,
	player_avatar_present: bool,
) -> Dictionary:
	var world_data := candidate.get("worldData", {}) as Dictionary
	var opening_config := candidate.get("openingConfig", {}) as Dictionary
	var prepared_identities := candidate.get("preparedIdentities", {}) as Dictionary
	var prepared := candidate.get("preparedState", {}) as Dictionary
	var prepared_world_log_value: Variant = candidate.get("preparedWorldLog")
	var restored_activity_runtime: TownWorldActivityRuntime = ACTIVITY_RUNTIME.new()
	restored_activity_runtime.configure(world_data)
	var restored_work_tasks := prepared.get("workTasksPrepared") as WORK_TASK_RUNTIME
	var restored_cargo_inventory := prepared.get("cargoInventoryPrepared") as CARGO_INVENTORY_RUNTIME
	var restored_production := prepared.get("productionStatePrepared") as PRODUCTION_RUNTIME
	var restored_occupation_services := prepared.get("occupationServicesPrepared") as OCCUPATION_SERVICE_RUNTIME
	var restored_resident_conditions := prepared.get("residentConditionsPrepared") as TownResidentConditionRuntime
	var restored_resident_sleep := prepared.get("residentSleepPrepared") as TownResidentSleepRuntime
	_running = false
	_activity_runtime.close()
	_activity_runtime = restored_activity_runtime
	_disconnect_work_task_log_source()
	_work_tasks = restored_work_tasks
	_cargo_inventory = restored_cargo_inventory
	_production = restored_production
	_occupation_services = restored_occupation_services
	_resident_conditions = restored_resident_conditions
	_resident_sleep = restored_resident_sleep
	_clinic_interviews = CLINIC_INTERVIEW_POLICY.new()
	var restored_private_messages := (
		prepared.get("privateMessagesPrepared", {}) as Dictionary
	)
	_private_messages = (
		restored_private_messages.get(
			"messagesById",
			{},
		) as Dictionary
	).duplicate(true)
	_private_message_sequence = int(
		restored_private_messages.get("sequence", 0),
	)
	_pause_reasons.clear()
	var speed_was_reset := _simulation_speed != 1
	_simulation_speed = 1
	_runtime_generation += 1
	_world_data = (
		prepared.get("worldData", world_data) as Dictionary
	).duplicate(true)
	_base_world_data = world_data.duplicate(true)
	_place_by_name_cache.clear()
	_presentation_cue_cache.clear()
	PERCEPTION_RUNTIME._rebuild_membership_grid_lookup(self)
	_indoor_layout_overrides.clear()
	_dynamic_props.clear()
	_agent_wake_preparation_runtime.clear()
	_animal_facts = (
		prepared.get("animalFactsPrepared", {}) as Dictionary
	).duplicate(true)
	_place_service_states = (
		prepared.get("placeServiceStatesPrepared", {}) as Dictionary
	).duplicate(true)
	for projection_value: Variant in prepared.get("indoorLayoutOverrides", []) as Array:
		var projection := projection_value as Dictionary
		_indoor_layout_overrides[String(projection.get("spaceId", ""))] = projection.duplicate(true)
	_opening = opening_config.duplicate(true)
	_owners = (prepared.get("owners", {}) as Dictionary).duplicate(true)
	_residents = (prepared.get("residents", {}) as Dictionary).duplicate(true)
	var restored_resident_lifecycle: TownResidentLifecycleRuntime = RESIDENT_LIFECYCLE_RUNTIME.new()
	for resident_value: Variant in _residents.values():
		var resident := resident_value as Dictionary
		var profile_attributes := resident.get("profileAttributes", {}) as Dictionary
		var runtime_attributes := resident.get("attributes", {}) as Dictionary
		restored_resident_lifecycle.initialize_resident(String(resident.get("residentId", "")),
			String(
				resident.get(
					"name",
					profile_attributes.get(
						"name",
						runtime_attributes.get("name", ""),
					),
				),
			),
			_resident_home_anchor(world_data, resident),)
	restored_resident_lifecycle.restore_save_snapshot(prepared.get("residentLifecyclePrepared", {}) as Dictionary,)
	_resident_lifecycle = restored_resident_lifecycle
	_staffing = STAFFING_RUNTIME.new()
	_staffing.configure(_world_data)
	var staffing_state_prepared := (
		prepared.get("staffingStatePrepared", {}) as Dictionary
	)
	if staffing_state_prepared.is_empty():
		_staffing.rebuild(
			prepared.get("livingResidentsPrepared", _residents) as Dictionary,
			int(
				(prepared.get("environment") as TownWorldEnvironment).get_absolute_minute()
			),
		)
	else:
		_staffing.restore_persistent_snapshot(
			staffing_state_prepared,
			prepared.get("livingResidentsPrepared", _residents) as Dictionary,
			int(
				(prepared.get("environment") as TownWorldEnvironment).get_absolute_minute()
			),
		)
	for resident_value: Variant in _residents.values():
		var restored_resident := resident_value as Dictionary
		_sync_body_from_activity_needs(
			restored_resident,
			restored_resident.get(
				"activityState",
				_activity_state_from_body(
					restored_resident.get("body", {}) as Dictionary,
				),
			) as Dictionary,
		)
	_activity_runtime.apply_prepared_restore(
		prepared.get("activityRuntimePrepared", {}) as Dictionary,
	)
	_activity_routines = (
		prepared.get(
			"activityRoutinesPrepared",
			{},
		) as Dictionary
	).get("routinesByResident", {}) as Dictionary
	_activity_routines = _activity_routines.duplicate(true)
	DINING_SERVICE.backfill_meal_period_refs(self, _activity_routines, _residents)
	_activity_work_task_bindings = (
		prepared.get(
			"activityWorkTaskBindingsPrepared",
			{},
		) as Dictionary
	).duplicate(true)
	_resident_order.clear()
	for resident_name_value: Variant in prepared.get("residentOrder", []) as Array:
		_resident_order.append(String(resident_name_value))
	_apply_resident_identities(prepared_identities)
	_player_avatar = (prepared.get("playerAvatar", {}) as Dictionary).duplicate(true)
	_player_avatar_present = player_avatar_present
	_traveler_relations = TRAVELER_RELATIONSHIP_BRIDGE.restore_snapshot(self, prepared)
	_reset_social_runtimes()
	_social_matters.restore_save_snapshot(
		prepared.get("socialMattersPrepared", {}) as Dictionary,
	)
	_community_bulletin.restore_save_snapshot(
		prepared.get("communityBulletinPrepared", {}) as Dictionary,
	)
	_announcements.clear()
	for announcement_value: Variant in prepared.get("announcements", []) as Array:
		_announcements.append((announcement_value as Dictionary).duplicate(true))
	_conversations = (prepared.get("conversations", {}) as Dictionary).duplicate(true)
	_autonomous_conversation_idle_seconds.clear()
	for conversation_id_value: Variant in _conversations:
		var conversation_id := String(conversation_id_value)
		var conversation := _conversations[conversation_id] as Dictionary
		if (
			String(conversation.get("status", "")) == "active"
			and CONVERSATION_RUNTIME._is_resident_only_conversation(self, conversation)
		):
			_autonomous_conversation_idle_seconds[conversation_id] = 0.0
	_trim_announcement_history()
	_observed_action_preview_resident_id = ""
	_public_event_log.clear()
	for event_value: Variant in prepared.get("eventLog", []) as Array:
		_public_event_log.append((event_value as Dictionary).duplicate(true))
	if prepared_world_log_value is RefCounted:
		_world_log_store = prepared_world_log_value as RefCounted
	else:
		_world_log_store = WORLD_LOG_STORE.new()
		_world_log_store.migrate_legacy_world_state(prepared)
	_world_log_consistency_error = ""
	_world_log_capture_enabled = false
	_rebuild_story_contexts_from_public_log()
	CONVERSATION_RUNTIME._trim_ended_conversation_history(self)
	_environment = prepared.get("environment") as WORLD_ENVIRONMENT
	_disconnect_conflict_controller_signals()
	_conflict_controller = (
		prepared.get("conflictControllerPrepared") as TownConflictWorldController
	)
	var conflict_bridge_configuration := _conflict_agent_world_bridge.configure(_conflict_controller,
		_person_name_for_id,) as Dictionary
	if conflict_bridge_configuration.get("ok") != true:
		return _command_failure(
			String(
				conflict_bridge_configuration.get(
					"errorCode",
					"CONFLICT_BRIDGE_CONFIG_INVALID",
				)
			),
			["冲突 Agent/World 接线无法恢复"],
		)
	_connect_conflict_controller_signals()
	var sequences := prepared.get("sequences", {}) as Dictionary
	_event_sequence = int(sequences.get("event", 0))
	_announcement_sequence = int(sequences.get("announcement", 0))
	_conversation_sequence = int(sequences.get("conversation", 0))
	_world_revision = maxi(_world_revision, int(sequences.get("worldRevision", 0)))
	_bump_world_revision(false)
	PERCEPTION_RUNTIME._refresh_perception(self, false)
	_begin_world_run()
	for resident_name in _resident_order:
		var resident := _residents[resident_name] as Dictionary
		# Older saves may contain the former concurrent preview.  The current
		# action already contains the confirmed work, so remove only the
		# presentation transient and never replay it after restore.
		resident["confirmedActionPreview"] = {}
		# A Gateway continuity wait is an error-recovery placeholder rather
		# than a resident-authored life choice. Do not restore an old placeholder
		# for another full hour; let the fresh post-restore decision choose from
		# the current, occupancy-filtered world snapshot.
		var restored_action := (
			resident.get("currentAction", {}) as Dictionary
		)
		if _is_continuity_wait_action(restored_action):
			resident["currentAction"] = {}
			resident["actionSuspendedAbsoluteMinute"] = -1
			resident["doing"] = "正在重新安排接下来的事"
		# 存档不保留网络中的 Agent 请求。恢复后重新用当前 World 快照
		# 唤醒居民，医患对话中正在等回应的患者也才能继续作答。
		_schedule_decision(resident_name, false, false, false, true)
	_assert_subsystems_installed("restore")
	var lifecycle := get_lifecycle_state()
	var summary := {
		"schemaVersion": SAVE_CODEC.SCHEMA_VERSION,
		"residentCount": _resident_order.size(),
		"residentRelocationRequired": true,
		"simulationSpeed": _simulation_speed,
		"identityStatus": _resident_identity_status,
		"time": get_time(),
		"weather": get_weather(),
		"lifecycle": lifecycle,
		"worldRevision": _world_revision,
	}
	_notify_world_revision()
	if speed_was_reset:
		simulation_speed_changed.emit(_simulation_speed, _world_revision)
	lifecycle_state_changed.emit(lifecycle.duplicate(true))
	conflict_projection_changed.emit(get_public_conflict_projection())
	world_restored.emit(summary.duplicate(true))
	return summary


func get_time() -> Dictionary:
	return _environment.get_time() as Dictionary if _environment != null else {}


func get_weather() -> String:
	if not _tick_weather_override.is_empty():
		return _tick_weather_override
	return String(_environment.get_weather()) if _environment != null else ""


func get_resident_names() -> Array[String]:
	var names: Array[String] = []
	for resident_id in _resident_order:
		names.append(String(_resident_name_by_id.get(resident_id, "")))
	return names


func get_resident_ids() -> Array[String]:
	return _resident_order.duplicate()


func create_private_message(
	sender_ref: String,
	recipient_ref: String,
	content: String,
	message_kind: String = "private",
	announcement_id: String = "",
	expires_at_minute: int = -1,
	source_ref: String = "",
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var sender_id := _resident_key(sender_ref)
	var recipient_id := _resident_key(recipient_ref)
	var normalized_content := content.strip_edges()
	var normalized_kind := message_kind.strip_edges()
	var normalized_announcement_id := announcement_id.strip_edges()
	if (
		sender_id.is_empty()
		or recipient_id.is_empty()
		or sender_id == recipient_id
	):
		return _command_failure(
			"PRIVATE_MESSAGE_PARTICIPANT_INVALID",
			["私人消息必须有两个不同的真实居民"],
		)
	if not _resident_is_alive(sender_id) or not _resident_is_alive(recipient_id):
		return _command_failure(
			"PRIVATE_MESSAGE_PARTICIPANT_DEAD",
			["死亡居民不能发送或接收新消息"],
		)
	if (
		normalized_kind not in ["private", "announcement_notice"]
		or (
			normalized_kind == "announcement_notice"
			and normalized_announcement_id.is_empty()
		)
		or (
			normalized_kind == "private"
			and not normalized_announcement_id.is_empty()
		)
	):
		return _command_failure(
			"PRIVATE_MESSAGE_KIND_INVALID",
			["正式通知必须携带唯一公告编号"],
		)
	if (
		normalized_content.is_empty()
		or normalized_content.length() > 240
	):
		return _command_failure(
			"PRIVATE_MESSAGE_CONTENT_INVALID",
			["私人消息必须是 1 到 240 个字符的文字"],
		)
	_private_message_sequence += 1
	var message_id := "private-message-%d" % _private_message_sequence
	var task_id := "private-message-task:%s" % message_id
	var created_at := int(_environment.get_absolute_minute())
	if expires_at_minute >= 0 and expires_at_minute <= created_at:
		_private_message_sequence -= 1
		return _command_failure(
			"PRIVATE_MESSAGE_EXPIRY_INVALID",
			["有时效的消息必须在创建之后到期"],
		)
	var batch_id := _active_unsorted_postal_batch_id()
	if batch_id.is_empty():
		batch_id = "postal-batch-%d-%d" % [
			created_at / 1440,
			_private_message_sequence,
		]
	var task_result := _work_tasks.create_task_for_occupations(
		{
			"taskId": task_id,
			"capability": "message.deliver",
			"sourceKind": (
				"formal_notice"
				if normalized_kind == "announcement_notice"
				else "resident_message"
			),
			"sourceRef": message_id,
			"targets": [{
				"kind": "resident",
				"ref": recipient_id,
			}],
			"requestedResultKind": "message_delivery",
			"createdAtMinute": created_at,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["private_message_delivery"],
		},
		["occupation_postal_worker"],
	) as Dictionary
	if task_result.get("ok") != true:
		_private_message_sequence -= 1
		return _decorate_command_result(task_result)
	var delivery_task := task_result.get("task", {}) as Dictionary
	var configured_process := _work_tasks.configure_initial_process(
		task_id,
		int(delivery_task.get("revision", 0)),
		"awaiting_sort",
		{
			"batchId": batch_id,
			"messageId": message_id,
			"nextActivityId": "__awaiting_postal_batch__",
		},
	) as Dictionary
	if configured_process.get("ok") != true:
		_work_tasks.cancel_task(
			task_id,
			"消息投递阶段初始化失败",
		)
		_private_message_sequence -= 1
		return _decorate_command_result(configured_process)
	delivery_task = configured_process.get("task", {}) as Dictionary
	var message := {
		"messageId": message_id,
		"senderResidentId": sender_id,
		"recipientResidentId": recipient_id,
		"content": normalized_content,
		"state": "pending",
		"createdAtMinute": created_at,
		"deliveredAtMinute": -1,
		"deliveredByResidentId": "",
		"taskId": task_id,
		"batchId": batch_id,
		"messageKind": normalized_kind,
		"announcementId": normalized_announcement_id,
		"expiresAtMinute": expires_at_minute,
		"sourceRef": source_ref.strip_edges(),
	}
	_private_messages[message_id] = message
	if (
		normalized_kind == "private"
		and _occupation_post_is_vacant("occupation_postal_worker")
	):
		_enable_private_message_sender_delivery(message_id)
		message = _private_messages.get(message_id, message) as Dictionary
		delivery_task = _work_tasks.task(task_id) as Dictionary
	else:
		_ensure_postal_sort_task(batch_id, created_at)
	_bump_world_revision()
	_append_private_message_log_event(
		"消息创建",
		message,
		"waiting",
	)
	for resident_id: String in _resident_order:
		if _resident_can_work_occupation(
			resident_id,
			"occupation_postal_worker",
		):
			_schedule_decision(resident_id, true)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"message": _public_private_message(message),
		"task": delivery_task.duplicate(true),
	})


func _private_message_distribution_token(
	source_ref: String,
	context_hint: String,
) -> String:
	return "%s|%d|%d|%s" % [
		String(source_ref).strip_edges(),
		int(_environment.get_absolute_minute()),
		_private_message_sequence + 1,
		String(context_hint).strip_edges(),
	]


func get_private_message(message_id: String) -> Dictionary:
	if not _private_messages.has(message_id):
		return {}
	return _public_private_message(
		_private_messages.get(message_id, {}) as Dictionary,
	)


func get_private_messages_for_resident(
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	var result: Array[Dictionary] = []
	var message_ids: Array[String] = []
	for message_id_value: Variant in _private_messages:
		message_ids.append(String(message_id_value))
	message_ids.sort()
	for message_id: String in message_ids:
		var message := _private_messages.get(
			message_id,
			{},
		) as Dictionary
		if resident_id in [
			String(message.get("senderResidentId", "")),
			String(message.get("recipientResidentId", "")),
			String(message.get("deliveredByResidentId", "")),
		]:
			result.append(_public_private_message(message))
	return result


func create_work_task(spec: Dictionary) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var prepared := spec.duplicate(true)
	if not prepared.has("createdAtMinute"):
		prepared["createdAtMinute"] = int(
			_environment.get_absolute_minute(),
		)
	var result := _work_tasks.create_task(
		prepared,
	) as Dictionary
	if result.get("ok") != true:
		return _decorate_command_result(result)
	_bump_world_revision()
	var created_task := result.get("task", {}) as Dictionary
	for resident_id_value: Variant in _resident_order:
		var resident_id := String(resident_id_value)
		var eligible := false
		for occupation_id: String in _work_occupation_ids_for_resident(
			resident_id,
		):
			if (
				created_task.get("eligibleOccupationIds", []) as Array
			).has(occupation_id):
				eligible = true
				break
		if (
			eligible
			or (created_task.get("eligibleResidentIds", []) as Array).has(
				resident_id,
			)
		):
			_schedule_decision(
				resident_id,
				true,
				false,
				_task_allows_current_activity_interrupt(created_task),
			)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"task": (
			created_task
		).duplicate(true),
	})

func get_work_tasks_for_resident(
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	var resident := _residents.get(resident_id, {}) as Dictionary
	var occupation_ids := _work_occupation_ids_for_resident(
		resident_id,
	)
	if occupation_ids.is_empty():
		return []
	var result: Array[Dictionary] = []
	var tasks_by_id: Dictionary = {}
	for occupation_id: String in occupation_ids:
		for value: Variant in _work_tasks.tasks_for_occupation(
			occupation_id,
			resident_id,
		) as Array:
			var task := value as Dictionary
			tasks_by_id[String(task.get("taskId", ""))] = task
	for value: Variant in _work_tasks.tasks_for_resident(
		resident_id,
	) as Array:
		var task := value as Dictionary
		tasks_by_id[String(task.get("taskId", ""))] = task
	var task_ids: Array[String] = []
	for task_id_value: Variant in tasks_by_id:
		task_ids.append(String(task_id_value))
	task_ids.sort()
	for task_id: String in task_ids:
		var task := tasks_by_id.get(task_id, {}) as Dictionary
		if not _work_task_is_currently_available(task):
			continue
		var projected_task := {
			"task_id": String(task.get("taskId", "")),
			"capability": String(task.get("capability", "")),
			"source_kind": String(task.get("sourceKind", "")),
			"source_ref": String(task.get("sourceRef", "")),
			"targets": _public_work_task_targets(
				task.get("targets", []) as Array,
			),
			"expected_result": String(
				task.get("requestedResultKind", ""),
			),
			"state": String(task.get("state", "")),
			"priority": int(task.get("priority", 0)),
			"process_stage": String(
				task.get("processStage", "ready"),
			),
		}
		var cargo_lot := _cargo_inventory.cargo_lot(String(task.get("sourceRef", "")),) as Dictionary
		if (
			String(task.get("capability", "")) == "cargo.deliver"
			and not cargo_lot.is_empty()
		):
			var cargo_state := String(cargo_lot.get("state", ""))
			var next_cargo_place := (
				String(cargo_lot.get("destinationPlaceId", ""))
				if cargo_state == "in_transit"
				else String(cargo_lot.get("sourcePlaceId", ""))
			)
			projected_task["next_step"] = {
				"place_id": next_cargo_place,
				"instruction": (
					"把已经领取的货送到%s" % next_cargo_place
					if cargo_state == "in_transit"
					else "先到%s领取货批" % next_cargo_place
				),
			}
		if (
			String(task.get("sourceKind", "")) in [
				"resident_message",
				"formal_notice",
			]
			and String(task.get("processStage", ""))
			== "out_for_delivery"
			and _private_messages.has(String(task.get("sourceRef", "")))
		):
			var message := _private_messages.get(
				String(task.get("sourceRef", "")),
				{},
			) as Dictionary
			var recipient_id := String(
				message.get("recipientResidentId", ""),
			)
			var recipient := _residents.get(
				recipient_id,
				{},
			) as Dictionary
			projected_task["message"] = {
				"kind": String(message.get("messageKind", "private")),
				"announcement_id": String(
					message.get("announcementId", ""),
				),
				"sender_resident_id": String(
					message.get("senderResidentId", ""),
				),
				"sender_name": _resident_display_name(
					String(message.get("senderResidentId", "")),
				),
				"recipient_resident_id": recipient_id,
				"recipient_name": _resident_display_name(recipient_id),
				"recipient_current_place": String(
					recipient.get("currentPlace", ""),
				),
				"content": String(message.get("content", "")),
			}
			projected_task["next_step"] = {
				"place_id": String(recipient.get("currentPlace", "")),
				"instruction": "前往收件人所在处，并当面对收件人说出原文",
			}
		DINING_SERVICE.decorate_projected_meal_task(task, projected_task, int(_environment.get_absolute_minute()))
		var occupation_service_request := _occupation_services.request(
			String(task.get("sourceRef", "")),
		) as Dictionary
		if not occupation_service_request.is_empty():
			var requester_id := String(
				occupation_service_request.get(
					"requesterResidentId",
					"",
				),
			)
			var projected_service_request := {
				"request_id": String(
					occupation_service_request.get("requestId", ""),
				),
				"kind": String(
					occupation_service_request.get("kind", ""),
				),
				"requester_resident_id": requester_id,
				"requester_name": _resident_display_name(
					requester_id,
				),
				"requester_current_place": String(
					(
						_residents.get(requester_id, {}) as Dictionary
					).get("currentPlace", ""),
				),
				"subject_ref": String(
					occupation_service_request.get("subjectRef", ""),
				),
				"item_id": String(
					occupation_service_request.get("itemId", ""),
				),
				"place_id": String(
					occupation_service_request.get("placeId", ""),
				),
				"state": String(
					occupation_service_request.get("state", ""),
				),
				"wait_reason": String(
					occupation_service_request.get("waitReason", ""),
				),
			}
			var request_context := (
				occupation_service_request.get("context", {}) as Dictionary
			)
			var medical_interview := request_context.get(
				"medicalInterview",
				{},
			) as Dictionary
			if not medical_interview.is_empty():
				projected_service_request["medical_dialogue"] = (
					_clinic_interviews.projection_for_role(medical_interview,
						"clinician",) as Dictionary
				).duplicate(true)
			projected_task["service_request"] = projected_service_request
			projected_task["next_step"] = {
				"place_id": String(
					occupation_service_request.get("placeId", ""),
				),
				"instruction": "到服务地点处理这位顾客的真实请求",
			}
		result.append(projected_task)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority := int(left.get("priority", 0))
		var right_priority := int(right.get("priority", 0))
		if left_priority != right_priority:
			return left_priority > right_priority
		return String(left.get("task_id", "")) < String(
			right.get("task_id", "")
		)
	)
	return result
func get_staffing_snapshot() -> Dictionary:
	if not _running:
		return {
			"schemaVersion": 1,
			"posts": [],
			"vacantPostIds": [],
			"duplicatePostIds": [],
			"capacityConflictPostIds": [],
			"unassignedResidentIds": [],
		}
	return _staffing.snapshot() as Dictionary


func get_cargo_inventory_snapshot() -> Dictionary:
	if not _running:
		return {
			"schemaVersion": 1,
			"inventories": {},
			"cargoLots": [],
			"lotSequence": 0,
			"archiveSummary": {
				"terminalLotCount": 0,
				"deliveredLotCount": 0,
				"cancelledLotCount": 0,
				"quantityByItem": {},
			},
		}
	return _cargo_inventory.snapshot() as Dictionary


func get_occupation_service_snapshot() -> Dictionary:
	if not _running:
		return {
			"schemaVersion": 1,
			"requestSequence": 0,
			"requestTerminalSequence": 0,
			"loanSequence": 0,
			"followUpSequence": 0,
			"accessionSequence": 0,
			"requests": [],
			"loans": [],
			"bookAvailableCopies": {},
			"dirtyDishCount": 0,
			"usedCafeTableCount": 0,
			"accessionRecords": [],
			"equipmentConditions": {},
			"scheduledFollowUps": [],
			"archiveSummary": {
				"requests": {
					"terminalCount": 0,
					"completedCount": 0,
					"cancelledCount": 0,
					"countByKind": {},
				},
				"returnedLoans": {"count": 0, "countByBook": {}},
				"resolvedFollowUps": {"count": 0},
				"accessions": {"count": 0},
			},
		}
	return _occupation_services.snapshot() as Dictionary


func get_occupation_service_request(request_id: String) -> Dictionary:
	if not _running:
		return {}
	return _occupation_services.request(
		request_id.strip_edges(),
	) as Dictionary


func create_occupation_service_request(spec: Dictionary) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var kind := String(spec.get("kind", "")).strip_edges()
	var requester_id := _resident_key(
		String(spec.get("requesterResidentId", "")),
	)
	if requester_id.is_empty():
		return _command_failure(
			"OCCUPATION_SERVICE_REQUESTER_UNKNOWN",
			["职业服务请求缺少真实居民"],
		)
	var definition := _occupation_service_definition(kind)
	if definition.is_empty():
		return _command_failure(
			"OCCUPATION_SERVICE_KIND_UNKNOWN",
			["未知职业服务类型：%s" % kind],
		)
	var request_context := (
		(spec.get("context", {}) as Dictionary).duplicate(true)
		if spec.get("context", {}) is Dictionary
		else {}
	)
	var prevalidated := _prevalidate_occupation_request_for_kind(
		kind,
		spec,
		requester_id,
		request_context,
		definition,
	)
	if prevalidated.get("ok") != true:
		return prevalidated.get("failure", {}) as Dictionary
	spec = prevalidated.get("spec", spec) as Dictionary
	var item_id := String(
		spec.get(
			"itemId",
			definition.get("defaultItemId", ""),
		),
	).strip_edges()
	var research_record_id := String(
		request_context.get("researchRecordId", ""),
	).strip_edges()
	var requests_research_booklet := (
		(kind == "clinic" and not research_record_id.is_empty())
		or (kind == "grocer_sale" and item_id == CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET)
	)
	if (
		requests_research_booklet
		and (
			research_record_id.is_empty()
			or (_occupation_services.accession_for_record(
				research_record_id,
			) as Dictionary).is_empty()
		)
	):
		return _command_failure(
			"RESEARCH_BOOKLET_SOURCE_INVALID",
			["研究参考必须引用已经入藏的真实研究记录"],
		)
	var subject_ref := String(spec.get("subjectRef", "")).strip_edges()
	if kind == "clinic" and subject_ref.is_empty():
		subject_ref = _clinic_default_subject_ref(requester_id)
	var request_now := _authoritative_absolute_minute()
	if kind == "dining_order" and _meal_period_for_minute(request_now).is_empty():
		return _command_failure(
			"DINING_SERVICE_CLOSED",
			["食堂当前不在供餐餐次内"],
		)
	request_context["mealPeriodRef"] = _meal_period_source_ref(request_now)
	if kind in OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS:
		if _occupation_service_preorder_needed(
			kind,
			item_id,
			String(definition.get("placeId", "")),
		):
			request_context["customerServiceMode"] = "preorder"
			request_context["preorderExpiresAtMinute"] = request_now + 1440
			request_context["customerNotifiedAtMinute"] = -1
		else:
			request_context["customerServiceMode"] = "onsite_wait"
			request_context["onsiteWaitUntilMinute"] = request_now + (
				_onsite_service_wait_minutes(kind)
			)
			request_context["customerAbsentSinceMinute"] = -1
	if kind == "dining_order":
		request_context["onsiteWaitUntilMinute"] = (
			DINING_SERVICE.wait_deadline(self, request_now)
		)
		var meal_period_ref := String(request_context.get("mealPeriodRef", ""))
		var already_completed := (
			not meal_period_ref.is_empty()
			and (
				_occupation_services.has_dining_order_completed_for_resident_meal_period(
					requester_id,
					meal_period_ref,
				)
				or not _dining_order_for_resident_meal_period(
					requester_id,
					request_now,
					["completed"],
				).is_empty()
			)
		)
		if already_completed:
			return _command_failure(
				"DINING_MEAL_ALREADY_SERVED",
				["本餐次已经完成取餐"],
			)
		var reused := _reuse_existing_dining_order(requester_id, request_now)
		if not reused.is_empty():
			return reused
	var created := _occupation_services.create_request(
		{
			"kind": kind,
			"requesterResidentId": requester_id,
			"subjectRef": subject_ref,
			"itemId": item_id,
			"placeId": String(definition.get("placeId", "")),
			"context": request_context,
			"createdAtMinute": request_now,
		},
	) as Dictionary
	if created.get("ok") != true:
		return _decorate_command_result(created)
	var request := created.get("request", {}) as Dictionary
	var request_id := String(request.get("requestId", ""))
	var task: Dictionary = {}
	if kind == "dining_order" and (
		_meal_period_for_minute(request_now).is_empty()
		or not _meal_service_is_open(request_now)
		or not _meal_period_is_prepared(request_now)
	):
		return _hold_dining_order_until_meal_service(
			request_id,
			requester_id,
			request_context,
			definition,
			request_now,
		)
	if bool(definition.get("placeService", false)):
		var service_result := record_place_service_request(
			String(definition.get("placeId", "")),
			request_id,
			true,
		)
		if service_result.get("ok") != true:
			_occupation_services.cancel_request(
				request_id,
				"地点服务任务创建失败",
			)
			return service_result
		task = _work_tasks.active_task_for_source(
			String(definition.get("sourceKind", "")),
			request_id,
		) as Dictionary
	else:
		var targets: Array = [{
			"kind": String(definition.get("targetKind", "")),
			"ref": (
				String(definition.get("targetRef", ""))
				if String(definition.get("targetKind", ""))
				== "audience_area"
				else request_id
			),
		}]
		if String(definition.get("targetKind", "")) == "audience_area":
			targets.append({
				"kind": "service_request",
				"ref": request_id,
			})
		else:
			targets.append({
				"kind": "resident",
				"ref": requester_id,
			})
		var task_result := _work_tasks.create_task_for_occupations(
			{
				"taskId": "occupation-service-task:%s" % request_id,
				"capability": String(
					definition.get("capability", ""),
				),
				"sourceKind": String(
					definition.get("sourceKind", ""),
				),
				"sourceRef": request_id,
				"targets": targets,
				"requestedResultKind": String(
					definition.get("resultKind", ""),
				),
				"createdAtMinute": int(
					_environment.get_absolute_minute(),
				),
				"priority": CONTENT_CATALOG.TASK_PRIORITY["occupation_service_request"],
			},
			[
				String(
					definition.get("occupationId", ""),
				),
			],
		) as Dictionary
		if task_result.get("ok") != true:
			_occupation_services.cancel_request(
				request_id,
				"职业任务创建失败",
			)
			return _decorate_command_result(task_result)
		task = task_result.get("task", {}) as Dictionary
		_bump_world_revision()
	var task_configuration := _configure_created_request_task_for_kind(
		kind,
		task,
		request_id,
		requester_id,
		request_context,
		subject_ref,
		item_id,
	)
	if task_configuration.get("ok") != true:
		return task_configuration.get("failure", {}) as Dictionary
	task = task_configuration.get("task", task) as Dictionary
	var attached := _occupation_services.attach_task(
		request_id,
		String(task.get("taskId", "")),
	) as Dictionary
	if attached.get("ok") != true:
		return _decorate_command_result(attached)
	task = _reserve_work_task(
		task,
		String(definition.get("occupationId", "")),
	)
	_begin_customer_service_wait(
		requester_id,
		request_id,
		String(definition.get("placeId", "")),
		request_context,
	)
	if requests_research_booklet:
		_sync_specialty_service_demand(
			kind,
			CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			request_id,
			request_now,
		)
	_schedule_occupation_service_worker(
		_occupation_services.request(request_id) as Dictionary,
	)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"request": (
			attached.get("request", {}) as Dictionary
		).duplicate(true),
		"task": task.duplicate(true),
	})


func _occupation_service_definition(kind: String) -> Dictionary:
	return (
		{
			"clinic": {
				"placeId": CONTENT_CATALOG.PLACE_CLINIC,
				"placeService": true,
				"capability": "care.consult",
				"sourceKind": "resident_care_request",
				"resultKind": "care_outcome",
				"occupationId": "occupation_clinic_practitioner",
				"targetKind": "service_request",
			},
			"library_loan": {
				"placeId": CONTENT_CATALOG.PLACE_LIBRARY,
				"placeService": true,
				"capability": "library.loan",
				"sourceKind": "loan_request",
				"resultKind": "loan_record",
				"occupationId": "occupation_librarian",
				"targetKind": "service_request",
			},
			"library_return": {
				"placeId": CONTENT_CATALOG.PLACE_LIBRARY,
				"placeService": false,
				"capability": "library.return",
				"sourceKind": "returned_book",
				"resultKind": "catalog_state_change",
				"occupationId": "occupation_librarian",
				"targetKind": "service_request",
			},
			"library_assist": {
				"placeId": CONTENT_CATALOG.PLACE_LIBRARY,
				"placeService": false,
				"capability": "library.assist",
				"sourceKind": "lookup_request",
				"resultKind": "catalog_state_change",
				"occupationId": "occupation_librarian",
				"targetKind": "service_request",
			},
			"civic_request": {
				"placeId": CONTENT_CATALOG.PLACE_TOWN_HALL,
				"placeService": false,
				"capability": "civic.service",
				"sourceKind": "resident_request",
				"resultKind": "civic_case_update",
				"occupationId": "occupation_town_manager",
				"targetKind": "service_request",
			},
			"repair": {
				"placeId": CONTENT_CATALOG.PLACE_WORKSHOP,
				"placeService": true,
				"capability": "craft.repair",
				"sourceKind": "repair_request",
				"resultKind": "repair_outcome",
				"occupationId": "occupation_craftsperson",
				"targetKind": "service_request",
			},
			"dining_order": {
				"placeId": CONTENT_CATALOG.PLACE_DINING_HALL,
				"placeService": true,
				"capability": "food.service",
				"sourceKind": "meal_demand",
				"resultKind": "meal_handoff",
				"occupationId": "occupation_dining_operator",
				"targetKind": "service_request",
				"defaultItemId": "meal",
			},
			"cafe_order": {
				"placeId": CONTENT_CATALOG.PLACE_CAFE,
				"placeService": true,
				"capability": "cafe.order",
				"sourceKind": "customer_order",
				"resultKind": "order_handoff",
				"occupationId": "occupation_cafe_worker",
				"targetKind": "service_request",
				"defaultItemId": CONTENT_CATALOG.ITEM_BREWED_COFFEE,
			},
			"grocer_sale": {
				"placeId": CONTENT_CATALOG.PLACE_MARKET,
				"placeService": false,
				"capability": "retail.sale",
				"sourceKind": "customer_demand",
				"resultKind": "retail_transfer",
				"occupationId": "occupation_grocer",
				"targetKind": "service_request",
				"defaultItemId": CONTENT_CATALOG.ITEM_GENERAL_GOODS,
			},
			"flower_sale": {
				"placeId": CONTENT_CATALOG.PLACE_MARKET,
				"placeService": false,
				"capability": "retail.sale",
				"sourceKind": "customer_demand",
				"resultKind": "retail_transfer",
				"occupationId": "occupation_flower_vendor",
				"targetKind": "service_request",
				"defaultItemId": CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
			},
			"performance": {
				"placeId": CONTENT_CATALOG.PLACE_PLAZA,
				"placeService": false,
				"capability": "music.perform",
				"sourceKind": "personal_performance_plan",
				"resultKind": "performance_record",
				"occupationId": "occupation_musician",
				"targetKind": "audience_area",
				"targetRef": "outdoor_plaza_01",
			},
		}.get(kind, {}) as Dictionary
	).duplicate(true)


# create_occupation_service_request 的 per-kind 特判钩子:按服务类型聚合,
# 主流水线只保留公共步骤。

func _prevalidate_occupation_request_for_kind(
	kind: String,
	spec: Dictionary,
	requester_id: String,
	request_context: Dictionary,
	definition: Dictionary,
) -> Dictionary:
	if kind == "clinic":
		var condition_context := _clinic_condition_request_context(
			requester_id,
		)
		if condition_context.is_empty():
			return {
				"ok": false,
				"failure": _command_failure(
					"CLINIC_ACTIVE_CONDITION_REQUIRED",
					["居民当前没有需要看诊的真实身体状况"],
				),
			}
		request_context.merge(
			condition_context.get("context", {}) as Dictionary,
			true,
		)
		if String(spec.get("subjectRef", "")).strip_edges().is_empty():
			spec = spec.duplicate(true)
			spec["subjectRef"] = String(
				condition_context.get("subjectRef", "身体不适"),
			)
		if not _clinic_has_executable_practitioner():
			return {
				"ok": false,
				"failure": _command_failure(
					"CLINIC_SERVICE_UNAVAILABLE",
					["诊所当前没有可以接诊的医生"],
				),
			}
	if kind == "performance":
		if bool(request_context.get("generatedFromPublicEvent", false)):
			definition["sourceKind"] = "public_event"
		elif bool(request_context.get("generatedFromResidentInvitation", false)):
			definition["sourceKind"] = "resident_invitation"
	return {"ok": true, "spec": spec}


func _clinic_default_subject_ref(requester_id: String) -> String:
	var body := (
		_residents.get(requester_id, {}) as Dictionary
	).get("body", {}) as Dictionary
	return "%s、%s、%s" % [
		String(body.get("困", "不困")),
		String(body.get("饿", "不饿")),
		String(body.get("累", "不累")),
	]


func _reuse_existing_dining_order(
	requester_id: String,
	request_now: int,
) -> Dictionary:
	var existing_meal_order := _dining_order_for_resident_meal_period(
		requester_id,
		request_now,
		["pending", "waiting", "in_progress"],
	)
	if existing_meal_order.is_empty():
		return {}
	var existing_request_id := String(
		existing_meal_order.get("requestId", ""),
	)
	if String(existing_meal_order.get("state", "")) in [
		"pending",
		"waiting",
		"in_progress",
	]:
		_begin_customer_service_wait(
			requester_id,
			existing_request_id,
			String(existing_meal_order.get("placeId", "")),
			existing_meal_order.get("context", {}) as Dictionary,
		)
		_schedule_occupation_service_worker(existing_meal_order)
	return _decorate_command_result({
		"ok": true,
		"changed": false,
		"request": existing_meal_order.duplicate(true),
		"task": (
			_work_tasks.task(String(existing_meal_order.get("taskId", "")),) as Dictionary
		).duplicate(true),
	})


func _hold_dining_order_until_meal_service(
	request_id: String,
	requester_id: String,
	request_context: Dictionary,
	definition: Dictionary,
	now: int,
) -> Dictionary:
	_sync_meal_period_tasks(now)
	var wait_reason := (
		"食堂当前不在供餐时间"
		if _meal_period_for_minute(now).is_empty()
		else (
			"当前餐次尚未开始供餐"
			if not _meal_service_is_open(now)
			else "当前餐次尚未完成备餐"
		)
	)
	var waiting := _occupation_services.mark_waiting(
		request_id,
		wait_reason,
	) as Dictionary
	var meal_preparation_task := _work_tasks.task("meal-preparation:%s" % _meal_period_source_ref(now),) as Dictionary
	meal_preparation_task = _reserve_work_task(
		meal_preparation_task,
		"occupation_dining_operator",
	)
	_begin_customer_service_wait(
		requester_id,
		request_id,
		String(definition.get("placeId", "")),
		request_context,
	)
	_schedule_occupation_decisions("occupation_dining_operator")
	return _decorate_command_result({
		"ok": waiting.get("ok") == true,
		"changed": waiting.get("ok") == true,
		"errorCode": String(waiting.get("errorCode", "")),
		"request": (
			waiting.get("request", {}) as Dictionary
		).duplicate(true),
		"task": meal_preparation_task.duplicate(true),
	})


func _configure_created_request_task_for_kind(
	kind: String,
	task: Dictionary,
	request_id: String,
	requester_id: String,
	request_context: Dictionary,
	subject_ref: String,
	item_id: String,
) -> Dictionary:
	if kind == "cafe_order" and item_id == CONTENT_CATALOG.ITEM_BREWED_COFFEE:
		var process_result := _work_tasks.configure_initial_process(
			String(task.get("taskId", "")),
			int(task.get("revision", 0)),
			"awaiting_brew",
			{
				"nextActivityId": "activity_cafe_brew_coffee",
				"serviceRequestId": request_id,
				"itemId": item_id,
			},
		) as Dictionary
		if process_result.get("ok") != true:
			_occupation_services.cancel_request(
				request_id,
				"咖啡订单过程初始化失败",
			)
			return {
				"ok": false,
				"failure": _decorate_command_result(process_result),
			}
		task = process_result.get("task", {}) as Dictionary
	if kind == "clinic":
		var medical_context := _clinic_interviews.create_context(request_id,
			requester_id,
			(request_context.get("conditionIds", []) as Array).duplicate(),
			subject_ref,) as Dictionary
		if medical_context.is_empty():
			_occupation_services.cancel_request(
				request_id,
				"问诊上下文初始化失败",
			)
			return {
				"ok": false,
				"failure": _command_failure(
					"CLINIC_INTERVIEW_CONTEXT_INVALID",
					["看诊请求无法建立问诊上下文"],
				),
			}
		var merged_medical_context := _occupation_services.merge_request_context(
			request_id,
			{"medicalInterview": medical_context},
		) as Dictionary
		if merged_medical_context.get("ok") != true:
			_occupation_services.cancel_request(
				request_id,
				"问诊上下文写入失败",
			)
			return {
				"ok": false,
				"failure": _decorate_command_result(merged_medical_context),
			}
		var interview_process := _work_tasks.configure_initial_process(
			String(task.get("taskId", "")),
			int(task.get("revision", 0)),
			"awaiting_interview",
			{
				"nextActivityId": "medical_interview",
				"serviceRequestId": request_id,
			},
		) as Dictionary
		if interview_process.get("ok") != true:
			_occupation_services.cancel_request(
				request_id,
				"问诊过程初始化失败",
			)
			return {
				"ok": false,
				"failure": _decorate_command_result(interview_process),
			}
		task = interview_process.get("task", {}) as Dictionary
	return {"ok": true, "task": task}


func create_cargo_lot(spec: Dictionary) -> Dictionary:
	return _create_cargo_lot_with_origin(
		spec,
		"local_inventory",
	)


func create_world_result_cargo_lot(spec: Dictionary) -> Dictionary:
	return _create_cargo_lot_with_origin(
		spec,
		"world_result",
	)


func create_external_supply_cargo_lot(
	spec: Dictionary,
) -> Dictionary:
	return _create_cargo_lot_with_origin(
		spec,
		"external_supply",
	)


func _create_cargo_lot_with_origin(
	spec: Dictionary,
	origin_kind: String,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var prepared := spec.duplicate(true)
	if not prepared.has("createdAtMinute"):
		prepared["createdAtMinute"] = int(
			_environment.get_absolute_minute(),
		)
	var cargo_result: Dictionary
	if origin_kind == "external_supply":
		cargo_result = _cargo_inventory.create_external_supply_lot(prepared)
	elif origin_kind == "world_result":
		cargo_result = _cargo_inventory.create_world_result_lot(prepared)
	else:
		cargo_result = _cargo_inventory.create_local_lot(prepared)
	if cargo_result.get("ok") != true:
		return _decorate_command_result(cargo_result)
	var lot := cargo_result.get("lot", {}) as Dictionary
	var lot_id := String(lot.get("lotId", ""))
	if String(lot.get("state", "")) == "awaiting_release":
		var release_result := _create_cargo_release_task(
			lot,
			int(prepared.get("priority", 70)),
		)
		if release_result.get("ok") != true:
			_cargo_inventory.cancel_available_lot(
				lot_id,
				int(_environment.get_absolute_minute()),
			)
			return _decorate_command_result(release_result)
		_bump_world_revision()
		_append_cargo_log_event(
			"货批生成",
			lot,
			"",
			"waiting",
		)
		_schedule_occupation_decisions(
			"occupation_warehouse_keeper",
		)
		return _decorate_command_result({
			"ok": true,
			"changed": true,
			"lot": lot.duplicate(true),
			"task": (
				release_result.get("task", {}) as Dictionary
			).duplicate(true),
		})
	var task_result := _create_cargo_delivery_task(
		lot,
		int(prepared.get("priority", 70)),
	)
	if task_result.get("ok") != true:
		_cargo_inventory.cancel_available_lot(
			lot_id,
			int(_environment.get_absolute_minute()),
		)
		return _decorate_command_result(task_result)
	_bump_world_revision()
	_append_cargo_log_event(
		"货批生成",
		lot,
		"",
		"ongoing",
	)
	_schedule_occupation_decisions("occupation_delivery_worker")
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"lot": lot.duplicate(true),
		"task": (
			task_result.get("task", {}) as Dictionary
		).duplicate(true),
	})


func _create_cargo_release_task(
	lot: Dictionary,
	priority: int,
) -> Dictionary:
	var lot_id := String(lot.get("lotId", ""))
	return _work_tasks.create_task_for_occupations(
		{
			"taskId": "cargo-release-task:%s" % lot_id,
			"capability": "inventory.release",
			"sourceKind": "inventory_request",
			"sourceRef": lot_id,
			"targets": [
				{"kind": "cargo_lot", "ref": lot_id},
				{"kind": "prop", "ref": "码头仓库货单桌"},
			],
			"requestedResultKind": "release_lot",
			"createdAtMinute": int(
				lot.get("createdAtMinute", 0),
			),
			"priority": priority,
		},
		["occupation_warehouse_keeper"],
	) as Dictionary


func _create_cargo_delivery_task(
	lot: Dictionary,
	priority: int,
) -> Dictionary:
	var lot_id := String(lot.get("lotId", ""))
	var source_kind := (
		"external_supply_arrival"
		if String(lot.get("originKind", "")) == "external_supply"
		else "cargo_available"
	)
	var task_spec := {
		"taskId": "delivery-task:%s" % lot_id,
		"capability": "cargo.deliver",
		"sourceKind": source_kind,
		"sourceRef": lot_id,
		"targets": [
			{"kind": "cargo_lot", "ref": lot_id},
			{
				"kind": "route",
				"ref": "%s->%s"
				% [
					String(lot.get("sourcePlaceId", "")),
					String(lot.get("destinationPlaceId", "")),
				],
			},
		],
		"requestedResultKind": "cargo_transfer",
		"createdAtMinute": int(lot.get("createdAtMinute", 0)),
		"priority": priority,
	}
	var created := _work_tasks.create_task_for_occupations(
		task_spec,
		["occupation_delivery_worker"],
	) as Dictionary
	if (
		created.get("ok") == true
		and int(lot.get("quantity", 0)) <= MAX_SELF_CARRIED_CARGO_QUANTITY
		and _occupation_post_is_vacant("occupation_delivery_worker")
	):
		var fallback_ids := _cargo_fallback_carrier_ids(lot)
		if not fallback_ids.is_empty():
			var granted := _work_tasks.add_eligible_residents(
				String((created.get("task", {}) as Dictionary).get("taskId", "")),
				fallback_ids,
			) as Dictionary
			if granted.get("ok") == true:
				created = granted
				for resident_id: String in fallback_ids:
					_schedule_decision(resident_id, true)
	if created.get("ok") == true:
		var reserved_task := _reserve_work_task(
			created.get("task", {}) as Dictionary,
			"occupation_delivery_worker",
		)
		created["task"] = reserved_task
	return created


func _schedule_occupation_decisions(occupation_id: String) -> void:
	for resident_id: String in _resident_order:
		if _resident_can_work_occupation(resident_id, occupation_id):
			_schedule_decision(resident_id, true)


func _reserve_work_task(
	task: Dictionary,
	preferred_occupation_id: String,
) -> Dictionary:
	if (
		task.is_empty()
		or String(task.get("state", "")) not in ["open", "waiting"]
		or not String(task.get("assignedResidentId", "")).is_empty()
	):
		return task.duplicate(true)
	var selected_resident_id := ""
	var selected_task_count := 2147483647
	for resident_id: String in _resident_order:
		if not _resident_can_accept_work_task(resident_id, task):
			continue
		var active_task_count := 0
		for active_value: Variant in _work_tasks.tasks_for_resident(resident_id,) as Array:
			var active_task := active_value as Dictionary
			if String(active_task.get("state", "")) in [
				"accepted",
				"in_progress",
				"waiting",
			]:
				active_task_count += 1
		if active_task_count < selected_task_count:
			selected_resident_id = resident_id
			selected_task_count = active_task_count
	if selected_resident_id.is_empty():
		return task.duplicate(true)
	var occupation_id := _task_acceptance_occupation_id(
		selected_resident_id,
		task,
	)
	if (
		_resident_can_work_occupation(
			selected_resident_id,
			preferred_occupation_id,
		)
		and (task.get("eligibleOccupationIds", []) as Array).has(
			preferred_occupation_id,
		)
	):
		occupation_id = preferred_occupation_id
	var accepted := _work_tasks.accept_task(String(task.get("taskId", "")),
		selected_resident_id,
		occupation_id,
		int(task.get("revision", 0)),) as Dictionary
	if accepted.get("ok") != true:
		return task.duplicate(true)
	_schedule_decision(
		selected_resident_id,
		true,
		false,
		_task_allows_current_activity_interrupt(task),
	)
	return (accepted.get("task", {}) as Dictionary).duplicate(true)


func pickup_cargo_lot(
	lot_id: String,
	resident_ref: String,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var resident := _residents.get(resident_id, {}) as Dictionary
	var task := _work_tasks.task(
		"delivery-task:%s" % lot_id,
	) as Dictionary
	if not _resident_can_accept_work_task(resident_id, task):
		return _command_failure(
			"CARGO_PICKUP_NOT_AUTHORIZED",
			["当前居民不是这批货的送货负责人"],
		)
	var lot := _cargo_inventory.cargo_lot(
		lot_id,
	) as Dictionary
	if (
		String(lot.get("state", "")) != "available"
		or String(resident.get("currentPlace", ""))
		!= String(lot.get("sourcePlaceId", ""))
	):
		return _command_failure(
			"CARGO_PICKUP_INVALID",
			["居民必须到真实来源地点领取仍可用的货批"],
		)
	if String(task.get("state", "")) in ["open", "waiting"]:
		var acceptance_occupation_id := _task_acceptance_occupation_id(
			resident_id,
			task,
		)
		var accepted := _work_tasks.accept_task(
			String(task.get("taskId", "")),
			resident_id,
			acceptance_occupation_id,
			int(task.get("revision", 0)),
		) as Dictionary
		if accepted.get("ok") != true:
			return _decorate_command_result(accepted)
		task = accepted.get("task", {}) as Dictionary
	if String(task.get("state", "")) == "accepted":
		var started := _work_tasks.start_task(
			String(task.get("taskId", "")),
			resident_id,
			int(task.get("revision", 0)),
		) as Dictionary
		if started.get("ok") != true:
			return _decorate_command_result(started)
		task = started.get("task", {}) as Dictionary
	if (
		String(task.get("state", "")) != "in_progress"
		or String(task.get("assignedResidentId", "")) != resident_id
	):
		return _command_failure(
			"CARGO_WORK_TASK_INVALID",
			["货运任务未由当前居民正式接取"],
		)
	var picked_up := _cargo_inventory.pickup(
		lot_id,
		resident_id,
		String(resident.get("currentPlace", "")),
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if picked_up.get("ok") != true:
		return _decorate_command_result(picked_up)
	_bump_world_revision()
	_append_cargo_log_event(
		"货批取货",
		picked_up.get("lot", {}) as Dictionary,
		resident_id,
		"ongoing",
	)
	_schedule_decision(resident_id, true)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"lot": (
			picked_up.get("lot", {}) as Dictionary
		).duplicate(true),
		"task": task.duplicate(true),
	})


func deliver_cargo_lot(
	lot_id: String,
	resident_ref: String,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var resident := _residents.get(resident_id, {}) as Dictionary
	var lot := _cargo_inventory.cargo_lot(
		lot_id,
	) as Dictionary
	var task := _work_tasks.task(
		"delivery-task:%s" % lot_id,
	) as Dictionary
	if (
		String(lot.get("state", "")) != "in_transit"
		or String(lot.get("carrierResidentId", "")) != resident_id
		or String(resident.get("currentPlace", ""))
		!= String(lot.get("destinationPlaceId", ""))
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("assignedResidentId", "")) != resident_id
	):
		return _command_failure(
			"CARGO_DELIVERY_INVALID",
			["同一送货员必须带着货批到达真实目的地"],
		)
	var delivered := _cargo_inventory.deliver(
		lot_id,
		resident_id,
		String(resident.get("currentPlace", "")),
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if delivered.get("ok") != true:
		return _decorate_command_result(delivered)
	var completed := _work_tasks.complete_task(
		String(task.get("taskId", "")),
		resident_id,
		int(task.get("revision", 0)),
		"cargo_transfer",
		{
			"resultRef": "cargo-arrival:%s" % lot_id,
			"facts": {
				"lotId": lot_id,
				"sourcePlaceId": String(
					lot.get("sourcePlaceId", ""),
				),
				"destinationPlaceId": String(
					lot.get("destinationPlaceId", ""),
				),
				"carrierResidentId": resident_id,
				"receiptPending": true,
			},
		},
	) as Dictionary
	if completed.get("ok") != true:
		return _decorate_command_result(completed)
	var receipt_task := _create_cargo_receipt_task(
		delivered.get("lot", {}) as Dictionary,
	)
	var delivered_lot := delivered.get("lot", {}) as Dictionary
	var destination_place_id := String(
		delivered_lot.get("destinationPlaceId", ""),
	)
	if receipt_task.is_empty() and _owners.has(destination_place_id):
		_cargo_inventory.receive(
			lot_id,
			String(_owners.get(destination_place_id, resident_id)),
			destination_place_id,
			int(_environment.get_absolute_minute()),
		)
	_bump_world_revision()
	var final_delivered_lot := _cargo_inventory.cargo_lot(
		lot_id,
	) as Dictionary
	_append_cargo_log_event(
		"货批到货",
		delivered.get("lot", {}) as Dictionary,
		resident_id,
		"waiting" if not receipt_task.is_empty() else "completed",
	)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"lot": (
			delivered.get("lot", {}) as Dictionary
		).duplicate(true),
		"task": (
			completed.get("task", {}) as Dictionary
		).duplicate(true),
		"receiptTask": receipt_task.duplicate(true),
	})


func _create_cargo_receipt_task(lot: Dictionary) -> Dictionary:
	var lot_id := String(lot.get("lotId", ""))
	var destination := String(lot.get("destinationPlaceId", ""))
	var capability := ""
	var result_kind := ""
	var source_kind := "incoming_cargo"
	var eligible_occupations: Array[String] = []
	if destination == CONTENT_CATALOG.PLACE_WAREHOUSE:
		capability = "inventory.receive"
		result_kind = "inventory_change"
		eligible_occupations = ["occupation_warehouse_keeper"]
	elif destination == CONTENT_CATALOG.PLACE_MARKET:
		capability = "retail.receive"
		result_kind = "retail_stock_change"
		if String(lot.get("itemId", "")) in [
			CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
			CONTENT_CATALOG.ITEM_BOUQUET,
		]:
			source_kind = "flower_cargo"
			eligible_occupations = ["occupation_flower_vendor"]
		else:
			eligible_occupations = ["occupation_grocer"]
	elif destination == CONTENT_CATALOG.PLACE_CAFE:
		capability = "cafe.production"
		result_kind = "stock_change"
		eligible_occupations = ["occupation_cafe_worker"]
	elif destination == CONTENT_CATALOG.PLACE_DINING_HALL:
		capability = "food.production"
		result_kind = "stock_change"
		eligible_occupations = ["occupation_dining_operator"]
	elif destination == CONTENT_CATALOG.PLACE_CLINIC:
		capability = "care.treatment"
		result_kind = "stock_change"
		eligible_occupations = ["occupation_clinic_practitioner"]
	elif destination == CONTENT_CATALOG.PLACE_WORKSHOP:
		capability = "craft.production"
		result_kind = "stock_change"
		eligible_occupations = ["occupation_craftsperson"]
	elif destination == CONTENT_CATALOG.PLACE_LIBRARY:
		capability = "library.accession"
		result_kind = "stock_change"
		eligible_occupations = ["occupation_librarian"]
	else:
		return {}
	var created := _work_tasks.create_task_for_occupations(
		{
			"taskId": "receipt-task:%s" % lot_id,
			"capability": capability,
			"sourceKind": source_kind,
			"sourceRef": lot_id,
			"targets": [
				{"kind": "cargo_lot", "ref": lot_id},
			],
			"requestedResultKind": result_kind,
			"createdAtMinute": int(
				_environment.get_absolute_minute(),
			),
			"priority": CONTENT_CATALOG.TASK_PRIORITY["cargo_receipt"],
		},
		eligible_occupations,
	) as Dictionary
	if created.get("ok") != true:
		return {}
	for resident_id: String in _resident_order:
		for occupation_id: String in eligible_occupations:
			if _resident_can_work_occupation(resident_id, occupation_id):
				_schedule_decision(resident_id, true)
				break
	return (
		created.get("task", {}) as Dictionary
	).duplicate(true)


func get_production_snapshot() -> Dictionary:
	return (
		_production.snapshot() as Dictionary
		if _running
		else {}
	)


func create_plant_research(
	requester_ref: String,
	question: String,
	source_kind := "personal_research_plan",
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var requester_id := _resident_key(requester_ref)
	if requester_id.is_empty():
		return _command_failure(
			"PLANT_RESEARCH_REQUESTER_INVALID",
			["植物研究必须来自真实居民或正式请求方"],
		)
	var begun := _production.begin_plant_research(
		question,
		source_kind,
		requester_id,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if begun.get("ok") != true:
		return _decorate_command_result(begun)
	var project := begun.get("project", {}) as Dictionary
	var task_result := _create_plant_research_stage_task(
		project,
		"observe",
	) as Dictionary
	if task_result.get("ok") != true:
		return _decorate_command_result(task_result)
	_bump_world_revision()
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"project": project.duplicate(true),
		"task": (
			task_result.get("task", {}) as Dictionary
		).duplicate(true),
	})


func get_plant_research_projects() -> Array[Dictionary]:
	return (
		_production.plant_research_projects() as Array[Dictionary]
		if _running
		else []
	)


func _create_plant_research_stage_task(
	project: Dictionary,
	stage: String,
) -> Dictionary:
	var project_id := String(project.get("projectId", ""))
	var capability := ""
	var targets: Array[Dictionary] = []
	match stage:
		"observe":
			capability = "research.observe"
			targets = _semantic_region_task_targets(
				"activity_botanist_observe_plants",
				"outdoor_garden_01",
				"%s:%s" % [project_id, stage],
			)
		"verify":
			capability = "research.verify"
			targets = [{
				"kind": "prop",
				"ref": "图书馆西侧高书架",
			}]
		"record":
			capability = "research.record"
			targets = [{
				"kind": "prop",
				"ref": "图书馆写作桌",
			}]
		_:
			return _command_failure(
				"PLANT_RESEARCH_STAGE_INVALID",
				["未知植物研究阶段"],
			)
	return create_work_task({
		"taskId": "research-task:%s:%s" % [project_id, stage],
		"capability": capability,
		"sourceKind": String(project.get("sourceKind", "")),
		"sourceRef": project_id,
		"targets": targets,
		"requestedResultKind": "research_record",
		"priority": (
			62
			if String(project.get("sourceKind", "")) == "abnormal_plant"
			else 74
		),
	})


func _sync_production_tasks(absolute_minute: int) -> void:
	# A3:_production.advance_to 单独计时;目标扫描在 _semantic_region_task_targets
	# 内累计;派生扫描 = 外层 productionTasksUsec 减去这两段。
	var lap_usec := Time.get_ticks_usec() if _advance_profile_enabled else 0
	var advanced := _production.advance_to(
		absolute_minute,
		get_weather(),
	) as Dictionary
	_advance_profile_lap(_advance_profile_scratch, "productionTasksAdvanceUsec", lap_usec)
	if advanced.get("ok") != true:
		return
	for market_item_id: String in [CONTENT_CATALOG.ITEM_FISH, CONTENT_CATALOG.ITEM_FRESH_FLOWERS]:
		_expire_specialty_inventory_before(
			CONTENT_CATALOG.PLACE_MARKET,
			market_item_id,
			absolute_minute - 1440,
		)
	var fish_inventory := int(_cargo_inventory.inventory_quantity(
		CONTENT_CATALOG.PLACE_MARKET,
		CONTENT_CATALOG.ITEM_FISH,
	))
	if bool(_production.fishing_task_needed(
		absolute_minute,
		fish_inventory,
	)) and not _has_active_cargo_to_place(CONTENT_CATALOG.ITEM_FISH, CONTENT_CATALOG.PLACE_MARKET):
		_ensure_production_task({
			"taskId": "fishing-task:%d" % absolute_minute,
			"capability": "fishing.harvest",
			"sourceKind": "fishing_conditions",
			"sourceRef": "outdoor_harbor_01",
			"targets": _semantic_region_task_targets(
				"activity_fisher_catch_in_region",
				"outdoor_harbor_01",
				"fishing:%d" % absolute_minute,
			),
			"requestedResultKind": "fishing_outcome",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["fishing_plan"],
		})
	var care_plot := _production.care_task_plot() as Dictionary
	if not care_plot.is_empty():
		var care_plot_id := String(care_plot.get("plotId", ""))
		_ensure_production_task({
			"taskId": "garden-care-task:%s:%d"
				% [care_plot_id, absolute_minute],
			"capability": "garden.care",
			"sourceKind": "plant_state",
			"sourceRef": care_plot_id,
			"targets": _semantic_region_task_targets(
				"activity_farm_water_beds",
				"outdoor_garden_01",
				"garden-care:%s:%d"
				% [care_plot_id, absolute_minute],
			),
			"requestedResultKind": "garden_state_change",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["garden_care_plan"],
		})
	var harvest_plot := _production.harvest_task_plot(
	) as Dictionary
	var fresh_flower_inventory := int(_cargo_inventory.inventory_quantity(
		CONTENT_CATALOG.PLACE_MARKET,
		CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
	))
	if (
		not harvest_plot.is_empty()
		and fresh_flower_inventory < 2
		and not _has_active_cargo_to_place(
			CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
			CONTENT_CATALOG.PLACE_MARKET,
		)
	):
		var harvest_plot_id := String(
			harvest_plot.get("plotId", ""),
		)
		_ensure_production_task({
			"taskId": "garden-harvest-task:%s:%d"
				% [harvest_plot_id, absolute_minute],
			"capability": "garden.harvest",
			"sourceKind": "flowering_state",
			"sourceRef": harvest_plot_id,
			"targets": _semantic_region_task_targets(
				"activity_garden_harvest_region",
				"outdoor_garden_01",
				"garden-harvest:%s:%d"
				% [harvest_plot_id, absolute_minute],
			),
			"requestedResultKind": "flower_lot",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["garden_harvest_plan"],
		})
	_sync_food_chain_tasks(absolute_minute)
	_sync_craft_chain_tasks(absolute_minute)
	_sync_clinic_follow_up_requests(absolute_minute)
	_sync_plant_research_tasks(absolute_minute, care_plot)
	_sync_music_work_tasks(absolute_minute)
	_sync_daily_operation_tasks(absolute_minute)
	_sync_market_preparation_tasks(absolute_minute)
	_sync_civic_work_tasks(absolute_minute)
	_sync_meal_period_tasks(absolute_minute)
	_sync_warehouse_audit_tasks(absolute_minute)
	_sync_library_catalog_tasks(absolute_minute)
	_sync_library_return_requests(absolute_minute)
	_sync_research_sample_tasks(absolute_minute)


func _sync_food_chain_tasks(absolute_minute: int) -> void:
	# Ordinary meals are prepared once per meal period from always-available base
	# supplies, then served during that period. Specialty baking is driven by a
	# daily work plan instead.
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 360 or minute_of_day >= 720:
		return
	var day_index := absolute_minute / 1440
	_expire_specialty_inventory_before(
		CONTENT_CATALOG.PLACE_CAFE,
		"pastry",
		absolute_minute - 1440,
	)
	var source_ref := "dining-pastry-plan-day:%d" % day_index
	if _retire_stale_period_work_tasks(
		"food.production",
		"daily_baking_plan",
		source_ref,
		"当天的烘焙计划已经结束",
	):
		return
	if (
		int(_cargo_inventory.inventory_quantity(
			CONTENT_CATALOG.PLACE_CAFE,
			"pastry",
		)) > 0
		or _has_active_cargo_to_place("pastry", CONTENT_CATALOG.PLACE_CAFE)
		or _has_active_specialty_production(
			"pastry",
			CONTENT_CATALOG.PLACE_CAFE,
		)
	):
		return
	_ensure_production_task({
		"taskId": "dining-pastry-plan:%d" % day_index,
		"capability": "food.production",
		"sourceKind": "daily_baking_plan",
		"sourceRef": source_ref,
		"targets": [
			{"kind": "prop", "ref": "公共食堂备餐柜"},
			{"kind": "prop", "ref": "公共食堂灶台"},
		],
		"requestedResultKind": "food_batch",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["daily_baking_plan"],
		"processStage": "planned",
		"processFacts": {
			"productItemId": "pastry",
			"destinationPlaceId": CONTENT_CATALOG.PLACE_CAFE,
			"nextActivityId": "activity_baker_prepare_dough",
		},
	})


func _sync_market_preparation_tasks(absolute_minute: int) -> void:
	var fresh_quantity := int(_cargo_inventory.inventory_quantity(
		CONTENT_CATALOG.PLACE_MARKET,
		CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
	))
	var bouquet_quantity := int(_cargo_inventory.inventory_quantity(
		CONTENT_CATALOG.PLACE_MARKET,
		CONTENT_CATALOG.ITEM_BOUQUET,
	))
	if fresh_quantity < 2 or bouquet_quantity >= 2:
		return
	_ensure_production_task({
		"taskId": "flower-arrangement:%d" % absolute_minute,
		"capability": "retail.arrange",
		"sourceKind": "display_change",
		"sourceRef": "flower-stall-bouquet-stock",
		"targets": [{
			"kind": "prop",
			"ref": "独立市集北侧花摊",
		}],
		"requestedResultKind": "bouquet_lot",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["retail_display_plan"],
	})


func _sync_craft_chain_tasks(absolute_minute: int) -> void:
	# Ordinary materials remain base supply. A repair starts only after a real
	# authored prop has accumulated enough completed uses to require maintenance.
	for fault_value: Variant in _occupation_services.active_equipment_faults(
	) as Array:
		var fault := fault_value as Dictionary
		var fault_id := String(fault.get("faultId", ""))
		if bool(_occupation_services.has_active_request(
			"repair",
			fault_id,
		)):
			continue
		var place_id := String(fault.get("placeId", ""))
		var requester_id := _resident_key(String(_owners.get(place_id, "")))
		if requester_id.is_empty():
			requester_id = _first_resident_for_occupation(
				"occupation_town_manager",
			)
		if requester_id.is_empty():
			continue
		create_occupation_service_request({
			"kind": "repair",
			"requesterResidentId": requester_id,
			"subjectRef": fault_id,
			"context": {
				"generatedFromEquipmentWear": true,
				"propName": String(fault.get("propName", "")),
				"placeId": place_id,
				"faultReason": String(fault.get("faultReason", "")),
				"completeOnRepair": true,
			},
		})
	# 工匠除了等维修，也会按镇务维护计划制作公共用品。材料属于基础
	# 供给，不以库存见底作为触发条件；成品则进入真实货运链。
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 480 or minute_of_day >= 960:
		return
	var day_index := absolute_minute / 1440
	var source_ref := "civic-craft-plan-day:%d" % day_index
	if _retire_stale_period_work_tasks(
		"craft.production",
		"production_request",
		source_ref,
		"新的公共用品制作周期已经开始",
	):
		return
	if (
		int(_cargo_inventory.inventory_quantity(
			CONTENT_CATALOG.PLACE_WAREHOUSE,
			"crafted_item",
		)) > 0
		or _has_active_cargo_to_place("crafted_item", CONTENT_CATALOG.PLACE_WAREHOUSE)
		or _has_active_specialty_production(
			"crafted_item",
			CONTENT_CATALOG.PLACE_WAREHOUSE,
		)
	):
		return
	_ensure_production_task({
		"taskId": "craft-production:%d" % day_index,
		"capability": "craft.production",
		"sourceKind": "production_request",
		"sourceRef": source_ref,
		"targets": [
			{"kind": "prop", "ref": "工作坊木料架"},
			{"kind": "prop", "ref": "工作坊打磨机"},
			{"kind": "prop", "ref": "工作坊装配锯架台"},
		],
		"requestedResultKind": "crafted_lot",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["craft_request"],
		"processStage": "materials_planned",
		"processFacts": {
			"productItemId": "crafted_item",
			"destinationPlaceId": CONTENT_CATALOG.PLACE_WAREHOUSE,
			"baseSupplyItems": ["lumber", "metal"],
			"nextActivityId": "activity_workshop_take_lumber",
		},
	})


func _sync_plant_research_tasks(
	absolute_minute: int,
	care_plot: Dictionary,
) -> void:
	var day_index := absolute_minute / 1440
	for project_value: Variant in _production.plant_research_projects(
	) as Array:
		var project := project_value as Dictionary
		if String(project.get("stage", "question")) != "accessioned":
			return
		if (
			int(project.get("createdAtMinute", -1440)) / 1440
			== day_index
		):
			return
	var botanist_id := _first_resident_for_occupation(
		"occupation_botanist",
	)
	if botanist_id.is_empty():
		return
	var research_plot := care_plot.duplicate(true)
	if research_plot.is_empty():
		var garden_plots := (
			(_production.snapshot() as Dictionary).get(
				"gardenPlots",
				[],
			) as Array
		)
		if garden_plots.is_empty():
			return
		research_plot = (
			garden_plots[posmod(day_index, garden_plots.size())] as Dictionary
		).duplicate(true)
	var plot_id := String(research_plot.get("plotId", ""))
	var source_kind := (
		"abnormal_plant"
		if not care_plot.is_empty()
		else "personal_research_plan"
	)
	var question := (
		"%s 的湿度和杂草变化是否需要调整照料方式" % plot_id
		if source_kind == "abnormal_plant"
		else "继续核对 %s 的长期湿度与生长记录" % plot_id
	)
	for request_value: Variant in (
		(_occupation_services.snapshot() as Dictionary).get(
			"requests",
			[],
		) as Array
	):
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "clinic"
			and String(request.get("state", "")) in ["pending", "waiting"]
		):
			source_kind = "clinic_request"
			question = "诊所当前接诊记录涉及的植物照料资料是否需要补充验证"
			break
	if source_kind != "clinic_request" and day_index > 0 and posmod(
		day_index,
		7,
	) == 0:
		source_kind = "season_change"
		question = "进入新的七日生长周期后，%s 的变化是否符合当前照料记录" % plot_id
	elif source_kind != "clinic_request" and posmod(day_index, 5) == 2:
		source_kind = "research_question"
		question = "%s 当前花木状态与图书馆既有记录是否一致" % plot_id
	elif source_kind != "clinic_request" and posmod(day_index, 3) == 1:
		source_kind = "personal_research_plan"
		question = "继续核对 %s 的长期湿度与生长记录" % plot_id
	create_plant_research(
		botanist_id,
		question,
		source_kind,
	)


func _sync_music_work_tasks(absolute_minute: int) -> void:
	_retire_stale_performance_requests(absolute_minute)
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 9 * 60 or minute_of_day >= 18 * 60:
		return
	var day_index := absolute_minute / 1440
	if (
		posmod(day_index, 3) == 0
		and not _occupation_service_request_exists(
			"performance",
			"public-event-day:%d" % day_index,
		)
	):
		var musician_id := WORK_ACTOR_SELECTION_POLICY.choose_qualified_actor(
			self,
			"occupation_musician",
			"public-event-day:%d" % day_index,
		)
		if not musician_id.is_empty():
			create_occupation_service_request({
				"kind": "performance",
				"requesterResidentId": musician_id,
				"subjectRef": "public-event-day:%d" % day_index,
				"context": {
					"generatedFromPublicEvent": true,
					"dayIndex": day_index,
				},
			})
	var source_ref := "music-rehearsal-day:%d" % day_index
	if _retire_stale_period_work_tasks(
		"music.rehearse",
		"personal_performance_plan",
		source_ref,
		"当天的排练计划已经结束",
	):
		return
	_ensure_production_task({
		"taskId": "music-rehearsal:%d" % day_index,
		"capability": "music.rehearse",
		"sourceKind": "personal_performance_plan",
		"sourceRef": source_ref,
		"targets": _semantic_region_task_targets(
			"activity_musician_rehearse",
			"outdoor_river_park_01",
			"music-rehearsal:%d" % day_index,
		),
		"requestedResultKind": "rehearsal_record",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["music_rehearsal_plan"],
	})


func _has_active_cargo_to_place(
	item_id: String,
	place_id: String,
) -> bool:
	var snapshot := _cargo_inventory.snapshot() as Dictionary
	for value: Variant in snapshot.get("cargoLots", []) as Array:
		var lot := value as Dictionary
		if (
			String(lot.get("itemId", "")) == item_id
			and String(lot.get("destinationPlaceId", "")) == place_id
			and String(lot.get("state", "")) in [
				"awaiting_release",
				"available",
				"in_transit",
				"awaiting_receipt",
			]
		):
			return true
	return false


func _ensure_production_task(spec: Dictionary) -> void:
	if not (
		_work_tasks.active_task_for_source(
			String(spec.get("sourceKind", "")),
			String(spec.get("sourceRef", "")),
		) as Dictionary
	).is_empty():
		return
	var task_spec := spec.duplicate(true)
	var process_stage := String(
		task_spec.get("processStage", ""),
	).strip_edges()
	var process_facts := (
		(task_spec.get("processFacts", {}) as Dictionary).duplicate(true)
		if task_spec.get("processFacts", {}) is Dictionary
		else {}
	)
	task_spec.erase("processStage")
	task_spec.erase("processFacts")
	var created := _work_tasks.create_task(
		task_spec,
	) as Dictionary
	if created.get("ok") != true:
		return
	var task := created.get("task", {}) as Dictionary
	if not process_stage.is_empty():
		var configured_process := _work_tasks.configure_initial_process(
			String(task.get("taskId", "")),
			int(task.get("revision", 0)),
			process_stage,
			process_facts,
		) as Dictionary
		if configured_process.get("ok") != true:
			_work_tasks.cancel_task(
				String(task.get("taskId", "")),
				"工作阶段初始化失败",
			)
			return
		task = configured_process.get("task", {}) as Dictionary
	for resident_id: String in _resident_order:
		var occupation_id := _occupation_id_for_resident(
			_residents.get(resident_id, {}) as Dictionary,
		)
		if (
			task.get("eligibleOccupationIds", []) as Array
		).has(occupation_id):
			_schedule_decision(resident_id, true)


func complete_work_task(
	task_id: String,
	resident_ref: String,
	result_kind: String,
	evidence: Dictionary,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"RESIDENT_NOT_FOUND",
			["找不到提交工作结果的居民"],
		)
	var task := _work_tasks.task(task_id) as Dictionary
	if task.is_empty():
		return _command_failure("WORK_TASK_NOT_FOUND", ["工作任务不存在"])
	var result := _work_tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		result_kind,
		evidence,
	) as Dictionary
	if result.get("ok") != true:
		return _decorate_command_result(result)
	_bump_world_revision()
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"task": (
			result.get("task", {}) as Dictionary
		).duplicate(true),
	})


func _occupation_id_for_resident(resident: Dictionary) -> String:
	var social_state := resident.get("socialState", {}) as Dictionary
	var occupation_name := String(
		social_state.get("job", ""),
	)
	for value: Variant in _world_data.get("occupations", []) as Array:
		if not value is Dictionary:
			continue
		var occupation := value as Dictionary
		if (
			String(occupation.get("label", "")) == occupation_name
			or (occupation.get("aliases", []) as Array).has(
				occupation_name,
			)
		):
			return String(occupation.get("occupationId", ""))
	return ""


func _first_resident_for_occupation(occupation_id: String) -> String:
	for resident_id: String in _resident_order:
		if _resident_can_work_occupation(resident_id, occupation_id):
			return resident_id
	return ""


func _occupation_definition(occupation_id: String) -> Dictionary:
	var normalized := occupation_id.strip_edges()
	if normalized.is_empty():
		return {}
	for value: Variant in _world_data.get("occupations", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get(
				"occupationId",
				"",
			)) == normalized
		):
			return (value as Dictionary).duplicate(true)
	return {}


func _work_occupation_ids_for_resident(
	resident_id: String,
) -> Array[String]:
	var result: Array[String] = []
	var resident := _residents.get(resident_id, {}) as Dictionary
	if _resident_is_on_leave(resident):
		return result
	var primary_id := _occupation_id_for_resident(resident)
	if not primary_id.is_empty():
		result.append(primary_id)
	if _staffing != null and _environment != null:
		for occupation_value: Variant in _staffing.active_assignment_occupation_ids(
			resident_id,
			int(_environment.get_absolute_minute()),
		) as Array:
			var occupation_id := String(occupation_value)
			if not occupation_id.is_empty() and not result.has(
				occupation_id,
			):
				result.append(occupation_id)
	return result


func _work_occupation_id_for_activity(
	resident_id: String,
	activity_id: String,
) -> String:
	for occupation_id: String in _work_occupation_ids_for_resident(
		resident_id,
	):
		if not (
			_work_tasks.tasks_for_activity(
				occupation_id,
				activity_id,
				resident_id,
			) as Array
		).is_empty():
			return occupation_id
	return _occupation_id_for_resident(
		_residents.get(resident_id, {}) as Dictionary,
	)


func _activity_social_state_for(
	resident_id: String,
	activity_id: String,
) -> Dictionary:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var social_state := (
		resident.get("socialState", {}) as Dictionary
	).duplicate(true)
	var occupation_id := _work_occupation_id_for_activity(
		resident_id,
		activity_id,
	)
	if not occupation_id.is_empty():
		social_state["occupationId"] = occupation_id
	return social_state


func _sync_staffing_matters() -> void:
	if not _running or _environment == null:
		return
	var snapshot := get_staffing_snapshot()
	var now := int(_environment.get_absolute_minute())
	var signature := _staffing_social_signature(snapshot)
	if (
		signature == _staffing_matter_sync_signature
		and _staffing_matter_last_sync_minute >= 0
		and (
			now - _staffing_matter_last_sync_minute
			< STAFFING_MATTER_REFRESH_INTERVAL_MINUTES
		)
	):
		return
	_staffing_matter_full_sync_count += 1
	var source_revision := maxi(_world_revision, 0)
	for post_value: Variant in snapshot.get("posts", []) as Array:
		if not post_value is Dictionary:
			continue
		var post := post_value as Dictionary
		var occupation_id := String(post.get("occupationId", ""))
		var vacant := String(post.get("status", "")) == "vacant"
		var candidate_ids: Array[String] = []
		if vacant:
			candidate_ids = _staffing_candidate_ids(
				snapshot,
				occupation_id,
			)
		sync_job_vacancy({
			"vacancy_id": "job-vacancy:%s" % occupation_id,
			"source_revision": source_revision,
			"occupation_id": occupation_id,
			"occupation_label": String(post.get("label", "")),
			"primary_place_id": String(
				post.get("primaryWorkplacePlace", ""),
			),
			"vacant": vacant,
			"temporary_absence": not (
				post.get(
					"temporarilyAbsentResidentIds",
					[],
				) as Array
			).is_empty(),
			"vacancy_effect": String(post.get("vacancyEffect", "")),
			"staffing_entry_rule": String(
				post.get("staffingEntryRule", ""),
			),
			"candidate_resident_ids": candidate_ids,
			"expires_at": now + 10080,
			"source_event_ids": [],
		})
	_staffing_matter_sync_signature = signature
	_staffing_matter_last_sync_minute = now


func _staffing_social_signature(snapshot: Dictionary) -> Array:
	var result: Array = []
	for post_value: Variant in snapshot.get("posts", []) as Array:
		if not post_value is Dictionary:
			continue
		var post := post_value as Dictionary
		var occupation_id := String(post.get("occupationId", ""))
		var vacant := String(post.get("status", "")) == "vacant"
		result.append([
			occupation_id,
			String(post.get("label", "")),
			String(post.get("primaryWorkplacePlace", "")),
			vacant,
			String(post.get("vacancyEffect", "")),
			String(post.get("staffingEntryRule", "")),
			(
				_staffing_candidate_ids(snapshot, occupation_id)
				if vacant
				else []
			),
		])
	result.sort_custom(
		func(left: Array, right: Array) -> bool:
			return String(left[0]) < String(right[0])
	)
	return result


func _staffing_candidate_ids(
	snapshot: Dictionary,
	target_occupation_id: String,
) -> Array[String]:
	# 用字典去重，保持追加顺序；避免 result.has 线性查找造成的平方复杂度。
	var seen := {}
	var result: Array[String] = []
	for post_value: Variant in snapshot.get("posts", []) as Array:
		if not post_value is Dictionary:
			continue
		var post := post_value as Dictionary
		if String(post.get("status", "")) != "duplicate":
			continue
		for resident_value: Variant in post.get(
			"assignedResidentIds",
			[],
		) as Array:
			var resident_id := String(resident_value)
			if not seen.has(resident_id):
				seen[resident_id] = true
				result.append(resident_id)
	for resident_value: Variant in snapshot.get(
		"unassignedResidentIds",
		[],
	) as Array:
		var resident_id := String(resident_value)
		if (
			not seen.has(resident_id)
			and not _resident_is_on_leave(
				_residents.get(resident_id, {}) as Dictionary,
			)
		):
			seen[resident_id] = true
			result.append(resident_id)
	for resident_id: String in _resident_order:
		if (
			seen.has(resident_id)
			or _occupation_id_for_resident(
				_residents.get(resident_id, {}) as Dictionary,
			) == target_occupation_id
			or _resident_is_on_leave(
				_residents.get(resident_id, {}) as Dictionary,
			)
		):
			continue
		seen[resident_id] = true
		result.append(resident_id)
	if result.size() > MAX_SOCIAL_RESPONSE_CANDIDATES:
		result.resize(MAX_SOCIAL_RESPONSE_CANDIDATES)
	return result


func _staffing_candidate_ability_score(
	resident: Dictionary,
	_source_state: Dictionary,
) -> int:
	var resident_id := String(resident.get("residentId", ""))
	var occupation_id := _occupation_id_for_resident(resident)
	var post := _staffing.post_for_occupation(
		occupation_id,
	) as Dictionary
	if occupation_id.is_empty():
		return 100
	if (
		String(post.get("status", "")) == "duplicate"
		and (post.get("assignedResidentIds", []) as Array).has(
			resident_id,
		)
	):
		return 100
	return 10


func get_resident_identity_snapshot() -> Dictionary:
	var residents: Array[Dictionary] = []
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in _resident_name_by_id:
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	for resident_id in resident_ids:
		residents.append({
			"residentId": resident_id,
			"residentName": String(_resident_name_by_id.get(resident_id, "")),
		})
	return {"status": _resident_identity_status, "residents": residents}


func get_resident_state(resident_ref: String) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	return _resident_state_projection(_residents[resident_id] as Dictionary)


func get_resident_lifecycle_state(resident_ref: String) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	return (
		_resident_lifecycle.get_resident_state(resident_id,) as Dictionary
	).duplicate(true)


func get_public_death_events() -> Array[Dictionary]:
	return (
		_resident_lifecycle.get_public_death_events() as Array
	).duplicate(true)


func confirm_resident_death(
	resident_ref: String,
	reason: String,
	expected_lifecycle_revision: int = -1,
	expected_world_instance_token: String = "",
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if (
		not expected_world_instance_token.is_empty()
		and str(get_instance_id()) != expected_world_instance_token
	):
		return _command_failure(
			"RESIDENT_DEATH_SESSION_STALE",
			["当前小镇已经切换，请重新选择居民后再确认"],
			{"stale": true},
		)
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"RESIDENT_NOT_FOUND",
			["找不到要确认死亡的居民"],
		)
	var existing := get_resident_lifecycle_state(resident_id)
	if (
		expected_lifecycle_revision >= 0
		and int(existing.get("revision", -1))
			!= expected_lifecycle_revision
	):
		return _command_failure(
			"RESIDENT_DEATH_REQUEST_STALE",
			["居民状态已经变化，请重新选择后再确认"],
			{"stale": true},
		)
	if String(existing.get("status", "")) == "dead":
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"state": existing,
			"event": (
				existing.get("deathEvent", {}) as Dictionary
			).duplicate(true),
		})
	var normalized_reason := reason.strip_edges()
	if normalized_reason.is_empty():
		return _command_failure(
			"RESIDENT_DEATH_REASON_REQUIRED",
			["死亡必须使用 World 已确认的原因"],
		)
	var event_id := _next_world_event_id()
	var resident := _residents[resident_id] as Dictionary
	var previous_place := String(resident.get("currentPlace", ""))
	var death_location := {
		"spaceId": String(resident.get("spaceId", "")),
		"regionId": String(resident.get("regionId", "")),
		"placeName": previous_place,
		"position": resident.get("position", Vector2.ZERO) as Vector2,
	}
	var confirmed := _resident_lifecycle.confirm_death(
		resident_id,
		normalized_reason,
		event_id,
		get_time(),
		death_location,
		false,
	) as Dictionary
	if confirmed.get("ok") != true:
		return _decorate_command_result(confirmed)
	var event := confirmed.get("event", {}) as Dictionary
	_append_public_event_log(
		event_id,
		"world_event",
		resident_id,
		_resident_display_name(resident_id),
		previous_place,
		event,
	)
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id)
	if not conversation.is_empty():
		CONVERSATION_RUNTIME._end_conversation(self, 
			String(conversation.get("conversationId", "")),
			"无法继续",
			"interrupted",
		)
	if not (resident.get("currentAction", {}) as Dictionary).is_empty():
		_interrupt_action(resident_id, "居民已经死亡，当前行动中止")
	resident["confirmedActionPreview"] = {}
	if _observed_action_preview_resident_id == resident_id:
		_observed_action_preview_resident_id = ""
	_release_resident_social_participation_for_death(resident_id)
	_release_resident_conflicts_for_death(resident_id)
	_cancel_private_messages_for_resident_death(resident_id)
	_work_tasks.release_tasks_for_resident(resident_id,
		"原负责人已经死亡，任务等待重新接取",)
	resident["doing"] = "已经死亡"
	resident["movementRevision"] = int(
		resident.get("movementRevision", 1),
	) + 1
	resident["routeConnector"] = []
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["conversationId"] = ""
	resident["conversation"] = null
	resident["eventQueue"] = []
	resident["resultQueue"] = []
	resident["inflightEvents"] = []
	resident["inflightResults"] = []
	_agent_wake_preparation_runtime.clear_resident(resident_id)
	resident["decisionPending"] = false
	resident["validDecisionId"] = ""
	resident["decisionMayInterruptCurrent"] = false
	resident["pendingWake"] = {}
	resident["wakeDispatchQueued"] = false
	_staffing.rebuild(_living_residents_for_staffing(),
		int(_environment.get_absolute_minute()),)
	_refresh_place_service_staffing()
	# 死亡是 World 已确认的全局事实。统一走公告栏的全体广播链，
	# 居民收到的是标准“公告发布”事件，不再额外交付一套 Agent 无法
	# 处理的“居民死亡”事件。
	var death_announcement := _publish_community_announcement(
		SYSTEM_BULLETIN_PUBLISHER_ID,
		_death_announcement_text(event),
		"",
		"board",
	) as Dictionary
	if death_announcement.get("ok") != true:
		push_error(
			"居民死亡公告发布失败：%s"
			% String(death_announcement.get("errorCode", "UNKNOWN"))
		)
	# 公告发布本身是普通事件，不会打断居民当前行动；死亡公告需要
	# 在本次 World 变更后立刻进入每个活着居民的下一次唤醒。
	for recipient_id: String in _resident_order:
		if _resident_is_alive(recipient_id):
			_schedule_decision(recipient_id, true)
	_bump_world_revision(false)
	_emit_place_change(resident_id, previous_place)
	_sync_staffing_matters()
	_notify_world_revision()
	_emit_resident_state_changed(resident_id)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"state": get_resident_lifecycle_state(resident_id),
		"event": event.duplicate(true),
	})


func _death_announcement_text(event: Dictionary) -> String:
	var death_time := event.get("time", {}) as Dictionary
	var resident_name := String(
		event.get("deceased_resident_name", "居民"),
	).strip_edges()
	var day := int(death_time.get("day", 0))
	var clock := String(death_time.get("clock", "")).strip_edges()
	if day > 0 and not clock.is_empty():
		return "%s于第%d天%s死亡。" % [resident_name, day, clock]
	if not clock.is_empty():
		return "%s于%s死亡。" % [resident_name, clock]
	return "%s已经死亡。" % resident_name


func _release_resident_social_participation_for_death(
	resident_id: String,
) -> void:
	var absolute_minute := int(_environment.get_absolute_minute())
	for matter_value: Variant in _social_matters.list_matters(false,) as Array:
		var matter := matter_value as Dictionary
		if String(matter.get("state", "")) not in ["assigned", "executing"]:
			continue
		var participant := (
			(matter.get("participants", {}) as Dictionary).get(
				resident_id,
				{},
			) as Dictionary
		)
		if String(participant.get("status", "")) not in [
			"assigned",
			"executing",
		]:
			continue
		var released := _social_matters.release_participant(String(matter.get("matter_id", "")),
			resident_id,
			"居民已经死亡",
			absolute_minute,) as Dictionary
		if released.get("ok") == true:
			_emit_social_matter_summary(
				String(matter.get("matter_id", "")),
			)


func _release_resident_conflicts_for_death(resident_id: String) -> void:
	if _conflict_controller == null:
		return
	for conflict_value: Variant in (
		get_public_conflict_projection().get(
			"activeConflicts",
			[],
		) as Array
	):
		var conflict := conflict_value as Dictionary
		if not (conflict.get("participantIds", []) as Array).has(
			resident_id,
		):
			continue
		_conflict_controller.leave_conflict(String(conflict.get("conflictId", "")),
			resident_id,
			"death",)


func _cancel_private_messages_for_resident_death(
	resident_id: String,
) -> void:
	var message_ids: Array[String] = []
	for message_id_value: Variant in _private_messages:
		var message_id := String(message_id_value)
		var message := _private_messages.get(message_id, {}) as Dictionary
		if String(message.get("state", "")) != "pending":
			continue
		if (
			String(message.get("senderResidentId", "")) == resident_id
			or String(message.get("recipientResidentId", "")) == resident_id
		):
			message_ids.append(message_id)
	message_ids.sort()
	for message_id: String in message_ids:
		_cancel_pending_private_message(
			message_id,
			"消息的一方已经死亡，投递取消",
		)


func get_resident_action_phase(resident_ref: String) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	return ACTION_PRESENTATION._resident_action_phase_projection(self, _residents[resident_id] as Dictionary)

func get_resident_public_relationship_progress(
	resident_ref: String,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"RESIDENT_NOT_FOUND",
			["找不到要查看的居民"],
		)
	var resident_names := {}
	for other_id_value: Variant in _resident_name_by_id:
		var other_id := String(other_id_value)
		resident_names[other_id] = String(
			_resident_name_by_id.get(other_id, "")
		)
	var items := RELATIONSHIP_EVIDENCE_PROGRESS.build(
		resident_id,
		resident_names,
		_conversations.values(),
		_social_matters.list_matters(true) as Array,
		get_public_conflict_projection().get("events", []) as Array,
	)
	TRAVELER_RELATIONSHIP_BRIDGE.append_public_projection(self, items, resident_id)
	return {
		"ok": true,
		"residentId": resident_id,
		"items": items,
		"worldRevision": _world_revision,
	}

func query_activity_options(
	resident_id: String,
	resident_override: Dictionary = {},
	max_uncached_reachability_checks := -1,
	priority_activity_id := "",
) -> Dictionary:
	return ACTIVITY_OPTION_QUERY.query(
		self,
		resident_id,
		resident_override,
		max_uncached_reachability_checks,
		priority_activity_id,
	)


func _resident_sleep_needed(resident: Dictionary) -> bool:
	return ACTIVITY_SCALARS.resident_sleep_needed(resident)

func _apply_sleep_activity_availability(
	resident: Dictionary,
	option: Dictionary,
) -> void:
	ACTIVITY_SCALARS.apply_sleep_activity_availability(resident, option)


func _apply_occupation_service_activity_availability(
	resident_id: String,
	option: Dictionary,
) -> void:
	if (
		not bool(option.get("available", false))
		or String(option.get("role", "")) != "visitor"
	):
		return
	var activity_id := String(option.get("activityId", ""))
	if activity_id in [
		"activity_dining_eat_meal",
		"activity_dining_return_dishes",
	]:
		option["available"] = false
		option["disabledReason"] = "DINING_MEAL_ROUTINE_ONLY"
		return
	if activity_id == "activity_dining_collect_meal":
		var collect_disabled_reason := DINING_SERVICE.collect_disabled_reason(
			self,
			resident_id,
			int(_environment.get_absolute_minute()),
		)
		if not collect_disabled_reason.is_empty():
			option["available"] = false
			option["disabledReason"] = collect_disabled_reason
			return
		# 公共食堂按餐次一次性备餐，开餐后居民自行取餐；
		# 日常用餐不再要求一个逐单接待员在柜台等待。
		return
	if _visitor_onsite_occupation_service_is_staffed(
		resident_id,
		activity_id,
	):
		return
	option["available"] = false
	option["disabledReason"] = "OCCUPATION_SERVICE_UNSTAFFED"


func _visitor_onsite_occupation_service_is_staffed(
	resident_id: String,
	activity_id: String,
) -> bool:
	if activity_id == "activity_dining_collect_meal":
		return DINING_SERVICE.collect_disabled_reason(
			self,
			resident_id,
			_authoritative_absolute_minute(),
		).is_empty()
	var request_spec := _visitor_occupation_service_spec(
		resident_id,
		activity_id,
	)
	if request_spec.is_empty():
		return true
	return _occupation_service_kind_is_staffed(
		String(request_spec.get("kind", "")),
	)


func _occupation_service_kind_is_staffed(kind: String) -> bool:
	# 医疗服务由自己的在岗与应急流程处理，这里保持原有规则。
	if kind == "clinic" or kind not in OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS:
		return true
	var definition := _occupation_service_definition(kind)
	var occupation_id := String(definition.get("occupationId", ""))
	if occupation_id.is_empty():
		return true
	var post := _staffing.post_for_occupation(
		occupation_id,
	) as Dictionary
	if post.is_empty() or String(post.get("status", "vacant")) == "vacant":
		return false
	var now := int(
		(_staffing.snapshot() as Dictionary).get(
			"absoluteMinute",
			0,
		),
	)
	for resident_id_value: Variant in post.get(
		"responsibleResidentIds",
		[],
	) as Array:
		var resident := _residents.get(
			String(resident_id_value),
			{},
		) as Dictionary
		if resident.is_empty():
			continue
		var attendance := resident.get(
			"attendanceState",
			{},
		) as Dictionary
		if (
			String(attendance.get("status", "available")) != "on_leave"
			or int(attendance.get("untilMinute", -1)) <= now
		):
			return true
	return false


func _apply_work_task_activity_availability(
	resident_id: String,
	resident: Dictionary,
	option: Dictionary,
) -> void:
	if (
		not bool(option.get("available", false))
		or String(option.get("role", "")) != "worker"
	):
		return
	var activity_id := String(option.get("activityId", ""))
	if _work_task_available_for_activity(
		resident_id,
		resident,
		activity_id,
		"worker",
	):
		return
	option["available"] = false
	option["disabledReason"] = "WORK_TASK_REQUIRED"


func _work_task_available_for_activity(
	resident_id: String,
	resident: Dictionary,
	activity_id: String,
	role: String,
) -> bool:
	if role != "worker":
		return true
	var capabilities := _work_task_capabilities_for_activity(activity_id)
	if capabilities.is_empty():
		return true
	var occupation_id := _work_occupation_id_for_activity(
		resident_id,
		activity_id,
	)
	var tasks := _work_tasks.tasks_for_activity(
		occupation_id,
		activity_id,
		resident_id,
	) as Array
	tasks = _available_work_tasks(tasks)
	if tasks.is_empty():
		return false
	var candidates := _activity_runtime.query_preflight_candidates(
		_activity_social_state_for(resident_id, activity_id),
		String(resident.get("currentPlace", "")),
		activity_id,
	) as Array
	return not _matching_work_tasks_for_targets(
		tasks,
		_activity_candidate_physical_targets(candidates),
	).is_empty()


func _apply_bulletin_activity_availability(
	resident_id: String,
	option: Dictionary,
) -> void:
	if not bool(option.get("available", false)):
		return
	var activity_id := String(option.get("activityId", ""))
	var available := _bulletin_activity_is_available(
		resident_id,
		activity_id,
	)
	var disabled_reason := ""
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID:
		if not available:
			disabled_reason = "BULLETIN_NOTHING_UNREAD"
	elif activity_id == SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID:
		if not available:
			disabled_reason = "BULLETIN_NO_CONFIRMED_POST"
	else:
		return
	option["available"] = available
	option["disabledReason"] = disabled_reason


func _bulletin_activity_is_available(
	resident_id: String,
	activity_id: String,
) -> bool:
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID:
		return (
			announcement_unread_count(resident_id) > 0
			or _has_active_social_capability(
				resident_id,
				"bulletin.read",
			)
		)
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID:
		return (
			_has_active_social_capability(
				resident_id,
				"bulletin.publish",
			)
			or not _natural_bulletin_task_for_resident(
				resident_id,
			).is_empty()
		)
	return true


func _interrupt_unsafe_weather_activities() -> void:
	if _activity_runtime == null:
		return
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in _resident_order:
		resident_ids.append(String(resident_id_value))
	for resident_id in resident_ids:
		if not _residents.has(resident_id):
			continue
		var resident := _residents[resident_id] as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		var execution := _activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if execution.is_empty():
			continue
		var availability := _activity_runtime.activity_weather_availability(
			String(execution.get("activityId", "")),
			String(execution.get("placeId", "")),
			String(execution.get("role", "")),
			get_weather(),
		) as Dictionary
		if bool(availability.get("available", true)):
			continue
		var reason := String(
			availability.get(
				"reason",
				"当前天气不适合继续这项活动。",
			)
		).strip_edges()
		if reason.is_empty():
			reason = "当前天气不适合继续这项活动。"
		_interrupt_action(resident_id, reason)


func perform_activity_step(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
) -> Dictionary:
	return _perform_activity_step_internal(
		resident_id,
		plan_id,
		plan_revision,
		step,
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_DIRECT,
		"",
		-1,
		true,
	)


func _perform_activity_step_internal(
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
	source_contract: String,
	source_action_id: String,
	duration_cap_minutes := -1,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var probe_lap_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if not _valid_activity_source(source_contract, source_action_id):
		return _command_failure(
			"ACTIVITY_STATE_CHANGED",
			["activity.perform 内部来源合同无效"],
		)
	var normalized_resident_id := resident_id.strip_edges()
	if normalized_resident_id.is_empty() or not _residents.has(
		normalized_resident_id
	):
		return _command_failure(
			"ACTIVITY_STATE_CHANGED",
			["activity.perform 必须使用稳定 residentId"],
		)
	var resident := _residents[normalized_resident_id] as Dictionary
	var step_target := (
		step.get("target", {}) as Dictionary
		if step.get("target") is Dictionary
		else {}
	)
	var requested_activity_id := String(
		step_target.get("activityId", "")
	)
	if (
		requested_activity_id == SLEEP_ACTIVITY_ID
		and not _resident_sleep_needed(resident)
	):
		return _command_failure(
			"ACTIVITY_NOT_ELIGIBLE",
			["当前精力还足，不需要睡觉"],
		)
	if requested_activity_id == "activity_dining_collect_meal":
		var dining_full_failure := DINING_SERVICE.collect_full_failure(self, normalized_resident_id, int(_environment.get_absolute_minute()))
		if not dining_full_failure.is_empty():
			return dining_full_failure
	var activity_social_state := _activity_social_state_for(
		normalized_resident_id,
		requested_activity_id,
	)
	if (
		requested_activity_id
		in [SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID, SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID]
		and not _bulletin_activity_is_available(
			normalized_resident_id,
			requested_activity_id,
		)
	):
		return _command_failure(
			"ACTIVITY_NOT_ELIGIBLE",
			[
				(
					"公告栏当前没有可阅读的新公告"
					if requested_activity_id == SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID
					else "没有已确认的公告内容，不能张贴"
				)
			],
		)
	var validated := _activity_runtime.validate_step(
		normalized_resident_id,
		plan_id,
		plan_revision,
		step,
		activity_social_state,
		String(resident.get("currentPlace", "")),
		get_weather(),
	) as Dictionary
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activity_validate")
	if validated.get("ok") != true:
		return _decorate_command_result(validated)
	var validated_candidates := validated.get("candidates", []) as Array
	if (
		not validated_candidates.is_empty()
		and String(
			(validated_candidates[0] as Dictionary).get("role", ""),
		) == "visitor"
		and not _visitor_onsite_occupation_service_is_staffed(
			normalized_resident_id,
			requested_activity_id,
		)
	):
		return _command_failure(
			"OCCUPATION_SERVICE_UNSTAFFED",
			["对应岗位当前无人值守，不能开始这项服务活动"],
		)
	if validated.get("idempotent") == true:
		if not bool(_activity_runtime.execution_source_matches(
			normalized_resident_id,
			plan_id,
			plan_revision,
			step,
			source_contract,
			source_action_id,
		)):
			return _command_failure(
				"ACTIVITY_STATE_CHANGED",
				["相同 activity 幂等键不能跨执行来源合同复用"],
			)
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"idempotent": true,
			"execution": _safe_activity_execution(
				validated.get("execution", {}) as Dictionary
			),
		})
	var task_requirement := _validate_activity_work_task(
		normalized_resident_id,
		resident,
		validated,
	)
	if task_requirement.get("ok") != true:
		return _decorate_command_result(task_requirement)
	_attach_activity_source(
		validated,
		source_contract,
		source_action_id,
	)
	var current_action := resident.get("currentAction", {}) as Dictionary
	var current_activity_execution := {}
	if not current_action.is_empty():
		current_activity_execution = _activity_runtime.execution_for_action(
			normalized_resident_id,
			String(current_action.get("action_id", "")),
		) as Dictionary
	var preflight := {}
	if not current_activity_execution.is_empty():
		if not allow_current_activity_interrupt:
			return _command_failure(
				"ACTIVITY_STATE_CHANGED",
				["居民已有活动正在执行，普通 activity.perform 必须等当前活动完成"],
			)
		_interrupt_action(
			normalized_resident_id,
			"被新的 activity.perform 替换",
		)
		validated = _activity_runtime.validate_step(
			normalized_resident_id,
			plan_id,
			plan_revision,
			step,
			activity_social_state,
			String(resident.get("currentPlace", "")),
			get_weather(),
		) as Dictionary
		if validated.get("ok") != true:
			return _decorate_command_result(validated)
		_attach_activity_source(
			validated,
			source_contract,
			source_action_id,
		)
		preflight = _preflight_activity_candidates(resident, validated)
		if preflight.get("ok") != true:
			return _decorate_command_result(preflight)
	else:
		preflight = _preflight_activity_candidates(resident, validated)
		if preflight.get("ok") != true:
			return _decorate_command_result(preflight)
		if not current_action.is_empty():
			_append_action_result_without_schedule(
				normalized_resident_id,
				String(current_action.get("action_id", "")),
				"replaced",
				"居民开始执行新的 activity.perform",
			)
			resident["currentAction"] = {}
			resident["actionSuspendedAbsoluteMinute"] = -1
			validated = _activity_runtime.validate_step(
				normalized_resident_id,
				plan_id,
				plan_revision,
				step,
				activity_social_state,
				String(resident.get("currentPlace", "")),
				get_weather(),
			) as Dictionary
			if validated.get("ok") != true:
				return _decorate_command_result(validated)
			_attach_activity_source(
				validated,
				source_contract,
				source_action_id,
			)
			preflight = _preflight_activity_candidates(
				resident,
				validated,
			)
			if preflight.get("ok") != true:
				return _decorate_command_result(preflight)
	var reservation := _activity_runtime.reserve_execution(
		validated,
		String(preflight.get("slotId", "")),
		String(preflight.get("memberAnchorId", "")),
	) as Dictionary
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activity_preflight_and_reserve")
	if reservation.get("ok") != true:
		return _decorate_command_result(reservation)
	var execution := reservation.get("execution", {}) as Dictionary
	_bind_work_task_to_activity(
		normalized_resident_id,
		execution,
	)
	var action := (
		preflight.get("action", {}) as Dictionary
	).duplicate(true)
	var public_action_thought := String(
		execution.get("reason", "")
	).strip_edges()
	if not public_action_thought.is_empty():
		action["line"] = public_action_thought
	var duration_minutes := int(execution.get("remainingTicks", 0))
	if duration_cap_minutes > 0:
		duration_minutes = mini(duration_minutes, duration_cap_minutes)
	action["durationMinutes"] = duration_minutes
	# Activity effects are committed by the activity runtime exactly once.
	# The reused prop action must therefore not apply the prop compatibility
	# effect table a second time.
	action["effects"] = {}
	action["sourceContract"] = String(
		execution.get("sourceContract", "")
	)
	action["sourceActionId"] = String(
		execution.get("sourceActionId", "")
	)
	if duration_cap_minutes > 0:
		_activity_runtime.sync_remaining_ticks(
			normalized_resident_id,
			_prop_approach_duration_minutes(action) + duration_minutes,
		)
	resident["currentAction"] = action
	(resident.get("usedActionIds", {}) as Dictionary)[
		String(action.get("action_id", ""))
	] = true
	if bool(action.get("consumeRouteConnector", false)):
		resident["routeConnector"] = []
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = "正在%s" % String(
		execution.get("activityLabel", "")
	)
	_start_sleep_leave_if_work_expected(
		resident,
		action,
		execution,
	)
	_bump_world_revision()
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activity_revision")
	_emit_activity_lifecycle(
		"started",
		normalized_resident_id,
		execution,
		"",
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activity_lifecycle")
	_emit_resident_state_changed(normalized_resident_id)
	WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activity_resident_emit")
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"execution": _safe_activity_execution(execution),
	})


func _start_sleep_leave_if_work_expected(
	resident: Dictionary,
	action: Dictionary,
	execution: Dictionary,
) -> void:
	if ACTIVITY_SCALARS.start_sleep_leave(
		resident,
		action,
		execution,
		bool(_life_rhythm_snapshot(resident).get("work_expected", false)),
		_prop_approach_duration_minutes(action),
	):
		WORK_SETTLEMENT.refresh_staffing_after_attendance_change(self)


func _clear_sleep_leave(resident: Dictionary) -> void:
	if ACTIVITY_SCALARS.clear_sleep_leave(resident):
		WORK_SETTLEMENT.refresh_staffing_after_attendance_change(self)


func _bind_work_task_to_activity(
	resident_id: String,
	execution: Dictionary,
) -> void:
	if String(execution.get("role", "")) != "worker":
		return
	var resident := _residents.get(resident_id, {}) as Dictionary
	var activity_id := String(execution.get("activityId", ""))
	var occupation_id := _work_occupation_id_for_activity(
		resident_id,
		activity_id,
	)
	if occupation_id.is_empty() or activity_id.is_empty():
		return
	var candidates := _work_tasks.tasks_for_activity(
		occupation_id,
		activity_id,
		resident_id,
	) as Array
	candidates = _available_work_tasks(candidates)
	if candidates.is_empty():
		return
	var physical_target := _activity_runtime.execution_physical_target(
		execution,
	) as Dictionary
	var execution_targets: Array[Dictionary] = []
	if not physical_target.is_empty():
		execution_targets.append(physical_target)
	candidates = _matching_work_tasks_for_targets(
		candidates,
		execution_targets,
	)
	if candidates.is_empty():
		return
	var claimed := _claim_specific_work_task(
		candidates[0] as Dictionary,
		occupation_id,
		resident_id,
	)
	if claimed.get("ok") != true:
		return
	var task := claimed.get("task", {}) as Dictionary
	var action_id := String(execution.get("actionId", ""))
	if action_id.is_empty():
		return
	_activity_work_task_bindings[
		_work_task_binding_key(resident_id, action_id)
	] = String(task.get("taskId", ""))


func _validate_activity_work_task(
	resident_id: String,
	resident: Dictionary,
	validated: Dictionary,
) -> Dictionary:
	var candidates := validated.get("candidates", []) as Array
	if candidates.is_empty():
		return {
			"ok": false,
			"errorCode": "ACTIVITY_NOT_ELIGIBLE",
			"retryable": true,
			"errors": ["当前活动没有合法目标"],
		}
	if String((candidates[0] as Dictionary).get("role", "")) != "worker":
		return {"ok": true}
	var activity_id := String(validated.get("activityId", ""))
	if _work_task_capabilities_for_activity(activity_id).is_empty():
		return {"ok": true}
	var occupation_id := _work_occupation_id_for_activity(
		resident_id,
		activity_id,
	)
	var tasks := _work_tasks.tasks_for_activity(
		occupation_id,
		activity_id,
		resident_id,
	) as Array
	if not tasks.is_empty():
		return {"ok": true}
	return {
		"ok": false,
		"errorCode": "WORK_TASK_REQUIRED",
		"retryable": true,
		"errors": ["当前没有需要处理的真实职业任务"],
	}


func _work_task_capabilities_for_activity(
	activity_id: String,
) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _work_tasks.capabilities_for_activity(
		activity_id,
	) as Array:
		result.append(String(value))
	return result


func _release_work_task_from_activity(
	resident_id: String,
	execution: Dictionary,
	lifecycle: String,
) -> void:
	var action_id := String(execution.get("actionId", ""))
	var binding_key := _bound_work_task_binding_key(
		resident_id,
		action_id,
	)
	if binding_key.is_empty():
		return
	var task_id := String(
		_activity_work_task_bindings.get(binding_key, ""),
	)
	_activity_work_task_bindings.erase(binding_key)
	var task := _work_tasks.task(task_id) as Dictionary
	if (
		task.is_empty()
		or String(task.get("state", "")) != "in_progress"
	):
		return
	var reason := (
		"活动过程已完成，等待 World 提交实际结果"
		if lifecycle == "completed"
		else "活动过程%s，任务保留等待重新决定"
		% ("被中断" if lifecycle == "interrupted" else "失败")
	)
	_work_tasks.wait_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		reason,
	)


func _bound_work_task_binding_key(
	resident_id: String,
	action_id: String,
) -> String:
	var exact_key := _work_task_binding_key(resident_id, action_id)
	if _activity_work_task_bindings.has(exact_key):
		return exact_key
	var resident_prefix := "%s:" % resident_id
	var resident_bindings: Array[String] = []
	for key_value: Variant in _activity_work_task_bindings:
		var candidate_key := String(key_value)
		if candidate_key.begins_with(resident_prefix):
			resident_bindings.append(candidate_key)
	return (
		resident_bindings[0]
		if resident_bindings.size() == 1
		else ""
	)


func _work_task_binding_key(
	resident_id: String,
	action_id: String,
) -> String:
	return "%s:%s" % [resident_id, action_id]


func _valid_activity_source(
	source_contract: String,
	source_action_id: String,
) -> bool:
	if source_contract == ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_DIRECT:
		return source_action_id.is_empty()
	if source_contract == ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_LEGACY_PROP:
		return (
			not source_action_id.is_empty()
			and source_action_id == source_action_id.strip_edges()
		)
	if source_contract == ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_AGENT_ACTIVITY:
		return (
			not source_action_id.is_empty()
			and source_action_id == source_action_id.strip_edges()
		)
	return false


func _attach_activity_source(
	validated: Dictionary,
	source_contract: String,
	source_action_id: String,
) -> void:
	validated["sourceContract"] = source_contract
	validated["sourceActionId"] = source_action_id


func get_resident_movement_snapshot(resident_ref: String) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	var resident := _residents[resident_id] as Dictionary
	if CONVERSATION_RUNTIME._resident_has_suspended_conversation(self, resident):
		var held_position := (
			resident.get("position", Vector2.ZERO) as Vector2
		)
		return {
			"residentId": resident_id,
			"spaceId": String(resident.get("spaceId", "")),
			"regionId": String(resident.get("regionId", "")),
			"currentPlace": String(resident.get("currentPlace", "")),
			"position": held_position,
			"target": {
				"spaceId": String(resident.get("spaceId", "")),
				"position": held_position,
			},
			"isMoving": false,
			"presentationPath": [],
			"routeCrossesPortal": false,
			"movementRevision": int(resident.get("movementRevision", 1)),
			"worldRevision": _world_revision,
		}
	var target := _resident_movement_target(resident)
	var is_moving := not target.is_empty()
	if target.is_empty():
		target = {
			"spaceId": String(resident.get("spaceId", "")),
			"position": resident.get("position", Vector2.ZERO) as Vector2,
		}
	# Model latency must not turn a confirmed World route into an idle
	# presentation.  A pending next decision only blocks a resident that has
	# no current action; confirmed movement remains authoritative.
	var movement_blocked := false
	var action := resident.get("currentAction", {}) as Dictionary
	if String(action.get("type", "")) == "用道具":
		var absolute_minute := int(_environment.get_absolute_minute())
		var elapsed := maxi(
			0,
			absolute_minute - int(action.get("startedAbsoluteMinute", absolute_minute)),
		)
		movement_blocked = (
			movement_blocked
			or elapsed >= _prop_approach_duration_minutes(action)
		)
	return {
		"residentId": resident_id,
		"spaceId": String(resident.get("spaceId", "")),
		"regionId": String(resident.get("regionId", "")),
		"currentPlace": String(resident.get("currentPlace", "")),
		"position": resident.get("position", Vector2.ZERO) as Vector2,
		"target": target,
		"isMoving": is_moving and not movement_blocked,
		"presentationPath": _resident_presentation_path(resident),
		"routeCrossesPortal": _resident_route_crosses_portal(resident),
		"movementRevision": int(resident.get("movementRevision", 1)),
		"worldRevision": _world_revision,
	}


func _resident_presentation_path(resident: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var action := resident.get("currentAction", {}) as Dictionary
	var action_type := String(action.get("type", ""))
	if action_type == "待着" and action.has("idlePathPoints"):
		var absolute_minute := int(_environment.get_absolute_minute())
		var elapsed := maxi(
			0,
			absolute_minute
				- int(action.get("startedAbsoluteMinute", absolute_minute)),
		)
		if elapsed >= int(action.get("idleMoveDurationMinutes", 0)):
			return result
		for point_value: Variant in action.get("idlePathPoints", []) as Array:
			if point_value is not Vector2:
				return []
			var point := point_value as Vector2
			if not point.is_finite():
				return []
			if result.is_empty() or result[-1].distance_to(point) > 0.001:
				result.append(point)
		return result
	if action_type == "用道具":
		for point_value: Variant in action.get("pathPoints", []) as Array:
			if point_value is not Vector2:
				return []
			var point := point_value as Vector2
			if not point.is_finite():
				return []
			if result.is_empty() or result[-1].distance_to(point) > 0.001:
				result.append(point)
		return result
	if action_type != "去":
		return result
	var route := action.get("route", {}) as Dictionary
	var positions := route.get("minutePositions", []) as Array
	if positions.is_empty():
		return result
	var absolute_minute := int(_environment.get_absolute_minute())
	var elapsed := maxi(
		0,
		absolute_minute - int(
			action.get("startedAbsoluteMinute", absolute_minute),
		),
	)
	var sample_index := mini(elapsed, positions.size() - 1)
	var sample_value: Variant = positions[sample_index]
	if sample_value is not Dictionary:
		return result
	var path_value: Variant = (sample_value as Dictionary).get(
		"presentationPath",
		[],
	)
	if path_value is not Array:
		return result
	for point_value: Variant in (path_value as Array):
		if point_value is not Dictionary:
			return []
		var point := point_value as Dictionary
		var x_value: Variant = point.get("x")
		var y_value: Variant = point.get("y")
		if (
			typeof(x_value) not in [TYPE_INT, TYPE_FLOAT]
			or typeof(y_value) not in [TYPE_INT, TYPE_FLOAT]
		):
			return []
		var position := Vector2(float(x_value), float(y_value))
		if not position.is_finite():
			return []
		if result.is_empty() or result[-1].distance_to(position) > 0.001:
			result.append(position)
	return result


func _resident_route_crosses_portal(resident: Dictionary) -> bool:
	var action := resident.get("currentAction", {}) as Dictionary
	if String(action.get("type", "")) != "去":
		return false
	var route := action.get("route", {}) as Dictionary
	for segment_value: Variant in route.get("segments", []) as Array:
		if (
			segment_value is Dictionary
			and String((segment_value as Dictionary).get("kind", ""))
				== "connection"
		):
			return true
	return false


func _resident_movement_target(resident: Dictionary) -> Dictionary:
	var action := resident.get("currentAction", {}) as Dictionary
	if (
		String(action.get("type", "")) == "待着"
		and action.get("idleTargetPosition") is Vector2
	):
		var absolute_minute := int(_environment.get_absolute_minute())
		var elapsed := maxi(
			0,
			absolute_minute
				- int(action.get("startedAbsoluteMinute", absolute_minute)),
		)
		if elapsed < int(action.get("idleMoveDurationMinutes", 0)):
			return {
				"spaceId": String(resident.get("spaceId", "")),
				"regionId": String(resident.get("regionId", "")),
				"placeName": String(resident.get("currentPlace", "")),
				"position": action.get("idleTargetPosition") as Vector2,
			}
	if String(action.get("type", "")) == "去":
		var positions := (
			(action.get("route", {}) as Dictionary).get("minutePositions", [])
			as Array
		)
		if positions.is_empty():
			return {}
		var sample := positions[-1] as Dictionary
		var position := sample.get("position", {}) as Dictionary
		return {
			"spaceId": String(sample.get("spaceId", "")),
			"regionId": String(sample.get("regionId", "")),
			"placeName": String(sample.get("placeName", "")),
			"position": Vector2(
				float(position.get("x", 0.0)),
				float(position.get("y", 0.0)),
			),
		}
	if String(action.get("type", "")) == "用道具":
		return {
			"spaceId": String(resident.get("spaceId", "")),
			"regionId": String(resident.get("regionId", "")),
			"placeName": String(resident.get("currentPlace", "")),
			"position": action.get(
				"targetPosition",
				resident.get("position", Vector2.ZERO),
			) as Vector2,
		}
	return {}


func get_all_resident_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_id in _resident_order:
		result.append(get_resident_state(resident_id))
	return result


# town_hud 专用轻量投影(A2):只算 HUD 实际消费的键,语义与完整投影键裁剪恒等。
func get_town_hud_resident_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_id in _resident_order:
		result.append(RESIDENT_STATE_PROJECTION.project_hud(
			self,
			_residents[resident_id] as Dictionary,
		))
	return result


func get_resident_detail(resident_ref: String) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	var resident := _residents[resident_id] as Dictionary
	return {
		"residentId": resident_id,
		"name": String((resident.get("attributes", {}) as Dictionary).get("name", "")),
		"attributes": (resident.get("attributes", {}) as Dictionary).duplicate(true),
		"socialState": (resident.get("socialState", {}) as Dictionary).duplicate(true),
		"runtimeState": _resident_state_projection(resident),
	}


func update_resident_social_profile(
	resident_ref: String,
	profile: Dictionary,
) -> Dictionary:
	var resident_id_result := _editable_resident_id(resident_ref)
	if not bool(resident_id_result.get("ok", false)):
		return resident_id_result
	var validation := _validate_social_profile(profile)
	if not bool(validation.get("ok", false)):
		return validation
	return _commit_resident_profile(
		String(resident_id_result.get("residentId", "")),
		{},
		validation.get("profile", {}) as Dictionary,
	)


func update_resident_profile(
	resident_ref: String,
	profile: Dictionary,
) -> Dictionary:
	var resident_id_result := _editable_resident_id(resident_ref)
	if not bool(resident_id_result.get("ok", false)):
		return resident_id_result
	for key_value: Variant in profile:
		var key := String(key_value)
		if key not in ["home", "job", "workplace", "attributes"]:
			return _command_failure(
				"RESIDENT_PROFILE_FIELD_NOT_EDITABLE",
				["居民资料不允许修改字段：%s" % key],
			)
	var attributes_value: Variant = profile.get("attributes")
	if not attributes_value is Dictionary:
		return _command_failure(
			"RESIDENT_PROFILE_ATTRIBUTES_REQUIRED",
			["居民公开属性必须是对象"],
		)
	var attributes := attributes_value as Dictionary
	for key_value: Variant in attributes:
		var key := String(key_value)
		if key not in [
			"gender",
			"age",
			"appearance",
			"desire",
			"personality",
			"speech",
			"interests",
			"customInterests",
		]:
			return _command_failure(
				"RESIDENT_PROFILE_FIELD_NOT_EDITABLE",
				["居民资料不允许修改字段：%s" % key],
			)
	var gender := String(attributes.get("gender", "")).strip_edges()
	if gender not in ["男", "女"]:
		return _command_failure(
			"RESIDENT_PROFILE_GENDER_INVALID",
			["居民性别仅支持男或女"],
		)
	var age_value: Variant = attributes.get("age")
	if typeof(age_value) not in [TYPE_INT, TYPE_FLOAT]:
		return _command_failure(
			"RESIDENT_PROFILE_AGE_INVALID",
			["居民年龄必须是数字"],
		)
	var age := int(age_value)
	if age < 1 or age > 120:
		return _command_failure(
			"RESIDENT_PROFILE_AGE_INVALID",
			["居民年龄需在 1 到 120 岁之间"],
		)
	var normalized_attributes := {
		"gender": gender,
		"age": age,
	}
	if attributes.has("appearance"):
		var appearance := String(attributes.get("appearance", "")).strip_edges()
		if (
			appearance.is_empty()
			or not appearance.begins_with("resident_wardrobe_v1:")
		):
			return _command_failure(
				"RESIDENT_PROFILE_APPEARANCE_INVALID",
				["居民外观必须来自正式衣柜"],
			)
		normalized_attributes["appearance"] = appearance
	for key in ["desire", "personality", "speech"]:
		var text := String(attributes.get(key, "")).strip_edges()
		if text.is_empty() or text.length() > 1200:
			return _command_failure(
				"RESIDENT_PROFILE_TEXT_INVALID",
				["居民资料 %s 不能为空且不能超过 1200 字" % key],
			)
		normalized_attributes[key] = text
	var interest_values := INTERESTS.normalize(
		attributes.get("interests", []),
	)
	var custom_interest_values := INTERESTS.normalize_custom(
		attributes.get("customInterests", []),
	)
	var interest_error := INTERESTS.profile_validation_error(
		interest_values,
		custom_interest_values,
	)
	if not interest_error.is_empty():
		return _command_failure(
			interest_error,
			["居民兴趣合计最多三项，自定义兴趣需为 1 到 20 个字且不能重复"],
		)
	normalized_attributes["interests"] = interest_values
	normalized_attributes["customInterests"] = custom_interest_values
	var social_validation := _validate_social_profile({
		"home": profile.get("home", ""),
		"job": profile.get("job", ""),
		"workplace": profile.get("workplace", ""),
	})
	if not bool(social_validation.get("ok", false)):
		return social_validation
	return _commit_resident_profile(
		String(resident_id_result.get("residentId", "")),
		normalized_attributes,
		social_validation.get("profile", {}) as Dictionary,
	)


func _editable_resident_id(resident_ref: String) -> Dictionary:
	if not _running:
		return _command_failure(
			"WORLD_NOT_RUNNING",
			["世界尚未运行，不能修改居民本局资料"],
		)
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"RESIDENT_IDENTITY_NOT_FOUND",
			["没有找到居民：%s" % resident_ref],
		)
	return {"ok": true, "residentId": resident_id}


func _validate_social_profile(profile: Dictionary) -> Dictionary:
	for key_value: Variant in profile:
		var key := String(key_value)
		if key not in ["home", "job", "workplace"]:
			return _command_failure(
				"RESIDENT_PROFILE_FIELD_NOT_EDITABLE",
				["居民总览不允许修改字段：%s" % key],
			)
	var home := String(profile.get("home", "")).strip_edges()
	var job := String(profile.get("job", "")).strip_edges()
	var workplace := String(profile.get("workplace", "")).strip_edges()
	if home.is_empty():
		return _command_failure(
			"RESIDENT_PROFILE_HOME_REQUIRED",
			["居民住所不能为空"],
		)
	var home_detail := get_place_detail(home)
	if home_detail.is_empty() or String(home_detail.get("type", "")) != "住家":
		return _command_failure(
			"RESIDENT_PROFILE_HOME_UNKNOWN",
			["居民住所不是本局可用住宅：%s" % home],
		)
	if job.is_empty():
		return _command_failure(
			"RESIDENT_PROFILE_JOB_REQUIRED",
			["居民职业不能为空"],
		)
	if workplace.is_empty() or get_place_detail(workplace).is_empty():
		return _command_failure(
			"RESIDENT_PROFILE_WORKPLACE_UNKNOWN",
			["居民工作地点不是本局可用地点：%s" % workplace],
		)
	return {
		"ok": true,
		"profile": {
			"home": home,
			"job": job,
			"workplace": workplace,
		},
	}


func _commit_resident_profile(
	resident_id: String,
	profile_attributes: Dictionary,
	social_profile: Dictionary,
) -> Dictionary:
	var resident := _residents[resident_id] as Dictionary
	var social := (resident.get("socialState", {}) as Dictionary).duplicate(true)
	var next_social := social_profile.duplicate(true)
	var attributes := (resident.get("attributes", {}) as Dictionary).duplicate(true)
	var next_attributes := attributes.duplicate(true)
	for key_value: Variant in profile_attributes:
		next_attributes[String(key_value)] = profile_attributes[key_value]
	var changed := social != next_social or attributes != next_attributes
	if not changed:
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"residentId": resident_id,
			"profile": next_social.duplicate(true),
			"attributes": _saved_profile_attributes(next_attributes),
		})
	resident["attributes"] = next_attributes
	resident["socialState"] = next_social
	_bump_world_revision(false)
	_emit_resident_state_changed(resident_id)
	_notify_world_revision()
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"residentId": resident_id,
		"profile": next_social.duplicate(true),
		"attributes": _saved_profile_attributes(next_attributes),
	})


func _saved_profile_attributes(attributes: Dictionary) -> Dictionary:
	return {
		"gender": String(attributes.get("gender", "")),
		"age": int(attributes.get("age", 0)),
		"appearance": String(attributes.get("appearance", "")),
		"desire": String(attributes.get("desire", "")),
		"personality": String(attributes.get("personality", "")),
		"speech": String(attributes.get("speech", "")),
		"interests": INTERESTS.normalize(
			attributes.get("interests", []),
		),
		"customInterests": INTERESTS.normalize_custom(
			attributes.get("customInterests", []),
		),
	}


func get_place_names() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _world_data.get("places", []) as Array:
		result.append(String((value as Dictionary).get("name", "")))
	result.sort()
	return result


# places 是随 _world_data 一起变化的静态列表，按名字建索引避免全量线性扫描。
func _place_record_for_name(place_name: String) -> Dictionary:
	if _place_by_name_cache.is_empty():
		for value: Variant in _world_data.get("places", []) as Array:
			var place := value as Dictionary
			_place_by_name_cache[String(place.get("name", ""))] = place
	return _place_by_name_cache.get(place_name, {}) as Dictionary


func get_place_detail(place_name: String) -> Dictionary:
	var found := _place_record_for_name(place_name)
	if not found.is_empty():
		var place := found
		var resident_names: Array[String] = []
		for resident_id in _resident_order:
			var resident := _residents[resident_id] as Dictionary
			if (
				_resident_is_present(resident)
				and String(resident.get("currentPlace", "")) == place_name
			):
				resident_names.append(_resident_display_name(resident_id))
		var owner_resident_id: Variant = null if String(place.get("type", "")) == "公共地点" else _owners.get(place_name)
		return {
			"name": place_name,
			"type": String(place.get("type", "")),
			"ownerResidentId": owner_resident_id,
			"owner": null if owner_resident_id == null else _person_name_for_id(String(owner_resident_id)),
			"summary": String(place.get("summary", "")),
			"spaceId": String(place.get("spaceId", "")),
			"capabilities": (place.get("capabilities", {}) as Dictionary).duplicate(true),
			"residentNames": resident_names,
			"playerAvatarPresent": (
				_player_avatar_present
				and String(_player_avatar.get("currentPlace", "")) == place_name
			),
			"props": PROP_QUERY.agent_props_at_place(
				_prop_query_data(),
				place_name,
			),
		}
	return {}


func upsert_dynamic_prop(
	prop_id: String,
	display_name: String,
	position: Vector2,
	active: bool = true,
) -> Dictionary:
	var normalized_id := prop_id.strip_edges()
	var normalized_name := display_name.strip_edges()
	if normalized_id.is_empty() or normalized_name.is_empty():
		return {
			"ok": false,
			"errorCode": "DYNAMIC_PROP_IDENTITY_INVALID",
		}
	_presentation_cue_cache.clear()
	if not active:
		var removed := _dynamic_props.erase(normalized_id)
		return {
			"ok": true,
			"status": "removed" if removed else "already_absent",
			"propId": normalized_id,
		}
	if not _running:
		return {
			"ok": false,
			"errorCode": "WORLD_NOT_RUNNING",
		}
	var membership := PERCEPTION_RUNTIME._membership(self, "town_outdoor", position)
	if membership.is_empty():
		membership = PERCEPTION_RUNTIME._nearest_outdoor_membership(self, position)
		if membership.is_empty():
			_dynamic_props.erase(normalized_id)
			return {
				"ok": false,
				"errorCode": "DYNAMIC_PROP_OUTSIDE_WORLD",
				"propId": normalized_id,
				"position": {"x": position.x, "y": position.y},
			}
	var approach_position := position + Vector2(0.0, 72.0)
	var approach_membership := PERCEPTION_RUNTIME._membership(self, 
		"town_outdoor",
		approach_position,
	)
	if approach_membership.is_empty():
		approach_position = position + Vector2(72.0, 0.0)
		approach_membership = PERCEPTION_RUNTIME._membership(self, 
			"town_outdoor",
			approach_position,
		)
	if approach_membership.is_empty():
		approach_position = position
	var prop := {
		"id": normalized_id,
		"name": normalized_name,
		"placeName": String(membership.get("placeName", "")),
		"actions": [
			{
				"verb": "摸摸",
				"durationMinutes": 5,
				"effects": {},
			},
		],
		"interaction": {
			"spaceId": "town_outdoor",
			"regionId": String(membership.get("regionId", "")),
			"anchorKind": "dynamic_animal",
			"actorFacing": "up",
			"position": [position.x, position.y],
			"approachPolyline": [
				[approach_position.x, approach_position.y],
				[position.x, position.y],
			],
		},
	}
	_dynamic_props[normalized_id] = prop
	return {
		"ok": true,
		"status": "registered",
		"propId": normalized_id,
		"placeName": prop["placeName"],
		"position": {"x": position.x, "y": position.y},
	}


func remove_dynamic_prop(prop_id: String) -> Dictionary:
	return upsert_dynamic_prop(prop_id, prop_id, Vector2.ZERO, false)


func get_dynamic_prop_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for prop_id_value: Variant in _dynamic_props:
		var prop := _dynamic_props.get(prop_id_value, {}) as Dictionary
		result.append(prop.duplicate(true))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("id", "")) < String(right.get("id", ""))
	)
	return result


func upsert_animal_presence(state: Dictionary) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	for field in [
		"animal_id",
		"display_name",
		"species",
		"exists",
		"position",
		"generation",
	]:
		if not state.has(field):
			return _command_failure(
				"ANIMAL_FACT_INVALID",
				["动物存在事实缺少字段：%s" % field],
			)
	var animal_id := String(state.get("animal_id", "")).strip_edges()
	var display_name := String(
		state.get("display_name", "")
	).strip_edges()
	var species := String(state.get("species", "")).strip_edges()
	var position_value: Variant = state.get("position")
	if (
		animal_id.is_empty()
		or display_name.is_empty()
		or species.is_empty()
		or not state.get("exists") is bool
		or not position_value is Vector2
		or not (position_value as Vector2).is_finite()
		or not state.get("generation") is int
		or int(state.get("generation", -1)) < 0
	):
		return _command_failure(
			"ANIMAL_FACT_INVALID",
			["动物存在事实字段无效"],
		)
	var exists := bool(state.get("exists"))
	var position := position_value as Vector2
	var previous := (
		_animal_facts.get(animal_id, {}) as Dictionary
	)
	if not exists and previous.is_empty():
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"status": "already_absent",
			"animal": {},
		})
	var place_id := String(previous.get("place_id", ""))
	if exists:
		var membership := PERCEPTION_RUNTIME._membership(self, "town_outdoor", position)
		if membership.is_empty():
			membership = PERCEPTION_RUNTIME._nearest_outdoor_membership(self, position)
		if membership.is_empty():
			return _command_failure(
				"ANIMAL_FACT_OUTSIDE_WORLD",
				["动物位置不属于当前小镇"],
			)
		place_id = String(membership.get("placeName", ""))
	var public_attention := bool(
		previous.get("public_attention", false)
	)
	var source_revision := int(
		previous.get("source_revision", 0)
	)
	var meaningful_change := (
		previous.is_empty()
		or bool(previous.get("exists", false)) != exists
		or String(previous.get("place_id", "")) != place_id
		or int(previous.get("generation", -1))
		!= int(state.get("generation"))
	)
	var attention_fact_changed := (
		not previous.is_empty()
		and public_attention
		and (
			not exists
			or String(previous.get("place_id", "")) != place_id
		)
	)
	if attention_fact_changed:
		source_revision += 1
		if not exists:
			public_attention = false
	var fact := {
		"animal_id": animal_id,
		"display_name": display_name,
		"species": species,
		"exists": exists,
		"place_id": place_id,
		"position": position,
		"generation": int(state.get("generation")),
		"public_attention": public_attention,
		"source_revision": source_revision,
		"expires_at": int(previous.get("expires_at", -1)),
		"source_event_ids": (
			previous.get("source_event_ids", []) as Array
		).duplicate(),
		"updated_at": int(
			_environment.get_absolute_minute()
		),
	}
	_animal_facts[animal_id] = fact
	if attention_fact_changed:
		var synced := _sync_animal_attention_fact(fact)
		if synced.get("ok") != true:
			return synced
	if meaningful_change:
		_bump_world_revision()
		var animal_event_type := "动物状态更新"
		if previous.is_empty() and exists:
			animal_event_type = "动物出现"
		elif bool(previous.get("exists", false)) and not exists:
			animal_event_type = "动物离开"
		elif String(previous.get("place_id", "")) != place_id:
			animal_event_type = "动物地点变化"
		_append_animal_log_event(animal_event_type, fact)
	return _decorate_command_result({
		"ok": true,
		"changed": meaningful_change,
		"status": "updated" if meaningful_change else "position_synced",
		"animal": fact.duplicate(true),
	})


func set_animal_public_attention(
	animal_id: String,
	active: bool,
	expires_at: int,
	source_event_ids: Array = [],
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var normalized_id := animal_id.strip_edges()
	var fact := (
		_animal_facts.get(normalized_id, {}) as Dictionary
	).duplicate(true)
	if fact.is_empty() or not bool(fact.get("exists", false)):
		return _command_failure(
			"ANIMAL_FACT_UNKNOWN",
			["只能让当前确实存在的动物成为公共关注"],
		)
	var now := int(_environment.get_absolute_minute())
	if active and expires_at <= now:
		return _command_failure(
			"ANIMAL_FACT_INVALID",
			["动物公共关注期限必须晚于当前时间"],
		)
	var normalized_event_ids: Array[String] = []
	for event_value: Variant in source_event_ids:
		if not event_value is String:
			return _command_failure(
				"ANIMAL_FACT_INVALID",
				["动物关注来源事件编号必须是文本"],
			)
		var event_id := String(event_value).strip_edges()
		if not event_id.is_empty() and not normalized_event_ids.has(
			event_id
		):
			normalized_event_ids.append(event_id)
	normalized_event_ids.sort()
	var unchanged: bool = (
		bool(fact.get("public_attention", false)) == active
		and int(fact.get("expires_at", -1)) == expires_at
		and fact.get("source_event_ids", []) == normalized_event_ids
	)
	if unchanged:
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"animal": fact,
		})
	fact["public_attention"] = active
	fact["expires_at"] = expires_at
	fact["source_event_ids"] = normalized_event_ids
	fact["source_revision"] = int(
		fact.get("source_revision", 0)
	) + 1
	fact["updated_at"] = int(
		_environment.get_absolute_minute()
	)
	_animal_facts[normalized_id] = fact
	var synced := _sync_animal_attention_fact(fact)
	if synced.get("ok") != true:
		return synced
	_append_animal_log_event(
		"动物成为公共关注" if active else "动物不再受关注",
		fact,
	)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"animal": fact.duplicate(true),
		"matter": (
			synced.get("matter", {}) as Dictionary
		).duplicate(true),
	})


func get_animal_fact_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var animal_ids: Array[String] = []
	for animal_id_value: Variant in _animal_facts:
		animal_ids.append(String(animal_id_value))
	animal_ids.sort()
	for animal_id: String in animal_ids:
		result.append(
			(
				_animal_facts.get(animal_id, {}) as Dictionary
			).duplicate(true)
		)
	return result


func _sync_animal_attention_fact(fact: Dictionary) -> Dictionary:
	return sync_animal_attention({
		"animal_id": String(fact.get("animal_id", "")),
		"source_revision": int(
			fact.get("source_revision", 0)
		),
		"exists": bool(fact.get("exists", false)),
		"public_attention": bool(
			fact.get("public_attention", false)
		),
		"place_id": String(fact.get("place_id", "")),
		"expires_at": int(fact.get("expires_at", -1)),
		"source_event_ids": (
			fact.get("source_event_ids", []) as Array
		).duplicate(),
	})


func _initialize_place_service_states() -> void:
	_place_service_states = _build_default_place_service_states(
		_world_data,
		_owners,
		_residents,
	)


func _build_default_place_service_states(
	world_data: Dictionary,
	_owners: Dictionary,
	residents: Dictionary = {},
	staffing_snapshot: Dictionary = {},
	residents_prevalidated_alive: bool = false,
) -> Dictionary:
	var result := {}
	for place_value: Variant in world_data.get("places", []) as Array:
		var place := place_value as Dictionary
		var profile_value: Variant = place.get("serviceProfile")
		if not profile_value is Dictionary:
			continue
		var profile := profile_value as Dictionary
		var place_id := String(place.get("name", "")).strip_edges()
		var helper_activity_id := String(
			profile.get("helperActivityId", "")
		).strip_edges()
		var service_occupation_id := _service_occupation_id(
			world_data,
			place_id,
			helper_activity_id,
		)
		var assigned_resident_ids: Array[String] = []
		if not staffing_snapshot.is_empty():
			for post_value: Variant in staffing_snapshot.get(
				"posts",
				[],
			) as Array:
				var post := post_value as Dictionary
				if String(post.get("occupationId", "")) != service_occupation_id:
					continue
				for resident_id_value: Variant in post.get(
					"responsibleResidentIds",
					[],
				) as Array:
					assigned_resident_ids.append(String(resident_id_value))
				break
		else:
			assigned_resident_ids = (
				_responsible_resident_ids_for_occupation(
					service_occupation_id,
				)
			)
		if assigned_resident_ids.is_empty():
			assigned_resident_ids = _resident_ids_for_occupation(
			world_data,
			residents,
			service_occupation_id,
			)
		assigned_resident_ids = assigned_resident_ids.filter(
			func(resident_id: String) -> bool:
				return (
					residents.has(resident_id)
					and (
						(
							String(
								(
									(
										residents.get(resident_id, {}) as Dictionary
									).get("arrivalState", {}) as Dictionary
								).get("status", "arrived"),
							) == "arrived"
							and not _resident_is_on_leave(
								residents.get(resident_id, {}) as Dictionary,
							)
						)
						if residents_prevalidated_alive
						else _resident_available_for_work(
							residents.get(resident_id, {}) as Dictionary,
						)
					)
				)
		)
		var owner_id := (
			assigned_resident_ids[0]
			if assigned_resident_ids.size() == 1
			else ""
		)
		var capacity := int(profile.get("capacity", 0))
		var request_activity_ids: Array[String] = []
		for activity_value: Variant in profile.get(
			"requestActivityIds",
			[],
		) as Array:
			var activity_id := String(activity_value).strip_edges()
			if not activity_id.is_empty():
				request_activity_ids.append(activity_id)
		if (
			place_id.is_empty()
			or service_occupation_id.is_empty()
			or helper_activity_id.is_empty()
			or capacity <= 0
			or request_activity_ids.is_empty()
			or not _world_data_has_activity_at_place(
				world_data,
				helper_activity_id,
				place_id,
			)
		):
			continue
		var valid_requests := request_activity_ids.all(
			func(activity_id: String) -> bool:
				return _world_data_has_activity_at_place(
					world_data,
					activity_id,
					place_id,
				)
		)
		if not valid_requests:
			continue
		result[place_id] = {
			"pressure_id": "service-pressure:%s" % place_id,
			"place_id": place_id,
			"owner_id": owner_id,
			"open": not owner_id.is_empty(),
			"service_occupation_id": service_occupation_id,
			"service_capacity": capacity,
			"helper_activity_id": helper_activity_id,
			"request_activity_ids": request_activity_ids,
			"pending_request_ids": [],
			"source_revision": 0,
			"expires_at": -1,
			"updated_at": -1,
		}
	return result


func _service_occupation_id(
	world_data: Dictionary,
	place_id: String,
	helper_activity_id: String,
) -> String:
	var helper_tags: Array = []
	for activity_value: Variant in world_data.get(
		"activityDefinitions",
		[],
	) as Array:
		if (
			activity_value is Dictionary
			and String((activity_value as Dictionary).get(
				"activityId",
				"",
			)) == helper_activity_id
		):
			helper_tags = (
				(activity_value as Dictionary).get("tags", []) as Array
			)
			break
	if helper_tags.is_empty():
		return ""
	var matches: Array[String] = []
	for occupation_value: Variant in world_data.get(
		"occupations",
		[],
	) as Array:
		if not occupation_value is Dictionary:
			continue
		var occupation := occupation_value as Dictionary
		if (
			String(occupation.get("primaryWorkplacePlace", ""))
			!= place_id
			or not _arrays_overlap(
				helper_tags,
				occupation.get("allowedActivityTags", []) as Array,
			)
		):
			continue
		matches.append(String(occupation.get("occupationId", "")))
	matches.sort()
	return matches[0] if matches.size() == 1 else ""


func _resident_ids_for_occupation(
	world_data: Dictionary,
	residents: Dictionary,
	occupation_id: String,
) -> Array[String]:
	var result: Array[String] = []
	if occupation_id.is_empty():
		return result
	var occupation: Dictionary = {}
	for occupation_value: Variant in world_data.get(
		"occupations",
		[],
	) as Array:
		if (
			occupation_value is Dictionary
			and String((occupation_value as Dictionary).get(
				"occupationId",
				"",
			)) == occupation_id
		):
			occupation = occupation_value as Dictionary
			break
	if occupation.is_empty():
		return result
	var labels: Array = [
		String(occupation.get("label", "")),
	]
	labels.append_array(occupation.get("aliases", []) as Array)
	for resident_id_value: Variant in residents:
		var resident_id := String(resident_id_value)
		var social_state := (
			(residents.get(resident_id, {}) as Dictionary).get(
				"socialState",
				{},
			) as Dictionary
		)
		if labels.has(String(social_state.get("job", ""))):
			result.append(resident_id)
	result.sort()
	return result


func _responsible_resident_ids_for_occupation(
	occupation_id: String,
) -> Array[String]:
	if occupation_id.is_empty() or _staffing == null:
		return []
	var post := _staffing.post_for_occupation(
		occupation_id,
	) as Dictionary
	var result: Array[String] = []
	for resident_id_value: Variant in post.get(
		"responsibleResidentIds",
		[],
	) as Array:
		var resident_id := String(resident_id_value)
		if not resident_id.is_empty() and not result.has(resident_id):
			result.append(resident_id)
	result.sort()
	return result


func _arrays_overlap(left: Array, right: Array) -> bool:
	for value: Variant in left:
		if right.has(value):
			return true
	return false


func record_place_service_request(
	place_id: String,
	request_id: String,
	active: bool,
	expires_at := -1,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var normalized_place := place_id.strip_edges()
	var normalized_request := request_id.strip_edges()
	if (
		normalized_request.is_empty()
		or not _place_service_states.has(normalized_place)
	):
		return _command_failure(
			"PLACE_SERVICE_REQUEST_INVALID",
			["地点没有可接入的服务配置，或请求编号为空"],
		)
	var state := (
		_place_service_states.get(normalized_place, {}) as Dictionary
	).duplicate(true)
	var pending: Array = (
		state.get("pending_request_ids", []) as Array
	).duplicate()
	var changed := false
	if active and not pending.has(normalized_request):
		pending.append(normalized_request)
		pending.sort()
		changed = true
	elif not active and pending.has(normalized_request):
		pending.erase(normalized_request)
		changed = true
	if not changed:
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"state": state,
		})
	state["pending_request_ids"] = pending
	state["source_revision"] = int(
		state.get("source_revision", 0)
	) + 1
	state["expires_at"] = (
		expires_at
		if expires_at >= 0
		else int(_environment.get_absolute_minute()) + 180
	)
	state["updated_at"] = int(
		_environment.get_absolute_minute()
	)
	_place_service_states[normalized_place] = state
	var work_task_sync := _sync_place_service_work_task(
		state,
		normalized_request,
		active,
	)
	if work_task_sync.get("ok") != true:
		return _decorate_command_result(work_task_sync)
	var refreshed := _refresh_place_service_pressure(
		normalized_place,
	)
	if refreshed.get("ok") != true:
		return refreshed
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"state": (
			_place_service_states.get(
				normalized_place,
				{},
			) as Dictionary
		).duplicate(true),
		"matter": (
			refreshed.get("matter", {}) as Dictionary
		).duplicate(true),
	})


func _sync_place_service_work_task(
	state: Dictionary,
	request_id: String,
	active: bool,
) -> Dictionary:
	var place_id := String(state.get("place_id", ""))
	var binding := _work_tasks.service_binding_for(
		place_id,
	) as Dictionary
	if binding.is_empty():
		return {
			"ok": true,
			"changed": false,
		}
	var source_kind := String(binding.get("sourceKind", ""))
	var existing := _work_tasks.active_task_for_source(
		source_kind,
		request_id,
	) as Dictionary
	if active:
		if not existing.is_empty():
			return {
				"ok": true,
				"changed": false,
				"task": existing,
			}
		return create_work_task({
			"taskId": "service-task:%s:%s:%d" % [
				place_id,
				request_id,
				int(state.get("source_revision", 0)),
			],
			"capability": String(binding.get("capability", "")),
			"sourceKind": source_kind,
			"sourceRef": request_id,
			"targets": [{
				"kind": "service_request",
				"ref": request_id,
			}],
			"requestedResultKind": String(
				binding.get("resultKind", ""),
			),
			"priority": CONTENT_CATALOG.TASK_PRIORITY["place_service_task"],
		})
	if existing.is_empty():
		return {
			"ok": true,
			"changed": false,
		}
	var cancelled := _work_tasks.cancel_task(
		String(existing.get("taskId", "")),
		"地点服务请求已撤销",
	) as Dictionary
	if cancelled.get("ok") != true:
		return cancelled
	_bump_world_revision()
	return {
		"ok": true,
		"changed": true,
		"task": (
			cancelled.get("task", {}) as Dictionary
		).duplicate(true),
	}


func set_place_service_open(
	place_id: String,
	open: bool,
	changed_by_resident_id: String = "",
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var normalized_place := place_id.strip_edges()
	if not _place_service_states.has(normalized_place):
		return _command_failure(
			"PLACE_SERVICE_STATE_UNKNOWN",
			["地点没有可接入的服务配置"],
		)
	var state := (
		_place_service_states.get(normalized_place, {}) as Dictionary
	).duplicate(true)
	if bool(state.get("open", true)) == open:
		return _decorate_command_result({
			"ok": true,
			"changed": false,
			"state": state,
		})
	state["open"] = open
	state["source_revision"] = int(
		state.get("source_revision", 0)
	) + 1
	state["updated_at"] = int(
		_environment.get_absolute_minute()
	)
	_place_service_states[normalized_place] = state
	if not open:
		_pause_conversation_follow_ups_for_service(
			normalized_place,
			"%s已经停止营业，需要重新决定怎样履行约定" % normalized_place,
		)
	var refreshed := _refresh_place_service_pressure(
		normalized_place,
	)
	if refreshed.get("ok") != true:
		return refreshed
	_emit_place_service_open_change(
		normalized_place,
		open,
		changed_by_resident_id,
	)
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"state": state,
	})


func _emit_place_service_open_change(
	place_id: String,
	open: bool,
	changed_by_resident_id: String,
) -> void:
	var summary := (
		"%s恢复营业了" % place_id
		if open
		else "%s今天停止营业了" % place_id
	)
	var event_source := {
		"type": "营业状态变化",
		"place_id": place_id,
		"open": open,
		"summary": summary,
		"changed_by_resident_id": changed_by_resident_id,
	}
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		if (
			resident_id == changed_by_resident_id
			or String(resident.get("currentPlace", "")) == place_id
		):
			_queue_world_event(
				resident_id,
				event_source,
			)


func _service_control_for_resident(
	resident: Dictionary,
) -> Dictionary:
	var resident_id := String(resident.get("residentId", ""))
	var current_place := String(resident.get("currentPlace", ""))
	var state := (
		_place_service_states.get(current_place, {}) as Dictionary
	)
	if (
		state.is_empty()
		or String(state.get("owner_id", "")) != resident_id
	):
		return {}
	return {
		"place_id": current_place,
		"open": bool(state.get("open", true)),
	}


func _closed_service_place_for_visitor(
	resident: Dictionary,
	place_id: String,
) -> bool:
	if DINING_SERVICE.can_admit_without_worker(self, place_id, int(_environment.get_absolute_minute())): return false
	var state := _place_service_states.get(place_id, {}) as Dictionary
	if state.is_empty() or bool(state.get("open", true)):
		return false
	var resident_id := String(resident.get("residentId", ""))
	if String(state.get("owner_id", "")) == resident_id:
		return false
	return String(
		(
			resident.get("socialState", {}) as Dictionary
		).get("workplace", "")
	) != place_id


func get_place_service_state_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var place_ids: Array[String] = []
	for place_id_value: Variant in _place_service_states:
		place_ids.append(String(place_id_value))
	place_ids.sort()
	for place_id: String in place_ids:
		var state := (
			_place_service_states.get(place_id, {}) as Dictionary
		).duplicate(true)
		state["active_workers"] = _active_place_service_workers(
			state,
		)
		state["waiting_requests"] = (
			state.get("pending_request_ids", []) as Array
		).size()
		result.append(state)
	return result


func _refresh_place_service_pressure(
	place_id: String,
) -> Dictionary:
	var state := (
		_place_service_states.get(place_id, {}) as Dictionary
	)
	if state.is_empty():
		return _command_failure(
			"PLACE_SERVICE_STATE_UNKNOWN",
			["地点服务状态不存在"],
		)
	return sync_place_service_pressure({
		"pressure_id": String(state.get("pressure_id", "")),
		"source_revision": int(
			state.get("source_revision", 0)
		),
		"place_id": String(state.get("place_id", "")),
		"owner_id": String(state.get("owner_id", "")),
		"open": bool(state.get("open", true)),
		"service_capacity": int(
			state.get("service_capacity", 0)
		),
		"active_workers": _active_place_service_workers(state),
		"waiting_requests": (
			state.get("pending_request_ids", []) as Array
		).size(),
		"helper_activity_id": String(
			state.get("helper_activity_id", "")
		),
		"expires_at": int(state.get("expires_at", -1)),
		"source_event_ids": (
			state.get("pending_request_ids", []) as Array
		).duplicate(),
	})


func _active_place_service_workers(state: Dictionary) -> int:
	var count := 0
	var helper_activity_id := String(
		state.get("helper_activity_id", "")
	)
	var place_id := String(state.get("place_id", ""))
	for resident_id: String in _resident_order:
		var resident := (
			_residents.get(resident_id, {}) as Dictionary
		)
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		var execution := _activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if (
			String(execution.get("status", "")) == "executing"
			and String(execution.get("activityId", ""))
			== helper_activity_id
			and String(execution.get("placeId", "")) == place_id
		):
			count += 1
	return count


func _apply_place_service_activity_completion(
	execution: Dictionary,
) -> void:
	var activity_id := String(execution.get("activityId", ""))
	if not _visitor_occupation_service_spec(
		"",
		activity_id,
	).is_empty():
		# The occupation-service runtime owns these request ids and their
		# inventory/result contracts. Do not also create a second anonymous
		# "activity-request" for the same customer action.
		return
	var place_id := String(execution.get("placeId", ""))
	if not _place_service_states.has(place_id):
		return
	var state := (
		_place_service_states.get(place_id, {}) as Dictionary
	).duplicate(true)
	var pending: Array = (
		state.get("pending_request_ids", []) as Array
	).duplicate()
	var changed := false
	if (
		state.get("request_activity_ids", []) as Array
	).has(activity_id):
		var request_id := "activity-request:%s" % String(
			execution.get("actionId", "")
		)
		if not pending.has(request_id):
			pending.append(request_id)
			pending.sort()
			changed = true
	elif (
		activity_id == String(
			state.get("helper_activity_id", "")
		)
		and not pending.is_empty()
	):
		var request_id := String(pending[0])
		var occupation_request := _occupation_services.request(
			request_id,
		) as Dictionary
		if (
			occupation_request.is_empty()
			or String(occupation_request.get("state", ""))
			in ["completed", "cancelled"]
		):
			pending.pop_front()
			changed = true
	if not changed:
		return
	state["pending_request_ids"] = pending
	state["source_revision"] = int(
		state.get("source_revision", 0)
	) + 1
	state["expires_at"] = int(
		_environment.get_absolute_minute()
	) + 180
	state["updated_at"] = int(
		_environment.get_absolute_minute()
	)
	_place_service_states[place_id] = state
	_rotate_completed_place_service_matter(
		state,
		execution,
	)
	_refresh_place_service_pressure(place_id)


func _create_clinic_treatment_task(
	request: Dictionary,
	now: int,
) -> Dictionary:
	var request_id := String(request.get("requestId", ""))
	var patient_id := String(
		request.get("requesterResidentId", ""),
	)
	return _work_tasks.create_task_for_occupations(
		{
			"taskId": "clinic-treatment-task:%s" % request_id,
			"capability": "care.treatment",
			"sourceKind": "follow_up_due",
			"sourceRef": request_id,
			"targets": [
				{"kind": "service_request", "ref": request_id},
				{"kind": "resident", "ref": patient_id},
			],
			"requestedResultKind": "care_outcome",
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["clinic_treatment"],
		},
		["occupation_clinic_practitioner"],
	) as Dictionary


func _occupation_service_item_allowed(
	kind: String,
	item_id: String,
) -> bool:
	return item_id in (
		{
			"dining_order": ["meal"],
			"cafe_order": [CONTENT_CATALOG.ITEM_BREWED_COFFEE, "pastry"],
			"grocer_sale": [
				CONTENT_CATALOG.ITEM_GENERAL_GOODS,
				CONTENT_CATALOG.ITEM_FISH,
				CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			],
			"flower_sale": [CONTENT_CATALOG.ITEM_FRESH_FLOWERS, CONTENT_CATALOG.ITEM_BOUQUET],
		}.get(kind, []) as Array
	)


func _apply_consumed_service_item(
	resident_id: String,
	item_id: String,
) -> void:
	var resident := _residents.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return
	var activity_state := (
		resident.get("activityState", {}) as Dictionary
	).duplicate(true)
	if item_id == "meal":
		activity_state["satiety"] = clampi(
			int(activity_state.get("satiety", 50)) + 35,
			0,
			100,
		)
	elif item_id in [CONTENT_CATALOG.ITEM_BREWED_COFFEE, "pastry"]:
		activity_state["energy"] = clampi(
			int(activity_state.get("energy", 50)) + 15,
			0,
			100,
		)
		if item_id == "pastry":
			activity_state["satiety"] = clampi(
				int(activity_state.get("satiety", 50)) + 12,
				0,
				100,
			)
	else:
		return
	resident["activityState"] = activity_state
	_sync_body_from_activity_needs(resident, activity_state)


func _performance_audience_ids(
	performer_id: String,
	place_id: String,
	day_index: int,
) -> Array[String]:
	if day_index < 0:
		return []
	var performer := _residents.get(performer_id, {}) as Dictionary
	var performer_position := performer.get(
		"position",
		Vector2.ZERO,
	) as Vector2
	var result: Array[String] = []
	for resident_id: String in _resident_order:
		if resident_id == performer_id:
			continue
		var resident := _residents.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			_resident_is_present(resident)
			and String(resident.get("currentPlace", "")) == place_id
			and String(action.get("type", "")) == "待着"
			and int(action.get("performanceDayIndex", -1)) == day_index
			and (
				resident.get("position", Vector2.ZERO) as Vector2
			).distance_to(performer_position) <= 640.0
		):
			result.append(resident_id)
	result.sort()
	return result


func _record_staffing_trial_from_result(
	resident_id: String,
	occupation_id: String,
	evidence: Dictionary,
) -> void:
	var trial := _staffing.active_trial_for(
		resident_id,
		occupation_id,
	) as Dictionary
	if trial.is_empty():
		return
	var result := _staffing.record_trial_result(
		String(trial.get("arrangementId", "")),
		true,
		evidence,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return
	_staffing.rebuild(
		_residents,
		int(_environment.get_absolute_minute()),
	)
	_sync_staffing_matters()


func _visitor_occupation_service_spec(
	resident_id: String,
	activity_id: String,
) -> Dictionary:
	match activity_id:
		"activity_cafe_order":
			return {
				"kind": "cafe_order",
				"requesterResidentId": resident_id,
				"itemId": CONTENT_CATALOG.ITEM_BREWED_COFFEE,
			}
		"activity_clinic_consult":
			var clinic_request := {
				"kind": "clinic",
				"requesterResidentId": resident_id,
			}
			var condition_context := _clinic_condition_request_context(
				resident_id,
			)
			if not condition_context.is_empty():
				clinic_request["subjectRef"] = String(
					condition_context.get("subjectRef", ""),
				)
				clinic_request["context"] = (
					condition_context.get("context", {}) as Dictionary
				).duplicate(true)
			return clinic_request
		"activity_library_checkout":
			var borrowed_loan := _occupation_services.borrowed_loan_for_resident(
				resident_id,
			) as Dictionary
			if not borrowed_loan.is_empty():
				return {
					"kind": "library_return",
					"requesterResidentId": resident_id,
					"subjectRef": String(
						borrowed_loan.get("loanId", ""),
					),
				}
			var book_ids := [
				"book_plant_reference",
				"book_town_history",
				"book_practical_crafts",
			]
			return {
				"kind": "library_loan",
				"requesterResidentId": resident_id,
				"itemId": book_ids[
					posmod(hash(resident_id), book_ids.size())
				],
			}
		"activity_library_research":
			return {
				"kind": "library_assist",
				"requesterResidentId": resident_id,
				"subjectRef": "请馆员协助查找资料",
			}
		"activity_town_hall_civic_service", "activity_town_hall_fill_form":
			return {
				"kind": "civic_request",
				"requesterResidentId": resident_id,
				"subjectRef": "居民提交的日常镇务",
			}
		"activity_town_hall_meeting":
			var invitation_subject := "居民邀请的广场小演出:%s:%d" % [
				resident_id,
				int(_environment.get_absolute_minute()) / 1440,
			]
			if bool(_occupation_services.has_active_request(
				"performance",
				invitation_subject,
			)):
				return {}
			return {
				"kind": "performance",
				"requesterResidentId": resident_id,
				"subjectRef": invitation_subject,
				"context": {"generatedFromResidentInvitation": true},
			}
		"activity_workshop_handoff_repair":
			return {
				"kind": "repair",
				"requesterResidentId": resident_id,
				"subjectRef": "居民带来交接的日常器物",
			}
		"activity_dining_collect_meal":
			return {
				"kind": "dining_order",
				"requesterResidentId": resident_id,
				"itemId": "meal",
			}
		"activity_market_buy_general_goods":
			return {
				"kind": "grocer_sale",
				"requesterResidentId": resident_id,
				"itemId": CONTENT_CATALOG.ITEM_GENERAL_GOODS,
			}
		"activity_market_buy_fish":
			return {
				"kind": "grocer_sale",
				"requesterResidentId": resident_id,
				"itemId": CONTENT_CATALOG.ITEM_FISH,
			}
		"activity_market_buy_flowers":
			var flower_home := _home_place_for_resident(resident_id)
			var wants_delivery := (
				not flower_home.is_empty()
				and posmod(hash("%s:%d" % [
					resident_id,
					int(_environment.get_absolute_minute()) / 1440,
				]), 2) == 0
			)
			return {
				"kind": "flower_sale",
				"requesterResidentId": resident_id,
				"itemId": CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
				"context": {
					"deliveryRequested": wants_delivery,
					"destinationPlaceId": flower_home,
				},
			}
	return {}


func _ensure_facility_cleanup_task(
	source_kind: String,
	now: int,
) -> void:
	var service_snapshot := _occupation_services.snapshot(
	) as Dictionary
	var count := (
		int(service_snapshot.get("dirtyDishCount", 0))
		if source_kind == "dirty_dishes"
		else int(service_snapshot.get("usedCafeTableCount", 0))
	)
	if count <= 0:
		return
	var source_ref := (
		"public-dining-dirty-dishes"
		if source_kind == "dirty_dishes"
		else "cafe-used-tables"
	)
	if not (
		_work_tasks.active_task_for_source(
			source_kind,
			source_ref,
		) as Dictionary
	).is_empty():
		return
	_ensure_production_task({
		"taskId": "%s-cleanup:%d:%d"
			% [source_kind, now, count],
		"capability": (
			"food.cleanup"
			if source_kind == "dirty_dishes"
			else "cafe.handoff"
		),
		"sourceKind": source_kind,
		"sourceRef": source_ref,
		"targets": [{
			"kind": "prop",
			"ref": (
				"公共食堂水槽"
				if source_kind == "dirty_dishes"
				else "花房咖啡馆西北座椅"
			),
		}],
		"requestedResultKind": (
			"dish_state_change"
			if source_kind == "dirty_dishes"
			else "cleanliness_change"
		),
		"createdAtMinute": now,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["facility_cleanup"],
	})


func _rotate_completed_place_service_matter(
	state: Dictionary,
	execution: Dictionary,
) -> void:
	if (
		(state.get("pending_request_ids", []) as Array).is_empty()
		or _active_place_service_workers(state) > 0
	):
		return
	var place_id := String(state.get("place_id", ""))
	var pressure_id := String(state.get("pressure_id", ""))
	var matter := _social_matters.find_active_matter(
		"place_service_pressure",
		pressure_id,
		[place_id],
	) as Dictionary
	if (
		String(matter.get("state", ""))
		not in ["assigned", "executing"]
		or _matter_has_active_social_participants(matter)
	):
		return
	var matter_id := String(matter.get("matter_id", ""))
	var closed := _social_matters.close_matter(
		matter_id,
		"social.resolve.service_reduced",
		"service_help_completed",
		[
			{
				"result_id": "service-cycle:%s"
				% String(execution.get("actionId", "")),
				"activity_id": String(
					execution.get("activityId", "")
				),
				"place_id": place_id,
			}
		],
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if closed.get("ok") == true:
		_emit_social_matter_summary(matter_id)


func get_all_place_details() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for place_name in get_place_names():
		result.append(get_place_detail(place_name))
	return result


func get_player_avatar_state() -> Dictionary:
	var state := _player_avatar.duplicate(true)
	state["present"] = _player_avatar_present
	var nearby_ids := (_player_avatar.get("nearby", []) as Array).duplicate()
	var nearby_names: Array[String] = []
	for resident_id_value: Variant in nearby_ids:
		nearby_names.append(_resident_display_name(String(resident_id_value)))
	state["nearbyResidentIds"] = nearby_ids
	state["nearby"] = nearby_names
	return state


func get_public_conflict_projection() -> Dictionary:
	if _conflict_controller == null:
		return _empty_conflict_projection()
	return (
		_conflict_controller.get_public_projection() as Dictionary
	).duplicate(true)


func submit_conflict_attack(intent: Dictionary) -> Dictionary:
	if not _running or _conflict_controller == null:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	for field: String in ["attackerId", "targetId"]:
		var actor_id := String(intent.get(field, "")).strip_edges()
		if not actor_id.is_empty() and not _resident_is_alive(actor_id):
			return _command_failure("RESIDENT_DEAD", ["死亡居民不能参与冲突"])
		if not _conflict_actor_is_available(actor_id):
			return _command_failure(
				"CONFLICT_ACTOR_NOT_AVAILABLE",
				["冲突参与者当前不在场"],
			)
	var before_revision := _conflict_runtime_revision()
	var result := _conflict_controller.begin_attack(intent) as Dictionary
	return _complete_conflict_command(result, before_revision)


func submit_conflict_tension_action(intent: Dictionary) -> Dictionary:
	if not _running or _conflict_controller == null:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	for field: String in ["actorId", "targetId"]:
		if not _conflict_actor_is_available(String(intent.get(field, ""))):
			return _command_failure(
				"CONFLICT_ACTOR_NOT_AVAILABLE",
				["争执参与者当前不在场"],
			)
	var before_revision := _conflict_runtime_revision()
	var result := _conflict_controller.apply_tension_action(intent,) as Dictionary
	return _complete_conflict_command(result, before_revision)


func submit_avatar_area_attack(intent: Dictionary) -> Dictionary:
	if not _running or _conflict_controller == null:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if not _conflict_actor_is_available(String(intent.get("attackerId", ""))):
		return _command_failure(
			"AVATAR_NOT_PRESENT",
			["化身当前不在小镇中"],
		)
	var before_revision := _conflict_runtime_revision()
	var result := _conflict_controller.begin_avatar_area_attack(intent,) as Dictionary
	TRAVELER_RELATIONSHIP_BRIDGE.record_attack_result(self, result, intent)
	return _complete_conflict_command(result, before_revision)

func submit_conflict_response(
	conflict_id: String,
	actor_id: String,
	response_kind: String,
) -> Dictionary:
	if not _running or _conflict_controller == null:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var before_revision := _conflict_runtime_revision()
	var result := _conflict_controller.respond(conflict_id,
		actor_id,
		response_kind,) as Dictionary
	return _complete_conflict_command(result, before_revision)


func leave_conflict(
	conflict_id: String,
	actor_id: String,
	reason: String,
) -> Dictionary:
	if not _running or _conflict_controller == null:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var before_revision := _conflict_runtime_revision()
	var result := _conflict_controller.leave_conflict(conflict_id,
		actor_id,
		reason,) as Dictionary
	return _complete_conflict_command(result, before_revision)


func set_player_avatar_present(
	present: bool,
	emit_events := true,
) -> Dictionary:
	if not _running:
		return _player_command_result("更新位置", false, "世界尚未运行")
	if _player_avatar_present == present:
		return _player_command_result("更新位置", true, "化身在场状态未变化", {
			"state": get_player_avatar_state(),
		})
	_player_avatar_present = present
	_bump_world_revision(false)
	PERCEPTION_RUNTIME._refresh_perception(self, emit_events)
	var state := get_player_avatar_state()
	player_avatar_state_changed.emit(state)
	_notify_world_revision()
	return _player_command_result("更新位置", true, "世界已确认化身在场状态", {
		"state": state,
	})


func submit_player_avatar_position(space_id: String, position: Vector2, doing := "") -> Dictionary:
	if not _running:
		return _player_command_result("更新位置", false, "世界尚未运行")
	if not is_finite(position.x) or not is_finite(position.y):
		return _player_command_result("更新位置", false, "化身位置必须是有限坐标")
	if not doing is String:
		return _player_command_result("更新位置", false, "化身动作描述必须是文本")
	var current_space_id := String(_player_avatar.get("spaceId", ""))
	if space_id != current_space_id:
		return _player_command_result("更新位置", false, "跨地图空间必须通过地点切换命令")
	var membership := PERCEPTION_RUNTIME._membership(self, space_id, position)
	if membership.is_empty():
		return _player_command_result("更新位置", false, "化身位置不是合法世界位置")
	return _apply_player_avatar_state(space_id, membership, position, String(doing), "更新位置")


func prepare_player_avatar_descent(space_id: String, position: Vector2) -> Dictionary:
	if not _running:
		return _player_command_result("更新位置", false, "世界尚未运行")
	if not is_finite(position.x) or not is_finite(position.y):
		return _player_command_result("更新位置", false, "化身降落点必须是有限坐标")
	var safe_position := CHARACTER_MOVEMENT_QUERY.nearest_safe_position(
		_world_data,
		space_id,
		position,
	) as Dictionary
	if safe_position.is_empty():
		return _player_command_result(
			"更新位置",
			false,
			"当前视野附近没有可供化身降落的安全区域",
		)
	var resolved_position := (
		safe_position.get("position", Vector2.ZERO) as Vector2
	)
	var membership := {
		"regionId": String(safe_position.get("regionId", "")),
		"placeName": String(safe_position.get("placeName", "")),
	}
	_player_avatar_present = true
	var result := _apply_player_avatar_state(
		space_id,
		membership,
		resolved_position,
		"降落在%s" % String(membership.get("placeName", "小镇里")),
		"更新位置",
	)
	result["landing"] = safe_position.duplicate(true)
	result["outdoorReturnPlace"] = _outdoor_connection_place_for(
		String(membership.get("placeName", "")),
	)
	return result


func change_player_avatar_place(target_place: String) -> Dictionary:
	if not _running:
		return _player_command_result("切换地点", false, "世界尚未运行")
	var normalized := target_place.strip_edges()
	if normalized.is_empty() or get_place_detail(normalized).is_empty():
		return _player_command_result("切换地点", false, "目标地点不存在")
	var current_place := String(_player_avatar.get("currentPlace", ""))
	if normalized == current_place:
		return _player_command_result("切换地点", false, "化身已经位于目标地点")
	var endpoint := _direct_connection_endpoint(current_place, normalized)
	if endpoint.is_empty():
		return _player_command_result("切换地点", false, "当前地点与目标地点没有直接入口连接")
	var point := endpoint.get("position", {}) as Dictionary
	var position := Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
	var membership := PERCEPTION_RUNTIME._membership(self, String(endpoint.get("spaceId", "")), position)
	if membership.is_empty() or String(membership.get("placeName", "")) != normalized:
		return _player_command_result("切换地点", false, "目标入口不是合法世界位置")
	return _apply_player_avatar_state(
		String(endpoint.get("spaceId", "")),
		membership,
		position,
		"进入%s" % normalized,
		"切换地点",
	)


func return_player_avatar_outdoors(
	connection_place: String,
	safe_return_position: Vector2,
) -> Dictionary:
	if not _running:
		return _player_command_result("离开室内", false, "世界尚未运行")
	if (
		not is_finite(safe_return_position.x)
		or not is_finite(safe_return_position.y)
	):
		return _player_command_result(
			"离开室内",
			false,
			"化身安全出门点必须是有限坐标",
		)
	var normalized := connection_place.strip_edges()
	if normalized.is_empty() or get_place_detail(normalized).is_empty():
		return _player_command_result("离开室内", false, "室外连接地点不存在")
	var current_place := String(_player_avatar.get("currentPlace", ""))
	var endpoint := _direct_connection_endpoint(current_place, normalized)
	if endpoint.is_empty():
		return _player_command_result(
			"离开室内",
			false,
			"当前室内与室外地点没有直接出口连接",
		)
	var target_space_id := String(endpoint.get("spaceId", ""))
	if target_space_id != "town_outdoor":
		return _player_command_result("离开室内", false, "目标连接不是室外出口")
	var membership := PERCEPTION_RUNTIME._membership(self, target_space_id, safe_return_position)
	if (
		membership.is_empty()
		or String(membership.get("placeName", "")) != normalized
	):
		return _player_command_result(
			"离开室内",
			false,
			"化身安全出门点不属于室外连接地点",
		)
	return _apply_player_avatar_state(
		target_space_id,
		membership,
		safe_return_position,
		"走出%s" % current_place,
		"离开室内",
	)


func player_start_conversation(target_name: String, say: String, narration: String, photos: Array = []) -> Dictionary:
	if not _running:
		return _player_command_result("发起对话", false, "世界尚未运行")
	var player_name := String(_player_avatar.get("name", ""))
	if not CONVERSATION_RUNTIME._active_conversation_for_person(self, _player_avatar_id()).is_empty():
		return _player_command_result("发起对话", false, "化身已经在参与一段对话")
	var normalized_target := _resident_key(target_name)
	if normalized_target.is_empty():
		return _player_command_result("发起对话", false, "对话目标不是已知居民")
	if not _resident_is_alive(normalized_target):
		return _player_command_result("发起对话", false, "死亡居民不能参与对话")
	var target := _residents[normalized_target] as Dictionary
	if not PERCEPTION_RUNTIME._are_nearby(self, _player_avatar, target):
		return _player_command_result("发起对话", false, "对话目标不在化身感知范围内")
	if not CONVERSATION_RUNTIME._active_conversation_for_person(self, normalized_target).is_empty():
		return _player_command_result("发起对话", false, "对话目标正在参与另一段对话")
	var action := {
		"target": _resident_display_name(normalized_target),
		"target_resident_id": normalized_target,
		"say": say,
		"narration": narration,
		"photos": photos.duplicate(true),
	}
	var turn_error := _validate_player_turn(action, false)
	if not turn_error.is_empty():
		return _player_command_result("发起对话", false, turn_error)
	_bump_world_revision(false)
	CONVERSATION_RUNTIME._start_conversation(self, _player_avatar_id(), action)
	_player_avatar["doing"] = ACTION_PRESENTATION._conversation_doing(self, action)
	player_avatar_state_changed.emit(get_player_avatar_state())
	_notify_world_revision()
	return _player_command_result("发起对话", true, "世界已确认玩家搭话", {"conversation": get_conversation(String(action.get("conversationId", "")))})


func player_reply_conversation(
	conversation_id: String,
	say: String,
	narration: String,
	photos: Array = [],
	end := false,
) -> Dictionary:
	if not _running:
		return _player_command_result("继续对话", false, "世界尚未运行")
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, _player_avatar_id())
	if conversation.is_empty() or String(conversation.get("conversationId", "")) != conversation_id:
		return _player_command_result("继续对话", false, "化身当前没有这段活动对话")
	if String(conversation.get("waitingFor", "")) != _player_avatar_id():
		return _player_command_result("继续对话", false, "当前对话还没有轮到化身回应")
	var action := {"conversation_id": conversation_id, "say": say, "narration": narration, "photos": photos.duplicate(true), "end": end}
	var turn_error := _validate_player_turn(action, true)
	if not turn_error.is_empty():
		return _player_command_result("继续对话", false, turn_error)
	_bump_world_revision(false)
	_player_avatar["doing"] = ACTION_PRESENTATION._conversation_doing(self, action)
	CONVERSATION_RUNTIME._apply_conversation_reply(self, _player_avatar_id(), action)
	player_avatar_state_changed.emit(get_player_avatar_state())
	_notify_world_revision()
	return _player_command_result("继续对话", true, "世界已确认玩家答话", {"conversation": get_conversation(conversation_id)})


func player_end_conversation(conversation_id: String, narration: String = "结束交谈") -> Dictionary:
	if not _running:
		return _player_command_result("结束对话", false, "世界尚未运行")
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, _player_avatar_id())
	if conversation.is_empty() or String(conversation.get("conversationId", "")) != conversation_id:
		return _player_command_result("结束对话", false, "化身当前没有这段活动对话")
	var normalized := narration.strip_edges()
	if normalized.is_empty():
		return _player_command_result("结束对话", false, "结束对话需要可观察的动作描述")
	var action := {"conversation_id": conversation_id, "say": "", "narration": normalized, "photos": [], "end": true}
	_bump_world_revision(false)
	_player_avatar["doing"] = normalized
	CONVERSATION_RUNTIME._apply_conversation_reply(self, _player_avatar_id(), action)
	player_avatar_state_changed.emit(get_player_avatar_state())
	_notify_world_revision()
	return _player_command_result("结束对话", true, "世界已确认玩家结束对话", {"conversation": get_conversation(conversation_id)})


func player_reject_conversation(conversation_id: String, narration: String = "没有接话") -> Dictionary:
	if not _running:
		return _player_command_result("拒绝对话", false, "世界尚未运行")
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, _player_avatar_id())
	if conversation.is_empty() or String(conversation.get("conversationId", "")) != conversation_id:
		return _player_command_result("拒绝对话", false, "化身当前没有这段活动对话")
	if not CONVERSATION_RUNTIME._is_initial_invitation_for(self, _player_avatar_id(), conversation):
		return _player_command_result("拒绝对话", false, "只有尚未回应的搭话邀请可以拒绝")
	var normalized := narration.strip_edges()
	if normalized.is_empty():
		return _player_command_result("拒绝对话", false, "拒绝对话需要可观察的动作描述")
	_bump_world_revision(false)
	_player_avatar["doing"] = normalized
	CONVERSATION_RUNTIME._end_conversation(self, conversation_id, "拒绝接话", "rejected")
	player_avatar_state_changed.emit(get_player_avatar_state())
	_notify_world_revision()
	return _player_command_result("拒绝对话", true, "世界已确认玩家拒绝接话", {"conversation": get_conversation(conversation_id)})


func get_place_exterior_anchor(place_name: String) -> Dictionary:
	for value: Variant in _world_data.get("connections", []) as Array:
		var connection := value as Dictionary
		var left := connection.get("from", {}) as Dictionary
		var right := connection.get("to", {}) as Dictionary
		if String(left.get("placeName", "")) == place_name and String(right.get("spaceId", "")) == "town_outdoor":
			return _connection_anchor(right)
		if String(right.get("placeName", "")) == place_name and String(left.get("spaceId", "")) == "town_outdoor":
			return _connection_anchor(left)
	return {}


func get_place_observation_hotspot(place_name: String) -> Dictionary:
	var connection_id := get_place_connection_id(place_name)
	if connection_id.is_empty():
		return {}
	var hotspots := (
		_world_data.get("placeObservationHotspots", {}) as Dictionary
	)
	var spec_value: Variant = hotspots.get(connection_id)
	if not spec_value is Dictionary:
		return {}
	var spec := spec_value as Dictionary
	var offset := spec.get("offset", {}) as Dictionary
	var size := spec.get("size", {}) as Dictionary
	var width := float(size.get("width", 0.0))
	var height := float(size.get("height", 0.0))
	if (
		not is_finite(width)
		or not is_finite(height)
		or width <= 0.0
		or height <= 0.0
	):
		return {}
	var anchor := get_place_exterior_anchor(place_name)
	if anchor.is_empty():
		return {}
	var anchor_position := anchor.get("position", Vector2.ZERO) as Vector2
	var offset_vector := Vector2(
		float(offset.get("x", 0.0)),
		float(offset.get("y", 0.0)),
	)
	if (
		not is_finite(offset_vector.x)
		or not is_finite(offset_vector.y)
	):
		return {}
	return {
		"placeName": place_name,
		"connectionId": connection_id,
		"center": anchor_position + offset_vector,
		"size": Vector2(width, height),
	}


func get_place_connection_id(place_name: String) -> String:
	var normalized := place_name.strip_edges()
	if normalized.is_empty():
		return ""
	for value: Variant in _world_data.get("connections", []) as Array:
		var connection := value as Dictionary
		var left := connection.get("from", {}) as Dictionary
		var right := connection.get("to", {}) as Dictionary
		if (
			String(left.get("spaceId", "")) == "town_outdoor"
			and String(right.get("placeName", "")) == normalized
		):
			return String(connection.get("id", ""))
		if (
			String(right.get("spaceId", "")) == "town_outdoor"
			and String(left.get("placeName", "")) == normalized
		):
			return String(connection.get("id", ""))
	return ""


func get_place_name_for_connection(connection_id: String) -> String:
	var normalized := connection_id.strip_edges()
	if normalized.is_empty():
		return ""
	for value: Variant in _world_data.get("connections", []) as Array:
		var connection := value as Dictionary
		if String(connection.get("id", "")) != normalized:
			continue
		var left := connection.get("from", {}) as Dictionary
		var right := connection.get("to", {}) as Dictionary
		if String(left.get("spaceId", "")) == "town_outdoor":
			return String(right.get("placeName", ""))
		if String(right.get("spaceId", "")) == "town_outdoor":
			return String(left.get("placeName", ""))
		return ""
	return ""

func get_announcements() -> Array[Dictionary]:
	return ANNOUNCEMENT_PUBLISHER_PROJECTION.project(self, _community_bulletin.get_announcements(true) as Array[Dictionary])

func get_public_event_log() -> Array[Dictionary]:
	var public_event_log: Array[Dictionary] = []
	for record: Dictionary in _public_event_log:
		var copy := record.duplicate(true)
		var payload := copy.get("payload", {}) as Dictionary
		if payload is Dictionary:
			copy["payload"] = _sanitize_public_event_payload(payload)
		public_event_log.append(copy)
	return public_event_log

func publish_announcement(text: String) -> Dictionary:
	return _publish_community_announcement(
		_player_avatar_id(),
		text,
		"",
		"board",
	)


func publish_resident_announcement(
	resident_ref: String,
	text: String,
	matter_id := "",
	delivery_mode := "",
) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var resolved_delivery_mode := delivery_mode.strip_edges()
	if resolved_delivery_mode.is_empty():
		resolved_delivery_mode = (
			_resident_announcement_delivery_mode(matter_id)
			if (
				not matter_id.strip_edges().is_empty()
				and _occupation_id_for_resident(
					_residents.get(resident_id, {}) as Dictionary,
				) == "occupation_town_manager"
			)
			else "board"
		)
	return _publish_community_announcement(
		resident_id,
		text,
		matter_id,
		resolved_delivery_mode,
	)


func read_announcement(
	resident_ref: String,
	announcement_id: String,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var result := _community_bulletin.read_announcement(
		resident_id,
		announcement_id,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return _social_command_result(result)
	var value := result.get("value", {}) as Dictionary
	var event := value.get("event", {}) as Dictionary
	if not event.is_empty():
		var publish_event_id := _announcement_publish_event_id(
			announcement_id,
		)
		if not publish_event_id.is_empty():
			event["causedByEventIds"] = [publish_event_id]
			event["storyRootEventIds"] = [publish_event_id]
		_bump_world_revision(false)
		_queue_world_event(resident_id, event)
	_complete_matching_direct_social_capability(
		resident_id,
		"bulletin.read",
		{"announcement_id": announcement_id},
		"bulletin-read:%s:%s" % [resident_id, announcement_id],
	)
	_notify_world_revision()
	return _decorate_command_result({
		"ok": true,
		"newKnowledge": bool(value.get("new_knowledge", false)),
		"announcement": (
			value.get("announcement", {}) as Dictionary
		).duplicate(true),
	})


func relay_announcement(
	speaker_ref: String,
	listener_ref: String,
	announcement_id: String,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var speaker_id := _resident_key(speaker_ref)
	var listener_id := _resident_key(listener_ref)
	if speaker_id.is_empty() or listener_id.is_empty():
		return _command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["公告转告者或接收者不是当前居民"],
		)
	var result := _community_bulletin.relay_announcement(
		speaker_id,
		listener_id,
		announcement_id,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return _social_command_result(result)
	var value := result.get("value", {}) as Dictionary
	if bool(value.get("new_knowledge", false)):
		var announcement := value.get(
			"announcement",
			{},
		) as Dictionary
		var publish_event_id := _announcement_publish_event_id(
			announcement_id,
		)
		var relay_event := {
			"type": "公告转告",
			"announcement_id": announcement_id,
			"speaker_resident_id": speaker_id,
			"text": String(announcement.get("text", "")),
			"matter_id": (
				String(announcement.get("matter_id", ""))
				if not String(
					announcement.get("matter_id", "")
				).is_empty()
				else null
			),
		}
		if not publish_event_id.is_empty():
			relay_event["causedByEventIds"] = [publish_event_id]
			relay_event["storyRootEventIds"] = [publish_event_id]
		_bump_world_revision(false)
		_queue_world_event(listener_id, relay_event)
		_notify_world_revision()
	return _decorate_command_result({
		"ok": true,
		"newKnowledge": bool(value.get("new_knowledge", false)),
		"announcement": (
			value.get("announcement", {}) as Dictionary
		).duplicate(true),
	})


func withdraw_announcement(announcement_id: String) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var result := _community_bulletin.withdraw_announcement(
		announcement_id,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return _social_command_result(result)
	var announcement := (
		result.get("value", {}) as Dictionary
	).duplicate(true)
	var publisher_id := String(
		announcement.get("publisher_id", ""),
	).strip_edges()
	_bump_world_revision(false)
	_notify_world_revision()
	return _decorate_command_result({
		"ok": true,
		"announcement": announcement,
	})


func announcement_unread_count(resident_ref: String) -> int:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return 0
	return int(_community_bulletin.unread_count(resident_id))


func announcement_knowledge_for(
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	return _community_bulletin.knowledge_for(
		resident_id,
	) as Array[Dictionary]


func _publish_community_announcement(
	publisher_id: String,
	text: String,
	matter_id: String,
	delivery_mode: String,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var social_snapshot := _social_matters.create_save_snapshot(
	) as Dictionary
	var bulletin_snapshot := _community_bulletin.create_save_snapshot(
	) as Dictionary
	var event_sequence_before := _event_sequence
	var announcement_event_id := _next_world_event_id()
	var announcement_schedule := ANNOUNCEMENT_TIME_PARSER.parse(
		text,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	var time_expression_detected := (
		ANNOUNCEMENT_TIME_PARSER.has_time_expression(text)
	)
	var result := _community_bulletin.publish(
		publisher_id,
		text,
		matter_id,
		int(_environment.get_absolute_minute()),
		get_time(),
		delivery_mode,
		announcement_event_id,
		announcement_schedule,
	) as Dictionary
	if result.get("ok") != true:
		_event_sequence = event_sequence_before
		if String(result.get("error_code", "")) == (
			"BULLETIN_ANNOUNCEMENT_INVALID"
		):
			return _command_failure(
				"ANNOUNCEMENT_INVALID",
				[String(result.get("reason", "公告内容无效"))],
			)
		return _social_command_result(result, "ANNOUNCEMENT_INVALID")
	var announcement := (
		(result.get("value", {}) as Dictionary).get(
			"announcement",
			{},
		) as Dictionary
	).duplicate(true)
	var broadcast_result := _record_announcement_broadcast_knowledge(
		announcement,
	) as Dictionary
	if broadcast_result.get("ok") != true:
		_event_sequence = event_sequence_before
		_social_matters.restore_save_snapshot(social_snapshot)
		_community_bulletin.restore_save_snapshot(
			bulletin_snapshot,
		)
		return _command_failure(
			"ANNOUNCEMENT_TRANSACTION_INVARIANT_BROKEN",
			[
				String(
					broadcast_result.get(
						"reason",
						"合法公告提交后未能完成全体交付",
					)
				)
			],
		)
	_announcements.append({
		"announcement_id": String(
			announcement.get("announcement_id", "")
		),
		"text": String(announcement.get("text", "")),
		"time": (
			announcement.get("time", get_time()) as Dictionary
		).duplicate(true),
	})
	_announcement_sequence = maxi(
		_announcement_sequence,
		SAVE_CODEC.sequence_from_prefixed_id(
			String(announcement.get("announcement_id", "")),
			"announcement-",
		),
	)
	_trim_announcement_history()
	var announcement_event := _materialize_world_event({
		"type": "公告发布",
		"announcement_priority": ANNOUNCEMENT_RESIDENT_RUNTIME.priority_for_publisher(self, publisher_id),
		"announcement_id": String(
			announcement.get("announcement_id", "")
		),
		"publisher_resident_id": String(
			announcement.get("publisher_id", publisher_id)
		),
		"publisher_name": ANNOUNCEMENT_RESIDENT_RUNTIME.publisher_name(
			self,
			String(announcement.get("publisher_id", publisher_id)),
		),
		"text": String(announcement.get("text", "")),
		"matter_id": (
			String(announcement.get("matter_id", ""))
			if not String(
				announcement.get("matter_id", "")
			).is_empty()
			else null
		),
		"time": (
			announcement.get("time", get_time()) as Dictionary
		).duplicate(true),
		"scheduled_absolute_minute": int(
			announcement.get("scheduled_absolute_minute", -1),
		),
		"scheduled_time_label": String(
			announcement.get("scheduled_time_label", ""),
		),
	}, announcement_event_id)
	for resident_value: Variant in broadcast_result.get(
		"reaction_resident_ids",
		[],
	) as Array:
		_enqueue_world_event(
			String(resident_value),
			announcement_event,
		)
	var broadcast_event_id := ""
	if String(announcement.get("delivery_mode", "board")) == "town_bell":
		broadcast_event_id = _deliver_town_bell_announcement(
			announcement,
			String(announcement_event.get("event_id", "")),
		)
	elif String(announcement.get("delivery_mode", "board")) == (
		"postal_notice"
	):
		_queue_announcement_postal_notices(announcement)
	_bump_world_revision(false)
	if _residents.has(publisher_id):
		_complete_matching_direct_social_capability(
			publisher_id,
			"bulletin.publish",
			{
				"text": String(announcement.get("text", "")),
				"matter_id": String(announcement.get("matter_id", "")),
			},
			"bulletin-publish:%s"
			% String(announcement.get("announcement_id", "")),
		)
	announcement_published.emit(announcement.duplicate(true))
	_notify_world_revision()
	return _decorate_command_result({
		"ok": true,
		"announcement": announcement,
		"eventId": String(announcement_event.get("event_id", "")),
		"broadcastEventId": broadcast_event_id,
		"scheduleRecognized": not announcement_schedule.is_empty(),
		"scheduleWarning": (
			time_expression_detected and announcement_schedule.is_empty()
		),
	})


func _announcement_publish_event_id(announcement_id: String) -> String:
	var normalized_id := announcement_id.strip_edges()
	if normalized_id.is_empty():
		return ""
	var announcement := _community_bulletin.get_announcement(
		normalized_id,
	) as Dictionary
	var stored_event_id := String(
		announcement.get("publish_event_id", ""),
	).strip_edges()
	if not stored_event_id.is_empty():
		return stored_event_id
	for reverse_index in _public_event_log.size():
		var record := _public_event_log[
			_public_event_log.size() - reverse_index - 1
		] as Dictionary
		if String(record.get("kind", "")) != "world_event":
			continue
		var payload := record.get("payload", {}) as Dictionary
		if (
			String(payload.get("type", "")) == "公告发布"
			and String(payload.get("announcement_id", "")) == normalized_id
		):
			return String(record.get("eventId", ""))
	return ""


func sync_place_service_pressure(place_state: Dictionary) -> Dictionary:
	return _sync_social_source(
		"sync_place_service_pressure",
		place_state,
	)


func sync_resident_request(request_state: Dictionary) -> Dictionary:
	return _sync_social_source(
		"sync_resident_request",
		request_state,
	)


func sync_conversation_commitment(commitment_state: Dictionary) -> Dictionary:
	return _sync_social_source(
		"sync_conversation_commitment",
		commitment_state,
	)


func sync_animal_attention(animal_state: Dictionary) -> Dictionary:
	return _sync_social_source(
		"sync_animal_attention",
		animal_state,
	)


func sync_job_vacancy(vacancy_state: Dictionary) -> Dictionary:
	return _sync_social_source(
		"sync_job_vacancy",
		vacancy_state,
	)


func record_social_awareness(
	matter_id: String,
	resident_ref: String,
	acquired_via: String,
	source_id: String,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var result := _social_matters.record_awareness(
		matter_id,
		resident_id,
		"known",
		acquired_via,
		source_id,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	return _finalize_social_mutation(result, matter_id)


func begin_social_response_round(
	matter_id: String,
	candidates: Array,
	response_window_minutes: int,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if response_window_minutes <= 0:
		return _command_failure(
			"SOCIAL_RESPONSE_ROUND_INVALID",
			["回应窗口必须大于零分钟"],
		)
	if candidates.size() > MAX_SOCIAL_RESPONSE_CANDIDATES:
		return _command_failure(
			"SOCIAL_RESPONSE_CANDIDATE_LIMIT",
			[
				"一轮最多选择 %d 名回应候选"
				% MAX_SOCIAL_RESPONSE_CANDIDATES
			],
		)
	var now := int(_environment.get_absolute_minute())
	var normalized_candidates: Array[Dictionary] = []
	for value: Variant in candidates:
		if typeof(value) != TYPE_DICTIONARY:
			return _command_failure(
				"SOCIAL_RESPONSE_CANDIDATE_INVALID",
				["回应候选必须是对象"],
			)
		var candidate := (value as Dictionary).duplicate(true)
		var resident_id := _resident_key(
			String(candidate.get("resident_id", ""))
		)
		if resident_id.is_empty():
			return _command_failure(
				"WORLD_RESIDENT_UNKNOWN",
				["回应候选不是当前居民"],
			)
		var active_load := _active_social_commitment_count(resident_id)
		if active_load >= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT:
			return _command_failure(
				"SOCIAL_COMMITMENT_LIMIT",
				["居民已有正在履行的社会承诺"],
			)
		candidate["resident_id"] = resident_id
		candidate["load"] = active_load
		candidate["available_at"] = _resident_social_available_at(
			resident_id,
			now,
		)
		normalized_candidates.append(candidate)
	var result := _social_matters.begin_response_round(
		matter_id,
		normalized_candidates,
		now,
		now + response_window_minutes,
	) as Dictionary
	if result.get("ok") == true:
		for candidate: Dictionary in normalized_candidates:
			_schedule_decision(
				String(candidate.get("resident_id", "")),
				true,
			)
	return _finalize_social_mutation(result, matter_id)


func begin_social_response_round_for_residents(
	matter_id: String,
	resident_refs: Array,
	response_window_minutes: int,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if resident_refs.is_empty():
		return _command_failure(
			"SOCIAL_RESPONSE_CANDIDATE_INVALID",
			["回应候选不能为空"],
		)
	var now := int(_environment.get_absolute_minute())
	var candidates: Array[Dictionary] = []
	var seen := {}
	for resident_value: Variant in resident_refs:
		var resident_id := _resident_key(String(resident_value))
		if resident_id.is_empty():
			return _command_failure(
				"WORLD_RESIDENT_UNKNOWN",
				["回应候选不是当前居民"],
			)
		if seen.has(resident_id):
			continue
		seen[resident_id] = true
		var load := _active_social_commitment_count(resident_id)
		if load >= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT:
			continue
		var candidate := _social_sources.response_candidate(
			resident_id,
			0,
			load,
			_resident_social_available_at(resident_id, now),
			matter_id,
		) as Dictionary
		if not candidate.is_empty():
			candidates.append(candidate)
		if candidates.size() >= MAX_SOCIAL_RESPONSE_CANDIDATES:
			break
	if candidates.is_empty():
		return _command_failure(
			"SOCIAL_RESPONSE_CANDIDATE_UNAVAILABLE",
			["当前没有能够进入本轮的知情居民"],
		)
	return begin_social_response_round(
		matter_id,
		candidates,
		response_window_minutes,
	)


func submit_social_response(
	resident_ref: String,
	response: Dictionary,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var result := _social_agent_adapter.submit_social_response(
		resident_id,
		response,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") == true:
		_settle_social_round_if_ready(
			String(response.get("matter_id", "")),
		)
	return _finalize_social_mutation(
		result,
		String(response.get("matter_id", "")),
	)


func mark_social_candidate_terminal(
	matter_id: String,
	resident_ref: String,
	reason: String,
	expected_response_round_id: String = "",
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return _command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var result := _social_matters.mark_candidate_terminal(
		matter_id,
		resident_id,
		reason,
		expected_response_round_id,
	) as Dictionary
	if result.get("ok") == true:
		_settle_social_round_if_ready(matter_id)
	return _finalize_social_mutation(result, matter_id)


func get_social_matter_summaries(
	include_closed := false,
) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for value: Variant in _social_matters.list_matters(
		include_closed,
	) as Array:
		var matter := value as Dictionary
		summaries.append(
			_social_matters.public_summary(
				String(matter.get("matter_id", "")),
			) as Dictionary
		)
	return summaries


func get_public_social_matter_activity() -> Dictionary:
	if not _running:
		return {
			"revision": maxi(_world_revision, 0),
			"items": [],
			"history": [],
		}
	if _public_social_matter_activity_cache_revision == _world_revision:
		return _public_social_matter_activity_cache.duplicate(true)
	var active_activities := {}
	var bulletin_matter_ids := {}
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		active_activities[resident_id] = {
			"actionId": String(action.get("action_id", "")),
			"actionType": String(action.get("type", "")),
			"activityId": "",
			"phase": "",
		}
		var execution := _activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if execution.is_empty():
			continue
		var cue_value: Variant = ACTION_PRESENTATION._resident_activity_cue(self, resident)
		var cue := (
			cue_value as Dictionary
			if cue_value is Dictionary
			else {}
		)
		active_activities[resident_id] = {
			"actionId": String(action.get("action_id", "")),
			"actionType": String(action.get("type", "")),
			"activityId": String(execution.get("activityId", "")),
			"phase": String(cue.get("phase", "")),
		}
		if String(execution.get("activityId", "")) != (
			SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID
		):
			continue
		var announcement_id := _first_unread_announcement_id(
			resident_id
		)
		var matter_id := _community_announcement_matter_id(
			announcement_id
		)
		if not matter_id.is_empty():
			bulletin_matter_ids[resident_id] = matter_id
	_public_social_matter_activity_cache = (
		SOCIAL_MATTER_PUBLIC_PROJECTION.build(
			_social_matters.list_matters(true) as Array,
			_resident_name_by_id,
			active_activities,
			bulletin_matter_ids,
			_world_revision,
			int(_environment.get_absolute_minute()),
		)
	)
	_public_social_matter_activity_cache_revision = _world_revision
	return _public_social_matter_activity_cache.duplicate(true)


func get_agent_social_matters(
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	return _social_agent_adapter.build_social_matters(
		resident_id,
	) as Array[Dictionary]


func get_agent_social_exposures(
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	var exposures := _social_matters.exposures_for(
		resident_id,
		int(_environment.get_absolute_minute()),
	) as Array[Dictionary]
	return exposures.slice(0, mini(1, exposures.size()))


func take_social_response_results(
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	return _social_agent_adapter.take_social_response_results(
		resident_id,
	) as Array[Dictionary]


func get_agent_initialization(resident_ref: String) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty() or not _resident_is_alive(resident_id):
		return {}
	return _build_agent_initialization(resident_id)


func _build_agent_initialization(resident_id: String) -> Dictionary:
	var runtime := _residents[resident_id] as Dictionary
	var attributes := (runtime.get("attributes", {}) as Dictionary).duplicate(true)
	attributes.erase("appearance")
	var soul_profiles := _opening.get("agentSoulProfiles", {}) as Dictionary
	var soul_profile := (
		(soul_profiles.get(resident_id, {}) as Dictionary).duplicate(true)
		if soul_profiles.get(resident_id, {}) is Dictionary
		else {}
	)
	var me := {
		"resident_id": resident_id,
		"attributes": attributes,
		"social_state": (runtime.get("socialState", {}) as Dictionary).duplicate(true),
	}
	if not soul_profile.is_empty():
		me["soul_profile"] = soul_profile
	var others: Array[Dictionary] = []
	for other_id in _resident_order:
		if other_id == resident_id:
			continue
		var other := _residents[other_id] as Dictionary
		var other_attributes := other.get("attributes", {}) as Dictionary
		var other_social := other.get("socialState", {}) as Dictionary
		others.append({
			"resident_id": other_id,
			"name": String(other_attributes.get("name", "")),
			"gender": String(other_attributes.get("gender", "")),
			"age": int(other_attributes.get("age", 0)),
			"job": String(other_social.get("job", "")),
			"home": String(other_social.get("home", "")),
			"workplace": String(other_social.get("workplace", "")),
			"lifecycle_status": String(
				(_resident_lifecycle.get_resident_state(other_id,) as Dictionary).get("status", "alive"),
			),
		})
	return {
		"me": me,
		"residents": others,
		"places": _agent_places(),
	}


func get_agent_initialization_by_id(resident_id: String) -> Dictionary:
	return get_agent_initialization(resident_id)


func take_pending_decision_requests(
	resident_filter: Array = [],
	materialize_snapshots: bool = true,
) -> Array[Dictionary]:
	if not _running or is_paused():
		return []
	if not _frame_probe_checked:
		_frame_probe_checked = true
		if OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1":
			_frame_probe = load("res://world/presentation/ui/TownUiFrameProbe.gd")
	var allowed := {}
	for value: Variant in resident_filter:
		var resident_id := _resident_key(String(value))
		if not resident_id.is_empty():
			allowed[resident_id] = true
	var result: Array[Dictionary] = []
	var pending_count := 0
	for resident_id in _resident_order:
		if not allowed.is_empty() and not allowed.has(resident_id):
			continue
		var resident := _residents[resident_id] as Dictionary
		if (
			not _resident_is_present(resident)
			or not bool(resident.get("wakeDispatchQueued", false))
		):
			continue
		pending_count += 1
		var lap_usec := Time.get_ticks_usec() if _frame_probe != null else 0
		if materialize_snapshots and AGENT_WAKE_STATE_RUNTIME.needs_refresh(resident, 0, ""):
			_refresh_pending_wake_snapshot(resident_id, resident)
			AGENT_WAKE_STATE_RUNTIME.mark_built(
				resident,
				int(_environment.get_absolute_minute()),
				get_weather(),
			)
			lap_usec = _take_probe_lap("agentTakeRefreshUsec", lap_usec)
		# Gateway 使用轻量模式先按并发容量选中请求，随后通过
		# refresh_pending_decision_request_by_id 在真正派发前冻结完整快照。
		# 默认值仍保留 World 公开 API 直接取得完整唤醒包的既有合同。
		resident["wakeDispatchQueued"] = false
		result.append({
			"residentId": resident_id,
			"residentName": String(_resident_name_by_id.get(resident_id, "")),
			"wakePacket": (resident.get("pendingWake", {}) as Dictionary).duplicate(true),
		})
		if _frame_probe != null:
			_take_probe_lap("agentTakePacketCopyUsec", lap_usec)
			_frame_probe.record(Engine.get_process_frames(), "agentTakeResidentCount", 1)
	if pending_count > int(_agent_request_metrics.get("pendingQueuePeak", 0)):
		_agent_request_metrics["pendingQueuePeak"] = pending_count
	return result


# C4:take 分段计时挂到 A1 帧探针,与 gateway 外层 agentTakeUsec 同帧对齐
# (差值=过滤规范化与在场检查等未分段部分)。
func _take_probe_lap(key: String, lap_started_usec: int) -> int:
	if _frame_probe == null:
		return lap_started_usec
	var now_usec := Time.get_ticks_usec()
	_frame_probe.record(Engine.get_process_frames(), key, now_usec - lap_started_usec)
	return now_usec
func _refresh_pending_wake_snapshot(
	resident_id: String,
	resident: Dictionary,
	frame_budgeted := false,
) -> void:
	var pending := resident.get("pendingWake", {}) as Dictionary
	if pending.is_empty():
		return
	_count_agent_request_metric("wakeRefresh")
	var preserved_social_results: Variant = (
		AGENT_WAKE_STATE_RUNTIME.preserved_social_results(pending)
	)
# Rebuild perception at dispatch time while preserving queued events/results.
	resident["pendingWake"] = _wake_packet(
		resident_id,
		resident,
		String(resident.get("validDecisionId", "")),
		(pending.get("events", []) as Array).duplicate(true),
		(pending.get("action_results", []) as Array).duplicate(true),
		preserved_social_results,
		bool(resident.get("decisionPrefetch", false))
		and _go_action_can_prefetch_decision(
			resident.get("currentAction", {}) as Dictionary,
		),
		frame_budgeted,
	)


func take_pending_decision_requests_by_ids(resident_ids: Array, materialize_snapshots: bool = true) -> Array[Dictionary]:
	if resident_ids.is_empty():
		return []
	var normalized_ids := AGENT_WAKE_STATE_RUNTIME.normalized_resident_ids(
		resident_ids,
		_residents,
		_resident_id_by_name,
	)
	return (
		[]
		if normalized_ids.is_empty()
		else take_pending_decision_requests(
			normalized_ids,
			materialize_snapshots,
		)
	)


func take_pending_decision_envelopes_by_ids(resident_ids: Array) -> Array[Dictionary]:
	return take_pending_decision_requests_by_ids(resident_ids, false)


func refresh_pending_decision_request_by_id(
	resident_ref: String,
	decision_id: String,
) -> Dictionary:
	var resident_id := _resident_key(resident_ref)
	if (
		resident_id.is_empty()
		or not _running
		or not _residents.has(resident_id)
	):
		return {"ok": false, "stale": true}
	var resident := _residents[resident_id] as Dictionary
	if (
		not _resident_is_present(resident)
		or not bool(resident.get("decisionPending", false))
		or String(resident.get("validDecisionId", "")) != decision_id
	):
		return {"ok": false, "stale": true}
	var current_minute := int(_environment.get_absolute_minute())
	var current_weather := get_weather()
	var refresh_started_usec := Time.get_ticks_usec() if _frame_probe != null else 0
	if AGENT_WAKE_STATE_RUNTIME.needs_refresh(resident, 0, ""):
		_refresh_pending_wake_snapshot(resident_id, resident, true)
		AGENT_WAKE_STATE_RUNTIME.mark_built(resident, current_minute, current_weather)
		_take_probe_lap("agentDispatchRefreshUsec", refresh_started_usec)
	return {
		"ok": true,
		"stale": false,
		"residentId": resident_id,
		"decisionId": decision_id,
		"wakePacket": (resident.get("pendingWake", {}) as Dictionary).duplicate(true),
	}


func advance_pending_decision_preparation_by_id(resident_ref: String, decision_id: String) -> Dictionary:
	return _agent_wake_preparation_runtime.advance(self, resident_ref, decision_id)
func redispatch_decision_request_by_id(resident_id: String, decision_id: String) -> bool:
	return redispatch_decision_request(resident_id, decision_id)
func redispatch_decision_request(resident_ref: String, decision_id: String) -> bool:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return false
	var resident := _residents[resident_id] as Dictionary
	if not bool(resident.get("decisionPending", false)) or String(resident.get("validDecisionId", "")) != decision_id:
		return false
	AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	resident["wakeDispatchQueued"] = true
	return true
func submit_agent_decision_by_id(resident_id: String, decision: Dictionary) -> Dictionary:
	var normalized := resident_id.strip_edges()
	if not _running:
		return {
			"ok": false,
			"stale": true,
			"errorCode": "WORLD_NOT_RUNNING",
			"retryable": false,
			"errors": ["世界尚未运行"],
			"residentId": normalized,
			"residentName": "",
			"worldRevision": _world_revision,
		}
	var resident_name := String(_resident_name_by_id.get(normalized, ""))
	if resident_name.is_empty() or not _residents.has(normalized):
		return {
			"ok": false,
			"stale": false,
			"errorCode": "WORLD_RESIDENT_ID_UNKNOWN",
			"retryable": false,
			"errors": ["未知居民 ID：%s" % normalized],
			"residentId": normalized,
			"residentName": "",
			"worldRevision": _world_revision,
		}
	if not _resident_is_alive(normalized):
		return {
			"ok": false,
			"stale": true,
			"errorCode": "RESIDENT_DEAD",
			"retryable": false,
			"errors": ["该居民已经死亡，不能再提交决定"],
			"residentId": normalized,
			"residentName": resident_name,
			"worldRevision": _world_revision,
		}
	var result := submit_agent_decision(normalized, decision)
	result["residentId"] = normalized
	result["residentName"] = resident_name
	result["errorCode"] = String(result.get("errorCode", ""))
	result["retryable"] = bool(result.get("retryable", false))
	result["worldRevision"] = _world_revision
	return result


func submit_agent_decision(resident_name: String, decision: Dictionary) -> Dictionary:
	if not _running:
		return {"ok": false, "stale": true, "errors": ["世界尚未运行"]}
	var resident_id := _resident_key(resident_name)
	if resident_id.is_empty():
		return {"ok": false, "stale": false, "errors": ["未知居民：%s" % resident_name]}
	resident_name = resident_id
	if not _resident_is_alive(resident_id):
		return {
			"ok": false,
			"stale": true,
			"errorCode": "RESIDENT_DEAD",
			"retryable": false,
			"errors": ["该居民已经死亡，不能再提交决定"],
		}
	var resident := _residents[resident_id] as Dictionary
	var decision_id := String(decision.get("decision_id", "")) if decision.get("decision_id") is String else ""
	var probe_lap_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	if is_paused():
		if (
			bool(resident.get("decisionPending", false))
			and decision_id == String(resident.get("validDecisionId", ""))
		):
			resident["wakeDispatchQueued"] = true
		return {
			"ok": false,
			"stale": false,
			"errorCode": "WORLD_PAUSED",
			"retryable": true,
			"errors": ["世界暂停期间不接收新的居民决定"],
		}
	if not bool(resident.get("decisionPending", false)) or decision_id != String(resident.get("validDecisionId", "")):
		return {"ok": false, "stale": true, "errors": ["决定已经失效：%s" % decision_id]}
	var decision_story_provenance := _decision_story_provenance(
		resident.get("inflightEvents", []) as Array,
		resident.get("inflightResults", []) as Array,
	)
	var inflight_events := (
		resident.get("inflightEvents", []) as Array
	).duplicate(true)
	var inflight_results := (
		resident.get("inflightResults", []) as Array
	).duplicate(true)
	var decision_wake := (
		resident.get("pendingWake", {}) as Dictionary
	).duplicate(true)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "submission_capture_wake")
	var decision_was_prefetched := bool(resident.get("decisionPrefetch", false))
	var decision_can_interrupt_current := bool(
		resident.get("decisionMayInterruptCurrent", false)
	)
	var pending_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
		self,
		resident_name,
	)
	var invitation_requires_reply := CONVERSATION_RUNTIME._is_initial_invitation_for(
		self,
		resident_name,
		pending_conversation,
	)
	if invitation_requires_reply:
		var submitted_action: Variant = decision.get("action")
		if (
			String(decision.get("handling", "")) != "replace_current"
			or not submitted_action is Dictionary
			or String((submitted_action as Dictionary).get("type", "")) != "答话"
		):
			return {
				"ok": false,
				"stale": false,
				"consumed": false,
				"errorCode": "CONVERSATION_REPLY_REQUIRED",
				"retryable": true,
				"errors": ["搭话必须提交答话；拒绝也要明确说明理由并结束对话"],
			}
		var invitation_reply := submitted_action as Dictionary
		if (
			bool(invitation_reply.get("end", false))
			and String(invitation_reply.get("say", "")).strip_edges().is_empty()
		):
			return {
				"ok": false,
				"stale": false,
				"consumed": false,
				"errorCode": "CONVERSATION_REFUSAL_REASON_REQUIRED",
				"retryable": true,
				"errors": ["拒绝搭话时答话必须说出明确理由"],
			}
	var pending_post_injury_reaction := _post_injury_reaction_for_events(
		resident_id,
		inflight_events,
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "submission_prechecks")
	var announcement_priority_error := ANNOUNCEMENT_RESIDENT_RUNTIME.player_priority_handling_error(decision, inflight_events)
	if not announcement_priority_error.is_empty(): return announcement_priority_error
	if not invitation_requires_reply and not pending_post_injury_reaction.is_empty():
		var post_injury_error := _post_injury_reaction_action_error(
			resident,
			decision,
			pending_post_injury_reaction,
		)
		if not post_injury_error.is_empty():
			return {
				"ok": false,
				"stale": false,
				"consumed": false,
				"errorCode": "POST_INJURY_REACTION_REQUIRED",
				"retryable": true,
				"errors": [post_injury_error],
			}
	_consume_valid_request(resident)
	_bump_world_revision(false)
	var decision_shape_error := _validate_decision_shape(
		decision,
		inflight_events,
		inflight_results,
	)
	if not decision_shape_error.is_empty():
		var malformed_action: Variant = decision.get("action")
		if malformed_action is Dictionary:
			return _complete_agent_submission(
				_reject_invalid_action(
					resident_name,
					resident,
					malformed_action as Dictionary,
					decision_shape_error,
				)
			)
		else:
			_schedule_decision(resident_name, false)
			return _complete_agent_submission({"ok": false, "stale": false, "errors": [decision_shape_error]})
	var accepted_conversation_follow_up := _accepted_conversation_follow_up(
		decision,
		decision_wake,
	)
	_settle_optional_social_attention(
		resident_id,
		(
			decision.get("social_attention", {}) as Dictionary
			if decision.get("social_attention") is Dictionary
			else {}
		),
		(
			(
				decision_wake.get("snapshot", {}) as Dictionary
			).get("social_exposures", []) as Array
		),
	)
	if decision.has("social_response"):
		_submit_optional_social_response(
			resident_id,
			decision.get("social_response"),
		)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "submission_validate_and_social")
	var handling := decision.get("handling") as String
	var active_conversation := pending_conversation
	var is_initial_invitation := invitation_requires_reply
	if handling == "continue_current":
		if (resident.get("currentAction", {}) as Dictionary).is_empty():
			_schedule_decision(resident_name, false)
			return _complete_agent_submission({"ok": false, "stale": false, "errors": ["没有可以继续的当前动作"]})
		if not active_conversation.is_empty() and String(active_conversation.get("waitingFor", "")) == resident_name:
			_schedule_decision(resident_name, false)
			return _complete_agent_submission({
				"ok": false,
				"stale": false,
				"errorCode": "CONVERSATION_REPLY_REQUIRED",
				"retryable": true,
				"errors": ["搭话必须提交答话；拒绝也要说明理由并结束对话"],
			})
		_emit_resident_reaction(
			resident_name,
			decision_id,
			decision.get("reaction", {}) as Dictionary,
			(
				decision.get("announcement_reactions", []) as Array
				if decision.get("announcement_reactions", []) is Array
				else []
			),
			inflight_events,
			inflight_results,
		)
		return _complete_agent_submission(
			_confirm_action_preview(
				resident_name,
				resident,
				decision_id,
				"continue_current",
				resident.get("currentAction", {}) as Dictionary,
			)
		)
	if handling != "replace_current" or typeof(decision.get("action")) != TYPE_DICTIONARY:
		_schedule_decision(resident_name, false)
		return _complete_agent_submission({"ok": false, "stale": false, "errors": ["决定必须继续当前动作或提交新动作"]})
	var action := (decision.get("action", {}) as Dictionary).duplicate(true)
	var current_action := resident.get("currentAction", {}) as Dictionary
	if decision_was_prefetched and not current_action.is_empty():
		# Hold the prefetched answer until the current action completes.
		resident["decisionPending"] = true
		resident["validDecisionId"] = decision_id
		resident["pendingWake"] = decision_wake
		resident["inflightEvents"] = inflight_events
		resident["inflightResults"] = inflight_results
		resident["wakeDispatchQueued"] = false
		resident["prefetchedDecision"] = decision.duplicate(true)
		resident["decisionPrefetch"] = false
		return _complete_agent_submission({
			"ok": true,
			"status": "prefetched",
			"residentId": resident_id,
			"decisionId": decision_id,
		})
	var action_type := String(action.get("type", ""))
	var conflict_intent := (
		decision.get("conflict_intent", {}) as Dictionary
		if decision.get("conflict_intent") is Dictionary
		else {}
	)
	var busy_activity_reconsideration := bool(
		resident.get("busyActivityReconsideration", false)
	)
	if (
		not active_conversation.is_empty()
		and String(active_conversation.get("waitingFor", "")) == resident_name
		and action_type != "答话"
	):
		var reply_error := (
			"搭话必须提交答话；拒绝也要说明理由并结束对话"
			if is_initial_invitation
			else "当前对话正在等待本居民提交答话动作"
		)
		return _complete_agent_submission(
			_reject_invalid_action(resident_name, resident, action, reply_error)
		)
	if busy_activity_reconsideration:
		resident["busyActivityReconsideration"] = false
	_emit_resident_reaction(
		resident_name,
		decision_id,
		decision.get("reaction", {}) as Dictionary,
		(
			decision.get("announcement_reactions", []) as Array
			if decision.get("announcement_reactions", []) is Array
			else []
		),
		inflight_events,
		inflight_results,
	)
	if not conflict_intent.is_empty():
		var reply_preparation := _prepare_action(
			resident,
			action,
			false,
			decision_wake.get("snapshot", {}) as Dictionary,
		)
		if reply_preparation.get("ok") != true:
			return _complete_agent_submission(
				_reject_invalid_action(
					resident_name,
					resident,
					action,
					String((reply_preparation.get("errors", ["对话已经无法继续"]) as Array)[0]),
				)
			)
		var prepared_reply := reply_preparation.get("action", {}) as Dictionary
		(resident.get("usedActionIds", {}) as Dictionary)[String(action.get("action_id", "")).strip_edges()] = true
		(resident.get("usedActionIds", {}) as Dictionary)[String(conflict_intent.get("action_id", "")).strip_edges()] = true
		return _complete_agent_submission(
			_confirm_action_preview(
				resident_name,
				resident,
				decision_id,
				"replace_current",
				prepared_reply,
				"",
				decision_story_provenance,
				{},
				accepted_conversation_follow_up,
				pending_post_injury_reaction,
				decision_can_interrupt_current,
				conflict_intent,
				decision_wake.get("snapshot", {}) as Dictionary,
			)
		)
	var conversation_end_reason := ""
	if not active_conversation.is_empty() and action_type != "答话":
		conversation_end_reason = "拒绝接话" if is_initial_invitation else "无法继续"
	if action_type == "用道具":
		return _complete_agent_submission(
			_submit_legacy_prop_activity(
				resident_name,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				decision_can_interrupt_current,
				)
		)
	if action_type == "做活动":
		return _complete_agent_submission(
			_submit_agent_activity(
				resident_name,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				decision_can_interrupt_current,
				)
		)
	var preparation := _prepare_action(
		resident,
		action,
		false,
		decision_wake.get("snapshot", {}) as Dictionary,
		not pending_post_injury_reaction.is_empty()
			and action_type == "去"
			and String(action.get("place", "")) == CONTENT_CATALOG.PLACE_CLINIC,
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "submission_prepare_action")
	if preparation.get("ok") != true:
		var preparation_errors := preparation.get("errors", []) as Array
		var preparation_error := String(
			preparation_errors[0] if not preparation_errors.is_empty() else ""
		)
		if not pending_post_injury_reaction.is_empty():
			# A route or target can change between the urgent wake and submission.
			# Keep the injury event authoritative so a transient clinic/range
			# failure cannot release the resident back into ordinary activity.
			resident["inflightEvents"] = inflight_events
			resident["inflightResults"] = inflight_results
			_restore_inflight_facts(resident)
			_schedule_decision(resident_name, false)
			return _complete_agent_submission({
				"ok": true,
				"stale": true,
				"ignored": true,
				"reason": preparation_error if not preparation_error.is_empty() else "受击后的首轮动作条件已变化，已重新观察",
			})
		if (
			action_type == "搭话"
			and preparation_error in [
				"搭话对象已经不在感知范围内",
				"搭话对象正在参与其他对话",
			]
		):
			resident["inflightEvents"] = inflight_events
			resident["inflightResults"] = inflight_results
			_restore_inflight_facts(resident)
			_schedule_decision(resident_name, false)
			return _complete_agent_submission({
				"ok": true,
				"stale": true,
				"ignored": true,
				"reason": "%s，已重新观察" % preparation_error,
			})
		var rejection := _reject_invalid_action(
			resident_name,
			resident,
			action,
			String((preparation.get("errors", ["动作不合法"]) as Array)[0]),
		)
		DINING_SERVICE.decorate_go_rejection(rejection, preparation)
		if conversation_end_reason == "拒绝接话":
			CONVERSATION_RUNTIME._end_conversation(self, String(active_conversation.get("conversationId", "")), conversation_end_reason, "rejected")
		return _complete_agent_submission(rejection)
	var prepared_action := (
		preparation.get("action", {}) as Dictionary
	).duplicate(true)
	var prepared_current_action := resident.get("currentAction", {}) as Dictionary
	if (
		bool(prepared_current_action.get("followUpPausedForReconsideration", false))
		and action_type == "待着"
	):
		var resume_action := prepared_current_action.duplicate(true)
		resume_action.erase("followUpPausedForReconsideration")
		resume_action.erase("followUpReconsiderationReason")
		resume_action.erase("followUpReconsiderationSinceMinute")
		prepared_action["conversationFollowUpMode"] = "reconsideration_wait"
		prepared_action["followUpPhase"] = "waiting_to_retry"
		prepared_action["followUpResumeAction"] = resume_action
	if (
		busy_activity_reconsideration
		and action_type == "待着"
	):
		prepared_action["completeAbsoluteMinute"] = mini(
			int(prepared_action.get(
				"completeAbsoluteMinute",
				int(_environment.get_absolute_minute())
				+ CONTINUITY_WAIT_MAX_MINUTES,
			)),
			int(_environment.get_absolute_minute())
			+ CONTINUITY_WAIT_MAX_MINUTES,
		)
	(resident.get("usedActionIds", {}) as Dictionary)[String(action.get("action_id", "")).strip_edges()] = true
	return _complete_agent_submission(
		_confirm_action_preview(
			resident_name,
			resident,
			decision_id,
			"replace_current",
			prepared_action,
			conversation_end_reason,
			decision_story_provenance,
			(
				decision.get("social_request", {}) as Dictionary
				if decision.get("social_request") is Dictionary
				else {}
			),
			accepted_conversation_follow_up,
			pending_post_injury_reaction,
			decision_can_interrupt_current,
		)
	)


func _submit_optional_social_response(
	resident_id: String,
	response_value: Variant,
) -> void:
	if not response_value is Dictionary:
		return
	var response := response_value as Dictionary
	var matter_id := (
		String(response.get("matter_id", "")).strip_edges()
		if response.get("matter_id") is String
		else ""
	)
	var result := _social_agent_adapter.submit_social_response(
		resident_id,
		response,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	var value := result.get("value", {}) as Dictionary
	var status := String(value.get("status", ""))
	if result.get("ok") == true and status in ["pending", "recorded"]:
		var assignment_outcome := String(
			value.get("assignment_outcome", "")
		)
		if assignment_outcome == "withdrawn":
			var resident := _residents.get(resident_id, {}) as Dictionary
			var current_action := (
				resident.get("currentAction", {}) as Dictionary
			)
			var action_goal := (
				value.get("action_goal", {}) as Dictionary
			)
			var execution := _activity_runtime.execution_for_action(
				resident_id,
				String(current_action.get("action_id", "")),
			) as Dictionary
			if (
				_social_goal_matches_action(
					action_goal,
					current_action,
					resident_id,
				)
				or (
					not execution.is_empty()
					and _social_goal_matches_activity(
						action_goal,
						execution,
					)
				)
			):
				_interrupt_action(
					resident_id,
					"居民已经退出这项承诺",
				)
			_maybe_begin_social_response_after_exposures(matter_id)
		_settle_social_round_if_ready(matter_id)
		_emit_social_matter_summary(matter_id)
		return
	if not matter_id.is_empty():
		var terminal := _social_matters.mark_candidate_terminal(
			matter_id,
			resident_id,
			"request_cancelled",
		) as Dictionary
		if terminal.get("ok") == true:
			_settle_social_round_if_ready(matter_id)
			_emit_social_matter_summary(matter_id)


func _submit_conversation_follow_up(
	resident_id: String,
	action: Dictionary,
	option: Dictionary,
	conversation: Dictionary,
) -> void:
	if option.is_empty() or conversation.is_empty() or String(action.get("type", "")) != "答话":
		return
	var conversation_id := String(conversation.get("conversationId", "")).strip_edges()
	if conversation_id != String(action.get("conversation_id", "")).strip_edges():
		return
	var beneficiary_ref := CONVERSATION_RUNTIME._other_conversation_participant(self, conversation, resident_id)
	var beneficiary_id := _person_id_for_name(beneficiary_ref)
	var capability_id := String(option.get("capability_id", "")).strip_edges()
	var target_refs := (option.get("target_refs", {}) as Dictionary).duplicate(true)
	var meaning := String(option.get("meaning", "")).strip_edges()
	var option_id := String(option.get("option_id", "")).strip_edges()
	if beneficiary_id.is_empty() or capability_id.is_empty() or target_refs.is_empty() or meaning.is_empty() or option_id.is_empty():
		return
	var commitment_id := "conversation-commitment:%s:%s" % [
		conversation_id,
		String(action.get("action_id", "")),
	]
	var now := int(_environment.get_absolute_minute())
	var source_result := sync_conversation_commitment({
		"commitment_id": commitment_id,
		"source_revision": 1,
		"conversation_id": conversation_id,
		"promisor_id": resident_id,
		"beneficiary_id": beneficiary_id,
		"active": true,
		"reason_summary": meaning,
		"place_id": String(option.get("place_id", "")),
		"capability_id": capability_id,
		"target_refs": target_refs,
		"success_result_id": String(option.get("success_result_id", "")),
		"expires_at": now + 360,
		"source_event_ids": ["conversation-follow-up:%s:%s" % [
			conversation_id,
			String(action.get("action_id", "")),
		]],
	}) as Dictionary
	if source_result.get("ok") != true:
		return
	var matter := _social_matters.find_active_matter("conversation_commitment",
		commitment_id,
		[resident_id, beneficiary_id],) as Dictionary
	if matter.is_empty():
		return
	var matter_id := String(matter.get("matter_id", ""))
	var candidate := _social_sources.response_candidate(resident_id,
		0,
		_active_social_commitment_count(resident_id),
		now,
		matter_id,) as Dictionary
	if candidate.is_empty():
		return
	var round_result := _social_matters.begin_response_round(matter_id,
		[candidate],
		now,
		now + 1,) as Dictionary
	if round_result.get("ok") != true:
		return
	matter = _social_matters.get_matter(matter_id) as Dictionary
	var submitted := _social_matters.submit_response(resident_id,
		{
			"response_id": "conversation-response:%s" % String(action.get("action_id", "")),
			"matter_id": matter_id,
			"matter_revision": int(matter.get("revision", 0)),
			"response_round_id": String(matter.get("response_round_id", "")),
			"option_id": "accept",
		},
		now,) as Dictionary
	if submitted.get("ok") != true:
		return
	var settled := _social_matters.settle_response_round(matter_id,
		now,
		"close",) as Dictionary
	if settled.get("ok") != true:
		return
	_reconcile_social_assignments(matter_id)
	action["conversation_commitment_matter_id"] = matter_id
	action["conversation_commitment_option_id"] = option_id
	# 选择正式后续行动就是“结束交谈后马上去做”的明确决定。模型是否额外
	# 填 end=true 不应决定承诺能否开始，否则会出现已经答应却永远停在
	# 对话里的假承诺。只有成功创建并指派事项后才自动结束，失败时仍保留
	# 原对话，让居民可以继续说明或重新决定。
	action["end"] = true
	_emit_social_matter_summary(matter_id)


func _settle_optional_social_attention(
	resident_id: String,
	attention: Dictionary,
	offered_exposures: Array,
) -> void:
	if offered_exposures.is_empty():
		return
	var exposure := offered_exposures[0] as Dictionary
	var matter_id := String(exposure.get("matter_id", ""))
	var option_id := "ignore"
	if (
		String(attention.get("exposure_id", ""))
		== String(exposure.get("exposure_id", ""))
		and String(attention.get("matter_id", "")) == matter_id
		and int(attention.get("matter_revision", -1))
		== int(exposure.get("matter_revision", -2))
		and String(attention.get("option_id", "")) in [
			"notice",
			"ignore",
			"defer",
		]
	):
		option_id = String(attention.get("option_id", ""))
	var resolved := _social_matters.resolve_exposure(
		matter_id,
		resident_id,
		{
			"exposure_id": String(exposure.get("exposure_id", "")),
			"option_id": option_id,
		},
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if resolved.get("ok") != true:
		return
	_emit_social_matter_summary(matter_id)
	_maybe_begin_social_response_after_exposures(matter_id)


func _maybe_begin_social_response_after_exposures(
	matter_id: String,
) -> void:
	var matter := _social_matters.get_matter(
		matter_id,
	) as Dictionary
	if matter.is_empty() or String(matter.get("state", "")) != "open":
		return
	var now := int(_environment.get_absolute_minute())
	var candidates: Array[Dictionary] = []
	var involvement := matter.get("involvement", {}) as Dictionary
	var aware_resident_ids: Array[String] = []
	for resident_value: Variant in (
		matter.get("awareness", {}) as Dictionary
	):
		aware_resident_ids.append(String(resident_value))
	aware_resident_ids.sort()
	for resident_id: String in aware_resident_ids:
		# 玩家可以是事项的知情者或受影响者，但不是由 Agent 调度的居民。
		if not _residents.has(resident_id):
			continue
		var role := String(
			(
				involvement.get(resident_id, {}) as Dictionary
			).get("role", "")
		)
		if (
			role == "creator"
			or _social_resident_already_considered(
				matter,
				resident_id,
			)
		):
			continue
		var load := _active_social_commitment_count(resident_id)
		if load >= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT:
			continue
		var candidate := _social_sources.response_candidate(
			resident_id,
			0,
			load,
			_resident_social_available_at(resident_id, now),
			matter_id,
		) as Dictionary
		if not candidate.is_empty():
			candidates.append(candidate)
		if candidates.size() >= MAX_SOCIAL_RESPONSE_CANDIDATES:
			break
	if candidates.is_empty():
		return
	var started := _social_matters.begin_response_round(
		matter_id,
		candidates,
		now,
		mini(now + 30, int(matter.get("expires_at", now + 30))),
	) as Dictionary
	if started.get("ok") != true:
		return
	for candidate: Dictionary in candidates:
		_schedule_decision(
			String(candidate.get("resident_id", "")),
			true,
		)
	_emit_social_matter_summary(matter_id)


func _social_resident_already_considered(
	matter: Dictionary,
	resident_id: String,
) -> bool:
	return SOCIAL_JUDGMENTS.social_resident_already_considered(matter, resident_id)


func _submit_optional_social_request(
	resident_id: String,
	action: Dictionary,
	request: Dictionary,
) -> void:
	if (
		request.is_empty()
		or String(action.get("type", "")) != "搭话"
	):
		return
	var recipient_id := _resident_key(
		String(request.get("recipient_id", ""))
	)
	var target_id := _resident_key(
		String(action.get("target_resident_id", ""))
	)
	var place_id := String(
		request.get("place_id", "")
	).strip_edges()
	var reason_summary := String(
		request.get("reason_summary", "")
	).strip_edges()
	if (
		recipient_id.is_empty()
		or recipient_id != target_id
		or place_id.is_empty()
		or get_place_detail(place_id).is_empty()
		or reason_summary.is_empty()
		or reason_summary.length() > 80
		or reason_summary.contains("\n")
		or reason_summary.contains("\r")
		or reason_summary.contains("\t")
	):
		return
	var now := int(_environment.get_absolute_minute())
	sync_resident_request({
		"request_id": "resident-request:%s:%s"
		% [
			resident_id,
			String(action.get("action_id", "")),
		],
		"source_revision": 1,
		"requester_id": resident_id,
		"recipient_ids": [recipient_id],
		"submitted": true,
		"active": true,
		"reason_summary": reason_summary,
		"subject_ids": [resident_id],
		"place_id": place_id,
		"capability_id": "world.go_to_place",
		"target_refs": {
			"place_id": place_id,
			"resident_id": resident_id,
		},
		"success_result_id": "helper-arrived",
		"expires_at": now + 180,
		"capacity": 1,
		"source_event_ids": [
			"direct-request:%s"
			% String(action.get("action_id", "")),
		],
	})


func _submit_legacy_prop_activity(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var shape_error := _validate_action_shape(action)
	if shape_error.is_empty() and (
		resident.get("usedActionIds", {}) as Dictionary
	).has(String(action.get("action_id", "")).strip_edges()):
		shape_error = "动作 action_id 已被该居民使用：%s" % String(
			action.get("action_id", "")
		).strip_edges()
	if not shape_error.is_empty():
		return _reject_invalid_action(
			resident_id,
			resident,
			action,
			shape_error,
		)
	if _is_dynamic_prop_action(resident, action):
		return _submit_direct_prop_action(
			resident_id,
			resident,
			decision_id,
			action,
			conversation_end_reason,
			allow_current_activity_interrupt,
		)
	var mapping := _activity_runtime.legacy_activity_mapping(
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		String(action.get("prop", "")),
		String(action.get("verb", "")),
	) as Dictionary
	if mapping.get("ok") != true:
		if _is_layout_override_prop_action(resident, action):
			return _submit_direct_prop_action(
				resident_id,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				allow_current_activity_interrupt,
			)
		var rejection := _reject_invalid_action(
			resident_id,
			resident,
			action,
			String(
				(mapping.get(
					"errors",
					["旧用道具动作不能唯一映射到可执行活动"],
				) as Array)[0]
			),
		)
		rejection["errorCode"] = String(
			mapping.get("errorCode", "ACTIVITY_NO_EXECUTABLE_SLOT")
		)
		rejection["retryable"] = bool(mapping.get("retryable", false))
		if conversation_end_reason == "拒绝接话":
			var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, 
				resident_id
			)
			if not active_conversation.is_empty():
				CONVERSATION_RUNTIME._end_conversation(self, 
					String(active_conversation.get("conversationId", "")),
					conversation_end_reason,
					"rejected",
				)
		return rejection
	if resident_id == _observed_action_preview_resident_id:
		var observed_preflight := _preflight_observed_legacy_prop_activity(
			resident_id,
			resident,
			decision_id,
			action,
			mapping,
		)
		if observed_preflight.get("ok") != true:
			return _reject_legacy_prop_activation(
				resident_id,
				action,
				observed_preflight,
				conversation_end_reason,
			)
	(resident.get("usedActionIds", {}) as Dictionary)[
		String(action.get("action_id", "")).strip_edges()
	] = true
	_clear_rejected_action_streak(resident)
	if resident_id == _observed_action_preview_resident_id:
		return _confirm_action_preview(
			resident_id,
			resident,
			decision_id,
			"replace_current",
			action,
			conversation_end_reason,
			{},
			{},
			{},
			{},
			allow_current_activity_interrupt,
		)
	return _activate_legacy_prop_activity(
		resident_id,
		resident,
		decision_id,
		action,
		conversation_end_reason,
		mapping,
		allow_current_activity_interrupt,
	)


func _preflight_observed_legacy_prop_activity(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	mapping: Dictionary,
) -> Dictionary:
	var target := {
		"activityId": String(mapping.get("activityId", "")),
		"placeId": String(mapping.get("placeId", "")),
	}
	var preferred_slot_id := String(
		mapping.get("preferredSlotId", "")
	).strip_edges()
	if not preferred_slot_id.is_empty():
		target["preferredSlotId"] = preferred_slot_id
	var step := {
		"stepId": String(action.get("action_id", "")).strip_edges(),
		"operation": "activity.perform",
		"target": target,
		"params": {
			"reason": String(action.get("line", "")),
		},
	}
	var validated := _activity_runtime.validate_step(
		resident_id,
		"legacy-prop-use:%s" % decision_id,
		0,
		step,
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		get_weather(),
	) as Dictionary
	if validated.get("ok") != true:
		return validated
	return _preflight_activity_candidates(resident, validated)


func _submit_agent_activity(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var activity_id := String(action.get("activity_id", "")).strip_edges()
	if (
		activity_id.is_empty()
		or String(action.get("line", "")).strip_edges().is_empty()
	):
		return _reject_invalid_action(
			resident_id,
			resident,
			action,
			"做活动必须包含当前可做的 activity_id 和非空 line",
		)
	var available := false
	for option_value: Variant in _agent_available_activities(
		resident,
		true,
		activity_id,
		1,
	):
		if String(
			(option_value as Dictionary).get("activity_id", "")
		) == activity_id:
			available = true
			break
	if not available:
		resident["busyActivityReconsideration"] = true
		_schedule_decision(resident_id, false)
		return _command_failure(
			"ACTIVITY_STATE_CHANGED",
			["这项活动当前不可用，请根据最新活动列表重新决定"],
			{"stale": true},
			true,
		)
	if resident_id == _observed_action_preview_resident_id:
		var preflight := _preflight_agent_activity(
			resident_id,
			resident,
			decision_id,
			action,
		)
		if preflight.get("ok") != true:
			return _reject_legacy_prop_activation(
				resident_id,
				action,
				preflight,
				conversation_end_reason,
			)
	(resident.get("usedActionIds", {}) as Dictionary)[
		String(action.get("action_id", "")).strip_edges()
	] = true
	_clear_rejected_action_streak(resident)
	if resident_id == _observed_action_preview_resident_id:
		return _confirm_action_preview(
			resident_id,
			resident,
			decision_id,
			"replace_current",
			action,
			conversation_end_reason,
			{},
			{},
			{},
			{},
			allow_current_activity_interrupt,
		)
	return _activate_agent_activity(
		resident_id,
		resident,
		decision_id,
		action,
		conversation_end_reason,
		allow_current_activity_interrupt,
	)


func _preflight_agent_activity(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
) -> Dictionary:
	var step := _agent_activity_step(
		action,
		String(resident.get("currentPlace", "")),
	)
	var validated := _activity_runtime.validate_step(
		resident_id,
		"agent-activity:%s" % decision_id,
		0,
		step,
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		get_weather(),
	) as Dictionary
	if validated.get("ok") != true:
		return validated
	return _preflight_activity_candidates(resident, validated)


func _activate_agent_activity(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var meal_result := DINING_SERVICE.activate_agent_meal_routine(self, resident_id, resident, decision_id, action, conversation_end_reason, allow_current_activity_interrupt) as Dictionary
	if not meal_result.is_empty():
		return meal_result
	var performed := _perform_activity_step_internal(
		resident_id,
		"agent-activity:%s" % decision_id,
		0,
		_agent_activity_step(
			action,
			String(resident.get("currentPlace", "")),
		),
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_AGENT_ACTIVITY,
		String(action.get("action_id", "")).strip_edges(),
		-1,
		allow_current_activity_interrupt,
	)
	if performed.get("ok") != true:
		return _reject_legacy_prop_activation(
			resident_id,
			action,
			performed,
			conversation_end_reason,
		)
	if not conversation_end_reason.is_empty():
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(self, 
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				(
					"rejected"
					if conversation_end_reason == "拒绝接话"
					else "interrupted"
				),
			)
	return {
		"ok": true,
		"stale": false,
		"status": "accepted",
		"action": _public_current_action(
			resident.get("currentAction", {}) as Dictionary
		),
		"actionPhase": ACTION_PRESENTATION._resident_action_phase_projection(self, resident),
		"activity": (
			performed.get("execution", {}) as Dictionary
		).duplicate(true),
	}


func _agent_activity_step(
	action: Dictionary,
	place_id: String,
) -> Dictionary:
	return ACTION_SUPPORT.agent_activity_step(action, place_id)


func _submit_direct_prop_action(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	if String(action.get("line", "")).strip_edges().is_empty():
		return _reject_invalid_action(
			resident_id,
			resident,
			action,
			"用道具动作必须包含非空 line",
		)
	if not _direct_prop_action_available(resident_id, resident, action):
		resident["busyActivityReconsideration"] = true
		resident["doing"] = "这个位置正有人用，正在另找能做的事"
		return _reject_invalid_action(
			resident_id,
			resident,
			action,
			"这个道具位置当前正被其他居民使用",
		)
	var preparation := _prepare_prop_action(resident, action)
	if preparation.get("ok") != true:
		return _reject_invalid_action(
			resident_id,
			resident,
			action,
			String(
				(preparation.get(
					"errors",
					["当前世界道具不可交互"],
				) as Array)[0]
			),
		)
	(resident.get("usedActionIds", {}) as Dictionary)[
		String(action.get("action_id", "")).strip_edges()
	] = true
	return _confirm_action_preview(
		resident_id,
		resident,
		decision_id,
		"replace_current",
		preparation.get("action", {}) as Dictionary,
		conversation_end_reason,
		{},
		{},
		{},
		{},
		allow_current_activity_interrupt,
	)


func _activate_legacy_prop_activity(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	action: Dictionary,
	conversation_end_reason: String,
	prevalidated_mapping: Dictionary = {},
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var mapping := prevalidated_mapping.duplicate(true)
	if mapping.is_empty():
		mapping = _activity_runtime.legacy_activity_mapping(
			resident.get("socialState", {}) as Dictionary,
			String(resident.get("currentPlace", "")),
			String(action.get("prop", "")),
			String(action.get("verb", "")),
		) as Dictionary
	if mapping.get("ok") != true:
		return _reject_legacy_prop_activation(
			resident_id,
			action,
			mapping,
			conversation_end_reason,
		)
	var routine_descriptor := _activity_runtime.routine_descriptor(
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		String(mapping.get("activityId", "")),
	) as Dictionary
	if not routine_descriptor.is_empty():
		var routine_candidates := _activity_runtime.routine_candidates(
			resident.get("socialState", {}) as Dictionary,
			String(resident.get("currentPlace", "")),
			String(routine_descriptor.get("group", "")),
		) as Array[Dictionary]
		var has_next_activity := routine_candidates.any(
			func(candidate: Dictionary) -> bool:
				return (
					bool(candidate.get("available", false))
					and String(candidate.get("activityId", ""))
					!= String(mapping.get("activityId", ""))
			)
		)
		if has_next_activity:
			if (
				String(routine_descriptor.get("group", "")) == "meal"
				and String(routine_descriptor.get("phase", "")) != "collect"
			):
				for candidate: Dictionary in routine_candidates:
					if (
						bool(candidate.get("available", false))
						and String(candidate.get("phase", "")) == "collect"
					):
						mapping["activityId"] = String(
							candidate.get("activityId", "")
						)
						mapping.erase("preferredSlotId")
						routine_descriptor = candidate.duplicate(true)
						routine_descriptor["group"] = "meal"
						break
			return _activate_activity_routine(
				resident_id,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				mapping,
				routine_descriptor,
				allow_current_activity_interrupt,
			)
	var target := {
		"activityId": String(mapping.get("activityId", "")),
		"placeId": String(mapping.get("placeId", "")),
	}
	var preferred_slot_id := String(
		mapping.get("preferredSlotId", "")
	).strip_edges()
	if not preferred_slot_id.is_empty():
		target["preferredSlotId"] = preferred_slot_id
	var step := {
		"stepId": String(action.get("action_id", "")).strip_edges(),
		"operation": "activity.perform",
		"target": target,
		"params": {
			"reason": String(action.get("line", "")),
		},
	}
	var performed := _perform_activity_step_internal(
		resident_id,
		"legacy-prop-use:%s" % decision_id,
		0,
		step,
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_LEGACY_PROP,
		String(action.get("action_id", "")).strip_edges(),
		-1,
		allow_current_activity_interrupt,
	)
	if performed.get("ok") != true:
		return _reject_legacy_prop_activation(
			resident_id,
			action,
			performed,
			conversation_end_reason,
		)
	if not conversation_end_reason.is_empty():
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(self, 
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				(
					"rejected"
					if conversation_end_reason == "拒绝接话"
					else "interrupted"
				),
			)
	return {
		"ok": true,
		"stale": false,
		"status": "accepted",
		"action": _public_current_action(
			resident.get("currentAction", {}) as Dictionary
		),
		"actionPhase": ACTION_PRESENTATION._resident_action_phase_projection(self, resident),
		"activity": (
			performed.get("execution", {}) as Dictionary
		).duplicate(true),
	}


func _activate_activity_routine(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	source_action: Dictionary,
	conversation_end_reason: String,
	mapping: Dictionary,
	descriptor: Dictionary,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var group := String(descriptor.get("group", ""))
	var routine_id := "routine:%s:%s" % [
		resident_id,
		String(source_action.get("action_id", "")),
	]
	var absolute_minute := int(_environment.get_absolute_minute())
	_activity_routines[resident_id] = {
		"routineId": routine_id,
		"sourceActionId": String(source_action.get("action_id", "")),
		"placeId": String(mapping.get("placeId", "")),
		"group": group,
		"mealPeriodRef": DINING_SERVICE.meal_period_ref_for_routine(self, group, absolute_minute),
		"endAbsoluteMinute": (
			absolute_minute
			+ int(ACTIVITY_ROUTINE_DURATION_MINUTES.get(group, 30))
		),
		"sequence": 0,
		"lastActivityId": String(mapping.get("activityId", "")),
		"lastPhase": String(descriptor.get("phase", "")),
		"visitedActivityIds": [
			String(mapping.get("activityId", "")),
		],
		"choiceSeed": hash("%s:%d:%s" % [
			resident_id,
			absolute_minute,
			String(source_action.get("action_id", "")),
		]),
	}
	var target := {
		"activityId": String(mapping.get("activityId", "")),
		"placeId": String(mapping.get("placeId", "")),
	}
	var preferred_slot_id := String(
		mapping.get("preferredSlotId", "")
	).strip_edges()
	if not preferred_slot_id.is_empty():
		target["preferredSlotId"] = preferred_slot_id
	var step := {
		"stepId": "step-0",
		"operation": "activity.perform",
		"target": target,
		"params": {"reason": String(source_action.get("line", ""))},
	}
	var performed := _perform_activity_step_internal(
		resident_id,
		routine_id,
		0,
		step,
		ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_DIRECT,
		"",
		int(ACTIVITY_ROUTINE_STEP_CAP_MINUTES.get(group, 15)),
		allow_current_activity_interrupt,
	)
	if performed.get("ok") != true:
		_activity_routines.erase(resident_id)
		return _reject_legacy_prop_activation(
			resident_id,
			source_action,
			performed,
			conversation_end_reason,
		)
	if not conversation_end_reason.is_empty():
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(self, 
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				(
					"rejected"
					if conversation_end_reason == "拒绝接话"
					else "interrupted"
				),
			)
	var routine_snapshot := (
		_activity_routines.get(resident_id, {}) as Dictionary
	).duplicate(true)
	return {
		"ok": true,
		"stale": false,
		"status": "accepted",
		"action": _public_current_action(
			resident.get("currentAction", {}) as Dictionary
		),
		"actionPhase": ACTION_PRESENTATION._resident_action_phase_projection(self, resident),
		"activity": (
			performed.get("execution", {}) as Dictionary
		).duplicate(true),
		# Activity lifecycle callbacks run synchronously. A listener may finish or
		# interrupt the routine before activation returns, so the entry is not
		# guaranteed to still exist here.
		"routine": routine_snapshot,
	}


func _reject_legacy_prop_activation(
	resident_id: String,
	action: Dictionary,
	failure_source: Dictionary,
	conversation_end_reason: String,
) -> Dictionary:
	var errors := failure_source.get(
		"errors",
		["旧用道具动作的 activity.perform 激活失败"],
	) as Array
	var reason := (
		String(errors[0])
		if not errors.is_empty()
		else "旧用道具动作的 activity.perform 激活失败"
	)
	var resident := _residents[resident_id] as Dictionary
	if (
		String(failure_source.get("errorCode", ""))
		== "ACTIVITY_RESERVATION_CONFLICT"
		and (resident.get("currentAction", {}) as Dictionary).is_empty()
	):
		resident["busyActivityReconsideration"] = true
		resident["doing"] = "这个位置正有人用，正在另找能做的事"
		_emit_resident_state_changed(resident_id)
	_queue_action_result(
		resident_id,
		String(action.get("action_id", "")).strip_edges(),
		"rejected",
		reason,
		true,
		true,
		ACTION_PRESENTATION._preview_action_presentation(self, resident, {"action": action}),
	)
	if conversation_end_reason == "拒绝接话":
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(self, 
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				"rejected",
			)
	return {
		"ok": false,
		"stale": false,
		"errorCode": String(
			failure_source.get("errorCode", "ACTIVITY_STATE_CHANGED")
		),
		"retryable": bool(failure_source.get("retryable", false)),
		"errors": [reason],
	}


func _confirm_action_preview(
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
	handling: String,
	action: Dictionary,
	conversation_end_reason := "",
	story_provenance: Dictionary = {},
	social_request: Dictionary = {},
	conversation_follow_up: Dictionary = {},
	post_injury_reaction: Dictionary = {},
	decision_can_interrupt_current := false,
	conflict_intent: Dictionary = {},
	decision_wake_snapshot: Dictionary = {},
) -> Dictionary:
	_clear_rejected_action_streak(resident)
	var action_id := String(action.get("action_id", ""))
	var preview := {
		"previewId": "%s::%s" % [decision_id, action_id],
		"decisionId": decision_id,
		"actionId": action_id,
		"handling": handling,
		"summary": ACTION_PRESENTATION._action_preview_summary(self, action, handling == "continue_current"),
		"publicThought": ACTION_PRESENTATION._public_surface_thought(self, action),
		"confirmedRevision": _world_revision,
		"confirmedAt": get_time(),
		"displaySeconds": CONFIRMED_ACTION_PREVIEW_SECONDS,
		"holdSeconds": CONFIRMED_ACTION_PREVIEW_SECONDS,
		"remainingSeconds": CONFIRMED_ACTION_PREVIEW_SECONDS,
		"conversationEndReason": conversation_end_reason,
		"storyProvenance": story_provenance.duplicate(true),
		"socialRequest": social_request.duplicate(true),
		"conversationFollowUp": conversation_follow_up.duplicate(true),
		"postInjuryReaction": post_injury_reaction.duplicate(true),
		"decisionMayInterruptCurrent": decision_can_interrupt_current,
		"conflictIntent": conflict_intent.duplicate(true),
		"decisionWakeSnapshot": decision_wake_snapshot.duplicate(true),
		"action": action.duplicate(true),
		"submittedAction": _submitted_action_for_preview(action),
	}
	if (
		handling == "continue_current"
		or resident_id != _observed_action_preview_resident_id
	):
		resident["confirmedActionPreview"] = {}
		# This activation occurs in the same call stack as successful preparation;
		# no World state can change between validation and activation. Reuse the
		# prepared action instead of repeating route/idle parking work. Observed
		# previews still revalidate after their real-time display delay.
		_activate_confirmed_action(resident_id, resident, preview, true)
	else:
		resident["confirmedActionPreview"] = preview
		_bump_world_revision()
		resident_action_phase_changed.emit(
			resident_id,
			ACTION_PRESENTATION._resident_action_phase_projection(self, resident),
		)
		_emit_resident_state_changed(resident_id)
	var phase := ACTION_PRESENTATION._resident_action_phase_projection(self, resident)
	return {
		"ok": true,
		"status": "continued" if handling == "continue_current" else "accepted",
		"action": _public_current_action(action),
		"actionPhase": phase,
	}


func _advance_confirmed_action_previews(real_seconds: float) -> void:
	if not is_finite(real_seconds) or real_seconds <= 0.0:
		return
	# 只有被观察居民可能持有 preview（其余路径立即激活，存档也不持久化），
	# 逐帧只需要看这一个居民。
	var resident_id := _observed_action_preview_resident_id
	if resident_id.is_empty() or not _residents.has(resident_id):
		return
	var resident := _residents[resident_id] as Dictionary
	var preview := resident.get("confirmedActionPreview", {}) as Dictionary
	if preview.is_empty():
		return
	preview["remainingSeconds"] = maxf(
		0.0,
		float(preview.get("remainingSeconds", 0.0)) - real_seconds,
	)
	resident["confirmedActionPreview"] = preview
	if float(preview.get("remainingSeconds", 0.0)) <= 0.0:
		_finish_confirmed_action_preview(resident_id, resident)


func _activate_confirmed_action(
	resident_id: String,
	resident: Dictionary,
	preview: Dictionary,
	prepared_action_is_fresh := false,
) -> void:
	var probe_lap_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	if preview.is_empty():
		return
	var handling := String(preview.get("handling", ""))
	var conversation_end_reason := String(preview.get("conversationEndReason", ""))
	var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id)
	if handling == "continue_current":
		_resume_conversation_follow_up_reconsideration(resident)
		_resume_suspended_action(resident)
		if not conversation_end_reason.is_empty() and not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(self, 
				String(active_conversation.get("conversationId", "")),
				conversation_end_reason,
				"rejected",
			)
		_bump_world_revision()
		var continued_phase := ACTION_PRESENTATION._resident_action_phase_projection(self, resident)
		resident_action_phase_changed.emit(resident_id, continued_phase.duplicate(true))
		_emit_resident_state_changed(resident_id)
		return
	var action := (
		preview.get("action", {}) as Dictionary
	).duplicate(true)
	var decision_can_interrupt_current := bool(
		preview.get("decisionMayInterruptCurrent", false)
	)
	if (
		String(action.get("type", "")) == "用道具"
		and String(action.get("dynamicPropId", "")).is_empty()
	):
		_activate_legacy_prop_activity(
			resident_id,
			resident,
			String(preview.get("decisionId", "")),
			action,
			conversation_end_reason,
			{},
			decision_can_interrupt_current,
		)
		return
	if String(action.get("type", "")) == "做活动":
		_activate_agent_activity(
			resident_id,
			resident,
			String(preview.get("decisionId", "")),
			action,
			conversation_end_reason,
			decision_can_interrupt_current,
		)
		return
	var submitted_action := (
		preview.get(
			"submittedAction",
			_submitted_action_for_preview(action),
		) as Dictionary
	).duplicate(true)
	if String(action.get("type", "")) in [
		"争执",
		"攻击",
		"回应冲突",
		"介入冲突",
		"离开冲突",
	]:
		_activate_conflict_action(
			resident_id,
			resident,
			action,
			preview,
			conversation_end_reason,
			active_conversation,
		)
		return
	var refreshed := (
		{"ok": true, "action": action}
		if prepared_action_is_fresh
		else (
			_prepare_prop_action(resident, submitted_action)
			if not String(action.get("dynamicPropId", "")).is_empty()
			else _prepare_action(resident, submitted_action, true)
		)
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_prepare")
	if refreshed.get("ok") != true:
		_reject_confirmed_action_preview_activation(
			resident_id,
			resident,
			submitted_action,
			String(
				(refreshed.get(
					"errors",
					["预览结束时动作条件已经失效"],
				) as Array)[0]
			),
		)
		return
	action = (
		refreshed.get("action", {}) as Dictionary
	).duplicate(true)
	# 预览确认时会重新校验玩家可提交字段。同行、代取等 World 内部状态
	# 不属于模型输入字段，必须从已确认动作带回，否则动作虽然开始移动，
	# 却会退化成普通“去”，承诺永远无法推进与结算。
	_copy_conversation_follow_up_state(
		preview.get("action", {}) as Dictionary,
		action,
	)
	if (
		String(action.get("type", "")) == "答话"
		and not active_conversation.is_empty()
		and String(active_conversation.get("waitingFor", "")) == resident_id
	):
		CONVERSATION_RUNTIME._activate_conversation_reply(self,
			resident_id,
			resident,
			action,
			preview,
		)
		return
	var old_action := resident.get("currentAction", {}) as Dictionary
	if not old_action.is_empty():
		var activity_execution := _activity_runtime.execution_for_action(
			resident_id,
			String(old_action.get("action_id", "")),
		) as Dictionary
		if not activity_execution.is_empty():
			_interrupt_action(
				resident_id,
				"居民确认新的合法动作后替换当前活动",
				decision_can_interrupt_current,
			)
		else:
			var replacement_status := (
				"completed" if decision_can_interrupt_current else "replaced"
			)
			var replacement_reason := (
				_priority_action_settlement_reason(
					old_action,
					"居民确认新的高优先级动作",
				)
				if decision_can_interrupt_current
				else "居民确认新的合法动作后开始执行"
			)
			_record_matching_social_action_result(
				resident_id,
				old_action,
				replacement_status,
				replacement_reason,
			)
			_append_action_result_without_schedule(
				resident_id,
				String(old_action.get("action_id", "")),
				replacement_status,
				replacement_reason,
			)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_replace_old")
	_rebase_action_timing(action)
	resident["currentAction"] = action
	if bool(action.get("consumeRouteConnector", false)):
		# A connector describes only the path back from the resident's current
		# indoor interaction anchor to the room network. Once a confirmed action
		# consumes it, carrying it into another building poisons all later path
		# queries with coordinates from the old space.
		resident["routeConnector"] = []
	resident["actionSuspendedAbsoluteMinute"] = -1
	# `line` is the resident's public expression, not an authoritative World
	# fact. Keep the formal state derived only from the validated action fields
	# so a model cannot make an unauthored prop or outcome appear to exist.
	resident["doing"] = _default_doing(action)
	_count_agent_request_metric("behaviorStarted")
	_start_matching_social_action(resident_id, action)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_social")
	_record_story_action_started(
		resident_id,
		action,
		preview.get("storyProvenance", {}) as Dictionary,
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_story")
	_bump_world_revision()
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_revision")
	var resident_display_name := _resident_display_name(resident_id)
	_emit_resident_state_changed(resident_id)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_resident_emit")
	var presented_action := _presentation_action(action)
	presented_action["residentId"] = resident_id
	resident_action_started.emit(resident_display_name, presented_action)
	resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(self, resident),
	)
	WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activation_action_signals")
	var action_type := String(action.get("type", ""))
	if action_type == "搭话":
		if String(action.get("approachMode", "")).is_empty():
			CONVERSATION_RUNTIME._start_conversation(self, resident_id, action)
			_submit_optional_social_request(
				resident_id,
				action,
				preview.get("socialRequest", {}) as Dictionary,
			)
	elif action_type == "答话":
		_submit_conversation_follow_up(
			resident_id,
			action,
			preview.get("conversationFollowUp", {}) as Dictionary,
			active_conversation,
		)
		CONVERSATION_RUNTIME._apply_conversation_reply(self, resident_id, action)
		var conflict_intent := preview.get("conflictIntent", {}) as Dictionary
		if not conflict_intent.is_empty():
			var conflict_result := CONVERSATION_CONFLICT_BRIDGE.activate_after_reply(
				self,
				resident_id,
				resident,
				conflict_intent,
				preview.get("decisionWakeSnapshot", {}) as Dictionary,
				preview.get("storyProvenance", {}) as Dictionary,
			) as Dictionary
			if conflict_result.get("ok") != true:
				resident["doing"] = "这场火气已经散了，先缓一缓"
				_queue_action_result(
					resident_id,
					String(conflict_intent.get("action_id", "")),
					"rejected",
					"对方已经走远，冲突没有继续",
					true,
					true,
				)
	elif not conversation_end_reason.is_empty() and not active_conversation.is_empty():
		CONVERSATION_RUNTIME._end_conversation(self, 
			String(active_conversation.get("conversationId", "")),
			conversation_end_reason,
			"rejected" if conversation_end_reason == "拒绝接话" else "interrupted",
		)
	_settle_post_injury_conflict(
		resident_id,
		String(action.get("type", "")),
		preview.get("postInjuryReaction", {}) as Dictionary,
	)


func _activate_conflict_action(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	preview: Dictionary,
	conversation_end_reason: String,
	active_conversation: Dictionary,
) -> void:
	var old_action := resident.get("currentAction", {}) as Dictionary
	if not old_action.is_empty():
		_interrupt_action(
			resident_id,
			"居民决定立即处理眼前的冲突",
			true,
		)
	if (
		not conversation_end_reason.is_empty()
		and not active_conversation.is_empty()
	):
		CONVERSATION_RUNTIME._end_conversation(self, 
			String(active_conversation.get("conversationId", "")),
			conversation_end_reason,
			"interrupted",
		)
	var result := (
		_conflict_agent_world_bridge.execute_action(resident_id,
			action,) as Dictionary
		if _conflict_agent_world_bridge != null
		else {"ok": false, "errorCode": "CONFLICT_BRIDGE_NOT_CONFIGURED"}
	)
	var action_type := String(action.get("type", ""))
	var public_line := String(action.get("line", "")).strip_edges()
	resident["doing"] = (
		public_line if not public_line.is_empty() else _default_doing(action)
	)
	_record_story_action_started(
		resident_id,
		action,
		preview.get("storyProvenance", {}) as Dictionary,
	)
	_queue_action_result(
		resident_id,
		String(action.get("action_id", "")),
		"completed" if result.get("ok") == true else "rejected",
		(
			TownConflictAgentWorldBridge.action_result_text(action_type)
			if result.get("ok") == true
			else TownConflictAgentWorldBridge.action_error_text(String(
				result.get("errorCode", "CONFLICT_ACTION_REJECTED")
			))
		),
		true,
		true,
	)
	_emit_resident_state_changed(resident_id)


func _submitted_action_for_preview(action: Dictionary) -> Dictionary:
	return ACTION_PROJECTION_MODULE.submitted_action_for_preview(action)


func _reject_confirmed_action_preview_activation(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	reason: String,
) -> void:
	_append_action_result_without_schedule(
		resident_id,
		String(action.get("action_id", "")),
		"rejected",
		reason,
		ACTION_PRESENTATION._preview_action_presentation(self, resident, {"action": action}),
	)
	_schedule_decision(resident_id, false)
	_bump_world_revision()
	resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(self, resident),
	)
	_emit_resident_state_changed(resident_id)


func _finish_confirmed_action_preview(
	resident_id: String,
	resident: Dictionary,
) -> void:
	var preview := resident.get("confirmedActionPreview", {}) as Dictionary
	if preview.is_empty():
		return
	resident["confirmedActionPreview"] = {}
	_activate_confirmed_action(resident_id, resident, preview)


func _has_observed_action_preview() -> bool:
	if _observed_action_preview_resident_id.is_empty():
		return false
	if not _residents.has(_observed_action_preview_resident_id):
		return false
	var resident := (
		_residents[_observed_action_preview_resident_id] as Dictionary
	)
	return not (
		resident.get("confirmedActionPreview", {}) as Dictionary
	).is_empty()


func _release_observed_action_preview() -> void:
	if _observed_action_preview_resident_id.is_empty():
		return
	if not _residents.has(_observed_action_preview_resident_id):
		return
	var resident := (
		_residents[_observed_action_preview_resident_id] as Dictionary
	)
	if (resident.get("confirmedActionPreview", {}) as Dictionary).is_empty():
		return
	_finish_confirmed_action_preview(
		_observed_action_preview_resident_id,
		resident,
	)


func _rebase_action_timing(action: Dictionary) -> void:
	ACTION_TIMING.rebase_action_timing(self, action)


func _resume_suspended_action(resident: Dictionary) -> void:
	ACTION_TIMING.resume_suspended_action(self, resident)


func _append_action_result_without_schedule(
	resident_id: String,
	action_id: String,
	status: String,
	reason: String,
	presentation: Dictionary = {},
) -> void:
	if RESIDENT_ARRIVAL_RUNTIME.is_entry_continuity_action_id(resident_id, action_id): return
	var resident := _residents[resident_id] as Dictionary
	var result := {
		"residentId": resident_id,
		"action_id": action_id,
		"status": status,
		"reason": reason,
		"time": get_time(),
	}
	_apply_action_result_presentation(result, status, presentation)
	_append_or_replace_action_result(
		resident.get("resultQueue", []) as Array,
		result,
	)
	if bool(resident.get("decisionPending", false)):
		AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	_append_public_event_log(
		_next_world_event_id(),
		"action_result",
		resident_id,
		_resident_display_name(resident_id),
		String(resident.get("currentPlace", "")),
		result,
	)
	_record_story_action_outcome(
		resident_id,
		action_id,
		status,
		reason,
	)
	action_result_created.emit(_resident_display_name(resident_id), result.duplicate(true))

func get_conversation(conversation_id: String) -> Dictionary:
	if not _conversations.has(conversation_id):
		return {}
	return (_conversations[conversation_id] as Dictionary).duplicate(true)


func get_active_conversations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[String] = []
	for conversation_id_value: Variant in _conversations:
		ids.append(String(conversation_id_value))
	ids.sort()
	for conversation_id in ids:
		var conversation := _conversations[conversation_id] as Dictionary
		if String(conversation.get("status", "")) == "active":
			result.append(conversation.duplicate(true))
	return result


func _resident_runtime(record: Dictionary, world_state: Dictionary, resident_id := "") -> Dictionary:
	var pair := world_state.get("position", []) as Array
	var body := (
		world_state.get("body", {}) as Dictionary
	).duplicate(true)
	return {
		"residentId": resident_id,
		"movementRevision": 1,
		"attributes": (record.get("attributes", {}) as Dictionary).duplicate(true),
		"socialState": (record.get("socialState", {}) as Dictionary).duplicate(true),
		"arrivalState": {
			"status": "arrived",
			"scheduledAbsoluteMinute": -1,
			"arrivedAbsoluteMinute": -1,
		},
		"position": Vector2(float(pair[0]), float(pair[1])),
		"spaceId": String(world_state.get("spaceId", "")),
		"regionId": String(world_state.get("regionId", "")),
		"currentPlace": String(world_state.get("place", "")),
		"doing": String(world_state.get("doing", "")),
		"body": body,
		"activityState": _activity_state_from_body(body),
		"attendanceState": {
			"status": "available",
			"untilMinute": -1,
		},
		"nearby": [],
		"currentAction": {},
		"confirmedActionPreview": {},
		"actionSuspendedAbsoluteMinute": -1,
		"routeConnector": [],
		"conversationId": "",
		"conversation": null,
		"eventQueue": [],
		"resultQueue": [],
		"usedActionIds": {},
		"lastRejectedActionFingerprint": "",
		"consecutiveRejectedActionCount": 0,
		"decisionSequence": 0,
		"decisionPending": false,
		"validDecisionId": "",
		"decisionMayInterruptCurrent": false,
		"pendingWake": {},
		"pendingWakeState": AGENT_WAKE_STATE_RUNTIME.initial_state(),
		"wakeDispatchQueued": false,
		"inflightEvents": [],
		"inflightResults": [],
		"decisionPrefetch": false,
		"prefetchedDecision": {},
	}


func _resident_home_anchor(
	world_data: Dictionary,
	resident: Dictionary,
) -> Dictionary:
	var home_place := String(
		(resident.get("socialState", {}) as Dictionary).get("home", ""),
	).strip_edges()
	if not home_place.is_empty():
		for prop_value: Variant in world_data.get("props", []) as Array:
			if not prop_value is Dictionary:
				continue
			var prop := prop_value as Dictionary
			var interaction := prop.get("interaction", {}) as Dictionary
			var actions := prop.get("actions", []) as Array
			var action_verb := ""
			if not actions.is_empty() and actions[0] is Dictionary:
				action_verb = String(
					(actions[0] as Dictionary).get("verb", ""),
				)
			if (
				String(prop.get("placeName", "")) != home_place
				or action_verb != "睡觉"
				or not interaction.get("position") is Array
			):
				continue
			var pair := interaction.get("position", []) as Array
			if pair.size() != 2:
				continue
			return {
				"spaceId": String(interaction.get("spaceId", "")),
				"regionId": String(interaction.get("regionId", "")),
				"placeName": home_place,
				"position": Vector2(float(pair[0]), float(pair[1])),
			}
		for connection_value: Variant in world_data.get(
			"connections",
			[],
		) as Array:
			if not connection_value is Dictionary:
				continue
			var connection := connection_value as Dictionary
			for endpoint_key in ["from", "to"]:
				var endpoint := connection.get(endpoint_key, {}) as Dictionary
				if String(endpoint.get("placeName", "")) == home_place:
					return _connection_anchor(endpoint)
	# Lifecycle identity must still be valid for openings whose home metadata is
	# incomplete. Keep the resident's real starting anchor instead of inventing
	# a prop or rejecting the whole town.
	return {
		"spaceId": String(resident.get("spaceId", "")),
		"regionId": String(resident.get("regionId", "")),
		"placeName": String(
			resident.get("currentPlace", home_place),
		),
		"position": resident.get("position", Vector2.ZERO) as Vector2,
	}


func _connection_anchor(endpoint: Dictionary) -> Dictionary:
	return ACTION_SUPPORT.connection_anchor(endpoint)


func _avatar_runtime(record: Dictionary) -> Dictionary:
	var state := record.get("worldState", {}) as Dictionary
	var pair := state.get("position", []) as Array
	return {
		"residentId": String(record.get("residentId", DEFAULT_PLAYER_AVATAR_ID)),
		"name": String(record.get("name", "")),
		"position": Vector2(float(pair[0]), float(pair[1])),
		"spaceId": String(state.get("spaceId", "")),
		"regionId": String(state.get("regionId", "")),
		"currentPlace": String(state.get("place", "")),
		"doing": String(state.get("doing", "")),
		"nearby": [],
		"conversationId": "",
		"conversation": null,
	}


# 字段派生逻辑在 RESIDENT_STATE_PROJECTION 子模块,与 town_hud 轻量投影共享(A2)。
func _resident_state_projection(resident: Dictionary) -> Dictionary:
	return RESIDENT_STATE_PROJECTION.project(self, resident)


# 表现状态通知的唯一发射口(docs/居民状态通知链减负方案.md C2):载荷为
# EMIT_KEYS 轻投影,发射条件与载荷语义只在这里定义。
func _emit_resident_state_changed(resident_ref: String) -> void:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		resident_state_changed.emit("", {})
		return
	var projected_state := RESIDENT_STATE_PROJECTION.project_emit(
		self,
		_residents[resident_id] as Dictionary,
	)
	resident_state_changed.emit(
		String(_resident_name_by_id.get(resident_id, "")),
		projected_state,
	)


# 感知模块读接口(F 之 2:12 共享符号去私有穿透;字典按引用返回,
# 感知侧的 nearby 就地更新语义不变)。
func environment() -> RefCounted:
	return _environment


func world_data() -> Dictionary:
	return _world_data


func residents() -> Dictionary:
	return _residents


func resident_order() -> Array:
	return _resident_order


func player_avatar() -> Dictionary:
	return _player_avatar


func player_avatar_present() -> bool:
	return _player_avatar_present


func resident_is_present(resident: Dictionary) -> bool:
	return _resident_is_present(resident)


func resident_display_name(resident_ref: String) -> String:
	return _resident_display_name(resident_ref)


func person_id_for_name(person_ref: String) -> String:
	return _person_id_for_name(person_ref)


func person_name_for_id(person_id: String) -> String:
	return _person_name_for_id(person_id)


func player_avatar_id() -> String:
	return _player_avatar_id()


func queue_world_event(resident_name: String, source: Dictionary) -> Dictionary:
	return _queue_world_event(resident_name, source)


func bump_world_revision(notify := true) -> void:
	_bump_world_revision(notify)


func _resident_is_present(resident: Dictionary) -> bool:
	var resident_id := String(resident.get("residentId", "")).strip_edges()
	if resident_id == _player_avatar_id():
		return _player_avatar_present
	if resident_id.is_empty() or not _resident_is_alive(resident_id):
		return false
	return (
		String(
			(
				resident.get("arrivalState", {}) as Dictionary
			).get("status", "arrived"),
		)
		== "arrived"
	)


func _resident_is_alive(resident_id: String) -> bool:
	return bool(_resident_lifecycle.is_alive(resident_id))


func _living_residents_for_staffing() -> Dictionary:
	var result := {}
	for resident_id: String in _resident_order:
		if _resident_is_alive(resident_id) and _residents.has(resident_id):
			result[resident_id] = _residents[resident_id]
	return result


func _public_current_action(action: Dictionary) -> Variant:
	return ACTION_PROJECTION_MODULE.public_current_action(action)


func _apply_resident_identities(prepared: Dictionary) -> void:
	_resident_id_by_name.clear()
	_resident_name_by_id.clear()
	var name_counts: Dictionary = {}
	for value: Variant in prepared.get("residents", []) as Array:
		var identity := value as Dictionary
		var resident_id := String(identity.get("residentId", ""))
		var resident_name := String(identity.get("residentName", ""))
		if resident_id.is_empty() or resident_name.is_empty():
			continue
		_resident_name_by_id[resident_id] = resident_name
		name_counts[resident_name] = int(name_counts.get(resident_name, 0)) + 1
		if int(name_counts[resident_name]) == 1:
			_resident_id_by_name[resident_name] = resident_id
		else:
			_resident_id_by_name.erase(resident_name)
	_resident_identity_status = String(prepared.get("status", "unavailable"))


func _player_avatar_id() -> String:
	var resident_id := String(_player_avatar.get("residentId", "")).strip_edges()
	return DEFAULT_PLAYER_AVATAR_ID if resident_id.is_empty() else resident_id


func _person_state(person_ref: String) -> Dictionary:
	var resident_id := _resident_key(person_ref)
	if not resident_id.is_empty():
		return _residents[resident_id] as Dictionary
	if person_ref in [_player_avatar_id(), String(_player_avatar.get("name", ""))]:
		return _player_avatar
	return {}


func _person_id_for_name(person_ref: String) -> String:
	var resident_id := _resident_key(person_ref)
	if not resident_id.is_empty():
		return resident_id
	if person_ref in [_player_avatar_id(), String(_player_avatar.get("name", ""))]:
		return _player_avatar_id()
	return ""


func _person_name_for_id(person_id: String) -> String:
	if _resident_name_by_id.has(person_id):
		return String(_resident_name_by_id[person_id])
	if person_id == _player_avatar_id():
		return String(_player_avatar.get("name", ""))
	return ""


func _resident_key(resident_ref: String) -> String:
	var normalized := resident_ref.strip_edges()
	if _residents.has(normalized):
		return normalized
	return String(_resident_id_by_name.get(normalized, ""))


func _resident_display_name(resident_ref: String) -> String:
	var resident_id := _resident_key(resident_ref)
	return String(_resident_name_by_id.get(resident_id, ""))


func _resident_is_waiting_for_active_onsite_service(
	resident_id: String,
) -> bool:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	var request_id := String(action.get("serviceRequestId", ""))
	if (
		String(action.get("type", "")) != "待着"
		or request_id.is_empty()
	):
		return false
	var request := _occupation_services.request(request_id,) as Dictionary
	return (
		String(request.get("state", ""))
		in ["pending", "waiting", "in_progress"]
		and String(
			(request.get("context", {}) as Dictionary).get(
				"customerServiceMode",
				"",
			),
		) == "onsite_wait"
	)


func _schedule_decision(
	resident_name: String,
	invalidate: bool,
	prefetch := false,
	allow_current_activity_interrupt := false,
	force_fresh := false,
	wake_while_current_action := false,
) -> void:
	var resident := _residents[resident_name] as Dictionary
	if not _resident_is_present(resident):
		return
	if (
		not force_fresh
		and _resident_is_completing_bound_clinic_work(resident_name, resident)
	):
		# 普通观察先留在队列里，不能每分钟重新决策并重启正在进行的诊疗。
		return
	if (
		not force_fresh
		and _resident_is_waiting_for_active_onsite_service(resident_name)
		and CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_name).is_empty()
	):
		if bool(resident.get("decisionPending", false)):
			_agent_wake_preparation_runtime.clear_resident(String(resident.get("residentId", resident_name)), String(resident.get("validDecisionId", "")))
			_restore_inflight_facts(resident)
			resident["decisionPending"] = false
			resident["validDecisionId"] = ""
			resident["pendingWake"] = {}
			resident["wakeDispatchQueued"] = false
		return
	var preview := resident.get("confirmedActionPreview", {}) as Dictionary
	if not preview.is_empty():
		if not allow_current_activity_interrupt:
			return
		_cancel_confirmed_action_preview_for_new_decision(
			resident_name,
			resident,
			preview,
		)
		if _resident_is_completing_bound_clinic_work(
			resident_name,
			resident,
		):
			return
	var current_action := resident.get("currentAction", {}) as Dictionary
	if DINING_SERVICE.keep_meal_routine_running(self, resident_name, current_action): return
	if (
		not current_action.is_empty()
		and not prefetch
		and not allow_current_activity_interrupt
		and not force_fresh
		and not wake_while_current_action
	):
		# 普通生活节奏和普通事件只留在队列里，当前活动完成后再统一唤醒。
		return
	var prefetched_decision := resident.get("prefetchedDecision", {}) as Dictionary
	if (
		bool(resident.get("decisionPending", false))
		and current_action.is_empty()
		and not prefetched_decision.is_empty()
	):
		_apply_prefetched_decision(resident_name)
		return
	if (
		invalidate
		and bool(resident.get("decisionPending", false))
		and current_action.is_empty()
		and bool(resident.get("decisionPrefetch", false))
	):
		# Keep the travelling response; a later urgent invalidation may discard it.
		return
	if invalidate and bool(resident.get("decisionPending", false)):
		_count_agent_request_metric("decisionInvalidated")
		_agent_wake_preparation_runtime.clear_resident(String(resident.get("residentId", resident_name)), String(resident.get("validDecisionId", "")))
		_restore_inflight_facts(resident)
		resident["decisionPending"] = false
		resident["validDecisionId"] = ""
		resident["pendingWake"] = {}
		resident["wakeDispatchQueued"] = false
		resident["decisionPrefetch"] = false
		resident["decisionMayInterruptCurrent"] = false
		resident["prefetchedDecision"] = {}
	if bool(resident.get("decisionPending", false)):
		return
	_count_agent_request_metric("decisionCreated")
	if (resident.get("currentAction", {}) as Dictionary).is_empty():
		_count_agent_request_metric("decisionPendingWithoutAction")
	if (
		int(resident.get("actionSuspendedAbsoluteMinute", -1)) >= 0
		and CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_name).is_empty()
	):
		_resume_suspended_action(resident)
	resident["decisionSequence"] = int(resident.get("decisionSequence", 0)) + 1
	var decision_id := "%s-g%d-%d" % [resident_name, _runtime_generation, int(resident["decisionSequence"])]
	var events := _deduplicated_world_events(
		(resident.get("eventQueue", []) as Array).duplicate(true),
	)
	var results := _deduplicated_action_results(
		(resident.get("resultQueue", []) as Array).duplicate(true),
	)
	(resident.get("eventQueue", []) as Array).clear()
	(resident.get("resultQueue", []) as Array).clear()
	resident["inflightEvents"] = events.duplicate(true)
	resident["inflightResults"] = results.duplicate(true)
	resident["validDecisionId"] = decision_id
	resident["decisionPending"] = true
	resident["decisionPrefetch"] = prefetch
	resident["decisionMayInterruptCurrent"] = (
		allow_current_activity_interrupt and not prefetch
	)
	resident["prefetchedDecision"] = {}
	# 排队阶段只保留决定编号和事实，不同步构造完整世界快照。事件先投影
	# 成 Gateway 可识别的公开形状，以便它在不展开快照的情况下排序对话。
	resident["pendingWake"] = {
		"decision_id": decision_id,
		"events": _agent_fact_payloads(events),
		"action_results": _agent_fact_payloads(results),
	}
	AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	resident["wakeDispatchQueued"] = true
	# A background reconsideration must not republish the unchanged visible
	# action phase. The presentation subscriber responds by pulling and applying
	# the resident's full state, so proximity events could synchronously repeat
	# that work for every moving resident in one world-minute frame. Residents
	# without a current action still publish the transition into thinking.
	if current_action.is_empty():
		resident_action_phase_changed.emit(
			resident_name,
			ACTION_PRESENTATION._resident_action_phase_projection(self, resident),
		)


func _apply_prefetched_decision(resident_id: String) -> void:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var decision := resident.get("prefetchedDecision", {}) as Dictionary
	if resident.is_empty() or decision.is_empty():
		return
	resident["prefetchedDecision"] = {}
	resident["decisionPrefetch"] = false
	# Preserve the decision envelope until the normal submission path consumes it.
	submit_agent_decision_by_id(resident_id, decision)


func _cancel_confirmed_action_preview_for_new_decision(
	resident_id: String,
	resident: Dictionary,
	preview: Dictionary,
) -> void:
	resident["confirmedActionPreview"] = {}
	_activate_confirmed_action(resident_id, resident, preview)


func _invalidate_all_pending_decisions() -> void:
	for resident_name in _resident_order:
		var resident := _residents[resident_name] as Dictionary
		if not bool(resident.get("decisionPending", false)):
			continue
		_count_agent_request_metric("decisionInvalidated")
		_agent_wake_preparation_runtime.clear_resident(String(resident.get("residentId", resident_name)), String(resident.get("validDecisionId", "")))
		_restore_inflight_facts(resident)
		resident["decisionPending"] = false
		resident["validDecisionId"] = ""
		resident["pendingWake"] = {}
		resident["wakeDispatchQueued"] = false
		resident["decisionPrefetch"] = false
		resident["decisionMayInterruptCurrent"] = false
		resident["prefetchedDecision"] = {}


func _restore_inflight_facts(resident: Dictionary) -> void:
	var events := (resident.get("inflightEvents", []) as Array).duplicate(true)
	events.append_array(resident.get("eventQueue", []) as Array)
	resident["eventQueue"] = _deduplicated_world_events(events)
	var results := (resident.get("inflightResults", []) as Array).duplicate(true)
	results.append_array(resident.get("resultQueue", []) as Array)
	resident["resultQueue"] = _deduplicated_action_results(results)
	resident["inflightEvents"] = []
	resident["inflightResults"] = []


func _deduplicated_world_events(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen_event_ids := {}
	var coalesced_indexes := {}
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var event := value as Dictionary
		var event_id := String(event.get("event_id", "")).strip_edges()
		if not event_id.is_empty() and seen_event_ids.has(event_id):
			continue
		if not event_id.is_empty():
			seen_event_ids[event_id] = true
		var coalescing_key := _world_event_coalescing_key(event)
		if (
			not coalescing_key.is_empty()
			and coalesced_indexes.has(coalescing_key)
		):
			# 同一件尚未处理的事实只保留最新版本；这是去重，不是
			# 丢弃，仍然会随待办队列一起保存并在下一次唤醒中交付。
			result[int(coalesced_indexes[coalescing_key])] = event.duplicate(true)
			continue
		if not coalescing_key.is_empty():
			coalesced_indexes[coalescing_key] = result.size()
		result.append(event.duplicate(true))
	return result


func _world_event_coalescing_key(event: Dictionary) -> String:
	var event_type := String(event.get("type", ""))
	match event_type:
		"天气变了":
			return "天气变了|%s" % String(event.get("weather", ""))
		"公告发布":
			return "公告发布|%s" % String(event.get("announcement_id", ""))
		"公告到点":
			return "公告到点|%s" % String(event.get("announcement_id", ""))
		"钟声公告":
			return "钟声公告|%s" % String(event.get("announcement_id", ""))
		"公告阅读":
			return "公告阅读|%s" % String(event.get("announcement_id", ""))
		"公告转告":
			return "公告转告|%s|%s" % [
				String(event.get("announcement_id", "")),
				String(event.get("speaker_resident_id", "")),
			]
		"正式通知送达":
			return "正式通知送达|%s" % String(event.get("message_id", ""))
		"营业状态变化":
			return "营业状态变化|%s|%s" % [
				String(event.get("place_id", "")),
				"1" if bool(event.get("open", false)) else "0",
			]
		"承诺条件变化":
			return "承诺条件变化|%s" % String(
				event.get("commitment_action_id", "")
			)
		"冲突见闻":
			return "冲突见闻|%s" % String(
				event.get("conflict_event_id", event.get("conflict_id", ""))
			)
		"身体状况变化":
			return "身体状况变化|%s|%s|%s" % [
				String(event.get("eventId", "")),
				String(event.get("conditionId", "")),
				String(event.get("state", "")),
			]
		_:
			return ""


func _append_pending_world_event(resident: Dictionary, event: Dictionary) -> void:
	var event_id := String(event.get("event_id", "")).strip_edges()
	var coalescing_key := _world_event_coalescing_key(event)
	var queue := resident.get("eventQueue", []) as Array
	for value: Variant in (resident.get("inflightEvents", []) as Array):
		if not value is Dictionary:
			continue
		var existing := value as Dictionary
		if (
			not event_id.is_empty()
			and String(existing.get("event_id", "")).strip_edges() == event_id
		):
			return
		if (
			not coalescing_key.is_empty()
			and _world_event_coalescing_key(existing) == coalescing_key
		):
			# 当前请求已经带走旧版本，新版本留在下一次请求中。
			break
	for index in queue.size():
		var existing_value: Variant = queue[index]
		if not existing_value is Dictionary:
			continue
		var existing := existing_value as Dictionary
		if (
			(not event_id.is_empty()
			and String(existing.get("event_id", "")).strip_edges() == event_id)
			or (
				not coalescing_key.is_empty()
			and _world_event_coalescing_key(existing) == coalescing_key
			)
		):
			queue[index] = event.duplicate(true)
			return
	queue.append(event.duplicate(true))


func _consume_valid_request(resident: Dictionary) -> void:
	ACTION_SUPPORT.consume_valid_request(resident)


func _prepare_action(
	resident: Dictionary,
	action: Dictionary,
	allow_used_action_id := false,
	issued_snapshot: Dictionary = {},
	allow_closed_clinic_for_injury := false,
) -> Dictionary:
	var shape_error := _validate_action_shape(action)
	if not shape_error.is_empty():
		return {"ok": false, "errors": [shape_error]}
	var action_id := (action.get("action_id") as String).strip_edges()
	if action_id.is_empty():
		return {"ok": false, "errors": ["动作 action_id 不能为空"]}
	if (
		not allow_used_action_id
		and (resident.get("usedActionIds", {}) as Dictionary).has(action_id)
	):
		return {"ok": false, "errors": ["动作 action_id 已被该居民使用：%s" % action_id]}
	var action_type := (action.get("type") as String).strip_edges()
	if (
		action_type in [
			"去",
			"用道具",
			"做活动",
			"调整营业",
			"托人传话",
			"待着",
		]
		and String(action.get("line", "")).strip_edges().is_empty()
	):
		return {"ok": false, "errors": ["%s 动作必须包含非空 line" % action_type]}
	match action_type:
		"去":
			return _prepare_go_action(
				resident,
				action,
				allow_closed_clinic_for_injury,
			)
		"用道具":
			return {
				"ok": false,
				"errors": [
					"旧用道具动作必须经唯一 activity.perform 映射，不能直达 prop 路径"
				],
			}
		"做活动":
			return {
				"ok": false,
				"errors": [
					"做活动必须经 activity.perform 入口执行"
				],
			}
		"调整营业":
			var place_id := String(
				action.get("place_id", "")
			).strip_edges()
			var control := _service_control_for_resident(resident)
			if (
				not action.get("open") is bool
				or place_id.is_empty()
				or control.is_empty()
				or String(control.get("place_id", "")) != place_id
				or bool(control.get("open", false))
				== bool(action.get("open", false))
			):
				return {
					"ok": false,
					"errors": ["本人当前不能这样改变营业状态"],
				}
			var prepared_service := action.duplicate(true)
			var service_now := int(
				_environment.get_absolute_minute()
			)
			prepared_service["startedAbsoluteMinute"] = service_now
			prepared_service["completeAbsoluteMinute"] = service_now + 1
			return {"ok": true, "action": prepared_service}
		"托人传话":
			var recipient_id := String(
				action.get("recipient_resident_id", ""),
			).strip_edges()
			var content := String(action.get("content", "")).strip_edges()
			var sender_id := String(resident.get("residentId", ""))
			if (
				recipient_id.is_empty()
				or recipient_id == sender_id
				or not _residents.has(recipient_id)
				or content.is_empty()
				or content.length() > 240
			):
				return {
					"ok": false,
					"errors": ["传话必须指定另一位真实居民和有效口信"],
				}
			var pending_from_sender := 0
			for message_value: Variant in _private_messages.values():
				var message := message_value as Dictionary
				if (
					String(message.get("senderResidentId", ""))
					== sender_id
					and String(message.get("state", "")) == "pending"
				):
					pending_from_sender += 1
			if pending_from_sender >= 2:
				return {
					"ok": false,
					"errors": ["已有口信在等待投递，先不要重复托付"],
				}
			var prepared_message := action.duplicate(true)
			var message_now := int(
				_environment.get_absolute_minute(),
			)
			prepared_message["startedAbsoluteMinute"] = message_now
			prepared_message["completeAbsoluteMinute"] = message_now + 1
			return {"ok": true, "action": prepared_message}
		"搭话":
			return _prepare_talk_action(String(resident.get("residentId", "")), resident, action)
		"答话":
			return _prepare_reply_action(String(resident.get("residentId", "")), action)
		"争执", "攻击", "回应冲突", "介入冲突", "离开冲突":
			if _conflict_agent_world_bridge == null:
				return {"ok": false, "errors": ["冲突系统尚未准备好"]}
			var conflict_preparation := _conflict_agent_world_bridge.prepare_action(String(resident.get("residentId", "")),
				action,
				issued_snapshot,) as Dictionary
			if conflict_preparation.get("ok") != true:
				return {
					"ok": false,
					"errors": [TownConflictAgentWorldBridge.action_error_text(String(
						conflict_preparation.get(
							"errorCode",
							"CONFLICT_ACTION_REJECTED",
						)
					))],
				}
			return conflict_preparation
		"待着":
			var prepared := action.duplicate(true)
			var started_absolute_minute := int(
				_environment.get_absolute_minute()
			)
			var wait_cap_minutes := (
				CONTINUITY_WAIT_MAX_MINUTES
				if _is_continuity_wait_action(prepared)
				else WAIT_ACTION_MAX_MINUTES
			)
			prepared["startedAbsoluteMinute"] = started_absolute_minute
			prepared["completeAbsoluteMinute"] = (
				started_absolute_minute
				+ mini(
					int(_environment.minutes_until_next_period()),
					wait_cap_minutes,
				)
			)
			DINING_SERVICE.cap_full_wait(self, resident, prepared)
			if _resident_has_current_animal_wait_assignment(
				String(resident.get("residentId", "")),
				prepared,
			):
				return {"ok": true, "action": prepared}
			var wait_probe_usec := WORLD_PERFORMANCE_PROBE.start_lap()
			var parking_attached := _attach_idle_parking_route(resident, prepared)
			wait_probe_usec = WORLD_PERFORMANCE_PROBE.record_lap(wait_probe_usec, "wait_parking")
			# 室内工作点暂时拥挤时，保留“待着”比把居民改成随机公共地点
			# 的“去”更稳定。后者会先经过建筑门口，看起来像碰撞后专门去
			# 门口逛；下一次决定仍会重新选择可用的室内站位。
			if (
				not parking_attached
				and String(resident.get("spaceId", "")) == "town_outdoor"
			):
				var departure := _prepare_idle_departure_action(
					resident,
					prepared,
				)
				WORLD_PERFORMANCE_PROBE.record_lap(wait_probe_usec, "wait_departure")
				if departure.get("ok") == true:
					return departure
			return {"ok": true, "action": prepared}
		_:
			return {"ok": false, "errors": ["当前运行层尚未接入动作类型：%s" % action.get("type", "")]}


func _attach_idle_parking_route(
	resident: Dictionary,
	prepared: Dictionary,
) -> bool:
	var space_id := String(resident.get("spaceId", ""))
	if space_id.is_empty():
		return true
	var portals := _portal_positions_for_space(space_id)
	var current_position := resident.get("position", Vector2.ZERO) as Vector2
	var near_portal := false
	for portal in portals:
		if current_position.distance_to(portal) <= IDLE_PORTAL_TRIGGER_DISTANCE_PX:
			near_portal = true
			break
	var occupied := _resident_idle_occupied_positions(
		String(resident.get("residentId", "")),
		space_id,
	)
	var crowded := _point_near_any(
		current_position,
		occupied,
		IDLE_RESIDENT_CLEARANCE_PX,
	)
	if not near_portal and not crowded:
		return true
	var candidates: Array[Dictionary] = []
	if space_id == "town_outdoor":
		candidates = _outdoor_idle_parking_candidates(
			current_position,
			portals,
			occupied,
		)
	else:
		candidates = CHARACTER_MOVEMENT_QUERY.indoor_idle_parking_candidates(
			_indoor_navigation_for_space(space_id),
			current_position,
			portals,
			occupied,
		) as Array[Dictionary]
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score := float(left.get("score", INF))
		var right_score := float(right.get("score", INF))
		if not is_equal_approx(left_score, right_score):
			return left_score < right_score
		var left_position := left.get("position", Vector2.ZERO) as Vector2
		var right_position := right.get("position", Vector2.ZERO) as Vector2
		return (
			left_position.y < right_position.y
			or (
				is_equal_approx(left_position.y, right_position.y)
				and left_position.x < right_position.x
			)
		)
	)
	var selected := candidates[0]
	var path_points: Array[Vector2] = []
	path_points.assign(selected.get("path", []) as Array)
	var move_duration := _movement_duration_for_path(path_points)
	prepared["idlePathPoints"] = path_points
	prepared["idleTargetPosition"] = selected.get(
		"position",
		current_position,
	) as Vector2
	prepared["idleMoveDurationMinutes"] = move_duration
	prepared["completeAbsoluteMinute"] = maxi(
		int(prepared.get("completeAbsoluteMinute", 0)),
		int(prepared.get("startedAbsoluteMinute", 0)) + move_duration + 1,
	)
	return true


func _prepare_idle_departure_action(
	resident: Dictionary,
	prepared_wait: Dictionary,
) -> Dictionary:
	var current_place := String(resident.get("currentPlace", ""))
	var target_places: Array[String] = []
	for value: Variant in _world_data.get("places", []) as Array:
		var place := value as Dictionary
		var target_place := String(place.get("name", ""))
		if (
			target_place.is_empty()
			or target_place == current_place
			or String(place.get("type", "")) != "公共地点"
		):
			continue
		target_places.append(target_place)
	if target_places.is_empty():
		return {}
	target_places.sort()
	var rotation := posmod(
		hash(
			"%s:%s" % [
				String(resident.get("residentId", "")),
				current_place,
			]
		),
		target_places.size(),
	)
	var candidate_count := mini(
		target_places.size(),
		IDLE_DEPARTURE_PLACE_CANDIDATE_LIMIT,
	)
	for offset in candidate_count:
		var target_place := target_places[
			(rotation + offset) % target_places.size()
		]
		var go_action := {
			"action_id": String(
				prepared_wait.get("action_id", "")
			),
			"type": "去",
			"place": target_place,
			"line": (
				"%s；这里暂时没有空位，先去%s"
				% [
					String(prepared_wait.get("line", "")),
					target_place,
				]
			),
		}
		var preparation := _prepare_go_action(resident, go_action)
		if preparation.get("ok") == true:
			return preparation
	return {}


func _outdoor_idle_parking_candidates(
	current_position: Vector2,
	portals: Array[Vector2],
	occupied: Array[Vector2],
) -> Array[Dictionary]:
	return CHARACTER_MOVEMENT_QUERY.outdoor_idle_parking_candidates(
		_world_data.get("movementNetwork", {}) as Dictionary,
		current_position,
		portals,
		occupied,
	) as Array[Dictionary]


func _vector_path_from_payload(values: Array) -> Array[Vector2]:
	return ACTION_GEOMETRY.vector_path_from_payload(values)


func _polyline_distance(points: Array[Vector2]) -> float:
	return ACTION_GEOMETRY.polyline_distance(points)


func _polyline_prefix(
	points: Array[Vector2],
	target_distance: float,
) -> Array[Vector2]:
	return ACTION_GEOMETRY.polyline_prefix(points, target_distance)


func _indoor_navigation_for_space(space_id: String) -> Dictionary:
	return ACTION_GEOMETRY.indoor_navigation_for_space(self, space_id)


func _portal_positions_for_space(space_id: String) -> Array[Vector2]:
	return ACTION_GEOMETRY.portal_positions_for_space(self, space_id)


func _resident_idle_occupied_positions(
	resident_id: String,
	space_id: String,
) -> Array[Vector2]:
	return ACTION_GEOMETRY.resident_idle_occupied_positions(self, resident_id, space_id)


func _point_near_any(
	point: Vector2,
	others: Array[Vector2],
	clearance: float,
) -> bool:
	return ACTION_GEOMETRY.point_near_any(point, others, clearance)


func _movement_duration_for_path(points: Array[Vector2]) -> int:
	return ACTION_GEOMETRY.movement_duration_for_path(self, points)


func _is_continuity_wait_action(action: Dictionary) -> bool:
	return ACTION_VALIDATION.is_continuity_wait_action(action)


func _reject_invalid_action(
	resident_name: String,
	resident: Dictionary,
	action: Dictionary,
	reason: String,
) -> Dictionary:
	var fingerprint := _invalid_action_fingerprint(action, reason)
	var previous_fingerprint := String(
		resident.get("lastRejectedActionFingerprint", "")
	)
	var repeat_count := (
		int(resident.get("consecutiveRejectedActionCount", 0)) + 1
		if fingerprint == previous_fingerprint
		else 1
	)
	resident["lastRejectedActionFingerprint"] = fingerprint
	resident["consecutiveRejectedActionCount"] = repeat_count
	var rejected_action_id := (
		String(action.get("action_id", "")).strip_edges()
		if action.get("action_id") is String
		else ""
	)
	var used_action_ids := resident.get("usedActionIds", {}) as Dictionary
	if rejected_action_id.is_empty() or used_action_ids.has(rejected_action_id):
		_schedule_decision(resident_name, false)
	else:
		used_action_ids[rejected_action_id] = true
		_queue_action_result(
			resident_name,
			rejected_action_id,
			"rejected",
			reason,
			true,
			not (
				repeat_count >= 2
				and String(action.get("type", "")) == "搭话"
			),
			ACTION_PRESENTATION._preview_action_presentation(self, resident, {"action": action}),
		)
	return {"ok": false, "stale": false, "errors": [reason]}


func _invalid_action_fingerprint(action: Dictionary, reason: String) -> String:
	return ACTION_VALIDATION.invalid_action_fingerprint(action, reason)


func _clear_rejected_action_streak(resident: Dictionary) -> void:
	ACTION_VALIDATION.clear_rejected_action_streak(resident)


func _validate_decision_shape(
	decision: Dictionary,
	inflight_events: Array = [],
	inflight_results: Array = [],
) -> String:
	return ACTION_VALIDATION.validate_decision_shape(decision, inflight_events, inflight_results)


func _validate_conversation_follow_up_shape(value: Variant) -> String:
	return ACTION_VALIDATION.validate_conversation_follow_up_shape(value)


func _accepted_conversation_follow_up(
	decision: Dictionary,
	wake_packet: Dictionary,
) -> Dictionary:
	if (
		_validate_conversation_follow_up_shape(
			decision.get("conversation_follow_up"),
		) != ""
		or decision.get("action") is not Dictionary
		or String((decision.get("action") as Dictionary).get("type", "")) != "答话"
	):
		return {}
	var option_id := String(
		(decision.get("conversation_follow_up") as Dictionary).get("option_id", ""),
	).strip_edges()
	for value: Variant in (
		(wake_packet.get("snapshot", {}) as Dictionary).get(
			"conversation_follow_up_options",
			[],
		) as Array
	):
		if value is not Dictionary:
			continue
		var option := value as Dictionary
		if String(option.get("option_id", "")) != option_id:
			continue
		if option.has("integrity_key"):
			var goal_result := _action_options.action_goal_from_option(option,) as Dictionary
			if goal_result.get("ok") != true:
				continue
		return option.duplicate(true)
	return {}


func _validate_reaction_shape(
	value: Variant,
	inflight_events: Array,
	inflight_results: Array,
) -> String:
	return ACTION_VALIDATION.validate_reaction_shape(value, inflight_events, inflight_results)


func _inflight_requires_reply(events: Array) -> bool:
	return ACTION_VALIDATION.inflight_requires_reply(events)


func _reaction_source_action_id(results: Array) -> String:
	return ACTION_VALIDATION.reaction_source_action_id(results)


func _emit_resident_reaction(
	resident_id: String,
	decision_id: String,
	reaction: Dictionary,
	announcement_reactions: Array = [],
	inflight_events: Array = [],
	inflight_results: Array = [],
) -> void:
	ANNOUNCEMENT_RESIDENT_RUNTIME.emit_reactions(
		self,
		resident_id,
		decision_id,
		reaction,
		announcement_reactions,
		inflight_events,
		inflight_results,
	)


func _validate_action_shape(action: Dictionary) -> String:
	return ACTION_VALIDATION.validate_action_shape(action)


func _require_action_texts(action: Dictionary, fields: Array[String], action_type: String) -> String:
	return ACTION_VALIDATION.require_action_texts(action, fields, action_type)


func _prepare_go_action(
	resident: Dictionary,
	action: Dictionary,
	allow_closed_clinic_for_injury := false,
) -> Dictionary:
	var from_place := String(resident.get("currentPlace", ""))
	var target_place := String(action.get("place", "")).strip_edges()
	if target_place.is_empty() or target_place == from_place:
		return {"ok": false, "errors": ["目标地点必须存在且不同于当前地点"]}
	if (
		_closed_service_place_for_visitor(resident, target_place)
		and not (
			allow_closed_clinic_for_injury
			and target_place == CONTENT_CATALOG.PLACE_CLINIC
		)
	):
		return {
			"ok": false,
			"errors": ["%s今天没有营业，不能进去" % target_place],
		}
	var dining_failure := DINING_SERVICE.go_admission_failure(self, resident, target_place, int(_environment.get_absolute_minute()))
	if not dining_failure.is_empty(): return dining_failure
	var route := ROUTE_QUERY.find_route_from_state(
		_world_data,
		{
			"position": resident.get("position", Vector2.ZERO),
			"spaceId": resident.get("spaceId", ""),
			"regionId": resident.get("regionId", ""),
			"currentPlace": from_place,
		},
		target_place,
		resident.get("routeConnector", []) as Array,
	) as Dictionary
	if route.is_empty():
		return {"ok": false, "errors": ["当前没有从 %s 到 %s 的固定路线" % [from_place, target_place]]}
	var prepared := action.duplicate(true)
	prepared["startedAbsoluteMinute"] = int(_environment.get_absolute_minute())
	prepared["durationMinutes"] = int(route.get("durationMinutes", 0))
	prepared["route"] = route.duplicate(true)
	prepared["completionEffects"] = (
		route.get("completionEffects", route.get("effects", {})) as Dictionary
	).duplicate(true)
	prepared["consumeRouteConnector"] = not (resident.get("routeConnector", []) as Array).is_empty()
	return {"ok": true, "action": prepared}


func _prepare_prop_action(resident: Dictionary, action: Dictionary) -> Dictionary:
	var path: Array[Vector2] = [resident.get("position", Vector2.ZERO) as Vector2]
	for point_value: Variant in resident.get("routeConnector", []) as Array:
		var connector_point := point_value as Vector2
		if not path[-1].is_equal_approx(connector_point):
			path.append(connector_point)
	var plan := PROP_QUERY.interaction_plan(
		_prop_query_data(),
		String(resident.get("currentPlace", "")),
		String(action.get("prop", "")),
		String(action.get("verb", "")),
		path[-1],
	) as Dictionary
	if plan.is_empty():
		return {"ok": false, "errors": ["当前地点没有这个可用道具或动作词"]}
	if String(plan.get("spaceId", "")) != String(resident.get("spaceId", "")):
		return {"ok": false, "errors": ["道具与居民不在同一个地图空间"]}
	for point_value: Variant in plan.get("approachPolyline", []) as Array:
		var point := point_value as Vector2
		if not path[-1].is_equal_approx(point):
			path.append(point)
	var prepared := action.duplicate(true)
	prepared["startedAbsoluteMinute"] = int(_environment.get_absolute_minute())
	prepared["sourcePlace"] = String(resident.get("currentPlace", ""))
	prepared["durationMinutes"] = int(plan.get("durationMinutes", 0))
	prepared["pathPoints"] = path
	prepared["effects"] = (plan.get("effects", {}) as Dictionary).duplicate(true)
	prepared["targetPosition"] = plan.get("position", resident.get("position", Vector2.ZERO)) as Vector2
	prepared["dynamicPropId"] = String(plan.get("propId", ""))
	var return_connector := (plan.get("approachPolyline", []) as Array).duplicate()
	return_connector.reverse()
	prepared["returnRouteConnector"] = return_connector
	prepared["consumeRouteConnector"] = not (resident.get("routeConnector", []) as Array).is_empty()
	if not _prepared_same_space_action_route_errors(
		resident,
		prepared,
	).is_empty():
		return {
			"ok": false,
			"errors": ["当前没有到这个道具的安全路线"],
		}
	prepared["pathClearanceVerified"] = true
	return {"ok": true, "action": prepared}


func _is_dynamic_prop_action(
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	var prop_name := String(action.get("prop", "")).strip_edges()
	var action_verb := String(action.get("verb", "")).strip_edges()
	var place_name := String(resident.get("currentPlace", ""))
	if prop_name.is_empty() or action_verb.is_empty():
		return false
	for prop_value: Variant in _dynamic_props.values():
		var prop := prop_value as Dictionary
		if (
			String(prop.get("name", "")) != prop_name
			or String(prop.get("placeName", "")) != place_name
		):
			continue
		for action_value: Variant in prop.get("actions", []) as Array:
			if (
				action_value is Dictionary
				and String((action_value as Dictionary).get("verb", ""))
				== action_verb
			):
				return true
	return false


func _is_layout_override_prop_action(
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	if not _indoor_layout_overrides.has(
		String(resident.get("spaceId", ""))
	):
		return false
	return not PROP_QUERY.action_definition(
		_prop_query_data(),
		String(resident.get("currentPlace", "")),
		String(action.get("prop", "")).strip_edges(),
		String(action.get("verb", "")).strip_edges(),
	).is_empty()


func _direct_prop_action_available(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	return ACTION_SUPPORT.direct_prop_action_available(self, resident_id, resident, action)


func _preflight_activity_candidates(
	resident: Dictionary,
	validated: Dictionary,
) -> Dictionary:
	var candidates := validated.get("candidates", []) as Array
	var candidates_to_try: Array = []
	var has_region_candidates := candidates.any(
		func(value: Variant) -> bool:
			return (
				value is Dictionary
				and String(
					(value as Dictionary).get("targetType", ""),
				) == "region"
			)
	)
	if has_region_candidates:
		candidates_to_try = candidates.duplicate()
		if candidates_to_try.size() > 1:
			var rotation := posmod(
				hash(
					"%s:%s"
					% [
						String(validated.get("residentId", "")),
						String(validated.get("actionId", "")),
					]
				),
				candidates_to_try.size(),
			)
			candidates_to_try = (
				candidates_to_try.slice(rotation)
				+ candidates_to_try.slice(0, rotation)
			)
	elif bool(validated.get("preferredRequested", false)):
		candidates_to_try = candidates.slice(0, mini(2, candidates.size()))
	else:
		for candidate_value: Variant in candidates:
			var candidate := candidate_value as Dictionary
			if bool(candidate.get("memberAvailable", false)):
				candidates_to_try.append(candidate)
				break
	if candidates_to_try.is_empty():
		return {
			"ok": false,
			"errorCode": "ACTIVITY_RESERVATION_CONFLICT",
			"retryable": true,
			"errors": ["当前活动的确定性 slot/member 已被预约"],
		}
	# 活动列表生成唤醒包时已经为“可做”候选跑过一次正式寻路。同一游戏
	# 分钟、同一居民位置下，优先复用那条已经验证过的路线，避免模型结果
	# 返回时再次扫描整张路网。预约可用性和区域占用仍以本次 validated 为准。
	var cached_candidates: Array = []
	var uncached_candidates: Array = []
	for candidate_value: Variant in candidates_to_try:
		var candidate := candidate_value as Dictionary
		if _activity_cached_prepared_action(resident, candidate).is_empty():
			uncached_candidates.append(candidate)
		else:
			cached_candidates.append(candidate)
	if not cached_candidates.is_empty():
		candidates_to_try = cached_candidates + uncached_candidates
	var has_available_candidate := false
	for candidate_value: Variant in candidates_to_try:
		if bool((candidate_value as Dictionary).get("memberAvailable", false)):
			has_available_candidate = true
			break
	if not has_available_candidate:
		return {
			"ok": false,
			"errorCode": "ACTIVITY_RESERVATION_CONFLICT",
			"retryable": true,
			"errors": ["当前活动的确定性 slot/member 已被预约"],
		}
	var target_unreachable := false
	for candidate_value: Variant in candidates_to_try:
		var candidate := candidate_value as Dictionary
		if not bool(candidate.get("memberAvailable", false)):
			continue
		if (
			String(candidate.get("targetType", "")) == "region"
			and _region_activity_position_occupied(
				String(validated.get("residentId", "")),
				candidate.get("memberPosition", []) as Array,
			)
		):
			continue
		var action := {
			"action_id": String(validated.get("actionId", "")),
			"type": "用道具",
			"prop": String(candidate.get("targetPropName", "")),
			"verb": String(candidate.get("targetActionVerb", "")),
			"line": String(validated.get("activityLabel", "")),
		}
		var cached_action := _activity_cached_prepared_action(
			resident,
			candidate,
		)
		var prepared := {}
		if cached_action.is_empty():
			prepared = (
				_prepare_region_activity_action(
					resident,
					action,
					candidate,
				)
				if String(candidate.get("targetType", "")) == "region"
				else _prepare_prop_action(resident, action)
			)
		else:
			cached_action["action_id"] = String(validated.get("actionId", ""))
			cached_action["type"] = "用道具"
			cached_action["prop"] = String(candidate.get("targetPropName", ""))
			cached_action["verb"] = String(candidate.get("targetActionVerb", ""))
			cached_action["line"] = String(validated.get("activityLabel", ""))
			prepared = {"ok": true, "action": cached_action}
		if prepared.get("ok") != true:
			target_unreachable = true
			continue
		var prepared_action := prepared.get("action", {}) as Dictionary
		var member_position := candidate.get("memberPosition", []) as Array
		if member_position.size() != 2:
			continue
		var expected := Vector2(
			float(member_position[0]),
			float(member_position[1]),
		)
		if not (
			prepared_action.get("targetPosition", Vector2.ZERO) as Vector2
		).is_equal_approx(expected) and not _is_layout_override_prop_action(
			resident,
			action,
		):
			continue
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"slotId": String(candidate.get("slotId", "")),
			"memberAnchorId": String(
				candidate.get("memberAnchorId", "")
			),
			"action": prepared_action.duplicate(true),
		}
	return {
		"ok": false,
		"errorCode": (
			"ACTIVITY_TARGET_UNREACHABLE"
			if target_unreachable
			else "ACTIVITY_SLOT_REFERENCE_INVALID"
		),
		"retryable": target_unreachable,
		"errors": [
			(
				"活动目标当前不可到达"
				if target_unreachable
				else "活动 slot/member 与权威 prop anchor 不一致"
			)
		],
	}


func _activity_query_candidate_reachable(
	resident: Dictionary,
	candidate: Dictionary,
	activity_label: String,
	reachability_memo: Dictionary = {},
) -> bool:
	var member_position := candidate.get("memberPosition", []) as Array
	if member_position.size() != 2:
		return false
	# memo 键以目标为准：同一次 query_activity_options 调用里居民原点
	# 不变，候选落在同一区域/道具上的可达性结论可以直接复用，
	# 不必为每个活动选项重复跑整张路网的寻路。
	var memo_key := _activity_candidate_memo_key(candidate)
	if reachability_memo.has(memo_key):
		return bool(reachability_memo[memo_key])
	_ensure_activity_reachability_cache_minute()
	var cache_key := _activity_candidate_cache_key(resident, candidate)
	if _activity_reachability_cache.has(cache_key):
		return bool(_activity_reachability_cache[cache_key])
	var action := {
		"action_id": "activity-query-preflight",
		"type": "用道具",
		"prop": String(candidate.get("targetPropName", "")),
		"verb": String(candidate.get("targetActionVerb", "")),
		"line": activity_label,
	}
	var route_probe_started_usec := (
		Time.get_ticks_usec() if _frame_probe != null else 0
	)
	var prepared := (
		_prepare_region_activity_action(
			resident,
			action,
			candidate,
		)
		if String(candidate.get("targetType", "")) == "region"
		else _prepare_prop_action(resident, action)
	)
	if _frame_probe != null:
		_take_probe_lap(
			"agentActivityQueryRouteUsec",
			route_probe_started_usec,
		)
		_frame_probe.record(
			Engine.get_process_frames(),
			"agentActivityQueryRouteCount",
			1,
		)
	if prepared.get("ok") != true:
		reachability_memo[memo_key] = false
		_activity_reachability_cache[cache_key] = false
		return false
	var prepared_action := prepared.get("action", {}) as Dictionary
	var expected := Vector2(
		float(member_position[0]),
		float(member_position[1]),
	)
	var reachable := (
		prepared_action.get("targetPosition", Vector2.ZERO) as Vector2
	).is_equal_approx(expected) or _is_layout_override_prop_action(
		resident,
		{
			"prop": String(candidate.get("targetPropName", "")),
			"verb": String(candidate.get("targetActionVerb", "")),
		},
	)
	reachability_memo[memo_key] = reachable
	_activity_reachability_cache[cache_key] = reachable
	if reachable:
		_activity_prepared_action_cache[cache_key] = prepared_action.duplicate(true)
	return reachable


func _ensure_activity_reachability_cache_minute() -> void:
	var cache_minute := int(_environment.get_absolute_minute())
	if cache_minute == _activity_reachability_cache_minute:
		return
	_activity_reachability_cache.clear()
	_activity_prepared_action_cache.clear()
	_activity_reachability_cache_minute = cache_minute


func _activity_candidate_memo_key(candidate: Dictionary) -> String:
	var member_position := candidate.get("memberPosition", []) as Array
	return "%s|%s|%s|%s|%s,%s" % [
		String(candidate.get("targetType", "")),
		String(candidate.get("targetRegionId", "")),
		String(candidate.get("targetPropName", "")),
		String(candidate.get("targetActionVerb", "")),
		str(member_position[0]) if member_position.size() == 2 else "",
		str(member_position[1]) if member_position.size() == 2 else "",
	]


func _activity_candidate_cache_key(
	resident: Dictionary,
	candidate: Dictionary,
) -> String:
	var origin := resident.get("position", Vector2.ZERO) as Vector2
	return "%s|%s|%s|%d,%d|%s|%s" % [
		String(resident.get("residentId", "")),
		String(resident.get("spaceId", "")),
		String(resident.get("currentPlace", "")),
		int(round(origin.x)),
		int(round(origin.y)),
		str(resident.get("routeConnector", []) as Array),
		_activity_candidate_memo_key(candidate),
	]


func _activity_cached_prepared_action(
	resident: Dictionary,
	candidate: Dictionary,
) -> Dictionary:
	if int(_environment.get_absolute_minute()) != _activity_reachability_cache_minute:
		return {}
	var cached := _activity_prepared_action_cache.get(
		_activity_candidate_cache_key(resident, candidate),
		{},
	) as Dictionary
	return cached.duplicate(true)


func _prepare_region_activity_action(
	resident: Dictionary,
	action: Dictionary,
	candidate: Dictionary,
) -> Dictionary:
	var position_value := candidate.get("memberPosition", []) as Array
	var region_id := String(candidate.get("targetRegionId", ""))
	if position_value.size() != 2 or region_id.is_empty():
		return {"ok": false, "errors": ["活动区域没有可用落点"]}
	var target_position := Vector2(
		float(position_value[0]),
		float(position_value[1]),
	)
	var route := ROUTE_QUERY.find_route_to_outdoor_position(
		_world_data,
		{
			"position": resident.get("position", Vector2.ZERO),
			"spaceId": resident.get("spaceId", ""),
			"regionId": resident.get("regionId", ""),
			"currentPlace": resident.get("currentPlace", ""),
		},
		target_position,
		region_id,
		resident.get("routeConnector", []) as Array,
	) as Dictionary
	if route.is_empty():
		return {"ok": false, "errors": ["当前没有到这个活动区域落点的合法路线"]}
	var path: Array[Vector2] = []
	for segment_value: Variant in route.get("segments", []) as Array:
		if not segment_value is Dictionary:
			return {"ok": false, "errors": ["活动区域路线数据无效"]}
		var segment := segment_value as Dictionary
		if String(segment.get("kind", "")) != "route_edge":
			return {"ok": false, "errors": ["活动区域路线不能跨地图空间"]}
		for point_value: Variant in segment.get("polyline", []) as Array:
			if not point_value is Dictionary:
				return {"ok": false, "errors": ["活动区域路线坐标无效"]}
			var point := point_value as Dictionary
			var vector := Vector2(
				float(point.get("x", 0.0)),
				float(point.get("y", 0.0)),
			)
			if path.is_empty() or not path[-1].is_equal_approx(vector):
				path.append(vector)
	if path.is_empty():
		path.append(resident.get("position", Vector2.ZERO) as Vector2)
	if not path[-1].is_equal_approx(target_position):
		path.append(target_position)
	var prepared := action.duplicate(true)
	prepared["startedAbsoluteMinute"] = int(
		_environment.get_absolute_minute(),
	)
	prepared["sourcePlace"] = String(resident.get("currentPlace", ""))
	prepared["durationMinutes"] = 0
	prepared["pathPoints"] = path
	prepared["effects"] = {}
	prepared["targetPosition"] = target_position
	prepared["dynamicPropId"] = ""
	var return_connector := path.duplicate()
	return_connector.reverse()
	prepared["returnRouteConnector"] = return_connector
	prepared["consumeRouteConnector"] = not (
		resident.get("routeConnector", []) as Array
	).is_empty()
	if not _prepared_same_space_action_route_errors(
		resident,
		prepared,
	).is_empty():
		return {
			"ok": false,
			"errors": ["当前没有到这个活动区域落点的安全路线"],
		}
	prepared["pathClearanceVerified"] = true
	return {"ok": true, "action": prepared}


func _prepared_same_space_action_route_errors(
	resident: Dictionary,
	prepared_action: Dictionary,
) -> PackedStringArray:
	return ACTION_SUPPORT.prepared_same_space_action_route_errors(resident, prepared_action)


func _region_activity_position_occupied(
	resident_id: String,
	position_value: Array,
) -> bool:
	return ACTION_SUPPORT.region_activity_position_occupied(self, resident_id, position_value)


func _validate_layout_occupants(
	space_id: String,
	projection: Dictionary,
	errors: PackedStringArray,
) -> void:
	ACTION_SUPPORT.validate_layout_occupants(self, space_id, projection, errors)


func _prepare_talk_action(resident_name: String, resident: Dictionary, action: Dictionary) -> Dictionary:
	if not CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_name).is_empty():
		return {"ok": false, "errors": ["居民已经在参与另一段对话"]}
	var target_resident_id := String(action.get("target_resident_id", "")).strip_edges()
	var target_ref := target_resident_id
	var target := _person_state(target_ref)
	if target_ref.is_empty() or target_ref == resident_name or target.is_empty():
		return {"ok": false, "errors": ["搭话对象必须是附近的其他人物"]}
	var postal_delivery := _private_message_delivery_task_for_talk(
		resident_name,
		target_ref,
		String(action.get("say", "")),
	)
	var medical_binding := _clinic_interview_binding_for_pair(
		resident_name,
		target_ref,
	)
	if medical_binding.is_empty():
		medical_binding = _clinic_interview_binding_for_pair(
			target_ref,
			resident_name,
		)
	if (
		not PERCEPTION_RUNTIME._are_nearby(self, resident, target)
		and postal_delivery.is_empty()
		and medical_binding.is_empty()
	):
		return {"ok": false, "errors": ["搭话对象已经不在感知范围内"]}
	if not CONVERSATION_RUNTIME._active_conversation_for_person(self, target_ref).is_empty():
		return {"ok": false, "errors": ["搭话对象正在参与其他对话"]}
	if medical_binding.is_empty() and CONVERSATION_RUNTIME._resident_pair_conversation_on_cooldown(self, 
		resident_name,
		target_ref,
	):
		return {"ok": false, "errors": ["双方刚结束交谈，稍后再聊"]}
	var turn_error := CONVERSATION_RUNTIME._validate_conversation_turn_action(self, resident_name, action, false)
	if not turn_error.is_empty():
		return {"ok": false, "errors": [turn_error]}
	var prepared := action.duplicate(true)
	prepared["target"] = _person_name_for_id(target_ref)
	prepared["target_resident_id"] = target_ref
	prepared["startedAbsoluteMinute"] = int(_environment.get_absolute_minute())
	if not medical_binding.is_empty():
		prepared["medicalRequestId"] = String(
			medical_binding.get("requestId", ""),
		)
		prepared["medicalTaskId"] = String(
			medical_binding.get("taskId", ""),
		)
	if not postal_delivery.is_empty() and not PERCEPTION_RUNTIME._are_nearby(self, resident, target):
		prepared["privateMessageId"] = String(
			postal_delivery.get("messageId", ""),
		)
		return _prepare_postal_talk_approach(
			resident,
			target,
			prepared,
		)
	return {"ok": true, "action": prepared}


func _prepare_reply_action(resident_name: String, action: Dictionary) -> Dictionary:
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_name)
	if conversation.is_empty():
		return {"ok": false, "errors": ["居民当前没有可以答话的对话"]}
	var conversation_id := String(action.get("conversation_id", "")).strip_edges()
	if conversation_id != String(conversation.get("conversationId", "")):
		return {"ok": false, "errors": ["答话的 conversation_id 与当前对话不一致"]}
	if String(conversation.get("waitingFor", "")) != resident_name:
		return {"ok": false, "errors": ["当前对话还没有轮到本居民答话"]}
	var turn_error := CONVERSATION_RUNTIME._validate_conversation_turn_action(self, resident_name, action, true)
	if not turn_error.is_empty():
		return {"ok": false, "errors": [turn_error]}
	var prepared := action.duplicate(true)
	prepared["startedAbsoluteMinute"] = int(_environment.get_absolute_minute())
	return {"ok": true, "action": prepared}


func _go_action_can_prefetch_decision(action: Dictionary) -> bool:
	if (
		String(action.get("type", "")) != "去"
		or not String(action.get("conversationFollowUpMode", "")).is_empty()
		or not String(action.get("serviceRequestId", "")).is_empty()
	):
		return false
	var route_value: Variant = action.get("route", {})
	if not route_value is Dictionary:
		return false
	var positions_value: Variant = (route_value as Dictionary).get(
		"minutePositions",
		[],
	)
	return positions_value is Array and not (positions_value as Array).is_empty()


func _go_action_arrival_projection(resident: Dictionary) -> Dictionary:
	var action := resident.get("currentAction", {}) as Dictionary
	if not _go_action_can_prefetch_decision(action):
		return {}
	var arrival := _resident_movement_target(resident)
	if arrival.is_empty():
		return {}
	var position_value: Variant = arrival.get("position")
	if not position_value is Vector2 or not (position_value as Vector2).is_finite():
		return {}
	var current_place := String(arrival.get("placeName", "")).strip_edges()
	if current_place.is_empty():
		current_place = String(action.get("place", "")).strip_edges()
	var space_id := String(arrival.get("spaceId", "")).strip_edges()
	var region_id := String(arrival.get("regionId", "")).strip_edges()
	if current_place.is_empty() or space_id.is_empty():
		return {}
	return {
		"spaceId": space_id,
		"regionId": region_id,
		"currentPlace": current_place,
		"position": position_value as Vector2,
	}


func _advance_actions(absolute_minute: int) -> void:
	for resident_name in _resident_order:
		var resident := _residents[resident_name] as Dictionary
		if not _resident_is_present(resident):
			continue
		var action := resident.get("currentAction", {}) as Dictionary
		if bool(resident.get("decisionPending", false)) and action.is_empty():
			continue
		if bool(action.get("followUpPausedForReconsideration", false)):
			continue
		if int(resident.get("actionSuspendedAbsoluteMinute", -1)) >= 0:
			if not CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_name).is_empty():
				continue
			_resume_suspended_action(resident)
			action = resident.get("currentAction", {}) as Dictionary
		# Prefetch the next decision without replacing the running action.
		var complete_minute := int(action.get("completeAbsoluteMinute", -1))
		if (
			not action.is_empty()
			and not bool(resident.get("decisionPending", false))
			and (
				String(action.get("type", "")) != "去"
				or _go_action_can_prefetch_decision(action)
			)
			and String(action.get("conversationFollowUpMode", "")).is_empty()
			and String(action.get("serviceRequestId", "")).is_empty()
			and complete_minute >= absolute_minute
			and complete_minute - absolute_minute <= ACTION_DECISION_PREFETCH_MINUTES
		):
			_schedule_decision(resident_name, false, true)
			action = resident.get("currentAction", {}) as Dictionary
		# 排查计时:按动作类型分段;前置检查成本=外层 actionsUsec 减各分段。
		var probe_lap_usec := Time.get_ticks_usec() if _advance_profile_enabled else 0
		if not action.is_empty() and not _action_still_valid(resident, action):
			var activity_execution := _activity_runtime.execution_for_action(
				resident_name,
				String(action.get("action_id", "")),
			) as Dictionary
			if activity_execution.is_empty() and not String(action.get("conversationFollowUpMode", "")).is_empty():
				_begin_conversation_follow_up_reconsideration(
					resident_name,
					"行动条件已经变化，需要重新决定怎样履行约定",
				)
			elif activity_execution.is_empty():
				_interrupt_action(resident_name, "动作执行条件已经失效")
			else:
				_fail_activity_action(
					resident_name,
					"ACTIVITY_STATE_CHANGED",
					"活动执行条件已经失效",
				)
			continue
		match String(action.get("type", "")):
			"去":
				_advance_go_action(resident_name, resident, action, absolute_minute)
			"用道具":
				_advance_prop_action(resident_name, resident, action, absolute_minute)
			"调整营业":
				if absolute_minute >= int(
					action.get("completeAbsoluteMinute", INF)
				):
					_finish_service_control_action(
						resident_name,
						action,
					)
			"托人传话":
				if absolute_minute >= int(
					action.get("completeAbsoluteMinute", INF)
				):
					_finish_private_message_action(
						resident_name,
						action,
					)
			"搭话":
				if not String(action.get("approachMode", "")).is_empty():
					_advance_postal_talk_approach(
						resident_name,
						resident,
						action,
						absolute_minute,
					)
			"待着":
				_advance_wait_action(
					resident_name,
					resident,
					action,
					absolute_minute,
				)
		if _advance_profile_enabled:
			var probe_type := String(action.get("type", "无"))
			_advance_profile_lap(_advance_profile_scratch, "actions:%sUsec" % probe_type, probe_lap_usec)
			_advance_profile_count("actions:%sCount" % probe_type, 1)


func _clearance_safe_position(space_id: String, position: Vector2) -> Vector2:
	# 行为修复轨(aya 08-07 裁决方案 A):路线插值点可能落在缺少玩家碰撞净空的
	# 位置,存档校验会拒绝该权威位置。落点选定时即施加净空约束——已安全的点
	# 原样返回(nearest_safe_position 对安全点 adjusted=false),不安全的点吸附
	# 到最近安全点;查询不可用时保持原值(不改变既有降级路径)。
	return MOVEMENT_CLEARANCE_RUNTIME.nearest_safe_position(
		_world_data,
		space_id,
		position,
	)


func _advance_go_action(resident_name: String, resident: Dictionary, action: Dictionary, absolute_minute: int) -> void:
	if _conversation_follow_up_timed_out(resident_name, action, absolute_minute):
		return
	if (
		String(action.get("conversationFollowUpMode", "")) == "escort_follower"
		and _hold_resident_escort_follower(resident_name, resident, action, absolute_minute)
	):
		return
	if (
		String(action.get("conversationFollowUpMode", "")) == "escort"
		and String(action.get("followUpPhase", "")) == "leading"
		and _hold_or_return_for_escort_companion(resident_name, resident, action, absolute_minute)
	):
		return
	if _closed_service_place_for_visitor(
		resident,
		String(action.get("place", "")),
	):
		var closed_reason := "%s今天没有营业，没能进去" % String(action.get("place", ""))
		if String(action.get("conversationFollowUpMode", "")).is_empty():
			_interrupt_action(resident_name, closed_reason)
		else:
			_begin_conversation_follow_up_reconsideration(resident_name, closed_reason)
		return
	var elapsed := maxi(0, absolute_minute - int(action.get("startedAbsoluteMinute", absolute_minute)))
	var route := action.get("route", {}) as Dictionary
	var positions := route.get("minutePositions", []) as Array
	var duration := int(action.get("durationMinutes", 0))
	var sample_index := mini(elapsed, positions.size() - 1)
	if sample_index >= 0:
		var previous_place := String(resident.get("currentPlace", ""))
		# runtimeStart only records that this route was connected from the resident's
		# exact live position. Its connector and minute samples were already built by
		# TownWorldRouteQuery against formal navigation, so repairing clearance again
		# on every game minute repeats an expensive collision search without adding
		# safety. Unverified ad-hoc paths retain their own one-time clearance contract.
		var position_changed := _apply_route_sample(
			resident,
			positions[sample_index] as Dictionary,
		)
		_emit_place_change(resident_name, previous_place)
		# C1(docs/居民状态通知链减负方案.md):表现真变化才发,静止分钟零发射。
		if position_changed:
			var probe_emit_usec := Time.get_ticks_usec() if _advance_profile_enabled else 0
			_emit_resident_state_changed(resident_name)
			_advance_profile_lap(_advance_profile_scratch, "actionsGoEmitUsec", probe_emit_usec)
			_advance_profile_count("actionsGoEmitCount", 1)
	if elapsed >= duration:
		_apply_body_effects(resident, action.get("completionEffects", {}) as Dictionary)
		_settle_cargo_arrival_for_resident(resident_name)
		_settle_resident_route_condition(
			resident_name,
			resident,
			action,
			"completed",
		)
		_finish_action(resident_name, "已到达%s" % String(action.get("place", "")))


func _conversation_follow_up_timed_out(
	resident_id: String,
	action: Dictionary,
	absolute_minute: int,
) -> bool:
	if String(action.get("conversationFollowUpMode", "")).is_empty():
		return false
	var deadline := int(action.get("followUpDeadlineMinute", -1))
	if deadline < 0 or absolute_minute <= deadline:
		return false
	_interrupt_action(resident_id, "约定持续太久仍未完成，居民结束等待并恢复自己的生活")
	return true


func _pause_active_conversation_follow_ups_for_reconsideration(reason: String) -> void:
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			action.is_empty()
			or String(action.get("conversationFollowUpMode", "")).is_empty()
			or String(action.get("conversationFollowUpMode", "")) in [
				"reconsideration_wait",
				"escort_follower",
			]
		):
			continue
		_begin_conversation_follow_up_reconsideration(resident_id, reason)


func _pause_conversation_follow_ups_for_service(place_id: String, reason: String) -> void:
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			String(action.get("conversationFollowUpMode", "")) != "fetch_service"
			or String(action.get("followUpServicePlace", "")) != place_id
		):
			continue
		_begin_conversation_follow_up_reconsideration(resident_id, reason)


func _begin_conversation_follow_up_reconsideration(
	resident_id: String,
	reason: String,
	queue_fact: bool = true,
) -> void:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if resident.is_empty() or action.is_empty() or String(action.get("conversationFollowUpMode", "")).is_empty():
		return
	if bool(action.get("followUpPausedForReconsideration", false)):
		return
	var normalized_reason := reason.strip_edges()
	if normalized_reason.is_empty():
		normalized_reason = "约定途中的情况已经变化"
	action["followUpPausedForReconsideration"] = true
	action["followUpReconsiderationReason"] = normalized_reason
	action["followUpReconsiderationSinceMinute"] = int(_environment.get_absolute_minute())
	resident["currentAction"] = action
	resident["doing"] = "正在重新考虑怎样履行刚才的约定"
	if queue_fact:
		_queue_world_event(resident_id, {
			"type": "承诺条件变化",
			"summary": normalized_reason,
			"commitment_action_id": String(action.get("action_id", "")),
			"time": get_time(),
		})
	_schedule_decision(resident_id, true, false, true)
	_bump_world_revision(false)
	_emit_resident_state_changed(resident_id)


func _resume_conversation_follow_up_after_wait(
	resident_id: String,
	resident: Dictionary,
	wait_action: Dictionary,
) -> bool:
	var resume_action := (wait_action.get("followUpResumeAction", {}) as Dictionary).duplicate(true)
	if resume_action.is_empty():
		_interrupt_action(resident_id, "等待结束后没有找到可以继续的原约定")
		return true
	var now := int(_environment.get_absolute_minute())
	if _conversation_follow_up_timed_out(resident_id, resume_action, now):
		return true
	resume_action["startedAbsoluteMinute"] = now
	resume_action["followUpLastAdvanceMinute"] = now
	_install_conversation_follow_up_action(resident_id, resident, resume_action, "继续履行刚才的约定")
	if (
		String(resume_action.get("conversationFollowUpMode", "")) == "fetch_service"
		and not _conversation_fetch_service_is_available(resume_action)
	):
		_begin_conversation_follow_up_reconsideration(resident_id, "等待后服务仍不可用，需要再次决定")
	return true


func _resume_conversation_follow_up_reconsideration(resident: Dictionary) -> void:
	var action := resident.get("currentAction", {}) as Dictionary
	if not bool(action.get("followUpPausedForReconsideration", false)):
		return
	var now := int(_environment.get_absolute_minute())
	var paused_at := int(action.get("followUpReconsiderationSinceMinute", now))
	var paused_minutes := maxi(0, now - paused_at)
	for field: String in ["startedAbsoluteMinute", "completeAbsoluteMinute"]:
		if action.has(field):
			action[field] = int(action.get(field, now)) + paused_minutes
	action["followUpLastAdvanceMinute"] = now
	action.erase("followUpPausedForReconsideration")
	action.erase("followUpReconsiderationReason")
	action.erase("followUpReconsiderationSinceMinute")
	resident["currentAction"] = action
	resident["doing"] = _default_doing(action)


func _hold_or_return_for_escort_companion(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> bool:
	var person_id := String(action.get("followUpPersonId", ""))
	var companion := _person_state(person_id)
	if companion.is_empty() or (person_id == _player_avatar_id() and not _player_avatar_present):
		_interrupt_action(resident_id, "同行者已经离开当前小镇现场")
		return true
	var last_advance := int(action.get("followUpLastAdvanceMinute", absolute_minute))
	var step_minutes := maxi(0, absolute_minute - last_advance)
	action["followUpLastAdvanceMinute"] = absolute_minute
	if PERCEPTION_RUNTIME._are_nearby(self, resident, companion):
		action["followUpLagStartedMinute"] = -1
		resident["currentAction"] = action
		resident["doing"] = "正带%s前往%s" % [
			_person_name_for_id(person_id),
			String(action.get("followUpDestinationPlace", "")),
		]
		return false
	if step_minutes > 0:
		action["startedAbsoluteMinute"] = int(action.get("startedAbsoluteMinute", absolute_minute)) + step_minutes
	var lag_started := int(action.get("followUpLagStartedMinute", -1))
	if lag_started < 0:
		lag_started = absolute_minute
		action["followUpLagStartedMinute"] = lag_started
	resident["currentAction"] = action
	if absolute_minute - lag_started < ESCORT_RETURN_AFTER_MINUTES:
		resident["doing"] = "停下来等%s跟上" % _person_name_for_id(person_id)
		_emit_resident_state_changed(resident_id)
		return true
	return _begin_follow_up_person_approach(resident_id, resident, action, "returning_to_companion")


func _hold_resident_escort_follower(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> bool:
	var guide_id := String(action.get("followUpPersonId", ""))
	var guide := _residents.get(guide_id, {}) as Dictionary
	var guide_action := guide.get("currentAction", {}) as Dictionary
	if (
		guide.is_empty()
		or String(guide_action.get("conversationFollowUpMode", "")) != "escort"
		or String(guide_action.get("followUpPersonId", "")) != resident_id
	):
		_interrupt_action(resident_id, "带路已经结束，同行者恢复自己的生活")
		return true
	var last_advance := int(action.get("followUpLastAdvanceMinute", absolute_minute))
	var step_minutes := maxi(0, absolute_minute - last_advance)
	action["followUpLastAdvanceMinute"] = absolute_minute
	if bool(guide_action.get("followUpPausedForReconsideration", false)):
		if step_minutes > 0:
			action["startedAbsoluteMinute"] = int(
				action.get("startedAbsoluteMinute", absolute_minute),
			) + step_minutes
		resident["currentAction"] = action
		resident["doing"] = "等带路人决定是否继续"
		return true
	resident["currentAction"] = action
	resident["doing"] = "正跟着%s前往%s" % [
		_person_name_for_id(guide_id),
		String(action.get("followUpDestinationPlace", "")),
	]
	return false


func _continue_conversation_follow_up_after_step(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	var mode := String(action.get("conversationFollowUpMode", ""))
	var phase := String(action.get("followUpPhase", ""))
	if mode.is_empty():
		return false
	if mode == "reconsideration_wait":
		return _resume_conversation_follow_up_after_wait(resident_id, resident, action)
	var person_id := String(action.get("followUpPersonId", ""))
	var person := _person_state(person_id)
	if person.is_empty() or (person_id == _player_avatar_id() and not _player_avatar_present):
		_interrupt_action(resident_id, "约定的同行者已经离开当前小镇现场")
		return true
	if mode == "escort":
		var destination := String(action.get("followUpDestinationPlace", ""))
		if String(resident.get("currentPlace", "")) == destination and String(person.get("currentPlace", "")) == destination and PERCEPTION_RUNTIME._are_nearby(self, resident, person):
			action["followUpPhase"] = "arrived"
			resident["currentAction"] = action
			return false
		if phase == "returning_to_companion" and PERCEPTION_RUNTIME._are_nearby(self, resident, person):
			return _begin_escort_destination_route(resident_id, resident, action)
		return _begin_follow_up_person_approach(resident_id, resident, action, "returning_to_companion")
	if mode == "fetch_service":
		if phase == "going_to_source":
			return _begin_conversation_service_collection(resident_id, resident, action)
		if phase == "collecting":
			action["followUpServiceCollected"] = true
			if PERCEPTION_RUNTIME._are_nearby(self, resident, person):
				action["followUpPhase"] = "delivered"
				resident["currentAction"] = action
				return false
			return _begin_follow_up_person_approach(resident_id, resident, action, "returning_to_person")
		if phase == "returning_to_person":
			if PERCEPTION_RUNTIME._are_nearby(self, resident, person):
				action["followUpPhase"] = "delivered"
				resident["currentAction"] = action
				return false
			return _begin_follow_up_person_approach(resident_id, resident, action, "returning_to_person")
	return false


func _begin_escort_destination_route(
	resident_id: String,
	resident: Dictionary,
	previous_action: Dictionary,
) -> bool:
	var destination := String(previous_action.get("followUpDestinationPlace", ""))
	if String(resident.get("currentPlace", "")) == destination:
		return _begin_follow_up_person_approach(resident_id, resident, previous_action, "returning_to_companion")
	var prepared := _prepare_go_action(resident, {
		"action_id": String(previous_action.get("action_id", "")),
		"type": "去",
		"place": destination,
		"line": "跟紧我，我们继续走",
	}) as Dictionary
	if prepared.get("ok") != true:
		_begin_conversation_follow_up_reconsideration(resident_id, "重新带路时，前往目的地的路线已经失效")
		return true
	var next_action := (prepared.get("action", {}) as Dictionary).duplicate(true)
	_copy_conversation_follow_up_state(previous_action, next_action)
	next_action["followUpPhase"] = "leading"
	next_action["followUpLagStartedMinute"] = -1
	next_action["followUpLastAdvanceMinute"] = int(_environment.get_absolute_minute())
	_install_conversation_follow_up_action(resident_id, resident, next_action, "等到同行者后继续带路")
	return true


func _begin_follow_up_person_approach(
	resident_id: String,
	resident: Dictionary,
	previous_action: Dictionary,
	phase: String,
) -> bool:
	var person_id := String(previous_action.get("followUpPersonId", ""))
	var target := _person_state(person_id)
	if target.is_empty():
		_interrupt_action(resident_id, "无法找到约定同行者的有效位置")
		return true
	if PERCEPTION_RUNTIME._are_nearby(self, resident, target):
		if phase == "returning_to_companion":
			return _begin_escort_destination_route(resident_id, resident, previous_action)
		previous_action["followUpPhase"] = "delivered"
		resident["currentAction"] = previous_action
		return false
	var approach_action := {
		"action_id": String(previous_action.get("action_id", "")),
		"type": "搭话",
		"target_resident_id": person_id,
		"target": _person_name_for_id(person_id),
		"say": "",
		"narration": "我沿安全路线返回约定同行者身边",
		"photos": [],
		"startedAbsoluteMinute": int(_environment.get_absolute_minute()),
	}
	var prepared := _prepare_postal_talk_approach(resident, target, approach_action) as Dictionary
	if prepared.get("ok") != true:
		_begin_conversation_follow_up_reconsideration(resident_id, "无法沿真实路线回到约定同行者身边")
		return true
	var next_action := (prepared.get("action", {}) as Dictionary).duplicate(true)
	_copy_conversation_follow_up_state(previous_action, next_action)
	next_action["followUpPhase"] = phase
	_install_conversation_follow_up_action(
		resident_id,
		resident,
		next_action,
		"我回来找你了，跟上来" if phase == "returning_to_companion" else "正把东西送回约定对象身边",
	)
	return true


func _settle_cargo_arrival_for_resident(resident_id: String) -> void:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var current_place := String(resident.get("currentPlace", ""))
	var carried := _cargo_inventory.lots_for_resident(
		resident_id,
	) as Array
	for lot_value: Variant in carried:
		var lot := lot_value as Dictionary
		if String(lot.get("destinationPlaceId", "")) == current_place:
			deliver_cargo_lot(
				String(lot.get("lotId", "")),
				resident_id,
			)
			return
	var candidates: Array[Dictionary] = []
	for task_value: Variant in get_work_tasks_for_resident(resident_id):
		var task := task_value as Dictionary
		if String(task.get("capability", "")) != "cargo.deliver":
			continue
		var lot := _cargo_inventory.cargo_lot(
			String(task.get("source_ref", "")),
		) as Dictionary
		if (
			String(lot.get("state", "")) == "available"
			and String(lot.get("sourcePlaceId", "")) == current_place
		):
			candidates.append(lot)
	if candidates.size() == 1:
		pickup_cargo_lot(
			String(candidates[0].get("lotId", "")),
			resident_id,
		)


func _extend_meal_routine_for_service_wait(
	resident_name: String,
	absolute_minute: int,
) -> void:
	if not _activity_routines.has(resident_name):
		return
	var routine := _activity_routines[resident_name] as Dictionary
	if String(routine.get("group", "")) != "meal":
		return
	routine["endAbsoluteMinute"] = maxi(
		int(routine.get("endAbsoluteMinute", absolute_minute)),
		absolute_minute
		+ int(ACTIVITY_ROUTINE_DURATION_MINUTES.get("meal", 30)),
	)
	_activity_routines[resident_name] = routine


func _advance_wait_action(
	resident_name: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> void:
	var service_request_id := String(
		action.get("serviceRequestId", ""),
	)
	if not service_request_id.is_empty():
		var service_request := _occupation_services.request(service_request_id,) as Dictionary
		if String(service_request.get("state", "")) in [
			"pending",
			"waiting",
			"in_progress",
		]:
			action["completeAbsoluteMinute"] = maxi(
				int(action.get("completeAbsoluteMinute", absolute_minute)),
				absolute_minute + 5,
			)
			_extend_meal_routine_for_service_wait(
				resident_name,
				absolute_minute,
			)
			return
	if _conversation_follow_up_timed_out(resident_name, action, absolute_minute):
		return
	if (
		String(action.get("conversationFollowUpMode", "")) == "fetch_service"
		and String(action.get("followUpPhase", "")) == "collecting"
		and not _conversation_fetch_service_is_available(action)
	):
		_begin_conversation_follow_up_reconsideration(
			resident_name,
			"答应前往的服务地点已经停止营业或不再提供这项服务",
		)
		return
	var move_duration := int(action.get("idleMoveDurationMinutes", 0))
	var elapsed := maxi(
		0,
		absolute_minute
			- int(action.get("startedAbsoluteMinute", absolute_minute)),
	)
	if (
		move_duration > 0
		and elapsed <= move_duration
		and action.get("idlePathPoints") is Array
	):
		var wait_move_lap_usec := Time.get_ticks_usec() if _advance_profile_enabled else 0
		var path_points: Array[Vector2] = []
		path_points.assign(action.get("idlePathPoints", []) as Array)
		var ratio := clampf(
			float(elapsed) / float(move_duration),
			0.0,
			1.0,
		)
		# idlePathPoints 只由正式室外 movementNetwork 或室内导航查询生成，
		# 路径本身已经满足对应空间的可行走合同。逐分钟再次做最近安全点
		# 径向搜索会让所有居民在同一秒重复扫描碰撞数据，造成周期卡顿。
		var next_position := _point_along_polyline(path_points, ratio)
		wait_move_lap_usec = _advance_profile_lap(
			_advance_profile_scratch,
			"actionsWaitPathSampleUsec",
			wait_move_lap_usec,
		)
		var previous_place := String(resident.get("currentPlace", ""))
		var membership := PERCEPTION_RUNTIME._membership(self,
			String(resident.get("spaceId", "")),
			next_position,
		)
		wait_move_lap_usec = _advance_profile_lap(
			_advance_profile_scratch,
			"actionsWaitMembershipUsec",
			wait_move_lap_usec,
		)
		var position_changed := _apply_authoritative_resident_position(
			resident,
			next_position,
			String(resident.get("spaceId", "")),
			String(
				membership.get(
					"regionId",
					resident.get("regionId", ""),
				)
			),
			String(
				membership.get(
					"placeName",
					resident.get("currentPlace", ""),
				)
			),
		)
		wait_move_lap_usec = _advance_profile_lap(
			_advance_profile_scratch,
			"actionsWaitApplyPositionUsec",
			wait_move_lap_usec,
		)
		var place_changed := _emit_place_change(
			resident_name,
			previous_place,
			true,
		)
		# C1(docs/居民状态通知链减负方案.md):表现真变化才发。
		if position_changed and not place_changed:
			# 权威位置已经在本分钟写入；画面刷新按帧预算发送，避免 15 位
			# 正在闲逛的居民在同一主线程帧里依次重建表现状态。
			_queue_resident_state_refresh(resident_name)
		_advance_profile_lap(
			_advance_profile_scratch,
			"actionsWaitStateQueueUsec",
			wait_move_lap_usec,
		)
	if absolute_minute >= int(action.get("completeAbsoluteMinute", INF)):
		_finish_action(resident_name, "已经停留了一会儿")


func _finish_service_control_action(
	resident_id: String,
	action: Dictionary,
) -> void:
	var place_id := String(action.get("place_id", ""))
	var opening := bool(action.get("open", false))
	var changed := set_place_service_open(
		place_id,
		opening,
		resident_id,
	)
	if changed.get("ok") != true:
		_interrupt_action(
			resident_id,
			String(
				(changed.get("errors", ["营业状态未能改变"]) as Array)[0]
			),
		)
		return
	_finish_action(
		resident_id,
		(
			"%s恢复营业了" % place_id
			if opening
			else "%s今天停止营业了" % place_id
		),
	)


func _finish_private_message_action(
	resident_id: String,
	action: Dictionary,
) -> void:
	var created := create_private_message(
		resident_id,
		String(action.get("recipient_resident_id", "")),
		String(action.get("content", "")),
	)
	if created.get("ok") != true:
		_interrupt_action(
			resident_id,
			String(
				(created.get(
					"errors",
					["口信没有进入投递流程"],
				) as Array)[0]
			),
		)
		return
	_finish_action(
		resident_id,
		"已把口信交给投递流程，等待邮差送达",
	)


func _advance_postal_talk_approach(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> void:
	var target_id := String(action.get("target_resident_id", ""))
	var target := _person_state(target_id)
	if target.is_empty():
		_interrupt_action(resident_id, "收件人已经不在小镇中")
		return
	var elapsed := maxi(
		0,
		absolute_minute - int(
			action.get("startedAbsoluteMinute", absolute_minute),
		),
	)
	var duration := maxi(0, int(action.get("durationMinutes", 0)))
	var approach_mode := String(action.get("approachMode", ""))
	if approach_mode == "same_space_path":
		var path: Array[Vector2] = []
		path.assign(action.get("pathPoints", []) as Array)
		if path.is_empty():
			_interrupt_action(resident_id, "到收件人身边的路线已经失效")
			return
		var ratio := (
			1.0
			if duration <= 0
			else clampf(float(elapsed) / float(duration), 0.0, 1.0)
		)
		var next_position := _point_along_polyline(path, ratio)
		var previous_place := String(resident.get("currentPlace", ""))
		var membership := PERCEPTION_RUNTIME._membership(self,
			String(resident.get("spaceId", "")),
			next_position,
		)
		var position_changed := _apply_authoritative_resident_position(
			resident,
			next_position,
			String(resident.get("spaceId", "")),
			String(membership.get("regionId", resident.get("regionId", ""))),
			String(
				membership.get("placeName", resident.get("currentPlace", "")),
			),
		)
		_emit_place_change(resident_id, previous_place)
		# C1(docs/居民状态通知链减负方案.md):表现真变化才发。
		if position_changed:
			_emit_resident_state_changed(resident_id)
	elif approach_mode == "place_route":
		var route := action.get("approachRoute", {}) as Dictionary
		var positions := route.get("minutePositions", []) as Array
		if positions.is_empty():
			_interrupt_action(resident_id, "到收件人所在地点的路线已经失效")
			return
		var sample_index := mini(elapsed, positions.size() - 1)
		var previous_place := String(resident.get("currentPlace", ""))
		var route_position_changed := _apply_route_sample(resident, positions[sample_index] as Dictionary)
		_emit_place_change(resident_id, previous_place)
		if route_position_changed:
			_emit_resident_state_changed(resident_id)
	else:
		_interrupt_action(resident_id, "邮差接近收件人的动作状态无效")
		return
	if elapsed < duration:
		return
	if not String(action.get("conversationFollowUpMode", "")).is_empty():
		_finish_action(resident_id, "已经回到约定同行者身边")
		return
	if PERCEPTION_RUNTIME._are_nearby(self, resident, target):
		for field: String in [
			"approachMode",
			"approachRoute",
			"pathPoints",
			"targetPosition",
			"targetSpaceId",
			"targetRegionId",
			"targetPlace",
			"expectedTargetPosition",
			"durationMinutes",
			"returnRouteConnector",
			"consumeRouteConnector",
		]:
			action.erase(field)
		resident["currentAction"] = action
		CONVERSATION_RUNTIME._start_conversation(self, resident_id, action)
		return
	var refreshed := _prepare_postal_talk_approach(
		resident,
		target,
		action,
	) as Dictionary
	if refreshed.get("ok") != true:
		_interrupt_action(resident_id, "没能继续接近正在移动的收件人")
		return
	var next_action := (
		refreshed.get("action", {}) as Dictionary
	).duplicate(true)
	next_action["startedAbsoluteMinute"] = absolute_minute
	resident["currentAction"] = next_action
	resident["doing"] = "正在接近收件人并转达口信"


func _advance_prop_action(resident_name: String, resident: Dictionary, action: Dictionary, absolute_minute: int) -> void:
	var duration := int(action.get("durationMinutes", 0))
	var elapsed := maxi(0, absolute_minute - int(action.get("startedAbsoluteMinute", absolute_minute)))
	var approach_duration := _prop_approach_duration_minutes(action)
	var ratio := (
		1.0
		if approach_duration <= 0
		else clampf(float(elapsed) / float(approach_duration), 0.0, 1.0)
	)
	# Dictionary/save restoration preserves Vector2 values but not the typed-array
	# element tag. Rebuild the typed boundary before calling the movement helpers.
	var path_points: Array[Vector2] = []
	path_points.assign(action.get("pathPoints", []) as Array)
	var next_position := _point_along_polyline(path_points, ratio)
	if not bool(action.get("pathClearanceVerified", false)):
		next_position = _clearance_safe_position(
			String(resident.get("spaceId", "")),
			next_position,
		)
	resident["routeConnector"] = _reverse_polyline_to_ratio(path_points, ratio)
	var previous_place := String(resident.get("currentPlace", ""))
	var space_id := String(resident.get("spaceId", ""))
	var region_id := String(resident.get("regionId", ""))
	var place_name := String(resident.get("currentPlace", ""))
	var membership := PERCEPTION_RUNTIME._membership(self, space_id, next_position)
	if not membership.is_empty():
		region_id = String(membership.get("regionId", region_id))
		place_name = String(membership.get("placeName", place_name))
	var position_changed := _apply_authoritative_resident_position(
		resident,
		next_position,
		space_id,
		region_id,
		place_name,
	)
	_emit_place_change(resident_name, previous_place)
	var activity_execution := _activity_runtime.execution_for_action(
		resident_name,
		String(action.get("action_id", "")),
	) as Dictionary
	if (
		not activity_execution.is_empty()
		and String(resident.get("currentPlace", ""))
		!= String(activity_execution.get("placeId", ""))
		and (
			String(activity_execution.get("targetType", ""))
				!= "region"
			or elapsed >= approach_duration
		)
	):
		_fail_activity_action(
			resident_name,
			"ACTIVITY_STATE_CHANGED",
			"居民离开活动地点",
		)
		return
	var sleep_started := false
	if (
		not activity_execution.is_empty()
		and elapsed >= approach_duration
	):
		sleep_started = _ensure_resident_sleep_started(
			resident_name,
			action,
			activity_execution,
		)
		resident["doing"] = _activity_progress_doing(
			activity_execution,
			maxi(0, elapsed - approach_duration),
		)
	# C1(docs/居民状态通知链减负方案.md):表现真变化才发——位置变化、activityCue
	# 阶段边界(approaching→performing)、睡眠实际开始;doing 轮换不在表现合同内。
	if (
		position_changed
		or sleep_started
		or (elapsed >= approach_duration and elapsed - 1 < approach_duration)
	):
		_emit_resident_state_changed(resident_name)
	if not activity_execution.is_empty():
		_activity_runtime.sync_remaining_ticks(
			resident_name,
			maxi(0, approach_duration + duration - elapsed),
		)
	if elapsed >= approach_duration + duration:
		if activity_execution.is_empty():
			_apply_body_effects(resident, action.get("effects", {}) as Dictionary)
			_finish_action(resident_name, "已完成%s·%s" % [action.get("prop", "道具"), action.get("verb", "动作")])
		else:
			_finish_activity_action(resident_name)


func _finish_action(resident_name: String, reason: String) -> void:
	var resident := _residents[resident_name] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	if _continue_conversation_follow_up_after_step(resident_name, resident, action):
		return
	var action_id := String(action.get("action_id", ""))
	var result_presentation := ACTION_PRESENTATION._preview_action_presentation(self, 
		resident,
		{"action": action},
	)
	_restore_action_route_connector(resident, action)
	_record_matching_social_action_result(
		resident_name,
		action,
		"completed",
		reason,
	)
	_record_completed_animal_interaction(
		resident_name,
		action,
	)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = reason
	_queue_action_result(
		resident_name,
		action_id,
		"completed",
		reason,
		true,
		true,
		result_presentation,
	)
	_emit_resident_state_changed(resident_name)


func _record_completed_animal_interaction(
	resident_id: String,
	action: Dictionary,
) -> void:
	if String(action.get("verb", "")) != "摸摸":
		return
	var prop_id := String(action.get("dynamicPropId", ""))
	var prefix := "dynamic_animal_"
	if not prop_id.begins_with(prefix):
		return
	var animal_id := prop_id.trim_prefix(prefix)
	var fact := (
		_animal_facts.get(animal_id, {}) as Dictionary
	)
	if fact.is_empty() or not bool(fact.get("exists", false)):
		return
	var event_ids: Array = (
		fact.get("source_event_ids", []) as Array
	).duplicate()
	var event_id := "animal-pet:%s:%s" % [
		resident_id,
		String(action.get("action_id", "")),
	]
	if not event_ids.has(event_id):
		event_ids.append(event_id)
	var now := int(_environment.get_absolute_minute())
	var attention_result := set_animal_public_attention(
		animal_id,
		true,
		maxi(int(fact.get("expires_at", -1)), now + 60),
		event_ids,
	) as Dictionary
	if bool(attention_result.get("ok", false)):
		_append_animal_log_event(
			"居民抚摸动物",
			fact,
			resident_id,
			_resident_display_name(resident_id),
		)


func _restore_action_route_connector(
	resident: Dictionary,
	action: Dictionary,
) -> void:
	if not action.has("returnRouteConnector"):
		return
	# 接近道具或活动站位时生成的反向折线只是室外路网的临时接头。
	# 室内下一段工作必须从当前站位重新寻路；继续消费上一段折线会把
	# 居民先带回旧接近点，旧接近点经常就是建筑门口。
	if String(resident.get("spaceId", "")) != "town_outdoor":
		resident["routeConnector"] = []
		return
	resident["routeConnector"] = (
		action.get("returnRouteConnector", []) as Array
	).duplicate()


func _priority_action_settlement_reason(
	action: Dictionary,
	priority_reason: String,
) -> String:
	var action_label := _default_doing(action).strip_edges()
	if action_label.is_empty():
		action_label = "当前动作"
	var prefix := priority_reason.strip_edges()
	if prefix.is_empty() or prefix.contains("替换"):
		prefix = "优先事项到来"
	return "%s，%s先告一段落" % [prefix, action_label]


func _interrupt_action(
	resident_id: String,
	reason: String,
	settle_as_completed := false,
) -> void:
	var resident := _residents[resident_id] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	var outcome_status := "completed" if settle_as_completed else "interrupted"
	var outcome_reason := (
		_priority_action_settlement_reason(action, reason)
		if settle_as_completed
		else reason
	)
	var action_id := String(action.get("action_id", ""))
	var result_presentation := ACTION_PRESENTATION._preview_action_presentation(self, 
		resident,
		{"action": action},
	)
	if String(resident.get("spaceId", "")) != "town_outdoor":
		# Indoor navigation can always rebuild a path from the authoritative
		# current position. Keeping the reverse path of an interrupted activity
		# instead points later actions back to the previous prop and can make the
		# resident unable to find the building exit.
		resident["routeConnector"] = []
	var activity_execution := _activity_runtime.execution_for_action(
		resident_id,
		action_id,
	) as Dictionary
	if not activity_execution.is_empty():
		var source_action_id := _activity_source_action_id(
			action,
			activity_execution,
		)
		var interrupted := _activity_runtime.interrupt_action(
			resident_id,
			action_id,
			outcome_reason,
		) as Dictionary
		_settle_resident_activity_condition(
			resident_id,
			resident,
			action,
			activity_execution,
			"interrupted",
			reason,
		)
		resident["currentAction"] = {}
		resident["actionSuspendedAbsoluteMinute"] = -1
		resident["doing"] = outcome_reason
		if _activity_routines.has(resident_id):
			_close_activity_routine(
				resident_id,
				"interrupted",
				outcome_reason,
			)
		_bump_world_revision(false)
		# Persist the legacy result before any public lifecycle callback can
		# observe or save the interrupted state. Replacement remains no-schedule.
		if not source_action_id.is_empty():
			_append_action_result_without_schedule(
				resident_id,
				source_action_id,
				outcome_status,
				outcome_reason,
				result_presentation,
			)
		_notify_world_revision()
		_emit_activity_lifecycle(
			"interrupted",
			resident_id,
			interrupted.get("execution", activity_execution) as Dictionary,
			outcome_reason,
		)
		_emit_resident_state_changed(resident_id)
		return
	_record_matching_social_action_result(
		resident_id,
		action,
		outcome_status,
		outcome_reason,
	)
	if String(action.get("type", "")) == "去":
		_settle_resident_route_condition(
			resident_id,
			resident,
			action,
			"interrupted",
		)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = outcome_reason
	_queue_action_result(
		resident_id,
		action_id,
		outcome_status,
		outcome_reason,
		true,
		true,
		result_presentation,
	)
	_emit_resident_state_changed(resident_id)


func _finish_activity_action(resident_id: String) -> void:
	var resident := _residents[resident_id] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	var activity_execution := _activity_runtime.execution_for_action(
		resident_id,
		String(action.get("action_id", "")),
	) as Dictionary
	var source_action_id := _activity_source_action_id(
		action,
		activity_execution,
	)
	var result_presentation := ACTION_PRESENTATION._preview_action_presentation(self, 
		resident,
		{"action": action},
	)
	var completed := _activity_runtime.complete_action(
		resident_id,
		String(action.get("action_id", "")),
	) as Dictionary
	if completed.get("ok") != true:
		_fail_activity_action(
			resident_id,
			String(completed.get("errorCode", "ACTIVITY_STATE_CHANGED")),
			"活动完成提交失败",
		)
		return
	var applied_effects := completed.get("effects", {}) as Dictionary
	var resident_effects := applied_effects
	if _activity_routines.has(resident_id):
		var active_routine := _activity_routines[resident_id] as Dictionary
		if (
			String(active_routine.get("group", "")) == "work"
			and int(active_routine.get("sequence", 0)) > 0
		):
			# A work routine is one sustained life action. Later prop changes
			# provide movement and semantic presentation without repeatedly
			# charging the full, uncapped activity effect.
			resident_effects = {}
	var next_activity_state := _next_activity_state(
		resident,
		resident_effects,
	)
	var committed := _activity_runtime.commit_completion(
		resident_id,
		String(action.get("action_id", "")),
		applied_effects,
	) as Dictionary
	if committed.get("ok") != true:
		_fail_activity_action(
			resident_id,
			String(committed.get("errorCode", "ACTIVITY_STATE_CHANGED")),
			"活动效果提交失败",
		)
		return
	# commit_completion and this assignment share one synchronous World call;
	# no lifecycle emission or save boundary can occur between them.
	resident["activityState"] = next_activity_state
	_sync_body_from_activity_needs(resident, next_activity_state)
	# Completion callbacks need the reserved slot and physical target as well as
	# the public completion status. Preserve the internal execution metadata and
	# overlay the authoritative public result returned by the commit.
	var execution := activity_execution.duplicate(true)
	for key: Variant in (
		committed.get("execution", {}) as Dictionary
	):
		execution[key] = (
			committed.get("execution", {}) as Dictionary
		).get(key)
	# 仅用于本次同步完成回调，不能写回 Activity Runtime 存档。诊疗结果
	# 需要真实发生时长，不能把一次完整检查误记成 1 分钟。
	execution["performedDurationMinutes"] = maxi(
		1,
		int(action.get("durationMinutes", 1)),
	)
	if String(execution.get("activityId", "")) == SLEEP_ACTIVITY_ID:
		_clear_sleep_leave(resident)
	_restore_action_route_connector(resident, action)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = "已完成%s" % String(
		execution.get("label", "活动")
	)
	_bump_world_revision(false)
	# Queue and schedule the legacy result before lifecycle/state callbacks can
	# persist the completed execution. Direct activity.perform has no old result.
	if not source_action_id.is_empty():
		_queue_action_result(
			resident_id,
			source_action_id,
			"completed",
			"已完成%s" % String(execution.get("label", "活动")),
			true,
			true,
			result_presentation,
		)
	_notify_world_revision()
	_emit_activity_lifecycle(
		"completed",
		resident_id,
		execution,
		"完成",
	)
	_settle_resident_activity_condition(
		resident_id,
		resident,
		action,
		execution,
		"completed",
		"完成",
	)
	var action_after_lifecycle := (
		resident.get("currentAction", {}) as Dictionary
	)
	if not String(
		action_after_lifecycle.get("serviceRequestId", ""),
	).is_empty():
		return
	if _continue_activity_routine(resident_id):
		return
	_emit_resident_state_changed(resident_id)


func _continue_activity_routine(resident_id: String) -> bool:
	if not _activity_routines.has(resident_id):
		return false
	var resident := _residents[resident_id] as Dictionary
	# A synchronous callback may have installed a newer action; leave it intact.
	if not (resident.get("currentAction", {}) as Dictionary).is_empty():
		_close_activity_routine(
			resident_id,
			"interrupted",
			"居民改做另一件事，刚才的活动安排先收尾了",
		)
		return false
	var routine := _activity_routines[resident_id] as Dictionary
	if (
		String(resident.get("currentPlace", ""))
		!= String(routine.get("placeId", ""))
	):
		_close_activity_routine(
			resident_id,
			"interrupted",
			"离开地点，手头的事情先停下了",
		)
		return false
	var absolute_minute := int(_environment.get_absolute_minute())
	if absolute_minute >= int(routine.get("endAbsoluteMinute", 0)):
		_close_activity_routine(
			resident_id,
			"completed",
			_activity_routine_completion_text(
				String(routine.get("group", "")),
			),
		)
		return false
	var group := String(routine.get("group", ""))
	if (
		int(routine.get("sequence", 0)) + 1
		>= int(ACTIVITY_ROUTINE_MAX_STEPS.get(group, 1))
	):
		_close_activity_routine(
			resident_id,
			"completed",
			_activity_routine_completion_text(group),
		)
		return false
	var expected_phase := ""
	if group == "meal":
		match String(routine.get("lastPhase", "")):
			"collect":
				expected_phase = "consume"
			"consume":
				expected_phase = "cleanup"
			_:
				_close_activity_routine(
					resident_id,
					"completed",
					_activity_routine_completion_text(group),
				)
				return false
	var candidates := _activity_runtime.routine_candidates(
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		group,
	) as Array[Dictionary]
	var usable: Array[Dictionary] = []
	var visited_activity_ids := (
		routine.get("visitedActivityIds", []) as Array
	)
	for candidate: Dictionary in candidates:
		if not bool(candidate.get("available", false)):
			continue
		if (
			String(candidate.get("activityId", ""))
			== String(routine.get("lastActivityId", ""))
		):
			continue
		if (
			group == "work"
			and visited_activity_ids.has(
				String(candidate.get("activityId", "")),
			)
		):
			continue
		if (
			not expected_phase.is_empty()
			and String(candidate.get("phase", "")) != expected_phase
		):
			continue
		usable.append(candidate)
	if usable.is_empty():
		_close_activity_routine(
			resident_id,
			"completed",
			_activity_routine_completion_text(group),
		)
		return false
	usable.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("activityId", "")) < String(
			right.get("activityId", "")
		)
	)
	var next_sequence := int(routine.get("sequence", 0)) + 1
	var start_index := posmod(
		int(routine.get("choiceSeed", 0))
		+ next_sequence * 1103515245,
		usable.size(),
	)
	for offset in usable.size():
		var candidate := usable[(start_index + offset) % usable.size()]
		var step := {
			"stepId": "step-%d-%s" % [
				next_sequence,
				String(candidate.get("activityId", "")),
			],
			"operation": "activity.perform",
			"target": {
				"activityId": String(candidate.get("activityId", "")),
				"placeId": String(routine.get("placeId", "")),
			},
			"params": {
				"reason": String(candidate.get("label", "")),
			},
		}
		var performed := _perform_activity_step_internal(
			resident_id,
			String(routine.get("routineId", "")),
			0,
			step,
			ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_DIRECT,
			"",
			int(ACTIVITY_ROUTINE_STEP_CAP_MINUTES.get(group, 15)),
		)
		if performed.get("ok") != true:
			continue
		routine["sequence"] = next_sequence
		routine["lastActivityId"] = String(
			candidate.get("activityId", "")
		)
		routine["lastPhase"] = String(candidate.get("phase", ""))
		var next_activity_id := String(candidate.get("activityId", ""))
		var next_visited := (
			routine.get("visitedActivityIds", []) as Array
		).duplicate()
		if not next_visited.has(next_activity_id):
			next_visited.append(next_activity_id)
		routine["visitedActivityIds"] = next_visited
		_activity_routines[resident_id] = routine
		return true
	_close_activity_routine(
		resident_id,
		"completed",
		_activity_routine_completion_text(group),
	)
	return false


func _close_activity_routine(
	resident_id: String,
	status: String,
	reason: String,
) -> void:
	if not _activity_routines.has(resident_id):
		return
	var routine := _activity_routines[resident_id] as Dictionary
	_activity_routines.erase(resident_id)
	DINING_SERVICE.settle_closed_meal_routine(self, resident_id, routine, status)
	var resident := _residents[resident_id] as Dictionary
	resident["doing"] = reason
	var last_activity_id := String(
		routine.get("lastActivityId", "")
	).strip_edges()
	var result_presentation := (
		ACTION_PRESENTATION._preview_action_presentation(self, 
			resident,
			{
				"action": {
					"type": "做活动",
					"activity_id": last_activity_id,
				},
			},
		)
		if not last_activity_id.is_empty()
		else {}
	)
	_queue_action_result(
		resident_id,
		String(routine.get("sourceActionId", "")),
		status,
		reason,
		true,
		true,
		result_presentation,
	)


func _activity_routine_completion_text(group: String) -> String:
	return ACTION_PROJECTION_MODULE.activity_routine_completion_text(group)


func _fail_activity_action(
	resident_id: String,
	error_code: String,
	reason: String,
) -> void:
	var resident := _residents[resident_id] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	var execution := _activity_runtime.execution_for_action(
		resident_id,
		String(action.get("action_id", "")),
	) as Dictionary
	var source_action_id := _activity_source_action_id(
		action,
		execution,
	)
	var result_presentation := ACTION_PRESENTATION._preview_action_presentation(self, 
		resident,
		{"action": action},
	)
	var failed := _activity_runtime.fail_action(
		resident_id,
		String(action.get("action_id", "")),
		error_code,
	) as Dictionary
	_settle_resident_activity_condition(
		resident_id,
		resident,
		action,
		execution,
		"failed",
		reason,
	)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = reason
	if _activity_routines.has(resident_id):
		_close_activity_routine(
			resident_id,
			"rejected",
			reason,
		)
	_bump_world_revision(false)
	# The rejected legacy result must be save-visible before failed lifecycle
	# callbacks; otherwise a callback save can permanently lose the next wake.
	if not source_action_id.is_empty():
		_queue_action_result(
			resident_id,
			source_action_id,
			"rejected",
			reason,
			true,
			true,
			result_presentation,
		)
	_notify_world_revision()
	_emit_activity_lifecycle(
		"failed",
		resident_id,
		failed.get("execution", execution) as Dictionary,
		reason,
		error_code,
	)
	_emit_resident_state_changed(resident_id)


func _activity_source_action_id(
	action: Dictionary,
	execution: Dictionary,
) -> String:
	return ACTION_PROJECTION_MODULE.activity_source_action_id(action, execution)


func _action_still_valid(resident: Dictionary, action: Dictionary) -> bool:
	match String(action.get("type", "")):
		"去":
			var route := action.get("route", {}) as Dictionary
			var positions := route.get("minutePositions", []) as Array
			if positions.is_empty() or get_place_detail(String(action.get("place", ""))).is_empty():
				return false
			# 途中每分钟都会走到这里：只校验当前采样点；
			# 后续采样点等走到时自然会被校验，不必每次重放整条路线。
			var now := int(_environment.get_absolute_minute())
			var elapsed := maxi(
				0,
				now - int(action.get("startedAbsoluteMinute", now)),
			)
			var sample_value: Variant = positions[mini(
				elapsed,
				positions.size() - 1,
			)]
			if not sample_value is Dictionary:
				return false
			var sample := sample_value as Dictionary
			var position_value: Variant = sample.get("position")
			if not position_value is Dictionary:
				return false
			var point := position_value as Dictionary
			var membership := PERCEPTION_RUNTIME._membership(self, 
				String(sample.get("spaceId", "")),
				Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))),
			)
			if (
				membership.is_empty()
				or String(membership.get("regionId", "")) != String(sample.get("regionId", ""))
				or String(membership.get("placeName", "")) != String(sample.get("placeName", ""))
			):
				return false
			return true
		"用道具":
			var activity_execution := _activity_runtime.execution_for_action(
				String(resident.get("residentId", "")),
				String(action.get("action_id", "")),
			) as Dictionary
			if (
				not activity_execution.is_empty()
				and String(
					activity_execution.get("targetType", ""),
				) == "region"
			):
				var target_position := action.get(
					"targetPosition",
					Vector2(INF, INF),
				) as Vector2
				var target_membership := PERCEPTION_RUNTIME._membership(self, 
					"town_outdoor",
					target_position,
				)
				return (
					target_position.is_finite()
					and not (
						action.get("pathPoints", []) as Array
					).is_empty()
					and String(
						target_membership.get("placeName", ""),
					) == String(
						activity_execution.get("placeId", ""),
					)
				)
			if (
				not activity_execution.is_empty()
				and String(resident.get("currentPlace", ""))
				!= String(activity_execution.get("placeId", ""))
			):
				return false
			return not PROP_QUERY.interaction_plan(
				_prop_query_data(),
				String(action.get("sourcePlace", resident.get("currentPlace", ""))),
				String(action.get("prop", "")),
				String(action.get("verb", "")),
				resident.get("position", Vector2.ZERO) as Vector2,
			).is_empty()
		"调整营业":
			var control := _service_control_for_resident(resident)
			return (
				not control.is_empty()
				and String(control.get("place_id", ""))
				== String(action.get("place_id", ""))
				and bool(control.get("open", false))
				!= bool(action.get("open", false))
			)
		"托人传话":
			return (
				_residents.has(String(
					action.get("recipient_resident_id", ""),
				))
				and String(action.get("recipient_resident_id", ""))
				!= String(resident.get("residentId", ""))
			)
		"待着", "搭话", "答话":
			return true
		_:
			return false


func _queue_action_result(
	resident_name: String,
	action_id: String,
	status: String,
	reason: String,
	invalidate_request := true,
	schedule_request := true,
	presentation: Dictionary = {},
) -> void:
	if RESIDENT_ARRIVAL_RUNTIME.is_entry_continuity_action_id(resident_name, action_id): return
	var resident := _residents[resident_name] as Dictionary
	var result_presentation := presentation.duplicate(true)
	if result_presentation.is_empty():
		var current_action := resident.get("currentAction", {}) as Dictionary
		if String(
			current_action.get(
				"sourceActionId",
				current_action.get("action_id", ""),
			)
		).strip_edges() == action_id.strip_edges():
			var activity_cue: Variant = ACTION_PRESENTATION._resident_activity_cue(self, resident)
			var current_presentation: Variant = ACTION_PRESENTATION._resident_action_presentation(self, 
				resident,
				activity_cue,
			)
			if current_presentation is Dictionary:
				result_presentation = (
					current_presentation as Dictionary
				).duplicate(true)
	var result := {
		"residentId": resident_name,
		"action_id": action_id,
		"status": status,
		"reason": reason,
		"time": get_time(),
	}
	_apply_action_result_presentation(result, status, result_presentation)
	_append_or_replace_action_result(
		resident.get("resultQueue", []) as Array,
		result,
	)
	if bool(resident.get("decisionPending", false)):
		AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	_append_public_event_log(
		_next_world_event_id(),
		"action_result",
		resident_name,
		_resident_display_name(resident_name),
		String(resident.get("currentPlace", "")),
		result,
	)
	_record_story_action_outcome(
		resident_name,
		action_id,
		status,
		reason,
	)
	action_result_created.emit(_resident_display_name(resident_name), result.duplicate(true))
	if schedule_request:
		_schedule_decision(resident_name, invalidate_request)


func _apply_action_result_presentation(
	result: Dictionary,
	status: String,
	presentation: Dictionary,
) -> void:
	ACTION_SUPPORT.apply_action_result_presentation(result, status, presentation)


func _append_or_replace_action_result(
	queue: Array,
	result: Dictionary,
) -> void:
	ACTION_VALIDATION.append_or_replace_action_result(queue, result)


func _deduplicated_action_results(values: Array) -> Array[Dictionary]:
	return ACTION_VALIDATION.deduplicated_action_results(values)


func _complete_private_message_delivery(
	initiator_ref: String,
	target_ref: String,
	turn: Dictionary,
) -> void:
	var postal_resident_id := _resident_key(initiator_ref)
	var recipient_id := _resident_key(target_ref)
	if (
		postal_resident_id.is_empty()
		or recipient_id.is_empty()
	):
		return
	var spoken_content := String(turn.get("say", "")).strip_edges()
	if spoken_content.is_empty():
		return
	var message_ids: Array[String] = []
	for message_id_value: Variant in _private_messages:
		message_ids.append(String(message_id_value))
	message_ids.sort()
	for message_id: String in message_ids:
		var message := _private_messages.get(
			message_id,
			{},
		) as Dictionary
		if (
			String(message.get("state", "")) != "pending"
			or String(message.get("recipientResidentId", ""))
			!= recipient_id
			or String(message.get("content", "")).strip_edges()
			!= spoken_content
		):
			continue
		var task_id := String(message.get("taskId", ""))
		var task := _work_tasks.task(task_id) as Dictionary
		var assigned_resident_id := String(
			task.get("assignedResidentId", ""),
		)
		if (
			task.is_empty()
			or not _resident_can_accept_work_task(
				postal_resident_id,
				task,
			)
			or String(task.get("processStage", ""))
			!= "out_for_delivery"
			or String(task.get("state", "")) in [
				"completed",
				"failed",
				"cancelled",
			]
			or (
				not assigned_resident_id.is_empty()
				and assigned_resident_id != postal_resident_id
			)
		):
			continue
		if String(task.get("state", "")) in ["open", "waiting"]:
			var acceptance_occupation_id := _task_acceptance_occupation_id(
				postal_resident_id,
				task,
			)
			var accepted := _work_tasks.accept_task(
				task_id,
				postal_resident_id,
				acceptance_occupation_id,
				int(task.get("revision", 0)),
			) as Dictionary
			if accepted.get("ok") != true:
				continue
			task = accepted.get("task", {}) as Dictionary
		if String(task.get("state", "")) == "accepted":
			var started := _work_tasks.start_task(
				task_id,
				postal_resident_id,
				int(task.get("revision", 0)),
			) as Dictionary
			if started.get("ok") != true:
				continue
			task = started.get("task", {}) as Dictionary
		if (
			String(task.get("state", "")) != "in_progress"
			or String(task.get("assignedResidentId", ""))
			!= postal_resident_id
		):
			continue
		var delivered_at := int(
			_environment.get_absolute_minute(),
		)
		var completed := _work_tasks.complete_task(
			task_id,
			postal_resident_id,
			int(task.get("revision", 0)),
			"message_delivery",
			{
				"resultRef": "message-delivery:%s" % message_id,
				"facts": {
					"messageId": message_id,
					"senderResidentId": String(
						message.get("senderResidentId", ""),
					),
					"recipientResidentId": recipient_id,
					"deliveredByResidentId": postal_resident_id,
					"deliveredAtMinute": delivered_at,
					"originalContentDelivered": true,
				},
			},
		) as Dictionary
		if completed.get("ok") != true:
			continue
		message["state"] = "delivered"
		message["deliveredAtMinute"] = delivered_at
		message["deliveredByResidentId"] = postal_resident_id
		_private_messages[message_id] = message
		_activate_delivered_private_message_follow_up(
			message_id,
			message,
			delivered_at,
		)
		_compact_delivered_private_messages()
		_apply_delivered_announcement_notice(
			message_id,
			message,
			postal_resident_id,
			recipient_id,
			delivered_at,
		)
		_bump_world_revision()
		_append_private_message_log_event(
			"消息送达",
			message,
			"completed",
			postal_resident_id,
		)
		var sender_id := String(
			message.get("senderResidentId", ""),
		)
		if _residents.has(sender_id):
			_schedule_decision(sender_id, true)
		return


func _install_resident_escort_follower(
	guide_resident_id: String,
	action_goal: Dictionary,
) -> void:
	var target_refs := action_goal.get("target_refs", {}) as Dictionary
	var follower_id := String(target_refs.get("person_id", ""))
	if follower_id.is_empty() or not _residents.has(follower_id):
		return
	var follower := _residents.get(follower_id, {}) as Dictionary
	var destination := String(target_refs.get("place_id", ""))
	var prepared := _prepare_go_action(follower, {
		"action_id": "escort-follower:%s" % String(action_goal.get("goal_id", "")),
		"type": "去",
		"place": destination,
		"line": "我跟着带路人走",
	}) as Dictionary
	if prepared.get("ok") != true:
		_begin_conversation_follow_up_reconsideration(
			guide_resident_id,
			"同行者当前无法沿安全路线跟上，需要重新决定",
		)
		return
	var follower_action := (
		prepared.get("action", {}) as Dictionary
	).duplicate(true)
	CONVERSATION_RUNTIME._decorate_conversation_follow_up_action(self, 
		follower_action,
		"escort_follower",
		"following",
		{
			"person_id": guide_resident_id,
			"place_id": destination,
		},
	)
	(follower.get("usedActionIds", {}) as Dictionary)[String(
		follower_action.get("action_id", ""),
	)] = true
	_install_conversation_follow_up_action(
		follower_id,
		follower,
		follower_action,
		"正跟着%s前往%s" % [
			_person_name_for_id(guide_resident_id),
			destination,
		],
	)


func _trim_announcement_history() -> void:
	while _announcements.size() > MAX_ANNOUNCEMENT_HISTORY:
		_announcements.pop_front()


func _wake_packet(
	resident_name: String,
	resident: Dictionary,
	decision_id: String,
	events: Array,
	results: Array,
	social_results_value: Variant = null,
	prefetch_arrival_context: bool = false,
	frame_budgeted := false,
) -> Dictionary:
	var perception_resident := resident
	if prefetch_arrival_context:
		var arrival_projection := _go_action_arrival_projection(resident)
		if not arrival_projection.is_empty():
			perception_resident = resident.duplicate(true)
			perception_resident["spaceId"] = arrival_projection.get("spaceId", "")
			perception_resident["regionId"] = arrival_projection.get("regionId", "")
			perception_resident["currentPlace"] = arrival_projection.get("currentPlace", "")
			perception_resident["position"] = arrival_projection.get(
				"position",
				Vector2.ZERO,
			)
			# 这次唤醒是在为抵达后的下一步做决定，不能让 Agent 把仍在
			# 路上的“去”动作当成抵达后的可继续动作。
			perception_resident["currentAction"] = {}
	var nearby: Array[Dictionary] = []
	for other_name_value: Variant in resident.get("nearby", []) as Array:
		var other_name := String(other_name_value)
		var other := _person_state(other_name)
		nearby.append({
			"resident_id": _person_id_for_name(other_name),
			"name": _person_name_for_id(_person_id_for_name(other_name)),
			"doing": String(other.get("doing", "")),
			"available_for_conversation": CONVERSATION_RUNTIME._active_conversation_for_person(self, other_name).is_empty(),
		})
	var public_events := _agent_fact_payloads(events)
	var public_results := _agent_fact_payloads(results)
	var social_results: Array[Dictionary] = []
	if social_results_value is Array:
		for value: Variant in social_results_value as Array:
			if value is Dictionary:
				social_results.append(
					(value as Dictionary).duplicate(true)
				)
	else:
		social_results = _social_agent_adapter.take_social_response_results(
			resident_name,
		) as Array[Dictionary]
	var life_destination_options := _agent_life_destination_options(
		perception_resident,
	)
	var place_snapshot := {
		"name": String(perception_resident.get("currentPlace", "")),
		"destinations": _agent_travel_destinations(perception_resident),
		"visible_props": _agent_visible_props(perception_resident),
		"props": _agent_available_props(perception_resident),
		"activities": _agent_available_activities(
			perception_resident,
			frame_budgeted,
		),
		"service_control": _service_control_for_resident(perception_resident),
		"message_recipients": _ordinary_private_message_recipients(
			resident_name,
		),
	}
	DINING_SERVICE.attach_capacity_status(self, place_snapshot, String(perception_resident.get("residentId", "")), String(perception_resident.get("currentPlace", "")), int(_environment.get_absolute_minute()))
	var priority_service_task := _priority_onsite_service_task_for_resident(
		String(resident.get("residentId", "")),
	)
	if not priority_service_task.is_empty():
		_focus_agent_place_snapshot_on_service_task(
			perception_resident,
			place_snapshot,
			priority_service_task,
		)
	var nearby_ids: Array[String] = []
	for nearby_value: Variant in nearby:
		var nearby_id := String(
			(nearby_value as Dictionary).get("resident_id", "")
		).strip_edges()
		if not nearby_id.is_empty():
			nearby_ids.append(nearby_id)
	var conflict_snapshot := _agent_conflict_snapshot(
		resident_name,
		resident,
		nearby_ids,
	)
	var post_injury_reaction := _post_injury_reaction_for_events(
		resident_name,
		events,
	)
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": get_time(),
			"weather": get_weather(),
			"weather_context": _activity_runtime.weather_context(
				get_weather(),
				String(perception_resident.get("currentPlace", "")),
			),
			"me": {
				"doing": String(perception_resident.get("doing", "")),
				"current_action": ACTION_PRESENTATION._agent_current_action(
					self,
					perception_resident.get("currentAction", {}) as Dictionary,
				),
				"body": (perception_resident.get("body", {}) as Dictionary).duplicate(true),
				"activityNeeds": (
					perception_resident.get(
						"activityState",
						_empty_activity_state(),
					) as Dictionary
				).duplicate(true),
				"conditions": _resident_conditions.get_conditions(resident_name,) as Array,
				"activeNeeds": _resident_conditions.get_active_needs(resident_name,) as Array,
			},
			"nearby": nearby,
			"place": place_snapshot,
			"rhythm": _life_rhythm_snapshot(resident),
			"work_tasks": get_work_tasks_for_resident(resident_name),
			"life_destination_options": life_destination_options,
			"known_announcements": _agent_known_announcements(
				resident_name,
			),
			"conversation": _duplicate_optional_dictionary(resident.get("conversation")),
			"conversation_follow_up_options": _conversation_follow_up_options(
				resident_name,
				resident,
				public_events,
				frame_budgeted,
			),
			"social_matters": _social_agent_adapter.build_social_matters(
				resident_name,
				int(_environment.get_absolute_minute()),
			) as Array[Dictionary],
			"social_exposures": (
				[]
				if _inflight_requires_reply(events)
				else get_agent_social_exposures(resident_name)
			),
			"conflicts": (
				conflict_snapshot.get("conflicts", []) as Array
			).duplicate(true),
			"conflict_injuries": (
				conflict_snapshot.get("conflict_injuries", []) as Array
			).duplicate(true),
			"conflict_tension_options": (
				conflict_snapshot.get(
					"conflict_tension_options",
					[],
				) as Array
			).duplicate(true),
			"medical_follow_up": (
				conflict_snapshot.get(
					"medical_follow_up",
					{},
				) as Dictionary
			).duplicate(true),
			"post_injury_reaction": post_injury_reaction,
		},
		"events": public_events,
		"action_results": public_results,
		"social_response_results": social_results,
	}


func _priority_onsite_service_task_for_resident(
	resident_id: String,
) -> Dictionary:
	var selected: Dictionary = {}
	for projected_task: Dictionary in get_work_tasks_for_resident(
		resident_id,
	):
		var task := _work_tasks.task(String(projected_task.get("task_id", "")),) as Dictionary
		if (
			task.is_empty()
			or String(task.get("assignedResidentId", "")) != resident_id
			or String(task.get("state", ""))
			not in ["accepted", "in_progress", "waiting"]
		):
			continue
		var request := _occupation_services.request(String(task.get("sourceRef", "")),) as Dictionary
		if (
			request.is_empty()
			and String(task.get("capability", "")) == "food.production"
			and String(task.get("sourceKind", "")) == "meal_demand"
			and String(task.get("sourceRef", "")).begins_with("meal-period:")
		):
			if (
				selected.is_empty()
				or int(task.get("priority", 0))
				> int(selected.get("priority", 0))
			):
				selected = {
					"task_id": String(task.get("taskId", "")),
					"priority": int(task.get("priority", 0)),
					"place_id": CONTENT_CATALOG.PLACE_DINING_HALL,
				}
			continue
		if (
			request.is_empty()
			or String(request.get("kind", "")) == "clinic"
			or String(request.get("state", ""))
			not in ["pending", "waiting", "in_progress"]
			or String(
				(request.get("context", {}) as Dictionary).get(
					"customerServiceMode",
					"",
				),
			) != "onsite_wait"
		):
			continue
		if (
			selected.is_empty()
			or int(task.get("priority", 0))
			> int(selected.get("priority", 0))
		):
			selected = {
				"task_id": String(task.get("taskId", "")),
				"priority": int(task.get("priority", 0)),
				"place_id": String(request.get("placeId", "")),
			}
	return selected


func _focus_agent_place_snapshot_on_service_task(
	resident: Dictionary,
	place_snapshot: Dictionary,
	service_task: Dictionary,
) -> void:
	ACTION_SUPPORT.focus_agent_place_snapshot_on_service_task(resident, place_snapshot, service_task)


func _conversation_follow_up_options(
	resident_id: String,
	resident: Dictionary,
	events: Array,
	frame_budgeted := false,
	place_data: Dictionary = {},
) -> Array[Dictionary]:
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id)
	if (
		conversation.is_empty()
		or String(conversation.get("waitingFor", "")) != resident_id
		or not _inflight_allows_conversation_reply(
			events,
			String(conversation.get("conversationId", "")),
		)
		or _active_social_commitment_count(resident_id)
			>= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT
	):
		return []
	var options: Array[Dictionary] = []
	var partner_ref := CONVERSATION_RUNTIME._other_conversation_participant(self, 
		conversation,
		resident_id,
	)
	var partner_id := _person_id_for_name(partner_ref)
	var requested_place_ids := _conversation_requested_place_ids(
		conversation,
		resident_id,
	)
	var destinations: Array = _agent_travel_destinations(resident)
	if place_data.has("travelDestinations"):
		destinations = place_data.get("travelDestinations", []) as Array
	for place_id: String in destinations:
		if (
			not requested_place_ids.is_empty()
			and not requested_place_ids.has(place_id)
		):
			continue
		options.append({
			"option_id": "go:%s" % place_id,
			"meaning": "对话结束后本人前往%s" % place_id,
			"capability_id": "world.go_to_place",
			"target_refs": {"place_id": place_id},
			"success_result_id": "conversation-destination-reached",
			"place_id": place_id,
		})
		if not partner_id.is_empty():
			options.append({
				"option_id": "escort:%s:%s" % [partner_id, place_id],
				"meaning": "对话结束后带%s前往%s；同行者掉队时等待或折返，双方到达才算完成" % [
					_person_name_for_id(partner_id), place_id,
				],
				"capability_id": "world.escort_person_to_place",
				"target_refs": {
					"place_id": place_id,
					"person_id": partner_id,
				},
				"success_result_id": "conversation-escort-arrived",
				"place_id": place_id,
			})
	var activities: Array = _agent_available_activities(resident, frame_budgeted)
	if place_data.has("activities"):
		activities = place_data.get("activities", []) as Array
	for activity_value: Variant in activities:
		if (
			not requested_place_ids.is_empty()
			and not requested_place_ids.has(
				String(resident.get("currentPlace", "")),
			)
		):
			continue
		var activity := activity_value as Dictionary
		var activity_id := String(activity.get("activity_id", ""))
		var label := String(activity.get("label", ""))
		if activity_id.is_empty() or label.is_empty():
			continue
		options.append({
			"option_id": "activity:%s" % activity_id,
			"meaning": "对话结束后在%s实际进行“%s”" % [
				String(resident.get("currentPlace", "")), label,
			],
			"capability_id": "world.perform_activity",
			"target_refs": {
				"place_id": String(resident.get("currentPlace", "")),
				"activity_id": activity_id,
			},
			"success_result_id": "conversation-activity-completed",
			"place_id": String(resident.get("currentPlace", "")),
		})
	for nearby_value: Variant in resident.get("nearby", []) as Array:
		if not requested_place_ids.is_empty():
			continue
		var nearby_id := _resident_key(String(nearby_value))
		if nearby_id.is_empty() or nearby_id in [resident_id, partner_ref]:
			continue
		options.append({
			"option_id": "talk:%s" % nearby_id,
			"meaning": "对话结束后尝试与%s当面交谈" % _resident_display_name(nearby_id),
			"capability_id": "world.start_conversation",
			"target_refs": {"resident_id": nearby_id},
			"success_result_id": "conversation-follow-up-contacted",
			"place_id": String(resident.get("currentPlace", "")),
		})
	if not bool(place_data.get("skipServiceOfferings", false)) and not partner_id.is_empty():
		for offering: Dictionary in _conversation_service_fetch_offerings(resident):
			var service_place := String(offering.get("place_id", ""))
			if (
				not requested_place_ids.is_empty()
				and not requested_place_ids.has(service_place)
			):
				continue
			var service_activity := String(offering.get("activity_id", ""))
			var service_label := String(offering.get("service_label", ""))
			options.append({
				"option_id": "fetch-service:%s:%s:%s" % [
					partner_id, service_place, service_activity,
				],
				"meaning": "请%s等候，前往%s取得%s后返回对方身边" % [
					_person_name_for_id(partner_id), service_place, service_label,
				],
				"capability_id": "world.fetch_service_for_person",
				"target_refs": {
					"person_id": partner_id,
					"service_place_id": service_place,
					"service_activity_id": service_activity,
					"service_label": service_label,
				},
				"success_result_id": "conversation-service-delivered",
				"place_id": service_place,
			})
	if bool(place_data.get("skipNormalize", false)): return options
	return _unified_conversation_follow_up_options(
		resident_id,
		conversation,
		options,
	)


func _conversation_requested_place_ids(
	conversation: Dictionary,
	responding_resident_id: String,
) -> Array[String]:
	return ACTION_SUPPORT.conversation_requested_place_ids(self, conversation, responding_resident_id)


func _inflight_allows_conversation_reply(
	events: Array,
	conversation_id: String,
) -> bool:
	return ACTION_SUPPORT.inflight_allows_conversation_reply(events, conversation_id)


func _unified_conversation_follow_up_options(
	resident_id: String,
	conversation: Dictionary,
	legacy_options: Array,
) -> Array[Dictionary]:
	var context_ref := {
		"context_type": "conversation",
		"context_id": String(conversation.get("conversationId", "")),
		"context_revision": (conversation.get("turns", []) as Array).size(),
	}
	var adapted := _action_option_sources.adapt_legacy_options(resident_id,
		context_ref,
		legacy_options,
		"promisor",
		0,) as Dictionary
	if adapted.get("ok") != true:
		return []
	var candidates := (
		(adapted.get("value", {}) as Dictionary).get("candidates", []) as Array
	)
	var queried := _action_options.query_options(resident_id,
		context_ref,
		candidates,
		int(_environment.get_absolute_minute()),
		maxi(candidates.size(), 1),) as Dictionary
	if queried.get("ok") != true:
		return []
	var result: Array[Dictionary] = []
	for value: Variant in (queried.get("value", {}) as Dictionary).get("items", []) as Array:
		if value is not Dictionary:
			continue
		var option := (value as Dictionary).duplicate(true)
		var target_refs := option.get("target_refs", {}) as Dictionary
		var result_contract := option.get("result_contract", {}) as Dictionary
		option["meaning"] = String(option.get("label", ""))
		option["success_result_id"] = String(result_contract.get("success_result_id", ""))
		option["place_id"] = String(target_refs.get(
			"place_id",
			target_refs.get("service_place_id", ""),
		))
		result.append(option)
	return result


func _agent_conflict_snapshot(
	resident_id: String,
	resident: Dictionary,
	nearby_ids: Array[String],
) -> Dictionary:
	if _conflict_agent_world_bridge == null:
		return {
			"conflicts": [],
			"conflict_injuries": [],
			"conflict_tension_options": [],
			"medical_follow_up": {},
		}
	var snapshot := _conflict_agent_world_bridge.snapshot_for_actor(resident_id,
		nearby_ids,) as Dictionary
	snapshot["conflict_tension_options"] = _decorate_conflict_tension_options(
		resident_id,
		resident,
		snapshot.get("conflict_tension_options", []) as Array,
	)
	if _conflict_controller == null:
		snapshot["medical_follow_up"] = {}
		return snapshot
	var follow_up := _conflict_controller.get_follow_up(resident_id) as Dictionary
	if bool(follow_up.get("required", false)):
		snapshot["medical_follow_up"] = {
			"required": true,
			"kind": String(follow_up.get("kind", "go_to_clinic")),
			"priority": String(follow_up.get("priority", "urgent")),
			"reason": String(follow_up.get("reason", "heavy_injury")),
			"place_id": CONTENT_CATALOG.PLACE_CLINIC,
			"at_required_place": (
				String(resident.get("currentPlace", ""))
				== CONTENT_CATALOG.PLACE_CLINIC
			),
		}
	else:
		snapshot["medical_follow_up"] = {}
	return snapshot


func _post_injury_reaction_for_events(
	resident_id: String,
	events: Array,
) -> Dictionary:
	var latest: Dictionary = {}
	for value: Variant in events:
		if value is not Dictionary:
			continue
		var event := value as Dictionary
		if not CONFLICT_KNOWLEDGE_PROJECTOR.is_injury_subject(
			event,
			resident_id,
		):
			continue
		var actor_ids := event.get("actor_ids", []) as Array
		var attacker_id := String(event.get("source_actor_id", "")).strip_edges()
		if attacker_id.is_empty() or attacker_id == resident_id:
			for actor_value: Variant in actor_ids:
				var actor_id := String(actor_value).strip_edges()
				if not actor_id.is_empty() and actor_id != resident_id:
					attacker_id = actor_id
					break
		latest = {
			"required": true,
			"conflict_id": String(event.get("conflict_id", "")),
			"injury_event_id": String(
				event.get("conflict_event_id", event.get("event_id", "")),
			),
			"severity": String(event.get("severity", "")),
			"attacker_resident_id": attacker_id,
			"attacker_name": _person_name_for_id(attacker_id),
		}
	return latest
func _post_injury_reaction_action_error(
	resident: Dictionary,
	decision: Dictionary,
	reaction: Dictionary,
) -> String:
	if reaction.is_empty():
		return ""
	if String(decision.get("handling", "")) != "replace_current":
		return "刚刚受伤，必须先当面质问攻击者，或直接去诊所"
	var action := (
		decision.get("action", {}) as Dictionary
		if decision.get("action") is Dictionary
		else {}
	)
	var action_type := String(action.get("type", ""))
	var attacker_id := String(reaction.get("attacker_resident_id", ""))
	if action_type == "搭话":
		if (
			not attacker_id.is_empty()
			and String(action.get("target_resident_id", "")) == attacker_id
		):
			return ""
		return "刚刚受伤时只能先当面质问攻击者，不能先和其他人搭话"
	if action_type == "去":
		if String(action.get("place", "")) == CONTENT_CATALOG.PLACE_CLINIC:
			return ""
		return "刚刚受伤时只能直接去诊所；去诊所本身就是离开冲突现场"
	if (
		action_type == "待着"
		and String(resident.get("currentPlace", "")) == CONTENT_CATALOG.PLACE_CLINIC
	):
		return ""
	return "刚刚受伤时只能先当面质问攻击者，或直接去诊所"


func _settle_post_injury_conflict(
	resident_id: String,
	action_type: String,
	reaction: Dictionary,
) -> void:
	if _conflict_controller == null or reaction.is_empty():
		return
	var conflict_id := String(reaction.get("conflict_id", "")).strip_edges()
	if conflict_id.is_empty():
		return
	var response_kind := "deescalate" if action_type == "搭话" else "flee"
	_conflict_controller.respond(conflict_id, resident_id, response_kind)


func _decorate_conflict_tension_options(
	resident_id: String,
	resident: Dictionary,
	options: Array,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in options:
		if value is not Dictionary:
			continue
		var projected := (value as Dictionary).duplicate(true)
		if String(projected.get("kind", "")) != "challenge":
			result.append(projected)
			continue
		var target_id := String(
			projected.get("target_resident_id", ""),
		).strip_edges()
		# 玩家化身永远不是攻击候选：人设再凶也不对化身生成攻击原因。
		if target_id == _player_avatar_id():
			continue
		var cause := _resident_conflict_cause_for_target(resident, target_id)
		if cause.is_empty():
			cause = _resident_profile_conflict_motive(resident, target_id)
			if cause.is_empty():
				continue
			projected["option_id"] = "profile-attack:%s:%s" % [
				resident_id,
				target_id,
			]
			projected["kind"] = "attack"
			projected["tension_id"] = ""
		elif (
			not CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id).is_empty()
			and not _resident_profile_conflict_motive(resident, target_id).is_empty()
		):
			# 对话仍在进行时，真实事件先保留质问入口；若居民自身公开人设
			# 也确实支持动手，额外给出一次可选的结构化攻击出口。这样
			# “说到这里决定动手”仍由 Agent 明确选择，不把普通口角自动升级。
			var profile_cause := _resident_profile_conflict_motive(resident, target_id)
			var profile_attack := projected.duplicate(true)
			profile_attack["option_id"] = "profile-attack:%s:%s" % [resident_id, target_id]
			profile_attack["kind"] = "attack"
			profile_attack["tension_id"] = ""
			profile_attack["source_event_ids"] = []
			profile_attack["source_kind"] = String(profile_cause.get("sourceKind", ""))
			profile_attack["source_summary"] = String(profile_cause.get("summary", ""))
			profile_attack["source_conversation_id"] = ""
			profile_attack["meaning"] = (
				"这是本人公开人设形成的攻击倾向。想打就打，不需要对方先动手；"
				+ "动手时台词和动作描述必须符合本人身份与说话方式，让旁观者看得出"
				+ "“这就是他会做的事”。人设依据：%s"
				% String(profile_cause.get("summary", ""))
			)
			result.append(profile_attack)
		projected["source_event_ids"] = (
			cause.get("sourceEventIds", []) as Array
		).duplicate()
		projected["source_kind"] = String(cause.get("sourceKind", ""))
		projected["source_summary"] = String(cause.get("summary", ""))
		projected["source_conversation_id"] = String(
			cause.get("conversationId", ""),
		)
		if String(cause.get("sourceKind", "")) == "resident_profile_motive":
			projected["meaning"] = (
				"这是本人公开人设形成的攻击倾向。想打就打，不需要对方先动手；"
				+ "动手时台词和动作描述必须符合本人身份与说话方式，让旁观者看得出"
				+ "“这就是他会做的事”。人设依据：%s"
				% String(cause.get("summary", ""))
			)
		else:
			projected["meaning"] = (
				"只可依据本轮列出的真实事件当面质问；不能把怀疑当作事实。依据：%s"
				% String(cause.get("summary", ""))
			)
		result.append(projected)
	return result


func _resident_conflict_cause_for_target(
	resident: Dictionary,
	target_id: String,
) -> Dictionary:
	return CONFLICT_JUDGMENTS.resident_conflict_cause_for_target(resident, target_id)


func _resident_profile_conflict_motive(
	resident: Dictionary,
	target_id: String,
) -> Dictionary:
	var profile := {}
	var resident_id := String(resident.get("residentId", ""))
	var profiles := _opening.get("agentSoulProfiles", {}) as Dictionary
	if profiles.get(resident_id, {}) is Dictionary:
		profile = (profiles.get(resident_id, {}) as Dictionary).duplicate(true)
	return CONFLICT_JUDGMENTS.resident_profile_conflict_motive(
		resident,
		target_id,
		profile,
	)


func _agent_travel_destinations(resident: Dictionary) -> Array[String]:
	return _agent_wake_preparation_runtime.travel_destinations(self, resident)
func _agent_life_destination_options(
	resident: Dictionary,
	travel_destinations: Variant = null,
) -> Array[Dictionary]:
	var resident_id := String(resident.get("residentId", ""))
	if resident_id.is_empty():
		return []
	var has_work_tasks := not get_work_tasks_for_resident(
		resident_id,
	).is_empty()
	var sleep_needed := _resident_sleep_needed(resident)
	var meal_needed := int((resident.get("activityState", _empty_activity_state()) as Dictionary).get("satiety", 50)) <= 35
	# 平常仍由职业任务优先；精力或饥饿达到阈值时，生活选项不能被工作遮住。
	if has_work_tasks and not sleep_needed and not meal_needed:
		return []
	var social_state := resident.get("socialState", {}) as Dictionary
	var home_place := String(social_state.get("home", ""))
	var attributes := resident.get("attributes", {}) as Dictionary
	var interests: Variant = attributes.get("interests", [])
	var absolute_minute := int(_environment.get_absolute_minute())
	var minute_of_day := posmod(absolute_minute, 1440)
	var day_index := absolute_minute / 1440
	var result: Array[Dictionary] = []
	var destinations: Array = (
		travel_destinations
		if travel_destinations is Array
		else _agent_travel_destinations(resident)
	)
	for place_id: String in destinations:
		var query := _activity_runtime.query_options(
			resident_id,
			social_state,
			place_id,
			minute_of_day,
			get_weather(),
		) as Dictionary
		if query.get("ok") != true:
			continue
		var activities: Array[Dictionary] = []
		for option_value: Variant in query.get("options", []) as Array:
			var option := (option_value as Dictionary).duplicate(true)
			var activity_id := String(option.get("activityId", ""))
			if (
				not bool(option.get("available", false))
				or String(option.get("role", "")) == "worker"
				or activity_id not in NATURAL_LIFE_ACTIVITY_IDS
			):
				continue
			if activity_id == SLEEP_ACTIVITY_ID and (
				place_id != home_place or not sleep_needed
			):
				continue
			if has_work_tasks and not DINING_SERVICE.activity_allowed_during_work(activity_id):
				continue
			var matched := INTERESTS.matched_labels_for_activity(
				interests,
				_activity_runtime.activity_tags(activity_id),
			)
			activities.append({
				"activity_id": activity_id,
				"label": String(option.get("label", "")),
				"interest_match": not matched.is_empty(),
				"matched_interests": matched,
			})
		activities.sort_custom(
			func(left: Dictionary, right: Dictionary) -> bool:
				var left_match := bool(left.get("interest_match", false))
				var right_match := bool(right.get("interest_match", false))
				if left_match != right_match:
					return left_match
				return String(left.get("activity_id", "")) < String(
					right.get("activity_id", ""),
				)
		)
		if activities.size() > MAX_LIFE_ACTIVITIES_PER_DESTINATION:
			activities.resize(MAX_LIFE_ACTIVITIES_PER_DESTINATION)
		if activities.is_empty():
			continue
		result.append({
			"place_id": place_id,
			"activities": activities,
			"interest_match": activities.any(
				func(activity: Dictionary) -> bool:
					return bool(activity.get("interest_match", false)),
			),
			"rotation_key": posmod(
				hash("%s:%d:%s" % [resident_id, day_index, place_id]),
				2147483647,
			),
		})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_match := bool(left.get("interest_match", false))
			var right_match := bool(right.get("interest_match", false))
			if left_match != right_match:
				return left_match
			var left_rotation := int(left.get("rotation_key", 0))
			var right_rotation := int(right.get("rotation_key", 0))
			if left_rotation != right_rotation:
				return left_rotation < right_rotation
			return String(left.get("place_id", "")) < String(
				right.get("place_id", ""),
			)
	)
	if result.size() > MAX_LIFE_DESTINATION_OPTIONS:
		result.resize(MAX_LIFE_DESTINATION_OPTIONS)
	for option: Dictionary in result:
		option.erase("interest_match")
		option.erase("rotation_key")
	return result


func _agent_known_announcements(
	resident_id: String,
) -> Array[Dictionary]:
	return ANNOUNCEMENT_RESIDENT_RUNTIME.known_announcements(
		self,
		_community_bulletin,
		resident_id,
		MAX_AGENT_KNOWN_ANNOUNCEMENTS,
	)


func _agent_visible_props(resident: Dictionary) -> Array[String]:
	return _agent_wake_preparation_runtime.visible_props(self, resident)


func _agent_available_props(resident: Dictionary) -> Array:
	var result: Array = []
	var resident_id := String(resident.get("residentId", ""))
	for prop_value: Variant in PROP_QUERY.agent_props_at_place(
		_prop_query_data(),
		String(resident.get("currentPlace", "")),
	):
		var prop := prop_value as Dictionary
		var prop_name := String(prop.get("name", ""))
		var available_verbs: Array = []
		for verb_value: Variant in prop.get("verbs", []) as Array:
			var verb := String(verb_value)
			if verb == "睡觉" and not _resident_sleep_needed(resident):
				continue
			var action := {
				"prop": prop_name,
				"verb": verb,
			}
			if _is_dynamic_prop_action(resident, action):
				if (
					_direct_prop_action_available(
						resident_id,
						resident,
						action,
					)
					and _prepare_prop_action(
						resident,
						{
							"action_id": "prop-query-preflight",
							"type": "用道具",
							"prop": prop_name,
							"verb": verb,
							"line": verb,
						},
					).get("ok") == true
				):
					available_verbs.append(verb)
				continue
			var availability := _activity_runtime.legacy_activity_candidates(
				resident.get("socialState", {}) as Dictionary,
				String(resident.get("currentPlace", "")),
				prop_name,
				verb,
			) as Dictionary
			if availability.get("ok") != true:
				if (
					_is_layout_override_prop_action(resident, action)
					and _direct_prop_action_available(
						resident_id,
						resident,
						action,
					)
					and _prepare_prop_action(
						resident,
						{
							"action_id": "prop-query-preflight",
							"type": "用道具",
							"prop": prop_name,
							"verb": verb,
							"line": verb,
						},
					).get("ok") == true
				):
					available_verbs.append(verb)
				continue
			for candidate_value: Variant in availability.get(
				"candidates",
				[],
			) as Array:
				var candidate := candidate_value as Dictionary
				var activity_id := String(
					candidate.get("activityId", ""),
				)
				if not _work_task_available_for_activity(
					resident_id,
					resident,
					activity_id,
					String(candidate.get("role", "")),
				):
					continue
				var weather_availability := _activity_runtime.activity_weather_availability(
					activity_id,
					String(
						candidate.get("placeId", "")
					),
					String(candidate.get("role", "")),
					get_weather(),
				) as Dictionary
				if (
					bool(
						weather_availability.get(
							"available",
							false,
						)
					)
					and
					bool(candidate.get("memberAvailable", false))
					and _activity_query_candidate_reachable(
						resident,
						candidate,
						verb,
					)
				):
					available_verbs.append(verb)
					break
		if not available_verbs.is_empty():
			result.append({
				"name": prop_name,
				"verbs": available_verbs,
			})
	return result


func _life_rhythm_snapshot(resident: Dictionary = {}) -> Dictionary:
	var minute_of_day := posmod(
		int(_environment.get_absolute_minute()),
		1440,
	)
	var social_state := resident.get("socialState", {}) as Dictionary
	var schedule_context := _activity_runtime.schedule_context(
		social_state,
		minute_of_day,
	) as Dictionary
	return ACTIVITY_SCALARS.life_rhythm_snapshot(
		resident,
		minute_of_day,
		schedule_context,
	)


func _schedule_life_rhythm_decisions(absolute_minute: int) -> void:
	var minute_of_day := posmod(absolute_minute, 1440)
	for resident_index in _resident_order.size():
		var stagger_minutes := (
			(resident_index % 8) * 2
			+ floori(resident_index / 8.0)
		)
		for anchor_value: Variant in LIFE_RHYTHM_ANCHORS:
			var anchor := anchor_value as Dictionary
			if (
				minute_of_day
				== int(anchor.get("minute", -1)) + stagger_minutes
			):
				_schedule_decision(
					_resident_order[resident_index],
					false,
				)
				break


func _agent_fact_payloads(values: Array) -> Array[Dictionary]:
	return ACTION_SUPPORT.agent_fact_payloads(values)


func _agent_places() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in _world_data.get("places", []) as Array:
		var place := value as Dictionary
		var place_name := String(place.get("name", ""))
		var place_type := String(place.get("type", ""))
		var owner: Variant = null if place_type == "公共地点" else _owners.get(place_name)
		result.append({
			"name": place_name,
			"type": place_type,
			"owner": null if owner == null else _person_name_for_id(String(owner)),
			"owner_resident_id": owner,
			"summary": String(place.get("summary", "")),
			"features": (
				place.get("visibleFeatures", []) as Array
			).duplicate(true),
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.get("name", "")) < String(right.get("name", "")))
	return result


func _connect_work_task_log_source() -> void:
	if _work_tasks == null or not _work_tasks.has_signal("task_committed"):
		return
	var callback := _on_work_task_committed_for_log
	if not _work_tasks.is_connected("task_committed", callback):
		_work_tasks.connect("task_committed", callback)


func _disconnect_work_task_log_source() -> void:
	if _work_tasks == null or not _work_tasks.has_signal("task_committed"):
		return
	var callback := _on_work_task_committed_for_log
	if _work_tasks.is_connected("task_committed", callback):
		_work_tasks.disconnect("task_committed", callback)


func _on_work_task_committed_for_log(task: Dictionary) -> void:
	if not _running:
		return
	var task_id := String(task.get("taskId", "")).strip_edges()
	var revision := int(task.get("revision", 0))
	if task_id.is_empty() or revision < 1:
		return
	var state := String(task.get("state", "open"))
	var payload := {
		"type": _work_task_log_event_type(state, revision),
		"taskId": task_id,
		"taskRevision": revision,
		"status": state,
		"capability": String(task.get("capability", "")),
		"sourceKind": String(task.get("sourceKind", "")),
		"sourceRef": String(task.get("sourceRef", "")),
		"requestedResultKind": String(task.get("requestedResultKind", "")),
		"waitReason": String(task.get("waitReason", "")),
		"targets": (task.get("targets", []) as Array).duplicate(true),
		"result": (task.get("result", {}) as Dictionary).duplicate(true),
	}
	var participant_ids: Array[String] = []
	var assigned_resident_id := String(
		task.get("assignedResidentId", ""),
	).strip_edges()
	if not assigned_resident_id.is_empty():
		participant_ids.append(assigned_resident_id)
	var place_name := ""
	for target_value: Variant in task.get("targets", []) as Array:
		if not target_value is Dictionary:
			continue
		var target := target_value as Dictionary
		var target_kind := String(target.get("kind", ""))
		var target_ref := String(target.get("ref", "")).strip_edges()
		match target_kind:
			"resident":
				if not target_ref.is_empty() and not participant_ids.has(target_ref):
					participant_ids.append(target_ref)
			"service_request":
				payload["requestId"] = target_ref
			"cargo_lot":
				payload["cargoLotId"] = target_ref
			"public_matter":
				payload["matterId"] = target_ref
			"place", "region", "route", "audience_area":
				if place_name.is_empty():
					place_name = target_ref
	_apply_work_task_log_associations(payload, task)
	payload["participantIds"] = participant_ids
	_append_world_log_event(
		"work-task:%s:revision:%d" % [task_id, revision],
		"work_task",
		assigned_resident_id,
		_resident_display_name(assigned_resident_id),
		place_name,
		payload,
	)


func _apply_work_task_log_associations(
	payload: Dictionary,
	task: Dictionary,
) -> void:
	ACTION_SUPPORT.apply_work_task_log_associations(payload, task)


func _work_task_log_event_type(state: String, revision: int) -> String:
	return RUNTIME_LOG_TEXT.work_task_log_event_type(state, revision)


func _append_cargo_log_event(
	event_type: String,
	lot: Dictionary,
	actor_resident_id: String,
	status: String,
) -> void:
	var lot_id := String(lot.get("lotId", "")).strip_edges()
	if lot_id.is_empty():
		return
	var participant_ids: Array[String] = []
	for resident_id_value: Variant in [
		actor_resident_id,
		lot.get("carrierResidentId", ""),
	]:
		var resident_id := String(resident_id_value).strip_edges()
		if not resident_id.is_empty() and not participant_ids.has(resident_id):
			participant_ids.append(resident_id)
	var source_place_id := String(lot.get("sourcePlaceId", ""))
	var destination_place_id := String(lot.get("destinationPlaceId", ""))
	var place_id := (
		destination_place_id
		if event_type in ["货批到货", "货批入库"]
		else source_place_id
	)
	_append_world_log_event(
		_next_world_event_id(),
		"cargo_event",
		actor_resident_id,
		_resident_display_name(actor_resident_id),
		place_id,
		{
			"type": event_type,
			"cargoLotId": lot_id,
			"status": status,
			"participantIds": participant_ids,
			"itemId": String(lot.get("itemId", "")),
			"quantity": int(lot.get("quantity", 0)),
			"sourcePlaceId": source_place_id,
			"destinationPlaceId": destination_place_id,
			"carrierResidentId": String(lot.get("carrierResidentId", "")),
			"carrierName": _resident_display_name(
				String(lot.get("carrierResidentId", "")),
			),
			"cargoState": String(lot.get("state", "")),
		},
	)


func _append_service_log_event(
	request: Dictionary,
	task: Dictionary,
	worker_resident_id: String,
	outcome: Dictionary,
) -> void:
	var request_id := String(request.get("requestId", "")).strip_edges()
	if request_id.is_empty():
		return
	var service_kind := String(request.get("kind", "")).strip_edges()
	var requester_id := String(request.get("requesterResidentId", "")).strip_edges()
	var participant_ids: Array[String] = []
	for resident_id: String in [requester_id, worker_resident_id]:
		if not resident_id.is_empty() and not participant_ids.has(resident_id):
			participant_ids.append(resident_id)
	var audience_value: Variant = outcome.get("audienceResidentIds", [])
	if audience_value is Array:
		for resident_id_value: Variant in audience_value as Array:
			var resident_id := String(resident_id_value).strip_edges()
			if not resident_id.is_empty() and not participant_ids.has(resident_id):
				participant_ids.append(resident_id)
	var completed_request := _occupation_services.request(request_id) as Dictionary
	var status := String(completed_request.get("state", "completed"))
	_append_world_log_event(
		_next_world_event_id(),
		"service_result",
		worker_resident_id,
		_resident_display_name(worker_resident_id),
		String(request.get("placeId", "")),
		{
			"type": _service_log_event_type(service_kind),
			"requestId": request_id,
			"taskId": String(task.get("taskId", "")),
			"serviceKind": service_kind,
			"status": status,
			"participantIds": participant_ids,
			"requesterResidentId": requester_id,
			"requesterName": _resident_display_name(requester_id),
			"workerResidentId": worker_resident_id,
			"workerName": _resident_display_name(worker_resident_id),
			"itemId": String(request.get("itemId", "")),
			"outcome": outcome.duplicate(true),
		},
	)


func _service_log_event_type(service_kind: String) -> String:
	return RUNTIME_LOG_TEXT.service_log_event_type(service_kind)


func _append_private_message_log_event(
	event_type: String,
	message: Dictionary,
	status: String,
	delivered_by_resident_id := "",
) -> void:
	var message_id := String(message.get("messageId", "")).strip_edges()
	if message_id.is_empty():
		return
	var sender_id := String(message.get("senderResidentId", ""))
	var recipient_id := String(message.get("recipientResidentId", ""))
	var participant_ids: Array[String] = []
	for resident_id_value: Variant in [
		sender_id,
		recipient_id,
		delivered_by_resident_id,
	]:
		var resident_id := String(resident_id_value).strip_edges()
		if not resident_id.is_empty() and not participant_ids.has(resident_id):
			participant_ids.append(resident_id)
	_append_world_log_event(
		_next_world_event_id(),
		"private_message",
		sender_id,
		_resident_display_name(sender_id),
		"",
		{
			"type": event_type,
			"messageId": message_id,
			"taskId": String(message.get("taskId", "")),
			"status": status,
			"participantIds": participant_ids,
			"senderResidentId": sender_id,
			"senderName": _resident_display_name(sender_id),
			"recipientResidentId": recipient_id,
			"recipientName": _resident_display_name(recipient_id),
			"deliveredByResidentId": String(delivered_by_resident_id),
			"deliveredByName": _resident_display_name(delivered_by_resident_id),
			"content": String(message.get("content", "")),
			"messageKind": String(message.get("messageKind", "private")),
			"announcementId": String(message.get("announcementId", "")),
			"sourceRef": String(message.get("sourceRef", "")),
			"reason": String(message.get("reason", "")),
		},
	)


func _sanitize_public_event_payload(payload: Dictionary) -> Dictionary:
	var sanitized := payload.duplicate(true)
	sanitized.erase("storyEventId")
	sanitized.erase("storyType")
	sanitized.erase("storyRootEventIds")
	return sanitized


func _append_animal_log_event(
	event_type: String,
	fact: Dictionary,
	actor_resident_id := "",
	actor_name := "",
) -> void:
	var animal_id := String(fact.get("animal_id", "")).strip_edges()
	if animal_id.is_empty():
		return
	var display_name := String(fact.get("display_name", "")).strip_edges()
	_append_world_log_event(
		_next_world_event_id(),
		"animal_event",
		actor_resident_id,
		actor_name,
		String(fact.get("place_id", "")),
		{
			"type": event_type,
			"animalId": animal_id,
			"animalName": display_name,
			"species": String(fact.get("species", "")),
			"exists": bool(fact.get("exists", false)),
			"placeId": String(fact.get("place_id", "")),
			"generation": int(fact.get("generation", 0)),
			"publicAttention": bool(fact.get("public_attention", false)),
			"status": "completed",
		},
	)


func record_player_animal_pet(animal_id: String) -> Dictionary:
	var normalized := animal_id.strip_edges()
	var fact := _animal_facts.get(normalized, {}) as Dictionary
	if normalized.is_empty() or fact.is_empty() or not bool(fact.get("exists", false)):
		return _command_failure(
			"ANIMAL_FACT_UNKNOWN",
			["只能记录当前确实存在的动物互动"],
		)
	_append_animal_log_event("抚摸动物", fact, "", "玩家")
	return _decorate_command_result({
		"ok": true,
		"changed": true,
		"status": "recorded",
		"animalId": normalized,
	})


func _append_public_event_log(
	event_id: String,
	kind: String,
	resident_id: String,
	resident_name: String,
	place_name: String,
	payload: Dictionary,
) -> void:
	var normalized_id := event_id.strip_edges()
	var normalized_kind := kind.strip_edges()
	if normalized_id.is_empty() or normalized_kind.is_empty():
		return
	var normalized_resident_id := resident_id.strip_edges()
	var normalized_resident_name := resident_name.strip_edges()
	if normalized_resident_id.is_empty():
		normalized_resident_name = ""
	for existing in _public_event_log:
		if String(existing.get("eventId", "")) == normalized_id:
			return
	var public_record := {
		"eventId": normalized_id,
		"kind": normalized_kind,
		"time": get_time(),
		"worldRevision": _world_revision,
		"residentId": normalized_resident_id,
		"residentName": normalized_resident_name,
		"placeName": place_name.strip_edges(),
		"payload": payload.duplicate(true),
	}
	_public_event_log.append(public_record)
	_append_world_log_source(public_record)
	if _public_event_log.size() > 200:
		_public_event_log.pop_front()


func _append_world_log_event(
	event_id: String,
	kind: String,
	resident_id: String,
	resident_name: String,
	place_name: String,
	payload: Dictionary,
) -> void:
	var normalized_id := event_id.strip_edges()
	var normalized_kind := kind.strip_edges()
	if normalized_id.is_empty() or normalized_kind.is_empty():
		return
	_append_world_log_source({
		"eventId": normalized_id,
		"kind": normalized_kind,
		"time": get_time(),
		"worldRevision": _world_revision,
		"residentId": resident_id.strip_edges(),
		"residentName": resident_name.strip_edges(),
		"placeName": place_name.strip_edges(),
		"payload": payload.duplicate(true),
	})


func _append_world_log_source(source: Dictionary) -> void:
	if not _world_log_capture_enabled:
		return
	# 高频感知事件（有人来了/走了）会被 store 排除；过滤要在深拷贝
	# 和参与者快照构建之前做，否则化身走动时白付两次全量拷贝。
	if not _world_log_store.should_capture_public_event(source):
		return
	var world_log_record := source.duplicate(true)
	var payload := world_log_record.get("payload", {}) as Dictionary
	world_log_record["payload"] = _world_log_payload_with_snapshots(
		payload,
		String(world_log_record.get("residentId", "")),
		String(world_log_record.get("residentName", "")),
	)
	var world_log_result := _world_log_store.append_public_event(
		world_log_record,
	) as Dictionary
	if world_log_result.get("ok") != true:
		_world_log_consistency_error = String(
			world_log_result.get(
				"errorCode",
				"WORLD_LOG_RECORD_INVALID",
			),
		)
		return
	if world_log_result.get("changed") != true:
		return
	world_log_changed.emit({
		"sourceEventId": String(world_log_record.get("eventId", "")),
		"sourceKind": String(world_log_record.get("kind", "")),
		"appended": int(world_log_result.get("appended", 0)),
		"latestSequence": int(world_log_result.get("latestSequence", 0)),
	})


func _world_log_payload_with_snapshots(
	payload: Dictionary,
	resident_id: String,
	resident_name: String,
) -> Dictionary:
	var result := payload.duplicate(true)
	var participant_ids: Array[String] = []
	if not resident_id.is_empty():
		participant_ids.append(resident_id)
	for key in [
		"participant_resident_ids",
		"participantIds",
		"resident_ids",
	]:
		var values: Variant = result.get(key, [])
		if not values is Array:
			continue
		for value: Variant in values as Array:
			var participant_id := String(value).strip_edges()
			if (
				not participant_id.is_empty()
				and not participant_ids.has(participant_id)
			):
				participant_ids.append(participant_id)
	var snapshots: Array[Dictionary] = []
	for participant_id: String in participant_ids:
		var display_name := _person_name_for_id(participant_id).strip_edges()
		if display_name.is_empty() and participant_id == resident_id:
			display_name = resident_name
		if display_name.is_empty():
			display_name = participant_id
		snapshots.append({
			"residentId": participant_id,
			"displayName": display_name,
		})
	result["participantSnapshots"] = snapshots
	return result

func query_world_log_threads(filters: Dictionary = {}) -> Dictionary:
	return _world_log_store.query_threads(filters.duplicate(true)) as Dictionary


func query_world_log_place_observations(
	place_id: String,
	options: Dictionary = {},
) -> Dictionary:
	return _world_log_store.query_place_observations(
		place_id,
		options.duplicate(true),
	) as Dictionary


func find_world_log_thread_by_source_event(event_id: String) -> Dictionary:
	return _world_log_store.find_thread_by_source_event(event_id) as Dictionary


func get_world_log_causal_chain(thread_id: String, options: Dictionary = {}) -> Dictionary:
	return _world_log_store.get_causal_chain(thread_id, options.duplicate(true)) as Dictionary


func get_world_log_thread_detail(thread_id: String, options: Dictionary = {}) -> Dictionary:
	return _world_log_store.get_thread_detail(thread_id, options.duplicate(true)) as Dictionary


func mark_world_log_thread_read(thread_id: String, displayed_through_sequence: int) -> Dictionary:
	return _world_log_store.mark_thread_read(thread_id, displayed_through_sequence) as Dictionary


func get_world_log_filter_catalog() -> Dictionary:
	return _world_log_store.get_filter_catalog() as Dictionary


func get_world_log_debug_snapshot() -> Dictionary:
	return {
		"timelineId": String(_world_log_store.get_timeline_id()),
		"recordCount": int(_world_log_store.get_record_count()),
		"consistencyError": _world_log_consistency_error,
	}


func _next_world_event_id() -> String:
	_event_sequence += 1
	return "world-event-%d" % _event_sequence


func _safe_activity_execution(execution: Dictionary) -> Dictionary:
	return ACTIVITY_SCALARS.safe_activity_execution(execution)


func _activity_progress_doing(
	execution: Dictionary,
	performing_minutes: int,
) -> String:
	return ACTIVITY_SCALARS.activity_progress_doing(execution, performing_minutes)


func _emit_activity_lifecycle(
	lifecycle: String,
	resident_id: String,
	execution: Dictionary,
	reason: String,
	_error_code := "",
) -> void:
	if execution.is_empty():
		return
	if lifecycle == "started":
		_start_matching_social_activity(resident_id, execution)
		_record_started_clinic_request(resident_id, execution)
	elif lifecycle in ["completed", "interrupted", "failed"]:
		if lifecycle == "completed":
			WORK_SETTLEMENT.settle_completed_activity(
				self,
				resident_id,
				execution,
			)
		_release_work_task_from_activity(
			resident_id,
			execution,
			lifecycle,
		)
		var bulletin_effect := {}
		if lifecycle == "completed":
			bulletin_effect = _complete_bulletin_activity_effect(
				resident_id,
				execution,
			)
		_record_matching_social_activity_result(
			resident_id,
			execution,
			_social_execution_status(lifecycle),
			reason,
			bulletin_effect,
		)
		if lifecycle == "completed":
			_apply_place_service_activity_completion(
				execution,
			)
	var label := String(
		execution.get(
			"label",
			execution.get("activityLabel", "活动"),
		)
	)
	var result_text := ""
	match lifecycle:
		"started":
			result_text = "开始%s" % label
		"completed":
			result_text = "完成%s" % label
		"interrupted":
			result_text = "%s被中断" % label
		"failed":
			result_text = "%s未能完成" % label
		_:
			return
	if not reason.strip_edges().is_empty() and lifecycle in [
		"interrupted",
		"failed",
	]:
		result_text = "%s：%s" % [result_text, reason.strip_edges()]
	var event := {
		"activityId": String(execution.get("activityId", "")),
		"label": label,
		"baseIconKey": ACTION_PRESENTATION.activity_icon_key(
			String(execution.get("activityId", ""))
		),
		"phase": lifecycle,
		"placeId": String(execution.get("placeId", "")),
		"role": String(execution.get("role", "")),
		"result": result_text,
		"time": get_time(),
	}
	_event_sequence += 1
	_append_public_event_log(
		"resident-activity:%d" % _event_sequence,
		"resident_activity",
		resident_id,
		_resident_display_name(resident_id),
		String(execution.get("placeId", "")),
		event,
	)
	match lifecycle:
		"started":
			resident_activity_started.emit(resident_id, event.duplicate(true))
		"completed":
			resident_activity_completed.emit(resident_id, event.duplicate(true))
		"interrupted":
			resident_activity_interrupted.emit(resident_id, event.duplicate(true))
		"failed":
			resident_activity_failed.emit(resident_id, event.duplicate(true))


func _decision_story_provenance(
	events: Array,
	action_results: Array,
) -> Dictionary:
	var source_event_ids: Array[String] = []
	var root_event_ids: Array[String] = []
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		var event_type := String(event.get("type", ""))
		if event_type not in [
			"公告发布",
			"公告阅读",
			"公告转告",
			"天气变了",
			"搭话",
			"对方答话",
			"对话结束",
		]:
			continue
		_append_unique_story_ids(
			source_event_ids,
			[event.get("event_id", "")],
		)
		var event_id := String(event.get("event_id", ""))
		var inherited_roots := _story_root_ids_for_world_event(
			event_id
		)
		if inherited_roots.is_empty():
			_append_unique_story_ids(
				root_event_ids,
				[event_id],
			)
		else:
			_append_unique_story_ids(
				root_event_ids,
				inherited_roots,
			)
	for result_value: Variant in action_results:
		if not result_value is Dictionary:
			continue
		var result := result_value as Dictionary
		var result_story := _story_context_for_action(
			String(result.get("action_id", ""))
		)
		_append_unique_story_ids(
			source_event_ids,
			result_story.get("sourceEventIds", []) as Array,
		)
		_append_unique_story_ids(
			root_event_ids,
			result_story.get("rootEventIds", []) as Array,
		)
	return {
		"sourceEventIds": source_event_ids,
		"rootEventIds": root_event_ids,
	}


func _story_root_ids_for_world_event(
	event_id: String,
) -> Array:
	if event_id.is_empty():
		return []
	for reverse_index in _public_event_log.size():
		var index := _public_event_log.size() - reverse_index - 1
		var record := _public_event_log[index] as Dictionary
		if String(record.get("eventId", "")) != event_id:
			continue
		var payload := record.get("payload", {}) as Dictionary
		return (
			payload.get("storyRootEventIds", []) as Array
		).duplicate(true)
	return []


func _record_story_action_started(
	resident_id: String,
	action: Dictionary,
	provenance: Dictionary,
) -> void:
	var root_event_ids := (
		provenance.get("rootEventIds", []) as Array
	).duplicate(true)
	if root_event_ids.is_empty():
		return
	if String(action.get("type", "")) == "待着":
		return
	var action_id := String(action.get("action_id", ""))
	if action_id.is_empty():
		return
	var story_event_id := "story-action:%s:%s" % [
		resident_id,
		action_id,
	]
	var context := {
		"sourceEventIds": [],
		"rootEventIds": root_event_ids,
		"directCauseEventIds": (
			provenance.get("sourceEventIds", []) as Array
		).duplicate(true),
		"actionType": String(action.get("type", "")),
		"line": _default_doing(action),
		"prop": String(action.get("prop", "")),
		"verb": String(action.get("verb", "")),
		"place": String(action.get("place", "")),
		"residentId": resident_id,
	}
	var public_story_event_id := _append_story_event(
		story_event_id,
		"action_started",
		resident_id,
		String((_residents[resident_id] as Dictionary).get(
			"currentPlace",
			""
		)),
		{
			"actionId": action_id,
			"actionType": String(action.get("type", "")),
			"line": _default_doing(action),
			"prop": String(action.get("prop", "")),
			"verb": String(action.get("verb", "")),
			"place": String(action.get("place", "")),
			"participantLabels": [
				_resident_display_name(resident_id),
			],
			"causedByEventIds": (
				context.get("directCauseEventIds", []) as Array
			).duplicate(true),
			"storyRootEventIds": root_event_ids,
		},
	)
	context["sourceEventIds"] = [public_story_event_id]
	_action_story_context[action_id] = context


func _record_story_action_outcome(
	resident_id: String,
	action_id: String,
	status: String,
	reason: String,
) -> void:
	var context := _story_context_for_action(action_id)
	if context.is_empty():
		return
	if String(context.get("actionType", "")) in [
		"去",
		"待着",
		"搭话",
		"答话",
	]:
		return
	_append_story_event(
		"story-result:%s:%s:%s" % [
			resident_id,
			action_id,
			status,
		],
		"action_outcome",
		resident_id,
		String((_residents[resident_id] as Dictionary).get(
			"currentPlace",
			""
		)),
		{
			"actionId": action_id,
			"actionType": String(context.get("actionType", "")),
			"line": String(context.get("line", "")),
			"prop": String(context.get("prop", "")),
			"verb": String(context.get("verb", "")),
			"place": String(context.get("place", "")),
			"status": status,
			"reason": reason,
			"participantLabels": [
				_resident_display_name(resident_id),
			],
			"causedByEventIds": (
				context.get("sourceEventIds", []) as Array
			).duplicate(true),
			"storyRootEventIds": (
				context.get("rootEventIds", []) as Array
			).duplicate(true),
		},
	)


func _story_context_for_action(action_id: String) -> Dictionary:
	if action_id.is_empty() or not _action_story_context.has(action_id):
		return {}
	return (
		_action_story_context[action_id] as Dictionary
	).duplicate(true)


func _append_story_event(
	event_id: String,
	story_type: String,
	resident_id: String,
	place_name: String,
	payload: Dictionary,
) -> String:
	var existing_event_id := _public_story_event_record_id(event_id)
	if not existing_event_id.is_empty():
		return existing_event_id
	var story_payload := payload.duplicate(true)
	story_payload["storyEventId"] = event_id
	story_payload["storyType"] = story_type
	story_payload["time"] = get_time()
	story_payload["worldRevision"] = _world_revision
	var public_event_id := _next_world_event_id()
	_append_public_event_log(
		public_event_id,
		"story_event",
		resident_id,
		_resident_display_name(resident_id),
		place_name,
		story_payload,
	)
	var emitted_payload := _sanitize_public_event_payload(story_payload)
	story_event_created.emit({
		"eventId": public_event_id,
		"kind": "story_event",
		"time": get_time(),
		"worldRevision": _world_revision,
		"residentId": resident_id,
		"residentName": _resident_display_name(resident_id),
		"placeName": place_name,
		"payload": emitted_payload,
	})
	return public_event_id


func _public_story_event_record_id(story_event_id: String) -> String:
	var normalized_id := story_event_id.strip_edges()
	if normalized_id.is_empty():
		return ""
	for record: Dictionary in _public_event_log:
		if String(record.get("kind", "")) != "story_event":
			continue
		var payload := record.get("payload", {}) as Dictionary
		if String(payload.get("storyEventId", "")) == normalized_id:
			return String(record.get("eventId", ""))
	return ""


func _append_unique_story_ids(
	target: Array[String],
	values: Array,
) -> void:
	ACTIVITY_SCALARS.append_unique_story_ids(target, values)


func _rebuild_story_contexts_from_public_log() -> void:
	_action_story_context.clear()
	_conversation_story_context.clear()
	for record: Dictionary in _public_event_log:
		var payload := record.get("payload", {}) as Dictionary
		if String(record.get("kind", "")) == "story_event":
			var story_type := String(payload.get("storyType", ""))
			if story_type == "gathering_arrival":
				var arrival_action_id := String(
					payload.get("actionId", "")
				)
				if (
					not arrival_action_id.is_empty()
					and _action_story_context.has(arrival_action_id)
				):
					var arrival_context := (
						_action_story_context[
							arrival_action_id
						] as Dictionary
					)
					arrival_context["sourceEventIds"] = [
						String(record.get("eventId", "")),
					]
					_action_story_context[
						arrival_action_id
					] = arrival_context
				continue
			if story_type != "action_started":
				continue
			var action_id := String(payload.get("actionId", ""))
			if action_id.is_empty():
				continue
			_action_story_context[action_id] = {
				"sourceEventIds": [
					String(record.get("eventId", "")),
				],
				"rootEventIds": (
					payload.get("storyRootEventIds", []) as Array
				).duplicate(true),
				"directCauseEventIds": (
					payload.get("causedByEventIds", []) as Array
				).duplicate(true),
				"actionType": String(payload.get("actionType", "")),
				"line": String(payload.get("line", "")),
				"prop": String(payload.get("prop", "")),
				"verb": String(payload.get("verb", "")),
				"place": String(payload.get("place", "")),
				"residentId": String(record.get("residentId", "")),
			}
			continue
		if String(record.get("kind", "")) != "world_event":
			continue
		var conversation_id := String(
			payload.get("conversation_id", "")
		)
		if conversation_id.is_empty():
			continue
		_conversation_story_context[conversation_id] = {
			"rootEventIds": (
				payload.get("storyRootEventIds", []) as Array
			).duplicate(true),
			"lastEventId": String(payload.get("event_id", "")),
		}


func _broadcast_event(source: Dictionary) -> void:
	var event := _materialize_world_event(source)
	var is_weather_change := String(event.get("type", "")) == "天气变了"
	for resident_name in _resident_order:
		var resident := _residents[resident_name] as Dictionary
		if not _resident_is_present(resident):
			continue
		_enqueue_world_event(
			resident_name,
			event,
			not is_weather_change
			or String(resident.get("spaceId", "")) == "town_outdoor",
		)


func _queue_world_event(
	resident_name: String,
	source: Dictionary,
) -> Dictionary:
	return _enqueue_world_event(
		resident_name,
		_materialize_world_event(source),
	)


func _materialize_world_event(
	source: Dictionary,
	reserved_event_id: String = "",
) -> Dictionary:
	var event := source.duplicate(true)
	event["event_id"] = (
		reserved_event_id
		if not reserved_event_id.is_empty()
		else _next_world_event_id()
	)
	event["time"] = (source.get("time", get_time()) as Dictionary).duplicate(true)
	_append_public_event_log(
		String(event["event_id"]),
		"world_event",
		"",
		"",
		String(event.get("placeName", event.get("place_name", ""))),
		event,
	)
	return event


func _enqueue_world_event(
	resident_name: String,
	event: Dictionary,
	schedule_event: bool = true,
) -> Dictionary:
	var resident := _residents[resident_name] as Dictionary
	_clear_rejected_action_streak(resident)
	if CONFLICT_KNOWLEDGE_PROJECTOR.is_injury_subject(
		event,
		resident_name,
	):
		_interrupt_action(resident_name, "刚刚遭遇冲突，当前行动中止")
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
			self,
			resident_name,
		)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(
				self,
				String(active_conversation.get("conversationId", "")),
				"一方离开",
				"interrupted",
			)
	var identified_event := event.duplicate(true)
	identified_event["residentId"] = resident_name
	var agent_event := identified_event.duplicate(true)
	for system_key: String in [
		"participant_resident_ids",
		"causedByEventIds",
		"storyRootEventIds",
		"placeName",
	]:
		agent_event.erase(system_key)
	# agent_event 已是本地独占深拷贝。可合并的重复事实只保留最新版本，
	# 当前请求中的旧版本和下一请求中的新版本不会互相覆盖。
	_append_pending_world_event(resident, agent_event)
	if bool(resident.get("decisionPending", false)):
		AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	world_event_created.emit(_resident_display_name(resident_name), identified_event)
	if schedule_event:
		if ANNOUNCEMENT_RESIDENT_RUNTIME.schedule_player_priority_decision(self, resident_name, event): return identified_event
		var event_type := String(event.get("type", ""))
		var wake_while_current_action := event_type in [
			"有人来了",
			"有人走了",
			"公告到点",
		]
		_schedule_decision(
			resident_name,
			URGENT_EVENT_TYPES.has(event_type),
			false,
			URGENT_EVENT_TYPES.has(event_type),
			false,
			wake_while_current_action,
		)
	return identified_event


func _queue_event_for_person(
	person_name: String,
	source: Dictionary,
) -> Dictionary:
	if _residents.has(person_name):
		return _queue_world_event(person_name, source)
	return {}


func _direct_connection_endpoint(current_place: String, target_place: String) -> Dictionary:
	return ACTION_SUPPORT.direct_connection_endpoint(self, current_place, target_place)


func _outdoor_connection_place_for(place_name: String) -> String:
	return ACTION_SUPPORT.outdoor_connection_place_for(self, place_name)


func _apply_player_avatar_state(
	space_id: String,
	membership: Dictionary,
	position: Vector2,
	doing: String,
	command: String,
) -> Dictionary:
	var previous_space_id := String(_player_avatar.get("spaceId", ""))
	var previous_region_id := String(_player_avatar.get("regionId", ""))
	var previous_place := String(_player_avatar.get("currentPlace", ""))
	var previous_position := _player_avatar.get("position", Vector2.ZERO) as Vector2
	_player_avatar["position"] = position
	_player_avatar["spaceId"] = space_id
	_player_avatar["regionId"] = String(membership.get("regionId", ""))
	_player_avatar["currentPlace"] = String(membership.get("placeName", ""))
	if not doing.strip_edges().is_empty():
		_player_avatar["doing"] = doing.strip_edges()
	var current_place := String(_player_avatar.get("currentPlace", ""))
	var semantic_state_changed := (
		String(_player_avatar.get("spaceId", "")) != previous_space_id
		or String(_player_avatar.get("regionId", "")) != previous_region_id
		or current_place != previous_place
	)
	var avatar_position_changed := previous_position != position
	if semantic_state_changed:
		_bump_world_revision(false)
	var perception_changed := PERCEPTION_RUNTIME._refresh_player_avatar_perception(self,
		true,
		not semantic_state_changed,
		semantic_state_changed,
		avatar_position_changed,
	)
	var state := get_player_avatar_state()
	player_avatar_state_changed.emit(state)
	if current_place != previous_place:
		var place_change := {
			"from": previous_place,
			"to": current_place,
			"time": get_time(),
			"state": state.duplicate(true),
		}
		_append_public_event_log(
			_next_world_event_id(),
			"player_place",
			"",
			"你",
			current_place,
			{
				"from": previous_place,
				"to": current_place,
				"time": (place_change.get("time", {}) as Dictionary).duplicate(true),
				"worldRevision": _world_revision,
			},
		)
		player_avatar_place_changed.emit(place_change)
	if semantic_state_changed or perception_changed:
		_notify_world_revision()
	return _player_command_result(command, true, "世界已确认化身位置", {
		"placeChanged": current_place != previous_place,
		"state": state,
	})


func _player_command_result(command: String, ok: bool, reason: String, extra: Dictionary = {}) -> Dictionary:
	var error_code := ""
	if not ok:
		if reason == "世界尚未运行":
			error_code = "WORLD_NOT_RUNNING"
		elif command == "更新位置":
			error_code = "PLAYER_POSITION_REJECTED"
		elif command == "切换地点":
			error_code = "PLAYER_PLACE_CHANGE_REJECTED"
		else:
			error_code = "CONVERSATION_COMMAND_REJECTED"
	var result := {
		"ok": ok,
		"command": command,
		"reason": reason,
		"time": get_time(),
		"errorCode": error_code,
		"retryable": false,
		"worldRevision": _world_revision,
	}
	if not ok:
		result["errors"] = [reason]
	for key: Variant in extra:
		var value: Variant = extra[key]
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	player_command_result_created.emit(result.duplicate(true))
	return result


func _emit_place_change(
	resident_name: String,
	previous_place: String,
	defer_signal := false,
) -> bool:
	var resident := _residents[resident_name] as Dictionary
	var current_place := String(resident.get("currentPlace", ""))
	if previous_place == current_place:
		return false
	var place_change := {
		"residentId": resident_name,
		"from": previous_place,
		"to": current_place,
		"time": get_time(),
		"worldRevision": _world_revision,
	}
	_append_public_event_log(
		_next_world_event_id(),
		"resident_place",
		resident_name,
		_resident_display_name(resident_name),
		current_place,
		{
			"residentId": resident_name,
			"from": previous_place,
			"to": current_place,
			"time": (place_change.get("time", {}) as Dictionary).duplicate(true),
			"worldRevision": _world_revision,
		},
	)
	var current_action := resident.get("currentAction", {}) as Dictionary
	var story_context := _story_context_for_action(
		String(current_action.get("action_id", ""))
	)
	if (
		String(current_action.get("type", "")) == "去"
		and not story_context.is_empty()
		and current_place == String(current_action.get("place", ""))
	):
		var story_arrival_id := "story-arrival:%s:%s:%d" % [
			resident_name,
			String(current_action.get("action_id", "")),
			_world_revision,
		]
		var public_arrival_event_id := _append_story_event(
			story_arrival_id,
			"gathering_arrival",
			resident_name,
			current_place,
			{
				"actionId": String(
					current_action.get("action_id", "")
				),
				"from": previous_place,
				"to": current_place,
				"participantLabels": [
					_resident_display_name(resident_name),
				],
				"causedByEventIds": (
					story_context.get("rootEventIds", []) as Array
				).duplicate(true),
				"storyRootEventIds": (
					story_context.get("rootEventIds", []) as Array
				).duplicate(true),
			},
		)
		story_context["sourceEventIds"] = [public_arrival_event_id]
		_action_story_context[
			String(current_action.get("action_id", ""))
		] = story_context
	if defer_signal:
		_queue_resident_place_change_signal(resident_name, place_change)
	else:
		place_change["state"] = get_resident_state(resident_name)
		resident_place_changed.emit(
			_resident_display_name(resident_name),
			place_change,
		)
	return true


func _apply_route_sample(
	resident: Dictionary,
	sample: Dictionary,
	repair_clearance: bool = false,
) -> bool:
	var position := sample.get("position", {}) as Dictionary
	var space_id := String(sample.get("spaceId", ""))
	var raw_position := Vector2(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
	)
	var authoritative_position := (
		_clearance_safe_position(space_id, raw_position)
		if repair_clearance
		else raw_position
	)
	return _apply_authoritative_resident_position(
		resident,
		authoritative_position,
		space_id,
		String(sample.get("regionId", "")),
		String(sample.get("placeName", "")),
	)


func _apply_authoritative_resident_position(
	resident: Dictionary,
	position: Vector2,
	space_id: String,
	region_id: String,
	place_name: String,
) -> bool:
	return ACTION_SUPPORT.apply_authoritative_resident_position(resident, position, space_id, region_id, place_name)


func _complete_agent_submission(result: Dictionary) -> Dictionary:
	var probe_started_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	_schedule_social_receipt_wakes()
	probe_started_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_started_usec, "submission_social_receipts")
	_notify_world_revision()
	WORLD_PERFORMANCE_PROBE.record_lap(probe_started_usec, "submission_revision_notify")
	return result


func _validate_player_turn(action: Dictionary, is_reply: bool) -> String:
	return ACTION_SUPPORT.validate_player_turn(action, is_reply)


func _presentation_action(action: Dictionary) -> Dictionary:
	var result := {
		"action_id": String(action.get("action_id", "")),
		"type": String(action.get("type", "")),
		"line": String(action.get("line", _default_doing(action))),
		"startedAt": get_time(),
	}
	for key in [
		"target_resident_id",
		"recipient_resident_id",
		"content",
		"conversation_id",
		"say",
		"narration",
		"photos",
		"end",
		"prop",
		"verb",
		"dynamicPropId",
	]:
		if action.has(key):
			var value: Variant = action[key]
			result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result


func _agent_available_activities(
	resident: Dictionary,
	frame_budgeted := false,
	priority_activity_id := "",
	max_uncached_route_checks_override := -2,
) -> Array:
	var resident_id := String(resident.get("residentId", ""))
	var current_place := String(resident.get("currentPlace", ""))
	var service_state := (
		_place_service_states.get(current_place, {}) as Dictionary
	)
	var query := query_activity_options(
		resident_id,
		resident,
		(
			max_uncached_route_checks_override
			if max_uncached_route_checks_override >= -1
			else MAX_AGENT_ACTIVITY_ROUTE_CHECKS_PER_WAKE
			if frame_budgeted
			else -1
		),
		priority_activity_id,
	)
	if query.get("ok") != true:
		return []
	var result: Array[Dictionary] = []
	var attributes := resident.get("attributes", {}) as Dictionary
	for option_value: Variant in query.get("options", []) as Array:
		var option := option_value as Dictionary
		var route_check_deferred := bool(
			option.get("routeCheckDeferred", false)
		)
		if not bool(option.get("available", false)) and not route_check_deferred:
			continue
		var activity_id := String(option.get("activityId", ""))
		if (
			not service_state.is_empty()
			and not bool(service_state.get("open", true))
			and (
				(service_state.get("request_activity_ids", []) as Array).has(
					activity_id
				)
				or activity_id
				== String(service_state.get("helper_activity_id", ""))
			)
		):
			continue
		var matched_interests := INTERESTS.matched_labels_for_activity(
			attributes.get("interests", []),
			_activity_runtime.activity_tags(activity_id),
		)
		var role := String(option.get("role", ""))
		var matching_task_ids: Array[String] = []
		var matching_task_capabilities: Array[String] = []
		if role == "worker":
			var occupation_id := _work_occupation_id_for_activity(
				resident_id,
				activity_id,
			)
			if not occupation_id.is_empty():
				var tasks := _work_tasks.tasks_for_activity(occupation_id,
					activity_id,
					resident_id,) as Array
				for task_value: Variant in _available_work_tasks(tasks):
					if not task_value is Dictionary:
						continue
					var task := task_value as Dictionary
					var task_id := String(task.get("taskId", ""))
					var capability := String(task.get("capability", ""))
					if not task_id.is_empty() and not matching_task_ids.has(task_id):
						matching_task_ids.append(task_id)
					if (
						not capability.is_empty()
						and not matching_task_capabilities.has(capability)
					):
						matching_task_capabilities.append(capability)
		matching_task_ids.sort()
		matching_task_capabilities.sort()
		result.append({
			"activity_id": activity_id,
			"label": String(option.get("label", "")),
			"role": role,
			"route_check_deferred": route_check_deferred,
			"advances_current_work_task": not matching_task_ids.is_empty(),
			"work_task_ids": matching_task_ids,
			"work_task_capabilities": matching_task_capabilities,
			"interest_match": not matched_interests.is_empty(),
			"matched_interests": matched_interests,
	})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_work := bool(left.get("advances_current_work_task", false))
		var right_work := bool(right.get("advances_current_work_task", false))
		if left_work != right_work:
			return left_work
		var left_match := bool(left.get("interest_match", false))
		var right_match := bool(right.get("interest_match", false))
		if left_match != right_match:
			return left_match
		return String(left.get("activity_id", "")) < String(
			right.get("activity_id", "")
		)
	)
	return result


func _prop_query_data() -> Dictionary:
	if _dynamic_props.is_empty():
		return _world_data
	var query_data := _world_data.duplicate(false)
	var props := (_world_data.get("props", []) as Array).duplicate()
	for prop_value: Variant in _dynamic_props.values():
		props.append((prop_value as Dictionary).duplicate(true))
	query_data["props"] = props
	return query_data


func _default_doing(action: Dictionary) -> String:
	return ACTION_PROJECTION_MODULE.default_doing(self, action)


func _point_along_polyline(points: Array[Vector2], ratio: float) -> Vector2:
	return ACTION_GEOMETRY.point_along_polyline(points, ratio)


func _prop_approach_duration_minutes(action: Dictionary) -> int:
	return ACTION_SUPPORT.prop_approach_duration_minutes(self, action)


func _reverse_polyline_to_ratio(points: Array[Vector2], ratio: float) -> Array[Vector2]:
	if points.is_empty():
		return []
	var current := _point_along_polyline(points, ratio)
	var result: Array[Vector2] = [current]
	var target_distance := 0.0
	for index in range(1, points.size()):
		target_distance += points[index - 1].distance_to(points[index])
	target_distance *= clampf(ratio, 0.0, 1.0)
	var cursor := 0.0
	var segment_index := 0
	for index in range(1, points.size()):
		var length := points[index - 1].distance_to(points[index])
		if target_distance <= cursor + length:
			segment_index = index - 1
			break
		cursor += length
	for index in range(segment_index, -1, -1):
		if not result[-1].is_equal_approx(points[index]):
			result.append(points[index])
	return result


func _apply_body_effects(resident: Dictionary, effects: Dictionary) -> void:
	var body := resident.get("body", {}) as Dictionary
	for state_name_value: Variant in effects:
		var state_name := String(state_name_value)
		if not BODY_LEVELS.has(state_name):
			continue
		var levels := BODY_LEVELS[state_name] as Array
		var current_index := levels.find(String(body.get(state_name, levels[0])))
		body[state_name] = levels[clampi(current_index + int(effects[state_name_value]), 0, levels.size() - 1)]
	var activity_state := (
		resident.get("activityState", _empty_activity_state()) as Dictionary
	).duplicate(true)
	if effects.has("饿"):
		activity_state["satiety"] = _need_value_for_body_level(
			String(body.get("饿", "不饿")),
		)
	if effects.has("累"):
		activity_state["energy"] = _need_value_for_body_level(
			String(body.get("累", "不累")),
		)
	resident["activityState"] = activity_state


func _empty_activity_state() -> Dictionary:
	return ACTIVITY_SCALARS.empty_activity_state()


func _activity_state_from_body(body: Dictionary) -> Dictionary:
	return ACTIVITY_SCALARS.activity_state_from_body(body)


func _need_value_for_body_level(level: String) -> int:
	return ACTIVITY_SCALARS.need_value_for_body_level(level)


func _next_activity_state(
	resident: Dictionary,
	effects: Dictionary,
) -> Dictionary:
	return ACTIVITY_SCALARS.next_activity_state(
		resident,
		effects,
		ACTIVITY_STATE_KEYS,
	)


func _advance_passive_activity_needs(absolute_minute: int) -> void:
	if posmod(absolute_minute, PASSIVE_NEED_TICK_MINUTES) != 0:
		return
	# A3:整点 tick 拆"需求计算"与"emit 消费链"两段计时,emit 计次数。
	var lap_usec := Time.get_ticks_usec() if _advance_profile_enabled else 0
	for resident_id in _resident_order:
		var resident := _residents[resident_id] as Dictionary
		if (
			not _resident_is_present(resident)
			or _resident_is_sleeping(resident)
		):
			continue
		var current_action := resident.get("currentAction", {}) as Dictionary
		var activity_execution := _activity_runtime.execution_for_action(
			resident_id,
			String(current_action.get("action_id", "")),
		) as Dictionary
		if not activity_execution.is_empty():
			continue
		var nearby := resident.get("nearby", []) as Array
		var effects := {
			"energy": -2,
			"satiety": -3,
			"socialNeed": -1 if not nearby.is_empty() else 2,
			"solitudeNeed": 2 if not nearby.is_empty() else -1,
		}
		var previous := (
			resident.get(
				"activityState",
				_empty_activity_state(),
			) as Dictionary
		).duplicate(true)
		var next := _next_activity_state(resident, effects)
		if next == previous:
			continue
		resident["activityState"] = next
		# C1(docs/居民状态通知链减负方案.md):整点需求只改 activityState/body,
		# 均不在表现合同内,不发射;HUD 饿/累经 world_revision_changed 拉取更新。
		_sync_body_from_activity_needs(resident, next)
		if ACTIVITY_SCALARS.hunger_crossed_decision_threshold(previous, next):
			_schedule_decision(resident_id, false)
		lap_usec = _advance_profile_lap(_advance_profile_scratch, "passiveNeedsComputeUsec", lap_usec)
	_advance_profile_lap(_advance_profile_scratch, "passiveNeedsComputeUsec", lap_usec)


func _resident_is_sleeping(resident: Dictionary) -> bool:
	var action := resident.get("currentAction", {}) as Dictionary
	if (
		String(action.get("type", "")) == "用道具"
		and String(action.get("verb", "")) == "睡觉"
	):
		return true
	var execution := _activity_runtime.execution_for_action(
		String(resident.get("residentId", "")),
		String(action.get("action_id", "")),
	) as Dictionary
	return String(execution.get("activityId", "")) == SLEEP_ACTIVITY_ID


func _sync_body_from_activity_needs(
	resident: Dictionary,
	activity_state: Dictionary,
) -> void:
	ACTIVITY_SCALARS.sync_body_from_activity_needs(resident, activity_state)


func _absolute_minute(time: Dictionary) -> int:
	return ACTION_SUPPORT.absolute_minute(time)


func _bump_world_revision(notify := true) -> void:
	_world_revision += 1
	if notify:
		_notify_world_revision()


func _notify_world_revision() -> void:
	world_revision_changed.emit(_world_revision)


func _reset_social_runtimes() -> void:
	_social_matters = SOCIAL_MATTER_RUNTIME.new()
	_community_bulletin = COMMUNITY_BULLETIN_RUNTIME.new()
	_social_sources = SOCIAL_MATTER_SOURCE_ADAPTER.new()
	_social_agent_adapter = SOCIAL_AGENT_ADAPTER.new()
	_community_bulletin.bind_social_runtime(
		_social_matters,
	)
	_social_sources.bind_social_runtime(
		_social_matters,
	)
	_social_agent_adapter.bind_social_runtime(
		_social_matters,
	)


func _start_matching_social_action(
	resident_id: String,
	action: Dictionary,
) -> void:
	for assignment: Dictionary in _active_social_assignments(
		resident_id,
		["assigned"],
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if not _social_goal_matches_action(
			action_goal,
			action,
			resident_id,
		):
			continue
		var result := _social_matters.start_execution(
			String(assignment.get("matter_id", "")),
			resident_id,
			String(action_goal.get("goal_id", "")),
			int(_environment.get_absolute_minute()),
		) as Dictionary
		if result.get("ok") == true:
			_emit_social_matter_summary(
				String(assignment.get("matter_id", "")),
			)


func _record_matching_social_action_result(
	resident_id: String,
	action: Dictionary,
	status: String,
	reason: String,
) -> void:
	for assignment: Dictionary in _active_social_assignments(
		resident_id,
		["executing"],
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if not _social_goal_action_type_matches(action_goal, action):
			continue
		var result_status := status
		var result_reason := reason
		if (
			status == "completed"
			and not _social_goal_matches_action(
				action_goal,
				action,
				resident_id,
			)
		):
			result_status = "failed"
			result_reason = "观察目标已经不在居民当前可感知范围内"
		_record_social_assignment_result(
			assignment,
			resident_id,
			{
				"result_id": "action:%s"
				% String(action.get("action_id", "")),
				"action_id": String(action.get("action_id", "")),
				"reason": result_reason,
			},
			result_status,
		)


func _start_matching_social_activity(
	resident_id: String,
	execution: Dictionary,
) -> void:
	for assignment: Dictionary in _active_social_assignments(
		resident_id,
		["assigned"],
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if not _social_goal_matches_activity(action_goal, execution):
			continue
		var result := _social_matters.start_execution(
			String(assignment.get("matter_id", "")),
			resident_id,
			String(action_goal.get("goal_id", "")),
			int(_environment.get_absolute_minute()),
		) as Dictionary
		if result.get("ok") == true:
			_emit_social_matter_summary(
				String(assignment.get("matter_id", "")),
			)


func _record_matching_social_activity_result(
	resident_id: String,
	execution: Dictionary,
	status: String,
	reason: String,
	bulletin_effect: Dictionary = {},
) -> void:
	for assignment: Dictionary in _active_social_assignments(
		resident_id,
		["executing"],
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if not _social_goal_matches_activity(action_goal, execution):
			continue
		var result_status := status
		var result_reason := reason
		if (
			status == "completed"
			and bool(bulletin_effect.get("handled", false))
			and bulletin_effect.get("ok") != true
		):
			result_status = "failed"
			result_reason = String(
				bulletin_effect.get(
					"reason",
					"公告栏操作没有形成有效世界结果",
				)
			)
		_record_social_assignment_result(
			assignment,
			resident_id,
			{
				"result_id": "activity:%s"
				% String(execution.get("actionId", "")),
				"action_id": String(execution.get("actionId", "")),
				"activity_id": String(execution.get("activityId", "")),
				"bulletin_result_id": String(
					bulletin_effect.get("result_id", "")
				),
				"reason": result_reason,
			},
			result_status,
		)


func _complete_bulletin_activity_effect(
	resident_id: String,
	execution: Dictionary,
) -> Dictionary:
	if String(execution.get("placeId", "")) != (
		SOCIAL_JUDGMENTS.COMMUNITY_BULLETIN_PLACE_ID
	):
		return {}
	var activity_id := String(execution.get("activityId", ""))
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID:
		var read_assignment := _active_social_assignment_for_capability(
			resident_id,
			"bulletin.read",
		)
		var announcement_id := ""
		if not read_assignment.is_empty():
			announcement_id = String(
				(
					(
						read_assignment.get(
							"action_goal",
							{},
						) as Dictionary
					).get("target_refs", {}) as Dictionary
				).get("announcement_id", "")
			)
		if announcement_id.is_empty():
			announcement_id = _first_unread_announcement_id(
				resident_id,
			)
		if announcement_id.is_empty():
			return {
				"handled": true,
				"ok": false,
				"reason": "公告栏当前没有可阅读的新公告",
			}
		var read_result := read_announcement(
			resident_id,
			announcement_id,
		)
		if read_result.get("ok") != true:
			return {
				"handled": true,
				"ok": false,
				"reason": String(
					(
						read_result.get(
							"errors",
							["公告已经失效"],
						) as Array
					)[0]
				),
			}
		return {
			"handled": true,
			"ok": true,
			"result_id": "bulletin-read:%s:%s"
				% [resident_id, announcement_id],
		}
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID:
		var publish_assignment := (
			_active_social_assignment_for_capability(
				resident_id,
				"bulletin.publish",
			)
		)
		if publish_assignment.is_empty():
			return {
				"handled": true,
				"ok": false,
				"reason": "没有已确认的公告内容，不能空贴公告",
			}
		var action_goal := (
			publish_assignment.get("action_goal", {}) as Dictionary
		)
		var target_refs := (
			action_goal.get("target_refs", {}) as Dictionary
		)
		var text := String(target_refs.get("text", "")).strip_edges()
		var matter_id := String(
			target_refs.get(
				"matter_id",
				publish_assignment.get("matter_id", ""),
			)
		).strip_edges()
		var publish_result := publish_resident_announcement(
			resident_id,
			text,
			matter_id,
		)
		if publish_result.get("ok") != true:
			return {
				"handled": true,
				"ok": false,
				"reason": String(
					(
						publish_result.get(
							"errors",
							["公告内容没有成功张贴"],
						) as Array
					)[0]
				),
			}
		var announcement := (
			publish_result.get("announcement", {}) as Dictionary
		)
		_record_staffing_trial_from_result(
			resident_id,
			"occupation_town_manager",
			{
				"announcementId": String(
					announcement.get("announcement_id", ""),
				),
				"matterId": matter_id,
			},
		)
		return {
			"handled": true,
			"ok": true,
			"result_id": "bulletin-publish:%s"
				% String(announcement.get("announcement_id", "")),
		}
	return {}


func _active_social_assignment_for_capability(
	resident_id: String,
	capability_id: String,
) -> Dictionary:
	for assignment: Dictionary in _active_social_assignments(
		resident_id,
		["assigned", "executing"],
	):
		if String(
			(
				assignment.get("action_goal", {}) as Dictionary
			).get("capability_id", "")
		) == capability_id:
			return assignment
	return {}


func _first_unread_announcement_id(resident_id: String) -> String:
	var known_ids := {}
	for knowledge_value: Variant in _community_bulletin.knowledge_for(
		resident_id,
	) as Array:
		var knowledge := knowledge_value as Dictionary
		known_ids[String(knowledge.get("announcement_id", ""))] = true
	for announcement: Dictionary in _community_bulletin.get_announcements(
		false,
	) as Array[Dictionary]:
		var announcement_id := String(
			announcement.get("announcement_id", "")
		)
		if not known_ids.has(announcement_id):
			return announcement_id
	return ""


func _community_announcement_matter_id(
	announcement_id: String,
) -> String:
	var normalized := announcement_id.strip_edges()
	if normalized.is_empty():
		return ""
	for announcement: Dictionary in _community_bulletin.get_announcements(
		true,
	) as Array[Dictionary]:
		if String(announcement.get("announcement_id", "")) == normalized:
			return String(announcement.get("matter_id", ""))
	return ""


func _record_social_assignment_result(
	assignment: Dictionary,
	resident_id: String,
	result_ref: Dictionary,
	status: String,
) -> void:
	var matter_id := String(assignment.get("matter_id", ""))
	var action_goal := assignment.get("action_goal", {}) as Dictionary
	var result := _social_matters.record_action_result(
		matter_id,
		resident_id,
		String(action_goal.get("goal_id", "")),
		result_ref,
		status,
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return
	var matter := _social_matters.get_matter(matter_id,) as Dictionary
	var source_ref := (
		matter.get("source_state_ref", {}) as Dictionary
	)
	if status == "completed":
		if String(source_ref.get("source_kind", "")) == (
			"animal_attention"
		):
			_resolve_animal_attention_source(matter)
		elif (
			not _matter_has_active_social_participants(matter)
			and String(source_ref.get("source_kind", ""))
			!= "place_service_pressure"
		):
			_social_matters.close_matter(
				matter_id,
				"social.resolve.goal_completed",
				String(action_goal.get("success_result_id", "")),
				[result_ref],
				int(_environment.get_absolute_minute()),
			)
	elif (
		String(source_ref.get("source_kind", ""))
		== "conversation_commitment"
		and not _matter_has_active_social_participants(matter)
	):
		# 对话承诺只有明确的承诺者；失败、主动退出或被中断后不能
		# 重新开放成一条无人负责的公共求助，否则居民会被旧承诺卡住。
		_social_matters.close_matter(matter_id,
			"social.resolve.cancelled",
			"commitment_failed",
			[result_ref],
			int(_environment.get_absolute_minute()),)
	_emit_social_matter_summary(matter_id)


func _resolve_animal_attention_source(matter: Dictionary) -> void:
	var source_ref := (
		matter.get("source_state_ref", {}) as Dictionary
	)
	var animal_id := String(source_ref.get("source_id", ""))
	var fact := (
		_animal_facts.get(animal_id, {}) as Dictionary
	).duplicate(true)
	if fact.is_empty() or not bool(
		fact.get("public_attention", false)
	):
		return
	fact["public_attention"] = false
	fact["source_revision"] = int(
		fact.get("source_revision", 0)
	) + 1
	fact["updated_at"] = int(
		_environment.get_absolute_minute()
	)
	_animal_facts[animal_id] = fact
	_sync_animal_attention_fact(fact)


func _complete_matching_direct_social_capability(
	resident_id: String,
	capability_id: String,
	target_refs: Dictionary,
	result_id: String,
) -> void:
	for assignment: Dictionary in _active_social_assignments(
		resident_id,
		["assigned"],
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if (
			String(action_goal.get("capability_id", ""))
			!= capability_id
			or not _target_refs_match(
				action_goal.get("target_refs", {}) as Dictionary,
				target_refs,
			)
		):
			continue
		var matter_id := String(assignment.get("matter_id", ""))
		var goal_id := String(action_goal.get("goal_id", ""))
		var started := _social_matters.start_execution(
			matter_id,
			resident_id,
			goal_id,
			int(_environment.get_absolute_minute()),
		) as Dictionary
		if started.get("ok") != true:
			continue
		_record_social_assignment_result(
			assignment,
			resident_id,
			{
				"result_id": result_id,
				"capability_id": capability_id,
			},
			"completed",
		)


func _target_refs_match(
	expected: Dictionary,
	actual: Dictionary,
) -> bool:
	return ACTIVITY_SCALARS.target_refs_match(expected, actual)


func _active_social_assignments(
	resident_id: String,
	statuses: Array[String],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for matter_value: Variant in _social_matters.list_matters(
		false,
	) as Array:
		var matter := matter_value as Dictionary
		var participant := (
			(matter.get("participants", {}) as Dictionary).get(
				resident_id,
				{},
			) as Dictionary
		)
		if (
			participant.is_empty()
			or String(participant.get("status", "")) not in statuses
		):
			continue
		result.append({
			"matter_id": String(matter.get("matter_id", "")),
			"action_goal": (
				participant.get("action_goal", {}) as Dictionary
			).duplicate(true),
		})
	return result


func _active_social_commitment_count(resident_id: String) -> int:
	return _active_social_assignments(
		resident_id,
		["assigned", "executing"],
	).size()


func _has_active_social_capability(
	resident_id: String,
	capability_id: String,
) -> bool:
	for assignment: Dictionary in _active_social_assignments(
		resident_id,
		["assigned", "executing"],
	):
		if String(
			(
				assignment.get("action_goal", {}) as Dictionary
			).get("capability_id", "")
		) == capability_id:
			return true
	return false


func _resident_social_available_at(
	resident_id: String,
	now: int,
) -> int:
	return SOCIAL_JUDGMENTS.resident_social_available_at(self, resident_id, now)


func _social_goal_matches_action(
	action_goal: Dictionary,
	action: Dictionary,
	resident_id: String = "",
) -> bool:
	if not _social_goal_action_type_matches(action_goal, action):
		return false
	var capability_id := String(action_goal.get("capability_id", ""))
	var target_refs := action_goal.get("target_refs", {}) as Dictionary
	match capability_id:
		"world.go_to_place":
			return (
				String(action.get("place", ""))
				== String(target_refs.get("place_id", ""))
			)
		"world.start_conversation":
			return (
				String(action.get("target_resident_id", ""))
				== String(target_refs.get("resident_id", ""))
			)
		"world.escort_person_to_place":
			return (
				String(action.get("conversationFollowUpMode", "")) == "escort"
				and String(action.get("followUpPersonId", "")) == String(target_refs.get("person_id", ""))
				and String(action.get("followUpDestinationPlace", "")) == String(target_refs.get("place_id", ""))
				and String(action.get("followUpPhase", "")) in ["leading", "returning_to_companion", "arrived"]
			)
		"world.fetch_service_for_person":
			return (
				String(action.get("conversationFollowUpMode", "")) == "fetch_service"
				and String(action.get("followUpPersonId", "")) == String(target_refs.get("person_id", ""))
				and String(action.get("followUpServicePlace", "")) == String(target_refs.get("service_place_id", ""))
				and String(action.get("followUpServiceActivityId", "")) == String(target_refs.get("service_activity_id", ""))
				and String(action.get("followUpPhase", "")) in ["going_to_source", "collecting", "returning_to_person", "delivered"]
			)
		"world.reply_conversation":
			return (
				String(action.get("conversation_id", ""))
				== String(target_refs.get("conversation_id", ""))
			)
		"world.wait":
			return _social_wait_target_is_current(
				target_refs,
				resident_id,
			)
	return false


func _social_goal_action_type_matches(
	action_goal: Dictionary,
	action: Dictionary,
) -> bool:
	return SOCIAL_JUDGMENTS.social_goal_action_type_matches(action_goal, action)


func _social_wait_target_is_current(
	target_refs: Dictionary,
	resident_id: String,
) -> bool:
	var animal_id := String(
		target_refs.get("animal_id", ""),
	).strip_edges()
	if animal_id.is_empty():
		return true
	var place_id := String(
		target_refs.get("place_id", ""),
	).strip_edges()
	var resident := _residents.get(resident_id, {}) as Dictionary
	var animal := _animal_facts.get(animal_id, {}) as Dictionary
	if (
		place_id.is_empty()
		or resident.is_empty()
		or animal.is_empty()
		or not _resident_is_present(resident)
		or not bool(animal.get("exists", false))
		or not bool(animal.get("public_attention", false))
		or String(resident.get("spaceId", "")) != "town_outdoor"
		or String(resident.get("currentPlace", "")) != place_id
		or String(animal.get("place_id", "")) != place_id
	):
		return false
	var resident_position := (
		resident.get("position", Vector2.INF) as Vector2
	)
	var animal_position := (
		animal.get("position", Vector2.INF) as Vector2
	)
	return (
		resident_position.is_finite()
		and animal_position.is_finite()
		and resident_position.distance_to(animal_position)
			<= float(_world_data.get("perceptionRange", 0.0))
	)


func _resident_has_current_animal_wait_assignment(
	resident_id: String,
	action: Dictionary,
) -> bool:
	for assignment: Dictionary in _active_social_assignments(
		resident_id,
		["assigned"],
	):
		var action_goal := (
			assignment.get("action_goal", {}) as Dictionary
		)
		var target_refs := (
			action_goal.get("target_refs", {}) as Dictionary
		)
		if (
			not String(target_refs.get("animal_id", "")).is_empty()
			and _social_goal_matches_action(
				action_goal,
				action,
				resident_id,
			)
		):
			return true
	return false


func _social_goal_matches_activity(
	action_goal: Dictionary,
	execution: Dictionary,
) -> bool:
	return SOCIAL_JUDGMENTS.social_goal_matches_activity(action_goal, execution)


func _matter_has_active_social_participants(matter: Dictionary) -> bool:
	return SOCIAL_JUDGMENTS.matter_has_active_social_participants(matter)


func _social_execution_status(status: String) -> String:
	return SOCIAL_JUDGMENTS.social_execution_status(status)


func _sync_social_source(
	method: String,
	source_state: Dictionary,
) -> Dictionary:
	if not _running:
		return _command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var reference_errors := _social_source_reference_errors(
		method,
		source_state,
	)
	if not reference_errors.is_empty():
		return _command_failure(
			"SOCIAL_SOURCE_REFERENCE_INVALID",
			reference_errors,
		)
	var sync_minute := int(_environment.get_absolute_minute())
	var result: Dictionary
	match method:
		"sync_place_service_pressure":
			result = _social_sources.sync_place_service_pressure(source_state, sync_minute)
		"sync_resident_request":
			result = _social_sources.sync_resident_request(source_state, sync_minute)
		"sync_conversation_commitment":
			result = _social_sources.sync_conversation_commitment(source_state, sync_minute)
		"sync_animal_attention":
			result = _social_sources.sync_animal_attention(source_state, sync_minute)
		"sync_job_vacancy":
			result = _social_sources.sync_job_vacancy(source_state, sync_minute)
		_:
			# 五个同名门面硬编码传入,按构造不可达。
			push_error("未知社会事项来源方法:%s" % method)
			result = _command_failure(
				"SOCIAL_SOURCE_REFERENCE_INVALID",
				["未知社会事项来源方法:%s" % method],
			)
	var matter_id := ""
	if result.get("value") is Dictionary:
		var matter := (
			(result.get("value", {}) as Dictionary).get(
				"matter",
				{},
			) as Dictionary
		)
		matter_id = String(matter.get("matter_id", ""))
	if result.get("ok") == true and not matter_id.is_empty():
		_prepare_initial_social_contacts(
			method,
			source_state,
			matter_id,
		)
		_begin_initial_social_response_round(
			method,
			source_state,
			matter_id,
		)
		# 对话承诺已经由本轮 conversation_follow_up 明确选定，随后会由
		# _submit_conversation_follow_up 直接登记承诺者。这里若再自动开启
		# 一轮社会回应，会把同一个承诺变成第二次待答复并阻断执行。
		if method != "sync_conversation_commitment":
			_maybe_begin_social_response_after_exposures(matter_id)
	return _finalize_social_mutation(result, matter_id)


func _prepare_initial_social_contacts(
	method: String,
	source_state: Dictionary,
	matter_id: String,
) -> void:
	var now := int(_environment.get_absolute_minute())
	var source_id := ""
	for event_value: Variant in source_state.get(
		"source_event_ids",
		[],
	) as Array:
		if event_value is String and not String(
			event_value
		).strip_edges().is_empty():
			source_id = String(event_value).strip_edges()
			break
	if source_id.is_empty():
		if method == "sync_place_service_pressure":
			source_id = String(source_state.get("pressure_id", ""))
		elif method == "sync_job_vacancy":
			source_id = String(source_state.get("vacancy_id", ""))
		else:
			source_id = String(
				source_state.get(
					"request_id",
					source_state.get("animal_id", ""),
				)
			)
	if method == "sync_resident_request":
		var requester_id := _resident_key(
			String(source_state.get("requester_id", ""))
		)
		if not requester_id.is_empty():
			_social_matters.record_involvement(
				matter_id,
				requester_id,
				"creator",
				now,
			)
		for resident_id: String in _initial_social_source_residents(
			method,
			source_state,
			true,
		):
			_social_matters.record_awareness(
				matter_id,
				resident_id,
				"known",
				"direct_request",
				source_id,
				now,
			)
		return
	if method == "sync_conversation_commitment":
		var promisor_id := _resident_key(String(source_state.get("promisor_id", "")))
		var beneficiary_id := _person_id_for_name(String(source_state.get("beneficiary_id", "")))
		if not promisor_id.is_empty():
			_social_matters.record_involvement(matter_id, promisor_id, "participant", now)
			_social_matters.record_awareness(matter_id, promisor_id, "known", "direct_conversation", source_id, now)
		if not beneficiary_id.is_empty():
			_social_matters.record_involvement(matter_id, beneficiary_id, "affected", now)
			_social_matters.record_awareness(matter_id, beneficiary_id, "known", "direct_conversation", source_id, now)
		return
	if method == "sync_job_vacancy":
		for resident_id: String in _initial_social_source_residents(
			method,
			source_state,
			false,
		):
			_social_matters.record_involvement(
				matter_id,
				resident_id,
				"affected",
				now,
			)
			_social_matters.record_awareness(
				matter_id,
				resident_id,
				"known",
				"direct_request",
				source_id,
				now,
			)
		return
	var owner_id := ""
	if method == "sync_place_service_pressure":
		owner_id = _resident_key(
			String(source_state.get("owner_id", ""))
		)
		if not owner_id.is_empty():
			_social_matters.record_involvement(
				matter_id,
				owner_id,
				"affected",
				now,
			)
			_social_matters.record_awareness(
				matter_id,
				owner_id,
				"known",
				"witnessed",
				source_id,
				now,
			)
	var clue := _initial_social_exposure_clue(
		method,
		source_state,
	)
	for resident_id: String in _initial_social_source_residents(
		method,
		source_state,
		false,
	):
		if resident_id == owner_id:
			continue
		_social_matters.offer_exposure(
			matter_id,
			resident_id,
			"visible",
			clue,
			source_id,
			now,
			int(source_state.get("expires_at", now + 1)),
		)
		_schedule_decision(resident_id, false)


func _initial_social_exposure_clue(
	method: String,
	source_state: Dictionary,
) -> String:
	return RUNTIME_LOG_TEXT.initial_social_exposure_clue(method, source_state)


func _begin_initial_social_response_round(
	method: String,
	source_state: Dictionary,
	matter_id: String,
) -> void:
	if method not in [
		"sync_resident_request",
		"sync_job_vacancy",
	]:
		return
	var matter := _social_matters.get_matter(
		matter_id,
	) as Dictionary
	if String(matter.get("state", "")) != "open":
		return
	var now := int(_environment.get_absolute_minute())
	var candidates: Array[Dictionary] = []
	for resident_id: String in _initial_social_source_residents(
		method,
		source_state,
		false,
	):
		var load := _active_social_commitment_count(resident_id)
		if load >= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT:
			continue
		var candidate: Dictionary
		if method == "sync_job_vacancy":
			var resident := (
				_residents.get(resident_id, {}) as Dictionary
			)
			var from_occupation_id := _occupation_id_for_resident(
				resident,
			)
			candidate = _social_sources.job_vacancy_response_candidate(
				resident_id,
				_staffing_candidate_ability_score(
					resident,
					source_state,
				),
				load,
				_resident_social_available_at(resident_id, now),
				matter_id,
				_staffing.allowed_assignment_modes(
					resident_id,
					String(
						source_state.get(
							"occupation_id",
							"",
						),
					),
				) as Array,
				from_occupation_id,
			) as Dictionary
		else:
			candidate = _social_sources.response_candidate(
				resident_id,
				0,
				load,
				_resident_social_available_at(resident_id, now),
				matter_id,
			) as Dictionary
		if not candidate.is_empty():
			candidates.append(candidate)
		if candidates.size() >= MAX_SOCIAL_RESPONSE_CANDIDATES:
			break
	if candidates.is_empty():
		return
	var started := _social_matters.begin_response_round(
		matter_id,
		candidates,
		now,
		now + 30,
	) as Dictionary
	if started.get("ok") != true:
		return
	for candidate: Dictionary in candidates:
		_schedule_decision(
			String(candidate.get("resident_id", "")),
			true,
		)


func _initial_social_source_residents(
	method: String,
	source_state: Dictionary,
	include_creator: bool,
) -> Array[String]:
	var result: Array[String] = []
	var place_id := String(source_state.get("place_id", ""))
	if method in [
		"sync_place_service_pressure",
		"sync_animal_attention",
	]:
		for resident_id: String in _resident_order:
			if String(
				(
					_residents.get(resident_id, {}) as Dictionary
				).get("currentPlace", "")
			) == place_id:
				result.append(resident_id)
	if method == "sync_place_service_pressure":
		var owner_id := _resident_key(
			String(source_state.get("owner_id", ""))
		)
		if not owner_id.is_empty() and not result.has(owner_id):
			result.append(owner_id)
	elif method == "sync_resident_request":
		for recipient_value: Variant in source_state.get(
			"recipient_ids",
			[],
		) as Array:
			var recipient_id := _resident_key(
				String(recipient_value)
			)
			if (
				not recipient_id.is_empty()
				and not result.has(recipient_id)
			):
				result.append(recipient_id)
		if include_creator:
			var requester_id := _resident_key(
				String(source_state.get("requester_id", ""))
			)
			if (
				not requester_id.is_empty()
				and not result.has(requester_id)
			):
				result.append(requester_id)
	elif method == "sync_job_vacancy":
		for candidate_value: Variant in source_state.get(
			"candidate_resident_ids",
			[],
		) as Array:
			var candidate_id := _resident_key(String(candidate_value))
			if (
				not candidate_id.is_empty()
				and not result.has(candidate_id)
			):
				result.append(candidate_id)
	result.sort()
	return result


func _social_source_reference_errors(
	method: String,
	source_state: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	match method:
		"sync_place_service_pressure":
			_validate_social_place_reference(
				source_state.get("place_id"),
				"地点服务压力 place_id",
				errors,
			)
			_validate_social_resident_reference(
				source_state.get("owner_id"),
				"地点服务压力 owner_id",
				errors,
			)
			var helper_activity_id := _source_text(
				source_state.get("helper_activity_id")
			)
			var pressure_place_id := _source_text(
				source_state.get("place_id")
			)
			if (
				not helper_activity_id.is_empty()
				and not pressure_place_id.is_empty()
				and not _world_has_activity_at_place(
					helper_activity_id,
					pressure_place_id,
				)
			):
				errors.append(
					"地点服务压力引用的帮助活动不属于该地点"
				)
		"sync_resident_request":
			_validate_social_resident_reference(
				source_state.get("requester_id"),
				"居民请求 requester_id",
				errors,
			)
			var recipient_ids_value: Variant = source_state.get(
				"recipient_ids",
				[],
			)
			if not recipient_ids_value is Array:
				errors.append("居民请求 recipient_ids 必须是数组")
			else:
				for recipient_value: Variant in (
					recipient_ids_value as Array
				):
					_validate_social_resident_reference(
						recipient_value,
						"居民请求 recipient_ids",
						errors,
					)
			var request_place_id := _source_text(
				source_state.get("place_id")
			)
			if not request_place_id.is_empty():
				_validate_social_place_reference(
					request_place_id,
					"居民请求 place_id",
					errors,
				)
			var capability_id := _source_text(
				source_state.get("capability_id")
			)
			var target_refs := (
				source_state.get("target_refs", {}) as Dictionary
				if source_state.get("target_refs") is Dictionary
				else {}
			)
			_validate_social_capability_references(
				capability_id,
				target_refs,
				errors,
			)
		"sync_animal_attention":
			_validate_social_place_reference(
				source_state.get("place_id"),
				"动物关注 place_id",
				errors,
			)
		"sync_job_vacancy":
			_validate_social_place_reference(
				source_state.get("primary_place_id"),
				"岗位空缺 primary_place_id",
				errors,
			)
			var occupation_id := _source_text(
				source_state.get("occupation_id"),
			)
			if _occupation_definition(occupation_id).is_empty():
				errors.append(
					"岗位空缺引用不存在的职业：%s" % occupation_id
				)
			for candidate_value: Variant in source_state.get(
				"candidate_resident_ids",
				[],
			) as Array:
				_validate_social_resident_reference(
					candidate_value,
					"岗位空缺 candidate_resident_ids",
					errors,
				)
	return errors


func _validate_social_capability_references(
	capability_id: String,
	target_refs: Dictionary,
	errors: Array[String],
) -> void:
	var target_place := _source_text(target_refs.get("place_id"))
	if not target_place.is_empty():
		_validate_social_place_reference(
			target_place,
			"行动目标 place_id",
			errors,
		)
	var target_resident := _source_text(
		target_refs.get("resident_id")
	)
	if not target_resident.is_empty():
		_validate_social_resident_reference(
			target_resident,
			"行动目标 resident_id",
			errors,
		)
	if capability_id == "world.perform_activity":
		var activity_id := _source_text(
			target_refs.get("activity_id")
		)
		if (
			not activity_id.is_empty()
			and not target_place.is_empty()
			and not _world_has_activity_at_place(
				activity_id,
				target_place,
			)
		):
			errors.append("行动目标活动不属于目标地点")
	elif capability_id == "world.reply_conversation":
		var conversation_id := _source_text(
			target_refs.get("conversation_id")
		)
		if (
			not conversation_id.is_empty()
			and get_conversation(conversation_id).is_empty()
		):
			errors.append("行动目标引用的对话不存在")
	elif capability_id == "bulletin.read":
		var announcement_id := _source_text(
			target_refs.get("announcement_id")
		)
		if (
			not announcement_id.is_empty()
			and not _community_announcement_exists(announcement_id)
		):
			errors.append("行动目标引用的公告不存在")
	elif capability_id == "staffing.apply_assignment":
		var occupation_id := _source_text(
			target_refs.get("occupation_id"),
		)
		if _occupation_definition(occupation_id).is_empty():
			errors.append("行动目标引用的职业不存在")


func _validate_social_place_reference(
	value: Variant,
	label: String,
	errors: Array[String],
) -> void:
	var place_id := _source_text(value)
	if not place_id.is_empty() and get_place_detail(place_id).is_empty():
		errors.append("%s 引用不存在的地点：%s" % [label, place_id])


func _validate_social_resident_reference(
	value: Variant,
	label: String,
	errors: Array[String],
) -> void:
	var resident_ref := _source_text(value)
	if not resident_ref.is_empty() and _resident_key(resident_ref).is_empty():
		errors.append("%s 引用不存在的居民：%s" % [label, resident_ref])


func _source_text(value: Variant) -> String:
	return RUNTIME_LOG_TEXT.source_text(value)


func _world_has_activity_at_place(
	activity_id: String,
	place_id: String,
) -> bool:
	return _world_data_has_activity_at_place(
		_world_data,
		activity_id,
		place_id,
	)


func _community_announcement_exists(announcement_id: String) -> bool:
	for announcement: Dictionary in _community_bulletin.get_announcements(
		true,
	) as Array[Dictionary]:
		if String(
			announcement.get("announcement_id", "")
		) == announcement_id:
			return true
	return false


func _finalize_social_mutation(
	result: Dictionary,
	matter_id := "",
) -> Dictionary:
	if result.get("ok") != true:
		return _social_command_result(result)
	_bump_world_revision(false)
	_emit_social_matter_summary(matter_id)
	_schedule_social_receipt_wakes()
	_notify_world_revision()
	var value: Variant = result.get("value")
	var extra := {}
	if value is Dictionary:
		extra = (value as Dictionary).duplicate(true)
	else:
		extra["value"] = value
	extra["ok"] = true
	return _decorate_command_result(extra)


func _social_command_result(
	result: Dictionary,
	fallback_error_code := "SOCIAL_COMMAND_REJECTED",
) -> Dictionary:
	var reason := String(
		result.get("reason", "社会事项操作未被 World 接受")
	).strip_edges()
	if reason.is_empty():
		reason = "社会事项操作未被 World 接受"
	var error_code := String(result.get("error_code", "")).strip_edges()
	if error_code.is_empty():
		error_code = fallback_error_code
	return _command_failure(error_code, [reason])


func _emit_social_matter_summary(matter_id: String) -> void:
	var normalized := matter_id.strip_edges()
	if normalized.is_empty():
		return
	var summary := _social_matters.public_summary(
		normalized,
	) as Dictionary
	if not summary.is_empty():
		_append_social_matter_log_event(normalized)
		social_matter_changed.emit(summary)


func _append_social_matter_log_event(matter_id: String) -> void:
	var matter := _social_matters.get_matter(matter_id) as Dictionary
	if matter.is_empty():
		return
	var revision := int(matter.get("revision", 0))
	if revision < 1:
		return
	var participant_ids: Array[String] = []
	for resident_id_value: Variant in [matter.get("creator_id", "")]:
		var resident_id := String(resident_id_value).strip_edges()
		if not resident_id.is_empty() and not participant_ids.has(resident_id):
			participant_ids.append(resident_id)
	for resident_id_value: Variant in matter.get("subject_ids", []) as Array:
		var resident_id := String(resident_id_value).strip_edges()
		if not resident_id.is_empty() and not participant_ids.has(resident_id):
			participant_ids.append(resident_id)
	for resident_id_value: Variant in (matter.get("participants", {}) as Dictionary).keys():
		var resident_id := String(resident_id_value).strip_edges()
		if not resident_id.is_empty() and not participant_ids.has(resident_id):
			participant_ids.append(resident_id)
	for candidate_value: Variant in matter.get("fixed_candidates", []) as Array:
		if not candidate_value is Dictionary:
			continue
		var candidate := candidate_value as Dictionary
		var resident_id := String(
			candidate.get("resident_id", candidate.get("residentId", "")),
		).strip_edges()
		if not resident_id.is_empty() and not participant_ids.has(resident_id):
			participant_ids.append(resident_id)
	var state := String(matter.get("state", "open"))
	var creator_id := String(matter.get("creator_id", "")).strip_edges()
	_append_world_log_event(
		"social-matter:%s:revision:%d" % [matter_id, revision],
		"social_matter",
		creator_id,
		_resident_display_name(creator_id),
		String(matter.get("place_id", "")),
		{
			"type": _social_matter_log_event_type(state, revision),
			"matterId": matter_id,
			"matterKind": String(matter.get("kind", "")),
			"matterRevision": revision,
			"status": (
				"completed"
				if state == "closed"
				else ("waiting" if state == "collecting" else "ongoing")
			),
			"participantIds": participant_ids,
			"attentionLevel": String(matter.get("attention_level", "daily")),
			"reasonSummary": String(matter.get("reason_summary", "")),
			"closeReason": String(matter.get("close_reason", "")),
			"sourceStateRef": (matter.get("source_state_ref", {}) as Dictionary).duplicate(true),
			"sourceEventIds": (matter.get("source_event_ids", []) as Array).duplicate(true),
			"resultRefs": (matter.get("result_refs", []) as Array).duplicate(true),
		},
	)


func _social_matter_log_event_type(state: String, revision: int) -> String:
	return RUNTIME_LOG_TEXT.social_matter_log_event_type(state, revision)


func _schedule_social_receipt_wakes() -> void:
	for resident_id in _resident_order:
		if (
			_social_matters.peek_receipts(
				resident_id,
			) as Array
		).is_empty():
			continue
		_schedule_decision(resident_id, false)


func _settle_social_round_if_ready(matter_id: String) -> void:
	var normalized := matter_id.strip_edges()
	if (
		normalized.is_empty()
		or not bool(
			_social_matters.is_response_round_ready(
				normalized,
			)
		)
	):
		return
	var settled := _social_matters.settle_response_round(
		normalized,
		int(_environment.get_absolute_minute()),
		"reopen",
	) as Dictionary
	if settled.get("ok") == true:
		_reconcile_social_assignments(normalized)
		_maybe_begin_social_response_after_exposures(normalized)


func _reconcile_social_assignments(matter_id: String) -> void:
	var matter := _social_matters.get_matter(
		matter_id,
	) as Dictionary
	if matter.is_empty():
		return
	for resident_value: Variant in (
		matter.get("participants", {}) as Dictionary
	):
		var resident_id := String(resident_value)
		var participant := (
			(matter.get("participants", {}) as Dictionary).get(
				resident_id,
				{},
			) as Dictionary
		)
		if (
			String(participant.get("status", "")) != "assigned"
			or not _residents.has(resident_id)
		):
			continue
		var resident := _residents.get(resident_id, {}) as Dictionary
		var action_goal := (
			participant.get("action_goal", {}) as Dictionary
		)
		if String(action_goal.get("capability_id", "")) == (
			"staffing.apply_assignment"
		):
			_apply_confirmed_staffing_assignment(
				matter_id,
				resident_id,
				action_goal,
			)
			continue
		if (
			String(action_goal.get("capability_id", ""))
			== "world.go_to_place"
			and String(resident.get("currentPlace", ""))
			== String(
				(
					action_goal.get("target_refs", {}) as Dictionary
				).get("place_id", "")
			)
		):
			var assignment := {
				"matter_id": matter_id,
				"action_goal": action_goal.duplicate(true),
			}
			var started := _social_matters.start_execution(
				matter_id,
				resident_id,
				String(action_goal.get("goal_id", "")),
				int(_environment.get_absolute_minute()),
			) as Dictionary
			if started.get("ok") == true:
				_record_social_assignment_result(
					assignment,
					resident_id,
					{
						"result_id": "already-at-place:%s:%s"
						% [matter_id, resident_id],
						"capability_id": "world.go_to_place",
						"place_id": String(
							resident.get("currentPlace", "")
						),
					},
					"completed",
				)
			continue
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		var execution := _activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if not execution.is_empty():
			_start_matching_social_activity(resident_id, execution)
		else:
			_start_matching_social_action(resident_id, action)


func _apply_confirmed_staffing_assignment(
	matter_id: String,
	resident_id: String,
	action_goal: Dictionary,
) -> void:
	var target_refs := (
		action_goal.get("target_refs", {}) as Dictionary
	)
	var target_occupation_id := String(
		target_refs.get("occupation_id", ""),
	)
	var assignment_kind := String(
		target_refs.get("assignment_kind", ""),
	)
	var resident := _residents.get(resident_id, {}) as Dictionary
	var current_occupation_id := _occupation_id_for_resident(resident)
	var target_post := _staffing.post_for_occupation(
		target_occupation_id,
	) as Dictionary
	var target_occupation := _occupation_definition(
		target_occupation_id,
	)
	var from_occupation_id := String(
		target_refs.get("from_occupation_id", ""),
	)
	var started := _social_matters.start_execution(
		matter_id,
		resident_id,
		String(action_goal.get("goal_id", "")),
		int(_environment.get_absolute_minute()),
	) as Dictionary
	if started.get("ok") != true:
		return
	var failure_reason := ""
	var allowed_modes := _staffing.allowed_assignment_modes(
		resident_id,
		target_occupation_id,
	) as Array
	if (
		assignment_kind not in [
			"transfer",
			"part_time",
			"shift",
			"trial",
		]
		or target_post.is_empty()
		or target_occupation.is_empty()
	):
		failure_reason = "岗位调整目标无效"
	elif assignment_kind not in allowed_modes:
		failure_reason = "居民当前没有以这种方式接手该岗位的资格"
	elif (
		assignment_kind == "transfer"
		and not (
			target_post.get("assignedResidentIds", []) as Array
		).is_empty()
	):
		failure_reason = "岗位已经有正式负责人"
	elif (
		assignment_kind != "transfer"
		and not (
			target_post.get("assignedResidentIds", []) as Array
		).is_empty()
	):
		failure_reason = "岗位已有正式负责人，本次空缺协商已经失效"
	elif (
		not from_occupation_id.is_empty()
		and from_occupation_id != current_occupation_id
	):
		failure_reason = "居民职业已经发生变化，本次申请失效"
	if not failure_reason.is_empty():
		_record_social_assignment_result(
			{
				"matter_id": matter_id,
				"action_goal": action_goal,
			},
			resident_id,
			{
				"result_id": "staffing-rejected:%s:%s"
				% [matter_id, resident_id],
				"reason": failure_reason,
			},
			"failed",
		)
		return
	if assignment_kind != "transfer":
		var arrangement_result := _staffing.create_arrangement(
			resident_id,
			target_occupation_id,
			assignment_kind,
			int(_environment.get_absolute_minute()),
			int(target_refs.get("shift_start_minute", 0)),
			int(target_refs.get("shift_end_minute", 1440)),
		) as Dictionary
		if arrangement_result.get("ok") != true:
			_record_social_assignment_result(
				{
					"matter_id": matter_id,
					"action_goal": action_goal,
				},
				resident_id,
				{
					"result_id": "staffing-rejected:%s:%s"
						% [matter_id, resident_id],
					"reason": "兼职、轮班或试岗安排发生冲突",
				},
				"failed",
			)
			return
		_staffing.rebuild(
			_residents,
			int(_environment.get_absolute_minute()),
		)
		_refresh_place_service_staffing()
		_bump_world_revision(false)
		var arrangement := arrangement_result.get(
			"arrangement",
			{},
		) as Dictionary
		_record_social_assignment_result(
			{
				"matter_id": matter_id,
				"action_goal": action_goal,
			},
			resident_id,
			{
				"result_id": "staffing-arrangement:%s"
					% String(arrangement.get("arrangementId", "")),
				"occupation_id": target_occupation_id,
				"assignment_kind": assignment_kind,
				"covers_post": bool(
					arrangement.get("coversPost", false),
				),
			},
			"completed",
		)
		_sync_staffing_matters()
		_schedule_decision(resident_id, true)
		_notify_world_revision()
		return
	_interrupt_action(
		resident_id,
		"居民自愿转岗，原工作已经交回待办",
	)
	_work_tasks.release_tasks_for_resident(
		resident_id,
		"原负责人已经转岗，任务等待重新接取",
	)
	_staffing.end_active_arrangements_for_occupation(
		target_occupation_id,
		int(_environment.get_absolute_minute()),
		"岗位已有正式负责人",
	)
	var social_state := (
		resident.get("socialState", {}) as Dictionary
	).duplicate(true)
	social_state["job"] = String(target_occupation.get("label", ""))
	social_state["workplace"] = String(
		target_occupation.get("primaryWorkplacePlace", ""),
	)
	resident["socialState"] = social_state
	_staffing.rebuild(
		_residents,
		int(_environment.get_absolute_minute()),
	)
	_refresh_place_service_staffing()
	_bump_world_revision(false)
	_emit_resident_state_changed(resident_id)
	_record_social_assignment_result(
		{
			"matter_id": matter_id,
			"action_goal": action_goal,
		},
		resident_id,
		{
			"result_id": "staffing-transfer:%s:%s:%s"
				% [matter_id, resident_id, target_occupation_id],
			"occupation_id": target_occupation_id,
			"assignment_kind": assignment_kind,
		},
		"completed",
	)
	_sync_staffing_matters()
	_schedule_decision(resident_id, true)
	_notify_world_revision()


func _refresh_place_service_staffing() -> void:
	var defaults := _build_default_place_service_states(
		_world_data,
		_owners,
		_residents,
	)
	var now := int(_environment.get_absolute_minute())
	for place_id_value: Variant in defaults:
		var place_id := String(place_id_value)
		var expected := defaults.get(place_id, {}) as Dictionary
		var current_ref := _place_service_states.get(place_id, {}) as Dictionary
		if current_ref.is_empty():
			_place_service_states[place_id] = expected.duplicate(true)
			continue
		var old_open := bool(current_ref.get("open", false))
		var next_open := bool(expected.get("open", false))
		var next_owner := String(expected.get("owner_id", ""))
		var next_occupation := String(
			expected.get("service_occupation_id", ""),
		)
		var changed := (
			String(current_ref.get("owner_id", "")) != next_owner
			or old_open != next_open
		)
		if (
			not changed
			and String(current_ref.get("service_occupation_id", ""))
				== next_occupation
		):
			continue
		var current := current_ref.duplicate(true)
		current["owner_id"] = next_owner
		current["open"] = next_open
		current["service_occupation_id"] = next_occupation
		if changed:
			current["source_revision"] = int(
				current.get("source_revision", 0),
			) + 1
			current["updated_at"] = now
		_place_service_states[place_id] = current
		if changed:
			_refresh_place_service_pressure(place_id)
			if old_open != next_open:
				_emit_place_service_open_change(
					place_id,
					next_open,
					String(current.get("owner_id", "")),
				)
	_sync_vacant_mobile_service_fallbacks()


func _advance_social_matters(absolute_minute: int) -> void:
	_social_matters.expire_exposures(absolute_minute)
	var actionable_resident_ids := (
		_social_matters.actionable_exposure_resident_ids(
			_resident_order,
			absolute_minute,
		) as Array[String]
	)
	for resident_id: String in actionable_resident_ids:
		_schedule_decision(resident_id, false)
	for matter_id: String in _social_matters.timeout_due_response_rounds(
		absolute_minute,
	) as Array[String]:
		var settled := _social_matters.settle_response_round(
			matter_id,
			absolute_minute,
			"reopen",
		) as Dictionary
		if settled.get("ok") == true:
			_reconcile_social_assignments(matter_id)
			_maybe_begin_social_response_after_exposures(matter_id)
			_emit_social_matter_summary(matter_id)
	var closed := _social_matters.expire_due(
		absolute_minute,
	) as Array[Dictionary]
	for matter: Dictionary in closed:
		_emit_social_matter_summary(
			String(matter.get("matter_id", "")),
		)
	_expire_animal_public_attention(absolute_minute)
	if not closed.is_empty():
		_schedule_social_receipt_wakes()


func _expire_animal_public_attention(absolute_minute: int) -> void:
	var changed := false
	for animal_id_value: Variant in _animal_facts:
		var animal_id := String(animal_id_value)
		var fact := (
			_animal_facts.get(animal_id, {}) as Dictionary
		)
		if (
			not bool(fact.get("public_attention", false))
			or int(fact.get("expires_at", -1)) > absolute_minute
		):
			continue
		fact["public_attention"] = false
		fact["source_revision"] = int(
			fact.get("source_revision", 0)
		) + 1
		fact["updated_at"] = absolute_minute
		_animal_facts[animal_id] = fact
		changed = true
	if changed:
		_bump_world_revision(false)


func _world_data_has_activity_at_place(
	world_data: Dictionary,
	activity_id: String,
	place_id: String,
) -> bool:
	return ACTION_SUPPORT.world_data_has_activity_at_place(self, world_data, activity_id, place_id)


func _advance_conflict_runtime() -> void:
	if _conflict_controller == null:
		return
	var before_revision := _conflict_runtime_revision()
	var result := _conflict_controller.advance() as Dictionary
	_complete_conflict_command(result, before_revision)


func _connect_conflict_controller_signals() -> void:
	if _conflict_controller == null:
		return
	for binding: Array in [
		["conflict_projection_changed", "_on_conflict_projection_changed"],
		["conflict_event_created", "_on_conflict_event_created"],
		["conflict_follow_up_required", "_on_conflict_follow_up_required"],
	]:
		var callback := Callable(self, String(binding[1]))
		if not _conflict_controller.is_connected(String(binding[0]), callback):
			_conflict_controller.connect(String(binding[0]), callback)


func _disconnect_conflict_controller_signals() -> void:
	if _conflict_controller == null:
		return
	for binding: Array in [
		["conflict_projection_changed", "_on_conflict_projection_changed"],
		["conflict_event_created", "_on_conflict_event_created"],
		["conflict_follow_up_required", "_on_conflict_follow_up_required"],
	]:
		var callback := Callable(self, String(binding[1]))
		if _conflict_controller.is_connected(String(binding[0]), callback):
			_conflict_controller.disconnect(String(binding[0]), callback)


func _on_conflict_projection_changed(projection: Dictionary) -> void:
	conflict_projection_changed.emit(projection.duplicate(true))
	var wake_priorities := _pending_conflict_knowledge_wakes.duplicate()
	_pending_conflict_knowledge_wakes.clear()
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		if resident.is_empty() or not _resident_is_present(resident):
			continue
		var nearby_ids: Array[String] = []
		for nearby_name: Variant in resident.get("nearby", []) as Array:
			var nearby_id := _person_id_for_name(String(nearby_name))
			if not nearby_id.is_empty():
				nearby_ids.append(nearby_id)
		var snapshot := _agent_conflict_snapshot(
			resident_id,
			resident,
			nearby_ids,
		)
		var direct_participant := false
		for conflict_value: Variant in snapshot.get("conflicts", []) as Array:
			if (
				conflict_value is Dictionary
				and String((conflict_value as Dictionary).get("role", "witness"))
				!= "witness"
			):
				direct_participant = true
				break
		if (
			direct_participant
			or not (snapshot.get("conflict_tension_options", []) as Array).is_empty()
		):
			wake_priorities[resident_id] = true
	var wake_resident_ids: Array[String] = []
	wake_resident_ids.assign(wake_priorities.keys())
	wake_resident_ids.sort()
	for resident_id: String in wake_resident_ids:
		var urgent := bool(wake_priorities.get(resident_id, false))
		_schedule_decision(resident_id, urgent, false, urgent)


func _on_conflict_event_created(event: Dictionary) -> void:
	_append_conflict_log_event(event)
	_queue_conflict_knowledge(event)
	conflict_event_created.emit(event.duplicate(true))


func _on_conflict_follow_up_required(follow_up: Dictionary) -> void:
	# Medical routing is a separate owner. This signal is the formal hand-off.
	conflict_follow_up_required.emit(follow_up.duplicate(true))


func _queue_conflict_knowledge(event: Dictionary) -> void:
	var actor_ids := _conflict_event_actor_ids(event)
	if actor_ids.is_empty():
		return
	var actor_names := {}
	for actor_id: String in actor_ids:
		actor_names[actor_id] = _person_name_for_id(actor_id)
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		if resident.is_empty() or not _resident_is_present(resident):
			continue
		var knowledge_kind := ""
		if actor_ids.has(resident_id):
			knowledge_kind = "participant"
		elif _resident_witnesses_conflict(resident, actor_ids):
			knowledge_kind = "witness"
		else:
			continue
		var projected := CONFLICT_KNOWLEDGE_PROJECTOR.project(
			event,
			knowledge_kind,
			actor_names,
		) as Dictionary
		if projected.get("ok") != true:
			continue
		var private_event := (
			projected.get("event", {}) as Dictionary
		).duplicate(true)
		private_event["event_id"] = _next_world_event_id()
		private_event["time"] = get_time()
		_enqueue_world_event(resident_id, private_event, false)
		_pending_conflict_knowledge_wakes[resident_id] = (
			bool(_pending_conflict_knowledge_wakes.get(resident_id, false))
			or knowledge_kind == "participant"
		)


func _conflict_event_actor_ids(event: Dictionary) -> Array[String]:
	return RUNTIME_LOG_TEXT.conflict_event_actor_ids(event)


func _resident_witnesses_conflict(
	resident: Dictionary,
	actor_ids: Array[String],
) -> bool:
	for nearby_name: Variant in resident.get("nearby", []) as Array:
		if actor_ids.has(_person_id_for_name(String(nearby_name))):
			return true
	return false


func _append_conflict_log_event(event: Dictionary) -> void:
	var event_id := String(event.get("eventId", "")).strip_edges()
	var conflict_id := String(
		event.get("rootConflictId", event.get("conflictId", ""))
	).strip_edges()
	var source_type := String(event.get("type", "")).strip_edges()
	if event_id.is_empty() or conflict_id.is_empty() or source_type.is_empty():
		return
	var source_actor_id := String(event.get("sourceActorId", "")).strip_edges()
	_append_world_log_event(
		event_id,
		"conflict_event",
		source_actor_id,
		_person_name_for_id(source_actor_id),
		String(event.get("placeId", "")),
		{
			"type": _conflict_log_event_type(source_type),
			"conflictId": conflict_id,
			"conflictEventType": source_type,
			"status": (
				"completed"
				if source_type in [
					"conflict_apologized",
					"conflict_disengaged",
					"conflict_ended",
				]
				else "ongoing"
			),
			"participantIds": _conflict_event_actor_ids(event),
			"sourceActorId": source_actor_id,
			"subjectId": String(event.get("subjectId", "")),
			"severity": String(event.get("severity", "")),
			"reason": String(event.get("reason", "")),
			"causeId": String(event.get("causeId", "")),
			"causeSummary": String(event.get("causeSummary", "")),
			"sourceConversationId": String(
				event.get("sourceConversationId", "")
			),
			"causedByEventIds": (
				event.get("sourceEventIds", []) as Array
			).duplicate(true),
			"occurredAtMinute": int(event.get("occurredAtMinute", -1)),
			"summary": _conflict_log_summary(event),
		},
	)


func _conflict_log_event_type(source_type: String) -> String:
	return RUNTIME_LOG_TEXT.conflict_log_event_type(source_type)


func _conflict_log_summary(event: Dictionary) -> String:
	return RUNTIME_LOG_TEXT.conflict_log_summary(event)


func _conflict_actor_is_available(actor_id: String) -> bool:
	var normalized := actor_id.strip_edges()
	if normalized.is_empty():
		return false
	if normalized == _player_avatar_id():
		return _player_avatar_present
	var resident := _residents.get(normalized, {}) as Dictionary
	return not resident.is_empty() and _resident_is_present(resident)


func _complete_conflict_command(
	result: Dictionary,
	before_revision: int,
) -> Dictionary:
	if (
		result.get("ok") == true
		and _conflict_runtime_revision() != before_revision
	):
		_bump_world_revision(false)
		_notify_world_revision()
	var decorated := _decorate_command_result(result)
	decorated["conflict"] = get_public_conflict_projection()
	return decorated


func _conflict_runtime_revision() -> int:
	return int(get_public_conflict_projection().get("revision", 0))


func _empty_conflict_projection() -> Dictionary:
	return CONFLICT_JUDGMENTS.empty_conflict_projection()


func _command_failure(
	error_code: String,
	errors: Array,
	extra: Dictionary = {},
	retryable := false,
) -> Dictionary:
	var result := {"ok": false, "errors": errors.duplicate(true)}
	for key: Variant in extra:
		var value: Variant = extra[key]
		if value is Dictionary:
			result[key] = (value as Dictionary).duplicate(true)
		elif value is Array:
			result[key] = (value as Array).duplicate(true)
		else:
			result[key] = value
	return _decorate_command_result(result, error_code, retryable)


func _decorate_command_result(
	source: Dictionary,
	error_code_on_failure := "",
	retryable := false,
) -> Dictionary:
	var result := source.duplicate(true)
	var ok: bool = result.get("ok") == true
	if ok:
		result["errorCode"] = ""
		result["retryable"] = false
	else:
		result["errorCode"] = (
			String(error_code_on_failure)
			if not String(error_code_on_failure).is_empty()
			else String(result.get("errorCode", ""))
		)
		result["retryable"] = (
			retryable
			if not String(error_code_on_failure).is_empty()
			else bool(result.get("retryable", false))
		)
	result["worldRevision"] = _world_revision
	return result


func _ensure_resident_sleep_started(
	resident_id: String,
	action: Dictionary,
	execution: Dictionary,
) -> bool:
	if String(execution.get("activityId", "")) != "activity_home_sleep":
		return false
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return false
	var active := _resident_sleep.get_active_sleep(resident_id,) as Dictionary
	if not active.is_empty():
		return false
	var sleep_started_at := int(action.get("startedAbsoluteMinute", 0)) + (
		_prop_approach_duration_minutes(action)
	)
	_resident_sleep.start_sleep(resident_id,
		action_id,
		sleep_started_at,
		maxi(1, int(action.get("durationMinutes", 0))),)
	return true


func _settle_resident_activity_condition(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	execution: Dictionary,
	status: String,
	reason: String,
) -> void:
	if execution.is_empty() or _environment == null:
		return
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return
	var occurred_at := int(_environment.get_absolute_minute())
	var activity_id := String(execution.get("activityId", ""))
	var condition_result: Dictionary = {}
	if activity_id == SLEEP_ACTIVITY_ID:
		_clear_sleep_leave(resident)
		var active_sleep := _resident_sleep.get_active_sleep(resident_id,) as Dictionary
		if active_sleep.is_empty():
			return
		var sleep_finish := _resident_sleep.finish_sleep(resident_id,
			action_id,
			occurred_at,
			status != "completed",
			reason if not reason.strip_edges().is_empty() else status,) as Dictionary
		if sleep_finish.get("ok") != true:
			return
		condition_result = _resident_conditions.submit_sleep_result(resident_id,
			sleep_finish.get("sleepResult", {}) as Dictionary,
			_resident_condition_life_state(resident),) as Dictionary
	else:
		var performing_started_at := int(
			action.get("startedAbsoluteMinute", occurred_at),
		) + _prop_approach_duration_minutes(action)
		performing_started_at = mini(performing_started_at, occurred_at)
		condition_result = _resident_conditions.submit_activity_execution_result(resident_id,
			{
				"resultId": "activity:%s:%s" % [action_id, status],
				"activityId": activity_id,
				"actionId": action_id,
				"startedAtMinute": performing_started_at,
				"occurredAtMinute": occurred_at,
				"status": status,
				"placeId": String(execution.get("placeId", "")),
				"weather": get_weather(),
				"outdoors": String(resident.get("spaceId", "")) == "town_outdoor",
			},
			_resident_condition_life_state(resident),) as Dictionary
	_record_resident_condition_result(resident_id, condition_result)


func _settle_resident_route_condition(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	status: String,
) -> void:
	if _environment == null or String(action.get("type", "")) != "去":
		return
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return
	var started_at := int(action.get("startedAbsoluteMinute", 0))
	var occurred_at := int(_environment.get_absolute_minute())
	var actual_duration := clampi(
		occurred_at - started_at,
		0,
		maxi(0, int(action.get("durationMinutes", 0))),
	)
	# Ordinary short walks do not receive a hidden incident roll. A route must
	# contain a meaningful amount of exertion before it can create a candidate.
	if actual_duration < 20:
		return
	var route := action.get("route", {}) as Dictionary
	var was_outdoors := false
	for sample_value: Variant in route.get("minutePositions", []) as Array:
		if (
			sample_value is Dictionary
			and String((sample_value as Dictionary).get("spaceId", ""))
			== "town_outdoor"
		):
			was_outdoors = true
			break
	var result := _resident_conditions.submit_world_action_result(resident_id,
		{
			"resultId": "route:%s:%s" % [action_id, status],
			"sourceKind": "route",
			"sourceRef": action_id,
			"startedAtMinute": started_at,
			"occurredAtMinute": occurred_at,
			"status": status,
			"riskTags": ["physical_exertion"],
			"reliefTags": [],
			"context": {
				"fromPlaceId": String(route.get("fromPlaceName", "")),
				"toPlaceId": String(action.get("place", "")),
				"weather": get_weather(),
				"outdoors": was_outdoors,
			},
		},
		_resident_condition_life_state(resident),) as Dictionary
	_record_resident_condition_result(resident_id, result)


func _resident_condition_life_state(resident: Dictionary) -> Dictionary:
	var state := resident.get(
		"activityState",
		_empty_activity_state(),
	) as Dictionary
	var result: Dictionary = {}
	for field_value: Variant in ACTIVITY_STATE_KEYS:
		var field := String(field_value)
		result[field] = clampf(float(state.get(field, 50.0)), 0.0, 100.0)
	return result


func _record_resident_condition_result(
	resident_id: String,
	result: Dictionary,
) -> void:
	if result.get("ok") != true:
		return
	for event_value: Variant in result.get("events", []) as Array:
		if not event_value is Dictionary:
			continue
		var event := (event_value as Dictionary).duplicate(true)
		var public_event_id := _next_world_event_id()
		_append_public_event_log(
			public_event_id,
			"world_event",
			resident_id,
			_resident_display_name(resident_id),
			String(
				(_residents.get(resident_id, {}) as Dictionary).get(
					"currentPlace",
					"",
				),
			),
			event,
		)
		var agent_event := event.duplicate(true)
		agent_event["event_id"] = public_event_id
		agent_event["time"] = get_time()
		agent_event["type"] = "身体状况变化"
		_enqueue_world_event(resident_id, agent_event)


func _clinic_interview_binding_for_pair(
	clinician_resident_id: String,
	patient_resident_id: String,
) -> Dictionary:
	var clinician := _residents.get(
		clinician_resident_id,
		{},
	) as Dictionary
	var patient := _residents.get(patient_resident_id, {}) as Dictionary
	if (
		clinician.is_empty()
		or patient.is_empty()
		or String(clinician.get("currentPlace", "")) != CONTENT_CATALOG.PLACE_CLINIC
		or String(patient.get("currentPlace", "")) != CONTENT_CATALOG.PLACE_CLINIC
	):
		return {}
	for task_value: Variant in get_work_tasks_for_resident(
		clinician_resident_id,
	):
		var task := task_value as Dictionary
		var service_request := (
			task.get("service_request", {}) as Dictionary
		)
		var medical_dialogue := (
			service_request.get("medical_dialogue", {}) as Dictionary
		)
		if (
			String(service_request.get("kind", "")) == "clinic"
			and String(
				service_request.get("requester_resident_id", ""),
			) == patient_resident_id
			and String(medical_dialogue.get("status", ""))
			in ["required", "interrupted"]
		):
			return {
				"requestId": String(
					service_request.get("request_id", ""),
				),
				"taskId": String(task.get("task_id", "")),
			}
	return {}


func _clinic_interview_projection_for_participant(
	conversation: Dictionary,
	participant_resident_id: String,
) -> Variant:
	var linked := CONVERSATION_RUNTIME._clinic_interview_for_conversation(self, conversation)
	if linked.is_empty():
		return null
	var interview := linked.get("context", {}) as Dictionary
	var role := (
		"patient"
		if String(interview.get("patientResidentId", ""))
		== participant_resident_id
		else "clinician"
	)
	return (
		_clinic_interviews.projection_for_role(interview,
			role,) as Dictionary
	).duplicate(true)


func _record_clinic_interview_response(
	conversation: Dictionary,
	speaker_resident_id: String,
	action: Dictionary,
	turn_id: int,
) -> void:
	var response_value: Variant = action.get("medical_response")
	if response_value == null or not response_value is Dictionary:
		return
	var linked := CONVERSATION_RUNTIME._clinic_interview_for_conversation(self, conversation)
	if linked.is_empty():
		return
	var interview := linked.get("context", {}) as Dictionary
	if String(interview.get("patientResidentId", "")) != speaker_resident_id:
		return
	var response := response_value as Dictionary
	var recorded := _clinic_interviews.record_patient_response(interview,
		String(conversation.get("conversationId", "")),
		String(response.get("response_kind", "")),
		turn_id,) as Dictionary
	if recorded.get("ok") != true:
		return
	var request := linked.get("request", {}) as Dictionary
	_occupation_services.merge_request_context(String(request.get("requestId", "")),
		{"medicalInterview": recorded.get("context", {})},)
	_bump_world_revision(false)


func _advance_resident_conditions(absolute_minute: int) -> void:
	var weather := get_weather()
	var weather_is_exposure := weather in [
		"小雨",
		"中雨",
		"大雨",
		"雷暴",
		"下雪",
	]
	for resident_id in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		if not _resident_is_present(resident):
			continue
		var outdoors := String(resident.get("spaceId", "")) == "town_outdoor"
		var active := _resident_conditions.get_active_exposure(resident_id,) as Dictionary
		var active_facts := active.get("facts", {}) as Dictionary
		var exposure_still_matches := (
			not active.is_empty()
			and outdoors
			and weather_is_exposure
			and String(active_facts.get("weather", "")) == weather
		)
		if not active.is_empty() and not exposure_still_matches:
			_resident_conditions.end_ambient_exposure(resident_id,
				String(active.get("exposureId", "")),)
			active = {}
		if active.is_empty() and outdoors and weather_is_exposure:
			var started := _resident_conditions.begin_world_weather_exposure(resident_id,
				{
					"exposureId": "weather-exposure:%s:%d" % [
						resident_id,
						absolute_minute,
					],
					"sourceKind": "weather_exposure",
					"sourceRef": "weather:%s:%d" % [
						weather,
						absolute_minute,
					],
					"startedAtMinute": absolute_minute,
					"weather": weather,
					"outdoors": true,
					"placeId": String(resident.get("currentPlace", "")),
					"riskTags": ["weather_exposure"],
				},) as Dictionary
			if started.get("ok") == true:
				active = _resident_conditions.get_active_exposure(resident_id,) as Dictionary
		var context := {
			"riskTags": (
				(active.get("riskTags", []) as Array).duplicate()
				if not active.is_empty()
				else []
			),
			"reliefTags": [],
			"lifeState": _resident_condition_life_state(resident),
		}
		var advanced := _resident_conditions.advance_resident(resident_id,
			absolute_minute,
			context,) as Dictionary
		if (
			advanced.get("ok") == true
			and not (advanced.get("events", []) as Array).is_empty()
		):
			_record_resident_condition_result(resident_id, advanced)
			_bump_world_revision(false)
			_emit_resident_state_changed(resident_id)


func _clinic_request_needs_basic_care(
	patient_resident_id: String,
	request_context: Dictionary,
) -> bool:
	if bool(request_context.get("conflictInjuryRequiresTreatment", false)):
		return true
	var requested_ids: Array = request_context.get("conditionIds", []) as Array
	if requested_ids.is_empty():
		return false
	for condition_value: Variant in _resident_conditions.get_conditions(patient_resident_id,) as Array:
		if not condition_value is Dictionary:
			continue
		var condition := condition_value as Dictionary
		var condition_id := String(condition.get("conditionId", ""))
		if (
			requested_ids.has(condition_id)
			and bool(_resident_conditions.condition_accepts_relief(patient_resident_id,
				condition_id,
				"basic_care",))
		):
			return true
	return false


func _begin_conflict_injury_treatment(
	resident_id: String,
	place_id: String,
) -> Dictionary:
	if _conflict_controller == null:
		return {
			"ok": false,
			"errorCode": "CONFLICT_CONTROLLER_NOT_CONFIGURED",
		}
	return _conflict_controller.begin_treatment(resident_id, place_id) as Dictionary


func _validate_medical_response_for_world(
	resident_id: String,
	action: Dictionary,
) -> String:
	if not action.has("medical_response") or action.get("medical_response") == null:
		return ""
	var response_value: Variant = action.get("medical_response")
	if not response_value is Dictionary:
		return "medical_response 必须是对象或 null"
	var response := response_value as Dictionary
	if response.size() != 2 or not response.has("request_id") or not response.has("response_kind"):
		return "medical_response 只能包含 request_id 和 response_kind"
	if (
		not response.get("request_id") is String
		or String(response.get("request_id", "")).strip_edges().is_empty()
		or not response.get("response_kind") is String
		or String(response.get("response_kind", "")).strip_edges().is_empty()
	):
		return "medical_response 缺少合法的请求编号或回应类型"
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(self, resident_id)
	var medical: Dictionary = _clinic_interview_projection_for_participant(
		conversation,
		resident_id,
	)
	if medical.is_empty():
		return "medical_response 只能在当前医患对话中提交"
	if String(medical.get("role", "")) != "patient":
		return "只有患者本人能提交 medical_response"
	if String(response.get("request_id", "")) != String(medical.get("request_id", "")):
		return "medical_response 的请求编号与当前医患对话不一致"
	if not (medical.get("response_options", []) as Array).has(
		String(response.get("response_kind", "")),
	):
		return "medical_response 的回应类型不在当前选项中"
	return ""

func _resident_is_actively_processing_work_task(
	resident_id: String,
	task_id: String,
) -> bool:
	if resident_id.is_empty() or task_id.is_empty():
		return false
	var resident := _residents.get(resident_id, {}) as Dictionary
	var current_action_id := String(
		(resident.get("currentAction", {}) as Dictionary).get(
			"action_id",
			"",
		),
	)
	if current_action_id.is_empty():
		return false
	return String(_activity_work_task_bindings.get(
		"%s:%s" % [resident_id, current_action_id],
		"",
	)) == task_id


func _apply_clinic_visitor_activity_availability(
	resident_id: String,
	option: Dictionary,
) -> void:
	if not bool(option.get("available", false)):
		return
	var activity_id := String(option.get("activityId", ""))
	if activity_id not in [
		"activity_clinic_consult",
		"activity_clinic_examination",
	]:
		return
	var request := _active_clinic_request_for_resident(resident_id)
	if activity_id == "activity_clinic_consult":
		if request.is_empty():
			return
		option["available"] = false
		option["disabledReason"] = "CLINIC_REQUEST_ALREADY_ACTIVE"
		return
	if request.is_empty():
		option["available"] = false
		option["disabledReason"] = "CLINIC_REQUEST_REQUIRED"
		return
	var interview := (
		(request.get("context", {}) as Dictionary).get(
			"medicalInterview",
			{},
		) as Dictionary
	)
	var task := _work_tasks.task(String(request.get("taskId", "")),) as Dictionary
	if (
		String(interview.get("status", "")) != "completed"
		or String(task.get("processStage", ""))
		!= "ready_examination"
	):
		option["available"] = false
		option["disabledReason"] = "CLINIC_EXAMINATION_NOT_READY"


func _active_clinic_request_for_resident(resident_id: String) -> Dictionary:
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		if not request_value is Dictionary:
			continue
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "clinic"
			and String(request.get("requesterResidentId", ""))
			== resident_id
			and String(request.get("state", ""))
			in ["pending", "waiting", "in_progress"]
		):
			return request.duplicate(true)
	return {}


func _apply_clinic_practitioner_request_priority(
	resident_id: String,
	option: Dictionary,
) -> void:
	if not bool(option.get("available", false)):
		return
	var task := _active_clinic_consult_task_for_practitioner(resident_id)
	if task.is_empty():
		return
	var activity_id := String(option.get("activityId", ""))
	if not activity_id.begins_with("activity_clinic_"):
		return
	var service_request := task.get("service_request", {}) as Dictionary
	var medical_dialogue := (
		service_request.get("medical_dialogue", {}) as Dictionary
	)
	var interview_status := String(
		medical_dialogue.get("status", ""),
	)
	var allowed_activity_id := (
		"activity_clinic_receive_patient"
		if interview_status == "completed"
		else ""
	)
	if activity_id == allowed_activity_id:
		return
	option["available"] = false
	option["disabledReason"] = (
		"CLINIC_EXAMINATION_HAS_PRIORITY"
		if interview_status == "completed"
		else "CLINIC_INTERVIEW_HAS_PRIORITY"
	)


func _active_clinic_consult_task_for_practitioner(
	resident_id: String,
) -> Dictionary:
	if _occupation_id_for_resident(
		_residents.get(resident_id, {}) as Dictionary,
	) != "occupation_clinic_practitioner":
		return {}
	for task: Dictionary in get_work_tasks_for_resident(resident_id):
		var service_request := task.get(
			"service_request",
			{},
		) as Dictionary
		if (
			String(task.get("capability", "")) == "care.consult"
			and String(service_request.get("kind", "")) == "clinic"
			and String(service_request.get("state", ""))
			in ["pending", "waiting", "in_progress"]
		):
			return task.duplicate(true)
	return {}


func _record_started_clinic_request(
	resident_id: String,
	execution: Dictionary,
) -> void:
	if (
		String(execution.get("role", "")) != "visitor"
		or String(execution.get("activityId", ""))
		!= "activity_clinic_consult"
		or not _active_clinic_request_for_resident(resident_id).is_empty()
	):
		return
	var spec := _visitor_occupation_service_spec(
		resident_id,
		"activity_clinic_consult",
	)
	if not spec.is_empty():
		create_occupation_service_request(spec)


func _resident_is_completing_bound_clinic_work(
	resident_id: String,
	resident: Dictionary,
) -> bool:
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return false
	var execution := _activity_runtime.execution_for_action(resident_id,
		String(action.get("action_id", "")),) as Dictionary
	if String(execution.get("activityId", "")) not in [
		"activity_clinic_receive_patient",
		"activity_clinic_prepare_medicine",
	]:
		return false
	for occupation_id: String in _work_occupation_ids_for_resident(resident_id):
		for task_value: Variant in _work_tasks.tasks_for_occupation(occupation_id,
			resident_id,) as Array:
			var task := task_value as Dictionary
			if (
				String(task.get("assignedResidentId", "")) == resident_id
				and String(task.get("state", "")) == "in_progress"
				and String(task.get("capability", ""))
				in ["care.consult", "care.treatment"]
			):
				return true
	return false

func _duplicate_optional_dictionary(value: Variant) -> Variant:
	return ACTIVITY_SCALARS.duplicate_optional_dictionary(value)


func _authoritative_absolute_minute() -> int:
	# 分钟结算循环内取当前 tick 的分钟;循环外取环境时钟。
	if _processing_tick_absolute_minute >= 0:
		return _processing_tick_absolute_minute
	return int(_environment.get_absolute_minute())


func _onsite_service_wait_minutes(kind: String) -> int:
	return ACTIVITY_SCALARS.onsite_service_wait_minutes(kind)


func _begin_customer_service_wait(
	resident_id: String,
	request_id: String,
	place_id: String,
	context: Dictionary,
) -> void:
	if String(context.get("customerServiceMode", "")) != "onsite_wait":
		return
	var request := _occupation_services.request(request_id,) as Dictionary
	if String(request.get("state", "")) not in ["pending", "waiting"]:
		return
	var resident := _residents.get(resident_id, {}) as Dictionary
	if (
		resident.is_empty()
		or String(resident.get("currentPlace", "")) != place_id
		or not (resident.get("currentAction", {}) as Dictionary).is_empty()
	):
		return
	# 服务请求经常在访客动作的 completed 回调中创建。
	# 此时上一条动作结果可能已经放进正在等待派发的唤醒；
	# 切换到“现场等待”前必须先把这些事实放回队列。
	if bool(resident.get("decisionPending", false)):
		_agent_wake_preparation_runtime.clear_resident(String(resident.get("residentId", resident_id)), String(resident.get("validDecisionId", "")))
		_restore_inflight_facts(resident)
		resident["decisionPending"] = false
		resident["validDecisionId"] = ""
		resident["pendingWake"] = {}
		resident["wakeDispatchQueued"] = false
	var now := _authoritative_absolute_minute()
	resident["currentAction"] = {
		"type": "待着",
		"action_id": "service-wait:%s" % request_id,
		"line": "在这里等待服务",
		"startedAbsoluteMinute": now,
		"completeAbsoluteMinute": int(
			context.get("onsiteWaitUntilMinute", now + 30),
		),
		"serviceRequestId": request_id,
	}
	(resident.get("usedActionIds", {}) as Dictionary)[
		"service-wait:%s" % request_id
	] = true
	resident["doing"] = "正在等待服务"
	_bump_world_revision(false)
	_emit_resident_state_changed(resident_id)


func _sync_occupation_service_presence(absolute_minute: int) -> void:
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("state", "")) not in [
				"pending",
				"waiting",
				"in_progress",
			]
			or not _occupation_service_request_requires_presence(request)
		):
			continue
		var request_id := String(request.get("requestId", ""))
		if (
			String(request.get("kind", "")) == "clinic"
			and not _clinic_request_has_executable_practitioner(request)
		):
			_cancel_occupation_service_request(
				request,
				"诊所当前没有可以继续接诊的医生",
			)
			continue
		var requester_id := String(request.get("requesterResidentId", ""))
		var requester := _residents.get(requester_id, {}) as Dictionary
		var context := (request.get("context", {}) as Dictionary).duplicate(true)
		var mode := String(context.get("customerServiceMode", ""))
		if mode.is_empty():
			mode = (
				"preorder"
				if _occupation_service_preorder_needed(
					String(request.get("kind", "")),
					String(request.get("itemId", "")),
					String(request.get("placeId", "")),
				)
				else "onsite_wait"
			)
			var migration_patch := {"customerServiceMode": mode}
			if mode == "preorder":
				migration_patch["preorderExpiresAtMinute"] = (
					int(request.get("createdAtMinute", absolute_minute)) + 1440
				)
				migration_patch["customerNotifiedAtMinute"] = -1
			else:
				migration_patch["onsiteWaitUntilMinute"] = (
					int(request.get("createdAtMinute", absolute_minute))
					+ _onsite_service_wait_minutes(
						String(request.get("kind", "")),
					)
				)
				migration_patch["customerAbsentSinceMinute"] = -1
			_occupation_services.merge_request_context(
				request_id,
				migration_patch,
			)
			context.merge(migration_patch, true)
		if (
			mode == "onsite_wait"
			and not _occupation_service_kind_is_staffed(
				String(request.get("kind", "")),
			)
		):
			_cancel_occupation_service_request(
				request,
				"对应岗位当前无人值守",
			)
			continue
		var at_service_place := (
			not requester.is_empty()
			and String(requester.get("currentPlace", ""))
			== String(request.get("placeId", ""))
		)
		if mode == "preorder":
			if absolute_minute >= int(
				context.get("preorderExpiresAtMinute", absolute_minute + 1),
			):
				_cancel_occupation_service_request(
					request,
					"预订超过一天仍未领取",
				)
				continue
			if at_service_place:
				_schedule_occupation_service_worker(request)
			else:
				_maybe_notify_ready_preorder(request, absolute_minute)
			continue
		if (
			String(request.get("kind", "")) != "dining_order"
			and _onsite_service_queue_is_advancing(request)
		):
			var extended_wait_until := maxi(
				int(context.get("onsiteWaitUntilMinute", absolute_minute)),
				absolute_minute + _onsite_service_wait_minutes(
					String(request.get("kind", "")),
				),
			)
			if extended_wait_until != int(
				context.get("onsiteWaitUntilMinute", -1),
			):
				_occupation_services.merge_request_context(request_id,
					{"onsiteWaitUntilMinute": extended_wait_until},)
				context["onsiteWaitUntilMinute"] = extended_wait_until
		if (
			_occupation_service_wait_deadline_applies(request)
			and absolute_minute >= int(
				context.get("onsiteWaitUntilMinute", absolute_minute + 1),
			)
		):
			if String(request.get("kind", "")) == "dining_order":
				DINING_SERVICE.complete_as_takeaway(
					self,
					request,
					absolute_minute,
					"等待超过半小时，已经领取打包餐",
				)
			else:
				_cancel_occupation_service_request(request, "等待服务时间已结束")
			continue
		if at_service_place:
			if int(context.get("customerAbsentSinceMinute", -1)) >= 0:
				_occupation_services.merge_request_context(
					request_id,
					{"customerAbsentSinceMinute": -1},
				)
			if (
				String(request.get("state", "")) == "waiting"
				and String(request.get("waitReason", ""))
				== "请求人尚未到达服务地点"
			):
				_occupation_services.resume_request(request_id)
			_schedule_occupation_service_worker(request)
			continue
		var absent_since := int(context.get("customerAbsentSinceMinute", -1))
		if absent_since < 0:
			absent_since = absolute_minute
			_occupation_services.merge_request_context(
				request_id,
				{"customerAbsentSinceMinute": absent_since},
			)
		_pause_service_task_for_absent_request(request)
		if absolute_minute - absent_since >= 5:
			_cancel_occupation_service_request(request, "请求人已经离开服务地点")


func _resident_is_heading_to_service_request(
	resident_id: String,
	request: Dictionary,
) -> bool:
	return ACTION_SUPPORT.resident_is_heading_to_service_request(self, resident_id, request)


func _onsite_service_queue_is_advancing(request: Dictionary) -> bool:
	var task := _work_tasks.task(String(request.get("taskId", "")),) as Dictionary
	var assigned_resident_id := String(
		task.get("assignedResidentId", ""),
	)
	if assigned_resident_id.is_empty():
		return false
	if _resident_is_heading_to_service_request(
		assigned_resident_id,
		request,
	):
		return true
	var place_id := String(request.get("placeId", ""))
	for projected_task: Dictionary in get_work_tasks_for_resident(
		assigned_resident_id,
	):
		var task_id := String(projected_task.get("task_id", ""))
		if not _resident_is_actively_processing_work_task(
			assigned_resident_id,
			task_id,
		):
			continue
		var active_task := _work_tasks.task(task_id) as Dictionary
		var active_request := _occupation_services.request(String(active_task.get("sourceRef", "")),) as Dictionary
		if (
			String(active_request.get("placeId", "")) == place_id
			and String(
				(active_request.get("context", {}) as Dictionary).get(
					"customerServiceMode",
					"",
				),
			) == "onsite_wait"
		):
			return true
	return false


func _occupation_service_wait_deadline_applies(
	request: Dictionary,
) -> bool:
	if String(request.get("kind", "")) == "clinic":
		return not _clinic_request_has_active_execution(request)
	if not (request.get("outcome", {}) as Dictionary).is_empty():
		return false
	var task_id := String(request.get("taskId", ""))
	if task_id.is_empty():
		return true
	var task := _work_tasks.task(task_id) as Dictionary
	if String(task.get("state", "")) not in ["accepted", "in_progress"]:
		return true
	var assigned_resident_id := String(
		task.get("assignedResidentId", ""),
	)
	return not (
		_resident_is_actively_processing_work_task(
			assigned_resident_id,
			task_id,
		)
		or _resident_is_heading_to_service_request(
			assigned_resident_id,
			request,
		)
	)


func _clinic_request_has_active_execution(request: Dictionary) -> bool:
	var task_id := String(request.get("taskId", ""))
	if task_id.is_empty():
		return false
	var task := _work_tasks.task(task_id) as Dictionary
	var assigned_id := String(task.get("assignedResidentId", ""))
	if assigned_id.is_empty():
		return false
	var assigned := _residents.get(assigned_id, {}) as Dictionary
	if (
		not _resident_available_for_work(assigned)
		or not _resident_can_work_occupation(
			assigned_id,
			"occupation_clinic_practitioner",
		)
	):
		return false
	var action := assigned.get("currentAction", {}) as Dictionary
	var action_id := String(action.get("action_id", ""))
	if not action_id.is_empty():
		var binding_key := _bound_work_task_binding_key(
			assigned_id,
			action_id,
		)
		if String(_activity_work_task_bindings.get(binding_key, "")) == task_id:
			return true
	var medical_interview := (
		(request.get("context", {}) as Dictionary).get(
			"medicalInterview",
			{},
		) as Dictionary
	)
	if String(medical_interview.get("clinicianResidentId", "")) != assigned_id:
		return false
	var conversation_id := String(
		medical_interview.get("conversationId", ""),
	)
	if conversation_id.is_empty():
		return false
	return String(
		(_conversations.get(conversation_id, {}) as Dictionary).get(
			"status",
			"",
		),
	) == "active"


func _clinic_has_executable_practitioner() -> bool:
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		if (
			_resident_available_for_work(resident)
			and _resident_can_work_occupation(
				resident_id,
				"occupation_clinic_practitioner",
			)
		):
			return true
	return false


func _clinic_request_has_executable_practitioner(
	request: Dictionary,
) -> bool:
	if not _clinic_has_executable_practitioner():
		return false
	var task := _work_tasks.task(String(request.get("taskId", "")),) as Dictionary
	var assigned_id := String(task.get("assignedResidentId", ""))
	if assigned_id.is_empty():
		return true
	var assigned := _residents.get(assigned_id, {}) as Dictionary
	return (
		_resident_available_for_work(assigned)
		and _resident_can_work_occupation(
			assigned_id,
			"occupation_clinic_practitioner",
		)
	)


func _schedule_occupation_service_worker(request: Dictionary) -> void:
	var task := _work_tasks.task(String(request.get("taskId", "")),) as Dictionary
	var can_interrupt := _task_allows_current_activity_interrupt(task)
	var assigned_resident_id := String(
		task.get("assignedResidentId", ""),
	)
	if not assigned_resident_id.is_empty():
		if _resident_is_actively_processing_work_task(
			assigned_resident_id,
			String(task.get("taskId", "")),
		):
			return
		_schedule_decision(assigned_resident_id, can_interrupt, false, can_interrupt)
		return
	var definition := _occupation_service_definition(
		String(request.get("kind", "")),
	)
	var occupation_id := String(definition.get("occupationId", ""))
	if occupation_id.is_empty():
		return
	for resident_id: String in _resident_order:
		if _resident_can_work_occupation(resident_id, occupation_id):
			_schedule_decision(resident_id, can_interrupt, false, can_interrupt)


func _pause_service_task_for_absent_request(request: Dictionary) -> void:
	var request_id := String(request.get("requestId", ""))
	var task := _work_tasks.task(
		String(request.get("taskId", "")),
	) as Dictionary
	if task.is_empty():
		return
	var assigned_id := String(task.get("assignedResidentId", ""))
	if not assigned_id.is_empty():
		for binding_key_value: Variant in _activity_work_task_bindings:
			if String(_activity_work_task_bindings.get(binding_key_value, "")) != (
				String(task.get("taskId", ""))
			):
				continue
			if String(binding_key_value).begins_with("%s:" % assigned_id):
				_interrupt_action(assigned_id, "顾客已经离开，服务暂时停下")
				break
		task = _work_tasks.task(String(task.get("taskId", ""))) as Dictionary
		if (
			String(task.get("state", "")) in ["accepted", "in_progress"]
			and String(task.get("assignedResidentId", "")) == assigned_id
		):
			_work_tasks.release_task(
				String(task.get("taskId", "")),
				assigned_id,
				int(task.get("revision", 0)),
				"请求人尚未到达服务地点",
			)
	_occupation_services.mark_waiting(
		request_id,
		"请求人尚未到达服务地点",
	)


func _cancel_occupation_service_request(
	request: Dictionary,
	reason: String,
) -> void:
	var request_id := String(request.get("requestId", ""))
	var task := _work_tasks.task(
		String(request.get("taskId", "")),
	) as Dictionary
	var medical_interview := (
		(request.get("context", {}) as Dictionary).get(
			"medicalInterview",
			{},
		) as Dictionary
	)
	var medical_conversation_id := String(
		medical_interview.get("conversationId", ""),
	)
	if not medical_conversation_id.is_empty():
		var medical_conversation := _conversations.get(
			medical_conversation_id,
			{},
		) as Dictionary
		if String(medical_conversation.get("status", "")) == "active":
			CONVERSATION_RUNTIME._end_conversation(self, 
				medical_conversation_id,
				"无法继续",
				"interrupted",
			)
	var task_id := String(task.get("taskId", ""))
	var assigned_id := String(task.get("assignedResidentId", ""))
	if not task_id.is_empty() and not assigned_id.is_empty():
		for binding_key_value: Variant in _activity_work_task_bindings.keys():
			var binding_key := String(binding_key_value)
			if (
				String(_activity_work_task_bindings.get(binding_key, ""))
				!= task_id
			):
				continue
			if binding_key.begins_with("%s:" % assigned_id):
				var assigned_action := (
					_residents.get(assigned_id, {}) as Dictionary
				).get("currentAction", {}) as Dictionary
				if not assigned_action.is_empty():
					_interrupt_action(assigned_id, reason)
				_activity_work_task_bindings.erase(binding_key)
	if not task.is_empty() and String(task.get("state", "")) not in [
		"completed", "failed", "cancelled",
	]:
		_work_tasks.cancel_task(String(task.get("taskId", "")), reason)
	_occupation_services.cancel_request(request_id, reason)
	if bool(_occupation_service_definition(
		String(request.get("kind", "")),
	).get("placeService", false)):
		record_place_service_request(
			String(request.get("placeId", "")),
			request_id,
			false,
		)
	if String(
		(request.get("context", {}) as Dictionary).get(
			"customerServiceMode",
			"",
		),
	) == "preorder":
		_cancel_private_messages_for_source(
			"preorder:%s" % request_id,
			reason,
		)
		_close_resident_request_source(
			"preorder-pickup:%s" % request_id,
			"preorder-cancelled",
		)
	_finish_customer_service_wait(
		String(request.get("requesterResidentId", "")),
		request_id,
		"没有等到服务，这次请求已经取消",
	)
	if not assigned_id.is_empty() and _residents.has(assigned_id):
		_schedule_decision(assigned_id, true)


func _finish_customer_service_wait(
	resident_id: String,
	request_id: String,
	reason: String,
	resume_activity_routine := false,
) -> void:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if (
		String(action.get("type", "")) == "待着"
		and String(action.get("serviceRequestId", "")) == request_id
	):
		_finish_action(resident_id, reason)
		if resume_activity_routine:
			_continue_activity_routine(resident_id)
		elif _activity_routines.has(resident_id):
			_close_activity_routine(
				resident_id,
				"interrupted",
				reason,
			)


func _begin_conversation_service_collection(
	resident_id: String,
	resident: Dictionary,
	previous_action: Dictionary,
) -> bool:
	if not _conversation_fetch_service_is_available(previous_action):
		_begin_conversation_follow_up_reconsideration(
			resident_id,
			"到达后发现服务地点已经停业或不再提供这项服务",
		)
		return true
	var now := int(_environment.get_absolute_minute())
	var next_action := {
		"action_id": String(previous_action.get("action_id", "")),
		"type": "待着",
		"line": "正在取%s" % String(
			previous_action.get("followUpServiceLabel", "东西"),
		),
		"startedAbsoluteMinute": now,
		"completeAbsoluteMinute": now + SERVICE_FETCH_DURATION_MINUTES,
	}
	_copy_conversation_follow_up_state(previous_action, next_action)
	next_action["followUpPhase"] = "collecting"
	next_action["followUpCollectUntilMinute"] = (
		now + SERVICE_FETCH_DURATION_MINUTES
	)
	_install_conversation_follow_up_action(
		resident_id,
		resident,
		next_action,
		"正在%s取%s" % [
			String(previous_action.get("followUpServicePlace", "服务地点")),
			String(previous_action.get("followUpServiceLabel", "东西")),
		],
	)
	return true


func _conversation_fetch_service_is_available(action: Dictionary) -> bool:
	var place_id := String(action.get("followUpServicePlace", ""))
	var activity_id := String(
		action.get("followUpServiceActivityId", ""),
	)
	var state := _place_service_states.get(place_id, {}) as Dictionary
	return (
		not state.is_empty()
		and bool(state.get("open", false))
		and _world_data_has_activity_at_place(
			_world_data,
			activity_id,
			place_id,
		)
	)


func _conversation_service_fetch_offerings(
	resident: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for state_value: Variant in _place_service_states.values():
		var state := state_value as Dictionary
		if not bool(state.get("open", false)):
			continue
		var place_id := String(state.get("place_id", ""))
		if place_id.is_empty() or _closed_service_place_for_visitor(
			resident,
			place_id,
		):
			continue
		var detail := get_place_detail(place_id)
		var capabilities := detail.get("capabilities", {}) as Dictionary
		var activity_id := ""
		var service_label := ""
		if bool(capabilities.get("food.prepare", false)):
			for request_value: Variant in state.get(
				"request_activity_ids",
				[],
			) as Array:
				var request_id := String(request_value)
				if _world_data_has_activity_at_place(
					_world_data,
					request_id,
					place_id,
				):
					activity_id = request_id
					break
			service_label = "一份饭菜"
		elif (
			bool(capabilities.get("drink.prepare", false))
			and _world_data_has_activity_at_place(
				_world_data,
				"activity_cafe_eat_pastry",
				place_id,
			)
		):
			activity_id = "activity_cafe_eat_pastry"
			service_label = "一份点心"
		if activity_id.is_empty() or service_label.is_empty():
			continue
		var route_available := (
			place_id == String(resident.get("currentPlace", ""))
			or not (
				_prepare_go_action(
					resident,
					{
						"action_id": "conversation-service-query",
						"type": "去",
						"place": place_id,
						"line": "查询服务地点",
					},
				).get("action", {}) as Dictionary
			).is_empty()
		)
		if not route_available:
			continue
		result.append({
			"place_id": place_id,
			"activity_id": activity_id,
			"service_label": service_label,
		})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("place_id", "")) < String(
				right.get("place_id", ""),
			)
	)
	return result


func _close_resident_request_source(
	source_id: String,
	result_id: String,
) -> void:
	var now := int(_environment.get_absolute_minute())
	for value: Variant in _social_matters.list_matters(
		false,
	) as Array:
		var matter := value as Dictionary
		var source_ref := matter.get("source_state_ref", {}) as Dictionary
		if (
			String(source_ref.get("source_kind", "")) != "resident_request"
			or String(source_ref.get("source_id", "")) != source_id
		):
			continue
		var closed := _social_matters.update_source_state(
			String(matter.get("matter_id", "")),
			int(source_ref.get("source_revision", 1)) + 1,
			false,
			now,
			[{"result_id": result_id}],
		) as Dictionary
		if closed.get("ok") == true:
			_finalize_social_mutation(
				closed,
				String(matter.get("matter_id", "")),
			)
		return


func _settle_clinic_condition_result(
	request: Dictionary,
	task: Dictionary,
	worker_resident_id: String,
	outcome: Dictionary,
	now: int,
	execution: Dictionary,
) -> void:
	var patient_id := String(request.get("requesterResidentId", ""))
	if not _residents.has(patient_id):
		return
	var request_context := request.get("context", {}) as Dictionary
	if bool(request_context.get("generatedFromConflictInjury", false)):
		return
	var condition_ids := (
		request_context.get("conditionIds", []) as Array
	).duplicate()
	if condition_ids.is_empty():
		return
	var capability := String(task.get("capability", ""))
	var relief_tags := (
		["care_examine", "indoor_dry"]
		if capability == "care.consult"
		else ["basic_care"]
	)
	var care_started_at := maxi(
		0,
		now - int(execution.get("performedDurationMinutes", 1)),
	)
	care_started_at = clampi(care_started_at, 0, now)
	var result := _resident_conditions.submit_world_action_result(patient_id,
		{
			"resultId": "clinic:%s:%s" % [
				String(request.get("requestId", "")),
				capability,
			],
			"sourceKind": "place_event",
			"sourceRef": String(request.get("requestId", "")),
			"startedAtMinute": care_started_at,
			"occurredAtMinute": now,
			"status": "completed",
			"riskTags": [],
			"reliefTags": relief_tags,
			"context": {
				"placeId": String(request.get("placeId", "")),
				"workerResidentId": worker_resident_id,
				"requestId": String(request.get("requestId", "")),
				"targetConditionIds": condition_ids,
				"careOutcome": outcome.duplicate(true),
			},
		},
		_resident_condition_life_state(
			_residents.get(patient_id, {}) as Dictionary,
		),) as Dictionary
	_record_resident_condition_result(patient_id, result)


func _clinic_condition_request_context(resident_id: String) -> Dictionary:
	var conditions := _resident_conditions.get_conditions(resident_id,) as Array
	var condition_ids: Array[String] = []
	var labels: Array[String] = []
	for condition_value: Variant in conditions:
		if not condition_value is Dictionary:
			continue
		var condition := condition_value as Dictionary
		var condition_id := String(condition.get("conditionId", "")).strip_edges()
		if condition_id.is_empty():
			continue
		condition_ids.append(condition_id)
		labels.append(String(condition.get("label", "身体不适")))
	var resident := _residents.get(resident_id, {}) as Dictionary
	var conflict_snapshot := _agent_conflict_snapshot(
		resident_id,
		resident,
		[],
	)
	var conflict_injury_ids: Array[String] = []
	var conflict_labels: Array[String] = []
	var conflict_injury_requires_treatment := false
	for injury_value: Variant in conflict_snapshot.get(
		"conflict_injuries",
		[],
	) as Array:
		if injury_value is not Dictionary:
			continue
		var injury := injury_value as Dictionary
		var injury_id := String(injury.get("injury_id", "")).strip_edges()
		if injury_id.is_empty():
			continue
		conflict_injury_ids.append(injury_id)
		var severity := String(injury.get("severity", ""))
		var source_name := String(injury.get("source_actor_name", "对方"))
		conflict_labels.append(
			"冲突造成的%s（来源%s）" % [
				"重伤" if severity == "heavy" else "轻伤",
				source_name if not source_name.is_empty() else "对方",
			]
		)
		if severity == "heavy":
			conflict_injury_requires_treatment = true
	if condition_ids.is_empty() and conflict_injury_ids.is_empty():
		return {}
	var requested_condition_ids: Array[String] = condition_ids.duplicate()
	requested_condition_ids.append_array(conflict_injury_ids)
	var subject_labels: Array[String] = labels.duplicate()
	subject_labels.append_array(conflict_labels)
	return {
		"subjectRef": "；".join(subject_labels),
		"context": {
			"conditionIds": requested_condition_ids,
			"generatedFromResidentCondition": not condition_ids.is_empty(),
			"conflictInjuryIds": conflict_injury_ids,
			"generatedFromConflictInjury": not conflict_injury_ids.is_empty(),
			"conflictInjuryRequiresTreatment": conflict_injury_requires_treatment,
		},
	}


func _home_place_for_resident(resident_id: String) -> String:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var home := String(
		(resident.get("socialState", {}) as Dictionary).get("home", ""),
	).strip_edges()
	if not home.is_empty():
		return home
	for place_value: Variant in _owners:
		var place_id := String(place_value)
		if (
			String(_owners.get(place_id, "")) == resident_id
			and place_id.contains("住宅")
		):
			return place_id
	return ""

func _maybe_notify_ready_preorder(
	request: Dictionary,
	absolute_minute: int,
) -> void:
	var context := request.get("context", {}) as Dictionary
	if int(context.get("customerNotifiedAtMinute", -1)) >= 0:
		return
	var item_id := String(request.get("itemId", ""))
	var place_id := String(request.get("placeId", ""))
	if _unreserved_preorder_inventory_quantity(place_id, item_id) <= 0:
		return
	var definition: Dictionary = _occupation_service_definition(
		String(request.get("kind", "")),
	)
	var request_id := String(request.get("requestId", ""))
	var source_ref := "preorder:%s" % request_id
	var sender_id := RESIDENT_MESSAGE_POLICY.sender_for_source(
		self,
		String(definition.get("occupationId", "")),
		source_ref,
		String(request.get("requesterResidentId", "")),
		_private_message_distribution_token(source_ref, "preorder"),
	)
	var requester_id := String(request.get("requesterResidentId", ""))
	if sender_id.is_empty() or requester_id.is_empty():
		return
	var message_result := RESIDENT_MESSAGE_POLICY.send(
		self,
		RESIDENT_MESSAGE_CONTENT.preorder_ready(
			sender_id,
			requester_id,
			place_id,
			request_id,
			int(context.get("preorderExpiresAtMinute", absolute_minute + 1440)),
		),
	) as Dictionary
	if message_result.get("ok") != true:
		return
	var merged := _occupation_services.merge_request_context(
		String(request.get("requestId", "")),
		{
			"customerNotifiedAtMinute": absolute_minute,
			"preorderReservedQuantity": 1,
			"pickupMessageId": String(
				(message_result.get("message", {}) as Dictionary).get(
					"message_id",
					"",
				),
			),
		},
	) as Dictionary
	if merged.get("ok") != true:
		_cancel_pending_private_message(
			String(
				(message_result.get("message", {}) as Dictionary).get(
					"message_id",
					"",
				),
			),
			"预订商品占货失败",
		)
		return


func _notify_repair_ready(
	request: Dictionary,
	worker_resident_id: String,
	absolute_minute: int,
) -> void:
	var context := request.get("context", {}) as Dictionary
	if int(context.get("pickupNotifiedAtMinute", -1)) >= 0:
		return
	var request_id := String(request.get("requestId", ""))
	var requester_id := String(request.get("requesterResidentId", ""))
	var message_result := RESIDENT_MESSAGE_POLICY.send(
		self,
		RESIDENT_MESSAGE_CONTENT.repair_ready(
			worker_resident_id,
			requester_id,
			request_id,
			absolute_minute + 10080,
		),
	) as Dictionary
	if message_result.get("ok") != true:
		return
	_occupation_services.merge_request_context(
		request_id,
		{
			"pickupNotifiedAtMinute": absolute_minute,
			"pickupMessageId": String(
				(message_result.get("message", {}) as Dictionary).get(
					"message_id",
					"",
				),
			),
		},
	)

func _cargo_fallback_carrier_ids(lot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var places := [
		String(lot.get("sourcePlaceId", "")),
		String(lot.get("destinationPlaceId", "")),
	]
	for place_id: String in places:
		var owner_id := _resident_key(String(_owners.get(place_id, "")))
		if not owner_id.is_empty() and not result.has(owner_id):
			result.append(owner_id)
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		var social_state := resident.get("socialState", {}) as Dictionary
		if (
			places.has(String(social_state.get("workplace", "")))
			and not result.has(resident_id)
		):
			result.append(resident_id)
	result.sort()
	return result


func _copy_conversation_follow_up_state(
	from_action: Dictionary,
	to_action: Dictionary,
) -> void:
	ACTION_PROJECTION_MODULE.copy_conversation_follow_up_state(from_action, to_action)


func _install_conversation_follow_up_action(
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	doing: String,
) -> void:
	resident["currentAction"] = action
	if bool(action.get("consumeRouteConnector", false)):
		resident["routeConnector"] = []
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = doing
	_start_matching_social_action(resident_id, action)
	_bump_world_revision(false)
	_emit_resident_state_changed(resident_id)
	var presented_action := _presentation_action(action)
	presented_action["residentId"] = resident_id
	resident_action_started.emit(
		_resident_display_name(resident_id),
		presented_action,
	)
	resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(self, resident),
	)


func _sync_vacant_mobile_service_fallbacks() -> void:
	if _occupation_post_is_vacant("occupation_postal_worker"):
		for message_id_value: Variant in _private_messages:
			_enable_private_message_sender_delivery(String(message_id_value))
	if not _occupation_post_is_vacant("occupation_delivery_worker"):
		return
	for lot_value: Variant in (
		_cargo_inventory.snapshot() as Dictionary
	).get("cargoLots", []) as Array:
		var lot := lot_value as Dictionary
		if (
			String(lot.get("state", "")) not in ["available", "in_transit"]
			or int(lot.get("quantity", 0)) > MAX_SELF_CARRIED_CARGO_QUANTITY
		):
			continue
		var task_id := "delivery-task:%s" % String(lot.get("lotId", ""))
		var task := _work_tasks.task(task_id) as Dictionary
		if task.is_empty() or String(task.get("state", "")) in [
			"completed", "failed", "cancelled",
		]:
			continue
		var fallback_ids := _cargo_fallback_carrier_ids(lot)
		if fallback_ids.is_empty():
			continue
		var granted := _work_tasks.add_eligible_residents(
			task_id,
			fallback_ids,
		) as Dictionary
		if granted.get("ok") == true:
			for resident_id: String in fallback_ids:
				_schedule_decision(resident_id, true)


func _work_task_is_currently_available(task: Dictionary) -> bool:
	var request := _occupation_services.request(
		String(task.get("sourceRef", "")),
	) as Dictionary
	if request.is_empty():
		return true
	if String(request.get("state", "")) in ["completed", "cancelled"]:
		return false
	if not _occupation_service_request_requires_presence(request):
		return true
	var requester := _residents.get(
		String(request.get("requesterResidentId", "")),
		{},
	) as Dictionary
	return (
		not requester.is_empty()
		and String(requester.get("currentPlace", ""))
		== String(request.get("placeId", ""))
	)


func _task_allows_current_activity_interrupt(task: Dictionary) -> bool:
	return int(task.get("priority", 0)) >= PRIORITY_INTERRUPT_THRESHOLD


func _available_work_tasks(tasks: Array) -> Array:
	var result: Array = []
	for value: Variant in tasks:
		var task := value as Dictionary
		if _work_task_is_currently_available(task):
			result.append(task)
	return result


func _public_work_task_targets(targets: Array) -> Array[Dictionary]:
	return ACTION_SUPPORT.public_work_task_targets(self, targets)


func _occupation_service_request_exists(
	kind: String,
	subject_ref: String,
) -> bool:
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == kind
			and String(request.get("subjectRef", "")) == subject_ref
		):
			return true
	return false


func _occupation_service_preorder_needed(
	kind: String,
	item_id: String,
	place_id: String,
) -> bool:
	if (
		(kind == "cafe_order" and item_id == "pastry")
		or (kind == "grocer_sale" and item_id in [CONTENT_CATALOG.ITEM_FISH, CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET])
		or (kind == "flower_sale" and item_id in [CONTENT_CATALOG.ITEM_FRESH_FLOWERS, CONTENT_CATALOG.ITEM_BOUQUET])
	):
		return _unreserved_preorder_inventory_quantity(
			place_id,
			item_id,
		) <= 0
	return false


func _unreserved_preorder_inventory_quantity(
	place_id: String,
	item_id: String,
) -> int:
	var inventory_quantity := int(_cargo_inventory.inventory_quantity(
		place_id,
		item_id,
	))
	var reserved_quantity := 0
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		var context := request.get("context", {}) as Dictionary
		if (
			String(request.get("state", "")) in ["pending", "waiting"]
			and String(request.get("placeId", "")) == place_id
			and String(request.get("itemId", "")) == item_id
			and String(context.get("customerServiceMode", "")) == "preorder"
		):
			reserved_quantity += maxi(
				int(context.get("preorderReservedQuantity", 0)),
				0,
			)
	return maxi(inventory_quantity - reserved_quantity, 0)


func _occupation_post_is_vacant(occupation_id: String) -> bool:
	if _staffing == null:
		return true
	var post := _staffing.post_for_occupation(
		occupation_id,
	) as Dictionary
	return post.is_empty() or String(post.get("status", "vacant")) == "vacant"


func _semantic_region_task_targets(
	activity_id: String,
	fallback_region_id: String,
	choice_key := "",
) -> Array[Dictionary]:
	# A3:目标扫描计时与调用/候选计数;全部调用点都在生产任务同步链内。
	var lap_usec := Time.get_ticks_usec() if _advance_profile_enabled else 0
	var scan := _semantic_region_task_targets_scan(
		activity_id,
		fallback_region_id,
		choice_key,
	)
	_advance_profile_lap(_advance_profile_scratch, "productionTasksTargetsUsec", lap_usec)
	_advance_profile_count("productionTasksTargetsCalls", 1)
	return scan


func _semantic_region_task_targets_scan(
	activity_id: String,
	fallback_region_id: String,
	choice_key: String,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in _activity_runtime.semantic_region_targets(
		activity_id,
	) as Array:
		var target := value as Dictionary
		var region_id := String(target.get("ref", ""))
		if region_id.is_empty():
			continue
		result.append({"kind": "region", "ref": region_id})
	if result.is_empty() and not fallback_region_id.is_empty():
		result.append({
			"kind": "region",
			"ref": fallback_region_id,
		})
	_advance_profile_count("productionTasksTargetCandidates", result.size())
	if result.size() <= 1:
		return result
	var selection_seed := "%s:%s:%d" % [
		activity_id,
		choice_key,
		int(_environment.get_absolute_minute()),
	]
	return [result[posmod(hash(selection_seed), result.size())]]


func _sync_daily_operation_tasks(absolute_minute: int) -> void:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 8 * 60 or minute_of_day >= 17 * 60:
		return
	var day_index := absolute_minute / 1440
	var operations: Array[Dictionary] = [
		{
			"key": "postal-collection",
			"capability": "message.accept",
			"targetKind": "route",
			"target": "小镇道路",
			"activityId": "activity_postal_collect_outgoing_mail",
			"sourceKind": "daily_postal_collection_plan",
			"resultKind": "postal_collection_record",
			"priority": CONTENT_CATALOG.TASK_PRIORITY["daily_postal_collection"],
		},
		{
			"key": "cafe-opening",
			"capability": "cafe.handoff",
			"target": "花房咖啡馆西北座椅",
			"activityId": "activity_cafe_tidy_tables",
		},
		{
			"key": "clinic-opening",
			"capability": "care.treatment",
			"target": "诊所药柜",
			"activityId": "activity_clinic_prepare_medicine",
		},
		{
			"key": "grocer-opening",
			"capability": "retail.stock",
			"target": "独立市集西侧杂货摊",
			"activityId": "activity_grocer_count_goods",
		},
		{
			"key": "flower-opening",
			"capability": "retail.sale",
			"target": "独立市集南侧花摊",
			"activityId": "activity_flower_watch_stall",
		},
	]
	for operation: Dictionary in operations:
		var source_ref := "%s-day:%d" % [
			String(operation.get("key", "operation")),
			day_index,
		]
		if _retire_stale_period_work_tasks(
			String(operation.get("capability", "")),
			String(operation.get("sourceKind", "daily_operation_plan")),
			source_ref,
			"新的每日营业整理周期已经开始",
		):
			continue
		_ensure_production_task({
			"taskId": "daily-operation:%s" % source_ref,
			"capability": String(operation.get("capability", "")),
			"sourceKind": String(
				operation.get("sourceKind", "daily_operation_plan"),
			),
			"sourceRef": source_ref,
			"targets": [{
				"kind": String(operation.get("targetKind", "prop")),
				"ref": String(operation.get("target", "")),
			}],
			"requestedResultKind": String(
				operation.get("resultKind", "daily_operation_record"),
			),
			"createdAtMinute": absolute_minute,
			"priority": int(operation.get("priority", 44)),
			"processStage": "planned",
			"processFacts": {
				"dayIndex": day_index,
				"nextActivityId": String(
					operation.get("activityId", ""),
				),
			},
		})


func _sync_library_catalog_tasks(absolute_minute: int) -> void:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 540 or minute_of_day >= 960:
		return
	var day_index := absolute_minute / 1440
	var source_ref := "library-catalog-check:%d" % day_index
	var carried_catalog_work := _retire_stale_period_work_tasks(
		"library.assist",
		"daily_catalog_plan",
		source_ref,
		"新的目录核对周期已经开始",
	)
	carried_catalog_work = (
		_retire_stale_period_work_tasks(
			"library.assist",
			"catalog_mismatch",
			source_ref,
			"新的目录核对周期已经开始",
		)
		or carried_catalog_work
	)
	if carried_catalog_work:
		return
	_ensure_production_task({
		"taskId": source_ref,
		"capability": "library.assist",
		"sourceKind": "daily_catalog_plan",
		"sourceRef": source_ref,
		"targets": [{"kind": "prop", "ref": "图书馆借还书柜台内侧"}],
		"requestedResultKind": "catalog_state_change",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["library_catalog_check"],
		"processStage": "catalog_check_due",
		"processFacts": {
			"nextActivityId": "activity_library_staff_checkout",
		},
	})


func _retire_stale_performance_requests(absolute_minute: int) -> void:
	var current_day := absolute_minute / 1440
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) != "performance"
			or String(request.get("state", "")) not in ["pending", "waiting"]
		):
			continue
		var context := request.get("context", {}) as Dictionary
		var request_day := int(
			context.get(
				"dayIndex",
				int(request.get("createdAtMinute", 0)) / 1440,
			),
		)
		if request_day >= current_day:
			continue
		var request_id := String(request.get("requestId", ""))
		_occupation_services.cancel_request(
			request_id,
			"演出日期已经过去",
		)
		var task_id := String(request.get("taskId", ""))
		if not task_id.is_empty():
			_work_tasks.cancel_task(
				task_id,
				"演出日期已经过去",
			)
		_cancel_private_messages_for_source(
			"performance-event:%d" % request_day,
			"演出日期已经过去",
		)
		_close_performance_invitation_sources(
			request_day,
			"演出日期已经过去",
		)


func _sync_civic_work_tasks(absolute_minute: int) -> void:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 7 * 60 or minute_of_day >= 17 * 60:
		return
	var day_index := absolute_minute / 1440
	var vacancy_count := 0
	for post_value: Variant in (
		get_staffing_snapshot().get("posts", []) as Array
	):
		if (
			post_value is Dictionary
			and String((post_value as Dictionary).get("status", ""))
			== "vacant"
		):
			vacancy_count += 1
	var open_service_count := 0
	for state_value: Variant in _place_service_states.values():
		if bool((state_value as Dictionary).get("open", false)):
			open_service_count += 1
	var daily_source_ref := "daily-town-state:%d" % day_index
	_retire_stale_period_work_tasks(
		"civic.service",
		"public_matter",
		daily_source_ref,
		"新的镇务核对周期已经开始",
	)
	_ensure_production_task({
		"taskId": "civic-daily-review:%d" % day_index,
		"capability": "civic.service",
		"sourceKind": "public_matter",
		"sourceRef": daily_source_ref,
		"targets": [{"kind": "prop", "ref": "镇公所档案柜"}],
		"requestedResultKind": "civic_case_update",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["civic_case"],
		"processStage": "reviewing",
		"processFacts": {
			"dayIndex": day_index,
			"weather": get_weather(),
			"openServiceCount": open_service_count,
			"vacancyCount": vacancy_count,
			"nextActivityId": "activity_town_hall_manage_records",
		},
	})
	if vacancy_count > 0:
		_ensure_production_task({
			"taskId": "civic-staffing-review:%d" % day_index,
			"capability": "staffing.coordinate",
			"sourceKind": "staffing_matter",
			"sourceRef": "staffing-vacancies",
			"targets": [{"kind": "prop", "ref": "镇公所档案柜"}],
			"requestedResultKind": "staffing_matter_update",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["staffing_review"],
			"processStage": "reviewing_staffing",
			"processFacts": {
				"vacancyCount": vacancy_count,
				"nextActivityId": "activity_town_hall_manage_records",
			},
		})
	else:
		_cancel_active_work_task_for_source(
			"staffing_matter",
			"staffing-vacancies",
			"岗位空缺已经消失",
		)
	for place_value: Variant in _place_service_states.values():
		var place_state := place_value as Dictionary
		var waiting_count := (
			place_state.get("pending_request_ids", []) as Array
		).size()
		var place_id := String(place_state.get("place_id", ""))
		if bool(place_state.get("open", true)) and waiting_count <= int(
			place_state.get("service_capacity", 0),
		):
			_cancel_active_work_task_for_source(
				"place_service_change",
				"place-service:%s" % place_id,
				"地点服务已经恢复正常",
			)
			continue
		_ensure_production_task({
			"taskId": "civic-service-change:%s:%d"
				% [place_id, day_index],
			"capability": "civic.service",
			"sourceKind": "place_service_change",
			"sourceRef": "place-service:%s" % place_id,
			"targets": [{"kind": "prop", "ref": "镇公所档案柜"}],
			"requestedResultKind": "civic_case_update",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["civic_urgent_case"],
			"processStage": "reviewing_service_change",
			"processFacts": {
				"placeId": place_id,
				"open": bool(place_state.get("open", true)),
				"waitingRequestCount": waiting_count,
				"weather": get_weather(),
				"nextActivityId": "activity_town_hall_manage_records",
			},
		})


func _meal_period_for_minute(absolute_minute: int) -> Dictionary:
	return ACTIVITY_SCALARS.meal_period_for_minute(absolute_minute)


func _meal_service_is_open(absolute_minute: int) -> bool:
	var period := _meal_period_for_minute(absolute_minute)
	if period.is_empty():
		return false
	return posmod(absolute_minute, 1440) >= int(
		period.get("serviceStart", period.get("start", 0)),
	)
func _dining_collect_can_finish_in_current_period(
	absolute_minute: int,
) -> bool:
	var period := _meal_period_for_minute(absolute_minute)
	if period.is_empty() or not _meal_service_is_open(absolute_minute):
		return false
	var minute_of_day := posmod(absolute_minute, 1440)
	return minute_of_day + 5 <= int(period.get("end", 0))


func _meal_period_source_ref(absolute_minute: int) -> String:
	var period := _meal_period_for_minute(absolute_minute)
	if period.is_empty():
		return ""
	return "meal-period:%d:%s" % [
		absolute_minute / 1440,
		String(period.get("id", "")),
	]


func _dining_order_for_resident_meal_period(
	resident_id: String,
	absolute_minute: int,
	states: Array,
) -> Dictionary:
	var period_ref := _meal_period_source_ref(absolute_minute)
	if period_ref.is_empty():
		return {}
	var selected: Dictionary = {}
	var selected_state_rank := states.size()
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		if not request_value is Dictionary:
			continue
		var request := request_value as Dictionary
		var request_state := String(request.get("state", ""))
		if (
			String(request.get("kind", "")) == "dining_order"
			and String(request.get("requesterResidentId", ""))
			== resident_id
			and states.has(request_state)
			and _meal_period_source_ref(
				int(request.get("createdAtMinute", -1)),
			) == period_ref
		):
			var state_rank := states.find(request_state)
			if selected.is_empty() or state_rank < selected_state_rank:
				selected = request.duplicate(true)
				selected_state_rank = state_rank
	return selected


func _dining_request_meal_is_ready(request: Dictionary) -> bool:
	var created_at := int(request.get("createdAtMinute", -1))
	return (
		created_at >= 0
		and not _meal_period_for_minute(created_at).is_empty()
		and _meal_period_is_prepared(created_at)
	)


func _meal_period_is_prepared(absolute_minute: int) -> bool:
	var source_ref := _meal_period_source_ref(absolute_minute)
	if source_ref.is_empty():
		return false
	var task := _work_tasks.task(
		"meal-preparation:%s" % source_ref,
	) as Dictionary
	return String(task.get("state", "")) == "completed"


func _sync_meal_period_tasks(absolute_minute: int) -> void:
	var period := _meal_period_for_minute(absolute_minute)
	var source_ref := _meal_period_source_ref(absolute_minute)
	for task_value: Variant in (
		_work_tasks.create_save_snapshot() as Dictionary
	).get("tasks", []) as Array:
		var existing_task := task_value as Dictionary
		if (
			String(existing_task.get("capability", ""))
			!= "food.production"
			or String(existing_task.get("sourceKind", ""))
			!= "meal_demand"
			or not String(existing_task.get("sourceRef", "")).begins_with(
				"meal-period:",
			)
			or String(existing_task.get("sourceRef", "")) == source_ref
			or _meal_period_has_waiting_orders(
				String(existing_task.get("sourceRef", "")),
			)
			or String(existing_task.get("state", ""))
			not in ["open", "waiting"]
		):
			continue
		_work_tasks.cancel_task(
			String(existing_task.get("taskId", "")),
			"当前餐次已经结束",
		)
	if period.is_empty():
		return
	_ensure_production_task({
		"taskId": "meal-preparation:%s" % source_ref,
		"capability": "food.production",
		"sourceKind": "meal_demand",
		"sourceRef": source_ref,
		"targets": [
			{"kind": "prop", "ref": "公共食堂备餐柜"},
			{"kind": "prop", "ref": "公共食堂灶台"},
		],
		"requestedResultKind": "food_batch",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["meal_demand_order"],
		"processStage": "meal_period_planned",
		"processFacts": {
			"periodId": String(period.get("id", "")),
			"periodLabel": String(period.get("label", "")),
			"menu": DINING_SERVICE.meal_menu_for_period(period),
			"serviceStartMinute": int(period.get("serviceStart", 0)),
			"baseSupply": true,
			"nextActivityId": "activity_dining_prepare_meal",
		},
	})
	DINING_SERVICE.reserve_meal_preparation_task(self, source_ref)
	_activate_waiting_dining_orders()


func _meal_period_has_waiting_orders(source_ref: String) -> bool:
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "dining_order"
			and String(request.get("state", "")) == "waiting"
			and String(request.get("waitReason", "")) in [
				"当前餐次尚未完成备餐",
				"当前餐次尚未开始供餐",
			]
			and _meal_period_source_ref(
				int(request.get("createdAtMinute", -1)),
			) == source_ref
		):
			return true
	return false


func _sync_warehouse_audit_tasks(absolute_minute: int) -> void:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 8 * 60 or minute_of_day >= 17 * 60:
		return
	var day_index := absolute_minute / 1440
	var audit_source_ref := "warehouse-audit:%d" % day_index
	var carried_inventory_work := _retire_stale_period_work_tasks(
		"inventory.receive",
		"daily_inventory_plan",
		audit_source_ref,
		"新的仓库盘点周期已经开始",
	)
	carried_inventory_work = (
		_retire_stale_period_work_tasks(
			"inventory.receive",
			"inventory_request",
			audit_source_ref,
			"新的仓库盘点周期已经开始",
		)
		or carried_inventory_work
	)
	if carried_inventory_work:
		return
	_ensure_production_task({
		"taskId": "warehouse-daily-audit:%d" % day_index,
		"capability": "inventory.receive",
		"sourceKind": "daily_inventory_plan",
		"sourceRef": audit_source_ref,
		"targets": [{"kind": "prop", "ref": "码头仓库货单桌"}],
		"requestedResultKind": "inventory_record",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["warehouse_audit"],
	})
	for lot_value: Variant in (
		(_cargo_inventory.snapshot() as Dictionary).get(
			"cargoLots",
			[],
		) as Array
	):
		var lot := lot_value as Dictionary
		if (
			String(lot.get("state", "")) != "awaiting_receipt"
			or absolute_minute - int(lot.get("deliveredAtMinute", 0)) < 120
		):
			continue
		var lot_id := String(lot.get("lotId", ""))
		_ensure_production_task({
			"taskId": "warehouse-discrepancy:%s" % lot_id,
			"capability": "inventory.receive",
			"sourceKind": "inventory_discrepancy",
			"sourceRef": lot_id,
			"targets": [{"kind": "prop", "ref": "码头仓库货单桌"}],
			"requestedResultKind": "inventory_record",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["inventory_discrepancy"],
		})


func _sync_library_return_requests(absolute_minute: int) -> void:
	var message_created_at := int(_environment.get_absolute_minute())
	for loan_value: Variant in _occupation_services.borrowed_loans_due_by(
		absolute_minute,
	) as Array:
		var loan := loan_value as Dictionary
		var loan_id := String(loan.get("loanId", ""))
		if bool(_occupation_services.has_active_request(
			"library_return",
			loan_id,
		)):
			continue
		var borrower_id := String(loan.get("borrowerResidentId", ""))
		var created := create_occupation_service_request({
			"kind": "library_return",
			"requesterResidentId": borrower_id,
			"subjectRef": loan_id,
			"context": {"generatedFromDueLoan": true},
		})
		if created.get("ok") != true:
			continue
		var source_ref := "library-return:%s" % loan_id
		var librarian_id := RESIDENT_MESSAGE_POLICY.sender_for_source(
			self,
			"occupation_librarian",
			source_ref,
			borrower_id,
			_private_message_distribution_token(source_ref, "library-return"),
		)
		if not librarian_id.is_empty():
			RESIDENT_MESSAGE_POLICY.send(
				self,
				RESIDENT_MESSAGE_CONTENT.library_due(
					librarian_id,
					borrower_id,
					loan_id,
					message_created_at + 1440,
				),
			)


func _sync_research_sample_tasks(absolute_minute: int) -> void:
	for project_value: Variant in _production.plant_research_projects(
	) as Array:
		var project := project_value as Dictionary
		var project_id := String(project.get("projectId", ""))
		if String(project.get("stage", "")) in ["recorded", "accessioned"]:
			var stale_task := _work_tasks.active_task_for_source(
				"sample_request",
				project_id,
			) as Dictionary
			if not stale_task.is_empty() and String(
				stale_task.get("state", ""),
			) in ["open", "waiting"]:
				_work_tasks.cancel_task(
					String(stale_task.get("taskId", "")),
					"研究已经完成记录，不再需要补采样本",
				)
			continue
		_ensure_production_task({
			"taskId": "garden-sample:%s" % project_id,
			"capability": "garden.harvest",
			"sourceKind": "sample_request",
			"sourceRef": project_id,
			"targets": _semantic_region_task_targets(
				"activity_garden_harvest_region",
				"outdoor_garden_01",
				"research-sample:%s" % project_id,
			),
			"requestedResultKind": "plant_sample_lot",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["research_sample_request"],
		})


func _has_active_specialty_production(
	item_id: String,
	destination_place_id: String,
) -> bool:
	for task_value: Variant in (
		_work_tasks.create_save_snapshot() as Dictionary
	).get("tasks", []) as Array:
		var task := task_value as Dictionary
		var facts := task.get("processFacts", {}) as Dictionary
		if (
			String(task.get("state", "")) not in [
				"completed",
				"failed",
				"cancelled",
			]
			and String(facts.get("productItemId", "")) == item_id
			and String(facts.get("destinationPlaceId", ""))
			== destination_place_id
		):
			return true
	return false


func _has_active_work_task_capability(capability: String) -> bool:
	for task_value: Variant in (
		_work_tasks.create_save_snapshot() as Dictionary
	).get("tasks", []) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) == capability
			and String(task.get("state", "")) not in [
				"completed",
				"failed",
				"cancelled",
			]
		):
			return true
	return false


func _retire_stale_period_work_tasks(
	capability: String,
	source_kind: String,
	current_source_ref: String,
	reason: String,
) -> bool:
	var carried_work_exists := false
	for task_value: Variant in (
		_work_tasks.create_save_snapshot() as Dictionary
	).get("tasks", []) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) != capability
			or String(task.get("sourceKind", "")) != source_kind
			or String(task.get("sourceRef", "")) == current_source_ref
			or String(task.get("state", "")) in [
				"completed",
				"failed",
				"cancelled",
			]
		):
			continue
		var state := String(task.get("state", ""))
		var process_stage := String(task.get("processStage", "ready"))
		if (
			state in ["accepted", "in_progress"]
			or not String(task.get("assignedResidentId", "")).is_empty()
			or process_stage not in ["ready", "planned", "reviewing"]
		):
			carried_work_exists = true
			continue
		_work_tasks.cancel_task(
			String(task.get("taskId", "")),
			reason,
		)
	return carried_work_exists


func _cancel_active_work_task_for_source(
	source_kind: String,
	source_ref: String,
	reason: String,
) -> void:
	var task := _work_tasks.active_task_for_source(
		source_kind,
		source_ref,
	) as Dictionary
	if task.is_empty():
		return
	_work_tasks.cancel_task(
		String(task.get("taskId", "")),
		reason,
	)


func _resident_can_work_occupation(
	resident_id: String,
	occupation_id: String,
) -> bool:
	return _work_occupation_ids_for_resident(resident_id).has(occupation_id)


func _resident_can_accept_work_task(
	resident_id: String,
	task: Dictionary,
) -> bool:
	if task.is_empty():
		return false
	if not _resident_available_for_work(
		_residents.get(resident_id, {}) as Dictionary,
	):
		return false
	if (task.get("eligibleResidentIds", []) as Array).has(resident_id):
		return true
	for occupation_id: String in _work_occupation_ids_for_resident(resident_id):
		if (task.get("eligibleOccupationIds", []) as Array).has(occupation_id):
			return true
	return false


func _task_acceptance_occupation_id(
	resident_id: String,
	task: Dictionary,
) -> String:
	for occupation_id: String in _work_occupation_ids_for_resident(resident_id):
		if (task.get("eligibleOccupationIds", []) as Array).has(occupation_id):
			return occupation_id
	return _occupation_id_for_resident(
		_residents.get(resident_id, {}) as Dictionary,
	)


func _natural_bulletin_task_for_resident(resident_id: String) -> Dictionary:
	if _occupation_id_for_resident(
		_residents.get(resident_id, {}) as Dictionary,
	) != "occupation_town_manager":
		return {}
	for task_value: Variant in _work_tasks.tasks_for_occupation(
		"occupation_town_manager",
		resident_id,
	) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) == "bulletin.publish"
			and String(task.get("state", "")) in [
				"open", "waiting", "accepted", "in_progress",
			]
		):
			return task.duplicate(true)
	return {}


func _sync_specialty_service_demand(
	kind: String,
	item_id: String,
	request_id: String,
	now: int,
) -> void:
	if kind == "cafe_order" and item_id == "pastry":
		if (
			_has_active_cargo_to_place("pastry", CONTENT_CATALOG.PLACE_CAFE)
			or _has_active_specialty_production(
				"pastry",
				CONTENT_CATALOG.PLACE_CAFE,
			)
		):
			return
		_ensure_production_task({
			"taskId": "pastry-order-production:%s" % request_id,
			"capability": "food.production",
			"sourceKind": "meal_demand",
			"sourceRef": "pastry-order:%s" % request_id,
			"targets": [
				{"kind": "prop", "ref": "公共食堂备餐柜"},
				{"kind": "prop", "ref": "公共食堂灶台"},
			],
			"requestedResultKind": "food_batch",
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["specialty_meal_demand"],
			"processStage": "planned",
			"processFacts": {
				"productItemId": "pastry",
				"destinationPlaceId": CONTENT_CATALOG.PLACE_CAFE,
				"serviceRequestId": request_id,
				"nextActivityId": "activity_baker_prepare_dough",
			},
		})
	elif kind == "grocer_sale" and item_id == CONTENT_CATALOG.ITEM_FISH:
		if (
			_has_active_cargo_to_place(CONTENT_CATALOG.ITEM_FISH, CONTENT_CATALOG.PLACE_MARKET)
			or _has_active_work_task_capability("fishing.harvest")
		):
			return
		_ensure_production_task({
			"taskId": "fishing-demand:%s" % request_id,
			"capability": "fishing.harvest",
			"sourceKind": "fish_demand",
			"sourceRef": "fish-demand:%s" % request_id,
			"targets": _semantic_region_task_targets(
				"activity_fisher_catch_in_region",
				"outdoor_harbor_01",
				"fish-demand:%s" % request_id,
			),
			"requestedResultKind": "fishing_outcome",
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["specialty_fishing_demand"],
		})
	elif item_id == CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET and kind in ["clinic", "grocer_sale"]:
		var request := _occupation_services.request(
			request_id,
		) as Dictionary
		var record_id := String(
			(request.get("context", {}) as Dictionary).get(
				"researchRecordId",
				"",
			),
		).strip_edges()
		var destination_place_id := (
			CONTENT_CATALOG.PLACE_CLINIC if kind == "clinic" else CONTENT_CATALOG.PLACE_MARKET
		)
		if (
			record_id.is_empty()
			or not (_occupation_services.accession_for_record(
				record_id,
			) as Dictionary).has("accessionId")
			or int(_cargo_inventory.inventory_quantity(
				destination_place_id,
				CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			)) > 0
			or _has_active_cargo_to_place(
				CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
				destination_place_id,
			)
			or _has_active_specialty_production(
				CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
				destination_place_id,
			)
		):
			return
		_ensure_production_task({
			"taskId": "research-booklet:%s" % request_id,
			"capability": "research.handoff",
			"sourceKind": "personal_research_plan",
			"sourceRef": "booklet-demand:%s" % request_id,
			"targets": [{"kind": "prop", "ref": "图书馆写作桌"}],
			"requestedResultKind": "handwritten_booklet",
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["research_booklet_handoff"],
			"processStage": "booklet_planned",
			"processFacts": {
				"recordId": record_id,
				"productItemId": CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
				"serviceRequestId": request_id,
				"destinationPlaceId": destination_place_id,
				"nextActivityId": "activity_botanist_record_plants",
			},
		})


func _resident_available_for_work(resident: Dictionary) -> bool:
	return (
		_resident_is_present(resident)
		and not _resident_is_on_leave(resident)
	)


func _resident_is_on_leave(
	resident: Dictionary,
	absolute_minute := -1,
) -> bool:
	return ACTION_SUPPORT.resident_is_on_leave(self, resident, absolute_minute)


func _expire_specialty_inventory_before(
	place_id: String,
	item_id: String,
	cutoff_minute: int,
) -> void:
	var quantity := int(_cargo_inventory.inventory_quantity(
		place_id,
		item_id,
	))
	if quantity <= 0 or cutoff_minute <= 0:
		return
	var latest_receipt_minute := -1
	for lot_value: Variant in (
		_cargo_inventory.snapshot() as Dictionary
	).get("cargoLots", []) as Array:
		var lot := lot_value as Dictionary
		if (
			String(lot.get("state", "")) == "delivered"
			and String(lot.get("itemId", "")) == item_id
			and String(lot.get("destinationPlaceId", "")) == place_id
		):
			latest_receipt_minute = maxi(
				latest_receipt_minute,
				int(lot.get("receivedAtMinute", -1)),
			)
	if latest_receipt_minute >= cutoff_minute:
		return
	var expired_inputs := {}
	expired_inputs[item_id] = quantity
	_cargo_inventory.apply_inventory_recipe(
		place_id,
		expired_inputs,
		{},
	)


func _sync_clinic_follow_up_requests(absolute_minute: int) -> void:
	var message_created_at := int(_environment.get_absolute_minute())
	for follow_up_value: Variant in _occupation_services.due_follow_ups(
		absolute_minute,
	) as Array:
		var follow_up := follow_up_value as Dictionary
		var follow_up_id := String(follow_up.get("followUpId", ""))
		var patient_id := String(follow_up.get("patientResidentId", ""))
		var created := create_occupation_service_request({
			"kind": "clinic",
			"requesterResidentId": patient_id,
			"subjectRef": "%s（复诊）" % String(
				follow_up.get("complaint", "身体不适"),
			),
			"context": {
				"generatedFromFollowUp": true,
				"followUpId": follow_up_id,
				"originalRequestId": String(
					follow_up.get("originalRequestId", ""),
				),
			},
		})
		if created.get("ok") != true:
			continue
		var request := created.get("request", {}) as Dictionary
		var attached := _occupation_services.attach_follow_up_request(
			follow_up_id,
			String(request.get("requestId", "")),
		) as Dictionary
		if attached.get("ok") != true:
			continue
		var source_ref := "clinic-follow-up:%s" % follow_up_id
		var practitioner_id := RESIDENT_MESSAGE_POLICY.sender_for_source(
			self,
			"occupation_clinic_practitioner",
			source_ref,
			patient_id,
			_private_message_distribution_token(
				source_ref,
				"clinic-follow-up",
			),
		)
		if not practitioner_id.is_empty():
			RESIDENT_MESSAGE_POLICY.send(
				self,
				RESIDENT_MESSAGE_CONTENT.clinic_follow_up(
					practitioner_id,
					patient_id,
					String(follow_up.get("complaint", "身体不适")),
					follow_up_id,
					message_created_at + 360,
				),
			)
			sync_resident_request({
				"request_id": "clinic-return:%s" % follow_up_id,
				"source_revision": 1,
				"requester_id": practitioner_id,
				"submitted": true,
				"active": true,
				"reason_summary": "诊所请%s按时回来复诊" % (
					_resident_display_name(patient_id)
				),
				"subject_ids": [practitioner_id, patient_id],
				"place_id": CONTENT_CATALOG.PLACE_CLINIC,
				"capability_id": "world.go_to_place",
				"target_refs": {"place_id": CONTENT_CATALOG.PLACE_CLINIC},
				"success_result_id": "clinic-follow-up-arrived",
				"expires_at": message_created_at + 360,
				"capacity": 1,
				"source_event_ids": [follow_up_id],
			})


func _activity_candidate_physical_targets(
	candidates: Array,
) -> Array[Dictionary]:
	return ACTIVITY_SCALARS.activity_candidate_physical_targets(candidates)


func _matching_work_tasks_for_targets(
	tasks: Array,
	physical_targets: Array[Dictionary],
) -> Array:
	return ACTIVITY_SCALARS.matching_work_tasks_for_targets(tasks, physical_targets)


func _claim_specific_work_task(
	task: Dictionary,
	occupation_id: String,
	resident_id: String,
) -> Dictionary:
	if not _work_task_is_currently_available(task):
		return {"ok": false, "errorCode": "WORK_TASK_NOT_AVAILABLE"}
	var task_id := String(task.get("taskId", ""))
	var state := String(task.get("state", ""))
	var revision := int(task.get("revision", 0))
	var selected := task
	if state in ["open", "waiting"]:
		var accepted := _work_tasks.accept_task(
			task_id,
			resident_id,
			occupation_id,
			revision,
		) as Dictionary
		if accepted.get("ok") != true:
			return accepted
		selected = accepted.get("task", {}) as Dictionary
		state = "accepted"
		revision = int(selected.get("revision", 0))
	if state == "accepted":
		return _work_tasks.start_task(
			task_id,
			resident_id,
			revision,
		) as Dictionary
	if state == "in_progress":
		return {"ok": true, "task": selected.duplicate(true)}
	return {"ok": false, "errorCode": "WORK_TASK_STATE_INVALID"}


func _occupation_service_request_requires_presence(
	request: Dictionary,
) -> bool:
	return ACTION_SUPPORT.occupation_service_request_requires_presence(request)


func _activate_waiting_dining_orders() -> void:
	var now := int(_environment.get_absolute_minute())
	if not _meal_service_is_open(now) or not _meal_period_is_prepared(now):
		return
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) != "dining_order"
			or String(request.get("state", "")) != "waiting"
			or String(request.get("waitReason", "")) not in [
				"当前餐次尚未完成备餐",
				"当前餐次尚未开始供餐",
				"食堂当前不在供餐时间",
			]
		):
			continue
		var request_id := String(request.get("requestId", ""))
		var service_result := record_place_service_request(
			CONTENT_CATALOG.PLACE_DINING_HALL,
			request_id,
			true,
		)
		if service_result.get("ok") != true:
			continue
		var task := _work_tasks.active_task_for_source(
			"meal_demand",
			request_id,
		) as Dictionary
		if task.is_empty():
			continue
		task = _reserve_work_task(
			task,
			"occupation_dining_operator",
		)
		_occupation_services.attach_follow_up_task(
			request_id,
			String(task.get("taskId", "")),
		)
		var refreshed_context := (
			request.get("context", {}) as Dictionary
		).duplicate(true)
		var wait_until := DINING_SERVICE.wait_deadline(self, now)
		refreshed_context["onsiteWaitUntilMinute"] = wait_until
		refreshed_context["customerAbsentSinceMinute"] = -1
		_occupation_services.merge_request_context(
			request_id,
			{
				"onsiteWaitUntilMinute": wait_until,
				"customerAbsentSinceMinute": -1,
			},
		)
		_begin_customer_service_wait(
			String(request.get("requesterResidentId", "")),
			request_id,
			CONTENT_CATALOG.PLACE_DINING_HALL,
			refreshed_context,
		)
		_schedule_occupation_service_worker(
			_occupation_services.request(request_id) as Dictionary,
		)


func _outdoor_path_from_route(route: Dictionary) -> Array[Vector2]:
	return ACTION_SUPPORT.outdoor_path_from_route(route)

func _begin_performance_listener_wait(
	resident_id: String,
	day_index: int,
) -> void:
	if day_index < 0:
		return
	var resident := _residents.get(resident_id, {}) as Dictionary
	if (
		resident.is_empty()
		or String(resident.get("currentPlace", "")) != CONTENT_CATALOG.PLACE_PLAZA
		or not (resident.get("currentAction", {}) as Dictionary).is_empty()
	):
		return
	if bool(resident.get("decisionPending", false)):
		_restore_inflight_facts(resident)
		resident["decisionPending"] = false
		resident["validDecisionId"] = ""
		resident["pendingWake"] = {}
		resident["wakeDispatchQueued"] = false
	var now := int(_environment.get_absolute_minute())
	var action_id := "performance-listen:%d:%s" % [day_index, resident_id]
	resident["currentAction"] = {
		"type": "待着",
		"action_id": action_id,
		"line": "在中心广场等待并聆听演奏",
		"startedAbsoluteMinute": now,
		"completeAbsoluteMinute": now + 120,
		"performanceDayIndex": day_index,
		"performanceEventId": "performance-event:%d" % day_index,
	}
	(resident.get("usedActionIds", {}) as Dictionary)[action_id] = true
	resident["doing"] = "正在中心广场等待并聆听演奏"
	_bump_world_revision(false)
	_emit_resident_state_changed(resident_id)

func _finish_performance_listener_waits(
	day_index: int,
	audience_ids: Array[String],
) -> void:
	for resident_id: String in audience_ids:
		var resident := _residents.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			String(action.get("type", "")) == "待着"
			and int(action.get("performanceDayIndex", -1)) == day_index
		):
			_finish_action(resident_id, "已经听完这场演奏")

func _close_performance_invitation_sources(
	day_index: int,
	reason: String,
) -> void:
	if day_index < 0:
		return
	var source_prefix := "performance-invitation:%d:" % day_index
	for resident_id: String in _resident_order:
		var resident := _residents.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		for assignment: Dictionary in _active_social_assignments(
			resident_id,
			["executing"],
		):
			var matter := _social_matters.get_matter(
				String(assignment.get("matter_id", "")),
			) as Dictionary
			var source_ref := matter.get(
				"source_state_ref",
				{},
			) as Dictionary
			if (
				String(source_ref.get("source_kind", ""))
				== "resident_request"
				and String(source_ref.get("source_id", "")).begins_with(
					source_prefix,
				)
				and _social_goal_matches_action(
					assignment.get("action_goal", {}) as Dictionary,
					action,
					resident_id,
				)
			):
				_interrupt_action(resident_id, reason)
				break
	var source_ids: Array[String] = []
	for value: Variant in _social_matters.list_matters(
		false,
	) as Array:
		var matter := value as Dictionary
		var source_ref := matter.get("source_state_ref", {}) as Dictionary
		var source_id := String(source_ref.get("source_id", ""))
		if (
			String(source_ref.get("source_kind", ""))
			== "resident_request"
			and source_id.begins_with(source_prefix)
			and not source_ids.has(source_id)
		):
			source_ids.append(source_id)
	for source_id: String in source_ids:
		_close_resident_request_source(
			source_id,
			"performance-invitation-ended",
		)

func _activate_delivered_preorder_pickup(
	message_id: String,
	request_id: String,
	sender_id: String,
	recipient_id: String,
	delivered_at: int,
) -> void:
	var request := _occupation_services.request(request_id) as Dictionary
	var context := request.get("context", {}) as Dictionary
	if (
		String(request.get("state", "")) not in ["pending", "waiting"]
		or String(request.get("requesterResidentId", "")) != recipient_id
		or String(context.get("pickupMessageId", "")) != message_id
		or int(context.get("preorderReservedQuantity", 0)) <= 0
	):
		return
	var expires_at := int(
		context.get("preorderExpiresAtMinute", delivered_at + 1440),
	)
	if expires_at <= delivered_at:
		return
	sync_resident_request({
		"request_id": "preorder-pickup:%s" % request_id,
		"source_revision": 1,
		"requester_id": sender_id,
		"submitted": true,
		"active": true,
		"reason_summary": "预订商品已经到店，可以回来领取",
		"subject_ids": [sender_id, recipient_id],
		"place_id": String(request.get("placeId", "")),
		"capability_id": "world.go_to_place",
		"target_refs": {"place_id": String(request.get("placeId", ""))},
		"success_result_id": "preorder-customer-arrived",
		"expires_at": expires_at,
		"capacity": 1,
		"source_event_ids": [request_id],
	})

func _activate_delivered_repair_pickup(
	message_id: String,
	request_id: String,
	sender_id: String,
	recipient_id: String,
	delivered_at: int,
	expires_at: int,
) -> void:
	var request := _occupation_services.request(request_id) as Dictionary
	var context := request.get("context", {}) as Dictionary
	var outcome := request.get("outcome", {}) as Dictionary
	if (
		String(request.get("kind", "")) != "repair"
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or String(request.get("requesterResidentId", "")) != recipient_id
		or String(context.get("pickupMessageId", "")) != message_id
		or String(outcome.get("status", "")) != "ready_for_pickup"
	):
		return
	if expires_at <= delivered_at:
		return
	sync_resident_request({
		"request_id": "repair-pickup:%s" % request_id,
		"source_revision": 1,
		"requester_id": sender_id,
		"submitted": true,
		"active": true,
		"reason_summary": "修理件已经完成，可以到工作坊领取",
		"subject_ids": [sender_id, recipient_id],
		"place_id": CONTENT_CATALOG.PLACE_WORKSHOP,
		"capability_id": "world.go_to_place",
		"target_refs": {"place_id": CONTENT_CATALOG.PLACE_WORKSHOP},
		"success_result_id": "repair-item-picked-up",
		"expires_at": expires_at,
		"capacity": 1,
		"source_event_ids": [request_id],
	})

func _activate_delivered_performance_invitation(
	day_index: int,
	sender_id: String,
	recipient_id: String,
	delivered_at: int,
	expires_at: int,
) -> void:
	if expires_at <= delivered_at:
		return
	var performance_active := false
	for request_value: Variant in (
		_occupation_services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		var context := request.get("context", {}) as Dictionary
		if (
			String(request.get("kind", "")) == "performance"
			and String(request.get("state", "")) in ["pending", "waiting"]
			and String(request.get("requesterResidentId", "")) == sender_id
			and int(context.get("dayIndex", -1)) == day_index
		):
			performance_active = true
			break
	if not performance_active:
		return
	sync_resident_request({
		"request_id": "performance-invitation:%d:%s"
			% [day_index, recipient_id],
		"source_revision": 1,
		"requester_id": sender_id,
		"submitted": true,
		"active": true,
		"reason_summary": "%s邀请居民到中心广场听演奏" % (
			_resident_display_name(sender_id)
		),
		"subject_ids": [sender_id, recipient_id],
		"place_id": CONTENT_CATALOG.PLACE_PLAZA,
		"capability_id": "world.go_to_place",
		"target_refs": {
			"place_id": CONTENT_CATALOG.PLACE_PLAZA,
			"resident_id": sender_id,
		},
		"success_result_id": "performance-audience-arrived",
		"expires_at": expires_at,
		"capacity": 1,
		"source_event_ids": ["performance-event:%d" % day_index],
	})

func _compact_delivered_private_messages() -> void:
	var delivered: Array[Dictionary] = []
	for value: Variant in _private_messages.values():
		var message := value as Dictionary
		if String(message.get("state", "")) == "delivered":
			delivered.append(message)
	delivered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("deliveredAtMinute", -1)) != int(b.get("deliveredAtMinute", -1)):
			return int(a.get("deliveredAtMinute", -1)) > int(b.get("deliveredAtMinute", -1))
		return String(a.get("messageId", "")) > String(b.get("messageId", ""))
	)
	for index in delivered.size():
		var message := delivered[index] as Dictionary
		var task := _work_tasks.task(
			String(message.get("taskId", "")),
		) as Dictionary
		if (
			index < MAX_DELIVERED_PRIVATE_MESSAGES
			and not task.is_empty()
			and String(task.get("state", "")) == "completed"
		):
			continue
		_private_message_archive_summary = (
			RESTORE_WORK.archive_private_message_in_summary(
				_private_message_archive_summary,
				message,
			)
		)
		_private_messages.erase(String(message.get("messageId", "")))

func _active_unsorted_postal_batch_id() -> String:
	var message_ids: Array[String] = []
	for message_id_value: Variant in _private_messages:
		message_ids.append(String(message_id_value))
	message_ids.sort()
	for message_id: String in message_ids:
		var message := _private_messages.get(message_id, {}) as Dictionary
		if String(message.get("state", "")) != "pending":
			continue
		var task := _work_tasks.task(
			String(message.get("taskId", "")),
		) as Dictionary
		if String(task.get("processStage", "")) == "awaiting_sort":
			return String(message.get("batchId", ""))
	return ""

func _enable_private_message_sender_delivery(message_id: String) -> void:
	var message := _private_messages.get(message_id, {}) as Dictionary
	if (
		message.is_empty()
		or String(message.get("state", "")) != "pending"
		or String(message.get("messageKind", "private")) != "private"
	):
		return
	var task_id := String(message.get("taskId", ""))
	var task := _work_tasks.task(task_id) as Dictionary
	if task.is_empty():
		return
	var sender_id := String(message.get("senderResidentId", ""))
	var granted := _work_tasks.add_eligible_residents(
		task_id,
		[sender_id],
	) as Dictionary
	if granted.get("ok") != true:
		return
	task = granted.get("task", {}) as Dictionary
	if String(task.get("processStage", "")) != "out_for_delivery":
		var staged := _work_tasks.set_process_stage_from_world(
			task_id,
			int(task.get("revision", 0)),
			"out_for_delivery",
			{
				"batchId": "",
				"messageId": message_id,
				"nextActivityId": "__resident_delivery__",
				"fallbackMode": "sender_in_person",
			},
		) as Dictionary
		if staged.get("ok") != true:
			return
	message["batchId"] = ""
	_private_messages[message_id] = message
	_schedule_decision(sender_id, true)

func _expire_time_sensitive_private_messages(absolute_minute: int) -> void:
	var expired_ids: Array[String] = []
	for message_id_value: Variant in _private_messages:
		var message_id := String(message_id_value)
		var message := _private_messages.get(message_id, {}) as Dictionary
		if (
			String(message.get("state", "")) == "pending"
			and int(message.get("expiresAtMinute", -1)) >= 0
			and absolute_minute >= int(message.get("expiresAtMinute", -1))
		):
			expired_ids.append(message_id)
	for message_id: String in expired_ids:
		_cancel_pending_private_message(message_id, "消息对应的事情已经过期")

func _cancel_private_messages_for_source(
	source_ref: String,
	reason: String,
) -> void:
	var normalized_source := source_ref.strip_edges()
	if normalized_source.is_empty():
		return
	var message_ids: Array[String] = []
	for message_id_value: Variant in _private_messages:
		var message_id := String(message_id_value)
		var message := _private_messages.get(message_id, {}) as Dictionary
		if (
			String(message.get("state", "")) == "pending"
			and String(message.get("sourceRef", "")) == normalized_source
		):
			message_ids.append(message_id)
	for message_id: String in message_ids:
		_cancel_pending_private_message(message_id, reason)

func _cancel_pending_private_message(
	message_id: String,
	reason: String,
) -> void:
	var message := _private_messages.get(message_id, {}) as Dictionary
	if message.is_empty() or String(message.get("state", "")) != "pending":
		return
	var task := _work_tasks.task(
		String(message.get("taskId", "")),
	) as Dictionary
	var assigned_id := String(task.get("assignedResidentId", ""))
	if not assigned_id.is_empty():
		var resident := _residents.get(assigned_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			String(action.get("type", "")) == "搭话"
			and String(action.get("say", "")).strip_edges()
			== String(message.get("content", "")).strip_edges()
		):
			_interrupt_action(assigned_id, reason)
		task = _work_tasks.task(
			String(message.get("taskId", "")),
		) as Dictionary
	if not task.is_empty() and String(task.get("state", "")) not in [
		"completed", "failed", "cancelled",
	]:
		_work_tasks.cancel_task(String(task.get("taskId", "")), reason)
	var cancelled_message := message.duplicate(true)
	cancelled_message["state"] = "cancelled"
	cancelled_message["reason"] = reason
	_append_private_message_log_event("消息取消", cancelled_message, "cancelled")
	_private_messages.erase(message_id)
	_bump_world_revision(false)

func _ensure_postal_sort_task(batch_id: String, created_at: int) -> void:
	if batch_id.is_empty():
		return
	_ensure_production_task({
		"taskId": "postal-sort-task:%s" % batch_id,
		"capability": "message.sort",
		"sourceKind": "postal_batch",
		"sourceRef": batch_id,
		"targets": [{"kind": "route", "ref": "小镇道路"}],
		"requestedResultKind": "message_batch_sorted",
		"createdAtMinute": created_at,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["postal_sort"],
	})

func _reserve_postal_delivery_tasks(batch_id: String) -> void:
	for message_value: Variant in _private_messages.values():
		var message := message_value as Dictionary
		if (
			String(message.get("batchId", "")) != batch_id
			or String(message.get("state", "")) != "pending"
		):
			continue
		var task := _work_tasks.task(String(message.get("taskId", "")),) as Dictionary
		_reserve_work_task(task, "occupation_postal_worker")


func _postal_batch_message_count(batch_id: String) -> int:
	var count := 0
	for message_value: Variant in _private_messages.values():
		var message := message_value as Dictionary
		if (
			String(message.get("batchId", "")) == batch_id
			and String(message.get("state", "")) == "pending"
		):
			count += 1
	return count

func _set_postal_delivery_tasks_stage(
	batch_id: String,
	stage: String,
	next_activity_id: String,
	now: int,
) -> void:
	for message_value: Variant in _private_messages.values():
		var message := message_value as Dictionary
		if (
			String(message.get("batchId", "")) != batch_id
			or String(message.get("state", "")) != "pending"
		):
			continue
		var task_id := String(message.get("taskId", ""))
		var task := _work_tasks.task(task_id) as Dictionary
		if task.is_empty():
			continue
		_work_tasks.set_process_stage_from_world(
			task_id,
			int(task.get("revision", 0)),
			stage,
			{
				"batchId": batch_id,
				"messageId": String(message.get("messageId", "")),
				"stageUpdatedAtMinute": now,
				"nextActivityId": next_activity_id,
			},
		)

func broadcast_announcement(text: String) -> Dictionary:
	return _publish_community_announcement(
		_player_avatar_id(),
		text,
		"",
		"town_bell",
	)

func _resident_announcement_delivery_mode(matter_id: String) -> String:
	var matter := _social_matters.get_matter(
		matter_id,
	) as Dictionary
	return (
		"town_bell"
		if String(matter.get("attention_level", "daily")) == "major"
		else "postal_notice"
	)

func _record_announcement_broadcast_knowledge(
	announcement: Dictionary,
) -> Dictionary:
	var announcement_id := String(
		announcement.get("announcement_id", ""),
	).strip_edges()
	var absolute_minute := int(
		_environment.get_absolute_minute(),
	)
	var resident_ids: Array[String] = []
	var reaction_resident_ids: Array[String] = []
	var publisher_id := String(
		announcement.get("publisher_id", ""),
	).strip_edges()
	for resident_id: String in _resident_order:
		if not _residents.has(resident_id):
			continue
		var received := _community_bulletin.receive_directly(
			resident_id,
			announcement_id,
			"announcement_broadcast",
			announcement_id,
			absolute_minute,
		) as Dictionary
		if received.get("ok") != true:
			return {
				"ok": false,
				"reason": String(
					received.get(
						"reason",
						"居民公告知情登记失败",
					)
				),
			}
		resident_ids.append(resident_id)
		if resident_id != publisher_id and _resident_is_alive(resident_id):
			reaction_resident_ids.append(resident_id)
	return {
		"ok": true,
		"resident_ids": resident_ids,
		"reaction_resident_ids": reaction_resident_ids,
	}


func _advance_announcement_schedules(absolute_minute: int) -> void:
	ANNOUNCEMENT_RESIDENT_RUNTIME.advance_schedules(self, _community_bulletin, absolute_minute)

func _deliver_town_bell_announcement(
	announcement: Dictionary,
	publish_event_id: String,
) -> String:
	var bell_event := _materialize_world_event({
		"type": "钟声公告",
		"announcement_id": String(
			announcement.get("announcement_id", ""),
		),
		"publisher_resident_id": String(
			announcement.get("publisher_id", ""),
		),
		"text": String(announcement.get("text", "")),
		"matter_id": (
			String(announcement.get("matter_id", ""))
			if not String(
				announcement.get("matter_id", ""),
			).is_empty()
			else null
		),
		"delivery_mode": "town_bell",
		"causedByEventIds": (
			[publish_event_id]
			if not publish_event_id.is_empty()
			else []
		),
		"storyRootEventIds": (
			[publish_event_id]
			if not publish_event_id.is_empty()
			else []
		),
	})
	return String(bell_event.get("event_id", ""))

func _queue_announcement_postal_notices(
	announcement: Dictionary,
) -> void:
	var publisher_id := String(announcement.get("publisher_id", ""))
	var announcement_id := String(announcement.get("announcement_id", "")).strip_edges()
	var matter_id := String(announcement.get("matter_id", ""))
	var matter := _social_matters.get_matter(matter_id) as Dictionary
	if publisher_id.is_empty() or announcement_id.is_empty() or matter.is_empty():
		return
	var recipients := {}
	for resident_value: Variant in matter.get("subject_ids", []) as Array:
		recipients[String(resident_value)] = true
	var creator_id := String(matter.get("creator_id", ""))
	if not creator_id.is_empty():
		recipients[creator_id] = true
	for candidate_value: Variant in matter.get(
		"fixed_candidates",
		[],
	) as Array:
		if candidate_value is Dictionary:
			recipients[String(
				(candidate_value as Dictionary).get("resident_id", ""),
			)] = true
	for participant_value: Variant in (
		matter.get("participants", {}) as Dictionary
	):
		recipients[String(participant_value)] = true
	for recipient_value: Variant in recipients:
		var recipient_id := String(recipient_value)
		if (
			recipient_id.is_empty()
			or recipient_id == publisher_id
			or not _residents.has(recipient_id)
			or _resident_knows_announcement(
				recipient_id,
				announcement_id,
			)
		):
			continue
		var message_payload := RESIDENT_MESSAGE_CONTENT.announcement_notice(
			publisher_id,
			recipient_id,
			String(announcement.get("text", "")),
			announcement_id,
			-1,
		)
		create_private_message(
			publisher_id,
			recipient_id,
			String(message_payload.get("content", "")),
			"announcement_notice",
			announcement_id,
			int(message_payload.get("expiresAtMinute", -1)),
			String(message_payload.get("sourceRef", "")),
		)

func _resident_knows_announcement(
	resident_id: String,
	announcement_id: String,
) -> bool:
	for value: Variant in _community_bulletin.knowledge_for(
		resident_id,
	) as Array:
		if String((value as Dictionary).get("announcement_id", "")) == (
			announcement_id
		):
			return true
	return false

func _private_message_delivery_task_for_talk(
	postal_resident_id: String,
	recipient_id: String,
	spoken_content: String,
) -> Dictionary:
	if spoken_content.strip_edges().is_empty():
		return {}
	var message_ids: Array[String] = []
	for message_id_value: Variant in _private_messages:
		message_ids.append(String(message_id_value))
	message_ids.sort()
	for message_id: String in message_ids:
		var message := _private_messages.get(message_id, {}) as Dictionary
		if (
			String(message.get("state", "")) != "pending"
			or String(message.get("recipientResidentId", "")) != recipient_id
			or String(message.get("content", "")).strip_edges()
			!= spoken_content.strip_edges()
		):
			continue
		var task := _work_tasks.task(
			String(message.get("taskId", "")),
		) as Dictionary
		var assigned_resident_id := String(
			task.get("assignedResidentId", ""),
		)
		if (
			task.is_empty()
			or not _resident_can_accept_work_task(
				postal_resident_id,
				task,
			)
			or String(task.get("processStage", "")) != "out_for_delivery"
			or String(task.get("state", "")) in [
				"completed",
				"failed",
				"cancelled",
			]
			or (
				not assigned_resident_id.is_empty()
				and assigned_resident_id != postal_resident_id
			)
		):
			continue
		return {
			"messageId": message_id,
			"message": message.duplicate(true),
			"task": task.duplicate(true),
		}
	return {}

func _prepare_postal_talk_approach(
	resident: Dictionary,
	target: Dictionary,
	prepared: Dictionary,
) -> Dictionary:
	var resident_space := String(resident.get("spaceId", ""))
	var target_space := String(target.get("spaceId", ""))
	var target_region := String(target.get("regionId", ""))
	var target_place := String(target.get("currentPlace", ""))
	var target_position := target.get("position", Vector2.ZERO) as Vector2
	if (
		resident_space.is_empty()
		or target_space.is_empty()
		or target_region.is_empty()
		or target_place.is_empty()
		or not target_position.is_finite()
	):
		return {"ok": false, "errors": ["收件人当前没有可接近的位置"]}
	prepared["targetSpaceId"] = target_space
	prepared["targetRegionId"] = target_region
	prepared["targetPlace"] = target_place
	prepared["expectedTargetPosition"] = target_position
	if resident_space == target_space:
		var path: Array[Vector2] = []
		if resident_space == "town_outdoor":
			var route := ROUTE_QUERY.find_route_to_outdoor_position(
				_world_data,
				{
					"position": resident.get("position", Vector2.ZERO),
					"spaceId": resident_space,
					"regionId": resident.get("regionId", ""),
					"currentPlace": resident.get("currentPlace", ""),
				},
				target_position,
				target_region,
				resident.get("routeConnector", []) as Array,
			) as Dictionary
			path = _outdoor_path_from_route(route)
		else:
			path.assign(
				INDOOR_PATH_QUERY.find_path(
					_indoor_navigation_for_space(resident_space),
					resident.get("position", Vector2.ZERO) as Vector2,
					target_position,
				) as Array,
			)
		if path.is_empty():
			return {"ok": false, "errors": ["当前没有到收件人身边的安全路线"]}
		var full_distance := _polyline_distance(path)
		var stop_distance := minf(
			POSTAL_TALK_APPROACH_STOP_DISTANCE_PX,
			full_distance,
		)
		var trimmed := _polyline_prefix(
			path,
			maxf(0.0, full_distance - stop_distance),
		)
		if not trimmed.is_empty():
			var endpoint_membership := PERCEPTION_RUNTIME._membership(self, 
				resident_space,
				trimmed[-1],
			)
			if String(endpoint_membership.get("regionId", "")) == target_region:
				path = trimmed
		prepared["approachMode"] = "same_space_path"
		prepared["pathPoints"] = path
		prepared["targetPosition"] = path[-1]
		prepared["durationMinutes"] = _prop_approach_duration_minutes(prepared)
		var return_connector := path.duplicate()
		return_connector.reverse()
		prepared["returnRouteConnector"] = return_connector
		prepared["consumeRouteConnector"] = not (
			resident.get("routeConnector", []) as Array
		).is_empty()
		if not _prepared_same_space_action_route_errors(
			resident,
			prepared,
		).is_empty():
			return {"ok": false, "errors": ["当前没有到收件人身边的安全路线"]}
		return {"ok": true, "action": prepared}
	if target_place == String(resident.get("currentPlace", "")):
		return {"ok": false, "errors": ["收件人当前不在可接近的地图空间"]}
	var approach_route := ROUTE_QUERY.find_route_from_state(
		_world_data,
		{
			"position": resident.get("position", Vector2.ZERO),
			"spaceId": resident_space,
			"regionId": resident.get("regionId", ""),
			"currentPlace": resident.get("currentPlace", ""),
		},
		target_place,
		resident.get("routeConnector", []) as Array,
	) as Dictionary
	if approach_route.is_empty():
		return {"ok": false, "errors": ["当前没有到收件人所在地点的固定路线"]}
	prepared["approachMode"] = "place_route"
	prepared["approachRoute"] = approach_route.duplicate(true)
	prepared["durationMinutes"] = int(
		approach_route.get("durationMinutes", 0),
	)
	prepared["consumeRouteConnector"] = not (
		resident.get("routeConnector", []) as Array
	).is_empty()
	return {"ok": true, "action": prepared}

func _activate_delivered_private_message_follow_up(
	message_id: String,
	message: Dictionary,
	delivered_at: int,
) -> void:
	if (
		String(message.get("state", "")) != "delivered"
		or String(message.get("messageKind", "private")) != "private"
		or String(message.get("messageId", "")) != message_id
	):
		return
	var source_ref := String(message.get("sourceRef", "")).strip_edges()
	var sender_id := String(message.get("senderResidentId", ""))
	var recipient_id := String(message.get("recipientResidentId", ""))
	if source_ref.begins_with("preorder:"):
		_activate_delivered_preorder_pickup(
			message_id,
			source_ref.substr("preorder:".length()),
			sender_id,
			recipient_id,
			delivered_at,
		)
		return
	if source_ref.begins_with("repair-pickup:"):
		_activate_delivered_repair_pickup(
			message_id,
			source_ref.substr("repair-pickup:".length()),
			sender_id,
			recipient_id,
			delivered_at,
			int(message.get("expiresAtMinute", -1)),
		)
		return
	if not source_ref.begins_with("performance-event:"):
		return
	var day_text := source_ref.substr("performance-event:".length())
	if not day_text.is_valid_int():
		return
	_activate_delivered_performance_invitation(
		int(day_text),
		sender_id,
		recipient_id,
		delivered_at,
		int(message.get("expiresAtMinute", -1)),
	)

func _apply_delivered_announcement_notice(
	message_id: String,
	message: Dictionary,
	postal_resident_id: String,
	recipient_id: String,
	delivered_at: int,
) -> void:
	if String(message.get("messageKind", "private")) != (
		"announcement_notice"
	):
		return
	var announcement_id := String(
		message.get("announcementId", ""),
	).strip_edges()
	var announcement := _community_bulletin.get_announcement(
		announcement_id,
	) as Dictionary
	if (
		announcement.is_empty()
		or String(announcement.get("delivery_mode", "board"))
		!= "postal_notice"
	):
		return
	_community_bulletin.receive_directly(
		postal_resident_id,
		announcement_id,
		"postal_notice",
		message_id,
		delivered_at,
	)
	var received := _community_bulletin.receive_directly(
		recipient_id,
		announcement_id,
		"postal_notice",
		message_id,
		delivered_at,
	) as Dictionary
	if received.get("ok") != true:
		return
	_queue_world_event(recipient_id, {
		"type": "正式通知送达",
		"announcement_id": announcement_id,
		"speaker_resident_id": postal_resident_id,
		"message_id": message_id,
		"text": String(announcement.get("text", "")),
		"matter_id": (
			String(announcement.get("matter_id", ""))
			if not String(
				announcement.get("matter_id", ""),
			).is_empty()
			else null
		),
	})

func _ordinary_private_message_recipients(
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id := _resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	var pending_from_sender := 0
	for message_value: Variant in _private_messages.values():
		var message := message_value as Dictionary
		if (
			String(message.get("senderResidentId", "")) == resident_id
			and String(message.get("state", "")) == "pending"
		):
			pending_from_sender += 1
	if pending_from_sender >= 2:
		return []
	var recipients: Array[Dictionary] = []
	for other_id: String in _resident_order:
		if other_id == resident_id:
			continue
		var other := _residents.get(other_id, {}) as Dictionary
		if not _resident_is_present(other):
			continue
		recipients.append({
			"resident_id": other_id,
			"name": _resident_display_name(other_id),
		})
	return recipients
