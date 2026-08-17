class_name TownConfirmedActionActivationPolicy
extends RefCounted


const ACTION_PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const CONFLICT_ACTION_TYPES := [
	"争执",
	"攻击",
	"回应冲突",
	"介入冲突",
	"离开冲突",
]


static func route_kind(action: Dictionary) -> String:
	var action_type := String(action.get("type", ""))
	if (
		action_type == "用道具"
		and String(action.get("dynamicPropId", "")).is_empty()
	):
		return "legacy_prop_activity"
	if action_type == "做活动":
		return "agent_activity"
	if action_type in CONFLICT_ACTION_TYPES:
		return "conflict"
	return "regular"


static func submitted_action(
	preview: Dictionary,
	confirmed_action: Dictionary,
) -> Dictionary:
	return (
		preview.get(
			"submittedAction",
			ACTION_PROJECTION.submitted_action_for_preview(confirmed_action),
		) as Dictionary
	).duplicate(true)


static func activate_resident(
	resident: Dictionary,
	action: Dictionary,
	doing: String,
) -> void:
	resident["currentAction"] = action
	if bool(action.get("consumeRouteConnector", false)):
		# A connector belongs only to the resident's current indoor anchor.
		resident["routeConnector"] = []
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = doing
