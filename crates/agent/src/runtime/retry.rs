//! 重试与放弃的规则：每个阈值只在这里定义一次，失败后的处理也在这里。
//! 设定中心能改的两个阈值（模型连续失败、回复连续过时）存在 Limits 里，这里按它们判断。
use super::{
    response::{OutdatedCause, RepliedRound},
    ResidentRuntime, Trace,
};
use crate::{
    completion::ModelError,
    notebook::REFLECTION_INTERVAL,
    session::{HoldCause, PauseKind, Session, Sleep},
};
use kernel::World;
use serde_json::json;

/// 搁置：一次醒来用满请求、相同问题连续失败或一次思考结束后，过这么多模拟分钟再看。
pub(crate) const POSTPONE_MINUTES: f64 = 30.0;
/// 相同问题连续失败达到这个次数就搁置。回应邀请连续格式错误也按它，host 据此提示「暂缓后会重试」。
pub const SAME_FAILURE_BEFORE_POSTPONE: u32 = 2;
/// 模型以上下文超长拒收：达到这个次数起，折叠时一轮原文也不留。
pub(crate) const CONTEXT_REJECTIONS_BEFORE_FULL_FOLD: u32 = 2;
/// 模型以上下文超长拒收超过这个次数，生活决策故障停止。
pub(crate) const CONTEXT_REJECTIONS_ALLOWED: u32 = 2;
/// 超长拒收后，输入额度收紧到上次实际发送量的这个比例（分子/分母）。
const CONTEXT_SHRINK: (u64, u64) = (3, 4);
/// 同一次轮到本人发言，最多这么多次回复没把发言权交出去（没有调用、格式错误或模型出错），
/// 之后代为倾听，交出发言权，不替本人说话。
pub(crate) const CHAT_ATTEMPTS_BEFORE_LISTEN: u32 = 2;
/// 整理失败后的等待按整理间隔成倍增加，最多翻这么多次倍。
const REFLECTION_BACKOFF_DOUBLINGS: u32 = 3;
/// 生活轮次模型请求失败后隔多少现实秒再试，连续第 n 次失败等 n 倍，最多 MODEL_RETRY_MAX_SECONDS。
/// 按现实时间算：服务恢复看的是现实时间。按模拟分钟算的话，走得慢的地图上一次 503
/// 就要站好几分钟，等他回话的人也跟着干等。
const MODEL_RETRY_SECONDS: u64 = 20;
const MODEL_RETRY_MAX_SECONDS: u64 = 120;

/// 搁置到 POSTPONE_MINUTES 之后；`wake_on_notice` 为真时重要通知会提前唤醒。
pub(super) fn postpone(
    s: &mut Session,
    now: f64,
    reason: impl Into<String>,
    wake_on_notice: bool,
    after_cursor: u64,
) {
    s.postpone(Sleep {
        until: now + POSTPONE_MINUTES,
        reason: reason.into(),
        wake_on_notice,
        after_cursor,
    });
}

/// 第 `failures` 次整理失败后，下次整理的时刻。
pub(super) fn reflection_retry_after(now: f64, failures: u32) -> f64 {
    now + REFLECTION_INTERVAL * 2_f64.powi(failures.min(REFLECTION_BACKOFF_DOUBLINGS) as i32)
}

impl ResidentRuntime {
    /// 相同问题连续失败达到次数就搁置，免得原样重试。
    pub(super) fn note_failure(
        &mut self,
        world: &World,
        s: &mut Session,
        problem: &str,
        error: &str,
    ) {
        let key = format!("{problem}:{error}");
        let failures = &mut s.streaks.failures;
        if failures.key == key {
            failures.count += 1;
        } else {
            failures.key = key;
            failures.count = 1;
        }
        if failures.count >= SAME_FAILURE_BEFORE_POSTPONE {
            let cursor = world.actor(&s.actor_id).map_or(0, |a| a.journal.cursor());
            postpone(
                s,
                world.minutes(),
                "相同问题连续失败，暂时搁置后重新查看",
                false,
                cursor,
            );
            self.record(world, s, Trace::new("wait", json!(s.sleep())));
        }
    }

    /// 模型请求失败（上下文超长另行处理）：连续失败达到额度里的次数就故障停止；
    /// 交谈轮次算一次没交出发言权；生活轮次隔一阵现实时间再试。
    pub(super) fn note_model_failure(
        &mut self,
        world: &mut World,
        s: &mut Session,
        round: &RepliedRound,
        failure: &ModelError,
    ) {
        let error = &failure.to_string();
        s.streaks.model_failures = s.streaks.model_failures.saturating_add(1);
        if s.streaks.model_failures >= self.state.limits.model_failures_before_pause {
            // 有界重试用完：世界继续消耗身体时不能无限等模型，交给用户处理。
            let reason = format!(
                "模型连续 {} 次请求失败：{error}；请检查模型服务再继续",
                s.streaks.model_failures
            );
            self.pause_fault_for(world, s, reason, Some(round.id), failure.cause());
            return;
        }
        if round.kind == super::RequestKind::Chat {
            self.spend_chat_attempt(world, s, round);
            return;
        }
        let wait = (MODEL_RETRY_SECONDS * u64::from(s.streaks.model_failures))
            .min(MODEL_RETRY_MAX_SECONDS);
        s.streaks.retry_at = self.wall_clock + wait;
        // 失败的请求什么也没做成，不占这次唤醒的调用数
        s.restart_wake_count();
        let data =
            json!({"error":error,"failures":s.streaks.model_failures,"retry_in_seconds":wait});
        self.record(world, s, Trace::new("model_retry", data).request(round.id));
    }

    /// 同一次轮到本人发言又有一次回复没交出发言权；次数用满仍轮到本人就代为倾听，不让整场交谈卡住。
    pub(super) fn spend_chat_attempt(
        &mut self,
        world: &mut World,
        s: &mut Session,
        round: &RepliedRound,
    ) {
        s.chat.attempts = s.chat.attempts.saturating_add(1);
        if world.chat_turn(&s.actor_id) && s.chat.attempts < CHAT_ATTEMPTS_BEFORE_LISTEN {
            return;
        }
        if world.chat_turn(&s.actor_id) {
            self.listen_silently(world, s, round);
        }
        s.chat.attempts = 0;
    }

    /// 回复因世界变化过时：计数；不在交谈中、请求期间世界状态被改掉的回复连续达到额度里的次数，停下并让全镇暂停。
    /// 持续聊天中的通知与成员变化不计连续次数、立即重新观察，避免卡住整场回应队列。
    /// 新到的重要通知（别人发来的邀请、需求告急）同样不计：它和世界速度无关，几个人同时到场互相邀请时
    /// 回复接连作废是常事，计数会让刚进镇的居民几分钟就被停掉。
    pub(super) fn note_outdated(
        &mut self,
        world: &World,
        s: &mut Session,
        round: &RepliedRound,
        cause: OutdatedCause,
    ) {
        s.tally.replies = s.tally.replies.saturating_add(1);
        s.tally.stale_replies = s.tally.stale_replies.saturating_add(1);
        let during_chat = world.active_chat(&s.actor_id).is_some();
        if during_chat {
            s.streaks.stale_streak = 0;
        } else if matches!(cause, OutdatedCause::Revision) {
            s.streaks.stale_streak = s.streaks.stale_streak.saturating_add(1);
        }
        if during_chat {
            s.cancel_sleep();
        }
        let data = json!({
            "cause": cause.as_str(),
            "during_chat": during_chat,
            "sim_delay": world.minutes() - round.stamp.sim_minutes,
            "streak": s.streaks.stale_streak,
            "stale_replies": s.tally.stale_replies,
            "replies": s.tally.replies
        });
        self.record(
            world,
            s,
            Trace::new("outdated_reply", data).request(round.id),
        );
        if s.streaks.stale_streak >= self.state.limits.stale_replies_before_pause {
            let reason = format!(
                "连续 {} 次回复因世界变化过时，全镇先暂停；模型可能回复太慢，可换更快的模型后点开始继续",
                s.streaks.stale_streak
            );
            s.pause(PauseKind::Stale, reason.clone());
            let data = json!({"kind":"stale","reason":reason});
            self.record(world, s, Trace::new("paused", data).request(round.id));
        }
    }

    /// 只处理服务端明确的超长拒收：收紧输入额度后重试，次数用尽就故障停止。网络错误走普通失败。
    pub(super) fn recover_context_error(
        &mut self,
        world: &World,
        s: &mut Session,
        round: &RepliedRound,
    ) {
        let stamp = &round.stamp;
        let reflecting = round.reflecting();
        let previous = self.input_budget(s);
        let sent =
            crate::conversation::estimate_tokens(stamp.sent_bytes, self.state.bytes_per_token);
        let (numerator, denominator) = CONTEXT_SHRINK;
        let reduced = previous.min(sent).saturating_mul(numerator) / denominator;
        s.input.ceiling = Some(reduced.max(1));
        s.input.rejections = s.input.rejections.saturating_add(1);
        s.forget_shown();
        self.record(world, s, Trace::new("context_retry", json!({"previous_budget":previous,"input_budget":reduced,"rejections":s.input.rejections,"reflection":reflecting})).request(stamp.id));
        if !reflecting && s.input.rejections > CONTEXT_REJECTIONS_ALLOWED {
            self.pause_fault_for(
                world,
                s,
                "上下文缩减重试已用尽；最小请求仍被模型拒收，请检查模型窗口配置。原文与事务已保留",
                Some(stamp.id),
                HoldCause::Context,
            );
        }
    }
}
