//! 流水：只增不改的历史——内核的事件、过完的日子、做完的动作组、结束了的互动，村民的记忆
//! 记录，和记忆目录里写过就不再变的文件的清单——一行一条，追加写在存档旁边的 history/ 里，
//! 不随 world.json 每次重写。
//! world.json 的清单记着每一卷已提交的长度和摘要，它才是提交点：文件里超出的部分是没提交成的
//! 尾巴，读档时不看，下次写之前截掉。只有最后一卷会再变长。
use super::residents::{directory, list_dir, remove_managed, FileVersion};
use super::{private_file, SAVE_FILE_NAME};
use crate::HostError;
use agent::memory::MemoryRecord;
use kernel::{history::Record, journal::DayRecord};
use protocol::{ActionGroup, Interaction, WorldFact};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};

/// 一卷写到这么大就另起一卷。只在两次提交之间换卷，一次提交的内容不拆开。
const SEGMENT_BYTES: u64 = 4 * 1024 * 1024;

/// world.json 里的流水清单。
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Manifest {
    /// 下一卷的编号。卷号只增不重用：换了新世界另起流水时，旧卷留到新存档提交之后才删。
    next: u64,
    segments: Vec<Segment>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Segment {
    id: u64,
    /// 已提交的长度，和这一段内容的 SHA-256
    bytes: u64,
    hash: String,
}

/// 流水里的一行，写的时候：借用世界和会话里的原件，不另拷一份。
#[derive(Serialize)]
#[serde(rename_all = "snake_case")]
pub(super) enum Line<'a> {
    Event {
        actor: &'a str,
        fact: &'a WorldFact,
    },
    Day {
        actor: &'a str,
        day: &'a DayRecord,
    },
    Actions {
        actor: &'a str,
        group: &'a ActionGroup,
    },
    Interaction {
        interaction: &'a Interaction,
    },
    /// 村民的一条记忆记录。记录会被改写（修正、合并来源），改过就再写一行，同一编号后写的算数。
    Memory {
        actor: &'a str,
        record: &'a MemoryRecord,
    },
    /// 记忆目录里一份写过就不再变的文件（折叠归档、上下文来源、笔记的旧版本）的清单条目：
    /// 这类文件越攒越多，清单不放 world.json。同一路径后写的算数。
    File {
        actor: &'a str,
        path: String,
        version: FileVersion,
    },
}

/// 流水里的一行，读回来的时候。变体和字段名跟 `Line` 一一对应，是同一种写法。
#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum Stored {
    Event {
        actor: String,
        fact: WorldFact,
    },
    Day {
        actor: String,
        day: DayRecord,
    },
    Actions {
        actor: String,
        group: ActionGroup,
    },
    Interaction {
        interaction: Box<Interaction>,
    },
    Memory {
        actor: String,
        record: Box<MemoryRecord>,
    },
    File {
        actor: String,
        path: String,
        version: FileVersion,
    },
}

impl<'a> From<&'a Record> for Line<'a> {
    fn from(record: &'a Record) -> Self {
        match record {
            Record::Event { actor, fact } => Line::Event { actor, fact },
            Record::Day { actor, day } => Line::Day { actor, day },
            Record::Actions { actor, group } => Line::Actions { actor, group },
            Record::Interaction(interaction) => Line::Interaction { interaction },
        }
    }
}

/// 读回来的一行：世界的历史，某位村民的一条记忆，或者他记忆目录里一份文件的清单条目。
pub(super) enum Read {
    World(Record),
    Memory(String, Box<MemoryRecord>),
    File(String, String, FileVersion),
}

impl From<Stored> for Read {
    fn from(line: Stored) -> Self {
        match line {
            Stored::Event { actor, fact } => Read::World(Record::Event { actor, fact }),
            Stored::Day { actor, day } => Read::World(Record::Day { actor, day }),
            Stored::Actions { actor, group } => Read::World(Record::Actions { actor, group }),
            Stored::Interaction { interaction } => Read::World(Record::Interaction(interaction)),
            Stored::Memory { actor, record } => Read::Memory(actor, record),
            Stored::File {
                actor,
                path,
                version,
            } => Read::File(actor, path, version),
        }
    }
}

/// 一次提交要往流水文件里写的东西。
pub(super) struct Append {
    path: PathBuf,
    /// 从文件的这个位置（已提交的长度）接着写
    offset: u64,
    bytes: Vec<u8>,
}

impl Append {
    pub(super) fn write(&self) -> Result<(), HostError> {
        let failed = |e: std::io::Error| {
            HostError::Save(format!("写流水 {} 失败：{e}", self.path.display()))
        };
        let dir = self.path.parent().expect("流水文件在 history 目录里");
        directory(dir)?;
        let mut file = private_file(&self.path, false).map_err(failed)?;
        let length = file.metadata().map_err(failed)?.len();
        if length < self.offset {
            return Err(HostError::Save(format!(
                "流水 {} 比存档记的短（{length} < {}），原文件已保留",
                self.path.display(),
                self.offset
            )));
        }
        // 上次没提交成的尾巴截掉，从已提交的长度接着写
        file.set_len(self.offset).map_err(failed)?;
        file.seek(SeekFrom::Start(self.offset)).map_err(failed)?;
        file.write_all(&self.bytes).map_err(failed)?;
        file.sync_all().map_err(failed)?;
        #[cfg(unix)]
        if self.offset == 0 {
            fs::File::open(dir)
                .and_then(|d| d.sync_all())
                .map_err(failed)?;
        }
        Ok(())
    }
}

/// 排好的一次追加，和它提交成功之后流水的样子。
pub(super) struct Planned {
    pub append: Option<Append>,
    pub manifest: Manifest,
    tail: Sha256,
}

/// 流水已提交到哪。只在主线程用；文件由 `Append::write` 去写。
pub(super) struct Journal {
    dir: PathBuf,
    manifest: Manifest,
    /// 最后一卷已提交内容的摘要算到了哪：接着往后算，不用为了追加几行重读整卷
    tail: Sha256,
}

impl Journal {
    pub(super) fn new(save: &Path) -> Self {
        Self {
            dir: dir_for(save),
            manifest: Manifest::default(),
            tail: Sha256::new(),
        }
    }

    fn file(&self, id: u64) -> PathBuf {
        self.dir.join(format!("{id:06}.jsonl"))
    }

    /// 把清单里的流水全部读回来，逐卷核对长度和摘要。读到的内容和 `adopt` 要的接续状态一起返回。
    pub(super) fn read(&self, manifest: &Manifest) -> Result<(Vec<Read>, Sha256), HostError> {
        let mut lines = Vec::new();
        let mut tail = Sha256::new();
        let mut previous = 0;
        for segment in &manifest.segments {
            if segment.id <= previous || segment.id >= manifest.next {
                return Err(HostError::Save("流水清单的卷号无效，原文件已保留".into()));
            }
            previous = segment.id;
            let path = self.file(segment.id);
            let broken = |what: &str| {
                HostError::Save(format!(
                    "流水 {} {what}，保留现场并停止恢复",
                    path.display()
                ))
            };
            let folder = fs::symlink_metadata(&self.dir).map_err(|_| broken("所在目录缺失"))?;
            if !folder.is_dir() || folder.file_type().is_symlink() {
                return Err(broken("所在目录不是实际目录"));
            }
            let meta = fs::symlink_metadata(&path).map_err(|_| broken("缺失"))?;
            if !meta.is_file() || meta.file_type().is_symlink() || meta.len() < segment.bytes {
                return Err(broken("类型不对或比存档记的短"));
            }
            let mut bytes = fs::read(&path).map_err(|_| broken("读不出来"))?;
            bytes.truncate(segment.bytes as usize);
            tail = Sha256::new_with_prefix(&bytes);
            if format!("{:x}", tail.clone().finalize()) != segment.hash {
                return Err(broken("校验失败"));
            }
            for line in bytes.split(|b| *b == b'\n').filter(|l| !l.is_empty()) {
                let line: Stored = serde_json::from_slice(line).map_err(|e| {
                    HostError::Save(format!("流水 {} 解析失败：{e}", path.display()))
                })?;
                lines.push(line.into());
            }
        }
        Ok((lines, tail))
    }

    /// 读档成功：之后从这份清单接着写。
    pub(super) fn adopt(&mut self, manifest: Manifest, tail: Sha256) {
        self.manifest = manifest;
        self.tail = tail;
    }

    /// 把这些行排进流水：接在最后一卷后面，卷满了就另起一卷。`fresh` 表示换了新世界：
    /// 以前的卷全部不要，这些行写进新的一卷。
    pub(super) fn plan(&self, lines: &[Line], fresh: bool) -> Result<Planned, HostError> {
        let mut manifest = self.manifest.clone();
        let mut tail = self.tail.clone();
        if fresh {
            manifest.segments.clear();
        }
        if lines.is_empty() {
            return Ok(Planned {
                append: None,
                manifest,
                tail,
            });
        }
        let mut bytes = Vec::new();
        for line in lines {
            serde_json::to_writer(&mut bytes, line)
                .map_err(|e| HostError::Save(format!("编码流水失败：{e}")))?;
            bytes.push(b'\n');
        }
        let open = manifest
            .segments
            .last()
            .is_some_and(|s| s.bytes < SEGMENT_BYTES);
        if !open {
            manifest.next = manifest.next.max(1);
            manifest.segments.push(Segment {
                id: manifest.next,
                bytes: 0,
                hash: String::new(),
            });
            manifest.next += 1;
            tail = Sha256::new();
        }
        let segment = manifest.segments.last_mut().expect("刚确认有最后一卷");
        let append = Append {
            path: self.file(segment.id),
            offset: segment.bytes,
            bytes,
        };
        tail.update(&append.bytes);
        segment.bytes += append.bytes.len() as u64;
        segment.hash = format!("{:x}", tail.clone().finalize());
        Ok(Planned {
            append: Some(append),
            manifest,
            tail,
        })
    }

    /// 排好的追加已经随 world.json 提交。
    pub(super) fn commit(&mut self, planned: Planned) {
        self.manifest = planned.manifest;
        self.tail = planned.tail;
    }

    /// 不知道上一次写到了哪一步：它可能已经用掉了下一个卷号，跳过去，另起的卷不会碰到它写的文件。
    pub(super) fn skip_segment(&mut self) {
        self.manifest.next = self.manifest.next.max(1) + 1;
    }
}

/// 流水目录：缺省存档旁边的 history/，别的存档名用 `<存档名>.history`。
pub(super) fn dir_for(save: &Path) -> PathBuf {
    let folder = if save.file_name().is_some_and(|n| n == SAVE_FILE_NAME) {
        "history".into()
    } else {
        format!("{}.history", save.file_name().unwrap().to_string_lossy())
    };
    save.parent().unwrap().join(folder)
}

/// 让流水目录和清单对上：清单里没有的卷删掉（换了新世界留下的旧卷、没提交成的整卷），
/// 清单里的卷比记的长就截到已提交的长度（没提交成的尾巴）。
pub(super) fn tidy(dir: &Path, manifest: &Manifest) -> Result<(), HostError> {
    if !dir.exists() {
        return Ok(());
    }
    for entry in list_dir(dir)? {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        let id = name
            .strip_suffix(".jsonl")
            .and_then(|n| n.parse::<u64>().ok());
        let Some(segment) = manifest.segments.iter().find(|s| Some(s.id) == id) else {
            remove_managed(&path)?;
            continue;
        };
        let failed =
            |e: std::io::Error| HostError::Save(format!("整理流水 {} 失败：{e}", path.display()));
        if entry.metadata().map_err(failed)?.len() > segment.bytes {
            let file = private_file(&path, false).map_err(failed)?;
            file.set_len(segment.bytes).map_err(failed)?;
            file.sync_all().map_err(failed)?;
        }
    }
    Ok(())
}

/// 备份：把清单里每一卷已提交的部分拷到另一个存档旁边。
pub(super) fn backup(save: &Path, target: &Path, manifest: &Manifest) -> Result<(), HostError> {
    let (from, to) = (dir_for(save), dir_for(target));
    for segment in &manifest.segments {
        let name = format!("{:06}.jsonl", segment.id);
        let mut bytes = fs::read(from.join(&name))
            .map_err(|e| HostError::Save(format!("读取流水 {name} 失败：{e}")))?;
        bytes.truncate(segment.bytes as usize);
        super::atomic_write(&to.join(name), &bytes)?;
    }
    Ok(())
}
