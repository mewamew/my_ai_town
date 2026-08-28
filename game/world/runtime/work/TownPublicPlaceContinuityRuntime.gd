class_name TownPublicPlaceContinuityRuntime
extends RefCounted


const DISABLED_REASON := "PUBLIC_PLACE_SERVICE_UNSTAFFED"


static func can_admit_without_service_staff(
	host,
	place_id: String,
) -> bool:
	return (
		not unstaffed_visitor_activity_ids(host, place_id).is_empty()
		and not has_executable_service_staff(host, place_id)
	)


static func apply_activity_availability(
	host,
	option: Dictionary,
) -> void:
	if (
		not bool(option.get("available", false))
		or String(option.get("role", "")) != "visitor"
	):
		return
	var place_id := String(option.get("placeId", ""))
	var activity_id := String(option.get("activityId", ""))
	if not activity_blocked_when_unstaffed(
		host,
		place_id,
		activity_id,
	):
		return
	option["available"] = false
	option["disabledReason"] = DISABLED_REASON


static func activity_blocked_when_unstaffed(
	host,
	place_id: String,
	activity_id: String,
) -> bool:
	var allowed_activity_ids := unstaffed_visitor_activity_ids(
		host,
		place_id,
	)
	return (
		not allowed_activity_ids.is_empty()
		and not has_executable_service_staff(host, place_id)
		and not allowed_activity_ids.has(activity_id)
	)


static func has_executable_service_staff(host, place_id: String) -> bool:
	var service_state := host._work.place_services.state(place_id) as Dictionary
	var occupation_id := String(
		service_state.get("service_occupation_id", ""),
	)
	if occupation_id.is_empty():
		return false
	var post := host._work.staffing.post_for_occupation(
		occupation_id,
	) as Dictionary
	if post.is_empty() or String(post.get("status", "vacant")) == "vacant":
		return false
	for resident_id_value: Variant in post.get(
		"responsibleResidentIds",
		[],
	) as Array:
		var resident_id := String(resident_id_value)
		var resident := host.resident_registry.records.get(
			resident_id,
			{},
		) as Dictionary
		if (
			not resident.is_empty()
			and host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.available_for_work(
				host,
				resident,
			)
			and host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(
				host,
				resident_id,
				occupation_id,
			)
		):
			return true
	return false


static func unstaffed_visitor_activity_ids(
	host,
	place_id: String,
) -> Array[String]:
	var result: Array[String] = []
	for place_value: Variant in (
		host.world_definition.world_data.get("places", []) as Array
	):
		if (
			place_value is not Dictionary
			or String((place_value as Dictionary).get("name", "")) != place_id
		):
			continue
		var profile := (
			(place_value as Dictionary).get("serviceProfile", {}) as Dictionary
		)
		for activity_id_value: Variant in profile.get(
			"unstaffedVisitorActivityIds",
			[],
		) as Array:
			result.append(String(activity_id_value))
		break
	return result
