//! 夹具二维地图、真实 WebSocket、隔离存档，模型使用固定回复。
use crate::support::*;
use serde_json::{json, Value};
use std::{fs, net::TcpStream};
use tungstenite::WebSocket;
fn town() -> Town {
    let mut t = Town::new();
    t.args = map_args(MAP_2D);
    t
}
fn environment(ws: &mut WebSocket<TcpStream>) -> Value {
    until(ws, |m| m["type"] == "roster")["environment"].clone()
}
fn command(view: &Value, id: &str, kind: &str) -> Value {
    json!({"type":"set_weather","world_id":view["world_id"],"request_id":id,"expected_revision":view["revision"],"mode":"fixed","kind":kind})
}
#[test]
fn weather_control_is_durable_idempotent_and_world_scoped() {
    let mut t = town();
    let mut ws = t.start();
    let original = environment(&mut ws);
    assert_eq!(original["kind"], "clear");
    let cmd = command(&original, "fixed-rain", "rain");
    let receipt = reply(&mut ws, cmd.clone(), "weather_saved");
    assert_eq!(receipt["ok"], true);
    let rain = receipt["environment"].clone();
    assert_eq!(rain["mode"], "fixed");
    assert_eq!(
        reply(&mut ws, cmd.clone(), "weather_saved")["environment"],
        rain
    );
    let conflict = reply(
        &mut ws,
        command(&original, "stale", "snow"),
        "weather_saved",
    );
    assert_eq!(conflict["code"], "revision_conflict");
    let mut changed = cmd.clone();
    changed["kind"] = json!("snow");
    assert_eq!(
        reply(&mut ws, changed, "weather_saved")["code"],
        "invalid_weather"
    );
    let mut wrong = command(&rain, "wrong-world", "snow");
    wrong["world_id"] = json!("not-this-world");
    assert_eq!(
        reply(&mut ws, wrong, "weather_saved")["code"],
        "world_mismatch"
    );
    let saved = t.saved(|s| s["world"]["weather"]["weather"]["view"] == rain);
    assert_eq!(saved["schema_version"], 6);
    assert_eq!(saved["world"]["schema_version"], 5);
    assert_eq!(saved["speed"], 0.0);
    let rng = saved["world"]["weather"]["weather"]["rng"].clone();
    drop(ws);
    t.kill();
    let mut ws = t.start();
    assert_eq!(environment(&mut ws), rain);
    assert_eq!(
        reply(&mut ws, cmd.clone(), "weather_saved")["environment"],
        rain
    );
    assert_eq!(
        t.saved(|s| s["world"]["weather"]["weather"]["view"] == rain)["world"]["weather"]
            ["weather"]["rng"],
        rng
    );
    let natural = reply(
        &mut ws,
        json!({"type":"set_weather","world_id":rain["world_id"],"request_id":"natural","expected_revision":rain["revision"],"mode":"natural"}),
        "weather_saved",
    );
    assert_eq!(natural["ok"], true);
    assert_eq!(natural["environment"]["kind"], "rain");
    reply(
        &mut ws,
        json!({"type":"reset_world","request_id":"test-reset-world"}),
        "world_reset",
    );
    assert_eq!(
        reply(&mut ws, cmd, "weather_saved")["code"],
        "world_mismatch"
    );
    let new = environment(&mut ws);
    assert_ne!(new["world_id"], rain["world_id"]);
    assert_eq!(new["kind"], "clear");
    assert_eq!(
        reply(&mut ws, command(&new, "not-ready", "snow"), "weather_saved")["code"],
        "world_not_ready"
    );
}
#[test]
fn failed_weather_save_rolls_back_and_can_retry_same_request() {
    let mut t = town();
    let mut ws = t.start();
    let initial = environment(&mut ws);
    let before = reply(
        &mut ws,
        command(&initial, "baseline", "clear"),
        "weather_saved",
    )["environment"]
        .clone();
    let bytes = fs::read(t.save()).unwrap();
    let temp = t.save().with_file_name("world.json.tmp");
    fs::create_dir(&temp).unwrap();
    let cmd = command(&before, "retry-save", "thunderstorm");
    let failed = reply(&mut ws, cmd.clone(), "weather_saved");
    assert_eq!(failed["code"], "save_failed");
    assert_eq!(failed["environment"], before);
    assert_eq!(fs::read(t.save()).unwrap(), bytes);
    fs::remove_dir(temp).unwrap();
    let ok = reply(&mut ws, cmd, "weather_saved");
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["environment"]["kind"], "thunderstorm");
}
#[test]
fn legacy_v4_migration_preserves_world_and_backs_up_original() {
    let mut t = town();
    let mut ws = t.start();
    let id = join_id(&mut ws, "tpl_a");
    let saved = t.saved(|s| !s["world"]["actors"][&id].is_null());
    drop(ws);
    t.kill();
    let mut old = saved.clone();
    old["schema_version"] = json!(4);
    old["world"]["schema_version"] = json!(4);
    old["world"].as_object_mut().unwrap().remove("weather");
    let bytes = serde_json::to_vec(&old).unwrap();
    fs::write(t.save(), &bytes).unwrap();
    let mut ws = t.start();
    let migrated = environment(&mut ws);
    assert_eq!(migrated["kind"], "clear");
    let new = t.saved(|s| s["schema_version"] == 6);
    assert_eq!(new["world"]["actors"], old["world"]["actors"]);
    assert_eq!(new["world"]["minutes"], old["world"]["minutes"]);
    assert_eq!(new["population"], old["population"]);
    let backup = t.dir.join("state/world.json.before-weather-v1/world.json");
    assert_eq!(fs::read(backup).unwrap(), bytes);
    drop(ws);
    t.kill();
    let mut ws = t.start();
    assert_eq!(environment(&mut ws), migrated);
    let mut broken = new.clone();
    broken["world"]["weather"]["weather"]["rng"]["state"] = json!(0);
    drop(ws);
    t.kill();
    let bad = serde_json::to_vec(&broken).unwrap();
    fs::write(t.save(), &bad).unwrap();
    assert!(t.try_start().is_err());
    assert_eq!(fs::read(t.save()).unwrap(), bad);
}
