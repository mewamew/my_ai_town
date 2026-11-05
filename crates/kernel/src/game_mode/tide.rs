//! 潮水圈：大逃杀式的缩圈。
//! 打开后从下一个天亮起，每天 06:00 公布下一圈，12:00 开始涨，18:00 涨到；圈外的地被水盖住。
//! 圈从整座岛的外接圆开始，按种子一圈圈缩小：每一圈都落在上一圈里、都包住终点（全岛最高处），
//! 最后一圈缩到终点上，傍晚水漫过全岛。人在不在水里只看行走地图上的坐标，不按地点。
//! 圈和公告进度随快照保存；行走地图不存档，读档后按存下的圈接着涨。
use super::Rules;
use crate::actor::Actor;
use crate::avatar::WalkMap;
use crate::error::{KernelError, Result};
use crate::physiology::{note, Rates, Trace};
use crate::props::Need;
use crate::{World, DAY};
use protocol::{
    EventInfo, FactKind, GameModeContext, GameModeView, TideCircle, TideContext, TidePhase,
    TideView,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::f64::consts::TAU;

/// 每一圈的半径：按陆地面积折成的等效圆半径乘这些比例。圈正对着岛中间时大约依次剩下六成多、
/// 三成多、不到两成、约半成的陆地；最后一圈缩成一点（终点）。岛不是圆的，按外接圆算会让头一圈
/// 几乎淹不到什么。
const SHRINK: [f64; 5] = [0.8, 0.6, 0.42, 0.24, 0.0];
/// 公布、开始涨、涨到的钟点（当天第几分钟）。
const ANNOUNCE: f64 = 360.0;
const RISE_FROM: f64 = 720.0;
const RISE_TO: f64 = 1080.0;
/// 涨潮时最长隔多久重新判断一次谁站在水里（分钟）。
const RISING_SLICE: f64 = 5.0;
/// 站在水里的人每分钟额外消耗的精力和湿透的速度（比雷暴天露天淋雨还重）。
const WADING_ENERGY: f64 = 0.1;
const WADING_WET: f64 = 3.0;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tide {
    pub seed: u32,
    /// `rings[0]` 是整座岛的外接圆，之后依次缩小；最后一圈半径为 0，落在终点上。
    pub rings: Vec<TideCircle>,
    /// 第 1 圈在第几天公布（第 1 天记作 0）。
    pub first_day: u32,
    /// 已经广播过的节点数：每一圈依次有公布、开始涨、涨到三个节点。
    #[serde(default)]
    pub told: u32,
    /// 上次判断时站在水里的人：进水时记一笔，出水不再提。
    #[serde(default)]
    pub wading: BTreeSet<String>,
}

fn dist(a: [f64; 2], b: [f64; 2]) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}

/// xorshift32；状态不能为 0。
fn roll(state: &mut u32) -> f64 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    f64::from(x) / f64::from(u32::MAX)
}

fn on_land(map: &WalkMap, p: [f64; 2]) -> bool {
    map.terrain
        .as_ref()
        .and_then(|t| t.height(p[0], p[1]))
        .is_some_and(|h| h > map.sea_level + 0.05)
}

/// 从 a 看 b 在哪个方向（地图上 x 朝东，z 朝南）。
fn direction(from: [f64; 2], to: [f64; 2]) -> &'static str {
    let angle = (-(to[1] - from[1])).atan2(to[0] - from[0]).to_degrees();
    let sector = ((angle + 360.0 + 22.5) % 360.0 / 45.0) as usize;
    ["东", "东北", "北", "西北", "西", "西南", "南", "东南"][sector.min(7)]
}

/// 这个人此刻在行走地图上的位置；在室内、不在场或地图上找不到时为 None。
fn outdoor_point(world: &World, a: &Actor) -> Option<[f64; 2]> {
    let map = world.walk_map.as_ref()?;
    let spot = map
        .transit_spot(&a.locus)
        .or_else(|| map.station_locus(&a.locus))?;
    (spot.space == map.outdoor_space).then_some(spot.position)
}

impl Tide {
    /// 按这座岛生成一组圈。要有带地形的行走地图（HD-2D 地图都有）。
    pub(super) fn open(world: &World, seed: u32) -> Result<Self> {
        let map = world
            .walk_map
            .as_ref()
            .ok_or_else(|| KernelError::navigation("这张地图没有行走地形，不能打开潮水圈"))?;
        Self::plan(map, seed, world.minutes())
            .ok_or_else(|| KernelError::navigation("地图上找不到陆地，不能打开潮水圈"))
    }

    /// 按地形生成一组圈。地图上没有陆地时为 None。
    fn plan(map: &WalkMap, seed: u32, now: f64) -> Option<Self> {
        let t = map.terrain.as_ref()?;
        let mut land = Vec::new();
        let mut top: Option<([f64; 2], f64)> = None;
        for row in 0..t.rows {
            for col in 0..t.columns {
                let h = *t.heights.get(row * t.columns + col)?;
                if h <= map.sea_level + 0.05 {
                    continue;
                }
                let p = [
                    t.origin[0] + col as f64 * t.step,
                    t.origin[1] + row as f64 * t.step,
                ];
                if top.is_none_or(|(_, best)| h > best) {
                    top = Some((p, h));
                }
                land.push(p);
            }
        }
        if land.len() < 8 {
            return None;
        }
        let n = land.len() as f64;
        let centroid = [
            land.iter().map(|p| p[0]).sum::<f64>() / n,
            land.iter().map(|p| p[1]).sum::<f64>() / n,
        ];
        let reach = land.iter().map(|p| dist(*p, centroid)).fold(0.0, f64::max) + t.step;
        let equal = (n * t.step * t.step / std::f64::consts::PI)
            .sqrt()
            .min(reach);
        let goal = top?.0;
        let mut dice = seed.max(1);
        let mut rings = vec![TideCircle {
            center: centroid,
            radius: reach,
        }];
        for k in SHRINK {
            let prev = *rings.last().expect("至少有外接圆");
            let radius = equal * k;
            if radius <= 0.0 {
                rings.push(TideCircle {
                    center: goal,
                    radius: 0.0,
                });
                continue;
            }
            // 新圈在上一圈里随机落位，要包住终点、圆心落在陆地上；抽不中就朝终点平移到刚好包住。
            let room = prev.radius - radius;
            let mut center = None;
            for _ in 0..400 {
                let a = roll(&mut dice) * TAU;
                let d = roll(&mut dice).sqrt() * room;
                let p = [prev.center[0] + a.cos() * d, prev.center[1] + a.sin() * d];
                if dist(p, goal) <= radius * 0.92 && on_land(map, p) {
                    center = Some(p);
                    break;
                }
            }
            let center = center.unwrap_or_else(|| {
                let gap = dist(prev.center, goal);
                let d = (gap - radius).clamp(0.0, room);
                if gap <= 1e-9 {
                    prev.center
                } else {
                    [
                        prev.center[0] + (goal[0] - prev.center[0]) * d / gap,
                        prev.center[1] + (goal[1] - prev.center[1]) * d / gap,
                    ]
                }
            });
            rings.push(TideCircle { center, radius });
        }
        let today = (now / DAY).floor();
        let first_day = if now - today * DAY < ANNOUNCE {
            today
        } else {
            today + 1.0
        };
        let mut state = Self {
            seed,
            rings,
            first_day: first_day as u32,
            told: 0,
            wading: BTreeSet::new(),
        };
        state.told = state.passed(now);
        Some(state)
    }

    fn total(&self) -> u32 {
        self.rings.len() as u32 - 1
    }

    fn nodes(&self) -> u32 {
        3 * self.total()
    }

    /// 第 i 个节点的时刻：第 i/3+1 圈的公布、开始涨或涨到。
    fn node_time(&self, i: u32) -> f64 {
        let day = f64::from(self.first_day + i / 3) * DAY;
        day + [ANNOUNCE, RISE_FROM, RISE_TO][(i % 3) as usize]
    }

    fn passed(&self, now: f64) -> u32 {
        (0..self.nodes())
            .take_while(|&i| self.node_time(i) <= now + 1e-9)
            .count() as u32
    }

    fn state(&self, now: f64) -> TideView {
        let total = self.total();
        for k in 1..=total {
            let base = f64::from(self.first_day + k - 1) * DAY;
            let prev = self.rings[(k - 1) as usize];
            let next = self.rings[k as usize];
            if now < base + ANNOUNCE {
                return TideView {
                    edge: prev,
                    next: None,
                    phase: if k == 1 {
                        TidePhase::Waiting
                    } else {
                        TidePhase::Holding
                    },
                    ring: k - 1,
                    rings: total,
                };
            }
            if now < base + RISE_FROM {
                return TideView {
                    edge: prev,
                    next: Some(next),
                    phase: TidePhase::Announced,
                    ring: k,
                    rings: total,
                };
            }
            if now < base + RISE_TO {
                let u = (now - base - RISE_FROM) / (RISE_TO - RISE_FROM);
                let edge = TideCircle {
                    center: [
                        prev.center[0] + (next.center[0] - prev.center[0]) * u,
                        prev.center[1] + (next.center[1] - prev.center[1]) * u,
                    ],
                    radius: prev.radius + (next.radius - prev.radius) * u,
                };
                return TideView {
                    edge,
                    next: Some(next),
                    phase: TidePhase::Rising,
                    ring: k,
                    rings: total,
                };
            }
        }
        TideView {
            edge: *self.rings.last().expect("至少有外接圆"),
            next: None,
            phase: TidePhase::Closed,
            ring: total,
            rings: total,
        }
    }

    /// 站在潮水里时离水边多远（米）；在圈里、在室内或位置不明时为 None。
    fn depth(&self, world: &World, a: &Actor) -> Option<f64> {
        let edge = self.state(world.minutes()).edge;
        let d = dist(outdoor_point(world, a)?, edge.center) - edge.radius;
        (d > 0.0).then_some(d)
    }

    /// 圈心一带叫什么：离圆心最近的落脚点所在的地点。
    fn place(world: &World, center: [f64; 2]) -> String {
        world
            .walk_map
            .as_ref()
            .and_then(|m| {
                m.stations
                    .values()
                    .filter(|s| s.space == m.outdoor_space)
                    .min_by(|a, b| dist(a.position, center).total_cmp(&dist(b.position, center)))
            })
            .map(|s| world.topo.locale_name(&s.locale))
            .unwrap_or_else(|| "岛中间".into())
    }

    fn notice(&self, world: &World, node: u32) -> String {
        let k = node / 3 + 1;
        let ring = self.rings[k as usize];
        let last = k == self.total();
        let place = Self::place(world, ring.center);
        match (node % 3, last) {
            (0, true) => format!(
                "【潮水】最后一圈已公布：今天 12:00 开始涨，18:00 前水会漫过全岛，最后被淹的是「{place}」一带。"
            ),
            (0, false) => format!(
                "【潮水】第 {k} 圈已公布：今天 12:00 开始涨，18:00 前涨到以「{place}」一带为中心、半径约 {:.0} 米的圈；圈外的地会被水淹。",
                ring.radius
            ),
            (1, true) => "【潮水】开始涨潮了，18:00 前水会漫过全岛。".into(),
            (1, false) => format!("【潮水】开始涨潮了，18:00 前涨到第 {k} 圈。"),
            (_, true) => "【潮水】水漫过了全岛。".into(),
            (_, false) => format!("【潮水】潮水涨到了第 {k} 圈。"),
        }
    }

    /// 这个人和水边、下一圈的关系，写给模型看；没有可说的时为 None。
    fn standing(&self, world: &World, a: &Actor) -> Option<String> {
        let view = self.state(world.minutes());
        let here = outdoor_point(world, a)?;
        let edge = view.edge;
        let out = dist(here, edge.center) - edge.radius;
        if out > 0.0 {
            return Some(format!(
                "你站在潮水里，离水边约 {:.0} 米；往{}走能回到圈里。",
                out.ceil(),
                direction(here, edge.center)
            ));
        }
        let next = view.next?;
        let gap = dist(here, next.center) - next.radius;
        Some(if next.radius <= 0.0 {
            "傍晚水会漫过全岛。".into()
        } else if gap > 0.0 {
            format!(
                "你离下一圈的边约 {:.0} 米，在圈外；往{}走能进圈。",
                gap.ceil(),
                direction(here, next.center)
            )
        } else {
            format!("你在下一圈里面，离它的边约 {:.0} 米。", (-gap).floor())
        })
    }
}

impl Rules for Tide {
    const ID: &'static str = "tide";

    /// 离下一个节点还有多久；涨潮时最多隔几分钟切一次，好及时判断谁被水追上。
    fn boundary(&self, world: &World) -> f64 {
        let now = world.minutes();
        let mut next = (0..self.nodes())
            .map(|i| self.node_time(i))
            .find(|t| *t > now + 1e-9)
            .map_or(f64::INFINITY, |t| t - now);
        if self.state(now).phase == TidePhase::Rising {
            next = next.min(RISING_SLICE);
        }
        next
    }

    /// 到点的公告写进每个人的经历和世界日志；刚被水追上的人记一笔自己的处境。
    fn advance(&mut self, world: &mut World) {
        let now = world.minutes();
        let mut notices = Vec::new();
        while self.told < self.nodes() && self.node_time(self.told) <= now + 1e-9 {
            notices.push(self.notice(world, self.told));
            self.told += 1;
        }
        let mut wading = BTreeSet::new();
        let mut caught = Vec::new();
        for (id, a) in &world.actors {
            if a.is_avatar() || !a.present() || a.needs.body.dead {
                continue;
            }
            if self.depth(world, a).is_some() {
                wading.insert(id.clone());
                if !self.wading.contains(id) {
                    if let Some(text) = self.standing(world, a) {
                        caught.push((id.clone(), text));
                    }
                }
            }
        }
        self.wading = wading;
        let object = format!("tide:{}", self.seed);
        for text in notices {
            for a in world
                .actors
                .values_mut()
                .filter(|a| !a.is_avatar() && a.present() && !a.needs.body.dead)
            {
                a.journal.fact(
                    now,
                    FactKind::Observation,
                    text.clone(),
                    vec![object.clone()],
                    None,
                    None,
                );
            }
            world.log(EventInfo::default(), text);
        }
        for (id, text) in caught {
            world.actor_mut(&id).journal.fact(
                now,
                FactKind::Observation,
                text,
                vec![object.clone()],
                None,
                None,
            );
        }
    }

    /// 站在圈外的水里额外消耗精力、很快湿透。不看天气开关，只看人在不在圈外。
    fn rates(&self, world: &World, a: &Actor, r: &mut Rates, trace: &mut Trace<'_>) {
        let n = &a.needs;
        if n.body.dead {
            return;
        }
        let Some(depth) = self.depth(world, a) else {
            return;
        };
        if n.on(Need::Energy) {
            r.values[Need::Energy] -= WADING_ENERGY;
        }
        if n.on(Need::Health) {
            r.wet = r.wet.max(WADING_WET);
        }
        note(trace, || {
            format!(
                "站在潮水里（离水边约 {depth:.0} 米）：精力每分钟额外消耗 {WADING_ENERGY:.2} 点，身上很快湿透"
            )
        });
    }

    fn view(&self, world: &World) -> GameModeView {
        GameModeView::Tide(self.state(world.minutes()))
    }

    /// 此刻的公告和自己的位置；人不在时为 None。
    fn context(&self, world: &World, actor: &str) -> Option<GameModeContext> {
        let a = world.actor(actor)?;
        let view = self.state(world.minutes());
        let notice = match view.phase {
            TidePhase::Waiting => "潮水圈：下一个天亮 06:00 公布第 1 圈。".into(),
            TidePhase::Holding => format!("潮水停在第 {} 圈；明天 06:00 公布下一圈。", view.ring),
            TidePhase::Closed => "水已经漫过全岛。".into(),
            TidePhase::Announced | TidePhase::Rising => {
                let node = 3 * (view.ring - 1) + u32::from(view.phase == TidePhase::Rising);
                self.notice(world, node).replace("【潮水】", "")
            }
        };
        Some(GameModeContext::Tide(TideContext {
            notice,
            standing: self.standing(world, a),
        }))
    }
}
