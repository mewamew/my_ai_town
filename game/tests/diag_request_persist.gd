extends SceneTree
## diag_request_persist.gd — 验证 LLM 请求原始数据落盘功能
## 运行: Godot --headless --path game --script res://tests/diag_request_persist.gd

const PROVIDER := preload("res://agent/model/OpenAICompatibleModelProvider.gd")

func _init() -> void:
	print("===== 请求原始数据落盘 验证 =====")
	var failures := 0
	var provider := PROVIDER.new(null, null, {
		"endpoint": "https://example.invalid/v1/chat/completions",
		"model": "test-model",
		"api_key": "test-key",
		"request_log_root": "user://tests/agent_runtime_requests_diag",
		"input_modalities": ["text"],
	})
	# 清理旧目录
	var old_root := "user://tests/agent_runtime_requests_diag"
	if DirAccess.dir_exists_absolute(old_root):
		DirAccess.remove_absolute(old_root)
	# 构造一次模型请求
	var model_request := {
		"messages": [
			{"role": "system", "content": "这是测试系统提示词,含家境殷实等数据"},
			{"role": "user", "content": "居民本轮决定上下文…"},
		],
		"max_tokens": 300,
	}
	# 直接调用落盘方法(绕过网络)
	if not provider.has_method("_persist_request_record"):
		# 本地改造的请求落盘接口未迁入上游 provider(官方以记忆写盘队列
		# MemoryStore/ResidentEvidenceQueue 取代), 该 diag 不再适用 → 快速跳过。
		print("[SKIP] 上游 provider 无 _persist_request_record, 跳过请求落盘验证")
		quit(0)
		return
	var recorded_request := {"url": "https://example.invalid/v1/chat/completions", "body": {
		"model": "test-model",
		"messages": model_request["messages"],
		"max_tokens": 300,
		"stream": false,
	}}
	provider._persist_request_record(recorded_request, {"choices": [{"message": {"content": "{\"decision_id\":\"t-1\"}"}}]}, {
		"provider": "openai-compatible",
		"model": "test-model",
		"status_code": 200,
		"elapsed_ms": 12,
		"parsed_decision": {"decision_id": "t-1"},
	})
	# 检查文件是否写入
	var root := "user://tests/agent_runtime_requests_diag"
	if not DirAccess.dir_exists_absolute(root):
		print("[FAIL] 落盘目录未创建")
		failures += 1
	else:
		var dir := DirAccess.open(root)
		var files: Array[String] = []
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir():
				files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		print("  生成文件数:", files.size())
		if files.is_empty():
			print("[FAIL] 没有生成请求记录文件")
			failures += 1
		else:
			for fn in files:
				var content := FileAccess.get_file_as_string("%s/%s" % [root, fn])
				var has_request := content.contains("request")
				var has_messages := content.contains("messages")
				var has_response := content.contains("raw_response")
				var has_decision := content.contains("parsed_decision")
				print("  [%s] 含request=%s 含messages=%s 含raw_response=%s 含decision=%s" % [fn, has_request, has_messages, has_response, has_decision])
				if not (has_request and has_messages and has_response and has_decision):
					print("[FAIL] %s 内容不完整" % fn)
					failures += 1
	print("\n===== 结果: %s =====" % ("全部通过" if failures == 0 else "%d 项失败" % failures))
	quit(failures)
