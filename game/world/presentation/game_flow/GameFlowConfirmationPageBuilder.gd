class_name GameFlowConfirmationPageBuilder
extends RefCounted


# 三张启动确认页视图模型的纯函数构建器(自 GameFlowHost 下沉):
# 新开局覆盖确认/删除存档确认/损坏档继续恢复确认。
# 输入只有 discovery 快照与宿主流程修订号,无自有状态。

const UI_VIEW_MODEL := preload("res://ui/common/AiTownUiViewModel.gd")


static func new_game_overwrite(
	discovery: Dictionary,
	flow_revision: int,
	fallback_slot_id: String,
) -> Dictionary:
	var summary := discovery.get("summary", {}) as Dictionary
	var slot_id := String(summary.get("slotId", fallback_slot_id))
	var save_revision := int(summary.get("saveRevision", 0))
	var saved_at := String(summary.get("savedAt", ""))
	return {
		"scope": "session",
		"status": "ready",
		"revision": maxi(flow_revision, 1),
		"data": {
			"mode": "new_game_overwrite",
			"sessionId": "",
			"canEnterTown": false,
			"residentCount": int(summary.get("residentCount", 0)),
			"providerStatus": "available",
			"loadSummary": {
				"promptId": "overwrite-%s-%d" % [slot_id, save_revision],
				"condition": "healthy",
				"saveId": "%s:%d" % [slot_id, save_revision],
				"saveRevision": save_revision,
				"savedAt": saved_at,
				"savedAtLabel": saved_at,
				"townSummary": "%d 位居民 · 世界修订 %d" % [
					int(summary.get("residentCount", 0)),
					int(summary.get("worldRevision", 0)),
				],
				"saveVersion": "1",
				"mapVersion": "town-current",
				"requiredSaveVersion": "1",
				"requiredMapVersion": "town-current",
				"recoveryStatus": "not_needed",
				"copy": {
					"kicker": "这里已经住着一座小镇",
					"title": "要开始新的小镇吗？",
					"body": "当前正式存档需要先完成安全覆盖事务，旧进度不会被静默删除。",
					"consequence": "模型设置和游戏设置会继续保留。",
					"cancel": "取消",
					"retryRestore": "继续旧小镇",
					"confirmOverwrite": "覆盖并开始",
					"rediagnose": "",
				},
			},
			"draftRevision": 0,
			"identityStatus": "confirmed",
			"validationMode": "formal",
			"source": "formal",
			"capabilityMode": "formal",
			"formalReady": true,
		},
		"actions": {
			"confirmOverwrite": {
				"intent": "session.overwrite_for_new_game",
				"enabled": true,
				"disabledReason": "",
			},
			"cancel": {
				"intent": "session.cancel_new_game_overwrite",
				"enabled": true,
				"disabledReason": "",
			},
			"retryRestore": {
				"intent": "session.retry_restore",
				"enabled": true,
				"disabledReason": "",
			},
			"rediagnose": {
				"intent": "session.rediagnose_recovery",
				"enabled": false,
				"disabledReason": "ACTION_NOT_AVAILABLE_IN_MODE",
			},
		},
		"operation": UI_VIEW_MODEL.idle_operation(),
		"error": null,
	}


static func delete_save(
	discovery: Dictionary,
	flow_revision: int,
	fallback_slot_id: String,
) -> Dictionary:
	var summary := discovery.get("summary", {}) as Dictionary
	var slot_id := String(summary.get("slotId", fallback_slot_id))
	var display_name := String(discovery.get("displayName", slot_id))
	var save_revision := int(summary.get("saveRevision", 0))
	var saved_at := String(summary.get("savedAt", ""))
	var slot_state := String(discovery.get("slotState", "corrupt"))
	var condition := (
		"healthy" if slot_state in ["healthy", "complete"] else "corrupt"
	)
	var town_summary := (
		"第 %d 天 · %d 位居民 · 世界修订 %d" % [
			int(summary.get("day", 0)),
			int(summary.get("residentCount", 0)),
			int(summary.get("worldRevision", 0)),
		]
		if not summary.is_empty() and save_revision > 0
		else "当前状态：%s" % slot_state
	)
	return {
		"scope": "session",
		"status": "ready",
		"revision": maxi(flow_revision, 1),
		"data": {
			"mode": "delete_save",
			"sessionId": String(summary.get("sessionId", "")),
			"canEnterTown": false,
			"residentCount": int(summary.get("residentCount", 0)),
			"providerStatus": "not_required",
			"loadSummary": {
				"promptId": "delete-%s-%d" % [slot_id, save_revision],
				"condition": condition,
				"saveId": "%s:%d" % [slot_id, save_revision],
				"saveRevision": save_revision,
				"savedAt": saved_at,
				"savedAtLabel": saved_at if not saved_at.is_empty() else "保存时间未知",
				"townSummary": town_summary,
				"saveVersion": "1",
				"mapVersion": "town-current",
				"requiredSaveVersion": "1",
				"requiredMapVersion": "town-current",
				"recoveryStatus": "not_needed",
				"copy": {
					"kicker": "存档管理",
					"title": "删除%s？" % display_name,
					"body": "确认后，这座小镇会从加载列表中移除，当前槽位会变为空槽。",
					"consequence": "系统会先安全归档 World、Agent 与 manifest；失败时原存档保持不变。",
					"cancel": "返回",
					"retryRestore": "",
					"confirmOverwrite": "确认删除",
					"rediagnose": "",
				},
			},
			"draftRevision": 0,
			"identityStatus": "confirmed",
			"validationMode": "formal",
			"source": "formal",
			"capabilityMode": "formal",
			"formalReady": true,
		},
		"actions": {
			"confirmOverwrite": {
				"intent": "save.confirm_delete_slot",
				"enabled": true,
				"disabledReason": "",
			},
			"cancel": {
				"intent": "save.cancel_delete_slot",
				"enabled": true,
				"disabledReason": "",
			},
			"retryRestore": {
				"intent": "session.retry_restore",
				"enabled": false,
				"disabledReason": "ACTION_NOT_AVAILABLE_IN_MODE",
			},
			"rediagnose": {
				"intent": "session.rediagnose_recovery",
				"enabled": false,
				"disabledReason": "ACTION_NOT_AVAILABLE_IN_MODE",
			},
		},
		"operation": UI_VIEW_MODEL.idle_operation(),
		"error": null,
	}


static func continue_recovery(
	discovery: Dictionary,
	flow_revision: int,
	fallback_slot_id: String,
) -> Dictionary:
	var summary := discovery.get("summary", {}) as Dictionary
	var plan := discovery.get("recoveryPlan", {}) as Dictionary
	var action := String(plan.get("action", ""))
	var damage := (discovery.get("damageDetails", {}) as Dictionary).duplicate(true)
	var progress_rollback := bool(damage.get("progressRollback", false))
	var slot_id := String(summary.get("slotId", fallback_slot_id))
	var save_revision := int(summary.get("saveRevision", 0))
	if damage.is_empty():
		damage = {
			"damagedSaveRevision": int(
				plan.get("damagedSaveRevision", save_revision),
			),
			"fallbackSaveRevision": save_revision,
			"progressRollback": false,
		}
	var damaged_revision := int(damage.get("damagedSaveRevision", -1))
	var damaged_saved_at := String(damage.get("damagedSavedAt", ""))
	var damage_label := (
		"revision %d（%s）" % [damaged_revision, damaged_saved_at]
		if not damaged_saved_at.is_empty()
		else "revision %d" % damaged_revision
	)
	var title := "使用最近完整存档？"
	var body := (
		"最新的 %s 已损坏。将恢复最近完整的 "
		+ "World + Agent 配对 revision %d，并发布新的完整修订。"
	) % [damage_label, save_revision]
	var consequence := (
		"确认后会回退确已保存的游戏进度；原存档和损坏证据都会保留。"
		if progress_rollback
		else "确认后将修复为可验证的完整存档；原存档和损坏证据都会保留。"
	)
	var execute_copy := "执行修复"
	if action == "reconcile_interrupted_transactions":
		title = "完成上次存档事务？"
		body = "已根据事务日志和已发布的 World + Agent 配对生成协调计划。"
		consequence = "确认后只封口已核实的中断事务；原存档和日志证据都会保留。"
	elif action == "export_save_diagnostic":
		title = "此存档无法安全修复"
		body = "没有足够证据重建完整的 World + Agent 配对，系统不会猜测游戏进度。"
		consequence = "可以导出去敏诊断记录；原存档不会被修改或删除。"
		execute_copy = "导出诊断"
	return {
		"scope": "session",
		"status": "ready",
		"revision": maxi(flow_revision, 1),
		"data": {
			"mode": "continue_recovery",
			"sessionId": String(summary.get("sessionId", "")),
			"canEnterTown": false,
			"residentCount": int(summary.get("residentCount", 0)),
			"providerStatus": "unchecked",
			"loadSummary": {
				"promptId": "continue-recovery-%s-%d" % [slot_id, damaged_revision],
				"condition": "corrupt",
				"saveId": "%s:%d" % [slot_id, save_revision],
				"saveRevision": save_revision,
				"savedAt": String(summary.get("savedAt", "")),
				"savedAtLabel": String(summary.get("savedAt", "")),
				"townSummary": "第 %d 天 · %d 位居民 · 世界修订 %d" % [
					int(summary.get("day", 0)),
					int(summary.get("residentCount", 0)),
					int(summary.get("worldRevision", 0)),
				],
				"saveVersion": "1",
				"mapVersion": "town-current",
				"requiredSaveVersion": "1",
				"requiredMapVersion": "town-current",
				"recoveryStatus": "progress_rollback_confirmation",
				"damageDetails": damage.duplicate(true),
				"copy": {
					"kicker": "存档处理确认",
					"title": title,
					"body": body,
					"consequence": consequence,
					"cancel": "仅返回",
					"retryRestore": execute_copy,
					"confirmOverwrite": "",
					"rediagnose": "重新诊断",
				},
			},
			"draftRevision": 0,
			"identityStatus": "confirmed",
			"validationMode": "formal",
			"source": "formal",
			"capabilityMode": "formal",
			"formalReady": true,
		},
		"actions": {
			"confirmOverwrite": {
				"intent": "session.overwrite_for_new_game",
				"enabled": false,
				"disabledReason": "ACTION_NOT_AVAILABLE",
			},
			"cancel": {
				"intent": "session.cancel_continue_recovery",
				"enabled": true,
				"disabledReason": "",
			},
			"retryRestore": {
				"intent": "session.confirm_recovery",
				"enabled": true,
				"disabledReason": "",
			},
			"rediagnose": {
				"intent": "session.rediagnose_recovery",
				"enabled": true,
				"disabledReason": "",
			},
		},
		"operation": UI_VIEW_MODEL.idle_operation(),
		"error": null,
	}
