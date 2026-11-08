//! 说给东西：有人在交谈或邀请里说要把身上的东西给对方，东西不会自己过去，要发赠予邀请、对方接受了才转手。
//! 第四局骆川几次说把饼干给了苏蔓，一次也没发赠予，三块都自己吃了；苏蔓以为饼干到手，在营地等着，饿死了。
//! 第二到四局模型嘴上说「给你」几十次，真正转手的赠予只有一次，还有几次是想要的一方反过来给自己发赠予。
//! 认出这种话时，给说的人和听的人各记一条通知：东西还在说的人身上，要他发赠予、对方接受了才算给了。
//!
//! 认法只看说的人此刻身上带着的东西：同一句或上一句提到它（全名、去掉开头「一份」的名字、三个字以上的
//! 头两个字或末两个字，或紧挨着「给你」的末一个字），这一句有「给你」「分你」「拿去」这类说法，
//! 没有「不给」「报给你」这类否定和传话。认错了只是多一条提醒。
use crate::World;
use protocol::{Interaction, InteractionCommand, InteractionKind};

/// 同一个人对同一个人说同样的东西，多久里只提醒一次（分钟）。
const QUIET_MINUTES: f64 = 180.0;
/// 把东西交出去的说法，空格隔开。
const CUES: &str =
    "给你 给您 送你 分你 匀你 拿去 你拿着 拿着吧 你收着 收下 归你 你先吃 你先喝 喂你";
/// 「给你看看」「报给你」是说话，不是给东西。
const TALK: &str = "给你看 给您看 给你说 给您说 给你讲 给你听 给你瞧 报给你 报给您";
const REFUSE: &str = "不给 没给 给不了 没得 别想 休想 凭什么 舍不得 不分 不送 不匀";
/// 说法前三个字里有这些字就是否定：「不整个给你」「别拿去」。
const NEGATIONS: &str = "不没别";
/// 量词：「一份干粮」去掉「一份」，「这块给你」的「块」不当成石块。
const MEASURES: &str = "份把个块筒节包根片袋瓶口";
const PUNCTUATION: &str = "，。！？；：、,.!?;:…—\n";

/// 这一句里第一个没被否定的给的说法：(字节位置, 说法)。
fn cue(clause: &str) -> Option<(usize, &'static str)> {
    if TALK
        .split(' ')
        .chain(REFUSE.split(' '))
        .any(|t| clause.contains(t))
    {
        return None;
    }
    CUES.split(' ').find_map(|c| {
        let i = clause.find(c)?;
        let negated = clause[..i]
            .chars()
            .rev()
            .take(3)
            .any(|ch| NEGATIONS.contains(ch));
        (!negated).then_some((i, c))
    })
}

/// 东西名字去掉开头的「一份」「两块」。
fn core(name: &str) -> Vec<char> {
    let chars: Vec<char> = name.chars().collect();
    match chars.as_slice() {
        [n, m, rest @ ..] if !rest.is_empty() && "一两半".contains(*n) && MEASURES.contains(*m) => {
            rest.to_vec()
        }
        _ => chars,
    }
}

/// 话里点到这件东西的叫法：全名、去掉量词的名字，三个字以上的再加头两个字和末两个字。
fn names(name: &str) -> Vec<String> {
    let core = core(name);
    let mut out = vec![name.to_string(), core.iter().collect()];
    if core.len() >= 3 {
        out.push(core[..2].iter().collect());
        out.push(core[core.len() - 2..].iter().collect());
    }
    out.retain(|n| n.chars().count() >= 2);
    out
}

/// 一句话里说要交出去的东西：carried 是说的人身上带着的东西的名字，返回其中被说到的。
pub(crate) fn pledged<'a>(text: &str, carried: &'a [String]) -> Vec<&'a str> {
    let clauses: Vec<&str> = text.split(|c: char| PUNCTUATION.contains(c)).collect();
    let mut hits: Vec<&str> = Vec::new();
    for (k, clause) in clauses.iter().enumerate() {
        let Some((at, said)) = cue(clause) else {
            continue;
        };
        let before = if k > 0 { clauses[k - 1] } else { "" };
        for name in carried {
            if hits.contains(&name.as_str()) {
                continue;
            }
            let named = names(name)
                .iter()
                .any(|n| clause.contains(n.as_str()) || before.contains(n.as_str()));
            // 单字只认紧挨着说法的：「水给你」「叉子给你」「给你水」
            let close = core(name)
                .last()
                .filter(|c| !MEASURES.contains(**c))
                .is_some_and(|c| {
                    clause[..at].chars().rev().take(2).any(|x| x == *c)
                        || clause[at + said.len()..].chars().take(2).any(|x| x == *c)
                });
            if named || close {
                hits.push(name);
            }
        }
    }
    hits
}

/// 这条命令说出口的话和听的人：指名的、交谈里唯一的另一个人、邀请的对方。人多又没指名时不算；
/// 赠予邀请本身就是在给，不算。
pub(super) fn spoken<'c>(
    actor: &str,
    command: &'c InteractionCommand,
    item: &Interaction,
) -> Option<(&'c str, String)> {
    use InteractionCommand as C;
    let only = |members: Option<&std::collections::BTreeSet<String>>| {
        let rest: Vec<&String> = members?.iter().filter(|m| *m != actor).collect();
        (rest.len() == 1).then(|| rest[0].clone())
    };
    let members = || only(item.chat.as_ref().map(|c| &c.members));
    match command {
        C::Say { message, to, .. } | C::Propose { message, to, .. } => {
            Some((message, to.clone().or_else(members)?))
        }
        // 告辞后自己已不在成员里，两人交谈也可能随之结束：按到过这场交谈的人算
        C::Leave { message, .. } => {
            Some((message, only(item.chat.as_ref().map(|c| &c.ever_members))?))
        }
        C::Join { message, .. } | C::Accept { message, .. } | C::Decline { message, .. } => {
            Some((message, members()?))
        }
        C::Offer {
            partner_id,
            interaction,
            message,
        } if !matches!(interaction, InteractionKind::Give { .. }) => {
            Some((message, partner_id.clone()))
        }
        C::Reply { message, .. } => {
            let other = if item.initiator == actor {
                &item.partner
            } else {
                &item.initiator
            };
            Some((message, other.clone()))
        }
        _ => None,
    }
}

impl World {
    /// speaker 对 listener 说的一句话要是说把身上的东西给对方，给两人各记一条通知（见模块说明）。
    pub(crate) fn note_pledge(&mut self, speaker: &str, listener: &str, text: &str) {
        let (Some(giver), Some(taker)) = (self.actors.get(speaker), self.actors.get(listener))
        else {
            return;
        };
        if speaker == listener || text.trim().is_empty() {
            return;
        }
        let mut carried: Vec<String> = Vec::new();
        for p in self.topo.props() {
            if !p.withdrawn
                && self.inventory.carried_by(&p.id, speaker)
                && !carried.contains(&p.name)
            {
                carried.push(p.name.clone());
            }
        }
        let items = pledged(text, &carried);
        if items.is_empty() {
            return;
        }
        let what = items.join("、");
        let (me, them) = (giver.name.clone(), taker.name.clone());
        let (giver_avatar, taker_avatar) = (giver.is_avatar(), taker.is_avatar());
        let mine = format!(
            "你说要把{what}给{them}，东西还在你身上：交谈结束后发赠予邀请交给{them}，{them}接受了才算给了；能对别人用的东西，也可以直接拿它对{them}用。"
        );
        let theirs = format!(
            "{me}说要把{what}给你，东西还在{me}身上，还不是你的：要{me}发赠予邀请、你接受了才到你手上，你自己发不了。"
        );
        let now = self.minutes;
        let said_lately = |id: &str, text: &str| {
            self.actors[id]
                .journal
                .events_after(0)
                .iter()
                .rev()
                .take_while(|e| e.at >= now - QUIET_MINUTES)
                .any(|e| e.kind == protocol::FactKind::Notice && e.text.ends_with(text))
        };
        if said_lately(speaker, &mine) || said_lately(listener, &theirs) {
            return;
        }
        // 化身是玩家自己，不用提醒
        if !giver_avatar {
            self.notify(speaker, mine);
        }
        if !taker_avatar {
            self.notify(listener, theirs);
        }
    }
}
