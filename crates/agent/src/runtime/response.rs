//! 模型回复的处理：结算用量、退回过时回复、执行工具、结束一轮。
//! 待完成工具的结算在 pending.rs，想法记录规则在 thought.rs。
use super::{
    event_arrived, pending::ToolResult, retry, thought::note_thought, RequestKind, RequestStatus,
    ResidentRuntime, Trace, BYTES_PER_TOKEN_RANGE, BYTES_PER_TOKEN_SMOOTHING,
};
use crate::{
    conversation::{Message, ModelError, ModelReply, Role, ToolCall, Usage},
    prompts,
    session::{KnownPrefix, RequestStamp, Session},
    tools::{self, ToolContext, ToolError, ToolErrorKind, ToolName, ToolOutcome},
};
use kernel::World;
use protocol::InteractionCommand;
use serde_json::{json, Value};

/// 整理轮次里回看阅读内容的来回上限；超过就结束这一批，下次再整理。
const READING_DIALOGUE_MAX: usize = 12;

/// host 交回的一次模型回复。
struct ReplyEnvelope {
    actor: String,
    id: u64,
    epoch: u64,
    reply: Result<ModelReply, ModelError>,
    latency_ms: u64,
}

/// 回复对应的那次请求；处理过程中各步共用。
pub(super) struct RepliedRound {
    pub(super) id: u64,
    pub(super) stamp: RequestStamp,
    pub(super) kind: RequestKind,
    /// 发出请求时会话已有的消息数；精确前缀按这个数计。
    sent_messages: usize,
    usage: Option<Usage>,
}
impl RepliedRound {
    pub(super) fn reflecting(&self) -> bool {
        self.kind == RequestKind::Reflection
    }
    /// 生活会话只增不改：这次的 prompt 就是下次请求前缀的精确计数。
    fn known(&self, messages: usize, tokens: u64) -> Option<KnownPrefix> {
        (self.kind == RequestKind::Life && self.usage.is_some()).then_some(KnownPrefix {
            prefix_digest: self.stamp.prefix_digest,
            messages,
            tokens,
        })
    }
}

/// 执行完一轮工具调用的结论。
struct CallsOutcome {
    /// 有调用因请求期间的重要通知被退回。
    outdated: bool,
    /// 工具名列表，写进台账。
    names: String,
}

#[derive(Clone, Copy)]
pub(super) enum OutdatedCause {
    Revision,
    Notice,
}
impl OutdatedCause {
    pub(super) fn as_str(self) -> &'static str {
        match self {
            Self::Revision => "revision",
            Self::Notice => "notice",
        }
    }
}

impl ResidentRuntime {
    /// host 的调用入口，参数与 `ReplyEnvelope` 一一对应。返回是否采纳了这次回复。
    pub fn on_reply(
        &mut self,
        world: &mut World,
        actor: &str,
        id: u64,
        epoch: u64,
        reply: Result<ModelReply, ModelError>,
        latency_ms: u64,
    ) -> bool {
        self.receive(
            world,
            ReplyEnvelope {
                actor: actor.into(),
                id,
                epoch,
                reply,
                latency_ms,
            },
        )
    }

    fn receive(&mut self, world: &mut World, envelope: ReplyEnvelope) -> bool {
        let Some(mut s) = self.state.sessions.remove(&envelope.actor) else {
            return false;
        };
        let adopted = self.settle_reply(world, &mut s, envelope);
        self.state.sessions.insert(s.actor_id.clone(), s);
        adopted
    }

    fn settle_reply(&mut self, world: &mut World, s: &mut Session, env: ReplyEnvelope) -> bool {
        let matching = s.in_flight.as_ref().is_some_and(|f| {
            f.id == env.id && f.epoch == env.epoch && env.epoch == self.state.epoch
        });
        if !matching {
            let trace = Trace::new("stale_reply", json!({"epoch":env.epoch})).request(env.id);
            self.record(world, s, trace);
            return false;
        }
        let stamp = s.in_flight.take().expect("刚检查过在途请求");
        let round = RepliedRound {
            id: env.id,
            kind: stamp.kind,
            stamp,
            sent_messages: s.messages.len(),
            usage: env.reply.as_ref().ok().and_then(|r| r.usage),
        };
        self.settle_usage(world, s, &round, &env);
        if self.reject_outdated(world, s, &round) {
            return false;
        }
        match env.reply.and_then(|r| {
            r.validate()?;
            Ok(r)
        }) {
            Err(error) => self.handle_model_error(world, s, &round, error),
            Ok(reply) => self.adopt_reply(world, s, &round, reply),
        }
        if round.reflecting() {
            self.finish_reflection_round(world, s, &round);
        }
        true
    }

    /// 用真实计量替换预留值、校准字节系数，并把回复写进台账与轨迹。
    fn settle_usage(
        &mut self,
        world: &World,
        s: &mut Session,
        round: &RepliedRound,
        env: &ReplyEnvelope,
    ) {
        let stamp = &round.stamp;
        if let Some(usage) = &round.usage {
            self.state.lifetime.reconcile(stamp.reserved_tokens, usage);
            if s.daily.day == stamp.day {
                s.daily.reconcile(stamp.reserved_tokens, usage);
            }
            if usage.input_tokens > 0 && stamp.sent_bytes > 0 {
                let ratio = stamp.sent_bytes as f64 / usage.input_tokens as f64;
                let smoothed = (1.0 - BYTES_PER_TOKEN_SMOOTHING) * self.state.bytes_per_token
                    + BYTES_PER_TOKEN_SMOOTHING * ratio;
                self.state.bytes_per_token =
                    smoothed.clamp(*BYTES_PER_TOKEN_RANGE.start(), *BYTES_PER_TOKEN_RANGE.end());
            }
        }
        self.ledger_reply(round.id, env.latency_ms, round.usage.as_ref());
        let data = json!({
            "reply": env.reply,
            "latency_ms": env.latency_ms,
            "observed_at": stamp.sim_minutes,
            "adopted_at": world.minutes(),
            "sim_delay": world.minutes() - stamp.sim_minutes,
            "reserved_tokens": stamp.reserved_tokens,
            "usage": round.usage,
            "actual_tokens": round.usage.map(|u| u.total()),
            "sent_bytes": stamp.sent_bytes,
            "bytes_per_token": self.state.bytes_per_token
        });
        self.record(world, s, Trace::new("response", data).request(round.id));
    }

    /// 请求期间外部改了安排、村民失去受控或无法行动：整条回复作废。
    fn reject_outdated(&mut self, world: &World, s: &mut Session, round: &RepliedRound) -> bool {
        let current = world.actor(&s.actor_id).is_some_and(|a| {
            a.actions.revision == round.stamp.revision
                && a.actions.agent_controlled
                && !a.needs.incapacitated()
        });
        if current {
            return false;
        }
        let input = round.usage.map_or(0, |u| u.input_tokens);
        if let Some(prefix) = round.known(round.sent_messages, input) {
            s.remember_known_prefix(prefix);
        }
        if round.kind == RequestKind::Life {
            s.messages
                .push(Message::text(Role::User, prompts::OUTDATED_BY_REVISION));
        }
        if !round.reflecting() {
            self.note_outdated(world, s, round, OutdatedCause::Revision);
        }
        self.ledger_close(
            round.id,
            RequestStatus::Outdated,
            "外部安排已改变，回复未执行",
        );
        s.restart_wake_count();
        s.notebook.request = None;
        true
    }

    /// 整理轮次的失败只走笔记退避；生活与交谈轮次按 retry 模块的规则有界重试，用完交给用户处理。
    fn handle_model_error(
        &mut self,
        world: &mut World,
        s: &mut Session,
        round: &RepliedRound,
        failure: ModelError,
    ) {
        let error = failure.to_string();
        self.ledger_close(round.id, RequestStatus::Failed, error.clone());
        if matches!(failure, ModelError::ContextWindowExceeded { .. }) {
            self.recover_context_error(world, s, round);
            if round.reflecting() {
                s.notebook.reading_dialogue.clear();
            }
            return;
        }
        if round.reflecting() {
            let trace = Trace::new("reflection_failed", json!({"error":error})).request(round.id);
            self.record(world, s, trace);
            return;
        }
        if round.kind == RequestKind::Life {
            s.messages
                .push(Message::text(Role::User, prompts::model_failed(&error)));
        }
        self.note_model_failure(world, s, round, &failure);
    }

    /// 回复有效：记录自述与调用，执行工具，然后结束这一轮。
    fn adopt_reply(
        &mut self,
        world: &mut World,
        s: &mut Session,
        round: &RepliedRound,
        reply: ModelReply,
    ) {
        s.streaks.model_failures = 0;
        s.input.rejections = 0;
        let format_retry = match round.kind {
            RequestKind::Life => s.is_format_retry(&reply),
            RequestKind::Chat => s.chat.attempts > 0,
            RequestKind::Reflection => false,
        };
        let assistant = Message {
            role: Role::Assistant,
            content: reply.thought.clone(),
            calls: reply.calls.clone(),
            call_id: None,
        };
        match round.kind {
            RequestKind::Reflection => s.notebook.reading_dialogue.push(assistant),
            RequestKind::Chat => {
                s.chat.commit();
                s.chat.messages.push(assistant);
            }
            RequestKind::Life => {
                s.cursors.acknowledged = s.cursors.acknowledged.max(round.stamp.seen_cursor);
                s.messages.push(assistant);
                let total = round.usage.map_or(0, |u| u.total());
                if let Some(prefix) = round.known(round.sent_messages + 1, total) {
                    s.remember_known_prefix(prefix);
                }
            }
        }
        if !format_retry {
            note_thought(world, &s.actor_id, round.kind, &reply);
        }
        if reply.calls.is_empty() {
            self.listen_silently(world, s, round);
        }
        let outcome = self.execute_calls(world, s, round, reply.calls);
        let status = if outcome.outdated {
            RequestStatus::Outdated
        } else if format_retry {
            RequestStatus::FormatRetry
        } else {
            RequestStatus::Adopted
        };
        let detail = if outcome.outdated {
            format!("请求期间收到重要通知；{}", outcome.names)
        } else {
            outcome.names
        };
        self.ledger_close(round.id, status, detail);
        match round.kind {
            RequestKind::Life => self.finish_life_round(world, s, round, outcome.outdated),
            RequestKind::Chat => self.finish_chat_round(world, s, round, outcome.outdated),
            RequestKind::Reflection => {}
        }
    }

    /// 轮到自己说话却没有任何调用：视为倾听，把轮次交给其他参与者。
    pub(super) fn listen_silently(&mut self, world: &mut World, s: &Session, round: &RepliedRound) {
        if !world.chat_turn(&s.actor_id) {
            return;
        }
        let Some(chat) = world.active_chat(&s.actor_id) else {
            return;
        };
        let command = InteractionCommand::Listen {
            interaction_id: chat.id.clone(),
        };
        let listened = world.interact(&s.actor_id, "silent-turn", round.stamp.revision, &command);
        let data = match listened {
            Ok(_) => json!({"reason":"本轮未发言，继续倾听"}),
            Err(error) => json!({"reason":"本轮未发言，倾听失败","error":error.to_string()}),
        };
        self.record(world, s, Trace::new("chat_listen", data).request(round.id));
    }

    /// 逐个执行调用；整理轮次只允许整理工具，收到重要通知后改变世界的调用退回。
    fn execute_calls(
        &mut self,
        world: &mut World,
        s: &mut Session,
        round: &RepliedRound,
        calls: Vec<ToolCall>,
    ) -> CallsOutcome {
        let important_new = world
            .actor(&s.actor_id)
            .is_some_and(|a| event_arrived(a, round.stamp.seen_cursor, None));
        let names = if calls.is_empty() {
            "没有工具调用".to_string()
        } else {
            calls
                .iter()
                .map(|c| c.name.as_str())
                .collect::<Vec<_>>()
                .join("、")
        };
        let mut outdated = false;
        let mut retry_tools = std::collections::BTreeSet::new();
        for (index, call) in calls.iter().enumerate() {
            self.record(
                world,
                s,
                Trace::new("tool_call", json!(call)).request(round.id),
            );
            let name = call.name.parse::<ToolName>().ok();
            let outcome = match screen(round.kind, name, important_new) {
                Some(error) => {
                    outdated |= error.kind == ToolErrorKind::Outdated;
                    Err(error)
                }
                None => self.run_tool(world, s, round.id, index, call),
            };
            let value = match outcome {
                Ok(ToolOutcome::Complete(value)) => json!({"ok":true,"result":value}),
                Ok(ToolOutcome::Pending(pending)) => {
                    s.pending.push(pending);
                    continue;
                }
                Err(error) => {
                    let format = error.kind == ToolErrorKind::InvalidArguments;
                    if format || name.is_some_and(ToolName::is_lookup) {
                        retry_tools.insert(call.name.clone());
                    }
                    if !round.reflecting() && error.kind != ToolErrorKind::Outdated {
                        if format && name == Some(ToolName::ReplyInvitation) {
                            self.note_failure(world, s, "reply_invitation", "回应邀请参数格式错误");
                        } else {
                            let problem = format!("{}:{}", call.name, call.arguments);
                            self.note_failure(world, s, &problem, &error.message);
                        }
                    }
                    error.result()
                }
            };
            let result = ToolResult {
                call,
                value,
                kind: round.kind,
            };
            self.complete_tool(world, s, result);
        }
        if round.kind == RequestKind::Life {
            s.remember_retry_tools(retry_tools);
        }
        CallsOutcome { outdated, names }
    }

    fn run_tool(
        &mut self,
        world: &mut World,
        s: &mut Session,
        request: u64,
        call_index: usize,
        call: &ToolCall,
    ) -> Result<ToolOutcome, ToolError> {
        let documents = self.documents.entry(s.actor_id.clone()).or_default();
        let mut ctx = ToolContext {
            world,
            session: s,
            index: &mut self.index,
            documents,
            request,
            call_index,
        };
        tools::execute(&mut ctx, call)
    }

    /// 生活轮次收尾：计数过时或采纳；没有调用就是本次思考结束，搁置到有新情况。
    fn finish_life_round(
        &mut self,
        world: &World,
        s: &mut Session,
        round: &RepliedRound,
        outdated: bool,
    ) {
        if outdated {
            self.note_outdated(world, s, round, OutdatedCause::Notice);
        } else {
            s.tally.replies = s.tally.replies.saturating_add(1);
            s.streaks.stale_streak = 0;
        }
        let thinking_done = s
            .messages
            .last()
            .is_some_and(|m| m.role == Role::Assistant && m.calls.is_empty());
        if !thinking_done {
            return;
        }
        let delivered = s.cursors.delivered;
        retry::postpone(
            s,
            world.minutes(),
            "本次思考结束，等待新情况",
            true,
            delivered,
        );
        s.memory.consolidate(world, &s.actor_id);
    }

    /// 整理轮次收尾：刚回看了阅读内容，或这一轮只调了回看工具（回看出错也算），就继续这一批，
    /// 让模型看到结果或错误后再交 reflect；否则批次结束，失败按指数退避。
    /// 海难环岛里两人都拿 read_content 查聊天，报错后整批推迟了两小时。
    fn finish_reflection_round(&mut self, world: &World, s: &mut Session, round: &RepliedRound) {
        let dialogue = &s.notebook.reading_dialogue;
        let read_something = dialogue.last().is_some_and(|m| {
            m.role == Role::Tool
                && serde_json::from_str::<Value>(&m.content).is_ok_and(|v| {
                    v["ok"] == true
                        && (v["result"].get("reading_result").is_some()
                            || v["result"].get("context_source").is_some()
                            || v["result"].get("source").is_some())
                })
        });
        let only_looked = dialogue
            .iter()
            .rev()
            .find(|m| m.role == Role::Assistant)
            .is_some_and(|m| {
                !m.calls.is_empty()
                    && m.calls.iter().all(|c| {
                        matches!(
                            c.name.parse(),
                            Ok(ToolName::ReadContent | ToolName::ContextRead)
                        )
                    })
            });
        let continue_reading =
            (read_something || only_looked) && dialogue.len() <= READING_DIALOGUE_MAX;
        if continue_reading || s.notebook.request.take().is_none() {
            return;
        }
        let book = &mut s.notebook;
        book.reading_dialogue.clear();
        book.failures = book.failures.saturating_add(1);
        book.retry_after = retry::reflection_retry_after(world.minutes(), book.failures);
        let data = json!({
            "retry_after": book.retry_after,
            "through_event": book.through_event
        });
        self.record(
            world,
            s,
            Trace::new("reflection_deferred", data).request(round.id),
        );
    }
}

/// 执行前退回的调用：本轮次不开放的工具，以及收到重要通知后改变世界的调用。
/// 未知工具名不在这里处理，交给执行入口报错。
fn screen(kind: RequestKind, name: Option<ToolName>, important_new: bool) -> Option<ToolError> {
    if name.is_some_and(|n| !n.allowed_in(kind)) {
        let rule = match kind {
            RequestKind::Reflection => prompts::REFLECTION_TOOLS_ONLY,
            RequestKind::Chat => prompts::CHAT_TOOLS_ONLY,
            RequestKind::Life => prompts::LIFE_TOOLS_ONLY,
        };
        return Some(ToolError::new(ToolErrorKind::NotAllowed, rule));
    }
    (important_new && name.is_some_and(ToolName::changes_world))
        .then(|| ToolError::new(ToolErrorKind::Outdated, prompts::STALE_AFTER_NOTICE))
}
