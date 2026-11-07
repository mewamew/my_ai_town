//! 狼人杀：法官是这里的一个状态机，把回合套在照旧异步的小镇上。
//! 白天村民自己过；16:30 敲钟，17:00 在议事广场按座次一次叫醒一个人发言，然后同时投票放逐一人
//! （第 1 天是相识日，只自我介绍）；被放逐的人留遗言后走出村子。天黑后狼人在狼人频道轮流说话、
//! 选刀口，预言家、守卫同时行动，女巫等狼人选完再决定；天亮公布昨晚倒下的人，不说死因、不翻牌。
//! 法官往下走只看两件事：该交的人交了，或者到点了（期限按游戏分钟，挂在 boundary 上）。
//! 只叫醒该做事的人：别人的发言写进每个人的经历，不发通知；投票和夜里行动这类同时进行的窗口，
//! 结算前不发通知，免得正在想的人被「重要通知」退回。身份、轮到谁、票和夜里的选择都存在这里，随快照保存。
use super::Rules;
use crate::error::{KernelError, Result};
use crate::{World, DAY};
use protocol::{
    DeathCause, EventActor, EventInfo, FactKind, GameModeAction, GameModeContext, GameModeView,
    Killing, WerewolfBallot, WerewolfCheck, WerewolfContext, WerewolfLine, WerewolfNight,
    WerewolfOut as Out, WerewolfPhase as Phase, WerewolfRole as Role, WerewolfSeat,
    WerewolfSide as Side, WerewolfView,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// 白天自由活动几小时：天亮到敲钟。不给时 6 小时。
const DAY_HOURS: std::ops::RangeInclusive<u32> = 1..=9;
const DEFAULT_DAY_HOURS: u32 = 6;
/// 16:30 敲钟，17:00 议事（当天第几分钟）。
const BELL: f64 = 990.0;
const MEET: f64 = 1020.0;
/// 议事散了以后过多久入夜，入夜不早于 19:00。
const CURFEW: f64 = 30.0;
const NIGHT_FROM: f64 = 1140.0;
/// 每一步的期限（游戏分钟）：到点没交就往下走。
const SPEAK_MINUTES: f64 = 15.0;
const VOTE_MINUTES: f64 = 15.0;
const LAST_WORDS_MINUTES: f64 = 10.0;
const SHOT_MINUTES: f64 = 15.0;
const WOLF_MINUTES: f64 = 15.0;
const WITCH_MINUTES: f64 = 20.0;
/// 预言家、守卫从入夜起多久内要交。
const ROLE_MINUTES: f64 = 60.0;
/// 被放逐的人说完遗言后多久离开地图。
const LEAVE_MINUTES: f64 = 20.0;
/// 一段发言最多多少字（交谈原有的上限）。
const SPEECH_CHARS: usize = 400;
/// 夜里倒下的人身上看到的样子：被刀和被毒看起来一样，发现尸体的人分不出死因。
const NIGHT_WOUND: &str = "脸色发青";
const PLAYERS: std::ops::RangeInclusive<usize> = 6..=12;
const EPS: f64 = 1e-6;

/// 按人数配板子：狼人几只、有哪些神职、平民几个。
fn board(players: usize) -> Vec<Role> {
    use Role::*;
    let (wolves, gods, villagers): (usize, &[Role], usize) = match players {
        6 => (2, &[Seer, Witch], 2),
        7 => (2, &[Seer, Witch, Hunter], 2),
        8 => (2, &[Seer, Witch, Hunter], 3),
        9 => (3, &[Seer, Witch, Hunter], 3),
        10 => (3, &[Seer, Witch, Hunter, Guard], 3),
        11 => (3, &[Seer, Witch, Hunter, Guard], 4),
        _ => (4, &[Seer, Witch, Hunter, Guard], 4),
    };
    let mut roles = vec![Wolf; wolves];
    roles.extend_from_slice(gods);
    roles.extend(std::iter::repeat_n(Villager, villagers));
    roles
}

fn role_name(role: Role) -> &'static str {
    match role {
        Role::Wolf => "狼人",
        Role::Seer => "预言家",
        Role::Witch => "女巫",
        Role::Hunter => "猎人",
        Role::Guard => "守卫",
        Role::Villager => "平民",
    }
}

fn is_god(role: Role) -> bool {
    matches!(role, Role::Seer | Role::Witch | Role::Hunter | Role::Guard)
}

/// xorshift32；状态不能为 0。
fn roll(state: &mut u32) -> u32 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    x
}

/// 只留前 n 个字；截掉了返回 true。
fn clip(text: &str, n: usize) -> (String, bool) {
    let text = text.trim();
    if text.chars().count() <= n {
        return (text.to_string(), false);
    }
    (text.chars().take(n).collect(), true)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Seat {
    pub id: String,
    pub name: String,
    pub role: Role,
    #[serde(default)]
    pub out: Option<Out>,
    #[serde(default)]
    pub out_day: Option<u32>,
    /// 只有自己知道的事：同伴、查验结果、用过的药……
    #[serde(default)]
    pub notes: Vec<String>,
}

/// 这一轮发言是什么。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Round {
    /// 第 1 天的自我介绍，说完不投票
    #[default]
    Intro,
    /// 议事，说完投票
    Debate,
    /// 平票的人各再说一句，说完重投
    Tie,
}

/// 猎人开完枪接着做什么。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AfterShot {
    /// 天亮被狼人杀害：开完枪他才倒下，接着过白天
    #[default]
    Dawn,
    /// 白天被放逐：开完枪走出村子，接着入夜
    Exile,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ballot {
    pub target: Option<usize>,
    #[serde(default)]
    pub reason: Option<String>,
}

/// 一夜里的选择和进度。座位都是下标。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Night {
    pub night: u32,
    pub wolf_lines: Vec<WerewolfLine>,
    /// 狼人选的刀口，按先后：（狼人，刀口）
    pub picks: Vec<(usize, usize)>,
    pub wolf_queue: Vec<usize>,
    pub wolf_turn: Option<usize>,
    pub wolf_round: u32,
    pub wolf_until: f64,
    pub wolves_done: bool,
    pub kill: Option<usize>,
    pub guard: Option<usize>,
    pub guard_done: bool,
    pub check: Option<(usize, bool)>,
    pub seer_done: bool,
    /// 预言家、守卫的期限
    pub roles_until: f64,
    /// 女巫被叫醒了
    pub witch_called: bool,
    pub witch_until: f64,
    pub witch_done: bool,
    pub save: bool,
    pub poison: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Werewolf {
    pub seed: u32,
    pub day_hours: u32,
    /// 第 1 天是世界的第几天（从 0 数）
    pub first_day: u32,
    pub seats: Vec<Seat>,
    pub phase: Phase,
    /// 第几天；开局前是 0
    pub day: u32,
    /// 这一步的期限或下一个钟点（世界分钟）；夜里看 night 里的几个期限和天亮
    pub until: f64,
    /// 议事广场的地点编号；地图上没有时不记发言的人到没到场
    #[serde(default)]
    pub meeting: Option<String>,
    #[serde(default)]
    pub turn: Option<usize>,
    /// 还没轮到的人，按次序
    #[serde(default)]
    pub queue: Vec<usize>,
    #[serde(default)]
    pub round: Round,
    /// 今天的发言和遗言
    #[serde(default)]
    pub lines: Vec<WerewolfLine>,
    #[serde(default)]
    pub ballots: BTreeMap<usize, Ballot>,
    #[serde(default)]
    pub revealed: bool,
    /// 平票重投时只能投这几个人
    #[serde(default)]
    pub tied: Vec<usize>,
    #[serde(default)]
    pub after_shot: AfterShot,
    /// 被放逐、还没走出地图的人：（座位，离开的时刻）
    #[serde(default)]
    pub leaving: Vec<(usize, f64)>,
    #[serde(default)]
    pub night: Night,
    /// 天亮公布的昨晚倒下的人
    #[serde(default)]
    pub dawn: Vec<usize>,
    pub save_left: bool,
    pub poison_left: bool,
    #[serde(default)]
    pub last_guard: Option<usize>,
    /// 公开的经过：每天、每夜一两句
    #[serde(default)]
    pub history: Vec<String>,
    #[serde(default)]
    pub winner: Option<Side>,
}

impl Werewolf {
    /// 按此刻在镇上的村民发身份（按编号排座次）。第 1 天从今天开始，过了 15:30 就从明天开始；
    /// 天亮前是开局前的等待。
    pub(super) fn open(world: &World, seed: u32, day_hours: Option<u32>) -> Result<Self> {
        let mut ids: Vec<&String> = world
            .actors
            .iter()
            .filter(|(_, a)| !a.is_avatar() && a.present() && !a.needs.body.dead)
            .map(|(id, _)| id)
            .collect();
        ids.sort();
        if ids.len() < *PLAYERS.start() {
            return Err(KernelError::action(format!(
                "狼人杀要 {}–{} 个村民，现在镇上只有 {} 个",
                PLAYERS.start(),
                PLAYERS.end(),
                ids.len()
            )));
        }
        ids.truncate(*PLAYERS.end());
        let day_hours = day_hours.unwrap_or(DEFAULT_DAY_HOURS);
        if !DAY_HOURS.contains(&day_hours) {
            return Err(KernelError::action(format!(
                "白天要在 {}–{} 小时之间",
                DAY_HOURS.start(),
                DAY_HOURS.end()
            )));
        }
        // 洗牌：同一个种子、同样的人，身份每次都一样
        let mut roles = board(ids.len());
        let mut dice = seed.max(1);
        for i in (1..roles.len()).rev() {
            let j = roll(&mut dice) as usize % (i + 1);
            roles.swap(i, j);
        }
        let seats: Vec<Seat> = ids
            .iter()
            .zip(roles)
            .map(|(id, role)| Seat {
                id: (*id).clone(),
                name: world.actors[*id].name.clone(),
                role,
                out: None,
                out_day: None,
                notes: Vec::new(),
            })
            .collect();
        let now = world.minutes();
        let today = (now / DAY).floor() as u32;
        let first_day = if crate::time_of_day(now) < BELL - 60.0 {
            today
        } else {
            today + 1
        };
        let meeting = world
            .topo
            .locales
            .values()
            .find(|l| l.name.contains("议事"))
            .or_else(|| {
                world
                    .topo
                    .locales
                    .values()
                    .find(|l| l.name.contains("广场"))
            })
            .map(|l| l.id.clone());
        let mut state = Self {
            seed,
            day_hours,
            first_day,
            seats,
            phase: Phase::Waiting,
            day: 0,
            until: 0.0,
            meeting,
            turn: None,
            queue: Vec::new(),
            round: Round::Intro,
            lines: Vec::new(),
            ballots: BTreeMap::new(),
            revealed: false,
            tied: Vec::new(),
            after_shot: AfterShot::Dawn,
            leaving: Vec::new(),
            night: Night::default(),
            dawn: Vec::new(),
            save_left: true,
            poison_left: true,
            last_guard: None,
            history: Vec::new(),
            winner: None,
        };
        // 第 1 天的天亮已经过了：开钟就算天亮
        state.until = state.dawn_at(1).max(now);
        Ok(state)
    }

    // ---------- 钟点 ----------

    fn day_start(&self, day: u32) -> f64 {
        f64::from(self.first_day + day.max(1) - 1) * DAY
    }
    fn dawn_at(&self, day: u32) -> f64 {
        self.day_start(day) + BELL - f64::from(self.day_hours) * 60.0
    }
    fn clock(at: f64) -> String {
        let t = crate::time_of_day(at).round() as i64;
        format!("{:02}:{:02}", t / 60 % 24, t % 60)
    }

    // ---------- 座位 ----------

    fn alive(&self, i: usize) -> bool {
        self.seats[i].out.is_none()
    }
    fn living(&self) -> Vec<usize> {
        (0..self.seats.len()).filter(|&i| self.alive(i)).collect()
    }
    fn label(&self, i: usize) -> String {
        format!("{} 号 {}", i + 1, self.seats[i].name)
    }
    fn seat_of(&self, actor: &str) -> Option<usize> {
        self.seats.iter().position(|s| s.id == actor)
    }
    fn living_role(&self, role: Role) -> Vec<usize> {
        self.living()
            .into_iter()
            .filter(|&i| self.seats[i].role == role)
            .collect()
    }
    /// 「3」「3 号」「芬恩」都认；认不出或不在座位上时说明原因。
    fn target(&self, action: &GameModeAction) -> Result<usize> {
        let raw = action
            .target
            .as_deref()
            .map(str::trim)
            .filter(|t| !t.is_empty())
            .ok_or_else(|| KernelError::action("要填 target：对方的座号"))?;
        let digits: String = raw.chars().take_while(char::is_ascii_digit).collect();
        let found = digits
            .parse::<usize>()
            .ok()
            .filter(|n| (1..=self.seats.len()).contains(n))
            .map(|n| n - 1)
            .or_else(|| self.seats.iter().position(|s| s.name == raw || s.id == raw));
        found.ok_or_else(|| {
            KernelError::action(format!(
                "认不出 target「{raw}」：填座号（1–{}）",
                self.seats.len()
            ))
        })
    }
    fn living_target(&self, action: &GameModeAction) -> Result<usize> {
        let t = self.target(action)?;
        if !self.alive(t) {
            return Err(KernelError::action(format!("{} 已经出局了", self.label(t))));
        }
        Ok(t)
    }

    fn winner_now(&self) -> Option<Side> {
        let count = |f: &dyn Fn(Role) -> bool| {
            self.living()
                .into_iter()
                .filter(|&i| f(self.seats[i].role))
                .count()
        };
        if count(&|r| r == Role::Wolf) == 0 {
            Some(Side::Good)
        } else if count(&|r| r == Role::Villager) == 0 || count(&is_god) == 0 {
            Some(Side::Wolf)
        } else {
            None
        }
    }

    // ---------- 告诉谁 ----------

    fn object(&self) -> Vec<String> {
        vec![format!("werewolf:{}", self.seed)]
    }

    /// 在场、活着的人（座位下标）：死了或已经走出地图的不再收话。
    fn listeners(&self, world: &World, who: &[usize]) -> Vec<String> {
        who.iter()
            .map(|&i| &self.seats[i].id)
            .filter(|id| {
                world
                    .actor(id)
                    .is_some_and(|a| a.present() && !a.needs.body.dead)
            })
            .cloned()
            .collect()
    }

    /// 写进这些人的经历，不叫醒。
    fn tell(&self, world: &mut World, who: &[usize], text: &str) {
        let now = world.minutes();
        for id in self.listeners(world, who) {
            world.actor_mut(&id).journal.fact(
                now,
                FactKind::Observation,
                text.to_string(),
                self.object(),
                None,
                None,
            );
        }
    }

    /// 叫醒一个人：正在私聊的先散场，免得只轮到交谈的回合、交不了玩法动作。
    fn call(&self, world: &mut World, i: usize, text: &str) {
        let Some(id) = self.listeners(world, &[i]).pop() else {
            return;
        };
        if world.active_chat(&id).is_some() {
            world.interrupt_actions(&id, "狼人杀轮到你了");
        }
        world.notify(&id, text.to_string());
    }

    /// 对所有还在座的人宣布，记进世界日志；wake 时叫醒每个人，否则只写进经历。
    fn announce(&self, world: &mut World, text: &str, wake: bool) {
        let living = self.living();
        if wake {
            for i in living {
                self.call(world, i, text);
            }
        } else {
            self.tell(world, &living, text);
        }
        world.log(EventInfo::default(), text.to_string());
    }

    /// 这个人倒下：健康归零，按遇害结算（中断手上的事、留下尸体、发现尸体照常）。
    fn fell(&self, world: &mut World, i: usize, by: &str, wound: &str) {
        let id = self.seats[i].id.clone();
        let Some(a) = world.actor(&id) else {
            return;
        };
        if !a.present() || a.needs.body.dead {
            return;
        }
        let was = a.needs.abilities();
        world.actor_mut(&id).needs.lose_health(100.0);
        world.reconcile_body(
            &id,
            was,
            by,
            DeathCause {
                killed: Some(Killing {
                    by: EventActor {
                        id: format!("werewolf:{}", self.seed),
                        name: by.into(),
                    },
                    wound: wound.into(),
                }),
                ..DeathCause::default()
            },
        );
    }

    fn line(&self, world: &World, i: usize, text: String, last: bool) -> WerewolfLine {
        let away = self.meeting.as_ref().is_some_and(|m| {
            world
                .actor(&self.seats[i].id)
                .is_none_or(|a| &a.locus.locale != m)
        });
        WerewolfLine {
            seat: i as u32 + 1,
            text,
            at: world.minutes(),
            away,
            last,
        }
    }

    // ---------- 白天 ----------

    /// 白天开始：清掉昨天的发言和票，等 16:30 敲钟。
    fn begin_day(&mut self) {
        self.phase = Phase::Day;
        self.until = self.day_start(self.day) + BELL;
        self.turn = None;
        self.lines.clear();
        self.ballots.clear();
        self.revealed = false;
        self.tied.clear();
    }

    fn schedule(&self) -> String {
        format!(
            "16:30 钟楼敲钟，17:00 在议事广场{}。",
            if self.day == 1 {
                "轮流自我介绍"
            } else {
                "按座次发言，然后投票放逐一人"
            }
        )
    }

    /// 第 1 天天亮：每人单独收到自己的身份（狼人还有同伴）。
    fn first_dawn(&mut self, world: &mut World) {
        self.day = 1;
        self.begin_day();
        let schedule = self.schedule();
        world.log(
            EventInfo::default(),
            format!("【狼人杀】天亮了，第 1 天（相识日）。身份已经发下。{schedule}"),
        );
        let wolves: Vec<usize> = self.living_role(Role::Wolf);
        for i in 0..self.seats.len() {
            let role = self.seats[i].role;
            let mut text = format!(
                "【狼人杀】天亮了，第 1 天（相识日）。你是 {}，身份是{}。",
                self.label(i),
                role_name(role)
            );
            if role == Role::Wolf {
                let mates: Vec<String> = wolves
                    .iter()
                    .filter(|&&w| w != i)
                    .map(|&w| self.label(w))
                    .collect();
                let note = format!("狼人同伴：{}", mates.join("、"));
                text.push_str(&note);
                text.push('。');
                self.seats[i].notes.push(note);
            }
            text.push_str(&schedule);
            self.call(world, i, &text);
        }
    }

    fn ring_bell(&mut self, world: &mut World) {
        self.phase = Phase::Gather;
        self.until = self.day_start(self.day) + MEET;
        self.announce(
            world,
            "【狼人杀】16:30 钟楼敲钟：所有人去议事广场，17:00 开始议事。",
            true,
        );
    }

    /// 17:00 议事：从当天的起始座位顺时针，一次叫一个人。
    fn open_assembly(&mut self, world: &mut World) {
        let living = self.living();
        let n = self.seats.len();
        let start = (self.seed as usize + self.day as usize * 3) % n;
        let mut order: Vec<usize> = (0..n).map(|k| (start + k) % n).collect();
        order.retain(|i| living.contains(i));
        self.round = if self.day == 1 {
            Round::Intro
        } else {
            Round::Debate
        };
        let first = order.first().copied().unwrap_or(0);
        self.queue = order;
        self.phase = Phase::Speech;
        let what = if self.round == Round::Intro {
            "每人自我介绍一次，今天不投票"
        } else {
            "每人发言一次，然后投票"
        };
        let text = format!(
            "【狼人杀】17:00 议事开始：从 {} 起顺时针，{what}。",
            self.label(first)
        );
        self.announce(world, &text, false);
        self.next_speaker(world);
    }

    fn next_speaker(&mut self, world: &mut World) {
        let now = world.minutes();
        while !self.queue.is_empty() {
            let i = self.queue.remove(0);
            if !self.alive(i) {
                continue;
            }
            self.turn = Some(i);
            self.until = now + SPEAK_MINUTES;
            let what = match self.round {
                Round::Tie => "平票了，你再说一句为自己辩护",
                Round::Intro => "轮到你自我介绍",
                Round::Debate => "轮到你发言",
            };
            let text = format!(
                "【狼人杀】{what}：用 mode_action 交 speak，text 写你要说的话（最多 {SPEECH_CHARS} 字）。{SPEAK_MINUTES:.0} 分钟内不交算跳过。"
            );
            self.call(world, i, &text);
            return;
        }
        self.turn = None;
        match self.round {
            Round::Intro => {
                self.history
                    .push(format!("第 {} 天：自我介绍，没有投票", self.day));
                self.close_day(world);
            }
            Round::Debate | Round::Tie => self.start_vote(world),
        }
    }

    fn start_vote(&mut self, world: &mut World) {
        self.phase = Phase::Vote;
        self.ballots.clear();
        self.revealed = false;
        self.until = world.minutes() + VOTE_MINUTES;
        let text = if self.tied.is_empty() {
            format!(
                "【狼人杀】发言结束，开始投票：用 mode_action 交 vote，target 填要放逐的人的座号；不投交 abstain。所有人交齐后一起亮票，{VOTE_MINUTES:.0} 分钟内不交算弃票。"
            )
        } else {
            let names: Vec<String> = self.tied.iter().map(|&i| self.label(i)).collect();
            format!(
                "【狼人杀】重新投票，只能投平票的 {}：用 mode_action 交 vote 或 abstain。",
                names.join("、")
            )
        };
        self.announce(world, &text, true);
    }

    /// 亮票：票最多的一人被放逐；平票的各再说一句重投，再平就没人被放逐。
    fn reveal(&mut self, world: &mut World) {
        self.revealed = true;
        let living = self.living();
        let mut tally: BTreeMap<usize, Vec<usize>> = BTreeMap::new();
        let mut abstained = Vec::new();
        for &v in &living {
            match self.ballots.get(&v).and_then(|b| b.target) {
                Some(t) => tally.entry(t).or_default().push(v),
                None => abstained.push(v),
            }
        }
        let most = tally.values().map(Vec::len).max().unwrap_or(0);
        let mut parts: Vec<(usize, String)> = tally
            .iter()
            .map(|(t, voters)| {
                let who: Vec<String> = voters.iter().map(|v| (v + 1).to_string()).collect();
                (
                    voters.len(),
                    format!(
                        "{} {} 票（{} 号投）",
                        self.label(*t),
                        voters.len(),
                        who.join("、")
                    ),
                )
            })
            .collect();
        parts.sort_by(|a, b| b.0.cmp(&a.0));
        let mut summary: Vec<String> = parts.into_iter().map(|(_, s)| s).collect();
        if !abstained.is_empty() {
            let who: Vec<String> = abstained.iter().map(|v| (v + 1).to_string()).collect();
            summary.push(format!("{} 号弃票", who.join("、")));
        }
        let top: Vec<usize> = tally
            .iter()
            .filter(|(_, v)| v.len() == most && most > 0)
            .map(|(t, _)| *t)
            .collect();
        let day = self.day;
        let head = format!("第 {day} 天投票：{}", summary.join("；"));
        match top.as_slice() {
            [] => {
                self.history.push(format!("{head}。没有人被放逐"));
                self.announce(
                    world,
                    &format!(
                        "【狼人杀】亮票：{}。没有人得票，今天没有人被放逐。",
                        summary.join("；")
                    ),
                    false,
                );
                self.close_day(world);
            }
            [one] => {
                let one = *one;
                self.history
                    .push(format!("{head}。{} 被放逐", self.label(one)));
                self.announce(
                    world,
                    &format!(
                        "【狼人杀】亮票：{}。{} 被放逐，说完遗言后走出村子。",
                        summary.join("；"),
                        self.label(one)
                    ),
                    false,
                );
                self.exile(world, one);
            }
            _ if self.tied.is_empty() => {
                let names: Vec<String> = top.iter().map(|&i| self.label(i)).collect();
                self.history.push(format!(
                    "{head}。{} 平票，各再说一句后重投",
                    names.join("、")
                ));
                self.announce(
                    world,
                    &format!(
                        "【狼人杀】亮票：{}。{} 平票，各再说一句，然后重投。",
                        summary.join("；"),
                        names.join("、")
                    ),
                    false,
                );
                self.tied = top.clone();
                self.round = Round::Tie;
                self.queue = top;
                self.phase = Phase::Speech;
                self.next_speaker(world);
            }
            _ => {
                self.history
                    .push(format!("{head}。重投又平票，没有人被放逐"));
                self.announce(
                    world,
                    &format!(
                        "【狼人杀】亮票：{}。重投又平票，今天没有人被放逐。",
                        summary.join("；")
                    ),
                    false,
                );
                self.close_day(world);
            }
        }
    }

    fn exile(&mut self, world: &mut World, i: usize) {
        self.seats[i].out = Some(Out::Exiled);
        self.seats[i].out_day = Some(self.day);
        self.phase = Phase::LastWords;
        self.turn = Some(i);
        self.until = world.minutes() + LAST_WORDS_MINUTES;
        self.call(
            world,
            i,
            &format!(
                "【狼人杀】你被投票放逐了。用 mode_action 交 speak 留遗言（最多 {SPEECH_CHARS} 字），{LAST_WORDS_MINUTES:.0} 分钟内不交就不留了。"
            ),
        );
    }

    /// 遗言说完（或到点）：猎人先开枪，其余人走出村子。
    fn after_last_words(&mut self, world: &mut World) {
        let Some(i) = self.turn.take() else {
            return self.close_day(world);
        };
        if self.seats[i].role == Role::Hunter {
            self.after_shot = AfterShot::Exile;
            return self.ask_shot(world, i);
        }
        self.walk_out(world, i);
        self.settle_or(world, Self::close_day);
    }

    fn walk_out(&mut self, world: &mut World, i: usize) {
        self.leaving.push((i, world.minutes() + LEAVE_MINUTES));
        self.call(
            world,
            i,
            &format!("【狼人杀】你出局了：现在走出村子，{LEAVE_MINUTES:.0} 分钟后离开这里。"),
        );
    }

    fn ask_shot(&mut self, world: &mut World, i: usize) {
        self.phase = Phase::Shot;
        self.turn = Some(i);
        self.until = world.minutes() + SHOT_MINUTES;
        self.call(
            world,
            i,
            &format!(
                "【狼人杀】你是猎人，倒下前可以开枪带走一人：用 mode_action 交 shoot，target 填座号；不开枪交 pass。{SHOT_MINUTES:.0} 分钟内不交算放弃。"
            ),
        );
    }

    /// 猎人开枪（或放弃）之后：倒下或走出村子，再看胜负。
    fn resolve_shot(&mut self, world: &mut World, target: Option<usize>) {
        let Some(h) = self.turn.take() else {
            return;
        };
        if let Some(t) = target {
            self.seats[t].out = Some(Out::Shot);
            self.seats[t].out_day = Some(self.day);
            self.fell(world, t, "猎人开枪", "胸口中了一枪");
            let text = format!(
                "【狼人杀】猎人 {} 开枪带走了 {}。",
                self.label(h),
                self.label(t)
            );
            self.history.push(text.replace("【狼人杀】", ""));
            self.announce(world, &text, false);
            if self.leaving.iter().any(|(i, _)| *i == t) {
                self.leaving.retain(|(i, _)| *i != t);
            }
        }
        match self.after_shot {
            AfterShot::Dawn => {
                self.fell(world, h, "狼人", NIGHT_WOUND);
                self.settle_or(world, |s, w| {
                    s.begin_day();
                    let text = format!("【狼人杀】{}", s.schedule());
                    s.announce(w, &text, false);
                });
            }
            AfterShot::Exile => {
                self.walk_out(world, h);
                self.settle_or(world, Self::close_day);
            }
        }
    }

    /// 分出胜负就结束，否则接着做 next。
    fn settle_or(&mut self, world: &mut World, next: fn(&mut Self, &mut World)) {
        match self.winner_now() {
            Some(side) => self.finish(world, side),
            None => next(self, world),
        }
    }

    /// 议事散了：回家，过一会儿入夜。
    fn close_day(&mut self, world: &mut World) {
        self.phase = Phase::Dusk;
        self.turn = None;
        let now = world.minutes();
        self.until = (now + CURFEW).max(self.day_start(self.day) + NIGHT_FROM);
        let text = format!(
            "【狼人杀】议事散了。天黑前回自己家，夜里待在家里别出门，一直停留到明天 {} 天亮；有身份的人夜里会被叫醒行动。",
            Self::clock(self.dawn_at(self.day + 1))
        );
        self.announce(world, &text, true);
    }

    // ---------- 夜里 ----------

    fn start_night(&mut self, world: &mut World) {
        self.phase = Phase::Night;
        let now = world.minutes();
        self.night = Night {
            night: self.day,
            roles_until: now + ROLE_MINUTES,
            wolf_round: 1,
            wolf_queue: self.living_role(Role::Wolf),
            ..Night::default()
        };
        self.announce(world, "【狼人杀】天黑请闭眼。", false);
        let seer = self.living_role(Role::Seer);
        let guard = self.living_role(Role::Guard);
        self.night.seer_done = seer.is_empty();
        self.night.guard_done = guard.is_empty();
        for i in seer {
            self.call(
                world,
                i,
                "【狼人杀】预言家请睁眼：用 mode_action 交 check，target 填今晚要查验的座号，会告诉你他是不是狼人。",
            );
        }
        for i in guard {
            let not = self
                .last_guard
                .map(|g| format!("（昨晚守了 {}，今晚不能再守他）", self.label(g)))
                .unwrap_or_default();
            self.call(
                world,
                i,
                &format!("【狼人杀】守卫请睁眼：用 mode_action 交 guard，target 填今晚要守护的座号{not}。"),
            );
        }
        self.next_wolf(world);
    }

    fn next_wolf(&mut self, world: &mut World) {
        let now = world.minutes();
        loop {
            while !self.night.wolf_queue.is_empty() {
                let i = self.night.wolf_queue.remove(0);
                if !self.alive(i) {
                    continue;
                }
                self.night.wolf_turn = Some(i);
                self.night.wolf_until = now + WOLF_MINUTES;
                let said = if self.night.wolf_lines.is_empty() {
                    String::new()
                } else {
                    "同伴说的话在你的经历里。".into()
                };
                let text = format!(
                    "【狼人杀】狼人频道（只有狼人看得见）：轮到你。用 mode_action 交 kill，target 填今晚要杀的座号，text 写给同伴的话。{said}意见不一按多数，平票按先选的。"
                );
                self.call(world, i, &text);
                return;
            }
            let wolves = self.living_role(Role::Wolf);
            let latest = self.latest_picks();
            let agreed = latest
                .values()
                .collect::<std::collections::BTreeSet<_>>()
                .len()
                <= 1;
            if self.night.wolf_round == 1 && wolves.len() > 1 && !agreed && !latest.is_empty() {
                self.night.wolf_round = 2;
                self.night.wolf_queue = wolves;
                continue;
            }
            break;
        }
        self.night.wolf_turn = None;
        self.night.wolves_done = true;
        self.night.kill = self.decide_kill();
        let wolves = self.living_role(Role::Wolf);
        let note = match self.night.kill {
            Some(k) => format!("第 {} 夜狼人刀了 {}", self.night.night, self.label(k)),
            None => format!("第 {} 夜狼人没有刀人", self.night.night),
        };
        for &w in &wolves {
            self.seats[w].notes.push(note.clone());
        }
        self.tell(world, &wolves, &format!("【狼人杀】狼人频道：{note}。"));
        self.call_witch(world);
    }

    /// 每只狼最后选的刀口。
    fn latest_picks(&self) -> BTreeMap<usize, usize> {
        let mut latest = BTreeMap::new();
        for &(w, t) in &self.night.picks {
            if self.alive(w) {
                latest.insert(w, t);
            }
        }
        latest
    }

    /// 按多数定刀口；平票按先选的。
    fn decide_kill(&self) -> Option<usize> {
        let latest = self.latest_picks();
        let mut count: BTreeMap<usize, usize> = BTreeMap::new();
        for t in latest.values() {
            *count.entry(*t).or_default() += 1;
        }
        let most = *count.values().max()?;
        self.night
            .picks
            .iter()
            .map(|(_, t)| *t)
            .find(|t| count.get(t) == Some(&most) && self.alive(*t))
    }

    fn call_witch(&mut self, world: &mut World) {
        let witch = self.living_role(Role::Witch);
        let Some(&w) = witch.first() else {
            self.night.witch_done = true;
            return;
        };
        if !self.save_left && !self.poison_left {
            self.night.witch_done = true;
            return;
        }
        self.night.witch_called = true;
        self.night.witch_until = world.minutes() + WITCH_MINUTES;
        let knife = match self.night.kill {
            _ if !self.save_left => "解药已经用过，今晚不告诉你刀口。".to_string(),
            Some(k) if k == w => "今晚被刀的是你自己（不能自救）。".to_string(),
            Some(k) => format!("今晚被刀的是 {}，可以交 save 救他。", self.label(k)),
            None => "今晚狼人没有刀人。".to_string(),
        };
        let poison = if self.poison_left {
            "可以交 poison 毒一人（target 填座号）。"
        } else {
            "毒药已经用过。"
        };
        let text = format!("【狼人杀】女巫请睁眼：{knife}{poison}一夜只能用一瓶；都不用交 pass。");
        self.call(world, w, &text);
    }

    /// 天亮结算：刀口没被守、没被救就倒下（同守同救也倒下），被毒的倒下。
    fn dawn(&mut self, world: &mut World) {
        let night = self.night.night;
        let mut fallen: Vec<(usize, Out)> = Vec::new();
        if let Some(k) = self.night.kill {
            let guarded = self.night.guard == Some(k);
            if guarded == self.night.save && self.alive(k) {
                fallen.push((k, Out::Killed));
            }
        }
        if let Some(p) = self.night.poison {
            if self.alive(p) && !fallen.iter().any(|(i, _)| *i == p) {
                fallen.push((p, Out::Poisoned));
            }
        }
        fallen.sort_by_key(|(i, _)| *i);
        self.day += 1;
        self.dawn = fallen.iter().map(|(i, _)| *i).collect();
        let names: Vec<String> = fallen.iter().map(|(i, _)| self.label(*i)).collect();
        let said = if names.is_empty() {
            self.history.push(format!("第 {night} 夜：平安夜"));
            "昨晚是平安夜。".to_string()
        } else {
            self.history
                .push(format!("第 {night} 夜：倒下的是 {}", names.join("、")));
            format!("昨晚倒下的是 {}。", names.join("、"))
        };
        let mut hunter = None;
        for &(i, how) in &fallen {
            self.seats[i].out = Some(how);
            self.seats[i].out_day = Some(night);
            if how == Out::Killed && self.seats[i].role == Role::Hunter {
                hunter = Some(i);
                continue;
            }
            let by = if how == Out::Poisoned {
                "女巫的毒药"
            } else {
                "狼人"
            };
            self.fell(world, i, by, NIGHT_WOUND);
        }
        let text = format!("【狼人杀】天亮了，第 {} 天。{said}", self.day);
        if let Some(h) = hunter {
            // 猎人被狼人杀害：先公布，开完枪他才倒下
            self.lines.clear();
            self.announce(world, &text, true);
            self.after_shot = AfterShot::Dawn;
            return self.ask_shot(world, h);
        }
        match self.winner_now() {
            Some(side) => {
                self.announce(world, &text, false);
                self.finish(world, side);
            }
            None => {
                self.begin_day();
                let text = format!("{text}{}", self.schedule());
                self.announce(world, &text, true);
            }
        }
    }

    fn finish(&mut self, world: &mut World, side: Side) {
        self.phase = Phase::Over;
        self.winner = Some(side);
        self.turn = None;
        self.queue.clear();
        let roles: Vec<String> = (0..self.seats.len())
            .map(|i| format!("{} {}", self.label(i), role_name(self.seats[i].role)))
            .collect();
        let text = format!(
            "【狼人杀】{}。翻牌：{}。",
            match side {
                Side::Good => "狼人全部出局，好人胜利",
                Side::Wolf => "狼人胜利",
            },
            roles.join("、")
        );
        self.history.push(text.replace("【狼人杀】", ""));
        self.announce(world, &text, true);
    }

    // ---------- 推进 ----------

    /// 到点的事做一件；做了返回 true。
    fn step(&mut self, world: &mut World) -> bool {
        let now = world.minutes() + EPS;
        match self.phase {
            Phase::Over => false,
            Phase::Waiting if now >= self.until => {
                self.first_dawn(world);
                true
            }
            Phase::Day if now >= self.until => {
                self.ring_bell(world);
                true
            }
            Phase::Gather if now >= self.until => {
                self.open_assembly(world);
                true
            }
            Phase::Speech if now >= self.until => {
                if let Some(i) = self.turn.take() {
                    let text = format!("【狼人杀】{} 没有发言（到点跳过）。", self.label(i));
                    self.announce(world, &text, false);
                }
                self.next_speaker(world);
                true
            }
            Phase::Vote if now >= self.until => {
                self.reveal(world);
                true
            }
            Phase::LastWords if now >= self.until => {
                self.after_last_words(world);
                true
            }
            Phase::Shot if now >= self.until => {
                self.resolve_shot(world, None);
                true
            }
            Phase::Dusk if now >= self.until => {
                self.start_night(world);
                true
            }
            Phase::Night => self.step_night(world, now),
            _ => false,
        }
    }

    fn step_night(&mut self, world: &mut World, now: f64) -> bool {
        if self.night.wolf_turn.is_some() && now >= self.night.wolf_until {
            self.night.wolf_turn = None;
            self.next_wolf(world);
            return true;
        }
        if self.night.witch_called && !self.night.witch_done && now >= self.night.witch_until {
            self.night.witch_done = true;
            return true;
        }
        if (!self.night.seer_done || !self.night.guard_done) && now >= self.night.roles_until {
            self.night.seer_done = true;
            self.night.guard_done = true;
            return true;
        }
        if now >= self.dawn_at(self.day + 1) {
            if !self.night.wolves_done {
                self.night.wolf_turn = None;
                self.night.wolf_queue.clear();
                self.night.wolf_round = 2;
                self.next_wolf(world);
            }
            self.night.witch_done = true;
            self.dawn(world);
            return true;
        }
        false
    }

    fn next_at(&self) -> f64 {
        let mut next = match self.phase {
            Phase::Over => f64::INFINITY,
            Phase::Night => {
                let n = &self.night;
                let mut at = self.dawn_at(self.day + 1);
                if n.wolf_turn.is_some() {
                    at = at.min(n.wolf_until);
                }
                if n.witch_called && !n.witch_done {
                    at = at.min(n.witch_until);
                }
                if !n.seer_done || !n.guard_done {
                    at = at.min(n.roles_until);
                }
                at
            }
            _ => self.until,
        };
        for (_, at) in &self.leaving {
            next = next.min(*at);
        }
        next
    }

    /// 被放逐的人到点离开地图。
    fn leave(&mut self, world: &mut World) {
        let now = world.minutes() + EPS;
        let (due, rest): (Vec<_>, Vec<_>) = self.leaving.iter().partition(|(_, at)| *at <= now);
        self.leaving = rest;
        for (i, _) in due {
            let id = self.seats[i].id.clone();
            world.depart(&id, "被放逐，走出了村子");
        }
    }

    /// 法官没经手的出局：白天被人害死、饿死，或者离开了这里。记成倒下，再看胜负；
    /// 正轮到他的那一步到点自己往下走。
    fn notice_losses(&mut self, world: &mut World) {
        if self.phase == Phase::Over {
            return;
        }
        let lost: Vec<usize> = (0..self.seats.len())
            .filter(|&i| {
                self.alive(i)
                    && world
                        .actor(&self.seats[i].id)
                        .is_none_or(|a| !a.present() || a.needs.body.dead)
            })
            .collect();
        if lost.is_empty() {
            return;
        }
        for &i in &lost {
            self.seats[i].out = Some(Out::Died);
            self.seats[i].out_day = Some(self.day);
            let text = format!("【狼人杀】{} 倒下了，出局。", self.label(i));
            self.history.push(text.replace("【狼人杀】", ""));
            self.announce(world, &text, false);
        }
        if let Some(side) = self.winner_now() {
            self.finish(world, side);
        }
    }

    // ---------- 给模型 ----------

    fn seats_line(&self, me: usize) -> String {
        let parts: Vec<String> = (0..self.seats.len())
            .map(|i| {
                let mark = match self.seats[i].out {
                    _ if i == me => "（你）",
                    None => "",
                    Some(Out::Exiled) => "（被放逐）",
                    Some(Out::Shot) => "（被猎人带走）",
                    Some(Out::Died) => "（倒下了）",
                    Some(_) => "（夜里倒下）",
                };
                format!("{} {}{mark}", i + 1, self.seats[i].name)
            })
            .collect();
        parts.join(" · ")
    }

    fn phase_line(&self) -> String {
        let d = self.day;
        match self.phase {
            Phase::Waiting => "开局前".into(),
            Phase::Day => format!("第 {d} 天 · 白天"),
            Phase::Gather => format!("第 {d} 天 · 敲过钟，去议事广场"),
            Phase::Speech => match self.round {
                Round::Intro => format!("第 {d} 天 · 自我介绍"),
                Round::Debate => format!("第 {d} 天 · 议事发言"),
                Round::Tie => format!("第 {d} 天 · 平票再说一句"),
            },
            Phase::Vote => format!("第 {d} 天 · 投票"),
            Phase::LastWords => format!("第 {d} 天 · 遗言"),
            Phase::Shot => format!("第 {d} 天 · 猎人开枪"),
            Phase::Dusk => format!("第 {d} 天 · 黄昏，回家"),
            Phase::Night => format!("第 {} 夜", self.night.night),
            Phase::Over => "一局结束".into(),
        }
    }

    /// 在家待到法官的天亮：停留只认时长（until 的「天亮」是早上 6 点），所以把还差几分钟算好给模型。
    fn stay_until(at: f64, now: f64) -> String {
        let minutes = (at - now).ceil().clamp(1.0, 1440.0);
        format!(
            "回自己家，到家后用「停留」，duration_minutes 填 {minutes:.0}（离天亮 {} 还有这么久；until 的「天亮」是早上 6 点，太早），天亮会叫醒你。",
            Self::clock(at)
        )
    }

    /// 此刻这个人能交的动作和该做什么。
    fn duty(&self, i: usize, now: f64) -> (Vec<&'static str>, String) {
        let seat = &self.seats[i];
        let dawn = self.dawn_at(self.day + 1);
        let mine = self.turn == Some(i);
        match self.phase {
            Phase::Waiting => (
                vec![],
                format!(
                    "狼人杀第 1 天 {} 天亮开局，身份那时发下。在那之前{}",
                    Self::clock(self.until),
                    Self::stay_until(self.until, now)
                ),
            ),
            Phase::Over => (vec![], "这一局结束了。".into()),
            _ if seat.out.is_some() && !mine => (vec![], "你已经出局了。".into()),
            Phase::Day => (
                vec![],
                "白天自由活动：可以找人私下聊、结盟、打听，也可以独处。16:30 钟楼敲钟后去议事广场，17:00 议事。"
                    .into(),
            ),
            Phase::Gather => (vec![], "去议事广场，17:00 开始议事。".into()),
            Phase::Speech if mine => (
                vec!["speak", "pass"],
                format!("轮到你发言：交 speak，text 写你要说的话（最多 {SPEECH_CHARS} 字）。"),
            ),
            Phase::Speech => (
                vec![],
                format!(
                    "议事中，现在是 {} 在说；轮到你时会叫你。等着时用 wait_for 等事件。",
                    self.turn.map(|t| self.label(t)).unwrap_or_default()
                ),
            ),
            Phase::Vote if self.ballots.contains_key(&i) => {
                (vec![], "你已经投了票，等大家交齐一起亮票。".into())
            }
            Phase::Vote => (
                vec!["vote", "abstain"],
                if self.tied.is_empty() {
                    "投票放逐一人：交 vote，target 填座号；不投交 abstain。reason 写理由（只给旁观的人看）。".into()
                } else {
                    let names: Vec<String> = self.tied.iter().map(|&t| self.label(t)).collect();
                    format!("重新投票，只能投 {}：交 vote 或 abstain。", names.join("、"))
                },
            ),
            Phase::LastWords if mine => (
                vec!["speak", "pass"],
                format!("你被放逐了：交 speak 留遗言（最多 {SPEECH_CHARS} 字）。"),
            ),
            Phase::Shot if mine => (
                vec!["shoot", "pass"],
                "你是猎人，可以开枪带走一人：交 shoot，target 填座号；不开枪交 pass。".into(),
            ),
            Phase::LastWords | Phase::Shot => (vec![], "等法官往下走。".into()),
            Phase::Dusk => (
                vec![],
                format!("天黑了别在外面：{}", Self::stay_until(dawn, now)),
            ),
            Phase::Night => self.night_duty(i, &Self::stay_until(dawn, now)),
        }
    }

    fn night_duty(&self, i: usize, stay: &str) -> (Vec<&'static str>, String) {
        let n = &self.night;
        let sleep = format!("夜里待在自己家里：{stay}");
        match self.seats[i].role {
            Role::Wolf if n.wolf_turn == Some(i) => (
                vec!["kill"],
                "狼人频道轮到你：交 kill，target 填今晚要杀的座号，text 写给同伴的话。".into(),
            ),
            Role::Wolf if !n.wolves_done => (vec![], "等同伴在狼人频道说完。".into()),
            Role::Seer if !n.seer_done => (
                vec!["check"],
                "交 check，target 填今晚要查验的座号。".into(),
            ),
            Role::Guard if !n.guard_done => (
                vec!["guard"],
                "交 guard，target 填今晚要守护的座号（不能连着两夜守同一人）。".into(),
            ),
            Role::Witch if n.witch_called && !n.witch_done => {
                let mut actions = vec!["pass"];
                if self.save_left && n.kill.is_some_and(|k| k != i) {
                    actions.insert(0, "save");
                }
                if self.poison_left {
                    actions.insert(0, "poison");
                }
                let knife = match n.kill {
                    _ if !self.save_left => "解药已经用过。".to_string(),
                    Some(k) if k == i => "今晚被刀的是你自己（不能自救）。".to_string(),
                    Some(k) => format!("今晚被刀的是 {}。", self.label(k)),
                    None => "今晚狼人没有刀人。".to_string(),
                };
                (
                    actions,
                    format!("{knife}可以 save 救人、poison 毒一人（target 座号），或 pass；一夜只用一瓶。"),
                )
            }
            Role::Witch if !n.wolves_done && (self.save_left || self.poison_left) => {
                (vec![], format!("等狼人选完刀口会叫你。{sleep}"))
            }
            _ => (vec![], sleep),
        }
    }

    fn known(&self, i: usize) -> Vec<String> {
        let seat = &self.seats[i];
        let mut known = seat.notes.clone();
        match seat.role {
            Role::Witch => known.push(format!(
                "解药{}，毒药{}",
                if self.save_left { "还在" } else { "已用" },
                if self.poison_left { "还在" } else { "已用" }
            )),
            Role::Hunter => {
                known.push("被狼人杀害或被放逐时可以开枪带走一人；被毒死不能开枪".into())
            }
            _ => {}
        }
        known
    }

    /// 今天的发言；狼人在夜里还看得到今晚狼人频道里的话。
    fn today(&self, i: usize) -> Vec<String> {
        let mut today: Vec<String> = self
            .lines
            .iter()
            .map(|l| {
                let i = l.seat as usize - 1;
                let tag = match (l.last, l.away) {
                    (true, _) => "（遗言）",
                    (false, true) => "（没到场）",
                    _ => "",
                };
                format!("{}{tag}：{}", self.label(i), l.text)
            })
            .collect();
        if self.phase == Phase::Night && self.seats[i].role == Role::Wolf {
            today.extend(
                self.night
                    .wolf_lines
                    .iter()
                    .map(|l| format!("狼人频道 · {}：{}", self.label(l.seat as usize - 1), l.text)),
            );
        }
        today
    }

    // ---------- 交动作 ----------

    fn speak(&mut self, world: &mut World, i: usize, action: &GameModeAction) -> Result<String> {
        let last = self.phase == Phase::LastWords;
        if action.action == "pass" {
            if last {
                self.after_last_words(world);
            } else {
                self.turn = None;
                self.next_speaker(world);
            }
            return Ok("跳过了这次发言".into());
        }
        if action.action != "speak" {
            return Err(KernelError::action("现在该交 speak（或 pass 跳过）"));
        }
        let raw = action.text.as_deref().unwrap_or("").trim();
        if raw.is_empty() {
            return Err(KernelError::action("text 不能为空：写上你要说的话"));
        }
        let (text, clipped) = clip(raw, SPEECH_CHARS);
        let line = self.line(world, i, text.clone(), last);
        let tag = if last { "遗言" } else { "议事" };
        let heard = format!(
            "【{tag}】{}{}：{text}",
            self.label(i),
            if line.away { "（没到场）" } else { "" }
        );
        self.lines.push(line);
        let living = self.living();
        let mut hearers = living.clone();
        if last && !hearers.contains(&i) {
            hearers.push(i);
        }
        self.tell(world, &hearers, &heard);
        let info = world.actors[&self.seats[i].id].event_info();
        world.log(info, heard);
        if last {
            self.after_last_words(world);
        } else {
            self.turn = None;
            self.next_speaker(world);
        }
        Ok(if clipped {
            format!("说完了；超出 {SPEECH_CHARS} 字的部分没有念出来")
        } else {
            "说完了，大家都听到了".into()
        })
    }

    fn vote(&mut self, world: &mut World, i: usize, action: &GameModeAction) -> Result<String> {
        let target = match action.action.as_str() {
            "abstain" => None,
            "vote" => {
                let t = self.living_target(action)?;
                if t == i {
                    return Err(KernelError::action("不能投自己"));
                }
                if !self.tied.is_empty() && !self.tied.contains(&t) {
                    let names: Vec<String> = self.tied.iter().map(|&x| self.label(x)).collect();
                    return Err(KernelError::action(format!(
                        "重投只能投 {}",
                        names.join("、")
                    )));
                }
                Some(t)
            }
            _ => return Err(KernelError::action("现在该交 vote 或 abstain")),
        };
        if self.ballots.contains_key(&i) {
            return Err(KernelError::action("你已经投过票了"));
        }
        self.ballots.insert(
            i,
            Ballot {
                target,
                reason: action.reason.clone().map(|r| clip(&r, 120).0),
            },
        );
        let done = self.living().iter().all(|v| self.ballots.contains_key(v));
        let said = match target {
            Some(t) => format!("投给了 {}", self.label(t)),
            None => "弃票".into(),
        };
        if done {
            self.reveal(world);
            return Ok(format!("{said}；大家都交齐了，已经亮票"));
        }
        Ok(format!("{said}；等大家交齐一起亮票"))
    }

    fn night_act(
        &mut self,
        world: &mut World,
        i: usize,
        action: &GameModeAction,
    ) -> Result<String> {
        let role = self.seats[i].role;
        match (role, action.action.as_str()) {
            (Role::Wolf, "kill") => {
                if self.night.wolf_turn != Some(i) {
                    return Err(KernelError::action("还没轮到你在狼人频道说话"));
                }
                let t = self.living_target(action)?;
                if self.seats[t].role == Role::Wolf {
                    return Err(KernelError::action("不能刀狼人同伴"));
                }
                let text = action
                    .text
                    .as_deref()
                    .map(|t| clip(t, SPEECH_CHARS).0)
                    .filter(|t| !t.is_empty())
                    .unwrap_or_else(|| format!("刀 {} 号", t + 1));
                let line = WerewolfLine {
                    seat: i as u32 + 1,
                    text: format!("{text}（选 {}）", self.label(t)),
                    at: world.minutes(),
                    away: false,
                    last: false,
                };
                let heard = format!("【狼人频道】{}：{}", self.label(i), line.text);
                self.night.wolf_lines.push(line);
                self.night.picks.push((i, t));
                let mates: Vec<usize> = self
                    .living_role(Role::Wolf)
                    .into_iter()
                    .filter(|&w| w != i)
                    .collect();
                self.tell(world, &mates, &heard);
                world.log(EventInfo::default(), heard);
                self.night.wolf_turn = None;
                self.next_wolf(world);
                Ok(format!("选了 {}，同伴都看到了", self.label(t)))
            }
            (Role::Seer, "check") if !self.night.seer_done => {
                let t = self.living_target(action)?;
                if t == i {
                    return Err(KernelError::action("不能查验自己"));
                }
                let wolf = self.seats[t].role == Role::Wolf;
                self.night.check = Some((t, wolf));
                self.night.seer_done = true;
                let note = format!(
                    "第 {} 夜查验 {}：{}",
                    self.night.night,
                    self.label(t),
                    if wolf { "狼人" } else { "好人" }
                );
                self.seats[i].notes.push(note.clone());
                Ok(note)
            }
            (Role::Guard, "guard") if !self.night.guard_done => {
                let t = self.living_target(action)?;
                if self.last_guard == Some(t) {
                    return Err(KernelError::action("不能连着两夜守同一人"));
                }
                self.night.guard = Some(t);
                self.last_guard = Some(t);
                self.night.guard_done = true;
                let note = format!("第 {} 夜守护 {}", self.night.night, self.label(t));
                self.seats[i].notes.push(note.clone());
                Ok(note)
            }
            (Role::Witch, "save" | "poison" | "pass")
                if self.night.witch_called && !self.night.witch_done =>
            {
                let note = match action.action.as_str() {
                    "save" => {
                        let k = self
                            .night
                            .kill
                            .filter(|_| self.save_left)
                            .ok_or_else(|| KernelError::action("今晚没有可救的人"))?;
                        if k == i {
                            return Err(KernelError::action("不能救自己"));
                        }
                        self.night.save = true;
                        self.save_left = false;
                        format!("第 {} 夜用解药救了 {}", self.night.night, self.label(k))
                    }
                    "poison" => {
                        if !self.poison_left {
                            return Err(KernelError::action("毒药已经用过了"));
                        }
                        let t = self.living_target(action)?;
                        if t == i {
                            return Err(KernelError::action("不能毒自己"));
                        }
                        self.night.poison = Some(t);
                        self.poison_left = false;
                        format!("第 {} 夜用毒药毒了 {}", self.night.night, self.label(t))
                    }
                    _ => format!("第 {} 夜没有用药", self.night.night),
                };
                self.night.witch_done = true;
                self.seats[i].notes.push(note.clone());
                Ok(note)
            }
            _ => Err(KernelError::action("现在没有要你在夜里做的事")),
        }
    }
}

impl Rules for Werewolf {
    const ID: &'static str = "werewolf";

    fn boundary(&self, world: &World) -> f64 {
        (self.next_at() - world.minutes()).max(0.0)
    }

    /// 到点的事依次做完：同一刻可能连着几步（比如发言到点跳过、接着叫下一个）。
    fn advance(&mut self, world: &mut World) {
        self.leave(world);
        self.notice_losses(world);
        for _ in 0..64 {
            if !self.step(world) {
                break;
            }
        }
    }

    fn view(&self, _world: &World) -> GameModeView {
        let seats = self
            .seats
            .iter()
            .enumerate()
            .map(|(i, s)| WerewolfSeat {
                seat: i as u32 + 1,
                id: s.id.clone(),
                name: s.name.clone(),
                role: s.role,
                out: s.out,
                out_day: s.out_day,
            })
            .collect();
        let ballots = self
            .ballots
            .iter()
            .map(|(v, b)| WerewolfBallot {
                voter: *v as u32 + 1,
                target: b.target.filter(|_| self.revealed).map(|t| t as u32 + 1),
                reason: b.reason.clone().filter(|_| self.revealed),
            })
            .collect();
        let n = &self.night;
        let night = (n.night > 0).then(|| WerewolfNight {
            night: n.night,
            wolf_lines: n.wolf_lines.clone(),
            kill: n.kill.map(|k| k as u32 + 1),
            guard: n.guard.map(|g| g as u32 + 1),
            check: n.check.map(|(s, wolf)| WerewolfCheck {
                seat: s as u32 + 1,
                wolf,
            }),
            save: n.save,
            poison: n.poison.map(|p| p as u32 + 1),
        });
        let turn = match self.phase {
            Phase::Night => n.wolf_turn,
            _ => self.turn,
        };
        let until = match self.phase {
            Phase::Speech | Phase::Vote | Phase::LastWords | Phase::Shot => Some(self.until),
            _ => None,
        };
        GameModeView::Werewolf(WerewolfView {
            phase: self.phase,
            day: self.day,
            seats,
            notice: self.phase_line(),
            turn: turn.map(|t| t as u32 + 1),
            until,
            lines: self.lines.clone(),
            ballots,
            revealed: self.revealed,
            night,
            dawn: self.dawn.iter().map(|d| *d as u32 + 1).collect(),
            winner: self.winner,
        })
    }

    fn context(&self, world: &World, actor: &str) -> Option<GameModeContext> {
        world.actor(actor)?;
        let i = self.seat_of(actor)?;
        let seat = &self.seats[i];
        let me = if self.phase == Phase::Waiting {
            format!("{}（身份天亮时发下）", self.label(i))
        } else {
            let side = if seat.role == Role::Wolf {
                "狼人阵营"
            } else {
                "好人阵营"
            };
            format!("{} · {}（{side}）", self.label(i), role_name(seat.role))
        };
        let goal = match seat.role {
            _ if self.phase == Phase::Waiting => String::new(),
            Role::Wolf => "狼人阵营：白天装成好人，夜里杀人；杀光平民或杀光神职（预言家、女巫、猎人、守卫）就赢。".into(),
            _ => "好人阵营：找出狼人，在议事上把他们全部投票放逐就赢；平民全灭或神职全灭就输。".into(),
        };
        let (actions, now) = self.duty(i, world.minutes());
        let known = if self.phase == Phase::Waiting {
            Vec::new()
        } else {
            self.known(i)
        };
        Some(GameModeContext::Werewolf(WerewolfContext {
            phase: self.phase_line(),
            me,
            goal,
            known,
            seats: self.seats_line(i),
            history: self.history.clone(),
            today: self.today(i),
            now,
            actions: actions.into_iter().map(str::to_owned).collect(),
        }))
    }

    /// 在座、没出局的人才有这件工具；出局的猎人轮到开枪时也有。说明对每个人都一样，好让请求前缀留在缓存里。
    fn tool(&self, _world: &World, actor: &str) -> Option<String> {
        let i = self.seat_of(actor)?;
        let shooting = matches!(self.phase, Phase::Shot | Phase::LastWords) && self.turn == Some(i);
        if self.phase == Phase::Over || (self.seats[i].out.is_some() && !shooting) {
            return None;
        }
        Some(format!(
            "狼人杀里交选择。只在观察里 werewolf.actions 列出时能用，此刻该做什么看 werewolf.now。\
action：speak 发言或留遗言（text，最多 {SPEECH_CHARS} 字）、vote 投票放逐（target）、abstain 弃票、\
kill 狼人选刀口（target，text 写给同伴的话）、check 预言家查验（target）、guard 守卫守护（target）、\
save 女巫用解药、poison 女巫用毒药（target）、shoot 猎人开枪（target）、pass 这一步放弃。\
target 填座号；reason 写为什么这么选（只给旁观的人看）。\
规则：白天自由活动，可以私下聊；16:30 敲钟去议事广场，17:00 按座次每人发言一次，然后同时投票放逐一人（第 1 天只自我介绍），\
平票的人各再说一句重投，再平就没人出局。夜里狼人选一人杀害，预言家查验一人是不是狼人，女巫一瓶解药一瓶毒药（一夜一瓶、不能自救），\
守卫每夜守一人（不能连守同一人，同守同救照样死），猎人被狼人杀害或被放逐时可以开枪带走一人（被毒不能）。\
天亮只公布谁倒下，不说死因；出局的人不翻牌。狼人全部出局好人赢；平民全灭或神职全灭狼人赢。"
        ))
    }

    fn act(&mut self, world: &mut World, actor: &str, action: &GameModeAction) -> Result<String> {
        let i = self
            .seat_of(actor)
            .ok_or_else(|| KernelError::action("你不在这一局里"))?;
        let mine = self.turn == Some(i);
        match self.phase {
            Phase::Over => Err(KernelError::action("这一局已经结束了")),
            Phase::Speech | Phase::LastWords if mine => self.speak(world, i, action),
            Phase::Shot if mine => match action.action.as_str() {
                "shoot" => {
                    let t = self.living_target(action)?;
                    if t == i {
                        return Err(KernelError::action("不能对自己开枪"));
                    }
                    let said = format!("开枪带走了 {}", self.label(t));
                    self.resolve_shot(world, Some(t));
                    Ok(said)
                }
                "pass" => {
                    self.resolve_shot(world, None);
                    Ok("没有开枪".into())
                }
                _ => Err(KernelError::action("现在该交 shoot 或 pass")),
            },
            _ if self.seats[i].out.is_some() => Err(KernelError::action("你已经出局了")),
            Phase::Vote => self.vote(world, i, action),
            Phase::Night => self.night_act(world, i, action),
            _ => Err(KernelError::action(format!(
                "现在是「{}」，没有要你交的动作：{}",
                self.phase_line(),
                self.duty(i, world.minutes()).1
            ))),
        }
    }
}
