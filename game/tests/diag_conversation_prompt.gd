extends SceneTree
## 诊断:居民间对话时 LLM 收到的完整 prompt(system + user)。
## 场景:林岚在中心广场被闻叙搭话,必须答话。

func _initialize() -> void:
	var compiler_script := preload("res://agent/prompt/AgentPromptCompiler.gd")
	var init := {
		"me": {
			"resident_id": "resident_lin_lan_01",
			"attributes": {
				"name": "林岚", "gender": "男", "age": 32,
				"desire": "安静做完自己的项目，不被小镇琐事打断。",
				"personality": "冷淡、怕麻烦、长期睡眠不足，但很有责任感。",
				"speech": "句子短，语气冷淡，抱怨后常给出具体解决办法。",
				"interests": ["interest_plant_research", "interest_reading"],
				"customInterests": ["制作植物标本"],
			},
			"social_state": {
				"home": "南街一号住宅", "job": "植物研究员",
				"workplace": "社区花园", "money": 40, "reputation": 25,
			},
			"soul_profile": {},
			"is_undercover": false,
		},
		"residents": [
			{"resident_id": "resident_wen_xu_01", "name": "闻叙", "gender": "男",
			 "age": 29, "job": "警察", "home": "镇公所", "workplace": "镇公所",
			 "money": 40, "reputation": 30, "lifecycle_status": "alive"},
		],
		"places": [
			{"name": "中心广场", "type": "公共地点", "owner_resident_id": null,
			 "owner": null, "summary": "小镇中央的集会广场，常有公告与人群。",
			 "features": ["公告栏", "长椅"]},
		],
	}
	var wake := {
		"decision_id": "resident_lin_lan_01-g1-10",
		"snapshot": {
			"time": {"day": 2, "clock": "10:30"},
			"weather": "晴天",
			"me": {
				"doing": "刚做完植物记录",
				"body": {"困": "不困", "饿": "有点饿", "累": "不累"},
				"current_action": null,
			},
			"place": {
				"name": "中心广场",
				"destinations": ["社区花园", "南街一号住宅", "公共食堂"],
				"props": [],
				"activities": [],
			},
			"nearby": [
				{"resident_id": "resident_wen_xu_01", "name": "闻叙",
				 "doing": "正在巡逻", "available_for_conversation": true},
			],
			"conversation": {
				"conversation_id": "conv-104",
				"with_resident_id": "resident_wen_xu_01",
				"with": "闻叙",
				"waiting_for": "resident_lin_lan_01",
			},
		},
		"events": [
			{"event_id": "conv-104-t3", "type": "搭话",
			 "conversation_id": "conv-104", "response_required": true,
			 "from": "闻叙", "from_resident_id": "resident_wen_xu_01",
			 "say": "昨晚广场东边的事，你看见了什么？"},
		],
		"action_results": [],
		"social_response_results": [],
	}
	var compiler := compiler_script.new(init)
	var result := compiler.compile(wake, "", "") as Dictionary
	if not bool(result.get("ok", true)):
		print("编译失败:", result)
		quit()
		return
	var messages := result["messages"] as Array
	var system_content := str((messages[0] as Dictionary)["content"])
	var user_content := str((messages[1] as Dictionary)["content"])
	print("==================== SYSTEM ====================")
	print(system_content)
	print("====================== USER ====================")
	print(user_content)
	print("================= END ==================")
	quit()
