//! 记忆文件视图：目标、笔记、原始事件与归档会话按路径摊成一份只读快照。
use super::Page;
use crate::{prompts, session::Session, tools::limits};
use kernel::World;
use serde::Deserialize;
use serde_json::{json, Value};
use std::{collections::BTreeMap, rc::Rc};

pub type Documents = BTreeMap<String, String>;

pub(crate) fn render_page(page: &Page) -> String {
    format!(
        "# {}\n\n状态：{}（{}）\n更新：{}\n\n{}\n\n来源事件：{}\n",
        page.title,
        page.status.label(),
        prompts::PAGE_STATUS_NOTE,
        kernel::clock_string(page.updated_at),
        page.text,
        crate::context::clean::event_ranges(&page.evidence)
    )
}

/// 文件视图的缓存键：事件游标、笔记版本与整理进度、目标内容、归档数。
#[derive(Debug, Clone, PartialEq, Eq)]
struct DocumentsKey {
    cursor: u64,
    revision: u64,
    through_event: u64,
    goals: u64,
    compactions: u64,
}

impl DocumentsKey {
    fn of(world: &World, s: &Session) -> Self {
        use std::hash::{DefaultHasher, Hash, Hasher};
        let mut hasher = DefaultHasher::new();
        serde_json::to_string(&s.context_goals())
            .unwrap_or_default()
            .hash(&mut hasher);
        Self {
            cursor: world.actor(&s.actor_id).map_or(0, |a| a.journal.cursor()),
            revision: s.notebook.revision,
            through_event: s.notebook.through_event,
            goals: hasher.finish(),
            compactions: s.folded.compactions,
        }
    }
}

/// 一位村民文件视图的缓存，由运行器持有，不存档。
/// 只有事件增加时按游标追加，其余变化整体重建；返回共享引用，不整份克隆。
#[derive(Debug, Default)]
pub struct DocumentsCache {
    cached: Option<(DocumentsKey, Rc<Documents>)>,
}

impl DocumentsCache {
    pub fn get(&mut self, world: &World, s: &Session) -> Rc<Documents> {
        let key = DocumentsKey::of(world, s);
        if let Some((cached_key, docs)) = &mut self.cached {
            if *cached_key == key {
                return Rc::clone(docs);
            }
            let mut older = key.clone();
            older.cursor = cached_key.cursor;
            if older == *cached_key && key.cursor > cached_key.cursor {
                append_events(world, s, Rc::make_mut(docs), cached_key.cursor);
                *cached_key = key;
                return Rc::clone(docs);
            }
        }
        let docs = Rc::new(build(world, s));
        self.cached = Some((key, Rc::clone(&docs)));
        docs
    }
}

fn append_events(world: &World, s: &Session, docs: &mut Documents, after: u64) {
    if let Some(actor) = world.actor(&s.actor_id) {
        for event in actor.journal.events_after(after) {
            let path = format!(
                "events/D{:03}.jsonl",
                kernel::calendar::day_index(event.at) + 1
            );
            let text = docs.entry(path).or_default();
            text.push_str(&serde_json::to_string(event).expect("world event is serializable"));
            text.push('\n');
        }
    }
}

/// 工具能读到的文件视图；只能读当前村民的快照，不接受操作系统路径。落盘的记忆目录里是同样的
/// 文件（事件除外，它们在存档的流水里）。每次调用整份重建；运行器内部用 DocumentsCache。
pub fn documents(world: &World, s: &Session) -> Documents {
    build(world, s)
}

fn build(world: &World, s: &Session) -> Documents {
    let mut docs: Documents = overview(s).into_iter().collect();
    docs.extend(s.notebook.pages.values().map(page_document));
    docs.extend(s.notebook.history.iter().map(revision_document));
    append_events(world, s, &mut docs, 0);
    docs.extend(
        s.archives()
            .iter()
            .map(|(id, messages)| archive_document(*id, messages)),
    );
    docs
}

// 下面四个函数是文件视图里各类文件的路径和正文的唯一出处：工具读的内存视图（build）和 host
// 落盘的记忆目录都用它们。事件不在其中：内存视图按天拼（append_events），落盘走存档的流水。

/// 每次都重拼的小文件：索引、当前事务，以及还没写过自述页时的缺省自述。
pub fn overview(s: &Session) -> Vec<(String, String)> {
    let mut index = prompts::index_header(&s.actor_id, s.notebook.through_event);
    let mut topics: Vec<_> = s.notebook.pages.values().collect();
    topics.sort_by(|a, b| b.updated_at.total_cmp(&a.updated_at));
    for page in topics.iter().take(24) {
        index.push_str(&format!("- {}：{}\n", page.path, page.title));
    }
    index.push_str(prompts::INDEX_FOOTER);
    let mut current = prompts::CURRENT_HEADER.to_string();
    for goal in s.context_goals() {
        current.push_str(&format!(
            "## {}\n状态：{}\n承诺：{}\n下一步：{}\n原因：{}\n\n",
            goal.title,
            goal.status.label(),
            goal.commitment,
            goal.next_steps.join("；"),
            goal.reason
        ));
    }
    if s.goals.is_empty() {
        current.push_str(prompts::NO_GOALS);
    }
    let mut docs = vec![("INDEX.md".into(), index), ("current.md".into(), current)];
    if !s.notebook.pages.contains_key("self.md") {
        docs.push(("self.md".into(), prompts::SELF_DEFAULT.into()));
    }
    docs
}

/// 一页笔记。
pub fn page_document(page: &Page) -> (String, String) {
    (page.path.clone(), render_page(page))
}

/// 笔记被改写前的一个旧版本。
pub fn revision_document(page: &Page) -> (String, String) {
    (
        format!("revisions/R{:06}.md", page.revision),
        render_page(page),
    )
}

/// 一份折叠归档的旧会话原文。
pub fn archive_document(id: u64, messages: &[crate::conversation::Message]) -> (String, String) {
    let text = messages
        .iter()
        .map(|m| serde_json::to_string(m).expect("message is serializable") + "\n")
        .collect();
    (format!("conversations/C{id:06}.jsonl"), text)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadQuery {
    pub path: String,
    #[serde(default)]
    pub offset: usize,
    #[serde(default = "read_limit")]
    pub limit: usize,
}
fn read_limit() -> usize {
    limits::READ_LIMIT_DEFAULT
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SearchQuery {
    pub query: String,
    #[serde(default)]
    pub directory: String,
    #[serde(default)]
    pub offset: usize,
    #[serde(default = "search_limit")]
    pub limit: usize,
}
fn search_limit() -> usize {
    limits::SEARCH_LIMIT_DEFAULT
}
fn safe_path(path: &str) -> bool {
    !path.starts_with('/')
        && !path.contains('\\')
        && path
            .split('/')
            .all(|p| p != ".." && p != "." && !p.starts_with('.'))
}

pub fn read_in(docs: &Documents, q: ReadQuery) -> Result<Value, String> {
    if !safe_path(&q.path) || !(1..=limits::READ_LIMIT_MAX).contains(&q.limit) {
        return Err(format!(
            "只能按相对路径读取本人的记忆；单次 1—{} 字",
            limits::READ_LIMIT_MAX
        ));
    }
    let text = if q.path.ends_with('/') {
        docs.keys()
            .filter(|p| p.starts_with(&q.path))
            .cloned()
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        docs.get(&q.path)
            .cloned()
            .ok_or("本人记忆目录中没有这个文件")?
    };
    let count = text.chars().count();
    if q.offset > count {
        return Err("读取偏移超出文件长度".into());
    }
    let body: String = text.chars().skip(q.offset).take(q.limit).collect();
    let end = q.offset + body.chars().count();
    Ok(json!({
        "path": q.path,
        "offset": q.offset,
        "text": body,
        "total_chars": count,
        "next_offset": (end < count).then_some(end)
    }))
}
pub fn search_in(docs: &Documents, q: SearchQuery) -> Result<Value, String> {
    if !safe_path(&q.directory)
        || q.query.trim().is_empty()
        || q.query.chars().count() > limits::QUERY_CHARS
        || !(1..=limits::SEARCH_LIMIT_MAX).contains(&q.limit)
    {
        return Err(format!(
            "查询须为 1—{} 字，最多返回 {} 条，且仅能查询自己的目录",
            limits::QUERY_CHARS,
            limits::SEARCH_LIMIT_MAX
        ));
    }
    let needle = q.query.to_lowercase();
    let mut hits = Vec::new();
    for (path, text) in docs {
        if !path.starts_with(&q.directory) {
            continue;
        }
        let mut offset = 0;
        for (line_number, line) in text.lines().enumerate() {
            if let Some(byte_pos) = line.to_lowercase().find(&needle) {
                // 片段保留命中附近文字；offset 是字符偏移，可继续读取完整事件。
                let pos = line.to_lowercase()[..byte_pos].chars().count();
                let start = pos.saturating_sub(80);
                hits.push(json!({
                    "path": path,
                    "line": line_number + 1,
                    "offset": offset + start,
                    "snippet": line.chars().skip(start).take(360).collect::<String>()
                }));
            }
            offset += line.chars().count() + 1;
        }
    }
    let total = hits.len();
    let results: Vec<_> = hits.into_iter().skip(q.offset).take(q.limit).collect();
    let end = q.offset + results.len();
    Ok(json!({
        "matches": results,
        "total": total,
        "next_offset": (end < total).then_some(end)
    }))
}
