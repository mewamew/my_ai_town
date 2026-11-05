//! 工具参数的长度与数量上限。schema 与运行时校验都从这里取值，只在这一处定义。
use std::ops::RangeInclusive;

/// memory_search.query 与 recall.text 的字数上限。
pub const QUERY_CHARS: usize = 120;
pub const SEARCH_LIMIT_MAX: usize = 20;
pub const SEARCH_LIMIT_DEFAULT: usize = 8;
pub const READ_LIMIT_MAX: usize = 8000;
pub const READ_LIMIT_DEFAULT: usize = 4000;

pub const RECALL_OBJECT_BYTES: usize = 160;
pub const RECALL_LIMIT_MAX: usize = 8;
pub const RECALL_LIMIT_DEFAULT: usize = 6;

/// reflect 提交的本批摘要字数上限。
pub const REFLECT_SUMMARY_CHARS: usize = 1600;
pub const NOTES_MAX: usize = 4;
pub const NOTE_TITLE_CHARS: usize = 80;
pub const NOTE_TEXT_CHARS: usize = 1600;
pub const NOTE_EVENT_IDS_MAX: usize = 24;
pub const QUOTES_MAX: usize = 8;
pub const QUOTE_CHARS: usize = 4000;

pub const GOAL_ID_BYTES: usize = 96;
pub const GOAL_TITLE_CHARS: usize = 200;
/// commitment 与 reason 共用。
pub const GOAL_TEXT_CHARS: usize = 400;
pub const GOAL_STEPS_MAX: usize = 8;
pub const GOAL_STEP_CHARS: usize = 160;
/// 同时进行或暂停的目标数上限。
pub const OPEN_GOALS_MAX: usize = 8;

pub const ACTIONS_MAX: usize = 8;
pub const ITEMS_MAX: usize = 40;
pub const TAKE_QUANTITY_MAX: u32 = 40;
pub const WRITING_TITLE_CHARS: usize = 80;
pub const WRITING_TEXT_CHARS: usize = 4000;
pub const DURATION_MINUTES_MAX: f64 = 1440.0;

pub const MESSAGE_CHARS: usize = 400;

pub const WAIT_MINUTES: RangeInclusive<f64> = 1.0..=1440.0;
/// 只填事件的等待到点也醒来重看：等的人一直不来，不至于空等一整天才被饥渴叫醒。
pub const EVENT_WAIT_MINUTES: f64 = 60.0;
pub const WAIT_REASON_CHARS: usize = 300;
