class_name TownNewGameOpeningCompiler
extends RefCounted


const DRAFT := preload("res://world/presentation/session/TownNewGameDraft.gd")
const OPENING := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const DEFAULT_OPAQUE_AVATAR_ID := "person_7f3a91c2d8e4"
const WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)
const WARDROBE_APPEARANCE_PREFIX := "resident_wardrobe_v1:"
const MOVEMENT := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const SOUL_PROFILE := preload("res://agent/soul/AgentSoulProfile.gd")
const REQUIRED_ATTRIBUTES: Array[String] = [
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


static func compile(
	draft: Dictionary,
	world_data: Dictionary,
	catalog: Dictionary,
) -> Dictionary:
	var draft_validation := DRAFT.validate(draft)
	if not bool(draft_validation.get("ok", false)):
		return draft_validation
	var catalog_shape := _validate_catalog_shape(catalog, world_data)
	if not bool(catalog_shape.get("ok", false)):
		return catalog_shape
	var places_by_space := _places_by_space(world_data)
	var places_by_name := _places_by_name(world_data)
	var regions_by_id := _regions_by_id(world_data)
	var residents_by_id_result := _residents_by_id(catalog)
	if not bool(residents_by_id_result.get("ok", false)):
		return residents_by_id_result
	var residents_by_id := residents_by_id_result.get("residents", {}) as Dictionary
	var model_bindings := DRAFT.model_bindings(draft)
	var selected_resident_ids: Dictionary = {}
	for binding in model_bindings:
		selected_resident_ids[String(binding.get("residentId", ""))] = true
	var shop_owner_result := _resolve_shop_owners(
		catalog,
		selected_resident_ids,
		places_by_name,
	)
	if not bool(shop_owner_result.get("ok", false)):
		return shop_owner_result
	var owned_place_by_resident := (
		shop_owner_result.get("ownedPlaceByResident", {}) as Dictionary
	)
	var defaults := catalog.get("openingDefaults", {}) as Dictionary
	var resident_body := defaults.get("residentBody", {}) as Dictionary
	var resident_doing := String(defaults.get("residentDoing", "")).strip_edges()
	var resident_spawn_policy := String(
		defaults.get(
			"residentSpawnPolicy",
			"staggered_south_entry",
		),
	).strip_edges()
	if resident_spawn_policy != "staggered_south_entry":
		return _catalog_failure([_error(
			"openingDefaults.residentSpawnPolicy",
			"SESSION_CATALOG_RESIDENT_SPAWN_POLICY_INVALID",
		)])
	var defaults_errors: Array[Dictionary] = []
	for body_name in ["困", "饿", "累"]:
		if String(resident_body.get(body_name, "")).is_empty():
			defaults_errors.append(_error(
				"openingDefaults.residentBody.%s" % body_name,
				"SESSION_CATALOG_OPENING_DEFAULT_REQUIRED",
			))
	if resident_doing.is_empty():
		defaults_errors.append(_error(
			"openingDefaults.residentDoing",
			"SESSION_CATALOG_OPENING_DEFAULT_REQUIRED",
		))
	if not defaults_errors.is_empty():
		return _catalog_failure(defaults_errors)
	var errors: Array[Dictionary] = []
	var opening_residents: Array[Dictionary] = []
	var owner_assignments: Dictionary = {}
	var resolved_bindings: Array[Dictionary] = []
	var workplace_residents: Dictionary = {}
	var resident_names: Dictionary = {}
	var south_entry := MOVEMENT.formal_south_entry(world_data) as Dictionary
	if south_entry.is_empty():
		return _catalog_failure([_error(
			"openingDefaults.residentSpawnPolicy",
			"SESSION_CATALOG_SOUTH_ENTRY_MISSING",
		)])
	var south_position := (
		south_entry.get("position", Vector2.ZERO) as Vector2
	)
	for binding in model_bindings:
		var resident_id := String(binding.get("residentId", ""))
		var space_id := String(binding.get("spaceId", ""))
		var entry := residents_by_id.get(resident_id, {}) as Dictionary
		if entry.is_empty():
			errors.append(_error(
				"residents.%s" % resident_id,
				"SESSION_CATALOG_RESIDENT_MISSING",
			))
			continue
		var catalog_attributes := entry.get("attributes", {}) as Dictionary
		var presentation := entry.get("presentation", {}) as Dictionary
		var attributes: Dictionary = {}
		# World/Agent opening data has a deliberately smaller contract than the
		# resident-selection catalog.  In particular selectionSummary is UI-only
		# metadata and must never leak into the exact World opening schema.
		for field in REQUIRED_ATTRIBUTES:
			if catalog_attributes.has(field):
				attributes[field] = catalog_attributes.get(field)
		if not attributes.has("interests"):
			attributes["interests"] = []
		else:
			attributes["interests"] = INTERESTS.normalize(
				attributes.get("interests", []),
			)
		attributes["customInterests"] = INTERESTS.normalize_custom(
			attributes.get("customInterests", []),
		)
		if attributes.has("age"):
			attributes["age"] = int(attributes.get("age", 0))
		var sprite_path := String(
			presentation.get("spritePath", "")
		).strip_edges()
		if (
			sprite_path.is_empty()
			or not sprite_path.begins_with("res://")
			or not ResourceLoader.exists(sprite_path)
			or not load(sprite_path) is Texture2D
		):
			errors.append(_error(
				"residents.%s.presentation.spritePath" % resident_id,
				"SESSION_CATALOG_PORTRAIT_MISSING",
			))
		_validate_attributes(resident_id, attributes, errors)
		var resident_name := String(attributes.get("name", "")).strip_edges()
		if resident_names.has(resident_name):
			errors.append(_error(
				"residents.%s.attributes.name" % resident_id,
				"SESSION_CATALOG_RESIDENT_NAME_DUPLICATED",
			))
		elif not resident_name.is_empty():
			resident_names[resident_name] = resident_id
		var occupation := entry.get("occupation", {}) as Dictionary
		var job_name := String(occupation.get("name", "")).strip_edges()
		var workplace_name := String(occupation.get("workplacePlace", "")).strip_edges()
		var legacy_owned_place_name := String(
			occupation.get("ownedPlace", "")
		).strip_edges()
		var owned_place_name := String(
			owned_place_by_resident.get(
				resident_id,
				legacy_owned_place_name,
			)
		).strip_edges()
		if (
			not legacy_owned_place_name.is_empty()
			and owned_place_name != legacy_owned_place_name
		):
			errors.append(_error(
				"residents.%s.occupation.ownedPlace" % resident_id,
				"SESSION_CATALOG_PLACE_OWNER_AMBIGUOUS",
			))
		if job_name.is_empty():
			errors.append(_error(
				"residents.%s.occupation.name" % resident_id,
				"SESSION_CATALOG_OCCUPATION_REQUIRED",
			))
		if workplace_name.is_empty() or not places_by_name.has(workplace_name):
			errors.append(_error(
				"residents.%s.occupation.workplacePlace" % resident_id,
				"SESSION_CATALOG_WORKPLACE_UNKNOWN",
			))
		if (
			not owned_place_name.is_empty()
			and (
				not places_by_name.has(owned_place_name)
				or String((places_by_name[owned_place_name] as Dictionary).get("type", "")) != "铺面"
			)
		):
			errors.append(_error(
				"residents.%s.occupation.ownedPlace" % resident_id,
				"SESSION_CATALOG_OWNED_PLACE_INVALID",
			))
		var home_place := places_by_space.get(space_id, {}) as Dictionary
		if home_place.is_empty() or String(home_place.get("type", "")) != "住家":
			errors.append(_error(
				"slots.%s.spaceId" % resident_id,
				"SESSION_CATALOG_HOME_SPACE_UNKNOWN",
			))
			continue
		var home_name := String(home_place.get("name", ""))
		var region_result := _initial_region_state(home_place, regions_by_id)
		if not bool(region_result.get("ok", false)):
			errors.append(_error(
				"slots.%s.spaceId" % resident_id,
				"SESSION_CATALOG_HOME_REGION_INVALID",
				{"spaceId": space_id},
			))
			continue
		owner_assignments[home_name] = resident_id
		if not owned_place_name.is_empty():
			var resident_ids := workplace_residents.get(owned_place_name, []) as Array
			resident_ids.append(resident_id)
			workplace_residents[owned_place_name] = resident_ids
		var initial_state := {
			"place": String(south_entry.get("placeName", "")),
			"spaceId": String(south_entry.get("spaceId", "")),
			"regionId": String(south_entry.get("regionId", "")),
			"position": [south_position.x, south_position.y],
			"doing": resident_doing,
			"body": resident_body.duplicate(true),
		}
		opening_residents.append({
			"residentId": resident_id,
			"attributes": attributes.duplicate(true),
			"socialState": {
				"home": home_name,
				"job": job_name,
				"workplace": workplace_name,
				"money": _initial_money_for_occupation(job_name),
				"reputation": _initial_reputation_for_occupation(job_name),
			},
			"worldState": initial_state,
		})
		resolved_bindings.append({
			"residentId": resident_id,
			"residentName": resident_name,
			"llmBinding": (binding.get("llmBinding", {}) as Dictionary).duplicate(true),
		})
	if not errors.is_empty():
		return _catalog_failure(errors)
	for place_variant in world_data.get("places", []) as Array:
		var place := place_variant as Dictionary
		if String(place.get("type", "")) in ["公共地点", "住家"]:
			continue
		var place_name := String(place.get("name", ""))
		var candidates := workplace_residents.get(place_name, []) as Array
		if candidates.size() != 1:
			errors.append(_error(
				"ownerAssignments.%s" % place_name,
				(
					"SESSION_CATALOG_PLACE_OWNER_MISSING"
					if candidates.is_empty()
					else "SESSION_CATALOG_PLACE_OWNER_AMBIGUOUS"
				),
				{"residentIds": candidates.duplicate()},
			))
			continue
		owner_assignments[place_name] = String(candidates[0])
	if not errors.is_empty():
		return _catalog_failure(errors)
	var opening_environment := (
		defaults.get("environment", {}) as Dictionary
	).duplicate(true)
	if opening_environment.has("day"):
		opening_environment["day"] = int(opening_environment.get("day", 1))
	if opening_environment.has("randomSeed"):
		opening_environment["randomSeed"] = int(
			opening_environment.get("randomSeed", 0)
		)
	var player_avatar := (defaults.get("playerAvatar", {}) as Dictionary).duplicate(true)
	if String(player_avatar.get("residentId", "")).strip_edges().is_empty():
		player_avatar["residentId"] = DEFAULT_OPAQUE_AVATAR_ID
	var opening_config := {
		"schemaVersion": 1,
		"worldId": String(world_data.get("worldId", "")),
		"environment": opening_environment,
		"ownerAssignments": owner_assignments,
		"residents": opening_residents,
		# 开局只分析一次；完整原始 OC 仍保留在 residents.attributes，
		# 这里存放给对应 Agent 的私有结构化索引。
		"agentSoulProfiles": SOUL_PROFILE.analyze_all(opening_residents),
		"playerAvatar": player_avatar,
	}
	var opening_errors := OPENING.validate(opening_config, world_data)
	if not opening_errors.is_empty():
		var details: Array[Dictionary] = []
		for message in opening_errors:
			details.append(_error(
				"openingConfig",
				"SESSION_OPENING_CONFIG_INVALID",
				{"message": message},
			))
		return {
			"ok": false,
			"errorCode": "SESSION_OPENING_CONFIG_INVALID",
			"retryable": false,
			"errors": details,
		}
	resolved_bindings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"openingConfig": opening_config,
		"residentBindings": resolved_bindings,
	}


static func _validate_catalog_shape(
	catalog: Dictionary,
	world_data: Dictionary,
) -> Dictionary:
	if int(catalog.get("schemaVersion", 0)) != 1:
		return _catalog_failure([_error(
			"schemaVersion",
			"SESSION_CATALOG_SCHEMA_UNSUPPORTED",
		)])
	if String(catalog.get("worldId", "")) != String(world_data.get("worldId", "")):
		return _catalog_failure([_error(
			"worldId",
			"SESSION_CATALOG_WORLD_MISMATCH",
		)])
	if not (catalog.get("residents", null) is Array):
		return _catalog_failure([_error(
			"residents",
			"SESSION_CATALOG_RESIDENTS_INVALID",
		)])
	var defaults := catalog.get("openingDefaults", {}) as Dictionary
	var errors: Array[Dictionary] = []
	if not (defaults.get("environment", null) is Dictionary):
		errors.append(_error(
			"openingDefaults.environment",
			"SESSION_CATALOG_OPENING_DEFAULT_REQUIRED",
		))
	if not (defaults.get("playerAvatar", null) is Dictionary):
		errors.append(_error(
			"openingDefaults.playerAvatar",
			"SESSION_CATALOG_OPENING_DEFAULT_REQUIRED",
		))
	if not (defaults.get("residentBody", null) is Dictionary):
		errors.append(_error(
			"openingDefaults.residentBody",
			"SESSION_CATALOG_OPENING_DEFAULT_REQUIRED",
		))
	return {"ok": true} if errors.is_empty() else _catalog_failure(errors)


static func _residents_by_id(catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var errors: Array[Dictionary] = []
	for index in (catalog.get("residents", []) as Array).size():
		var entry := (catalog.get("residents", []) as Array)[index] as Dictionary
		var resident_id := String(entry.get("residentId", "")).strip_edges()
		if resident_id.is_empty():
			errors.append(_error(
				"residents[%d].residentId" % index,
				"SESSION_CATALOG_RESIDENT_ID_REQUIRED",
			))
		elif result.has(resident_id):
			errors.append(_error(
				"residents[%d].residentId" % index,
				"SESSION_CATALOG_RESIDENT_ID_DUPLICATED",
			))
		else:
			result[resident_id] = entry
	return (
		{"ok": true, "residents": result}
		if errors.is_empty()
		else _catalog_failure(errors)
	)


static func _validate_attributes(
	resident_id: String,
	attributes: Dictionary,
	errors: Array[Dictionary],
) -> void:
	for field in REQUIRED_ATTRIBUTES:
		var missing := false
		if field == "age":
			missing = int(attributes.get(field, 0)) <= 0
		elif field == "interests":
			var interest_error := INTERESTS.profile_validation_error(
				attributes.get(field, []),
				attributes.get("customInterests", []),
			)
			if not interest_error.is_empty():
				errors.append(_error(
					"residents.%s.attributes.%s" % [resident_id, field],
					interest_error,
				))
			continue
		elif field == "customInterests":
			continue
		else:
			missing = String(attributes.get(field, "")).strip_edges().is_empty()
		if missing:
			errors.append(_error(
				"residents.%s.attributes.%s" % [resident_id, field],
				"SESSION_CATALOG_ATTRIBUTE_REQUIRED",
			))
	if (
		attributes.has("appearance")
		and not _appearance_id_is_known(attributes.get("appearance"))
	):
		errors.append(_error(
			"residents.%s.attributes.appearance" % resident_id,
			"SESSION_CATALOG_APPEARANCE_INVALID",
		))


static func _appearance_id_is_known(value: Variant) -> bool:
	if (
		not value is String
		or String(value) != String(value).strip_edges()
		or not String(value).begins_with(WARDROBE_APPEARANCE_PREFIX)
	):
		return false
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(WARDROBE_CATALOG_PATH),
	)
	if (
		parsed is not Dictionary
		or String((parsed as Dictionary).get("schema", ""))
		!= "ai-town.resident-wardrobe.v1"
	):
		return false
	var expected_id := String(value).trim_prefix(
		WARDROBE_APPEARANCE_PREFIX,
	)
	for loadout_value: Variant in (
		(parsed as Dictionary).get("loadouts", []) as Array
	):
		if (
			loadout_value is Dictionary
			and String((loadout_value as Dictionary).get("id", ""))
			== expected_id
		):
			return true
	return false


static func _resolve_shop_owners(
	catalog: Dictionary,
	selected_resident_ids: Dictionary,
	places_by_name: Dictionary,
) -> Dictionary:
	var candidates_value: Variant = catalog.get("shopOwnerCandidates")
	if candidates_value == null:
		return {"ok": true, "ownedPlaceByResident": {}}
	if not candidates_value is Dictionary or (candidates_value as Dictionary).is_empty():
		return _catalog_failure([_error(
			"shopOwnerCandidates",
			"SESSION_CATALOG_SHOP_OWNER_CANDIDATES_INVALID",
		)])
	var candidates := candidates_value as Dictionary
	var owned_place_by_resident: Dictionary = {}
	var assigned_owner_ids: Dictionary = {}
	var shop_names: Array[String] = []
	for shop_name_value: Variant in candidates:
		if not shop_name_value is String:
			return _catalog_failure([_error(
				"shopOwnerCandidates",
				"SESSION_CATALOG_SHOP_OWNER_CANDIDATES_INVALID",
			)])
		shop_names.append(String(shop_name_value))
	shop_names.sort()
	for shop_name in shop_names:
		var place := places_by_name.get(shop_name, {}) as Dictionary
		var candidate_values: Variant = candidates.get(shop_name)
		if (
			place.is_empty()
			or String(place.get("type", "")) != "铺面"
			or not candidate_values is Array
			or (candidate_values as Array).is_empty()
		):
			return _catalog_failure([_error(
				"shopOwnerCandidates.%s" % shop_name,
				"SESSION_CATALOG_SHOP_OWNER_CANDIDATES_INVALID",
			)])
		var owner_id := ""
		var has_selected_candidate := false
		for candidate_value: Variant in candidate_values as Array:
			if (
				candidate_value is String
				and selected_resident_ids.has(String(candidate_value))
			):
				has_selected_candidate = true
			if (
				candidate_value is String
				and selected_resident_ids.has(String(candidate_value))
				and not assigned_owner_ids.has(String(candidate_value))
			):
				owner_id = String(candidate_value)
				break
		if owner_id.is_empty() and has_selected_candidate:
			owner_id = _fallback_selected_shop_owner(
				catalog,
				selected_resident_ids,
				assigned_owner_ids,
				shop_name,
			)
		if owner_id.is_empty():
			return _catalog_failure([_error(
				"ownerAssignments.%s" % shop_name,
				"SESSION_CATALOG_PLACE_OWNER_MISSING",
			)])
		owned_place_by_resident[owner_id] = shop_name
		assigned_owner_ids[owner_id] = true
	return {
		"ok": true,
		"ownedPlaceByResident": owned_place_by_resident,
}


static func _fallback_selected_shop_owner(
	catalog: Dictionary,
	selected_resident_ids: Dictionary,
	assigned_owner_ids: Dictionary,
	shop_name: String,
) -> String:
	var selected_fallback := ""
	for resident_value: Variant in catalog.get("residents", []) as Array:
		if not resident_value is Dictionary:
			continue
		var resident := resident_value as Dictionary
		var resident_id := String(resident.get("residentId", "")).strip_edges()
		if (
			resident_id.is_empty()
			or not selected_resident_ids.has(resident_id)
			or assigned_owner_ids.has(resident_id)
		):
			continue
		if selected_fallback.is_empty():
			selected_fallback = resident_id
		var occupation := resident.get("occupation", {}) as Dictionary
		if String(occupation.get("workplacePlace", "")).strip_edges() == shop_name:
			return resident_id
	return selected_fallback


static func _initial_region_state(
	home_place: Dictionary,
	regions_by_id: Dictionary,
) -> Dictionary:
	for region_id_variant in home_place.get("perceptionRegionIds", []) as Array:
		var region_id := String(region_id_variant)
		var region := regions_by_id.get(region_id, {}) as Dictionary
		if (
			String(region.get("spaceId", "")) != String(home_place.get("spaceId", ""))
			or String(region.get("placeName", "")) != String(home_place.get("name", ""))
		):
			continue
		var position := _position_in_shape(region.get("shape", {}) as Dictionary)
		if position.size() == 2:
			return {
				"ok": true,
				"regionId": region_id,
				"position": position,
			}
	return {"ok": false}


static func _position_in_shape(shape: Dictionary) -> Array:
	var shape_type := String(shape.get("type", ""))
	if shape_type == "rect":
		return [
			float(shape.get("x", 0.0)) + float(shape.get("width", 0.0)) * 0.5,
			float(shape.get("y", 0.0)) + float(shape.get("height", 0.0)) * 0.5,
		]
	if shape_type == "grid_cells":
		var cells := shape.get("cells", []) as Array
		var cell_size := float(shape.get("cellSize", 0.0))
		if not cells.is_empty() and cell_size > 0.0:
			var pair := cells[0] as Array
			return [
				(float(pair[0]) + 0.5) * cell_size,
				(float(pair[1]) + 0.5) * cell_size,
			]
	return []


static func _places_by_space(world_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for place_variant in world_data.get("places", []) as Array:
		var place := place_variant as Dictionary
		if String(place.get("type", "")) == "住家":
			result[String(place.get("spaceId", ""))] = place
	return result


static func _places_by_name(world_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for place_variant in world_data.get("places", []) as Array:
		var place := place_variant as Dictionary
		result[String(place.get("name", ""))] = place
	return result


static func _regions_by_id(world_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for region_variant in world_data.get("perceptionRegions", []) as Array:
		var region := region_variant as Dictionary
		result[String(region.get("id", ""))] = region
	return result


static func _catalog_failure(errors: Array[Dictionary]) -> Dictionary:
	return {
		"ok": false,
		"errorCode": "SESSION_RESIDENT_CATALOG_INVALID",
		"retryable": false,
		"errors": errors,
	}


static func _error(path: String, code: String, meta: Dictionary = {}) -> Dictionary:
	return {
		"path": path,
		"code": code,
		"meta": meta.duplicate(true),
	}


## 金钱系统:按职业分配开局财富(富裕>中产>底层)。
static func _initial_money_for_occupation(occupation_name: String) -> int:
	match occupation_name:
		"杂货店主", "花店店主":
			return 90
		"工匠":
			return 80
		"小镇管理者":
			return 85
		"警察":
			return 90
		"食堂主理人":
			return 70
		"草药医师":
			return 60
		"植物研究员", "仓库管理员", "图书管理员", "邮差":
			return 50
		"渔夫":
			return 45
		"咖啡店店员", "园艺师":
			return 35
		"送货员":
			return 25
		"乐师":
			return 15
	return 40


## 声望系统:按职业分配开局威望(管理者/医师高, 底层低)。
static func _initial_reputation_for_occupation(occupation_name: String) -> int:
	match occupation_name:
		"小镇管理者":
			return 85
		"警察":
			return 95
		"草药医师":
			return 70
		"工匠":
			return 55
		"食堂主理人":
			return 50
		"杂货店主", "花店店主", "植物研究员", "图书管理员", "邮差", "仓库管理员":
			return 45
		"渔夫":
			return 25
		"咖啡店店员", "园艺师":
			return 25
		"送货员":
			return 15
		"乐师":
			return 10
	return 30
