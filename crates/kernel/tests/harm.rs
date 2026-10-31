//! 伤人：凶器道具对同处所的人动手，死者记下凶手和伤口；别人和尸体待在一起时发现，
//! 看得出是不是被人杀死的。都走 run_actions 与 step 的完整路径。
use crate::common;
use kernel::World;
use protocol::{Alert, FactKind, GroupStatus};
use serde_json::{json, Value};

const KNIFE: &str = r#"{"id":"test:knife","version":1,"name":"菜刀","portable":true,"actions":[
  {"id":"stab","label":"持刀袭击","duration_minutes":3,"recipient":true,
   "on_complete":[{"kind":"harm","amount":100,"wound":"胸口一处刀伤"}]}]}"#;

/// 阿明、林溪、老周在甲地，阿花在乙地；甲地放着一把菜刀。
fn world() -> World {
    common::world_with(
        common::two_places(json!([])),
        420.0,
        &[
            ("aming", "阿明", "loc_a"),
            ("linxi", "林溪", "loc_a"),
            ("laozhou", "老周", "loc_a"),
            ("ahua", "阿花", "loc_b"),
        ],
    )
}

fn put_knife(w: &mut World) {
    let def: kernel::props::Definition = serde_json::from_str(KNIFE).unwrap();
    w.place_prop(
        serde_json::from_value(json!({
            "instance":{"id":"knife","definition":def.reference(),"locale":"loc_a"},
            "definition":def
        }))
        .unwrap(),
    )
    .unwrap();
}

fn stab(w: &mut World, key: &str, recipient: Option<&str>) -> Result<(), String> {
    common::run(
        w,
        "aming",
        key,
        json!({"prop_id":"knife","intent":{"verb":"持刀袭击"},"recipient":recipient}),
    )
    .map(|_| ())
    .map_err(|e| e.to_string())
}

fn walk(w: &mut World, who: &str, key: &str, to: &str) {
    common::run(w, who, key, json!({"intent":{"verb":"前往","locale":to}})).unwrap();
    common::finish(w, who, key);
}

/// 本人记下的发现尸体。
fn found(w: &World, who: &str) -> Vec<String> {
    w.actor(who)
        .unwrap()
        .journal
        .events
        .iter()
        .filter(|e| e.kind == FactKind::Observation && e.text.starts_with("发现"))
        .map(|e| e.text.clone())
        .collect()
}

#[test]
fn stabbing_kills_and_the_dead_keep_killer_and_wound_after_reload() {
    let mut w = world();
    put_knife(&mut w);
    assert!(
        stab(&mut w, "self", None).is_err(),
        "伤人的动作不能对自己用"
    );
    stab(&mut w, "stab", Some("linxi")).unwrap();
    let r = common::finish(&mut w, "aming", "stab");
    assert_eq!(
        w.action_group("aming", "stab").unwrap().status,
        GroupStatus::Succeeded
    );
    assert!(r.changes.iter().any(|c| c == "林溪遇害身亡"), "{r:?}");
    let victim = w.actor("linxi").unwrap();
    assert!(victim.needs.body.dead);
    let killed = victim.needs.body.killed.clone().unwrap();
    assert_eq!(killed.by.id, "aming");
    assert_eq!(killed.wound, "胸口一处刀伤");
    // 死亡记录和提示卡带上遇害：前端据此写「林溪遇害了」
    let (text, alert) = w
        .diary("linxi")
        .iter()
        .flat_map(|d| d.receipts.clone())
        .find_map(|r| match r.alert {
            Some(Alert::Death(cause)) => Some((r.text, cause)),
            _ => None,
        })
        .unwrap();
    assert!(text.starts_with("遇害身亡，胸口一处刀伤"), "{text}");
    assert_eq!(alert.killed.as_ref(), Some(&killed));
    assert!(
        stab(&mut w, "again", Some("linxi")).is_err(),
        "不能对死者再动手"
    );
    let w = common::restore(&w, world());
    let body = &w.actor("linxi").unwrap().needs.body;
    assert!(body.dead);
    assert_eq!(body.killed.as_ref(), Some(&killed));
}

#[test]
fn finding_a_body_tells_a_killing_from_other_deaths_once() {
    let mut w = world();
    put_knife(&mut w);
    stab(&mut w, "stab", Some("linxi")).unwrap();
    common::finish(&mut w, "aming", "stab");
    // 在场的老周当场发现；随后老周也死了（不是被杀）
    assert_eq!(
        found(&w, "laozhou"),
        ["发现林溪倒在甲地，已经没有呼吸，胸口一处刀伤，像是被人杀死的"]
    );
    w.set_body_values("laozhou", None, None, None, Some(0.0))
        .unwrap();
    w.step(1.0);
    // 凶手不会“发现”自己杀的人；老周的尸体他照样看见
    assert_eq!(found(&w, "aming"), ["发现老周倒在甲地，已经没有呼吸"]);
    let before = w.snapshot();

    // 旧存档没有已见名单：读档时已有的尸体算作人人都见过，阿花进门不补发
    let mut old: Value = serde_json::to_value(&before).unwrap();
    for a in old["actors"].as_object_mut().unwrap().values_mut() {
        a.as_object_mut().unwrap().remove("bodies_seen");
    }
    let mut legacy = world();
    legacy
        .restore_snapshot(serde_json::from_value(old).unwrap())
        .unwrap();
    walk(&mut legacy, "ahua", "go", "loc_a");
    assert!(found(&legacy, "ahua").is_empty());

    walk(&mut w, "ahua", "go", "loc_a");
    let mut seen = found(&w, "ahua");
    seen.sort();
    assert_eq!(
        seen,
        [
            "发现林溪倒在甲地，已经没有呼吸，胸口一处刀伤，像是被人杀死的",
            "发现老周倒在甲地，已经没有呼吸",
        ]
    );
    // 每具尸体只记一次：接着待着、存档再读都不重复
    w.step(30.0);
    let mut w = common::restore(&w, world());
    w.step(30.0);
    assert_eq!(found(&w, "ahua").len(), 2);
}
