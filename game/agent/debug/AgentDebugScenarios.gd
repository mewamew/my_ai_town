class_name AgentDebugScenarios
extends RefCounted


const SCENARIOS := [
	{"id": "basic", "title": "基础决定"},
	{"id": "action_result", "title": "动作结果闭环"},
	{"id": "memory", "title": "记忆整理"},
	{"id": "continuous_actions", "title": "连续动作结果与记忆"},
]


func list() -> Array[Dictionary]:
	return SCENARIOS.duplicate(true)


func initialization() -> Dictionary:
	return {
		"me": {
			"resident_id": "resident-lin-lan",
			"attributes": {
				"name": "林岚",
				"gender": "男",
				"age": 32,
				"desire": "把手艺做好",
				"personality": "话少，慢热",
				"speech": "说话简短",
			},
			"social_state": {
				"home": "林岚家",
				"job": "木匠",
				"workplace": "工作坊",
			},
		},
		"residents": [
			{
				"resident_id": "resident-tang-xiao-man",
				"name": "唐小满",
				"gender": "女",
				"age": 29,
				"job": "摆杂货摊的",
				"home": "唐小满家",
				"workplace": "市集",
			},
		],
		"places": [
			{
				"name": "广场",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "碰头、闲坐和聚集的地方",
			},
			{
				"name": "工作坊",
				"type": "铺面",
				"owner": null,
				"owner_resident_id": null,
				"summary": "做木工的地方",
			},
		],
	}


func initialization_for(resident_id: String) -> Dictionary:
	if resident_id == "resident-lin-lan":
		return initialization()
	if resident_id != "resident-tang-xiao-man":
		return {}
	return {
		"me": {
			"resident_id": "resident-tang-xiao-man",
			"attributes": {
				"name": "唐小满",
				"gender": "女",
				"age": 29,
				"desire": "把杂货摊经营好",
				"personality": "爽快，观察细致",
				"speech": "说话直接但不刻薄",
			},
			"social_state": {
				"home": "唐小满家",
				"job": "摆杂货摊的",
				"workplace": "市集",
			},
		},
		"residents": [
			{
				"resident_id": "resident-lin-lan",
				"name": "林岚",
				"gender": "男",
				"age": 32,
				"job": "木匠",
				"home": "林岚家",
				"workplace": "工作坊",
			},
		],
		"places": initialization()["places"].duplicate(true),
	}


func wake_packet(
	decision_id: String = "debug-1",
	day: int = 1,
	clock: String = "08:10",
) -> Dictionary:
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": {"day": day, "clock": clock, "period": "上午"},
			"weather": "小雨",
			"me": {
				"doing": "站在广场上",
				"current_action": null,
				"body": {"困": "不困", "饿": "不饿", "累": "不累"},
			},
			"nearby": [
				{
					"resident_id": "resident-tang-xiao-man",
					"name": "唐小满",
					"doing": "站在公告栏旁边",
				},
			],
			"place": {
				"name": "广场",
				"props": [{"name": "长椅", "verbs": ["歇着"]}],
			},
			"conversation": null,
		},
		"events": [],
		"action_results": [],
	}


func wake_packet_for(
	resident_id: String,
	decision_id: String,
	day: int = 1,
	clock: String = "08:10",
) -> Dictionary:
	var packet := wake_packet(decision_id, day, clock)
	if resident_id == "resident-lin-lan":
		return packet
	if resident_id != "resident-tang-xiao-man":
		return {}
	packet["snapshot"]["me"]["doing"] = "在广场整理随身货物"
	packet["snapshot"]["nearby"] = [{
		"resident_id": "resident-lin-lan",
		"name": "林岚",
		"doing": "站在公告栏旁边",
	}]
	return packet


func sequence(scenario_id: String) -> Array[Dictionary]:
	match scenario_id:
		"basic":
			return [wake_packet()]
		"action_result":
			var first := wake_packet("debug-1", 1, "08:10")
			var second := wake_packet("debug-2", 1, "08:20")
			second["snapshot"]["me"]["current_action"] = {
				"action_id": "fake-debug-1",
				"type": "待着",
				"line": "先看看周围的情况",
			}
			second["action_results"] = [{
				"action_id": "fake-debug-1",
				"status": "completed",
				"reason": "林岚观察完广场，世界系统确认动作完成。",
				"time": {"day": 1, "clock": "08:18", "period": "上午"},
			}]
			return [first, second]
		"memory":
			var packets: Array[Dictionary] = []
			for index in 4:
				var packet := wake_packet(
					"memory-%d" % (index + 1),
					2,
					"08:%02d" % (10 + index * 5),
				)
				packet["events"] = [{
					"event_id": "memory-event-%d" % (index + 1),
					"type": "有人来了" if index % 2 == 0 else "有人走了",
					"who_resident_id": "resident-tang-xiao-man",
					"who": "唐小满",
					"time": packet["snapshot"]["time"].duplicate(true),
				}]
				packets.append(packet)
			return packets
		"continuous_actions":
			return _continuous_action_sequence()
	return []


func organized_memory() -> Dictionary:
	return {
		"important_memories": (
			"第1天上午，我连续观察广场，并经历了完成、拒绝、中断和替代的世界结果。"
			+ "唐小满几次在旁说明公告栏和木架的情况，这些结果都需要按实际经过记住。"
		),
		"relationships": "唐小满：她持续提供明确情况，我开始重视她的提醒。",
		"current_thoughts": "先确认广场和木架的真实情况，再决定下一步。",
		"long_term_goals": "把手艺做好，也让镇上的人觉得我可靠。",
		"short_term_goals": "之后向唐小满确认公告栏旁发生的事情。",
	}


func duplicate_continuous_wake() -> Dictionary:
	var packet := wake_packet("continuous-6", 1, "09:10")
	packet["action_results"] = [{
		"action_id": "fake-continuous-1",
		"status": "completed",
		"reason": "林岚观察完广场，唐小满确认公告栏旁没有危险。",
		"time": {"day": 1, "clock": "08:20", "period": "上午"},
	}]
	packet["events"] = [{
		"event_id": "continuous-event-1",
		"type": "有人来了",
		"who_resident_id": "resident-tang-xiao-man",
		"who": "唐小满",
		"time": {"day": 1, "clock": "08:20", "period": "上午"},
	}]
	return packet


func _continuous_action_sequence() -> Array[Dictionary]:
	var packets: Array[Dictionary] = [wake_packet("continuous-1", 1, "08:10")]
	var statuses := ["completed", "rejected", "interrupted", "replaced"]
	var reasons := [
		"林岚观察完广场，唐小满确认公告栏旁没有危险。",
		"唐小满提醒木架仍未固定，世界拒绝把检查记作完成。",
		"唐小满过来说明市集急需帮忙，观察动作因此中断。",
		"世界用前往工作坊检查木架替代了继续留在广场的动作。",
	]
	for index in statuses.size():
		var packet := wake_packet(
			"continuous-%d" % (index + 2),
			1,
			"08:%02d" % (20 + index * 10),
		)
		packet["action_results"] = [{
			"action_id": "fake-continuous-%d" % (index + 1),
			"status": statuses[index],
			"reason": reasons[index],
			"time": packet["snapshot"]["time"].duplicate(true),
		}]
		packet["events"] = [{
			"event_id": "continuous-event-%d" % (index + 1),
			"type": "有人来了" if index % 2 == 0 else "有人走了",
			"who_resident_id": "resident-tang-xiao-man",
			"who": "唐小满",
			"time": packet["snapshot"]["time"].duplicate(true),
		}]
		packets.append(packet)
	return packets
