class_name TownOccupationServiceRequestRuntime
extends RefCounted


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const SERVICE_QUERY := preload(
	"res://world/runtime/work/TownOccupationServiceQuery.gd"
)


static func entry_failure(
	running: bool,
	kind: String,
	requester_id: String,
	definition: Dictionary,
) -> Dictionary:
	if not running:
		return _failure("WORLD_NOT_RUNNING", "世界尚未运行")
	if requester_id.is_empty():
		return _failure(
			"OCCUPATION_SERVICE_REQUESTER_UNKNOWN",
			"职业服务请求缺少真实居民",
		)
	if definition.is_empty():
		return _failure(
			"OCCUPATION_SERVICE_KIND_UNKNOWN",
			"未知职业服务类型：%s" % kind,
		)
	return {}


static func prepare(
	spec: Dictionary,
	requester_id: String,
	requester: Dictionary,
	definition: Dictionary,
	condition_context: Dictionary,
	clinic_available: bool,
	request_now: int,
	dining_wait_deadline: int,
	cargo_inventory: TownCargoInventoryRuntime,
	occupation_services: TownOccupationServiceRuntime,
) -> Dictionary:
	var kind := String(spec.get("kind", "")).strip_edges()
	var prepared_spec := spec.duplicate(true)
	var prepared_definition := definition.duplicate(true)
	var context := (
		(spec.get("context", {}) as Dictionary).duplicate(true)
		if spec.get("context", {}) is Dictionary
		else {}
	)
	if kind == "clinic":
		if condition_context.is_empty():
			return _failure(
				"CLINIC_ACTIVE_CONDITION_REQUIRED",
				"居民当前没有需要看诊的真实身体状况",
			)
		context.merge(
			condition_context.get("context", {}) as Dictionary,
			true,
		)
		if String(prepared_spec.get("subjectRef", "")).strip_edges().is_empty():
			prepared_spec["subjectRef"] = String(
				condition_context.get("subjectRef", "身体不适"),
			)
		if not clinic_available:
			return _failure(
				"CLINIC_SERVICE_UNAVAILABLE",
				"诊所当前没有可以接诊的医生",
			)
	if kind == "performance":
		if bool(context.get("generatedFromPublicEvent", false)):
			prepared_definition["sourceKind"] = "public_event"
		elif bool(context.get("generatedFromResidentInvitation", false)):
			prepared_definition["sourceKind"] = "resident_invitation"
	var item_id := String(prepared_spec.get(
		"itemId",
		prepared_definition.get("defaultItemId", ""),
	)).strip_edges()
	var research_record_id := String(
		context.get("researchRecordId", ""),
	).strip_edges()
	var requests_research_booklet := (
		(kind == "clinic" and not research_record_id.is_empty())
		or (
			kind == "grocer_sale"
			and item_id == CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET
		)
	)
	var research_accession_exists := (
		not research_record_id.is_empty()
		and not (
			occupation_services.accession_for_record(
				research_record_id,
			) as Dictionary
		).is_empty()
	)
	if requests_research_booklet and not research_accession_exists:
		return _failure(
			"RESEARCH_BOOKLET_SOURCE_INVALID",
			"研究参考必须引用已经入藏的真实研究记录",
		)
	var subject_ref := String(
		prepared_spec.get("subjectRef", ""),
	).strip_edges()
	if kind == "clinic" and subject_ref.is_empty():
		subject_ref = TownOccupationServiceDefinition.clinic_default_subject_ref(
			requester,
		)
	var meal_period_ref := SERVICE_QUERY.meal_period_source_ref(request_now)
	if kind == "dining_order" and meal_period_ref.is_empty():
		return _failure(
			"DINING_SERVICE_CLOSED",
			"食堂当前不在供餐餐次内",
		)
	context["mealPeriodRef"] = meal_period_ref
	if kind in ACTION_SUPPORT.OCCUPATION_SERVICE_PRESENCE_REQUIRED_KINDS:
		if SERVICE_QUERY.preorder_needed(
			cargo_inventory,
			occupation_services,
			kind,
			item_id,
			String(prepared_definition.get("placeId", "")),
		):
			context["customerServiceMode"] = "preorder"
			context["preorderExpiresAtMinute"] = request_now + 1440
			context["customerNotifiedAtMinute"] = -1
		else:
			context["customerServiceMode"] = "onsite_wait"
			context["onsiteWaitUntilMinute"] = request_now + (
				ACTIVITY_SCALARS.onsite_service_wait_minutes(kind)
			)
			context["customerAbsentSinceMinute"] = -1
	if kind == "dining_order":
		context["onsiteWaitUntilMinute"] = dining_wait_deadline
		var dining_already_completed := (
			occupation_services.has_dining_order_completed_for_resident_meal_period(
				requester_id,
				meal_period_ref,
			)
			or not SERVICE_QUERY.dining_order_for_resident_meal_period(
				occupation_services,
				requester_id,
				request_now,
				["completed"],
			).is_empty()
		)
		if dining_already_completed:
			return _failure(
				"DINING_MEAL_ALREADY_SERVED",
				"本餐次已经完成取餐",
			)
	return {
		"ok": true,
		"kind": kind,
		"definition": prepared_definition,
		"context": context,
		"itemId": item_id,
		"subjectRef": subject_ref,
		"researchRecordId": research_record_id,
		"requestsResearchBooklet": requests_research_booklet,
		"requesterResidentId": requester_id,
		"requestNow": request_now,
	}


static func create_request(
	occupation_services: TownOccupationServiceRuntime,
	prepared: Dictionary,
) -> Dictionary:
	var definition := prepared.get("definition", {}) as Dictionary
	return occupation_services.create_request({
		"kind": String(prepared.get("kind", "")),
		"requesterResidentId": String(
			prepared.get("requesterResidentId", ""),
		),
		"subjectRef": String(prepared.get("subjectRef", "")),
		"itemId": String(prepared.get("itemId", "")),
		"placeId": String(definition.get("placeId", "")),
		"context": (
			prepared.get("context", {}) as Dictionary
		).duplicate(true),
		"createdAtMinute": int(prepared.get("requestNow", 0)),
	}) as Dictionary


static func create_non_place_task(
	work_tasks: TownWorkTaskRuntime,
	request: Dictionary,
	definition: Dictionary,
	requester_id: String,
	absolute_minute: int,
) -> Dictionary:
	var request_id := String(request.get("requestId", ""))
	var target_kind := String(definition.get("targetKind", ""))
	var targets: Array = [{
		"kind": target_kind,
		"ref": (
			String(definition.get("targetRef", ""))
			if target_kind == "audience_area"
			else request_id
		),
	}]
	if target_kind == "audience_area":
		targets.append({"kind": "service_request", "ref": request_id})
	else:
		targets.append({"kind": "resident", "ref": requester_id})
	return work_tasks.create_task_for_occupations(
		{
			"taskId": "occupation-service-task:%s" % request_id,
			"capability": String(definition.get("capability", "")),
			"sourceKind": String(definition.get("sourceKind", "")),
			"sourceRef": request_id,
			"targets": targets,
			"requestedResultKind": String(definition.get("resultKind", "")),
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY[
				"occupation_service_request"
			],
		},
		[String(definition.get("occupationId", ""))],
	) as Dictionary


static func configure_created_task(
	occupation_services: TownOccupationServiceRuntime,
	work_tasks: TownWorkTaskRuntime,
	clinic_interviews: TownClinicInterviewPolicy,
	prepared: Dictionary,
	task: Dictionary,
	request_id: String,
) -> Dictionary:
	var kind := String(prepared.get("kind", ""))
	var item_id := String(prepared.get("itemId", ""))
	var requester_id := String(prepared.get("requesterResidentId", ""))
	var context := prepared.get("context", {}) as Dictionary
	if kind == "cafe_order" and item_id == CONTENT_CATALOG.ITEM_BREWED_COFFEE:
		var process_result := work_tasks.configure_initial_process(
			String(task.get("taskId", "")),
			int(task.get("revision", 0)),
			"awaiting_brew",
			{
				"nextActivityId": "activity_cafe_brew_coffee",
				"serviceRequestId": request_id,
				"itemId": item_id,
			},
		) as Dictionary
		if process_result.get("ok") != true:
			occupation_services.cancel_request(
				request_id,
				"咖啡订单过程初始化失败",
			)
			return {"ok": false, "failure": process_result}
		task = process_result.get("task", {}) as Dictionary
	if kind == "clinic":
		var medical_context := clinic_interviews.create_context(
			request_id,
			requester_id,
			(context.get("conditionIds", []) as Array).duplicate(),
			String(prepared.get("subjectRef", "")),
		) as Dictionary
		if medical_context.is_empty():
			occupation_services.cancel_request(
				request_id,
				"问诊上下文初始化失败",
			)
			return {
				"ok": false,
				"failure": _failure(
					"CLINIC_INTERVIEW_CONTEXT_INVALID",
					"看诊请求无法建立问诊上下文",
				),
			}
		var merged := occupation_services.merge_request_context(
			request_id,
			{"medicalInterview": medical_context},
		) as Dictionary
		if merged.get("ok") != true:
			occupation_services.cancel_request(
				request_id,
				"问诊上下文写入失败",
			)
			return {"ok": false, "failure": merged}
		var interview_process := work_tasks.configure_initial_process(
			String(task.get("taskId", "")),
			int(task.get("revision", 0)),
			"awaiting_interview",
			{
				"nextActivityId": "medical_interview",
				"serviceRequestId": request_id,
			},
		) as Dictionary
		if interview_process.get("ok") != true:
			occupation_services.cancel_request(
				request_id,
				"问诊过程初始化失败",
			)
			return {"ok": false, "failure": interview_process}
		task = interview_process.get("task", {}) as Dictionary
	return {"ok": true, "task": task}


static func configure_and_attach_task(
	occupation_services: TownOccupationServiceRuntime,
	work_tasks: TownWorkTaskRuntime,
	clinic_interviews: TownClinicInterviewPolicy,
	prepared: Dictionary,
	task: Dictionary,
	request_id: String,
) -> Dictionary:
	var configured := configure_created_task(
		occupation_services,
		work_tasks,
		clinic_interviews,
		prepared,
		task,
		request_id,
	) as Dictionary
	if configured.get("ok") != true:
		return {
			"ok": false,
			"failure": configured.get("failure", {}) as Dictionary,
		}
	task = configured.get("task", task) as Dictionary
	var attached := occupation_services.attach_task(
		request_id,
		String(task.get("taskId", "")),
	) as Dictionary
	if attached.get("ok") != true:
		return {"ok": false, "failure": attached}
	return {
		"ok": true,
		"request": attached.get("request", {}) as Dictionary,
		"task": task,
	}


static func cancelled_failure(
	occupation_services: TownOccupationServiceRuntime,
	request_id: String,
	reason: String,
	failure: Dictionary,
) -> Dictionary:
	occupation_services.cancel_request(request_id, reason)
	return failure


static func success(request: Dictionary, task: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"changed": true,
		"request": request.duplicate(true),
		"task": task.duplicate(true),
	}


static func reused_dining_order(
	work_tasks: TownWorkTaskRuntime,
	request: Dictionary,
) -> Dictionary:
	return {
		"ok": true,
		"changed": false,
		"request": request.duplicate(true),
		"task": work_tasks.task(
			String(request.get("taskId", "")),
		).duplicate(true),
	}


static func hold_dining_order(
	occupation_services: TownOccupationServiceRuntime,
	work_tasks: TownWorkTaskRuntime,
	request_id: String,
	wait_reason: String,
	meal_preparation_task_id: String,
) -> Dictionary:
	var waiting := occupation_services.mark_waiting(
		request_id,
		wait_reason,
	) as Dictionary
	return {
		"ok": waiting.get("ok") == true,
		"changed": waiting.get("ok") == true,
		"errorCode": String(waiting.get("errorCode", "")),
		"request": (
			waiting.get("request", {}) as Dictionary
		).duplicate(true),
		"task": work_tasks.task(meal_preparation_task_id).duplicate(true),
	}


static func _failure(error_code: String, error: String) -> Dictionary:
	return RESULT_SHAPES.failure_with(error_code, false, [error])
