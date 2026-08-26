extends RefCounted


# O 域迁移第五件:动作对外投影与随身数据工具(含七表 T7 文案表)。

const VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)

const ACTIVITY_SOURCE_AGENT_ACTIVITY := "agent.activity"
const ACTIVITY_SOURCE_LEGACY_PROP := "legacy.agent.use_prop"
const ACTIVITY_SOURCE_DIRECT := "activity.perform"
const CONVERSATION_FOLLOW_UP_INTERNAL_FIELDS := [
	"conversationFollowUpMode",
	"followUpPhase",
	"followUpPersonId",
	"followUpDestinationPlace",
	"followUpServicePlace",
	"followUpServiceActivityId",
	"followUpServiceLabel",
	"followUpDeadlineMinute",
	"followUpLastAdvanceMinute",
	"followUpLagStartedMinute",
	"followUpServiceCollected",
	"followUpCollectUntilMinute",
	"followUpPausedForReconsideration",
	"followUpReconsiderationReason",
	"followUpReconsiderationSinceMinute",
	"followUpResumeAction",
]


static func activity_routine_completion_text(group: String) -> String:
	return (
		"吃完并把餐具收拾好了"
		if group == "meal"
		else "忙完了这一阵的活，该换口气看看别的事了"
	)

static func activity_source_action_id(
	action: Dictionary,
	execution: Dictionary,
) -> String:
	var action_source_contract := String(
		action.get("sourceContract", "")
	)
	var execution_source_contract := String(
		execution.get("sourceContract", "")
	)
	var action_source_id := String(
		action.get("sourceActionId", "")
	).strip_edges()
	var execution_source_id := String(
		execution.get("sourceActionId", "")
	).strip_edges()
	if (
		action_source_contract in [
			ACTIVITY_SOURCE_LEGACY_PROP,
			ACTIVITY_SOURCE_AGENT_ACTIVITY,
		]
		and execution_source_contract == action_source_contract
		and not action_source_id.is_empty()
		and action_source_id == execution_source_id
	):
		return action_source_id
	return ""

static func copy_conversation_follow_up_state(
	from_action: Dictionary,
	to_action: Dictionary,
) -> void:
	for field_value: Variant in CONVERSATION_FOLLOW_UP_INTERNAL_FIELDS:
		var field := String(field_value)
		if not from_action.has(field):
			continue
		var value: Variant = from_action.get(field)
		to_action[field] = (
			value.duplicate(true)
			if value is Array or value is Dictionary
			else value
		)

static func submitted_action_for_preview(action: Dictionary) -> Dictionary:
	var action_type := String(action.get("type", ""))
	var submitted := {}
	for field_value: Variant in VALIDATION.ACTION_FIELDS.get(action_type, []) as Array:
		var field := String(field_value)
		if not action.has(field):
			continue
		var value: Variant = action[field]
		submitted[field] = (
			value.duplicate(true)
			if value is Array or value is Dictionary
			else value
		)
	for field_value: Variant in VALIDATION.OPTIONAL_ACTION_FIELDS.get(action_type, []) as Array:
		var field := String(field_value)
		if not action.has(field):
			continue
		submitted[field] = action[field]
	return submitted

static func public_current_action(action: Dictionary) -> Variant:
	if action.is_empty():
		return null
	var action_id := String(action.get("action_id", ""))
	if (
		String(action.get("sourceContract", ""))
		== ACTIVITY_SOURCE_LEGACY_PROP
	):
		return {
			"action_id": String(action.get("sourceActionId", "")),
			"type": "用道具",
		}
	if (
		String(action.get("sourceContract", ""))
		== ACTIVITY_SOURCE_AGENT_ACTIVITY
	):
		return {
			"action_id": String(action.get("sourceActionId", "")),
			"type": "做活动",
		}
	return {
		"action_id": action_id,
		"type": (
			"activity.perform"
			if action_id.begins_with("activity-")
			else String(action.get("type", ""))
		),
	}


static func default_doing(world, action: Dictionary) -> String:
	match String(action.get("type", "")):
		"去": return "正前往%s" % String(action.get("place", ""))
		"用道具":
			var prop_name := String(action.get("prop", "")).strip_edges()
			var verb := String(action.get("verb", "")).strip_edges()
			return (
				"正在%s%s" % [verb, prop_name]
				if not prop_name.is_empty()
				else "正在%s" % verb
			)
		"做活动":
			return "正在进行当前活动"
		"调整营业":
			return (
				"正在宣布%s恢复营业"
				% String(action.get("place_id", ""))
				if bool(action.get("open", false))
				else "正在宣布%s暂停营业"
				% String(action.get("place_id", ""))
			)
		"托人传话":
			var recipient_name: String = world.person_name_for_id(
				String(action.get("recipient_resident_id", "")),
			)
			return (
				"正在托人给%s带口信" % recipient_name
				if not recipient_name.is_empty()
				else "正在托人带口信"
			)
		"发布公告":
			return "正在中心广场张贴公告"
		"待着":
			return (
				"正在找个不挡路的地方休息"
				if action.has("idlePathPoints")
				else "正在休息等待"
			)
		"搭话":
			var target_id := String(
				action.get("target_resident_id", "")
			).strip_edges()
			var target_name: String = world.person_name_for_id(target_id)
			return (
				"正在与%s交谈" % target_name
				if not target_name.is_empty()
				else "正在交谈"
			)
		"答话": return "正在交谈"
	return "正在行动"
