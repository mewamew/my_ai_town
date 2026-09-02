class_name TownUndercoverDeadlineRuntime
extends RefCounted
## 卧底期限机制:第5天结束未杀完 → 第6/7/8天依次处决卧底;无辜全灭 → 警察失败。
## 挂在 TownWorldRuntime 每日推进链上,由 world 调用。

const POLICE_JOB := "警察"
const DEADLINE_DAYS := 5            # 卧底任务期限:第5天结束前必须杀完
const EXECUTION_DAYS := [6, 7, 8]  # 逾期后第6/7/8天各处决一个卧底
const CHECK_MINUTE := 1440 - 1     # 每天最后一分钟检查(接近第X天结束)


static func check_deadline(world, absolute_minute: int) -> void:
	if not world._running:
		return
	var minute_of_day := posmod(absolute_minute, 1440)
	if minute_of_day != CHECK_MINUTE:
		return
	var day_index := absolute_minute / 1440
	if day_index < 1:
		return
	# 统计卧底与无辜存活人数
	var undercover_ids: Array[String] = world._undercover_resident_ids()
	var alive_undercover: Array[String] = []
	var innocent_alive := 0
	for resident_id: String in world._resident_order:
		if not world._resident_is_alive(resident_id):
			continue
		if undercover_ids.has(resident_id):
			alive_undercover.append(resident_id)
		else:
			innocent_alive += 1
	# 无辜全灭 → 警察失败(卧底赢)
	if innocent_alive == 0:
		world._undercover_declare_police_failed(day_index)
		return
	# 逾期未杀完 → 按天处决卧底
	if day_index in EXECUTION_DAYS and not alive_undercover.is_empty():
		var executed_id := alive_undercover[0]
		var deadline_reason := "卧底任务逾期未完成，组织按规矩处决"
		world.confirm_resident_death(executed_id, deadline_reason)
		var name: String = world._resident_display_name(executed_id)
		world.publish_resident_announcement(
			executed_id,
			"组织公告：%s 因任务逾期未完成，已被组织处决。其余卧底继续执行任务。" % name,
		)
