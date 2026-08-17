class_name TownActionPreparationPolicy
extends RefCounted


const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const CONFLICT_AGENT_WORLD_BRIDGE := preload(
	"res://world/runtime/conflict/TownConflictAgentWorldBridge.gd"
)
const LINE_REQUIRED_ACTION_TYPES := [
	"去",
	"用道具",
	"做活动",
	"调整营业",
	"托人传话",
	"待着",
]


static func entry_failure(
	action: Dictionary,
	used_action_ids: Dictionary,
	allow_used_action_id: bool,
) -> Dictionary:
	var shape_error := ACTION_VALIDATION.validate_action_shape(action)
	if not shape_error.is_empty():
		return _failure(shape_error)
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return _failure("动作 action_id 不能为空")
	if not allow_used_action_id and used_action_ids.has(action_id):
		return _failure("动作 action_id 已被该居民使用：%s" % action_id)
	var action_type := String(action.get("type", "")).strip_edges()
	if (
		action_type in LINE_REQUIRED_ACTION_TYPES
		and String(action.get("line", "")).strip_edges().is_empty()
	):
		return _failure("%s 动作必须包含非空 line" % action_type)
	return {}


static func delegated_action_failure(action_type: String) -> Dictionary:
	match action_type:
		"用道具":
			return _failure(
				"旧用道具动作必须经唯一 activity.perform 映射，不能直达 prop 路径",
			)
		"做活动":
			return _failure("做活动必须经 activity.perform 入口执行")
		_:
			return {}


static func service_adjustment(
	action: Dictionary,
	control: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var place_id := String(action.get("place_id", "")).strip_edges()
	if (
		not action.get("open") is bool
		or place_id.is_empty()
		or control.is_empty()
		or String(control.get("place_id", "")) != place_id
		or bool(control.get("open", false)) == bool(action.get("open", false))
	):
		return _failure("本人当前不能这样改变营业状态")
	return _timed_action(action, absolute_minute, absolute_minute + 1)


static func private_message(
	action: Dictionary,
	sender_id: String,
	recipient_exists: bool,
	pending_count: int,
	absolute_minute: int,
) -> Dictionary:
	var recipient_id := String(
		action.get("recipient_resident_id", ""),
	).strip_edges()
	var content := String(action.get("content", "")).strip_edges()
	if (
		recipient_id.is_empty()
		or recipient_id == sender_id
		or not recipient_exists
		or content.is_empty()
		or content.length() > 240
	):
		return _failure("传话必须指定另一位真实居民和有效口信")
	if pending_count >= 2:
		return _failure("已有口信在等待投递，先不要重复托付")
	return _timed_action(action, absolute_minute, absolute_minute + 1)


static func wait_action(
	action: Dictionary,
	absolute_minute: int,
	minutes_until_next_period: int,
	continuity_wait_max_minutes: int,
	wait_max_minutes: int,
) -> Dictionary:
	var wait_cap_minutes := (
		continuity_wait_max_minutes
		if ACTION_VALIDATION.is_continuity_wait_action(action)
		else wait_max_minutes
	)
	return _timed_action(
		action,
		absolute_minute,
		absolute_minute + mini(minutes_until_next_period, wait_cap_minutes),
	)


static func conflict_failure(error_code: String) -> Dictionary:
	return _failure(CONFLICT_AGENT_WORLD_BRIDGE.action_error_text(error_code))


static func unknown_action_failure(action_type: String) -> Dictionary:
	return _failure("当前运行层尚未接入动作类型：%s" % action_type)


static func _timed_action(
	action: Dictionary,
	started_absolute_minute: int,
	complete_absolute_minute: int,
) -> Dictionary:
	var prepared := action.duplicate(true)
	prepared["startedAbsoluteMinute"] = started_absolute_minute
	prepared["completeAbsoluteMinute"] = complete_absolute_minute
	return {"ok": true, "action": prepared}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "errors": [reason]}
