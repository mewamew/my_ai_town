class_name TownAgentDecisionAcceptancePolicy
extends RefCounted


const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)


static func invitation_reply_error(decision: Dictionary) -> Dictionary:
	var submitted_action: Variant = decision.get("action")
	if (
		String(decision.get("handling", "")) != "replace_current"
		or submitted_action is not Dictionary
		or String((submitted_action as Dictionary).get("type", "")) != "答话"
	):
		return {
			"ok": false,
			"stale": false,
			"consumed": false,
			"errorCode": "CONVERSATION_REPLY_REQUIRED",
			"retryable": true,
			"errors": ["搭话必须提交答话；拒绝也要明确说明理由并结束对话"],
		}
	var reply := submitted_action as Dictionary
	if (
		bool(reply.get("end", false))
		and String(reply.get("say", "")).strip_edges().is_empty()
	):
		return {
			"ok": false,
			"stale": false,
			"consumed": false,
			"errorCode": "CONVERSATION_REFUSAL_REASON_REQUIRED",
			"retryable": true,
			"errors": ["拒绝搭话时答话必须说出明确理由"],
		}
	return {}


static func post_injury_action_error(
	resident: Dictionary,
	decision: Dictionary,
	reaction: Dictionary,
	clinic_place_id: String = "诊所",
) -> String:
	if reaction.is_empty():
		return ""
	if String(decision.get("handling", "")) != "replace_current":
		return "刚刚受伤，必须先当面质问攻击者，或直接去诊所"
	var action := (
		decision.get("action", {}) as Dictionary
		if decision.get("action") is Dictionary
		else {}
	)
	var action_type := String(action.get("type", ""))
	var attacker_id := String(reaction.get("attacker_resident_id", ""))
	if action_type == "搭话":
		if (
			not attacker_id.is_empty()
			and String(action.get("target_resident_id", "")) == attacker_id
		):
			return ""
		return "刚刚受伤时只能先当面质问攻击者，不能先和其他人搭话"
	if action_type == "去":
		if String(action.get("place", "")) == clinic_place_id:
			return ""
		return "刚刚受伤时只能直接去诊所；去诊所本身就是离开冲突现场"
	if (
		action_type == "待着"
		and String(resident.get("currentPlace", "")) == clinic_place_id
	):
		return ""
	return "刚刚受伤时只能先当面质问攻击者，或直接去诊所"


static func waiting_conversation_reply_error(
	conversation: Dictionary,
	resident_id: String,
	action_type: String,
	is_initial_invitation: bool,
) -> String:
	if (
		conversation.is_empty()
		or String(conversation.get("waitingFor", "")) != resident_id
		or action_type == "答话"
	):
		return ""
	return (
		"搭话必须提交答话；拒绝也要说明理由并结束对话"
		if is_initial_invitation
		else "当前对话正在等待本居民提交答话动作"
	)


static func conversation_end_reason(
	conversation: Dictionary,
	action_type: String,
	is_initial_invitation: bool,
) -> String:
	if conversation.is_empty() or action_type == "答话":
		return ""
	return "拒绝接话" if is_initial_invitation else "无法继续"


static func accepted_conversation_follow_up(
	decision: Dictionary,
	wake_packet: Dictionary,
	action_options: TownActionOptionDirectory,
) -> Dictionary:
	if (
		ACTION_VALIDATION.validate_conversation_follow_up_shape(
			decision.get("conversation_follow_up"),
		) != ""
		or decision.get("action") is not Dictionary
		or String((decision.get("action") as Dictionary).get("type", "")) != "答话"
	):
		return {}
	var option_id := String(
		(decision.get("conversation_follow_up") as Dictionary).get("option_id", ""),
	).strip_edges()
	for value: Variant in (
		(wake_packet.get("snapshot", {}) as Dictionary).get(
			"conversation_follow_up_options",
			[],
		) as Array
	):
		if value is not Dictionary:
			continue
		var option := value as Dictionary
		if String(option.get("option_id", "")) != option_id:
			continue
		if option.has("integrity_key"):
			var goal_result := action_options.action_goal_from_option(option) as Dictionary
			if goal_result.get("ok") != true:
				continue
		return option.duplicate(true)
	return {}


static func apply_wait_reconsideration(
	prepared_action: Dictionary,
	current_action: Dictionary,
	busy_activity_reconsideration: bool,
	absolute_minute: int,
	continuity_wait_max_minutes: int,
) -> Dictionary:
	var result := prepared_action.duplicate(true)
	if (
		bool(current_action.get("followUpPausedForReconsideration", false))
		and String(result.get("type", "")) == "待着"
	):
		var resume_action := current_action.duplicate(true)
		resume_action.erase("followUpPausedForReconsideration")
		resume_action.erase("followUpReconsiderationReason")
		resume_action.erase("followUpReconsiderationSinceMinute")
		result["conversationFollowUpMode"] = "reconsideration_wait"
		result["followUpPhase"] = "waiting_to_retry"
		result["followUpResumeAction"] = resume_action
	if busy_activity_reconsideration and String(result.get("type", "")) == "待着":
		result["completeAbsoluteMinute"] = mini(
			int(result.get(
				"completeAbsoluteMinute",
				absolute_minute + continuity_wait_max_minutes,
			)),
			absolute_minute + continuity_wait_max_minutes,
		)
	return result
