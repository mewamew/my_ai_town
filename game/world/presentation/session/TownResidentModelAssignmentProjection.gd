class_name TownResidentModelAssignmentProjection
extends RefCounted


const POPULATION_RULES := preload("res://world/runtime/TownPopulationRules.gd")


static func build(
	session_config_value: Variant,
	base_catalog_value: Variant,
) -> Dictionary:
	if not session_config_value is Dictionary or not base_catalog_value is Dictionary:
		return _failure("SESSION_RESIDENT_ASSIGNMENT_PROJECTION_INVALID")
	var session_config := session_config_value as Dictionary
	var base_catalog := base_catalog_value as Dictionary
	var identities_value: Variant = session_config.get("residentIdentities")
	var bindings_value: Variant = session_config.get("residentBindings")
	var opening_value: Variant = session_config.get("openingConfig")
	if (
		not identities_value is Array
		or not bindings_value is Array
		or not opening_value is Dictionary
	):
		return _failure("SESSION_RESIDENT_ASSIGNMENT_PROJECTION_INVALID")
	var identities := identities_value as Array
	if not POPULATION_RULES.supports_resident_count(identities.size()):
		return _failure("SESSION_RESIDENT_ASSIGNMENT_PROJECTION_INVALID")
	var expected_ids: Array[String] = []
	for value: Variant in identities:
		if not value is Dictionary:
			return _failure("SESSION_RESIDENT_ASSIGNMENT_PROJECTION_INVALID")
		var resident_id := String(
			(value as Dictionary).get("residentId", ""),
		).strip_edges()
		if resident_id.is_empty() or expected_ids.has(resident_id):
			return _failure("SESSION_RESIDENT_ASSIGNMENT_PROJECTION_INVALID")
		expected_ids.append(resident_id)
	expected_ids.sort()
	var normalized := normalize_bindings(bindings_value, expected_ids)
	if normalized.get("ok") != true:
		return normalized
	var binding_by_id: Dictionary = {}
	for binding in normalized.get("bindings", []) as Array[Dictionary]:
		binding_by_id[String(binding.get("residentId", ""))] = (
			binding.get("llmBinding", {}) as Dictionary
		).duplicate(true)
	var opening := opening_value as Dictionary
	var saved_by_id := _records_by_id(opening.get("residents", []))
	var base_by_id := _records_by_id(base_catalog.get("residents", []))
	var residents: Array[Dictionary] = []
	var slots: Array[Dictionary] = []
	for index in expected_ids.size():
		var resident_id := expected_ids[index]
		var saved := saved_by_id.get(resident_id, {}) as Dictionary
		var base := base_by_id.get(resident_id, {}) as Dictionary
		var attributes := (
			(saved.get("attributes", {}) as Dictionary).duplicate(true)
			if saved.get("attributes") is Dictionary
			else (base.get("attributes", {}) as Dictionary).duplicate(true)
		)
		if attributes.is_empty():
			attributes = {"name": resident_id}
		var presentation := (
			base.get("presentation", {}) as Dictionary
		).duplicate(true)
		if saved.get("presentation") is Dictionary:
			presentation.merge(
				(saved.get("presentation", {}) as Dictionary).duplicate(true),
				true,
			)
		residents.append({
			"residentId": resident_id,
			"attributes": attributes,
			"presentation": presentation,
		})
		slots.append({
			"residentId": resident_id,
			"spaceId": "home_%02d" % (index + 1),
			"llmBinding": (binding_by_id[resident_id] as Dictionary).duplicate(true),
		})
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentCatalog": {"residents": residents},
		"draft": {
			"schemaVersion": 1,
			"sourceScope": "resident_selection",
			"draftRevision": 1,
			"slots": slots,
		},
	}


static func normalize_bindings(
	bindings_value: Variant,
	expected_ids_value: Variant,
) -> Dictionary:
	if not bindings_value is Array or not expected_ids_value is Array:
		return _failure("SESSION_LLM_BINDINGS_INVALID")
	var expected_ids: Array[String] = []
	for value: Variant in expected_ids_value as Array:
		if not value is String:
			return _failure("SESSION_LLM_BINDINGS_INVALID")
		expected_ids.append(value as String)
	expected_ids.sort()
	var seen: Dictionary = {}
	var bindings: Array[Dictionary] = []
	for value: Variant in bindings_value as Array:
		if not value is Dictionary:
			return _failure("SESSION_LLM_BINDINGS_INVALID")
		var item := value as Dictionary
		var resident_id := String(item.get("residentId", "")).strip_edges()
		var llm_value: Variant = item.get("llmBinding")
		if (
			resident_id.is_empty()
			or not expected_ids.has(resident_id)
			or seen.has(resident_id)
			or not llm_value is Dictionary
		):
			return _failure("SESSION_LLM_BINDINGS_INVALID")
		var llm := llm_value as Dictionary
		var provider_id := String(llm.get("providerId", "")).strip_edges()
		var model_id := String(llm.get("modelId", "")).strip_edges()
		if (
			String(llm.get("mode", "")) != "model"
			or provider_id.is_empty()
			or model_id.is_empty()
		):
			return _failure("SESSION_LLM_BINDINGS_INVALID")
		seen[resident_id] = true
		bindings.append({
			"residentId": resident_id,
			"llmBinding": {
				"mode": "model",
				"providerId": provider_id,
				"modelId": model_id,
			},
		})
	if seen.size() != expected_ids.size():
		return _failure("SESSION_LLM_BINDINGS_INVALID")
	bindings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"bindings": bindings,
	}


static func _records_by_id(value: Variant) -> Dictionary:
	var records: Dictionary = {}
	if not value is Array:
		return records
	for record_value: Variant in value as Array:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var resident_id := String(record.get("residentId", "")).strip_edges()
		if not resident_id.is_empty() and not records.has(resident_id):
			records[resident_id] = record.duplicate(true)
	return records


static func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"errors": [],
	}
