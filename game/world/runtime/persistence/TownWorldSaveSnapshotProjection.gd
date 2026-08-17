class_name TownWorldSaveSnapshotProjection
extends RefCounted


const SAVE_CODEC := preload(
	"res://world/runtime/persistence/TownWorldSaveCodec.gd"
)
const RESIDENT_EVENT_QUEUE_RUNTIME := preload(
	"res://world/runtime/event/TownResidentEventQueueRuntime.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const RESIDENT_PROFILE_EDITOR := preload(
	"res://world/runtime/presentation/TownResidentProfileEditor.gd"
)


static func capture(context: Dictionary) -> Dictionary:
	var work = context.get("workDomain")
	var bulletin = context.get("communityBulletin")
	var event_journal = context.get("eventJournal")
	var activity_runtime = context.get("activityRuntime")
	var private_message_runtime = context.get("privateMessageRuntime")
	var social_matters = context.get("socialMatters")
	var animal_facts = context.get("animalFacts")
	var resident_conditions = context.get("residentConditions")
	var resident_sleep = context.get("residentSleep")
	var resident_lifecycle = context.get("residentLifecycle")
	var traveler_relationships = context.get("travelerRelationships")
	var dynamic_props = context.get("dynamicProps")
	var conflict_controller = context.get("conflictController")
	var state := {
		"environment": context.get("environment").create_save_snapshot() as Dictionary,
		"owners": (context.get("owners", {}) as Dictionary).duplicate(true),
		"residents": resident_snapshots(
			context.get("residentOrder", []) as Array[String],
			context.get("residents", {}) as Dictionary,
		),
		"playerAvatar": (
			context.get("playerAvatar", {}) as Dictionary
		).duplicate(true),
		"announcements": bulletin.legacy_broadcast_snapshot(
			int(context.get("announcementHistoryLimit", 64)),
		),
		"conversations": conversation_snapshots(
			context.get("conversations", {}) as Dictionary,
		),
		"eventLog": event_journal.public_events(),
		"activityRuntime": (
			activity_runtime.create_save_snapshot() as Dictionary
		).duplicate(true),
		"activityRoutines": activity_routines_snapshot(
			context.get("activityRoutines", {}) as Dictionary,
		),
		"workTasks": work.tasks.create_save_snapshot() as Dictionary,
		"staffingState": work.staffing.persistent_snapshot() as Dictionary,
		"cargoInventory": work.cargo.snapshot() as Dictionary,
		"productionState": work.production.snapshot() as Dictionary,
		"occupationServices": work.services.snapshot() as Dictionary,
		"privateMessages": private_message_runtime.create_save_snapshot(work.tasks),
		"activityWorkTaskBindings": context.get("activityWorkTaskBindings").snapshot(),
		"socialMatters": social_matters.create_save_snapshot() as Dictionary,
		"communityBulletin": bulletin.create_save_snapshot() as Dictionary,
		"animalFacts": animal_facts.save_snapshot(),
		"placeServiceStates": work.place_services.save_snapshot(),
		"residentConditions": resident_conditions.create_save_snapshot() as Dictionary,
		"residentSleep": resident_sleep.create_save_snapshot() as Dictionary,
		"conflictState": (
			conflict_controller.export_state() as Dictionary
			if conflict_controller != null
			else {}
		),
		"residentLifecycle": resident_lifecycle.create_save_snapshot() as Dictionary,
		"travelerRelations": traveler_relationships.snapshot(),
		"indoorLayoutOverrides": dynamic_props.layout_override_snapshots(),
		"sequences": {
			"event": event_journal.event_sequence(),
			"announcement": bulletin.announcement_sequence(),
			"conversation": int(context.get("conversationSequence", 0)),
			"worldRevision": int(context.get("worldRevision", 0)),
		},
	}
	if not SAVE_CODEC.has_exact_string_keys(
		state,
		SAVE_CODEC.STATE_KEYS + SAVE_CODEC.OPTIONAL_STATE_KEYS,
	):
		return _failure(["世界快照键集合与 SaveCodec 域清单不一致"])
	var encoded_state := SAVE_CODEC.encode_checked(state) as Dictionary
	if encoded_state.get("ok") != true:
		return _failure(
			(encoded_state.get(
				"errors",
				["世界状态包含不能序列化的数据"],
			) as Array).duplicate(),
		)
	var world_data := context.get("worldData", {}) as Dictionary
	return {
		"ok": true,
		"snapshot": {
			"schema": SAVE_CODEC.SCHEMA,
			"schemaVersion": SAVE_CODEC.SCHEMA_VERSION,
			"worldId": String(world_data.get("worldId", "")),
			"worldDataSchemaVersion": int(world_data.get("schemaVersion", 0)),
			"worldDataVersion": int(world_data.get("dataVersion", 0)),
			"savedAt": (context.get("savedAt", {}) as Dictionary).duplicate(true),
			"state": encoded_state.get("value", {}),
		},
	}


static func sync_activity_save_state(
	world,
	residents: Dictionary,
	resident_order: Array[String],
	absolute_minute: int,
	activity_runtime,
) -> void:
	for resident_id in resident_order:
		var resident := residents[resident_id] as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		var execution := activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if execution.is_empty():
			continue
		var suspended_minute := int(
			resident.get("actionSuspendedAbsoluteMinute", -1),
		)
		var effective_minute := (
			suspended_minute if suspended_minute >= 0 else absolute_minute
		)
		var elapsed := maxi(
			0,
			effective_minute - int(
				action.get("startedAbsoluteMinute", effective_minute),
			),
		)
		activity_runtime.sync_remaining_ticks(
			resident_id,
			maxi(
				0,
				ACTION_SUPPORT.prop_approach_duration_minutes(world, action)
					+ int(action.get("durationMinutes", 0))
					- elapsed,
			),
		)


static func resident_snapshots(
	resident_order: Array[String],
	residents: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_id in resident_order:
		result.append(_resident_snapshot(
			resident_id,
			residents[resident_id] as Dictionary,
		))
	return result


static func conversation_snapshots(conversations: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var conversation_ids: Array[String] = []
	for conversation_id_value: Variant in conversations:
		conversation_ids.append(String(conversation_id_value))
	conversation_ids.sort()
	for conversation_id in conversation_ids:
		result.append((conversations[conversation_id] as Dictionary).duplicate(true))
	return result


static func activity_routines_snapshot(routines_by_resident: Dictionary) -> Dictionary:
	var routines: Array[Dictionary] = []
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in routines_by_resident:
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	for resident_id in resident_ids:
		var routine := (
			routines_by_resident[resident_id] as Dictionary
		).duplicate(true)
		routine["residentId"] = resident_id
		routines.append(routine)
	return {"schemaVersion": 1, "routines": routines}


static func _resident_snapshot(
	resident_id: String,
	resident: Dictionary,
) -> Dictionary:
	var pending_events := RESIDENT_EVENT_QUEUE_RUNTIME.deduplicated_world_events(
		(resident.get("inflightEvents", []) as Array).duplicate(true),
	)
	pending_events.append_array((resident.get("eventQueue", []) as Array).duplicate(true))
	pending_events = RESIDENT_EVENT_QUEUE_RUNTIME.deduplicated_world_events(pending_events)
	var pending_results := (resident.get("inflightResults", []) as Array).duplicate(true)
	pending_results.append_array((resident.get("resultQueue", []) as Array).duplicate(true))
	pending_results = ACTION_VALIDATION.deduplicated_action_results(pending_results)
	var used_action_ids: Array = (resident.get("usedActionIds", {}) as Dictionary).keys()
	used_action_ids.sort()
	return {
		"residentId": resident_id,
		"name": String((resident.get("attributes", {}) as Dictionary).get("name", "")),
		"movementRevision": int(resident.get("movementRevision", 1)),
		"profileAttributes": RESIDENT_PROFILE_EDITOR.saved_attributes(
			resident.get("attributes", {}) as Dictionary,
		),
		"socialState": (resident.get("socialState", {}) as Dictionary).duplicate(true),
		"arrivalState": (
			resident.get("arrivalState", {
				"status": "arrived",
				"scheduledAbsoluteMinute": -1,
				"arrivedAbsoluteMinute": -1,
			}) as Dictionary
		).duplicate(true),
		"position": resident.get("position", Vector2.ZERO),
		"spaceId": String(resident.get("spaceId", "")),
		"regionId": String(resident.get("regionId", "")),
		"currentPlace": String(resident.get("currentPlace", "")),
		"doing": String(resident.get("doing", "")),
		"body": (resident.get("body", {}) as Dictionary).duplicate(true),
		"activityState": (
			resident.get("activityState", ACTIVITY_SCALARS.empty_activity_state()) as Dictionary
		).duplicate(true),
		"attendanceState": (
			resident.get("attendanceState", {
				"status": "available",
				"untilMinute": -1,
			}) as Dictionary
		).duplicate(true),
		"currentAction": (resident.get("currentAction", {}) as Dictionary).duplicate(true),
		"confirmedActionPreview": {},
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


static func _duplicate_optional_dictionary(value: Variant) -> Variant:
	return (value as Dictionary).duplicate(true) if value is Dictionary else null


static func _failure(errors: Array) -> Dictionary:
	return {
		"ok": false,
		"errorCode": "SAVE_SERIALIZATION_FAILED",
		"errors": errors.duplicate(true),
	}
