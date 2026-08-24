extends SceneTree
## diag_wealth_render.gd — 端到端验证:金钱/声望从开局注入到 prompt 渲染全链路
## 运行: Godot --headless --path game --script res://tests/diag_wealth_render.gd

const PromptCompiler := preload("res://agent/prompt/AgentPromptCompiler.gd")

func _init() -> void:
	print("===== 金钱/声望 端到端链路验证 =====")
	var failures := 0

	# ---- 1. 构造模拟初始化数据(和 TownNewGameOpeningCompiler / _build_agent_initialization 一致) ----
	var initialization := {
		"me": {
			"resident_id": "resident_tang_xiaoman_01",
			"attributes": {
				"name": "唐小满",
				"gender": "女",
				"age": 28,
				"desire": "把生意做大",
				"personality": "泼辣刻薄",
				"speech": "直接",
				"interests": ["interest_collecting_stories"],
			},
			"social_state": {
				"home": "杂货铺后院",
				"job": "杂货店主",
				"workplace": "杂货铺",
				"money": 90,
				"reputation": 45,
			},
		},
		"residents": [
			{
				"resident_id": "resident_xie_mian_01",
				"name": "谢眠",
				"gender": "男",
				"age": 22,
				"job": "乐师",
				"home": "乐师小屋",
				"workplace": "露天戏台",
				"money": 15,
				"reputation": 10,
				"lifecycle_status": "alive",
			},
			{
				"resident_id": "resident_wen_xu_01",
				"name": "闻叙",
				"gender": "男",
				"age": 35,
				"job": "小镇管理者",
				"home": "镇公所",
				"workplace": "镇公所",
				"money": 85,
				"reputation": 85,
				"lifecycle_status": "alive",
			},
		],
		"places": [],
	}

	# ---- 2. 编译 prompt,检查家境/威望是否渲染 ----
	var compiler := PromptCompiler.new(initialization)
	var compile_errors := compiler.get_load_errors()
	if not compile_errors.is_empty():
		print("[FAIL] prompt 加载错误: %s" % compile_errors)
		failures += 1
	var compiled := compiler.compile({}, "")
	var system_content := ""
	var user_content := ""
	for message in compiled.get("messages", []):
		if String(message.get("role", "")) == "system":
			system_content = String(message.get("content", ""))
		else:
			user_content = String(message.get("content", ""))
	var combined := system_content + "\n" + user_content

	# 验证自己(me)的家境
	var checks := [
		["唐小满家境殷实", combined.contains("家境殷实")],
		["唐小满镇上威望较高", combined.contains("镇上威望较高")],
		["谢眠家境拮据", combined.contains("家境拮据")],
		["谢眠镇上威望低下", combined.contains("威望低下")],
		["闻叙镇上威望很高", combined.contains("威望很高")],
	]
	for check in checks:
		if bool(check[1]):
			print("[PASS] %s" % check[0])
		else:
			print("[FAIL] %s — prompt 中未找到!" % check[0])
			failures += 1

	# 打印渲染出的关键行供人工核对
	print("\n--- 渲染出的身份行(节选) ---")
	for line in system_content.split("\n"):
		if line.contains("本人：") or line.contains("家境") or line.contains("威望"):
			print("  " + line)

	# ---- 3. 验证 float 类型兼容性(money=90.0 也应渲染) ----
	print("\n--- 类型兼容性验证(float money) ---")
	var float_init := initialization.duplicate(true)
	(float_init["me"] as Dictionary)["social_state"]["money"] = 90.0
	(float_init["me"] as Dictionary)["social_state"]["reputation"] = 45.0
	var float_compiler := PromptCompiler.new(float_init)
	var float_compiled := float_compiler.compile({}, "")
	var float_content := ""
	for message in float_compiled.get("messages", []):
		if String(message.get("role", "")) == "system":
			float_content = String(message.get("content", ""))
	if float_content.contains("家境殷实"):
		print("[PASS] money=90.0(float) 仍渲染家境殷实")
	else:
		print("[FAIL] money=90.0(float) 未渲染家境 — Godot 存档解析为 float 时会丢失!")
		failures += 1

	print("\n===== 结果: %s =====" % ("全部通过" if failures == 0 else "%d 项失败" % failures))
	quit(failures)
