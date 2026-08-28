class_name TownNewGameDraft
extends RefCounted


const SCHEMA_VERSION := TownSaveSchemaRegistry.NEW_GAME_DRAFT_SCHEMA_VERSION
const SOURCE_SCOPE := "resident_selection"
const POPULATION_RULES := preload("res://world/runtime/TownPopulationRules.gd")
const HOME_SLOT_COUNT := POPULATION_RULES.MAX_RESIDENT_COUNT


static func validate(draft: Dictionary) -> Dictionary:
	var errors: Array[Dictionary] = []
	if int(draft.get("schemaVersion", 0)) != SCHEMA_VERSION:
		errors.append(_error("schemaVersion", "SESSION_DRAFT_SCHEMA_UNSUPPORTED"))
	if String(draft.get("sourceScope", "")) != SOURCE_SCOPE:
		errors.append(_error("sourceScope", "SESSION_DRAFT_SOURCE_INVALID"))
	if int(draft.get("draftRevision", 0)) < 1:
		errors.append(_error("draftRevision", "SESSION_DRAFT_REVISION_INVALID"))
	var expected_spaces := home_space_ids()
	var slots_variant: Variant = draft.get("slots", [])
	if not (slots_variant is Array):
		errors.append(_error("slots", "SESSION_DRAFT_SLOTS_INVALID"))
		slots_variant = []
	var slots: Array = slots_variant
	var seen_space_ids: Dictionary = {}
	var seen_resident_ids: Dictionary = {}
	for index in range(slots.size()):
		if not (slots[index] is Dictionary):
			errors.append(_error("slots[%d]" % index, "SESSION_DRAFT_SLOT_INVALID"))
			continue
		var slot: Dictionary = slots[index]
		var space_id := String(slot.get("spaceId", ""))
		var resident_id := String(slot.get("residentId", "")).strip_edges()
		if space_id.is_empty():
			errors.append(_error("slots[%d].spaceId" % index, "SESSION_HOME_SPACE_REQUIRED"))
		elif not expected_spaces.has(space_id):
			errors.append(_error("slots[%d].spaceId" % index, "SESSION_HOME_SPACE_UNKNOWN"))
		elif seen_space_ids.has(space_id):
			errors.append(_error("slots[%d].spaceId" % index, "SESSION_HOME_SPACE_DUPLICATED"))
		else:
			seen_space_ids[space_id] = true
		if resident_id.is_empty():
			errors.append(_error("slots[%d].residentId" % index, "SESSION_RESIDENT_ID_REQUIRED"))
		elif seen_resident_ids.has(resident_id):
			errors.append(_error("slots[%d].residentId" % index, "SESSION_RESIDENT_ID_DUPLICATED"))
		else:
			seen_resident_ids[resident_id] = true
		var binding_variant: Variant = slot.get("llmBinding", {})
		if not (binding_variant is Dictionary):
			errors.append(_error("slots[%d].llmBinding" % index, "SESSION_LLM_BINDING_INVALID"))
		else:
			var binding: Dictionary = binding_variant
			if String(binding.get("mode", "")) != "model":
				errors.append(_error(
					"slots[%d].llmBinding.mode" % index,
					"SESSION_LLM_BINDING_MODE_INVALID",
				))
			if String(binding.get("providerId", "")).is_empty():
				errors.append(_error(
					"slots[%d].llmBinding.providerId" % index,
					"SESSION_LLM_PROVIDER_REQUIRED",
				))
			if String(binding.get("modelId", "")).is_empty():
				errors.append(_error(
					"slots[%d].llmBinding.modelId" % index,
					"SESSION_LLM_MODEL_REQUIRED",
				))
	if not POPULATION_RULES.supports_resident_count(slots.size()):
		errors.append(_error(
			"slots",
			"SESSION_RESIDENT_COUNT_OUT_OF_RANGE",
			{
				"minimum": POPULATION_RULES.MIN_RESIDENT_COUNT,
				"maximum": POPULATION_RULES.MAX_RESIDENT_COUNT,
				"actual": slots.size(),
			},
		))
	return {
		"ok": errors.is_empty(),
		"errorCode": "" if errors.is_empty() else "SESSION_DRAFT_INVALID",
		"retryable": false,
		"draftRevision": int(draft.get("draftRevision", 0)),
		"errors": errors,
		"residentCount": slots.size(),
		"minimumResidentCount": POPULATION_RULES.MIN_RESIDENT_COUNT,
		"defaultResidentCount": POPULATION_RULES.DEFAULT_RESIDENT_COUNT,
		"maximumResidentCount": POPULATION_RULES.MAX_RESIDENT_COUNT,
		"expectedSpaceIds": expected_spaces,
	}


static func model_bindings(draft: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var slots: Array = (draft.get("slots", []) as Array).duplicate(true)
	slots.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String((a as Dictionary).get("spaceId", "")) < String((b as Dictionary).get("spaceId", ""))
	)
	for slot_variant in slots:
		var slot := slot_variant as Dictionary
		result.append({
			"residentId": String(slot.get("residentId", "")),
			"spaceId": String(slot.get("spaceId", "")),
			"llmBinding": (slot.get("llmBinding", {}) as Dictionary).duplicate(true),
		})
	return result


static func home_space_ids() -> Array[String]:
	var result: Array[String] = []
	for index in range(1, HOME_SLOT_COUNT + 1):
		result.append("home_%02d" % index)
	return result


static func _error(path: String, code: String, meta: Dictionary = {}) -> Dictionary:
	return {
		"path": path,
		"code": code,
		"meta": meta.duplicate(true),
	}
