extends "res://tests/support/TownWorldTestCase.gd"
## 内容数据一致性 合并套件。
##
## 由以下测试合并而来，断言逐条保留：
## - town_resident_catalog_test.gd
## - town_resident_interest_contract_test.gd
## - resident_profile_complete_set_test.gd
## - town_resident_interest_runtime_test.gd

class FakeAdapter:
	extends RefCounted

	var last_intent := ""
	var last_payload: Dictionary = {}

	func get_view_model(scope: String) -> Dictionary:
		if scope != "resident_overview":
			return {}
		return {
			"data": {
				"residents": [{
					"residentId": "resident_lin_lan_01",
					"displayName": "林岚",
					"genderLabel": "女",
					"age": 31,
					"appearanceId": "resident_wardrobe_v1:look_01",
					"desire": "照料好自己的生活",
					"personality": "安静可靠",
					"speech": "说话简洁",
					"occupationLabel": "木匠",
					"workplaceLabel": "木工坊",
					"homeLabel": "北街一号住宅",
					"portraitRef": "",
				}],
				"options": {
					"occupations": [{"label": "木匠"}],
					"workplaces": [{"label": "木工坊"}],
					"homes": [{"label": "北街一号住宅"}],
				},
			},
		}

	func dispatch(intent: String, payload: Dictionary = {}) -> Dictionary:
		last_intent = intent
		last_payload = payload.duplicate(true)
		return {"ok": true, "changed": true, "requestId": "fake-request"}

const CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const MOVEMENT := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const WORLD_DATA_PATH := "res://world/data/town/town_world.json"
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const RESIDENTS := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const AGENT_CONTRACT := preload(
	"res://agent/AgentContract.gd"
)
const SERVICE := preload(
	"res://ui/resident_overview/ResidentProfileEditorService.gd"
)


func _initialize() -> void:
	_scenario_resident_catalog()
	_scenario_resident_interest_contract()
	_scenario_resident_profile_complete_set()
	_scenario_resident_interest_runtime()
	_finish_suite("TOWN_RESIDENT_CONTENT_PASS")


func _scenario_resident_catalog() -> void:
	var catalog := CATALOG.load_catalog() as Dictionary
	_verify_candidate_catalog(catalog)
	_verify_world_references(catalog)
	_verify_staffing_warning_contract()
	_verify_world_home_space_failures(catalog)
	_verify_view_model(catalog)
	_verify_confirmation_payload_order()
	_verify_session_projection_confirmation()
	_verify_validation_failures(catalog)
	_verify_copy_boundaries(catalog)
	return
func _verify_candidate_catalog(catalog: Dictionary) -> void:
	var validation := CATALOG.validate(catalog) as Dictionary
	_expect(bool(validation.get("ok", false)), "candidate catalog validates")
	_expect_equal(
		(catalog.get("residents", []) as Array).size(),
		16,
		"candidate catalog contains 16 residents",
	)
	_expect_equal(
		validation.get("selectionLimit"),
		15,
		"validation exposes the 15-home selection limit",
	)
	_expect_equal(
		validation.get("appearanceReady"),
		true,
		"catalog confirms the frozen resident whitebody is available",
	)
	for value: Variant in catalog.get("residents", []) as Array:
		var resident := value as Dictionary
		var attributes := resident.get("attributes", {}) as Dictionary
		_expect(
			String(attributes.get("appearance", "")).begins_with(
				"resident_wardrobe_v1:",
			),
			"candidate profiles publish an approved wardrobe appearance id",
		)



func _verify_world_references(catalog: Dictionary) -> void:
	var world_data := _read_json(WORLD_DATA_PATH)
	_expect_equal(
		world_data.get("worldId"),
		catalog.get("worldId"),
		"resident catalog belongs to the current formal world",
	)
	var places_by_name: Dictionary = {}
	var home_space_ids: Array[String] = []
	for value: Variant in world_data.get("places", []) as Array:
		var place := value as Dictionary
		var place_name := String(place.get("name", ""))
		places_by_name[place_name] = place
		if String(place.get("type", "")) == "住家":
			home_space_ids.append(String(place.get("spaceId", "")))
	home_space_ids.sort()
	_expect_equal(
		home_space_ids.size(),
		CATALOG.SELECTION_LIMIT,
		"formal World exposes exactly the selectable home slots",
	)
	for value: Variant in catalog.get("residents", []) as Array:
		var resident := value as Dictionary
		var occupation := resident.get("occupation", {}) as Dictionary
		var workplace := String(occupation.get("workplacePlace", ""))
		_expect(
			places_by_name.has(workplace),
			"resident workplace resolves in formal World: %s" % workplace,
		)
		_expect(
			not occupation.has("ownedPlace"),
			"resident occupations do not carry legacy shop ownership",
		)
	_expect(
		not catalog.has("shopOwnerCandidates"),
		"resident catalog does not bind formal shops to built-in residents",
	)
	for occupation_value: Variant in world_data.get("occupations", []) as Array:
		var world_occupation := occupation_value as Dictionary
		var occupation_id := String(world_occupation.get("occupationId", ""))
		var occupation_label := String(world_occupation.get("label", ""))
		var primary_workplace := String(
			world_occupation.get("primaryWorkplacePlace", ""),
		)
		_expect(
			not occupation_id.is_empty(),
			"formal occupation publishes a stable id",
		)
		_expect(
			not occupation_label.is_empty(),
			"formal occupation publishes a player-facing label: %s" % occupation_id,
		)
		_expect(
			places_by_name.has(primary_workplace),
			"formal occupation workplace resolves in World: %s" % occupation_label,
		)
	var defaults := catalog.get("openingDefaults", {}) as Dictionary
	var player_avatar := defaults.get("playerAvatar", {}) as Dictionary
	var player_state := player_avatar.get("worldState", {}) as Dictionary
	_expect(
		MOVEMENT.validate_position_state(
			world_data,
			player_state,
		).is_empty(),
		"default player position resolves to the authored place and region",
	)


func _verify_staffing_warning_contract() -> void:
	var world_data := _read_json(WORLD_DATA_PATH)
	var staffing_catalog: Array[Dictionary] = []
	var selected_ids: Array[String] = []
	var world_occupations := world_data.get("occupations", []) as Array
	for index in world_occupations.size():
		var occupation := world_occupations[index] as Dictionary
		var resident_id := "custom_resident_staffing_%02d" % (index + 1)
		selected_ids.append(resident_id)
		staffing_catalog.append({
			"residentId": resident_id,
			"occupation": {
				"name": String(occupation.get("label", "")),
			},
		})
	_expect_equal(
		CATALOG._occupation_staffing_warnings(
			selected_ids,
			staffing_catalog,
			world_data,
		).size(),
		0,
		"a roster covering every formal occupation has no vacancy warning",
	)
	for index in world_occupations.size():
		var occupation := world_occupations[index] as Dictionary
		var selected_without_role := selected_ids.duplicate()
		selected_without_role.remove_at(index)
		var warnings := CATALOG._occupation_staffing_warnings(
			selected_without_role,
			staffing_catalog,
			world_data,
		) as Array[Dictionary]
		_expect_equal(
			warnings.size(),
			1,
			"omitting one occupation reports exactly one vacancy",
		)
		var warning := warnings[0] if warnings.size() == 1 else {}
		_expect_equal(
			warning.get("occupationId"),
			occupation.get("occupationId"),
			"vacancy warning keeps the missing occupation id",
		)
		_expect_equal(
			warning.get("occupationLabel"),
			occupation.get("label"),
			"vacancy warning keeps the missing occupation label",
		)
		_expect_equal(
			warning.get("workplacePlace"),
			occupation.get("primaryWorkplacePlace"),
			"vacancy warning keeps the affected workplace",
		)
		_expect(
			not String(warning.get("vacancyEffect", "")).is_empty(),
			"vacancy warning keeps the authored service effect",
		)



func _verify_world_home_space_failures(catalog: Dictionary) -> void:
	var world_data := _read_json(WORLD_DATA_PATH)
	var missing_home := world_data.duplicate(true)
	var missing_places := missing_home.get("places", []) as Array
	for index in range(missing_places.size() - 1, -1, -1):
		if String((missing_places[index] as Dictionary).get("type", "")) == "住家":
			missing_places.remove_at(index)
			break
	_expect_world_error(
		catalog,
		missing_home,
		"SESSION_CATALOG_HOME_SPACES_INVALID",
		"catalog validation rejects a missing formal home slot",
	)
	var duplicate_home := world_data.duplicate(true)
	var duplicate_home_places := duplicate_home.get("places", []) as Array
	var first_home_space_id := ""
	for place_value: Variant in duplicate_home_places:
		var place := place_value as Dictionary
		if String(place.get("type", "")) != "住家":
			continue
		if first_home_space_id.is_empty():
			first_home_space_id = String(place.get("spaceId", ""))
			continue
		place["spaceId"] = first_home_space_id
		break
	_expect_world_error(
		catalog,
		duplicate_home,
		"SESSION_CATALOG_HOME_SPACES_INVALID",
		"catalog validation rejects duplicate formal home spaces",
	)
	var unknown_home := world_data.duplicate(true)
	for place_value: Variant in unknown_home.get("places", []) as Array:
		var place := place_value as Dictionary
		if String(place.get("type", "")) == "住家":
			place["spaceId"] = "missing_formal_home_space"
			break
	_expect_world_error(
		catalog,
		unknown_home,
		"SESSION_CATALOG_HOME_SPACES_INVALID",
		"catalog validation rejects a home that references an unknown space",
	)



func _verify_view_model(_catalog: Dictionary) -> void:
	var view_model := CATALOG.build_view_model(
		"fake",
		"fake",
		true,
		7,
	) as Dictionary
	_expect_equal(view_model.get("scope"), "resident_selection", "scope is stable")
	var data := view_model.get("data", {}) as Dictionary
	_expect_equal(data.get("source"), "runtime", "candidate catalog never reports placeholder")
	_expect_equal(data.get("capabilityMode"), "formal", "formal capability is explicit")
	_expect_equal(
		data.get("formalReady"),
		true,
		"catalog is formally confirmable with the frozen resident rig",
	)
	_expect_equal(
		data.get("resident_catalog_status"),
		"formal",
		"resident appearance readiness is explicit",
	)
	var pending_vm := CATALOG.build_view_model(
		"fake",
		"fake",
		true,
		8,
	) as Dictionary
	var pending_data := (
		pending_vm.get("data", {}) as Dictionary
	)
	var pending_confirm := (
		(pending_vm.get("actions", {}) as Dictionary).get(
			"confirm",
			{},
		) as Dictionary
	)
	_expect_equal(
		pending_data.get("formalReady"),
		true,
		"frozen resident appearance keeps formal readiness open",
	)
	_expect_equal(
		pending_confirm.get("enabled"),
		true,
		"roster confirmation opens with the frozen resident appearance",
	)
	_expect_equal(
		pending_confirm.get("disabled_reason"),
		"",
		"formal roster confirmation has no disabled reason",
	)
	var pending_custom_resident := (
		(pending_vm.get("actions", {}) as Dictionary).get(
			"custom_resident",
			{},
		) as Dictionary
	)
	_expect_equal(
		pending_custom_resident.get("enabled"),
		true,
		"custom resident creation is available in the formal flow",
	)
	_expect_equal(
		pending_custom_resident.get("disabled_reason"),
		"",
		"formal custom resident action has no disabled reason",
	)
	_expect_equal((data.get("residents", []) as Array).size(), 16, "selection gets 16 residents")
	_expect_equal(
		(data.get("recommended_resident_ids", []) as Array).size(),
		15,
		"recommended selection fills all 15 homes",
	)
	var catalog_by_id: Dictionary = {}
	for catalog_value: Variant in data.get("resident_catalog", []) as Array:
		var catalog_entry := catalog_value as Dictionary
		catalog_by_id[String(catalog_entry.get("residentId", ""))] = catalog_entry
	var recommended_occupations: Dictionary = {}
	for resident_id_value: Variant in data.get("recommended_resident_ids", []) as Array:
		var resident_id := String(resident_id_value)
		var occupation_label := String(
			(
				(catalog_by_id.get(resident_id, {}) as Dictionary).get(
					"occupation",
					{},
				) as Dictionary
			).get("name", ""),
		)
		_expect(
			not occupation_label.is_empty()
			and not recommended_occupations.has(occupation_label),
			"recommended roster covers a distinct current occupation: %s"
				% occupation_label,
		)
		recommended_occupations[occupation_label] = true
	_expect_equal(
		data.get("confirmation_payload"),
		{},
		"an empty selection never exposes a partial roster draft",
	)
	_expect_equal(
		CATALOG.build_view_model(0),
		{},
		"non-positive revisions fail closed",
	)



func _verify_confirmation_payload_order() -> void:
	var view_model := CATALOG.build_view_model(
		"fake",
		"fake",
		true,
		7,
	) as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	var recommended := (
		data.get("recommended_resident_ids", []) as Array
	).duplicate()
	data["selected_resident_ids"] = (
		recommended.duplicate()
	)
	(data.get("selected_resident_ids", []) as Array).reverse()
	(data.get("residents", []) as Array).reverse()
	CATALOG.update_confirmation_payload(
		data,
		"fake",
		"fake",
		8,
	)
	var draft := data.get("confirmation_payload", {}) as Dictionary
	_expect_equal((draft.get("slots", []) as Array).size(), 15, "draft contains 15 slots")
	_expect_equal(
		draft.get("draftRevision"),
		8,
		"draft revision is preserved",
	)
	var slots := draft.get("slots", []) as Array
	var world_data := _read_json(WORLD_DATA_PATH)
	var home_space_ids: Array[String] = []
	for place_value: Variant in world_data.get("places", []) as Array:
		var place := place_value as Dictionary
		if String(place.get("type", "")) == "住家":
			home_space_ids.append(String(place.get("spaceId", "")))
	home_space_ids.sort()
	for index in slots.size():
		var slot := slots[index] as Dictionary
		_expect_equal(
			slot.get("residentId"),
			recommended[index],
			"slot order follows the stable catalog order",
		)
		_expect_equal(
			slot.get("spaceId"),
			home_space_ids[index],
			"slot maps deterministically to an authoritative World home",
		)
		_expect_equal(
			slot.get("llmBinding"),
			{
				"mode": "model",
				"providerId": "fake",
				"modelId": "fake",
			},
			"slot keeps the selected provider and model binding",
		)



func _verify_session_projection_confirmation() -> void:
	var deleted_preset_data := (
		CATALOG.build_view_model(10).get("data", {}) as Dictionary
	)
	var deleted_preset_residents := (
		deleted_preset_data.get("residents", []) as Array
	)
	deleted_preset_residents.pop_back()
	var remaining_ids: Array[String] = []
	for value: Variant in deleted_preset_residents:
		remaining_ids.append(String((value as Dictionary).get("resident_id", "")))
	deleted_preset_data["selected_resident_ids"] = remaining_ids
	CATALOG.update_confirmation_payload(deleted_preset_data, 10)
	_expect_equal(
		(
			(
				deleted_preset_data.get("confirmation_payload", {}) as Dictionary
			).get("slots", []) as Array
		).size(),
		CATALOG.SELECTION_LIMIT,
		"deleting one of 16 presets leaves a confirmable 15-resident draft",
	)

	var below_floor_data := (
		CATALOG.build_view_model(11).get("data", {}) as Dictionary
	)
	var below_floor_residents := (
		below_floor_data.get("residents", []) as Array
	)
	below_floor_residents.pop_back()
	below_floor_residents.pop_back()
	below_floor_data["selected_resident_ids"] = remaining_ids
	below_floor_data["confirmation_payload"] = {"stale": true}
	CATALOG.update_confirmation_payload(below_floor_data, 11)
	_expect_equal(
		below_floor_data.get("confirmation_payload"),
		{},
		"fewer than 15 projected candidates cannot produce a draft",
	)

	var excluded_selection_data := (
		CATALOG.build_view_model(12).get("data", {}) as Dictionary
	)
	excluded_selection_data["selected_resident_ids"] = (
		excluded_selection_data.get("recommended_resident_ids", []) as Array
	).duplicate()
	(
		excluded_selection_data.get("residents", []) as Array
	).pop_front()
	excluded_selection_data["confirmation_payload"] = {"stale": true}
	CATALOG.update_confirmation_payload(excluded_selection_data, 12)
	_expect_equal(
		excluded_selection_data.get("confirmation_payload"),
		{},
		"a selected resident excluded from the projection cannot produce a draft",
	)

	var custom_data := (
		CATALOG.build_view_model(13).get("data", {}) as Dictionary
	)
	var custom_id := "custom_resident_0123456789abcdef01234567_0001"
	var custom_entry := _formal_custom_catalog_entry(custom_id)
	(custom_data.get("resident_catalog", []) as Array).append(custom_entry)
	(custom_data.get("residents", []) as Array).append({
		"resident_id": custom_id,
		"source": "custom",
	})
	var custom_selection := (
		custom_data.get("recommended_resident_ids", []) as Array
	).slice(0, CATALOG.SELECTION_LIMIT - 1)
	custom_selection.append(custom_id)
	custom_data["selected_resident_ids"] = custom_selection
	CATALOG.update_confirmation_payload(custom_data, 13)
	var custom_slots := (
		(
			custom_data.get("confirmation_payload", {}) as Dictionary
		).get("slots", []) as Array
	)
	_expect_equal(
		custom_slots.size(),
		CATALOG.SELECTION_LIMIT,
		"a formally merged custom resident can join a 15-resident draft",
	)
	if custom_slots.size() == CATALOG.SELECTION_LIMIT:
		_expect_equal(
			(custom_slots.back() as Dictionary).get("residentId"),
			custom_id,
			"custom selection follows the merged session catalog order",
		)
	var forged_custom_data := (
		CATALOG.build_view_model(14).get("data", {}) as Dictionary
	)
	(forged_custom_data.get("resident_catalog", []) as Array).append({
		"residentId": custom_id,
		"source": "custom",
	})
	(forged_custom_data.get("residents", []) as Array).append({
		"resident_id": custom_id,
		"source": "custom",
	})
	forged_custom_data["selected_resident_ids"] = custom_selection
	CATALOG.update_confirmation_payload(forged_custom_data, 14)
	_expect_equal(
		forged_custom_data.get("confirmation_payload"),
		{},
		"a custom id and source cannot authorize a forged minimal catalog entry",
	)
	var legacy_custom_data := (
		CATALOG.build_view_model(15).get("data", {}) as Dictionary
	)
	var legacy_custom_entry := custom_entry.duplicate(true)
	(
		legacy_custom_entry.get("attributes", {}) as Dictionary
	)["appearance"] = "paper_doll_64:legacy"
	(legacy_custom_data.get("resident_catalog", []) as Array).append(
		legacy_custom_entry,
	)
	(legacy_custom_data.get("residents", []) as Array).append({
		"resident_id": custom_id,
		"source": "custom",
	})
	legacy_custom_data["selected_resident_ids"] = custom_selection
	CATALOG.update_confirmation_payload(legacy_custom_data, 15)
	_expect_equal(
		legacy_custom_data.get("confirmation_payload"),
		{},
		"legacy attributes.appearance cannot enter a custom confirmation draft",
	)



func _verify_validation_failures(catalog: Dictionary) -> void:
	var fractional_schema := catalog.duplicate(true)
	fractional_schema["schemaVersion"] = 1.5
	_expect_error(
		fractional_schema,
		"SESSION_CATALOG_SCHEMA_UNSUPPORTED",
		"schema version must be an integer",
	)
	var numeric_world := catalog.duplicate(true)
	numeric_world["worldId"] = 123
	_expect_error(
		numeric_world,
		"SESSION_CATALOG_WORLD_MISMATCH",
		"world id must be the town string",
	)
	var wrong_shape := catalog.duplicate(true)
	(wrong_shape.get("residents", []) as Array)[0] = "invalid"
	_expect_error(
		wrong_shape,
		"SESSION_CATALOG_RESIDENT_INVALID",
		"resident entries must be dictionaries",
	)
	var unexpected_catalog_field := catalog.duplicate(true)
	unexpected_catalog_field["legacyPortraitCatalog"] = []
	_expect_error(
		unexpected_catalog_field,
		"SESSION_CATALOG_SHAPE_INVALID",
		"catalog root rejects fields outside the pending contract",
	)
	var unexpected_resident_field := catalog.duplicate(true)
	(
		(unexpected_resident_field.get("residents", []) as Array)[0]
		as Dictionary
	)["legacyAnimation"] = "walk"
	_expect_error(
		unexpected_resident_field,
		"SESSION_CATALOG_RESIDENT_INVALID",
		"resident entries reject fields outside the pending contract",
	)
	var missing_attribute := catalog.duplicate(true)
	var first := (
		(missing_attribute.get("residents", []) as Array)[0] as Dictionary
	)
	(first.get("attributes", {}) as Dictionary)["personality"] = ""
	_expect_error(
		missing_attribute,
		"SESSION_CATALOG_ATTRIBUTE_REQUIRED",
		"required Agent attributes cannot be empty",
	)
	var bad_age := catalog.duplicate(true)
	(
		(
			(bad_age.get("residents", []) as Array)[0] as Dictionary
		).get("attributes", {}) as Dictionary
	)["age"] = 27.5
	_expect_error(
		bad_age,
		"SESSION_CATALOG_AGE_INVALID",
		"resident age must be a positive integer",
	)
	var impossible_age := catalog.duplicate(true)
	(
		(
			(impossible_age.get("residents", []) as Array)[0] as Dictionary
		).get("attributes", {}) as Dictionary
	)["age"] = 121
	_expect_error(
		impossible_age,
		"SESSION_CATALOG_AGE_INVALID",
		"resident age must stay within the World opening contract",
	)
	var bad_gender := catalog.duplicate(true)
	(
		(
			(bad_gender.get("residents", []) as Array)[0] as Dictionary
		).get("attributes", {}) as Dictionary
	)["gender"] = "未知"
	_expect_error(
		bad_gender,
		"SESSION_CATALOG_GENDER_INVALID",
		"resident gender must use the formal values",
	)
	var retired_appearance := catalog.duplicate(true)
	(
		(
			(retired_appearance.get("residents", []) as Array)[0] as Dictionary
		).get("attributes", {}) as Dictionary
	)["appearance"] = "paper_doll_64:neutral_hoodie"
	_expect_error(
		retired_appearance,
		"SESSION_CATALOG_WARDROBE_INVALID",
		"legacy appearance ids cannot bypass the approved wardrobe binding",
	)
	var retired_sprite_path := catalog.duplicate(true)
	(
		(
			(retired_sprite_path.get("residents", []) as Array)[0]
			as Dictionary
		).get("presentation", {}) as Dictionary
	)["spritePath"] = "res://retired_character.png"
	_expect_error(
		retired_sprite_path,
		"SESSION_CATALOG_PORTRAIT_MISSING",
		"missing resident sprite paths fail closed",
	)
	var retired_animation_field := catalog.duplicate(true)
	(
		(
			(retired_animation_field.get("residents", []) as Array)[0]
			as Dictionary
		).get("presentation", {}) as Dictionary
	)["animation"] = "walk"
	_expect_error(
		retired_animation_field,
		"SESSION_CATALOG_PRESENTATION_INVALID",
		"resident animation fields wait for the 2D rig contract",
	)
	var retired_portrait_field := catalog.duplicate(true)
	(
		(
			(retired_portrait_field.get("residents", []) as Array)[0]
			as Dictionary
		).get("attributes", {}) as Dictionary
	)["portrait"] = "legacy_portrait"
	_expect_error(
		retired_portrait_field,
		"SESSION_CATALOG_ATTRIBUTE_INVALID",
		"resident portrait fields wait for the 2D rig contract",
	)
	var false_appearance_status := catalog.duplicate(true)
	false_appearance_status["appearanceStatus"] = "ready"
	_expect_error(
		false_appearance_status,
		"SESSION_CATALOG_APPEARANCE_STATUS_INVALID",
		"catalog cannot claim appearance readiness before the asset contract lands",
	)
	var duplicate_id := catalog.duplicate(true)
	var duplicate_residents := duplicate_id.get("residents", []) as Array
	(duplicate_residents[1] as Dictionary)["residentId"] = String(
		(duplicate_residents[0] as Dictionary).get("residentId", "")
	)
	_expect_error(
		duplicate_id,
		"SESSION_CATALOG_RESIDENT_ID_INVALID",
		"resident ids must be unique",
	)
	var unsafe_id := catalog.duplicate(true)
	(unsafe_id.get("residents", []) as Array)[0]["residentId"] = "resident_unsafe/path"
	_expect_error(
		unsafe_id,
		"SESSION_CATALOG_RESIDENT_ID_INVALID",
		"resident ids must remain safe stable identifiers",
	)
	var duplicate_name := catalog.duplicate(true)
	var duplicate_name_residents := duplicate_name.get("residents", []) as Array
	(
		(duplicate_name_residents[1] as Dictionary).get(
			"attributes",
			{},
		) as Dictionary
	)["name"] = String(
		(
			(duplicate_name_residents[0] as Dictionary).get(
				"attributes",
				{},
			) as Dictionary
		).get("name", ""),
	)
	_expect(
		bool(CATALOG.validate(duplicate_name).get("ok", false)),
		"same display names remain legal because resident ids are authoritative",
	)
	var fixed_owner := catalog.duplicate(true)
	(
		(
			(fixed_owner.get("residents", []) as Array)[0] as Dictionary
		).get("occupation", {}) as Dictionary
	)["ownedPlace"] = "花房咖啡馆"
	_expect_error(
		fixed_owner,
		"SESSION_CATALOG_OWNED_PLACE_DEPRECATED",
		"candidate records cannot make shop ownership selection-dependent",
	)
	var unexpected_occupation_field := catalog.duplicate(true)
	(
		(
			(unexpected_occupation_field.get("residents", []) as Array)[0]
			as Dictionary
		).get("occupation", {}) as Dictionary
	)["legacyRole"] = "咖啡师"
	_expect_error(
		unexpected_occupation_field,
		"SESSION_CATALOG_OCCUPATION_INVALID",
		"resident occupations reject fields outside the pending contract",
	)
	var wrong_location := catalog.duplicate(true)
	(
		(
			(wrong_location.get("residents", []) as Array)[0] as Dictionary
		).get("presentation", {}) as Dictionary
	)["locationLabel"] = "不存在的地点"
	_expect_error(
		wrong_location,
		"SESSION_CATALOG_LOCATION_INVALID",
		"selection location must match the authored workplace",
	)
	var unknown_workplace := catalog.duplicate(true)
	var unknown_workplace_resident := (
		(unknown_workplace.get("residents", []) as Array)[0]
		as Dictionary
	)
	(
		unknown_workplace_resident.get("occupation", {}) as Dictionary
	)["workplacePlace"] = "不存在的地点"
	(
		unknown_workplace_resident.get("presentation", {}) as Dictionary
	)["locationLabel"] = "不存在的地点"
	_expect_error(
		unknown_workplace,
		"SESSION_CATALOG_WORKPLACE_UNKNOWN",
		"resident workplaces must resolve in the formal World",
	)
	var bad_clock := catalog.duplicate(true)
	(
		(bad_clock.get("openingDefaults", {}) as Dictionary).get(
			"environment",
			{},
		) as Dictionary
	)["clock"] = "24:00"
	_expect_error(
		bad_clock,
		"SESSION_CATALOG_ENVIRONMENT_INVALID",
		"opening clock must be a real time",
	)
	for signed_clock in ["+1:00", "-0:00"]:
		var signed_clock_catalog := catalog.duplicate(true)
		(
			(signed_clock_catalog.get("openingDefaults", {}) as Dictionary)
			.get("environment", {}) as Dictionary
		)["clock"] = signed_clock
		_expect_error(
			signed_clock_catalog,
			"SESSION_CATALOG_ENVIRONMENT_INVALID",
			"opening clock only accepts ASCII HH:MM: %s" % signed_clock,
		)
	var oversized_day := catalog.duplicate(true)
	(
		(oversized_day.get("openingDefaults", {}) as Dictionary).get(
			"environment",
			{},
		) as Dictionary
	)["day"] = CATALOG.MAX_SAFE_DAY + 1
	_expect_error(
		oversized_day,
		"SESSION_CATALOG_ENVIRONMENT_INVALID",
		"opening day must stay inside the formal opening time range",
	)
	var unsafe_random_seed := catalog.duplicate(true)
	(
		(unsafe_random_seed.get("openingDefaults", {}) as Dictionary).get(
			"environment",
			{},
		) as Dictionary
	)["randomSeed"] = CATALOG.MAX_SAFE_INTEGER + 1.0
	_expect_error(
		unsafe_random_seed,
		"SESSION_CATALOG_ENVIRONMENT_INVALID",
		"opening random seed must remain exactly representable",
	)
	var extra_body_state := catalog.duplicate(true)
	(
		(extra_body_state.get("openingDefaults", {}) as Dictionary).get(
			"residentBody",
			{},
		) as Dictionary
	)["渴"] = "不渴"
	_expect_error(
		extra_body_state,
		"SESSION_CATALOG_RESIDENT_BODY_INVALID",
		"resident opening body rejects fields outside the formal contract",
	)
	var padded_avatar_name := catalog.duplicate(true)
	(
		(padded_avatar_name.get("openingDefaults", {}) as Dictionary).get(
			"playerAvatar",
			{},
		) as Dictionary
	)["name"] = " 旅行者"
	_expect_error(
		padded_avatar_name,
		"SESSION_CATALOG_PLAYER_AVATAR_INVALID",
		"player avatar text must not depend on downstream trimming",
	)
	var out_of_range_avatar_position := catalog.duplicate(true)
	(
		(
			(out_of_range_avatar_position.get("openingDefaults", {}) as Dictionary)
			.get("playerAvatar", {}) as Dictionary
		).get("worldState", {}) as Dictionary
	)["position"] = [CATALOG.MAX_CANVAS_COMPONENT + 1.0, 3180]
	_expect_error(
		out_of_range_avatar_position,
		"SESSION_CATALOG_PLAYER_AVATAR_INVALID",
		"player avatar coordinates match the formal canvas limit",
	)
	var outside_avatar_position := catalog.duplicate(true)
	(
		(
			(outside_avatar_position.get("openingDefaults", {}) as Dictionary)
			.get("playerAvatar", {}) as Dictionary
		).get("worldState", {}) as Dictionary
	)["position"] = [0, 0]
	_expect_error(
		outside_avatar_position,
		"SESSION_CATALOG_PLAYER_AVATAR_INVALID",
		"player avatar position must belong to a formal World region",
	)
	var mismatched_avatar_region := catalog.duplicate(true)
	(
		(
			(mismatched_avatar_region.get("openingDefaults", {}) as Dictionary)
			.get("playerAvatar", {}) as Dictionary
		).get("worldState", {}) as Dictionary
	)["regionId"] = "outdoor_plaza_01"
	_expect_error(
		mismatched_avatar_region,
		"SESSION_CATALOG_PLAYER_AVATAR_INVALID",
		"player avatar position must match its declared region and place",
	)
	var missing_arrival_text := catalog.duplicate(true)
	(
		missing_arrival_text.get("openingDefaults", {}) as Dictionary
	)["residentDoing"] = "  "
	_expect_error(
		missing_arrival_text,
		"SESSION_CATALOG_RESIDENT_DOING_INVALID",
		"resident opening text stays non-empty",
	)
	var invalid_payload_data := {
		"selected_resident_ids": "invalid",
		"residents": [],
		"confirmation_payload": {"stale": true},
	}
	CATALOG.update_confirmation_payload(
		invalid_payload_data,
		1,
	)
	_expect_equal(
		invalid_payload_data.get("confirmation_payload"),
		{},
		"invalid selection state clears stale confirmation data",
	)
	var partial_payload_data := {
		"selected_resident_ids": ["resident_hanako_01"],
		"residents": (
			CATALOG.build_view_model(2).get("data", {}) as Dictionary
		).get("residents", []),
		"confirmation_payload": {"stale": true},
	}
	CATALOG.update_confirmation_payload(partial_payload_data, 2)
	_expect_equal(
		partial_payload_data.get("confirmation_payload"),
		{},
		"partial selections never expose a confirmable draft",
	)
	var duplicate_selection_data := (
		CATALOG.build_view_model(3).get("data", {}) as Dictionary
	)
	var duplicate_selection := (
		duplicate_selection_data.get(
			"recommended_resident_ids",
			[],
		) as Array
	).duplicate()
	duplicate_selection[1] = duplicate_selection[0]
	duplicate_selection_data["selected_resident_ids"] = duplicate_selection
	duplicate_selection_data["confirmation_payload"] = {"stale": true}
	CATALOG.update_confirmation_payload(duplicate_selection_data, 3)
	_expect_equal(
		duplicate_selection_data.get("confirmation_payload"),
		{},
		"duplicate selections never expose a confirmable draft",
	)
	var duplicate_projection_data := (
		CATALOG.build_view_model(4).get("data", {}) as Dictionary
	)
	duplicate_projection_data["selected_resident_ids"] = (
		duplicate_projection_data.get(
			"recommended_resident_ids",
			[],
		) as Array
	).duplicate()
	var duplicate_projection := (
		duplicate_projection_data.get("residents", []) as Array
	)
	duplicate_projection[1] = (duplicate_projection[0] as Dictionary).duplicate(true)
	duplicate_projection_data["confirmation_payload"] = {"stale": true}
	CATALOG.update_confirmation_payload(duplicate_projection_data, 4)
	_expect_equal(
		duplicate_projection_data.get("confirmation_payload"),
		{},
		"duplicate projected resident ids never expose a confirmable draft",
	)
	var incomplete_projection_data := (
		CATALOG.build_view_model(5).get("data", {}) as Dictionary
	)
	incomplete_projection_data["selected_resident_ids"] = (
		incomplete_projection_data.get(
			"recommended_resident_ids",
			[],
		) as Array
	).duplicate()
	(
		incomplete_projection_data.get("residents", []) as Array
	).pop_back()
	(
		incomplete_projection_data.get("residents", []) as Array
	).pop_back()
	incomplete_projection_data["confirmation_payload"] = {"stale": true}
	CATALOG.update_confirmation_payload(incomplete_projection_data, 5)
	_expect_equal(
		incomplete_projection_data.get("confirmation_payload"),
		{},
		"resident projections below the 15-candidate floor never expose a draft",
	)
	var forged_projection_data := (
		CATALOG.build_view_model(6).get("data", {}) as Dictionary
	)
	var forged_selection := (
		forged_projection_data.get(
			"recommended_resident_ids",
			[],
		) as Array
	).duplicate()
	var forged_projection := (
		forged_projection_data.get("residents", []) as Array
	)
	var original_first_id := String(forged_selection[0])
	var forged_id := "resident_forged_01"
	(forged_projection[0] as Dictionary)["resident_id"] = forged_id
	forged_selection[forged_selection.find(original_first_id)] = forged_id
	forged_projection_data["selected_resident_ids"] = forged_selection
	forged_projection_data["confirmation_payload"] = {"stale": true}
	CATALOG.update_confirmation_payload(forged_projection_data, 6)
	_expect_equal(
		forged_projection_data.get("confirmation_payload"),
		{},
		"resident projections cannot authorize ids outside the formal catalog",
	)



func _verify_copy_boundaries(catalog: Dictionary) -> void:
	var reloaded := CATALOG.load_catalog() as Dictionary
	var first := (reloaded.get("residents", []) as Array)[0] as Dictionary
	(first.get("attributes", {}) as Dictionary)["name"] = "被调用方修改"
	var second_load := CATALOG.load_catalog() as Dictionary
	_expect(
		String(
			(
				(
					(second_load.get("residents", []) as Array)[0]
					as Dictionary
				).get("attributes", {}) as Dictionary
			).get("name", "")
		) != "被调用方修改",
		"catalog loads return detached data",
	)


	var view_model := CATALOG.build_view_model(3) as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	var resident_catalog := data.get("resident_catalog", []) as Array
	var projected := data.get("residents", []) as Array
	(
		(
			(resident_catalog[0] as Dictionary).get("attributes", {})
			as Dictionary
		)
	)["name"] = "目录投影被修改"
	(projected[0] as Dictionary)["display_name"] = "列表投影被修改"
	var rebuilt := CATALOG.build_view_model(4) as Dictionary
	var rebuilt_data := rebuilt.get("data", {}) as Dictionary
	var rebuilt_catalog := (
		rebuilt_data.get("resident_catalog", []) as Array
	)
	var rebuilt_projection := rebuilt_data.get("residents", []) as Array
	_expect(
		String(
			(
				(
					(rebuilt_catalog[0] as Dictionary)
					.get("attributes", {}) as Dictionary
				).get("name", "")
			)
		) != "目录投影被修改",
		"catalog projections are rebuilt from detached source data",
	)
	_expect(
		String(
			(rebuilt_projection[0] as Dictionary).get(
				"display_name",
				"",
			)
		) != "列表投影被修改",
		"resident-card projections are rebuilt from detached source data",
	)
	_expect(
		String(
			(
				(
					(catalog.get("residents", []) as Array)[0]
					as Dictionary
				).get("attributes", {}) as Dictionary
			).get("name", "")
		) != "目录投影被修改",
		"view-model data cannot mutate the loaded source",
	)



func _formal_custom_catalog_entry(resident_id: String) -> Dictionary:
	var atlas_ref := (
		"res://assets/characters/paper_doll_64/compiled/"
		+ "neutral_hoodie_walk_64.png"
	)
	var portrait_ref := (
		"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
		+ "classic_sets/runtime_portraits/lin_lan_front.png"
	)
	return {
		"residentId": resident_id,
		"attributes": {
			"name": "自定义居民",
			"gender": "女",
			"age": 29,
			"appearance": "resident_wardrobe_v1:look_01",
			"desire": "参与小镇生活",
			"personality": "耐心且谨慎",
			"speech": "先核对事实再回答",
			"interests": ["interest_gardening"],
			"customInterests": [],
			"selectionSummary": "耐心且谨慎",
		},
		"occupation": {
			"name": "园丁",
			"workplacePlace": "社区花园",
		},
		"presentation": {
			"spritePath": atlas_ref,
			"portraitPath": portrait_ref,
			"locationLabel": "社区花园",
		},
		"source": "custom",
	}



func _expect_error(
	catalog: Dictionary,
	expected_code: String,
	message: String,
) -> void:
	var result := CATALOG.validate(catalog) as Dictionary
	_expect_equal(
		result.get("ok"),
		false,
		"%s rejects invalid data" % message,
	)
	_expect_equal(
		result.get("errorCode"),
		expected_code,
		message,
	)



func _expect_world_error(
	catalog: Dictionary,
	world_data: Dictionary,
	expected_code: String,
	message: String,
) -> void:
	var result := CATALOG.validate_against_world(
		catalog,
		world_data,
	) as Dictionary
	_expect_equal(
		result.get("ok"),
		false,
		"%s rejects invalid data" % message,
	)
	_expect_equal(result.get("errorCode"), expected_code, message)



func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	return parsed as Dictionary if parsed is Dictionary else {}



func _scenario_resident_interest_contract() -> void:
	var interest_catalog := INTERESTS.load_catalog() as Dictionary
	_expect(
		not interest_catalog.is_empty(),
		"formal interest catalog loads",
	)
	_expect_equal(
		INTERESTS.max_interests(interest_catalog),
		3,
		"one resident can keep at most three interests",
	)
	_expect_equal(
		INTERESTS.options(interest_catalog).size(),
		15,
		"the initial interest catalog exposes fifteen themes",
	)
	_expect_equal(
		INTERESTS.validation_error([
			"interest_reading",
			"interest_writing",
			"interest_calligraphy",
		]),
		"",
		"three known unique interests are valid",
	)
	_expect_equal(
		INTERESTS.validation_error([
			"interest_reading",
			"interest_reading",
		]),
		"RESIDENT_INTERESTS_INVALID",
		"duplicate interests fail closed",
	)
	_expect_equal(
		INTERESTS.validation_error(["interest_unknown"]),
		"RESIDENT_INTEREST_UNKNOWN",
		"unknown interests fail closed",
	)
	_expect_equal(
		INTERESTS.validation_error([
			"interest_reading",
			"interest_writing",
			"interest_calligraphy",
			"interest_music",
		]),
		"RESIDENT_INTERESTS_TOO_MANY",
		"more than three interests fail closed",
	)
	_expect_equal(
		INTERESTS.profile_validation_error(
			["interest_reading", "interest_writing"],
			["收集旧邮戳"],
		),
		"",
		"catalog and custom interests share the three-item limit",
	)
	_expect_equal(
		INTERESTS.profile_validation_error(
			["interest_reading", "interest_writing"],
			["收集旧邮戳", "听雨"],
		),
		"RESIDENT_INTERESTS_TOO_MANY",
		"catalog and custom interests cannot exceed three in total",
	)
	_expect_equal(
		INTERESTS.profile_validation_error(
			["interest_reading"],
			["阅读"],
		),
		"RESIDENT_CUSTOM_INTERESTS_INVALID",
		"custom interests cannot duplicate a selected catalog label",
	)

	var resident_catalog := RESIDENTS.load_catalog() as Dictionary
	_expect_equal(
		(RESIDENTS.validate(resident_catalog) as Dictionary).get("ok"),
		true,
		"default resident catalog accepts the interest field",
	)
	var residents := resident_catalog.get("residents", []) as Array
	_expect_equal(residents.size(), 16, "all sixteen preset templates load")
	for resident_value: Variant in residents:
		var resident := resident_value as Dictionary
		var attributes := resident.get("attributes", {}) as Dictionary
		_expect(
			attributes.has("interests"),
			"%s writes interests explicitly"
			% String(resident.get("residentId", "")),
		)
		_expect(
			attributes.has("customInterests"),
			"%s writes custom interests explicitly"
			% String(resident.get("residentId", "")),
		)
		_expect_equal(
			INTERESTS.profile_validation_error(
				attributes.get("interests"),
				attributes.get("customInterests"),
			),
			"",
			"%s uses registered unique interests"
			% String(resident.get("residentId", "")),
		)

	var migrated := INTERESTS.migrate_attributes({
		"name": "旧居民",
	}) as Dictionary
	_expect_equal(
		migrated.get("interests"),
		[],
		"legacy profiles without interests migrate to an empty list",
	)
	_expect_equal(
		migrated.get("customInterests"),
		[],
		"legacy profiles without custom interests migrate to an empty list",
	)

	var initialization := _initialization()
	_expect_equal(
		AGENT_CONTRACT.validate_initialization(initialization),
		[],
		"Agent initialization accepts a valid interest list",
	)
	var legacy_initialization := initialization.duplicate(true)
	(
		(
			legacy_initialization.get("me", {}) as Dictionary
		).get("attributes", {}) as Dictionary
	).erase("interests")
	_expect_equal(
		AGENT_CONTRACT.validate_initialization(legacy_initialization),
		[],
		"Agent initialization remains compatible with legacy profiles",
	)
	var invalid_initialization := initialization.duplicate(true)
	(
		(
			invalid_initialization.get("me", {}) as Dictionary
		).get("attributes", {}) as Dictionary
	)["interests"] = ["interest_unknown"]
	_expect(
		not AGENT_CONTRACT.validate_initialization(
			invalid_initialization,
		).is_empty(),
		"Agent initialization rejects an unregistered interest",
	)

	return
func _initialization() -> Dictionary:
	return {
		"me": {
			"resident_id": "resident-interest-test",
			"attributes": {
				"name": "青禾",
				"gender": "女",
				"age": 26,
				"desire": "把看见的事情认真记下来",
				"personality": "耐心，愿意求证",
				"speech": "说话简洁",
				"interests": [
					"interest_reading",
					"interest_plant_research",
				],
				"customInterests": ["制作植物标本"],
			},
			"social_state": {
				"home": "青禾家",
				"job": "植物研究员",
				"workplace": "社区花园",
			},
		},
		"residents": [],
		"places": [],
	}



func _scenario_resident_profile_complete_set() -> void:
	var service: RefCounted = SERVICE.new()
	var adapter := FakeAdapter.new()
	var configured := service.call(
		"configure",
		adapter,
		"resident_lin_lan_01",
	) as Dictionary
	_expect(bool(configured.get("ok", false)), "profile service configures")
	var view_model := service.call("get_view_model") as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	var actions := view_model.get("actions", {}) as Dictionary
	_expect(
		bool((actions.get("openWardrobe", {}) as Dictionary).get("enabled", false)),
		"complete-set wardrobe route is available",
	)
	var opened := service.call(
		"dispatch",
		"resident_profile_editor.open_wardrobe",
		{
			"revision": int(view_model.get("revision", -1)),
			"draftId": String(data.get("draftId", "")),
		},
	) as Dictionary
	_expect(bool(opened.get("ok", false)), "wardrobe handoff opens")
	var handoff := opened.get("wardrobeHandoff", {}) as Dictionary
	var applied := service.call(
		"dispatch",
		"resident_profile_editor.apply_wardrobe_result",
		{
			"revision": int(handoff.get("returnRevision", -1)),
			"draftId": String(handoff.get("draftId", "")),
			"loadoutId": "look_15",
			# The complete-set id is authoritative. The legacy four-slot
			# selection remains in the payload only for old saves/callers.
			"selection": {
				"hair": "soft_bob_brown",
				"top": "sage_daily",
				"bottom": "sage_daily",
				"shoes": "sage_daily",
			},
		},
	) as Dictionary
	_expect(bool(applied.get("ok", false)), "complete set applies by loadout id")
	var appearance := (
		applied.get("resolvedAppearance", {}) as Dictionary
	)
	_expect(
		String(appearance.get("appearanceId", ""))
		== "resident_wardrobe_v1:look_15",
		"loadout id resolves the selected complete character",
	)
	_expect(
		String(appearance.get("portraitPath", "")).ends_with(
			"classic_sets/runtime_portraits/shen_qiao_front.png"
		),
		"complete set keeps its matching portrait",
	)
	view_model = service.call("get_view_model") as Dictionary
	data = view_model.get("data", {}) as Dictionary
	var interest_update := service.call(
		"dispatch",
		"resident_profile_editor.update_fields",
		{
			"revision": int(view_model.get("revision", -1)),
			"draftId": String(data.get("draftId", "")),
			"fields": {
				"interests": ["interest_reading"],
				"customInterests": ["收集旧邮戳"],
			},
		},
	) as Dictionary
	_expect(bool(interest_update.get("ok", false)), "resident interests update")
	view_model = service.call("get_view_model") as Dictionary
	data = view_model.get("data", {}) as Dictionary
	var saved := service.call(
		"dispatch",
		"resident_profile_editor.save_existing",
		{
			"revision": int(view_model.get("revision", -1)),
			"draftId": String(data.get("draftId", "")),
			"residentId": "resident_lin_lan_01",
		},
	) as Dictionary
	_expect(bool(saved.get("ok", false)), "resident interests save")
	var saved_profile := adapter.last_payload.get("profile", {}) as Dictionary
	var saved_attributes := saved_profile.get("attributes", {}) as Dictionary
	_expect(
		saved_attributes.get("interests", []) == ["interest_reading"],
		"catalog interest reaches the World update payload",
	)
	_expect(
		saved_attributes.get("customInterests", []) == ["收集旧邮戳"],
		"custom interest reaches the World update payload",
	)



func _scenario_resident_interest_runtime() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(
		OPENING_PATH,
		data,
	) as Dictionary
	_expect(opening_result.get("ok") == true, "兴趣运行测试开局可加载")
	if opening_result.get("ok") != true:
		return
	var config := (
		opening_result.get("config", {}) as Dictionary
	).duplicate(true)
	for resident_value: Variant in config.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		if String(resident.get("residentId", "")) != "resident_ye_cheng_01":
			continue
		var attributes := resident.get("attributes", {}) as Dictionary
		attributes["interests"] = ["interest_fishing"]
		attributes["customInterests"] = ["收集旧鱼钩"]
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, config) as Dictionary
	_expect(started.get("ok") == true, "带目录和自定义兴趣的 World 可启动")
	if started.get("ok") != true:
		return
	var initialization := world.call(
		"get_agent_initialization",
		"resident_ye_cheng_01",
	) as Dictionary
	var me := initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	_expect(
		attributes.get("interests", []) == ["interest_fishing"],
		"目录兴趣进入本人 Agent 初始化资料",
	)
	_expect(
		attributes.get("customInterests", []) == ["收集旧鱼钩"],
		"自定义兴趣进入本人 Agent 初始化资料",
	)
	var requests := world.call(
		"take_pending_decision_requests",
		["叶澄"],
	) as Array
	_expect(not requests.is_empty(), "兴趣居民能取得开局决定请求")
	if not requests.is_empty():
		var wake := (
			(requests[0] as Dictionary).get("wakePacket", {}) as Dictionary
		)
		var place := (
			(wake.get("snapshot", {}) as Dictionary).get("place", {}) as Dictionary
		)
		var has_interest_match := false
		for activity_value: Variant in place.get("activities", []) as Array:
			if (
				activity_value is Dictionary
				and bool(
					(activity_value as Dictionary).get(
						"interest_match",
						false,
					)
				)
				and (
					(activity_value as Dictionary).get(
						"matched_interests",
						[],
					) as Array
				).has("钓鱼")
			):
				has_interest_match = true
				break
		_expect(
			has_interest_match,
			"World 把当前合法活动与目录兴趣匹配后交给 Agent",
		)
	var save_result := world.call("create_save_snapshot") as Dictionary
	_expect(save_result.get("ok") == true, "带自定义兴趣的世界可存档")
	if save_result.get("ok") == true:
		var restored: RefCounted = WORLD.new()
		var restore_result := restored.call(
			"restore_from_snapshot",
			data,
			config,
			save_result.get("snapshot", {}) as Dictionary,
		) as Dictionary
		_expect(restore_result.get("ok") == true, "带自定义兴趣的世界可读档")
		if restore_result.get("ok") == true:
			var restored_initialization := restored.call(
				"get_agent_initialization",
				"resident_ye_cheng_01",
			) as Dictionary
			var restored_attributes := (
				(restored_initialization.get("me", {}) as Dictionary).get(
					"attributes",
					{},
				) as Dictionary
			)
			_expect(
				restored_attributes.get("customInterests", [])
					== ["收集旧鱼钩"],
				"自定义兴趣在存档与读档后保持不变",
			)
			restored.call("stop")
	world.call("stop")
	return
