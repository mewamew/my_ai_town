class_name TownStartupOfflineResidentModelRebindCoordinator
extends Node


signal route_finished(saved: bool, destination: String, result: Dictionary)
signal action_blocked(intent: StringName, reason: String)


const OFFLINE_REBIND := preload(
	"res://world/presentation/session/TownOfflineResidentModelRebindService.gd"
)
const ASSIGNMENT := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentService.gd"
)
const PAGE_SCENE := preload(
	"res://ui/resident_model_assignment/ResidentModelAssignmentScreen.tscn"
)
const UI_NODE_RETIREMENT := preload(
	"res://ui/common/AiTownUiNodeRetirement.gd"
)
const RECONCILIATION := preload(
	"res://world/presentation/session/TownSaveReconciliationService.gd"
)


var _store: TownSessionSaveStore
var _agent_store: AgentSaveStore
var _provider: Object
var _adapter: TownUiAdapter
var _base_catalog: Dictionary = {}
var _page: ResidentModelAssignmentScreen
var _assignment: ResidentModelAssignmentService
var _rebind: TownOfflineResidentModelRebindService
var _target: Dictionary = {}
var _preserved_draft: Dictionary = {}
var _last_result: Dictionary = {}
var _return_state := ""


func configure(
	store: TownSessionSaveStore,
	agent_store: AgentSaveStore,
	provider: Object,
	adapter: TownUiAdapter,
	base_catalog: Dictionary,
) -> Dictionary:
	if (
		_store != null
		or store == null
		or agent_store == null
		or provider == null
		or adapter == null
	):
		return _failure("STARTUP_SAVE_MODEL_COORDINATOR_CONFIGURATION_INVALID")
	_store = store
	_agent_store = agent_store
	_provider = provider
	_adapter = adapter
	_base_catalog = base_catalog.duplicate(true)
	return _success()


func select_target(slot: Dictionary) -> Dictionary:
	if is_open():
		return _failure("STARTUP_SAVE_MODEL_COORDINATOR_ALREADY_OPEN")
	var projection := project_slot_edit(slot)
	var summary := slot.get("summary", {}) as Dictionary
	var target := {
		"slotId": String(slot.get("slotId", "")).strip_edges(),
		"sessionId": String(summary.get("sessionId", "")).strip_edges(),
		"saveRevision": int(summary.get("saveRevision", -1)),
	}
	if (
		not bool(projection.get("modelEditAvailable", false))
		or String(target.get("slotId", "")).is_empty()
		or String(target.get("sessionId", "")).is_empty()
		or int(target.get("saveRevision", -1)) < 1
	):
		return _failure(String(projection.get(
			"modelEditDisabledReason",
			"STARTUP_SAVE_MODEL_EDIT_TARGET_STALE",
		)))
	_target = target.duplicate(true)
	_return_state = (
		"recovery"
		if bool(projection.get("modelEditRecoveryRequired", false))
		else "selected"
	)
	var result := _success()
	result["target"] = _target.duplicate(true)
	result["recoveryRequired"] = _return_state == "recovery"
	return result


func open(startup: Control, slot: Dictionary) -> Dictionary:
	if _target.is_empty():
		var selected := select_target(slot)
		if selected.get("ok") != true:
			return selected
	return resume(startup, slot)


func resume(startup: Control, slot: Dictionary) -> Dictionary:
	if is_open():
		return _failure("STARTUP_SAVE_MODEL_COORDINATOR_ALREADY_OPEN")
	if _store == null or startup == null:
		return _failure("STARTUP_SAVE_MODEL_COORDINATOR_NOT_CONFIGURED")
	if not _slot_matches_target(slot):
		return _failure("STARTUP_SAVE_MODEL_EDIT_TARGET_STALE")
	var rebind := OFFLINE_REBIND.new() as TownOfflineResidentModelRebindService
	var configured := rebind.configure(_store, _agent_store, _provider)
	if configured.get("ok") != true:
		return configured
	var prepared := rebind.prepare(slot, _base_catalog)
	if prepared.get("ok") != true:
		return prepared
	var target := prepared.get("target", {}) as Dictionary
	var draft := (prepared.get("draft", {}) as Dictionary).duplicate(true)
	if (
		String(_preserved_draft.get("slotId", ""))
		== String(target.get("slotId", ""))
		and int(_preserved_draft.get("saveRevision", -1))
		== int(target.get("saveRevision", -2))
	):
		draft = (_preserved_draft.get("draft", {}) as Dictionary).duplicate(true)
	var assignment := ASSIGNMENT.new() as ResidentModelAssignmentService
	configured = assignment.configure(
		_provider,
		prepared.get("residentCatalog", {}) as Dictionary,
		draft,
		{
			"revision": maxi(int(draft.get("draftRevision", 1)), 1),
			"allowAutomaticBindingRepair": false,
			"applyHandler": func(
				applied_draft: Dictionary,
				bindings: Array,
			) -> Dictionary:
				return _apply_draft(applied_draft, bindings),
		},
	)
	if configured.get("ok") != true:
		return configured
	var bound := _adapter.bind_resident_model_assignment_service(assignment)
	if bound.get("ok") != true:
		return bound
	var page := PAGE_SCENE.instantiate() as ResidentModelAssignmentScreen
	if page == null:
		_adapter.bind_resident_model_assignment_service(null)
		return _failure("STARTUP_SAVE_MODEL_EDIT_ROUTE_FAILED")
	_rebind = rebind
	_assignment = assignment
	_target = target.duplicate(true)
	_return_state = "editing"
	_assignment.draft_applied.connect(_on_draft_applied)
	_assignment.back_requested.connect(_on_back_requested)
	page.provider_settings_requested.connect(_on_provider_settings_requested)
	page.action_blocked.connect(
		func(intent: String, reason: String) -> void:
			action_blocked.emit(StringName(intent), reason),
	)
	page.name = "StartupSaveModelAssignmentRoute"
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.z_index = 2300
	page.apply_route_payload({"mode": "save_slot"})
	page.bind_town_ui_adapter(_adapter)
	_page = page
	startup.add_child(page)
	startup.set_process_unhandled_input(false)
	_last_result = {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"target": target.duplicate(true),
	}
	return _last_result.duplicate(true)


func close() -> void:
	if is_instance_valid(_page):
		_page.unbind_town_ui_adapter()
		UI_NODE_RETIREMENT.retire(_page)
	_page = null
	if _adapter != null:
		_adapter.bind_resident_model_assignment_service(null)
	_assignment = null
	_rebind = null


func is_open() -> bool:
	return is_instance_valid(_page)


func page() -> Control:
	return _page


func assignment() -> RefCounted:
	return _assignment


func target() -> Dictionary:
	return _target.duplicate(true)


func awaiting_provider_settings() -> bool:
	return _return_state == "provider_settings" and not _target.is_empty()


func preserved_draft() -> Dictionary:
	return _preserved_draft.duplicate(true)


func last_result() -> Dictionary:
	return _last_result.duplicate(true)


static func project_slot_edit(slot: Dictionary) -> Dictionary:
	var summary := slot.get("summary", {}) as Dictionary
	var save_blockers := slot.get("saveBlockers", []) as Array
	var restore_blockers := slot.get("restoreBlockers", []) as Array
	var has_blockers := not save_blockers.is_empty() or not restore_blockers.is_empty()
	var reconciliation := slot.get("reconciliationPlan", {}) as Dictionary
	var recovery_required := (
		has_blockers
		and bool(reconciliation.get("repairable", false))
		and String(reconciliation.get("action", "")) == RECONCILIATION.RECONCILE_ACTION
	)
	var recovery_plan := slot.get("recoveryPlan", {}) as Dictionary
	var restore_before_edit := (
		not recovery_required
		and not recovery_plan.is_empty()
		and not summary.is_empty()
	)
	var available := (
		not summary.is_empty()
		and not restore_before_edit
		and (not has_blockers or recovery_required)
	)
	var reason := ""
	if not available:
		reason = (
			"OFFLINE_RESIDENT_MODEL_REBIND_RECOVERY_REQUIRED"
			if restore_before_edit
			else "SESSION_SAVE_NO_COMPLETE_REVISION"
		)
	return {
		"modelEditAvailable": available,
		"modelEditSaveRevision": int(summary.get("saveRevision", 0)),
		"modelEditDisabledReason": reason,
		"modelEditRecoveryRequired": recovery_required,
	}


func _apply_draft(_draft: Dictionary, bindings: Array) -> Dictionary:
	if _rebind == null:
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_NOT_CONFIGURED")
	_last_result = _rebind.apply_bindings(bindings)
	return _last_result.duplicate(true)


func _on_draft_applied(_draft: Dictionary, _revision: int) -> void:
	_preserved_draft.clear()
	var result := _last_result.duplicate(true)
	close()
	_clear_pending_target()
	route_finished.emit(true, "load_game", result)


func _on_back_requested(draft: Dictionary, _revision: int) -> void:
	_preserve(draft)
	close()
	_clear_pending_target()
	route_finished.emit(false, "load_game", _success())


func _on_provider_settings_requested(_revision: int) -> void:
	if _assignment != null:
		_preserve(_assignment.get_session_draft())
	close()
	_return_state = "provider_settings"
	var result := _success()
	result["target"] = _target.duplicate(true)
	route_finished.emit(false, "provider_settings", result)


func _preserve(draft: Dictionary) -> void:
	_preserved_draft = {
		"slotId": String(_target.get("slotId", "")),
		"saveRevision": int(_target.get("saveRevision", 0)),
		"draft": draft.duplicate(true),
	}


func _slot_matches_target(slot: Dictionary) -> bool:
	if _target.is_empty():
		return false
	var summary := slot.get("summary", {}) as Dictionary
	return (
		String(slot.get("slotId", "")) == String(_target.get("slotId", ""))
		and String(summary.get("sessionId", ""))
		== String(_target.get("sessionId", ""))
		and int(summary.get("saveRevision", -1))
		== int(_target.get("saveRevision", -2))
	)


func _clear_pending_target() -> void:
	_target.clear()
	_return_state = ""


func _success() -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false}


func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"errors": [],
	}
