extends SceneTree
## diag_wealth_evidence.gd — 用当前存档真实数据验证 prompt 含金钱/声望
## 运行: Godot --headless --path game --script res://tests/diag_wealth_evidence.gd

const PromptCompiler := preload("res://agent/prompt/AgentPromptCompiler.gd")
const SAVE_RESIDENTS_PATH := "res://tests/fixtures/town_residents_from_save.json"

func _init() -> void:
	print("===== 用新档真实数据验证 金钱/声望 进 prompt =====")
	var catalog_text := FileAccess.get_file_as_string(SAVE_RESIDENTS_PATH)
	var catalog := JSON.parse_string(catalog_text) as Dictionary
	if catalog.is_empty():
		print("[FAIL] 存档居民数据读取失败")
		quit(1)
		return
	var residents := catalog.get("residents", []) as Array
	if residents.is_empty():
		print("[FAIL] catalog 无居民")
		quit(1)
		return

	var failures := 0
	var checked := 0
	for resident_value in residents:
		var resident := resident_value as Dictionary
		var social := resident.get("socialState", {}) as Dictionary
		var name := String(resident.get("name", ""))
		if name.is_empty():
			continue
		var resident_id := String(resident.get("residentId", ""))
		var money := int(social.get("money", -1))
		var reputation := int(social.get("reputation", -1))
		if money < 0 or reputation < 0:
			print("[SKIP] %s 无 money/reputation" % name)
			continue
		checked += 1
		# 构建 Agent 初始化(与 TownWorldRuntime._build_agent_initialization 一致)
		var others: Array[Dictionary] = []
		for other_value in residents:
			var other := other_value as Dictionary
			if other.get("residentId", "") == resident_id:
				continue
			var other_social := other.get("socialState", {}) as Dictionary
			others.append({
				"resident_id": String(other.get("residentId", "")),
				"name": String(other.get("name", "")),
				"gender": String(other.get("gender", "")),
				"age": int(other.get("age", 0)),
				"job": String(other_social.get("job", "")),
				"home": String(other_social.get("home", "")),
				"workplace": String(other_social.get("workplace", "")),
				"money": int(other_social.get("money", 40)),
				"reputation": int(other_social.get("reputation", 30)),
				"lifecycle_status": "alive",
			})
		var initialization := {
			"me": {
				"resident_id": resident_id,
				"attributes": {
					"name": name,
					"gender": String(resident.get("gender", "")),
					"age": int(resident.get("age", 0)),
					"desire": "",
					"personality": "",
					"speech": "",
					"interests": [],
				},
				"social_state": {
					"home": String(social.get("home", "")),
					"job": String(social.get("job", "")),
					"workplace": String(social.get("workplace", "")),
					"money": money,
					"reputation": reputation,
				},
			},
			"residents": others,
			"places": [],
		}
		var compiler := PromptCompiler.new(initialization)
		var compiled := compiler.compile({}, "")
		var system_content := ""
		for message in compiled.get("messages", []):
			if String(message.get("role", "")) == "system":
				system_content = String(message.get("content", ""))
		var money_label := _wealth_label(money)
		var rep_label := _reputation_label(reputation)
		var me_money_ok := system_content.contains(name) and system_content.contains("家境%s" % money_label)
		var me_rep_ok := system_content.contains(name) and system_content.contains("威望%s" % rep_label)
		if me_money_ok and me_rep_ok:
			print("[PASS] %-8s 自己: 家境%s/威望%s 已进 prompt" % [name, money_label, rep_label])
		else:
			print("[FAIL] %-8s 家境%s=%s 威望%s=%s" % [name, money_label, me_money_ok, rep_label, me_rep_ok])
			failures += 1
		# 其他居民可见家境计数
		var others_visible := 0
		for line in system_content.split("\n"):
			if line.begins_with("- ") and line.contains("家境"):
				others_visible += 1
		if others_visible < 10:
			print("[WARN] %-8s 其他居民可见家境仅 %d 个" % [name, others_visible])

	print("\n===== 结果: 检查 %d 人, %s =====" % [checked, "全部通过" if failures == 0 else "%d 项失败" % failures])
	quit(failures)


func _wealth_label(money: int) -> String:
	if money >= 80:
		return "殷实"
	elif money >= 55:
		return "宽裕"
	elif money >= 30:
		return "普通"
	return "拮据"


func _reputation_label(reputation: int) -> String:
	if reputation >= 65:
		return "很高"
	elif reputation >= 40:
		return "较高"
	elif reputation >= 20:
		return "一般"
	return "低下"
