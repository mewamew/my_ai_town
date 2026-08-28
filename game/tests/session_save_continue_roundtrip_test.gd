extends SceneTree


const INTERNAL_CATALOG := preload(
	"res://world/presentation/session/TownInternalPlaytestCatalog.gd"
)
const COMPILER := preload(
	"res://world/presentation/session/TownNewGameOpeningCompiler.gd"
)
const BOOTSTRAP := preload(
	"res://world/presentation/session/TownSessionBootstrap.gd"
)
const PROVIDER_SERVICE := preload(
	"res://world/integration/TownAgentProviderService.gd"
)
const GATEWAY := preload(
	"res://world/integration/TownWorldAgentGateway.gd"
)
const TOWN_RUNTIME_SCENE := preload(
	"res://world/presentation/town_runtime/TownRuntime.tscn"
)
const STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const RUNTIME_GATE := preload(
	"res://world/presentation/session/TownSessionRuntimeGate.gd"
)
const COORDINATOR := preload(
	"res://world/presentation/session/TownSessionSaveCoordinator.gd"
)
const SESSION_UI_SERVICE := preload(
	"res://world/presentation/session/TownSessionUiService.gd"
)
const STARTUP_SAVE_CATALOG := preload(
	"res://world/presentation/session/TownStartupSaveCatalog.gd"
)
const AGENT_SAVE_STORE := preload(
	"res://agent/lifecycle/AgentSaveStore.gd"
)

var _failures: Array[String] = []
var _checks := 0


class ResultCollector:
	extends RefCounted
	var result: Dictionary = {}

	func collect(value: Dictionary) -> void:
		result = value.duplicate(true)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	var identity := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var slot_id := "roundtrip-slot-%s" % identity
	var session_id := "roundtrip-session-%s" % identity
	var test_root := "user://tests/town_session_saves/roundtrip_%s" % identity
	var world_data := _read_json("res://world/data/town/town_world.json")
	var selection_vm := INTERNAL_CATALOG.build_view_model("fake", "fake")
	var selection_data := selection_vm.get("data", {}) as Dictionary
	selection_data["selected_resident_ids"] = (
		selection_data.get("recommended_resident_ids", []) as Array
	).slice(0, 5)
	INTERNAL_CATALOG.update_confirmation_payload(
		selection_data,
		"fake",
		"fake",
		2,
	)
	var draft := (
		selection_data.get("confirmation_payload", {}) as Dictionary
	).duplicate(true)
	var catalog := INTERNAL_CATALOG.build_catalog(world_data, selection_vm)
	var compiled := COMPILER.compile(draft, world_data, catalog) as Dictionary
	_expect_ok(compiled, "正式组合器可生成完整开局配置")
	if compiled.get("ok") != true:
		_finish()
		return
	var bindings := compiled.get("residentBindings", []) as Array[Dictionary]
	var identities := _identities(bindings)
	_expect_equal(identities.size(), 5, "少人口闭环只包含五位居民")
	var request_host := Node.new()
	request_host.name = "SaveContinueRoundtripRequestHost"
	root.add_child(request_host)
	var provider_service: RefCounted = PROVIDER_SERVICE.new()
	_expect_ok(provider_service.call("configure", {
		"capabilityMode": "development",
		"source": "placeholder",
		"allowFake": true,
		"providerConfigs": {},
	}, request_host) as Dictionary, "离线居民模型服务可用于存档闭环")

	var source_gateway: Node = GATEWAY.new()
	var source_runtime: Node = TOWN_RUNTIME_SCENE.instantiate()
	var bootstrap: RefCounted = BOOTSTRAP.new()
	var collector := ResultCollector.new()
	var accepted := bootstrap.call(
		"begin_new_game_from_catalog",
		draft,
		world_data,
		catalog,
		provider_service,
		source_gateway,
		source_runtime,
		{
			"worldStartMode": "development",
			"internalPlaytest": true,
			"sessionId": session_id,
			"slotId": slot_id,
			"requestHost": request_host,
			"useLiveModel": false,
			"enablePlayerAvatar": false,
		},
		collector.collect,
	) as Dictionary
	_expect_equal(accepted.get("accepted"), true, "新游戏请求被正式组合器接收")
	_expect_ok(collector.result, "源小镇完成启动")
	if collector.result.get("ok") != true:
		source_runtime.free()
		request_host.queue_free()
		_finish()
		return
	root.add_child(source_runtime)
	await _wait_frames(4)
	_expect_ok(
		source_runtime.call("get_startup_result") as Dictionary,
		"源小镇完成场景挂载",
	)
	var source_world: RefCounted = source_runtime.call("get_world_runtime")
	var source_agent: RefCounted = source_gateway.call("get_agent_save_participant")
	var store: RefCounted = STORE.new()
	_expect_ok(
		store.call("configure_test_root", test_root) as Dictionary,
		"闭环测试存档目录可配置",
	)
	var source_gate: RefCounted = RUNTIME_GATE.new()
	_expect_ok(source_gate.call("configure", source_runtime) as Dictionary, "源小镇事务锁可配置")
	var save_coordinator: RefCounted = COORDINATOR.new()
	_expect_ok(save_coordinator.call(
		"configure",
		store,
		source_world,
		source_agent,
		source_gate,
	) as Dictionary, "成对存档协调器可配置")
	var session_config := {
		"mode": "new_game",
		"sessionId": session_id,
		"openingConfig": (
			compiled.get("openingConfig", {}) as Dictionary
		).duplicate(true),
		"residentIdentities": identities.duplicate(true),
		"residentBindings": _saved_bindings(bindings),
		"connectedResidents": _resident_names(identities),
		"worldStartMode": "formal",
		"useLiveModel": true,
		"enablePlayerAvatar": false,
		"enableTestUi": false,
	}
	var saved_time := source_world.call("get_time") as Dictionary
	var saved := save_coordinator.call("save", {
		"slotId": slot_id,
		"sessionId": session_id,
		"residentIdentities": identities.duplicate(true),
		"sessionConfig": session_config.duplicate(true),
		"savedAt": Time.get_datetime_string_from_system(false, false),
		"residentMessages": [],
	}) as Dictionary
	_expect_ok(saved, "世界与居民存档作为同一修订发布")
	var context := saved.get("context", {}) as Dictionary
	_expect_equal(context.get("save_revision"), 1, "首个成对存档修订号为 1")
	var discovered := save_coordinator.call("discover_latest", slot_id) as Dictionary
	_expect_ok(discovered, "刚发布的存档可从正式发现入口读取")
	_expect_equal(
		(discovered.get("summary", {}) as Dictionary).get("saveRevision"),
		1,
		"发现入口返回已发布修订而不是临时文件",
	)
	var async_session_config := session_config.duplicate(true)
	async_session_config["slotId"] = slot_id
	async_session_config["capabilityMode"] = "formal"
	async_session_config["formalReady"] = true
	var async_service: RefCounted = SESSION_UI_SERVICE.new()
	_expect_ok(
		async_service.call("configure_test_store_root", test_root) as Dictionary,
		"异步服务复用正式测试存储根目录",
	)
	_expect_ok(
		async_service.call(
			"configure",
			source_runtime,
			source_world,
			source_agent,
			async_session_config,
		) as Dictionary,
		"真实 World 与 Agent 可配置异步保存服务",
	)
	var async_started := async_service.call("begin_create_save_async", {
		"reason": "roundtrip_async_regression",
	}) as Dictionary
	_expect_equal(async_started.get("pending"), true, "真实异步保存立即返回 pending")
	var async_capture_step := async_service.call(
		"poll_create_save_async",
	) as Dictionary
	_expect_equal(
		async_capture_step.get("capturePending"),
		true,
		"多居民存档捕获按帧推进，不在启动调用中一次完成",
	)
	var manual_after_async := async_service.call("create_save", {
		"reason": "manual_save_during_async_regression",
	}) as Dictionary
	_expect_ok(manual_after_async, "手动保存等待异步任务后继续发布")
	_expect_equal(
		(manual_after_async.get("context", {}) as Dictionary).get("save_revision"),
		3,
		"手动保存排在异步修订之后，不覆盖异步修订",
	)
	var async_saved := await _wait_for_async_save(async_service)
	_expect_ok(async_saved, "真实异步保存发布第二个成对修订")
	var async_context := (
		async_saved.get("context", {}) as Dictionary
	).duplicate(true)
	_expect_equal(
		async_context.get("save_revision"),
		2,
		"真实异步保存分配第二个修订号",
	)
	_expect_equal(
		(source_agent.call("get_save_context") as Dictionary).get("save_revision"),
		3,
		"异步与手动 manifest 发布后 Agent 上下文保持最新",
	)
	var async_snapshot := async_service.call("get_save_snapshot") as Dictionary
	_expect_equal(
		((async_snapshot.get("slots", []) as Array)[0] as Dictionary).get(
			"saveRevision",
		),
		3,
		"正式发现入口只暴露已经发布的最新修订",
	)

	var damaged_manifest := manual_after_async.get("manifest", {}) as Dictionary
	var damaged_world := (
		(damaged_manifest.get("components", {}) as Dictionary)
		.get("world", {}) as Dictionary
	)
	_assert_component_damage_matrix(
		store,
		test_root,
		slot_id,
		session_id,
		identity,
		damaged_manifest,
	)
	var damaged_reference := String(damaged_world.get("snapshot_ref", ""))
	var damaged_path := "%s/%s" % [test_root, damaged_reference]
	var damaged_file := FileAccess.open(damaged_path, FileAccess.WRITE)
	_expect(damaged_file != null, "修复故事可构造最新 World 引用损坏")
	if damaged_file != null:
		damaged_file.store_string("{}\n")
		damaged_file = null

	var recovery_case := _inspect_recovery_case(store, slot_id, identity)
	var recovery_plan := recovery_case.get("plan", {}) as Dictionary

	source_runtime.queue_free()
	await _wait_frames(4)

	var prepared := await _prepare_continue_runtime({
		"providerService": provider_service,
		"requestHost": request_host,
		"testRoot": test_root,
		"sessionConfig": session_config,
		"identities": identities,
		"bindings": bindings,
		"context": async_context,
	})
	_expect_ok(prepared.get("gatewayConfiguration", {}), "恢复中的居民网关可配置")
	_expect_ok(prepared.get("gatewayInjection", {}), "恢复网关可注入新小镇")
	_expect_ok(prepared.get("runtimeConfiguration", {}), "正式继续游戏配置可在小镇入树前完成")
	_expect_ok(prepared.get("startup", {}), "恢复中的正式小镇完成场景挂载")
	_expect_ok(prepared.get("storeConfiguration", {}), "恢复服务可复用测试存档目录")
	_expect_ok(prepared.get("serviceConfiguration", {}), "成对恢复服务可配置")
	var restore_gateway: Node = prepared.get("gateway")
	var restored_runtime: Node = prepared.get("runtime")
	var restored_world: RefCounted = prepared.get("world")
	var restored_agent: RefCounted = prepared.get("agent")
	var restore_service: RefCounted = prepared.get("service")
	_expect_equal(
		restored_runtime.call("_viewport_size_or_default"),
		Vector2(1920.0, 1080.0),
		"正式小镇使用项目逻辑分辨率",
	)
	var restored := restore_service.call(
		"continue_revision",
		session_id,
		2,
		world_data,
		identities,
		restore_gateway,
	) as Dictionary
	_expect_ok(restored, "同一修订的世界与居民状态完整恢复")
	_expect_equal(restored.get("context"), async_context, "恢复回执对应异步存档修订")
	_expect_equal(restored_world.call("get_time"), saved_time, "恢复后世界时间与保存时一致")
	_expect_equal(
		(restored_world.call("get_resident_ids") as Array).size(),
		5,
		"恢复后仍是原有五位居民",
	)
	_expect_equal(
		restore_gateway.call("get_agent_save_context"),
		async_context,
		"恢复后居民存档上下文与世界修订一致",
	)
	_expect_equal(
		(restored_runtime.call("get_runtime_state") as Dictionary).get("avatarMode"),
		"observer",
		"加载存档后始终从自由观察模式进入小镇",
	)
	_expect_ok(
		restored_runtime.call("complete_restored_session", async_context) as Dictionary,
		"恢复完成状态可提交给小镇运行时",
	)
	var repaired_context := _verify_recovery_publication(
		restore_service,
		store,
		recovery_case,
		damaged_reference,
		damaged_world,
	)
	_expect_ok(
		restored_runtime.record_published_save(repaired_context),
		"运行时同步记录修复后发布的新修订",
	)
	_expect_equal(
		(restored_runtime.get("session_config") as Dictionary).get("saveRevision"),
		4,
		"进入小镇前运行时上下文已指向修订 4",
	)
	_expect_equal(
		(restored_runtime.call("get_runtime_state") as Dictionary).get("viewMode"),
		"town",
		"恢复完成后正式小镇保持可见室外视图",
	)
	# 正式存档继续沿用清单中的稳定会话配置；restorePending 等字段只属于
	# 本次进场运行上下文，不能写回持久化配置。
	var resaved := restore_service.call("create_save", {
		"residentMessages": [],
	}) as Dictionary
	_expect_ok(resaved, "五人存档恢复后可以再次成对保存")
	_expect_equal(
		(resaved.get("context", {}) as Dictionary).get("save_revision"),
		5,
		"恢复后的再次保存不会覆盖已有异步修订",
	)
	_expect_equal(
		(restored_world.call("get_resident_ids") as Array).size(),
		5,
		"再次保存不会补出未选择的居民",
	)

	var cleanup_agent := restored_agent
	var cleanup_context := (
		resaved.get("context", context) as Dictionary
	).duplicate(true)
	restored_runtime.queue_free()
	await _wait_frames(4)
	var reopen_request := {
		"providerService": provider_service,
		"requestHost": request_host,
		"testRoot": test_root,
		"sessionConfig": session_config,
		"identities": identities,
		"bindings": bindings,
		"context": repaired_context,
		"worldData": world_data,
	}
	var reopened := await _reopen_repaired_revision(reopen_request)
	_expect_ok(reopened, "修复后的修订可由全新 Runtime 重开")
	_expect_equal(
		(reopened.get("restoredContext", {}) as Dictionary).get("save_revision"),
		4,
		"全新 Runtime 读取修复发布的修订 4",
	)
	_expect_equal(
		(reopened.get("savedContext", {}) as Dictionary).get("save_revision"),
		6,
		"重开后继续运行并再次保存为修订 6",
	)
	var final_catalog := (recovery_case.get("catalog") as RefCounted).call(
		"get_catalog",
		recovery_case.get("slotDefinitions", []),
	) as Dictionary
	_expect_ok(final_catalog, "重开并再次保存后启动目录仍可检查")
	var final_slot := final_catalog.get("continueSlot", {}) as Dictionary
	_expect_equal(final_slot.get("state"), "healthy", "再次保存后槽位保持健康")
	_expect_equal(
		(final_slot.get("summary", {}) as Dictionary).get("saveRevision"),
		6,
		"再次启动会选择修复后继续产生的最新修订",
	)
	_expect_ok(
		cleanup_agent.call("delete_game", cleanup_context) as Dictionary,
		"闭环测试居民存档可清理",
	)
	_expect_ok(store.call("cleanup_test_root") as Dictionary, "闭环测试世界存档可清理")
	request_host.queue_free()
	_finish()


func _prepare_continue_runtime(request: Dictionary) -> Dictionary:
	var context := request.get("context", {}) as Dictionary
	var revision := int(context.get("save_revision", -1))
	var slot_id := String(context.get("slot_id", ""))
	var session_id := String(context.get("session_id", ""))
	var session_config := request.get("sessionConfig", {}) as Dictionary
	var identities := request.get("identities", []) as Array
	var bindings := request.get("bindings", []) as Array
	var steps := {}
	var gateway: Node = GATEWAY.new()
	steps["gatewayConfiguration"] = gateway.call("configure_session", {
		"sessionId": session_id,
		"slotId": slot_id,
		"saveRevision": revision,
		"restorePending": true,
		"openingConfig": session_config.get("openingConfig", {}),
		"residentIdentities": identities.duplicate(true),
		"residentBindings": bindings.duplicate(true),
		"capabilityMode": "formal",
		"formalReady": true,
	}, request.get("providerService"), request.get("requestHost")) as Dictionary
	if (steps.get("gatewayConfiguration") as Dictionary).get("ok") != true:
		return steps
	var runtime: Node = TOWN_RUNTIME_SCENE.instantiate()
	steps["gatewayInjection"] = runtime.call(
		"configure_agent_gateway",
		gateway,
	) as Dictionary
	if (steps.get("gatewayInjection") as Dictionary).get("ok") != true:
		runtime.free()
		return steps
	var runtime_config := {
		"mode": "continue",
		"sessionId": session_id,
		"slotId": slot_id,
		"saveRevision": revision,
		"restorePending": true,
		"openingConfig": session_config.get("openingConfig", {}),
		"residentIdentities": identities.duplicate(true),
		"residentBindings": bindings.duplicate(true),
		"connectedResidents": _resident_names(identities),
		"worldStartMode": "formal",
		"capabilityMode": "formal",
		"source": "runtime",
		"formalReady": true,
		"providerFormalReady": true,
		"internalPlaytest": false,
		"internalLivePlaytest": false,
		"requireAgentGateway": true,
		"useLiveModel": true,
		"enablePlayerAvatar": false,
		"avatarInitialMode": "observer",
		"enableTestUi": false,
	}
	steps["runtimeConfiguration"] = runtime.call(
		"configure_session",
		runtime_config,
	) as Dictionary
	if (steps.get("runtimeConfiguration") as Dictionary).get("ok") != true:
		runtime.free()
		return steps
	root.add_child(runtime)
	await _wait_frames(5)
	steps["startup"] = runtime.call("get_startup_result") as Dictionary
	if (steps.get("startup") as Dictionary).get("ok") != true:
		runtime.queue_free()
		await _wait_frames(4)
		return steps
	var service: RefCounted = SESSION_UI_SERVICE.new()
	steps["storeConfiguration"] = service.call(
		"configure_test_store_root",
		String(request.get("testRoot", "")),
	) as Dictionary
	if (steps.get("storeConfiguration") as Dictionary).get("ok") != true:
		runtime.queue_free()
		await _wait_frames(4)
		return steps
	steps["serviceConfiguration"] = service.call(
		"configure",
		runtime,
		runtime.call("get_world_runtime"),
		gateway.call("get_agent_save_participant"),
		runtime_config,
	) as Dictionary
	if (steps.get("serviceConfiguration") as Dictionary).get("ok") != true:
		runtime.queue_free()
		await _wait_frames(4)
		return steps
	steps.merge({
		"gateway": gateway,
		"runtime": runtime,
		"world": runtime.call("get_world_runtime"),
		"agent": gateway.call("get_agent_save_participant"),
		"service": service,
		"runtimeConfig": runtime_config,
	}, true)
	return steps


func _reopen_repaired_revision(request: Dictionary) -> Dictionary:
	var prepared := await _prepare_continue_runtime(request)
	var service_result := prepared.get("serviceConfiguration", {}) as Dictionary
	if service_result.get("ok") != true:
		return service_result
	var context := request.get("context", {}) as Dictionary
	var revision := int(context.get("save_revision", -1))
	var session_id := String(context.get("session_id", ""))
	var identities := request.get("identities", []) as Array
	var world_data := request.get("worldData", {}) as Dictionary
	var gateway: Node = prepared.get("gateway")
	var runtime: Node = prepared.get("runtime")
	var service: RefCounted = prepared.get("service")
	var restored := service.call(
		"continue_revision",
		session_id,
		revision,
		world_data,
		identities,
		gateway,
	) as Dictionary
	if restored.get("ok") != true:
		runtime.queue_free()
		await _wait_frames(4)
		return restored
	var restored_context := restored.get("context", {}) as Dictionary
	var completed := runtime.call(
		"complete_restored_session",
		restored_context,
	) as Dictionary
	if completed.get("ok") != true:
		runtime.queue_free()
		await _wait_frames(4)
		return completed
	var world: RefCounted = runtime.call("get_world_runtime")
	var before_time := world.call("get_time") as Dictionary
	var advanced := world.call("advance", 1.0) as Dictionary
	if advanced.get("ok") != true or world.call("get_time") == before_time:
		runtime.queue_free()
		await _wait_frames(4)
		return {"ok": false, "errorCode": "TEST_REPAIRED_WORLD_DID_NOT_ADVANCE"}
	var saved := service.call("create_save") as Dictionary
	if saved.get("ok") == true:
		var published_context := saved.get("context", {}) as Dictionary
		var recorded := runtime.call(
			"record_published_save",
			published_context,
		) as Dictionary
		if recorded.get("ok") != true:
			saved = recorded
		else:
			saved["restoredContext"] = restored_context.duplicate(true)
			saved["savedContext"] = published_context.duplicate(true)
	runtime.queue_free()
	await _wait_frames(4)
	return saved


func _assert_component_damage_matrix(
	store: RefCounted,
	test_root: String,
	slot_id: String,
	session_id: String,
	identity: String,
	manifest: Dictionary,
) -> void:
	var revision := int(manifest.get("save_revision", -1))
	var revision_text := "%020d" % revision
	var components := manifest.get("components", {}) as Dictionary
	var world := components.get("world", {}) as Dictionary
	var world_log := components.get("world_log", {}) as Dictionary
	var cases := [
		{
			"name": "manifest",
			"path": "%s/slots/%s/manifests/%s.json" % [test_root, slot_id, revision_text],
			"errorCode": "SESSION_SAVE_MANIFEST_INVALID",
		},
		{
			"name": "session-config",
			"path": "%s/%s" % [test_root, manifest.get("session_config_ref", "")],
			"errorCode": "SESSION_SAVE_REFERENCE_HASH_MISMATCH",
		},
		{
			"name": "world",
			"path": "%s/%s" % [test_root, world.get("snapshot_ref", "")],
			"errorCode": "SESSION_SAVE_REFERENCE_HASH_MISMATCH",
		},
		{
			"name": "world-log",
			"path": "%s/%s" % [test_root, world_log.get("snapshot_ref", "")],
			"errorCode": "SESSION_SAVE_REFERENCE_HASH_MISMATCH",
		},
		{
			"name": "agent",
			"path": (
				"user://agent_saves/%s/sessions/%s/revisions/%d/snapshot.json"
				% [slot_id, session_id, revision]
			),
			"errorCode": "SESSION_SAVE_AGENT_SNAPSHOT_INVALID",
		},
	]
	for case_value: Variant in cases:
		var damage_case := case_value as Dictionary
		var component_name := String(damage_case.get("name", ""))
		var path := String(damage_case.get("path", ""))
		var original := _read_text(path)
		_expect(not original.is_empty(), "%s 损坏样本可读取" % component_name)
		_expect_ok(_write_text(path, "{}\n"), "可构造 %s 独立损坏" % component_name)
		_assert_recoverable_damage(
			store,
			slot_id,
			identity,
			String(damage_case.get("errorCode", "")),
			component_name,
		)
		_expect_ok(_write_text(path, original), "%s 原始证据可复原" % component_name)


func _assert_recoverable_damage(
	store: RefCounted,
	slot_id: String,
	identity: String,
	expected_error_code: String,
	component_name: String,
) -> void:
	var catalog: RefCounted = STARTUP_SAVE_CATALOG.new()
	var agent_store: RefCounted = AGENT_SAVE_STORE.new()
	_expect_ok(catalog.call(
		"configure",
		store,
		"user://tests/town_startup_profile/matrix_%s_%s.json" % [
			identity,
			component_name,
		],
		agent_store,
	) as Dictionary, "%s 损坏检查器可配置" % component_name)
	var inspected := catalog.call("get_catalog", [
		{"slotId": slot_id, "displayName": "损坏矩阵"},
		{
			"slotId": "matrix-empty-%s" % identity,
			"displayName": "空槽位",
		},
	]) as Dictionary
	_expect_ok(inspected, "%s 损坏可完成只读诊断" % component_name)
	var slot := inspected.get("continueSlot", {}) as Dictionary
	_expect_equal(slot.get("state"), "recoverable", "%s 损坏可回退完整配对" % component_name)
	_expect_equal(slot.get("errorCode"), expected_error_code, "%s 损坏分类准确" % component_name)
	_expect_equal(
		(slot.get("recoveryPlan", {}) as Dictionary).get("action"),
		"restore_complete_pair_and_publish",
		"%s 损坏生成安全发布计划" % component_name,
	)


func _inspect_recovery_case(
	store: RefCounted,
	slot_id: String,
	identity: String,
) -> Dictionary:
	var catalog: RefCounted = STARTUP_SAVE_CATALOG.new()
	var agent_store: RefCounted = AGENT_SAVE_STORE.new()
	_expect_ok(catalog.call(
		"configure",
		store,
		"user://tests/town_startup_profile/roundtrip_%s.json" % identity,
		agent_store,
	) as Dictionary, "修复故事可配置生产只读检查器")
	var slot_definitions := [
		{"slotId": slot_id, "displayName": "修复测试"},
		{"slotId": "empty-%s" % identity, "displayName": "空槽位"},
	]
	var inspected := catalog.call("get_catalog", slot_definitions) as Dictionary
	_expect_ok(inspected, "最新修订损坏时只读检查成功")
	var slots := inspected.get("slots", []) as Array
	_expect(not slots.is_empty(), "只读检查返回目标槽位")
	var slot := slots[0] as Dictionary if not slots.is_empty() else {}
	_expect_equal(
		slot.get("state"),
		"recoverable",
		"最新损坏且旧完整配对存在时分类为可修复",
	)
	var inspection_report := (
		slot.get("inspectionReport", {}) as Dictionary
	).duplicate(true)
	var diagnostic_id := String(inspection_report.get("diagnosticId", ""))
	inspection_report.erase("diagnosticId")
	_expect_equal(
		inspection_report,
		{
			"version": 1,
			"slotId": slot_id,
			"classification": "older_complete_revision_available",
			"errorCode": "SESSION_SAVE_REFERENCE_HASH_MISMATCH",
			"latestEvidenceRevision": 3,
			"latestCompleteRevision": 2,
			"repairable": true,
		},
		"只读检查报告只保留制定计划所需的证据",
	)
	_expect(diagnostic_id.begins_with("SAVE-"), "只读检查报告提供稳定诊断编号")
	var plan := slot.get("recoveryPlan", {}) as Dictionary
	_expect_equal(
		plan.get("action"),
		"restore_complete_pair_and_publish",
		"只读检查给出恢复完整配对并发布新修订的计划",
	)
	_expect_equal(plan.get("sourceSaveRevision"), 2, "修复计划固定异步完整来源修订")
	_expect_equal(plan.get("damagedSaveRevision"), 3, "修复计划记录损坏修订证据")
	return {
		"catalog": catalog,
		"slotDefinitions": slot_definitions,
		"slot": slot,
		"plan": plan,
	}


func _verify_recovery_publication(
	service: RefCounted,
	store: RefCounted,
	recovery_case: Dictionary,
	damaged_reference: String,
	damaged_world: Dictionary,
) -> Dictionary:
	var plan := recovery_case.get("plan", {}) as Dictionary
	_expect(service.has_method("execute_recovery_plan"), "会话服务提供确认后的修复执行入口")
	var unconfirmed := service.call("execute_recovery_plan", plan, {}) as Dictionary
	_expect_equal(
		unconfirmed.get("errorCode"),
		"SESSION_SAVE_RECOVERY_PLAN_INVALID",
		"没有对应玩家确认时不执行修复计划",
	)
	var confirmation := {
		"confirmed": true,
		"planId": String(plan.get("planId", "")),
	}
	var slot := recovery_case.get("slot", {}) as Dictionary
	var repaired := service.call(
		"execute_recovery_plan",
		plan,
		confirmation,
		{"residentMessages": slot.get("residentMessages", [])},
	) as Dictionary
	_expect_ok(repaired, "确认后将恢复状态发布为新的完整修订")
	var receipt := repaired.get("repairReceipt", {}) as Dictionary
	_expect_equal(receipt.get("sourceSaveRevision"), 2, "修复回执记录异步恢复来源")
	_expect_equal(receipt.get("publishedSaveRevision"), 4, "修复不覆盖原档而是发布修订 4")
	_expect_equal(
		receipt.get("rebuiltDerivedData"),
		["manifest_index", "session_config_projection", "startup_summary"],
		"安全修复会通过正式发布重建索引、配置投影和启动摘要",
	)
	var repeated := service.call(
		"execute_recovery_plan",
		plan,
		confirmation,
	) as Dictionary
	_expect_equal(
		repeated.get("errorCode"),
		"SESSION_SAVE_RECOVERY_PLAN_INVALID",
		"同一修复计划不能重复发布新修订",
	)
	_expect_equal(
		(store.call(
			"read_reference",
			damaged_reference,
			String(damaged_world.get("snapshot_sha256", "")),
		) as Dictionary).get("errorCode"),
		"SESSION_SAVE_REFERENCE_HASH_MISMATCH",
		"修复后原损坏证据仍保持不变",
	)
	var catalog := recovery_case.get("catalog") as RefCounted
	var repaired_catalog := catalog.call(
		"get_catalog",
		recovery_case.get("slotDefinitions", []),
	) as Dictionary
	_expect_ok(repaired_catalog, "修复完成后可重新执行启动检查")
	var repaired_slots := repaired_catalog.get("slots", []) as Array
	_expect(not repaired_slots.is_empty(), "修复后启动检查返回目标槽位")
	var repaired_slot := (
		repaired_slots[0] as Dictionary
		if not repaired_slots.is_empty()
		else {}
	)
	_expect_equal(repaired_slot.get("state"), "healthy", "再次启动时新的完整修订成为当前存档")
	_expect_equal(
		repaired_slot.get("recoveryPlan"),
		{},
		"再次启动不再重复生成同一修复计划",
	)
	return (repaired.get("context", {}) as Dictionary).duplicate(true)


func _wait_for_async_save(service: RefCounted) -> Dictionary:
	for _index in 600:
		var result := service.call("poll_create_save_async") as Dictionary
		if not bool(result.get("pending", false)):
			return result
		await process_frame
	return {
		"ok": false,
		"errorCode": "SESSION_ASYNC_SAVE_TEST_TIMEOUT",
		"retryable": true,
	}


func _identities(bindings: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for binding: Dictionary in bindings:
		result.append({
			"residentId": String(binding.get("residentId", "")),
			"residentName": String(binding.get("residentName", "")),
		})
	return result


func _saved_bindings(bindings: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for binding: Dictionary in bindings:
		var llm := binding.get("llmBinding", {}) as Dictionary
		result.append({
			"residentId": String(binding.get("residentId", "")),
			"llmBinding": {
				"mode": String(llm.get("mode", "")),
				"providerId": String(llm.get("providerId", "")),
				"modelId": String(llm.get("modelId", "")),
			},
		})
	return result


func _resident_names(identities: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for identity: Dictionary in identities:
		result.append(String(identity.get("residentName", "")))
	return result


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file = null
	return parsed as Dictionary if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _write_text(path: String, content: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errorCode": "TEST_FILE_WRITE_FAILED"}
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file = null
	return {
		"ok": error == OK,
		"errorCode": "" if error == OK else "TEST_FILE_WRITE_FAILED",
	}


func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(
		bool(result.get("ok", false)),
		"%s（%s）" % [message, result.get("errorCode", "")],
	)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s；实际=%s，预期=%s" % [message, actual, expected])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
	for _index in 5:
		await process_frame
	await create_timer(0.3, true, false, true).timeout
	if _failures.is_empty():
		print("SESSION_SAVE_CONTINUE_ROUNDTRIP_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		printerr("SESSION_SAVE_CONTINUE_ROUNDTRIP_FAIL: %s" % failure)
	quit(1)
