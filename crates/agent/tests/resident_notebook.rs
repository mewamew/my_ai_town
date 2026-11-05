use crate::support::*;
use agent::{
    budget::Limits,
    memory::MemoryKind,
    notebook::{self, apply_reflection, plan_reflection},
    runtime::ResidentRuntime,
};
use serde_json::json;

#[test]
fn reflection_is_incremental_retains_revisions_and_supplies_related_context() {
    reflection_can_page_an_oversized_reading_without_losing_the_batch();
    let (mut w, mut r) = prepared();
    assert!(r.poll(&mut w, false).is_empty());
    let q = request(&mut r, &mut w);
    assert_eq!(q.tools.len(), 3);
    let task: serde_json::Value = serde_json::from_str(&q.messages[1].content).unwrap();
    assert_eq!(task["resident_identity"]["id"], "r1");
    assert_eq!(
        task["resident_identity"]["name"],
        w.actor("r1").unwrap().name
    );
    let body = update(
        &w,
        r.session("r1").unwrap(),
        "今天开放和明天关闭并不矛盾；查询时应保留日期。",
        "supported",
    );
    let reflect = tool_call("reflect-1", "reflect", body);
    assert!(reply_with(
        &mut r,
        &mut w,
        &q,
        "I'll start by reading.",
        vec![reflect]
    ));
    let thought = w.actor("r1").unwrap().journal.thought.as_ref();
    assert_ne!(
        thought.map(|t| t.text.as_str()),
        Some("I'll start by reading."),
        "整理轮次的文字是整理记忆时的说明，不是村民此刻的想法"
    );
    let s = r.session("r1").unwrap();
    assert!(s.notebook.request.is_none());
    assert!(s.notebook.through_event > 0);
    assert!(plan_reflection(&w, s).is_none());
    let next = request(&mut r, &mut w);
    assert!(next
        .messages
        .last()
        .unwrap()
        .content
        .contains("今天开放和明天关闭并不矛盾"));
    reply(&mut r, &mut w, &next, "observe", json!({}));
    w.step(65.0);
    read_board(
        &mut w,
        "r1",
        "third",
        &format!(
            "更新公告：明天维修取消，图书馆照常开放。{}",
            "这次公告修正了先前的安排，应注明来源与日期。".repeat(5)
        ),
    );
    let q = request(&mut r, &mut w);
    assert_eq!(
        q.tools.len(),
        3,
        "普通动作完成后应自动整理，不能依赖模型主动 observe 才有机会"
    );
    let old = r.session("r1").unwrap().notebook.through_event;
    let b = r.session("r1").unwrap().notebook.request.as_ref().unwrap();
    assert!(b.event_ids.iter().all(|id| *id > old));
    let body = update(
        &w,
        r.session("r1").unwrap(),
        "新公告撤销了明天维修关闭的安排，旧判断已过期。",
        "rejected",
    );
    reply(&mut r, &mut w, &q, "reflect", body);
    let s = r.session("r1").unwrap();
    assert_eq!(
        s.notebook.pages["places/library.md"].status,
        notebook::NoteStatus::Rejected
    );
    assert!(s
        .notebook
        .history
        .iter()
        .any(|p| p.path == "places/library.md" && p.text.contains("并不矛盾")));
    assert!(s.notebook.pages["summaries/D001.md"]
        .text
        .contains("新增整理"));
    ResidentRuntime::restore(r.state().clone(), &w).unwrap();
}

fn reflection_can_page_an_oversized_reading_without_losing_the_batch() {
    let (mut w, mut r) = prepared();
    let text = "这是本次读到的长公告原文。".repeat(250);
    read_board(&mut w, "r1", "long-reflection", &text);
    let event = w
        .actor("r1")
        .unwrap()
        .journal
        .events_after(0)
        .iter()
        .rev()
        .find(|event| event.kind == protocol::FactKind::Readable)
        .unwrap()
        .event_id;
    let q = request(&mut r, &mut w);
    assert_eq!(q.tools.len(), 3);
    let through = r
        .session("r1")
        .unwrap()
        .notebook
        .request
        .as_ref()
        .unwrap()
        .through;
    reply(
        &mut r,
        &mut w,
        &q,
        "read_content",
        json!({"event_id":event}),
    );
    let s = r.session("r1").unwrap();
    let result: serde_json::Value =
        serde_json::from_str(&s.notebook.reading_dialogue.last().unwrap().content).unwrap();
    let source = result["result"]["context_source"].as_u64().unwrap();
    let q = request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "context_read",
        json!({"source":source,"pointer":"/reading_result/content/text","limit":1_000}),
    );
    let s = r.session("r1").unwrap();
    assert_eq!(s.notebook.request.as_ref().unwrap().through, through);
    let result: serde_json::Value =
        serde_json::from_str(&s.notebook.reading_dialogue.last().unwrap().content).unwrap();
    assert_eq!(
        result["result"]["text"],
        text.chars().take(1_000).collect::<String>()
    );
    assert_eq!(result["result"]["next_offset"], 1_000);
    // 未提交 reflect 时，来源游标不能因分页提前完成。
    assert!(s.notebook.through_event < through);
}

#[test]
fn invalid_evidence_is_atomic_and_duplicate_receipts_do_not_prove_a_belief() {
    let (w, r) = prepared();
    let mut s = r.session("r1").unwrap().clone();
    s.notebook.request = plan_reflection(&w, &s);
    let before = json!(s);
    let mut bad = update(&w, &s, "这是结论", "supported");
    bad["notes"][0]["event_ids"] = json!([99999]);
    assert!(apply_reflection(&w, &mut s, serde_json::from_value(bad).unwrap()).is_err());
    assert_eq!(json!(s), before);
    let first = s
        .memory
        .records
        .iter()
        .find(|m| m.kind == MemoryKind::Episode && m.event_ids.len() > 1)
        .unwrap();
    let mut duplicate = update(&w, &s, "同一条公告的两个回执不是两次验证", "supported");
    duplicate["notes"][0]["event_ids"] = json!(first.event_ids);
    assert!(apply_reflection(&w, &mut s, serde_json::from_value(duplicate).unwrap()).is_err());
    assert_eq!(json!(s), before);
    for path in ["../someone/self.md", "events/D001.jsonl"] {
        let mut bad = update(&w, &s, "不能改原文", "candidate");
        bad["notes"][0]["path"] = json!(path);
        assert!(apply_reflection(&w, &mut s, serde_json::from_value(bad).unwrap()).is_err());
    }
    let body = update(&w, &s, "候选认识允许一次经历，但仍保留来源", "candidate");
    apply_reflection(&w, &mut s, serde_json::from_value(body).unwrap()).unwrap();
    s.notebook.pages.get_mut("summaries/D001.md").unwrap().path = "summaries/D.md".into();
    assert!(s.notebook.validate(&w, "r1").is_err());
}

/// 没读过任何东西时整理不给 read_content；模型硬拿它查别的事件，报错也接着这一批，交了 reflect 就完成，
/// 不整批推迟（海难环岛里两人都拿 read_content 查聊天，整理各推迟了两小时）。
#[test]
fn reflection_without_readings_offers_no_read_content_and_a_wrong_lookup_keeps_the_batch() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    w.set_need_values("r1", Some(30.0), None).unwrap();
    let is_reflection = |q: &agent::runtime::AgentRequest| {
        q.messages
            .iter()
            .any(|m| m.content.contains("reflection_task"))
    };
    let mut q = request(&mut r, &mut w);
    for _ in 0..5 {
        if is_reflection(&q) {
            break;
        }
        reply(
            &mut r,
            &mut w,
            &q,
            "wait_for",
            json!({"minutes":1,"reason":"歇一下"}),
        );
        w.step(1.1);
        q = request(&mut r, &mut w);
    }
    assert!(is_reflection(&q), "饿了的通知应当触发一次整理");
    let names: Vec<_> = q
        .tools
        .iter()
        .map(|t| t["function"]["name"].clone())
        .collect();
    assert!(!names.contains(&json!("read_content")), "{names:?}");
    let batch = r.session("r1").unwrap().notebook.request.clone().unwrap();
    reply(
        &mut r,
        &mut w,
        &q,
        "read_content",
        json!({"event_id":batch.through}),
    );
    let book = &r.session("r1").unwrap().notebook;
    assert_eq!(
        book.request.as_ref().map(|b| b.through),
        Some(batch.through)
    );
    assert_eq!(book.failures, 0, "查错了不算这一批失败");
    let q = request(&mut r, &mut w);
    assert!(is_reflection(&q), "接着整理同一批");
    reply(
        &mut r,
        &mut w,
        &q,
        "reflect",
        json!({"through_event":batch.through,"summary":"饿了，先记下。","notes":[]}),
    );
    let book = &r.session("r1").unwrap().notebook;
    assert!(book.request.is_none());
    assert_eq!(book.through_event, batch.through);
}
