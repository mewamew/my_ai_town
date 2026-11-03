//! world.json 中的内容哈希清单是提交点；可读目录是已提交文件的投影。
//! 新文件先写不可变版本，最后提交世界；中途退出不会把未来记忆带入旧世界。
use super::{atomic_write, SAVE_FILE_NAME};
use crate::agent_worker::AgentSave;
use crate::HostError;
use agent::{memory::MemoryRecord, notebook::Page};
use kernel::World;
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
pub(super) struct ResidentStore {
    root: PathBuf,
    verified: BTreeSet<String>,
    published: Option<Residents>,
    /// 上次暂存的每份文件（村民、路径）的正文与版本。存档每秒一次，记忆一多就是上千份、十几兆，
    /// 正文没变就沿用版本，不再整份重算 SHA-256；调试版里重算能占满主循环，世界时间跟着变慢。
    staged: BTreeMap<(String, String), (String, FileVersion)>,
}

fn hash(bytes: &[u8]) -> String {
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
fn directory(path: &Path) -> Result<(), HostError> {
    match fs::symlink_metadata(path) {
        Ok(m) if m.is_dir() && !m.file_type().is_symlink() => Ok(()),
        Ok(_) => Err(HostError::Save(format!(
            "记忆目录不是实际目录：{}",
            path.display()
        ))),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => fs::create_dir(path)
            .map_err(|e| HostError::Save(format!("创建记忆目录 {} 失败：{e}", path.display()))),
        Err(e) => Err(HostError::Save(format!(
            "检查记忆目录 {} 失败：{e}",
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
impl ResidentStore {
    pub(super) fn new(save: &Path) -> Self {
        let folder = if save.file_name().is_some_and(|n| n == SAVE_FILE_NAME) {
            "residents".into()
        } else {
            format!("{}.residents", save.file_name().unwrap().to_string_lossy())
        };
        Self {
            root: save.parent().unwrap().join(folder),
            verified: BTreeSet::new(),
            published: None,
            staged: BTreeMap::new(),
        }
    }
    fn prepare(&self) -> Result<(), HostError> {
        directory(&self.root)?;
        directory(&self.root.join(OBJECTS_DIR))
    }
    fn put(&mut self, bytes: &[u8]) -> Result<FileVersion, HostError> {
        let key = hash(bytes);
        let path = self.root.join(OBJECTS_DIR).join(&key);
        if !self.verified.contains(&key) {
            if path.exists() {
                let old = self.read(&FileVersion {
                    hash: key.clone(),
                    bytes: bytes.len() as u64,
                })?;
                if old != bytes {
                    return Err(HostError::Save("记忆内容校验不一致".into()));
                }
            } else {
                atomic_write(&path, bytes)?;
            }
            self.verified.insert(key.clone());
        }
        Ok(FileVersion {
            hash: key,
            bytes: bytes.len() as u64,
        })
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

    pub(super) fn stage(
        &mut self,
        world: &World,
        saved: &mut Option<AgentSave>,
    ) -> Result<Residents, HostError> {
        let Some(saved) = saved else {
            return Ok(BTreeMap::new());
        };
        self.prepare()?;
        let mut manifest = BTreeMap::new();
        let mut staged = BTreeMap::new();
        for (actor, s) in &mut saved.runtime.sessions {
            let mut docs = agent::notebook::documents(world, s);
            for record in std::mem::take(&mut s.memory.records) {
                let path = format!(
                    ".state/records/D{:03}.jsonl",
                    kernel::calendar::day_index(record.at) + 1
                );
                let body = docs.entry(path).or_default();
                body.push_str(&json(&record)?);
                body.push('\n');
            }
            for (path, page) in std::mem::take(&mut s.notebook.pages) {
                docs.insert(
                    format!(".state/pages/{}.json", hash(path.as_bytes())),
                    json(&page)?,
                );
            }
            for page in std::mem::take(&mut s.notebook.history) {
                docs.insert(
                    format!(".state/history/R{:06}.json", page.revision),
                    json(&page)?,
                );
            }
            s.take_archives();
            for (id, value) in std::mem::take(&mut s.input.sources) {
                docs.insert(format!(".state/context/S{id:06}.json"), json(&value)?);
            }
            let mut files = BTreeMap::new();
            for (path, text) in docs {
                let key = (actor.clone(), path);
                let version = match self.staged.remove(&key) {
                    Some((old, version)) if old == text => version,
                    _ => self.put(text.as_bytes())?,
                };
                files.insert(key.1.clone(), version.clone());
                staged.insert(key, (text, version));
            }
            manifest.insert(actor.clone(), files);
        }
        self.staged = staged;
        Ok(manifest)
    }
    pub(super) fn hydrate(
        &mut self,
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
            let files = manifest
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
                if !files.contains_key(required) {
                    return Err(HostError::Save("村民目录缺少必要索引文件".into()));
                }
            }
            for (path, version) in files {
                relative(path)?;
                let bytes = self.read(version)?;
                self.verified.insert(version.hash.clone());
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
            for (path, version) in files {
                keep.insert(version.hash.clone());
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
            clean_projection(&root, &root, &files.keys().cloned().collect())?;
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
                self.verified.remove(&key);
            }
        }
        self.published = Some(manifest.clone());
        Ok(())
    }
}
fn list_dir(dir: &Path) -> Result<Vec<fs::DirEntry>, HostError> {
    fs::read_dir(dir)
        .map_err(|e| HostError::Save(format!("读取目录 {} 失败：{e}", dir.display())))?
        .map(|entry| {
            entry.map_err(|e| HostError::Save(format!("读取目录 {} 失败：{e}", dir.display())))
        })
        .collect()
}
fn remove_managed(path: &Path) -> Result<(), HostError> {
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
