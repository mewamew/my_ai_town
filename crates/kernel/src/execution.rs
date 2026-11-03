//! 意图开始时的解析。只安装当前活动和位置；失败与完成后的世界后果由 simulation.rs 处理。
use crate::error::{KernelError, Result};
use crate::{
    activity::{walk_locus, ActKind, Activity, TravelStage},
    actor::Actor,
    intent::{BuiltinVerb, Intent, StopCond},
    path::{route, StartPoint},
    topology::Topology,
};
use protocol::{At, Locus};

impl Actor {
    /// 开始一个意图。`nominal_minutes` 是道具动作的标称时长，意图未给时长时用它；
    /// 调用方先经过 check_intent，道具动作一定带着它找到的可供性的时长。
    /// 失败时当前活动换成零时长占位，动词只用于失败通知。
    pub(crate) fn start_activity(
        &mut self,
        topo: &Topology,
        now: f64,
        intent: Intent,
        nominal_minutes: Option<f64>,
    ) -> Result<Option<String>> {
        let verb = intent.verb().to_string();
        let result = match intent {
            Intent::Goto { locale, station } => {
                self.start_travel(topo, now, &locale, station.as_deref())
            }
            Intent::Stay { cond, station } => {
                self.start_at_station(topo, now, &verb, ActKind::Placeholder { cond }, station)
            }
            Intent::Look => self.start_at_station(
                topo,
                now,
                &verb,
                ActKind::Timed {
                    cond: StopCond::Duration(crate::intent::LOOK_MINUTES),
                },
                None,
            ),
            Intent::Do { cond, station, .. } => {
                let cond = cond.unwrap_or_else(|| {
                    StopCond::Duration(
                        nominal_minutes.expect("道具动作的可供性已由 check_intent 找到"),
                    )
                });
                self.start_at_station(topo, now, &verb, ActKind::Timed { cond }, station)
            }
        };
        if result.is_err() {
            self.current = Activity::instant(&self.id, now, self.locus.locale.clone(), &verb);
        }
        result
    }

    fn start_at_station(
        &mut self,
        topo: &Topology,
        now: f64,
        verb: &str,
        kind: ActKind,
        station: Option<String>,
    ) -> Result<Option<String>> {
        let locale = self.locus.locale.clone();
        if let Some(station) = &station {
            ensure!(
                topo.station_in(station, &locale),
                KernelError::action(format!("落脚点 {station} 不在当前处所，不可达"))
            );
        }
        if let Some(station) = station.filter(|_| !self.player_controlled()) {
            self.locus = Locus {
                locale: locale.clone(),
                at: At::Station { station },
            };
        }
        self.current = Activity::new(&self.id, now, locale, verb, kind);
        Ok(None)
    }

    fn start_travel(
        &mut self,
        topo: &Topology,
        now: f64,
        locale: &str,
        station: Option<&str>,
    ) -> Result<Option<String>> {
        let origin = self.locus.locale.clone();
        let start = StartPoint::at(topo, &self.locus);
        let journey = route(topo, &start, locale, station)?;
        let eta = journey.total_minutes();
        let dest_name = topo.locale_name(locale);
        if eta <= 1e-9 {
            self.locus = journey.destination();
            self.current = Activity::instant_stay(&self.id, now, journey.dest_locale);
            return Ok(None);
        }
        let stage = if journey.lead_wait > 0.0 {
            TravelStage::Lead {
                left: journey.lead_wait,
            }
        } else {
            TravelStage::Walking { idx: 0, t: 0.0 }
        };
        if let (TravelStage::Walking { .. }, Some(walk)) = (&stage, journey.walks.first()) {
            self.locus = walk_locus(walk, 0.0);
        }
        self.current = Activity::new(
            &self.id,
            now,
            origin,
            BuiltinVerb::Goto.label(),
            ActKind::Travel { journey, stage },
        );
        // 「大约 1 分钟」：零点几分钟的精度对谁都没用
        Ok(Some(format!(
            "{} 出发前往 {dest_name}（大约 {} 分钟）",
            self.name,
            eta.round().max(1.0)
        )))
    }
}
