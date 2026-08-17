extends "res://tests/support/TownWorldTestCase.gd"
const RESIDENT_RUNTIME_FACTORY := preload(
	"res://world/runtime/lifecycle/TownResidentRuntimeFactory.gd"
)
const AGENT_WORLD_QUERY_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWorldQueryRuntime.gd"
)
const AGENT_WAKE_CONTEXT_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWakeContextRuntime.gd"
)
const ACTIVITY_STEP_EXECUTION_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityStepExecutionRuntime.gd"
)
const ACTION_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/action/TownActionSettlementRuntime.gd"
)
const ACTIVITY_ACTION_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityActionSettlementRuntime.gd"
)
const PASSIVE_NEED_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/activity/TownPassiveNeedAdvancementRuntime.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const GO_ACTION_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/movement/TownGoActionAdvancementRuntime.gd"
)
## 活动系统 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - town_world_activity_runtime_test.gd
## - town_world_activity_routine_test.gd
## - town_world_activity_catalog_contract_test.gd
## - town_world_activity_validator_test.gd
## - town_far_resident_activity_live_anchor_test.gd
## - town_far_resident_activity_incremental_refresh_test.gd
## - town_world_bulletin_activity_test.gd
## - town_default_occupation_activity_test.gd
## - town_world_activity_semantic_icon_test.gd
## - town_ui_adapter_activity_semantic_test.gd
## - town_activity_physical_occupancy_test.gd
## - town_weather_activity_policy_test.gd

class AnchorProvider:
	var anchors := {
		"resident-a": Vector2(500, 500),
		"resident-b": Vector2(700, 500),
		"resident-c": Vector2(1050, 560),
		"resident-d": Vector2(1250, 560),
	}
	var hidden: Dictionary = {}

	func get_town_hud_resident_head_anchor(resident_id: String) -> Dictionary:
		if not anchors.has(resident_id):
			return {"valid": false, "visible": false}
		var point := anchors[resident_id] as Vector2
		return {
			"valid": true,
			"visible": not bool(hidden.get(resident_id, false)),
			"kind": "head",
			"coordinateSpace": "viewport_logical",
			"x": point.x,
			"y": point.y,
			"spaceId": "town_outdoor",
		}

const ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownWorldActivityRuntime.gd"
)
const ACTIVITY_REACHABILITY_CACHE := preload(
	"res://world/runtime/activity/TownActivityReachabilityCache.gd"
)
const SAVE_SCHEMA_REGISTRY := preload(
	"res://world/presentation/session/TownSaveSchemaRegistry.gd"
)
const SAVE_CODEC := preload(
	"res://world/runtime/persistence/TownWorldSaveCodec.gd"
)
const RESIDENT_PRESENTATION := preload(
	"res://world/presentation/residents/ResidentCharacterPresentation.gd"
)
const WORK_CASES := [
	{
		"resident": "林岚",
		"residentId": "resident_lin_lan_01",
		"place": "工作坊",
		"prop": "工作坊主木工台",
		"verb": "制作器物",
		"capability": "craft.production",
		"sourceKind": "production_request",
		"resultKind": "crafted_lot",
	},
	{
		"resident": "阿禾",
		"residentId": "resident_a_he_01",
		"place": "花房咖啡馆",
		"prop": "花房咖啡馆咖啡机",
		"verb": "冲咖啡",
		"capability": "cafe.order",
		"sourceKind": "customer_order",
		"resultKind": "order_handoff",
	},
	{
		"resident": "顾川",
		"residentId": "resident_gu_chuan_01",
		"place": "诊所",
		"prop": "诊所药柜",
		"verb": "取药",
		"capability": "care.treatment",
		"sourceKind": "resident_care_request",
		"resultKind": "care_outcome",
	},
	{
		"resident": "苏禾",
		"residentId": "resident_su_he_01",
		"place": "图书馆",
		"prop": "图书馆还书车",
		"verb": "归还书籍",
		"capability": "library.return",
		"sourceKind": "returned_book",
		"resultKind": "loan_record",
	},
	{
		"resident": "赵棠",
		"residentId": "resident_zhao_tang_01",
		"place": "镇公所",
		"prop": "镇公所档案柜",
		"verb": "查档案",
		"capability": "civic.service",
		"sourceKind": "resident_request",
		"resultKind": "civic_case_update",
	},
	{
		"resident": "陈舟",
		"residentId": "resident_chen_zhou_01",
		"place": "码头仓库",
		"prop": "码头仓库入库木箱",
		"verb": "检查货物",
		"capability": "inventory.receive",
		"sourceKind": "inventory_discrepancy",
		"resultKind": "inventory_record",
	},
	{
		"resident": "陆青",
		"residentId": "resident_lu_qing_01",
		"place": "公共食堂",
		"prop": "公共食堂灶台",
		"verb": "做饭",
		"capability": "food.production",
		"sourceKind": "meal_demand",
		"resultKind": "food_batch",
	},
]
const CATALOG := preload(
	"res://world/data/town/TownWorldActivityCatalog.gd"
)
const VALIDATOR := preload(
	"res://world/data/town/TownWorldActivityValidator.gd"
)
const OCCUPATION_PATH := (
	SOURCE_DIR + "/occupation_catalog.json"
)
const RESIDENT_CATALOG_PATH := (
	"res://world/data/town/resident_catalog.json"
)
const PLACES_PATH := SOURCE_DIR + "/places.json"
const PROPS_PATH := SOURCE_DIR + "/props.json"
const INDOOR_AUTHORING_PATH := SOURCE_DIR + "/indoor_prop_authoring.json"
const SCHEDULE_PATH := SOURCE_DIR + "/schedule_templates.json"
const EXPECTED_REQUIRED_TARGET_FIELDS := ["activityId", "placeId"]
const EXPECTED_OPTIONAL_TARGET_FIELDS := ["preferredSlotId"]
const EXPECTED_OPTIONAL_PARAMS_FIELDS := ["reason"]
const EXPECTED_WORLD_QUERY_FIELDS := [
	"activityId",
	"label",
	"placeId",
	"role",
	"available",
	"disabledReason",
	"preferredSlots",
]
const EXPECTED_TEMPLATE_FIELDS := [
	"activityId",
	"label",
	"placeId",
	"role",
	"preferredSlots",
]
const EXPECTED_ERROR_CODES := [
	"ACTIVITY_UNKNOWN",
	"ACTIVITY_PLACE_MISMATCH",
	"ACTIVITY_NOT_ELIGIBLE",
	"ACTIVITY_REQUIRES_TRAVEL_STEP",
	"ACTIVITY_SLOT_REFERENCE_INVALID",
	"ACTIVITY_NO_EXECUTABLE_SLOT",
	"ACTIVITY_TARGET_UNREACHABLE",
	"ACTIVITY_RESERVATION_CONFLICT",
	"ACTIVITY_STATE_CHANGED",
]
const EXPECTED_IDEMPOTENCY_KEY_FIELDS := [
	"residentId",
	"planId",
	"stepId",
	"planRevision",
]
const FORBIDDEN_PUBLIC_FIELDS := [
	"sceneId",
	"propId",
	"propName",
	"actionId",
	"actionVerb",
	"anchorId",
	"memberAnchorId",
	"facing",
	"position",
	"coordinate",
	"route",
	"geometry",
	"duration",
	"durationMinutes",
	"durationTicks",
	"effects",
	"poseFamily",
	"capacity",
	"reservation",
	"reservationGeneration",
	"reservationRevision",
	"sourceFingerprint",
	"scheduleTemplateId",
	"schedule",
	"windowId",
	"goalPressure",
]
const OCCUPATION_PATH_ACTIVITY_VALIDATOR := SOURCE_DIR + "/occupation_catalog.json"
const ACTIVITY_PATH := SOURCE_DIR + "/activity_definitions.json"
const SLOT_PATH := SOURCE_DIR + "/activity_slots.json"
const LAYER_SCENE := preload(
	"res://ui/town/hud/runtime/TownFarResidentActivityLayer.tscn"
)
const HUD_SCENE := preload("res://ui/town/hud/runtime/TownHudOverlay.tscn")
const PROP_QUERY := preload(
	"res://world/data/town/TownWorldPropQuery.gd"
)
const RESIDENT_ID := "resident_lin_lan_01"
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ICON_MANIFEST_PATH := (
	"res://assets/ui/town/hud/runtime/action_icons_readable_v4/icon_manifest.json"
)
const PROP_SOURCE_PATH := "res://world/data/town/source/props.json"
const ADAPTER := preload(
	"res://world/presentation/ui/TownUiAdapter.gd"
)
const POLICY := preload(
	"res://world/runtime/activity/TownWorldWeatherActivityPolicy.gd"
)
const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const WORK_SETTLEMENT := preload(
	"res://world/runtime/work/TownWorkSettlement.gd"
)

var _started_events: Array[Dictionary] = []
var _completed_events: Array[Dictionary] = []
var _interrupted_events: Array[Dictionary] = []
var _state_change_counts: Dictionary = {}
var _started_by_resident: Dictionary = {}
var _service_activity_sequence := 0
var _occupation_document: Dictionary
var _activity_document: Dictionary
var _slot_document: Dictionary
var _places_document: Dictionary
var _props_document: Dictionary
var _indoor_authoring_document: Dictionary
var _schedule_document: Dictionary
var _resident_reactions: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_scenario_activity_reachability_cache()
	_scenario_activity_runtime()
	_scenario_activity_routine()
	_scenario_activity_catalog_contract()
	_scenario_activity_validator()
	_scenario_far_resident_activity_live_anchor()
	_scenario_far_resident_activity_incremental_refresh()
	_scenario_bulletin_activity()
	_scenario_default_occupation_activity()
	_scenario_activity_semantic_icon()
	_scenario_ui_adapter_activity_semantic()
	_scenario_activity_physical_occupancy()
	_scenario_weather_activity_policy()
	_finish_suite("TOWN_ACTIVITY_PASS")


func _scenario_activity_reachability_cache() -> void:
	var cache: TownActivityReachabilityCache = ACTIVITY_REACHABILITY_CACHE.new()
	var resident := {
		"residentId": "resident-cache-test",
		"spaceId": "town_outdoor",
		"currentPlace": "测试地点",
		"position": Vector2(10.0, 20.0),
		"routeConnector": [],
	}
	var candidate := {
		"targetType": "prop",
		"targetRegionId": "",
		"targetPropName": "测试道具",
		"targetActionVerb": "测试动作",
		"memberPosition": [30.0, 40.0],
	}
	_expect_equal(
		cache.cached_reachability(100, resident, candidate, {}),
		null,
		"uncached activity candidate has no reachability result",
	)
	cache.remember_reachability(
		resident,
		candidate,
		{},
		true,
		{
			"targetPosition": Vector2(30.0, 40.0),
			"path": [Vector2(10.0, 20.0), Vector2(30.0, 40.0)],
		},
	)
	_expect_equal(cache.reachability_count(), 1, "reachability result is cached")
	_expect_equal(cache.prepared_action_count(), 1, "prepared action is cached")
	var first_copy := cache.cached_prepared_action(100, resident, candidate)
	first_copy["targetPosition"] = Vector2.ZERO
	_expect_equal(
		cache.cached_prepared_action(100, resident, candidate).get("targetPosition"),
		Vector2(30.0, 40.0),
		"prepared action cache returns a deep copy",
	)
	_expect_equal(
		cache.cached_reachability(100, resident, candidate, {}),
		true,
		"same-minute reachability query reuses the cached result",
	)
	cache.ensure_minute(101)
	_expect(
		cache.reachability_count() == 0
			and cache.prepared_action_count() == 0
			and cache.cached_minute() == 101,
		"minute change invalidates both activity route caches",
	)
	_expect_equal(
		cache.cached_prepared_action(100, resident, candidate),
		{},
		"stale-minute prepared action cannot be reused",
	)
	cache.clear()
	_expect_equal(cache.cached_minute(), -1, "explicit cache clear resets the minute")


func _scenario_activity_runtime() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "activity opening loads")
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	_verify_compiled_data_fail_closed(data, opening)
	_verify_runtime_contract(data)
	_verify_weather_activity_policy(data)
	_verify_opening_body_and_numeric_needs_stay_aligned(data, opening)
	_verify_sleep_energy_and_leave_policy(data, opening)
	_verify_world_query_and_execution(data, opening)
	_verify_passive_needs_tick_is_presentation_silent(data, opening)
	_verify_hunger_wakes_idle_agent(data, opening)
	_verify_stationary_activity_minutes_are_presentation_silent(data, opening)
	_verify_legacy_prop_activity_adapter(data, opening)
	_verify_save_restore(data, opening)
	_verify_world_weather_execution(data, opening)
	return


func _verify_opening_body_and_numeric_needs_stay_aligned(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var hungry_opening := opening.duplicate(true)
	var residents := hungry_opening.get("residents", []) as Array
	var resident_opening := residents[0] as Dictionary
	var world_state := resident_opening.get("worldState", {}) as Dictionary
	world_state["body"] = {
		"困": "不困",
		"饿": "很饿",
		"累": "有点累",
	}
	var resident_id := String(resident_opening.get("residentId", ""))
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, hungry_opening) as Dictionary).get("ok"),
		true,
		"World starts with a non-neutral opening body state",
	)
	var initial := world.call("get_resident_state", resident_id) as Dictionary
	_expect_equal(
		initial.get("body"),
		world_state.get("body"),
		"opening qualitative body state is preserved",
	)
	_expect_equal(
		(
			initial.get("activityNeeds", {}) as Dictionary
		).get("satiety"),
		20,
		"very hungry opening starts from the matching numeric satiety",
	)
	_expect_equal(
		(
			initial.get("activityNeeds", {}) as Dictionary
		).get("energy"),
		35,
		"slightly tired opening starts from the matching numeric energy",
	)
	world.call("advance", 60.0)
	var advanced := world.call(
		"get_resident_state",
		resident_id,
	) as Dictionary
	_expect_equal(
		(advanced.get("body", {}) as Dictionary).get("饿"),
		"很饿",
		"elapsed-time consumption cannot make a hungry resident less hungry",
	)



func _verify_sleep_energy_and_leave_policy(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var work_opening := opening.duplicate(true)
	(work_opening.get("environment", {}) as Dictionary)["clock"] = "10:00"
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, work_opening) as Dictionary).get("ok"),
		true,
		"sleep policy World starts during a work period",
	)
	var resident_id := "resident_su_he_01"
	_expect_equal(
		(
			world.call(
				"create_work_task",
				{
					"taskId": "sleep_policy_library_return",
					"capability": "library.return",
					"sourceKind": "returned_book",
					"sourceRef": "sleep_policy_return_pile",
					"targets": [{
						"kind": "prop",
						"ref": "图书馆归还书台",
					}],
					"requestedResultKind": "loan_record",
					"priority": 60,
				},
			) as Dictionary
		).get("ok"),
		true,
		"sleep policy fixture gives the resident real work",
	)
	var resident := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {})
		as Dictionary
	)
	var activity_state := (
		resident.get("activityState", {}) as Dictionary
	).duplicate(true)
	activity_state["energy"] = 35
	resident["activityState"] = activity_state
	ACTIVITY_SCALARS.sync_body_from_activity_needs(resident, activity_state)
	_expect(
		not (world.call("get_work_tasks_for_resident", resident_id) as Array).is_empty(),
		"low-energy resident still has work before taking leave",
	)
	var life_options := AGENT_WORLD_QUERY_RUNTIME.life_destination_options(
		world, resident,
	) as Array
	var sleep_destination_found := false
	for destination_value: Variant in life_options:
		var destination := destination_value as Dictionary
		if String(destination.get("place_id", "")) != "西街二号住宅":
			continue
		for option_value: Variant in destination.get("activities", []) as Array:
			if String(
				(option_value as Dictionary).get("activity_id", ""),
			) == "activity_home_sleep":
				sleep_destination_found = true
	_expect(
		sleep_destination_found,
		"low energy exposes the resident's own bed even while work is waiting",
	)
	var rhythm := AGENT_WORLD_QUERY_RUNTIME.life_rhythm(world, resident) as Dictionary
	_expect_equal(
		rhythm.get("sleep_needed"),
		true,
		"work-period wake marks low energy as a sleep decision",
	)
	_expect(
		String(rhythm.get("label", "")).contains("上班时也可以请假"),
		"work-period wake explains that sleep may require leave",
	)

	var home_anchor := RESIDENT_RUNTIME_FACTORY.home_anchor(
		data,
		resident,
	) as Dictionary
	resident["currentPlace"] = String(home_anchor.get("placeName", ""))
	resident["spaceId"] = String(home_anchor.get("spaceId", ""))
	resident["regionId"] = String(home_anchor.get("regionId", ""))
	resident["position"] = home_anchor.get("position", Vector2.ZERO)
	resident["routeConnector"] = []
	activity_state["energy"] = 50
	resident["activityState"] = activity_state
	ACTIVITY_SCALARS.sync_body_from_activity_needs(resident, activity_state)
	var rested_query := world.call(
		"query_activity_options",
		resident_id,
	) as Dictionary
	var rested_sleep := _activity_option(
		rested_query.get("options", []) as Array,
		"activity_home_sleep",
	)
	_expect_equal(
		rested_sleep.get("available"),
		false,
		"a rested resident is not offered sleep",
	)
	_expect_equal(
		rested_sleep.get("disabledReason"),
		"SLEEP_NOT_NEEDED",
		"sleep option records the authoritative energy rejection",
	)
	_expect(
		not JSON.stringify(
			AGENT_WAKE_CONTEXT_RUNTIME.available_props(world, resident),
		).contains("睡觉"),
		"the legacy bed verb is hidden while energy is high",
	)
	var sleep_step := _activity_step(
		"sleep-policy-step",
		"activity_home_sleep",
		"西街二号住宅",
	)
	_expect_equal(
		(
			world.call(
				"perform_activity_step",
				resident_id,
				"sleep-policy-rested",
				1,
				sleep_step,
			) as Dictionary
		).get("errorCode"),
		"ACTIVITY_NOT_ELIGIBLE",
		"direct activity.perform cannot bypass the high-energy rejection",
	)

	activity_state["energy"] = 35
	resident["activityState"] = activity_state
	ACTIVITY_SCALARS.sync_body_from_activity_needs(resident, activity_state)
	_expect_equal(
		_activity_option(
			(
				world.call("query_activity_options", resident_id)
				as Dictionary
			).get("options", []) as Array,
			"activity_home_sleep",
		).get("available"),
		true,
		"low energy makes sleep available at the resident's own bed",
	)
	_expect(
		JSON.stringify(
			AGENT_WAKE_CONTEXT_RUNTIME.available_props(world, resident),
		).contains("睡觉"),
		"the legacy bed verb remains available when sleep is needed",
	)
	_expect_equal(
		(
			world.call(
				"perform_activity_step",
				resident_id,
				"sleep-policy-tired",
				1,
				sleep_step,
			) as Dictionary
		).get("ok"),
		true,
		"low-energy resident can start sleeping during work hours",
	)
	resident = (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {})
		as Dictionary
	)
	_expect_equal(
		String(
			(resident.get("attendanceState", {}) as Dictionary).get(
				"status",
				"",
			),
		),
		"on_leave",
		"starting work-hour sleep creates real leave",
	)
	_expect_equal(
		(world.call("get_work_tasks_for_resident", resident_id) as Array).size(),
		0,
		"work is no longer assigned while the resident is on sleep leave",
	)

	var save := world.call("create_save_snapshot") as Dictionary
	var snapshot := (save.get("snapshot", {}) as Dictionary).duplicate(true)
	var restored: RefCounted = WORLD.new()
	_expect_equal(
		(
			restored.call(
				"restore_from_snapshot",
				data,
				work_opening,
				snapshot,
			) as Dictionary
		).get("ok"),
		true,
		"active sleep leave survives save and restore",
	)
	var restored_resident := (
		((restored.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {})
		as Dictionary
	)
	_expect_equal(
		String(
			(restored_resident.get("attendanceState", {}) as Dictionary).get(
				"status",
				"",
			),
		),
		"on_leave",
		"restored resident remains on leave until sleep ends",
	)
	var restored_action := restored_resident.get("currentAction", {}) as Dictionary
	var sleep_minutes := int(restored_action.get("durationMinutes", 0))
	sleep_minutes += ACTION_SUPPORT.prop_approach_duration_minutes(
		restored,
		restored_action,
	)
	restored.call("advance", float(sleep_minutes + 1))
	restored_resident = (
		((restored.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {})
		as Dictionary
	)
	_expect_equal(
		String(
			(restored_resident.get("attendanceState", {}) as Dictionary).get(
				"status",
				"",
			),
		),
		"available",
		"sleep completion ends leave",
	)
	_expect(
		int(
			(restored_resident.get("activityState", {}) as Dictionary).get(
				"energy",
				0,
			),
		) > 35,
		"sleep restores energy above the sleep threshold",
	)
	_expect_equal(
		(
			restored.call(
				"perform_activity_step",
				resident_id,
				"sleep-policy-repeat",
				1,
				_activity_step(
					"sleep-policy-repeat-step",
					"activity_home_sleep",
					"西街二号住宅",
				),
			) as Dictionary
		).get("errorCode"),
		"ACTIVITY_NOT_ELIGIBLE",
		"a resident who woke with enough energy cannot immediately sleep again",
	)


func _verify_compiled_data_fail_closed(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	for section in [
		"occupations",
		"activityDefinitions",
		"activitySlots",
		"scheduleTemplates",
		"activityIntegrationReceipt",
	]:
		var missing := data.duplicate(true)
		missing.erase(section)
		var world: RefCounted = WORLD.new()
		var result := world.call("start", missing, opening) as Dictionary
		_expect_equal(
			result.get("errorCode"),
			"WORLD_DATA_INVALID",
			"start fails closed without %s" % section,
		)
	var forged := data.duplicate(true)
	(
		forged.get("activityIntegrationReceipt", {}) as Dictionary
	)["placeCapabilitiesVerified"] = false
	var runtime: RefCounted = ACTIVITY_RUNTIME.new()
	_expect_equal(
		(runtime.call("configure", forged) as Dictionary).get("errorCode"),
		"ACTIVITY_RUNTIME_DATA_NOT_COMPILED",
		"runtime rejects a receipt with a false validator proof",
	)
	var fake_document_keys := data.duplicate(true)
	var receipt := (
		fake_document_keys.get(
			"activityIntegrationReceipt",
			{},
		) as Dictionary
	)
	var fingerprints := {}
	for index in 7:
		fingerprints["fake-%d.json" % index] = "fake"
	receipt["sourceDocumentFingerprints"] = fingerprints
	_expect_equal(
		(
			ACTIVITY_RUNTIME.new().call(
				"configure",
				fake_document_keys,
			) as Dictionary
		).get("errorCode"),
		"ACTIVITY_RUNTIME_DATA_NOT_COMPILED",
		"seven fake fingerprint keys cannot authorize runtime data",
	)



func _verify_runtime_contract(data: Dictionary) -> void:
	var runtime: RefCounted = ACTIVITY_RUNTIME.new()
	_expect_equal(
		(runtime.call("configure", data) as Dictionary).get("ok"),
		true,
		"compiled activity runtime configures",
	)
	_verify_semantic_region_targets(runtime)
	var social := {
		"home": "西街二号住宅",
		"job": "图书管理员",
		"workplace": "图书馆",
	}
	var query := runtime.call(
		"query_options",
		"resident_one",
		social,
		"图书馆",
		600,
	) as Dictionary
	_expect_equal(query.get("ok"), true, "static runtime options resolve")
	for option_value: Variant in query.get("options", []) as Array:
		var option := option_value as Dictionary
		_expect_exact_keys(
			option,
			[
				"activityId",
				"label",
				"placeId",
				"role",
				"available",
				"disabledReason",
				"preferredSlots",
				"weatherReason",
				"weatherSuitability",
			],
			"query option stays on the frozen safe projection",
		)
		for slot_value: Variant in option.get("preferredSlots", []) as Array:
			var slot := slot_value as Dictionary
			_expect_exact_keys(
				slot,
				["slotId", "label"],
				"preferred slot exposes only stable id and readable label",
			)
			_expect(
				not String(slot.get("label", "")).is_empty(),
				"preferred slot label comes from its readable carrier",
			)
	var cross_place := runtime.call(
		"validate_step",
		"resident_one",
		"plan_cross_place",
		1,
		_activity_step(
			"step_cross_place",
			"activity_dining_eat_meal",
			"公共食堂",
		),
		social,
		"图书馆",
	) as Dictionary
	_expect_equal(
		cross_place.get("errorCode"),
		"ACTIVITY_REQUIRES_TRAVEL_STEP",
		"activity never invents a cross-place movement",
	)


	var expanded_step := _activity_step(
		"step_expanded",
		"activity_library_shelve_returns",
		"图书馆",
	)
	expanded_step["residentId"] = "resident_one"
	expanded_step["planId"] = "plan_illegal"
	expanded_step["planRevision"] = 1
	_expect_equal(
		(
			runtime.call(
				"validate_step",
				"resident_one",
				"plan_illegal",
				1,
				expanded_step,
				social,
				"图书馆",
			) as Dictionary
		).get("errorCode"),
		"ACTIVITY_STATE_CHANGED",
		"plan envelope fields are rejected inside ResidentPlanDraft step",
	)
	var preferred := _activity_step(
		"step_cafe_rest_greenhouse",
		"activity_cafe_rest",
		"花房咖啡馆",
		"slot_cafe_rest_greenhouse_01",
	)
	var first := runtime.call(
		"validate_step",
		"resident_one",
		"plan_read",
		1,
		preferred,
		social,
		"花房咖啡馆",
	) as Dictionary
	first["sourceContract"] = "activity.perform"
	first["sourceActionId"] = ""
	var first_candidate := (
		first.get("candidates", []) as Array
	)[0] as Dictionary
	_expect_equal(
		(
			runtime.call(
				"reserve_execution",
				first,
				first_candidate.get("slotId"),
				first_candidate.get("memberAnchorId"),
			) as Dictionary
		).get("ok"),
		true,
		"first resident compare-and-reserves the preferred member",
	)
	var second := runtime.call(
		"validate_step",
		"resident_two",
		"plan_read",
		1,
		preferred,
		social,
		"花房咖啡馆",
	) as Dictionary
	second["sourceContract"] = "activity.perform"
	second["sourceActionId"] = ""
	var second_candidates := second.get("candidates", []) as Array
	_expect_equal(
		second_candidates.size(),
		2,
		"same_activity_other_slot exposes exactly one deterministic fallback",
	)
	_expect_equal(
		(second_candidates[0] as Dictionary).get("memberAvailable"),
		false,
		"occupied preferred member is unavailable",
	)
	_expect_equal(
		(second_candidates[1] as Dictionary).get("memberAvailable"),
		true,
		"frozen fallback selects the other matching slot",
	)
	var fallback := second_candidates[1] as Dictionary
	_expect_equal(
		(
			runtime.call(
				"reserve_execution",
				second,
				fallback.get("slotId"),
				fallback.get("memberAnchorId"),
			) as Dictionary
		).get("ok"),
		true,
		"second resident reserves the fallback without stacking",
	)
	var snapshot := runtime.call("create_save_snapshot") as Dictionary
	_expect_equal(
		(snapshot.get("reservations", []) as Array).size(),
		2,
		"two residents occupy two distinct atomic reservation keys",
	)
	var repeated := runtime.call(
		"validate_step",
		"resident_one",
		"plan_read",
		1,
		preferred,
		social,
		"花房咖啡馆",
	) as Dictionary
	_expect_equal(repeated.get("idempotent"), true, "same execution key is idempotent")
	var different_payload := preferred.duplicate(true)
	(different_payload.get("params", {}) as Dictionary)["reason"] = "changed"
	_expect_equal(
		(
			runtime.call(
				"validate_step",
				"resident_one",
				"plan_read",
				1,
				different_payload,
				social,
				"花房咖啡馆",
			) as Dictionary
		).get("errorCode"),
		"ACTIVITY_STATE_CHANGED",
		"same idempotency key cannot carry different payload",
	)
	var action_id := String(
		(
			(snapshot.get("executions", []) as Array)[0] as Dictionary
		).get("actionId", "")
	)
	runtime.call("interrupt_action", "resident_one", action_id, "test")
	var released := runtime.call("create_save_snapshot") as Dictionary
	_expect_equal(
		(released.get("reservations", []) as Array).size(),
		1,
		"interrupt releases exactly the resident reservation",
	)



func _verify_semantic_region_targets(runtime: RefCounted) -> void:
	var botanist_targets := runtime.call(
		"semantic_region_targets",
		"activity_botanist_observe_plants",
	) as Array
	_expect_equal(
		botanist_targets.size(),
		3,
		"植物观察会展开到全镇三个正式花木区域",
	)
	var place_ids: Dictionary = {}
	for value: Variant in botanist_targets:
		var target := value as Dictionary
		_expect_equal(target.get("kind"), "region", "语义地点保持区域目标")
		place_ids[String(target.get("placeId", ""))] = true
	for place_id: String in ["中心广场", "社区花园", "河岸公园"]:
		_expect(
			place_ids.has(place_id),
			"植物观察覆盖正式地点：%s" % place_id,
		)
	var garden_targets := runtime.call(
		"semantic_region_targets",
		"activity_farm_water_beds",
	) as Array
	_expect_equal(
		garden_targets.size(),
		1,
		"园艺照料只命中具备 garden.care 的正式地点",
	)



func _verify_weather_activity_policy(data: Dictionary) -> void:
	var runtime: RefCounted = ACTIVITY_RUNTIME.new()
	_expect_equal(
		(runtime.call("configure", data) as Dictionary).get("ok"),
		true,
		"weather policy uses the compiled activity catalog",
	)
	var botanist_social := {
		"home": "西街二号住宅",
		"job": "植物学家",
		"workplace": "社区花园",
	}
	var sunny := runtime.call(
		"query_options",
		"resident_botanist",
		botanist_social,
		"社区花园",
		600,
		"晴天",
	) as Dictionary
	var sunny_observation := _activity_option(
		sunny.get("options", []) as Array,
		"activity_botanist_observe_plants",
	)
	_expect_equal(
		sunny_observation.get("available"),
		true,
		"sunny weather keeps an executable outdoor activity available",
	)
	_expect_equal(
		sunny_observation.get("weatherSuitability"),
		"preferred",
		"sunny weather prefers outdoor activity",
	)
	var storm := runtime.call(
		"query_options",
		"resident_botanist",
		botanist_social,
		"社区花园",
		600,
		"雷暴",
	) as Dictionary
	var storm_observation := _activity_option(
		storm.get("options", []) as Array,
		"activity_botanist_observe_plants",
	)
	_expect_equal(
		storm_observation.get("available"),
		false,
		"thunderstorm closes unsafe outdoor activity",
	)
	_expect_equal(
		storm_observation.get("disabledReason"),
		"ACTIVITY_WEATHER_UNSAFE",
		"weather rejection remains a stable World reason",
	)
	var rainy_cafe := runtime.call(
		"query_options",
		"resident_visitor",
		{},
		"花房咖啡馆",
		600,
		"大雨",
	) as Dictionary
	var pastry := _activity_option(
		rainy_cafe.get("options", []) as Array,
		"activity_cafe_eat_pastry",
	)
	_expect_equal(
		pastry.get("available"),
		true,
		"rain keeps a reachable indoor public activity available",
	)
	_expect_equal(
		pastry.get("weatherSuitability"),
		"preferred",
		"rain prefers a public indoor visitor activity",
	)
	var context := runtime.call(
		"weather_context",
		"大雨",
		"社区花园",
	) as Dictionary
	_expect_equal(
		context.get("outdoorPolicy"),
		"discouraged",
		"weather context explains the outdoor tradeoff without forcing home",
	)
	var alternatives := context.get("indoorAlternatives", []) as Array
	_expect(
		alternatives.has("花房咖啡馆")
		and alternatives.has("公共食堂")
		and alternatives.has("图书馆"),
		"rain exposes several public indoor alternatives instead of one home answer",
	)


# C1 世界级用例(docs/居民状态通知链减负方案.md):整点需求变化只改
# activityState/body,不发 resident_state_changed;世界状态与 HUD 拉取仍正确。

func _verify_passive_needs_tick_is_presentation_silent(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"C1 world starts for the passive-needs silence case",
	)
	world.connect("resident_state_changed", _on_state_changed_counted)
	_state_change_counts.clear()
	var resident_id := "resident_su_he_01"
	var before := world.call("get_resident_state", resident_id) as Dictionary
	var before_needs := before.get("activityNeeds", {}) as Dictionary
	PASSIVE_NEED_ADVANCEMENT_RUNTIME.advance(
		world,
		WORLD.PASSIVE_NEED_TICK_MINUTES,
	)
	_expect_equal(
		_state_change_counts.size(),
		0,
		"hourly needs tick emits zero resident_state_changed",
	)
	var after := world.call("get_resident_state", resident_id) as Dictionary
	var after_needs := after.get("activityNeeds", {}) as Dictionary
	_expect(
		after_needs != before_needs,
		"hourly needs tick still updates settled activityNeeds",
	)
	_expect_equal(
		after_needs.get("energy"),
		int(before_needs.get("energy", 0)) - 2,
		"hourly needs numeric semantics stay unchanged",
	)
	var hud := {}
	for hud_value: Variant in world.call("get_town_hud_resident_states") as Array:
		if String((hud_value as Dictionary).get("residentId", "")) == resident_id:
			hud = hud_value as Dictionary
	_expect_equal(
		hud.get("body"),
		after.get("body"),
		"town_hud pull path reflects the updated body facts",
	)


func _verify_hunger_wakes_idle_agent(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	var resident_id := "resident_su_he_01"
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"饥饿唤醒用例能启动 World",
	)
	var resident := ((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {}) as Dictionary
	resident["decisionPending"] = false
	resident["pendingWake"] = {}
	resident["wakeDispatchQueued"] = false
	resident["validDecisionId"] = ""
	resident["currentAction"] = {}
	var activity_state := (resident.get("activityState", {}) as Dictionary).duplicate(true)
	activity_state["satiety"] = 38
	resident["activityState"] = activity_state
	((world.get("resident_registry") as TownResidentRegistry).records as Dictionary)[resident_id] = resident
	PASSIVE_NEED_ADVANCEMENT_RUNTIME.advance(
		world, WORLD.PASSIVE_NEED_TICK_MINUTES,
	)
	var after := ((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {}) as Dictionary
	_expect_equal(
		(after.get("activityState", {}) as Dictionary).get("satiety"),
		35,
		"空闲居民跨过有点饿阈值后饱腹度正确下降",
	)
	_expect(
		bool(after.get("decisionPending", false)),
		"空闲居民饿到阈值后立即进入 Agent 判断队列",
	)
	var requests := world.call(
		"take_pending_decision_requests_by_ids",
		[resident_id],
	) as Array
	_expect_equal(requests.size(), 1, "饥饿唤醒能被 Agent 请求队列取到")
	world.call("stop")


# C1 世界级用例:原地 performing 的逐分钟心跳(含 worker doing 轮换)零发射,
# 完成事件仍然通知表现层。

func _verify_stationary_activity_minutes_are_presentation_silent(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"C1 world starts for the stationary-minutes silence case",
	)
	var resident_id := "resident_su_he_01"
	_expect_equal(
		(
			world.call(
				"create_work_task",
				{
					"taskId": "c1_silence_library_return_001",
					"capability": "library.return",
					"sourceKind": "returned_book",
					"sourceRef": "c1_silence_return_pile_001",
					"targets": [{
						"kind": "prop",
						"ref": "图书馆归还书台",
					}],
					"requestedResultKind": "loan_record",
					"priority": 60,
				},
			) as Dictionary
		).get("ok"),
		true,
		"C1 silence case reuses the librarian shelve work fixture",
	)
	var step := _activity_step(
		"step_shelve",
		"activity_library_shelve_returns",
		"图书馆",
		"slot_library_shelve_returns_01",
	)
	_expect_equal(
		(
			world.call(
				"perform_activity_step",
				resident_id,
				"plan_c1_silence",
				1,
				step,
			) as Dictionary
		).get("ok"),
		true,
		"C1 silence case starts the stationary activity",
	)
	var resident := ((world.get("resident_registry") as TownResidentRegistry).records as Dictionary)[resident_id] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	var approach_minutes := ACTION_SUPPORT.prop_approach_duration_minutes(
		world,
		action,
	)
	var duration_minutes := int(action.get("durationMinutes", 0))
	# 静默窗口取 performing 第 2..(duration-1) 分钟:跨过 doing 的 5 分钟轮换点,
	# 又不触及完成分钟(完成事件独立发射,不属于心跳静默范围)。
	_expect(
		duration_minutes >= 9,
		"fixture keeps a stationary performing window long enough to observe",
	)
	var execution := world.get("_activity_runtime").call(
		"execution_for_action",
		resident_id,
		String(action.get("action_id", "")),
	) as Dictionary
	_expect_equal(
		execution.get("role"),
		"worker",
		"fixture exercises the worker doing rotation",
	)
	world.call("advance", float(approach_minutes + 1))
	world.connect("resident_state_changed", _on_state_changed_counted)
	_state_change_counts.clear()
	var position_before := resident.get("position", Vector2.ZERO) as Vector2
	var doing_values := {}
	for _minute in range(maxi(6, duration_minutes - 3)):
		world.call("advance", 1.0)
		doing_values[String(
			(
				world.call("get_resident_state", resident_id) as Dictionary
			).get("doing", "")
		)] = true
	_expect_equal(
		int(_state_change_counts.get(resident_id, 0)),
		0,
		"stationary performing minutes emit zero resident_state_changed",
	)
	_expect_equal(
		resident.get("position", Vector2.ZERO),
		position_before,
		"the stationary resident never moved during the silent window",
	)
	_expect(
		doing_values.size() >= 2,
		"worker doing keeps rotating without any emission",
	)
	world.call("advance", float(approach_minutes + duration_minutes + 5))
	_expect(
		int(_state_change_counts.get(resident_id, 0)) >= 1,
		"activity completion still notifies the presentation layer",
	)



func _on_state_changed_counted(_resident_name: String, state: Dictionary) -> void:
	var resident_id := String(state.get("residentId", ""))
	_state_change_counts[resident_id] = int(
		_state_change_counts.get(resident_id, 0)
	) + 1



func _verify_world_query_and_execution(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	world.connect("resident_activity_started", _on_activity_started)
	world.connect("resident_activity_completed", _on_activity_completed)
	world.connect("resident_activity_interrupted", _on_activity_interrupted)
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"World starts with compiled activity data",
	)
	var resident_id := "resident_su_he_01"
	_expect_equal(
		(
			world.call(
				"create_work_task",
				{
					"taskId": "runtime_library_return_001",
					"capability": "library.return",
					"sourceKind": "returned_book",
					"sourceRef": "runtime_return_pile_001",
					"targets": [{
						"kind": "prop",
						"ref": "图书馆归还书台",
					}],
					"requestedResultKind": "loan_record",
					"priority": 60,
				},
			) as Dictionary
		).get("ok"),
		true,
		"real returned books create the librarian work used by this runtime test",
	)
	var initial_state := world.call(
		"get_resident_state",
		resident_id,
	) as Dictionary
	_expect_equal(
		initial_state.get("activityNeeds"),
		{
			"energy": 50,
			"satiety": 50,
			"stress": 50,
			"socialNeed": 50,
			"solitudeNeed": 50,
		},
		"opening without initialLifeState uses one neutral compatibility default",
	)
	var wake_requests := world.call(
		"take_pending_decision_requests_by_ids",
		[resident_id],
	) as Array
	var wake_me := (
		(
			(wake_requests[0] as Dictionary).get(
				"wakePacket",
				{},
			) as Dictionary
		).get("snapshot", {}) as Dictionary
	).get("me", {}) as Dictionary
	var wake_snapshot := (
		(wake_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
	).get("snapshot", {}) as Dictionary
	var weather_context := wake_snapshot.get(
		"weather_context",
		{},
	) as Dictionary
	_expect_equal(
		weather_context.get("outdoorPolicy"),
		"preferred",
		"Agent wake receives World-confirmed weather activity context",
	)
	_expect(
		weather_context.has("indoorAlternatives"),
		"weather context keeps one stable public projection shape",
	)
	_expect_equal(
		wake_me.get("activityNeeds"),
		initial_state.get("activityNeeds"),
		"Agent wake receives the same settled public life facts",
	)
	_expect(
		not JSON.stringify(wake_me).contains("\"effects\""),
		"Agent wake does not expose activity definition effects",
	)
	var revision_before_query := int(world.call("get_world_revision"))
	var query := world.call("query_activity_options", resident_id) as Dictionary
	_expect_equal(query.get("ok"), true, "World returns activity options")
	_expect_equal(
		world.call("get_world_revision"),
		revision_before_query,
		"availability preflight is read-only",
	)
	var query_text := JSON.stringify(query.get("options", []))
	for forbidden in [
		"memberAnchor",
		"anchorId",
		"position",
		"effects",
		"reservation",
		"sourceFingerprint",
		"scheduleTemplate",
	]:
		_expect(
			not query_text.contains(forbidden),
			"World query hides %s" % forbidden,
		)
	var shelve_option := _activity_option(
		query.get("options", []) as Array,
		"activity_library_shelve_returns",
	)
	_expect_equal(
		shelve_option.get("available"),
		true,
		"availability includes a reachable unreserved last-mile target",
	)
	var read_option := _activity_option(
		query.get("options", []) as Array,
		"activity_library_read",
	)
	var read_slots := read_option.get("preferredSlots", []) as Array
	_expect(
		read_slots.size() == 1
		and String((read_slots[0] as Dictionary).get("label", ""))
		== "图书馆东侧阅读桌",
		"the library keeps one dedicated reading table",
	)
	var write_option := _activity_option(
		query.get("options", []) as Array,
		"activity_library_write",
	)
	var write_slots := write_option.get("preferredSlots", []) as Array
	_expect(
		write_slots.size() == 1
		and String((write_slots[0] as Dictionary).get("label", ""))
		== "图书馆写作桌",
		"the other library table gives personal writing goals an executable place",
	)
	var step := _activity_step(
		"step_shelve",
		"activity_library_shelve_returns",
		"图书馆",
		"slot_library_shelve_returns_01",
	)
	var perform := world.call(
		"perform_activity_step",
		resident_id,
		"plan_library_work",
		1,
		step,
	) as Dictionary
	_expect_equal(perform.get("ok"), true, "same-place activity starts")
	var source_collision := ACTIVITY_STEP_EXECUTION_RUNTIME.perform(
		world,
		resident_id,
		"plan_library_work",
		1,
		step,
		"legacy.agent.use_prop",
		"source-collision-action",
	) as Dictionary
	_expect_equal(
		source_collision.get("errorCode"),
		"ACTIVITY_STATE_CHANGED",
		"idempotency key cannot be reused across direct and legacy source contracts",
	)
	var state := world.call("get_resident_state", resident_id) as Dictionary
	_expect(
		state.get("currentAction") != null,
		"activity reuses the existing prop action path",
	)
	world.call("_schedule_decision", resident_id, true, false, true)
	var direct_activity_requests := world.call(
		"take_pending_decision_requests_by_ids",
		[resident_id],
	) as Array
	_expect_equal(
		direct_activity_requests.size(),
		1,
		"an explicit activity interruption still creates one Agent wake request",
	)
	if direct_activity_requests.is_empty():
		return
	var direct_activity_wake := (
		(direct_activity_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
	)
	var direct_activity_me := (
		direct_activity_wake.get("snapshot", {}) as Dictionary
	).get("me", {}) as Dictionary
	_expect_equal(
		direct_activity_me.get("current_action"),
		null,
		"direct activity.perform is not injected into the old five-action Agent wake",
	)
	_expect(
		not JSON.stringify(direct_activity_wake).contains(
			"sourceContract"
		),
		"direct activity wake does not expose internal source metadata",
	)
	_expect_equal(
		_started_events.size(),
		1,
		"activity start emits one semantic event",
	)
	world.call("advance", 120.0)
	_expect_equal(
		_completed_events.size(),
		1,
		"activity completion emits one semantic event",
	)
	var completed_state := world.call(
		"get_resident_state",
		resident_id,
	) as Dictionary
	_expect_equal(
		(
			completed_state.get("activityNeeds", {}) as Dictionary
		).get("energy"),
		45,
		"settled activity and elapsed-time needs are available to later decisions",
	)
	_expect(
		not JSON.stringify(completed_state).contains("\"effects\""),
		"resident state does not leak the activity definition effects table",
	)
	var save := world.call("create_save_snapshot") as Dictionary
	var state_document := (
		(save.get("snapshot", {}) as Dictionary).get(
			"state",
			{},
		) as Dictionary
	)
	var decoded := preload(
		"res://world/runtime/persistence/TownWorldSaveCodec.gd"
	).decode_checked(state_document) as Dictionary
	var saved_resident := _saved_resident(
		decoded.get("value", {}) as Dictionary,
		resident_id,
	)
	_expect_equal(
		(
			saved_resident.get("activityState", {}) as Dictionary
		).get("energy"),
		45,
		"World is the single owner that applies activity and elapsed-time effects",
	)
	var repeated := world.call(
		"perform_activity_step",
		resident_id,
		"plan_library_work",
		1,
		step,
	) as Dictionary
	_expect_equal(repeated.get("idempotent"), true, "completed step remains idempotent")
	var save_after_repeat := world.call("create_save_snapshot") as Dictionary
	var decoded_after := preload(
		"res://world/runtime/persistence/TownWorldSaveCodec.gd"
	).decode_checked(
		(save_after_repeat.get("snapshot", {}) as Dictionary).get(
			"state",
			{},
		),
	) as Dictionary
	_expect_equal(
		(
			_saved_resident(
				decoded_after.get("value", {}) as Dictionary,
				resident_id,
			).get("activityState", {}) as Dictionary
		).get("energy"),
		45,
		"repeated completion does not apply effects twice",
	)
	_expect_equal(
		(
			(
				world.call(
					"get_resident_state",
					resident_id,
				) as Dictionary
			).get("activityNeeds", {}) as Dictionary
		).get("energy"),
		45,
		"public settled needs also remain exactly-once",
	)
	var clamped := ACTIVITY_SCALARS.next_activity_state(
		{
			"activityState": {
				"energy": 99,
				"satiety": 1,
				"stress": 100,
				"socialNeed": 0,
				"solitudeNeed": 50,
			},
		},
		{
			"energy": 20,
			"satiety": -20,
			"stress": 1,
			"socialNeed": -1,
			"solitudeNeed": 70,
		},
		WORLD.ACTIVITY_STATE_KEYS,
	) as Dictionary
	_expect_equal(
		clamped,
		{
			"energy": 100,
			"satiety": 0,
			"stress": 100,
			"socialNeed": 0,
			"solitudeNeed": 100,
		},
		"every instantaneous activity settlement clamps all five values to 0..100",
	)
	var interrupt_step := _activity_step(
		"step_read",
		"activity_library_read",
		"图书馆",
		"slot_library_read_east_01",
	)
	_expect_equal(
		(
			world.call(
				"perform_activity_step",
				resident_id,
				"plan_read",
				1,
				interrupt_step,
			) as Dictionary
		).get("ok"),
		true,
		"replacement scenario starts a long activity",
	)
	var replacement_step := _activity_step(
		"step_read_replacement",
		"activity_library_read",
		"图书馆",
		"slot_library_read_east_01",
	)
	_expect_equal(
		(
			world.call(
				"perform_activity_step",
				resident_id,
				"plan_read_replacement",
				1,
				replacement_step,
			) as Dictionary
		).get("ok"),
		true,
		"new valid activity can replace the old execution on the same slot",
	)
	_expect_equal(
		_interrupted_events.size(),
		1,
		"replacement releases and emits one interruption",
	)



func _verify_legacy_prop_activity_adapter(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var unique_world: RefCounted = WORLD.new()
	var legacy_started_events: Array[Dictionary] = []
	var completion_lifecycle_save_state := {}
	unique_world.connect(
		"resident_activity_started",
		func(_resident_id: String, event: Dictionary) -> void:
			legacy_started_events.append(event.duplicate(true))
	)
	unique_world.connect(
		"resident_activity_completed",
		func(_resident_id: String, _event: Dictionary) -> void:
			completion_lifecycle_save_state.merge(
				_decoded_world_save_state(unique_world),
				true,
			)
	)
	_expect_equal(
		(unique_world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"legacy adapter World starts",
	)
	var unique := _submit_legacy_prop_decision(
		unique_world,
		"resident_su_he_01",
		"legacy-checkout",
		"图书馆借还书柜台",
		"借还书",
	)
	_expect_equal(unique.get("ok"), true, "unique legacy prop mapping starts")
	_expect_equal(
		(unique.get("action", {}) as Dictionary).get("type"),
		"用道具",
		"legacy activity remains a legal old-contract action projection",
	)
	_expect_equal(
		(unique.get("action", {}) as Dictionary).get("action_id"),
		"legacy-checkout",
		"legacy activity projection preserves the original source action_id",
	)
	_expect_equal(
		(
			_activity_runtime_save_state(unique_world).get(
				"reservations",
				[],
			) as Array
		).size(),
		1,
		"legacy prop decision cannot bypass atomic activity reservation",
	)
	var unique_state := unique_world.call(
		"get_resident_state",
		"resident_su_he_01",
	) as Dictionary
	_expect_equal(
		unique_state.get("currentAction"),
		{
			"action_id": "legacy-checkout",
			"type": "用道具",
		},
		"resident projection keeps the original legacy action identity",
	)
	_expect(
		not JSON.stringify(unique_state).contains("sourceContract")
		and not JSON.stringify(legacy_started_events).contains(
			"sourceActionId"
		),
		"public resident state and lifecycle hide legacy source metadata",
	)
	# Community announcements are no longer a global resident wake. Schedule a
	# non-invalidating decision directly so this check keeps proving that an
	# Agent wake during an active legacy activity preserves the public action.
	unique_world.call(
		"_schedule_decision",
		"resident_su_he_01",
		false,
		false,
		false,
		false,
		true,
	)
	var activity_wake_requests := unique_world.call(
		"take_pending_decision_requests_by_ids",
		["resident_su_he_01"],
	) as Array
	_expect_equal(
		activity_wake_requests.size(),
		1,
		"active legacy activity schedules one non-invalidating Agent wake",
	)
	if activity_wake_requests.is_empty():
		return
	var activity_wake := (
		(activity_wake_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
	)
	var activity_wake_action: Variant = (
		(activity_wake.get("snapshot", {}) as Dictionary).get(
			"me",
			{},
		) as Dictionary
	).get("current_action")
	_expect_equal(
		activity_wake_action,
		{
			"action_id": "legacy-checkout",
			"type": "用道具",
		},
		"wake during legacy activity remains valid for AgentContract",
	)
	_expect(
		not JSON.stringify(activity_wake).contains("sourceContract")
		and not JSON.stringify(activity_wake).contains(
			"sourceActionId"
		),
		"legacy Agent wake does not expose internal source metadata",
	)
	unique_world.call("advance", 120.0)
	var completion_requests := unique_world.call(
		"take_pending_decision_requests_by_ids",
		["resident_su_he_01"],
	) as Array
	_expect_equal(
		completion_requests.size(),
		1,
		"legacy activity completion schedules one follow-up Agent wake",
	)
	if completion_requests.is_empty():
		return
	var completion_wake := (
		(completion_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
	)
	_expect_equal(
		_action_result_count(
			completion_wake,
			"legacy-checkout",
			"completed",
		),
		1,
		"legacy completion returns one old action result and schedules the next decision",
	)
	_expect_equal(
		_saved_action_result_count(
			completion_lifecycle_save_state,
			"resident_su_he_01",
			"legacy-checkout",
			"completed",
		),
		1,
		"completion lifecycle callback save already contains the single legacy result",
	)

	var replace_world: RefCounted = WORLD.new()
	replace_world.call("start", data, opening)
	var replace_requests := replace_world.call(
		"take_pending_decision_requests_by_ids",
		["resident_su_he_01"],
	) as Array
	var replace_wake := (
		(replace_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
	)
	replace_world.call(
		"submit_agent_decision_by_id",
		"resident_su_he_01",
		{
			"decision_id": String(replace_wake.get("decision_id", "")),
			"handling": "replace_current",
			"action": {
				"action_id": "ordinary-action-before-activity",
				"type": "去",
				"place": "社区花园",
				"line": "先去社区花园。",
			},
		},
	)
	_expect_equal(
		(
			replace_world.call(
				"perform_activity_step",
				"resident_su_he_01",
				"replace-ordinary-plan",
				1,
				_activity_step(
					"replace-ordinary-step",
					"activity_library_checkout",
					"图书馆",
					"slot_library_checkout_01",
				),
			) as Dictionary
		).get("ok"),
		true,
		"activity.perform replaces an ordinary action through the no-schedule boundary",
	)
	_expect_equal(
		(
			replace_world.call(
				"take_pending_decision_requests_by_ids",
				["resident_su_he_01"],
			) as Array
		).size(),
		0,
		"successful ordinary-action replacement does not enqueue a competing Agent decision",
	)

	var legacy_replace_world: RefCounted = WORLD.new()
	var interruption_lifecycle_save_state := {}
	legacy_replace_world.connect(
		"resident_activity_interrupted",
		func(_resident_id: String, _event: Dictionary) -> void:
			interruption_lifecycle_save_state.merge(
				_decoded_world_save_state(legacy_replace_world),
				true,
			)
	)
	legacy_replace_world.call("start", data, opening)
	_submit_legacy_prop_decision(
		legacy_replace_world,
		"resident_su_he_01",
		"legacy-replaced",
		"图书馆借还书柜台",
		"借还书",
	)
	legacy_replace_world.call(
		"_schedule_decision",
		"resident_su_he_01",
		false,
		false,
		false,
		false,
		true,
	)
	var legacy_replace_requests := legacy_replace_world.call(
		"take_pending_decision_requests_by_ids",
		["resident_su_he_01"],
	) as Array
	_expect_equal(
		legacy_replace_requests.size(),
		1,
		"active legacy activity schedules one replacement decision",
	)
	if legacy_replace_requests.is_empty():
		return
	var legacy_replace_wake := (
		(legacy_replace_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
	)
	legacy_replace_world.call(
		"submit_agent_decision_by_id",
		"resident_su_he_01",
		{
			"decision_id": String(
				legacy_replace_wake.get("decision_id", "")
			),
			"handling": "replace_current",
			"action": {
				"action_id": "legacy-replacement-go",
				"type": "去",
				"place": "社区花园",
				"line": "结束当前活动后去社区花园。",
			},
		},
	)
	_expect_equal(
		(
			legacy_replace_world.call(
				"take_pending_decision_requests_by_ids",
				["resident_su_he_01"],
			) as Array
		).size(),
		0,
		"Agent-submitted replacement records legacy interruption without a competing wake",
	)
	_expect_equal(
		_saved_action_result_count(
			interruption_lifecycle_save_state,
			"resident_su_he_01",
			"legacy-replaced",
			"interrupted",
		),
		1,
		"interruption lifecycle callback save contains the no-schedule result",
	)

	var legacy_failure_world: RefCounted = WORLD.new()
	var failure_lifecycle_save_state := {}
	legacy_failure_world.connect(
		"resident_activity_failed",
		func(_resident_id: String, _event: Dictionary) -> void:
			failure_lifecycle_save_state.merge(
				_decoded_world_save_state(legacy_failure_world),
				true,
			)
	)
	legacy_failure_world.call("start", data, opening)
	_submit_legacy_prop_decision(
		legacy_failure_world,
		"resident_su_he_01",
		"legacy-failed",
		"图书馆借还书柜台",
		"借还书",
	)
	ACTIVITY_ACTION_SETTLEMENT_RUNTIME.fail(
		legacy_failure_world,
		"resident_su_he_01",
		"ACTIVITY_STATE_CHANGED",
		"静态失败夹具",
	)
	var failure_requests := legacy_failure_world.call(
		"take_pending_decision_requests_by_ids",
		["resident_su_he_01"],
	) as Array
	var failure_wake := (
		(failure_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
	)
	_expect_equal(
		_action_result_count(
			failure_wake,
			"legacy-failed",
			"rejected",
		),
		1,
		"legacy failure returns one rejected old action result and schedules",
	)
	_expect_equal(
		_saved_action_result_count(
			failure_lifecycle_save_state,
			"resident_su_he_01",
			"legacy-failed",
			"rejected",
		),
		1,
		"failed lifecycle callback save already contains the rejected result",
	)

	var observed_world: RefCounted = WORLD.new()
	observed_world.call("start", data, opening)
	observed_world.call(
		"set_observed_action_preview_resident",
		"resident_su_he_01",
		true,
	)
	var observed_submission := _submit_legacy_prop_decision(
		observed_world,
		"resident_su_he_01",
		"legacy-observed-checkout",
		"图书馆借还书柜台",
		"借还书",
	)
	_expect_equal(
		observed_submission.get("status"),
		"accepted",
		"observed legacy prop decision enters the confirmed preview",
	)
	_expect_equal(
		(
			_activity_runtime_save_state(observed_world).get(
				"reservations",
				[],
			) as Array
		).size(),
		0,
		"observed preview creates no phantom reservation",
	)
	_expect_equal(
		(
			observed_world.call(
				"get_resident_action_phase",
				"resident_su_he_01",
			) as Dictionary
		).get("phase"),
		"executing_preview",
		"observed resident keeps the existing 2.5 second preview phase",
	)
	observed_world.call("advance", 3.0)
	_expect_equal(
		(
			_activity_runtime_save_state(observed_world).get(
				"reservations",
				[],
			) as Array
		).size(),
		1,
		"preview expiry performs fresh preflight and reserves exactly once",
	)
	_expect_equal(
		(
			(
				observed_world.call(
					"get_resident_state",
					"resident_su_he_01",
				) as Dictionary
			).get("currentAction", {}) as Dictionary
		).get("type"),
		"用道具",
		"observed legacy prop activates only after the preview boundary",
	)

	var shared_opening := opening.duplicate(true)
	var library_state := {}
	for resident_value: Variant in shared_opening.get("residents", []) as Array:
		var record := resident_value as Dictionary
		if String(record.get("residentId", "")) == "resident_su_he_01":
			library_state = (
				record.get("worldState", {}) as Dictionary
			).duplicate(true)
	for resident_value: Variant in shared_opening.get("residents", []) as Array:
		var record := resident_value as Dictionary
		if String(record.get("residentId", "")) == "resident_zhao_tang_01":
			record["worldState"] = library_state.duplicate(true)
			record["socialState"] = {
				"home": "西街三号住宅",
				"job": "图书管理员",
				"workplace": "图书馆",
			}
	var conflict_world: RefCounted = WORLD.new()
	_expect_equal(
		(
			conflict_world.call(
				"start",
				data,
				shared_opening,
			) as Dictionary
		).get("ok"),
		true,
		"shared-slot legacy adapter World starts",
	)
	_expect_equal(
		(
			conflict_world.call(
				"create_work_task",
				{
					"taskId": "runtime_library_conflict_return_001",
					"capability": "library.return",
					"sourceKind": "returned_book",
					"sourceRef": "runtime_conflict_return_pile_001",
					"targets": [{
						"kind": "prop",
						"ref": "图书馆归还书台",
					}],
					"requestedResultKind": "loan_record",
					"priority": 60,
				},
			) as Dictionary
		).get("ok"),
		true,
		"real returned books create an executable fallback task",
	)
	_expect_equal(
		(
			_submit_legacy_prop_decision(
				conflict_world,
				"resident_su_he_01",
				"legacy-first-checkout",
				"图书馆借还书柜台",
				"借还书",
			) as Dictionary
		).get("ok"),
		true,
		"first legacy prop decision reserves the unique member",
	)
	var conflicting_submission := _submit_legacy_prop_decision(
		conflict_world,
		"resident_zhao_tang_01",
		"legacy-conflict-checkout",
		"图书馆借还书柜台",
		"借还书",
	) as Dictionary
	_expect_equal(
		conflicting_submission.get("errorCode"),
		"ACTIVITY_RESERVATION_CONFLICT",
		"second legacy prop decision is rejected instead of stacking",
	)
	var retry_requests := conflict_world.call(
		"take_pending_decision_requests_by_ids",
		["resident_zhao_tang_01"],
	) as Array
	_expect_equal(
		retry_requests.size(),
		1,
		"busy activity position immediately gives the second resident another decision",
	)
	var retry_wake := (
		(retry_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
		if not retry_requests.is_empty()
		else {}
	)
	_expect(
		not _wake_has_prop_verb(
			retry_wake,
			"图书馆借还书柜台",
			"借还书",
		),
		"busy activity position is removed from the second resident's fresh wake",
	)
	_expect(
		_wake_has_prop_verb(
			retry_wake,
			"图书馆还书车",
			"归还书籍",
		),
		"the second resident still receives another executable workplace task",
	)
	var repeated_observation := conflict_world.call(
		"submit_agent_decision_by_id",
		"resident_zhao_tang_01",
		{
			"decision_id": String(retry_wake.get("decision_id", "")),
			"handling": "replace_current",
			"action": {
				"action_id": "wait-after-busy-position",
				"type": "待着",
				"line": "我先停一停，看看周围再作打算。",
			},
		},
	) as Dictionary
	_expect_equal(
		repeated_observation.get("ok"),
		true,
		"a resident displaced from a busy workstation may pause briefly before deciding again",
	)
	_expect_equal(
		(
			(
				conflict_world.call(
					"get_resident_state",
					"resident_zhao_tang_01",
				) as Dictionary
			).get("currentAction", {}) as Dictionary
		).get("type"),
		"待着",
		"the bounded pause becomes a real World action",
	)
	conflict_world.call("advance", 6.0)
	var reconsider_requests := conflict_world.call(
		"take_pending_decision_requests_by_ids",
		["resident_zhao_tang_01"],
	) as Array
	_expect_equal(
		reconsider_requests.size(),
		1,
		"the short pause ends with a fresh resident decision",
	)
	var reconsider_wake := (
		(reconsider_requests[0] as Dictionary).get(
			"wakePacket",
			{},
		) as Dictionary
		if not reconsider_requests.is_empty()
		else {}
	)
	conflict_world.call(
		"set_observed_action_preview_resident",
		"resident_zhao_tang_01",
		true,
	)
	var observed_conflict := conflict_world.call(
		"submit_agent_decision_by_id",
		"resident_zhao_tang_01",
		{
			"decision_id": String(
				reconsider_wake.get("decision_id", ""),
			),
			"handling": "replace_current",
			"action": {
				"action_id": "legacy-observed-conflict-checkout",
				"type": "用道具",
				"prop": "图书馆借还书柜台",
				"verb": "借还书",
				"line": "执行明确的道具活动。",
			},
		},
	) as Dictionary
	_expect_equal(
		observed_conflict.get("errorCode"),
		"ACTIVITY_RESERVATION_CONFLICT",
		"observed residents cannot preview an already occupied activity slot",
	)
	_expect_equal(
		(
			_activity_runtime_save_state(conflict_world).get(
				"reservations",
				[],
			) as Array
		).size(),
		1,
		"conflicting observed preview does not create a phantom reservation",
	)
	conflict_world.call("advance", 3.0)
	_expect_equal(
		(
			_activity_runtime_save_state(conflict_world).get(
				"reservations",
				[],
			) as Array
		).size(),
		1,
		"activation-time conflict is rejected without leaking a reservation",
	)

	var same_activity_data := data.duplicate(true)
	var duplicate_slot := {}
	for slot_value: Variant in same_activity_data.get("activitySlots", []) as Array:
		var slot := slot_value as Dictionary
		if String(slot.get("slotId", "")) == "slot_library_checkout_01":
			duplicate_slot = slot.duplicate(true)
			break
	duplicate_slot["slotId"] = "slot_library_checkout_same_activity_test"
	var duplicate_member := (
		(duplicate_slot.get("memberAnchors", []) as Array)[0]
		as Dictionary
	)
	duplicate_member["memberAnchorId"] = "member_library_checkout_same_activity_test"
	(same_activity_data.get("activitySlots", []) as Array).append(duplicate_slot)
	var same_activity_runtime: RefCounted = ACTIVITY_RUNTIME.new()
	same_activity_runtime.call("configure", same_activity_data)
	_expect_equal(
		(
			same_activity_runtime.call(
				"legacy_activity_mapping",
				{
					"home": "西街二号住宅",
					"job": "图书管理员",
					"workplace": "图书馆",
				},
				"图书馆",
				"图书馆借还书柜台",
				"借还书",
			) as Dictionary
		).get("activityId"),
		"activity_library_checkout",
		"multiple matching slots remain legal when activityId is unique",
	)
	var ambiguous_data := same_activity_data.duplicate(true)
	var ambiguous_slot := (
		(ambiguous_data.get("activitySlots", []) as Array)[-1]
		as Dictionary
	)
	ambiguous_slot["activityId"] = "activity_library_research"
	var ambiguous_runtime: RefCounted = ACTIVITY_RUNTIME.new()
	_expect_equal(
		(
			ambiguous_runtime.call(
				"configure",
				ambiguous_data,
			) as Dictionary
		).get("ok"),
		true,
		"ambiguous legacy runtime fixture configures for rejection coverage",
	)
	_expect_equal(
		(
			ambiguous_runtime.call(
				"legacy_activity_mapping",
				{
					"home": "西街二号住宅",
					"job": "图书管理员",
					"workplace": "图书馆",
				},
				"图书馆",
				"图书馆借还书柜台",
				"借还书",
			) as Dictionary
		).get("errorCode"),
		"ACTIVITY_SLOT_REFERENCE_INVALID",
		"multiple exact eligible activityIds are rejected without random choice",
	)

	var missing_world: RefCounted = WORLD.new()
	missing_world.call("start", data, opening)
	_expect_equal(
		(
			_submit_legacy_prop_decision(
				missing_world,
				"resident_su_he_01",
				"legacy-missing",
				"不存在的道具",
				"不存在的动作",
			) as Dictionary
		).get("errorCode"),
		"ACTIVITY_NO_EXECUTABLE_SLOT",
		"zero exact eligible mappings are rejected without old prop fallback",
	)



func _verify_save_restore(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var resident_id := "resident_su_he_01"
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"save/restore activity World starts",
	)
	var step := _activity_step(
		"step_restore_read",
		"activity_library_read",
		"图书馆",
	)
	_expect_equal(
		(
			world.call(
				"perform_activity_step",
				resident_id,
				"plan_restore",
				1,
				step,
			) as Dictionary
		).get("ok"),
		true,
		"active execution exists before save",
	)
	var save := world.call("create_save_snapshot") as Dictionary
	var snapshot := (
		save.get("snapshot", {}) as Dictionary
	).duplicate(true)
	var restored: RefCounted = WORLD.new()
	var replayed_starts: Array[Dictionary] = []
	restored.connect(
		"resident_activity_started",
		func(_resident_id: String, event: Dictionary) -> void:
			replayed_starts.append(event.duplicate(true))
	)
	var restore := restored.call(
		"restore_from_snapshot",
		data,
		opening,
		snapshot,
	) as Dictionary
	_expect_equal(restore.get("ok"), true, "active reservation restores")
	_expect_equal(
		replayed_starts.size(),
		0,
		"restore does not replay activity started event",
	)
	var historical_snapshot := snapshot.duplicate(true)
	var historical_activity_runtime := (
		(historical_snapshot.get("state", {}) as Dictionary).get(
			"activityRuntime",
			{},
		) as Dictionary
	)
	historical_activity_runtime["sourceFingerprint"] = (
		SAVE_SCHEMA_REGISTRY.ACTIVITY_SOURCE_FINGERPRINT_BEFORE_PUBLIC_DINING_SLOT_REWORK
	)
	var historical_place_service_states := (
		(historical_snapshot.get("state", {}) as Dictionary).get(
			"placeServiceStates",
			{},
		) as Dictionary
	)
	(
		historical_place_service_states.get("公共食堂", {}) as Dictionary
	)["service_capacity"] = 2
	var historical_execution := {
		"idempotencyKey": "resident_su_tang_01|legacy-dining-prep|prepare-dough|0",
		"payloadFingerprint": "legacy-dining-prep-payload",
		"residentId": "resident_su_tang_01",
		"actionId": "activity-legacy-dining-prep",
		"sourceContract": "agent.activity",
		"sourceActionId": "legacy-dining-prep",
		"activityId": "activity_baker_prepare_dough",
		"activityLabel": "准备面团",
		"placeId": "公共食堂",
		"role": "worker",
		"slotId": "slot_baker_prepare_dough_01",
		"memberAnchorId": "member_baker_prepare_dough_01",
		"targetType": "prop",
		"targetPropName": "公共食堂备餐柜",
		"targetActionVerb": "准备面团",
		"reason": "旧版食堂活动迁移测试",
		"reservationGeneration": 1,
		"reservationRevision": 1,
		"remainingTicks": 0,
		"effectCommit": true,
		"committedEffects": {"energy": -2},
		"status": "completed",
	}
	(historical_activity_runtime.get("executions", []) as Array).append(
		historical_execution,
	)
	var historical_serving_execution := {
		"idempotencyKey": "resident_su_tang_01|legacy-dining-serve|serve-meal|0",
		"payloadFingerprint": "legacy-dining-serve-payload",
		"residentId": "resident_su_tang_01",
		"actionId": "activity-legacy-dining-serve",
		"sourceContract": "agent.activity",
		"sourceActionId": "legacy-dining-serve",
		"activityId": "activity_dining_serve_meal",
		"activityLabel": "把备好的饭菜递给顾客",
		"placeId": "公共食堂",
		"role": "worker",
		"slotId": "slot_dining_serve_meal_01",
		"memberAnchorId": "member_dining_serve_meal_01",
		"targetType": "prop",
		"targetPropName": "公共食堂备餐柜",
		"targetActionVerb": "取餐",
		"reason": "旧版食堂递餐活动迁移测试",
		"reservationGeneration": 1,
		"reservationRevision": 1,
		"remainingTicks": 0,
		"effectCommit": true,
		"committedEffects": {"energy": -1},
		"status": "completed",
	}
	(historical_activity_runtime.get("executions", []) as Array).append(
		historical_serving_execution,
	)
	var migrated_world: RefCounted = WORLD.new()
	var migrated_restore := migrated_world.call(
		"restore_from_snapshot",
		data,
		opening,
		historical_snapshot,
	) as Dictionary
	_expect_equal(
		migrated_restore.get("ok"),
		true,
		"registered old activity target migration restores a historical save",
	)
	var migrated_save := migrated_world.call("create_save_snapshot") as Dictionary
	var migrated_snapshot_state := (
		(migrated_save.get("snapshot", {}) as Dictionary).get(
			"state",
			{},
		) as Dictionary
	)
	var migrated_activity_state := migrated_snapshot_state.get(
		"activityRuntime",
		{},
	) as Dictionary
	_expect_equal(
		migrated_activity_state.get("sourceFingerprint"),
		String(
			(data.get("activityIntegrationReceipt", {}) as Dictionary).get(
				"sourceFingerprint",
				"",
			)
		),
		"migrated activity save is rewritten to the current source fingerprint",
	)
	var migrated_dough_target := ""
	var migrated_serving_target := ""
	for execution_value: Variant in migrated_activity_state.get(
		"executions",
		[],
	) as Array:
		var execution := execution_value as Dictionary
		if String(execution.get("slotId", "")) == "slot_baker_prepare_dough_01":
			migrated_dough_target = String(execution.get("targetPropName", ""))
		if String(execution.get("slotId", "")) == "slot_dining_serve_meal_01":
			migrated_serving_target = String(execution.get("targetPropName", ""))
	_expect_equal(
		migrated_dough_target,
		"公共食堂面团操作台",
		"migrated activity execution uses the current dough station target",
	)
	_expect_equal(
		migrated_serving_target,
		"公共食堂递餐口",
		"migrated activity execution uses the current serving target",
	)
	var migrated_service_capacity := -1
	for service_value: Variant in (
		migrated_snapshot_state.get("placeServiceStates", {}) as Dictionary
	).values():
		var service := service_value as Dictionary
		if String(service.get("place_id", "")) == "公共食堂":
			migrated_service_capacity = int(service.get("service_capacity", -1))
	_expect_equal(
		migrated_service_capacity,
		4,
		"migrated dining service state uses the current service capacity",
	)
	var current_activity_source := String(
		(data.get("activityIntegrationReceipt", {}) as Dictionary).get(
			"sourceFingerprint",
			"",
		)
	)
	var historical_in_progress_execution := historical_execution.duplicate(true)
	historical_in_progress_execution["status"] = "executing"
	var legacy_action_migration := SAVE_SCHEMA_REGISTRY.migrate_world_state(
		{
			"activityRuntime": {
				"sourceFingerprint": (
					SAVE_SCHEMA_REGISTRY
					.ACTIVITY_SOURCE_FINGERPRINT_BEFORE_PUBLIC_DINING_SLOT_REWORK
				),
				"executions": [historical_in_progress_execution],
			},
			"residents": [
				{
					"residentId": "resident_su_tang_01",
					"currentAction": {
						"action_id": "activity-legacy-dining-prep",
						"sourceContract": "agent.activity",
						"sourceActionId": "legacy-dining-prep",
						"prop": "公共食堂备餐柜",
						"verb": "准备面团",
					},
				},
			],
		},
		current_activity_source,
	)
	var migrated_legacy_action_state := (
		legacy_action_migration.get("state", {}) as Dictionary
	)
	var migrated_legacy_action := (
		(
			(migrated_legacy_action_state.get("residents", []) as Array)[0]
			as Dictionary
		).get("currentAction", {}) as Dictionary
	)
	_expect_equal(
		migrated_legacy_action.get("prop"),
		"公共食堂面团操作台",
		"migrated in-progress resident action uses the current dough station",
	)
	_expect_equal(
		migrated_legacy_action.get("verb"),
		"准备面团",
		"migrated in-progress resident action preserves the dough action",
	)
	var direct_activity_action_migration := SAVE_SCHEMA_REGISTRY.migrate_world_state(
		{
			"activityRuntime": {
				"sourceFingerprint": (
					SAVE_SCHEMA_REGISTRY
					.ACTIVITY_SOURCE_FINGERPRINT_BEFORE_PUBLIC_DINING_SLOT_REWORK
				),
				"executions": [
					{
						"residentId": "resident_su_tang_01",
						"actionId": "activity-direct-dining-prep",
						"sourceContract": "activity.perform",
						"sourceActionId": "",
						"activityId": "activity_baker_prepare_dough",
						"slotId": "slot_baker_prepare_dough_01",
						"targetType": "prop",
						"targetPropName": "公共食堂备餐柜",
						"targetActionVerb": "准备面团",
						"status": "executing",
					},
				],
			},
			"residents": [
				{
					"residentId": "resident_su_tang_01",
					"currentAction": {
						"action_id": "activity-direct-dining-prep",
						"sourceContract": "activity.perform",
						"sourceActionId": "",
						"prop": "公共食堂备餐柜",
						"verb": "准备面团",
					},
				},
			],
		},
		current_activity_source,
	)
	var direct_activity_action := (
		(
			(direct_activity_action_migration.get("state", {}) as Dictionary)
			.get("residents", []) as Array
		)[0] as Dictionary
		).get("currentAction", {}) as Dictionary
	_expect_equal(
		direct_activity_action.get("prop"),
		"公共食堂面团操作台",
		"direct activity.perform migration uses the current dough station",
	)
	var completed_collision_migration := SAVE_SCHEMA_REGISTRY.migrate_world_state(
		{
			"activityRuntime": {
				"sourceFingerprint": (
					SAVE_SCHEMA_REGISTRY
					.ACTIVITY_SOURCE_FINGERPRINT_BEFORE_PUBLIC_DINING_SLOT_REWORK
				),
				"executions": [historical_execution.duplicate(true)],
			},
			"residents": [
				{
					"residentId": "resident_su_tang_01",
					"currentAction": {
						"action_id": "activity-legacy-dining-prep",
						"sourceContract": "agent.activity",
						"sourceActionId": "legacy-dining-prep",
						"prop": "公共食堂备餐柜",
						"verb": "准备面团",
					},
				},
			],
		},
		current_activity_source,
	)
	var completed_collision_action := (
		(
			(completed_collision_migration.get("state", {}) as Dictionary)
			.get("residents", []) as Array
		)[0] as Dictionary
		).get("currentAction", {}) as Dictionary
	_expect_equal(
		completed_collision_action.get("prop"),
		"公共食堂备餐柜",
		"completed activity execution does not rewrite a resident action",
	)
	var beta2_compatibility_migration := SAVE_SCHEMA_REGISTRY.migrate_world_state(
		{
			"activityRuntime": {
				"sourceFingerprint": (
					SAVE_SCHEMA_REGISTRY
					.ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_SLOT_REWORK
				),
				"executions": [],
			},
			"residents": [],
		},
		current_activity_source,
	)
	_expect_equal(
		(
			(beta2_compatibility_migration.get("state", {}) as Dictionary)
			.get("activityRuntime", {}) as Dictionary
		).get("sourceFingerprint"),
		current_activity_source,
		"beta.2 save advances through the current dining routine compatibility node",
	)
	_expect_equal(
		(beta2_compatibility_migration.get("applied", []) as Array).has(
			"2026-08-12-public-dining-day-routine"
		),
		true,
		"beta.2 save records the dining routine compatibility migration",
	)
	var active_legacy_snapshot := snapshot.duplicate(true)
	var active_legacy_state := active_legacy_snapshot.get("state", {}) as Dictionary
	var active_legacy_runtime := (
		active_legacy_state.get("activityRuntime", {}) as Dictionary
	)
	var active_legacy_execution := (
		active_legacy_runtime.get("executions", []) as Array
	)[0] as Dictionary
	var active_legacy_reservation := (
		active_legacy_runtime.get("reservations", []) as Array
	)[0] as Dictionary
	var active_legacy_catalog: RefCounted = ACTIVITY_RUNTIME.new()
	_expect_ok(
		active_legacy_catalog.call("configure", data) as Dictionary,
		"旧版进行中食堂活动迁移测试数据可编译",
	)
	var legacy_member_anchor_id := "member_baker_prepare_dough_01"
	var legacy_reservation_key := String(active_legacy_catalog.call(
		"_reservation_key",
		"slot_baker_prepare_dough_01",
		legacy_member_anchor_id,
	))
	active_legacy_execution["sourceContract"] = "agent.activity"
	active_legacy_execution["sourceActionId"] = "legacy-active-dining-prep"
	active_legacy_execution["activityId"] = "activity_baker_prepare_dough"
	active_legacy_execution["activityLabel"] = "准备面团"
	active_legacy_execution["placeId"] = "公共食堂"
	active_legacy_execution["role"] = "worker"
	active_legacy_execution["slotId"] = "slot_baker_prepare_dough_01"
	active_legacy_execution["memberAnchorId"] = legacy_member_anchor_id
	active_legacy_execution["targetType"] = "prop"
	active_legacy_execution["targetPropName"] = "公共食堂备餐柜"
	active_legacy_execution["targetActionVerb"] = "准备面团"
	active_legacy_execution["status"] = "executing"
	active_legacy_execution["effectCommit"] = false
	active_legacy_execution["committedEffects"] = {}
	active_legacy_reservation["reservationKey"] = legacy_reservation_key
	active_legacy_reservation["residentId"] = resident_id
	active_legacy_reservation["idempotencyKey"] = active_legacy_execution.get(
		"idempotencyKey",
	)
	active_legacy_reservation["slotId"] = "slot_baker_prepare_dough_01"
	active_legacy_reservation["memberAnchorId"] = legacy_member_anchor_id
	var active_legacy_resident := _saved_resident(
		active_legacy_state,
		resident_id,
	)
	active_legacy_resident["currentPlace"] = "公共食堂"
	active_legacy_resident["spaceId"] = "indoor_dining_hall"
	active_legacy_resident["regionId"] = "region_portal_dining_hall_entry"
	active_legacy_resident["position"] = _encoded_vector2(Vector2(680, 376))
	active_legacy_resident["routeConnector"] = []
	var active_legacy_action := (
		active_legacy_resident.get("currentAction", {}) as Dictionary
	)
	active_legacy_action["sourceContract"] = "agent.activity"
	active_legacy_action["sourceActionId"] = "legacy-active-dining-prep"
	active_legacy_action["sourcePlace"] = "公共食堂"
	active_legacy_action["prop"] = "公共食堂备餐柜"
	active_legacy_action["verb"] = "准备面团"
	active_legacy_action["action_id"] = active_legacy_execution.get("actionId")
	active_legacy_action["pathPoints"] = [_encoded_vector2(Vector2(680, 376))]
	active_legacy_action["targetPosition"] = _encoded_vector2(Vector2(680, 376))
	active_legacy_action["returnRouteConnector"] = []
	active_legacy_resident["currentAction"] = active_legacy_action
	active_legacy_runtime["sourceFingerprint"] = (
		SAVE_SCHEMA_REGISTRY.ACTIVITY_SOURCE_FINGERPRINT_BEFORE_PUBLIC_DINING_SLOT_REWORK
	)
	var active_legacy_world: RefCounted = WORLD.new()
	var active_legacy_restore := active_legacy_world.call(
		"restore_from_snapshot",
		data,
		opening,
		active_legacy_snapshot,
	) as Dictionary
	_expect_equal(
		active_legacy_restore.get("ok"),
		true,
		"旧版进行中的食堂活动可以在迁移动作后恢复",
	)
	var active_legacy_migrated_state := (
		(active_legacy_world.call("create_save_snapshot") as Dictionary)
		.get("snapshot", {}) as Dictionary
	).get("state", {}) as Dictionary
	var active_legacy_migrated_action := (
		_saved_resident(active_legacy_migrated_state, resident_id)
		.get("currentAction", {}) as Dictionary
	)
	_expect_equal(
		active_legacy_migrated_action.get("prop"),
		"公共食堂面团操作台",
		"恢复进行中的旧版活动会同步更新居民当前道具",
	)
	_expect_equal(
		active_legacy_migrated_action.get("verb"),
		"准备面团",
		"恢复进行中的旧版活动会保留居民当前动作",
	)
	_expect_equal(
		(
			_decoded_vector2(active_legacy_migrated_action.get("targetPosition"))
		).is_equal_approx(Vector2(680, 472)),
		true,
		"恢复进行中的旧版活动会重建到新目标的路线终点",
	)
	var direct_active_legacy_snapshot := active_legacy_snapshot.duplicate(true)
	var direct_active_legacy_state := (
		direct_active_legacy_snapshot.get("state", {}) as Dictionary
	)
	var direct_active_legacy_runtime := (
		direct_active_legacy_state.get("activityRuntime", {}) as Dictionary
	)
	var direct_active_legacy_execution := (
		direct_active_legacy_runtime.get("executions", []) as Array
	)[0] as Dictionary
	direct_active_legacy_execution["sourceContract"] = "activity.perform"
	direct_active_legacy_execution["sourceActionId"] = ""
	var direct_active_legacy_resident := _saved_resident(
		direct_active_legacy_state,
		resident_id,
	)
	var direct_active_legacy_action := (
		direct_active_legacy_resident.get("currentAction", {}) as Dictionary
	)
	direct_active_legacy_action["sourceContract"] = "activity.perform"
	direct_active_legacy_action["sourceActionId"] = ""
	var direct_active_legacy_world: RefCounted = WORLD.new()
	var direct_active_legacy_restore := direct_active_legacy_world.call(
		"restore_from_snapshot",
		data,
		opening,
		direct_active_legacy_snapshot,
	) as Dictionary
	_expect_equal(
		direct_active_legacy_restore.get("ok"),
		true,
		"直接 activity.perform 来源的旧版活动可以恢复",
	)
	var direct_active_legacy_migrated_state := (
		(direct_active_legacy_world.call("create_save_snapshot") as Dictionary)
		.get("snapshot", {}) as Dictionary
	).get("state", {}) as Dictionary
	var direct_active_legacy_migrated_action := (
		_saved_resident(direct_active_legacy_migrated_state, resident_id)
		.get("currentAction", {}) as Dictionary
	)
	_expect_equal(
		direct_active_legacy_migrated_action.get("prop"),
		"公共食堂面团操作台",
		"直接 activity.perform 来源会同步更新居民当前道具",
	)
	_expect_equal(
		(
			_decoded_vector2(
				direct_active_legacy_migrated_action.get("targetPosition")
			)
		).is_equal_approx(Vector2(680, 472)),
		true,
		"直接 activity.perform 来源会重建到新目标的路线终点",
	)
	direct_active_legacy_world.call("stop")
	active_legacy_world.call("stop")
	migrated_world.call("stop")
	var drifted := snapshot.duplicate(true)
	(
		(drifted.get("state", {}) as Dictionary).get(
			"activityRuntime",
			{},
		) as Dictionary
	)["sourceFingerprint"] = "drifted"
	var drifted_executions := (
		(drifted.get("state", {}) as Dictionary).get(
			"activityRuntime",
			{},
		) as Dictionary
	).get("executions", []) as Array
	var first_drifted_execution := drifted_executions[0] as Dictionary
	var original_target_type := String(
		first_drifted_execution.get("targetType", ""),
	)
	var migrated_target_type := (
		"point"
		if original_target_type == "prop"
		else "prop"
	)
	first_drifted_execution["targetType"] = (
		migrated_target_type
	)
	var drifted_world: RefCounted = WORLD.new()
	var drifted_restore := drifted_world.call(
		"restore_from_snapshot",
		data,
		opening,
		drifted,
	) as Dictionary
	_expect_equal(
		drifted_restore.get("ok"),
		true,
		"compatible activity data growth migrates an older source fingerprint",
	)
	var migrated_snapshot := (
		(drifted_world.call("create_save_snapshot") as Dictionary).get(
			"snapshot",
			{},
		) as Dictionary
	)
	_expect_equal(
		(
			(migrated_snapshot.get("state", {}) as Dictionary).get(
				"activityRuntime",
				{},
			) as Dictionary
		).get("sourceFingerprint"),
		String(
			(data.get("activityIntegrationReceipt", {}) as Dictionary).get(
				"sourceFingerprint",
				"",
			)
		),
		"prepared activity state adopts the current compiled fingerprint",
	)
	var migrated_executions := (
		(migrated_snapshot.get("state", {}) as Dictionary).get(
			"activityRuntime",
			{},
		) as Dictionary
	).get("executions", []) as Array
	_expect_equal(
		String((migrated_executions[0] as Dictionary).get("targetType", "")),
		original_target_type,
		"prepared activity execution adopts the current carrier type",
	)
	_expect_equal(
		String((migrated_executions[0] as Dictionary).get("targetType", ""))
		== migrated_target_type,
		false,
		"migrated snapshot does not retain the stale carrier type",
	)
	var mismatched_link := snapshot.duplicate(true)
	var mismatched_runtime := (
		(mismatched_link.get("state", {}) as Dictionary).get(
			"activityRuntime",
			{},
		) as Dictionary
	)
	(
		(mismatched_runtime.get("reservations", []) as Array)[0]
		as Dictionary
	)["residentId"] = "resident_other"
	_expect_equal(
		(
			WORLD.new().call(
				"restore_from_snapshot",
				data,
				opening,
				mismatched_link,
			) as Dictionary
		).get("ok"),
		false,
		"reservation and execution resident cross-link must match exactly",
	)
	var orphan := snapshot.duplicate(true)
	var orphan_runtime := (
		(orphan.get("state", {}) as Dictionary).get(
			"activityRuntime",
			{},
		) as Dictionary
	)
	(orphan_runtime.get("executions", []) as Array).clear()
	_expect_equal(
		(
			WORLD.new().call(
				"restore_from_snapshot",
				data,
				opening,
				orphan,
			) as Dictionary
		).get("ok"),
		false,
		"orphan reservation is rejected",
	)
	var legacy_active_world: RefCounted = WORLD.new()
	legacy_active_world.call("start", data, opening)
	_submit_legacy_prop_decision(
		legacy_active_world,
		resident_id,
		"legacy-save-source",
		"图书馆借还书柜台",
		"借还书",
	)
	var legacy_active_save := (
		legacy_active_world.call("create_save_snapshot") as Dictionary
	).get("snapshot", {}) as Dictionary
	var legacy_active_state := (
		legacy_active_save.get("state", {}) as Dictionary
	)
	var legacy_saved_resident := _saved_resident(
		legacy_active_state,
		resident_id,
	)
	var legacy_saved_action := (
		legacy_saved_resident.get("currentAction", {}) as Dictionary
	)
	var legacy_saved_execution := (
		(
			legacy_active_state.get("activityRuntime", {}) as Dictionary
		).get("executions", []) as Array
	)[0] as Dictionary
	_expect_equal(
		legacy_saved_action.get("sourceActionId"),
		"legacy-save-source",
		"active legacy save preserves the original action identity internally",
	)
	_expect_equal(
		legacy_saved_execution.get("sourceContract"),
		"legacy.agent.use_prop",
		"activity execution persists the exact legacy source contract",
	)
	_expect_equal(
		(
			WORLD.new().call(
				"restore_from_snapshot",
				data,
				opening,
				legacy_active_save,
			) as Dictionary
		).get("ok"),
		true,
		"matching legacy source metadata restores",
	)
	var mismatched_source := legacy_active_save.duplicate(true)
	var mismatched_source_state := (
		mismatched_source.get("state", {}) as Dictionary
	)
	(
		_saved_resident(
			mismatched_source_state,
			resident_id,
		).get("currentAction", {}) as Dictionary
	)["sourceActionId"] = "drifted-source-action"
	_expect_equal(
		(
			WORLD.new().call(
				"restore_from_snapshot",
				data,
				opening,
				mismatched_source,
			) as Dictionary
		).get("ok"),
		false,
		"restore rejects currentAction and execution sourceActionId drift",
	)
	var invalid_source_contract := legacy_active_save.duplicate(true)
	var invalid_source_execution := (
		(
			(
				invalid_source_contract.get("state", {}) as Dictionary
			).get("activityRuntime", {}) as Dictionary
		).get("executions", []) as Array
	)[0] as Dictionary
	invalid_source_execution["sourceContract"] = "legacy.invalid"
	_expect_equal(
		(
			WORLD.new().call(
				"restore_from_snapshot",
				data,
				opening,
				invalid_source_contract,
			) as Dictionary
		).get("ok"),
		false,
		"restore rejects unknown persisted activity source contracts",
	)
	var missing_source_field := legacy_active_save.duplicate(true)
	var missing_source_resident := _saved_resident(
		missing_source_field.get("state", {}) as Dictionary,
		resident_id,
	)
	(
		missing_source_resident.get("currentAction", {}) as Dictionary
	).erase("sourceContract")
	_expect_equal(
		(
			WORLD.new().call(
				"restore_from_snapshot",
				data,
				opening,
				missing_source_field,
			) as Dictionary
		).get("ok"),
		false,
		"restore rejects missing exact activity source fields",
	)
	var idle_world: RefCounted = WORLD.new()
	idle_world.call("start", data, opening)
	var idle_save := idle_world.call("create_save_snapshot") as Dictionary
	var out_of_range := (
		idle_save.get("snapshot", {}) as Dictionary
	).duplicate(true)
	var out_of_range_state := (
		out_of_range.get("state", {}) as Dictionary
	)
	(
		(
			(out_of_range_state.get("residents", []) as Array)[0]
			as Dictionary
		).get("activityState", {}) as Dictionary
	)["energy"] = 101
	_expect_equal(
		(
			WORLD.new().call(
				"restore_from_snapshot",
				data,
				opening,
				out_of_range,
			) as Dictionary
		).get("ok"),
		false,
		"new save rejects activityState values outside 0..100",
	)
	var legacy := (
		idle_save.get("snapshot", {}) as Dictionary
	).duplicate(true)
	var legacy_state := legacy.get("state", {}) as Dictionary
	legacy_state.erase("activityRuntime")
	for resident_value: Variant in legacy_state.get("residents", []) as Array:
		(resident_value as Dictionary).erase("activityState")
	var legacy_world: RefCounted = WORLD.new()
	_expect_equal(
		(
			legacy_world.call(
				"restore_from_snapshot",
				data,
				opening,
				legacy,
			) as Dictionary
		).get("ok"),
		true,
		"old v2 save without activityRuntime migrates to neutral state",
	)
	_expect_equal(
		(
			(
				legacy_world.call(
					"get_resident_state",
					resident_id,
				) as Dictionary
			).get("activityNeeds", {}) as Dictionary
		).get("energy"),
		50,
		"old v2 save without activity fields restores the neutral compatibility default",
	)



func _verify_world_weather_execution(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var weather_opening := opening.duplicate(true)
	var residents := weather_opening.get("residents", []) as Array
	var botanist := residents[0] as Dictionary
	botanist["socialState"] = {
		"home": "北街一号住宅",
		"job": "植物学家",
		"workplace": "社区花园",
	}
	botanist["worldState"] = {
		"place": "社区花园",
		"spaceId": "town_outdoor",
		"regionId": "outdoor_garden_01",
		"position": [3396, 2772],
		"doing": "在社区花园查看花圃",
		"body": {
			"困": "不困",
			"饿": "不饿",
			"累": "不累",
		},
	}
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, weather_opening) as Dictionary).get("ok"),
		true,
		"weather execution world starts",
	)
	var resident_id := String(botanist.get("residentId", ""))
	_expect_equal(
		(
			world.call(
				"create_work_task",
				{
					"taskId": "runtime_botanist_observation_001",
					"capability": "research.observe",
					"sourceKind": "season_change",
					"sourceRef": "runtime_garden_season_change_001",
					"targets": [{
						"kind": "region",
						"ref": "outdoor_garden_01",
					}],
					"requestedResultKind": "research_record",
					"priority": 50,
				},
			) as Dictionary
		).get("ok"),
		true,
		"a confirmed season change creates actual field observation work",
	)
	var sunny_query := world.call(
		"query_activity_options",
		resident_id,
	) as Dictionary
	_expect_equal(
		_activity_option(
			sunny_query.get("options", []) as Array,
			"activity_botanist_observe_plants",
		).get("available"),
		true,
		"World keeps a reachable outdoor activity available in clear weather",
	)
	var started := world.call(
		"perform_activity_step",
		resident_id,
		"plan_weather_outdoor",
		1,
		_activity_step(
			"step_weather_outdoor",
			"activity_botanist_observe_plants",
			"社区花园",
			"slot_botanist_observe_plants_01",
		),
	) as Dictionary
	_expect_equal(
		started.get("ok"),
		true,
		"outdoor activity starts before weather becomes unsafe",
	)
	_expect_equal(
		(world.call("set_weather", "雷暴") as Dictionary).get("changed"),
		true,
		"thunderstorm changes the confirmed World weather",
	)
	var interrupted_state := world.call(
		"get_resident_state",
		resident_id,
	) as Dictionary
	var interrupted_action: Variant = interrupted_state.get("currentAction")
	_expect(
		interrupted_action == null
		or (
			interrupted_action is Dictionary
			and (interrupted_action as Dictionary).is_empty()
		),
		"unsafe confirmed weather interrupts an executing outdoor activity",
	)
	_expect(
		String(interrupted_state.get("doing", "")).contains("雷暴"),
		"weather interruption remains a readable World fact",
	)
	var storm_query := world.call(
		"query_activity_options",
		resident_id,
	) as Dictionary
	var storm_option := _activity_option(
		storm_query.get("options", []) as Array,
		"activity_botanist_observe_plants",
	)
	_expect_equal(
		storm_option.get("available"),
		false,
		"World reachability cannot reopen a weather-rejected activity",
	)
	_expect_equal(
		storm_option.get("disabledReason"),
		"ACTIVITY_WEATHER_UNSAFE",
		"World preserves the weather rejection reason after reachability checks",
	)



func _submit_legacy_prop_decision(
	world: RefCounted,
	resident_id: String,
	action_id: String,
	prop_name: String,
	action_verb: String,
) -> Dictionary:
	var requests := world.call(
		"take_pending_decision_requests_by_ids",
		[resident_id],
	) as Array
	_expect_equal(
		requests.size(),
		1,
		"legacy adapter receives one pending decision for %s" % resident_id,
	)
	if requests.is_empty():
		return {}
	var wake := (
		(requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
	)
	return world.call(
		"submit_agent_decision_by_id",
		resident_id,
		{
			"decision_id": String(wake.get("decision_id", "")),
			"handling": "replace_current",
			"action": {
				"action_id": action_id,
				"type": "用道具",
				"prop": prop_name,
				"verb": action_verb,
				"line": "执行明确的道具活动。",
			},
		},
	) as Dictionary



func _wake_has_prop_verb(
	wake: Dictionary,
	prop_name: String,
	action_verb: String,
) -> bool:
	var place := (
		(wake.get("snapshot", {}) as Dictionary).get(
			"place",
			{},
		) as Dictionary
	)
	for prop_value: Variant in place.get("props", []) as Array:
		var prop := prop_value as Dictionary
		if (
			String(prop.get("name", "")) == prop_name
			and (prop.get("verbs", []) as Array).has(action_verb)
		):
			return true
	return false



func _activity_runtime_save_state(world: RefCounted) -> Dictionary:
	var runtime_value: Variant = world.get("_activity_runtime")
	if not runtime_value is RefCounted:
		return {}
	return (runtime_value as RefCounted).call(
		"create_save_snapshot"
	) as Dictionary



func _decoded_world_save_state(world: RefCounted) -> Dictionary:
	var save := world.call("create_save_snapshot") as Dictionary
	var encoded := (
		(save.get("snapshot", {}) as Dictionary).get(
			"state",
			{},
		) as Dictionary
	)
	var decoded := SAVE_CODEC.decode_checked(encoded) as Dictionary
	return (
		decoded.get("value", {}) as Dictionary
	).duplicate(true)



func _activity_step(
	step_id: String,
	activity_id: String,
	place_id: String,
	preferred_slot_id := "",
) -> Dictionary:
	var target := {
		"activityId": activity_id,
		"placeId": place_id,
	}
	if not preferred_slot_id.is_empty():
		target["preferredSlotId"] = preferred_slot_id
	return {
		"stepId": step_id,
		"operation": "activity.perform",
		"target": target,
		"params": {},
	}



func _saved_resident(state: Dictionary, resident_id: String) -> Dictionary:
	for value: Variant in state.get("residents", []) as Array:
		var resident := value as Dictionary
		if String(resident.get("residentId", "")) == resident_id:
			return resident
	return {}


func _encoded_vector2(point: Vector2) -> Dictionary:
	return SAVE_CODEC.encode_checked(point).get("value", {}) as Dictionary


func _decoded_vector2(value: Variant) -> Vector2:
	var decoded := SAVE_CODEC.decode_checked(value) as Dictionary
	return decoded.get("value", Vector2.ZERO) as Vector2



func _activity_option(options: Array, activity_id: String) -> Dictionary:
	for value: Variant in options:
		var option := value as Dictionary
		if String(option.get("activityId", "")) == activity_id:
			return option
	return {}



func _action_result_count(
	wake: Dictionary,
	action_id: String,
	status: String,
) -> int:
	return _result_count(
		wake.get("action_results", []) as Array,
		action_id,
		status,
	)



func _saved_action_result_count(
	state: Dictionary,
	resident_id: String,
	action_id: String,
	status: String,
) -> int:
	var resident := _saved_resident(state, resident_id)
	return _result_count(
		resident.get("pendingActionResults", []) as Array,
		action_id,
		status,
	)



func _result_count(
	results: Array,
	action_id: String,
	status: String,
) -> int:
	var count := 0
	for value: Variant in results:
		var result := value as Dictionary
		if (
			String(result.get("action_id", "")) == action_id
			and String(result.get("status", "")) == status
		):
			count += 1
	return count



func _on_activity_started(
	_resident_id: String,
	event: Dictionary,
) -> void:
	_started_events.append(event.duplicate(true))



func _on_activity_completed(
	_resident_id: String,
	event: Dictionary,
) -> void:
	_completed_events.append(event.duplicate(true))



func _on_activity_interrupted(
	_resident_id: String,
	event: Dictionary,
) -> void:
	_interrupted_events.append(event.duplicate(true))


func _on_resident_reaction(
	_resident_name: String,
	reaction: Dictionary,
) -> void:
	_resident_reactions.append(reaction.duplicate(true))



func _expect_exact_keys(
	value: Dictionary,
	expected: Array,
	message: String,
) -> void:
	var actual := value.keys()
	actual.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	_expect_equal(actual, sorted_expected, message)



func _scenario_activity_routine() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect_equal(opening_result.get("ok"), true, "活动过程开局数据可加载")
	if opening_result.get("ok") != true:
		return
	var opening := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	_verify_all_workplaces(data, opening)
	_verify_dining_prep_schedule()
	_verify_dining_departure_awareness(data, opening)
	_verify_meal_sequence(data, opening)
	_verify_meal_period_boundary_consumption(data, opening)
	_verify_dining_capacity_agent_reaction(data, opening)
	_verify_active_meal_routine_save(data, opening)
	_verify_meal_presentation_progress(data, opening)
	_verify_active_routine_save_restore(data, opening)
	return


func _verify_dining_prep_schedule() -> void:
	var schedule_document := _read_json(SCHEDULE_PATH)
	var activity_document := _read_json(ACTIVITY_PATH)
	for activity_value: Variant in activity_document.get("activities", []) as Array:
		var activity := activity_value as Dictionary
		if String(activity.get("activityId", "")) != "activity_dining_prepare_meal":
			continue
		_expect(
			int(activity.get("durationMinutes", 0)) <= 30,
			"统一备餐不会占用食堂负责人过长的生活时间",
		)
		break
	var dining_schedule: Dictionary = {}
	for value: Variant in schedule_document.get("scheduleTemplates", []) as Array:
		var schedule := value as Dictionary
		if String(schedule.get("scheduleTemplateId", "")) == "schedule_day_food_service":
			dining_schedule = schedule
			break
	var windows := dining_schedule.get("windows", []) as Array
	for service_start_value: Variant in [360, 660, 1020]:
		var service_start := int(service_start_value)
		var has_prep_window := false
		for window_value: Variant in windows:
			var window := window_value as Dictionary
			var tags := window.get("activityTagsAny", []) as Array
			if (
				"food.prepare" in tags
				and int(window.get("startMinute", 0)) <= service_start - 60
				and int(window.get("endMinute", 0)) >= service_start
			):
				has_prep_window = true
				break
		_expect(
			has_prep_window,
			"供餐 %02d:%02d 前至少有一小时备餐窗口" % [service_start / 60, service_start % 60],
		)


func _verify_all_workplaces(data: Dictionary, opening: Dictionary) -> void:
	var world: RefCounted = WORLD.new()
	world.connect("resident_activity_started", _on_activity_started_activity_routine)
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"多地点工作活动 World 可启动",
	)
	for case_value: Variant in WORK_CASES:
		var case := case_value as Dictionary
		var resident_name := String(case.get("resident", ""))
		var resident_id := String(case.get("residentId", ""))
		_started_by_resident[resident_id] = []
		_expect(
			_move_to_place(
				world,
				resident_name,
				String(case.get("place", "")),
			),
			"%s 能到达工作地点" % resident_name,
		)
		_expect_equal(
			(
				world.call(
					"create_work_task",
					{
						"taskId": "routine_redecision_%s"
						% resident_id,
						"capability": String(
							case.get("capability", ""),
						),
						"sourceKind": String(
							case.get("sourceKind", ""),
						),
						"sourceRef": "routine_test_%s" % resident_id,
						"targets": [{
							"kind": "prop",
							"ref": String(case.get("prop", "")),
						}],
						"requestedResultKind": String(
							case.get("resultKind", ""),
						),
						"priority": 70,
					},
				) as Dictionary
			).get("ok"),
			true,
			"%s 有真实工作任务" % resident_name,
		)
		var wake := _take_wake_activity_routine(world, resident_name)
		var decision := _use_prop(
			wake,
			String(case.get("prop", "")),
			String(case.get("verb", "")),
			"开始忙这一阵的工作",
		)
		var source_action_id := String(
			(decision.get("action", {}) as Dictionary).get(
				"action_id",
				"",
			)
		)
		_expect_accepted(
			world.call(
				"submit_agent_decision",
				resident_name,
				decision,
			) as Dictionary,
			"%s 能开始通用工作过程" % resident_name,
		)
		var positions := {}
		_expect(
			_advance_routine_until_clear(
				world,
				resident_name,
				positions,
			),
			"%s 的工作过程能结束" % resident_name,
		)
		var activity_ids := _started_by_resident.get(
			resident_id,
			[],
		) as Array
		_expect_equal(
			activity_ids.size(),
			1,
			"%s 的一次决定只执行一个工作阶段，不由 World 自动续选"
			% resident_name,
		)
		_expect(
			positions.size() >= 1,
			"%s 这一工作阶段确实到达真实工作位置，实际为 %s"
			% [resident_name, positions.keys()],
		)
		var result_wake := _take_wake_activity_routine(world, resident_name)
		_expect_equal(
			_action_result_count_activity_routine(
				result_wake,
				source_action_id,
				"completed",
			),
			1,
			"%s 完成一个阶段后收到结果并重新决定" % resident_name,
		)
	world.call("stop")



func _verify_dining_departure_awareness(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"食堂出发前状态检查 World 可启动",
	)
	var work_domain := world.get("work_domain") as TownWorkDomainRuntime
	var first_day_breakfast := work_domain.meal_period_for_minute(570)
	_expect_equal(
		first_day_breakfast.get("id"),
		"breakfast",
		"首日早餐备好后仍保留实际发放时段",
	)
	_expect(
		int(first_day_breakfast.get("end", 0)) >= 600,
		"首日早餐不会在备好的一刻立即被午餐备餐覆盖",
	)
	_expect_equal(
		work_domain.meal_period_for_minute(600).get("id"),
		"lunch",
		"早餐发放结束后会及时进入午餐备餐",
	)
	var resident_name := "唐小满"
	var resident_id := "resident_tang_xiaoman_01"
	var wake := _take_wake_activity_routine(world, resident_name)
	var place := (
		(wake.get("snapshot", {}) as Dictionary).get("place", {}) as Dictionary
	)
	var dining := place.get("dining", {}) as Dictionary
	_expect_equal(
		dining.get("state"),
		"not_ready",
		"食堂尚未备好时，外面的居民也能看到真实状态",
	)
	_expect(
		not (place.get("destinations", []) as Array).has("公共食堂"),
		"餐食尚未备好时不会让外部居民为了吃饭白跑一趟",
	)
	var meal_task: Dictionary = {}
	for task_value: Variant in world.call(
		"get_work_tasks_for_resident",
		"resident_lu_qing_01",
	) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) == "food.production"
			and String(task.get("source_ref", "")).begins_with("meal-period:")
		):
			meal_task = task
			break
	_expect(
		int(meal_task.get("priority", 0)) >= 85,
		"当餐统一备餐达到可打断普通闲逛的优先级",
	)
	var next_step := meal_task.get("next_step", {}) as Dictionary
	_expect_equal(
		next_step.get("place_id"),
		"公共食堂",
		"备餐任务明确把食堂负责人引导到真实工作地点",
	)
	_expect(
		String(next_step.get("instruction", "")).contains("统一备餐")
		and String(next_step.get("instruction", "")).contains("菜单公告"),
		"备餐任务明确告诉 Agent 完成时限和菜单公告结果",
	)
	_expect(
		_prepare_meal_for_activity_test(world),
		"出发前状态检查会完成当前餐次备餐",
	)
	var place_services := (
		world.work_domain.place_services as TownPlaceServiceRuntime
	)
	var service_state := place_services.state("公共食堂")
	service_state["open"] = false
	service_state["owner_id"] = ""
	place_services.set_state("公共食堂", service_state)
	var resident := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {}) as Dictionary
	)
	_expect(
		(AGENT_WORLD_QUERY_RUNTIME.travel_destinations(world, resident) as Array).has(
			"公共食堂",
		),
		"统一备餐完成后即使厨师离岗，食堂也会重新成为可前往地点",
	)
	_expect(
		_move_to_place(world, resident_name, "公共食堂"),
		"餐食备好后厨师缺席也不妨碍居民进入自助取餐",
	)
	var collect_option := _activity_option(
		(world.call("query_activity_options", resident_id) as Dictionary).get(
			"options",
			[],
		) as Array,
		"activity_dining_collect_meal",
	)
	_expect_equal(
		collect_option.get("available"),
		true,
		"厨师缺席时备好的餐食仍可自行取用",
	)
	world.call("stop")


func _verify_meal_sequence(data: Dictionary, opening: Dictionary) -> void:
	var world: RefCounted = WORLD.new()
	world.connect("resident_activity_started", _on_activity_started_activity_routine)
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"吃饭活动过程 World 可启动",
	)
	var resident_name := "唐小满"
	var resident_id := "resident_tang_xiaoman_01"
	_started_by_resident[resident_id] = []
	_expect(
		_move_to_place(world, resident_name, "公共食堂"),
		"访客能到达公共食堂",
	)
	var before_meal_query := world.call(
		"query_activity_options",
		resident_id,
	) as Dictionary
	var collect_before_meal := _activity_option(
		before_meal_query.get("options", []) as Array,
		"activity_dining_collect_meal",
	)
	_expect(
		not collect_before_meal.is_empty()
		and collect_before_meal.get("available") == false,
		"公共食堂未完成当餐备餐前不能直接取餐",
	)
	_expect(
		_prepare_meal_for_activity_test(world),
		"完整用餐检查会先完成当前餐次备餐",
	)
	var menu_announced := false
	for announcement_value: Variant in world.call(
		"get_announcements",
	) as Array:
		if String((announcement_value as Dictionary).get("text", "")).contains(
			"菜单",
		):
			menu_announced = true
		break
	var work_domain := world.get("work_domain") as TownWorkDomainRuntime
	var menu_period := work_domain.meal_period_for_minute(
		int((world.get("_environment") as RefCounted).call("get_absolute_minute")),
	)
	var menu_document := JSON.parse_string(FileAccess.get_file_as_string(
		"res://world/data/town/source/meal_menus.json",
	)) as Dictionary
	var configured_menu := String(
		(menu_document.get("menus", {}) as Dictionary).get(
			String(menu_period.get("id", "")),
			"",
		)
	)
	var menu_text_matches_data := false
	for announcement_value: Variant in world.call(
		"get_announcements",
	) as Array:
		if String((announcement_value as Dictionary).get("text", "")).contains(
			configured_menu,
		):
			menu_text_matches_data = true
			break
	_expect(
		menu_announced and menu_text_matches_data,
		"当餐备餐计划会发布来自菜单数据的公告",
	)
	var satiety_before_meal := int(
		(
			(world.call("get_resident_state", resident_id) as Dictionary).get(
				"activityNeeds",
				{},
			) as Dictionary
		).get("satiety", 0)
	)
	var wake := _take_wake_activity_routine(world, resident_name)
	var dining_context := (
		((wake.get("snapshot", {}) as Dictionary).get("place", {}) as Dictionary).get(
			"dining",
			{},
		) as Dictionary
	)
	_expect_equal(
		dining_context.get("serviceMode"),
		"self_service",
		"食堂状态明确告诉 Agent 这是统一备餐后的自助取餐",
	)
	_expect(
		String(dining_context.get("serviceRule", "")).contains("不需要等工作人员"),
		"Agent 不会把公共食堂误解成必须等人逐单递餐",
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			resident_name,
			_use_prop(
				wake,
				"公共食堂西侧餐桌",
				"吃饭",
				"坐下来吃顿饭",
			),
		) as Dictionary,
		"从餐桌发出的吃饭意图能开始完整过程",
	)
	world.call("_schedule_decision", resident_id, true, false, true)
	_expect_equal(
		(world.call(
			"take_pending_decision_requests_by_ids",
			[resident_id],
		) as Array).size(),
		0,
		"取餐、吃饭和还餐具的连续过程不会被普通或工作重判中途打断",
	)
	var positions := {}
	_expect(
		_advance_routine_until_clear(world, resident_name, positions),
		"吃饭过程能结束",
	)
	_expect_equal(
		_started_by_resident.get(resident_id, []) as Array,
		[
			"activity_dining_collect_meal",
			"activity_dining_eat_meal",
			"activity_dining_return_dishes",
		],
		"吃饭按取餐、就座吃饭、归还餐具三个必要阶段运行",
	)
	_expect(
		positions.size() >= 3,
		"吃饭过程至少经过三个不同位置，实际为 %s"
		% [positions.keys()],
	)
	var dining_request_found := false
	for request_value: Variant in (
		world.call("get_occupation_service_snapshot") as Dictionary
	).get("requests", []) as Array:
		if String((request_value as Dictionary).get("kind", "")) == "dining_order":
			dining_request_found = true
			break
	_expect(
		not dining_request_found,
		"公共食堂日常用餐不再按居民逐人创建点餐请求",
	)
	var satiety_after_meal := int(
		(
			(world.call("get_resident_state", resident_id) as Dictionary).get(
				"activityNeeds",
				{},
			) as Dictionary
		).get("satiety", 0)
	)
	_expect(
		satiety_after_meal > satiety_before_meal,
		"公共食堂用餐会真正补充居民饱腹度",
	)
	var meal_finished_at := int(
		(world.get("_environment") as RefCounted).call(
			"get_absolute_minute",
		)
	)
	var meal_period_ref := work_domain.meal_period_source_ref(meal_finished_at)
	var occupation_services := (
		world.get("work_domain") as TownWorkDomainRuntime
	).services as RefCounted
	_expect(
		bool(occupation_services.call(
			"has_dining_order_completed_for_resident_meal_period",
			resident_id,
			meal_period_ref,
		)),
		"完整吃完一餐会登记本餐次需求已经满足",
	)
	var after_meal_query := world.call(
		"query_activity_options",
		resident_id,
	) as Dictionary
	var collect_after_meal := _activity_option(
		after_meal_query.get("options", []) as Array,
		"activity_dining_collect_meal",
	)
	_expect_equal(
		collect_after_meal.get("disabledReason"),
		"DINING_MEAL_ALREADY_SERVED",
		"同一餐次吃完后不会再次取餐",
	)
	var leave_wake := _take_wake_activity_routine(world, resident_name)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			resident_name,
			_go_activity_routine(
				leave_wake,
				"市集",
				"吃好了，回去继续逛市集",
			),
		) as Dictionary,
		"吃完后居民能立刻离开食堂并恢复外部生活",
	)
	var leaving_action := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {})
		as Dictionary
	).get("currentAction", {}) as Dictionary
	_expect_equal(leaving_action.get("type"), "去", "吃完后的外出行动已经接入")
	_expect_equal(leaving_action.get("place"), "市集", "吃完后会前往外部生活地点")
	world.call("stop")


func _verify_meal_period_boundary_consumption(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var boundary_opening := opening.duplicate(true)
	(boundary_opening.get("environment", {}) as Dictionary)["clock"] = "10:00"
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, boundary_opening) as Dictionary).get("ok"),
		true,
		"跨餐次边界用餐检查 World 可启动",
	)
	var resident_id := "resident_tang_xiaoman_01"
	var work_domain := world.get("work_domain") as TownWorkDomainRuntime
	var breakfast_ref := work_domain.meal_period_source_ref(595)
	var lunch_ref := work_domain.meal_period_source_ref(600)
	var activity_routine_state := world.get("activity_routine_state") as TownActivityRoutineState
	activity_routine_state.records[resident_id] = {
		"group": "meal",
		"mealPeriodRef": breakfast_ref,
	}
	WORK_SETTLEMENT._record_facility_use_from_activity(
		world,
		resident_id,
		{
			"role": "visitor",
			"activityId": "activity_dining_eat_meal",
		},
	)
	var occupation_services := (
		world.get("work_domain") as TownWorkDomainRuntime
	).services as RefCounted
	_expect(
		bool(occupation_services.call(
			"has_dining_order_completed_for_resident_meal_period",
			resident_id,
			breakfast_ref,
		)),
		"跨到午餐时段完成早餐仍登记为早餐",
	)
	_expect(
		not bool(occupation_services.call(
			"has_dining_order_completed_for_resident_meal_period",
			resident_id,
			lunch_ref,
		)),
		"跨餐次完成早餐不会错误占用午餐",
	)
	world.call("stop")



func _verify_dining_capacity_agent_reaction(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	world.connect("resident_reaction_created", _on_resident_reaction)
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"食堂名额检查 World 可启动",
	)
	_expect(
		_prepare_meal_for_activity_test(world),
		"食堂名额检查会先完成当前餐次备餐",
	)
	var visitors := [
		{"name": "林岚", "id": "resident_lin_lan_01"},
		{"name": "唐小满", "id": "resident_tang_xiaoman_01"},
		{"name": "阿禾", "id": "resident_a_he_01"},
		{"name": "顾川", "id": "resident_gu_chuan_01"},
		{"name": "苏禾", "id": "resident_su_he_01"},
	]
	for index in 4:
		var visitor := visitors[index] as Dictionary
		var wake := _take_wake_activity_routine(
			world,
			String(visitor.get("name", "")),
		)
		_expect_accepted(
			world.call(
				"submit_agent_decision",
				String(visitor.get("name", "")),
				_go_activity_routine(
					wake,
					"公共食堂",
					"饿了，去公共食堂吃饭",
				),
			) as Dictionary,
			"前四名居民前往食堂时依次取得名额",
		)
	var resident_name := String((visitors[4] as Dictionary).get("name", ""))
	var resident_id := String((visitors[4] as Dictionary).get("id", ""))
	var now := int(
		(world.get("_environment") as RefCounted).call(
			"get_absolute_minute",
		)
	)
	var capacity := DINING_SERVICE.capacity_status(world, resident_id, now)
	_expect_equal(capacity.get("capacity"), 4, "公共食堂同时最多接待四人")
	_expect_equal(capacity.get("occupied"), 4, "四名在途居民已经占满食堂名额")
	_expect_equal(capacity.get("state"), "full", "四人同时前往后食堂如实报告满员")
	var wake := _take_wake_activity_routine(world, resident_name)
	var full_place := (
		(wake.get("snapshot", {}) as Dictionary).get("place", {}) as Dictionary
	)
	_expect_equal(
		(full_place.get("dining", {}) as Dictionary).get("state"),
		"full",
		"第五名居民出发前能看到食堂已经满员",
	)
	_expect(
		(full_place.get("destinations", []) as Array).has("公共食堂"),
		"满员时仍保留尝试入口，以便途中满员能进入 Agent 反应流程",
	)
	var full_decision := _go_activity_routine(
		wake,
		"公共食堂",
		"我饿了，去看看今天有没有位置",
	)
	var rejected := world.call(
		"submit_agent_decision",
		resident_name,
		full_decision,
	) as Dictionary
	_expect_equal(
		rejected.get("ok"),
		true,
		"满员是已处理的正常生活结果，不计作 Agent 网关错误",
	)
	_expect_equal(
		rejected.get("errorCode"),
		"DINING_HALL_FULL",
		"满员时第五名居民在进门前收到明确的可重试结果",
	)
	_expect(
		String((world.call(
			"get_resident_state",
			resident_id,
		) as Dictionary).get("currentPlace", "")) != "公共食堂",
		"满员居民不会先进入食堂再排队",
	)
	var full_wake := _take_wake_activity_routine(world, resident_name)
	var rejected_action_id := String(
		(full_decision.get("action", {}) as Dictionary).get("action_id", "")
	)
	_expect_equal(
		AGENT_CONTRACT.reaction_source_action_id(full_wake),
		rejected_action_id,
		"满员结果进入下一轮 Agent 的可回应动作结果",
	)
	var reaction_text := "满了，待会儿再来"
	_resident_reactions.clear()
	var reaction_decision := {
		"decision_id": String(full_wake.get("decision_id", "")),
		"handling": "replace_current",
		"reaction": {
			"source_action_id": rejected_action_id,
			"text": reaction_text,
		},
		"action": {
			"action_id": "%s-leave" % String(full_wake.get("decision_id", "")),
			"type": "待着",
			"line": "先离开取餐口，晚些时候再来",
		},
	}
	var reaction_result := world.call(
		"submit_agent_decision",
		resident_name,
		reaction_decision,
	) as Dictionary
	_expect_accepted(reaction_result, "Agent 能回应食堂满员结果")
	var wait_action := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {}) as Dictionary
	).get("currentAction", {}) as Dictionary
	_expect(
		int(wait_action.get("completeAbsoluteMinute", 0))
		- int(wait_action.get("startedAbsoluteMinute", 0)) <= 10,
		"满员时 Agent 选择等待也不会在食堂卡住太久",
	)
	var first_visitor := visitors[0] as Dictionary
	var first_name := String(first_visitor.get("name", ""))
	var first_id := String(first_visitor.get("id", ""))
	var first_resident := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(first_id, {})
		as Dictionary
	)
	var arrival_action := first_resident.get("currentAction", {}) as Dictionary
	GO_ACTION_ADVANCEMENT_RUNTIME.advance(
		world,
		first_id,
		first_resident,
		arrival_action,
		int(arrival_action.get("startedAbsoluteMinute", now))
		+ int(arrival_action.get("durationMinutes", 0)),
	)
	_expect_equal(
		first_resident.get("currentPlace"),
		"公共食堂",
		"取得名额的居民能正常进入食堂",
	)
	var leave_wake := _take_wake_activity_routine(world, first_name)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			first_name,
			_go_activity_routine(
				leave_wake,
				"中心广场",
				"先回到原来的生活",
			),
		) as Dictionary,
		"食堂中的居民可以离开并恢复外部生活",
	)
	var departure_action := first_resident.get("currentAction", {}) as Dictionary
	GO_ACTION_ADVANCEMENT_RUNTIME.advance(
		world,
		first_id,
		first_resident,
		departure_action,
		int(departure_action.get("startedAbsoluteMinute", now))
		+ int(departure_action.get("durationMinutes", 0)),
	)
	_expect_equal(
		first_resident.get("currentPlace"),
		"中心广场",
		"居民离开后确实回到外部地点",
	)
	now = int(
		(world.get("_environment") as RefCounted).call(
			"get_absolute_minute",
		)
	)
	var freed_capacity := DINING_SERVICE.capacity_status(world, resident_id, now)
	_expect_equal(freed_capacity.get("occupied"), 3, "有人离开后名额会释放")
	_expect_equal(freed_capacity.get("available"), 1, "有人离开后新居民可以进入")
	ACTION_SETTLEMENT_RUNTIME.interrupt(
		world, resident_id, "看到有位置，结束短暂等待",
	)
	var retry_wake := _take_wake_activity_routine(world, resident_name)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			resident_name,
			_go_activity_routine(
				retry_wake,
				"公共食堂",
				"现在有位置了，再去吃饭",
			),
		) as Dictionary,
		"有人离开后之前满员的居民可以重新前往食堂",
	)
	var reaction_was_created := false
	for reaction: Dictionary in _resident_reactions:
		if String(reaction.get("text", "")) == reaction_text:
			reaction_was_created = true
			break
	_expect(
		reaction_was_created,
		"满员气泡使用 Agent 自己提交的想法",
	)
	world.call("stop")


func _verify_active_meal_routine_save(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	world.connect(
		"resident_activity_started",
		_on_activity_started_activity_routine,
	)
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"用餐中途存档 World 可启动",
	)
	var resident_name := "唐小满"
	var resident_id := "resident_tang_xiaoman_01"
	_started_by_resident[resident_id] = []
	_expect(
		_move_to_place(world, resident_name, "公共食堂"),
		"用餐中途存档前居民能到达食堂",
	)
	_expect(
		_prepare_meal_for_activity_test(world),
		"用餐存档检查会先完成当前餐次备餐",
	)
	var wake := _take_wake_activity_routine(world, resident_name)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			resident_name,
			_use_prop(
				wake,
				"公共食堂西侧餐桌",
				"吃饭",
				"坐下来吃顿饭",
			),
		) as Dictionary,
		"用餐中途存档检查能开始吃饭过程",
	)
	var reached_second_stage := false
	for _minute in 180:
		if (
			_started_by_resident.get(resident_id, []) as Array
		).size() >= 2:
			reached_second_stage = true
			break
		if not _service_wait_request_id(world, resident_id).is_empty():
			if not _complete_pending_dining_service(world, resident_id):
				break
			continue
		world.call("advance", 1.0)
	_expect(reached_second_stage, "吃饭过程进入第二个活动阶段")
	if reached_second_stage:
		var prepared := world.call("prepare_save_candidate") as Dictionary
		_expect_equal(
			prepared.get("ok"),
			true,
			"吃饭第二阶段执行中可生成能回读的保存候选",
		)
	world.call("stop")



func _verify_meal_presentation_progress(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"室内活动表现检查 World 可启动",
	)
	var resident_name := "唐小满"
	var resident_id := "resident_tang_xiaoman_01"
	_expect(
		_move_to_place(world, resident_name, "公共食堂"),
		"室内活动表现检查前居民能到达食堂",
	)
	_expect(
		_prepare_meal_for_activity_test(world),
		"室内活动表现检查会先完成当前餐次备餐",
	)
	var actor_root := Node2D.new()
	actor_root.y_sort_enabled = true
	root.add_child(actor_root)
	var presentation := RESIDENT_PRESENTATION.new()
	root.add_child(presentation)
	_expect_equal(
		(
			presentation.call(
				"bind_world",
				world,
				actor_root,
				"town_outdoor",
				Vector2.ZERO,
			) as Dictionary
		).get("ok"),
		true,
		"居民表现层可绑定室内活动 World",
	)
	_expect_equal(
		(
			presentation.call(
				"set_observed_interior",
				"公共食堂",
				Vector2.ZERO,
			) as Dictionary
		).get("ok"),
		true,
		"居民表现层可聚焦公共食堂",
	)
	var body := presentation.call("get_body", resident_id) as Node
	_expect(body != null and body.visible, "食堂居民表现体可见")
	if body == null:
		presentation.call("unbind_world")
		presentation.free()
		actor_root.free()
		world.call("stop")
		return
	body.call("set_automatic_motion", false)
	var wake := _take_wake_activity_routine(world, resident_name)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			resident_name,
			_use_prop(
				wake,
				"公共食堂西侧餐桌",
				"吃饭",
				"坐下来吃顿饭",
			),
		) as Dictionary,
		"室内表现检查能开始吃饭过程",
	)
	var saw_approaching := false
	var saw_performing := false
	var saw_position_change := false
	var previous_world_position := (
		(world.call("get_resident_state", resident_name) as Dictionary)
		.get("position", Vector2.ZERO) as Vector2
	)
	var finished := false
	# 完整用餐包含取餐、走到餐桌、用餐和归还餐具。
	# 这里验收的是“接近阶段会继续推进”，不应把 60 游戏分钟
	# 当成整条演出的总时限。
	for _minute in 180:
		var before := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		if not _service_wait_request_id(world, resident_id).is_empty():
			_expect(
				_complete_pending_dining_service(world, resident_id),
				"室内吃饭过程能等到真实备餐和交付",
			)
			presentation.call("sync_from_world", true)
			continue
		var cue_value: Variant = before.get("activityCue")
		if cue_value is Dictionary:
			var phase := String(
				(cue_value as Dictionary).get("phase", "")
			)
			saw_approaching = saw_approaching or phase == "approaching"
			saw_performing = saw_performing or phase == "performing"
		world.call("advance", 1.0)
		presentation.call("sync_from_world", true)
		var after := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		var world_position := after.get(
			"position",
			Vector2.ZERO,
		) as Vector2
		saw_position_change = (
			saw_position_change
			or not world_position.is_equal_approx(previous_world_position)
		)
		previous_world_position = world_position
		var body_position := body.position as Vector2
		_expect(
			body_position.distance_to(world_position) <= 0.5,
			"室内居民表现跟上 World 位置，偏差为 %.2f"
			% body_position.distance_to(world_position),
		)
		if after.get("currentAction") == null:
			finished = true
			break
	_expect(saw_approaching, "室内活动出现接近道具阶段")
	_expect(saw_performing, "室内活动到位后切换到执行阶段")
	_expect(saw_position_change, "室内吃饭过程确实移动到不同道具")
	_expect(finished, "室内吃饭过程没有永久卡在接近道具阶段")
	presentation.call("unbind_world")
	presentation.free()
	actor_root.free()
	world.call("stop")



func _verify_active_routine_save_restore(
	data: Dictionary,
	opening: Dictionary,
) -> void:
	var world: RefCounted = WORLD.new()
	_expect_equal(
		(world.call("start", data, opening) as Dictionary).get("ok"),
		true,
		"活动过程存档 World 可启动",
	)
	_expect(
		_move_to_place(world, "阿禾", "花房咖啡馆"),
		"存档检查前咖啡师能到达工作地点",
	)
	_expect_equal(
		(
			world.call(
				"create_work_task",
				{
					"taskId": "routine_save_cafe_order",
					"capability": "cafe.order",
					"sourceKind": "customer_order",
					"sourceRef": "routine_save_probe",
					"targets": [{
						"kind": "prop",
						"ref": "花房咖啡馆咖啡机",
					}],
					"requestedResultKind": "order_handoff",
					"priority": 70,
				},
			) as Dictionary
		).get("ok"),
		true,
		"存档检查有真实咖啡订单任务",
	)
	var wake := _take_wake_activity_routine(world, "阿禾")
	var decision := _use_prop(
		wake,
		"花房咖啡馆咖啡机",
		"冲咖啡",
		"开始照看店里的工作",
	)
	var source_action_id := String(
		(decision.get("action", {}) as Dictionary).get("action_id", "")
	)
	_expect_accepted(
		world.call(
			"submit_agent_decision",
			"阿禾",
			decision,
		) as Dictionary,
		"可保存的工作过程能开始",
	)
	world.call("advance", 8.0)
	var prepared := world.call("prepare_save_candidate") as Dictionary
	_expect_equal(
		prepared.get("ok"),
		true,
		"工作过程执行中可生成能回读的保存候选",
	)
	var snapshot := (
		prepared.get("snapshot", {}) as Dictionary
	).duplicate(true)
	var routines := (
		(snapshot.get("state", {}) as Dictionary).get(
			"activityRoutines",
			{},
		) as Dictionary
	).get("routines", []) as Array
	_expect_equal(routines.size(), 1, "执行中的工作过程写入存档")
	if not routines.is_empty():
		var saved_routine := routines[0] as Dictionary
		_expect(
			saved_routine.get("visitedActivityIds") is Array
			and not (
				saved_routine.get("visitedActivityIds", []) as Array
			).is_empty(),
			"工作过程存档保留已做步骤，恢复后不会从头重复",
		)
		_expect_equal(
			typeof(saved_routine.get("choiceSeed")),
			TYPE_INT,
			"工作过程存档保留本次随机选择种子",
		)
	var restored: RefCounted = WORLD.new()
	_expect_equal(
		(
			restored.call(
				"restore_from_snapshot",
				data,
				opening,
				snapshot,
			) as Dictionary
		).get("ok"),
		true,
		"执行中的工作过程可恢复",
	)
	var positions := {}
	_expect(
		_advance_routine_until_clear(restored, "阿禾", positions),
		"恢复后的工作过程能继续到结束",
	)
	var result_wake := _take_wake_activity_routine(restored, "阿禾")
	_expect_equal(
		_action_result_count_activity_routine(
			result_wake,
			source_action_id,
			"completed",
		),
		1,
		"恢复后的完整过程只返回一次原始用道具结果",
	)
	var old_snapshot := snapshot.duplicate(true)
	var old_routines := (
		(old_snapshot.get("state", {}) as Dictionary).get(
			"activityRoutines",
			{},
		) as Dictionary
	).get("routines", []) as Array
	for routine_value: Variant in old_routines:
		var old_routine := routine_value as Dictionary
		old_routine.erase("visitedActivityIds")
		old_routine.erase("choiceSeed")
	var old_restored: RefCounted = WORLD.new()
	_expect_equal(
		(
			old_restored.call(
				"restore_from_snapshot",
				data,
				opening,
				old_snapshot,
			) as Dictionary
		).get("ok"),
		true,
		"旧工作过程存档可迁移，不因新增随机字段损坏",
	)
	world.call("stop")
	restored.call("stop")
	old_restored.call("stop")



func _move_to_place(
	world: RefCounted,
	resident_name: String,
	place: String,
) -> bool:
	var state := world.call(
		"get_resident_state",
		resident_name,
	) as Dictionary
	if String(state.get("currentPlace", "")) == place:
		return true
	var wake := _take_wake_activity_routine(world, resident_name)
	var accepted := world.call(
		"submit_agent_decision",
		resident_name,
		_go_activity_routine(wake, place, "去%s" % place),
	) as Dictionary
	if String(accepted.get("status", "")) != "accepted":
		_failures.append(
			"%s 前往%s未获接受：%s"
			% [resident_name, place, accepted]
		)
		return false
	if not _advance_until_action_clears(world, resident_name):
		return false
	state = world.call("get_resident_state", resident_name) as Dictionary
	return String(state.get("currentPlace", "")) == place



func _advance_routine_until_clear(
	world: RefCounted,
	resident_name: String,
	positions: Dictionary,
	maximum_minutes := 180,
) -> bool:
	for _minute in maximum_minutes:
		var state := world.call(
			"get_resident_state",
			resident_name,
		) as Dictionary
		if state.get("currentAction") == null:
			return true
		var service_request_id := _service_wait_request_id(
			world,
			resident_name,
		)
		if not service_request_id.is_empty():
			if not _complete_pending_dining_service(
				world,
				resident_name,
			):
				return false
			continue
		var cue_value: Variant = state.get("activityCue")
		if (
			cue_value is Dictionary
			and String(
				(cue_value as Dictionary).get("phase", "")
			) == "performing"
		):
			var position := state.get("position", Vector2.ZERO) as Vector2
			positions["%d,%d" % [roundi(position.x), roundi(position.y)]] = true
			_expect_equal(
				(cue_value as Dictionary).get("actionType"),
				"用道具",
				"%s 的活动过程持续提供用道具表现提示" % resident_name,
			)
			_expect(
				not String(
					(cue_value as Dictionary).get("actorFacing", "")
				).is_empty(),
				"%s 的活动过程持续提供朝向" % resident_name,
			)
		world.call("advance", 1.0)
	return false



func _service_wait_request_id(
	world: RefCounted,
	resident_ref: String,
) -> String:
	var resident_id := String(world.call("_resident_key", resident_ref))
	var resident := (
		((world.get("resident_registry") as TownResidentRegistry).records as Dictionary).get(resident_id, {})
		as Dictionary
	)
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return ""
	return String(action.get("serviceRequestId", ""))



func _complete_pending_dining_service(
	world: RefCounted,
	customer_id: String,
) -> bool:
	for _minute in 1440:
		if _service_wait_request_id(world, customer_id).is_empty():
			return true
		var activity_id := ""
		for task_value: Variant in world.call(
			"get_work_tasks_for_resident",
			"resident_lu_qing_01",
		) as Array:
			var task := task_value as Dictionary
			if String(task.get("source_kind", "")) != "meal_demand":
				continue
			match String(task.get("capability", "")):
				"food.production":
					activity_id = "activity_dining_prepare_meal"
				"food.service":
					activity_id = "activity_dining_serve_meal"
			if not activity_id.is_empty():
				break
		if activity_id.is_empty():
			world.call("advance", 1.0)
			continue
		if not _perform_dining_worker_activity(world, activity_id):
			return false
	return false


func _prepare_meal_for_activity_test(world: RefCounted) -> bool:
	var work_domain := world.get("work_domain") as TownWorkDomainRuntime
	for _minute in 1440:
		var now := int(
			(world.get("_environment") as RefCounted).call(
				"get_absolute_minute",
			)
		)
		var period := work_domain.meal_period_for_minute(now)
		if (
			not period.is_empty()
			and work_domain.meal_period_is_prepared(now)
			and work_domain.meal_service_is_open(now)
			and posmod(now, 1440) + 30 <= int(period.get("end", 0))
		):
			return true
		var day_start := now - posmod(now, 1440)
		if (
			period.is_empty()
			or now + 60 > day_start + int(period.get("end", 0))
		):
			world.call("advance", 1.0)
			continue
		for task_value: Variant in world.call(
			"get_work_tasks_for_resident",
			"resident_lu_qing_01",
		) as Array:
			var task := task_value as Dictionary
			if (
				String(task.get("source_kind", "")) == "meal_demand"
				and String(task.get("capability", "")) == "food.production"
			):
				if not _perform_dining_worker_activity(
					world,
					"activity_dining_prepare_meal",
				):
					return false
				break
		world.call("advance", 1.0)
	return false



func _perform_dining_worker_activity(
	world: RefCounted,
	activity_id: String,
) -> bool:
	_service_activity_sequence += 1
	var performed := world.call(
		"perform_activity_step",
		"resident_lu_qing_01",
		"meal-routine-service-%d" % _service_activity_sequence,
		0,
		{
			"stepId": "meal-service-step-%d" % _service_activity_sequence,
			"operation": "activity.perform",
			"target": {
				"activityId": activity_id,
				"placeId": "公共食堂",
			},
			"params": {"reason": "完成顾客正在等待的真实供餐任务"},
		},
	) as Dictionary
	if String(performed.get("errorCode", "")) == "ACTIVITY_REQUIRES_TRAVEL_STEP":
		if not _move_to_place(world, "陆青", "公共食堂"):
			return false
		_service_activity_sequence += 1
		performed = world.call(
			"perform_activity_step",
			"resident_lu_qing_01",
			"meal-routine-service-%d" % _service_activity_sequence,
			0,
			{
				"stepId": "meal-service-step-%d" % _service_activity_sequence,
				"operation": "activity.perform",
				"target": {
					"activityId": activity_id,
					"placeId": "公共食堂",
				},
				"params": {"reason": "完成顾客正在等待的真实供餐任务"},
			},
		) as Dictionary
	if performed.get("ok") != true:
		_failures.append("食堂真实服务活动无法开始：%s" % [performed])
		return false
	return _advance_until_action_clears(world, "陆青", 180)



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



func _take_wake_activity_routine(world: RefCounted, resident_name: String) -> Dictionary:
	var requests := world.call(
		"take_pending_decision_requests",
		[resident_name],
	) as Array[Dictionary]
	if requests.is_empty():
		_failures.append("缺少 %s 的决定请求" % resident_name)
		return {}
	return (
		(requests[0].get("wakePacket", {}) as Dictionary).duplicate(true)
	)



func _go_activity_routine(wake: Dictionary, place: String, line: String) -> Dictionary:
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



func _activity_decision(
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


func _unique_strings(values: Array) -> Array[String]:
	var seen := {}
	var result: Array[String] = []
	for value: Variant in values:
		var text := String(value)
		if seen.has(text):
			continue
		seen[text] = true
		result.append(text)
	return result



func _action_result_count_activity_routine(
	wake: Dictionary,
	action_id: String,
	status: String,
) -> int:
	var count := 0
	for value: Variant in wake.get("action_results", []) as Array:
		var result := value as Dictionary
		if (
			String(result.get("action_id", "")) == action_id
			and String(result.get("status", "")) == status
		):
			count += 1
	return count



func _on_activity_started_activity_routine(
	resident_id: String,
	event: Dictionary,
) -> void:
	var events := _started_by_resident.get(resident_id, []) as Array
	events.append(String(event.get("activityId", "")))
	_started_by_resident[resident_id] = events



func _expect_accepted(result: Dictionary, message: String) -> void:
	_expect_equal(
		result.get("status"),
		"accepted",
		"%s（%s）" % [message, result],
	)



func _scenario_activity_catalog_contract() -> void:
	var catalog := CATALOG.load_default() as Dictionary
	_expect_equal(catalog.get("ok"), true, "default activity catalog loads")
	if catalog.get("ok") != true:
		return
	_expect_equal(
		CATALOG.occupation_templates(catalog).size(),
		15,
		"catalog exposes the authored occupation candidates",
	)
	_expect_equal(
		CATALOG.activity_templates(catalog).size(),
		66,
		"catalog exposes the authored activity definitions",
	)
	_expect_equal(
		CATALOG.slot_templates(catalog).size(),
		89,
		"catalog exposes the authored prop slots",
	)
	_expect_equal(
		CATALOG.schedule_templates(catalog).size(),
		12,
		"catalog exposes the authoritative schedule templates",
	)
	_verify_structural_not_formal(catalog)
	_verify_source_fingerprint_determinism(catalog)
	_verify_agent_contract(catalog)
	_verify_runtime_availability_boundary(catalog)
	_verify_default_social_state_coverage(catalog)
	_verify_fail_closed_loading(catalog)
	_verify_legacy_boundary(catalog)
	_verify_identity_independence()
	_verify_deep_copy_boundary(catalog)
	return
func _verify_structural_not_formal(catalog: Dictionary) -> void:
	var status := CATALOG.validation_status(catalog) as Dictionary
	_expect_equal(
		status.get("structurallyValid"),
		true,
		"base schema and duplicate-id gate is closed",
	)
	_expect_equal(
		status.get("validated"),
		false,
		"static catalog is not formal runtime evidence",
	)
	_expect_equal(
		status.get("formalExecutable"),
		false,
		"Catalog still requires an exact Validator receipt",
	)
	_expect_equal(
		status.get("status"),
		"structural_only_unvalidated",
		"Catalog does not impersonate Validator evidence",
	)
	_expect(
		not CATALOG.formal_consumption_ready(catalog),
		"unvalidated catalog cannot serve Session, UI, or World",
	)
	_expect(
		CATALOG.occupations(catalog).is_empty()
		and CATALOG.activities(catalog).is_empty()
		and CATALOG.slots(catalog).is_empty(),
		"formal getters fail closed before validation",
	)
	var production_evidence := _production_validator_report(catalog)
	_expect_equal(
		CATALOG.authorize_formal_consumption(
			catalog,
			production_evidence,
		).get("ok"),
		true,
		"exact seven-document production evidence authorizes formal use",
	)



func _verify_source_fingerprint_determinism(catalog: Dictionary) -> void:
	var occupation_document := (
		catalog.get("occupationDocument", {}) as Dictionary
	)
	var activity_document := (
		catalog.get("activityDocument", {}) as Dictionary
	)
	var slot_document := catalog.get("slotDocument", {}) as Dictionary
	var places_document := catalog.get("placesDocument", {}) as Dictionary
	var props_document := catalog.get("propsDocument", {}) as Dictionary
	var indoor_document := (
		catalog.get("indoorAuthoringDocument", {}) as Dictionary
	)
	var schedule_document := (
		catalog.get("scheduleDocument", {}) as Dictionary
	)
	var fingerprint := String(catalog.get("sourceFingerprint", ""))
	_expect(not fingerprint.is_empty(), "catalog has a source fingerprint")
	_expect_equal(
		CATALOG.source_fingerprint(
			_reverse_dictionary_order(occupation_document),
			_reverse_dictionary_order(activity_document),
			_reverse_dictionary_order(slot_document),
			_reverse_dictionary_order(places_document),
			_reverse_dictionary_order(props_document),
			_reverse_dictionary_order(indoor_document),
			_reverse_dictionary_order(schedule_document),
		),
		fingerprint,
		"canonical fingerprint ignores Dictionary insertion order",
	)
	var changed := occupation_document.duplicate(true)
	(
		(changed.get("occupations", []) as Array)[0] as Dictionary
	)["label"] = "改变过的职业标签"
	_expect(
		CATALOG.source_fingerprint(
			changed,
			activity_document,
			slot_document,
			places_document,
			props_document,
			indoor_document,
			schedule_document,
		) != fingerprint,
		"source fingerprint changes with document content",
	)



func _verify_agent_contract(catalog: Dictionary) -> void:
	var contract := CATALOG.agent_contract(catalog) as Dictionary
	_expect_equal(
		contract.get("operation"),
		"activity.perform",
		"only one public activity operation is exposed",
	)
	_expect_equal(
		contract.get("requiredTargetFields"),
		EXPECTED_REQUIRED_TARGET_FIELDS,
		"required target fields are frozen",
	)
	_expect_equal(
		contract.get("optionalTargetFields"),
		EXPECTED_OPTIONAL_TARGET_FIELDS,
		"optional target fields are frozen",
	)
	_expect_equal(
		contract.get("optionalParamsFields"),
		EXPECTED_OPTIONAL_PARAMS_FIELDS,
		"optional params fields are frozen",
	)
	_expect_equal(
		contract.get("worldQueryFields"),
		EXPECTED_WORLD_QUERY_FIELDS,
		"WorldQuery fields are frozen",
	)
	_expect_equal(
		contract.get("errorCodes"),
		EXPECTED_ERROR_CODES,
		"public rejection codes are frozen",
	)
	_expect_equal(
		contract.get("idempotencyKeyFields"),
		EXPECTED_IDEMPOTENCY_KEY_FIELDS,
		"idempotency key structure is frozen",
	)
	for forbidden_field in FORBIDDEN_PUBLIC_FIELDS:
		_expect(
			not _contains_key_recursive(contract, forbidden_field),
			"agent contract does not expose %s" % forbidden_field,
		)



func _verify_runtime_availability_boundary(catalog: Dictionary) -> void:
	var templates := CATALOG.activity_option_templates(
		catalog,
		"公共食堂",
	) as Array
	_expect(not templates.is_empty(), "static activity templates are available")
	for template_value: Variant in templates:
		var template := template_value as Dictionary
		_expect_equal(
			_sorted_string_keys(template),
			_sorted_copy(EXPECTED_TEMPLATE_FIELDS),
			"static template never fabricates runtime availability",
		)
		_expect(not template.has("available"), "template has no available flag")
		_expect(
			not template.has("disabledReason"),
			"template has no disabled reason",
		)

	_expect(
		CATALOG.public_activity_options(
			catalog,
			"公共食堂",
		).is_empty(),
		"unvalidated catalog emits no public options",
	)
	var formal_fixture := _build_formal_fixture(catalog)
	var formal_catalog := formal_fixture.get("catalog", {}) as Dictionary
	var formal_report := formal_fixture.get("report", {}) as Dictionary
	_expect_equal(
		formal_report.get("validated"),
		true,
		"independent fixture is validated by the real Validator",
	)
	_expect_equal(
		formal_report.get("status"),
		"formal_executable",
		"independent fixture reaches the formal status",
	)
	formal_catalog = CATALOG.authorize_formal_consumption(
		formal_catalog,
		formal_report,
	)
	_expect_equal(
		formal_catalog.get("ok"),
		true,
		"exact Validator report authorizes its exact fixture documents",
	)
	_expect(
		CATALOG.formal_consumption_ready(formal_catalog),
		"authorized exact fixture is ready for formal consumption",
	)
	_verify_evidence_rejections(catalog, formal_fixture)
	var tampered_after_authorization := formal_catalog.duplicate(true)
	var authorized_occupations := (
		tampered_after_authorization.get(
			"occupationDocument",
			{},
		) as Dictionary
	)
	var authorized_first_occupation := (
		(authorized_occupations.get("occupations", []) as Array)[0]
		as Dictionary
	)
	authorized_first_occupation["label"] = "授权后篡改"
	_expect(
		not CATALOG.formal_consumption_ready(
			tampered_after_authorization
		),
		"source mutation invalidates formal readiness",
	)
	_expect(
		CATALOG.public_activity_options(
			formal_catalog,
			"公共食堂",
		).is_empty(),
		"no runtime availability means no public option",
	)

	var runtime_availability: Dictionary = {}
	for index in templates.size():
		var template := templates[index] as Dictionary
		var key := CATALOG.runtime_availability_key(
			"公共食堂",
			String(template.get("activityId", "")),
			String(template.get("role", "")),
		)
		runtime_availability[key] = {
			"available": index != 0,
			"disabledReason": (
				"" if index != 0 else "当前活动位已被占用"
			),
		}
	var options := CATALOG.public_activity_options(
		formal_catalog,
		"公共食堂",
		runtime_availability,
	) as Array
	_expect_equal(
		options.size(),
		templates.size(),
		"Runtime supplies every emitted availability result",
	)
	for option_value: Variant in options:
		var option := option_value as Dictionary
		_expect_equal(
			_sorted_string_keys(option),
			_sorted_copy(EXPECTED_WORLD_QUERY_FIELDS),
			"public option has only the frozen fields",
		)
		for forbidden_field in FORBIDDEN_PUBLIC_FIELDS:
			_expect(
				not _contains_key_recursive(option, forbidden_field),
				"public option does not leak %s" % forbidden_field,
			)



func _verify_default_social_state_coverage(catalog: Dictionary) -> void:
	var resident_catalog := _read_json(RESIDENT_CATALOG_PATH)
	var audit := CATALOG.audit_default_social_state(
		catalog,
		resident_catalog,
	) as Dictionary
	_expect_equal(audit.get("ok"), true, "all defaults are explicitly audited")
	_expect_equal(audit.get("actualCount"), 16, "16 resident defaults are read")
	_expect_equal(
		(audit.get("supported", []) as Array).size(),
		16,
		"all default combinations have an activity chain",
	)
	_expect_equal(
		(audit.get("gaps", []) as Array).size(),
		0,
		"no default combination remains an activity gap",
	)
	_expect(
		(audit.get("unregistered", []) as Array).is_empty(),
		"no default combination is silently omitted",
	)
	var supported_names := []
	for supported_value: Variant in audit.get("supported", []) as Array:
		supported_names.append(
			String((supported_value as Dictionary).get("occupationName", ""))
		)
	_expect("园艺师" in supported_names, "园艺师 has a formal activity chain")
	_expect("小镇管理者" in supported_names, "小镇管理者 has a formal activity chain")
	_expect("邮差" in supported_names, "邮差 has a formal activity chain")
	_expect("渔夫" in supported_names, "渔夫默认渔港组合 is formally executable")



func _verify_fail_closed_loading(catalog: Dictionary) -> void:
	var occupations := (
		catalog.get("occupationDocument", {}) as Dictionary
	).duplicate(true)
	var activities := (
		catalog.get("activityDocument", {}) as Dictionary
	).duplicate(true)
	var slots := (
		catalog.get("slotDocument", {}) as Dictionary
	).duplicate(true)
	var activity_items := activities.get("activities", []) as Array
	activity_items.append((activity_items[0] as Dictionary).duplicate(true))
	_expect_equal(
		CATALOG.from_documents(
			occupations,
			activities,
			slots,
			catalog.get("placesDocument", {}) as Dictionary,
			catalog.get("propsDocument", {}) as Dictionary,
			catalog.get("indoorAuthoringDocument", {}) as Dictionary,
			catalog.get("scheduleDocument", {}) as Dictionary,
		).get("ok"),
		false,
		"duplicate IDs fail closed instead of overwriting",
	)
	activities = (
		catalog.get("activityDocument", {}) as Dictionary
	).duplicate(true)
	activities["worldId"] = "other_world"
	_expect_equal(
		CATALOG.from_documents(
			occupations,
			activities,
			slots,
			catalog.get("placesDocument", {}) as Dictionary,
			catalog.get("propsDocument", {}) as Dictionary,
			catalog.get("indoorAuthoringDocument", {}) as Dictionary,
			catalog.get("scheduleDocument", {}) as Dictionary,
		).get("ok"),
		false,
		"worldId mismatch fails closed",
	)



func _verify_evidence_rejections(
	production_catalog: Dictionary,
	formal_fixture: Dictionary,
) -> void:
	var formal_catalog := formal_fixture.get("catalog", {}) as Dictionary
	var formal_report := formal_fixture.get("report", {}) as Dictionary
	var production_report := _production_validator_report(
		production_catalog
	)
	_expect_equal(
		CATALOG.authorize_formal_consumption(
			production_catalog,
			production_report,
		).get("ok"),
		true,
		"current production report authorizes its exact source documents",
	)
	var missing_fingerprint := formal_report.duplicate(true)
	missing_fingerprint.erase("sourceFingerprint")
	_expect_equal(
		CATALOG.authorize_formal_consumption(
			formal_catalog,
			missing_fingerprint,
		).get("ok"),
		false,
		"missing source fingerprint is rejected",
	)
	var wrong_fingerprint := formal_report.duplicate(true)
	wrong_fingerprint["sourceFingerprint"] = (
		"ffffffffffffffffffffffffffffffff"
		+ "ffffffffffffffffffffffffffffffff"
	)
	_expect_equal(
		CATALOG.authorize_formal_consumption(
			formal_catalog,
			wrong_fingerprint,
		).get("ok"),
		false,
		"wrong source fingerprint is rejected",
	)
	var mutated_source_catalog := formal_catalog.duplicate(true)
	var mutated_occupations := (
		mutated_source_catalog.get(
			"occupationDocument",
			{},
		) as Dictionary
	)
	var mutated_first_occupation := (
		(mutated_occupations.get("occupations", []) as Array)[0]
		as Dictionary
	)
	mutated_first_occupation["label"] = "授权后被篡改的职业标签"
	_expect_equal(
		CATALOG.authorize_formal_consumption(
			mutated_source_catalog,
			formal_report,
		).get("ok"),
		false,
		"cached fingerprint cannot authorize mutated source documents",
	)
	var mutated_places_catalog := formal_catalog.duplicate(true)
	var mutated_places := (
		mutated_places_catalog.get("placesDocument", {}) as Dictionary
	)
	var first_place := (
		(mutated_places.get("places", []) as Array)[0] as Dictionary
	)
	first_place["summary"] = "测试中被改写的地点"
	_expect_equal(
		CATALOG.authorize_formal_consumption(
			mutated_places_catalog,
			formal_report,
		).get("ok"),
		false,
		"a receipt for other places cannot authorize production data",
	)
	var mutated_schedule_catalog := formal_catalog.duplicate(true)
	var mutated_schedule := (
		mutated_schedule_catalog.get("scheduleDocument", {}) as Dictionary
	)
	var first_schedule := (
		(mutated_schedule.get("scheduleTemplates", []) as Array)[0]
		as Dictionary
	)
	first_schedule["label"] = "测试中被改写的日程"
	_expect_equal(
		CATALOG.authorize_formal_consumption(
			mutated_schedule_catalog,
			formal_report,
		).get("ok"),
		false,
		"a receipt for other schedules cannot authorize production data",
	)
	var handwritten_flags := {
		"sourceWorldId": "town",
		"sourceFingerprint": String(
			formal_catalog.get("sourceFingerprint", "")
		),
		"staticReferencesValidated": true,
		"activityChainVerified": true,
		"placeCapabilitiesVerified": true,
		"scheduleTemplatesResolved": true,
		"formalExecutable": true,
		"errors": [],
	}
	_expect_equal(
		CATALOG.authorize_formal_consumption(
			formal_catalog,
			handwritten_flags,
		).get("ok"),
		false,
		"handwritten booleans without Validator status are rejected",
	)



func _verify_legacy_boundary(catalog: Dictionary) -> void:
	_expect(
		CATALOG.resolve_unique_legacy_activity(
			catalog,
			"公共食堂",
			"公共食堂灶台",
			"做饭",
		).is_empty(),
		"unvalidated catalog cannot feed the legacy runtime adapter",
	)
	var exact_mapping := CATALOG.resolve_unique_legacy_activity_template(
		catalog,
		"公共食堂",
		"公共食堂灶台",
		"做饭",
	) as Dictionary
	_expect(not exact_mapping.is_empty(), "exact legacy template maps")
	_expect_equal(
		(exact_mapping.get("activity", {}) as Dictionary).get("activityId"),
		"activity_dining_prepare_meal",
		"legacy prop action does not invent extra plan steps",
	)
	_expect(
		CATALOG.resolve_unique_legacy_activity_template(
			catalog,
			"公共食堂",
			"公共食堂灶台",
			"上班",
		).is_empty(),
		"free-form work language is not parsed into an activity",
	)
	_expect(
		CATALOG.resolve_unique_legacy_activity_template(
			catalog,
			"独立市集",
			"市集入口",
			"进入",
		).is_empty(),
		"place entry never fabricates a work activity",
	)



func _verify_identity_independence() -> void:
	var source_text := FileAccess.get_file_as_string(OCCUPATION_PATH)
	var parsed := JSON.parse_string(source_text) as Dictionary
	for value: Variant in parsed.get("occupations", []) as Array:
		_expect(
			not (value as Dictionary).has("residentId"),
			"occupation definitions do not depend on resident identity",
		)



func _verify_deep_copy_boundary(catalog: Dictionary) -> void:
	var first_activity := CATALOG.activity_template(
		catalog,
		"activity_dining_prepare_meal",
	) as Dictionary
	first_activity["label"] = "被调用方修改"
	_expect_equal(
		CATALOG.activity_template(
			catalog,
			"activity_dining_prepare_meal",
		).get("label"),
		"准备饭菜",
		"activity lookup returns a deep copy",
	)
	var coverage := CATALOG.default_social_state_coverage(catalog)
	(coverage.get("activityChainSupported", []) as Array).clear()
	_expect_equal(
		(
			CATALOG.default_social_state_coverage(catalog).get(
				"activityChainSupported",
				[],
			) as Array
		).size(),
		16,
		"default social coverage is a detached deep copy",
	)



func _production_validator_report(catalog: Dictionary) -> Dictionary:
	return VALIDATOR.validate_with_status(
		catalog.get("occupationDocument", {}) as Dictionary,
		catalog.get("activityDocument", {}) as Dictionary,
		catalog.get("slotDocument", {}) as Dictionary,
		catalog.get("placesDocument", {}) as Dictionary,
		catalog.get("propsDocument", {}) as Dictionary,
		catalog.get("indoorAuthoringDocument", {}) as Dictionary,
		catalog.get("scheduleDocument", {}) as Dictionary,
	)



func _build_formal_fixture(production_catalog: Dictionary) -> Dictionary:
	var occupations := (
		production_catalog.get("occupationDocument", {}) as Dictionary
	).duplicate(true)
	var activities := (
		production_catalog.get("activityDocument", {}) as Dictionary
	).duplicate(true)
	var slots := (
		production_catalog.get("slotDocument", {}) as Dictionary
	).duplicate(true)
	var places := (
		production_catalog.get("placesDocument", {}) as Dictionary
	).duplicate(true)
	var props := (
		production_catalog.get("propsDocument", {}) as Dictionary
	).duplicate(true)
	var indoor := (
		production_catalog.get("indoorAuthoringDocument", {}) as Dictionary
	).duplicate(true)
	var schedule := (
		production_catalog.get("scheduleDocument", {}) as Dictionary
	).duplicate(true)

	var formal_catalog := CATALOG.from_documents(
		occupations,
		activities,
		slots,
		places,
		props,
		indoor,
		schedule,
	) as Dictionary
	var report := VALIDATOR.validate_with_status(
		occupations,
		activities,
		slots,
		places,
		props,
		indoor,
		schedule,
	) as Dictionary
	return {
		"catalog": formal_catalog,
		"report": report,
	}



func _reverse_dictionary_order(value: Variant) -> Variant:
	if value is Dictionary:
		var source := value as Dictionary
		var keys := []
		for key_value: Variant in source.keys():
			keys.append(String(key_value))
		keys.sort()
		keys.reverse()
		var result: Dictionary = {}
		for key: String in keys:
			result[key] = _reverse_dictionary_order(source[key])
		return result
	if value is Array:
		var result := []
		for item: Variant in value as Array:
			result.append(_reverse_dictionary_order(item))
		return result
	return value



func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	return parsed as Dictionary if parsed is Dictionary else {}



func _contains_key_recursive(value: Variant, key_name: String) -> bool:
	if value is Dictionary:
		for key_value: Variant in (value as Dictionary).keys():
			if String(key_value) == key_name:
				return true
			if _contains_key_recursive(
				(value as Dictionary)[key_value],
				key_name,
			):
				return true
	elif value is Array:
		for item: Variant in value as Array:
			if _contains_key_recursive(item, key_name):
				return true
	return false



func _sorted_string_keys(value: Dictionary) -> Array:
	var keys := []
	for key_value: Variant in value.keys():
		keys.append(String(key_value))
	keys.sort()
	return keys



func _sorted_copy(value: Array) -> Array:
	var result := value.duplicate()
	result.sort()
	return result



func _scenario_activity_validator() -> void:
	_occupation_document = _read_json(OCCUPATION_PATH_ACTIVITY_VALIDATOR)
	_activity_document = _read_json(ACTIVITY_PATH)
	_slot_document = _read_json(SLOT_PATH)
	_places_document = _read_json(PLACES_PATH)
	_props_document = _read_json(PROPS_PATH)
	_indoor_authoring_document = _read_json(INDOOR_AUTHORING_PATH)
	_schedule_document = _read_json(SCHEDULE_PATH)

	_verify_layered_baseline()
	_verify_duplicate_occupation_rejected()
	_verify_resident_identity_rejected()
	_verify_unknown_primary_workplace_rejected()
	_verify_unknown_related_workplace_rejected()
	_verify_unknown_fixed_work_area_rejected()
	_verify_incomplete_activity_chain_rejected()
	_verify_unknown_effect_key_rejected()
	_verify_duration_requires_positive_integer()
	_verify_service_result_contract_required()
	_verify_unknown_prop_reference_rejected()
	_verify_unknown_action_reference_rejected()
	_verify_unknown_anchor_reference_rejected()
	_verify_duplicate_member_coordinate_rejected()
	_verify_distinct_authored_member_anchors_supported()
	_verify_unauthored_member_anchor_rejected()
	_verify_fallback_requires_matching_role()
	_verify_missing_schedule_document_rejected()
	_verify_overlapping_schedule_windows_rejected()
	_verify_schedule_activity_tag_rejected()
	_verify_default_coverage_count_rejected()
	_verify_default_workplace_capability_rejected()
	_verify_place_service_profile_rejected()
	_verify_public_contract_leak_rejected()
	_verify_pose_family_is_presentation_only()
	return
func _verify_layered_baseline() -> void:
	var report := VALIDATOR.validate_with_status(
		_occupation_document,
		_activity_document,
		_slot_document,
		_places_document,
		_props_document,
		_indoor_authoring_document,
		_schedule_document,
	) as Dictionary
	if not bool(report.get("ok", false)):
		printerr(
			"TOWN_WORLD_ACTIVITY_VALIDATOR_DIAGNOSTIC: ",
			report.get("errors", []),
		)
	_expect_equal(report.get("ok"), true, "static references validate")
	_expect_equal(
		report.get("receiptVersion"),
		1,
		"Validator owns the receipt version",
	)
	_expect_equal(
		report.get("validator"),
		"TownWorldActivityValidator",
		"Validator owns its receipt identity",
	)
	_expect_equal(
		report.get("staticReferencesValidated"),
		true,
		"all authored prop slots pass current authoring references",
	)
	_expect_equal(
		report.get("activityChainVerified"),
		true,
		"occupation worker activity chains are statically present",
	)
	_expect_equal(
		report.get("placeCapabilitiesVerified"),
		true,
		"all professional place capabilities are independently authored",
	)
	_expect_equal(
		report.get("scheduleTemplatesResolved"),
		true,
		"all eight schedule ids resolve against the authoritative catalog",
	)
	_expect_equal(
		report.get("formalExecutable"),
		true,
		"the exact seven source documents are formally executable",
	)
	_expect_equal(
		report.get("validated"),
		true,
		"formal integration emits validated=true",
	)
	_expect_equal(
		report.get("status"),
		"formal_executable",
		"status exposes the completed static integration boundary",
	)
	var source_fingerprint := String(
		report.get("sourceFingerprint", "")
	)
	_expect(
		not source_fingerprint.is_empty(),
		"Validator report binds evidence to the source documents",
	)
	_expect_equal(
		source_fingerprint,
		VALIDATOR.source_fingerprint(
			_occupation_document,
			_activity_document,
			_slot_document,
			_places_document,
			_props_document,
			_indoor_authoring_document,
			_schedule_document,
		),
		"Validator report uses the canonical source fingerprint",
	)
	_expect_equal(
		(
			report.get(
				"pendingPlaceCapabilityOccupationIds",
				[],
			) as Array
		).size(),
		0,
		"all current occupations resolve authored place capabilities",
	)
	_expect_equal(
		(
			report.get(
				"unresolvedScheduleTemplateIds",
				[],
			) as Array
		).size(),
		0,
		"no referenced schedule template remains unresolved",
	)



func _verify_duplicate_occupation_rejected() -> void:
	var occupations := _occupation_document.duplicate(true)
	var items := occupations.get("occupations", []) as Array
	items.append((items[0] as Dictionary).duplicate(true))
	var errors := _validate(
		occupations,
		_activity_document,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "occupationId 重复"),
		"duplicate occupationId is rejected",
	)



func _verify_resident_identity_rejected() -> void:
	var occupations := _occupation_document.duplicate(true)
	var first := (
		(occupations.get("occupations", []) as Array)[0] as Dictionary
	)
	first["residentId"] = "resident_001"
	var errors := _validate(
		occupations,
		_activity_document,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "不得引用 residentId"),
		"occupation definitions cannot become identity records",
	)



func _verify_unknown_primary_workplace_rejected() -> void:
	var occupations := _occupation_document.duplicate(true)
	var first := (
		(occupations.get("occupations", []) as Array)[0] as Dictionary
	)
	first["primaryWorkplacePlace"] = "不存在的主要工作地"
	var errors := _validate(
		occupations,
		_activity_document,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "primaryWorkplacePlace 非法"),
		"occupation primary workplace must resolve to the real map",
	)



func _verify_unknown_related_workplace_rejected() -> void:
	var occupations := _occupation_document.duplicate(true)
	var first := (
		(occupations.get("occupations", []) as Array)[0] as Dictionary
	)
	first["relatedWorkplacePlaces"] = ["不存在的关联工作地"]
	var errors := _validate(
		occupations,
		_activity_document,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "relatedWorkplacePlaces 引用非法地点"),
		"occupation related workplaces must resolve to the real map",
	)



func _verify_unknown_fixed_work_area_rejected() -> void:
	var occupations := _occupation_document.duplicate(true)
	var grocer: Dictionary = {}
	for value: Variant in occupations.get("occupations", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("occupationId", ""))
				== "occupation_grocer"
		):
			grocer = value as Dictionary
			break
	_expect(not grocer.is_empty(), "baseline contains the grocer occupation")
	if grocer.is_empty():
		return
	grocer["fixedWorkAreaIds"] = ["slot_market_missing"]
	var errors := _validate(
		occupations,
		_activity_document,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "fixedWorkAreaIds 引用未知工作位"),
		"fixed market work areas must resolve to authored activity slots",
	)



func _verify_incomplete_activity_chain_rejected() -> void:
	var occupations := _occupation_document.duplicate(true)
	var first := (
		(occupations.get("occupations", []) as Array)[0] as Dictionary
	)
	first["allowedActivityTags"] = ["activity.tag.without_slot"]
	var errors := _validate(
		occupations,
		_activity_document,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "没有可验证的 worker activity chain"),
		"occupation requires an authored worker activity chain",
	)



func _verify_unknown_effect_key_rejected() -> void:
	var activities := _activity_document.duplicate(true)
	var first := (
		(activities.get("activities", []) as Array)[0] as Dictionary
	)
	(first.get("effects", {}) as Dictionary)["饥饿"] = 10
	var errors := _validate(
		_occupation_document,
		activities,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "非法状态键"),
		"localized text is rejected as a persisted effect key",
	)



func _verify_service_result_contract_required() -> void:
	var activities := _activity_document.duplicate(true)
	var service_activity: Dictionary = {}
	for value: Variant in activities.get("activities", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("kind", ""))
			== "service"
		):
			service_activity = value as Dictionary
			break
	_expect(
		not service_activity.is_empty(),
		"baseline contains a service activity",
	)
	if service_activity.is_empty():
		return
	service_activity.erase("resultContract")
	var errors := _validate(
		_occupation_document,
		activities,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "resultContract 必须为对象"),
		"service activities cannot complete from timing alone",
	)



func _verify_duration_requires_positive_integer() -> void:
	var activities := _activity_document.duplicate(true)
	var first := (
		(activities.get("activities", []) as Array)[0] as Dictionary
	)
	first["durationMinutes"] = "20"
	var errors := _validate(
		_occupation_document,
		activities,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "必须为正整数数值"),
		"numeric-looking strings are rejected as duration",
	)



func _verify_unknown_prop_reference_rejected() -> void:
	var slots := _slot_document.duplicate(true)
	var first := (slots.get("slots", []) as Array)[0] as Dictionary
	(first.get("target", {}) as Dictionary)["propName"] = "不存在的道具"
	var errors := _validate(
		_occupation_document,
		_activity_document,
		slots,
	)
	_expect(
		_errors_contain(errors, "引用未知道具"),
		"unknown prop reference is rejected",
	)



func _verify_unknown_action_reference_rejected() -> void:
	var slots := _slot_document.duplicate(true)
	var first := (slots.get("slots", []) as Array)[0] as Dictionary
	(first.get("target", {}) as Dictionary)["actionVerb"] = "不存在的动作"
	var errors := _validate(
		_occupation_document,
		_activity_document,
		slots,
	)
	_expect(
		_errors_contain(errors, "引用未知道具动作词"),
		"unknown prop action reference is rejected",
	)



func _verify_unknown_anchor_reference_rejected() -> void:
	var slots := _slot_document.duplicate(true)
	var first := (slots.get("slots", []) as Array)[0] as Dictionary
	(first.get("target", {}) as Dictionary)["anchorId"] = (
		"anchor_missing"
	)
	var errors := _validate(
		_occupation_document,
		_activity_document,
		slots,
	)
	_expect(
		_errors_contain(errors, "anchorId 与道具交互锚点不一致"),
		"unknown interaction anchor is rejected",
	)



func _verify_duplicate_member_coordinate_rejected() -> void:
	var slots := _slot_document.duplicate(true)
	var first := (slots.get("slots", []) as Array)[0] as Dictionary
	var target := first.get("target", {}) as Dictionary
	target.erase("anchorId")
	var members := first.get("memberAnchors", []) as Array
	var duplicate := (members[0] as Dictionary).duplicate(true)
	duplicate["memberAnchorId"] = "member_duplicate_coordinate"
	duplicate["anchorId"] = "barista_second"
	members.append(duplicate)
	var errors := _validate(
		_occupation_document,
		_activity_document,
		slots,
	)
	_expect(
		_errors_contain(errors, "共用同一坐标"),
		"one coordinate cannot represent multiple occupied members",
	)



func _verify_distinct_authored_member_anchors_supported() -> void:
	var slots := _slot_document.duplicate(true)
	var props := _props_document.duplicate(true)
	var indoor := _indoor_authoring_document.duplicate(true)
	(
		slots.get("memberAnchorContract", {}) as Dictionary
	)["maxAuthoredMembersPerSlot"] = 2
	var slot := _find_slot(slots, "slot_cafe_brew_coffee_01")
	var target := slot.get("target", {}) as Dictionary
	target.erase("anchorId")
	var members := slot.get("memberAnchors", []) as Array
	members.append({
		"memberAnchorId": "member_cafe_brew_coffee_02",
		"anchorId": "barista_use_second",
		"position": [400, 304],
	})
	var prop := _find_prop(props, "花房咖啡馆咖啡机")
	var interaction := prop.get("interaction", {}) as Dictionary
	interaction["memberAnchors"] = [
		{
			"anchorId": "barista_use_second",
			"position": [400, 304],
		},
	]
	var binding := _find_indoor_binding(
		indoor,
		"cafe",
		"花房咖啡馆咖啡机",
		"冲咖啡",
	)
	binding["memberAnchors"] = [
		{"anchorId": "barista_use_second"},
	]
	var errors := VALIDATOR.validate(
		_occupation_document,
		_activity_document,
		slots,
		_places_document,
		props,
		indoor,
		_schedule_document,
	)
	_expect(
		errors.is_empty(),
		"two distinct authored member anchors are independently valid",
	)



func _verify_unauthored_member_anchor_rejected() -> void:
	var slots := _slot_document.duplicate(true)
	var slot := _find_slot(slots, "slot_cafe_brew_coffee_01")
	var target := slot.get("target", {}) as Dictionary
	target.erase("anchorId")
	(slot.get("memberAnchors", []) as Array).append({
		"memberAnchorId": "member_cafe_brew_coffee_missing",
		"anchorId": "barista_missing",
		"position": [400, 304],
	})
	var errors := _validate(
		_occupation_document,
		_activity_document,
		slots,
	)
	_expect(
		_errors_contain(errors, "未匹配道具 authoring")
		and _errors_contain(errors, "未匹配室内 authoring"),
		"multi-member slots cannot invent un-authored anchors",
	)



func _verify_fallback_requires_matching_role() -> void:
	var slots := _slot_document.duplicate(true)
	var west := _find_slot(slots, "slot_dining_eat_west_01")
	var east := _find_slot(slots, "slot_dining_eat_east_01")
	west["role"] = "worker"
	east["fallback"] = "same_activity_other_slot"
	var errors := _validate(
		_occupation_document,
		_activity_document,
		slots,
	)
	_expect(
		_errors_contain(
			errors,
			"同地点、活动、role、targetType",
		),
		"fallback cannot cross from visitor to worker",
	)



func _verify_missing_schedule_document_rejected() -> void:
	var schedule := _schedule_document.duplicate(true)
	(schedule.get("scheduleTemplates", []) as Array).pop_back()
	var errors := _validate_with_schedule(schedule)
	_expect(
		_errors_contain(errors, "权威 schedule 目录必须精确覆盖"),
		"resolved flags cannot impersonate a missing schedule document",
	)



func _verify_overlapping_schedule_windows_rejected() -> void:
	var schedule := _schedule_document.duplicate(true)
	var template := (
		(schedule.get("scheduleTemplates", []) as Array)[0] as Dictionary
	)
	var windows := template.get("windows", []) as Array
	(windows[1] as Dictionary)["startMinute"] = 700
	var errors := _validate_with_schedule(schedule)
	_expect(
		_errors_contain(errors, "时段重叠或未按开始时间排序"),
		"schedule windows must be ordered and non-overlapping",
	)



func _verify_schedule_activity_tag_rejected() -> void:
	var schedule := _schedule_document.duplicate(true)
	var template := (
		(schedule.get("scheduleTemplates", []) as Array)[0] as Dictionary
	)
	var window := (
		(template.get("windows", []) as Array)[0] as Dictionary
	)
	window["activityTagsAny"] = ["care.nonexistent"]
	var errors := _validate_with_schedule(schedule)
	_expect(
		_errors_contain(errors, "没有 worker activity slot 的标签"),
		"schedule pressure cannot name an unauthored worker activity tag",
	)



func _verify_default_coverage_count_rejected() -> void:
	var occupations := _occupation_document.duplicate(true)
	var coverage := occupations.get(
		"defaultSocialStateCoverage",
		{},
	) as Dictionary
	(coverage.get("activityChainSupported", []) as Array).pop_back()
	var errors := _validate(
		occupations,
		_activity_document,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "supported + gaps"),
		"default social-state omissions are rejected",
	)



func _verify_default_workplace_capability_rejected() -> void:
	var places := _places_document.duplicate(true)
	for place_value: Variant in places.get("places", []) as Array:
		var place := place_value as Dictionary
		if String(place.get("name", "")) == "花房咖啡馆":
			(place.get("capabilities", {}) as Dictionary).erase(
				"drink.prepare"
			)
	var errors := VALIDATOR.validate(
		_occupation_document,
		_activity_document,
		_slot_document,
		places,
		_props_document,
		_indoor_authoring_document,
		_schedule_document,
	)
	_expect(
		_errors_contain(
			errors,
			"指定工作地缺少该职业所需 capability",
		),
		"default supported chain requires capability on the same workplace",
	)



func _verify_place_service_profile_rejected() -> void:
	var places := _places_document.duplicate(true)
	for place_value: Variant in places.get("places", []) as Array:
		var place := place_value as Dictionary
		if String(place.get("name", "")) != "花房咖啡馆":
			continue
		(
			place.get("serviceProfile", {}) as Dictionary
		)["helperActivityId"] = "activity_missing_helper"
	var errors := VALIDATOR.validate(
		_occupation_document,
		_activity_document,
		_slot_document,
		places,
		_props_document,
		_indoor_authoring_document,
		_schedule_document,
	)
	_expect(
		_errors_contain(
			errors,
			"引用未知 helperActivityId",
		),
		"地点服务来源不能引用并不存在的帮助活动",
	)



func _verify_public_contract_leak_rejected() -> void:
	var activities := _activity_document.duplicate(true)
	var contract := activities.get("agentContract", {}) as Dictionary
	var query_fields := contract.get("worldQueryFields", []) as Array
	query_fields.append("effects")
	query_fields.append("sourceFingerprint")
	query_fields.append("scheduleTemplateId")
	var errors := _validate(
		_occupation_document,
		activities,
		_slot_document,
	)
	_expect(
		_errors_contain(errors, "worldQueryFields 必须精确等于")
		and _errors_contain(errors, "Agent 公开字段不得包含 effects")
		and _errors_contain(
			errors,
			"Agent 公开字段不得包含 sourceFingerprint",
		)
		and _errors_contain(
			errors,
			"Agent 公开字段不得包含 scheduleTemplateId",
		),
		"public contract rejects World-internal evidence fields",
	)



func _verify_pose_family_is_presentation_only() -> void:
	var activities := _activity_document.duplicate(true)
	var slots := _slot_document.duplicate(true)
	var activity_id := "activity_dining_prepare_meal"
	var custom_pose := "future_kitchen_pose"
	var activity := _find_activity(activities, activity_id)
	activity["poseFamily"] = custom_pose
	for slot_value: Variant in slots.get("slots", []) as Array:
		var slot := slot_value as Dictionary
		if String(slot.get("activityId", "")) == activity_id:
			slot["poseFamily"] = custom_pose
	var errors := _validate(
		_occupation_document,
		activities,
		slots,
	)
	_expect(
		errors.is_empty(),
		"poseFamily remains a presentation hint, not a legality gate",
	)



func _validate(
	occupations: Dictionary,
	activities: Dictionary,
	slots: Dictionary,
) -> PackedStringArray:
	return VALIDATOR.validate(
		occupations,
		activities,
		slots,
		_places_document,
		_props_document,
		_indoor_authoring_document,
		_schedule_document,
	)



func _validate_with_schedule(schedule: Dictionary) -> PackedStringArray:
	return VALIDATOR.validate(
		_occupation_document,
		_activity_document,
		_slot_document,
		_places_document,
		_props_document,
		_indoor_authoring_document,
		schedule,
	)



func _find_activity(document: Dictionary, activity_id: String) -> Dictionary:
	for value: Variant in document.get("activities", []) as Array:
		var activity := value as Dictionary
		if String(activity.get("activityId", "")) == activity_id:
			return activity
	return {}



func _find_slot(document: Dictionary, slot_id: String) -> Dictionary:
	for value: Variant in document.get("slots", []) as Array:
		var slot := value as Dictionary
		if String(slot.get("slotId", "")) == slot_id:
			return slot
	return {}



func _find_prop(document: Dictionary, prop_name: String) -> Dictionary:
	for value: Variant in document.get("props", []) as Array:
		var prop := value as Dictionary
		if String(prop.get("name", "")) == prop_name:
			return prop
	return {}



func _find_indoor_binding(
	document: Dictionary,
	room_id: String,
	prop_name: String,
	verb: String,
) -> Dictionary:
	for room_value: Variant in document.get("rooms", []) as Array:
		var room := room_value as Dictionary
		if String(room.get("roomId", "")) != room_id:
			continue
		for value: Variant in room.get("props", []) as Array:
			var binding := value as Dictionary
			if String(binding.get("name", "")) != prop_name:
				continue
			if String(binding.get("verb", "")) == verb:
				return binding
			for action_value: Variant in binding.get("actions", []) as Array:
				if (
					action_value is Dictionary
					and String(
						(action_value as Dictionary).get("verb", "")
					) == verb
				):
					return binding
	return {}



func _errors_contain(errors: PackedStringArray, fragment: String) -> bool:
	for error in errors:
		if String(error).contains(fragment):
			return true
	return false



func _scenario_far_resident_activity_live_anchor() -> void:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	root.add_child(host)
	var provider := AnchorProvider.new()
	var layer := LAYER_SCENE.instantiate()
	host.add_child(layer)
	layer.bind_anchor_provider(provider)
	await process_frame

	_expect(layer.apply_view_model(_view_model(10, "middle")), "middle VM is accepted")
	await process_frame
	var first := layer.audit_snapshot() as Dictionary
	var first_slots := first.get("slots", []) as Array
	_expect_equal(
		first.get("visibleSlotCount"),
		3,
		"中景保留旁观入口、语义图标和无语义行动占位",
	)
	_expect_equal((first_slots[0] as Dictionary).get("kind"), "spectator_conversation", "conversation keeps priority")
	var middle_semantic := first_slots[1] as Dictionary
	_expect_equal(
		middle_semantic.get("kind"),
		"semantic_icon",
		"中景直接显示已确认的行动语义图标",
	)
	_expect(
		String(middle_semantic.get("iconPath", "")).ends_with(
			"walking.png"
		),
		"中景走路状态使用走路图标",
	)
	var compact_thought := first_slots[2] as Dictionary
	_expect_equal(
		compact_thought.get("kind"),
		"public_thought",
		"中景保留没有语义图标的居民公开想法",
	)
	_expect(
		not String(compact_thought.get("label", "")).is_empty(),
		"中景公开想法保留可读文字",
	)
	_expect(
		String(compact_thought.get("label", "")).ends_with("…"),
		"超宽的中景公开想法才收束",
	)
	var first_conversation_rect := (first_slots[0] as Dictionary).get("rect") as Rect2

	provider.anchors["resident-a"] = Vector2(800, 650)
	provider.anchors["resident-b"] = Vector2(1000, 650)
	await process_frame
	var moved := layer.audit_snapshot() as Dictionary
	var moved_rect := (
		((moved.get("slots", []) as Array)[0] as Dictionary).get("rect")
		as Rect2
	)
	_expect(
		moved_rect.position != first_conversation_rect.position,
		"active conversation follows the live midpoint between both residents",
	)
	provider.anchors["resident-a"] = Vector2(-200, 650)
	await process_frame
	var offscreen := layer.audit_snapshot() as Dictionary
	_expect(
		not bool(
			(((offscreen.get("slots", []) as Array)[0]) as Dictionary).get(
				"visible",
				true,
			)
		),
		"ordinary resident conversation hides when a participant leaves the viewport",
	)
	provider.anchors["resident-a"] = Vector2(800, 1000)
	await process_frame
	var behind_hud := layer.audit_snapshot() as Dictionary
	_expect(
		not bool(
			(((behind_hud.get("slots", []) as Array)[0]) as Dictionary).get(
				"visible",
				true,
			)
		),
		"resident bubble hides inside the HUD canvas but outside the visible playfield",
	)
	provider.anchors["resident-a"] = Vector2(800, 650)
	provider.hidden["resident-a"] = true
	await process_frame
	var wrong_space := layer.audit_snapshot() as Dictionary
	_expect(
		not bool(
			(((wrong_space.get("slots", []) as Array)[0]) as Dictionary).get(
				"visible",
				true,
			)
		),
		"cached conversation hides when a participant leaves the active space",
	)
	provider.hidden.erase("resident-a")

	_expect(layer.apply_view_model(_view_model(11, "far")), "far VM is accepted")
	await process_frame
	var far := layer.audit_snapshot() as Dictionary
	var far_slots := far.get("slots", []) as Array
	var far_semantic := far_slots[1] as Dictionary
	var far_thought := far_slots[2] as Dictionary
	_expect_equal(far_semantic.get("kind"), "semantic_icon", "far zoom renders a confirmed semantic icon")
	_expect(
		String(far_semantic.get("iconPath", "")).ends_with("walking.png"),
		"far walking state consumes the existing walking asset",
	)
	_expect_equal(
		far_semantic.get("semanticIconInsideActionShell"),
		true,
		"far semantic icon keeps the dedicated compact action frame",
	)
	_expect_equal(
		far_semantic.get("semanticIconHasNoEllipsisBase"),
		false,
		"far semantic icon does not lose its authored frame",
	)
	_expect_equal(
		far_semantic.get("semanticActionShellHasClearCenter"),
		true,
		"far semantic icon sits on a clear action shell without hidden dots",
	)
	_expect(
		String(far_semantic.get("skinPath", "")).ends_with(
			"activity_action_shell.png"
		),
		"far semantic icon consumes the dedicated action shell",
	)
	_expect_equal(far_thought.get("kind"), "public_thought_ellipsis", "far zoom renders ellipsis")
	_expect(
		String(far_thought.get("skinPath", "")).ends_with(
			"activity_ellipsis_shell.png"
		),
		"far zoom consumes the registered ellipsis asset",
	)
	var reaction_vm := _view_model(12, "far")
	var reaction_items := (
		((reaction_vm.get("data", {}) as Dictionary)
		.get("residentOverlays", {}) as Dictionary)
		.get("items", []) as Array
	)
	(reaction_items[0] as Dictionary)["thoughtKind"] = "activity_reaction"
	(reaction_items[0] as Dictionary)["thoughtLabel"] = "这顿吃得挺舒坦。"
	_expect(
		layer.apply_view_model(reaction_vm),
		"far completion reaction VM is accepted",
	)
	await process_frame
	var reaction_snapshot := layer.audit_snapshot() as Dictionary
	var reaction_slots := reaction_snapshot.get("slots", []) as Array
	var far_reaction := reaction_slots[1] as Dictionary
	_expect_equal(
		far_reaction.get("kind"),
		"semantic_icon",
		"far zoom keeps result reactions as icon-only map information",
	)
	_expect_equal(
		far_reaction.get("label"),
		"",
		"far zoom reserves the resident sentence for focused near views",
	)
	var reaction_head := far_reaction.get("headScreenAnchor") as Vector2
	var reaction_tail := far_reaction.get("tailTip") as Vector2
	_expect(
		reaction_head.distance_to(reaction_tail) <= 1.0,
		"authored thought-bubble pointer is attached to the live resident head",
	)
	_expect(
		absf(reaction_tail.x - reaction_head.x) <= 1.0,
		"off-centre thought-bubble pointer, not the frame centre, follows the head",
	)
	var social_observing_vm := _view_model(13, "far")
	var observing_far_items := (
		((social_observing_vm.get("data", {}) as Dictionary)
		.get("farResidentActivity", {}) as Dictionary)
		.get("items", []) as Array
	)
	var observing_semantic := observing_far_items[1] as Dictionary
	observing_semantic["iconType"] = "observing"
	observing_semantic["residentId"] = "resident-d"
	observing_semantic["residentName"] = "陆青"
	observing_far_items[1] = observing_semantic
	var observing_data := (
		social_observing_vm.get("data", {}) as Dictionary
	)
	var observing_far_activity := (
		observing_data.get("farResidentActivity", {}) as Dictionary
	)
	observing_far_activity["items"] = observing_far_items
	observing_data["farResidentActivity"] = observing_far_activity
	var observing_overlays := (
		(observing_data
		.get("residentOverlays", {}) as Dictionary)
		.get("items", []) as Array
	)
	var observing_overlay := observing_overlays[0] as Dictionary
	observing_overlay["thoughtKind"] = (
		"social_matter_observing"
	)
	observing_overlay["thoughtLabel"] = (
		"附近的小动物引起了关注"
	)
	observing_overlays[0] = observing_overlay
	var observing_resident_overlays := (
		observing_data.get("residentOverlays", {}) as Dictionary
	)
	observing_resident_overlays["items"] = observing_overlays
	observing_data["residentOverlays"] = observing_resident_overlays
	social_observing_vm["data"] = observing_data
	_expect(
		layer.apply_view_model(social_observing_vm),
		"far observing social VM is accepted",
	)
	await process_frame
	var observing_snapshot := layer.audit_snapshot() as Dictionary
	var observing_slots := observing_snapshot.get("slots", []) as Array
	_expect_equal(
		observing_snapshot.get("visibleSlotCount"),
		2,
		"far social matter renders its icon without a text bubble",
	)
	_expect_equal(
		(observing_slots[2] as Dictionary).get("visible"),
		false,
		"far social matter leaves the text bubble slot hidden",
	)
	_expect(
		String((observing_slots[1] as Dictionary).get(
			"iconPath",
			"",
		)).ends_with("observing.png"),
		"far observing matter consumes the approved observing icon",
	)
	var social_reading_vm := _view_model(14, "far")
	var reading_far_items := (
		((social_reading_vm.get("data", {}) as Dictionary)
		.get("farResidentActivity", {}) as Dictionary)
		.get("items", []) as Array
	)
	var reading_semantic := reading_far_items[1] as Dictionary
	reading_semantic["iconType"] = "reading"
	reading_far_items[1] = reading_semantic
	var reading_data := social_reading_vm.get("data", {}) as Dictionary
	var reading_far_activity := (
		reading_data.get("farResidentActivity", {}) as Dictionary
	)
	reading_far_activity["items"] = reading_far_items
	reading_data["farResidentActivity"] = reading_far_activity
	social_reading_vm["data"] = reading_data
	_expect(
		layer.apply_view_model(social_reading_vm),
		"far reading social VM is accepted",
	)
	await process_frame
	var reading_slots := (
		(layer.audit_snapshot() as Dictionary).get("slots", []) as Array
	)
	_expect(
		String((reading_slots[1] as Dictionary).get(
			"iconPath",
			"",
		)).ends_with("reading.png"),
		"far bulletin activity consumes the approved reading icon",
	)

	var hud := HUD_SCENE.instantiate()
	host.add_child(hud)
	await process_frame
	var hud_layer := hud.find_child("FarResidentActivityLayer", true, false)
	_expect(hud_layer != null, "HUD mounts one resident activity layer")
	if hud_layer != null:
		_expect_equal(hud_layer.z_index, 0, "resident activity remains below later formal pages")

	host.queue_free()
	await process_frame

func _view_model(revision: int, zoom_band: String) -> Dictionary:
	var now_msec := Time.get_ticks_msec()
	return {
		"scope": "town_hud",
		"status": "ready",
		"revision": revision,
		"data": {
			"formalReady": true,
			"pausePrompt": {"visible": false},
			"density": {"zoomBand": zoom_band},
			"residentOverlays": {
				"visibleBudget": 2,
				"aggregateCount": 0,
				"items": [{
					"contentKind": "public_thought",
					"thoughtId": "thought-c",
					"residentId": "resident-d",
					"residentName": "陆青",
					"thoughtLabel": "我得先把这些花盆和工具都仔细检查一遍，免得下午突然下雨时手忙脚乱，还耽误大家收拾花园的活。",
					"screenAnchor": {"x": 1250, "y": 560},
					"expiresAtMsec": now_msec + 5000,
					"action": {
						"intent": "town_hud.open_resident_action",
						"enabled": false,
						"disabledReason": "TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
					},
				}],
			},
			"farResidentActivity": {
				"available": true,
				"disabledReason": "",
				"revision": revision,
				"visibleBudget": 3,
				"aggregateCount": 0,
				"items": [{
					"overlayId": "conversation:conversation-01",
					"kind": "spectator_conversation",
					"conversationId": "conversation-01",
					"participantIds": ["resident-a", "resident-b"],
					"participantNames": ["林岚", "洛星"],
					"screenAnchor": {"x": 600, "y": 500},
					"anchorPolicy": "live_resident_head",
					"motionPolicy": "follow_resident",
					"expiresAtMsec": 0,
					"action": {
						"intent": "conversation.spectator.select",
						"enabled": true,
						"disabledReason": "",
					"payload": {"conversationId": "conversation-01"},
					},
				}, {
					"overlayId": "activity:resident-c",
					"kind": "semantic_icon",
					"residentId": "resident-c",
					"residentName": "顾川",
					"iconType": "walking",
					"semanticKind": "action",
					"screenAnchor": {"x": 1050, "y": 560},
					"anchorPolicy": "live_resident_head",
					"motionPolicy": "follow_resident",
					"expiresAtMsec": now_msec + 5000,
					"action": {
						"intent": "town_hud.open_resident_action",
						"enabled": false,
						"disabledReason": "TOWN_UI_ROUTE_HOST_NOT_CONNECTED",
					},
				}],
			},
		},
		"actions": {},
		"operation": {
			"status": "idle",
			"requestId": "",
			"intent": "",
			"submittedAtMsec": 0,
			"completedAtMsec": 0,
		},
		"error": null,
	}



func _scenario_far_resident_activity_incremental_refresh() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var layer := LAYER_SCENE.instantiate()
	host.add_child(layer)
	await process_frame
	var seventeen_unit_pages := layer.call(
		"_split_thought_pages",
		"一二三四五六七八九十一二三四五，尾",
	) as Array
	_expect_equal(seventeen_unit_pages.size(), 2, "十六加一公开想法会拆成两页")
	_expect(
		abs(
			String(seventeen_unit_pages[0]).length()
			- String(seventeen_unit_pages[1]).length()
		) <= 1,
		"十六加一公开想法不会留下单字尾页",
	)
	_expect_equal(
		"".join(seventeen_unit_pages),
		"一二三四五六七八九十一二三四五，尾",
		"十六加一公开想法分页保留完整原文",
	)

	var view_model := _view_model_far_resident_activity_incremental_refresh(10)
	_expect(layer.apply_view_model(view_model), "初次 HUD 数据可应用")
	var first := layer.audit_snapshot() as Dictionary
	_expect_equal(first.get("renderCount"), 1, "初次数据渲染一次")

	var revision_only := view_model.duplicate(true)
	revision_only["revision"] = 11
	_expect(
		layer.apply_view_model(revision_only),
		"只有 World 修订变化的 HUD 数据可应用",
	)
	var unchanged := layer.audit_snapshot() as Dictionary
	_expect_equal(
		unchanged.get("revision"),
		11,
		"气泡层接收最新 World 修订",
	)
	_expect_equal(
		unchanged.get("renderCount"),
		1,
		"气泡输入未变化时不重复生成槽位",
	)

	var changed := revision_only.duplicate(true)
	changed["revision"] = 12
	(
		(changed.get("data", {}) as Dictionary)
		.get("density", {}) as Dictionary
	)["zoomBand"] = "near"
	_expect(layer.apply_view_model(changed), "密度变化的 HUD 数据可应用")
	var rerendered := layer.audit_snapshot() as Dictionary
	_expect_equal(
		rerendered.get("renderCount"),
		2,
		"实际气泡输入变化时重新渲染",
	)
	var crowded := _view_model_far_resident_activity_incremental_refresh(13)
	var crowded_items: Array[Dictionary] = []
	for index: int in range(5):
		crowded_items.append({
			"overlayId": "resident:%d" % index,
			"kind": "semantic_icon",
			"residentId": "resident_%d" % index,
			"screenAnchor": {
				"x": 260.0 + index * 180.0,
				"y": 360.0,
			},
			"anchorPolicy": "live_resident_head",
			"motionPolicy": "follow_resident",
			"expiresAtMsec": 0,
			"iconType": "sort_mail",
			"phase": "performing",
			"animate": true,
		})
	var crowded_activity := (
		(crowded.get("data", {}) as Dictionary).get(
			"farResidentActivity",
			{},
		) as Dictionary
	)
	crowded_activity["visibleBudget"] = crowded_items.size()
	crowded_activity["items"] = crowded_items
	_expect(layer.apply_view_model(crowded), "五名居民动作数据可应用")
	var expanded := layer.audit_snapshot() as Dictionary
	_expect_equal(
		expanded.get("semanticItemCount"),
		5,
		"居民动作气泡不再受三人全局上限截断",
	)
	_expect_equal(
		expanded.get("visibleSlotCount"),
		5,
		"五名画面内居民均取得动作气泡",
	)
	var far_slot := ((expanded.get("slots", []) as Array)[0] as Dictionary)
	_expect_equal(far_slot.get("rect", Rect2()).size, Vector2(60, 56), "远景使用可读动作气泡")
	_expect_equal(far_slot.get("label"), "", "远景动作气泡不展开文字")
	_expect_equal(
		far_slot.get("iconRect"),
		Rect2(14, 7, 32, 32),
		"远景主图标恢复为可读尺寸并保持居中",
	)
	_expect_equal(
		far_slot.get("iconUsesNativeDisplaySize"),
		true,
		"远景动作图标保持原生尺寸",
	)
	var middle := _view_model_far_resident_activity_incremental_refresh(14)
	(middle.get("data", {}) as Dictionary)["density"] = {"zoomBand": "middle"}
	var middle_activity := (
		(middle.get("data", {}) as Dictionary).get(
			"farResidentActivity",
			{},
		) as Dictionary
	)
	middle_activity["visibleBudget"] = 1
	middle_activity["items"] = [{
		"overlayId": "resident:middle",
		"kind": "semantic_icon",
		"residentId": "resident_middle",
		"screenAnchor": {"x": 640.0, "y": 420.0},
		"anchorPolicy": "live_resident_head",
		"motionPolicy": "follow_resident",
		"expiresAtMsec": 0,
		"iconType": "sort_mail",
		"phase": "approaching",
		"markerKey": "phase_approaching",
		"label": "正在杂货摊接待客人",
		"activeActionLabel": "正在杂货摊接待客人",
		"thoughtLabel": "得先把客人的需求听清楚，再决定怎么安排后面的工作",
		"showLabel": true,
	}]
	_expect(layer.apply_view_model(middle), "中景动作气泡数据可应用")
	var middle_thought_slot := (
		((layer.audit_snapshot() as Dictionary).get("slots", []) as Array)[0]
		as Dictionary
	)
	_expect_equal(
		middle_thought_slot.get("rect", Rect2()).size,
		Vector2(267, 88),
		"中景先使用普通想法气泡",
	)
	_expect_equal(
		middle_thought_slot.get("semanticDisplayMode"),
		"thought",
		"中景先显示公开想法页",
	)
	_expect(
		bool(middle_thought_slot.get("semanticThoughtBubbleVisible", false)),
		"想法页显示普通气泡文字",
	)
	_expect_equal(
		middle_thought_slot.get("semanticThoughtPage"),
		0,
		"长想法从第一页开始显示",
	)
	_expect_equal(
		middle_thought_slot.get("semanticThoughtPageCount"),
		2,
		"长想法均衡分页，避免末尾只剩残缺单字",
	)
	var thought_pages := (
		middle_thought_slot.get("semanticThoughtPages", []) as Array
	)
	_expect(
		abs(
			String(thought_pages[0]).length()
			- String(thought_pages[1]).length()
		) <= 1,
		"十六加一边界会重新均衡为长度接近的想法页",
	)
	_expect_equal(
		"".join(thought_pages),
		"得先把客人的需求听清楚，再决定怎么安排后面的工作",
		"公开想法分页保留完整原文",
	)
	_expect_equal(
		middle_thought_slot.get("labelVisibleLineCount"),
		2,
		"想法页实际只显示两行完整文字",
	)
	_expect_equal(
		middle_thought_slot.get("iconVisible"),
		false,
		"想法页不显示动作图标",
	)
	_expect_equal(
		middle_thought_slot.get("behaviorLabelVisible"),
		false,
		"想法页不显示动作文字",
	)
	_expect(
		not String(middle_thought_slot.get("label", "")).contains("…"),
		"初次思绪页应完整展示，不含截断省略号",
	)
	await create_timer(4.1).timeout
	var middle_slot := (
		((layer.audit_snapshot() as Dictionary).get("slots", []) as Array)[0]
		as Dictionary
	)
	_expect_equal(
		middle_slot.get("semanticDisplayMode"),
		"action",
		"想法页完成观看后切换到动作页",
	)
	_expect_equal(
		middle_slot.get("label"),
		"",
		"动作页收起普通想法气泡文字",
	)
	_expect_equal(
		String(middle_slot.get("behaviorLabel", "")).replace("\n", ""),
		"正在杂货摊接待客人",
		"动作页显示正在进行的正式动作文字",
	)
	_expect_equal(
		middle_slot.get("behaviorLabelMaxLinesVisible"),
		2,
		"普通长动作文字允许均衡显示两行",
	)
	_expect_equal(
		middle_slot.get("behaviorLabelVisibleLineCount"),
		2,
		"普通长动作文字实际完整显示为两行",
	)
	_expect_equal(
		middle_slot.get("iconVisible"),
		true,
		"动作页显示任务图标",
	)
	_expect_equal(
		middle_slot.get("markerVisible"),
		true,
		"动作页显示阶段标记",
	)
	_expect_equal(
		middle_slot.get("iconRect"),
		Rect2(18, 14, 32, 32),
		"中景主图标不因角标发生偏移",
	)
	_expect_equal(
		middle_slot.get("markerRect"),
		Rect2(54, 8, 9, 9),
		"中景角标完全落在外框安全区内",
	)
	var dense := _view_model_far_resident_activity_incremental_refresh(15)
	var dense_activity := (
		(dense.get("data", {}) as Dictionary).get(
			"farResidentActivity",
			{},
		) as Dictionary
	)
	dense_activity["visibleBudget"] = 2
	dense_activity["items"] = []
	for index: int in range(2):
		dense_activity["items"].append({
			"overlayId": "resident:dense:%d" % index,
			"kind": "semantic_icon",
			"residentId": "resident_dense_%d" % index,
			"screenAnchor": {"x": 640.0, "y": 420.0},
			"anchorPolicy": "live_resident_head",
			"motionPolicy": "follow_resident",
			"expiresAtMsec": 0,
			"iconType": "sort_mail",
			"phase": "performing",
		})
	_expect(layer.apply_view_model(dense), "密集居民动作气泡数据可应用")
	var dense_slots := (
		(layer.audit_snapshot() as Dictionary).get("slots", []) as Array
	)
	_expect_equal(
		(dense_slots[1] as Dictionary).get("rect"),
		(dense_slots[0] as Dictionary).get("rect"),
		"同一头顶锚点的气泡保持原位，不为避让而漂移",
	)
	_expect_equal(
		(dense_slots[1] as Dictionary).get("tailToHeadDistance"),
		0.0,
		"动作气泡尾尖严格落在居民头顶锚点",
	)
	_expect_equal(
		(dense_slots[1] as Dictionary).get("connectorVisible"),
		false,
		"密集居民气泡不绘制穿过场景的归属线",
	)
	var near := _view_model_far_resident_activity_incremental_refresh(16)
	(near.get("data", {}) as Dictionary)["density"] = {"zoomBand": "near"}
	var near_activity := (
		(near.get("data", {}) as Dictionary).get(
			"farResidentActivity",
			{},
		) as Dictionary
	)
	near_activity["visibleBudget"] = 1
	near_activity["items"] = [{
		"overlayId": "resident:near",
		"kind": "semantic_icon",
		"residentId": "resident_near",
		"screenAnchor": {"x": 640.0, "y": 420.0},
		"anchorPolicy": "live_resident_head",
		"motionPolicy": "follow_resident",
		"expiresAtMsec": 0,
		"iconType": "sort_mail",
		"phase": "waiting",
		"markerKey": "phase_waiting",
		"label": "分拣信件",
		"activeActionLabel": "分拣信件",
		"showLabel": true,
	}]
	_expect(layer.apply_view_model(near), "近景动作气泡数据可应用")
	var near_snapshot := layer.audit_snapshot() as Dictionary
	var near_slot := (
		(near_snapshot.get("slots", []) as Array)[0] as Dictionary
	)
	_expect_equal(near_slot.get("label"), "", "近景动作页收起普通想法气泡文字")
	_expect_equal(
		near_slot.get("behaviorLabel"),
		"分拣信件",
		"近景显示正式动作短文字",
	)
	_expect_equal(near_slot.get("rect", Rect2()).size, Vector2(267, 88), "近景气泡展开为图标加文字")
	_expect_equal(near_slot.get("iconVisible"), true, "近景显示专属任务图标")
	_expect_equal(near_slot.get("markerVisible"), true, "等待阶段显示等待标记")
	_expect_equal(
		near_slot.get("iconTextureSize"),
		Vector2(32, 32),
		"近景动作图标使用原生32像素资源",
	)
	_expect_equal(
		near_slot.get("iconUsesNativeDisplaySize"),
		true,
		"近景动作图标不发生运行时缩放",
	)
	_expect_equal(
		near_slot.get("markerTextureSize"),
		Vector2(9, 9),
		"等待角标使用原生9像素资源",
	)
	_expect_equal(
		near_slot.get("markerUsesNativeDisplaySize"),
		true,
		"等待角标不发生运行时缩放",
	)
	_expect_equal(
		near_slot.get("tailToHeadDistance"),
		0.0,
		"近景图标加文字气泡仍严格贴住居民头顶",
	)
	var long_action := _view_model_far_resident_activity_incremental_refresh(18)
	(long_action.get("data", {}) as Dictionary)["density"] = {"zoomBand": "near"}
	var long_action_activity := (
		(long_action.get("data", {}) as Dictionary).get(
			"farResidentActivity",
			{},
		) as Dictionary
	)
	var long_action_label := "正在逐一核对花盆工具和天气记录并安排下午花园维护工作"
	long_action_activity["visibleBudget"] = 1
	long_action_activity["items"] = [{
		"overlayId": "resident:long-action",
		"kind": "semantic_icon",
		"residentId": "resident_long_action",
		"screenAnchor": {"x": 640.0, "y": 420.0},
		"anchorPolicy": "live_resident_head",
		"motionPolicy": "follow_resident",
		"expiresAtMsec": 0,
		"iconType": "sort_mail",
		"phase": "performing",
		"activeActionLabel": long_action_label,
		"showLabel": true,
	}]
	_expect(layer.apply_view_model(long_action), "超长动作文字气泡数据可应用")
	await process_frame
	var long_action_first := (
		((layer.audit_snapshot() as Dictionary).get("slots", []) as Array)[0]
		as Dictionary
	)
	var action_pages := (
		long_action_first.get("semanticActionPages", []) as Array
	)
	_expect(action_pages.size() > 1, "超长动作文字拆成多个轮播页")
	_expect_equal(
		"".join(action_pages),
		long_action_label,
		"动作分页保留完整原文",
	)
	_expect(
		not String(long_action_first.get("behaviorLabel", "")).contains("…"),
		"动作页不使用省略号吞掉内容",
	)
	_expect_equal(
		long_action_first.get("behaviorLabelVisibleLineCount"),
		2,
		"超长动作当前页实际完整显示为两行",
	)
	var first_action_page := String(
		long_action_first.get("behaviorLabel", "")
	).replace("\n", "")
	await create_timer(2.1).timeout
	var long_action_second := (
		((layer.audit_snapshot() as Dictionary).get("slots", []) as Array)[0]
		as Dictionary
	)
	_expect_equal(
		long_action_second.get("semanticActionPage"),
		1,
		"超长动作按两秒轮播到下一页",
	)
	_expect(
		String(long_action_second.get("behaviorLabel", "")).replace("\n", "")
		!= first_action_page,
		"动作轮播页文字确实发生变化",
	)
	var edge := _view_model_far_resident_activity_incremental_refresh(19)
	var edge_activity := (
		(edge.get("data", {}) as Dictionary).get(
			"farResidentActivity",
			{},
		) as Dictionary
	)
	edge_activity["visibleBudget"] = 1
	edge_activity["items"] = [{
		"overlayId": "resident:edge",
		"kind": "semantic_icon",
		"residentId": "resident_edge",
		"screenAnchor": {"x": 90.0, "y": 420.0},
		"anchorPolicy": "live_resident_head",
		"motionPolicy": "follow_resident",
		"expiresAtMsec": 0,
		"iconType": "sort_mail",
		"phase": "performing",
	}]
	_expect(layer.apply_view_model(edge), "画面边缘内动作气泡数据可应用")
	var edge_slot := (
		((layer.audit_snapshot() as Dictionary).get("slots", []) as Array)[0]
		as Dictionary
	)
	_expect_equal(
		(edge_slot.get("rect", Rect2()) as Rect2).position.x,
		60.0,
		"画面边缘内气泡保持头顶居中，不夹回布局安全线",
	)
	_expect_equal(
		edge_slot.get("tailToHeadDistance"),
		0.0,
		"画面边缘内动作气泡尾尖仍严格对准头顶",
	)
	var state_markers := {
		"approaching": "phase_approaching",
		"waiting": "phase_waiting",
		"interrupted": "phase_interrupted",
		"completed": "result_completed",
		"failed": "result_failed",
	}
	var marker_revision := 20
	for phase: String in state_markers:
		var marker_vm := _view_model_far_resident_activity_incremental_refresh(marker_revision)
		marker_revision += 1
		var marker_activity := (
			(marker_vm.get("data", {}) as Dictionary).get(
				"farResidentActivity",
				{},
			) as Dictionary
		)
		marker_activity["visibleBudget"] = 1
		marker_activity["items"] = [{
			"overlayId": "resident:marker:%s" % phase,
			"kind": "semantic_icon",
			"residentId": "resident_marker",
			"screenAnchor": {"x": 640.0, "y": 420.0},
			"anchorPolicy": "live_resident_head",
			"motionPolicy": "follow_resident",
			"expiresAtMsec": Time.get_ticks_msec() + 5000,
			"iconType": "sort_mail",
			"phase": phase,
			"markerKey": state_markers[phase],
		}]
		_expect(layer.apply_view_model(marker_vm), "%s阶段气泡可应用" % phase)
		var marker_slot := (
			((layer.audit_snapshot() as Dictionary).get("slots", []) as Array)[0]
			as Dictionary
		)
		_expect_equal(
			marker_slot.get("markerVisible"),
			true,
			"%s阶段角标可见" % phase,
		)
		_expect(
			String(marker_slot.get("markerPath", "")).ends_with(
				"%s.png" % state_markers[phase]
			),
			"%s阶段使用正确角标" % phase,
		)
		_expect_equal(
			marker_slot.get("markerUsesNativeDisplaySize"),
			true,
			"%s阶段角标保持原生尺寸" % phase,
		)

	host.queue_free()
	await process_frame

func _view_model_far_resident_activity_incremental_refresh(revision: int) -> Dictionary:
	return {
		"scope": "town_hud",
		"status": "ready",
		"revision": revision,
		"data": {
			"formalReady": true,
			"pausePrompt": {"visible": false},
			"density": {"zoomBand": "far"},
			"farResidentActivity": {
				"available": true,
				"visibleBudget": 3,
				"items": [],
			},
			"residentOverlays": {
				"visibleBudget": 3,
				"items": [],
			},
		},
		"actions": {},
		"operation": {
			"status": "idle",
			"requestId": "",
		},
	}



func _scenario_bulletin_activity() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		data,
	) as Dictionary
	_expect_equal(
		opening_result.get("ok"),
		true,
		"公告栏测试开局可加载",
	)
	if opening_result.get("ok") != true:
		return
	var opening_config := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	(
		opening_config.get("environment", {}) as Dictionary
	)["randomSeed"] = 1
	(
		opening_config.get("environment", {}) as Dictionary
	)["clock"] = "00:00"
	var public_props := PROP_QUERY.agent_props_at_place(
		data,
		"中心广场",
	)
	_expect(
		not JSON.stringify(public_props).contains(
			"中心广场公告栏阅读处"
		)
		and not JSON.stringify(public_props).contains(
			"中心广场公告栏张贴处"
		),
		"公告栏执行锚点不会冒充普通 Agent 道具",
	)
	var world: RefCounted = WORLD.new()
	_expect_equal(
			world.call(
				"start",
				data,
				opening_config,
			).get("ok"),
		true,
		"公告栏测试 World 可启动",
	)
	var before := world.call(
		"query_activity_options",
		RESIDENT_ID,
	) as Dictionary
	_expect_equal(
		_option_available(before, "activity_bulletin_read"),
		false,
		"没有未读公告时不提供空阅读",
	)
	_expect_equal(
		_option_available(before, "activity_bulletin_publish"),
		false,
		"没有已确认内容时不提供空张贴",
	)
	_expect_equal(
		world.call(
			"perform_activity_step",
			RESIDENT_ID,
			"bulletin-empty-plan",
			1,
			_activity_step_bulletin_activity(
				"bulletin-empty-read",
				"activity_bulletin_read",
			),
		).get("errorCode"),
		"ACTIVITY_NOT_ELIGIBLE",
		"直接 activity.perform 也不能绕过公告栏前置条件",
	)
	_expect_equal(
		world.call(
			"publish_announcement",
			"傍晚在广场集合。",
		).get("ok"),
		true,
		"玩家张贴一条正式公告",
	)
	var after_publish := world.call(
		"query_activity_options",
		RESIDENT_ID,
	) as Dictionary
	_expect_equal(
		_option_available(
			after_publish,
			"activity_bulletin_read",
		),
		false,
		"全局通知后不再生成必须阅读的任务",
	)
	_expect_equal(
		world.call(
			"read_announcement",
			RESIDENT_ID,
			"announcement-1",
		).get("newKnowledge"),
		false,
		"居民回看已知公告不会重复知情",
	)
	var knowledge := world.call(
		"announcement_knowledge_for",
		RESIDENT_ID,
	) as Array
	_expect_equal(
		knowledge.size(),
		1,
		"公告发布后正文立即进入居民知情",
	)
	_expect_equal(
		(knowledge[0] as Dictionary).get("announcement_id"),
		"announcement-1",
		"实际阅读记录引用正确公告",
	)
	var after_read := world.call(
		"query_activity_options",
		RESIDENT_ID,
	) as Dictionary
	_expect_equal(
		_option_available(after_read, "activity_bulletin_read"),
		false,
		"读完现有公告后不重复空读",
	)
	var requested_post := world.call(
		"sync_resident_request",
		{
			"request_id": "request-post-bulletin",
			"source_revision": 1,
			"requester_id": "resident_tang_xiaoman_01",
			"submitted": true,
			"active": true,
			"subject_ids": ["resident_tang_xiaoman_01"],
			"place_id": "中心广场",
			"capability_id": "bulletin.publish",
			"target_refs": {
				"text": "花园需要两个人帮忙整理。",
			},
			"success_result_id": "bulletin-posted",
			"expires_at": 3000,
			"capacity": 1,
			"source_event_ids": ["event-post-bulletin"],
		},
	) as Dictionary
	_expect_equal(
		requested_post.get("ok"),
		true,
		"居民提交的张贴请求形成社会事项",
	)
	var matter_id := String(
		(requested_post.get("matter", {}) as Dictionary).get(
			"matter_id",
			"",
		)
	)
	_expect_equal(
		world.call(
			"record_social_awareness",
			matter_id,
			RESIDENT_ID,
			"witnessed",
			"event-post-bulletin",
		).get("ok"),
		true,
		"被告知的居民实际知晓张贴请求",
	)
	_expect_equal(
		world.call(
			"begin_social_response_round_for_residents",
			matter_id,
			[RESIDENT_ID],
			30,
		).get("ok"),
		true,
		"张贴请求进入有限回应轮",
	)
	var projected := _projected_matter(
		world,
		matter_id,
	)
	_expect_equal(
		world.call(
			"submit_social_response",
			RESIDENT_ID,
			{
				"response_id": "response-post-bulletin",
				"matter_id": matter_id,
				"matter_revision": int(
					projected.get("revision", -1)
				),
				"response_round_id": String(
					projected.get("response_round_id", "")
				),
				"option_id": "accept",
				"public_text": "我去贴上。",
			},
		).get("ok"),
		true,
		"居民回应后由 World 确认张贴承诺",
	)
	var post_options := world.call(
		"query_activity_options",
		RESIDENT_ID,
	) as Dictionary
	_expect_equal(
		_option_available(
			post_options,
			"activity_bulletin_publish",
		),
		true,
		"只有已确认承诺才开放张贴活动",
	)
	var post_performed := world.call(
		"perform_activity_step",
		RESIDENT_ID,
		"bulletin-post-plan",
		1,
		_activity_step_bulletin_activity(
			"bulletin-post-step",
			"activity_bulletin_publish",
		),
	) as Dictionary
	_expect_equal(
		post_performed.get("ok"),
		true,
		"居民开始前往真实公告栏张贴",
	)
	var announcements: Array = []
	for _minute in 90:
		world.call("advance", 1.0)
		announcements = world.call("get_announcements") as Array
		if announcements.size() >= 2:
			break
	_expect_equal(
		announcements.size(),
		2,
		"完成实际张贴活动后才新增居民公告",
	)
	if announcements.size() >= 2:
		_expect_equal(
			(announcements[1] as Dictionary).get("text"),
			"花园需要两个人帮忙整理。",
			"居民公告正文来自已确认的 World 目标",
		)
	for resident_id: String in world.call("get_resident_ids") as Array[String]:
		_expect_equal(
			(world.call(
				"announcement_knowledge_for",
				resident_id,
			) as Array).size(),
			2,
			"居民完成张贴后全镇都收到第二条公告",
		)
	_expect_equal(
		_matter_state(world, matter_id),
		"closed",
		"张贴结果完成并关闭对应承诺",
	)
	world.call("stop")
	return
func _activity_step_bulletin_activity(step_id: String, activity_id: String) -> Dictionary:
	return {
		"stepId": step_id,
		"operation": "activity.perform",
		"target": {
			"activityId": activity_id,
			"placeId": "中心广场",
		},
		"params": {},
	}



func _option_available(query: Dictionary, activity_id: String) -> bool:
	for value: Variant in query.get("options", []) as Array:
		var option := value as Dictionary
		if String(option.get("activityId", "")) == activity_id:
			return bool(option.get("available", false))
	return false



func _projected_matter(
	world: RefCounted,
	matter_id: String,
) -> Dictionary:
	for value: Variant in world.call(
		"get_agent_social_matters",
		RESIDENT_ID,
	) as Array:
		var matter := value as Dictionary
		if String(matter.get("matter_id", "")) == matter_id:
			return matter
	return {}



func _matter_state(world: RefCounted, matter_id: String) -> String:
	for value: Variant in world.call(
		"get_social_matter_summaries",
		true,
	) as Array:
		var matter := value as Dictionary
		if String(matter.get("matter_id", "")) == matter_id:
			return String(matter.get("state", ""))
	return ""



func _scenario_default_occupation_activity() -> void:
	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var catalog := BUILDER.load_json_object(
		"res://world/data/town/resident_catalog.json"
	)
	var runtime: RefCounted = ACTIVITY_RUNTIME.new()
	_expect_equal(
		(runtime.call("configure", world_data) as Dictionary).get("ok"),
		true,
		"activity runtime configures from formal World data",
	)
	for value: Variant in catalog.get("residents", []) as Array:
		var resident := value as Dictionary
		var occupation := resident.get("occupation", {}) as Dictionary
		var resident_id := String(resident.get("residentId", ""))
		var occupation_name := String(occupation.get("name", ""))
		var workplace := String(occupation.get("workplacePlace", ""))
		var social_state := {
			"job": occupation_name,
			"workplace": workplace,
		}
		var formal_occupation := {}
		for occupation_value: Variant in world_data.get(
			"occupations",
			[],
		) as Array:
			var candidate_occupation := occupation_value as Dictionary
			if String(candidate_occupation.get("label", "")) == (
				occupation_name
			):
				formal_occupation = candidate_occupation
				break
		var work_places: Array[String] = [workplace]
		for place_value: Variant in formal_occupation.get(
			"relatedWorkplacePlaces",
			[],
		) as Array:
			var place_id := String(place_value)
			if not work_places.has(place_id):
				work_places.append(place_id)
		var activity_ids := {}
		var primary_worker_count := 0
		var work_positions := {}
		var has_region_target := false
		for work_place: String in work_places:
			var options_result := runtime.call(
				"query_options",
				resident_id,
				social_state,
				work_place,
				600,
			) as Dictionary
			for option_value: Variant in options_result.get(
				"options",
				[],
			) as Array:
				var option := option_value as Dictionary
				if String(option.get("role", "")) != "worker":
					continue
				activity_ids[String(option.get("activityId", ""))] = true
				if work_place == workplace:
					primary_worker_count += 1
		_expect(
			primary_worker_count >= 1,
			"%s 在主要工作地 %s 至少有一项真实工作"
			% [occupation_name, workplace],
		)
		for slot_value: Variant in world_data.get(
			"activitySlots",
			[],
		) as Array:
			var slot := slot_value as Dictionary
			if (
				String(slot.get("role", "")) != "worker"
				or not activity_ids.has(
					String(slot.get("activityId", "")),
				)
			):
				continue
			if String(slot.get("targetType", "")) == "region":
				has_region_target = true
			else:
				for member_value: Variant in slot.get("memberAnchors", []) as Array:
					var member := member_value as Dictionary
					var pair := member.get("position", []) as Array
					if pair.size() == 2:
						work_positions["%s,%s" % [pair[0], pair[1]]] = true
		_expect(
			activity_ids.size() >= 2,
			"%s 在主要和关联工作地合计至少有两个工作阶段"
			% occupation_name,
		)
		_expect(
			has_region_target or work_positions.size() >= 2,
			"%s 使用真实多位置或由 World 生成的语义区域落点"
			% occupation_name,
		)
	var occupation_by_id := {}
	for value: Variant in world_data.get("occupations", []) as Array:
		if value is Dictionary:
			var occupation := value as Dictionary
			occupation_by_id[String(
				occupation.get("occupationId", ""),
			)] = occupation
	var grocer := occupation_by_id.get(
		"occupation_grocer",
		{},
	) as Dictionary
	var flower_vendor := occupation_by_id.get(
		"occupation_flower_vendor",
		{},
	) as Dictionary
	_expect_equal(
		(grocer.get("fixedWorkAreaIds", []) as Array).size(),
		3,
		"杂货店主负责市集三个固定摊位",
	)
	_expect_equal(
		(flower_vendor.get("fixedWorkAreaIds", []) as Array).size(),
		2,
		"花店店主负责市集两个固定花摊",
	)
	var market_work_area_ids := {}
	for occupation: Dictionary in [grocer, flower_vendor]:
		for slot_id: Variant in occupation.get(
			"fixedWorkAreaIds",
			[],
		) as Array:
			market_work_area_ids[String(slot_id)] = true
	_expect_equal(
		market_work_area_ids.size(),
		5,
		"市集五个固定摊位不会在两个职业之间重复归属",
	)
	var derived_workplace_query := runtime.call(
		"query_options",
		"resident_workplace_derivation_probe",
		{
			"job": "杂货店主",
			"workplace": "图书馆",
		},
		"独立市集",
		600,
	) as Dictionary
	var derived_worker_count := 0
	for option_value: Variant in derived_workplace_query.get(
		"options",
		[],
	) as Array:
		var option := option_value as Dictionary
		if String(option.get("role", "")) == "worker":
			derived_worker_count += 1
	_expect(
		derived_worker_count >= 2,
		"职业目录决定主要工作地，居民资料里的旧 workplace 值不能改写职业规则",
	)
	var cafe_visitor_positions := {}
	for slot_value: Variant in world_data.get("activitySlots", []) as Array:
		var slot := slot_value as Dictionary
		if (
			String(slot.get("placeName", "")) != "花房咖啡馆"
			or String(slot.get("role", "")) != "visitor"
		):
			continue
		for member_value: Variant in slot.get("memberAnchors", []) as Array:
			var member := member_value as Dictionary
			var pair := member.get("position", []) as Array
			if pair.size() == 2:
				cafe_visitor_positions["%s,%s" % [pair[0], pair[1]]] = true
	_expect(
		cafe_visitor_positions.size() >= 4,
		"咖啡馆允许至少四名访客使用不同位置，不会被单人站位锁死",
	)
	return
func _scenario_activity_semantic_icon() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var runtime: RefCounted = ACTIVITY_RUNTIME.new()
	var configured := runtime.call("configure", data) as Dictionary
	_expect_equal(
		configured.get("ok"),
		true,
		"活动语义测试数据可配置",
	)
	var icon_keys := _runtime_icon_keys()
	_expect_icon(
		runtime,
		"activity_postal_sort_mail",
		"working",
		"分拣信件发布工作图标",
	)
	_expect_icon(
		runtime,
		"activity_dining_eat_meal",
		"eating",
		"正式吃饭活动发布吃饭图标",
	)
	_expect_icon(
		runtime,
		"activity_library_read",
		"reading",
		"阅读活动发布阅读图标",
	)
	_expect_base_icon(
		runtime,
		"activity_postal_sort_mail",
		"sort_mail",
		"分拣信件保留自己的任务图标",
	)
	_expect_base_icon(
		runtime,
		"activity_garden_bench_rest",
		"rest_outdoor_bench",
		"户外长椅休息保留实际休息方式",
	)
	for activity_value: Variant in data.get("activityDefinitions", []) as Array:
		var activity := activity_value as Dictionary
		var activity_id := String(activity.get("activityId", ""))
		var semantic := runtime.call(
			"presentation_semantic_for_activity",
			activity_id,
		) as Dictionary
		_expect(
			not String(semantic.get("baseIconKey", "")).is_empty(),
			"正式活动缺少动作图标：%s" % activity_id,
		)
		_expect(
			icon_keys.has(String(semantic.get("baseIconKey", ""))),
			"正式活动图标未进入运行资源：%s" % activity_id,
		)
	var prop_verbs: Dictionary = {}
	_collect_prop_verbs(
		JSON.parse_string(FileAccess.get_file_as_string(PROP_SOURCE_PATH)),
		prop_verbs,
	)
	for verb_value: Variant in prop_verbs.keys():
		var verb := String(verb_value)
		var icon_key := ACTION_PRESENTATION.verb_icon_key(verb)
		_expect(not icon_key.is_empty(), "正式道具动作缺少图标：%s" % verb)
		_expect(
			icon_keys.has(icon_key),
			"正式道具动作图标未进入运行资源：%s -> %s" % [verb, icon_key],
		)
	for system_case: Dictionary in [
		{"type": "去", "action": {}},
		{"type": "待着", "action": {}},
		{"type": "托人传话", "action": {}},
		{"type": "调整营业", "action": {"open": true}},
		{"type": "调整营业", "action": {"open": false}},
	]:
		var system_icon := ACTION_PRESENTATION.system_icon_key(
			String(system_case.get("type", "")),
			system_case.get("action", {}) as Dictionary,
		)
		_expect(
			not system_icon.is_empty() and icon_keys.has(system_icon),
			"系统动作缺少运行图标：%s" % String(system_case.get("type", "")),
		)
	_expect_equal(
		ACTION_PRESENTATION.verb_icon_key("整理笔记"),
		"write",
		"整理笔记复用正式写作图标",
	)
	_expect_equal(
		ACTION_PRESENTATION.verb_icon_key("自由书写"),
		"write",
		"自由书写复用正式写作图标",
	)


func _expect_icon(
	runtime: RefCounted,
	activity_id: String,
	expected_icon: String,
	message: String,
) -> void:
	var semantic := runtime.call(
		"presentation_semantic_for_activity",
		activity_id,
	) as Dictionary
	_expect_equal(
		semantic.get("semanticIconType"),
		expected_icon,
		message,
	)



func _expect_base_icon(
	runtime: RefCounted,
	activity_id: String,
	expected_icon: String,
	message: String,
) -> void:
	var semantic := runtime.call(
		"presentation_semantic_for_activity",
		activity_id,
	) as Dictionary
	_expect_equal(semantic.get("baseIconKey"), expected_icon, message)



func _runtime_icon_keys() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ICON_MANIFEST_PATH)
	)
	var result: Dictionary = {}
	if parsed is not Dictionary:
		_failures.append("动作图标运行清单无法读取")
		return result
	for item_value: Variant in (parsed as Dictionary).get("items", []) as Array:
		if item_value is not Dictionary:
			continue
		var icon_key := String((item_value as Dictionary).get("iconKey", ""))
		if not icon_key.is_empty():
			result[icon_key] = true
	return result



func _collect_prop_verbs(value: Variant, result: Dictionary) -> void:
	if value is Dictionary:
		var data := value as Dictionary
		var verb := String(data.get("verb", "")).strip_edges()
		if not verb.is_empty():
			result[verb] = true
		for child: Variant in data.values():
			_collect_prop_verbs(child, result)
	elif value is Array:
		for child: Variant in value as Array:
			_collect_prop_verbs(child, result)



func _scenario_ui_adapter_activity_semantic() -> void:
	var adapter: Node = ADAPTER.new()
	root.add_child(adapter)
	var approaching := adapter.call(
		"_hud_live_resident_semantic",
		{
			"currentAction": {
				"action_id": "mail-action",
				"type": "用道具",
			},
			"activityCue": {
				"phase": "approaching",
				"semanticIconType": "working",
			},
		},
	) as Dictionary
	_expect_equal(
		approaching.get("iconType"),
		"walking",
		"前往工作位置时显示走路图标",
	)

	var performing := adapter.call(
		"_hud_live_resident_semantic",
		{
			"currentAction": {
				"action_id": "mail-action",
				"type": "用道具",
			},
			"activityCue": {
				"phase": "performing",
				"activityKind": "work",
				"semanticIconType": "working",
			},
		},
	) as Dictionary
	_expect_equal(
		performing.get("iconType"),
		"working",
		"开始整理信件后显示工作图标",
	)
	var formal_performing := adapter.call(
		"_hud_live_resident_semantic",
		{
			"actionPresentation": {
				"baseIconKey": "sort_mail",
				"phase": "performing",
				"label": "分拣信件",
				"publicThought": "这些信得按街区分好。",
			},
		},
	) as Dictionary
	_expect_equal(
		formal_performing.get("iconType"),
		"sort_mail",
		"正式表现语义不再退化成通用工作图标",
	)
	_expect_equal(
		formal_performing.get("animate"),
		true,
		"执行中的正式动作启用共享两帧循环",
	)
	_expect_equal(
		formal_performing.get("thoughtLabel"),
		"这些信得按街区分好。",
		"执行中的正式动作继续携带居民公开想法",
	)
	var formal_waiting := adapter.call(
		"_hud_live_resident_semantic",
		{
			"actionPresentation": {
				"baseIconKey": "clinic_consult",
				"phase": "waiting",
				"label": "等待问诊位",
			},
		},
	) as Dictionary
	_expect_equal(
		formal_waiting.get("markerKey"),
		"phase_waiting",
		"等待状态保留原任务并叠加等待标记",
	)
	_expect_equal(
		formal_waiting.get("label"),
		"等待问诊位",
		"等待状态文字由正式阶段生成",
	)
	_expect_equal(
		adapter.call(
			"_hud_action_display_label",
			"分拣信件",
			"performing",
			"",
		),
		"正在分拣信件",
		"执行阶段文字明确说明正在做什么",
	)
	_expect_equal(
		adapter.call(
			"_hud_action_display_label",
			"捕鱼",
			"failed",
			"",
		),
		"捕鱼失败",
		"失败阶段文字不只显示动作名",
	)

	var travelling := adapter.call(
		"_hud_live_resident_semantic",
		{
			"currentAction": {
				"action_id": "go-post-office",
				"type": "去",
			},
			"isMoving": true,
		},
	) as Dictionary
	_expect_equal(
		travelling.get("iconType"),
		"walking",
		"普通赶路动作也显示走路图标",
	)
	_expect_equal(
		adapter.call(
			"_hud_effective_zoom_band",
			{
				"activeInteriorId": "market_shop",
				"cameraZoomBand": "middle",
			},
		),
		"near",
		"室内地点始终使用可读文字密度",
	)
	_expect_equal(
		adapter.call(
			"_hud_effective_zoom_band",
			{
				"activeInteriorId": "",
				"cameraZoomBand": "middle",
			},
		),
		"middle",
		"室外仍服从镜头距离密度",
	)
	_expect_equal(
		adapter.call(
			"_hud_effective_zoom_band",
			{
				"activeInteriorId": "",
				"cameraZoomBand": "far",
				"followedResident": "林岚",
			},
		),
		"near",
		"跟随居民始终使用图标加文字的个人聚焦密度",
	)
	_expect_equal(
		adapter.call(
			"_hud_public_thought_text",
			"刚到镇上，先回住处放东西，看看接下来做什么",
		),
		"刚到镇上，先回住处放东西，看看接下…",
		"公开想法不会在第一个逗号处被截成半句话",
	)
	_expect_equal(
		adapter.call(
			"_hud_public_thought_text",
			"abcdefghijklmnopqrstuvwxyzABCDEFGH",
		),
		"abcdefghijklmnopqrstuvwxyzABCDEFGH",
		"英文公开想法按实际显示宽度计算，不按字符数误截断",
	)
	_expect_equal(
		adapter.call(
			"_hud_public_thought_text",
			"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		),
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		"等宽像素字体中的英文恰好放得下时不误加省略号",
	)
	_expect_equal(
		adapter.call(
			"_hud_public_thought_text",
			"安排meeting后检查tools再出发",
		),
		"安排meeting后检查tools再出发",
		"中英混排公开想法未超过显示宽度时不误加省略号",
	)
	_expect(
		String(adapter.call(
			"_hud_public_thought_text",
			"安排meeting后检查tools再出发并完成今天所有工作",
		)).ends_with("…"),
		"公开想法确实超过显示宽度时才显示省略号",
	)

	adapter.queue_free()
	await process_frame

func _scenario_activity_physical_occupancy() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var runtime: RefCounted = ACTIVITY_RUNTIME.new()
	_expect_equal(
		(runtime.call("configure", data) as Dictionary).get("ok"),
		true,
		"物理占用检查可配置活动运行时",
	)
	var social := {
		"job": "食堂主理人",
		"workplace": "公共食堂",
	}
	var cooking := _validate_activity_physical_occupancy(
		runtime,
		"resident_cook",
		"plan_cook",
		"activity_dining_prepare_meal",
		social,
	)
	_expect_equal(cooking.get("ok"), true, "做饭活动可校验")
	if cooking.get("ok") == true:
		cooking["sourceContract"] = "activity.perform"
		cooking["sourceActionId"] = ""
		var cooking_candidate := (
			cooking.get("candidates", []) as Array
		)[0] as Dictionary
		_expect_equal(
			(
				runtime.call(
					"reserve_execution",
					cooking,
					cooking_candidate.get("slotId"),
					cooking_candidate.get("memberAnchorId"),
				) as Dictionary
			).get("ok"),
			true,
			"第一名居民占用公共食堂灶台",
		)
	var baking := _validate_activity_physical_occupancy(
		runtime,
		"resident_baker",
		"plan_bake",
		"activity_baker_bake_bread",
		social,
	)
	_expect_equal(baking.get("ok"), true, "烘焙活动可校验")
	if baking.get("ok") == true:
		baking["sourceContract"] = "activity.perform"
		baking["sourceActionId"] = ""
		var baking_candidate := (
			baking.get("candidates", []) as Array
		)[0] as Dictionary
		_expect_equal(
			baking_candidate.get("memberAvailable"),
			false,
			"不同活动引用同一场景同一坐标时也显示为占用",
		)
		var conflict := runtime.call(
			"reserve_execution",
			baking,
			baking_candidate.get("slotId"),
			baking_candidate.get("memberAnchorId"),
		) as Dictionary
		_expect_equal(
			conflict.get("errorCode"),
			"ACTIVITY_RESERVATION_CONFLICT",
			"做饭和烘焙不能按不同 slot 名称叠在同一灶台",
		)
	runtime.call("close")
	return
func _validate_activity_physical_occupancy(
	runtime: RefCounted,
	resident_id: String,
	plan_id: String,
	activity_id: String,
	social: Dictionary,
) -> Dictionary:
	return runtime.call(
		"validate_step",
		resident_id,
		plan_id,
		0,
		{
			"stepId": "step",
			"operation": "activity.perform",
			"target": {
				"activityId": activity_id,
				"placeId": "公共食堂",
			},
			"params": {"reason": "检查真实工作位占用"},
		},
		social,
		"公共食堂",
	) as Dictionary



func _scenario_weather_activity_policy() -> void:
	var policy: RefCounted = POLICY.new()
	var outdoor_activity := {"kind": "work"}
	var public_indoor_activity := {"kind": "social"}

	_expect(
		(policy.call(
			"evaluate",
			"雷暴",
			"town_outdoor",
			outdoor_activity,
			"worker",
		) as Dictionary).get("available") == false,
		"雷暴必须阻断户外活动",
	)
	for weather: String in ["小雨", "中雨", "大雨", "下雪"]:
		var outdoor := policy.call(
			"evaluate",
			weather,
			"town_outdoor",
			outdoor_activity,
			"worker",
		) as Dictionary
		_expect(
			outdoor.get("available") == true
			and String(outdoor.get("suitability", "")) == "discouraged"
			and int(outdoor.get("preference", 0)) < 0,
			"%s 必须降低户外活动优先级但不强制所有居民回家" % weather,
		)
		var indoor := policy.call(
			"evaluate",
			weather,
			"indoor_library",
			public_indoor_activity,
			"visitor",
		) as Dictionary
		_expect(
			indoor.get("available") == true
			and String(indoor.get("suitability", "")) == "preferred"
			and int(indoor.get("preference", 0)) > 0,
			"%s 必须提高公共室内活动优先级" % weather,
		)

	var sunny := policy.call(
		"evaluate",
		"晴天",
		"town_outdoor",
		outdoor_activity,
		"worker",
	) as Dictionary
	_expect(
		sunny.get("available") == true
		and String(sunny.get("suitability", "")) == "preferred",
		"晴天必须提高户外活动优先级",
	)

	for weather: String in [
		"晴天",
		"阴天",
		"小雨",
		"中雨",
		"大雨",
		"雷暴",
		"下雪",
	]:
		var context := policy.call("public_context", weather) as Dictionary
		_expect(
			not String(context.get("summary", "")).strip_edges().is_empty(),
			"%s 必须提供玩家与 Agent 可理解的公开影响摘要" % weather,
		)
		_expect(
			context.has("outdoorPolicy"),
			"%s 必须提供稳定的户外策略" % weather,
		)


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(
		bool(result.get("ok", false)),
		"%s（%s）" % [message, result.get("errorCode", "")],
	)
