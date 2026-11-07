//! 有界的当前世界视图。集合省略有来源可查；事件积压时只展示最近的，更早的报条数，游标到最新。
use super::input::InputState;
use crate::session::Session;
use serde_json::{json, Value};

/// 保留数组结构和完整条目；省略部分通过同级来源引用读取。
pub(crate) fn field(state: &mut InputState, object: &mut Value, key: &str, bytes: usize) {
    let Some(value) = object.get_mut(key) else {
        return;
    };
    if value.to_string().len() <= bytes {
        return;
    }
    let source = state.source(value);
    if let Some(items) = value.as_array_mut() {
        let mut size = 2;
        let keep = items
            .iter()
            .take_while(|item| {
                size += item.to_string().len() + 1;
                size <= bytes
            })
            .count();
        items.truncate(keep);
        object[format!("{key}_source")] =
            json!({"context_source":source,"truncated":true,"shown_items":keep});
    } else {
        *value = state.bound(value.take(), bytes);
    }
}

/// 先压缩道具详情，再截断列表，避免少量长说明挤掉附近的补给。
fn visible_props(state: &mut InputState, view: &mut Value, bytes: usize) {
    let Some(full) = view.get("visible_props").and_then(Value::as_array) else {
        return;
    };
    if view["visible_props"].to_string().len() <= bytes {
        return;
    }
    let source = state.source(&view["visible_props"]);
    let total = full.len();
    let mut compact = Vec::new();
    let mut size = 2;
    for prop in full {
        let verbs: Vec<_> = prop["verbs"].as_array().into_iter().flatten().map(|v| {
            json!({"verb":v["verb"],"action_id":v["action_id"],"minutes":v["minutes"],"remaining":v["remaining"],"effects":v["description"]["effects"]})
        }).collect();
        let item = json!({"id":prop["id"],"name":prop["name"],"verbs":verbs});
        size += item.to_string().len() + 1;
        if size > bytes {
            break;
        }
        compact.push(item);
    }
    let shown = compact.len();
    view["visible_props"] = json!(compact);
    view["visible_props_source"] = json!({
        "context_source":source,"details_omitted":true,
        "truncated":shown < total,"shown_items":shown,"total_items":total
    });
}

pub(crate) fn observation(s: &mut Session, raw: &Value, bytes: usize) -> (Value, u64) {
    let mut view = raw.clone();
    // 这些集合可按需查询，不能让它们挤掉本人状态与正在进行的互动。
    visible_props(&mut s.input, &mut view, bytes / 8);
    for key in ["people_here", "nearby_chats", "inventory"] {
        field(&mut s.input, &mut view, key, bytes / 8);
    }
    if let Some(items) = view["interactions"].as_array_mut() {
        let old = items.clone();
        items.retain(|item| matches!(item["status"].as_str(), Some("running" | "offered")));
        if items.len() != old.len() {
            let source = s.input.source(&json!(old));
            view["past_interactions_source"] = json!({"context_source":source});
        }
    }
    if let Some(items) = view["interactions"].as_array_mut() {
        // 当前聊天优先于待回应邀请。台词已经作为事件进入观察，这里只留最近几句看轮次和语境，旧台词可以回查。
        items.sort_by_key(|item| item["status"] != "running");
        for item in items {
            recent_field(&mut s.input, item, "entries", bytes / 12);
            for key in ["changes", "offered_items", "event_ids"] {
                field(&mut s.input, item, key, 1_000);
            }
        }
    }
    // 即使本次需要进一步缩减，也不能悄悄删除正在进行的事务。
    let running_bytes: usize = view["interactions"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|item| item["status"] == "running")
        .map(|item| item.to_string().len() + 1)
        .sum();
    field(
        &mut s.input,
        &mut view,
        "interactions",
        (bytes / 2).max(running_bytes + 2),
    );
    // 单个事件元数据也可能很大；至少保留事件身份、种类与原文摘要。
    if let Some(events) = view["events"].as_array_mut() {
        for event in events.iter_mut() {
            if event.to_string().len() > bytes / 3 {
                let source = s.input.source(event);
                *event = json!({"event_id":event["event_id"],"kind":event["kind"],"at":event["at"],"text":event["text"],"context_source":source,"truncated":true});
            }
        }
    }
    // 放不下时留最近的，丢掉的较早事件并进 earlier_events：醒来先要知道刚发生的事
    // （见 observation::observe）。游标照样到最新，丢掉的不再补看。
    let dropped = keep_recent_events(&mut view["events"], bytes / 3);
    crate::observation::note_earlier(&mut view, dropped);
    let cursor = raw["event_cursor"]
        .as_u64()
        .unwrap_or(s.cursors.acknowledged);
    view["event_cursor"] = json!(cursor);
    (view, cursor)
}

/// 事件从最早的丢起，直到放得下；最新一条和通知不丢。返回丢掉的（时刻，是不是交谈），按时间先后。
fn keep_recent_events(events: &mut Value, bytes: usize) -> Vec<(f64, bool)> {
    let Some(list) = events.as_array_mut() else {
        return Vec::new();
    };
    let (mut kept, mut dropped) = (Vec::new(), Vec::new());
    let (mut size, mut full) = (2, false);
    for event in list.drain(..).rev() {
        let len = event.to_string().len() + 1;
        full |= !kept.is_empty() && size + len > bytes;
        if full && event["kind"] != "notice" {
            dropped.push((
                event["at"].as_f64().unwrap_or(0.0),
                event["kind"] == "speech",
            ));
        } else {
            size += len;
            kept.push(event);
        }
    }
    kept.reverse();
    dropped.reverse();
    *list = kept;
    dropped
}

/// 发给模型前去掉只对程序有用的内容：事件的动作编号和对象列表、被同时刻动作回执或通知
/// 包含的观察与阅读事件（阅读正文按动作回执的编号查）、天气的修订号和过渡记录、与事件重复的
/// 身体变化历史；在室内时不带可去的室内地点。时间留一位小数，需求值和路程分钟取整。
/// 慢变字段按去掉之后的内容判断是否变化。
pub(crate) fn slim(observation: &Value) -> Value {
    let mut view = observation.clone();
    if let Some(object) = view.as_object_mut() {
        object.remove("revision");
    }
    round(&mut view["sim_minutes"], 10.0);
    if let Some(events) = view["events"].as_array_mut() {
        let receipts: Vec<(f64, String)> = events
            .iter()
            .filter(|e| matches!(e["kind"].as_str(), Some("action" | "notice")))
            .filter_map(|e| Some((e["at"].as_f64()?, e["text"].as_str()?.to_string())))
            .collect();
        events.retain(|e| {
            !matches!(e["kind"].as_str(), Some("observation" | "readable"))
                || !repeated(e, &receipts)
        });
        for event in events.iter_mut() {
            if let Some(object) = event.as_object_mut() {
                object.remove("action_id");
                object.remove("objects");
            }
            round(&mut event["at"], 10.0);
        }
    }
    if let Some(environment) = view.get_mut("environment").and_then(Value::as_object_mut) {
        if let Some(kind) = environment.get("weather").map(|w| w["kind"].clone()) {
            environment.insert("weather".into(), json!({ "kind": kind }));
        }
        if environment.get("exposure").and_then(Value::as_str) == Some("indoor") {
            environment.remove("indoor_alternatives");
        }
        for place in environment
            .get_mut("indoor_alternatives")
            .and_then(Value::as_array_mut)
            .into_iter()
            .flatten()
        {
            round(&mut place["minutes"], 1.0);
        }
    }
    if let Some(body) = view.get_mut("body").and_then(Value::as_object_mut) {
        body.remove("history");
        body.remove("revision");
        let safe = body
            .get("exposure")
            .and_then(Value::as_array)
            .is_some_and(|a| a.iter().all(|v| v.as_f64() == Some(0.0)));
        if safe {
            body.remove("exposure");
        }
        for minutes in body
            .get_mut("exposure")
            .and_then(Value::as_array_mut)
            .into_iter()
            .flatten()
        {
            round(minutes, 1.0);
        }
    }
    for need in view["needs"].as_array_mut().into_iter().flatten() {
        round(&mut need["value"], 1.0);
    }
    view
}

/// 观察或阅读事件的内容已在同一时刻的动作回执或通知里：整句被包含，或「某人使用某物：」之后的部分被包含。
fn repeated(event: &Value, receipts: &[(f64, String)]) -> bool {
    let (Some(at), Some(text)) = (event["at"].as_f64(), event["text"].as_str()) else {
        return false;
    };
    let tail = text.split_once('：').map_or("", |(_, rest)| rest);
    receipts.iter().any(|(time, receipt)| {
        (time - at).abs() < 1e-6
            && (receipt.contains(text) || (tail.chars().count() >= 4 && receipt.contains(tail)))
    })
}

/// 数值按 1/scale 取整；不是数字就不动。
fn round(value: &mut Value, scale: f64) {
    if let Some(number) = value.as_f64() {
        let rounded = (number * scale).round() / scale;
        *value = if scale == 1.0 {
            json!(rounded as i64)
        } else {
            json!(rounded)
        };
    }
}

pub(crate) fn recent_field(state: &mut InputState, object: &mut Value, key: &str, bytes: usize) {
    let Some(value) = object.get_mut(key) else {
        return;
    };
    if value.to_string().len() <= bytes {
        return;
    }
    let source = state.source(value);
    if let Some(items) = value.as_array_mut() {
        let mut size = 2;
        let keep = items
            .iter()
            .rev()
            .take_while(|item| {
                size += item.to_string().len() + 1;
                size <= bytes
            })
            .count()
            .max(1);
        let omitted = items.len().saturating_sub(keep);
        items.drain(..omitted);
        object[format!("{key}_source")] =
            json!({"context_source":source,"truncated":true,"omitted_older_items":omitted});
    }
}

/// 当前目标的身份、条件与承诺保持原文；步骤及结束目标超长时另给来源。
pub(crate) fn goals(s: &mut Session) -> Value {
    let full = json!(s.context_goals());
    if full.to_string().len() <= 8_000 {
        return full;
    }
    let source = s.input.source(&full);
    json!(s.context_goals().into_iter().filter(|g| g.status.is_open()).map(|g| {
        let mut goal = json!({
            "id":g.id,"title":g.title,"condition":g.condition,"status":g.status,
            "commitment":g.commitment,"reason":g.reason,"next_step":g.next_steps.first(),"context_source":source
        });
        if let Some(due) = &g.due_clock {
            goal["due_clock"] = json!(due);
        }
        goal
    }).collect::<Vec<_>>())
}
