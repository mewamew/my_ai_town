class_name TownResidentArrivalRuntime
extends RefCounted


const PRODUCTION_TASK_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskCoordinationRuntime.gd"
)


const CHARACTER_MOVEMENT_QUERY := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")
const PLACE_SERVICE_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceCommandRuntime.gd"
)
const SOUTH_ENTRY_PLACE := "南入口"
const ENTRY_CONTINUITY_DURATION_MINUTES := 1
const ENTRY_CONTINUITY_LINES: Array[String] = [
	"刚到镇上，先慢慢往里走几步看看四周",
	"沿着入口往里走，先熟悉一下周围",
	"先离开入口，到前面看看镇上的早晨",
]

static var _arrival_safe_position_cache: Dictionary = {}
static var _arrival_home_route_cache: Dictionary = {}
static var _arrival_entry_state_cache: Dictionary = {}


static func clear_cache() -> void:
	_arrival_safe_position_cache.clear()
	_arrival_home_route_cache.clear()
	_arrival_entry_state_cache.clear()


static func advance(world, absolute_minute: int, clearance_px: float) -> void:
	var arrived_resident_ids: Array[String] = []
	for resident_id: String in world.resident_registry.order:
		var resident := world.resident_registry.records.get(resident_id, {}) as Dictionary
		var arrival := resident.get("arrivalState", {}) as Dictionary
		if (
			String(arrival.get("status", "arrived")) != "pending"
			or absolute_minute
				< int(arrival.get("scheduledAbsoluteMinute", 2_147_483_647))
		):
			continue
		var entry_state := entry_state_for(world, resident_id, clearance_px)
		if not entry_state.is_empty():
			resident["position"] = entry_state.get(
				"position",
				resident.get("position", Vector2.ZERO),
			)
			resident["spaceId"] = String(
				entry_state.get("spaceId", resident.get("spaceId", "")),
			)
			resident["regionId"] = String(
				entry_state.get("regionId", resident.get("regionId", "")),
			)
			resident["currentPlace"] = String(
				entry_state.get(
					"placeName",
					resident.get("currentPlace", ""),
				),
			)
		arrival["status"] = "arrived"
		arrival["arrivedAbsoluteMinute"] = absolute_minute
		resident["arrivalState"] = arrival
		activate_entry_continuity(world, resident_id, resident, absolute_minute)
		resident["movementRevision"] = int(
			resident.get("movementRevision", 1),
		) + 1
		arrived_resident_ids.append(resident_id)
		world.WORLD_LOG_COMMIT_RUNTIME.append_event(world,
			world.world_log_domain.journal.next_world_event_id(),
			"resident_lifecycle",
			resident_id,
			world.resident_display_name(resident_id),
			String(resident.get("currentPlace", "")),
			{
				"type": "居民抵达",
				"lifecycleId": "resident-arrival:%s" % resident_id,
				"status": "completed",
				"participantIds": [resident_id],
				"arrivedAbsoluteMinute": absolute_minute,
			},
		)
		world._emit_resident_state_changed(resident_id)
		world._schedule_decision(resident_id, false, false, false, false, true)
	if arrived_resident_ids.is_empty():
		return
	PLACE_SERVICE_COMMAND_RUNTIME.refresh_staffing(world)
	PRODUCTION_TASK_COORDINATION_RUNTIME.sync(world, absolute_minute)


static func activate_entry_continuity(
	world,
	resident_id: String,
	resident: Dictionary,
	absolute_minute: int,
) -> void:
	var action_id := "%s-arrival-%d" % [resident_id, absolute_minute]
	var line := ENTRY_CONTINUITY_LINES[
		posmod(hash(resident_id), ENTRY_CONTINUITY_LINES.size())
	]
	var action := {
		"action_id": action_id,
		"type": "待着",
		"line": line,
		"startedAbsoluteMinute": absolute_minute,
		"completeAbsoluteMinute": (
			absolute_minute + ENTRY_CONTINUITY_DURATION_MINUTES
		),
		"decisionBridge": true,
	}
	var home := String(
		(resident.get("socialState", {}) as Dictionary).get("home", ""),
	).strip_edges()
	if not home.is_empty():
		var entry_state := {
			"position": resident.get("position", Vector2.ZERO),
			"spaceId": resident.get("spaceId", ""),
			"regionId": resident.get("regionId", ""),
			"placeName": resident.get("currentPlace", ""),
		}
		# 入口落点预热阶段已经为可达性检查算过这条路线。抵达发生在
		# 分钟结算热路径里，直接复用完整路线，避免同一个居民在启动期
		# 和抵达帧各跑一次路网搜索。
		var route := _cached_home_route(resident, entry_state)
		if (
			(
				route.is_empty()
				and not _arrival_home_route_cache.has(
					_home_route_cache_key(resident, entry_state),
				)
			)
			or not (resident.get("routeConnector", []) as Array).is_empty()
		):
			route = ROUTE_QUERY.find_route_from_state(
				world.world_data(),
				entry_state,
				home,
				resident.get("routeConnector", []) as Array,
			) as Dictionary
		var step_path := _first_route_step_path(route)
		if step_path.size() >= 2:
			action["idlePathPoints"] = step_path
			action["idleTargetPosition"] = step_path[-1]
			action["idleMoveDurationMinutes"] = 1
	resident["currentAction"] = action
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = line


static func _first_route_step_path(route: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var samples := route.get("minutePositions", []) as Array
	if samples.size() < 2 or not samples[1] is Dictionary:
		return result
	for point_value: Variant in (samples[1] as Dictionary).get(
		"presentationPath",
		[],
	) as Array:
		if not point_value is Dictionary:
			return []
		var point := point_value as Dictionary
		result.append(Vector2(
			float(point.get("x", 0.0)),
			float(point.get("y", 0.0)),
		))
	return result


static func is_entry_continuity_action_id(
	resident_id: String,
	action_id: String,
) -> bool:
	return action_id.begins_with("%s-arrival-" % resident_id)


static func prewarm_pending_entry_states(world, clearance_px: float) -> void:
	var residents := world.residents() as Dictionary
	for resident_id: String in world.resident_order():
		var resident := residents.get(resident_id, {}) as Dictionary
		var arrival_state := resident.get("arrivalState", {}) as Dictionary
		if String(arrival_state.get("status", "")) != "pending":
			continue
		entry_state_for(world, resident_id, clearance_px)


static func entry_state_for(
	world,
	resident_id: String,
	clearance_px: float,
) -> Dictionary:
	var residents := world.residents() as Dictionary
	var resident := residents.get(resident_id, {}) as Dictionary
	var entry_cache_key := "%s|%.3f" % [resident_id, clearance_px]
	if _arrival_entry_state_cache.has(entry_cache_key):
		var cached_entry := _arrival_entry_state_cache[entry_cache_key] as Dictionary
		var cached_position := cached_entry.get("position", Vector2.INF) as Vector2
		var occupied_cached: Array[Vector2] = []
		for other_id: String in world.resident_order():
			if other_id == resident_id:
				continue
			var other := residents.get(other_id, {}) as Dictionary
			if (
				not world.resident_is_present(other)
				or String(other.get("spaceId", "")) != "town_outdoor"
			):
				continue
			var other_position := other.get("position", Vector2.INF) as Vector2
			if other_position.is_finite():
				occupied_cached.append(other_position)
		if (
			not cached_entry.is_empty()
			and cached_position.is_finite()
			and not world.ACTION_GEOMETRY.point_near_any(
				cached_position, occupied_cached, clearance_px,
			)
		):
			return cached_entry.duplicate(true)
		_arrival_entry_state_cache.erase(entry_cache_key)
	var preferred := resident.get("position", Vector2.ZERO) as Vector2
	var occupied: Array[Vector2] = []
	for other_id: String in world.resident_order():
		if other_id == resident_id:
			continue
		var other := residents.get(other_id, {}) as Dictionary
		if (
			not world.resident_is_present(other)
			or String(other.get("spaceId", "")) != "town_outdoor"
		):
			continue
		var position := other.get("position", Vector2.INF) as Vector2
		if position.is_finite():
			occupied.append(position)
	var candidate_offsets: Array[Vector2] = [Vector2.ZERO]
	var direction_offset := posmod(hash(resident_id), 16)
	for ring_radius in [64.0, 128.0, 192.0]:
		for direction_index in 16:
			var angle := TAU * float(
				posmod(direction_index + direction_offset, 16),
			) / 16.0
			candidate_offsets.append(
				Vector2(cos(angle), sin(angle)) * ring_radius,
			)
	var reach_cache := {}
	var candidate_checks := 0
	for offset in candidate_offsets:
		if candidate_checks >= 8:
			break
		candidate_checks += 1
		var requested_position := preferred + offset
		var cache_key := "town_outdoor|%.3f|%.3f" % [
			requested_position.x,
			requested_position.y,
		]
		var resolved: Dictionary
		if _arrival_safe_position_cache.has(cache_key):
			resolved = _arrival_safe_position_cache[cache_key] as Dictionary
		else:
			resolved = CHARACTER_MOVEMENT_QUERY.nearest_safe_position(
				world.world_data(),
				"town_outdoor",
				requested_position,
			) as Dictionary
			_arrival_safe_position_cache[cache_key] = resolved.duplicate(true)
		if (
			resolved.is_empty()
			or String(resolved.get("placeName", "")) != SOUTH_ENTRY_PLACE
		):
			continue
		var position := resolved.get("position", Vector2.INF) as Vector2
		if not position.is_finite():
			continue
		var reach_key := "%s|%s|%.3f|%.3f" % [
			String(resolved.get("spaceId", "")),
			String(resolved.get("regionId", "")),
			position.x,
			position.y,
		]
		if not reach_cache.has(reach_key):
			reach_cache[reach_key] = _can_reach_home(
				world,
				resident,
				resolved,
			)
		if (
			bool(reach_cache[reach_key])
			and not world.ACTION_GEOMETRY.point_near_any(position, occupied, clearance_px)
		):
			_arrival_entry_state_cache[entry_cache_key] = resolved.duplicate(true)
			return resolved
	var fallback := CHARACTER_MOVEMENT_QUERY.nearest_safe_position(
		world.world_data(),
		"town_outdoor",
		preferred,
	) as Dictionary
	_arrival_entry_state_cache[entry_cache_key] = fallback.duplicate(true)
	return fallback


static func _can_reach_home(
	world,
	resident: Dictionary,
	entry_state: Dictionary,
) -> bool:
	var home := String(
		(resident.get("socialState", {}) as Dictionary).get("home", ""),
	).strip_edges()
	if home.is_empty():
		return true
	var cache_key := _home_route_cache_key(resident, entry_state)
	if _arrival_home_route_cache.has(cache_key):
		var cached: Variant = _arrival_home_route_cache[cache_key]
		if cached is Dictionary:
			return bool((cached as Dictionary).get("reachable", false))
		return bool(cached)
	var route := ROUTE_QUERY.find_route_from_state(
		world.world_data(),
		{
			"position": entry_state.get("position", Vector2.ZERO),
			"spaceId": entry_state.get("spaceId", ""),
			"regionId": entry_state.get("regionId", ""),
			"currentPlace": entry_state.get("placeName", ""),
		},
		home,
	) as Dictionary
	var reachable := not route.is_empty()
	_arrival_home_route_cache[cache_key] = {
		"reachable": reachable,
		"route": route.duplicate(true),
	}
	return reachable


static func _home_route_cache_key(
	resident: Dictionary,
	entry_state: Dictionary,
) -> String:
	var position := entry_state.get("position", Vector2.ZERO) as Vector2
	return "%s|%s|%s|%.3f|%.3f" % [
		String((resident.get("socialState", {}) as Dictionary).get("home", "")),
		String(entry_state.get("spaceId", "")),
		String(entry_state.get("regionId", "")),
		position.x,
		position.y,
	]


static func _cached_home_route(
	resident: Dictionary,
	entry_state: Dictionary,
) -> Dictionary:
	var cache_key := _home_route_cache_key(resident, entry_state)
	if not _arrival_home_route_cache.has(cache_key):
		return {}
	var cached: Variant = _arrival_home_route_cache[cache_key]
	if not cached is Dictionary or not (cached as Dictionary).has("route"):
		return {}
	return ((cached as Dictionary).get("route", {}) as Dictionary).duplicate(true)
