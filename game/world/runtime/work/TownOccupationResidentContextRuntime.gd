class_name TownOccupationResidentContextRuntime
extends RefCounted

const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)


static func living_residents_for_staffing(host) -> Dictionary:
	var result := {}
	for resident_id: String in host.resident_registry.order:
		if (
			host._resident_lifecycle.is_alive(resident_id)
			and host.resident_registry.records.has(resident_id)
		):
			result[resident_id] = host.resident_registry.records[resident_id]
	return result


static func primary_id(host, resident: Dictionary) -> String:
	return host._work.primary_occupation_id(
		resident,
		host.world_definition.world_data,
	)


static func first_resident(host, occupation_id: String) -> String:
	for resident_id: String in host.resident_registry.order:
		if can_work_occupation(host, resident_id, occupation_id):
			return resident_id
	return ""


static func can_work_occupation(
	host,
	resident_id: String,
	occupation_id: String,
) -> bool:
	return ids_for_resident(host, resident_id).has(occupation_id)


static func is_on_leave(
	host,
	resident: Dictionary,
	absolute_minute := -1,
) -> bool:
	return ACTION_SUPPORT.resident_is_on_leave(
		host, resident, absolute_minute,
	)


static func available_for_work(host, resident: Dictionary) -> bool:
	return host.resident_is_present(resident) and not is_on_leave(host, resident)


static func definition(host, occupation_id: String) -> Dictionary:
	var normalized := occupation_id.strip_edges()
	if normalized.is_empty():
		return {}
	for value: Variant in (
		host.world_definition.world_data.get("occupations", []) as Array
	):
		if (
			value is Dictionary
			and String((value as Dictionary).get("occupationId", "")) == normalized
		):
			return (value as Dictionary).duplicate(true)
	return {}


static func ids_for_resident(host, resident_id: String) -> Array[String]:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	return host._work.occupation_ids_for_resident(
		resident_id,
		resident,
		host.world_definition.world_data,
		int(host._environment.get_absolute_minute()),
	)


static func id_for_activity(
	host,
	resident_id: String,
	activity_id: String,
) -> String:
	return host._work.occupation_id_for_activity(
		ids_for_resident(host, resident_id),
		activity_id,
		resident_id,
		primary_id(
			host,
			host.resident_registry.records.get(resident_id, {}) as Dictionary,
		),
	)


static func activity_social_state(
	host,
	resident_id: String,
	activity_id: String,
) -> Dictionary:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var social_state := (
		resident.get("socialState", {}) as Dictionary
	).duplicate(true)
	var occupation_id := id_for_activity(host, resident_id, activity_id)
	if not occupation_id.is_empty():
		social_state["occupationId"] = occupation_id
	return social_state


static func home_place(host, resident_id: String) -> String:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var home := String(
		(resident.get("socialState", {}) as Dictionary).get("home", ""),
	).strip_edges()
	if not home.is_empty():
		return home
	for place_value: Variant in host.world_definition.owners:
		var place_id := String(place_value)
		if (
			String(host.world_definition.owners.get(place_id, "")) == resident_id
			and place_id.contains("住宅")
		):
			return place_id
	return ""


static func sync_staffing_matters(host) -> void:
	if not host._running or host._environment == null:
		return
	var now := int(host._environment.get_absolute_minute())
	var plan: Dictionary = host._work.staffing_matter_plan_for_residents(
		host._running,
		host.resident_registry.order,
		host.resident_registry.records,
		host.world_definition.world_data,
		host.MAX_SOCIAL_RESPONSE_CANDIDATES,
		maxi(host._world_revision, 0),
		now,
	)
	var signature := plan.get("signature", []) as Array
	if host.social_coordination_state.staffing_sync_is_fresh(
		signature,
		now,
		host.STAFFING_MATTER_REFRESH_INTERVAL_MINUTES,
	):
		return
	for source: Dictionary in plan.get("sources", []) as Array:
		host.sync_job_vacancy(source)
	host.social_coordination_state.record_staffing_sync(signature, now)
