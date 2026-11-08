use crate::common;
use kernel::{
    weather::{WeatherRequest, WeatherRules},
    World,
};
use protocol::{
    Exposure, InteractionCommand, InteractionKind, WeatherKind as Kind, WeatherMode as Mode,
};
use serde_json::{json, Value};
use std::{collections::BTreeMap, sync::Arc};
fn rules() -> WeatherRules {
    common::weather_rules()
}
fn world() -> World {
    let mut topo = common::tiny_topology();
    for id in ["bench_a", "bench_b"] {
        topo.prop_mut(id).unwrap().verbs[0].duration_minutes = Some(2.);
    }
    let mut w = common::world_with(
        topo,
        420.,
        &[
            ("a", "甲", "loc_a"),
            ("b", "乙", "loc_b"),
            ("c", "丙", "loc_a"),
        ],
    );
    // 无命名暗示的真实行走区域，A 室外、B 和孤岛 C 室内。
    use kernel::avatar::{Area, Spot, Surface, WalkMap};
    w.walk_map = Some(Arc::new(WalkMap {
        version: 1,
        svg_units_per_metre: 10.,
        metres_per_minute: 12.,
        outdoor_space: "town_outdoor".into(),
        surfaces: vec![
            ("loc_a", "town_outdoor"),
            ("loc_b", "room_b"),
            ("loc_c", "room_c"),
            ("edge_ab", "town_outdoor"),
        ]
        .into_iter()
        .map(|(locale, space)| Surface {
            locale: locale.into(),
            space: space.into(),
            area: Area::Rect {
                min: [0., 0.],
                max: [30., 30.],
            },
        })
        .collect(),
        stations: BTreeMap::from([
            (
                "st_a".into(),
                Spot {
                    locale: "loc_a".into(),
                    space: "town_outdoor".into(),
                    position: [2., 2.],
                },
            ),
            (
                "st_b".into(),
                Spot {
                    locale: "loc_b".into(),
                    space: "room_b".into(),
                    position: [2., 2.],
                },
            ),
        ]),
        ..Default::default()
    }));
    w.enable_weather(rules(), 123456789, "weather-test".into())
        .unwrap();
    w
}
fn set(w: &mut World, id: &str, mode: Mode, kind: Option<Kind>) {
    w.set_weather(WeatherRequest {
        request_id: id.into(),
        expected_revision: w.weather().unwrap().view.revision,
        mode,
        kind,
    })
    .unwrap();
}
fn state(w: &World) -> Value {
    json!(w.weather().unwrap())
}
#[test]
fn schedule_is_independent_replayable_and_fixed_mode_preserves_rng() {
    let mut a = world();
    let mut b = world();
    a.step(3000.);
    for _ in 0..12000 {
        b.step(0.25);
    }
    assert_eq!(state(&a), state(&b));
    let mut restored = common::restore(&a, world());
    for w in [&mut a, &mut restored] {
        w.step(700.);
    }
    assert_eq!(state(&a), state(&restored));
    let before = state(&a);
    a.step(0.);
    assert_eq!(before, state(&a));
    set(&mut a, "fixed", Mode::Fixed, Some(Kind::Snow));
    let rng = state(&a)["rng"].clone();
    a.step(500.);
    assert_eq!(state(&a)["rng"], rng);
    assert_eq!(a.weather().unwrap().view.kind, Kind::Snow);
    set(&mut a, "natural", Mode::Natural, None);
    let schedule = state(&a)["next_check_at"].clone();
    let rng = state(&a)["rng"].clone();
    set(&mut a, "noop", Mode::Natural, None);
    assert_eq!(state(&a)["next_check_at"], schedule);
    assert_eq!(state(&a)["rng"], rng);
    let request = WeatherRequest {
        request_id: "replay".into(),
        expected_revision: a.weather().unwrap().view.revision,
        mode: Mode::Fixed,
        kind: Some(Kind::Rain),
    };
    let receipt = a.set_weather(request.clone()).unwrap();
    set(&mut a, "later", Mode::Fixed, Some(Kind::Clear));
    let before = state(&a);
    assert_eq!(a.set_weather(request.clone()).unwrap(), receipt);
    assert_eq!(state(&a), before);
    let mut changed = request;
    changed.kind = Some(Kind::Snow);
    assert!(a.set_weather(changed).is_err());
    malformed_weather_is_rejected_without_replacing_world();
}
fn malformed_weather_is_rejected_without_replacing_world() {
    let mut w = world();
    let original = json!(w.snapshot());
    for (key, value) in [
        ("next_check_at", json!(420)),
        (
            "rng",
            json!({"algorithm":"xorshift32-v1","seed":1,"state":0}),
        ),
        ("next_event_id", json!(0)),
    ] {
        let mut bad = original.clone();
        bad["weather"]["weather"][key] = value;
        assert!(w
            .restore_snapshot(serde_json::from_value(bad).unwrap())
            .is_err());
        assert_eq!(json!(w.snapshot()), original);
    }
    let mut bad = original.clone();
    bad.as_object_mut().unwrap().remove("weather");
    assert!(w
        .restore_snapshot(serde_json::from_value(bad).unwrap())
        .is_err());
    let mut old = original.clone();
    old["schema_version"] = json!(4);
    old.as_object_mut().unwrap().remove("weather");
    let mut snap: kernel::WorldSnapshot = serde_json::from_value(old).unwrap();
    snap.migrate_weather(w.weather(), "old-world").unwrap();
    w.restore_snapshot(snap).unwrap();
    assert_eq!(w.minutes(), 420.);
    assert_eq!(w.weather().unwrap().view.world_id, "old-world");
    assert_eq!(w.actor_ids().len(), 3);
}
#[test]
fn thunderstorm_interrupts_outdoor_work_only_and_preserves_progress() {
    let mut w = world();
    for actor in ["a", "b"] {
        common::run(&mut w, actor,"work",json!({"prop_id":format!("bench_{actor}"),"intent":{"verb":"工作","duration_minutes":2}})).unwrap();
    }
    w.step(1.);
    set(&mut w, "rain", Mode::Fixed, Some(Kind::Rain));
    assert_eq!(w.actor("a").unwrap().current.verb, "工作");
    let revision = w.actor("a").unwrap().actions.revision;
    assert!(w
        .actor("a")
        .unwrap()
        .journal
        .events
        .iter()
        .filter(|e| e.text.contains("天气变化"))
        .all(|e| e.kind == protocol::FactKind::Observation));
    let energy = w.actor("a").unwrap().needs.energy.value;
    set(&mut w, "storm", Mode::Fixed, Some(Kind::Thunderstorm));
    assert_ne!(w.actor("a").unwrap().current.verb, "工作");
    assert_eq!(w.actor("a").unwrap().needs.energy.value, energy);
    assert!(w.actor("a").unwrap().actions.revision > revision);
    assert_eq!(w.actor("b").unwrap().current.verb, "工作");
    assert!(common::run(
        &mut w,
        "a",
        "blocked",
        json!({"intent":{"verb":"停留","duration_minutes":10}})
    )
    .unwrap_err()
    .to_string()
    .contains("weather_unsafe"));
    assert_eq!(w.exposure_at("a"), Exposure::Outdoor);
    assert_eq!(w.exposure_at("b"), Exposure::Indoor);
    assert_eq!(
        w.indoor_alternatives("a")
            .iter()
            .map(|p| p.locale.as_str())
            .collect::<Vec<_>>(),
        vec!["loc_b"]
    );
    common::run(
        &mut w,
        "a",
        "shelter",
        json!({"intent":{"verb":"前往","locale":"loc_b"}}),
    )
    .unwrap();
    w.step(3.);
    assert_eq!(w.exposure_at("a"), Exposure::Indoor);
    arrival_and_completion_boundary_recheck_weather_before_effects_or_next_action();
    active_chat_is_interrupted_but_outdoor_food_is_allowed();
}
fn arrival_and_completion_boundary_recheck_weather_before_effects_or_next_action() {
    let mut w = world();
    let mut r = rules();
    r.minimum_minutes = 2;
    r.maximum_minutes = 2;
    for row in &mut r.transitions {
        *row = [0, 0, 0, 0, 0, 100, 0];
    }
    w.enable_weather(r, 42, "boundary".into()).unwrap();
    common::run(
        &mut w,
        "a",
        "finish-outside",
        json!({"prop_id":"bench_a","intent":{"verb":"工作","duration_minutes":2}}),
    )
    .unwrap();
    let rev = w.actor("b").unwrap().actions.revision;
    w.run_actions("b","arrive-outside",rev,&serde_json::from_value::<Vec<protocol::ActionDraft>>(json!([
        {"intent":{"verb":"前往","locale":"loc_a"}}, {"prop_id":"bench_a","intent":{"verb":"工作","duration_minutes":2}}
    ])).unwrap()).unwrap();
    w.step(2.);
    assert_eq!(w.weather().unwrap().view.kind, Kind::Thunderstorm);
    assert_eq!(
        w.action_group("a", "finish-outside").unwrap().results[0].status,
        protocol::ActionStatus::Interrupted
    );
    assert_eq!(w.exposure_at("b"), Exposure::Outdoor);
    assert_ne!(w.actor("b").unwrap().current.verb, "工作");
    assert!(w
        .action_group("b", "arrive-outside")
        .unwrap()
        .results
        .iter()
        .any(|r| r.status == protocol::ActionStatus::Failed));
}
fn active_chat_is_interrupted_but_outdoor_food_is_allowed() {
    let mut w = world();
    for (actor, id, command) in [
        (
            "a",
            "invite",
            InteractionCommand::Offer {
                partner_id: "c".into(),
                interaction: InteractionKind::Talk,
                message: "你好".into(),
            },
        ),
        (
            "c",
            "accept",
            InteractionCommand::Reply {
                interaction_id: "invite".into(),
                accept: true,
                message: "好".into(),
            },
        ),
    ] {
        w.interact(
            actor,
            id,
            w.actor(actor).unwrap().actions.revision,
            &command,
        )
        .unwrap();
    }
    set(&mut w, "storm", Mode::Fixed, Some(Kind::Thunderstorm));
    assert!(w.actor("a").unwrap().current.interaction.is_none());
    assert!(w.actor("c").unwrap().current.interaction.is_none());
    assert!(w
        .interact(
            "a",
            "new",
            w.actor("a").unwrap().actions.revision,
            &InteractionCommand::Offer {
                partner_id: "c".into(),
                interaction: InteractionKind::Talk,
                message: "你好".into()
            }
        )
        .unwrap_err()
        .to_string()
        .contains("weather_unsafe"));
    let topo = common::two_places(
        json!([{"id":"food","locale":"loc_a","name":"干粮","definition":"test:rations@1"}]),
    );
    let mut food = common::world_with(topo, 420., &[("a", "甲", "loc_a")]);
    food.walk_map = w.walk_map.clone();
    food.enable_weather(rules(), 4, "food".into()).unwrap();
    set(&mut food, "storm", Mode::Fixed, Some(Kind::Thunderstorm));
    common::run(
        &mut food,
        "a",
        "eat",
        json!({"prop_id":"food","intent":{"verb":"吃干粮"}}),
    )
    .unwrap();
    assert_eq!(
        common::finish(&mut food, "a", "eat").status,
        protocol::ActionStatus::Succeeded
    );
}

/// 气候：热带不下雪、雷暴少，存档读回来还是热带；温带照原来的转移表。
#[test]
fn a_tropical_climate_never_snows_and_storms_less_and_survives_a_reload() {
    let count = |climate: protocol::Climate| {
        let mut w = world();
        w.set_climate(climate).unwrap();
        let (mut snow, mut storm) = (0, 0);
        for _ in 0..4000 {
            w.step(60.);
            match w.weather().unwrap().view.kind {
                Kind::Snow => snow += 1,
                Kind::Thunderstorm => storm += 1,
                _ => {}
            }
        }
        (w, snow, storm)
    };
    let (_, snow, storm) = count(protocol::Climate::Temperate);
    let (tropical, tropical_snow, tropical_storm) = count(protocol::Climate::Tropical);
    assert!(snow > 0, "温带该下过雪");
    assert_eq!(tropical_snow, 0);
    assert!(
        tropical_storm * 3 < storm * 2,
        "热带雷暴 {tropical_storm}，温带 {storm}"
    );
    let restored = common::restore(&tropical, world());
    assert_eq!(restored.climate(), protocol::Climate::Tropical);
}
