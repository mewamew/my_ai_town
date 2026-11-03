//! set_goal：目标的登记、更新与完成证据。完成证据的规则只在这里一份，恢复校验也用它。
use super::limits::*;
use crate::{
    event, resident,
    session::{Goal, GoalCondition, GoalStatus, Session},
};
use kernel::World;
use protocol::{ActionStatus, InteractionStatus};
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct GoalUpdate {
    id: String,
    title: String,
    /// 新目标必填；更新时省略即沿用原条件。
    #[serde(default)]
    condition: Option<GoalCondition>,
    status: GoalStatus,
    #[serde(default)]
    next_steps: Option<Vec<String>>,
    #[serde(default)]
    commitment: Option<String>,
    #[serde(default)]
    reason: String,
    /// 省略沿用原时刻，空串清除。
    #[serde(default)]
    due_clock: Option<String>,
}

impl GoalUpdate {
    fn within_limits(&self) -> bool {
        let chars = |s: &str| s.chars().count();
        !self.id.is_empty()
            && self.id.len() <= GOAL_ID_BYTES
            && !self.title.is_empty()
            && chars(&self.title) <= GOAL_TITLE_CHARS
            && self
                .commitment
                .as_deref()
                .is_none_or(|s| chars(s) <= GOAL_TEXT_CHARS)
            && chars(&self.reason) <= GOAL_TEXT_CHARS
            && self.next_steps.as_ref().is_none_or(|steps| {
                steps.len() <= GOAL_STEPS_MAX && steps.iter().all(|s| chars(s) <= GOAL_STEP_CHARS)
            })
    }
}

/// 校验约定时刻 `D日数 HH:MM`，返回规范写法；空串表示清除。
fn due_clock(text: &str) -> Result<Option<String>, String> {
    if text.is_empty() {
        return Ok(None);
    }
    let parsed = text.strip_prefix('D').and_then(|s| {
        let (day, time) = s.split_once(' ')?;
        let (hour, minute) = time.split_once(':')?;
        Some((
            day.parse::<u32>().ok()?,
            hour.parse::<u32>().ok()?,
            minute.parse::<u32>().ok()?,
        ))
    });
    match parsed {
        Some((d, h, m)) if d > 0 && h < 24 && m < 60 => Ok(Some(format!("D{d} {h:02}:{m:02}"))),
        _ => Err("due_clock 须写成 D日数 HH:MM，例如 D2 14:00；空串清除".into()),
    }
}

/// 目标建立后完成条件的世界证据：事件编号。不满足时说明原因。
pub(crate) fn completion_evidence(
    world: &World,
    actor_id: &str,
    condition: &GoalCondition,
    created_at: f64,
) -> Result<Vec<u64>, String> {
    let actor = resident(world, actor_id).map_err(|e| e.to_string())?;
    match condition {
        GoalCondition::Interaction { interaction_id } => {
            let item = world
                .interactions()
                .of(actor_id, interaction_id)
                .ok_or("互动不存在")?;
            if item.status != InteractionStatus::Succeeded {
                return Err("双方互动尚未完成，不能记为成功".into());
            }
            Ok(item.event_ids.get(actor_id).cloned().unwrap_or_default())
        }
        GoalCondition::Action { verb, locale } => {
            let evidence: Vec<u64> = actor
                .actions
                .groups
                .values()
                .flat_map(|g| &g.results)
                .filter(|r| {
                    r.verb == *verb
                        && r.status == ActionStatus::Succeeded
                        && r.ended_at >= created_at
                })
                .flat_map(|r| r.event_ids.iter().copied())
                .filter(|id| event(actor, *id).is_some_and(|e| e.objects.contains(locale)))
                .collect();
            if evidence.is_empty() {
                return Err("没有目标建立后完成指定动作的世界证据".into());
            }
            Ok(evidence)
        }
    }
}

fn resolve_condition(
    world: &World,
    session: &Session,
    given: Option<GoalCondition>,
    previous: Option<&Goal>,
) -> Result<GoalCondition, String> {
    let condition = match (given, previous) {
        (Some(condition), Some(old)) if condition != old.condition => {
            return Err("同一目标的完成条件不能替换；请先结束原目标，再建立新目标".into())
        }
        (Some(condition), _) => condition,
        (None, Some(old)) => old.condition.clone(),
        (None, None) => return Err("新目标必须给出完成条件 condition".into()),
    };
    match &condition {
        GoalCondition::Interaction { interaction_id }
            if world
                .interactions()
                .of(&session.actor_id, interaction_id)
                .is_none() =>
        {
            Err("互动目标必须引用自己发起或收到的真实邀请".into())
        }
        GoalCondition::Action { verb, locale }
            if !world.topo.is_dwell(locale)
                || !(world.affordances.is_verb(verb)
                    || kernel::intent::BuiltinVerb::parse(verb).is_some()) =>
        {
            Err("目标动作或地点不存在".into())
        }
        _ => Ok(condition),
    }
}

fn check_transition(
    session: &Session,
    args: &GoalUpdate,
    previous: Option<&Goal>,
) -> Result<(), String> {
    let open = session
        .goals
        .values()
        .filter(|g| g.status.is_open())
        .count();
    if previous.is_none() && args.status.is_open() && open >= OPEN_GOALS_MAX {
        return Err(format!(
            "同时进行或暂停的目标已达 {OPEN_GOALS_MAX} 个，请先处理已有目标；历史目标仍保留"
        ));
    }
    if previous.is_some_and(|g| !g.status.is_open()) {
        return Err("已结束的目标不能改写，请使用新的目标编号".into());
    }
    if matches!(
        args.status,
        GoalStatus::Abandoned | GoalStatus::Failed | GoalStatus::Paused
    ) && args.reason.trim().is_empty()
    {
        return Err("暂停、放弃或失败需要记录原因".into());
    }
    Ok(())
}

pub(super) fn set_goal(
    world: &World,
    session: &mut Session,
    args: GoalUpdate,
) -> Result<Value, String> {
    if !args.within_limits() {
        return Err("目标记录为空或超过长度上限".into());
    }
    let previous = session.goals.get(&args.id);
    let condition = resolve_condition(world, session, args.condition.clone(), previous)?;
    check_transition(session, &args, previous)?;
    let created_at = previous.map_or(world.minutes(), |g| g.created_at);
    let evidence = if args.status == GoalStatus::Completed {
        completion_evidence(world, &session.actor_id, &condition, created_at)?
    } else {
        vec![]
    };
    let due_clock = match args.due_clock.as_deref() {
        Some(text) => due_clock(text)?,
        None => previous.and_then(|g| g.due_clock.clone()),
    };
    let goal = Goal {
        id: args.id.clone(),
        title: args.title,
        condition,
        status: args.status,
        next_steps: args
            .next_steps
            .unwrap_or_else(|| previous.map(|g| g.next_steps.clone()).unwrap_or_default()),
        commitment: args
            .commitment
            .unwrap_or_else(|| previous.map(|g| g.commitment.clone()).unwrap_or_default()),
        reason: args.reason,
        created_at,
        updated_at: world.minutes(),
        due_clock,
        evidence,
    };
    let value = json!(goal);
    let closed = !goal.status.is_open() || goal.status == GoalStatus::Paused;
    session.goals.insert(args.id, goal);
    if closed {
        session.memory.consolidate(world, &session.actor_id);
    }
    Ok(value)
}
