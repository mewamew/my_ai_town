class_name TownDynamicPropRuntime
extends RefCounted


const PROP_QUERY := preload(
	"res://world/data/town/TownWorldPropQuery.gd"
)
const INDOOR_LAYOUT_PROJECTION := preload(
	"res://world/runtime/TownIndoorLayoutProjection.gd"
)

var _dynamic_props: Dictionary = {}
var _indoor_layout_overrides: Dictionary = {}


func reset() -> void:
	_dynamic_props.clear()
	_indoor_layout_overrides.clear()


func clear_dynamic_props() -> void:
	_dynamic_props.clear()


func normalize_identity(prop_id: String, display_name: String) -> Dictionary:
	var normalized_id := prop_id.strip_edges()
	var normalized_name := display_name.strip_edges()
	if normalized_id.is_empty() or normalized_name.is_empty():
		return {
			"ok": false,
			"errorCode": "DYNAMIC_PROP_IDENTITY_INVALID",
		}
	return {
		"ok": true,
		"propId": normalized_id,
		"displayName": normalized_name,
	}


func remove(prop_id: String) -> Dictionary:
	var removed := _dynamic_props.erase(prop_id)
	return {
		"ok": true,
		"status": "removed" if removed else "already_absent",
		"propId": prop_id,
	}


func reject_outside_world(prop_id: String, position: Vector2) -> Dictionary:
	_dynamic_props.erase(prop_id)
	return {
		"ok": false,
		"errorCode": "DYNAMIC_PROP_OUTSIDE_WORLD",
		"propId": prop_id,
		"position": {"x": position.x, "y": position.y},
	}


func upsert_normalized(
	identity: Dictionary,
	position: Vector2,
	active: bool,
	world_running: bool,
	placement: Dictionary,
) -> Dictionary:
	var prop_id := String(identity.get("propId", ""))
	if not active:
		return remove(prop_id)
	if not world_running:
		return {
			"ok": false,
			"errorCode": "WORLD_NOT_RUNNING",
		}
	if placement.is_empty():
		return reject_outside_world(prop_id, position)
	return register(
		prop_id,
		String(identity.get("displayName", "")),
		position,
		placement,
	)


func register(
	prop_id: String,
	display_name: String,
	position: Vector2,
	placement: Dictionary,
) -> Dictionary:
	var membership := placement.get("membership", {}) as Dictionary
	var approach_position := placement.get("approachPosition", position) as Vector2
	var prop := {
		"id": prop_id,
		"name": display_name,
		"placeName": String(membership.get("placeName", "")),
		"actions": [
			{
				"verb": "摸摸",
				"durationMinutes": 5,
				"effects": {},
			},
		],
		"interaction": {
			"spaceId": "town_outdoor",
			"regionId": String(membership.get("regionId", "")),
			"anchorKind": "dynamic_animal",
			"actorFacing": "up",
			"position": [position.x, position.y],
			"approachPolyline": [
				[approach_position.x, approach_position.y],
				[position.x, position.y],
			],
		},
	}
	_dynamic_props[prop_id] = prop
	return {
		"ok": true,
		"status": "registered",
		"propId": prop_id,
		"placeName": prop["placeName"],
		"position": {"x": position.x, "y": position.y},
	}


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for prop_value: Variant in _dynamic_props.values():
		result.append((prop_value as Dictionary).duplicate(true))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("id", "")) < String(right.get("id", ""))
	)
	return result


func query_data(world_data: Dictionary) -> Dictionary:
	if _dynamic_props.is_empty():
		return world_data
	var result := world_data.duplicate(false)
	var props := (world_data.get("props", []) as Array).duplicate()
	for prop_value: Variant in _dynamic_props.values():
		props.append((prop_value as Dictionary).duplicate(true))
	result["props"] = props
	return result


func cache_signature() -> String:
	return str(_dynamic_props)


func is_dynamic_action(resident: Dictionary, action: Dictionary) -> bool:
	var prop_name := String(action.get("prop", "")).strip_edges()
	var action_verb := String(action.get("verb", "")).strip_edges()
	var place_name := String(resident.get("currentPlace", ""))
	if prop_name.is_empty() or action_verb.is_empty():
		return false
	for prop_value: Variant in _dynamic_props.values():
		var prop := prop_value as Dictionary
		if (
			String(prop.get("name", "")) != prop_name
			or String(prop.get("placeName", "")) != place_name
		):
			continue
		for action_value: Variant in prop.get("actions", []) as Array:
			if (
				action_value is Dictionary
				and String((action_value as Dictionary).get("verb", ""))
				== action_verb
			):
				return true
	return false


func restore_layout_overrides(values: Array) -> void:
	_indoor_layout_overrides.clear()
	for projection_value: Variant in values:
		var projection := projection_value as Dictionary
		_indoor_layout_overrides[String(projection.get("spaceId", ""))] = (
			projection.duplicate(true)
		)


func layout_projection(world_data: Dictionary, space_id: String) -> Dictionary:
	return INDOOR_LAYOUT_PROJECTION.snapshot_for_space(
		world_data,
		space_id.strip_edges(),
	) as Dictionary


func validate_layout(
	world_data: Dictionary,
	projection: Dictionary,
) -> PackedStringArray:
	return INDOOR_LAYOUT_PROJECTION.validate(world_data, projection)


func apply_layout(
	world_data: Dictionary,
	base_world_data: Dictionary,
	projection: Dictionary,
) -> Dictionary:
	var space_id := String(projection.get("spaceId", ""))
	var previous := layout_projection(world_data, space_id)
	var next_data := INDOOR_LAYOUT_PROJECTION.apply(
		world_data,
		projection,
	) as Dictionary
	var next_projection := layout_projection(next_data, space_id)
	if next_projection == previous:
		return {
			"changed": false,
			"projection": previous,
		}
	record_layout_override(base_world_data, space_id, next_projection)
	return {
		"changed": true,
		"worldData": next_data,
		"projection": next_projection,
	}


func record_layout_override(
	base_world_data: Dictionary,
	space_id: String,
	projection: Dictionary,
) -> void:
	var baseline := INDOOR_LAYOUT_PROJECTION.snapshot_for_space(
		base_world_data,
		space_id,
	) as Dictionary
	if projection == baseline:
		_indoor_layout_overrides.erase(space_id)
	else:
		_indoor_layout_overrides[space_id] = projection.duplicate(true)


func layout_override_snapshots() -> Array:
	var result := []
	var space_ids: Array = _indoor_layout_overrides.keys()
	space_ids.sort()
	for space_id_value: Variant in space_ids:
		result.append(
			(_indoor_layout_overrides[space_id_value] as Dictionary).duplicate(true)
		)
	return result


func is_layout_override_action(
	world_data: Dictionary,
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	if not _indoor_layout_overrides.has(String(resident.get("spaceId", ""))):
		return false
	return not PROP_QUERY.action_definition(
		query_data(world_data),
		String(resident.get("currentPlace", "")),
		String(action.get("prop", "")).strip_edges(),
		String(action.get("verb", "")).strip_edges(),
	).is_empty()
