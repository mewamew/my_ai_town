//! 霜灯镇：有限物资、供热、政策与风暴是一份可保存的玩法状态。
//! 居民只能选择工作；玩家才能定政策。劳动借用完整动作组，走到工地、做完、返回热源
//! 才交付，发言不产生资源。原料先预留，中断归还；账本和任务一起保存，读档不重复发奖。
use super::Rules;
use crate::actor::Actor;
use crate::error::{KernelError, Result};
use crate::path::{route, StartPoint};
use crate::physiology::{Rates, Trace};
use crate::World;
use protocol::{
    ActionDraft, ActionStatus, EventInfo, FrostlightContext, FrostlightEnding, FrostlightNews,
    FrostlightPerson, FrostlightPhase as Phase, FrostlightPolicies, FrostlightStation,
    FrostlightView, FrostlightWork, GameModeAction, GameModeContext, GameModeView, GroupStatus,
    IntentDraft,
};
use serde::{Deserialize, Serialize};

const EPS: f64 = 1e-7;
const NEWS_LIMIT: usize = 24;
const BUILD_COST: f64 = 8.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum JobKind {
    Fuel,
    Food,
    Materials,
    Build,
    Tend,
}

impl JobKind {
    fn id(self) -> &'static str {
        match self {
            Self::Fuel => "fuel",
            Self::Food => "food",
            Self::Materials => "materials",
            Self::Build => "build",
            Self::Tend => "tend",
        }
    }
    fn name(self) -> &'static str {
        match self {
            Self::Fuel => "运回燃料",
            Self::Food => "筹备食物",
            Self::Materials => "回收建材",
            Self::Build => "加固保温层",
            Self::Tend => "照护与鼓舞",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Job {
    group: String,
    kind: JobKind,
    locale: String,
    ends_at: f64,
    amount: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Person {
    id: String,
    name: String,
    role: String,
    contribution: u32,
    job: Option<Job>,
    care_count: u32,
    gone: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Frostlight {
    started_at: f64,
    cold_at: f64,
    storm_at: f64,
    ends_at: f64,
    last_at: f64,
    phase: Phase,
    fuel: f64,
    food: f64,
    materials: f64,
    heat: u32,
    stress: f64,
    hope: f64,
    discontent: f64,
    insulation: u32,
    generator: String,
    clinic: String,
    stations: Vec<FrostlightStation>,
    policies: FrostlightPolicies,
    aid_used: bool,
    people: Vec<Person>,
    news: Vec<FrostlightNews>,
    ending: Option<FrostlightEnding>,
    sequence: u64,
    cold_minutes: f64,
    hunger_minutes: f64,
    unrest_minutes: f64,
    briefed: bool,
}

fn draft(verb: &str, locale: Option<&str>, duration: Option<f64>) -> ActionDraft {
    ActionDraft {
        intent: IntentDraft {
            verb: verb.into(),
            locale: locale.map(str::to_owned),
            target: None,
            duration_minutes: duration,
            until: None,
        },
        inventory: None,
        prop_id: None,
        recipient: None,
        writing: None,
    }
}

fn find_place(world: &World, ids: &[&str], names: &[&str]) -> Option<String> {
    ids.iter()
        .find(|id| world.topo.locales.contains_key(**id))
        .map(|id| (*id).to_owned())
        .or_else(|| {
            names.iter().find_map(|name| {
                world
                    .topo
                    .places
                    .iter()
                    .find(|p| world.topo.locale_name(&p.locale).contains(name))
                    .map(|p| p.locale.clone())
            })
        })
}

impl Frostlight {
    pub(super) fn open(world: &World, _seed: u32, hours: Option<u32>) -> Result<Self> {
        let hours = hours.unwrap_or(6);
        ensure!(
            (2..=12).contains(&hours),
            KernelError::action("霜灯镇时长须为 2–12 小时")
        );
        let residents: Vec<_> = world
            .actors
            .values()
            .filter(|a| !a.is_avatar() && a.present() && !a.needs.body.dead)
            .collect();
        ensure!(
            (2..=12).contains(&residents.len()),
            KernelError::action("霜灯镇需要 2–12 位在场居民")
        );
        let generator = find_place(
            world,
            &["gen:town-square", "frostlight:generator"],
            &["热源", "能量塔", "炉心", "广场"],
        )
        .ok_or_else(|| KernelError::action("霜灯镇缺少热源广场，请从霜灯镇预制地图开局"))?;
        let station = |id: &str,
                       label: &str,
                       ids: &[&str],
                       names: &[&str],
                       available: f64|
         -> Result<FrostlightStation> {
            let locale = find_place(world, ids, names)
                .ok_or_else(|| KernelError::action(format!("霜灯镇缺少{label}，请检查地图")))?;
            Ok(FrostlightStation {
                id: id.into(),
                name: label.into(),
                locale,
                available,
            })
        };
        let scale = residents.len() as f64 / 6.0;
        let stations = vec![
            station(
                "fuel",
                "燃料林场",
                &["gen:forest", "frostlight:fuel"],
                &["林场", "煤场", "森林"],
                150.0 * scale,
            )?,
            station(
                "food",
                "食物仓库",
                &["gen:market", "frostlight:food"],
                &["粮仓", "食物", "市场", "集市"],
                72.0 * scale,
            )?,
            station(
                "materials",
                "回收工坊",
                &["gen:workshop", "frostlight:materials"],
                &["工坊", "工场"],
                60.0 * scale,
            )?,
        ];
        let clinic = find_place(
            world,
            &["gen:clinic", "frostlight:clinic"],
            &["医务", "诊所", "照护"],
        )
        .unwrap_or_else(|| generator.clone());
        let now = world.minutes();
        let duration = f64::from(hours) * 60.0;
        let people = residents
            .iter()
            .map(|a| Person {
                id: a.id.clone(),
                name: a.name.clone(),
                // 职业与私人愿望来自居民人设；玩法不能随机给司炉员安上另一份身份。
                role: "守灯居民".into(),
                contribution: 0,
                job: None,
                care_count: 0,
                gone: false,
            })
            .collect();
        Ok(Self {
            started_at: now,
            cold_at: now + duration / 3.0,
            storm_at: now + duration * 2.0 / 3.0,
            ends_at: now + duration,
            last_at: now,
            phase: Phase::Preparation,
            fuel: 24.0 * scale,
            food: 12.0 * scale,
            materials: 6.0,
            heat: 1,
            stress: 0.0,
            hope: 60.0,
            discontent: 15.0,
            insulation: 0,
            generator,
            clinic,
            stations,
            policies: FrostlightPolicies::default(),
            aid_used: false,
            people,
            news: vec![],
            ending: None,
            sequence: 0,
            cold_minutes: 0.0,
            hunger_minutes: 0.0,
            unrest_minutes: 0.0,
            briefed: false,
        })
    }

    fn active(&self) -> Result<()> {
        ensure!(
            self.ending.is_none(),
            KernelError::action("这一局已结束，请在结局中查看每人的贡献")
        );
        Ok(())
    }

    fn temperature(&self) -> f64 {
        // 结局冻结最后一次真实结算时刻；寒潮中失守不能凭空跳到风暴温度。
        if self.last_at >= self.storm_at - EPS {
            -48.0
        } else if self.last_at >= self.cold_at - EPS {
            -28.0
        } else {
            -12.0
        }
    }

    fn warmth(&self) -> f64 {
        self.temperature() + f64::from(self.heat) * 18.0 + f64::from(self.insulation) * 8.0
    }

    fn survivors(&self, world: &World) -> u32 {
        self.people
            .iter()
            .filter(|p| {
                world
                    .actor(&p.id)
                    .is_some_and(|a| a.present() && !a.needs.body.dead)
            })
            .count() as u32
    }

    fn announce(&mut self, world: &mut World, text: String, wake: bool) {
        self.news.push(FrostlightNews {
            at: world.minutes(),
            text: text.clone(),
        });
        if self.news.len() > NEWS_LIMIT {
            self.news.remove(0);
        }
        world.log(EventInfo::default(), format!("【霜灯镇】{text}"));
        if wake {
            for p in &self.people {
                let Some(actor) = world
                    .actor(&p.id)
                    .filter(|a| a.present() && !a.needs.body.dead)
                else {
                    continue;
                };
                let idle = p.job.is_none() && actor.interaction_available();
                let text = format!("【霜灯镇】{text}");
                if idle {
                    world.notify(&p.id, text);
                } else {
                    // Notice 会要求 Agent 中断身体动作重新规划。天气阶段和玩家管理
                    // 只是本局事实更新，忙碌的人记入经历，做完原任务再读最新玩法上下文。
                    let now = world.minutes();
                    world.actor_mut(&p.id).journal.record(now, text);
                }
            }
        }
    }

    fn station(&self, kind: JobKind) -> Option<&FrostlightStation> {
        self.stations.iter().find(|s| s.id == kind.id())
    }

    fn return_reservation(&mut self, job: &Job) {
        match job.kind {
            JobKind::Build => self.materials += BUILD_COST,
            JobKind::Tend => self.food += 2.0,
            kind => {
                if let Some(s) = self.stations.iter_mut().find(|s| s.id == kind.id()) {
                    s.available += job.amount;
                }
            }
        }
    }

    fn settle_jobs(&mut self, world: &mut World) {
        for i in 0..self.people.len() {
            let id = self.people[i].id.clone();
            let alive = world
                .actor(&id)
                .is_some_and(|a| a.present() && !a.needs.body.dead);
            self.people[i].gone = !alive;
            let Some(job) = self.people[i].job.as_ref() else {
                continue;
            };
            let group = world.action_group(&id, &job.group);
            if alive && group.is_some_and(|g| g.status == GroupStatus::Running) {
                continue;
            }
            // 回程完成后，居民可能已接下下一段行走，玩法才获得下一拍结算机会。
            // 用真实动作账本证明曾经抵达热源；不能拿稍后的当前位置推翻已发生的交付。
            let delivered = alive
                && group.is_some_and(|g| {
                    g.status == GroupStatus::Succeeded
                        && g.actions.last().is_some_and(|action| {
                            action.intent.verb == "前往"
                                && action.intent.locale.as_deref() == Some(self.generator.as_str())
                        })
                        && g.results.last().is_some_and(|receipt| {
                            receipt.status == ActionStatus::Succeeded
                                && receipt.ended_at <= self.ends_at + EPS
                        })
                });
            let job = self.people[i].job.take().expect("已检查任务存在");
            if !delivered {
                self.return_reservation(&job);
                self.announce(
                    world,
                    format!(
                        "{}的{}中断，预留物资已退回；没有计入贡献。",
                        self.people[i].name,
                        job.kind.name()
                    ),
                    false,
                );
                continue;
            }
            match job.kind {
                JobKind::Fuel => self.fuel += job.amount,
                JobKind::Food => self.food += job.amount,
                JobKind::Materials => self.materials += job.amount,
                JobKind::Build => {
                    self.insulation = (self.insulation + 1).min(3);
                    self.stress = (self.stress - 15.0).max(0.0);
                    self.hope = (self.hope + 4.0).min(100.0);
                }
                JobKind::Tend => {
                    self.people[i].care_count += 1;
                    self.hope =
                        (self.hope + if self.policies.mutual_aid { 5.0 } else { 3.0 }).min(100.0);
                    self.discontent = (self.discontent - 4.0).max(0.0);
                    self.cold_minutes = (self.cold_minutes - 5.0).max(0.0);
                }
            }
            self.people[i].contribution += 1;
            let detail = match job.kind {
                JobKind::Fuel | JobKind::Food | JobKind::Materials => {
                    format!("，交付 {:.0} 单位", job.amount)
                }
                JobKind::Build => format!("，保温升至 {} 级", self.insulation),
                JobKind::Tend => "，居民重拾了一点信心".into(),
            };
            self.announce(
                world,
                format!("{}完成{}{}。", self.people[i].name, job.kind.name(), detail),
                false,
            );
        }
    }

    fn delivery_at(&self, world: &World, actor: &Actor, locale: &str, labor: f64) -> Result<f64> {
        let outbound = route(
            &world.topo,
            &StartPoint::at(&world.topo, &actor.locus),
            locale,
            None,
        )?
        .total_minutes();
        let inbound = route(
            &world.topo,
            &StartPoint::Dwell {
                locale: locale.into(),
            },
            &self.generator,
            None,
        )?
        .total_minutes();
        Ok(world.minutes() + outbound + labor + inbound)
    }

    fn start_job(&mut self, world: &mut World, i: usize, kind: JobKind) -> Result<String> {
        ensure!(
            self.people[i].job.is_none(),
            KernelError::action("你已有在途任务，请等待真实动作完成，不能重复领取")
        );
        let id = self.people[i].id.clone();
        let actor = world
            .actor(&id)
            .ok_or_else(|| KernelError::NoSuchActor(id.clone()))?;
        ensure!(
            actor.present() && !actor.needs.incapacitated() && !actor.player_controlled(),
            KernelError::action("你现在无法承担劳动")
        );
        ensure!(
            !actor
                .actions
                .groups
                .values()
                .any(|g| g.status == GroupStatus::Running),
            KernelError::action("请先完成当前身体动作，再领取霜灯镇任务")
        );
        let (locale, amount, minutes) = match kind {
            JobKind::Build => {
                let reserved = self
                    .people
                    .iter()
                    .filter(|p| p.job.as_ref().is_some_and(|j| j.kind == JobKind::Build))
                    .count() as u32;
                ensure!(
                    self.insulation + reserved < 3,
                    KernelError::action("保温最多三级，升级已经完成或有人在施工")
                );
                ensure!(
                    (BUILD_COST..=f64::MAX).contains(&self.materials),
                    KernelError::action("保温需要 8 单位建材，请先 work，target 填 materials")
                );
                (self.generator.clone(), 0.0, 35.0)
            }
            JobKind::Tend => {
                ensure!(
                    self.people[i].care_count < 2,
                    KernelError::action("每人最多承担两轮照护，请把精力留给物资筹备")
                );
                ensure!(
                    (2.0..=f64::MAX).contains(&self.food),
                    KernelError::action("照护需要 2 单位热食，请先筹备食物")
                );
                (self.clinic.clone(), 0.0, 25.0)
            }
            _ => {
                let s = self.station(kind).expect("开局已经检查资源站");
                let batch: f64 = if kind == JobKind::Fuel { 12.0 } else { 6.0 };
                let amount = s.available.min(
                    batch
                        * if self.policies.extended_shift {
                            1.5
                        } else {
                            1.0
                        },
                );
                ensure!(
                    (1.0..=f64::MAX).contains(&amount),
                    KernelError::action("这个站点已没有可回收物资，请换一种工作")
                );
                (
                    s.locale.clone(),
                    amount,
                    if self.policies.extended_shift {
                        35.0
                    } else {
                        25.0
                    },
                )
            }
        };
        let ends_at = self.delivery_at(world, actor, &locale, minutes)?;
        ensure!(
            ends_at.is_finite() && ends_at < self.ends_at - EPS,
            KernelError::action("风暴结束前来不及完成并交付这项工作；查看玩法中仍来得及的任务，否则留在热源等待或交谈。等待调用独立 wait_for 工具，例如 {\"minutes\":5,\"reason\":\"等待黎明\"}，不要重复提交这项工作")
        );
        let revision = actor.actions.revision;
        let mut sequence = self
            .sequence
            .checked_add(1)
            .ok_or_else(|| KernelError::action("这一局的任务编号已耗尽"))?;
        let group = loop {
            let candidate = format!("frostlight:{:x}:{sequence}", self.started_at.to_bits());
            if !actor.actions.groups.contains_key(&candidate) {
                break candidate;
            }
            sequence = sequence
                .checked_add(1)
                .ok_or_else(|| KernelError::action("这一局的任务编号已耗尽"))?;
        };
        world.run_actions(
            &id,
            &group,
            revision,
            &[
                draft("前往", Some(&locale), None),
                draft("停留", None, Some(minutes)),
                draft("前往", Some(&self.generator), None),
            ],
        )?;
        // 到这里动作整组预检并入队成功，才预留物资和安装任务；拒绝动作没有副作用。
        self.sequence = sequence;
        match kind {
            JobKind::Build => self.materials -= BUILD_COST,
            JobKind::Tend => self.food -= 2.0,
            _ => {
                self.stations
                    .iter_mut()
                    .find(|s| s.id == kind.id())
                    .expect("资源站存在")
                    .available -= amount
            }
        }
        self.people[i].job = Some(Job {
            group,
            kind,
            locale: locale.clone(),
            ends_at,
            amount,
        });
        let result = format!("已安排{}：前往{}、劳动 {:.0} 分钟、返回{}交付。走路和劳动正在实际执行，请等待动作回执。", kind.name(), world.topo.locale_name(&locale), minutes, world.topo.locale_name(&self.generator));
        self.announce(
            world,
            format!("{}出发{}。", self.people[i].name, kind.name()),
            false,
        );
        Ok(result)
    }

    fn finish(&mut self, world: &mut World, kind: &str, title: &str, text: &str) {
        if self.ending.is_some() {
            return;
        }
        // 结局之后不再劳动、不再结算奖品。正在路上的居民留在真实位置，旧任务明确中断。
        for i in 0..self.people.len() {
            if let Some(job) = self.people[i].job.take() {
                self.return_reservation(&job);
                if world.actor(&self.people[i].id).is_some() {
                    world.interrupt_actions(&self.people[i].id, "霜灯镇这一局已经结束");
                }
            }
        }
        self.ending = Some(FrostlightEnding {
            kind: kind.into(),
            title: title.into(),
            text: text.into(),
            survivors: self.survivors(world),
        });
        self.phase = Phase::Over;
        self.announce(world, format!("{title}：{text}"), true);
    }

    fn food_rate(&self, world: &World) -> f64 {
        f64::from(self.survivors(world)) * 0.7 / 60.0 * if self.policies.soup { 0.65 } else { 1.0 }
    }

    fn fuel_rate(&self) -> f64 {
        [0.0, 3.0, 6.0, 10.0][self.heat.min(3) as usize] * self.people.len() as f64 / 6.0 / 60.0
    }

    fn mood_rates(&self) -> (f64, f64) {
        let warmth = self.warmth();
        let hungry = self.food <= EPS;
        let hope_rate = if warmth >= 0.0 {
            1.0
        } else if warmth >= -18.0 {
            -5.0
        } else {
            -14.0
        };
        let unrest_rate = if warmth >= 0.0 {
            -1.0
        } else if warmth >= -18.0 {
            4.0
        } else {
            10.0
        };
        (
            (hope_rate - if hungry { 12.0 } else { 0.0 }
                + if self.policies.mutual_aid { 2.0 } else { 0.0 })
                / 60.0,
            (unrest_rate
                + if hungry { 14.0 } else { 0.0 }
                + if self.policies.extended_shift {
                    2.0
                } else {
                    0.0
                })
                / 60.0,
        )
    }

    fn unresting(&self, hope_rate: f64, unrest_rate: f64) -> bool {
        (self.hope < 5.0 - EPS || (self.hope <= 5.0 + EPS && hope_rate <= 0.0))
            || (self.discontent > 95.0 + EPS
                || (self.discontent >= 95.0 - EPS && unrest_rate >= 0.0))
    }

    fn consume(&mut self, world: &mut World, dt: f64) {
        // 按区间开始的状态积分；燃料在区间末耗尽，不得倒算整段时间都没供热。
        // boundary 会在耗尽、跳闸和士气阈值处分段，因此大步快进与逐拍推进一致。
        let warmth = self.warmth();
        let hungry = self.food <= EPS;
        let heat = self.heat;
        let (hope_rate, unrest_rate) = self.mood_rates();
        self.unrest_minutes = (self.unrest_minutes
            + if self.unresting(hope_rate, unrest_rate) {
                dt
            } else {
                -dt
            })
        .max(0.0);
        self.hunger_minutes = (self.hunger_minutes + if hungry { dt } else { -dt * 2.0 }).max(0.0);
        self.cold_minutes =
            (self.cold_minutes + if warmth < -18.0 { dt } else { -dt * 2.0 }).max(0.0);
        self.hope = (self.hope + dt * hope_rate).clamp(0.0, 100.0);
        self.discontent = (self.discontent + dt * unrest_rate).clamp(0.0, 100.0);
        self.fuel = (self.fuel - self.fuel_rate() * dt).max(0.0);
        self.food = (self.food - self.food_rate(world) * dt).max(0.0);
        self.stress = (self.stress + dt * if heat == 3 { 0.8 } else { -0.35 }).clamp(0.0, 100.0);
        if self.fuel <= EPS && self.heat > 0 {
            self.heat = 0;
            self.announce(
                world,
                "燃料用尽，热源熄灭。运回燃料后由玩家重新点火。".into(),
                true,
            );
        }
        if self.stress >= 100.0 - EPS && self.heat > 0 {
            self.heat = 0;
            self.hope = (self.hope - 12.0).max(0.0);
            self.announce(
                world,
                "热源过载跳闸！强度已归零，压力会缓慢冷却；保温施工也能减压。".into(),
                true,
            );
        }
    }
}

impl Rules for Frostlight {
    const ID: &'static str = "frostlight";

    fn boundary(&self, world: &World) -> f64 {
        if self.ending.is_some() {
            return f64::INFINITY;
        }
        let mut next = [self.cold_at, self.storm_at, self.ends_at]
            .into_iter()
            .filter(|at| *at > world.minutes() + EPS)
            .map(|at| at - world.minutes())
            .fold(1.0, f64::min);
        let mut consider = |delta: f64| {
            if delta > EPS && delta.is_finite() {
                next = next.min(delta);
            }
        };
        if self.fuel > EPS && self.heat > 0 {
            consider(self.fuel / self.fuel_rate());
        }
        if self.food > EPS {
            consider(self.food / self.food_rate(world));
        }
        if self.heat == 3 {
            consider((100.0 - self.stress) / 0.8);
        }
        if self.warmth() < -18.0 {
            consider(90.0 - self.cold_minutes);
        }
        if self.food <= EPS {
            consider(120.0 - self.hunger_minutes);
        }
        let (hope_rate, unrest_rate) = self.mood_rates();
        for threshold in [0.0, 5.0, 100.0] {
            consider((threshold - self.hope) / hope_rate);
        }
        for threshold in [0.0, 95.0, 100.0] {
            consider((threshold - self.discontent) / unrest_rate);
        }
        if self.unresting(hope_rate, unrest_rate) {
            consider(30.0 - self.unrest_minutes);
        }
        next
    }

    fn advance(&mut self, world: &mut World) {
        if self.ending.is_some() {
            return;
        }
        if !self.briefed {
            self.briefed = true;
            self.announce(world, "暴风雪正在逼近。燃料维持供热，食物每小时按人口消耗；请分头运回物资、建造保温层。每项劳动必须返回热源才算交付。".into(), true);
        }
        self.settle_jobs(world);
        let now = world.minutes();
        let dt = (now - self.last_at).max(0.0);
        self.consume(world, dt);
        self.last_at = now;
        let next = if now >= self.storm_at - EPS {
            Phase::Storm
        } else if now >= self.cold_at - EPS {
            Phase::Cold
        } else {
            Phase::Preparation
        };
        if next != self.phase {
            self.phase = next;
            self.announce(
                world,
                if next == Phase::Storm {
                    "暴风雪抵达，室外降到 −48°C。提高供热、完成保温，守住最后一段时间。"
                } else {
                    "寒潮抵达，室外降到 −28°C。储备正在消耗，居民需要更暖的避难所。"
                }
                .into(),
                true,
            );
        }
        if self.survivors(world) == 0 {
            self.finish(
                world,
                "abandoned",
                "无人守灯",
                "居民已全部离开或倒下，这座营地失去了守夜的人。",
            );
        } else if self.cold_minutes >= 90.0 - EPS {
            self.finish(
                world,
                "frozen",
                "炉火未能守住",
                "避难所累计严寒过久，居民无法等到风雪散去。回暖会逐步缓解严寒累积，下一局需要更早供热或加固保温。",
            );
        } else if self.unrest_minutes >= 30.0 - EPS || self.hunger_minutes >= 120.0 - EPS {
            self.finish(
                world,
                "abandoned",
                "营地离心",
                "持续饥饿或绝望耗尽了居民的信任，他们决定放弃这次灯会。",
            );
        } else if now >= self.ends_at - EPS {
            if self.warmth() < -12.0 || self.cold_minutes >= 60.0 {
                self.finish(
                    world,
                    "frozen",
                    "黎明仍然寒冷",
                    "风暴走了，避难所却仍不具备生存条件。灯火节没能如期举行。",
                );
            } else if self.hope <= 15.0 || self.discontent >= 90.0 {
                self.finish(
                    world,
                    "abandoned",
                    "活下来，却失去了信任",
                    "物资守住了营地，居民却不再愿意一起生活。政策的代价也需要被照顾。",
                );
            } else if self.warmth() >= 0.0
                && self.hope >= 45.0
                && self.food >= 2.0
                && self.survivors(world) as usize == self.people.len()
            {
                self.finish(
                    world,
                    "warm_dawn",
                    "暖灯迎来黎明",
                    "每个人都熬过了风雪，公共晚宴还有余粮。居民点亮灯火，庆祝一起守住的小镇。",
                );
            } else {
                self.finish(
                    world,
                    "survived",
                    "微光中的幸存者",
                    "小镇撑过了风暴。有人疲惫、有人仍然不满，但炉边留下了重建生活的机会。",
                );
            }
        }
    }

    fn rates(&self, world: &World, actor: &Actor, rates: &mut Rates, trace: &mut Trace<'_>) {
        if self.ending.is_some() || !self.people.iter().any(|p| p.id == actor.id && !p.gone) {
            return;
        }
        if world.physiology.health && self.warmth() < -18.0 {
            rates.values.health -= 0.035;
            if let Some(t) = trace {
                t.push("霜灯镇避难所严寒：每分钟损失 0.035 健康".into());
            }
        }
        if world.physiology.energy
            && self
                .people
                .iter()
                .any(|p| p.id == actor.id && p.job.is_some())
        {
            rates.values.energy -= if self.policies.extended_shift {
                0.06
            } else {
                0.025
            };
        }
    }

    fn view(&self, world: &World) -> GameModeView {
        GameModeView::Frostlight(FrostlightView {
            phase: self.phase,
            now: world.minutes(),
            until: match self.phase {
                Phase::Preparation => self.cold_at,
                Phase::Cold => self.storm_at,
                Phase::Storm | Phase::Over => self.ends_at,
            },
            storm_at: self.storm_at,
            ends_at: self.ends_at,
            temperature: self.temperature(),
            shelter_temperature: self.warmth(),
            cold_minutes: self.cold_minutes,
            hunger_minutes: self.hunger_minutes,
            unrest_minutes: self.unrest_minutes,
            fuel: self.fuel,
            food: self.food,
            materials: self.materials,
            heat: self.heat,
            stress: self.stress,
            hope: self.hope,
            discontent: self.discontent,
            insulation: self.insulation,
            generator: self.generator.clone(),
            stations: self.stations.clone(),
            policies: self.policies.clone(),
            aid_used: self.aid_used,
            people: self
                .people
                .iter()
                .map(|p| FrostlightPerson {
                    id: p.id.clone(),
                    name: p.name.clone(),
                    role: p.role.clone(),
                    contribution: p.contribution,
                    work: p.job.as_ref().map(|j| FrostlightWork {
                        kind: j.kind.id().into(),
                        locale: j.locale.clone(),
                        ends_at: j.ends_at,
                    }),
                    gone: p.gone
                        || world
                            .actor(&p.id)
                            .is_none_or(|a| !a.present() || a.needs.body.dead),
                })
                .collect(),
            news: self.news.clone(),
            ending: self.ending.clone(),
        })
    }

    fn context(&self, world: &World, actor: &str) -> Option<GameModeContext> {
        let p = self.people.iter().find(|p| p.id == actor && !p.gone)?;
        let phase = match self.phase {
            Phase::Preparation => "筹备",
            Phase::Cold => "寒潮",
            Phase::Storm => "暴风雪",
            Phase::Over => "结束",
        };
        let actions = if self.ending.is_some() {
            vec![]
        } else if p.job.is_some() {
            vec!["你的身体任务正在进行，等待动作回执；交谈承诺不算交付，不能重复领取。".into()]
        } else {
            let actor = world.actor(actor)?;
            let shift = if self.policies.extended_shift {
                35.0
            } else {
                25.0
            };
            let choices = [
                (
                    "燃料运输",
                    self.station(JobKind::Fuel)?.locale.as_str(),
                    shift,
                    r#"{"action":"work","target":"fuel"}"#,
                    "采集并交付燃料",
                ),
                (
                    "粮食运输",
                    self.station(JobKind::Food)?.locale.as_str(),
                    shift,
                    r#"{"action":"work","target":"food"}"#,
                    "采集并交付食物",
                ),
                (
                    "建材运输",
                    self.station(JobKind::Materials)?.locale.as_str(),
                    shift,
                    r#"{"action":"work","target":"materials"}"#,
                    "采集并交付建材",
                ),
                (
                    "保温施工",
                    self.generator.as_str(),
                    35.0,
                    r#"{"action":"build"}"#,
                    "消耗8建材，保温+1，最多3级",
                ),
                (
                    "照护",
                    self.clinic.as_str(),
                    25.0,
                    r#"{"action":"tend"}"#,
                    "消耗2食物，缓解不满与绝望，每人最多2次",
                ),
            ];
            let mut actions = Vec::new();
            for (name, locale, labor, arguments, detail) in choices {
                match self.delivery_at(world, actor, locale, labor) {
                    Ok(at) if at.is_finite() && at < self.ends_at - EPS => actions.push(format!(
                        "mode_action({arguments})：{detail}，含路程预计{:.1}分钟。",
                        at - world.minutes()
                    )),
                    Ok(_) => actions.push(format!("{name}已来不及在黎明前返回交付，不要开始。")),
                    Err(_) => actions.push(format!("{name}路线不可达，不要开始。")),
                }
            }
            actions.push("没有合适工作时留在热源等待或交谈。等待用独立工具 wait_for({\"minutes\":5,\"reason\":\"等待黎明\"})；不能向 mode_action 提交 wait_for 或 say。".into());
            actions
        };
        let policies: Vec<_> = [
            (self.policies.extended_shift, "延长班次"),
            (self.policies.soup, "节粮汤"),
            (self.policies.mutual_aid, "互助公约"),
        ]
        .into_iter()
        .filter_map(|(active, name)| active.then_some(name))
        .collect();
        let policies = if policies.is_empty() {
            "无".into()
        } else {
            policies.join("、")
        };
        Some(GameModeContext::Frostlight(FrostlightContext {
            phase: phase.into(), me: format!("{}，{}，已完成{}项贡献", p.name, p.role, p.contribution),
            goal: "和其他居民一起熬过风暴，准备暖灯晚宴。按短缺情况分工，可以先协商再开工；政策和热源强度由玩家决定。".into(),
            now: format!("室外 {:.0}°C，避难所 {:.0}°C；距黎明 {:.0} 分钟。希望 {:.0}/100，不满 {:.0}/100。", self.temperature(), self.warmth(), (self.ends_at - world.minutes()).max(0.0), self.hope, self.discontent),
            resources: format!("公共燃料 {:.1}、食物 {:.1}、建材 {:.1}；供热{}档、保温{}级、压力{:.0}%。当前全镇每小时消耗燃料{:.2}、食物{:.2}（食物每人{:.3}）；生效法令：{}。严寒或缺粮会使希望下降。", self.fuel, self.food, self.materials, self.heat, self.insulation, self.stress, self.fuel_rate() * 60.0, self.food_rate(world) * 60.0, if self.policies.soup { 0.455 } else { 0.7 }, policies),
            stations: self.stations.iter().map(|s| format!("{}：{}，编号{}，余量{:.0}", s.id, world.topo.locale_name(&s.locale), s.locale, s.available)).collect(),
            actions, news: self.news.iter().rev().take(4).rev().map(|n| n.text.clone()).collect(),
        }))
    }

    fn tool(&self, _world: &World, actor: &str) -> Option<String> {
        (self.ending.is_none() && self.people.iter().any(|p| p.id == actor && !p.gone)).then(|| "霜灯镇劳动，参数示例：{\"action\":\"work\",\"target\":\"fuel\"}；target仅fuel/food/materials。施工{\"action\":\"build\"}，照护{\"action\":\"tend\"}。真实前往、劳动、返回才交付；已有工作只等回执，不重领。只选玩法上下文中来得及交付的工作。空闲等待用另一个工具wait_for，参数{\"minutes\":5,\"reason\":\"等待黎明\"}；mode_action不接受wait_for或say。居民不能修改供热或法令。".into())
    }

    fn act(&mut self, world: &mut World, actor: &str, action: &GameModeAction) -> Result<String> {
        self.active()?;
        self.settle_jobs(world);
        let i = self
            .people
            .iter()
            .position(|p| p.id == actor && !p.gone)
            .ok_or_else(|| KernelError::action("你不是这一局在场的居民"))?;
        let kind = match action.action.as_str() {
            "work" => match action.target.as_deref() {
                Some("fuel") => JobKind::Fuel,
                Some("food") => JobKind::Food,
                Some("materials") => JobKind::Materials,
                _ => {
                    return Err(KernelError::action(
                        "work 的 target 只能是 fuel、food 或 materials",
                    ))
                }
            },
            "build" if action.target.is_none() => JobKind::Build,
            "tend" if action.target.is_none() => JobKind::Tend,
            _ => {
                return Err(KernelError::action(
                    "居民只能提交 work、build、tend；供热、法令和应急物资由玩家管理",
                ))
            }
        };
        self.start_job(world, i, kind)
    }

    fn control(&mut self, world: &mut World, action: &GameModeAction) -> Result<String> {
        self.active()?;
        let result = match action.action.as_str() {
            "heat" => {
                let heat = match action.target.as_deref() {
                    Some("0") => 0,
                    Some("1") => 1,
                    Some("2") => 2,
                    Some("3") => 3,
                    _ => return Err(KernelError::action("供热 target 只能为 0、1、2、3")),
                };
                ensure!(
                    heat == 0 || self.fuel > EPS,
                    KernelError::action("没有燃料，无法点火；请先让居民运回燃料或调用应急物资")
                );
                ensure!(
                    heat != 3 || self.stress < 90.0,
                    KernelError::action("热源压力过高，请降档冷却后再开过载")
                );
                self.heat = heat;
                format!(
                    "供热调至{heat}档；避难所预计 {:.0}°C。3档会积累压力，100%时跳闸。",
                    self.warmth()
                )
            }
            "law" => match action.target.as_deref() {
                Some("extended_shift") => {
                    ensure!(
                        !self.policies.extended_shift,
                        KernelError::action("延长班次已经生效，不能重复颁布")
                    );
                    self.policies.extended_shift = true;
                    self.hope = (self.hope - 8.0).max(0.0);
                    self.discontent = (self.discontent + 15.0).min(100.0);
                    "颁布延长班次：之后采集每趟产出+50%，劳动由25增至35分钟，精力消耗增加；希望−8，不满+15，之后每小时不满额外+2。".into()
                }
                Some("soup") => {
                    ensure!(
                        !self.policies.soup,
                        KernelError::action("节粮汤已经生效，不能重复颁布")
                    );
                    self.policies.soup = true;
                    self.hope = (self.hope - 5.0).max(0.0);
                    self.discontent = (self.discontent + 12.0).min(100.0);
                    "颁布节粮汤：食物日常消耗降低35%；希望−5，不满+12。居民仍然需要足够热食。"
                        .into()
                }
                Some("mutual_aid") => {
                    ensure!(
                        !self.policies.mutual_aid,
                        KernelError::action("互助公约已经生效，不能重复颁布")
                    );
                    ensure!(
                        (3.0..=f64::MAX).contains(&self.food),
                        KernelError::action("互助公约要先分发3单位食物")
                    );
                    self.policies.mutual_aid = true;
                    self.food -= 3.0;
                    self.hope = (self.hope + 10.0).min(100.0);
                    self.discontent = (self.discontent - 8.0).max(0.0);
                    "签下互助公约：分发3食物，希望+10、不满−8，之后每小时希望额外+2，照护效果增强。"
                        .into()
                }
                _ => {
                    return Err(KernelError::action(
                        "法令 target 只能为 extended_shift、soup、mutual_aid",
                    ))
                }
            },
            "relief" if action.target.is_none() => {
                ensure!(!self.aid_used, KernelError::action("应急物资只能领取一次"));
                self.aid_used = true;
                self.fuel += 12.0;
                self.food += 8.0;
                self.materials += 6.0;
                self.hope = (self.hope + 5.0).min(100.0);
                "一次性应急物资已入仓：燃料+12、食物+8、建材+6，希望+5。".into()
            }
            _ => return Err(KernelError::action("玩家指令只能为 heat、law、relief")),
        };
        self.announce(world, result.clone(), true);
        Ok(result)
    }

    fn pending_group(&self, world: &World, actor: &str) -> Option<String> {
        let job = self.people.iter().find(|p| p.id == actor)?.job.as_ref()?;
        world
            .action_group(actor, &job.group)
            .is_some_and(|g| g.status == GroupStatus::Running)
            .then(|| job.group.clone())
    }
}
