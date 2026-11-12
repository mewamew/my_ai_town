//! 用临时配置启动真实 host，覆盖命令分发、回执只回发出的连接、角色卡细节只发给在看的连接、
//! 额度暂停、自动快进与配置文件的启动门槛。
use crate::support::*;
use serde_json::{json, Value};
use std::{
    fs,
    time::{Duration, Instant},
};

/// 两个页面同时保存人设：回执各回各的连接，带各自的请求编号；读不懂的命令回错误，带上编号，
/// 也只回发出它的连接。
#[test]
fn receipts_go_only_to_the_connection_that_sent_the_command() {
    let mut town = Town::new();
    town.persistent = false;
    let mut first = town.start();
    let id = join_id(&mut first, "tpl_a");
    let mut second = connect_again(&first);
    let persona = |request_id: &str, text: &str| json!({"type":"set_persona","request_id":request_id,"resident":id,"text":text});
    send(&mut first, persona("first-save", "# 阿甲\n第一个页面写的"));
    send(
        &mut second,
        persona("second-save", "# 阿甲\n第二个页面写的"),
    );
    let receipt = |own: &'static str| move |m: &serde_json::Value| m["request_id"] == own;
    let mut seen_first = received_until(&mut first, receipt("first-save"));
    let mut seen_second = received_until(&mut second, receipt("second-save"));
    assert_eq!(seen_first.last().unwrap()["type"], "agent_saved");
    assert_eq!(seen_first.last().unwrap()["ok"], true);
    assert_eq!(seen_second.last().unwrap()["ok"], true);
    // 两条保存都处理完才发这两条查询：发错连接的回执一定排在查询结果前面。
    let fence = json!({"type":"get_world_settings"});
    send(&mut first, fence.clone());
    send(&mut second, fence);
    seen_first.extend(received_until(&mut first, |m| {
        m["type"] == "world_settings"
    }));
    seen_second.extend(received_until(&mut second, |m| {
        m["type"] == "world_settings"
    }));
    let receipts = |seen: &[serde_json::Value]| -> Vec<String> {
        seen.iter()
            .filter(|m| m["type"] == "agent_saved")
            .map(|m| m["request_id"].as_str().unwrap().to_string())
            .collect()
    };
    assert_eq!(receipts(&seen_first), ["first-save"]);
    assert_eq!(receipts(&seen_second), ["second-save"]);

    send(
        &mut second,
        json!({"type":"set_persona","request_id":"broken","resident":id}),
    );
    let error = until(&mut second, |m| m["type"] == "error");
    assert_eq!(error["request_id"], "broken", "{error}");
    send(&mut first, json!({"type":"get_world_settings"}));
    let seen = received_until(&mut first, |m| m["type"] == "world_settings");
    assert!(!seen.iter().any(|m| m["type"] == "error"), "{seen:?}");
}

/// 名册每拍整份广播，只带每拍要用的 Agent 状态。角色卡细节（目标、动作结果、互动、记着的事）只发给
/// 说了在看这位村民的连接：说的时候一份，之后变了才再发；别的连接收不到，不看了就停。
#[test]
fn card_detail_goes_only_to_the_watching_connection_and_only_when_it_changes() {
    const LISTS: [&str; 4] = ["goals", "results", "interactions", "memories"];
    let details = |seen: &[Value]| -> Vec<Value> {
        seen.iter()
            .filter(|m| m["type"] == "resident_detail")
            .map(|m| m["detail"].clone())
            .collect()
    };
    let mut town = Town::new();
    town.persistent = false;
    let mut watcher = town.start();
    let id = join_id(&mut watcher, "tpl_a");
    let mut other = connect_again(&watcher);

    send(&mut watcher, json!({"type":"watch_resident","resident":id}));
    let first = until(&mut watcher, |m| m["type"] == "resident_detail");
    assert_eq!(first["resident_id"], id, "{first}");
    for list in LISTS {
        assert!(first["detail"][list].is_array(), "{first}");
    }
    // 世界停着，细节没变：名册照常每拍来，细节不重发；名册里的人只带状态
    let quiet = through_rosters(&mut watcher, 5);
    assert!(details(&quiet).is_empty(), "{quiet:?}");
    let member = members(quiet.last().unwrap())
        .into_iter()
        .find(|m| m["id"] == id)
        .unwrap();
    let agent = member["resident_agent"].as_object().unwrap();
    assert!(agent.contains_key("state"), "{member}");
    for list in LISTS {
        assert!(!agent.contains_key(list), "{member}");
    }

    // 他快渴死了，世界一走就有新的经历记下来：细节变了，才来新的一份，每一份都和上一份不一样
    let world_id = reply(&mut watcher, json!({"type":"get_population"}), "population")
        ["population"]["world_id"]
        .clone();
    let parched = reply(
        &mut watcher,
        json!({"type":"set_resident_body","request_id":"parched","world_id":world_id,
            "resident_id":id,"values":{"water":1,"fullness":1}}),
        "agent_saved",
    );
    assert_eq!(parched["ok"], true, "{parched}");
    send(
        &mut watcher,
        json!({"type":"set_speed","request_id":"go","speed":20}),
    );
    let mut seen = received_until(&mut watcher, |m| {
        m["type"] == "resident_detail" && m["detail"] != first["detail"]
    });
    seen.extend(through_rosters(&mut watcher, 20));
    let mut previous = first["detail"].clone();
    for detail in details(&seen) {
        assert_ne!(detail, previous, "细节没变也发了一份");
        previous = detail;
    }

    // 另一个页面没说在看：一份也收不到
    send(&mut other, json!({"type":"get_world_settings"}));
    let unwatched = received_until(&mut other, |m| m["type"] == "world_settings");
    assert!(unwatched.iter().any(|m| m["type"] == "roster"));
    assert!(details(&unwatched).is_empty(), "{unwatched:?}");

    // 这边不看了、换那个页面看：细节改发给它，这边不再收到
    send(&mut watcher, json!({"type":"watch_resident"}));
    send(&mut other, json!({"type":"watch_resident","resident":id}));
    let moved = until(&mut other, |m| m["type"] == "resident_detail");
    assert_eq!(moved["resident_id"], id, "{moved}");
    send(&mut watcher, json!({"type":"get_world_settings"}));
    received_until(&mut watcher, |m| m["type"] == "world_settings");
    let after = through_rosters(&mut watcher, 10);
    assert!(details(&after).is_empty(), "{after:?}");
}

#[test]
fn budget_exhaustion_pauses_the_town_until_limits_change_and_a_speed_is_chosen() {
    let mut town = Town::new();
    town.persistent = false;
    let mut ws = town.start();
    until(&mut ws, |m| m["type"] == "roster");
    let id = join_id(&mut ws, "tpl_a");
    let current = reply(&mut ws, json!({"type":"get_agent_limits"}), "agent_limits");
    assert_eq!(current["limits"]["calls_per_day"], 400);
    // 设定页检查输入用的范围由后端给出：每日 token 不小于模型窗口加单次输出上限
    assert_eq!(
        current["ranges"]["calls_per_wake"],
        json!({"min":1,"max":6})
    );
    assert_eq!(
        current["ranges"]["tokens_per_day"],
        json!({"min":32_000 + 2048,"max":null})
    );
    assert_eq!(current["usage"]["lifetime_calls"], 0);
    let mut limits = current["limits"].clone();
    limits["calls_per_day"] = json!(0);
    assert_eq!(
        reply(
            &mut ws,
            json!({"type":"set_agent_limits","request_id":"test-set-agent-limits","limits":limits}),
            "config_saved"
        )["ok"],
        false
    );
    limits["calls_per_day"] = json!(1);
    assert_eq!(
        reply(
            &mut ws,
            json!({"type":"set_agent_limits","request_id":"test-set-agent-limits","limits":limits}),
            "config_saved"
        )["ok"],
        true
    );
    assert_eq!(
        until(&mut ws, |m| m["type"] == "agent_limits")["limits"]["calls_per_day"],
        1
    );
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":20}),
    );
    until(&mut ws, |m| {
        m["type"] == "event"
            && m["text"]
                .as_str()
                .is_some_and(|t| t.contains("全镇已暂停") && t.contains("额度用尽"))
    });
    let held = until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 0.0);
    assert_eq!(held["holds"][0]["resident"], "阿甲");
    assert_eq!(held["holds"][0]["kind"], "budget");
    let member = members(&held).into_iter().find(|m| m["id"] == id).unwrap();
    assert_eq!(member["resident_agent"]["state"], "budget");
    let usage = reply(&mut ws, json!({"type":"get_agent_limits"}), "agent_limits");
    assert_eq!(usage["usage"]["residents"][0]["daily_calls"], 1);
    assert!(usage["usage"]["residents"][0]["paused"]
        .as_str()
        .unwrap()
        .starts_with("额度用尽"));
    // 只选速度、不改额度：重新检查后立刻再停，世界只走了一拍。
    let minutes = held["sim_minutes"].as_f64().unwrap();
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":20}),
    );
    let again = until(&mut ws, |m| {
        m["type"] == "roster" && m["speed"] == 0.0 && m["sim_minutes"].as_f64().unwrap() > minutes
    });
    assert_eq!(again["holds"][0]["kind"], "budget");
    limits["calls_per_day"] = json!(120);
    assert_eq!(
        reply(
            &mut ws,
            json!({"type":"set_agent_limits","request_id":"test-set-agent-limits","limits":limits}),
            "config_saved"
        )["ok"],
        true
    );
    let minutes = again["sim_minutes"].as_f64().unwrap();
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":20}),
    );
    let running = until(&mut ws, |m| {
        m["type"] == "roster"
            && m["speed"] == 20.0
            && m["sim_minutes"].as_f64().unwrap() > minutes + 2.0
    });
    assert!(running["holds"].is_null());
}

/// 自动快进：村民在等模型回复时世界按正常速度走，回复因此不会过时；大家都在做一件还要好一阵的事时
/// 世界加快（名册的 pace 是正常速度的倍数）。固定回复模型每次要 0.6 秒，先看一眼道具，再等 30 分钟。
/// 走路时不快进由内核的快进空档保证（temporal_integrity.rs）。
#[test]
fn the_world_fast_forwards_only_while_everyone_is_settled() {
    let mut town = Town::new();
    town.persistent = false;
    town.mock_delay = Some("0.6".into());
    let mut ws = town.start();
    let id = join_id(&mut ws, "tpl_a");
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":1}),
    );
    let (mut waited, mut fastest) = (0, 0.0_f64);
    let mut last: Option<(bool, f64)> = None;
    let deadline = Instant::now() + Duration::from_secs(20);
    while (waited < 5 || fastest < 8.0) && Instant::now() < deadline {
        let roster = until(&mut ws, |m| m["type"] == "roster" && m["speed"] == 1.0);
        let member = members(&roster)
            .into_iter()
            .find(|m| m["id"] == id)
            .unwrap();
        let thinking = member["resident_agent"]["state"] == "thinking";
        let (minutes, pace) = (
            roster["sim_minutes"].as_f64().unwrap(),
            roster["pace"].as_f64().unwrap(),
        );
        assert!(pace >= 1.0, "{pace}");
        // 刚发出请求的那一拍是在发出前推进的；之后整个等待期间一拍只走 0.1 分钟
        if let Some((true, before)) = last.filter(|_| thinking) {
            assert_eq!(pace, 1.0, "等回复时不快进");
            assert!(minutes - before <= 0.1 + 1e-9, "{before} → {minutes}");
            waited += 1;
        }
        fastest = fastest.max(pace);
        last = Some((thinking, minutes));
    }
    assert!(waited >= 5, "没有看到等回复的过程");
    assert!(fastest >= 8.0, "大家都在等着时没有快进：最快 {fastest}");
    let usage = usage_of(&mut ws, &id);
    assert_eq!(usage["stale_replies"], 0, "{usage}");
}

/// providers.json 存在但损坏：启动拒绝，写路径也拒绝覆盖，原文件原样保留。
#[test]
fn corrupt_providers_file_blocks_startup_and_is_never_overwritten() {
    let mut town = Town::new();
    let path = town.dir.join("config/providers.json");
    fs::write(&path, "{broken").unwrap();
    let error = town.try_start().expect_err("损坏的配置不能启动");
    assert!(error.contains("退出"), "{error}");
    let saved = host::config::save_providers(
        path.to_str().unwrap(),
        &host::config::ProvidersFile::default(),
    );
    assert!(saved.is_err());
    assert_eq!(fs::read_to_string(&path).unwrap(), "{broken");
    // 不存在才是空配置：删掉文件后照常启动。
    fs::remove_file(&path).unwrap();
    let mut ws = town.start();
    until(&mut ws, |m| m["type"] == "roster");
}

/// 观察者调身体：世界在跑时不收；暂停时调到提醒线以下，名册马上是新数值，本人照常收到饿了的提醒，
/// 但经历、身体记录里都没有「观察者」「调整」这类幕后的字样，下次观察看到的就和一路饿下来一样。
/// 健康调到 0 不行。
#[test]
fn observer_sets_body_only_while_paused_and_the_resident_just_feels_hungry() {
    let mut town = Town::new();
    let mut ws = town.start();
    let id = join_id(&mut ws, "tpl_a");
    let world_id = reply(&mut ws, json!({"type":"get_population"}), "population")["population"]
        ["world_id"]
        .clone();
    let adjust = |request_id: &str, values: serde_json::Value| {
        json!({"type":"set_resident_body","request_id":request_id,"world_id":world_id,
            "resident_id":id,"values":values})
    };
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"run","speed":1}),
    );
    let running = reply(
        &mut ws,
        adjust("while-running", json!({"fullness":30})),
        "agent_saved",
    );
    assert_eq!(running["ok"], false, "{running}");
    assert!(running["message"].as_str().unwrap().contains("先暂停"));
    send(
        &mut ws,
        json!({"type":"set_speed","request_id":"pause","speed":0}),
    );
    let dead = reply(&mut ws, adjust("kill", json!({"health":0})), "agent_saved");
    assert_eq!(dead["ok"], false, "{dead}");
    let saved = reply(
        &mut ws,
        adjust("hungry", json!({"fullness":30,"energy":60})),
        "agent_saved",
    );
    assert_eq!(saved["ok"], true, "{saved}");
    assert_eq!(saved["request_id"], "hungry");
    assert!(saved["message"].as_str().unwrap().contains("饱腹 75 → 30"));
    let roster = until(&mut ws, |m| {
        m["type"] == "roster"
            && members(m).iter().any(|r| {
                r["id"] == id.as_str()
                    && r["needs"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .any(|n| n["kind"] == "fullness" && n["value"] == 30.0)
            })
    });
    let me = members(&roster)
        .into_iter()
        .find(|r| r["id"] == id.as_str())
        .unwrap();
    let fullness = me["needs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|n| n["kind"] == "fullness")
        .unwrap()
        .clone();
    assert_eq!(fullness["band"], "urgent", "{fullness}");
    let save = town.saved(|v| v["world"]["actors"][&id]["needs"]["fullness"]["value"] == 30.0);
    let actor = save["world"]["actors"][&id].to_string();
    assert!(actor.contains("饱腹降低，需要关注身体状态"), "{actor}");
    for hidden in ["观察者", "调整", "受控实验"] {
        assert!(
            !actor.contains(hidden),
            "本人记录里出现了「{hidden}」：{actor}"
        );
    }
}
