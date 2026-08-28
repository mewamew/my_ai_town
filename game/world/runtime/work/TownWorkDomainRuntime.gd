class_name TownWorkDomainRuntime
extends RefCounted


signal production_task_created(task: Dictionary)


const STATE_PROJECTION := preload(
	"res://world/runtime/work/TownWorkStateProjection.gd"
)
const CARGO_LOGISTICS := preload(
	"res://world/runtime/work/TownCargoLogisticsRuntime.gd"
)
const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const SERVICE_QUERY := preload(
	"res://world/runtime/work/TownOccupationServiceQuery.gd"
)
const PRODUCTION_TASK_SYNC := preload(
	"res://world/runtime/work/TownProductionTaskSyncRuntime.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const STAFFING_MATTER_PROJECTION := preload(
	"res://world/runtime/work/TownStaffingMatterProjection.gd"
)
const SERVICE_DEFINITION := preload(
	"res://world/runtime/work/TownOccupationServiceDefinition.gd"
)
const SERVICE_PRESENCE_POLICY := preload(
	"res://world/runtime/work/TownOccupationServicePresencePolicy.gd"
)
const SERVICE_LIFECYCLE := preload(
	"res://world/runtime/work/TownOccupationServiceLifecycleRuntime.gd"
)
const WORK_TASK_COMMAND := preload(
	"res://world/runtime/work/TownWorkTaskCommandRuntime.gd"
)
const PERIODIC_SERVICE_REQUEST := preload(
	"res://world/runtime/work/TownPeriodicServiceRequestRuntime.gd"
)
const PLACE_SERVICE_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceRuntime.gd"
)

var tasks: TownWorkTaskRuntime = TownWorkTaskRuntime.new()
var staffing: TownStaffingRuntime = TownStaffingRuntime.new()
var cargo: TownCargoInventoryRuntime = TownCargoInventoryRuntime.new()
var production: TownProductionRuntime = TownProductionRuntime.new()
var services: TownOccupationServiceRuntime = TownOccupationServiceRuntime.new()
var place_services: TownPlaceServiceRuntime = PLACE_SERVICE_RUNTIME.new()


func install(
	next_tasks: TownWorkTaskRuntime,
	next_staffing: TownStaffingRuntime,
	next_cargo: TownCargoInventoryRuntime,
	next_production: TownProductionRuntime,
	next_services: TownOccupationServiceRuntime,
) -> void:
	tasks = next_tasks
	staffing = next_staffing
	cargo = next_cargo
	production = next_production
	services = next_services


func install_restored_state(
	next_tasks: TownWorkTaskRuntime,
	next_cargo: TownCargoInventoryRuntime,
	next_production: TownProductionRuntime,
	next_services: TownOccupationServiceRuntime,
) -> void:
	tasks = next_tasks
	cargo = next_cargo
	production = next_production
	services = next_services


func reset_after_stop() -> void:
	staffing = TownStaffingRuntime.new()
	cargo = TownCargoInventoryRuntime.new()
	production = TownProductionRuntime.new()
	services = TownOccupationServiceRuntime.new()
	place_services.reset()


func reset_staffing() -> void:
	staffing = TownStaffingRuntime.new()


func staffing_snapshot(running: bool) -> Dictionary:
	return STATE_PROJECTION.staffing(running, staffing)


func cargo_snapshot(running: bool) -> Dictionary:
	return STATE_PROJECTION.cargo_inventory(running, cargo)


func service_snapshot(running: bool) -> Dictionary:
	return STATE_PROJECTION.occupation_services(running, services)


func service_request(running: bool, request_id: String) -> Dictionary:
	return STATE_PROJECTION.occupation_service_request(
		running,
		services,
		request_id,
	)


func production_snapshot(running: bool) -> Dictionary:
	return production.snapshot() as Dictionary if running else {}


func create_cargo_lot(
	spec: Dictionary,
	origin_kind: String,
	absolute_minute: int,
	delivery_post_vacant: bool,
	owners: Dictionary,
	resident_id_by_name: Dictionary,
	residents: Dictionary,
	resident_order: Array[String],
) -> Dictionary:
	var result := CARGO_LOGISTICS.create_lot(
		cargo,
		tasks,
		spec,
		origin_kind,
		absolute_minute,
		delivery_post_vacant,
		owners,
		resident_id_by_name,
		residents,
		resident_order,
	) as Dictionary
	if result.get("ok") == true:
		var task := result.get("task", {}) as Dictionary
		result["cargoCommand"] = {
			"logLabel": "货批生成",
			"logStatus": String(result.get("logStatus", "ongoing")),
			"reserveOccupationId": (
				"occupation_delivery_worker"
				if String(task.get("capability", "")) == "cargo.deliver"
				else ""
			),
		}
	return result


func pickup_cargo_lot(
	lot_id: String,
	resident_ref: String,
	resident_id: String,
	resident_place: String,
	absolute_minute: int,
	authorized: bool,
	acceptance_occupation_id: String,
) -> Dictionary:
	if resident_id.is_empty():
		return RESULT_SHAPES.failure_with(
			"WORLD_RESIDENT_UNKNOWN",
			false,
			["未知居民：%s" % resident_ref],
		)
	var result := CARGO_LOGISTICS.pickup(
		cargo,
		tasks,
		lot_id,
		resident_id,
		resident_place,
		absolute_minute,
		authorized,
		acceptance_occupation_id,
	) as Dictionary
	if result.get("ok") == true:
		result["scheduleResidentIds"] = [resident_id]
		result["cargoCommand"] = {
			"logLabel": "货批取货",
			"logActorResidentId": resident_id,
			"logStatus": "ongoing",
		}
	return result


func deliver_cargo_lot(
	lot_id: String,
	resident_ref: String,
	resident_id: String,
	resident_place: String,
	absolute_minute: int,
	owners: Dictionary,
) -> Dictionary:
	if resident_id.is_empty():
		return RESULT_SHAPES.failure_with(
			"WORLD_RESIDENT_UNKNOWN",
			false,
			["未知居民：%s" % resident_ref],
		)
	var result := CARGO_LOGISTICS.deliver(
		cargo,
		tasks,
		lot_id,
		resident_id,
		resident_place,
		absolute_minute,
		owners,
	) as Dictionary
	if result.get("ok") == true:
		result["cargoCommand"] = {
			"logLabel": "货批到货",
			"logActorResidentId": resident_id,
			"logStatus": (
				"waiting"
				if not (result.get("receiptTask", {}) as Dictionary).is_empty()
				else "completed"
			),
		}
	return result


func has_active_cargo_to_place(item_id: String, place_id: String) -> bool:
	return PRODUCTION_TASK_SYNC.has_active_cargo_to_place(
		cargo,
		item_id,
		place_id,
	)


func work_task_is_currently_available(
	task: Dictionary,
	residents: Dictionary,
) -> bool:
	return SERVICE_QUERY.work_task_is_currently_available(
		task,
		services,
		residents,
	)


func primary_occupation_id(
	resident: Dictionary,
	world_data: Dictionary,
) -> String:
	var occupation_name := String(
		(resident.get("socialState", {}) as Dictionary).get("job", ""),
	)
	for value: Variant in world_data.get("occupations", []) as Array:
		if value is not Dictionary:
			continue
		var occupation := value as Dictionary
		if (
			String(occupation.get("label", "")) == occupation_name
			or (occupation.get("aliases", []) as Array).has(occupation_name)
		):
			return String(occupation.get("occupationId", ""))
	return ""


func occupation_ids_for_resident(
	resident_id: String,
	resident: Dictionary,
	world_data: Dictionary,
	absolute_minute: int,
) -> Array[String]:
	var result: Array[String] = []
	var attendance := resident.get("attendanceState", {}) as Dictionary
	if (
		String(attendance.get("status", "available")) == "on_leave"
		and int(attendance.get("untilMinute", -1)) > absolute_minute
	):
		return result
	var primary_id := primary_occupation_id(resident, world_data)
	if not primary_id.is_empty():
		result.append(primary_id)
	for occupation_value: Variant in staffing.active_assignment_occupation_ids(
		resident_id,
		absolute_minute,
	) as Array:
		var occupation_id := String(occupation_value)
		if not occupation_id.is_empty() and not result.has(occupation_id):
			result.append(occupation_id)
	return result


func resident_can_accept_work_task(
	resident_id: String,
	task: Dictionary,
	resident: Dictionary,
	world_data: Dictionary,
	resident_is_present: bool,
	absolute_minute: int,
) -> bool:
	if task.is_empty() or not resident_is_present:
		return false
	var attendance := resident.get("attendanceState", {}) as Dictionary
	if (
		String(attendance.get("status", "available")) == "on_leave"
		and int(attendance.get("untilMinute", -1)) > absolute_minute
	):
		return false
	var occupation_ids := occupation_ids_for_resident(
		resident_id,
		resident,
		world_data,
		absolute_minute,
	)
	if (task.get("eligibleResidentIds", []) as Array).has(resident_id):
		return true
	var primary_id := primary_occupation_id(resident, world_data)
	var capability := String(task.get("capability", ""))
	for occupation_id: String in occupation_ids:
		if (
			(task.get("eligibleOccupationIds", []) as Array).has(occupation_id)
			and (
				occupation_id == primary_id
				or staffing.active_assignment_allows_capability(
					resident_id,
					occupation_id,
					capability,
					absolute_minute,
				)
			)
		):
			return true
	return false


func task_acceptance_occupation_id(
	resident_id: String,
	task: Dictionary,
	resident: Dictionary,
	world_data: Dictionary,
	absolute_minute: int,
) -> String:
	var primary_id := primary_occupation_id(resident, world_data)
	var capability := String(task.get("capability", ""))
	for occupation_id: String in occupation_ids_for_resident(
		resident_id,
		resident,
		world_data,
		absolute_minute,
	):
		if (
			(task.get("eligibleOccupationIds", []) as Array).has(occupation_id)
			and (
				occupation_id == primary_id
				or staffing.active_assignment_allows_capability(
					resident_id,
					occupation_id,
					capability,
					absolute_minute,
				)
			)
		):
			return occupation_id
	return primary_id


func reserve_work_task(
	task: Dictionary,
	preferred_occupation_id: String,
	resident_order: Array[String],
	residents: Dictionary,
	world_data: Dictionary,
	present_resident_ids: Array[String],
	absolute_minute: int,
) -> Dictionary:
	var present := {}
	for resident_id: String in present_resident_ids:
		present[resident_id] = true
	var candidates: Array[Dictionary] = []
	for resident_id: String in resident_order:
		var resident := residents.get(resident_id, {}) as Dictionary
		if not resident_can_accept_work_task(
			resident_id,
			task,
			resident,
			world_data,
			present.has(resident_id),
			absolute_minute,
		):
			continue
		var occupation_ids := occupation_ids_for_resident(
			resident_id,
			resident,
			world_data,
			absolute_minute,
		)
		candidates.append({
			"residentId": resident_id,
			"acceptanceOccupationId": task_acceptance_occupation_id(
				resident_id,
				task,
				resident,
				world_data,
				absolute_minute,
			),
			"canUsePreferredOccupation": (
				occupation_ids.has(preferred_occupation_id)
				and (task.get("eligibleOccupationIds", []) as Array).has(
					preferred_occupation_id,
				)
			),
		})
	return WORK_TASK_COMMAND.reserve(
		tasks,
		task,
		preferred_occupation_id,
		candidates,
	) as Dictionary


func claim_specific_work_task(
	task: Dictionary,
	occupation_id: String,
	resident_id: String,
	residents: Dictionary,
) -> Dictionary:
	if not work_task_is_currently_available(task, residents):
		return {"ok": false, "errorCode": "WORK_TASK_NOT_AVAILABLE"}
	var task_id := String(task.get("taskId", ""))
	var state := String(task.get("state", ""))
	var revision := int(task.get("revision", 0))
	var selected := task
	if state in ["open", "waiting"]:
		var accepted := tasks.accept_task(
			task_id,
			resident_id,
			occupation_id,
			revision,
		) as Dictionary
		if accepted.get("ok") != true:
			return accepted
		selected = accepted.get("task", {}) as Dictionary
		state = "accepted"
		revision = int(selected.get("revision", 0))
	if state == "accepted":
		return tasks.start_task(
			task_id,
			resident_id,
			revision,
		) as Dictionary
	if state == "in_progress":
		return {"ok": true, "task": selected.duplicate(true)}
	return {"ok": false, "errorCode": "WORK_TASK_STATE_INVALID"}


func available_work_tasks(tasks_value: Array, residents: Dictionary) -> Array:
	var result: Array = []
	for value: Variant in tasks_value:
		var task := value as Dictionary
		if work_task_is_currently_available(task, residents):
			result.append(task)
	return result


func occupation_service_preorder_needed(
	kind: String,
	item_id: String,
	place_id: String,
) -> bool:
	return SERVICE_QUERY.preorder_needed(
		cargo,
		services,
		kind,
		item_id,
		place_id,
	)


func active_presence_requests() -> Array[Dictionary]:
	return SERVICE_QUERY.active_presence_requests(services)


func onsite_service_wait_minutes(kind: String) -> int:
	return ACTIVITY_SCALARS.onsite_service_wait_minutes(kind)


func evaluate_presence_plan(
	request: Dictionary,
	requester: Dictionary,
	absolute_minute: int,
	service_staffed: bool,
	clinic_executable: bool,
	queue_advancing: bool,
	deadline_applies: bool,
) -> Dictionary:
	var kind := String(request.get("kind", ""))
	var wait_minutes := onsite_service_wait_minutes(kind)
	var mode_resolution := _presence_mode_resolution(request, absolute_minute)
	var mode := String(mode_resolution.get("mode", ""))
	var plan := SERVICE_PRESENCE_POLICY.evaluate(
		request,
		requester,
		absolute_minute,
		mode_resolution,
		(
			service_staffed
			if mode == "onsite_wait"
			else true
		),
		clinic_executable,
		queue_advancing if mode == "onsite_wait" and kind != "dining_order" else false,
		deadline_applies if mode == "onsite_wait" else false,
		wait_minutes,
	) as Dictionary
	var request_id := String(request.get("requestId", ""))
	for patch_value: Variant in plan.get("contextPatches", []) as Array:
		services.merge_request_context(request_id, patch_value as Dictionary)
	if bool(plan.get("resumeRequest", false)):
		services.resume_request(request_id)
	return plan


func occupation_service_presence_mode(
	request: Dictionary,
	absolute_minute: int,
) -> String:
	return String(
		_presence_mode_resolution(request, absolute_minute).get("mode", ""),
	)


func _presence_mode_resolution(
	request: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var kind := String(request.get("kind", ""))
	var context := request.get("context", {}) as Dictionary
	return SERVICE_PRESENCE_POLICY.resolve_mode(
		request,
		absolute_minute,
		(
			occupation_service_preorder_needed(
				kind,
				String(request.get("itemId", "")),
				String(request.get("placeId", "")),
			)
			if String(context.get("customerServiceMode", "")).is_empty()
			else false
		),
		onsite_service_wait_minutes(kind),
	)


func service_task(request: Dictionary) -> Dictionary:
	return tasks.task(String(request.get("taskId", ""))) as Dictionary


func service_worker_schedule_context(
	request: Dictionary,
	interrupt_priority: int,
) -> Dictionary:
	var task := service_task(request)
	return {
		"taskId": String(task.get("taskId", "")),
		"assignedResidentId": String(task.get("assignedResidentId", "")),
		"occupationId": String(SERVICE_DEFINITION.definition(
			String(request.get("kind", "")),
		).get("occupationId", "")),
		"canInterrupt": int(task.get("priority", 0)) >= interrupt_priority,
	}


func onsite_service_queue_is_advancing(
	request: Dictionary,
	projected_tasks: Array[Dictionary],
	active_task_ids: Dictionary,
) -> bool:
	return SERVICE_PRESENCE_POLICY.queue_is_advancing(
		request,
		projected_tasks,
		active_task_ids,
		tasks,
		services,
	)


func occupation_service_wait_deadline_applies(
	request: Dictionary,
	clinic_has_active_execution: bool,
	assigned_is_processing: bool,
	assigned_is_heading: bool,
) -> bool:
	return SERVICE_PRESENCE_POLICY.wait_deadline_applies(
		request,
		service_task(request),
		clinic_has_active_execution,
		assigned_is_processing,
		assigned_is_heading,
	)


func absent_service_pause_plan(
	request: Dictionary,
	bindings: Dictionary,
) -> Dictionary:
	var task := service_task(request)
	if task.is_empty():
		return {}
	var assigned_id := String(task.get("assignedResidentId", ""))
	return {
		"assignedResidentId": assigned_id,
		"bindingKeys": SERVICE_LIFECYCLE.matching_binding_keys(
			String(task.get("taskId", "")),
			assigned_id,
			bindings,
		),
	}


func commit_absent_service_pause(request: Dictionary) -> void:
	SERVICE_LIFECYCLE.pause_after_interruption(services, tasks, request)


func occupation_service_cancellation_plan(
	request: Dictionary,
	bindings: Dictionary,
	conversations: Dictionary,
) -> Dictionary:
	return SERVICE_LIFECYCLE.cancellation_plan(
		request,
		service_task(request),
		bindings,
		conversations,
		SERVICE_DEFINITION.definition(String(request.get("kind", ""))),
	)


func commit_occupation_service_cancellation(
	request_id: String,
	reason: String,
) -> void:
	SERVICE_LIFECYCLE.commit_cancellation(
		services,
		tasks,
		request_id,
		service_task(services.request(request_id) as Dictionary),
		reason,
	)


func unreserved_preorder_inventory_quantity(
	place_id: String,
	item_id: String,
) -> int:
	return SERVICE_QUERY.unreserved_preorder_inventory_quantity(
		cargo,
		services,
		place_id,
		item_id,
	)


func occupation_post_is_vacant(occupation_id: String) -> bool:
	return STATE_PROJECTION.occupation_post_is_vacant(staffing, occupation_id)


func staffing_matter_plan(
	running: bool,
	resident_order: Array[String],
	primary_occupation_by_resident: Dictionary,
	available_resident_ids: Array[String],
	max_candidates: int,
	source_revision: int,
	absolute_minute: int,
) -> Dictionary:
	return STAFFING_MATTER_PROJECTION.plan(
		staffing_snapshot(running),
		resident_order,
		primary_occupation_by_resident,
		available_resident_ids,
		max_candidates,
		source_revision,
		absolute_minute,
	)


func staffing_matter_plan_for_residents(
	running: bool,
	resident_order: Array[String],
	residents: Dictionary,
	world_data: Dictionary,
	max_candidates: int,
	source_revision: int,
	absolute_minute: int,
) -> Dictionary:
	var primary_occupation_by_resident := {}
	var available_resident_ids: Array[String] = []
	for resident_id: String in resident_order:
		var resident := residents.get(resident_id, {}) as Dictionary
		primary_occupation_by_resident[resident_id] = primary_occupation_id(
			resident,
			world_data,
		)
		var attendance := resident.get("attendanceState", {}) as Dictionary
		if not (
			String(attendance.get("status", "available")) == "on_leave"
			and int(attendance.get("untilMinute", -1)) > absolute_minute
		):
			available_resident_ids.append(resident_id)
	return staffing_matter_plan(
		running,
		resident_order,
		primary_occupation_by_resident,
		available_resident_ids,
		max_candidates,
		source_revision,
		absolute_minute,
	)


func staffing_candidate_ability_score(
	resident_id: String,
	primary_occupation_id: String,
) -> int:
	var post := staffing.post_for_occupation(primary_occupation_id) as Dictionary
	if primary_occupation_id.is_empty():
		return 100
	if (
		String(post.get("status", "")) == "duplicate"
		and (post.get("assignedResidentIds", []) as Array).has(resident_id)
	):
		return 100
	return 10


func occupation_id_for_activity(
	occupation_ids: Array[String],
	activity_id: String,
	resident_id: String,
	fallback_occupation_id: String,
	absolute_minute: int,
) -> String:
	for occupation_id: String in occupation_ids:
		for task_value: Variant in tasks.tasks_for_activity(
			occupation_id,
			activity_id,
			resident_id,
		) as Array:
			var capability := String((task_value as Dictionary).get("capability", ""))
			if (
				occupation_id == fallback_occupation_id
				or staffing.active_assignment_allows_capability(
					resident_id,
					occupation_id,
					capability,
					absolute_minute,
				)
			):
				return occupation_id
	return fallback_occupation_id


func authorized_work_capabilities_for_resident(
	resident_id: String,
	resident: Dictionary,
	world_data: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var result: Dictionary = {}
	var primary_id := primary_occupation_id(resident, world_data)
	for occupation_value: Variant in world_data.get("occupations", []) as Array:
		var occupation := occupation_value as Dictionary
		if String(occupation.get("occupationId", "")) != primary_id:
			continue
		for capability_value: Variant in occupation.get("taskCapabilities", []) as Array:
			result[String(capability_value)] = true
		break
	for capability: String in staffing.active_assignment_capabilities(
		resident_id,
		absolute_minute,
	):
		result[capability] = true
	return result


func retire_stale_period_work_tasks(
	capability: String,
	source_kind: String,
	current_source_ref: String,
	reason: String,
) -> bool:
	return PRODUCTION_TASK_SYNC.retire_stale_period_work_tasks(
		tasks,
		capability,
		source_kind,
		current_source_ref,
		reason,
	)


func meal_period_for_minute(absolute_minute: int) -> Dictionary:
	return ACTIVITY_SCALARS.meal_period_for_minute(absolute_minute)


func meal_service_is_open(absolute_minute: int) -> bool:
	var period := meal_period_for_minute(absolute_minute)
	if period.is_empty():
		return false
	return posmod(absolute_minute, 1440) >= int(
		period.get("serviceStart", period.get("start", 0)),
	)


func dining_collect_can_finish_in_current_period(
	absolute_minute: int,
) -> bool:
	var period := meal_period_for_minute(absolute_minute)
	if period.is_empty() or not meal_service_is_open(absolute_minute):
		return false
	return posmod(absolute_minute, 1440) + 5 <= int(period.get("end", 0))


func meal_period_source_ref(absolute_minute: int) -> String:
	var period := meal_period_for_minute(absolute_minute)
	if period.is_empty():
		return ""
	return "meal-period:%d:%s" % [
		absolute_minute / 1440,
		String(period.get("id", "")),
	]


func dining_order_for_resident_meal_period(
	resident_id: String,
	absolute_minute: int,
	states: Array,
) -> Dictionary:
	return SERVICE_QUERY.dining_order_for_resident_meal_period(
		services,
		resident_id,
		absolute_minute,
		states,
	)


func dining_request_meal_is_ready(request: Dictionary) -> bool:
	var created_at := int(request.get("createdAtMinute", -1))
	return (
		created_at >= 0
		and not meal_period_for_minute(created_at).is_empty()
		and meal_period_is_prepared(created_at)
	)


func meal_period_is_prepared(absolute_minute: int) -> bool:
	var source_ref := meal_period_source_ref(absolute_minute)
	if source_ref.is_empty():
		return false
	var task := tasks.task("meal-preparation:%s" % source_ref) as Dictionary
	return String(task.get("state", "")) == "completed"


func create_clinic_treatment_task(
	request: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var request_id := String(request.get("requestId", ""))
	var patient_id := String(request.get("requesterResidentId", ""))
	return tasks.create_task_for_occupations(
		{
			"taskId": "clinic-treatment-task:%s" % request_id,
			"capability": "care.treatment",
			"sourceKind": "follow_up_due",
			"sourceRef": request_id,
			"targets": [
				{"kind": "service_request", "ref": request_id},
				{"kind": "resident", "ref": patient_id},
			],
			"requestedResultKind": "care_outcome",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["clinic_treatment"],
		},
		["occupation_clinic_practitioner"],
	) as Dictionary


func priority_onsite_service_task(
	resident_id: String,
	projected_tasks: Array[Dictionary],
) -> Dictionary:
	var selected: Dictionary = {}
	for projected_task: Dictionary in projected_tasks:
		var task := tasks.task(String(projected_task.get("task_id", ""))) as Dictionary
		if (
			task.is_empty()
			or String(task.get("assignedResidentId", "")) != resident_id
			or String(task.get("state", ""))
			not in ["accepted", "in_progress", "waiting"]
		):
			continue
		var request := services.request(String(task.get("sourceRef", ""))) as Dictionary
		if (
			request.is_empty()
			and String(task.get("capability", "")) == "food.production"
			and String(task.get("sourceKind", "")) == "meal_demand"
			and String(task.get("sourceRef", "")).begins_with("meal-period:")
		):
			selected = _higher_priority_service_task(
				selected,
				task,
				CONTENT_CATALOG.PLACE_DINING_HALL,
			)
			continue
		var context := request.get("context", {}) as Dictionary
		if (
			request.is_empty()
			or String(request.get("kind", "")) == "clinic"
			or String(request.get("state", ""))
			not in ["pending", "waiting", "in_progress"]
			or String(context.get("customerServiceMode", "")) != "onsite_wait"
		):
			continue
		selected = _higher_priority_service_task(
			selected,
			task,
			String(request.get("placeId", "")),
		)
	return selected


func active_clinic_request_for_resident(resident_id: String) -> Dictionary:
	for request_value: Variant in (services.snapshot() as Dictionary).get(
		"requests", [],
	) as Array:
		if request_value is not Dictionary:
			continue
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "clinic"
			and String(request.get("requesterResidentId", "")) == resident_id
			and String(request.get("state", ""))
			in ["pending", "waiting", "in_progress"]
		):
			return request.duplicate(true)
	return {}


func due_library_return_plans(absolute_minute: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for loan: Dictionary in PERIODIC_SERVICE_REQUEST.due_library_return_loans(
		absolute_minute,
		services,
	):
		var loan_id := String(loan.get("loanId", ""))
		result.append({
			"loan": loan.duplicate(true),
			"sourceRef": "library-return:%s" % loan_id,
			"requestSpec": {
				"kind": "library_return",
				"requesterResidentId": String(
					loan.get("borrowerResidentId", ""),
				),
				"subjectRef": loan_id,
				"context": {"generatedFromDueLoan": true},
			},
		})
	return result


func due_clinic_follow_up_plans(
	absolute_minute: int,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for follow_up_value: Variant in services.due_follow_ups(
		absolute_minute,
	) as Array:
		var follow_up := follow_up_value as Dictionary
		var follow_up_id := String(follow_up.get("followUpId", ""))
		result.append({
			"followUp": follow_up.duplicate(true),
			"followUpId": follow_up_id,
			"patientResidentId": String(
				follow_up.get("patientResidentId", ""),
			),
			"sourceRef": "clinic-follow-up:%s" % follow_up_id,
			"requestSpec": PERIODIC_SERVICE_REQUEST.clinic_follow_up_request_spec(
				follow_up,
			),
		})
	return result


func attach_clinic_follow_up_request(
	follow_up_id: String,
	request_id: String,
) -> bool:
	return services.attach_follow_up_request(
		follow_up_id,
		request_id,
	).get("ok") == true


func expire_specialty_inventory_before(
	place_id: String,
	item_id: String,
	cutoff_minute: int,
) -> void:
	PRODUCTION_TASK_SYNC.expire_specialty_inventory_before(
		cargo,
		place_id,
		item_id,
		cutoff_minute,
	)


func ensure_production_task(spec: Dictionary) -> Dictionary:
	var existing := tasks.active_task_for_source(
		String(spec.get("sourceKind", "")),
		String(spec.get("sourceRef", "")),
	) as Dictionary
	if not existing.is_empty():
		return {"created": false, "task": existing.duplicate(true)}
	var task_spec := spec.duplicate(true)
	var process_stage := String(task_spec.get("processStage", "")).strip_edges()
	var process_facts := (
		(task_spec.get("processFacts", {}) as Dictionary).duplicate(true)
		if task_spec.get("processFacts", {}) is Dictionary
		else {}
	)
	task_spec.erase("processStage")
	task_spec.erase("processFacts")
	var created := tasks.create_task(task_spec) as Dictionary
	if created.get("ok") != true:
		return {"created": false, "task": {}}
	var task := created.get("task", {}) as Dictionary
	if not process_stage.is_empty():
		var configured := tasks.configure_initial_process(
			String(task.get("taskId", "")),
			int(task.get("revision", 0)),
			process_stage,
			process_facts,
		) as Dictionary
		if configured.get("ok") != true:
			tasks.cancel_task(
				String(task.get("taskId", "")),
				"工作阶段初始化失败",
			)
			return {"created": false, "task": {}}
		task = configured.get("task", {}) as Dictionary
	var public_task := task.duplicate(true)
	production_task_created.emit(public_task)
	return {"created": true, "task": public_task}


func ensure_production_tasks(specs: Array) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for spec_value: Variant in specs:
		results.append(ensure_production_task(spec_value as Dictionary))
	return results


func sync_facility_cleanup_task(source_kind: String, absolute_minute: int) -> void:
	var service_snapshot := services.snapshot() as Dictionary
	var count := (
		int(service_snapshot.get("dirtyDishCount", 0))
		if source_kind == "dirty_dishes"
		else int(service_snapshot.get("usedCafeTableCount", 0))
	)
	if count <= 0:
		return
	var source_ref := (
		"public-dining-dirty-dishes"
		if source_kind == "dirty_dishes"
		else "cafe-used-tables"
	)
	if not (tasks.active_task_for_source(source_kind, source_ref) as Dictionary).is_empty():
		return
	ensure_production_task({
		"taskId": "%s-cleanup:%d:%d" % [source_kind, absolute_minute, count],
		"capability": "food.cleanup" if source_kind == "dirty_dishes" else "cafe.handoff",
		"sourceKind": source_kind,
		"sourceRef": source_ref,
		"targets": [{
			"kind": "prop",
			"ref": "公共食堂水槽" if source_kind == "dirty_dishes" else "花房咖啡馆西北座椅",
		}],
		"requestedResultKind": (
			"dish_state_change"
			if source_kind == "dirty_dishes"
			else "cleanliness_change"
		),
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["facility_cleanup"],
	})


func sync_food_chain_tasks(absolute_minute: int) -> Array[Dictionary]:
	return ensure_production_tasks(PRODUCTION_TASK_SYNC.sync_food_chain(
		absolute_minute,
		cargo,
		tasks,
	))


func advance_production_to(
	absolute_minute: int,
	weather: String,
) -> Dictionary:
	return production.advance_to(absolute_minute, weather) as Dictionary


func production_region_task_plan(absolute_minute: int) -> Dictionary:
	for market_item_id: String in [
		CONTENT_CATALOG.ITEM_FISH,
		CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
	]:
		expire_specialty_inventory_before(
			CONTENT_CATALOG.PLACE_MARKET,
			market_item_id,
			absolute_minute - 1440,
		)
	var plans: Array[Dictionary] = []
	var fish_inventory := int(cargo.inventory_quantity(
		CONTENT_CATALOG.PLACE_MARKET,
		CONTENT_CATALOG.ITEM_FISH,
	))
	if (
		production.fishing_task_needed(absolute_minute, fish_inventory)
		and not has_active_cargo_to_place(
			CONTENT_CATALOG.ITEM_FISH,
			CONTENT_CATALOG.PLACE_MARKET,
		)
	):
		plans.append({
			"targetActivityId": "activity_fisher_catch_in_region",
			"fallbackRegionId": "outdoor_harbor_01",
			"choiceKey": "fishing:%d" % absolute_minute,
			"spec": {
				"taskId": "fishing-task:%d" % absolute_minute,
				"capability": "fishing.harvest",
				"sourceKind": "fishing_conditions",
				"sourceRef": "outdoor_harbor_01",
				"requestedResultKind": "fishing_outcome",
				"createdAtMinute": absolute_minute,
				"priority": CONTENT_CATALOG.TASK_PRIORITY["fishing_plan"],
			},
		})
	var care_plot := production.care_task_plot() as Dictionary
	if not care_plot.is_empty():
		var care_plot_id := String(care_plot.get("plotId", ""))
		plans.append({
			"targetActivityId": "activity_farm_water_beds",
			"fallbackRegionId": "outdoor_garden_01",
			"choiceKey": "garden-care:%s:%d" % [care_plot_id, absolute_minute],
			"spec": {
				"taskId": "garden-care-task:%s:%d" % [care_plot_id, absolute_minute],
				"capability": "garden.care",
				"sourceKind": "plant_state",
				"sourceRef": care_plot_id,
				"requestedResultKind": "garden_state_change",
				"createdAtMinute": absolute_minute,
				"priority": CONTENT_CATALOG.TASK_PRIORITY["garden_care_plan"],
			},
		})
	var harvest_plot := production.harvest_task_plot() as Dictionary
	var fresh_flower_inventory := int(cargo.inventory_quantity(
		CONTENT_CATALOG.PLACE_MARKET,
		CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
	))
	if (
		not harvest_plot.is_empty()
		and fresh_flower_inventory < 2
		and not has_active_cargo_to_place(
			CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
			CONTENT_CATALOG.PLACE_MARKET,
		)
	):
		var harvest_plot_id := String(harvest_plot.get("plotId", ""))
		plans.append({
			"targetActivityId": "activity_garden_harvest_region",
			"fallbackRegionId": "outdoor_garden_01",
			"choiceKey": "garden-harvest:%s:%d" % [harvest_plot_id, absolute_minute],
			"spec": {
				"taskId": "garden-harvest-task:%s:%d" % [harvest_plot_id, absolute_minute],
				"capability": "garden.harvest",
				"sourceKind": "flowering_state",
				"sourceRef": harvest_plot_id,
				"requestedResultKind": "flower_lot",
				"createdAtMinute": absolute_minute,
				"priority": CONTENT_CATALOG.TASK_PRIORITY["garden_harvest_plan"],
			},
		})
	return {
		"carePlot": care_plot.duplicate(true),
		"taskPlans": plans,
	}


func sync_market_preparation_tasks(absolute_minute: int) -> Array[Dictionary]:
	return ensure_production_tasks(
		PRODUCTION_TASK_SYNC.sync_market_preparation(absolute_minute, cargo)
	)


func sync_daily_operation_tasks(absolute_minute: int) -> Array[Dictionary]:
	return ensure_production_tasks(
		PRODUCTION_TASK_SYNC.sync_daily_operations(absolute_minute, tasks)
	)


func sync_library_catalog_tasks(absolute_minute: int) -> Array[Dictionary]:
	return ensure_production_tasks(
		PRODUCTION_TASK_SYNC.sync_library_catalog(absolute_minute, tasks)
	)


func sync_civic_work_tasks(
	absolute_minute: int,
	place_service_states: Array,
	weather: String,
) -> Array[Dictionary]:
	return ensure_production_tasks(PRODUCTION_TASK_SYNC.sync_civic_work(
		absolute_minute,
		tasks,
		staffing_snapshot(true).get("posts", []) as Array,
		place_service_states,
		weather,
	))


func sync_warehouse_audit_tasks(absolute_minute: int) -> Array[Dictionary]:
	return ensure_production_tasks(PRODUCTION_TASK_SYNC.sync_warehouse_audit(
		absolute_minute,
		cargo,
		tasks,
	))


func sync_meal_period_task(
	absolute_minute: int,
	menu: String,
) -> Dictionary:
	var period := meal_period_for_minute(absolute_minute)
	var source_ref := meal_period_source_ref(absolute_minute)
	for task_value: Variant in (
		tasks.create_save_snapshot() as Dictionary
	).get("tasks", []) as Array:
		var existing_task := task_value as Dictionary
		if (
			String(existing_task.get("capability", "")) != "food.production"
			or String(existing_task.get("sourceKind", "")) != "meal_demand"
			or not String(existing_task.get("sourceRef", "")).begins_with(
				"meal-period:",
			)
			or String(existing_task.get("sourceRef", "")) == source_ref
			or _meal_period_has_waiting_orders(
				String(existing_task.get("sourceRef", "")),
			)
			or String(existing_task.get("state", "")) not in ["open", "waiting"]
		):
			continue
		tasks.cancel_task(
			String(existing_task.get("taskId", "")),
			"当前餐次已经结束",
		)
	if period.is_empty():
		return {"period": {}, "sourceRef": "", "task": {}}
	var ensured := ensure_production_task({
		"taskId": "meal-preparation:%s" % source_ref,
		"capability": "food.production",
		"sourceKind": "meal_demand",
		"sourceRef": source_ref,
		"targets": [
			{"kind": "prop", "ref": "公共食堂备餐柜"},
			{"kind": "prop", "ref": "公共食堂灶台"},
		],
		"requestedResultKind": "food_batch",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["meal_demand_order"],
		"processStage": "meal_period_planned",
		"processFacts": {
			"periodId": String(period.get("id", "")),
			"periodLabel": String(period.get("label", "")),
			"menu": menu,
			"serviceStartMinute": int(period.get("serviceStart", 0)),
			"baseSupply": true,
			"nextActivityId": "activity_dining_prepare_meal",
		},
	})
	return {
		"period": period.duplicate(true),
		"sourceRef": source_ref,
		"task": (ensured.get("task", {}) as Dictionary).duplicate(true),
	}


func _meal_period_has_waiting_orders(source_ref: String) -> bool:
	for request_value: Variant in (services.snapshot() as Dictionary).get(
		"requests", [],
	) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "dining_order"
			and String(request.get("state", "")) == "waiting"
			and String(request.get("waitReason", "")) in [
				"当前餐次尚未完成备餐",
				"当前餐次尚未开始供餐",
			]
			and meal_period_source_ref(
				int(request.get("createdAtMinute", -1)),
			) == source_ref
		):
			return true
	return false


func _higher_priority_service_task(
	selected: Dictionary,
	task: Dictionary,
	place_id: String,
) -> Dictionary:
	if (
		not selected.is_empty()
		and int(task.get("priority", 0)) <= int(selected.get("priority", 0))
	):
		return selected
	return {
		"task_id": String(task.get("taskId", "")),
		"priority": int(task.get("priority", 0)),
		"place_id": place_id,
	}
