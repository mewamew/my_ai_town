//! 道具动作引发的后续：定时世界事件（来船、退潮）、概率效果的随机流、每天天亮补回的补给，
//! 以及村民离开这个世界。状态随世界存档；何时触发由 simulation.rs 的时间切片决定。
use crate::error::{KernelError, Result};
use crate::props::{Instance, InstantEffect, Placement, ScheduledProp};
use crate::World;
use protocol::{At, EventInfo};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// 随机流的起点；旧存档没有随机流时也从这里开始。
const DICE_SEED: u32 = 0x9E37_79B9;
fn dice_seed() -> u32 {
    DICE_SEED
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Happenings {
    /// 还没发生的事，按时刻先后。
    #[serde(default)]
    pub pending: Vec<Pending>,
    /// 概率效果的随机流（xorshift32，非零）。
    #[serde(default = "dice_seed")]
    pub dice: u32,
}
impl Default for Happenings {
    fn default() -> Self {
        Self {
            pending: Vec::new(),
            dice: DICE_SEED,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pending {
    pub at: f64,
    pub what: What,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum What {
    /// 定时事件：告诉在场的人，可带一件限时道具。
    Event {
        key: String,
        text: String,
        locale: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        place: Option<ScheduledProp>,
    },
    /// 限时道具到点撤走。
    Withdraw { prop: String, text: String },
    /// 村民离开这个世界；等这一刻的动作结算完再走。
    Depart { actor: String, text: String },
}

impl Happenings {
    /// 掷一次百分比；`percent` 已校验在 1–99。
    pub(crate) fn roll(&mut self, percent: u32) -> bool {
        let mut s = self.dice;
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        self.dice = s;
        (s % 100) < percent
    }
    fn push(&mut self, at: f64, what: What) {
        let i = self.pending.partition_point(|p| p.at <= at);
        self.pending.insert(i, Pending { at, what });
    }
    pub(crate) fn validate(&self) -> Result<()> {
        ensure!(
            self.dice != 0
                && self.pending.len() <= 1000
                && self.pending.iter().all(|p| p.at.is_finite() && p.at >= 0.0)
                && self.pending.windows(2).all(|w| w[0].at <= w[1].at),
            KernelError::snapshot("存档的定时事件无效")
        );
        Ok(())
    }
}

impl World {
    /// 概率效果先掷定，展开成实际发生的效果；没发生的写进 misses。`actor` 随身带着概率写明的工具时
    /// 按带工具的概率掷。
    pub(crate) fn roll_effects(
        &mut self,
        actor: &str,
        effects: &[InstantEffect],
    ) -> (Vec<InstantEffect>, Vec<String>) {
        let mut happened = Vec::new();
        let mut misses = Vec::new();
        for e in effects {
            match e {
                InstantEffect::Chance {
                    percent,
                    effects,
                    miss,
                    boost,
                } => {
                    let percent = match boost {
                        Some(b) if !self.carried_of(actor, &b.item).is_empty() => b.percent,
                        _ => *percent,
                    };
                    if self.happenings.roll(percent) {
                        happened.extend(effects.iter().cloned());
                    } else {
                        misses.push(if miss.trim().is_empty() {
                            "这次没有收获".into()
                        } else {
                            miss.clone()
                        });
                    }
                }
                other => happened.push(other.clone()),
            }
        }
        (happened, misses)
    }

    /// 安排定时事件；同一 key 还没发生时不重复。返回回执里的变化。
    pub(crate) fn schedule(
        &mut self,
        actor: &str,
        key: &str,
        after_minutes: f64,
        text: &str,
        place: Option<&ScheduledProp>,
    ) -> String {
        let waiting = self
            .happenings
            .pending
            .iter()
            .any(|p| matches!(&p.what, What::Event { key: k, .. } if k == key));
        if waiting {
            return "这件事已经在等着发生了".into();
        }
        let locale = self.actors[actor].locus.locale.clone();
        self.happenings.push(
            self.minutes + after_minutes,
            What::Event {
                key: key.into(),
                text: text.into(),
                locale,
                place: place.cloned(),
            },
        );
        "之后会有动静".into()
    }

    /// 动作结算完再离开：排在这一刻，切片末尾处理。
    pub(crate) fn depart_later(&mut self, actor: &str, text: &str) {
        self.happenings.push(
            self.minutes,
            What::Depart {
                actor: actor.into(),
                text: text.into(),
            },
        );
    }

    /// 下一件事还有多久。
    pub(crate) fn happenings_boundary(&self) -> f64 {
        self.happenings
            .pending
            .first()
            .map_or(f64::INFINITY, |p| (p.at - self.minutes).max(0.0))
    }

    /// 到点的事依次发生；发生时再安排的事（撤走限时道具）留到它自己的时刻。
    pub(crate) fn fire_happenings(&mut self) {
        while self
            .happenings
            .pending
            .first()
            .is_some_and(|p| p.at <= self.minutes + 1e-9)
        {
            let Pending { what, .. } = self.happenings.pending.remove(0);
            match what {
                What::Event {
                    key,
                    text,
                    locale,
                    place,
                } => self.fire_event(&key, &text, &locale, place),
                What::Withdraw { prop, text } => {
                    if self.topo.prop(&prop).is_some_and(|p| !p.withdrawn)
                        && self.remove_prop(&prop).is_ok()
                    {
                        self.inventory.bump();
                    }
                    if !text.is_empty() {
                        self.announce(&text);
                    }
                }
                What::Depart { actor, text } => self.depart(&actor, &text),
            }
        }
    }

    fn fire_event(&mut self, key: &str, text: &str, locale: &str, place: Option<ScheduledProp>) {
        if let Some(p) = place {
            let at = p.locale.clone().unwrap_or_else(|| locale.to_string());
            let id = format!(
                "event:{key}-{:x}",
                Sha256::digest(format!("{key}/{}", self.minutes.to_bits()))
            );
            let placement = Placement {
                instance: Instance {
                    id: id.clone(),
                    definition: p.prop.reference(),
                    locale: at,
                    name: None,
                    board: None,
                },
                definition: p.prop.as_ref().clone(),
            };
            match self.place_prop(placement) {
                Ok(()) => {
                    self.inventory.bump();
                    if let Some(lasts) = p.lasts_minutes {
                        self.happenings.push(
                            self.minutes + lasts,
                            What::Withdraw {
                                prop: id,
                                text: p.leave_text.clone(),
                            },
                        );
                    }
                }
                Err(error) => self.log(
                    EventInfo::default(),
                    format!("定时事件「{key}」的道具没能放下：{error}"),
                ),
            }
        }
        self.announce(text);
    }

    /// 在场、活着的村民都会得知；作为通知进收件箱，也会唤醒在等通知的村民。
    fn announce(&mut self, text: &str) {
        let ids: Vec<_> = self
            .actors
            .values()
            .filter(|a| a.present() && !a.is_avatar() && !a.needs.body.dead)
            .map(|a| a.id.clone())
            .collect();
        for id in ids {
            self.notify(&id, text.to_string());
        }
        self.log(EventInfo::default(), text.to_string());
    }

    /// 离开这个世界：中断手头的事，人不再出现在地图上，之后不再推进需求，也不再做决定。
    pub(crate) fn depart(&mut self, actor: &str, text: &str) {
        let Some(a) = self.actors.get(actor) else {
            return;
        };
        if !a.present() || a.needs.body.dead {
            return;
        }
        let name = a.name.clone();
        self.interrupt_actions(actor, text);
        let now = self.minutes;
        let a = self.actor_mut(actor);
        a.locus.at = At::Offstage;
        a.reset_idle(now, true);
        a.journal.record(now, format!("离开了：{text}"));
        let info = a.event_info();
        self.log(info, format!("{name} {text}"));
        self.inventory.bump();
    }

    /// 天亮时按道具定义补回补给，补到上限为止。
    pub(crate) fn restock_supplies(&mut self) {
        let mut updates = Vec::new();
        for p in self.topo.props().iter().filter(|p| !p.withdrawn) {
            for a in p.verbs.iter().filter_map(|v| v.action.as_ref()) {
                let Some(r) = a.supply.as_ref().and_then(|s| s.restock.as_ref()) else {
                    continue;
                };
                let now = self.props.supply_remaining(&p.id, a).unwrap_or(0);
                if now < r.max {
                    updates.push((p.id.clone(), a.id.clone(), r.max.min(now + r.amount)));
                }
            }
        }
        if updates.is_empty() {
            return;
        }
        for (prop, action, value) in updates {
            self.props.set_supply(&prop, &action, value);
        }
        self.inventory.bump();
    }
}
