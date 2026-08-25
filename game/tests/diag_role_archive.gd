extends "res://tests/support/TownWorldTestCase.gd"
## 角色请求留档(警察/卧底)机制验证:
## DecisionExecution 对目标居民的每个模型请求, 把提示词(messages)与最终决策 JSON
## 成对写入 <root>/<时间戳>_<居民id>_<决策id前段>.json; 非目标居民不写。
## 探针只验证归档机制(装配与角色集合由 gateway configure_session 注入)。

const POLICE_ID := "resident_wen_xu_01"
const CIVILIAN_ID := "resident_lin_lan_01"

const PROMPT_COMPILER := preload("res://agent/prompt/AgentPromptCompiler.gd")
const DECISION_EXECUTION := preload("res://agent/DecisionExecution.gd")

var _archive_root := "user://tests/role-archive"


## 假 Provider: 直接同步返回一份合法决策(继续当前动作)
class FakeArchiveProvider:
	extends RefCounted

	func request_decision(model_request: Dictionary, on_complete: Callable) -> void:
		on_complete.call({
			"ok": true,
			"decision": {
				"decision_id": String(model_request.get("_agent_request_id", "")),
				"handling": "replace_current",
				"action": {
					"action_id": "role-archive-1",
					"type": "待着",
					"line": "稍等片刻。",
				},
			},
		})

	func cancel_request(_request_id: String) -> bool:
		return true

	func cancel_all_requests() -> int:
		return 0


func _initialize() -> void:
	print("===== 角色请求留档(警察/卧底) 验证 =====\n")
	_verify_archive_mechanism()
	_finish_suite("ROLE_ARCHIVE_PASS")


func _verify_archive_mechanism() -> void:
	var abs_root := ProjectSettings.globalize_path(_archive_root)
	if DirAccess.dir_exists_absolute(abs_root):
		for f: String in DirAccess.get_files_at(abs_root):
			DirAccess.remove_absolute(abs_root.path_join(f))
	else:
		DirAccess.make_dir_recursive_absolute(abs_root)

	var data := _build_data()
	var opening := _garden_opening(data, "role archive opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	_inject_role_resident(world, POLICE_ID, "闻叙", "警察")

	# —— 目标居民(警察闻叙): 留档 1 条 ——
	world.call("_schedule_decision", POLICE_ID, false)
	var wake := _take_wake_by_id(world, POLICE_ID)
	_expect(not wake.is_empty(), "闻叙的 wake 可取到")
	if wake.is_empty():
		world.call("stop")
		return
	var init: Dictionary = world.call("get_agent_initialization", POLICE_ID)
	_expect(not init.is_empty(), "闻叙的 agent 初始化可取到")
	if init.is_empty():
		world.call("stop")
		return
	var execution: RefCounted = DECISION_EXECUTION.new(
		FakeArchiveProvider.new(),
		PROMPT_COMPILER.new(init, "res://prompts"),
	)
	execution.configure_role_archive(true, [POLICE_ID], _archive_root)
	var completed := {"done": false}
	execution.request_decision(
		init,
		wake,
		"",
		{},
		func(payload: Dictionary) -> void:
			completed["done"] = true
			completed["payload"] = payload,
	)
	_expect(bool(completed["done"]), "目标居民决策回调到达")
	if not bool(completed["done"]):
		world.call("stop")
		return
	var payload := completed["payload"] as Dictionary
	if not bool(payload.get("ok", false)):
		print("  决策校验错误: %s" % JSON.stringify(payload.get("errors", [])))
	_expect(bool(payload.get("ok", false)), "fake provider 决策通过契约校验")
	var files := DirAccess.get_files_at(abs_root)
	_expect(files.size() == 1, "目标居民留档写 1 个文件(实际 %d)" % files.size())
	if files.size() != 1:
		world.call("stop")
		return
	var text := FileAccess.get_file_as_string(abs_root.path_join(files[0]))
	var parsed: Variant = JSON.parse_string(text)
	_expect(parsed is Dictionary, "留档文件是合法 JSON")
	if not parsed is Dictionary:
		world.call("stop")
		return
	var record := parsed as Dictionary
	_expect_equal(String(record.get("schema", "")), "agent-decision-role-archive", "schema")
	_expect_equal(String(record.get("resident_id", "")), POLICE_ID, "resident_id")
	# 注入居民的 init.me.name 缺失(注入副作用) -> fallback 为 resident_id; 真实游戏 init 含名字。
	_expect(not String(record.get("resident_name", "")).is_empty(), "resident_name 非空")
	var messages := record.get("messages", []) as Array
	_expect(not messages.is_empty(), "提示词 messages 已归档(%d 条)" % messages.size())
	_expect_equal(
		String(record.get("request_id", "")),
		String(wake.get("decision_id", "")),
		"request_id 对应 decision_id",
	)
	_expect(bool(record.get("ok", false)), "留档记录 ok=true")
	var decision := record.get("decision", {}) as Dictionary
	_expect_equal(
		String((decision.get("action", {}) as Dictionary).get("type", "")),
		"待着",
		"留档 decision 为最终决策 JSON",
	)

	# —— 非目标居民(林岚): 不写盘 ——
	world.call("_schedule_decision", CIVILIAN_ID, false)
	var other_wake := _take_wake_by_id(world, CIVILIAN_ID)
	var before_count := DirAccess.get_files_at(abs_root).size()
	if not other_wake.is_empty():
		var other_init: Dictionary = world.call(
			"get_agent_initialization",
			CIVILIAN_ID,
		)
		var other_execution: RefCounted = DECISION_EXECUTION.new(
			FakeArchiveProvider.new(),
			PROMPT_COMPILER.new(other_init, "res://prompts"),
		)
		other_execution.configure_role_archive(true, [POLICE_ID], _archive_root)
		var other_done := {"done": false}
		other_execution.request_decision(
			other_init,
			other_wake,
			"",
			{},
			func(_payload: Dictionary) -> void:
				other_done["done"] = true,
		)
		_expect(bool(other_done["done"]), "非目标居民决策正常回调")
		if DirAccess.get_files_at(abs_root).size() == before_count:
			_expect(true, "非目标居民不写留档文件")
		else:
			_expect(false, "非目标居民不应写留档文件")
	else:
		print("  提示: 林岚暂无 pending 决策, 跳过非目标不写盘断言")
	world.call("stop")


## 注入测试用角色(范式同 diag_police_alert.gd / diag_role_skills.gd)
func _take_wake_by_id(world: RefCounted, resident_id: String) -> Dictionary:
	var requests := world.call(
		"take_pending_decision_requests",
		[resident_id],
	) as Array[Dictionary]
	for request in requests:
		if String(request.get("residentId", "")) == resident_id:
			return (request.get("wakePacket", {}) as Dictionary).duplicate(true)
	return {}


## 注入测试用角色(范式同 diag_police_alert.gd / diag_role_skills.gd)
func _inject_role_resident(
	world: RefCounted,
	resident_id: String,
	resident_name: String,
	job: String,
) -> void:
	var residents: Dictionary = world.call("residents")
	if residents.has(resident_id):
		return
	var source := residents.get(CIVILIAN_ID, {}) as Dictionary
	var home_anchor: Dictionary = {}
	if not source.is_empty():
		var lifecycle: Object = world.get("_resident_lifecycle")
		var source_state: Dictionary = lifecycle.call(
			"get_resident_state",
			CIVILIAN_ID,
		)
		home_anchor = (
			source_state.get("homeAnchor", {}) as Dictionary
		).duplicate(true)
	var resident := {
		"residentId": resident_id,
		"attributes": {
			"name": resident_name,
			"gender": "男",
			"age": 30,
			"desire": "测试用",
			"personality": "测试用",
			"speech": "测试用",
			"interests": [],
			"customInterests": [],
		},
		"profileAttributes": {"name": resident_name},
		"socialState": {
			"job": job,
			"home": "诊所",
			"workplace": "诊所",
			"money": 40,
			"reputation": 40,
		},
		"arrivalState": {"status": "arrived"},
		"currentAction": {},
		"doing": "在镇上",
		"body": {"困": "不困", "饿": "不饿", "累": "不累"},
	}
	if not source.is_empty():
		resident["spaceId"] = source.get("spaceId", "town_outdoor")
		resident["regionId"] = source.get("regionId", "")
		resident["currentPlace"] = source.get("currentPlace", "")
		resident["position"] = source.get("position", Vector2.ZERO)
		resident["nearby"] = (source.get("nearby", []) as Array).duplicate()
	residents[resident_id] = resident
	var lifecycle: Object = world.get("_resident_lifecycle")
	var initialized := lifecycle.call(
		"initialize_resident",
		resident_id,
		resident_name,
		home_anchor,
	) as Dictionary
	_expect_equal(initialized.get("ok"), true, "%s 注入生命周期" % resident_name)
	var order: Array = world.resident_order()
	if not order.has(resident_id):
		order.append(resident_id)
