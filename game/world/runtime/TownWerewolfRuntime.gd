class_name TownWerewolfRuntime
extends RefCounted
## 狼人杀化核心运行时(2026-08-16 MVP):
## ①夜间(20:00-08:00)暗杀死亡不即时公告,次日 08:00 统一公布("天亮发现尸体")
## ②每天 11:00 镇民大会开始放逐投票,12:30 开票,得票最高者被放逐并公布身份
## ③胜负判定:卧底全灭=镇民胜;平民全灭或平民数≤卧底数=卧底胜
## 状态挂在 world._werewolf_state(Dictionary),随存档走 werewolfState 域。
## 挂载点:TWR 每日推进链 _sync_production_tasks 之后 advance()。


const NIGHT_START_MINUTE := 1200  # 20:00
const DAWN_MINUTE := 480          # 08:00 天亮公布昨夜死讯
const VOTE_START_MINUTE := 660    # 11:00 镇民大会开始
const VOTE_REMIND_MINUTE := 720   # 12:00 强制唤醒未投票居民投票
const VOTE_SETTLE_MINUTE := 750   # 12:30 开票放逐
const EXILE_REASON := "被镇民大会投票放逐"
const TOWN_LOG := preload("res://world/runtime/TownLog.gd")
const ROLE_SKILL_RUNTIME := preload("res://world/runtime/TownRoleSkillRuntime.gd")


static func is_night(absolute_minute: int) -> bool:
	var minute_of_day := posmod(absolute_minute, 1440)
	return minute_of_day >= NIGHT_START_MINUTE or minute_of_day < DAWN_MINUTE


## 夜序：20:00 开始的夜晚属于当天；00:00-08:00 仍属于前一晚。
static func night_index(absolute_minute: int) -> int:
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day >= NIGHT_START_MINUTE:
		return absolute_minute / 1440
	return absolute_minute / 1440 - 1


## 卧底夜间击杀配额：只在夜间可用，且全体卧底每晚最多成功/尝试一次
## （被医生挡下同样消耗当晚机会，不能换个目标继续杀）。
static func undercover_kill_available(world, absolute_minute: int) -> bool:
	if bool(world._werewolf_state.get("gameOver", false)):
		return false
	if not is_night(absolute_minute):
		return false
	var last_kill_night := int(
		world._werewolf_state.get("undercoverKillLastNight", -1),
	)
	return last_kill_night != night_index(absolute_minute)


static func record_night_kill(world, absolute_minute: int) -> void:
	world._werewolf_state["undercoverKillLastNight"] = night_index(
		absolute_minute,
	)


## 警察警觉护盾剩余次数:警察每局有一次警觉免死(暗杀警察被挡下)。
static func police_alert_charges(world) -> int:
	return int(world._werewolf_state.get("policeAlertCharges", 0))


## 消耗一次警察警觉护盾。返回是否成功消耗(剩余次数 > 0 才消耗)。
static func consume_police_alert(world) -> bool:
	var charges := police_alert_charges(world)
	if charges <= 0:
		return false
	world._werewolf_state["policeAlertCharges"] = charges - 1
	return true


## 卧底夜间击杀额度是否已用尽(今晚已有人动过手或被医生挡下)。
## 供 wake 快照注入: 提示卧底今晚不能再提交暗杀。
static func undercover_kill_quota_exhausted(
	world,
	absolute_minute: int,
) -> bool:
	if not feature_active(world):
		return false
	if not is_night(absolute_minute):
		return false
	var last_kill_night := int(
		world._werewolf_state.get("undercoverKillLastNight", -1),
	)
	return last_kill_night == night_index(absolute_minute)


## 用"tick 分钟"生成与 _time_label 同格式的时间标签。
## 一次 advance 跨越多分钟时,world._time_label 读到的是终态分钟,
## 天亮/大会横幅会错标到结尾时间,因此阶段日志一律用本函数。
static func _label_for_minute(absolute_minute: int) -> String:
	var day_index := absolute_minute / 1440
	var minute_of_day := posmod(absolute_minute, 1440)
	return "第%d天 %02d:%02d" % [
		day_index + 1,
		minute_of_day / 60,
		minute_of_day % 60,
	]


static func default_state() -> Dictionary:
	return {
		"pendingDeathAnnouncements": [],  # 夜间暗杀待公布死亡事件队列
		"vote": {},                       # 进行中的投票回合
		"gameOver": false,
		"winner": "",
		"winnerAnnounced": false,         # 胜负公告是否已发出(夜间终局压到天亮)
		"roleSkills": ROLE_SKILL_RUNTIME.default_role_skills(),
		"undercoverKillLastNight": -1,    # 全卧底阵营每晚最多 1 杀（-1=未杀过）
		"policeAlertCharges": 1,          # 警察每局 1 次警觉免死(暗杀被挡下)
	}


## 世界每分钟推进入口(与 check_deadline 同链)。
static func advance(world, absolute_minute: int) -> void:
	if not world._running:
		return
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day == DAWN_MINUTE:
		if feature_active(world):
			TOWN_LOG.section(
				"%s · 天亮" % _label_for_minute(absolute_minute),
			)
		flush_pending_death_announcements(world, absolute_minute)
		announce_pending_victory(world, absolute_minute)
	if minute_of_day == VOTE_START_MINUTE:
		start_vote_round(world, absolute_minute)
	if minute_of_day == VOTE_REMIND_MINUTE:
		remind_unvoted_residents(world, absolute_minute)
	if minute_of_day == VOTE_SETTLE_MINUTE:
		settle_vote_round(world, absolute_minute)


## 世界里没有任何卧底居民(官方/fixture/自定义普通世界)时,整套狼人杀
## 特性不激活:夜间死亡不再延迟、镇民大会不开、投票接口一律空转。
static func feature_active(world) -> bool:
	var undercover_ids: Array[String] = world._undercover_resident_ids()
	for undercover_id: String in undercover_ids:
		if (world._residents as Dictionary).has(undercover_id):
			return true
	return false


## 该居民的死亡是否仍处于"夜间待公布"状态(天亮 flush 前不可见)。
static func death_announcement_pending(world, resident_id: String) -> bool:
	var queue: Array = (
		world._werewolf_state.get("pendingDeathAnnouncements", []) as Array
	)
	for pending_value: Variant in queue:
		var pending := pending_value as Dictionary
		var event := pending.get("event", {}) as Dictionary
		if String(event.get("deceased_resident_id", "")) == resident_id:
			return true
	return false


## 待公布死者的表现层遮罩:返回 {"pending":true,"previousDoing":"..."}。
## UI/感知投影用它把"已经死亡"的外观推迟到天亮公布之后。
static func pending_death_presentation(world, resident_id: String) -> Dictionary:
	var queue: Array = (
		world._werewolf_state.get("pendingDeathAnnouncements", []) as Array
	)
	for pending_value: Variant in queue:
		var pending := pending_value as Dictionary
		var event := pending.get("event", {}) as Dictionary
		if String(event.get("deceased_resident_id", "")) == resident_id:
			return {
				"pending": true,
				"previousDoing": String(
					pending.get("previousDoing", ""),
				).strip_edges(),
			}
	return {}


## 夜间暗杀死亡 → 入队等待天亮(由 confirm_resident_death 调用)。
## 返回 true 表示已入队,调用方应跳过即时公告与全员唤醒。
static func defer_night_death_announcement(
	world,
	event: Dictionary,
	previous_doing: String = "",
) -> bool:
	if not feature_active(world):
		return false
	if not is_night(int(world._environment.get_absolute_minute())):
		return false
	var reason := String(event.get("reason", "")).strip_edges()
	if not reason.contains("暗杀"):
		return false
	var queue: Array = (
		world._werewolf_state.get("pendingDeathAnnouncements", []) as Array
	)
	queue.append({
		"event": event.duplicate(true),
		"previousDoing": previous_doing.strip_edges(),
	})
	world._werewolf_state["pendingDeathAnnouncements"] = queue
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | 夜间死亡暂缓公告：%s(天亮统一公布)" % [
			world._time_label(),
			String(event.get("deceased_resident_name", "居民")),
		],
	)
	return true


## 天亮:批量公布昨夜死讯,唤醒全镇。
static func flush_pending_death_announcements(
	world,
	absolute_minute: int = -1,
) -> void:
	var time_label: String = (
		_label_for_minute(absolute_minute)
		if absolute_minute >= 0
		else String(world._time_label())
	)
	var queue: Array = (
		world._werewolf_state.get("pendingDeathAnnouncements", []) as Array
	)
	if queue.is_empty():
		return
	world._werewolf_state["pendingDeathAnnouncements"] = []
	for pending_value: Variant in queue:
		var pending := pending_value as Dictionary
		var event := pending.get("event", {}) as Dictionary
		var text := "清晨，%s" % world._death_announcement_text(event)
		var announcement := world.broadcast_announcement(text) as Dictionary
		if announcement.get("ok") != true:
			push_error(
				"天亮死亡公告发布失败：%s"
				% String(announcement.get("errorCode", "UNKNOWN"))
			)
		# 天亮公布后,死亡才算"公开":补记公共事件日志(夜里只入队不落公开
		# 日志),并让表现层把死者正式切换为已死亡外观。
		var deceased_id := String(event.get("deceased_resident_id", ""))
		world._append_public_event_log(
			String(event.get("event_id", "")),
			"world_event",
			deceased_id,
			String(event.get("deceased_resident_name", "")),
			String(
				(event.get("location", {}) as Dictionary).get(
					"placeName",
					"",
				),
			),
			event,
		)
		if not deceased_id.is_empty():
			world._emit_resident_state_changed(deceased_id)
		TOWN_LOG.line(
			"WEREWOLF",
			"%s | 天亮公布死讯：%s" % [
				time_label,
				text,
			],
		)
	for resident_id: String in world._resident_order:
		if world._resident_is_alive(resident_id):
			world._schedule_decision(resident_id, true)


## 11:00:开启镇民大会投票回合。
static func start_vote_round(world, absolute_minute: int) -> void:
	if not feature_active(world):
		return
	if world._werewolf_state.get("gameOver", false):
		return
	var day_index := absolute_minute / 1440
	if day_index < 1:
		return
	# 天数快照已在同一天开过就不再重开(存档恢复防重)
	var existing := world._werewolf_state.get("vote", {}) as Dictionary
	if int(existing.get("day", -1)) == day_index:
		return
	var alive_ids: Array[String] = []
	for resident_id: String in world._resident_order:
		if world._resident_is_alive(resident_id):
			alive_ids.append(resident_id)
	if alive_ids.size() < 3:
		return
	var candidate_names: Array[String] = []
	for resident_id: String in alive_ids:
		# 警察不参与放逐候选: 警察是镇民阵营对抗卧底的核心力量,
		# 不能让居民投票把他放逐掉(他仍可投票,只是不能被投)。
		if world._resident_is_police(resident_id):
			continue
		candidate_names.append(world._resident_display_name(resident_id))
	world._werewolf_state["vote"] = {
		"day": day_index,
		"votes": {},  # voter_id -> {"target_resident_name": String, "line": String}
		"candidateNames": candidate_names,
	}
	TOWN_LOG.section(
		"%s · 镇民大会开始" % _label_for_minute(absolute_minute),
	)
	world.broadcast_announcement(
		"镇民大会开始：近来镇上命案不断，今天 12:30 举行放逐投票。"
		+ "所有在世居民请投出你怀疑的人，得票最高者将被放逐出镇并公布其身份；平票则无人出局。",
	)
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | 第%d天镇民大会开始，候选人 %d 人" % [
			_label_for_minute(absolute_minute),
			day_index,
			candidate_names.size(),
		],
	)
	for resident_id: String in alive_ids:
		# 开会唤醒要"伴随当前动作":不打断居民手头的事,但必须立刻进入
		# 决策,否则动作跨过 12:30 的居民会直接错过本轮投票。
		world._schedule_decision(
			resident_id,
			true,
			false,
			false,
			false,
			true,
		)


## 12:00:强制唤醒所有尚未投票的居民,让他们补投。
## 与 11:00 的不同:只对"还没投"的居民唤醒,并让本轮 wake 快照携带
## forced 标记(投票为必填,见 vote_snapshot),避免 LLM 继续把投票当可选。
static func remind_unvoted_residents(world, absolute_minute: int) -> void:
	if not feature_active(world):
		return
	var vote := world._werewolf_state.get("vote", {}) as Dictionary
	if vote.is_empty() or world._werewolf_state.get("gameOver", false):
		return
	for resident_id: String in world._resident_order:
		if not world._resident_is_alive(resident_id):
			continue
		if (vote.get("votes", {}) as Dictionary).has(resident_id):
			continue
		world._schedule_decision(
			resident_id,
			true,
			false,
			false,
			true,
			true,
		)


## 投票快照:投票回合进行中才非空(进 wake_packet.snapshot.exile_vote)。
static func vote_snapshot(world, resident_id: String) -> Dictionary:
	if not feature_active(world):
		return {}
	var vote := world._werewolf_state.get("vote", {}) as Dictionary
	if vote.is_empty() or world._werewolf_state.get("gameOver", false):
		return {}
	if not world._resident_is_alive(resident_id):
		return {}
	var candidate_names: Array[String] = []
	var voter_name: String = String(world._resident_display_name(resident_id))
	for name_value: Variant in vote.get("candidateNames", []) as Array:
		var candidate_name := String(name_value)
		# 不能投自己: 全局候选名单已排除警察与死者, 这里再排除投票者本人。
		if candidate_name == voter_name:
			continue
		candidate_names.append(candidate_name)
	# 已投票的居民本轮不再重复投票
	if (vote.get("votes", {}) as Dictionary).has(resident_id):
		return {}
	return {
		"round_day": int(vote.get("day", 0)),
		"settle_clock": "12:30",
		"candidate_names": candidate_names,
		"forced": _vote_forced(world),
	}


## 11:00-12:30 投票窗口全程强制: 居民被唤醒就必须提交 exile_vote,
## 避免"可选"期居民不投票、12:00 集中补投又排不完(第2天仅 2/13 参与)。
## 12:00 的 VOTE_REMIND 仍保留, 只负责唤醒漏投者补投。
static func _vote_forced(world) -> bool:
	var minute_of_day := posmod(
		int(world._authoritative_absolute_minute()),
		1440,
	)
	return (
		minute_of_day >= VOTE_START_MINUTE
		and minute_of_day < VOTE_SETTLE_MINUTE
	)


## 居民提交 exile_vote(TWR 决策提交链调用)。
## 返回错误字符串,空串=投票已记录(方案A: 即时动作分支需把失败反馈给模型重试)。
static func submit_vote(world, resident_id: String, value: Dictionary) -> String:
	if not feature_active(world):
		return "当前没有进行中的镇民大会投票"
	var vote := world._werewolf_state.get("vote", {}) as Dictionary
	if vote.is_empty() or world._werewolf_state.get("gameOver", false):
		return "本轮投票未在进行"
	if not world._resident_is_alive(resident_id):
		return "你已不在镇上，无法投票"
	var votes := vote.get("votes", {}) as Dictionary
	if votes.has(resident_id):
		return "你已经投过票了，一票不能改"
	var target_name := String(
		value.get("target_resident_name", "")
	).strip_edges()
	if target_name.is_empty():
		return "投票目标 target_resident_name 必须是非空文本"
	var candidate_names: Array[String] = []
	for name_value: Variant in vote.get("candidateNames", []) as Array:
		candidate_names.append(String(name_value))
	if not candidate_names.has(target_name):
		return "投票目标 %s 不在候选人名单中" % target_name
	votes[resident_id] = {
		"target_resident_name": target_name,
		"line": String(value.get("line", "")).strip_edges(),
	}
	vote["votes"] = votes
	world._werewolf_state["vote"] = vote
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | %s 投票放逐 %s：%s" % [
			world._time_label(),
			world._resident_display_name(resident_id),
			target_name,
			String(value.get("line", "")),
		],
	)
	return ""


## 12:30:开票。得票最高者放逐(平票无人出局),公告并查胜负。
static func settle_vote_round(world, absolute_minute: int) -> void:
	if not feature_active(world):
		# 特性停用(或世界已不再有卧底)时丢弃任何残留投票回合。
		if not (world._werewolf_state.get("vote", {}) as Dictionary).is_empty():
			world._werewolf_state["vote"] = {}
		return
	var vote := world._werewolf_state.get("vote", {}) as Dictionary
	if vote.is_empty():
		return
	world._werewolf_state["vote"] = {}
	# 终局后不再开票:11:00 开会到 12:30 之间若已分出胜负,直接作废本轮,
	# 避免"胜负已定仍放逐一个无辜者"的终局后额外死亡。
	if world._werewolf_state.get("gameOver", false):
		return
	var day_index := absolute_minute / 1440
	if int(vote.get("day", -1)) != day_index:
		return
	TOWN_LOG.section(
		"%s · 镇民大会开票" % _label_for_minute(absolute_minute),
	)
	var votes := vote.get("votes", {}) as Dictionary
	# 按得票目标名计数
	var tally: Dictionary = {}
	for voter_value: Variant in votes:
		var ballot := votes[voter_value] as Dictionary
		var target_name := String(
			ballot.get("target_resident_name", "")
		).strip_edges()
		if target_name.is_empty():
			continue
		tally[target_name] = int(tally.get(target_name, 0)) + 1
	if tally.is_empty():
		world.broadcast_announcement(
			"镇民大会流会：没有人投出有效票，今晚无人被放逐。",
		)
		return
	# 找出唯一最高票(并列最高=平票,无人出局)
	var top_name := ""
	var top_count := 0
	var tie := false
	for target_name: String in tally:
		var count := int(tally[target_name])
		if count > top_count:
			top_count = count
			top_name = target_name
			tie = false
		elif count == top_count:
			tie = true
	if tie or top_name.is_empty():
		world.broadcast_announcement(
			"镇民大会开票：出现平票，今晚无人被放逐。",
		)
		return
	# 名字反查居民
	var exile_id := ""
	for resident_id: String in world._resident_order:
		if world._resident_display_name(resident_id) == top_name:
			exile_id = resident_id
			break
	if exile_id.is_empty() or not world._resident_is_alive(exile_id):
		return
	var summary := "镇民大会开票：%s 以 %d 票被放逐出镇。" % [top_name, top_count]
	if world._undercover_resident_ids().has(exile_id):
		summary += "离开时身份曝光——他竟是潜伏在镇上的卧底！"
	else:
		summary += "他只是个普通居民，小镇错放了一位无辜者。"
	world.broadcast_announcement(summary)
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | %s" % [_label_for_minute(absolute_minute), summary],
	)
	world.confirm_resident_death(exile_id, EXILE_REASON)


## 胜负判定(由 confirm_resident_death 末尾调用)。返回 true 表示已出结果。
static func check_victory(world) -> bool:
	if world._werewolf_state.get("gameOver", false):
		return true
	var undercover_ids: Array[String] = world._undercover_resident_ids()
	# 世界里根本没有卧底居民(如官方/fixture 世界)时,胜负机制不激活,
	# 避免第一次普通死亡就误发"卧底已清除"公告。
	var undercover_present := false
	for undercover_id: String in undercover_ids:
		if world._residents.has(undercover_id):
			undercover_present = true
			break
	if not undercover_present:
		return false
	var undercover_alive := 0
	var innocent_alive := 0
	for resident_id: String in world._resident_order:
		if not world._resident_is_alive(resident_id):
			continue
		if undercover_ids.has(resident_id):
			undercover_alive += 1
		else:
			innocent_alive += 1
	var winner := ""
	if undercover_alive == 0:
		winner = "镇民"
	elif innocent_alive == 0 or innocent_alive <= undercover_alive:
		winner = "卧底"
	if winner.is_empty():
		return false
	world._werewolf_state["gameOver"] = true
	world._werewolf_state["winner"] = winner
	world._werewolf_state["winnerAnnounced"] = false
	# 夜间终局遵循"天亮公布"语义:状态当夜即锁(后续投票/开票全部停摆),
	# 但胜负公告与唤醒压到次日 08:00,先公布死讯再宣布胜负。
	if not _night_silence_active(world):
		_publish_victory(world, winner)
		world._werewolf_state["winnerAnnounced"] = true
	return true


## 08:00 死讯公布完成后,补发昨夜延迟的胜负公告(白天终局不经过这里)。
static func announce_pending_victory(
	world,
	absolute_minute: int = -1,
) -> void:
	if not bool(world._werewolf_state.get("gameOver", false)):
		return
	if bool(world._werewolf_state.get("winnerAnnounced", false)):
		return
	var winner := String(world._werewolf_state.get("winner", ""))
	if winner.is_empty():
		return
	var time_label: String = (
		_label_for_minute(absolute_minute)
		if absolute_minute >= 0
		else String(world._time_label())
	)
	_publish_victory(world, winner, time_label)
	world._werewolf_state["winnerAnnounced"] = true


static func _publish_victory(
	world,
	winner: String,
	time_label: String = "",
) -> void:
	if time_label.is_empty():
		time_label = world._time_label()
	var text := ""
	if winner == "镇民":
		text = "小镇终于恢复安宁：所有潜伏的卧底都已被清除。镇民阵营获胜！"
	else:
		text = "小镇彻底沦陷：无辜者已不足以制衡潜伏的卧底。卧底阵营获胜。"
	TOWN_LOG.section("胜负已定：%s胜" % winner)
	world.broadcast_announcement(text)
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | 胜负已定：%s胜" % [time_label, winner],
	)
	for resident_id: String in world._resident_order:
		if world._resident_is_alive(resident_id):
			world._schedule_decision(resident_id, true)


## 当前是否处于"夜间静默":夜间终局不即时广播胜负。
static func _night_silence_active(world) -> bool:
	var minute := -1
	if world.has_method("_authoritative_absolute_minute"):
		minute = int(world.call("_authoritative_absolute_minute"))
	else:
		var environment: Variant = world.get("_environment")
		if environment != null:
			minute = int(environment.call("get_absolute_minute"))
	if minute < 0:
		return false
	return is_night(minute)
