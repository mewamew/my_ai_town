extends SceneTree
## 诊断:居民专属角色规则加载(方案A)。验证身份规则/居民个人规则/无规则三分支。

func _initialize() -> void:
	var cases := [
		{"id": "resident_lin_lan_01", "name": "林岚", "undercover": false, "job": "植物研究员"},
		{"id": "resident_tang_xiaoman_01", "name": "唐小满", "undercover": false, "job": "杂货店主"},
		{"id": "resident_luo_yuan_01", "name": "罗远", "undercover": false, "job": "工匠"},
		{"id": "resident_xu_zhao_01", "name": "许照", "undercover": false, "job": "图书管理员"},
		{"id": "resident_bai_zhi_01", "name": "白芷", "undercover": false, "job": "医生"},
		{"id": "resident_hanako_01", "name": "花子", "undercover": true, "job": "咖啡店店员"},
		{"id": "resident_wen_xu_01", "name": "闻叙", "undercover": false, "job": "警察"},
		{"id": "resident_mi_ya_01", "name": "米芽", "undercover": false, "job": "园艺师"},
	]
	var compiler_script := preload("res://agent/prompt/AgentPromptCompiler.gd")
	var all_pass := true
	for c in cases:
		var init := {
			"me": {
				"resident_id": c.id,
				"attributes": {
					"name": c.name, "gender": "女", "age": 30,
					"desire": "测试欲望", "personality": "测试性格",
					"speech": "测试说话方式", "interests": [], "customInterests": [],
				},
				"social_state": {"home": "家", "job": c.job, "workplace": "工作地"},
				"soul_profile": {},
				"is_undercover": c.undercover,
			},
			"residents": [],
			"places": [],
		}
		var compiler := compiler_script.new(init)
		var baseline := str(compiler.get("_baseline_prompt"))
		var has_role := baseline.contains("<role_rules>")
		print("=== %s(%s) ===" % [c.name, c.id])
		if has_role:
			print("  有 role_rules")
			for line in baseline.split("\n"):
				var t := line.strip_edges()
				if t.begins_with("### "):
					print("    标题: %s" % t)
		else:
			print("  无 role_rules")
		var errors := compiler.get_load_errors() as Array
		if not errors.is_empty():
			all_pass = false
			print("  加载错误: %s" % errors)
		# 断言
		if c.id == "resident_lin_lan_01":
			if not baseline.contains("林岚的为人"): all_pass = false; print("  FAIL: 林岚缺少个人规则")
		elif c.id == "resident_hanako_01":
			if not baseline.contains("卧底行动规则"): all_pass = false; print("  FAIL: 花子缺少卧底规则")
		elif c.id == "resident_xu_zhao_01":
			if not baseline.contains("档案查验"): all_pass = false; print("  FAIL: 许照缺少查验技能规则")
		elif c.id == "resident_bai_zhi_01":
			if not baseline.contains("守诊"): all_pass = false; print("  FAIL: 白芷缺少守诊技能规则")
		elif c.id == "resident_wen_xu_01":
			if not baseline.contains("警察查案规则"): all_pass = false; print("  FAIL: 闻叙缺少警察规则")
		elif c.id == "resident_mi_ya_01":
			if has_role: all_pass = false; print("  FAIL: 米芽不应有 role_rules")
	print("DIAG_ROLE_RULES_%s" % ("PASS" if all_pass else "FAIL"))
	quit()
