class_name TownPlayerAvatarMovementCommandRuntime
extends RefCounted


const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const CHARACTER_MOVEMENT_QUERY := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)


static func set_present(host, present: bool, emit_events := true) -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "更新位置", false, "世界尚未运行")
	if host.actor_presentation_state.player_avatar_present == present:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
			"更新位置",
			true,
			"化身在场状态未变化",
			{"state": host.get_player_avatar_state()},
		)
	host.actor_presentation_state.player_avatar_present = present
	host._bump_world_revision(false)
	PERCEPTION_RUNTIME._refresh_perception(
		host,
		emit_events,
		host._traveler_relationship_state,
	)
	var state: Dictionary = host.get_player_avatar_state()
	host.player_avatar_state_changed.emit(state)
	host._notify_world_revision()
	return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
		"更新位置",
		true,
		"世界已确认化身在场状态",
		{"state": state},
	)


static func submit_position(
	host,
	space_id: String,
	position: Vector2,
	doing := "",
) -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "更新位置", false, "世界尚未运行")
	if not is_finite(position.x) or not is_finite(position.y):
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "更新位置", false, "化身位置必须是有限坐标")
	if not doing is String:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "更新位置", false, "化身动作描述必须是文本")
	var current_space_id := String(host.actor_presentation_state.player_avatar.get("spaceId", ""))
	if space_id != current_space_id:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
			"更新位置",
			false,
			"跨地图空间必须通过地点切换命令",
		)
	var membership: Dictionary = PERCEPTION_RUNTIME._membership(
		host,
		space_id,
		position,
	)
	if membership.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "更新位置", false, "化身位置不是合法世界位置")
	return host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_player_avatar_state(host,
		space_id,
		membership,
		position,
		String(doing),
		"更新位置",
	)


static func prepare_descent(
	host,
	space_id: String,
	position: Vector2,
) -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "更新位置", false, "世界尚未运行")
	if not is_finite(position.x) or not is_finite(position.y):
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "更新位置", false, "化身降落点必须是有限坐标")
	var safe_position := CHARACTER_MOVEMENT_QUERY.nearest_safe_position(
		host.world_definition.world_data,
		space_id,
		position,
	) as Dictionary
	if safe_position.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
			"更新位置",
			false,
			"当前视野附近没有可供化身降落的安全区域",
		)
	var resolved_position := safe_position.get("position", Vector2.ZERO) as Vector2
	var membership := {
		"regionId": String(safe_position.get("regionId", "")),
		"placeName": String(safe_position.get("placeName", "")),
	}
	host.actor_presentation_state.player_avatar_present = true
	var result: Dictionary = host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_player_avatar_state(host,
		space_id,
		membership,
		resolved_position,
		"降落在%s" % String(membership.get("placeName", "小镇里")),
		"更新位置",
	)
	result["landing"] = safe_position.duplicate(true)
	result["outdoorReturnPlace"] = host.ACTION_SUPPORT.outdoor_connection_place_for(host,
		String(membership.get("placeName", "")),
	)
	return result


static func change_place(host, target_place: String) -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "切换地点", false, "世界尚未运行")
	var normalized := target_place.strip_edges()
	if normalized.is_empty() or host.get_place_detail(normalized).is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "切换地点", false, "目标地点不存在")
	var current_place := String(host.actor_presentation_state.player_avatar.get("currentPlace", ""))
	if normalized == current_place:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "切换地点", false, "化身已经位于目标地点")
	var endpoint: Dictionary = host.ACTION_SUPPORT.direct_connection_endpoint(host,
		current_place,
		normalized,
	)
	if endpoint.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
			"切换地点",
			false,
			"当前地点与目标地点没有直接入口连接",
		)
	var point := endpoint.get("position", {}) as Dictionary
	var position := Vector2(
		float(point.get("x", 0.0)),
		float(point.get("y", 0.0)),
	)
	var target_space_id := String(endpoint.get("spaceId", ""))
	var membership: Dictionary = PERCEPTION_RUNTIME._membership(
		host,
		target_space_id,
		position,
	)
	if membership.is_empty() or String(membership.get("placeName", "")) != normalized:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "切换地点", false, "目标入口不是合法世界位置")
	return host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_player_avatar_state(host,
		target_space_id,
		membership,
		position,
		"进入%s" % normalized,
		"切换地点",
	)


static func return_outdoors(
	host,
	connection_place: String,
	safe_return_position: Vector2,
) -> Dictionary:
	if not host._running:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "离开室内", false, "世界尚未运行")
	if not is_finite(safe_return_position.x) or not is_finite(safe_return_position.y):
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
			"离开室内",
			false,
			"化身安全出门点必须是有限坐标",
		)
	var normalized := connection_place.strip_edges()
	if normalized.is_empty() or host.get_place_detail(normalized).is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "离开室内", false, "室外连接地点不存在")
	var current_place := String(host.actor_presentation_state.player_avatar.get("currentPlace", ""))
	var endpoint: Dictionary = host.ACTION_SUPPORT.direct_connection_endpoint(host,
		current_place,
		normalized,
	)
	if endpoint.is_empty():
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
			"离开室内",
			false,
			"当前室内与室外地点没有直接出口连接",
		)
	var target_space_id := String(endpoint.get("spaceId", ""))
	if target_space_id != "town_outdoor":
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host, "离开室内", false, "目标连接不是室外出口")
	var membership: Dictionary = PERCEPTION_RUNTIME._membership(
		host,
		target_space_id,
		safe_return_position,
	)
	if membership.is_empty() or String(membership.get("placeName", "")) != normalized:
		return host.RESIDENT_POSITION_COMMIT_RUNTIME.player_command_result(host,
			"离开室内",
			false,
			"化身安全出门点不属于室外连接地点",
		)
	return host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_player_avatar_state(host,
		target_space_id,
		membership,
		safe_return_position,
		"走出%s" % current_place,
		"离开室内",
	)
