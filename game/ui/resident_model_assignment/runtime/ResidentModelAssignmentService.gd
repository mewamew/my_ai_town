class_name ResidentModelAssignmentService
extends RefCounted


signal view_model_changed(scope: String, view_model: Dictionary)
signal operation_completed(scope: String, operation: Dictionary)
signal draft_applied(draft: Dictionary, revision: int)
signal back_requested(draft: Dictionary, revision: int)


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const UI_VIEW_MODEL := preload(
	"res://ui/common/AiTownUiViewModel.gd"
)
const SCOPE := "resident_model_assignment"
const SLOT_COUNT := 15
const DRAFT_SCHEMA_VERSION := 1
const DRAFT_SOURCE_SCOPE := "resident_selection"
const DRAFT_CONTRACT := preload("res://world/presentation/session/TownNewGameDraft.gd")
const REQUIRED_PROVIDER_METHODS: Array[String] = [
	"get_health_snapshot",
	"list_available_models",
	"validate_resident_bindings",
]
const CUSTOM_MODEL_PROVIDER_IDS := [
	"openai-compatible",
	"302-ai",
	"ollama",
	"ollama-cloud",
	"lm-studio",
]
const INTENT_TO_ACTION := {
	"resident_model_assignment.select_resident": "selectResident",
	"resident_model_assignment.set_filter": "setFilter",
	"resident_model_assignment.set_mode": "setMode",
	"resident_model_assignment.select_batch_resident": "selectBatchResident",
	"resident_model_assignment.select_all_batch": "selectAllBatch",
	"resident_model_assignment.select_invalid": "selectInvalid",
	"resident_model_assignment.select_unassigned": "selectUnassigned",
	"resident_model_assignment.clear_batch_selection": "clearBatchSelection",
	"resident_model_assignment.select_provider": "selectProvider",
	"resident_model_assignment.select_model": "selectModel",
	"resident_model_assignment.assign_one": "assignOne",
	"resident_model_assignment.assign_batch": "assignBatch",
	"resident_model_assignment.apply_draft": "applyDraft",
	"resident_model_assignment.refresh": "refresh",
	"resident_model_assignment.back": "back",
}


var _provider_service: Object
var _catalog: Dictionary = {}
var _draft: Dictionary = {}
var _committed_draft: Dictionary = {}
var _configured := false
var _revision := 0
var _request_sequence := 0
var _selected_resident_id := ""
var _selected_provider_id := ""
var _selected_model_id := ""
var _mode := "single"
var _filter := "all"
var _batch_selection: Array[String] = []
var _health: Dictionary = {}
var _models: Array[Dictionary] = []
var _operation := _idle_operation()
var _error: Variant = null
var _apply_handler := Callable()
var _single_resident_mode := false
var _slot_count := SLOT_COUNT
var _allowed_space_ids: Array[String] = []


func configure(
	provider_service: Object,
	resident_catalog: Dictionary,
	session_draft: Dictionary,
	context: Dictionary = {},
) -> Dictionary:
	_reset()
	_single_resident_mode = bool(context.get("singleResidentMode", false))
	_slot_count = 1 if _single_resident_mode else SLOT_COUNT
	if _single_resident_mode:
		for value: Variant in context.get("allowedSpaceIds", []) as Array:
			var space_id := String(value).strip_edges()
			if not space_id.is_empty() and not _allowed_space_ids.has(space_id):
				_allowed_space_ids.append(space_id)
	if provider_service == null:
		return _configuration_failure("RESIDENT_MODEL_PROVIDER_SERVICE_NOT_BOUND")
	var missing_methods: Array[String] = []
	for method in REQUIRED_PROVIDER_METHODS:
		if not provider_service.has_method(method):
			missing_methods.append(method)
	if not missing_methods.is_empty():
		return _configuration_failure("RESIDENT_MODEL_PROVIDER_CONTRACT_INVALID")
	var catalog_result := _validate_catalog(resident_catalog)
	if not bool(catalog_result.get("ok", false)):
		return _configuration_failure(String(catalog_result.get("errorCode", "RESIDENT_MODEL_CATALOG_INVALID")))
	_catalog = resident_catalog.duplicate(true)
	var draft_result := _validate_initial_draft(session_draft)
	if not bool(draft_result.get("ok", false)):
		return _configuration_failure(String(draft_result.get("errorCode", "SESSION_DRAFT_INVALID")))

	_provider_service = provider_service
	var apply_handler_value: Variant = context.get("applyHandler")
	if apply_handler_value != null:
		if typeof(apply_handler_value) != TYPE_CALLABLE:
			return _configuration_failure(
				"RESIDENT_MODEL_ASSIGNMENT_APPLY_HANDLER_INVALID"
			)
		_apply_handler = apply_handler_value as Callable
	_draft = _normalize_initial_draft(session_draft)
	_committed_draft = _draft.duplicate(true)
	_selected_resident_id = String(context.get("selectedResidentId", ""))
	if _slot_index(_selected_resident_id) < 0:
		_selected_resident_id = String(((_draft.get("slots", []) as Array)[0] as Dictionary).get("residentId", ""))
	_revision = maxi(
		int(context.get("revision", _draft.get("draftRevision", 1))),
		1,
	)
	_configured = true
	var refreshed := _refresh_public_catalog()
	var provider_ready := bool(refreshed.get("ok", false))
	if provider_ready:
		_error = null
	else:
		var provider_error := String(refreshed.get("errorCode", "PROVIDER_CATALOG_UNAVAILABLE"))
		var provider_retryable := bool(refreshed.get("retryable", false))
		_error = _error_payload(provider_error, provider_retryable)
		_operation = _operation_payload(
			"",
			"resident_model_assignment.refresh",
			"error" if provider_retryable else "rejected",
		)
	_emit_view_model()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"revision": _revision,
		"residentCount": _slot_count,
		"providerReady": provider_ready,
		"providerErrorCode": String(refreshed.get("errorCode", "")),
	}


func get_view_model(scope: String = SCOPE) -> Dictionary:
	if scope != SCOPE:
		return _unknown_scope_view_model(scope)
	if not _configured:
		return _disabled_view_model()
	return _build_view_model()


func get_session_draft() -> Dictionary:
	return _draft.duplicate(true)


func get_committed_draft() -> Dictionary:
	return _committed_draft.duplicate(true)


func dispatch(intent: Variant, payload: Dictionary = {}) -> Dictionary:
	var intent_id := String(intent)
	var action_key := String(INTENT_TO_ACTION.get(intent_id, ""))
	var request_id := _next_request_id()
	if action_key.is_empty():
		return _dispatch_result(false, false, request_id, "UNKNOWN_RESIDENT_MODEL_ASSIGNMENT_INTENT", false)
	if not _configured:
		return _dispatch_result(false, false, request_id, "RESIDENT_MODEL_ASSIGNMENT_NOT_CONFIGURED", false)
	if int(payload.get("revision", -1)) != _revision:
		return _publish_rejected(request_id, intent_id, "RESIDENT_MODEL_ASSIGNMENT_REVISION_STALE")
	var action := (_actions_snapshot().get(action_key, {}) as Dictionary)
	if not bool(action.get("enabled", false)):
		return _publish_rejected(
			request_id,
			intent_id,
			String(action.get("disabledReason", "RESIDENT_MODEL_ASSIGNMENT_ACTION_DISABLED")),
		)

	_operation = _operation_payload(request_id, intent_id, "loading")
	_error = null
	_revision += 1
	_emit_view_model()
	var normalized := payload.duplicate(true)
	normalized["revision"] = _revision
	var result := _execute_intent(intent_id, normalized)
	return _finish_operation(request_id, intent_id, result)


func _execute_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"resident_model_assignment.select_resident":
			return _select_resident(String(payload.get("residentId", "")))
		"resident_model_assignment.set_filter":
			return _set_filter(String(payload.get("filter", "")))
		"resident_model_assignment.set_mode":
			return _set_mode(String(payload.get("mode", "")))
		"resident_model_assignment.select_batch_resident":
			return _select_batch_resident(
				String(payload.get("residentId", "")),
				bool(payload.get("selected", true)),
			)
		"resident_model_assignment.select_all_batch":
			return _select_all_batch()
		"resident_model_assignment.select_invalid":
			return _select_by_status("invalid")
		"resident_model_assignment.select_unassigned":
			return _select_by_status("unassigned")
		"resident_model_assignment.clear_batch_selection":
			return _clear_batch_selection()
		"resident_model_assignment.select_provider":
			return _select_provider(String(payload.get("providerId", "")))
		"resident_model_assignment.select_model":
			return _select_model(
				String(payload.get("providerId", "")),
				String(payload.get("modelId", "")),
			)
		"resident_model_assignment.assign_one":
			return _assign_one(payload)
		"resident_model_assignment.assign_batch":
			return _assign_batch(payload)
		"resident_model_assignment.apply_draft":
			return _apply_draft()
		"resident_model_assignment.refresh":
			return _refresh_public_catalog()
		"resident_model_assignment.back":
			return _request_back()
	return _failure("UNKNOWN_RESIDENT_MODEL_ASSIGNMENT_INTENT")


func _select_resident(resident_id: String) -> Dictionary:
	if _slot_index(resident_id) < 0:
		return _failure("RESIDENT_MODEL_ASSIGNMENT_RESIDENT_UNKNOWN")
	var changed := resident_id != _selected_resident_id
	_selected_resident_id = resident_id
	return _success(changed)


func _set_filter(value: String) -> Dictionary:
	if not ["all", "invalid", "unassigned"].has(value):
		return _failure("RESIDENT_MODEL_ASSIGNMENT_FILTER_INVALID")
	var changed := _filter != value
	_filter = value
	return _success(changed)


func _set_mode(value: String) -> Dictionary:
	if not ["single", "batch"].has(value):
		return _failure("RESIDENT_MODEL_ASSIGNMENT_MODE_INVALID")
	var changed := _mode != value
	_mode = value
	if _mode == "single" and not _batch_selection.is_empty():
		_batch_selection.clear()
		changed = true
	return _success(changed)


func _select_batch_resident(resident_id: String, selected: bool) -> Dictionary:
	if _mode != "batch" or _slot_index(resident_id) < 0:
		return _failure("RESIDENT_MODEL_ASSIGNMENT_BATCH_RESIDENT_INVALID")
	var changed := false
	if selected and not _batch_selection.has(resident_id):
		_batch_selection.append(resident_id)
		_selected_resident_id = resident_id
		changed = true
	elif not selected and _batch_selection.has(resident_id):
		_batch_selection.erase(resident_id)
		if _selected_resident_id == resident_id and not _batch_selection.is_empty():
			_selected_resident_id = _batch_selection[0]
		changed = true
	return _success(changed)


func _select_all_batch() -> Dictionary:
	if _mode != "batch":
		return _failure("RESIDENT_MODEL_ASSIGNMENT_BATCH_MODE_REQUIRED")
	var selected: Array[String] = []
	for resident in _resident_snapshots():
		selected.append(String(resident.get("residentId", "")))
	var changed := selected != _batch_selection
	_batch_selection = selected
	if not selected.is_empty():
		_selected_resident_id = selected[0]
	return _success(changed)


func _select_by_status(status: String) -> Dictionary:
	if _mode != "batch":
		return _failure("RESIDENT_MODEL_ASSIGNMENT_BATCH_MODE_REQUIRED")
	var selected: Array[String] = []
	for resident in _resident_snapshots():
		if String(resident.get("bindingStatus", "")) == status:
			selected.append(String(resident.get("residentId", "")))
	var changed := selected != _batch_selection
	_batch_selection = selected
	if not selected.is_empty():
		_selected_resident_id = selected[0]
	return _success(changed)


func _clear_batch_selection() -> Dictionary:
	var changed := not _batch_selection.is_empty()
	_batch_selection.clear()
	return _success(changed)


func _select_provider(provider_id: String) -> Dictionary:
	var provider := _provider_snapshot(provider_id)
	if provider.is_empty():
		return _failure("RESIDENT_MODEL_ASSIGNMENT_PROVIDER_UNKNOWN")
	var first_available := _first_available_model(provider_id)
	if first_available.is_empty():
		return _failure(_provider_model_readiness_reason(provider_id))
	var changed := _selected_provider_id != provider_id
	_selected_provider_id = provider_id
	var target_model := String(first_available.get("modelId", ""))
	if _selected_model_id != target_model:
		_selected_model_id = target_model
		changed = true
	return _success(changed)


func _select_model(provider_id: String, model_id: String) -> Dictionary:
	var model := _model_snapshot(provider_id, model_id)
	if model.is_empty():
		return _failure("RESIDENT_MODEL_ASSIGNMENT_MODEL_UNKNOWN")
	var validation := _validate_target_binding({
		"mode": "model",
		"providerId": provider_id,
		"modelId": model_id,
	})
	if not bool(validation.get("ok", false)):
		return validation
	var changed := _selected_provider_id != provider_id or _selected_model_id != model_id
	_selected_provider_id = provider_id
	_selected_model_id = model_id
	return _success(changed)


func _assign_one(payload: Dictionary) -> Dictionary:
	var resident_id := String(payload.get("residentId", ""))
	var binding_value: Variant = payload.get("llmBinding", {})
	if not binding_value is Dictionary:
		return _failure("SESSION_LLM_BINDING_INVALID")
	var binding := binding_value as Dictionary
	var validation := _validate_target_binding(binding)
	if not bool(validation.get("ok", false)):
		return validation
	var index := _slot_index(resident_id)
	if index < 0:
		return _failure("RESIDENT_MODEL_ASSIGNMENT_RESIDENT_UNKNOWN")
	var slots := (_draft.get("slots", []) as Array).duplicate(true)
	var slot := (slots[index] as Dictionary).duplicate(true)
	var normalized := _normalized_binding(binding)
	var changed := (slot.get("llmBinding", {}) as Dictionary) != normalized
	slot["llmBinding"] = normalized
	slots[index] = slot
	_draft["slots"] = slots
	_draft["draftRevision"] = int(_draft.get("draftRevision", 1)) + (1 if changed else 0)
	return _success(changed)


func _assign_batch(payload: Dictionary) -> Dictionary:
	var ids_value: Variant = payload.get("residentIds", [])
	var binding_value: Variant = payload.get("llmBinding", {})
	if not ids_value is Array or not binding_value is Dictionary:
		return _failure("RESIDENT_MODEL_ASSIGNMENT_BATCH_PAYLOAD_INVALID")
	var resident_ids: Array = ids_value
	if resident_ids.is_empty():
		return _failure("RESIDENT_MODEL_ASSIGNMENT_BATCH_EMPTY")
	var binding := binding_value as Dictionary
	var validation := _validate_target_binding(binding)
	if not bool(validation.get("ok", false)):
		return validation
	var normalized := _normalized_binding(binding)
	var slots := (_draft.get("slots", []) as Array).duplicate(true)
	var changed := false
	for resident_id_value: Variant in resident_ids:
		var resident_id := String(resident_id_value)
		var index := _slot_index(resident_id)
		if index < 0:
			return _failure("RESIDENT_MODEL_ASSIGNMENT_RESIDENT_UNKNOWN")
		var slot := (slots[index] as Dictionary).duplicate(true)
		if (slot.get("llmBinding", {}) as Dictionary) != normalized:
			slot["llmBinding"] = normalized.duplicate(true)
			slots[index] = slot
			changed = true
	_draft["slots"] = slots
	_draft["draftRevision"] = int(_draft.get("draftRevision", 1)) + (1 if changed else 0)
	return _success(changed)


func _apply_draft() -> Dictionary:
	var strict_validation := (
		_validate_initial_draft(_draft)
		if _single_resident_mode
		else DRAFT_CONTRACT.validate(_draft) as Dictionary
	)
	if not bool(strict_validation.get("ok", false)):
		return _failure("SESSION_DRAFT_INVALID", false, strict_validation.get("errors", []) as Array)
	var bindings: Array[Dictionary] = []
	for slot_value: Variant in _draft.get("slots", []) as Array:
		var slot := slot_value as Dictionary
		bindings.append({
			"residentId": String(slot.get("residentId", "")),
			"llmBinding": (slot.get("llmBinding", {}) as Dictionary).duplicate(true),
		})
	var provider_validation := _provider_service.call("validate_resident_bindings", bindings) as Dictionary
	if not bool(provider_validation.get("ok", false)):
		return _failure(
			String(provider_validation.get("errorCode", "SESSION_LLM_BINDINGS_INVALID")),
			bool(provider_validation.get("retryable", false)),
			provider_validation.get("errors", []) as Array,
		)
	if _apply_handler.is_valid():
		var external_result_value: Variant = _apply_handler.call(
			_draft.duplicate(true),
			bindings.duplicate(true),
		)
		if not external_result_value is Dictionary:
			return _failure(
				"RESIDENT_MODEL_ASSIGNMENT_APPLY_RESULT_INVALID",
				false,
			)
		var external_result := external_result_value as Dictionary
		if not bool(external_result.get("ok", false)):
			return _failure(
				String(external_result.get(
					"errorCode",
					"RESIDENT_MODEL_ASSIGNMENT_APPLY_FAILED",
				)),
				bool(external_result.get("retryable", false)),
				external_result.get("errors", []) as Array,
			)
	_committed_draft = _draft.duplicate(true)
	return _success(true)


func _request_back() -> Dictionary:
	# The current working draft is preserved and emitted after the operation's
	# final revision is published.
	return _success(false)


func _refresh_public_catalog() -> Dictionary:
	var health_value: Variant = _provider_service.call("get_health_snapshot")
	if not health_value is Dictionary:
		return _invalidate_provider_catalog("PROVIDER_HEALTH_SNAPSHOT_INVALID", false)
	var health := (health_value as Dictionary).duplicate(true)
	if not bool(health.get("ok", false)):
		return _invalidate_provider_catalog(
			String(health.get("errorCode", "PROVIDER_HEALTH_QUERY_FAILED")),
			bool(health.get("retryable", false)),
			health,
		)
	if (
		String(health.get("capabilityMode", "")) != "formal"
		or String(health.get("source", "")) != "runtime"
	):
		return _invalidate_provider_catalog(
			"PROVIDER_FORMAL_RUNTIME_REQUIRED",
			false,
			health,
		)
	var providers_value: Variant = health.get("providers", [])
	if not providers_value is Array:
		return _invalidate_provider_catalog("PROVIDER_HEALTH_CATALOG_INVALID", false, health)
	var provider_ids: Dictionary = {}
	for provider_value: Variant in providers_value as Array:
		if not provider_value is Dictionary:
			return _invalidate_provider_catalog("PROVIDER_HEALTH_CATALOG_INVALID", false, health)
		var provider_id := String((provider_value as Dictionary).get("providerId", "")).strip_edges()
		if provider_id.is_empty():
			return _invalidate_provider_catalog("PROVIDER_HEALTH_CATALOG_INVALID", false, health)
		if provider_ids.has(provider_id):
			return _invalidate_provider_catalog("PROVIDER_HEALTH_CATALOG_DUPLICATED", false, health)
		provider_ids[provider_id] = true
	var model_value: Variant = _provider_service.call("list_available_models")
	if not model_value is Array:
		return _invalidate_provider_catalog("PROVIDER_MODEL_CATALOG_INVALID", false, health)
	var normalized_models: Array[Dictionary] = []
	var model_keys: Dictionary = {}
	for value: Variant in model_value as Array:
		if not value is Dictionary:
			return _invalidate_provider_catalog("PROVIDER_MODEL_CATALOG_INVALID", false, health)
		var source := value as Dictionary
		var provider_id := String(source.get("providerId", source.get("provider_id", ""))).strip_edges()
		var model_id := String(source.get("modelId", source.get("id", ""))).strip_edges()
		if provider_id.is_empty() or model_id.is_empty() or not provider_ids.has(provider_id):
			return _invalidate_provider_catalog("PROVIDER_MODEL_CATALOG_INVALID", false, health)
		var model_key := "%s\n%s" % [provider_id, model_id]
		if model_keys.has(model_key):
			return _invalidate_provider_catalog("PROVIDER_MODEL_CATALOG_DUPLICATED", false, health)
		model_keys[model_key] = true
		normalized_models.append({
			"providerId": provider_id,
			"modelId": model_id,
			"displayName": String(source.get("label", model_id)),
			"available": bool(source.get("available", false)),
			"errorCode": String(source.get("errorCode", "")),
			"retryable": bool(source.get("retryable", false)),
			"capabilities": (source.get("capabilities", []) as Array).duplicate(),
		})
	_health = health
	_models = normalized_models
	_choose_available_target()
	return {"ok": true, "errorCode": "", "retryable": false, "changed": true}


func _invalidate_provider_catalog(
	error_code: String,
	retryable: bool,
	health_hint: Dictionary = {},
) -> Dictionary:
	var provider_sources_value: Variant = health_hint.get(
		"providers",
		_health.get("providers", []),
	)
	var unavailable_providers: Array[Dictionary] = []
	var seen: Dictionary = {}
	if provider_sources_value is Array:
		for value: Variant in provider_sources_value as Array:
			if not value is Dictionary:
				continue
			var source := value as Dictionary
			var provider_id := String(source.get("providerId", "")).strip_edges()
			if provider_id.is_empty() or seen.has(provider_id):
				continue
			seen[provider_id] = true
			unavailable_providers.append({
				"providerId": provider_id,
				"label": String(source.get("label", provider_id)),
				"status": "unavailable",
				"errorCode": error_code,
				"retryable": retryable,
			})
	_health = {
		"ok": false,
		"status": "unavailable",
		"capabilityMode": "formal",
		"source": "runtime",
		"formalReady": false,
		"errorCode": error_code,
		"retryable": retryable,
		"providers": unavailable_providers,
	}
	_models.clear()
	_selected_provider_id = ""
	_selected_model_id = ""
	return _failure(error_code, retryable)


func _build_view_model() -> Dictionary:
	var resident_rows := _resident_snapshots()
	var counts := _status_counts(resident_rows)
	var operation_status := String(_operation.get("status", "idle"))
	var status := "ready"
	if operation_status == "loading":
		status = "loading"
	elif operation_status == "error":
		status = "error"
	elif operation_status == "rejected":
		status = "rejected"
	return {
		"scope": SCOPE,
		"status": status,
		"revision": _revision,
		"data": {
			"capabilityMode": String(_health.get("capabilityMode", "formal")),
			"source": String(_health.get("source", "runtime")),
			"formalReady": _formal_ready(),
			"draftRevision": int(_draft.get("draftRevision", 1)),
			"residentCount": resident_rows.size(),
			"completedCount": int(counts.get("valid", 0)),
			"invalidCount": int(counts.get("invalid", 0)),
			"unassignedCount": int(counts.get("unassigned", 0)),
			"dirty": _draft != _committed_draft,
			"mode": _mode,
			"filter": _filter,
			"selectedResidentId": _selected_resident_id,
			"selectedProviderId": _selected_provider_id,
			"selectedModelId": _selected_model_id,
			"selectedBatchResidentIds": _batch_selection.duplicate(),
			"residents": resident_rows,
			"providers": _provider_snapshots(),
			"targetBinding": _target_binding(),
			"selectedResident": _resident_snapshot(_selected_resident_id),
		},
		"actions": _actions_snapshot(),
		"operation": _operation.duplicate(true),
		"error": null if _error == null else (_error as Dictionary).duplicate(true),
	}


func _actions_snapshot() -> Dictionary:
	var configured := _configured
	var target_validation := _validate_target_binding(_target_binding())
	var target_available := bool(target_validation.get("ok", false))
	var rows := _resident_snapshots() if configured else []
	var counts := _status_counts(rows)
	var complete := int(counts.get("valid", 0)) == _slot_count
	var provider_ready := _formal_ready()
	var provider_reason := (
		""
		if target_available
		else (
			_provider_readiness_reason()
			if not provider_ready
			else String(target_validation.get("errorCode", "LLM_MODEL_UNAVAILABLE"))
		)
	)
	var available_provider_count := 0
	for provider in _provider_snapshots():
		if not _first_available_model(String(provider.get("providerId", ""))).is_empty():
			available_provider_count += 1
	var apply_reason := (
		_provider_readiness_reason()
		if not provider_ready
		else ("RESIDENT_MODEL_ASSIGNMENT_DRAFT_INCOMPLETE" if not complete else "")
	)
	return {
		"selectResident": _action("resident_model_assignment.select_resident", configured),
		"setFilter": _action("resident_model_assignment.set_filter", configured),
		"setMode": _action(
			"resident_model_assignment.set_mode",
			configured and not _single_resident_mode,
			"RESIDENT_MODEL_ASSIGNMENT_SINGLE_RESIDENT_MODE",
		),
		"selectBatchResident": _action("resident_model_assignment.select_batch_resident", configured and _mode == "batch", "RESIDENT_MODEL_ASSIGNMENT_BATCH_MODE_REQUIRED"),
		"selectAllBatch": _action("resident_model_assignment.select_all_batch", configured and _mode == "batch" and _batch_selection.size() < rows.size(), "RESIDENT_MODEL_ASSIGNMENT_ALL_RESIDENTS_SELECTED"),
		"selectInvalid": _action("resident_model_assignment.select_invalid", configured and _mode == "batch" and int(counts.get("invalid", 0)) > 0, "RESIDENT_MODEL_ASSIGNMENT_NO_INVALID_RESIDENTS"),
		"selectUnassigned": _action("resident_model_assignment.select_unassigned", configured and _mode == "batch" and int(counts.get("unassigned", 0)) > 0, "RESIDENT_MODEL_ASSIGNMENT_NO_UNASSIGNED_RESIDENTS"),
		"clearBatchSelection": _action("resident_model_assignment.clear_batch_selection", configured and _mode == "batch" and not _batch_selection.is_empty(), "RESIDENT_MODEL_ASSIGNMENT_BATCH_EMPTY"),
		"selectProvider": _action("resident_model_assignment.select_provider", configured and available_provider_count > 0, _provider_readiness_reason()),
		"selectModel": _action("resident_model_assignment.select_model", configured and _available_model_count() > 0, _provider_readiness_reason()),
		"assignOne": _action("resident_model_assignment.assign_one", configured and _mode == "single" and target_available and not _selected_resident_id.is_empty(), provider_reason),
		"assignBatch": _action("resident_model_assignment.assign_batch", configured and _mode == "batch" and target_available and not _batch_selection.is_empty(), "RESIDENT_MODEL_ASSIGNMENT_BATCH_EMPTY" if _batch_selection.is_empty() else provider_reason),
		"applyDraft": _action("resident_model_assignment.apply_draft", configured and provider_ready and complete, apply_reason),
		"refresh": _action("resident_model_assignment.refresh", configured),
		"back": _action("resident_model_assignment.back", configured),
	}


func _resident_snapshots() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for slot_value: Variant in _draft.get("slots", []) as Array:
		var slot := slot_value as Dictionary
		var resident_id := String(slot.get("residentId", ""))
		var catalog_entry := _catalog_entry(resident_id)
		var attributes := catalog_entry.get("attributes", {}) as Dictionary
		var presentation := catalog_entry.get("presentation", {}) as Dictionary
		var binding := (slot.get("llmBinding", {}) as Dictionary).duplicate(true)
		var binding_status := _binding_status(binding)
		var provider_id := String(binding.get("providerId", ""))
		var model_id := String(binding.get("modelId", ""))
		var provider := _provider_snapshot(provider_id)
		var model := _model_snapshot(provider_id, model_id)
		var display_name := String(attributes.get("name", resident_id))
		var portrait_path := String(presentation.get("portraitPath", ""))
		var portrait_is_standalone := not portrait_path.is_empty()
		if portrait_path.is_empty():
			portrait_path = String(presentation.get("spritePath", ""))
		rows.append({
			"residentId": resident_id,
			"displayName": display_name,
			"portraitRef": portrait_path,
			"portraitFrameMode": (
				"full_texture"
				if portrait_is_standalone
				else "legacy_atlas_64x80"
			),
			"portraitFallbackText": display_name.strip_edges().left(1),
			"bindingStatus": binding_status,
			"bindingStatusLabel": _binding_status_label(binding_status),
			"llmBinding": binding,
			"providerDisplayName": String(provider.get("displayName", provider_id)),
			"modelDisplayName": String(model.get("displayName", model_id)),
			"providerErrorCode": String(provider.get("errorCode", "")),
			"modelErrorCode": String(model.get("errorCode", "")),
		})
	return rows


func _resident_snapshot(resident_id: String) -> Dictionary:
	for resident in _resident_snapshots():
		if String(resident.get("residentId", "")) == resident_id:
			return resident.duplicate(true)
	return {}


func _provider_snapshots() -> Array[Dictionary]:
	var providers: Array[Dictionary] = []
	for value: Variant in _health.get("providers", []) as Array:
		if not value is Dictionary:
			continue
		var source := value as Dictionary
		var provider_id := String(source.get("providerId", ""))
		if provider_id.is_empty():
			continue
		var models: Array[Dictionary] = []
		for model in _models:
			if String(model.get("providerId", "")) == provider_id:
				models.append(model.duplicate(true))
		providers.append({
			"providerId": provider_id,
			"displayName": _compact_provider_name(
				provider_id,
				String(source.get("label", provider_id)),
			),
			"status": String(source.get("status", "unavailable")),
			"available": String(source.get("status", "")) == "available",
			"errorCode": String(source.get("errorCode", "")),
			"retryable": bool(source.get("retryable", false)),
			"models": models,
		})
	return providers


func _compact_provider_name(provider_id: String, fallback: String) -> String:
	if provider_id in CUSTOM_MODEL_PROVIDER_IDS:
		var source := fallback.replace("（本地）", "")
		if provider_id == "openai-compatible":
			source = "兼容接口"
		return "自定义 · %s" % source
	match provider_id:
		"deepseek":
			return "DeepSeek"
		"zhipu-glm":
			return "Zhipu GLM"
		"kimi":
			return "Kimi"
	return fallback


func _provider_snapshot(provider_id: String) -> Dictionary:
	for provider in _provider_snapshots():
		if String(provider.get("providerId", "")) == provider_id:
			return provider.duplicate(true)
	return {}


func _model_snapshot(provider_id: String, model_id: String) -> Dictionary:
	for model in _models:
		if String(model.get("providerId", "")) == provider_id and String(model.get("modelId", "")) == model_id:
			return model.duplicate(true)
	return {}


func _first_available_model(provider_id: String) -> Dictionary:
	for model in _models:
		if String(model.get("providerId", "")) == provider_id and bool(model.get("available", false)):
			return model.duplicate(true)
	return {}


func _target_binding() -> Dictionary:
	if _selected_provider_id.is_empty() or _selected_model_id.is_empty():
		return {"mode": "model", "providerId": "", "modelId": ""}
	return {
		"mode": "model",
		"providerId": _selected_provider_id,
		"modelId": _selected_model_id,
	}


func _validate_target_binding(binding: Dictionary) -> Dictionary:
	if String(binding.get("mode", "")) != "model":
		return _failure("SESSION_LLM_BINDING_MODE_INVALID")
	var provider_id := String(binding.get("providerId", ""))
	var model_id := String(binding.get("modelId", ""))
	if provider_id.is_empty():
		return _failure("SESSION_LLM_PROVIDER_REQUIRED")
	if model_id.is_empty():
		return _failure("SESSION_LLM_MODEL_REQUIRED")
	var provider := _provider_snapshot(provider_id)
	if provider.is_empty():
		return _failure("LLM_PROVIDER_UNKNOWN")
	var model := _model_snapshot(provider_id, model_id)
	if model.is_empty():
		return _failure("LLM_MODEL_UNKNOWN")
	if not bool(model.get("available", false)):
		return _failure(String(model.get("errorCode", "LLM_MODEL_UNAVAILABLE")))
	return {"ok": true, "errorCode": "", "retryable": false}


func _binding_status(binding: Dictionary) -> String:
	if String(binding.get("mode", "")) != "model":
		return "invalid"
	if String(binding.get("providerId", "")).is_empty() or String(binding.get("modelId", "")).is_empty():
		return "unassigned"
	return "valid" if bool(_validate_target_binding(binding).get("ok", false)) else "invalid"


func _binding_status_label(status: String) -> String:
	match status:
		"valid":
			return "可用"
		"invalid":
			return "已失效"
	return "未分配"


func _status_counts(rows: Array[Dictionary]) -> Dictionary:
	var counts := {"valid": 0, "invalid": 0, "unassigned": 0}
	for row in rows:
		var status := String(row.get("bindingStatus", "unassigned"))
		counts[status] = int(counts.get(status, 0)) + 1
	return counts


func _formal_ready() -> bool:
	return (
		bool(_health.get("formalReady", false))
		and String(_health.get("capabilityMode", "")) == "formal"
		and String(_health.get("source", "")) == "runtime"
		and _available_model_count() > 0
	)


func _available_model_count() -> int:
	var count := 0
	for model in _models:
		if bool(model.get("available", false)):
			count += 1
	return count


func _provider_readiness_reason() -> String:
	var health_error := String(_health.get("errorCode", ""))
	if not health_error.is_empty():
		return health_error
	var providers := _provider_snapshots()
	if providers.is_empty():
		return "PROVIDER_CATALOG_UNAVAILABLE"
	var first_provider_error := ""
	for provider in providers:
		var provider_id := String(provider.get("providerId", ""))
		if not _first_available_model(provider_id).is_empty():
			return ""
		if first_provider_error.is_empty():
			first_provider_error = _provider_model_readiness_reason(provider_id)
	if not first_provider_error.is_empty():
		return first_provider_error
	return "LLM_MODEL_UNAVAILABLE"


func _provider_model_readiness_reason(provider_id: String) -> String:
	var first_model_error := ""
	for model in _models:
		if String(model.get("providerId", "")) != provider_id:
			continue
		if bool(model.get("available", false)):
			return ""
		if first_model_error.is_empty():
			first_model_error = String(model.get("errorCode", ""))
	if not first_model_error.is_empty():
		return first_model_error
	var provider := _provider_snapshot(provider_id)
	if not provider.is_empty():
		var provider_error := String(provider.get("errorCode", ""))
		if not provider_error.is_empty():
			return provider_error
	return "LLM_MODEL_UNAVAILABLE"


func _choose_available_target() -> void:
	var current := _resident_snapshot(_selected_resident_id)
	var current_binding := current.get("llmBinding", {}) as Dictionary
	if bool(_validate_target_binding(current_binding).get("ok", false)):
		_selected_provider_id = String(current_binding.get("providerId", ""))
		_selected_model_id = String(current_binding.get("modelId", ""))
		return
	_selected_provider_id = ""
	_selected_model_id = ""
	for provider in _provider_snapshots():
		var provider_id := String(provider.get("providerId", ""))
		var model := _first_available_model(provider_id)
		if not model.is_empty():
			_selected_provider_id = provider_id
			_selected_model_id = String(model.get("modelId", ""))
			return


func _normalized_binding(binding: Dictionary) -> Dictionary:
	return {
		"mode": "model",
		"providerId": String(binding.get("providerId", "")),
		"modelId": String(binding.get("modelId", "")),
	}


func _slot_index(resident_id: String) -> int:
	var slots := _draft.get("slots", []) as Array
	for index in slots.size():
		if String((slots[index] as Dictionary).get("residentId", "")) == resident_id:
			return index
	return -1


func _catalog_entry(resident_id: String) -> Dictionary:
	for value: Variant in _catalog.get("residents", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("residentId", "")) == resident_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _validate_catalog(catalog: Dictionary) -> Dictionary:
	var residents_value: Variant = catalog.get("residents", [])
	if not residents_value is Array:
		return _failure("RESIDENT_MODEL_CATALOG_INVALID")
	if (residents_value as Array).size() != _slot_count:
		return _failure("RESIDENT_MODEL_CATALOG_RESIDENT_COUNT_MISMATCH")
	var seen: Dictionary = {}
	for value: Variant in residents_value as Array:
		if not value is Dictionary:
			return _failure("RESIDENT_MODEL_CATALOG_INVALID")
		var resident_id := String((value as Dictionary).get("residentId", ""))
		if resident_id.is_empty() or seen.has(resident_id):
			return _failure("RESIDENT_MODEL_CATALOG_RESIDENT_INVALID")
		seen[resident_id] = true
	return {"ok": true, "errorCode": "", "retryable": false}


func _validate_initial_draft(draft: Dictionary) -> Dictionary:
	if int(draft.get("schemaVersion", 0)) != DRAFT_SCHEMA_VERSION:
		return _failure("SESSION_DRAFT_SCHEMA_UNSUPPORTED")
	if String(draft.get("sourceScope", "")) != DRAFT_SOURCE_SCOPE:
		return _failure("SESSION_DRAFT_SOURCE_INVALID")
	if int(draft.get("draftRevision", 0)) < 1:
		return _failure("SESSION_DRAFT_REVISION_INVALID")
	var slots_value: Variant = draft.get("slots", [])
	if not slots_value is Array:
		return _failure("SESSION_DRAFT_SLOTS_INVALID")
	if (slots_value as Array).size() != _slot_count:
		return _failure("SESSION_HOME_SPACE_COUNT_MISMATCH")
	var seen_residents: Dictionary = {}
	var seen_spaces: Dictionary = {}
	for value: Variant in slots_value as Array:
		if not value is Dictionary:
			return _failure("SESSION_DRAFT_SLOT_INVALID")
		var slot := value as Dictionary
		var resident_id := String(slot.get("residentId", "")).strip_edges()
		var space_id := String(slot.get("spaceId", "")).strip_edges()
		if resident_id.is_empty():
			return _failure("SESSION_RESIDENT_ID_REQUIRED")
		if seen_residents.has(resident_id):
			return _failure("SESSION_RESIDENT_ID_DUPLICATED")
		if _catalog_entry(resident_id).is_empty():
			return _failure("SESSION_RESIDENT_ID_UNKNOWN")
		if space_id.is_empty():
			return _failure("SESSION_HOME_SPACE_REQUIRED")
		if not _expected_home_space_ids().has(space_id):
			return _failure("SESSION_HOME_SPACE_UNKNOWN")
		if seen_spaces.has(space_id):
			return _failure("SESSION_HOME_SPACE_DUPLICATED")
		if slot.has("llmBinding") and not slot.get("llmBinding") is Dictionary:
			return _failure("SESSION_LLM_BINDING_INVALID")
		seen_residents[resident_id] = true
		seen_spaces[space_id] = true
	for expected_space in _expected_home_space_ids():
		if not seen_spaces.has(expected_space):
			return _failure("SESSION_HOME_SPACE_MISSING")
	return {"ok": true, "errorCode": "", "retryable": false}


func _normalize_initial_draft(draft: Dictionary) -> Dictionary:
	var normalized_slots: Array[Dictionary] = []
	for value: Variant in draft.get("slots", []) as Array:
		var slot := value as Dictionary
		var binding_source: Dictionary = {}
		if slot.get("llmBinding", {}) is Dictionary:
			binding_source = (slot.get("llmBinding", {}) as Dictionary).duplicate(true)
		var binding := {
			"mode": "model" if binding_source.is_empty() else String(binding_source.get("mode", "")),
			"providerId": String(binding_source.get("providerId", "")).strip_edges(),
			"modelId": String(binding_source.get("modelId", "")).strip_edges(),
		}
		normalized_slots.append({
			"residentId": String(slot.get("residentId", "")).strip_edges(),
			"spaceId": String(slot.get("spaceId", "")).strip_edges(),
			"llmBinding": binding,
		})
	return {
		"schemaVersion": DRAFT_SCHEMA_VERSION,
		"sourceScope": DRAFT_SOURCE_SCOPE,
		"draftRevision": int(draft.get("draftRevision", 1)),
		"slots": normalized_slots,
	}


func _expected_home_space_ids() -> Array[String]:
	if _single_resident_mode and not _allowed_space_ids.is_empty():
		return _allowed_space_ids.duplicate()
	var result: Array[String] = []
	for index in range(1, _slot_count + 1):
		result.append("home_%02d" % index)
	return result


func _finish_operation(request_id: String, intent: String, result: Dictionary) -> Dictionary:
	var ok := bool(result.get("ok", false))
	var retryable := bool(result.get("retryable", false))
	_operation = _operation_payload(request_id, intent, "success" if ok else ("error" if retryable else "rejected"))
	_operation["completedAtMsec"] = Time.get_ticks_msec()
	_error = null if ok else _error_payload(
		String(result.get("errorCode", "RESIDENT_MODEL_ASSIGNMENT_REJECTED")),
		retryable,
		result.get("errors", []) as Array,
	)
	_revision += 1
	_emit_view_model()
	if ok and intent == "resident_model_assignment.apply_draft":
		draft_applied.emit(_committed_draft.duplicate(true), _revision)
	elif ok and intent == "resident_model_assignment.back":
		back_requested.emit(_draft.duplicate(true), _revision)
	operation_completed.emit(SCOPE, _operation.duplicate(true))
	return _dispatch_result(ok, true, request_id, String(result.get("errorCode", "")), retryable, bool(result.get("changed", false)))


func _publish_rejected(request_id: String, intent: String, error_code: String) -> Dictionary:
	_operation = _operation_payload(request_id, intent, "rejected")
	_operation["completedAtMsec"] = Time.get_ticks_msec()
	_error = _error_payload(error_code, false)
	_revision += 1
	_emit_view_model()
	operation_completed.emit(SCOPE, _operation.duplicate(true))
	return _dispatch_result(false, true, request_id, error_code, false)


func _emit_view_model() -> void:
	view_model_changed.emit(SCOPE, _build_view_model().duplicate(true))


func _configuration_failure(error_code: String) -> Dictionary:
	_error = _error_payload(error_code, false)
	return RESULT_SHAPES.failure(error_code)


func _action(intent: String, enabled: bool, disabled_reason := "") -> Dictionary:
	return AiTownUiViewModel.make_action(intent, enabled, disabled_reason)


func _success(changed: bool) -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false, "changed": changed}


func _failure(error_code: String, retryable := false, errors: Array = []) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"errors": errors.duplicate(true),
	}


func _dispatch_result(
	ok: bool,
	accepted: bool,
	request_id: String,
	error_code: String,
	retryable: bool,
	changed := false,
) -> Dictionary:
	return UI_VIEW_MODEL.dispatch_result(ok, accepted, request_id, error_code, retryable, changed)


func _error_payload(error_code: String, retryable: bool, details: Array = []) -> Dictionary:
	return {
		"kind": "transport" if retryable else "validation",
		"code": error_code,
		"message": _error_message(error_code),
		"retryable": retryable,
		"details": details.duplicate(true),
	}


func _error_message(error_code: String) -> String:
	match error_code:
		"RESIDENT_MODEL_ASSIGNMENT_REVISION_STALE":
			return "页面数据已更新，请按最新状态继续操作。"
		"RESIDENT_MODEL_ASSIGNMENT_DRAFT_INCOMPLETE", "SESSION_DRAFT_INVALID":
			return "仍有居民未完成有效模型绑定，草稿已保留。"
		"PROVIDER_HEALTH_UNAVAILABLE", "PROVIDER_HEALTH_QUERY_FAILED", "PROVIDER_HEALTH_SNAPSHOT_INVALID", "PROVIDER_CATALOG_UNAVAILABLE", "PROVIDER_MODEL_CATALOG_INVALID", "PROVIDER_MODEL_CATALOG_DUPLICATED", "PROVIDER_HEALTH_CATALOG_INVALID", "PROVIDER_HEALTH_CATALOG_DUPLICATED", "PROVIDER_FORMAL_RUNTIME_REQUIRED", "LLM_PROVIDER_UNAVAILABLE", "LLM_MODEL_UNAVAILABLE", "LLM_MODEL_UNKNOWN":
			return "目标 Provider 或模型当前不可用，原绑定与草稿已保留。"
		"SESSION_DRAFT_SCHEMA_UNSUPPORTED", "SESSION_DRAFT_SOURCE_INVALID", "SESSION_DRAFT_REVISION_INVALID", "SESSION_DRAFT_SLOTS_INVALID", "SESSION_DRAFT_SLOT_INVALID", "SESSION_HOME_SPACE_COUNT_MISMATCH", "SESSION_HOME_SPACE_REQUIRED", "SESSION_HOME_SPACE_UNKNOWN", "SESSION_HOME_SPACE_DUPLICATED", "SESSION_HOME_SPACE_MISSING", "SESSION_RESIDENT_ID_REQUIRED", "SESSION_RESIDENT_ID_UNKNOWN", "SESSION_RESIDENT_ID_DUPLICATED", "SESSION_LLM_BINDING_INVALID":
			return "居民选择草稿无效，未进入模型分配；原草稿未被修改。"
		"RESIDENT_MODEL_ASSIGNMENT_BATCH_EMPTY":
			return "请先在批量模式选择至少一位居民。"
	return "操作未完成，已保留最近一次确认数据。"


func _operation_payload(request_id: String, intent: String, status: String) -> Dictionary:
	return {
		"requestId": request_id,
		"intent": intent,
		"status": status,
		"submittedAtMsec": Time.get_ticks_msec() if status == "loading" else 0,
		"completedAtMsec": 0,
	}


func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


func _next_request_id() -> String:
	_request_sequence += 1
	return AiTownUiViewModel.request_id("resident-model-assignment", _request_sequence)


func _unknown_scope_view_model(scope: String) -> Dictionary:
	return {
		"scope": scope,
		"status": "error",
		"revision": 0,
		"data": {},
		"actions": {},
		"operation": _idle_operation(),
		"error": _error_payload("UNKNOWN_UI_SCOPE", false),
	}


func _disabled_view_model() -> Dictionary:
	var disabled_error := (
		(_error as Dictionary).duplicate(true)
		if _error is Dictionary
		else _error_payload("RESIDENT_MODEL_ASSIGNMENT_NOT_CONFIGURED", false)
	)
	return {
		"scope": SCOPE,
		"status": "disabled",
		"revision": _revision,
		"data": {
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": false,
			"draftRevision": 0,
			"residentCount": _slot_count,
			"completedCount": 0,
			"invalidCount": 0,
			"unassignedCount": _slot_count,
			"dirty": false,
			"mode": "single",
			"filter": "all",
			"selectedResidentId": "",
			"selectedProviderId": "",
			"selectedModelId": "",
			"selectedBatchResidentIds": [],
			"residents": [],
			"providers": [],
			"targetBinding": {"mode": "model", "providerId": "", "modelId": ""},
			"selectedResident": {},
		},
		"actions": {},
		"operation": _operation_payload("", "", "disabled"),
		"error": disabled_error,
	}


func _reset() -> void:
	_provider_service = null
	_catalog.clear()
	_draft.clear()
	_committed_draft.clear()
	_configured = false
	_revision = 0
	_request_sequence = 0
	_selected_resident_id = ""
	_selected_provider_id = ""
	_selected_model_id = ""
	_mode = "single"
	_filter = "all"
	_batch_selection.clear()
	_health.clear()
	_models.clear()
	_operation = _idle_operation()
	_error = null
	_apply_handler = Callable()
	_single_resident_mode = false
	_slot_count = SLOT_COUNT
	_allowed_space_ids.clear()
