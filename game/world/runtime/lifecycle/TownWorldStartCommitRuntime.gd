class_name TownWorldStartCommitRuntime
extends RefCounted


const PRODUCTION_TASK_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskCoordinationRuntime.gd"
)


const WORLD_START_PREPARATION := preload(
	"res://world/runtime/lifecycle/TownWorldStartPreparation.gd"
)
const CLINIC_INTERVIEW_POLICY := preload(
	"res://world/runtime/condition/TownClinicInterviewPolicy.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const WORLD_LOG_STORE := preload(
	"res://world/runtime/log/TownWorldLogStore.gd"
)
const MOVEMENT_CLEARANCE_RUNTIME := preload(
	"res://world/runtime/TownMovementClearanceRuntime.gd"
)
const RESIDENT_ARRIVAL_RUNTIME := preload(
	"res://world/runtime/TownResidentArrivalRuntime.gd"
)
const RESIDENT_STATE_PROJECTION := preload(
	"res://world/runtime/presentation/TownResidentStateProjection.gd"
)


static func start(
	host,
	world_data: Dictionary,
	opening_config: Dictionary,
	require_world_ready: bool,
	resident_identities: Variant,
	initial_player_avatar_present: bool,
	validate_new_game_spawns: bool,
) -> Dictionary:
	var validation: Dictionary = host.validate_startup(
		world_data,
		opening_config,
		require_world_ready,
		resident_identities,
	)
	if validation.get("ok") != true:
		return validation
	var preparation := WORLD_START_PREPARATION.prepare(
		host,
		world_data,
		opening_config,
		require_world_ready,
		resident_identities,
		validate_new_game_spawns,
		host.NEW_GAME_ARRIVAL_END_MINUTE_OF_DAY,
	) as Dictionary
	if preparation.get("ok") != true:
		var failure := preparation.get("failure", {}) as Dictionary
		if bool(preparation.get("alreadyDecorated", false)):
			return failure
		return host._decorate_command_result(
			failure,
			String(preparation.get("errorCodeOverride", "")),
		)
	var prepared_activity_runtime: TownWorldActivityRuntime = preparation.get("activityRuntime")
	var prepared_work_tasks: TownWorkTaskRuntime = preparation.get("workTasks")
	var prepared_staffing: TownStaffingRuntime = preparation.get("staffing")
	var prepared_cargo_inventory: TownCargoInventoryRuntime = preparation.get("cargoInventory")
	var prepared_production: TownProductionRuntime = preparation.get("production")
	var prepared_occupation_services: TownOccupationServiceRuntime = preparation.get("occupationServices")
	var prepared_identities := preparation.get("residentIdentities", {}) as Dictionary
	var prepared_environment: TownWorldEnvironment = preparation.get("environment")
	var prepared_arrival_schedule := preparation.get("arrivalSchedule", {}) as Dictionary
	var prepared_resident_conditions: TownResidentConditionRuntime = preparation.get("residentConditions")
	var prepared_resident_sleep: TownResidentSleepRuntime = preparation.get("residentSleep")
	var prepared_conflict_controller: TownConflictWorldController = preparation.get("conflictController")
	var prepared_resident_lifecycle: TownResidentLifecycleRuntime = preparation.get("residentLifecycle")
	var initial := opening_config.get("environment", {}) as Dictionary
	host._running = false
	host._activity_runtime.close()
	host._activity_runtime = prepared_activity_runtime
	host._disconnect_work_task_log_source()
	host._work.install(
		prepared_work_tasks,
		prepared_staffing,
		prepared_cargo_inventory,
		prepared_production,
		prepared_occupation_services,
	)
	host._resident_conditions = prepared_resident_conditions
	host._resident_sleep = prepared_resident_sleep
	host._clinic_interviews = CLINIC_INTERVIEW_POLICY.new()
	host._pause_reasons.clear()
	host.frame_budget_runtime.reset()
	host.activity_reachability_state.clear()
	var speed_was_reset: bool = host._simulation_speed != 1
	host._simulation_speed = 1
	host._runtime_generation += 1
	host.world_definition.world_data = world_data.duplicate(true)
	host.world_definition.base_world_data = world_data.duplicate(true)
	host.place_presentation_query.clear_cache()
	PERCEPTION_RUNTIME._rebuild_membership_grid_lookup(host)
	host._dynamic_prop_runtime.reset()
	host._animal_fact_runtime.reset()
	host._activity_runtime.reset_runtime_state()
	host.activity_routine_state.reset()
	host.activity_work_task_bindings.reset()
	host.private_message_runtime.reset()
	host.world_definition.opening = opening_config.duplicate(true)
	host.world_definition.owners = (opening_config.get("ownerAssignments", {}) as Dictionary).duplicate(true)
	host.resident_registry.records.clear()
	host.resident_registry.order.clear()
	host._reset_social_runtimes()
	host.conversation_state.reset()
	host.world_log_domain.journal.reset()
	host.world_log_domain.store = WORLD_LOG_STORE.new()
	host.world_log_domain.store.reset()
	host.world_log_domain.capture_enabled = false
	host.actor_presentation_state.observed_action_preview_resident_id = ""
	host.perception_spatial.reset()
	host.social_coordination_state.reset()
	host._conflict_agent_world_bridge.reset_pending_knowledge_wakes()
	MOVEMENT_CLEARANCE_RUNTIME.clear_cache()
	RESIDENT_ARRIVAL_RUNTIME.clear_cache()
	host.telemetry.reset_agent_request_metrics()
	host._agent_wake_preparation_runtime.clear()
	host._tick_weather_override = ""
	host.resident_registry.install_identities(prepared_identities)
	var resident_preparation := WORLD_START_PREPARATION.prepare_residents(
		opening_config,
		prepared_arrival_schedule,
		world_data,
		host.resident_registry.id_by_name,
		prepared_resident_lifecycle,
		host._resident_conditions,
		host._resident_sleep,
	) as Dictionary
	if resident_preparation.get("ok") != true:
		return host._decorate_command_result(
			resident_preparation.get("failure", {}) as Dictionary,
		)
	host.resident_registry.records = resident_preparation.get("residents", {}) as Dictionary
	host.resident_registry.order.assign(
		resident_preparation.get("residentOrder", []) as Array,
	)
	host._resident_lifecycle = prepared_resident_lifecycle
	var staffing_rebuild := host._work.staffing.rebuild(
		host.resident_registry.records,
		int(prepared_environment.get_absolute_minute()),
	) as Dictionary
	if staffing_rebuild.get("ok") != true:
		return host._decorate_command_result(staffing_rebuild)
	host.PLACE_SERVICE_COMMAND_RUNTIME.initialize(host)
	host.actor_presentation_state.player_avatar = RESIDENT_STATE_PROJECTION.avatar_runtime(
		opening_config.get("playerAvatar", {}) as Dictionary,
		host.DEFAULT_PLAYER_AVATAR_ID,
	)
	host.actor_presentation_state.player_avatar_present = initial_player_avatar_present
	host._traveler_relationship_state.reset()
	host._environment = prepared_environment
	host._conflict_controller = prepared_conflict_controller
	RESIDENT_ARRIVAL_RUNTIME.prewarm_pending_entry_states(
		host,
		host.IDLE_RESIDENT_CLEARANCE_PX,
	)
	var conflict_bridge_configuration := host._conflict_agent_world_bridge.configure(
		host._conflict_controller,
		host.person_name_for_id,
	) as Dictionary
	if conflict_bridge_configuration.get("ok") != true:
		return host._decorate_command_result(conflict_bridge_configuration)
	host._connect_conflict_controller_signals()
	PERCEPTION_RUNTIME._refresh_perception(
		host,
		false,
		host._traveler_relationship_state,
	)
	host._bump_world_revision(false)
	host._begin_world_run()
	PRODUCTION_TASK_COORDINATION_RUNTIME.sync(
		host,
		int(host._environment.get_absolute_minute()),
	)
	for resident_id in host.resident_registry.order:
		host._schedule_decision(resident_id, false)
	host._assert_subsystems_installed("start")
	var lifecycle: Dictionary = host._announce_world_lifecycle(speed_was_reset)
	return host._decorate_command_result({
		"ok": true,
		"validationMode": "formal" if require_world_ready else "development",
		"residentCount": host.resident_registry.order.size(),
		"identityStatus": host.resident_registry.identity_status,
		"simulationSpeed": host._simulation_speed,
		"time": host.get_time(),
		"weather": host.get_weather(),
		"lifecycle": lifecycle,
	})
