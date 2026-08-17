class_name TownWorldRestoreCommitRuntime
extends RefCounted


const RESTORE_COMMIT_PROJECTION := preload(
	"res://world/runtime/persistence/TownWorldRestoreCommitProjection.gd"
)
const WORK_TASK_RUNTIME := preload(
	"res://world/runtime/work/TownWorkTaskRuntime.gd"
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
const CLINIC_INTERVIEW_POLICY := preload(
	"res://world/runtime/condition/TownClinicInterviewPolicy.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const WORLD_LOG_STORE := preload(
	"res://world/runtime/log/TownWorldLogStore.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const SAVE_CODEC := preload(
	"res://world/runtime/persistence/TownWorldSaveCodec.gd"
)


static func commit_candidate(
	host,
	token: String,
	player_avatar_present: bool,
	person_name_lookup: Callable,
) -> Dictionary:
	var commit_preparation := host._restore_candidate_runtime.begin_commit(
		token,
		host._runtime_generation,
		host._world_revision,
	) as Dictionary
	if commit_preparation.get("ok") != true:
		return host._decorate_command_result(commit_preparation)
	if bool(commit_preparation.get("alreadyCommitted", false)):
		commit_preparation.erase("alreadyCommitted")
		return host._decorate_command_result(commit_preparation)
	var candidate := commit_preparation.get("candidateState", {}) as Dictionary
	var summary := apply(
		host,
		candidate,
		player_avatar_present,
		person_name_lookup,
	)
	var receipt := {
		"token": token.strip_edges(),
		"runtimeGeneration": host._runtime_generation,
		"worldRevision": host._world_revision,
		"identitySnapshot": host.get_resident_identity_snapshot(),
	}
	return host._decorate_command_result(
		host._restore_candidate_runtime.complete_commit(
			token,
			host._runtime_generation,
			host._world_revision,
			summary,
			receipt,
		)
	)


static func apply(
	host,
	candidate: Dictionary,
	player_avatar_present: bool,
	person_name_lookup: Callable,
) -> Dictionary:
	var context := RESTORE_COMMIT_PROJECTION.commit_context(
		candidate,
		player_avatar_present,
	)
	install_core(host, context)
	install_people(host, context)
	var social_failure := install_social_and_conflict(
		host,
		context,
		person_name_lookup,
	)
	if not social_failure.is_empty():
		return social_failure
	return finish(host, context)


static func install_core(host, context: Dictionary) -> void:
	var world_data := context.get("worldData", {}) as Dictionary
	var prepared := context.get("prepared", {}) as Dictionary
	var restored_work_tasks := prepared.get("workTasksPrepared") as WORK_TASK_RUNTIME
	var restored_cargo_inventory := prepared.get("cargoInventoryPrepared") as CARGO_INVENTORY_RUNTIME
	var restored_production := prepared.get("productionStatePrepared") as PRODUCTION_RUNTIME
	var restored_occupation_services := prepared.get("occupationServicesPrepared") as OCCUPATION_SERVICE_RUNTIME
	var restored_resident_conditions := prepared.get("residentConditionsPrepared") as TownResidentConditionRuntime
	var restored_resident_sleep := prepared.get("residentSleepPrepared") as TownResidentSleepRuntime
	host._running = false
	host._activity_runtime.close()
	host._activity_runtime = context.get("activityRuntime") as TownWorldActivityRuntime
	host._disconnect_work_task_log_source()
	host._work.install_restored_state(
		restored_work_tasks,
		restored_cargo_inventory,
		restored_production,
		restored_occupation_services,
	)
	host._resident_conditions = restored_resident_conditions
	host._resident_sleep = restored_resident_sleep
	host._clinic_interviews = CLINIC_INTERVIEW_POLICY.new()
	host.private_message_runtime.restore_prepared(
		prepared.get("privateMessagesPrepared", {}) as Dictionary,
	)
	host._pause_reasons.clear()
	context["speedWasReset"] = host._simulation_speed != 1
	host._simulation_speed = 1
	host._runtime_generation += 1
	host.world_definition.world_data = (
		prepared.get("worldData", world_data) as Dictionary
	).duplicate(true)
	host.world_definition.base_world_data = world_data.duplicate(true)
	host.place_presentation_query.clear_cache()
	host.activity_reachability_state.clear()
	PERCEPTION_RUNTIME._rebuild_membership_grid_lookup(host)
	host._dynamic_prop_runtime.reset()
	host._agent_wake_preparation_runtime.clear()
	host._animal_fact_runtime.restore_prepared(
		prepared.get("animalFactsPrepared", {}) as Dictionary,
	)
	host._work.place_services.restore_prepared(
		prepared.get("placeServiceStatesPrepared", {}) as Dictionary,
	)
	host._dynamic_prop_runtime.restore_layout_overrides(
		prepared.get("indoorLayoutOverrides", []) as Array,
	)
	host.world_definition.opening = (
		context.get("openingConfig", {}) as Dictionary
	).duplicate(true)
	host.world_definition.owners = (prepared.get("owners", {}) as Dictionary).duplicate(true)
	host.resident_registry.records = (prepared.get("residents", {}) as Dictionary).duplicate(true)


static func install_people(host, context: Dictionary) -> void:
	var prepared := context.get("prepared", {}) as Dictionary
	var people_install := RESTORE_COMMIT_PROJECTION.prepare_people_install(
		context.get("worldData", {}) as Dictionary,
		host.resident_registry.records,
		prepared,
		host._work,
		host._activity_runtime,
	)
	host._resident_lifecycle = people_install.get("residentLifecycle")
	host.activity_routine_state.restore(
		people_install.get("activityRoutines", {}) as Dictionary,
	)
	DINING_SERVICE.backfill_meal_period_refs(
		host,
		host.activity_routine_state.records,
		host.resident_registry.records,
	)
	host.activity_work_task_bindings.restore(
		people_install.get("activityWorkTaskBindings", {}) as Dictionary,
	)
	host.resident_registry.order.clear()
	for resident_name_value: Variant in prepared.get("residentOrder", []) as Array:
		host.resident_registry.order.append(String(resident_name_value))
	host.resident_registry.install_identities(
		context.get("preparedIdentities", {}) as Dictionary,
	)
	host.actor_presentation_state.player_avatar = (
		prepared.get("playerAvatar", {}) as Dictionary
	).duplicate(true)
	host.actor_presentation_state.player_avatar_present = bool(context.get("playerAvatarPresent", false))
	host._traveler_relationship_state.restore(
		prepared.get("travelerRelations", {}),
		host.player_avatar_id(),
		host.resident_registry.order,
	)


static func install_social_and_conflict(
	host,
	context: Dictionary,
	person_name_lookup: Callable,
) -> Dictionary:
	var prepared := context.get("prepared", {}) as Dictionary
	var prepared_world_log_value: Variant = context.get("preparedWorldLog")
	host._reset_social_runtimes()
	host._social_matters.restore_save_snapshot(
		prepared.get("socialMattersPrepared", {}) as Dictionary,
	)
	host._community_bulletin.restore_save_snapshot(
		prepared.get("communityBulletinPrepared", {}) as Dictionary,
	)
	var prepared_conversations := (
		prepared.get("conversations", {}) as Dictionary
	).duplicate(true)
	var conversation_idle_seconds := (
		RESTORE_COMMIT_PROJECTION.active_resident_conversation_idle_seconds(
			host,
			prepared_conversations,
		)
	)
	var prepared_sequences := prepared.get("sequences", {}) as Dictionary
	host.conversation_state.restore(
		prepared_conversations,
		conversation_idle_seconds,
		int(prepared_sequences.get("conversation", 0)),
	)
	host.actor_presentation_state.observed_action_preview_resident_id = ""
	host.world_log_domain.journal.restore_public_events(prepared.get("eventLog", []) as Array)
	if prepared_world_log_value is RefCounted:
		host.world_log_domain.store = prepared_world_log_value as RefCounted
	else:
		host.world_log_domain.store = WORLD_LOG_STORE.new()
		host.world_log_domain.store.migrate_legacy_world_state(prepared)
	host.world_log_domain.journal.clear_consistency_error()
	host.world_log_domain.capture_enabled = false
	host.world_log_domain.journal.rebuild_story_contexts()
	CONVERSATION_RUNTIME._trim_ended_conversation_history(host)
	host._environment = prepared.get("environment") as TownWorldEnvironment
	host._disconnect_conflict_controller_signals()
	host._conflict_controller = (
		prepared.get("conflictControllerPrepared") as TownConflictWorldController
	)
	var bridge_configuration := host._conflict_agent_world_bridge.configure(
		host._conflict_controller,
		person_name_lookup,
	) as Dictionary
	if bridge_configuration.get("ok") != true:
		return host._command_failure(
			String(bridge_configuration.get("errorCode", "CONFLICT_BRIDGE_CONFIG_INVALID")),
			["冲突 Agent/World 接线无法恢复"],
		)
	host._connect_conflict_controller_signals()
	var sequences := prepared.get("sequences", {}) as Dictionary
	host.world_log_domain.journal.set_event_sequence(int(sequences.get("event", 0)))
	host._world_revision = maxi(
		host._world_revision,
		int(sequences.get("worldRevision", 0)),
	)
	host._bump_world_revision(false)
	return {}


static func finish(host, context: Dictionary) -> Dictionary:
	PERCEPTION_RUNTIME._refresh_perception(
		host,
		false,
		host._traveler_relationship_state,
	)
	host._begin_world_run()
	for resident_name: String in RESTORE_COMMIT_PROJECTION.prepare_residents_for_restart(
		host.resident_registry.records,
		host.resident_registry.order,
	):
		# 网络中的 Agent 请求不进入存档；恢复后按当前快照重新唤醒。
		host._schedule_decision(resident_name, false, false, false, true)
	host._assert_subsystems_installed("restore")
	var lifecycle: Dictionary = host.get_lifecycle_state()
	var summary := RESTORE_COMMIT_PROJECTION.summary(
		SAVE_CODEC.SCHEMA_VERSION,
		host.resident_registry.order.size(),
		host._simulation_speed,
		host.resident_registry.identity_status,
		host.get_time(),
		host.get_weather(),
		lifecycle,
		host._world_revision,
	)
	host._notify_world_revision()
	if bool(context.get("speedWasReset", false)):
		host.simulation_speed_changed.emit(
			host._simulation_speed,
			host._world_revision,
		)
	host.lifecycle_state_changed.emit(lifecycle.duplicate(true))
	host.conflict_projection_changed.emit(
		host.get_public_conflict_projection(),
	)
	host.world_restored.emit(summary.duplicate(true))
	return summary
