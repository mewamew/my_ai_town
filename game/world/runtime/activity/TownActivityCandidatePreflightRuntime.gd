class_name TownActivityCandidatePreflightRuntime
extends RefCounted


const ACTIVITY_CANDIDATE_PREFLIGHT_POLICY := preload(
	"res://world/runtime/activity/TownActivityCandidatePreflightPolicy.gd"
)
const ACTIVITY_REGION_ACTION_PREPARER := preload(
	"res://world/runtime/activity/TownActivityRegionActionPreparer.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)


static func preflight(
	host,
	resident: Dictionary,
	validated: Dictionary,
) -> Dictionary:
	var candidates_to_try := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.ordered_candidates(
		validated,
	)
	if candidates_to_try.is_empty():
		return ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.reservation_conflict(
			candidates_to_try,
		)
	# 活动列表生成唤醒包时已经为“可做”候选跑过一次正式寻路。同一游戏
	# 分钟、同一居民位置下，优先复用那条已经验证过的路线，避免模型结果
	# 返回时再次扫描整张路网。预约可用性和区域占用仍以本次 validated 为准。
	var absolute_minute := int(host._environment.get_absolute_minute())
	candidates_to_try = ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.prioritize_cached(
		candidates_to_try,
		host.activity_reachability_state,
		absolute_minute,
		resident,
	)
	var reservation_conflict := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.reservation_conflict(
		candidates_to_try,
	)
	if not reservation_conflict.is_empty():
		return reservation_conflict
	var target_unreachable := false
	for candidate_value: Variant in candidates_to_try:
		var candidate := candidate_value as Dictionary
		if not bool(candidate.get("memberAvailable", false)):
			continue
		if (
			String(candidate.get("targetType", "")) == "region"
			and ACTION_SUPPORT.region_activity_position_occupied(
				host,
				String(validated.get("residentId", "")),
				candidate.get("memberPosition", []) as Array,
			)
		):
			continue
		var action := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.candidate_action(
			validated,
			candidate,
		)
		var cached_action: Dictionary = host.activity_reachability_state.cached_prepared_action(
			absolute_minute,
			resident,
			candidate,
		)
		var prepared := {}
		if cached_action.is_empty():
			prepared = (
				ACTIVITY_REGION_ACTION_PREPARER.prepare(
					host.world_definition.world_data,
					absolute_minute,
					resident,
					action,
					candidate,
				)
				if String(candidate.get("targetType", "")) == "region"
				else host.PROP_ACTION_PREPARER.prepare_for_host(host, resident, action)
			)
		else:
			prepared = ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.prepared_from_cache(
				cached_action,
				action,
			)
		if prepared.get("ok") != true:
			target_unreachable = true
			continue
		var prepared_action := prepared.get("action", {}) as Dictionary
		var result := ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.candidate_result(
			candidate,
			prepared_action,
			host.PROP_ACTION_PREPARER.is_layout_override_action(host, resident, action),
		)
		if not result.is_empty():
			return result
	return ACTIVITY_CANDIDATE_PREFLIGHT_POLICY.target_failure(target_unreachable)


static func candidate_reachable(
	host,
	resident: Dictionary,
	candidate: Dictionary,
	activity_label: String,
	reachability_memo: Dictionary = {},
) -> bool:
	var cached: Variant = host.activity_reachability_state.cached_reachability(
		int(host._environment.get_absolute_minute()),
		resident,
		candidate,
		reachability_memo,
	)
	if cached != null:
		return bool(cached)
	var action := {
		"action_id": "activity-query-preflight",
		"type": "用道具",
		"prop": String(candidate.get("targetPropName", "")),
		"verb": String(candidate.get("targetActionVerb", "")),
		"line": activity_label,
	}
	var route_probe_started_usec := Time.get_ticks_usec() if host.telemetry.frame_probe != null else 0
	var prepared := (
		ACTIVITY_REGION_ACTION_PREPARER.prepare(
			host.world_definition.world_data,
			int(host._environment.get_absolute_minute()),
			resident,
			action,
			candidate,
		)
		if String(candidate.get("targetType", "")) == "region"
		else host.PROP_ACTION_PREPARER.prepare_for_host(host, resident, action)
	) as Dictionary
	if host.telemetry.frame_probe != null:
		host.AGENT_DECISION_DISPATCH_RUNTIME.probe_lap(host, "agentActivityQueryRouteUsec", route_probe_started_usec)
		host.telemetry.frame_probe.record(
			Engine.get_process_frames(),
			"agentActivityQueryRouteCount",
			1,
		)
	if prepared.get("ok") != true:
		host.activity_reachability_state.remember_reachability(
			resident,
			candidate,
			reachability_memo,
			false,
		)
		return false
	var prepared_action := prepared.get("action", {}) as Dictionary
	var member_position := candidate.get("memberPosition", []) as Array
	var expected := Vector2(float(member_position[0]), float(member_position[1]))
	var reachable: bool = (
		prepared_action.get("targetPosition", Vector2.ZERO) as Vector2
	).is_equal_approx(expected) or host.PROP_ACTION_PREPARER.is_layout_override_action(host,
		resident,
		{
			"prop": String(candidate.get("targetPropName", "")),
			"verb": String(candidate.get("targetActionVerb", "")),
		},
	)
	host.activity_reachability_state.remember_reachability(
		resident,
		candidate,
		reachability_memo,
		reachable,
		prepared_action,
	)
	return reachable
