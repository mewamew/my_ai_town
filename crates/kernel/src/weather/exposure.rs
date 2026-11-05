//! 室内外判断。规则来自正式的空间与行走数据（区域、路线的室内标记，行走空间是否室外），
//! 名称、住宅身份和客户端镜头都不参与。
use crate::{
    avatar::{Point, WalkMap},
    navigation::space::Space,
    path::{route, StartPoint},
    World,
};
use protocol::{At, Exposure, IndoorAlternative};

fn indoor(flag: bool) -> Exposure {
    if flag {
        Exposure::Indoor
    } else {
        Exposure::Outdoor
    }
}

impl Space {
    /// 精确导航地图按区域和路线的室内标记判断；这张图上没有这个处所时为 None。
    fn locale_exposure(&self, locale: &str) -> Option<Exposure> {
        if let Some(f) = self.floor(locale) {
            return Some(indoor(f.indoor));
        }
        self.all_routes()
            .find(|r| r.id == locale)
            .map(|r| indoor(r.indoor))
    }
}

impl WalkMap {
    /// 处所的区域都在室外空间为室外，都在别的空间为室内；两种都有或没有区域为未知。
    fn locale_exposure(&self, locale: &str) -> Exposure {
        let mut result = None;
        for s in self.surfaces.iter().filter(|s| s.locale == locale) {
            let here = indoor(s.space != self.outdoor_space);
            if result.is_some_and(|before| before != here) {
                return Exposure::Unknown;
            }
            result = Some(here);
        }
        result.unwrap_or(Exposure::Unknown)
    }

    /// 二维地图上一个自由位置：落在区域里才算数，室外空间为室外，其他有区域的空间为室内。
    fn position_exposure(&self, space: &str, position: Point, locale: &str) -> Exposure {
        if self.locale_at(space, position, locale).is_none() {
            Exposure::Unknown
        } else if space == self.outdoor_space {
            Exposure::Outdoor
        } else if self.surfaces.iter().any(|s| s.space == space) {
            Exposure::Indoor
        } else {
            Exposure::Unknown
        }
    }
}

impl World {
    pub fn exposure_at(&self, actor: &str) -> Exposure {
        let Some(a) = self.actor(actor) else {
            return Exposure::Unknown;
        };
        // 正在遮蔽处里做事（避雨、睡觉）按室内算。
        if crate::physiology::body_spot(self, a).is_some_and(|s| self.is_shelter(&s.prop)) {
            return Exposure::Indoor;
        }
        match &a.locus.at {
            At::Offstage => Exposure::Offstage,
            At::Free {
                space, position, ..
            } => match &self.walk_map {
                None => Exposure::Unknown,
                Some(map) => map.position_exposure(space, *position, &a.locus.locale),
            },
            _ => self.locale_exposure(&a.locus.locale),
        }
    }
    pub(crate) fn is_shelter(&self, prop: &str) -> bool {
        self.topo
            .prop(prop)
            .is_some_and(|p| p.shelter && !p.withdrawn)
    }
    pub fn locale_exposure(&self, locale: &str) -> Exposure {
        self.topo
            .navigation
            .as_ref()
            .and_then(|s| s.locale_exposure(locale))
            .or_else(|| self.walk_map.as_ref().map(|m| m.locale_exposure(locale)))
            .unwrap_or(Exposure::Unknown)
    }
    pub fn indoor_alternatives(&self, actor: &str) -> Vec<IndoorAlternative> {
        let Some(a) = self.actor(actor) else {
            return vec![];
        };
        if matches!(a.locus.at, At::Offstage) {
            return vec![];
        }
        let (start, lead) = if matches!(a.locus.at, At::Free { .. }) {
            let (Ok(walk), Some(map)) = (self.free_route(actor), &self.walk_map) else {
                return vec![];
            };
            let minutes = walk.length() / map.metres_per_minute;
            (
                StartPoint::Station {
                    station: walk.station,
                },
                minutes,
            )
        } else {
            (StartPoint::at(&self.topo, &a.locus), 0.)
        };
        let mut choices: Vec<_> = self
            .topo
            .places
            .iter()
            .filter(|p| {
                self.locale_exposure(&p.locale) == Exposure::Indoor
                    && (!p.residential || a.home.as_deref() == Some(&p.locale))
                    && self.remembers(actor, &p.locale)
            })
            .filter_map(|p| {
                route(&self.topo, &start, &p.locale, None).ok().map(|r| {
                    (
                        p.residential,
                        IndoorAlternative {
                            locale: p.locale.clone(),
                            name: p.name.clone(),
                            minutes: r.total_minutes() + lead,
                        },
                    )
                })
            })
            .collect();
        choices.sort_by(|a, b| {
            a.0.cmp(&b.0)
                .then(a.1.minutes.total_cmp(&b.1.minutes))
                .then(a.1.locale.cmp(&b.1.locale))
        });
        choices.into_iter().take(6).map(|(_, p)| p).collect()
    }
}
