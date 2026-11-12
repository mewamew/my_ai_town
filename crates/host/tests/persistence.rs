//! 临时目录中的真实进程重启测试；不读取或写入用户存档，不调用外部模型。
use crate::{
    avatar::{command, state},
    support::*,
};
use host::{persistence::SaveStore, world_settings::WorldSettings};
use serde_json::{json, Value};
use std::{fs, net::TcpStream, time::Instant};
use tungstenite::WebSocket;

fn query(ws: &mut WebSocket<TcpStream>, command: &str, response: &str) -> Value {
    reply(ws, json!({"type":command}), response)
}

#[test]
fn killed_host_restores_memory_time_activity_then_reset_replaces_save() {
    let mut town = Town::new();
    town.args = map_args(MAP_2D);
    town.mock_delay = Some("60".into());
    town.autosave = true;
    let mut ws = town.start();
    until(&mut ws, |m| m["type"] == "roster");
    let id = join_id(&mut ws, "tpl_a");
    // 附身让村民停留两小时再交还：这段活动不经过模型，重启前后应完全一致。
    let observing = state(&mut ws);
    let possessed = command(
        &mut ws,
        &observing,
        1,
        json!({"kind":"possess","resident":id}),
    );
    assert_eq!(possessed["ok"], true, "{possessed}");
    let s = possessed["state"].clone();
    // 玩家动作要在世界运行时下达；用很慢的速度开动，交还前时间几乎不动。
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":0.125}),
    );
    until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 0.125);
    let stay = command(
        &mut ws,
        &s,
        2,
        json!({"kind":"action","revision":s["actor"]["revision"],"action":{"intent":{"verb":"停留","duration_minutes":120}}}),
    );
    assert_eq!(stay["ok"], true, "{stay}");
    assert_eq!(
        command(&mut ws, &stay["state"], 3, json!({"kind":"leave"}))["ok"],
        true
    );
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":10}),
    );
    // 没有新命令或模型回复时，周期保存也必须持续推进。
    town.saved(|saved| saved["world"]["minutes"].as_f64().unwrap() > 425.0);
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":0}),
    );
    let roster = until(&mut ws, |m| {
        m["type"] == "roster" && m["speed"] == 0.0 && m["sim_minutes"].as_f64().unwrap() > 425.0
    });
    let diary = query(&mut ws, "get_diary", "diary");
    town.kill();
    drop(ws);
    // 写了一半的临时文件不影响完整检查点。
    fs::write(town.save().with_file_name("world.json.tmp"), b"{broken").unwrap();
    town.mock_delay = Some("0.01".into());
    let mut ws = town.start();
    let restored = until(&mut ws, |m| m["type"] == "roster");
    assert_eq!(restored, roster);
    assert_eq!(query(&mut ws, "get_diary", "diary"), diary);
    // 旧进程的在途请求不会让新进程停住：恢复后世界照常推进。
    let restored_minutes = restored["sim_minutes"].as_f64().unwrap();
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":10}),
    );
    until(&mut ws, |m| {
        m["type"] == "roster" && m["sim_minutes"].as_f64().unwrap() > restored_minutes + 1.0
    });
    send(
        &mut ws,
        json!({"type":"reset_world","request_id":"test-reset-world"}),
    );
    until(&mut ws, |m| m["type"] == "world_reset");
    town.kill();
    drop(ws);
    town.mock_delay = Some("60".into());
    let mut ws = town.start();
    let reset = until(&mut ws, |m| m["type"] == "roster");
    assert_eq!(reset["sim_minutes"], 420.0);
    // 没有特殊村民：重置后是空村，重启后仍是空村；读空村的日志回通用错误。
    assert!(members(&reset).is_empty());
    let missing = query(&mut ws, "get_diary", "error");
    assert!(missing["message"].as_str().is_some_and(|m| !m.is_empty()));
    #[cfg(unix)]
    town.shutdown();
}

/// 道具库删除只删图纸：存了两版的刀摆一把到广场，删掉以后两份文件和库里的定义都没了，
/// 广场上那把还在，目录另带着它那一版的定义（页面的说明、按用途筛靠它）；强杀重开，照样读回、还能用。
#[test]
fn deleting_a_library_prop_keeps_the_placed_copy_through_a_restart() {
    let mut town = Town::new();
    let mut ws = town.start();
    let world_id = query(&mut ws, "get_props", "props")["catalog"]["world_id"].clone();
    let knife = |version: u32, name: &str| {
        json!({"id":"player:knife","version":version,"name":name,"description":"一把磨得很快的刀。",
            "actions":[{"id":"cut","label":"切东西","duration_minutes":10,"during":[],"completion":"activity","conditions":[]}]})
    };
    for (request_id, definition) in [("save-1", knife(1, "刀")), ("save-2", knife(2, "猎刀"))] {
        let saved = reply(
            &mut ws,
            json!({"type":"save_prop","request_id":request_id,"definition":definition}),
            "prop_result",
        );
        assert_eq!(saved["ok"], true, "{saved}");
    }
    let placed = reply(
        &mut ws,
        json!({"type":"place_prop","request_id":"place","world_id":world_id,
            "instance":{"id":"user:knife","definition":"player:knife@1","locale":"square"}}),
        "prop_result",
    );
    assert_eq!(placed["ok"], true, "{placed}");
    let library = town.dir.join("state/prop-library");
    assert_eq!(fs::read_dir(&library).unwrap().count(), 2);

    let builtin = reply(
        &mut ws,
        json!({"type":"delete_prop","request_id":"core","id":"core:bed"}),
        "prop_result",
    );
    assert_eq!(builtin["ok"], false, "{builtin}");
    send(
        &mut ws,
        json!({"type":"delete_prop","request_id":"delete","id":"player:knife"}),
    );
    let deleted = until(&mut ws, |m| {
        m["type"] == "prop_result" && m["request_id"] == "delete"
    });
    assert_eq!(deleted["ok"], true, "{deleted}");
    assert_eq!(deleted["message"], "已删除「猎刀」");
    // 目录里的刀：道具库里还有没有、镇上那把自带的定义、广场上那把
    let knife_in = |catalog: &Value| {
        let of = |field: &str| catalog[field].as_array().cloned().unwrap_or_default();
        let knife = |d: &Value| d["id"] == "player:knife";
        let defined = of("definitions").iter().any(knife);
        let town_def = of("town_definitions").into_iter().find(knife);
        let placed = of("instances")
            .into_iter()
            .find(|p| p["id"] == "user:knife");
        (defined, town_def, placed)
    };
    let (defined, town_def, placed) =
        knife_in(&until(&mut ws, |m| m["type"] == "props")["catalog"]);
    assert!(!defined);
    assert_eq!(town_def.unwrap()["description"], "一把磨得很快的刀。");
    assert_eq!(placed.unwrap()["locale"], "square");
    assert_eq!(fs::read_dir(&library).unwrap().count(), 0);

    town.kill();
    drop(ws);
    let mut ws = town.start();
    let (defined, town_def, placed) = knife_in(&query(&mut ws, "get_props", "props")["catalog"]);
    assert!(!defined);
    assert_eq!(town_def.unwrap()["version"], 1);
    let placed = placed.expect("广场上的刀重开后还在");
    assert_eq!(placed["definition"], "player:knife@1");
    assert_eq!(placed["actions"][0]["label"], "切东西");
}

/// 管理进程握着 host 的 stdin 且从不写入；它消失后 host 读到 EOF，保存完整存档后自行退出。
#[test]
fn host_saves_and_exits_on_its_own_when_stdin_closes() {
    let mut town = Town::new();
    town.args.push("--stop-on-stdin-close".into());
    let mut ws = town.start();
    let id = join_id(&mut ws, "tpl_a");
    let started = Instant::now();
    town.close_stdin();
    assert!(town.wait_exit().success());
    assert!(started.elapsed().as_secs() < 8);
    let saved: Value = serde_json::from_slice(&fs::read(town.save()).unwrap()).unwrap();
    assert!(saved["population"]["residents"][&id].is_object());
    assert!(saved["world"]["actors"][&id].is_object());
    assert!(saved["resident_agent"]["runtime"]["sessions"][&id].is_object());
    assert!(!town.save().with_file_name("world.json.tmp").exists());
}

fn tiny_world() -> kernel::World {
    let topo = kernel::Topology::from_json(
        &read_json(&fixture("two_places.json")).to_string(),
        &kernel::props::Catalog::default(),
    )
    .unwrap();
    let mut w = kernel::World::new(topo, 420.0, need_rules());
    w.spawn("r1", "测试员", "loc_a").unwrap();
    w
}

#[test]
fn bad_or_incompatible_save_is_preserved_and_exclusive_lock_is_released() {
    let _no_spawns = hold_spawns();
    let town = Town::empty();
    let path = town.dir.join("world.tmp"); // 扩展名不能与临时文件或锁文件冲突
    let mut store = SaveStore::open(&path, "fixture-v1".into()).unwrap();
    let mut w = tiny_world();
    assert!(store.restore_bundle(&mut w).unwrap().is_none());
    w.note_thought("r1", "这件事要记得。", "测试");
    let settings = WorldSettings::default();
    store
        .checkpoint_bundle(&w, 0.0, &settings, None, None, true)
        .unwrap();
    let original = fs::read(&path).unwrap();
    let blocked_temp = town.dir.join("world.tmp.tmp");
    fs::create_dir(&blocked_temp).unwrap();
    w.note_thought("r1", "这次写入会失败。", "测试");
    assert!(store
        .checkpoint_bundle(&w, 0.0, &settings, None, None, true)
        .is_err());
    assert_eq!(fs::read(&path).unwrap(), original);
    fs::remove_dir(&blocked_temp).unwrap();
    assert!(SaveStore::open(&path, "fixture-v1".into()).is_err());
    drop(store);
    let mut wrong = SaveStore::open(&path, "different-map".into()).unwrap();
    assert!(wrong.restore_bundle(&mut tiny_world()).is_err());
    assert_eq!(fs::read(&path).unwrap(), original);
    drop(wrong);
    let mut invalid: Value = serde_json::from_slice(&original).unwrap();
    invalid["schema_version"] = json!(99);
    fs::write(&path, invalid.to_string()).unwrap();
    let mut store = SaveStore::open(&path, "fixture-v1".into()).unwrap();
    assert!(store.restore_bundle(&mut tiny_world()).is_err());
    assert_eq!(fs::read_to_string(&path).unwrap(), invalid.to_string());
    fs::write(&path, "{broken").unwrap();
    assert!(store.restore_bundle(&mut tiny_world()).is_err());
    assert_eq!(fs::read_to_string(&path).unwrap(), "{broken");
    fs::write(&path, original).unwrap();
    assert_eq!(
        store
            .restore_bundle(&mut tiny_world())
            .unwrap()
            .map(|r| r.speed),
        Some(0.0)
    );
}
