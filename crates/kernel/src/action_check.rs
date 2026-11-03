//! 单条动作的可执行性校验。入队（run_actions）和开始（start_intent）都走这里：
//! 静态条件（封闭集合、道具、时长、身体能力）两处都查，使用条件和道具占用只在开始那一刻查。
//! 这些检查横跨拓扑、可供性、背包、道具与人物，只读整个世界。
use crate::error::{KernelError, Result};
use crate::{
    actor::Actors,
    affordance::Spot,
    intent::{validate, Intent},
    props::{Action, Completion, Condition},
    topology::Topology,
    World,
};
use protocol::{ActionDraft, InventoryAction};

/// 背包操作草案的固定写法：verb 是操作名，没有别的参数，耗时 1 分钟。
fn check_inventory_shape(draft: &ActionDraft, op: &InventoryAction) -> Result<()> {
    let plain = draft.intent.verb == op.label()
        && draft.prop_id.is_none()
        && draft.recipient.is_none()
        && draft.writing.is_none()
        && draft.intent.locale.is_none()
        && draft.intent.target.is_none()
        && draft.intent.until.is_none()
        && !draft.intent.duration_minutes.is_some_and(|n| n != 1.0);
    ensure!(
        plain,
        KernelError::inventory("背包操作只填写对应 verb 和同级 inventory，固定耗时 1 分钟")
    );
    Ok(())
}

/// 把动作编号写法的 verb 换成动作词；找不到就原样返回。动作组和招待用餐共用。
pub(crate) fn normalize_verb(topo: &Topology, prop_id: Option<&str>, verb: &str) -> String {
    prop_id
        .and_then(|id| topo.prop(id))
        .and_then(|p| {
            p.verbs
                .iter()
                .find(|v| v.action.as_ref().is_some_and(|a| a.id == verb))
        })
        .map_or_else(|| verb.to_string(), |v| v.verb.clone())
}

pub(crate) fn normalize_drafts(topo: &Topology, drafts: &[ActionDraft]) -> Vec<ActionDraft> {
    drafts
        .iter()
        .map(|draft| {
            let mut d = draft.clone();
            d.intent.verb = normalize_verb(topo, d.prop_id.as_deref(), &d.intent.verb);
            d
        })
        .collect()
}

/// 单条草案 → (Intent, Spot)。`locale` 是这条动作将在哪个处所执行；
/// 道具可供性对前往、停留和背包操作为 None。
pub(crate) fn check_draft<'a>(
    w: &'a World,
    actor: &str,
    draft: &ActionDraft,
    locale: &str,
) -> Result<(Intent, Option<&'a Spot>)> {
    let intent = match &draft.inventory {
        Some(op) => {
            check_inventory_shape(draft, op)?;
            w.inventory.intent(&w.topo, actor, op)
        }
        None => validate(&w.topo, &w.affordances, &draft.intent)?,
    };
    let spot = check_intent(w, actor, &intent, locale, Some(draft))?;
    Ok((intent, spot))
}

/// 意图在 `locale` 执行的静态条件；`draft` 带道具、接受者、写作草稿等 Agent 参数。
pub(crate) fn check_intent<'a>(
    w: &'a World,
    actor: &str,
    intent: &Intent,
    locale: &str,
    draft: Option<&ActionDraft>,
) -> Result<Option<&'a Spot>> {
    if let Some(op) = draft.and_then(|d| d.inventory.as_ref()) {
        w.check_inventory(actor, op)?;
        return Ok(None);
    }
    let prop = draft.and_then(|d| d.prop_id.as_deref());
    let reach = crate::avatar::Reach::new(w);
    if let Some(prop) = prop {
        reach.prop(actor, prop)?;
    }
    if let Some(recipient) = draft.and_then(|d| d.recipient.as_deref()) {
        reach.pair(actor, recipient)?;
    }
    if let Some(d) = draft {
        crate::content::check_draft(&w.affordances, d, locale)?;
        ensure!(
            d.recipient.is_none() || prop.is_some(),
            KernelError::action("接受者只用于道具动作")
        );
    }
    let spot = match intent {
        Intent::Goto { .. } => {
            ensure!(prop.is_none(), KernelError::action("前往不接受道具参数"));
            None
        }
        Intent::Stay { station, .. } => {
            ensure!(prop.is_none(), KernelError::action("停留不接受道具参数"));
            check_action_station(&w.topo, locale, station.as_deref())?;
            None
        }
        Intent::Look => {
            ensure!(
                prop.is_none(),
                KernelError::action("查看四周不接受道具参数")
            );
            None
        }
        Intent::Do { verb, station, .. } => {
            check_action_station(&w.topo, locale, station.as_deref())?;
            Some(check_prop_action(w, actor, verb, locale, draft)?)
        }
    };
    w.actors
        .get(actor)
        .ok_or_else(|| KernelError::NoSuchActor(actor.into()))?
        .needs
        .check_action(intent.is_goto(), spot)?;
    w.check_weather_action(actor, intent, locale, spot)?;
    Ok(spot)
}

/// 道具动作：找到可供性，核对时长、道具状态与接受者。
fn check_prop_action<'a>(
    w: &'a World,
    actor: &str,
    verb: &str,
    locale: &str,
    draft: Option<&ActionDraft>,
) -> Result<&'a Spot> {
    let spot = match draft {
        None => w
            .affordances
            .spot(locale, verb)
            .ok_or_else(|| KernelError::action(format!("这里没有能{verb}的地方")))?,
        Some(d) => {
            if let Some(place) = d.intent.locale.as_deref().filter(|p| *p != locale) {
                return Err(KernelError::action(format!(
                    "当前不在 {place}；请先用 intent {{verb:前往, locale:目的地点ID}} 移动，到达后观察道具再行动"
                )));
            }
            let spot = action_spot_for(w, actor, locale, d)?;
            ensure!(
                d.intent.until.is_none()
                    && !d.intent.duration_minutes.is_some_and(|m| m < spot.minutes),
                KernelError::action("道具动作必须完成标称时长，不能提前结束")
            );
            spot
        }
    };
    if let Some(action) = &spot.action {
        let recipient = draft.and_then(|d| d.recipient.as_deref());
        crate::physiology::check_body_use(w, actor, locale, &spot.prop, action, recipient)?;
    }
    Ok(spot)
}

/// 开始那一刻才成立的条件：使用条件与道具占用。贴出来的公告大家可以同时看，几个人一起读同一条
/// 公告不算占用；别的动作（读书、写作、在别人正看时去用这件道具做别的事）仍要等道具空出来。
pub(crate) fn check_start_conditions(w: &World, actor: &str, spot: &Spot) -> Result<()> {
    if let Some(action) = &spot.action {
        let locale = &w.actors[actor].locus.locale;
        check_conditions(&w.topo, &w.actors, w.minutes, action, locale, &[actor])?;
    }
    let reads_notice = |action: Option<&Action>| {
        action.is_some_and(|a| matches!(a.completion, Completion::ReadBulletin))
    };
    let reading_too = |other: &str| {
        let a = &w.actors[other];
        reads_notice(
            w.affordances
                .action(Some(&spot.prop), &a.locus.locale, &a.current.verb),
        )
    };
    let shared = reads_notice(spot.action.as_ref());
    ensure!(
        w.prop_occupants(&spot.prop)
            .iter()
            .all(|o| o == actor || (shared && reading_too(o))),
        KernelError::action("道具正被其他村民使用")
    );
    Ok(())
}

/// 道具动作的使用条件：供餐时段按世界时间查，自己的住宅对每位使用者查。
/// 动作开始、招待用餐、领取补给都走这一份。
pub(crate) fn check_conditions(
    topo: &Topology,
    actors: &Actors,
    now: f64,
    action: &Action,
    locale: &str,
    users: &[&str],
) -> Result<()> {
    for condition in &action.conditions {
        match condition {
            Condition::OwnHome => ensure!(
                users
                    .iter()
                    .all(|u| actors[*u].home.as_deref() == Some(locale)),
                KernelError::action("只能在自己的住宅使用")
            ),
            Condition::MealWindow => ensure!(
                topo.meals.is_empty() || crate::calendar::meal_at(&topo.meals, now).is_some(),
                KernelError::action("这个点没有饭")
            ),
        }
    }
    Ok(())
}

fn check_action_station(topo: &Topology, locale: &str, station: Option<&str>) -> Result<()> {
    ensure!(
        station.is_none_or(|s| topo.station_in(s, locale)),
        KernelError::action("落脚点不在动作执行处所")
    );
    Ok(())
}

/// 草案指定的道具动作：道具须在眼前或随身（`Inventory::at_hand` 的两种情形分开报错）。
pub(crate) fn action_spot_for<'a>(
    w: &'a World,
    actor: &str,
    locale: &str,
    draft: &ActionDraft,
) -> Result<&'a Spot> {
    let prop = draft
        .prop_id
        .as_deref()
        .ok_or_else(|| KernelError::action("道具动作必须指定 prop_id"))?;
    if w.inventory.carried_by(prop, actor) {
        ensure!(
            draft.intent.target.is_none(),
            KernelError::action("使用随身物品无需指定落脚点")
        );
        ensure!(
            w.topo.is_dwell(locale),
            KernelError::action("随身物品须到合法驻留地点使用")
        );
        w.props.item(&w.topo, prop)?;
        return w
            .affordances
            .for_prop(prop, &draft.intent.verb)
            .ok_or_else(|| KernelError::action("该物品不支持此动作"));
    }
    let definition = w
        .topo
        .prop(prop)
        .ok_or_else(|| KernelError::action("道具不存在"))?;
    ensure!(
        !definition.withdrawn && w.inventory.on_map_at(&w.props, definition, locale),
        KernelError::action("道具不在动作执行处所")
    );
    w.affordances
        .for_prop(prop, &draft.intent.verb)
        .ok_or_else(|| KernelError::action("该道具不支持这个动作"))
}
