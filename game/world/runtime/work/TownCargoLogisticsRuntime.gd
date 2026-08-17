class_name TownCargoLogisticsRuntime
extends RefCounted


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const MAX_SELF_CARRIED_CARGO_QUANTITY := 2


static func public_result(result: Dictionary) -> Dictionary:
	var public_value := result.duplicate(true)
	public_value.erase("logStatus")
	public_value.erase("scheduleOccupationIds")
	public_value.erase("scheduleResidentIds")
	public_value.erase("cargoCommand")
	return public_value


static func create_lot(
	cargo_inventory: TownCargoInventoryRuntime,
	work_tasks: TownWorkTaskRuntime,
	spec: Dictionary,
	origin_kind: String,
	absolute_minute: int,
	delivery_post_vacant: bool,
	owners: Dictionary,
	resident_id_by_name: Dictionary,
	residents: Dictionary,
	resident_order: Array[String],
) -> Dictionary:
	var prepared := spec.duplicate(true)
	if not prepared.has("createdAtMinute"):
		prepared["createdAtMinute"] = absolute_minute
	var cargo_result := _create_inventory_lot(
		cargo_inventory,
		prepared,
		origin_kind,
	)
	if cargo_result.get("ok") != true:
		return cargo_result
	var lot := cargo_result.get("lot", {}) as Dictionary
	var fallback_ids := fallback_carrier_ids(
		lot,
		owners,
		resident_id_by_name,
		residents,
		resident_order,
	)
	var priority := int(prepared.get("priority", 70))
	var task_result: Dictionary
	var schedule_occupations: Array[String] = []
	var schedule_residents: Array[String] = []
	var log_status := "ongoing"
	if String(lot.get("state", "")) == "awaiting_release":
		task_result = work_tasks.create_task_for_occupations(
			_release_task_spec(lot, priority),
			["occupation_warehouse_keeper"],
		) as Dictionary
		schedule_occupations.append("occupation_warehouse_keeper")
		log_status = "waiting"
	else:
		task_result = work_tasks.create_task_for_occupations(
			_delivery_task_spec(lot, priority),
			["occupation_delivery_worker"],
		) as Dictionary
		if (
			task_result.get("ok") == true
			and int(lot.get("quantity", 0))
			<= MAX_SELF_CARRIED_CARGO_QUANTITY
			and delivery_post_vacant
			and not fallback_ids.is_empty()
		):
			var task := task_result.get("task", {}) as Dictionary
			var granted := work_tasks.add_eligible_residents(
				String(task.get("taskId", "")),
				fallback_ids,
			) as Dictionary
			if granted.get("ok") == true:
				task_result = granted
				schedule_residents.assign(fallback_ids)
		schedule_occupations.append("occupation_delivery_worker")
	if task_result.get("ok") != true:
		cargo_inventory.cancel_available_lot(
			String(lot.get("lotId", "")),
			absolute_minute,
		)
		return task_result
	return {
		"ok": true,
		"changed": true,
		"lot": lot.duplicate(true),
		"task": (
			task_result.get("task", {}) as Dictionary
		).duplicate(true),
		"logStatus": log_status,
		"scheduleOccupationIds": schedule_occupations,
		"scheduleResidentIds": schedule_residents,
	}


static func pickup(
	cargo_inventory: TownCargoInventoryRuntime,
	work_tasks: TownWorkTaskRuntime,
	lot_id: String,
	resident_id: String,
	resident_place: String,
	absolute_minute: int,
	authorized: bool,
	acceptance_occupation_id: String,
) -> Dictionary:
	var task := work_tasks.task("delivery-task:%s" % lot_id) as Dictionary
	if not authorized:
		return _failure(
			"CARGO_PICKUP_NOT_AUTHORIZED",
			"当前居民不是这批货的送货负责人",
		)
	var lot := cargo_inventory.cargo_lot(lot_id) as Dictionary
	if (
		String(lot.get("state", "")) != "available"
		or resident_place != String(lot.get("sourcePlaceId", ""))
	):
		return _failure(
			"CARGO_PICKUP_INVALID",
			"居民必须到真实来源地点领取仍可用的货批",
		)
	if String(task.get("state", "")) in ["open", "waiting"]:
		var accepted := work_tasks.accept_task(
			String(task.get("taskId", "")),
			resident_id,
			acceptance_occupation_id,
			int(task.get("revision", 0)),
		) as Dictionary
		if accepted.get("ok") != true:
			return accepted
		task = accepted.get("task", {}) as Dictionary
	if String(task.get("state", "")) == "accepted":
		var started := work_tasks.start_task(
			String(task.get("taskId", "")),
			resident_id,
			int(task.get("revision", 0)),
		) as Dictionary
		if started.get("ok") != true:
			return started
		task = started.get("task", {}) as Dictionary
	if (
		String(task.get("state", "")) != "in_progress"
		or String(task.get("assignedResidentId", "")) != resident_id
	):
		return _failure(
			"CARGO_WORK_TASK_INVALID",
			"货运任务未由当前居民正式接取",
		)
	var picked_up := cargo_inventory.pickup(
		lot_id,
		resident_id,
		resident_place,
		absolute_minute,
	) as Dictionary
	if picked_up.get("ok") != true:
		return picked_up
	return {
		"ok": true,
		"changed": true,
		"lot": (
			picked_up.get("lot", {}) as Dictionary
		).duplicate(true),
		"task": task.duplicate(true),
	}


static func create_delivery_task(
	work_tasks: TownWorkTaskRuntime,
	lot: Dictionary,
	priority: int,
	delivery_post_vacant: bool,
	fallback_ids: Array[String],
) -> Dictionary:
	var created := work_tasks.create_task_for_occupations(
		_delivery_task_spec(lot, priority),
		["occupation_delivery_worker"],
	) as Dictionary
	var scheduled_residents: Array[String] = []
	if (
		created.get("ok") == true
		and int(lot.get("quantity", 0)) <= MAX_SELF_CARRIED_CARGO_QUANTITY
		and delivery_post_vacant
		and not fallback_ids.is_empty()
	):
		var task := created.get("task", {}) as Dictionary
		var granted := work_tasks.add_eligible_residents(
			String(task.get("taskId", "")),
			fallback_ids,
		) as Dictionary
		if granted.get("ok") == true:
			created = granted
			scheduled_residents.assign(fallback_ids)
	created["scheduleResidentIds"] = scheduled_residents
	return created


static func deliver(
	cargo_inventory: TownCargoInventoryRuntime,
	work_tasks: TownWorkTaskRuntime,
	lot_id: String,
	resident_id: String,
	resident_place: String,
	absolute_minute: int,
	owners: Dictionary,
) -> Dictionary:
	var lot := cargo_inventory.cargo_lot(lot_id) as Dictionary
	var task := work_tasks.task("delivery-task:%s" % lot_id) as Dictionary
	if (
		String(lot.get("state", "")) != "in_transit"
		or String(lot.get("carrierResidentId", "")) != resident_id
		or resident_place != String(lot.get("destinationPlaceId", ""))
		or String(task.get("state", "")) != "in_progress"
		or String(task.get("assignedResidentId", "")) != resident_id
	):
		return _failure(
			"CARGO_DELIVERY_INVALID",
			"同一送货员必须带着货批到达真实目的地",
		)
	var delivered := cargo_inventory.deliver(
		lot_id,
		resident_id,
		resident_place,
		absolute_minute,
	) as Dictionary
	if delivered.get("ok") != true:
		return delivered
	var completed := work_tasks.complete_task(
		String(task.get("taskId", "")),
		resident_id,
		int(task.get("revision", 0)),
		"cargo_transfer",
		{
			"resultRef": "cargo-arrival:%s" % lot_id,
			"facts": {
				"lotId": lot_id,
				"sourcePlaceId": String(lot.get("sourcePlaceId", "")),
				"destinationPlaceId": String(
					lot.get("destinationPlaceId", ""),
				),
				"carrierResidentId": resident_id,
				"receiptPending": true,
			},
		},
	) as Dictionary
	if completed.get("ok") != true:
		return completed
	var delivered_lot := delivered.get("lot", {}) as Dictionary
	var receipt := _create_receipt_task(
		work_tasks,
		delivered_lot,
		absolute_minute,
	)
	var receipt_task := receipt.get("task", {}) as Dictionary
	var destination := String(delivered_lot.get("destinationPlaceId", ""))
	if receipt_task.is_empty() and owners.has(destination):
		cargo_inventory.receive(
			lot_id,
			String(owners.get(destination, resident_id)),
			destination,
			absolute_minute,
		)
	return {
		"ok": true,
		"changed": true,
		"lot": delivered_lot.duplicate(true),
		"task": (
			completed.get("task", {}) as Dictionary
		).duplicate(true),
		"receiptTask": receipt_task.duplicate(true),
		"scheduleOccupationIds": (
			receipt.get("occupationIds", []) as Array
		).duplicate(),
	}


static func fallback_carrier_ids(
	lot: Dictionary,
	owners: Dictionary,
	resident_id_by_name: Dictionary,
	residents: Dictionary,
	resident_order: Array[String],
) -> Array[String]:
	var result: Array[String] = []
	var places := [
		String(lot.get("sourcePlaceId", "")),
		String(lot.get("destinationPlaceId", "")),
	]
	for place_id: String in places:
		var owner_ref := String(owners.get(place_id, ""))
		var owner_id := (
			owner_ref
			if residents.has(owner_ref)
			else String(resident_id_by_name.get(owner_ref, ""))
		)
		if not owner_id.is_empty() and not result.has(owner_id):
			result.append(owner_id)
	for resident_id: String in resident_order:
		var resident := residents.get(resident_id, {}) as Dictionary
		var social_state := resident.get("socialState", {}) as Dictionary
		if (
			places.has(String(social_state.get("workplace", "")))
			and not result.has(resident_id)
		):
			result.append(resident_id)
	result.sort()
	return result


static func sync_vacant_delivery_fallbacks(
	cargo_inventory: TownCargoInventoryRuntime,
	work_tasks: TownWorkTaskRuntime,
	owners: Dictionary,
	resident_id_by_name: Dictionary,
	residents: Dictionary,
	resident_order: Array[String],
) -> Array[String]:
	var scheduled: Array[String] = []
	for lot_value: Variant in (
		cargo_inventory.snapshot() as Dictionary
	).get("cargoLots", []) as Array:
		var lot := lot_value as Dictionary
		if (
			String(lot.get("state", "")) not in ["available", "in_transit"]
			or int(lot.get("quantity", 0)) > MAX_SELF_CARRIED_CARGO_QUANTITY
		):
			continue
		var task_id := "delivery-task:%s" % String(lot.get("lotId", ""))
		var task := work_tasks.task(task_id) as Dictionary
		if task.is_empty() or String(task.get("state", "")) in [
			"completed",
			"failed",
			"cancelled",
		]:
			continue
		var fallback_ids := fallback_carrier_ids(
			lot,
			owners,
			resident_id_by_name,
			residents,
			resident_order,
		)
		if fallback_ids.is_empty():
			continue
		var granted := work_tasks.add_eligible_residents(
			task_id,
			fallback_ids,
		) as Dictionary
		if granted.get("ok") == true:
			for resident_id: String in fallback_ids:
				if not scheduled.has(resident_id):
					scheduled.append(resident_id)
	return scheduled


static func _create_inventory_lot(
	cargo_inventory: TownCargoInventoryRuntime,
	spec: Dictionary,
	origin_kind: String,
) -> Dictionary:
	if origin_kind == "external_supply":
		return cargo_inventory.create_external_supply_lot(spec)
	if origin_kind == "world_result":
		return cargo_inventory.create_world_result_lot(spec)
	return cargo_inventory.create_local_lot(spec)


static func _release_task_spec(
	lot: Dictionary,
	priority: int,
) -> Dictionary:
	var lot_id := String(lot.get("lotId", ""))
	return {
		"taskId": "cargo-release-task:%s" % lot_id,
		"capability": "inventory.release",
		"sourceKind": "inventory_request",
		"sourceRef": lot_id,
		"targets": [
			{"kind": "cargo_lot", "ref": lot_id},
			{"kind": "prop", "ref": "码头仓库货单桌"},
		],
		"requestedResultKind": "release_lot",
		"createdAtMinute": int(lot.get("createdAtMinute", 0)),
		"priority": priority,
	}


static func _delivery_task_spec(
	lot: Dictionary,
	priority: int,
) -> Dictionary:
	var lot_id := String(lot.get("lotId", ""))
	return {
		"taskId": "delivery-task:%s" % lot_id,
		"capability": "cargo.deliver",
		"sourceKind": (
			"external_supply_arrival"
			if String(lot.get("originKind", "")) == "external_supply"
			else "cargo_available"
		),
		"sourceRef": lot_id,
		"targets": [
			{"kind": "cargo_lot", "ref": lot_id},
			{
				"kind": "route",
				"ref": "%s->%s" % [
					String(lot.get("sourcePlaceId", "")),
					String(lot.get("destinationPlaceId", "")),
				],
			},
		],
		"requestedResultKind": "cargo_transfer",
		"createdAtMinute": int(lot.get("createdAtMinute", 0)),
		"priority": priority,
	}


static func _create_receipt_task(
	work_tasks: TownWorkTaskRuntime,
	lot: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var plan := _receipt_task_plan(lot, absolute_minute)
	if plan.is_empty():
		return {"task": {}, "occupationIds": []}
	var occupation_ids := plan.get("occupationIds", []) as Array
	var created := work_tasks.create_task_for_occupations(
		plan.get("spec", {}) as Dictionary,
		occupation_ids,
	) as Dictionary
	if created.get("ok") != true:
		return {"task": {}, "occupationIds": []}
	return {
		"task": (
			created.get("task", {}) as Dictionary
		).duplicate(true),
		"occupationIds": occupation_ids.duplicate(),
	}


static func _receipt_task_plan(
	lot: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var destination := String(lot.get("destinationPlaceId", ""))
	var capability := ""
	var result_kind := ""
	var source_kind := "incoming_cargo"
	var occupation_ids: Array[String] = []
	if destination == CONTENT_CATALOG.PLACE_WAREHOUSE:
		capability = "inventory.receive"
		result_kind = "inventory_change"
		occupation_ids = ["occupation_warehouse_keeper"]
	elif destination == CONTENT_CATALOG.PLACE_MARKET:
		capability = "retail.receive"
		result_kind = "retail_stock_change"
		if String(lot.get("itemId", "")) in [
			CONTENT_CATALOG.ITEM_FRESH_FLOWERS,
			CONTENT_CATALOG.ITEM_BOUQUET,
		]:
			source_kind = "flower_cargo"
			occupation_ids = ["occupation_flower_vendor"]
		else:
			occupation_ids = ["occupation_grocer"]
	elif destination == CONTENT_CATALOG.PLACE_CAFE:
		capability = "cafe.production"
		result_kind = "stock_change"
		occupation_ids = ["occupation_cafe_worker"]
	elif destination == CONTENT_CATALOG.PLACE_DINING_HALL:
		capability = "food.production"
		result_kind = "stock_change"
		occupation_ids = ["occupation_dining_operator"]
	elif destination == CONTENT_CATALOG.PLACE_CLINIC:
		capability = "care.treatment"
		result_kind = "stock_change"
		occupation_ids = ["occupation_clinic_practitioner"]
	elif destination == CONTENT_CATALOG.PLACE_WORKSHOP:
		capability = "craft.production"
		result_kind = "stock_change"
		occupation_ids = ["occupation_craftsperson"]
	elif destination == CONTENT_CATALOG.PLACE_LIBRARY:
		capability = "library.accession"
		result_kind = "stock_change"
		occupation_ids = ["occupation_librarian"]
	else:
		return {}
	var lot_id := String(lot.get("lotId", ""))
	return {
		"spec": {
			"taskId": "receipt-task:%s" % lot_id,
			"capability": capability,
			"sourceKind": source_kind,
			"sourceRef": lot_id,
			"targets": [{"kind": "cargo_lot", "ref": lot_id}],
			"requestedResultKind": result_kind,
			"createdAtMinute": absolute_minute,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["cargo_receipt"],
		},
		"occupationIds": occupation_ids,
	}


static func _failure(error_code: String, issue: String) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"errorCode": error_code,
		"issues": [issue],
	}
