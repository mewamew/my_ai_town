//! 意图：草案（protocol::IntentDraft）→ 校验 → 内核意图。
//!
//! 校验纪律：逐项丢弃，不重试；
//! 动词、处所、落脚点全部对着封闭集合查。绝对坐标/时刻在草案类型上
//! 已不可表示（protocol 侧 deny_unknown_fields），这里管的是 id 与取值。
//!
//! 动词封闭集合 = 内建 { 前往, 停留, 查看四周 } ∪ 道具动作词（affordance.rs）。
//! 「工作 / 睡觉 / 吃饭」三个泛动词已退役：睡觉、吃饭本来就是道具动作词，
//! 「工作」没有内容，不能作为当前封闭动作集合中的泛动词。

use crate::affordance::Affordances;
use crate::error::{KernelError, Result};
use crate::topology::Topology;
use protocol::{IntentDraft, UntilPredicate};

/// 内建动词：不来自道具表的动作词。文案只在 `label` 一处。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BuiltinVerb {
    Goto,
    Stay,
    /// 查看四周：花几分钟把眼前的地点、东西和人看清，回执逐一写明，没写的就是没有。
    Look,
}

impl BuiltinVerb {
    pub fn label(self) -> &'static str {
        match self {
            Self::Goto => "前往",
            Self::Stay => "停留",
            Self::Look => "查看四周",
        }
    }

    /// 草案动词对应的内建动词；道具动作词返回 None。
    pub fn parse(verb: &str) -> Option<Self> {
        [Self::Goto, Self::Stay, Self::Look]
            .into_iter()
            .find(|b| b.label() == verb)
    }
}

/// 查看四周花多少分钟。
pub const LOOK_MINUTES: f64 = 3.0;

/// 活动的结束条件。谓词是状态判断（"已天亮"），不是时刻——晚一点满足仍成立。
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum StopCond {
    /// 还差多少分钟（相对量）
    Duration(f64),
    /// 已天亮（06:00–19:00 为昼）
    Dawn,
    /// 已天黑
    Dusk,
    /// 永不自行结束（仅内核的空等用，草案不可表达）
    Never,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum Intent {
    Goto {
        locale: String,
        station: Option<String>,
    },
    Stay {
        cond: StopCond,
        station: Option<String>,
    },
    /// 做一件事：在当时所在的处所用道具做 verb。时长可缺省（None = 道具标称时长）。
    Do {
        verb: String,
        cond: Option<StopCond>,
        station: Option<String>,
    },
    /// 查看四周：在原地花 LOOK_MINUTES 分钟。
    Look,
}

impl Intent {
    pub fn verb(&self) -> &str {
        match self {
            Intent::Goto { .. } => BuiltinVerb::Goto.label(),
            Intent::Stay { .. } => BuiltinVerb::Stay.label(),
            Intent::Do { verb, .. } => verb,
            Intent::Look => BuiltinVerb::Look.label(),
        }
    }

    pub fn is_goto(&self) -> bool {
        matches!(self, Intent::Goto { .. })
    }

    pub fn describe(&self, topo: &Topology) -> String {
        match self {
            Intent::Goto { locale, .. } => format!("前往 {}", topo.locale_name(locale)),
            Intent::Stay { cond, .. } => format!("停留（{}）", cond_text(cond)),
            Intent::Do { verb, cond, .. } => match cond {
                Some(c) => format!("{verb}（{}）", cond_text(c)),
                None => verb.clone(),
            },
            Intent::Look => BuiltinVerb::Look.label().into(),
        }
    }
}

fn cond_text(c: &StopCond) -> String {
    match c {
        StopCond::Duration(m) => format!("{m:.0} 分钟"),
        StopCond::Dawn => "至天亮".into(),
        StopCond::Dusk => "至天黑".into(),
        StopCond::Never => "无期".into(),
    }
}

fn parse_cond(d: &IntentDraft, required: bool) -> Result<StopCond> {
    if let Some(u) = d.until {
        return Ok(match u {
            UntilPredicate::Dawn => StopCond::Dawn,
            UntilPredicate::Dusk => StopCond::Dusk,
        });
    }
    if let Some(m) = d.duration_minutes {
        if !(m > 0.0 && m <= 1440.0 && m.is_finite()) {
            return Err(KernelError::action(format!(
                "时长 {m} 不在 (0, 1440] 分钟内"
            )));
        }
        return Ok(StopCond::Duration(m));
    }
    if required {
        Err(KernelError::action("需要时长或谓词（天亮/天黑）"))
    } else {
        Ok(StopCond::Never)
    }
}

fn check_station(topo: &Topology, target: &Option<String>) -> Result<Option<String>> {
    match target {
        None => Ok(None),
        Some(t) => {
            if topo.stations.contains_key(t) {
                Ok(Some(t.clone()))
            } else {
                Err(KernelError::action(format!("落脚点 {t:?} 不在封闭集合")))
            }
        }
    }
}

/// 单条草案的校验。Err 即丢弃理由；调用方逐项收集，不重试。
/// 动作词只查「是否是某件道具的动作词」；在当前处所能不能做，是执行那一刻的可供性门控。
pub fn validate(topo: &Topology, aff: &Affordances, d: &IntentDraft) -> Result<Intent> {
    match BuiltinVerb::parse(&d.verb) {
        Some(BuiltinVerb::Goto) => {
            let locale = d
                .locale
                .clone()
                .ok_or_else(|| KernelError::action("前往需要目的处所"))?;
            if !topo.locales.contains_key(&locale) {
                return Err(KernelError::action(format!("处所 {locale:?} 不在封闭集合")));
            }
            if !topo.is_dwell(&locale) {
                return Err(KernelError::action(format!(
                    "处所 {locale:?} 是穿过型，不能作为目的地"
                )));
            }
            let station = check_station(topo, &d.target)?;
            if let Some(st) = &station {
                if !topo.station_in(st, &locale) {
                    return Err(KernelError::action(format!(
                        "落脚点 {st:?} 不在 {locale:?} 内"
                    )));
                }
            }
            Ok(Intent::Goto { locale, station })
        }
        Some(BuiltinVerb::Stay) => Ok(Intent::Stay {
            cond: parse_cond(d, true)?,
            station: check_station(topo, &d.target)?,
        }),
        Some(BuiltinVerb::Look) => {
            ensure!(
                d.locale.is_none() && d.target.is_none() && d.until.is_none(),
                KernelError::action("查看四周只看眼前，不填地点、落脚点和结束条件")
            );
            Ok(Intent::Look)
        }
        None if aff.is_verb(&d.verb) => Ok(Intent::Do {
            verb: d.verb.clone(),
            cond: match parse_cond(d, false)? {
                StopCond::Never => None,
                c => Some(c),
            },
            station: check_station(topo, &d.target)?,
        }),
        None => Err(KernelError::action(format!(
            "动词 {:?} 不在封闭集合",
            d.verb
        ))),
    }
}
