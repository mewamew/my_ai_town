extends SceneTree


const BUILDER := preload(
	"res://world/presentation/game_flow/GameFlowConfirmationPageBuilder.gd"
)
const PAGE_SCENE := preload(
	"res://ui/new_game_overwrite/NewGameOverwriteScreen.tscn"
)
const STARTUP_SCENE := preload("res://ui/startup/StartupScreen.tscn")

var _failures: Array[String] = []
var _checks := 0


class FailingRecoveryCatalog:
	extends RefCounted
	var calls := 0

	func get_catalog(_definitions: Array) -> Dictionary:
		calls += 1
		return {
			"ok": false,
			"errorCode": "TEST_REDIAGNOSIS_FAILED",
			"retryable": false,
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var page := PAGE_SCENE.instantiate() as Control
	var view_model := BUILDER.continue_recovery({
		"summary": {
			"slotId": "town-main",
			"sessionId": "recovery-session",
			"saveRevision": 1,
			"residentCount": 15,
			"savedAt": "2026-08-25T12:00:00+08:00",
			"day": 8,
			"worldRevision": 32,
		},
		"damageDetails": {
			"progressRollback": true,
			"damagedSaveRevision": 2,
			"fallbackSaveRevision": 1,
			"damagedSavedAt": "2026-08-25T12:30:00+08:00",
		},
	}, 1, "town-main") as Dictionary
	_expect(page.apply_view_model(view_model), "坏档确认页接受三操作 ViewModel")
	root.add_child(page)
	await process_frame
	_expect_button(page, "CancelButton", "仅返回")
	_expect_button(page, "RetryRestoreButton", "执行修复")
	_expect_button(page, "RediagnoseButton", "重新诊断")
	var overwrite := page.find_child(
		"ConfirmOverwriteButton",
		true,
		false,
	) as Button
	_expect(overwrite != null and not overwrite.visible, "坏档确认页不显示覆盖按钮")

	var intents: Array[String] = []
	page.intent_requested.connect(func(intent: StringName, _payload: Dictionary) -> void:
		intents.append(String(intent))
	)
	_expect(page.debug_request_action("rediagnose"), "重新诊断按钮可以提交操作")
	_expect(_refresh(page, view_model, 2), "重新诊断后页面可以刷新")
	_expect(page.debug_request_action("retryRestore"), "执行修复按钮可以提交操作")
	_expect(_refresh(page, view_model, 3), "执行操作后页面可以刷新")
	_expect(page.debug_request_action("cancel"), "仅返回按钮可以提交操作")
	_expect_equal(
		intents,
		[
			"session.rediagnose_recovery",
			"session.confirm_recovery",
			"session.cancel_continue_recovery",
		],
		"三个按钮分别提交诊断、修复和返回意图",
	)
	page.queue_free()
	await process_frame
	_verify_host_rediagnosis_failure()
	await _verify_host_cancel_refresh()
	_finish()


func _verify_host_rediagnosis_failure() -> void:
	var host := root.get_node_or_null("GameFlowHost")
	_expect(host != null, "重新诊断测试使用真实 GameFlowHost")
	if host == null:
		return
	var original_catalog: Variant = host.get("_startup_save_catalog")
	var catalog := FailingRecoveryCatalog.new()
	var stale_page := PAGE_SCENE.instantiate() as Control
	root.add_child(stale_page)
	host.set("_startup_save_catalog", catalog)
	host.set("_startup_overwrite_page", stale_page)
	host.set("_pending_save_handling_mode", "continue_recovery")
	host.set("_pending_save_handling_origin", "continue")
	host.set("_pending_new_game_discovery", {
		"summary": {"slotId": "town-main"},
	})
	host.call("_rediagnose_continue_recovery")
	_expect_equal(catalog.calls, 1, "重新诊断真实调用启动存档目录")
	_expect(
		host.get("_startup_overwrite_page") == null
		and String((host.get("_last_result") as Dictionary).get("errorCode", ""))
		== "TEST_REDIAGNOSIS_FAILED",
		"重新诊断失败会关闭旧计划，不能继续执行过期修复",
	)
	host.set("_startup_save_catalog", original_catalog)


func _verify_host_cancel_refresh() -> void:
	var host := root.get_node_or_null("GameFlowHost")
	_expect(host != null, "仅返回测试使用真实 GameFlowHost")
	if host == null:
		return
	var startup := STARTUP_SCENE.instantiate() as Control
	root.add_child(startup)
	current_scene = startup
	host.call("_bind_startup", startup)
	await process_frame
	startup.set("_host_request_pending_intent", &"session.continue")
	var stale_page := PAGE_SCENE.instantiate() as Control
	startup.add_child(stale_page)
	host.set("_startup_overwrite_page", stale_page)
	host.set("_pending_save_handling_mode", "continue_recovery")
	host.set("_pending_save_handling_origin", "continue")
	host.call(
		"_on_new_game_overwrite_intent_requested",
		&"session.cancel_continue_recovery",
		{},
	)
	await process_frame
	var snapshot := startup.call("get_route_contract_snapshot") as Dictionary
	_expect(
		not bool(snapshot.get("hostRequestPending", true)),
		"仅返回会清除启动页的旧请求，允许再次继续游戏",
	)
	current_scene = null
	if is_instance_valid(stale_page):
		stale_page.queue_free()
	startup.queue_free()
	await process_frame


func _expect_button(page: Control, node_name: String, copy: String) -> void:
	var button := page.find_child(node_name, true, false) as Button
	_expect(
		button != null
		and button.visible
		and not button.disabled
		and button.text == copy,
		"坏档确认页提供%s按钮" % copy,
	)


func _refresh(page: Control, view_model: Dictionary, revision: int) -> bool:
	var refreshed := view_model.duplicate(true)
	refreshed["revision"] = revision
	return page.apply_view_model(refreshed)


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
		print("SAVE_RECOVERY_CONFIRMATION_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		printerr("SAVE_RECOVERY_CONFIRMATION_FAIL: %s" % failure)
	quit(1)
