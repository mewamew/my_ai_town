class_name TownActivityReachabilityCache
extends RefCounted


var _reachability_by_candidate: Dictionary = {}
var _prepared_action_by_candidate: Dictionary = {}
var _absolute_minute := -1


func clear() -> void:
	_reachability_by_candidate.clear()
	_prepared_action_by_candidate.clear()
	_absolute_minute = -1


func ensure_minute(absolute_minute: int) -> void:
	if absolute_minute == _absolute_minute:
		return
	_reachability_by_candidate.clear()
	_prepared_action_by_candidate.clear()
	_absolute_minute = absolute_minute


func has_reachability(
	absolute_minute: int,
	resident: Dictionary,
	candidate: Dictionary,
) -> bool:
	ensure_minute(absolute_minute)
	return _reachability_by_candidate.has(
		candidate_cache_key(resident, candidate),
	)


func cached_prepared_action(
	absolute_minute: int,
	resident: Dictionary,
	candidate: Dictionary,
) -> Dictionary:
	if absolute_minute != _absolute_minute:
		return {}
	var cached := _prepared_action_by_candidate.get(
		candidate_cache_key(resident, candidate),
		{},
	) as Dictionary
	return cached.duplicate(true)


func cached_reachability(
	absolute_minute: int,
	resident: Dictionary,
	candidate: Dictionary,
	reachability_memo: Dictionary,
) -> Variant:
	var member_position := candidate.get("memberPosition", []) as Array
	if member_position.size() != 2:
		return false
	var memo_key := candidate_memo_key(candidate)
	if reachability_memo.has(memo_key):
		return bool(reachability_memo[memo_key])
	ensure_minute(absolute_minute)
	var cache_key := candidate_cache_key(resident, candidate)
	if _reachability_by_candidate.has(cache_key):
		return bool(_reachability_by_candidate[cache_key])
	return null


func remember_reachability(
	resident: Dictionary,
	candidate: Dictionary,
	reachability_memo: Dictionary,
	reachable: bool,
	prepared_action: Dictionary = {},
) -> void:
	var memo_key := candidate_memo_key(candidate)
	var cache_key := candidate_cache_key(resident, candidate)
	reachability_memo[memo_key] = reachable
	_reachability_by_candidate[cache_key] = reachable
	if reachable:
		_prepared_action_by_candidate[cache_key] = prepared_action.duplicate(true)


func candidate_memo_key(candidate: Dictionary) -> String:
	var member_position := candidate.get("memberPosition", []) as Array
	return "%s|%s|%s|%s|%s,%s" % [
		String(candidate.get("targetType", "")),
		String(candidate.get("targetRegionId", "")),
		String(candidate.get("targetPropName", "")),
		String(candidate.get("targetActionVerb", "")),
		str(member_position[0]) if member_position.size() == 2 else "",
		str(member_position[1]) if member_position.size() == 2 else "",
	]


func candidate_cache_key(
	resident: Dictionary,
	candidate: Dictionary,
) -> String:
	var origin := resident.get("position", Vector2.ZERO) as Vector2
	return "%s|%s|%s|%d,%d|%s|%s" % [
		String(resident.get("residentId", "")),
		String(resident.get("spaceId", "")),
		String(resident.get("currentPlace", "")),
		int(round(origin.x)),
		int(round(origin.y)),
		str(resident.get("routeConnector", []) as Array),
		candidate_memo_key(candidate),
	]


func reachability_count() -> int:
	return _reachability_by_candidate.size()


func prepared_action_count() -> int:
	return _prepared_action_by_candidate.size()


func cached_minute() -> int:
	return _absolute_minute
