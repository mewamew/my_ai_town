//! 存档恢复与世界重置。恢复前逐项校验会话与世界一致，不接受半份状态。
use super::{
    RequestKind, RequestStatus, ResidentRuntime, RuntimeState, BYTES_PER_TOKEN_RANGE,
    INSTRUCTIONS_MAX_CHARS,
};
use crate::{
    context,
    conversation::{Message, Role},
    event, prompts,
    session::{GoalStatus, PendingTool, Session},
    tools::completion_evidence,
    AgentError,
};
use kernel::{world::Actor, World};
use protocol::GroupStatus;
use std::collections::BTreeSet;

impl ResidentRuntime {
    pub fn restore(state: RuntimeState, world: &World) -> Result<Self, AgentError> {
        validate_state(&state, world).map_err(AgentError::Restore)?;
        let mut runtime = Self::with_state(state)?;
        runtime.state.epoch = runtime
            .state
            .epoch
            .checked_add(1)
            .ok_or_else(|| AgentError::Restore("世界代次溢出".into()))?;
        let mut dropped = Vec::new();
        for session in runtime.state.sessions.values_mut() {
            // v1 存档的折叠归档内嵌在笔记里；搬到会话层，下一次检查点由 host 拆成文件。
            let legacy = std::mem::take(&mut session.notebook.legacy_archives);
            session.folded.archives.extend(legacy);
            if let Some(stamp) = session.drop_in_flight() {
                dropped.push(stamp.id);
                // 原请求已预留的预算不返还；不知道服务商是否执行，保守计量。
                if stamp.kind == RequestKind::Life {
                    session
                        .messages
                        .push(Message::text(Role::User, prompts::RESTORED_AFTER_RESTART));
                }
            }
        }
        for id in dropped {
            runtime.ledger_close(
                id,
                RequestStatus::Dropped,
                "进程重启，旧请求不重放；预留预算不返还",
            );
        }
        Ok(runtime)
    }

    /// 重置世界：清空会话、记忆和用量，一个会话也不留；保留配置及递增编号，隔离旧世界的在途回复。
    pub fn clear_world(&mut self) -> Result<(), AgentError> {
        *self = self.cleared()?;
        Ok(())
    }

    fn cleared(&self) -> Result<Self, AgentError> {
        let mut fresh = Self::new(self.state.limits.clone())?;
        fresh.state.epoch = self
            .state
            .epoch
            .checked_add(1)
            .ok_or_else(|| AgentError::Restore("世界代次溢出".into()))?;
        fresh.state.next_request = self.state.next_request;
        fresh.state.next_session = self.state.next_session;
        Ok(fresh)
    }
}

fn validate_state(state: &RuntimeState, world: &World) -> Result<(), String> {
    if state.schema_version != 1 || state.epoch == 0 {
        return Err("不支持的 Agent 会话版本或世界代次".into());
    }
    if !state.bytes_per_token.is_finite() || !BYTES_PER_TOKEN_RANGE.contains(&state.bytes_per_token)
    {
        return Err("token 校准系数超出范围".into());
    }
    state.limits.validate()?;
    let mut ids = BTreeSet::new();
    for (actor, session) in &state.sessions {
        let resident = world.actor(actor).ok_or("会话指向未知村民")?;
        if !ids.insert(session.id) {
            return Err(format!("会话编号 {} 重复", session.id));
        }
        validate_session(state, world, resident, session)?;
    }
    Ok(())
}

fn validate_session(
    state: &RuntimeState,
    world: &World,
    resident: &Actor,
    session: &Session,
) -> Result<(), String> {
    if let Some(problem) = session_problem(state, resident, session) {
        return Err(format!("村民 {} 的会话无效：{problem}", resident.id));
    }
    validate_requests(state, world, resident, session)?;
    validate_pending(world, resident, session)?;
    validate_goals(world, resident, session)?;
    session.memory.validate(world, &resident.id)?;
    session.notebook.validate(world, &resident.id)?;
    Ok(())
}

/// 编号、游标、上下文来源与人设长度的范围；返回第一条不成立的说明。
fn session_problem(
    state: &RuntimeState,
    resident: &Actor,
    session: &Session,
) -> Option<&'static str> {
    let cursor = resident.journal.cursor();
    let input = &session.input;
    let checks = [
        (input.ceiling != Some(0), "收紧后的输入额度为 0"),
        (
            input.sources.len() as u64 == input.next_source,
            "上下文来源数与来源编号不一致",
        ),
        (
            input
                .sources
                .keys()
                .all(|id| *id != 0 && *id <= input.next_source),
            "上下文来源编号超出范围",
        ),
        (
            input
                .summary_source
                .is_none_or(|id| input.sources.contains_key(&id)),
            "归档摘要指向不存在的上下文来源",
        ),
        (
            session.actor_id == resident.id,
            "会话的村民编号与世界人物不一致",
        ),
        (
            resident.actions.agent_controlled,
            "世界里这位村民没有交给 Agent 决策",
        ),
        (
            session.id != 0 && session.id <= state.next_session,
            "会话编号超出范围",
        ),
        (
            session.last_request_id <= state.next_request,
            "会话最近的请求编号超出范围",
        ),
        (
            session.cursors.acknowledged <= session.cursors.delivered,
            "已确认的事件游标超过已送出的游标",
        ),
        (
            session.cursors.delivered <= cursor,
            "已送出的事件游标超过村民的事件数",
        ),
        (
            session.cursors.last_notice <= cursor,
            "已处理的通知游标超过村民的事件数",
        ),
        (
            session.instructions.chars().count() <= INSTRUCTIONS_MAX_CHARS,
            "人设和公共知识超过长度上限",
        ),
    ];
    checks
        .iter()
        .find(|(ok, _)| !ok)
        .map(|(_, problem)| *problem)
}

/// 在途请求、等待条件、未配对的工具调用与精确计数的前缀要和世界、会话一致。
fn validate_requests(
    state: &RuntimeState,
    world: &World,
    resident: &Actor,
    session: &Session,
) -> Result<(), String> {
    let cursor = resident.journal.cursor();
    if let Some(request) = &session.in_flight {
        if request.id > state.next_request
            || request.epoch != state.epoch
            || request.seen_cursor > cursor
            || !request.sim_minutes.is_finite()
            || request.sim_minutes > world.minutes()
            || session.pending.iter().any(PendingTool::blocks_request)
        {
            return Err("存档模型请求无效".into());
        }
    }
    if session
        .sleep()
        .is_some_and(|s| !s.until.is_finite() || s.after_cursor > cursor)
    {
        return Err("会话等待条件无效".into());
    }
    let open = context::open_calls(&session.messages)?;
    let expected: BTreeSet<_> = session
        .pending
        .iter()
        .filter(|p| p.blocks_request())
        .map(|p| p.call().id.clone())
        .collect();
    if open != expected {
        return Err("会话工具消息与等待状态不一致".into());
    }
    if session
        .known_prefix()
        .is_some_and(|k| k.messages > session.messages.len())
    {
        return Err("精确计数的前缀超过会话长度".into());
    }
    Ok(())
}

/// 待完成工具必须对应世界里真实的动作组或互动；世界在执行的动作组都要有记录，
/// 世界替带路人排的「前往」除外：它不经工具调用，会话里本来就没有。
fn validate_pending(world: &World, resident: &Actor, session: &Session) -> Result<(), String> {
    let actor = resident.id.as_str();
    let cursor = resident.journal.cursor();
    let running: BTreeSet<_> = resident
        .actions
        .groups
        .values()
        .filter(|g| g.status == GroupStatus::Running && !world.is_lead_group(actor, &g.id))
        .map(|g| g.id.as_str())
        .collect();
    let mut tracked = BTreeSet::new();
    for id in &resident.actions.player_groups {
        if world.action_group(actor, id).is_none() {
            return Err("玩家动作来源指向不存在的动作".into());
        }
        tracked.insert(id.as_str());
    }
    for id in &resident.actions.player_interactions {
        if world.interactions().of(actor, id).is_none() {
            return Err("玩家互动来源指向不存在的互动".into());
        }
    }

    for pending in &session.pending {
        match pending {
            PendingTool::Interaction { interaction_id, .. } => {
                if world
                    .interactions()
                    .of(actor, interaction_id)
                    .is_none_or(|i| i.partner != actor || i.accepted != Some(true))
                {
                    return Err("会话的待完成互动不存在或未经本人同意".into());
                }
            }
            PendingTool::Actions { group_id, .. } => {
                if world.action_group(actor, group_id).is_none() {
                    return Err("会话的待完成动作不存在".into());
                }
                tracked.insert(group_id.as_str());
            }
            PendingTool::Wait {
                until,
                after_cursor,
                ..
            } if !until.is_finite() || *after_cursor > cursor => {
                return Err("工具等待条件无效".into())
            }
            PendingTool::Wait { .. } => {}
        }
    }
    if !running.is_subset(&tracked) {
        return Err("世界正在执行会话未记录的动作".into());
    }
    let current = resident
        .current
        .interaction
        .as_ref()
        .and_then(|id| world.interactions().of(actor, id));
    if let Some(item) = current {
        let tracked = session.pending.iter().any(
            |p| matches!(p, PendingTool::Interaction { interaction_id, .. } if *interaction_id == item.id),
        );
        if item.chat.is_none()
            && item.partner == actor
            && !tracked
            && !resident.actions.player_interactions.contains(&item.id)
        {
            return Err("受邀者正在进行会话未记录的双方活动".into());
        }
    }
    Ok(())
}

/// 目标时间与证据必须指向本人真实事件；已完成的目标要能重新找到完成证据。
fn validate_goals(world: &World, resident: &Actor, session: &Session) -> Result<(), String> {
    for (id, goal) in &session.goals {
        if goal.id != *id
            || !goal.created_at.is_finite()
            || !goal.updated_at.is_finite()
            || goal.created_at > goal.updated_at
            || goal.updated_at > world.minutes()
            || goal
                .evidence
                .iter()
                .any(|id| event(resident, *id).is_none())
        {
            return Err("目标时间或证据无效".into());
        }
        if goal.status == GoalStatus::Completed {
            let found = completion_evidence(world, &resident.id, &goal.condition, goal.created_at)
                .is_ok_and(|ids| ids.iter().any(|id| goal.evidence.contains(id)));
            if !found {
                return Err("完成目标缺少世界结果".into());
            }
        }
    }
    Ok(())
}
