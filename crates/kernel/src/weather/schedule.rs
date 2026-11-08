use super::WeatherRules;
use crate::error::{KernelError, Result};
use protocol::{Climate, WeatherKind, WeatherMode, WeatherSource, WeatherTransition, WeatherView};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

const MAX_ID: u64 = 9_007_199_254_740_991;
/// 保留的天气操作回执数：写入时淘汰最早的，读档按同一上限校验。
const RECEIPT_LIMIT: usize = 128;
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RandomState {
    pub algorithm: String,
    pub seed: u32,
    pub state: u32,
}
impl RandomState {
    fn uniform(&mut self, n: u32) -> u32 {
        let limit = u32::MAX / n * n;
        loop {
            let mut s = self.state;
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            self.state = s;
            let x = s - 1;
            if x < limit {
                return x % n;
            }
        }
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WeatherRequest {
    pub request_id: String,
    pub expected_revision: u64,
    pub mode: WeatherMode,
    pub kind: Option<WeatherKind>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WeatherReceipt {
    pub request: WeatherRequest,
    pub view: WeatherView,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WeatherState {
    pub view: WeatherView,
    pub rules: WeatherRules,
    /// 气候：温带照转移表；热带不下雪、转到雷暴的机会减半。旧存档没有这一项，按温带读。
    #[serde(default, skip_serializing_if = "Climate::is_temperate")]
    pub climate: Climate,
    pub rng: RandomState,
    pub next_check_at: Option<f64>,
    pub next_event_id: u64,
    pub receipts: VecDeque<WeatherReceipt>,
}
/// 缺少字段与明确不启用分开表示，以兼容旧存档。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case", deny_unknown_fields)]
pub enum WeatherSnapshot {
    Disabled,
    Enabled { weather: Box<WeatherState> },
}

impl WeatherState {
    pub fn new(rules: WeatherRules, seed: u32, now: f64, world_id: String) -> Result<Self> {
        rules.validate()?;
        ensure!(
            !world_id.is_empty() && world_id.len() <= 256,
            KernelError::snapshot("天气世界编号无效")
        );
        ensure!(
            seed != 0 && now.is_finite() && now >= 0.,
            KernelError::snapshot("天气初始化参数无效")
        );
        let mut state = Self {
            view: WeatherView {
                world_id,
                revision: 0,
                kind: WeatherKind::Clear,
                mode: WeatherMode::Natural,
                changed_at: now,
                last_transition: None,
            },
            rules,
            climate: Climate::Temperate,
            rng: RandomState {
                algorithm: "xorshift32-v1".into(),
                seed,
                state: seed,
            },
            next_check_at: None,
            next_event_id: 1,
            receipts: VecDeque::new(),
        };
        state.schedule(now);
        Ok(state)
    }
    /// 天气视图与回执都记着所属世界；世界换编号时一起改。
    pub(crate) fn bind_world(&mut self, id: &str) {
        self.view.world_id = id.into();
        for r in &mut self.receipts {
            r.view.world_id = id.into();
        }
    }
    fn schedule(&mut self, now: f64) {
        let delay = self.rules.minimum_minutes
            + self
                .rng
                .uniform(self.rules.maximum_minutes - self.rules.minimum_minutes + 1);
        self.next_check_at = Some(now + f64::from(delay));
    }
    pub fn boundary(&self, now: f64) -> f64 {
        self.next_check_at
            .map_or(f64::INFINITY, |t| (t - now).max(0.))
    }
    fn change(
        &mut self,
        kind: WeatherKind,
        now: f64,
        source: WeatherSource,
    ) -> Option<WeatherTransition> {
        if kind == self.view.kind {
            return None;
        }
        let event = WeatherTransition {
            id: self.next_event_id,
            at: now,
            from: self.view.kind,
            to: kind,
            source,
        };
        self.next_event_id += 1;
        self.view.revision += 1;
        self.view.kind = kind;
        self.view.changed_at = now;
        self.view.last_transition = Some(event.clone());
        Some(event)
    }
    pub fn tick(&mut self, now: f64) -> Option<WeatherTransition> {
        let at = self.next_check_at.filter(|at| *at <= now + 1e-9)?;
        let row = self.row(self.view.kind);
        let roll = self.rng.uniform(row.iter().sum::<u32>().max(1));
        let mut weight = 0;
        let mut kind = self.view.kind;
        for (i, n) in row.iter().enumerate() {
            weight += n;
            if roll < weight {
                kind = self.rules.order[i];
                break;
            }
        }
        let event = self.change(kind, at, WeatherSource::Natural);
        self.schedule(at);
        event
    }
    /// 从这种天气转出去的各份权重，按气候改过：温带原样（合计 100，随机数用法和以前一样）；
    /// 热带去掉下雪、雷暴减半，按剩下的合计抽。
    fn row(&self, from: WeatherKind) -> [u32; 7] {
        let mut row = self.rules.transitions[from.index()];
        if self.climate == Climate::Tropical {
            for (i, kind) in self.rules.order.iter().enumerate() {
                match kind {
                    WeatherKind::Snow => row[i] = 0,
                    WeatherKind::Thunderstorm => row[i] /= 2,
                    _ => {}
                }
            }
        }
        row
    }

    pub fn cached(&self, request: &WeatherRequest) -> Result<Option<WeatherView>> {
        ensure!(
            !request.request_id.is_empty() && request.request_id.len() <= crate::ID_MAX_BYTES,
            KernelError::weather(protocol::WeatherCode::InvalidWeather, "天气请求编号无效")
        );
        if let Some(r) = self
            .receipts
            .iter()
            .find(|r| r.request.request_id == request.request_id)
        {
            ensure!(
                r.request == *request,
                KernelError::weather(
                    protocol::WeatherCode::InvalidWeather,
                    "相同请求编号不能改写载荷"
                )
            );
            return Ok(Some(r.view.clone()));
        }
        Ok(None)
    }
    pub fn set(&mut self, request: &WeatherRequest, now: f64) -> Result<Option<WeatherTransition>> {
        ensure!(
            request.expected_revision == self.view.revision,
            KernelError::weather(
                protocol::WeatherCode::RevisionConflict,
                "天气已改变，请重新读取后设置"
            )
        );
        ensure!(
            matches!(
                (request.mode, request.kind),
                (WeatherMode::Fixed, Some(_)) | (WeatherMode::Natural, None)
            ),
            KernelError::weather(
                protocol::WeatherCode::InvalidWeather,
                "固定模式必须指定天气，自然模式不接受天气类型"
            )
        );
        ensure!(
            self.view.revision < MAX_ID && self.next_event_id < MAX_ID,
            KernelError::weather(
                protocol::WeatherCode::InvalidWeather,
                "天气事件序号已达上限"
            )
        );
        let event = request
            .kind
            .and_then(|k| self.change(k, now, WeatherSource::Manual));
        if request.mode != self.view.mode {
            self.view.mode = request.mode;
            // 类型与模式同一次改动只增加一次对外版本。
            if event.is_none() {
                self.view.revision += 1;
            }
            if request.mode == WeatherMode::Natural {
                self.schedule(now);
            }
        }
        if request.mode == WeatherMode::Fixed {
            self.next_check_at = None;
        }
        self.receipts.push_back(WeatherReceipt {
            request: request.clone(),
            view: self.view.clone(),
        });
        while self.receipts.len() > RECEIPT_LIMIT {
            self.receipts.pop_front();
        }
        Ok(event)
    }
    pub fn validate(&self, now: f64) -> Result<()> {
        self.rules.validate()?;
        ensure!(
            valid_view(&self.view, now),
            KernelError::snapshot("天气投影无效")
        );
        ensure!(
            self.rng.algorithm == "xorshift32-v1" && self.rng.seed != 0 && self.rng.state != 0,
            KernelError::snapshot("天气随机状态无效")
        );
        ensure!(
            self.view.changed_at.is_finite()
                && self.view.changed_at >= 0.
                && self.view.changed_at <= now
                && self.view.revision <= MAX_ID
                && (1..MAX_ID).contains(&self.next_event_id),
            KernelError::snapshot("天气时刻或序号无效")
        );
        ensure!(
            match (self.view.mode, self.next_check_at) {
                (WeatherMode::Fixed, None) => true,
                (WeatherMode::Natural, Some(t)) =>
                    t.is_finite()
                        && t > now
                        && t <= now + f64::from(self.rules.maximum_minutes) + 1e-8,
                _ => false,
            },
            KernelError::snapshot("天气模式与下次检查时刻不一致")
        );
        if let Some(e) = &self.view.last_transition {
            ensure!(
                e.at == self.view.changed_at
                    && e.to == self.view.kind
                    && e.from != e.to
                    && e.id + 1 == self.next_event_id
                    && e.id <= self.view.revision,
                KernelError::snapshot("天气最近变化无效")
            );
        } else {
            ensure!(
                self.next_event_id == 1,
                KernelError::snapshot("天气变化记录缺失")
            );
        }
        let mut ids = std::collections::BTreeSet::new();
        ensure!(
            self.receipts.len() <= RECEIPT_LIMIT
                && self
                    .receipts
                    .iter()
                    .all(|r| !r.request.request_id.is_empty()
                        && r.request.request_id.len() <= crate::ID_MAX_BYTES
                        && ids.insert(&r.request.request_id)
                        && r.view.world_id == self.view.world_id
                        && r.view.revision <= self.view.revision
                        && r.view.changed_at.is_finite()
                        && r.view.changed_at >= 0.
                        && r.view.changed_at <= now
                        && valid_view(&r.view, now)
                        && r.request.mode == r.view.mode
                        && r.request.expected_revision <= r.view.revision
                        && r.view.revision - r.request.expected_revision <= 1
                        && matches!(
                            (r.request.mode, r.request.kind),
                            (WeatherMode::Natural, None) | (WeatherMode::Fixed, Some(_))
                        )
                        && r.request.kind.is_none_or(|k| k == r.view.kind)),
            KernelError::snapshot("天气操作回执无效")
        );
        Ok(())
    }
}

fn valid_view(view: &WeatherView, now: f64) -> bool {
    !view.world_id.is_empty()
        && view.world_id.len() <= 256
        && view.revision <= MAX_ID
        && view.changed_at.is_finite()
        && view.changed_at >= 0.
        && view.changed_at <= now
        && match &view.last_transition {
            Some(e) => {
                e.id > 0
                    && e.id <= view.revision
                    && e.at == view.changed_at
                    && e.from != e.to
                    && e.to == view.kind
            }
            None => view.kind == WeatherKind::Clear,
        }
}
