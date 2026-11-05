use crate::common;
use kernel::{
    avatar::{Area, Spot, Surface, WalkMap},
    navigation::space::Terrain,
    needs::NeedValues,
    Event, World,
};
use protocol::{
    GameModeChoice, GameModeContext, GameModeView, PhysiologySwitches, TideCircle, TidePhase,
    TideView,
};
use std::{collections::BTreeMap, sync::Arc};

const HOUR: f64 = 60.0;
const GOAL: [f64; 2] = [24.0, 18.0];

/// 一座圆岛：最高处在 (24, 18)，离它约 14.6 米以外是海。甲站在最高处，乙站在离它 12 米的东岸。
fn island() -> World {
    let mut w = common::world_with(
        common::tiny_topology(),
        7.0 * HOUR,
        &[("a", "甲", "loc_a"), ("b", "乙", "loc_b")],
    );
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
    w.game_mode_view().map(|GameModeView::Tide(v)| v)
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

    // 每天 20:00 停在当天那一圈：都在上一圈里，前四圈都包住最高处。
    for day in 1..=4 {
        let target = f64::from(day) * 1440.0 + 20.0 * HOUR;
        w.step(target - w.minutes());
        let v = tide(&w).unwrap();
        assert_eq!((v.phase, v.ring), (TidePhase::Holding, day));
        assert!(dist(v.edge.center, previous.center) + v.edge.radius <= previous.radius + 1e-6);
        assert!(dist(v.edge.center, GOAL) <= v.edge.radius);
        previous = v.edge;
    }

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

    // 第 6 天 18:00 最后一圈涨完：水漫过全岛。
    let events = w.step(5.0 * 1440.0 + 18.0 * HOUR - w.minutes());
    assert!(logs(&events).iter().any(|t| t == "【潮水】水漫过了全岛。"));
    let v = tide(&w).unwrap();
    assert_eq!((v.phase, v.edge.radius), (TidePhase::Closed, 0.0));
    assert_eq!(v.edge.center, GOAL);

    // 关掉以后不留痕迹
    w.set_game_mode(None).unwrap();
    assert!(w.game_mode().is_none());
    no_trace(&w);
}
