//! 潮水圈：大逃杀式的缩圈，只有一个人能活着离开。
//! 打开后从下一个天亮起，每天 06:00 公布下一圈，12:00 开始涨，18:00 涨到；圈外的地被水盖住。
//! 圈从整座岛的外接圆开始，按种子一圈圈缩小：每一圈都落在上一圈里、都包住终点（全岛最高处），
//! 最后一圈缩到终点上，傍晚水漫过全岛。人在不在水里只看行走地图上的坐标，不按地点。
//!
//! 输赢：打开时在岛上的人是这一局的选手，开局每人口袋里一张纸条写明规则。最后一天天亮，终点停一条船，
//! 只坐得下一个人，谁先登上去（道具动作「登船」，离开这个世界）谁赢；拖到 18:00 没人登船，船带走离它
//! 最近的那个人。在那之前只剩一个人活着，船就提前来接他。一个人也没剩下就没有赢家。
//! 第 1 到第 3 圈公布时，潮水往新圈里冲上来一只木箱：一把菜刀、一个急救包、一包压缩饼干各一箱；
//! 菜刀在前两箱里（第 2、3 天），其余顺序按种子定。每天天亮的公告和题面都写着还剩谁。
//! 有人对人动手、有人倒下、箱子和船都记进战报，名册里给画面看。
//!
//! 圈、公告进度、选手、战报和输赢随快照保存；行走地图不存档，读档后按存下的圈接着涨。
use super::Rules;
use crate::actor::Actor;
use crate::avatar::WalkMap;
use crate::error::{KernelError, Result};
use crate::physiology::{note, Rates, Trace};
use crate::props::{Definition, Instance, Need, Placement};
use crate::{World, DAY};
use protocol::{
    BodyConditionKind, EventInfo, FactKind, GameModeContext, GameModeView, PlaceNear, TideCircle,
    TideContext, TideNews, TideNewsKind, TidePhase, TidePlayer, TideView,
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
/// 平时最长隔多久看一眼谁倒下了、谁上了船（分钟）。
const CHECK_SLICE: f64 = 5.0;
/// 站在水里的人每分钟额外消耗的精力和湿透的速度（比雷暴天露天淋雨还重）。
const WADING_ENERGY: f64 = 0.1;
const WADING_WET: f64 = 3.0;
/// 等圈的空档世界走几倍速；涨潮、船来了、只剩两个人时照常速。
const FREE_TEMPO: f64 = 3.0;
/// 战报留几条。
const NEWS_KEPT: usize = 12;
/// 第几圈公布时冲上来一只木箱（第二局第 3 天才来第一只，那时只剩两个人）。
const CRATE_RINGS: [u32; 3] = [1, 2, 3];
const BOAT_ID: &str = "tide-boat";

/// 给每位选手的模型一直看着的目标。
const GOAL: &str = "只有一个人能活着离开：最后一天会来一条船，只坐得下一个人，谁先登上去就带谁走；在那之前岛上只剩你一个，船就提前来接你。";

/// 箱子里的东西。菜刀和道具库里的 core:kitchen_knife 第 1 版一字不差。
const KNIFE: &str = r#"{"id":"core:kitchen_knife","version":1,"name":"菜刀","description":"一把厚背菜刀，刀口很利。","portable":true,
 "actions":[{"id":"stab","label":"持刀袭击","duration_minutes":3,"completion":"activity",
  "on_complete":[{"kind":"harm","amount":100,"wound":"胸口一处刀伤"}],"recipient":true}]}"#;
const FIRST_AID: &str = r#"{"id":"tide:first-aid","version":1,"name":"急救包","description":"防水布包着的急救包，只够用一次：治病或包扎伤口。","portable":true,
 "actions":[
  {"id":"illness","label":"用急救包治病","duration_minutes":5,"completion":"activity","consumes_item":true,"recipient":true,
   "on_complete":[{"kind":"cure_condition","condition":"illness"}]},
  {"id":"injury","label":"用急救包包扎","duration_minutes":5,"completion":"activity","consumes_item":true,"recipient":true,
   "on_complete":[{"kind":"cure_condition","condition":"injury"},{"kind":"restore","need":"health","amount":20.0}]}]}"#;
const BISCUITS: &str = r#"{"id":"tide:biscuits","version":1,"name":"压缩饼干","description":"油纸包着的压缩饼干，一块顶一顿。","portable":true,"stack_limit":5,
 "actions":[{"id":"eat","label":"吃压缩饼干","duration_minutes":5,"completion":"activity","consumes_item":true,
  "on_complete":[{"kind":"restore","need":"fullness","amount":35.0}]}]}"#;
/// 船沿用道具库里救援小船的图：画面按编号后半段找图。
const BOAT: &str = r#"{"id":"tide:island-rescue-boat","version":1,"name":"来接人的船","description":"最后一天靠岸的小船，只坐得下一个人。谁先登上去，船就带谁走。",
 "actions":[{"id":"board","label":"登船","duration_minutes":10,"completion":"activity",
  "on_complete":[{"kind":"depart","text":"登上了船，离开了荒岛"}]}]}"#;

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
    /// 这一局的选手；旧存档没有，第一次结算时按当时在岛上的人补上。
    #[serde(default)]
    pub players: Vec<TidePlayer>,
    /// 开局的纸条发过了没有。
    #[serde(default)]
    pub briefed: bool,
    #[serde(default)]
    pub news: Vec<TideNews>,
    #[serde(default)]
    pub winner: Option<String>,
    /// 分出了结果（有人上了船，或者一个人也没剩下）：之后不再公布、不再结算。
    #[serde(default)]
    pub over: bool,
    /// 船停在岛上了（最后一天天亮放下，有人上船后撤走）。
    #[serde(default)]
    pub boat: bool,
}

/// 此刻的水边、下一圈、阶段和第几圈。
struct Shape {
    edge: TideCircle,
    next: Option<TideCircle>,
    phase: TidePhase,
    ring: u32,
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

/// 离 p 最近的户外落脚点所在的地点：(地点编号, 地点名)。
fn locale_near(world: &World, p: [f64; 2]) -> Option<(String, String)> {
    let m = world.walk_map.as_ref()?;
    let s = m
        .stations
        .values()
        .filter(|s| s.space == m.outdoor_space)
        .min_by(|a, b| dist(a.position, p).total_cmp(&dist(b.position, p)))?;
    Some((s.locale.clone(), world.topo.locale_name(&s.locale)))
}

fn definition(json: &str) -> Definition {
    serde_json::from_str(json).expect("潮水圈自带的道具定义是写死的")
}

/// 一只装着 `content` 的木箱：撬开一次，东西进撬箱人的背包。编号是 tide:crate-加上东西编号的后半段，
/// 画面按它找木箱的图。
fn crate_of(k: u32, content: &str, count: u32) -> Definition {
    let item = definition(content);
    let what = item.id.rsplit(':').next().unwrap_or("item").to_string();
    definition(
        &serde_json::json!({
            "id": format!("tide:crate-{what}"),
            "version": 1,
            "name": "漂来的木箱",
            "description": format!("第 {k} 圈公布时潮水冲上岸的木箱，钉得很牢，撬开才知道里面是什么。"),
            "actions": [{
                "id": "open", "label": "撬开木箱", "duration_minutes": 15.0, "completion": "activity",
                "during": [{"kind": "labor"}],
                "supply": {"initial": 1, "cost": 1},
                "on_complete": [{"kind": "give_item", "item": item, "count": count}]
            }]
        })
        .to_string(),
    )
}

/// 死因，写给战报和名册：被谁杀的，或者病、饿、渴、累。
fn cause(a: &Actor, wading: bool) -> String {
    let n = &a.needs;
    if let Some(k) = &n.body.killed {
        return format!("被{}杀死（{}）", k.by.name, k.wound);
    }
    let c = n.death_cause(None);
    let has = |k: BodyConditionKind| c.conditions.contains(&k);
    if has(BodyConditionKind::Illness) {
        "病死".into()
    } else if has(BodyConditionKind::Injury) {
        "伤重不治".into()
    } else if has(BodyConditionKind::Poison) {
        "中毒身亡".into()
    } else if c.shortages.contains(&Need::Energy) {
        if wading {
            "泡在潮水里耗尽了力气".into()
        } else {
            "累垮了".into()
        }
    } else if c.shortages.contains(&Need::Water) {
        "渴死".into()
    } else if c.shortages.contains(&Need::Fullness) {
        "饿死".into()
    } else {
        "倒下了".into()
    }
}

impl Tide {
    /// 按这座岛生成一组圈，此刻在岛上的人是选手。要有带地形的行走地图（HD-2D 地图都有）。
    pub(super) fn open(world: &World, seed: u32) -> Result<Self> {
        let map = world
            .walk_map
            .as_ref()
            .ok_or_else(|| KernelError::navigation("这张地图没有行走地形，不能打开潮水圈"))?;
        let mut tide = Self::plan(map, seed, world.minutes())
            .ok_or_else(|| KernelError::navigation("地图上找不到陆地，不能打开潮水圈"))?;
        tide.enlist(world);
        Ok(tide)
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
            players: Vec::new(),
            briefed: false,
            news: Vec::new(),
            winner: None,
            over: false,
            boat: false,
        };
        state.told = state.passed(now);
        Some(state)
    }

    /// 此刻在岛上、活着的居民都是选手（化身不算）。
    fn enlist(&mut self, world: &World) {
        self.players = world
            .actors
            .iter()
            .filter(|(_, a)| !a.is_avatar() && a.present() && !a.needs.body.dead)
            .map(|(id, a)| TidePlayer {
                id: id.clone(),
                name: a.name.clone(),
                fell: None,
            })
            .collect();
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

    /// 名册里的整份状态。
    fn state(&self, now: f64) -> TideView {
        let s = self.shape(now);
        TideView {
            edge: s.edge,
            next: s.next,
            phase: s.phase,
            ring: s.ring,
            rings: self.total(),
            players: self.players.clone(),
            news: self.news.clone(),
            winner: self.winner.clone(),
        }
    }

    /// 此刻的水边、下一圈、阶段和第几圈；每拍每人都要算，不带选手和战报。
    fn shape(&self, now: f64) -> Shape {
        let total = self.total();
        let view = |edge, next, phase, ring| Shape {
            edge,
            next,
            phase: if self.over { TidePhase::Over } else { phase },
            ring,
        };
        for k in 1..=total {
            let base = f64::from(self.first_day + k - 1) * DAY;
            let prev = self.rings[(k - 1) as usize];
            let next = self.rings[k as usize];
            if now < base + ANNOUNCE {
                let phase = if k == 1 {
                    TidePhase::Waiting
                } else {
                    TidePhase::Holding
                };
                return view(prev, None, phase, k - 1);
            }
            if now < base + RISE_FROM {
                return view(prev, Some(next), TidePhase::Announced, k);
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
                return view(edge, Some(next), TidePhase::Rising, k);
            }
        }
        let last = *self.rings.last().expect("至少有外接圆");
        view(last, None, TidePhase::Closed, total)
    }

    /// 站在潮水里时离水边多远（米）；在圈里、在室内或位置不明时为 None。
    fn depth(&self, world: &World, a: &Actor) -> Option<f64> {
        let edge = self.shape(world.minutes()).edge;
        let d = dist(outdoor_point(world, a)?, edge.center) - edge.radius;
        (d > 0.0).then_some(d)
    }

    /// 圈心一带叫什么：离圆心最近的落脚点所在的地点。
    fn place(world: &World, center: [f64; 2]) -> String {
        locale_near(world, center).map_or_else(|| "岛中间".into(), |(_, name)| name)
    }

    /// 最后一天在第几天（第 1 天记作 1）。
    fn last_day(&self) -> u32 {
        self.first_day + self.total()
    }

    fn notice(&self, world: &World, node: u32) -> String {
        let k = node / 3 + 1;
        let ring = self.rings[k as usize];
        let last = k == self.total();
        let place = Self::place(world, ring.center);
        match (node % 3, last) {
            (0, true) => format!(
                "【潮水】最后一圈已公布：今天 12:00 开始涨，18:00 前水会漫过全岛。船停在「{place}」一带的最高处，只坐得下一个人，谁先登上去就带谁走；18:00 还没人登船，船带走离它最近的那个人。"
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

    /// 开局的纸条：规则写全，第 1 圈哪天公布照实写。
    fn note(&self, world: &World) -> String {
        let today = (world.minutes() / DAY).floor() as u32;
        let first = if self.first_day == today {
            "今天".to_string()
        } else if self.first_day == today + 1 {
            "明天".to_string()
        } else {
            format!("第 {} 天", self.first_day + 1)
        };
        format!(
            "【纸条】每个人醒来时，口袋里都有一张同样的纸条：「潮水每天收一圈：天亮 06:00 公布当天的圈，12:00 开始涨，18:00 涨到，圈外的地会被淹；第 1 圈{first}天亮公布。第 {} 天会来一条船，只坐得下一个人，谁先登上去就带谁走。在那之前岛上只剩一个人，船就提前来接他。」",
            self.last_day()
        )
    }

    /// 这个人和水边、下一圈、船的关系，写给模型看；没有可说的时为 None。
    fn standing(&self, world: &World, a: &Actor) -> Option<String> {
        let view = self.shape(world.minutes());
        let here = outdoor_point(world, a)?;
        let edge = view.edge;
        let out = dist(here, edge.center) - edge.radius;
        let boat = self.boat.then(|| {
            let goal = self.rings.last().expect("至少有外接圆").center;
            format!(
                "船离你约 {:.0} 米，在你的{}边。",
                dist(here, goal).ceil(),
                direction(here, goal)
            )
        });
        let water = if out > 0.0 {
            Some(format!(
                "你站在潮水里，离水边约 {:.0} 米；往{}走能回到圈里。",
                out.ceil(),
                direction(here, edge.center)
            ))
        } else {
            view.next.map(|next| {
                let gap = dist(here, next.center) - next.radius;
                if next.radius <= 0.0 {
                    "傍晚水会漫过全岛。".into()
                } else if gap > 0.0 {
                    format!(
                        "你离下一圈的边约 {:.0} 米，在圈外；往{}走能进圈。",
                        gap.ceil(),
                        direction(here, next.center)
                    )
                } else {
                    format!("你在下一圈里面，离它的边约 {:.0} 米。", (-gap).floor())
                }
            })
        };
        match (water, boat) {
            (Some(w), Some(b)) => Some(format!("{w}{b}")),
            (w, b) => w.or(b),
        }
    }

    fn player(&self, id: &str) -> Option<&TidePlayer> {
        self.players.iter().find(|p| p.id == id)
    }

    /// 还活着的人的名字，按入住顺序用顿号连起来。
    fn alive_names(&self) -> String {
        self.alive()
            .iter()
            .filter_map(|id| self.player(id))
            .map(|p| p.name.as_str())
            .collect::<Vec<_>>()
            .join("、")
    }

    fn alive(&self) -> Vec<String> {
        self.players
            .iter()
            .filter(|p| p.fell.is_none() && self.winner.as_deref() != Some(&p.id))
            .map(|p| p.id.clone())
            .collect()
    }

    fn say(&mut self, now: f64, kind: TideNewsKind, text: String) {
        self.news.push(TideNews {
            at: now,
            kind,
            text,
        });
        let extra = self.news.len().saturating_sub(NEWS_KEPT);
        self.news.drain(..extra);
    }

    /// 公告写进还活着的人的经历和世界日志。
    fn announce(world: &mut World, object: &str, text: &str) {
        let now = world.minutes();
        for a in world
            .actors
            .values_mut()
            .filter(|a| !a.is_avatar() && a.present() && !a.needs.body.dead)
        {
            a.journal.fact(
                now,
                FactKind::Observation,
                text.to_string(),
                vec![object.to_string()],
                None,
                None,
            );
        }
        world.log(EventInfo::default(), text.to_string());
    }

    /// 在离 p 最近的地点里、靠近 p 的空位放一件道具；放不下就算了。返回地点名。
    fn drop_near(world: &mut World, id: &str, def: Definition, p: [f64; 2]) -> Option<String> {
        let (locale, name) = locale_near(world, p)?;
        let space = world.walk_map.as_ref()?.outdoor_space.clone();
        let placement = Placement {
            instance: Instance {
                id: id.into(),
                definition: def.reference(),
                locale,
                name: None,
                board: None,
            },
            definition: def,
        };
        let near = PlaceNear { space, position: p };
        world
            .place_prop_near(placement.clone(), Some(&near))
            .or_else(|_| world.place_prop(placement))
            .ok()
            .map(|()| name)
    }

    /// 第 k 圈公布时冲上来的木箱：菜刀在前两箱里的哪一箱、急救包和压缩饼干谁先，按种子定。
    fn wash_up_crate(&mut self, world: &mut World, k: u32) -> Option<String> {
        let slot = CRATE_RINGS.iter().position(|&r| r == k)?;
        let mut dice = self.seed.max(1) ^ 0x5bd1_e995;
        let knife = usize::from(roll(&mut dice) >= 0.5);
        let mut rest = [(FIRST_AID, 1), (BISCUITS, 3)];
        if roll(&mut dice) >= 0.5 {
            rest.swap(0, 1);
        }
        let mut rest = rest.into_iter();
        let contents: Vec<_> = (0..CRATE_RINGS.len())
            .map(|i| {
                if i == knife {
                    (KNIFE, 1)
                } else {
                    rest.next().expect("三箱：一箱菜刀，另两样各一箱")
                }
            })
            .collect();
        let (content, count) = contents[slot];
        let center = self.rings[k as usize].center;
        let place = Self::drop_near(
            world,
            &format!("tide-crate-{k}"),
            crate_of(k, content, count),
            center,
        )?;
        Some(format!("【潮水】潮水冲上来一只木箱，搁在「{place}」一带。"))
    }

    /// 有人上了船：他赢了，船撤走，这一局结束。`what` 是一整句经过（不带【潮水】）。
    fn sail(&mut self, world: &mut World, object: &str, id: &str, what: &str) {
        let now = world.minutes();
        self.winner = Some(id.to_string());
        self.over = true;
        if self.boat {
            let _ = world.remove_prop(BOAT_ID);
            self.boat = false;
        }
        self.say(now, TideNewsKind::Boat, what.to_string());
        Self::announce(world, object, &format!("【潮水】{what}"));
    }

    fn name_of(&self, id: &str) -> String {
        self.player(id).map_or_else(String::new, |p| p.name.clone())
    }

    /// 看一眼选手：谁倒下了、谁上了船，只剩一个人时船提前来。
    fn check_players(&mut self, world: &mut World, object: &str) {
        let now = world.minutes();
        let mut fallen = Vec::new();
        let mut boarded = None;
        for p in self.players.iter().filter(|p| p.fell.is_none()) {
            match world.actor(&p.id) {
                Some(a) if a.needs.body.dead => {
                    let place = world.topo.locale_name(&a.locus.locale);
                    let wading = self.depth(world, a).is_some();
                    fallen.push((p.id.clone(), place, cause(a, wading)));
                }
                Some(a) if a.present() => {}
                // 不在岛上了：船在的时候是登船走的，不然是被请出了这一局
                _ if self.boat && boarded.is_none() && self.winner.is_none() => {
                    boarded = Some(p.id.clone());
                }
                _ => fallen.push((p.id.clone(), String::new(), "离开了这一局".into())),
            }
        }
        for (id, place, why) in fallen {
            let name = self
                .player(&id)
                .map_or_else(String::new, |p| p.name.clone());
            if let Some(p) = self.players.iter_mut().find(|p| p.id == id) {
                p.fell = Some(why.clone());
            }
            let text = if place.is_empty() {
                format!("{name}{why}")
            } else {
                format!("{name}倒在{place}：{why}")
            };
            self.say(now, TideNewsKind::Fell, text);
        }
        if let Some(id) = boarded {
            let name = self.name_of(&id);
            self.sail(
                world,
                object,
                &id,
                &format!("{name}登上了船，是这一局唯一活着离开的人。"),
            );
            return;
        }
        let alive = self.alive();
        if self.players.len() >= 2 && alive.len() == 1 {
            let id = alive[0].clone();
            world.depart(&id, "被提前开来的船接走，离开了荒岛");
            let name = self.name_of(&id);
            self.sail(
                world,
                object,
                &id,
                &format!(
                    "岛上只剩{name}一个人了，船提前开来接走了他。{name}是这一局唯一活着离开的人。"
                ),
            );
        } else if alive.is_empty() && !self.players.is_empty() {
            self.over = true;
            let text = "【潮水】最后一个人也倒下了，没有人等到船。".to_string();
            self.say(now, TideNewsKind::Fell, text.replace("【潮水】", ""));
            Self::announce(world, object, &text);
        }
    }

    /// 最后一天 18:00 还没人登船：船带走离终点最近的活人。
    fn last_call(&mut self, world: &mut World, object: &str) {
        let goal = self.rings.last().expect("至少有外接圆").center;
        let nearest = self
            .alive()
            .into_iter()
            .filter_map(|id| {
                let a = world.actor(&id)?;
                let d = outdoor_point(world, a).map_or(f64::INFINITY, |p| dist(p, goal));
                Some((id, d))
            })
            .min_by(|a, b| a.1.total_cmp(&b.1));
        if let Some((id, _)) = nearest {
            world.depart(&id, "被船带走，离开了荒岛");
            let name = self.name_of(&id);
            self.sail(
                world,
                object,
                &id,
                &format!("{name}离船最近，被船带走了，是这一局唯一活着离开的人。"),
            );
        }
    }
}

impl Rules for Tide {
    const ID: &'static str = "tide";

    /// 离下一个节点还有多久；涨潮时最多隔几分钟切一次，好及时判断谁被水追上；
    /// 平时也隔几分钟看一眼谁倒下了、谁上了船。分出结果后不再结算。
    fn boundary(&self, world: &World) -> f64 {
        if self.over {
            return f64::INFINITY;
        }
        let now = world.minutes();
        let next = (0..self.nodes())
            .map(|i| self.node_time(i))
            .find(|t| *t > now + 1e-9)
            .map_or(f64::INFINITY, |t| t - now);
        let slice = if self.shape(now).phase == TidePhase::Rising {
            RISING_SLICE
        } else {
            CHECK_SLICE
        };
        next.min(slice)
    }

    /// 发纸条、到点的公告、木箱和船；刚被水追上的人记一笔自己的处境；选手倒下、上船、只剩一人。
    fn advance(&mut self, world: &mut World) {
        if self.over {
            return;
        }
        let now = world.minutes();
        let object = format!("tide:{}", self.seed);
        if self.players.is_empty() {
            self.enlist(world);
        }
        if !self.briefed {
            self.briefed = true;
            let note = self.note(world);
            Self::announce(world, &object, &note);
        }
        while self.told < self.nodes() && self.node_time(self.told) <= now + 1e-9 {
            let node = self.told;
            self.told += 1;
            let mut text = self.notice(world, node);
            let k = node / 3 + 1;
            let last = k == self.total();
            if node % 3 == 0 && last {
                let goal = self.rings[k as usize].center;
                self.boat = Self::drop_near(world, BOAT_ID, definition(BOAT), goal).is_some();
                if self.boat {
                    self.say(
                        now,
                        TideNewsKind::Boat,
                        "最后一天，船停在了岛的最高处".into(),
                    );
                }
            } else if node % 3 == 0 {
                if let Some(line) = self.wash_up_crate(world, k) {
                    self.say(now, TideNewsKind::Crate, line.replace("【潮水】", ""));
                    text = format!("{text}{}", line.replace("【潮水】", ""));
                }
            }
            // 天亮公布时提一句还剩谁：第二局 834 条心声里只有 4 条想到「只活一个」
            if node % 3 == 0 && !self.players.is_empty() {
                let alive = self.alive();
                text = format!(
                    "{text}岛上还剩 {} 个人：{}。",
                    alive.len(),
                    self.alive_names()
                );
            }
            Self::announce(world, &object, &text);
            if node % 3 == 2 && last {
                self.check_players(world, &object);
                if !self.over {
                    self.last_call(world, &object);
                }
                return;
            }
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
        self.check_players(world, &object);
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

    /// 等圈的空档走快一点；涨潮、船来了、只剩两个人、分出结果后照常速。
    fn tempo(&self, world: &World) -> f64 {
        let busy = self.over
            || self.boat
            || self.alive().len() <= 2
            || self.shape(world.minutes()).phase == TidePhase::Rising;
        if busy {
            1.0
        } else {
            FREE_TEMPO
        }
    }

    /// 选手看得到这一局怎么才算活下来；此刻的公告和自己的位置。人不在时为 None。
    fn context(&self, world: &World, actor: &str) -> Option<GameModeContext> {
        let a = world.actor(actor)?;
        let view = self.shape(world.minutes());
        let winner = self
            .winner
            .as_deref()
            .and_then(|id| self.player(id))
            .map(|p| p.name.clone());
        let notice = match view.phase {
            TidePhase::Over => match winner {
                Some(name) => format!("这一局结束了：{name}上了船。"),
                None => "这一局结束了，没有人等到船。".into(),
            },
            TidePhase::Waiting => "潮水圈：下一个天亮 06:00 公布第 1 圈。".into(),
            TidePhase::Holding => format!("潮水停在第 {} 圈；明天 06:00 公布下一圈。", view.ring),
            TidePhase::Closed => "水已经漫过全岛。".into(),
            TidePhase::Announced | TidePhase::Rising => {
                let node = 3 * (view.ring - 1) + u32::from(view.phase == TidePhase::Rising);
                self.notice(world, node).replace("【潮水】", "")
            }
        };
        let playing = !self.over && self.player(actor).is_some_and(|p| p.fell.is_none());
        let goal = if playing {
            format!(
                "{GOAL}眼下岛上还活着 {} 个人：{}。",
                self.alive().len(),
                self.alive_names()
            )
        } else {
            String::new()
        };
        Some(GameModeContext::Tide(TideContext {
            goal,
            notice,
            standing: self.standing(world, a),
        }))
    }

    /// 选手之间动手记进战报。
    fn clash(&mut self, world: &World, actor: &str, target: &str, text: &str) {
        if self.over || (self.player(actor).is_none() && self.player(target).is_none()) {
            return;
        }
        self.say(world.minutes(), TideNewsKind::Clash, text.to_string());
    }
}
