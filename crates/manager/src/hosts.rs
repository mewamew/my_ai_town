//! 按需启动的世界进程：一个小镇一个 host。
use crate::error::ApiError;
use crate::storage::{read_json, Storage};
use crate::ws;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::Mutex;
use std::time::{Duration, Instant};

const START_TIMEOUT: Duration = Duration::from_secs(20);
const CLOSE_TIMEOUT: Duration = Duration::from_secs(15);

struct Record {
    child: Child,
    /// 只握着不写：只有管理服务真正退出才关闭，API 关闭/切镇失败必须保留父子关系。
    _stdin: Option<ChildStdin>,
    shutdown_port: u16,
    shutdown_token: String,
    closing: Option<Closing>,
    endpoint: String,
    /// 最近一次有人进这个小镇的时间：跑满了先关最久没进过的
    used: Instant,
    /// 最近一次打开的凭证：每次打开都换一个，关闭时拿它核对，刷新后旧页面晚到的关闭就不算数
    lease: String,
}

struct Closing {
    stream: TcpStream,
    saved: bool,
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
        // 已退出的记录保留到显式重开：列表查询不能吞掉异常退出，让稍后的 close 伪报成功。
        running
            .get_mut(id)
            .is_some_and(|record| alive(&mut record.child))
    }

    /// 同时运行的小镇已经跑满（不算已经退出的）
    pub fn full(&self) -> bool {
        let mut running = self.running.lock().unwrap();
        running
            .values_mut()
            .map(|record| alive(&mut record.child))
            .filter(|alive| *alive)
            .count()
            >= self.max_running
    }

    /// 除了 except 之外最久没人进过的运行中小镇
    pub fn least_recent(&self, except: &str) -> Option<String> {
        let mut running = self.running.lock().unwrap();
        running
            .iter_mut()
            .filter_map(|(id, record)| {
                (id.as_str() != except && alive(&mut record.child)).then_some((id, record))
            })
            .min_by_key(|(_, record)| record.used)
            .map(|(id, _)| id.clone())
    }

    /// 打开小镇：已在运行就核对身份后直接返回，否则启动 host 并等它写就绪文件。
    /// 调用方把各次打开排成一个接一个（App::opening），正在启动的小镇不在 running 里，
    /// 并排着启动的话这里的名额检查拦不住；同一小镇的开关也由调用方串行，跑满时由调用方先腾出位置。
    pub fn open(&self, storage: &Storage, id: &str) -> Result<Value, ApiError> {
        let map = storage.map(id)?;
        let existing = self.is_running(id).then(|| self.endpoint(id)).flatten();
        if let Some(endpoint) = existing {
            let lease = crate::token();
            if let Some(record) = self.running.lock().unwrap().get_mut(id) {
                if record.closing.is_some() {
                    return Err(ApiError::bad("世界仍在保存关闭，请稍后重试关闭"));
                }
                record.used = Instant::now();
                record.lease = lease.clone();
            }
            verify(&endpoint, id, &map.hash)?;
            return info(storage, id, &map.document, &map.hash, &endpoint, &lease);
        }
        if self.full() {
            return Err(ApiError::bad(format!(
                "同时运行的小镇已达 {} 个，请关闭其他小镇",
                self.max_running
            )));
        }
        let dir = storage.town(id)?;
        let ready = dir.join("host-ready.json");
        let token = crate::token();
        let shutdown_token = crate::token();
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
            .args([
                "--connection-token",
                &token,
                "--shutdown-token",
                &shutdown_token,
                "--stop-on-stdin-close",
            ]);
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
        let (endpoint, shutdown_port) = loop {
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
                    if let (Some(port), Some(shutdown_port)) =
                        (result["port"].as_u64(), result["shutdown_port"].as_u64())
                    {
                        if let Ok(shutdown_port) = u16::try_from(shutdown_port) {
                            break (
                                format!("ws://127.0.0.1:{port}/?session={token}"),
                                shutdown_port,
                            );
                        }
                    }
                }
            }
            std::thread::sleep(Duration::from_millis(80));
        };
        self.running.lock().unwrap().insert(
            id.to_owned(),
            Record {
                child,
                _stdin: stdin,
                shutdown_port,
                shutdown_token,
                closing: None,
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

    /// 仅「本次最终存档已确认」并且「正常退出」才算关闭成功。等待期间保留登记、stdin 和
    /// 控制连接；超时只报错，不杀世界，后续 close 继续等同一次请求，不能把晚到的回执误配给新请求。
    pub fn close(&self, id: &str) -> Result<(), ApiError> {
        let deadline = Instant::now() + CLOSE_TIMEOUT;
        loop {
            let mut running = self.running.lock().unwrap();
            let Some(record) = running.get_mut(id) else {
                return Ok(());
            };
            if record.closing.is_none() {
                if record.child.try_wait()?.is_some() {
                    return Err(ApiError::bad(
                        "世界已意外退出，无法确认最后进度已保存，请查看该小镇的 host.log",
                    ));
                }
                let stream = host::shutdown::request(record.shutdown_port, &record.shutdown_token)
                    .map_err(|e| {
                        eprintln!("[town-manager] 请求关闭 {id} 失败：{e}");
                        ApiError::bad("无法请求世界保存关闭，未强制结束，请重试")
                    })?;
                record.closing = Some(Closing {
                    stream,
                    saved: false,
                });
            }
            let closing = record.closing.as_mut().unwrap();
            if !closing.saved {
                match host::shutdown::receive(&mut closing.stream) {
                    Ok(Some(true)) => closing.saved = true,
                    Ok(Some(false)) => {
                        record.closing = None;
                        return Err(ApiError::bad("保存失败，世界仍在运行，最新进度保留在内存中；请修复存储问题后重试关闭"));
                    }
                    Ok(None) => {}
                    Err(e) => {
                        eprintln!("[town-manager] 关闭 {id} 未收到保存确认：{e}");
                        record.closing = None;
                        return Err(ApiError::bad("关闭未收到保存确认，世界可能意外退出；未强制结束，请重试或查看 host.log"));
                    }
                }
            }
            if let Some(status) = record.child.try_wait()? {
                if closing.saved && status.success() {
                    running.remove(id);
                    return Ok(());
                }
                return Err(ApiError::bad(format!(
                    "世界异常退出（{status}），无法确认完整关闭，请查看该小镇的 host.log"
                )));
            }
            if Instant::now() >= deadline {
                return Err(ApiError::bad(format!(
                    "世界在 {} 秒内未确认保存并退出；仍保留世界进程，请勿退出应用，稍后重试关闭",
                    CLOSE_TIMEOUT.as_secs()
                )));
            }
            drop(running);
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    pub fn ids(&self) -> Vec<String> {
        self.running.lock().unwrap().keys().cloned().collect()
    }
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
