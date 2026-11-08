//! 生活轮次的请求组装与预算压缩。平时保持增量历史与稳定前缀。
use super::*;
use crate::context::{self, view};

/// 生活观察进上下文的字节上限；放不下时对半减，不低于下限。
const OBSERVATION_BYTES: usize = 16_000;
const OBSERVATION_BYTES_MIN: usize = 4_000;
/// 折叠线：估算超过额度里的 compact_at_tokens 与输入额度的这个比例（取小）就折叠。
const COMPACT_TRIGGER: (u64, u64) = (9, 10);
/// 折叠目标：折叠后降到折叠线的这个比例以下。留出约四轮的余量；留得多，几轮后就又要折叠，
/// 而每次折叠都让摘要之后的前缀重新计费。
const COMPACT_TARGET: (u64, u64) = (5, 8);
/// 新一次醒来时估算已超过折叠线的这个比例，就趁此折叠。
const EARLY_FOLD: (u64, u64) = (5, 6);

fn part(value: u64, (numerator, denominator): (u64, u64)) -> u64 {
    value * numerator / denominator
}

/// 一次生活请求的几条线（token）：可用输入额度、折叠线、折叠目标、醒来时提前折叠的线。
struct FoldLines {
    budget: u64,
    trigger: u64,
    target: u64,
    early: u64,
}
impl FoldLines {
    fn new(budget: u64, compact_at: u64) -> Self {
        let trigger = compact_at.min(part(budget, COMPACT_TRIGGER));
        Self {
            budget,
            trigger,
            target: part(trigger, COMPACT_TARGET),
            early: part(trigger, EARLY_FOLD),
        }
    }
}

/// 试组的一次生活请求：本轮 user 消息（连同 JSON 正文）、完整消息、前缀哈希、
/// 送出到的事件游标与估算 token。
struct Attempt {
    user: (Message, Value),
    messages: Vec<Message>,
    prefix_digest: u64,
    cursor: u64,
    estimated: u64,
}

/// 缩减过程的状态：是否在折叠、折叠时保留几轮原文、观察的字节上限。
struct Fitting {
    wake_start: bool,
    folding_at_wake: bool,
    compacting: bool,
    keep: usize,
    observation_bytes: usize,
}
impl Fitting {
    /// 上下文被服务商连续拒收达到次数时，一开始就全部折叠。
    fn new(s: &Session, keep_recent_rounds: usize) -> Self {
        let full_fold = s.input.rejections >= retry::CONTEXT_REJECTIONS_BEFORE_FULL_FOLD;
        Self {
            // 新一次醒来时已接近折叠线，就趁上一件事刚结束折叠，原文一轮不留，靠摘要、目标和观察接上：
            // 不打断正在做的事，折叠后重新计费的只有新摘要和本轮观察。
            wake_start: s.wake_calls() == 0 && !s.messages.is_empty(),
            folding_at_wake: false,
            compacting: full_fold,
            keep: if full_fold { 0 } else { keep_recent_rounds },
            observation_bytes: OBSERVATION_BYTES,
        }
    }
}

impl ResidentRuntime {
    pub(super) fn input_budget(&self, s: &Session) -> u64 {
        let configured = self.state.limits.input_budget();
        s.input.ceiling.unwrap_or(configured).min(configured)
    }

    pub(super) fn validate_instructions(
        &self,
        world: &World,
        actor: &str,
        instructions: &str,
    ) -> Result<(), AgentError> {
        let mut candidate = Session::new(0, actor, instructions);
        let system = self.system_message(world, &mut candidate)?;
        let (raw, _) =
            observation::observe(world, actor, resident(world, actor)?.journal.cursor())?;
        let (current, _) = view::observation(&mut candidate, &raw, 8_000);
        let messages = [system, Message::text(Role::User, current.to_string())];
        let bytes = wire_bytes(&messages)
            + json!(tools::definitions(RequestKind::Life))
                .to_string()
                .len() as u64;
        if estimate_tokens(bytes, self.state.bytes_per_token)
            > self.state.limits.input_budget() * 3 / 4
        {
            return Err(AgentError::Instructions(
                "人设、核心规则与当前状态放不进模型窗口，请缩短设定或配置更大的模型窗口".into(),
            ));
        }
        Ok(())
    }

    /// 生活轮次的请求：先确定有界的新输入，再按实际预算归档完整轮次；必要时可归档全部旧轮次。
    /// 每次放不下就按 `shrink_context` 的顺序缩减一步再试。
    pub(super) fn fit_context(
        &mut self,
        world: &World,
        s: &mut Session,
        raw: &Value,
        tools_json: &str,
    ) -> Result<Draft, AgentError> {
        if !context::paired(&s.messages) {
            return Err(AgentError::Context(
                "会话存在未配对的工具调用，暂停请求".into(),
            ));
        }
        let system = self.system_message(world, s)?;
        let lines = FoldLines::new(self.input_budget(s), self.state.limits.compact_at_tokens);
        let mut fit = Fitting::new(s, self.state.limits.keep_recent_rounds);
        let tools_bytes = tools_json.len() as u64;
        loop {
            let attempt =
                self.attempt(world, s, raw, &system, tools_json, fit.observation_bytes)?;
            let estimated = attempt.estimated;
            if fit.wake_start && !fit.compacting && estimated > lines.early {
                fit.folding_at_wake = true;
                fit.compacting = true;
                fit.keep = 0;
            }
            fit.compacting |= estimated > lines.trigger;
            let goal = if fit.compacting {
                lines.target
            } else {
                lines.trigger
            };
            if estimated <= goal || (s.messages.is_empty() && estimated <= lines.budget) {
                self.record_context_budget(
                    world,
                    s,
                    ContextUsage {
                        kind: RequestKind::Life,
                        restart: None,
                        system_bytes: wire_bytes(std::slice::from_ref(&system)),
                        tools_bytes,
                        summary_bytes: s.folded.compacted.len() as u64,
                        history_bytes: wire_bytes(&s.messages),
                        current_bytes: wire_bytes(std::slice::from_ref(&attempt.user.0)),
                        estimated,
                        budget: lines.budget,
                        target: Some(lines.target),
                    },
                );
                return Ok(Draft {
                    sent_bytes: wire_bytes(&attempt.messages) + tools_bytes,
                    messages: attempt.messages,
                    estimated,
                    prefix_digest: attempt.prefix_digest,
                    seen: attempt.cursor,
                    user: Some(attempt.user),
                    chat: None,
                });
            }
            let fixed = wire_bytes(std::slice::from_ref(&system))
                + tools_bytes
                + context::summary_bytes_after_fold(s.folded.compacted.len())
                + wire_bytes(std::slice::from_ref(&attempt.user.0));
            let room = goal.saturating_sub(estimate_tokens(fixed, self.state.bytes_per_token));
            if !self.shrink_context(world, s, &mut fit, room, estimated)? {
                return Err(AgentError::Context(format!("最小必要上下文仍需约 {estimated} token，可用输入额度 {}；请检查模型窗口与居民设定，当前事务和原文已保留", lines.budget)));
            }
        }
    }

    /// 按当前的观察上限组一次请求并估算；前缀一变，上一次的精确计数作废。
    fn attempt(
        &mut self,
        world: &World,
        s: &mut Session,
        raw: &Value,
        system: &Message,
        tools_json: &str,
        observation_bytes: usize,
    ) -> Result<Attempt, AgentError> {
        let (observation, cursor) = view::observation(s, raw, observation_bytes);
        let user = self.user_message(world, s, &observation)?;
        let prefix_digest = digest(&[&system.content, tools_json, &s.folded.compacted]);
        if s.known_prefix()
            .is_some_and(|k| k.prefix_digest != prefix_digest)
        {
            s.forget_known_prefix();
        }
        let messages = context::clean::messages(&compose(system, s, &user.0));
        let tools_bytes = tools_json.len() as u64;
        let estimated = self.estimate_request(s, prefix_digest, tools_bytes, &messages);
        Ok(Attempt {
            user,
            messages,
            prefix_digest,
            cursor,
            estimated,
        })
    }

    /// 放不下时缩减一步，按顺序：折叠旧轮次（按剩余空间一次算出能留几轮）、少留一轮原文、
    /// 观察减半（不低于下限）、把累积摘要归档成来源。返回 false 表示已经无可再减。
    fn shrink_context(
        &mut self,
        world: &World,
        s: &mut Session,
        fit: &mut Fitting,
        room: u64,
        estimated: u64,
    ) -> Result<bool, AgentError> {
        if fit.keep > 0 {
            // 一次算出能保留的轮数，只折叠一次、只追加一段摘要；估算偏差由下一次循环兜底。
            let bytes = (room as f64 * self.state.bytes_per_token) as u64;
            fit.keep = context::rounds_within(&s.messages, fit.keep, bytes);
        }
        if context::compact(s, fit.keep).map_err(AgentError::Context)? {
            let event = if fit.keep == 0 && !fit.folding_at_wake {
                "context_rebuilt"
            } else {
                "compacted"
            };
            let data = json!({"compactions":s.folded.compactions,"kept_rounds":fit.keep,"at_wake_start":fit.folding_at_wake,"estimated_tokens":estimated,"input_budget":self.input_budget(s)});
            self.record(world, s, Trace::new(event, data));
            return Ok(true);
        }
        if fit.keep > 0 {
            fit.keep -= 1;
            return Ok(true);
        }
        if fit.observation_bytes > OBSERVATION_BYTES_MIN {
            fit.observation_bytes /= 2;
            return Ok(true);
        }
        // 摘要是历史的有损视图；当前事务来自内核和独立目标，不能用摘要替代。
        if !s.folded.compacted.is_empty() {
            let source = s.input.source(&json!(s.folded.compacted));
            s.input.summary_source = Some(source);
            s.folded.compacted.clear();
            s.forget_shown();
            self.record(
                world,
                s,
                Trace::new("context_summary_archived", json!({"context_source":source})),
            );
            return Ok(true);
        }
        Ok(false)
    }

    fn system_message(&self, world: &World, s: &mut Session) -> Result<Message, AgentError> {
        let mut map = observation::static_map(world, &s.actor_id)?;
        view::field(&mut s.input, &mut map, "known_places", 4_000);
        context::clean::clean(&mut map);
        Ok(Message::text(
            Role::System,
            prompts::system_prompt(
                &s.instructions,
                &map.to_string(),
                self.state.limits.calls_per_wake,
            ),
        ))
    }

    /// 本轮 user 消息：观察必带，慢变字段没变时省略；目标、记忆索引、自动记忆与
    /// 相关主题只在有变化或未展示过时附带。同时返回 JSON 正文，请求确定发出后据此登记已展示的内容。
    fn user_message(
        &mut self,
        world: &World,
        s: &mut Session,
        observation: &Value,
    ) -> Result<(Message, Value), AgentError> {
        let mut body = serde_json::Map::new();
        body.insert(
            "observation".into(),
            omit_unchanged(s, &view::slim(observation)),
        );
        if let Some(source) = s.input.summary_source {
            body.insert("earlier_summary".into(), json!({"context_source":source}));
        }
        if !s.pending.is_empty() {
            // 已报告仍在执行的动作允许接收邀请；重建后仍须知道它尚未完成。
            // 调用编号和动作组编号只给程序配对回执，不写进题面。
            let pending: Vec<_> = s
                .pending
                .iter()
                .map(|p| match p {
                    crate::session::PendingTool::Actions { .. } => json!({"kind":"actions"}),
                    crate::session::PendingTool::Interaction { interaction_id, .. } => {
                        json!({"kind":"interaction","interaction_id":interaction_id})
                    }
                    crate::session::PendingTool::Wait { until, .. } => {
                        json!({"kind":"wait","until":until})
                    }
                })
                .collect();
            body.insert("pending_operations".into(), json!(pending));
        }
        let goals = json!(s.context_goals());
        if digest(&[&goals.to_string()]) != s.shown.sent_goals_digest {
            body.insert("goals".into(), view::goals(s));
        }
        let focus = relevance::Focus::of_observation(s, observation);
        let memories = self.context_memories(s, &focus)?;
        if !memories.is_empty() {
            body.insert("recent_memories".into(), json!(memories));
        }
        let mut files = serde_json::Map::new();
        if s.shown.sent_notebook_revision != Some(s.notebook.revision) {
            let docs = self.docs(world, s);
            files.insert("index".into(), json!(docs.get("INDEX.md")));
            files.insert("self".into(), json!(docs.get("self.md")));
        }
        let related = relevance::related_notes(world, s, &focus, true);
        if !related.is_empty() {
            files.insert("related".into(), json!(related));
        }
        if !files.is_empty() {
            body.insert("memory_files".into(), Value::Object(files));
        }
        let mut body = Value::Object(body);
        for key in ["recent_memories", "memory_files"] {
            view::field(&mut s.input, &mut body, key, 4_000);
        }
        Ok((Message::text(Role::User, body.to_string()), body))
    }

    /// 有精确前缀时只估算新增部分；否则整个请求按系数估算。
    /// 请求消息排列为 system、累积摘要、会话历史、本轮 user；前缀覆盖到历史的前若干条。
    fn estimate_request(
        &self,
        s: &Session,
        prefix_digest: u64,
        tools_bytes: u64,
        messages: &[Message],
    ) -> u64 {
        let ratio = self.state.bytes_per_token;
        if let Some(known) = s.known_prefix() {
            let head = messages.len().saturating_sub(s.messages.len() + 1);
            if known.prefix_digest == prefix_digest && known.messages <= s.messages.len() {
                let tail = &messages[head + known.messages..];
                return known.tokens + estimate_tokens(wire_bytes(tail), ratio);
            }
        }
        estimate_tokens(wire_bytes(messages) + tools_bytes, ratio)
    }
}

/// 慢变字段和本段会话上次发出的相同时省略，来源引用一并省略；和交谈轮次一样只发变化。
fn omit_unchanged(s: &Session, observation: &Value) -> Value {
    let mut view = observation.clone();
    for key in super::SLOW_OBSERVATION_FIELDS {
        let unchanged = s.shown.observation_digests.get(key)
            == Some(&super::observation_field_digest(observation, key));
        if let (true, Some(object)) = (unchanged, view.as_object_mut()) {
            object.remove(key);
            object.remove(&format!("{key}_source"));
        }
    }
    view
}
