//! 通过真实 WebSocket 验证启动门槛、上下文更新、冲突、重置和存档隔离。
use crate::support::*;
use serde_json::{json, Value};
use std::net::TcpStream;
use tungstenite::WebSocket;

fn state(ws: &mut WebSocket<TcpStream>) -> Value {
    reply(ws, json!({"type":"get_world_settings"}), "world_settings")["state"].clone()
}
fn save(ws: &mut WebSocket<TcpStream>, s: &Value, text: &str) -> Value {
    reply(
        ws,
        json!({"type":"set_worldview","request_id":"save-world","world_id":s["world_id"],"expected_revision":s["revision"],"text":text}),
        "world_settings_saved",
    )
}

#[test]
fn worldview_reaches_existing_and_new_residents_survives_restart_and_reset_requires_setup() {
    let mut town = Town::new();
    town.setup = false;
    let mut ws = town.start();
    let s = state(&mut ws);
    assert_eq!(save(&mut ws, &s, "初始世界：居民认识彼此。")["ok"], true);
    let a = join(&mut ws, "tpl_a", None);
    assert_eq!(a["ok"], true);
    let id = a["resident_id"].as_str().unwrap();
    let before = state(&mut ws);
    assert_eq!(
        save(&mut ws, &before, "新的世界：人们只通过公告交换消息。")["ok"],
        true
    );
    let b = join(&mut ws, "tpl_b", None);
    assert_eq!(b["ok"], true);
    // 存盘失败：设定、修订号和两位居民的会话指令都回到修改前。
    let blocker = town.save().with_file_name("world.json.tmp");
    std::fs::create_dir(&blocker).unwrap();
    let pending = state(&mut ws);
    let failed = save(&mut ws, &pending, "不会生效的世界观。");
    assert_eq!(failed["ok"], false, "{failed}");
    assert_eq!(state(&mut ws), pending);
    std::fs::remove_dir(&blocker).unwrap();
    // 设速度会存盘，把内存里的会话写到磁盘上检查；命令按顺序执行，读到下一条回复时这次存盘已经写完。
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-save-sessions","speed":0}),
    );
    assert_eq!(state(&mut ws), pending);
    let saved = town.saved(|_| true);
    for resident in [id, b["resident_id"].as_str().unwrap()] {
        let instructions = saved["resident_agent"]["runtime"]["sessions"][resident]["instructions"]
            .as_str()
            .unwrap();
        assert!(instructions.contains("人们只通过公告交换消息"));
        assert!(!instructions.contains("初始世界"));
        assert!(!instructions.contains("不会生效"));
    }
    let current = state(&mut ws);
    drop(ws);
    town.kill();
    // 旧存档还记着已经删掉的「手动验证」开关和工具协议：照常读进来，下次存盘不再写出。
    let mut old: Value =
        serde_json::from_str(&std::fs::read_to_string(town.save()).unwrap()).unwrap();
    // v7 没有初始化标记：升级只加格式版本，不能把玩家已定制的普通世界当作未完剧本。
    old["schema_version"] = json!(7);
    old["world_settings"]["autonomous"] = json!(false);
    old["resident_agent"]["protocol"] = json!("json");
    std::fs::write(town.save(), old.to_string()).unwrap();
    let original = std::fs::read(town.save()).unwrap();
    let mut ws = town.start();
    let backup = town
        .save()
        .with_file_name("world.json.before-prefab-setup-v1");
    assert_eq!(std::fs::read(backup.join("world.json")).unwrap(), original);
    assert_eq!(state(&mut ws), current);
    let migrated = town.saved(|v| v["schema_version"] == 8);
    assert!(migrated["world_settings"].get("prefab_setup").is_none());
    assert_eq!(
        migrated["world_settings"]["worldview"],
        old["world_settings"]["worldview"]
    );
    assert_eq!(migrated["population"], old["population"]);
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-drop-legacy","speed":0}),
    );
    town.saved(|v| {
        v["world_settings"].get("autonomous").is_none()
            && v["resident_agent"].get("protocol").is_none()
    });
    reply(
        &mut ws,
        json!({"type":"reset_world","request_id":"test-reset-world"}),
        "world_reset",
    );
    let fresh = state(&mut ws);
    assert_eq!(fresh["ready"], false);
    assert_eq!(fresh["revision"], 0);
    assert_ne!(fresh["world_id"], current["world_id"]);
    assert_eq!(save(&mut ws, &current, "迟到的保存")["ok"], false);
}
