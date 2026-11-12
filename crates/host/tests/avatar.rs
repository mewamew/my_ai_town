use crate::support::*;
use serde_json::{json, Value};
use std::{net::TcpStream, time::Duration};
use tungstenite::WebSocket;

pub(crate) fn command(
    ws: &mut WebSocket<TcpStream>,
    state: &Value,
    sequence: u64,
    command: Value,
) -> Value {
    let id = format!("avatar-{sequence}");
    send(
        ws,
        json!({"type":"avatar","world_id":state["world_id"],"request_id":id,"epoch":state["epoch"].as_str().unwrap_or(""),"sequence":sequence,"command":command}),
    );
    until(ws, |m| {
        m["type"] == "avatar_result" && m["request_id"] == id
    })
}
pub(crate) fn state(ws: &mut WebSocket<TcpStream>) -> Value {
    let w = reply(ws, json!({"type":"get_world_settings"}), "world_settings")["state"].clone();
    command(ws, &w, 0, json!({"kind":"view"}))["state"].clone()
}

#[test]
fn authoritative_input_single_controller_save_failure_and_restart() {
    let mut town = Town::new();
    town.args = map_args(MAP_2D);
    let mut ws = town.start();
    let s = state(&mut ws);
    assert_eq!(s["supported"], true);
    assert!(
        s["client_positions"].is_null(),
        "二维地图不应接受客户端位置"
    );
    let entered = command(
        &mut ws,
        &s,
        1,
        json!({"kind":"enter","name":"aya","appearance":{"marker":"我","color":"#387963"}}),
    );
    assert_eq!(entered["ok"], true, "{entered}");
    let s = entered["state"].clone();
    let history = reply(
        &mut ws,
        json!({"type":"get_chat_history","resident":"player_avatar","request_id":"avatar-history","offset":0}),
        "chat_history",
    );
    assert_eq!(history["resident"], "player_avatar");
    assert_eq!(history["total"], 0);
    let mut other = connect_again(&ws);
    let observed = state(&mut other);
    assert!(observed["resume_token"].is_null());
    assert!(
        observed["actor"].is_null(),
        "other connection received private control view: {observed}"
    );
    assert!(observed["inventory"].is_null());
    assert!(observed["interactions"].is_null());
    assert_eq!(
        command(
            &mut other,
            &observed,
            1,
            json!({"kind":"resume","token":s["resume_token"]})
        )["ok"],
        false,
        "活动租约不能被第二个连接抢走"
    );
    assert_eq!(
        command(
            &mut other,
            &observed,
            2,
            json!({"kind":"enter","name":"另一页面","appearance":{"marker":"我","color":"#387963"}})
        )["ok"],
        false
    );
    // 化身在场不再限制倍率：60 原样生效；随后换回 1 便于观察行走。
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":60}),
    );
    until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 60.0);
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":1}),
    );
    let roster = until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 1.0);
    assert_eq!(members(&roster).len(), 1);
    assert_eq!(members(&roster)[0]["kind"], "avatar");
    let old = s["actor"]["locus"].clone();
    let input = json!({"type":"avatar_input","world_id":s["world_id"],"epoch":s["epoch"],"sequence":1,"navigation_revision":s["navigation_revision"],"direction":[0,-1]});
    send(&mut ws, input.clone());
    until(&mut ws, |m| {
        m["type"] == "avatar_state" && m["state"]["actor"]["locus"] != old
    });
    // 没有后续输入时自动停步；重送旧序号不能再次启动。
    std::thread::sleep(Duration::from_millis(650));
    let stopped = state(&mut ws)["actor"]["locus"].clone();
    send(&mut ws, input);
    std::thread::sleep(Duration::from_millis(300));
    assert_eq!(state(&mut ws)["actor"]["locus"], stopped);
    let profile = json!({"kind":"profile","name":"aya 新名字","appearance":{"marker":"我","color":"#a15338"}});
    assert_eq!(command(&mut ws, &s, 3, profile.clone())["ok"], true);
    assert_eq!(command(&mut ws, &s, 3, profile)["ok"], true);
    assert_eq!(command(&mut ws, &s, 3, json!({"kind":"stop"}))["ok"], false);
    // 原子保存的目标被目录挡住时，化身修改回滚且全镇暂停；只操作隔离目录。
    let original = town.save().with_extension("saved");
    std::fs::rename(town.save(), &original).unwrap();
    std::fs::create_dir(town.save()).unwrap();
    let failed = command(
        &mut ws,
        &s,
        4,
        json!({"kind":"profile","name":"不应留下","appearance":{"marker":"我","color":"#387963"}}),
    );
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["state"]["actor"]["name"], "aya 新名字");
    assert_eq!(failed["state"]["speed"], 0.0);
    std::fs::remove_dir(town.save()).unwrap();
    std::fs::rename(original, town.save()).unwrap();
    std::thread::sleep(Duration::from_millis(300));
    let token = s["resume_token"].clone();
    drop(ws);
    std::thread::sleep(Duration::from_millis(200));
    let resumed = command(&mut other, &s, 5, json!({"kind":"resume","token":token}));
    assert_eq!(resumed["ok"], true, "{resumed}");
    assert_ne!(resumed["state"]["epoch"], s["epoch"]);
    let s = resumed["state"].clone();
    assert_eq!(
        command(&mut other, &s, 1, json!({"kind":"leave"}))["ok"],
        true
    );
    drop(other);
    town.shutdown();
    let mut ws = town.start();
    let s = state(&mut ws);
    assert_eq!(s["actor"]["present"], false);
    assert_eq!(s["actor"]["name"], "aya 新名字");
    assert_eq!(s["actor"]["locus"]["at"]["kind"], "offstage");
    let saved = town.saved(|v| v["schema_version"] == 6);
    assert!(saved["population"]["residents"]
        .as_object()
        .unwrap()
        .is_empty());
    let entered = command(
        &mut ws,
        &s,
        2,
        json!({"kind":"enter","name":"aya 新名字","appearance":{"marker":"我","color":"#a15338"}}),
    );
    assert_eq!(entered["ok"], true, "{entered}");
    assert_eq!(entered["state"]["actor"]["locus"], stopped);
}

/// v3 存档（人物没有 kind 字段）读入后居民的需求与位置不变，人口原样保留，原文件留有备份。
#[test]
fn legacy_save_migration_preserves_residents() {
    let mut town = Town::new();
    let mut ws = town.start();
    let resident = join_id(&mut ws, "tpl_a");
    town.shutdown();
    drop(ws);
    let mut old: Value = serde_json::from_slice(&std::fs::read(town.save()).unwrap()).unwrap();
    old["schema_version"] = json!(3);
    old["world"]["schema_version"] = json!(3);
    for a in old["world"]["actors"].as_object_mut().unwrap().values_mut() {
        a.as_object_mut().unwrap().remove("kind");
    }
    std::fs::write(town.save(), serde_json::to_vec(&old).unwrap()).unwrap();
    let before = old["world"]["actors"][&resident].clone();
    let mut ws = town.start();
    until(&mut ws, |m| m["type"] == "roster");
    town.shutdown();
    let current: Value = serde_json::from_slice(&std::fs::read(town.save()).unwrap()).unwrap();
    assert_eq!(
        current["world"]["actors"][&resident]["needs"],
        before["needs"]
    );
    assert_eq!(
        current["world"]["actors"][&resident]["locus"],
        before["locus"]
    );
    assert_eq!(current["population"], old["population"]);
    assert!(
        std::path::PathBuf::from(format!("{}.before-avatar-v1", town.save().display())).exists()
    );
}

/// 化身神力走完整路径：开关在设定里打开、随存档保存；化身对倒在入口的居民施展复活，
/// 回执带着给玩家看的结果；开关关着时同一条命令被拒。
#[test]
fn miracle_switch_persists_and_the_avatar_revives_a_resident() {
    let mut town = Town::new();
    town.args = map_args(MAP_2D);
    let mut ws = town.start();
    let resident = join_id(&mut ws, "tpl_a");
    town.shutdown();
    drop(ws);
    // 刚从入口进镇的居民（世界还停着，他没走开）倒在入口
    let mut save = read_json(&town.save());
    let needs = &mut save["world"]["actors"][&resident]["needs"];
    needs["health"]["value"] = json!(0.0);
    needs["body"]["dead"] = json!(true);
    std::fs::write(town.save(), serde_json::to_vec(&save).unwrap()).unwrap();
    let mut ws = town.start();
    let settings = |ws: &mut WebSocket<TcpStream>| {
        reply(ws, json!({"type":"get_world_settings"}), "world_settings")["state"].clone()
    };
    assert_eq!(settings(&mut ws)["miracles"], false);
    let s = state(&mut ws);
    let entered = command(
        &mut ws,
        &s,
        1,
        json!({"kind":"enter","name":"aya","appearance":{"marker":"我","color":"#387963"}}),
    );
    assert_eq!(entered["ok"], true, "{entered}");
    let s = entered["state"].clone();
    assert!(
        s["nearby"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["id"] == resident.as_str() && p["dead"] == true),
        "倒在跟前的人列在够得着的人里，标着已经死了：{s}"
    );
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"go","speed":1}),
    );
    until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 1.0);
    let revive = |state: &Value| json!({"kind":"miracle","revision":state["actor"]["revision"],"recipient":resident,"miracle":"revive"});
    let off = command(&mut ws, &s, 2, revive(&s));
    assert_eq!(off["ok"], false, "开关关着时不能施展：{off}");
    assert_eq!(off["state"]["miracles"], false);
    let saved = reply(
        &mut ws,
        json!({"type":"set_miracles","request_id":"m1","world_id":s["world_id"],"enabled":true}),
        "world_settings_saved",
    );
    assert_eq!(saved["ok"], true, "{saved}");
    let done = command(&mut ws, &s, 3, revive(&off["state"]));
    assert_eq!(done["ok"], true, "{done}");
    assert!(
        done["message"].as_str().unwrap().contains("活了过来"),
        "{done}"
    );
    assert_eq!(done["state"]["miracles"], true);
    let roster = until(&mut ws, |m| {
        m["type"] == "roster"
            && members(m)
                .iter()
                .any(|r| r["id"] == resident.as_str() && r["body"]["life"] == "alive")
    });
    assert!(!members(&roster).is_empty());
    town.shutdown();
    drop(ws);
    let mut ws = town.start();
    assert_eq!(settings(&mut ws)["miracles"], true, "开关随存档保存");
}
