use crate::common;
use kernel::{
    avatar::{Area, Spot, Surface, WalkMap},
    navigation::space::Terrain,
    needs::NeedValues,
    Event, World,
};
use protocol::{
    FactKind, GameModeAction, GameModeChoice, GameModeContext, GameModeView, GroupStatus,
    PhysiologySwitches, TideCircle, TideNewsKind, TidePhase, TideView, WerewolfOut, WerewolfPhase,
    WerewolfRole, WerewolfSide, WerewolfView,
};
use serde_json::json;
use std::{collections::BTreeMap, sync::Arc};

const HOUR: f64 = 60.0;
const GOAL: [f64; 2] = [24.0, 18.0];

/// 一座圆岛：最高处在 (24, 18)，离它约 14.6 米以外是海。甲站在最高处，乙站在离它 12 米的东岸。
fn island() -> World {
    island_with(&[("a", "甲", "loc_a"), ("b", "乙", "loc_b")])
}

/// 同一座岛，住进这些人：loc_a 的落脚点在最高处，loc_b 的在东岸。
fn island_with(people: &[(&str, &str, &str)]) -> World {
    let mut w = common::world_with(common::tiny_topology(), 7.0 * HOUR, people);
    let (columns, rows) = (41, 41);
    let heights = (0..rows)
        .flat_map(|z| {
            (0..columns)
                .map(move |x| 2.0 - (f64::from(x) - GOAL[0]).hypot(f64::from(z) - GOAL[1]) / 7.5)
        })
        .collect();
    let spot = |locale: &str, position| Spot {
        locale: locale.into(),
        space: "town_outdoor".into(),
        position,
    };
    w.walk_map = Some(Arc::new(WalkMap {
        version: 1,
        svg_units_per_metre: 10.,
        metres_per_minute: 12.,
        outdoor_space: "town_outdoor".into(),
        surfaces: ["loc_a", "loc_b", "edge_ab"]
            .into_iter()
            .map(|locale| Surface {
                locale: locale.into(),
                space: "town_outdoor".into(),
                area: Area::Rect {
                    min: [0., 0.],
                    max: [40., 40.],
                },
            })
            .collect(),
        stations: BTreeMap::from([
            ("st_a".into(), spot("loc_a", GOAL)),
            ("st_b".into(), spot("loc_b", [36., 18.])),
        ]),
        terrain: Some(Terrain {
            origin: [0., 0.],
            step: 1.0,
            columns: columns as usize,
            rows: rows as usize,
            heights,
        }),
        sea_level: 0.0,
        ..Default::default()
    }));
    // 只留精力在变，五天里没人吃喝睡也不会死，方便看潮水多扣的那份。
    w.set_physiology(PhysiologySwitches {
        fullness: false,
        energy: true,
        water: false,
        health: false,
        weather: false,
    });
    w
}

fn logs(events: &[Event]) -> Vec<String> {
    events
        .iter()
        .map(|e| {
            let Event::Log { text, .. } = e;
            text.clone()
        })
        .collect()
}

fn dist(a: [f64; 2], b: [f64; 2]) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}

fn tide(w: &World) -> Option<TideView> {
    match w.game_mode_view() {
        Some(GameModeView::Tide(v)) => Some(v),
        _ => None,
    }
}

/// 没开玩法时存档和名册里都没有玩法的字段，和没有玩法这回事时一样。
fn no_trace(w: &World) {
    let snapshot = serde_json::to_value(w.snapshot()).unwrap();
    assert!(snapshot.get("game_mode").is_none());
    let roster = serde_json::to_value(w.roster(1.0)).unwrap();
    assert!(roster.get("game_mode").is_none());
}

fn rested(w: &mut World) {
    for id in ["a", "b"] {
        w.adjust_body(
            id,
            NeedValues {
                fullness: None,
                energy: Some(90.0),
                water: None,
                health: None,
            },
        )
        .unwrap();
    }
}

#[test]
fn tide_rings_shrink_onto_the_high_ground_and_drain_whoever_stands_in_water() {
    let mut w = island();
    assert!(w.game_mode().is_none());
    no_trace(&w);
    // 第 1 天 07:00 打开：今天的 06:00 已过，第 1 圈第 2 天天亮公布。
    w.set_game_mode(Some(&GameModeChoice::Tide { seed: Some(7) }))
        .unwrap();
    assert_eq!(w.game_mode(), Some("tide"));
    let v = tide(&w).unwrap();
    assert_eq!((v.phase, v.ring, v.rings), (TidePhase::Waiting, 0, 5));
    let mut previous: TideCircle = v.edge;
    assert!(dist(previous.center, GOAL) + 0.1 < previous.radius);

    // 第 2 天 08:00：第 1 圈已公布，所有人都收到公告。
    let events = w.step(25.0 * HOUR);
    assert!(logs(&events)
        .iter()
        .any(|t| t.starts_with("【潮水】第 1 圈已公布")));
    let v = tide(&w).unwrap();
    assert_eq!((v.phase, v.ring), (TidePhase::Announced, 1));
    let first = v.next.unwrap();

    // 15:00 正在涨：水边在两圈之间；存档读档后接着涨到同一个位置。
    w.step(7.0 * HOUR);
    let v = tide(&w).unwrap();
    assert_eq!(v.phase, TidePhase::Rising);
    assert!(v.edge.radius < previous.radius && v.edge.radius > first.radius);
    let mut restored = island();
    restored.restore_snapshot(w.snapshot()).unwrap();
    assert_eq!(tide(&restored), tide(&w));
    w = restored;

    // 每天 20:00 停在当天那一圈：都在上一圈里，前四圈都包住最高处。第 2 到第 4 圈公布时各冲上来一只木箱。
    let mut crates = 0;
    for day in 1..=4 {
        let target = f64::from(day) * 1440.0 + 20.0 * HOUR;
        let events = w.step(target - w.minutes());
        crates += logs(&events)
            .iter()
            .filter(|t| t.contains("潮水冲上来一只木箱"))
            .count();
        let v = tide(&w).unwrap();
        assert_eq!((v.phase, v.ring), (TidePhase::Holding, day));
        assert!(dist(v.edge.center, previous.center) + v.edge.radius <= previous.radius + 1e-6);
        assert!(dist(v.edge.center, GOAL) <= v.edge.radius);
        previous = v.edge;
    }
    assert_eq!(crates, 3);

    // 第 4 圈只剩山顶一小块：乙站在水里，比站在山顶的甲每小时多掉 6 点精力。
    rested(&mut w);
    w.step(HOUR);
    let energy = |w: &World, id: &str| w.actor(id).unwrap().needs.energy.value;
    let (a, b) = (energy(&w, "a"), energy(&w, "b"));
    assert!((a - b - 6.0).abs() < 0.5, "甲 {a} 乙 {b}");
    let Some(GameModeContext::Tide(context)) = w.game_mode_context("b") else {
        panic!("开着潮水圈时乙的模型该看到潮水这一栏");
    };
    assert!(context.standing.unwrap().starts_with("你站在潮水里"));

    // 第 6 天天亮船停到最高处，只坐一个人；没人去登船，18:00 水漫过全岛，船带走离它最近的甲。
    let events = w.step(5.0 * 1440.0 + 18.0 * HOUR - w.minutes());
    let lines = logs(&events);
    assert!(lines
        .iter()
        .any(|t| t.starts_with("【潮水】最后一圈已公布") && t.contains("只坐得下一个人")));
    assert!(lines.iter().any(|t| t == "【潮水】水漫过了全岛。"));
    assert!(lines
        .iter()
        .any(|t| t == "【潮水】甲离船最近，被船带走了，是这一局唯一活着离开的人。"));
    let v = tide(&w).unwrap();
    assert_eq!((v.phase, v.edge.radius), (TidePhase::Over, 0.0));
    assert_eq!(v.edge.center, GOAL);
    assert_eq!(v.winner.as_deref(), Some("a"));
    assert!(!w.actor("a").unwrap().present());

    // 关掉以后不留痕迹
    w.set_game_mode(None).unwrap();
    assert!(w.game_mode().is_none());
    no_trace(&w);
}

const KNIFE: &str = r#"{"id":"core:kitchen_knife","version":1,"name":"菜刀","description":"一把厚背菜刀，刀口很利。","portable":true,
 "actions":[{"id":"stab","label":"持刀袭击","duration_minutes":3,"completion":"activity",
  "on_complete":[{"kind":"harm","amount":100,"wound":"胸口一处刀伤"}],"recipient":true}]}"#;

#[test]
fn tide_hands_the_boat_to_the_last_one_standing_and_keeps_the_fights_in_its_news() {
    // 三个人都在最高处；只看健康和精力。
    let people = [
        ("a", "甲", "loc_a"),
        ("b", "乙", "loc_a"),
        ("c", "丙", "loc_a"),
    ];
    let mut w = island_with(&people);
    w.set_physiology(PhysiologySwitches {
        fullness: false,
        energy: true,
        water: false,
        health: true,
        weather: false,
    });
    w.set_game_mode(Some(&GameModeChoice::Tide { seed: Some(7) }))
        .unwrap();
    // 开局每人一张纸条，模型一直看得到目标
    let events = w.step(1.0);
    assert!(logs(&events)
        .iter()
        .any(|t| t.starts_with("【纸条】") && t.contains("第 6 天会来一条船")));
    let Some(GameModeContext::Tide(context)) = w.game_mode_context("c") else {
        panic!("丙的模型该看到潮水这一栏");
    };
    assert!(context.goal.starts_with("只有一个人能活着离开"));
    assert_eq!(tide(&w).unwrap().players.len(), 3);

    // 甲拿地上的菜刀刺死乙：战报里有这一刀，名册里写着乙怎么死的
    let knife: kernel::props::Definition = serde_json::from_str(KNIFE).unwrap();
    w.place_prop(
        serde_json::from_value(json!({
            "instance":{"id":"knife","definition":knife.reference(),"locale":"loc_a"},
            "definition":knife
        }))
        .unwrap(),
    )
    .unwrap();
    let stab = |w: &mut World, key: &str, whom: &str| {
        common::run(
            w,
            "a",
            key,
            json!({"prop_id":"knife","intent":{"verb":"持刀袭击"},"recipient":whom}),
        )
        .unwrap();
        common::finish(w, "a", key);
        assert_eq!(
            w.action_group("a", key).unwrap().status,
            GroupStatus::Succeeded
        );
    };
    stab(&mut w, "stab-b", "b");
    w.step(5.0);
    let v = tide(&w).unwrap();
    assert!(v
        .news
        .iter()
        .any(|n| n.kind == TideNewsKind::Clash && n.text == "甲持刀袭击乙，健康 −100，乙倒下了"));
    let fell = |v: &TideView, id: &str| {
        v.players
            .iter()
            .find(|p| p.id == id)
            .and_then(|p| p.fell.clone())
    };
    assert_eq!(fell(&v, "b").as_deref(), Some("被甲杀死（胸口一处刀伤）"));
    assert!(v.winner.is_none());

    // 甲又刺死丙：只剩甲，船提前开来接走他，这一局结束，读档后结果还在
    stab(&mut w, "stab-c", "c");
    let events = w.step(5.0);
    assert!(logs(&events).iter().any(
        |t| t == "【潮水】岛上只剩甲一个人了，船提前开来接走了他。甲是这一局唯一活着离开的人。"
    ));
    let v = tide(&w).unwrap();
    assert_eq!((v.phase, v.winner.as_deref()), (TidePhase::Over, Some("a")));
    assert!(fell(&v, "c").is_some());
    assert!(!w.actor("a").unwrap().present());
    assert_eq!(w.game_mode_tempo(), 1.0);
    let mut restored = island_with(&people);
    restored.restore_snapshot(w.snapshot()).unwrap();
    assert_eq!(tide(&restored), tide(&w));
}

fn werewolf(w: &World) -> WerewolfView {
    match w.game_mode_view() {
        Some(GameModeView::Werewolf(v)) => v,
        other => panic!("开着的该是狼人杀：{other:?}"),
    }
}

fn wolf_context(w: &World, id: &str) -> protocol::WerewolfContext {
    match w.game_mode_context(id) {
        Some(GameModeContext::Werewolf(c)) => c,
        other => panic!("{id} 的模型该看到狼人杀这一栏：{other:?}"),
    }
}

fn mode_act(w: &mut World, id: &str, action: &str, target: Option<u32>, text: Option<&str>) {
    let action = GameModeAction {
        action: action.into(),
        target: target.map(|t| t.to_string()),
        text: text.map(str::to_owned),
        reason: Some(format!("{id} 心里这么想")),
    };
    let result = w.game_mode_act(id, &action);
    assert!(result.is_ok(), "{id} 交 {action:?}：{result:?}");
}

/// 一局 9 人：用给模型看的那一栏（werewolf.actions）当成模型，按固定打法交动作，走完整局。
/// 好人每天都投座号最小的狼，狼人每夜刀座号最小的平民；女巫第 1 夜救人，猎人不开枪。
/// 途中故意让一个人发言超时、一个人不投票（到点往下走），议事中途存档读档。
#[test]
fn werewolf_judge_runs_a_whole_game_through_turns_deadlines_and_a_reload() {
    let names = [
        "阿树", "小禾", "芬恩", "露娜", "石头", "米拉", "诺亚", "阿滩", "阿岚",
    ];
    let ids: Vec<String> = (1..=9).map(|n| format!("r{n}")).collect();
    let people: Vec<(&str, &str, &str)> = ids
        .iter()
        .zip(names)
        .map(|(id, name)| (id.as_str(), name, "loc_a"))
        .collect();
    // 吃喝睡关着（预制小镇的默认），四天里没人饿死渴死
    let fresh = || {
        let mut w = common::world_with(common::tiny_topology(), 7.0 * HOUR, &people);
        w.set_physiology(PhysiologySwitches {
            fullness: false,
            energy: false,
            water: false,
            health: false,
            weather: false,
        });
        w
    };
    let mut w = fresh();
    // 人不够开不了，原来的世界不受影响
    let mut few = common::world_with(common::tiny_topology(), 7.0 * HOUR, &people[..5]);
    assert!(few
        .set_game_mode(Some(&GameModeChoice::Werewolf {
            seed: Some(3),
            day_hours: None
        }))
        .is_err());
    assert!(few.game_mode().is_none());

    w.set_game_mode(Some(&GameModeChoice::Werewolf {
        seed: Some(11),
        day_hours: Some(6),
    }))
    .unwrap();
    assert_eq!(w.game_mode(), Some("werewolf"));
    let v = werewolf(&w);
    assert_eq!(
        (v.phase, v.day, v.seats.len()),
        (WerewolfPhase::Waiting, 0, 9)
    );
    let count = |role| v.seats.iter().filter(|s| s.role == role).count();
    assert_eq!(
        (count(WerewolfRole::Wolf), count(WerewolfRole::Villager)),
        (3, 3)
    );
    let role_of = |seat: u32| v.seats[seat as usize - 1].role;
    let seat_of = |role| v.seats.iter().find(|s| s.role == role).unwrap().seat;
    let (seer, witch, hunter) = (
        seat_of(WerewolfRole::Seer),
        seat_of(WerewolfRole::Witch),
        seat_of(WerewolfRole::Hunter),
    );
    let villagers: Vec<u32> = v
        .seats
        .iter()
        .filter(|s| s.role == WerewolfRole::Villager)
        .map(|s| s.seat)
        .collect();
    let wolves: Vec<u32> = v
        .seats
        .iter()
        .filter(|s| s.role == WerewolfRole::Wolf)
        .map(|s| s.seat)
        .collect();
    // 开局前就有玩法动作工具（整局工具表不变，请求前缀能留在缓存里），但没有要交的
    assert!(w.game_mode_tool("r1").unwrap().contains("vote"));
    assert!(wolf_context(&w, "r1").actions.is_empty());

    // 没开玩法的世界按正常速度走；开局前是空档，走快一点
    assert_eq!(few.game_mode_tempo(), 1.0);
    assert_eq!(w.game_mode_tempo(), 2.0);
    // 第 1 天 10:30 天亮：每人单独收到自己的身份，狼人还知道同伴
    w.step(3.6 * HOUR);
    assert_eq!(werewolf(&w).phase, WerewolfPhase::Day);
    for (k, id) in ids.iter().enumerate() {
        let a = w.actor(id).unwrap();
        let notice = a
            .journal
            .events_after(0)
            .iter()
            .find(|e| e.kind == FactKind::Notice && e.text.contains("身份是"))
            .unwrap_or_else(|| panic!("{id} 没收到身份"))
            .text
            .clone();
        let seat = k as u32 + 1;
        assert_eq!(
            notice.contains("狼人同伴"),
            role_of(seat) == WerewolfRole::Wolf
        );
    }

    let id_of = |seat: u32| ids[seat as usize - 1].clone();
    let alive = |w: &World, seat: u32| werewolf(w).seats[seat as usize - 1].out.is_none();
    let mut skipped = false;
    let mut abstained = false;
    let mut reloaded = false;
    let mut told_to_stay = false;
    let mut died_at_night = false;
    let mut heard_reason = false;
    for _ in 0..5000 {
        let v = werewolf(&w);
        if v.phase == WerewolfPhase::Over {
            break;
        }
        // 发言、投票这些有期限的回合照常速；发言记下了交的时候写的打算（只给旁观的人看）
        if v.phase == WerewolfPhase::Speech {
            assert_eq!(w.game_mode_tempo(), 1.0);
            if let Some(line) = v.lines.last() {
                heard_reason |= line
                    .reason
                    .as_deref()
                    .is_some_and(|r| r.ends_with("心里这么想"));
            }
        }
        // 第 2 夜的刀口没人救：夜里的选择交齐就结算，人已经倒下，天亮前座位上还不公布
        if let Some(n) = v.night.as_ref().filter(|n| n.night == 2 && !died_at_night) {
            if v.phase == WerewolfPhase::Night && w.minutes() % (24.0 * HOUR) >= 20.0 * HOUR {
                let k = n.kill.expect("第 2 夜狼人选了刀口");
                assert!(w.actor(&id_of(k)).unwrap().needs.body.dead);
                assert_eq!(v.seats[k as usize - 1].out, None);
                assert_eq!(w.game_mode_tempo(), 2.0);
                died_at_night = true;
            }
        }
        // 黄昏回家：停留只认时长，法官把离天亮（10:30）还差几分钟算好
        if v.phase == WerewolfPhase::Dusk && !told_to_stay {
            told_to_stay = true;
            let now = wolf_context(&w, "r1").now;
            let left = (24.0 * HOUR + 10.5 * HOUR - (w.minutes() % (24.0 * HOUR))).ceil();
            assert!(
                now.contains(&format!("duration_minutes 填 {left:.0}")),
                "{now}"
            );
        }
        // 第 2 天第三个发言的人不交，到点跳过
        if v.phase == WerewolfPhase::Speech && v.day == 2 && v.lines.len() == 2 && !skipped {
            skipped = true;
            let silent = v.turn.unwrap();
            w.step(16.0);
            let after = werewolf(&w);
            assert_ne!(after.turn, Some(silent));
            assert_eq!(after.lines.len(), 2);
            continue;
        }
        // 第 3 天议事说到一半存档，读进一个新世界接着走
        if v.phase == WerewolfPhase::Speech && v.day == 3 && v.lines.len() == 2 && !reloaded {
            reloaded = true;
            w = common::restore(&w, fresh());
            assert_eq!(werewolf(&w), v);
        }
        let mut acted = false;
        for seat in 1..=9u32 {
            let id = id_of(seat);
            let Some(GameModeContext::Werewolf(c)) = w.game_mode_context(&id) else {
                continue;
            };
            let Some(first) = c.actions.first().cloned() else {
                continue;
            };
            let v = werewolf(&w);
            let lowest = |pred: &dyn Fn(u32) -> bool| (1..=9u32).find(|&s| alive(&w, s) && pred(s));
            match first.as_str() {
                "speak" => mode_act(&mut w, &id, "speak", None, Some("我是好人，大家听我说。")),
                "vote" | "abstain" => {
                    // 第 2 天最后一个人不投，到点算弃票
                    let voted = v.ballots.len();
                    let living = v.seats.iter().filter(|s| s.out.is_none()).count();
                    if v.day == 2 && voted + 1 == living && !abstained {
                        abstained = true;
                        w.step(16.0);
                        assert!(werewolf(&w).revealed);
                        acted = true;
                        break;
                    }
                    let target = if role_of(seat) == WerewolfRole::Wolf {
                        lowest(&|s| !wolves.contains(&s))
                    } else {
                        lowest(&|s| wolves.contains(&s))
                    };
                    mode_act(&mut w, &id, "vote", target, None);
                }
                "kill" => {
                    let target = lowest(&|s| villagers.contains(&s));
                    mode_act(&mut w, &id, "kill", target, Some("刀他。"));
                }
                "check" => {
                    let target = lowest(&|s| s != seat);
                    mode_act(&mut w, &id, "check", target, None);
                }
                "poison" | "save" | "pass" if seat == witch => {
                    let night = v.night.as_ref().map_or(0, |n| n.night);
                    let save = night == 1 && c.actions.iter().any(|a| a == "save");
                    mode_act(&mut w, &id, if save { "save" } else { "pass" }, None, None);
                }
                _ => mode_act(&mut w, &id, "pass", None, None),
            }
            acted = true;
            break;
        }
        if !acted {
            w.step(5.0);
        }
    }
    assert!(skipped && abstained && reloaded && told_to_stay && died_at_night && heard_reason);
    let v = werewolf(&w);
    assert_eq!(
        (v.phase, v.winner),
        (WerewolfPhase::Over, Some(WerewolfSide::Good))
    );
    for &wolf in &wolves {
        assert_eq!(v.seats[wolf as usize - 1].out, Some(WerewolfOut::Exiled));
    }
    // 第 1 夜刀的平民被女巫救下，第 2 夜又被刀倒下，第 3 夜倒下第二个；最后一个平民和神职都活着
    assert_eq!(v.seats[villagers[2] as usize - 1].out, None);
    for &k in &villagers[..2] {
        assert_eq!(v.seats[k as usize - 1].out, Some(WerewolfOut::Killed));
        assert!(w.actor(&id_of(k)).unwrap().needs.body.dead);
    }
    for seat in [seer, witch, hunter] {
        assert_eq!(v.seats[seat as usize - 1].out, None);
    }
    let history = wolf_context(&w, &id_of(seer)).history;
    assert!(
        history.iter().any(|h| h == "第 1 夜：平安夜"),
        "{history:?}"
    );
    assert!(history.iter().any(|h| h.contains("弃票")), "{history:?}");
    // 被放逐的人说完遗言走出村子；出局的人和结束后都没有玩法动作工具
    w.step(30.0);
    for &wolf in &wolves {
        assert!(!w.actor(&id_of(wolf)).unwrap().present());
        assert!(w.game_mode_tool(&id_of(wolf)).is_none());
    }
    assert!(w.game_mode_tool(&id_of(seer)).is_none());

    w.set_game_mode(None).unwrap();
    no_trace(&w);
}
