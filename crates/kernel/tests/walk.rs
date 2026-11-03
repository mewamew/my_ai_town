//! 同行：交谈里说好就走、世界带着跟随的人穿门跟上、到了就结束；存档中途读回接着走；
//! 带路的化身离开小镇时同行结束，跟随的人不会卡住。
use crate::common;
use kernel::{
    avatar::{Area, Portal, Spot, Surface, WalkMap, ID},
    World,
};
use protocol::{Appearance, InteractionCommand as Cmd, InteractionKind, InteractionStatus};
use serde_json::json;
use std::sync::Arc;

fn spot(locale: &str, x: f64, y: f64) -> Spot {
    Spot {
        locale: locale.into(),
        space: locale.into(),
        position: [x, y],
    }
}

/// 甲乙两处各一个空间，甲处 (5,2) 有门通到乙处 (2,2)；入口在甲处落脚点。
fn world(residents: &[(&str, &str, &str)]) -> World {
    let mut topo = common::two_places(json!([]));
    topo.entry = Some(serde_json::from_value(json!({"locale":"loc_a","station":"st_a"})).unwrap());
    let mut w = common::world_with(topo, 600., residents);
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
    let look = Appearance {
        marker: "旅".into(),
        color: "#387963".into(),
        profile: None,
        look: None,
    };
    w.avatar_enter("旅人", look).unwrap();
}

fn act(w: &mut World, actor: &str, key: &str, command: Cmd) -> protocol::Interaction {
    let rev = w.actor(actor).unwrap().actions.revision;
    if actor == ID {
        w.avatar_interact(key, rev, &command).unwrap()
    } else {
        w.interact(actor, key, rev, &command).unwrap()
    }
}

/// 化身和阿树聊起来。
fn talk(w: &mut World) {
    act(
        w,
        ID,
        "chat",
        Cmd::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Talk,
            message: "你好，方便聊一会儿吗？".into(),
        },
    );
    act(
        w,
        "a",
        "chat-yes",
        Cmd::Reply {
            interaction_id: "chat".into(),
            accept: true,
            message: "说吧。".into(),
        },
    );
}

/// 化身朝 direction 走 minutes 分钟，世界同步推进。
fn walk_avatar(w: &mut World, direction: [f64; 2], minutes: f64) {
    let steps = (minutes / 0.05).ceil() as usize;
    for _ in 0..steps {
        w.avatar_move(direction, false, 0.05).unwrap();
        w.step(0.05);
    }
}

fn status(w: &World, id: &str) -> InteractionStatus {
    w.interactions().of("a", id).unwrap().status
}

#[test]
fn chat_proposal_turns_talk_into_walk_and_the_follower_comes_through_the_door() {
    let mut w = world(&[("a", "阿树", "loc_a")]);
    enter(&mut w);
    talk(&mut w);
    let normal = w.avatar_walk().unwrap().metres_per_minute;
    act(
        &mut w,
        ID,
        "propose",
        Cmd::Propose {
            interaction_id: "chat".into(),
            interaction: InteractionKind::Walk {
                leader: ID.into(),
                locale: None,
            },
            message: "我带你去".into(),
            to: None,
        },
    );
    // 只有被问的人能答应
    assert!(w
        .avatar_interact(
            "self-accept",
            w.avatar().unwrap().actions.revision,
            &Cmd::Accept {
                interaction_id: "chat".into(),
                message: String::new(),
                locale: None
            }
        )
        .is_err());
    let walk = act(
        &mut w,
        "a",
        "accept",
        Cmd::Accept {
            interaction_id: "chat".into(),
            message: "走吧，前头带路。".into(),
            locale: None,
        },
    );
    // 两人的交谈就地变成同行，说过的话还在；阿树跟着化身，化身照常能走，只是放慢了
    assert_eq!(walk.status, InteractionStatus::Running);
    assert!(matches!(walk.kind, InteractionKind::Walk { .. }));
    assert!(walk
        .chat
        .as_ref()
        .unwrap()
        .entries
        .iter()
        .any(|e| e.text == "我带你去"));
    assert_eq!(w.following("a"), Some(ID));
    assert!(w.avatar_walk().unwrap().metres_per_minute < normal);
    assert!(!w.chat_turn("a"), "路上默认安静，不用每分钟想一句话");

    walk_avatar(&mut w, [1., 0.], 0.2);
    w.avatar_portal("door").unwrap();
    assert_eq!(w.avatar().unwrap().locus.locale, "loc_b");
    for _ in 0..20 {
        w.step(0.05);
    }
    assert_eq!(w.actor("a").unwrap().locus.locale, "loc_b", "跟着穿过了门");
    assert_eq!(status(&w, "chat"), InteractionStatus::Running);
    // 边走边聊：路上开口，跟着的人轮到回话，照样跟着
    w.avatar_request_turn("chat", w.avatar().unwrap().actions.revision)
        .unwrap();
    act(
        &mut w,
        ID,
        "say",
        Cmd::Say {
            interaction_id: "chat".into(),
            message: "就在前面。".into(),
            to: None,
        },
    );
    assert!(w.chat_turn("a") && w.following("a") == Some(ID));
    act(
        &mut w,
        "a",
        "listen",
        Cmd::Listen {
            interaction_id: "chat".into(),
        },
    );
    // 带路的人在乙地停下，跟随的人也在：一会儿就算到了
    for _ in 0..40 {
        w.step(0.05);
    }
    assert_eq!(status(&w, "chat"), InteractionStatus::Succeeded);
    let a = w.actor("a").unwrap();
    assert!(a.waiting_for_plan() && a.current.interaction.is_none());
    assert_eq!(w.avatar_walk().unwrap().metres_per_minute, normal);
}

#[test]
fn resident_leader_sets_off_and_a_saved_walk_resumes_until_both_arrive() {
    let mut w = world(&[("a", "阿树", "loc_a"), ("b", "何青", "loc_a")]);
    act(
        &mut w,
        "b",
        "lead",
        Cmd::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Walk {
                leader: "b".into(),
                locale: Some("loc_b".into()),
            },
            message: "跟我去乙地看看。".into(),
        },
    );
    act(
        &mut w,
        "a",
        "lead-yes",
        Cmd::Reply {
            interaction_id: "lead".into(),
            accept: true,
            message: "行，我跟着你。".into(),
        },
    );
    // 说好了目的地，带路的人直接动身
    w.step(0.01);
    assert!(matches!(
        w.actor("b").unwrap().current.kind,
        kernel::world::ActKind::Travel { .. }
    ));
    assert_eq!(w.following("a"), Some("b"));
    w.step(0.5);
    let mut fresh = world(&[("a", "阿树", "loc_a"), ("b", "何青", "loc_a")]);
    fresh = common::restore(&w, fresh);
    assert_eq!(fresh.following("a"), Some("b"), "读档后还在跟着");
    for _ in 0..200 {
        fresh.step(0.05);
        if status(&fresh, "lead") != InteractionStatus::Running {
            break;
        }
    }
    assert_eq!(status(&fresh, "lead"), InteractionStatus::Succeeded);
    for id in ["a", "b"] {
        assert_eq!(fresh.actor(id).unwrap().locus.locale, "loc_b");
    }
    assert!(fresh.actor("a").unwrap().waiting_for_plan());
}

#[test]
fn avatar_leaving_town_ends_the_walk_and_frees_the_follower() {
    let mut w = world(&[("a", "阿树", "loc_a")]);
    enter(&mut w);
    act(
        &mut w,
        ID,
        "walk",
        Cmd::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Walk {
                leader: ID.into(),
                locale: None,
            },
            message: "跟我来。".into(),
        },
    );
    act(
        &mut w,
        "a",
        "walk-yes",
        Cmd::Reply {
            interaction_id: "walk".into(),
            accept: true,
            message: "好。".into(),
        },
    );
    walk_avatar(&mut w, [0., 1.], 0.3);
    let before = w.actor("a").unwrap().actions.revision;
    w.avatar_leave().unwrap();
    assert_eq!(status(&w, "walk"), InteractionStatus::Interrupted);
    let a = w.actor("a").unwrap();
    assert!(a.waiting_for_plan() && a.actions.revision > before);
    w.step(1.0);
    assert!(w.actor("a").unwrap().waiting_for_plan());
}

/// 看得见去向：同处的人看到谁往哪儿去了、谁来了；邀请对象走开后邀请作废，邀请人收到通知，不再干等。
#[test]
fn departures_are_seen_and_an_invitation_lapses_when_the_invitee_walks_off() {
    let mut w = world(&[("a", "陈默", "loc_a"), ("b", "何青", "loc_a")]);
    w.step(0.1);
    common::run(
        &mut w,
        "b",
        "go",
        json!({"intent":{"verb":"前往","locale":"loc_b"}}),
    )
    .unwrap();
    common::finish(&mut w, "b", "go");
    let seen: Vec<_> = w
        .actor("a")
        .unwrap()
        .journal
        .events
        .iter()
        .filter(|e| e.kind == protocol::FactKind::Presence)
        .map(|e| e.text.clone())
        .collect();
    assert_eq!(seen, ["何青往乙地去了"]);

    enter(&mut w);
    act(
        &mut w,
        "a",
        "ask",
        Cmd::Offer {
            partner_id: ID.into(),
            interaction: InteractionKind::Talk,
            message: "刀在哪儿看见的，你带我去。".into(),
        },
    );
    walk_avatar(&mut w, [0., 1.], 1.0);
    let ask = w.interactions().of("a", "ask").unwrap();
    assert_eq!(ask.status, InteractionStatus::Cancelled);
    assert!(ask.reason.as_deref().unwrap().contains("旅人已经走开"));
    assert!(w
        .actor("a")
        .unwrap()
        .journal
        .events
        .iter()
        .any(|e| e.kind == protocol::FactKind::Notice && e.text.contains("已经走开")));
}
