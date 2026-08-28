class_name InteriorRoomBuildProfiler
extends RefCounted

var _enabled := false
var _target_usec := 0
var _max_frame_work_usec := 0
var _max_stage_usec := 0
var _completed_room_count := 0
var _failed_room_count := 0
var _active_rooms: Dictionary = {}
var _completed_rooms: Dictionary = {}


func configure(enabled: bool, target_usec: int) -> void:
	_enabled = enabled
	_target_usec = target_usec
	clear()


func is_enabled() -> bool:
	return _enabled


func clear() -> void:
	_max_frame_work_usec = 0
	_max_stage_usec = 0
	_completed_room_count = 0
	_failed_room_count = 0
	_active_rooms.clear()
	_completed_rooms.clear()


func start_room(interior_id: String) -> void:
	if not _enabled:
		return
	_active_rooms[interior_id] = {
		"requested_usec": Time.get_ticks_usec(),
		"cpu_usec": 0,
		"max_stage_usec": 0,
		"stage_count": 0,
		"stages": {},
		"stage_calls": {},
		"max_stage_work_items": 0,
	}


func record_step(
	interior_id: String,
	status: InteriorRoomPreparationTask.AdvanceStatus,
) -> void:
	if not _enabled or not _active_rooms.has(interior_id):
		return
	var room := _active_rooms[interior_id] as Dictionary
	var stage_usec := status.elapsed_usec
	var stage_name := status.stage_name
	room["cpu_usec"] = int(room["cpu_usec"]) + stage_usec
	room["max_stage_usec"] = maxi(int(room["max_stage_usec"]), stage_usec)
	room["stage_count"] = int(room["stage_count"]) + 1
	var stages := room["stages"] as Dictionary
	stages[stage_name] = maxi(int(stages.get(stage_name, 0)), stage_usec)
	var stage_calls := room["stage_calls"] as Dictionary
	stage_calls[stage_name] = int(stage_calls.get(stage_name, 0)) + 1
	room["max_stage_work_items"] = maxi(
		int(room["max_stage_work_items"]),
		status.work_items,
	)
	_max_stage_usec = maxi(_max_stage_usec, stage_usec)


func record_frame(frame_work_usec: int) -> void:
	if _enabled:
		_max_frame_work_usec = maxi(_max_frame_work_usec, frame_work_usec)


func finish_room(interior_id: String, failed: bool) -> Dictionary:
	if not _enabled or not _active_rooms.has(interior_id):
		return {}
	var room := _active_rooms[interior_id] as Dictionary
	_active_rooms.erase(interior_id)
	var profile := {
		"cpu_usec": int(room["cpu_usec"]),
		"wall_usec": Time.get_ticks_usec() - int(room["requested_usec"]),
		"max_stage_usec": int(room["max_stage_usec"]),
		"stage_count": int(room["stage_count"]),
		"stages": (room["stages"] as Dictionary).duplicate(),
		"stage_calls": (room["stage_calls"] as Dictionary).duplicate(),
		"max_stage_work_items": int(room["max_stage_work_items"]),
	}
	_completed_rooms[interior_id] = profile
	if failed:
		_failed_room_count += 1
	else:
		_completed_room_count += 1
	return profile


func snapshot() -> Dictionary:
	if not _enabled:
		return {
			"profiling_enabled": false,
			"frame_target_usec": _target_usec,
		}
	return {
		"profiling_enabled": true,
		"frame_target_usec": _target_usec,
		"max_frame_work_usec": _max_frame_work_usec,
		"max_stage_usec": _max_stage_usec,
		"completed_room_count": _completed_room_count,
		"failed_room_count": _failed_room_count,
		"rooms": _completed_rooms.duplicate(true),
	}
