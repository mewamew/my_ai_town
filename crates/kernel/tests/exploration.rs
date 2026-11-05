//! 陌生环境与藏着的东西：初来乍到的人只认得脚下，顺着眼前的路走过去才认识新地方，不认得的去不了；
//! 藏着的东西到了也看不见、用不了，搜寻找到后才有，在场醒着的人一起看见；藏起来的东西只有当时在场
//! 的人知道，后来的人要搜寻；熟悉的世界不限地点。都走 run_actions 与 step 的完整路径。
use crate::common;
use kernel::World;
use protocol::{FactKind, GroupStatus};
use serde_json::{json, Value};

/// 礁石缝里卡着的罐头：放下就藏着。
const STASH: &str = r#"{"id":"test:stash","version":1,"name":"礁石缝里的罐头","hidden":true,"portable":true,"actions":[
  {"id":"eat","label":"吃罐头","duration_minutes":10,"consumes_item":true,"completion":"activity",
   "on_complete":[{"kind":"restore","need":"fullness","amount":40.0}]}]}"#;
const KNIFE: &str = r#"{"id":"test:knife","version":1,"name":"菜刀","portable":true,"actions":[]}"#;

fn put(w: &mut World, id: &str, definition: &str, locale: &str) {
    let def: kernel::props::Definition = serde_json::from_str(definition).unwrap();
    w.place_prop(
        serde_json::from_value(json!({
            "instance":{"id":id,"definition":def.reference(),"locale":locale},
            "definition":def
        }))
        .unwrap(),
    )
    .unwrap();
}

/// 甲地—乙地相通，孤岛不通任何地方。林晚、周屿在甲地，老渔夫在乙地。
fn world() -> World {
    let mut w = common::world_with(
        common::tiny_topology(),
        600.0,
        &[
            ("lin", "林晚", "loc_a"),
            ("zhou", "周屿", "loc_a"),
            ("old", "老渔夫", "loc_b"),
        ],
    );
    put(&mut w, "stash", STASH, "loc_a");
    put(&mut w, "knife", KNIFE, "loc_a");
    w.step(0.1);
    w
}

fn act(w: &mut World, who: &str, key: &str, draft: Value) -> Result<String, String> {
    common::run(w, who, key, draft).map_err(|e| e.to_string())?;
    let r = common::finish(w, who, key);
    match w.action_group(who, key).unwrap().status {
        GroupStatus::Succeeded => Ok(r.changes.join("；")),
        _ => Err(r.reason.unwrap_or_default()),
    }
}

fn ids(list: Option<Vec<kernel::exploration::KnownPlace>>) -> Vec<String> {
    list.unwrap().into_iter().map(|p| p.id).collect()
}

#[test]
fn strangers_only_know_where_they_have_been_and_learn_places_by_walking_there() {
    let mut w = world();
    // 熟悉的世界：没有已知地图这一说，哪儿都能去（去不去得成看路）
    assert!(w.known_places("lin").is_none() && w.exits("lin").is_none());
    w.set_strangers(true);
    assert_eq!(ids(w.known_places("lin")), ["loc_a"]);
    let exits = w.exits("lin").unwrap();
    assert_eq!(exits.len(), 1);
    assert_eq!(
        (exits[0].to.as_str(), exits[0].name.as_deref()),
        ("loc_b", None)
    );
    // 不通、没去过的地方去不了；眼前的路通到的地方能去
    let island = act(
        &mut w,
        "lin",
        "c",
        json!({"intent":{"verb":"前往","locale":"loc_c"}}),
    );
    assert!(island.unwrap_err().contains("还不知道那个地方怎么去"));
    act(
        &mut w,
        "lin",
        "b",
        json!({"intent":{"verb":"前往","locale":"loc_b"}}),
    )
    .unwrap();
    w.step(0.5);
    assert_eq!(ids(w.known_places("lin")), ["loc_b", "loc_a"]);
    let journal = &w.actor("lin").unwrap().journal.events;
    assert!(journal
        .iter()
        .any(|e| e.kind == FactKind::Observation && e.text == "第一次来到乙地"));
    let back = w.exits("lin").unwrap();
    assert_eq!(back[0].name.as_deref(), Some("甲地"), "到过的地方认得名字");
    // 记得的地方是上次离开时的样子，标着那个时刻
    let remembered = w
        .known_places("lin")
        .unwrap()
        .into_iter()
        .find(|p| p.id == "loc_a")
        .unwrap();
    assert!(remembered.last_seen.is_some());
}

#[test]
fn hidden_things_need_searching_and_what_is_hidden_is_known_only_to_those_who_saw() {
    let mut w = world();
    // 藏着的罐头：看不见、拾不起、用不了
    assert!(!w.sees_prop("lin", "stash"));
    let pick = act(
        &mut w,
        "lin",
        "p0",
        json!({"intent":{"verb":"拾取"},"inventory":{"operation":"pick_up","items":["stash"]}}),
    );
    assert!(pick.unwrap_err().contains("眼前没有这件东西"));
    let eat = act(
        &mut w,
        "lin",
        "e0",
        json!({"prop_id":"stash","intent":{"verb":"吃罐头"}}),
    );
    assert!(eat.unwrap_err().contains("这里没有能吃罐头的东西"));
    // 搜寻：有一定可能找到，找到了自己和在场醒着的人都看得见
    let mut found = String::new();
    for i in 0..8 {
        found = act(
            &mut w,
            "lin",
            &format!("s{i}"),
            json!({"intent":{"verb":"搜寻"}}),
        )
        .unwrap();
        if found.contains("找到了") {
            break;
        }
    }
    assert!(found.contains("找到了礁石缝里的罐头"), "{found}");
    assert!(w.sees_prop("lin", "stash") && w.sees_prop("zhou", "stash"));
    assert!(!w.sees_prop("old", "stash"), "不在场的人不知道");

    // 藏：林晚把菜刀藏在甲地，周屿在场看见了；后来的老渔夫看不见
    act(
        &mut w,
        "lin",
        "k",
        json!({"intent":{"verb":"拾取"},"inventory":{"operation":"pick_up","items":["knife"]}}),
    )
    .unwrap();
    let hid = act(
        &mut w,
        "lin",
        "h",
        json!({"prop_id":"knife","intent":{"verb":"藏"}}),
    )
    .unwrap();
    assert!(hid.contains("把菜刀藏在了甲地"), "{hid}");
    assert!(w.sees_prop("lin", "knife") && w.sees_prop("zhou", "knife"));
    act(
        &mut w,
        "old",
        "a",
        json!({"intent":{"verb":"前往","locale":"loc_a"}}),
    )
    .unwrap();
    assert!(!w.sees_prop("old", "knife"));
    // 拾起来就不再藏着
    act(
        &mut w,
        "zhou",
        "k2",
        json!({"intent":{"verb":"拾取"},"inventory":{"operation":"pick_up","items":["knife"]}}),
    )
    .unwrap();
    assert!(w.sees_prop("old", "knife"));
}
