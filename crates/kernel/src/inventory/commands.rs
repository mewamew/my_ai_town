//! 背包结算的世界入口：转移完成后刷新修订号、可供性和空间修订号。
use crate::error::{KernelError, Result};
use crate::World;
use protocol::InventoryAction as Op;

impl World {
    /// 转移后的收尾：道具列表、可供性和空间数据都要重发。
    pub(crate) fn refresh_inventory(&mut self) {
        self.inventory.bump();
        self.affordances.rebuild(&self.topo);
        self.topo.bump_navigation_revision();
    }

    /// 背包操作的全部检查：背包规则读到的部件由这里给出，化身的可达判断也在这里接上。
    pub(crate) fn check_inventory(&self, actor: &str, op: &Op) -> Result<()> {
        let within = crate::avatar::Reach::new(self);
        // 藏着、自己还没找到的东西够不着
        let reach = |actor: &str, prop: &str| {
            ensure!(
                self.sees_prop(actor, prop),
                KernelError::inventory("眼前没有这件东西")
            );
            within.prop(actor, prop)
        };
        let cx = crate::inventory::Surroundings {
            topo: &self.topo,
            props: &self.props,
            actors: &self.actors,
            interactions: &self.interactions,
            now: self.minutes,
            reach: &reach,
        };
        self.inventory.check(&cx, actor, op)
    }

    /// 背包动作完成：再查一遍条件，再结算。
    pub(crate) fn finish_inventory(
        &mut self,
        actor: &str,
        op: &Op,
        key: &str,
    ) -> Result<Vec<String>> {
        self.check_inventory(actor, op)?;
        let a = &self.actors[actor];
        let changes = self
            .inventory
            .finish(&mut self.topo, &mut self.props, a, op, key)?;
        // 拾起来的东西不再藏着
        if let Op::PickUp { items } = op {
            for item in items {
                self.reveal(item);
            }
        }
        self.refresh_inventory();
        Ok(changes)
    }

    pub(crate) fn finish_gift(&mut self, from: &str, to: &str, items: &[String]) -> Result<()> {
        self.inventory
            .check_gift(&self.topo, &self.props, from, to, items)?;
        self.inventory.finish_gift(
            &mut self.topo,
            &mut self.props,
            &self.actors[from],
            &self.actors[to],
            items,
        )?;
        self.refresh_inventory();
        Ok(())
    }

    /// 消耗随身物品。活动回执还要读它的动作定义，索引留到活动完成后重建。
    pub(crate) fn consume_carried_prop(&mut self, id: &str) {
        self.inventory.bump();
        self.inventory.forget(id);
        self.props.withdraw(&mut self.topo, id);
        self.affordances.mark_dirty();
    }
}
