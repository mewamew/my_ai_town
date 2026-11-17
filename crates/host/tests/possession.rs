use crate::{
    avatar::{command, state},
    support::*,
};
use serde_json::json;
use std::time::Duration;

#[test]
fn possession_lease_actions_rollback_reconnect_and_restart_use_the_original_resident() {
    let mut town = Town::new();
    town.args = map_args(MAP_2D);
    let mut ws = town.start();
    let resident = join_id(&mut ws, "tpl_b");
    let s = state(&mut ws);
    let entered = command(
        &mut ws,
        &s,
        1,
        json!({"kind":"possess","resident":resident}),
    );
    assert_eq!(entered["ok"], true, "{entered}");
    let mut s = entered["state"].clone();
    assert_eq!(s["mode"], "possession");
    assert_eq!(s["actor"]["id"], resident);
    assert_eq!(s["actor"]["needs"].as_array().unwrap().len(), 4);
    let mut other = connect_again(&ws);
    let other_state = state(&mut other);
    assert!(other_state["resume_token"].is_null());
    assert!(other_state["recent"].is_null());
    assert_eq!(
        command(
            &mut other,
            &other_state,
            1,
            json!({"kind":"possess","resident":resident})
        )["ok"],
        false
    );
    assert_eq!(
        command(
            &mut ws,
            &s,
            2,
            json!({"kind":"profile","name":"changed","appearance":{"marker":"我","color":"#387963"}})
        )["ok"],
        false
    );
    // 先记录一个未完成的真实玩家动作，再测试交还保存失败与重启。
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":0.125}),
    );
    until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 0.125);
    let action = command(
        &mut ws,
        &s,
        3,
        json!({"kind":"action","revision":s["actor"]["revision"],"action":{"intent":{"verb":"停留","duration_minutes":2}}}),
    );
    assert_eq!(action["ok"], true, "{action}");
    s = action["state"].clone();
    let original = town.save().with_extension("backup");
    std::fs::rename(town.save(), &original).unwrap();
    std::fs::create_dir(town.save()).unwrap();
    let failed = command(&mut ws, &s, 4, json!({"kind":"leave"}));
    assert_eq!(failed["ok"], false);
    assert_eq!(failed["state"]["controlled"], true);
    assert_eq!(failed["state"]["actor"]["id"], resident);
    std::fs::remove_dir(town.save()).unwrap();
    std::fs::rename(original, town.save()).unwrap();
    until(&mut ws, |m| m["type"] == "roster");
    let token = s["resume_token"].clone();
    drop(ws);
    std::thread::sleep(Duration::from_millis(150));
    let resumed = command(
        &mut other,
        &other_state,
        5,
        json!({"kind":"resume","token":token}),
    );
    assert_eq!(resumed["ok"], true, "{resumed}");
    assert_ne!(resumed["state"]["epoch"], s["epoch"]);
    assert_eq!(resumed["state"]["actor"]["id"], resident);
    let saved_text = std::fs::read_to_string(town.save()).unwrap();
    assert!(
        !saved_text.contains(token.as_str().unwrap()),
        "恢复令牌不能写入存档"
    );
    assert!(!saved_text.contains(resumed["state"]["resume_token"].as_str().unwrap()));
    town.shutdown();
    let mut ws = town.start();
    let current = state(&mut ws);
    assert_eq!(current["controlled"], false);
    let reentered = command(
        &mut ws,
        &current,
        1,
        json!({"kind":"possess","resident":resident}),
    );
    assert_eq!(reentered["ok"], true, "{reentered}");
    let s = reentered["state"].clone();
    assert_eq!(s["actor"]["id"], resident);
    assert_eq!(command(&mut ws, &s, 1, json!({"kind":"leave"}))["ok"], true);
    let saved: serde_json::Value =
        serde_json::from_slice(&std::fs::read(town.save()).unwrap()).unwrap();
    assert!(saved.to_string().contains("player_groups"));
    town.shutdown();
}

#[test]
fn resident_release_does_not_write_receipts_into_offstage_avatar() {
    let mut town = Town::new();
    town.args = map_args(MAP_2D);
    let mut ws = town.start();
    let resident = join_id(&mut ws, "tpl_b");
    let initial = state(&mut ws);
    let entered = command(
        &mut ws,
        &initial,
        1,
        json!({"kind":"enter","name":"aya","appearance":{"marker":"我","color":"#387963"}}),
    );
    assert_eq!(entered["ok"], true);
    let avatar = entered["state"].clone();
    assert_eq!(
        command(&mut ws, &avatar, 20, json!({"kind":"stop"}))["ok"],
        true
    );
    assert_eq!(
        command(&mut ws, &avatar, 21, json!({"kind":"leave"}))["ok"],
        true
    );
    let before =
        town.saved(|v| v["world"]["actors"]["player_avatar"]["locus"]["at"]["kind"] == "offstage");
    let observing = state(&mut ws);
    let possessed = command(
        &mut ws,
        &observing,
        1,
        json!({"kind":"possess","resident":resident}),
    );
    assert_eq!(possessed["ok"], true);
    assert_eq!(
        command(&mut ws, &possessed["state"], 2, json!({"kind":"leave"}))["ok"],
        true
    );
    let after: serde_json::Value =
        serde_json::from_slice(&std::fs::read(town.save()).unwrap()).unwrap();
    assert_eq!(
        after["world"]["actors"]["player_avatar"]["avatar"],
        before["world"]["actors"]["player_avatar"]["avatar"],
        "resident release must not lower the other actor's receipt sequence"
    );
    town.shutdown();
    let mut ws = town.start();
    assert_eq!(state(&mut ws)["controlled"], false);
    town.shutdown();
}

#[test]
fn possessed_tide_winner_releases_the_client_and_restores_new_and_legacy_saves() {
    let mut town = Town::new();
    town.args = map_args(MAP_2D);
    town.mock_delay = Some("60".into());
    let mut ws = town.start();
    let resident = join_id(&mut ws, "tpl_b");
    town.shutdown();
    drop(ws);
    // 保存的终局前夹具：只剩最后一圈的一分钟，不花几天模拟时间等待潮水。
    // 结局仍由真实 host 推进 Tide::last_call → depart，附身、动作和保存均走线上命令。
    let mut ready = read_json(&town.save());
    ready["world"]["game_mode"] = json!({"tide": {
        "seed":7,"first_day":0,"rings":[
            {"center":[24.0,30.0],"radius":40.0},
            {"center":[24.0,30.0],"radius":0.0}
        ],"timetable":[[400.0,410.0,421.0]],"told":2,
        "players":[{"id":resident,"name":"阿乙"}],"briefed":true
    }});
    town.write("state/world.json", ready);
    let mut ws = town.start();
    let observing = state(&mut ws);
    let entered = command(
        &mut ws,
        &observing,
        1,
        json!({"kind":"possess","resident":resident}),
    );
    assert_eq!(entered["ok"], true, "{entered}");
    let controlled = entered["state"].clone();
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"slow","speed":0.125}),
    );
    until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 0.125);
    let action = command(
        &mut ws,
        &controlled,
        2,
        json!({"kind":"action","revision":controlled["actor"]["revision"],"action":{"intent":{"verb":"停留","duration_minutes":120}}}),
    );
    assert_eq!(action["ok"], true, "{action}");
    let old_control = read_json(&town.save())["world"]["actors"][&resident]["possession"].clone();
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"finish","speed":60}),
    );
    until(&mut ws, |m| {
        m["type"] == "roster" && m["game_mode"]["winner"] == resident
    });
    let released = until(&mut ws, |m| m["type"] == "avatar_state")["state"].clone();
    assert_eq!(released["controlled"], false, "{released}");
    assert_eq!(released["occupied"], false);
    assert!(released["epoch"].is_null());
    assert!(released["resume_token"].is_null());
    assert!(released["actor"].is_null());
    let stale = command(&mut ws, &controlled, 3, json!({"kind":"stop"}));
    assert_eq!(stale["ok"], false, "old lease must not retain control");
    let mut other = connect_again(&ws);
    let s = state(&mut other);
    let entered = command(
        &mut other,
        &s,
        1,
        json!({
            "kind":"enter","name":"旁观者","appearance":{"marker":"我","color":"#387963"}
        }),
    );
    assert_eq!(
        entered["ok"], true,
        "departure must free the lease: {entered}"
    );
    assert_eq!(
        command(&mut other, &entered["state"], 2, json!({"kind":"leave"}))["ok"],
        true
    );
    town.shutdown();
    let saved = read_json(&town.save());
    let actor = &saved["world"]["actors"][&resident];
    assert_eq!(actor["locus"]["at"]["kind"], "offstage");
    assert!(actor.get("possession").is_none());
    assert!(actor["current"]["action"].is_null());
    assert!(actor["plan"].as_array().unwrap().is_empty());
    let mut ws = town.start();
    assert_eq!(state(&mut ws)["controlled"], false);
    let roster = until(&mut ws, |m| m["type"] == "roster");
    assert_eq!(roster["game_mode"]["winner"], resident);
    town.shutdown();

    // v6 的真实错误形状：离场、动作回执、历史均已落盘，唯独没有删掉原 possession。
    // 同一份结束存档先验证边界：新版本不走兼容修复，旧版本坏回执/重复控制也不能被清理掩盖。
    let mut legacy = saved.clone();
    legacy["schema_version"] = json!(6);
    legacy["world"]["actors"][&resident]["possession"] = old_control.clone();
    let backup = town
        .save()
        .with_file_name("world.json.before-departed-possession-v1");
    let mut current = legacy.clone();
    current["schema_version"] = json!(7);
    let mut bad_receipts = legacy.clone();
    bad_receipts["world"]["actors"][&resident]["possession"]["last_sequence"] = json!(0);
    let mut duplicate = legacy.clone();
    duplicate["world"]["actors"]["player_avatar"]["possession"] = old_control;
    for invalid in [current, bad_receipts, duplicate] {
        town.write("state/world.json", invalid);
        let bytes = std::fs::read(town.save()).unwrap();
        assert!(
            town.try_start().is_err(),
            "invalid control state must still fail closed"
        );
        town.kill();
        assert_eq!(std::fs::read(town.save()).unwrap(), bytes);
        assert!(
            !backup.exists(),
            "failed validation must not commit a migration"
        );
    }
    town.write("state/world.json", legacy.clone());
    let original = std::fs::read(town.save()).unwrap();
    let mut ws = town.start();
    assert_eq!(state(&mut ws)["controlled"], false);
    assert_eq!(std::fs::read(backup.join("world.json")).unwrap(), original);
    for segment in legacy["history"]["segments"].as_array().unwrap() {
        let name = format!("{:06}.jsonl", segment["id"].as_u64().unwrap());
        let source = std::fs::read(town.save().with_file_name("history").join(&name)).unwrap();
        let backed_up = std::fs::read(backup.join("history").join(name)).unwrap();
        let committed = segment["bytes"].as_u64().unwrap() as usize;
        assert_eq!(&backed_up[..committed], &source[..committed]);
    }
    town.shutdown();
    let migrated = read_json(&town.save());
    assert_eq!(migrated["schema_version"], 8);
    assert!(migrated["world"]["actors"][&resident]
        .get("possession")
        .is_none());
    assert_eq!(migrated["world"]["game_mode"], saved["world"]["game_mode"]);
    assert_eq!(
        town.history(&migrated),
        town.history(&saved),
        "repair must preserve history"
    );
    let mut ws = town.start();
    assert_eq!(state(&mut ws)["controlled"], false);
    town.shutdown();
}
