class_name TownWorldStartPreparation
extends RefCounted


const ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownWorldActivityRuntime.gd"
)
const WORK_TASK_RUNTIME := preload(
	"res://world/runtime/work/TownWorkTaskRuntime.gd"
)
const STAFFING_RUNTIME := preload(
	"res://world/runtime/work/TownStaffingRuntime.gd"
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
const WORLD_ENVIRONMENT := preload(
	"res://world/runtime/environment/TownWorldEnvironment.gd"
)
const OPENING_CONFIG := preload(
	"res://world/runtime/TownWorldOpeningConfig.gd"
)
const RESIDENT_CONDITION_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentConditionRuntime.gd"
)
const RESIDENT_SLEEP_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentSleepRuntime.gd"
)
const CONFLICT_CONTROLLER := preload(
	"res://world/runtime/conflict/TownConflictWorldController.gd"
)
const RESIDENT_LIFECYCLE_RUNTIME := preload(
	"res://world/runtime/lifecycle/TownResidentLifecycleRuntime.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const RESTORE_PEOPLE := preload(
	"res://world/runtime/persistence/TownWorldRestorePeople.gd"
)
const RESIDENT_RUNTIME_FACTORY := preload(
	"res://world/runtime/lifecycle/TownResidentRuntimeFactory.gd"
)


static func prepare(
	world_host,
	world_data: Dictionary,
	opening_config: Dictionary,
	require_world_ready: bool,
	resident_identities: Variant,
	validate_new_game_spawns: bool,
	new_game_arrival_end_minute_of_day: int,
) -> Dictionary:
	var prepared_activity_runtime: TownWorldActivityRuntime = ACTIVITY_RUNTIME.new()
	var failure := prepared_activity_runtime.configure(world_data) as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)

	var prepared_work_tasks := WORK_TASK_RUNTIME.new()
	failure = prepared_work_tasks.configure() as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)

	var prepared_staffing := STAFFING_RUNTIME.new()
	failure = prepared_staffing.configure(world_data) as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)

	var prepared_cargo_inventory := CARGO_INVENTORY_RUNTIME.new()
	failure = prepared_cargo_inventory.configure(world_data) as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)
	failure = prepared_cargo_inventory.initialize_opening_stock() as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)

	var prepared_production := PRODUCTION_RUNTIME.new()
	failure = prepared_production.configure(world_data) as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)

	var prepared_occupation_services := OCCUPATION_SERVICE_RUNTIME.new()
	failure = prepared_occupation_services.configure() as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)
	failure = prepared_occupation_services.initialize() as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)

	if require_world_ready and validate_new_game_spawns:
		failure = world_host.validate_new_game_resident_spawns(
			world_data,
			opening_config,
		) as Dictionary
		if failure.get("ok") != true:
			return _failure(failure, true)

	var prepared_identities := OPENING_CONFIG.prepare_resident_identities(
		opening_config,
		resident_identities,
		require_world_ready,
	) as Dictionary
	var prepared_environment := WORLD_ENVIRONMENT.new()
	var initial := opening_config.get("environment", {}) as Dictionary
	failure = prepared_environment.start(
		int(initial.get("day", 1)),
		String(initial.get("clock", "00:00")),
		String(initial.get("weather", "晴天")),
		int(initial.get("randomSeed", 1)),
	) as Dictionary
	if failure.get("ok") != true:
		return _failure(failure, false, "ENVIRONMENT_CONFIG_INVALID")

	var prepared_arrival_schedule := {}
	if require_world_ready and validate_new_game_spawns:
		var arrival_preparation := prepare_arrival_schedule(
			opening_config,
			int(prepared_environment.get_absolute_minute()),
			new_game_arrival_end_minute_of_day,
		) as Dictionary
		if arrival_preparation.get("ok") != true:
			return _failure(arrival_preparation)
		prepared_arrival_schedule = (
			arrival_preparation.get("schedule", {}) as Dictionary
		)

	failure = prepared_production.initialize(
		int(prepared_environment.get_absolute_minute()),
	) as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)

	var prepared_resident_conditions := RESIDENT_CONDITION_RUNTIME.new()
	failure = prepared_resident_conditions.configure() as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)
	var prepared_resident_sleep := RESIDENT_SLEEP_RUNTIME.new()
	var prepared_conflict_controller := CONFLICT_CONTROLLER.new()
	failure = prepared_conflict_controller.configure(world_host) as Dictionary
	if failure.get("ok") != true:
		return _failure(failure)

	return {
		"ok": true,
		"activityRuntime": prepared_activity_runtime,
		"workTasks": prepared_work_tasks,
		"staffing": prepared_staffing,
		"cargoInventory": prepared_cargo_inventory,
		"production": prepared_production,
		"occupationServices": prepared_occupation_services,
		"residentIdentities": prepared_identities,
		"environment": prepared_environment,
		"arrivalSchedule": prepared_arrival_schedule,
		"residentConditions": prepared_resident_conditions,
		"residentSleep": prepared_resident_sleep,
		"conflictController": prepared_conflict_controller,
		"residentLifecycle": RESIDENT_LIFECYCLE_RUNTIME.new(),
	}


static func prepare_arrival_schedule(
	opening_config: Dictionary,
	start_absolute_minute: int,
	arrival_end_minute_of_day: int,
) -> Dictionary:
	var resident_ids: Array[String] = []
	for value: Variant in opening_config.get("residents", []) as Array:
		if value is Dictionary:
			var resident_id := String(
				(value as Dictionary).get("residentId", ""),
			).strip_edges()
			if not resident_id.is_empty():
				resident_ids.append(resident_id)
	resident_ids.sort()
	var day_start := start_absolute_minute - posmod(start_absolute_minute, 1440)
	var candidate_minutes: Array[int] = []
	for absolute_minute in range(
		start_absolute_minute + 1,
		day_start + arrival_end_minute_of_day + 1,
	):
		candidate_minutes.append(absolute_minute)
	if candidate_minutes.size() < resident_ids.size():
		return {
			"ok": false,
			"errorCode": "WORLD_RESIDENT_ARRIVAL_WINDOW_INVALID",
			"retryable": false,
			"errors": ["首日上午剩余时间不足以让所有居民逐个抵达"],
		}
	var random := RandomNumberGenerator.new()
	random.seed = (
		int(Time.get_unix_time_from_system() * 1_000_000.0)
		^ Time.get_ticks_usec()
		^ int(
			(opening_config.get("environment", {}) as Dictionary).get(
				"randomSeed",
				0,
			)
		)
	)
	for index in range(candidate_minutes.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var held := candidate_minutes[index]
		candidate_minutes[index] = candidate_minutes[swap_index]
		candidate_minutes[swap_index] = held
	DINING_SERVICE.prioritize_dining_worker_arrival(
		opening_config,
		resident_ids,
		candidate_minutes,
	)
	var schedule := {}
	for index in resident_ids.size():
		schedule[resident_ids[index]] = candidate_minutes[index]
	return {"ok": true, "errorCode": "", "schedule": schedule}


static func prepare_residents(
	opening_config: Dictionary,
	arrival_schedule: Dictionary,
	world_data: Dictionary,
	resident_id_by_name: Dictionary,
	resident_lifecycle: TownResidentLifecycleRuntime,
	resident_conditions: TownResidentConditionRuntime,
	resident_sleep: TownResidentSleepRuntime,
) -> Dictionary:
	var residents := {}
	var resident_order: Array[String] = []
	for value: Variant in opening_config.get("residents", []) as Array:
		var record := value as Dictionary
		var attributes := record.get("attributes", {}) as Dictionary
		var world_state := record.get("worldState", {}) as Dictionary
		var resident_name := String(attributes.get("name", ""))
		var resident_id := String(record.get("residentId", "")).strip_edges()
		if resident_id.is_empty():
			resident_id = String(resident_id_by_name.get(resident_name, ""))
		resident_order.append(resident_id)
		var resident_runtime := RESIDENT_RUNTIME_FACTORY.create(
			record,
			world_state,
			resident_id,
		)
		if arrival_schedule.has(resident_id):
			resident_runtime["arrivalState"] = {
				"status": "pending",
				"scheduledAbsoluteMinute": int(arrival_schedule.get(resident_id, -1)),
				"arrivedAbsoluteMinute": -1,
			}
			resident_runtime["doing"] = "尚未抵达小镇"
		var initialized := resident_lifecycle.initialize_resident(
			resident_id,
			resident_name,
			RESIDENT_RUNTIME_FACTORY.home_anchor(world_data, resident_runtime),
		) as Dictionary
		if initialized.get("ok") != true:
			return _failure(initialized)
		residents[resident_id] = resident_runtime
		initialized = resident_conditions.initialize_resident(
			resident_id,
			RESTORE_PEOPLE.resident_condition_seed(resident_id),
		) as Dictionary
		if initialized.get("ok") != true:
			return _failure(initialized)
		initialized = resident_sleep.initialize_resident(resident_id) as Dictionary
		if initialized.get("ok") != true:
			return _failure(initialized)
	resident_order.sort()
	return {
		"ok": true,
		"residents": residents,
		"residentOrder": resident_order,
	}


static func _failure(
	result: Dictionary,
	already_decorated := false,
	error_code_override := "",
) -> Dictionary:
	return {
		"ok": false,
		"failure": result,
		"alreadyDecorated": already_decorated,
		"errorCodeOverride": error_code_override,
	}
