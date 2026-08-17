class_name TownProductionTaskCoordinationRuntime
extends RefCounted


const TASK_SYNC := preload(
	"res://world/runtime/work/TownProductionTaskSyncRuntime.gd"
)
const PERFORMANCE_SERVICE := preload(
	"res://world/runtime/work/TownPerformanceServiceRuntime.gd"
)
const OCCUPATION_SERVICE_QUERY := preload(
	"res://world/runtime/work/TownOccupationServiceQuery.gd"
)
const WORK_ACTOR_SELECTION_POLICY := preload(
	"res://world/runtime/work/TownWorkActorSelectionPolicy.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const PERIODIC_SERVICE_REQUEST := preload(
	"res://world/runtime/work/TownPeriodicServiceRequestRuntime.gd"
)


static func create_plant_research_stage_task(
	host,
	project: Dictionary,
	stage: String,
) -> Dictionary:
	var observe_targets: Array[Dictionary] = []
	if stage == "observe":
		observe_targets = semantic_region_targets(
			host,
			"activity_botanist_observe_plants",
			"outdoor_garden_01",
			"%s:%s" % [String(project.get("projectId", "")), stage],
		)
	var planned := TASK_SYNC.plant_research_stage_task_spec(
		project,
		stage,
		observe_targets,
	) as Dictionary
	if planned.get("ok") != true:
		return host._command_failure(
			"PLANT_RESEARCH_STAGE_INVALID",
			["未知植物研究阶段"],
		)
	return host.create_work_task(planned.get("spec", {}) as Dictionary)


static func sync(host, absolute_minute: int) -> void:
	var lap_usec := Time.get_ticks_usec() if host.telemetry.advance_profile_enabled else 0
	var advanced := host._work.advance_production_to(
		absolute_minute,
		host.get_weather(),
	) as Dictionary
	host.telemetry.lap(
		host.telemetry.advance_profile_scratch,
		"productionTasksAdvanceUsec",
		lap_usec,
	)
	if advanced.get("ok") != true:
		return
	var production_plan: Dictionary = host._work.production_region_task_plan(
		absolute_minute,
	)
	ensure_region_task_plans(
		host,
		production_plan.get("taskPlans", []) as Array,
	)
	var care_plot := production_plan.get("carePlot", {}) as Dictionary
	host._work.sync_food_chain_tasks(absolute_minute)
	sync_craft_chain(host, absolute_minute)
	sync_clinic_follow_up(host, absolute_minute)
	sync_plant_research(host, absolute_minute, care_plot)
	sync_music_work(host, absolute_minute)
	host._work.sync_daily_operation_tasks(absolute_minute)
	host._work.sync_market_preparation_tasks(absolute_minute)
	host._work.sync_civic_work_tasks(
		absolute_minute,
		host._work.place_services.values_snapshot(),
		host.get_weather(),
	)
	sync_meal_period(host, absolute_minute)
	host._work.sync_warehouse_audit_tasks(absolute_minute)
	host._work.sync_library_catalog_tasks(absolute_minute)
	sync_library_returns(host, absolute_minute)
	sync_research_samples(host, absolute_minute)


static func sync_craft_chain(host, absolute_minute: int) -> void:
	for request_spec: Dictionary in TASK_SYNC.craft_repair_request_specs(
		host._work.services,
		host.world_definition.owners,
		host.resident_registry.records,
		host.resident_registry.id_by_name,
		host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.first_resident(host, "occupation_town_manager"),
	):
		host.create_occupation_service_request(request_spec)
	host._work.ensure_production_tasks(TASK_SYNC.sync_craft_production(
		absolute_minute,
		host._work.cargo,
		host._work.tasks,
	))


static func sync_plant_research(
	host,
	absolute_minute: int,
	care_plot: Dictionary,
) -> void:
	var planned := TASK_SYNC.sync_plant_research(
		absolute_minute,
		care_plot,
		host._work.production,
		host._work.services,
		host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.first_resident(host, "occupation_botanist"),
	) as Dictionary
	if not planned.is_empty():
		host.create_plant_research(
			String(planned.get("requesterId", "")),
			String(planned.get("question", "")),
			String(planned.get("sourceKind", "")),
		)


static func sync_music_work(host, absolute_minute: int) -> void:
	PERFORMANCE_SERVICE.retire_stale_requests(host, absolute_minute)
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 9 * 60 or minute_of_day >= 18 * 60:
		return
	var day_index := absolute_minute / 1440
	var request_exists := OCCUPATION_SERVICE_QUERY.request_exists(
		host._work.services,
		"performance",
		"public-event-day:%d" % day_index,
	)
	var musician_id := ""
	if posmod(day_index, 3) == 0 and not request_exists:
		musician_id = WORK_ACTOR_SELECTION_POLICY.choose_qualified_actor(
			host,
			"occupation_musician",
			"public-event-day:%d" % day_index,
		)
	var planned := TASK_SYNC.sync_music_work(
		absolute_minute,
		request_exists,
		musician_id,
	) as Dictionary
	for request_spec: Dictionary in planned.get("serviceRequests", []) as Array:
		host.create_occupation_service_request(request_spec)
	var source_ref := String(planned.get("sourceRef", ""))
	if source_ref.is_empty() or host._work.retire_stale_period_work_tasks(
		"music.rehearse",
		"personal_performance_plan",
		source_ref,
		"当天的排练计划已经结束",
	):
		return
	ensure_region_task_plans(host, planned.get("taskPlans", []) as Array)


static func ensure_region_task_plans(host, plans: Array) -> void:
	for plan_value: Variant in plans:
		var plan := plan_value as Dictionary
		var spec := (plan.get("spec", {}) as Dictionary).duplicate(true)
		spec["targets"] = semantic_region_targets(
			host,
			String(plan.get("targetActivityId", "")),
			String(plan.get("fallbackRegionId", "")),
			String(plan.get("choiceKey", "")),
		)
		host._work.ensure_production_task(spec)


static func semantic_region_targets(
	host,
	activity_id: String,
	fallback_region_id: String,
	choice_key := "",
) -> Array[Dictionary]:
	var lap_usec := Time.get_ticks_usec() if host.telemetry.advance_profile_enabled else 0
	var selection := TASK_SYNC.semantic_region_targets(
		host._activity_runtime,
		activity_id,
		fallback_region_id,
		choice_key,
		int(host._environment.get_absolute_minute()),
	)
	host.telemetry.lap(
		host.telemetry.advance_profile_scratch,
		"productionTasksTargetsUsec",
		lap_usec,
	)
	host.telemetry.count_advance_profile("productionTasksTargetsCalls", 1)
	host.telemetry.count_advance_profile(
		"productionTasksTargetCandidates",
		int(selection.get("candidateCount", 0)),
	)
	var targets: Array[Dictionary] = []
	targets.assign(selection.get("targets", []) as Array)
	return targets


static func sync_meal_period(host, absolute_minute: int) -> void:
	var period: Dictionary = host._work.meal_period_for_minute(absolute_minute)
	var synced: Dictionary = host._work.sync_meal_period_task(
		absolute_minute,
		DINING_SERVICE.meal_menu_for_period(period) if not period.is_empty() else "",
	)
	var source_ref := String(synced.get("sourceRef", ""))
	if source_ref.is_empty():
		return
	DINING_SERVICE.reserve_meal_preparation_task(host, source_ref)
	host.OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME.activate_waiting_dining_orders(host)


static func sync_library_returns(host, absolute_minute: int) -> void:
	var message_created_at := int(host._environment.get_absolute_minute())
	for plan: Dictionary in host._work.due_library_return_plans(absolute_minute):
		var created: Dictionary = host.create_occupation_service_request(
			plan.get("requestSpec", {}) as Dictionary,
		)
		if created.get("ok") != true:
			continue
		PERIODIC_SERVICE_REQUEST.notify_library_return(
			host,
			plan.get("loan", {}) as Dictionary,
			message_created_at,
			host.PRIVATE_MESSAGE_QUERY_RUNTIME.distribution_token(
				host,
				String(plan.get("sourceRef", "")),
				"library-return",
			),
		)


static func sync_research_samples(host, absolute_minute: int) -> void:
	ensure_region_task_plans(host, TASK_SYNC.sync_research_samples(
		absolute_minute,
		host._work.production,
		host._work.tasks,
	))


static func sync_specialty_service_demand(
	host,
	kind: String,
	item_id: String,
	request_id: String,
	now: int,
) -> void:
	var planned := TASK_SYNC.specialty_service_demand_plan(
		kind,
		item_id,
		request_id,
		now,
		host._work.cargo,
		host._work.tasks,
		host._work.services,
	) as Dictionary
	if planned.is_empty():
		return
	var spec := (planned.get("spec", {}) as Dictionary).duplicate(true)
	if planned.has("targetActivityId"):
		spec["targets"] = semantic_region_targets(
			host,
			String(planned.get("targetActivityId", "")),
			String(planned.get("fallbackRegionId", "")),
			String(planned.get("choiceKey", "")),
		)
	host._work.ensure_production_task(spec)


static func sync_clinic_follow_up(host, absolute_minute: int) -> void:
	var message_created_at := int(host._environment.get_absolute_minute())
	for plan: Dictionary in host._work.due_clinic_follow_up_plans(absolute_minute):
		var follow_up := plan.get("followUp", {}) as Dictionary
		var created: Dictionary = host.create_occupation_service_request(
			plan.get("requestSpec", {}) as Dictionary,
		)
		if created.get("ok") != true:
			continue
		var request := created.get("request", {}) as Dictionary
		if not host._work.attach_clinic_follow_up_request(
			String(plan.get("followUpId", "")),
			String(request.get("requestId", "")),
		):
			continue
		var resident_request := PERIODIC_SERVICE_REQUEST.notify_clinic_follow_up(
			host,
			follow_up,
			message_created_at,
			host.PRIVATE_MESSAGE_QUERY_RUNTIME.distribution_token(
				host,
				String(plan.get("sourceRef", "")),
				"clinic-follow-up",
			),
			host.resident_display_name(
				String(plan.get("patientResidentId", "")),
			),
		) as Dictionary
		if not resident_request.is_empty():
			host.sync_resident_request(resident_request)
