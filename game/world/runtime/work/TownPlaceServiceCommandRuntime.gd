class_name TownPlaceServiceCommandRuntime
extends RefCounted


const VISITOR_OCCUPATION_SERVICE_SPEC := preload(
	"res://world/runtime/work/TownVisitorOccupationServiceSpec.gd"
)
const CONSUMED_SERVICE_ITEM_PROJECTION := preload(
	"res://world/runtime/work/TownConsumedServiceItemProjection.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const OCCUPATION_RESIDENT_CONTEXT_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationResidentContextRuntime.gd"
)


static func initialize(host) -> void:
	host._work.place_services.replace_with_defaults(build_default_states(
		host,
		host.world_definition.world_data,
		host.resident_registry.records,
	))


static func build_default_states(
	host,
	world_data: Dictionary,
	residents: Dictionary = {},
	staffing_snapshot: Dictionary = {},
	residents_prevalidated_alive: bool = false,
) -> Dictionary:
	var available_resident_ids: Array[String] = []
	for resident_id_value: Variant in residents:
		var resident_id := String(resident_id_value)
		var resident := residents.get(resident_id, {}) as Dictionary
		var available: bool = (
			String((resident.get("arrivalState", {}) as Dictionary).get(
				"status",
				"arrived",
			)) == "arrived" and not host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.is_on_leave(host, resident)
			if residents_prevalidated_alive
			else host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.available_for_work(host, resident)
		)
		if available:
			available_resident_ids.append(resident_id)
	return host._work.place_services.build_default_states(
		world_data,
		residents,
		staffing_snapshot if not staffing_snapshot.is_empty() else host.get_staffing_snapshot(),
		available_resident_ids,
	)


static func record_request(
	host,
	place_id: String,
	request_id: String,
	active: bool,
	expires_at: int,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var transition: Dictionary = host._work.place_services.update_request(
		place_id,
		request_id,
		active,
		expires_at,
		int(host._environment.get_absolute_minute()),
	)
	if transition.get("ok") != true:
		return host._command_failure(
			String(transition.get("errorCode", "PLACE_SERVICE_REQUEST_INVALID")),
			transition.get("errors", []) as Array,
		)
	if transition.get("changed") != true:
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"state": transition.get("state", {}) as Dictionary,
		})
	var normalized_place := String(transition.get("placeId", ""))
	var normalized_request := String(transition.get("requestId", ""))
	var state := transition.get("state", {}) as Dictionary
	var work_task_sync := sync_work_task(
		host,
		state,
		normalized_request,
		active,
	)
	if work_task_sync.get("ok") != true:
		return host._decorate_command_result(work_task_sync)
	var refreshed: Dictionary = refresh_pressure(host, normalized_place)
	if refreshed.get("ok") != true:
		return refreshed
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"state": host._work.place_services.state(normalized_place),
		"matter": (
			refreshed.get("matter", {}) as Dictionary
		).duplicate(true),
	})


static func sync_work_task(
	host,
	state: Dictionary,
	request_id: String,
	active: bool,
) -> Dictionary:
	var plan: Dictionary = host._work.place_services.work_task_sync_plan(
		state,
		request_id,
		active,
		host._work.tasks,
	)
	if String(plan.get("operation", "")) == "create":
		return host.create_work_task(plan.get("spec", {}) as Dictionary)
	if String(plan.get("operation", "")) != "cancel":
		return plan.get("result", {}) as Dictionary
	var cancelled := host._work.tasks.cancel_task(
		String(plan.get("taskId", "")),
		"地点服务请求已撤销",
	) as Dictionary
	if cancelled.get("ok") != true:
		return cancelled
	host._bump_world_revision()
	return {
		"ok": true,
		"changed": true,
		"task": (
			cancelled.get("task", {}) as Dictionary
		).duplicate(true),
	}


static func set_open(
	host,
	place_id: String,
	open: bool,
	changed_by_resident_id: String,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var transition: Dictionary = host._work.place_services.update_open(
		place_id,
		open,
		int(host._environment.get_absolute_minute()),
	)
	if transition.get("ok") != true:
		return host._command_failure(
			String(transition.get("errorCode", "PLACE_SERVICE_STATE_UNKNOWN")),
			transition.get("errors", []) as Array,
		)
	var state := transition.get("state", {}) as Dictionary
	if transition.get("changed") != true:
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"state": state,
		})
	var normalized_place := String(transition.get("placeId", ""))
	if not open:
		host.CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.pause_for_service(
			host,
			normalized_place,
			"%s已经停止营业，需要重新决定怎样履行约定" % normalized_place,
		)
	var refreshed: Dictionary = refresh_pressure(host, normalized_place)
	if refreshed.get("ok") != true:
		return refreshed
	emit_open_change(host, normalized_place, open, changed_by_resident_id)
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"state": state,
	})


static func emit_open_change(
	host,
	place_id: String,
	open: bool,
	changed_by_resident_id: String,
) -> void:
	var notification: Dictionary = host._work.place_services.open_change_notification(
		place_id,
		open,
		changed_by_resident_id,
		host.resident_registry.records,
		host.resident_registry.order,
	)
	for resident_id: String in notification.get("residentIds", []) as Array[String]:
		host.WORLD_EVENT_DELIVERY_RUNTIME.queue(host,
			resident_id,
			notification.get("source", {}) as Dictionary,
		)


static func apply_activity_completion(host, execution: Dictionary) -> void:
	var activity_id := String(execution.get("activityId", ""))
	if not visitor_occupation_service_spec(host, "", activity_id).is_empty():
		# The occupation-service runtime owns these request ids and their
		# inventory/result contracts. Do not also create a second anonymous
		# "activity-request" for the same customer action.
		return
	var place_id := String(execution.get("placeId", ""))
	if not host._work.place_services.has(place_id):
		return
	var state: Dictionary = host._work.place_services.state(place_id)
	var request_id: String = host._work.place_services.first_pending_request(place_id)
	var remove_completed_helper_request := false
	if (
		activity_id == String(state.get("helper_activity_id", ""))
		and not request_id.is_empty()
	):
		var occupation_request := host._work.services.request(request_id) as Dictionary
		remove_completed_helper_request = (
			occupation_request.is_empty()
			or String(occupation_request.get("state", ""))
			in ["completed", "cancelled"]
		)
	var transition: Dictionary = host._work.place_services.apply_activity_completion(
		execution,
		remove_completed_helper_request,
		int(host._environment.get_absolute_minute()),
	)
	if transition.get("changed") != true:
		return
	state = transition.get("state", {}) as Dictionary
	rotate_completed_matter(host, state, execution)
	refresh_pressure(host, place_id)


static func finish_control_action(host, resident_id: String, action: Dictionary) -> void:
	var place_id := String(action.get("place_id", ""))
	var opening := bool(action.get("open", false))
	var changed: Dictionary = set_open(host, place_id, opening, resident_id)
	if changed.get("ok") != true:
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
			resident_id,
			String((changed.get("errors", ["营业状态未能改变"]) as Array)[0]),
		)
		return
	host.ACTION_SETTLEMENT_RUNTIME.finish(host,
		resident_id,
		"%s恢复营业了" % place_id if opening else "%s今天停止营业了" % place_id,
	)


static func service_control(host, resident: Dictionary) -> Dictionary:
	return host._work.place_services.service_control(resident)


static func closed_for_visitor(
	host,
	resident: Dictionary,
	place_id: String,
) -> bool:
	if DINING_SERVICE.can_admit_without_worker(
		host,
		place_id,
		int(host._environment.get_absolute_minute()),
	):
		return false
	return host._work.place_services.is_closed_for_visitor(resident, place_id)


static func snapshots(host) -> Array[Dictionary]:
	var active_workers_by_place := {}
	for place_id: String in host._work.place_services.sorted_place_ids():
		active_workers_by_place[place_id] = active_worker_count(
			host,
			host._work.place_services.state(place_id),
		)
	return host._work.place_services.public_snapshots(active_workers_by_place)


static func refresh_pressure(host, place_id: String) -> Dictionary:
	var state: Dictionary = host._work.place_services.state(place_id)
	var prepared: Dictionary = host._work.place_services.pressure_payload(
		place_id,
		active_worker_count(host, state),
	)
	if prepared.get("ok") != true:
		return host._command_failure(
			String(prepared.get("errorCode", "PLACE_SERVICE_STATE_UNKNOWN")),
			prepared.get("errors", []) as Array,
		)
	return host.sync_place_service_pressure(
		prepared.get("payload", {}) as Dictionary,
	)


static func active_worker_count(host, state: Dictionary) -> int:
	return host._work.place_services.active_worker_count(
		state,
		host.resident_registry.records,
		host.resident_registry.order,
		host._activity_runtime,
	)


static func apply_consumed_item(
	host,
	resident_id: String,
	item_id: String,
) -> void:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return
	var activity_state: Dictionary = (
		CONSUMED_SERVICE_ITEM_PROJECTION.activity_state_after_consumption(
			resident.get("activityState", {}) as Dictionary,
			item_id,
		)
	)
	if activity_state.is_empty():
		return
	resident["activityState"] = activity_state
	host.ACTIVITY_SCALARS.sync_body_from_activity_needs(resident, activity_state)


static func record_staffing_trial(
	host,
	resident_id: String,
	occupation_id: String,
	evidence: Dictionary,
) -> void:
	var trial := host._work.staffing.active_trial_for(
		resident_id,
		occupation_id,
	) as Dictionary
	if trial.is_empty():
		return
	var result := host._work.staffing.record_trial_result(
		String(trial.get("arrangementId", "")),
		true,
		evidence,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return
	host._work.staffing.rebuild(
		host.resident_registry.records,
		int(host._environment.get_absolute_minute()),
	)
	host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.sync_staffing_matters(host)


static func refresh_staffing(host) -> void:
	var defaults: Dictionary = build_default_states(
		host,
		host.world_definition.world_data,
		host.resident_registry.records,
	)
	var now := int(host._environment.get_absolute_minute())
	for change: Dictionary in host._work.place_services.reconcile_staffing(
		defaults,
		now,
	):
		if bool(change.get("visibleChanged", false)):
			var place_id := String(change.get("placeId", ""))
			var current := change.get("state", {}) as Dictionary
			refresh_pressure(host, place_id)
			if bool(change.get("openChanged", false)):
				emit_open_change(
				host,
				place_id,
				bool(current.get("open", false)),
				String(current.get("owner_id", "")),
			)
	sync_vacant_mobile_service_fallbacks(host)


static func sync_vacant_mobile_service_fallbacks(host) -> void:
	if host._work.occupation_post_is_vacant("occupation_postal_worker"):
		for message_id: String in host.private_message_runtime.sorted_message_ids():
			host.PRIVATE_MESSAGE_DELIVERY_RUNTIME.enable_sender_delivery(host, message_id)
	if not host._work.occupation_post_is_vacant("occupation_delivery_worker"):
		return
	for resident_id: String in host.CARGO_LOGISTICS_RUNTIME.sync_vacant_delivery_fallbacks(
		host._work.cargo,
		host._work.tasks,
		host.world_definition.owners,
		host.resident_registry.id_by_name,
		host.resident_registry.records,
		host.resident_registry.order,
	):
		host._schedule_decision(resident_id, true)


static func visitor_occupation_service_spec(
	host,
	resident_id: String,
	activity_id: String,
) -> Dictionary:
	var now := int(host._environment.get_absolute_minute())
	var context := {}
	match activity_id:
		"activity_clinic_consult":
			context["clinicCondition"] = host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.request_context(host, resident_id)
		"activity_library_checkout":
			context["borrowedLoan"] = (
				host._work.services.borrowed_loan_for_resident(resident_id)
			)
		"activity_town_hall_meeting":
			context["performanceActive"] = host._work.services.has_active_request(
				"performance",
				VISITOR_OCCUPATION_SERVICE_SPEC.performance_subject(resident_id, now),
			)
		"activity_market_buy_flowers":
			context["flowerHome"] = OCCUPATION_RESIDENT_CONTEXT_RUNTIME.home_place(
				host, resident_id,
			)
	return VISITOR_OCCUPATION_SERVICE_SPEC.build(
		resident_id,
		activity_id,
		now,
		context,
	)


static func rotate_completed_matter(
	host,
	state: Dictionary,
	execution: Dictionary,
) -> void:
	if (
		(state.get("pending_request_ids", []) as Array).is_empty()
		or active_worker_count(host, state) > 0
	):
		return
	var place_id := String(state.get("place_id", ""))
	var pressure_id := String(state.get("pressure_id", ""))
	var matter := host._social_matters.find_active_matter(
		"place_service_pressure",
		pressure_id,
		[place_id],
	) as Dictionary
	if (
		String(matter.get("state", "")) not in ["assigned", "executing"]
		or host.SOCIAL_GOAL_MATCHING_RUNTIME.matter_has_active_participants(matter)
	):
		return
	var matter_id := String(matter.get("matter_id", ""))
	var closed := host._social_matters.close_matter(
		matter_id,
		"social.resolve.service_reduced",
		"service_help_completed",
		[
			{
				"result_id": "service-cycle:%s"
				% String(execution.get("actionId", "")),
				"activity_id": String(execution.get("activityId", "")),
				"place_id": place_id,
			}
		],
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if closed.get("ok") == true:
		host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(host, matter_id)
