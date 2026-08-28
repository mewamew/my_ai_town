class_name InteriorRoomBuildQueue
extends Node

signal room_prepared(interior_id: String, room: InteriorRoom, profile: Dictionary)
signal room_failed(interior_id: String, error: String, profile: Dictionary)

const FRAME_TARGET_USEC := 8000
const MIN_STEP_REMAINING_USEC := InteriorRoom.PREPARATION_WORK_ITEM_TARGET_USEC
const MAX_UNRETURNED_ATTEMPTS := 3
const ROOM_SCENE := preload(
	"res://world/maps/town/interiors/InteriorRoom.tscn"
)

class BuildJob:
	extends RefCounted
	var room: InteriorRoom
	var unreturned_attempts := 0

	func _init(room_value: InteriorRoom) -> void:
		room = room_value


var _order: Array[String] = []
var _jobs: Dictionary = {}
var _profiler := InteriorRoomBuildProfiler.new()


func _ready() -> void:
	_profiler.configure(false, FRAME_TARGET_USEC)
	set_process(false)


func _exit_tree() -> void:
	for job_value: Variant in _jobs.values():
		var job := job_value as BuildJob
		if is_instance_valid(job.room) and job.room.get_parent() == null:
			job.room.cancel_preparation()
			job.room.free()
	_jobs.clear()
	_order.clear()


func request(
	interior_id: String,
	definition: Dictionary,
	priority: bool = false,
) -> bool:
	if interior_id.is_empty() or definition.is_empty() or _jobs.has(interior_id):
		return false
	var room := ROOM_SCENE.instantiate() as InteriorRoom
	if room == null:
		return false
	if not room.begin_preparation(
		String(definition.get("shell_path", "")),
		definition.get("entry_point", Vector2.ZERO) as Vector2,
		definition.get("exit_point", Vector2.ZERO) as Vector2,
		String(definition.get("geometry_path", "")),
		String(definition.get("occlusion_path", "")),
		String(definition.get("furniture_manifest_path", "")),
		String(definition.get("layout_path", "")),
		true,
	):
		room.free()
		return false
	_jobs[interior_id] = BuildJob.new(room)
	_profiler.start_room(interior_id)
	if priority:
		_order.push_front(interior_id)
	else:
		_order.append(interior_id)
	set_process(true)
	return true


func is_pending(interior_id: String) -> bool:
	return _jobs.has(interior_id)


# 兼容旧调用。这里是调度目标，不是硬实时保证。
func get_frame_budget_usec() -> int:
	return FRAME_TARGET_USEC


func get_frame_target_usec() -> int:
	return FRAME_TARGET_USEC


func set_profiling_enabled(enabled: bool) -> void:
	if enabled == _profiler.is_enabled():
		return
	_profiler.configure(enabled, FRAME_TARGET_USEC)
	if enabled:
		for interior_id in _order:
			_profiler.start_room(interior_id)


func is_profiling_enabled() -> bool:
	return _profiler.is_enabled()


func get_profile_snapshot() -> Dictionary:
	return _profiler.snapshot()


func _process(_delta: float) -> void:
	if _order.is_empty():
		set_process(false)
		return
	var frame_started_usec := Time.get_ticks_usec()
	var deadline_usec := frame_started_usec + FRAME_TARGET_USEC
	while not _order.is_empty():
		if deadline_usec - Time.get_ticks_usec() < MIN_STEP_REMAINING_USEC:
			break
		var interior_id := _order[0]
		var job := _jobs.get(interior_id) as BuildJob
		if job == null or not is_instance_valid(job.room):
			_finish_failed(interior_id, "interior room disappeared")
		else:
			job.unreturned_attempts += 1
			if job.unreturned_attempts > MAX_UNRETURNED_ATTEMPTS:
				_finish_failed(
					interior_id,
					"interior preparation repeatedly aborted without returning",
				)
				continue
			var status := job.room.prepare_next_stage(
				deadline_usec,
				_profiler.is_enabled(),
			)
			job.unreturned_attempts = 0
			if status == null:
				_finish_failed(interior_id, "interior preparation returned no status")
				continue
			_profiler.record_step(interior_id, status)
			if status.failed:
				_finish_failed(interior_id, status.error)
			elif status.complete:
				_finish_prepared(interior_id, job.room)
			if status.waiting:
				break
		if Time.get_ticks_usec() >= deadline_usec:
			break
	_profiler.record_frame(Time.get_ticks_usec() - frame_started_usec)
	if _order.is_empty():
		set_process(false)


func _finish_prepared(interior_id: String, room: InteriorRoom) -> void:
	var profile := _profiler.finish_room(interior_id, false)
	_remove_job(interior_id)
	room_prepared.emit(interior_id, room, profile)


func _finish_failed(interior_id: String, error: String) -> void:
	var job := _jobs.get(interior_id) as BuildJob
	var profile := _profiler.finish_room(interior_id, true)
	_remove_job(interior_id)
	if job != null and is_instance_valid(job.room):
		job.room.cancel_preparation()
		job.room.free()
	room_failed.emit(interior_id, error, profile)


func _remove_job(interior_id: String) -> void:
	_jobs.erase(interior_id)
	_order.erase(interior_id)
