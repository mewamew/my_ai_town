class_name TownGoActionAdvancementRuntime
extends RefCounted

const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)


const CONVERSATION_FOLLOW_UP_ACTION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpActionRuntime.gd"
)
const CARGO_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownCargoCommandRuntime.gd"
)


static func advance(
	host,
	resident_name: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> void:
	if CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.timed_out(
		host, resident_name, action, absolute_minute,
	):
		return
	if (
		String(action.get("conversationFollowUpMode", "")) == "escort_follower"
		and CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.hold_resident_follower(
			host, resident_name, resident, action, absolute_minute,
		)
	):
		return
	if (
		String(action.get("conversationFollowUpMode", "")) == "escort"
		and String(action.get("followUpPhase", "")) == "leading"
		and CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.hold_or_return_for_companion(
			host, resident_name, resident, action, absolute_minute,
		)
	):
		return
	if host.PLACE_SERVICE_COMMAND_RUNTIME.closed_for_visitor(host, resident, String(action.get("place", ""))):
		var closed_reason := "%s今天没有营业，没能进去" % String(action.get("place", ""))
		if String(action.get("conversationFollowUpMode", "")).is_empty():
			host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_name, closed_reason)
		else:
			CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.begin_reconsideration(
				host, resident_name, closed_reason,
			)
		return
	var elapsed := maxi(0, absolute_minute - int(action.get("startedAbsoluteMinute", absolute_minute)))
	var route := action.get("route", {}) as Dictionary
	var positions := route.get("minutePositions", []) as Array
	var duration := int(action.get("durationMinutes", 0))
	var sample_index := mini(elapsed, positions.size() - 1)
	if sample_index >= 0:
		var previous_place := String(resident.get("currentPlace", ""))
		var position_changed: bool = host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_route_sample(host,
			resident,
			positions[sample_index] as Dictionary,
		)
		host.RESIDENT_POSITION_COMMIT_RUNTIME.emit_place_change(host, resident_name, previous_place)
		if position_changed:
			var probe_emit_usec := Time.get_ticks_usec() if host.telemetry.advance_profile_enabled else 0
			host._emit_resident_state_changed(resident_name)
			host.telemetry.lap(
				host.telemetry.advance_profile_scratch,
				"actionsGoEmitUsec",
				probe_emit_usec,
			)
			host.telemetry.count_advance_profile("actionsGoEmitCount", 1)
	if elapsed >= duration:
		ACTIVITY_SCALARS.apply_body_effects(
			resident,
			action.get("completionEffects", {}) as Dictionary,
			host.BODY_LEVELS,
		)
		CARGO_COMMAND_RUNTIME.settle_arrival(host, resident_name)
		host.RESIDENT_CONDITION_SETTLEMENT_RUNTIME.settle_route(host,
			resident_name,
			resident,
			action,
			"completed",
		)
		host.ACTION_SETTLEMENT_RUNTIME.finish(host,
			resident_name,
			"已到达%s" % String(action.get("place", "")),
		)
