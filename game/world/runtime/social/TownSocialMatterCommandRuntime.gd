class_name TownSocialMatterCommandRuntime
extends RefCounted


static func record_awareness(
	host,
	matter_id: String,
	resident_ref: String,
	acquired_via: String,
	source_id: String,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return host._command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var result := host._social_matters.record_awareness(
		matter_id,
		resident_id,
		"known",
		acquired_via,
		source_id,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	return finalize_mutation(host, result, matter_id)


static func submit_response(
	host,
	resident_ref: String,
	response: Dictionary,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return host._command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var result := host._social_agent_adapter.submit_social_response(
		resident_id,
		response,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	var matter_id := String(response.get("matter_id", ""))
	if result.get("ok") == true:
		host.SOCIAL_RESPONSE_ROUND_RUNTIME.settle_if_ready(host, matter_id)
	return finalize_mutation(host, result, matter_id)


static func mark_candidate_terminal(
	host,
	matter_id: String,
	resident_ref: String,
	reason: String,
	expected_response_round_id: String = "",
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return host._command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var result := host._social_matters.mark_candidate_terminal(
		matter_id,
		resident_id,
		reason,
		expected_response_round_id,
	) as Dictionary
	if result.get("ok") == true:
		host.SOCIAL_RESPONSE_ROUND_RUNTIME.settle_if_ready(host, matter_id)
	return finalize_mutation(host, result, matter_id)


static func summaries(host, include_closed := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in host._social_matters.list_matters(include_closed) as Array:
		var matter := value as Dictionary
		result.append(host._social_matters.public_summary(
			String(matter.get("matter_id", "")),
		) as Dictionary)
	return result


static func agent_matters(host, resident_ref: String) -> Array[Dictionary]:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	return host._social_agent_adapter.build_social_matters(
		resident_id,
	) as Array[Dictionary]


static func agent_exposures(host, resident_ref: String) -> Array[Dictionary]:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	var exposures := host._social_matters.exposures_for(
		resident_id,
		int(host._environment.get_absolute_minute()),
	) as Array[Dictionary]
	return exposures.slice(0, mini(1, exposures.size()))


static func take_response_results(
	host,
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	return host._social_agent_adapter.take_social_response_results(
		resident_id,
	) as Array[Dictionary]


static func close_resident_request_source(
	host,
	source_id: String,
	result_id: String,
) -> void:
	var now := int(host._environment.get_absolute_minute())
	for value: Variant in host._social_matters.list_matters(false) as Array:
		var matter := value as Dictionary
		var source_ref := matter.get("source_state_ref", {}) as Dictionary
		if (
			String(source_ref.get("source_kind", "")) != "resident_request"
			or String(source_ref.get("source_id", "")) != source_id
		):
			continue
		var closed := host._social_matters.update_source_state(
			String(matter.get("matter_id", "")),
			int(source_ref.get("source_revision", 1)) + 1,
			false,
			now,
			[{"result_id": result_id}],
		) as Dictionary
		if closed.get("ok") == true:
			finalize_mutation(
				host,
				closed,
				String(matter.get("matter_id", "")),
			)
		return


static func advance(host, absolute_minute: int) -> void:
	host._social_matters.expire_exposures(absolute_minute)
	var actionable_resident_ids := (
		host._social_matters.actionable_exposure_resident_ids(
			host.resident_registry.order,
			absolute_minute,
		) as Array[String]
	)
	for resident_id: String in actionable_resident_ids:
		host._schedule_decision(resident_id, false)
	for matter_id: String in host._social_matters.timeout_due_response_rounds(
		absolute_minute,
	) as Array[String]:
		var settled := host._social_matters.settle_response_round(
			matter_id,
			absolute_minute,
			"reopen",
		) as Dictionary
		if settled.get("ok") == true:
			host.SOCIAL_ASSIGNMENT_RECONCILIATION_RUNTIME.reconcile(host, matter_id)
			host.SOCIAL_RESPONSE_ROUND_RUNTIME.maybe_begin_after_exposures(host, matter_id)
			emit_summary(host, matter_id)
	var closed := host._social_matters.expire_due(
		absolute_minute,
	) as Array[Dictionary]
	for matter: Dictionary in closed:
		emit_summary(host, String(matter.get("matter_id", "")))
	if host._animal_fact_runtime.expire_public_attention(absolute_minute):
		host._bump_world_revision(false)
	if not closed.is_empty():
		schedule_receipt_wakes(host)


static func finalize_mutation(
	host,
	result: Dictionary,
	matter_id := "",
) -> Dictionary:
	if result.get("ok") != true:
		return command_result(host, result)
	host._bump_world_revision(false)
	emit_summary(host, matter_id)
	schedule_receipt_wakes(host)
	host._notify_world_revision()
	var value: Variant = result.get("value")
	var extra := {}
	if value is Dictionary:
		extra = (value as Dictionary).duplicate(true)
	else:
		extra["value"] = value
	extra["ok"] = true
	return host._decorate_command_result(extra)


static func command_result(
	host,
	result: Dictionary,
	fallback_error_code := "SOCIAL_COMMAND_REJECTED",
) -> Dictionary:
	var reason := String(
		result.get("reason", "社会事项操作未被 World 接受")
	).strip_edges()
	if reason.is_empty():
		reason = "社会事项操作未被 World 接受"
	var error_code := String(result.get("error_code", "")).strip_edges()
	if error_code.is_empty():
		error_code = fallback_error_code
	return host._command_failure(error_code, [reason])


static func emit_summary(host, matter_id: String) -> void:
	var normalized := matter_id.strip_edges()
	if normalized.is_empty():
		return
	var summary := host._social_matters.public_summary(normalized) as Dictionary
	if summary.is_empty():
		return
	var matter := host._social_matters.get_matter(normalized) as Dictionary
	var creator_id := String(matter.get("creator_id", "")).strip_edges()
	host.WORLD_LOG_COMMIT_RUNTIME.append_domain(
		host,
		host.DOMAIN_LOG_PROJECTION.social_matter_event(
			matter,
			host.resident_display_name(creator_id),
		),
	)
	host.social_matter_changed.emit(summary)


static func schedule_receipt_wakes(host) -> void:
	for resident_id in host.resident_registry.order:
		if (host._social_matters.peek_receipts(resident_id) as Array).is_empty():
			continue
		host._schedule_decision(resident_id, false)
