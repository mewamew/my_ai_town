extends SceneTree


const OFFLINE_REBIND := preload(
	"res://world/presentation/session/TownOfflineResidentModelRebindService.gd"
)
const SAVE_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const AGENT_STORE := preload("res://agent/lifecycle/AgentSaveStore.gd")
const ASSIGNMENT_SERVICE := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentService.gd"
)
const FIXTURE := preload(
	"res://tests/support/OfflineResidentModelRebindFixture.gd"
)


class FakeProviderService:
	extends RefCounted
	var available := true

	func set_available(value: bool) -> void:
		available = value

	func get_health_snapshot() -> Dictionary:
		if not available:
			return {
				"ok": false,
				"errorCode": "PROVIDER_HEALTH_UNAVAILABLE",
				"retryable": false,
			}
		return {
			"ok": true,
			"formalReady": true,
			"capabilityMode": "formal",
			"source": "runtime",
			"providers": [{
				"providerId": "current-provider",
				"label": "当前服务",
				"status": "available",
			}],
		}

	func list_available_models() -> Array:
		var models: Array[Dictionary] = []
		if not available:
			return models
		for model_id in ["current-model", "current-model-2", "current-model-3"]:
			models.append({
				"providerId": "current-provider",
				"modelId": model_id,
				"label": model_id,
				"available": true,
			})
		return models

	func validate_resident_bindings(bindings: Variant) -> Dictionary:
		if not bindings is Array:
			return _failure("SESSION_LLM_BINDINGS_INVALID")
		var errors: Array[Dictionary] = []
		for value: Variant in bindings as Array:
			if not value is Dictionary:
				return _failure("SESSION_LLM_BINDINGS_INVALID")
			var binding := (value as Dictionary).get("llmBinding", {}) as Dictionary
			if (
				String(binding.get("providerId", "")) != "current-provider"
				or String(binding.get("modelId", ""))
				not in ["current-model", "current-model-2", "current-model-3"]
			):
				errors.append({
					"code": "LLM_MODEL_UNAVAILABLE",
					"meta": {
						"residentId": String((value as Dictionary).get("residentId", "")),
						"providerId": String(binding.get("providerId", "")),
						"modelId": String(binding.get("modelId", "")),
					},
				})
		return (
			{"ok": true, "errorCode": "", "retryable": false}
			if errors.is_empty()
			else {
				"ok": false,
				"errorCode": "LLM_MODEL_UNAVAILABLE",
				"retryable": false,
				"errors": errors,
			}
		)

	func create_provider_for_resident(_binding: Dictionary) -> RefCounted:
		return null

	func get_latest_diagnostic(_resident_id: String = "") -> Dictionary:
		return {}

	func _failure(error_code: String) -> Dictionary:
		return {
			"ok": false,
			"errorCode": error_code,
			"retryable": false,
			"errors": [],
		}


class FailPublishStore:
	extends TownSessionSaveStore

	func publish_manifest(_manifest: Variant) -> Dictionary:
		return {
			"ok": false,
			"errorCode": "SESSION_SAVE_MANIFEST_PUBLISH_FAILED",
			"retryable": true,
		}


class FaultInjectingAgentStore:
	extends AgentSaveStore
	var fail_next_discard := false

	func discard_snapshot(context: Variant) -> Dictionary:
		if fail_next_discard:
			fail_next_discard = false
			return {
				"ok": false,
				"errorCode": "TEST_AGENT_SNAPSHOT_DELETE_FAILED",
				"retryable": true,
				"errors": [{"code": "TEST_AGENT_SNAPSHOT_DELETE_FAILED"}],
			}
		return super.discard_snapshot(context)

var _failures: Array[String] = []
var _checks := 0
var _save_store: RefCounted
var _agent_store: RefCounted
var _slot_id := ""
var _session_id := ""
var _save_root := ""
var _agent_root := ""
var _profile_path := ""
var _fixture: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var identity := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_fixture = FIXTURE.new()
	_expect_ok(
		_fixture.configure(identity, FaultInjectingAgentStore.new()),
		"离线改绑使用隔离的 World 与 Agent 存档目录",
	)
	_slot_id = _fixture.slot_id
	_session_id = _fixture.session_id
	_save_root = _fixture.save_root
	_agent_root = _fixture.agent_root
	_profile_path = _fixture.profile_path
	_save_store = _fixture.save_store
	_agent_store = _fixture.agent_store
	var source := _create_source_revision()
	_expect_ok(source, "源完整修订可创建")
	if source.get("ok") == true:
		var context := source.get("context", {}) as Dictionary
		_expect(
			ProjectSettings.globalize_path(String(
				_save_store.call("_revision_root", context),
			)).length() >= 260,
			"离线复制夹具跨过传统 Windows 260 字符路径边界",
		)
		_test_prepare_and_publish(source)
	await _cleanup()
	if _failures.is_empty():
		print("OFFLINE_RESIDENT_MODEL_REBIND_PASS checks=%d" % _checks)
	else:
		for failure in _failures:
			printerr("OFFLINE_RESIDENT_MODEL_REBIND_FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_prepare_and_publish(source: Dictionary) -> void:
	var slot := _catalog_slot()
	_expect(not slot.is_empty(), "启动目录可读取源完整修订")
	if slot.is_empty():
		return
	var service: RefCounted = OFFLINE_REBIND.new()
	_expect_ok(
		service.call(
			"configure",
			_save_store,
			_agent_store,
			FakeProviderService.new(),
		) as Dictionary,
		"离线改绑服务可绑定 World 与 Agent Store",
	)
	var prepared := service.call(
		"prepare",
		slot,
		_base_catalog(),
	) as Dictionary
	_expect_ok(prepared, "失效的旧绑定不会阻止编辑页准备")
	_expect_equal(
		((prepared.get("draft", {}) as Dictionary).get("slots", []) as Array).size(),
		2,
		"编辑草稿只包含存档中的居民",
	)
	var assignment := ASSIGNMENT_SERVICE.new()
	_expect_ok(
		assignment.configure(
			FakeProviderService.new(),
			prepared.get("residentCatalog", {}) as Dictionary,
			prepared.get("draft", {}) as Dictionary,
		),
		"模型分配页可带着失效旧绑定打开",
	)
	var assignment_data := (
		assignment.get_view_model().get("data", {}) as Dictionary
	)
	_expect_equal(assignment_data.get("invalidCount"), 2, "失效旧绑定显示为待改绑")

	var source_manifest := (
		source.get("manifest", {}) as Dictionary
	).duplicate(true)
	var source_world_hash := String(
		((source_manifest.get("components", {}) as Dictionary).get(
			"world",
			{},
		) as Dictionary).get("snapshot_sha256", ""),
	)
	var rejected_binding := service.call(
		"apply_bindings",
		_bindings_for("current-provider", "removed-model"),
	) as Dictionary
	_expect_equal(
		rejected_binding.get("errorCode"),
		"LLM_MODEL_UNAVAILABLE",
		"事务提交点拒绝已从当前配置移除的目标模型",
	)
	_expect_equal(
		((_save_store.call("list_published", _slot_id) as Dictionary).get(
			"manifests",
			[],
		) as Array).size(),
		1,
		"无效目标绑定不会预留或发布新修订",
	)
	var applied := service.call(
		"apply_bindings",
		_current_bindings(),
	) as Dictionary
	_expect_ok(applied, "离线改绑发布新的完整修订")
	_expect_equal(
		(applied.get("context", {}) as Dictionary).get("save_revision"),
		2,
		"离线改绑发布下一个修订号",
	)
	var manifests := (
		(_save_store.call("list_published", _slot_id) as Dictionary).get(
			"manifests",
			[],
		) as Array
	)
	_expect_equal(manifests.size(), 2, "原修订与新修订同时保留")
	if manifests.size() != 2:
		return
	var old_manifest := manifests[1] as Dictionary
	var new_manifest := manifests[0] as Dictionary
	_expect_equal(old_manifest, source_manifest, "原 manifest 保持只读")
	_expect_equal(
		((old_manifest.get("components", {}) as Dictionary).get(
			"world",
			{},
		) as Dictionary).get("snapshot_sha256"),
		source_world_hash,
		"原 World 哈希保持不变",
	)
	var new_config := _save_store.call(
		"read_reference",
		new_manifest.get("session_config_ref"),
		new_manifest.get("session_config_sha256"),
	) as Dictionary
	_expect_equal(
		(new_config.get("value", {}) as Dictionary).get("residentBindings"),
		_current_bindings(),
		"新修订只采用当前可用模型绑定",
	)
	var old_world := _save_store.call(
		"read_reference",
		((old_manifest.get("components", {}) as Dictionary).get(
			"world",
			{},
		) as Dictionary).get("snapshot_ref"),
		source_world_hash,
	) as Dictionary
	var new_world_component := (
		(new_manifest.get("components", {}) as Dictionary).get("world", {})
		as Dictionary
	)
	var new_world := _save_store.call(
		"read_reference",
		new_world_component.get("snapshot_ref"),
		new_world_component.get("snapshot_sha256"),
	) as Dictionary
	_expect_equal(new_world.get("value"), old_world.get("value"), "World 快照成对复制")
	var old_agent := _agent_store.call(
		"load_snapshot",
		{"slot_id": _slot_id, "session_id": _session_id, "save_revision": 1},
	) as Dictionary
	var new_agent := _agent_store.call(
		"load_snapshot",
		{"slot_id": _slot_id, "session_id": _session_id, "save_revision": 2},
	) as Dictionary
	_expect_equal(
		new_agent.get("resident_payloads"),
		old_agent.get("resident_payloads"),
		"Agent 快照与同一源修订成对复制",
	)

	var fresh_slot := _catalog_slot()
	var first := OFFLINE_REBIND.new()
	var second := OFFLINE_REBIND.new()
	first.call("configure", _save_store, _agent_store, FakeProviderService.new())
	second.call("configure", _save_store, _agent_store, FakeProviderService.new())
	first.call("prepare", fresh_slot, _base_catalog())
	second.call("prepare", fresh_slot, _base_catalog())
	var next_bindings := _bindings_for("current-provider", "current-model-2")
	_expect_ok(
		second.call("apply_bindings", next_bindings) as Dictionary,
		"并发基线中的先提交者成功",
	)
	var stale := first.call("apply_bindings", next_bindings) as Dictionary
	_expect_equal(
		stale.get("errorCode"),
		"OFFLINE_RESIDENT_MODEL_REBIND_TARGET_STALE",
		"目标修订变化后拒绝迟到提交",
	)

	var failure_service := OFFLINE_REBIND.new()
	var failing_store := FailPublishStore.new()
	_expect_ok(
		failing_store.configure_test_root(_save_root),
		"发布失败替身复用隔离的 World 存档目录",
	)
	failure_service.call(
		"configure",
		failing_store,
		_agent_store,
		FakeProviderService.new(),
	)
	failure_service.call("prepare", _catalog_slot(), _base_catalog())
	(_agent_store as FaultInjectingAgentStore).fail_next_discard = true
	var failed := failure_service.call(
		"apply_bindings",
		_bindings_for("current-provider", "current-model-3"),
	) as Dictionary
	_expect(not bool(failed.get("ok", false)), "manifest 发布失败会返回可重试错误")
	_expect_equal(failed.get("retryable"), true, "磁盘发布失败明确允许玩家重试")
	_expect_equal(
		failed.get("errorCode"),
		"OFFLINE_RESIDENT_MODEL_REBIND_CLEANUP_FAILED",
		"Agent 清理失败使用可恢复的清理错误",
	)
	var after_failure := _save_store.call("list_published", _slot_id) as Dictionary
	_expect_equal(
		(after_failure.get("manifests", []) as Array).size(),
		3,
		"失败提交不影响已有完整修订",
	)
	var preserved_agent := _agent_store.call(
		"load_snapshot",
		{"slot_id": _slot_id, "session_id": _session_id, "save_revision": 4},
	) as Dictionary
	_expect_ok(preserved_agent, "Agent 删除失败时保留未发布修订证据")
	_expect_equal(
		((failed.get("meta", {}) as Dictionary).get("context", {}) as Dictionary).get(
			"save_revision",
		),
		4,
		"清理失败回执标记被保留的修订",
	)
	var retry_service := OFFLINE_REBIND.new()
	_expect_ok(
		retry_service.call(
			"configure",
			_save_store,
			_agent_store,
			FakeProviderService.new(),
		) as Dictionary,
		"Agent 清理失败后可重建离线改绑流程",
	)
	_expect_ok(
		retry_service.call("prepare", _catalog_slot(), _base_catalog()) as Dictionary,
		"重试仍钉住原发布修订",
	)
	var retried := retry_service.call(
		"apply_bindings",
		_bindings_for("current-provider", "current-model-3"),
	) as Dictionary
	_expect_ok(retried, "重试跳过残留修订并成功发布")
	_expect_equal(
		(retried.get("context", {}) as Dictionary).get("save_revision"),
		5,
		"残留 allocation 推动修订号前进",
	)


func _create_source_revision() -> Dictionary:
	return _fixture.create_source_revision()


func _catalog_slot() -> Dictionary:
	var slot: Dictionary = _fixture.catalog_slot()
	if slot.has("fixtureError"):
		_failures.append("启动存档目录读取失败：%s" % slot.get("fixtureError"))
		return {}
	return slot


func _base_catalog() -> Dictionary:
	return _fixture.base_catalog()


func _current_bindings() -> Array[Dictionary]:
	return _bindings_for("current-provider", "current-model")


func _bindings_for(provider_id: String, model_id: String) -> Array[Dictionary]:
	return _fixture.bindings_for(provider_id, model_id)


func _cleanup() -> void:
	if _fixture != null:
		_fixture.cleanup()
	_save_store = null
	_agent_store = null
	_fixture = null
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	for _index in 3:
		await process_frame
	await create_timer(0.3, true, false, true).timeout


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(bool(result.get("ok", false)), "%s：%s" % [message, result])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s（actual=%s expected=%s）" % [message, actual, expected])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
