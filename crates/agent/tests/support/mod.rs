//! 测试夹具：两地一人的世界、运行器、回复与直接调用工具。
//! 地图、道具库、需求规则与天气规则都用 tests/fixtures 下的副本，不读仓库里的正式数据。
use agent::{
    budget::Limits,
    conversation::{ModelReply, ToolCall},
    memory::MemoryIndex,
    notebook::DocumentsCache,
    runtime::{AgentRequest, ResidentRuntime},
    session::Session,
    tools::{execute, ToolContext, ToolError, ToolOutcome},
};
use kernel::{props::Catalog, Topology, World};
use protocol::NeedRules;
use serde_json::{json, Value};

/// 需求参数的合法范围（fixtures/needs_rules.json）。
pub fn need_rules() -> NeedRules {
    NeedRules::parse(include_str!("../fixtures/needs_rules.json")).unwrap()
}

/// 测试道具库（fixtures/props.json）：床、饮用水桶、变质干粮与一朵野花，编号在 test: 下。
pub fn catalog() -> Catalog {
    Catalog::from_json(include_str!("../fixtures/props.json")).unwrap()
}

pub fn world() -> World {
    let mut data: Value =
        serde_json::from_str(include_str!("../fixtures/two_places.json")).unwrap();
    data["props"] = json!([
        {"id":"board","name":"公告栏","locale":"loc_a","verbs":[{"verb":"阅读公告","duration_minutes":1,"action":{"id":"read_bulletin","label":"阅读公告","duration_minutes":1,"completion":"read_bulletin"}}]},
        {"id":"bench","name":"工作台","locale":"loc_b","verbs":[{"verb":"制作器物","duration_minutes":2}]}
    ]);
    data["props"][0]["readable"] = json!({"work_id":"b1","version":1,"kind":"bulletin","title":"公告","author":"佚名","text":"图书馆今天开放","origin":{"kind":"builtin"}});
    data["props"][0]["board"] = json!("fixture-board");
    data["props"].as_array_mut().unwrap().push(json!({"id":"fixture-board","name":"公告栏支架","locale":"loc_a","bulletin_board":true,"verbs":[{"verb":"查看支架","duration_minutes":1}]}));
    data["props"][0]["verbs"]
        .as_array_mut()
        .unwrap()
        .push(json!({"verb":"查看公告栏","duration_minutes":1}));
    let mut w = World::new(
        Topology::from_json(&data.to_string(), &catalog()).unwrap(),
        420.0,
        need_rules(),
    );
    w.spawn("r1", "阿树", "loc_a").unwrap();
    w
}

pub fn runtime(w: &mut World, limits: Limits) -> ResidentRuntime {
    let mut r = ResidentRuntime::new(limits).unwrap();
    r.register(w, "r1", "我想了解小镇，也会注意吃饭和休息。")
        .unwrap();
    r
}

pub fn tool_call(id: &str, name: &str, arguments: Value) -> ToolCall {
    ToolCall {
        id: id.into(),
        name: name.into(),
        arguments,
    }
}

pub fn model_reply(thought: &str, calls: Vec<ToolCall>) -> ModelReply {
    ModelReply {
        thought: thought.into(),
        calls,
        usage: None,
    }
}

/// 轮询一次，必须恰好有一个请求。
pub fn request(r: &mut ResidentRuntime, w: &mut World) -> AgentRequest {
    let mut requests = r.poll(w, true);
    assert_eq!(requests.len(), 1, "应恰好有一个请求");
    requests.remove(0)
}

/// 轮询到生活决策为止：途中的整理轮次回一份空的整理结果。
pub fn life_request(r: &mut ResidentRuntime, w: &mut World) -> AgentRequest {
    loop {
        let q = request(r, w);
        let through = q.messages.iter().find_map(|m| {
            serde_json::from_str::<Value>(&m.content)
                .ok()
                .and_then(|v| v["reflection_task"]["through"].as_u64())
        });
        let Some(through) = through else {
            return q;
        };
        reply(
            r,
            w,
            &q,
            "reflect",
            json!({"through_event":through,"summary":"整理完毕。","notes":[]}),
        );
    }
}

/// 用自定义自述和多个调用回复；返回是否采纳。
pub fn reply_with(
    r: &mut ResidentRuntime,
    w: &mut World,
    q: &AgentRequest,
    thought: &str,
    calls: Vec<ToolCall>,
) -> bool {
    r.on_reply(
        w,
        &q.actor_id,
        q.stamp.id,
        q.stamp.epoch,
        Ok(model_reply(thought, calls)),
        25,
    )
}

/// 单个调用、固定自述的回复；必须被采纳。
pub fn reply(r: &mut ResidentRuntime, w: &mut World, q: &AgentRequest, name: &str, args: Value) {
    let call = tool_call(&format!("c{}", q.stamp.id), name, args);
    assert!(reply_with(r, w, q, "先看看情况。", vec![call]));
}

/// 不经运行器直接执行一个工具。
pub fn call(
    w: &mut World,
    s: &mut Session,
    name: &str,
    args: Value,
) -> Result<ToolOutcome, ToolError> {
    let mut ctx = ToolContext {
        world: w,
        session: s,
        index: &mut MemoryIndex::new().unwrap(),
        documents: &mut DocumentsCache::default(),
        request: 1,
        call_index: 0,
    };
    execute(&mut ctx, &tool_call(name, name, args))
}

/// 直接执行并要求立即完成。
pub fn call_value(
    w: &mut World,
    s: &mut Session,
    name: &str,
    args: Value,
) -> Result<Value, ToolError> {
    match call(w, s, name, args)? {
        ToolOutcome::Complete(v) => Ok(v),
        ToolOutcome::Pending(_) => panic!("{name} 不应等待"),
    }
}

pub fn read_board(w: &mut World, actor: &str, id: &str, text: &str) {
    let version = w.content_detail("board").unwrap().content.unwrap().version;
    w.revise_bulletin(
        "board",
        version,
        format!("公告{id}"),
        "佚名".into(),
        text.into(),
    )
    .unwrap();
    w.run_actions(
        actor,
        id,
        w.actor(actor).unwrap().actions.revision,
        &serde_json::from_value::<Vec<protocol::ActionDraft>>(
            json!([{"intent":{"verb":"阅读公告"},"prop_id":"board"}]),
        )
        .unwrap(),
    )
    .unwrap();
    w.step(2.0);
}

/// 读过两次公告并完成一次观察的村民与运行器。
pub fn prepared() -> (World, ResidentRuntime) {
    let mut w = world();
    w.enable_agent("r1").unwrap();
    read_board(
        &mut w,
        "r1",
        "first",
        &format!(
            "图书馆今天开放。{}",
            "这是公告当时写的内容，尚未亲自到图书馆核实。".repeat(5)
        ),
    );
    read_board(
        &mut w,
        "r1",
        "second",
        "新公告：图书馆明天维修关闭，后天再开放。",
    );
    let mut r = runtime(&mut w, Limits::default());
    let q = request(&mut r, &mut w);
    reply(&mut r, &mut w, &q, "observe", json!({}));
    (w, r)
}

/// 这些事件里实际读到的原文，作为 reading_quotes。
pub fn quotes(w: &World, actor: &str, ids: &[u64]) -> Value {
    json!(ids
        .iter()
        .filter_map(|id| w
            .contents()
            .reading_result(actor, *id)
            .ok()
            .map(|r| json!({"event_id":id,"text":r.content.text})))
        .take(8)
        .collect::<Vec<_>>())
}

/// 针对当前待整理批次的 reflect 参数。
pub fn update(w: &World, s: &Session, text: &str, status: &str) -> Value {
    let b = s.notebook.request.as_ref().unwrap();
    json!({
        "through_event": b.through,
        "summary": "我读到了两次公告，开放安排随日期变化，需保留时间范围。",
        "notes": [{
            "path": "places/library.md",
            "title": "图书馆开放安排",
            "text": text,
            "event_ids": b.event_ids,
            "status": status,
            "reading_quotes": quotes(w, &s.actor_id, &b.event_ids)
        }]
    })
}
