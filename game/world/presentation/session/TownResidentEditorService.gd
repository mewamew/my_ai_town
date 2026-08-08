class_name TownResidentEditorService
extends RefCounted


signal view_model_changed(scope: String, view_model: Dictionary)


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const SCOPE := "resident_editor"
const SLOT_COUNT := 15
const CATALOG := preload("res://world/presentation/session/TownResidentCatalog.gd")
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const DRAFT := preload("res://world/presentation/session/TownNewGameDraft.gd")
const COMPILER := preload(
	"res://world/presentation/session/TownNewGameOpeningCompiler.gd"
)
const INTENT_TO_ACTION := {
	"resident_editor.select_slot": "selectSlot",
	"resident_editor.update_attributes": "updateAttributes",
	"resident_editor.assign_home": "assignHome",
	"resident_editor.assign_occupation": "assignOccupation",
	"resident_editor.assign_workplace": "assignWorkplace",
	"resident_editor.restore_default": "restoreDefault",
	"resident_editor.randomize": "randomize",
	"resident_editor.save": "save",
	"resident_editor.retry": "retry",
	"resident_editor.back": "back",
}
const ATTRIBUTE_FIELDS := [
	"name",
	"gender",
	"age",
	"appearanceId",
	"desire",
	"personality",
	"speech",
	"interests",
	"customInterests",
]


var _catalog: Dictionary = {}
var _world_data: Dictionary = {}
var _draft: Dictionary = {}
var _entries: Array[Dictionary] = []
var _defaults_by_slot: Dictionary = {}
var _selected_slot_id := ""
var _draft_id := ""
var _configured := false
var _dirty := false
var _revision := 0
var _request_sequence := 0
var _operation := _idle_operation()
var _error: Variant = null
var _configuration_error := "RESIDENT_EDITOR_SERVICE_NOT_CONFIGURED"
var _occupation_options: Array[Dictionary] = []
var _occupation_by_id: Dictionary = {}
var _appearance_options: Array[Dictionary] = []
var _appearance_by_id: Dictionary = {}
var _home_options: Array[Dictionary] = []
var _home_by_space: Dictionary = {}
var _workplace_options: Array[Dictionary] = []
var _workplace_by_id: Dictionary = {}
var _gender_options: Array[Dictionary] = []
var _saved_catalog: Dictionary = {}
var _saved_draft: Dictionary = {}


func configure(
	catalog: Dictionary,
	world_data: Dictionary,
	session_draft: Dictionary,
	context: Dictionary = {},
) -> Dictionary:
	_reset()
	var catalog_validation := CATALOG.validate(catalog) as Dictionary
	if not bool(catalog_validation.get("ok", false)):
		return _configuration_failure(
			String(catalog_validation.get("errorCode", "SESSION_CATALOG_INVALID")),
		)
	var draft_validation := DRAFT.validate(session_draft) as Dictionary
	if not bool(draft_validation.get("ok", false)):
		return _configuration_failure(
			String(draft_validation.get("errorCode", "SESSION_DRAFT_INVALID")),
		)
	if world_data.is_empty():
		return _configuration_failure("RESIDENT_EDITOR_WORLD_CATALOG_MISSING")
	var compile_validation := COMPILER.compile(
		session_draft,
		world_data,
		catalog,
	) as Dictionary
	if not bool(compile_validation.get("ok", false)):
		return _configuration_failure(
			String(
				compile_validation.get(
					"errorCode",
					"RESIDENT_EDITOR_SESSION_DRAFT_INVALID",
				)
			),
			compile_validation.get("errors", []) as Array,
		)

	_catalog = catalog.duplicate(true)
	_world_data = world_data.duplicate(true)
	_draft = session_draft.duplicate(true)
	_build_options()
	var residents_by_id := _residents_by_id(_catalog)
	for index in SLOT_COUNT:
		var binding := (_draft.get("slots", []) as Array)[index] as Dictionary
		var resident_id := String(binding.get("residentId", ""))
		var resident := (residents_by_id.get(resident_id, {}) as Dictionary).duplicate(true)
		if resident.is_empty():
			return _configuration_failure("RESIDENT_EDITOR_RESIDENT_NOT_FOUND")
		var entry := _entry_from_sources(index, binding, resident)
		_entries.append(entry)
		_defaults_by_slot[String(entry.get("slotId", ""))] = entry.duplicate(true)
	_selected_slot_id = String(_entries[0].get("slotId", ""))
	_draft_id = String(context.get("draftId", "")).strip_edges()
	if _draft_id.is_empty():
		_draft_id = "resident-editor-%d" % int(_draft.get("draftRevision", 1))
	_configured = true
	_configuration_error = ""
	_revision = maxi(int(context.get("revision", 1)), 1)
	_saved_catalog = _build_catalog(_entries)
	_saved_draft = _build_draft(_entries)
	_emit_view_model()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"revision": _revision,
		"draftId": _draft_id,
	}


func get_view_model() -> Dictionary:
	if not _configured:
		return _disabled_view_model()
	var validation := _validate_entries(_entries)
	var data := _data_snapshot(validation)
	var status := "ready"
	var operation_status := String(_operation.get("status", "idle"))
	if operation_status == "loading":
		status = "loading"
	elif operation_status == "error":
		status = "error"
	return {
		"scope": SCOPE,
		"status": status,
		"revision": _revision,
		"data": data,
		"actions": _actions_snapshot(validation),
		"operation": _operation.duplicate(true),
		"error": null if _error == null else (_error as Dictionary).duplicate(true),
	}


func dispatch(intent: String, payload: Dictionary = {}) -> Dictionary:
	var action_key := String(INTENT_TO_ACTION.get(intent, ""))
	if action_key.is_empty():
		return _dispatch_result(false, false, "", "UNKNOWN_RESIDENT_EDITOR_INTENT", false)
	var request_id := _next_request_id()
	if not _configured:
		return _dispatch_result(
			false,
			false,
			request_id,
			_configuration_error,
			false,
		)
	var action := (_actions_snapshot(_validate_entries(_entries)).get(
		action_key,
		{},
	) as Dictionary)
	if not bool(action.get("enabled", false)):
		return _finish_operation(
			request_id,
			intent,
			_failure(String(action.get("disabledReason", "RESIDENT_EDITOR_ACTION_DISABLED"))),
		)
	if int(payload.get("revision", -1)) != _revision:
		return _finish_operation(
			request_id,
			intent,
			_failure("RESIDENT_EDITOR_REVISION_STALE"),
		)
	if String(payload.get("draftId", "")) != _draft_id:
		return _finish_operation(
			request_id,
			intent,
			_failure("RESIDENT_EDITOR_DRAFT_MISMATCH"),
		)

	_operation = {
		"requestId": request_id,
		"intent": intent,
		"status": "loading",
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": 0,
	}
	_error = null
	_revision += 1
	_emit_view_model()
	var normalized_payload := payload.duplicate(true)
	# The loading ViewModel has a newer revision, but the command remains bound to
	# the revision supplied by the page before loading started.
	normalized_payload["revision"] = _revision
	var result := _execute_intent(intent, normalized_payload)
	return _finish_operation(request_id, intent, result)


func get_session_catalog() -> Dictionary:
	return _build_catalog(_entries) if _configured else {}


func get_session_draft() -> Dictionary:
	return _build_draft(_entries) if _configured else {}


func get_saved_catalog() -> Dictionary:
	return _saved_catalog.duplicate(true)


func get_saved_draft() -> Dictionary:
	return _saved_draft.duplicate(true)


func _execute_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"resident_editor.select_slot":
			return _select_slot(String(payload.get("slotId", "")))
		"resident_editor.update_attributes":
			return _update_attributes(
				String(payload.get("slotId", "")),
				payload.get("fields", {}) as Dictionary,
			)
		"resident_editor.assign_home":
			return _assign_home(
				String(payload.get("slotId", "")),
				String(payload.get("homeSpaceId", "")),
			)
		"resident_editor.assign_occupation":
			return _assign_occupation(
				String(payload.get("slotId", "")),
				String(payload.get("occupationId", "")),
			)
		"resident_editor.assign_workplace":
			return _failure("RESIDENT_EDITOR_WORKPLACE_DERIVED")
		"resident_editor.restore_default":
			return _restore_default(String(payload.get("slotId", "")))
		"resident_editor.randomize":
			return _randomize_profile(String(payload.get("slotId", "")))
		"resident_editor.save":
			return _save()
		"resident_editor.retry":
			return _failure("NO_RETRYABLE_ERROR")
		"resident_editor.back":
			return _success(false)
	return _failure("UNKNOWN_RESIDENT_EDITOR_INTENT")


func _select_slot(slot_id: String) -> Dictionary:
	if _entry_index(slot_id) < 0:
		return _failure("RESIDENT_EDITOR_SLOT_NOT_FOUND")
	var changed := _selected_slot_id != slot_id
	_selected_slot_id = slot_id
	return _success(changed)


func _update_attributes(slot_id: String, fields: Dictionary) -> Dictionary:
	var index := _entry_index(slot_id)
	if index < 0:
		return _failure("RESIDENT_EDITOR_SLOT_NOT_FOUND")
	if fields.is_empty():
		return _failure("RESIDENT_EDITOR_ATTRIBUTE_FIELDS_REQUIRED")
	var candidate_entries := _entries.duplicate(true)
	var entry := (candidate_entries[index] as Dictionary).duplicate(true)
	var attributes := (entry.get("attributes", {}) as Dictionary).duplicate(true)
	for field_value: Variant in fields.keys():
		var field := String(field_value)
		if not ATTRIBUTE_FIELDS.has(field):
			return _failure("RESIDENT_EDITOR_ATTRIBUTE_FIELD_UNKNOWN")
		var value: Variant = fields[field]
		match field:
			"age":
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
					return _failure("RESIDENT_EDITOR_AGE_INVALID")
				var age := int(value)
				if age < 1 or age > 120:
					return _failure("RESIDENT_EDITOR_AGE_INVALID")
				attributes[field] = age
			"appearanceId":
				var appearance_id := String(value).strip_edges()
				if not _appearance_by_id.has(appearance_id):
					return _failure("RESIDENT_EDITOR_APPEARANCE_UNKNOWN")
				attributes[field] = appearance_id
			"gender":
				var gender := String(value).strip_edges()
				if not _option_has_id(_gender_options, gender):
					return _failure("RESIDENT_EDITOR_GENDER_INVALID")
				attributes[field] = gender
			"interests":
				var interest_values := INTERESTS.normalize(value)
				var interest_error := INTERESTS.profile_validation_error(
					interest_values,
					attributes.get("customInterests", []),
				)
				if not interest_error.is_empty():
					return _failure(interest_error)
				attributes[field] = interest_values
			"customInterests":
				var custom_interest_values := INTERESTS.normalize_custom(
					value,
				)
				var custom_interest_error := (
					INTERESTS.profile_validation_error(
						attributes.get("interests", []),
						custom_interest_values,
					)
				)
				if not custom_interest_error.is_empty():
					return _failure(custom_interest_error)
				attributes[field] = custom_interest_values
			_:
				var text := String(value).strip_edges()
				if text.is_empty():
					return _failure("RESIDENT_EDITOR_ATTRIBUTE_REQUIRED")
				if text.length() > 1200:
					return _failure("RESIDENT_EDITOR_ATTRIBUTE_TOO_LONG")
				attributes[field] = text
	entry["attributes"] = attributes
	candidate_entries[index] = entry
	return _commit_candidate(candidate_entries)


func _assign_home(slot_id: String, home_space_id: String) -> Dictionary:
	var index := _entry_index(slot_id)
	if index < 0:
		return _failure("RESIDENT_EDITOR_SLOT_NOT_FOUND")
	if not _home_by_space.has(home_space_id):
		return _failure("RESIDENT_EDITOR_HOME_UNKNOWN")
	var current_home := String(_entries[index].get("homeSpaceId", ""))
	if current_home == home_space_id:
		return _success(false)
	var candidate_entries := _entries.duplicate(true)
	var swap_index := -1
	for other_index in candidate_entries.size():
		if String(candidate_entries[other_index].get("homeSpaceId", "")) == home_space_id:
			swap_index = other_index
			break
	candidate_entries[index]["homeSpaceId"] = home_space_id
	if swap_index >= 0:
		candidate_entries[swap_index]["homeSpaceId"] = current_home
	return _commit_candidate(candidate_entries)


func _assign_occupation(slot_id: String, occupation_id: String) -> Dictionary:
	var index := _entry_index(slot_id)
	if index < 0:
		return _failure("RESIDENT_EDITOR_SLOT_NOT_FOUND")
	if not _occupation_by_id.has(occupation_id):
		return _failure("RESIDENT_EDITOR_OCCUPATION_UNKNOWN")
	var candidate_entries := _entries.duplicate(true)
	var entry := (candidate_entries[index] as Dictionary).duplicate(true)
	entry["occupation"] = (
		_occupation_by_id[occupation_id] as Dictionary
	).duplicate(true)
	candidate_entries[index] = entry
	return _commit_candidate(candidate_entries)


func _restore_default(slot_id: String) -> Dictionary:
	var index := _entry_index(slot_id)
	if index < 0 or not _defaults_by_slot.has(slot_id):
		return _failure("RESIDENT_EDITOR_SLOT_NOT_FOUND")
	var default_entry := (_defaults_by_slot[slot_id] as Dictionary).duplicate(true)
	if _entries[index] == default_entry:
		return _success(false)
	var candidate_entries := _entries.duplicate(true)
	# Preserve another slot's current home by swapping, so the 15-home invariant
	# remains true when this resident is restored after a home reassignment.
	var default_home := String(default_entry.get("homeSpaceId", ""))
	var current_home := String(candidate_entries[index].get("homeSpaceId", ""))
	for other_index in candidate_entries.size():
		if (
			other_index != index
			and String(candidate_entries[other_index].get("homeSpaceId", "")) == default_home
		):
			candidate_entries[other_index]["homeSpaceId"] = current_home
			break
	candidate_entries[index] = default_entry
	return _commit_candidate(candidate_entries)


func _randomize_profile(slot_id: String) -> Dictionary:
	var index := _entry_index(slot_id)
	if index < 0:
		return _failure("RESIDENT_EDITOR_SLOT_NOT_FOUND")
	var residents := _catalog.get("residents", []) as Array
	if residents.is_empty():
		return _failure("RESIDENT_EDITOR_CATALOG_EMPTY")
	var source_index := (index + _revision + 1) % residents.size()
	var source := residents[source_index] as Dictionary
	var source_attributes := source.get("attributes", {}) as Dictionary
	var candidate_entries := _entries.duplicate(true)
	var entry := (candidate_entries[index] as Dictionary).duplicate(true)
	var attributes := (entry.get("attributes", {}) as Dictionary).duplicate(true)
	for field in [
		"gender",
		"age",
		"appearance",
		"desire",
		"personality",
		"speech",
		"interests",
		"customInterests",
	]:
		var target_field: String = "appearanceId" if field == "appearance" else String(field)
		var source_value: Variant = source_attributes.get(
			field,
			attributes.get(target_field),
		)
		attributes[target_field] = (
			source_value.duplicate(true)
			if source_value is Array or source_value is Dictionary
			else source_value
		)
	entry["attributes"] = attributes
	candidate_entries[index] = entry
	return _commit_candidate(candidate_entries)


func _save() -> Dictionary:
	var validation := _validate_entries(_entries)
	if String(validation.get("status", "invalid")) != "valid":
		return _failure("RESIDENT_EDITOR_DRAFT_INVALID")
	_saved_catalog = _build_catalog(_entries)
	_saved_draft = _build_draft(_entries)
	var compiled := COMPILER.compile(_saved_draft, _world_data, _saved_catalog) as Dictionary
	if not bool(compiled.get("ok", false)):
		return _failure(
			String(compiled.get("errorCode", "RESIDENT_EDITOR_DRAFT_INVALID")),
			false,
			compiled.get("errors", []) as Array,
		)
	_catalog = _saved_catalog.duplicate(true)
	_draft = _saved_draft.duplicate(true)
	_dirty = false
	for entry in _entries:
		_defaults_by_slot[String(entry.get("slotId", ""))] = entry.duplicate(true)
	return _success(true)


func _commit_candidate(candidate_entries: Array[Dictionary]) -> Dictionary:
	var validation := _validate_entries(candidate_entries)
	if String(validation.get("status", "invalid")) != "valid":
		return _failure(
			"RESIDENT_EDITOR_DRAFT_INVALID",
			false,
			validation.get("issues", []) as Array,
		)
	var candidate_catalog := _build_catalog(candidate_entries)
	var candidate_draft := _build_draft(candidate_entries)
	var compiled := COMPILER.compile(
		candidate_draft,
		_world_data,
		candidate_catalog,
	) as Dictionary
	if not bool(compiled.get("ok", false)):
		return _failure(
			String(compiled.get("errorCode", "RESIDENT_EDITOR_DRAFT_INVALID")),
			false,
			compiled.get("errors", []) as Array,
		)
	var changed := candidate_entries != _entries
	if changed:
		_entries = candidate_entries.duplicate(true)
		_dirty = true
	return _success(changed)


func _finish_operation(
	request_id: String,
	intent: String,
	result: Dictionary,
) -> Dictionary:
	var ok := bool(result.get("ok", false))
	var retryable := bool(result.get("retryable", false))
	_operation = {
		"requestId": request_id,
		"intent": intent,
		"status": "success" if ok else ("error" if retryable else "rejected"),
		"submittedAtMsec": int(_operation.get("submittedAtMsec", Time.get_ticks_msec())),
		"completedAtMsec": Time.get_ticks_msec(),
	}
	_error = null if ok else {
		"kind": "transport" if retryable else "validation",
		"code": String(result.get("errorCode", "RESIDENT_EDITOR_COMMAND_REJECTED")),
		"retryable": retryable,
		"message": String(result.get("message", "居民草稿未通过检查，已保留原数据。")),
		"details": (result.get("errors", []) as Array).duplicate(true),
	}
	_revision += 1
	_emit_view_model()
	return _dispatch_result(
		ok,
		true,
		request_id,
		String(result.get("errorCode", "")),
		retryable,
		bool(result.get("changed", false)),
	)


func _data_snapshot(validation: Dictionary) -> Dictionary:
	var slots: Array[Dictionary] = []
	var valid_slots := validation.get("validSlots", {}) as Dictionary
	for entry in _entries:
		var slot_id := String(entry.get("slotId", ""))
		var attributes := entry.get("attributes", {}) as Dictionary
		var occupation := entry.get("occupation", {}) as Dictionary
		var home_space_id := String(entry.get("homeSpaceId", ""))
		var slot_valid := bool(valid_slots.get(slot_id, false))
		slots.append({
			"slotId": slot_id,
			"ordinal": int(entry.get("ordinal", 0)),
			"residentId": String(entry.get("residentId", "")),
			"displayName": String(attributes.get("name", "")),
			"homeSpaceId": home_space_id,
			"homeLabel": _home_label(home_space_id),
			"occupationLabel": String(occupation.get("label", "")),
			"workplaceLabel": String(occupation.get("workplaceLabel", "")),
			"validationStatus": "valid" if slot_valid else "invalid",
			"issueCodes": (
				validation.get("issuesBySlot", {}).get(slot_id, []) as Array
			).duplicate(),
		})
	var selected := _entry_by_slot(_selected_slot_id)
	var selected_attributes := selected.get("attributes", {}) as Dictionary
	var selected_occupation := selected.get("occupation", {}) as Dictionary
	var appearance_id := String(selected_attributes.get("appearanceId", ""))
	var appearance := _appearance_by_id.get(appearance_id, {}) as Dictionary
	var completed_count := int(validation.get("completedSlotCount", 0))
	return {
		"capabilityMode": "formal",
		"source": "runtime",
		"formalReady": true,
		"draftId": _draft_id,
		"flowMode": "new_game",
		"selectedSlotId": _selected_slot_id,
		"slotCount": SLOT_COUNT,
		"completedSlotCount": completed_count,
		"invalidSlotCount": SLOT_COUNT - completed_count,
		"dirty": _dirty,
		"slots": slots,
		"editor": {
			"slotId": _selected_slot_id,
			"residentId": String(selected.get("residentId", "")),
			"attributes": {
				"name": String(selected_attributes.get("name", "")),
				"gender": String(selected_attributes.get("gender", "")),
				"age": int(selected_attributes.get("age", 0)),
				"appearanceId": appearance_id,
				"appearanceLabel": String(appearance.get("label", appearance_id)),
				"appearanceStatus": String(appearance.get("status", "unavailable")),
				"portraitRef": String(appearance.get("portraitRef", "")),
				"desire": String(selected_attributes.get("desire", "")),
				"personality": String(selected_attributes.get("personality", "")),
				"speech": String(selected_attributes.get("speech", "")),
				"interests": INTERESTS.normalize(
					selected_attributes.get("interests", []),
				),
				"customInterests": INTERESTS.normalize_custom(
					selected_attributes.get("customInterests", []),
				),
			},
			"social": {
				"homeSpaceId": String(selected.get("homeSpaceId", "")),
				"homeLabel": _home_label(String(selected.get("homeSpaceId", ""))),
				"occupationId": String(selected_occupation.get("id", "")),
				"occupationLabel": String(selected_occupation.get("label", "")),
				"workplaceMode": String(selected_occupation.get("workplaceMode", "")),
				"workplaceId": String(selected_occupation.get("workplaceId", "")),
				"workplaceLabel": String(selected_occupation.get("workplaceLabel", "")),
			},
		},
		"options": {
			"genders": _gender_options.duplicate(true),
			"age": {"min": 1, "max": 120, "step": 1},
			"interests": INTERESTS.options(),
			"maxInterests": INTERESTS.max_interests(),
			"appearanceStatus": "formal",
			"appearances": _appearance_options.duplicate(true),
			"homeSpaces": _home_option_snapshot(),
			"occupations": _occupation_options.duplicate(true),
			"workplaces": _workplace_option_snapshot(),
		},
		"validation": {
			"status": String(validation.get("status", "invalid")),
			"summaryLabel": (
				"15 个居民槽位资料完整"
				if completed_count == SLOT_COUNT
				else "%d 个居民槽位需要处理" % (SLOT_COUNT - completed_count)
			),
			"issues": (validation.get("issues", []) as Array).duplicate(true),
			"fieldIssues": (
				validation.get("selectedFieldIssues", {}) as Dictionary
			).duplicate(true),
		},
		"copyProfile": _copy_profile(selected_attributes),
	}


func _actions_snapshot(validation: Dictionary) -> Dictionary:
	var available := _configured
	var valid := String(validation.get("status", "invalid")) == "valid"
	var retryable := _error is Dictionary and bool((_error as Dictionary).get("retryable", false))
	return {
		"selectSlot": _action("resident_editor.select_slot", available, "RESIDENT_EDITOR_SERVICE_NOT_READY"),
		"updateAttributes": _action("resident_editor.update_attributes", available, "RESIDENT_EDITOR_SERVICE_NOT_READY"),
		"assignHome": _action("resident_editor.assign_home", available, "RESIDENT_EDITOR_SERVICE_NOT_READY"),
		"assignOccupation": _action("resident_editor.assign_occupation", available, "RESIDENT_EDITOR_SERVICE_NOT_READY"),
		"assignWorkplace": _action(
			"resident_editor.assign_workplace",
			false,
			"RESIDENT_EDITOR_WORKPLACE_DERIVED",
		),
		"restoreDefault": _action("resident_editor.restore_default", available, "RESIDENT_EDITOR_SERVICE_NOT_READY"),
		"randomize": _action("resident_editor.randomize", available, "RESIDENT_EDITOR_SERVICE_NOT_READY"),
		"save": _action("resident_editor.save", available and valid, "RESIDENT_EDITOR_DRAFT_INVALID"),
		"retry": _action("resident_editor.retry", retryable, "NO_RETRYABLE_ERROR"),
		"back": _action("resident_editor.back", available, "RESIDENT_EDITOR_SERVICE_NOT_READY"),
	}


func _validate_entries(entries: Array[Dictionary]) -> Dictionary:
	var issues: Array[Dictionary] = []
	var issues_by_slot: Dictionary = {}
	var field_issues_by_slot: Dictionary = {}
	var seen_homes: Dictionary = {}
	var seen_names: Dictionary = {}
	var valid_slots: Dictionary = {}
	for entry in entries:
		var slot_id := String(entry.get("slotId", ""))
		var attributes := entry.get("attributes", {}) as Dictionary
		var occupation := entry.get("occupation", {}) as Dictionary
		var slot_codes: Array[String] = []
		var field_issues: Dictionary = {}
		var name := String(attributes.get("name", "")).strip_edges()
		if name.is_empty():
			_add_field_issue(field_issues, "attributes.name", "RESIDENT_EDITOR_NAME_REQUIRED")
			slot_codes.append("RESIDENT_EDITOR_NAME_REQUIRED")
		elif seen_names.has(name):
			_add_field_issue(field_issues, "attributes.name", "RESIDENT_EDITOR_NAME_DUPLICATED")
			slot_codes.append("RESIDENT_EDITOR_NAME_DUPLICATED")
		else:
			seen_names[name] = slot_id
		var age := int(attributes.get("age", 0))
		if age < 1 or age > 120:
			_add_field_issue(field_issues, "attributes.age", "RESIDENT_EDITOR_AGE_INVALID")
			slot_codes.append("RESIDENT_EDITOR_AGE_INVALID")
		for field in ["gender", "appearanceId", "desire", "personality", "speech"]:
			if String(attributes.get(field, "")).strip_edges().is_empty():
				var code := "RESIDENT_EDITOR_%s_REQUIRED" % String(field).to_upper()
				_add_field_issue(field_issues, "attributes.%s" % field, code)
				slot_codes.append(code)
		var interest_error := INTERESTS.profile_validation_error(
			attributes.get("interests", []),
			attributes.get("customInterests", []),
		)
		if not interest_error.is_empty():
			_add_field_issue(
				field_issues,
				"attributes.interests",
				interest_error,
			)
			slot_codes.append(interest_error)
		var home_space_id := String(entry.get("homeSpaceId", ""))
		if not _home_by_space.has(home_space_id):
			_add_field_issue(field_issues, "social.homeSpaceId", "RESIDENT_EDITOR_HOME_UNKNOWN")
			slot_codes.append("RESIDENT_EDITOR_HOME_UNKNOWN")
		elif seen_homes.has(home_space_id):
			_add_field_issue(field_issues, "social.homeSpaceId", "RESIDENT_EDITOR_HOME_DUPLICATED")
			slot_codes.append("RESIDENT_EDITOR_HOME_DUPLICATED")
		else:
			seen_homes[home_space_id] = slot_id
		if not _occupation_by_id.has(String(occupation.get("id", ""))):
			_add_field_issue(field_issues, "social.occupationId", "RESIDENT_EDITOR_OCCUPATION_UNKNOWN")
			slot_codes.append("RESIDENT_EDITOR_OCCUPATION_UNKNOWN")
		if not _workplace_by_id.has(String(occupation.get("workplaceId", ""))):
			_add_field_issue(field_issues, "social.workplaceId", "RESIDENT_EDITOR_WORKPLACE_UNKNOWN")
			slot_codes.append("RESIDENT_EDITOR_WORKPLACE_UNKNOWN")
		issues_by_slot[slot_id] = slot_codes
		field_issues_by_slot[slot_id] = field_issues
		valid_slots[slot_id] = slot_codes.is_empty()
		for code in slot_codes:
			issues.append({
				"code": code,
				"slotId": slot_id,
				"message": "居民槽位资料不完整。",
			})
	var completed_count := 0
	for slot_valid in valid_slots.values():
		if bool(slot_valid):
			completed_count += 1
	return {
		"status": "valid" if issues.is_empty() and entries.size() == SLOT_COUNT else "invalid",
		"issues": issues,
		"issuesBySlot": issues_by_slot,
		"validSlots": valid_slots,
		"completedSlotCount": completed_count,
		"selectedFieldIssues": (
			field_issues_by_slot.get(_selected_slot_id, {}) as Dictionary
		).duplicate(true),
	}


func _build_options() -> void:
	_occupation_options.clear()
	_occupation_by_id.clear()
	_appearance_options.clear()
	_appearance_by_id.clear()
	_home_options.clear()
	_home_by_space.clear()
	_workplace_options.clear()
	_workplace_by_id.clear()
	_gender_options.clear()
	for resident_value in _catalog.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		var attributes := resident.get("attributes", {}) as Dictionary
		var gender := String(attributes.get("gender", ""))
		if not gender.is_empty() and not _option_has_id(_gender_options, gender):
			_gender_options.append({"id": gender, "label": gender})
		var appearance_id := String(attributes.get("appearance", ""))
		if not appearance_id.is_empty() and not _appearance_by_id.has(appearance_id):
			var presentation := resident.get("presentation", {}) as Dictionary
			var portrait_ref := String(
				presentation.get(
					"portraitPath",
					presentation.get("spritePath", ""),
				)
			)
			var appearance := {
				"id": appearance_id,
				"label": appearance_id,
				"formalReady": ResourceLoader.exists(portrait_ref),
				"status": "formal",
				"portraitRef": portrait_ref,
			}
			_appearance_options.append(appearance)
			_appearance_by_id[appearance_id] = appearance
	for place_value in _world_data.get("places", []) as Array:
		var place := place_value as Dictionary
		var place_name := String(place.get("name", ""))
		var capabilities := place.get("capabilities", {}) as Dictionary
		if String(place.get("type", "")) == "住家":
			var home := {
				"spaceId": String(place.get("spaceId", "")),
				"label": place_name,
			}
			_home_options.append(home)
			_home_by_space[String(home.get("spaceId", ""))] = home
		if bool(capabilities.get("assignableWorkplace", false)):
			var workplace := {
				"id": place_name,
				"label": place_name,
				"occupancyMode": "shared",
			}
			_workplace_options.append(workplace)
			_workplace_by_id[place_name] = workplace
	for occupation_value: Variant in _world_data.get(
		"occupations",
		[],
	) as Array:
		if not occupation_value is Dictionary:
			continue
		var source := occupation_value as Dictionary
		var occupation_id := String(
			source.get("occupationId", ""),
		)
		var occupation_label := String(source.get("label", ""))
		var workplace_label := String(
			source.get("primaryWorkplacePlace", ""),
		)
		if (
			occupation_id.is_empty()
			or occupation_label.is_empty()
			or not _workplace_by_id.has(workplace_label)
		):
			continue
		var option := {
			"id": occupation_id,
			"label": occupation_label,
			"workplaceMode": String(
				source.get("workplaceMode", ""),
			),
			"workplaceIds": [workplace_label],
			"workplaceId": workplace_label,
			"workplaceLabel": workplace_label,
			"relatedWorkplaceIds": (
				source.get(
					"relatedWorkplacePlaces",
					[],
				) as Array
			).duplicate(),
			"dynamicWorkTargetRules": (
				source.get(
					"dynamicWorkTargetRules",
					[],
				) as Array
			).duplicate(),
			"fixedWorkAreaIds": (
				source.get(
					"fixedWorkAreaIds",
					[],
				) as Array
			).duplicate(),
		}
		_occupation_options.append(option)
		_occupation_by_id[occupation_id] = option
	_home_options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("spaceId", "")) < String(right.get("spaceId", ""))
	)
	_occupation_options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("label", "")) < String(right.get("label", ""))
	)
	_workplace_options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("label", "")) < String(right.get("label", ""))
	)


func _entry_from_sources(index: int, binding: Dictionary, resident: Dictionary) -> Dictionary:
	var attributes := resident.get("attributes", {}) as Dictionary
	var occupation_source := resident.get("occupation", {}) as Dictionary
	var occupation_id := _occupation_id(String(occupation_source.get("name", "")))
	var occupation := (
		_occupation_by_id.get(occupation_id, {}) as Dictionary
	).duplicate(true)
	return {
		"slotId": "resident_slot_%02d" % (index + 1),
		"ordinal": index + 1,
		"residentId": String(binding.get("residentId", "")),
		"homeSpaceId": String(binding.get("spaceId", "")),
		"llmBinding": (binding.get("llmBinding", {}) as Dictionary).duplicate(true),
		"attributes": {
			"name": String(attributes.get("name", "")),
			"gender": String(attributes.get("gender", "")),
			"age": int(attributes.get("age", 0)),
			"appearanceId": String(attributes.get("appearance", "")),
			"desire": String(attributes.get("desire", "")),
			"personality": String(attributes.get("personality", "")),
			"speech": String(attributes.get("speech", "")),
			"interests": INTERESTS.normalize(
				attributes.get("interests", []),
			),
			"customInterests": INTERESTS.normalize_custom(
				attributes.get("customInterests", []),
			),
		},
		"occupation": occupation,
	}


func _build_catalog(entries: Array[Dictionary]) -> Dictionary:
	var result := _catalog.duplicate(true)
	var entries_by_id: Dictionary = {}
	for entry in entries:
		entries_by_id[String(entry.get("residentId", ""))] = entry
	var residents := result.get("residents", []) as Array
	for index in residents.size():
		var resident := (residents[index] as Dictionary).duplicate(true)
		var resident_id := String(resident.get("residentId", ""))
		if not entries_by_id.has(resident_id):
			continue
		var entry := entries_by_id[resident_id] as Dictionary
		var attributes := entry.get("attributes", {}) as Dictionary
		resident["attributes"] = {
			"name": String(attributes.get("name", "")),
			"gender": String(attributes.get("gender", "")),
			"age": int(attributes.get("age", 0)),
			"appearance": String(attributes.get("appearanceId", "")),
			"desire": String(attributes.get("desire", "")),
			"personality": String(attributes.get("personality", "")),
			"speech": String(attributes.get("speech", "")),
			"interests": INTERESTS.normalize(
				attributes.get("interests", []),
			),
			"customInterests": INTERESTS.normalize_custom(
				attributes.get("customInterests", []),
			),
		}
		var occupation := entry.get("occupation", {}) as Dictionary
		var occupation_payload := {
			"name": String(occupation.get("label", "")),
			"workplacePlace": String(occupation.get("workplaceLabel", "")),
		}
		resident["occupation"] = occupation_payload
		residents[index] = resident
	result["residents"] = residents
	return result


func _build_draft(entries: Array[Dictionary]) -> Dictionary:
	var slots: Array[Dictionary] = []
	for entry in entries:
		slots.append({
			"residentId": String(entry.get("residentId", "")),
			"spaceId": String(entry.get("homeSpaceId", "")),
			"llmBinding": (
				entry.get("llmBinding", {}) as Dictionary
			).duplicate(true),
		})
	return {
		"schemaVersion": int(_draft.get("schemaVersion", 1)),
		"sourceScope": String(_draft.get("sourceScope", "resident_selection")),
		"draftRevision": _revision,
		"slots": slots,
	}


func _home_option_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for home in _home_options:
		var option := home.duplicate(true)
		var assigned_slot_id := ""
		for entry in _entries:
			if String(entry.get("homeSpaceId", "")) == String(home.get("spaceId", "")):
				assigned_slot_id = String(entry.get("slotId", ""))
				break
		option["assignedSlotId"] = assigned_slot_id
		option["available"] = assigned_slot_id.is_empty() or assigned_slot_id == _selected_slot_id
		result.append(option)
	return result


func _workplace_option_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for workplace in _workplace_options:
		var option := workplace.duplicate(true)
		var assigned: Array[String] = []
		for entry in _entries:
			if String((entry.get("occupation", {}) as Dictionary).get("workplaceId", "")) == String(workplace.get("id", "")):
				assigned.append(String(entry.get("slotId", "")))
		option["assignedSlotIds"] = assigned
		result.append(option)
	return result


func _disabled_view_model() -> Dictionary:
	var slots: Array[Dictionary] = []
	for index in SLOT_COUNT:
		slots.append({
			"slotId": "resident_slot_%02d" % (index + 1),
			"ordinal": index + 1,
			"displayName": "",
			"homeSpaceId": "",
			"homeLabel": "",
			"occupationLabel": "",
			"workplaceLabel": "",
			"validationStatus": "unavailable",
			"issueCodes": [_configuration_error],
		})
	var data := {
		"capabilityMode": "formal",
		"source": "runtime",
		"formalReady": false,
		"draftId": "",
		"flowMode": "new_game",
		"selectedSlotId": "resident_slot_01",
		"slotCount": SLOT_COUNT,
		"completedSlotCount": 0,
		"invalidSlotCount": SLOT_COUNT,
		"dirty": false,
		"slots": slots,
		"editor": {
			"slotId": "resident_slot_01",
			"residentId": "",
			"attributes": {
				"name": "", "gender": "", "age": 0,
				"appearanceId": "", "appearanceLabel": "",
				"appearanceStatus": "unavailable", "portraitRef": "",
				"desire": "", "personality": "", "speech": "",
				"interests": [],
				"customInterests": [],
			},
			"social": {
				"homeSpaceId": "", "homeLabel": "", "occupationId": "",
				"occupationLabel": "", "workplaceMode": "",
				"workplaceId": "", "workplaceLabel": "",
			},
		},
		"options": {
			"genders": [], "age": {"min": 1, "max": 120, "step": 1},
			"interests": [],
			"maxInterests": INTERESTS.max_interests(),
			"appearanceStatus": "unavailable", "appearances": [],
			"homeSpaces": [], "occupations": [], "workplaces": [],
		},
		"validation": {
			"status": "unavailable",
			"summaryLabel": "正式居民草稿尚未绑定",
			"issues": [{"code": _configuration_error, "message": "正式居民草稿尚未绑定。"}],
			"fieldIssues": {},
		},
		"copyProfile": "regular",
	}
	var actions := {}
	for intent in INTENT_TO_ACTION:
		actions[INTENT_TO_ACTION[intent]] = _action(
			String(intent),
			false,
			_configuration_error,
		)
	return {
		"scope": SCOPE,
		"status": "disabled",
		"revision": _revision,
		"data": data,
		"actions": actions,
		"operation": _operation.duplicate(true),
		"error": {
			"kind": "unavailable",
			"code": _configuration_error,
			"retryable": false,
			"message": "正式居民草稿尚未绑定。",
			"details": [],
		},
	}


func _entry_by_slot(slot_id: String) -> Dictionary:
	var index := _entry_index(slot_id)
	return _entries[index] as Dictionary if index >= 0 else {}


func _entry_index(slot_id: String) -> int:
	for index in _entries.size():
		if String(_entries[index].get("slotId", "")) == slot_id:
			return index
	return -1


func _residents_by_id(catalog: Dictionary) -> Dictionary:
	var result := {}
	for value in catalog.get("residents", []) as Array:
		var resident := value as Dictionary
		result[String(resident.get("residentId", ""))] = resident
	return result


func _home_label(space_id: String) -> String:
	return String((_home_by_space.get(space_id, {}) as Dictionary).get("label", space_id))


func _occupation_id(label: String) -> String:
	for occupation_id_value: Variant in _occupation_by_id:
		var occupation_id := String(occupation_id_value)
		var occupation := _occupation_by_id.get(
			occupation_id,
			{},
		) as Dictionary
		if String(occupation.get("label", "")) == label:
			return occupation_id
	return ""


func _option_has_id(options: Array[Dictionary], option_id: String) -> bool:
	for option in options:
		if String(option.get("id", "")) == option_id:
			return true
	return false


func _copy_profile(attributes: Dictionary) -> String:
	var length := 0
	for field in ["desire", "personality", "speech"]:
		length += String(attributes.get(field, "")).length()
	return "expanded_130" if length > 130 else "regular"


func _add_field_issue(field_issues: Dictionary, field: String, code: String) -> void:
	var values := field_issues.get(field, []) as Array
	values.append(code)
	field_issues[field] = values


func _action(intent: String, enabled: bool, disabled_reason: String) -> Dictionary:
	return AiTownUiViewModel.make_action(intent, enabled, disabled_reason)


func _configuration_failure(error_code: String, errors: Array = []) -> Dictionary:
	_configuration_error = error_code
	_revision = 1
	_operation = _idle_operation()
	_error = {
		"kind": "unavailable",
		"code": error_code,
		"retryable": false,
		"message": "正式居民 catalog 或 session draft 尚未就绪。",
		"details": errors.duplicate(true),
	}
	_emit_view_model()
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"errors": errors.duplicate(true),
	}


func _failure(
	error_code: String,
	retryable := false,
	errors: Array = [],
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"errors": errors.duplicate(true),
		"changed": false,
	}


func _success(changed: bool) -> Dictionary:
	return RESULT_SHAPES.success_changed(changed)


func _dispatch_result(
	ok: bool,
	accepted: bool,
	request_id: String,
	error_code: String,
	retryable: bool,
	changed := false,
) -> Dictionary:
	return {
		"ok": ok,
		"accepted": accepted,
		"requestId": request_id,
		"errorCode": error_code,
		"retryable": retryable,
		"changed": changed,
		"revision": _revision,
	}


func _emit_view_model() -> void:
	view_model_changed.emit(SCOPE, get_view_model())


func _next_request_id() -> String:
	_request_sequence += 1
	return AiTownUiViewModel.request_id("resident-editor", _request_sequence)


func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


func _reset() -> void:
	_catalog.clear()
	_world_data.clear()
	_draft.clear()
	_entries.clear()
	_defaults_by_slot.clear()
	_selected_slot_id = ""
	_draft_id = ""
	_configured = false
	_dirty = false
	_revision = 0
	_operation = _idle_operation()
	_error = null
	_configuration_error = "RESIDENT_EDITOR_SERVICE_NOT_CONFIGURED"
	_saved_catalog.clear()
	_saved_draft.clear()
