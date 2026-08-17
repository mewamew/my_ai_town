class_name TownSocialCoordinationState
extends RefCounted


var _public_activity_cache: Dictionary = {}
var _public_activity_cache_revision := -1
var _staffing_sync_signature: Array = []
var _staffing_last_sync_minute := -1
var _staffing_full_sync_count := 0


func reset() -> void:
	_public_activity_cache.clear()
	_public_activity_cache_revision = -1
	_staffing_sync_signature.clear()
	_staffing_last_sync_minute = -1
	_staffing_full_sync_count = 0


func has_public_activity_cache(world_revision: int) -> bool:
	return _public_activity_cache_revision == world_revision


func public_activity_cache_snapshot() -> Dictionary:
	return _public_activity_cache.duplicate(true)


func store_public_activity_cache(
	projection: Dictionary,
	world_revision: int,
) -> Dictionary:
	_public_activity_cache = projection.duplicate(true)
	_public_activity_cache_revision = world_revision
	return _public_activity_cache.duplicate(true)


func staffing_sync_is_fresh(
	signature: Array,
	absolute_minute: int,
	refresh_interval_minutes: int,
) -> bool:
	return (
		signature == _staffing_sync_signature
		and _staffing_last_sync_minute >= 0
		and absolute_minute - _staffing_last_sync_minute < refresh_interval_minutes
	)


func record_staffing_sync(signature: Array, absolute_minute: int) -> void:
	_staffing_full_sync_count += 1
	_staffing_sync_signature = signature.duplicate(true)
	_staffing_last_sync_minute = absolute_minute
