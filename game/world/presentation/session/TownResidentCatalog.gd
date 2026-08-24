class_name TownResidentCatalog
extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const OPENING := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const MOVEMENT := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const CATALOG_PATH := "res://world/data/town/resident_catalog.json"
const WORLD_DATA_PATH := "res://world/data/town/town_world.json"
const WORK_CHAIN_CATALOG_PATH := (
	"res://world/data/town/work_chain_catalog.json"
)
const SELECTION_LIMIT := 15
const EXPECTED_RESIDENT_COUNT := 16
const MAX_SESSION_RESIDENT_COUNT := 128
const RESIDENT_ID_PREFIX := "resident_"
const CUSTOM_RESIDENT_ID_PREFIX := "custom_resident_"
const APPEARANCE_STATUS_FORMAL := "resident_wardrobe_v1_approved_four_look"
const WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)
const WARDROBE_APPEARANCE_PREFIX := "resident_wardrobe_v1:"
const MAX_RESIDENT_AGE := 120
const MAX_SAFE_DAY := OPENING.MAX_SAFE_DAY
const MAX_SAFE_INTEGER := OPENING.MAX_SAFE_INTEGER
const MAX_CANVAS_COMPONENT := OPENING.MAX_CANVAS_COMPONENT
const WEATHER_VALUES := OPENING.WEATHER_VALUES
const BODY_VALUES := OPENING.BODY_VALUES
const REQUIRED_ATTRIBUTE_FIELDS: Array[String] = [
	"name",
	"gender",
	"desire",
	"personality",
	"speech",
]


static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CATALOG_PATH)
	)
	if not parsed is Dictionary:
		return {}
	var catalog := (parsed as Dictionary).duplicate(true)
	var residents := catalog.get("residents", []) as Array
	for index in residents.size():
		if not residents[index] is Dictionary:
			continue
		var resident := (residents[index] as Dictionary).duplicate(true)
		if resident.get("attributes") is Dictionary:
			resident["attributes"] = INTERESTS.migrate_attributes(
				resident.get("attributes", {}) as Dictionary
			)
		residents[index] = resident
	catalog["residents"] = residents
	return catalog


static func validate(catalog: Dictionary) -> Dictionary:
	return validate_against_world(catalog, _load_world_data())


static func validate_against_world(
	catalog: Dictionary,
	world_data: Dictionary,
) -> Dictionary:
	if not _has_exact_fields(
		catalog,
		[
			"schemaVersion",
			"worldId",
			"appearanceStatus",
			"openingDefaults",
			"residents",
		],
	):
		return _failure("SESSION_CATALOG_SHAPE_INVALID")
	var schema_version: Variant = catalog.get("schemaVersion")
	if (
		not _is_integer_number(schema_version)
		or int(schema_version) != 1
	):
		return _failure("SESSION_CATALOG_SCHEMA_UNSUPPORTED")
	var world_id: Variant = catalog.get("worldId")
	if not world_id is String or String(world_id) != "town":
		return _failure("SESSION_CATALOG_WORLD_MISMATCH")
	if String(catalog.get("appearanceStatus", "")) != APPEARANCE_STATUS_FORMAL:
		return _failure("SESSION_CATALOG_APPEARANCE_STATUS_INVALID")
	if (
		world_data.is_empty()
		or String(world_data.get("worldId", "")) != String(world_id)
	):
		return _failure("SESSION_CATALOG_WORLD_MISMATCH")
	if _home_space_ids(world_data).size() != SELECTION_LIMIT:
		return _failure("SESSION_CATALOG_HOME_SPACES_INVALID")
	var opening_validation := _validate_opening_defaults(
		catalog.get("openingDefaults"),
		world_data,
	)
	if not bool(opening_validation.get("ok", false)):
		return opening_validation
	var resident_values: Variant = catalog.get("residents", [])
	if (
		not resident_values is Array
		or resident_values.size() != EXPECTED_RESIDENT_COUNT
	):
		return _failure("SESSION_CATALOG_RESIDENT_COUNT_INVALID")
	var ids: Dictionary = {}
	var wardrobe_catalog := _load_wardrobe_catalog()
	if wardrobe_catalog.is_empty():
		return _failure("SESSION_CATALOG_WARDROBE_INVALID")
	for value: Variant in resident_values as Array:
		if not value is Dictionary:
			return _failure("SESSION_CATALOG_RESIDENT_INVALID")
		var entry := value as Dictionary
		if not _has_exact_fields(
			entry,
			["residentId", "attributes", "occupation", "presentation"],
		):
			return _failure("SESSION_CATALOG_RESIDENT_INVALID")
		var resident_id_value: Variant = entry.get("residentId")
		if not _valid_resident_id(resident_id_value):
			return _failure("SESSION_CATALOG_RESIDENT_ID_INVALID")
		var resident_id := String(resident_id_value)
		if ids.has(resident_id):
			return _failure("SESSION_CATALOG_RESIDENT_ID_INVALID")
		var attributes_value: Variant = entry.get("attributes")
		var occupation_value: Variant = entry.get("occupation")
		var presentation_value: Variant = entry.get("presentation")
		if (
			not attributes_value is Dictionary
			or not occupation_value is Dictionary
			or not presentation_value is Dictionary
		):
			return _failure("SESSION_CATALOG_RESIDENT_INVALID")
		var attributes := attributes_value as Dictionary
		var occupation := occupation_value as Dictionary
		var presentation := presentation_value as Dictionary
		var attribute_fields: Array[String] = [
			"name",
			"gender",
			"age",
			"appearance",
			"desire",
			"personality",
			"speech",
			"interests",
			"customInterests",
		]
		var legacy_without_custom_interests: Array[String] = (
			attribute_fields.duplicate()
		)
		legacy_without_custom_interests.erase("customInterests")
		var legacy_without_interests: Array[String] = (
			legacy_without_custom_interests.duplicate()
		)
		legacy_without_interests.erase("interests")
		if (
			not _has_exact_fields(attributes, attribute_fields)
			and not _has_exact_fields(
				attributes,
				legacy_without_custom_interests,
			)
			and not _has_exact_fields(attributes, legacy_without_interests)
		):
			return _failure("SESSION_CATALOG_ATTRIBUTE_INVALID")
		for field in REQUIRED_ATTRIBUTE_FIELDS:
			var attribute_value: Variant = attributes.get(field)
			if not _non_empty_string(attribute_value):
				return _failure("SESSION_CATALOG_ATTRIBUTE_REQUIRED")
		if String(attributes.get("gender")) not in ["男", "女"]:
			return _failure("SESSION_CATALOG_GENDER_INVALID")
		var interest_error := INTERESTS.profile_validation_error(
			attributes.get("interests", []),
			attributes.get("customInterests", []),
		)
		if not interest_error.is_empty():
			return _failure(interest_error)
		if (
			not _is_integer_number(attributes.get("age"))
			or int(attributes.get("age")) <= 0
			or int(attributes.get("age")) > MAX_RESIDENT_AGE
		):
			return _failure("SESSION_CATALOG_AGE_INVALID")
		if not _wardrobe_binding_is_valid(
			resident_id,
			attributes.get("appearance"),
			presentation,
			wardrobe_catalog,
		):
			return _failure("SESSION_CATALOG_WARDROBE_INVALID")
		if occupation.has("ownedPlace"):
			return _failure("SESSION_CATALOG_OWNED_PLACE_DEPRECATED")
		if not _has_exact_fields(
			occupation,
			["name", "workplacePlace"],
		):
			return _failure("SESSION_CATALOG_OCCUPATION_INVALID")
		var occupation_name_value: Variant = occupation.get("name")
		if not _non_empty_string(occupation_name_value):
			return _failure("SESSION_CATALOG_OCCUPATION_REQUIRED")
		var workplace_value: Variant = occupation.get("workplacePlace")
		if not _non_empty_string(workplace_value):
			return _failure("SESSION_CATALOG_WORKPLACE_REQUIRED")
		if not _world_has_place(world_data, String(workplace_value)):
			return _failure("SESSION_CATALOG_WORKPLACE_UNKNOWN")
		if not _has_exact_fields(
			presentation,
			["locationLabel", "spritePath", "portraitPath"],
		):
			return _failure("SESSION_CATALOG_PRESENTATION_INVALID")
		var location_value: Variant = presentation.get("locationLabel")
		if (
			not _non_empty_string(location_value)
			or String(location_value) != String(workplace_value)
		):
			return _failure("SESSION_CATALOG_LOCATION_INVALID")
		var sprite_path_value: Variant = presentation.get("spritePath")
		if (
			not _non_empty_string(sprite_path_value)
			or not String(sprite_path_value).begins_with("res://")
			or not ResourceLoader.exists(String(sprite_path_value))
			or not load(String(sprite_path_value)) is Texture2D
		):
			return _failure("SESSION_CATALOG_PORTRAIT_MISSING")
		var portrait_path_value: Variant = presentation.get("portraitPath")
		if (
			not _non_empty_string(portrait_path_value)
			or not String(portrait_path_value).begins_with("res://")
			or not ResourceLoader.exists(String(portrait_path_value))
			or not load(String(portrait_path_value)) is Texture2D
		):
			return _failure("SESSION_CATALOG_PORTRAIT_MISSING")
		ids[resident_id] = true
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentCount": ids.size(),
		"selectionLimit": SELECTION_LIMIT,
		"appearanceReady": true,
	}


static func build_view_model(
	provider_id_value: Variant = "",
	model_id: String = "",
	provider_ready: bool = false,
	revision: int = 1,
) -> Dictionary:
	var provider_id := str(provider_id_value)
	if _is_integer_number(provider_id_value) and model_id.is_empty():
		revision = int(provider_id_value)
		provider_id = ""
	if revision < 1:
		return {}
	var catalog := load_catalog()
	var validation := validate(catalog)
	if not bool(validation.get("ok", false)):
		return {}
	var residents: Array[Dictionary] = []
	var resident_catalog := catalog.get("residents", []) as Array
	for value: Variant in resident_catalog:
		var entry := value as Dictionary
		var attributes := entry.get("attributes", {}) as Dictionary
		var occupation := entry.get("occupation", {}) as Dictionary
		var presentation := entry.get("presentation", {}) as Dictionary
		var sprite_path := String(presentation.get("spritePath", ""))
		var portrait_path := String(
			presentation.get("portraitPath", sprite_path),
		)
		residents.append({
			"resident_id": String(entry.get("residentId", "")),
			"appearance_id": String(attributes.get("appearance", "")),
			"display_name": String(attributes.get("name", "")),
			"occupation": String(occupation.get("name", "")),
			"one_line_role": String(attributes.get("personality", "")),
			"personality": String(attributes.get("personality", "")),
			"desire": String(attributes.get("desire", "")),
			"interests": INTERESTS.normalize(
				attributes.get("interests", []),
			),
			"custom_interests": INTERESTS.normalize_custom(
				attributes.get("customInterests", []),
			),
			"interest_labels": INTERESTS.combined_labels_for(
				attributes.get("interests", []),
				attributes.get("customInterests", []),
			),
			"location": String(presentation.get("locationLabel", "")),
			"sprite_path": sprite_path,
			"portrait_path": portrait_path,
			"portrait_frame_mode": (
				"full_texture"
				if not String(presentation.get("portraitPath", "")).is_empty()
				else "legacy_first_frame"
			),
		})
	var recommended_ids := _recommended_resident_ids(resident_catalog)
	if recommended_ids.size() != SELECTION_LIMIT:
		return {}
	var data := {
		"capabilityMode": "formal",
		"source": "runtime",
		"formalReady": true,
		"internalPlaytest": false,
		"selection_limit": SELECTION_LIMIT,
		"provider_id": provider_id,
		"model_id": model_id,
		"provider_ready": provider_ready,
		"connection_label": (
			"模型已准备"
			if provider_ready and not provider_id.is_empty() and not model_id.is_empty()
			else "模型将在下一步分配"
		),
		"focused_resident_id": String(residents[0].get("resident_id", "")),
		"selected_resident_ids": [],
		"recommended_resident_ids": recommended_ids,
		"confirmation_payload": {},
		"staffing_warnings": [],
		"resident_catalog_status": "formal",
		"resident_catalog": resident_catalog.duplicate(true),
		"residents": residents,
	}
	update_confirmation_payload(data, provider_id, model_id, revision)
	return {
		"scope": "resident_selection",
		"status": "ready",
		"revision": revision,
		"data": data,
		"actions": {
			"selection": _action(true),
			"recommend": _action(true),
			"clear": _action(true),
			"confirm": _action(true),
			"custom_resident": _action(true),
			"back": _action(true),
		},
		"operation": _idle_operation(),
		"error": null,
	}


static func _recommended_resident_ids(
	resident_catalog: Array,
) -> Array[String]:
	var recommended_ids: Array[String] = []
	var recommended_set: Dictionary = {}
	var covered_occupations: Dictionary = {}
	# 推荐组合先覆盖尽可能多的职业，再按候选目录顺序补足人数。
	for catalog_value: Variant in resident_catalog:
		if not catalog_value is Dictionary:
			continue
		var catalog_entry := catalog_value as Dictionary
		var resident_id := String(catalog_entry.get("residentId", ""))
		var occupation_label := String(
			(catalog_entry.get("occupation", {}) as Dictionary).get("name", ""),
		)
		if (
			resident_id.is_empty()
			or occupation_label.is_empty()
			or covered_occupations.has(occupation_label)
		):
			continue
		recommended_ids.append(resident_id)
		recommended_set[resident_id] = true
		covered_occupations[occupation_label] = true
		if recommended_ids.size() >= SELECTION_LIMIT:
			return recommended_ids
	for catalog_value: Variant in resident_catalog:
		if not catalog_value is Dictionary:
			continue
		var resident_id := String(
			(catalog_value as Dictionary).get("residentId", ""),
		)
		if resident_id.is_empty() or recommended_set.has(resident_id):
			continue
		recommended_ids.append(resident_id)
		recommended_set[resident_id] = true
		if recommended_ids.size() >= SELECTION_LIMIT:
			break
	return recommended_ids


static func update_confirmation_payload(
	data: Dictionary,
	provider_id_value: Variant,
	model_id_value: Variant = "",
	draft_revision: int = 1,
) -> void:
	data["staffing_warnings"] = []
	var provider_id := str(provider_id_value)
	var model_id := str(model_id_value)
	if _is_integer_number(provider_id_value) and str(model_id_value).is_empty():
		draft_revision = int(provider_id_value)
		provider_id = ""
		model_id = ""
	var selected_value: Variant = data.get("selected_resident_ids")
	var residents_value: Variant = data.get("residents")
	var session_catalog_value: Variant = data.get("resident_catalog")
	if (
		draft_revision < 1
		or not selected_value is Array
		or not residents_value is Array
		or not session_catalog_value is Array
		or (residents_value as Array).size() < SELECTION_LIMIT
		or (residents_value as Array).size() > MAX_SESSION_RESIDENT_COUNT
		or (session_catalog_value as Array).size() < SELECTION_LIMIT
		or (session_catalog_value as Array).size() > MAX_SESSION_RESIDENT_COUNT
	):
		data["confirmation_payload"] = {}
		return
	var selected := selected_value as Array
	if selected.size() != SELECTION_LIMIT:
		data["confirmation_payload"] = {}
		return
	var base_catalog := load_catalog()
	var world_data := _load_world_data()
	var catalog_validation := validate_against_world(base_catalog, world_data)
	var home_space_ids := _home_space_ids(world_data)
	if (
		not bool(catalog_validation.get("ok", false))
		or home_space_ids.size() != SELECTION_LIMIT
	):
		data["confirmation_payload"] = {}
		return
	var selected_ids: Dictionary = {}
	for selected_id_value: Variant in selected:
		if (
			not _valid_session_resident_id(selected_id_value)
			or selected_ids.has(String(selected_id_value))
		):
			data["confirmation_payload"] = {}
			return
		selected_ids[String(selected_id_value)] = true
	var base_catalog_entries: Dictionary = {}
	for base_value: Variant in base_catalog.get("residents", []) as Array:
		var base_entry := base_value as Dictionary
		base_catalog_entries[String(base_entry.get("residentId", ""))] = base_entry
	var session_catalog_ids: Dictionary = {}
	var session_catalog := session_catalog_value as Array
	for catalog_value: Variant in session_catalog:
		if not catalog_value is Dictionary:
			data["confirmation_payload"] = {}
			return
		var catalog_entry := catalog_value as Dictionary
		var catalog_id_value: Variant = catalog_entry.get("residentId")
		var catalog_id := String(catalog_id_value)
		var is_base_resident := (
			base_catalog_entries.has(catalog_id)
			and catalog_entry == (base_catalog_entries[catalog_id] as Dictionary)
		)
		var is_custom_resident := (
			catalog_id.begins_with(CUSTOM_RESIDENT_ID_PREFIX)
			and String(catalog_entry.get("source", "")) == "custom"
			and _session_custom_catalog_entry_is_valid(catalog_entry, world_data)
		)
		if (
			not _valid_session_resident_id(catalog_id_value)
			or session_catalog_ids.has(catalog_id)
			or (not is_base_resident and not is_custom_resident)
		):
			data["confirmation_payload"] = {}
			return
		session_catalog_ids[catalog_id] = true
	var projected_ids: Dictionary = {}
	for resident_value: Variant in residents_value as Array:
		if not resident_value is Dictionary:
			data["confirmation_payload"] = {}
			return
		var resident_id_value: Variant = (
			resident_value as Dictionary
		).get("resident_id")
		if (
			not _valid_session_resident_id(resident_id_value)
			or not session_catalog_ids.has(String(resident_id_value))
			or projected_ids.has(String(resident_id_value))
		):
			data["confirmation_payload"] = {}
			return
		var resident_id := String(resident_id_value)
		projected_ids[resident_id] = true
	var ordered_ids: Array[String] = []
	for selected_id: Variant in selected_ids:
		if (
			not session_catalog_ids.has(selected_id)
			or not projected_ids.has(selected_id)
		):
			data["confirmation_payload"] = {}
			return
	for catalog_value: Variant in session_catalog:
		var catalog_id := String(
			(catalog_value as Dictionary).get("residentId", "")
		)
		if selected_ids.has(catalog_id):
			ordered_ids.append(catalog_id)
	if ordered_ids.size() != SELECTION_LIMIT:
		data["confirmation_payload"] = {}
		return
	data["staffing_warnings"] = _occupation_staffing_warnings(
		ordered_ids,
		session_catalog,
		world_data,
	)
	var slots: Array[Dictionary] = []
	for index in SELECTION_LIMIT:
		slots.append({
			"residentId": ordered_ids[index],
			"spaceId": home_space_ids[index],
			"llmBinding": {
				"mode": "model",
				"providerId": provider_id,
				"modelId": model_id,
			},
		})
	data["confirmation_payload"] = {
		"schemaVersion": 1,
		"sourceScope": "resident_selection",
		"draftRevision": draft_revision,
		"slots": slots,
	}


static func _occupation_staffing_warnings(
	selected_resident_ids: Array[String],
	session_catalog: Array,
	world_data: Dictionary,
) -> Array[Dictionary]:
	var catalog_by_id: Dictionary = {}
	for catalog_value: Variant in session_catalog:
		if not catalog_value is Dictionary:
			continue
		var catalog_entry := catalog_value as Dictionary
		catalog_by_id[String(catalog_entry.get("residentId", ""))] = catalog_entry
	var selected_occupation_counts: Dictionary = {}
	for resident_id: String in selected_resident_ids:
		if not catalog_by_id.has(resident_id):
			continue
		var occupation_value: Variant = (
			catalog_by_id[resident_id] as Dictionary
		).get("occupation", {})
		if not occupation_value is Dictionary:
			continue
		var occupation_label := String(
			(occupation_value as Dictionary).get("name", ""),
		).strip_edges()
		if occupation_label.is_empty():
			continue
		selected_occupation_counts[occupation_label] = (
			int(selected_occupation_counts.get(occupation_label, 0)) + 1
		)
	var vacancy_effect_by_occupation_id: Dictionary = {}
	var work_chain_catalog := _load_json_dictionary(WORK_CHAIN_CATALOG_PATH)
	for chain_value: Variant in work_chain_catalog.get("chains", []) as Array:
		if not chain_value is Dictionary:
			continue
		var chain := chain_value as Dictionary
		var occupation_id := String(chain.get("occupationId", ""))
		if occupation_id.is_empty():
			continue
		vacancy_effect_by_occupation_id[occupation_id] = String(
			chain.get("vacancyEffect", ""),
		)
	var warnings: Array[Dictionary] = []
	for occupation_value: Variant in world_data.get("occupations", []) as Array:
		if not occupation_value is Dictionary:
			continue
		var occupation := occupation_value as Dictionary
		var occupation_label := String(occupation.get("label", "")).strip_edges()
		if (
			occupation_label.is_empty()
			or int(selected_occupation_counts.get(occupation_label, 0)) > 0
		):
			continue
		var occupation_id := String(occupation.get("occupationId", ""))
		warnings.append({
			"occupationId": occupation_id,
			"occupationLabel": occupation_label,
			"workplacePlace": String(
				occupation.get("primaryWorkplacePlace", ""),
			),
			"vacancyEffect": String(
				vacancy_effect_by_occupation_id.get(occupation_id, ""),
			),
		})
	return warnings


static func _validate_opening_defaults(
	value: Variant,
	world_data: Dictionary,
) -> Dictionary:
	if not value is Dictionary:
		return _failure("SESSION_CATALOG_OPENING_DEFAULT_INVALID")
	var defaults := value as Dictionary
	if not _has_exact_fields(
		defaults,
		[
			"environment",
			"residentBody",
			"residentDoing",
			"residentSpawnPolicy",
			"playerAvatar",
		],
	):
		return _failure("SESSION_CATALOG_OPENING_DEFAULT_INVALID")
	var environment_value: Variant = defaults.get("environment")
	var resident_body_value: Variant = defaults.get("residentBody")
	var player_avatar_value: Variant = defaults.get("playerAvatar")
	if (
		not environment_value is Dictionary
		or not resident_body_value is Dictionary
		or not player_avatar_value is Dictionary
	):
		return _failure("SESSION_CATALOG_OPENING_DEFAULT_INVALID")
	var environment := environment_value as Dictionary
	if (
		not _has_exact_fields(
			environment,
			["day", "clock", "weather", "randomSeed"],
		)
		or not _is_integer_number(environment.get("day"))
		or int(environment.get("day")) < 1
		or int(environment.get("day")) > MAX_SAFE_DAY
		or not _valid_clock(environment.get("clock"))
		or not environment.get("weather") is String
		or String(environment.get("weather")) not in WEATHER_VALUES
		or not _is_integer_number(environment.get("randomSeed"))
		or absf(float(environment.get("randomSeed"))) > MAX_SAFE_INTEGER
	):
		return _failure("SESSION_CATALOG_ENVIRONMENT_INVALID")
	var resident_body := resident_body_value as Dictionary
	if not _has_exact_fields(resident_body, ["困", "饿", "累"]):
		return _failure("SESSION_CATALOG_RESIDENT_BODY_INVALID")
	for body_name in ["困", "饿", "累"]:
		if (
			not resident_body.get(body_name) is String
			or not (
				String(resident_body.get(body_name))
				in (BODY_VALUES[body_name] as Array)
			)
		):
			return _failure("SESSION_CATALOG_RESIDENT_BODY_INVALID")
	var resident_doing: Variant = defaults.get("residentDoing")
	if not _non_empty_string(resident_doing):
		return _failure("SESSION_CATALOG_RESIDENT_DOING_INVALID")
	if (
		String(defaults.get("residentSpawnPolicy", ""))
		!= "staggered_south_entry"
	):
		return _failure("SESSION_CATALOG_RESIDENT_SPAWN_POLICY_INVALID")
	return _validate_player_avatar(
		player_avatar_value as Dictionary,
		world_data,
	)


static func _validate_player_avatar(
	player_avatar: Dictionary,
	world_data: Dictionary,
) -> Dictionary:
	if (
		not _has_exact_fields(player_avatar, ["name", "worldState"])
		or not _non_empty_string(player_avatar.get("name"))
	):
		return _failure("SESSION_CATALOG_PLAYER_AVATAR_INVALID")
	var world_state_value: Variant = player_avatar.get("worldState")
	if not world_state_value is Dictionary:
		return _failure("SESSION_CATALOG_PLAYER_AVATAR_INVALID")
	var world_state := world_state_value as Dictionary
	if not _has_exact_fields(
		world_state,
		["place", "spaceId", "regionId", "position", "doing"],
	):
		return _failure("SESSION_CATALOG_PLAYER_AVATAR_INVALID")
	for field in ["place", "spaceId", "regionId", "doing"]:
		if not _non_empty_string(world_state.get(field)):
			return _failure("SESSION_CATALOG_PLAYER_AVATAR_INVALID")
	var position_value: Variant = world_state.get("position")
	if not position_value is Array or position_value.size() != 2:
		return _failure("SESSION_CATALOG_PLAYER_AVATAR_INVALID")
	for coordinate: Variant in position_value as Array:
		if (
			typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(coordinate))
			or absf(float(coordinate)) > MAX_CANVAS_COMPONENT
		):
			return _failure("SESSION_CATALOG_PLAYER_AVATAR_INVALID")
	if (
		not MOVEMENT.validate_position_state(
			world_data,
			world_state,
		).is_empty()
	):
		return _failure("SESSION_CATALOG_PLAYER_AVATAR_INVALID")
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
	}


static func _valid_clock(value: Variant) -> bool:
	if not value is String:
		return false
	var text := String(value)
	if (
		text.length() != 5
		or text.substr(2, 1) != ":"
		or not _is_ascii_digit(text.substr(0, 1))
		or not _is_ascii_digit(text.substr(1, 1))
		or not _is_ascii_digit(text.substr(3, 1))
		or not _is_ascii_digit(text.substr(4, 1))
	):
		return false
	var parts := text.split(":")
	var hour := int(parts[0])
	var minute := int(parts[1])
	return hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59


static func _is_ascii_digit(character: String) -> bool:
	return WORLD_SCALARS.is_ascii_digit(character)


static func _load_world_data() -> Dictionary:
	return _load_json_dictionary(WORLD_DATA_PATH)


static func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	return (
		(parsed as Dictionary).duplicate(true)
		if parsed is Dictionary
		else {}
	)


static func _home_space_ids(world_data: Dictionary) -> Array[String]:
	var spaces_value: Variant = world_data.get("mapSpaces")
	var places_value: Variant = world_data.get("places")
	if not spaces_value is Array or not places_value is Array:
		return []
	var known_space_ids: Dictionary = {}
	for space_value: Variant in spaces_value as Array:
		if not space_value is Dictionary:
			return []
		var space_id_value: Variant = (space_value as Dictionary).get("id")
		if (
			not _non_empty_string(space_id_value)
			or known_space_ids.has(String(space_id_value))
		):
			return []
		known_space_ids[String(space_id_value)] = true
	var home_space_ids: Array[String] = []
	var seen_home_space_ids: Dictionary = {}
	for place_value: Variant in places_value as Array:
		if not place_value is Dictionary:
			return []
		var place := place_value as Dictionary
		if String(place.get("type", "")) != "住家":
			continue
		var home_space_id_value: Variant = place.get("spaceId")
		if (
			not _non_empty_string(home_space_id_value)
			or not known_space_ids.has(String(home_space_id_value))
			or seen_home_space_ids.has(String(home_space_id_value))
		):
			return []
		var home_space_id := String(home_space_id_value)
		seen_home_space_ids[home_space_id] = true
		home_space_ids.append(home_space_id)
	home_space_ids.sort()
	return home_space_ids


static func _world_has_place(
	world_data: Dictionary,
	expected_name: String,
) -> bool:
	for place_value: Variant in world_data.get("places", []) as Array:
		if (
			place_value is Dictionary
			and String(
				(place_value as Dictionary).get("name", "")
			) == expected_name
		):
			return true
	return false


static func _session_custom_catalog_entry_is_valid(
	entry: Dictionary,
	world_data: Dictionary,
) -> bool:
	if not _has_exact_fields(
		entry,
		[
			"residentId",
			"attributes",
			"occupation",
			"presentation",
			"source",
		],
	):
		return false
	var attributes_value: Variant = entry.get("attributes")
	var occupation_value: Variant = entry.get("occupation")
	var presentation_value: Variant = entry.get("presentation")
	if (
		not attributes_value is Dictionary
		or not occupation_value is Dictionary
		or not presentation_value is Dictionary
		or entry.get("source") != "custom"
	):
		return false
	var attributes := attributes_value as Dictionary
	if (
		not _has_exact_fields(
			attributes,
			[
				"name",
				"gender",
				"age",
				"appearance",
				"desire",
				"personality",
				"speech",
				"interests",
				"customInterests",
				"selectionSummary",
			],
		)
		or not _non_empty_string(attributes.get("name"))
		or String(attributes.get("name")).length() > 24
		or not attributes.get("gender") is String
		or attributes.get("gender") not in ["男", "女"]
		or not _is_integer_number(attributes.get("age"))
		or int(attributes.get("age")) <= 0
		or int(attributes.get("age")) > MAX_RESIDENT_AGE
		or not _non_empty_string(attributes.get("desire"))
		or String(attributes.get("desire")).length() > 240
		or not _non_empty_string(attributes.get("personality"))
		or String(attributes.get("personality")).length() > 240
		or not _non_empty_string(attributes.get("speech"))
		or String(attributes.get("speech")).length() > 240
		or not _non_empty_string(attributes.get("selectionSummary"))
		or String(attributes.get("selectionSummary")).length() > 24
		or not INTERESTS.profile_validation_error(
			attributes.get("interests", []),
			attributes.get("customInterests", []),
		).is_empty()
	):
		return false
	var wardrobe_catalog := _load_wardrobe_catalog()
	var loadout := _wardrobe_loadout_for_appearance(
		attributes.get("appearance"),
		wardrobe_catalog,
	)
	if loadout.is_empty():
		return false
	var occupation := occupation_value as Dictionary
	if not _has_exact_fields(
		occupation,
		["name", "workplacePlace"],
	):
		return false
	var workplace_value: Variant = occupation.get("workplacePlace")
	var workplace_name := (
		workplace_value as String
		if workplace_value is String
		else ""
	)
	if (
		not _non_empty_string(occupation.get("name"))
		or not _non_empty_string(workplace_value)
		or not _world_has_place(world_data, workplace_name)
	):
		return false
	var presentation := presentation_value as Dictionary
	return (
		_has_exact_fields(
			presentation,
			["spritePath", "portraitPath", "locationLabel"],
		)
		and presentation.get("spritePath") is String
		and presentation.get("portraitPath") is String
		and presentation.get("locationLabel") is String
		and _texture_path_is_ready(String(presentation.get("spritePath")))
		and _texture_path_is_ready(String(presentation.get("portraitPath")))
		and presentation.get("portraitPath") == loadout.get("portraitPath")
		and presentation.get("locationLabel") == workplace_name
	)


static func _load_wardrobe_catalog() -> Dictionary:
	if not FileAccess.file_exists(WARDROBE_CATALOG_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(WARDROBE_CATALOG_PATH)
	)
	if (
		parsed is not Dictionary
		or String((parsed as Dictionary).get("schema", ""))
		!= "ai-town.resident-wardrobe.v1"
		or (parsed as Dictionary).get("loadouts") is not Array
		or (parsed as Dictionary).get("residentAssignments") is not Dictionary
	):
		return {}
	return (parsed as Dictionary).duplicate(true)


static func _wardrobe_loadout_for_appearance(
	appearance_value: Variant,
	wardrobe_catalog: Dictionary,
) -> Dictionary:
	if (
		not _non_empty_string(appearance_value)
		or not String(appearance_value).begins_with(
			WARDROBE_APPEARANCE_PREFIX,
		)
	):
		return {}
	var loadout_id := String(appearance_value).trim_prefix(
		WARDROBE_APPEARANCE_PREFIX,
	)
	for loadout_value: Variant in (
		wardrobe_catalog.get("loadouts", []) as Array
	):
		if (
			loadout_value is Dictionary
			and String((loadout_value as Dictionary).get("id", ""))
			== loadout_id
		):
			return (loadout_value as Dictionary).duplicate(true)
	return {}


static func _texture_path_is_ready(path: String) -> bool:
	return (
		not path.is_empty()
		and path.begins_with("res://")
		and ResourceLoader.exists(path, "Texture2D")
		and load(path) is Texture2D
	)


static func _wardrobe_binding_is_valid(
	resident_id: String,
	appearance_value: Variant,
	presentation: Dictionary,
	wardrobe_catalog: Dictionary,
) -> bool:
	if not appearance_value is String:
		return false
	var assignments := (
		wardrobe_catalog.get("residentAssignments", {}) as Dictionary
	)
	var loadout_id := String(assignments.get(resident_id, ""))
	var appearance_id := WARDROBE_APPEARANCE_PREFIX + loadout_id
	if loadout_id.is_empty() or String(appearance_value) != appearance_id:
		return false
	var matching_loadout: Dictionary = {}
	for loadout_value: Variant in (
		wardrobe_catalog.get("loadouts", []) as Array
	):
		if (
			loadout_value is Dictionary
			and String((loadout_value as Dictionary).get("id", ""))
			== loadout_id
		):
			matching_loadout = loadout_value as Dictionary
			break
	if matching_loadout.is_empty():
		return false
	var portrait_path_value: Variant = presentation.get("portraitPath")
	return (
		portrait_path_value is String
		and portrait_path_value
		== matching_loadout.get("portraitPath")
	)


static func _non_empty_string(value: Variant) -> bool:
	return (
		value is String
		and not String(value).is_empty()
		and String(value) == String(value).strip_edges()
	)


static func _has_exact_fields(
	value: Dictionary,
	expected_fields: Array[String],
) -> bool:
	if value.size() != expected_fields.size():
		return false
	for key_value: Variant in value:
		if (
			not key_value is String
			or not expected_fields.has(String(key_value))
		):
			return false
	return true


static func _is_integer_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == floor(float(value))
	)


static func _valid_resident_id(value: Variant) -> bool:
	if not value is String:
		return false
	var resident_id := String(value)
	if (
		resident_id.is_empty()
		or resident_id != resident_id.strip_edges()
		or resident_id.length() > 128
		or not resident_id.begins_with(RESIDENT_ID_PREFIX)
	):
		return false
	for character in resident_id:
		var code := character.unicode_at(0)
		var is_ascii_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_ascii_letter and not is_digit and character not in ["_", "-"]:
			return false
	return true


static func _valid_session_resident_id(value: Variant) -> bool:
	if not value is String:
		return false
	var resident_id := String(value)
	if (
		resident_id.is_empty()
		or resident_id != resident_id.strip_edges()
		or resident_id.length() > 128
		or (
			not resident_id.begins_with(RESIDENT_ID_PREFIX)
			and not resident_id.begins_with(CUSTOM_RESIDENT_ID_PREFIX)
		)
	):
		return false
	for character in resident_id:
		var code := character.unicode_at(0)
		var is_ascii_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_ascii_letter and not is_digit and character not in ["_", "-"]:
			return false
	return true


static func _action(enabled: bool, disabled_reason := "") -> Dictionary:
	return {
		"enabled": enabled,
		"disabled_reason": "" if enabled else disabled_reason,
	}


static func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


static func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure(error_code)
