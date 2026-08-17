class_name TownResidentPositionCommitRuntime
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const MOVEMENT_CLEARANCE_RUNTIME := preload(
	"res://world/runtime/TownMovementClearanceRuntime.gd"
)


static func apply_player_avatar_state(
	host,
	space_id: String,
	membership: Dictionary,
	position: Vector2,
	doing: String,
	command: String,
) -> Dictionary:
	var previous_space_id := String(host.actor_presentation_state.player_avatar.get("spaceId", ""))
	var previous_region_id := String(host.actor_presentation_state.player_avatar.get("regionId", ""))
	var previous_place := String(host.actor_presentation_state.player_avatar.get("currentPlace", ""))
	var previous_position := host.actor_presentation_state.player_avatar.get("position", Vector2.ZERO) as Vector2
	host.actor_presentation_state.player_avatar["position"] = position
	host.actor_presentation_state.player_avatar["spaceId"] = space_id
	host.actor_presentation_state.player_avatar["regionId"] = String(membership.get("regionId", ""))
	host.actor_presentation_state.player_avatar["currentPlace"] = String(membership.get("placeName", ""))
	if not doing.strip_edges().is_empty():
		host.actor_presentation_state.player_avatar["doing"] = doing.strip_edges()
	var current_place := String(host.actor_presentation_state.player_avatar.get("currentPlace", ""))
	var semantic_state_changed := (
		String(host.actor_presentation_state.player_avatar.get("spaceId", "")) != previous_space_id
		or String(host.actor_presentation_state.player_avatar.get("regionId", "")) != previous_region_id
		or current_place != previous_place
	)
	var avatar_position_changed := previous_position != position
	if semantic_state_changed:
		host._bump_world_revision(false)
	var perception_changed: bool = PERCEPTION_RUNTIME._refresh_player_avatar_perception(
		host,
		host._traveler_relationship_state,
		true,
		not semantic_state_changed,
		semantic_state_changed,
		avatar_position_changed,
	)
	var state: Dictionary = host.get_player_avatar_state()
	host.player_avatar_state_changed.emit(state)
	if current_place != previous_place:
		var place_change := {
			"from": previous_place,
			"to": current_place,
			"time": host.get_time(),
			"state": state.duplicate(true),
		}
		WORLD_LOG_COMMIT_RUNTIME.append_public(
			host,
			host.world_log_domain.journal.next_world_event_id(),
			"player_place",
			"",
			"你",
			current_place,
			{
				"from": previous_place,
				"to": current_place,
				"time": (place_change.get("time", {}) as Dictionary).duplicate(true),
				"worldRevision": host._world_revision,
			},
		)
		host.player_avatar_place_changed.emit(place_change)
	if semantic_state_changed or perception_changed:
		host._notify_world_revision()
	return player_command_result(host, command, true, "世界已确认化身位置", {
		"placeChanged": current_place != previous_place,
		"state": state,
	})



static func player_command_result(host, command: String, ok: bool, reason: String, extra: Dictionary = {}) -> Dictionary:
	var error_code := ""
	if not ok:
		if reason == "世界尚未运行":
			error_code = "WORLD_NOT_RUNNING"
		elif command == "更新位置":
			error_code = "PLAYER_POSITION_REJECTED"
		elif command == "切换地点":
			error_code = "PLAYER_PLACE_CHANGE_REJECTED"
		else:
			error_code = "CONVERSATION_COMMAND_REJECTED"
	var result := {
		"ok": ok,
		"command": command,
		"reason": reason,
		"time": host.get_time(),
		"errorCode": error_code,
		"retryable": false,
		"worldRevision": host._world_revision,
	}
	if not ok:
		result["errors"] = [reason]
	for key: Variant in extra:
		var value: Variant = extra[key]
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	host.player_command_result_created.emit(result.duplicate(true))
	return result



static func emit_place_change(
	host,
	resident_name: String,
	previous_place: String,
	defer_signal := false,
) -> bool:
	var resident := host.resident_registry.records[resident_name] as Dictionary
	var current_place := String(resident.get("currentPlace", ""))
	if previous_place == current_place:
		return false
	var place_change := {
		"residentId": resident_name,
		"from": previous_place,
		"to": current_place,
		"time": host.get_time(),
		"worldRevision": host._world_revision,
	}
	WORLD_LOG_COMMIT_RUNTIME.append_public(
		host,
		host.world_log_domain.journal.next_world_event_id(),
		"resident_place",
		resident_name,
		host.resident_display_name(resident_name),
		current_place,
		{
			"residentId": resident_name,
			"from": previous_place,
			"to": current_place,
			"time": (place_change.get("time", {}) as Dictionary).duplicate(true),
			"worldRevision": host._world_revision,
		},
	)
	var current_action := resident.get("currentAction", {}) as Dictionary
	var story_context: Dictionary = host.world_log_domain.journal.action_story_context(
		String(current_action.get("action_id", ""))
	)
	if (
		String(current_action.get("type", "")) == "去"
		and not story_context.is_empty()
		and current_place == String(current_action.get("place", ""))
	):
		var story_arrival_id := "story-arrival:%s:%s:%d" % [
			resident_name,
			String(current_action.get("action_id", "")),
			host._world_revision,
		]
		var public_arrival_event_id: String = WORLD_LOG_COMMIT_RUNTIME.append_story(host,
			story_arrival_id,
			"gathering_arrival",
			resident_name,
			current_place,
			{
				"actionId": String(
					current_action.get("action_id", "")
				),
				"from": previous_place,
				"to": current_place,
				"participantLabels": [
					host.resident_display_name(resident_name),
				],
				"causedByEventIds": (
					story_context.get("rootEventIds", []) as Array
				).duplicate(true),
				"storyRootEventIds": (
					story_context.get("rootEventIds", []) as Array
				).duplicate(true),
			},
		)
		story_context["sourceEventIds"] = [public_arrival_event_id]
		host.world_log_domain.journal.set_action_story_context(
			String(current_action.get("action_id", "")),
			story_context,
		)
	if defer_signal:
		host.frame_budget_runtime.queue_resident_place_change_signal(
			resident_name,
			place_change,
			host.get_world_revision(),
		)
	else:
		place_change["state"] = host.get_resident_state(resident_name)
		host.resident_place_changed.emit(
			host.resident_display_name(resident_name),
			place_change,
		)
	return true



static func apply_route_sample(
	host,
	resident: Dictionary,
	sample: Dictionary,
	repair_clearance: bool = false,
) -> bool:
	var position := sample.get("position", {}) as Dictionary
	var space_id := String(sample.get("spaceId", ""))
	var raw_position := Vector2(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
	)
	var authoritative_position: Vector2 = (
		clearance_safe_position(host, space_id, raw_position)
		if repair_clearance
		else raw_position
	)
	return apply_authoritative_resident_position(
		resident,
		authoritative_position,
		space_id,
		String(sample.get("regionId", "")),
		String(sample.get("placeName", "")),
	)


static func clearance_safe_position(
	host,
	space_id: String,
	position: Vector2,
) -> Vector2:
	return MOVEMENT_CLEARANCE_RUNTIME.nearest_safe_position(
		host.world_definition.world_data,
		space_id,
		position,
	)



static func apply_authoritative_resident_position(
	resident: Dictionary,
	position: Vector2,
	space_id: String,
	region_id: String,
	place_name: String,
) -> bool:
	return ACTION_SUPPORT.apply_authoritative_resident_position(resident, position, space_id, region_id, place_name)
