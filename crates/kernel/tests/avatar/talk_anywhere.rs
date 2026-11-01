//! 玩家搭话只看距离和遮挡：隔着看不见的处所分界、和走在路上的人都能聊，存档读得回来。
use super::*;
use protocol::{At, InteractionStatus};

/// 同一片室外：甲地、甲乙路、乙地连成一条，分界在画面上看不出来。
fn outdoors() -> World {
    let mut topo = common::two_places(json!([]));
    topo.entry = Some(serde_json::from_value(json!({"locale":"loc_a","station":"st_a"})).unwrap());
    let mut w = common::world_with(
        topo,
        600.,
        &[("a", "阿树", "loc_a"), ("b", "小禾", "loc_b")],
    );
    let at = |locale: &str, x: f64| Spot {
        locale: locale.into(),
        space: "out".into(),
        position: [x, 5.],
    };
    let rect = |id: &str, x0: f64| Surface {
        locale: id.into(),
        space: "out".into(),
        area: Area::Rect {
            min: [x0, 0.],
            max: [x0 + 10., 10.],
        },
    };
    w.walk_map = Some(Arc::new(WalkMap {
        version: 1,
        svg_units_per_metre: 12.,
        metres_per_minute: 12.,
        outdoor_space: "out".into(),
        surfaces: vec![
            rect("loc_a", 0.),
            Surface {
                locale: "edge_ab".into(),
                space: "out".into(),
                area: Area::Corridor {
                    points: vec![[10., 5.], [30., 5.]],
                    width: 2.,
                },
            },
            rect("loc_b", 30.),
        ],
        stations: [
            ("st_a".into(), at("loc_a", 9.)),
            ("st_b".into(), at("loc_b", 31.)),
        ]
        .into(),
        ..Default::default()
    }));
    w
}

fn offer(w: &mut World, to: &str) {
    interact(
        w,
        Chat::Offer {
            partner_id: to.into(),
            interaction: InteractionKind::Talk,
            message: "聊聊？".into(),
        },
    );
}

fn accept(w: &mut World, who: &str) {
    w.interact(
        who,
        "yes",
        w.actor(who).unwrap().actions.revision,
        &Chat::Reply {
            interaction_id: "chat".into(),
            accept: true,
            message: "好啊".into(),
        },
    )
    .unwrap();
}

#[test]
fn player_talks_across_an_unseen_place_boundary() {
    let mut w = outdoors();
    enter(&mut w);
    // 往东一步走上甲乙路，阿树还站在甲地边上，相距 1.2 米
    w.avatar_move([1., 0.], false, 0.04).unwrap();
    assert_eq!(w.avatar().unwrap().locus.locale, "edge_ab");
    assert_eq!(json!(w.avatar_view())["nearby"][0]["id"], "a");
    offer(&mut w, "a");
    accept(&mut w, "a");
    // 交谈记在阿树那边，化身往前挪了一步站进甲地
    let me = w.avatar().unwrap();
    assert_eq!(me.locus.locale, "loc_a");
    let At::Free { position, .. } = me.locus.at else {
        panic!("化身应在自由位置")
    };
    assert!(position[0] <= 10.);
    assert_eq!(w.active_chat(ID).unwrap().locale, "loc_a");
    let w = common::restore(&w, outdoors());
    assert!(w.active_chat("a").is_some());
}

#[test]
fn walking_resident_stops_on_the_road_to_talk_and_walks_on_afterwards() {
    let mut w = outdoors();
    enter(&mut w);
    common::run(
        &mut w,
        "b",
        "go",
        json!({"intent":{"verb":"前往","locale":"loc_a"}}),
    )
    .unwrap();
    w.step(1.);
    // 小禾走到甲乙路正中（20 米处）；化身沿路迎上去，停在 18.6 米处
    assert!(matches!(w.actor("b").unwrap().locus.at, At::Transit { .. }));
    for _ in 0..8 {
        w.avatar_move([1., 0.], false, 0.04).unwrap();
    }
    let nearby = json!(w.avatar_view())["nearby"].clone();
    assert_eq!(nearby[0]["id"], "b", "走在路上的人也够得着：{nearby}");
    assert_eq!(nearby[0]["can_talk"], true);
    offer(&mut w, "b");
    let waiting = w.actor("b").unwrap().locus.clone();
    w.step(3.);
    assert_eq!(w.actor("b").unwrap().locus, waiting, "回应前停在路上");
    accept(&mut w, "b");
    assert_eq!(w.active_chat("b").unwrap().locale, "edge_ab");
    let mut w = common::restore(&w, outdoors());
    interact(
        &mut w,
        Chat::Leave {
            interaction_id: "chat".into(),
            message: "回头见".into(),
        },
    );
    assert_eq!(
        w.interactions().of("b", "chat").unwrap().status,
        InteractionStatus::Succeeded
    );
    // 聊完从路上接着走
    common::run(
        &mut w,
        "b",
        "again",
        json!({"intent":{"verb":"前往","locale":"loc_a"}}),
    )
    .unwrap();
    common::finish(&mut w, "b", "again");
    assert_eq!(w.actor("b").unwrap().locus.locale, "loc_a");
}
