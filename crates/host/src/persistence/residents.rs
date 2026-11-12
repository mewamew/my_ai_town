//! 村民的记忆目录。world.json 里的内容摘要清单是提交点；可读目录是已提交文件的投影。
//! 新文件先写不可变版本，最后提交世界；中途退出不会把未来记忆带入旧世界。
//! 暂存（`ResidentStore`，主线程）只看上次提交之后变了的：笔记页按版本，旧版本、折叠归档和
//! 上下文来源按编号（只增不改），所以存盘的花费不随记忆变多而变大。事件和记忆记录不在这个
//! 目录里，它们进流水（history.rs）；旧版本、归档、来源这些写过就不再变的文件还在这个目录里，
//! 只是清单条目也记在流水里，world.json 的清单只列会反复改写的那几份（索引、当前事务、笔记页）。
//! 落到文件上的动作在 `ResidentFiles`，可以在后台线程做。
use super::history::Line;
use super::{atomic_write, SAVE_FILE_NAME};
use crate::agent_worker::AgentSave;
use crate::HostError;
use agent::{memory::MemoryRecord, notebook::Page, runtime::RuntimeState, session::Session};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

const OBJECTS_DIR: &str = ".objects";
type Files = BTreeMap<String, FileVersion>;
pub(super) type Residents = BTreeMap<String, Files>;
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub(super) struct FileVersion {
    hash: String,
    bytes: u64,
}

pub(super) fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn component(s: &str) -> String {
    if agent::notebook::safe_component(s) {
        return s.into();
    }
    format!("~{}", hash(s.as_bytes()))
}
fn relative(path: &str) -> Result<(), HostError> {
    if path.is_empty()
        || path.starts_with('/')
        || path.contains('\\')
        || path
            .split('/')
            .any(|p| p.is_empty() || p == "." || p == "..")
    {
        return Err(HostError::Save("记忆文件清单含非法相对路径".into()));
    }
    Ok(())
}
pub(super) fn directory(path: &Path) -> Result<(), HostError> {
    match fs::symlink_metadata(path) {
        Ok(m) if m.is_dir() && !m.file_type().is_symlink() => Ok(()),
        Ok(_) => Err(HostError::Save(format!(
            "存档目录不是实际目录：{}",
            path.display()
        ))),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => fs::create_dir(path)
            .map_err(|e| HostError::Save(format!("创建存档目录 {} 失败：{e}", path.display()))),
        Err(e) => Err(HostError::Save(format!(
            "检查存档目录 {} 失败：{e}",
            path.display()
        ))),
    }
}
fn parent_dirs(root: &Path, path: &str) -> Result<PathBuf, HostError> {
    relative(path)?;
    let mut result = root.to_path_buf();
    let pieces: Vec<_> = path.split('/').collect();
    for piece in &pieces[..pieces.len() - 1] {
        result.push(piece);
        directory(&result)?;
    }
    result.push(pieces.last().unwrap());
    if fs::symlink_metadata(&result).is_ok_and(|m| m.file_type().is_symlink() || !m.is_file()) {
        return Err(HostError::Save("记忆文件不能是符号链接或目录".into()));
    }
    Ok(result)
}
fn json<T: Serialize>(value: &T) -> Result<String, HostError> {
    serde_json::to_string(value).map_err(|e| HostError::Save(format!("编码记忆文件失败：{e}")))
}
/// 按行解析；出错时带上文件相对路径。
fn lines<T: serde::de::DeserializeOwned>(path: &str, bytes: &[u8]) -> Result<Vec<T>, HostError> {
    String::from_utf8(bytes.to_vec())
        .map_err(|e| HostError::Save(format!("记忆文件 {path} 不是 UTF-8：{e}")))?
        .lines()
        .filter(|l| !l.is_empty())
        .map(|l| {
            serde_json::from_str(l)
                .map_err(|e| HostError::Save(format!("记忆文件 {path} 解析失败：{e}")))
        })
        .collect()
}
fn parse<T: serde::de::DeserializeOwned>(path: &str, bytes: &[u8]) -> Result<T, HostError> {
    serde_json::from_slice(bytes)
        .map_err(|e| HostError::Save(format!("记忆文件 {path} 解析失败：{e}")))
}

/// 写过就不再变的文件：折叠归档、上下文来源、笔记的旧版本。清单条目记在流水里。
fn settled(path: &str) -> bool {
    [
        "conversations/",
        "revisions/",
        ".state/history/",
        ".state/context/",
    ]
    .iter()
    .any(|folder| path.starts_with(folder))
}

/// 记忆目录：缺省存档旁边的 residents/，别的存档名用 `<存档名>.residents`。
fn root_for(save: &Path) -> PathBuf {
    let folder = if save.file_name().is_some_and(|n| n == SAVE_FILE_NAME) {
        "residents".into()
    } else {
        format!("{}.residents", save.file_name().unwrap().to_string_lossy())
    };
    save.parent().unwrap().join(folder)
}

/// 一位村民已经暂存到哪。
#[derive(Clone, Default)]
struct Staged {
    /// 会话编号：换了会话就从头暂存
    session: u64,
    files: Files,
    /// 各笔记页已暂存的版本
    pages: BTreeMap<String, u64>,
    /// 笔记旧版本暂存了几条
    history: usize,
    /// 折叠归档、上下文来源各暂存到了第几号
    archives: u64,
    sources: u64,
    /// 记忆记录写进流水的版本：比它新的才要再写
    memory: u64,
}

impl Staged {
    /// 这份会话是接着上次暂存的那份往下走的：编号没换，各样只增的东西没有变少。
    fn continues(&self, s: &Session) -> bool {
        self.session == s.id
            && self.history <= s.notebook.history.len()
            && self.archives <= last_key(s.archives())
            && self.sources <= last_key(&s.input.sources)
            && self.memory <= s.memory.revision
    }
}

/// 按编号只增的表里最大的编号；空表是 0。
fn last_key<T>(map: &BTreeMap<u64, T>) -> u64 {
    map.keys().next_back().copied().unwrap_or(0)
}

/// 一次暂存的结果：新的清单、盘上还没有的文件版本，和提交成功后要记下的进度。
pub(super) struct Stage {
    /// 全部文件的清单：可读目录和旧版本的清理照它来
    pub manifest: Residents,
    /// 写进 world.json 的那部分清单：不含条目记在流水里的文件
    pub listed: Residents,
    pub objects: Vec<(String, Vec<u8>)>,
    staged: BTreeMap<String, Staged>,
}

pub(super) struct ResidentStore {
    /// 盘上已有、内容核对过的文件版本（按摘要）
    known: BTreeSet<String>,
    staged: BTreeMap<String, Staged>,
}

impl ResidentStore {
    pub(super) fn new() -> Self {
        Self {
            known: BTreeSet::new(),
            staged: BTreeMap::new(),
        }
    }

    /// 有人的记忆已经写进过流水，现在的会话却不是接着那份往下走的：流水得另起一份，
    /// 否则旧会话的记忆会在读档时混进新会话。
    pub(super) fn diverged(&self, state: Option<&RuntimeState>) -> bool {
        self.staged.iter().any(|(actor, staged)| {
            staged.memory > 0
                && !state
                    .and_then(|state| state.sessions.get(actor))
                    .is_some_and(|s| staged.continues(s))
        })
    }

    /// 暂存各位村民变了的记忆文件，新的记忆记录和清单条目排进流水。`fresh` 表示流水另起了
    /// 一份：全部从头暂存，记录和条目重新写一遍。
    pub(super) fn stage<'a>(
        &self,
        state: Option<&'a RuntimeState>,
        journal: &mut Vec<Line<'a>>,
        fresh: bool,
    ) -> Result<Stage, HostError> {
        let mut stage = Stage {
            manifest: BTreeMap::new(),
            listed: BTreeMap::new(),
            objects: Vec::new(),
            staged: BTreeMap::new(),
        };
        let mut queued = BTreeSet::new();
        for (actor, s) in state.iter().flat_map(|state| &state.sessions) {
            let mut next = match self.staged.get(actor) {
                Some(old) if !fresh && old.continues(s) => old.clone(),
                _ => Staged {
                    session: s.id,
                    ..Staged::default()
                },
            };
            let mut put = |next: &mut Staged, path: String, text: String| {
                let version = FileVersion {
                    hash: hash(text.as_bytes()),
                    bytes: text.len() as u64,
                };
                if !self.known.contains(&version.hash) && queued.insert(version.hash.clone()) {
                    stage
                        .objects
                        .push((version.hash.clone(), text.into_bytes()));
                }
                if next.files.get(&path) == Some(&version) {
                    return;
                }
                if settled(&path) {
                    journal.push(Line::File {
                        actor,
                        path: path.clone(),
                        version: version.clone(),
                    });
                }
                next.files.insert(path, version);
            };
            for (path, text) in agent::notebook::overview(s) {
                put(&mut next, path, text);
            }
            for page in s.notebook.pages.values() {
                if next.pages.get(&page.path) == Some(&page.revision) {
                    continue;
                }
                let (path, text) = agent::notebook::page_document(page);
                put(&mut next, path, text);
                let state_path = format!(".state/pages/{}.json", hash(page.path.as_bytes()));
                put(&mut next, state_path, json(page)?);
                next.pages.insert(page.path.clone(), page.revision);
            }
            for page in &s.notebook.history[next.history..] {
                let (path, text) = agent::notebook::revision_document(page);
                put(&mut next, path, text);
                let state_path = format!(".state/history/R{:06}.json", page.revision);
                put(&mut next, state_path, json(page)?);
            }
            next.history = s.notebook.history.len();
            for (id, messages) in s.archives().range(next.archives + 1..) {
                let (path, text) = agent::notebook::archive_document(*id, messages);
                put(&mut next, path, text);
            }
            next.archives = last_key(s.archives());
            for (id, value) in s.input.sources.range(next.sources + 1..) {
                put(
                    &mut next,
                    format!(".state/context/S{id:06}.json"),
                    json(value)?,
                );
            }
            next.sources = last_key(&s.input.sources);
            for record in &s.memory.records {
                if record.revision > next.memory {
                    journal.push(Line::Memory { actor, record });
                }
            }
            next.memory = s.memory.revision;
            let listed = next.files.iter().filter(|(path, _)| !settled(path));
            stage.listed.insert(
                actor.clone(),
                listed.map(|(path, v)| (path.clone(), v.clone())).collect(),
            );
            stage.manifest.insert(actor.clone(), next.files.clone());
            stage.staged.insert(actor.clone(), next);
        }
        Ok(stage)
    }

    /// 暂存的东西已经随 world.json 提交：盘上现有的版本就是清单里的那些。
    pub(super) fn commit(&mut self, stage: Stage) {
        self.known = stage
            .manifest
            .values()
            .flat_map(|files| files.values().map(|v| v.hash.clone()))
            .collect();
        self.staged = stage.staged;
    }

    /// 读档：按清单把各位村民的记忆文件读回会话。旧存档（v5 及以前）的记忆记录也在清单里，
    /// 照旧读回；v6 起记录在流水里，由调用方装上。
    pub(super) fn hydrate(
        &mut self,
        files: &ResidentFiles,
        manifest: &Residents,
        saved: &mut Option<AgentSave>,
    ) -> Result<(), HostError> {
        let Some(saved) = saved else {
            if manifest.is_empty() {
                return Ok(());
            }
            return Err(HostError::Save("记忆清单缺少对应 Agent".into()));
        };
        if manifest.len() != saved.runtime.sessions.len() {
            return Err(HostError::Save("村民记忆目录与世界人口不一致".into()));
        }
        for (actor, s) in &mut saved.runtime.sessions {
            let listed = manifest
                .get(actor)
                .ok_or_else(|| HostError::Save("村民记忆清单缺失".into()))?;
            if !s.memory.records.is_empty()
                || !s.notebook.pages.is_empty()
                || !s.archives().is_empty()
                || !s.notebook.history.is_empty()
                || !s.input.sources.is_empty()
            {
                return Err(HostError::Save(
                    "v2 存档混入内嵌记忆，拒绝混用两个版本".into(),
                ));
            }
            for required in ["INDEX.md", "current.md", "self.md"] {
                if !listed.contains_key(required) {
                    return Err(HostError::Save("村民目录缺少必要索引文件".into()));
                }
            }
            for (path, version) in listed {
                relative(path)?;
                let bytes = files.read(version)?;
                self.known.insert(version.hash.clone());
                if path.starts_with(".state/context/S") {
                    let id = path
                        .trim_start_matches(".state/context/S")
                        .trim_end_matches(".json")
                        .parse::<u64>()
                        .map_err(|e| HostError::Save(format!("上下文来源 {path} 编号无效：{e}")))?;
                    if id == 0
                        || id > s.input.next_source
                        || s.input.sources.insert(id, parse(path, &bytes)?).is_some()
                    {
                        return Err(HostError::Save(format!(
                            "上下文来源 {path} 编号重复或超出范围"
                        )));
                    }
                } else if path.starts_with(".state/records/") {
                    s.memory
                        .records
                        .extend(lines::<MemoryRecord>(path, &bytes)?);
                } else if path.starts_with(".state/pages/") {
                    let p: Page = parse(path, &bytes)?;
                    if s.notebook.pages.insert(p.path.clone(), p).is_some() {
                        return Err(HostError::Save(format!("主题路径重复：{path}")));
                    }
                } else if path.starts_with(".state/history/") {
                    s.notebook.history.push(parse(path, &bytes)?);
                } else if path.starts_with("conversations/C") {
                    let id = path
                        .trim_start_matches("conversations/C")
                        .trim_end_matches(".jsonl")
                        .parse::<u64>()
                        .map_err(|e| HostError::Save(format!("对话归档 {path} 编号无效：{e}")))?;
                    s.restore_archive(id, lines(path, &bytes)?)?;
                }
            }
            s.memory.records.sort_by_key(|r| r.memory_id);
            s.notebook.history.sort_by_key(|p| p.revision);
        }
        Ok(())
    }

    /// 读回来的是流水另存的存档（v6 起）：各人的记忆记录和 `recorded` 里的清单条目都已经在
    /// 盘上，从这里接着往下写。笔记页、归档这些不记进度：开镇后第一次存盘重拼一遍，内容没变就
    /// 什么也不写；该记在流水里却没记上的条目，那一次补记。
    pub(super) fn adopt(&mut self, recorded: &Residents, state: Option<&RuntimeState>) {
        self.staged = state
            .iter()
            .flat_map(|state| &state.sessions)
            .map(|(actor, s)| {
                let staged = Staged {
                    session: s.id,
                    files: recorded.get(actor).cloned().unwrap_or_default(),
                    memory: s.memory.revision,
                    ..Staged::default()
                };
                (actor.clone(), staged)
            })
            .collect();
    }

    /// 存档清单里条目该记在流水里的文件先拿掉：只有流水里读到的才算记过。
    pub(super) fn unsettled(manifest: &Residents) -> Residents {
        let keep = |files: &Files| {
            let listed = files.iter().filter(|(path, _)| !settled(path));
            listed.map(|(path, v)| (path.clone(), v.clone())).collect()
        };
        manifest
            .iter()
            .map(|(actor, files)| (actor.clone(), keep(files)))
            .collect()
    }

    /// 读回来的是没有流水的旧存档：下一次存盘把全部记忆文件重新暂存，记录全部写进流水。
    pub(super) fn forget(&mut self) {
        self.staged.clear();
    }

    /// 不知道上一次写到了哪一步：暂存进度作废，盘上有哪些文件版本也不作数，下一次逐个核对。
    pub(super) fn distrust(&mut self) {
        self.staged.clear();
        self.known.clear();
    }
}

/// 记忆目录里落到文件上的那一半：读写不可变版本、对齐可读目录。
pub(super) struct ResidentFiles {
    root: PathBuf,
    published: Option<Residents>,
}

impl ResidentFiles {
    pub(super) fn new(save: &Path) -> Self {
        Self {
            root: root_for(save),
            published: None,
        }
    }
    fn prepare(&self) -> Result<(), HostError> {
        directory(&self.root)?;
        directory(&self.root.join(OBJECTS_DIR))
    }
    /// 写一个不可变版本；已经有了就核对内容。
    pub(super) fn put(&self, key: &str, bytes: &[u8]) -> Result<(), HostError> {
        self.prepare()?;
        let path = self.root.join(OBJECTS_DIR).join(key);
        if !path.exists() {
            return atomic_write(&path, bytes);
        }
        let version = FileVersion {
            hash: key.into(),
            bytes: bytes.len() as u64,
        };
        if self.read(&version)? != bytes {
            return Err(HostError::Save("记忆内容校验不一致".into()));
        }
        Ok(())
    }
    fn read(&self, version: &FileVersion) -> Result<Vec<u8>, HostError> {
        if version.hash.len() != 64 || !version.hash.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(HostError::Save("记忆版本编号无效".into()));
        }
        let objects = self.root.join(OBJECTS_DIR);
        for directory in [&self.root, &objects] {
            let m = fs::symlink_metadata(directory).map_err(|e| {
                HostError::Save(format!("缺少记忆目录 {}：{e}", directory.display()))
            })?;
            if !m.is_dir() || m.file_type().is_symlink() {
                return Err(HostError::Save(format!(
                    "记忆目录 {} 不能是符号链接",
                    directory.display()
                )));
            }
        }
        let path = objects.join(&version.hash);
        let meta = fs::symlink_metadata(&path)
            .map_err(|e| HostError::Save(format!("缺少记忆版本 {}：{e}", path.display())))?;
        if !meta.is_file() || meta.file_type().is_symlink() || meta.len() != version.bytes {
            return Err(HostError::Save(format!(
                "记忆文件 {} 长度或类型无效",
                path.display()
            )));
        }
        let bytes = fs::read(&path)
            .map_err(|e| HostError::Save(format!("读取 {} 失败：{e}", path.display())))?;
        if hash(&bytes) != version.hash {
            return Err(HostError::Save(format!(
                "记忆版本 {} 校验失败，保留现场并停止恢复",
                path.display()
            )));
        }
        Ok(bytes)
    }
    /// 备份保留原 world.json 与它引用的全部记忆对象，避免后续清理使旧档失去原文。
    pub(super) fn backup(
        &self,
        root: &Path,
        world: &[u8],
        manifest: &Residents,
    ) -> Result<(), HostError> {
        directory(root)?;
        let target = root.join(SAVE_FILE_NAME);
        if target.exists()
            && fs::read(&target)
                .map_err(|e| HostError::Save(format!("读取 {} 失败：{e}", target.display())))?
                != world
        {
            return Err(HostError::Save(format!(
                "旧档备份目录 {} 已存在其他版本，请保留备份并另选存档副本",
                root.display()
            )));
        }
        let residents = root.join("residents");
        directory(&residents)?;
        let objects = residents.join(OBJECTS_DIR);
        directory(&objects)?;
        for files in manifest.values() {
            for version in files.values() {
                atomic_write(&objects.join(&version.hash), &self.read(version)?)?;
            }
        }
        atomic_write(&target, world)
    }

    /// 仅在 world.json 已提交后投影可读目录。断电留下旧投影时，下次恢复按清单重建。
    pub(super) fn publish(&mut self, manifest: &Residents) -> Result<(), HostError> {
        if self.published.as_ref() == Some(manifest) {
            return Ok(());
        }
        if manifest.is_empty() && !self.root.exists() {
            return Ok(());
        }
        self.prepare()?;
        let mut keep = BTreeSet::new();
        let mut folders = BTreeSet::new();
        for (actor, files) in manifest {
            let name = component(actor);
            folders.insert(name.clone());
            let root = self.root.join(&name);
            directory(&root)?;
            let unchanged = self.published.as_ref().and_then(|m| m.get(actor)) == Some(files);
            for (path, version) in files {
                keep.insert(version.hash.clone());
                if unchanged {
                    continue;
                }
                let dest = parent_dirs(&root, path)?;
                let cached = self
                    .published
                    .as_ref()
                    .and_then(|m| m.get(actor))
                    .and_then(|f| f.get(path))
                    == Some(version);
                let same = cached
                    || fs::read(&dest)
                        .is_ok_and(|b| b.len() as u64 == version.bytes && hash(&b) == version.hash);
                if !same {
                    atomic_write(&dest, &self.read(version)?)?;
                }
            }
            if !unchanged {
                clean_projection(&root, &root, &files.keys().cloned().collect())?;
            }
        }
        for entry in list_dir(&self.root)? {
            let name = entry.file_name().to_string_lossy().to_string();
            if name != OBJECTS_DIR && !folders.contains(&name) {
                remove_managed(&entry.path())?;
            }
        }
        for entry in list_dir(&self.root.join(OBJECTS_DIR))? {
            let key = entry.file_name().to_string_lossy().to_string();
            if !keep.contains(&key) {
                remove_managed(&entry.path())?;
            }
        }
        self.published = Some(manifest.clone());
        Ok(())
    }
}
pub(super) fn list_dir(dir: &Path) -> Result<Vec<fs::DirEntry>, HostError> {
    fs::read_dir(dir)
        .map_err(|e| HostError::Save(format!("读取目录 {} 失败：{e}", dir.display())))?
        .map(|entry| {
            entry.map_err(|e| HostError::Save(format!("读取目录 {} 失败：{e}", dir.display())))
        })
        .collect()
}
pub(super) fn remove_managed(path: &Path) -> Result<(), HostError> {
    let meta = fs::symlink_metadata(path)
        .map_err(|e| HostError::Save(format!("检查 {} 失败：{e}", path.display())))?;
    // 删除链接本身，不跟随；本目录是程序专用数据目录。
    if meta.is_dir() && !meta.file_type().is_symlink() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    }
    .map_err(|e| HostError::Save(format!("删除 {} 失败：{e}", path.display())))
}
fn clean_projection(root: &Path, dir: &Path, keep: &BTreeSet<String>) -> Result<(), HostError> {
    for entry in list_dir(dir)? {
        let path = entry.path();
        let meta = fs::symlink_metadata(&path)
            .map_err(|e| HostError::Save(format!("检查 {} 失败：{e}", path.display())))?;
        if meta.is_dir() && !meta.file_type().is_symlink() {
            clean_projection(root, &path, keep)?;
            if list_dir(&path)?.is_empty() {
                fs::remove_dir(&path)
                    .map_err(|e| HostError::Save(format!("删除 {} 失败：{e}", path.display())))?;
            }
        } else {
            let relative = path.strip_prefix(root).map_err(|e| {
                HostError::Save(format!("路径 {} 不在记忆目录内：{e}", path.display()))
            })?;
            // 清单里的路径按 / 分隔；Windows 的路径分隔符是 \，逐段拼回来再比
            let key = relative
                .iter()
                .map(|part| part.to_string_lossy())
                .collect::<Vec<_>>()
                .join("/");
            if !keep.contains(&key) {
                remove_managed(&path)?;
            }
        }
    }
    Ok(())
}
