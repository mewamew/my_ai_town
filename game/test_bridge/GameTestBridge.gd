extends Node
## Opt-in, loopback-only HTTP/1.1 bridge. Never dispatches arbitrary methods.

const DEFAULT_PORT := 18765
const MAX_CLIENTS := 8
const MAX_HEADER_BYTES := 8192
const MAX_BODY_BYTES := 4096
const MAX_COMMANDS := 128
const MAX_RESPONSE_BYTES := 65536
const IO_CHUNK_BYTES := 4096
const FRAME_BUDGET_USEC := 2000
const CLIENT_TIMEOUT_MSEC := 3000
const MAX_MOVE_TIMEOUT_MSEC := 30000
const MAX_SESSION_TIMEOUT_MSEC := 120000
const MOVE_STALL_TIMEOUT_MSEC := 1200
const MOVE_PROGRESS_EPSILON := 0.5
const MAX_EVENT_QUEUE := 64
const WEBSOCKET_GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _context_provider: Callable
var _port := 0
var _sequence := 0
var _nonce := Crypto.new().generate_random_bytes(12).hex_encode()
var _commands_enabled := false
# No eviction: losing a receipt must never silently permit duplicate execution.
var _commands: Dictionary = {}
var _idempotency: Dictionary = {}
var _active_move_id := ""
var _active_session_command_id := ""
var _event_sequence := 0
var _last_observed_state: Dictionary = {}


func start(context_provider: Callable, port: int = DEFAULT_PORT, commands_enabled := false) -> Dictionary:
	if _server.is_listening():
		return {"ok": false, "errorCode": "BRIDGE_ALREADY_STARTED"}
	if not context_provider.is_valid() or port < 1 or port > 65535:
		return {"ok": false, "errorCode": "INVALID_BRIDGE_CONFIG"}
	var error := _server.listen(port, "127.0.0.1")
	if error != OK:
		return {"ok": false, "errorCode": "BRIDGE_LISTEN_FAILED", "engineError": error}
	_context_provider = context_provider
	_port = port
	_commands_enabled = commands_enabled
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	return {"ok": true, "address": "127.0.0.1", "port": port}


func stop() -> void:
	if not _active_move_id.is_empty():
		_finish_move_failure("BRIDGE_STOPPED")
	if not _active_session_command_id.is_empty():
		_finish_session_failure("BRIDGE_STOPPED")
	_server.stop()
	for client in _clients:
		(client.peer as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	_context_provider = Callable()
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	_advance_move_command()
	_advance_session_command()
	_observe_state_version()
	poll()


func poll() -> void:
	if not _server.is_listening():
		return
	var started := Time.get_ticks_usec()
	# Bound acceptance as well as retained connections, including overload.
	for _attempt in MAX_CLIENTS:
		if not _server.is_connection_available():
			break
		var peer := _server.take_connection()
		if _clients.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		_clients.append({
			"peer": peer, "input": PackedByteArray(), "output": PackedByteArray(),
			"offset": 0, "created": Time.get_ticks_msec(), "responding": false,
			"mode": "http", "upgrading": false, "events": [], "closing": false,
		})
	# Rotate the queue so one slow reader cannot monopolize the frame budget.
	var count := _clients.size()
	for _index in count:
		if Time.get_ticks_usec() - started >= FRAME_BUDGET_USEC:
			break
		var client: Dictionary = _clients.pop_front()
		if _poll_client(client):
			_clients.append(client)


func _poll_client(client: Dictionary) -> bool:
	var peer := client.peer as StreamPeerTCP
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()
		return false
	if bool(client.closing):
		peer.disconnect_from_host()
		return false
	if String(client.mode) == "websocket":
		return _poll_websocket_client(client, peer)
	# Absolute lifetime, not sliding inactivity: slow-drip requests also expire.
	if Time.get_ticks_msec() - int(client.created) > CLIENT_TIMEOUT_MSEC:
		peer.disconnect_from_host()
		return false
	if not bool(client.responding):
		var available := mini(peer.get_available_bytes(), IO_CHUNK_BYTES)
		if available > 0:
			var read := peer.get_partial_data(available)
			if read[0] != OK:
				peer.disconnect_from_host()
				return false
			var input := client.input as PackedByteArray
			input.append_array(read[1])
			client.input = input
			var response := _parse_request(input, int(client.created), true)
			if not response.is_empty():
				if bool(response.get("upgrade", false)):
					_queue_websocket_handshake(client, String(response.get("key", "")))
				else:
					_queue_response(client, response)
	if bool(client.responding):
		var output := client.output as PackedByteArray
		var offset := int(client.offset)
		var sent := peer.put_partial_data(output.slice(offset, mini(offset + IO_CHUNK_BYTES, output.size())))
		if sent[0] != OK:
			peer.disconnect_from_host()
			return false
		client.offset = offset + int(sent[1])
		if int(client.offset) >= output.size():
			if bool(client.upgrading):
				client.mode = "websocket"
				client.upgrading = false
				client.responding = false
				client.output = PackedByteArray()
				client.offset = 0
				return true
			peer.disconnect_from_host()
			return false
	return true


func handle_http_header(raw: String) -> Dictionary:
	return _parse_request(raw.to_utf8_buffer(), Time.get_ticks_msec(), false)


func _parse_request(bytes: PackedByteArray, received_at: int, allow_partial: bool) -> Dictionary:
	# Find the ASCII delimiter without decoding a possibly partial UTF-8 body.
	var end := -1
	for index in range(0, mini(bytes.size() - 3, MAX_HEADER_BYTES)):
		if bytes[index] == 13 and bytes[index + 1] == 10 and bytes[index + 2] == 13 and bytes[index + 3] == 10:
			end = index
			break
	if (end < 0 and bytes.size() > MAX_HEADER_BYTES) or end + 4 > MAX_HEADER_BYTES:
		return _failure(431, "HEADERS_TOO_LARGE")
	var header_bytes := bytes.slice(0, end + 4) if end >= 0 else bytes
	if not _valid_header_bytes(header_bytes):
		return _failure(400, "MALFORMED_HTTP")
	if end < 0:
		return {} if allow_partial else _failure(400, "MALFORMED_HTTP")
	var raw := header_bytes.get_string_from_ascii()
	var lines := raw.substr(0, end).split("\r\n")
	var request := lines[0].split(" ", false)
	if request.size() != 3 or request[2] != "HTTP/1.1":
		return _failure(400, "MALFORMED_HTTP")
	var headers := {}
	for index in range(1, lines.size()):
		var colon := lines[index].find(":")
		if colon <= 0:
			return _failure(400, "MALFORMED_HTTP")
		var key := lines[index].substr(0, colon).to_lower()
		if key != key.strip_edges() or headers.has(key):
			return _failure(400, "MALFORMED_HTTP")
		headers[key] = lines[index].substr(colon + 1).strip_edges()
	# Host whitelist prevents DNS rebinding; no browser-origin access or CORS.
	if String(headers.get("host", "")) not in ["127.0.0.1:%d" % _port, "localhost:%d" % _port]:
		return _failure(403, "HOST_NOT_ALLOWED")
	if headers.has("origin"):
		return _failure(403, "ORIGIN_NOT_ALLOWED")
	if request[0] != "GET" and (request[0] != "POST" or not _commands_enabled):
		return _failure(405, "METHOD_NOT_ALLOWED")
	if request[0] == "GET" and (headers.has("transfer-encoding") or String(headers.get("content-length", "0")) != "0" or bytes.size() != end + 4):
		return _failure(400, "BODY_NOT_ALLOWED")
	var path: String = request[1]
	if path.contains("?") or path.contains("%") or path.contains("#") or path.contains(".."):
		return _failure(400, "INVALID_PATH")
	if request[0] == "GET" and path == "/events":
		return _websocket_upgrade(headers)
	if request[0] == "GET":
		return _route(path)
	if path not in ["/commands/set-speed", "/commands/move-player", "/commands/save", "/commands/load"]:
		return _failure(404, "ROUTE_NOT_FOUND")
	if headers.has("transfer-encoding"):
		return _failure(400, "TRANSFER_ENCODING_NOT_ALLOWED")
	var length_text := String(headers.get("content-length", ""))
	if length_text.is_empty() or length_text.length() > 8:
		return _failure(400, "INVALID_CONTENT_LENGTH")
	for character in length_text:
		if character < "0" or character > "9":
			return _failure(400, "INVALID_CONTENT_LENGTH")
	var length := int(length_text)
	if length > MAX_BODY_BYTES:
		return _failure(413, "BODY_TOO_LARGE")
	if String(headers.get("content-type", "")).to_lower() not in ["application/json", "application/json; charset=utf-8"]:
		return _failure(415, "JSON_CONTENT_TYPE_REQUIRED")
	if bytes.size() < end + 4 + length:
		return {} if allow_partial else _failure(400, "INCOMPLETE_BODY")
	if bytes.size() != end + 4 + length:
		return _failure(400, "BODY_LENGTH_MISMATCH")
	var body_bytes := bytes.slice(end + 4)
	var body_text := body_bytes.get_string_from_utf8()
	if body_text.to_utf8_buffer() != body_bytes:
		return _failure(400, "INVALID_JSON")
	var json := JSON.new()
	if json.parse(body_text) != OK or not json.data is Dictionary:
		return _failure(400, "INVALID_JSON")
	match path:
		"/commands/set-speed":
			return _set_speed(json.data, received_at)
		"/commands/move-player":
			return _move_player(json.data, received_at)
		"/commands/save":
			return _save_session(json.data, received_at)
		_:
			return _load_session(json.data, received_at)


func _websocket_upgrade(headers: Dictionary) -> Dictionary:
	var connection_tokens: Array[String] = []
	for value in String(headers.get("connection", "")).to_lower().split(",", false):
		connection_tokens.append(value.strip_edges())
	var key := String(headers.get("sec-websocket-key", ""))
	if (
		String(headers.get("upgrade", "")).to_lower() != "websocket"
		or not connection_tokens.has("upgrade")
		or String(headers.get("sec-websocket-version", "")) != "13"
		or Marshalls.base64_to_raw(key).size() != 16
		or headers.has("sec-websocket-extensions")
		or headers.has("sec-websocket-protocol")
	):
		return _failure(400, "INVALID_WEBSOCKET_UPGRADE")
	return {"upgrade": true, "key": key}


func _queue_websocket_handshake(client: Dictionary, key: String) -> void:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA1)
	hashing.update((key + WEBSOCKET_GUID).to_utf8_buffer())
	var accept := Marshalls.raw_to_base64(hashing.finish())
	client.output = (
		"HTTP/1.1 101 Switching Protocols\r\n"
		+ "Upgrade: websocket\r\n"
		+ "Connection: Upgrade\r\n"
		+ "Sec-WebSocket-Accept: %s\r\n\r\n" % accept
	).to_utf8_buffer()
	client.input = PackedByteArray()
	client.offset = 0
	client.responding = true
	client.upgrading = true


func _poll_websocket_client(client: Dictionary, peer: StreamPeerTCP) -> bool:
	var available := mini(peer.get_available_bytes(), IO_CHUNK_BYTES)
	if available > 0:
		var read := peer.get_partial_data(available)
		if read[0] != OK:
			peer.disconnect_from_host()
			return false
		var input := client.input as PackedByteArray
		input.append_array(read[1])
		client.input = input
		if not _consume_websocket_input(client):
			peer.disconnect_from_host()
			return false
	var output := client.output as PackedByteArray
	if int(client.offset) >= output.size():
		client.output = PackedByteArray()
		output = client.output
		client.offset = 0
		var events := client.events as Array
		if not events.is_empty():
			client.output = _websocket_frame(String(events.pop_front()).to_utf8_buffer(), 1)
			client.events = events
			output = client.output
	if output.is_empty():
		return true
	var offset := int(client.offset)
	var sent := peer.put_partial_data(output.slice(offset, mini(offset + IO_CHUNK_BYTES, output.size())))
	if sent[0] != OK:
		peer.disconnect_from_host()
		return false
	client.offset = offset + int(sent[1])
	return true


func _consume_websocket_input(client: Dictionary) -> bool:
	var input := client.input as PackedByteArray
	while not input.is_empty():
		if input.size() < 2:
			break
		var first := int(input[0])
		var second := int(input[1])
		var opcode := first & 0x0f
		var payload_length := second & 0x7f
		if (first & 0x80) == 0 or (first & 0x70) != 0 or (second & 0x80) == 0 or payload_length > 125:
			return false
		var header_length := 6
		if input.size() < header_length + payload_length:
			break
		var mask := input.slice(2, 6)
		var payload := input.slice(header_length, header_length + payload_length)
		for index in payload.size():
			payload[index] = payload[index] ^ mask[index % 4]
		input = input.slice(header_length + payload_length)
		match opcode:
			8:
				return false
			9:
				if not (client.output as PackedByteArray).is_empty():
					return false
				client.output = _websocket_frame(payload, 10)
				client.offset = 0
			10:
				pass
			_:
				return false
	client.input = input
	return input.size() <= MAX_BODY_BYTES


func _websocket_frame(payload: PackedByteArray, opcode: int) -> PackedByteArray:
	var result := PackedByteArray([0x80 | opcode])
	if payload.size() < 126:
		result.append(payload.size())
	else:
		result.append(126)
		result.append((payload.size() >> 8) & 0xff)
		result.append(payload.size() & 0xff)
	result.append_array(payload)
	return result


func _valid_header_bytes(bytes: PackedByteArray) -> bool:
	for byte in bytes:
		if byte >= 127 or (byte < 32 and byte not in [9, 10, 13]):
			return false
	return true


func _route(path: String) -> Dictionary:
	if _commands_enabled and path.begins_with("/commands/"):
		var command_id := path.trim_prefix("/commands/")
		if not _commands.has(command_id):
			return _failure(404, "COMMAND_NOT_FOUND")
		return _success(_commands[command_id].receipt.duplicate(true))
	if path not in ["/health", "/world/state", "/events/cursor"] and not path.begins_with("/residents/"):
		return _failure(404, "ROUTE_NOT_FOUND")
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var world: Object = context.get("world")
	var ready := is_instance_valid(world) and bool(world.is_running())
	if path == "/health":
		return _success({"bridgeReady": true, "worldReady": ready, "readOnly": not _commands_enabled})
	if not ready:
		return _failure(503, "WORLD_NOT_READY")
	var metadata := _metadata(context, world)
	if path == "/events/cursor":
		# Global to this Bridge instance, including periods without subscribers.
		# Emitted means generated/queued, NOT transmitted or acknowledged by a peer.
		metadata["streamId"] = _nonce
		metadata["lastEmittedEventSequence"] = _event_sequence
		return _success(metadata)
	var identities: Array = world.get_resident_identity_snapshot().get("residents", [])
	if path == "/world/state":
		var residents: Array[Dictionary] = []
		for identity: Dictionary in identities:
			residents.append({"residentId": String(identity.get("residentId", "")), "name": String(identity.get("residentName", ""))})
		var player_avatar := {}
		if world.has_method("get_player_avatar_state"):
			var raw_avatar := world.get_player_avatar_state() as Dictionary
			for key in ["residentId", "name", "currentPlace", "spaceId", "position", "doing", "present"]:
				player_avatar[key] = _json_copy(raw_avatar.get(key))
		metadata.merge({
			"time": _json_copy(world.get_time()), "lifecycle": _json_copy(world.get_lifecycle_state()),
			"simulationSpeed": int(world.get_simulation_speed()), "residents": residents,
			"residentCount": residents.size(), "playerAvatar": player_avatar,
		})
		return _success(metadata)
	var resident_id := path.trim_prefix("/residents/")
	var found := false
	for identity: Dictionary in identities:
		if String(identity.get("residentId", "")) == resident_id:
			found = true
			break
	if not found:
		return _failure(404, "RESIDENT_NOT_FOUND")
	var state: Dictionary = world.get_resident_state(resident_id)
	var resident := {}
	# Never forward memories, model configuration, prompts or full action payloads.
	for key in ["residentId", "name", "currentPlace", "spaceId", "position", "doing", "isPresent"]:
		resident[key] = _json_copy(state.get(key))
	metadata["resident"] = resident
	return _success(metadata)


func _metadata(context: Dictionary, world: Object) -> Dictionary:
	return {
		"sessionId": context.get("sessionId", ""),
		"worldGeneration": "%s:%d:%d" % [_nonce, world.get_instance_id(), world.get_runtime_generation()],
		"stateVersion": int(world.get_world_revision()),
		"capturedAt": Time.get_datetime_string_from_system(true) + "Z",
	}


func _valid_identifier(value: Variant, limit := 128) -> bool:
	if not value is String or value.is_empty() or value.length() > limit:
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character in ["-", "_", ":"]):
			return false
	return true


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _command_replay(command: Dictionary) -> Dictionary:
	var key := String(command.get("idempotencyKey", ""))
	var command_id := String(command.get("commandId", ""))
	if _idempotency.has(key):
		var prior: Dictionary = _commands[_idempotency[key]]
		if prior.command != command:
			return _failure(409, "IDEMPOTENCY_CONFLICT")
		return _success(prior.receipt.duplicate(true))
	if _commands.has(command_id):
		return _failure(409, "COMMAND_ID_CONFLICT")
	return {}


func _command_context(command: Dictionary, received_at: int, max_timeout: int) -> Dictionary:
	if not _integer_in_range(command.expectedStateVersion, 0, 9007199254740991) or not _integer_in_range(command.timeoutMs, 1, max_timeout):
		return {"response": _failure(400, "INVALID_COMMAND_SCHEMA")}
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var world: Object = context.get("world")
	if not is_instance_valid(world) or not world.is_running():
		return {"response": _failure(503, "WORLD_NOT_READY")}
	var metadata := _metadata(context, world)
	if command.expectedSessionId != metadata.sessionId:
		return {"response": _failure(409, "SESSION_CONFLICT")}
	if command.expectedWorldGeneration != metadata.worldGeneration:
		return {"response": _failure(409, "WORLD_GENERATION_CONFLICT")}
	if int(command.expectedStateVersion) != int(metadata.stateVersion):
		return {"response": _failure(409, "STATE_VERSION_CONFLICT")}
	if Time.get_ticks_msec() - received_at >= int(command.timeoutMs):
		return {"response": _failure(408, "COMMAND_TIMEOUT")}
	if _commands.size() >= MAX_COMMANDS:
		return {"response": _failure(503, "COMMAND_CAPACITY_REACHED")}
	return {"context": context, "world": world, "metadata": metadata}


func _set_speed(command: Dictionary, received_at: int) -> Dictionary:
	var fields := ["commandId", "idempotencyKey", "expectedSessionId", "expectedWorldGeneration", "expectedStateVersion", "timeoutMs", "speed"]
	if command.size() != fields.size():
		return _failure(400, "INVALID_COMMAND_SCHEMA")
	for field in fields:
		if not command.has(field):
			return _failure(400, "INVALID_COMMAND_SCHEMA")
	for field in ["commandId", "idempotencyKey", "expectedSessionId", "expectedWorldGeneration"]:
		if not _valid_identifier(command[field]):
			return _failure(400, "INVALID_COMMAND_SCHEMA")
	if not _integer_in_range(command.expectedStateVersion, 0, 9007199254740991) or not _integer_in_range(command.timeoutMs, 1, CLIENT_TIMEOUT_MSEC) or not _integer_in_range(command.speed, 1, 3):
		return _failure(400, "INVALID_COMMAND_SCHEMA")
	# Replay before current version/deadline checks; receipts describe the original execution.
	var replay := _command_replay(command)
	if not replay.is_empty():
		return replay
	var validated := _command_context(command, received_at, CLIENT_TIMEOUT_MSEC)
	if validated.has("response"):
		return validated.response
	var key: String = command.idempotencyKey
	var command_id: String = command.commandId
	var context: Dictionary = validated.context
	var world: Object = validated.world
	# Synchronous main-thread command; no await between validation, execution and receipt.
	var result: Dictionary = world.set_simulation_speed(int(command.speed))
	if not bool(result.get("ok", false)):
		return _failure(409, "WORLD_COMMAND_REJECTED")
	var receipt := _metadata(context, world)
	receipt.merge({"accepted": true, "commandId": command_id, "status": "completed", "result": {
		"simulationSpeed": int(world.get_simulation_speed()), "changed": bool(result.get("changed", false)),
	}})
	_commands[command_id] = {"kind": "set-speed", "command": command.duplicate(true), "receipt": receipt.duplicate(true)}
	_idempotency[key] = command_id
	_emit_command_event(receipt)
	return _success(receipt)


func _move_player(command: Dictionary, received_at: int) -> Dictionary:
	var fields := ["commandId", "idempotencyKey", "expectedSessionId", "expectedWorldGeneration", "expectedStateVersion", "timeoutMs", "spaceId", "targetPosition", "tolerance"]
	if command.size() != fields.size():
		return _failure(400, "INVALID_COMMAND_SCHEMA")
	for field in fields:
		if not command.has(field):
			return _failure(400, "INVALID_COMMAND_SCHEMA")
	for field in ["commandId", "idempotencyKey", "expectedSessionId", "expectedWorldGeneration", "spaceId"]:
		if not _valid_identifier(command[field]):
			return _failure(400, "INVALID_COMMAND_SCHEMA")
	if (
		not command.targetPosition is Array
		or command.targetPosition.size() != 2
		or not _finite_number(command.targetPosition[0])
		or not _finite_number(command.targetPosition[1])
		or not _finite_number(command.tolerance)
		or float(command.tolerance) < 2.0
		or float(command.tolerance) > 64.0
	):
		return _failure(400, "INVALID_COMMAND_SCHEMA")
	var replay := _command_replay(command)
	if not replay.is_empty():
		return replay
	var validated := _command_context(command, received_at, MAX_MOVE_TIMEOUT_MSEC)
	if validated.has("response"):
		return validated.response
	if not _active_move_id.is_empty():
		return _failure(409, "PLAYER_MOVE_BUSY")
	var context: Dictionary = validated.context
	var world: Object = validated.world
	var runtime: Object = context.get("runtime")
	if not is_instance_valid(runtime) or not runtime.has_method("get_avatar_movement_state"):
		return _failure(503, "PLAYER_RUNTIME_NOT_READY")
	var movement := runtime.get_avatar_movement_state() as Dictionary
	if String(movement.get("avatarMode", "")) != "avatar_active" or not bool(movement.get("present", false)):
		return _failure(409, "AVATAR_NOT_ACTIVE")
	if bool(movement.get("paused", false)):
		return _failure(409, "WORLD_PAUSED")
	if not bool(movement.get("movementInputEnabled", false)):
		return _failure(409, "AVATAR_MOVEMENT_BLOCKED")
	if bool(movement.get("transitionActive", false)):
		return _failure(409, "AVATAR_TRANSITION_ACTIVE")
	if command.spaceId != movement.spaceId:
		return _failure(409, "SPACE_CONFLICT")
	var target := Vector2(float(command.targetPosition[0]), float(command.targetPosition[1]))
	var target_result := runtime.validate_virtual_movement_target(String(command.spaceId), target) as Dictionary
	if not bool(target_result.get("ok", false)):
		return _failure(422, String(target_result.get("errorCode", "TARGET_NOT_WALKABLE")))
	var position := movement.get("position", Vector2.ZERO) as Vector2
	var distance := position.distance_to(target)
	var now := Time.get_ticks_msec()
	var receipt: Dictionary = validated.metadata.duplicate(true)
	receipt.merge({
		"accepted": true, "commandId": String(command.commandId), "commandType": "move-player",
		"status": "running", "result": null, "failure": null,
		"progress": {"spaceId": String(command.spaceId), "startPosition": _json_copy(position),
			"currentPosition": _json_copy(position), "targetPosition": _json_copy(target), "distance": distance},
	})
	var record := {
		"kind": "move-player", "command": command.duplicate(true), "receipt": receipt,
		"runtimeInstanceId": runtime.get_instance_id(), "worldInstanceId": world.get_instance_id(),
		"startedAt": now, "deadline": now + int(command.timeoutMs), "lastProgressAt": now,
		"bestDistance": distance, "target": target, "tolerance": float(command.tolerance),
	}
	_commands[command.commandId] = record
	_idempotency[command.idempotencyKey] = command.commandId
	if distance <= float(command.tolerance):
		_active_move_id = String(command.commandId)
		_finish_move_success(position, false)
		return _success(_commands[command.commandId].receipt.duplicate(true))
	_active_move_id = String(command.commandId)
	runtime.set_virtual_movement_input((target - position).normalized())
	return _success(receipt.duplicate(true), 202)


func _save_session(command: Dictionary, received_at: int) -> Dictionary:
	var validation := _validate_session_command(command, received_at)
	if validation.has("response"):
		return validation.response
	if not _active_session_command_id.is_empty():
		return _failure(409, "SESSION_COMMAND_BUSY")
	var context: Dictionary = validation.context
	var host: Object = context.get("flowHost")
	if not is_instance_valid(host) or not host.has_method("gametest_begin_save"):
		return _failure(503, "SESSION_SAVE_SERVICE_NOT_READY")
	var started := host.gametest_begin_save() as Dictionary
	if not bool(started.get("ok", false)):
		return _failure(
			503 if bool(started.get("retryable", false)) else 409,
			String(started.get("errorCode", "SESSION_SAVE_REJECTED")),
		)
	var receipt: Dictionary = validation.metadata.duplicate(true)
	receipt.merge({
		"accepted": true,
		"commandId": String(command.commandId),
		"commandType": "save",
		"status": "running",
		"result": null,
		"failure": null,
	})
	var record := {
		"kind": "save",
		"command": command.duplicate(true),
		"receipt": receipt,
		"flowHostInstanceId": host.get_instance_id(),
		"deadline": Time.get_ticks_msec() + int(command.timeoutMs),
	}
	_commands[command.commandId] = record
	_idempotency[command.idempotencyKey] = command.commandId
	_active_session_command_id = String(command.commandId)
	if not bool(started.get("pending", true)):
		_finish_session_from_save(started)
	return _success((_commands[command.commandId].receipt as Dictionary).duplicate(true), 202)


func _load_session(command: Dictionary, received_at: int) -> Dictionary:
	var validation := _validate_session_command(command, received_at)
	if validation.has("response"):
		return validation.response
	if not _active_session_command_id.is_empty():
		return _failure(409, "SESSION_COMMAND_BUSY")
	var context: Dictionary = validation.context
	var host: Object = context.get("flowHost")
	if not is_instance_valid(host) or not host.has_method("gametest_begin_load"):
		return _failure(503, "SESSION_LOAD_SERVICE_NOT_READY")
	var started := host.gametest_begin_load(String(command.commandId)) as Dictionary
	if not bool(started.get("ok", false)):
		return _failure(
			503 if bool(started.get("retryable", false)) else 409,
			String(started.get("errorCode", "SESSION_LOAD_REJECTED")),
		)
	if not _active_move_id.is_empty():
		_finish_move_failure("COMMAND_INVALIDATED_BY_LOAD")
	var receipt: Dictionary = validation.metadata.duplicate(true)
	receipt.merge({
		"accepted": true,
		"commandId": String(command.commandId),
		"commandType": "load",
		"status": "running",
		"result": null,
		"failure": null,
	})
	var record := {
		"kind": "load",
		"command": command.duplicate(true),
		"receipt": receipt,
		"flowHostInstanceId": host.get_instance_id(),
		"deadline": Time.get_ticks_msec() + int(command.timeoutMs),
		"slotId": String(started.get("slotId", "")),
		"saveRevision": int(started.get("saveRevision", 0)),
	}
	_commands[command.commandId] = record
	_idempotency[command.idempotencyKey] = command.commandId
	_active_session_command_id = String(command.commandId)
	return _success(receipt.duplicate(true), 202)


func _validate_session_command(command: Dictionary, received_at: int) -> Dictionary:
	var fields := ["commandId", "idempotencyKey", "expectedSessionId", "expectedWorldGeneration", "expectedStateVersion", "timeoutMs"]
	if command.size() != fields.size():
		return {"response": _failure(400, "INVALID_COMMAND_SCHEMA")}
	for field in fields:
		if not command.has(field):
			return {"response": _failure(400, "INVALID_COMMAND_SCHEMA")}
	for field in ["commandId", "idempotencyKey", "expectedSessionId", "expectedWorldGeneration"]:
		if not _valid_identifier(command[field]):
			return {"response": _failure(400, "INVALID_COMMAND_SCHEMA")}
	if (
		not _integer_in_range(command.expectedStateVersion, 0, 9007199254740991)
		or not _integer_in_range(command.timeoutMs, 1, MAX_SESSION_TIMEOUT_MSEC)
	):
		return {"response": _failure(400, "INVALID_COMMAND_SCHEMA")}
	var replay := _command_replay(command)
	if not replay.is_empty():
		return {"response": replay}
	return _command_context(command, received_at, MAX_SESSION_TIMEOUT_MSEC)


func _advance_session_command() -> void:
	if _active_session_command_id.is_empty() or not _commands.has(_active_session_command_id):
		return
	var record: Dictionary = _commands[_active_session_command_id]
	if Time.get_ticks_msec() >= int(record.deadline):
		_finish_session_failure("SESSION_COMMAND_TIMEOUT")
		return
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var host: Object = context.get("flowHost")
	if not is_instance_valid(host) or host.get_instance_id() != int(record.flowHostInstanceId):
		_finish_session_failure("SESSION_CONTEXT_LOST")
		return
	if String(record.kind) == "save":
		var save_result := host.gametest_poll_save() as Dictionary
		if bool(save_result.get("pending", false)):
			return
		_finish_session_from_save(save_result)
		return
	var load_result := host.gametest_poll_load(_active_session_command_id) as Dictionary
	if not bool(load_result.get("ok", false)):
		_finish_session_failure(String(load_result.get("errorCode", "SESSION_LOAD_FAILED")))
		return
	var operation := load_result.get("operation", {}) as Dictionary
	match String(operation.get("status", "")):
		"completed":
			var world: Object = context.get("world")
			if not is_instance_valid(world) or not bool(world.is_running()):
				return
			_finish_session_success({
				"slotId": String(operation.get("slotId", record.get("slotId", ""))),
				"sessionId": String(operation.get("sessionId", "")),
				"saveRevision": int(operation.get("saveRevision", record.get("saveRevision", 0))),
				"worldGeneration": String(_metadata(context, world).worldGeneration),
			})
		"failed":
			var failure := operation.get("failure", {}) as Dictionary
			_finish_session_failure(String(failure.get("code", "SESSION_LOAD_FAILED")))


func _finish_session_from_save(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_finish_session_failure(String(result.get("errorCode", "SESSION_SAVE_FAILED")))
		return
	var context := result.get("context", {}) as Dictionary
	var manifest := result.get("manifest", {}) as Dictionary
	_finish_session_success({
		"slotId": String(context.get("slot_id", manifest.get("slot_id", ""))),
		"sessionId": String(context.get("session_id", manifest.get("session_id", ""))),
		"saveRevision": int(context.get("save_revision", manifest.get("save_revision", 0))),
	})


func _finish_session_success(result: Dictionary) -> void:
	var command_id := _active_session_command_id
	var record := _commands.get(command_id, {}) as Dictionary
	if record.is_empty():
		_active_session_command_id = ""
		return
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var world: Object = context.get("world")
	var receipt := record.receipt as Dictionary
	if is_instance_valid(world) and bool(world.is_running()):
		receipt.merge(_metadata(context, world), true)
	receipt.status = "completed"
	receipt.result = result.duplicate(true)
	record.receipt = receipt
	_commands[command_id] = record
	_active_session_command_id = ""
	_emit_command_event(receipt)


func _finish_session_failure(code: String) -> void:
	var command_id := _active_session_command_id
	var record := _commands.get(command_id, {}) as Dictionary
	if record.is_empty():
		_active_session_command_id = ""
		return
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var world: Object = context.get("world")
	var receipt := record.receipt as Dictionary
	if is_instance_valid(world) and bool(world.is_running()):
		receipt.merge(_metadata(context, world), true)
	receipt.status = "failed"
	receipt.failure = {"code": code, "message": code}
	record.receipt = receipt
	_commands[command_id] = record
	_active_session_command_id = ""
	_emit_command_event(receipt)


func _advance_move_command() -> void:
	if _active_move_id.is_empty() or not _commands.has(_active_move_id):
		return
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var world: Object = context.get("world")
	var runtime: Object = context.get("runtime")
	var record: Dictionary = _commands[_active_move_id]
	if (
		not is_instance_valid(world)
		or not world.is_running()
		or world.get_instance_id() != int(record.worldInstanceId)
		or not is_instance_valid(runtime)
		or runtime.get_instance_id() != int(record.runtimeInstanceId)
	):
		_finish_move_failure("MOVEMENT_CONTEXT_LOST")
		return
	var expected_metadata: Dictionary = record.receipt
	var current_metadata := _metadata(context, world)
	if current_metadata.sessionId != expected_metadata.sessionId or current_metadata.worldGeneration != expected_metadata.worldGeneration:
		_finish_move_failure("MOVEMENT_CONTEXT_LOST")
		return
	var movement := runtime.get_avatar_movement_state() as Dictionary
	if bool(movement.get("paused", false)):
		_finish_move_failure("WORLD_PAUSED")
		return
	if String(movement.get("avatarMode", "")) != "avatar_active" or not bool(movement.get("present", false)):
		_finish_move_failure("AVATAR_NOT_ACTIVE")
		return
	if not bool(movement.get("movementInputEnabled", false)):
		_finish_move_failure("AVATAR_MOVEMENT_BLOCKED")
		return
	if bool(movement.get("transitionActive", false)) or String(movement.get("spaceId", "")) != String(record.command.spaceId):
		_finish_move_failure("SPACE_OR_TRANSITION_CHANGED")
		return
	var position := movement.get("position", Vector2.ZERO) as Vector2
	var target := record.target as Vector2
	var distance := position.distance_to(target)
	var now := Time.get_ticks_msec()
	if distance <= float(record.tolerance):
		_finish_move_success(position, true)
		return
	if now >= int(record.deadline):
		_finish_move_failure("MOVE_TIMEOUT", position)
		return
	if distance + MOVE_PROGRESS_EPSILON < float(record.bestDistance):
		record.bestDistance = distance
		record.lastProgressAt = now
	elif now - int(record.lastProgressAt) >= MOVE_STALL_TIMEOUT_MSEC:
		_finish_move_failure("MOVE_BLOCKED", position)
		return
	var receipt := record.receipt as Dictionary
	receipt.stateVersion = int(world.get_world_revision())
	receipt.capturedAt = Time.get_datetime_string_from_system(true) + "Z"
	receipt.progress.currentPosition = _json_copy(position)
	receipt.progress.distance = distance
	record.receipt = receipt
	_commands[_active_move_id] = record
	runtime.set_virtual_movement_input((target - position).normalized())


func _finish_move_success(position: Vector2, changed: bool) -> void:
	var command_id := _active_move_id
	var record: Dictionary = _commands.get(command_id, {})
	if record.is_empty():
		_active_move_id = ""
		return
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var runtime: Object = context.get("runtime")
	if is_instance_valid(runtime) and runtime.has_method("stop_virtual_movement_and_sync"):
		runtime.stop_virtual_movement_and_sync()
	var world: Object = context.get("world")
	var receipt: Dictionary = record.receipt
	if is_instance_valid(world):
		receipt.merge(_metadata(context, world), true)
	receipt.status = "completed"
	receipt.progress.currentPosition = _json_copy(position)
	receipt.progress.distance = position.distance_to(record.target as Vector2)
	receipt.result = {"spaceId": String(record.command.spaceId), "position": _json_copy(position),
		"targetPosition": _json_copy(record.target), "tolerance": float(record.tolerance), "changed": changed}
	record.receipt = receipt
	_commands[command_id] = record
	_active_move_id = ""
	_emit_command_event(receipt)


func _finish_move_failure(code: String, position := Vector2.INF) -> void:
	var command_id := _active_move_id
	var record: Dictionary = _commands.get(command_id, {})
	if record.is_empty():
		_active_move_id = ""
		return
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var runtime: Object = context.get("runtime")
	if is_instance_valid(runtime) and runtime.has_method("stop_virtual_movement_and_sync"):
		runtime.stop_virtual_movement_and_sync()
	var world: Object = context.get("world")
	var receipt: Dictionary = record.receipt
	if is_instance_valid(world):
		receipt.merge(_metadata(context, world), true)
	if position.is_finite():
		receipt.progress.currentPosition = _json_copy(position)
		receipt.progress.distance = position.distance_to(record.target as Vector2)
	receipt.status = "failed"
	receipt.failure = {"code": code, "message": code}
	record.receipt = receipt
	_commands[command_id] = record
	_active_move_id = ""
	_emit_command_event(receipt)


func _observe_state_version() -> void:
	var context: Dictionary = _context_provider.call() if _context_provider.is_valid() else {}
	var world: Object = context.get("world")
	if not is_instance_valid(world) or not bool(world.is_running()):
		return
	var current := _metadata(context, world)
	if _last_observed_state.is_empty():
		_last_observed_state = current
		return
	if (
		String(current.worldGeneration) == String(_last_observed_state.worldGeneration)
		and int(current.stateVersion) == int(_last_observed_state.stateVersion)
	):
		return
	var event := current.duplicate(true)
	event["eventType"] = "state-version-changed"
	event["previousWorldGeneration"] = String(_last_observed_state.worldGeneration)
	event["previousStateVersion"] = int(_last_observed_state.stateVersion)
	_last_observed_state = current
	_emit_event(event)


func _emit_command_event(receipt: Dictionary) -> void:
	var status := String(receipt.get("status", ""))
	if status not in ["completed", "failed"]:
		return
	var event := {"result": null, "failure": null}
	for key in ["sessionId", "worldGeneration", "stateVersion", "capturedAt", "commandId", "commandType", "result", "failure"]:
		if receipt.has(key):
			event[key] = _json_copy(receipt.get(key))
	if not event.has("commandType") or not event.commandType is String or event.commandType.is_empty():
		event["commandType"] = "set-speed"
	event["eventType"] = "command-completed" if status == "completed" else "command-failed"
	_emit_event(event)


func _emit_event(event: Dictionary) -> void:
	_event_sequence += 1
	var envelope := event.duplicate(true)
	envelope["protocolVersion"] = "0.1"
	envelope["eventSequence"] = _event_sequence
	envelope["eventId"] = "%s-event-%d" % [_nonce, _event_sequence]
	var encoded := JSON.stringify(envelope)
	for client in _clients:
		if String(client.get("mode", "")) != "websocket":
			continue
		var events := client.events as Array
		if events.size() >= MAX_EVENT_QUEUE:
			client.closing = true
			continue
		events.append(encoded)
		client.events = events


func _json_copy(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i:
		return [value.x, value.y]
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[String(key)] = _json_copy(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_json_copy(item))
		return result
	if value == null or value is String or value is bool or value is int:
		return value
	if value is float and is_finite(value):
		return value
	return null


func _success(data: Dictionary, status := 200) -> Dictionary:
	return _response(status, data, null)


func _failure(status: int, code: String) -> Dictionary:
	return _response(status, null, {"code": code, "message": code})


func _response(status: int, data: Variant, error: Variant) -> Dictionary:
	_sequence += 1
	return {"status": status, "body": {
		"protocolVersion": "0.1", "requestId": "%s-%d" % [_nonce, _sequence],
		"ok": status >= 200 and status < 300, "data": data, "error": error,
	}}


func _queue_response(client: Dictionary, response: Dictionary) -> void:
	var body := JSON.stringify(response.body).to_utf8_buffer()
	if body.size() > MAX_RESPONSE_BYTES:
		response = _failure(503, "SNAPSHOT_TOO_LARGE")
		body = JSON.stringify(response.body).to_utf8_buffer()
	var header := "HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n" % [
		int(response.status), ("Accepted" if int(response.status) == 202 else ("OK" if int(response.status) == 200 else "Error")), body.size(),
	]
	if int(response.status) == 405:
		header += "Allow: GET, POST\r\n" if _commands_enabled else "Allow: GET\r\n"
	var output := (header + "\r\n").to_utf8_buffer()
	output.append_array(body)
	client.output = output
	client.input = PackedByteArray()
	client.responding = true
