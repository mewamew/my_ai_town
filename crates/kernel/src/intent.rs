//! 意图：草案（protocol::IntentDraft）→ 校验 → 内核意图。
//!
//! 校验纪律：逐项丢弃，不重试；
//! 动词、处所、落脚点全部对着封闭集合查。绝对坐标/时刻在草案类型上
//! 已不可表示（protocol 侧 deny_unknown_fields），这里管的是 id 与取值。
//!
//! 动词封闭集合 = 内建 { 前往, 停留, 坐下, 躺下, 查看四周, 搜寻, 藏, 推搡, 抢, 偷 } ∪ 道具动作词（affordance.rs）。
//! 坐下、躺下是换了姿势的停留；搜寻、藏管藏着的东西（exploration.rs）；推搡、抢、偷是对在场的人动手（force.rs）。
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
    /// 坐着停留：参数和停留一样，只换姿势。
    Sit,
    /// 躺着停留：不算睡觉，只换姿势。
    Lie,
    /// 查看四周：花几分钟把眼前的地点、东西和人看清，回执逐一写明，没写的就是没有。
    Look,
    /// 在原地翻找藏着的东西。
    Search,
    /// 把随身的一样东西藏在这里。
    Hide,
    /// 推在场的人一把。
    Push,
    /// 当面抢对方身上的东西。
    Rob,
    /// 趁对方睡着或倒下时拿走他身上的东西。
    Steal,
}

impl BuiltinVerb {
    const ALL: [Self; 10] = [
        Self::Goto,
        Self::Stay,
        Self::Sit,
        Self::Lie,
        Self::Look,
        Self::Search,
        Self::Hide,
        Self::Push,
        Self::Rob,
        Self::Steal,
    ];

    pub fn label(self) -> &'static str {
        match self {
            Self::Goto => "前往",
            Self::Stay => "停留",
            Self::Sit => "坐下",
            Self::Lie => "躺下",
            Self::Look => "查看四周",
            Self::Search => "搜寻",
            Self::Hide => "藏",
            Self::Push => "推搡",
            Self::Rob => "抢",
            Self::Steal => "偷",
        }
    }

    /// 草案动词对应的内建动词；道具动作词返回 None。
    pub fn parse(verb: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|b| b.label() == verb)
    }

    /// 停留的几种姿势：停留、坐下、躺下。
    pub fn is_stay(self) -> bool {
        matches!(self, Self::Stay | Self::Sit | Self::Lie)
    }
}

/// 停留时的姿势；旧存档没有这一项，按站着读。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Pose {
    #[default]
    Stand,
    Sit,
    Lie,
}

impl Pose {
    fn verb(self) -> BuiltinVerb {
        match self {
            Self::Stand => BuiltinVerb::Stay,
            Self::Sit => BuiltinVerb::Sit,
            Self::Lie => BuiltinVerb::Lie,
        }
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
        #[serde(default)]
        pose: Pose,
    },
    /// 做一件事：在当时所在的处所用道具做 verb。时长可缺省（None = 道具标称时长）。
    Do {
        verb: String,
        cond: Option<StopCond>,
        station: Option<String>,
    },
    /// 查看四周：在原地花 LOOK_MINUTES 分钟。
    Look,
    /// 对在场的人动手：对象和东西在动作草案的 recipient、prop_id 里，规则在 force.rs。
    Force { kind: crate::force::Force },
    /// 搜寻：在原地花一段时间翻找藏着的东西。
    Search,
    /// 藏：把草案 prop_id 里那件随身的东西藏在这里。
    Hide,
}

impl Intent {
    pub fn verb(&self) -> &str {
        match self {
            Intent::Goto { .. } => BuiltinVerb::Goto.label(),
            Intent::Stay { pose, .. } => pose.verb().label(),
            Intent::Do { verb, .. } => verb,
            Intent::Look => BuiltinVerb::Look.label(),
            Intent::Force { kind } => kind.label(),
            Intent::Search => BuiltinVerb::Search.label(),
            Intent::Hide => BuiltinVerb::Hide.label(),
        }
    }

    pub fn is_goto(&self) -> bool {
        matches!(self, Intent::Goto { .. })
    }

    pub fn describe(&self, topo: &Topology) -> String {
        match self {
            Intent::Goto { locale, .. } => format!("前往 {}", topo.locale_name(locale)),
            Intent::Stay { cond, pose, .. } => {
                format!("{}（{}）", pose.verb().label(), cond_text(cond))
            }
            Intent::Do { verb, cond, .. } => match cond {
                Some(c) => format!("{verb}（{}）", cond_text(c)),
                None => verb.clone(),
            },
            Intent::Look => BuiltinVerb::Look.label().into(),
            Intent::Force { kind } => kind.label().into(),
            Intent::Search => BuiltinVerb::Search.label().into(),
            Intent::Hide => BuiltinVerb::Hide.label().into(),
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
        Some(verb @ (BuiltinVerb::Stay | BuiltinVerb::Sit | BuiltinVerb::Lie)) => {
            Ok(Intent::Stay {
                cond: parse_cond(d, true)?,
                station: check_station(topo, &d.target)?,
                pose: match verb {
                    BuiltinVerb::Sit => Pose::Sit,
                    BuiltinVerb::Lie => Pose::Lie,
                    _ => Pose::Stand,
                },
            })
        }
        Some(verb @ (BuiltinVerb::Push | BuiltinVerb::Rob | BuiltinVerb::Steal)) => {
            ensure!(
                d.locale.is_none()
                    && d.target.is_none()
                    && d.until.is_none()
                    && d.duration_minutes.is_none(),
                KernelError::action(format!(
                    "{}只填 recipient（抢和偷再填 prop_id），不填地点、落脚点和时长",
                    verb.label()
                ))
            );
            Ok(Intent::Force {
                kind: crate::force::Force::of(verb),
            })
        }
        Some(BuiltinVerb::Look) => {
            ensure!(
                d.locale.is_none() && d.target.is_none() && d.until.is_none(),
                KernelError::action("查看四周只看眼前，不填地点、落脚点和结束条件")
            );
            Ok(Intent::Look)
        }
        Some(verb @ (BuiltinVerb::Search | BuiltinVerb::Hide)) => {
            ensure!(
                d.locale.is_none()
                    && d.target.is_none()
                    && d.until.is_none()
                    && d.duration_minutes.is_none(),
                KernelError::action(format!("{}在原地做，不填地点、落脚点和时长", verb.label()))
            );
            Ok(if verb == BuiltinVerb::Search {
                Intent::Search
            } else {
                Intent::Hide
            })
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
