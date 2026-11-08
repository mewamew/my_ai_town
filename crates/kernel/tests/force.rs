//! 对人动手与亲近：推搡伤人、打断对方；抢只对醒着的人、偷只对睡着的人，东西真的换了主人；睡着时
//! 被偷的人醒来才发现；死人身上的东西搜身一次拿走；牵手、依偎、拥抱要对方答应，躲开了双方和旁人都看得见；坐下是换了姿势的停留。
//! 都走 run_actions、interact 与 step 的完整路径。
use crate::common;
use kernel::World;
use protocol::{
    FactKind, Gesture, GroupStatus, InteractionCommand as Command, InteractionKind as Kind,
    InteractionStatus,
};
use serde_json::{json, Value};

const CAN: &str = r#"{"id":"test:can","version":1,"name":"罐头","portable":true,"stack_limit":5,"actions":[
  {"id":"eat","label":"吃罐头","duration_minutes":10,"consumes_item":true,"completion":"activity",
   "on_complete":[{"kind":"restore","need":"fullness","amount":40.0}]}]}"#;
const MAT: &str = r#"{"id":"test:mat","version":1,"name":"草垫","actions":[
  {"id":"sleep","label":"睡觉","duration_minutes":480,"completion":"sleep","rest":true,
   "during":[{"kind":"restore_need","need":"energy","per_minute":0.1,"pause_decay":true}]}]}"#;

/// 林晚、周屿和旁观的老渔夫都在甲地；甲地有一罐罐头、一张草垫。需求不随时间变，只看动手的后果。
fn world() -> World {
    let mut w = common::world_with(
        common::two_places(json!([])),
        600.0,
        &[
            ("lin", "林晚", "loc_a"),
            ("zhou", "周屿", "loc_a"),
            ("old", "老渔夫", "loc_a"),
        ],
    );
    for id in ["lin", "zhou", "old"] {
        w.tune_needs(
            id,
            protocol::NeedsTuning {
                fullness_decay: 0.0,
                energy_decay: 0.0,
                ..kernel::default_tuning()
            },
        )
        .unwrap();
    }
    for (id, def) in [("can", CAN), ("mat", MAT)] {
        let def: kernel::props::Definition = serde_json::from_str(def).unwrap();
        w.place_prop(
            serde_json::from_value(json!({
                "instance":{"id":id,"definition":def.reference(),"locale":"loc_a"},
                "definition":def
            }))
            .unwrap(),
        )
        .unwrap();
    }
    w
}

/// 跑一条动作到结束；返回结局和回执变化（失败时是原因）。入队就被拒时返回 Err。
fn act(w: &mut World, who: &str, key: &str, draft: Value) -> Result<(GroupStatus, String), String> {
    common::run(w, who, key, draft).map_err(|e| e.to_string())?;
    let r = common::finish(w, who, key);
    let status = w.action_group(who, key).unwrap().status;
    Ok((
        status,
        if status == GroupStatus::Succeeded {
            r.changes.join("；")
        } else {
            r.reason.unwrap_or_default()
        },
    ))
}

fn texts(w: &World, who: &str, kind: FactKind) -> String {
    w.actor(who)
        .unwrap()
        .journal
        .events
        .iter()
        .filter(|e| e.kind == kind)
        .map(|e| e.text.as_str())
        .collect::<Vec<_>>()
        .join("\n")
}

fn holds(w: &World, who: &str) -> bool {
    w.inventory().carried_by("can", who)
}

fn pick_up(w: &mut World, who: &str) {
    let (status, why) = act(
        w,
        who,
        "pick",
        json!({"intent":{"verb":"拾取"},"inventory":{"operation":"pick_up","items":["can"]}}),
    )
    .unwrap();
    assert_eq!(status, GroupStatus::Succeeded, "{why}");
}

#[test]
fn pushing_hurts_and_interrupts_robbing_takes_what_the_awake_hold_and_onlookers_see() {
    let mut w = world();
    pick_up(&mut w, "zhou");
    // 坐下是换了姿势的停留
    common::run(
        &mut w,
        "lin",
        "sit",
        json!({"intent":{"verb":"坐下","duration_minutes":30}}),
    )
    .unwrap();
    w.step(0.5);
    assert_eq!(w.actor("lin").unwrap().current.verb, "坐下");

    let (status, text) = act(
        &mut w,
        "zhou",
        "push",
        json!({"intent":{"verb":"推搡"},"recipient":"lin"}),
    )
    .unwrap();
    assert_eq!(status, GroupStatus::Succeeded, "{text}");
    assert!(
        text.contains("推了林晚一把") && text.contains("健康减少"),
        "{text}"
    );
    assert_eq!(w.actor("lin").unwrap().needs.health.value, 95.0);
    assert_eq!(
        w.action_group("lin", "sit").unwrap().status,
        GroupStatus::Interrupted,
        "被推了一把，坐着的被打断"
    );
    assert!(texts(&w, "lin", FactKind::Notice).contains("周屿推了你一把"));
    assert!(texts(&w, "old", FactKind::Observation).contains("看见周屿推了林晚一把"));

    // 醒着的人偷不了，只能抢；抢的成败看双方的精力和健康，成没成双方和旁人都知道
    let steal = act(
        &mut w,
        "lin",
        "steal",
        json!({"intent":{"verb":"偷"},"recipient":"zhou","prop_id":"can"}),
    );
    assert!(steal.unwrap_err().contains("醒着，偷不了"));
    let (status, text) = act(
        &mut w,
        "lin",
        "rob",
        json!({"intent":{"verb":"抢"},"recipient":"zhou","prop_id":"can"}),
    )
    .unwrap();
    assert_eq!(status, GroupStatus::Succeeded, "{text}");
    let (felt, saw) = if text.contains("抢走了") {
        assert!(
            holds(&w, "lin") && !holds(&w, "zhou"),
            "抢到了，罐头换了主人"
        );
        ("林晚从你手里抢走了罐头", "看见林晚从周屿手里抢走了罐头")
    } else {
        assert!(text.contains("没抢到") && holds(&w, "zhou"), "{text}");
        (
            "林晚想抢你的罐头，被你护住了",
            "看见林晚想抢周屿的罐头，没抢到",
        )
    };
    assert!(texts(&w, "zhou", FactKind::Notice).contains(felt));
    assert!(texts(&w, "old", FactKind::Observation).contains(saw));
}

#[test]
fn sleepers_can_be_robbed_only_by_stealth_and_find_out_when_they_wake() {
    let mut w = world();
    pick_up(&mut w, "zhou");
    common::run(
        &mut w,
        "zhou",
        "sleep",
        json!({"prop_id":"mat","intent":{"verb":"睡觉"}}),
    )
    .unwrap();
    w.step(1.0);
    assert!(!w.awake("zhou"));
    let rob = act(
        &mut w,
        "lin",
        "rob",
        json!({"intent":{"verb":"抢"},"recipient":"zhou","prop_id":"can"}),
    );
    assert!(rob.unwrap_err().contains("没醒着，抢不了"));
    let (status, text) = act(
        &mut w,
        "lin",
        "steal",
        json!({"intent":{"verb":"偷"},"recipient":"zhou","prop_id":"can"}),
    )
    .unwrap();
    assert_eq!(status, GroupStatus::Succeeded, "{text}");
    if text.contains("没偷成") {
        // 惊醒了：当场撞见，睡觉被打断，东西还在
        assert!(holds(&w, "zhou"));
        assert!(texts(&w, "zhou", FactKind::Notice).contains("看见林晚正伸手拿你身上的罐头"));
        assert_eq!(
            w.action_group("zhou", "sleep").unwrap().status,
            GroupStatus::Interrupted
        );
        return;
    }
    // 没惊醒：东西到了林晚身上，周屿还睡着、什么也不知道，旁人看见了
    assert!(holds(&w, "lin") && !holds(&w, "zhou"), "{text}");
    assert!(!texts(&w, "zhou", FactKind::Notice).contains("不见了"));
    assert!(texts(&w, "old", FactKind::Observation)
        .contains("看见林晚趁周屿睡着，从周屿身上拿走了罐头"));
    // 醒来能留意周围时才发现
    w.interrupt_actions("zhou", "天亮了");
    w.step(0.5);
    assert!(texts(&w, "zhou", FactKind::Notice).contains("醒来发现随身的罐头不见了"));
}

#[test]
fn the_dead_can_be_searched_and_what_they_carried_changes_hands() {
    let mut w = world();
    pick_up(&mut w, "zhou");
    let alive = act(
        &mut w,
        "lin",
        "loot-alive",
        json!({"intent":{"verb":"搜身"},"recipient":"zhou"}),
    );
    assert!(alive.unwrap_err().contains("还活着，搜不了身"));
    // 老渔夫拿刀刺死周屿，林晚搜他的身：罐头到了林晚身上，老渔夫看见了
    let knife: kernel::props::Definition = serde_json::from_str(
        r#"{"id":"test:knife","version":1,"name":"菜刀","portable":true,"actions":[
          {"id":"stab","label":"持刀袭击","duration_minutes":3,"recipient":true,
           "on_complete":[{"kind":"harm","amount":100,"wound":"胸口一处刀伤"}]}]}"#,
    )
    .unwrap();
    w.place_prop(
        serde_json::from_value(json!({
            "instance":{"id":"knife","definition":knife.reference(),"locale":"loc_a"},
            "definition":knife
        }))
        .unwrap(),
    )
    .unwrap();
    let (status, why) = act(
        &mut w,
        "old",
        "stab",
        json!({"prop_id":"knife","intent":{"verb":"持刀袭击"},"recipient":"zhou"}),
    )
    .unwrap();
    assert_eq!(status, GroupStatus::Succeeded, "{why}");
    assert!(w.actor("zhou").unwrap().needs.body.dead);
    let (status, text) = act(
        &mut w,
        "lin",
        "loot",
        json!({"intent":{"verb":"搜身"},"recipient":"zhou"}),
    )
    .unwrap();
    assert_eq!(status, GroupStatus::Succeeded, "{text}");
    assert!(text.contains("从周屿的尸体上拿走了罐头"), "{text}");
    assert!(holds(&w, "lin") && !holds(&w, "zhou"));
    assert!(texts(&w, "old", FactKind::Observation).contains("看见林晚搜了周屿的身，拿走了罐头"));
}

#[test]
fn touching_needs_consent_and_dodging_is_seen_by_both_and_onlookers() {
    let mut w = world();
    let offer = |w: &mut World, key: &str, gesture: Gesture| {
        let revision = w.actor("lin").unwrap().actions.revision;
        w.interact(
            "lin",
            key,
            revision,
            &Command::Offer {
                partner_id: "zhou".into(),
                interaction: Kind::Touch { gesture },
                message: "阿屿，靠近一点".into(),
            },
        )
        .unwrap()
    };
    let reply = |w: &mut World, key: &str, id: &str, accept: bool| {
        let revision = w.actor("zhou").unwrap().actions.revision;
        w.interact(
            "zhou",
            key,
            revision,
            &Command::Reply {
                interaction_id: id.into(),
                accept,
                message: if accept { "嗯" } else { "别闹" }.into(),
            },
        )
        .unwrap()
    };
    let hug = offer(&mut w, "hug", Gesture::Hug);
    let dodged = reply(&mut w, "no", &hug.id, false);
    assert_eq!(dodged.status, InteractionStatus::Declined);
    for who in ["lin", "zhou"] {
        assert!(texts(&w, who, FactKind::Observation).contains("林晚想抱周屿，周屿躲开了"));
    }
    assert!(texts(&w, "old", FactKind::Observation).contains("看见林晚想抱周屿，周屿躲开了"));

    let hands = offer(&mut w, "hands", Gesture::HoldHands);
    reply(&mut w, "yes", &hands.id, true);
    for who in ["lin", "zhou"] {
        assert_eq!(w.actor(who).unwrap().current.verb, "牵手");
    }
    assert!(texts(&w, "old", FactKind::Observation).contains("看见林晚和周屿牵起了手"));
    w.step(11.0);
    assert_eq!(
        w.interactions().of("lin", &hands.id).unwrap().status,
        InteractionStatus::Succeeded
    );
    assert!(texts(&w, "zhou", FactKind::Notice).contains("牵手了一会儿"));
}
