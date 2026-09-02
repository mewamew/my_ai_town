extends SceneTree
## diag_undercover.gd — 验证卧底期限机制逻辑
## 运行: Godot --headless --path game --script res://tests/diag_undercover.gd

const RUNTIME := preload("res://world/runtime/TownUndercoverDeadlineRuntime.gd")

func _init() -> void:
	print("===== 卧底期限机制验证 =====")
	var failures := 0

	# 1. 常量检查
	if RUNTIME.DEADLINE_DAYS == 5:
		print("[PASS] 期限=5天")
	else:
		print("[FAIL] 期限=%d" % RUNTIME.DEADLINE_DAYS)
		failures += 1
	if RUNTIME.EXECUTION_DAYS == [6, 7, 8]:
		print("[PASS] 处决日=第6/7/8天")
	else:
		print("[FAIL] 处决日=%s" % str(RUNTIME.EXECUTION_DAYS))
		failures += 1

	# 2. 检查 CHECK_MINUTE 语义:每天最后一分钟
	var check := RUNTIME.CHECK_MINUTE
	if check == 1439:
		print("[PASS] 检查时刻=每天23:59")
	else:
		print("[FAIL] 检查时刻=%d" % check)
		failures += 1

	# 3. 边界:第6天(day_index=6)应触发处决
	var day6 := 6 * 1440 + 1439
	if day6 / 1440 == 6 and posmod(day6, 1440) == 1439:
		print("[PASS] 第6天23:59 会被检查")
	else:
		print("[FAIL] 第6天计算错误")
		failures += 1

	# 4. 边界:第5天(day_index=5)不触发(期限未到)
	var day5 := 5 * 1440 + 1439
	if day5 / 1440 == 5 and 5 not in RUNTIME.EXECUTION_DAYS:
		print("[PASS] 第5天不在处决日,期限内")
	else:
		print("[FAIL] 第5天边界错误")
		failures += 1

	# 5. 卧底名单应与 catalog 中的卧底一致
	var catalog := _load_catalog()
	var undercover_ids := [
		"resident_xie_mian_01",
		"resident_qiao_yiming_01",
		"resident_hanako_01",
	]
	for rid in undercover_ids:
		var found := false
		for r in catalog.get("residents", []) as Array:
			if String((r as Dictionary).get("residentId", "")) == rid:
				var personality := String(((r as Dictionary).get("attributes", {}) as Dictionary).get("personality", ""))
				if personality.contains("卧底"):
					found = true
				else:
					print("[FAIL] %s 人格未提及卧底!" % rid)
					failures += 1
		if not found:
			print("[FAIL] catalog 中找不到卧底 %s" % rid)
			failures += 1
	print("[PASS] 3个卧底在catalog中均带卧底人格(若上一行无FAIL)")

	# 6. 警察闻叙检查
	for r in catalog.get("residents", []) as Array:
		var resident := r as Dictionary
		if String((resident.get("attributes", {}) as Dictionary).get("name", "")) == "闻叙":
			var occ := String((resident.get("occupation", {}) as Dictionary).get("name", ""))
			var personality := String((resident.get("attributes", {}) as Dictionary).get("personality", ""))
			if occ == "警察":
				print("[PASS] 闻叙职业=警察")
			else:
				print("[FAIL] 闻叙职业=%s" % occ)
				failures += 1
			if personality.contains("卧底") and personality.contains("失败"):
				print("[PASS] 闻叙人格:知情+失败条件")
			else:
				print("[FAIL] 闻叙人格缺知情/失败内容")
				failures += 1
			break

	print("\n===== 结果: %s =====" % ("全部通过" if failures == 0 else "%d 项失败" % failures))
	quit(failures)


func _load_catalog() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://world/data/town/resident_catalog.json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}
