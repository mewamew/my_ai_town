extends "res://tests/support/TownWorldTestCase.gd"

const BRIDGE := preload("res://test_bridge/GameTestBridge.gd")
const TOWN_RUNTIME_SCENE := preload("res://world/presentation/town_runtime/TownRuntime.tscn")
var _world: RefCounted
var _bridge: Node
var _runtime: Node
var _session_id := "bridge-offline-fixture"
var _port := 18865
var _flow_host: RefCounted
var _websocket_test_buffer := PackedByteArray()


class FakeSessionFlowHost extends RefCounted:
	var world: RefCounted
	var world_data: Dictionary
	var opening: Dictionary
	var save_steps := 0
	var load_steps := 0
	var load_operation_id := ""
	var fail_next_save := false

	func configure(bound_world: RefCounted, data: Dictionary, opening_config: Dictionary) -> void:
		world = bound_world
		world_data = data
		opening = opening_config

	func gametest_begin_save() -> Dictionary:
		if save_steps > 0:
			return {"ok": false, "errorCode": "SESSION_SAVE_BUSY", "retryable": true}
		save_steps = 20
		return {"ok": true, "pending": true}

	func gametest_poll_save() -> Dictionary:
		if save_steps <= 0:
			return {"ok": true, "pending": false, "idle": true}
		save_steps -= 1
		if save_steps > 0:
			return {"ok": true, "pending": true}
		if fail_next_save:
			fail_next_save = false
			return {"ok": false, "pending": false, "errorCode": "TEST_SAVE_FAILED"}
		return {"ok": true, "pending": false, "context": {
			"slot_id": "isolated-slot", "session_id": "bridge-offline-fixture", "save_revision": 7,
		}}

	func gametest_begin_load(operation_id: String) -> Dictionary:
		load_operation_id = operation_id
		load_steps = 2
		return {"ok": true, "pending": true, "slotId": "isolated-slot",
			"sessionId": "bridge-offline-fixture", "saveRevision": 7}

	func gametest_poll_load(operation_id: String) -> Dictionary:
		if operation_id != load_operation_id:
			return {"ok": false, "errorCode": "SESSION_LOAD_OPERATION_NOT_FOUND"}
		load_steps -= 1
		if load_steps > 0:
			return {"ok": true, "pending": true, "operation": {"status": "running"}}
		if load_steps == 0:
			world.call("stop")
			world.call("start", world_data, opening)
		return {"ok": true, "pending": false, "operation": {
			"status": "completed", "slotId": "isolated-slot",
			"sessionId": "bridge-offline-fixture", "saveRevision": 7,
		}}


func _initialize() -> void:
	call_deferred("_run_bridge_tests")


func _context() -> Dictionary:
	return {"world": _world, "runtime": _runtime, "sessionId": _session_id, "flowHost": _flow_host}


func _header(path: String, method := "GET", extra := "") -> String:
	return "%s %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n%s\r\n" % [method, path, _port, extra]


func _run_bridge_tests() -> void:
	_bridge = BRIDGE.new()
	root.add_child(_bridge)
	_expect_equal(_bridge.start(_context, -1).get("errorCode"), "INVALID_BRIDGE_CONFIG", "invalid port rejected")
	var started: Dictionary = _bridge.start(_context, _port)
	_expect_equal(started.get("ok"), true, "loopback listener starts: %s" % [started])
	if not started.get("ok", false):
		_bridge.free()
		_finish_suite("GAMETEST_BRIDGE_PASS")
		return
	var duplicate := BRIDGE.new()
	_expect_equal(duplicate.start(_context, _port).get("errorCode"), "BRIDGE_LISTEN_FAILED", "port collision explicit")
	duplicate.free()
	var health := await _exchange(_header("/health"))
	_expect_equal(health.get("status"), 200, "HTTP health works before game starts")
	_expect_equal(health.get("body", {}).get("data", {}).get("worldReady"), false, "health distinguishes world readiness")
	var not_ready := await _exchange(_header("/world/state"))
	_expect_equal(not_ready.get("status"), 503, "world endpoint unavailable in menu")
	var data := _build_data()
	_world = WORLD.new()
	_expect_equal(_world.call("start", data, _load_opening(data)).get("ok"), true, "real fixture World starts without LLM")
	_flow_host = FakeSessionFlowHost.new()
	_flow_host.call("configure", _world, data, _load_opening(data))
	if OS.get_cmdline_user_args().has("--bridge-movement-only"):
		await _test_real_player_movement()
		_bridge.stop()
		_bridge.free()
		if is_instance_valid(_runtime):
			_runtime.queue_free()
		_finish_suite("GAMETEST_BRIDGE_MOVEMENT_PASS")
		return
	if OS.get_cmdline_user_args().has("--bridge-smoke-server"):
		if OS.get_cmdline_user_args().has("--bridge-smoke-commands"):
			_bridge.stop()
			_bridge.start(_context, _port, true)
		print("GAMETEST_SMOKE_READY http://127.0.0.1:%d" % _port)
		var smoke_duration := 1200.0 if OS.get_cmdline_user_args().has("--bridge-smoke-long") else 45.0
		await create_timer(smoke_duration).timeout
		_bridge.free()
		_finish_suite("GAMETEST_SMOKE_DONE")
		return
	var snapshot := await _exchange(_header("/world/state"))
	var snapshot_data: Dictionary = snapshot.get("body", {}).get("data", {})
	_expect_equal(snapshot.get("status"), 200, "real World snapshot over HTTP")
	_expect_equal(snapshot_data.get("residentCount"), 15, "15 actual residents")
	_expect_equal(snapshot_data.get("sessionId"), _session_id, "session identity preserved")
	_expect(snapshot_data.get("playerAvatar") is Dictionary, "world snapshot exposes public player avatar state")
	_expect((snapshot_data.get("playerAvatar", {}) as Dictionary).get("position") is Array, "player avatar Vector2 converted to JSON array")
	_expect_equal((snapshot_data.get("playerAvatar", {}) as Dictionary).size(), 7, "only seven public player avatar fields exposed")
	var resident_id := String(snapshot_data.get("residents", [{}])[0].get("residentId", ""))
	var resident := await _exchange(_header("/residents/" + resident_id))
	var resident_data: Dictionary = resident.get("body", {}).get("data", {}).get("resident", {})
	_expect_equal(resident_data.get("residentId"), resident_id, "lookup by stable ID")
	_expect(resident_data.get("position") is Array, "Vector2 converted to JSON array")
	_expect_equal(resident_data.size(), 7, "only seven public resident fields exposed")
	var version_before: int = _world.call("get_world_revision")
	for _repeat in 20:
		var repeated := await _exchange(_header("/world/state"))
		_expect_equal(repeated.get("status"), 200, "repeated queries keep frame loop alive")
	_expect_equal(_world.call("get_world_revision"), version_before, "reads do not mutate world revision")
	var cases := [
		[_header("/residents/unknown"), 404, "RESIDENT_NOT_FOUND"],
		[_header("/residents/阿禾"), 400, "MALFORMED_HTTP"],
		[_header("/missing"), 404, "ROUTE_NOT_FOUND"],
		[_header("/commands/save", "POST"), 405, "METHOD_NOT_ALLOWED"],
		[_header("/world/state?key=secret"), 400, "INVALID_PATH"],
		[_header("/health", "GET", "Origin: https://example.com\r\n"), 403, "ORIGIN_NOT_ALLOWED"],
		["GET /health HTTP/1.1\r\nHost: evil.example\r\n\r\n", 403, "HOST_NOT_ALLOWED"],
		[_header("/health", "GET", "Content-Length: 1\r\n"), 400, "BODY_NOT_ALLOWED"],
		[_header("/health", "GET", "Transfer-Encoding: chunked\r\n"), 400, "BODY_NOT_ALLOWED"],
		[_header("/health", "GET", "Host: duplicate\r\n"), 400, "MALFORMED_HTTP"],
		["broken\r\n\r\n", 400, "MALFORMED_HTTP"],
		[_header("/health", "GET", "X-Fill: " + "a".repeat(8200) + "\r\n"), 431, "HEADERS_TOO_LARGE"],
	]
	for test_case: Array in cases:
		var response := await _exchange(test_case[0])
		_expect_equal(response.get("status"), test_case[1], "HTTP rejection: " + test_case[2])
		_expect_equal(response.get("body", {}).get("error", {}).get("code"), test_case[2], "structured rejection: " + test_case[2])
	var split := await _exchange(_header("/health"), true)
	_expect_equal(split.get("status"), 200, "partial TCP headers assembled")
	_world.call("pause", "manual")
	var paused := await _exchange(_header("/world/state"))
	_expect_equal(paused.get("body", {}).get("data", {}).get("lifecycle", {}).get("paused"), true, "reads still work while paused")
	_world.call("stop")
	var stopped := await _exchange(_header("/world/state"))
	_expect_equal(stopped.get("status"), 503, "stopped World not published as ready")
	_world.call("start", data, _load_opening(data))
	var restarted := await _exchange(_header("/world/state"))
	_expect(restarted.get("body", {}).get("data", {}).get("worldGeneration") != snapshot_data.get("worldGeneration"), "restart of same object changes generation")
	await _test_slow_client()
	await _test_connection_limit()
	await _test_event_stream()
	await _test_session_commands()
	await _test_speed_commands(data)
	await _test_real_player_movement()
	_bridge.stop()
	_expect_equal(_bridge.start(_context, _port).get("ok"), true, "stop releases listener for reuse")
	_bridge.free()
	if is_instance_valid(_runtime):
		_runtime.queue_free()
	_finish_suite("GAMETEST_BRIDGE_PASS")


func _command(identifier: String, speed := 2) -> Dictionary:
	var state: Dictionary = _bridge.handle_http_header(_header("/world/state")).body.data
	return {"commandId": identifier, "idempotencyKey": "key-" + identifier,
		"expectedSessionId": state.sessionId, "expectedWorldGeneration": state.worldGeneration,
		"expectedStateVersion": state.stateVersion, "timeoutMs": 3000, "speed": speed}


func _post(command: Variant) -> String:
	return _post_path("/commands/set-speed", command)


func _post_path(path: String, command: Variant) -> String:
	var body := JSON.stringify(command)
	return _header(path, "POST", "Content-Type: application/json\r\nContent-Length: %d\r\n" % body.to_utf8_buffer().size()) + body


func _session_command(identifier: String, timeout_msec := 5000) -> Dictionary:
	var state: Dictionary = _bridge.handle_http_header(_header("/world/state")).body.data
	return {"commandId": identifier, "idempotencyKey": "key-" + identifier,
		"expectedSessionId": state.sessionId, "expectedWorldGeneration": state.worldGeneration,
		"expectedStateVersion": state.stateVersion, "timeoutMs": timeout_msec}


func _test_session_commands() -> void:
	_bridge.stop()
	_expect_equal(_bridge.start(_context, _port, true).get("ok"), true, "session-command listener starts")
	var save_command := _session_command("save-first")
	var save_accepted := await _exchange(_post_path("/commands/save", save_command), true)
	_expect_equal(save_accepted.get("status"), 202, "save is accepted asynchronously")
	_expect_equal(save_accepted.body.data.status, "running", "save acceptance is not publication completion")
	var concurrent_save := await _exchange(_post_path("/commands/save", _session_command("save-concurrent")))
	_expect_error(concurrent_save, 409, "SESSION_COMMAND_BUSY")
	var saved := await _wait_for_command(save_command.commandId)
	_expect_equal(saved.get("status"), "completed", "formal save publication reaches completed")
	_expect_equal((saved.get("result", {}) as Dictionary).get("saveRevision"), 7, "save receipt exposes published revision")
	var saved_query := await _exchange(_header("/commands/" + save_command.commandId))
	var save_replay := await _exchange(_post_path("/commands/save", save_command))
	_expect_equal(save_replay.body.data, saved_query.body.data, "save retry replays publication receipt")
	var before_load := _bridge.handle_http_header(_header("/world/state")).body.data as Dictionary
	var load_command := _session_command("load-first")
	var load_accepted := await _exchange(_post_path("/commands/load", load_command))
	_expect_equal(load_accepted.get("status"), 202, "load is accepted before scene replacement")
	_expect_equal(load_accepted.body.data.status, "running", "load acceptance does not claim restored world ready")
	var loaded := await _wait_for_command(load_command.commandId)
	_expect_equal(loaded.get("status"), "completed", "load completes only after replacement world is running")
	var after_load := _bridge.handle_http_header(_header("/world/state")).body.data as Dictionary
	_expect(after_load.worldGeneration != before_load.worldGeneration, "load changes world generation")
	var loaded_query := await _exchange(_header("/commands/" + load_command.commandId))
	var load_replay := await _exchange(_post_path("/commands/load", load_command))
	_expect_equal(load_replay.body.data, loaded_query.body.data, "load retry does not restore twice")
	var stale := _session_command("load-stale")
	stale.expectedWorldGeneration = before_load.worldGeneration
	_expect_error(await _exchange(_post_path("/commands/load", stale)), 409, "WORLD_GENERATION_CONFLICT")
	_bridge.stop()
	_expect_equal(_bridge.start(_context, _port).get("ok"), true, "session test restores read-only listener")


func _test_event_stream() -> void:
	_bridge.stop()
	_expect_equal(_bridge.start(_context, _port, true).get("ok"), true, "event-stream listener starts")
	var rejected := _bridge.handle_http_header(_header("/events")) as Dictionary
	_expect_error(rejected, 400, "INVALID_WEBSOCKET_UPGRADE")
	var peer := StreamPeerTCP.new()
	_websocket_test_buffer = PackedByteArray()
	_expect_equal(peer.connect_to_host("127.0.0.1", _port), OK, "WebSocket client connects")
	var deadline := Time.get_ticks_msec() + 5000
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		peer.poll()
		await process_frame
	var upgrade := _header("/events", "GET",
		"Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n")
	peer.put_data(upgrade.to_utf8_buffer())
	var handshake := PackedByteArray()
	while handshake.get_string_from_ascii().find("\r\n\r\n") < 0 and Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_available_bytes() > 0:
			handshake.append_array(peer.get_data(peer.get_available_bytes())[1])
		await process_frame
	var handshake_text := handshake.get_string_from_ascii()
	_expect(handshake_text.begins_with("HTTP/1.1 101 Switching Protocols"), "valid WebSocket upgrade returns 101")
	_expect(handshake_text.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo="), "WebSocket accept key follows RFC handshake")
	var command := _command("event-speed", 2)
	var response := _bridge.handle_http_header(_post(command)) as Dictionary
	_expect_equal(response.get("status"), 200, "event source command completes")
	var first_event := await _read_websocket_event_matching(peer, "command-completed", command.commandId)
	_expect_equal(first_event.get("eventType"), "command-completed", "WebSocket publishes command completion")
	_expect_equal(first_event.get("commandId"), command.commandId, "event correlates command ID")
	var second_event := await _read_websocket_event_matching(peer, "state-version-changed")
	_expect_equal(second_event.get("eventType"), "state-version-changed", "WebSocket publishes state version changes")
	_expect(int(second_event.get("eventSequence", 0)) > int(first_event.get("eventSequence", 0)), "event sequence is strictly increasing")
	_flow_host.set("fail_next_save", true)
	var failing_save := _session_command("event-save-failure")
	var save_response := _bridge.handle_http_header(_post_path("/commands/save", failing_save)) as Dictionary
	_expect_equal(save_response.get("status"), 202, "failing save is first accepted")
	var failed_receipt := await _wait_for_command(failing_save.commandId)
	_expect_equal(failed_receipt.get("status"), "failed", "accepted save reaches failed receipt")
	var failure_event := await _read_websocket_event_matching(peer, "command-failed", failing_save.commandId)
	_expect_equal(failure_event.get("eventType"), "command-failed", "WebSocket publishes command failure")
	_expect_equal(failure_event.get("commandId"), failing_save.commandId, "failure event correlates command ID")
	_expect_equal((failure_event.get("failure", {}) as Dictionary).get("code"), "TEST_SAVE_FAILED", "failure event keeps terminal error code")
	peer.disconnect_from_host()
	_world.call("set_simulation_speed", 1)
	_bridge.stop()
	_expect_equal(_bridge.start(_context, _port).get("ok"), true, "event test restores read-only listener")


func _read_websocket_event(peer: StreamPeerTCP) -> Dictionary:
	var received := _websocket_test_buffer
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_available_bytes() > 0:
			received.append_array(peer.get_data(peer.get_available_bytes())[1])
		if received.size() >= 2:
			var payload_length := int(received[1]) & 0x7f
			var header_length := 2
			var header_ready := true
			if payload_length == 126 and received.size() >= 4:
				payload_length = (int(received[2]) << 8) | int(received[3])
				header_length = 4
			elif payload_length == 126:
				header_ready = false
			if header_ready and received.size() >= header_length + payload_length:
				_websocket_test_buffer = received.slice(header_length + payload_length)
				var parsed: Variant = JSON.parse_string(
					received.slice(header_length, header_length + payload_length).get_string_from_utf8()
				)
				return parsed as Dictionary if parsed is Dictionary else {}
		await process_frame
	_websocket_test_buffer = received
	return {}


func _read_websocket_event_matching(peer: StreamPeerTCP, event_type: String, command_id := "") -> Dictionary:
	for _attempt in 24:
		var event := await _read_websocket_event(peer)
		if event.is_empty():
			return {}
		if (
			String(event.get("eventType", "")) == event_type
			and (command_id.is_empty() or String(event.get("commandId", "")) == command_id)
		):
			return event
	return {}


func _expect_error(response: Dictionary, status: int, code: String) -> void:
	_expect_equal(response.get("status"), status, code + " HTTP status")
	var error_value: Variant = response.get("body", {}).get("error")
	_expect_equal(
		(error_value as Dictionary).get("code") if error_value is Dictionary else null,
		code,
		"structured " + code,
	)


func _test_speed_commands(data: Dictionary) -> void:
	var command := _command("speed-first")
	_expect_error(await _exchange(_post(command)), 405, "METHOD_NOT_ALLOWED")
	_expect_equal(_world.call("get_simulation_speed"), 1, "default read-only leaves speed unchanged")
	_bridge.stop()
	_expect_equal(_bridge.start(_context, _port, true).get("ok"), true, "explicit command listener starts")
	var health := await _exchange(_header("/health"))
	_expect_equal(health.body.data.readOnly, false, "health reports write capability")
	var before: int = _world.call("get_world_revision")
	var first := await _exchange(_post(command), true)
	_expect_equal(first.get("status"), 200, "split header and body accepted")
	if first.get("status") != 200:
		return
	_expect_equal(first.body.data.status, "completed", "speed receipt is completed, not just accepted")
	_expect_equal(first.body.data.accepted, true, "accepted command identity present")
	_expect_equal(first.body.data.commandId, command.commandId, "command ID correlated")
	_expect_equal(_world.call("get_simulation_speed"), 2, "real World speed changed")
	_expect_equal(_world.call("get_world_revision"), before + 1, "speed changes world revision exactly once")
	var replay := await _exchange(_post(command))
	_expect_equal(replay.body.data, first.body.data, "retry gets immutable original receipt despite stale expected version")
	_expect(first.body.requestId != replay.body.requestId, "HTTP retries have separate request IDs")
	_expect_equal(_world.call("get_world_revision"), before + 1, "retry does not re-execute")
	var status := await _exchange(_header("/commands/" + command.commandId))
	_expect_equal(status.body.data, first.body.data, "GET recovers result after a lost response")
	_expect_error(await _exchange(_header("/commands/unknown")), 404, "COMMAND_NOT_FOUND")
	var changed := command.duplicate(true)
	changed.speed = 3
	_expect_error(await _exchange(_post(changed)), 409, "IDEMPOTENCY_CONFLICT")
	changed = command.duplicate(true)
	changed.idempotencyKey = "different-key"
	_expect_error(await _exchange(_post(changed)), 409, "COMMAND_ID_CONFLICT")
	var invalid_cases := [
		["speed", 0, 400, "INVALID_COMMAND_SCHEMA"],
		["speed", 4, 400, "INVALID_COMMAND_SCHEMA"],
		["speed", true, 400, "INVALID_COMMAND_SCHEMA"],
		["speed", "2", 400, "INVALID_COMMAND_SCHEMA"],
		["speed", 1.5, 400, "INVALID_COMMAND_SCHEMA"],
		["timeoutMs", 0, 400, "INVALID_COMMAND_SCHEMA"],
		["timeoutMs", 3001, 400, "INVALID_COMMAND_SCHEMA"],
		["expectedStateVersion", true, 400, "INVALID_COMMAND_SCHEMA"],
		["expectedStateVersion", -1, 400, "INVALID_COMMAND_SCHEMA"],
		["expectedStateVersion", before, 409, "STATE_VERSION_CONFLICT"],
		["expectedSessionId", "old-session", 409, "SESSION_CONFLICT"],
		["expectedWorldGeneration", "old-generation", 409, "WORLD_GENERATION_CONFLICT"],
		["commandId", "../bad", 400, "INVALID_COMMAND_SCHEMA"],
		["commandId", "", 400, "INVALID_COMMAND_SCHEMA"],
		["commandId", "a".repeat(129), 400, "INVALID_COMMAND_SCHEMA"],
		["extra", 1, 400, "INVALID_COMMAND_SCHEMA"],
	]
	for test_case: Array in invalid_cases:
		changed = _command("invalid-case", 3)
		changed[test_case[0]] = test_case[1]
		_expect_error(await _exchange(_post(changed)), test_case[2], test_case[3])
	changed = _command("missing-field")
	changed.erase("speed")
	_expect_error(await _exchange(_post(changed)), 400, "INVALID_COMMAND_SCHEMA")
	_expect_error(await _exchange(_post([])), 400, "INVALID_JSON")
	_expect_error(await _exchange(_header("/commands/set-speed", "POST", "Content-Type: application/json\r\nContent-Length: 1\r\n") + "{"), 400, "INVALID_JSON")
	_expect_error(await _exchange(_header("/commands/set-speed", "POST", "Content-Type: application/json\r\nContent-Length: 4097\r\n")), 413, "BODY_TOO_LARGE")
	_expect_error(await _exchange(_header("/commands/set-speed", "POST", "Content-Length: -1\r\n")), 400, "INVALID_CONTENT_LENGTH")
	_expect_error(await _exchange(_header("/commands/set-speed", "POST", "Content-Length: 0\r\n")), 415, "JSON_CONTENT_TYPE_REQUIRED")
	_expect_error(await _exchange(_header("/commands/set-speed", "POST", "Transfer-Encoding: chunked\r\n")), 400, "TRANSFER_ENCODING_NOT_ALLOWED")
	_expect_error(await _exchange(_header("/commands/save", "POST")), 400, "INVALID_CONTENT_LENGTH")
	var origin_request := _post(_command("origin")).replace("Content-Type:", "Origin: http://localhost\r\nContent-Type:")
	_expect_error(await _exchange(origin_request), 403, "ORIGIN_NOT_ALLOWED")
	var host_request := _post(_command("host")).replace("127.0.0.1:%d" % _port, "evil.example")
	_expect_error(await _exchange(host_request), 403, "HOST_NOT_ALLOWED")
	# Inject elapsed receive time only in the test, without sleeping or changing environment.
	var expired := _command("expired", 3)
	var timed_out: Dictionary = _bridge._parse_request(_post(expired).to_utf8_buffer(), Time.get_ticks_msec() - 3001, false)
	_expect_error(timed_out, 408, "COMMAND_TIMEOUT")
	expired.timeoutMs = 1
	_expect_error(await _exchange(_post(expired), true), 408, "COMMAND_TIMEOUT")
	var truncated_request := _post(_command("truncated", 3))
	_expect_error(_bridge.handle_http_header(truncated_request.substr(0, truncated_request.length() - 1)), 400, "INCOMPLETE_BODY")
	_expect_error(await _exchange(_post(_command("extra-bytes", 3)) + "x"), 400, "BODY_LENGTH_MISMATCH")
	_expect_equal(_world.call("get_simulation_speed"), 2, "invalid/conflicting/expired commands have no side effects")
	_expect_equal(_world.call("get_world_revision"), before + 1, "rejected commands do not bump version")
	var noop := await _exchange(_post(_command("noop", 2)))
	_expect_equal(noop.body.data.result.changed, false, "same speed is an explicit no-op")
	_expect_equal(_world.call("get_world_revision"), before + 1, "no-op leaves version unchanged")
	var old_generation := _command("old-world", 3)
	_world.call("stop")
	_expect_error(await _exchange(_post(_command_from_snapshot(old_generation, "stopped"))), 503, "WORLD_NOT_READY")
	_world.call("start", data, _load_opening(data))
	old_generation.expectedStateVersion = _world.call("get_world_revision")
	_expect_error(await _exchange(_post(old_generation)), 409, "WORLD_GENERATION_CONFLICT")
	var old_replay := await _exchange(_post(command))
	_expect_equal(old_replay.body.data, first.body.data, "old receipt is retained across World restart, never executed again")
	_expect_equal(_world.call("get_simulation_speed"), 1, "old retry does not mutate replacement World")
	var fresh := await _exchange(_post(_command("fresh-world", 3)))
	_expect_equal(fresh.get("status"), 200, "fresh generation executes")
	_expect_equal(_world.call("get_simulation_speed"), 3, "third speed supported")
	# Capacity is deliberately bounded; fill through real command handling, not cache mutation.
	while (_bridge.get("_commands") as Dictionary).size() < BRIDGE.MAX_COMMANDS:
		var identifier := "capacity-%d" % (_bridge.get("_commands") as Dictionary).size()
		var filled: Dictionary = _bridge.handle_http_header(_post(_command(identifier, 3)))
		_expect_equal(filled.get("status"), 200, "bounded receipt table accepts remaining slot")
	_expect_error(await _exchange(_post(_command("overflow", 2))), 503, "COMMAND_CAPACITY_REACHED")
	_expect_equal(_world.call("get_simulation_speed"), 3, "full receipt cache rejects before side effect")
	var retained := await _exchange(_post(command))
	_expect_equal(retained.body.data, first.body.data, "old receipt still replays at capacity")
	_bridge.stop()
	_bridge.start(_context, _port, true)
	var after_restart := await _exchange(_post(command))
	_expect_equal(after_restart.body.data, first.body.data, "listener restart retains receipt safety")


func _command_from_snapshot(source: Dictionary, identifier: String) -> Dictionary:
	var result := source.duplicate(true)
	result.commandId = identifier
	result.idempotencyKey = "key-" + identifier
	return result


func _move_command(identifier: String, target: Vector2, timeout_msec := 3000) -> Dictionary:
	var state: Dictionary = _bridge.handle_http_header(_header("/world/state")).body.data
	var movement := _runtime.call("get_avatar_movement_state") as Dictionary
	return {"commandId": identifier, "idempotencyKey": "key-" + identifier,
		"expectedSessionId": state.sessionId, "expectedWorldGeneration": state.worldGeneration,
		"expectedStateVersion": state.stateVersion, "timeoutMs": timeout_msec,
		"spaceId": movement.get("spaceId", ""), "targetPosition": [target.x, target.y], "tolerance": 6.0}


func _choose_clear_target(origin: Vector2, distance := 96.0) -> Vector2:
	for offset in [Vector2(distance, 0), Vector2(-distance, 0), Vector2(0, distance), Vector2(0, -distance)]:
		var candidate: Vector2 = origin + (offset as Vector2)
		if bool((_runtime.call("validate_virtual_movement_target", "town_outdoor", candidate) as Dictionary).get("ok", false)):
			return candidate
	return Vector2.INF


func _wait_for_command(command_id: String, timeout_msec := 5000) -> Dictionary:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		var record := (_bridge.get("_commands") as Dictionary).get(command_id, {}) as Dictionary
		var receipt := record.get("receipt", {}) as Dictionary
		if String(receipt.get("status", "")) in ["completed", "failed"]:
			return receipt.duplicate(true)
		await physics_frame
	return {}


func _test_real_player_movement() -> void:
	_bridge.stop()
	_bridge.free()
	_runtime = TOWN_RUNTIME_SCENE.instantiate()
	var opening := _load_opening(_build_data())
	var configured := _runtime.call("configure_session", {
		"openingConfig": opening,
		"sessionId": "bridge-movement-fixture",
		"worldStartMode": "development",
		"useLiveModel": false,
	}) as Dictionary
	_expect_equal(configured.get("ok"), true, "movement fixture uses formal session configuration entry")
	root.add_child(_runtime)
	for _frame in 12:
		await process_frame
	var startup := _runtime.call("get_startup_result") as Dictionary
	_expect_equal(startup.get("ok"), true, "real Town Runtime starts for movement bridge")
	if not bool(startup.get("ok", false)):
		_bridge = BRIDGE.new()
		root.add_child(_bridge)
		_bridge.start(_context, _port, true)
		return
	_world = _runtime.call("get_world_runtime") as RefCounted
	_session_id = "bridge-movement-fixture"
	_bridge = BRIDGE.new()
	root.add_child(_bridge)
	_expect_equal(_bridge.start(_context, _port, true).get("ok"), true, "movement bridge starts on real Town")
	var inactive_state := _runtime.call("get_avatar_movement_state") as Dictionary
	var inactive_target := (inactive_state.get("position", Vector2.ZERO) as Vector2) + Vector2(64, 0)
	_expect_error(await _exchange(_post_path("/commands/move-player", _move_command("inactive", inactive_target))), 409, "AVATAR_NOT_ACTIVE")
	_expect_equal((_runtime.call("enter_avatar_mode") as Dictionary).get("ok"), true, "formal avatar descent begins")
	_expect_equal((_runtime.call("complete_avatar_descent") as Dictionary).get("ok"), true, "test reaches formal active avatar state")
	await physics_frame
	var movement := _runtime.call("get_avatar_movement_state") as Dictionary
	_expect_equal(movement.get("avatarMode"), "avatar_active", "movement adapter exposes active avatar mode")
	_expect_equal(movement.get("present"), true, "movement adapter maps the player avatar present field")
	var start := movement.position as Vector2
	var target := _choose_clear_target(start)
	_expect(target.is_finite(), "finds a safe nearby outdoor movement target")
	if not target.is_finite():
		return
	var command: Dictionary = {}
	var accepted: Dictionary = {}
	for attempt in 12:
		command = _move_command("move-success-%d" % attempt, target, 5000)
		accepted = await _exchange(_post_path("/commands/move-player", command), true)
		if accepted.get("status") == 202:
			break
		_expect_equal(accepted.get("body", {}).get("error", {}).get("code"), "STATE_VERSION_CONFLICT", "live-world retry only follows an observed version race")
	_expect_equal(accepted.get("status"), 202, "real movement is accepted asynchronously: %s" % [accepted])
	if accepted.get("status") != 202:
		return
	_expect_equal(accepted.body.data.status, "running", "POST does not claim movement already completed")
	var position_after_accept := (_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2
	_expect(position_after_accept.distance_to(target) > float(command.tolerance), "acceptance does not teleport to target")
	var busy := _move_command("move-busy", start, 5000)
	var busy_response: Dictionary = _bridge.handle_http_header(_post_path("/commands/move-player", busy))
	_expect_error(busy_response, 409, "PLAYER_MOVE_BUSY")
	var samples: Array[Vector2] = [position_after_accept]
	var terminal: Dictionary = {}
	for _frame in 360:
		await physics_frame
		var current := (_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2
		if samples[-1].distance_to(current) > 0.1:
			samples.append(current)
		var record := (_bridge.get("_commands") as Dictionary).get(command.commandId, {}) as Dictionary
		terminal = (record.get("receipt", {}) as Dictionary).duplicate(true)
		if String(terminal.get("status", "")) in ["completed", "failed"]:
			break
	_expect_equal(terminal.get("status"), "completed", "real CharacterBody movement reaches target")
	_expect(samples.size() >= 3, "movement is observed across multiple physics frames")
	var finish := (_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2
	_expect(finish.distance_to(target) <= float(command.tolerance) + 1.0, "final physical position is within tolerance")
	var queried := await _exchange(_header("/commands/" + command.commandId))
	_expect_equal(queried.body.data.status, "completed", "completed movement is queryable over HTTP")
	var replayed := await _exchange(_post_path("/commands/move-player", command))
	_expect_equal(replayed.body.data, queried.body.data, "completed movement retry replays result without moving again")
	var timeout_target := _choose_clear_target(finish, 96.0)
	var timeout_command := _move_command("move-timeout", timeout_target, 10)
	var timeout_accept: Dictionary = _bridge.handle_http_header(
		_post_path("/commands/move-player", timeout_command),
	)
	_expect_equal(timeout_accept.get("status"), 202, "short-deadline movement is accepted before execution timeout")
	var timeout_result := await _wait_for_command(timeout_command.commandId, 2000)
	_expect_equal(timeout_result.get("status"), "failed", "movement timeout reaches a terminal receipt")
	var timeout_failure: Variant = timeout_result.get("failure")
	_expect(timeout_failure is Dictionary, "failed movement publishes structured failure")
	if timeout_failure is Dictionary:
		_expect_equal((timeout_failure as Dictionary).get("code"), "MOVE_TIMEOUT", "movement timeout has distinct error code")
	var timeout_stop := (_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2
	for _frame in 12:
		await physics_frame
	_expect(
		((_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2).distance_to(timeout_stop) <= 0.25,
		"timed-out movement clears virtual input",
	)
	finish = (_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2
	_world.call("pause", "manual")
	var pause_target := _choose_clear_target(finish, 48.0)
	_expect_error(await _exchange(_post_path("/commands/move-player", _move_command("paused-move", pause_target))), 409, "WORLD_PAUSED")
	_world.call("resume", "manual")
	_runtime.call("set_avatar_movement_input_enabled", false)
	_expect_error(await _exchange(_post_path("/commands/move-player", _move_command("blocked-input", pause_target))), 409, "AVATAR_MOVEMENT_BLOCKED")
	_runtime.call("set_avatar_movement_input_enabled", true)
	var wrong_space := _move_command("wrong-space", pause_target)
	wrong_space.spaceId = "home_01"
	_expect_error(await _exchange(_post_path("/commands/move-player", wrong_space)), 409, "SPACE_CONFLICT")
	var unsafe := _move_command("unsafe-target", Vector2(-1000, -1000))
	_expect_error(await _exchange(_post_path("/commands/move-player", unsafe)), 422, "TARGET_NOT_WALKABLE")
	var malformed := _move_command("bad-position", pause_target)
	malformed.targetPosition = [1]
	_expect_error(await _exchange(_post_path("/commands/move-player", malformed)), 400, "INVALID_COMMAND_SCHEMA")
	malformed = _move_command("bad-tolerance", pause_target)
	malformed.tolerance = 100
	_expect_error(await _exchange(_post_path("/commands/move-player", malformed)), 400, "INVALID_COMMAND_SCHEMA")
	# A test-only in-memory wall proves the endpoint uses CharacterBody collision.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(28, 220)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	var blocked_start := (_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2
	wall.position = blocked_start + Vector2(54, -12)
	_runtime.add_child(wall)
	await physics_frame
	var blocked_target := blocked_start + Vector2(132, 0)
	_expect(bool((_runtime.call("validate_virtual_movement_target", "town_outdoor", blocked_target) as Dictionary).get("ok", false)), "wall test keeps destination itself walkable")
	var blocked_command := _move_command("collision-blocked", blocked_target, 4000)
	var blocked_accept := await _exchange(_post_path("/commands/move-player", blocked_command))
	_expect_equal(blocked_accept.get("status"), 202, "collision case is accepted before it encounters wall")
	var blocked_result := await _wait_for_command(blocked_command.commandId, 3500)
	_expect_equal(blocked_result.get("status"), "failed", "collision stall reaches terminal failure")
	_expect_equal((blocked_result.get("failure", {}) as Dictionary).get("code"), "MOVE_BLOCKED", "collision stall has distinct error code")
	var stopped_position := (_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2
	for _frame in 12:
		await physics_frame
	var settled_position := (_runtime.call("get_avatar_movement_state") as Dictionary).position as Vector2
	_expect(
		settled_position.distance_to(stopped_position) <= 0.25,
		"failed movement clears virtual input after sub-pixel collision settling",
	)
	wall.queue_free()
	await physics_frame


func _exchange(raw: String, split := false) -> Dictionary:
	var peer := StreamPeerTCP.new()
	_expect_equal(peer.connect_to_host("127.0.0.1", _port), OK, "client connects")
	var deadline := Time.get_ticks_msec() + 5000
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		peer.poll()
		await process_frame
	var bytes := raw.to_utf8_buffer()
	var sent := 0
	while sent < bytes.size() and Time.get_ticks_msec() < deadline:
		var chunk_end := mini(sent + (7 if split else 4096), bytes.size())
		var result := peer.put_partial_data(bytes.slice(sent, chunk_end))
		if result[0] != OK:
			break
		sent += int(result[1])
		await process_frame
	var received := PackedByteArray()
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var available := peer.get_available_bytes()
		if available > 0:
			var result := peer.get_partial_data(available)
			received.append_array(result[1])
		await process_frame
	peer.disconnect_from_host()
	var wire := received.get_string_from_utf8()
	var header_end := wire.find("\r\n\r\n")
	if header_end < 0:
		_failures.append("No complete HTTP response")
		return {}
	var body_text := wire.substr(header_end + 4)
	var body: Variant = JSON.parse_string(body_text)
	_expect(body is Dictionary, "response parses as JSON")
	for line in wire.substr(0, header_end).split("\r\n"):
		if line.begins_with("Content-Length: "):
			_expect_equal(int(line.trim_prefix("Content-Length: ")), body_text.to_utf8_buffer().size(), "UTF-8 byte length correct")
	return {"status": int(wire.split(" ")[1]), "body": body}


func _test_slow_client() -> void:
	var slow := StreamPeerTCP.new()
	slow.connect_to_host("127.0.0.1", _port)
	for _frame in 5:
		slow.poll()
		await process_frame
	slow.put_partial_data("GET /health HTTP/1.1\r\n".to_utf8_buffer())
	var healthy := await _exchange(_header("/health"))
	_expect_equal(healthy.get("status"), 200, "incomplete client does not block another request")
	await create_timer(3.2).timeout
	slow.poll()
	_expect(slow.get_status() != StreamPeerTCP.STATUS_CONNECTED, "incomplete client times out")
	slow.disconnect_from_host()


func _test_connection_limit() -> void:
	var peers: Array[StreamPeerTCP] = []
	for _index in BRIDGE.MAX_CLIENTS + 1:
		var peer := StreamPeerTCP.new()
		peer.connect_to_host("127.0.0.1", _port)
		peers.append(peer)
	for _frame in 12:
		for peer in peers:
			peer.poll()
		await process_frame
	_expect_equal((_bridge.get("_clients") as Array).size(), BRIDGE.MAX_CLIENTS, "retained connections capped")
	_expect(peers[-1].get_status() != StreamPeerTCP.STATUS_CONNECTED, "overload connection closed")
	for peer in peers:
		peer.disconnect_from_host()
	for _frame in 5:
		await process_frame
	var recovered := await _exchange(_header("/health"))
	_expect_equal(recovered.get("status"), 200, "listener recovers after overload")
