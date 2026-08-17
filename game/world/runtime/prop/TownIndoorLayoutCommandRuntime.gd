class_name TownIndoorLayoutCommandRuntime
extends RefCounted


const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)


static func apply(host, projection: Dictionary) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if not host._pause_reasons.has("furniture_editor"):
		return host._command_failure(
			"FURNITURE_EDITOR_NOT_PAUSED",
			["更新室内道具布局前必须以 furniture_editor 原因暂停世界"],
		)
	var errors: PackedStringArray = host._dynamic_prop_runtime.validate_layout(
		host.world_definition.world_data,
		projection,
	)
	var space_id := String(projection.get("spaceId", ""))
	if errors.is_empty():
		ACTION_SUPPORT.validate_layout_occupants(
			host,
			space_id,
			projection,
			errors,
		)
	if not errors.is_empty():
		return host._command_failure(
			"INDOOR_LAYOUT_PROJECTION_INVALID",
			Array(errors),
			{"projection": host.get_indoor_layout_projection(space_id)},
		)
	var layout_change: Dictionary = host._dynamic_prop_runtime.apply_layout(
		host.world_definition.world_data,
		host.world_definition.base_world_data,
		projection,
	)
	var next_projection := layout_change.get("projection", {}) as Dictionary
	if not bool(layout_change.get("changed", false)):
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"projection": next_projection,
		})
	host.world_definition.world_data = layout_change.get("worldData", {}) as Dictionary
	host.place_presentation_query.clear_cache()
	host.activity_reachability_state.clear()
	host._bump_world_revision()
	for resident_name in host.resident_registry.order:
		var resident := host.resident_registry.records[resident_name] as Dictionary
		if String(resident.get("spaceId", "")) == space_id:
			host._schedule_decision(resident_name, true, false, true)
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"projection": next_projection,
	})
