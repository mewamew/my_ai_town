class_name TownWorldSaveCommandRuntime
extends RefCounted


const SAVE_SNAPSHOT_PROJECTION := preload(
	"res://world/runtime/persistence/TownWorldSaveSnapshotProjection.gd"
)
const ACTION_PREVIEW_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreviewRuntime.gd"
)


static func create_snapshot(host) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	ACTION_PREVIEW_RUNTIME.release_observed(host)
	var interrupted_results: Array[Dictionary] = (
		host._activity_runtime.reconcile_activity_routines_before_save(
			host.activity_routine_state.records,
			host.resident_registry.records,
			host.ACTION_PROJECTION_MODULE.ACTIVITY_SOURCE_DIRECT,
		) as Array[Dictionary]
	)
	for result: Dictionary in interrupted_results:
		host._append_action_result_without_schedule(
			String(result.get("residentId", "")),
			String(result.get("actionId", "")),
			String(result.get("status", "interrupted")),
			String(result.get("reason", "")),
		)
	SAVE_SNAPSHOT_PROJECTION.sync_activity_save_state(
		host,
		host.resident_registry.records,
		host.resident_registry.order,
		int(host._environment.get_absolute_minute()),
		host._activity_runtime,
	)
	return host._decorate_command_result(SAVE_SNAPSHOT_PROJECTION.capture({
		"worldData": host.world_definition.world_data,
		"savedAt": host.get_time(),
		"environment": host._environment,
		"owners": host.world_definition.owners.duplicate(true),
		"residents": host.resident_registry.records,
		"residentOrder": host.resident_registry.order,
		"playerAvatar": host.actor_presentation_state.player_avatar.duplicate(true),
		"announcementHistoryLimit": host.MAX_ANNOUNCEMENT_HISTORY,
		"communityBulletin": host._community_bulletin,
		"conversations": host.conversation_state.records,
		"eventJournal": host.world_log_domain.journal,
		"activityRuntime": host._activity_runtime,
		"activityRoutines": host.activity_routine_state.records,
		"workDomain": host._work,
		"privateMessageRuntime": host.private_message_runtime,
		"activityWorkTaskBindings": host.activity_work_task_bindings,
		"socialMatters": host._social_matters,
		"animalFacts": host._animal_fact_runtime,
		"residentConditions": host._resident_conditions,
		"residentSleep": host._resident_sleep,
		"conflictController": host._conflict_controller,
		"residentLifecycle": host._resident_lifecycle,
		"travelerRelationships": host._traveler_relationship_state,
		"dynamicProps": host._dynamic_prop_runtime,
		"conversationSequence": host.conversation_state.sequence,
		"worldRevision": host._world_revision,
	}))


static func restore_snapshot(
	host,
	world_data: Dictionary,
	opening_config: Dictionary,
	snapshot: Dictionary,
	resident_identities: Variant = [],
) -> Dictionary:
	var preparation: Dictionary = host.prepare_restore_candidate(
		world_data,
		opening_config,
		snapshot,
		resident_identities,
		false,
	)
	if preparation.get("ok") != true:
		return preparation
	var token := String(
		(preparation.get("candidate", {}) as Dictionary).get("token", ""),
	)
	var result: Dictionary = host.commit_restore_candidate(token)
	if result.get("ok") == true:
		host.cleanup_restore_candidate(token)
	else:
		host.abort_restore_candidate(token)
	return result
