use crate::support::*;
use agent::{
    budget::Limits,
    conversation::Role,
    memory::{EvidenceSource, MemoryIndex, RecallQuery},
    runtime::ResidentRuntime,
    session::GoalStatus,
};
use protocol::{InteractionCommand as Command, InteractionKind, InteractionStatus};
use serde_json::json;

fn command(w: &mut kernel::World, actor: &str, key: &str, cmd: Command) {
    w.interact(actor, key, w.actor(actor).unwrap().actions.revision, &cmd)
        .unwrap();
}

#[test]
fn chat_turns_restore_and_reject_other_partys_stale_reply() {
    busy_invitation_does_not_cancel_work_until_the_resident_accepts();
    invitation_reply_repairs_format_without_assuming_consent();
    let mut w = world();
    w.spawn("r2", "小禾", "loc_a").unwrap();
    let mut r = runtime(&mut w, Limits::default());
    r.register(&mut w, "r2", "我会独立决定是否参加交谈。")
        .unwrap();
    let requests = r.poll(&mut w, true);
    let first = requests.iter().find(|q| q.actor_id == "r1").unwrap();
    let old_partner = requests.iter().find(|q| q.actor_id == "r2").unwrap();
    reply(
        &mut r,
        &mut w,
        first,
        "offer_invitation",
        json!({"partner_id":"r2","interaction":{"kind":"talk"},"message":"听说图书馆明天关闭"}),
    );
    let invitation = w.interactions().for_actor("r1")[0].id.clone();
    // 邀请在对方请求途中送达，旧请求须先 observe；不能拿旧观察直接同意。
    reply(
        &mut r,
        &mut w,
        old_partner,
        "reply_invitation",
        json!({"interaction_id":invitation,"accept":true,"message":"好"}),
    );
    assert_eq!(
        w.interactions().for_actor("r1")[0].status,
        InteractionStatus::Offered
    );
    // 交谈邀请发出后邀请者本次醒来结束，只有受邀者请求模型。
    let requests = r.poll(&mut w, true);
    assert!(requests.iter().all(|q| q.actor_id == "r2"));
    let receiver = requests.iter().find(|q| q.actor_id == "r2").unwrap();
    reply(
        &mut r,
        &mut w,
        receiver,
        "reply_invitation",
        json!({"interaction_id":invitation,"accept":true,"message":"我愿意聊聊，不过我还没核实"}),
    );
    assert_eq!(
        w.interactions().for_actor("r1")[0].status,
        InteractionStatus::Running
    );
    // 超过原来的五分钟仍在聊天；邀请状态随对方回应返回给邀请者，只有轮到的人请求模型。
    w.step(6.0);
    let q = request(&mut r, &mut w);
    assert_eq!(q.actor_id, "r1");
    let session = r.session("r1").unwrap();
    let offer_result = session
        .messages
        .iter()
        .rev()
        .find(|m| m.role == Role::Tool)
        .unwrap();
    assert!(offer_result.content.contains("\"replied\":true"));
    reply(
        &mut r,
        &mut w,
        &q,
        "interact",
        json!({"operation":"say","interaction_id":invitation,"message":"那我们明天去核实一下。","to":"r2"}),
    );
    let mut fresh = world();
    fresh.spawn("r2", "小禾", "loc_a").unwrap();
    fresh.restore_snapshot(w.snapshot()).unwrap();
    w = fresh;
    r = ResidentRuntime::restore(r.state().clone(), &w).unwrap();
    let next = request(&mut r, &mut w);
    assert_eq!(next.actor_id, "r2");
    reply(
        &mut r,
        &mut w,
        &next,
        "interact",
        json!({"operation":"leave","interaction_id":invitation,"message":"好，我先去吃饭。"}),
    );
    let requests = r.poll(&mut w, true);
    assert_eq!(requests.len(), 2);
    let s = r.session("r2").unwrap();
    let call = format!("c{}", receiver.stamp.id);
    assert_eq!(
        s.messages
            .iter()
            .filter(|m| m.role == Role::Tool && m.call_id.as_ref() == Some(&call))
            .count(),
        1
    );
    assert!(s.pending.is_empty());
    let reported = s
        .memory
        .records
        .iter()
        .find(|m| m.text.contains("图书馆明天关闭"))
        .unwrap();
    assert_eq!(reported.source, EvidenceSource::Reported);
    assert_eq!(reported.confidence, 0.5);
    let mut index = MemoryIndex::new().unwrap();
    let recalled = index
        .recall(
            "r2",
            &s.memory,
            &RecallQuery {
                object: Some("r1".into()),
                ..Default::default()
            },
        )
        .unwrap();
    assert!(recalled
        .iter()
        .any(|m| m.source == EvidenceSource::Reported));
    assert!(index
        .recall("r3", &s.memory, &RecallQuery::default())
        .is_err());
    let mut q = requests
        .iter()
        .find(|q| q.actor_id == "r2")
        .unwrap()
        .clone();
    if let Some(through) = q.messages.iter().find_map(|m| {
        serde_json::from_str::<serde_json::Value>(&m.content)
            .ok()
            .and_then(|v| v["reflection_task"]["through"].as_u64())
    }) {
        reply(
            &mut r,
            &mut w,
            &q,
            "reflect",
            json!({"through_event":through,"summary":"与阿树交谈，消息仍需核实。","notes":[]}),
        );
        q = r
            .poll(&mut w, true)
            .into_iter()
            .find(|q| q.actor_id == "r2")
            .unwrap();
    }
    reply(
        &mut r,
        &mut w,
        &q,
        "set_goal",
        json!({"id":"talked","title":"与阿树聊聊","condition":{"kind":"interaction","interaction_id":invitation},"status":"completed"}),
    );
    assert_eq!(
        r.session("r2").unwrap().goals["talked"].status,
        GoalStatus::Completed
    );
    ResidentRuntime::restore(r.state().clone(), &w).unwrap();
}

fn busy_invitation_does_not_cancel_work_until_the_resident_accepts() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    w.spawn("r2", "打招呼的人", "loc_a").unwrap();
    w.enable_agent("r2").unwrap();
    let q = request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "run_actions",
        json!({"actions":[
            {"intent":{"verb":"停留","duration_minutes":1000}},
            {"intent":{"verb":"停留","duration_minutes":10}}
        ]}),
    );
    w.step(1.);
    let group = w
        .actor("r1")
        .unwrap()
        .actions
        .groups
        .keys()
        .next()
        .unwrap()
        .clone();
    let original_call = r.session("r1").unwrap().pending[0].call().id.clone();
    let invite = |w: &mut kernel::World, id: &str| {
        command(
            w,
            "r2",
            id,
            Command::Offer {
                partner_id: "r1".into(),
                interaction: InteractionKind::Talk,
                message: "方便聊聊吗？".into(),
            },
        )
    };
    invite(&mut w, "busy-no");
    let q = request(&mut r, &mut w);
    assert_eq!(
        w.action_group("r1", &group).unwrap().status,
        protocol::GroupStatus::Running
    );
    assert!(agent::context::paired(&q.messages));
    ResidentRuntime::restore(r.state().clone(), &w).unwrap();
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"interaction_id":"busy-no","accept":false,"message":"我还在忙，稍后吧"}),
    );
    // 名册里「被婉拒」的记号记在发出邀请的人头上（画面上他冒怒气），不记在拒绝的人头上
    let declined = |actor: &str| {
        w.interactions()
            .latest_declined_offer(actor)
            .map(|i| i.id.clone())
    };
    assert_eq!(declined("r2").as_deref(), Some("busy-no"));
    assert_eq!(declined("r1"), None);
    assert!(r.poll(&mut w, true).is_empty());
    assert_eq!(
        w.action_group("r1", &group).unwrap().status,
        protocol::GroupStatus::Running
    );
    r = ResidentRuntime::restore(r.state().clone(), &w).unwrap();
    invite(&mut w, "busy-expire");
    let q = request(&mut r, &mut w);
    assert!(reply_with(&mut r, &mut w, &q, "暂时没有决定", vec![]));
    w.step(601.);
    assert!(r.poll(&mut w, true).is_empty());
    assert_eq!(
        w.interactions().of("r1", "busy-expire").unwrap().status,
        InteractionStatus::Expired
    );
    assert_eq!(
        w.action_group("r1", &group).unwrap().status,
        protocol::GroupStatus::Running
    );
    invite(&mut w, "busy-yes");
    let q = request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"interaction_id":"busy-yes","accept":true,"message":"这回可以，我先停下"}),
    );
    r.poll(&mut w, true);
    assert_eq!(w.active_chat("r1").unwrap().id, "busy-yes");
    let g = w.action_group("r1", &group).unwrap();
    assert_eq!(g.status, protocol::GroupStatus::Interrupted);
    assert_eq!(g.results.len(), 2);
    let s = r.session("r1").unwrap();
    assert!(s.pending.is_empty());
    assert_eq!(
        s.messages
            .iter()
            .filter(|m| m.role == Role::Tool && m.call_id.as_ref() == Some(&original_call))
            .count(),
        1
    );
    assert!(agent::context::paired(&s.messages));
    ResidentRuntime::restore(r.state().clone(), &w).unwrap();
}

fn invitation_reply_repairs_format_without_assuming_consent() {
    let mut w = world();
    w.spawn("r2", "邀请者", "loc_a").unwrap();
    w.enable_agent("r2").unwrap();
    let mut r = runtime(&mut w, Limits::default());
    command(
        &mut w,
        "r2",
        "repair-invite",
        Command::Offer {
            partner_id: "r1".into(),
            interaction: InteractionKind::Talk,
            message: "聊聊？".into(),
        },
    );
    let q = request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"partner_id":"r2","interaction":{"kind":"talk"},"message":"当然可以"}),
    );
    assert_eq!(
        w.interactions().of("r1", "repair-invite").unwrap().status,
        InteractionStatus::Offered
    );
    let q = request(&mut r, &mut w);
    // 格式错误退回时告诉模型可回应的邀请编号。
    assert!(q.messages.iter().any(|m| {
        serde_json::from_str::<serde_json::Value>(&m.content)
            .is_ok_and(|v| v["error_kind"] == "invalid_arguments")
            && m.content.contains("repair-invite")
    }));
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"interaction_id":"repair-invite","message":"当然可以"}),
    );
    assert!(r.poll(&mut w, true).is_empty());
    assert_eq!(
        r.session("r1")
            .unwrap()
            .invitation_reply_failure
            .as_ref()
            .unwrap()
            .attempts,
        2
    );
    r = ResidentRuntime::restore(r.state().clone(), &w).unwrap();
    assert_eq!(
        r.session("r1")
            .unwrap()
            .invitation_reply_failure
            .as_ref()
            .unwrap()
            .attempts,
        2
    );
    w.step(31.0);
    let q = request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"interaction_id":"repair-invite","accept":false,"message":"现在不方便"}),
    );
    assert_eq!(
        w.interactions().of("r1", "repair-invite").unwrap().status,
        InteractionStatus::Declined
    );
    assert!(r.session("r1").unwrap().invitation_reply_failure.is_none());
}

#[test]
fn invalid_chat_id_reports_the_real_id_without_sending_the_rejected_message() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    w.spawn("r2", "小禾", "loc_a").unwrap();
    w.enable_agent("r2").unwrap();
    command(
        &mut w,
        "r1",
        "real-chat",
        Command::Offer {
            partner_id: "r2".into(),
            interaction: InteractionKind::Talk,
            message: "聊聊？".into(),
        },
    );
    command(
        &mut w,
        "r2",
        "accept",
        Command::Reply {
            interaction_id: "real-chat".into(),
            accept: true,
            message: "好".into(),
        },
    );
    let q = request(&mut r, &mut w);
    assert_eq!(q.stamp.kind, protocol::RequestKind::Chat);
    let before = serde_json::to_value(w.snapshot()).unwrap();
    // 只发工具调用，不带 support::reply 默认自述；自述会合法写入世界日记。
    assert!(reply_with(
        &mut r,
        &mut w,
        &q,
        "",
        vec![tool_call(
            "wrong-chat-id",
            "interact",
            json!({"operation":"say","interaction_id":"chat.id","message":"今天一起散步吧。"}),
        )],
    ));
    assert_eq!(before, serde_json::to_value(w.snapshot()).unwrap());
    assert!(w.chat_turn("r1"));
    let retry = request(&mut r, &mut w);
    assert!(retry.messages.iter().any(|m| {
        m.role == Role::Tool
            && serde_json::from_str::<serde_json::Value>(&m.content)
                .is_ok_and(|v| v["error_kind"] == "world")
            && m.content.contains("real-chat")
    }));
    // 本地结构化交谈必须显式 say/listen/leave，不能把心声中的告辞当成离场。
    let empty_reply = json!({"choices":[{"finish_reason":"stop","message":{"content":
        json!({"thought":"我这就去散步。","calls":[]}).to_string()
    }}]});
    assert!(agent::completion::parse_local_tool_reply(&empty_reply, &retry).is_err());
    assert!(w.chat_turn("r1"));
    let corrected = agent::completion::parse_local_tool_reply(
        &json!({"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":
            json!({"thought":"","calls":[{"name":"interact","arguments":{
                "operation":"say","interaction_id":"real-chat","message":"今天一起散步吧。"
            }}]}).to_string()
        }}]}),
        &retry,
    )
    .unwrap();
    assert!(r.on_reply(
        &mut w,
        &retry.actor_id,
        retry.stamp.id,
        retry.stamp.epoch,
        Ok(corrected),
        1,
    ));
    assert!(w.chat_turn("r2"));
    let chat = w.active_chat("r1").unwrap().chat.as_ref().unwrap();
    assert_eq!(chat.entries.last().unwrap().text, "今天一起散步吧。");

    // 下一轮只追加变化，末尾观察不再重复 chat.id；本地提示仍须从本场完整状态取编号。
    command(
        &mut w,
        "r2",
        "partner-follow-up",
        Command::Say {
            interaction_id: "real-chat".into(),
            message: "好，散步时再聊。".into(),
            to: None,
        },
    );
    let next = request(&mut r, &mut w);
    let latest_user = next
        .messages
        .iter()
        .rev()
        .find(|m| m.role == Role::User)
        .unwrap();
    let delta: serde_json::Value = serde_json::from_str(&latest_user.content).unwrap();
    assert!(delta["chat"].get("id").is_none());
    assert!(delta["chat"]["new_entries"].is_array());
    let original = serde_json::to_value(&next).unwrap();
    let shared = agent::completion::tool_request_body(&next, "qwen3.5:2b");
    let local = agent::completion::local_tool_request_body(&next, "qwen3.5:2b");
    let local_system = local["messages"][0]["content"].as_str().unwrap();
    assert!(local_system.contains(r#"{"interaction_id":"real-chat"}"#));
    assert_eq!(
        local["response_format"]["json_schema"]["schema"]["properties"]["calls"]["minItems"],
        1
    );
    let tail = local["messages"].as_array().unwrap().last().unwrap();
    let current: serde_json::Value =
        serde_json::from_str(tail["content"].as_str().unwrap()).unwrap();
    assert_eq!(current["decision_state"]["chat"]["id"], "real-chat");
    assert_eq!(current["decision_state"]["chat"]["turn"], "r1");
    assert_eq!(
        current["decision_state"]["chat"]["lines"],
        delta["chat"]["lines"]
    );
    assert!(current["decision_state"]["chat"].get("entries").is_none());
    assert!(current["decision_state"]["needs"].is_array());
    let chat_calls = local["response_format"]["json_schema"]["schema"]["properties"]["calls"]
        ["items"]["anyOf"]
        .as_array()
        .unwrap();
    assert_eq!(chat_calls.len(), 1);
    assert_eq!(chat_calls[0]["properties"]["name"]["const"], "interact");
    let operations = chat_calls[0]["properties"]["arguments"]["anyOf"]
        .as_array()
        .unwrap();
    // say、listen、leave，以及提议一起走和回答提议
    assert_eq!(operations.len(), 6);
    for operation in operations {
        assert_eq!(operation["additionalProperties"], false);
        assert_eq!(
            operation["properties"]["interaction_id"]["const"],
            "real-chat"
        );
        let required = operation["required"].as_array().unwrap();
        assert!(required.contains(&json!("operation")));
        assert!(required.contains(&json!("interaction_id")));
        if operation["properties"]["operation"]["const"] == "say" {
            assert!(required.contains(&json!("message")));
        }
    }
    assert!(local.get("tools").is_none());
    // 转换只发生在本地传输副本，原请求、存档历史和公共工具协议不被改写。
    assert_eq!(serde_json::to_value(&next).unwrap(), original);
    assert_eq!(
        agent::completion::tool_request_body(&next, "qwen3.5:2b"),
        shared
    );

    // 从真实阅读经历触发整理，整理请求不应收到移动或聊天的指导。
    let (mut reflection_world, mut reflection_runtime) = prepared();
    let reflection = request(&mut reflection_runtime, &mut reflection_world);
    assert_eq!(reflection.stamp.kind, protocol::RequestKind::Reflection);
    let reflection_local = agent::completion::local_tool_request_body(&reflection, "qwen3.5:2b");
    assert_eq!(
        reflection_local["response_format"]["json_schema"]["schema"]["properties"]["calls"]
            ["minItems"],
        0
    );
    assert!(
        agent::completion::parse_local_tool_reply(&empty_reply, &reflection)
            .unwrap()
            .calls
            .is_empty()
    );
    let reflection_calls = reflection_local["response_format"]["json_schema"]["schema"]
        ["properties"]["calls"]["items"]["anyOf"]
        .as_array()
        .unwrap();
    let names: Vec<_> = reflection_calls
        .iter()
        .map(|call| call["properties"]["name"]["const"].as_str().unwrap())
        .collect();
    assert!(names.contains(&"reflect"));
    assert!(!names.contains(&"move_to") && !names.contains(&"use_prop"));
    let system = reflection_local["messages"][0]["content"].as_str().unwrap();
    assert!(!system.contains("move_to") && !system.contains("use_prop"));
}

#[test]
fn chat_turn_sees_what_was_heard_since_the_summary() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    w.spawn("r2", "小禾", "loc_a").unwrap();
    w.spawn("r3", "老周", "loc_a").unwrap();
    w.enable_agent("r2").unwrap();
    w.enable_agent("r3").unwrap();
    // 第一场：小禾来提醒，阿树回绝了邀请。这句话只在生活会话原文里，还没折叠进摘要。
    let warn = Command::Offer {
        partner_id: "r1".into(),
        interaction: InteractionKind::Talk,
        message: "有人让我拿刀害你，你当心点".into(),
    };
    command(&mut w, "r2", "warn", warn);
    let q = life_request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"interaction_id":"warn","accept":false,"message":"知道了，改天细说"}),
    );
    // 第二场：老周来问，轮到阿树发言时得记得刚才的提醒；本场的台词不重复。
    let ask = Command::Offer {
        partner_id: "r1".into(),
        interaction: InteractionKind::Talk,
        message: "刀的事你听说了吗？".into(),
    };
    command(&mut w, "r3", "ask", ask);
    let q = life_request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"interaction_id":"ask","accept":true,"message":"你说哪件？"}),
    );
    let say = Command::Say {
        interaction_id: "ask".into(),
        message: "就是有人要动刀那件".into(),
        to: None,
    };
    command(&mut w, "r3", "ask-say", say);
    let turn = request(&mut r, &mut w);
    assert_eq!(turn.stamp.kind, protocol::RequestKind::Chat);
    let body: serde_json::Value =
        serde_json::from_str(&turn.messages.last().unwrap().content).unwrap();
    let recent: Vec<_> = body["recent_events"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e.as_str().unwrap())
        .collect();
    assert!(recent.iter().any(|e| e.contains("有人让我拿刀害你")));
    assert!(recent.iter().all(|e| !e.contains("刀的事你听说了吗")));
}

/// 交谈轮次的兜底：一次回复没有调用就倾听；格式错误或模型掉线连续两次后代为倾听。
/// 都只交出发言权，不替村民说话，也不搁置，交谈照常轮到对方。
#[test]
fn chat_turn_fallbacks_yield_the_turn_without_speaking_for_the_resident() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    w.spawn("r2", "小禾", "loc_a").unwrap();
    w.enable_agent("r2").unwrap();
    let offer = Command::Offer {
        partner_id: "r2".into(),
        interaction: InteractionKind::Talk,
        message: "来聊聊".into(),
    };
    command(&mut w, "r1", "chat", offer);
    let accept = Command::Reply {
        interaction_id: "chat".into(),
        accept: true,
        message: "好".into(),
    };
    command(&mut w, "r2", "accept", accept);
    // 邀请与回应的话已是开场台词；之后本人不该再有任何台词。
    let opening = w
        .interactions()
        .of("r1", "chat")
        .unwrap()
        .chat
        .as_ref()
        .unwrap()
        .entries
        .len();
    let partner_speaks = |w: &mut kernel::World, text: &str| {
        assert!(w.chat_turn("r2"), "发言权应已交给对方");
        let say = Command::Say {
            interaction_id: "chat".into(),
            message: text.into(),
            to: None,
        };
        command(w, "r2", text, say);
        assert!(w.chat_turn("r1"));
    };
    let fail = |r: &mut ResidentRuntime, w: &mut kernel::World| {
        let q = request(r, w);
        assert_eq!(q.stamp.kind, protocol::RequestKind::Chat);
        r.on_reply(
            w,
            "r1",
            q.stamp.id,
            q.stamp.epoch,
            Err(agent::completion::ModelError::Network("连接被拒绝".into())),
            5,
        );
    };
    let bad_format = |r: &mut ResidentRuntime, w: &mut kernel::World| {
        let q = request(r, w);
        let call = tool_call("bad", "interact", json!({"operation":"say"}));
        assert!(reply_with(r, w, &q, "", vec![call]));
    };

    // 一次回复没有任何调用：当场倾听。
    let q = request(&mut r, &mut w);
    assert!(reply_with(&mut r, &mut w, &q, "先听听", vec![]));
    partner_speaks(&mut w, "你先说吧");
    // 格式错误：第一次留着发言权重试，第二次代为倾听。
    bad_format(&mut r, &mut w);
    assert!(w.chat_turn("r1"));
    bad_format(&mut r, &mut w);
    partner_speaks(&mut w, "那我接着说");
    // 模型掉线：同样重试一次，再失败就代为倾听，交谈不停。
    fail(&mut r, &mut w);
    assert!(w.chat_turn("r1"), "第一次失败后立即重试");
    fail(&mut r, &mut w);
    assert!(w.chat_turn("r2"));
    let s = r.session("r1").unwrap();
    assert!(s.pause_reason().is_none() && s.sleep().is_none());
    let chat = w.interactions().of("r1", "chat").unwrap();
    assert_eq!(chat.status, InteractionStatus::Running);
    let entries = &chat.chat.as_ref().unwrap().entries[opening..];
    assert!(
        !entries
            .iter()
            .any(|e| e.actor == "r1" && e.kind == protocol::ChatEntryKind::Speech),
        "兜底只交出发言权，不产生台词"
    );
}

/// 甲乙两处各是一间屋，甲处 (5,2) 有门通到乙处 (2,2)；化身从甲处落脚点进场。
fn two_rooms() -> kernel::World {
    use kernel::avatar::{Area, Portal, Spot, Surface, WalkMap};
    let spot = |locale: &str, x: f64, y: f64| Spot {
        locale: locale.into(),
        space: locale.into(),
        position: [x, y],
    };
    let mut w = world();
    w.topo.entry =
        Some(serde_json::from_value(json!({"locale":"loc_a","station":"st_a"})).unwrap());
    w.walk_map = Some(std::sync::Arc::new(WalkMap {
        version: 1,
        svg_units_per_metre: 12.,
        metres_per_minute: 12.,
        surfaces: ["loc_a", "loc_b"]
            .into_iter()
            .map(|id| Surface {
                locale: id.into(),
                space: id.into(),
                area: Area::Rect {
                    min: [0., 0.],
                    max: [20., 20.],
                },
            })
            .collect(),
        stations: [
            ("st_a".into(), spot("loc_a", 2., 2.)),
            ("st_b".into(), spot("loc_b", 2., 2.)),
        ]
        .into(),
        portals: vec![Portal {
            id: "door".into(),
            label: "门".into(),
            from: spot("loc_a", 5., 2.),
            to: spot("loc_b", 2., 2.),
        }],
        ..Default::default()
    }));
    w
}

/// 答应同行后跟着走的村民一路不请求模型，到了地方才醒来，观察里写着到了哪儿。
#[test]
fn following_resident_stays_quiet_until_the_walk_arrives() {
    let mut w = two_rooms();
    let mut r = runtime(&mut w, Limits::default());
    w.spawn("r2", "何青", "loc_a").unwrap();
    w.enable_agent("r2").unwrap();
    command(
        &mut w,
        "r2",
        "walk",
        Command::Offer {
            partner_id: "r1".into(),
            interaction: InteractionKind::Walk {
                leader: "r2".into(),
                locale: Some("loc_b".into()),
            },
            message: "跟我去乙地看看。".into(),
        },
    );
    let q = life_request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"interaction_id":"walk","accept":true,"message":"行，我跟着你。"}),
    );
    assert_eq!(w.following("r1"), Some("r2"));
    let mut quiet = 0;
    while w.interactions().of("r1", "walk").unwrap().status == InteractionStatus::Running {
        assert!(r.poll(&mut w, true).is_empty(), "跟着走的路上不请求模型");
        w.step(0.1);
        quiet += 1;
        assert!(quiet < 200, "同行应该在几分钟内走到");
    }
    assert_eq!(
        w.interactions().of("r1", "walk").unwrap().status,
        InteractionStatus::Succeeded
    );
    assert_eq!(w.actor("r1").unwrap().locus.locale, "loc_b");
    let woke = request(&mut r, &mut w);
    assert!(woke
        .messages
        .last()
        .unwrap()
        .content
        .contains("到了乙地，同行结束"));
}

/// 村民带路、跟着的是自己走的化身：化身站着没跟上，带路人到了也不醒来另作打算（雾港凶案里
/// 何青到了苏晴家就对着空屋子说「到了」）；等满几分钟算没跟上、同行结束，他才醒来看到实际结果。
#[test]
fn resident_leader_waits_for_the_avatar_until_the_walk_really_ends() {
    let mut w = two_rooms();
    let mut r = runtime(&mut w, Limits::default());
    let look = protocol::Appearance {
        marker: "旅".into(),
        color: "#387963".into(),
        profile: None,
        look: None,
    };
    w.avatar_enter("旅人", look).unwrap();
    let rev = w.avatar().unwrap().actions.revision;
    w.avatar_interact(
        "walk",
        rev,
        &Command::Offer {
            partner_id: "r1".into(),
            interaction: InteractionKind::Walk {
                leader: "r1".into(),
                locale: Some("loc_b".into()),
            },
            message: "你带我去乙地看看吧。".into(),
        },
    )
    .unwrap();
    let q = life_request(&mut r, &mut w);
    reply(
        &mut r,
        &mut w,
        &q,
        "reply_invitation",
        json!({"interaction_id":"walk","accept":true,"message":"走，我带你去。"}),
    );
    let mut ticks = 0;
    while w.interactions().of("r1", "walk").unwrap().status == InteractionStatus::Running {
        assert!(
            r.poll(&mut w, true).is_empty(),
            "化身没跟上时带路人原地等，不请求模型"
        );
        w.step(0.1);
        ticks += 1;
        assert!(ticks < 200, "没跟上的人应该在几分钟内退出同行");
    }
    assert_eq!(w.actor("r1").unwrap().locus.locale, "loc_b");
    assert_eq!(w.avatar().unwrap().locus.locale, "loc_a");
    let walk = w.interactions().of("r1", "walk").unwrap();
    assert_eq!(walk.status, InteractionStatus::Interrupted);
    let woke = request(&mut r, &mut w);
    assert!(woke
        .messages
        .last()
        .unwrap()
        .content
        .contains("旅人没跟上阿树，同行结束"));
}

/// 带路的路上什么时候存档都读得回来。世界替带路人排的「前往」不经他自己的工具调用，会话里
/// 没有记录；读档核对曾因此拒绝整个世界（大逃杀荒岛的存档停在说好一起走的那一刻，之后再也
/// 打不开）。跟着的人半路不跟了、同行先结束，带路人照样走到地方，这一段也要读得回来。
#[test]
fn a_walk_saved_at_any_moment_loads_again() {
    let mut w = two_rooms();
    let mut r = runtime(&mut w, Limits::default());
    w.spawn("r2", "何青", "loc_a").unwrap();
    r.register(&mut w, "r2", "我熟悉这一带，常给人带路。")
        .unwrap();
    command(
        &mut w,
        "r2",
        "walk",
        Command::Offer {
            partner_id: "r1".into(),
            interaction: InteractionKind::Walk {
                leader: "r2".into(),
                locale: Some("loc_b".into()),
            },
            message: "跟我去乙地看看。".into(),
        },
    );
    command(
        &mut w,
        "r1",
        "walk-yes",
        Command::Reply {
            interaction_id: "walk".into(),
            accept: true,
            message: "行，我跟着你。".into(),
        },
    );
    let leading = |w: &kernel::World| {
        w.action_group("r2", "walk/lead")
            .is_some_and(|g| g.status == protocol::GroupStatus::Running)
    };
    assert!(leading(&w), "说好了目的地，带路人直接动身");
    let mut ticks = 0;
    while leading(&w) {
        if ticks == 1 {
            command(
                &mut w,
                "r1",
                "walk-off",
                Command::Leave {
                    interaction_id: "walk".into(),
                    message: "我先不去了。".into(),
                },
            );
            assert_ne!(
                w.interactions().of("r1", "walk").unwrap().status,
                InteractionStatus::Running
            );
            assert!(leading(&w), "同行结束了，带路人还在路上");
        }
        let saved_world = serde_json::to_value(w.snapshot()).unwrap();
        let saved_runtime = serde_json::to_value(r.state()).unwrap();
        let mut loaded = two_rooms();
        loaded
            .restore_snapshot(serde_json::from_value(saved_world).unwrap())
            .unwrap();
        if let Err(error) =
            ResidentRuntime::restore(serde_json::from_value(saved_runtime).unwrap(), &loaded)
        {
            panic!("第 {ticks} 拍的存档读不回来：{error}");
        }
        w.step(0.1);
        ticks += 1;
        assert!(ticks < 200, "带路人应该在几分钟内走到");
    }
    assert_eq!(w.actor("r2").unwrap().locus.locale, "loc_b");
}

/// 目标里提到的人来了：正在停留的人提前结束停留醒来，不必站满提前排好的时长。
#[test]
fn a_planned_stay_ends_when_someone_from_the_goals_shows_up() {
    let mut w = world();
    let mut r = runtime(&mut w, Limits::default());
    w.spawn("r2", "何青", "loc_b").unwrap();
    w.enable_agent("r2").unwrap();
    let q = life_request(&mut r, &mut w);
    let goal = tool_call(
        "goal",
        "set_goal",
        json!({"id":"等人","title":"等何青来说清楚后墙根的事","condition":{"kind":"action","verb":"停留","locale":"loc_a"},"status":"active"}),
    );
    let stay = tool_call(
        "stay",
        "run_actions",
        json!({"actions":[{"intent":{"verb":"停留","duration_minutes":120}}]}),
    );
    assert!(reply_with(
        &mut r,
        &mut w,
        &q,
        "在这儿等她。",
        vec![goal, stay]
    ));
    w.step(1.);
    assert!(r.poll(&mut w, true).is_empty());
    let rev = w.actor("r2").unwrap().actions.revision;
    w.run_actions(
        "r2",
        "come",
        rev,
        &serde_json::from_value::<Vec<protocol::ActionDraft>>(
            json!([{"intent":{"verb":"前往","locale":"loc_a"}}]),
        )
        .unwrap(),
    )
    .unwrap();
    for _ in 0..40 {
        w.step(0.1);
    }
    assert_eq!(w.actor("r2").unwrap().locus.locale, "loc_a");
    let woke = request(&mut r, &mut w);
    let body = &woke.messages.last().unwrap().content;
    assert!(body.contains("何青来了"), "醒来时看到她来了");
    let group = w.action_group("r1", "a1-1").unwrap();
    assert_eq!(group.status, protocol::GroupStatus::Interrupted);
}
