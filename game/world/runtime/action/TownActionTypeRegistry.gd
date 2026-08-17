extends RefCounted


# 动作类型登记表（批次 F 之 4"七表统一"）。
#
# 动作类型的处理散在七张平行分派表里，各表的类型集合并不相同。此前无人能说清
# 哪些差集是有意的、哪些是漏的——2026-08-07 两次逐条验证给出了确定答案，本表把
# 结论固化为单一事实源，并由 town_world_action_type_registry_test 逐表比对，
# 防止差集在后续改动中漂移，也防止有人把"有意的差集"误当缺口去补。
#
# 七张表（迁移后所在位置）：
#   T1 ACTION_FIELDS            TownActionValidation  字段白名单（全集权威源）
#   T2 _prepare_action          TownWorldRuntime      准备/分流
#   T3 invalid_action_fingerprint TownActionValidation 拒绝去重指纹
#   T4 validate_action_shape    TownActionValidation  形状校验
#   T5 _advance_actions         TownWorldRuntime      分钟推进
#   T6 _action_still_valid      TownActionValidityPolicy  推进期有效性
#   T7 default_doing            TownActionProjection  UI 文案

const ALL_TYPES: Array[String] = [
	"去",
	"用道具",
	"做活动",
	"调整营业",
	"托人传话",
	"待着",
	"搭话",
	"答话",
	"争执",
	"攻击",
	"回应冲突",
	"介入冲突",
	"离开冲突",
]

# 冲突五类：由冲突桥即时结算（execute_action → 直接产出动作结果），
# 全程不写 resident["currentAction"]，因此永不进入推进循环。
# 结论（2026-08-07 验证）：它们不出现在 T4/T5/T6/T7 是**有意且正确**的，
# 为其补分支只会引入不可达代码，并暗示"冲突动作可被推进"这一错误语义。
const CONFLICT_TYPES: Array[String] = [
	"争执",
	"攻击",
	"回应冲突",
	"介入冲突",
	"离开冲突",
]

# 经 _prepare_action 硬拒、必须改走 activity.perform 的类型。
# 注意"用道具"不在此列：它在更上游的 submit_agent_decision 就被分流到
# _submit_legacy_prop_activity（完整活路径），T2 的硬拒只守 _prepare_action
# 直连入口。2026-08-07 验证结论：用道具是活玩法，其实现链不得删除。
const PREPARE_REJECTED_TYPES: Array[String] = [
	"做活动",
]

# 各表应覆盖的类型集合（差集即上面两段注释所述的有意设计）。
# T4 实为两层:前置的字段白名单校验对**全部 13 类**生效(未知字段一律拒),
# 其后的逐类型必填校验只覆盖 8 类。登记表按后者记录,前者等同 T1 全集。
const TABLE_TYPES := {
	"T1_action_fields": ALL_TYPES,
	"T4_required_fields": [
		"去",
		"用道具",
		"做活动",
		"调整营业",
		"托人传话",
		"待着",
		"搭话",
		"答话",
	],
	"T7_default_doing": [
		"去",
		"用道具",
		"做活动",
		"调整营业",
		"托人传话",
		"待着",
		"搭话",
		"答话",
	],
}


static func is_conflict_type(action_type: String) -> bool:
	return action_type in CONFLICT_TYPES


static func participates_in(table_id: String, action_type: String) -> bool:
	var types: Variant = TABLE_TYPES.get(table_id, [])
	return (types as Array).has(action_type)
