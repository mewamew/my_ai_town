class_name TownProductionTaskSyncRuntime
extends RefCounted


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)


static func has_active_cargo_to_place(
	cargo_inventory: TownCargoInventoryRuntime,
	item_id: String,
	place_id: String,
) -> bool:
	var snapshot := cargo_inventory.snapshot() as Dictionary
	for value: Variant in snapshot.get("cargoLots", []) as Array:
		var lot := value as Dictionary
		if (
			String(lot.get("itemId", "")) == item_id
			and String(lot.get("destinationPlaceId", "")) == place_id
			and String(lot.get("state", "")) in [
				"awaiting_release",
				"available",
				"in_transit",
				"awaiting_receipt",
			]
		):
			return true
	return false


static func has_active_specialty_production(
	work_tasks: TownWorkTaskRuntime,
	item_id: String,
	destination_place_id: String,
) -> bool:
	for task_value: Variant in (
		work_tasks.create_save_snapshot() as Dictionary
	).get("tasks", []) as Array:
		var task := task_value as Dictionary
		var facts := task.get("processFacts", {}) as Dictionary
		if (
			String(task.get("state", "")) not in [
				"completed",
				"failed",
				"cancelled",
			]
			and String(facts.get("productItemId", "")) == item_id
			and String(facts.get("destinationPlaceId", ""))
			== destination_place_id
		):
			return true
	return false


static func has_active_work_task_capability(
	work_tasks: TownWorkTaskRuntime,
	capability: String,
) -> bool:
	for task_value: Variant in (
		work_tasks.create_save_snapshot() as Dictionary
	).get("tasks", []) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) == capability
			and String(task.get("state", "")) not in [
				"completed",
				"failed",
				"cancelled",
			]
		):
			return true
	return false


static func retire_stale_period_work_tasks(
	work_tasks: TownWorkTaskRuntime,
	capability: String,
	source_kind: String,
	current_source_ref: String,
	reason: String,
) -> bool:
	var carried_work_exists := false
	for task_value: Variant in (
		work_tasks.create_save_snapshot() as Dictionary
	).get("tasks", []) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) != capability
			or String(task.get("sourceKind", "")) != source_kind
			or String(task.get("sourceRef", "")) == current_source_ref
			or String(task.get("state", "")) in [
				"completed",
				"failed",
				"cancelled",
			]
		):
			continue
		var state := String(task.get("state", ""))
		var process_stage := String(task.get("processStage", "ready"))
		if (
			state in ["accepted", "in_progress"]
			or not String(task.get("assignedResidentId", "")).is_empty()
			or process_stage not in ["ready", "planned", "reviewing"]
		):
			carried_work_exists = true
			continue
		work_tasks.cancel_task(
			String(task.get("taskId", "")),
			reason,
		)
	return carried_work_exists


static func cancel_active_work_task_for_source(
	work_tasks: TownWorkTaskRuntime,
	source_kind: String,
	source_ref: String,
	reason: String,
) -> void:
	var task := work_tasks.active_task_for_source(
		source_kind,
		source_ref,
	) as Dictionary
	if task.is_empty():
		return
	work_tasks.cancel_task(
		String(task.get("taskId", "")),
		reason,
	)


static func expire_specialty_inventory_before(
	cargo_inventory: TownCargoInventoryRuntime,
	place_id: String,
	item_id: String,
	cutoff_minute: int,
) -> void:
	var quantity := int(cargo_inventory.inventory_quantity(place_id, item_id))
	if quantity <= 0 or cutoff_minute <= 0:
		return
	var latest_receipt_minute := -1
	for lot_value: Variant in (
		cargo_inventory.snapshot() as Dictionary
	).get("cargoLots", []) as Array:
		var lot := lot_value as Dictionary
		if (
			String(lot.get("state", "")) == "delivered"
			and String(lot.get("itemId", "")) == item_id
			and String(lot.get("destinationPlaceId", "")) == place_id
		):
			latest_receipt_minute = maxi(
				latest_receipt_minute,
				int(lot.get("receivedAtMinute", -1)),
			)
	if latest_receipt_minute >= cutoff_minute:
		return
	var expired_inputs := {}
	expired_inputs[item_id] = quantity
	cargo_inventory.apply_inventory_recipe(place_id, expired_inputs, {})


static func sync_food_chain(
	absolute_minute: int,
	cargo_inventory: TownCargoInventoryRuntime,
	work_tasks: TownWorkTaskRuntime,
) -> Array[Dictionary]:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 360 or minute_of_day >= 720:
		return []
	var day_index := absolute_minute / 1440
	expire_specialty_inventory_before(
		cargo_inventory,
		CONTENT_CATALOG.PLACE_CAFE,
		"pastry",
		absolute_minute - 1440,
	)
	var source_ref := "dining-pastry-plan-day:%d" % day_index
	if retire_stale_period_work_tasks(
		work_tasks,
		"food.production",
		"daily_baking_plan",
		source_ref,
		"当天的烘焙计划已经结束",
	):
		return []
	if (
		int(cargo_inventory.inventory_quantity(
			CONTENT_CATALOG.PLACE_CAFE,
			"pastry",
		)) > 0
		or has_active_cargo_to_place(
			cargo_inventory,
			"pastry",
			CONTENT_CATALOG.PLACE_CAFE,
		)
		or has_active_specialty_production(
			work_tasks,
			"pastry",
			CONTENT_CATALOG.PLACE_CAFE,
		)
	):
		return []
	return [{
		"taskId": "dining-pastry-plan:%d" % day_index,
		"capability": "food.production",
		"sourceKind": "daily_baking_plan",
		"sourceRef": source_ref,
		"targets": [
			{"kind": "prop", "ref": "公共食堂备餐柜"},
			{"kind": "prop", "ref": "公共食堂灶台"},
		],
		"requestedResultKind": "food_batch",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["daily_baking_plan"],
		"processStage": "planned",
		"processFacts": {
			"productItemId": "pastry",
			"destinationPlaceId": CONTENT_CATALOG.PLACE_CAFE,
			"nextActivityId": "activity_baker_prepare_dough",
		},
	}]


static func sync_market_preparation(
	absolute_minute: int,
	cargo_inventory: TownCargoInventoryRuntime,
) -> Array[Dictionary]:
	var fresh_quantity := int(cargo_inventory.inventory_quantity(
		CONTENT_CATALOG.PLACE_MARKET,
		CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
	))
	var bouquet_quantity := int(cargo_inventory.inventory_quantity(
		CONTENT_CATALOG.PLACE_MARKET,
		CONTENT_CATALOG.ITEM_BOUQUET,
	))
	if fresh_quantity < 2 or bouquet_quantity >= 2:
		return []
	return [{
		"taskId": "flower-arrangement:%d" % absolute_minute,
		"capability": "retail.arrange",
		"sourceKind": "display_change",
		"sourceRef": "flower-stall-bouquet-stock",
		"targets": [{"kind": "prop", "ref": "独立市集北侧花摊"}],
		"requestedResultKind": "bouquet_lot",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["retail_display_plan"],
	}]


static func craft_repair_request_specs(
	occupation_services: TownOccupationServiceRuntime,
	requester_by_place: Dictionary,
	residents: Dictionary,
	town_manager_id: String,
) -> Array[Dictionary]:
	var service_requests: Array[Dictionary] = []
	for fault_value: Variant in occupation_services.active_equipment_faults():
		var fault := fault_value as Dictionary
		var fault_id := String(fault.get("faultId", ""))
		if bool(occupation_services.has_active_request("repair", fault_id)):
			continue
		var place_id := String(fault.get("placeId", ""))
		var requester_id := String(
			requester_by_place.get(place_id, ""),
		).strip_edges()
		if not residents.has(requester_id):
			requester_id = ""
		if requester_id.is_empty():
			requester_id = town_manager_id
		if requester_id.is_empty():
			continue
		service_requests.append({
			"kind": "repair",
			"requesterResidentId": requester_id,
			"subjectRef": fault_id,
			"context": {
				"generatedFromEquipmentWear": true,
				"propName": String(fault.get("propName", "")),
				"placeId": place_id,
				"faultReason": String(fault.get("faultReason", "")),
				"completeOnRepair": true,
			},
		})
	return service_requests


static func sync_craft_production(
	absolute_minute: int,
	cargo_inventory: TownCargoInventoryRuntime,
	work_tasks: TownWorkTaskRuntime,
) -> Array[Dictionary]:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 480 or minute_of_day >= 960:
		return []
	var day_index := absolute_minute / 1440
	var source_ref := "civic-craft-plan-day:%d" % day_index
	if retire_stale_period_work_tasks(
		work_tasks,
		"craft.production",
		"production_request",
		source_ref,
		"新的公共用品制作周期已经开始",
	):
		return []
	if (
		int(cargo_inventory.inventory_quantity(
			CONTENT_CATALOG.PLACE_WAREHOUSE,
			"crafted_item",
		)) > 0
		or has_active_cargo_to_place(
			cargo_inventory,
			"crafted_item",
			CONTENT_CATALOG.PLACE_WAREHOUSE,
		)
		or has_active_specialty_production(
			work_tasks,
			"crafted_item",
			CONTENT_CATALOG.PLACE_WAREHOUSE,
		)
	):
		return []
	return [{
		"taskId": "craft-production:%d" % day_index,
		"capability": "craft.production",
		"sourceKind": "production_request",
		"sourceRef": source_ref,
		"targets": [
			{"kind": "prop", "ref": "工作坊木料架"},
			{"kind": "prop", "ref": "工作坊打磨机"},
			{"kind": "prop", "ref": "工作坊装配锯架台"},
		],
		"requestedResultKind": "crafted_lot",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["craft_request"],
		"processStage": "materials_planned",
		"processFacts": {
			"productItemId": "crafted_item",
			"destinationPlaceId": CONTENT_CATALOG.PLACE_WAREHOUSE,
			"baseSupplyItems": ["lumber", "metal"],
			"nextActivityId": "activity_workshop_take_lumber",
		},
	}]


static func sync_daily_operations(
	absolute_minute: int,
	work_tasks: TownWorkTaskRuntime,
) -> Array[Dictionary]:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 8 * 60 or minute_of_day >= 17 * 60:
		return []
	var day_index := absolute_minute / 1440
	var task_specs: Array[Dictionary] = []
	var operations: Array[Dictionary] = [
		{
			"key": "postal-collection",
			"capability": "message.accept",
			"targetKind": "route",
			"target": "小镇道路",
			"activityId": "activity_postal_collect_outgoing_mail",
			"sourceKind": "daily_postal_collection_plan",
			"resultKind": "postal_collection_record",
			"priority": CONTENT_CATALOG.TASK_PRIORITY["daily_postal_collection"],
		},
		{
			"key": "cafe-opening",
			"capability": "cafe.handoff",
			"target": "花房咖啡馆西北座椅",
			"activityId": "activity_cafe_tidy_tables",
		},
		{
			"key": "clinic-opening",
			"capability": "care.treatment",
			"target": "诊所药柜",
			"activityId": "activity_clinic_prepare_medicine",
		},
		{
			"key": "grocer-opening",
			"capability": "retail.stock",
			"target": "独立市集西侧杂货摊",
			"activityId": "activity_grocer_count_goods",
		},
		{
			"key": "flower-opening",
			"capability": "retail.sale",
			"target": "独立市集南侧花摊",
			"activityId": "activity_flower_watch_stall",
		},
	]
	for operation: Dictionary in operations:
		var source_ref := "%s-day:%d" % [
			String(operation.get("key", "operation")),
			day_index,
		]
		if retire_stale_period_work_tasks(
			work_tasks,
			String(operation.get("capability", "")),
			String(operation.get("sourceKind", "daily_operation_plan")),
			source_ref,
			"新的每日营业整理周期已经开始",
		):
			continue
		task_specs.append({
			"taskId": "daily-operation:%s" % source_ref,
			"capability": String(operation.get("capability", "")),
			"sourceKind": String(
				operation.get("sourceKind", "daily_operation_plan"),
			),
			"sourceRef": source_ref,
			"targets": [{
				"kind": String(operation.get("targetKind", "prop")),
				"ref": String(operation.get("target", "")),
			}],
			"requestedResultKind": String(
				operation.get("resultKind", "daily_operation_record"),
			),
			"createdAtMinute": absolute_minute,
			"priority": int(operation.get("priority", 44)),
			"processStage": "planned",
			"processFacts": {
				"dayIndex": day_index,
				"nextActivityId": String(operation.get("activityId", "")),
			},
		})
	return task_specs


static func sync_library_catalog(
	absolute_minute: int,
	work_tasks: TownWorkTaskRuntime,
) -> Array[Dictionary]:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 540 or minute_of_day >= 960:
		return []
	var day_index := absolute_minute / 1440
	var source_ref := "library-catalog-check:%d" % day_index
	var carried_catalog_work := retire_stale_period_work_tasks(
		work_tasks,
		"library.assist",
		"daily_catalog_plan",
		source_ref,
		"新的目录核对周期已经开始",
	)
	carried_catalog_work = (
		retire_stale_period_work_tasks(
			work_tasks,
			"library.assist",
			"catalog_mismatch",
			source_ref,
			"新的目录核对周期已经开始",
		)
		or carried_catalog_work
	)
	if carried_catalog_work:
		return []
	return [{
		"taskId": source_ref,
		"capability": "library.assist",
		"sourceKind": "daily_catalog_plan",
		"sourceRef": source_ref,
		"targets": [{"kind": "prop", "ref": "图书馆借还书柜台内侧"}],
		"requestedResultKind": "catalog_state_change",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["library_catalog_check"],
		"processStage": "catalog_check_due",
		"processFacts": {
			"nextActivityId": "activity_library_staff_checkout",
		},
	}]


static func sync_civic_work(
	absolute_minute: int,
	work_tasks: TownWorkTaskRuntime,
	staffing_posts: Array,
	place_states: Array,
	weather: String,
) -> Array[Dictionary]:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 7 * 60 or minute_of_day >= 17 * 60:
		return []
	var day_index := absolute_minute / 1440
	var task_specs: Array[Dictionary] = []
	var vacancy_count := 0
	for post_value: Variant in staffing_posts:
		if (
			post_value is Dictionary
			and String((post_value as Dictionary).get("status", ""))
			== "vacant"
		):
			vacancy_count += 1
	var open_service_count := 0
	for state_value: Variant in place_states:
		if bool((state_value as Dictionary).get("open", false)):
			open_service_count += 1
	var daily_source_ref := "daily-town-state:%d" % day_index
	retire_stale_period_work_tasks(
		work_tasks,
		"civic.service",
		"public_matter",
		daily_source_ref,
		"新的镇务核对周期已经开始",
	)
	task_specs.append({
		"taskId": "civic-daily-review:%d" % day_index,
		"capability": "civic.service",
		"sourceKind": "public_matter",
		"sourceRef": daily_source_ref,
		"targets": [{"kind": "prop", "ref": "镇公所档案柜"}],
		"requestedResultKind": "civic_case_update",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["civic_case"],
		"processStage": "reviewing",
		"processFacts": {
			"dayIndex": day_index,
			"weather": weather,
			"openServiceCount": open_service_count,
			"vacancyCount": vacancy_count,
			"nextActivityId": "activity_town_hall_manage_records",
		},
	})
	if vacancy_count > 0:
		task_specs.append({
			"taskId": "civic-staffing-review:%d" % day_index,
			"capability": "staffing.coordinate",
			"sourceKind": "staffing_matter",
			"sourceRef": "staffing-vacancies",
			"targets": [{"kind": "prop", "ref": "镇公所档案柜"}],
			"requestedResultKind": "staffing_matter_update",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["staffing_review"],
			"processStage": "reviewing_staffing",
			"processFacts": {
				"vacancyCount": vacancy_count,
				"nextActivityId": "activity_town_hall_manage_records",
			},
		})
	else:
		cancel_active_work_task_for_source(
			work_tasks,
			"staffing_matter",
			"staffing-vacancies",
			"岗位空缺已经消失",
		)
	for place_value: Variant in place_states:
		var place_state := place_value as Dictionary
		var waiting_count := (
			place_state.get("pending_request_ids", []) as Array
		).size()
		var place_id := String(place_state.get("place_id", ""))
		if bool(place_state.get("open", true)) and waiting_count <= int(
			place_state.get("service_capacity", 0),
		):
			cancel_active_work_task_for_source(
				work_tasks,
				"place_service_change",
				"place-service:%s" % place_id,
				"地点服务已经恢复正常",
			)
			continue
		task_specs.append({
			"taskId": "civic-service-change:%s:%d" % [place_id, day_index],
			"capability": "civic.service",
			"sourceKind": "place_service_change",
			"sourceRef": "place-service:%s" % place_id,
			"targets": [{"kind": "prop", "ref": "镇公所档案柜"}],
			"requestedResultKind": "civic_case_update",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["civic_urgent_case"],
			"processStage": "reviewing_service_change",
			"processFacts": {
				"placeId": place_id,
				"open": bool(place_state.get("open", true)),
				"waitingRequestCount": waiting_count,
				"weather": weather,
				"nextActivityId": "activity_town_hall_manage_records",
			},
		})
	return task_specs


static func sync_warehouse_audit(
	absolute_minute: int,
	cargo_inventory: TownCargoInventoryRuntime,
	work_tasks: TownWorkTaskRuntime,
) -> Array[Dictionary]:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 8 * 60 or minute_of_day >= 17 * 60:
		return []
	var day_index := absolute_minute / 1440
	var task_specs: Array[Dictionary] = []
	var audit_source_ref := "warehouse-audit:%d" % day_index
	var carried_inventory_work := retire_stale_period_work_tasks(
		work_tasks,
		"inventory.receive",
		"daily_inventory_plan",
		audit_source_ref,
		"新的仓库盘点周期已经开始",
	)
	carried_inventory_work = (
		retire_stale_period_work_tasks(
			work_tasks,
			"inventory.receive",
			"inventory_request",
			audit_source_ref,
			"新的仓库盘点周期已经开始",
		)
		or carried_inventory_work
	)
	if carried_inventory_work:
		return []
	task_specs.append({
		"taskId": "warehouse-daily-audit:%d" % day_index,
		"capability": "inventory.receive",
		"sourceKind": "daily_inventory_plan",
		"sourceRef": audit_source_ref,
		"targets": [{"kind": "prop", "ref": "码头仓库货单桌"}],
		"requestedResultKind": "inventory_record",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["warehouse_audit"],
	})
	for lot_value: Variant in (
		cargo_inventory.snapshot() as Dictionary
	).get("cargoLots", []) as Array:
		var lot := lot_value as Dictionary
		if (
			String(lot.get("state", "")) != "awaiting_receipt"
			or absolute_minute - int(lot.get("deliveredAtMinute", 0)) < 120
		):
			continue
		var lot_id := String(lot.get("lotId", ""))
		task_specs.append({
			"taskId": "warehouse-discrepancy:%s" % lot_id,
			"capability": "inventory.receive",
			"sourceKind": "inventory_discrepancy",
			"sourceRef": lot_id,
			"targets": [{"kind": "prop", "ref": "码头仓库货单桌"}],
			"requestedResultKind": "inventory_record",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["inventory_discrepancy"],
		})
	return task_specs


static func sync_research_samples(
	absolute_minute: int,
	production: TownProductionRuntime,
	work_tasks: TownWorkTaskRuntime,
) -> Array[Dictionary]:
	var task_plans: Array[Dictionary] = []
	for project_value: Variant in production.plant_research_projects():
		var project := project_value as Dictionary
		var project_id := String(project.get("projectId", ""))
		if String(project.get("stage", "")) in ["recorded", "accessioned"]:
			var stale_task := work_tasks.active_task_for_source(
				"sample_request",
				project_id,
			) as Dictionary
			if not stale_task.is_empty() and String(
				stale_task.get("state", ""),
			) in ["open", "waiting"]:
				work_tasks.cancel_task(
					String(stale_task.get("taskId", "")),
					"研究已经完成记录，不再需要补采样本",
				)
			continue
		task_plans.append({
			"targetActivityId": "activity_garden_harvest_region",
			"fallbackRegionId": "outdoor_garden_01",
			"choiceKey": "research-sample:%s" % project_id,
			"spec": {
			"taskId": "garden-sample:%s" % project_id,
			"capability": "garden.harvest",
			"sourceKind": "sample_request",
			"sourceRef": project_id,
			"targets": [],
			"requestedResultKind": "plant_sample_lot",
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY[
				"research_sample_request"
			],
			},
		})
	return task_plans


static func semantic_region_targets(
	activity_runtime: TownWorldActivityRuntime,
	activity_id: String,
	fallback_region_id: String,
	choice_key: String,
	absolute_minute: int,
) -> Dictionary:
	var result: Array[Dictionary] = []
	for value: Variant in activity_runtime.semantic_region_targets(activity_id):
		var target := value as Dictionary
		var region_id := String(target.get("ref", ""))
		if region_id.is_empty():
			continue
		result.append({"kind": "region", "ref": region_id})
	if result.is_empty() and not fallback_region_id.is_empty():
		result.append({"kind": "region", "ref": fallback_region_id})
	var candidate_count := result.size()
	if candidate_count <= 1:
		return {"targets": result, "candidateCount": candidate_count}
	var selection_seed := "%s:%s:%d" % [
		activity_id,
		choice_key,
		absolute_minute,
	]
	return {
		"targets": [result[posmod(hash(selection_seed), result.size())]],
		"candidateCount": candidate_count,
	}


static func sync_plant_research(
	absolute_minute: int,
	care_plot: Dictionary,
	production: TownProductionRuntime,
	occupation_services: TownOccupationServiceRuntime,
	botanist_id: String,
) -> Dictionary:
	var day_index := absolute_minute / 1440
	for project_value: Variant in production.plant_research_projects():
		var project := project_value as Dictionary
		if String(project.get("stage", "question")) != "accessioned":
			return {}
		if int(project.get("createdAtMinute", -1440)) / 1440 == day_index:
			return {}
	if botanist_id.is_empty():
		return {}
	var research_plot := care_plot.duplicate(true)
	if research_plot.is_empty():
		var garden_plots := (
			(production.snapshot() as Dictionary).get("gardenPlots", []) as Array
		)
		if garden_plots.is_empty():
			return {}
		research_plot = (
			garden_plots[posmod(day_index, garden_plots.size())] as Dictionary
		).duplicate(true)
	var plot_id := String(research_plot.get("plotId", ""))
	var source_kind := (
		"abnormal_plant" if not care_plot.is_empty() else "personal_research_plan"
	)
	var question := (
		"%s 的湿度和杂草变化是否需要调整照料方式" % plot_id
		if source_kind == "abnormal_plant"
		else "继续核对 %s 的长期湿度与生长记录" % plot_id
	)
	for request_value: Variant in (
		(occupation_services.snapshot() as Dictionary).get("requests", []) as Array
	):
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) == "clinic"
			and String(request.get("state", "")) in ["pending", "waiting"]
		):
			source_kind = "clinic_request"
			question = "诊所当前接诊记录涉及的植物照料资料是否需要补充验证"
			break
	if source_kind != "clinic_request" and day_index > 0 and posmod(
		day_index,
		7,
	) == 0:
		source_kind = "season_change"
		question = "进入新的七日生长周期后，%s 的变化是否符合当前照料记录" % plot_id
	elif source_kind != "clinic_request" and posmod(day_index, 5) == 2:
		source_kind = "research_question"
		question = "%s 当前花木状态与图书馆既有记录是否一致" % plot_id
	elif source_kind != "clinic_request" and posmod(day_index, 3) == 1:
		source_kind = "personal_research_plan"
		question = "继续核对 %s 的长期湿度与生长记录" % plot_id
	return {
		"requesterId": botanist_id,
		"question": question,
		"sourceKind": source_kind,
	}


static func plant_research_stage_task_spec(
	project: Dictionary,
	stage: String,
	observe_targets: Array[Dictionary],
) -> Dictionary:
	var project_id := String(project.get("projectId", ""))
	var capability := ""
	var targets: Array[Dictionary] = []
	match stage:
		"observe":
			capability = "research.observe"
			targets.assign(observe_targets)
		"verify":
			capability = "research.verify"
			targets = [{"kind": "prop", "ref": "图书馆西侧高书架"}]
		"record":
			capability = "research.record"
			targets = [{"kind": "prop", "ref": "图书馆写作桌"}]
		_:
			return {
				"ok": false,
				"errorCode": "PLANT_RESEARCH_STAGE_INVALID",
			}
	return {"ok": true, "spec": {
		"taskId": "research-task:%s:%s" % [project_id, stage],
		"capability": capability,
		"sourceKind": String(project.get("sourceKind", "")),
		"sourceRef": project_id,
		"targets": targets,
		"requestedResultKind": "research_record",
		"priority": (
			62
			if String(project.get("sourceKind", "")) == "abnormal_plant"
			else 74
		),
	}}


static func sync_music_work(
	absolute_minute: int,
	performance_request_exists: bool,
	musician_id: String,
) -> Dictionary:
	var service_requests: Array[Dictionary] = []
	var task_plans: Array[Dictionary] = []
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day < 9 * 60 or minute_of_day >= 18 * 60:
		return {"serviceRequests": service_requests, "taskPlans": task_plans}
	var day_index := absolute_minute / 1440
	if (
		posmod(day_index, 3) == 0
		and not performance_request_exists
		and not musician_id.is_empty()
	):
		service_requests.append({
			"kind": "performance",
			"requesterResidentId": musician_id,
			"subjectRef": "public-event-day:%d" % day_index,
			"context": {
				"generatedFromPublicEvent": true,
				"dayIndex": day_index,
			},
		})
	var source_ref := "music-rehearsal-day:%d" % day_index
	task_plans.append({
		"targetActivityId": "activity_musician_rehearse",
		"fallbackRegionId": "outdoor_river_park_01",
		"choiceKey": "music-rehearsal:%d" % day_index,
		"spec": {
		"taskId": "music-rehearsal:%d" % day_index,
		"capability": "music.rehearse",
		"sourceKind": "personal_performance_plan",
		"sourceRef": source_ref,
		"targets": [],
		"requestedResultKind": "rehearsal_record",
		"createdAtMinute": absolute_minute,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["music_rehearsal_plan"],
		},
	})
	return {
		"serviceRequests": service_requests,
		"taskPlans": task_plans,
		"sourceRef": source_ref,
	}


static func specialty_service_demand_plan(
	kind: String,
	item_id: String,
	request_id: String,
	now: int,
	cargo_inventory: TownCargoInventoryRuntime,
	work_tasks: TownWorkTaskRuntime,
	occupation_services: TownOccupationServiceRuntime,
) -> Dictionary:
	if kind == "cafe_order" and item_id == "pastry":
		if (
			has_active_cargo_to_place(
				cargo_inventory,
				"pastry",
				CONTENT_CATALOG.PLACE_CAFE,
			)
			or has_active_specialty_production(
				work_tasks,
				"pastry",
				CONTENT_CATALOG.PLACE_CAFE,
			)
		):
			return {}
		return {"spec": {
			"taskId": "pastry-order-production:%s" % request_id,
			"capability": "food.production",
			"sourceKind": "meal_demand",
			"sourceRef": "pastry-order:%s" % request_id,
			"targets": [
				{"kind": "prop", "ref": "公共食堂备餐柜"},
				{"kind": "prop", "ref": "公共食堂灶台"},
			],
			"requestedResultKind": "food_batch",
			"createdAtMinute": now,
			"priority": CONTENT_CATALOG.TASK_PRIORITY[
				"specialty_meal_demand"
			],
			"processStage": "planned",
			"processFacts": {
				"productItemId": "pastry",
				"destinationPlaceId": CONTENT_CATALOG.PLACE_CAFE,
				"serviceRequestId": request_id,
				"nextActivityId": "activity_baker_prepare_dough",
			},
		}}
	if kind == "grocer_sale" and item_id == CONTENT_CATALOG.ITEM_FISH:
		if (
			has_active_cargo_to_place(
				cargo_inventory,
				CONTENT_CATALOG.ITEM_FISH,
				CONTENT_CATALOG.PLACE_MARKET,
			)
			or has_active_work_task_capability(work_tasks, "fishing.harvest")
		):
			return {}
		return {
			"targetActivityId": "activity_fisher_catch_in_region",
			"fallbackRegionId": "outdoor_harbor_01",
			"choiceKey": "fish-demand:%s" % request_id,
			"spec": {
				"taskId": "fishing-demand:%s" % request_id,
				"capability": "fishing.harvest",
				"sourceKind": "fish_demand",
				"sourceRef": "fish-demand:%s" % request_id,
				"targets": [],
				"requestedResultKind": "fishing_outcome",
				"createdAtMinute": now,
				"priority": CONTENT_CATALOG.TASK_PRIORITY[
					"specialty_fishing_demand"
				],
			},
		}
	if (
		item_id != CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET
		or kind not in ["clinic", "grocer_sale"]
	):
		return {}
	var request := occupation_services.request(request_id) as Dictionary
	var record_id := String(
		(request.get("context", {}) as Dictionary).get("researchRecordId", ""),
	).strip_edges()
	var destination_place_id := (
		CONTENT_CATALOG.PLACE_CLINIC
		if kind == "clinic"
		else CONTENT_CATALOG.PLACE_MARKET
	)
	if (
		record_id.is_empty()
		or not (occupation_services.accession_for_record(
			record_id,
		) as Dictionary).has("accessionId")
		or int(cargo_inventory.inventory_quantity(
			destination_place_id,
			CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
		)) > 0
		or has_active_cargo_to_place(
			cargo_inventory,
			CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			destination_place_id,
		)
		or has_active_specialty_production(
			work_tasks,
			CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			destination_place_id,
		)
	):
		return {}
	return {"spec": {
		"taskId": "research-booklet:%s" % request_id,
		"capability": "research.handoff",
		"sourceKind": "personal_research_plan",
		"sourceRef": "booklet-demand:%s" % request_id,
		"targets": [{"kind": "prop", "ref": "图书馆写作桌"}],
		"requestedResultKind": "handwritten_booklet",
		"createdAtMinute": now,
		"priority": CONTENT_CATALOG.TASK_PRIORITY[
			"research_booklet_handoff"
		],
		"processStage": "booklet_planned",
		"processFacts": {
			"recordId": record_id,
			"productItemId": CONTENT_CATALOG.ITEM_RESEARCH_BOOKLET,
			"serviceRequestId": request_id,
			"destinationPlaceId": destination_place_id,
			"nextActivityId": "activity_botanist_record_plants",
		},
	}}
