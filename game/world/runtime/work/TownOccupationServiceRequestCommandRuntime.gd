class_name TownOccupationServiceRequestCommandRuntime
extends RefCounted


const OCCUPATION_SERVICE_DEFINITION := preload(
	"res://world/runtime/work/TownOccupationServiceDefinition.gd"
)
const OCCUPATION_SERVICE_REQUEST_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceRequestRuntime.gd"
)
const OCCUPATION_SERVICE_STAFFING_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceStaffingRuntime.gd"
)
const OCCUPATION_SERVICE_REQUEST_COMMIT := preload(
	"res://world/runtime/work/TownOccupationServiceRequestCommit.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const PRODUCTION_TASK_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskCoordinationRuntime.gd"
)
const OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServicePresenceAdvancementRuntime.gd"
)


static func create(host, spec: Dictionary) -> Dictionary:
	var kind := String(spec.get("kind", "")).strip_edges()
	var requester_id: String = host._resident_key(
		String(spec.get("requesterResidentId", "")),
	)
	var definition := OCCUPATION_SERVICE_DEFINITION.definition(kind)
	var entry_failure := OCCUPATION_SERVICE_REQUEST_RUNTIME.entry_failure(
		host._running,
		kind,
		requester_id,
		definition,
	) as Dictionary
	if not entry_failure.is_empty():
		return entry_failure
	var request_now: int = host._authoritative_absolute_minute()
	var prepared := OCCUPATION_SERVICE_REQUEST_RUNTIME.prepare(
		spec,
		requester_id,
		host.resident_registry.records.get(requester_id, {}) as Dictionary,
		definition,
		host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.request_context(host, requester_id) if kind == "clinic" else {},
		not host.CLINIC_SERVICE_COORDINATION_RUNTIME.executable_practitioner_ids(host).is_empty() if kind == "clinic" else true,
		request_now,
		DINING_SERVICE.wait_deadline(host, request_now),
		host._work.cargo,
		host._work.services,
	) as Dictionary
	if prepared.get("ok") != true:
		return host._decorate_command_result(prepared)
	definition = prepared.get("definition", {}) as Dictionary
	var staffing_failure := (
		OCCUPATION_SERVICE_STAFFING_RUNTIME.paused_request_failure(
			host,
			kind,
			definition,
		) as Dictionary
	)
	if not staffing_failure.is_empty():
		return host._decorate_command_result(staffing_failure)
	var request_context := prepared.get("context", {}) as Dictionary
	if kind == "dining_order":
		var reused: Dictionary = host.DINING_ORDER_COORDINATION_RUNTIME.reuse_existing(host,
			requester_id,
			request_now,
		)
		if not reused.is_empty():
			return reused
	var created := OCCUPATION_SERVICE_REQUEST_RUNTIME.create_request(
		host._work.services,
		prepared,
	) as Dictionary
	if created.get("ok") != true:
		return host._decorate_command_result(created)
	var request := created.get("request", {}) as Dictionary
	var request_id := String(request.get("requestId", ""))
	if kind == "dining_order" and (
		host._work.meal_period_for_minute(request_now).is_empty()
		or not host._work.meal_service_is_open(request_now)
		or not host._work.meal_period_is_prepared(request_now)
	):
		return host.DINING_ORDER_COORDINATION_RUNTIME.hold_until_service(host,
			request_id,
			requester_id,
			request_context,
			definition,
			request_now,
		)
	var task: Dictionary = {}
	if bool(definition.get("placeService", false)):
		var service_result: Dictionary = host.record_place_service_request(
			String(definition.get("placeId", "")),
			request_id,
			true,
		)
		if service_result.get("ok") != true:
			return OCCUPATION_SERVICE_REQUEST_RUNTIME.cancelled_failure(
				host._work.services,
				request_id,
				"地点服务任务创建失败",
				service_result,
			)
		task = host._work.tasks.active_task_for_source(
			String(definition.get("sourceKind", "")),
			request_id,
		) as Dictionary
	var request_commit := OCCUPATION_SERVICE_REQUEST_COMMIT.new(
		host._work.services,
		host._work.tasks,
		host._clinic_interviews,
	)
	var task_result := request_commit.create_task(
		prepared,
		request,
		task,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if task_result.get("ok") != true:
		return host._decorate_command_result(
			task_result.get("failure", {}) as Dictionary
		)
	task = task_result.get("task", {}) as Dictionary
	if bool(task_result.get("createdNonPlaceTask", false)):
		host._bump_world_revision()
	var configured := request_commit.configure_task(
		prepared,
		task,
		request_id,
	) as Dictionary
	if configured.get("ok") != true:
		return host._decorate_command_result(
			configured.get("failure", {}) as Dictionary
		)
	task = configured.get("task", task) as Dictionary
	task = host.WORK_TASK_PUBLIC_RUNTIME.reserve(
		host,
		task,
		String(definition.get("occupationId", "")),
	)
	host.CUSTOMER_SERVICE_WAIT_RUNTIME.begin(host,
		requester_id,
		request_id,
		String(definition.get("placeId", "")),
		request_context,
	)
	if bool(prepared.get("requestsResearchBooklet", false)):
		PRODUCTION_TASK_COORDINATION_RUNTIME.sync_specialty_service_demand(
			host,
			kind,
			CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			request_id,
			request_now,
		)
	OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME.schedule_worker(
		host,
		host._work.services.request(request_id) as Dictionary,
	)
	return host._decorate_command_result(
		OCCUPATION_SERVICE_REQUEST_RUNTIME.success(
			configured.get("request", {}) as Dictionary,
			task,
		)
	)
