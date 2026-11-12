//! 世界检查点与各村民文件版本共同提交；坏档不会被新世界覆盖。
//! 存档分三处：world.json 是当前状态，也是提交点；只增不改的历史追加在流水里（history.rs）；
//! 村民的笔记、归档这些文件在记忆目录里（residents.rs）。world.json 的清单记着后两处提交到了哪。
//! 存盘分两步：主线程抓一份当前状态和上次提交之后新增的历史，花费只跟变了多少有关；落到文件上
//! 的动作（`Disk::commit`）平时交给后台线程，命令和事务要当场知道成没成，就在主线程写完再返回。
use crate::HostError;
use crate::{
    agent_worker::AgentSave,
    fnv::{fnv1a, FNV_OFFSET},
    population::Population,
    world_settings::{valid_speed, WorldSettings},
};
use agent::{memory::MemoryRecord, runtime::RuntimeState};
use kernel::{
    history::{Archived, Record},
    World, WorldSnapshot,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, MutexGuard},
    thread::JoinHandle,
    time::{Duration, Instant},
};

mod history;
mod migration;
mod residents;
mod retired_commissions;
use migration::{Backup, SCHEMA_VERSION};
use residents::{ResidentFiles, ResidentStore, Residents};

/// 周期存盘隔多久一次。强杀或断电最多丢这么久的进度；命令、事务和正常退出都当场存。
pub const AUTOSAVE_INTERVAL: Duration = Duration::from_secs(30);
/// 存盘失败后隔多久再试。
const RETRY_INTERVAL: Duration = Duration::from_secs(1);
/// 缺省存档文件名；村民记忆目录与流水按它旁边的 residents/、history/ 放。
pub const SAVE_FILE_NAME: &str = "world.json";

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct SaveFile {
    #[serde(default)]
    world_settings: WorldSettings,
    schema_version: u32,
    world_key: String,
    speed: f64,
    world: WorldSnapshot,
    #[serde(default)]
    resident_agent: Option<AgentSave>,
    #[serde(default)]
    resident_files: Residents,
    /// v3 起的人口登记；旧档没有，由启动配置迁移。
    #[serde(default)]
    population: Option<Population>,
    /// v6 起：流水各卷已提交的长度和摘要。之前的存档没有流水，历史都在 world 和记忆文件里。
    /// 流水里除了历史，还有记忆目录里写过就不再变的文件的清单条目：读档时并回 `resident_files`。
    #[serde(default)]
    history: history::Manifest,
}

/// 恢复结果：速度、世界设定、Agent 会话与人口登记（旧档为 None，交给调用者迁移）。
/// Agent 会话只是存档里的数据，恢复成运行器由调用方做一次，这里不重复恢复。
/// 世界设定交给调用方保管，存盘时再传回来，存档对象自己不留副本。
#[derive(Debug)]
pub struct Restored {
    pub speed: f64,
    pub world_settings: WorldSettings,
    pub agent: Option<AgentSave>,
    pub population: Option<Population>,
}

pub struct SaveStore {
    path: PathBuf,
    world_key: String,
    /// 规范化后的场景定义；v1/v2 旧档的兼容标识还要把人物身份算进去，从它重新算。
    definition: Option<serde_json::Value>,
    /// 旧档兼容标识表的路径；只在遇到身体字段升级前的存档时读取。
    compatibility: Option<PathBuf>,
    _lock: File,
    /// 上次提交的 world.json 内容；这次的一样就不重写。
    previous: Arc<Vec<u8>>,
    /// 已经写进流水的世界历史、流水和记忆目录各自提交到了哪：提交成功才往前挪。
    archived: Archived,
    journal: history::Journal,
    residents: ResidentStore,
    /// 落到文件上的那一半；后台写盘时由写盘线程拿着锁。
    disk: Arc<Mutex<Disk>>,
    /// 后台正在写的那一次。同时只有一次：它写完之前不抓下一份。
    writing: Option<Writing>,
    /// 周期存盘隔多久一次，下一次什么时候到点。
    interval: Duration,
    due: Instant,
    /// 上次提交后可读目录没整理成，下次检查点补做。
    untidy: bool,
    /// 写盘线程中途异常退出过，不知道它写到了哪一步：下一次不接着盘上的写，流水另起一卷、
    /// 记忆文件全部重新核对，等新的 world.json 提交了再清旧的。
    unsure: bool,
}

/// 存档落到文件上的那一半：读写都不碰世界，可以在后台线程做。
struct Disk {
    path: PathBuf,
    residents: ResidentFiles,
    history: PathBuf,
}

/// 一次提交要落盘的全部东西。
struct Commit {
    append: Option<history::Append>,
    /// 盘上还没有的记忆文件版本（摘要、内容）
    objects: Vec<(String, Vec<u8>)>,
    /// world.json 的新内容；None 表示内容没变，只补做上次没做成的整理
    world: Option<Arc<Vec<u8>>>,
    /// 提交之后记忆目录和流水的清单：可读目录、用不着的旧文件照它们整理
    manifest: Residents,
    journal: history::Manifest,
}

/// 抓好的一次存盘里，提交成功之后才记下的进度。
struct Pending {
    world: Option<Arc<Vec<u8>>>,
    /// 流水另起了一份（换了新世界）
    fresh: bool,
    records: Vec<Record>,
    journal: history::Planned,
    residents: residents::Stage,
}

struct Writing {
    thread: JoinHandle<Result<bool, HostError>>,
    pending: Pending,
}

/// 写盘线程出了意外也不让锁一直坏着：`Disk` 里只有路径和「整理到哪了」的记号。
fn lock(disk: &Mutex<Disk>) -> MutexGuard<'_, Disk> {
    disk.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

impl Disk {
    /// 先写流水和新的记忆文件版本，最后替换 world.json（提交点），再整理可读目录。
    /// 返回整理有没有做成：没做成不算存盘失败，下次检查点补做。
    fn commit(&mut self, commit: &Commit) -> Result<bool, HostError> {
        if let Some(append) = &commit.append {
            append.write()?;
        }
        for (key, bytes) in &commit.objects {
            self.residents.put(key, bytes)?;
        }
        if let Some(bytes) = &commit.world {
            // 换名之后目录 fsync 仍可能失败。已经换成新内容的提交不可再按“未提交”回滚内存。
            if let Some(error) =
                replace(&self.path, bytes).map_err(|e| write_failed(&self.path, e))?
            {
                eprintln!(
                    "[host] 存档已替换，但目录同步失败，断电持久性未确认：{}",
                    write_failed(&self.path, error)
                );
            }
        }
        // world.json、流水与不可变对象已经提交；可读目录是可重建投影。
        // 投影失败不能让命令回滚到已不再属于磁盘的旧世界，下一次检查点会重试。
        match self.tidy(&commit.manifest, &commit.journal) {
            Ok(()) => Ok(true),
            Err(error) => {
                eprintln!("[host] 存档已提交，居民可读目录待重建：{error}");
                Ok(false)
            }
        }
    }

    /// 可读目录对齐清单；清单里没有的旧记忆版本、旧流水卷和没提交成的流水尾巴删掉。
    fn tidy(&mut self, manifest: &Residents, journal: &history::Manifest) -> Result<(), HostError> {
        self.residents.publish(manifest)?;
        history::tidy(&self.history, journal)
    }
}

/// 独立运行数据目录里的存档文件。
pub fn default_save_path() -> Result<PathBuf, HostError> {
    Ok(crate::application::data_root()?.join(SAVE_FILE_NAME))
}

/// 规范化的场景定义：道具按目录展开、忽略排版、去掉只影响新加入者的入口。
fn world_definition(
    topology: &str,
    catalog: &kernel::props::Catalog,
) -> Result<serde_json::Value, HostError> {
    kernel::Topology::from_json(topology, catalog)?;
    let mut definition = catalog.world_definition(topology)?;
    // 入口只影响新加入者；已有村民恢复其保存的位置。
    if let Some(object) = definition.as_object_mut() {
        object.remove("entry");
    }
    Ok(definition)
}

/// FNV-1a 检测场景定义变化（不用于安全认证）。
/// `resident` 只有旧档（v1/v2）的兼容标识才带人物身份；v3 起人口是存档自己的状态，传空。
fn key_of(definition: &serde_json::Value, resident: &[&str]) -> String {
    let text = serde_json::json!([definition, resident]).to_string();
    format!("physiology-v1:{:016x}", fnv1a(text.as_bytes(), FNV_OFFSET))
}

pub fn world_key(
    topology: &str,
    resident: &[&str],
    catalog: &kernel::props::Catalog,
) -> Result<String, HostError> {
    Ok(key_of(&world_definition(topology, catalog)?, resident))
}

impl SaveStore {
    /// 用给定标识打开；旧档兼容标识不可用（测试与工具用）。
    pub fn open(path: &Path, world_key: String) -> Result<Self, HostError> {
        let path = std::path::absolute(path).map_err(|e| HostError::Save(e.to_string()))?;
        let parent = path
            .parent()
            .ok_or_else(|| HostError::Save("存档需要文件路径".into()))?;
        fs::create_dir_all(parent)
            .map_err(|e| HostError::Save(format!("创建存档目录失败：{e}")))?;
        let path = parent
            .canonicalize()
            .map_err(|e| HostError::Save(e.to_string()))?
            .join(
                path.file_name()
                    .ok_or_else(|| HostError::Save("存档需要文件名".into()))?,
            );
        if fs::symlink_metadata(&path).is_ok_and(|m| m.file_type().is_symlink()) {
            return Err(HostError::Save(
                "存档文件不能是符号链接，请使用实际文件路径".into(),
            ));
        }
        let lock = private_file(&sidecar(&path, ".lock"), false)
            .map_err(|e| HostError::Save(format!("打开存档锁失败：{e}")))?;
        crate::process::lock_save(&lock).map_err(|e| {
            HostError::Save(format!(
                "无法独占存档 {}，可能有另一个 host 正在使用：{e}",
                path.display()
            ))
        })?;
        let disk = Disk {
            residents: ResidentFiles::new(&path),
            history: history::dir_for(&path),
            path: path.clone(),
        };
        Ok(Self {
            journal: history::Journal::new(&path),
            residents: ResidentStore::new(),
            disk: Arc::new(Mutex::new(disk)),
            path,
            world_key,
            definition: None,
            compatibility: None,
            _lock: lock,
            previous: Arc::new(Vec::new()),
            archived: Archived::default(),
            writing: None,
            interval: AUTOSAVE_INTERVAL,
            due: Instant::now() + AUTOSAVE_INTERVAL,
            untidy: false,
            unsure: false,
        })
    }

    /// 换一个周期存盘的间隔（缺省 `AUTOSAVE_INTERVAL`）。
    pub fn set_autosave(&mut self, interval: Duration) {
        self.interval = interval;
        self.due = Instant::now() + interval;
    }

    /// 按场景定义打开：标识从定义算出，v1/v2 旧档按含人物身份的兼容标识识别。
    /// `compatibility` 是旧档兼容标识表，遇到身体字段升级前的存档才读。
    pub fn open_world(
        path: &Path,
        topology: &str,
        catalog: &kernel::props::Catalog,
        compatibility: &Path,
    ) -> Result<Self, HostError> {
        let definition = world_definition(topology, catalog)?;
        let mut store = Self::open(path, key_of(&definition, &[]))?;
        store.definition = Some(definition);
        store.compatibility = Some(compatibility.to_path_buf());
        Ok(store)
    }

    /// 兼容标识表原文；没有配置路径或文件缺失都是错误，不会把旧档当成不匹配悄悄拒绝。
    fn compatibility_table(&self) -> Result<String, HostError> {
        let path = self
            .compatibility
            .as_ref()
            .ok_or_else(|| HostError::Save("此存档打开方式不支持旧档兼容标识表".into()))?;
        fs::read_to_string(path)
            .map_err(|e| HostError::Save(format!("读取兼容标识表 {} 失败：{e}", path.display())))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// 只有不存在才返回 None；错误向上传递，阻止新世界覆盖旧档。
    pub fn restore_bundle(&mut self, world: &mut World) -> Result<Option<Restored>, HostError> {
        // 读档只在开镇时做，照理没有写盘在途；有就等它写完再读
        let _ = self.finish_writing(true);
        let bytes = match fs::read(&self.path) {
            Ok(bytes) => bytes,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(e) => {
                return Err(HostError::Save(format!(
                    "读取存档 {} 失败：{e}",
                    self.path.display()
                )))
            }
        };
        let value: serde_json::Value = serde_json::from_slice(&bytes).map_err(|e| {
            HostError::Save(format!(
                "存档 {} 损坏或格式不兼容，原文件已保留：{e}",
                self.path.display()
            ))
        })?;
        let migrated = migration::migrate(value)?;
        let mut saved = migrated.file;
        let legacy = migrated.from_version < 3; // v3 起身份已由人口登记单独管理；v4 不改变地图标识。
        self.check_identity(
            &saved,
            legacy,
            migrated.backups.contains(&Backup::Physiology),
        )?;
        if !valid_speed(saved.speed) {
            return Err(HostError::Save("存档速度无效，原文件已保留".into()));
        }
        // v6 起历史在流水里：读回来核对摘要，世界的装回快照，记忆记录装回各人的会话。
        // 之前的存档清单是空的，历史本来就在 world.json 和记忆文件里，下面照旧读。
        let (lines, tail) = self.journal.read(&saved.history)?;
        let mut records = Vec::new();
        let mut memories: BTreeMap<String, BTreeMap<u64, MemoryRecord>> = BTreeMap::new();
        // 已经记下的清单条目：world.json 里列着的，加上流水里读到的（写过就不再变的那些文件）
        let mut recorded = ResidentStore::unsettled(&saved.resident_files);
        for line in lines {
            match line {
                history::Read::World(record) => records.push(record),
                history::Read::File(actor, path, version) => {
                    let listed = recorded.entry(actor.clone()).or_default();
                    listed.insert(path.clone(), version.clone());
                    let files = saved.resident_files.entry(actor).or_default();
                    files.insert(path, version);
                }
                // 改写过的记录在流水里有好几行，后写的算数
                history::Read::Memory(actor, record) => {
                    memories
                        .entry(actor)
                        .or_default()
                        .insert(record.memory_id, *record);
                }
            }
        }
        // v1 的记忆内嵌在会话里，下一次检查点才拆成文件。
        if migrated.from_version >= 2 {
            self.residents.hydrate(
                &lock(&self.disk).residents,
                &saved.resident_files,
                &mut saved.resident_agent,
            )?;
        }
        attach_memories(&mut saved.resident_agent, memories)?;
        let archived = saved.world.attach(records)?;
        let weather_id = saved
            .population
            .as_ref()
            .map(|p| p.world_id.as_str())
            .unwrap_or(&saved.world_key);
        saved.world.migrate_weather(world.weather(), weather_id)?;
        world.restore_snapshot(saved.world)?;
        if world
            .weather()
            .map(|weather| weather.view.clone())
            .is_some_and(|v| v.world_id != weather_id)
        {
            return Err(HostError::Save(
                "天气所属世界与存档人口不一致，原文件已保留".into(),
            ));
        }
        if let Some(population) = &saved.population {
            population.validate_against(
                world,
                saved.resident_agent.as_ref().map(|a| &a.runtime.sessions),
            )?;
        }
        for backup in &migrated.backups {
            self.write_backup(backup, &bytes, &saved.resident_files, &saved.history)?;
        }
        if migrated.from_version >= 2 {
            lock(&self.disk).tidy(&saved.resident_files, &saved.history)?;
        }
        saved.world_settings.validate()?;
        // 读成了：之后的存盘从盘上这份接着写。旧存档没有流水，第一次存盘把全部历史写进去。
        let agent = saved.resident_agent.as_ref().map(|a| &a.runtime);
        if migrated.from_version >= 6 {
            self.residents.adopt(&recorded, agent);
        } else {
            self.residents.forget();
        }
        self.archived = archived;
        self.journal.adopt(saved.history, tail);
        self.previous = Arc::new(bytes);
        self.untidy = false;
        self.unsure = false;
        Ok(Some(Restored {
            speed: saved.speed,
            world_settings: saved.world_settings,
            agent: saved.resident_agent,
            population: saved.population,
        }))
    }

    /// 存档必须是同一张地图、同一套规则；旧档还把人物身份算进标识。
    fn check_identity(
        &self,
        saved: &SaveFile,
        legacy: bool,
        body_migrated: bool,
    ) -> Result<(), HostError> {
        let identities = saved.world.identities();
        let expected = match (&self.definition, legacy) {
            (Some(definition), true) => {
                let flat: Vec<&str> = identities
                    .iter()
                    .flat_map(|(id, home)| [id.as_str(), home.as_str()])
                    .collect();
                key_of(definition, &flat)
            }
            _ => self.world_key.clone(),
        };
        let known_upgrade = body_migrated
            && migration::known_upgrade(
                &self.compatibility_table()?,
                &saved.world_key,
                &self.world_key,
                legacy,
                &identities,
            )?;
        if saved.world_key != expected && !known_upgrade {
            return Err(HostError::Save(format!(
                "存档 {} 的版本、地图、规则或村民身份不匹配，原文件已保留；请使用匹配配置或 --save-file 指定新文件",
                self.path.display()
            )));
        }
        Ok(())
    }

    /// 迁移前把原始存档及其引用的记忆对象、流水完整留存。
    fn write_backup(
        &self,
        backup: &Backup,
        bytes: &[u8],
        files: &Residents,
        journal: &history::Manifest,
    ) -> Result<(), HostError> {
        let dir = sidecar(&self.path, backup.suffix());
        lock(&self.disk).residents.backup(&dir, bytes, files)?;
        history::backup(&self.path, &dir.join(SAVE_FILE_NAME), journal)?;
        if let Some(name) = backup.extra_file() {
            fs::write(dir.join(name), self.compatibility_table()?).map_err(|e| {
                HostError::Save(format!("写迁移备份 {} 失败：{e}", dir.join(name).display()))
            })?;
        }
        eprintln!("[host] {}：{}", backup.label(), dir.display());
        Ok(())
    }

    /// 存盘。`now` 为真：现在就存，写完才返回（命令、事务、退出）；为假：到点才存，抓一份状态
    /// 交给后台线程写，不等它。返回 true 表示这次调用确认了一次存盘写成（当场写完，或后台那次
    /// 写完了，或盘上本来就是这样）；后台那次失败，在它写完后的下一次调用里返回错误，过一会儿重试。
    /// `agent` 借用运行中的会话，不克隆：记忆文件和流水只取上次提交之后变了的。
    pub fn checkpoint_bundle(
        &mut self,
        world: &World,
        speed: f64,
        world_settings: &WorldSettings,
        population: Option<&Population>,
        agent: Option<&RuntimeState>,
        now: bool,
    ) -> Result<bool, HostError> {
        let mut saved = false;
        match self.finish_writing(now) {
            Some(Ok(())) => saved = true,
            // 当场存的这一次会把没写成的一并带上，以它的结果为准
            Some(Err(error)) if !now => {
                self.due = Instant::now() + RETRY_INTERVAL;
                return Err(error);
            }
            _ => {}
        }
        if self.writing.is_some() || (!now && Instant::now() < self.due) {
            return Ok(saved);
        }
        self.due = Instant::now() + self.interval;
        let captured = self
            .capture(world, speed, world_settings, population, agent)
            .inspect_err(|_| self.due = Instant::now() + RETRY_INTERVAL)?;
        let Some((commit, pending)) = captured else {
            return Ok(true);
        };
        if now {
            return self.write_now(&commit, pending);
        }
        let commit = Arc::new(commit);
        let (disk, job) = (Arc::clone(&self.disk), Arc::clone(&commit));
        let spawned = std::thread::Builder::new()
            .name("save".into())
            .spawn(move || lock(&disk).commit(&job));
        match spawned {
            Ok(thread) => {
                self.writing = Some(Writing { thread, pending });
                Ok(saved)
            }
            // 起不了线程就当场写
            Err(_) => self.write_now(&commit, pending),
        }
    }

    /// 抓一份要提交的东西：当前状态编成 world.json，上次提交之后新增的历史排进流水，变了的
    /// 记忆文件列出来。和盘上一模一样、也没有欠着的整理时返回 None。
    fn capture(
        &self,
        world: &World,
        speed: f64,
        world_settings: &WorldSettings,
        population: Option<&Population>,
        agent: Option<&RuntimeState>,
    ) -> Result<Option<(Commit, Pending)>, HostError> {
        // 世界重置过、或者会话换了人，就不是接着盘上那份流水往下走的：另起一份，全部历史重写。
        let continued = (!self.unsure && !self.residents.diverged(agent))
            .then(|| world.detach(&self.archived))
            .flatten();
        let fresh = continued.is_none();
        let detached = continued
            .or_else(|| world.detach(&Archived::default()))
            .ok_or_else(|| HostError::Save("拆不出世界的历史".into()))?;
        let mut lines: Vec<history::Line> = detached.records.iter().map(Into::into).collect();
        let mut stage = self.residents.stage(agent, &mut lines, fresh)?;
        let mut planned = self.journal.plan(&lines, fresh)?;
        drop(lines);
        let saved = SaveFile {
            world_settings: world_settings.clone(),
            schema_version: SCHEMA_VERSION,
            resident_files: stage.listed.clone(),
            world_key: self.world_key.clone(),
            speed,
            world: detached.snapshot,
            resident_agent: agent.map(|state| AgentSave {
                runtime: state.without_files(),
            }),
            population: population.cloned(),
            history: planned.manifest.clone(),
        };
        let bytes = serde_json::to_vec(&saved)
            .map_err(|e| HostError::Save(format!("编码存档失败：{e}")))?;
        let world = (self.unsure || bytes != *self.previous).then(|| Arc::new(bytes));
        if world.is_none() && !self.untidy {
            return Ok(None);
        }
        let commit = Commit {
            append: planned.append.take(),
            objects: std::mem::take(&mut stage.objects),
            world: world.clone(),
            manifest: stage.manifest.clone(),
            journal: saved.history,
        };
        let pending = Pending {
            world,
            fresh,
            records: detached.records,
            journal: planned,
            residents: stage,
        };
        Ok(Some((commit, pending)))
    }

    /// 在这个线程上把一次提交写完。
    fn write_now(&mut self, commit: &Commit, pending: Pending) -> Result<bool, HostError> {
        let result = lock(&self.disk).commit(commit);
        match result {
            Ok(tidy) => {
                self.settle(pending, tidy);
                Ok(true)
            }
            Err(error) => {
                self.due = Instant::now() + RETRY_INTERVAL;
                Err(error)
            }
        }
    }

    /// 后台那次写完了没有；`wait` 为真就等它写完。写成了记下进度；没在写或还没写完返回 None。
    fn finish_writing(&mut self, wait: bool) -> Option<Result<(), HostError>> {
        if !wait && !self.writing.as_ref()?.thread.is_finished() {
            return None;
        }
        let writing = self.writing.take()?;
        let result = writing.thread.join().unwrap_or_else(|_| {
            self.unsure = true;
            self.residents.distrust();
            self.journal.skip_segment();
            Err(HostError::Save("写盘线程异常退出".into()))
        });
        Some(result.map(|tidy| self.settle(writing.pending, tidy)))
    }

    /// 一次提交写成了：流水、记忆目录的进度往前挪，world.json 的内容记下来。
    fn settle(&mut self, pending: Pending, tidy: bool) {
        if pending.fresh {
            self.archived = Archived::default();
        }
        for record in &pending.records {
            self.archived.note(record);
        }
        self.journal.commit(pending.journal);
        self.residents.commit(pending.residents);
        if let Some(bytes) = pending.world {
            self.previous = bytes;
        }
        self.untidy = !tidy;
        self.unsure = false;
    }
}

impl Drop for SaveStore {
    /// 后台还在写就等它写完，再放开存档锁。
    fn drop(&mut self) {
        let _ = self.finish_writing(true);
    }
}

/// 流水里读回的记忆记录装回各人的会话（按编号排好）。
fn attach_memories(
    agent: &mut Option<AgentSave>,
    memories: BTreeMap<String, BTreeMap<u64, MemoryRecord>>,
) -> Result<(), HostError> {
    for (actor, records) in memories {
        let session = agent
            .as_mut()
            .and_then(|a| a.runtime.sessions.get_mut(&actor))
            .ok_or_else(|| HostError::Save(format!("流水里的记忆属于存档里没有的村民 {actor}")))?;
        if !session.memory.records.is_empty() {
            return Err(HostError::Save(
                "记忆记录同时在流水和记忆目录里，拒绝混用两个版本".into(),
            ));
        }
        session.memory.records = records.into_values().collect();
    }
    Ok(())
}

fn private_file(path: &Path, truncate: bool) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.create(true).write(true).truncate(truncate);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
    }
    options.open(path)
}

/// 全 host 唯一的原子写入：临时文件 + fsync + rename，再 fsync 目录；不跟随符号链接，
/// 文件权限 0600。父目录不存在时创建。
pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), HostError> {
    match replace(path, bytes) {
        Ok(None) => Ok(()),
        Ok(Some(error)) | Err(error) => Err(write_failed(path, error)),
    }
}

fn write_failed(path: &Path, error: io::Error) -> HostError {
    HostError::Io(format!("写入 {} 失败：{error}", path.display()))
}

/// 原子写入的两段：Err 是换名之前失败，目标文件没动；Ok(Some(错误)) 是已经换成新内容，
/// 只是目录落盘没确认。
fn replace(path: &Path, bytes: &[u8]) -> io::Result<Option<io::Error>> {
    let dir = match path.parent() {
        Some(dir) if !dir.as_os_str().is_empty() => dir,
        _ => Path::new("."),
    };
    fs::create_dir_all(dir)?;
    let temporary = sidecar(path, ".tmp");
    let mut file = private_file(&temporary, true)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    fs::rename(&temporary, path)?;
    #[cfg(unix)]
    if let Err(error) = File::open(dir).and_then(|dir| dir.sync_all()) {
        return Ok(Some(error));
    }
    Ok(None)
}

fn sidecar(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(suffix);
    PathBuf::from(name)
}
