use crate::common;
use kernel::{
    avatar::{Area, Obstacle, Portal, Spot, Surface, WalkMap, ID},
    World,
};
use protocol::{Appearance, InteractionCommand as Chat, InteractionKind, InventoryAction};
use serde_json::{json, Value};
use std::sync::Arc;

fn spot(locale: &str, x: f64, y: f64) -> Spot {
    Spot {
        locale: locale.into(),
        space: locale.into(),
        position: [x, y],
    }
}
fn world() -> World {
    world_with_props(json!([
        {"id":"flower","definition":"test:flower@1","locale":"loc_a"}
    ]))
}
fn world_with_props(props: Value) -> World {
    let mut topo = common::two_places(props);
    topo.entry = Some(serde_json::from_value(json!({"locale":"loc_a","station":"st_a"})).unwrap());
    let mut w = common::world_with(
        topo,
        600.,
        &[("a", "阿树", "loc_a"), ("b", "远处的人", "loc_b")],
    );
    w.walk_map = Some(Arc::new(WalkMap {
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
        props: [("flower".into(), spot("loc_a", 3., 2.))].into(),
        obstacles: vec![Obstacle {
            id: "wall".into(),
            spot: spot("loc_a", 10., 10.),
            half: [0.1, 10.],
        }],
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
fn enter(w: &mut World) {
    w.avatar_enter(
        "aya",
        Appearance {
            marker: "我".into(),
            color: "#387963".into(),
            profile: None,
            look: None,
        },
    )
    .unwrap();
}
fn snapshot(w: &World) -> Value {
    serde_json::to_value(w.snapshot()).unwrap()
}
fn interact(w: &mut World, command: Chat) {
    let rev = w.avatar().unwrap().actions.revision;
    w.avatar_interact("chat", rev, &command).unwrap();
}

#[test]
fn avatar_can_cancel_a_running_chat() {
    let mut w = world();
    enter(&mut w);
    interact(
        &mut w,
        Chat::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Talk,
            message: "聊聊？".into(),
        },
    );
    w.interact(
        "a",
        "accept",
        w.actor("a").unwrap().actions.revision,
        &Chat::Reply {
            interaction_id: "chat".into(),
            accept: true,
            message: "好。".into(),
        },
    )
    .unwrap();
    assert!(w.active_chat(ID).is_some());
    interact(
        &mut w,
        Chat::Cancel {
            interaction_id: "chat".into(),
        },
    );
    assert!(w.active_chat(ID).is_none());
    assert!(w.active_chat("a").is_none());
    assert_eq!(
        w.interactions().of("a", "chat").unwrap().status,
        protocol::InteractionStatus::Succeeded
    );
    assert!(w.avatar().unwrap().interaction_available());
}

#[test]
fn avatar_uses_inventory_and_chat_without_an_agent_and_keeps_identity_after_leaving() {
    busy_talk::invitation_preserves_work_until_acceptance();
    let mut w = world();
    enter(&mut w);
    assert!(!w.avatar().unwrap().actions.agent_controlled);
    let rev = w.avatar().unwrap().actions.revision;
    assert!(w
        .avatar_action(
            "bad-recipient",
            rev,
            &serde_json::from_value(
                json!({"intent":{"verb":"停留"},"prop_id":"flower","recipient":"missing-person"})
            )
            .unwrap()
        )
        .is_err());
    assert!(w.enable_agent(ID).is_err());
    let op = InventoryAction::PickUp {
        items: vec!["flower".into()],
    };
    let action: protocol::ActionDraft =
        serde_json::from_value(json!({"intent":{"verb":op.label()},"inventory":op})).unwrap();
    let rev = w.avatar().unwrap().actions.revision;
    assert!(w
        .run_actions(ID, "wrong-source", rev, &[action.clone()])
        .is_err());
    w.avatar_action("pick", rev, &action).unwrap();
    // 活动进行中也必须可存盘、恢复，不得把自由位置改成道具站位。
    let mut restored = world();
    restored.restore_snapshot(w.snapshot()).unwrap();
    w = restored;
    common::finish(&mut w, ID, "pick");
    assert_eq!(w.inventory_view(ID).used, 1);
    w.avatar_action("pick", rev, &action).unwrap();
    assert_eq!(w.inventory_view(ID).used, 1);
    interact(
        &mut w,
        Chat::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Talk,
            message: "你好".into(),
        },
    );
    w.interact(
        "a",
        "accept",
        w.actor("a").unwrap().actions.revision,
        &Chat::Reply {
            interaction_id: "chat".into(),
            accept: true,
            message: "你好 aya".into(),
        },
    )
    .unwrap();
    let before = w.avatar().unwrap().locus.clone();
    w.avatar_move([1., 0.], 0.1).unwrap();
    assert_eq!(w.avatar().unwrap().locus, before);
    assert!(w
        .interact(
            "b",
            "too-far",
            w.actor("b").unwrap().actions.revision,
            &Chat::Join {
                interaction_id: "chat".into(),
                message: "加入".into()
            }
        )
        .is_err());
    if w.chat_turn(ID) {
        interact(
            &mut w,
            Chat::Say {
                interaction_id: "chat".into(),
                message: "我是玩家。".into(),
                to: None,
            },
        );
    }
    w.spawn("c", "第三位居民", "loc_a").unwrap();
    w.enable_agent("c").unwrap();
    w.interact(
        "c",
        "join-three",
        w.actor("c").unwrap().actions.revision,
        &Chat::Join {
            interaction_id: "chat".into(),
            message: "一起聊".into(),
        },
    )
    .unwrap();
    w.avatar_leave().unwrap();
    assert!(w.active_chat(ID).is_none());
    assert!(
        w.active_chat("a").is_some(),
        "化身离场不能结束剩下两位居民的聊天"
    );
    let speaker = if w.chat_turn("a") { "a" } else { "c" };
    if w.chat_turn(speaker) {
        w.interact(
            speaker,
            "after-leave",
            w.actor(speaker).unwrap().actions.revision,
            &Chat::Say {
                interaction_id: "chat".into(),
                message: "玩家离开后才说的话".into(),
                to: None,
            },
        )
        .unwrap();
    }
    let history =
        serde_json::to_value(w.chat_history(ID, "history".into(), Some("chat".into()), 0)).unwrap();
    assert!(history["entries"]
        .as_array()
        .unwrap()
        .iter()
        .all(|e| e["audience"].as_array().unwrap().iter().any(|a| a == ID)));
    assert!(!history.to_string().contains("玩家离开后才说的话"));
    w.interact(
        "c",
        "leave-three",
        w.actor("c").unwrap().actions.revision,
        &Chat::Leave {
            interaction_id: "chat".into(),
            message: "先走了".into(),
        },
    )
    .unwrap();
    let needs = snapshot(&w)["actors"][ID]["needs"].clone();
    w.step(30.);
    assert_eq!(snapshot(&w)["actors"][ID]["needs"], needs);
    let mut restored = world();
    restored.restore_snapshot(w.snapshot()).unwrap();
    enter(&mut restored);
    assert_eq!(restored.inventory_view(ID).used, 1);
    assert_eq!(restored.avatar().unwrap().name, "aya");
    assert!(
        !json!(restored.chat_history(ID, "restored".into(), None, 0))["chats"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    // 赠送沿用双方同意与完成后结算；邀请本身不转移物品。
    let rev = restored.avatar().unwrap().actions.revision;
    restored
        .avatar_interact(
            "gift",
            rev,
            &Chat::Offer {
                partner_id: "a".into(),
                interaction: InteractionKind::Give {
                    items: vec!["flower".into()],
                },
                message: "送你".into(),
            },
        )
        .unwrap();
    assert_eq!(restored.inventory_view(ID).used, 1);
    restored
        .interact(
            "a",
            "yes",
            restored.actor("a").unwrap().actions.revision,
            &Chat::Reply {
                interaction_id: "gift".into(),
                accept: true,
                message: "谢谢".into(),
            },
        )
        .unwrap();
    restored.step(10.);
    assert_eq!(restored.inventory_view(ID).used, 0);
    assert_eq!(restored.inventory_view("a").used, 1);
    default_runtime_props_keep_authoritative_and_legacy_positions();
}

/// 玩家来搭话时，受邀的人手头的事先停着等回应，免得想好要聊时已经走远；拒绝后照原样接着做。
/// 一直不回应时只停一小会儿，不会一直站着。
#[test]
fn walking_resident_waits_for_a_player_invitation() {
    let mut w = world();
    enter(&mut w);
    let plan: Vec<protocol::ActionDraft> = serde_json::from_value(json!([
        {"intent":{"verb":"停留","duration_minutes":1}},
        {"intent":{"verb":"前往","locale":"loc_b"}}
    ]))
    .unwrap();
    let revision = w.actor("a").unwrap().actions.revision;
    w.run_actions("a", "go", revision, &plan).unwrap();
    w.step(0.01);
    interact(
        &mut w,
        Chat::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Talk,
            message: "等等，聊两句？".into(),
        },
    );
    let waiting = w.actor("a").unwrap().locus.clone();
    w.step(5.);
    assert_eq!(w.actor("a").unwrap().locus, waiting, "回应前不动身");
    w.interact(
        "a",
        "later",
        w.actor("a").unwrap().actions.revision,
        &Chat::Reply {
            interaction_id: "chat".into(),
            accept: false,
            message: "我先去那边，回头再聊".into(),
        },
    )
    .unwrap();
    let result = common::finish(&mut w, "a", "go");
    assert_eq!(
        result.status,
        protocol::ActionStatus::Succeeded,
        "{result:?}"
    );
    assert_eq!(w.actor("a").unwrap().locus.locale, "loc_b");

    // 没有回应：停满时限后照常动身
    let mut w = world();
    enter(&mut w);
    let revision = w.actor("a").unwrap().actions.revision;
    w.run_actions("a", "go", revision, &plan).unwrap();
    w.step(0.01);
    interact(
        &mut w,
        Chat::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Talk,
            message: "在吗？".into(),
        },
    );
    w.step(kernel::interactions::TALK_HOLD_MINUTES + 5.);
    assert_ne!(
        w.actor("a").unwrap().locus.locale,
        "loc_a",
        "不回应时只停一小会儿"
    );
}

#[test]
fn movement_normalizes_diagonals_stops_at_walls_and_only_uses_nearby_doors() {
    let mut w = world();
    enter(&mut w);
    // 化身没有身体状态：在场时推进时间也不改变需求，状态里也不给需求条
    let needs = snapshot(&w)["actors"][ID]["needs"].clone();
    w.step(240.);
    assert_eq!(snapshot(&w)["actors"][ID]["needs"], needs);
    assert_eq!(json!(w.avatar_view())["actor"]["needs"], json!([]));
    assert!(w.avatar_move([f64::NAN, 0.], 0.1).is_err());
    assert!(w.avatar_move([1., 0.], 30.).is_err());
    assert!(w.avatar_portal("door").is_err());
    w.avatar_move([1., 1.], 0.1).unwrap();
    let protocol::At::Free { position, .. } = w.avatar().unwrap().locus.at else {
        panic!()
    };
    assert!(((position[0] - 2.).hypot(position[1] - 2.) - 1.2).abs() < 1e-8);
    for _ in 0..30 {
        w.avatar_move([1., 0.], 0.1).unwrap();
    }
    let protocol::At::Free { position, .. } = w.avatar().unwrap().locus.at else {
        panic!()
    };
    assert!(position[0] < 9.67);
    let rev = w.avatar().unwrap().actions.revision;
    assert!(w.avatar_action("remote",rev,&serde_json::from_value(json!({"intent":{"verb":"拾取"},"inventory":{"operation":"pick_up","items":["flower"]}})).unwrap()).is_err());
    for _ in 0..4 {
        w.avatar_move([-1., 0.], 0.1).unwrap();
    }
    w.avatar_portal("door").unwrap();
    assert_eq!(w.avatar().unwrap().locus.locale, "loc_b");
    let mut invalid = snapshot(&w);
    invalid["actors"][ID]["locus"]["at"]["position"] = json!([900., 900.]);
    assert!(w
        .restore_snapshot(serde_json::from_value(invalid).unwrap())
        .is_err());
    assert_eq!(w.avatar().unwrap().locus.locale, "loc_b");
    w.set_body_values(ID, None, None, None, Some(0.)).unwrap();
    w.avatar_leave().unwrap();
    let body = snapshot(&w)["actors"][ID]["needs"].clone();
    enter(&mut w);
    assert_eq!(snapshot(&w)["actors"][ID]["needs"], body);
    assert_eq!(json!(w.avatar_view())["actor"]["body"]["life"], "dead");
    avatar_rejects_people_and_props_beyond_reach_or_behind_a_wall();
}

fn default_runtime_props_keep_authoritative_and_legacy_positions() {
    let mut w = world();
    let definition = common::catalog().definitions["test:flower@1"].clone();
    w.place_prop(kernel::props::Placement {
        instance: serde_json::from_value(
            json!({"id":"new_flower","definition":"test:flower@1","locale":"loc_a"}),
        )
        .unwrap(),
        definition,
    })
    .unwrap();
    let placed = snapshot(&w)["walk_prop_positions"]["new_flower"].clone();
    assert_eq!(placed["locale"], "loc_a");
    assert!(w
        .prop_views()
        .iter()
        .find(|p| p.id == "new_flower")
        .unwrap()
        .walk_position
        .is_some());
    let saved = w.snapshot();
    w.restore_snapshot(saved).unwrap();
    assert_eq!(snapshot(&w)["walk_prop_positions"]["new_flower"], placed);
    let mut old = snapshot(&w);
    old.as_object_mut().unwrap().remove("walk_prop_positions");
    w.restore_snapshot(serde_json::from_value(old).unwrap())
        .unwrap();
    w.restore_walk_props([("new_flower".into(), ("loc_a".into(), [4., 4.]))].into())
        .unwrap();
    assert_eq!(
        snapshot(&w)["walk_prop_positions"]["new_flower"]["position"],
        json!([4., 4.])
    );
    // 此后世界存档优先，旧显示文件不再把道具移回其他位置。
    w.restore_walk_props([("new_flower".into(), ("loc_a".into(), [8., 8.]))].into())
        .unwrap();
    let before = snapshot(&w);
    assert_eq!(
        before["walk_prop_positions"]["new_flower"]["position"],
        json!([4., 4.])
    );
    let mut bad = snapshot(&w);
    bad["walk_prop_positions"]["new_flower"]["position"] = json!([900., 900.]);
    assert!(w
        .restore_snapshot(serde_json::from_value(bad).unwrap())
        .is_err());
    assert_eq!(snapshot(&w), before);
}

mod busy_talk;

fn avatar_rejects_people_and_props_beyond_reach_or_behind_a_wall() {
    for blocked_by_wall in [false, true] {
        let mut w = world();
        enter(&mut w);
        let target_x = if blocked_by_wall { 3. } else { 12. };
        let map = Arc::make_mut(w.walk_map.as_mut().unwrap());
        map.stations
            .insert("st_a".into(), spot("loc_a", target_x, 2.));
        map.props
            .insert("flower".into(), spot("loc_a", target_x, 2.));
        map.obstacles.clear();
        if blocked_by_wall {
            map.obstacles.push(Obstacle {
                id: "partition".into(),
                spot: spot("loc_a", 2.5, 2.),
                half: [0.1, 0.5],
            });
        }
        let before = snapshot(&w);
        let revision = w.avatar().unwrap().actions.revision;
        let pick = serde_json::from_value(json!({
            "intent":{"verb":"拾取"},
            "inventory":{"operation":"pick_up","items":["flower"]}
        }))
        .unwrap();
        let error = w
            .avatar_action("unreachable-pick", revision, &pick)
            .unwrap_err();
        assert!(error.to_string().contains("请走近道具再操作"), "{error}");
        let offer = Chat::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Talk,
            message: "聊聊？".into(),
        };
        let error = w
            .avatar_interact("unreachable-talk", revision, &offer)
            .unwrap_err();
        assert!(error.to_string().contains("不能隔墙交谈"), "{error}");
        let after = snapshot(&w);
        for field in ["inventory", "interactions"] {
            assert_eq!(before[field], after[field]);
        }
        assert_eq!(before["actors"][ID]["locus"], after["actors"][ID]["locus"]);
        // 同一目标移到近处、撤去隔断后允许操作，排除目标本身不可用。
        let map = Arc::make_mut(w.walk_map.as_mut().unwrap());
        map.obstacles.clear();
        map.stations.insert("st_a".into(), spot("loc_a", 3., 2.));
        map.props.insert("flower".into(), spot("loc_a", 3., 2.));
        w.avatar_action("reachable-pick", revision, &pick).unwrap();
        common::finish(&mut w, ID, "reachable-pick");
        let revision = w.avatar().unwrap().actions.revision;
        w.avatar_interact("reachable-talk", revision, &offer)
            .unwrap();
    }
}

/// 房间的到达点在门外：站点画在外面的空间，处所却是房间。站在那里的人算在屋里，
/// 化身进门就能和他说话；附身他时从门内开始，存档读得回来。
#[test]
fn resident_on_the_doorstep_counts_as_inside() {
    let doorstep = |w: &mut World| {
        Arc::make_mut(w.walk_map.as_mut().unwrap()).stations.insert(
            "st_b".into(),
            Spot {
                locale: "loc_b".into(),
                space: "loc_a".into(),
                position: [5., 2.],
            },
        );
    };
    let mut w = world();
    doorstep(&mut w);
    enter(&mut w);
    for _ in 0..2 {
        w.avatar_move([1., 0.], 0.1).unwrap();
    }
    w.avatar_portal("door").unwrap();
    let revision = w.avatar().unwrap().actions.revision;
    w.avatar_interact(
        "doorstep-talk",
        revision,
        &Chat::Offer {
            partner_id: "b".into(),
            interaction: InteractionKind::Talk,
            message: "聊聊？".into(),
        },
    )
    .unwrap();

    let mut w = world();
    doorstep(&mut w);
    w.possess("b").unwrap();
    assert_eq!(snapshot(&w)["actors"]["b"]["locus"]["at"]["space"], "loc_b");
    let saved = w.snapshot();
    w.restore_snapshot(saved).unwrap();
}
