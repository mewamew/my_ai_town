use crate::common;
use kernel::{KernelError, World};
use protocol::{
    Interaction, InteractionCommand as Command, InteractionKind as Kind,
    InteractionStatus as Status,
};
use serde_json::json;

fn world() -> World {
    let topo = common::two_places(json!([
        {"id":"board","name":"公告栏","locale":"loc_a","board":"fixture-board",
         "readable":{"work_id":"b1","version":1,"kind":"bulletin","title":"公告","author":"佚名","text":"图书馆今天开放","origin":{"kind":"builtin"}},
         "verbs":[{"verb":"阅读公告","duration_minutes":1,"action":{"id":"read_bulletin","label":"阅读公告","duration_minutes":1,"completion":"read_bulletin"}}]},
        {"id":"bench","name":"工作台","locale":"loc_a","verbs":[{"verb":"制作器物","duration_minutes":2},{"verb":"取用木料","duration_minutes":1}]},
        {"id":"food","name":"餐台","locale":"loc_a","verbs":[{"verb":"吃点心","duration_minutes":20,"effects":{"饿":-1},"action":{"id":"snack","label":"吃点心","duration_minutes":20,"during":[{"kind":"restore_need","need":"fullness","per_minute":1.25,"pause_decay":false}],"completion":"activity","conditions":[]}},{"verb":"吃饭","duration_minutes":30,"effects":{"饿":-2},"action":{"id":"eat","label":"吃饭","duration_minutes":30,"during":[{"kind":"restore_need","need":"fullness","per_minute":1.6666666666666667,"pause_decay":false}],"completion":"meal","conditions":["meal_window"]}}]},
        {"id":"fixture-board","name":"公告栏支架","locale":"loc_a","bulletin_board":true,"verbs":[{"verb":"查看支架","duration_minutes":1}]}
    ]));
    common::world_with(
        topo,
        600.0,
        &[
            ("r1", "阿树", "loc_a"),
            ("r2", "小禾", "loc_a"),
            ("r3", "旁观者", "loc_a"),
        ],
    )
}
fn command(
    w: &mut World,
    actor: &str,
    id: &str,
    command: Command,
) -> Result<Interaction, KernelError> {
    w.interact(
        actor,
        id,
        w.actor(actor).unwrap().actions.revision,
        &command,
    )
}
fn offer(w: &mut World, id: &str, kind: Kind) -> Interaction {
    command(
        w,
        "r1",
        id,
        Command::Offer {
            partner_id: "r2".into(),
            interaction: kind,
            message: "明天图书馆会关闭，这是我的听说。".into(),
        },
    )
    .unwrap()
}
fn reply(w: &mut World, id: &str, accept: bool) -> Interaction {
    command(
        w,
        "r2",
        "reply",
        Command::Reply {
            interaction_id: id.into(),
            accept,
            message: if accept { "好" } else { "现在不想" }.into(),
        },
    )
    .unwrap()
}
/// 本人看到的聊天，序列化成文本方便查找台词。
fn observation(w: &World, actor: &str) -> String {
    let item = w.interactions().of(actor, "chat").unwrap();
    serde_json::to_string(&kernel::interactions::Interactions::observation(
        actor, item,
    ))
    .unwrap()
}
fn restore(w: &World) -> World {
    common::restore(w, world())
}

#[test]
fn three_people_join_speak_leave_and_only_hear_their_own_interval() {
    let mut w = world();
    offer(&mut w, "chat", Kind::Talk);
    // 旧存档仍按原到期时间恢复，新的慢模型回复可超过旧的 30 分钟限制。
    let mut legacy = serde_json::to_value(w.snapshot()).unwrap();
    let invitation = &mut legacy["interactions"]["chat"];
    invitation["expires_at"] = json!(invitation["created_at"].as_f64().unwrap() + 30.0);
    let mut old = world();
    old.restore_snapshot(serde_json::from_value(legacy).unwrap())
        .unwrap();
    old.step(30.0);
    assert_eq!(
        old.interactions().of("r1", "chat").unwrap().status,
        Status::Expired
    );
    restore(&old);
    w.step(300.0);
    w = restore(&w);
    assert_eq!(
        w.interactions().of("r1", "chat").unwrap().status,
        Status::Offered
    );
    reply(&mut w, "chat", true);
    command(
        &mut w,
        "r1",
        "first",
        Command::Say {
            interaction_id: "chat".into(),
            message: "只有我们两人听过的前一句".into(),
            to: Some("r2".into()),
        },
    )
    .unwrap();
    assert!(w.interactions().of("r3", "chat").is_none());
    assert_eq!(w.nearby_chats("r3").len(), 1);
    command(
        &mut w,
        "r3",
        "join",
        Command::Join {
            interaction_id: "chat".into(),
            message: "我也来聊聊".into(),
        },
    )
    .unwrap();
    for id in ["r1", "r2", "r3"] {
        assert_eq!(w.actor(id).unwrap().current.participants.len(), 3);
    }
    assert!(!observation(&w, "r3").contains("只有我们两人"));
    assert!(command(
        &mut w,
        "r1",
        "wrong-turn",
        Command::Say {
            interaction_id: "chat".into(),
            message: "抢话".into(),
            to: None
        }
    )
    .is_err());
    command(
        &mut w,
        "r2",
        "answer",
        Command::Say {
            interaction_id: "chat".into(),
            message: "大家想喝什么？".into(),
            to: Some("r3".into()),
        },
    )
    .unwrap();
    assert!(w.chat_turn("r3"));
    command(
        &mut w,
        "r3",
        "answer",
        Command::Say {
            interaction_id: "chat".into(),
            message: "我想喝拿铁".into(),
            to: None,
        },
    )
    .unwrap();
    w = restore(&w);
    command(
        &mut w,
        "r1",
        "leave",
        Command::Leave {
            interaction_id: "chat".into(),
            message: "先走了".into(),
        },
    )
    .unwrap();
    assert_eq!(
        w.interactions().of("r2", "chat").unwrap().status,
        Status::Running
    );
    assert!(w.actor("r1").unwrap().interaction_available());
    assert!(w.chat_turn("r2"));
    command(
        &mut w,
        "r2",
        "after",
        Command::Say {
            interaction_id: "chat".into(),
            message: "离开后才说的内容".into(),
            to: None,
        },
    )
    .unwrap();
    assert!(!observation(&w, "r1").contains("离开后才说"));
    assert!(!w
        .actor("r1")
        .unwrap()
        .journal
        .events
        .iter()
        .any(|e| e.text.contains("离开后才说")));
    command(
        &mut w,
        "r3",
        "leave",
        Command::Leave {
            interaction_id: "chat".into(),
            message: "再见".into(),
        },
    )
    .unwrap();
    assert_eq!(
        w.interactions().of("r2", "chat").unwrap().status,
        Status::Succeeded
    );
    assert!(w.actor("r2").unwrap().interaction_available());
    let history =
        serde_json::to_value(w.chat_history("r1", "history".into(), Some("chat".into()), 0))
            .unwrap();
    assert!(
        history["entries"]
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e["text"] == "离开后才说的内容"),
        "玩家历史可看完整过程，Agent 仍受听见范围限制"
    );
    restore(&w);
}

/// 编号靠前的人被搭话（玩家的编号排在所有村民前面）：说完一轮的最后一句，该对方回话，
/// 不会又轮到自己，让对方干等。
#[test]
fn whoever_ends_a_round_does_not_get_the_next_turn() {
    let mut w = world();
    command(
        &mut w,
        "r2",
        "chat",
        Command::Offer {
            partner_id: "r1".into(),
            interaction: Kind::Talk,
            message: "你刚才在哪儿？".into(),
        },
    )
    .unwrap();
    command(
        &mut w,
        "r1",
        "reply",
        Command::Reply {
            interaction_id: "chat".into(),
            accept: true,
            message: "好。".into(),
        },
    )
    .unwrap();
    for (speaker, line) in [("r2", "我一直在院里。"), ("r1", "我知道是你。")] {
        assert!(w.chat_turn(speaker));
        command(
            &mut w,
            speaker,
            "say",
            Command::Say {
                interaction_id: "chat".into(),
                message: line.into(),
                to: None,
            },
        )
        .unwrap();
    }
    assert!(w.chat_turn("r2"), "该被指认的人回话");
    assert!(!w.chat_turn("r1"));
}

#[test]
fn service_uses_one_prop_and_only_diners_gain_fullness() {
    let mut w = world();
    w.set_need_values("r2", Some(50.0), None).unwrap();
    offer(
        &mut w,
        "meal",
        Kind::Serve {
            prop_id: "food".into(),
            verb: "吃点心".into(),
        },
    );
    reply(&mut w, "meal", true);
    assert_eq!(w.prop_occupants("food"), vec!["r1", "r2"]);
    common::run(
        &mut w,
        "r3",
        "competing",
        json!({"intent":{"verb":"吃点心"},"prop_id":"food"}),
    )
    .unwrap();
    w.step(10.0);
    assert_eq!(
        w.action_group("r3", "competing").unwrap().status,
        protocol::GroupStatus::Failed
    );
    assert!((w.actor("r2").unwrap().needs.fullness.value - 62.0).abs() < 1e-6);
    assert!((w.actor("r1").unwrap().needs.fullness.value - 74.5).abs() < 1e-6);
    w = restore(&w);
    w.step(10.0);
    assert_eq!(
        w.interactions().of("r1", "meal").unwrap().status,
        Status::Succeeded
    );
    assert!((w.actor("r2").unwrap().needs.fullness.value - 74.0).abs() < 1e-6);
    assert!(w.prop_occupants("food").is_empty());
}

/// 嘴上说把身上的东西给对方，东西还在说的人身上：两人各收到一条通知，说「不给」的不算，
/// 同样的话三小时里只提醒一次（第四局骆川几次说把饼干给了苏蔓，三块都自己吃了，苏蔓饿死）。
#[test]
fn saying_you_give_something_leaves_it_with_the_speaker_and_both_are_told() {
    let mut w = world();
    let biscuits: kernel::props::Definition = serde_json::from_value(json!({
        "id":"player:biscuits","version":1,"name":"压缩饼干","portable":true,"stack_limit":5,"actions":[]
    }))
    .unwrap();
    let tube: kernel::props::Definition = serde_json::from_value(json!({
        "id":"player:tube","version":1,"name":"竹筒水","portable":true,"actions":[]
    }))
    .unwrap();
    w.place_prop(
        serde_json::from_value(json!({
            "instance":{"id":"t1","definition":tube.reference(),"locale":"loc_a"},
            "definition":tube
        }))
        .unwrap(),
    )
    .unwrap();
    for id in ["b1", "b2"] {
        w.place_prop(
            serde_json::from_value(json!({
                "instance":{"id":id,"definition":biscuits.reference(),"locale":"loc_a"},
                "definition":biscuits
            }))
            .unwrap(),
        )
        .unwrap();
    }
    let pick = protocol::InventoryAction::PickUp {
        items: vec!["b1".into(), "b2".into(), "t1".into()],
    };
    common::run(
        &mut w,
        "r1",
        "pick",
        json!({"intent":{"verb":pick.label()},"inventory":pick}),
    )
    .unwrap();
    common::finish(&mut w, "r1", "pick");
    assert!(w.inventory().carried_by("b1", "r1"));
    offer(&mut w, "chat", Kind::Talk);
    reply(&mut w, "chat", true);
    let notices = |w: &World, id: &str| -> Vec<String> {
        w.actor(id)
            .unwrap()
            .journal
            .events_after(0)
            .iter()
            .filter(|e| e.kind == protocol::FactKind::Notice)
            .map(|e| e.text.clone())
            .collect()
    };
    let before = (notices(&w, "r1").len(), notices(&w, "r2").len());
    let say = |w: &mut World, who: &str, line: &str| {
        command(
            w,
            who,
            "say",
            Command::Say {
                interaction_id: "chat".into(),
                message: line.into(),
                to: None,
            },
        )
        .unwrap();
    };
    say(&mut w, "r1", "饼干不给你，自己找去。");
    say(&mut w, "r2", "那算了。");
    say(&mut w, "r1", "饼干分你一块？想都别想。");
    say(&mut w, "r2", "行。");
    // 「水线归你」说的是看水的差事，不是身上的竹筒水（第五局误认过）
    say(&mut w, "r1", "水线归你，我不抢。");
    say(&mut w, "r2", "好。");
    assert_eq!((notices(&w, "r1").len(), notices(&w, "r2").len()), before);

    say(&mut w, "r1", "行，一块饼干给你，先垫垫。");
    let mine = notices(&w, "r1");
    let theirs = notices(&w, "r2");
    assert!(mine
        .last()
        .unwrap()
        .ends_with("你说要把压缩饼干给小禾，东西还在你身上：交谈结束后发赠予邀请交给小禾，小禾接受了才算给了；能对别人用的东西，也可以直接拿它对小禾用。"));
    assert!(theirs
        .last()
        .unwrap()
        .ends_with("阿树说要把压缩饼干给你，东西还在阿树身上，还不是你的：要阿树发赠予邀请、你接受了才到你手上，你自己发不了。"));
    assert!(w.inventory().carried_by("b1", "r1") && w.inventory().carried_by("b2", "r1"));

    say(&mut w, "r2", "谢了。");
    say(&mut w, "r1", "饼干你拿着。");
    assert_eq!(notices(&w, "r1").len(), mine.len());
    assert_eq!(notices(&w, "r2").len(), theirs.len());
}
