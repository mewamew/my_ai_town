//! Agent 轨迹日志：开镇时清掉空文件和超出额度的旧日志，别的文件不碰；配置里没写缺省（安装包就是这样）、
//! 设备上也没拨过时不记完整题面；在设定里打开后马上记，开关存进 preferences.json，重开小镇照旧。
use crate::support::*;
use serde_json::{json, Value};
use std::{
    fs,
    path::Path,
    time::{Duration, Instant, SystemTime},
};

#[test]
fn trace_logs_stay_within_limits_and_full_prompts_follow_the_device_switch() {
    let mut town = Town::new();
    let logs = town.dir.join("logs");
    fs::create_dir_all(&logs).unwrap();
    let stale = SystemTime::now() - Duration::from_secs(3600);
    let old = |stamp: u64| logs.join(format!("resident-agent-{stamp}-7.jsonl"));
    // 以前每次开镇都留下一份，没写东西的也留着
    for i in 0..3 {
        let file = fs::File::create(old(1_600_000_000_000 + i)).unwrap();
        file.set_modified(stale).unwrap();
    }
    // 四份旧日志各 100 MB（稀疏文件，不真占地方）：连新的一份最多留 256 MB，只装得下最新的两份
    for i in 0..4 {
        let file = fs::File::create(old(1_700_000_000_000 + i)).unwrap();
        file.set_len(100 << 20).unwrap();
    }
    fs::write(logs.join("builtin-model.log"), "llama").unwrap();
    fs::write(logs.join("resident-agent-notes.jsonl"), "").unwrap();

    let mut ws = town.start();
    let mut left = names(&logs);
    left.sort();
    assert_eq!(
        left,
        [
            "builtin-model.log",
            "resident-agent-1700000000002-7.jsonl",
            "resident-agent-1700000000003-7.jsonl",
            "resident-agent-notes.jsonl",
        ]
    );

    join_id(&mut ws, "tpl_a");
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"go","speed":60}),
    );
    let brief = next_request(&logs, &left, |_| true);
    let request = &brief["trace"]["data"]["request"];
    assert!(request.get("messages").is_none() && request.get("tools").is_none());
    assert!(request["message_count"].as_u64().unwrap() >= 2, "{request}");
    assert!(request["tool_count"].as_u64().unwrap() > 0, "{request}");
    assert!(
        request["latest_message"]["content"].is_string(),
        "{request}"
    );
    let state = reply(&mut ws, json!({"type":"get_agent_trace"}), "agent_trace")["state"].clone();
    assert_eq!(state["full_prompts"], false);
    assert_eq!(state["files"], 3, "{state}");
    assert!(state["bytes"].as_u64().unwrap() <= 256 << 20, "{state}");

    let saved = reply(
        &mut ws,
        json!({"type":"set_agent_trace","request_id":"full","full_prompts":true}),
        "config_saved",
    );
    assert_eq!(saved["ok"], true, "{saved}");
    assert_eq!(
        read_json(&town.dir.join("config/preferences.json")),
        json!({"trace_full_prompts": true})
    );
    // 回执到时已经写下的请求是打开之前发的；之后的才记完整题面
    let sent = last_request(&logs, &left);
    let full = next_request(&logs, &left, |line| {
        line["trace"]["request_id"].as_u64().unwrap() > sent
    });
    let request = &full["trace"]["data"]["request"];
    assert!(
        request["messages"].as_array().unwrap().len() >= 2,
        "{request}"
    );
    assert!(
        !request["tools"].as_array().unwrap().is_empty(),
        "{request}"
    );

    town.shutdown();
    drop(ws);
    let mut ws = town.start();
    let state = reply(&mut ws, json!({"type":"get_agent_trace"}), "agent_trace")["state"].clone();
    assert_eq!(state["full_prompts"], true, "{state}");
}

fn names(dir: &Path) -> Vec<String> {
    fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .collect()
}

/// 这次开镇新写的轨迹（开镇前没有的文件）里所有的请求行。
fn requests(logs: &Path, before: &[String]) -> Vec<Value> {
    let mut lines = Vec::new();
    for name in names(logs).into_iter().filter(|n| !before.contains(n)) {
        let text = fs::read_to_string(logs.join(name)).unwrap();
        // 最后一行可能还没写完
        lines.extend(
            text.lines()
                .filter_map(|line| serde_json::from_str::<Value>(line).ok())
                .filter(|line| line["trace"]["event"] == "request"),
        );
    }
    lines
}

fn last_request(logs: &Path, before: &[String]) -> u64 {
    requests(logs, before)
        .iter()
        .filter_map(|line| line["trace"]["request_id"].as_u64())
        .max()
        .unwrap()
}

/// 这次开镇新写的轨迹里，第一条满足条件的请求。
#[track_caller]
fn next_request(logs: &Path, before: &[String], accept: impl Fn(&Value) -> bool) -> Value {
    let deadline = Instant::now() + WAIT;
    loop {
        if let Some(line) = requests(logs, before).into_iter().find(|line| accept(line)) {
            return line;
        }
        assert!(Instant::now() < deadline, "轨迹里没等到请求");
        std::thread::sleep(Duration::from_millis(20));
    }
}
