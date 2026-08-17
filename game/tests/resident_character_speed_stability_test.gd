extends SceneTree


const RESIDENT_BODY := preload(
	"res://world/presentation/residents/ResidentCharacterBody.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var blocker := RESIDENT_BODY.new()
	var mover := RESIDENT_BODY.new()
	root.add_child(blocker)
	root.add_child(mover)
	blocker.set_automatic_motion(false)
	mover.set_automatic_motion(false)
	var blocker_state := _state("speed-blocker", Vector2(42.0, 0.0))
	var mover_state := _state("speed-mover", Vector2.ZERO)
	_expect(
		bool(blocker.configure({
			"residentId": "speed-blocker",
			"residentName": "挡路居民",
		}, blocker_state).get("ok", false)),
		"blocking resident configures",
	)
	_expect(
		bool(mover.configure({
			"residentId": "speed-mover",
			"residentName": "倍率居民",
		}, mover_state).get("ok", false)),
		"moving resident configures",
	)
	_expect_equal(
		mover.collision_mask,
		11,
		"resident movement does not collide with other resident bodies",
	)
	var route_state := mover_state.duplicate(true)
	route_state["position"] = Vector2(80.0, 0.0)
	route_state["isMoving"] = true
	route_state["currentAction"] = {
		"action_id": "speed-route",
		"type": "去",
	}
	route_state["target"] = {
		"spaceId": "town_outdoor",
		"placeName": "社区花园",
		"position": Vector2(80.0, 0.0),
	}
	route_state["movementRevision"] = 2
	var applied := mover.apply_authoritative_state(
		route_state,
		2,
		null,
		false,
		0.5,
	)
	_expect_equal(applied.get("status"), "following", "2x route remains a walking target")
	var maximum_frame_distance := 0.0
	for _frame in 40:
		await physics_frame
		var before := mover.position
		mover.advance_presentation(1.0 / 60.0)
		maximum_frame_distance = maxf(
			maximum_frame_distance,
			before.distance_to(mover.position),
		)
	_expect(
		mover.position.distance_to(Vector2(80.0, 0.0)) < 0.1,
		"2x movement reaches the confirmed route sample without relocation",
	)
	for diagnostic_value: Variant in mover.take_presentation_diagnostics():
		if not diagnostic_value is Dictionary:
			continue
		var code := String((diagnostic_value as Dictionary).get("code", ""))
		_expect(
			code not in [
				"PRESENTATION_BLOCKED_AUTHORITY_RESYNC",
				"PRESENTATION_LARGE_CORRECTION_RELOCATED",
			],
			"2x route does not fall back to authority relocation (%s)" % code,
		)
	route_state["position"] = Vector2(120.0, 0.0)
	route_state["target"]["position"] = Vector2(120.0, 0.0)
	route_state["movementRevision"] = 3
	var three_x_applied := mover.apply_authoritative_state(
		route_state,
		3,
		null,
		false,
		1.0 / 3.0,
	)
	_expect_equal(
		three_x_applied.get("status"),
		"following",
		"switching from 2x to 3x keeps the resident on a walking target",
	)
	for _frame in 80:
		await physics_frame
		var before := mover.position
		mover.advance_presentation(1.0 / 60.0)
		maximum_frame_distance = maxf(
			maximum_frame_distance,
			before.distance_to(mover.position),
		)
	_expect(
		maximum_frame_distance <= 8.0,
		"2x-to-3x movement advances in walking-sized frames (max %.3f px)"
		% maximum_frame_distance,
	)
	_expect(
		mover.position.distance_to(Vector2(120.0, 0.0)) < 0.1,
		"3x movement reaches the confirmed route sample without relocation",
	)
	route_state["position"] = Vector2(200.0, 0.0)
	route_state["target"]["position"] = Vector2(200.0, 0.0)
	route_state["movementRevision"] = 4
	var slow_frame_applied := mover.apply_authoritative_state(
		route_state,
		4,
		null,
		false,
		1.0 / 3.0,
	)
	_expect_equal(
		slow_frame_applied.get("status"),
		"following",
		"slow-frame route remains a walking target",
	)
	var before_slow_frame := mover.position
	mover.advance_presentation(0.05)
	_expect(
		before_slow_frame.distance_to(mover.position) <= 8.01,
		"a 50 ms presentation update never becomes one large visible step",
	)
	_expect(
		mover.position.distance_to(Vector2(200.0, 0.0)) > 0.1,
		"slow-frame smoothing does not rewrite visual position to authority",
	)
	for diagnostic_value: Variant in mover.take_presentation_diagnostics():
		if not diagnostic_value is Dictionary:
			continue
		var code := String((diagnostic_value as Dictionary).get("code", ""))
		_expect(
			code not in [
				"PRESENTATION_BLOCKED_AUTHORITY_RESYNC",
				"PRESENTATION_LARGE_CORRECTION_RELOCATED",
			],
			"3x route does not fall back to authority relocation (%s)" % code,
		)
	blocker.queue_free()
	mover.queue_free()
	# 与 TownWorldTestCase 的统一收尾保持一致：自动加载的模型脚本需要几帧
	# 完成 _ready 后再释放音频与退出，否则断言虽通过，Godot 仍会报告资源泄漏。
	for _index in 5:
		await process_frame
	_finish()


func _state(resident_id: String, position: Vector2) -> Dictionary:
	return {
		"residentId": resident_id,
		"name": resident_id,
		"appearance": "",
		"position": position,
		"spaceId": "town_outdoor",
		"regionId": "",
		"currentPlace": "南入口",
		"doing": "",
		"body": {},
		"currentAction": null,
		"actionPhase": {"phase": "idle"},
		"movementRevision": 1,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s: expected %s, got %s" % [message, expected, actual]
		)


func _finish() -> void:
	var exit_code := 0 if _failures.is_empty() else 1
	if _failures.is_empty():
		print("RESIDENT_CHARACTER_SPEED_STABILITY_PASS")
	else:
		for failure in _failures:
			printerr("RESIDENT_CHARACTER_SPEED_STABILITY_FAIL: ", failure)
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	quit(exit_code)
