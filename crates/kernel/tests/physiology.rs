use crate::common;
use kernel::{Event, Topology, World};
use protocol::{Alert, BodyConditionKind as C, BodyEventKind, DeathCause, GroupStatus};
use serde_json::json;
fn world() -> World {
    common::world_with(
        Topology::from_json(
            include_str!("fixtures/physiology-s7.json"),
            &common::catalog(),
        )
        .unwrap(),
        420.0,
        &[("a", "a", "lab_room"), ("b", "b", "lab_room")],
    )
}
fn set(w: &mut World, id: &str, v: [f64; 4]) {
    w.set_body_values(id, Some(v[0]), Some(v[1]), Some(v[2]), Some(v[3]))
        .unwrap();
}
fn action(w: &mut World, id: &str, key: &str, prop: &str, verb: &str, target: Option<&str>) {
    common::run(
        w,
        id,
        key,
        json!({"intent":{"verb":verb},"prop_id":prop,"recipient":target}),
    )
    .unwrap();
}
fn close(a: f64, b: f64) {
    assert!((a - b).abs() < 1e-7, "{a} != {b}");
}
/// 世界日志里需要提示卡的那些行。
fn alerts(events: Vec<Event>) -> Vec<Alert> {
    events
        .into_iter()
        .filter_map(|Event::Log { info, .. }| info.alert)
        .collect()
}
/// 状况、危重与死亡都在日志和日记上带结构化的提示细节，前端不用解析句子。
#[test]
fn conditions_coexist_cure_is_specific_and_revival_explicit() {
    let mut w = world();
    for c in [C::Injury, C::Illness, C::Poison] {
        w.apply_condition("b", c, 1.0, "来源").unwrap();
    }
    let condition = |condition| Alert::Condition { condition };
    assert_eq!(
        alerts(w.step(10.0)),
        [
            condition(C::Injury),
            condition(C::Illness),
            condition(C::Poison)
        ]
    );
    let h = w.actor("b").unwrap().needs.health.value;
    assert!(h < 100.0, "三种状况同时损害健康：{h}");
    w.cure_condition("b", C::Poison, "解毒剂").unwrap();
    assert_eq!(w.actor("b").unwrap().needs.body.conditions.len(), 2);
    close(w.actor("b").unwrap().needs.health.value, h);
    set(&mut w, "b", [50.0, 50.0, 50.0, 0.1]);
    assert_eq!(alerts(w.take_events()), [Alert::Critical]);
    // 受伤和疾病继续损害健康直到死亡：死因里是这两种状况
    let death = Alert::Death(DeathCause {
        shortages: vec![],
        conditions: vec![C::Injury, C::Illness],
        killed: None,
    });
    assert_eq!(alerts(w.step(10.0)), [death.clone()]);
    assert!(w
        .diary("b")
        .iter()
        .flat_map(|d| &d.receipts)
        .any(|r| r.alert.as_ref() == Some(&death)));
    assert!(w
        .set_body_values("b", None, None, None, Some(30.0))
        .is_err());
    assert!(common::run(
        &mut w,
        "a",
        "invalid",
        json!({"intent":{"verb":"治疗健康"},"prop_id":"medical","recipient":"b"})
    )
    .is_err());
    action(&mut w, "a", "revive", "revive", "施用复苏石", Some("b"));
    w.step(10.0);
    let n = &w.actor("b").unwrap().needs;
    assert!(!n.body.dead);
    close(n.health.value, 40.0);
    assert!(n.body.conditions.is_empty());
    assert!(n
        .body
        .history
        .iter()
        .any(|e| e.kind == BodyEventKind::Death));
    assert!(n
        .body
        .history
        .iter()
        .any(|e| e.kind == BodyEventKind::Revive));
}

#[test]
fn exhausted_supply_and_competing_consumers_cannot_duplicate_effects() {
    let mut w = world();
    let view = w.prop_views();
    let food = view.iter().find(|p| p.id == "food").unwrap();
    let protocol::PropActionEntry::Defined(eat) = &food.actions[0] else {
        panic!("干粮的动作有定义")
    };
    let key = format!("food/{}", eat.id);
    let mut snapshot = json!(w.snapshot());
    snapshot["supplies"][&key] = json!(1);
    w.restore_snapshot(serde_json::from_value(snapshot).unwrap())
        .unwrap();
    set(&mut w, "a", [50.0, 90.0, 100.0, 100.0]);
    set(&mut w, "b", [50.0, 90.0, 100.0, 100.0]);
    action(&mut w, "a", "one", "food", "吃干粮", None);
    action(&mut w, "b", "two", "food", "吃干粮", None);
    w.step(10.0);
    assert_eq!(
        w.action_group("a", "one").unwrap().status,
        GroupStatus::Succeeded
    );
    assert_eq!(
        w.action_group("b", "two").unwrap().status,
        GroupStatus::Failed
    );
    // 两人同样经过了这段时间，差别只是吃到的那一份（夹具里每份 25 点）。
    let fullness = |id: &str| w.actor(id).unwrap().needs.fullness.value;
    close(fullness("a") - fullness("b"), 25.0);
    assert_eq!(json!(w.snapshot())["supplies"][&key], 0);
    assert!(common::run(
        &mut w,
        "b",
        "empty",
        json!({"intent":{"verb":"吃干粮"},"prop_id":"food"})
    )
    .is_err());
}

#[test]
fn switched_off_needs_freeze_hide_and_resume_after_reload() {
    let mut w = world();
    set(&mut w, "a", [0.0, 100.0, 10.0, 100.0]);
    assert!(w.body_view("a").unwrap().limitation.contains("饱腹耗尽"));
    let off = protocol::PhysiologySwitches {
        fullness: false,
        water: false,
        ..Default::default()
    };
    w.set_physiology(off);
    w.step(1440.0);
    // 关掉的饱腹与水分冻结，精力照常消耗，健康不受关掉的项影响。
    let n = &w.actor("a").unwrap().needs;
    close(n.fullness.value, 0.0);
    close(n.water.value, 10.0);
    assert!(n.energy.value < 100.0);
    close(n.health.value, 100.0);
    let names: Vec<_> = n.states().into_iter().map(|s| s.need).collect();
    assert_eq!(names, ["精力", "健康"]);
    let body = w.body_view("a").unwrap();
    assert!(body.can_decide && body.can_labor);
    assert_eq!(body.exposure, [0.0; 3]);
    assert!(body
        .causes
        .iter()
        .all(|c| !c.contains("饱腹") && !c.contains("水分")));

    let saved = serde_json::to_vec(&w.snapshot()).unwrap();
    let mut w = world();
    w.restore_snapshot(serde_json::from_slice(&saved).unwrap())
        .unwrap();
    assert_eq!(w.physiology(), off);
    assert!(w.body_view("a").unwrap().can_labor);

    w.set_physiology(Default::default());
    assert!(w.body_view("a").unwrap().limitation.contains("饱腹耗尽"));
    w.step(10.0);
    assert!(
        w.actor("a").unwrap().needs.water.value < 10.0,
        "重新打开后水分恢复消耗"
    );
}

/// 第一次「很渴」的提醒被放过去、又睡回去的村民，水分跌到崩溃线时会再被叫醒一次，
/// 不会一觉睡到失能：家里有水也得自己起来喝。
#[test]
fn ignored_thirst_warning_wakes_the_sleeper_again_at_the_collapse_line() {
    let mut w = world();
    w.enable_agent("a").unwrap();
    // 已经低于第一次提醒线（那次放过去了），精力不满睡得着
    set(&mut w, "a", [80.0, 40.0, 16.0, 100.0]);
    action(&mut w, "a", "nap", "bed", "睡觉", None);
    w.step(30.0);
    assert_eq!(
        w.action_group("a", "nap").unwrap().status,
        GroupStatus::Interrupted
    );
    assert!(w.actor("a").unwrap().needs.water.value > 0.0);
}
