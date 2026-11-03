//! 交谈轮次：轮到本人发言时的单次请求。只带聊天规则、人设、累积摘要和本场对话，
//! 不带地图、道具、记忆工具和生活会话历史；台词本身仍作为事件进入之后的生活轮次。
//! 本场对话只在末尾追加：第一轮带全量状态，之后只加新听到的台词和有变化的状态，
//! 本人说过的话留在自己的调用里。每轮请求都以上一轮为前缀，能命中缓存。
use super::*;
use crate::context::view;
use crate::session::{ChatDelta, ChatSeen};
use protocol::{ChatEntry, ChatEntryKind};

/// 全量里台词的字节上限；放不下时对半减到这个下限。
const ENTRIES_BYTES: usize = 6_000;
const ENTRIES_BYTES_MIN: usize = 500;
/// 交谈期间的重要通知最多带几条。
const NOTICES_MAX: usize = 6;
/// 属于本场对话的字段：有变化时放进 chat 里重发，不放在顶层。等人回答的提议没有时为 null，
/// 交谈变成同行时 kind 跟着变。
const CHAT_FIELDS: [&str; 3] = ["members", "proposal", "kind"];
/// 对话记录超过这个字节数就从全量重新开始：交谈再长，请求也有上限。
const TRANSCRIPT_BYTES: u64 = 16_000;

impl ResidentRuntime {
    /// system 与摘要在整场交谈里不变；本场对话按追加排列，放不下时从全量重新开始。
    pub(super) fn chat_draft(
        &mut self,
        world: &World,
        s: &mut Session,
        tools_json: &str,
    ) -> Result<Draft, AgentError> {
        let (raw, _) = observation::observe(world, &s.actor_id, s.cursors.acknowledged)?;
        let system = Message::text(Role::System, prompts::chat_system_prompt(&s.instructions));
        let budget = self.input_budget(s);
        let ratio = self.state.bytes_per_token;
        let chat = world.active_chat(&s.actor_id);
        let chat_id = chat.map_or(String::new(), |c| c.id.clone());
        let mut restart = s.chat.chat_id != chat_id
            || s.chat.messages.is_empty()
            || wire_bytes(&s.chat.messages) > TRANSCRIPT_BYTES;
        let mut entries_bytes = ENTRIES_BYTES;
        loop {
            let state = TurnState::read(world, s, &raw)?;
            let delta = if restart {
                state.full(s, &chat_id, entries_bytes)
            } else {
                state.update(s, &chat_id)
            };
            let mut messages = request_head(&system, s);
            if !delta.restart {
                messages.extend(s.chat.messages.iter().cloned());
            }
            messages.extend(delta.message.clone());
            let sent_bytes = wire_bytes(&messages) + tools_json.len() as u64;
            let estimated = estimate_tokens(sent_bytes, ratio);
            if estimated <= budget || (restart && entries_bytes <= ENTRIES_BYTES_MIN) {
                let usage = ContextUsage {
                    kind: RequestKind::Chat,
                    restart: Some(restart),
                    system_bytes: wire_bytes(&messages[..1]),
                    tools_bytes: tools_json.len() as u64,
                    summary_bytes: s.folded.compacted.len() as u64,
                    history_bytes: if restart {
                        0
                    } else {
                        wire_bytes(&s.chat.messages)
                    },
                    current_bytes: delta.message.as_ref().map_or(0, |m| m.content.len() as u64),
                    estimated,
                    budget,
                    target: None,
                };
                self.record_context_budget(world, s, usage);
                return Ok(Draft {
                    estimated,
                    messages,
                    sent_bytes,
                    prefix_digest: 0,
                    // 过时判断以发出时的全部事件为准；观察游标不动，台词留给生活轮次。
                    seen: resident(world, &s.actor_id)?.journal.cursor(),
                    user: None,
                    chat: Some(delta),
                });
            }
            if restart {
                entries_bytes /= 2;
            }
            restart = true;
        }
    }

    /// 交谈轮次收尾：发言权交出去了就重新计数；没交出去按 retry 模块的次数重试，用满就代为倾听。
    pub(super) fn finish_chat_round(
        &mut self,
        world: &mut World,
        s: &mut Session,
        round: &response::RepliedRound,
        outdated: bool,
    ) {
        if outdated {
            self.note_outdated(world, s, round, response::OutdatedCause::Notice);
        } else {
            s.tally.replies = s.tally.replies.saturating_add(1);
            s.streaks.stale_streak = 0;
        }
        self.spend_chat_attempt(world, s, round);
    }
}

/// 交谈轮次能看到的状态：本人、在场的人、本场对话、交谈期间的通知与当前目标。
struct TurnState {
    clock: Value,
    /// 只在变化时重发的字段，按名字排列。
    fields: Vec<(&'static str, Value)>,
    /// 本场对话的观察，含台词、轮次、已聊时长与句数。
    chat: Value,
    /// 本人听得到的全部台词。
    entries: Vec<ChatEntry>,
    notices: Vec<Value>,
}

impl TurnState {
    fn read(world: &World, s: &Session, raw: &Value) -> Result<Self, AgentError> {
        let actor = resident(world, &s.actor_id)?;
        let item = world.active_chat(&s.actor_id);
        let chat = match item {
            Some(item) => {
                let mut view = crate::interaction::observation(world, &s.actor_id, item);
                // 聊了多久、多少句，让模型自己判断该不该收尾。
                let since = item.started_at.unwrap_or(item.created_at);
                view["elapsed_minutes"] = json!((world.minutes() - since).round());
                view["lines"] = json!(item.chat.as_ref().map_or(0, |c| c.entries.len()));
                view
            }
            None => Value::Null,
        };
        let entries = item
            .and_then(|i| i.chat.as_ref())
            .map(|c| {
                c.entries
                    .iter()
                    .filter(|e| e.audience.contains(&s.actor_id))
                    .cloned()
                    .collect()
            })
            .unwrap_or_default();
        let mut notices: Vec<_> = actor
            .journal
            .events_after(s.cursors.acknowledged)
            .iter()
            .filter(|e| e.kind == FactKind::Notice)
            .map(|e| json!({"event_id":e.event_id,"at":e.at,"text":e.text}))
            .collect();
        notices.drain(..notices.len().saturating_sub(NOTICES_MAX));
        let people: Vec<_> = raw["people_here"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|p| json!({"id":p["id"],"name":p["name"]}))
            .collect();
        let goals: Vec<_> = s
            .goals
            .values()
            .filter(|g| g.status.is_open())
            .map(|g| {
                let mut goal = json!({"id":g.id,"title":g.title,"commitment":g.commitment,"next_step":g.next_steps.first()});
                if let Some(due) = &g.due_clock {
                    goal["due_clock"] = json!(due);
                }
                goal
            })
            .collect();
        let slim = view::slim(raw);
        // 提议一起去某处时要写地点编号；交谈轮次不带地图，只列名字和编号。
        let places: Vec<_> = world
            .topo
            .places
            .iter()
            .map(|p| json!({"id":p.locale,"name":p.name}))
            .collect();
        Ok(Self {
            clock: raw["clock"].clone(),
            fields: vec![
                ("identity", json!({"id": actor.id, "name": actor.name})),
                ("places", json!(places)),
                ("location", raw["location"].clone()),
                ("needs", slim["needs"].clone()),
                (
                    "body",
                    json!({"limitation": raw["body"]["limitation"], "conditions": raw["body"]["conditions"]}),
                ),
                (
                    "environment",
                    json!({"weather": raw["environment"]["weather"]["kind"], "activity": raw["environment"]["activity"]}),
                ),
                ("people_here", json!(people)),
                ("members", chat["members"].clone()),
                ("proposal", chat["proposal"].clone()),
                ("kind", chat["kind"].clone()),
                ("goals", json!(goals)),
            ],
            chat,
            entries,
            notices,
        })
    }

    /// 发过之后据以判断「有没有变化」的摘要值。需求只看档位，数值每分钟都在变。
    fn digests(&self) -> BTreeMap<String, u64> {
        self.fields
            .iter()
            .map(|(key, value)| {
                let basis = if *key == "needs" {
                    json!(value
                        .as_array()
                        .into_iter()
                        .flatten()
                        .map(|n| json!([n["need"], n["band"]]))
                        .collect::<Vec<_>>())
                } else {
                    value.clone()
                };
                (key.to_string(), digest(&[&basis.to_string()]))
            })
            .collect()
    }

    fn seen(&self, s: &Session) -> ChatSeen {
        ChatSeen {
            seq: self.entries.last().map_or(s.chat.seen.seq, |e| e.seq),
            notice: self
                .notices
                .last()
                .and_then(|n| n["event_id"].as_u64())
                .unwrap_or(s.chat.seen.notice),
            digests: self.digests(),
        }
    }

    /// 新记录的第一条：全部状态、本场对话（台词过长时只留最近的）、通知与目标。
    fn full(&self, s: &mut Session, chat_id: &str, entries_bytes: usize) -> ChatDelta {
        let mut chat = self.chat.clone();
        if let Some(entries) = chat.get_mut("entries").and_then(Value::as_array_mut) {
            // 记录可能在交谈中途重建，较早的台词要带上说话时刻，“明天”才不会按现在算。
            for entry in entries.iter_mut() {
                let at = entry["at"].as_f64();
                *entry = compact_entry(entry);
                if let Some(at) = at {
                    entry["clock"] = json!(kernel::clock_string(at));
                }
            }
        }
        view::recent_field(&mut s.input, &mut chat, "entries", entries_bytes);
        let mut body = serde_json::Map::new();
        body.insert("clock".into(), self.clock.clone());
        for (key, value) in &self.fields {
            if !CHAT_FIELDS.contains(key) {
                body.insert((*key).into(), value.clone());
            }
        }
        body.insert("chat".into(), chat);
        body.insert("notices".into(), json!(self.notices));
        ChatDelta {
            chat_id: chat_id.into(),
            restart: true,
            message: Some(Message::text(Role::User, Value::Object(body).to_string())),
            seen: self.seen(s),
        }
    }

    /// 接在记录末尾的变化：上次之后别人说的话、新通知、变了的状态。同一次轮到本人时的重试，
    /// 没有新内容就不加消息，模型直接看到上一次调用的结果。
    fn update(&self, s: &Session, chat_id: &str) -> ChatDelta {
        let seen = &s.chat.seen;
        let new_entries: Vec<_> = self
            .entries
            .iter()
            .filter(|e| e.seq > seen.seq && e.actor != s.actor_id)
            .map(|e| compact_entry(&json!(e)))
            .collect();
        let notices: Vec<_> = self
            .notices
            .iter()
            .filter(|n| n["event_id"].as_u64().is_some_and(|id| id > seen.notice))
            .cloned()
            .collect();
        let digests = self.digests();
        let changed: Vec<_> = self
            .fields
            .iter()
            .filter(|(key, _)| seen.digests.get(*key) != digests.get(*key))
            .collect();
        let message = if new_entries.is_empty()
            && notices.is_empty()
            && changed.is_empty()
            && s.chat.attempts > 0
        {
            None
        } else {
            let mut chat = json!({
                "turn": self.chat["turn"],
                "elapsed_minutes": self.chat["elapsed_minutes"],
                "lines": self.chat["lines"],
                "new_entries": new_entries
            });
            let mut body = serde_json::Map::new();
            body.insert("clock".into(), self.clock.clone());
            for (key, value) in changed {
                if CHAT_FIELDS.contains(key) {
                    chat[*key] = value.clone();
                } else {
                    body.insert((*key).into(), value.clone());
                }
            }
            body.insert("chat".into(), chat);
            if !notices.is_empty() {
                body.insert("notices".into(), json!(notices));
            }
            Some(Message::text(Role::User, Value::Object(body).to_string()))
        };
        ChatDelta {
            chat_id: chat_id.into(),
            restart: false,
            message,
            seen: self.seen(s),
        }
    }
}

/// 台词只留编号、说话人和原文；时间和听众对模型没有用处，非发言的条目注明种类。
fn compact_entry(entry: &Value) -> Value {
    let mut compact = json!({
        "seq": entry["seq"],
        "actor": entry["actor"],
        "name": entry["name"],
        "text": entry["text"]
    });
    let speech = serde_json::to_value(ChatEntryKind::Speech).unwrap_or_default();
    if entry["kind"] != speech {
        compact["kind"] = entry["kind"].clone();
    }
    compact
}
