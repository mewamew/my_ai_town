//! Agent 轨迹日志：村民和模型之间的每一次往来写一行 JSON，复盘和调试用。写在小镇目录的 logs/ 里
//! （管理服务用 AI_TOWN_LOG_DIR 指定），一次开镇一份 `resident-agent-<毫秒>-<进程号>.jsonl`，有东西要写时才建，
//! 写满 FILE_BYTES 换下一份。打开时和每建一份新的时清一次旧的：空文件删掉，其余从新到旧留着，
//! 连正在写的一份不超过 KEEP_BYTES、KEEP_FILES 份，更早的删掉。只动这个名字格式的文件，
//! 同目录里的 builtin-model.log 等不碰。
//!
//! 每次请求的完整题面（整份 messages 和工具表）占日志九成以上。不记完整题面时，「请求」那一行的
//! messages 换成最后一条（这一轮新给的，latest_message）和条数（message_count），工具表只留个数（tool_count），
//! 其余各行照旧。记不记由这台设备的设定决定（settings.rs），改了马上生效，不换文件。
use agent::runtime::TraceRecord;
use serde_json::{json, Value};
use std::{
    fs::{self, File},
    io::{BufWriter, ErrorKind, Write},
    path::{Path, PathBuf},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

/// 一份写到这么大就换下一份。
pub const FILE_BYTES: u64 = 32 << 20;
/// 每个小镇的轨迹最多留这么大，连正在写的一份。
pub const KEEP_BYTES: u64 = 256 << 20;
/// 最多留这么多份：开镇次数多、每次只写一点时，不至于攒出一大堆小文件。
pub const KEEP_FILES: usize = 64;
const PREFIX: &str = "resident-agent-";
const SUFFIX: &str = ".jsonl";
/// 空文件放了这么久才删：同一目录里别的进程刚建、还没写进去的那份不误删。
const EMPTY_GRACE: Duration = Duration::from_secs(60);

#[derive(Debug, Clone, Copy)]
pub struct Limits {
    pub file_bytes: u64,
    pub keep_bytes: u64,
    pub keep_files: usize,
}

impl Limits {
    pub const DEFAULT: Self = Self {
        file_bytes: FILE_BYTES,
        keep_bytes: KEEP_BYTES,
        keep_files: KEEP_FILES,
    };
}

pub struct TraceLog {
    dir: PathBuf,
    limits: Limits,
    full_prompts: bool,
    current: Option<Current>,
    /// 写不进去（磁盘满了之类）以后这个进程不再写，免得每拍报一次错、留下一串空文件；改设定时再试。
    broken: bool,
}

struct Current {
    path: PathBuf,
    out: BufWriter<File>,
    bytes: u64,
}

impl TraceLog {
    /// 清一遍旧文件，不建新文件。
    pub fn open(dir: PathBuf, full_prompts: bool, limits: Limits) -> Self {
        let log = Self {
            dir,
            limits,
            full_prompts,
            current: None,
            broken: false,
        };
        log.prune(None);
        log
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    pub fn full_prompts(&self) -> bool {
        self.full_prompts
    }

    pub fn set_full_prompts(&mut self, on: bool) {
        self.full_prompts = on;
        self.broken = false;
    }

    /// 目录里现有的轨迹：份数和总字节数，连正在写的一份。
    pub fn usage(&self) -> (usize, u64) {
        let files = self.files();
        (files.len(), files.iter().map(|f| f.bytes).sum())
    }

    /// 写一批轨迹。每行是 `{"model_snapshot":…, "trace":…}`，`model` 给请求那一行附上发给哪个模型。
    /// 写不进去时返回错误，之后不再写。
    pub fn write(
        &mut self,
        records: Vec<TraceRecord>,
        model: impl Fn(&TraceRecord) -> Option<Value>,
    ) -> Result<(), String> {
        if records.is_empty() || self.broken {
            return Ok(());
        }
        let written = self.append(records, model);
        if written.is_err() {
            self.broken = true;
            self.current = None;
        }
        written
    }

    fn append(
        &mut self,
        records: Vec<TraceRecord>,
        model: impl Fn(&TraceRecord) -> Option<Value>,
    ) -> Result<(), String> {
        for mut record in records {
            let snapshot = model(&record);
            if !self.full_prompts && record.event == "request" {
                brief(&mut record.data);
            }
            let mut line = serde_json::to_vec(&json!({"trace":record,"model_snapshot":snapshot}))
                .map_err(|e| format!("写 Agent 轨迹失败：{e}"))?;
            line.push(b'\n');
            let len = line.len() as u64;
            if let Some(full) = self
                .current
                .take_if(|c| c.bytes > 0 && c.bytes + len > self.limits.file_bytes)
            {
                finish(full)?;
            }
            if self.current.is_none() {
                self.current = Some(self.start()?);
            }
            let current = self.current.as_mut().expect("刚建好");
            current
                .out
                .write_all(&line)
                .map_err(|e| format!("写 Agent 轨迹 {} 失败：{e}", current.path.display()))?;
            current.bytes += len;
        }
        match &mut self.current {
            Some(current) => current
                .out
                .flush()
                .map_err(|e| format!("写 Agent 轨迹 {} 失败：{e}", current.path.display())),
            None => Ok(()),
        }
    }

    /// 建新的一份，再清旧的。毫秒相同时往后挪一毫秒，不覆盖已有的文件。
    fn start(&self) -> Result<Current, String> {
        fs::create_dir_all(&self.dir)
            .map_err(|e| format!("创建日志目录 {} 失败：{e}", self.dir.display()))?;
        let mut stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_millis());
        let (path, file) = loop {
            let path = self
                .dir
                .join(format!("{PREFIX}{stamp}-{}{SUFFIX}", std::process::id()));
            match File::options().write(true).create_new(true).open(&path) {
                Ok(file) => break (path, file),
                Err(e) if e.kind() == ErrorKind::AlreadyExists => stamp += 1,
                Err(e) => return Err(format!("创建 Agent 轨迹 {} 失败：{e}", path.display())),
            }
        };
        println!("[host] Agent 轨迹 → {}", path.display());
        self.prune(Some(&path));
        Ok(Current {
            path,
            out: BufWriter::new(file),
            bytes: 0,
        })
    }

    /// 从新到旧数：正在写的一份先占一整份的额度，其余的按大小往里装，装不下的和更早的都删掉；
    /// 空文件不占额度，放久了直接删。删不掉（别的进程开着之类）就留到下次。
    fn prune(&self, current: Option<&Path>) {
        let mut room = self
            .limits
            .keep_bytes
            .saturating_sub(self.limits.file_bytes);
        let mut slots = self.limits.keep_files.saturating_sub(1);
        let mut full = false;
        let now = SystemTime::now();
        for file in self.files() {
            if Some(file.path.as_path()) == current {
                continue;
            }
            let doomed = if file.bytes == 0 {
                file.modified
                    .and_then(|m| now.duration_since(m).ok())
                    .is_some_and(|age| age >= EMPTY_GRACE)
            } else {
                full = full || slots == 0 || file.bytes > room;
                if !full {
                    room -= file.bytes;
                    slots -= 1;
                }
                full
            };
            if doomed {
                let _ = fs::remove_file(&file.path);
            }
        }
    }

    /// 目录里这个名字格式的文件，新的在前。
    fn files(&self) -> Vec<TraceFile> {
        let Ok(entries) = fs::read_dir(&self.dir) else {
            return Vec::new();
        };
        let mut files: Vec<_> = entries
            .flatten()
            .filter_map(|entry| {
                let stamp = entry.file_name().to_str().and_then(stamp)?;
                let meta = entry.metadata().ok().filter(|m| m.is_file())?;
                Some(TraceFile {
                    stamp,
                    path: entry.path(),
                    bytes: meta.len(),
                    modified: meta.modified().ok(),
                })
            })
            .collect();
        files.sort_by(|a, b| (b.stamp, &b.path).cmp(&(a.stamp, &a.path)));
        files
    }
}

struct TraceFile {
    stamp: u128,
    path: PathBuf,
    bytes: u64,
    modified: Option<SystemTime>,
}

/// `resident-agent-<毫秒>-<进程号>.jsonl` 里的毫秒；不是这个格式的不算轨迹。
fn stamp(name: &str) -> Option<u128> {
    let (ms, pid) = name
        .strip_prefix(PREFIX)?
        .strip_suffix(SUFFIX)?
        .split_once('-')?;
    let digits = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit());
    if digits(ms) && digits(pid) {
        ms.parse().ok()
    } else {
        None
    }
}

fn finish(mut full: Current) -> Result<(), String> {
    full.out
        .flush()
        .map_err(|e| format!("写 Agent 轨迹 {} 失败：{e}", full.path.display()))
}

/// 请求那一行不记完整题面：messages 只留最后一条和条数，工具表只留个数。
fn brief(data: &mut Value) {
    let Some(request) = data.get_mut("request").and_then(Value::as_object_mut) else {
        return;
    };
    if let Some(Value::Array(messages)) = request.remove("messages") {
        request.insert("message_count".into(), json!(messages.len()));
        if let Some(latest) = messages.into_iter().last() {
            request.insert("latest_message".into(), latest);
        }
    }
    if let Some(Value::Array(tools)) = request.remove("tools") {
        request.insert("tool_count".into(), json!(tools.len()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(event: &str, text: &str) -> TraceRecord {
        TraceRecord {
            schema_version: 1,
            epoch: 1,
            actor_id: "resident_001".into(),
            session_id: 1,
            request_id: None,
            sim_minutes: 0.0,
            event: event.into(),
            data: json!({ "text": text }),
        }
    }

    /// 写满一份就换下一份，一行不拆开；份数超了只留最新的几份。
    #[test]
    fn full_files_roll_over_and_only_the_newest_stay() {
        let dir = std::env::temp_dir().join(format!(
            "ai-town-trace-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let limits = Limits {
            file_bytes: 1_000,
            keep_bytes: 3_000,
            keep_files: 3,
        };
        let mut log = TraceLog::open(dir.clone(), true, limits);
        let text = "x".repeat(300);
        for _ in 0..12 {
            log.write(vec![record("wait", &text)], |_| None).unwrap();
        }
        let files = log.files();
        assert_eq!(files.len(), 3, "只留最新的三份");
        let lines: Vec<usize> = files
            .iter()
            .map(|f| {
                let text = fs::read_to_string(&f.path).unwrap();
                assert!(f.bytes <= limits.file_bytes, "{} 超过一份的上限", f.bytes);
                for line in text.lines() {
                    serde_json::from_str::<Value>(line).expect("每行都是完整的 JSON");
                }
                text.lines().count()
            })
            .collect();
        // 一行四百多字节：每份装两行，十二行写成六份，留下最后三份
        assert_eq!(lines, vec![2, 2, 2]);
        fs::remove_dir_all(&dir).unwrap();
    }
}
