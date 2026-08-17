class_name TownWorldRestoreCommitProjection
extends RefCounted


const ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownWorldActivityRuntime.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const RESIDENT_LIFECYCLE_RUNTIME := preload(
	"res://world/runtime/lifecycle/TownResidentLifecycleRuntime.gd"
)
const RESIDENT_RUNTIME_FACTORY := preload(
	"res://world/runtime/lifecycle/TownResidentRuntimeFactory.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)


static func commit_context(
	candidate: Dictionary,
	player_avatar_present: bool,
) -> Dictionary:
	var world_data := candidate.get("worldData", {}) as Dictionary
	var prepared := candidate.get("preparedState", {}) as Dictionary
	var activity_runtime: TownWorldActivityRuntime = ACTIVITY_RUNTIME.new()
	activity_runtime.configure(world_data)
	return {
		"worldData": world_data,
		"openingConfig": candidate.get("openingConfig", {}) as Dictionary,
		"preparedIdentities": candidate.get("preparedIdentities", {}) as Dictionary,
		"prepared": prepared,
		"preparedWorldLog": candidate.get("preparedWorldLog"),
		"activityRuntime": activity_runtime,
		"playerAvatarPresent": player_avatar_present,
	}


static func summary(
	schema_version: int,
	resident_count: int,
	simulation_speed: int,
	identity_status: String,
	time: Dictionary,
	weather: String,
	lifecycle: Dictionary,
	world_revision: int,
) -> Dictionary:
	return {
		"schemaVersion": schema_version,
		"residentCount": resident_count,
		"residentRelocationRequired": true,
		"simulationSpeed": simulation_speed,
		"identityStatus": identity_status,
		"time": time.duplicate(true),
		"weather": weather,
		"lifecycle": lifecycle.duplicate(true),
		"worldRevision": world_revision,
	}


static func prepare_people_install(
	world_data: Dictionary,
	residents: Dictionary,
	prepared: Dictionary,
	work_domain,
	activity_runtime,
) -> Dictionary:
	var resident_lifecycle = RESIDENT_LIFECYCLE_RUNTIME.new()
	for resident_value: Variant in residents.values():
		var resident := resident_value as Dictionary
		var profile_attributes := resident.get("profileAttributes", {}) as Dictionary
		var runtime_attributes := resident.get("attributes", {}) as Dictionary
		resident_lifecycle.initialize_resident(
			String(resident.get("residentId", "")),
			String(resident.get("name", profile_attributes.get(
				"name",
				runtime_attributes.get("name", ""),
			))),
			RESIDENT_RUNTIME_FACTORY.home_anchor(world_data, resident),
		)
	resident_lifecycle.restore_save_snapshot(
		prepared.get("residentLifecyclePrepared", {}) as Dictionary,
	)
	work_domain.reset_staffing()
	work_domain.staffing.configure(world_data)
	var staffing_state := prepared.get("staffingStatePrepared", {}) as Dictionary
	var living_residents := prepared.get(
		"livingResidentsPrepared",
		residents,
	) as Dictionary
	var absolute_minute := int(
		prepared.get("environment").get_absolute_minute(),
	)
	if staffing_state.is_empty():
		work_domain.staffing.rebuild(living_residents, absolute_minute)
	else:
		work_domain.staffing.restore_persistent_snapshot(
			staffing_state,
			living_residents,
			absolute_minute,
		)
	for resident_value: Variant in residents.values():
		var resident := resident_value as Dictionary
		var activity_state := resident.get("activityState") as Dictionary
		if activity_state == null:
			activity_state = ACTIVITY_SCALARS.activity_state_from_body(
				resident.get("body", {}) as Dictionary,
			)
		ACTIVITY_SCALARS.sync_body_from_activity_needs(resident, activity_state)
	activity_runtime.apply_prepared_restore(
		prepared.get("activityRuntimePrepared", {}) as Dictionary,
	)
	return {
		"residentLifecycle": resident_lifecycle,
		"activityRoutines": (
			(prepared.get("activityRoutinesPrepared", {}) as Dictionary).get(
				"routinesByResident",
				{},
			) as Dictionary
		).duplicate(true),
		"activityWorkTaskBindings": (
			prepared.get("activityWorkTaskBindingsPrepared", {}) as Dictionary
		).duplicate(true),
	}


static func active_resident_conversation_idle_seconds(
	world,
	conversations: Dictionary,
) -> Dictionary:
	var result := {}
	for conversation_id_value: Variant in conversations:
		var conversation_id := String(conversation_id_value)
		var conversation := conversations[conversation_id] as Dictionary
		if (
			String(conversation.get("status", "")) == "active"
			and CONVERSATION_RUNTIME._is_resident_only_conversation(
				world,
				conversation,
			)
		):
			result[conversation_id] = 0.0
	return result


static func prepare_residents_for_restart(
	residents: Dictionary,
	resident_order: Array[String],
) -> Array[String]:
	var result: Array[String] = []
	for resident_id in resident_order:
		var resident := residents[resident_id] as Dictionary
		# 旧存档可能带有并发预览；已确认行动本身仍保留，只清表现瞬态。
		resident["confirmedActionPreview"] = {}
		var restored_action := resident.get("currentAction", {}) as Dictionary
		if ACTION_VALIDATION.is_continuity_wait_action(restored_action):
			resident["currentAction"] = {}
			resident["actionSuspendedAbsoluteMinute"] = -1
			resident["doing"] = "正在重新安排接下来的事"
		result.append(resident_id)
	return result
