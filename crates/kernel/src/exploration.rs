//! 陌生环境与藏着的东西。
//!
//! 世界设成「村民初来乍到」（strangers）时，每人只知道到过的地方和自己的家；别处要顺着眼前的路
//! 走过去才知道。到过的地方记着上次在那里时能做的事，远处的变化看不见。没去过的路只知道往哪个方向。
//!
//! 藏着的东西：定义里 hidden 的道具放下后、或者有人「藏」起来的随身物品，到了也看不见，要「搜寻」
//! 才找得到。谁找到谁知道，当时在场醒着的人也看见；藏的时候在场醒着的人同样知道藏在哪。
//! 有人拾取后就不再藏着。熟悉的世界（默认）不限地点，藏着的东西照样要搜寻。
use crate::error::{KernelError, Result};
use crate::World;
use protocol::{ActionDraft, InventoryAction};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

/// 到过的地方在记忆里的样子：最后一次在那里的时刻，和当时那里能做的事。
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct PlaceMemory {
    pub at: f64,
    pub verbs: Vec<String>,
}

/// 村民记得的一处地方（陌生环境里的已知地图）。
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct KnownPlace {
    pub id: String,
    pub name: String,
    pub verbs: Vec<String>,
    /// 上次在那里的时刻；正在那里时为空（眼前的东西看观察）。
    pub last_seen: Option<String>,
}

/// 从眼下所在地点出去的一条路。
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Exit {
    /// 前往时 intent.locale 填它。
    pub to: String,
    /// 到过才知道叫什么。
    pub name: Option<String>,
    pub way: String,
}

/// 搜寻要多久、一次搜到的可能（百分比）；藏一样东西要多久。
pub(crate) const SEARCH_MINUTES: f64 = 20.0;
const SEARCH_FINDS: u32 = 60;
pub(crate) const HIDE_MINUTES: f64 = 2.0;

/// 方向：东为 0°，逆时针；地图上北是 z 减小的方向。
const DIRECTIONS: [&str; 8] = ["东", "东北", "北", "西北", "西", "西南", "南", "东南"];

impl World {
    /// 村民是不是初来乍到：只知道到过的地方。
    pub fn strangers(&self) -> bool {
        self.strangers
    }

    /// 打开或关掉陌生环境。打开时每人只记得眼下所在的地方（家照样知道）。
    pub fn set_strangers(&mut self, on: bool) {
        self.strangers = on;
        if !on {
            return;
        }
        for id in self.actor_ids() {
            if self.actors[&id].is_avatar() {
                continue;
            }
            self.actor_mut(&id).places_known.clear();
            if let Some(place) = self.place_now(&id) {
                self.remember_place(&id, &place);
            }
        }
    }

    /// 看不看得见这件东西：没藏着的都看得见；藏着的只有找到过、亲眼看见藏的人，和玩家操控的人看得见。
    pub fn sees_prop(&self, actor: &str, prop: &str) -> bool {
        !self.concealed.contains(prop)
            || self
                .actors
                .get(actor)
                .is_some_and(|a| a.player_controlled() || a.found.contains(prop))
    }

    /// 定义里写着藏起来的道具，放下时就藏着。
    pub(crate) fn conceal_if_hidden(&mut self, prop: &str, hidden: bool) {
        if hidden {
            self.concealed.insert(prop.into());
        }
    }

    /// 东西被人拾取：不再藏着。
    pub(crate) fn reveal(&mut self, prop: &str) {
        self.concealed.remove(prop);
    }

    /// 眼下所在的地点（路段、街道上不算）。
    fn place_now(&self, id: &str) -> Option<String> {
        let a = self.actors.get(id).filter(|a| a.present())?;
        self.enclosing_place(&a.locus.locale)
    }

    /// 这个人此刻在这个地点能做的事（看得见的道具上的动作词）；别人家里只记得名字。
    fn verbs_here(&self, id: &str, locale: &str) -> Vec<String> {
        let a = &self.actors[id];
        let others_home = self
            .topo
            .place_of(locale)
            .is_some_and(|p| p.residential && a.home.as_deref() != Some(locale));
        if others_home {
            return vec![];
        }
        let mut verbs: Vec<String> = self
            .affordances
            .options(locale)
            .iter()
            .filter(|s| self.sees_prop(id, &s.prop))
            .map(|s| s.verb.clone())
            .collect();
        verbs.dedup();
        verbs
    }

    /// 记下这个地方此刻的样子（来到、离开时）。
    pub(crate) fn remember_place(&mut self, id: &str, locale: &str) {
        if self.actors[id].is_avatar() || self.topo.place_of(locale).is_none() {
            return;
        }
        let memory = PlaceMemory {
            at: self.minutes,
            verbs: self.verbs_here(id, locale),
        };
        self.actor_mut(id)
            .places_known
            .insert(locale.into(), memory);
    }

    /// 来到一个地点：陌生环境里第一次来时记一笔，再记下这里的样子。quiet 是开局就在这里，不算「来到」。
    pub(crate) fn visit(&mut self, id: &str, locale: &str, quiet: bool) {
        if self.actors[id].is_avatar() || self.topo.place_of(locale).is_none() {
            return;
        }
        let first = !self.actors[id].places_known.contains_key(locale);
        if self.strangers && first && !quiet {
            let now = self.minutes;
            let name = self.topo.locale_name(locale);
            self.actor_mut(id).journal.record_seen(
                now,
                format!("第一次来到{name}"),
                vec![locale.into()],
            );
        }
        self.remember_place(id, locale);
    }

    /// 陌生环境里这个人记得的地方（家和眼下所在的也算），按名字排；熟悉的世界返回 None。
    pub fn known_places(&self, actor: &str) -> Option<Vec<KnownPlace>> {
        if !self.strangers {
            return None;
        }
        let a = self.actors.get(actor)?;
        let here = self.place_now(actor);
        let mut ids: BTreeSet<&str> = a.places_known.keys().map(String::as_str).collect();
        ids.extend(a.home.as_deref());
        ids.extend(here.as_deref());
        let mut list: Vec<KnownPlace> = ids
            .into_iter()
            .filter_map(|id| {
                let place = self.topo.place_of(id)?;
                let current = here.as_deref() == Some(id);
                let memory = a.places_known.get(id);
                Some(KnownPlace {
                    id: id.into(),
                    name: place.name.clone(),
                    verbs: if current {
                        self.verbs_here(actor, id)
                    } else {
                        memory.map(|m| m.verbs.clone()).unwrap_or_default()
                    },
                    last_seen: (!current)
                        .then(|| memory.map(|m| crate::clock_string(m.at)))
                        .flatten(),
                })
            })
            .collect();
        list.sort_by(|x, y| x.name.cmp(&y.name));
        Some(list)
    }

    /// 陌生环境里从眼下所在地点出去的路：通到哪个地点、往哪个方向，没去过的不写名字。
    /// 熟悉的世界、不在地点里（走在路上）时返回 None。
    pub fn exits(&self, actor: &str) -> Option<Vec<Exit>> {
        if !self.strangers {
            return None;
        }
        let a = self.actors.get(actor)?;
        let here = self.place_now(actor)?;
        let exits = self
            .neighbours(&here)
            .into_iter()
            .map(|to| {
                let known = a.places_known.contains_key(&to) || a.home.as_deref() == Some(&to);
                Exit {
                    name: known.then(|| self.topo.locale_name(&to)),
                    way: match self.direction(&here, &to) {
                        Some(d) => format!("往{d}去的路"),
                        None => "一条通往别处的路".into(),
                    },
                    to,
                }
            })
            .collect();
        Some(exits)
    }

    /// 能不能前往：熟悉的世界、玩家操控的人随便去；陌生环境里只能去记得的地方和眼前的路通到的地方。
    pub(crate) fn knows_way(&self, actor: &str, locale: &str) -> bool {
        let Some(a) = self.actors.get(actor) else {
            return false;
        };
        !self.strangers
            || a.player_controlled()
            || a.is_avatar()
            || a.places_known.contains_key(locale)
            || a.home.as_deref() == Some(locale)
            || self.place_now(actor).as_deref() == Some(locale)
            || self
                .exits(actor)
                .is_some_and(|exits| exits.iter().any(|e| e.to == locale))
    }

    /// 记不记得这个地方（陌生环境里到过的和自己的家；熟悉的世界都记得）。
    pub(crate) fn remembers(&self, actor: &str, locale: &str) -> bool {
        let Some(a) = self.actors.get(actor) else {
            return false;
        };
        !self.strangers
            || a.player_controlled()
            || a.is_avatar()
            || a.places_known.contains_key(locale)
            || a.home.as_deref() == Some(locale)
    }

    /// 不知道路时的说法。
    pub(crate) fn unknown_way() -> KernelError {
        KernelError::action(
            "你还不知道那个地方怎么去；没去过的地方要从 exits 里选一条路，走过去才知道",
        )
    }

    /// 从一个地点沿路走、不穿过别的地点就能到的地点（路段、街道照走）。
    fn neighbours(&self, from: &str) -> Vec<String> {
        let mut found = BTreeSet::new();
        let mut seen = BTreeSet::from([from.to_string()]);
        let mut queue = VecDeque::from([from.to_string()]);
        while let Some(locale) = queue.pop_front() {
            for p in &self.topo.passages {
                let next = if p.a == locale {
                    &p.b
                } else if p.b == locale {
                    &p.a
                } else {
                    continue;
                };
                if !seen.insert(next.clone()) {
                    continue;
                }
                if self.topo.place_of(next).is_some() {
                    found.insert(next.clone());
                } else {
                    queue.push_back(next.clone());
                }
            }
        }
        found.into_iter().collect()
    }

    /// 从 a 看 b 在哪个方向：用两处落脚点在空间地图上的位置；没有空间地图时为空。
    fn direction(&self, a: &str, b: &str) -> Option<&'static str> {
        let nav = self.topo.navigation.as_ref()?;
        let at = |locale: &str| {
            let station = &self.topo.place_of(locale)?.arrival_station;
            nav.stations
                .iter()
                .find(|s| &s.id == station)
                .map(|s| s.position)
        };
        let (pa, pb) = (at(a)?, at(b)?);
        let (dx, dz) = (pb[0] - pa[0], pb[2] - pa[2]);
        if dx.hypot(dz) < 1e-6 {
            return None;
        }
        let angle = (-dz).atan2(dx).to_degrees().rem_euclid(360.0);
        Some(DIRECTIONS[((angle + 22.5) / 45.0) as usize % 8])
    }

    /// 搜寻完成：这里藏着、自己还不知道的东西里，按编号先找第一件，有一定可能找到；
    /// 找到了自己和在场醒着的人都知道。返回回执里的变化。
    pub(crate) fn finish_search(&mut self, id: &str) -> Vec<String> {
        let locale = self.actors[id].locus.locale.clone();
        let place = self.topo.locale_name(&locale);
        let hidden: Vec<(String, String)> = self
            .topo
            .props()
            .iter()
            .filter(|p| {
                !p.withdrawn
                    && p.locale == locale
                    && self.inventory.on_map(&self.props, &p.id)
                    && !self.sees_prop(id, &p.id)
            })
            .map(|p| (p.id.clone(), p.name.clone()))
            .collect::<BTreeMap<_, _>>()
            .into_iter()
            .collect();
        let text = match hidden.first() {
            None => format!("仔细找遍了{place}，这里没有藏着别的东西"),
            Some(_) if !self.happenings.roll(SEARCH_FINDS) => {
                format!("在{place}找了一阵，没找到什么")
            }
            Some((prop, name)) => {
                let who = self.actors[id].name.clone();
                self.actor_mut(id).found.insert(prop.clone());
                for other in self.actor_ids() {
                    let o = &self.actors[&other];
                    if other != id && o.locus.locale == locale && self.can_notice(o) {
                        self.actor_mut(&other).found.insert(prop.clone());
                    }
                }
                self.onlookers(&locale, &[id], &format!("看见{who}找到了{name}"), false);
                let info = self.actors[id].event_info();
                self.log(info, format!("{who}在{place}找到了{name}"));
                self.remember_place(id, &locale);
                format!("在{place}找到了{name}（{prop}）")
            }
        };
        let now = self.minutes;
        self.actor_mut(id).journal.record(now, text.clone());
        vec![text]
    }

    /// 藏的条件：prop_id 填自己随身带着的一件东西，人在可以放东西的地方。
    pub(crate) fn check_hide(&self, actor: &str, draft: &ActionDraft) -> Result<()> {
        let item = draft
            .prop_id
            .as_deref()
            .ok_or_else(|| KernelError::action("藏要在 prop_id 填自己身上那件东西的 ID"))?;
        ensure!(
            draft.recipient.is_none() && draft.inventory.is_none() && draft.writing.is_none(),
            KernelError::action("藏只填 prop_id")
        );
        ensure!(
            self.inventory.carried_by(item, actor),
            KernelError::action("只能藏自己随身带着的东西")
        );
        self.check_inventory(
            actor,
            &InventoryAction::Drop {
                items: vec![item.into()],
            },
        )
    }

    /// 藏起来：放在这里并藏好，自己和在场醒着的人知道在哪。返回回执里的变化。
    pub(crate) fn finish_hide(
        &mut self,
        id: &str,
        draft: &ActionDraft,
        key: &str,
    ) -> Result<Vec<String>> {
        self.check_hide(id, draft)?;
        let item = draft.prop_id.clone().expect("check_hide 查过");
        let name = self.props.item(&self.topo, &item)?.name.clone();
        self.finish_inventory(
            id,
            &InventoryAction::Drop {
                items: vec![item.clone()],
            },
            key,
        )?;
        self.concealed.insert(item.clone());
        let locale = self.actors[id].locus.locale.clone();
        let place = self.topo.locale_name(&locale);
        let who = self.actors[id].name.clone();
        self.actor_mut(id).found.insert(item.clone());
        for other in self.actor_ids() {
            let o = &self.actors[&other];
            if other != id && o.locus.locale == locale && self.can_notice(o) {
                self.actor_mut(&other).found.insert(item.clone());
            }
        }
        self.onlookers(&locale, &[id], &format!("看见{who}把{name}藏了起来"), false);
        let info = self.actors[id].event_info();
        self.log(info, format!("{who}把{name}藏在了{place}"));
        let text = format!("把{name}藏在了{place}，别人要搜寻才找得到");
        let now = self.minutes;
        self.actor_mut(id).journal.record(now, text.clone());
        Ok(vec![text])
    }
}
