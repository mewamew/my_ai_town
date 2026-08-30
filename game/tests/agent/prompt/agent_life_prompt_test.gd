extends "res://tests/agent/support/AgentPromptTestCase.gd"


const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")


func _initialize() -> void:
	var compiler_script := _load_prompt_compiler()
	if compiler_script != null:
		_test_life_and_social_context(compiler_script)
		_test_retry_feedback_is_scoped_to_the_correction(compiler_script)
		_test_interest_labels_are_rendered(compiler_script)
		_test_body_conditions_and_needs_are_rendered(compiler_script)
		_test_social_assignment_context(compiler_script)
		_test_interrogation_talk_targets(compiler_script)
		_test_idle_talk_targets_restored(compiler_script)
		_test_report_phase_police_options(compiler_script)
		_test_police_lead_log_rendered(compiler_script)
	_finish_prompt_test("AGENT_LIFE_PROMPT_PASS")


func _test_report_phase_police_options(compiler_script: Script) -> void:
	# 汇报期警察: 动作列表不能再注入"向警察汇报"(模型照选必被白名单
	# 拒绝, 还出现过警察试图汇报"周既明昨夜行踪可疑"的怪决策)。
	# 警察的唯一合法动作是"待着"(白名单同步放行)。
	var compiler: RefCounted = compiler_script.new(_initialization())
	var police_wake := _wake_packet("report-police-1", "晴天")
	(police_wake.get("snapshot", {}) as Dictionary)["assembly"] = {
		"phase": "report",
		"frozen": true,
		"role": "police",
		"reportPrompt": "汇报正在收集中，警察请等待汇报收齐后开始审讯。",
		"kinds": ["目击", "听到", "怀疑", "不汇报"],
		"reported": true,
	}
	var police_request := compiler.call("compile", police_wake, "") as Dictionary
	var police_actions := (
		(police_request.get("derived_constraints", {}) as Dictionary).get(
			"actions",
			{},
		) as Dictionary
	).keys()
	_expect(
		not police_actions.has("向警察汇报"),
		"汇报期警察动作列表不含向警察汇报: %s" % str(police_actions),
	)
	_expect(
		police_actions.has("待着"),
		"汇报期警察保留待着选项: %s" % str(police_actions),
	)
	var civilian_wake := _wake_packet("report-civilian-1", "晴天")
	(civilian_wake.get("snapshot", {}) as Dictionary)["assembly"] = {
		"phase": "report",
		"frozen": true,
		"reported": false,
		"kinds": ["目击", "听到", "怀疑", "不汇报"],
		"reportPrompt": "请向警察汇报。",
	}
	var civilian_request := compiler.call("compile", civilian_wake, "") as Dictionary
	var civilian_actions := (
		(civilian_request.get("derived_constraints", {}) as Dictionary).get(
			"actions",
			{},
		) as Dictionary
	).keys()
	_expect_equal(
		civilian_actions,
		["向警察汇报"],
		"汇报期平民动作列表只含向警察汇报: %s" % str(civilian_actions),
	)


func _test_police_lead_log_rendered(compiler_script: Script) -> void:
	# 线索已告知账本: 注入 wake 的已告知条目必须渲染进提示词, 并带
	# "不要重复去说"的提醒——终结执念型居民无限重复汇报同一线索。
	var compiler: RefCounted = compiler_script.new(_initialization())
	var wake := _wake_packet("police-lead-1", "晴天")
	(wake.get("snapshot", {}) as Dictionary)["police_lead_log"] = {
		"entries": [
			{
				"day": 2,
				"minute_label": "第2天 08:00",
				"channel": "审讯会汇报",
				"summary": "我听见乔一鸣说看见个黑影……",
			},
		],
	}
	var request := compiler.call("compile", wake, "") as Dictionary
	var user_text := String(
		((request.get("messages", []) as Array)[1] as Dictionary).get(
			"content",
			"",
		),
	)
	_expect(
		user_text.contains("你已告诉过警察的线索")
		and user_text.contains("我听见乔一鸣说看见个黑影")
		and user_text.contains("审讯会汇报"),
		"已告知线索账本渲染进提示词",
	)
	_expect(
		user_text.contains("不要再重复去说"),
		"已告知账本附带不重复提醒",
	)
	# 空账本不渲染任何内容。
	var empty_wake := _wake_packet("police-lead-empty-1", "晴天")
	var empty_request := compiler.call("compile", empty_wake, "") as Dictionary
	var empty_text := String(
		((empty_request.get("messages", []) as Array)[1] as Dictionary).get(
			"content",
			"",
		),
	)
	_expect(
		not empty_text.contains("你已告诉过警察的线索"),
		"空账本不渲染已告知段落",
	)


func _test_idle_talk_targets_restored(compiler_script: Script) -> void:
	# 冻结-解冻不变量: 审讯期"搭话目标合并可审候选"是瞬时叠加, 解冻后
	# (assembly 快照为空)搭话目标必须回到纯 nearby 感知范围——否则远程
	# 提审的宽松规则泄漏到正常时间, 警察平时也能隔空搭话全镇。
	var compiler: RefCounted = compiler_script.new(_initialization())
	var wake := _wake_packet("idle-talk-1", "晴天")
	var snapshot := wake.get("snapshot", {}) as Dictionary
	snapshot["assembly"] = {}  # 解冻后 assembly 快照为空
	var request := compiler.call("compile", wake, "") as Dictionary
	var constraints := request.get("derived_constraints", {}) as Dictionary
	var actions := constraints.get("actions", {}) as Dictionary
	var talk := actions.get("搭话", {}) as Dictionary
	var talk_targets := talk.get("targets", []) as Array
	_expect_equal(
		talk_targets,
		["resident-tang-xiao-man"],
		"解冻后搭话目标恢复为纯 nearby(无审讯候选泄漏): %s" % str(talk_targets),
	)
	# 对应地: 汇报期居民也看不到搭话选项之外的东西(动作裁剪不泄漏)。
	var report_wake := _wake_packet("report-restore-1", "晴天")
	(report_wake.get("snapshot", {}) as Dictionary)["assembly"] = {
		"phase": "report",
		"frozen": true,
		"reported": false,
		"kinds": ["目击", "听到", "怀疑", "不汇报"],
		"reportPrompt": "请向警察汇报。",
	}
	var report_request := compiler.call("compile", report_wake, "") as Dictionary
	var report_constraints := report_request.get("derived_constraints", {}) as Dictionary
	var report_actions := (report_constraints.get("actions", {}) as Dictionary).keys()
	_expect_equal(
		report_actions,
		["向警察汇报"],
		"汇报期动作裁剪只留汇报: %s" % str(report_actions),
	)


func _test_interrogation_talk_targets(compiler_script: Script) -> void:
	# 警察审讯期: 搭话目标必须合并可审候选(远程提审), 不能只有 nearby。
	# 否则 08:00 开会时警察身边人少, 想审的嫌疑人(不在附近)没有搭话
	# 选项也没有 ID, 审讯 5 人额度用不满、身边无人时审讯期卡到兜底超时。
	var compiler: RefCounted = compiler_script.new(_initialization())
	var wake := _wake_packet("interrogation-talk-1", "晴天")
	var snapshot := wake.get("snapshot", {}) as Dictionary
	snapshot["assembly"] = {
		"phase": "interrogation",
		"frozen": true,
		"role": "police",
		"reportSummary": [],
		"interrogationCount": 0,
		"interrogationMax": 5,
		"targets": [
			{"resident_id": "resident-tang-xiao-man", "name": "唐小满"},
			{"resident_id": "resident-lin-lan", "name": "林岚"},
			{"resident_id": "resident-zhou-ning", "name": "周宁"},
		],
		"interrogated": [],
		"prompt": "审讯进行中。",
	}
	var request := compiler.call("compile", wake, "") as Dictionary
	var constraints := request.get("derived_constraints", {}) as Dictionary
	var actions := constraints.get("actions", {}) as Dictionary
	var talk := actions.get("搭话", {}) as Dictionary
	var talk_targets := talk.get("targets", []) as Array
	_expect(
		talk_targets.has("resident-tang-xiao-man")
		and talk_targets.has("resident-lin-lan")
		and talk_targets.has("resident-zhou-ning"),
		"审讯期警察搭话目标含全部可审候选(远程): %s" % str(talk_targets),
	)
	var user_text := String(
		((request.get("messages", []) as Array)[1] as Dictionary).get(
			"content",
			"",
		),
	)
	_expect(
		user_text.contains("可审讯对象"),
		"审讯期警察看到可审讯对象列表",
	)


func _test_life_and_social_context(compiler_script: Script) -> void:
	var compiler: RefCounted = compiler_script.new(_initialization())
	var wake := _wake_packet("life-social-context", "晴天")
	var snapshot := wake.get("snapshot", {}) as Dictionary
	var place := snapshot.get("place", {}) as Dictionary
	place["destinations"] = ["花房咖啡馆", "公共食堂"]
	place["message_recipients"] = [{
		"resident_id": "resident-tang-xiao-man",
		"name": "唐小满",
	}]
	snapshot["life_destination_options"] = [{
		"place_id": "花房咖啡馆",
		"activities": [{
			"activity_id": "activity_cafe_rest",
			"label": "在咖啡馆歇一会儿",
			"interest_match": false,
			"matched_interests": [],
		}],
	}]
	snapshot["known_announcements"] = [{
		"announcement_id": "announcement-1",
		"text": "今晚广场有露天电影。",
		"publisher_resident_id": "resident-tang-xiao-man",
		"acquired_via": "town_bell",
		"active": true,
	}]
	var request := compiler.call("compile", wake, "") as Dictionary
	var user_text := String(
		((request.get("messages", []) as Array)[1] as Dictionary).get(
			"content",
			"",
		),
	)
	_expect(
		user_text.contains("花房咖啡馆：在咖啡馆歇一会儿")
		and user_text.contains("今晚广场有露天电影。"),
		"life options and known announcements enter the decision prompt",
	)
	var constraints := request.get("derived_constraints", {}) as Dictionary
	var actions := constraints.get("actions", {}) as Dictionary
	_expect_equal(
		(actions.get("托人传话", {}) as Dictionary).get("recipients", []),
		["resident-tang-xiao-man"],
		"private-message recipients come from the current World snapshot",
	)
	wake["events"] = [{
		"event_id": "event-announcement-life-1",
		"time": {"day": 1, "clock": "12:00", "period": "中午"},
		"type": "公告发布",
		"announcement_id": "announcement-1",
		"text": "今晚广场有露天电影。",
	}]
	var announcement_request := compiler.call("compile", wake, "") as Dictionary
	var announcement_constraints := (
		announcement_request.get("derived_constraints", {}) as Dictionary
	)
	_expect_equal(
		(announcement_constraints.get("announcement_reactions", {}) as Dictionary).get(
			"source_event_ids",
		),
		["event-announcement-life-1"],
		"newly delivered announcement exposes a required reaction source",
	)


func _test_retry_feedback_is_scoped_to_the_correction(
	compiler_script: Script,
) -> void:
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request := compiler.call(
		"compile",
		_wake_packet("retry-feedback-1", "晴天"),
		"",
		"- action.place 必须来自 snapshot.place.destinations",
	) as Dictionary
	var messages := request.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "retry correction keeps the normal request shape")
	if messages.size() != 2:
		return
	var user_text := String((messages[1] as Dictionary).get("content", ""))
	_expect(
		user_text.contains("<retry_correction>")
		and user_text.contains(
			"action.place 必须来自 snapshot.place.destinations",
		),
		"the second model attempt receives the exact contract correction",
	)
	var ordinary := compiler.call(
		"compile",
		_wake_packet("retry-feedback-2", "晴天"),
		"",
	) as Dictionary
	var ordinary_messages := ordinary.get("messages", []) as Array
	_expect(
		ordinary_messages.size() == 2
		and String(
			(ordinary_messages[1] as Dictionary).get("content", ""),
		).contains("<retry_correction>\n无\n</retry_correction>"),
		"ordinary decisions do not inherit a previous correction",
	)


func _test_interest_labels_are_rendered(compiler_script: Script) -> void:
	var initialization := _initialization()
	var me := initialization.get("me", {}) as Dictionary
	var attributes := (me.get("attributes", {}) as Dictionary).duplicate(true)
	attributes["interests"] = [
		"interest_reading",
		"interest_plant_research",
	]
	attributes["customInterests"] = ["制作植物标本"]
	me["attributes"] = attributes
	initialization["me"] = me
	var compiler: RefCounted = compiler_script.new(initialization)
	var wake := _wake_packet("interest-prompt-1", "晴天")
	wake["snapshot"]["place"]["activities"] = [{
		"activity_id": "activity_library_research",
		"label": "查阅资料",
		"interest_match": true,
		"matched_interests": ["阅读", "植物研究"],
	}]
	var request := compiler.call(
		"compile",
		wake,
		"",
	) as Dictionary
	var messages := request.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "interest prompt compiles normally")
	if messages.size() != 2:
		return
	var system_text := String(
		(messages[0] as Dictionary).get("content", ""),
	)
	_expect(
		system_text.contains("兴趣：阅读、植物研究、制作植物标本"),
		"stable resident profile renders catalog and custom interest labels",
	)
	_expect(
		not system_text.contains("interest_reading"),
		"stable resident profile does not expose internal interest ids",
	)
	_expect(
		system_text.contains("自定义兴趣没有对应活动时"),
		"stable behavior rules explain the custom-interest boundary",
	)
	var user_text := String(
		(messages[1] as Dictionary).get("content", ""),
	)
	_expect(
		user_text.contains("符合兴趣：阅读、植物研究"),
		"current legal activities expose their interest match to the Agent",
	)


func _test_body_conditions_and_needs_are_rendered(
	compiler_script: Script,
) -> void:
	var wake := _wake_packet("condition-prompt-1", "晴天")
	wake["snapshot"]["me"]["conditions"] = [{
		"conditionId": "condition-resident-liang-qiu-000001",
		"kind": "headache",
		"label": "头痛得需要停下来",
		"severity": "serious",
		"sourceKind": "formal_activity",
		"sourceRef": "activity-library-write-result",
		"startedAtMinute": 510,
		"lastChangedAtMinute": 620,
		"state": "active",
		"nextChangeAtMinute": 700,
	}]
	wake["snapshot"]["me"]["activeNeeds"] = [{
		"needId": "need-condition-resident-liang-qiu-000001-consider_clinic",
		"kind": "consider_clinic",
		"label": "可以考虑向诊所提出看诊请求",
		"urgency": "high",
		"conditionId": "condition-resident-liang-qiu-000001",
		"conditionKind": "headache",
		"responseRequirements": ["clinic_request"],
	}]
	wake["events"] = [{
		"event_id": "world-event-condition-1",
		"type": "身体状况变化",
		"time": {"day": 1, "clock": "10:20", "period": "上午"},
		"eventId": "condition-event-000001",
		"eventType": "condition_changed",
		"residentId": "resident-liang-qiu",
		"conditionId": "condition-resident-liang-qiu-000001",
		"conditionKind": "headache",
		"label": "头痛得需要停下来",
		"severity": "serious",
		"state": "active",
		"atMinute": 620,
		"sourceRef": "condition_due",
	}]
	_expect_equal(
		AGENT_CONTRACT.validate_wake_packet(wake),
		[],
		"身体状况及其当前需要通过 Agent 唤醒合同",
	)
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request := compiler.call("compile", wake, "") as Dictionary
	var messages := request.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "身体状况提示词可以编译")
	if messages.size() != 2:
		return
	var user_text := String((messages[1] as Dictionary).get("content", ""))
	_expect(
		user_text.contains("头痛得需要停下来")
		and user_text.contains("程度严重")
		and user_text.contains("紧迫程度高")
		and user_text.contains("clinic_request")
		and user_text.contains("优先选择真实可执行的处理方式"),
		"模型能看到具体状况、紧迫程度和可执行处理需要",
	)


func _test_social_assignment_context(compiler_script: Script) -> void:
	var compiler: RefCounted = compiler_script.new(_initialization())
	var candidate_wake := _wake_packet("social-candidate-1", "晴天")
	candidate_wake["snapshot"]["social_matters"] = [{
		"matter_id": "matter-help-candidate",
		"revision": 3,
		"kind": "resident_request",
		"summary": "唐小满请人去社区花园帮忙。",
		"expires_at": 900,
		"response_round_id": "matter-help-candidate-r1",
		"response_window_until": 860,
		"options": [
			{
				"option_id": "accept",
				"allows_public_text": true,
			},
			{
				"option_id": "decline",
				"allows_public_text": true,
			},
		],
		"assignment": null,
	}]
	var candidate_request := compiler.call(
		"compile",
		candidate_wake,
		"",
	) as Dictionary
	var candidate_constraints := (
		candidate_request.get("derived_constraints", {}) as Dictionary
	).get("social_response", {}) as Dictionary
	_expect_equal(
		candidate_constraints.get("required"),
		false,
		"a response round exposes an optional independent social response",
	)
	var candidate_messages := (
		candidate_request.get("messages", []) as Array
	)
	if candidate_messages.size() == 2:
		_expect(
			String(
				(candidate_messages[1] as Dictionary).get("content", "")
			).contains("可选社会回应"),
			"compiled prompt states that the social response is optional",
		)
	var reply_wake := candidate_wake.duplicate(true)
	reply_wake["decision_id"] = "social-candidate-reply-1"
	reply_wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-social-priority",
		"with_resident_id": "resident-tang-xiao-man",
		"with": "唐小满",
		"turns": [{
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "你先回答我，好吗？",
			"narration": "",
			"photos": [],
		}],
	}
	reply_wake["events"] = [{
		"event_id": "social-priority-reply-event",
		"time": {"day": 1, "clock": "08:10", "period": "上午"},
		"type": "对方答话",
		"conversation_id": "conversation-social-priority",
		"turn": (
			reply_wake["snapshot"]["conversation"]["turns"][0] as Dictionary
		).duplicate(true),
	}]
	var reply_request := compiler.call("compile", reply_wake, "") as Dictionary
	_expect(
		not (
			reply_request.get("derived_constraints", {}) as Dictionary
		).has("social_response"),
		"an immediate conversation reply does not also request a social response",
	)

	var wake := _wake_packet("social-assignment-1", "晴天")
	wake["snapshot"]["social_matters"] = [{
		"matter_id": "matter-help-1",
		"revision": 4,
		"kind": "resident_request",
		"summary": "唐小满请人去社区花园帮忙。",
		"expires_at": 900,
		"response_round_id": null,
		"response_window_until": null,
		"options": [],
		"assignment": {
			"goal_id": "matter-help-1-g1",
			"role": "helper",
			"status": "assigned",
			"capability_id": "world.go_to_place",
			"target_refs": {"place_id": "社区花园"},
			"success_result_id": "helper-arrived",
		},
	}]
	var request := compiler.call("compile", wake, "") as Dictionary
	var messages := request.get("messages", []) as Array
	_expect_equal(
		messages.size(),
		2,
		"social assignment compiles into the regular decision request",
	)
	if messages.size() != 2:
		return
	var user_text := String(
		(messages[1] as Dictionary).get("content", "")
	)
	_expect(
		user_text.contains("已确认承诺"),
		"selected response is rendered as a formal commitment",
	)
	_expect(
		user_text.contains("world.go_to_place")
		and user_text.contains("place_id=社区花园"),
		"formal commitment keeps its executable capability and target",
	)
	_expect(
		not (
			request.get("derived_constraints", {}) as Dictionary
		).has("social_response"),
		"assigned matter without options does not invite a second response",
	)
	var assignment_constraints := (
		request.get("derived_constraints", {}) as Dictionary
	)
	var assignment_actions := (
		assignment_constraints.get("actions", {}) as Dictionary
	)
	_expect(
		assignment_actions.has("去")
		and assignment_actions.has("待着")
		and assignment_actions.has("用道具"),
		"a confirmed commitment keeps the resident's ordinary legal choices",
	)
	var assignment_places := (
		(assignment_actions.get("去", {}) as Dictionary).get(
			"places",
			[],
		) as Array
	)
	_expect(
		not assignment_places.has("社区花园"),
		"the current place is not offered as a redundant movement target",
	)
	_expect_equal(
		assignment_constraints.get("social_assignment"),
		(
			wake["snapshot"]["social_matters"][0] as Dictionary
		).get("assignment"),
		"the formal commitment remains visible without forcing one action",
	)
