use crate::common;
use kernel::World;
use protocol::{
    FrostlightPhase, FrostlightView, GameModeAction, GameModeChoice, GameModeView,
    PhysiologySwitches,
};
use serde_json::json;

fn town() -> World {
    let topo = common::topology(&common::two_places_json(|data| {
        data["locales"][0]["name"] = json!("热源广场诊所");
        data["locales"][1]["name"] = json!("林场粮仓工坊");
    }));
    let mut world = common::world_with(
        topo,
        420.0,
        &[("a", "阿树", "loc_a"), ("b", "白雪", "loc_a")],
    );
    world.set_physiology(PhysiologySwitches {
        fullness: false,
        energy: false,
        water: false,
        health: false,
        weather: false,
    });
    world
}

fn open(hours: u32) -> World {
    let mut world = town();
    world
        .set_game_mode(Some(&GameModeChoice::Frostlight {
            seed: Some(11),
            duration_hours: Some(hours),
        }))
        .unwrap();
    world
}

fn action(name: &str, target: Option<&str>) -> GameModeAction {
    GameModeAction {
        action: name.into(),
        target: target.map(str::to_owned),
        text: None,
        reason: None,
    }
}

fn view(world: &World) -> FrostlightView {
    match world.game_mode_view().unwrap() {
        GameModeView::Frostlight(v) => v,
        _ => panic!("expected frostlight"),
    }
}

fn work(world: &mut World, who: &str, name: &str, target: Option<&str>) {
    world.game_mode_act(who, &action(name, target)).unwrap();
}

fn control(world: &mut World, name: &str, target: Option<&str>) {
    world.game_mode_control(&action(name, target)).unwrap();
}

fn finish_work(world: &mut World) {
    for _ in 0..200 {
        if view(world).people.iter().all(|p| p.work.is_none()) {
            return;
        }
        world.step(1.0);
    }
    panic!("labor failed to finish: {:?}", view(world));
}

#[test]
fn labor_physically_travels_and_delivers_once_across_save_and_restore() {
    let mut world = open(6);
    control(&mut world, "heat", Some("0"));
    let initial = view(&world);
    work(&mut world, "a", "work", Some("fuel"));
    assert!(world.game_mode_pending_group("a").is_some());
    assert_eq!(view(&world).fuel, initial.fuel);
    world.step(1.0);
    assert_ne!(
        world.actor("a").unwrap().locus.locale,
        "loc_a",
        "must move before delivery"
    );
    assert_eq!(view(&world).people[0].contribution, 0);
    assert_eq!(view(&world).fuel, initial.fuel);

    let mut world = common::restore(&world, town());
    assert!(
        world
            .game_mode_act("a", &action("work", Some("fuel")))
            .is_err(),
        "in-flight task cannot be duplicated"
    );
    // 身体动作完成和玩法下一拍结算之间允许存盘或开始新的普通行走。
    // 已交付的物资不能因为居民随后离开热源而丢失。
    for _ in 0..400 {
        if world.game_mode_pending_group("a").is_none() {
            break;
        }
        world.step(0.1);
    }
    assert!(world.game_mode_pending_group("a").is_none());
    assert_eq!(view(&world).people[0].contribution, 0);
    assert_eq!(world.actor("a").unwrap().locus.locale, "loc_a");
    let departure = serde_json::from_value(json!({
        "intent": {"verb": "前往", "locale": "loc_b"}
    }))
    .unwrap();
    world
        .run_actions(
            "a",
            "leave-after-delivery",
            world.actor("a").unwrap().actions.revision,
            &[departure],
        )
        .unwrap();
    let mut world = common::restore(&world, town());
    world.step(0.1);
    let delivered = view(&world);
    assert_eq!(delivered.people[0].contribution, 1);
    assert_eq!(delivered.fuel, initial.fuel + 12.0);
    assert_eq!(
        delivered.stations[0].available,
        initial.stations[0].available - 12.0
    );
    assert!(world.game_mode_pending_group("a").is_none());

    let mut restored = common::restore(&world, town());
    restored.step(5.0);
    assert_eq!(view(&restored).fuel, delivered.fuel);
    assert_eq!(view(&restored).people[0].contribution, 1);
}

#[test]
fn interrupted_or_unreachable_work_never_awards_and_refunds_reservations() {
    let mut world = open(6);
    let initial = view(&world);
    work(&mut world, "a", "work", Some("materials"));
    world.step(1.0);
    world.interrupt_actions("a", "测试临时撤回劳动");
    world.step(0.1);
    let after = view(&world);
    assert_eq!(after.materials, initial.materials);
    assert_eq!(after.stations[2].available, initial.stations[2].available);
    assert_eq!(after.people[0].contribution, 0);
    assert!(after.people[0].work.is_none());

    let mut topo = common::tiny_topology();
    topo.locales.get_mut("loc_a").unwrap().name = "热源广场诊所".into();
    topo.locales.get_mut("loc_b").unwrap().name = "林场粮仓".into();
    topo.locales.get_mut("loc_c").unwrap().name = "孤立工坊".into();
    let mut isolated = common::world_with(
        topo,
        420.0,
        &[("a", "阿树", "loc_a"), ("b", "白雪", "loc_a")],
    );
    isolated
        .set_game_mode(Some(&GameModeChoice::Frostlight {
            seed: None,
            duration_hours: None,
        }))
        .unwrap();
    let before = json!(isolated.snapshot());
    assert!(isolated
        .game_mode_act("a", &action("work", Some("materials")))
        .is_err());
    assert_eq!(
        json!(isolated.snapshot()),
        before,
        "route validation must precede reservations"
    );

    let mut freezing = open(6);
    control(&mut freezing, "heat", Some("0"));
    freezing.step(205.0);
    let before = view(&freezing);
    work(&mut freezing, "a", "work", Some("fuel"));
    let group = freezing.game_mode_pending_group("a").unwrap();
    freezing.step(30.0);
    assert_eq!(view(&freezing).ending.unwrap().kind, "frozen");
    assert_eq!(
        freezing.action_group("a", &group).unwrap().status,
        protocol::GroupStatus::Interrupted,
        "an early ending must stop work before its return trip can deliver"
    );
    let mut freezing = common::restore(&freezing, town());
    freezing.step(100.0);
    let after = view(&freezing);
    assert_eq!(after.fuel, before.fuel);
    assert_eq!(after.stations[0].available, before.stations[0].available);
    assert_eq!(after.people[0].contribution, 0);
    assert!(after.people[0].work.is_none());
}

#[test]
fn management_is_separate_bounded_and_irreversible_policies_cannot_be_farmed() {
    let mut world = open(6);
    let before = json!(world.snapshot());
    assert!(world
        .game_mode_act("a", &action("heat", Some("3")))
        .is_err());
    assert!(world
        .game_mode_control(&action("heat", Some("999")))
        .is_err());
    assert!(world
        .game_mode_control(&action("work", Some("fuel")))
        .is_err());
    assert_eq!(json!(world.snapshot()), before);
    control(&mut world, "relief", None);
    control(&mut world, "law", Some("soup"));
    let once = json!(world.snapshot());
    assert!(world.game_mode_control(&action("relief", None)).is_err());
    assert!(world
        .game_mode_control(&action("law", Some("soup")))
        .is_err());
    assert_eq!(json!(world.snapshot()), once);
    control(&mut world, "heat", Some("3"));
    world.step(126.0);
    assert_eq!(
        view(&world).heat,
        0,
        "overdrive must trip at its pressure limit"
    );
    assert!((0.0..=100.0).contains(&view(&world).stress));
    assert!(view(&world).news.iter().any(|n| n.text.contains("跳闸")));
}

#[test]
fn a_coordinated_session_reaches_a_warm_dawn_with_real_labor() {
    let mut world = open(6);
    control(&mut world, "relief", None);
    control(&mut world, "heat", Some("2"));
    work(&mut world, "a", "work", Some("materials"));
    work(&mut world, "b", "build", None);
    finish_work(&mut world);
    let mut marginal = common::restore(&world, town());
    marginal.step(view(&marginal).ends_at - marginal.minutes() + 1.0);
    assert_eq!(view(&marginal).ending.as_ref().unwrap().kind, "survived");
    work(&mut world, "b", "build", None);
    finish_work(&mut world);
    assert_eq!(view(&world).insulation, 2);
    assert_eq!(
        view(&world)
            .people
            .iter()
            .map(|p| p.contribution)
            .sum::<u32>(),
        3
    );
    let remaining = view(&world).ends_at - world.minutes();
    world.step(remaining + 1.0);
    let end = view(&world);
    assert_eq!(end.phase, FrostlightPhase::Over);
    assert_eq!(end.ending.as_ref().unwrap().kind, "warm_dawn");
    assert_eq!(end.ending.as_ref().unwrap().survivors, 2);
    assert!(end.people.iter().all(|p| p.work.is_none()));
    let restored = common::restore(&world, town());
    assert_eq!(view(&restored).ending, end.ending);
}

#[test]
fn cold_and_starvation_have_distinct_terminal_failures() {
    let mut cold = open(6);
    control(&mut cold, "heat", Some("0"));
    cold.step(400.0);
    assert_eq!(view(&cold).ending.as_ref().unwrap().kind, "frozen");
    assert_eq!(
        view(&cold).temperature,
        -28.0,
        "early loss keeps the actual temperature"
    );
    let ended = json!(cold.snapshot());
    assert!(cold.game_mode_control(&action("relief", None)).is_err());
    assert!(cold
        .game_mode_act("a", &action("work", Some("fuel")))
        .is_err());
    assert_eq!(json!(cold.snapshot()), ended);

    let mut hunger = open(12);
    control(&mut hunger, "relief", None);
    control(&mut hunger, "heat", Some("2"));
    hunger.step(730.0);
    assert_eq!(view(&hunger).ending.as_ref().unwrap().kind, "abandoned");
}

#[test]
fn large_time_steps_preserve_stage_boundaries_resource_exhaustion_and_the_ending() {
    let mut fast = open(12);
    control(&mut fast, "relief", None);
    control(&mut fast, "heat", Some("2"));
    let mut gradual = common::restore(&fast, town());
    let until = fast.minutes() + 730.0;
    fast.step(730.0);
    while gradual.minutes() < until - 1e-8 {
        gradual.step((until - gradual.minutes()).min(0.37));
    }
    let a = view(&fast);
    let b = view(&gradual);
    assert_eq!(a.ending, b.ending);
    assert_eq!(a.phase, b.phase);
    for (left, right) in [
        (a.fuel, b.fuel),
        (a.food, b.food),
        (a.hope, b.hope),
        (a.discontent, b.discontent),
        (a.cold_minutes, b.cold_minutes),
        (a.hunger_minutes, b.hunger_minutes),
    ] {
        assert!(
            (left - right).abs() < 1e-5,
            "chunking changed an economic result: {left} != {right}"
        );
    }
    for phrase in ["寒潮抵达", "暴风雪抵达"] {
        assert_eq!(a.news.iter().filter(|n| n.text.contains(phrase)).count(), 1);
        assert_eq!(b.news.iter().filter(|n| n.text.contains(phrase)).count(), 1);
    }
}
