class_name TownWorldRestoreLayout
extends RefCounted


const INDOOR_PATH_QUERY := preload("res://world/data/town/TownIndoorPropPathQuery.gd")
const INDOOR_LAYOUT_PROJECTION := preload(
	"res://world/runtime/TownIndoorLayoutProjection.gd"
)
const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const SAVE_SCHEMA_REGISTRY := preload(
	"res://world/presentation/session/TownSaveSchemaRegistry.gd"
)
const PROJECTION_KEYS := [
	"spaceId",
	"placeName",
	"regionId",
	"roomId",
	"navigation",
	"props",
]
const NAVIGATION_KEYS := [
	"cellSize",
	"placeName",
	"regionId",
	"roomId",
	"spaceId",
	"walkableCells",
]
const PROP_KEYS := ["actions", "interaction", "name", "placeName"]
const INTERACTION_KEYS := [
	"actorFacing",
	"anchorId",
	"anchorKind",
	"anchorSnappedToFloor",
	"assetId",
	"direction",
	"instanceId",
	"instancePosition",
	"position",
	"regionId",
	"roomId",
	"sourceAnchorPosition",
	"spaceId",
]
const ACTION_KEYS := ["durationMinutes", "effects", "verb"]


static func prepare(world_data: Dictionary, state: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var restored_world_data := world_data.duplicate(true)
	var restored_overrides := []
	var layouts_value: Variant = state.get("indoorLayoutOverrides")
	if not layouts_value is Array:
		errors.append("世界存档 indoorLayoutOverrides 必须为数组")
	else:
		var restored_spaces := {}
		for index in (layouts_value as Array).size():
			var projection_value: Variant = (layouts_value as Array)[index]
			if not projection_value is Dictionary:
				errors.append("世界存档 indoorLayoutOverrides[%d] 必须为对象" % index)
				continue
			var projection := projection_value as Dictionary
			var shape_errors := _validate_projection_shape(
				projection,
				index,
			)
			errors.append_array(shape_errors)
			if not shape_errors.is_empty():
				continue
			var space_id_value: Variant = projection.get("spaceId")
			var space_id := space_id_value as String
			if restored_spaces.has(space_id):
				errors.append("世界存档室内布局空间重复：%s" % space_id)
				continue
			restored_spaces[space_id] = true
			var projection_errors := INDOOR_LAYOUT_PROJECTION.validate(
				restored_world_data,
				projection,
			) as PackedStringArray
			for projection_error in projection_errors:
				errors.append(str(projection_error))
			if projection_errors.is_empty():
				restored_world_data = INDOOR_LAYOUT_PROJECTION.apply(
					restored_world_data,
					projection,
				) as Dictionary
				restored_overrides.append(
					INDOOR_LAYOUT_PROJECTION.snapshot_for_space(
						restored_world_data,
						space_id,
					) as Dictionary
				)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {
		"ok": true,
		"worldData": restored_world_data,
		"indoorLayoutOverrides": restored_overrides,
	}


static func validate_occupants(
	world_data: Dictionary,
	residents: Dictionary,
	player_avatar: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	var navigation_by_space := {}
	var known_spaces := {}
	var spaces_value: Variant = world_data.get("mapSpaces")
	if not spaces_value is Array:
		return ["当前世界数据 mapSpaces 必须为数组"]
	for value: Variant in spaces_value as Array:
		if not value is Dictionary:
			continue
		var space_id_value: Variant = (value as Dictionary).get("id")
		if space_id_value is String:
			known_spaces[space_id_value] = true
	var navigation_value: Variant = world_data.get("indoorNavigation")
	if not navigation_value is Array:
		return ["当前世界数据 indoorNavigation 必须为数组"]
	for value: Variant in navigation_value as Array:
		if not value is Dictionary:
			continue
		var navigation := value as Dictionary
		var navigation_space_value: Variant = navigation.get("spaceId")
		if navigation_space_value is String:
			navigation_by_space[navigation_space_value] = navigation
	for resident_name_value: Variant in residents:
		var resident_name := str(resident_name_value)
		var resident_value: Variant = residents[resident_name_value]
		if not resident_value is Dictionary:
			errors.append("世界存档居民状态必须为对象：%s" % resident_name)
			continue
		var resident := resident_value as Dictionary
		var space_value: Variant = resident.get("spaceId")
		if not space_value is String or String(space_value).strip_edges().is_empty():
			errors.append("世界存档居民空间必须为非空文本：%s" % resident_name)
			continue
		var space_id := space_value as String
		if not known_spaces.has(space_id):
			errors.append("世界存档居民引用未知空间：%s" % resident_name)
			continue
		var position_value: Variant = resident.get("position")
		if not position_value is Vector2:
			errors.append("世界存档居民位置必须为 Vector2：%s" % resident_name)
			continue
		if navigation_by_space.has(space_id) and not INDOOR_PATH_QUERY.is_position_walkable(
			navigation_by_space[space_id] as Dictionary,
			position_value as Vector2,
		):
			errors.append("世界存档室内布局会把居民 %s 压在碰撞内" % resident_name)
	var player_space_value: Variant = player_avatar.get("spaceId")
	if (
		not player_space_value is String
		or String(player_space_value).strip_edges().is_empty()
	):
		errors.append("世界存档玩家空间必须为非空文本")
		return errors
	var player_space_id := player_space_value as String
	if not known_spaces.has(player_space_id):
		errors.append("世界存档玩家引用未知空间")
		return errors
	var player_position_value: Variant = player_avatar.get("position")
	if not player_position_value is Vector2:
		errors.append("世界存档玩家位置必须为 Vector2")
		return errors
	if navigation_by_space.has(player_space_id) and not INDOOR_PATH_QUERY.is_position_walkable(
		navigation_by_space[player_space_id] as Dictionary,
		player_position_value as Vector2,
	):
		errors.append("世界存档室内布局会把玩家压在碰撞内")
	return errors


static func _validate_projection_shape(
	projection: Dictionary,
	index: int,
) -> Array[String]:
	var errors: Array[String] = []
	var label := "世界存档 indoorLayoutOverrides[%d]" % index
	_validate_exact_keys(projection, PROJECTION_KEYS, label, errors)
	_validate_string_fields(
		projection,
		["spaceId", "placeName", "regionId", "roomId"],
		label,
		errors,
	)
	var navigation_value: Variant = projection.get("navigation")
	if not navigation_value is Dictionary:
		return errors
	var navigation := navigation_value as Dictionary
	_validate_exact_keys(
		navigation,
		NAVIGATION_KEYS,
		"%s.navigation" % label,
		errors,
	)
	_validate_string_fields(
		navigation,
		["spaceId", "placeName", "regionId", "roomId"],
		"%s.navigation" % label,
		errors,
	)
	var props_value: Variant = projection.get("props")
	if not props_value is Array:
		return errors
	for prop_index in (props_value as Array).size():
		var prop_value: Variant = (props_value as Array)[prop_index]
		if not prop_value is Dictionary:
			continue
		var prop := prop_value as Dictionary
		var prop_label := "%s.props[%d]" % [label, prop_index]
		_validate_exact_keys(prop, PROP_KEYS, prop_label, errors)
		_validate_string_fields(
			prop,
			["name", "placeName"],
			prop_label,
			errors,
		)
		var interaction_value: Variant = prop.get("interaction")
		if interaction_value is Dictionary:
			var interaction := interaction_value as Dictionary
			_validate_exact_keys(
				interaction,
				INTERACTION_KEYS,
				"%s.interaction" % prop_label,
				errors,
			)
			_validate_string_fields(
				interaction,
				[
					"anchorId",
					"assetId",
					"direction",
					"instanceId",
					"regionId",
					"roomId",
					"spaceId",
				],
				"%s.interaction" % prop_label,
				errors,
			)
		var actions_value: Variant = prop.get("actions")
		if not actions_value is Array:
			continue
		for action_index in (actions_value as Array).size():
			var action_value: Variant = (actions_value as Array)[action_index]
			if not action_value is Dictionary:
				continue
			var action := action_value as Dictionary
			var action_label := (
				"%s.actions[%d]" % [prop_label, action_index]
			)
			_validate_exact_keys(
				action,
				ACTION_KEYS,
				action_label,
				errors,
			)
			_validate_string_fields(
				action,
				["verb"],
				action_label,
				errors,
			)
	return errors


static func _validate_exact_keys(
	value: Dictionary,
	expected: Array,
	label: String,
	errors: Array[String],
) -> void:
	for key_value: Variant in value:
		if not key_value is String or not expected.has(key_value):
			errors.append("%s 包含未知字段：%s" % [label, str(key_value)])
	for key_value: Variant in expected:
		if not value.has(key_value):
			errors.append("%s 缺少字段：%s" % [label, str(key_value)])


static func _validate_string_fields(
	value: Dictionary,
	fields: Array,
	label: String,
	errors: Array[String],
) -> void:
	for field_value: Variant in fields:
		var field := str(field_value)
		if not value.get(field) is String:
			errors.append("%s.%s 必须为文本" % [label, field])
		elif String(value.get(field)) != String(value.get(field)).strip_edges():
			errors.append("%s.%s 不能包含首尾空白" % [label, field])


static func world_data_has_place(
	world_data: Dictionary,
	place_id: String,
) -> bool:
	for place_value: Variant in world_data.get("places", []) as Array:
		if String(
			(place_value as Dictionary).get("name", "")
		) == place_id:
			return true
	return false


static func world_data_has_activity_at_place(
	world_data: Dictionary,
	activity_id: String,
	place_id: String,
) -> bool:
	var activity_exists := false
	for activity_value: Variant in world_data.get(
		"activityDefinitions",
		[],
	) as Array:
		if String(
			(activity_value as Dictionary).get("activityId", "")
		) == activity_id:
			activity_exists = true
			break
	if not activity_exists:
		return false
	for slot_value: Variant in world_data.get(
		"activitySlots",
		[],
	) as Array:
		var slot := slot_value as Dictionary
		if (
			String(slot.get("activityId", "")) == activity_id
			and String(slot.get("placeName", "")) == place_id
		):
			return true
	return false


# defaults 由地点服务模块按当前岗位状态构建，
# 本函数只负责把存档状态与默认配置逐字段对账。
static func prepare_place_service_states(
	value: Variant,
	defaults: Dictionary,
) -> Dictionary:
	var unpacked := SAVE_CODEC.unpack_optional_domain_snapshot(
		value,
		"placeServiceStates 必须是对象",
	)
	if unpacked.get("ok") != true:
		return {"ok": false, "errors": unpacked.get("errors", [])}
	if unpacked.get("empty") == true:
		return {"ok": true, "states": defaults}
	var snapshot := unpacked.get("snapshot", {}) as Dictionary
	var states := {}
	var errors: Array[String] = []
	for place_id_value: Variant in snapshot:
		var place_id := String(place_id_value).strip_edges()
		var state_value: Variant = snapshot.get(
			place_id_value
		)
		if (
			place_id.is_empty()
			or not state_value is Dictionary
			or not defaults.has(place_id)
		):
			errors.append(
				"placeServiceStates 包含未配置的地点：%s"
				% place_id
			)
			continue
		var state := state_value as Dictionary
		var expected := defaults.get(place_id, {}) as Dictionary
		for field in [
			"pressure_id",
			"place_id",
			"owner_id",
			"open",
			"service_occupation_id",
			"service_capacity",
			"helper_activity_id",
			"request_activity_ids",
			"pending_request_ids",
			"source_revision",
			"expires_at",
			"updated_at",
		]:
			if not state.has(field):
				errors.append(
					"placeServiceStates.%s 缺少字段：%s"
					% [place_id, field]
				)
		if (
			String(state.get("place_id", "")) != place_id
			or String(state.get("owner_id", ""))
			!= String(expected.get("owner_id", ""))
			or not SAVE_SCHEMA_REGISTRY.place_service_config_matches(
				state,
				expected,
			)
		):
			errors.append(
				"placeServiceStates.%s 与当前地点服务配置不一致"
				% place_id
			)
		if (
			not state.get("open") is bool
			or not state.get("pending_request_ids") is Array
			or not state.get("source_revision") is int
			or int(state.get("source_revision", -1)) < 0
			or not state.get("expires_at") is int
			or not state.get("updated_at") is int
		):
			errors.append(
				"placeServiceStates.%s 状态字段类型无效"
				% place_id
			)
		var seen_requests := {}
		for request_value: Variant in state.get(
			"pending_request_ids",
			[],
		) as Array:
			if (
				not request_value is String
				or String(request_value).strip_edges().is_empty()
				or seen_requests.has(String(request_value))
			):
				errors.append(
					"placeServiceStates.%s 请求编号无效或重复"
					% place_id
				)
				continue
			seen_requests[String(request_value)] = true
		states[place_id] = state.duplicate(true)
	for default_place_value: Variant in defaults:
		var default_place := String(default_place_value)
		if not states.has(default_place):
			states[default_place] = (
				defaults.get(default_place, {}) as Dictionary
			).duplicate(true)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "states": states}
