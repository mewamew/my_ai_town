//! 录像：把广播给页面的消息顺手写进小镇目录，事后照着它把画面重演一遍、换角度拍素材
//! （读的一方是 scripts/replay/reel.mjs）。录的是模型做完决定之后的结果，重演时不开世界、不调模型。
//!
//! 一卷是从开始录到停的一段：世界打开（录像开着）、在设定里打开录像、重置世界，各开新的一卷。
//! 目录 `recordings/<卷>/` 里是 `header.json`（这一卷的说明）和每 5 分钟一段的 `NNN.jsonl`；
//! 一段写满就在后台压成 `NNN.jsonl.gz`。进程意外退出时最后一段留着没压的原文，读的一方两种都认。
//!
//! 每行一条 JSON，`t` 是离这一卷开头的毫秒数：
//! - `{"t","m":消息}`：名册以外的广播原样照抄（事件、世界设定、道具、人口……）；
//! - `{"t","k":名册}`：完整名册。这一卷的第一份、每段开头，以及名册变了而离上一份完整的已过 10 秒时写；
//!   名册里每个人只带画面每拍要用的 Agent 状态，角色卡细节（目标、动作结果、互动、记着的事）不是广播，不录；
//! - `{"t","d":变化}`：名册只记跟上一份不同的地方：`s` 变了的顶层字段，`u` 没了的顶层字段，
//!   `m` 按人记变了（或新来的人的全部）字段，`x` 按人记没了的字段，`o` 处所和人的先后（变了才记）；
//!   `b` 按人记身体（body）里变了的地方：`s` 变了的项、`u` 没了的项、`h` 经历列表末尾新添的几条。
//!   病人的身体每拍都在变，经历列表越积越长，整份重写会让录像暴涨，所以身体单独往下拆一层。
//!   跟上一份一样的名册不写，重演时上一份一直有效。
//!
//! 每段开头先抄一遍最近的世界设定、道具和人口，再写一份完整名册，所以每一段都能单独拿来重演。
//! 地图按摘要另存一份在 `recordings/maps/`，以后改了图，旧录像照样能放。
use crate::HostError;
use flate2::{write::GzEncoder, Compression};
use protocol::{ReelView, ServerMsg};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, File};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// 小镇目录下放录像的子目录
pub const RECORDINGS_DIR: &str = "recordings";
/// 录像目录下按摘要存地图的子目录
pub const MAPS_DIR: &str = "maps";
const HEADER: &str = "header.json";
/// 录像文件的格式号；读的一方只认得这个号，改了行的写法要加一。
/// 2：名册变化里身体单独记（`b`），读 2 的一方也读得了 1。
/// 3：行的写法没变，名册里每个人的 Agent 状态只留每拍要用的（protocol 的 ResidentAgentView），
/// 不再带整份角色卡细节；读 3 的一方读 1、2 时从旧名册里的列表补出画面要的两个记号。
pub const FORMAT: u32 = 3;
/// 一段录这么久（现实时间）就换下一段
const SEGMENT: Duration = Duration::from_secs(5 * 60);
/// 名册变了、离上一份完整名册已过这么久，就写完整的，跳到任意时刻最多从 10 秒前接起
const KEYFRAME: Duration = Duration::from_secs(10);
/// 缓冲最多攒这么久才写进文件；进程意外退出时最多丢这么一点
const FLUSH: Duration = Duration::from_secs(1);

/// 开一卷要知道的：录在哪个小镇目录、这是哪个小镇哪个世界、用的哪张地图。
pub struct Reel<'a> {
    pub town_dir: &'a Path,
    pub town_id: Option<&'a str>,
    pub world_id: &'a str,
    pub map_hash: &'a str,
    /// 地图文件；按摘要另存一份，没有时不存
    pub map_document: Option<&'a Path>,
}

/// `header.json`：这一卷的说明。录的过程中只在换段和收尾时更新。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Header {
    pub format: u32,
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub town_id: Option<String>,
    pub world_id: String,
    pub map_hash: String,
    pub started_at: u64,
    #[serde(default)]
    pub ended_at: Option<u64>,
    #[serde(default)]
    pub from_clock: String,
    #[serde(default)]
    pub to_clock: String,
    #[serde(default)]
    pub from_minutes: Option<f64>,
    #[serde(default)]
    pub to_minutes: Option<f64>,
    /// 写到第几段（段数）
    pub segments: u32,
}

/// 正在录的一卷。
pub struct Recorder {
    dir: PathBuf,
    header: Header,
    clock: Instant,
    out: BufWriter<File>,
    segment_started: Duration,
    flushed: Duration,
    /// 最近的世界设定、道具和人口原文：每段开头重抄一遍
    state: BTreeMap<&'static str, String>,
    /// 上一份完整名册；下一份只记跟它不同的地方
    roster: Option<Value>,
    keyframe: Duration,
    /// 开头那几条以后录到过东西（名册变了、有世界日志）；收起时什么都没录到的一卷不留
    eventful: bool,
    /// 后台压缩写满的段
    packing: Vec<JoinHandle<()>>,
}

impl Recorder {
    /// 开新的一卷，先把页面开局要的消息（世界设定、道具、人口、名册）写进去。
    pub fn start(reel: Reel, opening: &[ServerMsg]) -> Result<Self, HostError> {
        let root = reel.town_dir.join(RECORDINGS_DIR);
        let started_at = now_ms();
        let id = unused_id(&root, started_at);
        let dir = root.join(&id);
        fs::create_dir_all(&dir).map_err(|e| io_error(&dir, e))?;
        if let Some(map) = reel.map_document {
            keep_map(&root, reel.map_hash, map)?;
        }
        let out = open_segment(&dir, 0)?;
        let mut recorder = Self {
            header: Header {
                format: FORMAT,
                id,
                town_id: reel.town_id.map(str::to_owned),
                world_id: reel.world_id.into(),
                map_hash: reel.map_hash.into(),
                started_at,
                ended_at: None,
                from_clock: String::new(),
                to_clock: String::new(),
                from_minutes: None,
                to_minutes: None,
                segments: 1,
            },
            dir,
            clock: Instant::now(),
            out,
            segment_started: Duration::ZERO,
            flushed: Duration::ZERO,
            state: BTreeMap::new(),
            roster: None,
            keyframe: Duration::ZERO,
            eventful: false,
            packing: Vec::new(),
        };
        recorder.write_header()?;
        for msg in opening {
            let json = serde_json::to_string(msg)
                .map_err(|e| HostError::Runtime(format!("录像编码失败：{e}")))?;
            recorder.record(msg, &json)?;
        }
        recorder.out.flush().map_err(|e| recorder.io(e))?;
        recorder.eventful = false;
        Ok(recorder)
    }

    pub fn id(&self) -> &str {
        &self.header.id
    }

    /// 记一条广播；`json` 是这条消息发给页面的原文。
    pub fn record(&mut self, msg: &ServerMsg, json: &str) -> Result<(), HostError> {
        let now = self.clock.elapsed();
        if now - self.segment_started >= SEGMENT {
            self.rotate(now)?;
        }
        let t = now.as_millis();
        if let ServerMsg::Roster { .. } = msg {
            let next: Value = serde_json::from_str(json)
                .map_err(|e| HostError::Runtime(format!("录像读名册失败：{e}")))?;
            self.note_clock(&next);
            match self.roster.as_ref().map(|prev| roster_delta(prev, &next)) {
                None => self.keyframe_line(t, now, &next)?,
                Some(None) => {}
                Some(Some(_)) if now - self.keyframe >= KEYFRAME => {
                    self.eventful = true;
                    self.keyframe_line(t, now, &next)?
                }
                Some(Some(delta)) => {
                    self.eventful = true;
                    self.line(t, "d", &delta.to_string())?
                }
            }
            self.roster = Some(next);
        } else {
            if let Some(kind) = state_kind(msg) {
                self.state.insert(kind, json.to_owned());
            }
            self.eventful |= matches!(msg, ServerMsg::Event { .. });
            self.line(t, "m", json)?;
        }
        if now - self.flushed >= FLUSH {
            self.out.flush().map_err(|e| self.io(e))?;
            self.flushed = now;
        }
        Ok(())
    }

    /// 这一卷此刻的样子，给录像列表用。
    pub fn view(&self) -> ReelView {
        let mut view = reel_view(&self.header, &self.dir);
        view.ended_at = None;
        view
    }

    /// 收尾：写完缓冲、记下结束时刻，关上最后一段再压好，等后台的压缩都做完。
    /// 开头以后什么也没录到（世界一直暂停着就关了）的一卷不留，免得列表里一串空卷。
    pub fn finish(mut self) -> Result<(), HostError> {
        if !self.eventful {
            let Recorder {
                dir, out, packing, ..
            } = self;
            drop(out);
            for handle in packing {
                let _ = handle.join();
            }
            return fs::remove_dir_all(&dir).map_err(|e| io_error(&dir, e));
        }
        let flushed = self.out.flush().map_err(|e| self.io(e));
        self.header.ended_at = Some(now_ms());
        let header = self.write_header();
        let last = self.header.segments - 1;
        let Recorder {
            dir,
            out,
            mut packing,
            ..
        } = self;
        drop(out);
        packing.push(pack(&dir, last));
        for handle in packing {
            let _ = handle.join();
        }
        flushed.and(header)
    }

    fn keyframe_line(&mut self, t: u128, now: Duration, roster: &Value) -> Result<(), HostError> {
        self.keyframe = now;
        self.line(t, "k", &roster.to_string())
    }

    fn line(&mut self, t: u128, key: &str, json: &str) -> Result<(), HostError> {
        let line = format!("{{\"t\":{t},\"{key}\":{json}}}\n");
        self.out
            .write_all(line.as_bytes())
            .map_err(|e| io_error(&self.dir, e))
    }

    /// 换下一段：写满的这段交给后台压缩；新的一段先抄最近的设定、道具、人口和完整名册。
    fn rotate(&mut self, now: Duration) -> Result<(), HostError> {
        self.out.flush().map_err(|e| self.io(e))?;
        let done = self.header.segments - 1;
        // 换上新的一段时旧文件随之关上，再交给后台压缩
        self.out = open_segment(&self.dir, done + 1)?;
        self.header.segments += 1;
        self.segment_started = now;
        self.packing.retain(|h| !h.is_finished());
        self.packing.push(pack(&self.dir, done));
        self.write_header()?;
        let t = now.as_millis();
        let state: Vec<String> = self.state.values().cloned().collect();
        for json in state {
            self.line(t, "m", &json)?;
        }
        if let Some(roster) = self.roster.take() {
            let written = self.keyframe_line(t, now, &roster);
            self.roster = Some(roster);
            written?;
        }
        Ok(())
    }

    fn note_clock(&mut self, roster: &Value) {
        let clock = roster["clock"].as_str().unwrap_or_default();
        let minutes = roster["sim_minutes"].as_f64();
        if self.header.from_minutes.is_none() {
            self.header.from_clock = clock.into();
            self.header.from_minutes = minutes;
        }
        self.header.to_clock = clock.into();
        self.header.to_minutes = minutes;
    }

    fn write_header(&self) -> Result<(), HostError> {
        let bytes = serde_json::to_vec_pretty(&self.header)
            .map_err(|e| HostError::Runtime(format!("录像说明编码失败：{e}")))?;
        crate::persistence::atomic_write(&self.dir.join(HEADER), &bytes)
    }

    fn io(&self, error: io::Error) -> HostError {
        io_error(&self.dir, error)
    }
}

/// 录像机和模拟循环、广播共用的一份：开着录像时每条广播都交给它。写不进去（磁盘满了之类）就收起
/// 这一卷，原因留给模拟循环去报告。
#[derive(Clone, Default)]
pub struct Tape(Arc<Mutex<Deck>>);

#[derive(Default)]
struct Deck {
    recorder: Option<Recorder>,
    failure: Option<String>,
}

impl Tape {
    /// 记一条广播；没在录时什么也不做。
    pub fn record(&self, msg: &ServerMsg, json: &str) {
        let mut deck = self.0.lock().unwrap();
        let Some(recorder) = deck.recorder.as_mut() else {
            return;
        };
        if let Err(error) = recorder.record(msg, json) {
            if let Some(recorder) = deck.recorder.take() {
                let _ = recorder.finish();
            }
            eprintln!("[host] 录像写不进去，已停下：{error}");
            deck.failure = Some(error.to_string());
        }
    }

    /// 收起正在录的一卷（如果有），开新的一卷。
    pub fn start(&self, reel: Reel, opening: &[ServerMsg]) -> Result<(), HostError> {
        let mut deck = self.0.lock().unwrap();
        if let Some(old) = deck.recorder.take() {
            if let Err(error) = old.finish() {
                eprintln!("[host] 收起上一卷录像失败：{error}");
            }
        }
        let recorder = Recorder::start(reel, opening)?;
        println!("[host] 开始录像：{}", recorder.id());
        deck.recorder = Some(recorder);
        Ok(())
    }

    /// 收起正在录的一卷；没在录时什么也不做。
    pub fn stop(&self) -> Result<(), HostError> {
        let recorder = self.0.lock().unwrap().recorder.take();
        match recorder {
            Some(recorder) => {
                let id = recorder.id().to_owned();
                recorder.finish()?;
                println!("[host] 录像已收起：{id}");
                Ok(())
            }
            None => Ok(()),
        }
    }

    /// 正在录的一卷
    pub fn live(&self) -> Option<ReelView> {
        self.0.lock().unwrap().recorder.as_ref().map(Recorder::view)
    }

    /// 上次写不进去而停下的原因；取走后清空
    pub fn take_failure(&self) -> Option<String> {
        self.0.lock().unwrap().failure.take()
    }
}

/// 小镇目录里录下的几卷，新的在前；`live` 是正在录的那一卷，用它此刻的样子。
pub fn list(town_dir: &Path, live: Option<ReelView>) -> Vec<ReelView> {
    let root = town_dir.join(RECORDINGS_DIR);
    let live_id = live.as_ref().map(|l| l.id.clone());
    let mut reels: Vec<ReelView> = fs::read_dir(&root)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|entry| entry.file_name() != MAPS_DIR && entry.path().is_dir())
        .filter_map(|entry| {
            let dir = entry.path();
            let header: Header = serde_json::from_slice(&fs::read(dir.join(HEADER)).ok()?).ok()?;
            if live_id.as_deref() == Some(header.id.as_str()) {
                return None;
            }
            Some(reel_view(&header, &dir))
        })
        .chain(live)
        .collect();
    reels.sort_by(|a, b| b.started_at.cmp(&a.started_at).then(b.id.cmp(&a.id)));
    reels
}

/// 上次世界进程没来得及收尾就没了（崩溃、被强行结束、断电、手机上在后台被系统杀掉）的几卷：
/// 打开世界、开新的一卷之前补上收尾。存档锁保证同一个小镇同时只有一个世界进程，这时还没写结束时刻的
/// 都是上次留下的。从录下的行里找回时间范围，结束时刻按最后一行算；没压的段截掉没写完的最后一行再压好。
/// 读不出的段当作到那里为止，有多少算多少；补不上的那一卷原样留着，下次打开再补。
pub fn seal_unfinished(town_dir: &Path) {
    let root = town_dir.join(RECORDINGS_DIR);
    for entry in fs::read_dir(&root).into_iter().flatten().flatten() {
        let dir = entry.path();
        if entry.file_name() == MAPS_DIR || !dir.is_dir() {
            continue;
        }
        let Some(mut header) = fs::read(dir.join(HEADER))
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Header>(&bytes).ok())
        else {
            continue;
        };
        if header.ended_at.is_some() {
            continue;
        }
        match seal(&dir, &mut header) {
            Ok(()) => println!("[host] 补上了上次没收尾的录像：{}", header.id),
            Err(error) => eprintln!("[host] 上次没收尾的录像补不上：{}：{error}", header.id),
        }
    }
}

/// 补一卷的收尾：逐段读完，没压的段只留完整的行再压；最后写说明。中途又断了，下次照样从头补。
fn seal(dir: &Path, header: &mut Header) -> Result<(), HostError> {
    let mut indices = BTreeSet::new();
    for entry in fs::read_dir(dir).map_err(|e| io_error(dir, e))?.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.ends_with(".gz.tmp") {
            // 压到一半的临时文件：原文还在，重新压
            let _ = fs::remove_file(entry.path());
        } else if let Some(index) = name
            .strip_suffix(".jsonl.gz")
            .or_else(|| name.strip_suffix(".jsonl"))
            .and_then(|stem| stem.parse::<u32>().ok())
        {
            indices.insert(index);
        }
    }
    // 压缩会改文件时刻，先记下最后写入的时刻：一行都读不到时按它算结束
    let written = last_write(dir);
    // 换过段的卷，说明里已经有开头的时钟，换段前的几段不用再读（长录像意外退出后开镇不用多等）
    let known = !header.from_clock.is_empty();
    let current = header.segments.saturating_sub(1);
    let mut span = Span::default();
    for &index in &indices {
        let packed = segment_path(dir, index, true);
        let plain = segment_path(dir, index, false);
        if packed.is_file() {
            // 压好、改完名还没来得及删原文
            if plain.is_file() {
                let _ = fs::remove_file(&plain);
            }
            if known && index < current {
                continue;
            }
            let mut text = Vec::new();
            // 读不完的压缩段：读出多少算多少
            let source = File::open(&packed).map_err(|e| io_error(&packed, e))?;
            let _ = io::Read::read_to_end(&mut flate2::read::GzDecoder::new(source), &mut text);
            span.read(&text);
        } else {
            let text = fs::read(&plain).map_err(|e| io_error(&plain, e))?;
            let whole = span.read(&text);
            compress_from(whole.as_slice(), &packed)
                .and_then(|()| fs::remove_file(&plain))
                .map_err(|e| io_error(&packed, e))?;
        }
    }
    header.ended_at = Some(match span.last_t {
        Some(t) => header.started_at + t,
        None => written.unwrap_or(header.started_at),
    });
    if let Some((clock, minutes)) = span.first.filter(|_| !known) {
        header.from_clock = clock;
        header.from_minutes = minutes;
    }
    if let Some((clock, minutes)) = span.last {
        header.to_clock = clock;
        header.to_minutes = minutes;
    }
    header.segments = indices.last().map_or(header.segments, |last| last + 1);
    let bytes = serde_json::to_vec_pretty(&header)
        .map_err(|e| HostError::Runtime(format!("录像说明编码失败：{e}")))?;
    crate::persistence::atomic_write(&dir.join(HEADER), &bytes)
}

/// 补收尾时从录下的行里找回的：最后一行的时刻、第一份和最后一份名册上的时钟。
#[derive(Default)]
struct Span {
    last_t: Option<u64>,
    first: Option<(String, Option<f64>)>,
    last: Option<(String, Option<f64>)>,
}

impl Span {
    /// 读一段的原文，返回其中完整的行（每行带换行）。到第一行读不出的为止：进程意外退出时
    /// 最后一行可能没写完，和读的一方（scripts/replay/reel.mjs）一样丢掉它和之后的。
    fn read(&mut self, text: &[u8]) -> Vec<u8> {
        let mut whole = Vec::with_capacity(text.len());
        for line in text.split(|b| *b == b'\n').filter(|l| !l.is_empty()) {
            let Ok(value) = serde_json::from_slice::<Value>(line) else {
                break;
            };
            whole.extend_from_slice(line);
            whole.push(b'\n');
            if let Some(t) = value["t"].as_u64() {
                self.last_t = Some(t);
            }
            // 时钟在完整名册（k）里，或在名册变化里变了的顶层字段（d.s）里
            let roster = if value["k"].is_object() {
                &value["k"]
            } else {
                &value["d"]["s"]
            };
            if let Some(clock) = roster["clock"].as_str() {
                let at = (clock.to_owned(), roster["sim_minutes"].as_f64());
                self.first.get_or_insert_with(|| at.clone());
                self.last = Some(at);
            }
        }
        whole
    }
}

/// 删掉录完的一卷，再清掉没有哪一卷还用着的地图。编号只认得 `unused_id` 起的那种名字。
pub fn delete(town_dir: &Path, id: &str) -> Result<(), HostError> {
    let valid = !id.is_empty()
        && id != MAPS_DIR
        && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-');
    let root = town_dir.join(RECORDINGS_DIR);
    let dir = root.join(id);
    if !valid || !dir.join(HEADER).is_file() {
        return Err(HostError::Rejected(format!("没有这一卷录像：{id}")));
    }
    fs::remove_dir_all(&dir).map_err(|e| io_error(&dir, e))?;
    let used: BTreeSet<String> = fs::read_dir(&root)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| fs::read(entry.path().join(HEADER)).ok())
        .filter_map(|bytes| serde_json::from_slice::<Header>(&bytes).ok())
        .map(|header| format!("{}.json.gz", header.map_hash))
        .collect();
    for entry in fs::read_dir(root.join(MAPS_DIR))
        .into_iter()
        .flatten()
        .flatten()
    {
        if !used.contains(&entry.file_name().to_string_lossy().to_string()) {
            let _ = fs::remove_file(entry.path());
        }
    }
    Ok(())
}

/// 名册的变化；跟上一份一样时为空。写法见文件开头。
pub fn roster_delta(prev: &Value, next: &Value) -> Option<Value> {
    // 名册总是对象（带 type 标签的枚举）
    let (Value::Object(prev), Value::Object(next)) = (prev, next) else {
        return None;
    };
    let mut delta = Map::new();
    let top = |k: &String| k != "type" && k != "locales";
    let set: Map<String, Value> = next
        .iter()
        .filter(|(k, v)| top(k) && prev.get(*k) != Some(*v))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    let unset: Vec<Value> = prev
        .keys()
        .filter(|k| top(k) && !next.contains_key(*k))
        .map(|k| Value::String(k.clone()))
        .collect();
    let before = members(prev);
    let (mut changed, mut gone, mut bodies) = (Map::new(), Map::new(), Map::new());
    for (id, member) in members(next) {
        let Some(old) = before.get(&id) else {
            changed.insert(id, Value::Object(member.clone()));
            continue;
        };
        let mut fields: Map<String, Value> = member
            .iter()
            .filter(|(k, v)| old.get(*k) != Some(*v))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        if let (Some(Value::Object(was)), Some(Value::Object(now))) =
            (old.get("body"), fields.get("body"))
        {
            bodies.insert(id.clone(), body_delta(was, now));
            fields.remove("body");
        }
        let missing: Vec<Value> = old
            .keys()
            .filter(|k| !member.contains_key(*k))
            .map(|k| Value::String(k.clone()))
            .collect();
        if !fields.is_empty() {
            changed.insert(id.clone(), Value::Object(fields));
        }
        if !missing.is_empty() {
            gone.insert(id, Value::Array(missing));
        }
    }
    for (key, value) in [
        ("s", Value::Object(set)),
        ("u", Value::Array(unset)),
        ("m", Value::Object(changed)),
        ("x", Value::Object(gone)),
        ("b", Value::Object(bodies)),
    ] {
        let empty = match &value {
            Value::Object(o) => o.is_empty(),
            Value::Array(a) => a.is_empty(),
            _ => false,
        };
        if !empty {
            delta.insert(key.into(), value);
        }
    }
    let seated = order(next);
    if seated != order(prev) {
        delta.insert("o".into(), seated);
    }
    (!delta.is_empty()).then_some(Value::Object(delta))
}

/// 一个人身体里变了的地方：`s` 变了的项，`u` 没了的项，`h` 经历列表末尾新添的；
/// 经历不是只往后添（比如复活后清了）时整份放进 `s`。
fn body_delta(was: &Map<String, Value>, now: &Map<String, Value>) -> Value {
    let mut set: Map<String, Value> = now
        .iter()
        .filter(|(k, v)| k.as_str() != "history" && was.get(*k) != Some(*v))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    let unset: Vec<Value> = was
        .keys()
        .filter(|k| !now.contains_key(*k))
        .map(|k| Value::String(k.clone()))
        .collect();
    let mut delta = Map::new();
    match (was.get("history"), now.get("history")) {
        (Some(Value::Array(old)), Some(Value::Array(new)))
            if new.len() >= old.len() && new[..old.len()] == old[..] =>
        {
            if new.len() > old.len() {
                delta.insert("h".into(), Value::Array(new[old.len()..].to_vec()));
            }
        }
        (old, Some(new)) if old != Some(new) => {
            set.insert("history".into(), new.clone());
        }
        _ => {}
    }
    if !set.is_empty() {
        delta.insert("s".into(), Value::Object(set));
    }
    if !unset.is_empty() {
        delta.insert("u".into(), Value::Array(unset));
    }
    Value::Object(delta)
}

/// 名册里每个人：编号 → 字段
fn members(roster: &Map<String, Value>) -> BTreeMap<String, &Map<String, Value>> {
    roster
        .get("locales")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .flat_map(|locale| locale["members"].as_array().into_iter().flatten())
        .filter_map(|member| {
            let member = member.as_object()?;
            Some((member.get("id")?.as_str()?.to_owned(), member))
        })
        .collect()
}

/// 处所和人的先后：`[[处所, [编号…]], …]`
fn order(roster: &Map<String, Value>) -> Value {
    let locales = roster
        .get("locales")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|locale| {
            let ids: Vec<Value> = locale["members"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|m| m["id"].clone())
                .collect();
            Value::Array(vec![locale["locale"].clone(), Value::Array(ids)])
        })
        .collect();
    Value::Array(locales)
}

/// 每段开头要重抄的消息：页面开局要的世界设定、道具和人口
fn state_kind(msg: &ServerMsg) -> Option<&'static str> {
    match msg {
        ServerMsg::WorldSettings { .. } => Some("world_settings"),
        ServerMsg::Props { .. } => Some("props"),
        ServerMsg::Population { .. } => Some("population"),
        _ => None,
    }
}

fn reel_view(header: &Header, dir: &Path) -> ReelView {
    ReelView {
        id: header.id.clone(),
        started_at: header.started_at,
        // 意外退出、还没补上收尾的，按最后写入的时刻算
        ended_at: header.ended_at.or_else(|| last_write(dir)),
        from_clock: header.from_clock.clone(),
        to_clock: header.to_clock.clone(),
        bytes: files(dir).iter().map(fs::Metadata::len).sum(),
    }
}

fn files(dir: &Path) -> Vec<fs::Metadata> {
    fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| entry.metadata().ok())
        .filter(fs::Metadata::is_file)
        .collect()
}

/// 一卷里最后写入文件的时刻（毫秒）
fn last_write(dir: &Path) -> Option<u64> {
    files(dir)
        .iter()
        .filter_map(|m| m.modified().ok())
        .max()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
}

fn segment_path(dir: &Path, index: u32, packed: bool) -> PathBuf {
    dir.join(format!(
        "{index:03}.jsonl{}",
        if packed { ".gz" } else { "" }
    ))
}

/// 在后台把写满（已关上）的一段压成 `.jsonl.gz`：先写临时文件再改名，最后删掉原文；
/// 中途退出时原文还在，读的一方照样认。
fn pack(dir: &Path, index: u32) -> JoinHandle<()> {
    let plain = segment_path(dir, index, false);
    let packed = segment_path(dir, index, true);
    std::thread::spawn(move || {
        if let Err(error) = compress(&plain, &packed) {
            eprintln!(
                "[host] 录像压缩失败，原文留着：{}：{error}",
                plain.display()
            );
        }
    })
}

fn open_segment(dir: &Path, index: u32) -> Result<BufWriter<File>, HostError> {
    let path = segment_path(dir, index, false);
    File::create(&path)
        .map(BufWriter::new)
        .map_err(|e| io_error(&path, e))
}

fn compress(plain: &Path, packed: &Path) -> io::Result<()> {
    compress_from(File::open(plain)?, packed)?;
    fs::remove_file(plain)
}

/// 压成 `packed`：先写临时文件再改名，压到一半断了不会留下坏的压缩段
fn compress_from(mut source: impl io::Read, packed: &Path) -> io::Result<()> {
    let temporary = packed.with_extension("gz.tmp");
    let mut encoder = GzEncoder::new(File::create(&temporary)?, Compression::default());
    io::copy(&mut source, &mut encoder)?;
    encoder.finish()?.sync_all()?;
    fs::rename(&temporary, packed)
}

/// 地图按摘要存一份；已经有了就不再存。
fn keep_map(root: &Path, hash: &str, map: &Path) -> Result<(), HostError> {
    if hash.is_empty() || !hash.bytes().all(|b| b.is_ascii_alphanumeric()) {
        return Ok(());
    }
    let dir = root.join(MAPS_DIR);
    let path = dir.join(format!("{hash}.json.gz"));
    if path.is_file() {
        return Ok(());
    }
    fs::create_dir_all(&dir).map_err(|e| io_error(&dir, e))?;
    let temporary = dir.join(format!("{hash}.json.gz.tmp"));
    let written = File::open(map).and_then(|mut source| {
        let mut encoder = GzEncoder::new(File::create(&temporary)?, Compression::default());
        io::copy(&mut source, &mut encoder)?;
        encoder.finish()?.sync_all()?;
        fs::rename(&temporary, &path)
    });
    written.map_err(|e| io_error(&path, e))
}

/// 卷的编号：开始录的 UTC 时刻；同一秒里已经有了就在后面加序号
fn unused_id(root: &Path, started_at: u64) -> String {
    let base = utc_stamp(started_at / 1000);
    (1..)
        .map(|n| {
            if n == 1 {
                base.clone()
            } else {
                format!("{base}-{n}")
            }
        })
        .find(|id| !root.join(id).exists())
        .expect("总有一个没用过的编号")
}

/// Unix 秒 → `YYYYMMDDTHHMMSSZ`（Howard Hinnant 的 civil_from_days）
fn utc_stamp(seconds: u64) -> String {
    let days = (seconds / 86_400) as i64;
    let rest = seconds % 86_400;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}{month:02}{day:02}T{:02}{:02}{:02}Z",
        rest / 3_600,
        rest % 3_600 / 60,
        rest % 60
    )
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or_default()
}

fn io_error(path: &Path, error: io::Error) -> HostError {
    HostError::Io(format!("录像写入 {} 失败：{error}", path.display()))
}
