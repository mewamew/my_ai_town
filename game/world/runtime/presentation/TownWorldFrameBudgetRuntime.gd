class_name TownWorldFrameBudgetRuntime
extends RefCounted


const RESIDENT_PRESENTATION_REFRESH_BUDGET_PER_ADVANCE := 3
const RESIDENT_PLACE_CHANGE_SIGNAL_BUDGET_PER_ADVANCE := 1
const PERCEPTION_MAX_DEFERRED_ADVANCES := 12

var _resident_state_refreshes: Array[String] = []
var _resident_state_refresh_keys: Dictionary = {}
var _resident_place_change_signals: Array[Dictionary] = []
var _perception_refresh_deferred := false
var _perception_deferred_advance_count := 0


static func should_defer_agent_dispatch(world_advance: Dictionary) -> bool:
	return (
		int(world_advance.get("minutesAdvanced", 0)) > 0
		or int(
			world_advance.get("deferredPresentationRefreshesProcessed", 0)
		) > 0
		or int(
			world_advance.get("deferredPlaceChangeSignalsProcessed", 0)
		) > 0
		or bool(world_advance.get("deferredPerceptionProcessed", false))
	)


func reset() -> void:
	_resident_state_refreshes.clear()
	_resident_state_refresh_keys.clear()
	_resident_place_change_signals.clear()
	_perception_refresh_deferred = false
	_perception_deferred_advance_count = 0


func defer_perception_refresh() -> void:
	if not _perception_refresh_deferred:
		_perception_deferred_advance_count = 0
	_perception_refresh_deferred = true


func queue_resident_state_refresh(resident_id: String) -> void:
	if _resident_state_refresh_keys.has(resident_id):
		return
	_resident_state_refresh_keys[resident_id] = true
	_resident_state_refreshes.append(resident_id)


func queue_resident_place_change_signal(
	resident_id: String,
	place_change: Dictionary,
	world_revision: int,
) -> void:
	# 地点事件已经逐条写入公开日志；这里排的是表现通知。低帧率或 3 倍速下，
	# 同一居民再次跨区时合并到最新终点，队列长度因此最多等于居民数。
	for queued_value: Variant in _resident_place_change_signals:
		var queued := queued_value as Dictionary
		if String(queued.get("residentId", "")) != resident_id:
			continue
		var queued_change := queued.get("change", {}) as Dictionary
		queued_change["to"] = place_change.get("to", queued_change.get("to", ""))
		queued_change["time"] = place_change.get(
			"time",
			queued_change.get("time", {}),
		)
		queued_change["worldRevision"] = place_change.get(
			"worldRevision",
			queued_change.get("worldRevision", world_revision),
		)
		return
	_resident_place_change_signals.append({
		"residentId": resident_id,
		"change": place_change,
	})


func process_deferred_work(
	world,
	advance_profile: Dictionary,
	traveler_relationship_state: TownTravelerRelationshipState,
) -> Dictionary:
	var result := {
		"presentationProcessed": 0,
		"placeProcessed": 0,
		"perceptionProcessed": false,
	}
	if _perception_refresh_deferred:
		_perception_deferred_advance_count += 1
	if (
		_perception_refresh_deferred
		and _perception_deferred_advance_count
		>= PERCEPTION_MAX_DEFERRED_ADVANCES
	):
		_refresh_perception(world, advance_profile, traveler_relationship_state)
		result["perceptionProcessed"] = true
	elif not _resident_place_change_signals.is_empty():
		var lap_usec := Time.get_ticks_usec() if world.telemetry.advance_profile_enabled else 0
		result["placeProcessed"] = _drain_place_change_signals(world)
		world.telemetry.lap(
			advance_profile,
			"deferredPlaceChangeSignalUsec",
			lap_usec,
		)
		if (
			_resident_place_change_signals.is_empty()
			and _resident_state_refreshes.is_empty()
		):
			defer_perception_refresh()
	elif not _resident_state_refreshes.is_empty():
		var lap_usec := Time.get_ticks_usec() if world.telemetry.advance_profile_enabled else 0
		result["presentationProcessed"] = _drain_state_refreshes(world)
		world.telemetry.lap(
			advance_profile,
			"deferredPresentationRefreshUsec",
			lap_usec,
		)
		if _resident_state_refreshes.is_empty():
			defer_perception_refresh()
	elif _perception_refresh_deferred:
		_refresh_perception(world, advance_profile, traveler_relationship_state)
		result["perceptionProcessed"] = true
	return result


func refresh_or_defer_perception(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
) -> void:
	if (
		_resident_place_change_signals.is_empty()
		and _resident_state_refreshes.is_empty()
	):
		world.PERCEPTION_RUNTIME._refresh_perception(
			world,
			true,
			traveler_relationship_state,
		)
	else:
		defer_perception_refresh()


func _drain_state_refreshes(world) -> int:
	var resident_ids: Array[String] = []
	while (
		not _resident_state_refreshes.is_empty()
		and resident_ids.size()
		< RESIDENT_PRESENTATION_REFRESH_BUDGET_PER_ADVANCE
	):
		var resident_id: String = _resident_state_refreshes.pop_front()
		_resident_state_refresh_keys.erase(resident_id)
		if not world.resident_registry.records.has(resident_id):
			continue
		resident_ids.append(resident_id)
	if resident_ids.is_empty():
		return 0
	world._bump_world_revision(false)
	for resident_id: String in resident_ids:
		world._emit_resident_state_changed(resident_id)
	world._notify_world_revision()
	return resident_ids.size()


func _drain_place_change_signals(world) -> int:
	var signals: Array[Dictionary] = []
	while (
		not _resident_place_change_signals.is_empty()
		and signals.size()
		< RESIDENT_PLACE_CHANGE_SIGNAL_BUDGET_PER_ADVANCE
	):
		var deferred_signal := (
			_resident_place_change_signals.pop_front()
			as Dictionary
		)
		if not world.resident_registry.records.has(
			String(deferred_signal.get("residentId", "")),
		):
			continue
		signals.append(deferred_signal)
	if signals.is_empty():
		return 0
	world._bump_world_revision(false)
	for deferred_signal: Dictionary in signals:
		var resident_id := String(deferred_signal.get("residentId", ""))
		var place_change := deferred_signal.get("change", {}) as Dictionary
		place_change["state"] = world.get_resident_state(resident_id)
		place_change["worldRevision"] = world._world_revision
		world.resident_place_changed.emit(
			world.resident_display_name(resident_id),
			place_change,
		)
	world._notify_world_revision()
	return signals.size()


func _refresh_perception(
	world,
	advance_profile: Dictionary,
	traveler_relationship_state: TownTravelerRelationshipState,
) -> void:
	var lap_usec := Time.get_ticks_usec() if world.telemetry.advance_profile_enabled else 0
	_perception_refresh_deferred = false
	_perception_deferred_advance_count = 0
	world._bump_world_revision(false)
	world.PERCEPTION_RUNTIME._refresh_perception(
		world,
		true,
		traveler_relationship_state,
	)
	world._notify_world_revision()
	world.telemetry.lap(
		advance_profile,
		"perceptionUsec",
		lap_usec,
	)


func presentation_refresh_count() -> int:
	return _resident_state_refreshes.size()


func place_change_signal_count() -> int:
	return _resident_place_change_signals.size()


func clear_presentation_refreshes() -> void:
	_resident_state_refreshes.clear()
	_resident_state_refresh_keys.clear()


func perception_is_deferred() -> bool:
	return _perception_refresh_deferred


func perception_deferred_advance_count() -> int:
	return _perception_deferred_advance_count
