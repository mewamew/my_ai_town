class_name TownCargoCommandRuntime
extends RefCounted


const CARGO_LOGISTICS_RUNTIME := preload(
	"res://world/runtime/work/TownCargoLogisticsRuntime.gd"
)
const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


static func create(host, spec: Dictionary, origin_kind: String) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var result: Dictionary = host._work.create_cargo_lot(
		spec,
		origin_kind,
		int(host._environment.get_absolute_minute()),
		host._work.occupation_post_is_vacant("occupation_delivery_worker"),
		host.world_definition.owners,
		host.resident_registry.id_by_name,
		host.resident_registry.records,
		host.resident_registry.order,
	)
	return commit(host, result)


static func pickup(host, lot_id: String, resident_ref: String) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id: String = host._resident_key(resident_ref)
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var task := host._work.tasks.task("delivery-task:%s" % lot_id) as Dictionary
	var result: Dictionary = host._work.pickup_cargo_lot(
		lot_id,
		resident_ref,
		resident_id,
		String(resident.get("currentPlace", "")),
		int(host._environment.get_absolute_minute()),
		host._resident_can_accept_work_task(resident_id, task),
		host._task_acceptance_occupation_id(resident_id, task),
	)
	return commit(host, result)


static func deliver(host, lot_id: String, resident_ref: String) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id: String = host._resident_key(resident_ref)
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var result: Dictionary = host._work.deliver_cargo_lot(
		lot_id,
		resident_ref,
		resident_id,
		String(resident.get("currentPlace", "")),
		int(host._environment.get_absolute_minute()),
		host.world_definition.owners,
	)
	return commit(host, result)


static func commit(host, result: Dictionary) -> Dictionary:
	if result.get("ok") != true:
		return host._decorate_command_result(result)
	var command := result.get("cargoCommand", {}) as Dictionary
	var reserve_occupation_id := String(command.get("reserveOccupationId", ""))
	if not reserve_occupation_id.is_empty():
		result["task"] = host.WORK_TASK_PUBLIC_RUNTIME.reserve(
			host,
			result.get("task", {}) as Dictionary,
			reserve_occupation_id,
		)
	host._bump_world_revision()
	WORLD_LOG_COMMIT_RUNTIME.append_cargo(
		host,
		String(command.get("logLabel", "")),
		result.get("lot", {}) as Dictionary,
		String(command.get("logActorResidentId", "")),
		String(command.get("logStatus", "ongoing")),
	)
	for occupation_value: Variant in result.get("scheduleOccupationIds", []) as Array:
		schedule_occupation_decisions(host, String(occupation_value))
	for resident_value: Variant in result.get("scheduleResidentIds", []) as Array:
		host._schedule_decision(String(resident_value), true)
	return host._decorate_command_result(CARGO_LOGISTICS_RUNTIME.public_result(result))


static func schedule_occupation_decisions(host, occupation_id: String) -> void:
	for resident_id: String in host.resident_registry.order:
		if host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(host, resident_id, occupation_id):
			host._schedule_decision(resident_id, true)


static func create_delivery_task(
	host,
	lot: Dictionary,
	priority: int,
) -> Dictionary:
	var created: Dictionary = CARGO_LOGISTICS_RUNTIME.create_delivery_task(
		host._work.tasks,
		lot,
		priority,
		host._work.occupation_post_is_vacant("occupation_delivery_worker"),
		CARGO_LOGISTICS_RUNTIME.fallback_carrier_ids(
			lot,
			host.world_definition.owners,
			host.resident_registry.id_by_name,
			host.resident_registry.records,
			host.resident_registry.order,
		),
	)
	for resident_value: Variant in created.get("scheduleResidentIds", []) as Array:
		host._schedule_decision(String(resident_value), true)
	created.erase("scheduleResidentIds")
	if created.get("ok") == true:
		created["task"] = host.WORK_TASK_PUBLIC_RUNTIME.reserve(
			host,
			created.get("task", {}) as Dictionary,
			"occupation_delivery_worker",
		)
	return created


static func settle_arrival(host, resident_id: String) -> void:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var current_place := String(resident.get("currentPlace", ""))
	var carried := host._work.cargo.lots_for_resident(resident_id) as Array
	for lot_value: Variant in carried:
		var lot := lot_value as Dictionary
		if String(lot.get("destinationPlaceId", "")) == current_place:
			deliver(host, String(lot.get("lotId", "")), resident_id)
			return
	var candidates: Array[Dictionary] = []
	for task_value: Variant in host.get_work_tasks_for_resident(resident_id):
		var task := task_value as Dictionary
		if String(task.get("capability", "")) != "cargo.deliver":
			continue
		var lot := host._work.cargo.cargo_lot(
			String(task.get("source_ref", "")),
		) as Dictionary
		if (
			String(lot.get("state", "")) == "available"
			and String(lot.get("sourcePlaceId", "")) == current_place
		):
			candidates.append(lot)
	if candidates.size() == 1:
		pickup(host, String(candidates[0].get("lotId", "")), resident_id)
