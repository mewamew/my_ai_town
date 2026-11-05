//! 村民 Agent 运行器：无网络、无线程；host 负责发送请求并交回同一个编号。
use crate::{
    budget::{Account, Limits},
    conversation::{estimate_tokens, wire_bytes, Message, Role},
    memory::MemoryIndex,
    notebook::{Documents, DocumentsCache, ReflectionBatch, REFLECTION_INTERVAL},
    observation, prompts, resident,
    session::{HoldCause, PauseKind, RequestStamp, Session},
    tools, AgentError,
};
use kernel::{world::Actor, World};
use protocol::FactKind;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, VecDeque},
    hash::{DefaultHasher, Hash, Hasher},
    rc::Rc,
};

mod arrivals;
mod chat;
mod controlled;
mod input;
mod invitations;
mod ledger;
mod pending;
mod recovery;
mod reflection;
mod relevance;
mod response;
mod retry;
mod thought;
pub use controlled::ControlCheckpoint;
pub use ledger::{RequestKind, RequestRecord, RequestStatus, LEDGER_LIMIT};
pub use retry::SAME_FAILURE_BEFORE_POSTPONE;

/// 人设与公共知识的字数上限。
pub const INSTRUCTIONS_MAX_CHARS: usize = 12_000;
/// 预留 token 在估算之上加的百分比。
const RESERVE_MARGIN_PERCENT: u64 = 15;
/// 校准每 token 字节数时新样本的权重。
const BYTES_PER_TOKEN_SMOOTHING: f64 = 0.3;
pub(crate) const BYTES_PER_TOKEN_RANGE: std::ops::RangeInclusive<f64> = 1.5..=6.0;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeState {
    pub schema_version: u32,
    pub epoch: u64,
    pub next_request: u64,
    pub next_session: u64,
    pub sessions: BTreeMap<String, Session>,
    pub limits: Limits,
    pub lifetime: Account,
    pub last_dispatched: Option<String>,
    /// 每 token 的正文字节数，按服务商返回的 usage 指数平均校准。
    #[serde(default = "bytes_per_token_default")]
    pub bytes_per_token: f64,
    /// 最近的模型请求台账（消耗页用），最多 LEDGER_LIMIT 条。
    #[serde(default)]
    pub requests: VecDeque<RequestRecord>,
}
fn bytes_per_token_default() -> f64 {
    3.5
}

fn digest(parts: &[&str]) -> u64 {
    let mut hasher = DefaultHasher::new();
    for part in parts {
        part.hash(&mut hasher);
    }
    hasher.finish()
}

/// 观察里变化慢的字段：和本段会话上次发出的相同时省略。
pub(crate) const SLOW_OBSERVATION_FIELDS: [&str; 8] = [
    "visible_props",
    "environment",
    "people_here",
    "inventory",
    "body",
    "known_places",
    "exits",
    "spots",
];

/// 字段连同它的来源引用一起计摘要，截断方式变了也算变化。
pub(crate) fn observation_field_digest(observation: &Value, key: &str) -> u64 {
    let source = observation[format!("{key}_source")].to_string();
    digest(&[&observation[key].to_string(), &source])
}

fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// 游标之后是否到达能唤醒等待的事件：重要通知，或指定种类的事件。
pub(crate) fn event_arrived(actor: &Actor, after: u64, kind: Option<FactKind>) -> bool {
    actor
        .journal
        .events_after(after)
        .iter()
        .any(|e| e.kind == FactKind::Notice || kind.is_some_and(|k| k == e.kind))
}

struct BudgetShortfall {
    scope: &'static str,
    calls: u64,
    calls_limit: u64,
    tokens: u64,
    tokens_limit: u64,
    reserve: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentRequest {
    pub actor_id: String,
    pub session_id: u64,
    pub stamp: RequestStamp,
    pub messages: Vec<Message>,
    pub tools: Vec<Value>,
    pub max_output_tokens: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceRecord {
    pub schema_version: u32,
    pub epoch: u64,
    pub actor_id: String,
    pub session_id: u64,
    pub request_id: Option<u64>,
    pub sim_minutes: f64,
    pub event: String,
    pub data: Value,
}

/// 一条轨迹：事件名、数据，可选关联的请求编号。
pub(crate) struct Trace {
    request: Option<u64>,
    event: &'static str,
    data: Value,
}
impl Trace {
    pub(crate) fn new(event: &'static str, data: Value) -> Self {
        Self {
            request: None,
            event,
            data,
        }
    }
    pub(crate) fn request(mut self, id: u64) -> Self {
        self.request = Some(id);
        self
    }
}

/// 一轮请求的种类：整理批次、带观察的生活决策，或轮到本人发言的交谈。
enum PlannedRound {
    Reflection(ReflectionBatch),
    Life { observation: Value },
    Chat,
}
impl PlannedRound {
    fn kind(&self) -> RequestKind {
        match self {
            Self::Reflection(_) => RequestKind::Reflection,
            Self::Life { .. } => RequestKind::Life,
            Self::Chat => RequestKind::Chat,
        }
    }
}

/// 已排好的请求内容与估算。
struct Draft {
    messages: Vec<Message>,
    estimated: u64,
    sent_bytes: u64,
    prefix_digest: u64,
    seen: u64,
    /// 生活决策本轮的 user 消息及其 JSON 正文；整理轮次没有。
    user: Option<(Message, Value)>,
    /// 交谈轮次在本场对话末尾新加的内容；回复被采纳后并入记录。
    chat: Option<crate::session::ChatDelta>,
}

pub struct ResidentRuntime {
    state: RuntimeState,
    index: MemoryIndex,
    trace: Vec<TraceRecord>,
    /// 每位村民记忆文件视图的缓存；不存档。
    documents: BTreeMap<String, DocumentsCache>,
    /// 最近一次 poll 传入的现实时间（Unix 秒），写进台账。
    wall_clock: u64,
}

impl ResidentRuntime {
    pub fn new(limits: Limits) -> Result<Self, AgentError> {
        limits.validate().map_err(AgentError::Limits)?;
        Self::with_state(RuntimeState {
            schema_version: 1,
            epoch: 1,
            next_request: 0,
            next_session: 0,
            sessions: BTreeMap::new(),
            limits,
            lifetime: Account::default(),
            last_dispatched: None,
            bytes_per_token: bytes_per_token_default(),
            requests: Default::default(),
        })
    }
    fn with_state(state: RuntimeState) -> Result<Self, AgentError> {
        Ok(Self {
            state,
            index: MemoryIndex::new()?,
            trace: vec![],
            documents: BTreeMap::new(),
            wall_clock: 0,
        })
    }
    pub fn state(&self) -> &RuntimeState {
        &self.state
    }
    pub fn session(&self, actor: &str) -> Option<&Session> {
        self.state.sessions.get(actor)
    }
    pub fn drain_trace(&mut self) -> Vec<TraceRecord> {
        std::mem::take(&mut self.trace)
    }

    pub fn register(
        &mut self,
        world: &mut World,
        actor: &str,
        instructions: &str,
    ) -> Result<(), AgentError> {
        if instructions.chars().count() > INSTRUCTIONS_MAX_CHARS {
            return Err(AgentError::Instructions(
                "人设和公共知识超过长度上限".into(),
            ));
        }
        self.validate_instructions(world, actor, instructions)?;
        world.enable_agent(actor)?;
        if let Some(session) = self.state.sessions.get_mut(actor) {
            session.instructions = instructions.into();
        } else {
            self.state.next_session += 1;
            let mut session = Session::new(self.state.next_session, actor, instructions);
            // 接管旧世界时，历史进入可检索记忆，不能把几天前的通知当成请求中的新中断。
            session.start_at_cursor(resident(world, actor)?.journal.cursor());
            self.state.sessions.insert(actor.into(), session);
        }
        Ok(())
    }

    /// 现实时间取自系统时钟的便捷入口；确定性场景用 `poll_at`。
    pub fn poll(&mut self, world: &mut World, running: bool) -> Vec<AgentRequest> {
        self.poll_at(world, running, unix_now())
    }

    /// 公平轮转；同时在途数量有上限，等待世界时不占模型计算名额。
    /// `unix_now` 写进台账的发出时间，也用来隔开模型失败后的重试；别的决策只看模拟时间。
    pub fn poll_at(
        &mut self,
        world: &mut World,
        running: bool,
        unix_now: u64,
    ) -> Vec<AgentRequest> {
        self.wall_clock = unix_now;
        let mut requests = Vec::new();
        let mut actors: Vec<_> = self.state.sessions.keys().cloned().collect();
        if let Some(last) = &self.state.last_dispatched {
            let offset = actors.iter().position(|id| id > last).unwrap_or(0);
            actors.rotate_left(offset);
        }
        let mut in_flight = self
            .state
            .sessions
            .values()
            .filter(|s| s.in_flight.is_some())
            .count();
        for actor in actors {
            let mut session = self
                .state
                .sessions
                .remove(&actor)
                .expect("会话列表来自同一张表");
            session.memory.ingest(world, &actor);
            if world.actor(&actor).is_none_or(|a| a.possession.is_none()) {
                self.resolve_pending(world, &mut session);
                self.wake_for_chat_turn(world, &mut session);
            }
            if running
                && wants_request(world, &session)
                && in_flight < self.state.limits.max_concurrent
                && self.awake(world, &mut session)
            {
                match self.prepare(world, &mut session) {
                    Ok(Some(request)) => {
                        self.state.last_dispatched = Some(actor.clone());
                        in_flight += 1;
                        requests.push(request);
                    }
                    Ok(None) => {}
                    Err(error) => self.pause_fault(world, &mut session, error.to_string(), None),
                }
            }
            self.state.sessions.insert(actor, session);
        }
        requests
    }

    /// 轮到本人发言时立即唤醒；同一动作版本只唤醒一次。
    fn wake_for_chat_turn(&self, world: &World, s: &mut Session) {
        if !world.chat_turn(&s.actor_id) {
            return;
        }
        let revision = world.actor(&s.actor_id).map_or(0, |a| a.actions.revision);
        s.wake_for_turn(revision);
    }

    fn awake(&mut self, world: &World, s: &mut Session) -> bool {
        if !due(world, s) || self.retry_pending(world, s) {
            return false;
        }
        if s.sleep().is_some() {
            s.wake_up();
        }
        true
    }

    /// 有村民在等模型：请求在途，或者此刻就该发请求（要做决定、醒着、没有暂停），
    /// 或者上次请求失败、正等着重试（重试仍按现实时间隔开，给模型服务恢复的时间）。
    /// 有人在等就按正常速度走、不快进，回复才赶得上世界。
    pub fn thinking(&self, world: &World) -> bool {
        self.state.sessions.values().any(|s| {
            let due = due(world, s);
            s.in_flight.is_some()
                || (s.streaks.model_failures > 0 && (!due || self.retry_pending(world, s)))
                || (due && wants_request(world, s))
        })
    }

    /// 生活轮次的模型请求刚失败、还没到现实的重试时刻。轮到发言不等：交谈有自己的重试规则。
    fn retry_pending(&self, world: &World, s: &Session) -> bool {
        self.wall_clock < s.streaks.retry_at && !world.chat_turn(&s.actor_id)
    }

    fn docs(&mut self, world: &World, s: &Session) -> Rc<Documents> {
        self.documents
            .entry(s.actor_id.clone())
            .or_default()
            .get(world, s)
    }

    fn prepare(
        &mut self,
        world: &World,
        s: &mut Session,
    ) -> Result<Option<AgentRequest>, AgentError> {
        let now = world.minutes();
        let cursor = resident(world, &s.actor_id)?.journal.cursor();
        let day = kernel::calendar::day_index(now);
        if s.daily.day < day {
            s.memory.consolidate(world, &s.actor_id);
        }
        s.daily.new_day(day);
        let limits = self.state.limits.clone();
        if s.wake_calls() >= limits.calls_per_wake {
            retry::postpone(s, now, "本次唤醒达到调用上限", false, cursor);
            self.record(world, s, Trace::new("wait", json!(s.sleep())));
            return Ok(None);
        }
        let round = self.plan_round(world, s)?;
        let kind = round.kind();
        let tools = tools::definitions(kind);
        let tools_json = serde_json::to_string(&tools).expect("工具定义可序列化");
        let draft = match &round {
            PlannedRound::Reflection(batch) => self.reflection_draft(world, s, batch, &tools_json),
            PlannedRound::Life { observation } => {
                self.fit_context(world, s, observation, &tools_json)?
            }
            PlannedRound::Chat => self.chat_draft(world, s, &tools_json)?,
        };
        if draft.estimated > self.input_budget(s) {
            return Err(AgentError::Context(
                "最小必要上下文仍超过可用输入额度，请检查模型窗口与居民设定".into(),
            ));
        }
        let reserve = draft.estimated
            + draft.estimated * RESERVE_MARGIN_PERCENT / 100
            + limits.max_output_tokens;
        if let Err(shortfall) = self.check_budget(s, reserve) {
            let reflecting = kind == RequestKind::Reflection;
            return Ok(self.out_of_budget(world, s, reflecting, shortfall));
        }
        Ok(Some(self.dispatch(world, s, round, draft, tools, reserve)))
    }

    /// 轮到本人发言就走交谈轮次；有待整理的批次且放得下就走整理轮次；否则观察世界，走生活决策。
    fn plan_round(&mut self, world: &World, s: &mut Session) -> Result<PlannedRound, AgentError> {
        if world.chat_turn(&s.actor_id) {
            return Ok(PlannedRound::Chat);
        }
        // 不在交谈轮次说明交谈已结束，本场对话记录不再需要。
        s.chat = Default::default();
        if !world.interactions().has_talk_invitation(&s.actor_id) {
            if let Some(batch) = crate::notebook::plan_reflection(world, s) {
                let docs = self.docs(world, s);
                let fitted = reflection::fit_reflection(
                    world,
                    s,
                    &docs,
                    batch,
                    self.input_budget(s),
                    self.state.bytes_per_token,
                );
                if let Some(batch) = fitted {
                    return Ok(PlannedRound::Reflection(batch));
                }
                s.notebook.request = None;
                s.notebook.reading_dialogue.clear();
                s.notebook.retry_after = world.minutes() + REFLECTION_INTERVAL;
                let data = json!({
                    "reason": "单条经历与整理上下文超过窗口，原文保留，继续正常决策",
                    "retry_after": s.notebook.retry_after
                });
                self.record(world, s, Trace::new("reflection_deferred", data));
            }
        }
        let (observation, _) = observation::observe(world, &s.actor_id, s.cursors.acknowledged)?;
        Ok(PlannedRound::Life { observation })
    }

    /// 整理轮次不进生活会话：单独的 system 与 user，没有历史，也不推进观察游标。
    fn reflection_draft(
        &mut self,
        world: &World,
        s: &mut Session,
        batch: &ReflectionBatch,
        tools_json: &str,
    ) -> Draft {
        let docs = self.docs(world, s);
        let messages = reflection::messages(world, s, batch, &docs);
        let sent_bytes = wire_bytes(&messages) + tools_json.len() as u64;
        let usage = ContextUsage {
            kind: RequestKind::Reflection,
            restart: None,
            system_bytes: wire_bytes(&messages[..1]),
            tools_bytes: tools_json.len() as u64,
            summary_bytes: 0,
            history_bytes: wire_bytes(&s.notebook.reading_dialogue),
            current_bytes: wire_bytes(&messages[1..2]),
            estimated: estimate_tokens(sent_bytes, self.state.bytes_per_token),
            budget: self.input_budget(s),
            target: None,
        };
        self.record_context_budget(world, s, usage);
        Draft {
            estimated: estimate_tokens(sent_bytes, self.state.bytes_per_token),
            messages,
            sent_bytes,
            prefix_digest: 0,
            seen: s.cursors.acknowledged,
            user: None,
            chat: None,
        }
    }

    /// 总额度先于当日额度；任一不足即停。
    fn check_budget(&self, s: &Session, reserve: u64) -> Result<(), BudgetShortfall> {
        let limits = &self.state.limits;
        let scopes = [
            (
                "运行时总调用或 token 预算耗尽",
                &self.state.lifetime,
                limits.total_calls,
                limits.total_tokens,
            ),
            (
                "今天的调用或 token 预算耗尽",
                &s.daily,
                limits.calls_per_day,
                limits.tokens_per_day,
            ),
        ];
        for (scope, account, calls_limit, tokens_limit) in scopes {
            if account.calls >= calls_limit || account.tokens.saturating_add(reserve) > tokens_limit
            {
                return Err(BudgetShortfall {
                    scope,
                    calls: account.calls,
                    calls_limit,
                    tokens: account.tokens,
                    tokens_limit,
                    reserve,
                });
            }
        }
        Ok(())
    }

    /// 预算已过：登记请求编号、预留用量与在途状态，生活轮次把 user 消息写入会话。
    fn dispatch(
        &mut self,
        world: &World,
        s: &mut Session,
        round: PlannedRound,
        draft: Draft,
        tools: Vec<Value>,
        reserve: u64,
    ) -> AgentRequest {
        let limits = self.state.limits.clone();
        self.state.next_request += 1;
        let kind = round.kind();
        let stamp = RequestStamp {
            id: self.state.next_request,
            epoch: self.state.epoch,
            revision: world.actor(&s.actor_id).map_or(0, |a| a.actions.revision),
            seen_cursor: draft.seen,
            sim_minutes: world.minutes(),
            reserved_tokens: reserve,
            day: kernel::calendar::day_index(world.minutes()),
            sent_bytes: draft.sent_bytes,
            prefix_digest: draft.prefix_digest,
            kind,
        };
        let batch = match round {
            PlannedRound::Reflection(batch) => Some(batch),
            PlannedRound::Life { .. } | PlannedRound::Chat => None,
        };
        s.daily.charge(reserve);
        self.state.lifetime.charge(reserve);
        self.ledger_open(s, &stamp, kind, draft.estimated);
        s.in_flight = Some(stamp.clone());
        s.last_request_id = stamp.id;
        s.notebook.request = batch;
        s.chat.pending = draft.chat;
        if let Some((user, body)) = draft.user {
            s.count_wake_call();
            mark_shown(s, &body);
            s.cursors.delivered = s.cursors.delivered.max(draft.seen);
            s.messages.push(user);
        }
        let request = AgentRequest {
            actor_id: s.actor_id.clone(),
            session_id: s.id,
            stamp,
            messages: draft.messages,
            tools,
            max_output_tokens: limits.max_output_tokens,
        };
        let data = json!({
            "request": request,
            "limits": limits,
            "estimated_tokens": draft.estimated,
            "bytes_per_token": self.state.bytes_per_token,
            "known_prefix": s.known_prefix()
        });
        self.record(
            world,
            s,
            Trace::new("request", data).request(request.stamp.id),
        );
        request
    }

    /// 整理额度不足只推迟整理；必要生活决策拿不到额度则按额度原因停止，由 host 暂停全镇。
    /// 不靠等待模拟次日恢复：用户修改额度并主动继续后才重新检查。
    fn out_of_budget(
        &mut self,
        world: &World,
        s: &mut Session,
        reflecting: bool,
        shortfall: BudgetShortfall,
    ) -> Option<AgentRequest> {
        let budget = json!({
            "calls": shortfall.calls,
            "calls_limit": shortfall.calls_limit,
            "tokens": shortfall.tokens,
            "tokens_limit": shortfall.tokens_limit,
            "reserve": shortfall.reserve
        });
        if reflecting {
            s.notebook.retry_after = world.minutes() + REFLECTION_INTERVAL;
            let data = json!({
                "reason": format!("{}，整理推迟，原始记录保留", shortfall.scope),
                "retry_after": s.notebook.retry_after,
                "budget": budget
            });
            self.record(world, s, Trace::new("reflection_deferred", data));
            return None;
        }
        let reason = format!(
            "{}：调用 {}/{}，token {}/{}，本次需预留 {}；请修改额度再继续",
            shortfall.scope,
            shortfall.calls,
            shortfall.calls_limit,
            shortfall.tokens,
            shortfall.tokens_limit,
            shortfall.reserve
        );
        s.pause(PauseKind::Budget, reason.clone());
        let data = json!({"kind":"budget","reason":reason,"budget":budget});
        self.record(world, s, Trace::new("paused", data));
        None
    }

    /// 需要全镇停下的会话：额度用尽、故障、回复接连过时。模型服务名由 host 按绑定补上。
    pub fn town_holds(&self, world: &World) -> Vec<protocol::WorldHold> {
        self.state
            .sessions
            .values()
            .filter(|s| s.pause_kind().holds_town())
            .filter_map(|s| {
                Some(protocol::WorldHold {
                    resident_id: s.actor_id.clone(),
                    resident: crate::view::actor_name(world, &s.actor_id),
                    kind: s.pause_kind(),
                    reason: s.pause_reason()?.to_owned(),
                    cause: s.pause_cause(),
                    provider: String::new(),
                })
            })
            .collect()
    }

    /// 用户主动继续：清除停止原因并留档。条件仍在时，下一次请求前会再次停止。
    /// 等模型的不在此列，模型能用了自己会接着走。
    pub fn resume(&mut self, world: &World) -> usize {
        let mut resumed = 0;
        let actors: Vec<_> = self.state.sessions.keys().cloned().collect();
        for actor in actors {
            let mut session = self
                .state
                .sessions
                .remove(&actor)
                .expect("会话来自同一张表");
            if !session.waiting_for_model() && session.resume() {
                resumed += 1;
                self.record(world, &session, Trace::new("resumed", json!({})));
            }
            self.state.sessions.insert(actor, session);
        }
        resumed
    }

    /// host 每拍告诉运行器谁还没有能用的模型（村民编号 → 给玩家看的原因）。
    /// 没有别的停止原因的人停在等模型上，不发请求、不算失败；名单里没有了就自动接着走。
    pub fn wait_for_models(&mut self, world: &World, missing: &BTreeMap<String, String>) {
        let actors: Vec<_> = self.state.sessions.keys().cloned().collect();
        for actor in actors {
            let mut session = self
                .state
                .sessions
                .remove(&actor)
                .expect("会话来自同一张表");
            match missing.get(&actor) {
                Some(reason) if session.pause_reason().is_none() => {
                    session.pause(PauseKind::NoModel, reason.clone());
                    let data = json!({"kind":"no_model","reason":reason});
                    self.record(world, &session, Trace::new("paused", data));
                }
                Some(reason) if session.waiting_for_model() => {
                    // 原因变了（比如选了服务但还没填密钥）就换成新的说法，不另记轨迹
                    if session.pause_reason() != Some(reason.as_str()) {
                        session.pause(PauseKind::NoModel, reason.clone());
                    }
                }
                None if session.stop_waiting_for_model() => {
                    let data = json!({"kind":"no_model"});
                    self.record(world, &session, Trace::new("resumed", data));
                }
                _ => {}
            }
            self.state.sessions.insert(actor, session);
        }
    }

    /// 有人停在等模型上，而且没有一个村民能自己做决定（死去、失能、被附身的不算）。
    /// host 据此让时间停着：谁都不会思考时世界照走，他们只会一路饿着。
    pub fn nobody_can_think(&self, world: &World) -> bool {
        let mut waiting = false;
        for s in self.state.sessions.values() {
            let Some(a) = world.actor(&s.actor_id) else {
                continue;
            };
            if !a.present()
                || a.needs.body.dead
                || a.needs.incapacitated()
                || a.possession.is_some()
            {
                continue;
            }
            if s.waiting_for_model() {
                waiting = true;
            } else {
                return false;
            }
        }
        waiting
    }

    /// 空等着的村民过多少分钟再想：等待工具到点或推迟到的时刻，取早的。现在就该想、
    /// 或者没约时间的为 None。host 据此算能快进多久（kernel::World::quiet_minutes）。
    pub fn next_thought_in(&self, world: &World, actor_id: &str) -> Option<f64> {
        let s = self.state.sessions.get(actor_id)?;
        let waits = s.pending.iter().filter_map(|p| match p {
            crate::session::PendingTool::Wait { until, .. } => Some(*until),
            _ => None,
        });
        let until = waits
            .chain(s.sleep().map(|sleep| sleep.until))
            .fold(f64::INFINITY, f64::min);
        let left = until - world.minutes();
        (left.is_finite() && left > 0.0).then_some(left)
    }

    /// 有人停在等模型上；有人在等时 host 不自动快进。
    pub fn waiting_for_model(&self) -> bool {
        self.state.sessions.values().any(Session::waiting_for_model)
    }

    /// 设定中心改额度：只改额度类字段，并发与上下文窗口沿用当前值。
    pub fn set_agent_limits(&mut self, view: &protocol::AgentLimits) -> Result<(), AgentError> {
        let mut limits = self.state.limits.clone();
        limits.apply(view);
        self.set_limits(limits)
    }

    /// 运行中修改额度并随存档保存；并发上限决定工作线程数，只能重启改。
    fn set_limits(&mut self, limits: Limits) -> Result<(), AgentError> {
        limits.validate().map_err(AgentError::Limits)?;
        if limits.max_concurrent != self.state.limits.max_concurrent {
            return Err(AgentError::Limits(
                "并发上限只能重启后生效，运行中不能修改".into(),
            ));
        }
        if limits.context_tokens != self.state.limits.context_tokens
            || limits.max_output_tokens != self.state.limits.max_output_tokens
        {
            for s in self.state.sessions.values_mut() {
                s.input.ceiling = None;
                s.input.rejections = 0;
                s.forget_known_prefix();
            }
        }
        self.state.limits = limits;
        Ok(())
    }

    /// 故障停止：设原因与类别并记轨迹。全镇随之暂停，用户处理后点开始继续。
    /// 待完成工具每拍都会检查，已经因同一原因停着就不再重复记轨迹。
    pub(crate) fn pause_fault(
        &mut self,
        world: &World,
        s: &mut Session,
        reason: impl Into<String>,
        request: Option<u64>,
    ) {
        self.pause_fault_for(world, s, reason, request, HoldCause::Other);
    }

    /// 带原因类别的故障停止：模型服务的问题按类别给玩家修复按钮。
    pub(crate) fn pause_fault_for(
        &mut self,
        world: &World,
        s: &mut Session,
        reason: impl Into<String>,
        request: Option<u64>,
        cause: HoldCause,
    ) {
        let reason = reason.into();
        if s.pause_kind() == PauseKind::Fault && s.pause_reason() == Some(reason.as_str()) {
            return;
        }
        s.pause_for(PauseKind::Fault, reason.clone(), cause);
        let mut trace = Trace::new("paused", json!({"kind":"fault","reason":reason}));
        if let Some(id) = request {
            trace = trace.request(id);
        }
        self.record(world, s, trace);
    }

    /// 各段换算成 token 估算后记 context_budget 轨迹。
    fn record_context_budget(&mut self, world: &World, s: &Session, usage: ContextUsage) {
        let tokens = |bytes| estimate_tokens(bytes, self.state.bytes_per_token);
        let mut data = json!({
            "kind": usage.kind,
            "system": tokens(usage.system_bytes),
            "tools": tokens(usage.tools_bytes),
            "summary": tokens(usage.summary_bytes),
            "history": tokens(usage.history_bytes),
            "current": tokens(usage.current_bytes),
            "estimated_total": usage.estimated,
            "input_budget": usage.budget,
        });
        if let Some(restart) = usage.restart {
            data["restart"] = json!(restart);
        }
        if let Some(target) = usage.target {
            data["compaction_target"] = json!(target);
        }
        self.record(world, s, Trace::new("context_budget", data));
    }

    pub(crate) fn record(&mut self, world: &World, s: &Session, trace: Trace) {
        self.trace.push(TraceRecord {
            schema_version: 1,
            epoch: self.state.epoch,
            actor_id: s.actor_id.clone(),
            session_id: s.id,
            request_id: trace.request,
            sim_minutes: world.minutes(),
            event: trace.event.into(),
            data: trace.data,
        });
    }
}

/// 村民此刻是否需要一次模型决策：受控、能行动、没有在等世界或模型，且轮到自己说话。
fn wants_request(world: &World, s: &Session) -> bool {
    let Some(a) = world.actor(&s.actor_id) else {
        return false;
    };
    // 带路到了目的地、跟着的人还没到齐时也不算空闲：原地等，同行结束时再想
    let idle = a.plan.is_empty()
        && matches!(
            a.current.kind,
            kernel::world::ActKind::Placeholder {
                cond: kernel::intent::StopCond::Never
            }
        )
        && !world.awaiting_followers(&s.actor_id);
    let responding =
        world.interactions().has_talk_invitation(&s.actor_id) && world.talk_available(&s.actor_id);
    // 交谈的成员和同行里跟着走的人占着活动，只在轮到自己说话时想；带路人边走边说也是轮到才想。
    let turn = world.chat_turn(&s.actor_id);
    a.actions.agent_controlled
        && a.present()
        && a.possession.is_none()
        && !a.needs.incapacitated()
        && ((a.current.action.is_none() && idle) || responding || turn)
        && (a.current.interaction.is_none() || turn)
        && s.in_flight.is_none()
        && !s
            .pending
            .iter()
            .any(crate::session::PendingTool::blocks_request)
        && s.pause_reason().is_none()
}

/// 会话的等待到点了，或等待期间来了该醒的通知；没在等也算到点。
fn due(world: &World, s: &Session) -> bool {
    s.sleep().is_none_or(|sleep| {
        world.minutes() >= sleep.until
            || (sleep.wake_on_notice
                && world
                    .actor(&s.actor_id)
                    .is_some_and(|a| event_arrived(a, sleep.after_cursor, None)))
    })
}

/// 请求开头：system，加上累积摘要（有的话）。生活与交谈轮次共用，是缓存前缀的开始。
fn request_head(system: &Message, s: &Session) -> Vec<Message> {
    let mut messages = vec![system.clone()];
    if !s.folded.compacted.is_empty() {
        messages.push(Message::text(
            Role::User,
            prompts::compacted_summary(&s.folded.compacted),
        ));
    }
    messages
}

/// 生活请求消息的排列：system、累积摘要、会话历史、本轮 user。
fn compose(system: &Message, s: &Session, user: &Message) -> Vec<Message> {
    let mut messages = request_head(system, s);
    messages.extend(s.messages.iter().cloned());
    messages.push(user.clone());
    messages
}

/// 一次请求各段的字节数与估算，记成 context_budget 轨迹。三种轮次共用。
struct ContextUsage {
    kind: RequestKind,
    /// 交谈轮次：这次是否从全量重新开始。
    restart: Option<bool>,
    system_bytes: u64,
    tools_bytes: u64,
    summary_bytes: u64,
    history_bytes: u64,
    current_bytes: u64,
    estimated: u64,
    budget: u64,
    /// 生活轮次的折叠目标。
    target: Option<u64>,
}

/// 请求已确定发出：记下本轮带上的目标、索引、记忆、主题和观察字段，下一轮不再重复。
fn mark_shown(s: &mut Session, body: &Value) {
    for key in SLOW_OBSERVATION_FIELDS {
        if body["observation"].get(key).is_some() {
            let value = observation_field_digest(&body["observation"], key);
            s.shown.observation_digests.insert(key.into(), value);
        }
    }
    if body.get("goals").is_some() {
        s.shown.sent_goals_digest = digest(&[&json!(s.context_goals()).to_string()]);
    }
    if body["memory_files"].get("index").is_some() {
        s.shown.sent_notebook_revision = Some(s.notebook.revision);
    }
    for memory in body["recent_memories"].as_array().into_iter().flatten() {
        if let Some(id) = memory["memory_id"].as_u64() {
            s.shown.shown_memory_ids.insert(id);
        }
    }
    for note in body["memory_files"]["related"]
        .as_array()
        .into_iter()
        .flatten()
    {
        if let (Some(path), Some(revision)) = (note["path"].as_str(), note["revision"].as_u64()) {
            s.shown.shown_notes.insert(format!("{path}@{revision}"));
        }
    }
}
