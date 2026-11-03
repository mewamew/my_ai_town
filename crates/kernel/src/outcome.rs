//! 执行记录的文案：动作回执与日记流水里的句子都在这里写，何时写、写给谁由各子系统决定。
//! 回执只记录发生的事实；阅读正文由 content 模块按实际读过的版本提供。
use crate::calendar;
use crate::presence;
use crate::props::{Completion, Need};
use crate::world::{ActKind, World};

/// 未完成的动作结算时：已经过去的时间与保留的后果。
pub(crate) fn elapsed(minutes: f64) -> String {
    format!("已进行 {minutes:.2} 分钟；已发生的移动和身体变化保留")
}

pub(crate) fn arrived(place: &str) -> String {
    format!("到达 {place}")
}

/// 前往当前所在的处所：没有移动。
pub(crate) fn stayed(place: &str) -> String {
    format!("已在{place}，本次未进行跨处所移动（耗时 0 分钟）")
}

/// 拾取、放下、存放、取回：操作名、物品名、件数。
pub(crate) fn transferred(label: &str, names: &[String], count: usize) -> String {
    format!("{label} {}；共 {count} 件", names.join("、"))
}

pub(crate) fn taken(portion: &str, quantity: u32, remaining: u32) -> String {
    format!("领取{portion} ×{quantity}；来源剩余 {remaining} 份")
}

pub(crate) fn supply_used(cost: u32, remaining: u32) -> String {
    format!("消耗 {cost} 份，剩余 {remaining} 份")
}

pub(crate) fn restored(name: &str, need: Need, gained: f64) -> String {
    format!("{name}{}恢复 {gained:.2} 点", need.label())
}

pub(crate) fn condition_applied(label: &str) -> String {
    format!("施加{label}")
}

pub(crate) fn condition_cured(label: &str) -> String {
    format!("解除{label}")
}

pub(crate) const REVIVED: &str = "接受者复活";

pub(crate) fn harmed(name: &str, wound: &str, lost: f64) -> String {
    format!("{name}受伤：{wound}，健康减少 {lost:.2} 点")
}

pub(crate) fn killed(name: &str) -> String {
    format!("{name}遇害身亡")
}

pub(crate) fn finished_reading(content: &crate::content::Text, prop_id: &str) -> String {
    format!(
        "读完《{}》版本 {}，作者 {}，实例 {prop_id}；可用 read_content 查看本次正文，是否记忆自行决定",
        content.title, content.version, content.author
    )
}

/// 写完的回执。`beside_writer`：地上没有空位了，书放在了作者写作的地方。
pub(crate) fn finished_writing(
    author: &str,
    title: &str,
    book: &str,
    place: &str,
    beside_writer: bool,
) -> String {
    if beside_writer {
        format!("{author}完成《{title}》；{place}地上没有空位了，书籍 {book} 放在写作的地方")
    } else {
        format!("{author}完成《{title}》；书籍 {book} 已放在{place}")
    }
}

pub(crate) struct Receipt {
    pub text: String,
    pub readable: Option<protocol::ReadableFact>,
}

/// 查看四周的回执：这里是什么地方、有哪些东西（说明、剩余、里面装着什么）、谁在、地上放着什么；
/// 末尾写明除此之外没有别的，说法能拿它当场核实。
pub(crate) fn survey(w: &World, actor_id: &str) -> String {
    let a = &w.actors[actor_id];
    let locale = &a.locus.locale;
    let place = w.topo.locale_name(locale);
    let mut parts = Vec::new();
    if let Some(p) = w.topo.place_of(locale) {
        if !p.summary.is_empty() {
            parts.push(p.summary.clone());
        }
        if !p.visible_features.is_empty() {
            parts.push(format!("看得到{}", p.visible_features.join("、")));
        }
    }
    let things: Vec<String> = w
        .topo
        .props()
        .iter()
        .filter(|p| p.locale == *locale && !p.withdrawn && w.can_access_prop(actor_id, p))
        .filter(|p| !w.inventory.carried_by(&p.id, actor_id))
        .map(|p| {
            let mut notes = Vec::new();
            if !p.description.is_empty() {
                notes.push(p.description.clone());
            }
            for action in p.verbs.iter().filter_map(|v| v.action.as_ref()) {
                if let Some(left) = w.props.supply_remaining(&p.id, action) {
                    notes.push(format!("剩 {left} 份"));
                }
            }
            let inside: Vec<String> = w
                .container_items(actor_id, &p.id)
                .into_iter()
                .map(|i| i.name)
                .collect();
            if p.storage_slots > 0 {
                notes.push(if inside.is_empty() {
                    "里面是空的".into()
                } else {
                    format!("里面有{}", inside.join("、"))
                });
            }
            if notes.is_empty() {
                p.name.clone()
            } else {
                format!("{}（{}）", p.name, notes.join("；"))
            }
        })
        .collect();
    parts.push(if things.is_empty() {
        "没有什么东西".into()
    } else {
        format!("有{}", things.join("、"))
    });
    let people: Vec<String> = w
        .actors
        .values()
        .filter(|o| o.id != actor_id && o.present() && o.locus.locale == *locale)
        .map(|o| {
            if o.needs.body.dead {
                match &o.needs.body.killed {
                    Some(k) => format!("{}（已经死了，{}）", o.name, k.wound),
                    None => format!("{}（已经死了）", o.name),
                }
            } else {
                format!("{}（{}）", o.name, o.current.verb)
            }
        })
        .collect();
    parts.push(if people.is_empty() {
        "没有别人".into()
    } else {
        format!("{}在这里", people.join("、"))
    });
    format!(
        "仔细查看了{place}：{}。除此之外，这里没有别的东西",
        parts.join("；")
    )
}

/// 生成一条执行记录的正文。verb 是刚完成的活动，now 是完成时刻。
pub(crate) fn receipt(w: &World, actor_id: &str, verb: &str, now: f64) -> Receipt {
    if crate::intent::BuiltinVerb::parse(verb) == Some(crate::intent::BuiltinVerb::Look) {
        return Receipt {
            text: survey(w, actor_id),
            readable: None,
        };
    }
    let a = &w.actors[actor_id];
    let minutes = (now - a.current.started_at).round().max(0.0);
    let locale = a.locus.locale.clone();
    let place = w.topo.locale_name(&locale);
    let started_at = a.current.started_at;
    let timed = matches!(a.current.kind, ActKind::Timed { .. });

    let prop_id = a
        .current
        .action
        .as_ref()
        .and_then(|b| b.draft.prop_id.as_deref());
    let completion = if timed {
        w.affordances
            .action(prop_id, &locale, verb)
            .map(|a| a.completion.clone())
    } else {
        None
    };
    let body = match completion {
        Some(Completion::Meal) => match calendar::meal_at(&w.topo.meals, started_at) {
            Some(m) => format!("在{place}吃了{}（{}）", m.name, m.menu),
            None => format!("在{place}吃了饭"),
        },
        Some(Completion::Research) => format!(
            "在{place}做了 {minutes:.0} 分钟「{verb}」；本动作尚未提供具体查询资料，不能据此判断是否存在相关记载"
        ),
        // 占位活动只有停留会走到这里（零时长占位在上游已排除）
        None if !a.current.advancing() => {
            let others = presence::others_here(&w.actors, actor_id);
            if others.is_empty() {
                format!("在{place}停留了 {minutes:.0} 分钟，周围没有别人")
            } else {
                format!(
                    "在{place}停留了 {minutes:.0} 分钟，{}也在",
                    presence::list(&others)
                )
            }
        }
        _ if timed && w.affordances.has(&locale, verb) => {
            format!("在{place}做了 {minutes:.0} 分钟「{verb}」")
        }
        _ => format!("完成了「{verb}」"),
    };
    Receipt {
        text: body,
        readable: None,
    }
}
