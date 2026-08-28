class_name TownWorldActivityValidator
extends RefCounted

const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const STATE_KEYS := [
	"energy",
	"satiety",
	"stress",
	"socialNeed",
	"solitudeNeed",
]
const WORKPLACE_POLICIES := ["required", "optional", "route_based", "none"]
const DYNAMIC_WORK_TARGET_RULES := [
	"task_audience_area",
	"task_authorized_resident",
	"task_cargo_destination",
	"task_cargo_lot",
	"task_cargo_source",
	"task_fishing_region",
	"task_message_recipient_current_place",
	"task_own_home_workspace",
	"task_plant_region",
	"task_public_place",
]
const ACTIVITY_KINDS := ["work", "need", "leisure", "social", "service"]
const RESULT_CONTRACT_MODES := [
	"create_task",
	"advance_task",
	"complete_task",
]
const RESULT_EVIDENCE_FIELDS := [
	"taskId",
	"residentId",
	"workerResidentId",
	"subjectId",
	"itemId",
	"content",
	"targetPlaceId",
]
const TARGET_TYPES := ["prop", "point", "region", "route"]
const SLOT_ROLES := ["worker", "visitor", "participant", "observer"]
const FACINGS := ["up", "down", "left", "right"]
const FALLBACKS := ["reject", "same_activity_other_slot"]
const SCHEDULE_ROLES := ["worker"]
const SCHEDULE_GOAL_IDS := ["occupation_activity"]
const SCHEDULE_MINUTE_RANGE := [0, 1440]
const SCHEDULE_WINDOW_BOUNDARY := "start_inclusive_end_exclusive"
const SCHEDULE_WINDOW_ORDERING := "authored_start_then_window_id"
const SCHEDULE_OUTPUT := "goal_pressure_only"
const SCHEDULE_PLAN_OWNER := "resident_agent"
const PUBLIC_REQUIRED_TARGET_FIELDS := ["activityId", "placeId"]
const PUBLIC_OPTIONAL_TARGET_FIELDS := ["preferredSlotId"]
const PUBLIC_OPTIONAL_PARAMS_FIELDS := ["reason"]
const PUBLIC_WORLD_QUERY_FIELDS := [
	"activityId",
	"label",
	"placeId",
	"role",
	"available",
	"disabledReason",
	"preferredSlots",
]
const PUBLIC_ERROR_CODES := [
	"ACTIVITY_UNKNOWN",
	"ACTIVITY_PLACE_MISMATCH",
	"ACTIVITY_NOT_ELIGIBLE",
	"ACTIVITY_REQUIRES_TRAVEL_STEP",
	"ACTIVITY_SLOT_REFERENCE_INVALID",
	"ACTIVITY_NO_EXECUTABLE_SLOT",
	"ACTIVITY_TARGET_UNREACHABLE",
	"ACTIVITY_RESERVATION_CONFLICT",
	"ACTIVITY_STATE_CHANGED",
]
const IDEMPOTENCY_KEY_FIELDS := [
	"residentId",
	"planId",
	"stepId",
	"planRevision",
]
const FORBIDDEN_AGENT_FIELDS := [
	"sceneId",
	"propId",
	"propName",
	"actionId",
	"actionVerb",
	"anchorId",
	"memberAnchorId",
	"facing",
	"position",
	"coordinate",
	"route",
	"geometry",
	"duration",
	"durationMinutes",
	"durationTicks",
	"effects",
	"poseFamily",
	"capacity",
	"reservation",
	"reservationGeneration",
	"reservationRevision",
	"sourceFingerprint",
	"scheduleTemplateId",
	"schedule",
	"windowId",
	"goalPressure",
]
const STATIC_PENDING_STATUS := (
	"activity_chain_verified_place_capability_pending"
)


static func validate(
	occupation_document: Dictionary,
	activity_document: Dictionary,
	slot_document: Dictionary,
	places_document: Dictionary,
	props_document: Dictionary,
	indoor_authoring_document: Dictionary,
	schedule_document: Dictionary,
) -> PackedStringArray:
	var report := validate_with_status(
		occupation_document,
		activity_document,
		slot_document,
		places_document,
		props_document,
		indoor_authoring_document,
		schedule_document,
	)
	return report.get("errors", PackedStringArray()) as PackedStringArray


static func validate_with_status(
	occupation_document: Dictionary,
	activity_document: Dictionary,
	slot_document: Dictionary,
	places_document: Dictionary,
	props_document: Dictionary,
	indoor_authoring_document: Dictionary,
	schedule_document: Dictionary,
) -> Dictionary:
	var fingerprint := source_fingerprint(
		occupation_document,
		activity_document,
		slot_document,
		places_document,
		props_document,
		indoor_authoring_document,
		schedule_document,
	)
	var document_fingerprints := source_document_fingerprints(
		occupation_document,
		activity_document,
		slot_document,
		places_document,
		props_document,
		indoor_authoring_document,
		schedule_document,
	)
	var errors := PackedStringArray()
	if fingerprint.is_empty():
		errors.append("Activity Integration 无法生成组合 sourceFingerprint")
	if document_fingerprints.size() != 7:
		errors.append("Activity Integration 必须生成七份单文档 fingerprints")
	for file_name_value: Variant in document_fingerprints.keys():
		if String(document_fingerprints[file_name_value]).is_empty():
			errors.append("源文档 fingerprint 为空：%s" % String(file_name_value))
	_validate_envelope(occupation_document, "occupation_catalog", errors)
	_validate_envelope(activity_document, "activity_definitions", errors)
	_validate_envelope(slot_document, "activity_slots", errors)
	_validate_envelope(places_document, "places", errors)
	_validate_envelope(props_document, "props", errors)
	_validate_envelope(
		indoor_authoring_document,
		"indoor_prop_authoring",
		errors,
	)
	_validate_envelope(schedule_document, "schedule_templates", errors)
	_validate_agent_contract(activity_document, errors)
	_validate_default_social_coverage(occupation_document, errors)
	_validate_slot_contracts(slot_document, errors)

	var places_by_name := _index_places(places_document, errors)
	var props_by_name := _index_props(props_document, errors)
	var indoor_bindings := _index_indoor_bindings(
		indoor_authoring_document,
		errors,
	)
	var activities_by_id := _validate_activities(activity_document, errors)
	var slots_by_id := _validate_slots(
		slot_document,
		activities_by_id,
		places_by_name,
		props_by_name,
		indoor_bindings,
		errors,
	)
	_validate_place_service_profiles(
		places_document,
		activities_by_id,
		slots_by_id,
		errors,
	)
	_validate_fallbacks(slots_by_id, errors)
	var schedules_by_id := _validate_schedules(
		schedule_document,
		activities_by_id,
		slots_by_id,
		errors,
	)
	_validate_reference_status(
		occupation_document,
		schedules_by_id,
		errors,
	)
	_validate_occupations(
		occupation_document,
		activities_by_id,
		slots_by_id,
		places_by_name,
		schedules_by_id,
		errors,
	)
	_validate_default_social_supported_chains(
		occupation_document,
		activities_by_id,
		slots_by_id,
		places_by_name,
		errors,
	)
	_validate_content_gaps(
		occupation_document.get("contentGaps", []),
		"occupation_catalog.contentGaps",
		errors,
	)
	_validate_content_gaps(
		slot_document.get("contentGaps", []),
		"activity_slots.contentGaps",
		errors,
	)
	var pending_place_capabilities := (
		_place_capability_pending_occupations(
			occupation_document,
			activities_by_id,
			slots_by_id,
			places_by_name,
		)
	)
	var unresolved_schedule_ids := _unresolved_schedule_template_ids(
		occupation_document,
		schedules_by_id,
	)
	var static_references_validated := errors.is_empty()
	var place_capabilities_verified := (
		pending_place_capabilities.is_empty()
	)
	var schedule_templates_resolved := (
		static_references_validated
		and unresolved_schedule_ids.is_empty()
		and not schedules_by_id.is_empty()
	)
	var formal_executable := (
		static_references_validated
		and place_capabilities_verified
		and schedule_templates_resolved
	)
	var status := "invalid"
	if static_references_validated and not formal_executable:
		status = STATIC_PENDING_STATUS
	elif formal_executable:
		status = "formal_executable"
	return {
		"receiptVersion": 1,
		"validator": "TownWorldActivityValidator",
		"ok": static_references_validated,
		"validated": formal_executable,
		"formalExecutable": formal_executable,
		"status": status,
		"sourceWorldId": String(
			activity_document.get("worldId", "")
		),
		"sourceFingerprint": fingerprint,
		"sourceDocumentFingerprints": document_fingerprints,
		"staticReferencesValidated": static_references_validated,
		"activityChainVerified": static_references_validated,
		"placeCapabilitiesVerified": place_capabilities_verified,
		"scheduleTemplatesResolved": schedule_templates_resolved,
		"pendingPlaceCapabilityOccupationIds": (
			pending_place_capabilities
		),
		"unresolvedScheduleTemplateIds": unresolved_schedule_ids,
		"errors": errors,
	}


static func source_fingerprint(
	occupation_document: Dictionary,
	activity_document: Dictionary,
	slot_document: Dictionary,
	places_document: Dictionary,
	props_document: Dictionary,
	indoor_authoring_document: Dictionary,
	schedule_document: Dictionary,
) -> String:
	var canonical_source := _canonical_value({
		"activityDefinitions": activity_document,
		"activitySlots": slot_document,
		"indoorPropAuthoring": indoor_authoring_document,
		"occupationCatalog": occupation_document,
		"places": places_document,
		"props": props_document,
		"scheduleTemplates": schedule_document,
	})
	return _sha256_text(
		"town_world_activity_integration_source_v2\n"
		+ canonical_source
	)


static func source_document_fingerprints(
	occupation_document: Dictionary,
	activity_document: Dictionary,
	slot_document: Dictionary,
	places_document: Dictionary,
	props_document: Dictionary,
	indoor_authoring_document: Dictionary,
	schedule_document: Dictionary,
) -> Dictionary:
	var documents := {
		"occupation_catalog.json": occupation_document,
		"activity_definitions.json": activity_document,
		"activity_slots.json": slot_document,
		"places.json": places_document,
		"props.json": props_document,
		"indoor_prop_authoring.json": indoor_authoring_document,
		"schedule_templates.json": schedule_document,
	}
	var result := {}
	for file_name_value: Variant in documents.keys():
		var file_name := String(file_name_value)
		result[file_name] = _sha256_text(
			"town_world_source_document_v1\n%s\n%s"
			% [
				file_name,
				_canonical_value(documents[file_name]),
			]
		)
	return result


static func _sha256_text(value: String) -> String:
	var hashing_context := HashingContext.new()
	var start_error := hashing_context.start(
		HashingContext.HASH_SHA256
	)
	if start_error != OK:
		return ""
	hashing_context.update(value.to_utf8_buffer())
	return hashing_context.finish().hex_encode()


static func _validate_envelope(
	document: Dictionary,
	label: String,
	errors: PackedStringArray,
) -> void:
	var schema_value: Variant = document.get("schemaVersion")
	if not _is_integer_number(schema_value) or int(schema_value) != 1:
		errors.append("%s.schemaVersion 必须是整数 1" % label)
	var world_id_value: Variant = document.get("worldId")
	if (
		not world_id_value is String
		or String(world_id_value) != "town"
	):
		errors.append("%s.worldId 必须为 town" % label)


static func _validate_agent_contract(
	activity_document: Dictionary,
	errors: PackedStringArray,
) -> void:
	_expect_exact_string_array(
		activity_document.get("stateKeys"),
		STATE_KEYS,
		"activity_definitions.stateKeys",
		errors,
	)
	var contract_value: Variant = activity_document.get("agentContract")
	if not contract_value is Dictionary:
		errors.append("activity_definitions.agentContract 必须为对象")
		return
	var contract := contract_value as Dictionary
	if String(contract.get("operation", "")) != "activity.perform":
		errors.append("公开活动 operation 必须为 activity.perform")
	_expect_exact_string_array(
		contract.get("requiredTargetFields"),
		PUBLIC_REQUIRED_TARGET_FIELDS,
		"agentContract.requiredTargetFields",
		errors,
	)
	_expect_exact_string_array(
		contract.get("optionalTargetFields"),
		PUBLIC_OPTIONAL_TARGET_FIELDS,
		"agentContract.optionalTargetFields",
		errors,
	)
	_expect_exact_string_array(
		contract.get("optionalParamsFields"),
		PUBLIC_OPTIONAL_PARAMS_FIELDS,
		"agentContract.optionalParamsFields",
		errors,
	)
	_expect_exact_string_array(
		contract.get("worldQueryFields"),
		PUBLIC_WORLD_QUERY_FIELDS,
		"agentContract.worldQueryFields",
		errors,
	)
	_expect_exact_string_array(
		contract.get("errorCodes"),
		PUBLIC_ERROR_CODES,
		"agentContract.errorCodes",
		errors,
	)
	_expect_exact_string_array(
		contract.get("idempotencyKeyFields"),
		IDEMPOTENCY_KEY_FIELDS,
		"agentContract.idempotencyKeyFields",
		errors,
	)
	var public_fields := []
	for key in [
		"requiredTargetFields",
		"optionalTargetFields",
		"optionalParamsFields",
		"worldQueryFields",
	]:
		var fields_value: Variant = contract.get(key, [])
		if fields_value is Array:
			public_fields.append_array(fields_value as Array)
	for forbidden_field in FORBIDDEN_AGENT_FIELDS:
		if forbidden_field in public_fields:
			errors.append("Agent 公开字段不得包含 %s" % forbidden_field)


static func _validate_reference_status(
	occupation_document: Dictionary,
	schedules_by_id: Dictionary,
	errors: PackedStringArray,
) -> void:
	var status_value: Variant = occupation_document.get("referenceStatus")
	if not status_value is Dictionary:
		errors.append("occupation_catalog.referenceStatus 必须为对象")
		return
	var status := status_value as Dictionary
	var catalog_status := String(
		status.get("scheduleTemplateCatalog", "")
	)
	var unresolved := _string_array(
		status.get("unresolvedScheduleTemplateIds"),
		"referenceStatus.unresolvedScheduleTemplateIds",
		errors,
	)
	var resolved := _string_array(
		status.get("resolvedScheduleTemplateIds", []),
		"referenceStatus.resolvedScheduleTemplateIds",
		errors,
	)
	var referenced: Array = []
	for value: Variant in occupation_document.get("occupations", []) as Array:
		if not value is Dictionary:
			continue
		var schedule_id := String(
			(value as Dictionary).get("scheduleTemplateId", "")
		)
		if not schedule_id.is_empty() and schedule_id not in referenced:
			referenced.append(schedule_id)
	referenced.sort()
	unresolved.sort()
	resolved.sort()
	var authored := []
	for schedule_id_value: Variant in schedules_by_id.keys():
		authored.append(String(schedule_id_value))
	authored.sort()
	if (
		catalog_status == "unavailable"
		and (
			unresolved != referenced
			or not resolved.is_empty()
		)
	):
		errors.append(
			"未解析 scheduleTemplateId 必须精确覆盖职业目录引用"
		)
	elif (
		catalog_status == "resolved"
		and (
			resolved != referenced
			or not unresolved.is_empty()
			or authored != referenced
		)
	):
		errors.append(
			"已解析 scheduleTemplateId 与权威 schedule 目录必须精确覆盖职业目录引用"
		)
	elif catalog_status not in ["unavailable", "resolved"]:
		errors.append(
			"scheduleTemplateCatalog 必须为 unavailable 或 resolved"
		)


static func _validate_default_social_coverage(
	occupation_document: Dictionary,
	errors: PackedStringArray,
) -> void:
	var coverage_value: Variant = occupation_document.get(
		"defaultSocialStateCoverage"
	)
	if not coverage_value is Dictionary:
		errors.append("defaultSocialStateCoverage 必须为对象")
		return
	var coverage := coverage_value as Dictionary
	if String(coverage.get("sourceCatalogPath", "")) != (
		"res://world/data/town/resident_catalog.json"
	):
		errors.append("defaultSocialStateCoverage sourceCatalogPath 非法")
	var expected_value: Variant = coverage.get(
		"expectedDefaultCombinationCount"
	)
	if not _is_integer_number(expected_value) or int(expected_value) != 16:
		errors.append("默认社会状态预期数量必须为整数 16")
	var supported_value: Variant = coverage.get(
		"activityChainSupported"
	)
	var gaps_value: Variant = coverage.get("gaps")
	if not supported_value is Array or not gaps_value is Array:
		errors.append("默认社会状态 supported/gaps 必须为数组")
		return
	var supported := supported_value as Array
	var gaps := gaps_value as Array
	if supported.size() + gaps.size() != int(expected_value):
		errors.append("默认社会状态 supported + gaps 必须精确覆盖预期数量")
	var combination_ids: Dictionary = {}
	for value: Variant in supported + gaps:
		if not value is Dictionary:
			errors.append("默认社会状态覆盖条目必须为对象")
			continue
		var record := value as Dictionary
		var combination_id := String(record.get("combinationId", ""))
		_validate_stable_id(
			combination_id,
			"default_social_",
			"defaultSocialStateCoverage.combinationId",
			errors,
		)
		if combination_ids.has(combination_id):
			errors.append(
				"默认社会状态 combinationId 重复：%s" % combination_id
			)
		else:
			combination_ids[combination_id] = true
		var occupation_name := String(record.get("occupationName", ""))
		var workplace_place := String(record.get("workplacePlace", ""))
		if occupation_name.is_empty() or workplace_place.is_empty():
			errors.append("默认社会状态职业与工作地不能为空")
	for value: Variant in supported:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		if String(record.get("occupationId", "")).is_empty():
			errors.append("supported 默认社会状态必须引用 occupationId")
		if String(record.get("status", "")) != "formal_executable":
			errors.append(
				"supported 默认社会状态必须标记 formal_executable"
			)
	for value: Variant in gaps:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		if String(record.get("reasonCode", "")).is_empty():
			errors.append("默认社会状态 gap 缺少 reasonCode")
		if String(record.get("reason", "")).strip_edges().is_empty():
			errors.append("默认社会状态 gap 缺少 reason")


static func _validate_slot_contracts(
	slot_document: Dictionary,
	errors: PackedStringArray,
) -> void:
	var member_contract_value: Variant = slot_document.get(
		"memberAnchorContract"
	)
	if not member_contract_value is Dictionary:
		errors.append("activity_slots.memberAnchorContract 必须为对象")
	else:
		var member_contract := member_contract_value as Dictionary
		if member_contract.get("singlePropTargetAnchorAllowed") != true:
			errors.append("单人 prop 旧锚点兼容合同必须为 true")
		if String(
			member_contract.get("multiPropTargetAnchorMode", "")
		) != "per_member":
			errors.append("多人 prop 必须使用 per_member 锚点模式")
		if member_contract.get("requiresPropAuthoringMatch") != true:
			errors.append("member anchor 必须匹配 props authoring")
		if member_contract.get("requiresIndoorAuthoringMatch") != true:
			errors.append("member anchor 必须匹配 indoor authoring")
		if member_contract.get("oneMemberPerCoordinate") != true:
			errors.append("一个坐标只能对应一个 member")
		var capacity_value: Variant = member_contract.get(
			"maxAuthoredMembersPerSlot"
		)
		if not _is_integer_number(capacity_value) or int(capacity_value) <= 0:
			errors.append(
				"maxAuthoredMembersPerSlot 必须为正整数"
			)
	var fallback_contract := slot_document.get(
		"fallbackContract",
		{},
	) as Dictionary
	_expect_exact_string_array(
		fallback_contract.get("sameActivityOtherSlotMatchFields"),
		["placeName", "activityId", "role", "targetType"],
		"fallbackContract.sameActivityOtherSlotMatchFields",
		errors,
	)


static func _index_places(
	places_document: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	var result: Dictionary = {}
	var places_value: Variant = places_document.get("places")
	if not places_value is Array:
		errors.append("places.places 必须为数组")
		return result
	for index in (places_value as Array).size():
		var value: Variant = (places_value as Array)[index]
		if not value is Dictionary:
			errors.append("places[%d] 必须为对象" % index)
			continue
		var place := value as Dictionary
		var place_name := String(place.get("name", "")).strip_edges()
		if place_name.is_empty():
			errors.append("places[%d].name 不能为空" % index)
		elif result.has(place_name):
			errors.append("地点名字重复：%s" % place_name)
		else:
			result[place_name] = place.duplicate(true)
	return result


static func _index_props(
	props_document: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	var result: Dictionary = {}
	var props_value: Variant = props_document.get("props")
	if not props_value is Array:
		errors.append("props.props 必须为数组")
		return result
	for index in (props_value as Array).size():
		var value: Variant = (props_value as Array)[index]
		if not value is Dictionary:
			errors.append("props[%d] 必须为对象" % index)
			continue
		var prop := value as Dictionary
		var prop_name := String(prop.get("name", "")).strip_edges()
		if prop_name.is_empty():
			errors.append("props[%d].name 不能为空" % index)
		elif result.has(prop_name):
			errors.append("道具名字重复：%s" % prop_name)
		else:
			result[prop_name] = prop.duplicate(true)
	return result


static func _index_indoor_bindings(
	indoor_authoring_document: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	var result: Dictionary = {}
	var rooms_value: Variant = indoor_authoring_document.get("rooms")
	if not rooms_value is Array:
		errors.append("indoor_prop_authoring.rooms 必须为数组")
		return result
	for room_value: Variant in rooms_value as Array:
		if not room_value is Dictionary:
			continue
		var room := room_value as Dictionary
		var room_id := String(room.get("roomId", ""))
		var place_name := String(room.get("placeName", ""))
		for binding_value: Variant in room.get("props", []) as Array:
			if not binding_value is Dictionary:
				continue
			var binding := binding_value as Dictionary
			var anchors: Dictionary = {}
			var base_anchor_id := String(binding.get("anchorId", ""))
			if not base_anchor_id.is_empty():
				anchors[base_anchor_id] = true
			for member_value: Variant in binding.get(
				"memberAnchors",
				[],
			) as Array:
				if not member_value is Dictionary:
					continue
				var member_anchor_id := String(
					(member_value as Dictionary).get("anchorId", "")
				)
				_validate_stable_reference(
					member_anchor_id,
					"indoor memberAnchors.anchorId",
					errors,
				)
				if anchors.has(member_anchor_id):
					errors.append(
						"indoor authoring anchorId 重复：%s"
						% member_anchor_id
					)
				elif not member_anchor_id.is_empty():
					anchors[member_anchor_id] = true
			var actions: Array = []
			if binding.get("actions") is Array:
				actions = binding.get("actions") as Array
			else:
				actions = [{"verb": binding.get("verb", "")}]
			for action_value: Variant in actions:
				if not action_value is Dictionary:
					continue
				var key := _prop_action_binding_key(
					place_name,
					String(binding.get("name", "")),
					String((action_value as Dictionary).get("verb", "")),
					room_id,
				)
				if result.has(key):
					errors.append(
						"indoor prop/action authoring 重复：%s"
						% String(binding.get("name", ""))
					)
				elif not key.is_empty():
					result[key] = anchors.duplicate(true)
	for prop_value: Variant in indoor_authoring_document.get(
		"outdoorProps",
		[],
	) as Array:
		if not prop_value is Dictionary:
			continue
		var prop := prop_value as Dictionary
		var interaction := prop.get("interaction", {}) as Dictionary
		var room_id := String(interaction.get("roomId", ""))
		if room_id.is_empty():
			continue
		var anchors: Dictionary = {}
		var base_anchor_id := String(interaction.get("anchorId", ""))
		if not base_anchor_id.is_empty():
			anchors[base_anchor_id] = true
		for member_value: Variant in interaction.get(
			"memberAnchors",
			[],
		) as Array:
			if not member_value is Dictionary:
				continue
			var member_anchor_id := String(
				(member_value as Dictionary).get("anchorId", "")
			)
			if not member_anchor_id.is_empty():
				anchors[member_anchor_id] = true
		for action_value: Variant in prop.get("actions", []) as Array:
			if not action_value is Dictionary:
				continue
			var key := _prop_action_binding_key(
				String(prop.get("placeName", "")),
				String(prop.get("name", "")),
				String((action_value as Dictionary).get("verb", "")),
				room_id,
			)
			if result.has(key):
				errors.append(
					"显式 prop/action authoring 重复：%s"
					% String(prop.get("name", ""))
				)
			elif not key.is_empty():
				result[key] = anchors.duplicate(true)
	return result


static func _validate_activities(
	activity_document: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	var result: Dictionary = {}
	var activities_value: Variant = activity_document.get("activities")
	if not activities_value is Array:
		errors.append("activity_definitions.activities 必须为数组")
		return result
	for index in (activities_value as Array).size():
		var value: Variant = (activities_value as Array)[index]
		if not value is Dictionary:
			errors.append("activities[%d] 必须为对象" % index)
			continue
		var activity := value as Dictionary
		var activity_id := String(activity.get("activityId", ""))
		_validate_stable_id(
			activity_id,
			"activity_",
			"activities[%d].activityId" % index,
			errors,
		)
		if result.has(activity_id):
			errors.append("activityId 重复：%s" % activity_id)
		else:
			result[activity_id] = activity.duplicate(true)
		if String(activity.get("label", "")).strip_edges().is_empty():
			errors.append("%s.label 不能为空" % activity_id)
		if String(activity.get("kind", "")) not in ACTIVITY_KINDS:
			errors.append("%s.kind 非法" % activity_id)
		_validate_nonempty_string_array(
			activity.get("tags"),
			"%s.tags" % activity_id,
			errors,
		)
		var duration_value: Variant = activity.get("durationMinutes")
		if not _is_integer_number(duration_value) or int(duration_value) <= 0:
			errors.append(
				"%s.durationMinutes 必须为正整数数值" % activity_id
			)
		if not activity.get("interruptible") is bool:
			errors.append("%s.interruptible 必须为布尔值" % activity_id)
		var pose_family_value: Variant = activity.get("poseFamily", "")
		if not pose_family_value is String:
			errors.append("%s.poseFamily 必须为字符串" % activity_id)
		var effects_value: Variant = activity.get("effects")
		if not effects_value is Dictionary:
			errors.append("%s.effects 必须为对象" % activity_id)
		else:
			for state_key_value: Variant in (effects_value as Dictionary).keys():
				var state_key := String(state_key_value)
				if state_key not in STATE_KEYS:
					errors.append("%s.effects 使用非法状态键：%s" % [
						activity_id,
						state_key,
					])
				var delta_value: Variant = (effects_value as Dictionary)[
					state_key_value
				]
				if not delta_value is int and not delta_value is float:
					errors.append("%s.effects.%s 必须为数字" % [
						activity_id,
						state_key,
					])
		if (
			String(activity.get("kind", "")) == "service"
			or activity.has("resultContract")
		):
			_validate_result_contract(
				activity.get("resultContract"),
				activity_id,
				errors,
			)
	return result


static func _validate_result_contract(
	value: Variant,
	activity_id: String,
	errors: PackedStringArray,
) -> void:
	if not value is Dictionary:
		errors.append("%s.resultContract 必须为对象" % activity_id)
		return
	var contract := value as Dictionary
	var actual_keys := contract.keys()
	var expected_keys := [
		"mode",
		"taskCapability",
		"resultKind",
		"requiredEvidence",
	]
	actual_keys.sort()
	expected_keys.sort()
	if actual_keys != expected_keys:
		errors.append("%s.resultContract 字段无效" % activity_id)
	var mode := String(contract.get("mode", ""))
	if mode not in RESULT_CONTRACT_MODES:
		errors.append("%s.resultContract.mode 无效" % activity_id)
	var capability := String(
		contract.get("taskCapability", ""),
	).strip_edges()
	if capability.is_empty():
		errors.append(
			"%s.resultContract.taskCapability 不能为空" % activity_id,
		)
	var result_kind := String(
		contract.get("resultKind", ""),
	).strip_edges()
	if result_kind.is_empty():
		errors.append(
			"%s.resultContract.resultKind 不能为空" % activity_id,
		)
	var evidence := _string_array(
		contract.get("requiredEvidence"),
		"%s.resultContract.requiredEvidence" % activity_id,
		errors,
	)
	if evidence.is_empty():
		errors.append(
			"%s.resultContract.requiredEvidence 至少需要一个值"
			% activity_id,
		)
	for evidence_field: Variant in evidence:
		if String(evidence_field) not in RESULT_EVIDENCE_FIELDS:
			errors.append(
				"%s.resultContract.requiredEvidence 使用未知字段：%s"
				% [activity_id, String(evidence_field)],
			)


static func _validate_slots(
	slot_document: Dictionary,
	activities_by_id: Dictionary,
	places_by_name: Dictionary,
	props_by_name: Dictionary,
	indoor_bindings: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	var result: Dictionary = {}
	var member_ids: Dictionary = {}
	var member_contract := slot_document.get(
		"memberAnchorContract",
		{},
	) as Dictionary
	var max_authored_members := int(
		member_contract.get("maxAuthoredMembersPerSlot", 0)
	)
	var slots_value: Variant = slot_document.get("slots")
	if not slots_value is Array:
		errors.append("activity_slots.slots 必须为数组")
		return result
	for index in (slots_value as Array).size():
		var value: Variant = (slots_value as Array)[index]
		if not value is Dictionary:
			errors.append("slots[%d] 必须为对象" % index)
			continue
		var slot := value as Dictionary
		var slot_id := String(slot.get("slotId", ""))
		var place_name := String(slot.get("placeName", ""))
		var scene_id := String(slot.get("sceneId", ""))
		var target_type := String(slot.get("targetType", ""))
		var role := String(slot.get("role", ""))
		var activity_id := String(slot.get("activityId", ""))
		_validate_stable_id(
			slot_id,
			"slot_",
			"slots[%d].slotId" % index,
			errors,
		)
		if result.has(slot_id):
			errors.append("slotId 重复：%s" % slot_id)
		else:
			result[slot_id] = slot.duplicate(true)
		if not places_by_name.has(place_name):
			errors.append("%s 引用未知地点：%s" % [slot_id, place_name])
		if scene_id.is_empty():
			errors.append("%s.sceneId 不能为空" % slot_id)
		if target_type not in TARGET_TYPES:
			errors.append("%s.targetType 非法" % slot_id)
		if role not in SLOT_ROLES:
			errors.append("%s.role 非法" % slot_id)
		if not activities_by_id.has(activity_id):
			errors.append("%s 引用未知 activityId：%s" % [slot_id, activity_id])
		if String(slot.get("fallback", "")) not in FALLBACKS:
			errors.append("%s.fallback 非法" % slot_id)
		if String(slot.get("facing", "")) not in FACINGS:
			errors.append("%s.facing 非法" % slot_id)
		var pose_family_value: Variant = slot.get("poseFamily", "")
		if not pose_family_value is String:
			errors.append("%s.poseFamily 必须为字符串" % slot_id)
		var target_value: Variant = slot.get("target")
		if not target_value is Dictionary:
			errors.append("%s.target 必须为对象" % slot_id)
			continue
		var target := target_value as Dictionary
		var member_anchors_value: Variant = slot.get("memberAnchors")
		if (
			member_anchors_value is Array
			and max_authored_members > 0
			and (member_anchors_value as Array).size()
			> max_authored_members
		):
			errors.append(
				"%s member 数量超过本数据批声明上限" % slot_id
			)
		var authoring_context := {}
		if target_type == "prop":
			authoring_context = _validate_prop_target(
				slot_id,
				place_name,
				scene_id,
				target,
				props_by_name,
				indoor_bindings,
				errors,
			)
		elif target_type == "point":
			_validate_stable_reference(
				String(target.get("pointId", "")),
				"%s.target.pointId" % slot_id,
				errors,
			)
		elif target_type == "region":
			_validate_stable_reference(
				String(target.get("regionId", "")),
				"%s.target.regionId" % slot_id,
				errors,
			)
			_validate_region_semantic_query(
				slot_id,
				place_name,
				target,
				places_by_name,
				errors,
			)
			if (
				not member_anchors_value is Array
				or not (member_anchors_value as Array).is_empty()
			):
				errors.append(
					"%s.region slot 的 memberAnchors 必须由 World 从真实路网生成"
					% slot_id
				)
		elif target_type == "route":
			_validate_stable_reference(
				String(target.get("routeId", "")),
				"%s.target.routeId" % slot_id,
				errors,
			)
		if target_type != "region":
			_validate_member_anchors(
				slot_id,
				target,
				member_anchors_value,
				authoring_context,
				member_ids,
				errors,
			)
	return result


static func _validate_region_semantic_query(
	slot_id: String,
	seed_place_name: String,
	target: Dictionary,
	places_by_name: Dictionary,
	errors: PackedStringArray,
) -> void:
	if not target.has("semanticQuery"):
		return
	var query_value: Variant = target.get("semanticQuery")
	if query_value is not Dictionary:
		errors.append("%s.target.semanticQuery 必须为对象" % slot_id)
		return
	var query := query_value as Dictionary
	for key_value: Variant in query:
		if String(key_value) not in [
			"visibleFeaturesAny",
			"placeCapabilitiesAny",
		]:
			errors.append(
				"%s.target.semanticQuery 包含未知条件：%s"
				% [slot_id, String(key_value)]
			)
	var visible_features := _string_array(
		query.get("visibleFeaturesAny", []),
		"%s.target.semanticQuery.visibleFeaturesAny" % slot_id,
		errors,
	)
	var capabilities := _string_array(
		query.get("placeCapabilitiesAny", []),
		"%s.target.semanticQuery.placeCapabilitiesAny" % slot_id,
		errors,
	)
	if visible_features.is_empty() and capabilities.is_empty():
		errors.append(
			"%s.target.semanticQuery 至少需要一项环境或地点能力条件"
			% slot_id
		)
		return
	var matching_places: Array[String] = []
	for place_name_value: Variant in places_by_name:
		var place_name := String(place_name_value)
		var place := places_by_name[place_name_value] as Dictionary
		if String(place.get("spaceId", "")) != "town_outdoor":
			continue
		if _place_matches_region_semantic_query(
			place,
			visible_features,
			capabilities,
		):
			matching_places.append(place_name)
	if matching_places.is_empty():
		errors.append(
			"%s.target.semanticQuery 没有命中任何室外正式地点"
			% slot_id
		)
	elif seed_place_name not in matching_places:
		errors.append(
			"%s 的种子地点不符合自身 semanticQuery" % slot_id
		)


static func _place_matches_region_semantic_query(
	place: Dictionary,
	visible_features: Array,
	capabilities: Array,
) -> bool:
	if (
		not visible_features.is_empty()
		and not _arrays_intersect(
			visible_features,
			place.get("visibleFeatures", []) as Array,
		)
	):
		return false
	if not capabilities.is_empty():
		var place_capabilities := place.get("capabilities", {}) as Dictionary
		var matched := false
		for capability_value: Variant in capabilities:
			if place_capabilities.get(String(capability_value)) == true:
				matched = true
				break
		if not matched:
			return false
	return true


static func _validate_place_service_profiles(
	places_document: Dictionary,
	activities_by_id: Dictionary,
	slots_by_id: Dictionary,
	errors: PackedStringArray,
) -> void:
	for place_value: Variant in places_document.get("places", []) as Array:
		if not place_value is Dictionary:
			continue
		var place := place_value as Dictionary
		if not place.has("serviceProfile"):
			continue
		var place_name := String(place.get("name", ""))
		var profile_value: Variant = place.get("serviceProfile")
		if not profile_value is Dictionary:
			errors.append("%s.serviceProfile 必须为对象" % place_name)
			continue
		var profile := profile_value as Dictionary
		var profile_keys: Array[String] = []
		for key_value: Variant in profile:
			profile_keys.append(String(key_value))
		profile_keys.sort()
		if profile_keys != [
			"capacity",
			"helperActivityId",
			"requestActivityIds",
			"unstaffedVisitorActivityIds",
		]:
			errors.append(
				"%s.serviceProfile 字段必须精确为 capacity/helperActivityId/requestActivityIds/unstaffedVisitorActivityIds"
				% place_name
			)
		var capacity_value: Variant = profile.get("capacity")
		if (
			not _is_integer_number(capacity_value)
			or int(capacity_value) <= 0
		):
			errors.append(
				"%s.serviceProfile.capacity 必须为正整数"
				% place_name
			)
		var helper_activity_id := String(
			profile.get("helperActivityId", "")
		)
		if not activities_by_id.has(helper_activity_id):
			errors.append(
				"%s.serviceProfile 引用未知 helperActivityId：%s"
				% [place_name, helper_activity_id]
			)
		elif not _has_activity_slot_at_place(
			slots_by_id,
			helper_activity_id,
			place_name,
			"worker",
		):
			errors.append(
				"%s.serviceProfile 的帮助活动没有同地点 worker slot"
				% place_name
			)
		var request_ids_value: Variant = profile.get(
			"requestActivityIds"
		)
		if (
			not request_ids_value is Array
			or (request_ids_value as Array).is_empty()
		):
			errors.append(
				"%s.serviceProfile.requestActivityIds 必须为非空数组"
				% place_name
			)
			continue
		var seen_request_ids := {}
		for request_value: Variant in request_ids_value as Array:
			if (
				typeof(request_value) != TYPE_STRING
				or String(request_value).strip_edges().is_empty()
			):
				errors.append(
					"%s.serviceProfile.requestActivityIds 只能包含非空字符串"
					% place_name
				)
				continue
			var request_activity_id := String(
				request_value
			).strip_edges()
			if seen_request_ids.has(request_activity_id):
				errors.append(
					"%s.serviceProfile 请求活动重复：%s"
					% [place_name, request_activity_id]
				)
				continue
			seen_request_ids[request_activity_id] = true
			if not activities_by_id.has(request_activity_id):
				errors.append(
					"%s.serviceProfile 引用未知请求 activityId：%s"
					% [place_name, request_activity_id]
				)
			elif not _has_activity_slot_at_place(
				slots_by_id,
				request_activity_id,
				place_name,
				"visitor",
			):
				errors.append(
					"%s.serviceProfile 的请求活动没有同地点 visitor slot：%s"
					% [place_name, request_activity_id]
				)
		var unstaffed_ids_value: Variant = profile.get(
			"unstaffedVisitorActivityIds",
		)
		if unstaffed_ids_value is not Array:
			errors.append(
				"%s.serviceProfile.unstaffedVisitorActivityIds 必须为数组"
				% place_name
			)
			continue
		var seen_unstaffed_ids := {}
		for activity_value: Variant in unstaffed_ids_value as Array:
			if (
				typeof(activity_value) != TYPE_STRING
				or String(activity_value).strip_edges().is_empty()
			):
				errors.append(
					"%s.serviceProfile.unstaffedVisitorActivityIds 只能包含非空字符串"
					% place_name
				)
				continue
			var activity_id := String(activity_value).strip_edges()
			if seen_unstaffed_ids.has(activity_id):
				errors.append(
					"%s.serviceProfile 无人值守访客活动重复：%s"
					% [place_name, activity_id]
				)
				continue
			seen_unstaffed_ids[activity_id] = true
			if not activities_by_id.has(activity_id):
				errors.append(
					"%s.serviceProfile 引用未知无人值守访客 activityId：%s"
					% [place_name, activity_id]
				)
			elif not _has_activity_slot_at_place(
				slots_by_id,
				activity_id,
				place_name,
				"visitor",
			):
				errors.append(
					"%s.serviceProfile 的无人值守活动没有同地点 visitor slot：%s"
					% [place_name, activity_id]
				)


static func _has_activity_slot_at_place(
	slots_by_id: Dictionary,
	activity_id: String,
	place_name: String,
	role: String,
) -> bool:
	for slot_value: Variant in slots_by_id.values():
		var slot := slot_value as Dictionary
		if (
			String(slot.get("activityId", "")) == activity_id
			and String(slot.get("placeName", "")) == place_name
			and String(slot.get("role", "")) == role
		):
			return true
	return false


static func _validate_prop_target(
	slot_id: String,
	place_name: String,
	scene_id: String,
	target: Dictionary,
	props_by_name: Dictionary,
	indoor_bindings: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	var prop_name := String(target.get("propName", ""))
	var action_verb := String(target.get("actionVerb", ""))
	var anchor_id := String(target.get("anchorId", ""))
	if not props_by_name.has(prop_name):
		errors.append("%s 引用未知道具：%s" % [slot_id, prop_name])
		return {}
	var prop := props_by_name[prop_name] as Dictionary
	if String(prop.get("placeName", "")) != place_name:
		errors.append("%s 道具地点与 slot 地点不一致" % slot_id)
	var interaction := prop.get("interaction", {}) as Dictionary
	if String(interaction.get("roomId", "")) != scene_id:
		errors.append("%s sceneId 与道具 roomId 不一致" % slot_id)
	var prop_anchors := _prop_authoring_anchor_positions(
		interaction,
		slot_id,
		errors,
	)
	var action_found := false
	for action_value: Variant in prop.get("actions", []) as Array:
		if (
			action_value is Dictionary
			and String((action_value as Dictionary).get("verb", "")) == action_verb
		):
			action_found = true
			break
	if not action_found:
		errors.append("%s 引用未知道具动作词：%s" % [slot_id, action_verb])
	var binding_key := _prop_action_binding_key(
		place_name,
		prop_name,
		action_verb,
		scene_id,
	)
	if not indoor_bindings.has(binding_key):
		errors.append("%s 未匹配 indoor_prop_authoring 绑定" % slot_id)
	var indoor_anchors := (
		indoor_bindings.get(binding_key, {}) as Dictionary
	).duplicate(true)
	if not anchor_id.is_empty():
		if not prop_anchors.has(anchor_id):
			errors.append("%s anchorId 与道具交互锚点不一致" % slot_id)
		if not indoor_anchors.has(anchor_id):
			errors.append("%s anchorId 未匹配室内 authoring" % slot_id)
	return {
		"targetType": "prop",
		"propAnchors": prop_anchors,
		"indoorAnchors": indoor_anchors,
	}


static func _validate_member_anchors(
	slot_id: String,
	target: Dictionary,
	member_anchors_value: Variant,
	authoring_context: Dictionary,
	global_member_ids: Dictionary,
	errors: PackedStringArray,
) -> void:
	if not member_anchors_value is Array:
		errors.append("%s.memberAnchors 必须为数组" % slot_id)
		return
	var member_anchors := member_anchors_value as Array
	if member_anchors.is_empty():
		errors.append("%s 至少需要一个 member anchor" % slot_id)
		return
	var coordinates: Dictionary = {}
	var anchor_ids: Dictionary = {}
	var target_anchor_id := String(target.get("anchorId", ""))
	if member_anchors.size() > 1 and not target_anchor_id.is_empty():
		errors.append(
			"%s 多人 prop slot 不得共用单一 target.anchorId" % slot_id
		)
	for index in member_anchors.size():
		var value: Variant = member_anchors[index]
		if not value is Dictionary:
			errors.append("%s.memberAnchors[%d] 必须为对象" % [slot_id, index])
			continue
		var member := value as Dictionary
		var member_id := String(member.get("memberAnchorId", ""))
		var anchor_id := String(member.get("anchorId", ""))
		_validate_stable_reference(
			anchor_id,
			"%s.memberAnchors[%d].anchorId" % [slot_id, index],
			errors,
		)
		_validate_stable_id(
			member_id,
			"member_",
			"%s.memberAnchors[%d].memberAnchorId" % [slot_id, index],
			errors,
		)
		if global_member_ids.has(member_id):
			errors.append("memberAnchorId 重复：%s" % member_id)
		else:
			global_member_ids[member_id] = slot_id
		if anchor_ids.has(anchor_id):
			errors.append("%s 多个 member 共用同一 anchorId" % slot_id)
		else:
			anchor_ids[anchor_id] = member_id
		if (
			member_anchors.size() == 1
			and not target_anchor_id.is_empty()
			and anchor_id != target_anchor_id
		):
			errors.append("%s 的 member anchor 与 target.anchorId 不一致" % slot_id)
		var position_value: Variant = member.get("position")
		if not _valid_position(position_value):
			errors.append("%s.memberAnchors[%d].position 必须是两个数字" % [
				slot_id,
				index,
			])
			continue
		var position := position_value as Array
		var coordinate_key := "%s,%s" % [str(position[0]), str(position[1])]
		if coordinates.has(coordinate_key):
			errors.append("%s 多个 member anchor 共用同一坐标" % slot_id)
		else:
			coordinates[coordinate_key] = member_id
		if String(authoring_context.get("targetType", "")) == "prop":
			var prop_anchors := authoring_context.get(
				"propAnchors",
				{},
			) as Dictionary
			var indoor_anchors := authoring_context.get(
				"indoorAnchors",
				{},
			) as Dictionary
			if not prop_anchors.has(anchor_id):
				errors.append(
					"%s member anchor 未匹配道具 authoring：%s" % [
						slot_id,
						anchor_id,
					]
				)
			elif not _positions_equal(
				position,
				prop_anchors[anchor_id],
			):
				errors.append(
					"%s member anchor 坐标与对应 authoring 锚点不一致"
					% slot_id
				)
			if not indoor_anchors.has(anchor_id):
				errors.append(
					"%s member anchor 未匹配室内 authoring：%s" % [
						slot_id,
						anchor_id,
					]
				)


static func _validate_fallbacks(
	slots_by_id: Dictionary,
	errors: PackedStringArray,
) -> void:
	for slot_value: Variant in slots_by_id.values():
		var slot := slot_value as Dictionary
		if String(slot.get("fallback", "")) != "same_activity_other_slot":
			continue
		var has_alternative := false
		for other_value: Variant in slots_by_id.values():
			var other := other_value as Dictionary
			if String(other.get("slotId", "")) == String(slot.get("slotId", "")):
				continue
			if (
				String(other.get("activityId", ""))
				== String(slot.get("activityId", ""))
				and String(other.get("placeName", ""))
				== String(slot.get("placeName", ""))
				and String(other.get("role", ""))
				== String(slot.get("role", ""))
				and String(other.get("targetType", ""))
				== String(slot.get("targetType", ""))
			):
				has_alternative = true
				break
		if not has_alternative:
			errors.append(
				"%s fallback 需要同地点、活动、role、targetType 的其他 slot"
				% String(slot.get("slotId", ""))
			)


static func _validate_schedules(
	schedule_document: Dictionary,
	activities_by_id: Dictionary,
	slots_by_id: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	var result: Dictionary = {}
	var contract_value: Variant = schedule_document.get("scheduleContract")
	if not contract_value is Dictionary:
		errors.append("schedule_templates.scheduleContract 必须为对象")
	else:
		var contract := contract_value as Dictionary
		var minute_range_value: Variant = contract.get("minuteRange")
		if (
			not minute_range_value is Array
			or (minute_range_value as Array).size() != 2
			or not _is_integer_number((minute_range_value as Array)[0])
			or not _is_integer_number((minute_range_value as Array)[1])
			or int((minute_range_value as Array)[0]) != SCHEDULE_MINUTE_RANGE[0]
			or int((minute_range_value as Array)[1]) != SCHEDULE_MINUTE_RANGE[1]
		):
			errors.append("scheduleContract.minuteRange 必须为 [0, 1440]")
		if String(contract.get("windowBoundary", "")) != SCHEDULE_WINDOW_BOUNDARY:
			errors.append("scheduleContract.windowBoundary 非法")
		if String(contract.get("windowOrdering", "")) != SCHEDULE_WINDOW_ORDERING:
			errors.append("scheduleContract.windowOrdering 非法")
		if String(contract.get("output", "")) != SCHEDULE_OUTPUT:
			errors.append("schedule 只能输出 goal pressure")
		if String(contract.get("planOwner", "")) != SCHEDULE_PLAN_OWNER:
			errors.append("schedule 不能取得 ResidentAgent 的计划所有权")
		if String(contract.get("publicActivityOperation", "")) != "activity.perform":
			errors.append("schedule 活动边界必须为 activity.perform")
		var generated_fields_value: Variant = contract.get("generatedPlanFields")
		if (
			not generated_fields_value is Array
			or not (generated_fields_value as Array).is_empty()
		):
			errors.append("schedule 不得生成 Agent 私有计划字段")

	var worker_activity_tags: Dictionary = {}
	for slot_value: Variant in slots_by_id.values():
		var slot := slot_value as Dictionary
		if String(slot.get("role", "")) != "worker":
			continue
		var activity_id := String(slot.get("activityId", ""))
		if not activities_by_id.has(activity_id):
			continue
		var activity := activities_by_id[activity_id] as Dictionary
		if String(activity.get("kind", "")) != "work":
			continue
		for tag_value: Variant in activity.get("tags", []) as Array:
			worker_activity_tags[String(tag_value)] = true

	var templates_value: Variant = schedule_document.get("scheduleTemplates")
	if not templates_value is Array:
		errors.append("schedule_templates.scheduleTemplates 必须为数组")
		return result
	var window_ids: Dictionary = {}
	for index in (templates_value as Array).size():
		var value: Variant = (templates_value as Array)[index]
		if not value is Dictionary:
			errors.append("scheduleTemplates[%d] 必须为对象" % index)
			continue
		var template := value as Dictionary
		var schedule_id := String(template.get("scheduleTemplateId", ""))
		_validate_stable_id(
			schedule_id,
			"schedule_",
			"scheduleTemplates[%d].scheduleTemplateId" % index,
			errors,
		)
		if result.has(schedule_id):
			errors.append("scheduleTemplateId 重复：%s" % schedule_id)
		else:
			result[schedule_id] = template.duplicate(true)
		if String(template.get("label", "")).strip_edges().is_empty():
			errors.append("%s.label 不能为空" % schedule_id)
		var template_role := String(template.get("role", ""))
		if template_role not in SCHEDULE_ROLES:
			errors.append("%s.role 必须为 worker" % schedule_id)
		var windows_value: Variant = template.get("windows")
		if not windows_value is Array or (windows_value as Array).is_empty():
			errors.append("%s.windows 必须为非空数组" % schedule_id)
			continue
		var previous_end := -1
		var previous_window_id := ""
		for window_index in (windows_value as Array).size():
			var window_value: Variant = (windows_value as Array)[window_index]
			if not window_value is Dictionary:
				errors.append("%s.windows[%d] 必须为对象" % [
					schedule_id,
					window_index,
				])
				continue
			var window := window_value as Dictionary
			var window_id := String(window.get("windowId", ""))
			_validate_stable_id(
				window_id,
				"window_",
				"%s.windows[%d].windowId" % [
					schedule_id,
					window_index,
				],
				errors,
			)
			if window_ids.has(window_id):
				errors.append("windowId 重复：%s" % window_id)
			else:
				window_ids[window_id] = schedule_id
			var start_value: Variant = window.get("startMinute")
			var end_value: Variant = window.get("endMinute")
			if (
				not _is_integer_number(start_value)
				or not _is_integer_number(end_value)
				or int(start_value) < 0
				or int(end_value) > 1440
				or int(start_value) >= int(end_value)
			):
				errors.append("%s 必须使用 0..1440 内合法的整数半开时段" % window_id)
				continue
			var start_minute := int(start_value)
			var end_minute := int(end_value)
			if start_minute < previous_end:
				errors.append("%s 的时段重叠或未按开始时间排序" % schedule_id)
			elif (
				start_minute == previous_end
				and not previous_window_id.is_empty()
				and window_id == previous_window_id
			):
				errors.append("%s 的窗口顺序不确定" % schedule_id)
			previous_end = end_minute
			previous_window_id = window_id
			if String(window.get("role", "")) != template_role:
				errors.append("%s.role 必须与 schedule role 一致" % window_id)
			var pressure_value: Variant = window.get("goalPressure")
			if not pressure_value is Dictionary:
				errors.append("%s.goalPressure 必须为对象" % window_id)
			else:
				var pressure := pressure_value as Dictionary
				var pressure_keys := []
				for key_value: Variant in pressure.keys():
					pressure_keys.append(String(key_value))
				pressure_keys.sort()
				if pressure_keys != ["goalId", "weight"]:
					errors.append("%s.goalPressure 字段必须精确为 goalId/weight" % window_id)
				if String(pressure.get("goalId", "")) not in SCHEDULE_GOAL_IDS:
					errors.append("%s.goalPressure.goalId 非法" % window_id)
				var weight_value: Variant = pressure.get("weight")
				if (
					not _is_integer_number(weight_value)
					or int(weight_value) <= 0
					or int(weight_value) > 100
				):
					errors.append("%s.goalPressure.weight 必须为 1..100 的整数" % window_id)
			var tags := _string_array(
				window.get("activityTagsAny"),
				"%s.activityTagsAny" % window_id,
				errors,
			)
			if tags.is_empty():
				errors.append("%s 至少需要一个 activity tag" % window_id)
			for tag_value: Variant in tags:
				var tag := String(tag_value)
				if not worker_activity_tags.has(tag):
					errors.append(
						"%s 引用了没有 worker activity slot 的标签：%s"
						% [window_id, tag]
					)
	return result


static func _validate_occupations(
	occupation_document: Dictionary,
	activities_by_id: Dictionary,
	slots_by_id: Dictionary,
	places_by_name: Dictionary,
	schedules_by_id: Dictionary,
	errors: PackedStringArray,
) -> void:
	var occupations_value: Variant = occupation_document.get("occupations")
	if not occupations_value is Array:
		errors.append("occupation_catalog.occupations 必须为数组")
		return
	var occupation_ids: Dictionary = {}
	var occupation_names: Dictionary = {}
	for index in (occupations_value as Array).size():
		var value: Variant = (occupations_value as Array)[index]
		if not value is Dictionary:
			errors.append("occupations[%d] 必须为对象" % index)
			continue
		var occupation := value as Dictionary
		var occupation_id := String(occupation.get("occupationId", ""))
		_validate_stable_id(
			occupation_id,
			"occupation_",
			"occupations[%d].occupationId" % index,
			errors,
		)
		if occupation_ids.has(occupation_id):
			errors.append("occupationId 重复：%s" % occupation_id)
		else:
			occupation_ids[occupation_id] = true
		if _contains_key_recursive(occupation, "residentId"):
			errors.append("%s 不得引用 residentId" % occupation_id)
		var occupation_label := String(
			occupation.get("label", "")
		).strip_edges()
		if occupation_label.is_empty():
			errors.append("%s.label 不能为空" % occupation_id)
		elif occupation_names.has(occupation_label):
			errors.append("职业名称或别名重复：%s" % occupation_label)
		else:
			occupation_names[occupation_label] = occupation_id
		var aliases := _string_array(
			occupation.get("aliases", []),
			"%s.aliases" % occupation_id,
			errors,
		)
		for alias in aliases:
			if alias.strip_edges().is_empty():
				errors.append("%s.aliases 不能包含空字符串" % occupation_id)
			elif occupation_names.has(alias):
				errors.append("职业名称或别名重复：%s" % alias)
			else:
				occupation_names[alias] = occupation_id
		var workplace_policy := String(occupation.get("workplacePolicy", ""))
		if workplace_policy not in WORKPLACE_POLICIES:
			errors.append("%s.workplacePolicy 非法" % occupation_id)
		var primary_workplace_place := String(
			occupation.get("primaryWorkplacePlace", ""),
		).strip_edges()
		if (
			workplace_policy != "none"
			and (
				primary_workplace_place.is_empty()
				or not places_by_name.has(primary_workplace_place)
			)
		):
			errors.append("%s.primaryWorkplacePlace 非法" % occupation_id)
		var related_workplace_places := _string_array(
			occupation.get("relatedWorkplacePlaces"),
			"%s.relatedWorkplacePlaces" % occupation_id,
			errors,
		)
		for related_place: String in related_workplace_places:
			if (
				related_place == primary_workplace_place
				or not places_by_name.has(related_place)
			):
				errors.append(
					"%s.relatedWorkplacePlaces 引用非法地点：%s"
					% [occupation_id, related_place],
				)
		var dynamic_work_target_rules := _string_array(
			occupation.get("dynamicWorkTargetRules"),
			"%s.dynamicWorkTargetRules" % occupation_id,
			errors,
		)
		for rule: String in dynamic_work_target_rules:
			if rule not in DYNAMIC_WORK_TARGET_RULES:
				errors.append(
					"%s.dynamicWorkTargetRules 引用未知规则：%s"
					% [occupation_id, rule],
				)
		var fixed_work_area_ids := _string_array(
			occupation.get("fixedWorkAreaIds"),
			"%s.fixedWorkAreaIds" % occupation_id,
			errors,
		)
		var required_capabilities := _string_array(
			occupation.get("requiredPlaceCapabilitiesAny"),
			"%s.requiredPlaceCapabilitiesAny" % occupation_id,
			errors,
		)
		var allowed_tags := _string_array(
			occupation.get("allowedActivityTags"),
			"%s.allowedActivityTags" % occupation_id,
			errors,
		)
		if allowed_tags.is_empty():
			errors.append("%s 至少需要一个 allowed activity tag" % occupation_id)
		if (
			workplace_policy != "none"
			and required_capabilities.is_empty()
		):
			errors.append("%s 至少需要一个地点能力" % occupation_id)
		if (
			workplace_policy != "none"
			and places_by_name.has(primary_workplace_place)
		):
			var primary_place := places_by_name[
				primary_workplace_place
			] as Dictionary
			var primary_capabilities := primary_place.get(
				"capabilities",
				{},
			) as Dictionary
			var primary_capability_found := false
			for capability: String in required_capabilities:
				if primary_capabilities.get(capability) == true:
					primary_capability_found = true
					break
			if not primary_capability_found:
				errors.append(
					"%s 的主要工作地缺少职业所需能力：%s"
					% [occupation_id, primary_workplace_place],
				)
		for fixed_work_area_id: String in fixed_work_area_ids:
			if not slots_by_id.has(fixed_work_area_id):
				errors.append(
					"%s.fixedWorkAreaIds 引用未知工作位：%s"
					% [occupation_id, fixed_work_area_id],
				)
				continue
			var fixed_slot := slots_by_id[fixed_work_area_id] as Dictionary
			var fixed_activity_id := String(
				fixed_slot.get("activityId", ""),
			)
			var fixed_activity := activities_by_id.get(
				fixed_activity_id,
				{},
			) as Dictionary
			if (
				String(fixed_slot.get("role", "")) != "worker"
				or String(fixed_slot.get("placeName", ""))
					!= primary_workplace_place
				or not _arrays_intersect(
					fixed_activity.get("tags", []) as Array,
					allowed_tags,
				)
			):
				errors.append(
					"%s.fixedWorkAreaIds 工作位与职业不匹配：%s"
					% [occupation_id, fixed_work_area_id],
				)
		var schedule_template_id := String(
			occupation.get("scheduleTemplateId", "")
		)
		_validate_stable_reference(
			schedule_template_id,
			"%s.scheduleTemplateId" % occupation_id,
			errors,
		)
		if not _declared_schedule_template_ids(
			occupation_document
		).has(schedule_template_id):
			errors.append(
				"%s.scheduleTemplateId 必须显式登记为 resolved/unresolved reference"
				% occupation_id
			)
		if not schedules_by_id.has(schedule_template_id):
			errors.append(
				"%s 引用不存在的 schedule template：%s"
				% [occupation_id, schedule_template_id]
			)
		else:
			var schedule := schedules_by_id[
				schedule_template_id
			] as Dictionary
			if String(schedule.get("role", "")) != "worker":
				errors.append("%s 的 schedule role 必须为 worker" % occupation_id)
			for window_value: Variant in schedule.get("windows", []) as Array:
				if not window_value is Dictionary:
					continue
				var window := window_value as Dictionary
				if not _arrays_intersect(
					window.get("activityTagsAny", []) as Array,
					allowed_tags,
				):
					errors.append(
						"%s 的 schedule window 与 allowedActivityTags 不相容：%s"
						% [
							occupation_id,
							String(window.get("windowId", "")),
						]
					)
		if not _occupation_has_activity_chain(
			workplace_policy,
			allowed_tags,
			activities_by_id,
			slots_by_id,
			places_by_name,
		):
			errors.append(
				"%s 没有可验证的 worker activity chain" % occupation_id
			)


static func _occupation_has_activity_chain(
	workplace_policy: String,
	allowed_tags: Array,
	activities_by_id: Dictionary,
	slots_by_id: Dictionary,
	places_by_name: Dictionary,
) -> bool:
	for slot_value: Variant in slots_by_id.values():
		var slot := slot_value as Dictionary
		if workplace_policy != "none" and String(slot.get("role", "")) != "worker":
			continue
		var activity_id := String(slot.get("activityId", ""))
		if not activities_by_id.has(activity_id):
			continue
		var activity := activities_by_id[activity_id] as Dictionary
		var tags := activity.get("tags", []) as Array
		if not _arrays_intersect(tags, allowed_tags):
			continue
		var place_name := String(slot.get("placeName", ""))
		if not places_by_name.has(place_name):
			continue
		if workplace_policy == "required":
			var place := places_by_name[place_name] as Dictionary
			var capabilities := place.get("capabilities", {}) as Dictionary
			if not bool(capabilities.get("assignableWorkplace", false)):
				continue
		return true
	return false


static func _validate_default_social_supported_chains(
	occupation_document: Dictionary,
	activities_by_id: Dictionary,
	slots_by_id: Dictionary,
	places_by_name: Dictionary,
	errors: PackedStringArray,
) -> void:
	var occupations_by_id: Dictionary = {}
	for value: Variant in occupation_document.get(
		"occupations",
		[],
	) as Array:
		if value is Dictionary:
			var occupation := value as Dictionary
			occupations_by_id[String(
				occupation.get("occupationId", "")
			)] = occupation
	var coverage := occupation_document.get(
		"defaultSocialStateCoverage",
		{},
	) as Dictionary
	for value: Variant in coverage.get(
		"activityChainSupported",
		[],
	) as Array:
		if not value is Dictionary:
			continue
		var record := value as Dictionary
		var occupation_id := String(record.get("occupationId", ""))
		if not occupations_by_id.has(occupation_id):
			errors.append(
				"默认 supported 组合引用未知 occupationId：%s"
				% occupation_id
			)
			continue
		var occupation := occupations_by_id[occupation_id] as Dictionary
		if String(occupation.get("label", "")) != String(
			record.get("occupationName", "")
		):
			errors.append("默认 supported 组合职业显示名不匹配")
		var allowed_tags := occupation.get(
			"allowedActivityTags",
			[],
		) as Array
		var workplace_place := String(
			record.get("workplacePlace", "")
		)
		if workplace_place != String(
			occupation.get("primaryWorkplacePlace", ""),
		):
			errors.append(
				"默认 supported 组合工作地不是职业主要工作地：%s@%s"
				% [
					String(record.get("occupationName", "")),
					workplace_place,
				],
			)
		var workplace_capability_found := false
		if places_by_name.has(workplace_place):
			var workplace := places_by_name[workplace_place] as Dictionary
			var capabilities := workplace.get(
				"capabilities",
				{},
			) as Dictionary
			for capability_value: Variant in occupation.get(
				"requiredPlaceCapabilitiesAny",
				[],
			) as Array:
				if capabilities.get(String(capability_value)) == true:
					workplace_capability_found = true
					break
		var chain_found := false
		for slot_value: Variant in slots_by_id.values():
			var slot := slot_value as Dictionary
			if (
				String(slot.get("placeName", "")) != workplace_place
				or String(slot.get("role", "")) != "worker"
			):
				continue
			var activity_id := String(slot.get("activityId", ""))
			if not activities_by_id.has(activity_id):
				continue
			var activity := activities_by_id[activity_id] as Dictionary
			if _arrays_intersect(
				activity.get("tags", []) as Array,
				allowed_tags,
			):
				chain_found = true
				break
		if not chain_found:
			errors.append(
				"默认 supported 组合没有指定工作地 worker activity chain：%s@%s"
				% [
					String(record.get("occupationName", "")),
					workplace_place,
				]
			)
		if not workplace_capability_found:
			errors.append(
				"默认 supported 组合的指定工作地缺少该职业所需 capability：%s@%s"
				% [
					String(record.get("occupationName", "")),
					workplace_place,
				]
			)


static func _place_capability_pending_occupations(
	occupation_document: Dictionary,
	activities_by_id: Dictionary,
	slots_by_id: Dictionary,
	places_by_name: Dictionary,
) -> Array:
	var result := []
	for value: Variant in occupation_document.get(
		"occupations",
		[],
	) as Array:
		if not value is Dictionary:
			continue
		var occupation := value as Dictionary
		var occupation_id := String(
			occupation.get("occupationId", "")
		)
		var required_capabilities := occupation.get(
			"requiredPlaceCapabilitiesAny",
			[],
		) as Array
		var allowed_tags := occupation.get(
			"allowedActivityTags",
			[],
		) as Array
		var capability_proven := false
		for slot_value: Variant in slots_by_id.values():
			var slot := slot_value as Dictionary
			if String(slot.get("role", "")) != "worker":
				continue
			var activity_id := String(slot.get("activityId", ""))
			if not activities_by_id.has(activity_id):
				continue
			var activity := activities_by_id[activity_id] as Dictionary
			if not _arrays_intersect(
				activity.get("tags", []) as Array,
				allowed_tags,
			):
				continue
			var place_name := String(slot.get("placeName", ""))
			if not places_by_name.has(place_name):
				continue
			var place := places_by_name[place_name] as Dictionary
			var capabilities := place.get(
				"capabilities",
				{},
			) as Dictionary
			for capability_value: Variant in required_capabilities:
				var capability := String(capability_value)
				if capabilities.get(capability) == true:
					capability_proven = true
					break
			if capability_proven:
				break
		if not capability_proven:
			result.append(occupation_id)
	result.sort()
	return result


static func _unresolved_schedule_template_ids(
	occupation_document: Dictionary,
	schedules_by_id: Dictionary,
) -> Array:
	var status := occupation_document.get(
		"referenceStatus",
		{},
	) as Dictionary
	var result := []
	for value: Variant in status.get(
		"unresolvedScheduleTemplateIds",
		[],
	) as Array:
		var schedule_id := String(value)
		if not schedule_id.is_empty() and schedule_id not in result:
			result.append(schedule_id)
	for value: Variant in occupation_document.get("occupations", []) as Array:
		if not value is Dictionary:
			continue
		var schedule_id := String(
			(value as Dictionary).get("scheduleTemplateId", "")
		)
		if (
			not schedule_id.is_empty()
			and not schedules_by_id.has(schedule_id)
			and schedule_id not in result
		):
			result.append(schedule_id)
	result.sort()
	return result


static func _declared_schedule_template_ids(
	occupation_document: Dictionary,
) -> Array:
	var status := occupation_document.get(
		"referenceStatus",
		{},
	) as Dictionary
	var result := []
	for field in [
		"resolvedScheduleTemplateIds",
		"unresolvedScheduleTemplateIds",
	]:
		for value: Variant in status.get(field, []) as Array:
			var schedule_id := String(value)
			if not schedule_id.is_empty() and schedule_id not in result:
				result.append(schedule_id)
	result.sort()
	return result


static func _validate_content_gaps(
	gaps_value: Variant,
	label: String,
	errors: PackedStringArray,
) -> void:
	if not gaps_value is Array:
		errors.append("%s 必须为数组" % label)
		return
	var gap_ids: Dictionary = {}
	for index in (gaps_value as Array).size():
		var value: Variant = (gaps_value as Array)[index]
		if not value is Dictionary:
			errors.append("%s[%d] 必须为对象" % [label, index])
			continue
		var gap := value as Dictionary
		var gap_id := String(
			gap.get("gapId", gap.get("occupationId", ""))
		)
		if gap_id.is_empty():
			errors.append("%s[%d] 缺少稳定 gap id" % [label, index])
		elif gap_ids.has(gap_id):
			errors.append("%s gap id 重复：%s" % [label, gap_id])
		else:
			gap_ids[gap_id] = true
		if String(gap.get("reason", "")).strip_edges().is_empty():
			errors.append("%s[%d].reason 不能为空" % [label, index])


static func _expect_exact_string_array(
	value: Variant,
	expected: Array,
	label: String,
	errors: PackedStringArray,
) -> void:
	if not value is Array:
		errors.append("%s 必须为数组" % label)
		return
	if value != expected:
		errors.append("%s 必须精确等于 %s" % [label, str(expected)])


static func _validate_nonempty_string_array(
	value: Variant,
	label: String,
	errors: PackedStringArray,
) -> void:
	var values := _string_array(value, label, errors)
	if values.is_empty():
		errors.append("%s 至少需要一个值" % label)


static func _string_array(
	value: Variant,
	label: String,
	errors: PackedStringArray,
) -> Array:
	var result := []
	if not value is Array:
		errors.append("%s 必须为数组" % label)
		return result
	for index in (value as Array).size():
		var item: Variant = (value as Array)[index]
		if not item is String or String(item).strip_edges().is_empty():
			errors.append("%s[%d] 必须为非空字符串" % [label, index])
			continue
		if item not in result:
			result.append(item)
	return result


static func _validate_stable_id(
	value: String,
	required_prefix: String,
	label: String,
	errors: PackedStringArray,
) -> void:
	if not value.begins_with(required_prefix) or not _ascii_identifier(value):
		errors.append("%s 必须是以 %s 开头的稳定小写 id" % [
			label,
			required_prefix,
		])


static func _validate_stable_reference(
	value: String,
	label: String,
	errors: PackedStringArray,
) -> void:
	if value.is_empty() or not _ascii_identifier(value):
		errors.append("%s 必须是稳定小写 id" % label)


static func _ascii_identifier(value: String) -> bool:
	if value.is_empty():
		return false
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_"
	for index in value.length():
		if allowed.find(value.substr(index, 1)) < 0:
			return false
	return true


static func _contains_key_recursive(value: Variant, key_name: String) -> bool:
	if value is Dictionary:
		var dictionary := value as Dictionary
		for key_value: Variant in dictionary.keys():
			if String(key_value) == key_name:
				return true
			if _contains_key_recursive(dictionary[key_value], key_name):
				return true
	elif value is Array:
		for item: Variant in value as Array:
			if _contains_key_recursive(item, key_name):
				return true
	return false


static func _arrays_intersect(left: Array, right: Array) -> bool:
	for value: Variant in left:
		if value in right:
			return true
	return false


static func _prop_authoring_anchor_positions(
	interaction: Dictionary,
	slot_id: String,
	errors: PackedStringArray,
) -> Dictionary:
	var result: Dictionary = {}
	var base_anchor_id := String(interaction.get("anchorId", ""))
	var base_position: Variant = interaction.get("position")
	if not base_anchor_id.is_empty():
		if _valid_position(base_position):
			result[base_anchor_id] = (
				base_position as Array
			).duplicate(true)
		else:
			errors.append("%s 道具主交互锚点缺少合法坐标" % slot_id)
	var members_value: Variant = interaction.get("memberAnchors", [])
	if not members_value is Array:
		errors.append("%s 道具 memberAnchors authoring 必须为数组" % slot_id)
		return result
	for index in (members_value as Array).size():
		var value: Variant = (members_value as Array)[index]
		if not value is Dictionary:
			errors.append("%s 道具 memberAnchors[%d] 必须为对象" % [
				slot_id,
				index,
			])
			continue
		var member := value as Dictionary
		var anchor_id := String(member.get("anchorId", ""))
		var position_value: Variant = member.get("position")
		_validate_stable_reference(
			anchor_id,
			"%s 道具 memberAnchors[%d].anchorId" % [
				slot_id,
				index,
			],
			errors,
		)
		if not _valid_position(position_value):
			errors.append(
				"%s 道具 memberAnchors[%d].position 非法" % [
					slot_id,
					index,
				]
			)
			continue
		if result.has(anchor_id):
			errors.append("%s 道具 authoring anchorId 重复：%s" % [
				slot_id,
				anchor_id,
			])
		else:
			result[anchor_id] = (
				position_value as Array
			).duplicate(true)
	return result


static func _valid_position(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	for coordinate: Variant in value as Array:
		if not coordinate is int and not coordinate is float:
			return false
	return true


static func _is_integer_number(value: Variant) -> bool:
	return WORLD_SCALARS.is_integer_number(value)


static func _positions_equal(left: Array, right_value: Variant) -> bool:
	if not _valid_position(right_value):
		return false
	var right := right_value as Array
	return is_equal_approx(float(left[0]), float(right[0])) and is_equal_approx(
		float(left[1]),
		float(right[1]),
	)


static func _canonical_value(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "n"
		TYPE_BOOL:
			return "b1" if bool(value) else "b0"
		TYPE_INT:
			return "i%s;" % str(value)
		TYPE_FLOAT:
			return "f%s;" % JSON.stringify(value)
		TYPE_STRING:
			var encoded := JSON.stringify(String(value))
			return "s%d:%s" % [encoded.length(), encoded]
		TYPE_ARRAY:
			var array_parts := PackedStringArray()
			for item: Variant in value as Array:
				array_parts.append(_canonical_value(item))
			return "a%d:[%s]" % [
				(value as Array).size(),
				"".join(array_parts),
			]
		TYPE_DICTIONARY:
			var dictionary := value as Dictionary
			var keys := []
			for key_value: Variant in dictionary.keys():
				keys.append(String(key_value))
			keys.sort()
			var dictionary_parts := PackedStringArray()
			for key: String in keys:
				dictionary_parts.append(_canonical_value(key))
				dictionary_parts.append(
					_canonical_value(dictionary[key])
				)
			return "d%d:{%s}" % [
				dictionary.size(),
				"".join(dictionary_parts),
			]
		_:
			return "unsupported:%s;" % str(typeof(value))


static func _prop_action_binding_key(
	place_name: String,
	prop_name: String,
	action_verb: String,
	room_id: String,
) -> String:
	if (
		place_name.is_empty()
		or prop_name.is_empty()
		or action_verb.is_empty()
		or room_id.is_empty()
	):
		return ""
	return "%s\u001f%s\u001f%s\u001f%s" % [
		place_name,
		prop_name,
		action_verb,
		room_id,
	]
