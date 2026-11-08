//! 摘录先按证据类型和新旧选择，再按发生顺序展示；预算不足不等于后面的事没发生。
use crate::{
    conversation::{Message, Role},
    prompts,
    tools::ToolName,
};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

pub(super) const SECTION_CHARS: usize = 2000;
const OVERFLOW_CHARS: usize = 80;

fn clip(text: &str, chars: usize) -> String {
    text.chars()
        .take(chars)
        .map(|c| if c == '\n' || c == '\r' { ' ' } else { c })
        .collect()
}

/// 摘录及其优先级：0 最先保留。
type Excerpt = (u8, String);

#[derive(Default)]
struct Collector<'a> {
    excerpts: Vec<Excerpt>,
    event_ids: BTreeSet<u64>,
    /// 各轮观察的钟点，摘要开头写起止。
    clocks: Vec<String>,
    /// 调用编号到工具名，供工具结果摘录使用。
    names: BTreeMap<&'a str, &'a str>,
}

/// 观察里的钟点；没有 clock 的旧观察按分钟数换算。
fn clock_of(observation: &Value) -> Option<String> {
    observation["clock"]
        .as_str()
        .map(str::to_owned)
        .or_else(|| {
            observation["sim_minutes"]
                .as_f64()
                .map(kernel::clock_string)
        })
}

impl<'a> Collector<'a> {
    fn user(&mut self, message: &Message) {
        let value = serde_json::from_str::<Value>(&message.content).ok();
        // 收到邀请时还在做的那组动作，做完的结果补成一条 user 消息
        if let Some(result) = value.as_ref().and_then(|v| v.get("action_result")) {
            if let Some(line) = actions_line(result) {
                let priority = if result["ok"] == false { 0 } else { 2 };
                self.excerpts.push((priority, line));
            }
            return;
        }
        let observation = match value {
            Some(value) if value.get("observation").is_some() => value["observation"].clone(),
            _ => {
                let line = format!(
                    "{}{}",
                    prompts::SUMMARY_PROMPT_PREFIX,
                    clip(&message.content, 200)
                );
                self.excerpts.push((2, line));
                return;
            }
        };
        self.clocks.extend(clock_of(&observation));
        for event in observation["events"].as_array().into_iter().flatten() {
            let Some(event_id) = event["event_id"].as_u64() else {
                continue;
            };
            let text = event["text"].as_str().unwrap_or_default();
            if !self.event_ids.insert(event_id) || text.trim().is_empty() {
                continue;
            }
            let reading = event.get("readable").is_some_and(|v| !v.is_null());
            let priority = match event["kind"].as_str() {
                Some("readable" | "notice" | "speech" | "job" | "interaction") => 0,
                _ if reading => 0,
                _ => 1,
            };
            // 读的是哪本、第几版，正文里写着；内容指纹是给程序核对的哈希，不进摘要
            let line = format!(
                "事件 #{event_id} {}：{}",
                kernel::clock_string(event["at"].as_f64().unwrap_or(0.0)),
                clip(text, 200)
            );
            self.excerpts.push((priority, line));
        }
    }
    fn assistant(&mut self, message: &'a Message) {
        for call in &message.calls {
            self.names.insert(call.id.as_str(), call.name.as_str());
        }
        if !message.content.is_empty() {
            let line = format!(
                "{}{}",
                prompts::SUMMARY_THOUGHT_PREFIX,
                clip(&message.content, 120)
            );
            self.excerpts.push((3, line));
        }
    }
    /// 工具结果写成一句话；服务商给的调用编号和原样的结果 JSON 不进摘要。
    fn tool(&mut self, message: &Message) {
        let call_id = message.call_id.as_deref().unwrap_or_default();
        let name = self.names.get(call_id).copied().unwrap_or_default();
        let value: Value = serde_json::from_str(&message.content).unwrap_or_default();
        let reading = name == ToolName::ReadContent.as_str()
            || value.get("reading_result").is_some()
            || value["result"].get("reading_result").is_some();
        if reading && value["ok"] != false {
            let id = value
                .get("event_id")
                .unwrap_or(&value["result"]["event_id"]);
            self.excerpts.push((2, prompts::summary_reading(id)));
            return;
        }
        let tool = name.parse::<ToolName>().ok();
        if value["ok"] == false {
            if let Some(error) = value["error"].as_str() {
                let priority = if tool.is_some_and(ToolName::is_lookup) {
                    2
                } else {
                    0
                };
                let line = prompts::summary_failed(name, &clip(error, 160));
                self.excerpts.push((priority, line));
                return;
            }
        }
        let result = value.get("result").unwrap_or(&value);
        let line = match tool {
            Some(ToolName::RunActions) => actions_line(&value),
            Some(ToolName::SetGoal) => result["title"].as_str().map(|title| {
                prompts::summary_goal(
                    &clip(title, 60),
                    result["status"].as_str().unwrap_or_default(),
                    result["reason"]
                        .as_str()
                        .filter(|r| !r.is_empty())
                        .map(|r| clip(r, 80))
                        .as_deref(),
                )
            }),
            Some(ToolName::OfferInvitation | ToolName::ReplyInvitation | ToolName::Interact) => {
                interaction_line(&result["interaction"])
                    .or_else(|| interaction_line(&value["invitation"]))
                    .or_else(|| interaction_line(&value["interaction"]))
            }
            Some(ToolName::WaitFor) => value["invitation"]
                .is_object()
                .then(|| interaction_line(&value["invitation"]))
                .flatten()
                .or_else(|| {
                    let at = value["at"].as_f64()?;
                    Some(prompts::summary_wait(
                        &kernel::clock_string(at),
                        value["woke_by"] == "event",
                    ))
                }),
            Some(ToolName::ModeAction) => result
                .as_str()
                .map(|text| prompts::summary_mode(&clip(text, 160))),
            // 查看、回想、翻记忆：看到的东西在之后的观察和事件里，不另记
            _ => None,
        };
        if let Some(line) = line {
            let priority = if tool == Some(ToolName::SetGoal) {
                0
            } else {
                2
            };
            self.excerpts.push((priority, line));
        }
    }
}

/// 一组动作的结果写成一句：开始的钟点，每项动作的动词、结果、变化和原因。
fn actions_line(value: &Value) -> Option<String> {
    let results = value["group"]["results"].as_array()?;
    let at = results
        .first()
        .and_then(|r| r["started_at"].as_f64().or(r["ended_at"].as_f64()))
        .or(value["group"]["accepted_at"].as_f64())?;
    let steps: Vec<String> = results
        .iter()
        .map(|r| {
            let changes: Vec<&str> = r["changes"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .take(3)
                .collect();
            prompts::summary_step(
                r["verb"].as_str().unwrap_or_default(),
                r["status"].as_str().unwrap_or_default(),
                &changes,
                r["reason"].as_str(),
            )
        })
        .collect();
    if steps.is_empty() {
        let status = value["group"]["status"].as_str().unwrap_or_default();
        return Some(prompts::summary_actions(
            &kernel::clock_string(at),
            &[prompts::summary_step("这组动作", status, &[], None)],
        ));
    }
    Some(clip(
        &prompts::summary_actions(&kernel::clock_string(at), &steps),
        300,
    ))
}

/// 邀请、交谈、同行这些互动：种类、状态和最后一句变化。
fn interaction_line(interaction: &Value) -> Option<String> {
    let kind =
        serde_json::from_value::<protocol::InteractionKind>(interaction["kind"].clone()).ok()?;
    let last = interaction["changes"]
        .as_array()
        .and_then(|c| c.last())
        .and_then(Value::as_str)
        .map(|c| clip(c, 80));
    Some(prompts::summary_interaction(
        kind.label(),
        interaction["status"].as_str().unwrap_or_default(),
        last.as_deref(),
    ))
}

/// 折叠一批消息的摘要文本，以及其中最后一个事件的编号。
pub(super) fn summarize(messages: &[Message], id: u64) -> (String, Option<u64>) {
    let mut collector = Collector::default();
    for message in messages {
        match message.role {
            Role::User => collector.user(message),
            Role::Assistant => collector.assistant(message),
            Role::Tool => collector.tool(message),
            Role::System => {}
        }
    }
    let last_event = collector.event_ids.last().copied();
    let range = match (collector.event_ids.first(), collector.event_ids.last()) {
        (Some(a), Some(b)) => format!("事件 #{a}—#{b}"),
        _ => prompts::SUMMARY_NO_EVENTS.into(),
    };
    let span = match (collector.clocks.first(), collector.clocks.last()) {
        (Some(a), Some(b)) => format!("，{a}—{b}"),
        _ => String::new(),
    };
    let mut text = prompts::summary_header(id, &range, &span);
    let total = collector.excerpts.len();
    let mut ranked: Vec<_> = collector.excerpts.into_iter().enumerate().collect();
    // 同等类型优先保留后来的事实，避免开头的普通记录挤掉后面的关键变化。
    ranked.sort_by(|(i, (a, _)), (j, (b, _))| a.cmp(b).then_with(|| j.cmp(i)));
    let mut used = text.chars().count() + OVERFLOW_CHARS;
    let mut selected = Vec::new();
    for (index, (_, line)) in ranked {
        let cost = line.chars().count() + 1;
        if used + cost <= SECTION_CHARS {
            used += cost;
            selected.push((index, line));
        }
    }
    selected.sort_by_key(|(index, _)| *index);
    let omitted = total - selected.len();
    for (_, line) in selected {
        text.push('\n');
        text.push_str(&line);
    }
    if omitted > 0 {
        text.push_str(&prompts::summary_omitted(omitted));
    }
    (text, last_event)
}
