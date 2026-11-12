//! 隔离小镇夹具：临时目录 + 正式 host（缺省固定回复模型），可停可重启，存档在目录内的 state/。
//! 地图、道具库与村民库都用 tests/fixtures 下的夹具；需求规则与天气规则是应用配置，读仓库里的
//! config/。不读取或写入用户存档，不调用外部模型。
use protocol::NeedRules;
use serde_json::{json, Value};
use std::{
    fs,
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Child, ChildStdin, Command, ExitStatus, Stdio},
    time::{Duration, Instant},
};
use tungstenite::{Message, WebSocket};

pub const WAIT: Duration = Duration::from_secs(8);

/// 起子进程时串行：并行的用例会选到同一个临时端口；子进程创建时还会短暂继承本进程打开的文件，
/// 在进程内开关存档锁的用例要拿着它，否则刚关掉的锁可能还挂在子进程上。
static SPAWN: std::sync::Mutex<()> = std::sync::Mutex::new(());

pub fn hold_spawns() -> std::sync::MutexGuard<'static, ()> {
    SPAWN.lock().unwrap_or_else(|e| e.into_inner())
}

/// 夹具小镇在测试目录里的地图文件：二维（门口、广场、三处住宅）。
/// 用 `map_args` 传给 host 时编译出行走地图；不传时 host 只拿裸拓扑，没有行走地图和天气。
pub const MAP_2D: &str = "map-2d.json";

pub struct Town {
    pub dir: PathBuf,
    /// 起进程并连上后是否自动设置世界观。
    pub setup: bool,
    /// 固定回复模型的延迟秒数；None 表示用配置里的模型端点（测试用本地 HTTP 夹具）。
    pub mock_delay: Option<String>,
    /// false 时以 --no-save 启动。
    pub persistent: bool,
    /// 起进程的额外参数。
    pub args: Vec<String>,
    child: Option<Child>,
    stdin: Option<ChildStdin>,
}

pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

pub fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name)
}

pub fn read_json(path: &Path) -> Value {
    serde_json::from_slice(&fs::read(path).unwrap()).unwrap()
}

/// 需求参数的合法范围：与 host 启动时读的是同一份配置。
pub fn need_rules() -> NeedRules {
    let path = repo_root().join("config/needs_rules.json");
    NeedRules::parse(&fs::read_to_string(path).expect("需求规则文件应存在")).unwrap()
}

/// 以 `--map-document` 启动时的参数。
pub fn map_args(map: &str) -> Vec<String> {
    vec!["--map-document".into(), map.into()]
}

fn scratch_dir() -> PathBuf {
    // 系统时间只有微秒精度，并行用例可能同一微秒开始，目录名再加一个进程内序号。
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let dir = std::env::temp_dir().join(format!(
        "town-host-test-{}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

impl Town {
    /// 夹具小镇与三份村民模板（tpl_a 阿甲、tpl_b 阿乙、tpl_c 阿丙）；新世界一律空村，居民都从村民库加入。
    pub fn new() -> Self {
        let town = Self::empty();
        let mut doc = read_json(&fixture("town-2d.json"));
        doc["content_hash"] = json!(host::maps::hash(&doc));
        town.write(MAP_2D, doc);
        town.write(
            "topology.json",
            read_json(&town.dir.join(MAP_2D))["topology"].clone(),
        );
        fs::create_dir_all(town.dir.join("library")).unwrap();
        for entry in fs::read_dir(fixture("library")).unwrap() {
            let path = entry.unwrap().path();
            fs::copy(
                &path,
                town.dir.join("library").join(path.file_name().unwrap()),
            )
            .unwrap();
        }
        town.configure("topology.json");
        town
    }

    /// 只有规则配置与夹具道具库；调用方用 `configure` 写应用配置，并自己放拓扑。
    pub fn empty() -> Self {
        let dir = scratch_dir();
        for file in ["config/needs_rules.json", "config/weather_rules.json"] {
            fs::create_dir_all(dir.join(file).parent().unwrap()).unwrap();
            fs::copy(repo_root().join(file), dir.join(file)).unwrap();
        }
        fs::copy(fixture("props.json"), dir.join("props.json")).unwrap();
        fs::write(dir.join("retired-props.json"), "[]").unwrap();
        Self {
            dir,
            setup: true,
            mock_delay: Some("0.01".into()),
            persistent: true,
            args: Vec::new(),
            child: None,
            stdin: None,
        }
    }

    /// 应用配置：道具库与村民库指向目录里的夹具，拓扑文件由调用方给。
    pub fn configure(&self, topology: &str) {
        self.write(
            "config/application.json",
            json!({
                "port":0,"topology_path":topology,
                "prop_catalog_path":"props.json","legacy_prop_catalog_path":"retired-props.json",
                "resident_library_path":"library",
                "providers_path":"config/providers.json","credentials_path":"config/credentials.json"
            }),
        );
    }

    /// 自定义村民库指向几个小镇共用的目录，和管理服务开镇时一样。
    pub fn share_library(&self, dir: &Path) {
        let mut config = read_json(&self.dir.join("config/application.json"));
        config["custom_library_path"] = json!(dir);
        self.write("config/application.json", config);
    }

    pub fn write(&self, relative: &str, value: Value) {
        let path = self.dir.join(relative);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, serde_json::to_string_pretty(&value).unwrap()).unwrap();
    }

    pub fn save(&self) -> PathBuf {
        self.dir.join("state/world.json")
    }

    #[track_caller]
    pub fn start(&mut self) -> WebSocket<TcpStream> {
        self.try_start().unwrap_or_else(|e| panic!("{e}"))
    }

    /// 起进程并连上；进程在监听前退出时返回错误（启动阶段拒绝的用例用）。
    pub fn try_start(&mut self) -> Result<WebSocket<TcpStream>, String> {
        // 选端口、启动、连上这一段串行。
        let _serial = hold_spawns();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let mut command = Command::new(env!("CARGO_BIN_EXE_host"));
        command
            .current_dir(&self.dir)
            .args(["--speed", "0", "--port", &port.to_string()])
            .args(&self.args)
            .env("AI_TOWN_HOME", self.dir.join("state"))
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::inherit());
        // Windows 没有 SIGTERM；夹具和桌面管理服务一样，关闭管道后等待 host 保存退出。
        #[cfg(windows)]
        command.arg("--stop-on-stdin-close");
        if let Some(delay) = &self.mock_delay {
            command.args(["--mock-llm", "--mock-delay", delay]);
        }
        if !self.persistent {
            command.arg("--no-save");
        }
        let mut child = command.spawn().unwrap();
        self.stdin = child.stdin.take();
        self.child = Some(child);
        let deadline = Instant::now() + WAIT;
        loop {
            if let Ok(stream) = TcpStream::connect(("127.0.0.1", port)) {
                stream.set_read_timeout(Some(WAIT)).unwrap();
                let (mut ws, _) =
                    tungstenite::client(format!("ws://127.0.0.1:{port}"), stream).unwrap();
                if self.setup {
                    configure_world(&mut ws);
                }
                return Ok(ws);
            }
            if let Some(status) = self.child.as_mut().unwrap().try_wait().unwrap() {
                return Err(format!("host 在监听前退出：{status}"));
            }
            if Instant::now() >= deadline {
                return Err("host 未监听".into());
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    pub fn kill(&mut self) {
        self.stdin = None;
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }

    /// 关掉子进程 stdin 的写端：模拟管理进程消失。
    pub fn close_stdin(&mut self) {
        self.stdin = None;
    }

    /// 等进程自行退出。
    #[track_caller]
    pub fn wait_exit(&mut self) -> ExitStatus {
        let child = self.child.as_mut().expect("进程未启动");
        let deadline = Instant::now() + WAIT;
        loop {
            if let Some(status) = child.try_wait().unwrap() {
                self.child = None;
                return status;
            }
            assert!(Instant::now() < deadline, "进程没有在限定时间内退出");
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    /// SIGTERM 后必须完成保存并正常退出。
    #[cfg(unix)]
    #[track_caller]
    pub fn shutdown(&mut self) {
        let pid = self.child.as_ref().expect("进程未启动").id() as i32;
        assert_eq!(unsafe { libc::kill(pid, libc::SIGTERM) }, 0);
        assert!(self.wait_exit().success(), "SIGTERM 后未完成保存退出");
    }

    /// Windows 通过管理管道关闭请求正常退出，不能用强杀代替保存。
    #[cfg(windows)]
    #[track_caller]
    pub fn shutdown(&mut self) {
        self.close_stdin();
        assert!(self.wait_exit().success(), "stdin 关闭后未完成保存退出");
    }

    /// 轮询存档直到满足条件。
    #[track_caller]
    pub fn saved(&self, predicate: impl Fn(&Value) -> bool) -> Value {
        let start = Instant::now();
        loop {
            if let Ok(text) = fs::read_to_string(self.save()) {
                if let Ok(value) = serde_json::from_str(&text) {
                    if predicate(&value) {
                        return value;
                    }
                }
            }
            assert!(
                start.elapsed() < WAIT,
                "未保存预期状态：{}",
                fs::read_to_string(self.save()).unwrap_or_default()
            );
            std::thread::sleep(Duration::from_millis(10));
        }
    }
}

impl Drop for Town {
    fn drop(&mut self) {
        self.kill();
        let _ = fs::remove_dir_all(&self.dir);
    }
}

pub fn send(ws: &mut WebSocket<TcpStream>, command: Value) {
    ws.send(Message::Text(command.to_string())).unwrap();
}

#[track_caller]
pub fn until(ws: &mut WebSocket<TcpStream>, predicate: impl Fn(&Value) -> bool) -> Value {
    received_until(ws, predicate).pop().unwrap()
}

/// 读到满足条件的消息为止，返回读到的全部消息（最后一条满足条件）。
#[track_caller]
pub fn received_until(
    ws: &mut WebSocket<TcpStream>,
    predicate: impl Fn(&Value) -> bool,
) -> Vec<Value> {
    let deadline = Instant::now() + WAIT;
    let mut received = Vec::new();
    loop {
        assert!(Instant::now() < deadline, "未收到预期消息");
        if let Message::Text(text) = ws.read().unwrap() {
            let message: Value = serde_json::from_str(&text).unwrap();
            let done = predicate(&message);
            received.push(message);
            if done {
                return received;
            }
        }
    }
}

/// 同一个小镇再开一条连接（另一个页面）。
pub fn connect_again(ws: &WebSocket<TcpStream>) -> WebSocket<TcpStream> {
    let address = ws.get_ref().peer_addr().unwrap();
    let stream = TcpStream::connect(address).unwrap();
    stream.set_read_timeout(Some(WAIT)).unwrap();
    tungstenite::client(format!("ws://{address}"), stream)
        .unwrap()
        .0
}

#[track_caller]
pub fn reply(ws: &mut WebSocket<TcpStream>, command: Value, kind: &str) -> Value {
    send(ws, command);
    until(ws, |m| m["type"] == kind)
}

/// 消耗页里这位居民的一行：今天的调用数、token、回复数与其中过时的。
#[track_caller]
pub fn usage_of(ws: &mut WebSocket<TcpStream>, id: &str) -> Value {
    reply(ws, json!({"type":"get_usage"}), "usage")["residents"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["id"] == id)
        .expect("消耗页里没有这位居民")
        .clone()
}

/// 读到第 `count` 份名册为止，返回读到的全部消息。
#[track_caller]
pub fn through_rosters(ws: &mut WebSocket<TcpStream>, count: usize) -> Vec<Value> {
    let seen = std::cell::Cell::new(0);
    received_until(ws, |m| {
        seen.set(seen.get() + usize::from(m["type"] == "roster"));
        seen.get() >= count
    })
}

pub fn members(roster: &Value) -> Vec<Value> {
    roster["locales"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|l| {
            let locale = l["locale"].clone();
            l["members"].as_array().unwrap().iter().map(move |m| {
                let mut m = m.clone();
                m["locale"] = locale.clone();
                m
            })
        })
        .collect()
}

/// 一次完整加入：预览拿版本，再按操作编号提交；返回 resident_joined 或 join_result 里的结果。
#[track_caller]
pub fn join(ws: &mut WebSocket<TcpStream>, template_id: &str, name: Option<&str>) -> Value {
    join_as(ws, template_id, name, None)
}

/// 同 `join`，可以带上入住时选的模型（`{"provider":…,"model":…}`）。
#[track_caller]
pub fn join_as(
    ws: &mut WebSocket<TcpStream>,
    template_id: &str,
    name: Option<&str>,
    model: Option<Value>,
) -> Value {
    configure_world(ws);
    let population =
        reply(ws, json!({"type":"get_population"}), "population")["population"].clone();
    let preview = reply(
        ws,
        json!({"type":"preview_resident_join","template_id":template_id,"name":name}),
        "join_preview",
    )["preview"]
        .clone();
    let op_id = format!(
        "op-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let mut command = json!({"type":"join_resident","op_id":op_id,"world_id":population["world_id"],"template_id":template_id,
        "template_version":preview["template_version"],"name":preview["name"],"home":preview["home"]});
    if let Some(model) = model {
        command["model"] = model;
    }
    send(ws, command);
    until(ws, |m| {
        (m["type"] == "resident_joined" || m["type"] == "join_result")
            && m["outcome"]["op_id"] == op_id
    })["outcome"]
        .clone()
}

/// 加入必须成功，返回服务器分配的 id。
#[track_caller]
pub fn join_id(ws: &mut WebSocket<TcpStream>, template_id: &str) -> String {
    let outcome = join(ws, template_id, None);
    assert_eq!(outcome["ok"], true, "{outcome}");
    outcome["resident_id"].as_str().unwrap().to_string()
}

pub fn configure_world(ws: &mut WebSocket<TcpStream>) {
    let state = reply(ws, json!({"type":"get_world_settings"}), "world_settings")["state"].clone();
    if state["ready"] == true {
        return;
    }
    let receipt = reply(
        ws,
        json!({"type":"set_worldview","request_id":"fixture-setup","world_id":state["world_id"],"expected_revision":state["revision"],"text":"这是一个供村民自由生活的世界。"}),
        "world_settings_saved",
    );
    assert_eq!(receipt["ok"], true, "{receipt}");
}
