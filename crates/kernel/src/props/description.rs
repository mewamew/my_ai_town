//! 道具动作给 Agent 和观察仪看的说明；文案在这里，规则在各校验处。
use super::*;
use crate::physiology::enabled;
use protocol::{
    Choice, DurationRange, PhysiologySwitches, PropActionView, PropCapabilities, RateRange,
    SupplyView,
};

/// 效果说明只列开启的生理项；关掉的项对村民不存在。
fn effect_texts(a: &Action, s: PhysiologySwitches) -> Vec<String> {
    let on = |need| enabled(s, need);
    let mut effects: Vec<String> = a
        .during
        .iter()
        .filter_map(|e| match e {
            Effect::RestoreNeed { need, .. } if !on(*need) => None,
            Effect::RestoreNeed {
                need,
                per_minute,
                pause_decay,
            } => Some(format!(
                "{}每分钟恢复 {} 点{}",
                need.label(),
                per_minute,
                if *pause_decay {
                    "，暂停该项自然消耗"
                } else {
                    "，仍有自然消耗"
                }
            )),
            Effect::Labor => match (on(Need::Energy), on(Need::Water)) {
                (true, true) => Some("按居民的劳作参数额外消耗精力，并消耗水分".into()),
                (true, false) => Some("按居民的劳作参数额外消耗精力".into()),
                (false, true) => Some("劳作时额外消耗水分".into()),
                (false, false) => None,
            },
        })
        .collect();
    effects.extend(a.on_complete.iter().filter_map(|e| instant_text(e, s)));
    if a.rest && on(Need::Health) {
        effects.push("有效休息：满足饮食与无损害条件时休养恢复健康".into());
    }
    effects
}

/// 一项完成效果的说明；关掉的生理项不说。
fn instant_text(e: &InstantEffect, s: PhysiologySwitches) -> Option<String> {
    let on = |need| enabled(s, need);
    Some(match e {
        InstantEffect::Restore { need, .. } if !on(*need) => return None,
        InstantEffect::ApplyCondition { .. }
        | InstantEffect::CureCondition { .. }
        | InstantEffect::Harm { .. }
            if !on(Need::Health) =>
        {
            return None
        }
        InstantEffect::Harm { amount, wound } if *amount >= 100.0 => {
            format!("完成时杀死对方，身上留下{wound}")
        }
        InstantEffect::Harm { amount, wound } => {
            format!("完成时对方健康减少 {amount} 点，身上留下{wound}；健康扣到 0 就会死")
        }
        InstantEffect::Restore { need, amount } => {
            format!("完成时{}恢复 {amount} 点", need.label())
        }
        InstantEffect::ApplyCondition {
            condition,
            severity,
        } => format!("完成时施加{}（程度 {severity}）", condition.label()),
        InstantEffect::CureCondition { condition } => {
            format!("完成时解除{}，不补回健康", condition.label())
        }
        InstantEffect::Revive {
            values,
            clear_conditions,
        } => {
            let restored: Vec<_> = Need::ALL
                .into_iter()
                .zip(values)
                .filter(|(need, _)| on(*need))
                .map(|(need, v)| format!("{} {v}", need.label()))
                .collect();
            let mut text = format!("完成时复活：{}", restored.join("、"));
            if on(Need::Health) {
                text += if *clear_conditions {
                    "；清除受伤、疾病和中毒"
                } else {
                    "；保留受伤、疾病和中毒"
                };
            }
            text
        }
        InstantEffect::GiveItem { item, count } => {
            format!("完成时得到{}×{count}，放进背包", item.name)
        }
        InstantEffect::PlaceProp { prop } => format!("完成时在这里建成「{}」", prop.name),
        InstantEffect::Chance {
            percent, effects, ..
        } => {
            let inner: Vec<_> = effects
                .iter()
                .filter_map(|e| instant_text(e, s))
                .map(|t| t.trim_start_matches("完成时").to_string())
                .collect();
            if inner.is_empty() {
                return None;
            }
            format!("完成时有 {percent}% 可能：{}", inner.join("，"))
        }
        // 后续会发生什么由世界决定；只说会有后续，不提前剧透。
        InstantEffect::Schedule { .. } => "完成后过一段时间可能会有动静".into(),
        InstantEffect::Depart { text } => format!("完成时离开这里：{text}"),
    })
}

fn condition_texts(a: &Action) -> Vec<String> {
    let mut conditions: Vec<String> = [
        "道具在当前地点或本人背包中",
        "道具未被其他居民占用",
        "完成规定时长",
    ]
    .map(String::from)
    .to_vec();
    if a.on_complete
        .iter()
        .any(|e| matches!(e, InstantEffect::Revive { .. }))
    {
        conditions.push("由存活者对同一地点的死者施用".into());
    } else if a.harms() {
        conditions.push("只能对同一地点活着的别人施用".into());
    } else if a.recipient {
        conditions.push("可对自己或同一地点的存活者施用".into());
    }
    for c in &a.conditions {
        conditions.push(
            match c {
                Condition::MealWindow => "在供餐时段开始",
                Condition::OwnHome => "位于使用者自己的住宅",
            }
            .into(),
        );
    }
    conditions.extend(a.requires.iter().map(super::making::requirement_text));
    conditions
}

fn result_text(a: &Action) -> &'static str {
    let makes = a.on_complete.iter().any(|e| {
        matches!(e, InstantEffect::GiveItem { .. } | InstantEffect::PlaceProp { .. })
            || matches!(e, InstantEffect::Chance { effects, .. } if effects.iter().any(|x| matches!(x, InstantEffect::GiveItem { .. } | InstantEffect::PlaceProp { .. })))
    });
    match a.completion {
        Completion::Activity | Completion::Sleep if makes => {
            "记录实际进行的活动；按完成效果产出物品或道具"
        }
        Completion::Activity | Completion::Sleep => "记录实际进行的活动；没有额外物品产出",
        Completion::Meal => "记录餐次与菜单",
        Completion::ReadBook => "完成后可访问这本书的正文；记忆由本人决定",
        Completion::ReadBulletin => "完成后可访问这条公告的正文",
        Completion::WriteBook => "提交书名、正文，完成后在此处生成书籍",
        Completion::Research => "只记录查询活动，目前没有具体查询资料",
    }
}

/// 完整说明（道具编辑与目录用）。
pub fn action_description(a: &Action) -> PropActionView {
    action_description_for(a, PhysiologySwitches::default())
}

/// 按世界生理开关过滤效果的说明（村民观察与游戏界面用）。
pub fn action_description_for(a: &Action, s: PhysiologySwitches) -> PropActionView {
    PropActionView {
        conditions: condition_texts(a),
        consumes_item: a.consumes_item,
        effects: effect_texts(a, s),
        id: a.id.clone(),
        label: a.label.clone(),
        minutes: a.duration_minutes,
        portion_name: a.portion_name.clone(),
        recipient: a.recipient,
        remaining: None,
        result: result_text(a).into(),
        supply: a.supply.as_ref().map(|s| SupplyView {
            cost: s.cost,
            initial: s.initial,
        }),
    }
}

fn choices(items: &[(&str, &str)]) -> Vec<Choice> {
    items
        .iter()
        .map(|(id, label)| Choice {
            id: (*id).into(),
            label: (*label).into(),
        })
        .collect()
}

/// 道具编辑器能选的效果、条件与完成方式。
pub fn capabilities() -> PropCapabilities {
    PropCapabilities {
        completion_effects: choices(&[
            ("restore", "完成时恢复数值"),
            ("apply_condition", "施加身体状况"),
            ("cure_condition", "解除身体状况"),
            ("revive", "明确复活"),
        ]),
        completions: choices(&[
            ("activity", "记录活动"),
            ("sleep", "睡眠记录"),
            ("meal", "餐次与菜单"),
            ("read_book", "阅读书籍"),
            ("read_bulletin", "阅读公告"),
            ("write_book", "创作书籍"),
            ("research", "查询活动（暂无内容）"),
        ]),
        conditions: choices(&[("meal_window", "供餐时段"), ("own_home", "自己的住宅")]),
        duration: DurationRange { max: 1440, min: 1 },
        effects: choices(&[("restore_need", "恢复身体状态"), ("labor", "劳作消耗")]),
        max_actions: MAX_ACTIONS,
        needs: choices(&[
            ("energy", "精力"),
            ("fullness", "饱腹"),
            ("water", "水分"),
            ("health", "健康"),
        ]),
        rate: RateRange {
            max: 100,
            min: 0.001,
        },
        schema_version: 2,
        supports_recipients: true,
        supports_supply: true,
    }
}
