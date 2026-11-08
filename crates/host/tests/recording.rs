//! 录像：世界开着录像跑一段，在设定里关掉后这一卷收好、列在录像里，开关随存档保存；
//! 删除只认录完的卷。收起的这一卷和页面当时收到的消息放进 target/tmp/recording-sample，
//! 由 scripts/tests/replay-reel.test.mjs 用重演画面共用的读法核对：名册一份不差。
//! 有一个人一开局就快渴死了：他的身体每拍都在变，录像里身体是拆开记的（b），也要读回一份不差。
use crate::support::*;
use serde_json::{json, Value};
use std::{cell::Cell, fs, path::Path};

#[test]
fn a_running_world_is_recorded_until_the_switch_is_turned_off() {
    let mut town = Town::new();
    town.args = map_args(MAP_2D);
    let mut ws = town.start();
    let thirsty = join_id(&mut ws, "tpl_a");
    join_id(&mut ws, "tpl_b");
    let world_id = reply(&mut ws, json!({"type":"get_population"}), "population")["population"]
        ["world_id"]
        .clone();
    let parched = reply(
        &mut ws,
        json!({"type":"set_resident_body","request_id":"parched","world_id":world_id,
            "resident_id":thirsty,"values":{"water":1,"fullness":1}}),
        "agent_saved",
    );
    assert_eq!(parched["ok"], true, "{parched}");
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"go","speed":20}),
    );
    let rosters = Cell::new(0);
    let mut received = received_until(&mut ws, |m| {
        rosters.set(rosters.get() + usize::from(m["type"] == "roster"));
        rosters.get() >= 30
    });
    send(
        &mut ws,
        json!({"type":"set_recording","request_id":"off","world_id":world_id,"enabled":false}),
    );
    received.extend(received_until(&mut ws, |m| {
        m["type"] == "world_settings_saved"
    }));
    assert_eq!(received.last().unwrap()["ok"], true);
    town.saved(|v| v["world_settings"]["recording"] == false);

    let list = reply(&mut ws, json!({"type":"get_recordings"}), "recordings");
    assert!(list.get("live").is_none(), "{list}");
    let reels = list["reels"].as_array().unwrap();
    assert_eq!(reels.len(), 1, "{list}");
    assert!(reels[0]["ended_at"].is_u64(), "{list}");
    let reel = reels[0]["id"].as_str().unwrap().to_owned();
    let recordings = town.save().with_file_name("recordings");
    assert!(
        reel_lines(&recordings.join(&reel))
            .iter()
            .any(|line| line["d"].get("b").is_some()),
        "快渴死的人身体在变，录像里该有拆开记的身体"
    );
    hand_to_reader_test(&recordings.join(&reel), &received);

    let on = reply(
        &mut ws,
        json!({"type":"set_recording","request_id":"on","world_id":world_id,"enabled":true}),
        "world_settings_saved",
    );
    assert_eq!(on["ok"], true, "{on}");
    let live = reply(&mut ws, json!({"type":"get_recordings"}), "recordings")["live"]
        .as_str()
        .unwrap()
        .to_owned();
    assert_ne!(live, reel);
    for (target, ok) in [
        (live.as_str(), false),
        ("../state", false),
        ("maps", false),
        (reel.as_str(), true),
    ] {
        let receipt = reply(
            &mut ws,
            json!({"type":"delete_recording","request_id":"del","world_id":world_id,"reel":target}),
            "world_settings_saved",
        );
        assert_eq!(receipt["ok"], ok, "{target}: {receipt}");
    }
    assert!(!recordings.join(&reel).exists());
    assert!(recordings.join(&live).join("header.json").is_file());
    assert!(town.save().is_file());
}

/// 这一卷的每一行（段文件压没压都认）。
fn reel_lines(reel: &Path) -> Vec<Value> {
    let mut lines = Vec::new();
    for entry in fs::read_dir(reel).unwrap() {
        let path = entry.unwrap().path();
        let name = path.file_name().unwrap().to_string_lossy().into_owned();
        let text = if name.ends_with(".jsonl.gz") {
            let mut out = String::new();
            std::io::Read::read_to_string(
                &mut flate2::read::GzDecoder::new(fs::File::open(&path).unwrap()),
                &mut out,
            )
            .unwrap();
            out
        } else if name.ends_with(".jsonl") {
            fs::read_to_string(&path).unwrap()
        } else {
            continue;
        };
        lines.extend(text.lines().filter_map(|l| serde_json::from_str(l).ok()));
    }
    lines
}

/// 这一卷和页面收到的消息（一行一条）放进 target/tmp/recording-sample。
fn hand_to_reader_test(reel: &Path, received: &[Value]) {
    let sample = Path::new(env!("CARGO_TARGET_TMPDIR")).join("recording-sample");
    let _ = fs::remove_dir_all(&sample);
    fs::create_dir_all(sample.join("reel")).unwrap();
    for entry in fs::read_dir(reel).unwrap() {
        let path = entry.unwrap().path();
        fs::copy(&path, sample.join("reel").join(path.file_name().unwrap())).unwrap();
    }
    let lines: Vec<String> = received.iter().map(Value::to_string).collect();
    fs::write(sample.join("received.jsonl"), lines.join("\n") + "\n").unwrap();
}
