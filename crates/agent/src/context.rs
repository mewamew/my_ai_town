//! 仅在工具调用全部配对之后折叠最旧的轮次。当前目标和承诺始终由独立字段保留。
use crate::{
    conversation::{wire_bytes, Message, Role},
    session::Session,
};
use std::collections::BTreeSet;

pub(crate) mod clean;
pub mod input;
mod summary;
pub(crate) mod view;
use summary::summarize;

/// 会话折叠的累积摘要总长度上限；超过就一次丢掉最旧的几段到一半以下，原文仍在归档里。
const FOLDED_SUMMARY_CHARS: usize = 6400;

/// 折叠一次之后摘要最多占的字节数：现有摘要加一段新摘录，不超过总上限。中文按 3 字节一字估。
pub(crate) fn summary_bytes_after_fold(current: usize) -> u64 {
    (current + summary::SECTION_CHARS * 3).min(FOLDED_SUMMARY_CHARS * 3) as u64
}

/// 检查会话消息里工具调用与结果是否配对，返回尚未收到结果的调用编号。
/// 配对规则只有这一份：请求前检查、折叠前检查、恢复存档时校验都用它。
pub fn open_calls(messages: &[Message]) -> Result<BTreeSet<String>, String> {
    let mut pending = BTreeSet::new();
    for message in messages {
        match message.role {
            Role::Assistant => {
                if !pending.is_empty() {
                    return Err("会话在工具结果未返回时继续了模型请求".into());
                }
                for call in &message.calls {
                    if !pending.insert(call.id.clone()) {
                        return Err("工具调用编号重复".into());
                    }
                }
            }
            Role::Tool => {
                if !message
                    .call_id
                    .as_ref()
                    .is_some_and(|id| pending.remove(id))
                {
                    return Err("工具结果缺少对应调用".into());
                }
            }
            _ => {
                if !pending.is_empty() {
                    return Err("未配对的工具调用被其他消息打断".into());
                }
            }
        }
    }
    Ok(pending)
}

/// 全部调用都已收到结果。
pub fn paired(messages: &[Message]) -> bool {
    open_calls(messages).is_ok_and(|open| open.is_empty())
}

/// 轮次从一条 user 消息开始；旧存档没有观察消息时，以不紧跟 user 的 assistant 为界。
fn round_starts(messages: &[Message]) -> Vec<usize> {
    let mut starts = Vec::new();
    for (i, message) in messages.iter().enumerate() {
        let start = match message.role {
            Role::User => true,
            Role::Assistant => i == 0 || messages[i - 1].role != Role::User,
            _ => false,
        };
        if start {
            starts.push(i);
        }
    }
    starts
}

/// 折叠后能保留的轮数：不超过 `most`，且保留下来的轮次正文放得进 `bytes`；一轮也放不下就归零。
pub fn rounds_within(messages: &[Message], most: usize, bytes: u64) -> usize {
    let starts = round_starts(messages);
    (1..=most.min(starts.len()))
        .rev()
        .find(|&k| wire_bytes(&messages[starts[starts.len() - k]..]) <= bytes)
        .unwrap_or(0)
}

/// 折叠最旧的轮次，保留最近 `keep_rounds` 轮原文。被折叠的消息整组归档，
/// 确定性摘录追加到累积摘要；没有可折叠的轮次返回 Ok(false)。
pub fn compact(session: &mut Session, keep_rounds: usize) -> Result<bool, String> {
    if session
        .pending
        .iter()
        .any(crate::session::PendingTool::blocks_request)
        || session.in_flight.is_some()
        || !paired(&session.messages)
    {
        return Err("工具结果尚未完整配对，保留上下文并暂停压缩".into());
    }
    let starts = round_starts(&session.messages);
    if starts.len() <= keep_rounds {
        return Ok(false);
    }
    let end = if keep_rounds == 0 {
        session.messages.len()
    } else {
        starts[starts.len() - keep_rounds]
    };
    let id = session.folded.compactions + 1;
    let folded: Vec<Message> = session.messages.drain(..end).collect();
    let (section, last_event) = summarize(&folded, id);
    if let Some(last) = last_event {
        session.cursors.folded_through = session.cursors.folded_through.max(last);
    }
    let mut sections: Vec<String> = session
        .folded
        .compacted
        .split("\n\n")
        .filter(|s| !s.trim().is_empty())
        .map(str::to_string)
        .collect();
    sections.push(section);
    // 平时只在末尾追加，摘要原有部分仍是下次请求的前缀、能命中缓存。超过上限时一次删到一半以下，
    // 而不是每次删一段：那样之后每次折叠都会改动摘要开头，整段摘要都要重新计费。
    let total = |sections: &[String]| {
        sections
            .iter()
            .map(|s| s.chars().count() + 2)
            .sum::<usize>()
    };
    if total(&sections) > FOLDED_SUMMARY_CHARS {
        while sections.len() > 1 && total(&sections) > FOLDED_SUMMARY_CHARS / 2 {
            sections.remove(0);
        }
    }
    session.folded.compacted = sections.join("\n\n");
    session.folded.archives.insert(id, folded);
    session.folded.compactions = id;
    session.forget_shown();
    Ok(true)
}
