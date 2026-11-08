//! 发给模型前的统一出口。生活、交谈和整理三种轮次组好请求后，每条 user 与 tool 消息里的 JSON 都在
//! 这里过一遍；截断时的预览和可回查的原文（`InputState`）也一样，以后新加的字段自动管住。
//! 会话里存的、存档、录像、日志里的世界数据和画面拿到的都不变，只改写给模型看的样子：
//!
//! - 没有值的字段不写：null 和空字符串；空列表只在零碎栏目里省掉（`EMPTY_NOISE`）。眼前的人、
//!   道具、事件这类状态列表空着也照写，「没出现」在只发变化的规则里是「和上次一样」。
//! - 时刻写成「D1 08:48」：游戏时刻是从第 1 天 0 点算起的分钟数，按字段名认（`TIME_KEYS`）。
//! - 其余小数最多两位，整数值写成整数。
//! - 事件编号的列表写成区间「#1–31」（`event_ranges`）。
//! - 书信报纸只留书名、作者、第几版；阅读事实只留读的哪件、读没读过、改没改过——内容指纹是给
//!   程序核对的 64 位哈希。
//! - 记忆里涉及的对象去掉聊天台词和旧动作编号，天气变化不带世界编号。
//! - 动作回执不写动作组和每项动作的编号，也不重复交上去的草案。
use crate::conversation::{Message, Role};
use serde_json::{json, Map, Value};

/// 值是游戏时刻（分钟数）的字段。
const TIME_KEYS: [&str; 13] = [
    "at",
    "sim_minutes",
    "created_at",
    "updated_at",
    "since",
    "until",
    "started_at",
    "ended_at",
    "accepted_at",
    "expires_at",
    "resume_at",
    "first_minutes",
    "last_minutes",
];

/// 空着就不写的零碎栏目：目标的证据和下一步、动作回执的变化、记忆的修正关系、身体状况、
/// 道具的存放和动作……空着和没有一样。
const EMPTY_NOISE: [&str; 19] = [
    "evidence",
    "next_steps",
    "replaces",
    "changes",
    "objects",
    "conditions",
    "causes",
    "stored_items",
    "effects",
    "actions",
    "occupants",
    "audience",
    "event_ids",
    "indoor_alternatives",
    "notices",
    "verbs",
    "members",
    "entries",
    "offered_items",
];

/// 值是事件编号列表、三个以上就写成区间的字段。
const EVENT_LISTS: [&str; 3] = ["sources", "event_ids", "evidence"];

/// 发给模型的消息：user 和 tool 消息的正文是 JSON 就清理，别的原样。
pub(crate) fn messages(messages: &[Message]) -> Vec<Message> {
    messages.iter().map(message).collect()
}

fn message(message: &Message) -> Message {
    let mut out = message.clone();
    if matches!(message.role, Role::User | Role::Tool) {
        if let Ok(mut value) = serde_json::from_str::<Value>(&message.content) {
            if value.is_object() || value.is_array() {
                clean(&mut value);
                out.content = value.to_string();
            }
        }
    }
    out
}

/// 清理以后的字节数：截断、分配额度都按发给模型的样子量。
pub(crate) fn wire_len(value: &Value) -> usize {
    let mut value = value.clone();
    clean(&mut value);
    value.to_string().len()
}

/// 就地清理一份给模型看的 JSON。
pub(crate) fn clean(value: &mut Value) {
    match value {
        Value::Object(map) => clean_object(map),
        Value::Array(items) => items.iter_mut().for_each(clean),
        Value::Number(_) => *value = round(value),
        _ => {}
    }
}

fn clean_object(map: &mut Map<String, Value>) {
    let keys: Vec<String> = map.keys().cloned().collect();
    for key in keys {
        let value = map.get_mut(&key).expect("键来自同一张表");
        match key.as_str() {
            k if TIME_KEYS.contains(&k) && value.is_number() => {
                *value = json!(kernel::clock_string(value.as_f64().unwrap_or(0.0)));
            }
            k if EVENT_LISTS.contains(&k) => match event_list(value) {
                Some(ranges) => *value = json!(ranges),
                None => clean(value),
            },
            "readable" if value.is_object() => readable(value),
            "objects" => objects(value),
            "group" if value.get("accepted_at").is_some() => {
                action_group(value);
                clean(value);
            }
            _ => clean(value),
        }
        let empty = match &*value {
            Value::Null => true,
            Value::String(s) => s.is_empty(),
            Value::Array(items) => items.is_empty() && EMPTY_NOISE.contains(&key.as_str()),
            Value::Object(fields) => fields.is_empty() && EMPTY_NOISE.contains(&key.as_str()),
            _ => false,
        };
        if empty {
            map.remove(&key);
        }
    }
}

/// 小数最多两位；整数值写成整数。整数原样。
fn round(value: &Value) -> Value {
    match value.as_f64() {
        Some(number) if !value.is_i64() && !value.is_u64() && number.is_finite() => {
            let rounded = (number * 100.0).round() / 100.0;
            if rounded.fract() == 0.0 && rounded.abs() < 1e15 {
                json!(rounded as i64)
            } else {
                json!(rounded)
            }
        }
        _ => value.clone(),
    }
}

/// 三个以上的事件编号写成区间；不是编号列表就不动。
fn event_list(value: &Value) -> Option<String> {
    let ids: Vec<u64> = value
        .as_array()?
        .iter()
        .map(Value::as_u64)
        .collect::<Option<_>>()?;
    (ids.len() >= 3).then(|| event_ranges(&ids))
}

/// 事件编号写成区间：连着的三个以上写「#1–31」，其余逐个写，用顿号隔开。
pub(crate) fn event_ranges(ids: &[u64]) -> String {
    let mut ids = ids.to_vec();
    ids.sort_unstable();
    ids.dedup();
    let mut parts = Vec::new();
    let mut i = 0;
    while i < ids.len() {
        let mut j = i;
        while j + 1 < ids.len() && ids[j + 1] == ids[j] + 1 {
            j += 1;
        }
        if j - i >= 2 {
            parts.push(format!("#{}–{}", ids[i], ids[j]));
        } else {
            parts.extend(ids[i..=j].iter().map(|id| format!("#{id}")));
        }
        i = j + 1;
    }
    parts.join("、")
}

/// 动作组的回执：动作组和每项动作的编号、受理时刻、交上去的草案原样都是给程序配对的，不写。
fn action_group(group: &mut Value) {
    if let Some(fields) = group.as_object_mut() {
        for key in ["id", "accepted_at", "actions"] {
            fields.remove(key);
        }
    }
    for result in group["results"].as_array_mut().into_iter().flatten() {
        if let Some(fields) = result.as_object_mut() {
            fields.remove("action_id");
            fields.remove("group_id");
        }
    }
}

/// 书信报纸的元数据只留书名、作者、第几版；阅读事实只留读的哪件、读没读过、改没改过。
fn readable(value: &mut Value) {
    let fact = value.get("previously_read").is_some();
    let mut compact = Map::new();
    if fact {
        for key in ["id", "previously_read"] {
            if let Some(v) = value.get(key) {
                compact.insert(key.into(), v.clone());
            }
        }
        let changed = value["previous_version"]
            .as_str()
            .is_some_and(|old| value["version"].as_str() != Some(old));
        if changed {
            compact.insert("changed_since_last_read".into(), json!(true));
        }
    } else {
        for key in ["title", "author", "version"] {
            if let Some(v) = value.get(key) {
                compact.insert(key.into(), v.clone());
            }
        }
    }
    *value = Value::Object(compact);
    clean(value);
}

/// 记忆涉及的对象：聊天里的单句（chat:编号:句号）和旧写法的动作编号对模型没有用处，去掉；
/// 天气变化写成「天气」，不带世界编号。
fn objects(value: &mut Value) {
    let Some(items) = value.as_array_mut() else {
        clean(value);
        return;
    };
    let mut kept: Vec<Value> = Vec::new();
    for item in items.drain(..) {
        let item = match item.as_str() {
            Some(text) if text.starts_with("chat:") || old_command_id(text) => continue,
            Some(text) if text.starts_with("weather:") => json!("天气"),
            _ => item,
        };
        if !kept.contains(&item) {
            kept.push(item);
        }
    }
    *items = kept;
}

/// 以前的世界命令编号：`s{会话}-r{请求}-{服务商的调用编号}`。
fn old_command_id(text: &str) -> bool {
    let Some(rest) = text.strip_prefix('s') else {
        return false;
    };
    let mut parts = rest.splitn(3, '-');
    let session = parts.next().unwrap_or_default();
    let request = parts.next().unwrap_or_default();
    parts.next().is_some_and(|call| !call.is_empty())
        && !session.is_empty()
        && session.bytes().all(|b| b.is_ascii_digit())
        && request.len() > 1
        && request.starts_with('r')
        && request[1..].bytes().all(|b| b.is_ascii_digit())
}
