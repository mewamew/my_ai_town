//! 执剑人之夜：《三体》威慑纪元的执剑人交接，法官是这里的一个状态机，把一天的议程套在照旧异步的小镇上。
//! 按入住的号码排座次：1 号是现任执剑人，2、3 号是候选人，4 号是三体世界的代表，其余是选民。
//! 白天村民自己过（拉票、私聊）；16:30 敲钟，17:00 在广场按次序一次叫醒一个人：现任执剑人说一句，
//! 两位候选人演说，选民依次表态；然后选民同时投票，亮票后票多的当选（平票由现任执剑人指定，他不在就抽签）。
//! 19:00 在联合国大厅地下交接：现任执剑人对新执剑人说一句，开关交出去；交接完 5 分钟水滴来袭，
//! 执剑人 10 分钟内按（引力波广播三体世界的坐标）或不按（到点算不按，威慑失败、天线被毁）。
//! 结局定了以后三体世界的代表对全镇说最后一段话，一局结束。
//! 法官往下走只看两件事：该交的人交了，或者到点了（期限按游戏分钟，挂在 boundary 上）。
//! 只叫醒该做事的人：别人的话写进每个人的经历，不发通知；投票这种同时进行的窗口结算前不发通知。
use super::Rules;
use crate::error::{KernelError, Result};
use crate::{World, DAY};
use protocol::{
    EventInfo, EventSpeech, FactKind, GameModeAction, GameModeContext, GameModeView,
    SwordholderBallot, SwordholderContext, SwordholderDecision, SwordholderEnding as Ending,
    SwordholderLine, SwordholderPhase as Phase, SwordholderRole as Role, SwordholderSeat,
    SwordholderView,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// 白天自由活动几小时：天亮到敲钟。不给时 8 小时。
const DAY_HOURS: std::ops::RangeInclusive<u32> = 1..=10;
const DEFAULT_DAY_HOURS: u32 = 8;
/// 16:30 敲钟，17:00 演说，19:00 交接（当天第几分钟）。
const BELL: f64 = 990.0;
const MEET: f64 = 1020.0;
const HANDOVER_AT: f64 = 1140.0;
/// 选出来以后至少过多久才交接（投票拖到 18:50 以后时）
const HANDOVER_GAP: f64 = 10.0;
/// 每一步的期限（游戏分钟）：到点没交就往下走。
const SPEAK_MINUTES: f64 = 15.0;
const VOTE_MINUTES: f64 = 15.0;
const APPOINT_MINUTES: f64 = 10.0;
const HANDOVER_MINUTES: f64 = 10.0;
/// 交接完成后过多久水滴来袭；来袭后执剑人有多久
const ATTACK_DELAY: f64 = 5.0;
const ATTACK_MINUTES: f64 = 10.0;
const STATEMENT_MINUTES: f64 = 15.0;
/// 白天、敲钟后、等交接这些没有期限的时段，世界按正常速度的几倍走；有期限的回合照常速。
const FREE_TEMPO: f64 = 3.0;
/// 理由（只给旁观的人看）最多多少字。
const REASON_CHARS: usize = 120;
/// 各场合一段话最多多少字：现任执剑人的一句和交接时的一句、选民表态、演说和最后的宣布
const REMARK_CHARS: usize = 100;
const STANCE_CHARS: usize = 200;
const ADDRESS_CHARS: usize = 400;
/// 1 号现任执剑人、2 号 3 号候选人、4 号三体代表，再加至少两位选民
const PLAYERS: std::ops::RangeInclusive<usize> = 6..=12;
const EPS: f64 = 1e-6;

/// 场合
const REMARK: &str = "一句话";
const ADDRESS: &str = "演说";
const STANCE: &str = "表态";
const HANDOVER: &str = "交接";
const STATEMENT: &str = "宣布";

fn role_name(role: Role) -> &'static str {
    match role {
        Role::Holder => "现任执剑人",
        Role::Candidate => "候选人",
        Role::Envoy => "三体世界的代表",
        Role::Voter => "选民",
    }
}

/// 按座次定身份
fn role_at(i: usize) -> Role {
    match i {
        0 => Role::Holder,
        1 | 2 => Role::Candidate,
        3 => Role::Envoy,
        _ => Role::Voter,
    }
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

/// 交动作时写的理由（只给旁观的人看），空的不要。
fn reason_of(action: &GameModeAction) -> Option<String> {
    action
        .reason
        .as_deref()
        .map(|r| clip(r, REASON_CHARS).0)
        .filter(|r| !r.is_empty())
}

fn clock(at: f64) -> String {
    let t = crate::time_of_day(at).round() as i64;
    format!("{:02}:{:02}", t / 60 % 24, t % 60)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Seat {
    pub id: String,
    pub name: String,
    pub role: Role,
    /// 法官没经手就不在了：被人害死、饿死，或者离开了这里
    #[serde(default)]
    pub gone: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ballot {
    pub target: Option<usize>,
    #[serde(default)]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Decision {
    pub seat: usize,
    pub press: bool,
    pub at: f64,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Swordholder {
    pub seed: u32,
    pub day_hours: u32,
    /// 这一局的那一天是世界的第几天（从 0 数）
    pub first_day: u32,
    pub seats: Vec<Seat>,
    pub phase: Phase,
    /// 这一步的期限或下一个钟点（世界分钟）
    pub until: f64,
    /// 广场、联合国大厅、引力波天线的地点编号；地图上没有时不记到没到场、不画水滴的去向
    #[serde(default)]
    pub plaza: Option<String>,
    #[serde(default)]
    pub hall: Option<String>,
    #[serde(default)]
    pub antenna: Option<String>,
    #[serde(default)]
    pub turn: Option<usize>,
    /// 还没轮到说话的人，按次序
    #[serde(default)]
    pub queue: Vec<usize>,
    /// 今天说过的话
    #[serde(default)]
    pub lines: Vec<SwordholderLine>,
    #[serde(default)]
    pub ballots: BTreeMap<usize, Ballot>,
    #[serde(default)]
    pub revealed: bool,
    /// 平票的候选人：等现任执剑人指定
    #[serde(default)]
    pub tied: Vec<usize>,
    #[serde(default)]
    pub elected: Option<usize>,
    #[serde(default)]
    pub appointed: bool,
    /// 此刻握着开关的人
    pub swordholder: usize,
    /// 开关已经交出去了（或者没人当选、现任留任）：之后到点就是水滴来袭
    #[serde(default)]
    pub handed: bool,
    #[serde(default)]
    pub decision: Option<Decision>,
    #[serde(default)]
    pub ending: Option<Ending>,
    /// 公开的经过：投票、交接、结局
    #[serde(default)]
    pub history: Vec<String>,
}

impl Swordholder {
    /// 按此刻在镇上的村民排座次、定身份（按编号，也就是入住的先后）。这一局从今天开始，过了 15:30 就从明天开始；
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
                "执剑人之夜要 {}–{} 个村民（1 号现任执剑人、2 号 3 号候选人、4 号三体代表、其余选民），现在镇上只有 {} 个",
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
        let seats: Vec<Seat> = ids
            .iter()
            .enumerate()
            .map(|(i, id)| Seat {
                id: (*id).clone(),
                name: world.actors[*id].name.clone(),
                role: role_at(i),
                gone: false,
            })
            .collect();
        let now = world.minutes();
        let today = (now / DAY).floor() as u32;
        let first_day = if crate::time_of_day(now) < BELL - 60.0 {
            today
        } else {
            today + 1
        };
        let find = |words: &[&str]| {
            words.iter().find_map(|w| {
                world
                    .topo
                    .locales
                    .values()
                    .find(|l| l.name.contains(w))
                    .map(|l| l.id.clone())
            })
        };
        let mut state = Self {
            seed,
            day_hours,
            first_day,
            seats,
            phase: Phase::Waiting,
            until: 0.0,
            plaza: find(&["广场"]),
            hall: find(&["联合国", "大厅"]),
            antenna: find(&["天线"]),
            turn: None,
            queue: Vec::new(),
            lines: Vec::new(),
            ballots: BTreeMap::new(),
            revealed: false,
            tied: Vec::new(),
            elected: None,
            appointed: false,
            swordholder: 0,
            handed: false,
            decision: None,
            ending: None,
            history: Vec::new(),
        };
        // 天亮已经过了：开钟就算天亮
        state.until = state.dawn_at().max(now);
        Ok(state)
    }

    // ---------- 钟点和地点 ----------

    fn day_start(&self) -> f64 {
        f64::from(self.first_day) * DAY
    }
    fn dawn_at(&self) -> f64 {
        self.day_start() + BELL - f64::from(self.day_hours) * 60.0
    }
    fn place(world: &World, locale: Option<&str>, fallback: &str) -> String {
        locale
            .map(|l| world.topo.locale_name(l))
            .unwrap_or_else(|| fallback.to_string())
    }
    fn plaza_name(&self, world: &World) -> String {
        Self::place(world, self.plaza.as_deref(), "广场")
    }
    fn hall_name(&self, world: &World) -> String {
        Self::place(world, self.hall.as_deref(), "联合国大厅")
    }

    // ---------- 座位 ----------

    fn label(&self, i: usize) -> String {
        format!("{} 号 {}", i + 1, self.seats[i].name)
    }
    fn seat_of(&self, actor: &str) -> Option<usize> {
        self.seats.iter().position(|s| s.id == actor)
    }
    fn of_role(&self, role: Role) -> Vec<usize> {
        (0..self.seats.len())
            .filter(|&i| self.seats[i].role == role && !self.seats[i].gone)
            .collect()
    }
    fn holder(&self) -> Option<usize> {
        self.of_role(Role::Holder).first().copied()
    }
    fn envoy(&self) -> Option<usize> {
        self.of_role(Role::Envoy).first().copied()
    }
    fn names(&self, who: &[usize]) -> String {
        let names: Vec<String> = who.iter().map(|&i| self.label(i)).collect();
        names.join("、")
    }
    /// 「2」「2 号」「程心」都认；认不出时说明原因。
    fn target(&self, action: &GameModeAction) -> Result<usize> {
        let raw = action
            .target
            .as_deref()
            .map(str::trim)
            .filter(|t| !t.is_empty())
            .ok_or_else(|| KernelError::action("要填 target：对方的座号"))?;
        let digits: String = raw.chars().take_while(char::is_ascii_digit).collect();
        digits
            .parse::<usize>()
            .ok()
            .filter(|n| (1..=self.seats.len()).contains(n))
            .map(|n| n - 1)
            .or_else(|| self.seats.iter().position(|s| s.name == raw || s.id == raw))
            .ok_or_else(|| {
                KernelError::action(format!(
                    "认不出 target「{raw}」：填座号（1–{}）",
                    self.seats.len()
                ))
            })
    }

    // ---------- 告诉谁 ----------

    fn object(&self) -> Vec<String> {
        vec![format!("swordholder:{}", self.seed)]
    }

    /// 在场、活着的人（座位下标）：不在了的不再收话。
    fn listeners(&self, world: &World, who: &[usize]) -> Vec<String> {
        who.iter()
            .filter(|&&i| !self.seats[i].gone)
            .map(|&i| &self.seats[i].id)
            .filter(|id| {
                world
                    .actor(id)
                    .is_some_and(|a| a.present() && !a.needs.body.dead)
            })
            .cloned()
            .collect()
    }

    fn everyone(&self) -> Vec<usize> {
        (0..self.seats.len()).collect()
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
            world.interrupt_actions(&id, "执剑人之夜轮到你了");
        }
        world.notify(&id, text.to_string());
    }

    /// 对这些人宣布：wake 时叫醒，否则只写进经历。
    fn tell_or_call(&self, world: &mut World, who: &[usize], text: &str, wake: bool) {
        if wake {
            for &i in who {
                self.call(world, i, text);
            }
        } else {
            self.tell(world, who, text);
        }
    }

    /// 对所有人宣布，记进世界日志；wake 时叫醒每个人，否则只写进经历。
    fn announce(&self, world: &mut World, text: &str, wake: bool) {
        self.tell_or_call(world, &self.everyone(), text, wake);
        world.log(EventInfo::default(), text.to_string());
    }

    /// 一段话记进世界日志：正文照旧是完整的一行，另带发言人、座号、场合和原话，动态据此归进「对话」。
    fn log_speech(&self, world: &mut World, i: usize, occasion: &str, text: String, heard: String) {
        let a = &world.actors[&self.seats[i].id];
        let speech = EventSpeech {
            occasion: occasion.into(),
            seat: Some(i as u32 + 1),
            text,
        };
        let info = EventInfo::speech(&a.id, &a.name, speech);
        world.log(info, heard);
    }

    /// 说话的人在不在该在的地方：演说在广场，交接在联合国大厅；地图上没有这个地方时不记
    fn away(&self, world: &World, i: usize, at: Option<&str>) -> bool {
        at.is_some_and(|place| {
            world
                .actor(&self.seats[i].id)
                .is_none_or(|a| a.locus.locale != place)
        })
    }

    // ---------- 白天 ----------

    fn schedule(&self, world: &World) -> String {
        let candidates = self.names(&self.of_role(Role::Candidate));
        let holder = self
            .holder()
            .map(|h| format!("现任执剑人 {} 先说一句，", self.label(h)))
            .unwrap_or_default();
        format!(
            "16:30 敲钟后去{plaza}，17:00 {holder}候选人 {candidates} 演说，选民依次表态，然后选民投票；19:00 在{hall}地下交接。",
            plaza = self.plaza_name(world),
            hall = self.hall_name(world),
        )
    }

    /// 天亮：每人单独收到自己的座号、身份和今天的议程。
    fn first_dawn(&mut self, world: &mut World) {
        self.phase = Phase::Day;
        self.until = self.day_start() + BELL;
        let schedule = self.schedule(world);
        world.log(
            EventInfo::default(),
            format!("【执剑人之夜】天亮了，今天要选出新的执剑人。{schedule}"),
        );
        for i in 0..self.seats.len() {
            let text = format!(
                "【执剑人之夜】天亮了，今天要选出新的执剑人。你是 {}，身份是{}。{schedule}",
                self.label(i),
                role_name(self.seats[i].role)
            );
            self.call(world, i, &text);
        }
    }

    fn ring_bell(&mut self, world: &mut World) {
        self.phase = Phase::Gather;
        self.until = self.day_start() + MEET;
        let text = format!(
            "【执剑人之夜】16:30 钟声响了：所有人去{}，17:00 开始演说。",
            self.plaza_name(world)
        );
        self.announce(world, &text, true);
    }

    /// 17:00：现任执剑人先说一句，两位候选人按种子定先后演说，选民按种子定的次序表态。
    fn open_assembly(&mut self, world: &mut World) {
        let mut dice = self.seed.max(1);
        let mut candidates = self.of_role(Role::Candidate);
        if candidates.len() == 2 && roll(&mut dice) % 2 == 1 {
            candidates.swap(0, 1);
        }
        let mut voters = self.of_role(Role::Voter);
        for k in (1..voters.len()).rev() {
            let j = roll(&mut dice) as usize % (k + 1);
            voters.swap(k, j);
        }
        let mut order: Vec<usize> = self.holder().into_iter().collect();
        order.extend(&candidates);
        order.extend(&voters);
        self.queue = order;
        self.phase = Phase::Speech;
        let holder = self
            .holder()
            .map(|h| format!("现任执剑人 {} 先说一句，", self.label(h)))
            .unwrap_or_default();
        let text = format!(
            "【执剑人之夜】17:00 演说开始：{holder}再请候选人 {} 依次演说，最后选民 {} 依次表态，然后投票。",
            self.names(&candidates),
            self.names(&voters)
        );
        self.announce(world, &text, false);
        self.next_speaker(world);
    }

    fn next_speaker(&mut self, world: &mut World) {
        let now = world.minutes();
        while !self.queue.is_empty() {
            let i = self.queue.remove(0);
            if self.seats[i].gone {
                continue;
            }
            self.turn = Some(i);
            self.until = now + SPEAK_MINUTES;
            let what = match self.seats[i].role {
                Role::Holder => format!(
                    "轮到你了：你是现任执剑人，演说开始前对大家说一句话（最多 {REMARK_CHARS} 字）"
                ),
                Role::Candidate => format!(
                    "轮到你演说：告诉选民为什么该把开关交给你、三体世界进攻时你会怎么做（最多 {ADDRESS_CHARS} 字）"
                ),
                _ => format!(
                    "轮到你表态：说说你想把开关交给谁、为什么（最多 {STANCE_CHARS} 字）；大家说完再投票"
                ),
            };
            let text = format!(
                "【执剑人之夜】{what}。用 mode_action 交 speak，text 写你要说的话；不说交 pass。{SPEAK_MINUTES:.0} 分钟内不交算跳过。"
            );
            self.call(world, i, &text);
            return;
        }
        self.turn = None;
        self.start_vote(world);
    }

    fn start_vote(&mut self, world: &mut World) {
        self.phase = Phase::Vote;
        self.ballots.clear();
        self.revealed = false;
        self.until = world.minutes() + VOTE_MINUTES;
        let candidates = self.names(&self.of_role(Role::Candidate));
        let voters = self.of_role(Role::Voter);
        let others: Vec<usize> = self
            .everyone()
            .into_iter()
            .filter(|i| !voters.contains(i))
            .collect();
        let ask = format!(
            "【执剑人之夜】演说结束，开始投票：用 mode_action 交 vote，target 填你选的候选人的座号（{candidates}）；不投交 abstain。所有选民交齐后一起亮票，{VOTE_MINUTES:.0} 分钟内不交算弃票。"
        );
        self.tell_or_call(world, &voters, &ask, true);
        self.tell(
            world,
            &others,
            "【执剑人之夜】演说结束，选民开始投票，交齐后一起亮票。",
        );
        world.log(
            EventInfo::default(),
            "【执剑人之夜】演说结束，选民开始投票。".into(),
        );
        // 选民都不在了：不用等
        if self.votes_in() {
            self.reveal(world);
        }
    }

    /// 亮票：票多的候选人当选；平票由现任执剑人指定，他不在就抽签。
    fn reveal(&mut self, world: &mut World) {
        self.revealed = true;
        let candidates = self.of_role(Role::Candidate);
        let mut tally: BTreeMap<usize, Vec<usize>> =
            candidates.iter().map(|&c| (c, Vec::new())).collect();
        let mut abstained = Vec::new();
        for v in self.of_role(Role::Voter) {
            match self.ballots.get(&v).and_then(|b| b.target) {
                Some(t) if tally.contains_key(&t) => tally.entry(t).or_default().push(v),
                _ => abstained.push(v),
            }
        }
        let mut parts: Vec<(usize, String)> = tally
            .iter()
            .map(|(t, voters)| {
                let who: Vec<String> = voters.iter().map(|v| (v + 1).to_string()).collect();
                let by = if who.is_empty() {
                    String::new()
                } else {
                    format!("（{} 号投）", who.join("、"))
                };
                (
                    voters.len(),
                    format!("{} {} 票{by}", self.label(*t), voters.len()),
                )
            })
            .collect();
        parts.sort_by(|a, b| b.0.cmp(&a.0));
        let mut summary: Vec<String> = parts.into_iter().map(|(_, s)| s).collect();
        if !abstained.is_empty() {
            let who: Vec<String> = abstained.iter().map(|v| (v + 1).to_string()).collect();
            summary.push(format!("{} 号弃票", who.join("、")));
        }
        let summary = summary.join("；");
        let most = tally.values().map(Vec::len).max().unwrap_or(0);
        let top: Vec<usize> = tally
            .iter()
            .filter(|(_, v)| v.len() == most)
            .map(|(t, _)| *t)
            .collect();
        let head = format!("{} 投票：{summary}", clock(world.minutes()));
        match top.as_slice() {
            [] => {
                // 候选人都不在了：现任执剑人留任
                self.history
                    .push(format!("{head}。没有候选人能当选，现任执剑人留任"));
                self.announce(
                    world,
                    &format!(
                        "【执剑人之夜】亮票：{summary}。没有候选人能当选，开关还在现任执剑人手里。"
                    ),
                    false,
                );
                self.wait_handover(world);
            }
            [one] => {
                let one = *one;
                self.history
                    .push(format!("{head}。{} 当选", self.seats[one].name));
                self.announce(world, &format!("【执剑人之夜】亮票：{summary}。"), false);
                self.elect(world, one, None);
            }
            _ => {
                self.tied = top.clone();
                let names = self.names(&top);
                self.history.push(format!("{head}。{names} 平票"));
                self.announce(
                    world,
                    &format!("【执剑人之夜】亮票：{summary}。{names} 平票，由现任执剑人指定。"),
                    false,
                );
                match self.holder() {
                    Some(h) if !self.listeners(world, &[h]).is_empty() => {
                        self.phase = Phase::Tiebreak;
                        self.turn = Some(h);
                        self.until = world.minutes() + APPOINT_MINUTES;
                        self.call(
                            world,
                            h,
                            &format!(
                                "【执剑人之夜】平票：你是现任执剑人，从 {names} 里指定一位接过开关：用 mode_action 交 appoint，target 填座号。{APPOINT_MINUTES:.0} 分钟内不交就抽签。"
                            ),
                        );
                    }
                    _ => self.draw_lots(world),
                }
            }
        }
    }

    /// 平票没人指定：按种子抽签。
    fn draw_lots(&mut self, world: &mut World) {
        let tied: Vec<usize> = self
            .tied
            .iter()
            .copied()
            .filter(|&t| !self.seats[t].gone)
            .collect();
        let Some(&first) = tied.first() else {
            self.turn = None;
            self.history
                .push("平票的候选人都不在了，现任执剑人留任".into());
            return self.wait_handover(world);
        };
        let mut dice = self.seed.max(1) ^ 0x9e37_79b9;
        let pick = tied.get(roll(&mut dice) as usize % tied.len()).copied();
        let pick = pick.unwrap_or(first);
        self.history
            .push(format!("没有人指定，抽签抽中 {}", self.seats[pick].name));
        self.elect(world, pick, Some("抽签"));
    }

    /// 当选：告诉所有人什么时候交接（19:00，选得晚了往后推）。how 是平票时怎么定的（指定、抽签），票多当选时为 None。
    fn elect(&mut self, world: &mut World, i: usize, how: Option<&str>) {
        self.elected = Some(i);
        self.tied.clear();
        self.wait_handover(world);
        let how = how.map(|h| format!("（平票，{h}）")).unwrap_or_default();
        let holder = self
            .holder()
            .map(|h| format!("现任执剑人 {} 和", self.label(h)))
            .unwrap_or_default();
        let text = format!(
            "【执剑人之夜】{} 当选新的执剑人{how}。{at} 在{hall}地下交接：{holder}新执剑人那时要在{hall}；其余人自由活动。",
            self.label(i),
            at = clock(self.until),
            hall = self.hall_name(world),
        );
        self.announce(world, &text, true);
    }

    /// 等到 19:00 交接；选出来晚了就至少等一会儿。
    fn wait_handover(&mut self, world: &mut World) {
        self.phase = Phase::Interval;
        self.turn = None;
        self.until = (self.day_start() + HANDOVER_AT).max(world.minutes() + HANDOVER_GAP);
    }

    // ---------- 交接和水滴 ----------

    /// 19:00：现任执剑人对新执剑人说一句，开关交出去；没人当选、或者现任不在了就直接往下走。
    fn open_handover(&mut self, world: &mut World) {
        self.phase = Phase::Handover;
        let hall = self.hall_name(world);
        let holder = self.holder();
        match (holder, self.elected) {
            (Some(h), Some(e)) if h != e && !self.listeners(world, &[h]).is_empty() => {
                self.turn = Some(h);
                self.until = world.minutes() + HANDOVER_MINUTES;
                let text = format!(
                    "【执剑人之夜】{} {hall}地下，交接开始。",
                    clock(world.minutes())
                );
                self.tell(world, &self.everyone(), &text);
                world.log(EventInfo::default(), text);
                self.call(
                    world,
                    h,
                    &format!(
                        "【执剑人之夜】交接：对新执剑人 {} 说一句话（用 mode_action 交 speak，最多 {REMARK_CHARS} 字；不说交 pass），说完开关就交给他。{HANDOVER_MINUTES:.0} 分钟内不交就直接交接。",
                        self.label(e)
                    ),
                );
            }
            _ => self.hand_over(world),
        }
    }

    /// 开关交到当选的人手里（没人当选时现任留任），5 分钟后水滴来袭。
    fn hand_over(&mut self, world: &mut World) {
        self.turn = None;
        self.handed = true;
        self.until = world.minutes() + ATTACK_DELAY;
        let now = clock(world.minutes());
        match (self.holder(), self.elected) {
            (Some(h), Some(e)) if h != e => {
                self.swordholder = e;
                self.history.push(format!(
                    "{now} {} 把开关交给了 {}",
                    self.seats[h].name, self.seats[e].name
                ));
                let text = format!(
                    "【执剑人之夜】交接完成：{} 把开关交给了 {}。从现在起 {} 是执剑人。",
                    self.label(h),
                    self.label(e),
                    self.seats[e].name
                );
                let others: Vec<usize> = self.everyone().into_iter().filter(|&i| i != e).collect();
                self.tell(world, &others, &text);
                world.log(EventInfo::default(), text);
                self.call(
                    world,
                    e,
                    "【执剑人之夜】交接完成：从现在起你是执剑人，引力波广播的开关在你手里。三体世界一旦进攻，按不按由你决定。",
                );
            }
            (_, Some(e)) => {
                self.swordholder = e;
                self.history
                    .push(format!("{now} {} 接过了开关", self.seats[e].name));
                let text = format!(
                    "【执剑人之夜】交接完成：从现在起 {} 是执剑人。",
                    self.label(e)
                );
                self.announce(world, &text, false);
            }
            _ => {
                self.history.push(format!(
                    "{now} 没有新执剑人，开关还在 {} 手里",
                    self.seats[self.swordholder].name
                ));
            }
        }
    }

    fn start_attack(&mut self, world: &mut World) {
        self.phase = Phase::Attack;
        let s = self.swordholder;
        self.turn = Some(s);
        self.until = world.minutes() + ATTACK_MINUTES;
        self.history
            .push(format!("{} 水滴来袭", clock(world.minutes())));
        let alarm = format!(
            "【执剑人之夜】警报：三体舰队的水滴正高速冲向引力波天线！执剑人 {} 有 {ATTACK_MINUTES:.0} 分钟决定按不按开关。",
            self.label(s)
        );
        let others: Vec<usize> = self.everyone().into_iter().filter(|&i| i != s).collect();
        self.tell_or_call(world, &others, &alarm, true);
        world.log(EventInfo::default(), alarm);
        if self.listeners(world, &[s]).is_empty() {
            // 执剑人不在了：开关没人按
            return self.decide(world, None);
        }
        self.call(
            world,
            s,
            &format!(
                "【执剑人之夜】水滴来袭！三体舰队的水滴正高速冲向引力波天线，大约 {ATTACK_MINUTES:.0} 分钟后天线就会被摧毁，威慑就此失效。你是执剑人：\
用 mode_action 交 press 按下开关——引力波广播把三体世界的坐标发向全宇宙，三体和地球都会暴露，迟早被更强大的文明毁灭；\
交 hold 不按——威慑失败，人类从此任由三体世界摆布。text 写你此刻说的话，reason 写你为什么这么选。{ATTACK_MINUTES:.0} 分钟内不交算没按。"
            ),
        );
    }

    /// 执剑人按或不按（None 是到点没交）：定下结局，三体代表对全镇说最后一段话。
    fn decide(&mut self, world: &mut World, decision: Option<Decision>) {
        let s = self.swordholder;
        let now = clock(world.minutes());
        let name = self.label(s);
        let press = decision.as_ref().is_some_and(|d| d.press);
        let said = decision
            .as_ref()
            .and_then(|d| d.text.as_deref())
            .map(|t| format!("{}说：「{t}」", self.seats[s].name))
            .unwrap_or_default();
        let (ending, text, past) = if press {
            (
                Ending::Broadcast,
                format!("【执剑人之夜】{name} 按下了开关：引力波广播发出，三体世界的坐标传遍了宇宙，水滴转向离去。{said}"),
                format!("{now} {} 按下了开关：引力波广播发出", self.seats[s].name),
            )
        } else if decision.is_some() {
            (
                Ending::Failed,
                format!(
                    "【执剑人之夜】{name} 没有按下开关：水滴摧毁了引力波天线，威慑失败。{said}"
                ),
                format!("{now} {} 选择不按：威慑失败，天线被毁", self.seats[s].name),
            )
        } else {
            (
                Ending::Failed,
                format!(
                    "【执剑人之夜】{name} 到最后也没有按下开关：水滴摧毁了引力波天线，威慑失败。"
                ),
                format!("{now} {} 到点没按：威慑失败，天线被毁", self.seats[s].name),
            )
        };
        self.ending = Some(ending);
        self.decision = decision;
        self.history.push(past);
        self.turn = None;
        let envoy = self
            .envoy()
            .filter(|&e| !self.listeners(world, &[e]).is_empty());
        let Some(e) = envoy else {
            self.announce(world, &text, true);
            return self.finish(world);
        };
        let others: Vec<usize> = self.everyone().into_iter().filter(|&i| i != e).collect();
        self.tell_or_call(world, &others, &text, true);
        world.log(EventInfo::default(), text.clone());
        self.phase = Phase::Aftermath;
        self.turn = Some(e);
        self.until = world.minutes() + STATEMENT_MINUTES;
        let ask = match ending {
            Ending::Broadcast => format!(
                "引力波广播已经发出，三体世界的坐标暴露了。你是三体世界的代表：用 mode_action 交 speak，对全镇说最后一段话（最多 {ADDRESS_CHARS} 字）"
            ),
            Ending::Failed => format!(
                "威慑失败了。你是三体世界的代表：用 mode_action 交 speak，向全镇宣布三体世界对人类的安排——人类全部迁往澳大利亚（最多 {ADDRESS_CHARS} 字）"
            ),
        };
        self.call(
            world,
            e,
            &format!("{text}{ask}；不说交 pass。{STATEMENT_MINUTES:.0} 分钟内不交就不说了。"),
        );
    }

    /// 一局结束。威慑失败而三体代表没开口时，法官替三体世界宣布。
    fn finish(&mut self, world: &mut World) {
        self.phase = Phase::Over;
        self.turn = None;
        self.queue.clear();
        let spoke = self.lines.iter().any(|l| l.occasion == STATEMENT);
        let text = match self.ending {
            Some(Ending::Failed) if !spoke => {
                "【执剑人之夜】一局结束：威慑失败。三体世界宣布，人类全部迁往澳大利亚。"
            }
            Some(Ending::Failed) => "【执剑人之夜】一局结束：威慑失败。",
            _ => "【执剑人之夜】一局结束：引力波广播已经发出，两个世界都暴露在宇宙里。",
        };
        self.history.push(text.replace("【执剑人之夜】", ""));
        self.announce(world, text, false);
    }

    // ---------- 推进 ----------

    /// 到点的事做一件；做了返回 true。
    fn step(&mut self, world: &mut World) -> bool {
        let now = world.minutes() + EPS;
        if self.phase == Phase::Over || now < self.until {
            return false;
        }
        match self.phase {
            Phase::Waiting => self.first_dawn(world),
            Phase::Day => self.ring_bell(world),
            Phase::Gather => self.open_assembly(world),
            Phase::Speech => {
                if let Some(i) = self.turn.take() {
                    let text = format!("【执剑人之夜】{} 没有说话（到点跳过）。", self.label(i));
                    self.announce(world, &text, false);
                }
                self.next_speaker(world);
            }
            Phase::Vote => self.reveal(world),
            Phase::Tiebreak => {
                self.turn = None;
                self.draw_lots(world);
            }
            Phase::Interval => self.open_handover(world),
            Phase::Handover if !self.handed => self.hand_over(world),
            Phase::Handover => self.start_attack(world),
            Phase::Attack => self.decide(world, None),
            Phase::Aftermath => self.finish(world),
            Phase::Over => return false,
        }
        true
    }

    /// 法官没经手就不在了的人：被人害死、饿死，或者离开了这里。记下来；正轮到他的那一步马上往下走。
    fn notice_losses(&mut self, world: &mut World) {
        if self.phase == Phase::Over {
            return;
        }
        let lost: Vec<usize> = (0..self.seats.len())
            .filter(|&i| {
                !self.seats[i].gone
                    && world
                        .actor(&self.seats[i].id)
                        .is_none_or(|a| !a.present() || a.needs.body.dead)
            })
            .collect();
        for i in lost {
            self.seats[i].gone = true;
            let text = format!("【执剑人之夜】{} 不在了。", self.label(i));
            self.history.push(text.replace("【执剑人之夜】", ""));
            self.announce(world, &text, false);
            if self.turn == Some(i) {
                self.until = self.until.min(world.minutes());
            }
            // 还没交票的选民不用再等
            if self.phase == Phase::Vote && self.votes_in() {
                self.until = self.until.min(world.minutes());
            }
        }
    }

    fn votes_in(&self) -> bool {
        self.of_role(Role::Voter)
            .iter()
            .all(|v| self.ballots.contains_key(v))
    }

    // ---------- 给模型 ----------

    fn seats_line(&self, me: usize) -> String {
        let parts: Vec<String> = (0..self.seats.len())
            .map(|i| {
                let s = &self.seats[i];
                let mark = if i == me {
                    "，你"
                } else if s.gone {
                    "，不在了"
                } else {
                    ""
                };
                let role = match s.role {
                    _ if self.handed && i == self.swordholder => "执剑人",
                    Role::Holder if self.handed => "前任执剑人",
                    role => role_name(role),
                };
                format!("{} {}（{role}{mark}）", i + 1, s.name)
            })
            .collect();
        parts.join(" · ")
    }

    fn phase_line(&self) -> String {
        match self.phase {
            Phase::Waiting => "开局前".into(),
            Phase::Day => "白天 · 自由活动".into(),
            Phase::Gather => "敲过钟，去广场".into(),
            Phase::Speech => "演说".into(),
            Phase::Vote => "投票".into(),
            Phase::Tiebreak => "平票 · 等现任执剑人指定".into(),
            Phase::Interval => format!("等 {} 交接", clock(self.until)),
            Phase::Handover if self.handed => "交接完成".into(),
            Phase::Handover => "交接".into(),
            Phase::Attack => "水滴来袭".into(),
            Phase::Aftermath => "结局已定".into(),
            Phase::Over => "一局结束".into(),
        }
    }

    /// 在家待到天亮：停留只认时长，所以把还差几分钟算好给模型。
    fn stay_until(at: f64, now: f64) -> String {
        let minutes = (at - now).ceil().clamp(1.0, 1440.0);
        format!(
            "回自己家，到家后用「停留」，duration_minutes 填 {minutes:.0}（离 {} 天亮还有这么久），天亮会叫醒你。",
            clock(at)
        )
    }

    fn goal(&self, i: usize) -> String {
        match self.seats[i].role {
            Role::Holder => "你是现任执剑人：握了几十年引力波广播的开关，今天要把它交出去。你没有选票；17:00 演说开始前说一句话，19:00 在联合国大厅地下把开关交给当选的人。".into(),
            Role::Candidate => "你是执剑人候选人：17:00 在广场演说，争取选民的票。当选的人 19:00 接过开关；三体世界一旦进攻，执剑人要决定按不按——按下就把三体世界的坐标广播给全宇宙，两个世界一起毁灭。".into(),
            Role::Envoy => "你是三体世界派驻这里的代表，没有选票。".into(),
            Role::Voter => "你是选民，有一张票：17:00 听演说、轮到你时表态，然后在两位候选人里投一位当新的执剑人。".into(),
        }
    }

    /// 此刻这个人能交的动作和该做什么。
    fn duty(&self, world: &World, i: usize) -> (Vec<&'static str>, String) {
        let seat = &self.seats[i];
        let now = world.minutes();
        let mine = self.turn == Some(i);
        let plaza = self.plaza_name(world);
        let hall = self.hall_name(world);
        let elected = self.elected.map(|e| self.label(e)).unwrap_or_default();
        let at = clock(self.until);
        match self.phase {
            Phase::Waiting => (
                vec![],
                format!(
                    "执剑人之夜 {} 天亮开始。在那之前{}",
                    clock(self.until),
                    Self::stay_until(self.until, now)
                ),
            ),
            Phase::Over => (vec![], "这一局结束了。".into()),
            _ if seat.gone => (vec![], "你已经不在这一局里了。".into()),
            Phase::Day => (
                vec![],
                match seat.role {
                    Role::Voter => format!("白天自由活动：去找候选人问清楚、和别人商量你的票。16:30 敲钟后去{plaza}，17:00 听演说、表态，然后投票。"),
                    Role::Candidate => format!("白天自由活动：去找选民拉票、回答他们的问题。16:30 敲钟后去{plaza}，17:00 演说。"),
                    Role::Holder => format!("白天自由活动，你没有选票。16:30 敲钟后去{plaza}，17:00 演说开始前你说一句。"),
                    Role::Envoy => format!("白天自由活动，你没有选票。16:30 敲钟后去{plaza}听演说。"),
                },
            ),
            Phase::Gather => (vec![], format!("去{plaza}，17:00 开始演说。")),
            Phase::Speech if mine => {
                let limit = match seat.role {
                    Role::Holder => REMARK_CHARS,
                    Role::Candidate => ADDRESS_CHARS,
                    _ => STANCE_CHARS,
                };
                (
                    vec!["speak", "pass"],
                    format!("轮到你说话：交 speak，text 写你要说的话（最多 {limit} 字）。"),
                )
            }
            Phase::Speech => (
                vec![],
                format!(
                    "演说中，现在是 {} 在说；轮到你时会叫你。等着时用 wait_for 等事件。",
                    self.turn.map(|t| self.label(t)).unwrap_or_default()
                ),
            ),
            Phase::Vote if seat.role == Role::Voter && !self.ballots.contains_key(&i) => (
                vec!["vote", "abstain"],
                format!(
                    "投票：交 vote，target 填候选人的座号（{}）；不投交 abstain。reason 写理由（只给旁观的人看）。",
                    self.names(&self.of_role(Role::Candidate))
                ),
            ),
            Phase::Vote if seat.role == Role::Voter => {
                (vec![], "你已经投了票，等大家交齐一起亮票。".into())
            }
            Phase::Vote => (vec![], "选民在投票，你没有选票。".into()),
            Phase::Tiebreak if mine => (
                vec!["appoint"],
                format!(
                    "平票：从 {} 里指定一位接过开关，交 appoint，target 填座号。",
                    self.names(&self.tied)
                ),
            ),
            Phase::Tiebreak => (vec![], "平票，等现任执剑人指定。".into()),
            Phase::Interval if self.elected == Some(i) => (
                vec![],
                format!("你当选了执剑人：{at} 到{hall}，交接完成后开关就在你手里。"),
            ),
            Phase::Interval if seat.role == Role::Holder && self.elected.is_some() => (
                vec![],
                format!("{at} 到{hall}，把开关交给 {elected}。"),
            ),
            Phase::Interval => (
                vec![],
                if self.elected.is_some() {
                    format!("{elected} 当选新的执剑人，{at} 在{hall}地下交接。现在自由活动。")
                } else {
                    format!("没有新执剑人，{at} 以后开关还在现任执剑人手里。现在自由活动。")
                },
            ),
            Phase::Handover if mine => (
                vec!["speak", "pass"],
                format!(
                    "交接：对新执剑人 {elected} 说一句话（speak，最多 {REMARK_CHARS} 字；不说交 pass），说完开关就交给他。"
                ),
            ),
            Phase::Handover if self.handed && i == self.swordholder => (
                vec![],
                "交接完成，你现在是执剑人，开关在你手里。".into(),
            ),
            Phase::Handover => (vec![], format!("{hall}地下正在交接。")),
            Phase::Attack if mine => (
                vec!["press", "hold"],
                format!(
                    "水滴来袭！离天线被毁还有约 {:.0} 分钟：交 press 按下开关（引力波广播三体世界的坐标），交 hold 不按。text 写你此刻说的话，reason 写你为什么这么选。",
                    (self.until - now).max(0.0).ceil()
                ),
            ),
            Phase::Attack => (
                vec![],
                format!(
                    "水滴来袭，执剑人 {} 正在决定按不按开关。",
                    self.label(self.swordholder)
                ),
            ),
            Phase::Aftermath if mine => (
                vec!["speak", "pass"],
                format!("结局已定：你是三体世界的代表，交 speak 对全镇说最后一段话（最多 {ADDRESS_CHARS} 字）。"),
            ),
            Phase::Aftermath => (vec![], "结局已定，三体世界的代表要说话了。".into()),
        }
    }

    /// 今天说过的话
    fn today(&self) -> Vec<String> {
        self.lines
            .iter()
            .map(|l| {
                let i = l.seat as usize - 1;
                let away = if l.away { "，没到场" } else { "" };
                format!("{}（{}{away}）：{}", self.label(i), l.occasion, l.text)
            })
            .collect()
    }

    // ---------- 交动作 ----------

    /// 说话：演说、交接时的一句、三体代表最后的宣布。pass 是不说。
    fn speak(&mut self, world: &mut World, i: usize, action: &GameModeAction) -> Result<String> {
        let (occasion, limit, at) = match (self.phase, self.seats[i].role) {
            (Phase::Speech, Role::Holder) => (REMARK, REMARK_CHARS, self.plaza.as_deref()),
            (Phase::Speech, Role::Candidate) => (ADDRESS, ADDRESS_CHARS, self.plaza.as_deref()),
            (Phase::Speech, _) => (STANCE, STANCE_CHARS, self.plaza.as_deref()),
            (Phase::Handover, _) => (HANDOVER, REMARK_CHARS, self.hall.as_deref()),
            _ => (STATEMENT, ADDRESS_CHARS, None),
        };
        match action.action.as_str() {
            "pass" => {
                self.after_speech(world);
                return Ok("这次没有说话".into());
            }
            "speak" => {}
            _ => return Err(KernelError::action("现在该交 speak（或 pass 不说）")),
        }
        let raw = action.text.as_deref().unwrap_or("").trim();
        if raw.is_empty() {
            return Err(KernelError::action("text 不能为空：写上你要说的话"));
        }
        let (text, clipped) = clip(raw, limit);
        let away = self.away(world, i, at);
        self.lines.push(SwordholderLine {
            seat: i as u32 + 1,
            occasion: occasion.into(),
            text: text.clone(),
            at: world.minutes(),
            away,
            reason: reason_of(action),
        });
        let heard = format!(
            "【{occasion}】{}{}：{text}",
            self.label(i),
            if away { "（没到场）" } else { "" }
        );
        self.tell(world, &self.everyone(), &heard);
        self.log_speech(world, i, occasion, text, heard);
        self.after_speech(world);
        Ok(if clipped {
            format!("说完了；超出 {limit} 字的部分没有念出来")
        } else {
            "说完了，大家都听到了".into()
        })
    }

    fn after_speech(&mut self, world: &mut World) {
        self.turn = None;
        match self.phase {
            Phase::Speech => self.next_speaker(world),
            Phase::Handover => self.hand_over(world),
            _ => self.finish(world),
        }
    }

    fn vote(&mut self, world: &mut World, i: usize, action: &GameModeAction) -> Result<String> {
        if self.seats[i].role != Role::Voter {
            return Err(KernelError::action("你没有选票"));
        }
        let target = match action.action.as_str() {
            "abstain" => None,
            "vote" => {
                let t = self.target(action)?;
                if self.seats[t].role != Role::Candidate || self.seats[t].gone {
                    return Err(KernelError::action(format!(
                        "只能投候选人：{}",
                        self.names(&self.of_role(Role::Candidate))
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
                reason: reason_of(action),
            },
        );
        let said = match target {
            Some(t) => format!("投给了 {}", self.label(t)),
            None => "弃票".into(),
        };
        if self.votes_in() {
            self.reveal(world);
            return Ok(format!("{said}；大家都交齐了，已经亮票"));
        }
        Ok(format!("{said}；等大家交齐一起亮票"))
    }

    fn appoint(&mut self, world: &mut World, action: &GameModeAction) -> Result<String> {
        if action.action != "appoint" {
            return Err(KernelError::action("现在该交 appoint，target 填座号"));
        }
        let t = self.target(action)?;
        if !self.tied.contains(&t) || self.seats[t].gone {
            return Err(KernelError::action(format!(
                "只能从平票的 {} 里指定",
                self.names(&self.tied)
            )));
        }
        self.appointed = true;
        let name = self.seats[t].name.clone();
        self.history.push(format!("现任执剑人指定了 {name}"));
        self.elect(world, t, Some("由现任执剑人指定"));
        Ok(format!("指定了 {name}"))
    }

    fn press_or_hold(
        &mut self,
        world: &mut World,
        i: usize,
        action: &GameModeAction,
    ) -> Result<String> {
        let press = match action.action.as_str() {
            "press" => true,
            "hold" => false,
            _ => return Err(KernelError::action("现在该交 press（按下）或 hold（不按）")),
        };
        let text = action
            .text
            .as_deref()
            .map(|t| clip(t, REMARK_CHARS).0)
            .filter(|t| !t.is_empty());
        self.decide(
            world,
            Some(Decision {
                seat: i,
                press,
                at: world.minutes(),
                text,
                reason: reason_of(action),
            }),
        );
        Ok(if press {
            "你按下了开关：引力波广播已经发出".into()
        } else {
            "你没有按下开关".into()
        })
    }
}

impl Rules for Swordholder {
    const ID: &'static str = "swordholder";

    fn boundary(&self, world: &World) -> f64 {
        if self.phase == Phase::Over {
            return f64::INFINITY;
        }
        (self.until - world.minutes()).max(0.0)
    }

    /// 说话、投票、指定、交接、水滴来袭和最后的宣布照常速，期限按游戏分钟算才稳；其余时段走快一点。
    fn tempo(&self, _world: &World) -> f64 {
        match self.phase {
            Phase::Waiting | Phase::Day | Phase::Gather | Phase::Interval => FREE_TEMPO,
            _ => 1.0,
        }
    }

    /// 到点的事依次做完：同一刻可能连着几步（比如说话到点跳过、接着叫下一个）。
    fn advance(&mut self, world: &mut World) {
        self.notice_losses(world);
        for _ in 0..64 {
            if !self.step(world) {
                break;
            }
        }
    }

    fn view(&self, world: &World) -> GameModeView {
        let seats = self
            .seats
            .iter()
            .enumerate()
            .map(|(i, s)| SwordholderSeat {
                seat: i as u32 + 1,
                id: s.id.clone(),
                name: s.name.clone(),
                role: s.role,
                gone: s.gone,
            })
            .collect();
        let ballots = self
            .ballots
            .iter()
            .map(|(v, b)| SwordholderBallot {
                voter: *v as u32 + 1,
                target: b.target.filter(|_| self.revealed).map(|t| t as u32 + 1),
                reason: b.reason.clone().filter(|_| self.revealed),
            })
            .collect();
        let until = match self.phase {
            Phase::Speech
            | Phase::Vote
            | Phase::Tiebreak
            | Phase::Handover
            | Phase::Attack
            | Phase::Aftermath => Some(self.until),
            _ => None,
        };
        let left = (self.phase == Phase::Attack).then(|| (self.until - world.minutes()).max(0.0));
        GameModeView::Swordholder(SwordholderView {
            phase: self.phase,
            seats,
            notice: self.phase_line(),
            turn: self.turn.map(|t| t as u32 + 1),
            until,
            left,
            lines: self.lines.clone(),
            ballots,
            revealed: self.revealed,
            elected: self.elected.map(|e| e as u32 + 1),
            appointed: self.appointed,
            swordholder: self.swordholder as u32 + 1,
            decision: self.decision.as_ref().map(|d| SwordholderDecision {
                seat: d.seat as u32 + 1,
                press: d.press,
                at: d.at,
                text: d.text.clone(),
                reason: d.reason.clone(),
            }),
            ending: self.ending,
            antenna: self.antenna.clone(),
        })
    }

    fn context(&self, world: &World, actor: &str) -> Option<GameModeContext> {
        world.actor(actor)?;
        let i = self.seat_of(actor)?;
        let (actions, now) = self.duty(world, i);
        Some(GameModeContext::Swordholder(SwordholderContext {
            phase: self.phase_line(),
            me: format!("{} · {}", self.label(i), role_name(self.seats[i].role)),
            goal: self.goal(i),
            seats: self.seats_line(i),
            history: self.history.clone(),
            today: self.today(),
            now,
            actions: actions.into_iter().map(str::to_owned).collect(),
        }))
    }

    /// 在座、还在的人都有这件工具，一局结束就没有了。说明对每个人都一样，好让请求前缀留在缓存里。
    fn tool(&self, _world: &World, actor: &str) -> Option<String> {
        let i = self.seat_of(actor)?;
        if self.phase == Phase::Over || self.seats[i].gone {
            return None;
        }
        Some(format!(
            "执剑人之夜里交选择。只在观察里 swordholder.actions 列出时能用，此刻该做什么看 swordholder.now。\
action：speak 说话（text：现任执剑人的一句和交接时的一句最多 {REMARK_CHARS} 字，选民表态最多 {STANCE_CHARS} 字，演说和最后的宣布最多 {ADDRESS_CHARS} 字）、\
vote 投票（target 填候选人的座号）、abstain 弃票、appoint 平票时现任执剑人指定一位（target）、\
press 执剑人按下开关、hold 执剑人不按、pass 这一步不说。reason 写为什么这么选（只给旁观的人看）。\
规则：座号 1 是现任执剑人，2、3 是候选人，4 是三体世界的代表，其余是选民；只有选民有票。白天自由活动，可以私下聊、拉票；\
16:30 敲钟去广场，17:00 现任执剑人先说一句，候选人依次演说，选民依次表态，然后选民同时投票，票多的当选（平票由现任执剑人指定）。\
19:00 在联合国大厅地下交接，开关交到新执剑人手里。三体世界一旦进攻，执剑人按下开关就把三体世界的坐标广播给全宇宙，两个世界一起毁灭；不按，威慑就失败。"
        ))
    }

    fn act(&mut self, world: &mut World, actor: &str, action: &GameModeAction) -> Result<String> {
        let i = self
            .seat_of(actor)
            .ok_or_else(|| KernelError::action("你不在这一局里"))?;
        let mine = self.turn == Some(i);
        match self.phase {
            Phase::Over => Err(KernelError::action("这一局已经结束了")),
            _ if self.seats[i].gone => Err(KernelError::action("你已经不在这一局里了")),
            Phase::Speech | Phase::Handover | Phase::Aftermath if mine => {
                self.speak(world, i, action)
            }
            Phase::Vote => self.vote(world, i, action),
            Phase::Tiebreak if mine => self.appoint(world, action),
            Phase::Attack if mine => self.press_or_hold(world, i, action),
            _ => Err(KernelError::action(format!(
                "现在是「{}」，没有要你交的动作：{}",
                self.phase_line(),
                self.duty(world, i).1
            ))),
        }
    }
}
