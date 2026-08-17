class_name TownResidentRuntimeFactory
extends RefCounted


const AGENT_WAKE_STATE_RUNTIME := preload(
	"res://world/runtime/TownAgentWakeStateRuntime.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)


static func create(
	record: Dictionary,
	world_state: Dictionary,
	resident_id := "",
) -> Dictionary:
	var pair := world_state.get("position", []) as Array
	var body := (world_state.get("body", {}) as Dictionary).duplicate(true)
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
		"activityState": ACTIVITY_SCALARS.activity_state_from_body(body),
		"attendanceState": {"status": "available", "untilMinute": -1},
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


static func home_anchor(
	world_data: Dictionary,
	resident: Dictionary,
) -> Dictionary:
	var home_place := String(
		(resident.get("socialState", {}) as Dictionary).get("home", ""),
	).strip_edges()
	if not home_place.is_empty():
		for prop_value: Variant in world_data.get("props", []) as Array:
			if prop_value is not Dictionary:
				continue
			var prop := prop_value as Dictionary
			var interaction := prop.get("interaction", {}) as Dictionary
			var actions := prop.get("actions", []) as Array
			var action_verb := ""
			if not actions.is_empty() and actions[0] is Dictionary:
				action_verb = String((actions[0] as Dictionary).get("verb", ""))
			if (
				String(prop.get("placeName", "")) != home_place
				or action_verb != "睡觉"
				or interaction.get("position") is not Array
			):
				continue
			var pair := interaction.get("position", []) as Array
			if pair.size() == 2:
				return {
					"spaceId": String(interaction.get("spaceId", "")),
					"regionId": String(interaction.get("regionId", "")),
					"placeName": home_place,
					"position": Vector2(float(pair[0]), float(pair[1])),
				}
		for connection_value: Variant in world_data.get("connections", []) as Array:
			if connection_value is not Dictionary:
				continue
			var connection := connection_value as Dictionary
			for endpoint_key in ["from", "to"]:
				var endpoint := connection.get(endpoint_key, {}) as Dictionary
				if String(endpoint.get("placeName", "")) == home_place:
					return ACTION_SUPPORT.connection_anchor(endpoint)
	return {
		"spaceId": String(resident.get("spaceId", "")),
		"regionId": String(resident.get("regionId", "")),
		"placeName": String(resident.get("currentPlace", home_place)),
		"position": resident.get("position", Vector2.ZERO) as Vector2,
	}
