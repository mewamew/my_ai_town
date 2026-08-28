class_name TownWerewolfRuntime
extends RefCounted
## 狼人杀化核心运行时(2026-08-16 MVP, 2026-08-27 审讯会改造):
## ①夜间(20:00-08:00)暗杀死亡不即时公告,次日 08:00 统一公布("天亮发现尸体")
## ②每天 08:00 警察审讯会开始(替代旧"11:00 镇民大会"):
##   汇报期(全员向警察秘密汇报/不汇报,收齐或 60s 超时)→ 审讯期(警察最多审
##   5 人,可随时结束,逐字稿累积,不实时广播)→ 投票期(审讯记录一次性注入
##   全员,全员只有投票选项,投完或 90s 超时立即开票)→ 公布后散会。
##   大会期间世界冻结(advance 短路,独立大会标志,不走 is_paused,LLM 派发
##   与对话仍放行),投票得票最高者被放逐并公布身份。
## ③胜负判定:卧底全灭=镇民胜;平民全灭或平民数≤卧底数=卧底胜
## 状态挂在 world._werewolf_state(Dictionary),随存档走 werewolfState 域。
## 挂载点:TWR 每日推进链 _sync_production_tasks 之后 advance()。


const NIGHT_START_MINUTE := 1200  # 20:00
const DAWN_MINUTE := 480          # 08:00 天亮公布昨夜死讯
const VOTE_START_MINUTE := 480    # 08:00 天亮后警察审讯会开始(原镇民大会)
const VOTE_SETTLE_MINUTE := 750   # 12:30 兜底开票(大会冻结期间到不了,解冻异常时兜底)
const EXILE_REASON := "被警察审讯会投票放逐"
## 警察审讯会参数。
const ASSEMBLY_REPORT_TIMEOUT_SECONDS := 60.0   # 汇报期真实超时(超时者视为不汇报)
const ASSEMBLY_VOTE_TIMEOUT_SECONDS := 90.0     # 投票期真实超时(超时未投者弃权,立即开票)
const ASSEMBLY_INTERROGATION_MAX := 5           # 警察最多审讯人数(每次发起新询问 +1,追问不限)
const ASSEMBLY_INTERROGATION_TIMEOUT_SECONDS := 600.0  # 审讯期兜底超时(警察卡死防永久冻结)
## 汇报类型: 目击/听到/怀疑 为有内容汇报, 不汇报 计入"已交"但内容为空。
const ASSEMBLY_REPORT_KINDS: Array[String] = ["目击", "听到", "怀疑", "不汇报"]
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
		"vote": {},                       # 进行中的投票回合(审讯会投票期)
		"assembly": default_assembly_state(),  # 警察审讯会状态(2026-08-27)
		"gameOver": false,
		"winner": "",
		"winnerAnnounced": false,         # 胜负公告是否已发出(夜间终局压到天亮)
		"roleSkills": ROLE_SKILL_RUNTIME.default_role_skills(),
		"undercoverKillLastNight": -1,    # 全卧底阵营每晚最多 1 杀（-1=未杀过）
		"policeAlertCharges": 1,          # 警察每局 1 次警觉免死(暗杀被挡下)
		"policeDevices": {},              # 警察追踪装置安装状态(单一槽位,监听/定位/重大行动一体)
	}


## 审讯会默认状态。phase 取值: idle(无大会)/report(汇报期)/interrogation(审讯期)/
## vote(投票期)。frozen 派生自 phase != idle(世界冻结,见 assembly_frozen)。
## 阶段推进由真实秒驱动(tick_assembly,见 TownWorldAdvanceRuntime.advance 短路前),
## 不依赖游戏分钟——大会冻结时分钟不推进,超时/收齐是仅有的阶段切换源。
static func default_assembly_state() -> Dictionary:
	return {
		"phase": "idle",
		"day": -1,
		"reports": {},            # resident_id -> {"kind": String, "line": String}
		"reportElapsed": 0.0,     # 汇报期已过真实秒
		"reportSummary": [],      # 汇报汇总(切审讯时打包,注入警察 wake): {resident_id,name,kind,line}
		"interrogationTargets": [],  # 可审候选: {resident_id, name}
		"interrogated": [],       # 已审完的 resident_id
		"interrogationCount": 0,  # 已发起询问的人数(≤ASSEMBLY_INTERROGATION_MAX)
		"interrogationTranscript": [],  # 审讯逐字稿: {minute, speaker_id, speaker, say}
		"interrogationElapsed": 0.0,    # 审讯期已过真实秒(兜底超时用)
		"voteElapsed": 0.0,       # 投票期已过真实秒
		"announced": false,       # 本次大会是否已开票公布
	}


## 警察追踪装置: 1 个槽位,装新目标覆盖旧的,时长 1 天(游戏时间)。
## 一次安装同时获得: 目标对话(原窃听) + 行踪目的地(原定位) + 重大行动上报。
const POLICE_DEVICE_DURATION_MINUTES := 1440
const POLICE_DEVICE_TRACKER := "tracker"


static func police_device_state(world, device_key: String) -> Dictionary:
	var devices := world._werewolf_state.get("policeDevices", {}) as Dictionary
	return (devices.get(device_key, {}) as Dictionary).duplicate()


static func install_police_device(
	world,
	device_key: String,
	target_id: String,
	installed_by: String,
	minute: int,
) -> void:
	var devices := world._werewolf_state.get("policeDevices", {}) as Dictionary
	devices[device_key] = {
		"targetId": target_id,
		"installedBy": installed_by,
		"installedMinute": minute,
		"expireMinute": minute + POLICE_DEVICE_DURATION_MINUTES,
		# 追踪档案: 装置监听期间收集的情报(对话/行踪/重大行动)。
		# 装新目标覆盖旧装置时随之重置; 过期后仍保留直到被覆盖。
		"log": [],
	}
	world._werewolf_state["policeDevices"] = devices


## 装置是否正在监听指定目标(未过期)。
static func police_device_active(
	world,
	device_key: String,
	target_id: String,
	minute: int,
) -> bool:
	var device := police_device_state(world, device_key)
	return (
		String(device.get("targetId", "")) == target_id
		and int(device.get("expireMinute", -1)) > minute
	)


## 追踪装置档案: 已记录的情报列表(含过期记录, 直到装新目标覆盖)。
## 一条 = {minute: 记录时刻(绝对分钟), text: 情报文本}。
static func police_tracker_log(world) -> Array:
	var device := police_device_state(world, POLICE_DEVICE_TRACKER)
	return (device.get("log", []) as Array).duplicate()


## 把一条情报记入追踪档案。仅当装置正在监听该目标(未过期)时才记录,
## 返回是否已记入。对话/行踪/重大行动三个情报钩子共用; 不再实时投递
## 事件给警察, 警察只能去镇公所查案阅读档案。
static func append_police_tracker_log(
	world,
	target_id: String,
	minute: int,
	text: String,
) -> bool:
	if not police_device_active(world, POLICE_DEVICE_TRACKER, target_id, minute):
		return false
	var devices := world._werewolf_state.get("policeDevices", {}) as Dictionary
	var device := devices.get(POLICE_DEVICE_TRACKER, {}) as Dictionary
	if device.is_empty():
		return false
	var log := device.get("log", []) as Array
	log.append({"minute": minute, "text": text})
	device["log"] = log
	devices[POLICE_DEVICE_TRACKER] = device
	world._werewolf_state["policeDevices"] = devices
	return true


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
		start_assembly(world, absolute_minute)
	# 12:00 补投提醒已取消: 审讯会投票期由"全员投完/90s 超时"驱动,
	# 进入投票期时已全员唤醒, 无需中间补投。
	if minute_of_day == VOTE_SETTLE_MINUTE:
		# 兜底: 大会冻结期间到不了 12:30, 此处仅在"大会异常未冻结"时兜底开票。
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


# ===================== 警察审讯会(2026-08-27) =====================
## 把旧"镇民大会(11:00 定时投票)"改造为警察审讯会: 08:00 触发后世界冻结
## (见 TownWorldAdvanceRuntime.advance 大会短路), 依次经历 汇报期→审讯期→
## 投票期, 投票收齐/超时立即开票, 公布后散会解冻。请求消耗目标:
## 汇报期=存活居民×1(每人一次汇报), 审讯期=仅警察+被审者×轮数,
## 散会注入=0(数据写入 wake), 投票期=存活居民×1。

## 大会当前状态(永不返回空, 缺省回退 idle)。
static func assembly_state(world) -> Dictionary:
	return world._werewolf_state.get("assembly", {}) as Dictionary


## 大会是否进行中(汇报/审讯/投票任一阶段)。
static func assembly_active(world) -> bool:
	var assembly := assembly_state(world)
	return String(assembly.get("phase", "idle")) != "idle"


## 大会当前阶段: idle/report/interrogation/vote。
static func assembly_phase(world) -> String:
	return String(assembly_state(world).get("phase", "idle"))


## 世界是否因大会而冻结。与 host.is_paused() 相互独立: 大会冻结只短路
## advance(分钟不推进), 不置暂停标志, 因此 LLM 决策派发与对话仍然放行。
static func assembly_frozen(world) -> bool:
	return assembly_active(world)


## 存活居民 ID 列表(按 _resident_order)。
static func _assembly_alive_ids(world) -> Array[String]:
	var alive_ids: Array[String] = []
	for resident_id: String in world._resident_order:
		if world._resident_is_alive(resident_id):
			alive_ids.append(resident_id)
	return alive_ids


## 当前存活警察的 resident_id(没有则返回空串)。
static func _assembly_police_id(world) -> String:
	for resident_id: String in world._resident_order:
		if world._resident_is_alive(resident_id) and world._resident_is_police(resident_id):
			return resident_id
	return ""


## 唤醒全体存活居民(伴随当前动作, 不打断手头的事; 与旧大会唤醒同参数)。
static func _assembly_wake_all(world) -> void:
	for resident_id: String in world._resident_order:
		if world._resident_is_alive(resident_id):
			world._schedule_decision(resident_id, true, false, false, false, true)


## 08:00:开启警察审讯会(替代旧 start_vote_round)。
## 进入汇报期并冻结世界: 全员(非警察)向警察秘密汇报目击/听到/怀疑/不汇报。
static func start_assembly(world, absolute_minute: int) -> void:
	if not feature_active(world):
		return
	if world._werewolf_state.get("gameOver", false):
		return
	var day_index := absolute_minute / 1440
	if day_index < 1:
		return
	# 天数快照已在同一天开过就不再重开(存档恢复防重)
	var existing := world._werewolf_state.get("assembly", {}) as Dictionary
	if int(existing.get("day", -1)) == day_index:
		return
	var alive_ids := _assembly_alive_ids(world)
	if alive_ids.size() < 3:
		return
	var assembly := default_assembly_state()
	assembly["phase"] = "report"
	assembly["day"] = day_index
	world._werewolf_state["assembly"] = assembly
	TOWN_LOG.section(
		"%s · 警察审讯会开始(世界冻结)" % _label_for_minute(absolute_minute),
	)
	world.broadcast_announcement(
		"警察审讯会开始：小镇时间暂时冻结。所有居民请向警察汇报你昨晚的所见所闻"
		+ "（目击 / 听到 / 怀疑），没有线索也可以选择不汇报。汇报收齐后警察将逐一提审。",
	)
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | 第%d天审讯会开始，汇报期(存活 %d 人)" % [
			_label_for_minute(absolute_minute),
			day_index,
			alive_ids.size(),
		],
	)
	# 汇报期唤醒: 非警察居民提交汇报。警察不汇报, 等汇报收齐后一次性唤醒。
	for resident_id: String in alive_ids:
		if world._resident_is_police(resident_id):
			continue
		world._schedule_decision(resident_id, true, false, false, false, true)


## 居民提交汇报(决策附件 report / 即时动作「向警察汇报」双通道)。
## 返回错误字符串, 空串=已记录。收齐后自动进入审讯期并唤醒警察。
static func submit_report(world, resident_id: String, value: Dictionary) -> String:
	if not feature_active(world):
		return "当前没有进行中的审讯会"
	if world._werewolf_state.get("gameOver", false):
		return "小镇胜负已定"
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	if String(assembly.get("phase", "idle")) != "report":
		return "当前不在汇报期"
	if not world._resident_is_alive(resident_id):
		return "你已不在镇上，无法汇报"
	if world._resident_is_police(resident_id):
		return "警察主持审讯，无需汇报"
	var reports := assembly.get("reports", {}) as Dictionary
	if reports.has(resident_id):
		return "你已经提交过汇报了，一次审讯只能汇报一次"
	var kind := String(value.get("kind", "")).strip_edges()
	if not ASSEMBLY_REPORT_KINDS.has(kind):
		return "汇报类型 kind 必须是：%s" % "、".join(ASSEMBLY_REPORT_KINDS)
	var line := String(value.get("line", "")).strip_edges()
	if kind != "不汇报" and line.is_empty():
		return "汇报内容 line 不能为空"
	reports[resident_id] = {
		"kind": kind,
		"line": line,
		"resident_id": resident_id,
		"resident_name": world._resident_display_name(resident_id),
	}
	assembly["reports"] = reports
	world._werewolf_state["assembly"] = assembly
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | %s 汇报：%s%s" % [
			world._time_label(),
			world._resident_display_name(resident_id),
			kind,
			("：" + line) if not line.is_empty() else "",
		],
	)
	if _assembly_reports_collected(world, assembly):
		_begin_interrogation(world)
	return ""


## 汇报是否收齐: 所有存活非警察居民均已提交(含"不汇报")。
static func _assembly_reports_collected(world, assembly: Dictionary) -> bool:
	var reports := assembly.get("reports", {}) as Dictionary
	for resident_id: String in world._resident_order:
		if not world._resident_is_alive(resident_id):
			continue
		if world._resident_is_police(resident_id):
			continue
		if not reports.has(resident_id):
			return false
	return true


## 汇报收齐/超时 → 进入审讯期: 打包汇报汇总, 一次性唤醒警察(零请求零回复,
## 汇总直接注入警察 wake), 警察最多审 ASSEMBLY_INTERROGATION_MAX 人。
static func _begin_interrogation(world) -> void:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	assembly["phase"] = "interrogation"
	assembly["reportElapsed"] = 0.0
	assembly["interrogationElapsed"] = 0.0
	assembly["interrogationTranscript"] = []
	assembly["interrogationCount"] = 0
	assembly["interrogated"] = []
	var summary: Array = []
	for resident_id: String in world._resident_order:
		if not world._resident_is_alive(resident_id):
			continue
		if world._resident_is_police(resident_id):
			continue
		var report := (assembly.get("reports", {}) as Dictionary).get(
			resident_id,
			{"kind": "未汇报", "line": ""},
		) as Dictionary
		summary.append({
			"resident_id": resident_id,
			"name": world._resident_display_name(resident_id),
			"kind": String(report.get("kind", "未汇报")),
			"line": String(report.get("line", "")),
		})
	assembly["reportSummary"] = summary
	# 可审候选: 存活非警察、尚未被审(警察可随时提前结束, 不强制审满)。
	var targets: Array = []
	for resident_id: String in world._resident_order:
		if not world._resident_is_alive(resident_id):
			continue
		if world._resident_is_police(resident_id):
			continue
		targets.append({
			"resident_id": resident_id,
			"name": world._resident_display_name(resident_id),
		})
	assembly["interrogationTargets"] = targets
	world._werewolf_state["assembly"] = assembly
	var police_id := _assembly_police_id(world)
	if police_id.is_empty():
		# 警察已死(或不存在): 无审讯者, 跳过审讯直接进入投票期。
		TOWN_LOG.line(
			"WEREWOLF",
			"%s | 镇上没有警察，审讯环节跳过，直接进入投票期" % world._time_label(),
		)
		_begin_vote(world)
		return
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | 汇报收齐，%d 人汇报，进入审讯期(警察最多审 %d 人)" % [
			world._time_label(),
			summary.size(),
			ASSEMBLY_INTERROGATION_MAX,
		],
	)
	world.broadcast_announcement(
		"居民汇报已收齐。警察开始逐一提审嫌疑人，请其余居民耐心等待。",
	)
	# 一次性唤醒警察: 汇报汇总已打包进 wake(assembly_wake_snapshot)。
	world._schedule_decision(police_id, true, false, false, false, true)


## 审讯逐字稿记录(对话引擎钩子调用, 见 TownConversationRuntime 狼人杀钩子区)。
## 仅在审讯期且对话双方=警察+非警察居民时记录; 不实时广播, 散会时一次性
## 注入投票 wake。返回是否已记录。
static func record_interrogation_turn(
	world,
	speaker_id: String,
	other_id: String,
	minute: int,
	say: String,
) -> bool:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	if String(assembly.get("phase", "idle")) != "interrogation":
		return false
	if say.strip_edges().is_empty():
		return false
	var speaker_is_police: bool = world._resident_is_police(speaker_id)
	var other_is_police: bool = world._resident_is_police(other_id)
	if speaker_is_police == other_is_police:
		return false  # 双方同阵营(都警察或都平民)不算审讯
	var transcript := assembly.get("interrogationTranscript", []) as Array
	transcript.append({
		"minute": minute,
		"speaker_id": speaker_id,
		"speaker": world._resident_display_name(speaker_id),
		"say": say.strip_edges(),
	})
	assembly["interrogationTranscript"] = transcript
	world._werewolf_state["assembly"] = assembly
	return true


## 审讯期: 警察向某居民发起询问是否允许(供 prepare_talk_action 放宽距离/
## 冷却校验)。目标必须存活、非警察、尚未被审; 发起者必须是警察。
## 返回 "" 表示允许, 非空为拒绝原因。
static func police_interrogation_allowed(
	world,
	initiator_id: String,
	target_id: String,
) -> String:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	if String(assembly.get("phase", "idle")) != "interrogation":
		return ""
	if not world._resident_is_police(initiator_id):
		return ""
	if not world._resident_is_alive(target_id):
		return "目标已不在镇上"
	if world._resident_is_police(target_id):
		return "不能审讯警察"
	if (assembly.get("interrogated", []) as Array).has(target_id):
		return "%s 已经接受过审讯了" % world._resident_display_name(target_id)
	if int(assembly.get("interrogationCount", 0)) >= ASSEMBLY_INTERROGATION_MAX:
		return "本轮审讯次数已用完(%d 人)" % ASSEMBLY_INTERROGATION_MAX
	return ""


## 审讯登记(对话引擎 _start_conversation 钩子调用): 警察发起搭话成功开对话时
## 计数+1 并把目标登记为已审(幂等——普通居民对话/非审讯期均返回 false)。
## 注意: 此处严格校验阵营, 不复用 police_interrogation_allowed(它把"非警察
## 发起"按"非审讯场景"宽松放行, 那是给 prepare_talk_action 的语义)。
## 返回是否登记成功。
static func begin_interrogation_target(
	world,
	initiator_id: String,
	target_id: String,
) -> bool:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	if String(assembly.get("phase", "idle")) != "interrogation":
		return false
	if not world._resident_is_police(initiator_id):
		return false
	if not world._resident_is_alive(target_id):
		return false
	if world._resident_is_police(target_id):
		return false
	if (assembly.get("interrogated", []) as Array).has(target_id):
		return false
	if int(assembly.get("interrogationCount", 0)) >= ASSEMBLY_INTERROGATION_MAX:
		return false
	assembly["interrogationCount"] = int(assembly.get("interrogationCount", 0)) + 1
	var interrogated := assembly.get("interrogated", []) as Array
	if not interrogated.has(target_id):
		interrogated.append(target_id)
	assembly["interrogated"] = interrogated
	var targets := assembly.get("interrogationTargets", []) as Array
	if targets.has(target_id):
		targets.erase(target_id)
		assembly["interrogationTargets"] = targets
	world._werewolf_state["assembly"] = assembly
	return true


## 警察结束当前审讯(主动选择「结束审讯」): 进入投票期, 审讯逐字稿一次性
## 注入全员投票 wake。也可由审满 ASSEMBLY_INTERROGATION_MAX 自动触发。
## 返回错误字符串, 空串=已结束。
static func end_interrogation(world, resident_id: String) -> String:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	if String(assembly.get("phase", "idle")) != "interrogation":
		return "当前不在审讯期"
	if not world._resident_is_police(resident_id):
		return "只有警察可以结束审讯"
	_begin_vote(world)
	return ""


## 审讯期 → 投票期: 开新投票回合(候选=存活非警察), 全员唤醒,
## 投票 wake 携带审讯逐字稿(assembly_wake_snapshot)。
static func _begin_vote(world) -> void:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	var alive_ids := _assembly_alive_ids(world)
	var candidate_ids: Array[String] = []
	for resident_id: String in alive_ids:
		# 警察不参与放逐候选(仍可投票, 只是不能被投)。
		if world._resident_is_police(resident_id):
			continue
		candidate_ids.append(resident_id)
	assembly["phase"] = "vote"
	assembly["voteElapsed"] = 0.0
	world._werewolf_state["assembly"] = assembly
	world._werewolf_state["vote"] = {
		"day": int(assembly.get("day", -1)),
		"votes": {},  # voter_id -> {"target_resident_id": String, "target_resident_name": String, "line": String}
		"candidateIds": candidate_ids,
	}
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | 审讯结束，进入投票期(候选人 %d 人)，投完即开票" % [
			world._time_label(),
			candidate_ids.size(),
		],
	)
	world.broadcast_announcement(
		"警察审讯结束。全体居民请根据审讯记录投出你怀疑的人：得票最高者将被"
		+ "放逐出镇并公布其身份；平票则无人出局。投票收齐或 90 秒后立即开票。",
	)
	_assembly_wake_all(world)


## 大会散会: 状态复位(idle), 解冻(advance 恢复推进)。由开票公布后调用。
static func _dismiss_assembly(world) -> void:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	assembly["phase"] = "idle"
	assembly["announced"] = true
	world._werewolf_state["assembly"] = assembly


## 真实秒驱动的大会阶段推进(由 TownWorldAdvanceRuntime.advance 每帧调用,
## 在世界冻结短路之前)。超时是阶段切换的兜底源: 汇报期 60s / 审讯期
## 600s / 投票期 90s; 收齐仍优先触发切换(submit_report/submit_vote 内)。
static func tick_assembly(world, real_seconds: float) -> void:
	if not feature_active(world):
		return
	if world._werewolf_state.get("gameOver", false):
		# 终局后大会自动收尾: 作废投票回合并散会解冻, 防止永久冻结。
		world._werewolf_state["vote"] = {}
		_dismiss_assembly_if_assembly_vote(world)
		return
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	match String(assembly.get("phase", "idle")):
		"report":
			assembly["reportElapsed"] = float(assembly.get("reportElapsed", 0.0)) + real_seconds
			if float(assembly.get("reportElapsed", 0.0)) >= ASSEMBLY_REPORT_TIMEOUT_SECONDS:
				TOWN_LOG.line(
					"WEREWOLF",
					"%s | 汇报期超时(%ds)，未汇报者视为不汇报" % [
						world._time_label(),
						int(ASSEMBLY_REPORT_TIMEOUT_SECONDS),
					],
				)
				world._werewolf_state["assembly"] = assembly
				_begin_interrogation(world)
				return
			world._werewolf_state["assembly"] = assembly
		"interrogation":
			assembly["interrogationElapsed"] = (
				float(assembly.get("interrogationElapsed", 0.0)) + real_seconds
			)
			if float(assembly.get("interrogationElapsed", 0.0)) >= ASSEMBLY_INTERROGATION_TIMEOUT_SECONDS:
				TOWN_LOG.line(
					"WEREWOLF",
					"%s | 审讯期超时(%ds)，强制进入投票期" % [
						world._time_label(),
						int(ASSEMBLY_INTERROGATION_TIMEOUT_SECONDS),
					],
				)
				world._werewolf_state["assembly"] = assembly
				_begin_vote(world)
				return
			world._werewolf_state["assembly"] = assembly
		"vote":
			assembly["voteElapsed"] = float(assembly.get("voteElapsed", 0.0)) + real_seconds
			if float(assembly.get("voteElapsed", 0.0)) >= ASSEMBLY_VOTE_TIMEOUT_SECONDS:
				TOWN_LOG.line(
					"WEREWOLF",
					"%s | 投票期超时(%ds)，立即开票" % [
						world._time_label(),
						int(ASSEMBLY_VOTE_TIMEOUT_SECONDS),
					],
				)
				world._werewolf_state["assembly"] = assembly
				settle_vote_round(world, int(world._authoritative_absolute_minute()))
				return
			world._werewolf_state["assembly"] = assembly


## 大会期间动作白名单(TownActionPreparationRuntime.prepare 入口调用)。
## 返回 "" 允许, 非空为拒绝原因。汇报期: 非警察只能「向警察汇报」; 审讯期:
## 警察=搭话/答话/结束审讯, 平民=答话(被审中)/待着; 投票期: 全员只能「投票放逐」。
static func assembly_action_allowed(world, resident_id: String, action_type: String) -> String:
	var phase := assembly_phase(world)
	if phase == "idle":
		return ""
	if not world._resident_is_alive(resident_id):
		return "你已不在镇上"
	var is_police: bool = world._resident_is_police(resident_id)
	match phase:
		"report":
			if is_police:
				return "汇报正在收集中，警察请等待"
			if action_type == "向警察汇报":
				return ""
			return "汇报期只能向警察汇报"
		"interrogation":
			if is_police:
				if action_type in ["搭话", "答话", "结束审讯"]:
					return ""
				return "审讯期警察只能询问居民或结束审讯"
			if action_type in ["答话", "待着"]:
				return ""
			return "审讯进行中，请等待投票开始"
		"vote":
			if action_type == "投票放逐":
				return ""
			return "投票期只能投票放逐"
	return ""



## 时写入 "assembly" 键)。投票选项本体走 exile_vote 快照(vote_snapshot),
## 这里只提供提示与逐字稿; 各阶段"只有某类选项"的裁剪见 constrain_wake。
static func assembly_wake_snapshot(world, resident_id: String) -> Dictionary:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	var phase := String(assembly.get("phase", "idle"))
	if phase == "idle" or world._werewolf_state.get("gameOver", false):
		return {}
	if not world._resident_is_alive(resident_id):
		return {}
	var police_id := _assembly_police_id(world)
	var is_police: bool = world._resident_is_police(resident_id)
	match phase:
		"report":
			var reports := assembly.get("reports", {}) as Dictionary
			var reported := reports.has(resident_id)
			return {
				"phase": "report",
				"frozen": true,
				"reportPrompt": (
					"小镇时间已冻结。你已提交汇报，等待警察收齐汇报后开始审讯。"
					if reported
					else "小镇时间已冻结。请向警察汇报你昨晚的所见所闻：选择汇报类型"
						+ "（目击 / 听到 / 怀疑）并说明内容，没有线索就选「不汇报」。"
				),
				"kinds": ASSEMBLY_REPORT_KINDS,
				"reported": reported,
				"deadlineSeconds": int(ASSEMBLY_REPORT_TIMEOUT_SECONDS),
			}
		"interrogation":
			if is_police:
				var summary := assembly.get("reportSummary", []) as Array
				var targets := assembly.get("interrogationTargets", []) as Array
				return {
					"phase": "interrogation",
					"frozen": true,
					"role": "police",
					"reportSummary": summary,
					"interrogationCount": int(assembly.get("interrogationCount", 0)),
					"interrogationMax": ASSEMBLY_INTERROGATION_MAX,
					"targets": targets,
					"interrogated": assembly.get("interrogated", []) as Array,
					"prompt": (
						"审讯进行中。请从汇报中挑选嫌疑人逐个审问：向目标「搭话」提问，"
						+ "可连续追问。审完一个人后可审下一个，最多审 %d 人。"
						+ "想结束就选「结束审讯」，结束后全员将看到审讯记录并投票。"
					) % ASSEMBLY_INTERROGATION_MAX,
				}
			var interrogated := (assembly.get("interrogated", []) as Array).has(resident_id)
			return {
				"phase": "interrogation",
				"frozen": true,
				"role": "resident",
				"interrogated": interrogated,
				"prompt": (
					"警察正在审讯嫌疑人，时间已冻结。%s"
					% (
						"你已接受过审讯，请耐心等待投票开始。"
						if interrogated
						else "若警察向你问话，请如实回答。"
					)
				),
			}
		"vote":
			var transcript := assembly.get("interrogationTranscript", []) as Array
			return {
				"phase": "vote",
				"frozen": true,
				"transcript": transcript,
				"prompt": "审讯记录已公开，请投票放逐你最怀疑的人。投票收齐后立即开票。",
				"deadlineSeconds": int(ASSEMBLY_VOTE_TIMEOUT_SECONDS),
			}
	return {}


## wake 裁剪: 大会进行期间移除与大会无关的日常选项, 实现"各阶段只有某类
## 选项"。在 finalize 拼装 snapshot 后调用(仅大会激活时)。
static func constrain_wake(world, resident_id: String, snapshot: Dictionary) -> void:
	var assembly := world._werewolf_state.get("assembly", {}) as Dictionary
	var phase := String(assembly.get("phase", "idle"))
	if phase == "idle" or world._werewolf_state.get("gameOver", false):
		return
	if not world._resident_is_alive(resident_id):
		return
	var is_police: bool = world._resident_is_police(resident_id)
	# 大会期间一律屏蔽: 出行目的地 / 冲突选项 / 工作 / 社交传话 / 活动。
	snapshot["life_destination_options"] = []
	snapshot["conflict_tension_options"] = []
	snapshot["conflicts"] = []
	snapshot["conflict_injuries"] = []
	snapshot["medical_follow_up"] = {}
	snapshot["post_injury_reaction"] = {}
	snapshot["work_tasks"] = []
	# 对话跟随选项: 审讯期保留(警察与当前被审者对话需要), 其余阶段清空。
	# finalize 已把当前对话填入 snapshot["conversation"], 这里只做清空/保留。
	if phase != "interrogation":
		snapshot["conversation"] = {}
		snapshot["conversation_follow_up_options"] = []
	# 投票期: 任何人不得发起对话; 汇报/审讯期: 非警察不对话。
	if phase == "vote" or not is_police:
		snapshot["conversation"] = {}
		snapshot["conversation_follow_up_options"] = []
	if phase == "vote":
		snapshot["nearby"] = []
		snapshot["social_matters"] = []
		snapshot["social_exposures"] = []
	# 汇报期非警察: 没有任何日常去向(唯一动作=向警察汇报)。
	if phase == "report" and not is_police:
		snapshot["nearby"] = []
		snapshot["social_matters"] = []
		snapshot["social_exposures"] = []
		snapshot["rhythm"] = {}


## 投票快照:投票回合进行中才非空(进 wake_packet.snapshot.exile_vote)。
## 审讯会投票期(大会 phase==vote)才产生投票回合; legacy 上下文(无大会状态,
## 旧"镇民大会"测试探针)下 vote 非空同样返回。
static func vote_snapshot(world, resident_id: String) -> Dictionary:
	if not feature_active(world):
		return {}
	var vote := world._werewolf_state.get("vote", {}) as Dictionary
	if vote.is_empty() or world._werewolf_state.get("gameOver", false):
		return {}
	if not world._resident_is_alive(resident_id):
		return {}
	var candidate_ids: Array[String] = []
	for candidate_value: Variant in vote.get("candidateIds", []) as Array:
		var candidate_id := String(candidate_value)
		# 不能投自己: 全局候选名单已排除警察与死者, 这里再排除投票者本人。
		if candidate_id == resident_id:
			continue
		candidate_ids.append(candidate_id)
	# 已投票的居民本轮不再重复投票
	if (vote.get("votes", {}) as Dictionary).has(resident_id):
		return {}
	return {
		"round_day": int(vote.get("day", 0)),
		"settle_clock": "全员投完或超时即开票",
		"candidate_ids": candidate_ids,
		"forced": _vote_forced(world),
	}


## 投票是否强制: 审讯会投票期全程强制(居民被唤醒就必须提交 exile_vote,
## 投票是唯一动作); legacy 上下文(无大会)回退旧时间窗口 08:00-12:30。
static func _vote_forced(world) -> bool:
	if assembly_active(world):
		return assembly_phase(world) == "vote"
	var minute_of_day := posmod(
		int(world._authoritative_absolute_minute()),
		1440,
	)
	return (
		minute_of_day >= VOTE_START_MINUTE
		and minute_of_day < VOTE_SETTLE_MINUTE
	)


## 投票是否收齐: 所有存活居民(含警察)均已投票。
static func _assembly_votes_collected(world) -> bool:
	var vote := world._werewolf_state.get("vote", {}) as Dictionary
	var votes := vote.get("votes", {}) as Dictionary
	for resident_id: String in world._resident_order:
		if world._resident_is_alive(resident_id) and not votes.has(resident_id):
			return false
	return true


## 居民提交 exile_vote(TWR 决策提交链调用)。
## 返回错误字符串,空串=投票已记录(方案A: 即时动作分支需把失败反馈给模型重试)。
## 审讯会投票期: 全员投完立即开票(不再等 12:30); legacy 上下文按旧行为处理。
static func submit_vote(world, resident_id: String, value: Dictionary) -> String:
	if not feature_active(world):
		return "当前没有进行中的审讯会投票"
	var vote := world._werewolf_state.get("vote", {}) as Dictionary
	if world._werewolf_state.get("gameOver", false):
		# 终局后投票作废并散会解冻(大会不能永久卡在投票期冻结)。
		world._werewolf_state["vote"] = {}
		_dismiss_assembly_if_assembly_vote(world)
		return "本轮投票未在进行"
	if vote.is_empty():
		return "本轮投票未在进行"
	if assembly_active(world) and assembly_phase(world) != "vote":
		return "当前不在投票期"
	if not world._resident_is_alive(resident_id):
		return "你已不在镇上，无法投票"
	var votes := vote.get("votes", {}) as Dictionary
	if votes.has(resident_id):
		return "你已经投过票了，一票不能改"
	var target_id := String(
		value.get("target_resident_id", "")
	).strip_edges()
	# 容错: 模型有时从选项里抄到 "ID｜名字" 混合格式, 截取 ID 部分再校验。
	if target_id.contains("｜"):
		target_id = target_id.split("｜")[0].strip_edges()
	if target_id.is_empty():
		return "投票目标 target_resident_id 必须是非空居民ID"
	var candidate_ids: Array[String] = []
	for candidate_value: Variant in vote.get("candidateIds", []) as Array:
		candidate_ids.append(String(candidate_value))
	if not candidate_ids.has(target_id):
		return "投票目标 %s 不在候选人名单中" % world._resident_display_name(target_id)
	votes[resident_id] = {
		"target_resident_id": target_id,
		"target_resident_name": world._resident_display_name(target_id),
		"line": String(value.get("line", "")).strip_edges(),
	}
	vote["votes"] = votes
	world._werewolf_state["vote"] = vote
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | %s 投票放逐 %s：%s" % [
			world._time_label(),
			world._resident_display_name(resident_id),
			world._resident_display_name(target_id),
			String(value.get("line", "")),
		],
	)
	# 审讯会: 全员投完立即开票(收齐驱动, 不等超时)。
	if _assembly_votes_collected(world):
		settle_vote_round(world, int(world._authoritative_absolute_minute()))
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
		# 终局同样要散会解冻, 否则大会永久卡在投票期冻结。
		_dismiss_assembly_if_assembly_vote(world)
		return
	var day_index := absolute_minute / 1440
	var vote_day := int(vote.get("day", -1))
	if vote_day != day_index:
		# 大会投票: 投票回合天数来自大会 day。大会冻结期间绝对分钟可能仍未
		# 跨天(如开局当天/测试手动开会), 此时以大会 day 为准, 否则投票回合
		# 会被天数校验作废(症状: vote 已清空但 phase 卡在 vote、不散会)。
		if not (
			assembly_active(world)
			and vote_day == int(assembly_state(world).get("day", -1))
		):
			return
	TOWN_LOG.section(
		"%s · 审讯会开票" % _label_for_minute(absolute_minute),
	)
	var votes := vote.get("votes", {}) as Dictionary
	# 按被投目标聚计: count=得票数, reasons=去重后的投票理由(不公开投票人)。
	var tally: Dictionary = {}
	for voter_value: Variant in votes:
		var ballot := votes[voter_value] as Dictionary
		var target_id := String(
			ballot.get("target_resident_id", "")
		).strip_edges()
		if target_id.is_empty():
			continue
		var entry := tally.get(target_id, {
			"count": 0,
			"reasons": [],
		}) as Dictionary
		entry["count"] = int(entry["count"]) + 1
		var line := String(ballot.get("line", "")).strip_edges()
		if not line.is_empty() and not (entry["reasons"] as Array).has(line):
			(entry["reasons"] as Array).append(line)
		tally[target_id] = entry
	if tally.is_empty():
		world.broadcast_announcement(
			"审讯会投票流会：没有人投出有效票，今晚无人被放逐。",
		)
		_dismiss_assembly_if_assembly_vote(world)
		return
	var detail := _format_vote_tally_detail(world, tally)
	# 找出唯一最高票(并列最高=平票,无人出局)
	var top_id := ""
	var top_count := 0
	var tie := false
	for target_id: String in tally:
		var count := int((tally[target_id] as Dictionary).get("count", 0))
		if count > top_count:
			top_count = count
			top_id = target_id
			tie = false
		elif count == top_count:
			tie = true
	if tie or top_id.is_empty():
		world.broadcast_announcement(
			_attach_vote_detail("审讯会开票：出现平票，今晚无人被放逐。", detail),
		)
		_dismiss_assembly_if_assembly_vote(world)
		return
	var exile_id := top_id
	if exile_id.is_empty() or not world._resident_is_alive(exile_id):
		_dismiss_assembly_if_assembly_vote(world)
		return
	var top_name: String = world._resident_display_name(exile_id)
	var summary := "审讯会开票：%s 以 %d 票被放逐出镇。" % [top_name, top_count]
	if world._undercover_resident_ids().has(exile_id):
		summary += "离开时身份曝光——他竟是潜伏在镇上的卧底！"
	else:
		summary += "他只是个普通居民，小镇错放了一位无辜者。"
	world.broadcast_announcement(_attach_vote_detail(summary, detail))
	TOWN_LOG.line(
		"WEREWOLF",
		"%s | %s" % [_label_for_minute(absolute_minute), summary],
	)
	world.confirm_resident_death(exile_id, EXILE_REASON)
	_dismiss_assembly_if_assembly_vote(world)


## 审讯会开票后散会解冻(时间恢复流动)。legacy 上下文(无大会)不动。
static func _dismiss_assembly_if_assembly_vote(world) -> void:
	if not assembly_active(world):
		return
	_dismiss_assembly(world)
	world.broadcast_announcement("审讯会结束，小镇时间恢复流动。")


# 开票公告附加"票型明细"(每人得票数 + 去重理由,不点名投票人)。
# 社区公告栏单条长度上限 280, 明细过长时优先保正文、裁掉尾部理由。
static func _attach_vote_detail(base: String, detail: String) -> String:
	if detail.is_empty():
		return base
	var combined := "%s　票型：%s" % [base, detail]
	if combined.length() <= 280:
		return combined
	var budget := 280 - base.length() - "　票型：".length()
	if budget <= 0:
		return base
	return "%s　票型：%s…" % [base, detail.substr(0, budget - 1)]


static func _format_vote_tally_detail(world, tally: Dictionary) -> String:
	var parts: Array[String] = []
	var target_ids := tally.keys() as Array
	target_ids.sort_custom(
		func(left: String, right: String) -> bool:
			var left_count := int((tally[left] as Dictionary).get("count", 0))
			var right_count := int((tally[right] as Dictionary).get("count", 0))
			if left_count != right_count:
				return left_count > right_count
			return left < right
	)
	for target_id: String in target_ids:
		var entry := tally[target_id] as Dictionary
		var count := int(entry.get("count", 0))
		var reasons := entry.get("reasons", []) as Array
		var name: String = world._resident_display_name(target_id)
		if reasons.is_empty():
			parts.append("%s %d票" % [name, count])
		else:
			var reason_text := "；".join(
				PackedStringArray(reasons.map(func(r: Variant) -> String: return String(r)))
			)
			parts.append("%s %d票（%s）" % [name, count, reason_text])
	return "；".join(parts)


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
