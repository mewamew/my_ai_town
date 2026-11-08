//! 背包与容器的只读投影。
use super::*;
use crate::World;
use protocol::{InventorySlot, InventoryView, StoredItem};

impl Inventory {
    pub(crate) fn location_name(
        &self,
        topo: &Topology,
        actors: &Actors,
        id: &str,
    ) -> Option<String> {
        match self.locations.get(id)? {
            Location::Carried { actor } => actors.get(actor).map(|a| a.name.clone()),
            Location::Stored { container } => topo.prop(container).map(|p| p.name.clone()),
            Location::Ground { locale, .. } => Some(topo.locale_name(locale)),
        }
    }
    /// 放下的物品画在既有的静止锚点上；不改写历史路线。
    pub(crate) fn position(&self, topo: &Topology, id: &str) -> Option<[f64; 3]> {
        let Location::Ground { locale, station } = self.locations.get(id)? else {
            return None;
        };
        topo.point(
            locale,
            &protocol::At::Station {
                station: station.clone(),
            },
        )
    }
}

impl World {
    /// 一个人的背包：同样的物品按叠放上限分格。
    pub fn inventory_view(&self, actor: &str) -> InventoryView {
        let mut groups: BTreeMap<String, Vec<&Prop>> = BTreeMap::new();
        for p in self
            .topo
            .props()
            .iter()
            .filter(|p| !p.withdrawn && self.inventory.carried_by(&p.id, actor))
        {
            groups
                .entry(Inventory::stack_key(&self.props, p))
                .or_default()
                .push(p);
        }
        let mut slots = Vec::new();
        for items in groups.values() {
            for stack in items.chunks(Inventory::stack_limit(items[0])) {
                let p = stack[0];
                slots.push(InventorySlot {
                    actions: p
                        .verbs
                        .iter()
                        .filter_map(|v| v.action.as_ref())
                        .map(|a| crate::props::action_description_for(a, self.physiology()))
                        .collect(),
                    definition: p.definition.clone(),
                    items: stack.iter().map(|p| p.id.clone()).collect(),
                    name: p.name.clone(),
                    quantity: stack.len(),
                    readable: p.readable.as_ref().map(crate::content::Text::metadata),
                });
            }
        }
        InventoryView {
            capacity: CAPACITY,
            used: slots.len(),
            slots,
        }
    }

    /// 一组物品按叠放键分堆：身份和状态完全相同的一堆（和背包分格同一个键），堆按键排，堆里按编号排。
    /// 给村民看时一堆只列一个编号，要几件由 agent 从这一堆里挑（`stack_mates`）。
    pub fn item_stacks<'a>(&self, items: impl IntoIterator<Item = &'a Prop>) -> Vec<Vec<&'a Prop>> {
        let mut groups: BTreeMap<String, Vec<&Prop>> = BTreeMap::new();
        for p in items {
            groups
                .entry(Inventory::stack_key(&self.props, p))
                .or_default()
                .push(p);
        }
        groups
            .into_values()
            .map(|mut stack| {
                stack.sort_by(|a, b| a.id.cmp(&b.id));
                stack
            })
            .collect()
    }

    /// 和这件物品同一堆的物品编号，含它自己，按编号排：同一个人身上、同一个容器里或地上同一个
    /// 落脚点，叠放键相同。不是还在世界里的可携带物品时为空。
    pub fn stack_mates(&self, id: &str) -> Vec<String> {
        let live = |p: &&Prop| p.portable && !p.withdrawn && !self.props.is_removed(&p.id);
        let Some(item) = self.topo.prop(id).filter(live) else {
            return vec![];
        };
        // 地图自带、没挪过的物品各在自己的操作点上，只算它自己
        let place = |p: &Prop| match self.inventory.location(&p.id) {
            Some(location) => serde_json::to_string(location).unwrap_or_default(),
            None => format!("map:{}", p.id),
        };
        let (here, key) = (place(item), Inventory::stack_key(&self.props, item));
        let mut ids: Vec<_> = self
            .topo
            .props()
            .iter()
            .filter(live)
            .filter(|p| place(p) == here && Inventory::stack_key(&self.props, p) == key)
            .map(|p| p.id.clone())
            .collect();
        ids.sort();
        ids
    }

    /// 本人看得到的容器里存着的物品；够不着或进不了别人家时为空。
    pub fn container_items(&self, actor: &str, container: &str) -> Vec<StoredItem> {
        let w = self;
        let Some(p) = w.topo.prop(container).filter(|p| p.storage_slots > 0) else {
            return vec![];
        };
        let Some(a) = w.actors.get(actor) else {
            return vec![];
        };
        if !w.inventory.at_hand(&w.props, &a.id, p, &a.locus.locale)
            || check_property_access(&w.topo, a, &p.locale).is_err()
        {
            return vec![];
        }
        w.topo
            .props()
            .iter()
            .filter(|p| {
                !p.withdrawn
                    && matches!(
                        w.inventory.location(&p.id),
                        Some(Location::Stored { container: c }) if c == container
                    )
            })
            .map(|p| StoredItem {
                definition: p.definition.clone(),
                id: p.id.clone(),
                name: p.name.clone(),
            })
            .collect()
    }
}
