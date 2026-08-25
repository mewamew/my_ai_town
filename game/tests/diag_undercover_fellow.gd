extends "res://tests/support/TownWorldTestCase.gd"
## diag_undercover_fellow.gd — 验证卧底不杀同伙：
## 1) 选项注入: 卧底对同伙(其他卧底)不注入 assassinate/attack, 对普通居民正常注入
## 2) 执行侧: _prepare_assassination_action 拒绝同伙目标, 普通目标正常通过
## 运行: Godot --headless --path game --script res://tests/diag_undercover_fellow.gd

const XIE_ID := "resident_xie_mian_01"
const QIAO_ID := "resident_qiao_yiming_01"
const LIN_ID := "resident_lin_lan_01"
const CIVILIAN_ID := "resident_lin_lan_01"

const SPACE := "town_outdoor"
const REGION := "outdoor_plaza_01"


func _initialize() -> void:
	print("===== 卧底不杀同伙 验证 =====")
	_verify_fellow_excluded()
	_finish_suite("UNDERCOVER_FELLOW_PASS")


func _verify_fellow_excluded() -> void:
	var data := _build_data()
	var opening := _garden_opening(data, "undercover fellow opening")
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect_equal(started.get("ok"), true, "world starts")
	if started.get("ok") != true:
		return
	_advance_to_minute_of_day(world, 1200)  # 夜间 20:00, 暗杀可用
	# 注入两个卧底(谢眠/乔一鸣), 都进入 residents/order/生命周期
	_inject_role_resident(world, XIE_ID, "谢眠", "乐师")
	_inject_role_resident(world, QIAO_ID, "乔一鸣", "商贩")
	var residents: Dictionary = world.call("residents")
	# 三人同户外区域: 谢眠(100,100) 乔一鸣(120,100) 林岚(200,100)
	_place(residents, XIE_ID, Vector2(100, 100))
	_place(residents, QIAO_ID, Vector2(120, 100))
	_place(residents, LIN_ID, Vector2(200, 100))
	var xie := residents[XIE_ID] as Dictionary
	# 1) 选项注入: 谢眠视角
	var decorated: Array = world.call(
		"_decorate_conflict_tension_options",
		XIE_ID,
		xie,
		[],
	) as Array
	print("  谢眠注入选项: %d 个" % decorated.size())
	var has_assassinate_lin := false
	var has_fellow_option := false
	for v in decorated:
		var o := v as Dictionary
		var kind := String(o.get("kind", ""))
		var target_id := String(o.get("target_resident_id", ""))
		var tname := String(o.get("target_resident_name", ""))
		print("    kind=%s target=%s(%s)" % [kind, tname, target_id])
		if target_id == QIAO_ID and (kind == "assassinate" or kind == "attack"):
			has_fellow_option = true
		if kind == "assassinate" and target_id == LIN_ID:
			has_assassinate_lin = true
	_expect_equal(has_assassinate_lin, true, "对普通居民(林岚)正常注入 assassinate")
	_expect_equal(has_fellow_option, false, "对同伙(乔一鸣)不注入 assassinate/attack")
	# 2) 执行侧: 直接提交同伙目标被拒, 普通目标通过
	var qiao_reject: Dictionary = world.call(
		"_prepare_assassination_action",
		XIE_ID,
		xie,
		{"target_resident_id": QIAO_ID, "line": "去串个门"},
	)
	print("  同伙目标提交: ok=%s errors=%s" % [
		str(qiao_reject.get("ok")),
		str(qiao_reject.get("errors", [])),
	])
	_expect_equal(qiao_reject.get("ok"), false, "执行侧拒绝同伙目标")
	var errors := qiao_reject.get("errors", []) as Array
	var has_fellow_msg := false
	for e in errors:
		if String(e).contains("同伙"):
			has_fellow_msg = true
	_expect_equal(has_fellow_msg, true, "拒绝文案含\"同伙\"")
	var lin_ok: Dictionary = world.call(
		"_prepare_assassination_action",
		XIE_ID,
		xie,
		{"target_resident_id": LIN_ID, "line": "夜深了, 借一步说话"},
	)
	print("  普通目标提交: ok=%s" % str(lin_ok.get("ok")))
	_expect_equal(lin_ok.get("ok"), true, "普通居民目标正常通过")
	world.call("stop")


## 把居民移到指定户外位置(只改字典, 保持 order/生命周期不变)
func _place(residents: Dictionary, resident_id: String, pos: Vector2) -> void:
	var r: Variant = residents.get(resident_id)
	if not r is Dictionary:
		_expect(false, "%s 存在" % resident_id)
		return
	(r as Dictionary)["spaceId"] = SPACE
	(r as Dictionary)["regionId"] = REGION
	(r as Dictionary)["currentPlace"] = "中心广场"
	(r as Dictionary)["position"] = pos
	(r as Dictionary)["currentAction"] = {}


## 注入测试用角色: 进入 residents/_resident_order + 初始化生命周期
## (范式同 diag_role_skills.gd _inject_role_resident)
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


func _advance_to_minute_of_day(world: RefCounted, target_minute: int) -> void:
	var env: Object = world.get("_environment")
	var current := int(env.call("get_absolute_minute"))
	var minute_of_day := posmod(current, 1440)
	var delta := target_minute - minute_of_day
	if delta <= 0:
		delta += 1440
	var result := world.call("advance", float(delta)) as Dictionary
	_expect_equal(result.get("ok"), true, "advance %d 分钟 ok" % delta)
