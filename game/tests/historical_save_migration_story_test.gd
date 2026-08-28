extends SceneTree


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
const AGENT_STORE := preload(
	"res://agent/lifecycle/AgentSaveStore.gd"
)
const STARTUP_CATALOG := preload(
	"res://world/presentation/session/TownStartupSaveCatalog.gd"
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
const COMPATIBILITY := preload(
	"res://world/presentation/session/TownSaveCompatibilityRegistry.gd"
)
const SCHEMA_REGISTRY := preload(
	"res://world/presentation/session/TownSaveSchemaRegistry.gd"
)

const EMPTY_SLOT_ID := "historical-empty-slot"
const FIRST_REVISION := 1
const ACTIVITY_MIGRATION_ID := "2026-08-12-public-dining-day-routine"
const PLACE_SERVICE_OWNER_MIGRATION_ID := (
	"2026-08-24-place-service-owner-backfill"
)
const AGENT_SHOP_OWNER_MIGRATION_ID := (
	"2026-08-24-shop-owner-derived-from-occupation"
)

var _failures: Array[String] = []
var _checks := 0
var _release_id := "beta2"
var _slot_id := "roundtrip-slot-beta2"
var _session_id := "roundtrip-session-beta2"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	var requested_release := OS.get_environment(
		"AI_TOWN_HISTORICAL_FIXTURE_ID",
	).strip_edges()
	if not requested_release.is_empty():
		_release_id = requested_release
	if _release_id not in ["beta1", "beta2", "beta3", "beta4", "beta5", "beta6"]:
		_expect(false, "存档兼容故事只接受 beta1 至 beta6")
		_finish()
		return
	_slot_id = "roundtrip-slot-%s" % _release_id
	_session_id = "roundtrip-session-%s" % _release_id
	var requested_slot_id := OS.get_environment(
		"AI_TOWN_HISTORICAL_SLOT_ID",
	).strip_edges()
	var requested_session_id := OS.get_environment(
		"AI_TOWN_HISTORICAL_SESSION_ID",
	).strip_edges()
	if not requested_slot_id.is_empty():
		_slot_id = requested_slot_id
	if not requested_session_id.is_empty():
		_session_id = requested_session_id
	if _release_id == "beta6":
		_expect_ok(_mark_fixture_as_current_release(), "beta6 样本写入当前发行标记")
	var store: RefCounted = STORE.new()
	var catalog: RefCounted = STARTUP_CATALOG.new()
	_expect_ok(
		catalog.call("configure", store, "user://town_startup_profile.json", AGENT_STORE.new()) as Dictionary,
		"启动存档目录可配置",
	)
	var slot_definitions := [
		{"slotId": _slot_id, "displayName": "历史存档"},
		{"slotId": EMPTY_SLOT_ID, "displayName": "空槽位"},
	]
	var startup := catalog.call("get_catalog", slot_definitions) as Dictionary
	_expect_ok(startup, "%s 存档可由正式启动目录发现" % _release_id)
	_expect_equal(startup.get("continueAvailable"), true, "%s 存档可继续" % _release_id)
	var slot := startup.get("continueSlot", {}) as Dictionary
	_expect_equal(slot.get("state"), "healthy", "旧格式不会被误判为坏档")
	_expect_equal(slot.get("agentIntegrity"), "agent_snapshot_verified", "World 与 Agent 完整对通过检查")
	var agent_slot_path := "user://agent_saves/%s/slot.json" % _slot_id
	var original_agent_slot := _read_json(agent_slot_path)
	var future_agent_slot := original_agent_slot.duplicate(true)
	future_agent_slot["format_version"] = 4
	_expect_ok(_write_json(agent_slot_path, future_agent_slot), "可构造未来 Agent 版本证据")
	var future_catalog := catalog.call("get_catalog", slot_definitions) as Dictionary
	_expect_ok(future_catalog, "未来 Agent 版本仍可只读列入目录")
	var future_slot := (future_catalog.get("slots", []) as Array)[0] as Dictionary
	_expect_equal(future_slot.get("state"), "read_only", "未来 Agent 版本不判为坏档")
	_expect_equal(
		future_slot.get("errorCode"),
		"SAVE_VERSION_NEWER_THAN_SUPPORTED",
		"未来 Agent 版本返回稳定只读错误",
	)
	_expect_equal(
		(future_slot.get("recoveryPlan", {}) as Dictionary).is_empty(),
		true,
		"未来 Agent 版本不会生成坏档修复计划",
	)
	_expect_ok(_write_json(agent_slot_path, original_agent_slot), "恢复历史 Agent 版本证据")
	startup = catalog.call("get_catalog", slot_definitions) as Dictionary
	slot = startup.get("continueSlot", {}) as Dictionary
	var manifest_path := (
		"user://town_session_saves/slots/%s/manifests/%020d.json"
		% [_slot_id, FIRST_REVISION]
	)
	var original_manifest := _read_json(manifest_path)
	var future_manifest := original_manifest.duplicate(true)
	future_manifest["schema_version"] = 4
	_expect_ok(_write_json(manifest_path, future_manifest), "可构造未来 manifest 版本证据")
	var future_manifest_catalog := catalog.call("get_catalog", slot_definitions) as Dictionary
	_expect_ok(future_manifest_catalog, "未来 manifest 可按外层版本只读列入目录")
	var future_manifest_slot := (
		future_manifest_catalog.get("slots", []) as Array
	)[0] as Dictionary
	_expect_equal(future_manifest_slot.get("state"), "read_only", "未来 manifest 不判为坏档")
	_expect_equal(
		future_manifest_slot.get("errorCode"),
		"SAVE_VERSION_NEWER_THAN_SUPPORTED",
		"未来 manifest 返回稳定只读错误",
	)
	_expect_equal(
		(future_manifest_slot.get("recoveryPlan", {}) as Dictionary).is_empty(),
		true,
		"未来 manifest 不读取当前 World 结构，也不生成修复计划",
	)
	_expect_ok(_write_json(manifest_path, original_manifest), "恢复历史 manifest 版本证据")
	startup = catalog.call("get_catalog", slot_definitions) as Dictionary
	slot = startup.get("continueSlot", {}) as Dictionary
	var session_config := (slot.get("sessionConfig", {}) as Dictionary).duplicate(true)
	var identities := (session_config.get("residentIdentities", []) as Array).duplicate(true)
	_expect_equal(identities.size(), 15, "历史样本保留全部居民")

	var provider_host := Node.new()
	provider_host.name = "HistoricalSaveProviderHost"
	root.add_child(provider_host)
	var provider_service: RefCounted = PROVIDER_SERVICE.new()
	_expect_ok(provider_service.call("configure", {
		"capabilityMode": "development",
		"source": "placeholder",
		"allowFake": true,
		"providerConfigs": {},
	}, provider_host) as Dictionary, "离线模型服务可用于历史存档恢复")

	var first := await _prepare_runtime(
		store,
		provider_service,
		provider_host,
		session_config,
		identities,
		FIRST_REVISION,
	)
	var upgrade_service := first.get("service") as RefCounted
	var blocked_discovery := slot.duplicate(true)
	var blocked_evidence := (
		slot.get("compatibilityEvidence", {}) as Dictionary
	).duplicate(true)
	blocked_evidence["activitySourceFingerprint"] = "unknown-fingerprint"
	blocked_discovery["compatibility"] = COMPATIBILITY.detect_release(
		blocked_evidence,
	)
	var blocked := upgrade_service.call(
		"restore_discovered_revision",
		blocked_discovery,
		_read_json("res://world/data/town/town_world.json"),
		identities,
		first.get("gateway"),
		{"slotDefinitions": slot_definitions, "residentMessages": []},
		catalog,
	) as Dictionary
	_expect_equal(blocked.get("ok"), false, "生产恢复入口拒绝未知版本组合")
	_expect_equal(blocked.get("readOnly"), true, "拒绝结果保持只读")

	var upgraded := upgrade_service.call(
		"restore_discovered_revision",
		slot,
		_read_json("res://world/data/town/town_world.json"),
		identities,
		first.get("gateway"),
		{
			"slotDefinitions": slot_definitions.duplicate(true),
			"residentMessages": slot.get("residentMessages", []),
		},
		catalog,
	) as Dictionary
	_expect_ok(upgraded, "%s 存档可通过正式继续入口恢复" % _release_id)
	var is_current_release := _release_id == "beta6"
	_expect_equal(
		upgraded.get("changed", false),
		false if is_current_release else true,
		"当前版本不迁移，旧版本明确发布升级修订",
	)
	_expect_equal(
		(upgraded.get("context", {}) as Dictionary).get("save_revision"),
		1 if is_current_release else 2,
		"正式入口保持当前修订或发布升级修订",
	)
	if is_current_release:
		_expect_equal(
			upgraded.get("migrationReceipt", {}),
			{},
			"原生 beta6 继续游戏不产生迁移回执",
		)
		_expect_ok(
			(first.get("runtime") as Node).call(
				"complete_restored_session",
				upgraded.get("context", {}),
			) as Dictionary,
			"原生 beta6 恢复结果可提交给运行时",
		)
	else:
		var first_migration := upgraded.get("migrationReceipt", {}) as Dictionary
		_expect(
			(first_migration.get("applied", []) as Array).has(
				ACTIVITY_MIGRATION_ID,
			),
			"beta1/2 首次恢复明确报告活动迁移",
		) if _release_id in ["beta1", "beta2"] else _expect(
			not (first_migration.get("applied", []) as Array).has(
				ACTIVITY_MIGRATION_ID,
			),
			"beta3 至 beta5 不重复执行已完成的活动迁移",
		)
		_expect(
			(first_migration.get("applied", []) as Array).has(
				PLACE_SERVICE_OWNER_MIGRATION_ID,
			),
			"首次恢复明确报告地点服务协调者迁移",
		)
		_expect(
			(first_migration.get("applied", []) as Array).has(
				AGENT_SHOP_OWNER_MIGRATION_ID,
			),
			"首次恢复明确报告 Agent 铺面负责人迁移",
		)
		_expect_equal(
			(
				(first_migration.get("moduleReceipts", {}) as Dictionary)
				.get("resident_payload", {}) as Dictionary
			).get("applied"),
			[AGENT_SHOP_OWNER_MIGRATION_ID],
			"Agent 迁移回执保持独立模块和版本",
		)
	var first_world: RefCounted = first.get("world")
	var before_time := first_world.call("get_time") as Dictionary
	_expect_ok(first_world.call("advance", 1.0) as Dictionary, "升级后的世界可继续推进")
	_expect(first_world.call("get_time") != before_time, "升级后产生可观察的时间变化")
	var played_revision := await _save_restored(first, session_config, identities)
	_expect_equal(
		played_revision,
		2 if is_current_release else 3,
		"继续游玩后发布下一份成对修订",
	)
	var upgraded_config := session_config.duplicate(true)
	upgraded_config["saveRelease"] = COMPATIBILITY.current_release()
	var current_catalog := catalog.call("get_catalog", slot_definitions) as Dictionary
	_expect_ok(current_catalog, "升级后可从生产目录重新取得版本证据")
	var current_slot := current_catalog.get("continueSlot", {}) as Dictionary
	var repeated := upgrade_service.call("upgrade_revision", {
		"context": {
			"slot_id": _slot_id,
			"session_id": _session_id,
			"save_revision": played_revision,
		},
		"releaseEvidence": (
			current_slot.get("compatibilityEvidence", {}) as Dictionary
		).duplicate(true),
		"sessionConfig": (
			current_slot.get("sessionConfig", {}) as Dictionary
		).duplicate(true),
		"worldData": _read_json("res://world/data/town/town_world.json"),
		"residentIdentities": identities.duplicate(true),
		"agentHydrator": first.get("gateway"),
	}, {
		"slotDefinitions": slot_definitions.duplicate(true),
		"residentMessages": [],
	}, catalog) as Dictionary
	_expect_ok(repeated, "当前版本再次交给升级器仍返回成功")
	_expect_equal(repeated.get("changed"), false, "第二次升级不再写入新修订")
	await _release_runtime(first)
	var reopened_catalog := catalog.call("get_catalog", slot_definitions) as Dictionary
	_expect_ok(reopened_catalog, "运行时释放后启动目录可重新读取升级结果")
	var reopened_slot := reopened_catalog.get("continueSlot", {}) as Dictionary
	_expect_equal(reopened_slot.get("state"), "healthy", "升级后启动目录保持健康")
	_expect_equal(
		(reopened_slot.get("summary", {}) as Dictionary).get("saveRevision"),
		played_revision,
		"启动目录选择升级后的最新修订",
	)

	var saved_snapshot := _read_world_snapshot(store, _slot_id, _session_id, played_revision)
	_expect_equal(
		(saved_snapshot.get("state", {}) as Dictionary).size(),
		27,
		"升级后存档只保留 beta6 的 27 个 World 分区",
	)
	var saved_state := saved_snapshot.get("state", {}) as Dictionary
	_expect_equal(
		(saved_state.get("activityRuntime", {}) as Dictionary).get("sourceFingerprint"),
		SCHEMA_REGISTRY.ACTIVITY_SOURCE_FINGERPRINT_AFTER_UNSTAFFED_PUBLIC_PLACE_ACCESS,
		"升级后写入当前活动指纹",
	)
	_expect_equal(
		(saved_state.get("travelerRelations", {}) as Dictionary).get("schemaVersion"),
		1,
		"缺失的旅行者关系按当前格式重建",
	)

	var reopened := await _prepare_runtime(
		store,
		provider_service,
		provider_host,
		upgraded_config,
		identities,
		played_revision,
	)
	var reopened_restore := _restore_prepared(
		reopened,
		played_revision,
		identities,
	)
	_expect_ok(reopened_restore, "升级后存档重建运行时仍可恢复")
	var second_migration := (
		(reopened_restore.get("commitReceipt", {}) as Dictionary)
		.get("migrationReceipt", {}) as Dictionary
	)
	_expect_equal(second_migration.get("applied"), [], "第二次恢复不再重复迁移")
	var reopened_revision := await _save_restored(reopened, upgraded_config, identities)
	_expect_equal(
		reopened_revision,
		played_revision + 1,
		"新 Runtime 重开后可再次成对保存",
	)
	var resaved_state := (
		_read_world_snapshot(store, _slot_id, _session_id, reopened_revision)
		.get("state", {}) as Dictionary
	)
	_expect_equal(
		resaved_state.get("activityRuntime"),
		saved_state.get("activityRuntime"),
		"第二次保存不再改变活动迁移结果",
	)
	_expect_equal(
		resaved_state.get("travelerRelations"),
		saved_state.get("travelerRelations"),
		"第二次保存不再改变重建的旅行者关系",
	)
	_expect_agent_snapshots_equal(played_revision, reopened_revision)
	await _release_runtime(reopened)
	provider_host.queue_free()
	_finish()


func _prepare_runtime(
	store: RefCounted,
	provider_service: RefCounted,
	provider_host: Node,
	session_config: Dictionary,
	identities: Array,
	revision: int,
) -> Dictionary:
	var gateway: Node = GATEWAY.new()
	var gateway_config := session_config.duplicate(true)
	gateway_config.merge({
		"slotId": _slot_id,
		"saveRevision": revision,
		"restorePending": true,
		"capabilityMode": "formal",
		"formalReady": true,
	}, true)
	_expect_ok(
		gateway.call("configure_session", gateway_config, provider_service, provider_host) as Dictionary,
		"历史存档 Agent 网关可配置",
	)
	var runtime: Node = TOWN_RUNTIME_SCENE.instantiate()
	_expect_ok(runtime.call("configure_agent_gateway", gateway) as Dictionary, "恢复网关可注入小镇")
	var runtime_config := gateway_config.duplicate(true)
	runtime_config.merge({
		"mode": "continue",
		"connectedResidents": _resident_names(identities),
		"source": "runtime",
		"providerFormalReady": true,
		"internalPlaytest": false,
		"internalLivePlaytest": false,
		"requireAgentGateway": true,
		"avatarInitialMode": "observer",
	}, true)
	_expect_ok(runtime.call("configure_session", runtime_config) as Dictionary, "继续游戏运行时可配置")
	root.add_child(runtime)
	await _wait_frames(5)
	_expect_ok(runtime.call("get_startup_result") as Dictionary, "继续游戏场景完成挂载")
	var world: RefCounted = runtime.call("get_world_runtime")
	var gate: RefCounted = RUNTIME_GATE.new()
	_expect_ok(gate.call("configure", runtime) as Dictionary, "恢复事务锁可配置")
	var coordinator: RefCounted = COORDINATOR.new()
	_expect_ok(coordinator.call(
		"configure",
		store,
		world,
		gateway.call("get_agent_save_participant"),
		gate,
	) as Dictionary, "成对存档协调器可配置")
	var service: RefCounted = SESSION_UI_SERVICE.new()
	_expect_ok(service.call(
		"configure",
		runtime,
		world,
		gateway.call("get_agent_save_participant"),
		runtime_config,
	) as Dictionary, "生产会话服务可配置通用升级入口")
	return {
		"runtime": runtime,
		"gateway": gateway,
		"world": world,
		"coordinator": coordinator,
		"service": service,
	}


func _restore_prepared(
	prepared: Dictionary,
	revision: int,
	identities: Array,
) -> Dictionary:
	var restored := (prepared.get("coordinator") as RefCounted).call(
		"restore_revision",
		_slot_id,
		_session_id,
		revision,
		_read_json("res://world/data/town/town_world.json"),
		identities,
		prepared.get("gateway"),
	) as Dictionary
	if restored.get("ok") == true:
		_expect_ok(
			(prepared.get("runtime") as Node).call(
				"complete_restored_session",
				restored.get("context", {}),
			) as Dictionary,
			"恢复结果可提交给小镇运行时",
		)
	return restored


func _save_restored(restored: Dictionary, session_config: Dictionary, identities: Array) -> int:
	var next_config := session_config.duplicate(true)
	next_config["mode"] = "continue"
	next_config["saveRelease"] = COMPATIBILITY.current_release()
	var saved := (restored.get("coordinator") as RefCounted).call("save", {
		"slotId": _slot_id,
		"sessionId": _session_id,
		"residentIdentities": identities.duplicate(true),
		"sessionConfig": next_config,
		"residentMessages": [],
	}) as Dictionary
	_expect_ok(saved, "升级后的 World 与 Agent 可成对保存")
	return int((saved.get("context", {}) as Dictionary).get("save_revision", -1))


func _read_world_snapshot(store: RefCounted, slot_id: String, session_id: String, revision: int) -> Dictionary:
	var discovered := store.call("list_published", slot_id) as Dictionary
	for value: Variant in discovered.get("manifests", []) as Array:
		var manifest := value as Dictionary
		if (
			String(manifest.get("session_id", "")) == session_id
			and int(manifest.get("save_revision", 0)) == revision
		):
			var world := (manifest.get("components", {}) as Dictionary).get("world", {}) as Dictionary
			var loaded := store.call(
				"read_reference",
				String(world.get("snapshot_ref", "")),
				String(world.get("snapshot_sha256", "")),
			) as Dictionary
			_expect_ok(loaded, "升级后的 World 快照可按哈希重读")
			return (loaded.get("value", {}) as Dictionary).duplicate(true)
	_expect(false, "找不到升级后发布的 World 快照")
	return {}


func _expect_agent_snapshots_equal(first_revision: int, second_revision: int) -> void:
	var agent_store: RefCounted = AGENT_STORE.new()
	var first := agent_store.call("load_snapshot", {
		"slot_id": _slot_id,
		"session_id": _session_id,
		"save_revision": first_revision,
	}) as Dictionary
	var second := agent_store.call("load_snapshot", {
		"slot_id": _slot_id,
		"session_id": _session_id,
		"save_revision": second_revision,
	}) as Dictionary
	_expect_ok(first, "首次升级后的 Agent 快照可重读")
	_expect_ok(second, "第二次保存后的 Agent 快照可重读")
	var first_payloads := first.get("resident_payloads", {}) as Dictionary
	var second_payloads := second.get("resident_payloads", {}) as Dictionary
	var first_ids := first_payloads.keys()
	var second_ids := second_payloads.keys()
	first_ids.sort()
	second_ids.sort()
	_expect_equal(second_ids, first_ids, "第二次保存保持同一居民集合")
	for resident_id: Variant in first_ids:
		_expect_equal(
			second_payloads.get(resident_id),
			first_payloads.get(resident_id),
			"第二次保存不改变居民 %s 的 Agent 载荷" % resident_id,
		)


func _release_runtime(value: Dictionary) -> void:
	var runtime: Node = value.get("runtime")
	if is_instance_valid(runtime):
		runtime.queue_free()
	await _wait_frames(4)


func _resident_names(identities: Array) -> Array[String]:
	var names: Array[String] = []
	for value: Variant in identities:
		names.append(String((value as Dictionary).get("residentName", "")))
	return names


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _mark_fixture_as_current_release() -> Dictionary:
	var revision_text := "%020d" % FIRST_REVISION
	var revision_root := (
		"user://town_session_saves/slots/%s/sessions/%s/revisions/%s"
		% [_slot_id, _session_id, revision_text]
	)
	var config_path := "%s/session_config.json" % revision_root
	var config := _read_json(config_path)
	if config.is_empty():
		return {"ok": false, "errorCode": "TEST_SESSION_CONFIG_MISSING"}
	config["saveRelease"] = COMPATIBILITY.current_release()
	var written := _write_json(config_path, config)
	if written.get("ok") != true:
		return written
	var config_sha256 := _sha256_file(config_path)
	if config_sha256.is_empty():
		return {"ok": false, "errorCode": "TEST_SESSION_CONFIG_HASH_FAILED"}
	var manifest_path := (
		"user://town_session_saves/slots/%s/manifests/%s.json"
		% [_slot_id, revision_text]
	)
	var manifest := _read_json(manifest_path)
	if manifest.is_empty():
		return {"ok": false, "errorCode": "TEST_MANIFEST_MISSING"}
	manifest["session_config_sha256"] = config_sha256
	return _write_json(manifest_path, manifest)


func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(file.get_buffer(file.get_length())) != OK:
		return ""
	return hashing.finish().hex_encode()


func _write_json(path: String, value: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errorCode": "TEST_FILE_WRITE_FAILED"}
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var write_error := file.get_error()
	file = null
	return {
		"ok": write_error == OK,
		"errorCode": "" if write_error == OK else "TEST_FILE_WRITE_FAILED",
	}


func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect_ok(result: Dictionary, message: String) -> void:
	_expect(bool(result.get("ok", false)), "%s（%s）" % [message, result.get("errorCode", "")])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s；实际=%s，预期=%s" % [message, actual, expected])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for _index in 5:
		await process_frame
	if _failures.is_empty():
		print("HISTORICAL_SAVE_MIGRATION_STORY_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		printerr("HISTORICAL_SAVE_MIGRATION_STORY_FAIL: %s" % failure)
	quit(1)
