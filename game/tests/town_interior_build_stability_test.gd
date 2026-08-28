extends SceneTree

const TOWN_BASE := preload("res://world/maps/town/TownBase.gd")
const BUILD_QUEUE := preload(
	"res://world/maps/town/interiors/InteriorRoomBuildQueue.gd"
)
const MAX_BLOCKING_USEC := 25000
const MAX_BUILD_FRAMES := 1500

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cold := await _measure_round("cold")
	var hot := await _measure_round("hot")
	var queues: Array[Node] = []
	queues.assign([cold.get("queue"), hot.get("queue")])
	var prepared_rooms: Array[InteriorRoom] = []
	prepared_rooms.assign(cold.get("prepared_rooms", []))
	prepared_rooms.append_array(hot.get("prepared_rooms", []))
	cold.erase("queue")
	hot.erase("queue")
	cold.erase("prepared_rooms")
	hot.erase("prepared_rooms")
	for queue in queues:
		if is_instance_valid(queue):
			queue.queue_free()
	for room in prepared_rooms:
		if is_instance_valid(room):
			room.free()
	await process_frame
	await process_frame
	_assert_round(cold)
	_assert_round(hot)
	_expect_equal(
		cold.get("frame_target_usec"),
		8000,
		"cold preparation reports the eight-millisecond scheduling target",
	)
	_expect_equal(
		hot.get("frame_target_usec"),
		8000,
		"hot preparation reports the eight-millisecond scheduling target",
	)
	_finish(cold, hot)


func _measure_round(label: String) -> Dictionary:
	var queue := BUILD_QUEUE.new()
	root.add_child(queue)
	var prepared_rooms: Array[InteriorRoom] = []
	queue.room_prepared.connect(
		func(_interior_id: String, room: InteriorRoom, _profile: Dictionary) -> void:
			prepared_rooms.append(room),
	)
	queue.set_profiling_enabled(true)
	for interior_id_value: Variant in TOWN_BASE.INTERIOR_DEFINITIONS.keys():
		var interior_id := String(interior_id_value)
		queue.request(
			interior_id,
			TOWN_BASE.INTERIOR_DEFINITIONS.get(interior_id, {}) as Dictionary,
		)
	var frame_count := 0
	while frame_count < MAX_BUILD_FRAMES:
		var snapshot := queue.get_profile_snapshot() as Dictionary
		if (
			int(snapshot.get("completed_room_count", 0))
			+ int(snapshot.get("failed_room_count", 0))
			>= TOWN_BASE.INTERIOR_DEFINITIONS.size()
		):
			break
		frame_count += 1
		await process_frame
	var result := queue.get_profile_snapshot() as Dictionary
	result["label"] = label
	result["frame_count"] = frame_count
	result["queue"] = queue
	result["prepared_rooms"] = prepared_rooms
	return result


func _assert_round(result: Dictionary) -> void:
	var label := String(result.get("label", "unknown"))
	_expect_equal(
		result.get("completed_room_count"),
		TOWN_BASE.INTERIOR_DEFINITIONS.size(),
		"%s preparation completes all ten rooms" % label,
	)
	_expect_equal(
		result.get("failed_room_count"),
		0,
		"%s preparation has no failed room" % label,
	)
	_expect(
		int(result.get("frame_count", MAX_BUILD_FRAMES)) < MAX_BUILD_FRAMES,
		"%s preparation finishes before the focused-test timeout" % label,
	)
	_expect(
		int(result.get("max_frame_work_usec", MAX_BLOCKING_USEC + 1))
		<= MAX_BLOCKING_USEC,
		"%s preparation keeps every queue frame under 25 ms" % label,
	)
	_expect(
		int(result.get("max_stage_usec", MAX_BLOCKING_USEC + 1))
		<= MAX_BLOCKING_USEC,
		"%s preparation keeps every resumable stage under 25 ms" % label,
	)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s: expected %s, got %s" % [message, expected, actual])


func _finish(cold: Dictionary, hot: Dictionary) -> void:
	_prepare_audio_shutdown()
	var metrics := (
		"coldFrames=%d coldMaxFrameUsec=%d coldMaxStageUsec=%d coldSlowest=%s hotFrames=%d hotMaxFrameUsec=%d hotMaxStageUsec=%d hotSlowest=%s"
		% [
			int(cold.get("frame_count", 0)),
			int(cold.get("max_frame_work_usec", 0)),
			int(cold.get("max_stage_usec", 0)),
			_slowest_stage(cold),
			int(hot.get("frame_count", 0)),
			int(hot.get("max_frame_work_usec", 0)),
			int(hot.get("max_stage_usec", 0)),
			_slowest_stage(hot),
		]
	)
	if _failures.is_empty():
		print(
			"TOWN_INTERIOR_BUILD_STABILITY_PASS checks=%d %s"
			% [_checks, metrics],
		)
		call_deferred("_quit_after_cleanup", 0)
		return
	for failure in _failures:
		printerr("TOWN_INTERIOR_BUILD_STABILITY_FAIL: %s" % failure)
	printerr("TOWN_INTERIOR_BUILD_STABILITY_METRICS: %s" % metrics)
	call_deferred("_quit_after_cleanup", 1)


func _slowest_stage(profile: Dictionary) -> String:
	var slowest := "none"
	var slowest_usec := -1
	for room_id_value: Variant in (profile.get("rooms", {}) as Dictionary).keys():
		var room_id := String(room_id_value)
		var room := (profile.get("rooms", {}) as Dictionary).get(room_id, {}) as Dictionary
		for stage_value: Variant in (room.get("stages", {}) as Dictionary).keys():
			var stage := String(stage_value)
			var elapsed := int((room.get("stages", {}) as Dictionary).get(stage, 0))
			if elapsed > slowest_usec:
				slowest_usec = elapsed
				slowest = "%s/%s" % [room_id, stage]
	return slowest


func _quit_after_cleanup(exit_code: int) -> void:
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	quit(exit_code)


func _prepare_audio_shutdown() -> void:
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
