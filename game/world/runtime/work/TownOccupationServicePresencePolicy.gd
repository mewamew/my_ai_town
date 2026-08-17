class_name TownOccupationServicePresencePolicy
extends RefCounted


static func resolve_mode(
	request: Dictionary,
	absolute_minute: int,
	preorder_needed: bool,
	onsite_wait_minutes: int,
) -> Dictionary:
	var context := (
		request.get("context", {}) as Dictionary
	).duplicate(true)
	var mode := String(context.get("customerServiceMode", ""))
	if not mode.is_empty():
		return {"mode": mode, "patch": {}}
	mode = "preorder" if preorder_needed else "onsite_wait"
	var created_at := int(request.get("createdAtMinute", absolute_minute))
	var patch := {"customerServiceMode": mode}
	if mode == "preorder":
		patch["preorderExpiresAtMinute"] = created_at + 1440
		patch["customerNotifiedAtMinute"] = -1
	else:
		patch["onsiteWaitUntilMinute"] = created_at + onsite_wait_minutes
		patch["customerAbsentSinceMinute"] = -1
	return {"mode": mode, "patch": patch}


static func evaluate(
	request: Dictionary,
	requester: Dictionary,
	absolute_minute: int,
	mode_resolution: Dictionary,
	kind_staffed: bool,
	clinic_executable: bool,
	queue_advancing: bool,
	deadline_applies: bool,
	onsite_wait_minutes: int,
) -> Dictionary:
	var kind := String(request.get("kind", ""))
	if kind == "clinic" and not clinic_executable:
		return _cancel("诊所当前没有可以继续接诊的医生")
	var context := (
		request.get("context", {}) as Dictionary
	).duplicate(true)
	var patches: Array[Dictionary] = []
	var migration_patch := mode_resolution.get("patch", {}) as Dictionary
	if not migration_patch.is_empty():
		patches.append(migration_patch.duplicate(true))
		context.merge(migration_patch, true)
	var mode := String(mode_resolution.get("mode", ""))
	if mode == "onsite_wait" and not kind_staffed:
		return _cancel_with_patches("对应岗位当前无人值守", patches)
	var at_service_place := (
		not requester.is_empty()
		and String(requester.get("currentPlace", ""))
		== String(request.get("placeId", ""))
	)
	if mode == "preorder":
		if absolute_minute >= int(
			context.get("preorderExpiresAtMinute", absolute_minute + 1),
		):
			return _cancel_with_patches(
				"预订超过一天仍未领取",
				patches,
			)
		return {
			"action": "schedule_worker" if at_service_place else "notify_preorder",
			"contextPatches": patches,
		}
	if kind != "dining_order" and queue_advancing:
		var extended_wait_until := maxi(
			int(context.get("onsiteWaitUntilMinute", absolute_minute)),
			absolute_minute + onsite_wait_minutes,
		)
		if extended_wait_until != int(
			context.get("onsiteWaitUntilMinute", -1),
		):
			var extension := {
				"onsiteWaitUntilMinute": extended_wait_until,
			}
			patches.append(extension)
			context.merge(extension, true)
	if (
		deadline_applies
		and absolute_minute >= int(
			context.get("onsiteWaitUntilMinute", absolute_minute + 1),
		)
	):
		if kind == "dining_order":
			return {"action": "takeaway", "contextPatches": patches}
		return _cancel_with_patches("等待服务时间已结束", patches)
	if at_service_place:
		if int(context.get("customerAbsentSinceMinute", -1)) >= 0:
			patches.append({"customerAbsentSinceMinute": -1})
		return {
			"action": "schedule_worker",
			"contextPatches": patches,
			"resumeRequest": (
				String(request.get("state", "")) == "waiting"
				and String(request.get("waitReason", ""))
				== "请求人尚未到达服务地点"
			),
		}
	var absent_since := int(context.get("customerAbsentSinceMinute", -1))
	if absent_since < 0:
		absent_since = absolute_minute
		patches.append({"customerAbsentSinceMinute": absent_since})
	return {
		"action": (
			"pause_and_cancel"
			if absolute_minute - absent_since >= 5
			else "pause"
		),
		"cancelReason": "请求人已经离开服务地点",
		"contextPatches": patches,
	}


static func queue_is_advancing(
	request: Dictionary,
	projected_tasks: Array[Dictionary],
	active_task_ids: Dictionary,
	work_tasks: TownWorkTaskRuntime,
	occupation_services: TownOccupationServiceRuntime,
) -> bool:
	var place_id := String(request.get("placeId", ""))
	for projected_task: Dictionary in projected_tasks:
		var task_id := String(projected_task.get("task_id", ""))
		if not active_task_ids.has(task_id):
			continue
		var active_task := work_tasks.task(task_id) as Dictionary
		var active_request := occupation_services.request(
			String(active_task.get("sourceRef", "")),
		) as Dictionary
		if (
			String(active_request.get("placeId", "")) == place_id
			and String(
				(active_request.get("context", {}) as Dictionary).get(
					"customerServiceMode",
					"",
				),
			) == "onsite_wait"
		):
			return true
	return false


static func wait_deadline_applies(
	request: Dictionary,
	task: Dictionary,
	clinic_has_active_execution: bool,
	assigned_is_processing: bool,
	assigned_is_heading: bool,
) -> bool:
	if String(request.get("kind", "")) == "clinic":
		return not clinic_has_active_execution
	if not (request.get("outcome", {}) as Dictionary).is_empty():
		return false
	if String(request.get("taskId", "")).is_empty():
		return true
	if String(task.get("state", "")) not in ["accepted", "in_progress"]:
		return true
	return not assigned_is_processing and not assigned_is_heading


static func _cancel(reason: String) -> Dictionary:
	return _cancel_with_patches(reason, [])


static func _cancel_with_patches(
	reason: String,
	patches: Array,
) -> Dictionary:
	return {
		"action": "cancel",
		"cancelReason": reason,
		"contextPatches": patches.duplicate(true),
	}
