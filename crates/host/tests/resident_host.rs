//! 隔离配置下运行正式 host，通过本地 HTTP 工具服务验证模型调用与存档恢复。
use crate::support::*;
use serde_json::{json, Value};
use std::{
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};
use tungstenite::WebSocket;

struct Endpoint {
    url: String,
    stop: Arc<AtomicBool>,
    models: Arc<Mutex<Vec<String>>>,
    thread: Option<std::thread::JoinHandle<()>>,
}
impl Endpoint {
    fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let stop = Arc::new(AtomicBool::new(false));
        let stopping = stop.clone();
        let models = Arc::new(Mutex::new(Vec::new()));
        let recorded_models = models.clone();
        let thread = std::thread::spawn(move || {
            while !stopping.load(Ordering::Relaxed) {
                let Ok((mut stream, _)) = listener.accept() else {
                    std::thread::sleep(Duration::from_millis(5));
                    continue;
                };
                // macOS 的 accept 会继承非阻塞标志；请求正文按有超时的阻塞流读取。
                stream.set_nonblocking(false).unwrap();
                stream
                    .set_read_timeout(Some(Duration::from_secs(5)))
                    .unwrap();
                let mut bytes = Vec::new();
                let mut chunk = [0; 4096];
                let value = loop {
                    let count = stream.read(&mut chunk).unwrap();
                    assert!(count > 0);
                    bytes.extend_from_slice(&chunk[..count]);
                    if let Some(end) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
                        let headers = String::from_utf8_lossy(&bytes[..end]);
                        let length: usize = headers
                            .lines()
                            .find_map(|line| {
                                line.to_lowercase()
                                    .strip_prefix("content-length:")
                                    .map(|v| v.trim().parse().unwrap())
                            })
                            .unwrap();
                        if bytes.len() >= end + 4 + length {
                            break serde_json::from_slice::<Value>(
                                &bytes[end + 4..end + 4 + length],
                            )
                            .unwrap();
                        }
                    }
                };
                recorded_models
                    .lock()
                    .unwrap()
                    .push(value["model"].as_str().unwrap_or_default().to_string());
                let reflection = value["messages"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .filter_map(|m| m["content"].as_str())
                    .filter_map(|s| serde_json::from_str::<Value>(s).ok())
                    .find_map(|v| v.get("reflection_task").cloned());
                assert_eq!(
                    value["tools"].as_array().unwrap().len(),
                    if reflection.is_some() { 3 } else { 13 }
                );
                let completed = value["messages"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|m| m["tool_call_id"] == "read");
                let (id, name, args) = if let Some(batch) = reflection {
                    (
                        "reflect",
                        "reflect",
                        json!({"through_event":batch["through"],"summary":"测试公告经历已整理。","notes":[]}),
                    )
                } else if completed {
                    (
                        "wait",
                        "wait_for",
                        json!({"minutes":60,"reason":"读完后休息"}),
                    )
                } else {
                    (
                        "read",
                        "run_actions",
                        json!({"actions":[{"intent":{"verb":"阅读公告"},"prop_id":"board"}]}),
                    )
                };
                let message = json!({"role":"assistant","content":"读一读公告。","tool_calls":[{"id":id,"type":"function","function":{"name":name,"arguments":args.to_string()}}]});
                let body=json!({"choices":[{"message":message}],"usage":{"prompt_tokens":100,"completion_tokens":50}}).to_string();
                write!(stream,"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",body.len(),body).unwrap();
            }
        });
        Self {
            url,
            stop,
            models,
            thread: Some(thread),
        }
    }

    fn models(&self) -> Vec<String> {
        self.models.lock().unwrap().clone()
    }
}
impl Drop for Endpoint {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        let result = self.thread.take().unwrap().join();
        if !std::thread::panicking() {
            result.expect("固定工具服务线程失败");
        }
    }
}

/// 两地小镇：甲地是入口（公告栏也在这里），乙地是唯一住家；模型端点指向本地夹具。
fn town(endpoint: &str) -> Town {
    let mut town = Town::empty();
    town.mock_delay = None;
    town.configure("topology.json");
    let mut topo = read_json(&fixture("two_places.json"));
    topo["places"][0]["type"] = json!("公共地点");
    topo["places"][1]["type"] = json!("住家");
    topo["places"][1]["residential"] = json!(true);
    topo["entry"] = json!({"locale":"loc_a","station":"st_a"});
    topo["props"] = json!([{"id":"board","name":"公告栏","locale":"loc_a","verbs":[{"verb":"阅读公告","duration_minutes":5,"action":{"id":"read_bulletin","label":"阅读公告","duration_minutes":5,"completion":"read_bulletin"}}]}]);
    topo["props"][0]["readable"] = json!({"work_id":"b1","version":1,"kind":"bulletin","title":"公告","author":"佚名","text":"图书馆今天开放","origin":{"kind":"builtin"}});
    topo["props"][0]["board"] = json!("board_furniture");
    topo["props"].as_array_mut().unwrap().push(json!({"id":"board_furniture","name":"公告栏","locale":"loc_a","bulletin_board":true,"verbs":[]}));
    town.write("topology.json", topo);
    town.write("config/providers.json",json!({"active":{"resident":"阿树","provider":"fixture","model":"m"},"providers":[{"id":"fixture","name":"Fixture","base_url":endpoint}]}));
    town
}

fn speed(ws: &mut WebSocket<TcpStream>, value: f64) {
    send(
        ws,
        json!({"type":"set_speed","request_id":"test-set-speed","speed":value}),
    );
}

/// 没有默认村民也没有内置库：先存一份自定义模板，再从村民库加入，返回服务器分配的 id。
fn join_first(ws: &mut WebSocket<TcpStream>) -> String {
    let saved = reply(
        ws,
        json!({"type":"save_resident_template","request_id":"test-save-resident-template","fields":{"name":"阿树","intro":"喜欢了解新事物。","tags":[],"appearance":{"marker":"dot","color":"#000"}}}),
        "template_saved",
    );
    assert_eq!(saved["ok"], true, "{saved}");
    let template_id = saved["template"]["template_id"].as_str().unwrap();
    join_id(ws, template_id)
}

#[test]
fn sessions_resume_in_the_formal_host_without_repeating_actions() {
    let endpoint = Endpoint::start();
    let mut town = town(&endpoint.url);
    // 模型回复和世界自己往前走的进度不再当场存，靠周期存盘落到盘上
    town.autosave = true;
    let mut ws = town.start();
    let id = join_first(&mut ws);
    assert_eq!(id, "resident_001");
    let configured = reply(
        &mut ws,
        json!({"type":"set_resident_model","request_id":"test-set-resident-model","resident":id,"model":{"provider":"fixture","model":"m"}}),
        "agent_saved",
    );
    assert_eq!(configured["ok"], true, "{configured}");
    speed(&mut ws, 1.0);
    town.saved(|v| {
        v.pointer("/resident_agent/runtime/sessions/resident_001/pending/0/kind")
            == Some(&json!("actions"))
            && v["world"]["actors"]["resident_001"]["current"]["action"].is_object()
    });
    speed(&mut ws, 0.0);
    send(
        &mut ws,
        json!({"type":"set_persona","request_id":"test-set-persona","resident":id,"text":"# 阿树\n重启后仍记得的新设定。"}),
    );
    let before = town.saved(|v| {
        v["speed"] == 0.0
            && v["world"]["actors"]["resident_001"]["current"]["action"].is_object()
            && v["resident_agent"]["runtime"]["sessions"]["resident_001"]["instructions"]
                .as_str()
                .is_some_and(|s| s.contains("重启后仍记得的新设定"))
    });
    let old_epoch = before["resident_agent"]["runtime"]["epoch"]
        .as_u64()
        .unwrap();
    let old_groups = before["world"]["actors"]["resident_001"]["actions"]["groups"].clone();
    town.kill();
    drop(ws);
    let mut ws = town.start();
    let recovered = town.saved(|v| {
        v["resident_agent"]["runtime"]["epoch"]
            .as_u64()
            .is_some_and(|e| e > old_epoch)
    });
    assert_eq!(
        recovered["world"]["actors"]["resident_001"]["actions"]["groups"],
        old_groups
    );
    assert_eq!(recovered["world"]["minutes"], before["world"]["minutes"]);
    speed(&mut ws, 10.0);
    let complete = town.saved(|v| {
        v.pointer("/resident_agent/runtime/sessions/resident_001/pending/0/kind")
            == Some(&json!("wait"))
    });
    // 做完的动作组不在 world.json 里了，在流水里：只有一组，没有重做
    let running = &complete["world"]["actors"]["resident_001"]["actions"]["groups"];
    assert_eq!(running, &json!({}));
    let history = town.history(&complete);
    let groups: Vec<_> = history
        .iter()
        .filter(|line| line["actions"]["actor"] == "resident_001")
        .collect();
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0]["actions"]["group"]["status"], "succeeded");
    let messages = complete["resident_agent"]["runtime"]["sessions"]["resident_001"]["messages"]
        .as_array()
        .unwrap();
    assert_eq!(
        messages
            .iter()
            .filter(|m| m["role"] == "tool" && m["call_id"] == "read")
            .count(),
        1
    );
    assert_eq!(
        complete["resident_agent"]["runtime"]["lifetime"]["calls"],
        2
    );
}

#[test]
fn residents_use_independent_models_and_the_binding_survives_restart() {
    let endpoint = Endpoint::start();
    let mut town = Town::new();
    town.mock_delay = None;
    town.write(
        "config/providers.json",
        json!({
            "active":null,
            "providers":[
                {"id":"fixture-a","name":"Resident A","base_url":endpoint.url},
                {"id":"fixture-b","name":"Resident B","base_url":endpoint.url,"model":"resident-b"}
            ]
        }),
    );
    let mut ws = town.start();
    let first = join_id(&mut ws, "tpl_a");
    let second = join_id(&mut ws, "tpl_b");
    assert_ne!(first, second);

    let unconfigured = reply(
        &mut ws,
        json!({"type":"get_agent_config","resident":first}),
        "agent_config",
    );
    assert!(unconfigured["model_binding"].is_null(), "{unconfigured}");
    let saved_first = reply(
        &mut ws,
        json!({"type":"set_resident_model","request_id":"test-set-resident-model","resident":first,"model":{"provider":"fixture-a","model":"resident-a"}}),
        "agent_saved",
    );
    assert_eq!(saved_first["ok"], true, "{saved_first}");
    let saved = reply(
        &mut ws,
        json!({"type":"set_resident_model","request_id":"test-set-resident-model","resident":second,"model":{"provider":"fixture-b","model":"resident-b"}}),
        "agent_saved",
    );
    assert_eq!(saved["ok"], true, "{saved}");
    let snapshot = town.saved(|value| {
        value["population"]["residents"][&first]["model_binding"]["model"] == "resident-a"
            && value["population"]["residents"][&second]["model_binding"]["model"] == "resident-b"
    });
    assert_eq!(
        snapshot["population"]["residents"][&first]["model_binding"]["model"],
        "resident-a"
    );

    let rejected = reply(
        &mut ws,
        json!({
            "type":"set_model_config","request_id":"test-set-model-config",
            "active":null,
            "providers":[
                {"id":"fixture-a","name":"Resident A","base_url":endpoint.url}
            ],
            "keys":[]
        }),
        "config_saved",
    );
    assert_eq!(rejected["ok"], false, "{rejected}");
    assert!(
        rejected["message"]
            .as_str()
            .unwrap_or_default()
            .contains("fixture-b"),
        "{rejected}"
    );

    speed(&mut ws, 1.0);
    let deadline = std::time::Instant::now() + Duration::from_secs(8);
    loop {
        let models = endpoint.models();
        if models.iter().any(|model| model == "resident-a")
            && models.iter().any(|model| model == "resident-b")
        {
            break;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "没有观察到两位村民各自的模型请求：{models:?}"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
    speed(&mut ws, 0.0);
    town.kill();
    drop(ws);

    let mut ws = town.start();
    let config = reply(
        &mut ws,
        json!({"type":"get_agent_config","resident":second}),
        "agent_config",
    );
    assert_eq!(config["resident_id"], second);
    assert_eq!(config["model_binding"]["provider"], "fixture-b");
    assert_eq!(config["model_binding"]["model"], "resident-b");

    let first_config = reply(
        &mut ws,
        json!({"type":"get_agent_config","resident":first}),
        "agent_config",
    );
    assert_eq!(first_config["model_binding"]["provider"], "fixture-a");
    assert_eq!(first_config["model_binding"]["model"], "resident-a");

    // 服务记着的模型名：被拒的保存没动配置，重开后回读里还带着，页面选这个服务时靠它自动填上
    let config = reply(&mut ws, json!({"type":"get_model_config"}), "model_config");
    let models: Vec<_> = config["providers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| (p["id"].as_str().unwrap(), p["model"].as_str().unwrap()))
        .collect();
    assert!(models.contains(&("fixture-a", "")), "{config}");
    assert!(models.contains(&("fixture-b", "resident-b")), "{config}");
}

/// 没选模型不算故障：不暂停全镇、不发请求，也不悄悄改用小镇的工具模型；谁都还不能思考时时间停着。
/// 入住时带上模型的人直接开始思考，没选的人选好后自动接着走。
#[test]
fn residents_without_a_model_wait_until_one_is_chosen() {
    let endpoint = Endpoint::start();
    let mut town = Town::new();
    town.mock_delay = None;
    town.write(
        "config/providers.json",
        json!({
            "active":{"resident":"小镇","provider":"fixture-tool","model":"tool-model"},
            "providers":[
                {"id":"fixture-tool","name":"Tool","base_url":endpoint.url}
            ]
        }),
    );
    let mut ws = town.start();
    let id = join_id(&mut ws, "tpl_a");

    speed(&mut ws, 20.0);
    let waiting = until(&mut ws, |message| {
        message["type"] == "roster"
            && message["speed"] == 20.0
            && members(message)
                .iter()
                .any(|m| m["id"] == id && m["resident_agent"]["state"] == "no_model")
    });
    let frozen_at = waiting["sim_minutes"].clone();
    for _ in 0..10 {
        let roster = until(&mut ws, |message| message["type"] == "roster");
        assert_eq!(roster["speed"], 20.0, "等模型不该暂停全镇");
        assert!(
            roster["holds"].as_array().is_none_or(Vec::is_empty),
            "{roster}"
        );
        assert_eq!(roster["sim_minutes"], frozen_at, "谁都不能思考时时间应停着");
    }
    assert!(endpoint.models().is_empty(), "没选模型不该发请求");

    let joined = join_as(
        &mut ws,
        "tpl_b",
        None,
        Some(json!({"provider":"fixture-tool","model":"joined-model"})),
    );
    assert_eq!(joined["ok"], true, "{joined}");
    let models_seen = |name: &str| {
        let deadline = std::time::Instant::now() + Duration::from_secs(8);
        while !endpoint.models().iter().any(|model| model == name) {
            assert!(
                std::time::Instant::now() < deadline,
                "没有观察到 {name} 的请求：{:?}",
                endpoint.models()
            );
            std::thread::sleep(Duration::from_millis(10));
        }
    };
    models_seen("joined-model");
    let saved = reply(
        &mut ws,
        json!({"type":"set_resident_model","request_id":"test-set-resident-model","resident":id,"model":{"provider":"fixture-tool","model":"chosen-model"}}),
        "agent_saved",
    );
    assert_eq!(saved["ok"], true, "{saved}");
    models_seen("chosen-model");
    assert!(
        !endpoint.models().iter().any(|model| model == "tool-model"),
        "工具模型不应收到村民请求"
    );
}
