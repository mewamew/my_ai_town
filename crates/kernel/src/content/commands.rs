//! 作品的世界入口：玩家侧的创建、修订与撤下，以及活动里的阅读与写作接线。
use super::*;
use crate::error::{KernelError, Result};
use crate::{inventory::Location, props::Placement, World};
use protocol::{At, ContentDetail};

impl World {
    pub fn content_detail(&self, id: &str) -> Result<ContentDetail> {
        self.contents.detail(&self.topo, id)
    }

    pub fn create_content(
        &mut self,
        id: String,
        locale: String,
        title: String,
        author: String,
        text: String,
        board: Option<String>,
    ) -> Result<ContentDetail> {
        ensure!(
            id.starts_with("user:") && crate::props::identifier(&id, true),
            KernelError::content("实例编号须为有效的 user: 编号")
        );
        let content = Text {
            work_id: id.clone(),
            version: 1,
            kind: if board.is_some() {
                Kind::Bulletin
            } else {
                Kind::Book
            },
            title,
            author,
            text,
            origin: Origin::Player,
        };
        content.validate()?;
        self.place_prop(book_placement(id.clone(), locale, content, board))?;
        self.content_detail(&id)
    }

    pub fn revise_bulletin(
        &mut self,
        id: &str,
        expected_version: u32,
        title: String,
        author: String,
        text: String,
    ) -> Result<ContentDetail> {
        self.contents
            .revise_bulletin(id, expected_version, title, author, text)?;
        self.contents.restore_props(&mut self.topo)?;
        self.affordances.rebuild(&self.topo);
        self.content_detail(id)
    }

    pub fn withdraw_bulletin(&mut self, id: &str, expected_version: u32) -> Result<ContentDetail> {
        self.contents.withdraw_bulletin(id, expected_version)?;
        self.contents.restore_props(&mut self.topo)?;
        self.affordances.rebuild(&self.topo);
        self.content_detail(id)
    }

    /// 活动开始时冻结正文：阅读锁定当前版本，写作把草稿定成作品。
    pub(crate) fn prepare_content(&mut self, actor: &str) -> Result<()> {
        let pending = rules::pending_for(&self.affordances, &self.topo, &self.actors[actor])?;
        self.actor_mut(actor).current.content = pending;
        Ok(())
    }

    /// 活动完成：阅读出带正文来源的回执，写作把书放进世界。
    pub(crate) fn complete_content(
        &mut self,
        actor: &str,
    ) -> Result<Option<crate::outcome::Receipt>> {
        let Some(pending) = self.actors[actor].current.content.clone() else {
            return Ok(None);
        };
        match pending {
            Pending::Reading { prop_id, content } => Ok(Some(
                self.contents.reading_receipt(actor, &prop_id, &content),
            )),
            Pending::Writing { placement } => {
                let t = placement
                    .definition
                    .readable
                    .clone()
                    .ok_or_else(|| KernelError::content("写作草稿缺少作品"))?;
                let book = placement.instance.id.clone();
                let place = self.topo.locale_name(&placement.instance.locale);
                let beside_writer = self.shelve_book(actor, *placement)?;
                Ok(Some(crate::outcome::Receipt {
                    text: crate::outcome::finished_writing(
                        &t.author,
                        &t.title,
                        &book,
                        &place,
                        beside_writer,
                    ),
                    readable: None,
                }))
            }
        }
    }

    /// 写好的书放进世界：先在当地找空位摆上；地上摆不下了（家具和通道占满），就像放下随身物品
    /// 那样放在作者站着的落脚点上——不占新的地面、不铺新的通道，谁来都能读，也能拿走。
    /// 不然两个小时白写，书也没了，村民只会一遍遍重写。返回书是否放在了作者身边。
    /// 两种放法都推进背包修订号，host 据此重发道具列表，页面上马上看得到这本书。
    fn shelve_book(&mut self, actor: &str, placement: Placement) -> Result<bool> {
        let no_room = match self.place_prop(placement.clone()) {
            Ok(()) => {
                self.inventory.bump();
                return Ok(false);
            }
            Err(e @ KernelError::Navigation(_)) => e,
            Err(e) => return Err(e),
        };
        let locale = placement.instance.locale.clone();
        let station = match &self.actors[actor].locus.at {
            At::Station { station } if self.topo.station_in(station, &locale) => station.clone(),
            _ => return Err(no_room),
        };
        crate::props::check_room(self.topo.props().len(), 1)?;
        let prop = self.props.validate_placement(&self.topo, &placement)?;
        let id = prop.id.clone();
        self.contents.capture(&prop);
        self.props.insert(&mut self.topo, placement, prop);
        self.inventory.set_location(
            &mut self.topo,
            &mut self.props,
            &id,
            Location::Ground { locale, station },
        );
        self.refresh_inventory();
        Ok(true)
    }

    pub(crate) fn record_completed_reading(&mut self, actor: &str, event_id: u64) {
        if let Some(pending) = self.actors[actor].current.content.clone() {
            let now = self.minutes;
            self.contents.record_reading(actor, event_id, &pending, now);
        }
    }
}
