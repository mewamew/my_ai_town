//! 每个测试使用独立目录；覆盖提交失败、恢复、迁移与重置，不碰正式存档。
//! 夹具只依赖 agent 的公开接口，不引用 agent 的测试文件。
use crate::support::Town;
use agent::{
    budget::Limits,
    context,
    conversation::{ModelReply, ToolCall},
    notebook::{apply_reflection, plan_reflection},
    runtime::{AgentRequest, ResidentRuntime},
    session::Session,
};
use host::persistence::SaveStore;
use kernel::{Topology, World};
use serde_json::{json, Value};
use std::{fs, path::PathBuf};

/// 只用夹具的临时目录，存档直接放在目录根下。用例在进程内反复开关存档锁，期间不起子进程。
struct Scratch {
    dir: PathBuf,
    _town: Town,
    _no_spawns: std::sync::MutexGuard<'static, ()>,
}
impl Scratch {
    fn new() -> Self {
        let no_spawns = crate::support::hold_spawns();
        let town = Town::empty();
        Self {
            dir: town.dir.clone(),
            _town: town,
            _no_spawns: no_spawns,
        }
    }
    fn save(&self) -> PathBuf {
        self.dir.join("world.json")
    }
    fn store(&self) -> SaveStore {
        SaveStore::open(&self.save(), "fixture".into()).unwrap()
    }
}

/// 两地小镇：甲地有一块可读公告，阿树住在甲地。
fn world() -> World {
    let mut data = crate::support::read_json(&crate::support::fixture("two_places.json"));
    data["props"] = json!([
        {"id":"board","name":"公告栏","locale":"loc_a","board":"fixture-board",
         "readable":{"work_id":"b1","version":1,"kind":"bulletin","title":"公告","author":"佚名","text":"图书馆今天开放","origin":{"kind":"builtin"}},
         "verbs":[{"verb":"阅读公告","duration_minutes":1,"action":{"id":"read_bulletin","label":"阅读公告","duration_minutes":1,"completion":"read_bulletin"}},
                  {"verb":"查看公告栏","duration_minutes":1}]},
        {"id":"bench","name":"工作台","locale":"loc_b","verbs":[{"verb":"制作器物","duration_minutes":2}]},
        {"id":"fixture-board","name":"公告栏支架","locale":"loc_a","bulletin_board":true,"verbs":[{"verb":"查看支架","duration_minutes":1}]}
    ]);
    let mut w = World::new(
        Topology::from_json(&data.to_string(), &kernel::props::Catalog::default()).unwrap(),
        420.0,
        crate::support::need_rules(),
    );
    w.spawn("r1", "阿树", "loc_a").unwrap();
    w
}

fn reply(r: &mut ResidentRuntime, w: &mut World, request: &AgentRequest, name: &str, args: Value) {
    assert!(r.on_reply(
        w,
        &request.actor_id,
        request.stamp.id,
        request.stamp.epoch,
        Ok(ModelReply {
            thought: "先看看情况。".into(),
            calls: vec![ToolCall {
                id: format!("c{}", request.stamp.id),
                name: name.into(),
                arguments: args
            }],
            usage: None,
        }),
        25
    ));
}

/// 改一版公告并让 r1 读完它。
fn read_board(w: &mut World, actor: &str, id: &str, text: &str) {
    let version = w.content_detail("board").unwrap().content.unwrap().version;
    w.revise_bulletin(
        "board",
        version,
        format!("公告{id}"),
        "佚名".into(),
        text.into(),
    )
    .unwrap();
    w.run_actions(
        actor,
        id,
        w.actor(actor).unwrap().actions.revision,
        &serde_json::from_value::<Vec<protocol::ActionDraft>>(
            json!([{"intent":{"verb":"阅读公告"},"prop_id":"board"}]),
        )
        .unwrap(),
    )
    .unwrap();
    w.step(2.0);
}

/// 读过两版公告、回复过一次观察的会话。
fn prepared() -> (World, ResidentRuntime) {
    let mut w = world();
    w.enable_agent("r1").unwrap();
    read_board(
        &mut w,
        "r1",
        "first",
        &format!(
            "图书馆今天开放。{}",
            "这是公告当时写的内容，尚未亲自到图书馆核实。".repeat(5)
        ),
    );
    read_board(
        &mut w,
        "r1",
        "second",
        "新公告：图书馆明天维修关闭，后天再开放。",
    );
    let mut r = ResidentRuntime::new(Limits::default()).unwrap();
    r.register(&mut w, "r1", "我想了解小镇，也会注意吃饭和休息。")
        .unwrap();
    let q = r.poll(&mut w, true).remove(0);
    reply(&mut r, &mut w, &q, "observe", json!({}));
    (w, r)
}

/// 按整理任务写一条笔记，让会话产生笔记本页面与记忆记录。
fn reflect(w: &World, s: &mut Session, text: &str) {
    s.notebook.request = plan_reflection(w, s);
    let batch = s.notebook.request.as_ref().unwrap();
    let quotes: Vec<Value> = batch
        .event_ids
        .iter()
        .filter_map(|id| {
            w.contents()
                .reading_result(&s.actor_id, *id)
                .ok()
                .map(|r| json!({"event_id":id,"text":r.content.text}))
        })
        .take(8)
        .collect();
    let value = json!({
        "through_event": batch.through,
        "summary": "我读到了两次公告，开放安排随日期变化，需保留时间范围。",
        "notes": [{
            "path": "places/library.md", "title": "图书馆开放安排", "text": text,
            "event_ids": batch.event_ids, "status": "candidate", "reading_quotes": quotes,
        }],
    });
    apply_reflection(w, s, serde_json::from_value(value).unwrap()).unwrap();
}

fn populated() -> (World, ResidentRuntime) {
    let (w, r) = prepared();
    let mut state = r.state().clone();
    let s = state.sessions.get_mut("r1").unwrap();
    reflect(&w, s, "独有旧主题：图书馆的开放安排需结合日期");
    context::compact(s, 0).unwrap();
    let restored = ResidentRuntime::restore(state, &w).unwrap();
    (w, restored)
}
fn checkpoint(store: &mut SaveStore, w: &World, r: &ResidentRuntime) {
    store
        .checkpoint_bundle(w, 0.0, &Default::default(), None, Some(r.state()), true)
        .unwrap();
}

#[test]
fn context_sources_restore_from_committed_files_and_http_overflow_is_classified_before_clipping() {
    use agent::{completion::ModelError, context::input::ReadSource};
    use std::io::{Read, Write};
    use std::net::TcpListener;
    let d = Scratch::new();
    let (w, r) = prepared();
    let original = json!({"text":"完整来源。".repeat(2_000)});
    let mut state = r.state().clone();
    let s = state.sessions.get_mut("r1").unwrap();
    let source = s.input.source(&original);
    s.input.ceiling = Some(20_000);
    s.input.rejections = 1;
    let r = ResidentRuntime::restore(state, &w).unwrap();
    let mut store = d.store();
    checkpoint(&mut store, &w, &r);
    let disk: Value = serde_json::from_slice(&fs::read(d.save()).unwrap()).unwrap();
    assert!(!disk.to_string().contains(&"完整来源。".repeat(2)));
    assert!(d
        .dir
        .join(format!("residents/r1/.state/context/S{source:06}.json"))
        .is_file());
    drop(store);
    let mut restored_world = world();
    let saved = d
        .store()
        .restore_bundle(&mut restored_world)
        .unwrap()
        .unwrap()
        .agent
        .unwrap();
    let mut r = ResidentRuntime::restore(saved.runtime, &restored_world).unwrap();
    let s = r.session("r1").unwrap();
    assert_eq!(s.input.sources[&source], original);
    assert_eq!(s.input.ceiling, Some(20_000));
    let page = s
        .input
        .read(ReadSource {
            source,
            pointer: "/text".into(),
            offset: 1_000,
            limit: 1_000,
        })
        .unwrap();
    assert_eq!(page["next_offset"], 2_000);
    let request = r.poll(&mut restored_world, true).remove(0);
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let server = std::thread::spawn(move || {
        for context_error in [true, false] {
            let (mut socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(std::time::Duration::from_secs(5)))
                .unwrap();
            let mut bytes = Vec::new();
            let mut block = [0; 4_096];
            loop {
                let n = socket.read(&mut block).unwrap();
                assert!(n > 0);
                bytes.extend_from_slice(&block[..n]);
                if let Some(end) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
                    let headers = String::from_utf8_lossy(&bytes[..end]);
                    let length: usize = headers
                        .lines()
                        .find_map(|line| {
                            line.to_ascii_lowercase()
                                .strip_prefix("content-length:")
                                .map(|v| v.trim().parse().unwrap())
                        })
                        .unwrap();
                    if bytes.len() >= end + 4 + length {
                        break;
                    }
                }
            }
            // code 在显示文案的 200 字符之外，分类必须发生在截短之前。
            let code = if context_error {
                "context_length_exceeded"
            } else {
                "model_not_found"
            };
            let body = format!(
                "{{\"error\":{{\"message\":\"{}\",\"code\":\"{code}\"}}}}",
                "x".repeat(600)
            );
            write!(socket, "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
        }
    });
    let target = host::llm::LlmTarget {
        provider: "fixture".into(),
        model: "fixture".into(),
        base_url: format!("http://{addr}"),
        api_key: None,
    };
    let error = host::agent_worker::complete(&target, &request).unwrap_err();
    assert!(matches!(
        error,
        ModelError::ContextWindowExceeded { status: 400, .. }
    ));
    let ordinary = host::agent_worker::complete(&target, &request).unwrap_err();
    assert!(matches!(ordinary, ModelError::Http { status: 400, .. }));
    server.join().unwrap();
}

/// 存档提交失败：world.json 不动，没提交成的历史只是挂在流水文件的尾巴上；再读档，世界和记忆
/// 都停在上次提交的地方，尾巴截掉，损坏的可读文件按清单重建。接着过，新的经历接着往流水后面写。
#[test]
fn failed_world_commit_cannot_bring_the_future_back_and_restore_repairs_projection() {
    let d = Scratch::new();
    let (mut w, r) = populated();
    let mut store = d.store();
    checkpoint(&mut store, &w, &r);
    let committed = fs::read(d.save()).unwrap();
    let before = json!(w.snapshot());
    let journal = d.dir.join("history/000001.jsonl");
    let written = fs::read(&journal).unwrap();
    let page = d.dir.join("residents/r1/places/library.md");
    let original = fs::read(&page).unwrap();
    // world.json 只留当前状态：事件和记忆记录在流水里
    let disk: Value = serde_json::from_slice(&committed).unwrap();
    assert_eq!(
        disk["world"]["actors"]["r1"]["journal"]["events"],
        json!([])
    );
    let memory = &disk["resident_agent"]["runtime"]["sessions"]["r1"]["memory"];
    assert_eq!(memory["records"], json!([]));
    let lines = String::from_utf8_lossy(&written).into_owned();
    assert!(lines.contains("{\"event\":{\"actor\":\"r1\"") && lines.contains("{\"memory\":"));

    fs::create_dir(d.dir.join("world.json.tmp")).unwrap();
    read_board(&mut w, "r1", "future", "这是尚未提交的未来经历。");
    let mut state = r.state().clone();
    state
        .sessions
        .get_mut("r1")
        .unwrap()
        .memory
        .consolidate(&w, "r1");
    let future = ResidentRuntime::restore(state, &w).unwrap();
    let failed = store.checkpoint_bundle(
        &w,
        0.0,
        &Default::default(),
        None,
        Some(future.state()),
        true,
    );
    assert!(failed.is_err());
    assert_eq!(fs::read(d.save()).unwrap(), committed);
    let tail = fs::read(&journal).unwrap();
    assert!(tail.len() > written.len() && tail.starts_with(&written));
    drop(store);

    fs::remove_dir(d.dir.join("world.json.tmp")).unwrap();
    fs::write(&page, "投影损坏").unwrap();
    let mut store = d.store();
    let mut restored = world();
    let saved = store.restore_bundle(&mut restored).unwrap().unwrap().agent;
    assert_eq!(json!(restored.snapshot()), before);
    assert_eq!(json!(saved.as_ref().unwrap().runtime), json!(r.state()));
    assert_eq!(fs::read(&page).unwrap(), original);
    assert_eq!(fs::read(&journal).unwrap(), written);
    for p in fs::read_dir(d.dir.join("residents/.objects")).unwrap() {
        assert!(!fs::read_to_string(p.unwrap().path())
            .unwrap()
            .contains("尚未提交的未来经历"));
    }

    let r = ResidentRuntime::restore(saved.unwrap().runtime, &restored).unwrap();
    read_board(&mut restored, "r1", "later", "后来真的发生的事。");
    checkpoint(&mut store, &restored, &r);
    let grown = fs::read(&journal).unwrap();
    assert!(grown.len() > written.len() && grown.starts_with(&written));
    assert!(!String::from_utf8_lossy(&grown).contains("尚未提交的未来经历"));
    drop(store);
    let mut again = world();
    d.store().restore_bundle(&mut again).unwrap().unwrap();
    assert_eq!(json!(again.snapshot()), json!(restored.snapshot()));
}

#[cfg(unix)]
#[test]
fn resident_projection_cannot_escape_through_a_symlink() {
    let d = Scratch::new();
    let (w, r) = populated();
    let mut store = d.store();
    checkpoint(&mut store, &w, &r);
    drop(store);
    let outside = d.dir.join("outside");
    fs::create_dir(&outside).unwrap();
    fs::write(outside.join("library.md"), "不得覆盖").unwrap();
    fs::remove_dir_all(d.dir.join("residents/r1/places")).unwrap();
    std::os::unix::fs::symlink(&outside, d.dir.join("residents/r1/places")).unwrap();
    assert!(d.store().restore_bundle(&mut world()).is_err());
    assert_eq!(
        fs::read_to_string(outside.join("library.md")).unwrap(),
        "不得覆盖"
    );
}

/// 可读目录写不成不算存盘失败：世界、流水和记忆文件照样提交，下一次检查点把欠着的补上。
#[test]
fn committed_world_survives_readable_projection_failure_and_repairs_on_retry() {
    let d = Scratch::new();
    let (mut w, r) = populated();
    let mut store = d.store();
    checkpoint(&mut store, &w, &r);
    // 下一份上下文来源的可读文件被一个目录占住
    let mut state = r.state().clone();
    let session = state.sessions.get_mut("r1").unwrap();
    let source = session.input.source(&json!({"text":"后来才有的来源"}));
    let path = format!(".state/context/S{source:06}.json");
    let projection = d.dir.join("residents/r1").join(&path);
    fs::create_dir_all(&projection).unwrap();
    let r = ResidentRuntime::restore(state, &w).unwrap();
    read_board(&mut w, "r1", "committed", "这条经历必须随世界保存。");
    checkpoint(&mut store, &w, &r);
    // 上下文来源写过就不再变：它的清单条目记在流水里，不在 world.json
    let saved: Value = serde_json::from_slice(&fs::read(d.save()).unwrap()).unwrap();
    assert!(saved["resident_files"]["r1"].get(&path).is_none());
    let journal = fs::read_to_string(d.dir.join("history/000001.jsonl")).unwrap();
    let entry = journal
        .lines()
        .map(|line| serde_json::from_str::<Value>(line).unwrap())
        .find(|line| line["file"]["path"] == path.as_str())
        .unwrap();
    let hash = entry["file"]["version"]["hash"].as_str().unwrap();
    assert!(projection.is_dir());
    fs::remove_dir(&projection).unwrap();
    checkpoint(&mut store, &w, &r);
    assert_eq!(
        fs::read(projection).unwrap(),
        fs::read(d.dir.join("residents/.objects").join(hash)).unwrap()
    );
    drop(store);
    let mut restored = world();
    let agent = d
        .store()
        .restore_bundle(&mut restored)
        .unwrap()
        .unwrap()
        .agent;
    assert_eq!(json!(restored.snapshot()), json!(w.snapshot()));
    assert_eq!(json!(agent.unwrap().runtime), json!(r.state()));
}

/// 夹具 save-v5 是 0.5.0 的世界进程写的存档（v5：全部历史都在 world.json 和记忆文件里），
/// 连同存它时的拓扑。新版本打开它：原档留一份备份；第一次存盘把历史搬进流水，world.json 只剩
/// 当前状态；再读回来，世界和会话都和搬之前一字不差。
#[test]
fn a_v5_save_moves_its_history_into_the_journal_and_keeps_the_original() {
    let fixture = crate::support::fixture("save-v5");
    let town = || {
        let topology = fs::read_to_string(fixture.join("topology.json")).unwrap();
        World::new(
            Topology::from_json(&topology, &kernel::props::Catalog::default()).unwrap(),
            420.0,
            crate::support::need_rules(),
        )
    };
    let d = Scratch::new();
    let objects = "residents/.objects";
    fs::create_dir_all(d.dir.join(objects)).unwrap();
    for entry in fs::read_dir(fixture.join(objects)).unwrap() {
        let path = entry.unwrap().path();
        fs::copy(&path, d.dir.join(objects).join(path.file_name().unwrap())).unwrap();
    }
    let original = fs::read(fixture.join("world.json")).unwrap();
    fs::write(d.save(), &original).unwrap();
    let old: Value = serde_json::from_slice(&original).unwrap();
    assert_eq!(old["schema_version"], 5);

    let mut store = d.store();
    let mut w = town();
    let restored = store.restore_bundle(&mut w).unwrap().unwrap();
    assert_eq!(json!(w.snapshot()), old["world"]);
    // 读档不改原档；原档和它引用的记忆文件另留一份，旧版本用它还能打开
    assert_eq!(fs::read(d.save()).unwrap(), original);
    let backup = d.dir.join("world.json.before-history-v1");
    assert_eq!(fs::read(backup.join("world.json")).unwrap(), original);
    for version in old["resident_files"]["r1"].as_object().unwrap().values() {
        let name = version["hash"].as_str().unwrap();
        assert_eq!(
            fs::read(backup.join(objects).join(name)).unwrap(),
            fs::read(fixture.join(objects).join(name)).unwrap()
        );
    }

    let r = ResidentRuntime::restore(restored.agent.unwrap().runtime, &w).unwrap();
    checkpoint(&mut store, &w, &r);
    let new: Value = serde_json::from_slice(&fs::read(d.save()).unwrap()).unwrap();
    assert_eq!(new["schema_version"], 6);
    for actor in ["r1", "r2"] {
        let a = &new["world"]["actors"][actor];
        assert_eq!(a["journal"]["events"], json!([]));
        assert_eq!(a["journal"]["days"], json!([]));
        assert_eq!(a["actions"]["groups"], json!({}));
    }
    assert_eq!(new["world"]["interactions"], json!({}));
    let memory = &new["resident_agent"]["runtime"]["sessions"]["r1"]["memory"];
    assert_eq!(memory["records"], json!([]));
    // 事件和记忆记录不再是记忆目录里的整份文件；world.json 的清单只列会反复改写的文件，
    // 折叠归档这类写过就不再变的，文件还在记忆目录里，清单条目在流水里
    let files = new["resident_files"]["r1"].as_object().unwrap();
    let listed: Vec<_> = files.keys().map(String::as_str).collect();
    assert!(listed.contains(&"places/library.md") && listed.contains(&"INDEX.md"));
    let moved = ["events/", ".state/records/", "conversations/"];
    assert!(!listed
        .iter()
        .any(|path| moved.iter().any(|folder| path.starts_with(folder))));
    assert!(!d.dir.join("residents/r1/events").exists());
    assert!(d
        .dir
        .join("residents/r1/conversations/C000001.jsonl")
        .is_file());
    let journal = fs::read_to_string(d.dir.join("history/000001.jsonl")).unwrap();
    for kind in ["event", "day", "actions", "interaction", "memory", "file"] {
        assert!(
            journal.contains(&format!("{{\"{kind}\":")),
            "流水里没有 {kind}"
        );
    }
    drop(store);

    let mut again = town();
    let saved = d.store().restore_bundle(&mut again).unwrap().unwrap().agent;
    assert_eq!(json!(again.snapshot()), old["world"]);
    assert_eq!(json!(saved.unwrap().runtime), json!(r.state()));
}
