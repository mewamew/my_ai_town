//! 会话与世界结果的观察仪投影，保持有界并保留可追溯的原始事件。
//! 分两份：名册里每拍带的状态（`view`，每位村民每拍算一次，只放便宜的），和角色卡细节
//! （`detail`，有连接看着这位村民时才算）。
mod memory_page;
use crate::{
    event, interaction,
    memory::{self, MemoryStatus, TEXT_PREVIEW_CHARS},
    runtime::ResidentRuntime,
    session::{Goal, GoalStatus, PendingTool, Session},
};
use kernel::{world::Actor, World};
use protocol::{
    AgentState, AgentWaitView, FactKind, GoalMark, ResidentAgentView, ResidentDetailView,
    ResidentGoalView, ResidentMemoryView, ResidentUsage,
};

/// 观察仪各列表的上限。
const GOALS_SHOWN: usize = 12;
const RESULTS_SHOWN: usize = 6;
const INTERACTIONS_SHOWN: usize = 6;
const MEMORIES_SHOWN: usize = 8;
const EVENTS_PER_MEMORY: usize = 4;
const EVENT_TEXT_SHOWN: usize = 600;

/// 村民姓名；世界里没有这个人时退回编号。
pub(crate) fn actor_name(world: &World, id: &str) -> String {
    world
        .actor(id)
        .map_or_else(|| id.to_string(), |a| a.name.clone())
}

/// 村民此刻的状态与说明；按严重程度从前往后判断。状态是枚举，前端按值查文案。
/// 在等时另给结构化的等待：角色卡「正在」一栏按它写等什么、几点醒。
fn state_label(
    world: &World,
    s: &Session,
    a: &Actor,
) -> (AgentState, String, Option<AgentWaitView>) {
    let actor = s.actor_id.as_str();
    let plain = |state, text: &str| (state, text.to_string(), None);
    if a.needs.body.dead {
        return plain(AgentState::Dead, "停止决策；需要明确的复活手段");
    }
    if a.possession.is_some() {
        return plain(AgentState::Manual, "玩家正在附身，AI 暂停决策");
    }
    if let Some(reason) = s.pause_reason() {
        return plain(AgentState::paused(s.pause_kind()), reason);
    }
    if a.needs.incapacitated() {
        return plain(AgentState::Rescue, a.needs.limitation());
    }
    if world.active_chat(actor).is_some() {
        let doing = if world.chat_turn(actor) {
            "正在考虑如何回应"
        } else {
            "正在听其他人说话"
        };
        return plain(AgentState::Chatting, doing);
    }
    if a.current.interaction.is_some() {
        let text = format!("{}；等待双方活动结束", a.current.verb);
        return plain(AgentState::Interacting, &text);
    }
    if s.in_flight.is_some() {
        return if s.notebook.request.is_some() {
            plain(AgentState::Reflecting, "正在根据新增经历总结并提炼主题")
        } else {
            plain(AgentState::Thinking, "正在等待模型响应")
        };
    }
    match s.pending.first() {
        Some(PendingTool::Actions { .. }) => {
            return plain(AgentState::Acting, "等待世界返回动作结果")
        }
        Some(PendingTool::Interaction { .. }) => {
            return plain(AgentState::Interacting, "等待世界返回双方活动结果")
        }
        Some(PendingTool::Wait {
            until,
            call,
            event,
            invitation,
            ..
        }) => {
            let reason = if invitation.is_some() {
                "等待对方回应邀请"
            } else {
                call.arguments["reason"].as_str().unwrap_or("等待事件")
            };
            let text = format!("{reason} · 最迟 {} 再看", kernel::clock_string(*until));
            let wait = AgentWaitView {
                reason: reason.into(),
                until: *until,
                event: *event,
            };
            return (AgentState::Waiting, text, Some(wait));
        }
        None => {}
    }
    if s.streaks.model_failures > 0 && s.streaks.retry_at > 0 {
        let text = format!("模型请求失败 {} 次，稍后自动重试", s.streaks.model_failures);
        return plain(AgentState::Waiting, &text);
    }
    if let Some(sleep) = s.sleep() {
        let text = format!(
            "{} · {} 再看",
            sleep.reason,
            kernel::clock_string(sleep.until)
        );
        // 搁置的唤醒：到点再看；收得到要紧通知的，通知来了也会提前醒
        let wait = AgentWaitView {
            reason: sleep.reason.clone(),
            until: sleep.until,
            event: sleep.wake_on_notice.then_some(FactKind::Notice),
        };
        return (AgentState::Waiting, text, Some(wait));
    }
    plain(AgentState::Undecided, "等世界继续后决定下一步")
}

impl Session {
    /// 消耗页与额度页的按人一行。姓名要查世界，所以不是 `From`。
    pub fn usage(&self, world: &World) -> ResidentUsage {
        ResidentUsage {
            id: self.actor_id.clone(),
            name: actor_name(world, &self.actor_id),
            daily_calls: self.daily.calls,
            daily_tokens: self.daily.tokens,
            daily_input_tokens: self.daily.input_tokens,
            daily_cache_hit_tokens: self.daily.cache_hit_tokens,
            replies: self.tally.replies,
            stale_replies: self.tally.stale_replies,
            in_flight: self.in_flight.is_some(),
            paused: self
                .pause_reason()
                .map(|reason| format!("{}：{reason}", self.pause_kind().label())),
        }
    }
}

/// 最近定下或改过的进行中目标：画面上换了就冒灯泡。改动时刻相同时取编号靠前的。
fn latest_goal(s: &Session) -> Option<GoalMark> {
    let mut latest: Option<&Goal> = None;
    for goal in s.goals.values().filter(|g| g.status == GoalStatus::Active) {
        if latest.is_none_or(|l| goal.updated_at > l.updated_at) {
            latest = Some(goal);
        }
    }
    latest.map(|g| GoalMark {
        id: g.id.clone(),
        updated_at: g.updated_at,
    })
}

/// 进行中和暂停的目标在前，其余按更新时间倒序。
fn goal_views(s: &Session) -> Vec<ResidentGoalView> {
    let mut goals: Vec<_> = s.goals.values().collect();
    goals.sort_by(|l, r| {
        r.status
            .is_open()
            .cmp(&l.status.is_open())
            .then_with(|| r.updated_at.total_cmp(&l.updated_at))
    });
    goals
        .into_iter()
        .take(GOALS_SHOWN)
        .map(|g| ResidentGoalView {
            id: g.id.clone(),
            title: g.title.clone(),
            status: g.status,
            reason: g.reason.clone(),
            commitment: g.commitment.clone(),
            next_steps: g.next_steps.clone(),
            updated_at: g.updated_at,
        })
        .collect()
}

fn recent_results(a: &Actor) -> Vec<protocol::ActionResultView> {
    let mut results: Vec<_> = a
        .actions
        .groups
        .values()
        .flat_map(|g| g.results.iter().map(move |r| (g, r)))
        .collect();
    results.sort_by(|(_, a), (_, b)| {
        b.ended_at
            .total_cmp(&a.ended_at)
            .then_with(|| b.event_ids.cmp(&a.event_ids))
    });
    results
        .into_iter()
        .take(RESULTS_SHOWN)
        .map(|(g, r)| protocol::ActionResultView {
            result: r.clone(),
            verb_kind: kernel::action_state::result_verb_kind(g, r),
        })
        .collect()
}

/// 最新的有效记忆，同一件事只出现一次；每条附上来源事件的节选。
fn memory_views(s: &Session, a: &Actor) -> Vec<ResidentMemoryView> {
    let mut memories: Vec<_> = s
        .memory
        .records
        .iter()
        .filter(|m| m.status != MemoryStatus::Superseded)
        .collect();
    memories.sort_by(|a, b| {
        b.at.total_cmp(&a.at)
            .then_with(|| b.memory_id.cmp(&a.memory_id))
    });
    memory::distinct_records(memories, MEMORIES_SHOWN)
        .into_iter()
        .map(|m| ResidentMemoryView {
            memory_id: m.memory_id,
            kind: m.kind,
            source: m.source,
            status: m.status,
            confidence: m.confidence,
            text: m.text.chars().take(TEXT_PREVIEW_CHARS).collect(),
            at: m.at,
            replaces: m.replaces.clone(),
            events: m
                .event_ids
                .iter()
                .rev()
                .take(EVENTS_PER_MEMORY)
                .filter_map(|id| event(a, *id))
                .cloned()
                .map(|mut e| {
                    e.text = e.text.chars().take(EVENT_TEXT_SHOWN).collect();
                    e
                })
                .collect(),
        })
        .collect()
}

/// 一位村民「记着的事」的缓存，由运行器持有，不存档。记忆每变一次修订号就加一，会话和修订号都没变
/// 就用上次算好的，不必每次把全部记忆排一遍序；来源事件写下后不再改，所以不用另外看。
#[derive(Debug, Default)]
pub(crate) struct MemoryViews {
    /// 会话编号、记忆修订号，和按它们算出的那一份
    cached: Option<(u64, u64, Vec<ResidentMemoryView>)>,
}

impl MemoryViews {
    fn get(&mut self, s: &Session, a: &Actor) -> Vec<ResidentMemoryView> {
        match &self.cached {
            Some((session, revision, views))
                if (*session, *revision) == (s.id, s.memory.revision) =>
            {
                views.clone()
            }
            _ => {
                let views = memory_views(s, a);
                self.cached = Some((s.id, s.memory.revision, views.clone()));
                views
            }
        }
    }
}

impl ResidentRuntime {
    /// 名册里每拍带的状态：每位村民每拍算一次，不排序、不整份抄记忆。
    pub fn view(&self, world: &World, actor: &str) -> Option<ResidentAgentView> {
        let s = self.session(actor)?;
        let a = world.actor(actor)?;
        let (state, reason, wait) = state_label(world, s, a);
        Some(ResidentAgentView {
            state,
            reason,
            wait,
            latest_goal: latest_goal(s),
            declined_invitation: world
                .interactions()
                .latest_declined_offer(actor)
                .map(|i| i.id.clone()),
        })
    }

    /// 角色卡细节：目标、最近的动作结果、互动和记着的事。有连接看着这位村民时 host 才来取。
    pub fn detail(&mut self, world: &World, actor: &str) -> Option<ResidentDetailView> {
        let a = world.actor(actor)?;
        let (s, memories) = self.session_with_memory_views(actor)?;
        Some(ResidentDetailView {
            goals: goal_views(s),
            results: recent_results(a),
            interactions: world
                .interactions()
                .for_actor(actor)
                .into_iter()
                .take(INTERACTIONS_SHOWN)
                .map(|i| interaction::summary(world, i))
                .collect(),
            memories: memories.get(s, a),
        })
    }
}
