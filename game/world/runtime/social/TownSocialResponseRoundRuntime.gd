class_name TownSocialResponseRoundRuntime
extends RefCounted


const SOCIAL_JUDGMENTS := preload(
	"res://world/runtime/social/TownSocialJudgments.gd"
)
const INITIAL_SOCIAL_CONTACT_POLICY := preload(
	"res://world/runtime/social/TownInitialSocialContactPolicy.gd"
)

const MAX_SOCIAL_RESPONSE_CANDIDATES := 4
const MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT := 1


static func begin(
	host,
	matter_id: String,
	candidates: Array,
	response_window_minutes: int,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if response_window_minutes <= 0:
		return host._command_failure(
			"SOCIAL_RESPONSE_ROUND_INVALID",
			["回应窗口必须大于零分钟"],
		)
	if candidates.size() > MAX_SOCIAL_RESPONSE_CANDIDATES:
		return host._command_failure(
			"SOCIAL_RESPONSE_CANDIDATE_LIMIT",
			["一轮最多选择 %d 名回应候选" % MAX_SOCIAL_RESPONSE_CANDIDATES],
		)
	var now := int(host._environment.get_absolute_minute())
	var normalized_candidates: Array[Dictionary] = []
	for value: Variant in candidates:
		if typeof(value) != TYPE_DICTIONARY:
			return host._command_failure(
				"SOCIAL_RESPONSE_CANDIDATE_INVALID",
				["回应候选必须是对象"],
			)
		var candidate := (value as Dictionary).duplicate(true)
		var resident_id: String = host._resident_key(
			String(candidate.get("resident_id", ""))
		)
		if resident_id.is_empty():
			return host._command_failure(
				"WORLD_RESIDENT_UNKNOWN",
				["回应候选不是当前居民"],
			)
		var active_load: int = host.SOCIAL_GOAL_MATCHING_RUNTIME.active_commitment_count(host, resident_id)
		if active_load >= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT:
			return host._command_failure(
				"SOCIAL_COMMITMENT_LIMIT",
				["居民已有正在履行的社会承诺"],
			)
		candidate["resident_id"] = resident_id
		candidate["load"] = active_load
		candidate["available_at"] = host.SOCIAL_GOAL_MATCHING_RUNTIME.resident_available_at(host,
			resident_id,
			now,
		)
		normalized_candidates.append(candidate)
	var result := host._social_matters.begin_response_round(
		matter_id,
		normalized_candidates,
		now,
		now + response_window_minutes,
	) as Dictionary
	if result.get("ok") == true:
		for candidate: Dictionary in normalized_candidates:
			host._schedule_decision(
				String(candidate.get("resident_id", "")),
				true,
			)
	return host.SOCIAL_MATTER_COMMAND_RUNTIME.finalize_mutation(host, result, matter_id)


static func begin_for_residents(
	host,
	matter_id: String,
	resident_refs: Array,
	response_window_minutes: int,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if resident_refs.is_empty():
		return host._command_failure(
			"SOCIAL_RESPONSE_CANDIDATE_INVALID",
			["回应候选不能为空"],
		)
	var now := int(host._environment.get_absolute_minute())
	var candidates: Array[Dictionary] = []
	var seen := {}
	for resident_value: Variant in resident_refs:
		var resident_id: String = host._resident_key(String(resident_value))
		if resident_id.is_empty():
			return host._command_failure(
				"WORLD_RESIDENT_UNKNOWN",
				["回应候选不是当前居民"],
			)
		if seen.has(resident_id):
			continue
		seen[resident_id] = true
		var load: int = host.SOCIAL_GOAL_MATCHING_RUNTIME.active_commitment_count(host, resident_id)
		if load >= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT:
			continue
		var candidate := host._social_sources.response_candidate(
			resident_id,
			0,
			load,
			host.SOCIAL_GOAL_MATCHING_RUNTIME.resident_available_at(host, resident_id, now),
			matter_id,
		) as Dictionary
		if not candidate.is_empty():
			candidates.append(candidate)
		if candidates.size() >= MAX_SOCIAL_RESPONSE_CANDIDATES:
			break
	if candidates.is_empty():
		return host._command_failure(
			"SOCIAL_RESPONSE_CANDIDATE_UNAVAILABLE",
			["当前没有能够进入本轮的知情居民"],
		)
	return begin(host, matter_id, candidates, response_window_minutes)


static func submit_optional_response(
	host,
	resident_id: String,
	response_value: Variant,
) -> void:
	if not response_value is Dictionary:
		return
	var response := response_value as Dictionary
	var matter_id := (
		String(response.get("matter_id", "")).strip_edges()
		if response.get("matter_id") is String
		else ""
	)
	var result := host._social_agent_adapter.submit_social_response(
		resident_id,
		response,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	var value := result.get("value", {}) as Dictionary
	var status := String(value.get("status", ""))
	if result.get("ok") == true and status in ["pending", "recorded"]:
		var assignment_outcome := String(value.get("assignment_outcome", ""))
		if assignment_outcome == "withdrawn":
			var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
			var current_action := resident.get("currentAction", {}) as Dictionary
			var action_goal := value.get("action_goal", {}) as Dictionary
			var execution := host._activity_runtime.execution_for_action(
				resident_id,
				String(current_action.get("action_id", "")),
			) as Dictionary
			if (
				host.SOCIAL_GOAL_MATCHING_RUNTIME.goal_matches_action(host,
					action_goal,
					current_action,
					resident_id,
				)
				or (
					not execution.is_empty()
					and host.SOCIAL_GOAL_MATCHING_RUNTIME.goal_matches_activity(action_goal, execution)
				)
			):
				host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "居民已经退出这项承诺")
			maybe_begin_after_exposures(host, matter_id)
		settle_if_ready(host, matter_id)
		host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(host, matter_id)
		return
	if not matter_id.is_empty():
		var terminal := host._social_matters.mark_candidate_terminal(
			matter_id,
			resident_id,
			"request_cancelled",
		) as Dictionary
		if terminal.get("ok") == true:
			settle_if_ready(host, matter_id)
			host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(host, matter_id)


static func settle_optional_attention(
	host,
	resident_id: String,
	attention: Dictionary,
	offered_exposures: Array,
) -> void:
	if offered_exposures.is_empty():
		return
	var exposure := offered_exposures[0] as Dictionary
	var matter_id := String(exposure.get("matter_id", ""))
	var option_id := "ignore"
	if (
		String(attention.get("exposure_id", ""))
		== String(exposure.get("exposure_id", ""))
		and String(attention.get("matter_id", "")) == matter_id
		and int(attention.get("matter_revision", -1))
		== int(exposure.get("matter_revision", -2))
		and String(attention.get("option_id", "")) in [
			"notice",
			"ignore",
			"defer",
		]
	):
		option_id = String(attention.get("option_id", ""))
	var resolved := host._social_matters.resolve_exposure(
		matter_id,
		resident_id,
		{
			"exposure_id": String(exposure.get("exposure_id", "")),
			"option_id": option_id,
		},
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if resolved.get("ok") != true:
		return
	host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(host, matter_id)
	maybe_begin_after_exposures(host, matter_id)


static func maybe_begin_after_exposures(host, matter_id: String) -> void:
	var matter := host._social_matters.get_matter(matter_id) as Dictionary
	if matter.is_empty() or String(matter.get("state", "")) != "open":
		return
	var now := int(host._environment.get_absolute_minute())
	var candidates: Array[Dictionary] = []
	var involvement := matter.get("involvement", {}) as Dictionary
	var aware_resident_ids: Array[String] = []
	for resident_value: Variant in (matter.get("awareness", {}) as Dictionary):
		aware_resident_ids.append(String(resident_value))
	aware_resident_ids.sort()
	for resident_id: String in aware_resident_ids:
		# 玩家可以是事项的知情者或受影响者，但不是由 Agent 调度的居民。
		if not host.resident_registry.records.has(resident_id):
			continue
		var role := String(
			(involvement.get(resident_id, {}) as Dictionary).get("role", "")
		)
		if (
			role == "creator"
			or SOCIAL_JUDGMENTS.social_resident_already_considered(
				matter,
				resident_id,
			)
		):
			continue
		var load: int = host.SOCIAL_GOAL_MATCHING_RUNTIME.active_commitment_count(host, resident_id)
		if load >= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT:
			continue
		var candidate := host._social_sources.response_candidate(
			resident_id,
			0,
			load,
			host.SOCIAL_GOAL_MATCHING_RUNTIME.resident_available_at(host, resident_id, now),
			matter_id,
		) as Dictionary
		if not candidate.is_empty():
			candidates.append(candidate)
		if candidates.size() >= MAX_SOCIAL_RESPONSE_CANDIDATES:
			break
	if candidates.is_empty():
		return
	var started := host._social_matters.begin_response_round(
		matter_id,
		candidates,
		now,
		mini(now + 30, int(matter.get("expires_at", now + 30))),
	) as Dictionary
	if started.get("ok") != true:
		return
	for candidate: Dictionary in candidates:
		host._schedule_decision(
			String(candidate.get("resident_id", "")),
			true,
		)
	host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(host, matter_id)


static func begin_initial(
	host,
	method: String,
	source_state: Dictionary,
	matter_id: String,
) -> void:
	if method not in ["sync_resident_request", "sync_job_vacancy"]:
		return
	var matter := host._social_matters.get_matter(matter_id) as Dictionary
	if String(matter.get("state", "")) != "open":
		return
	var now := int(host._environment.get_absolute_minute())
	var candidates: Array[Dictionary] = []
	for resident_id: String in INITIAL_SOCIAL_CONTACT_POLICY.source_resident_ids(
		method,
		source_state,
		false,
		host.resident_registry.order,
		host.resident_registry.records,
		host.resident_registry.id_by_name,
	):
		var load: int = host.SOCIAL_GOAL_MATCHING_RUNTIME.active_commitment_count(host, resident_id)
		if load >= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT:
			continue
		var candidate: Dictionary
		if method == "sync_job_vacancy":
			var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
			var from_occupation_id: String = host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.primary_id(host, resident)
			candidate = host._social_sources.job_vacancy_response_candidate(
				resident_id,
				host._work.staffing_candidate_ability_score(
					resident_id,
					from_occupation_id,
				),
				load,
				host.SOCIAL_GOAL_MATCHING_RUNTIME.resident_available_at(host, resident_id, now),
				matter_id,
				host._work.staffing.allowed_assignment_modes(
					resident_id,
					String(source_state.get("occupation_id", "")),
				) as Array,
				from_occupation_id,
			) as Dictionary
		else:
			candidate = host._social_sources.response_candidate(
				resident_id,
				0,
				load,
				host.SOCIAL_GOAL_MATCHING_RUNTIME.resident_available_at(host, resident_id, now),
				matter_id,
			) as Dictionary
		if not candidate.is_empty():
			candidates.append(candidate)
		if candidates.size() >= MAX_SOCIAL_RESPONSE_CANDIDATES:
			break
	if candidates.is_empty():
		return
	var started := host._social_matters.begin_response_round(
		matter_id,
		candidates,
		now,
		now + 30,
	) as Dictionary
	if started.get("ok") != true:
		return
	for candidate: Dictionary in candidates:
		host._schedule_decision(
			String(candidate.get("resident_id", "")),
			true,
		)


static func settle_if_ready(host, matter_id: String) -> void:
	var normalized := matter_id.strip_edges()
	if (
		normalized.is_empty()
		or not bool(host._social_matters.is_response_round_ready(normalized))
	):
		return
	var settled := host._social_matters.settle_response_round(
		normalized,
		int(host._environment.get_absolute_minute()),
		"reopen",
	) as Dictionary
	if settled.get("ok") == true:
		host.SOCIAL_ASSIGNMENT_RECONCILIATION_RUNTIME.reconcile(host, normalized)
		maybe_begin_after_exposures(host, normalized)
