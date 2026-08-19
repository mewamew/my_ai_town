class_name OpenAICompatibleModelProvider
extends "res://agent/model/ModelProvider.gd"


const AgentJsonScript := preload("res://agent/AgentJson.gd")
const ENDPOINT_SECURITY := preload(
	"res://common/ProviderEndpointSecurity.gd"
)

const LOCAL_ENV_FILE := ".tmp/.env"
const DEFAULT_TIMEOUT_SECONDS := 30.0
const DEFAULT_MAX_TOKENS := 1024
# 调试记录含完整请求/响应（系统提示词 + wake packet 副本），每居民常驻。
# 默认只留最近几条排障用；调试场景可通过 config.record_limit 调高。
const DEFAULT_RECORD_LIMIT := 4

var _request_host: Node
var _transport: Object
var _config: Dictionary
var _model_requests: Array[Dictionary] = []
var _requests: Array[Dictionary] = []
var _responses: Array[Dictionary] = []
var _diagnostics: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _active_requests: Dictionary = {}
var _request_sequence := 0
var _env_file_cache: Dictionary = {}


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	_request_host = request_host
	_transport = transport
	_config = config.duplicate(true)


func get_provider_descriptor() -> Dictionary:
	return {
		"id": _provider_id(),
		"label": _provider_label(),
		"transport_label": _transport_label(),
		"external": true,
		"model_id": String(_config.get("model", _default_model())),
		"input_modalities": _configured_input_modalities(),
	}


func validate_configuration() -> Array[String]:
	var endpoint := String(_config.get("endpoint", _default_endpoint())).strip_edges()
	if not endpoint.is_empty() and not ENDPOINT_SECURITY.scheme_is_supported(endpoint):
		return ["Provider 地址格式无效"]
	if not _insecure_http_transport_is_allowed():
		return ["远程 HTTP 地址尚未获得未加密传输授权"]
	if _api_key_required() and _resolve_api_key().is_empty():
		return [_missing_api_key_message(true)]
	return []


func _insecure_http_transport_is_allowed() -> bool:
	var endpoint := String(_config.get("endpoint", _default_endpoint())).strip_edges()
	if not ENDPOINT_SECURITY.requires_insecure_http_consent(endpoint):
		return true
	var consent_value: Variant = _config.get("allow_insecure_http", false)
	return typeof(consent_value) == TYPE_BOOL and bool(consent_value)


func get_model_requests() -> Array[Dictionary]:
	return _model_requests.duplicate(true)


func get_requests() -> Array[Dictionary]:
	return _requests.duplicate(true)


func get_responses() -> Array[Dictionary]:
	return _responses.duplicate(true)


func get_diagnostics() -> Array[Dictionary]:
	return _diagnostics.duplicate(true)


func get_results() -> Array[Dictionary]:
	return _results.duplicate(true)


func request_decision(model_request: Dictionary, on_complete: Callable) -> void:
	var recorded_model_request := model_request.duplicate(true)
	_retain_record(_model_requests, recorded_model_request)
	var request_errors := _validate_model_request(recorded_model_request)
	if not request_errors.is_empty():
		_complete_failure(
			on_complete,
			request_errors,
			{"error_type": "request_validation", "retryable": false},
		)
		return
	var configuration_errors := validate_configuration()
	if not configuration_errors.is_empty():
		_complete_failure(
			on_complete,
			configuration_errors,
			{"error_type": "configuration", "retryable": false},
		)
		return
	var api_key := _resolve_api_key()
	var body := _build_request_body(recorded_model_request)
	var endpoint := String(_config.get("endpoint", _default_endpoint()))
	var recorded_request := {"url": endpoint, "body": body}
	_retain_record(_requests, recorded_request)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	if not api_key.is_empty():
		headers.append("Authorization: Bearer %s" % api_key)
	var started_at := Time.get_ticks_msec()
	var request_id := String(
		recorded_model_request.get("_agent_request_id", "")
	).strip_edges()
	if request_id.is_empty():
		# 退出留言等结构化请求可能没有决策编号，也必须纳入会话级清理。
		_request_sequence += 1
		request_id = "__provider_request_%d" % _request_sequence
	var request_state := _begin_active_request(request_id)
	var settled := request_state.get("settled", {}) as Dictionary
	# transport 回复、请求启动失败、看门狗超时和主动取消竞争同一个
	# 结算状态：只有第一个占位者能写历史并回调，迟到的回复直接丢弃。
	var settle_response := func(response: Dictionary) -> void:
		if settled["done"]:
			return
		settled["done"] = true
		# settle_failure 会捕获 request_state；结算后必须断开 state -> closure
		# 的引用，否则同步 transport 会留下 RefCounted 循环引用。
		request_state["settleFailure"] = Callable()
		_clear_watchdog(request_state)
		_end_active_request(request_id, request_state)
		_handle_transport_result(
			response,
			on_complete,
			started_at,
			recorded_request,
		)
	var settle_failure := func(errors: Array, diagnostics: Dictionary) -> void:
		if settled["done"]:
			return
		settled["done"] = true
		request_state["settleFailure"] = Callable()
		_clear_watchdog(request_state)
		_end_active_request(request_id, request_state)
		_complete_failure(on_complete, errors, diagnostics)
	request_state["settleFailure"] = settle_failure
	if _transport != null:
		var error: int = _transport.call(
			"request_json",
			endpoint,
			headers,
			body.duplicate(true),
			settle_response,
		)
		if error != OK:
			settle_failure.call(
				["模型请求未能启动：%s" % error_string(error)],
				{"error_type": "request_start", "retryable": false, "request": recorded_request},
			)
			return
		# 某些注入 transport 会同步回调；请求已经结算时不能再创建 watchdog。
		if bool(settled.get("done", false)):
			return
		_start_transport_watchdog(settle_failure, recorded_request, request_state)
		return
	_request_with_godot_http(
		endpoint,
		headers,
		body,
		recorded_request,
		request_state,
		settle_response,
		settle_failure,
	)


func cancel_request(request_id: String) -> bool:
	var normalized_request_id := request_id.strip_edges()
	if normalized_request_id.is_empty():
		return false
	var request_state := _active_requests.get(normalized_request_id, {}) as Dictionary
	if request_state.is_empty():
		return false
	var settled := request_state.get("settled", {}) as Dictionary
	if bool(settled.get("done", false)):
		return false
	var settle_failure := request_state.get("settleFailure", Callable()) as Callable
	if not settle_failure.is_valid():
		return false
	# 先结算上层，避免 transport 的同步取消回调抢先写入普通失败；
	# 之后再停止 HTTPRequest 或通知注入 transport。
	settle_failure.call(
		["模型请求已取消"],
		{
			"error_type": "cancelled",
			"retryable": false,
			"cancelled": true,
		},
	)
	var http_request_value: Variant = request_state.get("httpRequest")
	if http_request_value is HTTPRequest and is_instance_valid(http_request_value):
		var http_request := http_request_value as HTTPRequest
		http_request.cancel_request()
		http_request.queue_free()
	var transport := _transport
	if transport != null and transport.has_method("cancel_request"):
		transport.call("cancel_request", normalized_request_id)
	return true


func cancel_all_requests() -> int:
	var request_ids: Array[String] = []
	for request_id_value: Variant in _active_requests.keys():
		request_ids.append(String(request_id_value))
	var cancelled_count := 0
	for request_id: String in request_ids:
		if cancel_request(request_id):
			cancelled_count += 1
	return cancelled_count


func _begin_active_request(request_id: String) -> Dictionary:
	var request_state := {
		"settled": {"done": false},
		"httpRequest": null,
		"watchdogTimer": null,
		"settleFailure": Callable(),
	}
	if not request_id.is_empty():
		_active_requests[request_id] = request_state
	return request_state


func _end_active_request(request_id: String, request_state: Dictionary) -> void:
	if request_id.is_empty():
		return
	if _active_requests.get(request_id, {}) == request_state:
		_active_requests.erase(request_id)


func _clear_watchdog(request_state: Dictionary) -> void:
	var timer_value: Variant = request_state.get("watchdogTimer")
	if timer_value is Timer and is_instance_valid(timer_value):
		var timer := timer_value as Timer
		timer.stop()
		# timeout 信号回调期间对象处于锁定状态，必须延迟释放；同步
		# transport 已完成时不会创建 watchdog，因此不会留下未处理的节点。
		timer.queue_free()
	request_state["watchdogTimer"] = null


func _build_request_body(model_request: Dictionary) -> Dictionary:
	var body := {
		"model": String(_config.get("model", _default_model())),
		"messages": model_request["messages"],
		"max_tokens": int(model_request.get(
			"max_tokens",
			_config.get("max_tokens", _default_max_tokens()),
		)),
		"stream": false,
	}
	var provider_options := _provider_request_options()
	for key: Variant in provider_options:
		body[key] = provider_options[key]
	return body


func _validate_model_request(model_request: Dictionary) -> Array[String]:
	var messages: Variant = model_request.get("messages")
	if typeof(messages) != TYPE_ARRAY or (messages as Array).is_empty():
		return ["模型请求必须包含非空 messages 数组"]
	if _messages_contain_image(messages as Array) and "image" not in _configured_input_modalities():
		return ["当前模型未声明 image 输入能力"]
	return []


func _configured_input_modalities() -> Array:
	var configured: Variant = _config.get("input_modalities", ["text"])
	if typeof(configured) != TYPE_ARRAY:
		return ["text"]
	return (configured as Array).duplicate()


func _messages_contain_image(messages: Array) -> bool:
	for message_value: Variant in messages:
		if typeof(message_value) != TYPE_DICTIONARY:
			continue
		var content: Variant = (message_value as Dictionary).get("content")
		if typeof(content) != TYPE_ARRAY:
			continue
		for part_value: Variant in content:
			if typeof(part_value) != TYPE_DICTIONARY:
				continue
			if String((part_value as Dictionary).get("type", "")) == "image_url":
				return true
	return false


func _default_max_tokens() -> int:
	return DEFAULT_MAX_TOKENS


func _resolve_api_key() -> String:
	var configured_key := String(_config.get("api_key", "")).strip_edges()
	if not configured_key.is_empty():
		return configured_key
	for environment_name: String in _api_key_environment_names():
		var environment_key := OS.get_environment(environment_name).strip_edges()
		if not environment_key.is_empty():
			return environment_key
	var env_file_path := String(_config.get("env_file_path", _local_env_file_path()))
	for environment_name: String in _api_key_environment_names():
		var file_key := _read_env_value(env_file_path, environment_name)
		if not file_key.is_empty():
			return file_key
	return ""


func _local_env_file_path() -> String:
	var game_directory := ProjectSettings.globalize_path("res://").trim_suffix("/")
	return game_directory.get_base_dir().path_join(LOCAL_ENV_FILE)


func _read_env_value(path: String, key: String) -> String:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return ""
	var modified_at := FileAccess.get_modified_time(path)
	var cached: Variant = _env_file_cache.get(path)
	if (
		typeof(cached) == TYPE_DICTIONARY
		and int((cached as Dictionary).get("modified_at", -1)) == modified_at
	):
		return String(((cached as Dictionary).get("values", {}) as Dictionary).get(key, ""))
	var values := _parse_env_file(path)
	_env_file_cache[path] = {"modified_at": modified_at, "values": values}
	return String(values.get(key, ""))


func _parse_env_file(path: String) -> Dictionary:
	var values := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return values
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("export "):
			line = line.trim_prefix("export ").strip_edges()
		var separator := line.find("=")
		if separator <= 0:
			continue
		var entry_key := line.left(separator).strip_edges()
		var value := line.substr(separator + 1).strip_edges()
		if value.length() >= 2:
			var first_character := value.left(1)
			var last_character := value.right(1)
			if (first_character == "\"" and last_character == "\"") or (first_character == "'" and last_character == "'"):
				value = value.substr(1, value.length() - 2)
		if not values.has(entry_key):
			values[entry_key] = value.strip_edges()
	return values


func _start_transport_watchdog(
	settle_failure: Callable,
	recorded_request: Dictionary,
	request_state: Dictionary,
) -> void:
	# 注入 transport 不经过 HTTPRequest 的超时机制；宿主可用时补一个超时兜底，
	# 防止回调永不到达导致上游永远等待。结算唯一性由 settle_failure 内部
	# 的结算状态保证。
	# 限定：生产 Provider 由 ModelProviderCatalog 提供有效的场景树宿主；
	# request_host 为 null 或不在树内时（部分测试注入场景），注入 transport
	# 不具备异步超时能力。如需把无宿主注入定义为完整公共接口，应另行
	# 解决无宿主超时，而不是在这里引入线程或全局定时器。
	if _request_host == null or not is_instance_valid(_request_host):
		return
	if not _request_host.is_inside_tree():
		return
	var timeout_seconds := float(_config.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS))
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = timeout_seconds
	_request_host.add_child(timer)
	request_state["watchdogTimer"] = timer
	timer.timeout.connect(func() -> void:
		settle_failure.call(
			["模型请求超时：transport 超过 %s 秒未回复" % timeout_seconds],
			{
				"error_type": "timeout",
				"retryable": true,
				"request": recorded_request,
			},
		)
	)
	timer.start()


func _request_with_godot_http(
	endpoint: String,
	headers: PackedStringArray,
	body: Dictionary,
	recorded_request: Dictionary,
	request_state: Dictionary,
	settle_response: Callable,
	settle_failure: Callable,
) -> void:
	if _request_host == null or not is_instance_valid(_request_host):
		settle_failure.call(
			["%s 需要有效的 HTTPRequest 宿主节点" % _provider_label()],
			{"error_type": "configuration", "retryable": false},
		)
		return
	var http_request := HTTPRequest.new()
	http_request.timeout = float(_config.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS))
	var system_ca_pem := OS.get_system_ca_certificates()
	if not system_ca_pem.is_empty():
		var system_ca := X509Certificate.new()
		if system_ca.load_from_string(system_ca_pem) == OK:
			http_request.set_tls_options(TLSOptions.client(system_ca))
	_request_host.add_child(http_request)
	request_state["httpRequest"] = http_request
	http_request.request_completed.connect(
		_on_http_request_completed.bind(http_request, settle_response),
		CONNECT_ONE_SHOT,
	)
	var error := http_request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		http_request.queue_free()
		request_state["httpRequest"] = null
		settle_failure.call(
			["模型请求未能启动：%s" % error_string(error)],
			{"error_type": "request_start", "retryable": false},
		)


func _on_http_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	settle_response: Callable,
) -> void:
	if is_instance_valid(http_request):
		http_request.queue_free()
	settle_response.call(
		{
			"result": result,
			"status_code": response_code,
			"headers": headers,
			"body": body,
		},
	)


func _handle_transport_result(
	response: Dictionary,
	on_complete: Callable,
	started_at: int,
	recorded_request: Dictionary,
) -> void:
	var elapsed_ms := Time.get_ticks_msec() - started_at
	var result := int(response.get("result", HTTPRequest.RESULT_REQUEST_FAILED))
	var status_code := int(response.get("status_code", 0))
	var body_bytes: PackedByteArray = response.get("body", PackedByteArray())
	var body_text := body_bytes.get_string_from_utf8()
	var decoded: Variant = null
	var raw_response := {"body": body_text}
	if result == HTTPRequest.RESULT_SUCCESS:
		decoded = AgentJsonScript.normalize_numbers(JSON.parse_string(body_text))
		raw_response = (
			decoded
			if typeof(decoded) == TYPE_DICTIONARY
			else {"body": body_text}
		)
	_retain_record(_responses, raw_response)
	var diagnostics := {
		"provider": _provider_id(),
		"model": String(_config.get("model", _default_model())),
		"status_code": status_code,
		"elapsed_ms": elapsed_ms,
		"request": recorded_request,
		"raw_response": raw_response,
		"retryable": false,
	}
	if result != HTTPRequest.RESULT_SUCCESS:
		diagnostics["error_type"] = _transport_error_type(result)
		diagnostics["retryable"] = result in [HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE]
		_complete_failure(on_complete, ["模型网络请求失败：%s" % _transport_error_text(result)], diagnostics)
		return
	if status_code < 200 or status_code >= 300:
		diagnostics["error_type"] = _http_error_type(status_code, raw_response)
		diagnostics["retryable"] = _http_error_retryable(status_code, raw_response)
		var provider_code := _provider_error_code(raw_response)
		if not provider_code.is_empty():
			diagnostics["provider_error_code"] = provider_code
		var provider_message := _provider_error_message(raw_response)
		diagnostics["provider_error_message"] = provider_message
		var message := "模型服务返回 HTTP %d" % status_code
		if not provider_message.is_empty():
			message += "：%s" % provider_message
		_complete_failure(on_complete, [message], diagnostics)
		return
	if typeof(decoded) != TYPE_DICTIONARY:
		diagnostics["error_type"] = "invalid_response_json"
		_complete_failure(on_complete, ["模型服务返回的内容不是合法 JSON 对象"], diagnostics)
		return
	var choices: Variant = raw_response.get("choices")
	if typeof(choices) != TYPE_ARRAY or (choices as Array).is_empty():
		diagnostics["error_type"] = "missing_choice"
		_complete_failure(on_complete, ["模型回答缺少 choices"], diagnostics)
		return
	var choice: Variant = (choices as Array)[0]
	if typeof(choice) != TYPE_DICTIONARY:
		diagnostics["error_type"] = "invalid_choice"
		_complete_failure(on_complete, ["模型回答的 choice 不是对象"], diagnostics)
		return
	var choice_data := choice as Dictionary
	diagnostics["finish_reason"] = String(choice_data.get("finish_reason", ""))
	if diagnostics["finish_reason"] == "length":
		diagnostics["error_type"] = "output_truncated"
		_complete_failure(on_complete, ["模型回答因达到输出上限而被截断"], diagnostics)
		return
	var usage: Variant = raw_response.get("usage")
	diagnostics["usage"] = usage if typeof(usage) == TYPE_DICTIONARY else {}
	var message_value: Variant = choice_data.get("message")
	if typeof(message_value) != TYPE_DICTIONARY:
		diagnostics["error_type"] = "missing_message"
		_complete_failure(on_complete, ["模型回答缺少 message"], diagnostics)
		return
	var message := message_value as Dictionary
	var raw_content := _response_text(message.get("content", ""))
	var reasoning_content := _reasoning_text(choice_data, message)
	diagnostics["raw_content"] = raw_content
	diagnostics["content_length"] = raw_content.length()
	diagnostics["content_present"] = not raw_content.is_empty()
	diagnostics["reasoning_present"] = not reasoning_content.is_empty()
	diagnostics["reasoning_length"] = reasoning_content.length()
	if raw_content.is_empty():
		diagnostics["error_type"] = (
			"reasoning_only_response"
			if not reasoning_content.is_empty()
			else "empty_content"
		)
		_complete_failure(
			on_complete,
			[
				(
					"模型只返回了思考内容，没有返回居民动作 JSON"
					if not reasoning_content.is_empty()
					else "模型返回了空回答"
				),
			],
			diagnostics,
		)
		return
	var cleaned_content := _strip_thinking_blocks(raw_content)
	diagnostics["thinking_block_removed"] = bool(cleaned_content.get("removed", false))
	var content := String(cleaned_content.get("text", "")).strip_edges()
	diagnostics["parse_content_length"] = content.length()
	if content.is_empty():
		diagnostics["error_type"] = "thinking_only_content"
		_complete_failure(
			on_complete,
			["模型只返回了思考内容，没有返回居民动作 JSON"],
			diagnostics,
		)
		return
	var repair := _parse_decision_content(content)
	var decision: Variant = repair.get("decision")
	if bool(repair.get("repaired", false)):
		diagnostics["json_repaired"] = true
		diagnostics["json_repair_kind"] = String(
		repair.get("repair_kind", "wrapper")
	)
	if typeof(decision) != TYPE_DICTIONARY:
		diagnostics["error_type"] = "invalid_decision_json"
		_complete_failure(on_complete, ["模型回答不是合法的决定 JSON 对象"], diagnostics)
		return
	diagnostics["parsed_decision"] = decision
	_retain_record(_diagnostics, diagnostics)
	var result_packet := {"ok": true, "decision": decision}
	_retain_record(_results, result_packet)
	if on_complete.is_valid():
		on_complete.call(result_packet.duplicate(true))


func _parse_decision_content(content: String) -> Dictionary:
	# Provider responses occasionally wrap an otherwise valid object in a
	# markdown fence or one short sentence. Parse balanced JSON objects instead
	# of taking the first and last braces: thinking text may contain an example
	# object before the actual resident decision.
	var candidates: Array[Dictionary] = []
	var trimmed := content.strip_edges()
	candidates.append({"text": trimmed, "kind": "direct"})
	var unfenced := trimmed
	if unfenced.begins_with("```"):
		var first_newline := unfenced.find("\n")
		var last_fence := unfenced.rfind("```")
		if first_newline >= 0 and last_fence > first_newline:
			unfenced = unfenced.substr(
				first_newline + 1,
				last_fence - first_newline - 1,
			).strip_edges()
			candidates.append({"text": unfenced, "kind": "code_fence"})
	var object_candidates := _balanced_json_objects(unfenced)
	for index in range(object_candidates.size() - 1, -1, -1):
		candidates.append({
			"text": object_candidates[index],
			"kind": "outer_text",
		})
	for candidate: Dictionary in candidates:
		var candidate_text := String(candidate.get("text", ""))
		var parsed: Variant = _try_parse_json(candidate_text)
		if parsed is Dictionary:
			return {
				"decision": AgentJsonScript.normalize_numbers(parsed),
				"repaired": candidate.get("kind", "direct") != "direct",
				"repair_kind": String(candidate.get("kind", "direct")),
			}
		var comma_regex := RegEx.new()
		if comma_regex.compile(",\\s*([}\\]])") == OK:
			var comma_fixed := comma_regex.sub(candidate_text, "$1", true)
			parsed = _try_parse_json(comma_fixed)
			if parsed is Dictionary:
				return {
					"decision": AgentJsonScript.normalize_numbers(parsed),
					"repaired": true,
					"repair_kind": "%s_trailing_comma" % String(
						candidate.get("kind", "direct")
					),
				}
	return {"decision": null, "repaired": false}


func _response_text(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return (value as String).strip_edges()
	if value is Array:
		var parts: Array[String] = []
		for part_value: Variant in value as Array:
			var part_text := _response_text(part_value)
			if not part_text.is_empty():
				parts.append(part_text)
		return "\n".join(parts).strip_edges()
	if value is Dictionary:
		var part := value as Dictionary
		for key: String in ["text", "content", "value"]:
			if part.has(key):
				return _response_text(part.get(key))
	return ""


func _reasoning_text(choice: Dictionary, message: Dictionary) -> String:
	for source: Dictionary in [message, choice]:
		for key: String in [
			"reasoning_content",
			"thinking_content",
			"reasoning",
			"thinking",
		]:
			if source.has(key):
				var text := _response_text(source.get(key))
				if not text.is_empty():
					return text
	return ""


func _strip_thinking_blocks(content: String) -> Dictionary:
	var cleaned := content
	var removed := false
	for tag: String in ["think", "thinking", "reasoning"]:
		var regex := RegEx.new()
		if regex.compile("(?is)<%s>.*?</%s>" % [tag, tag]) != OK:
			continue
		var replaced := regex.sub(cleaned, "", true)
		if replaced != cleaned:
			removed = true
		cleaned = replaced
		var opening := RegEx.new()
		if opening.compile("(?is)<%s>" % tag) != OK:
			continue
		var match := opening.search(cleaned)
		if match != null:
			# An unfinished thinking block cannot safely be searched for a
			# decision object; discard it and let the caller report a clear error.
			cleaned = cleaned.substr(0, match.get_start()).strip_edges()
			removed = true
	return {"text": cleaned.strip_edges(), "removed": removed}


func _balanced_json_objects(text: String) -> Array[String]:
	var objects: Array[String] = []
	var depth := 0
	var object_start := -1
	var in_string := false
	var escaped := false
	for index: int in text.length():
		var character := text.substr(index, 1)
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == '"':
				in_string = false
			continue
		if character == '"':
			in_string = true
		elif character == '{':
			if depth == 0:
				object_start = index
			depth += 1
		elif character == '}' and depth > 0:
			depth -= 1
			if depth == 0 and object_start >= 0:
				objects.append(text.substr(
					object_start,
					index - object_start + 1,
				).strip_edges())
				object_start = -1
	return objects


func _try_parse_json(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


func _complete_failure(on_complete: Callable, errors: Array, diagnostics: Dictionary) -> void:
	diagnostics["provider"] = _provider_id()
	diagnostics["model"] = String(_config.get("model", _default_model()))
	diagnostics["errors"] = errors.duplicate(true)
	_retain_record(_diagnostics, diagnostics)
	var result_packet := {"ok": false, "errors": ["模型调用失败"]}
	_retain_record(_results, result_packet)
	if on_complete.is_valid():
		on_complete.call(result_packet.duplicate(true))


func _provider_error_message(raw_response: Dictionary) -> String:
	var error: Variant = raw_response.get("error")
	if typeof(error) == TYPE_DICTIONARY:
		return String((error as Dictionary).get("message", ""))
	return String(raw_response.get("message", ""))


func _provider_error_code(raw_response: Dictionary) -> String:
	var error: Variant = raw_response.get("error")
	if typeof(error) == TYPE_DICTIONARY:
		return String((error as Dictionary).get("code", ""))
	return String(raw_response.get("code", ""))


func _http_error_type(status_code: int, raw_response: Dictionary = {}) -> String:
	var error_identifiers := [_provider_error_code(raw_response), _provider_error_type(raw_response)]
	for identifier: String in error_identifiers:
		if identifier in _billing_error_identifiers():
			return "billing"
	match status_code:
		401:
			return "authentication"
		402:
			return "billing"
		429:
			return "rate_limit"
		500, 502, 503, 504:
			return "server"
		_:
			return "http"


func _http_error_retryable(status_code: int, raw_response: Dictionary = {}) -> bool:
	if status_code == 429:
		return _http_error_type(status_code, raw_response) != "billing"
	return status_code >= 500


func _provider_error_type(raw_response: Dictionary) -> String:
	var error: Variant = raw_response.get("error")
	if typeof(error) == TYPE_DICTIONARY:
		return String((error as Dictionary).get("type", ""))
	return String(raw_response.get("type", ""))


func _billing_error_identifiers() -> Array[String]:
	return []


func _transport_error_type(result: int) -> String:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return "timeout"
	return "network"


func _transport_error_text(result: int) -> String:
	if result == HTTPRequest.RESULT_TIMEOUT:
		return "请求超时"
	return "错误码 %d" % result


func _retain_record(records: Array, record: Dictionary) -> void:
	# 记录归 Provider 所有，保留后不再修改；getter 返回深拷贝。
	records.append(record)
	var record_limit := maxi(int(_config.get("record_limit", DEFAULT_RECORD_LIMIT)), 1)
	while records.size() > record_limit:
		records.pop_front()


func _provider_id() -> String:
	return "openai-compatible"


func _provider_label() -> String:
	return "OpenAICompatibleModelProvider"


func _transport_label() -> String:
	return "OpenAI-compatible API"


func _default_endpoint() -> String:
	return ""


func _default_model() -> String:
	return ""


func _provider_request_options() -> Dictionary:
	return {}


func _api_key_environment_names() -> Array[String]:
	return []


func _api_key_required() -> bool:
	return true


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少模型 API Key"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
