extends "res://tests/support/TownWorldTestCase.gd"
## diag_undercover_runtime.gd — 真实运行验证卧底期限机制
## 启动世界 → 注入3卧底 → 推进到第6天23:59 → 验证1个卧底被处决
## 场景B: 无辜全灭警察失败公告(幂等: 只发一次)
## 运行: Godot --headless --path game --script res://tests/diag_undercover_runtime.gd

const UNDERCOVER_IDS: Array[String] = [
	"resident_xie_mian_01",
	"resident_qiao_yiming_01",
	"resident_hanako_01",
]
const CIVILIAN_ID := "resident_lin_lan_01"


func _initialize() -> void:
	print("===== 卧底期限机制 运行时验证 =====")
	_verify_execution_on_day6()
	_verify_police_failed_flag()
	_finish_suite("UNDERCOVER_RUNTIME_PASS")


func _verify_execution_on_day6() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "undercover runtime opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	# fixture 无卧底居民, 注入3个(带生命周期), 否则期限机制不激活
	_inject_undercover(world, "resident_xie_mian_01", "谢眠", "乐师")
	_inject_undercover(world, "resident_qiao_yiming_01", "乔一鸣", "店员")
	_inject_undercover(world, "resident_hanako_01", "花子", "住客")
	# 记录第1天卧底存活数
	var alive_day1 := _count_alive(world, UNDERCOVER_IDS)
	_expect_equal(alive_day1, 3, "第1天3个卧底存活")
	# 推进到第6天23:59 (check_deadline 每天23:59检查, 第6天应处决1个卧底)
	# 注意 advance 参数是"真实秒", 1 秒=1 游戏分钟; 旧测试误写 5*1440*60
	# (=432000 分钟=300 天) 导致推进耗时数分钟, 卡死误判。
	var env: Object = world.get("_environment")
	var current := int(env.call("get_absolute_minute"))
	var target_minute := 6 * 1440 + 1439
	var delta := target_minute - current
	var advance_result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(advance_result.get("ok"), true, "advance 到第6天成功 (%s)" % str(advance_result.get("errorCode", "")))
	# 读取当前 day (环境无 get_day, 用绝对分钟换算)
	var day := int(env.call("get_absolute_minute")) / 1440
	print("  推进后 day=%d" % day)
	# 处决后卧底存活数应为 2(第6天处决1个)
	var alive_after := _count_alive(world, UNDERCOVER_IDS)
	print("  第6天后卧底存活=%d" % alive_after)
	_expect_equal(alive_after, 2, "第6天处决1个卧底后剩2个")
	world.call("stop")


func _verify_police_failed_flag() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "undercover police fail opening")
	var world: RefCounted = WORLD.new()
	world.call("start", data, opening)
	# 直接调用失败公告(第一次应发公告)
	world.call("_undercover_declare_police_failed", 6)
	var count1 := _count_announcements_containing(world, "彻底失败")
	# 第二次调用应被 flag 拦截(不再发)
	world.call("_undercover_declare_police_failed", 7)
	var count2 := _count_announcements_containing(world, "彻底失败")
	print("  失败公告数: 首次=%d 二次=%d" % [count1, count2])
	_expect_equal(count1, 1, "第一次调用发出失败公告")
	_expect_equal(count2, 1, "第二次调用被 flag 拦截, 不重复发公告")
	_expect_equal(bool(world.get("_undercover_police_failed_declared")), true, "失败声明 flag 置位")
	world.call("stop")


## 注入测试用卧底: 进入 residents/_resident_order + 初始化生命周期(同 diag_role_skills 范式)。
func _inject_undercover(
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
			"personality": "卧底",
			"speech": "测试用",
			"interests": [],
			"customInterests": [],
		},
		"profileAttributes": {"name": resident_name},
		"socialState": {
			"job": job,
			"home": "卧底据点",
			"workplace": "卧底据点",
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


func _count_alive(world: RefCounted, ids: Array[String]) -> int:
	var count := 0
	for id in ids:
		if world.call("_resident_is_alive", String(id)):
			count += 1
	return count


func _count_announcements_containing(world: RefCounted, needle: String) -> int:
	var count := 0
	for value: Variant in world.call("get_announcements") as Array:
		if not value is Dictionary:
			continue
		if String((value as Dictionary).get("text", "")).contains(needle):
			count += 1
	return count
