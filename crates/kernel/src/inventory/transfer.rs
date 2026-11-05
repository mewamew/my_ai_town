//! 背包操作的校验与结算：拾取、放下、存取与领取单份补给。
use super::*;
use crate::error::{KernelError, Result};
use crate::{
    action_check::check_conditions,
    intent::{Intent, StopCond},
    props::{check_room, Action, Definition, Instance, Placement, MAX_STACK},
};
use protocol::{At, InventoryAction as Op};
use sha2::{Digest, Sha256};

/// 一次领取的份数上限。
const TAKE_MAX: u32 = 40;

/// 背包检查读到的世界部件。可达判断由世界传入：居民总能够着眼前的物品，
/// 化身和附身者还要按行走几何走近（avatar 模块的规则）。
pub(crate) struct Surroundings<'a> {
    pub topo: &'a Topology,
    pub props: &'a Props,
    pub actors: &'a Actors,
    pub interactions: &'a crate::interactions::Interactions,
    pub now: f64,
    pub reach: &'a dyn Fn(&str, &str) -> Result<()>,
}

/// 一次领取：来源道具、动作编号与份数。
struct Take<'a> {
    source: &'a str,
    action: &'a str,
    quantity: u32,
}

fn bag(actor: &str) -> Location {
    Location::Carried {
        actor: actor.into(),
    }
}

/// 领取时的单份物品：独立定义，带完整的完成效果；劳作和持续设施效果不带走。
fn portions(
    topo: &Topology,
    props: &Props,
    actor: &Actor,
    take: &Take,
    key: &str,
) -> Result<Vec<Placement>> {
    let p = props.item(topo, take.source)?;
    let a = portion_action(p, take.action)?;
    let hash = format!(
        "{:x}",
        Sha256::digest(serde_json::json!([p.definition, a]).to_string())
    );
    let mut use_action = a.clone();
    use_action.supply = None;
    use_action.portion_name = None;
    use_action.consumes_item = true;
    use_action.conditions.clear();
    use_action.during.clear();
    let def = Definition {
        id: format!("portion:{hash}"),
        version: 1,
        name: a
            .portion_name
            .clone()
            .ok_or_else(|| KernelError::inventory("该动作未配置可领取物品"))?,
        description: "从有限补给领取的单份物品".into(),
        portable: true,
        stack_limit: MAX_STACK,
        storage_slots: 0,
        actions: vec![use_action],
        readable: None,
        bulletin_board: false,
        shelter: false,
    };
    def.validate()?;
    let prefix = format!("{:x}", Sha256::digest(format!("{}/{key}", actor.id)));
    Ok((0..take.quantity)
        .map(|i| Placement {
            instance: Instance {
                id: format!("portion:{prefix}_{i}"),
                definition: def.reference(),
                locale: actor.locus.locale.clone(),
                name: None,
                board: None,
            },
            definition: def.clone(),
        })
        .collect())
}

fn portion_action<'a>(prop: &'a Prop, action: &str) -> Result<&'a Action> {
    prop.verbs
        .iter()
        .filter_map(|v| v.action.as_ref())
        .find(|a| a.id == action && a.portion_name.is_some() && a.supply.is_some())
        .ok_or_else(|| KernelError::inventory("该动作未配置可领取物品"))
}

impl Inventory {
    /// 操作背包的人必须在合法驻留地点的落脚点上，且能够行动；返回所在处所。
    fn transfer_locale<'a>(&self, topo: &Topology, actor: &'a Actor) -> Result<&'a str> {
        ensure!(
            !actor.needs.incapacitated()
                && topo.is_dwell(&actor.locus.locale)
                && matches!(actor.locus.at, At::Station { .. } | At::Free { .. }),
            KernelError::inventory("须在合法驻留地点且能够行动时操作背包")
        );
        Ok(&actor.locus.locale)
    }
    fn source_here<'a>(&self, cx: &Surroundings<'a>, actor: &Actor, id: &str) -> Result<&'a Prop> {
        let locale = self.transfer_locale(cx.topo, actor)?;
        (cx.reach)(&actor.id, id)?;
        let p = cx.props.item(cx.topo, id)?;
        ensure!(
            self.on_map_at(cx.props, p, locale),
            KernelError::inventory("物品或容器不在眼前")
        );
        check_property_access(cx.topo, actor, locale)?;
        item_idle(cx.actors, cx.interactions, &actor.id, id)?;
        Ok(p)
    }
    /// 物品的操作点：随身没有；落地的在落地点；否则是道具自己的操作点（地图上有的话）。
    pub(crate) fn item_station(&self, topo: &Topology, actor: &str, id: &str) -> Option<String> {
        if self.carried_by(id, actor) {
            return None;
        }
        if let Some(Location::Ground { station, .. }) = self.locations.get(id) {
            return Some(station.clone());
        }
        topo.prop_station(id)
            .filter(|key| topo.stations.contains_key(key))
    }
    pub(crate) fn check(&self, cx: &Surroundings, actor: &str, op: &Op) -> Result<()> {
        let a = cx
            .actors
            .get(actor)
            .ok_or_else(|| KernelError::NoSuchActor(actor.into()))?;
        self.transfer_locale(cx.topo, a)?;
        if !matches!(op, Op::Take { .. }) {
            check_items(cx.topo, cx.props, op.items())?;
        }
        for id in op.items() {
            item_idle(cx.actors, cx.interactions, actor, id)?;
        }
        match op {
            Op::PickUp { items } => self.check_pick_up(cx, a, items),
            Op::Drop { items } => self.check_put_down(cx, a, items, None),
            Op::Store { items, container } => self.check_put_down(cx, a, items, Some(container)),
            Op::Retrieve { items, container } => self.check_retrieve(cx, a, items, container),
            Op::Take {
                source,
                action,
                quantity,
            } => self.check_take(
                cx,
                a,
                &Take {
                    source,
                    action,
                    quantity: *quantity,
                },
            ),
        }
    }
    fn check_pick_up(&self, cx: &Surroundings, actor: &Actor, items: &[String]) -> Result<()> {
        let mut station = None;
        for id in items {
            self.source_here(cx, actor, id)?;
            let at = self.item_station(cx.topo, &actor.id, id);
            ensure!(
                station.as_ref().is_none_or(|s| *s == at),
                KernelError::inventory("多件拾取须来自同一操作点，请分次拾取")
            );
            station = Some(at);
        }
        self.check_capacity(cx.topo, cx.props, &bag(&actor.id), items)
    }
    /// 放下或存进固定容器：只能动自己背包里的物品。
    fn check_put_down(
        &self,
        cx: &Surroundings,
        actor: &Actor,
        items: &[String],
        container: Option<&str>,
    ) -> Result<()> {
        for id in items {
            ensure!(
                self.carried_by(id, &actor.id),
                KernelError::inventory("只能转移自己背包里的物品")
            );
        }
        let locale = self.transfer_locale(cx.topo, actor)?;
        check_property_access(cx.topo, actor, locale)?;
        let Some(container) = container else {
            return Ok(());
        };
        let c = self.source_here(cx, actor, container)?;
        ensure!(
            c.storage_slots > 0 && !c.portable,
            KernelError::inventory("该道具不是固定容器")
        );
        self.check_capacity(
            cx.topo,
            cx.props,
            &Location::Stored {
                container: container.into(),
            },
            items,
        )
    }
    fn check_retrieve(
        &self,
        cx: &Surroundings,
        actor: &Actor,
        items: &[String],
        container: &str,
    ) -> Result<()> {
        let c = self.source_here(cx, actor, container)?;
        ensure!(
            c.storage_slots > 0,
            KernelError::inventory("该道具不是容器")
        );
        let source = Location::Stored {
            container: container.into(),
        };
        for id in items {
            ensure!(
                self.locations.get(id) == Some(&source),
                KernelError::inventory("物品已不在该容器")
            );
        }
        self.check_capacity(cx.topo, cx.props, &bag(&actor.id), items)
    }
    /// 领取单份：只检查来源、数量、条件和背包容量；效果在使用那一份时才结算。
    fn check_take(&self, cx: &Surroundings, actor: &Actor, take: &Take) -> Result<()> {
        let p = self.source_here(cx, actor, take.source)?;
        let a = portion_action(p, take.action)?;
        ensure!(
            (1..=TAKE_MAX).contains(&take.quantity),
            KernelError::inventory(format!("一次领取数量须为 1–{TAKE_MAX}"))
        );
        check_conditions(cx.topo, cx.actors, cx.now, a, &p.locale, &[&actor.id])?;
        let cost = a
            .supply
            .as_ref()
            .ok_or_else(|| KernelError::inventory("该动作未配置可领取物品"))?
            .cost
            .checked_mul(take.quantity)
            .ok_or_else(|| KernelError::inventory("领取数量溢出"))?;
        ensure!(
            cx.props.supply_remaining(take.source, a).unwrap_or(0) >= cost,
            KernelError::inventory("补给数量不足")
        );
        let pieces = portions(cx.topo, cx.props, actor, take, "preview")?;
        let resolved = pieces
            .iter()
            .map(|p| crate::props::catalog::resolve(&p.instance, &p.definition))
            .collect::<Result<Vec<_>, _>>()?;
        let existing = cx
            .topo
            .props()
            .iter()
            .filter(|p| !p.withdrawn && self.carried_by(&p.id, &actor.id));
        ensure!(
            Self::slots_used(cx.props, existing.chain(resolved.iter())) <= CAPACITY,
            KernelError::inventory("背包容量不足，未领取任何物品")
        );
        check_room(cx.topo.props().len(), resolved.len())?;
        Ok(())
    }
    /// 背包操作对应的意图：在来源物品或容器的操作点停留 1 分钟。
    pub(crate) fn intent(&self, topo: &Topology, actor: &str, op: &Op) -> Intent {
        let source = match op {
            Op::PickUp { items } => items.first().map(String::as_str),
            Op::Store { container, .. } | Op::Retrieve { container, .. } => {
                Some(container.as_str())
            }
            Op::Take { source, .. } => Some(source.as_str()),
            _ => None,
        };
        Intent::Stay {
            cond: StopCond::Duration(1.0),
            station: source.and_then(|s| self.item_station(topo, actor, s)),
            pose: crate::intent::Pose::Stand,
        }
    }
    /// 已通过 `check` 的操作在这里结算；返回回执里的变化。
    pub(crate) fn finish(
        &mut self,
        topo: &mut Topology,
        props: &mut Props,
        actor: &Actor,
        op: &Op,
        key: &str,
    ) -> Result<Vec<String>> {
        if let Op::Take {
            source,
            action,
            quantity,
        } = op
        {
            let take = Take {
                source,
                action,
                quantity: *quantity,
            };
            return self.finish_take(topo, props, actor, &take, key);
        }
        let dest = match op {
            Op::PickUp { .. } | Op::Retrieve { .. } => bag(&actor.id),
            Op::Store { container, .. } => Location::Stored {
                container: container.clone(),
            },
            Op::Drop { .. } => {
                let station = match &actor.locus.at {
                    At::Station { station } => station,
                    At::Free { .. } => actor
                        .control()
                        .and_then(|p| p.drop_station.as_ref())
                        .ok_or_else(|| KernelError::inventory("请走近落脚点再放下"))?,
                    _ => return Err(KernelError::inventory("当前位置不能放下物品")),
                };
                Location::Ground {
                    locale: actor.locus.locale.clone(),
                    station: station.clone(),
                }
            }
            Op::Take { .. } => unreachable!("领取已在上面结算"),
        };
        let names = op
            .items()
            .iter()
            .map(|id| props.item(topo, id).map(|p| p.name.clone()))
            .collect::<Result<Vec<_>, _>>()?;
        for id in op.items() {
            self.set_location(topo, props, id, dest.clone());
        }
        Ok(vec![crate::outcome::transferred(
            op.label(),
            &names,
            op.items().len(),
        )])
    }
    fn finish_take(
        &mut self,
        topo: &mut Topology,
        props: &mut Props,
        actor: &Actor,
        take: &Take,
        key: &str,
    ) -> Result<Vec<String>> {
        let pieces = portions(topo, props, actor, take, key)?;
        let resolved = pieces
            .iter()
            .map(|p| props.validate_placement(topo, p))
            .collect::<Result<Vec<_>, _>>()?;
        let a = portion_action(props.item(topo, take.source)?, take.action)?.clone();
        let remaining = props.consume_supply(take.source, &a, take.quantity);
        let ids: Vec<_> = pieces.iter().map(|p| p.instance.id.clone()).collect();
        for (placement, prop) in pieces.into_iter().zip(resolved) {
            props.insert(topo, placement, prop);
        }
        for id in &ids {
            self.set_location(topo, props, id, bag(&actor.id));
        }
        Ok(vec![crate::outcome::taken(
            a.portion_name.as_deref().unwrap_or_default(),
            take.quantity,
            remaining,
        )])
    }
    pub(crate) fn check_gift(
        &self,
        topo: &Topology,
        props: &Props,
        from: &str,
        to: &str,
        items: &[String],
    ) -> Result<()> {
        check_items(topo, props, items)?;
        for id in items {
            ensure!(
                self.carried_by(id, from),
                KernelError::inventory("赠品已不在发起者背包中")
            );
        }
        self.check_capacity(topo, props, &bag(to), items)
    }
    /// 抢、偷之前：东西还在对方身上，自己背包放得下。
    pub(crate) fn check_seize(
        &self,
        topo: &Topology,
        props: &Props,
        from: &str,
        to: &str,
        item: &str,
    ) -> Result<()> {
        let items = [item.to_string()];
        check_items(topo, props, &items)?;
        ensure!(
            self.carried_by(item, from),
            KernelError::inventory("那件东西不在对方身上")
        );
        self.check_capacity(topo, props, &bag(to), &items)
    }
    /// 已通过 `check_seize` 的抢、偷在这里转移。
    pub(crate) fn seize(&mut self, topo: &mut Topology, props: &mut Props, to: &str, item: &str) {
        self.set_location(topo, props, item, bag(to));
    }
    /// 已通过 `check_gift` 的赠予在这里转移。
    pub(crate) fn finish_gift(
        &mut self,
        topo: &mut Topology,
        props: &mut Props,
        from: &Actor,
        to: &Actor,
        items: &[String],
    ) -> Result<()> {
        ensure!(
            from.locus.locale == to.locus.locale
                && !from.needs.incapacitated()
                && !to.needs.incapacitated(),
            KernelError::inventory("赠予双方须在场且能行动")
        );
        for id in items {
            self.set_location(topo, props, id, bag(&to.id));
        }
        Ok(())
    }
}
