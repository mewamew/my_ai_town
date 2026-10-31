//! 村民自己的经历与自述记录。events 是不可改写的世界事件，Agent 按编号游标读取。
//! today / days 供观察仪的日志页；thought 是自述。

use crate::clock_string;
use protocol::{Alert, DiaryDay, ReadableFact, ReceiptView, ThoughtView, TriggerInfo};

/// 想法存储上限（字）。提示词要求 ≤ 80 字，这里是兜底，防提示词膨胀。
pub const THOUGHT_MAX_CHARS: usize = 120;
/// 心声（第一句）上限（字）。
pub const LINE_MAX_CHARS: usize = 20;
/// 心声在逗号处断开时至少保留的字数；更短就按字截断。
const LINE_MIN_CHARS: usize = 6;

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Thought {
    pub text: String,
    pub line: String,
    /// 记下时的模拟分钟
    pub at: f64,
    /// 那次规划的触发原因
    pub trigger_info: TriggerInfo,
}

impl Thought {
    pub fn view(&self) -> ThoughtView {
        ThoughtView {
            sim_minutes: self.at,
            trigger_info: self.trigger_info.clone(),
            text: self.text.clone(),
            line: self.line.clone(),
            clock: clock_string(self.at),
        }
    }
}

/// 执行事实：原始时间与正文分开存储；展示格式不参与折叠判断。死亡这类生命记录另存提示卡的细节，
/// 旧存档没有这一项。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Receipt {
    pub at: f64,
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub alert: Option<Alert>,
}

impl Receipt {
    pub fn view(&self) -> ReceiptView {
        ReceiptView {
            sim_minutes: self.at,
            clock: clock_string(self.at),
            text: self.text.clone(),
            alert: self.alert.clone(),
        }
    }
}

/// 归档的一天（天亮到天亮）：给观察仪的日志页看，不进提示词。
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct DayRecord {
    /// 这一天开始时的日序（0 = D1）
    pub day: i64,
    pub receipts: Vec<Receipt>,
    pub thoughts: Vec<Thought>,
    /// 次日早上他自己写的「昨天」
    pub summary: Option<String>,
}

impl DayRecord {
    fn diary(&self, label: String, current: bool) -> DiaryDay {
        DiaryDay {
            label,
            receipts: self.receipts.iter().map(Receipt::view).collect(),
            thoughts: self.thoughts.iter().map(Thought::view).collect(),
            summary: self.summary.clone(),
            current,
        }
    }
}

#[derive(Debug, Default, Clone, serde::Serialize, serde::Deserialize)]
pub struct Journal {
    #[serde(default)]
    pub events: Vec<protocol::WorldFact>,
    /// 今天的流水：世界写的执行记录（到达、做了什么、活的进度）
    pub today: Vec<Receipt>,
    /// 今天的想法（按时间）；天亮归档
    pub thoughts_today: Vec<Thought>,
    /// 过去的每一天（观察仪日志页用）
    pub days: Vec<DayRecord>,
    /// 最近一次决定时的想法；提交计划不清它，下一次想法覆盖它
    pub thought: Option<Thought>,
}

impl Journal {
    pub(crate) fn record_readable(
        &mut self,
        at: f64,
        text: String,
        source: ReadableFact,
        locale: String,
    ) {
        self.fact(
            at,
            protocol::FactKind::Readable,
            text.clone(),
            vec![locale, source.id.clone()],
            None,
            Some(source),
        );
        self.today.push(Receipt {
            at,
            text,
            alert: None,
        });
    }

    pub fn record(&mut self, at: f64, text: impl Into<String>) {
        self.record_alert(at, text.into(), None);
    }

    /// 记一条执行事实；需要提示卡的生命记录带上细节，日志页据此标出。
    pub(crate) fn record_alert(&mut self, at: f64, text: String, alert: Option<Alert>) {
        self.fact(
            at,
            protocol::FactKind::Observation,
            text.clone(),
            vec![],
            None,
            None,
        );
        self.today.push(Receipt { at, text, alert });
    }

    /// 记一条亲眼看到的事实，带上涉及的人和地点（recall 按对象查得到），同时进今天的流水。
    pub(crate) fn record_seen(&mut self, at: f64, text: String, objects: Vec<String>) {
        self.fact(
            at,
            protocol::FactKind::Observation,
            text.clone(),
            objects,
            None,
            None,
        );
        self.today.push(Receipt {
            at,
            text,
            alert: None,
        });
    }

    pub fn cursor(&self) -> u64 {
        self.events.last().map_or(0, |event| event.event_id)
    }

    /// 按编号取一条事件。事件按编号递增存放（读档时校验过），二分查找。
    pub(crate) fn event(&self, event_id: u64) -> Option<&protocol::WorldFact> {
        self.events
            .binary_search_by_key(&event_id, |e| e.event_id)
            .ok()
            .map(|i| &self.events[i])
    }

    pub fn events_after(&self, cursor: u64) -> &[protocol::WorldFact] {
        let from = self.events.partition_point(|e| e.event_id <= cursor);
        &self.events[from..]
    }

    /// 显著通知（活动失败、紧急提醒和其他需要重新决策的世界事实）：只作为事件记录，Agent 按游标读取。
    pub(crate) fn notice(&mut self, at: f64, text: String) {
        self.fact(at, protocol::FactKind::Notice, text, vec![], None, None);
    }

    /// 写一条世界事实，返回事件编号。
    pub(crate) fn fact(
        &mut self,
        at: f64,
        kind: protocol::FactKind,
        text: String,
        objects: Vec<String>,
        action_id: Option<String>,
        readable: Option<ReadableFact>,
    ) -> u64 {
        let event_id = self.cursor() + 1;
        self.events.push(protocol::WorldFact {
            event_id,
            at,
            kind,
            text,
            objects,
            action_id,
            readable,
        });
        event_id
    }

    /// 天亮：整天归档进日志（day = 刚过去那天的日序）。
    pub fn roll_day(&mut self, day: i64) {
        self.days.push(DayRecord {
            day,
            receipts: std::mem::take(&mut self.today),
            thoughts: std::mem::take(&mut self.thoughts_today),
            summary: None,
        });
    }

    /// 记下一次想法。空白文本不记（返回 None）；超长截断。
    /// `voiced` 为假时心声留空：地图不冒气泡，右栏和日志照常显示全文。
    pub fn note_decision(
        &mut self,
        text: &str,
        at: f64,
        trigger_info: &TriggerInfo,
        voiced: bool,
    ) -> Option<&Thought> {
        let text = normalize(text);
        let text = unquote(&text);
        if text.is_empty() {
            return None;
        }
        let text = truncate(text, THOUGHT_MAX_CHARS);
        let line = if voiced {
            first_sentence(&text)
        } else {
            String::new()
        };
        let t = Thought {
            text,
            line,
            at,
            trigger_info: trigger_info.clone(),
        };
        self.thoughts_today.push(t.clone());
        self.thought = Some(t);
        self.thought.as_ref()
    }

    /// 日志：过去的每一天 + 进行中的今天（today_day = 今天的日序）。
    pub fn diary(&self, today_day: i64) -> Vec<DiaryDay> {
        let mut out: Vec<DiaryDay> = self
            .days
            .iter()
            .map(|d| d.diary(format!("D{}", d.day + 1), false))
            .collect();
        let today = DayRecord {
            day: today_day,
            receipts: self.today.clone(),
            thoughts: self.thoughts_today.clone(),
            summary: None,
        };
        out.push(today.diary(format!("D{}", today_day + 1), true));
        out
    }

    pub fn view(&self) -> Option<ThoughtView> {
        self.thought.as_ref().map(Thought::view)
    }
}

/// 心声：第一句（含句末标点）。句界只认句号级标点（。！？；及其 ASCII 形），逗号不算——
/// 「困得手抖，再干要砸活。」是一句。超过 LINE_MAX_CHARS 字时，在上限以内最后一个逗号、顿号、
/// 冒号或破折号处断开加「…」；这个停顿太靠前或没有停顿时按字截断。
pub(crate) fn first_sentence(text: &str) -> String {
    let text = normalize(text);
    let mut end = text.len();
    for (i, c) in text.char_indices() {
        if matches!(c, '。' | '！' | '？' | '；' | '!' | '?' | ';') {
            end = i + c.len_utf8();
            break;
        }
    }
    let chars: Vec<char> = text[..end].trim().chars().collect();
    if chars.len() <= LINE_MAX_CHARS {
        return chars.into_iter().collect();
    }
    let pause = chars[..LINE_MAX_CHARS]
        .iter()
        .rposition(|c| matches!(c, '，' | '、' | '：' | '—' | '…' | ',' | ':'))
        .filter(|&i| i >= LINE_MIN_CHARS);
    let head: String = chars[..pause.unwrap_or(LINE_MAX_CHARS)].iter().collect();
    // 破折号和省略号常成对出现，断在第二个上时去掉残留的第一个。
    format!("{}…", head.trim_end_matches(['—', '…']))
}

/// 去掉包住整段想法的一对引号：人设的说话方式常用「」举例，模型会照着把心声也括起来。
/// 只去成对且中间不再出现同样引号的，「他说「坐下」」这类不动。
fn unquote(text: &str) -> &str {
    for (open, close) in [('「', '」'), ('『', '』'), ('“', '”'), ('"', '"')] {
        if let Some(inner) = text.strip_prefix(open).and_then(|t| t.strip_suffix(close)) {
            if !inner.contains([open, close]) {
                return inner.trim();
            }
        }
    }
    text
}

/// 折叠换行与多余空白（模型偶尔在 JSON 字符串里换行）。
fn normalize(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// 按字（char）截断，超出加「…」。
fn truncate(s: &str, max_chars: usize) -> String {
    if s.chars().count() <= max_chars {
        return s.to_string();
    }
    let mut out: String = s.chars().take(max_chars).collect();
    out.push('…');
    out
}
