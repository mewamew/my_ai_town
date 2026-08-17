class_name TownWorldRestoreState
extends RefCounted


const WORLD_ENVIRONMENT := preload("res://world/runtime/environment/TownWorldEnvironment.gd")
const RESTORE_LAYOUT := preload("res://world/runtime/persistence/TownWorldRestoreLayout.gd")
const RESTORE_PEOPLE := preload("res://world/runtime/persistence/TownWorldRestorePeople.gd")
const RESTORE_SOCIAL := preload("res://world/runtime/persistence/TownWorldRestoreSocialState.gd")
const RESTORE_WORK := preload("res://world/runtime/persistence/TownWorldRestoreWork.gd")
const RESTORE_ANIMALS := preload(
	"res://world/runtime/persistence/TownWorldRestoreAnimals.gd"
)
const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const SAVE_SCHEMA_REGISTRY := preload(
	"res://world/presentation/session/TownSaveSchemaRegistry.gd"
)
const ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownWorldActivityRuntime.gd"
)
const PLACE_SERVICE_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceCommandRuntime.gd"
)
const PROP_QUERY := preload("res://world/data/town/TownWorldPropQuery.gd")
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
const SOCIAL_MATTER_RUNTIME := preload(
	"res://world/runtime/social/TownSocialMatterRuntime.gd"
)
const COMMUNITY_BULLETIN_RUNTIME := preload(
	"res://world/runtime/social/TownCommunityBulletinRuntime.gd"
)
const CONFLICT_CONTROLLER := preload(
	"res://world/runtime/conflict/TownConflictWorldController.gd"
)


static func prepare(
	world_data: Dictionary,
	opening_config: Dictionary,
	state: Dictionary,
) -> Dictionary:
	var errors: Array[String] = []
	var layout := RESTORE_LAYOUT.prepare(world_data, state) as Dictionary
	if layout.get("ok") != true:
		errors.append_array(layout.get("errors", []) as Array[String])
	var restored_world_data := (
		layout.get("worldData", world_data.duplicate(true)) as Dictionary
	)
	var people := RESTORE_PEOPLE.prepare(
		restored_world_data,
		opening_config,
		state,
	) as Dictionary
	if people.get("ok") != true:
		errors.append_array(people.get("errors", []) as Array[String])
	var residents := people.get("residents", {}) as Dictionary
	var player_avatar := people.get("playerAvatar", {}) as Dictionary
	if layout.get("ok") == true and people.get("ok") == true:
		errors.append_array(
			RESTORE_LAYOUT.validate_occupants(
				restored_world_data,
				residents,
				player_avatar,
			) as Array[String]
		)
	var social := {}
	# Social references can only be validated against a complete restored
	# roster. Running that phase after a resident restore failure turns one
	# actionable error into hundreds of misleading "unknown resident" errors.
	if people.get("ok") == true:
		social = RESTORE_SOCIAL.prepare(
			restored_world_data,
			state,
			residents,
			player_avatar,
		) as Dictionary
		if social.get("ok") != true:
			errors.append_array(social.get("errors", []) as Array[String])
	var restored_environment: RefCounted = WORLD_ENVIRONMENT.new()
	var environment_value: Variant = state.get("environment")
	if not environment_value is Dictionary:
		errors.append("世界存档 environment 必须是对象")
	else:
		var environment_result := restored_environment.restore_from_snapshot(environment_value as Dictionary,) as Dictionary
		if environment_result.get("ok") != true:
			errors.append_array(environment_result.get("errors", []) as Array[String])
		else:
			var current_absolute_minute := int(
				restored_environment.get_absolute_minute()
			)
			errors.append_array(
				_validate_saved_history_times(
					state,
					current_absolute_minute,
				)
			)
			if people.get("ok") == true:
				errors.append_array(
					_validate_resident_action_times(
						restored_world_data,
						residents,
						current_absolute_minute,
					)
				)
	var activity_runtime_value: Variant = state.get("activityRuntime")
	if state.has("activityRuntime") and not activity_runtime_value is Dictionary:
		errors.append("世界存档 activityRuntime 必须是对象")
	var activity_routines_value: Variant = state.get("activityRoutines")
	if state.has("activityRoutines") and not activity_routines_value is Dictionary:
		errors.append("世界存档 activityRoutines 必须是对象")
	var work_tasks_value: Variant = state.get("workTasks")
	if state.has("workTasks") and not work_tasks_value is Dictionary:
		errors.append("世界存档 workTasks 必须是对象")
	var staffing_state_value: Variant = state.get("staffingState")
	if (
		state.has("staffingState")
		and not staffing_state_value is Dictionary
	):
		errors.append("世界存档 staffingState 必须是对象")
	var cargo_inventory_value: Variant = state.get("cargoInventory")
	if (
		state.has("cargoInventory")
		and not cargo_inventory_value is Dictionary
	):
		errors.append("世界存档 cargoInventory 必须是对象")
	var production_state_value: Variant = state.get("productionState")
	if (
		state.has("productionState")
		and not production_state_value is Dictionary
	):
		errors.append("世界存档 productionState 必须是对象")
	var occupation_services_value: Variant = state.get(
		"occupationServices",
	)
	if (
		state.has("occupationServices")
		and not occupation_services_value is Dictionary
	):
		errors.append("世界存档 occupationServices 必须是对象")
	var private_messages_value: Variant = state.get("privateMessages")
	if (
		state.has("privateMessages")
		and not private_messages_value is Dictionary
	):
		errors.append("世界存档 privateMessages 必须是对象")
	var work_task_bindings_value: Variant = state.get(
		"activityWorkTaskBindings",
	)
	if (
		state.has("activityWorkTaskBindings")
		and not work_task_bindings_value is Dictionary
	):
		errors.append("世界存档 activityWorkTaskBindings 必须是对象")
	var social_matters_value: Variant = state.get("socialMatters")
	if state.has("socialMatters") and not social_matters_value is Dictionary:
		errors.append("世界存档 socialMatters 必须是对象")
	var community_bulletin_value: Variant = state.get("communityBulletin")
	if (
		state.has("communityBulletin")
		and not community_bulletin_value is Dictionary
	):
		errors.append("世界存档 communityBulletin 必须是对象")
	var animal_facts_value: Variant = state.get("animalFacts")
	if state.has("animalFacts") and not animal_facts_value is Dictionary:
		errors.append("世界存档 animalFacts 必须是对象")
	var place_service_states_value: Variant = state.get(
		"placeServiceStates"
	)
	if (
		state.has("placeServiceStates")
		and not place_service_states_value is Dictionary
	):
		errors.append("世界存档 placeServiceStates 必须是对象")
	var resident_conditions_value: Variant = state.get("residentConditions")
	if (
		state.has("residentConditions")
		and not resident_conditions_value is Dictionary
	):
		errors.append("世界存档 residentConditions 必须是对象")
	var resident_sleep_value: Variant = state.get("residentSleep")
	if state.has("residentSleep") and not resident_sleep_value is Dictionary:
		errors.append("世界存档 residentSleep 必须是对象")
	var conflict_state_value: Variant = state.get("conflictState")
	if state.has("conflictState") and not conflict_state_value is Dictionary:
		errors.append("世界存档 conflictState 必须是对象")
	var resident_lifecycle_value: Variant = state.get("residentLifecycle")
	if state.has("residentLifecycle") and resident_lifecycle_value is not Dictionary:
		errors.append("世界存档 residentLifecycle 必须是对象")
	var traveler_relations_value: Variant = state.get("travelerRelations")
	if state.has("travelerRelations") and not traveler_relations_value is Dictionary:
		errors.append("世界存档 travelerRelations 必须是对象")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {
		"ok": true,
		"worldData": restored_world_data,
		"indoorLayoutOverrides": (
			layout.get("indoorLayoutOverrides", []) as Array
		).duplicate(true),
		"owners": (social.get("owners", {}) as Dictionary).duplicate(true),
		"residents": residents,
		"residentOrder": (people.get("residentOrder", []) as Array).duplicate(),
		"playerAvatar": player_avatar,
		"announcements": (social.get("announcements", []) as Array).duplicate(true),
		"conversations": (social.get("conversations", {}) as Dictionary).duplicate(true),
		"eventLog": (social.get("eventLog", []) as Array).duplicate(true),
		"sequences": (social.get("sequences", {}) as Dictionary).duplicate(true),
		"environment": restored_environment,
		"activityRuntime": (
			(activity_runtime_value as Dictionary).duplicate(true)
			if state.has("activityRuntime")
			else null
		),
		"activityRoutines": (
			(activity_routines_value as Dictionary).duplicate(true)
			if state.has("activityRoutines")
			else null
		),
		"workTasks": (
			(work_tasks_value as Dictionary).duplicate(true)
			if state.has("workTasks")
			else null
		),
		"staffingState": (
			(staffing_state_value as Dictionary).duplicate(true)
			if state.has("staffingState")
			else null
		),
		"cargoInventory": (
			(cargo_inventory_value as Dictionary).duplicate(true)
			if state.has("cargoInventory")
			else null
		),
		"productionState": (
			(production_state_value as Dictionary).duplicate(true)
			if state.has("productionState")
			else null
		),
		"occupationServices": (
			(occupation_services_value as Dictionary).duplicate(true)
			if state.has("occupationServices")
			else null
		),
		"privateMessages": (
			(private_messages_value as Dictionary).duplicate(true)
			if state.has("privateMessages")
			else null
		),
		"activityWorkTaskBindings": (
			(work_task_bindings_value as Dictionary).duplicate(true)
			if state.has("activityWorkTaskBindings")
			else null
		),
		"socialMatters": (
			(social_matters_value as Dictionary).duplicate(true)
			if state.has("socialMatters")
			else null
		),
		"communityBulletin": (
			(community_bulletin_value as Dictionary).duplicate(true)
			if state.has("communityBulletin")
			else null
		),
		"animalFacts": (
			(animal_facts_value as Dictionary).duplicate(true)
			if state.has("animalFacts")
			else null
		),
		"placeServiceStates": (
			(place_service_states_value as Dictionary).duplicate(true)
			if state.has("placeServiceStates")
			else null
		),
		"residentConditions": (
			(resident_conditions_value as Dictionary).duplicate(true)
			if state.has("residentConditions")
			else null
		),
		"residentSleep": (
			(resident_sleep_value as Dictionary).duplicate(true)
			if state.has("residentSleep")
			else null
		),
		"conflictState": (
			(conflict_state_value as Dictionary).duplicate(true)
			if state.has("conflictState")
			else null
		),
		"residentLifecycle": (
			(resident_lifecycle_value as Dictionary).duplicate(true)
			if state.has("residentLifecycle")
			else null
		),
		"travelerRelations": (
			(traveler_relations_value as Dictionary).duplicate(true)
			if state.has("travelerRelations")
			else null
		),
	}


# 恢复候选的完整准备链：prepare() 校验基础域后，把各业务域交给对应恢复模块，
# 再把结果写回 prepared["*Prepared"]。world 仅用于两处保留在世界运行时的逻辑
# （家宅锚点、按当前岗位构建场所服务默认值）以及冲突控制器接线。
static func prepare_full(
	world: RefCounted,
	world_data: Dictionary,
	opening_config: Dictionary,
	state: Dictionary,
) -> Dictionary:
	var current_activity_source_fingerprint := String(
		(
			world_data.get("activityIntegrationReceipt", {}) as Dictionary
		).get("sourceFingerprint", "")
	)
	var migration := SAVE_SCHEMA_REGISTRY.migrate_world_state(
		state,
		current_activity_source_fingerprint,
	)
	if migration.get("ok") != true:
		return {"ok": false, "errors": ["世界存档旧版本迁移失败"]}
	state = migration.get("state", state) as Dictionary
	var prepared := prepare(
		world_data,
		opening_config,
		state,
	) as Dictionary
	if prepared.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				prepared.get(
					"errors",
					["世界存档无法恢复"],
				) as Array
			).duplicate(true),
		}
	if bool(migration.get("refreshResidentActionRoutes", false)):
		_refresh_migrated_activity_action_routes(
			prepared.get("worldData", world_data) as Dictionary,
			prepared.get("residents", {}) as Dictionary,
		)
	var resident_condition_restore := RESTORE_PEOPLE.prepare_resident_conditions(
		prepared,
	) as Dictionary
	if resident_condition_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": resident_condition_restore.get(
				"errors",
				["居民临时状况存档无法恢复"],
			) as Array,
		}
	prepared["residentConditionsPrepared"] = resident_condition_restore.get("conditions")
	prepared["residentSleepPrepared"] = resident_condition_restore.get("sleep")
	var prepared_activity_runtime := ACTIVITY_RUNTIME.new()
	var activity_configuration := prepared_activity_runtime.configure(
		world_data,
	) as Dictionary
	if activity_configuration.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				activity_configuration.get(
					"errors",
					["Activity Runtime 数据未编译"],
				) as Array
			).duplicate(true),
		}
	var resident_actions := {}
	for resident_id_value: Variant in (
		prepared.get("residents", {}) as Dictionary
	):
		var resident_id := String(resident_id_value)
		var restored_resident := (
			prepared.get("residents", {}) as Dictionary
		)[resident_id_value] as Dictionary
		resident_actions[resident_id] = (
			restored_resident.get("currentAction", {}) as Dictionary
		).duplicate(true)
	var activity_restore := prepared_activity_runtime.prepare_restore(
		prepared.get("activityRuntime"),
		resident_actions,
	) as Dictionary
	if activity_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				activity_restore.get(
					"errors",
					["activityRuntime 存档无法恢复"],
				) as Array
			).duplicate(true),
		}
	prepared["activityRuntimePrepared"] = activity_restore.duplicate(true)
	var routine_restore := RESTORE_WORK.prepare_activity_routines(
		prepared.get("activityRoutines"),
		prepared.get("residents", {}) as Dictionary,
	) as Dictionary
	if routine_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				routine_restore.get(
					"errors",
					["activityRoutines 存档无法恢复"],
				) as Array
			).duplicate(true),
		}
	prepared["activityRoutinesPrepared"] = routine_restore.duplicate(true)
	var prepared_work_tasks := WORK_TASK_RUNTIME.new()
	var work_task_configuration := prepared_work_tasks.configure(
	) as Dictionary
	if work_task_configuration.get("ok") != true:
		return {
			"ok": false,
			"errors": ["工作任务目录无法配置"],
		}
	var work_task_snapshot := (
		prepared.get("workTasks") as Dictionary
		if prepared.get("workTasks") is Dictionary
		else {"schemaVersion": 1, "tasks": []}
	)
	var work_task_restore := prepared_work_tasks.restore_save_snapshot(
		work_task_snapshot,
	) as Dictionary
	if work_task_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": ["workTasks 存档无法恢复"],
		}
	var work_task_bindings_restore := (
		RESTORE_WORK.prepare_work_task_bindings(
			prepared.get("activityWorkTaskBindings"),
			prepared.get("residents", {}) as Dictionary,
			prepared_work_tasks,
		) as Dictionary
	)
	if work_task_bindings_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				work_task_bindings_restore.get(
					"errors",
					["activityWorkTaskBindings 存档无法恢复"],
				) as Array
			).duplicate(true),
		}
	prepared["workTasksPrepared"] = prepared_work_tasks
	prepared["activityWorkTaskBindingsPrepared"] = (
		work_task_bindings_restore.get("bindings", {}) as Dictionary
	).duplicate(true)
	var private_message_restore := RESTORE_WORK.prepare_private_messages(
		prepared.get("privateMessages"),
		prepared.get("residents", {}) as Dictionary,
		prepared_work_tasks,
	) as Dictionary
	if private_message_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				private_message_restore.get(
					"errors",
					["privateMessages 存档无法恢复"],
				) as Array
			).duplicate(true),
		}
	prepared["privateMessagesPrepared"] = (
		private_message_restore.duplicate(true)
	)
	var prepared_cargo_inventory := CARGO_INVENTORY_RUNTIME.new()
	var cargo_configuration := prepared_cargo_inventory.configure(
		world_data,
	) as Dictionary
	if cargo_configuration.get("ok") != true:
		return {
			"ok": false,
			"errors": ["货批和地点库存目录无法配置"],
		}
	var cargo_snapshot := (
		prepared.get("cargoInventory") as Dictionary
		if prepared.get("cargoInventory") is Dictionary
		else {}
	)
	if cargo_snapshot.is_empty():
		var initialized := prepared_cargo_inventory.initialize_opening_stock(
		) as Dictionary
		if initialized.get("ok") != true:
			return {
				"ok": false,
				"errors": ["旧存档无法建立开局地点库存"],
			}
	else:
		var cargo_restore := prepared_cargo_inventory.restore_snapshot(
			cargo_snapshot,
		) as Dictionary
		if cargo_restore.get("ok") != true:
			return {
				"ok": false,
				"errors": ["cargoInventory 存档无法恢复"],
			}
	prepared["cargoInventoryPrepared"] = prepared_cargo_inventory
	var prepared_production := PRODUCTION_RUNTIME.new()
	var production_configuration := prepared_production.configure(
		world_data,
	) as Dictionary
	if production_configuration.get("ok") != true:
		return {
			"ok": false,
			"errors": ["生产区域目录无法配置"],
		}
	var production_snapshot := (
		prepared.get("productionState") as Dictionary
		if prepared.get("productionState") is Dictionary
		else {}
	)
	var production_restore := (
		prepared_production.restore(
			production_snapshot,
		) as Dictionary
		if not production_snapshot.is_empty()
		else prepared_production.initialize(
			int(
				(prepared.get("environment") as RefCounted).get_absolute_minute()
			),
		) as Dictionary
	)
	if production_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": ["productionState 存档无法恢复"],
		}
	prepared["productionStatePrepared"] = prepared_production
	var prepared_occupation_services := OCCUPATION_SERVICE_RUNTIME.new()
	var occupation_service_configuration := (
		prepared_occupation_services.configure() as Dictionary
	)
	if occupation_service_configuration.get("ok") != true:
		return {
			"ok": false,
			"errors": ["职业服务结果目录无法配置"],
		}
	var occupation_service_snapshot := (
		prepared.get("occupationServices") as Dictionary
		if prepared.get("occupationServices") is Dictionary
		else {}
	)
	var occupation_service_restore := (
		prepared_occupation_services.restore(
			occupation_service_snapshot,
		) as Dictionary
		if not occupation_service_snapshot.is_empty()
		else prepared_occupation_services.initialize(
		) as Dictionary
	)
	if occupation_service_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": ["occupationServices 存档无法恢复"],
		}
	prepared["occupationServicesPrepared"] = prepared_occupation_services
	var prepared_staffing := STAFFING_RUNTIME.new()
	var staffing_configuration := prepared_staffing.configure(
		world_data,
	) as Dictionary
	if staffing_configuration.get("ok") != true:
		return {
			"ok": false,
			"errors": ["岗位状态目录无法配置"],
		}
	var staffing_snapshot := (
		prepared.get("staffingState") as Dictionary
		if prepared.get("staffingState") is Dictionary
		else {}
	)
	var staffing_restore := (
		prepared_staffing.restore_persistent_snapshot(
			staffing_snapshot,
			prepared.get("residents", {}) as Dictionary,
			int(
				(prepared.get("environment") as RefCounted).get_absolute_minute()
			),
		) as Dictionary
		if not staffing_snapshot.is_empty()
		else prepared_staffing.rebuild(
			prepared.get("residents", {}) as Dictionary,
			int(
				(prepared.get("environment") as RefCounted).get_absolute_minute()
			),
		) as Dictionary
	)
	if staffing_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": ["staffingState 存档无法恢复"],
		}
	prepared["staffingStatePrepared"] = (
		prepared_staffing.persistent_snapshot() as Dictionary
	)
	var prepared_social_matters := SOCIAL_MATTER_RUNTIME.new()
	var social_snapshot_value: Variant = prepared.get("socialMatters")
	if social_snapshot_value is Dictionary:
		var social_restore := prepared_social_matters.restore_save_snapshot(
			social_snapshot_value as Dictionary,
		) as Dictionary
		if social_restore.get("ok") != true:
			return {
				"ok": false,
				"errors": [
					"socialMatters 存档无法恢复：%s"
					% String(social_restore.get("reason", "字段无效"))
				],
			}
	var prepared_bulletin := COMMUNITY_BULLETIN_RUNTIME.new()
	prepared_bulletin.bind_social_runtime(
		prepared_social_matters,
	)
	var bulletin_snapshot_value: Variant = prepared.get(
		"communityBulletin",
	)
	if bulletin_snapshot_value is Dictionary:
		var bulletin_restore := prepared_bulletin.restore_save_snapshot(
			bulletin_snapshot_value as Dictionary,
		) as Dictionary
		if bulletin_restore.get("ok") != true:
			return {
				"ok": false,
				"errors": [
					"communityBulletin 存档无法恢复：%s"
					% String(bulletin_restore.get("reason", "字段无效"))
				],
			}
	else:
		var legacy_migration := prepared_bulletin.migrate_legacy_broadcasts(
			prepared.get("announcements", []) as Array,
			(prepared.get("residents", {}) as Dictionary).keys(),
		) as Dictionary
		if legacy_migration.get("ok") != true:
			return {
				"ok": false,
				"errors": [
					"旧公告无法迁移：%s"
					% String(legacy_migration.get("reason", "字段无效"))
				],
			}
	var animal_restore := RESTORE_ANIMALS.prepare_animal_facts(
		prepared.get("animalFacts"),
		world_data,
	) as Dictionary
	if animal_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				animal_restore.get(
					"errors",
					["animalFacts 存档无法恢复"],
				) as Array
			).duplicate(true),
		}
	var prepared_animal_facts := (
		animal_restore.get("facts", {}) as Dictionary
	)
	var lifecycle_restore := RESTORE_PEOPLE.prepare_resident_lifecycle(
		world,
		world_data,
		prepared.get("residents", {}) as Dictionary,
		prepared.get("residentLifecycle"),
	) as Dictionary
	if lifecycle_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": lifecycle_restore.get(
				"errors",
				["residentLifecycle 存档无法恢复"],
			),
		}
	prepared["residentLifecyclePrepared"] = (
		lifecycle_restore.get("snapshot", {}) as Dictionary
	)
	prepared["livingResidentsPrepared"] = (
		lifecycle_restore.get("livingResidents", {}) as Dictionary
	)
	var place_service_defaults := PLACE_SERVICE_COMMAND_RUNTIME.build_default_states(
		world,
		world_data,
		prepared.get("livingResidentsPrepared", {}) as Dictionary,
		{},
		true,
	)
	var place_service_restore := RESTORE_LAYOUT.prepare_place_service_states(
		prepared.get("placeServiceStates"),
		place_service_defaults,
	) as Dictionary
	if place_service_restore.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				place_service_restore.get(
					"errors",
					["placeServiceStates 存档无法恢复"],
				) as Array
			).duplicate(true),
		}
	var prepared_place_service_states := (
		place_service_restore.get("states", {}) as Dictionary
	)
	var social_reference_errors := RESTORE_SOCIAL.validate_restore_references(
		prepared_social_matters,
		prepared_bulletin,
		world_data,
		prepared.get("residents", {}) as Dictionary,
		prepared.get("playerAvatar", {}) as Dictionary,
		prepared.get("conversations", []),
		prepared.get("eventLog", []) as Array,
		int(
			(prepared.get("sequences", {}) as Dictionary).get(
				"event",
				0,
			),
		),
		prepared_animal_facts,
	)
	if not social_reference_errors.is_empty():
		return {
			"ok": false,
			"errors": social_reference_errors,
		}
	var prepared_conflict_controller: RefCounted = CONFLICT_CONTROLLER.new()
	var conflict_configuration := prepared_conflict_controller.configure(world,) as Dictionary
	if conflict_configuration.get("ok") != true:
		return {
			"ok": false,
			"errors": ["冲突与伤势状态无法配置"],
		}
	var conflict_state_value: Variant = prepared.get("conflictState")
	if conflict_state_value is Dictionary and not (
		conflict_state_value as Dictionary
	).is_empty():
		var conflict_restore := prepared_conflict_controller.restore_state(conflict_state_value as Dictionary,) as Dictionary
		if conflict_restore.get("ok") != true:
			return {
				"ok": false,
				"errors": ["conflictState 存档无法恢复"],
			}
	prepared["socialMattersPrepared"] = prepared_social_matters.create_save_snapshot(
	) as Dictionary
	prepared["communityBulletinPrepared"] = prepared_bulletin.create_save_snapshot(
	) as Dictionary
	prepared["animalFactsPrepared"] = prepared_animal_facts.duplicate(true)
	prepared["placeServiceStatesPrepared"] = (
		prepared_place_service_states.duplicate(true)
	)
	prepared["conflictControllerPrepared"] = prepared_conflict_controller
	return {
		"ok": true,
		"preparedState": prepared,
	}


static func _refresh_migrated_activity_action_routes(
	world_data: Dictionary,
	residents: Dictionary,
) -> void:
	for resident_value: Variant in residents.values():
		if not resident_value is Dictionary:
			continue
		var resident := resident_value as Dictionary
		var action_value: Variant = resident.get("currentAction", {})
		if not action_value is Dictionary:
			continue
		var action := action_value as Dictionary
		if (
			String(action.get("type", "")) != "用道具"
			or String(action.get("sourceContract", "")) not in [
				"agent.activity",
				"legacy.agent.use_prop",
				"activity.perform",
			]
		):
			continue
		var place_name := String(resident.get("currentPlace", ""))
		var prop_name := String(action.get("prop", ""))
		var action_verb := String(action.get("verb", ""))
		if place_name.is_empty() or prop_name.is_empty() or action_verb.is_empty():
			continue
		var path: Array[Vector2] = [
			resident.get("position", Vector2.ZERO) as Vector2,
		]
		for point_value: Variant in resident.get("routeConnector", []) as Array:
			if not point_value is Vector2:
				continue
			var connector_point := point_value as Vector2
			if not path[-1].is_equal_approx(connector_point):
				path.append(connector_point)
		var plan := PROP_QUERY.interaction_plan(
			world_data,
			place_name,
			prop_name,
			action_verb,
			path[-1],
		) as Dictionary
		if plan.is_empty():
			continue
		var approach := plan.get("approachPolyline", []) as Array
		for point_value: Variant in approach:
			if not point_value is Vector2:
				continue
			var point := point_value as Vector2
			if not path[-1].is_equal_approx(point):
				path.append(point)
		var return_connector := approach.duplicate()
		return_connector.reverse()
		action["pathPoints"] = path
		action["targetPosition"] = (
			plan.get("position", resident.get("position", Vector2.ZERO))
			as Vector2
		)
		action["dynamicPropId"] = String(plan.get("propId", ""))
		action["returnRouteConnector"] = return_connector
		action["pathClearanceVerified"] = true
		resident["currentAction"] = action


static func _validate_saved_history_times(
	state: Dictionary,
	current_absolute_minute: int,
) -> Array[String]:
	var errors: Array[String] = []
	var residents_value: Variant = state.get("residents")
	if residents_value is Array:
		for resident_index in (residents_value as Array).size():
			var resident_value: Variant = (residents_value as Array)[
				resident_index
			]
			if not resident_value is Dictionary:
				continue
			var resident := resident_value as Dictionary
			var arrival_value: Variant = resident.get("arrivalState")
			if arrival_value is Dictionary:
				var arrival := arrival_value as Dictionary
				var scheduled := int(
					arrival.get("scheduledAbsoluteMinute", -1),
				)
				var arrived := int(
					arrival.get("arrivedAbsoluteMinute", -1),
				)
				if (
					String(arrival.get("status", "")) == "pending"
					and scheduled <= current_absolute_minute
				):
					errors.append(
						"世界存档 residents[%d].arrivalState 已错过抵达时间"
						% resident_index,
					)
				if arrived > current_absolute_minute:
					errors.append(
						"世界存档 residents[%d].arrivalState.arrivedAbsoluteMinute 晚于恢复后的世界时间"
						% resident_index,
					)
			for key in ["pendingEvents", "pendingActionResults"]:
				var values: Variant = resident.get(key)
				if not values is Array:
					continue
				for value_index in (values as Array).size():
					var value: Variant = (values as Array)[value_index]
					if value is Dictionary:
						_append_future_time_error(
							(value as Dictionary).get("time"),
							"residents[%d].%s[%d].time"
							% [resident_index, key, value_index],
							current_absolute_minute,
							errors,
						)
			var preview_value: Variant = resident.get(
				"confirmedActionPreview"
			)
			if preview_value is Dictionary and not (
				preview_value as Dictionary
			).is_empty():
				_append_future_time_error(
					(preview_value as Dictionary).get("confirmedAt"),
					"residents[%d].confirmedActionPreview.confirmedAt"
					% resident_index,
					current_absolute_minute,
					errors,
				)
	for collection_case in [
		{"key": "announcements", "timeKeys": ["time"]},
		{
			"key": "conversations",
			"timeKeys": ["startedAt", "updatedAt", "endedAt"],
		},
		{"key": "eventLog", "timeKeys": ["time"]},
	]:
		var collection_key := String(collection_case["key"])
		var collection_value: Variant = state.get(collection_key)
		if not collection_value is Array:
			continue
		for value_index in (collection_value as Array).size():
			var value: Variant = (collection_value as Array)[value_index]
			if not value is Dictionary:
				continue
			for time_key_value: Variant in collection_case["timeKeys"] as Array:
				var time_key := String(time_key_value)
				if (value as Dictionary).has(time_key):
					_append_future_time_error(
						(value as Dictionary).get(time_key),
						"%s[%d].%s"
						% [collection_key, value_index, time_key],
						current_absolute_minute,
						errors,
					)
	return errors


static func _append_future_time_error(
	value: Variant,
	label: String,
	current_absolute_minute: int,
	errors: Array[String],
) -> void:
	var absolute_minute := _absolute_minute_if_valid(value)
	if absolute_minute > current_absolute_minute:
		errors.append(
			"世界存档 %s 晚于恢复后的世界时间"
			% label
		)


static func _absolute_minute_if_valid(value: Variant) -> int:
	if not SAVE_CODEC.validate_time_snapshot(value).is_empty():
		return -1
	var time := value as Dictionary
	var parts := String(time.get("clock", "")).split(":")
	return (
		(int(time.get("day", 1)) - 1) * 1440
		+ int(parts[0]) * 60
		+ int(parts[1])
	)


static func _validate_resident_action_times(
	world_data: Dictionary,
	residents: Dictionary,
	current_absolute_minute: int,
) -> Array[String]:
	var errors: Array[String] = []
	for resident_id_value: Variant in residents:
		var resident_id := String(resident_id_value)
		var resident := residents[resident_id_value] as Dictionary
		var current_action := resident.get("currentAction", {}) as Dictionary
		var suspended_minute := int(
			resident.get("actionSuspendedAbsoluteMinute", -1),
		)
		if suspended_minute > current_absolute_minute:
			errors.append(
				"世界存档居民 %s 的动作挂起时间晚于世界时间"
				% resident_id
			)
		var effective_absolute_minute := (
			suspended_minute
			if suspended_minute >= 0
			else current_absolute_minute
		)
		var started_absolute_minute := int(
			current_action.get("startedAbsoluteMinute", -1),
		)
		if (
			not current_action.is_empty()
			and started_absolute_minute > effective_absolute_minute
		):
			errors.append(
				"世界存档居民 %s 的当前动作开始时间晚于生效世界时间"
				% resident_id
			)
			continue
		if current_action.is_empty():
			continue
		var elapsed := effective_absolute_minute - started_absolute_minute
		var action_type := String(current_action.get("type", ""))
		if (
			action_type == "去"
			and elapsed >= int(current_action.get("durationMinutes", 0))
		):
			errors.append(
				"世界存档居民 %s 保留了已经到期的当前动作"
				% resident_id
			)
		elif action_type == "用道具":
			_validate_prop_action_progress(
				world_data,
				resident_id,
				resident,
				current_action,
				elapsed,
				errors,
			)
		elif (
			action_type == "待着"
			and effective_absolute_minute
			>= int(current_action.get("completeAbsoluteMinute", -1))
		):
			errors.append(
				"世界存档居民 %s 保留了已经到期的等待动作"
				% resident_id
			)
		if action_type == "去":
			var route := current_action.get("route", {}) as Dictionary
			var samples := route.get("minutePositions", []) as Array
			var sample_index := mini(elapsed, samples.size() - 1)
			if (
				sample_index < 0
				or not _resident_matches_route_sample(
					resident,
					samples[sample_index] as Dictionary,
				)
			):
				errors.append(
					"世界存档居民 %s 的位置与当前动作进度不一致"
					% resident_id
				)
	return errors


static func _validate_prop_action_progress(
	world_data: Dictionary,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	elapsed: int,
	errors: Array[String],
) -> void:
	var path_values := action.get("pathPoints", []) as Array
	var path: Array[Vector2] = []
	for value: Variant in path_values:
		if value is Vector2:
			path.append(value as Vector2)
	if path.size() != path_values.size() or path.is_empty():
		return
	var approach_duration := _prop_approach_duration_minutes(world_data, path)
	var total_duration := (
		approach_duration + int(action.get("durationMinutes", 0))
	)
	if elapsed >= total_duration:
		errors.append(
			"世界存档居民 %s 保留了已经到期的当前动作"
			% resident_id
		)
		return
	var ratio := (
		1.0
		if approach_duration <= 0
		else clampf(float(elapsed) / float(approach_duration), 0.0, 1.0)
	)
	var expected_position := _point_along_polyline(path, ratio)
	if (
		not resident.get("position") is Vector2
		or (resident.get("position") as Vector2).distance_to(
			expected_position,
		) > 0.01
	):
		errors.append(
			"世界存档居民 %s 的位置与道具动作进度不一致"
			% resident_id
		)


static func _prop_approach_duration_minutes(
	world_data: Dictionary,
	points: Array[Vector2],
) -> int:
	var distance := 0.0
	for index in range(1, points.size()):
		distance += points[index - 1].distance_to(points[index])
	if distance <= 0.000001:
		return 0
	var movement_rules := world_data.get("movementRules", {}) as Dictionary
	var distance_per_minute := float(
		movement_rules.get("outdoorDistancePerGameMinute", 0.0)
	)
	if distance_per_minute <= 0.0:
		return 1
	return maxi(1, ceili(distance / distance_per_minute))


static func _point_along_polyline(
	points: Array[Vector2],
	ratio: float,
) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	var target := total * clampf(ratio, 0.0, 1.0)
	var cursor := 0.0
	for index in range(1, points.size()):
		var length := points[index - 1].distance_to(points[index])
		if target <= cursor + length or index == points.size() - 1:
			var local_ratio := (
				0.0
				if length <= 0.000001
				else (target - cursor) / length
			)
			return points[index - 1].lerp(
				points[index],
				clampf(local_ratio, 0.0, 1.0),
			)
		cursor += length
	return points[-1]


static func _resident_matches_route_sample(
	resident: Dictionary,
	sample: Dictionary,
) -> bool:
	var point_value: Variant = sample.get("position")
	if not point_value is Dictionary or not resident.get("position") is Vector2:
		return false
	var point := point_value as Dictionary
	var expected_position := Vector2(
		float(point.get("x", NAN)),
		float(point.get("y", NAN)),
	)
	return (
		is_finite(expected_position.x)
		and is_finite(expected_position.y)
		and (resident.get("position") as Vector2).distance_to(
			expected_position,
		) <= 0.01
		and resident.get("spaceId") == sample.get("spaceId")
		and resident.get("regionId") == sample.get("regionId")
		and resident.get("currentPlace") == sample.get("placeName")
	)
