//! 存盘时把历史拆成流水、读档时装回来：拆几次、装回去都得和完整快照一字不差。
use crate::common;
use kernel::{
    history::{Archived, Record},
    World, WorldSnapshot,
};
use protocol::{InteractionCommand as Command, InteractionKind as Kind};
use serde_json::{json, Value};

fn world() -> World {
    let topo = common::two_places(json!([
        {"id":"bench","name":"工作台","locale":"loc_a","verbs":[{"verb":"制作器物","duration_minutes":2}]}
    ]));
    // 天亮前一小时开始：过一会儿就跨过天亮，不用等到人饿倒
    common::world_with(
        topo,
        300.0,
        &[("r1", "阿树", "loc_a"), ("r2", "小禾", "loc_a")],
    )
}

fn interact(w: &mut World, actor: &str, id: &str, command: Command) {
    let revision = w.actor(actor).unwrap().actions.revision;
    w.interact(actor, id, revision, &command).unwrap();
}

/// 聊一场（邀请、答应、各说一句、告辞）再做一件事：事件、做完的动作组、结束的互动都有了。
fn live_a_little(w: &mut World, round: &str) {
    let chat = format!("chat-{round}");
    interact(
        w,
        "r1",
        &chat,
        Command::Offer {
            partner_id: "r2".into(),
            interaction: Kind::Talk,
            message: "聊两句？".into(),
        },
    );
    let reply = Command::Reply {
        interaction_id: chat.clone(),
        accept: true,
        message: "好".into(),
    };
    interact(w, "r2", &format!("reply-{round}"), reply);
    let say = Command::Say {
        interaction_id: chat.clone(),
        message: format!("第 {round} 回说的话"),
        to: None,
    };
    interact(w, "r1", &format!("say-{round}"), say);
    let leave = Command::Leave {
        interaction_id: chat,
        message: "先走了".into(),
    };
    interact(w, "r2", &format!("leave-{round}"), leave);
    let work = format!("work-{round}");
    common::run(
        w,
        "r1",
        &work,
        json!({"intent":{"verb":"制作器物"},"prop_id":"bench"}),
    )
    .unwrap();
    common::finish(w, "r1", &work);
}

/// 把这次拆出来的记成已写。
fn written(archived: &mut Archived, records: &[Record]) {
    for record in records {
        archived.note(record);
    }
}

#[test]
fn history_leaves_the_save_once_and_comes_back_as_the_same_world() {
    let mut w = world();
    live_a_little(&mut w, "一");
    // 过一个天亮：今天的流水归档成「过完的一天」
    w.step(90.0);
    let mut archived = Archived::default();
    let first = w.detach(&archived).unwrap();
    let state = json!(first.snapshot);
    for actor in ["r1", "r2"] {
        let a = &state["actors"][actor];
        assert_eq!(a["journal"]["events"], json!([]));
        assert_eq!(a["journal"]["days"], json!([]));
        assert_eq!(a["actions"]["groups"], json!({}));
    }
    assert_eq!(state["interactions"], json!({}));
    assert!(first
        .records
        .iter()
        .any(|r| matches!(r, Record::Day { .. })));
    written(&mut archived, &first.records);

    // 接着过：只拆出新增的，写过的不再出现
    let cursor = w.actor("r1").unwrap().journal.cursor();
    live_a_little(&mut w, "二");
    let invite = Command::Offer {
        partner_id: "r2".into(),
        interaction: Kind::Talk,
        message: "还没回的邀请".into(),
    };
    interact(&mut w, "r1", "pending", invite);
    let second = w.detach(&archived).unwrap();
    assert!(second.records.iter().all(|r| match r {
        Record::Event { actor, fact } => actor != "r1" || fact.event_id > cursor,
        Record::Day { .. } => false,
        Record::Actions { group, .. } => group.id == "work-二",
        Record::Interaction(item) => item.id == "chat-二",
    }));
    // 没结束的互动算当前状态，留在快照里
    assert!(json!(second.snapshot)["interactions"]["pending"].is_object());
    written(&mut archived, &second.records);
    assert!(w.detach(&archived).unwrap().records.is_empty());

    // 读档：当前状态加两次的流水，装回去就是完整快照，世界照常恢复
    let saved: Value = json!(second.snapshot);
    let mut snapshot: WorldSnapshot = serde_json::from_value(saved).unwrap();
    let records = first.records.into_iter().chain(second.records);
    let restored_marks = snapshot.attach(records).unwrap();
    assert_eq!(json!(snapshot), json!(w.snapshot()));
    let mut restored = world();
    restored.restore_snapshot(snapshot).unwrap();
    assert!(restored.detach(&restored_marks).unwrap().records.is_empty());

    // 重置过的世界对不上那份流水：要另起一份
    assert!(world().detach(&archived).is_none());
}
