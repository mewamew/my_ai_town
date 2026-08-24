extends "res://tests/support/TownWorldTestCase.gd"
## diag_bed_ownership.gd — 验证睡觉活动可用性（新架构 TownActivityScalars）
## 官方拆分后可用性语义: 仅当精力过低(需要睡眠)时睡觉选项可用; 不困时禁用
## SLEEP_NOT_NEEDED。本地旧版"只能睡自己的床"的床归属校验不在新架构的
## 可用性层实现(睡觉选项按家生成/执行期校验), 见迁移方案文档。

const ACTIVITY_AVAILABILITY := preload(
	"res://world/runtime/activity/TownActivityAvailabilityRuntime.gd"
)


func _initialize() -> void:
	print("===== 睡觉活动可用性 验证 =====")
	# 场景A: 困(energy=20) → 睡觉可用
	var sleepy := {"activityState": {"energy": 20}}
	var opt_a := _make_sleep_option("北街一号住宅")
	ACTIVITY_AVAILABILITY.apply_sleep(sleepy, opt_a)
	print("  困倦时 床可用=%s" % str(opt_a.get("available", true)))
	_expect_equal(bool(opt_a.get("available", true)), true, "困倦时睡觉可用")
	# 场景B: 不困(energy=80) → 禁用 SLEEP_NOT_NEEDED
	var rested := {"activityState": {"energy": 80}}
	var opt_b := _make_sleep_option("北街一号住宅")
	ACTIVITY_AVAILABILITY.apply_sleep(rested, opt_b)
	print("  不困时 床可用=%s reason=%s" % [str(opt_b.get("available", true)), str(opt_b.get("disabledReason", ""))])
	_expect_equal(bool(opt_b.get("available", true)), false, "不困时睡觉禁用")
	_expect_equal(String(opt_b.get("disabledReason", "")), "SLEEP_NOT_NEEDED", "禁用原因=SLEEP_NOT_NEEDED")
	# 场景C: 非睡觉活动不受 apply_sleep 影响
	var opt_c := {
		"activityId": "activity_dining_collect_meal",
		"label": "取餐",
		"placeId": "杂货铺",
		"available": true,
	}
	ACTIVITY_AVAILABILITY.apply_sleep(rested, opt_c)
	_expect_equal(bool(opt_c.get("available", true)), true, "非睡觉活动不受影响")
	_finish_suite("BED_OWNERSHIP_PASS")


func _make_sleep_option(place: String) -> Dictionary:
	return {
		"activityId": "activity_home_sleep",
		"label": "睡觉",
		"placeId": place,
		"available": true,
	}
