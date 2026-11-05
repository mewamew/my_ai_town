//! 作品、实物及实际阅读结果。正文不进入日记，也不自动生成笔记。
//! 规则在 rules.rs（`impl ContentState`），世界入口在 commands.rs。
mod commands;
mod rules;
use crate::error::{KernelError, Result};
pub use protocol::{ContentKind as Kind, ContentOrigin as Origin};
use protocol::{ContentMetadata, ContentText};
pub(crate) use rules::check_draft;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

pub const MAX_TEXT: usize = 4000;
pub const READ_MINUTES: f64 = 30.0;
pub const WRITE_MINUTES: f64 = 120.0;
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Text {
    pub work_id: String,
    pub version: u32,
    pub kind: Kind,
    pub title: String,
    pub author: String,
    pub text: String,
    pub origin: Origin,
}
impl Text {
    pub fn validate(&self) -> Result<()> {
        if self.work_id.is_empty()
            || self.work_id.len() > 180
            || self.version == 0
            || self.version > 1_000_000
        {
            return Err(KernelError::content("作品编号或版本无效"));
        }
        if self.title.trim().is_empty()
            || self.title.chars().count() > 80
            || self.author.trim().is_empty()
            || self.author.chars().count() > 80
            || self.text.trim().is_empty()
            || self.text.chars().count() > MAX_TEXT
        {
            return Err(KernelError::content(
                "书名和作者须为 1–80 字，正文须为 1–4000 字",
            ));
        }
        if matches!(&self.origin, Origin::Resident { actor } if actor.is_empty() || actor.len() > crate::ID_MAX_BYTES)
        {
            return Err(KernelError::content("作者身份无效"));
        }
        Ok(())
    }
    pub fn fingerprint(&self) -> String {
        format!(
            "{:x}",
            Sha256::digest(serde_json::to_vec(self).expect("作品可序列化"))
        )
    }
    pub fn metadata(&self) -> ContentMetadata {
        ContentMetadata {
            author: self.author.clone(),
            fingerprint: self.fingerprint(),
            kind: self.kind,
            origin: self.origin.clone(),
            title: self.title.clone(),
            version: self.version,
            work_id: self.work_id.clone(),
        }
    }
    pub fn view(&self) -> ContentText {
        ContentText {
            author: self.author.clone(),
            kind: self.kind,
            origin: self.origin.clone(),
            text: self.text.clone(),
            title: self.title.clone(),
            version: self.version,
            work_id: self.work_id.clone(),
        }
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Document {
    pub versions: Vec<Text>,
    pub withdrawn: bool,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Reading {
    pub prop_id: String,
    pub content: Text,
    pub at: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Pending {
    Reading {
        prop_id: String,
        content: Text,
    },
    Writing {
        placement: Box<crate::props::Placement>,
    },
}
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ContentState {
    pub documents: BTreeMap<String, Document>,
    pub readings: BTreeMap<String, BTreeMap<u64, Reading>>,
}
impl ContentState {
    pub(crate) fn from_topology(topo: &crate::Topology) -> Self {
        Self {
            documents: topo
                .props()
                .iter()
                .filter_map(|p| {
                    p.readable.clone().map(|t| {
                        (
                            p.id.clone(),
                            Document {
                                versions: vec![t],
                                withdrawn: p.withdrawn,
                            },
                        )
                    })
                })
                .collect(),
            readings: BTreeMap::new(),
        }
    }
    pub(crate) fn validate_actors(
        &self,
        actors: &BTreeMap<String, crate::world::Actor>,
        now: f64,
    ) -> Result<()> {
        for (actor, reads) in &self.readings {
            let a = actors
                .get(actor)
                .ok_or_else(|| KernelError::snapshot("阅读记录指向未知村民"))?;
            for (id, read) in reads {
                read.content.validate()?;
                if !read.at.is_finite()
                    || read.at > now
                    || read.at < 0.0
                    || !a.journal.event(*id).is_some_and(|e| {
                        e.readable.as_ref().is_some_and(|f| {
                            f.id == read.prop_id && f.version == read.content.fingerprint()
                        })
                    })
                {
                    return Err(KernelError::snapshot("实际阅读结果与本人事实来源不符"));
                }
                if self
                    .documents
                    .get(&read.prop_id)
                    .is_none_or(|d| !d.versions.contains(&read.content))
                {
                    return Err(KernelError::snapshot("阅读版本不属于该实例的历史版本"));
                }
            }
        }
        for (actor, a) in actors {
            if let Some(pending) = &a.current.content {
                let binding = a
                    .current
                    .action
                    .as_ref()
                    .ok_or_else(|| KernelError::snapshot("阅读或写作草稿缺少动作身份"))?;
                match pending {
                    Pending::Reading { prop_id, content } => {
                        if binding.draft.prop_id.as_ref() != Some(prop_id)
                            || self
                                .documents
                                .get(prop_id)
                                .is_none_or(|d| !d.versions.contains(content))
                        {
                            return Err(KernelError::snapshot("在读版本与动作实例不符"));
                        }
                    }
                    Pending::Writing { placement } => {
                        placement.definition.validate()?;
                        let content = placement
                            .definition
                            .readable
                            .as_ref()
                            .ok_or_else(|| KernelError::snapshot("写作缺少作品"))?;
                        if !matches!(&content.origin,Origin::Resident{actor:id} if id==actor)
                            || binding
                                .draft
                                .writing
                                .as_ref()
                                .is_none_or(|d| d.title != content.title || d.text != content.text)
                            || placement.instance.locale != a.current.locale
                        {
                            return Err(KernelError::snapshot("草稿与作者或写作动作不符"));
                        }
                    }
                }
            }
        }
        Ok(())
    }
    /// 道具表按作品状态重排：名称、正文和撤下标记都以作品为准。
    pub(crate) fn restore_props(&self, topo: &mut crate::Topology) -> Result<()> {
        for (id, document) in &self.documents {
            let prop = topo
                .prop_mut(id)
                .ok_or_else(|| KernelError::snapshot("存档作品缺少实例"))?;
            let mut last = 0;
            let first = document
                .versions
                .first()
                .ok_or_else(|| KernelError::snapshot("存档作品没有版本"))?;
            for text in &document.versions {
                text.validate()?;
                if text.version <= last || text.work_id != first.work_id || text.kind != first.kind
                {
                    return Err(KernelError::snapshot("存档作品版本链无效"));
                }
                last = text.version;
            }
            prop.readable = document.versions.last().cloned();
            prop.name = prop.readable.as_ref().unwrap().title.clone();
            prop.withdrawn = document.withdrawn;
        }
        if topo
            .props()
            .iter()
            .any(|p| p.readable.is_some() && !self.documents.contains_key(&p.id))
        {
            return Err(KernelError::snapshot("存档缺少作品快照"));
        }
        Ok(())
    }
}
pub fn book_placement(
    id: String,
    locale: String,
    content: Text,
    board: Option<String>,
) -> crate::props::Placement {
    use crate::props::*;
    let bulletin = content.kind == Kind::Bulletin;
    let definition = Definition {
        portable: !bulletin,
        stack_limit: 1,
        storage_slots: 0,
        id: format!("runtime:content-{}", &content.fingerprint()[..32]),
        version: content.version,
        name: content.title.clone(),
        description: "阅读完成后可查看正文；是否记忆由阅读者决定".into(),
        actions: vec![Action {
            consumes_item: false,
            portion_name: None,
            requires: vec![],
            id: "read".into(),
            label: if bulletin { "阅读公告" } else { "阅读" }.into(),
            duration_minutes: READ_MINUTES,
            during: vec![],
            on_complete: vec![],
            supply: None,
            recipient: false,
            rest: false,
            completion: if bulletin {
                Completion::ReadBulletin
            } else {
                Completion::ReadBook
            },
            conditions: vec![],
        }],
        readable: Some(content),
        bulletin_board: false,
        shelter: false,
        hidden: false,
    };
    Placement {
        instance: Instance {
            id,
            definition: definition.reference(),
            locale,
            name: None,
            board,
        },
        definition,
    }
}
