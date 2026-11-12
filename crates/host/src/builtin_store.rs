//! 内置模型的下载与更新。模型不随应用带：发布在魔搭（application::BUILTIN_SOURCE），应用自己下到用户数据
//! 目录，有新版本时再下。管理服务（crates/manager）直接调这里。
//!
//! 发布处的 manifest.json 列出所有版本（新版本在训练环境里发布，先传模型文件、最后传清单）：
//!   { "models": [ { "date": "2026-10-08", "format": 1, "file": "2026-10-08/model.gguf",
//!                   "size": 529297024, "sha256": "…", "notes": "…" } ] }
//! 游戏只取格式号和自己一样（builtin::FORMAT）的版本里日期最新的；格式号更大、日期更新的只提示要先更新游戏。
//!
//! 目录（Application::builtin_store）里：
//! - model.gguf、installed.json：在用的模型和它是哪一版。
//! - model.gguf.part：下到一半的文件，断了从这里接着下。
//! - download.json：要下哪一版、玩家让它下还是停。只有玩家的操作写它。
//! - progress.json：下载线程的近况和心跳，只有下载线程写。心跳几秒没更新就当下载已经停了（比如应用被关掉）。
//! - latest.json：上次看清单的结果；settings.json：自动更新开没开。
//!
//! 下完先核对大小和 sha256 才换上，对不上就删掉重下。换上是整个文件替换：开着的推理服务还用着旧文件，
//! 重启服务（或者下次开镇）才用上新的，见 builtin::stale。
use crate::{application::Application, builtin, persistence::atomic_write, HostError};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{self, Read, Write},
    path::{Path, PathBuf},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const PART: &str = "model.gguf.part";
const INSTALLED: &str = "installed.json";
const DOWNLOAD: &str = "download.json";
const PROGRESS: &str = "progress.json";
const LATEST: &str = "latest.json";
const SETTINGS: &str = "settings.json";
/// 下载线程每秒写一次心跳，这么久没写就当它已经停了。
const BEAT_STALE_MS: u64 = 5000;
/// 下完之外再留这么多空间，不把设备塞满。
const SPARE: u64 = 64 << 20;
/// 断网后重试的间隔从 1 秒起翻倍，最长一分钟。
const RETRY_MAX: Duration = Duration::from_secs(60);
/// 文件连着几次对不上就不再自动重下，等玩家点重试。
const BAD_FILES: u32 = 2;

/// 清单里的一个版本。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct Version {
    /// 发布日期，玩家看到的版本名由它来（「10 月 8 日版」）；本机认不出来的模型为空。
    date: String,
    #[serde(default)]
    format: u32,
    #[serde(default)]
    file: String,
    size: u64,
    sha256: String,
    #[serde(default)]
    notes: String,
}

impl Version {
    /// 给页面看的：版本名、大小、这一版改了什么。文件路径和校验值不出现在界面上。
    fn view(&self) -> Value {
        json!({ "date": self.date, "size": self.size, "notes": self.notes })
    }
}

#[derive(Deserialize)]
struct Manifest {
    models: Vec<Version>,
}

#[derive(Default, Serialize, Deserialize)]
struct Latest {
    checked_at: u64,
    latest: Option<Version>,
    /// 更新的版本要配新版游戏
    needs_app: Option<Version>,
}

#[derive(Serialize, Deserialize)]
struct Installed {
    #[serde(flatten)]
    version: Version,
    installed_at: u64,
}

#[derive(Serialize, Deserialize)]
struct Intent {
    target: Version,
    /// 玩家点了下载为 true，点了暂停为 false
    run: bool,
}

#[derive(Default, Serialize, Deserialize)]
struct Progress {
    /// running / verifying / error-net / error-space / error-file
    state: String,
    #[serde(default)]
    message: String,
    #[serde(default)]
    need: u64,
    #[serde(default)]
    free: u64,
    beat: u64,
}

#[derive(Serialize, Deserialize)]
struct Prefs {
    auto: bool,
}

impl Default for Prefs {
    fn default() -> Self {
        Self { auto: true }
    }
}

struct Store {
    dir: PathBuf,
    source: String,
}

impl Store {
    fn of(app: &Application) -> Self {
        Self {
            dir: PathBuf::from(app.builtin_store()),
            source: app.builtin_source(),
        }
    }
    fn path(&self, name: &str) -> PathBuf {
        self.dir.join(name)
    }
    fn read<T: DeserializeOwned>(&self, name: &str) -> Option<T> {
        let text = fs::read_to_string(self.path(name)).ok()?;
        serde_json::from_str(&text).ok()
    }
    fn write<T: Serialize>(&self, name: &str, value: &T) -> Result<(), HostError> {
        let bytes = serde_json::to_vec_pretty(value).map_err(|e| HostError::Io(e.to_string()))?;
        atomic_write(&self.path(name), &bytes)
    }
    fn remove(&self, name: &str) {
        let _ = fs::remove_file(self.path(name));
    }
    fn part_len(&self) -> u64 {
        fs::metadata(self.path(PART)).map_or(0, |m| m.len())
    }
    fn installed(&self) -> Option<Installed> {
        if !self.path(builtin::MODEL).is_file() {
            return None;
        }
        self.read(INSTALLED).or_else(|| {
            // 认不出是哪一版（比如旧的安卓包解出来的）：先当本机的模型用，看清单时再认
            let size = fs::metadata(self.path(builtin::MODEL)).map_or(0, |m| m.len());
            Some(Installed {
                version: Version {
                    size,
                    ..Version::default()
                },
                installed_at: 0,
            })
        })
    }
    fn beat(&self, state: &str) -> Result<(), HostError> {
        self.progress(Progress {
            state: state.into(),
            ..Progress::default()
        })
    }
    fn progress(&self, mut progress: Progress) -> Result<(), HostError> {
        progress.beat = now_ms();
        self.write(PROGRESS, &progress)
    }
    /// 玩家还要这一版：没点暂停，也没换成别的版本、没删掉。
    fn wanted(&self, target: &Version) -> bool {
        self.read::<Intent>(DOWNLOAD)
            .is_some_and(|intent| intent.run && intent.target.sha256 == target.sha256)
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

/// 页面看的状态：
/// { supported, installed, latest, update, needs_app, checked_at, auto,
///   download: { date, size, notes, done, state, resume, message, need, free } | null }
/// download.state：running / verifying / paused / error-net / error-space / error-file；
/// resume 表示是被打断的（应用关掉过），不是玩家点的暂停，页面可以自己接着下。
pub fn status(app: &Application) -> Result<Value, HostError> {
    let store = Store::of(app);
    let installed = store.installed();
    let latest: Latest = store.read(LATEST).unwrap_or_default();
    let prefs: Prefs = store.read(SETTINGS).unwrap_or_default();
    let update = match (&installed, &latest.latest) {
        (Some(have), Some(new)) => {
            have.version.sha256 != new.sha256 && new.date >= have.version.date
        }
        _ => false,
    };
    let download = store.read::<Intent>(DOWNLOAD).map(|intent| {
        let progress: Progress = store.read(PROGRESS).unwrap_or_default();
        let alive = now_ms().saturating_sub(progress.beat) < BEAT_STALE_MS;
        let stopped = matches!(progress.state.as_str(), "error-space" | "error-file");
        let (state, resume) = if !intent.run {
            ("paused", false)
        } else if stopped || alive {
            (progress.state.as_str(), false)
        } else {
            ("paused", true)
        };
        let mut view = intent.target.view();
        view["done"] = json!(store.part_len().min(intent.target.size));
        view["state"] = json!(state);
        view["resume"] = json!(resume);
        view["message"] = json!(progress.message);
        view["need"] = json!(progress.need);
        view["free"] = json!(progress.free);
        view
    });
    Ok(json!({
        "supported": builtin::supported(app),
        "installed": installed.map(|i| i.version.view()),
        "latest": latest.latest.as_ref().map(Version::view),
        "update": update,
        "needs_app": latest.needs_app.as_ref().map(Version::view),
        "checked_at": (latest.checked_at > 0).then_some(latest.checked_at),
        "auto": prefs.auto,
        "download": download,
    }))
}

/// 看一眼发布处有没有新版本。认不出版本的本机模型顺便核对一下是哪一版。
pub fn check(app: &Application) -> Result<Value, HostError> {
    let store = Store::of(app);
    let url = format!("{}/manifest.json", store.source);
    // 原因只给玩家看人话，回给页面的就是这一句，不带底层的网络错误
    let manifest: Manifest = ureq::get(&url)
        .timeout(Duration::from_secs(20))
        .call()
        .map_err(|_| HostError::Rejected("现在连不上内置模型的下载服务器，稍后再试".into()))?
        .into_json()
        .map_err(|_| HostError::Rejected("内置模型的版本清单读不出来，稍后再试".into()))?;
    let newest = |format: fn(u32) -> bool| {
        manifest
            .models
            .iter()
            .filter(|v| format(v.format) && !v.file.is_empty() && v.size > 0)
            .max_by(|a, b| a.date.cmp(&b.date))
            .cloned()
    };
    let latest = newest(|f| f == builtin::FORMAT);
    let needs_app =
        newest(|f| f > builtin::FORMAT).filter(|v| latest.as_ref().is_none_or(|l| v.date > l.date));
    if store.path(builtin::MODEL).is_file() && !store.path(INSTALLED).is_file() {
        recognize(&store, &manifest.models)?;
    }
    store.write(
        LATEST,
        &Latest {
            checked_at: now_ms(),
            latest,
            needs_app,
        },
    )?;
    status(app)
}

/// 没有记录的模型文件按 sha256 认是清单里的哪一版；都对不上就记成认不出的版本，下次不再重算。
fn recognize(store: &Store, versions: &[Version]) -> Result<(), HostError> {
    let model = store.path(builtin::MODEL);
    let sha256 = digest(&model, || {}).map_err(|e| HostError::Io(format!("读取模型失败：{e}")))?;
    let size = fs::metadata(&model).map_or(0, |m| m.len());
    let version = versions
        .iter()
        .find(|v| v.sha256 == sha256)
        .cloned()
        .unwrap_or(Version {
            size,
            sha256,
            ..Version::default()
        });
    store.write(
        INSTALLED,
        &Installed {
            version,
            installed_at: now_ms(),
        },
    )
}

/// 玩家的操作：{ action: "download" | "pause" | "delete" | "auto", on? }。返回操作后的状态。
/// download 之后由管理服务确保有一个下载线程在跑（work）；暂停时下载线程一秒内自己停下。
pub fn act(app: &Application, body: &Value) -> Result<Value, HostError> {
    let store = Store::of(app);
    match body["action"].as_str().unwrap_or_default() {
        "download" => {
            if !builtin::supported(app) {
                return Err(HostError::Rejected(format!(
                    "这个版本没有带{}",
                    builtin::NAME
                )));
            }
            let target = match store.read::<Latest>(LATEST).and_then(|l| l.latest) {
                Some(target) => target,
                None => {
                    check(app)?;
                    store
                        .read::<Latest>(LATEST)
                        .and_then(|l| l.latest)
                        .ok_or_else(|| {
                            HostError::Rejected(format!("现在还没有能下载的{}", builtin::NAME))
                        })?
                }
            };
            if store
                .installed()
                .is_some_and(|have| have.version.sha256 == target.sha256)
            {
                return status(app);
            }
            // 换了目标：下到一半的是别的版本，从头下
            if store
                .read::<Intent>(DOWNLOAD)
                .is_none_or(|old| old.target.sha256 != target.sha256)
            {
                store.remove(PART);
            }
            store.write(DOWNLOAD, &Intent { target, run: true })?;
            // 下载线程还没起来时页面就来问：先当它在下，免得闪一下「已暂停」
            store.beat("running")?;
        }
        "pause" => {
            if let Some(mut intent) = store.read::<Intent>(DOWNLOAD) {
                intent.run = false;
                store.write(DOWNLOAD, &intent)?;
            }
        }
        "delete" => {
            for name in [DOWNLOAD, PROGRESS, PART, INSTALLED, builtin::MODEL] {
                store.remove(name);
            }
        }
        "auto" => {
            let auto = body["on"]
                .as_bool()
                .ok_or_else(|| HostError::Rejected("缺少 on".into()))?;
            store.write(SETTINGS, &Prefs { auto })?;
        }
        other => return Err(HostError::Rejected(format!("未知操作：{other}"))),
    }
    status(app)
}

/// 下载线程：按 download.json 下到底、核对、换上；玩家暂停或换了目标就停。断网时隔一会儿自己重试，
/// 空间不够、文件连着对不上时停下等玩家点重试。同一时间只能有一个，由管理服务保证。
pub fn work(app: &Application) {
    let store = Store::of(app);
    let agent = ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(15))
        .timeout_read(Duration::from_secs(30))
        .build();
    let mut retry = Duration::from_secs(1);
    let mut bad_files = 0;
    loop {
        let Some(target) = store
            .read::<Intent>(DOWNLOAD)
            .filter(|intent| intent.run)
            .map(|intent| intent.target)
        else {
            return;
        };
        let have = store.part_len();
        if have > target.size {
            store.remove(PART);
        }
        let have = store.part_len();
        if let Some(free) = free_space(&store.dir) {
            let need = target.size - have + SPARE;
            if free < need {
                let _ = store.progress(Progress {
                    state: "error-space".into(),
                    need: target.size - have,
                    free,
                    ..Progress::default()
                });
                return;
            }
        }
        if have < target.size {
            match fetch(&agent, &store, &target, have) {
                Ok(true) => retry = Duration::from_secs(1),
                Ok(false) => return,
                Err(message) => {
                    eprintln!("[builtin-model] {message}");
                    let _ = store.progress(Progress {
                        state: "error-net".into(),
                        message: "网络断了".into(),
                        ..Progress::default()
                    });
                    if !wait(&store, &target, retry) {
                        return;
                    }
                    retry = (retry * 2).min(RETRY_MAX);
                    continue;
                }
            }
        }
        let _ = store.beat("verifying");
        let part = store.path(PART);
        // 几百 MB 在手机上要算好几秒：边算边写心跳，不被当成停了
        let matches = store.part_len() == target.size
            && digest(&part, || {
                let _ = store.beat("verifying");
            })
            .is_ok_and(|sha256| sha256 == target.sha256);
        if !store.wanted(&target) {
            return;
        }
        if !matches {
            eprintln!("[builtin-model] {} 下载的文件对不上，删掉重下", target.date);
            store.remove(PART);
            bad_files += 1;
            if bad_files >= BAD_FILES {
                let _ = store.beat("error-file");
                return;
            }
            continue;
        }
        if let Err(error) = install(&store, target) {
            eprintln!("[builtin-model] {error}");
            let _ = store.beat("error-file");
        }
        return;
    }
}

/// 断网后等一会儿再试，等的时候照样写心跳、看玩家有没有点暂停；点了暂停返回 false。
/// 玩家点了重试（act 把状态写回 running）就不再等。
fn wait(store: &Store, target: &Version, delay: Duration) -> bool {
    let until = Instant::now() + delay;
    while Instant::now() < until {
        std::thread::sleep(Duration::from_millis(500).min(delay));
        if !store.wanted(target) {
            return false;
        }
        let mut progress: Progress = store.read(PROGRESS).unwrap_or_default();
        if progress.state != "error-net" {
            return true;
        }
        progress.beat = now_ms();
        let _ = store.write(PROGRESS, &progress);
    }
    true
}

/// 接着下到文件末尾。下完返回 true，玩家暂停或换了目标返回 false，网络出错返回原因。
fn fetch(agent: &ureq::Agent, store: &Store, target: &Version, have: u64) -> Result<bool, String> {
    let url = format!("{}/{}", store.source, target.file);
    let mut request = agent.get(&url);
    if have > 0 {
        request = request.set("Range", &format!("bytes={have}-"));
    }
    let response = request.call().map_err(|e| format!("{url}: {e}"))?;
    let part = store.path(PART);
    // 服务器不认 Range 时回整个文件：从头写。魔搭对小文件回 200 却带着 Content-Range，也算接上了
    let from = format!("bytes {have}-");
    let append = have > 0
        && (response.status() == 206
            || response
                .header("Content-Range")
                .is_some_and(|range| range.starts_with(&from)));
    let mut file = File::options()
        .create(true)
        .write(true)
        .append(append)
        .truncate(!append)
        .open(&part)
        .map_err(|e| format!("{}: {e}", part.display()))?;
    let mut reader = response.into_reader();
    let mut buffer = vec![0u8; 256 << 10];
    let mut written = if append { have } else { 0 };
    let mut last = Instant::now();
    let _ = store.beat("running");
    while written < target.size {
        let n = match reader.read(&mut buffer) {
            Ok(0) => return Err(format!("{url}: 连接提前断开")),
            Ok(n) => n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(format!("{url}: {e}")),
        };
        let n = n.min((target.size - written) as usize);
        file.write_all(&buffer[..n])
            .map_err(|e| format!("{}: {e}", part.display()))?;
        written += n as u64;
        if last.elapsed() >= Duration::from_secs(1) {
            last = Instant::now();
            if !store.wanted(target) {
                return Ok(false);
            }
            let _ = store.beat("running");
        }
    }
    file.sync_all()
        .map_err(|e| format!("{}: {e}", part.display()))?;
    Ok(true)
}

/// 核对过的文件换成正在用的模型，记下是哪一版，清掉下载记录。
fn install(store: &Store, version: Version) -> Result<(), HostError> {
    fs::rename(store.path(PART), store.path(builtin::MODEL))
        .map_err(|e| HostError::Io(format!("换上新模型失败：{e}")))?;
    store.write(
        INSTALLED,
        &Installed {
            version,
            installed_at: now_ms(),
        },
    )?;
    store.remove(DOWNLOAD);
    store.remove(PROGRESS);
    Ok(())
}

/// 文件的 sha256；算的时候每秒调一次 tick。
fn digest(path: &Path, mut tick: impl FnMut()) -> io::Result<String> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 1 << 20];
    let mut last = Instant::now();
    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        hasher.update(&buffer[..n]);
        if last.elapsed() >= Duration::from_secs(1) {
            last = Instant::now();
            tick();
        }
    }
    Ok(hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

/// 目录所在磁盘的剩余空间；查不到时为 None，不拦着下载。
fn free_space(dir: &Path) -> Option<u64> {
    fs::create_dir_all(dir).ok()?;
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        let path = std::ffi::CString::new(dir.as_os_str().as_bytes()).ok()?;
        let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
        if unsafe { libc::statvfs(path.as_ptr(), &mut stat) } != 0 {
            return None;
        }
        // 各平台字段的整数宽度不一样
        #[allow(clippy::unnecessary_cast)]
        let free = stat.f_bavail as u64 * stat.f_frsize as u64;
        Some(free)
    }
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;
        let wide: Vec<u16> = dir.as_os_str().encode_wide().chain([0]).collect();
        let mut free = 0u64;
        let null = std::ptr::null_mut();
        let ok = unsafe { GetDiskFreeSpaceExW(wide.as_ptr(), &mut free, null, null) };
        (ok != 0).then_some(free)
    }
    #[cfg(not(any(unix, windows)))]
    {
        None
    }
}
