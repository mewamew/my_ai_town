extends SceneTree


const STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const AGENT_STORE := preload("res://agent/lifecycle/AgentSaveStore.gd")
const MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const RECONCILIATION := preload(
	"res://world/presentation/session/TownSaveReconciliationService.gd"
)
const STARTUP_CATALOG := preload(
	"res://world/presentation/session/TownStartupSaveCatalog.gd"
)
const CONFIRMATION_BUILDER := preload(
	"res://world/presentation/game_flow/GameFlowConfirmationPageBuilder.gd"
)
const FILE_SYSTEM := preload("res://agent/AgentFileSystem.gd")

var _checks := 0
var _failures: Array[String] = []


class FailSecondReconciliationWriteStore:
	extends RefCounted
	var inner: RefCounted
	var write_count := 0
	var failed_once := false

	func _init(value: RefCounted) -> void:
		inner = value

	func begin_slot_transaction(slot_id: Variant) -> Dictionary:
		return inner.call("begin_slot_transaction", slot_id) as Dictionary

	func end_slot_transaction(token: Variant) -> Dictionary:
		return inner.call("end_slot_transaction", token) as Dictionary

	func list_incomplete(slot_id: Variant) -> Dictionary:
		return inner.call("list_incomplete", slot_id) as Dictionary

	func list_published(slot_id: Variant) -> Dictionary:
		return inner.call("list_published", slot_id) as Dictionary

	func read_latest_intent(
		context: Variant,
		kind: Variant,
		intent_id: Variant = "",
	) -> Dictionary:
		return inner.call(
			"read_latest_intent",
			context,
			kind,
			intent_id,
		) as Dictionary

	func read_reference(reference: Variant, sha256: Variant) -> Dictionary:
		return inner.call("read_reference", reference, sha256) as Dictionary

	func read_world_log_snapshot(reference: Variant, sha256: Variant) -> Dictionary:
		return inner.call(
			"read_world_log_snapshot",
			reference,
			sha256,
		) as Dictionary

	func write_intent_stage(
		context: Variant,
		kind: Variant,
		intent_id: Variant,
		stage: Variant,
		payload: Variant = {},
	) -> Dictionary:
		write_count += 1
		if write_count == 2 and not failed_once:
			failed_once = true
			return {
				"ok": false,
				"errorCode": "TEST_RECONCILIATION_WRITE_FAILED",
				"retryable": true,
			}
		return inner.call(
			"write_intent_stage",
			context,
			kind,
			intent_id,
			stage,
			payload,
		) as Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var identity := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store_root := "user://tests/town_session_saves/reconcile_%s" % identity
	var agent_root := "user://agent_save_tests/reconcile_%s" % identity
	var diagnostic_root := "user://tests/save_diagnostics/reconcile_%s" % identity
	var store := STORE.new()
	var agent_store := AGENT_STORE.new()
	_expect_ok(store.configure_test_root(store_root), "事务协调 Store 可配置")
	_expect_ok(agent_store.configure_test_root(agent_root), "事务协调 Agent Store 可配置")
	var service := RECONCILIATION.new()
	_expect_ok(
		service.configure(store, agent_store, diagnostic_root),
		"事务协调服务可配置",
	)

	_test_save_orphan_reconciliation(store, agent_store, service)
	_test_classification_matrix()
	_test_partial_failure_resume(store, agent_store)
	_test_restore_reconciliation(store, agent_store, service, store_root)
	_test_structural_damage_rejected(store, agent_store, service)
	_test_unrepairable_export(store, agent_store, service, diagnostic_root, identity)
	_test_long_path_cleanup(store, service)
	_expect(
		not _tree_contains_file(store_root, "owner.json"),
		"协调完成后不残留事务 owner.json",
	)
	_expect(
		not _tree_contains_suffix(diagnostic_root, ".tmp"),
		"诊断导出完成后不残留临时文件",
	)

	_expect_ok(store.cleanup_test_root(), "事务协调世界测试数据可清理")
	_expect_ok(agent_store.cleanup_test_root(), "事务协调 Agent 测试数据可清理")
	FILE_SYSTEM.remove_tree(diagnostic_root)
	_finish()


func _test_save_orphan_reconciliation(
	store: RefCounted,
	agent_store: RefCounted,
	service: RefCounted,
) -> void:
	var context := _reserve(store, "reconcile-save", "session-save")
	var intent := _begin_intent(store, context, "save")
	_write_stage(store, context, "save", intent, "save_started")
	_write_stage(store, context, "save", intent, "world_candidate_written")
	_write_stage(store, context, "save", intent, "agent_commit_started")
	_expect_ok(
		agent_store.create_new_game(context, _resident_payloads()),
		"可构造已提交但未发布 manifest 的 Agent 快照",
	)
	_write_stage(store, context, "save", intent, "agent_committed")
	var plan := service.inspect("reconcile-save") as Dictionary
	_expect_ok(plan, "可诊断保存中断")
	_expect_equal(plan.get("action"), RECONCILIATION.RECONCILE_ACTION, "完整 Agent 证据允许协调")
	var reopened_service := RECONCILIATION.new()
	_expect_ok(
		reopened_service.configure(store, agent_store),
		"新进程可重新配置事务协调服务",
	)
	_expect_equal(
		reopened_service.execute(plan, {}).get("errorCode"),
		"SESSION_SAVE_RECONCILIATION_PLAN_INVALID",
		"没有玩家确认时不执行协调",
	)
	var reconciled := reopened_service.execute(plan, {
		"confirmed": true,
		"planId": plan.get("planId"),
	}) as Dictionary
	_expect_ok(reconciled, "确认后封口保存中断事务")
	_expect_equal(reconciled.get("sealedIntentCount"), 1, "只封口目标事务")
	_expect_ok(agent_store.load_snapshot(context), "孤立 Agent 快照作为证据保留")
	_expect_equal(
		(store.list_incomplete("reconcile-save") as Dictionary).get("records"),
		[],
		"协调后不再阻塞新存档",
	)
	var repeated := reopened_service.execute(plan, {
			"confirmed": true,
			"planId": plan.get("planId"),
		}) as Dictionary
	_expect_ok(repeated, "同一计划重复执行返回安全结果")
	_expect_equal(repeated.get("changed"), false, "同一计划不会重复写协调记录")
	var next_runtime_service := RECONCILIATION.new()
	_expect_ok(
		next_runtime_service.configure(store, agent_store),
		"再次启动可重新配置协调检查",
	)
	_expect_equal(
		(next_runtime_service.inspect("reconcile-save") as Dictionary).get(
			"items",
			[],
		),
		[],
		"再次启动不会重复提示已处理事务",
	)


func _test_classification_matrix() -> void:
	var cases := [
		["save", "save_started", {}, "pre_agent_cleanup"],
		["save", "world_candidate_written", {}, "pre_agent_cleanup"],
		["save", "agent_commit_started", {}, "agent_commit_uncertain"],
		["save", "agent_commit_uncertain", {}, "agent_commit_uncertain"],
		["save", "agent_committed", {}, "agent_orphan_isolated"],
		["save", "world_committed", {}, "agent_orphan_isolated"],
		["save", "agent_orphan_isolated", {}, "agent_orphan_isolated"],
		["restore", "restore_started", {}, "pre_agent_cleanup"],
		["restore", "restore_world_prepared", {}, "pre_agent_cleanup"],
		["restore", "restore_agent_started", {}, "restore_agent_uncertain"],
		["restore", "restore_agent_commit_started", {}, "restore_agent_uncertain"],
		["restore", "restore_agent_committed", {}, "restore_partial_commit"],
		["restore", "restore_world_committed", {}, "restore_partial_commit"],
		["restore", "transaction_failed", {"stage": "agent_commit"}, "restore_agent_uncertain"],
		["restore", "transaction_failed", {"stage": "post_commit_validation"}, "restore_partial_commit"],
	]
	for case_value: Variant in cases:
		var case := case_value as Array
		var classified := TownSaveJournalStates.classify_incomplete(
			String(case[0]),
			String(case[1]),
			case[2] as Dictionary,
		)
		_expect_equal(
			classified.get("classification"),
			case[3],
			"事务阶段 %s/%s 分类准确" % [case[0], case[1]],
		)


func _test_restore_reconciliation(
	store: RefCounted,
	agent_store: RefCounted,
	service: RefCounted,
	store_root: String,
) -> void:
	var context := _reserve(store, "reconcile-restore", "session-restore")
	var fixture_root := (
		"res://tests/fixtures/historical_saves/beta6/town_session_saves/slots/"
		+ "roundtrip-slot-beta6/sessions/roundtrip-session-beta6/revisions/"
		+ "00000000000000000001"
	)
	var world_snapshot := _read_json("%s/world_snapshot.json" % fixture_root)
	var session_config := _valid_session_config("session-restore")
	var stored := store.write_world_candidate(
		context,
		world_snapshot,
		session_config,
		{
			"schema": "town-world-log-snapshot",
			"schemaVersion": 1,
			"timelineId": "reconcile-timeline",
			"parentTimelineId": "",
			"maxSequence": 0,
			"worldRevision": 1,
			"records": [],
			"readState": {},
		},
	) as Dictionary
	_expect_ok(stored, "恢复中断样本的 World 候选可写入")
	_expect_ok(
		agent_store.create_new_game(context, _resident_payloads()),
		"恢复中断样本的 Agent 配对可写入",
	)
	var manifest := MANIFEST.build(
		context,
		"2026-08-25T00:00:00",
		stored.get("sessionConfigRef"),
		stored.get("sessionConfigSha256"),
		["resident-1"],
		{
			"snapshotRef": stored.get("snapshotRef"),
			"worldRevision": 1,
			"schema": "town-world-save",
			"schemaVersion": 2,
			"worldDataVersion": 4,
			"day": 1,
		},
		stored.get("snapshotSha256"),
		[],
		{
			"snapshotRef": stored.get("worldLogSnapshotRef"),
			"snapshotSha256": stored.get("worldLogSnapshotSha256"),
			"schema": "town-world-log-snapshot",
			"schemaVersion": 1,
			"timelineId": "reconcile-timeline",
			"maxSequence": 0,
			"worldRevision": 1,
		},
	)
	_expect(not manifest.is_empty(), "恢复中断样本 manifest 合法")
	_expect_ok(store.publish_manifest(manifest), "恢复中断样本 manifest 可发布")
	var intent := _begin_intent(store, context, "restore")
	for stage: String in [
		"restore_started",
		"restore_world_prepared",
		"restore_agent_started",
		"restore_agent_hydrated",
		"restore_world_validated",
		"restore_agent_commit_started",
		"restore_agent_committed",
	]:
		_write_stage(store, context, "restore", intent, stage)
	var world_path := "%s/%s" % [store_root, stored.get("snapshotRef", "")]
	var original_world := FileAccess.get_file_as_string(world_path)
	_expect(not original_world.is_empty(), "恢复协调可读取原 World 证据")
	_expect(_write_text(world_path, "{}\n"), "可构造恢复协调中的 World 哈希损坏")
	var damaged_plan := service.inspect("reconcile-restore") as Dictionary
	_expect_equal(damaged_plan.get("action"), RECONCILIATION.EXPORT_ACTION, "World 证据损坏时拒绝协调")
	_expect_equal(
		((damaged_plan.get("items", []) as Array)[0] as Dictionary).get(
			"publishedPairValid",
		),
		false,
		"恢复协调会验证完整发布配对而非只看 manifest",
	)
	_expect(_write_text(world_path, original_world), "恢复协调可还原 World 测试证据")
	var plan := service.inspect("reconcile-restore") as Dictionary
	_expect_ok(plan, "可诊断恢复中断")
	_expect_equal(plan.get("action"), RECONCILIATION.RECONCILE_ACTION, "完整发布配对允许结束旧 Runtime 恢复")
	_expect_ok(service.execute(plan, {
		"confirmed": true,
		"planId": plan.get("planId"),
	}), "恢复中断协调成功")
	_expect_equal(
		(store.list_incomplete("reconcile-restore") as Dictionary).get("records"),
		[],
		"恢复中断不再重复阻塞",
	)
	_expect_ok(agent_store.load_snapshot(context), "协调不会修改已发布 Agent 配对")
	var published := store.list_published("reconcile-restore") as Dictionary
	_expect_equal(
		(published.get("manifests", []) as Array).size()
		+ (published.get("readOnly", []) as Array).size(),
		1,
		"协调不会修改已发布 manifest",
	)


func _test_partial_failure_resume(
	store: RefCounted,
	agent_store: RefCounted,
) -> void:
	for session_id: String in ["session-partial-a", "session-partial-b"]:
		var context := _reserve(store, "reconcile-partial", session_id)
		var intent := _begin_intent(store, context, "save")
		_write_stage(store, context, "save", intent, "save_started")
	var failing_store := FailSecondReconciliationWriteStore.new(store)
	var service := RECONCILIATION.new()
	_expect_ok(
		service.configure(failing_store, agent_store),
		"故障注入协调服务可配置",
	)
	var plan := service.inspect("reconcile-partial") as Dictionary
	_expect_equal((plan.get("items", []) as Array).size(), 2, "同一计划包含两个中断事务")
	var view_model := CONFIRMATION_BUILDER.continue_recovery({
		"summary": {
			"slotId": "reconcile-partial",
			"saveRevision": 1,
			"residentCount": 1,
			"worldRevision": 1,
			"day": 1,
		},
		"recoveryPlan": plan,
		"damageDetails": {},
	}, 1, "reconcile-partial")
	var repair_copy := (
		((view_model.get("data", {}) as Dictionary).get(
			"loadSummary",
			{},
		) as Dictionary).get("copy", {}) as Dictionary
	)
	_expect_equal(repair_copy.get("retryRestore"), "执行修复", "协调确认页显示真实执行动作")
	_expect_equal(repair_copy.get("title"), "完成上次存档事务？", "协调确认页解释事务处理")
	var confirmation := {
		"confirmed": true,
		"planId": plan.get("planId"),
	}
	var failed := service.execute(plan, confirmation) as Dictionary
	_expect_equal(failed.get("errorCode"), "TEST_RECONCILIATION_WRITE_FAILED", "第二项写入失败会准确返回")
	_expect_equal(
		(store.list_incomplete("reconcile-partial") as Dictionary).get(
			"records",
			[],
		).size(),
		1,
		"失败后只保留尚未封口的事务",
	)
	var resumed := service.execute(plan, confirmation) as Dictionary
	_expect_ok(resumed, "同一计划可从部分完成状态继续")
	_expect_equal(resumed.get("alreadySealedIntentCount"), 1, "续跑识别已完成项")
	_expect_equal(resumed.get("sealedIntentCount"), 1, "续跑只写剩余项")
	_expect_equal(
		(store.list_incomplete("reconcile-partial") as Dictionary).get(
			"records",
			[],
		),
		[],
		"故障恢复后不再残留阻塞事务",
	)


func _test_structural_damage_rejected(
	store: RefCounted,
	agent_store: RefCounted,
	service: RefCounted,
) -> void:
	var context := _reserve(store, "reconcile-structural", "session-structural")
	var stored := store.write_world_candidate(
		context,
		{},
		_valid_session_config("session-structural"),
		{
			"schema": "town-world-log-snapshot",
			"schemaVersion": 1,
			"timelineId": "structural-timeline",
			"parentTimelineId": "",
			"maxSequence": 0,
			"worldRevision": 1,
			"records": [],
			"readState": {},
		},
	) as Dictionary
	_expect_ok(stored, "可构造哈希正确但结构损坏的 World")
	_expect_ok(
		agent_store.create_new_game(context, _resident_payloads()),
		"结构损坏样本保留完整 Agent 配对",
	)
	var manifest := MANIFEST.build(
		context,
		"2026-08-25T00:00:00",
		stored.get("sessionConfigRef"),
		stored.get("sessionConfigSha256"),
		["resident-1"],
		{
			"snapshotRef": stored.get("snapshotRef"),
			"worldRevision": 1,
			"schema": "town-world-save",
			"schemaVersion": 2,
			"worldDataVersion": 4,
			"day": 1,
		},
		stored.get("snapshotSha256"),
		[],
		{
			"snapshotRef": stored.get("worldLogSnapshotRef"),
			"snapshotSha256": stored.get("worldLogSnapshotSha256"),
			"schema": "town-world-log-snapshot",
			"schemaVersion": 1,
			"timelineId": "structural-timeline",
			"maxSequence": 0,
			"worldRevision": 1,
		},
	)
	_expect_ok(store.publish_manifest(manifest), "结构损坏样本 manifest 可发布为证据")
	var intent := _begin_intent(store, context, "restore")
	for stage: String in [
		"restore_started",
		"restore_world_prepared",
		"restore_agent_started",
	]:
		_write_stage(store, context, "restore", intent, stage)
	var plan := service.inspect("reconcile-structural") as Dictionary
	_expect_equal(plan.get("action"), RECONCILIATION.EXPORT_ACTION, "哈希正确但 World 结构损坏时拒绝协调")
	_expect_equal(
		((plan.get("items", []) as Array)[0] as Dictionary).get(
			"publishedPairValid",
		),
		false,
		"完整配对检查包含 World 结构校验",
	)
	var catalog := STARTUP_CATALOG.new()
	_expect_ok(catalog.configure(
		store,
		"user://tests/town_startup_profile/reconcile_structural.json",
		agent_store,
	), "单修订损坏可接入启动检查")
	var inspected := catalog.get_catalog([
		{"slotId": "reconcile-structural", "displayName": "单修订损坏"},
		{"slotId": "reconcile-structural-empty", "displayName": "空槽位"},
	]) as Dictionary
	_expect_ok(inspected, "单个损坏修订可完成只读诊断")
	var slot := (inspected.get("slots", []) as Array)[0] as Dictionary
	_expect_equal(slot.get("latestCompleteRevision"), -1, "单个损坏修订没有虚构回退来源")
	_expect_equal(slot.get("diagnosticAvailable"), true, "单个损坏修订只提供诊断导出")


func _test_unrepairable_export(
	store: RefCounted,
	agent_store: RefCounted,
	service: RefCounted,
	diagnostic_root: String,
	identity: String,
) -> void:
	var context := _reserve(store, "reconcile-unsafe", "session-unsafe")
	var intent := _begin_intent(store, context, "save")
	_write_stage(store, context, "save", intent, "save_started")
	_write_stage(store, context, "save", intent, "world_candidate_written")
	_write_stage(store, context, "save", intent, "agent_commit_started")
	var plan := service.inspect("reconcile-unsafe") as Dictionary
	_expect_ok(plan, "证据不足的保存中断仍可诊断")
	_expect_equal(plan.get("action"), RECONCILIATION.EXPORT_ACTION, "无法证明安全时只允许导出")
	var exported := service.export_diagnostic(plan) as Dictionary
	_expect_ok(exported, "不可修复存档可导出去敏诊断")
	_expect(FileAccess.file_exists(String(exported.get("path", ""))), "诊断文件实际存在")
	_expect_equal(
		service.export_diagnostic(plan).get("changed"),
		false,
		"重复导出不会覆盖或制造冲突文件",
	)
	var escaped_plan := plan.duplicate(true)
	escaped_plan["diagnosticId"] = "../outside"
	_expect_equal(
		service.export_diagnostic(escaped_plan).get("errorCode"),
		"SESSION_SAVE_DIAGNOSTIC_PLAN_INVALID",
		"诊断编号不能逃出专用目录",
	)
	_expect_equal(
		(store.list_incomplete("reconcile-unsafe") as Dictionary).get("records", []).size(),
		1,
		"导出诊断不修改原事务证据",
	)
	_expect(String(exported.get("path", "")).begins_with(diagnostic_root), "诊断只写入专用目录")
	var catalog := STARTUP_CATALOG.new()
	_expect_ok(catalog.configure(
		store,
		"user://tests/town_startup_profile/reconcile_%s.json" % identity,
		agent_store,
	), "不可修复槽位可接入正式启动检查")
	var catalog_result := catalog.get_catalog([
		{"slotId": "reconcile-unsafe", "displayName": "诊断测试"},
		{"slotId": "reconcile-empty", "displayName": "空槽位"},
	]) as Dictionary
	_expect_ok(catalog_result, "不可修复槽位可完成只读检查")
	var slots := catalog_result.get("slots", []) as Array
	var slot := slots[0] as Dictionary if not slots.is_empty() else {}
	_expect_equal(slot.get("diagnosticAvailable"), true, "没有完整配对时提供诊断入口")
	var discovery := {
		"summary": {
			"slotId": "reconcile-unsafe",
			"saveRevision": 1,
			"residentCount": 0,
			"worldRevision": -1,
			"day": 0,
		},
		"recoveryPlan": slot.get("recoveryPlan", {}),
		"damageDetails": {},
	}
	var view_model := CONFIRMATION_BUILDER.continue_recovery(
		discovery,
		1,
		"reconcile-unsafe",
	)
	var copy := (
		((view_model.get("data", {}) as Dictionary).get(
			"loadSummary",
			{},
		) as Dictionary).get("copy", {}) as Dictionary
	)
	_expect_equal(copy.get("retryRestore"), "导出诊断", "确认页准确显示导出动作")


func _test_long_path_cleanup(store: RefCounted, service: RefCounted) -> void:
	var suffix := "x".repeat(90)
	var slot_id := "reconcile-long-%s" % suffix
	var session_id := "session-long-%s" % suffix
	var context := _reserve(store, slot_id, session_id)
	var intent := _begin_intent(store, context, "save")
	_write_stage(store, context, "save", intent, "save_started")
	var evidence_path := ProjectSettings.globalize_path(
		"user://tests/town_session_saves/reconcile-placeholder/slots/%s/intents/save/%s"
		% [slot_id, session_id],
	)
	_expect(evidence_path.length() > 260, "长路径样本超过传统 Windows 260 字符边界")
	var plan := service.inspect(slot_id) as Dictionary
	_expect_equal(plan.get("action"), RECONCILIATION.RECONCILE_ACTION, "提交前中断可安全回收")
	_expect_ok(service.execute(plan, {
		"confirmed": true,
		"planId": plan.get("planId"),
	}), "长路径事务锁、日志重读和封口成功")
	_expect_equal(
		(store.list_incomplete(slot_id) as Dictionary).get("records"),
		[],
		"长路径协调后可重新读取",
	)


func _reserve(store: RefCounted, slot_id: String, session_id: String) -> Dictionary:
	var reserved := store.reserve_revision(slot_id, session_id) as Dictionary
	_expect_ok(reserved, "修订号可预留")
	return (reserved.get("context", {}) as Dictionary).duplicate(true)


func _begin_intent(store: RefCounted, context: Dictionary, kind: String) -> String:
	var begun := store.begin_intent(context, kind) as Dictionary
	_expect_ok(begun, "%s 事务日志可创建" % kind)
	return String(begun.get("intentId", ""))


func _write_stage(
	store: RefCounted,
	context: Dictionary,
	kind: String,
	intent: String,
	stage: String,
) -> void:
	_expect_ok(
		store.write_intent_stage(context, kind, intent, stage, {}),
		"%s 日志阶段 %s 可写入" % [kind, stage],
	)


func _resident_payloads() -> Dictionary:
	return {
		"resident-1": {
			"resident_name": "测试居民",
			"payload": "payload".to_utf8_buffer(),
		},
	}


func _valid_session_config(session_id: String) -> Dictionary:
	var fixture_path := (
		"res://tests/fixtures/historical_saves/beta6/town_session_saves/slots/"
		+ "roundtrip-slot-beta6/sessions/roundtrip-session-beta6/revisions/"
		+ "00000000000000000001/session_config.json"
	)
	var fixture_config := _read_json(fixture_path)
	var fixture_bindings := fixture_config.get("residentBindings", []) as Array
	return {
		"mode": "continue",
		"sessionId": session_id,
		"saveRelease": "beta6",
		"openingConfig": (
			fixture_config.get("openingConfig", {}) as Dictionary
		).duplicate(true),
		"residentIdentities": [{
			"residentId": "resident-1",
			"residentName": "测试居民",
		}],
		"residentBindings": [{
			"residentId": "resident-1",
			"llmBinding": (
				((fixture_bindings[0] as Dictionary).get(
					"llmBinding",
					{},
				) as Dictionary).duplicate(true)
			),
		}],
		"connectedResidents": ["测试居民"],
		"worldStartMode": "formal",
		"useLiveModel": true,
		"enablePlayerAvatar": false,
		"enableTestUi": false,
	}


func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file = null
	return error == OK


func _read_json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _tree_contains_file(path: String, target_name: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	for file_name: String in directory.get_files():
		if file_name == target_name:
			return true
	for directory_name: String in directory.get_directories():
		if _tree_contains_file("%s/%s" % [path, directory_name], target_name):
			return true
	return false


func _tree_contains_suffix(path: String, suffix: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	for file_name: String in directory.get_files():
		if file_name.contains(suffix):
			return true
	for directory_name: String in directory.get_directories():
		if (
			directory_name.contains(suffix)
			or _tree_contains_suffix("%s/%s" % [path, directory_name], suffix)
		):
			return true
	return false


func _expect_ok(value: Dictionary, message: String) -> void:
	_expect(bool(value.get("ok", false)), "%s：%s" % [message, value])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s；expected=%s actual=%s" % [message, expected, actual])


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
		print("SAVE_RECONCILIATION_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_RECONCILIATION_FAIL: %s" % failure)
	quit(1)
