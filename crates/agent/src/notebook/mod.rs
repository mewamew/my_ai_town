//! 每位村民自己的可检索笔记。原始经历不由模型改写，提炼结果必须保留来源。
use crate::{conversation::Message, event, memory::MemoryKind, session::Session};
use kernel::World;
pub use protocol::NoteStatus;
use protocol::{ActionStatus, FactKind};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

mod documents;
mod reflection;
pub use documents::{
    archive_document, documents, overview, page_document, read_in, revision_document, search_in,
    Documents, DocumentsCache, ReadQuery, SearchQuery,
};
pub use reflection::{apply_reflection, ReflectionUpdate};

pub(crate) const REFLECTION_BATCH: usize = 12;
/// 两次整理之间至少间隔的模拟分钟数；整理失败或额度不足也按这个间隔重试。
pub const REFLECTION_INTERVAL: f64 = 60.0;
const ROUTINE_BATCH: usize = 6;
/// 单条经历或阅读正文达到这个字数就值得单独整理。
const IMPORTANT_TEXT_CHARS: usize = 80;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Notebook {
    pub through_event: u64,
    pub last_reflection_at: f64,
    pub retry_after: f64,
    pub failures: u32,
    pub revision: u64,
    pub pages: BTreeMap<String, Page>,
    pub history: Vec<Page>,
    /// v1 存档把折叠归档内嵌在这里；恢复时搬到会话的 `folded.archives`，新存档不再写。
    #[serde(default, skip_serializing, rename = "archives")]
    pub(crate) legacy_archives: BTreeMap<u64, Vec<Message>>,
    pub request: Option<ReflectionBatch>,
    #[serde(default)]
    pub reading_dialogue: Vec<Message>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Page {
    pub path: String,
    pub title: String,
    pub text: String,
    pub evidence: Vec<u64>,
    pub status: NoteStatus,
    pub updated_at: f64,
    pub revision: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReflectionBatch {
    pub from: u64,
    pub through: u64,
    pub day: i64,
    pub event_ids: Vec<u64>,
    pub reason: String,
}

/// 重要通知和双方邀请先响应；首次请求前也不整理。
fn reflection_blocked(world: &World, session: &Session) -> bool {
    let Some(actor) = world.actor(&session.actor_id) else {
        return true;
    };
    session.last_request_id == 0
        || actor
            .journal
            .events_after(session.cursors.acknowledged)
            .iter()
            .any(|e| e.kind == FactKind::Notice)
        || world
            .interactions()
            .for_actor(&session.actor_id)
            .iter()
            .any(|i| !i.status.terminal())
}

/// 上次整理之后是否出现值得单独整理的经历：通知、交谈、长文、失败或目标结束。
fn important_since(world: &World, session: &Session) -> bool {
    let book = &session.notebook;
    let Some(actor) = world.actor(&session.actor_id) else {
        return false;
    };
    actor
        .journal
        .events_after(book.through_event)
        .iter()
        .any(|e| {
            matches!(
                e.kind,
                FactKind::Notice | FactKind::Speech | FactKind::Interaction
            ) || e.text.chars().count() >= IMPORTANT_TEXT_CHARS
                || world
                    .contents()
                    .reading_result(&session.actor_id, e.event_id)
                    .is_ok_and(|r| r.content.text.chars().count() >= IMPORTANT_TEXT_CHARS)
        })
        || actor
            .actions
            .groups
            .values()
            .flat_map(|g| &g.results)
            .any(|r| {
                r.status == ActionStatus::Failed
                    && r.event_ids.iter().any(|id| *id > book.through_event)
            })
        || session
            .goals
            .values()
            .any(|g| !g.status.is_open() && g.updated_at > book.last_reflection_at)
}

pub fn plan_reflection(world: &World, session: &Session) -> Option<ReflectionBatch> {
    let book = &session.notebook;
    if world.minutes() < book.retry_after
        || world.minutes() - book.last_reflection_at < REFLECTION_INTERVAL
        || reflection_blocked(world, session)
    {
        return None;
    }
    if let Some(batch) = &book.request {
        return Some(batch.clone());
    }
    let episodes: Vec<_> = session
        .memory
        .records
        .iter()
        .filter(|m| {
            m.kind == MemoryKind::Episode
                && !m.text.trim().is_empty()
                && m.event_ids.iter().any(|id| *id > book.through_event)
        })
        .collect();
    let first = episodes.first()?;
    let day = kernel::calendar::day_index(first.at);
    let crossed_day = day < kernel::calendar::day_index(world.minutes());
    let important = important_since(world, session);
    if !crossed_day && !important && episodes.len() < ROUTINE_BATCH {
        return None;
    }
    // 同一批只整理同一天，避免一天的摘要覆盖另一日；按来源推进，去重后的事件也算已处理。
    let ids: Vec<_> = episodes
        .into_iter()
        .take_while(|m| kernel::calendar::day_index(m.at) == day)
        .take(REFLECTION_BATCH)
        .flat_map(|m| m.event_ids.iter().copied())
        .filter(|id| *id > book.through_event)
        .collect();
    Some(ReflectionBatch {
        from: book.through_event,
        through: *ids.iter().max()?,
        day,
        event_ids: ids,
        reason: if crossed_day {
            "跨日整理"
        } else if important {
            "重要经历整理"
        } else {
            "新增经历积累"
        }
        .into(),
    })
}

pub(crate) fn valid_path(path: &str) -> bool {
    if path == "self.md" {
        return true;
    }
    let Some((folder, file)) = path.split_once('/') else {
        return false;
    };
    matches!(folder, "people" | "places" | "lessons")
        && file.ends_with(".md")
        && safe_component(file.trim_end_matches(".md"))
}
pub fn safe_component(name: &str) -> bool {
    !name.is_empty()
        && name.chars().count() <= 80
        && name
            .chars()
            .all(|c| c.is_alphanumeric() || c == '_' || c == '-')
}
/// 日摘要的路径；`day` 从 0 起，文件名从第 1 天起。
pub(crate) fn day_path(day: i64) -> String {
    format!("summaries/D{:03}.md", day + 1)
}
/// 日摘要路径里的天数（从第 1 天起）；不是日摘要返回 None。
pub(crate) fn summary_day(path: &str) -> Option<i64> {
    let digits = path.strip_prefix("summaries/D")?.strip_suffix(".md")?;
    if digits.is_empty() || !digits.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    digits.parse::<i64>().ok().filter(|d| *d > 0)
}

impl Notebook {
    pub fn validate(&self, world: &World, actor: &str) -> Result<(), String> {
        let resident = world.actor(actor).ok_or("笔记所属村民不存在")?;
        if self.through_event > resident.journal.cursor()
            || !self.last_reflection_at.is_finite()
            || !self.retry_after.is_finite()
            || self.last_reflection_at > world.minutes()
        {
            return Err("笔记整理进度无效".into());
        }
        if let Some(batch) = &self.request {
            if batch.from != self.through_event
                || batch.through <= batch.from
                || batch.through > resident.journal.cursor()
                || batch.event_ids.is_empty()
                || batch.event_ids.iter().any(|id| {
                    *id <= batch.from || *id > batch.through || event(resident, *id).is_none()
                })
            {
                return Err("待整理批次超出本人事件范围".into());
            }
        }
        for page in self.pages.values().chain(&self.history) {
            if (!valid_path(&page.path) && summary_day(&page.path).is_none())
                || page.revision > self.revision
                || !page.updated_at.is_finite()
                || page.updated_at > world.minutes()
                || page.evidence.is_empty()
                || page
                    .evidence
                    .iter()
                    .any(|id| event(resident, *id).is_none())
            {
                return Err("笔记路径、时间或来源无效".into());
            }
        }
        if self.pages.iter().any(|(path, p)| *path != p.path) {
            return Err("笔记索引与路径不一致".into());
        }
        Ok(())
    }
}
