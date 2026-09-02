class_name TownAgentDecisionSubmissionRuntime
extends RefCounted

const LEGACY_PROP_ACTIVITY_RUNTIME := preload(
	"res://world/runtime/activity/TownLegacyPropActivityRuntime.gd"
)
const AGENT_ACTIVITY_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/activity/TownAgentActivitySubmissionRuntime.gd"
)


const WORLD_PERFORMANCE_PROBE := preload(
	"res://world/runtime/TownWorldPerformanceProbe.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)
const AGENT_DECISION_ENVELOPE_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionEnvelopeRuntime.gd"
)
const AGENT_DECISION_ACCEPTANCE_POLICY := preload(
	"res://world/runtime/agent/TownAgentDecisionAcceptancePolicy.gd"
)
const AGENT_DECISION_ACTION_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionActionRuntime.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const ANNOUNCEMENT_RESIDENT_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementResidentRuntime.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const TOWN_LOG := preload("res://world/runtime/TownLog.gd")

## 即时/回合制关键动作: 这些动作的价值随时间清零, 永不允许走
## prefetched 暂存路径(暂存=回合结束后作废, 模型永远看不到结果)。
## 暗杀/制服/发布公告是提交即结算的即时动作, 暂存后目标可能移动/
## 回合可能结束, 且暂存被 invalidate 清掉时连拒绝反馈都没有
## (实锤: 花子第1天20:23提交暗杀姜澄后被静默暂存销毁, 无成功/
## 失败/回执任何痕迹——用户看到的"暗杀没回复")。
const IMMEDIATE_ACTION_TYPES: Array[String] = [
	"向警察汇报",
	"投票放逐",
	"结束审讯",
	"使用技能",
	"答话",
	"暗杀",
	"制服",
	"发布公告",
]


static func submit(host, resident_name: String, decision: Dictionary) -> Dictionary:
	var submitted_resident_ref := resident_name
	var resident_id: String = host._resident_key(resident_name)
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var decision_id := String(decision.get("decision_id", "")) if decision.get("decision_id") is String else ""
	var probe_lap_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	var entry_error := AGENT_DECISION_ENVELOPE_RUNTIME.submission_entry_error(
		host._running,
		submitted_resident_ref,
		resident_id,
		host._running and not resident_id.is_empty() and host._resident_is_alive(resident_id),
		host.is_paused(),
		resident,
		decision_id,
	)
	if not entry_error.is_empty():
		# 本地修复: 医生守诊的 night_skill 即使决策 stale 也消费技能意图。
		# decision_id 频繁过期会让医生整晚守不成(实锤: 白芷 7 次守诊全部
		# "决定已经失效", 警察无人保护被暗杀); consumed=true 让 gateway
		# 不再 discard/重投, 避免重试风暴。
		if (
			bool(entry_error.get("stale", false))
			and (decision.get("night_skill") is Dictionary)
			and not (decision.get("night_skill") as Dictionary).is_empty()
		):
			host.ROLE_SKILL_RUNTIME.submit_night_skill(
				host,
				resident_id,
				decision.get("night_skill") as Dictionary,
			)
			entry_error = entry_error.duplicate(true)
			entry_error["consumed"] = true
			entry_error["errors"] = [
				"决定已经失效：%s（夜间技能意图已记录）" % decision_id,
			]
		return entry_error
	var submission_context := AGENT_DECISION_ENVELOPE_RUNTIME.submission_context(
		resident,
		host.world_log_domain.journal.decision_story_provenance(
			resident.get("inflightEvents", []) as Array,
			resident.get("inflightResults", []) as Array,
		),
	)
	var inflight_events := submission_context.get("inflightEvents", []) as Array
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "submission_capture_wake")
	var pending_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		resident_id,
	)
	var invitation_requires_reply := CONVERSATION_RUNTIME._is_initial_invitation_for(
		host,
		resident_id,
		pending_conversation,
	)
	if invitation_requires_reply:
		var invitation_error := AGENT_DECISION_ACCEPTANCE_POLICY.invitation_reply_error(decision)
		if not invitation_error.is_empty():
			return invitation_error
	var pending_post_injury_reaction: Dictionary = host.WORLD_EVENT_DELIVERY_PROJECTION.post_injury_reaction_for_host(host,
		resident_id,
		inflight_events,
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "submission_prechecks")
	var announcement_priority_error := ANNOUNCEMENT_RESIDENT_RUNTIME.player_priority_handling_error(decision, inflight_events)
	if not announcement_priority_error.is_empty():
		return announcement_priority_error
	if not invitation_requires_reply and not pending_post_injury_reaction.is_empty():
		var post_injury_error := AGENT_DECISION_ACCEPTANCE_POLICY.post_injury_action_error(
			resident,
			decision,
			pending_post_injury_reaction,
			host.CONTENT_CATALOG.PLACE_CLINIC,
		)
		if not post_injury_error.is_empty():
			return {
				"ok": false,
				"stale": false,
				"consumed": false,
				"errorCode": "POST_INJURY_REACTION_REQUIRED",
				"retryable": true,
				"errors": [post_injury_error],
			}
	submission_context["residentId"] = resident_id
	submission_context["decisionId"] = decision_id
	submission_context["pendingConversation"] = pending_conversation
	submission_context["invitationRequiresReply"] = invitation_requires_reply
	submission_context["pendingPostInjuryReaction"] = pending_post_injury_reaction
	submission_context["probeLapUsec"] = probe_lap_usec
	return consume(host, resident, decision, submission_context)


static func consume(
	host,
	resident: Dictionary,
	decision: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var resident_id := String(context.get("residentId", ""))
	var inflight_events := context.get("inflightEvents", []) as Array
	var inflight_results := context.get("inflightResults", []) as Array
	var decision_wake := context.get("wakePacket", {}) as Dictionary
	ACTION_SUPPORT.consume_valid_request(resident)
	# 飞行期间收到过作废请求(见 Scheduling 的 reRequestAfterResponse):
	# 此处只清标记, 不立即补调度——决策尚未应用, 立即调度会让下一次
	# wake 拿到应用前的世界状态(实锤: 化身对话中居民答完一轮后又被
	# 旧状态唤醒多答一轮, 轮到化身回应的判定被打穿)。后续事件流会
	# 以最新状态重新调度, 无需在这里抢跑。
	resident["reRequestAfterResponse"] = false
	host._bump_world_revision(false)
	var decision_shape_error := ACTION_VALIDATION.validate_decision_shape(
		decision,
		inflight_events,
		inflight_results,
	)
	if not decision_shape_error.is_empty():
		var malformed_action: Variant = decision.get("action")
		if malformed_action is Dictionary:
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(host,
					resident_id,
					resident,
					malformed_action as Dictionary,
					decision_shape_error,
				)
			)
		host._schedule_decision(resident_id, false)
		return host._complete_agent_submission({"ok": false, "stale": false, "errors": [decision_shape_error]})
	var accepted_conversation_follow_up := AGENT_DECISION_ACCEPTANCE_POLICY.accepted_conversation_follow_up(
		decision,
		decision_wake,
		host._action_options,
	)
	host.SOCIAL_RESPONSE_ROUND_RUNTIME.settle_optional_attention(host,
		resident_id,
		(
			decision.get("social_attention", {}) as Dictionary
			if decision.get("social_attention") is Dictionary
			else {}
		),
		((decision_wake.get("snapshot", {}) as Dictionary).get("social_exposures", []) as Array),
	)
	if decision.has("social_response"):
		host.SOCIAL_RESPONSE_ROUND_RUNTIME.submit_optional_response(host,
			resident_id,
			decision.get("social_response"),
		)
	var attachment_submitted := {}
	var attachment_errors: Array[String] = []
	# 附件通道(汇报/投票/夜间技能)先于动作通道提交。记录提交结果供
	# submit_valid 做双通道幂等: 模型同时输出附件+同类型动作(或只输出
	# 附件)时, 附件已生效而动作被拒("已经提交过")会把决策整体打回重试,
	# 重试时附件再报"已经提交过"——汇报实际成功但模型永远看不到成功反馈。
	if decision.has("exile_vote"):
		var vote_error: String = host.WEREWOLF_RUNTIME.submit_vote(
			host,
			resident_id,
			decision.get("exile_vote") as Dictionary,
		)
		attachment_submitted["exile_vote"] = vote_error.is_empty()
		if not vote_error.is_empty():
			attachment_errors.append(vote_error)
	if decision.has("report"):
		var report_error: String = host.WEREWOLF_RUNTIME.submit_report(
			host,
			resident_id,
			decision.get("report") as Dictionary,
		)
		attachment_submitted["report"] = report_error.is_empty()
		if not report_error.is_empty():
			attachment_errors.append(report_error)
	if decision.has("night_skill"):
		var skill_error: String = host.ROLE_SKILL_RUNTIME.submit_night_skill(
			host,
			resident_id,
			decision.get("night_skill") as Dictionary,
		)
		attachment_submitted["night_skill"] = skill_error.is_empty()
		if not skill_error.is_empty():
			attachment_errors.append(skill_error)
	if not attachment_errors.is_empty():
		# 附件被世界侧拒绝时必须留下可见痕迹: 此前失败被吞进布尔值,
		# 模型看不到任何原因(实锤: 警察汇报期的提交凭空消失)。
		TOWN_LOG.line(
			"AGENT",
			"%s | %s 附件提交失败：%s" % [
				host._time_label(),
				host.resident_display_name(resident_id),
				"；".join(attachment_errors),
			],
		)
	context["attachmentSubmitted"] = attachment_submitted
	context["attachmentErrors"] = attachment_errors
	context["probeLapUsec"] = WORLD_PERFORMANCE_PROBE.record_lap(
		int(context.get("probeLapUsec", 0)),
		"submission_validate_and_social",
	)
	context["acceptedConversationFollowUp"] = accepted_conversation_follow_up
	return submit_valid(host, resident, decision, context)


static func submit_valid(
	host,
	resident: Dictionary,
	decision: Dictionary,
	context: Dictionary,
) -> Dictionary:
	var resident_id := String(context.get("residentId", ""))
	var resident_name_for_log: String = host.resident_display_name(resident_id)
	if resident_name_for_log.is_empty():
		resident_name_for_log = resident_id
	var decision_id := String(context.get("decisionId", ""))
	var inflight_events := context.get("inflightEvents", []) as Array
	var inflight_results := context.get("inflightResults", []) as Array
	var decision_wake := context.get("wakePacket", {}) as Dictionary
	var active_conversation := context.get("pendingConversation", {}) as Dictionary
	var is_initial_invitation := bool(context.get("invitationRequiresReply", false))
	var handling := decision.get("handling") as String
	if handling == "continue_current":
		TOWN_LOG.line(
			"AGENT",
			"%s | %s 选择了: 继续当前动作" % [
				host._time_label(),
				resident_name_for_log,
			],
		)
		return AGENT_DECISION_ACTION_RUNTIME.continue_decision(
			host, resident_id, resident, decision, context
		)
	if handling != "replace_current" or typeof(decision.get("action")) != TYPE_DICTIONARY:
		# 附件通道(汇报/投票/夜间技能)已生效时, 无动作也算有效决策:
		# 模型可能只输出附件(legacy 通道), 拒绝会导致附件已生效但决策
		# 报错, 模型重试时附件再报"已经提交过"。
		var attachment_submitted_any := _attachment_submitted_any(
			context.get("attachmentSubmitted", {}) as Dictionary,
		)
		if attachment_submitted_any:
			return host._complete_agent_submission({
				"ok": true,
				"consumed": true,
				"stale": false,
			})
		host._schedule_decision(resident_id, false)
		return host._complete_agent_submission({"ok": false, "stale": false, "errors": ["决定必须继续当前动作或提交新动作"]})
	var action := (decision.get("action", {}) as Dictionary).duplicate(true)
	# 行为流日志: LLM 本轮最终选择的动作(与"收到选项"呼应)
	var decision_conflict_intent := (
		decision.get("conflict_intent", {}) as Dictionary
		if decision.get("conflict_intent") is Dictionary
		else {}
	)
	var choice_summary := String(action.get("type", ""))
	if not decision_conflict_intent.is_empty():
		var intent_kind := String(decision_conflict_intent.get("kind", ""))
		var intent_target := String(decision_conflict_intent.get("target_resident_id", ""))
		if intent_kind.is_empty():
			intent_kind = "意图"
		var intent_label := intent_kind
		if not intent_target.is_empty():
			var intent_target_name: String = host.resident_display_name(intent_target)
			if intent_target_name.is_empty():
				intent_target_name = intent_target
			intent_label += "→%s" % intent_target_name
		choice_summary += "（%s）" % intent_label
	var choice_target := String(action.get("target_resident_id", ""))
	if not choice_target.is_empty():
		var choice_target_name: String = host.resident_display_name(choice_target)
		if choice_target_name.is_empty():
			choice_target_name = choice_target
		choice_summary += " 目标:%s" % choice_target_name
	for choice_key: String in ["place", "prop", "verb", "activity_id"]:
		var choice_value := String(action.get(choice_key, ""))
		if not choice_value.is_empty():
			choice_summary += " %s:%s" % [choice_key, choice_value]
	var choice_text := String(action.get("line", "")).strip_edges()
	if choice_text.is_empty():
		choice_text = String(action.get("text", "")).strip_edges()
	if not choice_text.is_empty():
		choice_text = choice_text.replace("\n", " ")
		if choice_text.length() > 40:
			choice_text = choice_text.substr(0, 40) + "…"
		choice_summary += " 台词:%s" % choice_text
	TOWN_LOG.line(
		"AGENT",
		"%s | %s 选择了: %s" % [
			host._time_label(),
			resident_name_for_log,
			choice_summary,
		],
	)
	var current_action := resident.get("currentAction", {}) as Dictionary
	if (
		bool(context.get("wasPrefetched", false))
		and not current_action.is_empty()
		and not IMMEDIATE_ACTION_TYPES.has(String(action.get("type", "")))
	):
		# 大会/回合制关键动作(见 IMMEDIATE_ACTION_TYPES)永不暂存:
		# 暂存到以后执行时回合早就结束(实锤: 第3天开票后谢眠/许照/沈桥/
		# 唐小满的迟到票被静默暂存再作废, 凭空消失), 必须立即校验——
		# 成则生效, 败则给模型明确拒绝。
		return host._complete_agent_submission(
			AGENT_DECISION_ENVELOPE_RUNTIME.store_prefetched_decision(
				resident,
				resident_id,
				decision_id,
				decision,
				decision_wake,
				inflight_events,
				inflight_results,
			)
		)
	var action_type := String(action.get("type", ""))
	# 大会冻结期: 所有动作(含下面的即时动作分支)统一先过阶段白名单。
	# 此前做活动/用道具/追踪/查案等即时分支不经过 prepare 入口检查——
	# 连续性兜底在冻结期给居民塞生活动作(实锤: 汇报期"我先取餐"开工),
	# 警察也能在审讯期装追踪器, 全部绕过了"汇报期只能向警察汇报"等约束。
	var assembly_rejection: String = host.WEREWOLF_RUNTIME.assembly_action_allowed(
		host,
		resident_id,
		action_type,
	)
	if not assembly_rejection.is_empty():
		return host._complete_agent_submission(
			ACTION_RESULT_RUNTIME.reject_invalid(
				host,
				resident_id,
				resident,
				action,
				assembly_rejection,
			)
		)
	var conflict_intent := (
		decision.get("conflict_intent", {}) as Dictionary
		if decision.get("conflict_intent") is Dictionary
		else {}
	)
	var busy_activity_reconsideration := bool(resident.get("busyActivityReconsideration", false))
	var reply_error := AGENT_DECISION_ACCEPTANCE_POLICY.waiting_conversation_reply_error(
		active_conversation,
		resident_id,
		action_type,
		is_initial_invitation,
	)
	if not reply_error.is_empty():
		return host._complete_agent_submission(
			ACTION_RESULT_RUNTIME.reject_invalid(host, resident_id, resident, action, reply_error)
		)
	if busy_activity_reconsideration:
		resident["busyActivityReconsideration"] = false
	host.ANNOUNCEMENT_RESIDENT_RUNTIME.emit_reactions(host,
		resident_id,
		decision_id,
		decision.get("reaction", {}) as Dictionary,
		(
			decision.get("announcement_reactions", []) as Array
			if decision.get("announcement_reactions", []) is Array
			else []
		),
		inflight_events,
		inflight_results,
	)
	if not conflict_intent.is_empty():
		return AGENT_DECISION_ACTION_RUNTIME.submit_conflict_intent(
			host, resident, action, conflict_intent, context
		)
	if action_type == "投票放逐":
		# 方案A: 投票放逐作为即时动作直接提交(不写 currentAction、不进推进循环)。
		# 目标按ID校验(候选名单=ID),失败反馈模型重试;附件 exile_vote 通道仍保留。
		# 双通道幂等: 附件 exile_vote 已提交成功时, 动作通道重复提交视为成功。
		var attachment_submitted := context.get("attachmentSubmitted", {}) as Dictionary
		if bool(attachment_submitted.get("exile_vote", false)):
			return host._complete_agent_submission({
				"ok": true,
				"consumed": true,
				"stale": false,
			})
		var vote_error: String = host.WEREWOLF_RUNTIME.submit_vote(host, resident_id, {
			"target_resident_id": String(action.get("target_resident_id", "")),
			"line": String(action.get("line", "")),
		})
		if not vote_error.is_empty():
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(
					host, resident_id, resident, action, vote_error
				)
			)
		return host._complete_agent_submission({
			"ok": true,
			"consumed": true,
			"stale": false,
		})
	if action_type == "使用技能":
		# 夜间技能作为即时动作直接提交(不写 currentAction、不进推进循环)。
		# 目标按ID校验(候选名单=ID),失败反馈模型重试;附件 night_skill 通道仍保留。
		# 双通道幂等: 附件 night_skill 已提交成功时, 动作通道重复提交视为成功。
		var attachment_submitted := context.get("attachmentSubmitted", {}) as Dictionary
		if bool(attachment_submitted.get("night_skill", false)):
			return host._complete_agent_submission({
				"ok": true,
				"consumed": true,
				"stale": false,
			})
		var skill_error: String = host.ROLE_SKILL_RUNTIME.submit_night_skill(host, resident_id, {
			"skill_id": String(action.get("skill_id", "")),
			"target_resident_id": String(action.get("target_resident_id", "")),
			"line": String(action.get("line", "")),
		})
		if not skill_error.is_empty():
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(
					host, resident_id, resident, action, skill_error
				)
			)
		return host._complete_agent_submission({
			"ok": true,
			"consumed": true,
			"stale": false,
		})
	if action_type == "向警察汇报":
		# 审讯会汇报期: 居民向警察秘密汇报(目击/听到/怀疑/不汇报), 即时提交。
		# 内容保密不广播, 只进警察侧汇总; 失败反馈模型重试。
		# 双通道幂等: 附件 report 已提交成功时, 动作通道重复提交视为成功。
		var attachment_submitted := context.get("attachmentSubmitted", {}) as Dictionary
		if bool(attachment_submitted.get("report", false)):
			return host._complete_agent_submission({
				"ok": true,
				"consumed": true,
				"stale": false,
			})
		var report_error: String = host.WEREWOLF_RUNTIME.submit_report(host, resident_id, {
			"kind": String(action.get("kind", "")),
			"line": String(action.get("line", "")),
		})
		if not report_error.is_empty():
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(
					host, resident_id, resident, action, report_error
				)
			)
		return host._complete_agent_submission({
			"ok": true,
			"consumed": true,
			"stale": false,
		})
	if action_type == "结束审讯":
		# 审讯会审讯期: 警察主动结束审讯(逐字稿随投票 wake 注入全员), 即时提交。
		var end_error: String = host.WEREWOLF_RUNTIME.end_interrogation(
			host, resident_id,
		)
		if not end_error.is_empty():
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(
					host, resident_id, resident, action, end_error
				)
			)
		return host._complete_agent_submission({
			"ok": true,
			"consumed": true,
			"stale": false,
		})
	if action_type == "追踪":
		# 警察侦查装备即时动作: 靠近目标装追踪装置(原窃听+定位合并),
		# 之后 1 天实时上报目标的对话/行踪/重大行动。失败反馈模型重试。
		var intel_result: Dictionary = host._activate_police_tracker_action(
			resident_id, resident, action,
		)
		if not bool(intel_result.get("ok", false)):
			var intel_errors := intel_result.get("errors", []) as Array
			var intel_error: String = (
				"侦查失败"
				if intel_errors.is_empty()
				else String(intel_errors[0])
			)
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(
					host, resident_id, resident, action, intel_error
				)
			)
		return host._complete_agent_submission({
			"ok": true,
			"consumed": true,
			"stale": false,
		})
	if action_type == "查案":
		# 警察镇公所查案即时动作: 在镇公所查阅档案, 获取死亡案件与夜间
		# 行踪疑点线索(每天限 2 次)。失败反馈模型重试。
		var investigate_result: Dictionary = host._activate_police_investigate_action(
			resident_id, resident, action,
		)
		if not bool(investigate_result.get("ok", false)):
			var investigate_errors := investigate_result.get("errors", []) as Array
			var investigate_error: String = (
				"查案失败"
				if investigate_errors.is_empty()
				else String(investigate_errors[0])
			)
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(
					host, resident_id, resident, action, investigate_error
				)
			)
		return host._complete_agent_submission({
			"ok": true,
			"consumed": true,
			"stale": false,
		})
	if action_type in ["暗杀", "制服", "发布公告"]:
		# 狼人杀即时动作:提交即校验(prepare),通过后立即结算(activate),
		# 不写 currentAction、不进推进循环。
		var prepared_action: Dictionary
		match action_type:
			"暗杀":
				prepared_action = host._prepare_assassination_action(
					resident_id, resident, action,
				)
			"制服":
				prepared_action = host._prepare_subdue_action(
					resident_id, resident, action,
				)
			_:
				prepared_action = host._prepare_announcement_action(
					resident_id, resident, action,
				)
		if prepared_action.get("ok") != true:
			return host._complete_agent_submission(
				ACTION_RESULT_RUNTIME.reject_invalid(
					host,
					resident_id,
					resident,
					action,
					String(
						(prepared_action.get("errors", ["动作被拒绝"]) as Array)[0]
					),
				)
			)
		var validated_action := prepared_action.get("action", {}) as Dictionary
		var conversation_end_reason := AGENT_DECISION_ACCEPTANCE_POLICY.conversation_end_reason(
			active_conversation,
			action_type,
			is_initial_invitation,
		)
		match action_type:
			"暗杀":
				host._activate_assassination_action(
					resident_id, resident, validated_action, decision_wake,
					conversation_end_reason, active_conversation,
				)
			"制服":
				host._activate_subdue_action(
					resident_id, resident, validated_action, decision_wake,
					conversation_end_reason, active_conversation,
				)
			_:
				host._activate_announcement_action(
					resident_id, resident, validated_action, decision_wake,
					conversation_end_reason, active_conversation,
				)
		return host._complete_agent_submission({
			"ok": true,
			"consumed": true,
			"stale": false,
		})
	var conversation_end_reason := AGENT_DECISION_ACCEPTANCE_POLICY.conversation_end_reason(
		active_conversation,
		action_type,
		is_initial_invitation,
	)
	if action_type == "用道具":
		return host._complete_agent_submission(
			LEGACY_PROP_ACTIVITY_RUNTIME.submit(
				host,
				resident_id,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				bool(context.get("mayInterruptCurrent", false)),
			)
		)
	if action_type == "做活动":
		return host._complete_agent_submission(
			AGENT_ACTIVITY_SUBMISSION_RUNTIME.submit(
				host,
				resident_id,
				resident,
				decision_id,
				action,
				conversation_end_reason,
				bool(context.get("mayInterruptCurrent", false)),
			)
		)
	context["actionType"] = action_type
	context["busyActivityReconsideration"] = busy_activity_reconsideration
	context["conversationEndReason"] = conversation_end_reason
	return AGENT_DECISION_ACTION_RUNTIME.submit_prepared_action(
		host, resident, decision, action, context
	)


## 附件通道(汇报/投票/夜间技能)是否至少有一类已提交成功。
static func _attachment_submitted_any(attachment_submitted: Dictionary) -> bool:
	for submitted_value: Variant in attachment_submitted.values():
		if bool(submitted_value):
			return true
	return false
