class_name TownRoleSkillRuntime
extends RefCounted
## 狼人杀化·身份技能运行时（第一批：医生守诊 / 图书管理员查验 / 卧底嫁祸 / 警察制服额度）。
## 技能以决策附件 night_skill 提交（仿 exile_vote），同时支持"使用技能"动作类型
## （模型对动作遵守度高，动作通道为主、附件通道兼容）：
## - 20:00 夜间行动开始（唤醒技能持有者）
## - 08:00 统一结算（医生守护在死亡 flush 之前处理，查验线索/嫁祸线索在死亡公告后可见）
## 状态全部挂在 world._werewolf_state["roleSkills"]，随 werewolfState 存档走。

const TOWN_LOG := preload("res://world/runtime/TownLog.gd")

const DOCTOR_ID := "resident_bai_zhi_01"
const SCHOLAR_ID := "resident_xu_zhao_01"

const SKILL_DOCTOR := "doctor_protect"
const SKILL_SCHOLAR := "scholar_inspect"
const SKILL_FRAME := "undercover_frame"
const NIGHT_SKILLS: Array[String] = [
	SKILL_DOCTOR,
	SKILL_SCHOLAR,
	SKILL_FRAME,
]

const SCHOLAR_CHARGES_MAX := 3
const POLICE_CHARGES_MAX := 2
# 警察追踪装置额度(每局): 合并后的追踪器 3 次(原窃听器 2 + 定位器 3 合并)。
const TRACKER_CHARGES_MAX := 3
# 警察错杀平民的停职时长(分钟): 3 小时, 期满恢复 1 次额度。
const SUBDUE_SUSPENSION_MINUTES := 180
const NIGHT_START_MINUTE := 1200
const DAWN_MINUTE := 480


static func default_role_skills() -> Dictionary:
	return {
		"doctor": {
			"submissionTargetId": "",
			"submissionTargetName": "",
			"lastProtectedId": "",
			"lastProtectedDay": -1,
		},
		"scholar": {
			"charges": SCHOLAR_CHARGES_MAX,
			"submission": {},
			"lastInspectDay": -1,
		},
		"frame": {
			"used": false,
			"pendingTargetId": "",
			"pendingTargetName": "",
			"consumedEventId": "",
		},
		"police": {
			"charges": POLICE_CHARGES_MAX,
			"disarmed": false,
			"trackerCharges": TRACKER_CHARGES_MAX,
		},
		"nightRoundDay": -1,
	}


## 旧档/异常状态自愈：把缺失的 roleSkills 子键补齐。
static func ensure_state(world) -> void:
	var werewolf_state: Dictionary = world._werewolf_state
	var skills_value: Variant = werewolf_state.get("roleSkills")
	if not skills_value is Dictionary:
		werewolf_state["roleSkills"] = default_role_skills()
		return
	var skills := skills_value as Dictionary
	var defaults := default_role_skills()
	for key: Variant in defaults:
		if not skills.has(key):
			skills[key] = defaults[key]
	# 深补: 旧档的 police 子键可能缺 trackerCharges(追踪装置上线前的档)。
	var police_value: Variant = skills.get("police")
	if police_value is Dictionary:
		var police := police_value as Dictionary
		var default_police := defaults.get("police", {}) as Dictionary
		for sub_key: Variant in default_police:
			if not police.has(sub_key):
				police[sub_key] = default_police[sub_key]
		skills["police"] = police
	werewolf_state["roleSkills"] = skills


static func feature_active(world) -> bool:
	var undercover_ids: Array[String] = world._undercover_resident_ids()
	for undercover_id: String in undercover_ids:
		if (world._residents as Dictionary).has(undercover_id):
			return true
	return false


static func _skills(world) -> Dictionary:
	ensure_state(world)
	return world._werewolf_state.get("roleSkills", {}) as Dictionary


static func _label_for_minute(absolute_minute: int) -> String:
	var day_index := absolute_minute / 1440
	var minute_of_day := posmod(absolute_minute, 1440)
	return "第%d天 %02d:%02d" % [
		day_index + 1,
		minute_of_day / 60,
		minute_of_day % 60,
	]


## 20:00 夜间行动 / 08:00 结算入口（与 TWR.advance 同链，08:00 先结算再 flush 死讯）。
static func advance(world, absolute_minute: int) -> void:
	if not world._running:
		return
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day == NIGHT_START_MINUTE:
		start_night_round(world, absolute_minute)
	elif minute_of_day == DAWN_MINUTE:
		resolve_night(world, absolute_minute)


## 夜间行动开始：唤醒医生/图书管理员/所有卧底，让他们可以提交 night_skill。
static func start_night_round(world, absolute_minute: int) -> void:
	if not feature_active(world):
		return
	if bool(world._werewolf_state.get("gameOver", false)):
		return
	var day_index := absolute_minute / 1440
	var skills := _skills(world)
	skills["nightRoundDay"] = day_index
	(skills["doctor"] as Dictionary)["submissionTargetId"] = ""
	(skills["doctor"] as Dictionary)["submissionTargetName"] = ""
	(skills["scholar"] as Dictionary)["submission"] = {}
	world._werewolf_state["roleSkills"] = skills
	TOWN_LOG.section(
		"%s · 夜间行动" % _label_for_minute(absolute_minute),
	)
	var undercover_ids: Array[String] = world._undercover_resident_ids()
	for resident_id: String in world._resident_order:
		if not world._resident_is_alive(resident_id):
			continue
		if (
			resident_id == DOCTOR_ID
			or resident_id == SCHOLAR_ID
			or undercover_ids.has(resident_id)
		):
			# force_fresh=true: 强制生成新 wake 快照, 确保 night_skill
			# (守诊/查验/嫁祸) 一定进入本轮提示词。否则居民若在 20:00
			# 前已有旧 pending wake, 会复用旧快照而丢失夜间技能选项
			# (实锤: 白芷整晚没收到守诊选项 → 警察无人保护被暗杀)。
			world._schedule_decision(
				resident_id,
				true,
				false,
				false,
				true,
				true,
			)


## 08:00 结算：医生守护先于死讯 flush 处理（救下的人直接移出待公布队列）；
## 查验者获得昨夜行为线索。嫁祸不在这里结算——它在暗杀发生时即被消费。
static func resolve_night(world, absolute_minute: int) -> void:
	if not feature_active(world):
		_clear_night_submissions(world)
		return
	var day_index := absolute_minute / 1440
	var skills := _skills(world)
	var round_day := int(skills.get("nightRoundDay", -1))
	if round_day < 0 or day_index != round_day + 1:
		return
	_resolve_doctor(world, skills, round_day)
	_resolve_scholar(world, skills, round_day)
	skills["nightRoundDay"] = -1
	world._werewolf_state["roleSkills"] = skills


static func _clear_night_submissions(world) -> void:
	var skills := _skills(world)
	(skills["doctor"] as Dictionary)["submissionTargetId"] = ""
	(skills["doctor"] as Dictionary)["submissionTargetName"] = ""
	(skills["scholar"] as Dictionary)["submission"] = {}
	skills["nightRoundDay"] = -1
	world._werewolf_state["roleSkills"] = skills


static func _resolve_doctor(world, skills: Dictionary, round_day: int) -> void:
	var doctor := skills.get("doctor", {}) as Dictionary
	var protected_id := String(doctor.get("submissionTargetId", "")).strip_edges()
	if protected_id.is_empty():
		return
	var protected_name := String(doctor.get("submissionTargetName", ""))
	if protected_name.is_empty():
		protected_name = world._resident_display_name(protected_id)
	# 把被守护者当夜的暗杀死讯从待公布队列里摘掉：人没死，天亮不公告。
	var queue: Array = (
		world._werewolf_state.get("pendingDeathAnnouncements", []) as Array
	)
	var kept: Array = []
	var blocked_event: Dictionary = {}
	for pending_value: Variant in queue:
		var pending := pending_value as Dictionary
		var event := pending.get("event", {}) as Dictionary
		if (
			String(event.get("deceased_resident_id", "")) == protected_id
			and String(event.get("reason", "")).contains("暗杀")
		):
			blocked_event = event
			continue
		kept.append(pending)
	if blocked_event.is_empty():
		# 守护落空：不额外投递事件，医生下次自然唤醒即可继续生活。
		doctor["lastProtectedId"] = protected_id
		doctor["lastProtectedDay"] = round_day
		return
	world._werewolf_state["pendingDeathAnnouncements"] = kept
	doctor["lastProtectedId"] = protected_id
	doctor["lastProtectedDay"] = round_day
	var attacker_id := String(blocked_event.get("attacker_resident_id", ""))
	var attacker_name: String = world._resident_display_name(attacker_id)
	if attacker_name.is_empty():
		attacker_name = "那个暗中下手的人"
	var doctor_event := {
		"event_id": "role-skill-doctor-save:%d:%s" % [round_day, protected_id],
		"type": "守诊结果",
		"time": world.get_time(),
		"target_resident_id": protected_id,
		"summary": "昨夜你守在%s身边。半夜里%s对他下了手，被你及时拦下，人救回来了。" % [
			protected_name,
			attacker_name,
		],
	}
	var victim_event := {
		"event_id": "role-skill-doctor-saved:%d:%s" % [round_day, protected_id],
		"type": "被救",
		"time": world.get_time(),
		"attacker_resident_id": attacker_id,
		"summary": "昨夜有人暗中对你下手，你被及时救了下来，捡回一条命。",
	}
	world._append_pending_world_event(
		world._residents.get(DOCTOR_ID, {}) as Dictionary,
		doctor_event,
	)
	world._append_pending_world_event(
		world._residents.get(protected_id, {}) as Dictionary,
		victim_event,
	)
	if not attacker_id.is_empty():
		var attacker_fail_event := {
			"event_id": "role-skill-doctor-block:%d:%s" % [round_day, attacker_id],
			"type": "暗杀失败",
			"time": world.get_time(),
			"target_resident_id": protected_id,
			"summary": "你对%s的暗杀没有得手——有人提前护住了他。" % protected_name,
		}
		world._append_pending_world_event(
			world._residents.get(attacker_id, {}) as Dictionary,
			attacker_fail_event,
		)
	TOWN_LOG.line(
		"ROLE_SKILL",
		"%s | 医生守诊成功：救下 %s（行凶者 %s）" % [
			world._time_label(),
			protected_name,
			attacker_name,
		],
	)
	for resident_id: String in [DOCTOR_ID, protected_id, attacker_id]:
		if not resident_id.is_empty() and world._resident_is_alive(resident_id):
			world._schedule_decision(resident_id, true)


static func _resolve_scholar(world, skills: Dictionary, round_day: int) -> void:
	var scholar := skills.get("scholar", {}) as Dictionary
	var submission := scholar.get("submission", {}) as Dictionary
	if submission.is_empty():
		return
	var target_id := String(submission.get("targetId", "")).strip_edges()
	var target_name := String(submission.get("targetName", ""))
	if target_name.is_empty():
		target_name = world._resident_display_name(target_id)
	var observed_place := String(submission.get("observedPlace", ""))
	var observed_doing := String(submission.get("observedDoing", ""))
	var observed_nearby := String(submission.get("observedNearby", ""))
	var current_place := ""
	if world._residents.has(target_id):
		current_place = String(
			(world._residents[target_id] as Dictionary).get(
				"currentPlace",
				"",
			),
		)
	var moved := (
		not observed_place.is_empty()
		and not current_place.is_empty()
		and observed_place != current_place
	)
	var clue := "档案查验：昨夜你关注的%s，入夜时在%s" % [
		target_name,
		observed_place if not observed_place.is_empty() else "一个你没有看清的地方",
	]
	if not observed_doing.is_empty():
		clue += "（%s）" % observed_doing
	if not observed_nearby.is_empty():
		clue += "，当时与他同区域的人：%s" % observed_nearby
	if moved:
		clue += "。今晨他出现在%s，夜里似乎离开过原来的地方。" % current_place
	else:
		clue += "。今晨他仍在%s，夜里似乎一直待在那里。" % (
			current_place if not current_place.is_empty() else observed_place
		)
	if not world._resident_is_alive(target_id):
		clue = "档案查验：你昨夜关注%s，但天亮前他已经不在人世了。" % target_name
	var event := {
		"event_id": "role-skill-scholar-inspect:%d:%s" % [round_day, target_id],
		"type": "查验结果",
		"time": world.get_time(),
		"target_resident_id": target_id,
		"summary": clue,
	}
	world._append_pending_world_event(
		world._residents.get(SCHOLAR_ID, {}) as Dictionary,
		event,
	)
	scholar["charges"] = maxi(0, int(scholar.get("charges", 0)) - 1)
	scholar["lastInspectDay"] = round_day
	TOWN_LOG.line(
		"ROLE_SKILL",
		"%s | 许照查验完成：%s（剩余 %d 次）" % [
			world._time_label(),
			target_name,
			int(scholar.get("charges", 0)),
		],
	)
	if world._resident_is_alive(SCHOLAR_ID):
		world._schedule_decision(SCHOLAR_ID, true)


## 夜间技能快照：技能持有者才会拿到 night_skill 键；其他人/已提交者返回空。
static func night_skill_snapshot(world, resident_id: String) -> Dictionary:
	if not feature_active(world):
		return {}
	if bool(world._werewolf_state.get("gameOver", false)):
		return {}
	if not world._resident_is_alive(resident_id):
		return {}
	var skills := _skills(world)
	var round_day := int(skills.get("nightRoundDay", -1))
	if round_day < 0:
		return {}
	var day := int(world._environment.get_absolute_minute()) / 1440
	if day < round_day or day > round_day + 1:
		return {}
	var undercover_ids: Array[String] = world._undercover_resident_ids()
	var skill_ids: Array[String] = []
	var candidate_ids: Array[String] = []
	if resident_id == DOCTOR_ID:
		var doctor := skills.get("doctor", {}) as Dictionary
		if not String(doctor.get("submissionTargetId", "")).is_empty():
			return {}
		skill_ids.append(SKILL_DOCTOR)
		candidate_ids = _alive_candidate_ids(world, "")
		var last_protected_id := String(doctor.get("lastProtectedId", ""))
		if (
			not last_protected_id.is_empty()
			and int(doctor.get("lastProtectedDay", -1)) == round_day - 1
		):
			candidate_ids.erase(last_protected_id)
	elif resident_id == SCHOLAR_ID:
		var scholar := skills.get("scholar", {}) as Dictionary
		if int(scholar.get("charges", 0)) <= 0:
			return {}
		if not (scholar.get("submission", {}) as Dictionary).is_empty():
			return {}
		skill_ids.append(SKILL_SCHOLAR)
		candidate_ids = _alive_candidate_ids(world, resident_id)
	elif undercover_ids.has(resident_id):
		var frame := skills.get("frame", {}) as Dictionary
		if bool(frame.get("used", false)):
			return {}
		if not String(frame.get("pendingTargetId", "")).is_empty():
			return {}
		skill_ids.append(SKILL_FRAME)
		candidate_ids = _alive_non_undercover_ids(world, undercover_ids)
	else:
		return {}
	if skill_ids.is_empty() or candidate_ids.is_empty():
		return {}
	return {
		"round_day": round_day,
		"settle_clock": "次日 08:00",
		"skills": skill_ids,
		"candidate_ids": candidate_ids,
	}


static func _alive_candidate_ids(world, exclude_id: String) -> Array[String]:
	var ids: Array[String] = []
	for resident_id: String in world._resident_order:
		if resident_id == exclude_id or not world._resident_is_alive(resident_id):
			continue
		if world._resident_display_name(resident_id).is_empty():
			continue
		ids.append(resident_id)
	return ids


static func _alive_non_undercover_ids(
	world,
	undercover_ids: Array[String],
) -> Array[String]:
	var ids: Array[String] = []
	for resident_id: String in world._resident_order:
		if undercover_ids.has(resident_id) or not world._resident_is_alive(resident_id):
			continue
		if world._resident_display_name(resident_id).is_empty():
			continue
		ids.append(resident_id)
	return ids


static func _resident_id_for_name(world, target_name: String) -> String:
	for resident_id: String in world._resident_order:
		if world._resident_display_name(resident_id) == target_name:
			return resident_id
	return ""


## 居民提交 night_skill（TWR 决策提交链调用）。返回错误串，空串=成功。
## 既支持附件通道（决策里带 night_skill 键），也支持"使用技能"动作通道。
static func submit_night_skill(world, resident_id: String, value: Dictionary) -> String:
	var snapshot := night_skill_snapshot(world, resident_id)
	if snapshot.is_empty():
		# 细分空快照原因，给模型可行动的反馈（而不是静默忽略）。
		if not feature_active(world) or bool(world._werewolf_state.get("gameOver", false)):
			return "当前没有进行中的夜间技能行动"
		if not world._resident_is_alive(resident_id):
			return "你已不在镇上，无法使用夜间技能"
		var skills := _skills(world)
		if int(skills.get("nightRoundDay", -1)) < 0:
			return "夜间行动尚未开始，20:00 后才会开放"
		if resident_id == DOCTOR_ID:
			var doctor := skills.get("doctor", {}) as Dictionary
			if not String(doctor.get("submissionTargetId", "")).is_empty():
				return "你已经提交过守诊了，一晚只能守护一个人"
		elif resident_id == SCHOLAR_ID:
			var scholar := skills.get("scholar", {}) as Dictionary
			if int(scholar.get("charges", 0)) <= 0:
				return "你的查验次数已用完"
		return "夜间技能行动窗口已结束"
	var skill_id := String(value.get("skill_id", "")).strip_edges()
	var target_id := String(
		value.get("target_resident_id", ""),
	).strip_edges()
	if skill_id.is_empty():
		return "技能 skill_id 必须是非空文本"
	if target_id.is_empty():
		return "目标 target_resident_id 必须是非空居民ID"
	if not (snapshot.get("skills", []) as Array).has(skill_id):
		return "技能 %s 不在可用技能列表中" % skill_id
	if not (snapshot.get("candidate_ids", []) as Array).has(target_id):
		return "目标 %s 不在候选名单中" % world._resident_display_name(target_id)
	if not world._resident_is_alive(target_id):
		return "目标 %s 当前不在镇上" % world._resident_display_name(target_id)
	var target_name: String = world._resident_display_name(target_id)
	var skills := _skills(world)
	match skill_id:
		SKILL_DOCTOR:
			var doctor := skills.get("doctor", {}) as Dictionary
			doctor["submissionTargetId"] = target_id
			doctor["submissionTargetName"] = target_name
			skills["doctor"] = doctor
		SKILL_SCHOLAR:
			var scholar := skills.get("scholar", {}) as Dictionary
			var target := world._residents.get(target_id, {}) as Dictionary
			var nearby_names: Array[String] = []
			for person_ref: Variant in target.get("nearby", []) as Array:
				var person_name := String(person_ref)
				if not person_name.is_empty() and person_name != target_name:
					nearby_names.append(person_name)
			scholar["submission"] = {
				"targetId": target_id,
				"targetName": target_name,
				"observedPlace": String(target.get("currentPlace", "")),
				"observedDoing": String(target.get("doing", "")),
				"observedNearby": "、".join(nearby_names),
			}
			skills["scholar"] = scholar
		SKILL_FRAME:
			var frame := skills.get("frame", {}) as Dictionary
			frame["pendingTargetId"] = target_id
			frame["pendingTargetName"] = target_name
			skills["frame"] = frame
	world._werewolf_state["roleSkills"] = skills
	TOWN_LOG.line(
		"ROLE_SKILL",
		"%s | %s 提交夜间技能 %s → %s：%s" % [
			world._time_label(),
			world._resident_display_name(resident_id),
			skill_id,
			target_name,
			String(value.get("line", "")),
		],
	)
	# 追踪装置: 被追踪目标提交夜间技能时实时上报安装者(警察)。
	if world.has_method("_record_police_device_action_intel"):
		world._record_police_device_action_intel(
			resident_id,
			"夜间技能",
			"深夜对 %s 施展技能 %s" % [target_name, skill_id],
			[],
		)
	return ""


## 暗杀执行前的守护判定：医生已提交守护该目标时，暗杀直接失败。
static func is_assassination_blocked(world, target_id: String) -> bool:
	if not feature_active(world):
		return false
	var skills := _skills(world)
	var doctor := skills.get("doctor", {}) as Dictionary
	return String(doctor.get("submissionTargetId", "")) == target_id


## 嫁祸：下一次暗杀死亡发生时消费，把伪造线索挂到该案件上。
static func consume_frame_for_death(world, event_id: String) -> void:
	var skills := _skills(world)
	var frame := skills.get("frame", {}) as Dictionary
	if bool(frame.get("used", false)):
		return
	var pending_id := String(frame.get("pendingTargetId", "")).strip_edges()
	if pending_id.is_empty():
		return
	frame["used"] = true
	frame["consumedEventId"] = event_id
	skills["frame"] = frame
	world._werewolf_state["roleSkills"] = skills
	TOWN_LOG.line(
		"ROLE_SKILL",
		"%s | 卧底嫁祸生效：案件 %s 的线索指向 %s" % [
			world._time_label(),
			event_id,
			String(frame.get("pendingTargetName", "")),
		],
	)


## 警察案件档案里的伪造线索（只有被嫁祸污染的案件才返回名字）。
static func frame_clue_for_event(world, event_id: String) -> String:
	var skills := _skills(world)
	var frame := skills.get("frame", {}) as Dictionary
	if (
		bool(frame.get("used", false))
		and String(frame.get("consumedEventId", "")) == event_id
	):
		return String(frame.get("pendingTargetName", ""))
	return ""


## 警察制服额度。
static func police_can_subdue(world) -> bool:
	var skills := _skills(world)
	var police := skills.get("police", {}) as Dictionary
	if bool(police.get("disarmed", false)):
		var until := int(police.get("disarmed_until_absolute_minute", -1))
		if until >= 0 and int(world._authoritative_absolute_minute()) >= until:
			# 停职期满自动恢复: 惩罚性损失一次额度(恢复后剩 1 次)。
			police["disarmed"] = false
			police["charges"] = 1
			police.erase("disarmed_until_absolute_minute")
			skills["police"] = police
			world._werewolf_state["roleSkills"] = skills
			TOWN_LOG.line(
				"ROLE_SKILL",
				"%s | 闻叙停职期满恢复制服权（剩余额度 1）" % world._time_label(),
			)
		else:
			return false
	return (
		int(police.get("charges", 0)) > 0
		and not bool(police.get("disarmed", false))
	)


static func police_charges_remaining(world) -> int:
	var skills := _skills(world)
	return int((skills.get("police", {}) as Dictionary).get("charges", 0))


## 警察追踪装置余量。
static func police_tracker_charges(world) -> int:
	var skills := _skills(world)
	return int(
		(skills.get("police", {}) as Dictionary).get("trackerCharges", 0)
	)


## 消耗一次追踪装置（余量 > 0 才消耗，返回是否成功）。
static func consume_police_tracker(world) -> bool:
	var skills := _skills(world)
	var police := skills.get("police", {}) as Dictionary
	var remaining := int(police.get("trackerCharges", 0))
	if remaining <= 0:
		return false
	police["trackerCharges"] = remaining - 1
	skills["police"] = police
	world._werewolf_state["roleSkills"] = skills
	return true


## 制服结算：正确制服扣 1 次额度；错杀平民立即停职并清零额度。
static func record_subdue_result(world, target_id: String, is_undercover: bool) -> void:
	var skills := _skills(world)
	var police := skills.get("police", {}) as Dictionary
	if is_undercover:
		police["charges"] = maxi(
			0,
			int(police.get("charges", 0)) - 1,
		)
		TOWN_LOG.line(
			"ROLE_SKILL",
			"%s | 闻叙制服卧底 %s 成功（剩余额度 %d）" % [
				world._time_label(),
				world._resident_display_name(target_id),
				int(police.get("charges", 0)),
			],
		)
	else:
		police["charges"] = 0
		police["disarmed"] = true
		police["disarmed_until_absolute_minute"] = (
			int(world._authoritative_absolute_minute())
			+ SUBDUE_SUSPENSION_MINUTES
		)
		TOWN_LOG.line(
			"ROLE_SKILL",
			"%s | 闻叙误伤平民 %s：制服权被停用 %d 小时" % [
				world._time_label(),
				world._resident_display_name(target_id),
				int(SUBDUE_SUSPENSION_MINUTES / 60),
			],
		)
	skills["police"] = police
	world._werewolf_state["roleSkills"] = skills
