//! 请求发出前预留预算。额度与会话一起持久化，重启或新唤醒不能重置它。
use crate::conversation::Usage;
use serde::{Deserialize, Serialize};
use std::ops::RangeInclusive;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Limits {
    pub calls_per_wake: u32,
    pub calls_per_day: u64,
    pub tokens_per_day: u64,
    pub total_calls: u64,
    pub total_tokens: u64,
    pub max_concurrent: usize,
    pub max_output_tokens: u64,
    /// 模型总窗口：输入、输出预留与安全余量共用。
    pub context_tokens: u64,
    /// 估算超过这个值就折叠最旧的轮次。
    #[serde(default = "compact_at_default")]
    pub compact_at_tokens: u64,
    /// 折叠时最多保留原文的最近轮次数；放不进折叠目标时再少留。
    #[serde(default = "keep_rounds_default")]
    pub keep_recent_rounds: usize,
    /// 同一次决策连续因世界变化过时被退回达到这个次数，停止该人的请求；世界不停。
    #[serde(default = "stale_replies_default")]
    pub stale_replies_before_pause: u32,
    /// 模型请求连续失败达到这个次数，进入故障暂停；之前按 30 分钟搁置重试。
    #[serde(default = "model_failures_default")]
    pub model_failures_before_pause: u32,
}
fn compact_at_default() -> u64 {
    24_000
}
fn keep_rounds_default() -> usize {
    2
}
fn stale_replies_default() -> u32 {
    2
}
fn model_failures_default() -> u32 {
    3
}
/// 各项额度的取值范围；Limits::validate 按它们检查。
const CALLS_PER_WAKE: RangeInclusive<u32> = 1..=6;
const MAX_CONCURRENT: RangeInclusive<usize> = 1..=16;
const MAX_OUTPUT_TOKENS: RangeInclusive<u64> = 1..=8192;
const MIN_CONTEXT_TOKENS: u64 = 2000;
const MIN_INPUT_BUDGET: u64 = 1000;
const MIN_COMPACT_AT: u64 = 1000;
const KEEP_RECENT_ROUNDS: RangeInclusive<usize> = 2..=64;
/// 回复连续过时、模型连续失败两种停止次数共用的范围。
const BEFORE_PAUSE: RangeInclusive<u32> = 1..=20;

/// 闭区间换成线上的取值范围。
fn range<T: Copy + Into<u64>>(range: &RangeInclusive<T>) -> protocol::LimitRange {
    protocol::LimitRange {
        min: (*range.start()).into(),
        max: Some((*range.end()).into()),
    }
}

/// 只有下限的取值范围。
fn at_least(min: u64) -> protocol::LimitRange {
    protocol::LimitRange { min, max: None }
}

/// 设定中心可改的额度；并发与上下文窗口不在其中。
impl From<&Limits> for protocol::AgentLimits {
    fn from(l: &Limits) -> Self {
        protocol::AgentLimits {
            calls_per_wake: l.calls_per_wake,
            calls_per_day: l.calls_per_day,
            tokens_per_day: l.tokens_per_day,
            total_calls: l.total_calls,
            total_tokens: l.total_tokens,
            stale_replies_before_pause: l.stale_replies_before_pause,
            model_failures_before_pause: l.model_failures_before_pause,
        }
    }
}
impl Limits {
    /// 设定中心可改各项的取值范围，与 validate 的单项检查同一组规则：
    /// 每日与总调用须大于 0，每日 token 不小于模型窗口加单次输出上限。
    pub fn ranges(&self) -> protocol::AgentLimitRanges {
        protocol::AgentLimitRanges {
            calls_per_wake: range(&CALLS_PER_WAKE),
            calls_per_day: at_least(1),
            tokens_per_day: at_least(self.context_tokens + self.max_output_tokens),
            total_calls: at_least(1),
            total_tokens: at_least(1),
            stale_replies_before_pause: range(&BEFORE_PAUSE),
            model_failures_before_pause: range(&BEFORE_PAUSE),
        }
    }

    /// 用设定中心提交的额度覆盖对应字段，其余保持不变。
    pub fn apply(&mut self, view: &protocol::AgentLimits) {
        self.calls_per_wake = view.calls_per_wake;
        self.calls_per_day = view.calls_per_day;
        self.tokens_per_day = view.tokens_per_day;
        self.total_calls = view.total_calls;
        self.total_tokens = view.total_tokens;
        self.stale_replies_before_pause = view.stale_replies_before_pause;
        self.model_failures_before_pause = view.model_failures_before_pause;
    }
}
/// 默认额度按实测定：生活决策一次约 7–20k token，交谈发言一次约 2.5k；交谈密集时一个村民
/// 半个游戏日就能用掉 120 次调用而 token 只用 30 万，所以调用次数放宽，token 才是主要约束。
/// 每日 token 额度留一倍余量；总额度按 4 人小镇玩满 10 个游戏日的每日上限算，人更多时在设定中心改。
/// 同时在途的请求最多 12 个：每个村民本来就只有一个请求在途，人少的镇不受影响；原来的 4 个会让
/// 九人局白天大半时间在等模型（所有人都在等时世界停表，狼人杀演示局第 3 天 2 个游戏小时用了 26 分钟）。
/// 只对新开的世界生效，存档里已经保存的额度照旧。
impl Default for Limits {
    fn default() -> Self {
        Self {
            calls_per_wake: 6,
            calls_per_day: 400,
            tokens_per_day: 2_000_000,
            total_calls: 16_000,
            total_tokens: 80_000_000,
            max_concurrent: 12,
            max_output_tokens: 2048,
            context_tokens: 32_000,
            compact_at_tokens: compact_at_default(),
            keep_recent_rounds: keep_rounds_default(),
            stale_replies_before_pause: stale_replies_default(),
            model_failures_before_pause: model_failures_default(),
        }
    }
}
impl Limits {
    /// 给输出、协议包装与估算误差留余量；所有请求类型共用。
    pub fn input_budget(&self) -> u64 {
        self.context_tokens
            .saturating_sub(self.max_output_tokens)
            .saturating_sub(512)
            * 100
            / 115
    }

    /// 逐项检查，报第一个不合规的项。
    pub fn validate(&self) -> Result<(), String> {
        let checks = [
            within(
                self.calls_per_wake,
                &CALLS_PER_WAKE,
                "每次唤醒的调用上限",
                "",
            ),
            within(self.max_concurrent, &MAX_CONCURRENT, "并发上限", ""),
            (self.calls_per_day > 0, "每日调用上限须大于 0".into()),
            (self.total_calls > 0, "总调用上限须大于 0".into()),
            within(
                self.max_output_tokens,
                &MAX_OUTPUT_TOKENS,
                "单次输出上限",
                " token",
            ),
            (
                self.context_tokens >= MIN_CONTEXT_TOKENS,
                format!("模型窗口至少 {MIN_CONTEXT_TOKENS} token"),
            ),
            (
                self.input_budget() >= MIN_INPUT_BUDGET,
                format!("模型窗口扣除输出上限与余量后，可用输入不足 {MIN_INPUT_BUDGET} token"),
            ),
            (
                self.compact_at_tokens >= MIN_COMPACT_AT,
                format!("折叠线至少 {MIN_COMPACT_AT} token"),
            ),
            (
                self.compact_at_tokens < self.context_tokens,
                "折叠线须小于模型窗口".into(),
            ),
            within(
                self.keep_recent_rounds,
                &KEEP_RECENT_ROUNDS,
                "折叠时保留的原文轮数",
                "",
            ),
            within(
                self.stale_replies_before_pause,
                &BEFORE_PAUSE,
                "回复连续过时的停止次数",
                "",
            ),
            within(
                self.model_failures_before_pause,
                &BEFORE_PAUSE,
                "模型连续失败的停止次数",
                "",
            ),
            (
                self.tokens_per_day >= self.context_tokens + self.max_output_tokens,
                "每日 token 上限须不小于模型窗口加单次输出上限".into(),
            ),
            (
                self.total_tokens >= self.tokens_per_day,
                "总 token 上限须不小于每日 token 上限".into(),
            ),
        ];
        match checks.into_iter().find(|(ok, _)| !ok) {
            Some((_, problem)) => Err(format!("Agent 预算配置无效：{problem}")),
            None => Ok(()),
        }
    }
}

/// 取值在范围内；不在时的说明写成「{label}须为 a–b{unit}」。
fn within<T: PartialOrd + std::fmt::Display>(
    value: T,
    range: &RangeInclusive<T>,
    label: &str,
    unit: &str,
) -> (bool, String) {
    (
        range.contains(&value),
        format!("{label}须为 {}–{}{unit}", range.start(), range.end()),
    )
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Account {
    pub day: i64,
    pub calls: u64,
    pub tokens: u64,
    #[serde(default)]
    pub input_tokens: u64,
    #[serde(default)]
    pub cache_hit_tokens: u64,
}
impl Account {
    pub(crate) fn new_day(&mut self, day: i64) {
        if day > self.day {
            *self = Self {
                day,
                ..Self::default()
            };
        }
    }
    pub(crate) fn charge(&mut self, tokens: u64) {
        self.calls = self.calls.saturating_add(1);
        self.tokens = self.tokens.saturating_add(tokens);
    }
    /// 用真实计量替换预留值，并累计输入与缓存命中，供命中率显示。
    pub(crate) fn reconcile(&mut self, reserved: u64, usage: &Usage) {
        self.tokens = self
            .tokens
            .saturating_sub(reserved)
            .saturating_add(usage.total());
        self.input_tokens = self.input_tokens.saturating_add(usage.input_tokens);
        self.cache_hit_tokens = self.cache_hit_tokens.saturating_add(usage.cache_hit_tokens);
    }
}
