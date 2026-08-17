class_name TownPlacePresentationQuery
extends RefCounted


const PROP_QUERY := preload("res://world/data/town/TownWorldPropQuery.gd")
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)

var _place_by_name: Dictionary = {}
var _presentation_cue_by_key: Dictionary = {}


func clear_cache() -> void:
	_place_by_name.clear()
	_presentation_cue_by_key.clear()


func clear_presentation_cue_cache() -> void:
	_presentation_cue_by_key.clear()


func presentation_cue(
	prop_query_data: Dictionary,
	place_name: String,
	prop_name: String,
	verb: String,
) -> Dictionary:
	var key := "%s|%s|%s" % [place_name, prop_name, verb]
	if not _presentation_cue_by_key.has(key):
		_presentation_cue_by_key[key] = PROP_QUERY.presentation_cue(
			prop_query_data,
			place_name,
			prop_name,
			verb,
		) as Dictionary
	# 调用方会往结果里补字段，返回浅拷贝避免污染缓存。
	return (_presentation_cue_by_key[key] as Dictionary).duplicate()


func names(world_data: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in world_data.get("places", []) as Array:
		result.append(String((value as Dictionary).get("name", "")))
	result.sort()
	return result


func detail(
	world_data: Dictionary,
	residents: Dictionary,
	resident_order: Array,
	owners: Dictionary,
	player_avatar: Dictionary,
	player_avatar_present: bool,
	prop_query_data: Dictionary,
	place_name: String,
	resident_is_present: Callable,
	resident_display_name: Callable,
	person_name_for_id: Callable,
) -> Dictionary:
	var place := _record(world_data, place_name)
	if place.is_empty():
		return {}
	var resident_names: Array[String] = []
	for resident_id_value: Variant in resident_order:
		var resident_id := String(resident_id_value)
		var resident := residents.get(resident_id, {}) as Dictionary
		if (
			bool(resident_is_present.call(resident))
			and String(resident.get("currentPlace", "")) == place_name
		):
			resident_names.append(
				String(resident_display_name.call(resident_id)),
			)
	var owner_resident_id: Variant = (
		null
		if String(place.get("type", "")) == "公共地点"
		else owners.get(place_name)
	)
	return {
		"name": place_name,
		"type": String(place.get("type", "")),
		"ownerResidentId": owner_resident_id,
		"owner": (
			null
			if owner_resident_id == null
			else String(person_name_for_id.call(String(owner_resident_id)))
		),
		"summary": String(place.get("summary", "")),
		"spaceId": String(place.get("spaceId", "")),
		"capabilities": (
			place.get("capabilities", {}) as Dictionary
		).duplicate(true),
		"residentNames": resident_names,
		"playerAvatarPresent": (
			player_avatar_present
			and String(player_avatar.get("currentPlace", "")) == place_name
		),
		"props": PROP_QUERY.agent_props_at_place(prop_query_data, place_name),
	}


func all_details(
	world_data: Dictionary,
	residents: Dictionary,
	resident_order: Array,
	owners: Dictionary,
	player_avatar: Dictionary,
	player_avatar_present: bool,
	prop_query_data: Dictionary,
	resident_is_present: Callable,
	resident_display_name: Callable,
	person_name_for_id: Callable,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for place_name: String in names(world_data):
		result.append(detail(
			world_data,
			residents,
			resident_order,
			owners,
			player_avatar,
			player_avatar_present,
			prop_query_data,
			place_name,
			resident_is_present,
			resident_display_name,
			person_name_for_id,
		))
	return result


func exterior_anchor(world_data: Dictionary, place_name: String) -> Dictionary:
	for value: Variant in world_data.get("connections", []) as Array:
		var connection := value as Dictionary
		var left := connection.get("from", {}) as Dictionary
		var right := connection.get("to", {}) as Dictionary
		if (
			String(left.get("placeName", "")) == place_name
			and String(right.get("spaceId", "")) == "town_outdoor"
		):
			return ACTION_SUPPORT.connection_anchor(right)
		if (
			String(right.get("placeName", "")) == place_name
			and String(left.get("spaceId", "")) == "town_outdoor"
		):
			return ACTION_SUPPORT.connection_anchor(left)
	return {}


func observation_hotspot(
	world_data: Dictionary,
	place_name: String,
) -> Dictionary:
	var connection_id := connection_id(world_data, place_name)
	if connection_id.is_empty():
		return {}
	var hotspots := world_data.get("placeObservationHotspots", {}) as Dictionary
	var spec_value: Variant = hotspots.get(connection_id)
	if spec_value is not Dictionary:
		return {}
	var spec := spec_value as Dictionary
	var offset := spec.get("offset", {}) as Dictionary
	var size := spec.get("size", {}) as Dictionary
	var width := float(size.get("width", 0.0))
	var height := float(size.get("height", 0.0))
	if (
		not is_finite(width)
		or not is_finite(height)
		or width <= 0.0
		or height <= 0.0
	):
		return {}
	var anchor := exterior_anchor(world_data, place_name)
	if anchor.is_empty():
		return {}
	var anchor_position := anchor.get("position", Vector2.ZERO) as Vector2
	var offset_vector := Vector2(
		float(offset.get("x", 0.0)),
		float(offset.get("y", 0.0)),
	)
	if not offset_vector.is_finite():
		return {}
	return {
		"placeName": place_name,
		"connectionId": connection_id,
		"center": anchor_position + offset_vector,
		"size": Vector2(width, height),
	}


func connection_id(world_data: Dictionary, place_name: String) -> String:
	var normalized := place_name.strip_edges()
	if normalized.is_empty():
		return ""
	for value: Variant in world_data.get("connections", []) as Array:
		var connection := value as Dictionary
		var left := connection.get("from", {}) as Dictionary
		var right := connection.get("to", {}) as Dictionary
		if (
			String(left.get("spaceId", "")) == "town_outdoor"
			and String(right.get("placeName", "")) == normalized
		):
			return String(connection.get("id", ""))
		if (
			String(right.get("spaceId", "")) == "town_outdoor"
			and String(left.get("placeName", "")) == normalized
		):
			return String(connection.get("id", ""))
	return ""


func place_name_for_connection(
	world_data: Dictionary,
	connection_id_value: String,
) -> String:
	var normalized := connection_id_value.strip_edges()
	if normalized.is_empty():
		return ""
	for value: Variant in world_data.get("connections", []) as Array:
		var connection := value as Dictionary
		if String(connection.get("id", "")) != normalized:
			continue
		var left := connection.get("from", {}) as Dictionary
		var right := connection.get("to", {}) as Dictionary
		if String(left.get("spaceId", "")) == "town_outdoor":
			return String(right.get("placeName", ""))
		if String(right.get("spaceId", "")) == "town_outdoor":
			return String(left.get("placeName", ""))
		return ""
	return ""


func agent_places(
	world_data: Dictionary,
	owners: Dictionary,
	resident_names_by_id: Dictionary,
	player_id: String,
	player_name: String,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in world_data.get("places", []) as Array:
		var place := value as Dictionary
		var place_name := String(place.get("name", ""))
		var place_type := String(place.get("type", ""))
		var owner: Variant = (
			null if place_type == "公共地点" else owners.get(place_name)
		)
		var owner_id := String(owner) if owner != null else ""
		var owner_name := String(resident_names_by_id.get(owner_id, ""))
		if owner_name.is_empty() and owner_id == player_id:
			owner_name = player_name
		result.append({
			"name": place_name,
			"type": place_type,
			"owner": (
				null
				if owner == null
				else owner_name
			),
			"owner_resident_id": owner,
			"summary": String(place.get("summary", "")),
			"features": (
				place.get("visibleFeatures", []) as Array
			).duplicate(true),
		})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("name", "")) < String(right.get("name", "")),
	)
	return result


func _record(world_data: Dictionary, place_name: String) -> Dictionary:
	if _place_by_name.is_empty():
		for value: Variant in world_data.get("places", []) as Array:
			var place := value as Dictionary
			_place_by_name[String(place.get("name", ""))] = place
	return _place_by_name.get(place_name, {}) as Dictionary
