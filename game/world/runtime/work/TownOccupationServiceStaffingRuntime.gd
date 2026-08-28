class_name TownOccupationServiceStaffingRuntime
extends RefCounted


static func executable_worker_ids(
	host,
	occupation_id: String,
	capability: String,
) -> Array[String]:
	var result: Array[String] = []
	var normalized_occupation_id := occupation_id.strip_edges()
	var normalized_capability := capability.strip_edges()
	if normalized_occupation_id.is_empty() or normalized_capability.is_empty():
		return result
	var absolute_minute := int(host._authoritative_absolute_minute())
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records.get(
			resident_id,
			{},
		) as Dictionary
		if not host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.available_for_work(
			host,
			resident,
		):
			continue
		if host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.primary_id(
			host,
			resident,
		) == normalized_occupation_id:
			result.append(resident_id)
			continue
		if host.work_domain.staffing.active_assignment_allows_capability(
			resident_id,
			normalized_occupation_id,
			normalized_capability,
			absolute_minute,
		):
			result.append(resident_id)
	return result


static func service_has_executable_worker(
	host,
	definition: Dictionary,
) -> bool:
	return not executable_worker_ids(
		host,
		String(definition.get("occupationId", "")),
		String(definition.get("capability", "")),
	).is_empty()


static func paused_request_failure(
	host,
	kind: String,
	definition: Dictionary,
) -> Dictionary:
	if String(definition.get("unstaffedBehavior", "")) != "pause":
		return {}
	if service_has_executable_worker(host, definition):
		return {}
	return unstaffed_failure(
		kind,
		String(definition.get("serviceLabel", "这项")),
		String(definition.get("placeId", "")),
		String(definition.get("occupationId", "")),
		String(definition.get("capability", "")),
	)


static func unstaffed_failure(
	kind: String,
	service_label: String,
	place_id: String,
	occupation_id: String,
	capability: String,
) -> Dictionary:
	var normalized_label := service_label.strip_edges()
	if normalized_label.is_empty():
		normalized_label = "这项"
	var normalized_place := place_id.strip_edges()
	var location_text := (
		"%s的" % normalized_place
		if not normalized_place.is_empty()
		else ""
	)
	return {
		"ok": false,
		"errorCode": "OCCUPATION_SERVICE_UNSTAFFED",
		"retryable": false,
		"errors": [
			"%s%s服务当前没有可执行人员，已经暂停"
			% [location_text, normalized_label],
		],
		"serviceAvailability": {
			"state": "paused",
			"reason": "occupation_unstaffed",
			"kind": kind.strip_edges(),
			"serviceLabel": normalized_label,
			"placeId": normalized_place,
			"occupationId": occupation_id.strip_edges(),
			"capability": capability.strip_edges(),
		},
	}
