//! 整理轮次的请求内容：本批经历、当天较早摘要、相关主题与当时已知的目标。
use super::relevance::{related_notes, Focus};
use crate::{
    conversation::{estimate_tokens, wire_bytes, Message, Role},
    memory::{MemoryKind, MemoryRecord},
    notebook::{day_path, Documents, ReflectionBatch},
    prompts,
    session::Session,
    tools,
};
use kernel::World;
use serde_json::json;

/// 当天较早摘要只带末尾这么多字。
const EARLIER_SAME_DAY_TAIL_CHARS: usize = 2000;

fn episodes<'a>(s: &'a Session, batch: &ReflectionBatch) -> Vec<&'a MemoryRecord> {
    s.memory
        .records
        .iter()
        .filter(|m| {
            m.kind == MemoryKind::Episode
                && m.event_ids.iter().any(|id| batch.event_ids.contains(id))
        })
        .collect()
}

/// 保留完整来源，窗口不足时缩小批次。单条也放不下则暂缓，不能因此暂停生活。
pub(super) fn fit_reflection(
    world: &World,
    s: &mut Session,
    docs: &Documents,
    mut batch: ReflectionBatch,
    budget: u64,
    bytes_per_token: f64,
) -> Option<ReflectionBatch> {
    let tool_cost = json!(tools::definitions(protocol::RequestKind::Reflection))
        .to_string()
        .len() as u64;
    loop {
        let bytes = wire_bytes(&messages(world, s, &batch, docs)) + tool_cost;
        if estimate_tokens(bytes, bytes_per_token) <= budget {
            return Some(batch);
        }
        let last = episodes(s, &batch).pop()?;
        batch.event_ids.retain(|id| !last.event_ids.contains(id));
        batch.through = *batch.event_ids.iter().max()?;
    }
}

pub(super) fn messages(
    world: &World,
    s: &mut Session,
    batch: &ReflectionBatch,
    docs: &Documents,
) -> Vec<Message> {
    let events = episodes(s, batch);
    let earlier_same_day = docs.get(&day_path(batch.day)).map(|t| {
        let skip = t
            .chars()
            .count()
            .saturating_sub(EARLIER_SAME_DAY_TAIL_CHARS);
        t.chars().skip(skip).collect::<String>()
    });
    // 补整理旧经历时，不能把后来才产生的目标证据混进这一批来源。
    let source_until = events.last().map_or(0.0, |e| e.at);
    let goals: Vec<_> = s
        .context_goals()
        .into_iter()
        .filter(|g| g.updated_at <= source_until)
        .map(crate::context::view::goal_view)
        .collect();
    let focus = Focus::of_episodes(&events);
    let mut task = json!({
        "resident_identity": {
            "id": s.actor_id,
            "name": world.actor(&s.actor_id).map(|a| &a.name)
        },
        "reflection_task": batch,
        "source_window": {
            "first_minutes": events.first().map(|e| e.at),
            "last_minutes": events.last().map(|e| e.at),
            "day": batch.day + 1
        },
        "new_experiences": events,
        "earlier_same_day_excerpt": earlier_same_day,
        "memory_index": docs.get("INDEX.md"),
        "self": docs.get("self.md"),
        "relevant_notes": related_notes(world, s, &focus, false),
        "goals_known_in_this_period": goals
    });
    // 背景索引和单条经历都能回查，不能让一份超长来源永久堵住整理队列。
    for key in [
        "memory_index",
        "self",
        "relevant_notes",
        "goals_known_in_this_period",
    ] {
        crate::context::view::field(&mut s.input, &mut task, key, 4_000);
    }
    if let Some(events) = task["new_experiences"].as_array_mut() {
        for event in events {
            for key in ["text", "objects"] {
                crate::context::view::field(&mut s.input, event, key, 2_000);
            }
        }
    }
    let mut messages = vec![
        Message::text(Role::System, prompts::reflection_rules()),
        Message::text(Role::User, task.to_string()),
    ];
    messages.extend(s.notebook.reading_dialogue.clone());
    crate::context::clean::messages(&messages)
}
