use super::*;
use protocol::{ActionStatus, GroupStatus, InteractionStatus};

pub(super) fn invitation_preserves_work_until_acceptance() {
    let mut w = world();
    enter(&mut w);
    w.run_actions(
        "a",
        "work",
        w.actor("a").unwrap().actions.revision,
        &serde_json::from_value::<Vec<protocol::ActionDraft>>(json!([
            {"intent":{"verb":"停留","duration_minutes":1000}},
            {"intent":{"verb":"停留","duration_minutes":10}}
        ]))
        .unwrap(),
    )
    .unwrap();
    w.step(1.);
    assert_eq!(json!(w.avatar_view())["nearby"][0]["available"], false);
    assert_eq!(json!(w.avatar_view())["nearby"][0]["can_talk"], true);
    let before = serde_json::to_value(w.actor("a").unwrap()).unwrap();
    let offer = |w: &mut World, id: &str| {
        w.avatar_interact(
            id,
            w.avatar().unwrap().actions.revision,
            &Chat::Offer {
                partner_id: "a".into(),
                interaction: InteractionKind::Talk,
                message: "聊聊？".into(),
            },
        )
    };
    offer(&mut w, "decline").unwrap();
    assert!(offer(&mut w, "duplicate").is_err());
    w.interact(
        "a",
        "no",
        w.actor("a").unwrap().actions.revision,
        &Chat::Reply {
            interaction_id: "decline".into(),
            accept: false,
            message: "忙完再聊".into(),
        },
    )
    .unwrap();
    let after = serde_json::to_value(w.actor("a").unwrap()).unwrap();
    for field in ["current", "plan", "locus", "actions"] {
        assert_eq!(before[field], after[field], "拒绝不能改变 {field}");
    }
    offer(&mut w, "expires").unwrap();
    w.step(601.);
    assert_eq!(
        w.interactions().of(ID, "expires").unwrap().status,
        InteractionStatus::Expired
    );
    assert_eq!(
        w.action_group("a", "work").unwrap().status,
        GroupStatus::Running
    );
    offer(&mut w, "accept").unwrap();
    // 邀请后走远，接受失败不能先中断受邀者的工作。
    w.avatar_move([1., 0.], false, 0.2).unwrap();
    let reply = Chat::Reply {
        interaction_id: "accept".into(),
        accept: true,
        message: "好，先聊一会儿".into(),
    };
    assert!(w
        .interact(
            "a",
            "too-far",
            w.actor("a").unwrap().actions.revision,
            &reply
        )
        .is_err());
    assert_eq!(
        w.action_group("a", "work").unwrap().status,
        GroupStatus::Running
    );
    w.avatar_move([-1., 0.], false, 0.2).unwrap();
    w.interact("a", "yes", w.actor("a").unwrap().actions.revision, &reply)
        .unwrap();
    let results = &w.action_group("a", "work").unwrap().results;
    assert_eq!(
        results.iter().map(|r| r.status).collect::<Vec<_>>(),
        vec![ActionStatus::Interrupted, ActionStatus::Cancelled]
    );
    assert!(w.actor("a").unwrap().plan.is_empty());
    assert_eq!(w.active_chat("a").unwrap().id, "accept");
    let save = w.snapshot();
    let mut restored = world();
    restored.restore_snapshot(save).unwrap();
    assert_eq!(restored.active_chat("a").unwrap().id, "accept");
    assert_eq!(restored.action_group("a", "work").unwrap().results.len(), 2);
}
