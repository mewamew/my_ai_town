//! 按需启动的世界进程：一个小镇一个 host。
use crate::error::ApiError;
use crate::storage::{read_json, Storage};
use crate::ws;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::Mutex;
use std::time::{Duration, Instant};

const START_TIMEOUT: Duration = Duration::from_secs(20);
const CLOSE_TIMEOUT: Duration = Duration::from_secs(15);

struct Record {
    child: Child,
    /// 只握着不写：本进程无论怎样退出，管道关闭，host 读到 EOF 后保存并退出。Windows 上关小镇也靠它。
    #[cfg_attr(unix, allow(dead_code))]
    stdin: Option<ChildStdin>,
    endpoint: String,
    /// 最近一次有人进这个小镇的时间：跑满了先关最久没进过的
    used: Instant,
    /// 最近一次打开的凭证：每次打开都换一个，关闭时拿它核对，刷新后旧页面晚到的关闭就不算数
    lease: String,
}

pub struct Hosts {
    pub host_bin: PathBuf,
    /// 世界进程的工作目录（应用自带数据）。
    pub app: PathBuf,
    /// 写好绝对路径的应用配置。
    pub config: PathBuf,
    pub max_running: usize,
    pub mock_llm: bool,
    running: Mutex<HashMap<String, Record>>,
}

fn alive(child: &mut Child) -> bool {
    matches!(child.try_wait(), Ok(None))
}

impl Hosts {
    pub fn new(
        host_bin: PathBuf,
        app: PathBuf,
        config: PathBuf,
        max_running: usize,
        mock_llm: bool,
    ) -> Self {
        Self {
            host_bin,
            app,
            config,
            max_running,
            mock_llm,
            running: Mutex::new(HashMap::new()),
        }
    }

    pub fn is_running(&self, id: &str) -> bool {
        let mut running = self.running.lock().unwrap();
        let alive = running.get_mut(id).map(|record| alive(&mut record.child));
        if alive == Some(false) {
            running.remove(id);
        }
        alive == Some(true)
    }

    /// 同时运行的小镇已经跑满（不算已经退出的）
    pub fn full(&self) -> bool {
        let mut running = self.running.lock().unwrap();
        running.retain(|_, record| alive(&mut record.child));
        running.len() >= self.max_running
    }

    /// 除了 except 之外最久没人进过的运行中小镇
    pub fn least_recent(&self, except: &str) -> Option<String> {
        let running = self.running.lock().unwrap();
        running
            .iter()
            .filter(|(id, _)| id.as_str() != except)
            .min_by_key(|(_, record)| record.used)
            .map(|(id, _)| id.clone())
    }

    /// 打开小镇：已在运行就核对身份后直接返回，否则启动 host 并等它写就绪文件。
    /// 同一小镇的开关由调用方串行；跑满时由调用方先腾出位置。
    pub fn open(&self, storage: &Storage, id: &str) -> Result<Value, ApiError> {
        let map = storage.map(id)?;
        let existing = self.is_running(id).then(|| self.endpoint(id)).flatten();
        if let Some(endpoint) = existing {
            let lease = crate::token();
            if let Some(record) = self.running.lock().unwrap().get_mut(id) {
                record.used = Instant::now();
                record.lease = lease.clone();
            }
            verify(&endpoint, id, &map.hash)?;
            return info(storage, id, &map.document, &map.hash, &endpoint, &lease);
        }
        if self.running.lock().unwrap().len() >= self.max_running {
            return Err(ApiError::bad(format!(
                "同时运行的小镇已达 {} 个，请关闭其他小镇",
                self.max_running
            )));
        }
        let dir = storage.town(id)?;
        let ready = dir.join("host-ready.json");
        let token = crate::token();
        let lease = crate::token();
        let _ = fs::remove_file(&ready);
        let log = OpenOptions::new()
            .create(true)
            .append(true)
            .open(dir.join("host.log"))?;
        let mut command = Command::new(&self.host_bin);
        command
            .arg("--map-document")
            .arg(dir.join("map.json"))
            .args(["--town-id", id, "--port", "0", "--speed", "0"])
            .arg("--save-file")
            .arg(dir.join("world.json"))
            .arg("--ready-file")
            .arg(&ready)
            .args(["--connection-token", &token, "--stop-on-stdin-close"]);
        if self.mock_llm {
            command.args(["--mock-llm", "--mock-delay", "0.01"]);
        }
        let mut child = host::process::no_console(&mut command)
            .current_dir(&self.app)
            .env("AI_TOWN_CONFIG", &self.config)
            .env("AI_TOWN_LOG_DIR", dir.join("logs"))
            .stdin(Stdio::piped())
            .stdout(log.try_clone()?)
            .stderr(log)
            .spawn()?;
        let stdin = child.stdin.take();
        let pid = child.id();
        let deadline = Instant::now() + START_TIMEOUT;
        let endpoint = loop {
            if !alive(&mut child) {
                return Err(ApiError::bad("世界启动失败，请查看该小镇的 host.log"));
            }
            if Instant::now() > deadline {
                let _ = child.kill();
                let _ = child.wait();
                return Err(ApiError::bad("世界启动超时"));
            }
            if let Ok(result) = read_json(&ready) {
                let identity = &result["identity"];
                if result["pid"] == pid
                    && identity["town_id"] == id
                    && identity["map_hash"] == map.hash.as_str()
                {
                    if let Some(port) = result["port"].as_u64() {
                        break format!("ws://127.0.0.1:{port}/?session={token}");
                    }
                }
            }
            std::thread::sleep(Duration::from_millis(80));
        };
        self.running.lock().unwrap().insert(
            id.to_owned(),
            Record {
                child,
                stdin,
                endpoint: endpoint.clone(),
                used: Instant::now(),
                lease: lease.clone(),
            },
        );
        let opened = verify(&endpoint, id, &map.hash)
            .and_then(|_| info(storage, id, &map.document, &map.hash, &endpoint, &lease));
        if opened.is_err() {
            let _ = self.close(id);
        }
        opened
    }

    /// 这次打开的凭证还是不是最新的
    pub fn holds(&self, id: &str, lease: &str) -> bool {
        self.running
            .lock()
            .unwrap()
            .get(id)
            .is_some_and(|r| r.lease == lease)
    }

    fn endpoint(&self, id: &str) -> Option<String> {
        self.running
            .lock()
            .unwrap()
            .get(id)
            .map(|r| r.endpoint.clone())
    }

    /// 先让 host 保存后退出（见 terminate）；超时则强制结束并报错，让调用方知道保存可能不完整。
    pub fn close(&self, id: &str) -> Result<(), ApiError> {
        let Some(mut record) = self.running.lock().unwrap().remove(id) else {
            return Ok(());
        };
        if !alive(&mut record.child) {
            return Ok(());
        }
        terminate(&mut record);
        let deadline = Instant::now() + CLOSE_TIMEOUT;
        while Instant::now() < deadline {
            if !alive(&mut record.child) {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        let _ = record.child.kill();
        let _ = record.child.wait();
        Err(ApiError::bad(format!(
            "世界在 {} 秒内没有完成保存，已强制结束",
            CLOSE_TIMEOUT.as_secs()
        )))
    }

    pub fn ids(&self) -> Vec<String> {
        self.running.lock().unwrap().keys().cloned().collect()
    }
}

/// 让 host 保存后退出：unix 上发 SIGTERM；Windows 没有这个信号，关掉它的标准输入，效果一样。
#[cfg(unix)]
fn terminate(record: &mut Record) {
    unsafe {
        libc::kill(record.child.id() as libc::pid_t, libc::SIGTERM);
    }
}

#[cfg(not(unix))]
fn terminate(record: &mut Record) {
    record.stdin.take();
}

fn verify(endpoint: &str, id: &str, hash: &str) -> Result<(), ApiError> {
    let identity = ws::query(endpoint, None, |m| m["type"] == "world_identity")?;
    if identity["town_id"] != id || identity["map_hash"] != hash {
        return Err(ApiError::bad("世界与地图身份不一致"));
    }
    Ok(())
}

fn info(
    storage: &Storage,
    id: &str,
    document: &Value,
    hash: &str,
    endpoint: &str,
    lease: &str,
) -> Result<Value, ApiError> {
    let settings = ws::query(
        endpoint,
        Some(&json!({ "type": "get_world_settings" })),
        |m| m["type"] == "world_settings",
    )?;
    let (name, description, creation) = storage.labels(id, document);
    Ok(json!({
        "id": id,
        "name": name,
        "description": description,
        "creation": creation,
        "version": "1",
        "clientKind": "town-2d",
        "views": ["2d"],
        "available": true,
        "mapHash": hash,
        "worldId": settings["state"]["world_id"],
        "endpoint": endpoint,
        "lease": lease,
    }))
}
