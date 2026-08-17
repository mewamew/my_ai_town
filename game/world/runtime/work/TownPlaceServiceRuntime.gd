class_name TownPlaceServiceRuntime
extends RefCounted


const RESTORE_LAYOUT := preload(
	"res://world/runtime/persistence/TownWorldRestoreLayout.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)

var _states: Dictionary = {}


func reset() -> void:
	_states.clear()


func restore_prepared(prepared: Dictionary) -> void:
	_states = prepared.duplicate(true)


func save_snapshot() -> Dictionary:
	return _states.duplicate(true)


func replace_with_defaults(defaults: Dictionary) -> void:
	_states = defaults.duplicate(true)


func has(place_id: String) -> bool:
	return _states.has(place_id)


func state(place_id: String) -> Dictionary:
	return (_states.get(place_id, {}) as Dictionary).duplicate(true)


func set_state(place_id: String, value: Dictionary) -> void:
	if place_id.is_empty():
		return
	_states[place_id] = value.duplicate(true)


func values_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for place_id: String in sorted_place_ids():
		result.append(state(place_id))
	return result


func sorted_place_ids() -> Array[String]:
	var result: Array[String] = []
	for place_id_value: Variant in _states:
		result.append(String(place_id_value))
	result.sort()
	return result


func build_default_states(
	world_data: Dictionary,
	residents: Dictionary,
	staffing_snapshot: Dictionary,
	available_resident_ids: Array[String],
) -> Dictionary:
	var result := {}
	for place_value: Variant in world_data.get("places", []) as Array:
		var place := place_value as Dictionary
		var profile_value: Variant = place.get("serviceProfile")
		if profile_value is not Dictionary:
			continue
		var profile := profile_value as Dictionary
		var place_id := String(place.get("name", "")).strip_edges()
		var helper_activity_id := String(
			profile.get("helperActivityId", ""),
		).strip_edges()
		var service_occupation_id := _service_occupation_id(
			world_data,
			place_id,
			helper_activity_id,
		)
		var assigned_resident_ids := _staffing_resident_ids(
			staffing_snapshot,
			service_occupation_id,
		)
		if assigned_resident_ids.is_empty():
			assigned_resident_ids = _resident_ids_for_occupation(
				world_data,
				residents,
				service_occupation_id,
			)
		assigned_resident_ids = assigned_resident_ids.filter(
			func(resident_id: String) -> bool:
				return available_resident_ids.has(resident_id),
		)
		var owner_id := (
			assigned_resident_ids[0]
			if assigned_resident_ids.size() == 1
			else ""
		)
		var capacity := int(profile.get("capacity", 0))
		var request_activity_ids: Array[String] = []
		for activity_value: Variant in profile.get(
			"requestActivityIds",
			[],
		) as Array:
			var activity_id := String(activity_value).strip_edges()
			if not activity_id.is_empty():
				request_activity_ids.append(activity_id)
		if (
			place_id.is_empty()
			or service_occupation_id.is_empty()
			or helper_activity_id.is_empty()
			or capacity <= 0
			or request_activity_ids.is_empty()
			or not RESTORE_LAYOUT.world_data_has_activity_at_place(
				world_data,
				helper_activity_id,
				place_id,
			)
		):
			continue
		var valid_requests := request_activity_ids.all(
			func(activity_id: String) -> bool:
				return RESTORE_LAYOUT.world_data_has_activity_at_place(
					world_data,
					activity_id,
					place_id,
				),
		)
		if not valid_requests:
			continue
		result[place_id] = {
			"pressure_id": "service-pressure:%s" % place_id,
			"place_id": place_id,
			"owner_id": owner_id,
			"open": not owner_id.is_empty(),
			"service_occupation_id": service_occupation_id,
			"service_capacity": capacity,
			"helper_activity_id": helper_activity_id,
			"request_activity_ids": request_activity_ids,
			"pending_request_ids": [],
			"source_revision": 0,
			"expires_at": -1,
			"updated_at": -1,
		}
	return result


func update_request(
	place_id: String,
	request_id: String,
	active: bool,
	expires_at: int,
	absolute_minute: int,
) -> Dictionary:
	var normalized_place := place_id.strip_edges()
	var normalized_request := request_id.strip_edges()
	if normalized_request.is_empty() or not has(normalized_place):
		return _failure(
			"PLACE_SERVICE_REQUEST_INVALID",
			"地点没有可接入的服务配置，或请求编号为空",
		)
	var current := state(normalized_place)
	var pending := (current.get("pending_request_ids", []) as Array).duplicate()
	var changed := false
	if active and not pending.has(normalized_request):
		pending.append(normalized_request)
		pending.sort()
		changed = true
	elif not active and pending.has(normalized_request):
		pending.erase(normalized_request)
		changed = true
	if not changed:
		return {"ok": true, "changed": false, "state": current}
	current["pending_request_ids"] = pending
	current["source_revision"] = int(current.get("source_revision", 0)) + 1
	current["expires_at"] = (
		expires_at if expires_at >= 0 else absolute_minute + 180
	)
	current["updated_at"] = absolute_minute
	set_state(normalized_place, current)
	return {
		"ok": true,
		"changed": true,
		"placeId": normalized_place,
		"requestId": normalized_request,
		"state": current,
	}


func update_open(
	place_id: String,
	open: bool,
	absolute_minute: int,
) -> Dictionary:
	var normalized_place := place_id.strip_edges()
	if not has(normalized_place):
		return _failure(
			"PLACE_SERVICE_STATE_UNKNOWN",
			"地点没有可接入的服务配置",
		)
	var current := state(normalized_place)
	if bool(current.get("open", true)) == open:
		return {"ok": true, "changed": false, "state": current}
	current["open"] = open
	current["source_revision"] = int(current.get("source_revision", 0)) + 1
	current["updated_at"] = absolute_minute
	set_state(normalized_place, current)
	return {
		"ok": true,
		"changed": true,
		"placeId": normalized_place,
		"state": current,
	}


func work_task_sync_plan(
	value: Dictionary,
	request_id: String,
	active: bool,
	work_tasks: TownWorkTaskRuntime,
) -> Dictionary:
	var place_id := String(value.get("place_id", ""))
	var binding := work_tasks.service_binding_for(place_id) as Dictionary
	if binding.is_empty():
		return {"operation": "none", "result": {"ok": true, "changed": false}}
	var source_kind := String(binding.get("sourceKind", ""))
	var existing := work_tasks.active_task_for_source(
		source_kind,
		request_id,
	) as Dictionary
	if active:
		if not existing.is_empty():
			return {
				"operation": "none",
				"result": {"ok": true, "changed": false, "task": existing},
			}
		return {
			"operation": "create",
			"spec": {
				"taskId": "service-task:%s:%s:%d" % [
					place_id,
					request_id,
					int(value.get("source_revision", 0)),
				],
				"capability": String(binding.get("capability", "")),
				"sourceKind": source_kind,
				"sourceRef": request_id,
				"targets": [{"kind": "service_request", "ref": request_id}],
				"requestedResultKind": String(binding.get("resultKind", "")),
				"priority": CONTENT_CATALOG.TASK_PRIORITY["place_service_task"],
			},
		}
	if existing.is_empty():
		return {"operation": "none", "result": {"ok": true, "changed": false}}
	return {
		"operation": "cancel",
		"taskId": String(existing.get("taskId", "")),
	}


func service_control(resident: Dictionary) -> Dictionary:
	var resident_id := String(resident.get("residentId", ""))
	var current_place := String(resident.get("currentPlace", ""))
	var current := state(current_place)
	if current.is_empty() or String(current.get("owner_id", "")) != resident_id:
		return {}
	return {
		"place_id": current_place,
		"open": bool(current.get("open", true)),
	}


func is_closed_for_visitor(resident: Dictionary, place_id: String) -> bool:
	var current := state(place_id)
	if current.is_empty() or bool(current.get("open", true)):
		return false
	var resident_id := String(resident.get("residentId", ""))
	if String(current.get("owner_id", "")) == resident_id:
		return false
	return String(
		(resident.get("socialState", {}) as Dictionary).get("workplace", ""),
	) != place_id


func public_snapshots(active_workers_by_place: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for place_id: String in sorted_place_ids():
		var current := state(place_id)
		current["active_workers"] = int(active_workers_by_place.get(place_id, 0))
		current["waiting_requests"] = (
			current.get("pending_request_ids", []) as Array
		).size()
		result.append(current)
	return result


func pressure_payload(place_id: String, active_workers: int) -> Dictionary:
	var current := state(place_id)
	if current.is_empty():
		return _failure(
			"PLACE_SERVICE_STATE_UNKNOWN",
			"地点服务状态不存在",
		)
	return {
		"ok": true,
		"payload": {
			"pressure_id": String(current.get("pressure_id", "")),
			"source_revision": int(current.get("source_revision", 0)),
			"place_id": String(current.get("place_id", "")),
			"owner_id": String(current.get("owner_id", "")),
			"open": bool(current.get("open", true)),
			"service_capacity": int(current.get("service_capacity", 0)),
			"active_workers": active_workers,
			"waiting_requests": (
				current.get("pending_request_ids", []) as Array
			).size(),
			"helper_activity_id": String(current.get("helper_activity_id", "")),
			"expires_at": int(current.get("expires_at", -1)),
			"source_event_ids": (
				current.get("pending_request_ids", []) as Array
			).duplicate(),
		},
	}


func active_worker_count(
	value: Dictionary,
	residents: Dictionary,
	resident_order: Array,
	activity_runtime: TownWorldActivityRuntime,
) -> int:
	var count := 0
	var helper_activity_id := String(value.get("helper_activity_id", ""))
	var place_id := String(value.get("place_id", ""))
	for resident_id_value: Variant in resident_order:
		var resident_id := String(resident_id_value)
		var resident := residents.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		var execution := activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if (
			String(execution.get("status", "")) == "executing"
			and String(execution.get("activityId", "")) == helper_activity_id
			and String(execution.get("placeId", "")) == place_id
		):
			count += 1
	return count


func open_change_notification(
	place_id: String,
	open: bool,
	changed_by_resident_id: String,
	residents: Dictionary,
	resident_order: Array,
) -> Dictionary:
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in resident_order:
		var resident_id := String(resident_id_value)
		var resident := residents.get(resident_id, {}) as Dictionary
		if (
			resident_id == changed_by_resident_id
			or String(resident.get("currentPlace", "")) == place_id
		):
			resident_ids.append(resident_id)
	return {
		"residentIds": resident_ids,
		"source": {
			"type": "营业状态变化",
			"place_id": place_id,
			"open": open,
			"summary": (
				"%s恢复营业了" % place_id
				if open
				else "%s今天停止营业了" % place_id
			),
			"changed_by_resident_id": changed_by_resident_id,
		},
	}


func apply_activity_completion(
	execution: Dictionary,
	remove_completed_helper_request: bool,
	absolute_minute: int,
) -> Dictionary:
	var activity_id := String(execution.get("activityId", ""))
	var place_id := String(execution.get("placeId", ""))
	if not has(place_id):
		return {"changed": false}
	var current := state(place_id)
	var pending := (current.get("pending_request_ids", []) as Array).duplicate()
	var changed := false
	if (current.get("request_activity_ids", []) as Array).has(activity_id):
		var request_id := "activity-request:%s" % String(
			execution.get("actionId", ""),
		)
		if not pending.has(request_id):
			pending.append(request_id)
			pending.sort()
			changed = true
	elif (
		activity_id == String(current.get("helper_activity_id", ""))
		and not pending.is_empty()
		and remove_completed_helper_request
	):
		pending.pop_front()
		changed = true
	if not changed:
		return {"changed": false, "state": current}
	current["pending_request_ids"] = pending
	current["source_revision"] = int(current.get("source_revision", 0)) + 1
	current["expires_at"] = absolute_minute + 180
	current["updated_at"] = absolute_minute
	set_state(place_id, current)
	return {"changed": true, "state": current, "placeId": place_id}


func first_pending_request(place_id: String) -> String:
	var pending := state(place_id).get("pending_request_ids", []) as Array
	return String(pending[0]) if not pending.is_empty() else ""


func reconcile_staffing(defaults: Dictionary, absolute_minute: int) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for place_id_value: Variant in defaults:
		var place_id := String(place_id_value)
		var expected := defaults.get(place_id, {}) as Dictionary
		var current := state(place_id)
		if current.is_empty():
			set_state(place_id, expected)
			continue
		var old_open := bool(current.get("open", false))
		var next_open := bool(expected.get("open", false))
		var next_owner := String(expected.get("owner_id", ""))
		var next_occupation := String(expected.get("service_occupation_id", ""))
		var visible_changed := (
			String(current.get("owner_id", "")) != next_owner
			or old_open != next_open
		)
		if (
			not visible_changed
			and String(current.get("service_occupation_id", "")) == next_occupation
		):
			continue
		current["owner_id"] = next_owner
		current["open"] = next_open
		current["service_occupation_id"] = next_occupation
		if visible_changed:
			current["source_revision"] = int(current.get("source_revision", 0)) + 1
			current["updated_at"] = absolute_minute
		set_state(place_id, current)
		changes.append({
			"placeId": place_id,
			"state": current,
			"visibleChanged": visible_changed,
			"openChanged": old_open != next_open,
		})
	return changes


func _service_occupation_id(
	world_data: Dictionary,
	place_id: String,
	helper_activity_id: String,
) -> String:
	var helper_tags: Array = []
	for activity_value: Variant in world_data.get("activityDefinitions", []) as Array:
		if (
			activity_value is Dictionary
			and String((activity_value as Dictionary).get("activityId", ""))
				== helper_activity_id
		):
			helper_tags = (activity_value as Dictionary).get("tags", []) as Array
			break
	if helper_tags.is_empty():
		return ""
	var matches: Array[String] = []
	for occupation_value: Variant in world_data.get("occupations", []) as Array:
		if occupation_value is not Dictionary:
			continue
		var occupation := occupation_value as Dictionary
		if (
			String(occupation.get("primaryWorkplacePlace", "")) != place_id
			or not _arrays_overlap(
				helper_tags,
				occupation.get("allowedActivityTags", []) as Array,
			)
		):
			continue
		matches.append(String(occupation.get("occupationId", "")))
	matches.sort()
	return matches[0] if matches.size() == 1 else ""


func _staffing_resident_ids(
	staffing_snapshot: Dictionary,
	occupation_id: String,
) -> Array[String]:
	var result: Array[String] = []
	for post_value: Variant in staffing_snapshot.get("posts", []) as Array:
		var post := post_value as Dictionary
		if String(post.get("occupationId", "")) != occupation_id:
			continue
		for resident_id_value: Variant in post.get(
			"responsibleResidentIds",
			[],
		) as Array:
			var resident_id := String(resident_id_value)
			if not resident_id.is_empty() and not result.has(resident_id):
				result.append(resident_id)
		break
	result.sort()
	return result


func _resident_ids_for_occupation(
	world_data: Dictionary,
	residents: Dictionary,
	occupation_id: String,
) -> Array[String]:
	var result: Array[String] = []
	if occupation_id.is_empty():
		return result
	var occupation: Dictionary = {}
	for occupation_value: Variant in world_data.get("occupations", []) as Array:
		if (
			occupation_value is Dictionary
			and String((occupation_value as Dictionary).get("occupationId", ""))
				== occupation_id
		):
			occupation = occupation_value as Dictionary
			break
	if occupation.is_empty():
		return result
	var labels: Array = [String(occupation.get("label", ""))]
	labels.append_array(occupation.get("aliases", []) as Array)
	for resident_id_value: Variant in residents:
		var resident_id := String(resident_id_value)
		var social_state := (
			(residents.get(resident_id, {}) as Dictionary).get("socialState", {})
			as Dictionary
		)
		if labels.has(String(social_state.get("job", ""))):
			result.append(resident_id)
	result.sort()
	return result


func _arrays_overlap(left: Array, right: Array) -> bool:
	for value: Variant in left:
		if right.has(value):
			return true
	return false


func _failure(error_code: String, error: String) -> Dictionary:
	return {"ok": false, "errorCode": error_code, "errors": [error]}
