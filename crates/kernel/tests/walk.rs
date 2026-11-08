//! 同行：交谈里说好就走、世界带着跟随的人穿门跟上、到了就结束；存档中途读回接着走；
//! 带路的化身离开小镇时同行结束，跟随的人不会卡住；站在走不通的地方的人也走得开，这样的存档读得回来。
use crate::common;
use kernel::{
    avatar::{Area, Obstacle, Portal, Spot, Surface, WalkMap, ID},
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

/// 甲乙两处挨着、在同一个室外空间里（像街道和广场）：甲处 x 0–10，乙处 x 10–20。
fn open_world(residents: &[(&str, &str, &str)]) -> World {
    let mut w = world(residents);
    let outdoor = |locale: &str, x: f64| Spot {
        locale: locale.into(),
        space: "town".into(),
        position: [x, 2.],
    };
    w.walk_map = Some(Arc::new(WalkMap {
        version: 1,
        svg_units_per_metre: 12.,
        metres_per_minute: 12.,
        surfaces: [("loc_a", 0., 10.), ("loc_b", 10., 20.)]
            .into_iter()
            .map(|(id, x0, x1)| Surface {
                locale: id.into(),
                space: "town".into(),
                area: Area::Rect {
                    min: [x0, 0.],
                    max: [x1, 20.],
                },
            })
            .collect(),
        stations: [
            ("st_a".into(), outdoor("loc_a", 2.)),
            ("st_b".into(), outdoor("loc_b", 11.)),
        ]
        .into(),
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
    // 边走边聊：路上谁开口就从谁说起（不用先请求发言），跟着的人轮到回话，照样跟着
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

/// 约定：答应后照常活动，到点前提醒双方；到时都在就算见上，没去的人记爽约。
#[test]
fn appointments_remind_both_and_record_who_did_not_come() {
    let mut w = world(&[("a", "陈默", "loc_a"), ("b", "何青", "loc_a")]);
    let meet = |w: &mut World, key: &str, at: f64| {
        act(
            w,
            "b",
            key,
            Cmd::Offer {
                partner_id: "a".into(),
                interaction: InteractionKind::Appointment {
                    locale: "loc_b".into(),
                    at,
                },
                message: "下午在乙地碰头。".into(),
            },
        );
        act(
            w,
            "a",
            &format!("{key}-yes"),
            Cmd::Reply {
                interaction_id: key.into(),
                accept: true,
                message: "好，到时见。".into(),
            },
        );
    };
    let now = w.minutes();
    meet(&mut w, "kept", now + 60.);
    meet(&mut w, "missed", now + 300.);
    // 答应了约定照常活动，不占身体
    assert!(w.actor("a").unwrap().waiting_for_plan());
    let notices = |w: &World, id: &str| {
        w.actor(id)
            .unwrap()
            .journal
            .events
            .iter()
            .filter(|e| e.kind == protocol::FactKind::Notice && e.text.contains("还有 30 分钟"))
            .count()
    };
    w.step(35.);
    assert_eq!(
        (notices(&w, "a"), notices(&w, "b")),
        (1, 1),
        "到点前提醒双方，只提醒一次"
    );
    for id in ["a", "b"] {
        common::run(
            &mut w,
            id,
            "go",
            json!({"intent":{"verb":"前往","locale":"loc_b"}}),
        )
        .unwrap();
        common::finish(&mut w, id, "go");
    }
    w.step(30.);
    assert_eq!(status(&w, "kept"), InteractionStatus::Succeeded);
    // 第二个约定之前陈默回了甲地：何青等到宽限过去，记下陈默没去
    common::run(
        &mut w,
        "a",
        "back",
        json!({"intent":{"verb":"前往","locale":"loc_a"}}),
    )
    .unwrap();
    common::finish(&mut w, "a", "back");
    w.step(300.);
    let missed = w.interactions().of("a", "missed").unwrap();
    assert_eq!(missed.status, InteractionStatus::Interrupted);
    assert!(missed
        .reason
        .as_deref()
        .unwrap()
        .contains("陈默没有按约到乙地"));
}

/// 查看四周：回执写明这里有什么、谁在，末尾说明没写到的就是没有。路过的同行可以跟上，多人一起走。
#[test]
fn looking_around_lists_what_is_here_and_a_third_person_can_join_a_walk() {
    let mut w = world(&[
        ("a", "陈默", "loc_a"),
        ("b", "何青", "loc_a"),
        ("c", "苏晴", "loc_a"),
    ]);
    common::run(&mut w, "a", "look", json!({"intent":{"verb":"查看四周"}})).unwrap();
    let look = common::finish(&mut w, "a", "look");
    let text = look.changes.join("");
    assert!(
        text.contains("何青")
            && text.contains("苏晴")
            && text.contains("除此之外，这里没有别的东西")
    );

    act(
        &mut w,
        "b",
        "walk",
        Cmd::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Walk {
                leader: "b".into(),
                locale: Some("loc_b".into()),
            },
            message: "跟我去乙地。".into(),
        },
    );
    act(
        &mut w,
        "a",
        "walk-yes",
        Cmd::Reply {
            interaction_id: "walk".into(),
            accept: true,
            message: "走。".into(),
        },
    );
    act(
        &mut w,
        "c",
        "join",
        Cmd::Join {
            interaction_id: "walk".into(),
            message: "我也去。".into(),
        },
    );
    assert_eq!(w.following("c"), Some("b"));
    for _ in 0..200 {
        w.step(0.05);
        if status(&w, "walk") != InteractionStatus::Running {
            break;
        }
    }
    assert_eq!(status(&w, "walk"), InteractionStatus::Succeeded);
    for id in ["a", "b", "c"] {
        assert_eq!(w.actor(id).unwrap().locus.locale, "loc_b");
    }
}

/// 带路人刚跨进广场就停下，跟着的人停在身后几步、还在路上：也算一起到了，跟着的人挪进广场。
#[test]
fn a_follower_a_few_steps_behind_at_the_entrance_still_arrives_inside() {
    let mut w = open_world(&[("a", "林夏", "loc_a")]);
    enter(&mut w);
    act(
        &mut w,
        ID,
        "walk",
        Cmd::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Walk {
                leader: ID.into(),
                locale: Some("loc_b".into()),
            },
            message: "跟我去广场。".into(),
        },
    );
    act(
        &mut w,
        "a",
        "walk-yes",
        Cmd::Reply {
            interaction_id: "walk".into(),
            accept: true,
            message: "好呀。".into(),
        },
    );
    // 化身从 x=2 走到刚过分界的 x≈10.5 停下
    let pace = w.avatar_walk().unwrap().metres_per_minute;
    walk_avatar(&mut w, [1., 0.], 8.5 / pace);
    for _ in 0..10 {
        w.step(0.05);
    }
    assert_eq!(status(&w, "walk"), InteractionStatus::Succeeded);
    assert_eq!(w.actor("a").unwrap().locus.locale, "loc_b", "挪进了广场");
}

/// 约好在广场见：村民站在广场入口的落脚点，玩家站在他身边的路面上（还没跨进广场），也算见上了。
#[test]
fn meeting_side_by_side_at_the_entrance_keeps_the_appointment() {
    let mut w = open_world(&[("a", "老周", "loc_a")]);
    enter(&mut w);
    let at = w.minutes() + 20.;
    act(
        &mut w,
        ID,
        "meet",
        Cmd::Offer {
            partner_id: "a".into(),
            interaction: InteractionKind::Appointment {
                locale: "loc_b".into(),
                at,
            },
            message: "过一会儿广场见？".into(),
        },
    );
    act(
        &mut w,
        "a",
        "meet-yes",
        Cmd::Reply {
            interaction_id: "meet".into(),
            accept: true,
            message: "行。".into(),
        },
    );
    common::run(
        &mut w,
        "a",
        "go",
        json!({"intent":{"verb":"前往","locale":"loc_b"}}),
    )
    .unwrap();
    common::finish(&mut w, "a", "go");
    // 化身从 x=2 走到 x≈9.5，还在路上（甲处）
    let pace = w.avatar_walk().unwrap().metres_per_minute;
    walk_avatar(&mut w, [1., 0.], 7.5 / pace);
    assert_eq!(w.avatar().unwrap().locus.locale, "loc_a");
    w.step(30.);
    assert_eq!(status(&w, "meet"), InteractionStatus::Succeeded);
}

/// 跟着走的村民起步时躺在床上（床的占地盖住他的落脚点）：也能起身跟着出门。
#[test]
fn a_follower_on_the_bed_gets_up_and_follows_out_of_the_door() {
    let mut w = world(&[("a", "林夏", "loc_a")]);
    let mut map = (**w.walk_map.as_ref().unwrap()).clone();
    map.obstacles.push(Obstacle {
        id: "bed".into(),
        spot: spot("loc_a", 2., 2.),
        half: [0.6, 0.6],
    });
    w.walk_map = Some(Arc::new(map));
    enter(&mut w);
    // 化身站到两三米外再说话：离床太远，不能直接一步站过去
    let pace = w.avatar_walk().unwrap().metres_per_minute;
    w.avatar_move([1., 0.], false, 1.6 / pace).unwrap();
    talk(&mut w);
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
            message: "跟我来。".into(),
            to: None,
        },
    );
    act(
        &mut w,
        "a",
        "accept",
        Cmd::Accept {
            interaction_id: "chat".into(),
            message: "好呀。".into(),
            locale: None,
        },
    );
    w.avatar_portal("door").unwrap();
    for _ in 0..40 {
        w.step(0.05);
    }
    assert_eq!(
        w.actor("a").unwrap().locus.locale,
        "loc_b",
        "起身跟着穿过了门"
    );
}

/// 大逃杀第二局：有人站在新放的道具跟前、落在可走格子外，之后每个动作都被拒，三个人卡到渴死；
/// 那样的存档也读不回来。现在站在走不通的地方先迈出去再走；读档时落在区域外的人挪回区域里。
#[test]
fn a_resident_left_where_nobody_can_stand_walks_away_and_the_save_reloads() {
    let bed = |w: &mut World| {
        let mut map = (**w.walk_map.as_ref().unwrap()).clone();
        map.obstacles.push(Obstacle {
            id: "bed".into(),
            spot: spot("loc_a", 6., 6.),
            half: [0.6, 0.6],
        });
        w.walk_map = Some(Arc::new(map));
    };
    let at = |w: &World, position: [f64; 2]| {
        let mut snap = serde_json::to_value(w.snapshot()).unwrap();
        snap["actors"]["a"]["locus"]["at"] =
            json!({"kind": "free", "space": "loc_a", "position": position});
        let mut restored = world(&[("a", "林夏", "loc_a")]);
        bed(&mut restored);
        restored
            .restore_snapshot(serde_json::from_value(snap).unwrap())
            .unwrap();
        restored
    };
    let mut w = world(&[("a", "林夏", "loc_a")]);
    bed(&mut w);

    // 贴着床站：人物半径里碰着床，这一格走不通，照样能走到乙处
    let mut stuck = at(&w, [6.7, 6.]);
    common::run(
        &mut stuck,
        "a",
        "go",
        json!({"intent":{"verb":"前往","locale":"loc_b"}}),
    )
    .unwrap();
    let r = common::finish(&mut stuck, "a", "go");
    assert_eq!(
        stuck.action_group("a", "go").unwrap().status,
        protocol::GroupStatus::Succeeded,
        "{r:?}"
    );
    assert_eq!(stuck.actor("a").unwrap().locus.locale, "loc_b");

    // 站在甲处区域外 0.3 米：读档时挪回区域里，读得回来
    let outside = at(&w, [20.3, 6.]);
    let protocol::At::Free { position, .. } = &outside.actor("a").unwrap().locus.at else {
        panic!("该还在自由位置上");
    };
    assert!(
        position[0] < 20. && (position[1] - 6.).abs() < 1.,
        "{position:?}"
    );
}
